print("[Income] Module loaded")

local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local S3             = game:GetService("ServerScriptService")
local DS             = S3:WaitForChild("DataStore")
local RS             = game:GetService("ReplicatedStorage")

local Build          = S3:WaitForChild("Build")
local Zones          = Build:WaitForChild("Zones")
local ZoneMgr        = Zones:WaitForChild("ZoneManager")
local ZoneTracker    = require(ZoneMgr:WaitForChild("ZoneTracker"))
local CityInteractions = require(ZoneMgr:WaitForChild("CityInteraction"))
local EconomyService = require(ZoneMgr:WaitForChild("EconomyService"))

local DistrictStatsModule = require(script.Parent:WaitForChild("DistrictStatsModule"))
local PlayerDataService = require(S3.Services.PlayerDataService)
local ZoneRequirementsChecker = require(ZoneMgr:WaitForChild("ZoneRequirementsCheck"))

local Events          = RS:WaitForChild("Events")
local BindableEvents  = Events:WaitForChild("BindableEvents")
local StatsChanged    = BindableEvents:WaitForChild("StatsChanged")
local Balancing 	  = RS:WaitForChild("Balancing")

local Balance = require(Balancing:WaitForChild("BalanceEconomy"))
local PlayerDataInterfaceService = require(game.ServerScriptService.Services.PlayerDataInterfaceService)

-- Configuration
local TICK_INTERVAL = 5 -- seconds between income ticks
local lastTick      = 0


-- State
local playerIncomeCache = {} -- [userId] = incomePerTick

-- Initialisation

Players.PlayerRemoving:Connect(function(player)
	playerIncomeCache[player.UserId] = nil
end)

local function getWealthAtGrid(player, zoneId, gx, gz)
	local plot = workspace.PlayerPlots:FindFirstChild("Plot_" .. player.UserId)
	if not plot then return nil end
	local populated = plot:FindFirstChild("Buildings")
		and plot.Buildings:FindFirstChild("Populated")
	if not populated then return nil end

	for _, folderName in ipairs({ zoneId, "Utilities" }) do
		local folder = populated:FindFirstChild(folderName)
		if folder then
			for _, inst in ipairs(folder:GetChildren()) do
				if inst:GetAttribute("ZoneId") == zoneId
					and inst:GetAttribute("GridX")  == gx
					and inst:GetAttribute("GridZ")  == gz then
					return inst:GetAttribute("WealthState") or "Poor"
				end
			end
		end
	end

	return nil
end

local function tileHasAllRequirements(player, zoneId, gx, gz)
	-- true only when Road *and* Water *and* Power are individually true
	return ZoneTracker.getTileRequirement(player, zoneId, gx, gz, "Road")  == true
		and ZoneTracker.getTileRequirement(player, zoneId, gx, gz, "Water") == true
		and ZoneTracker.getTileRequirement(player, zoneId, gx, gz, "Power") == true
end

local function calculateZoneIncome(player, zoneData)
	local total = 0

	for _, coord in ipairs(zoneData.gridList) do
		if tileHasAllRequirements(player, zoneData.zoneId, coord.x, coord.z) then
			local state = ZoneTracker.getGridWealth(player, zoneData.zoneId, coord.x, coord.z) or "Poor"
			local conf  = Balance.StatConfig[zoneData.mode][state]
			local base  = (conf and conf.income) or 0

			local mulNeg = CityInteractions.getTileIncomePollutionMultiplier(player, zoneData.zoneId, coord.x, coord.z)
			local mulPos = CityInteractions.getTileIncomePositiveMultiplier(player, zoneData.zoneId, coord.x, coord.z, zoneData.mode)
			local tileIncome = math.floor(base * mulNeg * mulPos + 0.5)

			total += tileIncome
		end
	end

	if PlayerDataInterfaceService.HasGamepass(player, "x2 Money") then
		total = total * 2
	end

	return total
end

	-- Income calculation
local function updateIncome()
	for _, player in ipairs(Players:GetPlayers()) do
		local SaveData = PlayerDataService.GetSaveFileData(player)
		if not SaveData then continue end

		-- 1) Base income: sum tile incomes with infra flags
		local total = 0
		local statsByZone = DistrictStatsModule.getStatsForPlayer(player.UserId)
		for zoneId, _ in pairs(statsByZone) do
			local zone = ZoneTracker.getZoneById(player, zoneId)
			if zone then
				total += calculateZoneIncome(player, zone)
			end
		end

		-- 2) Capacity coverage
		local totalsReq  = DistrictStatsModule.getTotalsForPlayer(player)
		local produced   = ZoneRequirementsChecker.getEffectiveProduction(player)
			or DistrictStatsModule.getUtilityProduction(player)

		local coverW = (totalsReq.water  > 0) and math.min(1, (produced.water or 0) / totalsReq.water)  or 1
		local coverP = (totalsReq.power  > 0) and math.min(1, (produced.power or 0) / totalsReq.power)  or 1
		local coverage = math.min(coverW, coverP)

		-- 3) Global rate scaling (optional)
		local rate = Balance.IncomeRate and Balance.IncomeRate.TICK_INCOME or 1
		local pay  = math.floor(total * coverage * rate + 0.5)

		-- cache per-tick
		playerIncomeCache[player.UserId] = pay

		-- 4) Authoritative mutation (centralized path)
		EconomyService.adjustBalance(player, pay)

		--5) Tell the central UI module to push a FULL, consistent payload
		StatsChanged:Fire(player)
	end
end


RunService.Heartbeat:Connect(function(dt)
	lastTick += dt
	if lastTick >= TICK_INTERVAL then
		updateIncome()
		lastTick = 0
	end
end)


-- Public API
local Income = {}

function Income.getBalance(player)
	return EconomyService.getBalance(player)
end

function Income.getIncomePerSecond(player)
	local incomePerTick = playerIncomeCache[player.UserId] or 0
	local perSecond     = incomePerTick / TICK_INTERVAL
	print(("[INCOME/s] %s: %d"):format(player.Name, perSecond))
	return perSecond
end

function Income.setBalance(player, amount)
	EconomyService.setBalance(player, amount)
	print(("[SET] %s balance to %d"):format(player.Name, amount))
end

function Income.addMoney(player, amount)
	EconomyService.adjustBalance(player, amount)
	print(("[ADD] %s: +%d → %d"):format(
		player.Name, amount, EconomyService.getBalance(player)
		))
end

function Income.removeMoney(player, amount)
	EconomyService.adjustBalance(player, -amount)
	print(("[REMOVE] %s: -%d → %d"):format(
		player.Name, amount, EconomyService.getBalance(player)
		))
end

return Income