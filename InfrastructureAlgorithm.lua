local NetworkManager = {}
NetworkManager.__index = NetworkManager

----------------------------------------------------------------------
--  Services & shared modules
----------------------------------------------------------------------
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ZoneTrackerModule  = require(script.Parent.Parent.Zones.ZoneManager.ZoneTracker)

----------------------------------------------------------------------
--  Events
----------------------------------------------------------------------
local Events            = ReplicatedStorage:WaitForChild("Events")
local BE                = Events:WaitForChild("BindableEvents")
local NetworkReadyEvent = BE:WaitForChild("NetworkReady")

----------------------------------------------------------------------
--  Configuration
----------------------------------------------------------------------
local DEBUG_LOGS        = false          -- set true for verbose prints
local WARN_SPAM_DELAY   = 10             -- seconds between identical warns
local USE_DIAGONAL_ADJ  = true           -- keep 8-way; set false for 4-way strict
local POST_TICK_RESCAN  = true           -- one-shot deferred rescan after add
local USE_ZONE_TRACKER_FALLBACK = false  -- keep false to avoid “any zone” ambiguity
local WARN_GRACE_SEC    = 8              -- suppress warnings for a short window after join

-- Road source coordinate – any road zone that contains this grid
-- acts as the single "source" for the Road network.
local ROAD_SOURCE_COORD = { x = 0, z = 0 }

----------------------------------------------------------------------
--  Private helpers
----------------------------------------------------------------------
local warnOnce     = {}            -- [msg] = true  (cleared after delay)
local warnGraceUntil = {}          -- [userId] = os.clock() + grace

local function dPrint(...)
	if DEBUG_LOGS then
		print("[NetworkManager]", ...)
	end
end

local WARNINGS_ENABLED = false
local function wPrint(msg)
	if not WARNINGS_ENABLED then return end
	if not warnOnce[msg] then
		warn(msg)
		warnOnce[msg] = true
		task.delay(WARN_SPAM_DELAY, function() warnOnce[msg] = nil end)
	end
end

-- compact grid key (used only for the UF over cells)
local function keyXZ(x, z)
	return tostring(x) .. "|" .. tostring(z)
end

-- Safe extractor for coord {x=?, z=?}
local function getXZ(coord)
	if typeof(coord) == "table" and coord.x ~= nil and coord.z ~= nil then
		return coord.x, coord.z
	end
	return nil, nil
end

-- does this zone's gridList contain a specific grid coordinate?
local function zoneContainsCoord(zoneData, gx, gz)
	if not zoneData or typeof(zoneData) ~= "table" then return false end
	local gl = zoneData.gridList
	if typeof(gl) ~= "table" then return false end
	for _, c in ipairs(gl) do
		local x, z = getXZ(c)
		if x and z and x == gx and z == gz then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
--  Data structures
----------------------------------------------------------------------
-- playerId → { Power = { zones = {..}, adjacency = {..}, unionFind = {..},
--                        cells = { [x] = { [z] = { [zoneId]=true } } },
--                        ufCells = { parent, rank, present, sourceRoots },
--                        ufCellsDirty, rebuildScheduled,
--                        notifyQueue = { [zoneId]=zoneData }, notifyScheduled },
--              Water = {..}, Road = {..} }
NetworkManager.networks = {}

-- Pre‑computed neighbouring offsets
local adjacentOffsets
if USE_DIAGONAL_ADJ then
	adjacentOffsets = {
		{ 1,  0}, {-1,  0}, { 0,  1}, { 0, -1},
		{ 1,  1}, {-1,  1}, { 1, -1}, {-1, -1},
	}
else
	adjacentOffsets = {
		{ 1,  0}, {-1,  0}, { 0,  1}, { 0, -1},
	}
end

----------------------------------------------------------------------
--  Union‑Find (disjoint‑set) helpers
----------------------------------------------------------------------
local function uf_find(uf, x)
	if uf.parent[x] == nil then
		uf.parent[x], uf.rank[x] = x, 0
		return x
	end
	if uf.parent[x] ~= x then
		uf.parent[x] = uf_find(uf, uf.parent[x])
	end
	return uf.parent[x]
end

local function uf_union(uf, x, y)
	local rootX, rootY = uf_find(uf, x), uf_find(uf, y)
	if rootX == rootY then return end

	local rankX = uf.rank[rootX] or 0
	local rankY = uf.rank[rootY] or 0

	if rankX < rankY then
		uf.parent[rootX] = rootY
	elseif rankX > rankY then
		uf.parent[rootY] = rootX
	else
		uf.parent[rootY] = rootX
		uf.rank[rootX]   = rankX + 1
	end
end

----------------------------------------------------------------------
--  Zone‑type lookup tables (names used verbatim)
--  (Buildings are members so they can belong to a component;
--   infra is a subset used for cell-level connectivity)
----------------------------------------------------------------------
local waterNetworkModes = {
	WaterTower=true, WaterPipe=true, WaterPlant=true,
	PurificationWaterPlant=true, MolecularWaterPlant=true,
	Residential=true, Commercial=true, Industrial=true,
	ResDense=true,   CommDense=true,  IndusDense=true,
}

local powerNetworkModes = {
	PowerLines=true, SolarPanels=true, WindTurbine=true,
	CoalPowerPlant=true, GasPowerPlant=true, GeothermalPowerPlant=true,
	NuclearPowerPlant=true,
	Residential=true, Commercial=true, Industrial=true,
	ResDense=true,   CommDense=true,  IndusDense=true,
}

-- Infra predicates for cell-level DSU
local function isWaterInfra(mode)
	return mode == "WaterTower" or mode == "WaterPipe" or mode == "WaterPlant"
		or mode == "PurificationWaterPlant" or mode == "MolecularWaterPlant"
end
local function isPowerInfra(mode)
	return mode == "PowerLines" or mode == "SolarPanels" or mode == "WindTurbine"
		or mode == "CoalPowerPlant" or mode == "GasPowerPlant"
		or mode == "GeothermalPowerPlant" or mode == "NuclearPowerPlant"
end
local function isRoadInfra(mode)
	return mode == "DirtRoad" or mode == "Pavement" or mode == "Highway"
end
local function isInfraMode(mode, networkType)
	if networkType == "Water" then return isWaterInfra(mode)
	elseif networkType == "Power" then return isPowerInfra(mode)
	elseif networkType == "Road"  then return isRoadInfra(mode)
	end
	return false
end

----------------------------------------------------------------------
--  Utility – ensure the per‑player, per‑type table exists
----------------------------------------------------------------------
local function ensurePlayerNetwork(player, networkType)
	local pid = player.UserId
	NetworkManager.networks[pid] = NetworkManager.networks[pid] or {}
	local nets = NetworkManager.networks[pid]

	if not nets[networkType] then
		nets[networkType] = {
			zones     = {},      -- [zoneId] → zoneData
			adjacency = {},      -- [zoneId] → { [neighbourId]=true, ... }
			unionFind = { parent = {}, rank = {} },
			cells     = {},      -- nested: [x] → [z] → { [zoneId] = true }
			ufCells   = nil,     -- cell-level DSU cache (built on demand)
			-- incremental rebuild + notify coalescing
			ufCellsDirty     = false,
			rebuildScheduled = false,
			notifyQueue      = {},
			notifyScheduled  = false,
		}
	end
	return nets[networkType]
end

----------------------------------------------------------------------
--  Adjacency (use sets for O(1) add/remove)
----------------------------------------------------------------------
local function adjEnsure(net, id)
	net.adjacency[id] = net.adjacency[id] or {}
end

local function adjAdd(net, a, b)
	if a == b then return end
	adjEnsure(net, a); adjEnsure(net, b)
	net.adjacency[a][b] = true
	net.adjacency[b][a] = true
end

local function adjRemoveEverywhere(net, id)
	local neigh = net.adjacency[id]
	if neigh then
		for n, _ in pairs(neigh) do
			if net.adjacency[n] then
				net.adjacency[n][id] = nil
			end
		end
	end
	net.adjacency[id] = nil
end

local function adjCount(net, id)
	local t = net.adjacency[id]
	if not t then return 0 end
	local n = 0
	for _ in pairs(t) do n += 1 end
	return n
end

----------------------------------------------------------------------
--  Cell index (nested tables: cells[x][z] -> set(zoneId))
----------------------------------------------------------------------
local function getCellBucket(net, x, z, create)
	local col = net.cells[x]
	if not col then
		if not create then return nil end
		col = {}
		net.cells[x] = col
	end
	local bucket = col[z]
	if not bucket and create then
		bucket = {}
		col[z] = bucket
	end
	return bucket
end

local function clearCellIfEmpty(net, x, z)
	local col = net.cells[x]
	if not col then return end
	local bucket = col[z]
	if bucket and next(bucket) == nil then
		col[z] = nil
		if next(col) == nil then
			net.cells[x] = nil
		end
	end
end

----------------------------------------------------------------------
--  Public: predicate – does this zone belong to the queried network?
----------------------------------------------------------------------
function NetworkManager.isZonePartOfNetwork(zoneData, networkType)
	local m = zoneData.mode
	if     networkType == "Water" then
		return waterNetworkModes[m] == true
	elseif networkType == "Power" then
		return powerNetworkModes[m] == true
	elseif networkType == "Road"  then
		return m == "DirtRoad" or m == "Pavement" or m == "Highway"
	end
	return false
end

----------------------------------------------------------------------
--  Internal – index / de-index cells for a zone (per network)
----------------------------------------------------------------------
local function indexZoneCells(net, zoneId, gridList)
	if not gridList then return end
	for _, coord in ipairs(gridList) do
		local x, z = getXZ(coord)
		if x ~= nil and z ~= nil then
			local bucket = getCellBucket(net, x, z, true)
			bucket[zoneId] = true
		elseif DEBUG_LOGS then
			wPrint("NetworkManager.indexZoneCells: bad coord")
		end
	end
end

local function deindexZoneCells(net, zoneId, gridList)
	if not gridList then return end
	for _, coord in ipairs(gridList) do
		local x, z = getXZ(coord)
		if x ~= nil and z ~= nil then
			local bucket = getCellBucket(net, x, z, false)
			if bucket then
				bucket[zoneId] = nil
				clearCellIfEmpty(net, x, z)
			end
		end
	end
end

----------------------------------------------------------------------
--  Incremental rebuild + notify coalescing
----------------------------------------------------------------------
function NetworkManager.scheduleCellRebuild(player, networkType)
	local net = ensurePlayerNetwork(player, networkType)
	net.ufCellsDirty = true
	if net.rebuildScheduled then return end
	net.rebuildScheduled = true
	task.defer(function()
		net.rebuildScheduled = false
	if net.ufCellsDirty then
			NetworkManager.rebuildCellUnionFind(player, networkType)
			net.ufCellsDirty = false
		end
	end)
end

local function queueNetworkReady(player, networkType, zoneId, zoneData)
	local net = ensurePlayerNetwork(player, networkType)
	net.notifyQueue[zoneId] = zoneData or (net.zones and net.zones[zoneId])
	if net.notifyScheduled then return end
	net.notifyScheduled = true
	task.defer(function()
		net.notifyScheduled = false
		for zid, zdata in pairs(net.notifyQueue) do
			NetworkReadyEvent:Fire(player, zid, zdata)
			net.notifyQueue[zid] = nil
		end
	end)
end

----------------------------------------------------------------------
--  Cell-level connectivity (per-network cell DSU)
----------------------------------------------------------------------
function NetworkManager.rebuildCellUnionFind(player, networkType)
	local net = ensurePlayerNetwork(player, networkType)

	local uf  = { parent = {}, rank = {} }
	local present = {}          -- set of infra cell keys "x|z"
	local coords  = {}          -- k -> {x=?, z=?} (avoid string parsing)
	local sourceKeys = {}       -- set of source cell keys

	-- 1) collect infra cells + mark sources
	for _, z in pairs(net.zones) do
		if isInfraMode(z.mode, networkType) then
			local zIsSource = NetworkManager.isSourceZone(z, networkType)
			for _, c in ipairs(z.gridList or {}) do
				local x, cz = getXZ(c)
				if x ~= nil and cz ~= nil then
					local k = keyXZ(x, cz)
					if not present[k] then
						present[k] = true
						coords[k]  = { x = x, z = cz }
						uf.parent[k], uf.rank[k] = k, 0
					end
					if zIsSource then
						sourceKeys[k] = true
					end
				end
			end
		end
	end

	-- 2) connect neighbour infra cells (4‑ or 8‑way depending on USE_DIAGONAL_ADJ)
	for k, c in pairs(coords) do
		local x, z = c.x, c.z
		for _, off in ipairs(adjacentOffsets) do
			local nk = keyXZ(x + off[1], z + off[2])
			if present[nk] then
				uf_union(uf, k, nk)
			end
		end
	end

	-- 3) compute source roots
	local roots = {}
	for k, _ in pairs(sourceKeys) do
		roots[uf_find(uf, k)] = true
	end

	-- store
	net.ufCells = {
		parent      = uf.parent,
		rank        = uf.rank,
		present     = present,
		sourceRoots = roots,
	}
end

-- Query: is this infra cell connected to any source cell?
function NetworkManager.isCellConnectedToSource(player, networkType, gx, gz)
	local net = NetworkManager.networks[player.UserId]
		and NetworkManager.networks[player.UserId][networkType]
	if not net then return false end
	if net.ufCellsDirty or not net.ufCells then
		NetworkManager.rebuildCellUnionFind(player, networkType)
		net.ufCellsDirty = false
		if not net.ufCells then return false end
	end
	local k = keyXZ(gx, gz)
	if not net.ufCells.present[k] then return false end
	local uf = { parent = net.ufCells.parent, rank = net.ufCells.rank }
	return net.ufCells.sourceRoots[uf_find(uf, k)] == true
end

----------------------------------------------------------------------
--  Public: add / remove
----------------------------------------------------------------------
function NetworkManager.addZoneToNetwork(player, zoneId, zoneData, networkType)
	local net = ensurePlayerNetwork(player, networkType)

	-- Register zone
	net.zones[zoneId]              = zoneData
	adjEnsure(net, zoneId)
	net.unionFind.parent[zoneId]   = zoneId
	net.unionFind.rank[zoneId]     = 0

	-- Index the zone's grid cells FIRST to avoid external race/ambiguity
	indexZoneCells(net, zoneId, zoneData.gridList)

	-- Connect to neighbours already present (uses our internal index)
	NetworkManager.updateZoneConnections(player, zoneId, zoneData, networkType)

	-- Defer one cell DSU rebuild for this tick (coalesced across changes)
	NetworkManager.scheduleCellRebuild(player, networkType)

	-- One-shot post-tick rescan (adjacency only); keep DSU rebuild deferred
	if POST_TICK_RESCAN then
		task.defer(function()
			local stillHere = NetworkManager.networks[player.UserId]
				and NetworkManager.networks[player.UserId][networkType]
				and NetworkManager.networks[player.UserId][networkType].zones[zoneId]
			if stillHere then
				NetworkManager.updateZoneConnections(player, zoneId, zoneData, networkType)
				NetworkManager.scheduleCellRebuild(player, networkType)
			end
		end)
	end

	-- optional debug
	if NetworkManager.isSourceZone(zoneData, networkType)
		and adjCount(net, zoneId) == 0
	then
		dPrint(("Zone %s is a standalone %s source."):format(zoneId, networkType))
	end

	-- Coalesced notify (downstream systems rescan once)
	queueNetworkReady(player, networkType, zoneId, zoneData)
end

function NetworkManager.removeZoneFromNetwork(player, zoneId, networkType)
	local pnets = NetworkManager.networks[player.UserId]
	local net = pnets and pnets[networkType]
	if not (net and net.zones[zoneId]) then return end

	local zData = net.zones[zoneId] -- keep reference before purge

	-- capture neighbours BEFORE unlinking (to notify them after rebuild)
	local neighbours = {}
	do
		local neighSet = net.adjacency[zoneId]
		if neighSet then
			for nid, _ in pairs(neighSet) do
				if nid and nid ~= zoneId then
					neighbours[#neighbours+1] = nid
				end
			end
		end
	end

	-- de-index cells
	deindexZoneCells(net, zoneId, zData and zData.gridList)

	-- unlink from adjacency
	adjRemoveEverywhere(net, zoneId)

	-- purge own tables
	net.zones[zoneId]            = nil
	net.unionFind.parent[zoneId] = zoneId
	net.unionFind.rank[zoneId]   = net.unionFind.rank[zoneId] or 0

	-- rebuild zone-level DSU (cheap) and mark cells DSU dirty (deferred)
	NetworkManager.rebuildUnionFind(player, networkType)
	NetworkManager.scheduleCellRebuild(player, networkType)

	-- notify surviving neighbours so downstream systems rescan (coalesced)
	for _, nid in ipairs(neighbours) do
		local nz = net.zones[nid]
		if nz then
			queueNetworkReady(player, networkType, nid, nz)
		end
	end
end

----------------------------------------------------------------------
--  Internal – adjacency / connectivity
----------------------------------------------------------------------
function NetworkManager.updateZoneConnections(player, zoneId, zoneData, networkType)
	local net = ensurePlayerNetwork(player, networkType)
	adjEnsure(net, zoneId)

	for adjId, _ in pairs(NetworkManager.getAdjacentZones(player, zoneData.gridList, networkType)) do
		if adjId ~= zoneId then
			adjAdd(net, zoneId, adjId)
			uf_union(net.unionFind, zoneId, adjId)
		end
	end
end

function NetworkManager.rebuildUnionFind(player, networkType)
	local net = NetworkManager.networks[player.UserId]
		and NetworkManager.networks[player.UserId][networkType]
	if not net then return end

	local uf = { parent = {}, rank = {} }
	for zid in pairs(net.zones) do
		uf.parent[zid], uf.rank[zid] = zid, 0
	end
	for zid, neighbours in pairs(net.adjacency) do
		for nid, _ in pairs(neighbours) do
			uf_union(uf, zid, nid)
		end
	end
	net.unionFind = uf

	-- mark cell-level DSU dirty; rebuild is coalesced
	net.ufCellsDirty = true
	NetworkManager.scheduleCellRebuild(player, networkType)
end

----------------------------------------------------------------------
--  Public: query – is zone connected to a source?
----------------------------------------------------------------------
function NetworkManager.isZoneConnected(player, zoneId, networkType)
	local net = NetworkManager.networks[player.UserId]
		and NetworkManager.networks[player.UserId][networkType]
	if not net then
		if not (warnGraceUntil[player.UserId] and os.clock() < warnGraceUntil[player.UserId]) then
			wPrint(("NetworkManager: '%s' network missing for %s")
				:format(networkType, player.Name))
		end
		return false
	end
	if not net.zones[zoneId] then
		if not (warnGraceUntil[player.UserId] and os.clock() < warnGraceUntil[player.UserId]) then
			wPrint(("NetworkManager: Zone '%s' not found in %s for %s")
				:format(zoneId, networkType, player.Name))
		end
		return false
	end

	local root = uf_find(net.unionFind, zoneId)
	for srcId, data in pairs(net.zones) do
		if NetworkManager.isSourceZone(data, networkType)
			and uf_find(net.unionFind, srcId) == root
		then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
--  Public: predicate – is this zone a source?
----------------------------------------------------------------------
function NetworkManager.isSourceZone(zoneData, networkType)
	local m = zoneData.mode
	if networkType == "Water" then
		return m == "WaterTower"
			or m == "WaterPlant"
			or m == "PurificationWaterPlant"
			or m == "MolecularWaterPlant"
	elseif networkType == "Power" then
		return m == "SolarPanels"
			or m == "WindTurbine"
			or m == "CoalPowerPlant"
			or m == "GasPowerPlant"
			or m == "GeothermalPowerPlant"
			or m == "NuclearPowerPlant"
	elseif networkType == "Road" then
		-- treat whichever road zone contains ROAD_SOURCE_COORD as the source
		if m == "DirtRoad" or m == "Pavement" or m == "Highway" then
			return zoneContainsCoord(zoneData, ROAD_SOURCE_COORD.x, ROAD_SOURCE_COORD.z)
		end
	end
	return false
end

----------------------------------------------------------------------
--  Internal – neighbour scan (internal index; optional fallback)
----------------------------------------------------------------------
function NetworkManager.getAdjacentZones(player, gridList, networkType)
	local out = {}
	if not gridList then return out end

	local net = NetworkManager.networks[player.UserId]
		and NetworkManager.networks[player.UserId][networkType]

	-- Use our internal cell index (overlay-safe)
	if net and net.cells then
		for _, coord in ipairs(gridList) do
			local x, z = getXZ(coord)
			if x ~= nil and z ~= nil then
				-- same-cell
				local bucket0 = getCellBucket(net, x, z, false)
				if bucket0 then
					for nid in pairs(bucket0) do
						out[nid] = net.zones[nid]
					end
				end
				-- neighbours
				for _, off in ipairs(adjacentOffsets) do
					local gx, gz = x + off[1], z + off[2]
					local bucket = getCellBucket(net, gx, gz, false)
					if bucket then
						for nid in pairs(bucket) do
							out[nid] = net.zones[nid]
						end
					end
				end
			elseif DEBUG_LOGS then
				wPrint("NetworkManager.getAdjacentZones: bad coord")
			end
		end
		return out
	end

	-- Optional fallback (disabled by default)
	if USE_ZONE_TRACKER_FALLBACK then
		for _, coord in ipairs(gridList) do
			if typeof(coord) == "table" and coord.x and coord.z then
				local z0 = ZoneTrackerModule.getAnyZoneAtGrid(player, coord.x, coord.z)
				if z0 and NetworkManager.isZonePartOfNetwork(z0, networkType) then
					out[z0.zoneId] = z0
				end
				for _, off in ipairs(adjacentOffsets) do
					local gx, gz = coord.x + off[1], coord.z + off[2]
					local zt = ZoneTrackerModule.getAnyZoneAtGrid(player, gx, gz)
					if zt and NetworkManager.isZonePartOfNetwork(zt, networkType) then
						out[zt.zoneId] = zt
					end
				end
			elseif DEBUG_LOGS then
				wPrint("NetworkManager.getAdjacentZones: bad coord")
			end
		end
	end

	return out
end

----------------------------------------------------------------------
--  Event wiring – keep graphs in sync with ZoneTracker
----------------------------------------------------------------------
local function onZoneAdded(player, zoneId, zoneData)
	local relevant = false
	if NetworkManager.isZonePartOfNetwork(zoneData, "Water") then
		NetworkManager.addZoneToNetwork(player, zoneId, zoneData, "Water")
		relevant = true
	end
	if NetworkManager.isZonePartOfNetwork(zoneData, "Power") then
		NetworkManager.addZoneToNetwork(player, zoneId, zoneData, "Power")
		relevant = true
	end
	if NetworkManager.isZonePartOfNetwork(zoneData, "Road") then
		NetworkManager.addZoneToNetwork(player, zoneId, zoneData, "Road")
		relevant = true
	end

	if DEBUG_LOGS and not relevant and zoneData and zoneData.mode then
		dPrint(("Unrecognized mode on add: %s"):format(tostring(zoneData.mode)))
	end

	-- Do NOT fire NetworkReady directly here; addZoneToNetwork() queued it.
end

local function onZoneCreated(player, zoneId, mode, gridList)
	local zData = { zoneId = zoneId, mode = mode, gridList = gridList }
	return onZoneAdded(player, zoneId, zData)
end

local function onZoneRemoved(player, zoneId, mode, gridList)
	local dummy = { zoneId = zoneId, mode = mode }
	if NetworkManager.isZonePartOfNetwork(dummy, "Water") then
		NetworkManager.removeZoneFromNetwork(player, zoneId, "Water")
	end
	if NetworkManager.isZonePartOfNetwork(dummy, "Power") then
		NetworkManager.removeZoneFromNetwork(player, zoneId, "Power")
	end
	if NetworkManager.isZonePartOfNetwork(dummy, "Road") then
		NetworkManager.removeZoneFromNetwork(player, zoneId, "Road")
	end
end

BE:WaitForChild("ZoneAdded").Event:Connect(onZoneAdded)
BE:WaitForChild("ZoneRemoved").Event:Connect(onZoneRemoved)

do
	local zc = BE:FindFirstChild("ZoneCreated")
	if zc and zc:IsA("BindableEvent") then
		zc.Event:Connect(onZoneCreated)
	end
end

function NetworkManager.rebuildAllForPlayer(player)
	local pid = player.UserId

	-- Ensure per-type tables exist
	local water = ensurePlayerNetwork(player, "Water")
	local power = ensurePlayerNetwork(player, "Power")
	local road  = ensurePlayerNetwork(player, "Road")

	-- Pass 1: add any missing zones from ZoneTracker into our indices
	for zid, z in pairs(ZoneTrackerModule.getAllZones(player)) do
		if NetworkManager.isZonePartOfNetwork(z, "Water") and not water.zones[zid] then
			NetworkManager.addZoneToNetwork(player, zid, z, "Water")
		end
		if NetworkManager.isZonePartOfNetwork(z, "Power") and not power.zones[zid] then
			NetworkManager.addZoneToNetwork(player, zid, z, "Power")
		end
		if NetworkManager.isZonePartOfNetwork(z, "Road")  and not road.zones[zid] then
			NetworkManager.addZoneToNetwork(player, zid, z, "Road")
		end
	end

	-- Pass 2: rebuild connectivity for each type (also flags cell DSUs dirty)
	NetworkManager.rebuildUnionFind(player, "Water")
	NetworkManager.rebuildUnionFind(player, "Power")
	NetworkManager.rebuildUnionFind(player, "Road")

	-- Pass 3: notify downstream (batched)
	for _, networkType in ipairs({"Water","Power","Road"}) do
		local net = NetworkManager.networks[pid] and NetworkManager.networks[pid][networkType]
		if net then
			for zid, zdata in pairs(net.zones) do
				queueNetworkReady(player, networkType, zid, zdata)
			end
		end
	end
end

----------------------------------------------------------------------
--  Player cleanup – avoid memory leaks
----------------------------------------------------------------------
Players.PlayerRemoving:Connect(function(plr)
	local pid = plr.UserId
	NetworkManager.networks[pid] = nil
	warnGraceUntil[pid] = nil
end)

Players.PlayerAdded:Connect(function(plr)
	warnGraceUntil[plr.UserId] = os.clock() + WARN_GRACE_SEC
end)

----------------------------------------------------------------------
--  Optional debug helpers
----------------------------------------------------------------------
function NetworkManager.countZones(player, networkType)
	local net = NetworkManager.networks[player.UserId]
		and NetworkManager.networks[player.UserId][networkType]
	if not net then return 0 end
	local n = 0
	for _ in pairs(net.zones) do n += 1 end
	return n
end

function NetworkManager.debugDump(player, networkType)
	local net = NetworkManager.networks[player.UserId]
		and NetworkManager.networks[player.UserId][networkType]
	print("=== Network dump:", player.Name, networkType, "===")
	if not net then print("  <none>"); return end
	for zid, data in pairs(net.zones) do
		print(("  • %s  (%s)  neighbours=%d")
			:format(zid, data.mode, adjCount(net, zid)))
	end
end

function NetworkManager.getConnectedZoneIds(player, startZoneId, networkType)
	local net = NetworkManager.networks[player.UserId]
		and NetworkManager.networks[player.UserId][networkType]
	if not net or not net.zones[startZoneId] then return {} end
	local root = uf_find(net.unionFind, startZoneId)
	local out = {}
	for zid in pairs(net.zones) do
		if uf_find(net.unionFind, zid) == root then
			table.insert(out, zid)
		end
	end
	return out
end

function NetworkManager.getZoneData(player, zoneId, networkType)
	local net = NetworkManager.networks[player.UserId]
		and NetworkManager.networks[player.UserId][networkType]
	if not net then return nil end
	return net.zones[zoneId]
end

return NetworkManager
