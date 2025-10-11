local PowerLinePath = {}
PowerLinePath.__index = PowerLinePath

local ZoneTrackerModule = require(game.ServerScriptService.Build.Zones.ZoneManager.ZoneTracker)
local GridConfig       = require(game.ReplicatedStorage.Scripts.Grid.GridConfig)
local GridUtil         = require(game.ReplicatedStorage.Scripts.Grid.GridUtil)

-- Debug flag + helpers
local DEBUG = false
local function dprint(...)
	if DEBUG then
		print(...)
	end
end
local function dwarn(...)
	if DEBUG then
		warn(...)
	end
end

-- We'll store zone data in 'lineNetworks'
-- Also store a 'globalAdjacency' table for BFS across all zones
PowerLinePath.globalAdjacency = {}

local lineNetworks    = {}
local globalAdjacency = PowerLinePath.globalAdjacency  -- convenience alias

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

local function getLineDirection(coord1, coord2)
	local dx = coord2.x - coord1.x
	local dz = coord2.z - coord1.z
	if dx == 0 and dz == 0 then
		return "Undefined"
	end
	local angle = math.deg(math.atan2(dz, dx))
	if angle < 0 then angle = angle + 360 end
	return getNearestDirection(angle)
end

local function getAngleBetweenCoords(c1, c2)
	local dx = c2.x - c1.x
	local dz = c2.z - c1.z
	if dx == 0 and dz == 0 then
		return -1
	end
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

-- Given a list of coords (like start/end), fill any missing intermediate cells
local function fillLineBetweenCoords(coords)
	-- Example: coords = { (16,9), (16,12) } -> we fill (16,10) & (16,11)
	if #coords < 2 then
		return coords
	end

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
			-- Only straight lines supported; keep c2 but this won’t fill diagonals
			table.insert(fullList, c2)
		end
	end

	return fullList
end

-- INTERNAL: addToNetwork – merges new line cells into adjacency for BFS.
local function addToNetwork(zoneId, lineCoords)
	dprint(string.format("[PowerLinePath] Adding line segments for Line ID '%s'", zoneId))

	local network = lineNetworks[zoneId]
	if not network then
		network = {
			id = zoneId,
			segments = {},
			overallDirection = "Undefined",
			startCoord = nil,
			endCoord = nil
		}
		lineNetworks[zoneId] = network
	end

	-- Build the 'segments' table: each coordinate plus a direction to next
	for i = 1, #lineCoords - 1 do
		local direction = getLineDirection(lineCoords[i], lineCoords[i + 1])
		table.insert(network.segments, { coord = lineCoords[i], direction = direction })
	end

	-- The last coordinate goes in with direction = "End"
	if #lineCoords > 0 then
		table.insert(network.segments, { coord = lineCoords[#lineCoords], direction = "End" })
		network.endCoord  = lineCoords[#lineCoords]
		network.startCoord = lineCoords[1] -- assume first is the 'start'
	end

	-- Create adjacency nodes for these new cells
	for _, c in ipairs(lineCoords) do
		local k = nodeKey(c)
		if not globalAdjacency[k] then
			globalAdjacency[k] = {}
		end
	end

	-- Link new cells to each other if areNeighbors
	for i = 1, #lineCoords do
		for j = i + 1, #lineCoords do
			if areNeighbors(lineCoords[i], lineCoords[j]) then
				local k1 = nodeKey(lineCoords[i])
				local k2 = nodeKey(lineCoords[j])
				if not table.find(globalAdjacency[k1], k2) then
					table.insert(globalAdjacency[k1], k2)
				end
				if not table.find(globalAdjacency[k2], k1) then
					table.insert(globalAdjacency[k2], k1)
				end
			end
		end
	end

	-- Merge adjacency with existing lines
	for _, newCoord in ipairs(lineCoords) do
		local newKey = nodeKey(newCoord)
		for existingKey, neighborList in pairs(globalAdjacency) do
			if existingKey ~= newKey then
				local exX, exZ = splitKey(existingKey)
				local oldCoord = { x = exX, z = exZ }

				-- (A) Same cell => unify adjacency sets
				if newCoord.x == exX and newCoord.z == exZ then
					local newAdj = globalAdjacency[newKey]
					local oldAdj = neighborList
					for _, nbrId in ipairs(oldAdj) do
						if not table.find(newAdj, nbrId) then
							table.insert(newAdj, nbrId)
						end
					end
					for _, nbrId in ipairs(newAdj) do
						if not table.find(oldAdj, nbrId) then
							table.insert(oldAdj, nbrId)
						end
					end
					globalAdjacency[newKey] = newAdj
					globalAdjacency[existingKey] = oldAdj

					-- (B) Neighbors => link them
				elseif areNeighbors(newCoord, oldCoord) then
					local newAdj = globalAdjacency[newKey]
					if not table.find(newAdj, existingKey) then
						table.insert(newAdj, existingKey)
					end
					if not table.find(neighborList, newKey) then
						table.insert(neighborList, newKey)
					end
				end
			end
		end
	end
end

-- classifyNode: is it Straight, Turn, 3Way, 4Way, etc.?
function PowerLinePath.classifyNode(coord)
	local k = nodeKey(coord)
	local neighbors = globalAdjacency[k]
	if not neighbors or #neighbors == 0 then
		return "None"
	end

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

function PowerLinePath.determineOverallDirection(startCoord, endCoord)
	if not startCoord or not endCoord then
		error("[PowerLinePath] startCoord or endCoord is nil")
	end
	local dx = endCoord.x - startCoord.x
	local dz = endCoord.z - startCoord.z
	dprint("[CALLER] Power line StartCoord:", startCoord.x, startCoord.z)
	dprint("[CALLER] Power line EndCoord:",   endCoord.x,   endCoord.z)
	if dx == 0 and dz == 0 then
		return "Undefined"
	end
	local angle = math.deg(math.atan2(dz, dx))
	if angle < 0 then angle = angle + 360 end
	return getNearestDirection(angle)
end

-- registerLine
-- MAIN ENTRY: we fill missing cells, then add to adjacency, then store direction.
function PowerLinePath.registerLine(zoneId, mode, gridCoords, startCoord, endCoord)
	dprint(string.format(
		"[PowerLinePath] Registering line '%s' of type '%s' with grid coordinates:",
		zoneId, mode
		))
	for _, coord in ipairs(gridCoords) do
		-- (intentionally silent unless you want per-cell logs)
		-- dprint(string.format("  (%d,%d)", coord.x, coord.z))
	end

	-- 1) Fill any missing cells to avoid skipping
	local filledCoords = fillLineBetweenCoords(gridCoords)

	-- 2) Actually build adjacency
	addToNetwork(zoneId, filledCoords)

	-- 3) Determine direction
	local overallDirection = PowerLinePath.determineOverallDirection(startCoord, endCoord)
	dprint(string.format("[PowerLinePath] Line '%s' is built in direction: %s", zoneId, overallDirection))

	-- 4) Store direction + start/end
	local network = lineNetworks[zoneId]
	if network then
		network.overallDirection = overallDirection
		network.startCoord = startCoord
		network.endCoord   = endCoord
		dprint(string.format(
			"[PowerLinePath] Stored direction '%s' + start/end for '%s'.",
			overallDirection, zoneId
			))
	else
		dwarn(string.format("[PowerLinePath] Could not update network for line '%s'.", zoneId))
	end
end

-- unregisterLine
function PowerLinePath.unregisterLine(zoneId)
	local network = lineNetworks[zoneId]
	if network then
		dprint(string.format("[PowerLinePath] Unregistering line '%s'.", zoneId))
		-- Remove from global adjacency
		if network.segments then
			for _, seg in ipairs(network.segments) do
				local k = nodeKey(seg.coord)
				if globalAdjacency[k] then
					for _, neighborKey in ipairs(globalAdjacency[k]) do
						if globalAdjacency[neighborKey] then
							local newList = {}
							for _, item in ipairs(globalAdjacency[neighborKey]) do
								if item ~= k then
									table.insert(newList, item)
								end
							end
							globalAdjacency[neighborKey] = newList
						end
					end
					globalAdjacency[k] = nil
				end
			end
		end
		lineNetworks[zoneId] = nil
		dprint(string.format("[PowerLinePath] Line '%s' unregistered + adjacency updated.", zoneId))
	else
		dwarn(string.format("[PowerLinePath] Attempted to unregister non-existent line '%s'.", zoneId))
	end
end

-- BFS & other helpers
function PowerLinePath.getLineNetworks()
	return lineNetworks
end

function PowerLinePath.bfsFindPathGlobal(startCoord, endCoord)
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
		dwarn("bfsFindPathGlobal: startCoord not in adjacency. No line covers it?")
		return nil
	end
	if not globalAdjacency[endKey] then
		dwarn("bfsFindPathGlobal: endCoord not in adjacency. No line covers it?")
		return nil
	end

	local queue   = { startKey }
	local visited = { [startKey] = true }
	local parent  = {}

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
					parent[nbrKey]  = current
					table.insert(queue, nbrKey)
				end
			end
		end
	end

	return nil
end

function PowerLinePath.findFarthestNode(startCoord)
	local startKey = nodeKey(startCoord)
	if not globalAdjacency[startKey] then
		dwarn("findFarthestNode: startCoord not in adjacency. Possibly no line covers it?")
		return nil
	end

	local queue   = { startKey }
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

function PowerLinePath.getConnectedLines(coord)
	local connectedLines = {}
	local k    = nodeKey(coord)
	local nbrs = globalAdjacency[k]
	if nbrs then
		for _, neighborKey in ipairs(nbrs) do
			local x, z = splitKey(neighborKey)
			for zoneId, network in pairs(lineNetworks) do
				if network.startCoord
					and network.startCoord.x == x
					and network.startCoord.z == z then
					table.insert(connectedLines, network)
				elseif network.endCoord
					and network.endCoord.x == x
					and network.endCoord.z == z then
					table.insert(connectedLines, network)
				end
			end
		end
	end
	return connectedLines
end

function PowerLinePath.getLineData(zoneId)
	return PowerLinePath.getLineNetworks()[zoneId]
end

PowerLinePath.nodeKey          = nodeKey
PowerLinePath.directionAngles  = directionAngles
PowerLinePath.getLineDirection = getLineDirection

return PowerLinePath
