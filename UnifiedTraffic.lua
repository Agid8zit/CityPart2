--==========================================--
-- UnifiedTraffic (your second chunk) ENHANCED
--==========================================--
local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

--// Modules
local GridConfig        = require(ReplicatedStorage.Scripts.Grid.GridConfig)
local GridUtil          = require(ReplicatedStorage.Scripts.Grid.GridUtil)
local ZoneTrackerModule = require(game.ServerScriptService.Build.Zones.ZoneManager.ZoneTracker)
local PathingModule     = require(script.Parent.PathingModule)   -- existing
local CarMovement       = require(script.Parent.CarMovement)     -- existing

--// Events
local BindableEvents       = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents")
local RemoteEvents         = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents")
local ZoneAddedEvt         = BindableEvents:WaitForChild("ZoneAdded")
local ZoneRemovedEvt       = BindableEvents:WaitForChild("ZoneRemoved")
local ZoneReCreatedEvt     = BindableEvents:WaitForChild("ZoneReCreated")
local ZonePopulatedEvt     = BindableEvents:WaitForChild("ZonePopulated")
local FireSupportEvt       = BindableEvents:WaitForChild("FireSupportUnlocked")
local PoliceSupportEvt     = BindableEvents:WaitForChild("PoliceSupportUnlocked")
local HealthSupportEvt     = BindableEvents:WaitForChild("HealthSupportUnlocked")
local TrashSupportEvt      = BindableEvents:WaitForChild("TrashSupportUnlocked")
local BusSupportUnlocked   = BindableEvents:WaitForChild("BusSupportUnlocked")
local BusSupportRevoked    = BindableEvents:WaitForChild("BusSupportRevoked")
local SpawnCarToFarthestEvt = RemoteEvents:FindFirstChild("SpawnCarToFarthest")
local CameraAttachEvt       = RemoteEvents:FindFirstChild("CameraAttachToCar")
local TrafficClientDriveEvt = RemoteEvents:FindFirstChild("TrafficClientDrive") or Instance.new("RemoteEvent", RemoteEvents)
TrafficClientDriveEvt.Name = "TrafficClientDrive"
local TrafficClientAckEvt   = RemoteEvents:FindFirstChild("TrafficClientDriveAck") or Instance.new("RemoteEvent", RemoteEvents)
TrafficClientAckEvt.Name   = "TrafficClientDriveAck"
local TrafficClientArrivedEvt = RemoteEvents:FindFirstChild("TrafficClientArrived") or Instance.new("RemoteEvent", RemoteEvents)
TrafficClientArrivedEvt.Name = "TrafficClientArrived"

-- Save reload gates (optional, but your stack has them)
local RequestReloadFromCurrentEvt = BindableEvents:FindFirstChild("RequestReloadFromCurrent")
local NetworksPostLoadEvt         = BindableEvents:FindFirstChild("NetworksPostLoad")

--// Template Roots
local CarsRoot          = ReplicatedStorage:WaitForChild("FuncTestGroundRS"):WaitForChild("Cars")
local DefaultCarsFolder = CarsRoot:WaitForChild("RedTestCar")
local UniqueCarsFolder  = CarsRoot:FindFirstChild("UniqueCars")
local BusesFolder       = CarsRoot:FindFirstChild("Buses") or CarsRoot:FindFirstChild("Busses")

local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService:WaitForChild("Services")

-- Bus tiers/levels read
local PlayerDataInterfaceService = require(Services:WaitForChild("PlayerDataInterfaceService"))
local SoundController = require(ReplicatedStorage.Scripts.Controllers.SoundController)

--======================================================================
--  CONFIG (tune to taste)
--======================================================================
local FIXED_Y_OFFSET            = 1.5

local MIN_PATH_CELLS            = 6       -- don’t spawn for trivial hops
local SPAWN_INTERVAL_SEC        = 2.0     -- target average (per player)
local RANDOM_JITTER_SEC         = 1.25    -- jitter to avoid sync bursts
local MAX_CONCURRENT_PER_PLAYER = 10      -- live cars cap per player
local TOKEN_BUCKET_RATE         = 0.5     -- tokens/sec added
local TOKEN_BUCKET_MAX          = 5       -- max tokens
local CAR_LIFETIME_SEC          = 300     -- hard cleanup fallback
local FADE_OUT_TIME             = 1.5     -- despawn fade
local RECOMPUTE_DEBOUNCE        = 0.1     -- recompute coalescing
local RESCAN_PERIODIC_SEC       = 45      -- periodic safety net

--======================================================================
--  BUS BALANCING (tiers/levels → % traffic that are buses)
--======================================================================
local MAX_BUS_SHARE        = 0.30  -- hard cap when all 10 tiers are level 100
local LOG_RESPONSE_A       = 0.50  -- >0 means stronger early returns, diminishing later
local MAX_BUS_TIERS        = 10    -- schema says 10
local LEVELS_PER_TIER_UNLOCK = 3

-- Vehicle audio (kept subtle)
local VEHICLE_AUDIO = {
	ambience = {
		maxInstances   = 6,
		defaultChance  = 0.22,
		busChance      = 0.35,
		volume         = 0.15,
		rollOffMin     = 10,
		rollOffMax     = 220,
		pitchMin       = 0.94,
		pitchMax       = 1.06,
	},
	horn = {
		chance         = 0.04,
		cooldownSec    = 7,
		volume         = 0.18,
		rollOffMin     = 12,
		rollOffMax     = 240,
		pitchMin       = 0.95,
		pitchMax       = 1.05,
	},
	siren = {
		maxInstances   = 3,
		chance         = 0.22,
		volume         = 0.16,
		rollOffMin     = 12,
		rollOffMax     = 260,
		pitchMin       = 0.97,
		pitchMax       = 1.03,
	},
}

-- Two-way options (kept; ignored in zone-based modes below)
local BUS_SPAWN_CHANCE          = 0.25
local FIRE_SPAWN_CHANCE         = 0.15
local POLICE_SPAWN_CHANCE       = FIRE_SPAWN_CHANCE
local HEALTH_SPAWN_CHANCE       = FIRE_SPAWN_CHANCE
local TRASH_SPAWN_CHANCE        = FIRE_SPAWN_CHANCE
local TWO_WAY_ENABLED           = true
local TWO_WAY_MODE              = "mirror"        -- "mirror" or "chance"
local TWO_WAY_CHANCE            = 0.5

-- Prefer sinks from endpoints; allow near-zone sinks
local PREFER_ENDPOINT_SINKS     = true

-- Source of the road network (must be covered by a road tile to be "live").
-- In zone-based modes this acts as the DESTINATION.
local SOURCE_COORD = { x = 0, z = 0 }

-- NEW: how close (in grid cells) a non-road zone center must be to “snap” to a road node as a zone source
local NEAR_ZONE_MAX_DIST_CELLS  = 3
-- Optionally cap how many near-zone sources we consider
local MAX_NEAR_ZONE_SINKS       = 16

-- NEW: Dispatch mode. Choose ONE.
--   "ZoneToOriginOnly"     -> spawn near-zone -> drive to SOURCE_COORD (your request)
--   "ZoneToOriginAndBack"  -> also mirror a return trip SOURCE_COORD -> the same zone
--   "OriginToSinks"        -> legacy behavior (SOURCE_COORD -> sinks [+ optional mirror])
local DISPATCH_MODE = "ZoneToOriginAndBack"

local TrafficTierConfig = {
	["desktop-high"] = {
		spawnInterval    = SPAWN_INTERVAL_SEC,
		maxConcurrent    = MAX_CONCURRENT_PER_PLAYER,
		tokenRate        = TOKEN_BUCKET_RATE,
		tokenMax         = TOKEN_BUCKET_MAX,
		maxNearZoneSinks = MAX_NEAR_ZONE_SINKS,
		dispatchMode     = DISPATCH_MODE,
	},
	["desktop-balanced"] = {
		spawnInterval    = SPAWN_INTERVAL_SEC * 1.2,
		maxConcurrent    = math.max(6, math.floor(MAX_CONCURRENT_PER_PLAYER * 0.8 + 0.5)),
		tokenRate        = TOKEN_BUCKET_RATE * 0.9,
		tokenMax         = math.max(3, TOKEN_BUCKET_MAX - 1),
		maxNearZoneSinks = math.max(10, MAX_NEAR_ZONE_SINKS - 4),
		dispatchMode     = "ZoneToOriginOnly",
	},
	["desktop-low"] = {
		spawnInterval    = SPAWN_INTERVAL_SEC * 1.35,
		maxConcurrent    = math.max(4, math.floor(MAX_CONCURRENT_PER_PLAYER * 0.6 + 0.5)),
		tokenRate        = TOKEN_BUCKET_RATE * 0.7,
		tokenMax         = math.max(2, TOKEN_BUCKET_MAX - 2),
		maxNearZoneSinks = math.max(8, MAX_NEAR_ZONE_SINKS - 6),
		dispatchMode     = "ZoneToOriginOnly",
	},
	["mobile-low"] = {
		spawnInterval    = SPAWN_INTERVAL_SEC * 1.6,
		maxConcurrent    = 4,
		tokenRate        = TOKEN_BUCKET_RATE * 0.5,
		tokenMax         = 2,
		maxNearZoneSinks = math.max(6, math.floor(MAX_NEAR_ZONE_SINKS * 0.5 + 0.5)),
		dispatchMode     = "OriginToSinks",
	},
}

local function perfTier(player)
	local t = player and player:GetAttribute("PerfTier")
	if t == "mobile" then return "mobile-low" end
	if t == "desktop" then return "desktop-high" end
	if t == "desktop-high" or t == "desktop-balanced" or t == "desktop-low" or t == "mobile-low" then
		return t
	end
	return "desktop-high"
end

local function trafficConfigFor(player)
	local tier = perfTier(player)
	return TrafficTierConfig[tier] or TrafficTierConfig["desktop-high"]
end

--======================================================================
--  STATE
--======================================================================
local fireSupport   = {}  -- [userId] = true when Fire unlocked
local policeSupport = {}  -- [userId] = true when Police unlocked
local healthSupport = {}  -- [userId] = true when Health unlocked
local trashSupport  = {}  -- [userId] = true when Trash unlocked
local busSupport    = {}  -- [userId] = true when Bus unlocked
local _busWarnedMissing = false

local ctxByUserId = {}
local ensureCtx -- forward declaration

local variantsWithAmbience = { Default = true, Bus = true }
local variantsWithSiren    = { Fire = true, Police = true, Health = true }
local activeAmbienceCount  = 0
local activeSirenCount     = 0
local lastHornAt           = 0

local function applyTrafficConfig(ctx, player)
	if not ctx then return end
	local cfg = trafficConfigFor(player)
	-- cache tier string on cfg so we can check changes
	local tier = perfTier(player)
	if ctx._tier == tier and ctx.config == cfg then return end
	ctx._tier = tier
	ctx.config = cfg
	-- clamp tokens and live counts to the new caps
	ctx.tokens = math.min(cfg.tokenMax or TOKEN_BUCKET_MAX, ctx.tokens or 0)
	if ctx.carCount and cfg.maxConcurrent and ctx.carCount > cfg.maxConcurrent then
		ctx.carCount = cfg.maxConcurrent
	end
end

local function currentDispatchMode(ctx)
	if ctx and ctx.config and ctx.config.dispatchMode then
		return ctx.config.dispatchMode
	end
	return DISPATCH_MODE
end

local CLIENT_DRIVE_ENABLED = true  -- flip false to revert to server tweens
local CLIENT_DRIVE_DEBUG   = false
local CLIENT_DRIVE_MAX_POINTS = 120 -- gate client-drive on very long paths to limit payload size
local CLIENT_DRIVE_ALLOWED_TIERS = {
	["desktop-high"]     = true,
	["desktop-balanced"] = true,
}
local function clientDriveAllowed(player: Player?)
	if not CLIENT_DRIVE_ENABLED then return false end
	local tier = perfTier(player)
	return CLIENT_DRIVE_ALLOWED_TIERS[tier] == true
end

local function _markClientArrived(car: Model?)
	if not car then return end
	local ownerId = tonumber(car:GetAttribute("TrafficOwner"))
	if not ownerId then return end
	local ctx = ctxByUserId[ownerId]
	if ctx and ctx.cars and ctx.cars[car] then
		ctx.cars[car] = nil
		ctx.carCount = math.max(0, (ctx.carCount or 1) - 1)
	end
end

TrafficClientAckEvt.OnServerEvent:Connect(function(player, car)
	if CLIENT_DRIVE_DEBUG then
		print(string.format("[TrafficClient] ack <- %s car=%s", player and player.Name or "?", car))
	end
	if not car or not car:IsA("Model") then return end
	car:SetAttribute("ClientDriveActive", true)
	car:SetAttribute("ClientDrivePending", false)
end)

TrafficClientArrivedEvt.OnServerEvent:Connect(function(player, car)
	if CLIENT_DRIVE_DEBUG then
		print(string.format("[TrafficClient] arrived <- %s car=%s", player and player.Name or "?", car))
	end
	if not car or not car:IsA("Model") then return end
	_markClientArrived(car)
	fadeOutAndDestroy(car, FADE_OUT_TIME)
end)

local templates = {
	default = {},
	fire    = {},
	police  = {},
	health  = {},
	trash   = {},
	bus     = {},
}

local uniqueVehicleVariants = {
	{ templateKey = "police", folderName = "Police", label = "Police", supportTable = policeSupport, chance = POLICE_SPAWN_CHANCE },
	{ templateKey = "fire",   folderName = "Fire",   label = "Fire",   supportTable = fireSupport,   chance = FIRE_SPAWN_CHANCE },
	{ templateKey = "health", folderName = "Health", label = "Health", supportTable = healthSupport, chance = HEALTH_SPAWN_CHANCE },
	{ templateKey = "trash",  folderName = "Trash",  label = "Trash",  supportTable = trashSupport,  chance = TRASH_SPAWN_CHANCE },
}

-- Keep a per-tier index for buses so tier unlock gates selection cleanly
local busByTier = {}   -- [tierIndex] = {Model, ...}
for i=1, MAX_BUS_TIERS do busByTier[i] = {} end

local function busTierOf(model: Instance): number
	-- Prefer explicit attribute if you add it later
	local att = tonumber(model:GetAttribute("Tier"))
	if att then return math.clamp(math.floor(att), 1, MAX_BUS_TIERS) end
	-- Fallback: parse trailing digits in name (e.g., "Bus3" -> 3)
	local n = tonumber(string.match(model.Name, "(%d+)$"))
	if n then return math.clamp(n, 1, MAX_BUS_TIERS) end
	return 1
end

--======================================================================
--  ALL-WAY STOP CONFIG + HELPERS
--======================================================================
local ALL_WAY_STOP_SEC       = 0.30
local STOP_JITTER_SEC        = 0.35
local INCLUDE_TURNS_AS_STOPS = false

--========================
-- [DRIVE MODE] CONFIG
--========================
local DRIVE_RESPAWN_DELAY   = 1.0     -- time between trips
local DRIVE_MOVE_DIST_STOP  = 60.0    -- studs from start pos (2D) before we auto-cancel
local DRIVE_MOVE_SPEED_STOP = 40.0    -- ignore normal walking or being seated in the drive car
local DRIVE_TOGGLE_DEBOUNCE = 0.5     -- per-toggle server cooldown
local DRIVE_MOVE_GRACE_SEC  = 1.0     -- grace window after toggling on
local DRIVE_NEAR_CAR_RADIUS = 45      -- if the player is near/inside a drive car, don't cancel
local DRIVE_SPAWN_OVERRIDES = { skipTokens = true, skipCarLimit = true }

--======================================================================
--  UTILITIES
--======================================================================
local function dprint(...) end

local function getPlotForUserId(uid)
	local plots = Workspace:FindFirstChild("PlayerPlots")
	return plots and plots:FindFirstChild("Plot_"..tostring(uid))
end

local boundsCache = {} -- [plot] = { bounds=..., terrains={...} }
local function getGlobalBoundsForPlot(plot)
	if not plot then return nil, nil end
	local cached = boundsCache[plot]
	if cached then return cached.bounds, cached.terrains end

	local terrains = {}
	local unlocks  = plot:FindFirstChild("Unlocks")
	if unlocks then
		for _, zone in ipairs(unlocks:GetChildren()) do
			for _, seg in ipairs(zone:GetChildren()) do
				if seg:IsA("BasePart") and seg.Name:match("^Segment%d+$") then
					table.insert(terrains, seg)
				end
			end
		end
	end
	local testTerrain = plot:FindFirstChild("TestTerrain")
	if #terrains == 0 and testTerrain then table.insert(terrains, testTerrain) end

	local gb = GridConfig.calculateGlobalBounds(terrains)
	boundsCache[plot] = { bounds = gb, terrains = terrains }
	return gb, terrains
end

local function gridToWorld(plot, coord)
	local gb, terrains = getGlobalBoundsForPlot(plot)
	if not gb then
		local worldX, worldZ = GridUtil.gridToWorldPosition(coord.x, coord.z, 0, 0)
		return Vector3.new(worldX, FIXED_Y_OFFSET, worldZ)
	end
	local wx, _, wz = GridUtil.globalGridToWorldPosition(coord.x, coord.z, gb, terrains)
	return Vector3.new(wx, FIXED_Y_OFFSET, wz)
end


-- Token bucket
local function addTokens(ctx)
	local cfg = ctx and ctx.config or TrafficTierConfig["desktop-high"]
	local t = os.clock()
	local dt = t - (ctx.last or t)
	local rate = cfg.tokenRate or TOKEN_BUCKET_RATE
	local max  = cfg.tokenMax  or TOKEN_BUCKET_MAX
	ctx.tokens = math.min(max, (ctx.tokens or 0) + dt * rate)
	ctx.last = t
end
local function trySpend(ctx, cost)
	addTokens(ctx)
	if ctx.tokens >= cost then
		ctx.tokens -= cost
		return true
	end
	return false
end

local function buildEdgeKeysForPath(gridPath)
	if not gridPath or #gridPath < 2 then return {} end
	local edgeKeys = {}
	for k = 1, #gridPath - 1 do
		local a = gridPath[k]
		local b = gridPath[k+1]
		edgeKeys[k] = string.format("%d_%d->%d_%d", a.x, a.z, b.x, b.z)
	end
	return edgeKeys
end

local function computePreIntersectionStops(player, gridPath)
	if not gridPath or #gridPath < 3 then return {}, {} end
	local preStops, keysByIdx = {}, {}
	for i = 2, #gridPath - 1 do
		local c = gridPath[i]
		local cls = PathingModule.classifyNode(c, player)
		if cls == "4Way" or cls == "3Way" or (INCLUDE_TURNS_AS_STOPS and cls == "Turn") then
			local preIdx = i - 1
			if preIdx >= 1 then
				preStops[#preStops+1] = preIdx
				keysByIdx[preIdx] = PathingModule.nodeKey(c)
			end
		end
	end
	if #preStops > 1 then
		local compact = { preStops[1] }
		for k = 2, #preStops do
			if preStops[k] ~= preStops[k-1] then
				compact[#compact+1] = preStops[k]
			end
		end
		preStops = compact
	end
	return preStops, keysByIdx
end

local function newPathId(uid)
	return ("P%s_%d"):format(uid, math.floor(os.clock()*1000))
end

local function reversedGridPath(path)
	if not path or #path < 2 then return nil end
	local out = table.create(#path)
	for i = #path, 1, -1 do
		out[#out + 1] = { x = path[i].x, z = path[i].z }
	end
	return out
end

-- Vehicle audio helpers
local function randomBetween(minValue, maxValue)
	return minValue + (maxValue - minValue) * math.random()
end

local function attachSoundToCar(car, soundName, opts)
	if not car then return nil end
	local primary = car.PrimaryPart or car:FindFirstChildWhichIsA("BasePart")
	if not primary then return nil end
	local ok, sound = pcall(SoundController.CreateSound, "Misc", soundName)
	if not ok or not sound then return nil end
	if opts then
		if opts.volume then sound.Volume = opts.volume end
		if opts.rollOffMin then sound.RollOffMinDistance = opts.rollOffMin end
		if opts.rollOffMax then sound.RollOffMaxDistance = opts.rollOffMax end
		if opts.playbackSpeed then sound.PlaybackSpeed = opts.playbackSpeed end
		if opts.loop ~= nil then sound.Looped = opts.loop end
	end
	sound.Parent = primary
	task.spawn(function()
		if not sound.IsLoaded then
			pcall(function() sound.Loaded:Wait() end)
		end
		if sound.Parent then
			sound:Play()
		end
	end)
	return sound
end

local function bindSoundLifecycle(car, sound, opts)
	if not (car and sound) then return end
	local onCleanup = opts and opts.onCleanup
	local stopOnEnded = true
	if opts and opts.stopOnEnded ~= nil then
		stopOnEnded = opts.stopOnEnded
	end
	local conn
	local fired = false
	local function finalize()
		if fired then return end
		fired = true
		if conn then
			conn:Disconnect()
			conn = nil
		end
		if onCleanup then
			local ok, err = pcall(onCleanup)
			if not ok then
				warn("[UnifiedTraffic] vehicle audio cleanup error:", err)
			end
		end
		if sound and sound.Parent then
			sound:Stop()
			sound:Destroy()
		end
	end
	conn = car.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			finalize()
		end
	end)
	if stopOnEnded and sound then
		sound.Ended:Connect(finalize)
	end
end

local function attachVehicleAudio(car, variantLabel)
	if not car then return end
	variantLabel = variantLabel or "Default"

	if variantsWithAmbience[variantLabel]
		and activeAmbienceCount < VEHICLE_AUDIO.ambience.maxInstances
	then
		local chance = (variantLabel == "Bus") and VEHICLE_AUDIO.ambience.busChance or VEHICLE_AUDIO.ambience.defaultChance
		if math.random() < chance then
			local sound = attachSoundToCar(car, "CarAmbiance", {
				loop = true,
				volume = VEHICLE_AUDIO.ambience.volume,
				rollOffMin = VEHICLE_AUDIO.ambience.rollOffMin,
				rollOffMax = VEHICLE_AUDIO.ambience.rollOffMax,
				playbackSpeed = randomBetween(VEHICLE_AUDIO.ambience.pitchMin, VEHICLE_AUDIO.ambience.pitchMax),
			})
			if sound then
				activeAmbienceCount += 1
				bindSoundLifecycle(car, sound, {
					stopOnEnded = false,
					onCleanup = function()
						activeAmbienceCount = math.max(0, activeAmbienceCount - 1)
					end,
				})
			end
		end
	end

	local now = os.clock()
	if (now - lastHornAt) >= VEHICLE_AUDIO.horn.cooldownSec
		and math.random() < VEHICLE_AUDIO.horn.chance
	then
		local sound = attachSoundToCar(car, "CarHorn", {
			volume = VEHICLE_AUDIO.horn.volume,
			rollOffMin = VEHICLE_AUDIO.horn.rollOffMin,
			rollOffMax = VEHICLE_AUDIO.horn.rollOffMax,
			playbackSpeed = randomBetween(VEHICLE_AUDIO.horn.pitchMin, VEHICLE_AUDIO.horn.pitchMax),
		})
		if sound then
			lastHornAt = now
			bindSoundLifecycle(car, sound, {
				stopOnEnded = true,
			})
		end
	end

	if variantsWithSiren[variantLabel]
		and activeSirenCount < VEHICLE_AUDIO.siren.maxInstances
		and math.random() < VEHICLE_AUDIO.siren.chance
	then
		local sound = attachSoundToCar(car, "Siren", {
			volume = VEHICLE_AUDIO.siren.volume,
			rollOffMin = VEHICLE_AUDIO.siren.rollOffMin,
			rollOffMax = VEHICLE_AUDIO.siren.rollOffMax,
			playbackSpeed = randomBetween(VEHICLE_AUDIO.siren.pitchMin, VEHICLE_AUDIO.siren.pitchMax),
		})
		if sound then
			activeSirenCount += 1
			bindSoundLifecycle(car, sound, {
				stopOnEnded = true,
				onCleanup = function()
					activeSirenCount = math.max(0, activeSirenCount - 1)
				end,
			})
		end
	end
end

-- Templates
local function clear(list) for i=#list,1,-1 do list[i]=nil end end
local function repackChildren(folder, into)
	if not folder then return end
	for _, ch in ipairs(folder:GetChildren()) do
		if ch:IsA("Model") then
			table.insert(into, ch)
		elseif ch:IsA("Folder") then
			for _, m in ipairs(ch:GetChildren()) do
				if m:IsA("Model") then table.insert(into, m) end
			end
		end
	end
end

local function refreshTemplateCache()
	clear(templates.default); repackChildren(DefaultCarsFolder, templates.default)
	for _, variant in ipairs(uniqueVehicleVariants) do
		local pool = templates[variant.templateKey]
		clear(pool)
		if UniqueCarsFolder then
			local node = UniqueCarsFolder:FindFirstChild(variant.folderName)
			if node then
				if node:IsA("Model") then
					table.insert(pool, node)
				else
					repackChildren(node, pool)
				end
			end
		end
	end
	clear(templates.bus)
	for i=1, MAX_BUS_TIERS do clear(busByTier[i]) end

	if BusesFolder then
		-- Gather all bus models into templates.bus and per-tier bins
		local function addBusModel(m)
			if m:IsA("Model") then
				table.insert(templates.bus, m)
				local ti = busTierOf(m)
				table.insert(busByTier[ti], m)
			end
		end
		for _, ch in ipairs(BusesFolder:GetChildren()) do
			if ch:IsA("Model") then
				addBusModel(ch)
			elseif ch:IsA("Folder") then
				for _, m in ipairs(ch:GetChildren()) do
					addBusModel(m)
				end
			end
		end
	end
end
refreshTemplateCache()
local function watchFolder(folder)
	if not folder then return end
	folder.ChildAdded:Connect(function() task.defer(refreshTemplateCache) end)
	folder.ChildRemoved:Connect(function() task.defer(refreshTemplateCache) end)
end
watchFolder(DefaultCarsFolder); watchFolder(UniqueCarsFolder); watchFolder(BusesFolder)

local function unlockedTiersFromUnlockValue(unlockNum: number): number
	-- same math as your Interface: floor(unlock / LEVELS_PER_TIER_UNLOCK)+1 clamped to 1..10
	local t = math.floor(math.max(0, tonumber(unlockNum) or 0) / LEVELS_PER_TIER_UNLOCK) + 1
	return math.clamp(t, 1, MAX_BUS_TIERS)
end

-- Log-shaped contribution: strong early gains; diminishing later
local function levelContributionLog(level: number): number
	local L = math.clamp(tonumber(level) or 0, 0, 100)
	if LOG_RESPONSE_A <= 0 then
		return L/100 -- linear fallback if A<=0
	end
	local num = math.log(1 + LOG_RESPONSE_A * L)
	local den = math.log(1 + LOG_RESPONSE_A * 100)
	return (den > 0) and (num / den) or (L/100)
end

-- Main bus share + highest eligible tier for this player
local function computeBusShareAndMaxTier(player: Player): (number, number)
	-- Interface helpers you added at the bottom of your file:
	--   GetTransitUnlock(player, "busDepot")
	--   GetTransitTierLevel(player, "busDepot", tierIndex)
	local unlock = PlayerDataInterfaceService.GetTransitUnlock(player, "busDepot") or 0
	local unlocked = unlockedTiersFromUnlockValue(unlock)

	local sum = 0
	local maxTierEligible = 0
	for ti = 1, unlocked do
		local lv = PlayerDataInterfaceService.GetTransitTierLevel(player, "busDepot", ti) or 0
		if lv > 0 then
			maxTierEligible = ti
		end
		sum += levelContributionLog(lv) -- 0..1 per tier
	end

	-- Cap at 30% when all 10 tiers are 100: sum==10 ⇒ 0.3
	local share = MAX_BUS_SHARE * (sum / MAX_BUS_TIERS)
	return share, maxTierEligible
end


local function pickTemplateForPlayer(player)
	local uid = player.UserId

	-- Compute per-player bus share + max eligible tier
	local busShare, maxBusTier = 0, 0
	if busSupport[uid] and #templates.bus > 0 then
		busShare, maxBusTier = computeBusShareAndMaxTier(player)
	end

	-- Try to spawn a bus under the share constraint if supported & any tier is eligible
	if busSupport[uid] and maxBusTier > 0 and math.random() < busShare then
		-- Choose a bus from tiers 1..maxBusTier (weighted uniformly across available models)
		-- If you want to bias toward higher tiers, we can weight later—this is simple & robust.
		local candidatePool = {}
		for ti = 1, maxBusTier do
			-- e.g., weight = ti (linear) or ti^2 (quadratic). Start with linear:
			local weight = ti
			for _, m in ipairs(busByTier[ti]) do
				for _ = 1, weight do
					table.insert(candidatePool, m)
				end
			end
		end
		if #candidatePool > 0 then
			return candidatePool[math.random(1, #candidatePool)], "Bus"
		end
		-- fallthrough to fire/default if something odd happened
	end

	for _, variant in ipairs(uniqueVehicleVariants) do
		local support = variant.supportTable
		local pool = templates[variant.templateKey]
		if support[uid] and #pool > 0 and math.random() < variant.chance then
			return pool[math.random(1, #pool)], variant.label
		end
	end

	if #templates.default == 0 then
		warn("[UnifiedTraffic] DefaultCarsFolder is empty; cannot spawn traffic.")
		return nil, nil
	end
	return templates.default[math.random(1, #templates.default)], "Default"
end

--======================================================================
--  GRAPH / OWNERSHIP FILTERING
--======================================================================
local function refreshOwnRoadZones(player, ctx)
	local set = {}
	for zid, z in pairs(ZoneTrackerModule.getAllZones(player)) do
		if z.mode == "DirtRoad" or z.mode == "Pavement" or z.mode == "Highway" then
			set[zid] = true
		end
	end
	ctx.ownRoadZoneIds = set
end

local function adjacencyForPlayer(player)
	if PathingModule.getAdjacencyForOwner then
		return PathingModule.getAdjacencyForOwner(player) or PathingModule.globalAdjacency
	end
	return PathingModule.globalAdjacency
end

local function nodeOwnedByPlayer(player, key, ctx)
	if not key then return false end
	ctx = ctx or ensureCtx(player)
	local metaBucket = PathingModule.getNodeMetaForOwner and PathingModule.getNodeMetaForOwner(player) or nil
	local meta = metaBucket and metaBucket[key]
	if not meta then return false end
	local zid = meta.groupId
	if not zid then return false end
	if ctx and ctx.ownRoadZoneIds then
		return ctx.ownRoadZoneIds[zid] == true
	end
	return ZoneTrackerModule.getZoneById(player, zid) ~= nil
end

local function coordFromKey(key, cache)
	if cache and cache[key] then
		return cache[key]
	end
	local sep = string.find(key, "_", 1, true)
	if not sep then return nil end
	local x = tonumber(string.sub(key, 1, sep - 1))
	local z = tonumber(string.sub(key, sep + 1))
	if not x or not z then return nil end
	local coord = { x = x, z = z }
	if cache then
		cache[key] = coord
	end
	return coord
end

local function gridPathFromKeys(keys, cache)
	if not keys then return nil end
	local path = table.create(#keys)
	for i = 1, #keys do
		local coord = coordFromKey(keys[i], cache)
		if not coord then return nil end
		path[i] = { x = coord.x, z = coord.z }
	end
	return path
end

local function pathKeysFromOrigin(ctx, targetKey)
	if not ctx or not ctx.bfsOriginKey then return nil end
	local dist = ctx.bfsDist
	local parent = ctx.bfsParent
	if not (dist and parent) then return nil end
	if not dist[targetKey] then return nil end
	local keys, cur = {}, targetKey
	while cur do
		keys[#keys+1] = cur
		if cur == ctx.bfsOriginKey then break end
		cur = parent[cur]
	end
	if keys[#keys] ~= ctx.bfsOriginKey then return nil end
	for i = 1, math.floor(#keys/2) do
		keys[i], keys[#keys - i + 1] = keys[#keys - i + 1], keys[i]
	end
	return keys
end

local function pathFromOrigin(ctx, coord)
	if not ctx then return nil end
	local targetKey = PathingModule.nodeKey(coord)
	local keys = pathKeysFromOrigin(ctx, targetKey)
	if not keys then return nil end
	ctx.coordCache = ctx.coordCache or {}
	return gridPathFromKeys(keys, ctx.coordCache)
end

local function ensureBfsSnapshot(player, ctx)
	ctx = ctx or ensureCtx(player)
	if not ctx then return nil end
	local adj = adjacencyForPlayer(player)
	if not adj then
		ctx.bfsOriginKey, ctx.bfsDist, ctx.bfsParent = nil, nil, nil
		return nil
	end
	local originKey = PathingModule.nodeKey(SOURCE_COORD)
	if not (adj[originKey] and nodeOwnedByPlayer(player, originKey, ctx)) then
		ctx.bfsOriginKey, ctx.bfsDist, ctx.bfsParent = nil, nil, nil
		return nil
	end
	local dist, parent = { [originKey] = 0 }, {}
	local queue = table.create(256)
	local head, tail = 1, 1
	queue[tail] = originKey
	tail += 1
	while head < tail do
		local cur = queue[head]
		head += 1
		local curDist = dist[cur]
		local nbrs = adj[cur]
		if nbrs then
			for i = 1, #nbrs do
				local nb = nbrs[i]
				if not dist[nb] and nodeOwnedByPlayer(player, nb, ctx) then
					dist[nb] = curDist + 1
					parent[nb] = cur
					queue[tail] = nb
					tail += 1
				end
			end
		end
	end
	ctx.bfsOriginKey = originKey
	ctx.bfsDist = dist
	ctx.bfsParent = parent
	ctx.coordCache = ctx.coordCache or {}
	return dist
end

local function bfsPathOwned(player, ctx, startCoord, endCoord)
	ctx = ctx or ensureCtx(player)
	local originKey = PathingModule.nodeKey(SOURCE_COORD)
	local startKey = PathingModule.nodeKey(startCoord)
	local endKey   = PathingModule.nodeKey(endCoord)
	local adj = adjacencyForPlayer(player)
	if ctx and ctx.bfsOriginKey == originKey and ctx.bfsDist then
		if startKey == originKey then
			local path = pathFromOrigin(ctx, endCoord)
			if path then return path end
		elseif endKey == originKey then
			local path = pathFromOrigin(ctx, startCoord)
			if path then return reversedGridPath(path) end
		end
	end
	if not (adj and adj[startKey] and adj[endKey]) then return nil end
	if not nodeOwnedByPlayer(player, startKey, ctx) then return nil end
	if not nodeOwnedByPlayer(player, endKey, ctx)   then return nil end

	local queue = table.create(128)
	local head, tail = 1, 1
	queue[tail] = startKey
	tail += 1

	local seen = { [startKey] = true }
	local parent = {}
	local coordCache = {
		[startKey] = { x = startCoord.x, z = startCoord.z },
		[endKey] = { x = endCoord.x, z = endCoord.z },
	}

	while head < tail do
		local cur = queue[head]
		head += 1
		if cur == endKey then
			local keys, k = {}, cur
			while k do
				keys[#keys + 1] = k
				k = parent[k]
			end
			for i = 1, math.floor(#keys / 2) do
				keys[i], keys[#keys - i + 1] = keys[#keys - i + 1], keys[i]
			end
			local path = table.create(#keys)
			for i = 1, #keys do
				local coord = coordFromKey(keys[i], coordCache)
				if not coord then return nil end
				path[i] = { x = coord.x, z = coord.z }
			end
			return path
		end

		local nbrs = adj[cur]
		if nbrs then
			for i = 1, #nbrs do
				local nb = nbrs[i]
				if not seen[nb] and nodeOwnedByPlayer(player, nb, ctx) then
					seen[nb] = true
					parent[nb] = cur
					queue[tail] = nb
					tail += 1
				end
			end
		end
	end
	return nil
end

local function pathIsValid(player, path)
	if not path or #path < 2 then return false end
	local adj = adjacencyForPlayer(player)
	local ctx = ensureCtx(player)
	if not adj then return false end
	for i = 1, #path do
		local k = PathingModule.nodeKey(path[i])
		if not (adj[k] and nodeOwnedByPlayer(player, k, ctx)) then
			return false
		end
	end
	return true
end

-- BFS to a specific target (re-derive a path when shortcuts were added)
local function bfsToTarget(player, targetCoord)
	if not targetCoord then return nil end
	local ctx = ensureCtx(player)
	return bfsPathOwned(player, ctx, SOURCE_COORD, targetCoord)
end

local function originLiveForPlayer(player, ctx)
	ctx = ctx or ensureCtx(player)
	local key = PathingModule.nodeKey(SOURCE_COORD)
	local adj = adjacencyForPlayer(player)
	return adj and adj[key] ~= nil and nodeOwnedByPlayer(player, key, ctx)
end

local function zoneCenterCoord(z)
	local cells = z.gridList or z.cells or z.grid or z.coords
	if type(cells) ~= "table" or #cells == 0 then return nil end
	local sx, sz = 0, 0
	for i=1,#cells do
		local c = cells[i]
		if c and type(c.x)=="number" and type(c.z)=="number" then
			sx += c.x; sz += c.z
		end
	end
	return { x = math.floor(sx/#cells + 0.5), z = math.floor(sz/#cells + 0.5) }
end

local function collectNearZoneSinks(player, ctx)
	ctx = ctx or ensureCtx(player)
	applyTrafficConfig(ctx, player)
	local sinks, count = {}, 0
	local cap = (ctx.config and ctx.config.maxNearZoneSinks) or MAX_NEAR_ZONE_SINKS
	for _, z in pairs(ZoneTrackerModule.getAllZones(player)) do
		if z.mode ~= "DirtRoad" and z.mode ~= "Pavement" and z.mode ~= "Highway" then
			local center = zoneCenterCoord(z)
			if center then
				local near = PathingModule.findNearestRoadNode(center, NEAR_ZONE_MAX_DIST_CELLS, player)
				if near and nodeOwnedByPlayer(player, near.key, ctx) then
					sinks[#sinks+1] = { x = near.x, z = near.z }
					count += 1
					if count >= cap then break end
				end
			end
		end
	end
	return sinks
end

local function computeSinksForPlayer(player, ctx)
	ctx = ctx or ensureCtx(player)
	local dist = ctx and ctx.bfsDist
	if not dist then return {} end
	local ranked = {}
	local function tryRank(coord)
		if coord and type(coord.x)=="number" and type(coord.z)=="number" then
			local key = PathingModule.nodeKey(coord)
			local steps = dist[key]
			if steps and (steps + 1) >= MIN_PATH_CELLS then
				table.insert(ranked, { coord = coord, len = steps + 1 })
			end
		end
	end
	if PREFER_ENDPOINT_SINKS then
		for _, coord in ipairs(PathingModule.getOwnedDeadEnds(player)) do
			tryRank(coord)
		end
	end
	if #ranked == 0 then
		for _, coord in ipairs(collectNearZoneSinks(player, ctx)) do tryRank(coord) end
	end
	if #ranked == 0 then
		local sampled = 0
		for key,_ in pairs(dist) do
			local coord = coordFromKey(key, ctx and ctx.coordCache or nil)
			if coord then
				tryRank(coord)
				sampled += 1
				if sampled >= 128 then break end
			end
		end
	end
	table.sort(ranked, function(a,b) return a.len > b.len end)
	if #ranked >= 4 then
		local keep = math.max(4, math.floor(#ranked * 0.25 + 0.5))
		while #ranked > keep do table.remove(ranked) end
	end
	local sinks = {}
	for i=1,#ranked do sinks[i] = ranked[i].coord end
	return sinks
end

local function computeZoneSourcesForPlayer(player, ctx)
	ctx = ctx or ensureCtx(player)
	local dist = ctx and ctx.bfsDist
	if not dist then return {} end
	local ranked = {}
	for _, sourceCoord in ipairs(collectNearZoneSinks(player, ctx)) do
		local key = PathingModule.nodeKey(sourceCoord)
		local steps = dist[key]
		if steps and (steps + 1) >= MIN_PATH_CELLS then
			table.insert(ranked, { coord = sourceCoord, len = steps + 1 })
		end
	end
	table.sort(ranked, function(a,b) return a.len > b.len end)
	if #ranked >= 4 then
		local keep = math.max(4, math.floor(#ranked * 0.25 + 0.5))
		while #ranked > keep do table.remove(ranked) end
	end
	local sources = {}
	for i=1,#ranked do sources[i] = ranked[i].coord end
	return sources
end


--======================================================================
--  SPAWN / MOVE / CLEANUP
--======================================================================
local function fadeOutAndDestroy(model, t)
	if not model then return end
	local info  = TweenInfo.new(t, Enum.EasingStyle.Linear)
	local tweens = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("MeshPart") or d:IsA("Decal") then
			table.insert(tweens, TweenService:Create(d, info, {Transparency = 1}))
		end
	end
	for i=1,#tweens do tweens[i]:Play() end
	if #tweens > 0 then
		tweens[1].Completed:Connect(function() pcall(function() model:Destroy() end) end)
	else
		pcall(function() model:Destroy() end)
	end
end

local function worldPathFor(plot, gridPath)
	if not gridPath or #gridPath == 0 then return nil end
	local out = table.create(#gridPath)
	for i=1,#gridPath do out[i] = gridToWorld(plot, gridPath[i]) end
	return out
end

local function spawnCarAlongPath(player, ctx, gridPath, worldPath, variantLabel, spawnConfig)
	if ctx.suspended then return end
	if not worldPath or #worldPath < 2 then return end
	applyTrafficConfig(ctx, player)
	local cfg = ctx.config or trafficConfigFor(player)
	local skipTokens    = spawnConfig and spawnConfig.skipTokens
	local skipCarLimit  = spawnConfig and spawnConfig.skipCarLimit
	if not skipTokens and not trySpend(ctx, 1.0) then return end

	if not skipCarLimit then
		local live = ctx.carCount or 0
		if live >= (cfg.maxConcurrent or MAX_CONCURRENT_PER_PLAYER) then return end
	end

	local template, chosenVariant = pickTemplateForPlayer(player)
	if not template then return end
	variantLabel = variantLabel or chosenVariant or "Default"

	local car = template:Clone()
	car.Name = ("Traffic_P%s_%s_%d"):format(player.UserId, variantLabel, math.random(1,999999))
	car.PrimaryPart = car.PrimaryPart or car:FindFirstChildWhichIsA("BasePart")
	car:SetAttribute("IsTraffic", true)
	car:SetAttribute("TrafficOwner", player.UserId)
	car:SetAttribute("TrafficVariant", variantLabel)
	car.Parent = ctx.plot
	car:SetPrimaryPartCFrame(CFrame.new(worldPath[1]))

	attachVehicleAudio(car, variantLabel)

	ctx.cars[car] = true
	ctx.carCount = (ctx.carCount or 0) + 1
	Debris:AddItem(car, CAR_LIFETIME_SEC)

	local preStopIndices, preStopKeys = computePreIntersectionStops(player, gridPath)
	local edgeKeyByIndex = buildEdgeKeysForPath(gridPath)

	local opts = {
		preStopIndices   = preStopIndices,
		preStopKeysByIdx = preStopKeys,
		edgeKeyByIndex   = edgeKeyByIndex,
		stopSeconds      = ALL_WAY_STOP_SEC + math.random() * STOP_JITTER_SEC,
		minEdgeHeadwaySec = 0.25,
	}

	local pathId = newPathId(player.UserId)
	local function onArrive(arrived)
		if ctx.cars[car] then
			ctx.cars[car] = nil
			ctx.carCount = math.max(0, (ctx.carCount or 1) - 1)
		end
		fadeOutAndDestroy(arrived, FADE_OUT_TIME)
	end

	local clientDrove = false
	if player and clientDriveAllowed(player) and #worldPath <= CLIENT_DRIVE_MAX_POINTS then
		car:SetAttribute("ClientDrivePending", true)
		car:SetAttribute("ClientDriveActive", false)
		local okOwn = pcall(function()
			if car.PrimaryPart then car.PrimaryPart:SetNetworkOwner(player) end
		end)
		if okOwn then
			if CLIENT_DRIVE_DEBUG then
				print(string.format("[TrafficClient] send -> %s car=%s pts=%d variant=%s", player.Name, tostring(car), #worldPath, tostring(variantLabel)))
			end
			task.defer(function()
				if car and car.Parent then
					TrafficClientDriveEvt:FireClient(player, car, worldPath, opts, pathId)
				end
			end)
			clientDrove = true
			-- Fallback if client never acks
			task.delay(1.0, function()
				if not car or not car.Parent then return end
				if car:GetAttribute("ClientDriveActive") == true then return end
				if CLIENT_DRIVE_DEBUG then
					print(string.format("[TrafficClient] fallback server drive; no ack car=%s owner=%s", tostring(car), player.Name))
				end
				car:SetAttribute("ClientDrivePending", false)
				car:SetAttribute("ClientDriveActive", false)
				pcall(function() if car.PrimaryPart then car.PrimaryPart:SetNetworkOwner(nil) end end)
				CarMovement.moveCarAlongPath(car, worldPath, opts, onArrive, pathId)
			end)
		end
	end

	if not clientDrove then
		CarMovement.moveCarAlongPath(car, worldPath, opts, onArrive, pathId)
	end
	return car
end

local function spawnOnceOriginToSinksMode(player, ctx)
	if ctx.suspended then return end
	if not originLiveForPlayer(player, ctx) then return end
	if not ctx.sinks or #ctx.sinks == 0 then return end
	ensureBfsSnapshot(player, ctx)

	local sink = ctx.sinks[math.random(1, #ctx.sinks)]
	local gridPath = bfsPathOwned(player, ctx, SOURCE_COORD, sink)
	if (not gridPath or #gridPath < MIN_PATH_CELLS) and #ctx.sinks > 1 then
		sink = ctx.sinks[math.random(1, #ctx.sinks)]
		gridPath = bfsPathOwned(player, ctx, SOURCE_COORD, sink)
	end
	if not gridPath or #gridPath < MIN_PATH_CELLS then return end

	local worldPath = worldPathFor(ctx.plot, gridPath)
	spawnCarAlongPath(player, ctx, gridPath, worldPath, nil)

	if not TWO_WAY_ENABLED then return end
	if TWO_WAY_MODE == "chance" and math.random() >= TWO_WAY_CHANCE then return end

	local revGrid = reversedGridPath(gridPath)
	if not revGrid or #revGrid < MIN_PATH_CELLS then return end
	local revWorld = worldPathFor(ctx.plot, revGrid)
	local revCar = spawnCarAlongPath(player, ctx, revGrid, revWorld, nil)
	if revCar then revCar:SetAttribute("DriveSession", true) end -- harmless tag
end

local function spawnOnceZoneToOriginMode(player, ctx)
	if ctx.suspended then return end
	if not originLiveForPlayer(player, ctx) then return end
	if not ctx.zoneSources or #ctx.zoneSources == 0 then return end
	ensureBfsSnapshot(player, ctx)

	local sourceCoord = ctx.zoneSources[math.random(1, #ctx.zoneSources)]
	local gridPath = bfsPathOwned(player, ctx, sourceCoord, SOURCE_COORD)
	if (not gridPath or #gridPath < MIN_PATH_CELLS) and #ctx.zoneSources > 1 then
		sourceCoord = ctx.zoneSources[math.random(1, #ctx.zoneSources)]
		gridPath = bfsPathOwned(player, ctx, sourceCoord, SOURCE_COORD)
	end
	if not gridPath or #gridPath < MIN_PATH_CELLS then return end

	local worldPath = worldPathFor(ctx.plot, gridPath)
	spawnCarAlongPath(player, ctx, gridPath, worldPath, nil)

	local mode = currentDispatchMode(ctx)
	if mode ~= "ZoneToOriginAndBack" then return end
	local revGrid = reversedGridPath(gridPath)
	if not revGrid or #revGrid < MIN_PATH_CELLS then return end
	local revWorld = worldPathFor(ctx.plot, revGrid)
	local revCar = spawnCarAlongPath(player, ctx, revGrid, revWorld, nil)
	if revCar then revCar:SetAttribute("DriveSession", true) end -- harmless tag
end

local function spawnOnce(player, ctx)
	local mode = currentDispatchMode(ctx or ensureCtx(player))
	if mode == "OriginToSinks" then
		return spawnOnceOriginToSinksMode(player, ctx)
	else
		return spawnOnceZoneToOriginMode(player, ctx)
	end
end

local function killAllTraffic(ctx)
	for car,_ in pairs(ctx.cars) do
		if car and car.Parent then fadeOutAndDestroy(car, 0.5) end
	end
	ctx.cars = {}
	ctx.carCount = 0
end

local function hardKillTrafficInPlot(plot)
	if not plot then return end
	for _, inst in ipairs(plot:GetDescendants()) do
		if (inst:IsA("Model") or inst:IsA("Folder")) and inst:GetAttribute("IsTraffic") == true then
			pcall(function() inst:Destroy() end)
		end
	end
end

--=== FARTEST-POINT FROM ORIGIN HELPERS =================================
local function computeFarthestOwnedPathFromOrigin(player, ctx)
	ctx = ctx or ensureCtx(player)
	if not originLiveForPlayer(player, ctx) then return nil end
	ensureBfsSnapshot(player, ctx)
	if not ctx.bfsDist then return nil end
	local bestKey, bestLen = nil, -1
	local function considerCoord(coord)
		if not coord then return end
		local key = PathingModule.nodeKey(coord)
		local steps = ctx.bfsDist and ctx.bfsDist[key]
		if steps and (steps + 1) >= MIN_PATH_CELLS and steps > bestLen then
			bestKey = key
			bestLen = steps
		end
	end
	local deadEnds = PathingModule.getOwnedDeadEnds(player)
	if deadEnds and #deadEnds > 0 then
		for _, coord in ipairs(deadEnds) do considerCoord(coord) end
	end
	if not bestKey then
		for key,_ in pairs(ctx.bfsDist) do
			if ctx.bfsDist[key] then
				local coord = coordFromKey(key, ctx.coordCache or nil)
				considerCoord(coord)
			end
		end
	end
	if not bestKey then return nil end
	local coord = coordFromKey(bestKey, ctx.coordCache or nil)
	return coord and pathFromOrigin(ctx, coord) or nil
end

local function spawnOnce_OriginToFarthest(player, ctx)
	if ctx.suspended then return end
	if not originLiveForPlayer(player, ctx) then return end
	ensureBfsSnapshot(player, ctx)
	local gridPath = computeFarthestOwnedPathFromOrigin(player, ctx)
	if not gridPath then return end
	local worldPath = worldPathFor(ctx.plot, gridPath)
	local car = spawnCarAlongPath(player, ctx, gridPath, worldPath, "Farthest")
	if car then car:SetAttribute("DriveSession", true) end
	if TWO_WAY_ENABLED then
		if TWO_WAY_MODE == "mirror" or (TWO_WAY_MODE == "chance" and math.random() < TWO_WAY_CHANCE) then
			local revGrid = reversedGridPath(gridPath)
			if revGrid and #revGrid >= MIN_PATH_CELLS then
				local revWorld = worldPathFor(ctx.plot, revGrid)
				local revCar = spawnCarAlongPath(player, ctx, revGrid, revWorld, "Farthest")
				if revCar then revCar:SetAttribute("DriveSession", true) end
			end
		end
	end
end

--======================================================================
--  RECOMPUTE / SCHEDULER
--======================================================================
local recomputeQueued = {} -- [uid] = true

function ensureCtx(player)
	local uid = player.UserId
	local ctx = ctxByUserId[uid]
	local cfg = trafficConfigFor(player)
	if not ctx then
		ctx = {
			plot = getPlotForUserId(uid),
			suspended = false,
			tokens = (cfg.tokenMax or TOKEN_BUCKET_MAX) * 0.5,
			last = os.clock(),
			cars = {},
			carCount = 0,
			sinks = {},
			zoneSources = {},
			nextSpawnAt = os.clock() + (cfg.spawnInterval or SPAWN_INTERVAL_SEC) + math.random() * RANDOM_JITTER_SEC,

			-- [DRIVE MODE] per-player session
			drive = nil, -- { active=bool, loopTask=thread, startPos=Vector3 }
			nextDriveToggleAt = 0,
		}
		ctxByUserId[uid] = ctx
	end
	ctx.config = cfg
	ctx._tier = perfTier(player)
	applyTrafficConfig(ctx, player)
	-- keep a reference to player (for camera reset on stop)
	ctx.player = player
	if not ctx.plot or ctx.plot.Parent == nil then
		ctx.plot = getPlotForUserId(uid)
	end
	return ctx
end

local function recomputeForPlayer(player)
	local ctx = ensureCtx(player)
	if ctx.suspended then return end
	applyTrafficConfig(ctx, player)
	refreshOwnRoadZones(player, ctx)

	if originLiveForPlayer(player, ctx) then
		ensureBfsSnapshot(player, ctx)
		local mode = currentDispatchMode(ctx)
		if mode == "OriginToSinks" then
			ctx.sinks = computeSinksForPlayer(player, ctx)
			ctx.zoneSources = {}
			dprint(("Player %s sinks=%d (origin->sinks mode)"):format(player.Name, #ctx.sinks))
		else
			ctx.zoneSources = computeZoneSourcesForPlayer(player, ctx)
			ctx.sinks = {}
			dprint(("Player %s zoneSources=%d (zone->origin mode)"):format(player.Name, #ctx.zoneSources))
		end
	else
		ctx.sinks = {}
		ctx.zoneSources = {}
		ctx.bfsOriginKey = nil
		ctx.bfsDist = nil
		ctx.bfsParent = nil
		ctx.coordCache = nil
	end
end

local function scheduleRecompute(player, delaySec)
	local uid = player.UserId
	if recomputeQueued[uid] then return end
	recomputeQueued[uid] = true
	task.delay(delaySec or RECOMPUTE_DEBOUNCE, function()
		recomputeQueued[uid] = nil
		pcall(function() recomputeForPlayer(player) end)
	end)
end

local function ensureSpawnLoop(player)
	local uid = player.UserId
	local ctx = ensureCtx(player)
	if ctx.spawnLoop then return end
	ctx.spawnLoop = task.spawn(function()
		while Players:GetPlayerByUserId(uid) do
			applyTrafficConfig(ctx, player)
			if ctx.suspended then
				task.wait(0.5)
			else
				local now = os.clock()
				local nextAt = ctx.nextSpawnAt or now
				if now >= nextAt then
					pcall(function() spawnOnce(player, ctx) end)
					local cfg = ctx.config or trafficConfigFor(player)
					ctx.nextSpawnAt = os.clock() + (cfg.spawnInterval or SPAWN_INTERVAL_SEC) + math.random() * RANDOM_JITTER_SEC
				else
					task.wait(math.min(nextAt - now, 0.5))
				end
			end
		end
	end)
end

--========================
-- [DRIVE MODE] helpers
--========================
local function getHRP(player)
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart")
end

local function nearDriveCar(hrp: BasePart?, driveState)
	if not (driveState and driveState.cars and hrp) then return false end
	local pos = hrp.Position
	for car,_ in pairs(driveState.cars) do
		if car and car.Parent and car.PrimaryPart then
			if (car.PrimaryPart.Position - pos).Magnitude <= DRIVE_NEAR_CAR_RADIUS then
				return true
			end
		end
	end
	return false
end

local function movedTooMuch(player, driveState)
	if not driveState or not driveState.startPos then return false end
	if driveState.moveGraceUntil and os.clock() < driveState.moveGraceUntil then
		return false
	end
	local hrp = getHRP(player)
	if not hrp then return false end
	if nearDriveCar(hrp, driveState) then
		return false
	end
	-- 2D distance (XZ) + planar speed check
	local a = Vector2.new(hrp.Position.X, hrp.Position.Z)
	local b = Vector2.new(driveState.startPos.X, driveState.startPos.Z)
	local dist = (a - b).Magnitude
	local vel = hrp.AssemblyLinearVelocity
	local planarSpeed = Vector2.new(vel.X, vel.Z).Magnitude
	return (dist >= DRIVE_MOVE_DIST_STOP) or (planarSpeed >= DRIVE_MOVE_SPEED_STOP)
end

local function trackDriveCar(driveState, car)
	if not driveState or not car then return end
	driveState.cars = driveState.cars or {}
	driveState.cars[car] = true
	car:GetPropertyChangedSignal("Parent"):Connect(function()
		if not car.Parent and driveState.cars then
			driveState.cars[car] = nil
		end
	end)
end

local function destroyTrackedDriveCars(ctx, driveState, fadeTime)
	if not driveState or not driveState.cars then return end
	for car,_ in pairs(driveState.cars) do
		if ctx and ctx.cars then
			if ctx.cars[car] then
				ctx.cars[car] = nil
				ctx.carCount = math.max(0, (ctx.carCount or 1) - 1)
			end
		end
		if car and car.Parent then
			fadeOutAndDestroy(car, fadeTime or 0.4)
		end
		driveState.cars[car] = nil
	end
	driveState.cars = {}
end

local function interruptDriveSession(ctx, driveState)
	if not driveState then return end
	driveState.active = false
	destroyTrackedDriveCars(ctx, driveState, 0.35)
	if CameraAttachEvt and ctx and ctx.player then
		CameraAttachEvt:FireClient(ctx.player, nil)
	end
end

local function cleanupDriveSession(ctx, driveState)
	if not ctx then return end
	destroyTrackedDriveCars(ctx, driveState)
	if ctx.plot then
		for _, inst in ipairs(ctx.plot:GetDescendants()) do
			if inst:IsA("Model")
				and inst:GetAttribute("IsTraffic")
				and inst:GetAttribute("DriveSession")
			then
				pcall(function() inst:Destroy() end)
			end
		end
	end
	if CameraAttachEvt and ctx.player then
		CameraAttachEvt:FireClient(ctx.player, nil)
	end
	if ctx.drive == driveState then
		ctx.drive = nil
	end
end

local function stopDriveMode(ctx)
	if not ctx or not ctx.drive then return end
	local driveState = ctx.drive
	driveState.active = false
	if driveState.loopTask then
		task.cancel(driveState.loopTask)
	end
	driveState.loopTask = nil
	cleanupDriveSession(ctx, driveState)
end

local function startDriveMode(player, ctx)
	if ctx.drive then
		local prev = ctx.drive
		if prev.loopTask then
			task.cancel(prev.loopTask)
		end
		cleanupDriveSession(ctx, prev)
	end

	local hrp = getHRP(player)
	local driveState = {
		active = true,
		startPos = hrp and hrp.Position or nil,
		loopTask = nil,
		cars = {},
		moveGraceUntil = os.clock() + DRIVE_MOVE_GRACE_SEC,
	}
	ctx.drive = driveState

	driveState.loopTask = task.spawn(function()
		while driveState.active and Players:GetPlayerByUserId(player.UserId) do
			pcall(function() recomputeForPlayer(player) end)

			if not originLiveForPlayer(player, ctx) then
				task.wait(1.0)
			else
				local forwardPath = computeFarthestOwnedPathFromOrigin(player, ctx)

				if not forwardPath or #forwardPath < MIN_PATH_CELLS then
					task.wait(1.0)
				else
					local worldPath = worldPathFor(ctx.plot, forwardPath)
					local car = spawnCarAlongPath(player, ctx, forwardPath, worldPath, "Farthest", DRIVE_SPAWN_OVERRIDES)
					if car then
						car:SetAttribute("DriveSession", true)
						trackDriveCar(driveState, car)
					end

					if driveState.active and car and car.Parent and CameraAttachEvt then
						CameraAttachEvt:FireClient(player, car)
					end

					if TWO_WAY_ENABLED then
						if TWO_WAY_MODE == "mirror" or (TWO_WAY_MODE == "chance" and math.random() < TWO_WAY_CHANCE) then
							local reversePath = reversedGridPath(forwardPath)
							if reversePath and #reversePath >= MIN_PATH_CELLS then
								local revWorld = worldPathFor(ctx.plot, reversePath)
								local revCar = spawnCarAlongPath(player, ctx, reversePath, revWorld, "Farthest", DRIVE_SPAWN_OVERRIDES)
								if revCar then
									revCar:SetAttribute("DriveSession", true)
									trackDriveCar(driveState, revCar)
								end
							end
						end
					end

					local t0 = os.clock()
					while driveState.active and car and car.Parent and (os.clock() - t0) < CAR_LIFETIME_SEC do
						if movedTooMuch(player, driveState) then
							interruptDriveSession(ctx, driveState)
							break
						end
						task.wait(0.2)
					end

					local untilT = os.clock() + DRIVE_RESPAWN_DELAY
					while driveState.active and os.clock() < untilT do
						if movedTooMuch(player, driveState) then
							interruptDriveSession(ctx, driveState)
							break
						end
						task.wait(0.05)
					end
				end
			end
		end
		cleanupDriveSession(ctx, driveState)
	end)
end

-- Suspend/unsuspend during save reloads
local function suspendPlayerTraffic(player)
	local ctx = ensureCtx(player)
	ctx.suspended = true
	killAllTraffic(ctx)
	hardKillTrafficInPlot(ctx.plot)
	-- [DRIVE MODE] pause/stop on suspend
	stopDriveMode(ctx)
end
local function unsuspendPlayerTraffic(player)
	local ctx = ensureCtx(player)
	ctx.suspended = false
	scheduleRecompute(player, 0.05)
end

--======================================================================
--  EVENT WIRING
--======================================================================
-- Feature flags
FireSupportEvt.Event:Connect(function(player)
	fireSupport[player.UserId] = true
	print(("[UnifiedTraffic] Fire support ENABLED for %s."):format(player.Name))
end)
PoliceSupportEvt.Event:Connect(function(player)
	policeSupport[player.UserId] = true
	print(("[UnifiedTraffic] Police support ENABLED for %s."):format(player.Name))
end)
HealthSupportEvt.Event:Connect(function(player)
	healthSupport[player.UserId] = true
	print(("[UnifiedTraffic] Health support ENABLED for %s."):format(player.Name))
end)
TrashSupportEvt.Event:Connect(function(player)
	trashSupport[player.UserId] = true
	print(("[UnifiedTraffic] Trash support ENABLED for %s."):format(player.Name))
end)
BusSupportUnlocked.Event:Connect(function(player)
	busSupport[player.UserId] = true
	print(("[UnifiedTraffic] Bus support ENABLED for %s."):format(player.Name))
	if #templates.bus == 0 and not _busWarnedMissing then
		warn("[UnifiedTraffic] Bus support enabled but no bus models found under Cars.Buses/Busses.")
		_busWarnedMissing = true
	end
end)
BusSupportRevoked.Event:Connect(function(player)
	busSupport[player.UserId] = nil
	print(("[UnifiedTraffic] Bus support DISABLED for %s."):format(player.Name))
end)

-- [DRIVE MODE] Toggle on the same event:
--   1st click -> enable loop (attach camera on first leg)
--   2nd click -> disable loop (kill drive cars + reset camera)
SpawnCarToFarthestEvt.OnServerEvent:Connect(function(player)
	local ctx = ensureCtx(player)
	local now = os.clock()
	if ctx.nextDriveToggleAt and now < ctx.nextDriveToggleAt then
		return
	end

	-- If not active, turn ON and start loop, attach camera on first leg
	if not ctx.drive or not ctx.drive.active then
		ctx.nextDriveToggleAt = now + DRIVE_TOGGLE_DEBOUNCE
		startDriveMode(player, ctx)
		print(("[UnifiedTraffic] DriveMode ENABLED for %s"):format(player.Name))
		return
	end

	-- If already active, turn OFF (hard stop)
	ctx.nextDriveToggleAt = now + DRIVE_TOGGLE_DEBOUNCE
	stopDriveMode(ctx)
	print(("[UnifiedTraffic] DriveMode DISABLED for %s"):format(player.Name))
end)

-- Zone graph changes → recompute
local function onZoneAdded(player, zoneId, zoneData)           scheduleRecompute(player, RECOMPUTE_DEBOUNCE) end
local function onZoneRemoved(player, zoneId, mode, gridList)   scheduleRecompute(player, RECOMPUTE_DEBOUNCE) end
local function onZoneReCreated(player, zoneId, mode, gridList) scheduleRecompute(player, RECOMPUTE_DEBOUNCE) end
local function onZonePopulated(player, zoneId, _)              scheduleRecompute(player, RECOMPUTE_DEBOUNCE) end

ZoneAddedEvt.Event:Connect(onZoneAdded)
ZoneRemovedEvt.Event:Connect(onZoneRemoved)
ZoneReCreatedEvt.Event:Connect(onZoneReCreated)
ZonePopulatedEvt.Event:Connect(onZonePopulated)

-- Save reload gates
if RequestReloadFromCurrentEvt then
	RequestReloadFromCurrentEvt.Event:Connect(function(player) suspendPlayerTraffic(player) end)
end
local function attachNetworksPostLoad(ev)
	if ev and ev.IsA and ev:IsA("BindableEvent") then
		ev.Event:Connect(function(player) unsuspendPlayerTraffic(player) end)
	end
end
attachNetworksPostLoad(NetworksPostLoadEvt)
BindableEvents.ChildAdded:Connect(function(ch)
	if ch.Name == "NetworksPostLoad" and ch:IsA("BindableEvent") then
		attachNetworksPostLoad(ch)
	end
end)

-- Player lifecycle
Players.PlayerAdded:Connect(function(plr)
	local ctx = ensureCtx(plr)
	scheduleRecompute(plr, 0.25)
	ensureSpawnLoop(plr)
end)
Players.PlayerRemoving:Connect(function(plr)
	local uid = plr.UserId
	local ctx = ctxByUserId[uid]
	if ctx then
		ctx.suspended = true
		killAllTraffic(ctx)
		stopDriveMode(ctx) -- [DRIVE MODE] cleanup
		ctxByUserId[uid] = nil
	end
	fireSupport[uid] = nil
	policeSupport[uid] = nil
	healthSupport[uid] = nil
	trashSupport[uid] = nil
	busSupport[uid]  = nil
end)

for _, p in ipairs(Players:GetPlayers()) do
	local ctx = ensureCtx(p)
	scheduleRecompute(p, 0.25)
	ensureSpawnLoop(p)
end

task.spawn(function()
	while true do
		task.wait(RESCAN_PERIODIC_SEC)
		for _, p in ipairs(Players:GetPlayers()) do
			scheduleRecompute(p, 0)
		end
	end
end)

local defaultDispatchMode = (TrafficTierConfig["desktop-high"] and TrafficTierConfig["desktop-high"].dispatchMode) or DISPATCH_MODE
print(("[UnifiedTraffic] online - DispatchMode=%s; origin=(%d,%d) - Bus/Service variants (Fire/Police/Health/Trash) where supported")
	:format(defaultDispatchMode, SOURCE_COORD.x, SOURCE_COORD.z))
