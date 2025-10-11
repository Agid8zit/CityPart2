
-- ServerScriptService/ZoneSelectionHandler.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local Events            = ReplicatedStorage:WaitForChild("Events")
local selectZoneEvent   = Events.RemoteEvents:WaitForChild("SelectZoneType")
local displayGridEvent  = Events.RemoteEvents:WaitForChild("DisplayGrid")
local notifyLockedEvent = Events.RemoteEvents:WaitForChild("NotifyLocked")

local ServerScriptService = game:GetService("ServerScriptService")
local Progression = require(ServerScriptService.Build.Districts.Stats.Progression)

selectZoneEvent.OnServerEvent:Connect(function(player, zoneType)
	assert(player and player:IsA("Player"), "bad player")
	
	if not Progression.playerHasUnlock(player, zoneType) then
		local requiredLevel = Progression.getRequiredLevel(zoneType)
		-- Tell the client it’s locked and at which level it unlocks
		notifyLockedEvent:FireClient(player, zoneType, requiredLevel)
		return
	end

	----------------------------------------------------------------
	-- All good – let the client draw the placement grid
	----------------------------------------------------------------
	displayGridEvent:FireClient(player, zoneType)
end)