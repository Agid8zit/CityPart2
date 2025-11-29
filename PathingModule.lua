local PathingModule = {}
PathingModule.__index = PathingModule

local ZoneTrackerModule = require(game.ServerScriptService.Build.Zones.ZoneManager.ZoneTracker)
local GridConfig = require(game.ReplicatedStorage.Scripts.Grid.GridConfig)
local GridUtil = require(game.ReplicatedStorage.Scripts.Grid.GridUtil)

-- ===================== CONFIG =====================
-- How should parallel, colinear roads from different groups stitch together?
--   "never"     -> never stitch parallel/colinear (hard shield)
--   "endpoints" -> stitch only when BOTH sides are endpoints (default)
--   "anywhere"  -> stitch at any node (the relaxed behavior that caused the regression)
local PARALLEL_CONNECT_POLICY = "endpoints"
-- ==================================================

-- Debug flag + helpers
local DEBUG = false
local function dprint(...) if DEBUG then print(...) end end
local function dwarn(...)  if DEBUG then warn(...)  end end

-- We'll store zone data in 'roadNetworks'
-- Also store per-owner adjacency; `globalAdjacency` is a union view rebuilt from owner buckets.
PathingModule.globalAdjacency = {}

-- Owner-scoped state
local adjacencyByOwner = {}            -- [ownerKey] = { [nodeKey] = { neighborKey, ... } }
local nodeMetaByOwner  = {}            -- [ownerKey] = { [nodeKey] = meta }
PathingModule.nodeMeta = nodeMetaByOwner

local roadNetworks = {}                -- [zoneId] = { owner=<ownerKey>, ... }
local globalAdjacency = PathingModule.globalAdjacency  -- union view (read-only for consumers)

-- Road Parallel helpers
local function insertUnique(t, v)
	for i = 1, #t do if t[i] == v then return t end end
	table.insert(t, v)
	return t
end
local function addEdge(adj, aKey, bKey)
	if not adj then return end
	adj[aKey] = insertUnique(adj[aKey] or {}, bKey)
	adj[bKey] = insertUnique(adj[bKey] or {}, aKey)
end

-- Helpers to normalize an owner key (Player | userId | string)
local function ownerKey(owner)
	if typeof(owner) == "Instance" and owner:IsA("Player") then
		return tostring(owner.UserId)
	end
	local n = tonumber(owner)
	if n then return tostring(n) end
	return owner and tostring(owner) or "global"
end

local function getAdjacency(owner, create)
	local key = ownerKey(owner)
	local bucket = adjacencyByOwner[key]
	if not bucket and create then
		bucket = {}
		adjacencyByOwner[key] = bucket
	end
	return bucket, key
end

local function getNodeMeta(owner, create)
	local key = ownerKey(owner)
	local bucket = nodeMetaByOwner[key]
	if not bucket and create then
		bucket = {}
		nodeMetaByOwner[key] = bucket
	end
	return bucket, key
end

local function rebuildAdjacencyUnion()
	local newUnion = {}
	for _, adj in pairs(adjacencyByOwner) do
		for nodeKeyStr, neighbors in pairs(adj) do
			local dest = newUnion[nodeKeyStr]
			if not dest then
				dest = {}
				newUnion[nodeKeyStr] = dest
			end
			for _, nb in ipairs(neighbors) do
				insertUnique(dest, nb)
			end
		end
	end
	globalAdjacency = newUnion
	PathingModule.globalAdjacency = globalAdjacency
end

-- Public: cache of owned endpoints (dead-ends) by userId (rebuilt on demand)
PathingModule._ownedDeadEndsCache = {}  -- [userId] = { ["x_z"]=true, ... }

-- HELPER: directionAngles, nearestDirection, etc.
local directionAngles = {
	North      = 270,
	NorthEast  = 315,
	East       = 0,
	SouthEast  = 45,
	South      = 90,
	SouthWest  = 135,
	West       = 180,
	NorthWest  = 225
}
local function getNearestDirection(angle)
	local minDiff = 360
	local nearestDirection = "Undefined"
	for direction, dirAngle in pairs(directionAngles) do
		local diff = math.abs(angle - dirAngle)
		if diff > 180 then diff = 360 - diff end
		if diff < minDiff then
			minDiff = diff
			nearestDirection = direction
		end
	end
	return nearestDirection
end
local function getRoadDirection(coord1, coord2)
	local dx = coord2.x - coord1.x
	local dz = coord2.z - coord1.z
	if dx == 0 and dz == 0 then return "Undefined" end
	local angle = math.deg(math.atan2(dz, dx))
	if angle < 0 then angle = angle + 360 end
	return getNearestDirection(angle)
end
local function getAngleBetweenCoords(c1, c2)
	local dx = c2.x - c1.x
	local dz = c2.z - c1.z
	if dx == 0 and dz == 0 then return -1 end
	local angle = math.deg(math.atan2(dz, dx))
	if angle < 0 then angle = angle + 360 end
	return angle
end

-- HELPER: nodeKey => store coords in a dictionary like "x_z"
local function nodeKey(coord)
	return tostring(coord.x) .. "_" .. tostring(coord.z)
end
local function splitKey(k)
	local xz = string.split(k, "_")
	local x = tonumber(xz[1])
	local z = tonumber(xz[2])
	return x, z
end

-- HELPER: Are two cells immediate neighbors? (dx=1,dz=0 or dx=0,dz=1)
local function areNeighbors(c1, c2)
	local dx = math.abs(c1.x - c2.x)
	local dz = math.abs(c1.z - c2.z)
	return (dx == 1 and dz == 0) or (dx == 0 and dz == 1)
end

-- Axis helpers for “parallel shielding”
local function axisOfStep(a, b)
	-- EW if x changes, NS if z changes (roads are ortho)
	if a.x ~= b.x then return "EW" else return "NS" end
end
local function axisOfCell(list, i)
	if list[i + 1] then return axisOfStep(list[i], list[i + 1]) end
	if list[i - 1] then return axisOfStep(list[i - 1], list[i]) end
	return "EW" -- default for singletons
end
local function isLateralNeighbor(axis, dx, dz)
	-- For an EW segment, lateral neighbors are up/down (dz≠0).
	-- For an NS segment, lateral neighbors are left/right (dx≠0).
	return (axis == "EW" and dz ~= 0) or (axis == "NS" and dx ~= 0)
end

-- NEW: policy gate for parallel stitching (colinear)
local function shouldConnectParallel(eMeta, nMeta)
	if PARALLEL_CONNECT_POLICY == "anywhere" then
		return true
	elseif PARALLEL_CONNECT_POLICY == "endpoints" then
		return (eMeta.role == "End") and (nMeta.role == "End")
	else -- "never"
		return false
	end
end

-- NEW: allow **lateral** stitches between parallel roads *only at endpoints*.
-- This is the key fix: let endpoints form Turns/3-Ways with a side-by-side neighbor.
local function shouldConnectLateralAtEndpoints(eMeta, nMeta)
	-- If caller sets policy to "never", respect it fully (no lateral even at endpoints).
	if PARALLEL_CONNECT_POLICY == "never" then return false end
	return (eMeta.role == "End") or (nMeta.role == "End")
end

-- NEW: fillLineBetweenCoords (ensures no skipped cells along straight segments)
local function fillLineBetweenCoords(coords)
	if #coords < 2 then return coords end
	local fullList = {}
	table.insert(fullList, coords[1])
	for i = 1, (#coords - 1) do
		local c1 = coords[i]
		local c2 = coords[i+1]
		if c1.z == c2.z then
			local z = c1.z
			local step = (c2.x > c1.x) and 1 or -1
			for x = c1.x + step, c2.x, step do
				table.insert(fullList, { x = x, z = z })
			end
		elseif c1.x == c2.x then
			local x = c1.x
			local step = (c2.z > c1.z) and 1 or -1
			for z = c1.z + step, c2.z, step do
				table.insert(fullList, { x = x, z = z })
			end
		else
			-- Only orthogonal roads supported; keep c2 to avoid gaps but won’t fill diagonals
			table.insert(fullList, c2)
		end
	end
	return fullList
end

-- INTERNAL: addToNetwork
-- Merges new road cells into adjacency for BFS. Stitching policy:
--   * PERPENDICULAR: allow anywhere
--   * PARALLEL colinear: policy gate (see shouldConnectParallel)
--   * PARALLEL lateral: **allow only at endpoints** (see shouldConnectLateralAtEndpoints)
local function addToNetwork(zoneId, roadCoords, owner)
	dprint(string.format("[PathingModule] Adding road segments for Road ID '%s'", zoneId))
	local adj, ownerKeyStr = getAdjacency(owner, true)
	local meta = select(1, getNodeMeta(ownerKeyStr, true))

	-- Build or update the per-road record
	local network = roadNetworks[zoneId]
	if not network then
		network = {
			id = zoneId,
			segments = {},
			overallDirection = "Undefined",
			startCoord = nil,
			endCoord = nil
		}
		roadNetworks[zoneId] = network
	else
		network.segments = {}
	end

	-- Build 'segments'
	for i = 1, #roadCoords - 1 do
		local direction = getRoadDirection(roadCoords[i], roadCoords[i + 1])
		table.insert(network.segments, { coord = roadCoords[i], direction = direction })
	end
	if #roadCoords > 0 then
		table.insert(network.segments, { coord = roadCoords[#roadCoords], direction = "End" })
		network.startCoord = roadCoords[1]
		network.endCoord   = roadCoords[#roadCoords]
	end

	-- Ensure nodes exist + write metadata (axis, role, group)
	for i, c in ipairs(roadCoords) do
		local k = nodeKey(c)
		if adj and not adj[k] then adj[k] = {} end
		local role = (i == 1 or i == #roadCoords) and "End" or "Mid"
		local axis = axisOfCell(roadCoords, i)
		meta[k] = { groupId = zoneId, axis = axis, role = role }
	end

	-- Connect consecutive cells inside this path
	for i = 1, #roadCoords - 1 do
		addEdge(adj, nodeKey(roadCoords[i]), nodeKey(roadCoords[i + 1]))
	end

	-- STITCH: to OTHER paths around every node
	for i, e in ipairs(roadCoords) do
		local eKey  = nodeKey(e)
		local eMeta = meta[eKey]
		local candidates = {
			{ x = e.x + 1, z = e.z     },
			{ x = e.x - 1, z = e.z     },
			{ x = e.x,     z = e.z + 1 },
			{ x = e.x,     z = e.z - 1 },
		}
		for _, n in ipairs(candidates) do
			local nKey  = nodeKey(n)
			local nAdj  = adj and adj[nKey] or nil
			local nMeta = meta[nKey]
			if nAdj and nMeta and nMeta.groupId ~= eMeta.groupId then
				local dx, dz = n.x - e.x, n.z - e.z
				local axesParallel = (nMeta.axis == eMeta.axis)

				if not axesParallel then
					-- Perpendicular => allow T/4-way joins anywhere
					addEdge(adj, eKey, nKey)
				else
					-- Parallel
					local lateral = isLateralNeighbor(eMeta.axis, dx, dz)
					if lateral then
						-- NEW: allow lateral stitches ONLY at endpoints (one side or both)
						if shouldConnectLateralAtEndpoints(eMeta, nMeta) then
							addEdge(adj, eKey, nKey)
						end
					else
						-- Colinear: policy gate
						if shouldConnectParallel(eMeta, nMeta) then
							addEdge(adj, eKey, nKey)
						end
					end
				end
			end
		end
	end

	-- invalidate owned endpoints cache (graph changed)
	PathingModule._ownedDeadEndsCache[ownerKeyStr] = nil
end

-- classifyNode: is it Straight, Turn, 3Way, 4Way, etc.?
function PathingModule.classifyNode(coord, owner)
	local k = nodeKey(coord)
	local adj = getAdjacency(owner, false) or globalAdjacency
	local neighbors = adj and adj[k]
	if not neighbors or #neighbors == 0 then return "None" end

	local upKey = nodeKey({ x = coord.x,     z = coord.z - 1 })
	local dnKey = nodeKey({ x = coord.x,     z = coord.z + 1 })
	local ltKey = nodeKey({ x = coord.x - 1, z = coord.z })
	local rtKey = nodeKey({ x = coord.x + 1, z = coord.z })

	local up = table.find(neighbors, upKey) ~= nil
	local dn = table.find(neighbors, dnKey) ~= nil
	local lt = table.find(neighbors, ltKey) ~= nil
	local rt = table.find(neighbors, rtKey) ~= nil

	local count = 0
	if up then count += 1 end
	if dn then count += 1 end
	if lt then count += 1 end
	if rt then count += 1 end

	if count == 0 then
		return "None"
	elseif count == 1 then
		return "DeadEnd"
	elseif count == 2 then
		if (up and dn) or (lt and rt) then
			return "Straight"
		else
			return "Turn"
		end
	elseif count == 3 then
		return "3Way"
	elseif count == 4 then
		return "4Way"
	end
	return "None"
end

function PathingModule.determineOverallDirection(startCoord, endCoord)
	if not startCoord or not endCoord then
		error("[PathingModule] startCoord or endCoord is nil")
	end
	local dx = endCoord.x - startCoord.x
	local dz = endCoord.z - startCoord.z
	if dx == 0 and dz == 0 then return "Undefined" end
	local angle = math.deg(math.atan2(dz, dx))
	if angle < 0 then angle = angle + 360 end
	return getNearestDirection(angle)
end

--=== NEW PUBLIC HELPERS: endpoints & proximity ===--

local function nodeOwnedByPlayer(player, key)
	local metaBucket = select(1, getNodeMeta(player, false))
	local meta = metaBucket and metaBucket[key]
	if not meta then return false end
	local zid = meta.groupId
	if not zid then return false end
	local z = ZoneTrackerModule.getZoneById(player, zid)
	return z ~= nil
end

-- Returns a set of dead-end nodeKeys owned by player. Cached per userId.
function PathingModule.getOwnedDeadEndKeys(player)
	if not player then return {} end
	local uid = ownerKey(player)
	local cached = PathingModule._ownedDeadEndsCache[uid]
	if cached then return cached end
	local adj = select(1, getAdjacency(player, false))
	if not adj then return {} end
	local set = {}
	for k, nbrs in pairs(adj) do
		if nodeOwnedByPlayer(player, k) then
			if nbrs and #nbrs == 1 then
				set[k] = true
			end
		end
	end
	PathingModule._ownedDeadEndsCache[uid] = set
	return set
end

-- Convenience: return list of coords for owned dead-ends
function PathingModule.getOwnedDeadEnds(player)
	local out = {}
	for k,_ in pairs(PathingModule.getOwnedDeadEndKeys(player)) do
		local x, z = splitKey(k)
		table.insert(out, { x = x, z = z })
	end
	return out
end

-- Iterate all road nodes (coords)
function PathingModule.iterAllRoadCoords(owner)
	local list = {}
	local adj = getAdjacency(owner, false) or globalAdjacency
	for k,_ in pairs(adj) do
		local x, z = splitKey(k)
		list[#list+1] = { x = x, z = z, key = k }
	end
	return list
end

-- Find nearest road node to a given grid coord within maxManhattan (cells). Returns coord or nil.
function PathingModule.findNearestRoadNode(coord, maxManhattan, owner)
	local best, bestD = nil, math.huge
	local adj = getAdjacency(owner, false) or globalAdjacency
	for k,_ in pairs(adj) do
		local x, z = splitKey(k)
		local d = math.abs(x - coord.x) + math.abs(z - coord.z)
		if d < bestD and d <= maxManhattan then
			bestD = d
			best = { x = x, z = z, key = k }
		end
	end
	return best
end

-- NEW: pass to add lateral stitches at endpoints across ALL currently known networks.
-- Useful after loading old saves or toggling policy.
function PathingModule.stitchEndpointLaterals(owner)
	local function stitchBucket(adj, meta)
		for eKey, _ in pairs(adj or {}) do
			local eMeta = meta and meta[eKey]
			if eMeta then
				local ex, ez = splitKey(eKey)
				local candidates
				if eMeta.axis == "EW" then
					candidates = {
						{ x = ex, z = ez - 1 },
						{ x = ex, z = ez + 1 },
					}
				else -- "NS"
					candidates = {
						{ x = ex - 1, z = ez },
						{ x = ex + 1, z = ez },
					}
				end
				for _, n in ipairs(candidates) do
					local nKey  = nodeKey(n)
					local nMeta = meta and meta[nKey]
					-- Only stitch to another group; require same axis (parallel) and endpoint on either side
					if nMeta and nMeta.groupId ~= eMeta.groupId and nMeta.axis == eMeta.axis then
						if shouldConnectLateralAtEndpoints(eMeta, nMeta) then
							addEdge(adj, eKey, nKey)
						end
					end
				end
			end
		end
	end
	if owner ~= nil then
		local adj = select(1, getAdjacency(owner, false))
		local meta = select(1, getNodeMeta(owner, false))
		if adj and meta then stitchBucket(adj, meta) end
		PathingModule._ownedDeadEndsCache[ownerKey(owner)] = nil
	else
		for ownerKeyStr, adj in pairs(adjacencyByOwner) do
			local meta = nodeMetaByOwner[ownerKeyStr]
			if adj and meta then stitchBucket(adj, meta) end
			PathingModule._ownedDeadEndsCache[ownerKeyStr] = nil
		end
	end
	rebuildAdjacencyUnion()
end

-- MAIN ENTRY: we fill missing cells, then add to adjacency, then store direction.
function PathingModule.registerRoad(zoneId, mode, gridCoords, startCoord, endCoord, owner)
	dprint(string.format("[PathingModule] Registering road '%s' of type '%s' with grid coordinates:", zoneId, mode))
	-- for _, coord in ipairs(gridCoords) do dprint(string.format("[PathingModule] (%d,%d)", coord.x, coord.z)) end

	local filledCoords = fillLineBetweenCoords(gridCoords)
	addToNetwork(zoneId, filledCoords, owner)

	-- NEW: after adding this network, stitch endpoint laterals globally so
	-- endpoints next to side-by-side roads become connected.
	PathingModule.stitchEndpointLaterals(owner)

	local overallDirection = PathingModule.determineOverallDirection(startCoord, endCoord)
	dprint(string.format("[PathingModule] Road '%s' is built in direction: %s", zoneId, overallDirection))

	local network = roadNetworks[zoneId]
	if network then
		network.overallDirection = overallDirection
		network.startCoord = startCoord
		network.endCoord   = endCoord
		network.owner      = ownerKey(owner)
		dprint(string.format("[PathingModule] Stored direction '%s' + start/end for '%s'.", overallDirection, zoneId))
	else
		dwarn(string.format("[PathingModule] Could not update network for road '%s'.", zoneId))
	end
	rebuildAdjacencyUnion()
end

function PathingModule.unregisterRoad(zoneId, owner)
	local network = roadNetworks[zoneId]
	local ownerKeyStr = ownerKey(owner or (network and network.owner))
	local adj = select(1, getAdjacency(ownerKeyStr, false)) or select(1, getAdjacency("global", false))
	local meta = select(1, getNodeMeta(ownerKeyStr, false)) or select(1, getNodeMeta("global", false))
	if network then
		if network.segments and adj then
			for _, seg in ipairs(network.segments) do
				local k = nodeKey(seg.coord)
				if adj[k] then
					for _, neighborKey in ipairs(adj[k]) do
						if adj[neighborKey] then
							local newList = {}
							for _, item in ipairs(adj[neighborKey]) do
								if item ~= k then table.insert(newList, item) end
							end
							adj[neighborKey] = newList
						end
					end
					adj[k] = nil
				end
				if meta then meta[k] = nil end
			end
		end
		roadNetworks[zoneId] = nil
	else
		dwarn(string.format("[PathingModule] Attempted to unregister non-existent road '%s'.", zoneId))
	end
	-- graph changed: drop caches
	PathingModule._ownedDeadEndsCache[ownerKeyStr] = nil
	rebuildAdjacencyUnion()
end

-- BFS & other helpers
function PathingModule.getRoadNetworks() return roadNetworks end

function PathingModule.bfsFindPathGlobal(startCoord, endCoord)
	local function reconstructPath(parent, current)
		local pathKeys = {}
		local cursor = current
		while cursor do
			table.insert(pathKeys, 1, cursor)
			cursor = parent[cursor]
		end
		local path = {}
		for _, k in ipairs(pathKeys) do
			local x, z = splitKey(k)
			table.insert(path, { x = x, z = z })
		end
		return path
	end

	local startKey = nodeKey(startCoord)
	local endKey   = nodeKey(endCoord)
	if not globalAdjacency[startKey] then
		dwarn("bfsFindPathGlobal: startCoord not in adjacency. No road covers it?")
		return nil
	end
	if not globalAdjacency[endKey] then
		dwarn("bfsFindPathGlobal: endCoord not in adjacency. No road covers it?")
		return nil
	end

	local queue = { startKey }
	local visited = { [startKey] = true }
	local parent = {}

	while #queue > 0 do
		local current = table.remove(queue, 1)
		if current == endKey then
			return reconstructPath(parent, current)
		end
		local neighbors = globalAdjacency[current]
		if neighbors then
			for _, nbrKey in ipairs(neighbors) do
				if not visited[nbrKey] then
					visited[nbrKey] = true
					parent[nbrKey] = current
					table.insert(queue, nbrKey)
				end
			end
		end
	end

	return nil
end

function PathingModule.findFarthestNode(startCoord)
	local startKey = nodeKey(startCoord)
	if not globalAdjacency[startKey] then
		dwarn("findFarthestNode: startCoord not in adjacency. Possibly no road covers it?")
		return nil
	end

	local queue = { startKey }
	local visited = { [startKey] = true }
	local lastKey = startKey

	while #queue > 0 do
		local current = table.remove(queue, 1)
		lastKey = current
		local neighbors = globalAdjacency[current]
		if neighbors then
			for _, nbrKey in ipairs(neighbors) do
				if not visited[nbrKey] then
					visited[nbrKey] = true
					table.insert(queue, nbrKey)
				end
			end
		end
	end

	return lastKey
end

function PathingModule.getConnectedRoads(coord)
	local connectedRoads = {}
	local k = nodeKey(coord)
	local nbrs = globalAdjacency[k]
	if nbrs then
		for _, neighborKey in ipairs(nbrs) do
			local x, z = splitKey(neighborKey)
			for _, network in pairs(roadNetworks) do
				if network.startCoord and network.startCoord.x == x and network.startCoord.z == z then
					table.insert(connectedRoads, network)
				elseif network.endCoord and network.endCoord.x == x and network.endCoord.z == z then
					table.insert(connectedRoads, network)
				end
			end
		end
	end
	return connectedRoads
end

function PathingModule.reset()
	adjacencyByOwner = {}
	nodeMetaByOwner  = {}
	PathingModule.nodeMeta = nodeMetaByOwner
	PathingModule.globalAdjacency = {}
	globalAdjacency = PathingModule.globalAdjacency
	roadNetworks = {}
	PathingModule._ownedDeadEndsCache = {}
end

function PathingModule.resetForPlayer(owner)
	local key = ownerKey(owner)
	adjacencyByOwner[key] = nil
	nodeMetaByOwner[key]  = nil
	PathingModule._ownedDeadEndsCache[key] = nil
	for zid, net in pairs(roadNetworks) do
		if net and (net.owner == key or (net.id and tostring(net.id):find(key))) then
			roadNetworks[zid] = nil
		end
	end
	rebuildAdjacencyUnion()
end

function PathingModule.getAdjacencyForOwner(owner)
	return select(1, getAdjacency(owner, false))
end

function PathingModule.getNodeMetaForOwner(owner)
	return select(1, getNodeMeta(owner, false))
end

PathingModule.nodeKey           = nodeKey
PathingModule.directionAngles   = directionAngles
PathingModule.getRoadDirection  = getRoadDirection

return PathingModule
