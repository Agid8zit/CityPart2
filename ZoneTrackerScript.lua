--[[
Script Order: 7
Script Name: ZoneTrackerScript.lua
Description: Script that listens for zone creation events and updates the ZoneTracker.
Dependencies: ZoneTracker.lua
Dependents: None
]]--

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Events = ReplicatedStorage:WaitForChild("Events")
local BindableEvents = Events:WaitForChild("BindableEvents")

local ZoneTrackerModule = require(script.Parent:WaitForChild("ZoneTracker"))

-- Listen for Events
local zoneCreatedEvent = BindableEvents:WaitForChild("ZoneCreated")
zoneCreatedEvent.Event:Connect(function(player, zoneId, mode, gridList)
	-- Before adding:
	local existingZone = ZoneTrackerModule.getZoneById(player, zoneId)
	if existingZone then
		-- Zone already exists, so skip adding
		return
	end

	-- If it doesn't exist, proceed to add it
	local success = ZoneTrackerModule.addZone(player, zoneId, mode, gridList)
	if not success then
		warn("Failed to add Zone", zoneId, "for player", player.Name)
	end
end)

-- This will be our primary controller for Co-Op probably
-- Need to add requirements for like Water, Power, etc