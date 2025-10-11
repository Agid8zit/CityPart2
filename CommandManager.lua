-- CommandManager.lua  (replace the whole file with this)

local CommandManager = {}
CommandManager.__index = CommandManager

-- Debug toggle
local DEBUG = false
local function debugPrint(...)
	if DEBUG then
		print("[CommandManager]", ...)
	end
end

------------------------------------------------------------------------
-- Constructor
------------------------------------------------------------------------
function CommandManager.new()
	local self = setmetatable({}, CommandManager)
	self.undoStack     = {}
	self.redoStack     = {}
	self.commandQueue  = {}
	self.isProcessing  = false
	debugPrint("Created new CommandManager instance.")
	return self
end

------------------------------------------------------------------------
-- Enqueue / immediate execution
------------------------------------------------------------------------
function CommandManager:enqueueCommand(command)
	local MAX_QUEUE_SIZE = 5
	if #self.commandQueue >= MAX_QUEUE_SIZE then
		warn("Command queue exceeded maximum size. Command not enqueued.")
		return
	end

	debugPrint("Enqueuing command of type:", command.__className or "Unknown")
	if command.__className == "DeleteZoneCommand" then
		for i = #self.undoStack, 1, -1 do
			local c = self.undoStack[i]
			if c.containsZone and c:containsZone(command.zoneId) then
				table.remove(self.undoStack, i)
			end
		end
	end
	--------------------------------------------------------------------
	-- FAST-PATH: command wants to run immediately (skipQueue = true)
	--------------------------------------------------------------------
	if command.skipQueue then
		-- *** PUSH FIRST so Undo is available during long execution ***
		if command.__className ~= "UndoCommand" and command.__className ~= "RedoCommand" then
			table.insert(self.undoStack, command)
			command._pushedToStack = true
			self.redoStack = {}
			debugPrint("Pushed to undoStack BEFORE execute (skipQueue).")
		end

		local success, err = pcall(function()
			command:execute()
		end)

		if not success then
			-- Roll back the premature push
			if command._pushedToStack then
				table.remove(self.undoStack) -- remove last
				command._pushedToStack = nil
			end
			warn("Immediate command execution failed:", err)
		end
		return
	end

	--------------------------------------------------------------------
	-- Normal queued command
	--------------------------------------------------------------------
	table.insert(self.commandQueue, command)
	self:processQueue()
end

------------------------------------------------------------------------
-- Queue processor

function CommandManager:processQueue()
	if self.isProcessing then return end
	self.isProcessing = true
	debugPrint("Starting to process command queue...")

	coroutine.wrap(function()
		while #self.commandQueue > 0 do
			local command = table.remove(self.commandQueue, 1)
			debugPrint("Executing command from queue:", command.__className or "Unknown")

			local success, err = pcall(function()
				command:execute()
			end)

			if success then
				if command.__className ~= "UndoCommand" and command.__className ~= "RedoCommand" then
					if not command._pushedToStack then
						table.insert(self.undoStack, command)
						command._pushedToStack = true
						self.redoStack = {}
					end
				end
			else
				warn("Command execution failed:", err)
			end

			task.wait() -- yield
		end
		self.isProcessing = false
		debugPrint("Finished processing queue.")
	end)()
end

------------------------------------------------------------------------
-- Undo / Redo logic (unchanged)
------------------------------------------------------------------------
function CommandManager:undo()
	debugPrint("Undo requested. isProcessing:", self.isProcessing, "UndoStack size:", #self.undoStack)
	if self.isProcessing then
		table.insert(self.commandQueue, (require(script.Parent.CommandManager)).UndoCommand.new(self))
		self:processQueue()
	else
		local command = table.remove(self.undoStack)
		if command then
			local success, err = pcall(function()
				command:undo()
			end)
			if success then
				table.insert(self.redoStack, command)
			else
				warn("Undo failed:", err)
			end
		end
	end
end

function CommandManager:redo()
	debugPrint("Redo requested. isProcessing:", self.isProcessing, "RedoStack size:", #self.redoStack)
	if self.isProcessing then
		table.insert(self.commandQueue, (require(script.Parent.CommandManager)).RedoCommand.new(self))
		self:processQueue()
	else
		local command = table.remove(self.redoStack)
		if command then
			local success, err = pcall(function()
				command:execute()
			end)
			if success then
				table.insert(self.undoStack, command)
			else
				warn("Redo failed:", err)
			end
		end
	end
end

------------------------------------------------------------------------
-- Nested Undo / Redo command classes (unchanged)
------------------------------------------------------------------------
local UndoCommand = {}
UndoCommand.__index = UndoCommand
UndoCommand.__className = "UndoCommand"
setmetatable(UndoCommand, {__index = require(script.Parent.Command)})

function UndoCommand.new(manager)
	return setmetatable({manager = manager}, UndoCommand)
end
function UndoCommand:execute()
	local cmd = table.remove(self.manager.undoStack)
	if cmd then
		local ok, err = pcall(function() cmd:undo() end)
		if ok then table.insert(self.manager.redoStack, cmd) else warn("Undo failed:", err) end
	end
end
CommandManager.UndoCommand = UndoCommand

local RedoCommand = {}
RedoCommand.__index = RedoCommand
RedoCommand.__className = "RedoCommand"
setmetatable(RedoCommand, {__index = require(script.Parent.Command)})

function RedoCommand.new(manager)
	return setmetatable({manager = manager}, RedoCommand)
end
function RedoCommand:execute()
	local cmd = table.remove(self.manager.redoStack)
	if cmd then
		local ok, err = pcall(function() cmd:execute() end)
		if ok then table.insert(self.manager.undoStack, cmd) else warn("Redo failed:", err) end
	end
end
CommandManager.RedoCommand = RedoCommand

return CommandManager
