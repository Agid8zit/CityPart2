-- MetroTunnelGeneratorScript.server.lua
-- Handles create, recreate, and removal for MetroTunnel utility zones.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Events            = ReplicatedStorage:WaitForChild("Events")
local BindableEvents    = Events:WaitForChild("BindableEvents")

local MetroTunnelGenerator = require(script.Parent:WaitForChild("MetroTunnelGenerator"))

-- Modes this script owns (extend if you add variants)
local metroTypes = {
	MetroTunnel = true,
}

-- Helpers ---------------------------------------------------------------------

local function isMetroMode(mode: string?): boolean
	return mode ~= nil and metroTypes[mode] == true
end

-- Recreate idempotently: clear this zone's tunnels, then regenerate from coords
local function recreateMetro(player: Player, zoneId: string, mode: string, coords: {any})
	if not isMetroMode(mode) then return end
	if type(coords) ~= "table" or #coords == 0 then
		warn(("[MetroTunnelGeneratorScript] No coords to (re)create for %s (%s)"):format(zoneId, tostring(mode)))
		return
	end

	-- Make regeneration idempotent by cleaning any leftovers first
	if typeof(MetroTunnelGenerator.removeMetroZone) == "function" then
		pcall(MetroTunnelGenerator.removeMetroZone, player, zoneId)
	end

	-- Generate fresh from the path coordinates (no stored snapshot required)
	MetroTunnelGenerator.generateMetro(player, zoneId, mode, coords)
end

-- Events ----------------------------------------------------------------------

-- 1) Fresh zone creation
local ZoneCreated = BindableEvents:WaitForChild("ZoneCreated")
ZoneCreated.Event:Connect(function(player: Player, zoneId: string, mode: string, selectedCoords: {any})
	if not isMetroMode(mode) then return end
	print(string.format("[MetroTunnelGeneratorScript] Create: %s (%s)", zoneId, mode))
	recreateMetro(player, zoneId, mode, selectedCoords)
end)

-- 2) Zone re-creation (e.g., on load)
-- Signature: (player, zoneId, mode, coords, payloadOrSnapshot?, rotationOr0?)
local ZoneReCreated = BindableEvents:WaitForChild("ZoneReCreated")
ZoneReCreated.Event:Connect(function(player: Player, zoneId: string, mode: string, coords: {any})
	if not isMetroMode(mode) then return end
	print(string.format("[MetroTunnelGeneratorScript] Recreate: %s (%s)", zoneId, mode))
	recreateMetro(player, zoneId, mode, coords)
end)

-- 3) Zone removal → clean up occupancy and visuals so future placements aren’t blocked
local ZoneRemoved = BindableEvents:WaitForChild("ZoneRemoved")
ZoneRemoved.Event:Connect(function(player: Player, zoneId: string)
	-- We don't know the mode here, but removal is safe/idempotent.
	if typeof(MetroTunnelGenerator.removeMetroZone) == "function" then
		print(string.format("[MetroTunnelGeneratorScript] Remove: %s", zoneId))
		pcall(MetroTunnelGenerator.removeMetroZone, player, zoneId)
	end
end)
