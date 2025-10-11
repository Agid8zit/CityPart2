-- PipeGeneratorScript.server.lua
-- Fully enhanced: handles create, recreate, and removal for pipe-type utility zones.
-- No persistence needed — we always rebuild directly from the coords given.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Events            = ReplicatedStorage:WaitForChild("Events")
local BindableEvents    = Events:WaitForChild("BindableEvents")

local PipeGeneratorModule = require(script.Parent:WaitForChild("PipeGenerator"))

-- Utility zone types this script owns (extend if you add more)
local utilityTypes = {
	WaterPipe = true, -- your current mode
	-- e.g. "Pipe" = true, "WaterLines" = true
}

-- Helpers ---------------------------------------------------------------------

local function isUtilityMode(mode: string?): boolean
	return mode ~= nil and utilityTypes[mode] == true
end

-- Recreate idempotently: clear this zone's pipes, then regenerate from coords
local function recreatePipes(player: Player, zoneId: string, mode: string, coords: {any})
	if not isUtilityMode(mode) then return end
	if type(coords) ~= "table" or #coords == 0 then
		warn(("[PipeGeneratorScript] No coords to (re)create for %s (%s)"):format(zoneId, tostring(mode)))
		return
	end

	-- Make regeneration idempotent by cleaning any leftovers first
	if typeof(PipeGeneratorModule.removePipeZone) == "function" then
		pcall(PipeGeneratorModule.removePipeZone, player, zoneId)
	end

	-- Generate fresh from the path coordinates (no stored snapshot required)
	PipeGeneratorModule.generatePipe(player, zoneId, mode, coords)
end

-- Events ----------------------------------------------------------------------

-- 1) Fresh zone creation
local ZoneCreated = BindableEvents:WaitForChild("ZoneCreated")
ZoneCreated.Event:Connect(function(player: Player, zoneId: string, mode: string, selectedCoords: {any})
	if not isUtilityMode(mode) then return end
	print(string.format("[PipeGeneratorScript] Create: %s (%s)", zoneId, mode))
	recreatePipes(player, zoneId, mode, selectedCoords)
end)

-- 2) Zone re-creation (e.g., on load) — SaveManager fires this with coords
-- Signature: (player, zoneId, mode, coords, payloadOrSnapshot, rotationOr0)
local ZoneReCreated = BindableEvents:WaitForChild("ZoneReCreated")
ZoneReCreated.Event:Connect(function(player: Player, zoneId: string, mode: string, coords: {any})
	if not isUtilityMode(mode) then return end
	--print(string.format("[PipeGeneratorScript] Recreate: %s (%s)", zoneId, mode))
	recreatePipes(player, zoneId, mode, coords)
end)

-- 3) Zone removal → clean up occupancy and visuals so future placements aren’t blocked
local ZoneRemoved = BindableEvents:WaitForChild("ZoneRemoved")
ZoneRemoved.Event:Connect(function(player: Player, zoneId: string)
	-- We don't know the mode here, but removal is safe/idempotent.
	if typeof(PipeGeneratorModule.removePipeZone) == "function" then
		print(string.format("[PipeGeneratorScript] Remove: %s", zoneId))
		pcall(PipeGeneratorModule.removePipeZone, player, zoneId)
	end
end)
