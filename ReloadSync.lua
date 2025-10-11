local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BE = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents")

-- Match your tree exactly (from the code you posted):
local ZoneTracker = require(ServerScriptService.Build.Zones.ZoneManager.ZoneTracker)
local PathingModule = require(ServerScriptService.Build.Transport.Roads.CoreConcepts.Pathing.PathingModule)

----------------------------------------------------------------------
-- Utilities
----------------------------------------------------------------------
local function isRoadMode(m)
	return m == "DirtRoad" or m == "Pavement" or m == "Highway"
end

local function keyXZ(x, z) return tostring(x).."_"..tostring(z) end

-- Build a 4-way adjacency for the tiles in this zone (dedup included)
-- Returns:
--   nodesList   : array of keys ( "x_z" )
--   nodesSet    : set of keys -> true
--   adj         : key -> { neighborKey, ... } (within this zone only)
--   degree      : key -> integer degree
local function buildAdjacency(gridList)
	local nodesSet, nodesList = {}, {}

	-- dedupe + pack
	for _, c in ipairs(gridList or {}) do
		if typeof(c) == "table" and typeof(c.x) == "number" and typeof(c.z) == "number" then
			local k = keyXZ(c.x, c.z)
			if not nodesSet[k] then
				nodesSet[k] = { x = c.x, z = c.z }
				table.insert(nodesList, k)
			end
		end
	end

	local adj, degree = {}, {}
	for _, k in ipairs(nodesList) do
		adj[k] = {}
		degree[k] = 0
	end

	-- 4-way neighbors
	local offsets = { {1,0}, {-1,0}, {0,1}, {0,-1} }
	for _, k in ipairs(nodesList) do
		local c = nodesSet[k]
		for _, o in ipairs(offsets) do
			local nx, nz = c.x + o[1], c.z + o[2]
			local nk = keyXZ(nx, nz)
			if nodesSet[nk] then
				table.insert(adj[k], nk)
				degree[k] += 1
			end
		end
	end

	return nodesList, nodesSet, adj, degree
end

-- BFS that stays inside the given adjacency; returns parent map and farthest key
local function bfsFrom(adj, startKey)
	local parent, dist = {}, {}
	local q = { startKey }
	parent[startKey] = false
	dist[startKey] = 0
	local head = 1
	local last = startKey

	while q[head] do
		local cur = q[head]; head += 1
		last = cur
		local nbrs = adj[cur]
		if nbrs then
			for i = 1, #nbrs do
				local nb = nbrs[i]
				if dist[nb] == nil then
					dist[nb] = dist[cur] + 1
					parent[nb] = cur
					q[#q+1] = nb
				end
			end
		end
	end

	-- find farthest visited
	local far = startKey
	local farD = -1
	for k, d in pairs(dist) do
		if d > farD then
			farD = d
			far = k
		end
	end
	return parent, dist, far
end

-- Reconstruct path keys from parent map
local function reconstructPath(parent, endKey)
	local keys = {}
	local k = endKey
	while k do
		table.insert(keys, 1, k)
		k = parent[k]
		if k == false then break end
	end
	return keys
end

-- Choose a good pair of endpoints:
--  1) Prefer true endpoints (deg==1). Use double‑sweep to get farthest pair among them.
--  2) If no endpoints (loop), double‑sweep from an arbitrary node to approximate diameter.
local function chooseEndpoints(nodesList, degree, adj)
	if #nodesList == 0 then return nil, nil end

	-- collect degree-1 nodes
	local endpoints = {}
	for _, k in ipairs(nodesList) do
		if (degree[k] or 0) == 1 then
			table.insert(endpoints, k)
		end
	end

	if #endpoints >= 2 then
		-- double sweep among endpoints
		local any = endpoints[1]
		local _, _, far1 = bfsFrom(adj, any)
		local p2, _, far2 = bfsFrom(adj, far1)
		-- Make sure far2 is reachable path from far1
		local pathKeys = reconstructPath(p2, far2)
		if #pathKeys >= 2 then
			return far1, far2
		end
		-- fallback to first two endpoints
		return endpoints[1], endpoints[2]
	end

	-- No deg-1 (likely a loop); pick approximate diameter by double sweep
	local seed = nodesList[1]
	local _, _, farA = bfsFrom(adj, seed)
	local _, _, farB = bfsFrom(adj, farA)
	if farA ~= farB then
		return farA, farB
	end
	-- fallback: any two distinct nodes if possible
	for i = 2, #nodesList do
		if nodesList[i] ~= nodesList[1] then
			return nodesList[1], nodesList[i]
		end
	end
	return nodesList[1], nodesList[1] -- single tile edge-case
end

-- Order the unordered gridList into a polyline:
-- Returns (orderedCoords, startCoord, endCoord)
local function orderGridListAsPolyline(gridList)
	local nodesList, nodesSet, adj, degree = buildAdjacency(gridList)
	if #nodesList <= 1 then
		-- trivial
		local only = nodesList[1]
		if not only then return {}, nil, nil end
		local c = nodesSet[only]
		return { {x=c.x, z=c.z} }, {x=c.x, z=c.z}, {x=c.x, z=c.z}
	end

	local startKey, endKey = chooseEndpoints(nodesList, degree, adj)
	if not startKey or not endKey then
		return {}, nil, nil
	end

	-- BFS path between chosen endpoints
	local pmap = bfsFrom(adj, startKey)
	-- bfsFrom returns (parent, dist, far) when destructured; here we only need parent:
	local parent = pmap
	local pathKeys = reconstructPath(parent, endKey)

	-- Sanity: if we didn't include all tiles, it means the zone was branched.
	-- That's okay; we prioritize a simple path (what registerRoad expects).
	if #pathKeys < #nodesList then
		warn(("[RoadGraphReloadSync] Zone has branches/loops; using longest simple path (%d/%d tiles).")
			:format(#pathKeys, #nodesList))
	end

	-- Convert to coords
	local ordered, sCoord, eCoord = {}, nil, nil
	for i = 1, #pathKeys do
		local k = pathKeys[i]
		local c = nodesSet[k]
		ordered[i] = { x = c.x, z = c.z }
		if i == 1 then sCoord = { x = c.x, z = c.z } end
		if i == #pathKeys then eCoord = { x = c.x, z = c.z } end
	end
	return ordered, sCoord, eCoord
end

----------------------------------------------------------------------
-- Rebuild routine (per player)
----------------------------------------------------------------------
local function rebuildRoadGraphForPlayer(player)
	local zones = ZoneTracker.getAllZones(player)
	if not zones then return end

	for zoneId, z in pairs(zones) do
		if isRoadMode(z.mode) and type(z.gridList) == "table" and #z.gridList > 0 then
			-- Produce an ordered polyline from ZoneTracker's unordered tiles
			local ordered, startCoord, endCoord = orderGridListAsPolyline(z.gridList)
			if not ordered or #ordered == 0 or not startCoord or not endCoord then
				warn(("[RoadGraphReloadSync] Skipping road %s – unable to order coords."):format(zoneId))
			else
				-- Drop any stale edges for this road id, then re-register cleanly
				pcall(PathingModule.unregisterRoad, zoneId)
				local ok, err = pcall(function()
					PathingModule.registerRoad(zoneId, z.mode, ordered, startCoord, endCoord)
				end)
				if not ok then
					warn(("[RoadGraphReloadSync] registerRoad failed for %s: %s"):format(zoneId, tostring(err)))
				else
					-- Helpful trace (you can comment this out once stable)
					print(("[RoadGraphReloadSync] Rebound road %-20s tiles=%-3d pathLen=%-3d start=(%d,%d) end=(%d,%d)")
						:format(zoneId, #z.gridList, #ordered, startCoord.x, startCoord.z, endCoord.x, endCoord.z))
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- Event wiring
----------------------------------------------------------------------
local NetworksPostLoad = BE:FindFirstChild("NetworksPostLoad")

local function attach(ev)
	if ev and ev.IsA and ev:IsA("BindableEvent") then
		ev.Event:Connect(function(player)
			-- After SaveManager finishes (zones recreated + visuals), rebuild the logical graph:
			rebuildRoadGraphForPlayer(player)
			-- Your UnifiedTraffic listens to NetworksPostLoad and will recompute its sinks on unsuspend.
		end)
	end
end

if NetworksPostLoad then
	attach(NetworksPostLoad)
else
	BE.ChildAdded:Connect(function(ch)
		if ch.Name == "NetworksPostLoad" and ch:IsA("BindableEvent") then
			attach(ch)
		end
	end)
end

print("[RoadGraphReloadSync] ready – rebuilds ordered road polylines on NetworksPostLoad")