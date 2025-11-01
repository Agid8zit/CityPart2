--[[
Script Order: 3
Script Name: ZoneRequirementsCheck.lua
Description: Module that checks zone requirements after creation,
             but defers alarm creation until BuildingGeneratorModule fires ZonePopulated.
Dependencies: ZoneTracker.lua, ZoneValidation.lua
Dependents: None
]]--
local ZoneRequirementsChecker = {}
ZoneRequirementsChecker.__index = ZoneRequirementsChecker

-- CONFIGURATION
local DEBUG = false
local SEARCH_RADIUS = 4      -- How far in each direction to search (4 => 9x9 area when cellSize=1)
local DEBOUNCE_TIME = 0.5    -- Seconds to debounce event triggers

-- DEBUG PRINT FUNCTION
local function debugPrint(...)
	if DEBUG then
		print("[ZoneRequirementsChecker]", ...)
	end
end

local TweenService = game:GetService("TweenService")

-- SERVICES AND MODULES
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BindableEvents = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents")
local RemoteEvents = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local NetworkReadyEvent = BindableEvents:WaitForChild("NetworkReady")

local DistrictStatsModule = require(ServerScriptService.Build.Districts.Stats.DistrictStatsModule)
local NetworkManager = require(ServerScriptService.Build.Infrastructure.InfrastructureAlgorithm)
local ZoneTrackerModule = require(script.Parent:WaitForChild("ZoneTracker"))

local GridScripts = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Grid")
local GridUtil    = require(GridScripts:WaitForChild("GridUtil"))
local GridConfig  = require(GridScripts:WaitForChild("GridConfig"))
local notifyPlayerEvent = RemoteEvents:WaitForChild("NotifyPlayer")
local UtilityAlertsRE = RemoteEvents:FindFirstChild("UtilityAlerts")
local CityInteractions =require(script.Parent.CityInteraction)

local Balance = require(game.ReplicatedStorage.Balancing.BalanceEconomy)

local WigiPlacedEvent = BindableEvents:WaitForChild("Wigw8mPlaced")

local boundsCache = {}

local SHOW_POPULATING_ALARMS = true       -- master switch for temp alarms
local TEMP_ALARM_FOLDER_NAME = "TempAlarms"
-- Prevent bulk temp alarms from infra events / full-zone scans before population
local SHOW_TEMP_FROM_INFRA_EVENTS = false

-- ==== PERFORMANCE / LOAD-AWARE TUNABLES (ADDED) ===========================
local TEMP_ALARM_BUDGET_MS         = 4      -- soft time budget per update call
local TEMP_ALARM_YIELD_EVERY_OPS   = 200    -- yield cadence for large batches
local LOAD_AWARE_SKIP_TEMP_ALARMS  = true   -- skip temp alarms during world reload

-- >>> ADDED: definitive requirement name mapping for defensive checks
local REQ_NAME_FOR_ALARM = {
	AlarmRoad  = "Road",
	AlarmWater = "Water",
	AlarmPower = "Power",
}

-- >>> ADDED: last-writer-wins sequencing to eliminate stale re-adds
local AlarmSeq     = {} -- [uid][zoneId][alarmType] = seq
local TempAlarmSeq = {} -- [uid][zoneId][alarmType] = seq
local function _getSeq(tbl, player, zoneId, alarmType)
	local uid = player and player.UserId
	if not uid then return 0 end
	local a = tbl[uid]; if not a then return 0 end
	local b = a[zoneId]; if not b then return 0 end
	return b[alarmType] or 0
end
local function _bumpSeq(tbl, player, zoneId, alarmType)
	local uid = player and player.UserId
	if not uid then return 0 end
	tbl[uid] = tbl[uid] or {}
	tbl[uid][zoneId] = tbl[uid][zoneId] or {}
	local nextSeq = (tbl[uid][zoneId][alarmType] or 0) + 1
	tbl[uid][zoneId][alarmType] = nextSeq
	return nextSeq
end
local function _setSeq(tbl, player, zoneId, alarmType, seq)
	local uid = player and player.UserId
	if not uid then return end
	tbl[uid] = tbl[uid] or {}
	tbl[uid][zoneId] = tbl[uid][zoneId] or {}
	tbl[uid][zoneId][alarmType] = seq
end
local function _clearSeqsForZone(player, zoneId)
	local uid = player and player.UserId
	if not uid then return end
	if AlarmSeq[uid]     then AlarmSeq[uid][zoneId]     = nil end
	if TempAlarmSeq[uid] then TempAlarmSeq[uid][zoneId] = nil end
end
-- ========================================================================

-- Track world-reload windows fired by SaveManager (if present)
local WorldReloadActiveByUid = {}

do
	local WorldReloadBeginBE = BindableEvents:FindFirstChild("WorldReloadBegin")
	local WorldReloadEndBE   = BindableEvents:FindFirstChild("WorldReloadEnd")

	if WorldReloadBeginBE and WorldReloadBeginBE:IsA("BindableEvent") then
		WorldReloadBeginBE.Event:Connect(function(player)
			if player and player.UserId then
				WorldReloadActiveByUid[player.UserId] = true
				-- >>> ADDED: on reload begin, also clear alarm sequences for safety
				_clearSeqsForZone(player, "ALL_ZONES_SEQ_SENTINEL") -- noop pattern; just keeping symmetry
			end
		end)
	end
	if WorldReloadEndBE and WorldReloadEndBE:IsA("BindableEvent") then
		WorldReloadEndBE.Event:Connect(function(player)
			if player and player.UserId then
				WorldReloadActiveByUid[player.UserId] = nil
				-- >>> ADDED: sequences not strictly needed to clear here since zone-wise clears happen elsewhere
			end
		end)
	end
end

local AGGREGATE_CACHE_TTL = 0.25
local aggregateTotalsCache = {}
local aggregateProductionCache = {}

local function copyAggregate(src)
	local dest = { water = 0, power = 0 }
	if src then
		dest.water = tonumber(src.water) or 0
		dest.power = tonumber(src.power) or 0
	end
	return dest
end

local function getAggregateCache(cache, player)
	if not (player and player.UserId) then return nil end
	local entry = cache[player.UserId]
	if not entry then return nil end

	local now = os.clock()
	if entry.expiry and entry.expiry > now then
		return copyAggregate(entry.value)
	end

	cache[player.UserId] = nil
	return nil
end

local function setAggregateCache(cache, player, totals)
	if not (player and player.UserId) then return end
	cache[player.UserId] = {
		value = copyAggregate(totals),
		expiry = os.clock() + AGGREGATE_CACHE_TTL,
	}
end

local function invalidateAggregateCaches(player)
	if not (player and player.UserId) then return end
	aggregateTotalsCache[player.UserId] = nil
	aggregateProductionCache[player.UserId] = nil
end

Players.PlayerRemoving:Connect(function(player)
	invalidateAggregateCaches(player)
end)

-- ========================================================================

local function getGlobalBoundsForPlot(plot)
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
	if #terrains == 0 and testTerrain then
		table.insert(terrains, testTerrain)
	end

	local gb = GridConfig.calculateGlobalBounds(terrains)
	boundsCache[plot] = { bounds = gb, terrains = terrains }
	return gb, terrains
end

local function collectTerrains(playerPlot)
	local terrains   = {}
	local unlocks    = playerPlot:FindFirstChild("Unlocks")
	if unlocks then
		for _, z in ipairs(unlocks:GetChildren()) do
			for _, part in ipairs(z:GetChildren()) do
				if part:IsA("BasePart") and part.Name:match("^Segment%d+$") then
					table.insert(terrains, part)
				end
			end
		end
	end

	local testTerrain = playerPlot:FindFirstChild("TestTerrain")
	if #terrains == 0 and testTerrain then
		table.insert(terrains, testTerrain)
	end
	return terrains
end

local function gridToWorld(playerPlot, gx, gz)
	local referenceTerrain = playerPlot:FindFirstChild("TestTerrain")
	if not referenceTerrain then
		-- fallback keeps the original Y logic
		return Vector3.new(0, GridConfig.Y_OFFSET, 0)
	end

	-- global‑bounds X/Z
	local gb, terrains   = getGlobalBoundsForPlot(playerPlot)
	local worldX, _, worldZ =
		GridUtil.globalGridToWorldPosition(gx, gz, gb, terrains)

	-- Y computation stays exactly as before
	local worldY = referenceTerrain.Position.Y
		+ (referenceTerrain.Size.Y / 2)
		+ GridConfig.Y_OFFSET

	return Vector3.new(worldX, worldY, worldZ)
end

local _happyDirty = {}

local function scheduleHappinessPublish(player, delaySec)
	local uid = player and player.UserId
	if not uid then return end
	if _happyDirty[uid] then return end
	_happyDirty[uid] = true
	task.delay(delaySec or 0.05, function()
		_happyDirty[uid] = nil
		ZoneRequirementsChecker.recomputeAndPublishHappiness(player)
	end)
end

local getProductionSynergyWidth
local computeProductionMultiplierForProducer

-- Component-aware production/requirement for a seed zone's network.
-- Uses DSU from NetworkManager + ProductionConfig for sources + DSM stats for demand.
local function getComponentBudget(player, seedZoneId, networkType, opts)
	opts = opts or {}
	local gridAware = opts.gridAware == true

	local ids = NetworkManager.getConnectedZoneIds(player, seedZoneId, networkType)
	if not ids or #ids == 0 then return 0, 0 end

	local produced, required = 0, 0
	local statsByZone = DistrictStatsModule.getStatsForPlayer(player.UserId)

	for _, zid in ipairs(ids) do
		local z = ZoneTrackerModule.getZoneById(player, zid)
		if z then
			if NetworkManager.isSourceZone(z, networkType) then
				local pcfg = Balance.ProductionConfig[z.mode]
				if pcfg and ((networkType == "Water" and pcfg.type == "water")
					or (networkType == "Power" and pcfg.type == "power")) then
					-- NEW: apply production synergy multiplier based on nearby zones
					local mul = computeProductionMultiplierForProducer(player, z.zoneId, z.mode)
					produced += (pcfg.amount or 0) * mul
				end
			elseif ZoneRequirementsChecker.isBuildingZone(z.mode) then
				if gridAware then
					local cfgTbl = Balance.StatConfig[z.mode]
					if cfgTbl and z.gridList then
						for _, c in ipairs(z.gridList) do
							local reachable = (networkType == "Water")
								and ZoneRequirementsChecker.zoneHasWater(player, z.zoneId, {c}, SEARCH_RADIUS)
								or ZoneRequirementsChecker.zoneHasPower(player, z.zoneId, {c}, SEARCH_RADIUS)
							if reachable then
								local w = ZoneTrackerModule.getGridWealth(player, z.zoneId, c.x, c.z) or "Poor"
								local T = cfgTbl[w]
								if T then
									required += (networkType == "Water") and (T.water or 0) or (T.power or 0)
								end
							end
						end
					end
				else
					local s = statsByZone[zid]
					if s then
						if networkType == "Water" then required += (s.water or 0) end
						if networkType == "Power" then required += (s.power or 0) end
					else
						local cfgTbl = Balance.StatConfig[z.mode]
						if cfgTbl and z.gridList then
							for _, c in ipairs(z.gridList) do
								local w = ZoneTrackerModule.getGridWealth(player, zid, c.x, c.z) or "Poor"
								local T = cfgTbl[w]
								if T then
									if networkType == "Water" then required += (T.water or 0) end
									if networkType == "Power" then required += (T.power or 0) end
								end
							end
						end
					end
				end
			end
		end
	end

	return produced, required
end

-- === Deferred production gate for recreates ===
local function getProductionSnapshot(player)
	local totals = { water = 0, power = 0 }
	local statsByZone = DistrictStatsModule.getStatsForPlayer(player.UserId)
	for _, stats in pairs(statsByZone) do
		totals.water  += (stats.water  or 0)
		totals.power  += (stats.power  or 0)
	end
	local produced = DistrictStatsModule.getUtilityProduction(player)
	return totals, produced
end

local function productionSufficientForZone(player, zoneId)
	local wP, wR = getComponentBudget(player, zoneId, "Water", { gridAware = true })
	local pP, pR = getComponentBudget(player, zoneId, "Power", { gridAware = true })
	return (wP >= wR), (pP >= pR)
end

-- per-player bounded retry queue
local pendingRecreate = {} -- [uid][zoneId] = {mode=..., gridList=..., tries=...}

local function scheduleDeferredRecreateEval(player, zoneId, mode, gridList)
	local uid = player.UserId
	pendingRecreate[uid] = pendingRecreate[uid] or {}
	if pendingRecreate[uid][zoneId] then return end -- already queued

	pendingRecreate[uid][zoneId] = { mode = mode, gridList = gridList, tries = 0 }
	task.spawn(function()
		local MAX_TRIES, SLEEP = 20, 0.15
		while pendingRecreate[uid] and pendingRecreate[uid][zoneId] do
			local rec = pendingRecreate[uid][zoneId]; rec.tries += 1
			local wOK, pOK = productionSufficientForZone(player, zoneId)
			if wOK and pOK then
				ZoneRequirementsChecker.checkZoneRequirements(player, zoneId, mode, gridList, { runSync = true })
				scheduleHappinessPublish(player, 0.01)
				pendingRecreate[uid][zoneId] = nil
				if next(pendingRecreate[uid]) == nil then pendingRecreate[uid] = nil end
				break
			end
			if rec.tries >= MAX_TRIES then
				if DEBUG then
					warn(("[ZoneReq] Deferred recreate timed out for %s after %d tries; running sync."):format(zoneId, rec.tries))
				end
				ZoneRequirementsChecker.checkZoneRequirements(player, zoneId, mode, gridList, { runSync = true })
				scheduleHappinessPublish(player, 0.01)
				pendingRecreate[uid][zoneId] = nil
				if next(pendingRecreate[uid]) == nil then pendingRecreate[uid] = nil end
				break
			end
			task.wait(SLEEP)
		end
	end)
end

--For rechecking on reload from save
local zoneReCreatedEvent = BindableEvents:WaitForChild("ZoneReCreated")
zoneReCreatedEvent.Event:Connect(function(player, zoneId, mode, gridList)
	-- Rebuild spatial indices and run pending checks like a fresh placement
	ZoneRequirementsChecker.onZoneCreated(player, zoneId, mode, gridList)

	-- Building zones: gate on production; defer if insufficient to avoid false negatives
	if ZoneRequirementsChecker.isBuildingZone(mode) then
		local wOK, pOK = productionSufficientForZone(player, zoneId)
		if wOK and pOK then
			ZoneRequirementsChecker.checkZoneRequirements(player, zoneId, mode, gridList, { runSync = true })
			scheduleHappinessPublish(player, 0.01)
		else
			if DEBUG then
				print(("[ZoneReq] Recreate: deferring check for '%s' (production insufficient)."):format(zoneId))
			end
			scheduleDeferredRecreateEval(player, zoneId, mode, gridList)
		end
	end
end)

-- Building Zones (for quick checks on roads/water)
local buildingZoneTypes = {
	Residential = true,
	Commercial = true,
	Industrial = true,
	ResDense = true,
	CommDense = true,
	IndusDense = true,
}

function ZoneRequirementsChecker.isBuildingZone(mode)
	return buildingZoneTypes[mode] == true
end

local powerInfrastructureModes = {
	PowerLines           = true,
	SolarPanels          = true,
	WindTurbine          = true,
	CoalPowerPlant       = true,
	GasPowerPlant        = true,
	GeothermalPowerPlant = true,
	NuclearPowerPlant    = true,
}

local waterInfrastructureModes = {
	WaterTower = true,
	WaterPipe  = true,
	WaterPlant = true,
	PurificationWaterPlant = true,
	MolecularWaterPlant = true,
}

local roadInfrastructureModes = {
	DirtRoad = true,
	Pavement = true,
	Highway  = true,
}

local ROAD_SOURCE_X, ROAD_SOURCE_Z = 0, 0
----------------------------------------------------------------------
-- 1) ZONE REQUIREMENT CACHE (both tile-level and zone-level)
----------------------------------------------------------------------
local zoneRequirementCache = {}

-- Debounce Table
local debounceTable = {}
local AlarmPool = {} 
-------------------------------------------------------------------
-- SHARED BOBBING SYSTEM
--------------------------------------------------------------------
local USE_SHARED_BOBBING = true      -- flip to false to return to Tween mode
local BOB_SPEED     = 2              -- radians / sec
local BOB_AMPLITUDE = 0.5            -- studs

local RunService     = game:GetService("RunService")
local ActiveAlarms   = {}            -- [part] = { base = Vector3, phase = number }
local heartbeatConn  -- lazily made

local function attachSharedBobbing(part, basePos)
	if not USE_SHARED_BOBBING then return end

	ActiveAlarms[part] = { base = basePos, phase = math.random() * math.pi * 2 }

	if heartbeatConn then return end
	local t = 0
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		t += dt
		for p,info in pairs(ActiveAlarms) do
			if p.Parent then
				p.Position = info.base + Vector3.new(0, math.sin(t*BOB_SPEED + info.phase)*BOB_AMPLITUDE, 0)
			else
				ActiveAlarms[p] = nil   -- clean up stray
			end
		end
		if next(ActiveAlarms) == nil then
			heartbeatConn:Disconnect()
			heartbeatConn = nil
		end
	end)
end

local function detachSharedBobbing(part)
	ActiveAlarms[part] = nil
end

local function borrowAlarm(templateFolder, alarmType)
	AlarmPool[alarmType] = AlarmPool[alarmType] or {}
	local pool = AlarmPool[alarmType]
	local part = table.remove(pool)
	if part then return part end          -- reuse

	local t = templateFolder:FindFirstChild(alarmType)
	if not t then warn("[ZoneReq] no template for", alarmType) return nil end

	part = t:Clone()
	part.Anchored, part.CanCollide = true, false
	return part
end

local function returnAlarm(part)
	if not part then return end
	detachSharedBobbing(part)
	local t = part.Name:match("^(Alarm%u%l+)")   -- AlarmRoad / AlarmWater / …
	if not t then part:Destroy() return end
	AlarmPool[t] = AlarmPool[t] or {}
	table.insert(AlarmPool[t], part)
	part.Parent = nil
end

local function purgeSatisfiedHigherAlarms(player, zoneId, zoneModel, higherTypes)
	for _, t in ipairs(higherTypes or {}) do
		local reqName = (t == "AlarmRoad" and "Road")
			or (t == "AlarmWater" and "Water")
			or nil
		if reqName then
			for _, child in ipairs(zoneModel:GetChildren()) do
				if child:IsA("BasePart") and child.Name:sub(1, #t) == t then
					local gx, gz = child.Name:match("^"..t.."_([%-0-9]+)_([%-0-9]+)$")
					if gx and gz then
						local ok = ZoneTrackerModule.getTileRequirement(
							player, zoneId, tonumber(gx), tonumber(gz), reqName
						)
						if ok == true then
							returnAlarm(child) -- requirement met → higher alarm is stale
						end
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- 2) HELPERS FOR MARKING TILES/GETTING/SETTING CACHE
----------------------------------------------------------------------
local function markTile(player, zoneId, gx, gz, req, value)
	ZoneTrackerModule.markTileRequirement(player, zoneId, gx, gz, req, value)
end

local function getCachedRequirements(player, zoneId)
	local userId = player.UserId
	if zoneRequirementCache[userId] and zoneRequirementCache[userId][zoneId] then
		return {
			hasRoad  = zoneRequirementCache[userId][zoneId].hasRoad,
			hasWater = zoneRequirementCache[userId][zoneId].hasWater,
			hasPower = zoneRequirementCache[userId][zoneId].hasPower
		}
	end
	return nil
end

local function setCachedRequirements(player, zoneId, hasRoad, hasWater, hasPower)
	local userId = player.UserId
	zoneRequirementCache[userId] = zoneRequirementCache[userId] or {}
	zoneRequirementCache[userId][zoneId] = zoneRequirementCache[userId][zoneId] or {}

	zoneRequirementCache[userId][zoneId].hasRoad  = hasRoad
	zoneRequirementCache[userId][zoneId].hasWater = hasWater
	zoneRequirementCache[userId][zoneId].hasPower = hasPower
end

local function tileKey(gx, gz)
	return ("%d_%d"):format(gx, gz)
end

local function getCachedTileRequirements(player, zoneId, gx, gz)
	local userId = player.UserId
	if zoneRequirementCache[userId]
		and zoneRequirementCache[userId][zoneId]
		and zoneRequirementCache[userId][zoneId].tiles
	then
		return zoneRequirementCache[userId][zoneId].tiles[tileKey(gx, gz)]
	end
	return nil
end

local function setCachedTileRequirements(player, zoneId, gx, gz, hasRoad, hasWater, hasPower)
	local userId = player.UserId
	zoneRequirementCache[userId] = zoneRequirementCache[userId] or {}
	zoneRequirementCache[userId][zoneId] = zoneRequirementCache[userId][zoneId] or {}

	zoneRequirementCache[userId][zoneId].tiles = zoneRequirementCache[userId][zoneId].tiles or {}
	zoneRequirementCache[userId][zoneId].tiles[tileKey(gx, gz)] = {
		hasRoad  = hasRoad,
		hasWater = hasWater,
		hasPower = hasPower
	}
end

local function invalidateZoneCache(player, zoneId)
	local userId = player.UserId
	if zoneRequirementCache[userId] and zoneRequirementCache[userId][zoneId] then
		zoneRequirementCache[userId][zoneId] = nil
	end
	invalidateAggregateCaches(player)
	-- >>> ADDED: clear sequencing for this zone to avoid cross-talk
	_clearSeqsForZone(player, zoneId)
end

local function _postPopulationRecheck(player, zoneId)
	local z = ZoneTrackerModule.getZoneById(player, zoneId)
	if not z or not buildingZoneTypes[z.mode] then return end
	invalidateZoneCache(player, zoneId)
	ZoneRequirementsChecker.checkZoneRequirements(player, zoneId, z.mode, z.gridList, { runSync = true })
	scheduleHappinessPublish(player, 0.01)
end

----------------------------------------------------------------------
-- 3) TRACKING "POPULATED" STATE & PENDING ALARMS
----------------------------------------------------------------------

-- Priority: Road > Water > Power
local ALARM_ORDER = { "AlarmRoad", "AlarmWater", "AlarmPower" }
local ALARM_HIGHER = {
	["AlarmWater"] = { "AlarmRoad" },
	["AlarmPower"] = { "AlarmRoad", "AlarmWater" },
}
local ALARM_LOWER = {
	["AlarmRoad"]  = { "AlarmWater", "AlarmPower" },
	["AlarmWater"] = { "AlarmPower" },
	["AlarmPower"] = {},
}

local zonePopulated = {}  -- zonePopulated[player.UserId][zoneId] = bool
local pendingAlarms = {}  -- pendingAlarms[player.UserId][zoneId][alarmType] = { list of coords }

local function isZonePopulated(player, zoneId)
	local userId = player.UserId
	return zonePopulated[userId]
		and zonePopulated[userId][zoneId] == true
end

-- small helper for coord keying
local function coordKey(c)
	return ("%d_%d"):format(c.x, c.z)
end

local function storePendingAlarms(player, zoneId, alarmType, coordsList)
	local userId = player.UserId
	pendingAlarms[userId] = pendingAlarms[userId] or {}
	pendingAlarms[userId][zoneId] = pendingAlarms[userId][zoneId] or {}

	-- Build a deduped replacement list
	local newList = {}
	local seen = {}

	if type(coordsList) == "table" then
		for _, c in ipairs(coordsList) do
			if c and typeof(c) == "table" and typeof(c.x) == "number" and typeof(c.z) == "number" then
				local k = coordKey(c)
				if not seen[k] then
					seen[k] = true
					newList[#newList+1] = { x = c.x, z = c.z }
				end
			end
		end
	end

	if #newList == 0 then
		-- Nothing currently missing → clear this alarmType
		pendingAlarms[userId][zoneId][alarmType] = nil

		-- Tidy zone bucket if empty
		if next(pendingAlarms[userId][zoneId]) == nil then
			pendingAlarms[userId][zoneId] = nil
		end
		-- Tidy user bucket if empty
		if pendingAlarms[userId] and next(pendingAlarms[userId]) == nil then
			pendingAlarms[userId] = nil
		end
		return
	end

	-- Replace previous contents with the fresh set
	pendingAlarms[userId][zoneId][alarmType] = newList
end

-- Called when a zone becomes populated: create any pending alarms
function ZoneRequirementsChecker.flushPendingAlarms(player, zoneId)
	local userId = player.UserId
	local pendByType = pendingAlarms[userId] and pendingAlarms[userId][zoneId]
	if not pendByType then
		return
	end

	local function toSet(list)
		local set = {}
		if type(list) == "table" then
			for _, c in ipairs(list) do
				if c and typeof(c) == "table" and typeof(c.x) == "number" and typeof(c.z) == "number" then
					set[coordKey(c)] = { x = c.x, z = c.z }
				end
			end
		end
		return set
	end

	local roadSet  = toSet(pendByType["AlarmRoad"])
	local waterSet = toSet(pendByType["AlarmWater"])
	local powerSet = toSet(pendByType["AlarmPower"])

	for k in pairs(roadSet) do
		waterSet[k] = nil
		powerSet[k] = nil
	end
	for k in pairs(waterSet) do
		powerSet[k] = nil
	end

	local function toList(set)
		local t = {}
		for _, v in pairs(set) do
			table.insert(t, v)
		end
		return t
	end

	debugPrint("Flushing pending alarms for zone", zoneId, "in priority order Road→Water→Power")
	-- >>> ADDED: pass last-writer-wins sequence
	local seqR = _bumpSeq(AlarmSeq, player, zoneId, "AlarmRoad")
	ZoneRequirementsChecker.updateTileAlarms(player, zoneId, "AlarmRoad" , toList(roadSet), seqR)
	local seqW = _bumpSeq(AlarmSeq, player, zoneId, "AlarmWater")
	ZoneRequirementsChecker.updateTileAlarms(player, zoneId, "AlarmWater", toList(waterSet), seqW)
	local seqP = _bumpSeq(AlarmSeq, player, zoneId, "AlarmPower")
	ZoneRequirementsChecker.updateTileAlarms(player, zoneId, "AlarmPower", toList(powerSet), seqP)

	pendingAlarms[userId][zoneId] = nil
end

-- Listen for ZonePopulated event from BuildingGeneratorModule
local zonePopulatedEvent = BindableEvents:WaitForChild("ZonePopulated")
zonePopulatedEvent.Event:Connect(function(player, zoneId, placedBuildingsData)
	local userId = player.UserId
	zonePopulated[userId] = zonePopulated[userId] or {}
	zonePopulated[userId][zoneId] = true

	-- Clear cosmetic temp alarms before promoting real ones
	ZoneRequirementsChecker.clearTempAlarms(player, zoneId)

	debugPrint(string.format(
		"ZoneRequirementsChecker: Marking zone '%s' as Populated for player %s. Flushing alarms now...",
		zoneId, player.Name
		))
	ZoneRequirementsChecker.flushPendingAlarms(player, zoneId)
	task.delay(1.0, function()
		_postPopulationRecheck(player, zoneId)
	end)
end)

----------------------------------------------------------------------
-- 4) SPATIAL GRID FOR FINDING NEARBY ROADS, WATER, ETC.
----------------------------------------------------------------------
local SpatialGrid = {}
SpatialGrid.__index = SpatialGrid

function SpatialGrid.new(cellSize)
	local self = setmetatable({}, SpatialGrid)
	self.cellSize = cellSize
	self.cells = {}
	self.byId  = {}   -- [zoneId] = entry added by addZone
	return self
end

function SpatialGrid:removeZoneById(zoneId)
	local entry = self.byId[zoneId]
	if entry then
		self:removeZone(entry)
		return
	end
	for cx, col in pairs(self.cells) do
		for cz, list in pairs(col) do
			for i = #list, 1, -1 do
				if list[i].zoneId == zoneId then
					table.remove(list, i)
				end
			end
			if self.cells[cx] and self.cells[cx][cz] and #self.cells[cx][cz] == 0 then
				self.cells[cx][cz] = nil
			end
		end
		if self.cells[cx] and next(self.cells[cx]) == nil then
			self.cells[cx] = nil
		end
	end
	self.byId[zoneId] = nil
end

function SpatialGrid:getCell(x, z)
	return math.floor(x / self.cellSize), math.floor(z / self.cellSize)
end

function SpatialGrid:addZone(zone)
	if self.byId[zone.zoneId] then
		self:removeZone(self.byId[zone.zoneId])
	end

	zone._tileCells = {}
	local seen = {}

	for _, coord in ipairs(zone.gridList) do
		if type(coord) == "table" and type(coord.x) == "number" and type(coord.z) == "number" then
			local cellX, cellZ = self:getCell(coord.x, coord.z)
			local key = tostring(cellX) .. "|" .. tostring(cellZ)

			if not seen[key] then
				self.cells[cellX] = self.cells[cellX] or {}
				self.cells[cellX][cellZ] = self.cells[cellX][cellZ] or {}

				table.insert(self.cells[cellX][cellZ], zone)
				table.insert(zone._tileCells, {cellX = cellX, cellZ = cellZ})

				seen[key] = true
			end
		end
	end

	self.byId[zone.zoneId] = zone
end

function SpatialGrid:removeZone(zone)
	local entry = zone
	if not (entry and entry._tileCells) then
		entry = self.byId[zone.zoneId]
	end

	if entry and entry._tileCells then
		for _, cellPos in ipairs(entry._tileCells) do
			local cellX, cellZ = cellPos.cellX, cellPos.cellZ
			local bucket = self.cells[cellX] and self.cells[cellX][cellZ]
			if bucket then
				for i = #bucket, 1, -1 do
					if bucket[i].zoneId == entry.zoneId then
						table.remove(bucket, i)
					end
				end
				if #bucket == 0 then
					self.cells[cellX][cellZ] = nil
				end
			end
		end
	else
		self:removeZoneById(zone.zoneId)
		return
	end

	if entry then entry._tileCells = nil end
	self.byId[zone.zoneId] = nil
end

function SpatialGrid:getNearbyZones(x, z, radius)
	local nearbyZones = {}
	local cellX, cellZ = self:getCell(x, z)
	local cellsToCheck = math.ceil(radius / self.cellSize)

	for dx = -cellsToCheck, cellsToCheck do
		for dz = -cellsToCheck, cellsToCheck do
			local currentCellX = cellX + dx
			local currentCellZ = cellZ + dz
			if self.cells[currentCellX] and self.cells[currentCellX][currentCellZ] then
				for _, zone in ipairs(self.cells[currentCellX][currentCellZ]) do
					table.insert(nearbyZones, zone)
				end
			end
		end
	end

	return nearbyZones
end

function SpatialGrid:getNearbyCells(x, z, radius)
	local out = {}
	local cellX0, cellZ0 = self:getCell(x, z)
	local cellsToCheck = math.ceil(radius / self.cellSize)

	for dx = -cellsToCheck, cellsToCheck do
		for dz = -cellsToCheck, cellsToCheck do
			local cx, cz = cellX0 + dx, cellZ0 + dz
			local bucket = self.cells[cx] and self.cells[cx][cz]
			if bucket then
				local ddx, ddz = cx - cellX0, cz - cellZ0
				if (ddx*ddx + ddz*ddz) <= (radius*radius) then
					for i = 1, #bucket do
						local zref = bucket[i]
						out[#out+1] = { zoneId = zref.zoneId, mode = zref.mode, cellX = cx, cellZ = cz }
					end
				end
			end
		end
	end
	return out
end

local function computeZoneCenter(gridList)
	local totalX, totalZ, count = 0, 0, 0
	for _, coord in ipairs(gridList) do
		if type(coord) == "table" and type(coord.x) == "number" and type(coord.z) == "number" then
			totalX = totalX + coord.x
			totalZ = totalZ + coord.z
			count = count + 1
		end
	end
	if count == 0 then
		return nil
	end
	return { x = totalX / count, z = totalZ / count }
end

local function startBobbing(part, basePos)
	if USE_SHARED_BOBBING then
		attachSharedBobbing(part, basePos)
	else
		local up = TweenService:Create(part, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{Position = basePos + Vector3.new(0, 0.5, 0)})
		local down = TweenService:Create(part, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
			{Position = basePos})
		up.Completed:Connect(function() down:Play() end)
		down.Completed:Connect(function() up:Play() end)
		up:Play()
	end
end

local function getZoneModelPosition(zoneModel)
	if zoneModel:IsA("Model") then
		if zoneModel.PrimaryPart then
			return zoneModel.PrimaryPart.Position
		else
			local cf, _ = zoneModel:GetBoundingBox()
			return cf.Position
		end
	elseif zoneModel:IsA("BasePart") then
		return zoneModel.Position
	end
	return nil
end

local function getZoneModelFor(player, zoneId)
	local plotFolder = workspace:FindFirstChild("PlayerPlots")
	local playerPlot = plotFolder and plotFolder:FindFirstChild("Plot_" .. player.UserId)
	if not playerPlot then return nil, nil end
	local zoneModelFolder = playerPlot:FindFirstChild("PlayerZones")
	local zoneModel = zoneModelFolder and zoneModelFolder:FindFirstChild(zoneId)
	return zoneModel, playerPlot
end

local function ensureTempAlarmFolder(zoneModel)
	if not zoneModel then return nil end
	local f = zoneModel:FindFirstChild(TEMP_ALARM_FOLDER_NAME)
	if not f then
		f = Instance.new("Folder")
		f.Name = TEMP_ALARM_FOLDER_NAME
		f.Parent = zoneModel
	end
	return f
end

function ZoneRequirementsChecker.clearTempAlarms(player, zoneId)
	local zoneModel = select(1, getZoneModelFor(player, zoneId))
	if not zoneModel then return end
	local f = zoneModel:FindFirstChild(TEMP_ALARM_FOLDER_NAME)
	if not f then return end
	for _, ch in ipairs(f:GetChildren()) do
		if ch:IsA("BasePart") then
			returnAlarm(ch)
		else
			ch:Destroy()
		end
	end
	f:Destroy()
end

-- Lower-type cleanup but scoped to a specific container (TempAlarms) (REPLACED)
local function removeLowerTypeAlarmsInContainer(container, lowerTypes, neededSet)
	if not container or not lowerTypes or #lowerTypes == 0 then return end

	local ops, Y = 0, TEMP_ALARM_YIELD_EVERY_OPS
	for _, child in ipairs(container:GetChildren()) do
		ops += 1
		if (ops % Y) == 0 then task.wait() end

		if child:IsA("BasePart") then
			for _, lt in ipairs(lowerTypes) do
				local gx, gz = child.Name:match("^"..lt.."_([%-0-9]+)_([%-0-9]+)$")
				if gx and gz then
					local key = gx.."_"..gz
					if neededSet[key] then
						returnAlarm(child)
						break
					end
				end
			end
		end
	end
end

local function hasHigherTempAlarm(container, higherTypes, x, z)
	if not container or not higherTypes or #higherTypes == 0 then return false end
	for _, t in ipairs(higherTypes) do
		local name = string.format("%s_%d_%d", t, x, z)
		if container:FindFirstChild(name) then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- Helpers for alarm placement ordering / cleanup
----------------------------------------------------------------------
local function removeLowerTypeAlarms(zoneModel, lowerTypes, neededSet)
	if not lowerTypes or #lowerTypes == 0 then return end
	for _, child in ipairs(zoneModel:GetChildren()) do
		if child:IsA("BasePart") then
			for _, lt in ipairs(lowerTypes) do
				local gx, gz = child.Name:match("^"..lt.."_([%-0-9]+)_([%-0-9]+)$")
				if gx and gz then
					local key = gx.."_"..gz
					if neededSet[key] then
						returnAlarm(child)
						break
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- Normal alarm update (only when populated)
----------------------------------------------------------------------
function ZoneRequirementsChecker.updateTileAlarms(player, zoneId, alarmType, unsatisfiedCoords, seq)
	-- >>> ADDED: last-writer-wins gate
	local current = _getSeq(AlarmSeq, player, zoneId, alarmType)
	if seq and seq < current then
		if DEBUG then
			print(("[ZoneReq] Ignoring stale %s update for %s (seq %d < %d)"):format(alarmType, zoneId, seq, current))
		end
		return
	end
	if seq and seq > current then
		_setSeq(AlarmSeq, player, zoneId, alarmType, seq)
	end

	-- If zone is NOT populated, store in pending and bail out
	if not isZonePopulated(player, zoneId) then
		debugPrint("Zone NOT populated, storing alarm coords for later:", alarmType, zoneId)
		storePendingAlarms(player, zoneId, alarmType, unsatisfiedCoords)

		if SHOW_POPULATING_ALARMS and SHOW_TEMP_FROM_INFRA_EVENTS then
			local tseq = _bumpSeq(TempAlarmSeq, player, zoneId, alarmType) -- >>> ADDED
			ZoneRequirementsChecker.updateTempTileAlarms(
				player, zoneId, alarmType, unsatisfiedCoords, unsatisfiedCoords, tseq
			)
		end
		return
	end

	local plotFolder = workspace:FindFirstChild("PlayerPlots")
	local playerPlot = plotFolder and plotFolder:FindFirstChild("Plot_" .. player.UserId)
	if not playerPlot then return end

	local zoneModelFolder = playerPlot:FindFirstChild("PlayerZones")
	local zoneModel = zoneModelFolder and zoneModelFolder:FindFirstChild(zoneId)
	if not zoneModel then return end

	local templateFolder = ReplicatedStorage:WaitForChild("FuncTestGroundRS"):WaitForChild("Alarms")

	local higher = ALARM_HIGHER[alarmType] or {}
	local lower  = ALARM_LOWER[alarmType]  or {}

	purgeSatisfiedHigherAlarms(player, zoneId, zoneModel, higher)

	local function hasHigherAlarm(x, z)
		for _, t in ipairs(higher) do
			local nameCheck = string.format("%s_%d_%d", t, x, z)
			local part = zoneModel:FindFirstChild(nameCheck)
			if part then
				local reqName = (t == "AlarmRoad"  and "Road")
					or (t == "AlarmWater" and "Water")
					or nil
				local v = reqName and ZoneTrackerModule.getTileRequirement(player, zoneId, x, z, reqName)
				local stillMissing = (v == false)
				if stillMissing then
					return true
				else
					returnAlarm(part)
				end
			end
		end
		return false
	end

	-- >>> ADDED: build 'needed' from unsatisfiedCoords, but confirm with ZoneTracker (defensive truth check)
	local needed = {}
	local reqName = REQ_NAME_FOR_ALARM[alarmType]
	for _, c in ipairs(unsatisfiedCoords or {}) do
		local missing = true
		if reqName then
			local v = ZoneTrackerModule.getTileRequirement(player, zoneId, c.x, c.z, reqName)
			missing = (v == false)
		end
		if missing and not hasHigherAlarm(c.x, c.z) then
			needed[string.format("%d_%d", c.x, c.z)] = true
		end
	end

	if #ALARM_LOWER[alarmType] > 0 and next(needed) ~= nil then
		removeLowerTypeAlarms(zoneModel, ALARM_LOWER[alarmType], needed)
	end

	-- Remove any existing parts of this type that are no longer needed
	for _, child in ipairs(zoneModel:GetChildren()) do
		if child:IsA("BasePart") and child.Name:sub(1, #alarmType) == alarmType then
			local gx, gz = child.Name:match("^"..alarmType.."_([%-0-9]+)_([%-0-9]+)$")
			if gx and gz then
				local key = gx.."_"..gz
				if not needed[key] then
					returnAlarm(child)
				end
			end
		end
	end

	-- Place required alarms
	for k, _ in pairs(needed) do
		local x, z = k:match("^([%-0-9]+)_([%-0-9]+)$")
		x, z = tonumber(x), tonumber(z)
		local name = string.format("%s_%d_%d", alarmType, x, z)
		if not zoneModel:FindFirstChild(name) then
			local basePos = gridToWorld(playerPlot, x, z) + Vector3.new(0,6,0)
			local alarm   = borrowAlarm(templateFolder, alarmType)
			if alarm then
				alarm.Name     = name
				alarm.Parent   = zoneModel
				alarm.Position = basePos
				startBobbing(alarm, basePos)
			end
		end
	end
end

----------------------------------------------------------------------
-- TEMP alarm updater (pre-population only)
----------------------------------------------------------------------
local function indexTempAlarmFolder(tempFolder)
	-- idx[AlarmType][ "x_z" ] = part
	local idx = {}
	local children = tempFolder:GetChildren()
	for i = 1, #children do
		local ch = children[i]
		if ch:IsA("BasePart") then
			local t, x, z = ch.Name:match("^(Alarm%u%l+)_([%-0-9]+)_([%-0-9]+)$")
			if t and x and z then
				local bucket = idx[t]
				if not bucket then bucket = {}; idx[t] = bucket end
				bucket[x.."_"..z] = ch
			end
		end
	end
	return idx
end

-- TEMP alarm updater (pre-population only) (REPLACED)
function ZoneRequirementsChecker.updateTempTileAlarms(player, zoneId, alarmType, unsatisfiedCoords, scopeCoords, seq)
	if not SHOW_POPULATING_ALARMS then return end
	if not player or not zoneId or not alarmType then return end

	-- >>> ADDED: last-writer-wins for temp alarms
	local current = _getSeq(TempAlarmSeq, player, zoneId, alarmType)
	if seq and seq < current then
		if DEBUG then
			print(("[ZoneReq] Ignoring stale TEMP %s update for %s (seq %d < %d)"):format(alarmType, zoneId, seq, current))
		end
		return
	end
	if seq and seq > current then
		_setSeq(TempAlarmSeq, player, zoneId, alarmType, seq)
	end

	-- Skip temp alarms entirely while SaveManager is doing a progressive world reload
	if LOAD_AWARE_SKIP_TEMP_ALARMS and WorldReloadActiveByUid[player.UserId] then
		return
	end

	if isZonePopulated(player, zoneId) then return end

	local zoneModel, playerPlot = getZoneModelFor(player, zoneId)
	if not (zoneModel and playerPlot) then return end

	local tempFolder     = ensureTempAlarmFolder(zoneModel)
	local templateFolder = ReplicatedStorage:WaitForChild("FuncTestGroundRS"):WaitForChild("Alarms")

	local higher = ALARM_HIGHER[alarmType] or {}
	local lower  = ALARM_LOWER[alarmType]  or {}

	-- Build sets
	local needed = {}       -- tiles that should have *this* alarmType
	if type(unsatisfiedCoords) == "table" then
		for _, c in ipairs(unsatisfiedCoords) do
			if c and typeof(c) == "table" and typeof(c.x) == "number" and typeof(c.z) == "number" then
				needed[("%d_%d"):format(c.x, c.z)] = c
			end
		end
	end

	local scope = {}        -- tiles we will touch (promote, keep, or clear)
	scopeCoords = scopeCoords or unsatisfiedCoords
	if type(scopeCoords) == "table" then
		for _, c in ipairs(scopeCoords) do
			if c and typeof(c) == "table" and typeof(c.x) == "number" and typeof(c.z) == "number" then
				scope[("%d_%d"):format(c.x, c.z)] = c
			end
		end
	end

	-- Build an index of existing temp alarms to avoid rescanning children for each tile
	local idx = indexTempAlarmFolder(tempFolder)

	local function idxHas(typeName, key)
		local b = idx[typeName]; return b and b[key] or nil
	end
	local function idxRemove(typeName, key)
		local b = idx[typeName]
		if b then
			local part = b[key]
			if part then
				returnAlarm(part)
				b[key] = nil
			end
		end
	end

	-- Budgeted processing
	local start = os.clock()
	local ops   = 0
	local function maybeYield()
		ops += 1
		if (ops % TEMP_ALARM_YIELD_EVERY_OPS) == 0 then task.wait() ; start = os.clock() end
		if (os.clock() - start) >= (TEMP_ALARM_BUDGET_MS / 1000) then
			task.wait()
			start = os.clock()
		end
	end

	-- 1) Lower-type cleanup **once** for all needed keys
	if next(needed) ~= nil and #lower > 0 then
		for key, _ in pairs(needed) do
			for i = 1, #lower do
				idxRemove(lower[i], key)
			end
			maybeYield()
		end
	end

	-- 2) For each tile in scope: ensure correct presence/absence of current alarmType
	for key, coord in pairs(scope) do
		local x, z = coord.x, coord.z

		-- Respect priority: if any higher-type temp alarm exists for this tile, skip placing lower
		local hasHigher = false
		for i = 1, #higher do
			if idxHas(higher[i], key) then
				hasHigher = true
				break
			end
		end

		if hasHigher then
			-- If we currently have this alarmType at this tile, remove it (higher takes precedence)
			idxRemove(alarmType, key)
		else
			if needed[key] then
				-- Should exist: place or update
				if not idxHas(alarmType, key) then
					local basePos = gridToWorld(playerPlot, x, z) + Vector3.new(0, 6, 0)
					local alarm   = borrowAlarm(templateFolder, alarmType)
					if alarm then
						alarm.Name     = string.format("%s_%d_%d", alarmType, x, z)
						alarm.Parent   = tempFolder
						alarm.Position = basePos
						startBobbing(alarm, basePos)
						-- update index
						idx[alarmType] = idx[alarmType] or {}
						idx[alarmType][key] = alarm
					end
				else
					-- Update position in case terrain moved
					local basePos = gridToWorld(playerPlot, x, z) + Vector3.new(0, 6, 0)
					local p = idxHas(alarmType, key)
					if p then
						p.Position = basePos
						if ActiveAlarms[p] then ActiveAlarms[p].base = basePos end
					end
				end
			else
				-- Should *not* exist: remove if present
				idxRemove(alarmType, key)
			end
		end

		maybeYield()
	end
end

----------------------------------------------------------------------
-- 5) CREATE THE GLOBAL SPATIAL GRIDS
----------------------------------------------------------------------
local roadSpatialGrid = SpatialGrid.new(1)
local waterSpatialGrid = SpatialGrid.new(1)
local powerSpatialGrid = SpatialGrid.new(1)
local buildingSpatialGrid = SpatialGrid.new(1)

-- On Server Start, populate the grids for any pre-existing zones
do
	for _, player in ipairs(Players:GetPlayers()) do
		for zId, z in pairs(ZoneTrackerModule.getAllZones(player)) do
			local entry = { zoneId = zId, mode = z.mode, gridList = z.gridList,
				center = computeZoneCenter(z.gridList) }
			if z.mode == "DirtRoad" or z.mode == "Pavement" or z.mode == "Highway" then
				roadSpatialGrid:addZone(entry)
			elseif waterInfrastructureModes[z.mode] then
				waterSpatialGrid:addZone(entry)
			elseif powerInfrastructureModes[z.mode] then
				powerSpatialGrid:addZone(entry)
			elseif buildingZoneTypes[z.mode] then
				buildingSpatialGrid:addZone(entry)
			end
		end
	end
end

for _, p in ipairs(Players:GetPlayers()) do
	scheduleHappinessPublish(p, 0.05)
end
Players.PlayerAdded:Connect(function(p)
	scheduleHappinessPublish(p, 0.25)
end)

local function collectDistinctNearbyBuildingZones(coordList, radius)
	local touched = {}
	for _, c in ipairs(coordList) do
		local raw = buildingSpatialGrid:getNearbyZones(c.x, c.z, radius)
		for i = 1, #raw do
			local z = raw[i]
			local zid = z and z.zoneId
			if zid and not touched[zid] then
				touched[zid] = z
			end
		end
	end
	return touched
end

local function getTileDemand(player, zoneId, mode, coord, networkType)
	local cfgTbl = Balance.StatConfig[mode]
	if not cfgTbl then return 0 end
	local w = ZoneTrackerModule.getGridWealth(player, zoneId, coord.x, coord.z) or "Poor"
	local T = cfgTbl[w]; if not T then return 0 end

	local base = (networkType == "Water") and (T.water or 0) or (T.power or 0)

	-- NEW: mixed-use demand bonus (Res <-> Comm)
	local mul = 1.0
	if CityInteractions and CityInteractions.getTileDemandMultiplier then
		mul = CityInteractions.getTileDemandMultiplier(player, zoneId, coord.x, coord.z, mode, networkType)
	end

	return math.floor(base * mul + 0.5)  -- keep it integer per tile
end

local function nearestConnectedInfraDist2(player, networkType, coord, radius)
	local grid = (networkType == "Water") and waterSpatialGrid or powerSpatialGrid
	local r2, best = radius*radius, math.huge
	for _, z in ipairs(grid:getNearbyZones(coord.x, coord.z, radius)) do
		for _, c in ipairs(z.gridList or {}) do
			local dx, dz = c.x - coord.x, c.z - coord.z
			local d2 = dx*dx + dz*dz
			if d2 <= r2 and NetworkManager.isCellConnectedToSource(player, networkType, c.x, c.z) then
				if d2 < best then best = d2 end
			end
		end
	end
	return best
end

-- === NEW: Production synergy radius (per *producer* mode) ===================
getProductionSynergyWidth = function(prodMode: string): number
	local Interactions = require(ReplicatedStorage.Balancing.BalanceInteractions)
	local ps   = Interactions and Interactions.ProductionSynergy
	local per  = ps and ps.Radius or nil
	local def  = ps and ps.DefaultRadius or nil
	local w    = (per and per[prodMode]) or def
	if type(w) == "number" and w >= 1 then return math.max(1, math.floor(w)) end
	-- fallback to UXP width for identical neighborhood math
	local BalanceEconomy = require(ReplicatedStorage.Balancing.BalanceEconomy)
	local UXP_RADIUS = (BalanceEconomy and BalanceEconomy.UxpConfig and BalanceEconomy.UxpConfig.Radius) or {}
	local function getInfluenceWidth(mode: string)
		local ww = (UXP_RADIUS :: any)[mode]
		if type(ww) ~= "number" or ww < 1 then return 5 end
		return math.max(1, math.floor(ww))
	end
	return getInfluenceWidth(prodMode)
end

-- === NEW: Compute production multiplier for a producer zone =================
computeProductionMultiplierForProducer = function(player: Player, producerZoneId: string, producerMode: string): number
	local Interactions = require(ReplicatedStorage.Balancing.BalanceInteractions)
	local ps = Interactions and Interactions.ProductionSynergy
	if not ps then return 1.0 end

	local deltas = ps.Deltas or {}
	local maxBonus   = tonumber(ps.MaxBonus)   or 0.5
	local maxPenalty = tonumber(ps.MaxPenalty) or 0.8

	-- Look for *building* zones near the producer (one hit per category; dense overrides non-dense)
	local prodZ = ZoneTrackerModule.getZoneById(player, producerZoneId)
	if not prodZ or not prodZ.gridList then return 1.0 end

	local center = computeZoneCenter(prodZ.gridList) or { x = prodZ.gridList[1].x, z = prodZ.gridList[1].z }
	local radius = getProductionSynergyWidth(producerMode)

	-- Sample nearby building zones via existing spatial grid
	local nearby = buildingSpatialGrid:getNearbyZones(center.x, center.z, radius)

	local seen = {
		Residential = false, ResDense = false,
		Commercial  = false, CommDense = false,
		Industrial  = false, IndusDense = false,
	}

	-- Use center-to-center Chebyshev window to decide "within radius"
	local function within(gx1, gz1, gx2, gz2, side)
		local half = math.floor(side / 2)
		return math.abs(gx1 - gx2) <= half and math.abs(gz1 - gz2) <= half
	end

	for _, z in ipairs(nearby) do
		if z and z.mode then
			local zc = z.center or computeZoneCenter(z.gridList or {}) or z.gridList and z.gridList[1]
			if zc and within(center.x, center.z, zc.x, zc.z, radius) then
				if z.mode == "ResDense"   then seen.ResDense   = true
				elseif z.mode == "Residential" then seen.Residential = seen.ResDense and true or true
				elseif z.mode == "CommDense"   then seen.CommDense   = true
				elseif z.mode == "Commercial"  then seen.Commercial  = seen.CommDense and true or true
				elseif z.mode == "IndusDense"  then seen.IndusDense  = true
				elseif z.mode == "Industrial"  then seen.Industrial  = seen.IndusDense and true or true
				end
			end
		end
	end

	-- Dense versions override their base category: only count one per category
	local delta = 0
	if seen.ResDense   then delta += (deltas.ResDense   or 0)
	elseif seen.Residential then delta += (deltas.Residential or 0) end

	if seen.CommDense   then delta += (deltas.CommDense   or 0)
	elseif seen.Commercial  then delta += (deltas.Commercial  or 0) end

	if seen.IndusDense  then delta += (deltas.IndusDense  or 0)
	elseif seen.Industrial  then delta += (deltas.Industrial or 0) end

	-- Clamp total delta
	local minMul = 1.0 - maxPenalty
	local maxMul = 1.0 + maxBonus
	local mul    = 1.0 + delta
	if mul < minMul then mul = minMul end
	if mul > maxMul then mul = maxMul end
	return mul
end

function ZoneRequirementsChecker.getEffectiveProduction(player: Player)
	-- Sum all producer zones for this player using production multipliers.

	local cached = getAggregateCache(aggregateProductionCache, player)
	if cached then return cached end

	local totals = { water = 0, power = 0 }
	if not (player and player:IsA("Player")) then return totals end

	for zid, z in pairs(ZoneTrackerModule.getAllZones(player) or {}) do
		local pcfg = Balance.ProductionConfig[z.mode]
		if pcfg and (pcfg.type == "water" or pcfg.type == "power") then
			local mul = computeProductionMultiplierForProducer(player, zid, z.mode)
			totals[pcfg.type] = (totals[pcfg.type] or 0) + ((pcfg.amount or 0) * mul)
		end
	end

	setAggregateCache(aggregateProductionCache, player, totals)
	return copyAggregate(totals)
end

-- Uses CityInteractions.getTileDemandMultiplier so Res<->Comm proximity bumps demand.
function ZoneRequirementsChecker.getEffectiveTotals(player)
	local cached = getAggregateCache(aggregateTotalsCache, player)
	if cached then return cached end

	local totals = { water = 0, power = 0 }
	if not (player and player:IsA("Player")) then return totals end

	local Zones = ZoneTrackerModule.getAllZones(player)
	if not Zones then return totals end

	for _, z in pairs(Zones) do
		if ZoneRequirementsChecker.isBuildingZone(z.mode) and z.gridList then
			local cfgTbl = Balance.StatConfig[z.mode]
			if cfgTbl then
				for _, c in ipairs(z.gridList) do
					local w = ZoneTrackerModule.getGridWealth(player, z.zoneId, c.x, c.z) or "Poor"
					local T = cfgTbl[w]
					if T then
						local baseW = T.water or 0
						local baseP = T.power or 0

						-- Mixed-use demand bonus from CityInteractions (Res <-> Comm knobs)
						local mulW, mulP = 1.0, 1.0
						if CityInteractions and CityInteractions.getTileDemandMultiplier then
							mulW = CityInteractions.getTileDemandMultiplier(player, z.zoneId, c.x, c.z, z.mode, "Water") or 1.0
							mulP = CityInteractions.getTileDemandMultiplier(player, z.zoneId, c.x, c.z, z.mode, "Power") or 1.0
						end

						totals.water += math.floor(baseW * mulW + 0.5)
						totals.power += math.floor(baseP * mulP + 0.5)
					end
				end
			end
		end
	end

	setAggregateCache(aggregateTotalsCache, player, totals)
	return copyAggregate(totals)
end

local function allocateTilesForZone(player, zoneId, networkType, gridList, produced, required, radius)
	local z = ZoneTrackerModule.getZoneById(player, zoneId)
	if not z or not ZoneRequirementsChecker.isBuildingZone(z.mode) then return {} end

	local cand, zoneReachableDemand = {}, 0
	for _, c in ipairs(gridList) do
		local reachable = (networkType == "Water")
			and ZoneRequirementsChecker.zoneHasWater(player, zoneId, {c}, radius)
			or ZoneRequirementsChecker.zoneHasPower(player, zoneId, {c}, radius)
		if reachable then
			local d = getTileDemand(player, zoneId, z.mode, c, networkType)
			local d2 = nearestConnectedInfraDist2(player, networkType, c, radius)
			zoneReachableDemand += d
			table.insert(cand, {coord=c, demand=d, dist2=d2})
		end
	end
	if #cand == 0 or zoneReachableDemand == 0 then return {} end

	local share = (produced >= required) and zoneReachableDemand or (produced * (zoneReachableDemand/required))
	if share > zoneReachableDemand then share = zoneReachableDemand end

	table.sort(cand, function(a,b)
		if a.dist2 ~= b.dist2 then return a.dist2 < b.dist2 end
		if a.demand ~= b.demand then return a.demand < b.demand end
		if a.coord.x ~= b.coord.x then return a.coord.x < b.coord.x end
		return a.coord.z < b.coord.z
	end)

	local remaining, served = share, {}
	for _, t in ipairs(cand) do
		if remaining <= 0 then break end
		served[("%d_%d"):format(t.coord.x,t.coord.z)] = true
		remaining -= t.demand
	end
	return served
end

----------------------------------------------------------------------
-- 6) UTILITY TOTALS
----------------------------------------------------------------------
local function getPlayerTotalRequirements(player)
	local totals = { water = 0, power = 0 }
	local statsByZone = DistrictStatsModule.getStatsForPlayer(player.UserId)
	for _, stats in pairs(statsByZone) do
		totals.water  = totals.water  + (stats.water  or 0)
		totals.power  = totals.power  + (stats.power  or 0)
	end
	return totals
end

----------------------------------------------------------------------
-- 7) BIND TO ZoneCreated / ZoneRemoved
----------------------------------------------------------------------
local zoneCreatedEvent = BindableEvents:WaitForChild("ZoneCreated")
zoneCreatedEvent.Event:Connect(function(player, zoneId, mode, gridList)
	debugPrint(string.format("ZoneCreated: Player=%s, ZoneID=%s, Mode=%s", player.Name, zoneId, mode))
	ZoneRequirementsChecker.onZoneCreated(player, zoneId, mode, gridList)
end)

local zoneAddedEvent = BindableEvents:WaitForChild("ZoneAdded")
zoneAddedEvent.Event:Connect(function(player, zoneId, zoneData)
	if not player or not zoneData then return end
	if typeof(zoneData) ~= "table" or typeof(zoneData.gridList) ~= "table" then return end
	ZoneRequirementsChecker.onZoneCreated(player, zoneId, zoneData.mode, zoneData.gridList)
end)

local zoneRemovedEvent = BindableEvents:WaitForChild("ZoneRemoved")
zoneRemovedEvent.Event:Connect(function(player, zoneId, mode, gridList)
	debugPrint(string.format("ZoneRemoved: Player=%s, ZoneID=%s, Mode=%s", player.Name, zoneId, mode))
	ZoneRequirementsChecker.onZoneRemoved(player, zoneId, mode, gridList)
end)

----------------------------------------------------------------------
-- 8) CORE API
----------------------------------------------------------------------
function ZoneRequirementsChecker.getNearbyCoords(coord, radius)
	local nearby = {}
	for dx = -radius, radius do
		for dz = -radius, radius do
			table.insert(nearby, { x = coord.x + dx, z = coord.z + dz })
		end
	end
	return nearby
end

function ZoneRequirementsChecker.notifyPlayer(player, message)
	if not player or not player:IsA("Player") then
		warn("Invalid player in notifyPlayer.")
		return
	end
	if type(message) ~= "string" then
		warn("Invalid message in notifyPlayer.")
		return
	end
	debugPrint(string.format("Notifying '%s': %s", player.Name, message))
	if notifyPlayerEvent then
		notifyPlayerEvent:FireClient(player, message)
	else
		warn("notifyPlayerEvent not found.")
	end
end

local UtilityAlertsRF = RemoteEvents:FindFirstChild("GetUtilityAlertsSnapshot")
if not UtilityAlertsRF then
	UtilityAlertsRF = Instance.new("RemoteFunction")
	UtilityAlertsRF.Name = "GetUtilityAlertsSnapshot"
	UtilityAlertsRF.Parent = RemoteEvents
end

UtilityAlertsRF.OnServerInvoke = function(player)
	local totals, produced = getProductionSnapshot(player)
	local tW, tP = (totals.water or 0), (totals.power or 0)
	local pW, pP = (produced.water or 0), (produced.power or 0)
	return {
		waterInsufficient = pW < tW,
		powerInsufficient = pP < tP,
		waterRequired = tW, waterProduced = pW, waterDeficit = math.max(0, tW - pW),
		powerRequired = tP, powerProduced = pP, powerDeficit = math.max(0, tP - pP),
	}
end

function ZoneRequirementsChecker.evaluateRoadsForZone(player, zoneId, mode, gridList)
	if not ZoneRequirementsChecker.isBuildingZone(mode) then
		return true, {}
	end
	local unsatisfied = {}
	for _, c in ipairs(gridList) do
		local ok = ZoneRequirementsChecker.checkNearbyRoad(player, zoneId, mode, {c})
		markTile(player, zoneId, c.x, c.z, "Road", ok)
		if not ok then table.insert(unsatisfied, c) end
	end
	return (#unsatisfied == 0), unsatisfied
end

function ZoneRequirementsChecker.evaluateWaterForZone(player, zoneId, gridList)
	local zData = ZoneTrackerModule.getZoneById(player, zoneId)
	local mode  = zData and zData.mode
	if not ZoneRequirementsChecker.isBuildingZone(mode) then
		return true, {}
	end

	local produced, required = getComponentBudget(player, zoneId, "Water", { gridAware = true })
	local servedSet = nil
	if produced < required then
		servedSet = allocateTilesForZone(player, zoneId, "Water", gridList, produced, required, SEARCH_RADIUS)
	end

	local unsatisfied = {}
	for _, c in ipairs(gridList) do
		local reachable = ZoneRequirementsChecker.zoneHasWater(player, zoneId, {c}, SEARCH_RADIUS)
		local ok = (produced >= required) and reachable or (reachable and servedSet and servedSet[("%d_%d"):format(c.x,c.z)] == true)
		ZoneTrackerModule.markTileRequirement(player, zoneId, c.x, c.z, "Water", ok)
		if not ok then table.insert(unsatisfied, c) end
	end

	return (#unsatisfied == 0), unsatisfied
end

function ZoneRequirementsChecker.evaluatePowerForZone(player, zoneId, gridList)
	local zData = ZoneTrackerModule.getZoneById(player, zoneId)
	local mode  = zData and zData.mode
	if not ZoneRequirementsChecker.isBuildingZone(mode) then
		return true, {}
	end

	local produced, required = getComponentBudget(player, zoneId, "Power", { gridAware = true })
	local servedSet = nil
	if produced < required then
		servedSet = allocateTilesForZone(player, zoneId, "Power", gridList, produced, required, SEARCH_RADIUS)
	end

	local unsatisfied = {}
	for _, c in ipairs(gridList) do
		local reachable = ZoneRequirementsChecker.zoneHasPower(player, zoneId, {c}, SEARCH_RADIUS)
		local ok = (produced >= required) and reachable or (reachable and servedSet and servedSet[("%d_%d"):format(c.x,c.z)] == true)
		ZoneTrackerModule.markTileRequirement(player, zoneId, c.x, c.z, "Power", ok)
		if not ok then table.insert(unsatisfied, c) end
	end

	return (#unsatisfied == 0), unsatisfied
end

function ZoneRequirementsChecker.attemptActivatePendingZone(player, zoneId)
	local zoneData = ZoneTrackerModule.getZoneById(player, zoneId)
	if not zoneData then
		warn(string.format("ZoneRequirementsChecker: No data found for ZoneID=%s", zoneId))
		return
	end

	if not buildingZoneTypes[zoneData.mode] then
		warn(string.format("ZoneRequirementsChecker: Invalid building zone mode '%s' for ZoneID=%s", zoneData.mode, zoneId))
		return
	end

	local hasRoad = zoneData.requirements and zoneData.requirements["Road"] == true
	if hasRoad then
		local zoneActivatedEvent = BindableEvents:FindFirstChild("ZoneActivated")
		if zoneActivatedEvent then
			zoneActivatedEvent:Fire(player, zoneId, zoneData.mode, zoneData.gridList)
			debugPrint(string.format("ZoneActivated event fired for ZoneID=%s by Player=%s", zoneId, player.Name))
		else
			warn("ZoneRequirementsChecker: ZoneActivated BindableEvent not found.")
		end
	end
end

local function debounce(key)
	if debounceTable[key] then
		return true
	else
		debounceTable[key] = true
		task.delay(DEBOUNCE_TIME, function()
			debounceTable[key] = nil
		end)
		return false
	end
end

----------------------------------------------------------------------
-- onZoneCreated / onZoneRemoved
----------------------------------------------------------------------
function ZoneRequirementsChecker.onZoneCreated(player, zoneId, mode, gridList)
	if debounce(("create:%s:%s"):format(player.UserId, zoneId)) then return end
	invalidateZoneCache(player, zoneId)

	local entry = { zoneId = zoneId, mode = mode, gridList = gridList,
		center = computeZoneCenter(gridList) }

	if mode == "DirtRoad" or mode == "Pavement" or mode == "Highway" then
		roadSpatialGrid:addZone(entry)
		ZoneRequirementsChecker.checkPendingRoadRequirements(player, zoneId, mode, gridList)
	elseif waterInfrastructureModes[mode] then
		waterSpatialGrid:addZone(entry)
		ZoneRequirementsChecker.checkPendingWaterRequirements(player, zoneId, mode, gridList)
	elseif powerInfrastructureModes[mode] then
		powerSpatialGrid:addZone(entry)
		ZoneRequirementsChecker.checkPendingPowerRequirements(player, zoneId, mode, gridList) 
	elseif buildingZoneTypes[mode] then
		buildingSpatialGrid:addZone(entry)
	end

	if buildingZoneTypes[mode] then
		ZoneRequirementsChecker.checkZoneRequirements(player, zoneId, mode, gridList)
	end
end

function ZoneRequirementsChecker.onZoneRemoved(player, zoneId, mode, gridList)
	if debounce(("remove:%s:%s"):format(player.UserId, zoneId)) then return end
	invalidateZoneCache(player, zoneId)
	ZoneRequirementsChecker.clearTempAlarms(player, zoneId)
	_clearSeqsForZone(player, zoneId) -- >>> ADDED: drop any pending sequences for this zone

	local entry = { zoneId = zoneId, mode = mode, gridList = gridList,
		center = computeZoneCenter(gridList) }

	if mode == "DirtRoad" or mode == "Pavement" or mode == "Highway" then
		roadSpatialGrid:removeZone(entry)
	elseif waterInfrastructureModes[mode] then
		waterSpatialGrid:removeZone(entry)
	elseif powerInfrastructureModes[mode] then
		powerSpatialGrid:removeZone(entry)
	elseif buildingZoneTypes[mode] then
		buildingSpatialGrid:removeZone(entry)
	end

	if mode == "DirtRoad" or mode == "Pavement" or mode == "Highway" then
		ZoneRequirementsChecker.checkDependentZonesAfterRoadRemoval(player, zoneId, gridList)
		scheduleHappinessPublish(player, 0.03)
	elseif waterInfrastructureModes[mode] then
		ZoneRequirementsChecker.checkDependentZonesAfterWaterRemoval(player, zoneId, gridList)
		scheduleHappinessPublish(player, 0.03)
	elseif powerInfrastructureModes[mode] then
		ZoneRequirementsChecker.checkDependentZonesAfterPowerRemoval(player, zoneId, gridList)
		scheduleHappinessPublish(player, 0.03)
	end
end

----------------------------------------------------------------------
-- 9) Zone requirement checks (populated / cached paths)
----------------------------------------------------------------------
function ZoneRequirementsChecker.checkZoneRequirements(player, zoneId, mode, gridList, opts)
	opts = opts or {}
	local runAsync = not opts.runSync

	if not player or not player:IsA("Player") then return end
	if type(zoneId) ~= "string" or type(mode) ~= "string" or type(gridList) ~= "table" then return end

	if not ZoneRequirementsChecker.isBuildingZone(mode) then
		if opts.onFinished then pcall(opts.onFinished) end
		return
	end

	local startTime = os.clock()
	local function work()
		local cached = getCachedRequirements(player, zoneId)
		if cached then
			ZoneTrackerModule.markZoneRequirement(player, zoneId, "Road",  cached.hasRoad)
			ZoneTrackerModule.markZoneRequirement(player, zoneId, "Water", cached.hasWater)
			ZoneTrackerModule.markZoneRequirement(player, zoneId, "Power", cached.hasPower)
			if cached.hasRoad then ZoneRequirementsChecker.attemptActivatePendingZone(player, zoneId) end
			if DEBUG then
				print(string.format("checkZoneRequirements (cached) in %.4fs for '%s'",
					os.clock() - startTime, zoneId))
			end
			scheduleHappinessPublish(player, 0.02)
			if opts.onFinished then pcall(opts.onFinished) end
			return
		end

		local success, err = pcall(function()
			local allRoad,  missR = ZoneRequirementsChecker.evaluateRoadsForZone(player, zoneId, mode, gridList)
			local allWater, missW = ZoneRequirementsChecker.evaluateWaterForZone(player, zoneId, gridList)
			local allPower, missP = ZoneRequirementsChecker.evaluatePowerForZone(player, zoneId, gridList)

			ZoneTrackerModule.markZoneRequirement(player, zoneId, "Road",  allRoad)
			ZoneTrackerModule.markZoneRequirement(player, zoneId, "Water", allWater)
			ZoneTrackerModule.markZoneRequirement(player, zoneId, "Power", allPower)

			if not allRoad then
				ZoneRequirementsChecker.notifyPlayer(player, ("Zone '%s' needs a road within %d blocks."):format(zoneId, SEARCH_RADIUS))
			end
			if not allWater then
				ZoneRequirementsChecker.notifyPlayer(player, ("Zone '%s' needs water. Build tower/pipes within %d blocks."):format(zoneId, SEARCH_RADIUS))
			end
			if not allPower then
				ZoneRequirementsChecker.notifyPlayer(player, ("Zone '%s' needs power. Build plant/lines within %d blocks."):format(zoneId, SEARCH_RADIUS))
			end

			-- >>> ADDED: sequence bump per alarmType
			local seqR = _bumpSeq(AlarmSeq, player, zoneId, "AlarmRoad")
			ZoneRequirementsChecker.updateTileAlarms(player, zoneId, "AlarmRoad",  missR, seqR)
			local seqW = _bumpSeq(AlarmSeq, player, zoneId, "AlarmWater")
			ZoneRequirementsChecker.updateTileAlarms(player, zoneId, "AlarmWater", missW, seqW)
			local seqP = _bumpSeq(AlarmSeq, player, zoneId, "AlarmPower")
			ZoneRequirementsChecker.updateTileAlarms(player, zoneId, "AlarmPower", missP, seqP)

			setCachedRequirements(player, zoneId, allRoad, allWater, allPower)

			if allRoad then ZoneRequirementsChecker.attemptActivatePendingZone(player, zoneId) end
		end)
		if not success then
			warn(string.format("Error in checkZoneRequirements('%s'): %s", zoneId, err))
		end

		if DEBUG then
			print(string.format("checkZoneRequirements executed in %.4fs for '%s'", os.clock() - startTime, zoneId))
		end

		scheduleHappinessPublish(player, 0.02)
		if opts.onFinished then pcall(opts.onFinished) end
	end

	if runAsync then
		task.spawn(work)
	else
		work()
	end
end

function ZoneRequirementsChecker.checkNearbyRoad(player, zoneId, mode, gridList)
	for _, coord in pairs(gridList) do
		if type(coord) == "table" and type(coord.x) == "number" and type(coord.z) == "number" then
			local nearbyRoads = roadSpatialGrid:getNearbyZones(coord.x, coord.z, SEARCH_RADIUS)
			for _, roadZone in ipairs(nearbyRoads) do
				for _, roadCoord in ipairs(roadZone.gridList or {}) do
					local dx = roadCoord.x - coord.x
					local dz = roadCoord.z - coord.z
					if (dx * dx + dz * dz) <= (SEARCH_RADIUS * SEARCH_RADIUS) then
						local connectedToSource = NetworkManager.isZoneConnected(player, roadZone.zoneId, "Road")
						if connectedToSource then
							return true
						end
					end
				end
			end
		end
	end
	return false
end

function ZoneRequirementsChecker.zoneHasWater(player, zoneId, gridList, radius)
	for _, coord in ipairs(gridList) do
		local nearbyWaters = waterSpatialGrid:getNearbyZones(coord.x, coord.z, radius)
		for _, waterZone in ipairs(nearbyWaters) do
			for _, waterCoord in ipairs(waterZone.gridList or {}) do
				local dx = waterCoord.x - coord.x
				local dz = waterCoord.z - coord.z
				if (dx * dx + dz * dz) <= (radius * radius) then
					local connected = NetworkManager.isCellConnectedToSource(player, "Water", waterCoord.x, waterCoord.z)
					if connected then
						debugPrint(string.format("Found connected water zone '%s' at (%d, %d).",
							waterZone.mode, waterCoord.x, waterCoord.z))
						return true
					end
				end
			end
		end
	end
	return false
end

function ZoneRequirementsChecker.zoneHasPower(player, zoneId, gridList, radius)
	for _, coord in ipairs(gridList) do
		local nearbyPowers = powerSpatialGrid:getNearbyZones(coord.x, coord.z, radius)
		for _, powerZone in ipairs(nearbyPowers) do
			for _, powerCoord in ipairs(powerZone.gridList or {}) do
				local dx = powerCoord.x - coord.x
				local dz = powerCoord.z - coord.z
				if (dx * dx + dz * dz) <= (radius * radius) then
					local connected = NetworkManager.isCellConnectedToSource(player, "Power", powerCoord.x, powerCoord.z)
					if connected then
						debugPrint(string.format("Found connected power zone '%s' at (%d, %d).",
							powerZone.mode, powerCoord.x, powerCoord.z))
						return true
					end
				end
			end
		end
	end
	return false
end

function ZoneRequirementsChecker.isZoneConnectedToWater(player, zoneId)
	return NetworkManager.isZoneConnected(player, zoneId, "Water")
end

----------------------------------------------------------------------
-- 10) Infrastructure checks after creation (Water/Power) or removal
----------------------------------------------------------------------
function ZoneRequirementsChecker.checkPendingRoadRequirements(player, zoneId, mode, gridList)
	--if isReloading(player) then return end 
	local touched = collectDistinctNearbyBuildingZones(gridList, SEARCH_RADIUS)

	for _, bZone in pairs(touched) do
		local data = ZoneTrackerModule.getZoneById(player, bZone.zoneId)
		if not data then continue end

		local wasOK = data.requirements and data.requirements["Road"] == true
		local allRoad, missR = ZoneRequirementsChecker.evaluateRoadsForZone(
			player, bZone.zoneId, data.mode, data.gridList)
		local seqR = _bumpSeq(AlarmSeq, player, bZone.zoneId, "AlarmRoad") -- >>> ADDED
		ZoneRequirementsChecker.updateTileAlarms(player, bZone.zoneId, "AlarmRoad", missR, seqR)

		if allRoad and not wasOK then
			ZoneTrackerModule.markZoneRequirement(player, bZone.zoneId, "Road", true)
			ZoneRequirementsChecker.notifyPlayer(player, ("Zone '%s' is now connected to a road."):format(bZone.zoneId))
			ZoneRequirementsChecker.attemptActivatePendingZone(player, bZone.zoneId)
		elseif not allRoad and wasOK then
			ZoneTrackerModule.markZoneRequirement(player, bZone.zoneId, "Road", false)
			ZoneRequirementsChecker.notifyPlayer(player, ("Zone '%s' lost road connection."):format(bZone.zoneId))
		end

		local allWater, missW = ZoneRequirementsChecker.evaluateWaterForZone(player, bZone.zoneId, data.gridList)
		ZoneTrackerModule.markZoneRequirement(player, bZone.zoneId, "Water", allWater)
		local seqW = _bumpSeq(AlarmSeq, player, bZone.zoneId, "AlarmWater") -- >>> ADDED
		ZoneRequirementsChecker.updateTileAlarms(player, bZone.zoneId, "AlarmWater", missW, seqW)

		local allPower, missP = ZoneRequirementsChecker.evaluatePowerForZone(player, bZone.zoneId, data.gridList)
		ZoneTrackerModule.markZoneRequirement(player, bZone.zoneId, "Power", allPower)
		local seqP = _bumpSeq(AlarmSeq, player, bZone.zoneId, "AlarmPower") -- >>> ADDED
		ZoneRequirementsChecker.updateTileAlarms(player, bZone.zoneId, "AlarmPower", missP, seqP)

		setCachedRequirements(player, bZone.zoneId, allRoad, allWater, allPower)
	end
end

function ZoneRequirementsChecker.checkPendingWaterRequirements(player, zoneId, mode, gridList)
	--if isReloading(player) then return end
	local touched = collectDistinctNearbyBuildingZones(gridList, SEARCH_RADIUS)

	for _, bZone in pairs(touched) do
		local data = ZoneTrackerModule.getZoneById(player, bZone.zoneId)
		if not data then continue end

		local wasOK = data.requirements and data.requirements["Water"] == true
		local allWater, missW = ZoneRequirementsChecker.evaluateWaterForZone(player, bZone.zoneId, data.gridList)
		local seqW = _bumpSeq(AlarmSeq, player, bZone.zoneId, "AlarmWater") -- >>> ADDED
		ZoneRequirementsChecker.updateTileAlarms(player, bZone.zoneId, "AlarmWater", missW, seqW)

		if allWater and not wasOK then
			ZoneTrackerModule.markZoneRequirement(player, bZone.zoneId, "Water", true)
			ZoneRequirementsChecker.notifyPlayer(player, ("Zone '%s' now has water."):format(bZone.zoneId))
			ZoneRequirementsChecker.attemptActivatePendingZone(player, bZone.zoneId)
		elseif not allWater and wasOK then
			ZoneTrackerModule.markZoneRequirement(player, bZone.zoneId, "Water", false)
			ZoneRequirementsChecker.notifyPlayer(player, ("Zone '%s' lost water connection."):format(bZone.zoneId))
		end

		task.defer(function()
			local allPower, missP = ZoneRequirementsChecker.evaluatePowerForZone(player, bZone.zoneId, data.gridList)
			ZoneTrackerModule.markZoneRequirement(player, bZone.zoneId, "Power", allPower)
			local seqP = _bumpSeq(AlarmSeq, player, bZone.zoneId, "AlarmPower") -- >>> ADDED
			ZoneRequirementsChecker.updateTileAlarms(player, bZone.zoneId, "AlarmPower", missP, seqP)
		end)
	end
end

function ZoneRequirementsChecker.checkPendingPowerRequirements(player, zoneId, mode, gridList)
	--if isReloading(player) then return end
	local touched = collectDistinctNearbyBuildingZones(gridList, SEARCH_RADIUS)

	for _, bZone in pairs(touched) do
		local data = ZoneTrackerModule.getZoneById(player, bZone.zoneId)
		if not data then continue end

		local wasOK = data.requirements and data.requirements["Power"] == true
		local allPower, missP = ZoneRequirementsChecker.evaluatePowerForZone(player, bZone.zoneId, data.gridList)
		local seqP = _bumpSeq(AlarmSeq, player, bZone.zoneId, "AlarmPower") -- >>> ADDED
		ZoneRequirementsChecker.updateTileAlarms(player, bZone.zoneId, "AlarmPower", missP, seqP)

		if allPower and not wasOK then
			ZoneTrackerModule.markZoneRequirement(player, bZone.zoneId, "Power", true)
			ZoneRequirementsChecker.notifyPlayer(player, ("Zone '%s' now has power."):format(bZone.zoneId))
		elseif not allPower and wasOK then
			ZoneTrackerModule.markZoneRequirement(player, bZone.zoneId, "Power", false)
			ZoneRequirementsChecker.notifyPlayer(player, ("Zone '%s' lost power connection."):format(bZone.zoneId))
		end
	end
end

----------------------------------------------------------------------
-- 11) CHECKING AFTER INFRASTRUCTURE REMOVAL
----------------------------------------------------------------------
function ZoneRequirementsChecker.checkDependentZonesAfterRoadRemoval(player, removedRoadId, removedRoadGridList)
	local touched = collectDistinctNearbyBuildingZones(removedRoadGridList, SEARCH_RADIUS)

	for _, bZone in pairs(touched) do
		local data = ZoneTrackerModule.getZoneById(player, bZone.zoneId)
		if not data then continue end

		local wasOK = data.requirements and data.requirements["Road"] == true
		local allRoad, missR = ZoneRequirementsChecker.evaluateRoadsForZone(player, bZone.zoneId, data.mode, data.gridList)
		local seqR = _bumpSeq(AlarmSeq, player, bZone.zoneId, "AlarmRoad") -- >>> ADDED
		ZoneRequirementsChecker.updateTileAlarms(player, bZone.zoneId, "AlarmRoad", missR, seqR)

		if allRoad and not wasOK then
			ZoneTrackerModule.markZoneRequirement(player, bZone.zoneId, "Road", true)
			ZoneRequirementsChecker.notifyPlayer(player, ("Zone '%s' is again connected to a road."):format(bZone.zoneId))
			ZoneRequirementsChecker.attemptActivatePendingZone(player, bZone.zoneId)
		elseif not allRoad and wasOK then
			ZoneTrackerModule.markZoneRequirement(player, bZone.zoneId, "Road", false)
			ZoneRequirementsChecker.notifyPlayer(player, ("Zone '%s' is no longer connected to a road."):format(bZone.zoneId))
		end

		local allWater, missW = ZoneRequirementsChecker.evaluateWaterForZone(player, bZone.zoneId, data.gridList)
		local seqW = _bumpSeq(AlarmSeq, player, bZone.zoneId, "AlarmWater") -- >>> ADDED
		ZoneRequirementsChecker.updateTileAlarms(player, bZone.zoneId, "AlarmWater", missW, seqW)
		ZoneTrackerModule.markZoneRequirement(player, bZone.zoneId, "Water", allWater)

		local allPower, missP = ZoneRequirementsChecker.evaluatePowerForZone(player, bZone.zoneId, data.gridList)
		local seqP = _bumpSeq(AlarmSeq, player, bZone.zoneId, "AlarmPower") -- >>> ADDED
		ZoneRequirementsChecker.updateTileAlarms(player, bZone.zoneId, "AlarmPower", missP, seqP)
		ZoneTrackerModule.markZoneRequirement(player, bZone.zoneId, "Power", allPower)
	end
end

function ZoneRequirementsChecker.checkDependentZonesAfterWaterRemoval(player, removedWaterId, removedWaterGridList)
	local touched = collectDistinctNearbyBuildingZones(removedWaterGridList, SEARCH_RADIUS)

	for _, bZone in pairs(touched) do
		local data = ZoneTrackerModule.getZoneById(player, bZone.zoneId)
		if not data then continue end

		local allOK, miss = ZoneRequirementsChecker.evaluateWaterForZone(player, bZone.zoneId, data.gridList)
		local seqW = _bumpSeq(AlarmSeq, player, bZone.zoneId, "AlarmWater") -- >>> ADDED
		ZoneRequirementsChecker.updateTileAlarms(player, bZone.zoneId, "AlarmWater", miss, seqW)

		if not allOK then
			ZoneTrackerModule.markZoneRequirement(player, bZone.zoneId, "Water", false)
			ZoneRequirementsChecker.notifyPlayer(player, ("Zone '%s' is no longer connected to water."):format(bZone.zoneId))
		end
	end
end

function ZoneRequirementsChecker.checkDependentZonesAfterPowerRemoval(player, removedPowerId, removedPowerGridList)
	local touched = collectDistinctNearbyBuildingZones(removedPowerGridList, SEARCH_RADIUS)

	for _, bZone in pairs(touched) do
		local data = ZoneTrackerModule.getZoneById(player, bZone.zoneId)
		if not data then continue end

		local allOK, miss = ZoneRequirementsChecker.evaluatePowerForZone(player, bZone.zoneId, data.gridList)
		local seqP = _bumpSeq(AlarmSeq, player, bZone.zoneId, "AlarmPower") -- >>> ADDED
		ZoneRequirementsChecker.updateTileAlarms(player, bZone.zoneId, "AlarmPower", miss, seqP)

		if not allOK then
			ZoneTrackerModule.markZoneRequirement(player, bZone.zoneId, "Power", false)
			ZoneRequirementsChecker.notifyPlayer(player, ("Zone '%s' is no longer connected to power."):format(bZone.zoneId))
		end
	end
end

local function gatherComponentInfraCoords(player, networkType, seedZoneId)
	local ids = {}
	if NetworkManager.getConnectedZoneIds then
		ids = NetworkManager.getConnectedZoneIds(player, seedZoneId, networkType)
	else
		ids = { seedZoneId }
	end

	local coords = {}
	for _, zid in ipairs(ids) do
		local zData = ZoneTrackerModule.getZoneById(player, zid)
		if zData then
			local isInfra =
				(networkType == "Water" and (waterInfrastructureModes[zData.mode] == true)) or
				(networkType == "Power" and (powerInfrastructureModes[zData.mode] == true)) or
				(networkType == "Road"  and (roadInfrastructureModes[zData.mode]  == true))
			if isInfra then
				for _, c in ipairs(zData.gridList or {}) do
					table.insert(coords, c)
				end
			end
		end
	end
	return coords
end

local function recheckBuildingsAroundCoords(player, coordList, which)
	local seen = {}
	for _, c in ipairs(coordList) do
		for _, bZone in ipairs(buildingSpatialGrid:getNearbyZones(c.x, c.z, SEARCH_RADIUS)) do
			if bZone and bZone.zoneId then
				seen[bZone.zoneId] = true
			end
		end
	end

	for bId in pairs(seen) do
		local data = ZoneTrackerModule.getZoneById(player, bId)
		if data then
			if which == "Water" then
				local allW, missW = ZoneRequirementsChecker.evaluateWaterForZone(player, bId, data.gridList)
				ZoneTrackerModule.markZoneRequirement(player, bId, "Water", allW)
				local seqW = _bumpSeq(AlarmSeq, player, bId, "AlarmWater") -- >>> ADDED
				ZoneRequirementsChecker.updateTileAlarms(player, bId, "AlarmWater", missW, seqW)
				if allW then ZoneRequirementsChecker.attemptActivatePendingZone(player, bId) end

			elseif which == "Road" then
				local allR, missR = ZoneRequirementsChecker.evaluateRoadsForZone(player, bId, data.mode, data.gridList)
				ZoneTrackerModule.markZoneRequirement(player, bId, "Road", allR)
				local seqR = _bumpSeq(AlarmSeq, player, bId, "AlarmRoad") -- >>> ADDED
				ZoneRequirementsChecker.updateTileAlarms(player, bId, "AlarmRoad", missR, seqR)
				if allR then ZoneRequirementsChecker.attemptActivatePendingZone(player, bId) end

			else -- Power
				local allP, missP = ZoneRequirementsChecker.evaluatePowerForZone(player, bId, data.gridList)
				ZoneTrackerModule.markZoneRequirement(player, bId, "Power", allP)
				local seqP = _bumpSeq(AlarmSeq, player, bId, "AlarmPower") -- >>> ADDED
				ZoneRequirementsChecker.updateTileAlarms(player, bId, "AlarmPower", missP, seqP)
			end
		end
	end
end

-- ==================================================================
-- Temp-only “dirty” evaluators (no writes / no normal alarms)
-- ==================================================================
local function dirtyEvaluateRoadsForTiles(player, zoneId, mode, tiles)
	if not ZoneRequirementsChecker.isBuildingZone(mode) then return {} end
	local miss = {}
	for _, c in ipairs(tiles) do
		local ok = ZoneRequirementsChecker.checkNearbyRoad(player, zoneId, mode, { c })
		if not ok then miss[#miss+1] = c end
	end
	return miss
end

local function dirtyEvaluateWaterForTiles(player, zoneId, mode, tiles)
	if not ZoneRequirementsChecker.isBuildingZone(mode) then return {} end
	local zData = ZoneTrackerModule.getZoneById(player, zoneId)
	if not (zData and zData.gridList) then return {} end

	local produced, required = getComponentBudget(player, zoneId, "Water", { gridAware = true })
	local servedSet = nil
	if produced < required then
		servedSet = allocateTilesForZone(player, zoneId, "Water", zData.gridList, produced, required, SEARCH_RADIUS)
	end

	local miss = {}
	for _, c in ipairs(tiles) do
		local reachable = ZoneRequirementsChecker.zoneHasWater(player, zoneId, { c }, SEARCH_RADIUS)
		local ok = (produced >= required) and reachable
			or (reachable and servedSet and servedSet[("%d_%d"):format(c.x, c.z)] == true)
		if not ok then miss[#miss+1] = c end
	end
	return miss
end

local function dirtyEvaluatePowerForTiles(player, zoneId, mode, tiles)
	if not ZoneRequirementsChecker.isBuildingZone(mode) then return {} end
	local zData = ZoneTrackerModule.getZoneById(player, zoneId)
	if not (zData and zData.gridList) then return {} end

	local produced, required = getComponentBudget(player, zoneId, "Power", { gridAware = true })
	local servedSet = nil
	if produced < required then
		servedSet = allocateTilesForZone(player, zoneId, "Power", zData.gridList, produced, required, SEARCH_RADIUS)
	end

	local miss = {}
	for _, c in ipairs(tiles) do
		local reachable = ZoneRequirementsChecker.zoneHasPower(player, zoneId, { c }, SEARCH_RADIUS)
		local ok = (produced >= required) and reachable
			or (reachable and servedSet and servedSet[("%d_%d"):format(c.x, c.z)] == true)
		if not ok then miss[#miss+1] = c end
	end
	return miss
end

-- Helper: collect ALL current temp-alarm coords for this zone
local function collectTempAlarmCoords(zoneModel)
	local coords = {}   -- list
	local seen   = {}   -- key set
	local f = zoneModel and zoneModel:FindFirstChild(TEMP_ALARM_FOLDER_NAME)
	if not f then return coords end
	for _, ch in ipairs(f:GetChildren()) do
		if ch:IsA("BasePart") then
			local x, z = ch.Name:match("^Alarm%u%l+_([%-0-9]+)_([%-0-9]+)$")
			if x and z then
				local k = x .. "_" .. z
				if not seen[k] then
					seen[k] = true
					table.insert(coords, { x = tonumber(x), z = tonumber(z) })
				end
			end
		end
	end
	return coords
end

-- UPDATED: Wigi temp-alarms; refresh **all existing temp tiles + current tile** (temp-only).
WigiPlacedEvent.Event:Connect(function(player, zoneId, payload)
	if not SHOW_POPULATING_ALARMS then return end
	if not player or not zoneId or not payload then return end
	if isZonePopulated(player, zoneId) then return end

	if LOAD_AWARE_SKIP_TEMP_ALARMS and WorldReloadActiveByUid[player.UserId] then
		return
	end

	local zData = ZoneTrackerModule.getZoneById(player, zoneId)
	local zMode = zData and zData.mode
	if not (zMode and buildingZoneTypes[zMode]) then return end

	local gx, gz = payload.gridX, payload.gridZ
	if typeof(gx) ~= "number" or typeof(gz) ~= "number" then return end
	local current = { x = gx, z = gz }

	-- Build scope = all coords with existing temp alarms for this zone + current Wigi tile
	local zoneModel = select(1, getZoneModelFor(player, zoneId))
	if not zoneModel then return end
	local scope = collectTempAlarmCoords(zoneModel)
	-- Include current if not already present
	do
		local already = false
		for i = 1, #scope do
			if scope[i].x == current.x and scope[i].z == current.z then
				already = true; break
			end
		end
		if not already then table.insert(scope, current) end
	end
	if #scope == 0 then scope = { current } end

	-- Temp-only “dirty” evaluation: NO writes to ZoneTracker, NO normal alarms, NO notifications.
	-- Order matters for priority visuals: Road → Water → Power
	local missR = dirtyEvaluateRoadsForTiles(player, zoneId, zMode, scope)
	local seqR  = _bumpSeq(TempAlarmSeq, player, zoneId, "AlarmRoad") -- >>> ADDED
	ZoneRequirementsChecker.updateTempTileAlarms(player, zoneId, "AlarmRoad",  missR, scope, seqR)

	local missW = dirtyEvaluateWaterForTiles(player, zoneId, zMode, scope)
	local seqW  = _bumpSeq(TempAlarmSeq, player, zoneId, "AlarmWater") -- >>> ADDED
	ZoneRequirementsChecker.updateTempTileAlarms(player, zoneId, "AlarmWater", missW, scope, seqW)

	local missP = dirtyEvaluatePowerForTiles(player, zoneId, zMode, scope)
	local seqP  = _bumpSeq(TempAlarmSeq, player, zoneId, "AlarmPower") -- >>> ADDED
	ZoneRequirementsChecker.updateTempTileAlarms(player, zoneId, "AlarmPower", missP, scope, seqP)
end)

function ZoneRequirementsChecker.recomputeAndPublishHappiness(player)
	if not (player and player:IsA("Player")) then return end

	local happiness = ZoneTrackerModule.computeInfrastructureHappiness(player)

	local BindableEvents = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents")
	local StatsChanged = BindableEvents:FindFirstChild("StatsChanged")
	if StatsChanged then
		StatsChanged:Fire(player)
	end

	local totals, produced = getProductionSnapshot(player)
	local tW, tP = (totals.water or 0),  (totals.power or 0)
	local pW, pP = (produced.water or 0), (produced.power or 0)
	if UtilityAlertsRE then
		UtilityAlertsRE:FireClient(player, {
			waterInsufficient = pW < tW,
			powerInsufficient = pP < tP,
			waterRequired = tW, waterProduced = pW,
			powerRequired = tP, powerProduced = pP,
			waterDeficit = math.max(0, tW - pW),
			powerDeficit = math.max(0, tP - pP),
		})
	end

	if DEBUG then
		print(("[ZoneRequirementsChecker] Happiness recomputed for %s: %d%%"):format(player.Name, happiness))
	end
end

----------------------------------------------------------------------
-- 12) Listen for "NetworkReady" events (infrastructure connectivity)
----------------------------------------------------------------------
NetworkReadyEvent.Event:Connect(function(player, zoneId, zoneData)
	if waterInfrastructureModes[zoneData.mode] then
		ZoneRequirementsChecker.checkPendingWaterRequirements(player, zoneId, zoneData.mode, zoneData.gridList)
		local coords = gatherComponentInfraCoords(player, "Water", zoneId)
		task.defer(function()
			recheckBuildingsAroundCoords(player, coords, "Water")
			scheduleHappinessPublish(player, 0.03)
		end)

	elseif roadInfrastructureModes[zoneData.mode] then
		ZoneRequirementsChecker.checkPendingRoadRequirements(player, zoneId, zoneData.mode, zoneData.gridList)
		local coords = gatherComponentInfraCoords(player, "Road", zoneId)
		task.defer(function()
			recheckBuildingsAroundCoords(player, coords, "Road")
			recheckBuildingsAroundCoords(player, coords, "Water")
			recheckBuildingsAroundCoords(player, coords, "Power")
			scheduleHappinessPublish(player, 0.03)
		end)

	elseif powerInfrastructureModes[zoneData.mode] then
		ZoneRequirementsChecker.checkPendingPowerRequirements(player, zoneId, zoneData.mode, zoneData.gridList)
		local coords = gatherComponentInfraCoords(player, "Power", zoneId)
		task.defer(function()
			recheckBuildingsAroundCoords(player, coords, "Power")
			scheduleHappinessPublish(player, 0.03)
		end)
	end
end)

function NetworkManager.removeZoneFromNetwork(player, zoneId, networkType)
	local pnets = NetworkManager.networks[player.UserId]
	local net = pnets and pnets[networkType]
	if not (net and net.zones[zoneId]) then return end

	local zData = net.zones[zoneId]

	local neighbours = {}
	do
		local adj = net.adjacency[zoneId]
		if adj then
			for i = 1, #adj do
				local nid = adj[i]
				if nid and nid ~= zoneId then
					neighbours[#neighbours+1] = nid
				end
			end
		end
	end

	if zData and zData.gridList then
		for _, coord in ipairs(zData.gridList) do
			if type(coord) == "table" and type(coord.x) == "number" and type(coord.z) == "number" then
				local k = tostring(coord.x) .. "|" .. tostring(coord.z)
				local bucket = net.cells and net.cells[k]
				if bucket then
					bucket[zoneId] = nil
					local empty = true
					for _ in pairs(bucket) do empty = false break end
					if empty then net.cells[k] = nil end
				end
			end
		end
	end

	for _, list in pairs(net.adjacency) do
		for i = #list, 1, -1 do
			if list[i] == zoneId then
				table.remove(list, i)
			end
		end
	end
	net.adjacency[zoneId] = nil

	net.zones[zoneId] = nil
	if net.unionFind then
		net.unionFind.parent[zoneId] = nil
		net.unionFind.rank[zoneId]   = nil
	end

	NetworkManager.rebuildUnionFind(player, networkType)

	for _, nid in ipairs(neighbours) do
		local nz = net.zones[nid]
		if nz then
			NetworkReadyEvent:Fire(player, nid, nz)
		end
	end
end

function ZoneRequirementsChecker.clearPlayerData(player)
	zoneRequirementCache[player.UserId] = nil
	pendingAlarms[player.UserId]        = nil
	zonePopulated[player.UserId]        = nil
	AlarmSeq[player.UserId]             = nil -- >>> ADDED
	TempAlarmSeq[player.UserId]         = nil -- >>> ADDED

	-- flush any alarm parts sitting in the pool
	for _, pool in pairs(AlarmPool) do
		for i = #pool, 1, -1 do
			pool[i]:Destroy()
			pool[i] = nil
		end
	end
end

return ZoneRequirementsChecker
