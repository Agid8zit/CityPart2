local PlayerCleanupService = {}
PlayerCleanupService.__index = PlayerCleanupService

-- Dependencies
local S3 = game:GetService("ServerScriptService")
local Bld = S3:WaitForChild("Build")
local Zones = Bld:WaitForChild("Zones")
local ZoneMgr = Zones:WaitForChild("ZoneManager")
local ZoneManager = require(ZoneMgr:WaitForChild("ZoneManager"))
local ZoneTracker = require(ZoneMgr:WaitForChild("ZoneTracker"))
local ZoneRequirementsCheck = require(ZoneMgr:WaitForChild("ZoneRequirementsCheck"))
local EconomyService = require(ZoneMgr:WaitForChild("EconomyService"))

local Transport = Bld:WaitForChild("Transport")
local Roads = Transport:WaitForChild("Roads")
local RoadsCore = Roads:WaitForChild("CoreConcepts")
local Pathing = RoadsCore:WaitForChild("Pathing")

local PathingModule = require(Pathing:WaitForChild("PathingModule"))
local CarMovement = require(Pathing:WaitForChild("CarMovement"))

local Workspace = game:GetService("Workspace")

local alreadyCleaned = {}

function PlayerCleanupService.cleanupPlayer(player)
	if alreadyCleaned[player.UserId] then return end
	alreadyCleaned[player.UserId] = true
	local userId = player.UserId
	local plotName = "Plot_" .. userId
	print("[Cleanup] Cleaning up player:", player.Name)

	-- Clear ZoneManager state
	ZoneManager.playerZoneCounters[userId] = nil

	-- Clear ZoneTracker state
	ZoneTracker.clearPlayerData(player)

	-- Clear RequirementsCheck cache
	ZoneRequirementsCheck.clearPlayerData(player)

	-- Road-specific cleanup
	local roadNetworks = PathingModule.getRoadNetworks()
	for zoneId, network in pairs(roadNetworks) do
		if network and network.id and string.find(network.id, tostring(userId)) then
			-- Unregister road
			PathingModule.unregisterRoad(zoneId)

			-- Stop all car movement for this zone
			CarMovement.stopMovementsForZone(zoneId)

			-- Destroy any remaining car models
			for _, obj in ipairs(Workspace:GetDescendants()) do
				if obj:IsA("Model") and obj.Name:match("^Car_" .. zoneId) then
					obj:Destroy()
				end
			end
		end
	end

	print("[Cleanup] Finished cleaning player:", player.Name)
end

do
	-- Guarantee the event exists (SaveManager creates it if missing)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local PlayerSavedEvent  = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents"):WaitForChild("PlayerSaved")

	-- Run clean-up only when SaveManager fires PlayerSaved
	PlayerSavedEvent.Event:Connect(PlayerCleanupService.cleanupPlayer)
end

return PlayerCleanupService