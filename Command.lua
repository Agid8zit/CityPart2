local Command = {}
Command.__index = Command

-- Abstract execute method
function Command:execute()
	error("execute() must be implemented by subclass")
end

-- Abstract undo method
function Command:undo()
	error("undo() must be implemented by subclass")
end

return Command