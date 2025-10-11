local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService         = game:GetService("HttpService")

---------------------------------------------------------------------
-- Config
---------------------------------------------------------------------
local DEBUG                    = false
local MIN_PUSH_INTERVAL_SEC    = 0.25     -- don’t send more often than this per player
local MAX_COALESCE_DELAY_SEC   = 0.50     -- if many changes happen, flush at this bound
local HAPPINESS_DELTA_ABS      = 1        -- only push happiness if +/- this changed
local PCT_LABEL_DELTA_ABS      = 1        -- only update “Usage: %” if percent changed >= this
local BIG_NUMBER_ABBR_THRESHOLD= 1000     -- unchanged from your logic

local function LOG(...)
	if DEBUG then print("[CentralUIStatsModule]", ...) end
end

---------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------
local Events             = ReplicatedStorage:WaitForChild("Events")
local RemoteEvents       = Events:WaitForChild("RemoteEvents")
local UIUpdateEvent      = RemoteEvents:WaitForChild("UpdateStatsUI")
local HappinessUpdateEvt = RemoteEvents:WaitForChild("UpdateHappiness")
local Bindable           = Events:WaitForChild("BindableEvents")
local StatsChanged       = Bindable:WaitForChild("StatsChanged")
local XPChanged          = Bindable:WaitForChild("XPChanged")

local Balancing                   = ReplicatedStorage:WaitForChild("Balancing")
local BalanceEconomy              = require(Balancing:WaitForChild("BalanceEconomy"))
local PlayerDataInterfaceService  = require(ServerScriptService.Services.PlayerDataInterfaceService)
local CityInteractions            = require(game.ServerScriptService.Build.Zones.ZoneManager.CityInteraction)

-- NEW: client handshake ("I'm ready, send me my UI now")
local RequestStatsUI = RemoteEvents:FindFirstChild("RequestStatsUI")
if not RequestStatsUI then
	RequestStatsUI = Instance.new("RemoteEvent")
	RequestStatsUI.Name = "RequestStatsUI"
	RequestStatsUI.Parent = RemoteEvents
end

-- other modules
local LocalizationLoader    = require(ReplicatedStorage.Localization.Localizing)
local PlayerDataService	    = require(ServerScriptService.Services.PlayerDataService)
local DistrictStatsModule   = require(game.ServerScriptService.Build.Districts.Stats.DistrictStatsModule)
local ProgressionModule     = require(game.ServerScriptService.Build.Districts.Stats.Progression)
local ZoneTracker           = require(game.ServerScriptService.Build.Zones.ZoneManager.ZoneTracker)
local Abr                   = require(ReplicatedStorage.Scripts.UI.Abrv)
local ZoneRequirementsChecker = require(game.ServerScriptService.Build.Zones.ZoneManager.ZoneRequirementsCheck)

---------------------------------------------------------------------
-- Internal state (per-player)
---------------------------------------------------------------------
local lastSentAt        = {}  -- [player] = timestamp (os.clock)
local pendingFlush      = {}  -- [player] = true if a flush is scheduled
local lastPayloadHash   = {}  -- [player] = string hash (JSON md5-like)
local lastHappiness     = {}  -- [player] = number
local lastUsagePct      = {}  -- [player] = number

-- small localization template cache: key -> (lang -> string)
local locCache = {}     -- locCache[key] = { [lang] = value }

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function _loc(key, lang, fallbackFmt)
	locCache[key] = locCache[key] or {}
	local cached = locCache[key][lang]
	if cached ~= nil then return cached end

	local tpl = LocalizationLoader.get(key, lang)
	if type(tpl) ~= "string" or #tpl == 0 then
		tpl = fallbackFmt or "%s"
	end
	locCache[key][lang] = tpl
	return tpl
end

-- abbreviate any big numbers in the payload (leave sensitive keys raw)
local function applyAbbreviation(t)
	for k, v in pairs(t) do
		if type(v) == "number"
			and k ~= "xp"
			and k ~= "level"
			and k ~= "xpAtCurrentLevel"
			and k ~= "nextLevelXP"
			and k ~= "balance"
			and k ~= "income"
			and k ~= "powerRequired"
			and k ~= "powerProduced"
			and math.abs(v) >= BIG_NUMBER_ABBR_THRESHOLD
		then
			t[k] = Abr.abbreviateNumber(v)
		end
	end
end

local function tileHasAllRequirements(player, zoneId, gx, gz)
	return ZoneTracker.getTileRequirement(player, zoneId, gx, gz, "Road")  == true
		and ZoneTracker.getTileRequirement(player, zoneId, gx, gz, "Water") == true
		and ZoneTracker.getTileRequirement(player, zoneId, gx, gz, "Power") == true
end

-- Per-zone tick income using per-tile pollution penalty and positive bonus (via CityInteractions)
local function calculateZoneIncome(player, zoneData)
	local total = 0
	for _, coord in ipairs(zoneData.gridList) do
		if tileHasAllRequirements(player, zoneData.zoneId, coord.x, coord.z) then
			local state = ZoneTracker.getGridWealth(player, zoneData.zoneId, coord.x, coord.z) or "Poor"
			local conf  = BalanceEconomy.StatConfig[zoneData.mode]
			conf        = conf and conf[state]
			local base  = (conf and conf.income) or 0

			-- NET multiplier = negative pollution * positive mixed-use bonus
			local netMul = CityInteractions.getTileIncomeNetMultiplier(player, zoneData.zoneId, coord.x, coord.z, zoneData.mode)

			-- whole numbers per tile
			local tileIncome = math.floor(base * netMul + 0.5)
			total += tileIncome
		end
	end

	if PlayerDataInterfaceService.HasGamepass(player, "x2 Money") then
		total = total * 2
	end

	return total -- integer
end

local function computeTickIncome(player)
	-- base income across zones (per-tile calc)
	local total = 0
	local statsByZone = DistrictStatsModule.getStatsForPlayer(player.UserId) or {}
	for zoneId, _ in pairs(statsByZone) do
		local zone = ZoneTracker.getZoneById(player, zoneId)
		if zone then
			total += calculateZoneIncome(player, zone)
		end
	end

	-- capacity coverage (use EFFECTIVE totals so mixed-use demand shows)
	local totalsReq = ZoneRequirementsChecker.getEffectiveTotals(player)
		or DistrictStatsModule.getTotalsForPlayer(player)
		or { water = 0, power = 0 }

	local produced  = ZoneRequirementsChecker.getEffectiveProduction(player)
		or DistrictStatsModule.getUtilityProduction(player)
		or { water = 0, power = 0 }

	local coverW    = (totalsReq.water > 0) and math.min(1, (produced.water or 0) / totalsReq.water) or 1
	local coverP    = (totalsReq.power > 0) and math.min(1, (produced.power or 0) / totalsReq.power) or 1
	local coverage  = math.min(coverW, coverP)

	local rate = BalanceEconomy.IncomeRate and BalanceEconomy.IncomeRate.TICK_INCOME or 1
	return math.floor(total * coverage * rate + 0.5)
end

-- Build the payload (pure, no side effects)
local function buildPayload(player)
	local PlayerData = PlayerDataService.GetData(player)
	if not PlayerData then return nil end

	local SaveData = PlayerDataService.GetSaveFileData(player)
	if not SaveData then return nil end

	local stats     = DistrictStatsModule.getStatsForPlayer(player.UserId) or {}

	-- EFFECTIVE production & demand (reflects mixed-use)
	local utilities = ZoneRequirementsChecker.getEffectiveProduction(player)
		or DistrictStatsModule.getUtilityProduction(player)
		or { water = 0, power = 0 }

	local effTotals = ZoneRequirementsChecker.getEffectiveTotals(player)
		or { water = 0, power = 0 }

	-- sum totals across all districts (keep pop/income from DSM; replace demand with effective)
	local total = { population = 0, income = 0, water = 0, power = 0 }
	for _, s in pairs(stats) do
		total.population += s.population or 0
		total.income     += s.income     or 0
	end
	total.water = effTotals.water or 0
	total.power = effTotals.power or 0

	local lang    = PlayerData.Language
	local prodTpl = _loc("Produced WATER", lang, "Produced: %s")
	local usedTpl = _loc("Used WATER",     lang, "Used: %s")
	local usageTpl= _loc("Usage WATER",    lang, "Usage: %s%%")

	local producedNum = tonumber(utilities.water) or 0
	local usedNum     = tonumber(total.water) or 0

	local producedText = string.format(prodTpl, Abr.abbreviateNumber(producedNum))
	local usedText     = string.format(usedTpl, Abr.abbreviateNumber(usedNum))

	local pct = 0
	if producedNum > 0 then
		pct = math.floor((usedNum / producedNum) * 100 + 0.5)
	end
	local usageText = string.format(usageTpl, pct)

	local happiness = ZoneTracker.computeInfrastructureHappiness(player)

	local result = {
		population    = total.population,
		income        = computeTickIncome(player),
		waterRequired = total.water,
		powerRequired = total.power,
		waterProduced = producedNum,
		powerProduced = tonumber(utilities.power) or 0,

		-- formatted labels
		producedLabel = producedText,
		usedLabel     = usedText,
		usageLabel    = usageText,

		-- happiness metric
		happiness     = happiness,

		balance       = (SaveData.economy and SaveData.economy.money) or 0,
		xp            = SaveData.xp or 0,
		level         = SaveData.cityLevel or 0,
		zoneDemand    = ZoneTracker.getZoneDemand(player),

		lang          = lang,
	}
	result.xpAtCurrentLevel = ProgressionModule.getXPAtLevelStart(SaveData.cityLevel or 0)
	result.nextLevelXP      = ProgressionModule.getXPToReachLevel(SaveData.cityLevel or 0)

	applyAbbreviation(result)

	-- attach a few ephemeral values for diffing decisions (not sent to client)
	result.__usagePct = pct

	return result
end

-- Return a stable hash for dedupe (ignores volatile keys we don’t want to compare)
local function hashPayloadForDedupe(payload)
	local copy = {}
	for k, v in pairs(payload) do
		if k ~= "producedLabel" and k ~= "usedLabel" and k ~= "usageLabel" and k ~= "__usagePct" then
			copy[k] = v
		end
	end
	-- Stable JSON string
	local ok, json = pcall(HttpService.JSONEncode, HttpService, copy)
	if not ok then
		return tostring(os.clock()) -- fallback changes each time to avoid false positives
	end
	-- Poor-man’s hash: deterministic but cheap; good enough to dedupe
	return HttpService:GenerateGUID(false) .. ":" .. #json .. ":" .. string.sub(json, 1, 32)
end

---------------------------------------------------------------------
-- Sending (now throttled + diffed)
---------------------------------------------------------------------
local CentralUIStatsModule = {}

-- internal, does the actual fire after diff checks
local function _sendNow(player, payload)
	if not (player and player:IsA("Player")) then return end
	if not payload then return end

	-- HAPPINESS: only if meaningfully changed
	local hap = tonumber(payload.happiness) or 0
	local lastHap = lastHappiness[player]
	local pushHap = (lastHap == nil) or (math.abs(hap - lastHap) >= HAPPINESS_DELTA_ABS)

	-- Usage % label: only if percent meaningfully changed
	local usagePct = tonumber(payload.__usagePct) or 0
	local lastPct = lastUsagePct[player]
	local pushPct = (lastPct == nil) or (math.abs(usagePct - lastPct) >= PCT_LABEL_DELTA_ABS)

	-- Deduplicate whole payload (ignoring human-readable labels)
	local hash = hashPayloadForDedupe(payload)
	local same = (lastPayloadHash[player] == hash)

	if same and not pushHap and not pushPct then
		LOG(player.Name, "suppressed identical payload")
		return
	end

	-- Update lasts
	lastPayloadHash[player] = hash
	if pushHap then lastHappiness[player] = hap end
	if pushPct then lastUsagePct[player] = usagePct end

	-- Strip the internal field before sending
	payload.__usagePct = nil

	-- Send (Happiness first)
	if pushHap then
		HappinessUpdateEvt:FireClient(player, hap)
	end
	UIUpdateEvent:FireClient(player, payload)

	LOG(player.Name, "pushed UI (hap=", pushHap, ", pct=", pushPct, ")")
end

-- schedule: coalesce bursts and obey MIN_PUSH_INTERVAL_SEC
local function scheduleSend(player)
	if pendingFlush[player] then return end
	pendingFlush[player] = true

	-- compute when we’re allowed to send next
	local now      = os.clock()
	local earliest = (lastSentAt[player] or 0) + MIN_PUSH_INTERVAL_SEC
	local delaySec = math.max(0, math.min(earliest - now, MAX_COALESCE_DELAY_SEC))

	task.delay(delaySec, function()
		pendingFlush[player] = nil
		lastSentAt[player] = os.clock()

		local payload = buildPayload(player)
		_sendNow(player, payload)
	end)
end

-- public API kept for backward compatibility
function CentralUIStatsModule.sendStatsToUI(player)
	-- This call now uses scheduling (single place to control rate)
	scheduleSend(player)
end

function CentralUIStatsModule.init()
	-- Push on any stats/xp change (coalesced)
	StatsChanged.Event:Connect(function(playerOrUserId)
		-- Some callers fire with userId; normalize to Player
		local player = playerOrUserId
		if typeof(playerOrUserId) == "number" then
			player = Players:GetPlayerByUserId(playerOrUserId)
		end
		if player then scheduleSend(player) end
	end)

	XPChanged.Event:Connect(function(playerOrUserId)
		local player = playerOrUserId
		if typeof(playerOrUserId) == "number" then
			player = Players:GetPlayerByUserId(playerOrUserId)
		end
		if player then scheduleSend(player) end
	end)

	-- Client handshake: push immediately (bypasses delay for first frame)
	RequestStatsUI.OnServerEvent:Connect(function(player)
		lastSentAt[player] = 0 -- allow immediate
		local payload = buildPayload(player)
		_sendNow(player, payload)
	end)

	-- Also push once on join (small delay so PlayerData is ready)
	Players.PlayerAdded:Connect(function(p)
		task.delay(0.25, function()
			if p.Parent then
				lastSentAt[p] = 0
				local payload = buildPayload(p)
				_sendNow(p, payload)
			end
		end)
	end)

	-- Cleanup on leave
	Players.PlayerRemoving:Connect(function(p)
		lastSentAt[p]      = nil
		pendingFlush[p]    = nil
		lastPayloadHash[p] = nil
		lastHappiness[p]   = nil
		lastUsagePct[p]    = nil
	end)
end

return CentralUIStatsModule