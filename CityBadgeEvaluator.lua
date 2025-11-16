local CityBadgeEvaluator = {}
CityBadgeEvaluator.__index = CityBadgeEvaluator

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BadgeServiceModule = require(ServerScriptService.Services.BadgeService)
local BuildFolder = ServerScriptService:WaitForChild("Build")
local Zones = BuildFolder:WaitForChild("Zones")
local ZonesFolder = Zones:WaitForChild("ZoneManager")
local ZoneTrackerModule = require(ZonesFolder:WaitForChild("ZoneTracker"))
local Balance = require(ReplicatedStorage.Balancing.BalanceEconomy)

local BindableEvents = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents")

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

local CATEGORY_DATA = {}
local INFRA_REQUIRED_MODES = {}
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

	for _, zone in pairs(zones) do
		local mode = zone.mode
		local online = zoneIsOnline(zone)

		if zoneNeedsInfrastructure(mode) and not online then
			allInfraOnline = false
		end

		if online then
			if REQUIRED_ZONE_GROUPS.Residential[mode] then
				hasZones.Residential = true
			elseif REQUIRED_ZONE_GROUPS.Commercial[mode] then
				hasZones.Commercial = true
			elseif REQUIRED_ZONE_GROUPS.Industrial[mode] then
				hasZones.Industrial = true
			end

			for label, set in pairs(CATEGORY_DATA) do
				if set[mode] then
					serviceCoverage[label] = true
				end
			end
		end
	end

	if not (hasZones.Residential and hasZones.Commercial and hasZones.Industrial) then
		return
	end

	for label in pairs(CATEGORY_DATA) do
		if not serviceCoverage[label] then
			return
		end
	end

	if not allInfraOnline then
		return
	end

	BadgeServiceModule.AwardCityBeginnings(player)
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
