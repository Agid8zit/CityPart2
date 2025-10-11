---------------------------------------------------------------------
-- BuildPowerLineCommand.lua   •   grid-based orientation version
---------------------------------------------------------------------
local BuildPowerLineCommand = {}
BuildPowerLineCommand.__index = BuildPowerLineCommand

-- ───────────────────────────────────────────────────────────────────
-- Services & reference modules
-- ───────────────────────────────────────────────────────────────────
local S3                = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build      = S3:WaitForChild("Build")
local Zones      = Build:WaitForChild("Zones")
local ZoneMgr    = Zones:WaitForChild("ZoneManager")

local ZoneManager    = require(ZoneMgr:WaitForChild("ZoneManager"))
local ZoneTracker    = require(ZoneMgr:WaitForChild("ZoneTracker"))
local EconomyService = require(ZoneMgr:WaitForChild("EconomyService"))

local CC             = Zones:WaitForChild("CoreConcepts")
local PwrGen         = CC:WaitForChild("PowerGen")
local PowerLinePath  = require(PwrGen:WaitForChild("PowerLinePath"))

local BE = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents")
local RE = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents")
local zoneCreatedBE        = BE :WaitForChild("ZoneCreated")
local notifyZoneCreatedRE   = RE :WaitForChild("NotifyZoneCreated")

-- ───────────────────────────────────────────────────────────────────
-- Helpers
-- ───────────────────────────────────────────────────────────────────
-- 1) 2-D Bresenham preview (fallback)
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

-- 2) build heading list  ───────────────────────────────────────────
local function buildSegmentDirs(list)      -- NEW
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

-- ───────────────────────────────────────────────────────────────────
-- Constructor / (de)serialisers
-- ───────────────────────────────────────────────────────────────────
function BuildPowerLineCommand.new(player, startCoord, endCoord, mode)
	return setmetatable({
		player       = player,
		startCoord   = startCoord,
		endCoord     = endCoord,
		mode         = mode,
		lineId       = nil,
		gridList     = nil,
		segmentDirs  = nil,
		cost         = 0,
		wasCharged   = false,
	}, BuildPowerLineCommand)
end

function BuildPowerLineCommand:toData()    -- CHANGED
	return {
		CommandType = "BuildPowerLineCommand",
		Parameters = {
			startCoord  = {x=self.startCoord.x,y=self.startCoord.y,z=self.startCoord.z},
			endCoord    = {x=self.endCoord.x,  y=self.endCoord.y,  z=self.endCoord.z},
			mode        = self.mode,
			lineId      = self.lineId,
			segmentDirs = self.segmentDirs,   -- NEW
		},
		Timestamp = os.time(),
	}
end

function BuildPowerLineCommand.fromData(player, p)  -- CHANGED
	local start = Vector3.new(p.startCoord.x,p.startCoord.y,p.startCoord.z)
	local finish= Vector3.new(p.endCoord.x,  p.endCoord.y,  p.endCoord.z)
	local cmd   = BuildPowerLineCommand.new(player,start,finish,p.mode)
	cmd.lineId      = p.lineId
	cmd.segmentDirs = p.segmentDirs          -- NEW
	return cmd
end

-- ───────────────────────────────────────────────────────────────────
-- EXECUTE
-- ───────────────────────────────────────────────────────────────────
function BuildPowerLineCommand:execute()
	-- 1) Conflict check
	local preview  = previewGrid(self.startCoord, self.endCoord)
	local blocked, otherId = ZoneTracker.hasPopulatingConflict(self.player, preview)
	if blocked and otherId ~= self.lineId then
		local oz = ZoneTracker.getZoneById(self.player, otherId)
		-- Only block if the *other* populating zone is PowerLines (or a road type, if desired)
		local isRoad = oz and (oz.mode == "DirtRoad" or oz.mode == "Pavement" or oz.mode == "Highway")
		if oz and (oz.mode == "PowerLines" or isRoad) then
			warn(("Cannot lay %s line; conflicts with in-flight %s zone %s")
				:format(self.mode, tostring(oz.mode), tostring(otherId)))
			return
		end
		-- else: building/pipes/etc. → allowed to proceed concurrently
	end

	-- 2) Redo path? (already has id)
	if self.lineId then
		if not self.wasCharged and self.cost > 0 then
			EconomyService.chargePlayer(self.player, self.cost)
			self.wasCharged = true
		end
		PowerLinePath.registerLine(self.lineId, self.mode, self.gridList,
			self.startCoord, self.endCoord, self.segmentDirs)   -- CHANGED
		zoneCreatedBE:Fire(self.player, self.lineId, self.mode, self.gridList)
		return
	end

	-- 3) First-time build
	local ok, idOrErr = ZoneManager.buildPowerLine(
		self.player, self.startCoord, self.endCoord, self.mode)
	if not ok then error("Power line build failed: "..tostring(idOrErr)) end
	self.lineId = idOrErr

	-- Newly-created zone data
	local zoneData = ZoneTracker.getZoneById(self.player, self.lineId)
	assert(zoneData, "ZoneTracker missing new line")
	self.gridList    = zoneData.gridList
	self.segmentDirs = buildSegmentDirs(self.gridList)            -- NEW

	-- 4) Economy & occupancy
	self.cost = EconomyService.getCost(self.mode, #self.gridList)
	if not EconomyService.chargePlayer(self.player, self.cost) then
		error(("Need %d credits."):format(self.cost))
	end
	--[[
	for _,c in ipairs(self.gridList) do
		ZoneTracker.markGridOccupied(self.player,c.x,c.z,"power",self.lineId,self.mode)
	end
]]
	-- 5) Client notify
	notifyZoneCreatedRE:FireClient(self.player, self.lineId, self.gridList, self.segmentDirs) -- CHANGED
end

-- ───────────────────────────────────────────────────────────────────
-- UNDO
-- ───────────────────────────────────────────────────────────────────
function BuildPowerLineCommand:undo()
	if not self.lineId then
		warn("[BuildPowerLineCommand] undo: no lineId")
		return
	end
	ZoneManager.removePowerLine(self.player, self.lineId)
	if self.cost > 0 then
		EconomyService.adjustBalance(self.player, self.cost)
	end
end

return BuildPowerLineCommand
