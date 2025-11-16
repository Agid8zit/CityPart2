local PowerBadgeTracker = {}
PowerBadgeTracker.__index = PowerBadgeTracker

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Balance = require(ReplicatedStorage:WaitForChild("Balancing"):WaitForChild("BalanceEconomy"))
local ZoneTrackerModule = require(ServerScriptService.Build.Zones.ZoneManager.ZoneTracker)
local BadgeServiceModule = require(ServerScriptService.Services.BadgeService)

local CLEAN_THRESHOLD = 500000
local DIRTY_THRESHOLD = 500000

local CleanSources = {
	WindTurbine = true,
	SolarPanels = true,
	GeothermalPowerPlant = true,
	NuclearPowerPlant = true,
}

local DirtySources = {
	CoalPowerPlant = true,
	GasPowerPlant = true,
}

local playerTotals = {}        -- [Player] = { clean = number, dirty = number }
local zoneContributions = {}   -- [Player] = { [zoneId] = { bucket = "clean"/"dirty", amount = number } }

local function ensurePlayerTables(player)
	if not playerTotals[player] then
		playerTotals[player] = { clean = 0, dirty = 0 }
	end
	if not zoneContributions[player] then
		zoneContributions[player] = {}
	end
	return playerTotals[player], zoneContributions[player]
end

local function checkBadges(player)
	local totals = playerTotals[player]
	if not totals then return end

	if (totals.clean or 0) >= CLEAN_THRESHOLD and (totals.dirty or 0) == 0 then
		BadgeServiceModule.AwardCleanEnergyBadge(player)
	end
	if (totals.dirty or 0) >= DIRTY_THRESHOLD and (totals.clean or 0) == 0 then
		BadgeServiceModule.AwardDirtyEnergyBadge(player)
	end
end

local function updateContribution(player, zoneId, mode, isRemoval)
	if not player or not mode then return end
	local config = Balance.ProductionConfig[mode]
	if not config or config.type ~= "power" then return end

	local bucket
	if CleanSources[mode] then
		bucket = "clean"
	elseif DirtySources[mode] then
		bucket = "dirty"
	else
		return
	end

	local amount = config.amount or 0
	if amount <= 0 then return end

	local totals, contribs = ensurePlayerTables(player)
	local existing = contribs[zoneId]

	if isRemoval then
		if existing then
			local prevBucket = existing.bucket
			totals[prevBucket] = math.max(0, (totals[prevBucket] or 0) - existing.amount)
			contribs[zoneId] = nil
		else
			-- best-effort: subtract from inferred bucket
			totals[bucket] = math.max(0, (totals[bucket] or 0) - amount)
		end
	else
		if existing then
			totals[existing.bucket] = math.max(0, (totals[existing.bucket] or 0) - existing.amount)
		end
		contribs[zoneId] = { bucket = bucket, amount = amount }
		totals[bucket] = (totals[bucket] or 0) + amount
	end

	checkBadges(player)
end

local function seedPlayer(player)
	if not player then return end
	playerTotals[player] = { clean = 0, dirty = 0 }
	zoneContributions[player] = {}

	local zones = ZoneTrackerModule.getAllZones(player)
	for zoneId, zoneData in pairs(zones) do
		updateContribution(player, zoneId, zoneData.mode, false)
	end
end

local function onZoneAdded(player, zoneId, zoneData)
	if not player or not zoneData then return end
	updateContribution(player, zoneId, zoneData.mode, false)
end

local function onZoneRemoved(player, zoneId, mode)
	if not player then return end
	updateContribution(player, zoneId, mode, true)
end

local function cleanupPlayer(player)
	playerTotals[player] = nil
	zoneContributions[player] = nil
end

function PowerBadgeTracker.Init()
	ZoneTrackerModule.zoneAddedEvent.Event:Connect(onZoneAdded)
	ZoneTrackerModule.zoneRemovedEvent.Event:Connect(onZoneRemoved)

	Players.PlayerAdded:Connect(function(player)
		task.defer(seedPlayer, player)
	end)
	Players.PlayerRemoving:Connect(cleanupPlayer)

	for _, plr in ipairs(Players:GetPlayers()) do
		task.defer(seedPlayer, plr)
	end
end

return PowerBadgeTracker
