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

----------------------------------------------------------------
-- Cross-Debounce / Streak Logic (ADDED)
----------------------------------------------------------------
-- Tuning knobs (you can tweak these):
local RESET_WINDOW_SEC = 1.2      -- gap that breaks a streak
local SAME_AFTER4_COOLDOWN = 0.5  -- starting at the 5th consecutive same action
local MIN_OPP_LOCK = 0.20         -- minimum lock on the opposite action (even on the 1st in a streak)
local OPP_LOCK_ALPHA = 0.75       -- scales logarithmic growth of opposite lock

-- Per-player state
type CoolUntil = { undo: number, redo: number }
type PlayerState = {
	lastAction: "undo" | "redo" | nil,
	lastTime: number?,
	undoStreak: number,
	redoStreak: number,
	coolUntil: CoolUntil,   -- own local cooldown for each action
	oppLockUntil: CoolUntil -- cross-lock imposed by the other action's streak
}
local stateByUser: { [number]: PlayerState } = {}

local function now()
	return time()
end

local function getState(userId: number): PlayerState
	local s = stateByUser[userId]
	if s then return s end
	s = {
		lastAction = nil,
		lastTime = nil,
		undoStreak = 0,
		redoStreak = 0,
		coolUntil = { undo = 0, redo = 0 },
		oppLockUntil = { undo = 0, redo = 0 },
	}
	stateByUser[userId] = s
	return s
end

local function computeOppLock(streak: number): number
	-- Logarithmic: lock = MIN + ALPHA * ln(1 + streak)
	return MIN_OPP_LOCK + OPP_LOCK_ALPHA * math.log(1 + math.max(streak, 0))
end

local function canDoAction(s: PlayerState, action: "undo" | "redo"): boolean
	local t = now()
	-- Block if own local cooldown is active
	if t < s.coolUntil[action] then
		if DEBUG then debugPrint(("blocked own cooldown %s; tLeft=%.2f"):format(action, s.coolUntil[action] - t)) end
		return false
	end
	-- Block if opposite's lockout on this action is active
	if t < s.oppLockUntil[action] then
		if DEBUG then debugPrint(("blocked opposite lock %s; tLeft=%.2f"):format(action, s.oppLockUntil[action] - t)) end
		return false
	end
	return true
end

local function recordActionAndApplyLocks(s: PlayerState, action: "undo" | "redo")
	local t = now()

	-- Maintain streaks
	if s.lastAction == action and s.lastTime and (t - s.lastTime) <= RESET_WINDOW_SEC then
		if action == "undo" then
			s.undoStreak += 1
		else
			s.redoStreak += 1
		end
	else
		-- switching or gap: reset appropriate streak and set current to 1
		if action == "undo" then
			s.undoStreak = 1
			s.redoStreak = 0
		else
			s.redoStreak = 1
			s.undoStreak = 0
		end
	end

	-- Own local cooldown starting with the 5th consecutive same action
	if action == "undo" then
		if s.undoStreak >= 5 then
			s.coolUntil.undo = math.max(s.coolUntil.undo, t + SAME_AFTER4_COOLDOWN)
		end
	else -- redo
		if s.redoStreak >= 5 then
			s.coolUntil.redo = math.max(s.coolUntil.redo, t + SAME_AFTER4_COOLDOWN)
		end
	end

	-- Cross-debounce: pressing one action locks the opposite action
	local streak = (action == "undo") and s.undoStreak or s.redoStreak
	local opp = (action == "undo") and "redo" or "undo"
	local oppLock = computeOppLock(streak)
	s.oppLockUntil[opp] = math.max(s.oppLockUntil[opp], t + oppLock)

	if DEBUG then
		local streakUndo, streakRedo = s.undoStreak, s.redoStreak
		debugPrint(
			("action=%s; streakU=%d streakR=%d; set oppLock[%s]=+%.2fs (until %.2f)"):format(
				action, streakUndo, streakRedo, opp, oppLock, s.oppLockUntil[opp]
			)
		)
	end

	-- Update last action/time
	s.lastAction = action
	s.lastTime = t
end
----------------------------------------------------------------

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
	local s = getState(player.UserId)
	if not canDoAction(s, "undo") then
		-- Optional: fire a tiny UI toast to client
		-- RemoteEvents:WaitForChild("NotifyLocked"):FireClient(player, "Undo throttled")
		return
	end

	debugPrint("UndoCommand accepted from:", player.Name)
	recordActionAndApplyLocks(s, "undo")

	local manager = commandHandler:getManager(player)
	local ok, err = pcall(function()
		manager:undo()
	end)
	if not ok then
		warn("Undo failed:", err)
	end
end

local function onRedoCommand(player)
	local s = getState(player.UserId)
	if not canDoAction(s, "redo") then
		-- Optional: fire a tiny UI toast to client
		-- RemoteEvents:WaitForChild("NotifyLocked"):FireClient(player, "Redo throttled")
		return
	end

	debugPrint("RedoCommand accepted from:", player.Name)
	recordActionAndApplyLocks(s, "redo")

	local manager = commandHandler:getManager(player)
	local ok, err = pcall(function()
		manager:redo()
	end)
	if not ok then
		warn("Redo failed:", err)
	end
end

ExecuteCommandEvent.OnServerEvent:Connect(onExecuteCommand)
UndoCommandEvent.OnServerEvent:Connect(onUndoCommand)
RedoCommandEvent.OnServerEvent:Connect(onRedoCommand)

local function cleanupPlayerCommands(player)
	debugPrint("Cleaning up manager for player:", player.Name)
	commandHandler:removeManager(player)

	-- Clear cross-debounce state
	stateByUser[player.UserId] = nil
end

Players.PlayerRemoving:Connect(cleanupPlayerCommands)
