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
local LayerManager = require(S3.Build.LayerManager)

local Transport = Bld:WaitForChild("Transport")
local Roads = Transport:WaitForChild("Roads")
local RoadsCore = Roads:WaitForChild("CoreConcepts")
local Pathing = RoadsCore:WaitForChild("Pathing")

local PathingModule = require(Pathing:WaitForChild("PathingModule"))
local CarMovement = require(Pathing:WaitForChild("CarMovement"))

local Workspace = game:GetService("Workspace")

local alreadyCleaned = {}

local VERBOSE_LOG = false
local function log(...)
	if VERBOSE_LOG then print(...) end
end

function PlayerCleanupService.cleanupPlayer(player)
	if alreadyCleaned[player.UserId] then return end
	alreadyCleaned[player.UserId] = true
	local userId = player.UserId
	local plotName = "Plot_" .. userId
	log("[Cleanup] Cleaning up player:", player.Name)

	-- Clear ZoneManager state
	ZoneManager.playerZoneCounters[userId] = nil

	-- Clear ZoneTracker state
	ZoneTracker.clearPlayerData(player)

	-- Clear RequirementsCheck cache
	ZoneRequirementsCheck.clearPlayerData(player)

	-- Clear any archived layer data for this player (prevents cross-session restores)
	LayerManager.clearPlayer(player)

	-- Road-specific cleanup
	local roadNetworks = PathingModule.getRoadNetworks()
	local ownerKey = tostring(userId)
	for key, network in pairs(roadNetworks) do
		local zoneId = network and network.id or key
		local owned = network and (
			(network.owner and network.owner == ownerKey)
			or (type(key) == "string" and string.find(key, "^" .. ownerKey .. "::"))
			or (zoneId and string.find(tostring(zoneId), ownerKey))
		)
		if owned then
			-- Unregister road
			PathingModule.unregisterRoad(zoneId, userId)

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

	log("[Cleanup] Finished cleaning player:", player.Name)
end

do
	-- Guarantee the event exists (SaveManager creates it if missing)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local PlayerSavedEvent  = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents"):WaitForChild("PlayerSaved")

	-- Run clean-up only when SaveManager fires PlayerSaved
	PlayerSavedEvent.Event:Connect(PlayerCleanupService.cleanupPlayer)
end

return PlayerCleanupService
