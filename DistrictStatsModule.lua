local DistrictStatsModule = {}
DistrictStatsModule.__index = DistrictStatsModule

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Events = ReplicatedStorage:WaitForChild("Events")
local BindableEvents = Events:WaitForChild("BindableEvents")
local StatsChanged = BindableEvents:WaitForChild("StatsChanged")

local Balance = require(game.ReplicatedStorage.Balancing.BalanceEconomy)
local ZoneTrackerModule = require(game.ServerScriptService.Build.Zones.ZoneManager.ZoneTracker)

local DEBUG = false
local function dprint(...)
	if DEBUG then
		print(...)
	end
end
local function dwarn(...)
	if DEBUG then
		warn(...)
	end
end
local function TRACE(tag)
	if DEBUG then
		-- skip the TRACE frame itself so the top of the stack is the caller
		warn(string.format("[DistrictStats][%s]\n%s", tag, debug.traceback("", 2)))
	end
end

TRACE("MODULE LOADED")

local WHITELISTED_ZONE_TYPES = {
	Residential = true,
	Commercial  = true,
	Industrial  = true,
	ResDense    = true,
	CommDense   = true,
	IndusDense  = true,
}

-- Holds final stats per zoneId
local zoneStats = {}
local utilityZones = {}
local utilityProducers = {}

local function fireStatsChanged(player)
	if player then
		StatsChanged:Fire(player)
	end
end

-- Create new zone stat entry
local function calculateStats(zoneId, zoneData)
	-- Sum per-tile using the actual stored wealth for each tile
	local mode = zoneData.mode
	local grid = zoneData.gridList or {}
	local player = zoneData.player
	if not mode or not player then return end

	local pop, inc, waterReq, powerReq, expSum = 0, 0, 0, 0, 0

	for _, coord in ipairs(grid) do
		local wealth = ZoneTrackerModule.getGridWealth(player, zoneId, coord.x, coord.z) or "nil"
		local cfgTbl = Balance.StatConfig[mode]
		local cfg    = cfgTbl and cfgTbl[wealth]
		if cfg then
			pop      += cfg.population
			inc      += cfg.income
			waterReq += cfg.water
			powerReq += cfg.power
			expSum   += (cfg.exp or 0)
		else
			dwarn(("Missing StatConfig for mode=%s wealth=%s"):format(tostring(mode), tostring(wealth)))
		end
	end

	zoneStats[zoneId] = {
		playerUserId = player.UserId,
		mode         = mode,
		gridCount    = #grid,
		population   = pop,
		income       = inc,
		water        = waterReq,
		power        = powerReq,
		exp          = expSum,
	}
end

local function calculatePlayerHappiness(player)
	local zoneCounts = ZoneTrackerModule.getZoneTypeCounts(player)
	local totalZones = 0
	local uniqueTypes = 0

	for zoneType, count in pairs(zoneCounts) do
		totalZones += count
		if count > 0 then
			uniqueTypes += 1
		end
	end

	local ratio = totalZones > 0 and (uniqueTypes / totalZones) or 0
	local happiness

	if ratio >= 0.75 then
		happiness = 100
	elseif ratio >= 0.5 then
		happiness = 75
	elseif ratio >= 0.25 then
		happiness = 50
	elseif ratio > 0 then
		happiness = 25
	else
		happiness = 0
	end

	return happiness
end

local function printTotalStats()
	TRACE("printTotalStats")
	local total = {population = 0, income = 0, water = 0, power = 0, exp = 0}
	for _, stats in pairs(zoneStats) do
		total.population += stats.population
		total.income += stats.income
		total.water += stats.water
		total.power += stats.power
		total.exp += stats.exp or 0 
	end

	dprint("EXP Earned:         ", total.exp)

	local produced = {water = 0, power = 0}
	for _, prod in pairs(utilityProducers) do
		produced.water += prod.water
		produced.power += prod.power
	end

	dprint("=== CITY TOTAL STATS ===")
	dprint("Population:         ", total.population)
	dprint("Income:             ", total.income)
	dprint("Water Required:     ", total.water)
	dprint("Power Required:     ", total.power)
	dprint("Water Produced:     ", produced.water)
	dprint("Power Produced:     ", produced.power)
	dprint("========================")
end

-- Zone Added
function DistrictStatsModule.onZoneAdded(zoneId, zoneData)
	TRACE("onZoneAdded  zoneId=" .. tostring(zoneId))
	local mode = zoneData.mode
	dprint("[ZONE ADDED]", zoneId, mode)

	-- Utilities first: always treat via ProductionConfig (bypass whitelist)
	if Balance.ProductionConfig[mode] then
		if utilityZones[zoneId] then
			return -- Prevent duplicate utility registration
		end
		utilityZones[zoneId] = {playerUserId = zoneData.player.UserId, buildingType = mode}
		DistrictStatsModule.addUtilityBuilding(zoneData.player, mode)
		return
	end

	-- Non-utility zones must be whitelisted to count
	if not WHITELISTED_ZONE_TYPES[mode] then
		-- silently ignore non-whitelisted zone types
		return
	end

	-- Handle regular zones
	zoneData.wealth = zoneData.wealth or "Poor"

	task.delay(1, function()
		if zoneData.gridList and #zoneData.gridList > 0 then
			calculateStats(zoneId, zoneData)
			printTotalStats()
			calculatePlayerHappiness(zoneData.player)
			fireStatsChanged(zoneData.player)
		else
			dwarn("[DELAYED STATS] Skipped due to empty gridList:", zoneId)
		end
	end)
end

-- Zone Removed
function DistrictStatsModule.onZoneRemoved(zoneId)
	TRACE("onZoneRemoved zoneId=" .. tostring(zoneId))
	local utilInfo = utilityZones[zoneId]
	if utilInfo then
		local player = Players:GetPlayerByUserId(utilInfo.playerUserId)
		if player then
			DistrictStatsModule.removeUtilityBuilding(player, utilInfo.buildingType)
			fireStatsChanged(player)
		end
		utilityZones[zoneId] = nil
		return
	end

	local zoneData = zoneStats[zoneId]
	if not zoneData then return end

	zoneStats[zoneId] = nil
	printTotalStats()

	local player = Players:GetPlayerByUserId(zoneData.playerUserId)
	if player then
		calculatePlayerHappiness(player)
		fireStatsChanged(player)
	end
end

-- Called when upgrading wealth level
function DistrictStatsModule.setZoneWealth(player, zoneId, wealthLevel)
	local z = ZoneTrackerModule.getZoneById(player, zoneId)
	if not z then return end
	local cfgTbl = Balance.StatConfig[z.mode]
	if not (cfgTbl and cfgTbl[wealthLevel]) then return end
	-- write per-tile so calculateStats reads correct stored wealth
	for _, c in ipairs(z.gridList) do
		ZoneTrackerModule.setGridWealth(player, zoneId, c.x, c.z, wealthLevel)
	end
	calculateStats(zoneId, z)
	fireStatsChanged(player)
end

function DistrictStatsModule.getStats(zoneId)
	return zoneStats[zoneId]
end

function DistrictStatsModule.getTotalsForPlayer(player)
	local t = { population=0, income=0, water=0, power=0, exp=0 }
	for _, s in pairs(zoneStats) do
		if s.playerUserId == player.UserId then
			t.population += s.population
			t.income     += s.income
			t.water      += s.water
			t.power      += s.power
			t.exp        += (s.exp or 0)
		end
	end
	return t
end

function DistrictStatsModule.getStatsForPlayer(playerUserId)
	local result = {}
	for zoneId, stats in pairs(zoneStats) do
		if stats.playerUserId == playerUserId then
			result[zoneId] = stats
		end
	end

	-- Defensive: if stats somehow went missing (e.g. after a reload hiccup),
	-- rebuild them from the live zones so downstream systems (income, UI) keep working.
	if next(result) == nil then
		local player = Players:GetPlayerByUserId(playerUserId)
		if player then
			local zones = ZoneTrackerModule.getAllZones(player) or {}
			for zid, zdata in pairs(zones) do
				if Balance.ProductionConfig[zdata.mode] then
					if not utilityZones[zid] then
						utilityZones[zid] = { playerUserId = playerUserId, buildingType = zdata.mode }
						DistrictStatsModule.addUtilityBuilding(player, zdata.mode)
					end
				elseif WHITELISTED_ZONE_TYPES[zdata.mode] then
					calculateStats(zid, zdata)
					if zoneStats[zid] then
						result[zid] = zoneStats[zid]
					end
				end
			end
		end
	end

	return result
end

function DistrictStatsModule.clearStatsForPlayer(playerUserId)
	for zoneId, stats in pairs(zoneStats) do
		if stats.playerUserId == playerUserId then
			zoneStats[zoneId] = nil
		end
	end
end

function DistrictStatsModule.addUtilityBuilding(player, buildingType)
	local config = Balance.ProductionConfig[buildingType]
	if not config then
		dwarn("Unknown utility building:", buildingType)
		return
	end
	dprint(string.format("[UTILITY] Adding %s for %s (%dL)", buildingType, player.Name, config.amount))
	local store  = utilityProducers[player.UserId] or {water=0, power=0}
	-- ensure keys exist to avoid nil arithmetic
	store.water = store.water or 0
	store.power = store.power or 0
	store[config.type] = (store[config.type] or 0) + config.amount
	utilityProducers[player.UserId] = store

	printTotalStats()
	fireStatsChanged(player)
end

function DistrictStatsModule.removeUtilityBuilding(player, buildingType)
	local config = Balance.ProductionConfig[buildingType]
	if not config then return end

	local store = utilityProducers[player.UserId]
	if store then
		store[config.type] = math.max(0, (store[config.type] or 0) - config.amount)
	end
	printTotalStats()
	fireStatsChanged(player)
end

function DistrictStatsModule.getUtilityProduction(player)
	return utilityProducers[player.UserId] or { water = 0, power = 0 }
end

function DistrictStatsModule.clearUtilityProduction(playerUserId)
	utilityProducers[playerUserId] = nil
end

function DistrictStatsModule.getHappiness(player)
	return calculatePlayerHappiness(player)
end

function DistrictStatsModule.getZoneDataFor(playerUserId, zoneId)
	local player = Players:GetPlayerByUserId(playerUserId)
	if not player then return nil end
	return ZoneTrackerModule.getZoneById(player, zoneId)
end

function DistrictStatsModule.init()
	TRACE("init() – connecting zoneAddedEvent")
	ZoneTrackerModule.zoneAddedEvent.Event:Connect(function(player, zoneId, zoneData)
		zoneData.player = player
		DistrictStatsModule.onZoneAdded(zoneId, zoneData)
	end)
	TRACE("init() – connecting zoneRemovedEvent")
	ZoneTrackerModule.zoneRemovedEvent.Event:Connect(function(player, zoneId)
		DistrictStatsModule.onZoneRemoved(zoneId)
	end)
end

return DistrictStatsModule
