-- PowerGeneratorScript (server)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Events           = ReplicatedStorage:WaitForChild("Events")
local BindableEvents   = Events:WaitForChild("BindableEvents")

local PowerGeneratorModule = require(script.Parent:WaitForChild("PowerGenerator"))
local ZoneTrackerModule    = require(script.Parent.Parent.Parent.ZoneManager:WaitForChild("ZoneTracker"))

local powerZoneTypes = {
	PowerLines = true,
	-- e.g., Substation = true,
}

local zoneAddedEvent     = BindableEvents:WaitForChild("ZoneAdded")     -- <— NEW
local zoneRemovedEvent   = BindableEvents:WaitForChild("ZoneRemoved")
local zoneReCreatedEvent = BindableEvents:WaitForChild("ZoneReCreated")

local VERBOSE_LOG = false
local function log(...)
	if VERBOSE_LOG then print(...) end
end

-- Remove the duplicated ZoneCreated connection (you currently have it twice).
-- Keep ZoneCreated only for UI/client notify flows if you want.
-- (If you keep one, leave it, but power line population should hinge on ZoneAdded.)

zoneAddedEvent.Event:Connect(function(player, zoneId, zoneData)
	-- zoneData is guaranteed present here
	if not zoneData then return end
	if not powerZoneTypes[zoneData.mode] then return end

	--print(("[PowerGeneratorScript] ZoneAdded received. ZoneId='%s' Mode='%s'"):format(zoneId, zoneData.mode))

	-- zoneData.gridList is the authoritative footprint
	PowerGeneratorModule.populateZone(player, zoneId, zoneData.mode, zoneData.gridList)
end)

zoneReCreatedEvent.Event:Connect(function(player, zoneId, mode, gridList, predefinedLines, rotation, isReload)
	if not powerZoneTypes[mode] then return end

	--print(("[PowerGeneratorScript] ZoneReCreated received. Rebuilding zone '%s' for '%s'."):format(zoneId, player.Name))

	-- Defensive cleanup (if implemented)
	if typeof(PowerGeneratorModule.removeLines) == "function" then
		PowerGeneratorModule.removeLines(player, zoneId)
	end

	-- Replay saved geometry if present, else regenerate
	PowerGeneratorModule.populateZone(player, zoneId, mode, gridList, predefinedLines, rotation, true, isReload)
end)

zoneRemovedEvent.Event:Connect(function(player, zoneId, mode)
	if powerZoneTypes[mode] then
		log(("[PowerGeneratorScript] ZoneRemoved received. Cleaning up zone '%s' for '%s'."):format(zoneId, player.Name))
		PowerGeneratorModule.removeLines(player, zoneId)
	end
end)

log("[PowerGeneratorScript] Module loaded and listening on ZoneAdded/ZoneReCreated/ZoneRemoved.")
