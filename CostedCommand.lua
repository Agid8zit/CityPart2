local Command = require(script.Parent.Command)
local EconomyService = require(game.ServerScriptService.Build.Zones.ZoneManager.EconomyService)

local CostedCommand = {}
CostedCommand.__index = CostedCommand
setmetatable(CostedCommand, {__index = Command})
CostedCommand.__className = "CostedCommand"

-- Constructor
function CostedCommand.new(player, cost)
	local self = setmetatable({}, CostedCommand)
	self.player = player
	self.cost = cost or 0
	self.wasCharged = false
	return self
end

-- Main entrypoint - automatically handles economy
function CostedCommand:execute()
	if self.cost > 0 and not self.wasCharged then
		if not EconomyService.chargePlayer(self.player, self.cost) then
			error("Insufficient funds. Required: " .. self.cost)
		end
		self.wasCharged = true
	end

	if self.run then
		self:run()
	else
		error("CostedCommand: 'run' method not implemented.")
	end
end

-- Undo logic - handles refunding
function CostedCommand:undo()
	if self.runUndo then
		self:runUndo()
	else
		error("CostedCommand: 'runUndo' method not implemented.")
	end
	
	if self.cost > 0 then
		EconomyService.adjustBalance(self.player, self.cost)
	end
end

return CostedCommand