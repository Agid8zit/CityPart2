local VERBOSE_LOG = false
local function log(...)
	if VERBOSE_LOG then print(...) end
end

log("[XP] Module loaded")

--// SERVICES --
local Players        = game:GetService("Players")
local S3             = game:GetService("ServerScriptService")
local RS             = game:GetService("ReplicatedStorage")

local DS             = S3:WaitForChild("DataStore")          -- Player‑side data table
local Build          = S3:WaitForChild("Build")
local Zones          = Build:WaitForChild("Zones")
local ZoneMgr        = Zones:WaitForChild("ZoneManager")
local ZoneTracker    = require(ZoneMgr:WaitForChild("ZoneTracker"))

local DistrictStatsModule = require(script.Parent:WaitForChild("DistrictStatsModule"))
local PlayerDataService = require(S3.Services.PlayerDataService)

local Events         = RS:WaitForChild("Events")
local BindableEvents = Events:WaitForChild("BindableEvents")
local ZoneCreated    = BindableEvents:WaitForChild("ZoneCreated")
local ZoneRemoved    = BindableEvents:WaitForChild("ZoneRemoved")
local XPChanged      = BindableEvents:WaitForChild("XPChanged")

local Balancing      = RS:WaitForChild("Balancing")
local Balance        = require(Balancing:WaitForChild("BalanceEconomy"))
local BuildingGhostManager   = require(RS.Scripts.BuildingManager:WaitForChild("BuildingGhostManager"))

local PlayerDataInterfaceService = require(game.ServerScriptService.Services.PlayerDataInterfaceService)

local UNDO_WINDOW = 30 

--// STATE --
local processedZones 	= {}       -- [userId] = set of zoneIds already awarded
local xpHistory 		= {}


local function awardXP(player, amount, zoneId)
	if type(amount) ~= "number" or amount <= 0 then return end
	
	if PlayerDataInterfaceService.HasGamepass(player, "x2 EXP") then
		amount *= 2
	end
	
	local SaveData = PlayerDataService.GetSaveFileData(player)
	if not SaveData then return end
	
	local newXP = SaveData.xp + amount
	PlayerDataService.ModifySaveData(player, "xp", newXP)

	log(("[XP] %s +%d → %d"):format(player.Name, amount, newXP))
	XPChanged:Fire(player, newXP)

	if zoneId then
		xpHistory[player.UserId] = xpHistory[player.UserId] or {}
		xpHistory[player.UserId][zoneId] = {
			amount    = amount,
			timestamp = os.time(),
		}
	end
end


--// INITIALISATION --

Players.PlayerAdded:Connect(function(player)

	processedZones[player.UserId] = {}
	xpHistory[player.UserId] = {}

	--print(("[JOIN] %s – Starting XP: %d"):format(player.Name, data.xp))
end)

Players.PlayerRemoving:Connect(function(player)

	processedZones[player.UserId] = nil
end)

--// ZONE‑CREATION LISTENER --
ZoneCreated.Event:Connect(function(player, zoneId)
	local uid = player.UserId
	if processedZones[uid][zoneId] then return end

	local zoneData = ZoneTracker.getZoneById(player, zoneId)
	if not zoneData then
		warn(("XP> Could not find zone %s for %s"):format(zoneId, player.Name))
		return
	end

	local zoneType    = zoneData.mode or zoneData.type or "Unknown"
	local gridList    = zoneData.gridList
	local gridCount   = (type(gridList) == "table") and #gridList or 0
	local baseXP    = Balance.ZoneXP[zoneType] or 0

	local totalReward
	if BuildingGhostManager.isGhostable(zoneType) then
		totalReward = baseXP
	else
		totalReward = baseXP * gridCount
	end

	log(("[XP] %d XP for %s (%s)"):format(totalReward, zoneType, zoneId))
	awardXP(player, totalReward, zoneId)

	processedZones[uid][zoneId] = true
end)

ZoneRemoved.Event:Connect(function(player, zoneId)
	local uid = player.UserId
	xpHistory[uid] = xpHistory[uid] or {}
	local rec = xpHistory[uid][zoneId]
	-- If we remember this zone's award and we're within the window, do an exact revert.
	if rec and (os.time() - (rec.timestamp or 0)) <= UNDO_WINDOW then
		local SaveData = PlayerDataService.GetSaveFileData(player)
		if SaveData then
			local newXP = math.max(0, (SaveData.xp or 0) - (rec.amount or 0))
			PlayerDataService.ModifySaveData(player, "xp", newXP)
			log(("[XP] %s AUTO-UNDO %d for %s → %d"):format(player.Name, rec.amount or 0, zoneId, newXP))
			XPChanged:Fire(player, newXP)
		end
		-- Allow re-award if they build again.
		xpHistory[uid][zoneId] = nil
		processedZones[uid] = processedZones[uid] or {}
		processedZones[uid][zoneId] = nil
	else
		-- Outside window or unknown: still clear processed so rebuild can pay again.
		processedZones[uid] = processedZones[uid] or {}
		processedZones[uid][zoneId] = nil
	end
end)

--// PUBLIC API --
local XP = {}

function XP.getXP(player)
	local SaveData = PlayerDataService.GetSaveFileData(player)
	if not SaveData then return 0 end
	
	log(("[XP] %s: %d"):format(player.Name, SaveData.xp))
	return SaveData.xp
end

function XP.setXP(player, amount)
	if type(amount) ~= "number" then return end
	
	local SaveData = PlayerDataService.GetSaveFileData(player)
	if not SaveData then return 0 end
	
	PlayerDataService.ModifySaveData(player, "xp", amount)
	
	log(("[XP] %s set to %d"):format(player.Name, amount))
	XPChanged:Fire(player, amount)
end

function XP.addXP(player, amount)
	awardXP(player, amount)
end

function XP.removeXP(player, amount, zoneId)
	if type(amount) ~= "number" then return end
	local uid = player.UserId
	local SaveData = PlayerDataService.GetSaveFileData(player)

	-- Attempt zone-based revert
	if zoneId and xpHistory[uid] and xpHistory[uid][zoneId] then
		local rec = xpHistory[uid][zoneId]
		if rec.amount == amount and (os.time() - rec.timestamp) <= UNDO_WINDOW then
			-- valid revert
			local newXP = math.max(0, SaveData.xp - amount)
			PlayerDataService.ModifySaveData(player, "xp", newXP)
			log(("[XP] %s UNDO %d from zone %s → %d"):format(player.Name, amount, zoneId, newXP))
			XPChanged:Fire(player, newXP)

			-- clear history and allow zone re-award if they build again
			xpHistory[uid][zoneId] = nil
			processedZones[uid][zoneId] = nil
			return
		else
			warn(("[XP] Cannot undo XP for zone %s: either amount mismatch or undo window expired."):format(zoneId))
		end
	end

	-- Generic removal (or invalid zone revert): XP drops but level will not regress
	local newXP = math.max(0, SaveData.xp - amount)
	PlayerDataService.ModifySaveData(player, "xp", newXP)

	log(("[XP] %s –%d → %d (generic removal)"):format(player.Name, amount, newXP))
	XPChanged:Fire(player, newXP)
end

XP.XPChanged = XPChanged

function XP.getZoneAwardTimestamp(player, zoneId)
	local uid = player.UserId
	local rec = xpHistory[uid] and xpHistory[uid][zoneId]
	return rec and rec.timestamp or nil
end

return XP
