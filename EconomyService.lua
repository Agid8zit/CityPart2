--// ServerScriptService/Build/Zones/ZoneManager/EconomyService.lua

local S3 = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Balancing / Ghosts
local Balancing = ReplicatedStorage:WaitForChild("Balancing")
local Balance = require(Balancing:WaitForChild("BalanceEconomy"))
local Scripts = ReplicatedStorage:WaitForChild("Scripts")
local BldMgr = Scripts:WaitForChild("BuildingManager")
local BuildingGhostManager = require(BldMgr:WaitForChild("BuildingGhostManager"))

-- Events
local Events = ReplicatedStorage:WaitForChild("Events")
local BindableEvents = Events:WaitForChild("BindableEvents")
local StatsChanged = BindableEvents:WaitForChild("StatsChanged")

-- RemoteEvents (CLIENT NOTIFICATION)
local RemoteEvents = Events:WaitForChild("RemoteEvents")
local RE_PlayerDataChanged_Money = RemoteEvents:WaitForChild("PlayerDataChanged_Money")

-- Data
local PlayerDataService = require(S3.Services.PlayerDataService)
local PlayerDataInterfaceService = require(S3.Services.PlayerDataInterfaceService) -- <-- centralize mutations

local EconomyService = {}
EconomyService.__index = EconomyService

-- optional: tiny per-player mutex to avoid concurrent stale adds
local _locks = setmetatable({}, { __mode = "k" })

local function withLock(player, fn)
	-- naive mutex; good enough for single-server write coalescing
	while _locks[player] do task.wait() end
	_locks[player] = true
	local ok, err = pcall(fn)
	_locks[player] = nil
	if not ok then error(err) end
end

-- ========= Balance Queries =========

function EconomyService.getBalance(player)
	local SaveData = PlayerDataService.GetSaveFileData(player)
	if not SaveData or not SaveData.economy then return 0 end
	return SaveData.economy.money or 0
end

-- ========= Balance Mutations (server -> client notify) =========
-- NOTE: we route through PlayerDataInterfaceService so all money mutations fire the proper RemoteEvent.

function EconomyService.setBalance(player, amount:number)
	withLock(player, function()
		PlayerDataInterfaceService.SetCoinsInSaveData(player, amount) -- unified path "economy/money"
		-- StatsChanged Bindable remains for any server listeners you already wired
		StatsChanged:Fire(player)
	end)
	return EconomyService.getBalance(player)
end

function EconomyService.adjustBalance(player, delta:number)
	withLock(player, function()
		PlayerDataInterfaceService.AdjustCoinsInSaveData(player, delta)
		StatsChanged:Fire(player)
	end)
	return EconomyService.getBalance(player)
end

function EconomyService.canAfford(player, totalCost:number)
	return EconomyService.getBalance(player) >= (totalCost or 0)
end

function EconomyService.chargePlayer(player, totalCost:number)
	if totalCost and totalCost > 0 and EconomyService.canAfford(player, totalCost) then
		EconomyService.adjustBalance(player, -totalCost)
		-- UI is notified via PlayerDataChanged_Money inside the InterfaceService.
		return true
	end
	return false
end

-- ========= Cost Calculations =========

function EconomyService.isRobuxExclusiveBuilding(mode:string)
	return Balance.costPerGrid[mode] == "ROBUX"
end

function EconomyService.getCost(mode:string, numGrids:number)
	local base = Balance.costPerGrid[mode] or 0

	-- If the entry is the sentinel "ROBUX", NEVER return it as a number.
	-- Callers must gate on isRobuxExclusiveBuilding first.
	if base == "ROBUX" then
		return "ROBUX"
	end

	-- Ghostables: fixed price per footprint (ignore numGrids)
	if BuildingGhostManager.isGhostable(mode) then
		return base
	end

	-- Normal zones/utilities: linear scale by selected cell count
	return base * (numGrids or 1)
end

return EconomyService
