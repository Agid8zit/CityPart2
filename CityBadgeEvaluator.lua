local CityBadgeEvaluator = {}
CityBadgeEvaluator.__index = CityBadgeEvaluator

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local BadgeServiceModule = require(ServerScriptService.Services.BadgeService)
local BuildFolder = ServerScriptService:WaitForChild("Build")
local Zones = BuildFolder:WaitForChild("Zones")
local ZonesFolder = Zones:WaitForChild("ZoneManager")
local ZoneTrackerModule = require(ZonesFolder:WaitForChild("ZoneTracker"))
local Balance = require(ReplicatedStorage.Balancing.BalanceEconomy)
local DistrictStatsModule = require(ServerScriptService:WaitForChild("DistrictStatsModule"))

local BindableEvents = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents")
local GridScripts = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Grid")
local GridConfig = require(GridScripts:WaitForChild("GridConfig"))
local GetUnlocksBindable = BindableEvents:FindFirstChild("GetUnlocksForPlayer")

local REQUIRED_ZONE_GROUPS = {
	Residential = { Residential = true, ResDense = true },
	Commercial  = { Commercial  = true, CommDense = true },
	Industrial  = { Industrial  = true, IndusDense = true },
}

local SERVICE_CATEGORY_KEYS = {
	Health   = "Health",
	Fire     = "Fire",
	Police   = "Police",
	Leisure  = "Leisure",
	Education= "Education",
	Sports   = "SportsAndRecreation",
	Landmark = "Landmark",
}

local CATEGORY_DATA, INFRA_REQUIRED_MODES = {}, {}
local function registerModes(set)
	for mode in pairs(set) do
		INFRA_REQUIRED_MODES[mode] = true
	end
end

for _, group in pairs(REQUIRED_ZONE_GROUPS) do
	registerModes(group)
end

local balanceCategories = (Balance.UxpConfig and Balance.UxpConfig.Category) or {}
for label, key in pairs(SERVICE_CATEGORY_KEYS) do
	local src = balanceCategories[key] or {}
	local set = {}
	for mode in pairs(src) do
		set[mode] = true
	end
	CATEGORY_DATA[label] = set
	registerModes(set)
end

local RELIGIOUS_BUILDINGS = {
	Church = true,
	Mosque = true,
	ShintoTemple = true,
	HinduTemple = true,
	BuddhaStatue = true,
}

local FLAG_MODES = { Flags = true }
local ResidentialModes = { Residential = true, ResDense = true }
local CommercialModes  = { Commercial = true, CommDense = true }
local IndustrialModes  = { Industrial = true, IndusDense = true }
local SIX_ZONE_LIST = { "Residential", "Commercial", "Industrial", "ResDense", "CommDense", "IndusDense" }

local MAP_EXPANSION_UNLOCKS = {
	Unlock_1 = true,
	Unlock_2 = true,
	Unlock_3 = true,
	Unlock_4 = true,
	Unlock_5 = true,
	Unlock_6 = true,
}

local function zoneNeedsInfrastructure(mode)
	return INFRA_REQUIRED_MODES[mode] == true
end

local function zoneIsOnline(zoneData)
	local req = zoneData and zoneData.requirements
	if not req then
		return false
	end
	return req.Road ~= false and req.Water ~= false and req.Power ~= false
end

local function getPlayerPlot(player)
	local plots = Workspace:FindFirstChild("PlayerPlots")
	if not plots then return nil end
	return plots:FindFirstChild("Plot_" .. player.UserId)
end

local function gatherTerrains(plot)
	local terrains = {}
	if not plot then return terrains end

	local unlocks = plot:FindFirstChild("Unlocks")
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

	return terrains
end

local function getPlotGridBounds(player)
	local plot = getPlayerPlot(player)
	if not plot then return nil end
	local terrains = gatherTerrains(plot)
	if #terrains == 0 then return nil end
	return GridConfig.calculateGlobalBounds(terrains)
end

local function countOccupiedCells(zones)
	local occupied = {}
	local count = 0
	for _, zone in pairs(zones) do
		if zone.gridList then
			for _, coord in ipairs(zone.gridList) do
				if coord and coord.x and coord.z then
					local key = tostring(coord.x) .. "," .. tostring(coord.z)
					if not occupied[key] then
						occupied[key] = true
						count += 1
					end
				end
			end
		end
	end
	return count
end

local function countCellsForModes(zones, modeSet)
	local seen = {}
	local count = 0
	for _, zone in pairs(zones) do
		if modeSet[zone.mode] and zone.gridList then
			for _, coord in ipairs(zone.gridList) do
				local key = tostring(coord.x) .. "," .. tostring(coord.z)
				if not seen[key] then
					seen[key] = true
					count += 1
				end
			end
		end
	end
	return count
end

local function getZoneCellCounts(zones)
	local counts = { Residential = 0, Commercial = 0, Industrial = 0, ResDense = 0, CommDense = 0, IndusDense = 0 }
	for _, zone in pairs(zones) do
		if counts[zone.mode] ~= nil and zone.gridList then
			counts[zone.mode] += #zone.gridList
		end
	end
	return counts
end

local function hasAllModes(found, required)
	if not required or next(required) == nil then
		return false
	end
	for mode in pairs(required) do
		if not found[mode] then
			return false
		end
	end
	return true
end

local function getPopulation(player)
	if not DistrictStatsModule or not DistrictStatsModule.getStatsForPlayer then
		return 0
	end
	local statsByZone = DistrictStatsModule.getStatsForPlayer(player.UserId)
	local total = 0
	for _, stats in pairs(statsByZone or {}) do
		total += stats.population or 0
	end
	return total
end

local function hasAllMapUnlocks(player)
	if not GetUnlocksBindable or not GetUnlocksBindable.IsA or not GetUnlocksBindable:IsA("BindableFunction") then
		return false
	end
	local unlocks = GetUnlocksBindable:Invoke(player)
	if type(unlocks) ~= "table" then
		return false
	end
	for name in pairs(MAP_EXPANSION_UNLOCKS) do
		if unlocks[name] ~= true then
			return false
		end
	end
	return true
end

local function evaluatePlayer(player)
	if not (player and player:IsA("Player")) then
		return
	end

	local zones = ZoneTrackerModule.getAllZones(player)
	if not zones then
		return
	end

	local hasZones = {
		Residential = false,
		Commercial  = false,
		Industrial  = false,
	}
	local serviceCoverage = {}
	for label in pairs(SERVICE_CATEGORY_KEYS) do
		serviceCoverage[label] = false
	end

	local allInfraOnline = true
	local sportsFound = {}
	local religiousFound = {}
	local policeStationCount = 0
	local healthBuildingCount = 0
	local newsStationCount = 0
	local hasFlag = false

	for _, zone in pairs(zones) do
		local mode = zone.mode
		local online = zoneIsOnline(zone)

		if zoneNeedsInfrastructure(mode) and not online then
			allInfraOnline = false
		end

		if REQUIRED_ZONE_GROUPS.Residential[mode] and online then
			hasZones.Residential = true
		elseif REQUIRED_ZONE_GROUPS.Commercial[mode] and online then
			hasZones.Commercial = true
		elseif REQUIRED_ZONE_GROUPS.Industrial[mode] and online then
			hasZones.Industrial = true
		end

		if online then
			for label, set in pairs(CATEGORY_DATA) do
				if set[mode] then
					serviceCoverage[label] = true
				end
			end

			if CATEGORY_DATA.Sports and CATEGORY_DATA.Sports[mode] then
				sportsFound[mode] = true
			end

			if RELIGIOUS_BUILDINGS[mode] then
				religiousFound[mode] = true
			end

			if mode == "PoliceStation" then
				policeStationCount += 1
			end

			if mode == "NewsStation" then
				newsStationCount += 1
			end
		end

		if CATEGORY_DATA.Health and CATEGORY_DATA.Health[mode] then
			healthBuildingCount += 1
		end

		if FLAG_MODES[mode] then
			hasFlag = true
		end
	end

	local hasBaseZones = hasZones.Residential and hasZones.Commercial and hasZones.Industrial
	local hasAllServices = true
	for label in pairs(SERVICE_CATEGORY_KEYS) do
		if not serviceCoverage[label] then
			hasAllServices = false
			break
		end
	end

	local population = getPopulation(player)

	if hasBaseZones and hasAllServices and allInfraOnline then
		BadgeServiceModule.AwardCityBeginnings(player)
		if population >= 100000 then
			BadgeServiceModule.AwardUtopia(player)
		end
	end

	if newsStationCount >= 15 then
		BadgeServiceModule.AwardPropagandaMachine(player)
	end

	if population >= 100000 and healthBuildingCount == 0 then
		BadgeServiceModule.AwardAmericanHealthcare(player)
	end

	if hasAllModes(sportsFound, CATEGORY_DATA.Sports or {}) then
		BadgeServiceModule.AwardAthleticCity(player)
	end

	if hasAllModes(religiousFound, RELIGIOUS_BUILDINGS) then
		BadgeServiceModule.AwardCoexist(player)
	end

	if policeStationCount >= 10 then
		BadgeServiceModule.AwardPoliceState(player)
	end

	if hasFlag then
		BadgeServiceModule.AwardPatriotism(player)
	end

	local bounds = getPlotGridBounds(player)
	local totalCells = 0
	if bounds then
		totalCells = math.max(0, (bounds.gridSizeX or 0)) * math.max(0, (bounds.gridSizeZ or 0))
	end

	local occupiedCells = countOccupiedCells(zones)
	local fullUnlocks = hasAllMapUnlocks(player)

	if fullUnlocks and totalCells > 0 and occupiedCells >= totalCells then
		BadgeServiceModule.AwardHitTheGriddy(player)
	end

	if fullUnlocks and totalCells > 0 then
		local industrialCells = countCellsForModes(zones, IndustrialModes)
		local residentialCells = countCellsForModes(zones, ResidentialModes)
		local commercialCells  = countCellsForModes(zones, CommercialModes)

		if industrialCells / totalCells >= 0.80 then
			BadgeServiceModule.AwardIndusValley(player)
		end
		if residentialCells / totalCells >= 0.80 then
			BadgeServiceModule.AwardOverpopulation(player)
		end
		if commercialCells / totalCells >= 0.80 then
			BadgeServiceModule.AwardAmericanDream(player)
		end
	end

	local sixCounts = getZoneCellCounts(zones)
	local balanced = true
	local baseline = nil
	for _, name in ipairs(SIX_ZONE_LIST) do
		local val = sixCounts[name] or 0
		if val == 0 then
			balanced = false
			break
		end
		if not baseline then
			baseline = val
		elseif val ~= baseline then
			balanced = false
			break
		end
	end
	if balanced then
		BadgeServiceModule.AwardPerfectlyBalanced(player)
	end
end

local function scheduleEvaluation(player)
	if not player then
		return
	end
	task.defer(evaluatePlayer, player)
end

function CityBadgeEvaluator.Init()
	if ZoneTrackerModule.zoneAddedEvent then
		ZoneTrackerModule.zoneAddedEvent.Event:Connect(scheduleEvaluation)
	end
	if ZoneTrackerModule.zoneRemovedEvent then
		ZoneTrackerModule.zoneRemovedEvent.Event:Connect(scheduleEvaluation)
	end

	local requirementChanged = BindableEvents:FindFirstChild("ZoneRequirementChanged")
	if requirementChanged then
		requirementChanged.Event:Connect(scheduleEvaluation)
	end
end

function CityBadgeEvaluator.PlayerAdded(player)
	scheduleEvaluation(player)
end

return CityBadgeEvaluator
