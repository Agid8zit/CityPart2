local SocialMediaService = {}
SocialMediaService.__index = SocialMediaService

---------------------------------------------------------------------
-- Services & wiring
---------------------------------------------------------------------
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService          = game:GetService("RunService")
local Workspace           = game:GetService("Workspace")

-- Localization loader + language folders (robust WaitForChild pathing)
local LocalizationFolder = ReplicatedStorage:WaitForChild("Localization")
local LocalizationLoader = require(LocalizationFolder:WaitForChild("Localizing"))
local LanguagesFolder    = LocalizationFolder:WaitForChild("Languages")

-- Events root
local EventsFolder = ReplicatedStorage:FindFirstChild("Events") or Instance.new("Folder")
EventsFolder.Name = "Events"
EventsFolder.Parent = ReplicatedStorage

local BindableEvents = EventsFolder:FindFirstChild("BindableEvents") or Instance.new("Folder")
BindableEvents.Name = "BindableEvents"
BindableEvents.Parent = EventsFolder

local RemoteEvents = EventsFolder:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = EventsFolder

-- GUI feed (client should listen to this to append a post to the “social feed”)
local RE_SocialMediaAddPost = RemoteEvents:FindFirstChild("SocialMediaAddPost")
if not RE_SocialMediaAddPost then
	RE_SocialMediaAddPost = Instance.new("RemoteEvent")
	RE_SocialMediaAddPost.Name = "SocialMediaAddPost"
	RE_SocialMediaAddPost.Parent = RemoteEvents
end

-- Text bubble updater (you already use this in your TextDialog script)
local UpdateTextDialog         = BindableEvents:WaitForChild("UpdateTextDialog")
local RequestRandomBubbleLine  = BindableEvents:FindFirstChild("RequestRandomBubbleLine") -- optional; guarded below

---------------------------------------------------------------------
-- Anti-spam wrapper for SocialMediaAddPost (RemoteEvent)
-- Token-bucket rate limiter with per-player + global limits, queueing,
-- dedup within a short window, and paced flushing.
---------------------------------------------------------------------
local FEED_LIMITS = {
	ENABLED               = true,   -- flip to false to bypass limiter entirely
	PER_PLAYER_PER_SEC    = 4,      -- steady rate per player
	PER_PLAYER_BURST      = 8,      -- burst capacity per player
	PER_PLAYER_PER_MIN    = 60,     -- hard cap per player per minute
	GLOBAL_PER_SEC        = 120,    -- steady global rate (all players combined)
	GLOBAL_BURST          = 240,    -- global burst capacity
	FLUSH_INTERVAL        = 0.20,   -- seconds between flush ticks per player
	QUEUE_MAX             = 80,     -- max enqueued posts per player (oldest dropped)
	DEDUP_WINDOW          = 6,      -- seconds: identical (text+key) within this window is skipped
	LOG                   = false,  -- verbose logging for diagnostics
}

local FeedLimiter = {}
FeedLimiter.__index = FeedLimiter
FeedLimiter._states = {} -- [userId] = { tokens, last, queue, recent, perMinute, windowStart, worker }
FeedLimiter._global = { tokens = FEED_LIMITS.GLOBAL_BURST, last = time() }

local function _refill(state, rate, cap, now)
	local last = state.last or now
	local dt = now - last
	if dt > 0 then
		state.tokens = math.min(cap, (state.tokens or cap) + dt * rate)
		state.last = now
	end
end

function FeedLimiter:_getState(player)
	local uid = player.UserId
	local st = self._states[uid]
	if not st then
		st = {
			tokens      = FEED_LIMITS.PER_PLAYER_BURST,
			last        = time(),
			queue       = {},
			recent      = {}, -- [dedupKey] = lastTimestamp
			perMinute   = 0,
			windowStart = time(),
			worker      = false,
		}
		self._states[uid] = st
	end
	return st
end

function FeedLimiter:_slideMinuteWindow(st, now)
	if not st.windowStart or (now - st.windowStart) >= 60 then
		st.windowStart = now
		st.perMinute = 0
	end
end

function FeedLimiter:_canSendNow(st, now)
	_refill(st, self.perPlayerRate or FEED_LIMITS.PER_PLAYER_PER_SEC, FEED_LIMITS.PER_PLAYER_BURST, now)
	_refill(self._global, FEED_LIMITS.GLOBAL_PER_SEC, FEED_LIMITS.GLOBAL_BURST, now)
	return st.tokens >= 1 and self._global.tokens >= 1
end

function FeedLimiter:_flushOnce(player, st)
	local now = time()
	local sent = 0

	-- maximum we allow this tick, based on steady rate and interval
	local maxThisTick = math.max(1, math.floor(FEED_LIMITS.PER_PLAYER_PER_SEC * FEED_LIMITS.FLUSH_INTERVAL))

	while #st.queue > 0 and sent < maxThisTick do
		_refill(st, FEED_LIMITS.PER_PLAYER_PER_SEC, FEED_LIMITS.PER_PLAYER_BURST, now)
		_refill(self._global, FEED_LIMITS.GLOBAL_PER_SEC, FEED_LIMITS.GLOBAL_BURST, now)

		if st.tokens < 1 or self._global.tokens < 1 then
			break
		end

		local payload = table.remove(st.queue, 1)

		-- minute cap
		self:_slideMinuteWindow(st, now)
		if st.perMinute >= FEED_LIMITS.PER_PLAYER_PER_MIN then
			-- put it back and wait for the next minute window
			table.insert(st.queue, 1, payload)
			if FEED_LIMITS.LOG then
				warn(("[FeedLimiter] minute cap reached for %s; delaying posts"):format(player.Name))
			end
			break
		end

		st.tokens -= 1
		self._global.tokens -= 1
		st.perMinute += 1

		local ok, err = pcall(function()
			RE_SocialMediaAddPost:FireClient(player, payload)
		end)
		if not ok and FEED_LIMITS.LOG then
			warn("[FeedLimiter] FireClient failed:", err)
		end

		sent += 1
	end

	return sent
end

function FeedLimiter:_ensureWorker(player, st)
	if st.worker then return end
	st.worker = true

	task.spawn(function()
		while st.worker do
			if not player.Parent then break end
			local sent = self:_flushOnce(player, st)
			if #st.queue == 0 then
				st.worker = false
				break
			end
			if sent == 0 then
				task.wait(FEED_LIMITS.FLUSH_INTERVAL)
			else
				-- small yield between bursts to keep frame pacing smooth
				RunService.Heartbeat:Wait()
			end
		end
	end)
end

function FeedLimiter:Enqueue(player, payload)
	local function pruneRecent(st, now)
		-- prune at most 16 keys per call to amortize cost
		local pruned = 0
		for k, t0 in pairs(st.recent) do
			if (now - t0) > FEED_LIMITS.DEDUP_WINDOW then
				st.recent[k] = nil
				pruned += 1
				if pruned >= 16 then break end
			end
		end
	end
	-- ----------------------------------------------------------------------

	if not FEED_LIMITS.ENABLED then
		-- passthrough mode
		local ok, err = pcall(function()
			RE_SocialMediaAddPost:FireClient(player, payload)
		end)
		if not ok and FEED_LIMITS.LOG then warn("[FeedLimiter] passthrough FireClient failed:", err) end
		return
	end

	if not player or not player.Parent then return end

	local st = self:_getState(player)

	-- Deduplicate identical text + langKey within a short window
	local dedupKey = tostring(payload.langKey or "") .. "\n" .. tostring(payload.text or "")
	local now = time()

	-- NEW: prune once per enqueue (cheap)
	pruneRecent(st, now)

	local last = st.recent[dedupKey]
	if last and (now - last) <= FEED_LIMITS.DEDUP_WINDOW then
		if FEED_LIMITS.LOG then
			print("[FeedLimiter] Drop duplicate within window for", player.Name, payload.langKey)
		end
		return
	end
	st.recent[dedupKey] = now

	-- Queue with cap (drop oldest to prefer fresher posts)
	if #st.queue >= FEED_LIMITS.QUEUE_MAX then
		table.remove(st.queue, 1)
	end
	table.insert(st.queue, payload)

	self:_ensureWorker(player, st)
end

function FeedLimiter:Clear(player)
	if not player then return end
	local st = self._states[player.UserId]
	if st then
		st.worker = false
		self._states[player.UserId] = nil
	end
end

Players.PlayerRemoving:Connect(function(plr)
	FeedLimiter:Clear(plr)
end)

---------------------------------------------------------------------
-- Localization helpers
---------------------------------------------------------------------
local function sanitizeLanguage(language: string): string
	if LocalizationLoader.isValidLanguage and LocalizationLoader.isValidLanguage(language) then
		return language
	end
	return "English"
end

local function requireLanguageModule(language: string): table?
	local ok, mod = pcall(function()
		return require(LanguagesFolder:WaitForChild(language))
	end)
	return ok and mod or nil
end

local function isPlaceholder(v: any): boolean
	return v == nil or v == "" or v == "..."
end

local function getOrAssignCivDialect(model: Model, langMod: table, entry: any): string?
	if not (model and model.Parent and type(langMod)=="table" and type(entry)=="table") then
		return nil
	end

	-- Reuse if already chosen AND still valid (exists + non-empty in this key entry)
	local existing = model:GetAttribute("CivDialect")
	if type(existing)=="string" and existing ~= "" then
		local v = entry[existing]
		if type(v)=="string" and v~="" and v~="..." then
			return existing
		end
		-- else: drop invalid/empty and re-pick
		model:SetAttribute("CivDialect", nil)
	end

	-- Build candidate dialect keys (exclude _default; require non-empty)
	local candidates = {}
	for k, v in pairs(entry) do
		if k ~= "_default" and type(v)=="string" and v~="" and v~="..." then
			table.insert(candidates, k)
		end
	end
	if #candidates == 0 then return nil end

	local chosen = candidates[math.random(1, #candidates)]
	model:SetAttribute("CivDialect", chosen)
	return chosen
end

-- Random dialect inside the chosen language (player does NOT pick dialect).
-- If no dialect string is available for that key, fall back smartly.
local function localizeRandomDialectFor(player: Player, englishKey: string, model: Model?): string
	-- Toggle this if you want to see what each civ speaks
	local DEBUG_DIALECT_LOG = false -- quieter by default; set true to inspect

	local function log(fmt: string, ...)
		if DEBUG_DIALECT_LOG then
			print(("[CivDialect] " .. fmt):format(...))
		end
	end

	local language = sanitizeLanguage(player:GetAttribute("Language") or "English")
	local langMod  = requireLanguageModule(language)
	if type(langMod) ~= "table" then
		log("%s lang module missing; falling back to English key | key='%s'", language, tostring(englishKey))
		return englishKey
	end

	local entry = langMod[englishKey]

	-- Helper to check if a value is a placeholder/blank
	local function validStr(v: any): boolean
		return (type(v) == "string") and (v ~= "") and (v ~= "...")
	end

	----------------------------------------------------------------
	-- 1) MODEL-SCOPED consistency: stick to this civ's dialect
	----------------------------------------------------------------
	if model and type(entry) == "table" then
		local dialectKey = getOrAssignCivDialect(model, langMod, entry)
		if type(dialectKey) == "string" and dialectKey ~= "" then
			local v = entry[dialectKey]
			if validStr(v) then
				log("%s speaks '%s' (%s) | key='%s'", model.Name, dialectKey, language, englishKey)
				return v
			else
				-- Invalidate bad/now-missing dialect and let the flow re-pick below
				model:SetAttribute("CivDialect", nil)
				log("%s had invalid dialect '%s' for key='%s' (%s) — re-picking",
					model.Name, tostring(dialectKey), englishKey, language)
			end
		end
	end

	----------------------------------------------------------------
	-- 2) RANDOM dialect (no model or no valid persisted dialect)
	----------------------------------------------------------------
	if type(entry) == "table" then
		-- Build random dialect pool (exclude _default, require non-empty)
		local poolKeys = {}
		for k, v in pairs(entry) do
			if k ~= "_default" and validStr(v) then
				table.insert(poolKeys, k)
			end
		end

		if #poolKeys > 0 then
			local chosenKey = poolKeys[math.random(1, #poolKeys)]
			local chosenVal = entry[chosenKey]
			log("%s speaks RANDOM '%s' (%s) | key='%s'",
				model and model.Name or "<no-model>", chosenKey, language, englishKey)
			-- If we have a model, remember this choice for future lines
			if model then model:SetAttribute("CivDialect", chosenKey) end
			return chosenVal
		end

		-- 2a) Language default dialect (e.g., mandarin) → _default
		local dd = langMod.__default_dialect
		if type(dd) == "string" and validStr(entry[dd]) then
			log("%s uses default dialect '%s' (%s) | key='%s'",
				model and model.Name or "<no-model>", dd, language, englishKey)
			if model then model:SetAttribute("CivDialect", dd) end
			return entry[dd]
		end

		if validStr(entry["_default"]) then
			log("%s uses _default (%s) | key='%s'",
				model and model.Name or "<no-model>", language, englishKey)
			return entry["_default"]
		end
	end

	----------------------------------------------------------------
	-- 3) Last resort: Loader (language-only), then English key
	----------------------------------------------------------------
	local s = LocalizationLoader.get and LocalizationLoader.get(englishKey, language) or nil
	if validStr(s) then
		log("%s uses Loader fallback (%s) | key='%s'",
			model and model.Name or "<no-model>", language, englishKey)
		return s
	end

	log("%s uses ENGLISH KEY fallback | key='%s'", model and model.Name or "<no-model>", englishKey)
	return englishKey
end

---------------------------------------------------------------------
-- Optional localization source
-- Expect a module returning a table: Localize[EnglishKey] = { _default="", DIALECT1="", ... }
-- If not found, we still work (we will output the EnglishKey).
---------------------------------------------------------------------
local Localize
do
	local ok, mod = pcall(function()
		-- Adjust if you keep a different path; this is a sensible default
		local Scripts = ReplicatedStorage:WaitForChild("Localization")
		local LocRoot = Scripts:FindFirstChild("Languages") or Scripts
		return require(LocRoot:WaitForChild("English"))
	end)
	Localize = ok and mod or {}
end

---------------------------------------------------------------------
-- Civ discovery helpers (mirrors your TextDialog script’s logic)
---------------------------------------------------------------------
local function isCiv(model: Instance): boolean
	return model
		and model:IsA("Model")
		and model:GetAttribute("CivAlive") == true
		and (model:GetAttribute("OwnerUserId") ~= nil)
end

local function getPlayerPlot(player: Player): Instance?
	local plots = Workspace:FindFirstChild("PlayerPlots")
	if not plots then return nil end
	return plots:FindFirstChild("Plot_" .. player.UserId)
end

local function pickRandomCivOnPlot(plot: Instance): Model?
	if not plot then return nil end
	local pool = {}
	for _, d in ipairs(plot:GetDescendants()) do
		if d:IsA("Model") and isCiv(d) then
			table.insert(pool, d)
		end
	end
	if #pool == 0 then return nil end
	return pool[math.random(1, #pool)]
end

local function findCivByNameAllPlots(name: string): Model?
	local pp = Workspace:FindFirstChild("PlayerPlots")
	if not pp or not name or name == "" then return nil end
	for _, plot in ipairs(pp:GetChildren()) do
		for _, inst in ipairs(plot:GetDescendants()) do
			if inst:IsA("Model") and inst.Name == name and isCiv(inst) then
				return inst
			end
		end
	end
	return nil
end

---------------------------------------------------------------------

---------------------------------------------------------------------
-- Curated English keys by Category/Sentiment
-- NOTE: these are the MAIN KEYS from your English table.
-- You can expand/trim at will; the system will still run.
---------------------------------------------------------------------
local KEYS = {
	-- ===== Free-form chatter category (only 'lines' bucket kept, as requested) =====
	Random = {
		lines = {
			"Was there always a road there? I like it.",
			"Did you know there are more planes in the ocean than submarines in the sky?",
			"I like the new coffee shop downtown.",
			"Everyone has the right to be stupid, it's just some people abuse the privilege.",
			"My friend said that the old factory has a really cool abandoned tunnel in it. I don't think I'll find out for myself.",
			"I dont think inside the box or outside the box... I dont even know where the box is...",
			"I think I might paint my house blue. I like blue.",
			"Things just aren’t what they used to be. And probably never were.",
			"I’ve always wanted to be somebody, but I see now I should’ve been more specific.",
			"The early bird can have the worm, because worms are gross and mornings are stupid.",
			"I love the new trees they planted in my neighborhood.",
			"Be yourself. No one can ever tell you’re doing it wrong.",
			"My favorite childhood memory, is not paying bills.",
			"Did you know that birds control time? They do this out of spite.",
			"If someone makes you happy, make them happier.",
			"I like bananas because they have no bones.",
			"A raccoon ate through my trashcan yesterday. It was a really cute raccoon, so I'm not really mad about it.",
			"Forever is a long time. But not as long as it was yesterday.",
			"I've heard they're getting rid of Ohio. It's for the best, really.",
			"Have you seen Marvin? He owes me money.",
			"Do you think my cat knows about the feminist movement?",
			"Norbert has a face you’d want to punch. Not because there is anything wrong with the face itself, but just because it's his and he is mean.",
			"Refusing to have an opinion, is a way of having one, isn’t it?",
			"My name is Len, short for Lenjamin.",
			"Do you think if we get enough of us together, we could overthrow the gigantic person that runs our city?",
			"I cannot become what I need to be, by remaining what I am.",
			"It’s ok that you’re not who you thought you’d be.",
			"If you feel like everyone else hates you, you need sleep. If you feel like you hate everyone else, you need to eat.",
			"Do you think whoever runs this city knows what a penguin looks like? I don't, and I am really curious.",
			"I think ultimately you become whoever would have saved you that time that no one did.",
			"I learn something everyday. And a lot of times, it’s that what I learned yesterday, was wrong.",
			"I know that when the world falls apart, raccoons will never judge me. They will only haunt my waking nightmares with their tiny, tiny hands.",
			"I've got to be careful going in search of adventure. It’s ridiculously easy to find.",
			"Latest news: A new type of deodorant has been invented! It does exactly the same thing as the old ones.",
			"If god isn't real then why does the palm of a man fit so perfectly against the throat of a goose?",
		},
	},

	Police = {
		need = {
			"Every night it’s sirens and shouting. Where are the police?",
			"Break-ins everywhere. We need a police station closer than the next city over.",
			"Feels like crime’s the only thing booming in this neighborhood.",
			"Every shop’s installing bars on the windows. Maybe build a precinct instead?",
			"Someone stole my bike again. At this point I should just rent it to them.",
		},
		praise = {
			"Finally, a police precinct opened nearby. Streets already feel calmer.",
			"Just saw officers patrolling downtown. Feels safer than it’s been in years.",
			"Crime dropped fast once the new Police Dept went up. Great work, city!",
			"Courthouse finally opened! Justice might actually happen now!",
			"Seeing blue lights used to mean trouble. Now it means peace of mind.",
		},
		funding = {
			"Police doing their best, but there’s only so many of them. Fund the department!",
			"Response times are slow. Maybe the precinct needs more vehicles.",
			"Wouldn’t mind a few more patrols in the alley behind my store.",
			"The courthouse backlog is wild! Cases from last year still waiting.",
			"If they had better funding, maybe the cops could stop using scooters.",
		},
		flavor = {
			"The new precinct’s coffee is apparently better than the café’s.",
			"Finally got my wallet back from lost-and-found. Didn’t expect that level of service!",
			"Saw an officer petting a stray dog on patrol. City’s really turning around.",
			"Funny how crime drops when people realize there’s actually a police station now.",
		}
	},

	Fire = {
		need = {
			"A single spark out here and the whole block’s gone. Where are the firefighters?",
			"My neighbor’s grill caught fire and we had to use buckets. That can’t be normal city life.",
			"No fire station for miles...guess we’re all volunteers now.",
			"Every time I smell smoke, I start packing. We need a fire dept.",
		},
		praise = {
			"Finally, the new Fire Dept opened nearby. Feels good knowing someone’s watching the flames.",
			"The new Fire Station looks incredible. Hope I never need it, but I’m glad it’s there.",
			"Heard sirens this morning! Quick response, city’s improving!",
			"Firefighters saved the bakery! Free muffins for heroes.",
			"Finally, hydrants with pressure. My water hose isn’t the first line of defense anymore.",
		},
		funding = {
			"Fire Dept’s underfunded. They’re still driving 20-year-old trucks!",
			"More firefighters, less fireworks! Give them proper funding!",
			"Response times are slow lately. Maybe they need more stations!",
			"If the Fire Precinct had more funding, maybe insurance wouldn’t be this high.",
			"Firefighters are doing their best, but the city’s growing faster than their budget.",
		},
		flavor = {
			"Someone left their toast on again. I heard the sirens before the smoke alarm.",
			"If the Fire Station had a café, I’d stop by just to say thanks.",
			"Shoutout to the Fire Dept! They’re faster than my internet.",
		}
	},

	Health = {
		need = {
			"Got sick again and there’s still no clinic in this district.",
			"The nearest hospital is two bus rides away. Hope I survive the trip.",
			"Can’t even get an appointment. We need more doctors, not more paperwork.",
			"Small Clinic is closed again. Guess I’ll just tough it out.",
			"No emergency care nearby. If you get hurt here, good luck.",
		},
		praise = {
			"The new City Hospital looks amazing! Finally, real healthcare in town.",
			"Finally, a Local Hospital nearby. No more traveling halfway across the city for a checkup.",
			"Got treated at the Small Clinic today! Fast, clean, and professional. Kudos to the staff!",
			"The Major Hospital opened and it’s already saving lives. Great job, city!",
			"Feeling safer just knowing there’s a functioning hospital nearby.",
		},
		funding = {
			"Doctors are overworked and patients keep piling in! Build another hospital!",
			"Clinic’s great, but they could use more nurses. Everyone’s exhausted.",
			"The ER waiting room looks like a concert lineup. Fund the health system already!",
			"Healthcare’s stretched too thin! Patients in hallways again.",
			"If the City Hospital got better funding, maybe we wouldn’t have two-hour ambulance waits.",
		},
		flavor = {
			"Big thanks to the clinic nurse who still smiles after twelve-hour shifts.",
			"Someone coughed on the bus and ten people panicked. We really need better hospitals.",
			"They opened a Major Hospital and the pharmacy lines doubled overnight. Progress?",
			"My kid said the clinic lollipops taste like medicine. Honestly, same.",
			"Doctors and firefighters should get statues before politicians do.",
		}
	},

	Education = {
		need = {
			"Our kids deserve real classrooms, not overflow in hallways. Build more schools!",
			"Buses are shipping students across town again. We need a local school now.",
			"Textbooks are older than the dionsaurs in them. Can we fund education like we mean it?",
			"Smaller class sizes would fix half our problems. Build one more school, please.",
		},
		praise = {
			"Proud day for the city! Our kids finally have places to learn close to home.",
			"The new Middle School looks amazing! Our kids won’t have to commute forever anymore.",
			"Clubs, sports, and science fairs? Middle School is finally a real hub for families.",
			"Heard the Middle School library got new computers. That’s how you build futures.",
			"Private School opened its doors and suddenly uniforms are in fashion.",
			"Museum’s finally open! Weekend plans solved!",
			"Local News Station is live finally! City updates that aren’t rumors.",
		},
		funding = {
			"Middle School is packed already. Guess we should’ve built two.",
			"Drop-off lane at Middle School is chaos. Great school! Now fix the traffic plan!",
			"Private School scholarships would go a long way! Talent shouldn’t depend on wallets.",
			"More late-night hours at the Museum, please some of us work days!",
		}
	},

	Leisure = {
		need = {
			"This city needs more places to unwind before we all burn out.",
			"Weekends feel better when there’s somewhere calm to go and clear your head.",
			"Public spaces pay for themselves in community spirit. Build more, argue less.",
		},
		praise = {
			"Hotel just opened downtown! Tourists incoming and local shops smiling already.",
			"The new movie theater revived date night. Popcorn economy booming!",
			"Museum’s finally open! Weekend plans solved!",
		},
		flavor = {
			"Love the theater, but staggering showtimes could ease the parking crunch by a lot.",
			"If the Hotel improves transit shuttles, guests won’t flood the streets with taxis. Win-win.",
		}
	},

	Transportation = {
		BusDepot = {
			need = {
				"Still no Bus Depot in this district; half the routes end in the middle of nowhere.",
				"No depot means buses break down on the street. Maybe build one before the fleet collapses?",
				"Waiting for a bus that never comes. This neighborhood needs proper service.",
			},
			praise = {
				"The new Bus Depot changed everything. Buses actually arrive on time now!",
				"Depot is open, routes are smooth, and commuting finally feels civilized.",
				"Seeing freshly cleaned buses every morning gives me more faith in the city than most speeches do.",
			},
			upgrade = {
				"Bus Depot is working overtime. Time to expand before rush hour destroys it.",
				"We need more electric buses. The depot could lead the way in going green.",
				"Depot is too small for a growing city. Fund upgrades before delays return.",
				"Drivers deserve better facilities too. Fund the depot break rooms and workshops.",
			}
		},
		Airport = {
			need = {
				"No Airport means we are cut off from the world. Businesses and tourism are stuck on the ground.",
				"We have skyscrapers but no Airport. How do people even visit this place?",
				"Driving to another city just to fly is ridiculous. Build an Airport already!",
			},
			praise = {
				"Finally, flights are running and the Airport looks incredible.",
				"Airport security is smooth, shops are open, and it actually feels world class.",
				"Seeing planes overhead again feels like the city is truly connected to the world.",
				"The Airport has boosted local hotels and restaurants overnight. Smart investment!",
			},
			upgrade = {
				"Airport is great, but we need a second terminal before travelers start camping on the floor.",
				"Customs lines are brutal. Time for more staff and faster systems.",
				"Airport expansion would mean new routes, new jobs, and fewer layovers. Let's do it.",
				"The cargo side of the Airport could use more funding too. Exports keep the city running.",
			}
		},
		Metro = {
			need = {
				"We need a Metro system already. The buses can only do so much.",
				"Traffic is a nightmare. Please, just build a Metro before I lose my mind.",
				"A Metro would connect the city like nothing else. No more two-hour commutes.",
			},
			praise = {
				"The Metro opened this week and it already feels like the city leveled up.",
				"Fast, clean, quiet. I cannot believe I am saying this about public transport.",
				"Took the Metro today and got to work early for the first time in years.",
				"Finally, a Metro that makes us feel like a real city. Worth every tax dollar.",
			}
		}
	},

	Sports = {
		ArcheryRange = {
			need = {
				"Would love an Archery Range out here. Beats staring at empty lots all weekend.",
			},
			praise = {
				"Archery Range is finally open. Calm, quiet, and precise. Best stress relief in the city.",
				"Archery Range is way better than another mall. Focus over shopping any day.",
			}
		},
		BasketballCourt = {
			need = {
				"Wish we had a Basketball Court nearby. It would keep the kids busy and happy.",
			},
			praise = {
				"The Basketball Court is packed every afternoon. Easily the best community spot around.",
				"Basketball Court beats any gym membership. Free, fun, and friendly.",
			}
		},
		BasketballStadium = {
			need = {
				"We need a real Basketball Stadium so the team stops borrowing arenas.",
			},
			praise = {
				"Basketball Stadium days are the loudest, happiest days this city gets.",
				"The new Basketball Stadium is incredible. Feels like a major city now.",
			}
		},
		FootballStadium = {
			need = {
				"Still waiting on a Football Stadium here. Everyone keeps driving to the next city.",
			},
			praise = {
				"Football Stadium crowds are massive. Local economy is loving game days.",
				"The new Football Stadium puts our city on the map.",
			}
		},
		GolfCourse = {
			need = {
				"A Golf Course would look great here. Better than another office park.",
			},
			praise = {
				"Golf Course opened this week. Finally a reason for business meetings outdoors.",
				"Golf Course greens make this part of town look alive. Best landscaping in the city.",
			}
		},
		PublicPool = {
			need = {
				"We could use a Public Pool. The kids are melting out here.",
			},
			praise = {
				"Public Pool is open and the whole neighborhood showed up. Best summer in years.",
				"The Public Pool beats every private gym. Cheap, clean, and fun.",
			}
		},
		SkatePark = {
			need = {
				"Still no Skate Park here. Guess the stairs will have to do.",
			},
			praise = {
				"The Skate Park finally opened. Now we can stop getting yelled at downtown.",
				"Skate Park brings life to this area. Better than another parking lot any day.",
			}
		},
		SoccerStadium = {
			need = {
				"Still no Soccer Stadium. Players keep practicing on empty fields.",
			},
			praise = {
				"Soccer Stadium is packed and electric. Nothing beats game day energy.",
				"Our Soccer Stadium puts the whole city in a good mood.",
			}
		},
		TennisCourt = {
			need = {
				"Still no Tennis Court nearby. Guess we will keep using the parking lot lines.",
			},
			praise = {
				"The Tennis Court is spotless and full every morning. Great addition to the neighborhood.",
				"The Tennis Court looks great next to the park. Makes the area feel upscale.",
			}
		},
	},

	-- Utilities (No Power / No Water) if you want to post about networks
	Utilities = {
		Power = {
			need = {
				"A blackout again? I can't even call or email the electrical company when there's no power :(",
				"Help, my TV doesn't work when there's no power!",
				"Power to the people! How hard is it to build a working power grid? It’s not exactly state of the art technology.",
			}
		},
		Water = {
			need = {
				"Hey, guys, is the water supposed to be brown and crunchy?",
				"Don't I pay my taxes for services like water??? This is absurd!",
				"I would think that fresh water is basic stuff, but NO! How long do we have to wait for working water pipes!?",
			}
		}
	}
}

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function pickRandom(list)
	if not list or #list == 0 then return nil end
	return list[math.random(1, #list)]
end

local function postToGui(player: Player, text: string, meta: table?, englishKeyOrNil: string?)
	local payload = {
		text      = text,
		category  = meta and meta.category or nil,
		sentiment = meta and meta.sentiment or nil,
		zoneId    = meta and meta.zoneId or nil,
		timestamp = os.time(),
		langKey   = englishKeyOrNil,  -- <-- included for client-side traceability/dedupe
	}
	-- *** IMPORTANT: route via limiter instead of firing directly ***
	FeedLimiter:Enqueue(player, payload)
end

-- Resolve the TextLabel under a TextDialog part and stamp LangKey on it.
local function setLangKeyOnLabelFromRoot(root: Instance, englishKey: string)
	if not (englishKey and englishKey ~= "") then return end
	local function try()
		if root and root:IsA("BasePart") and root.Name == "TextDialog" then
			local att = root:FindFirstChild("Attachment")
			local bb  = att and att:FindFirstChild("BillboardGui")
			local mf  = bb and bb:FindFirstChild("MainFrame")
			local tl  = mf and mf:FindFirstChildWhichIsA("TextLabel")
			if tl then
				tl:SetAttribute("LangKey", englishKey)
				return true
			end
		end
		return false
	end
	if not try() then
		-- Label may appear a tick later (clone/layout); retry once asynchronously
		task.defer(try)
	end
end

local function setLangKeyOnDialog(model: Model, englishKey: string)
	if not (model and model.Parent and englishKey and englishKey ~= "") then return end
	local dlg = model:FindFirstChild("TextDialog")
	if dlg and dlg:IsA("BasePart") then
		setLangKeyOnLabelFromRoot(dlg, englishKey)
	else
		task.defer(function()
			local d = model:FindFirstChild("TextDialog")
			if d and d:IsA("BasePart") then
				setLangKeyOnLabelFromRoot(d, englishKey)
			end
		end)
	end
end

local function pickAnyEnglishKeyPreferRandom()
	-- Prefer Random.lines
	local rl = KEYS.Random and KEYS.Random.lines
	if rl and #rl > 0 then
		return rl[math.random(1, #rl)]
	end

	-- Otherwise, build a one-time pool from all families with content
	local pool = {}

	local function addTableOfStrings(t)
		for _, v in pairs(t) do
			if type(v) == "string" then table.insert(pool, v)
			elseif type(v) == "table" then addTableOfStrings(v) end
		end
	end

	addTableOfStrings(KEYS)
	if #pool == 0 then return nil end
	return pool[math.random(1, #pool)]
end

local function postToBubble(player: Player, text: string, targetOrName: any, englishKeyOrNil: string?)
	-- If a Model instance is provided, use it directly (fast path)
	if typeof(targetOrName) == "Instance" and targetOrName:IsA("Model") then
		local model = targetOrName
		UpdateTextDialog:Fire(model, text)
		if englishKeyOrNil then setLangKeyOnDialog(model, englishKeyOrNil) end
		return
	end

	-- If a name string was provided, try to resolve the model
	if typeof(targetOrName) == "string" and targetOrName ~= "" then
		local model = findCivByNameAllPlots(targetOrName)
		if model then
			UpdateTextDialog:Fire(model, text)
			if englishKeyOrNil then setLangKeyOnDialog(model, englishKeyOrNil) end
			return
		end
		-- fallback: let the renderer resolve the string target
		UpdateTextDialog:Fire(targetOrName, text)
		return
	end

	-- Otherwise, pick a random civ on the player's plot
	local plot = getPlayerPlot(player)
	local civ  = pickRandomCivOnPlot(plot)
	if civ then
		UpdateTextDialog:Fire(civ, text)
		if englishKeyOrNil then setLangKeyOnDialog(civ, englishKeyOrNil) end
	end
end

---------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------

-- Post a specific English key (exact key in your table)
function SocialMediaService.postKey(player: Player, englishKey: string, opts: table?)
	if not player or not englishKey or englishKey == "" then return end

	-- Try to resolve a specific civ model if this post is from a named/targeted speaker
	local speakerModel: Model? = nil
	if opts and type(opts.targetName)=="string" and opts.targetName ~= "" then
		speakerModel = findCivByNameAllPlots(opts.targetName)
	end

	local text = localizeRandomDialectFor(player, englishKey, speakerModel)
	local meta = { category = "Direct", sentiment = "Key" }
	postToGui(player, text, meta, englishKey)
	postToBubble(player, text, opts and opts.targetName or speakerModel or nil, englishKey)
end

-- Post by (category, sentiment [, subtopic])
--  category: "Police"|"Fire"|"Health"|"Education"|"Leisure"|"Transportation"|"Sports"|"Utilities"
--  sentiment: "need"|"praise"|"funding"|"upgrade"|"flavor"
--  subtopic: for Transportation: "BusDepot"|"Airport"|"Metro"; for Sports: facility name; for Utilities: "Power"|"Water"
function SocialMediaService.postCategory(player: Player, category: string, sentiment: string, opts: table?)
	if not player or not category or not sentiment then return end
	local pool

	if category == "Transportation" then
		local sub = opts and opts.subtopic or "BusDepot"
		local bucket = KEYS.Transportation[sub]
		pool = bucket and bucket[sentiment]
	elseif category == "Sports" then
		local sub = opts and opts.subtopic or "BasketballCourt"
		local bucket = KEYS.Sports[sub]
		pool = bucket and bucket[sentiment]
	elseif category == "Utilities" then
		local sub = opts and opts.subtopic or "Power"
		local bucket = KEYS.Utilities[sub]
		pool = bucket and bucket[sentiment]
	else
		local bucket = KEYS[category]
		pool = bucket and bucket[sentiment]
	end

	local englishKey = pickRandom(pool)
	if not englishKey then return end

	local speakerModel: Model? = nil
	if opts and type(opts.targetName)=="string" and opts.targetName ~= "" then
		speakerModel = findCivByNameAllPlots(opts.targetName)
	end

	local text = localizeRandomDialectFor(player, englishKey, speakerModel)
	local meta = { category = category, sentiment = sentiment, zoneId = opts and opts.zoneId or nil }
	postToGui(player, text, meta, englishKey)
	postToBubble(player, text, opts and opts.targetName or speakerModel or nil, englishKey)
end

---------------------------------------------------------------------
-- RANDOM SOCIAL POSTS (unconditional chatter)
---------------------------------------------------------------------

-- Post a random line from your free-form Random category.
-- If bucketName is omitted, one of the buckets under KEYS.Random is chosen at random.
function SocialMediaService.postRandomBucket(player: Player, bucketName: string?, opts: table?)
	if not player then return end
	local randomRoot = KEYS.Random
	if not randomRoot then return end

	-- Collect available bucket names under Random
	local buckets = {}
	for name, list in pairs(randomRoot) do
		if type(list) == "table" and #list >= 1 then
			table.insert(buckets, name)
		end
	end
	if #buckets == 0 then return end

	local chosenBucket = bucketName
	if not chosenBucket or not randomRoot[chosenBucket] or #randomRoot[chosenBucket] == 0 then
		chosenBucket = buckets[math.random(1, #buckets)]
	end

	local englishKey = pickRandom(randomRoot[chosenBucket])
	if not englishKey then return end

	local speakerModel: Model? = nil
	if opts and type(opts.targetName)=="string" and opts.targetName ~= "" then
		speakerModel = findCivByNameAllPlots(opts.targetName)
	end

	local text = localizeRandomDialectFor(player, englishKey, speakerModel)
	local meta = { category = "Random", sentiment = chosenBucket, random = true }
	postToGui(player, text, meta, englishKey)
	postToBubble(player, text, opts and opts.targetName or speakerModel or nil, englishKey)
end

-- “Random from everything” picker; includes Random if it has lines.
function SocialMediaService.postRandom(player: Player, opts: table?)
	if not player then return end

	-- Build a choice among categories that currently have content.
	local families = {}

	-- Random family available?
	do
		local randomRoot = KEYS.Random
		if randomRoot then
			for _, list in pairs(randomRoot) do
				if type(list) == "table" and #list >= 1 then
					table.insert(families, "Random")
					break
				end
			end
		end
	end

	-- Structured families (include only if at least one pool has items)
	local structuredCandidates = { "Police","Fire","Health","Education","Leisure" }
	for _, fam in ipairs(structuredCandidates) do
		local bucket = KEYS[fam]
		local hasAny = false
		for _, list in pairs(bucket) do
			if type(list) == "table" and #list >= 1 then hasAny = true break end
		end
		if hasAny then table.insert(families, fam) end
	end

	-- Transportation/Sports/Utilities are nested; include if any subtopic has items
	local function nestedHasAny(root)
		for _, sub in pairs(root) do
			for _, list in pairs(sub) do
				if type(list) == "table" and #list >= 1 then return true end
			end
		end
		return false
	end
	if nestedHasAny(KEYS.Transportation) then table.insert(families, "Transportation") end
	if nestedHasAny(KEYS.Sports)         then table.insert(families, "Sports")         end
	if nestedHasAny(KEYS.Utilities)      then table.insert(families, "Utilities")      end

	if #families == 0 then return end

	local category = families[math.random(1, #families)]

	-- If Random chosen, delegate to postRandomBucket (it will pick a bucket)
	if category == "Random" then
		SocialMediaService.postRandomBucket(player, nil, opts)
		return
	end

	-- Otherwise pick a random sentiment and subtopic
	local sentiment
	local subtopic
	local pool

	if category == "Transportation" then
		local subs = {}
		for name, tbl in pairs(KEYS.Transportation) do
			for _, list in pairs(tbl) do
				if type(list) == "table" and #list >= 1 then
					table.insert(subs, name); break
				end
			end
		end
		if #subs == 0 then return end
		subtopic = subs[math.random(1, #subs)]
		local bucket = KEYS.Transportation[subtopic]
		local sentiments = {}
		for s, list in pairs(bucket) do
			if type(list) == "table" and #list >= 1 then table.insert(sentiments, s) end
		end
		if #sentiments == 0 then return end
		sentiment = sentiments[math.random(1, #sentiments)]
		pool = KEYS.Transportation[subtopic][sentiment]

	elseif category == "Sports" then
		local subs = {}
		for name, tbl in pairs(KEYS.Sports) do
			for _, list in pairs(tbl) do
				if type(list) == "table" and #list >= 1 then
					table.insert(subs, name); break
				end
			end
		end
		if #subs == 0 then return end
		subtopic = subs[math.random(1, #subs)]
		local bucket = KEYS.Sports[subtopic]
		local sentiments = {}
		for s, list in pairs(bucket) do
			if type(list) == "table" and #list >= 1 then table.insert(sentiments, s) end
		end
		if #sentiments == 0 then return end
		sentiment = sentiments[math.random(1, #sentiments)]
		pool = KEYS.Sports[subtopic][sentiment]

	elseif category == "Utilities" then
		local subs = {}
		for name, tbl in pairs(KEYS.Utilities) do
			for _, list in pairs(tbl) do
				if type(list) == "table" and #list >= 1 then
					table.insert(subs, name); break
				end
			end
		end
		if #subs == 0 then return end
		subtopic = subs[math.random(1, #subs)]
		local bucket = KEYS.Utilities[subtopic]
		local sentiments = {}
		for s, list in pairs(bucket) do
			if type(list) == "table" and #list >= 1 then table.insert(sentiments, s) end
		end
		if #sentiments == 0 then return end
		sentiment = sentiments[math.random(1, #sentiments)]
		pool = KEYS.Utilities[subtopic][sentiment]

	else
		local bucket = KEYS[category]
		local sentiments = {}
		for s, list in pairs(bucket) do
			if type(list) == "table" and #list >= 1 then table.insert(sentiments, s) end
		end
		if #sentiments == 0 then return end
		sentiment = sentiments[math.random(1, #sentiments)]
		pool = KEYS[category][sentiment]
	end

	local englishKey = pickRandom(pool)
	if not englishKey then return end

	local speakerModel: Model? = nil
	if opts and type(opts.targetName)=="string" and opts.targetName ~= "" then
		speakerModel = findCivByNameAllPlots(opts.targetName)
	end

	local text = localizeRandomDialectFor(player, englishKey, speakerModel)
	local meta = {
		category  = category,
		sentiment = sentiment,
		subtopic  = subtopic,
		random    = true,
	}

	postToGui(player, text, meta, englishKey)
	postToBubble(player, text, opts and opts.targetName or speakerModel or nil, englishKey)
end

local playerCacheByUserId = {}

local function playerForUserId(uid: number): Player?
	if not uid then return nil end
	local cached = playerCacheByUserId[uid]
	if cached and cached.Parent then return cached end
	local plr = Players:GetPlayerByUserId(uid)
	if plr then playerCacheByUserId[uid] = plr end
	return plr
end

local function getSpeakerPlayerForModel(model: Model): Player?
	-- 1) Direct attribute (fast path)
	local uid = model:GetAttribute("OwnerUserId")
	local plr = playerForUserId(tonumber(uid))
	if plr then return plr end

	-- 2) Walk up to find a Plot_<userId> ancestor (fallback)
	local ancestor = model
	while ancestor and ancestor ~= Workspace do
		if ancestor:IsA("Model") or ancestor:IsA("Folder") then
			local name = ancestor.Name
			-- matches "Plot_1234567"
			local idStr = name:match("^Plot_(%d+)$")
			if idStr then
				plr = playerForUserId(tonumber(idStr))
				if plr then return plr end
			end
		end
		ancestor = ancestor.Parent
	end

	-- 3) Absolute fallback: any connected player (last resort)
	local list = Players:GetPlayers()
	return list[1]
end

-- Guarded connect in case RequestRandomBubbleLine is not present yet
if RequestRandomBubbleLine then
	RequestRandomBubbleLine.Event:Connect(function(targetModel)
		if not (typeof(targetModel) == "Instance" and targetModel:IsA("Model")) then return end

		local player = getSpeakerPlayerForModel(targetModel)
		if not player then return end

		local englishKey = pickAnyEnglishKeyPreferRandom()
		if not englishKey then return end

		-- Localize using the OWNER'S language; pick/remember a dialect for THIS civ
		local text = localizeRandomDialectFor(player, englishKey, targetModel)

		-- Seed the exact model (shared world text), and stamp LangKey as you already do
		postToBubble(player, text, targetModel, englishKey)
	end)
else
	warn("[SocialMediaService] Optional Bindable 'RequestRandomBubbleLine' not found; skipping connection.")
end

return SocialMediaService
