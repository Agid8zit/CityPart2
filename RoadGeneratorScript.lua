local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Events = ReplicatedStorage:WaitForChild("Events")
local BindableEvents = Events:WaitForChild("BindableEvents")

local RoadGeneratorModule = require(script.Parent:WaitForChild("RoadGenerator"))

-- Road types recognized by this script
local roadTypes = {
	DirtRoad = true,
	Pavement = true,
	Highway = true,
	-- Add any other valid road modes here
}

local VERBOSE_LOG = false
local function log(...)
	if VERBOSE_LOG then print(...) end
end

-- Listen for ZoneCreated event
local zoneCreatedEvent = BindableEvents:WaitForChild("ZoneCreated")
zoneCreatedEvent.Event:Connect(function(player, zoneId, mode, selectedCoords)
	-- Only handle recognized road modes
	if roadTypes[mode] then
		log(string.format(
			"RoadGeneratorScript: Generating road for Zone '%s' of type '%s'",
			zoneId, mode
			))
		RoadGeneratorModule.populateZone(player, zoneId, mode, selectedCoords)
	end
end)

-- Listen for ZoneReCreated event (rebuild roads)
local zoneReCreatedEvent = BindableEvents:WaitForChild("ZoneReCreated")
zoneReCreatedEvent.Event:Connect(function(player, zoneId, mode, gridList, saved, rotation)
	if not roadTypes[mode] then return end

	--print(string.format("RoadGeneratorScript: Re-creating road zone '%s' (%s) for player '%s'",zoneId, mode, player.Name))

	if typeof(RoadGeneratorModule.removeRoad) == "function" then
		RoadGeneratorModule.removeRoad(player, zoneId)
	end

	local isSnapshot =
		(typeof(saved) == "table") and (saved.segments ~= nil) and (typeof(saved.segments) == "table")
	local isPlacedList =
		(typeof(saved) == "table") and (#saved > 0) and (typeof(saved[1]) == "table") and (saved[1].gridX ~= nil)

	if isSnapshot and typeof(RoadGeneratorModule.populateZoneFromSave) == "function" then
		return RoadGeneratorModule.populateZoneFromSave(player, zoneId, mode, gridList, saved, rotation)
	elseif isPlacedList then
		return RoadGeneratorModule.populateZone(player, zoneId, mode, gridList, saved, rotation, true)
	else
		-- Treat as no predefined content (procedural rebuild)
		return RoadGeneratorModule.populateZone(player, zoneId, mode, gridList, nil, rotation, true)
	end
end)

-- Listen for ZoneRemoved event
local zoneRemovedEvent = BindableEvents:WaitForChild("ZoneRemoved")
zoneRemovedEvent.Event:Connect(function(player, zoneId, mode)
	-- Only remove roads if this zone is actually a road
	if roadTypes[mode] then
		--print(string.format("RoadGeneratorScript: Removing roads for Zone '%s' for player '%s'",zoneId, player.Name))
		RoadGeneratorModule.removeRoad(player, zoneId)
	end
end)

log("RoadGeneratorScript loaded.")
