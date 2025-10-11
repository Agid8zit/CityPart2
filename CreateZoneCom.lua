local Command = require(script.Parent.Command)
local ZoneManager = require(game.ServerScriptService.Build.Zones.ZoneManager.ZoneManager)

local CreateZoneCommand = {}
CreateZoneCommand.__index = CreateZoneCommand
setmetatable(CreateZoneCommand, Command)
CreateZoneCommand.__className = "CreateZoneCommand"

local DEBUG = false
local function debugPrint(...)
	if DEBUG then
		print("[CreateZoneCommand]", ...)
	end
end

function CreateZoneCommand.new(player, mode, gridList)
	local self = setmetatable({}, CreateZoneCommand)
	self.player = player
	self.mode = mode
	self.gridList = gridList
	self.zoneId = nil
	return self
end

function CreateZoneCommand:execute()
	debugPrint("execute called for player:", self.player.Name, "Mode:", self.mode)
	local selectedCoords = {
		start = self.gridList.start,
		finish = self.gridList.finish
	}
	local success, message, data = ZoneManager.onGridSelection(self.player, selectedCoords)
	if success then
		self.zoneId = data.zoneId
		debugPrint("Zone created with zoneId:", self.zoneId)
	else
		error("Failed to create zone - " .. tostring(message))
	end
end

function CreateZoneCommand:undo()
	debugPrint("undo called. Removing zoneId:", self.zoneId)
	if self.zoneId then
		local success = ZoneManager.onRemoveZone(self.player, self.zoneId)
		if not success then
			warn("Failed to undo zone creation for zoneId:", self.zoneId)
		else
			debugPrint("Zone removed successfully for undo.")
		end
	else
		warn("No zoneId to undo.")
	end
end

return CreateZoneCommand
