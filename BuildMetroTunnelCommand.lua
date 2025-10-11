---------------------------------------------------------------------
-- BuildMetroTunnelCommand.lua   •   linear metro builder
---------------------------------------------------------------------
local BuildMetroTunnelCommand = {}
BuildMetroTunnelCommand.__index = BuildMetroTunnelCommand

local S3                = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build      = S3:WaitForChild("Build")
local Zones      = Build:WaitForChild("Zones")
local ZoneMgr    = Zones:WaitForChild("ZoneManager")

local ZoneManager    = require(ZoneMgr:WaitForChild("ZoneManager"))
local ZoneTracker    = require(ZoneMgr:WaitForChild("ZoneTracker"))
local EconomyService = require(ZoneMgr:WaitForChild("EconomyService"))

local BE = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents")
local RE = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents")
local zoneCreatedBE       = BE:WaitForChild("ZoneCreated")
local notifyZoneCreatedRE = RE:WaitForChild("NotifyZoneCreated")

-- simple Bresenham from A->B (same as powerline file)
local function previewGrid(a, b)
	local pts = {}
	local x0, z0 = math.floor(a.x + .5), math.floor(a.z + .5)
	local x1, z1 = math.floor(b.x + .5), math.floor(b.z + .5)
	local dx, dz = math.abs(x1 - x0), -math.abs(z1 - z0)
	local sx     = x0 < x1 and 1 or -1
	local sz     = z0 < z1 and 1 or -1
	local err    = dx + dz
	while true do
		table.insert(pts, {x = x0, z = z0})
		if x0 == x1 and z0 == z1 then break end
		local e2 = 2 * err
		if e2 >=  dz then err += dz; x0 += sx end
		if e2 <=  dx then err += dx; z0 += sz end
	end
	return pts
end

local function buildSegmentDirs(list)
	local dirs = table.create(#list - 1)
	for i = 1, #list - 1 do
		local a, b  = list[i], list[i+1]
		local dx, dz = b.x - a.x, b.z - a.z
		dirs[i] =
			(dx ==  1 and "E") or (dx == -1 and "W") or
			(dz ==  1 and "S") or (dz == -1 and "N") or "?"
	end
	return dirs
end

function BuildMetroTunnelCommand.new(player, startCoord, endCoord, mode)
	return setmetatable({
		player      = player,
		startCoord  = startCoord,
		endCoord    = endCoord,
		mode        = mode,      -- must be "MetroTunnel"
		lineId      = nil,
		gridList    = nil,
		segmentDirs = nil,
		cost        = 0,
		wasCharged  = false,
	}, BuildMetroTunnelCommand)
end

function BuildMetroTunnelCommand:toData()
	return {
		CommandType = "BuildMetroTunnelCommand",
		Parameters = {
			startCoord  = {x=self.startCoord.x,y=self.startCoord.y,z=self.startCoord.z},
			endCoord    = {x=self.endCoord.x,  y=self.endCoord.y,  z=self.endCoord.z},
			mode        = self.mode,
			lineId      = self.lineId,
			segmentDirs = self.segmentDirs,
		},
		Timestamp = os.time(),
	}
end

function BuildMetroTunnelCommand.fromData(player, p)
	local start = Vector3.new(p.startCoord.x,p.startCoord.y,p.startCoord.z)
	local finish= Vector3.new(p.endCoord.x,  p.endCoord.y,  p.endCoord.z)
	local cmd   = BuildMetroTunnelCommand.new(player,start,finish,p.mode)
	cmd.lineId      = p.lineId
	cmd.segmentDirs = p.segmentDirs
	return cmd
end

function BuildMetroTunnelCommand:execute()
	-- Allow concurrent with non-conflicting zones, block if other *tunnel* is populating (optional)
	local preview  = previewGrid(self.startCoord, self.endCoord)
	local blocked, otherId = ZoneTracker.hasPopulatingConflict(self.player, preview)
	if blocked and otherId ~= self.lineId then
		local oz = ZoneTracker.getZoneById(self.player, otherId)
		if oz and (oz.mode == "MetroTunnel") then
			warn(("Cannot lay %s; conflicts with in-flight %s %s")
				:format(self.mode, tostring(oz.mode), tostring(otherId)))
			return
		end
	end

	-- Redo path (already has id)
	if self.lineId then
		if not self.wasCharged and self.cost > 0 then
			EconomyService.chargePlayer(self.player, self.cost)
			self.wasCharged = true
		end
		zoneCreatedBE:Fire(self.player, self.lineId, self.mode, self.gridList)
		return
	end

	-- First-time build through ZoneManager
	local ok, idOrErr = ZoneManager.buildMetroTunnel(
		self.player, self.startCoord, self.endCoord, self.mode)
	if not ok then error("Metro tunnel build failed: "..tostring(idOrErr)) end
	self.lineId = idOrErr

	-- Load stored data (grid path from ZoneTracker)
	local zoneData = ZoneTracker.getZoneById(self.player, self.lineId)
	assert(zoneData, "ZoneTracker missing new MetroTunnel")
	self.gridList    = zoneData.gridList
	self.segmentDirs = buildSegmentDirs(self.gridList)

	-- Charge economy (per-tile cost, if configured)
	self.cost = EconomyService.getCost(self.mode, #self.gridList)
	if (self.cost or 0) > 0 then
		if not EconomyService.chargePlayer(self.player, self.cost) then
			error(("Need %d credits."):format(self.cost))
		end
		self.wasCharged = true
	else
		-- zero-cost: do not attempt to charge or throw
		self.wasCharged = false
	end

	-- Client notify (optional payload mirrors powerlines)
	notifyZoneCreatedRE:FireClient(self.player, self.lineId, self.gridList, self.segmentDirs)
end

function BuildMetroTunnelCommand:containsZone(zoneId)
	return self.lineId == zoneId
end

function BuildMetroTunnelCommand:undo()
	if not self.lineId then
		warn("[BuildMetroTunnelCommand] undo: no lineId")
		return
	end
	-- Generic remove works; if you later add specialized cleanup, call a dedicated remover.
	local ok = ZoneManager.onRemoveZone(self.player, self.lineId)
	if ok and self.cost > 0 then
		EconomyService.adjustBalance(self.player, self.cost)
	end
end

return BuildMetroTunnelCommand
