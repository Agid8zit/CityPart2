local GridUtil = {}
GridUtil.__index = GridUtil

local GridConfig = require(script.Parent:WaitForChild("GridConfig"))
local GRID_SIZE = GridConfig.GRID_SIZE

local RunService = game:GetService("RunService")

-- Convert a world position to grid coordinates using local minX and minZ.
function GridUtil.worldToGridPosition(worldPosition, minX, minZ)
	local gridX = math.floor((worldPosition.X - minX) / GRID_SIZE)
	local gridZ = math.floor((worldPosition.Z - minZ) / GRID_SIZE)
	return gridX, gridZ
end

-- Convert grid coordinates to a world position using local minX and minZ.
function GridUtil.gridToWorldPosition(gridX, gridZ, minX, minZ)
	local worldX = minX + (gridX + 0.5) * GRID_SIZE
	local worldZ = minZ + (gridZ + 0.5) * GRID_SIZE
	return worldX, worldZ
end

-- Convert a world position to global grid coordinates using the global bounds.
function GridUtil.worldToGlobalGridPosition(worldPosition, globalBounds)
	local gridX = math.floor((worldPosition.X - globalBounds.minX) / GRID_SIZE)
	local gridZ = math.floor((worldPosition.Z - globalBounds.minZ) / GRID_SIZE)
	return gridX, gridZ
end

-- Convert global grid coordinates to a world position.
-- Uses globalBounds for X/Z and scans terrains to pick a reasonable Y.
function GridUtil.globalGridToWorldPosition(gridX, gridZ, globalBounds, terrains)
	local worldX = globalBounds.minX + (gridX + 0.5) * GRID_SIZE
	local worldZ = globalBounds.minZ + (gridZ + 0.5) * GRID_SIZE
	local worldY = nil

	for _, terrain in ipairs(terrains) do
		local tMinX, tMinZ = GridConfig.calculateCoords(terrain)
		local tMaxX = tMinX + terrain.Size.X
		local tMaxZ = tMinZ + terrain.Size.Z
		if worldX >= tMinX and worldX <= tMaxX and worldZ >= tMinZ and worldZ <= tMaxZ then
			worldY = terrain.Position.Y + (terrain.Size.Y / 2) + GridConfig.Y_OFFSET
			break
		end
	end
	if not worldY then
		worldY = GridConfig.Y_OFFSET
	end
	return worldX, worldY, worldZ
end

-- Generate a list of grid coordinates within a rectangle.
function GridUtil.getGridList(startCoord, finishCoord)
	local gridList = {}
	local minX = math.min(startCoord.x, finishCoord.x)
	local maxX = math.max(startCoord.x, finishCoord.x)
	local minZ = math.min(startCoord.z, finishCoord.z)
	local maxZ = math.max(startCoord.z, finishCoord.z)

	for x = minX, maxX do
		for z = minZ, maxZ do
			table.insert(gridList, {x = x, z = z})
		end
	end
	return gridList
end

-- Split a list of grid coordinates into connected components.
function GridUtil.splitIntoConnectedComponents(gridList)
	local components, visited, gridSet = {}, {}, {}
	for _, coord in ipairs(gridList) do
		gridSet[coord.x .. "," .. coord.z] = true
	end
	local function dfs(coord, acc)
		local key = coord.x .. "," .. coord.z
		if visited[key] then return end
		visited[key] = true; acc[#acc+1] = coord
		local neighbors = {
			{ x = coord.x + 1, z = coord.z },
			{ x = coord.x - 1, z = coord.z },
			{ x = coord.x,     z = coord.z + 1 },
			{ x = coord.x,     z = coord.z - 1 },
		}
		for _, n in ipairs(neighbors) do
			local nk = n.x .. "," .. n.z
			if gridSet[nk] and not visited[nk] then dfs(n, acc) end
		end
	end
	for _, c in ipairs(gridList) do
		local k = c.x .. "," .. c.z
		if not visited[k] then
			local comp = {}; dfs(c, comp)
			components[#components+1] = comp
		end
	end
	return components
end

-- Split a new zone around existing roads.
function GridUtil.splitZoneAroundRoad(newZoneGridList, roadGridList)
	local splitZones, visited, roadSet, zoneSet = {}, {}, {}, {}
	for _, c in ipairs(roadGridList) do roadSet[c.x .. "," .. c.z] = true end
	for _, c in ipairs(newZoneGridList) do
		local k = c.x .. "," .. c.z
		if not roadSet[k] then zoneSet[k] = true end
	end
	local function dfs(coord, acc)
		local key = coord.x .. "," .. coord.z
		if visited[key] or not zoneSet[key] then return end
		visited[key] = true; acc[#acc+1] = coord
		local neighbors = {
			{ x = coord.x + 1, z = coord.z },
			{ x = coord.x - 1, z = coord.z },
			{ x = coord.x,     z = coord.z + 1 },
			{ x = coord.x,     z = coord.z - 1 },
		}
		for _, n in ipairs(neighbors) do
			local nk = n.x .. "," .. n.z
			if zoneSet[nk] and not visited[nk] then dfs(n, acc) end
		end
	end
	for _, c in ipairs(newZoneGridList) do
		local k = c.x .. "," .. c.z
		if zoneSet[k] and not visited[k] then
			local acc = {}; dfs(c, acc)
			if #acc > 0 then splitZones[#splitZones+1] = acc end
		end
	end
	return splitZones
end

--------------------------------------------------------------------
-- RESERVATION API (server-only): prevents destructive races but
-- allows overlay coexistence via a compatibility matrix.
--------------------------------------------------------------------
do
	local function _uid(player) return player and player.UserId end
	local function _key(x, z) return tostring(x) .. "," .. tostring(z) end

	-- Compatibility: “does myType block otherType?”
	-- Goal: buildings and water co-exist; water blocks only water.
	local _BLOCKS = {
		building = { building = true, road = true }, -- ⬅ block buildings when roads pre‑reserve tiles
		water    = { water    = true }, -- water vs water blocks (avoid duplicates)
		power    = { power    = true }, -- future: power vs power blocks; power vs building allowed
		road     = { road     = true, building = false }, -- roads may co‑reserve where a building is in-flight
	}

	-- per-player store: _R[uid][key] = { reservation, ... }
	-- reservation = { uid, zoneId, occupantType, expireAt, cells = {...} }
	local _R = {}

	if RunService:IsServer() then
		function GridUtil.sweepReservations(player)
			local uid = _uid(player); if not uid then return end
			local grid = _R[uid]; if not grid then return end
			local now = os.clock()
			for key, stack in pairs(grid) do
				for i = #stack, 1, -1 do
					if stack[i].expireAt and stack[i].expireAt <= now then
						table.remove(stack, i)
					end
				end
				if #stack == 0 then grid[key] = nil end
			end
		end

		-- Internal: conflict between types?
		local function _conflicts(myType, otherType)
			if not myType or not otherType then return true end
			return (_BLOCKS[myType] and _BLOCKS[myType][otherType]) or false
		end

		-- Is there any reservation that *blocks* me at (x,z)?
		function GridUtil.isReservationBlocking(player, zoneId, x, z, myOccType)
			local uid = _uid(player); if not uid then return false end
			local grid = _R[uid]; if not grid then return false end
			local stack = grid[_key(x, z)]; if not stack then return false end
			local now = os.clock()
			for _, r in ipairs(stack) do
				if (not r.expireAt or r.expireAt > now) and r.zoneId ~= zoneId then
					if _conflicts(myOccType or "building", r.occupantType) then
						return true
					end
				end
			end
			return false
		end

		function GridUtil.anyReservationsBlocked(player, zoneId, originX, originZ, width, depth, myOccType)
			for dx = 0, width - 1 do
				for dz = 0, depth - 1 do
					if GridUtil.isReservationBlocking(player, zoneId, originX + dx, originZ + dz, myOccType) then
						return true
					end
				end
			end
			return false
		end

		local function _reserveRaw(uid, zoneId, occType, cells, ttl)
			_R[uid] = _R[uid] or {}
			local grid = _R[uid]
			local now = os.clock()
			local h = { uid = uid, zoneId = zoneId, occupantType = occType, expireAt = now + ttl, cells = cells }
			for _, c in ipairs(cells) do
				local key = _key(c.x, c.z)
				grid[key] = grid[key] or {}
				table.insert(grid[key], h)
			end
			return h
		end

		-- Reserve cells; allow overlays to co-reserve when compatibility permits.
		function GridUtil.reserveArea(player, zoneId, occupantType, cells, opts)
			local uid = _uid(player); if not uid then return nil, "no-player" end
			opts = opts or {}
			local ttl = tonumber(opts.ttl) or 12.0
			GridUtil.sweepReservations(player)

			local grid = _R[uid]
			local now = os.clock()
			for _, c in ipairs(cells) do
				local stack = grid and grid[_key(c.x, c.z)]
				if stack then
					for _, r in ipairs(stack) do
						if (not r.expireAt or r.expireAt > now) and r.zoneId ~= zoneId then
							-- Only block if the compatibility matrix says so
							if _BLOCKS[occupantType] and _BLOCKS[occupantType][r.occupantType] then
								return nil, ("blocked by '%s' reservation at %d,%d"):format(r.occupantType, c.x, c.z)
							end
							-- Note: we do NOT block in the reverse direction by default (r vs me)
							-- so building<->water can happily co-reserve.
						end
					end
				end
			end

			table.sort(cells, function(a,b)
				return (a.x == b.x) and (a.z < b.z) or (a.x < b.x)
			end)
			return _reserveRaw(uid, zoneId, occupantType, cells, ttl)
		end

		function GridUtil.reserveFootprint(player, zoneId, occupantType, originX, originZ, width, depth, opts)
			local cells = {}
			for dx = 0, width - 1 do
				for dz = 0, depth - 1 do
					cells[#cells+1] = { x = originX + dx, z = originZ + dz }
				end
			end
			return GridUtil.reserveArea(player, zoneId, occupantType, cells, opts)
		end

		function GridUtil.releaseReservation(handle)
			if not handle or not handle.cells or not handle.uid then return end
			local grid = _R[handle.uid]; if not grid then return end
			for _, c in ipairs(handle.cells) do
				local key = _key(c.x, c.z)
				local stack = grid[key]
				if stack then
					for i = #stack, 1, -1 do
						if stack[i] == handle then table.remove(stack, i) end
					end
					if #stack == 0 then grid[key] = nil end
				end
			end
		end

		-- Backwards-compat aliases used earlier (assume building intent)
		function GridUtil.isReservedByOther(player, zoneId, x, z)
			return GridUtil.isReservationBlocking(player, zoneId, x, z, "building")
		end

	else
		-- Client stubs (safe no-ops)
		function GridUtil.sweepReservations(_) end
		function GridUtil.isReservationBlocking(_, _, _, _, _) return false end
		function GridUtil.anyReservationsBlocked(_, _, _, _, _, _, _) return false end
		function GridUtil.reserveArea(_, _, _, _, _) return nil, "client-noop" end
		function GridUtil.reserveFootprint(_, _, _, _, _, _, _, _) return nil, "client-noop" end
		function GridUtil.releaseReservation(_) end
		function GridUtil.isReservedByOther(_, _, _, _) return false end
	end
end

return GridUtil
