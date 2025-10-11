local GridConfig = {}
GridConfig.__index = GridConfig

-- Configuration
GridConfig.GRID_SIZE = 4
GridConfig.Y_OFFSET = 0.4

-- We track two bounding boxes:
-- 1) stableMinX/stableMinZ -> stableMaxX/stableMaxZ
--    - This is used for converting world positions into gridX, gridZ
--    - We never shift stableMinX/stableMinZ after the first time, so old zones don't move.
-- 2) absoluteMinX/absoluteMinZ
--    - The actual farthest-left/bottom discovered. Might be < stableMinX/stableMinZ,
--      in which case newly unlocked left terrain has negative grid coords.

local stableMinX, stableMinZ = nil, nil
local stableMaxX, stableMaxZ = nil, nil
local absoluteMinX, absoluteMinZ = nil, nil

function GridConfig.setStableAnchorFromPart(part)
	--if stableMinX then return end                     -- only first time
	stableMinX = part.Position.X - GridConfig.GRID_SIZE * 0.5
	stableMinZ = part.Position.Z - GridConfig.GRID_SIZE * 0.5

	stableMaxX, stableMaxZ = stableMinX, stableMinZ
	absoluteMinX, absoluteMinZ = stableMinX, stableMinZ
end


-- Helper: compute minX, minZ for a single terrain

function GridConfig.calculateCoords(terrain)
	local size = terrain.Size
	local pos = terrain.Position
	local minX = pos.X - (size.X * 0.5)
	local minZ = pos.Z - (size.Z * 0.5)
	return minX, minZ
end


-- Main: calculateGlobalBounds
--  - Merges newly discovered terrain with stable bounding box
--  - Returns table with stableMin/Max + absoluteMin + gridSize

function GridConfig.calculateGlobalBounds(terrains)
	-- Step 1: find local bounding box from these terrains
	local localMinX = math.huge
	local localMinZ = math.huge
	local localMaxX = -math.huge
	local localMaxZ = -math.huge

	for i, terrain in ipairs(terrains) do
		local minX, minZ = GridConfig.calculateCoords(terrain)
		local maxX = minX + terrain.Size.X
		local maxZ = minZ + terrain.Size.Z

		-- Debug
		--[[print(string.format(
			"Terrain %d: minX=%.2f, minZ=%.2f, maxX=%.2f, maxZ=%.2f",
			i, minX, minZ, maxX, maxZ
			))]]

		if minX < localMinX then localMinX = minX end
		if minZ < localMinZ then localMinZ = minZ end
		if maxX > localMaxX then localMaxX = maxX end
		if maxZ > localMaxZ then localMaxZ = maxZ end
	end

	-- Step 2: merge local bounding box with the stable bounding box
	if stableMinX == nil then
		-- First time: set stable to local
		stableMinX = localMinX
		stableMinZ = localMinZ
		stableMaxX = localMaxX
		stableMaxZ = localMaxZ

		absoluteMinX = localMinX
		absoluteMinZ = localMinZ
	else
		-- Keep stableMinX/stableMinZ where they are, so old zones don't shift
		-- but if the new localMin is even smaller, we record it in absoluteMinX
		if localMinX < absoluteMinX then
			absoluteMinX = localMinX
		end
		if localMinZ < absoluteMinZ then
			absoluteMinZ = localMinZ
		end

		-- stableMaxX and stableMaxZ can grow if new terrain extends the map
		if localMaxX > stableMaxX then
			stableMaxX = localMaxX
		end
		if localMaxZ > stableMaxZ then
			stableMaxZ = localMaxZ
		end
	end

	-- Step 3: compute the stable bounding box's grid size
	local gridSizeX = math.ceil((stableMaxX - stableMinX) / GridConfig.GRID_SIZE)
	local gridSizeZ = math.ceil((stableMaxZ - stableMinZ) / GridConfig.GRID_SIZE)

	--[[ Debug
	print(string.format(
		"Stable Anchor: minX=%.2f, minZ=%.2f, maxX=%.2f, maxZ=%.2f",
		stableMinX, stableMinZ, stableMaxX, stableMaxZ
		))
	print(string.format(
		"Absolute Bounds: minX=%.2f, minZ=%.2f  (for reference)",
		absoluteMinX, absoluteMinZ
		))
	print(string.format(
		"Grid Size: gridSizeX=%d, gridSizeZ=%d",
		gridSizeX, gridSizeZ
		))
]]
	-- Return stable bounding box + absoluteMin for reference
	return {
		-- The stable bounding box used for coordinate conversions
		minX = stableMinX,
		minZ = stableMinZ,
		maxX = stableMaxX,
		maxZ = stableMaxZ,

		-- The actual farthest-left/bottom discovered (could be < stableMin)
		absMinX = absoluteMinX,
		absMinZ = absoluteMinZ,

		-- The stable bounding box's grid dimension
		gridSizeX = gridSizeX,
		gridSizeZ = gridSizeZ,
	}
end


-- Reset if you ever need a brand-new anchor

function GridConfig.resetStableBounds()
	stableMinX, stableMinZ = nil, nil
	stableMaxX, stableMaxZ = nil, nil
	absoluteMinX, absoluteMinZ = nil, nil
end

return GridConfig
