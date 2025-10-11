local CommandClasses = {}

CommandClasses["BuildRoadCommand"] = require(script.Parent.BuildRoadCommand)
CommandClasses["BuildPipeCommand"] = require(script.Parent.BuildPipeCommand)
CommandClasses["PlaceBuildingCommand"] = require(script.Parent.PlaceBuildingCommand)
CommandClasses["CreateZoneCommand"] = require(script.Parent.CreateZoneCom)
CommandClasses["DeleteZoneCommand"] = require(script.Parent.DeleteZoneCom)
CommandClasses["BuildZoneCommand"] = require(script.Parent.BuildZoneCommand)
CommandClasses["BuildPowerLineCommand"] = require(script.Parent.BuildPowerLineCommand)
CommandClasses["BuildMetroTunnelCommand"] = require(script.Parent.BuildMetroTunnelCommand)

return CommandClasses