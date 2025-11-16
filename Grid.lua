local GridConfig = {}
GridConfig.__index = GridConfig

-- Configuration
GridConfig.GRID_SIZE = 4
GridConfig.Y_OFFSET = 0.4

-- Each plot needs its own set of cached bounds so multiplayer players
-- never stomp each other.  We store those bounds keyed by the plot model.
local function newContext()
	return {
		stableMinX = nil,
		stableMinZ = nil,
		stableMaxX = nil,
		stableMaxZ = nil,
		absoluteMinX = nil,
		absoluteMinZ = nil,
		axisDirX    = 1,
		axisDirZ    = 1,
	}
end

local plotContexts = setmetatable({}, { __mode = "k" })
local defaultContext = newContext()

local function isPlayerPlot(model)
	if not (model and model:IsA("Model")) then
		return false
	end

	if model:GetAttribute("IsPlayerPlot") == true then
		return true
	end

	local parent = model.Parent
	if parent and parent.Name == "PlayerPlots" then
		return true
	end

	local name = model.Name
	return typeof(name) == "string" and string.sub(name, 1, 5) == "Plot_"
end

local function findPlotAncestor(instance)
	local current = instance
	while current do
		if isPlayerPlot(current) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function getContextForPlot(plot)
	if plot then
		local ctx = plotContexts[plot]
		if not ctx then
			ctx = newContext()
			plotContexts[plot] = ctx
		end
		return ctx
	end
	return defaultContext
end

local function getContextFromInstance(instance)
	return getContextForPlot(findPlotAncestor(instance))
end

local function getContextFromTerrains(terrains)
	if type(terrains) ~= "table" then
		return defaultContext
	end

	for _, inst in ipairs(terrains) do
		if typeof(inst) == "Instance" then
			local plot = findPlotAncestor(inst)
			if plot then
				return getContextForPlot(plot)
			end
		end
	end

	return defaultContext
end

local function normalizeAxisDir(value)
	if value == -1 then
		return -1
	end
	return 1
end

function GridConfig.setAxisDirectionsForPlot(plot, axisDirX, axisDirZ)
	if not plot then
		return
	end

	local ctx = getContextForPlot(plot)
	ctx.axisDirX = normalizeAxisDir(axisDirX)
	ctx.axisDirZ = normalizeAxisDir(axisDirZ)
end

function GridConfig.getAxisDirectionsForPlot(plot)
	local ctx = getContextForPlot(plot)
	return ctx.axisDirX or 1, ctx.axisDirZ or 1
end

function GridConfig.getAxisDirectionsForInstance(instance)
	local ctx = getContextFromInstance(instance)
	return ctx.axisDirX or 1, ctx.axisDirZ or 1
end

function GridConfig.setStableAnchorFromPart(part)
	if not part then
		return
	end

	local ctx = getContextFromInstance(part)
	local anchorX = part.Position.X - GridConfig.GRID_SIZE * 0.5
	local anchorZ = part.Position.Z - GridConfig.GRID_SIZE * 0.5

	ctx.stableMinX = anchorX
	ctx.stableMinZ = anchorZ
	ctx.stableMaxX = anchorX
	ctx.stableMaxZ = anchorZ
	ctx.absoluteMinX = anchorX
	ctx.absoluteMinZ = anchorZ
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
	local ctx = getContextFromTerrains(terrains)

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

	if localMinX == math.huge then
		-- No terrains provided; fall back to whatever the context already knows.
		localMinX = ctx.stableMinX or 0
		localMinZ = ctx.stableMinZ or 0
		localMaxX = ctx.stableMaxX or localMinX
		localMaxZ = ctx.stableMaxZ or localMinZ
	end

	-- Step 2: merge local bounding box with the stable bounding box
	if ctx.stableMinX == nil then
		ctx.stableMinX = localMinX
		ctx.stableMinZ = localMinZ
		ctx.stableMaxX = localMaxX
		ctx.stableMaxZ = localMaxZ

		ctx.absoluteMinX = localMinX
		ctx.absoluteMinZ = localMinZ
	else
		-- Keep stableMinX/stableMinZ where they are, so old zones don't shift
		ctx.absoluteMinX = math.min(ctx.absoluteMinX or localMinX, localMinX)
		ctx.absoluteMinZ = math.min(ctx.absoluteMinZ or localMinZ, localMinZ)

		-- stableMaxX and stableMaxZ can grow if new terrain extends the map
		if localMaxX > ctx.stableMaxX then
			ctx.stableMaxX = localMaxX
		end
		if localMaxZ > ctx.stableMaxZ then
			ctx.stableMaxZ = localMaxZ
		end
	end

	local stableMinX = ctx.stableMinX
	local stableMinZ = ctx.stableMinZ
	local stableMaxX = ctx.stableMaxX
	local stableMaxZ = ctx.stableMaxZ

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
		absMinX = ctx.absoluteMinX or stableMinX,
		absMinZ = ctx.absoluteMinZ or stableMinZ,

		-- The stable bounding box's grid dimension
		gridSizeX = gridSizeX,
		gridSizeZ = gridSizeZ,
	}
end


-- Reset if you ever need a brand-new anchor

function GridConfig.resetStableBounds(plot)
	if plot then
		plotContexts[plot] = nil
		return
	end

	plotContexts = setmetatable({}, { __mode = "k" })
	defaultContext = newContext()
end

return GridConfig
