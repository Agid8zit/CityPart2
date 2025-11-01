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

-- Road source coordinate – any road zone that contains this grid
-- acts as the single "source" for the Road network.
local ROAD_SOURCE_COORD = { x = 0, z = 0 }

----------------------------------------------------------------------
--  Private helpers
----------------------------------------------------------------------
local warnOnce     = {}            -- [msg] = true  (cleared after delay)

local function dPrint(...)
	if DEBUG_LOGS then
		print("[NetworkManager]", ...)
	end
end

local function wPrint(msg)
	if not warnOnce[msg] then
		warn(msg)
		warnOnce[msg] = true
		task.delay(WARN_SPAM_DELAY, function() warnOnce[msg] = nil end)
	end
end

-- compact grid key
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
-- playerId → { Power = { zones = {..}, adjacency = {..}, unionFind = {..}, cells = {}, ufCells = {..} },
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
			adjacency = {},      -- [zoneId] → { neighbourId, … }
			unionFind = { parent = {}, rank = {} },
			cells     = {},      -- [keyXZ] → { [zoneId]=true, ... }
			ufCells   = nil,     -- cell-level DSU cache (built on demand)
		}
	end
	return nets[networkType]
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
			local k = keyXZ(x, z)
			local bucket = net.cells[k]
			if bucket == nil then
				bucket = {}
				net.cells[k] = bucket
			end
			bucket[zoneId] = true
		elseif DEBUG_LOGS then
			warn("NetworkManager.indexZoneCells: bad coord:", coord)
		end
	end
end

local function deindexZoneCells(net, zoneId, gridList)
	if not gridList then return end
	for _, coord in ipairs(gridList) do
		local x, z = getXZ(coord)
		if x ~= nil and z ~= nil then
			local k = keyXZ(x, z)
			local bucket = net.cells[k]
			if bucket then
				bucket[zoneId] = nil
				local empty = true
				for _ in pairs(bucket) do empty = false; break end
				if empty then net.cells[k] = nil end
			end
		end
	end
end

----------------------------------------------------------------------
--  Cell-level connectivity (per-network cell DSU)
----------------------------------------------------------------------
function NetworkManager.rebuildCellUnionFind(player, networkType)
	local net = ensurePlayerNetwork(player, networkType)

	local uf  = { parent = {}, rank = {} }
	local present = {}        -- set of infra cell keys "x|z" that exist
	local sourceCells = {}    -- list of source cell keys

	-- 1) collect infra cells + mark sources
	for _, z in pairs(net.zones) do
		if isInfraMode(z.mode, networkType) then
			for _, c in ipairs(z.gridList or {}) do
				if c and c.x ~= nil and c.z ~= nil then
					local k = keyXZ(c.x, c.z)
					present[k] = true
					if uf.parent[k] == nil then
						uf.parent[k], uf.rank[k] = k, 0
					end
					if NetworkManager.isSourceZone(z, networkType) then
						sourceCells[#sourceCells+1] = k
					end
				end
			end
		end
	end

	-- 2) connect neighbour infra cells (4‑ or 8‑way depending on USE_DIAGONAL_ADJ)
	for k, _ in pairs(present) do
		local xs, zs = k:match("([^|]+)|([^|]+)")
		local x, z = tonumber(xs), tonumber(zs)
		for _, off in ipairs(adjacentOffsets) do
			local nk = keyXZ(x + off[1], z + off[2])
			if present[nk] then
				uf_union(uf, k, nk)
			end
		end
	end

	-- 3) compute source roots
	local roots = {}
	for _, k in ipairs(sourceCells) do
		roots[uf_find(uf, k)] = true
	end

	-- store
	net.ufCells = { parent = uf.parent, rank = uf.rank, present = present, sourceRoots = roots }
end

-- Query: is this infra cell connected to any source cell?
function NetworkManager.isCellConnectedToSource(player, networkType, gx, gz)
	local net = NetworkManager.networks[player.UserId]
		and NetworkManager.networks[player.UserId][networkType]
	if not net then return false end
	if not net.ufCells then
		NetworkManager.rebuildCellUnionFind(player, networkType)
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
	net.adjacency[zoneId]          = net.adjacency[zoneId] or {}
	net.unionFind.parent[zoneId]   = zoneId
	net.unionFind.rank[zoneId]     = 0

	-- Index the zone's grid cells FIRST to avoid external race/ambiguity
	indexZoneCells(net, zoneId, zoneData.gridList)

	-- Connect to neighbours already present (uses our internal index)
	NetworkManager.updateZoneConnections(player, zoneId, zoneData, networkType)

	-- Keep cell-level DSU current after add
	NetworkManager.rebuildCellUnionFind(player, networkType)

	-- One-shot post-tick rescan
	if POST_TICK_RESCAN then
		task.defer(function()
			local stillHere = NetworkManager.networks[player.UserId]
				and NetworkManager.networks[player.UserId][networkType]
				and NetworkManager.networks[player.UserId][networkType].zones[zoneId]
			if stillHere then
				NetworkManager.updateZoneConnections(player, zoneId, zoneData, networkType)
				-- Cell DSU is topology based; adding connections does not change present cells,
				-- but rebuild anyway to be explicit & future-safe.
				NetworkManager.rebuildCellUnionFind(player, networkType)
			end
		end)
	end

	-- optional debug
	if NetworkManager.isSourceZone(zoneData, networkType)
		and #(net.adjacency[zoneId]) == 0
	then
		dPrint(("Zone %s is a standalone %s source."):format(zoneId, networkType))
	end
end

function NetworkManager.removeZoneFromNetwork(player, zoneId, networkType)
	local pnets = NetworkManager.networks[player.UserId]
	local net = pnets and pnets[networkType]
	if not (net and net.zones[zoneId]) then return end

	local zData = net.zones[zoneId] -- keep reference before purge

	-- capture neighbours BEFORE unlinking (to notify them after rebuild)
	local neighbours = {}
	do
		local list = net.adjacency[zoneId]
		if list then
			for i = 1, #list do
				local nid = list[i]
				if nid and nid ~= zoneId then
					neighbours[#neighbours+1] = nid
				end
			end
		end
	end

	-- de-index cells
	deindexZoneCells(net, zoneId, zData and zData.gridList)

	-- unlink from all adjacency lists
	for parentId, list in pairs(net.adjacency) do
		for i = #list, 1, -1 do
			if list[i] == zoneId then table.remove(list, i) end
		end
	end

	-- purge own tables
	net.adjacency[zoneId]        = nil
	net.zones[zoneId]            = nil
	net.unionFind.parent[zoneId] = zoneId
	net.unionFind.rank[zoneId]   = net.unionFind.rank[zoneId] or 0

	-- rebuild DSUs (zone-level then cell-level)
	NetworkManager.rebuildUnionFind(player, networkType)
	NetworkManager.rebuildCellUnionFind(player, networkType)

	-- notify surviving neighbours so downstream systems rescan
	for _, nid in ipairs(neighbours) do
		local nz = net.zones[nid]
		if nz then
			NetworkReadyEvent:Fire(player, nid, nz)
		end
	end
end

----------------------------------------------------------------------
--  Internal – adjacency / connectivity
----------------------------------------------------------------------
function NetworkManager.updateZoneConnections(player, zoneId, zoneData, networkType)
	local net = ensurePlayerNetwork(player, networkType)
	net.adjacency[zoneId] = net.adjacency[zoneId] or {}

	for adjId, _ in pairs(NetworkManager.getAdjacentZones(player, zoneData.gridList, networkType)) do
		if adjId ~= zoneId then
			net.adjacency[adjId] = net.adjacency[adjId] or {}
			if not table.find(net.adjacency[zoneId], adjId) then
				table.insert(net.adjacency[zoneId], adjId)
			end
			if not table.find(net.adjacency[adjId], zoneId) then
				table.insert(net.adjacency[adjId], zoneId)
			end
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
		for _, nid in ipairs(neighbours) do
			uf_union(uf, zid, nid)
		end
	end
	net.unionFind = uf

	-- keep cell-level DSU in sync with any topology rebuilds
	NetworkManager.rebuildCellUnionFind(player, networkType)
end

----------------------------------------------------------------------
--  Public: query – is zone connected to a source?
----------------------------------------------------------------------
function NetworkManager.isZoneConnected(player, zoneId, networkType)
	local net = NetworkManager.networks[player.UserId]
		and NetworkManager.networks[player.UserId][networkType]
	if not net then
		wPrint(("NetworkManager: '%s' network missing for %s")
			:format(networkType, player.Name))
		return false
	end
	if not net.zones[zoneId] then
		wPrint(("NetworkManager: Zone '%s' not found in %s for %s")
			:format(zoneId, networkType, player.Name))
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
				local k0 = keyXZ(x, z)
				local bucket0 = net.cells[k0]
				if bucket0 then
					for nid in pairs(bucket0) do
						out[nid] = net.zones[nid]
					end
				end
				-- neighbours
				for _, off in ipairs(adjacentOffsets) do
					local gx, gz = x + off[1], z + off[2]
					local k = keyXZ(gx, gz)
					local bucket = net.cells[k]
					if bucket then
						for nid in pairs(bucket) do
							out[nid] = net.zones[nid]
						end
					end
				end
			elseif DEBUG_LOGS then
				warn("NetworkManager.getAdjacentZones: bad coord:", coord)
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
					local z = ZoneTrackerModule.getAnyZoneAtGrid(player, gx, gz)
					if z and NetworkManager.isZonePartOfNetwork(z, networkType) then
						out[z.zoneId] = z
					end
				end
			elseif DEBUG_LOGS then
				warn("NetworkManager.getAdjacentZones: bad coord:", coord)
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

	if relevant then
		NetworkReadyEvent:Fire(player, zoneId, zoneData)
	end
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

	-- Pass 2: rebuild connectivity for each type (also rebuilds cell DSUs)
	NetworkManager.rebuildUnionFind(player, "Water")
	NetworkManager.rebuildUnionFind(player, "Power")
	NetworkManager.rebuildUnionFind(player, "Road")

	-- Pass 3: notify downstream (ZoneRequirementsChecker listens to NetworkReady)
	for networkType, net in pairs(NetworkManager.networks[pid]) do
		for zid, zdata in pairs(net.zones) do
			NetworkReadyEvent:Fire(player, zid, zdata)
		end
	end
end

----------------------------------------------------------------------
--  Player cleanup – avoid memory leaks
----------------------------------------------------------------------
Players.PlayerRemoving:Connect(function(plr)
	local pid = plr.UserId
	NetworkManager.networks[pid] = nil
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
			:format(zid, data.mode, #(net.adjacency[zid] or {})))
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
