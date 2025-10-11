local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerCommandManager = require(script.Parent.PlayerCommandManager)

local CreateZoneCommand = require(script.Parent.CreateZoneCom)
local BuildRoadCommand = require(script.Parent.BuildRoadCommand)
local BuildPipeCommand = require(script.Parent.BuildPipeCommand)
local PlaceBuildingCommand = require(script.Parent.PlaceBuildingCommand)
local DeleteZoneCommand = require(script.Parent.DeleteZoneCom)
local BuildZoneCommand = require(script.Parent.BuildZoneCommand)
local BuildPowerLineCommand = require(script.Parent.BuildPowerLineCommand)
local BuildMetroTunnelCommand = require(script.Parent.BuildMetroTunnelCommand)

local commandHandler = PlayerCommandManager.new()

local RemoteEvents = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents")
local ExecuteCommandEvent = RemoteEvents:WaitForChild("ExecuteCommand")
local UndoCommandEvent = RemoteEvents:WaitForChild("UndoCommand")
local RedoCommandEvent = RemoteEvents:WaitForChild("RedoCommand")

-- Configuration for debug
local DEBUG = false
local function debugPrint(...)
	if DEBUG then
		print("[CommandManagerHandler]", ...)
	end
end

debugPrint("Ready. Listening for Execute/Undo/Redo events.")

local function onExecuteCommand(player, commandType, ...)
	debugPrint("ExecuteCommand received from:", player.Name, "CommandType:", commandType)
	local manager = commandHandler:getManager(player)
	local command

	if commandType == "CreateZone" then
		local mode, gridList = ...
		command = CreateZoneCommand.new(player, mode, gridList)
	elseif commandType == "BuildRoad" then
		local startCoord, endCoord, mode = ...
		command = BuildRoadCommand.new(player, startCoord, endCoord, mode)
	elseif commandType == "BuildPipe" then
		local startCoord, endCoord, mode = ...
		command = BuildPipeCommand.new(player, startCoord, endCoord, mode)
	elseif commandType == "PlaceBuilding" then
		local gridPosition, buildingType = ...
		command = PlaceBuildingCommand.new(player, gridPosition, buildingType)
	elseif commandType == "DeleteZone" then
		local zoneId = ...
		command = DeleteZoneCommand.new(player, zoneId)
	elseif commandType == "BuildZone" then
		local startCoord, endCoord, mode, rotation = ...
		command = BuildZoneCommand.new(player, startCoord, endCoord, mode, rotation)
	elseif commandType == "BuildPowerLine" then
		local startCoord, endCoord, mode = ...
		command = BuildPowerLineCommand.new(player, startCoord, endCoord, mode)	
	elseif commandType == "BuildMetroTunnel" then
		local startCoord, endCoord, mode = ...
		command = BuildMetroTunnelCommand.new(player, startCoord, endCoord, mode)
	else
		warn("Unknown command type:", commandType)
		return
	end

	if command then
		debugPrint("Enqueuing command:", command.__className or "Unknown")
		local success, err = pcall(function()
			manager:enqueueCommand(command)
		end)
		if not success then
			warn("Failed to enqueue command:", err)
		end
	end
end

local function onUndoCommand(player)
	debugPrint("UndoCommand received from:", player.Name)
	local manager = commandHandler:getManager(player)
	local success, err = pcall(function()
		manager:undo()
	end)
	if not success then
		warn("Undo failed:", err)
	end
end

local function onRedoCommand(player)
	debugPrint("RedoCommand received from:", player.Name)
	local manager = commandHandler:getManager(player)
	local success, err = pcall(function()
		manager:redo()
	end)
	if not success then
		warn("Redo failed:", err)
	end
end

ExecuteCommandEvent.OnServerEvent:Connect(onExecuteCommand)
UndoCommandEvent.OnServerEvent:Connect(onUndoCommand)
RedoCommandEvent.OnServerEvent:Connect(onRedoCommand)

local function cleanupPlayerCommands(player)
	debugPrint("Cleaning up manager for player:", player.Name)
	commandHandler:removeManager(player)
end

Players.PlayerRemoving:Connect(cleanupPlayerCommands)
