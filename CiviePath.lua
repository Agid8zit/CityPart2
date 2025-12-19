local CivPathing = {}
CivPathing.__index = CivPathing

----------------------------------------------------------------------
-- Sections
--   1) Module setup & configuration
--   2) Zone state & event wiring
--   3) Math / grid helpers
--   4) Adjacency & destination helpers
--   5) Path building entry points
----------------------------------------------------------------------

----------------------------------------------------------------------
-- 1) Module setup & configuration
----------------------------------------------------------------------

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Workspace           = game:GetService("Workspace")
local ZoneTrackerModule   = require(game.ServerScriptService.Build.Zones.ZoneManager.ZoneTracker)
local GridConfig          = require(game.ReplicatedStorage.Scripts.Grid.GridConfig)
local GridUtil            = require(game.ReplicatedStorage.Scripts.Grid.GridUtil)

-- Optional events
local BindableEvents  = ReplicatedStorage:FindFirstChild("Events")
	and ReplicatedStorage.Events:FindFirstChild("BindableEvents")
local ZoneAddedEvent   = BindableEvents and BindableEvents:FindFirstChild("ZoneAdded")
local ZoneRemovedEvent = BindableEvents and BindableEvents:FindFirstChild("ZoneRemoved")


----------------------------------------------------------------------
-- Config / Injection points
----------------------------------------------------------------------

CivPathing.Debug                   = false

-- Destination picking
CivPathing.DestinationStrategy     = "nearest" -- or "random"
CivPathing.DestinationJitterProb   = 0.5

-- Grid move rules
CivPathing.AllowDiagonals          = true
CivPathing.NoCornerCutting         = true
CivPathing.AStarMaxNodes           = 12000
CivPathing.AStarHeuristicWeight    = 1.5  -- f(n) = g(n) + weight * h(n)

-- Prefer roads
CivPathing.PreferRoads             = true
CivPathing.RoadCaptureRadius       = 128
CivPathing.BlockRoadsInOffroad     = true

-- Zones civvies may IGNORE (walk through)
CivPathing.PassthroughModes = {
	--PowerLines = true, Power = true,
	Pipes = true, WaterPipe = true,
}

-- Which zone modes count as "roads"
CivPathing.RoadModes = {
	DirtRoad = true, Road = true,
}

-- Road curb-following (sticky curb side)
CivPathing.RoadWalkOffset               = nil         -- e.g., set to 1.9 to force ~2 studs
CivPathing.RoadWalkOffsetFactor         = 0.49        -- ~half the cell width (very near curb)
CivPathing.RoadWalkOffsetMax            = 6.0         -- cap for very large cells
CivPathing.RoadEdgeMarginStuds          = 0.20        -- don’t sit *on* the curb; tiny safety margin
CivPathing.StickyCurb                   = true
CivPathing.ForceRoadWhenNear    = true
CivPathing.RoadSnapRadiusCells  = 6     -- X in “within X radius”

-- Inject a BFS over the car road graph
local roadBFS = nil
function CivPathing.setRoadBFS(fn) roadBFS = fn end

-- Inject road adjacency provider { ["x_z"] = {neighbors...}, ... }
local adjProvider = nil
function CivPathing.setAdjacencyProvider(fn) adjProvider = fn end


----------------------------------------------------------------------
-- 2) Zone state & event wiring
----------------------------------------------------------------------
local zones = {}
CivPathing.zones = zones

local function dprint(...) if CivPathing.Debug then print("[CivPathing]", ...) end end
local UP = Vector3.new(0,1,0)


----------------------------------------------------------------------
-- 3) Math / Grid helpers
----------------------------------------------------------------------
local directionAngles = {
	North=270, NorthEast=315, East=0, SouthEast=45,
	South=90,  SouthWest=135, West=180, NorthWest=225
}
CivPathing.directionAngles = directionAngles

function CivPathing.nodeKey(c) return tostring(c.x).."_"..tostring(c.z) end
function CivPathing.splitKey(k) local t=string.split(k,"_"); return tonumber(t[1]), tonumber(t[2]) end
function CivPathing.manhattan(a,b) return math.abs(a.x-b.x)+math.abs(a.z-b.z) end
function CivPathing.euclidean(a,b) local dx=a.x-b.x; local dz=a.z-b.z; return math.sqrt(dx*dx+dz*dz) end
function CivPathing.octile(a,b)
	local dx, dz = math.abs(a.x-b.x), math.abs(a.z-b.z)
	local dmin, dmax = math.min(dx,dz), math.max(dx,dz)
	return dmin*math.sqrt(2)+(dmax-dmin)
end

function CivPathing.angleBetween(a,b)
	local dx, dz = b.x-a.x, b.z-a.z
	if dx==0 and dz==0 then return -1 end
	local ang = math.deg(math.atan2(dz,dx))
	if ang < 0 then ang = ang + 360 end
	return ang
end

function CivPathing.nearestDirection(angle)
	local best, bestDiff = "Undefined", 360
	for dir,deg in pairs(directionAngles) do
		local d = math.abs(angle-deg); if d>180 then d=360-d end
		if d<bestDiff then bestDiff, best = d, dir end
	end
	return best
end

local function cardinalNeighbors4(c)
	return {
		{x=c.x+1,z=c.z}, {x=c.x-1,z=c.z},
		{x=c.x,z=c.z+1}, {x=c.x,z=c.z-1},
	}
end

local function neighbors8(c)
	local out = cardinalNeighbors4(c)
	out[#out+1] = {x=c.x+1,z=c.z+1}
	out[#out+1] = {x=c.x+1,z=c.z-1}
	out[#out+1] = {x=c.x-1,z=c.z+1}
	out[#out+1] = {x=c.x-1,z=c.z-1}
	return out
end

local function fillLineBetweenCoords_(coords)
	if #coords < 2 then return coords end
	local full = {}
	table.insert(full, coords[1])
	for i=1,#coords-1 do
		local c1, c2 = coords[i], coords[i+1]
		if c1.x == c2.x then
			local step = (c2.z > c1.z) and 1 or -1
			for z=c1.z+step, c2.z, step do table.insert(full, {x=c1.x, z=z}) end
		elseif c1.z == c2.z then
			local step = (c2.x > c1.x) and 1 or -1
			for x=c1.x+step, c2.x, step do table.insert(full, {x=x, z=c1.z}) end
		else
			table.insert(full, c2)
		end
	end
	return full
end

CivPathing.fillLineBetweenCoords = fillLineBetweenCoords_
CivPathing.cardinalNeighbors4    = cardinalNeighbors4
CivPathing.neighbors8            = neighbors8


-- Mode helpers
function CivPathing.isRoadMode(mode)        return mode ~= nil and CivPathing.RoadModes[mode] == true end
function CivPathing.isPassthroughMode(mode) return mode ~= nil and CivPathing.PassthroughModes[mode] == true end


-- Zone tracker integration
-- Track zone payloads from Build pipeline so we can reuse descriptors.
function CivPathing.onZoneAdded(a, b)
	if typeof(a) == "Instance" and a:IsA("Player") then
		local player, zoneId = a, tostring(b)
		if ZoneTrackerModule.getZoneById then
			local z = ZoneTrackerModule.getZoneById(player, zoneId)
			if z then zones[zoneId] = z else zones[zoneId] = zones[zoneId] or { zoneId = zoneId } end
		else
			zones[zoneId] = zones[zoneId] or { zoneId = zoneId }
		end
		return
	end
	local payload = a
	local id = payload and (payload.Id or payload.id or payload.zoneId) or tostring(payload)
	zones[id] = payload
end

-- Drop cached descriptors when a zone disappears.
function CivPathing.onZoneRemoved(a, b)
	local zoneId = (typeof(a) == "Instance" and a:IsA("Player")) and tostring(b) or tostring(a)
	if not zoneId then return end
	zones[zoneId] = nil
end

function CivPathing.refreshFromTracker()
	local ok, result = pcall(function()
		if ZoneTrackerModule.GetAllZones then return ZoneTrackerModule:GetAllZones()
		elseif ZoneTrackerModule.GetZones then   return ZoneTrackerModule:GetZones()
		elseif ZoneTrackerModule.Zones then     return ZoneTrackerModule.Zones end
		return nil
	end)
	if ok and result then
		for k,v in pairs(result) do
			if typeof(k) == "string" or typeof(k) == "number" then zones[k] = v
			elseif typeof(v) == "table" then zones[v.Id or v.id or v.zoneId or tostring(k)] = v end
		end
	end
	return zones
end

local function tryConnectEvents()
	if ZoneAddedEvent   and ZoneAddedEvent.Event   then ZoneAddedEvent.Event:Connect(function(...) CivPathing.onZoneAdded(...) end) end
	if ZoneRemovedEvent and ZoneRemovedEvent.Event then ZoneRemovedEvent.Event:Connect(function(...) CivPathing.onZoneRemoved(...) end) end
end
tryConnectEvents()


-- Plot/world helpers (match RoadGeneratorModule math)
local boundsCache = {} -- [plot] -> { bounds, terrains }

local function getGlobalBoundsForPlot(plot)
	local cached = boundsCache[plot]
	if cached then return cached.bounds, cached.terrains end

	local terrains = {}
	local unlocks  = plot and plot:FindFirstChild("Unlocks")
	if unlocks then
		for _, zone in ipairs(unlocks:GetChildren()) do
			for _, seg in ipairs(zone:GetChildren()) do
				if seg:IsA("BasePart") and seg.Name:match("^Segment%d+$") then
					table.insert(terrains, seg)
				end
			end
		end
	end
	local testTerrain = plot and plot:FindFirstChild("TestTerrain")
	if #terrains == 0 and testTerrain then table.insert(terrains, testTerrain) end

	local gb = GridConfig.calculateGlobalBounds(terrains)
	boundsCache[plot] = { bounds = gb, terrains = terrains }
	return gb, terrains
end

function CivPathing.gridToWorld(coord, plot)
	if not plot then return Vector3.new() end
	local gb, terrains = getGlobalBoundsForPlot(plot)
	if gb then
		local wx, _, wz = GridUtil.globalGridToWorldPosition(coord.x, coord.z, gb, terrains)
		return Vector3.new(wx, 0, wz)
	else
		local tt = plot:FindFirstChild("TestTerrain")
		local minX, minZ = GridConfig.calculateCoords(tt)
		local wx, wz     = GridUtil.gridToWorldPosition(coord.x, coord.z, minX, minZ)
		return Vector3.new(wx, 0, wz)
	end
end

function CivPathing.gridPathToWorld(path, plot)
	local out = table.create(#path)
	for i = 1, #path do out[i] = CivPathing.gridToWorld(path[i], plot) end
	return out
end

local function _cellStepWorld(plot)
	local a  = CivPathing.gridToWorld({x=0,z=0}, plot)
	local ax = CivPathing.gridToWorld({x=1,z=0}, plot)
	local az = CivPathing.gridToWorld({x=0,z=1}, plot)
	local dx = (ax - a); dx = Vector3.new(dx.X,0,dx.Z).Magnitude
	local dz = (az - a); dz = Vector3.new(dz.X,0,dz.Z).Magnitude
	if dx > 1e-3 and dz > 1e-3 then return (dx+dz)*0.5 end
	return (dx>1e-3) and dx or ((dz>1e-3) and dz or 4.0)
end


-- Zone math
function CivPathing.nearestCellInZoneTo(srcCell, zone)
	local list = zone and zone.gridList
	if not list or #list == 0 then return nil, math.huge end
	local best, bestD
	for _, c in ipairs(list) do
		local d = math.abs(c.x - srcCell.x) + math.abs(c.z - srcCell.z)
		if not bestD or d < bestD then best, bestD = c, d end
		if bestD == 0 then break end
	end
	return best, bestD or math.huge
end

function CivPathing.pickDestinationZone(player, srcZone, strategy)
	strategy = strategy or CivPathing.DestinationStrategy
	if not srcZone or not srcZone.gridList or #srcZone.gridList == 0 then return nil end

	local all = ZoneTrackerModule.getAllZones(player); if not all then return nil end
	local startCell = srcZone.gridList[1]
	local pool = {}
	for zoneId, z in pairs(all) do
		if z ~= srcZone and z.mode and z.gridList and #z.gridList > 0
			and not CivPathing.isRoadMode(z.mode)
			and not CivPathing.isPassthroughMode(z.mode)
		then
			local targetCell, d = CivPathing.nearestCellInZoneTo(startCell, z)
			if targetCell then
				table.insert(pool, { id = zoneId, data = z, a = startCell, b = targetCell, dist = d })
			end
		end
	end
	if #pool == 0 then return nil end
	if strategy == "random" then return pool[math.random(1, #pool)] end
	table.sort(pool, function(p,q) return p.dist < q.dist end)
	if #pool == 1 then return pool[1] end
	if (CivPathing.DestinationJitterProb or 0) > 0 and math.random() < CivPathing.DestinationJitterProb then
		return pool[math.random(1, #pool)]
	end
	return pool[1]
end

-- Road-graph helpers
local function getAdjacency() return (adjProvider and adjProvider()) or nil end

local function _buildCellModeIndex(player)
	local idx, all = {}, ZoneTrackerModule.getAllZones(player)
	if not all then return idx end
	for zid, z in pairs(all) do
		if typeof(z)=="table" and z.gridList then
			for _,c in ipairs(z.gridList) do
				idx[CivPathing.nodeKey(c)] = { id = zid, mode = z.mode }
			end
		end
	end
	return idx
end

local function _isRoadCellKey(key, cellModeIndex, roadModes)
	local hit = cellModeIndex[key]
	return hit and hit.mode and (roadModes[hit.mode] == true)
end

local function _buildRoadCellSet(player, roadModes)
	local set, idx = {}, _buildCellModeIndex(player)
	for k, meta in pairs(idx) do
		if meta.mode and roadModes[meta.mode] then set[k] = true end
	end
	return set
end

----------------------------------------------------------------------
-- 4) Adjacency & destination helpers
----------------------------------------------------------------------

function CivPathing.nearestRoadNodeFromZone(zone, radius)
	local adj = getAdjacency(); if not adj then return nil end
	local list = zone and zone.gridList; if not list or #list == 0 then return nil end
	local best, bestD
	for _, cell in ipairs(list) do
		for dx = -radius, radius do
			local rem = radius - math.abs(dx)
			for dz = -rem, rem do
				local c = { x = cell.x + dx, z = cell.z + dz }
				local k = CivPathing.nodeKey(c)
				if adj[k] then
					local d = math.abs(dx) + math.abs(dz)
					if not bestD or d < bestD then best, bestD = c, d; if d == 0 then return best end end
				end
			end
		end
	end
	return best
end

local function _nearestRoadNodeFromCell(cell, searchRadius)
	local adj = getAdjacency(); if not adj then return nil end
	local best, bestD
	for dx = -searchRadius, searchRadius do
		local rem = searchRadius - math.abs(dx)
		for dz = -rem, rem do
			local c = {x=cell.x+dx, z=cell.z+dz}
			local k = CivPathing.nodeKey(c)
			if adj[k] then
				local d = math.abs(dx) + math.abs(dz)
				if not bestD or d < bestD then best, bestD = c, d; if d==0 then return best end end
			end
		end
	end
	return best
end

local function _nearestRoadNodeToZoneGrowing(dstZone, maxRadius)
	maxRadius = maxRadius or 256
	for r=8, maxRadius, 16 do
		local n = CivPathing.nearestRoadNodeFromZone(dstZone, r)
		if n then return n end
	end
	local adj = getAdjacency(); if not adj then return nil end
	if not dstZone or not dstZone.gridList or #dstZone.gridList == 0 then return nil end
	local best, bestD = nil, math.huge
	for k,_ in pairs(adj) do
		local x,z = CivPathing.splitKey(k)
		for _,c in ipairs(dstZone.gridList) do
			local d = math.abs(c.x - x) + math.abs(c.z - z)
			if d < bestD then bestD, best = d, {x=x,z=z} end
		end
	end
	return best
end


-- Obstacle building + 8-dir A* (off-road only)
local function _neighborsFiltered(c, blocked, allowDiag, noCornerCut)
	local nbrs = {
		{x=c.x+1,z=c.z}, {x=c.x-1,z=c.z},
		{x=c.x,  z=c.z+1}, {x=c.x,  z=c.z-1},
	}
	if allowDiag then
		local diags = {
			{x=c.x+1,z=c.z+1}, {x=c.x+1,z=c.z-1},
			{x=c.x-1,z=c.z+1}, {x=c.x-1,z=c.z-1},
		}
		for _,d in ipairs(diags) do
			if not noCornerCut then
				if not blocked[CivPathing.nodeKey(d)] then table.insert(nbrs, d) end
			else
				local dx, dz = d.x - c.x, d.z - c.z
				local sideA = {x=c.x+dx, z=c.z}
				local sideB = {x=c.x,    z=c.z+dz}
				if (not blocked[CivPathing.nodeKey(d)])
					and (not blocked[CivPathing.nodeKey(sideA)])
					and (not blocked[CivPathing.nodeKey(sideB)]) then
					table.insert(nbrs, d)
				end
			end
		end
	end
	local out = {}
	for _,n in ipairs(nbrs) do
		if not blocked[CivPathing.nodeKey(n)] then table.insert(out, n) end
	end
	return out
end

-- Build a lookup of "forbidden" grid cells when generating off-road stubs.
function CivPathing.buildBlockedCellsFromZones(player, opts)
	opts = opts or {}
	local blocked = {}
	local all = ZoneTrackerModule.getAllZones(player); if not all then return blocked end

	local passthrough = opts.passthroughModes or CivPathing.PassthroughModes
	local roads       = opts.roadModes       or CivPathing.RoadModes
	local excludeRefs = opts.excludeZoneRefs

	for zid, z in pairs(all) do
		if typeof(z) == "table" and z.gridList and #z.gridList > 0 then
			local mode = z.mode
			local exclude = (opts.excludeZoneIds and opts.excludeZoneIds[zid]) or (excludeRefs and excludeRefs[z] == true)
			local isPass  = mode and passthrough and passthrough[mode]
			local isRoad  = mode and roads and roads[mode]
			local shouldBlock =
				(not exclude) and (not isPass) and
				( (opts.blockAllOtherZones == true) or (opts.blockModes and mode and opts.blockModes[mode] == true) )

			-- NOTE: we do not block road here; we optionally add all roads below to enforce "no crossing roads".
			if shouldBlock and (not isRoad) then
				for _, c in ipairs(z.gridList) do
					blocked[CivPathing.nodeKey(c)] = true
				end
			end
		end
	end

	--optionally block *all* road cells for off-road A*
	if opts.blockRoads == true then
		local roadSet = _buildRoadCellSet(player, opts.roadModes or CivPathing.RoadModes)
		for k,_ in pairs(roadSet) do blocked[k] = true end
	end

	return blocked
end

local function buildZoneCellSet(zone)
	if not zone or not zone.gridList or #zone.gridList == 0 then return nil end
	local set = table.create(#zone.gridList)
	for _, c in ipairs(zone.gridList) do
		set[CivPathing.nodeKey(c)] = true
	end
	return set
end
CivPathing.buildZoneCellSet = buildZoneCellSet

local function trimLeadingZoneCells(path, zoneSet)
	if not (path and zoneSet and next(zoneSet)) then return path end
	local keepIdx = 1
	while keepIdx < #path and zoneSet[CivPathing.nodeKey(path[keepIdx])] do
		keepIdx += 1
	end
	if keepIdx > 1 then
		local trimmed = table.create(#path - keepIdx + 1)
		for i = keepIdx, #path do
			trimmed[#trimmed+1] = path[i]
		end
		return trimmed
	end
	return path
end

local function trimTrailingZoneCells(path, zoneSet)
	if not (path and zoneSet and next(zoneSet)) then return path end
	local keepIdx = #path
	while keepIdx > 1 and zoneSet[CivPathing.nodeKey(path[keepIdx])] do
		keepIdx -= 1
	end
	if keepIdx < #path then
		local trimmed = table.create(keepIdx)
		for i = 1, keepIdx do
			trimmed[#trimmed+1] = path[i]
		end
		return trimmed
	end
	return path
end

-- Basic A* over grid cells (used for the off-road stubs / stumbles).
function CivPathing.findGridPathAvoiding(a, b, opts)
	opts = opts or {}
	local blocked       = opts.blocked or {}
	local allowDiag     = (opts.allowDiagonals ~= nil) and opts.allowDiagonals or CivPathing.AllowDiagonals
	local noCornerCut   = (opts.noCornerCut   ~= nil) and opts.noCornerCut   or CivPathing.NoCornerCutting
	local cap           = opts.maxNodes or CivPathing.AStarMaxNodes
	if blocked[CivPathing.nodeKey(a)] or blocked[CivPathing.nodeKey(b)] then return nil end

	local function moveCost(p, q)
		local dx, dz = math.abs(q.x - p.x), math.abs(q.z - p.z)
		return (dx == 1 and dz == 1) and math.sqrt(2) or 1
	end
	local heuristicWeight = tonumber(opts.heuristicWeight) or CivPathing.AStarHeuristicWeight or 1
	local function h(p, q) return CivPathing.octile(p, q) * heuristicWeight end

	local startK, goalK = CivPathing.nodeKey(a), CivPathing.nodeKey(b)
	local open, inOpen = {}, {}
	local g, f, parent = {}, {}, {}

	local function push(k) table.insert(open, k); inOpen[k] = true end
	local function popLowest()
		local bi, bk, bf = 1, open[1], f[open[1]] or math.huge
		for i=2,#open do
			local kk = open[i]
			local ff = f[kk] or math.huge
			if ff < bf then bi, bk, bf = i, kk, ff end
		end
		table.remove(open, bi)
		inOpen[bk] = nil
		return bk
	end

	g[startK] = 0
	f[startK] = h(a,b)
	push(startK)

	local visited, nodes = {}, 0
	while #open > 0 do
		nodes += 1; if nodes > cap then return nil end

		local currentK = popLowest()
		if currentK == goalK then
			local path = {}
			local k = currentK
			while k do
				local x,z = CivPathing.splitKey(k)
				table.insert(path, 1, {x=x,z=z})
				k = parent[k]
			end
			return path
		end

		visited[currentK] = true
		local cx, cz = CivPathing.splitKey(currentK)
		local current = {x=cx, z=cz}

		for _,nbr in ipairs(_neighborsFiltered(current, blocked, allowDiag, noCornerCut)) do
			local nk = CivPathing.nodeKey(nbr)
			if not visited[nk] then
				local tentative = (g[currentK] or math.huge) + moveCost(current, nbr)
				if tentative < (g[nk] or math.huge) then
					parent[nk] = currentK
					g[nk] = tentative
					f[nk] = tentative + h(nbr, b)
					if not inOpen[nk] then push(nk) end
				end
			end
		end
	end
	return nil
end

function CivPathing.worldPathAvoiding(plot, aGrid, bGrid, opts)
	local gpath = CivPathing.findGridPathAvoiding(aGrid, bGrid, opts or {})
	return gpath and CivPathing.gridPathToWorld(gpath, plot) or nil
end


-- Road-first hybrid: off-road stub → road BFS → off-road stub
----------------------------------------------------------------------
-- 5) Path building helpers
----------------------------------------------------------------------

local function _pickCurbOffset(plot, player, roadPath, stickSign, dstWorldPts)
	-- cell world step (studs)
	local function _cellStepWorld_local(plot)
		local a  = CivPathing.gridToWorld({x=0,z=0}, plot)
		local ax = CivPathing.gridToWorld({x=1,z=0}, plot)
		local az = CivPathing.gridToWorld({x=0,z=1}, plot)
		local dx = (ax - a); dx = Vector3.new(dx.X,0,dx.Z).Magnitude
		local dz = (az - a); dz = Vector3.new(dz.X,0,dz.Z).Magnitude
		if dx > 1e-3 and dz > 1e-3 then return (dx+dz)*0.5 end
		return (dx>1e-3) and dx or ((dz>1e-3) and dz or 4.0)
	end

	-- Build a quick cell->mode index so we can ask "is this cell a road?"
	local function _buildCellModeIndex_local(player)
		local idx, all = {}, ZoneTrackerModule.getAllZones(player)
		if not all then return idx end
		for zid, z in pairs(all) do
			if typeof(z)=="table" and z.gridList then
				for _,c in ipairs(z.gridList) do
					idx[CivPathing.nodeKey(c)] = { id = zid, mode = z.mode }
				end
			end
		end
		return idx
	end

	local cellSize   = _cellStepWorld_local(plot)
	local margin     = tonumber(CivPathing.RoadEdgeMarginStuds) or 0.20
	local cellModes  = _buildCellModeIndex_local(player)
	local roadModes  = CivPathing.RoadModes

	local function _isRoadCell(c)
		local hit = cellModes[CivPathing.nodeKey(c)]
		return hit and hit.mode and (roadModes[hit.mode] == true)
	end

	-- Given a road grid cell and a perpendicular direction (+/-), walk outward until we exit road.
	local function _halfWidthCellsFromCenter(cell, perp)
		local steps = 0
		while true do
			local nextC = { x = cell.x + perp.x * (steps + 1), z = cell.z + perp.z * (steps + 1) }
			if not _isRoadCell(nextC) then break end
			steps += 1
		end
		return steps -- cells from centerline to curb on this side
	end

	-- Return a function that, for each (p,q), emits a world point p shifted to the chosen curb by (halfWidth - margin).
	return function(i, p, q, prevWorld)
		local cell = roadPath[i]  -- {x,z}

		-- Segment direction in world (for perpendicular)
		local dir = q - p
		if dir.Magnitude < 1e-6 then dir = Vector3.new(1,0,0) end
		dir  = dir.Unit
		local sideWorld = dir:Cross(Vector3.new(0,1,0)).Unit

		-- Convert perpendicular world sign into grid +/- X or +/- Z step
		local sx, sz = math.abs(sideWorld.X), math.abs(sideWorld.Z)
		local perpGrid
		if sx >= sz then
			perpGrid = { x = (sideWorld.X >= 0) and 1 or -1, z = 0 }
		else
			perpGrid = { x = 0, z = (sideWorld.Z >= 0) and 1 or -1 }
		end

		-- Measure half-width (in cells) on both sides from the current road cell
		local halfA = _halfWidthCellsFromCenter(cell,  perpGrid)
		local halfB = _halfWidthCellsFromCenter(cell, {x=-perpGrid.x, z=-perpGrid.z})

		-- Choose sticky curb side
		local sign = stickSign
		if not sign then
			local offsetA = math.max(0, (halfA * cellSize) - margin)
			local offsetB = math.max(0, (halfB * cellSize) - margin)
			local candA   = p + sideWorld *  offsetA
			local candB   = p + sideWorld * -offsetB

			if prevWorld then
				sign = ((prevWorld - candA).Magnitude <= (prevWorld - candB).Magnitude) and 1 or -1
			else
				local function nearestZoneDist2(worldPoint)
					local best = math.huge
					for j=1,#dstWorldPts do
						local d = worldPoint - dstWorldPts[j]
						local ds2 = d.X*d.X + d.Z*d.Z
						if ds2 < best then best = ds2 end
					end
					return best
				end
				sign = (nearestZoneDist2(candA) <= nearestZoneDist2(candB)) and 1 or -1
			end
		end

		-- Use the selected side’s half-width
		local halfCells = (sign == 1) and halfA or halfB
		local offset    = math.max(0, (halfCells * cellSize) - margin)
		return p + sideWorld * (offset * sign), sign
	end
end

local function _zoneCentroidGrid(zone)
	if not zone or not zone.gridList or #zone.gridList == 0 then return nil end
	local sx, sz = 0, 0
	for _, c in ipairs(zone.gridList) do sx += c.x; sz += c.z end
	return { x = sx / #zone.gridList, z = sz / #zone.gridList }
end

local function _precomputeZoneWorld(plot, zone)
	if not zone or not zone.gridList or #zone.gridList == 0 then return {} end
	local list = table.create(#zone.gridList)
	for i,c in ipairs(zone.gridList) do list[i] = CivPathing.gridToWorld(c, plot) end
	return list
end

local function _planOffroadStub(player, aCell, bCell, opts)
	return CivPathing.findGridPathAvoiding(aCell, bCell, {
		blocked        = opts.blocked,
		allowDiagonals = opts.allowDiag,
		noCornerCut    = opts.noCornerCut,
		maxNodes       = opts.maxNodes or CivPathing.AStarMaxNodes,
	})
end

-- PUBLIC: expected entry point. Behavior: road-first if graph available.
----------------------------------------------------------------------
-- Full road-first itinerary (origin zone -> road BFS -> destination zone).
function CivPathing.hybridZoneToZonePath(plot, player, srcZone, dstZone, opts)
	opts = opts or {}
	local allowDiag   = (opts.allowDiagonals ~= nil) and opts.allowDiagonals or CivPathing.AllowDiagonals
	local noCornerCut = (opts.noCornerCut   ~= nil) and opts.noCornerCut   or CivPathing.NoCornerCutting
	local roads       = opts.roadModes or CivPathing.RoadModes

	if not srcZone or not dstZone or not srcZone.gridList or not dstZone.gridList
		or #srcZone.gridList == 0 or #dstZone.gridList == 0 then
		return nil
	end

	local srcCellSet = buildZoneCellSet(srcZone)
	local dstCellSet = buildZoneCellSet(dstZone)

	-- Never route *to* a road/passthrough zone as a destination
	if CivPathing.isRoadMode(dstZone.mode) or CivPathing.isPassthroughMode(dstZone.mode) then
		return nil
	end

	-- Build a blocked set for off-road stubs AND block roads so A* can’t cross them.
	local exclude = {
		[srcZone.Id or srcZone.id or srcZone.zoneId or ""] = true,
		[dstZone.Id or dstZone.id or dstZone.zoneId or ""] = true
	}
	local blockedBase = CivPathing.buildBlockedCellsFromZones(player, {
		excludeZoneIds     = exclude,
		blockAllOtherZones = true,
		roadModes          = roads,
		blockRoads         = CivPathing.BlockRoadsInOffroad, -- NEW
	})

	local haveGraph = roadBFS and (adjProvider and adjProvider())

	-- If we’re near a road at the source, force snapping onto it
	local snapR = tonumber(opts.RoadSnapRadiusCells) or CivPathing.RoadSnapRadiusCells or 0
	local startCell = srcZone.gridList[1]
	local entryRoad = nil
	if CivPathing.ForceRoadWhenNear and snapR > 0 then
		entryRoad = _nearestRoadNodeFromCell(startCell, snapR)
	end
	-- Fallback: general nearest road to the zone
	if not entryRoad then
		entryRoad = CivPathing.nearestRoadNodeFromZone(srcZone, opts.SearchRadius or CivPathing.RoadCaptureRadius or 128)
	end

	-- Destination road anchor (nearest road node toward the destination zone)
	local exitRoad  = _nearestRoadNodeToZoneGrowing(dstZone, opts.SearchRadius or CivPathing.RoadCaptureRadius or 128)
	
	-- If graph not available or either side has no road, fall back to off-road-only BUT still forbid crossing roads.
	if not haveGraph or not entryRoad or not exitRoad then
		dprint("Road graph unavailable or endpoints missing; using off-road-only (roads blocked).")
		local a, b = srcZone.gridList[1], dstZone.gridList[1]
		local g = CivPathing.findGridPathAvoiding(a, b, {
			blocked        = blockedBase,
			allowDiagonals = allowDiag,
			noCornerCut    = noCornerCut,
		})
		if not g then return nil end
		g = trimLeadingZoneCells(g, srcCellSet)
		g = trimTrailingZoneCells(g, dstCellSet)
		if not g or #g < 2 then return nil end
		return CivPathing.gridPathToWorld(g, plot)
	end

	-- Off-road stub (src -> entryRoad)
	local aCell = srcZone.gridList[1]
	local blockA = {}
	for k,v in pairs(blockedBase) do blockA[k] = v end
	blockA[CivPathing.nodeKey(entryRoad)] = nil -- allow stepping onto the entry road node
	local pre = _planOffroadStub(player, aCell, entryRoad, {
		blocked  = blockA, allowDiag = allowDiag, noCornerCut = noCornerCut
	}) or { aCell, entryRoad }
	pre = trimLeadingZoneCells(pre, srcCellSet)

	-- Road leg
	local roadPath = roadBFS(entryRoad, exitRoad)
	if not roadPath or #roadPath < 2 then
		dprint("BFS failed; using off-road-only (roads blocked).")
		local a, b = srcZone.gridList[1], dstZone.gridList[1]
		local g = CivPathing.findGridPathAvoiding(a, b, {
			blocked        = blockedBase,
			allowDiagonals = allowDiag,
			noCornerCut    = noCornerCut,
		})
		if not g then return nil end
		g = trimLeadingZoneCells(g, srcCellSet)
		g = trimTrailingZoneCells(g, dstCellSet)
		if not g or #g < 2 then return nil end
		return CivPathing.gridPathToWorld(g, plot)
	end

	-- Off-road stub (exitRoad -> dst)
	local bCell = dstZone.gridList[1]
	local blockB = {}
	for k,v in pairs(blockedBase) do blockB[k] = v end
	blockB[CivPathing.nodeKey(exitRoad)] = nil -- allow stepping off the road node
	local tail = _planOffroadStub(player, exitRoad, bCell, {
		blocked  = blockB, allowDiag = allowDiag, noCornerCut = noCornerCut
	}) or { exitRoad, bCell }
	tail = trimTrailingZoneCells(tail, dstCellSet)

	-- Assemble as WORLD path with sticky curb offset for road leg
	local world = {}

	-- 1) pre (off-road) world
	if #pre > 0 then
		for i=1,#pre do world[#world+1] = CivPathing.gridToWorld(pre[i], plot) end
	end
	local prevWorld = (#world > 0) and world[#world] or nil

	-- 2) road leg with sticky curb
	local dstWorldPts = _precomputeZoneWorld(plot, dstZone)
	local offsetFn = _pickCurbOffset(plot, player, roadPath, nil, dstWorldPts)
	local stickySign = nil
	for i=1,#roadPath do
		local p  = CivPathing.gridToWorld(roadPath[i], plot)
		local q  = CivPathing.gridToWorld(roadPath[math.min(i+1, #roadPath)], plot)
		if i == #roadPath and #roadPath > 1 then q = CivPathing.gridToWorld(roadPath[i-1], plot) end
		local pOff, sign = offsetFn(i, p, q, prevWorld)
		if CivPathing.StickyCurb and not stickySign then stickySign = sign end
		-- lock sign after first decision
		offsetFn = _pickCurbOffset(plot, player, roadPath, stickySign, dstWorldPts) -- FIX: pass player
		world[#world+1] = pOff
		prevWorld = pOff
	end

	-- 3) tail (off-road) world
	if #tail > 0 then
		for i=1,#tail do world[#world+1] = CivPathing.gridToWorld(tail[i], plot) end
	end

	return world
end

-- Optional helper: if a civ *steps onto a road*, swap to road-first plan immediately.
function CivPathing.replanIfOnRoad(plot, player, currentCell, dstZone, opts)
	if not dstZone or not currentCell then return nil end
	if not (roadBFS and (adjProvider and adjProvider())) then return nil end

	local dstCellSet = buildZoneCellSet(dstZone)
	local cellModes = _buildCellModeIndex(player)
	local key = CivPathing.nodeKey(currentCell)
	local isRoad = _isRoadCellKey(key, cellModes, opts and opts.roadModes or CivPathing.RoadModes)
	if not isRoad then
		-- try to capture if *near* a road
		local near = _nearestRoadNodeFromCell(
			currentCell,
			(opts and (opts.RoadSnapRadiusCells or opts.SearchRadius))
				or CivPathing.RoadSnapRadiusCells
				or CivPathing.RoadCaptureRadius
				or 128
		)
		if not near then return nil end
		currentCell = near
	end

	local exitRoad  = _nearestRoadNodeToZoneGrowing(dstZone, opts and opts.SearchRadius or CivPathing.RoadCaptureRadius or 128)
	if not exitRoad then return nil end

	-- road BFS
	local roadPath = roadBFS(currentCell, exitRoad)
	if not roadPath or #roadPath < 2 then return nil end

	-- tail off-road (roads blocked)
	local blocked = CivPathing.buildBlockedCellsFromZones(player, {
		excludeZoneIds     = { [dstZone.Id or dstZone.id or dstZone.zoneId or ""] = true },
		blockAllOtherZones = true,
		blockRoads         = CivPathing.BlockRoadsInOffroad,
	})
	blocked[CivPathing.nodeKey(exitRoad)] = nil

	local bCell = dstZone.gridList[1]
	local tail = CivPathing.findGridPathAvoiding(exitRoad, bCell, {
		blocked  = blocked, allowDiagonals = CivPathing.AllowDiagonals, noCornerCut = CivPathing.NoCornerCutting
	}) or { exitRoad, bCell }
	tail = trimTrailingZoneCells(tail, dstCellSet)

	-- Assemble world with curb offset on the road leg only
	local world = {}
	local dstWorldPts = _precomputeZoneWorld(plot, dstZone)
	local offsetFn = _pickCurbOffset(plot, player, roadPath, nil, dstWorldPts)
	local stickySign = nil
	local prevWorld = nil
	for i=1,#roadPath do
		local p  = CivPathing.gridToWorld(roadPath[i], plot)
		local q  = CivPathing.gridToWorld(roadPath[math.min(i+1, #roadPath)], plot)
		if i == #roadPath and #roadPath > 1 then q = CivPathing.gridToWorld(roadPath[i-1], plot) end
		local pOff, sign = offsetFn(i, p, q, prevWorld)
		if CivPathing.StickyCurb and not stickySign then stickySign = sign end
		offsetFn = _pickCurbOffset(plot, player, roadPath, stickySign, dstWorldPts) -- FIX: pass player
		world[#world+1] = pOff
		prevWorld = pOff
	end
	for i=1,#tail do world[#world+1] = CivPathing.gridToWorld(tail[i], plot) end
	return world
end

----------------------------------------------------------------------
-- Public API export
----------------------------------------------------------------------

return CivPathing
