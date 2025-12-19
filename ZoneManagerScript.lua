--[[
Script Order: 6
Script Name: ZoneManagerScript.lua
Description: Script that connects RemoteEvents to ZoneManager handlers.
Dependencies: ZoneManager.lua, ZoneRequirementsCheck.lua, ZoneDisplay.lua, ZoneTracker.lua, ZoneValidation.lua
Dependents: None
]]--

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Events = ReplicatedStorage:WaitForChild("Events")
local RemoteEvents = Events:WaitForChild("RemoteEvents")
local BindableEvents = Events:WaitForChild("BindableEvents")
local S3 = game:GetService("ServerScriptService")

local ZoneManager = require(script.Parent:WaitForChild("ZoneManager"))
local ZoneDisplayModule = require(script.Parent:WaitForChild("ZoneDisplay"))
local ZoneTrackerModule = require(script.Parent:WaitForChild("ZoneTracker"))
local ZoneValidationModule = require(script.Parent:WaitForChild("ZoneValidation"))
local ZoneRequirementsCheck = require(script.Parent:WaitForChild("ZoneRequirementsCheck"))
local CityInteractions = require(script.Parent:WaitForChild("CityInteraction"))
local Advisor = require(S3.Twitter.Advisor)

local VERBOSE_LOG = false
local function log(...)
	if VERBOSE_LOG then print(...) end
end

log("Server: CityInteractions Module required successfully!")

-- Connect RemoteEvents to ZoneManager handlers
--local selectZoneEvent = RemoteEvents:WaitForChild("SelectZoneType")
local gridSelectionEvent = RemoteEvents:WaitForChild("GridSelection")
local buildRoadEvent = RemoteEvents:WaitForChild("BuildRoad")
local buildPipeEvent = RemoteEvents:WaitForChild("BuildPipe")
local buildPowerLineEvent = RemoteEvents:WaitForChild("BuildPowerLine")

local placeWaterTowerEvent = RemoteEvents:WaitForChild("PlaceWaterTower")
--local togglePipesEvent = RemoteEvents:WaitForChild("TogglePipesVisibility")
--[[
selectZoneEvent.OnServerEvent:Connect(function(player, zoneType)
	ZoneManager.onSelectZoneType(player, zoneType)
end)
log("Server: 'SelectZoneType' RemoteEvent connected to ZoneManager.onSelectZoneType")
]]
gridSelectionEvent.OnServerEvent:Connect(function(player, selectedCoords)
	ZoneManager.onGridSelection(player, selectedCoords)
end)
log("Server: 'GridSelection' RemoteEvent connected to ZoneManager.onGridSelection")

-- Server-side event handler for building roads
buildRoadEvent.OnServerEvent:Connect(function(player, startCoord, endCoord, mode)
	-- Validate the coordinates
	if not (startCoord and startCoord.x and startCoord.z) then
		warn("Invalid startCoord received from", player.Name)
		return
	end
	if not (endCoord and endCoord.x and endCoord.z) then
		warn("Invalid endCoord received from", player.Name)
		return
	end

	-- Handle road building logic
	log("Received buildRoadEvent from", player.Name)
	log("Start Coord:", startCoord.x, startCoord.z)
	log("End Coord:", endCoord.x, endCoord.z)
	log("Mode:", mode)

	-- Call ZoneManager.buildRoad
	local success, message = ZoneManager.buildRoad(player, startCoord, endCoord, mode)
	if success then
		log("Road built successfully.")
	else
		warn("Failed to build road:", message)
	end
end)
log("Server: 'BuildRoad' RemoteEvent connected to ZoneManager.buildRoad")

-- Server-side event handler for building pipes
buildPipeEvent.OnServerEvent:Connect(function(player, startCoord, endCoord, mode)
	-- Validate the coordinates
	if not (startCoord and startCoord.x and startCoord.z) then
		warn("Invalid startCoord received from", player.Name)
		return
	end
	if not (endCoord and endCoord.x and endCoord.z) then
		warn("Invalid endCoord received from", player.Name)
		return
	end

	-- Handle pipe building logic
	log("Received buildPipeEvent from", player.Name)
	log("Start Coord:", startCoord.x, startCoord.z)
	log("End Coord:", endCoord.x, endCoord.z)
	log("Mode:", mode)

	-- Call ZoneManager.buildPipe
	local success, message = ZoneManager.buildPipe(player, startCoord, endCoord, mode)
	if success then
		log("Pipe built successfully.")
	else
		warn("Failed to build pipe:", message)
	end
end)
log("Server: 'BuildPipe' RemoteEvent connected to ZoneManager.buildPipe")

-- Handle PlaceWaterTower event
placeWaterTowerEvent.OnServerEvent:Connect(function(player, gridPosition)
	ZoneManager.onPlaceWaterTower(player, gridPosition)
end)
--print("Server: 'PlaceWaterTower' RemoteEvent connected to ZoneManager.onPlaceWaterTower")

--[[ Handle TogglePipesVisibility event
togglePipesEvent.OnServerEvent:Connect(function(player, visible)
	-- Relay the event to the specific client
	togglePipesEvent:FireClient(player, visible)
end)
log("Server: 'TogglePipesVisibility' RemoteEvent connected.")
]]

buildPowerLineEvent.OnServerEvent:Connect(function(player, startCoord, endCoord, mode)
	-- Validate the coordinates
	if not (startCoord and startCoord.x and startCoord.z) then
		warn("Invalid startCoord received from", player.Name)
		return
	end
	if not (endCoord and endCoord.x and endCoord.z) then
		warn("Invalid endCoord received from", player.Name)
		return
	end

	-- Logging
	log("Received buildPowerLineEvent from", player.Name)
	log("Start Coord:", startCoord.x, startCoord.z)
	log("End Coord:",   endCoord.x,   endCoord.z)
	log("Mode:", mode)

	-- Actual build call
	local success, messageOrId = ZoneManager.buildPowerLine(player, startCoord, endCoord, mode)
	if success then
		log("PowerLines built successfully. ZoneId =", messageOrId)
	else
		warn("Failed to build power line:", messageOrId)
	end
end)

--print("Server: 'BuildPowerLine' RemoteEvent connected to ZoneManager.buildPowerLine")

-- Connect BindableEvents to ZoneDisplayModule only
local zoneCreatedEvent = BindableEvents:WaitForChild("ZoneCreated")
zoneCreatedEvent.Event:Connect(function(player, zoneId, mode, gridList, rotationYDeg)
log("ZoneManagerScript: 'ZoneCreated' event fired for zoneId:", zoneId)
	-- Notify ZoneDisplayModule to display the zone
	--ZoneDisplayModule.displayZone(player, zoneId, mode, gridList, rotationYDeg or 0 )
end)

--print("Server: BindableEvent 'ZoneCreated' connected to ZoneDisplayModule only")

-- Optional: Confirm ZoneRequirementsCheck Initialization
--print("Server: 'ZoneRequirementsCheck' Module initialized and connected to events.")
