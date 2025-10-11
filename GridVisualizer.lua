--THIS IS THE PRIMARY USER INPUT LOCAL SCRIPT THEY CLICK A BUTTON, IT PROBABLY OPENS THIS, THIS FIRES TO EVERYTHING ELSE LIKELY
-- Services THIS HAS GHOSTING
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui") -- Added: fallback notification path

-- Remote Events
local RemoteEventsFolder = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents")
local displayGridEvent = RemoteEventsFolder:WaitForChild("DisplayGrid")
local gridSelectionEvent = RemoteEventsFolder:WaitForChild("GridSelection")
local buildRoadEvent = RemoteEventsFolder:WaitForChild("BuildRoad")
local buildPipeEvent = RemoteEventsFolder:WaitForChild("BuildPipe")
local placeWaterTowerEvent = RemoteEventsFolder:WaitForChild("PlaceWaterTower")
local plotAssignedEvent = RemoteEventsFolder:WaitForChild("PlotAssigned")
local ExecuteCommandEvent = RemoteEventsFolder:WaitForChild("ExecuteCommand")
local notifyLockedEvent = RemoteEventsFolder:WaitForChild("NotifyLocked")
local UIUpdateEvent = RemoteEventsFolder:WaitForChild("UpdateStatsUI")
local Balancing = ReplicatedStorage:WaitForChild("Balancing")
local Balance = require(Balancing:WaitForChild("BalanceEconomy"))
local unlocksUpdatedEvent = RemoteEventsFolder:WaitForChild("UnlocksUpdated")
local requestAllUnlocksRF = RemoteEventsFolder:WaitForChild("RequestAllUnlocks")
local PlotAssignedAck = RemoteEventsFolder:WaitForChild("PlotAssignedAck")

-- Modules
local GridScripts = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Grid")
local GridConfig = require(GridScripts:WaitForChild("GridConfig"))
local GridUtil = require(GridScripts:WaitForChild("GridUtil"))

-- For spawning the Water Tower ghost
local BuildingGhostManager = require(ReplicatedStorage.Scripts.BuildingManager.BuildingGhostManager)

-- Player
local player = Players.LocalPlayer
local PlayerGui = player.PlayerGui
local mouse = player:GetMouse()

local GridSelectionBox = Instance.new("SelectionBox")
GridSelectionBox.Color3 = Color3.fromRGB(179, 190, 255)
GridSelectionBox.Parent = PlayerGui

-- dependencies
local BuildMenuUI = require(PlayerGui:WaitForChild("BuildMenu"):WaitForChild("Logic"))

local playerBalance = 0
local COST_PER_GRID = Balance.costPerGrid

-- References to the player's plot and terrain segments
local playerPlot = nil
local terrains = {} -- Table of terrains (segments unlocked)

-- Global grid bounds (calculated from terrains)
local globalBounds = nil

-- Configuration
local GRID_SIZE = GridConfig.GRID_SIZE
local GRID_TRANSPARENCY = 0.5

-- Tables for grid parts
local gridParts = {}
local gridLookup = {}  
local cardinalGridParts = {}
local metroEntranceCells = {}
local metroTunnelCells = {}

local function _countKeys(t)
	local c = 0
	for _ in pairs(t) do c += 1 end
	return c
end

local function _isEntranceCell(x, z)
	return metroEntranceCells[string.format("%d,%d", x, z)] == true
end

local function _key(x, z) return string.format("%d,%d", x, z) end



-- Map a world position to the nearest currently-rendered GridSquare (uses gridParts)
local function _nearestGridKeyFromWorld(pos)
	local bestKey, bestDist = nil, math.huge
	local px, pz = pos.X, pos.Z
	for _, part in ipairs(gridParts) do
		-- gridParts only has GridSquare/CardinalGridSquare we created
		if part.Name == "GridSquare" then
			local gx = part:GetAttribute("GridX")
			local gz = part:GetAttribute("GridZ")
			if gx and gz then
				local dx = part.Position.X - px
				local dz = part.Position.Z - pz
				local d2 = dx*dx + dz*dz
				if d2 < bestDist then
					bestDist = d2
					bestKey  = string.format("%d,%d", gx, gz)
				end
			end
		end
	end
	return bestKey
end

local function _isTunnelCell(x, z)
	return metroTunnelCells[_key(x, z)] == true
end
local function _isAdjacentToTunnel(x, z)
	return metroTunnelCells[_key(x+1, z)] or
		metroTunnelCells[_key(x-1, z)] or
		metroTunnelCells[_key(x, z+1)] or
		metroTunnelCells[_key(x, z-1)] or false
end

local function _isValidMetroStart(x, z)
	local hasEntrances = _countKeys(metroEntranceCells) > 0
	local hasTunnels   = _countKeys(metroTunnelCells)   > 0
	local onEntrance   = _isEntranceCell(x, z)
	local nearTunnel   = _isAdjacentToTunnel(x, z)

	if hasTunnels then
		return onEntrance or nearTunnel
	elseif hasEntrances then
		return onEntrance
	else
		return true
	end
end

local function findMetroTunnels()
	table.clear(metroTunnelCells)
	if not playerPlot then
		warn("[Metro] findMetroTunnels: no playerPlot yet")
		return
	end
	local tunnelsFolder = playerPlot:FindFirstChild("MetroTunnels")
	if not tunnelsFolder then
		warn("[Metro] findMetroTunnels: MetroTunnels folder not found under plot")
		return
	end

	for _, zoneFolder in ipairs(tunnelsFolder:GetChildren()) do
		-- MetroTunnelZone_<uid>_<n>
		if zoneFolder:IsA("Folder") and zoneFolder.Name:match("^MetroTunnelZone_") then
			for _, inst in ipairs(zoneFolder:GetDescendants()) do
				if inst:IsA("BasePart") then
					local gx = inst:GetAttribute("GridX")
					local gz = inst:GetAttribute("GridZ")
					local key
					if gx and gz then
						key = _key(gx, gz)
					else
						key = _nearestGridKeyFromWorld(inst.Position) -- snap to nearest visible grid
					end
					if key then
						metroTunnelCells[key] = true
					end
				end
			end
		end
	end

	print(("[Metro] Tunnel cells mapped: %d"):format(_countKeys(metroTunnelCells)))
end

-- Scan Plot_<uid>/Buildings/Populated/Zone_*/Model "Metro Entrance"
local function findMetroEntrances()
	table.clear(metroEntranceCells)
	if not playerPlot then
		warn("[Metro] findMetroEntrances: no playerPlot yet")
		return
	end

	local buildings = playerPlot:FindFirstChild("Buildings")
	local populated = buildings and buildings:FindFirstChild("Populated")
	if not populated then
		warn("[Metro] findMetroEntrances: Buildings/Populated not found")
		return
	end

	for _, zoneFolder in ipairs(populated:GetChildren()) do
		-- Zone folders are named "Zone_<uid>_<n>"
		if zoneFolder:IsA("Folder") and zoneFolder.Name:match("^Zone_") then
			for _, inst in ipairs(zoneFolder:GetChildren()) do
				if inst:IsA("Model") and string.lower(inst.Name) == "metro entrance" then
					local pp = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
					if pp then
						-- Prefer attributes if present; otherwise snap to nearest rendered grid cell
						local gx = pp:GetAttribute("GridX")
						local gz = pp:GetAttribute("GridZ")
						local key
						if gx and gz then
							key = string.format("%d,%d", gx, gz)
						else
							key = _nearestGridKeyFromWorld(pp.Position)
						end
						if key then
							metroEntranceCells[key] = true
						else
							warn("[Metro] Could not map Metro Entrance to a grid cell (no nearby grid square?)")
						end
					else
						warn("[Metro] Metro Entrance has no PrimaryPart/BasePart")
					end
				end
			end
		end
	end

	print(("[Metro] Entrances found (mapped): %d"):format(_countKeys(metroEntranceCells)))
end

-- Variables for selection and mode
local currentMode = nil
local selectedCoord = nil
local selectedCoords = {}

-- Debounce
local debounce = false
local DEBOUNCE_TIME = 0.5 -- seconds

-- Ghost model variables
local ghostModel = nil
local moveConnection = nil

-- Track rotation for the ghost model
local buildingRotation = 0 

-- Table for currently highlighted squares (for footprints, etc.)
local highlightSquares = {}

local playerBuildings = nil
local playerBuildingsOrigParent = nil

local function printTable(t, indent)
	indent = indent or ""
	for k, v in pairs(t) do
		if type(v) == "table" then
			print(indent .. tostring(k) .. ":")
			printTable(v, indent .. "  ")
		else
			print(indent .. tostring(k) .. " = " .. tostring(v))
		end
	end
end

local function parseAbbrev(str)
	-- “50k” → 50000, “1.2m” → 1200000
	local num, suffix = tonumber(str:match("^([%d%.]+)")), str:match("([kmbt])$")
	if not num then return 0 end
	local mults = { k = 1e3, m = 1e6, b = 1e9, t = 1e12 }
	return num * (mults[suffix] or 1)
end

-- Added: normalize any numeric/string cost to a number
local function asNumber(val)
	if type(val) == "number" then
		return val
	elseif type(val) == "string" then
		return tonumber(val) or parseAbbrev(val) or 0
	else
		return 0
	end
end

UIUpdateEvent.OnClientEvent:Connect(function(stats)
	if type(stats.balance) == "string" then
		playerBalance = parseAbbrev(stats.balance)
	else
		playerBalance = stats.balance or 0
	end
end)

-- Added: unified way to open purchase / insufficient funds UI for both buildings & zones
local function openPremiumShop()
	local pg = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui")

	-- Preferred (module-driven) shop
	local premiumShopGui = pg:FindFirstChild("PremiumShopGui")
	if premiumShopGui and premiumShopGui:FindFirstChild("Logic") then
		local ok, mod = pcall(function()
			return require(premiumShopGui.Logic)
		end)
		if ok and mod and type(mod.OnShow) == "function" then
			mod.OnShow() -- keep signature same as your building path
			return true
		end
	end

	-- Legacy ScreenGui fallback
	local legacyShop = pg:FindFirstChild("PremiumShop")
	if legacyShop then
		legacyShop.Enabled = true
		return true
	end

	-- Last-resort feedback so players always see something
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = "Not enough cash",
			Text = "You don't have enough funds for this action.",
			Duration = 4
		})
	end)
	return false
end

local zoneHighlights = {}

local function clearZoneHighlights()
	for _, part in ipairs(zoneHighlights) do
		part.Color        = part:GetAttribute("BaseColor") or part.Color
		part.Transparency = GRID_TRANSPARENCY
	end
	zoneHighlights = {}
end

local function highlightZoneRange(startCoord)
	clearZoneHighlights()

	if not startCoord or type(startCoord.x) ~= "number" then
		return
	end

	-- Changed: normalize cost to number (supports "50k" style configs too)
	local cost = asNumber(Balance.costPerGrid[currentMode])
	if cost <= 0 then return end

	local maxCells = math.floor(playerBalance / cost)
	if maxCells <= 0 then return end

	for _, part in ipairs(gridParts) do
		local gx, gz = part:GetAttribute("GridX"), part:GetAttribute("GridZ")

		-- **skip the first-click cell** so it stays red
		if gx == startCoord.x and gz == startCoord.z then
			-- do nothing
		else
			local w = math.abs(gx - startCoord.x) + 1
			local d = math.abs(gz - startCoord.z) + 1
			if w * d <= maxCells then
				part.Color        = Color3.new(1, 1, 0)
				part.Transparency = 0.3
				table.insert(zoneHighlights, part)
			end
		end
	end
end


-- ROTATION HELPER

local function rotateGhost()
	buildingRotation = (buildingRotation + 90) % 360
end


-- CLEAR FOOTPRINT HIGHLIGHTS

local function clearFootprintHighlights()
	for _, part in ipairs(highlightSquares) do
		-- Optionally restore color/transparency
		part.Color = part:GetAttribute("BaseColor") or part.Color
		part.Transparency = GRID_TRANSPARENCY
	end
	highlightSquares = {}
end


-- HIGHLIGHT FOOTPRINT

local function highlightFootprint(gx, gz, width, depth)
	clearFootprintHighlights()

	for x = gx, gx + width - 1 do
		for z = gz, gz + depth - 1 do
			local key = x .. "," .. z
			local part = gridLookup[key]
			if part then
				-- Color these squares differently, e.g. yellow
				part.Color = Color3.new(1, 1, 0)
				part.Transparency = 0.3
				table.insert(highlightSquares, part)
			end
		end
	end
end


local function rebuildTerrainsFromUnlocks(unlockData)
	if not playerPlot then return end
	terrains = {}

	local unlocksFolder = playerPlot:FindFirstChild("Unlocks")
	if unlocksFolder then
		for _, zone in ipairs(unlocksFolder:GetChildren()) do
			local zoneName = zone.Name
			if unlockData and unlockData[zoneName] then
				for _, child in ipairs(zone:GetChildren()) do
					if child.Name:match("^Segment%d+$") then
						table.insert(terrains, child)
					end
				end
			end
		end
	end

	local testTerrain = playerPlot:FindFirstChild("TestTerrain")
	if testTerrain then
		table.insert(terrains, testTerrain)
	end

	if #terrains == 0 then
		warn("GridVisualizer: No unlocked terrain segments in this plot.")
	else
		print("GridVisualizer: Terrain segments assigned ("..tostring(#terrains)..")")
	end
end

-- GET BUILDING FOOTPRINT (WITH ROTATION)
--  If rotation is 90° or 270°, we swap X and Z to account for bounding box

local function getBuildingFootprint(model, rotationDegrees)
	if not model or not model.PrimaryPart then
		return 1, 1
	end
	rotationDegrees = rotationDegrees or 0
	local sizeX = model.PrimaryPart.Size.X
	local sizeZ = model.PrimaryPart.Size.Z

	-- For 90 or 270, swap
	local modRotation = rotationDegrees % 180
	local w, d
	if modRotation == 90 then
		w = math.ceil(sizeZ / GRID_SIZE)
		d = math.ceil(sizeX / GRID_SIZE)
	else
		w = math.ceil(sizeX / GRID_SIZE)
		d = math.ceil(sizeZ / GRID_SIZE)
	end

	return w, d
end




-- MOVE GHOST MODEL (APPLYING ROTATION)

local function startGhostMovement()
	if moveConnection then
		moveConnection:Disconnect()
		moveConnection = nil
	end

	moveConnection = RunService.RenderStepped:Connect(function()
		if ghostModel and ghostModel.PrimaryPart then
			local target = mouse.Target
			if target and (target.Name == "GridSquare" or target.Name == "CardinalGridSquare") then
				local gx = target:GetAttribute("GridX")
				local gz = target:GetAttribute("GridZ")
				if gx and gz and globalBounds and terrains then

					local w, d = getBuildingFootprint(ghostModel, buildingRotation)
					-- Position the ghost's model
					local x, y, z = GridUtil.globalGridToWorldPosition(gx, gz, globalBounds, terrains)
					local offX = (w - 1) * GRID_SIZE * 0.5
					local offZ = (d - 1) * GRID_SIZE * 0.5
					local pivotOffset = CFrame.new(offX, 0, offZ)


					-- offset pivot from center back to the corner
					local half      = GRID_SIZE/2
					local cornerOff = CFrame.new(-half, 0, -half)

					ghostModel:SetPrimaryPartCFrame(
						CFrame.new(x, y, z)
							* pivotOffset
							* CFrame.Angles(0, math.rad(buildingRotation), 0)
					)
					-- Highlight squares (multi-cell footprint with rotation)

					highlightFootprint(gx, gz, w, d)
				else
					clearFootprintHighlights()
				end
			else
				clearFootprintHighlights()
			end
		end
	end)
end


-- STOP GHOST MOVEMENT AND REMOVE GHOST

local function removeGhost()
	if ghostModel then
		ghostModel:Destroy()
		ghostModel = nil
	end
	if moveConnection then
		moveConnection:Disconnect()
		moveConnection = nil
	end
	clearFootprintHighlights()
end


-- CLEAR FUNCTIONS

local function clearCardinalGrids()
	for _, part in ipairs(cardinalGridParts) do
		part:Destroy()
	end
	cardinalGridParts = {}
end

local function clearGrid()

	if playerBuildings then
		playerBuildings.Parent = playerBuildingsOrigParent
	end

	for _, part in ipairs(gridParts) do
		part:Destroy()
	end
	gridParts = {}
	gridLookup  = {}
end

local function clearAll()
	clearCardinalGrids()
	clearGrid()
	selectedCoord = nil
	selectedCoords = {}
end

local BE_DisableBuildMode = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents"):WaitForChild("DisableBuildMode")
BE_DisableBuildMode.Event:Connect(function()
	removeGhost()
	clearAll()
	currentMode = nil
end)

notifyLockedEvent.OnClientEvent:Connect(function(zoneType, requiredLevel)
	-- wipe anything that might already be on the screen
	removeGhost()
	clearAll()
	currentMode = nil

	-- show feedback – replace this with your own UI if you like
	warn(("%s is locked. Reach city level %d to unlock it."):format(zoneType, requiredLevel))
	-- you could also flash the button, open a popup, etc.
end)


-- CREATE GRID

local function createGrid(mode)
	if not terrains or #terrains == 0 then
		warn("GridVisualizer: No terrains are defined.")
		return
	end

	-- Calculate global bounds
	globalBounds = GridConfig.calculateGlobalBounds(terrains)

	print("=== globalBounds ===")
	printTable(globalBounds)
	print("====================")

	-- Clear existing grid parts
	for _, part in ipairs(gridParts) do
		part:Destroy()
	end
	gridParts = {}

	-- hide buildings
	--if mode == "WaterPipe" or mode == "PowerLines" then
	--	if not playerBuildings then
	--		local PlayerPlots = workspace:FindFirstChild("PlayerPlots")
	--		if PlayerPlots then
	--			local PlayerPlot = PlayerPlots:FindFirstChild("Plot_"..player.UserId)
	--			if PlayerPlot then
	--				playerBuildings = PlayerPlot:FindFirstChild("Buildings")
	--				if playerBuildings then
	--					playerBuildingsOrigParent = playerBuildings.Parent
	--				end
	--			end
	--		end
	--	end
	--	if playerBuildings then
	--		playerBuildings.Parent = ReplicatedStorage
	--	end
	--end

	-- Decide color
	local GRID_COLOUR = Color3.new(0, 1, 0)
	if mode == "DirtRoad" or mode == "Pavement" or mode == "Highway" or mode == "PowerLines" or mode == "MetroTunnel" then
		GRID_COLOUR = Color3.new(0, 1, 0)
	elseif mode == "WaterPipe" or mode == "WaterTower" then
		GRID_COLOUR = Color3.new(0, 0, 1)
	end

	local anchorMinX = globalBounds.minX
	local anchorMinZ = globalBounds.minZ
	local anchorMaxX = globalBounds.maxX
	local anchorMaxZ = globalBounds.maxZ

	local absMinX = globalBounds.absMinX
	local absMinZ = globalBounds.absMinZ

	local step = GRID_SIZE
	local totalWidthX = anchorMaxX - absMinX
	local totalWidthZ = anchorMaxZ - absMinZ

	local displayGridSizeX = math.ceil(totalWidthX / step)
	local displayGridSizeZ = math.ceil(totalWidthZ / step)

	-- Create/find a folder
	local gridFolder = workspace.PlayerPlots.GridParts

	-- Generate squares
	for i = 0, displayGridSizeX - 1 do
		for j = 0, displayGridSizeZ - 1 do
			local worldX = absMinX + (i + 0.5) * step
			local worldZ = absMinZ + (j + 0.5) * step

			local gridX = math.floor((worldX - anchorMinX) / step)
			local gridZ = math.floor((worldZ - anchorMinZ) / step)

			local finalWorldX, finalWorldY, finalWorldZ =
				GridUtil.globalGridToWorldPosition(gridX, gridZ, globalBounds, terrains)

			local gridPart = Instance.new("Part")
			gridPart.Size = Vector3.new(step, 0.2, step)
			gridPart.Position = Vector3.new(finalWorldX, finalWorldY, finalWorldZ)
			gridPart.Anchored = true
			gridPart.CanCollide = false
			gridPart.Color = GRID_COLOUR
			gridPart.Transparency = GRID_TRANSPARENCY
			gridPart.Name = "GridSquare"

			gridPart:SetAttribute("GridX", gridX)
			gridPart:SetAttribute("GridZ", gridZ)
			gridPart:SetAttribute("BaseColor", GRID_COLOUR)
			gridPart.Parent = gridFolder
			table.insert(gridParts, gridPart)

			gridLookup[gridX .. "," .. gridZ] = gridPart
		end
	end
	if mode == "MetroTunnel" then
		findMetroEntrances()
		findMetroTunnels()

		-- highlight entrances (yellow)
		for key, _ in pairs(metroEntranceCells) do
			local part = gridLookup[key]
			if part then
				part.Color = Color3.fromRGB(255, 220, 0)
				part.Transparency = 0.25
			end
		end

		-- highlight allowed starts adjacent to tunnels (orange); don't overwrite entrance tint
		for key, _ in pairs(metroTunnelCells) do
			local gx, gz = key:match("^(-?%d+),(-?%d+)$")
			gx, gz = tonumber(gx), tonumber(gz)
			if gx and gz then
				local neighbors = { _key(gx+1, gz), _key(gx-1, gz), _key(gx, gz+1), _key(gx, gz-1) }
				for _, nk in ipairs(neighbors) do
					if not metroTunnelCells[nk] and not metroEntranceCells[nk] then
						local np = gridLookup[nk]
						if np then
							np.Color = Color3.fromRGB(255, 160, 0)
							np.Transparency = 0.25
						end
					end
				end
			end
		end
	end
end


-- SHOW CARDINAL GRIDS

local function showCardinalGrids(startCoord)
	if not terrains or #terrains == 0 then
		warn("GridVisualizer: No terrains are defined.")
		return
	end

	clearCardinalGrids()
	local step = GRID_SIZE

	local minGridX = math.floor((globalBounds.absMinX - globalBounds.minX) / step)
	local maxGridX = math.floor((globalBounds.maxX - globalBounds.minX) / step)
	local minGridZ = math.floor((globalBounds.absMinZ - globalBounds.minZ) / step)
	local maxGridZ = math.floor((globalBounds.maxZ - globalBounds.minZ) / step)

	local directions = {
		{1, 0},   -- East
		{-1, 0},  -- West
		{0, 1},   -- South
		{0, -1},  -- North
	}

	local cardinalFolder = playerPlot and playerPlot.Parent:FindFirstChild("CardinalGridParts")
	if not cardinalFolder then
		cardinalFolder = Instance.new("Folder")
		cardinalFolder.Name = "CardinalGridParts"
		if playerPlot then
			cardinalFolder.Parent = playerPlot.Parent
		else
			cardinalFolder.Parent = Workspace
		end
	end

	for _, dir in ipairs(directions) do
		local dx, dz = dir[1], dir[2]
		local x, z = startCoord.x, startCoord.z

		while true do
			x = x + dx
			z = z + dz
			if x < minGridX or x > maxGridX or z < minGridZ or z > maxGridZ then
				break
			end

			local worldX, worldY, worldZ =
				GridUtil.globalGridToWorldPosition(x, z, globalBounds, terrains)

			local gridPart = Instance.new("Part")
			gridPart.Size = Vector3.new(step, 0.2, step)
			gridPart.Position = Vector3.new(worldX, worldY + 0.05, worldZ)
			gridPart.Anchored = true
			gridPart.CanCollide = false
			gridPart.Color = Color3.new(1, 1, 0)
			gridPart.Transparency = 0.3
			gridPart.Material = Enum.Material.Neon
			gridPart.Name = "CardinalGridSquare"

			gridPart:SetAttribute("GridX", x)
			gridPart:SetAttribute("GridZ", z)
			gridPart.Parent = cardinalFolder
			table.insert(cardinalGridParts, gridPart)
		end
	end
end


-- INPUT HANDLER
RunService.Heartbeat:Connect(function()
	local target = mouse.Target
	if target and target:IsA("Part") and (target.Name == "GridSquare" or target.Name == "CardinalGridSquare") then
		GridSelectionBox.Adornee = target
	else
		GridSelectionBox.Adornee = nil
	end
end)

local targetMobile = nil
local function click(target)
	--warn("click")
	if target and target:IsA("Part") and (target.Name == "GridSquare" or target.Name == "CardinalGridSquare") then
		local x_grid = target:GetAttribute("GridX")
		local z_grid = target:GetAttribute("GridZ")
		if not x_grid or not z_grid then
			warn("GridVisualizer: GridSquare missing GridX or GridZ.")
			return
		end

		print("Clicked grid coords: x =", x_grid, "z =", z_grid)

		if currentMode == "DirtRoad" or currentMode == "Pavement" or currentMode == "Highway" then
			if not selectedCoord then
				selectedCoord = {x = x_grid, z = z_grid}
				print("Road start:", selectedCoord.x, selectedCoord.z)
				target.Color = Color3.new(1, 0, 0)
				showCardinalGrids(selectedCoord)
			else
				if (target.Name == "CardinalGridSquare" or target.Name == "GridSquare" and selectedCoord.x == x_grid and selectedCoord.z == z_grid) then
					local endCoord = {x = x_grid, z = z_grid}
					print("Road end:", endCoord.x, endCoord.z)
					ExecuteCommandEvent:FireServer("BuildRoad", selectedCoord, endCoord, currentMode)
					clearAll()
					--buildModeToggleEvent:Fire(false)
					--BuildMenuUI.OnHide()
				else
					print("Please select a cardinal grid.")
				end
			end

		elseif currentMode == "WaterPipe" then
			if not selectedCoord then
				selectedCoord = {x = x_grid, z = z_grid}
				print("WaterPipe start:", selectedCoord.x, selectedCoord.z)
				target.Color = Color3.new(1, 0, 0)
				showCardinalGrids(selectedCoord)
			else
				if (target.Name == "CardinalGridSquare" or target.Name == "GridSquare" and selectedCoord.x == x_grid and selectedCoord.z == z_grid) then
					local endCoord = {x = x_grid, z = z_grid}
					print("WaterPipe end:", endCoord.x, endCoord.z)
					buildPipeEvent:FireServer(selectedCoord, endCoord, currentMode)
					clearAll()
					--buildModeToggleEvent:Fire(false)
					--BuildMenuUI.OnHide()
				else
					print("Please select a cardinal grid.")
				end
			end

		elseif currentMode == "PowerLines" then
			if not selectedCoord then
				selectedCoord = {x = x_grid, z = z_grid}
				print("PowerLines start:", selectedCoord.x, selectedCoord.z)
				target.Color = Color3.new(1, 0, 0)
				showCardinalGrids(selectedCoord)
			else
				if (target.Name == "CardinalGridSquare" or target.Name == "GridSquare" and selectedCoord.x == x_grid and selectedCoord.z == z_grid) then
					local endCoord = {x = x_grid, z = z_grid}
					print("PowerLines end:", endCoord.x, endCoord.z)
					ExecuteCommandEvent:FireServer("BuildPowerLine", selectedCoord, endCoord, currentMode)
					clearAll()
					--buildModeToggleEvent:Fire(false)
					--BuildMenuUI.OnHide()
				else
					print("Please select a cardinal grid.")
				end
			end
		elseif currentMode == "MetroTunnel" then
			if not selectedCoord then
				-- refresh scans
				findMetroEntrances()
				findMetroTunnels()

				local hasEntrances = _countKeys(metroEntranceCells) > 0
				local hasTunnels   = _countKeys(metroTunnelCells)   > 0
				local onEntrance   = _isEntranceCell(x_grid, z_grid)
				local nearTunnel   = _isAdjacentToTunnel(x_grid, z_grid)

				-- Rules:
				-- - If tunnels exist: allow start on an entrance OR adjacent to any tunnel (N/E/S/W).
				-- - If no tunnels but entrances exist: must start on an entrance.
				-- - If neither exists: unrestricted.
				if hasTunnels then
					if not (onEntrance or nearTunnel) then
						warn("Metro: start on an Entrance or next to an existing tunnel.")
						pcall(function()
							StarterGui:SetCore("SendNotification", {
								Title = "Metro",
								Text = "Start on an Entrance or next to a Metro tunnel.",
								Duration = 3
							})
						end)
						return
					end
				elseif hasEntrances then
					if not onEntrance then
						warn("MetroTunnel: start must be on a Metro Entrance.")
						pcall(function()
							StarterGui:SetCore("SendNotification", {
								Title = "Metro",
								Text = "Start your tunnel on a Metro Entrance.",
								Duration = 3
							})
						end)
						return
					end
				end

				selectedCoord = {x = x_grid, z = z_grid}
				print("MetroTunnel start:", selectedCoord.x, selectedCoord.z)
				target.Color = Color3.new(1, 0, 0)
				showCardinalGrids(selectedCoord)
			else
				if (target.Name == "CardinalGridSquare" or target.Name == "GridSquare" and selectedCoord.x == x_grid and selectedCoord.z == z_grid) then
					local startCoord = selectedCoord
					local endCoord   = {x = x_grid, z = z_grid}

					-- guarantee the *first* param we send is a valid metro start
					if not _isValidMetroStart(startCoord.x, startCoord.z) and _isValidMetroStart(endCoord.x, endCoord.z) then
						startCoord, endCoord = endCoord, startCoord
					end

					print("MetroTunnel end:", endCoord.x, endCoord.z)
					ExecuteCommandEvent:FireServer("BuildMetroTunnel", startCoord, endCoord, currentMode)
					clearAll()
				else
					print("Please select a cardinal grid.")
				end
			end

		elseif BuildingGhostManager.isGhostable(currentMode) then
			local coord = {x = x_grid, z = z_grid}
			local w, d = BuildingGhostManager.getFootprint(ghostModel, buildingRotation)
			local endCoord = {x = coord.x + w - 1, z = coord.z + d - 1}

			-- compute total cost (normalized)
			local totalCost = asNumber(Balance.costPerGrid[currentMode])

			-- if they can't afford it, open PremiumShop and bail
			if playerBalance < totalCost then
				openPremiumShop()
				removeGhost()
				clearAll()
				currentMode = nil
				return
			end

			-- otherwise proceed with placement
			print("Placing", currentMode, "from:", coord.x, coord.z, "to", endCoord.x, endCoord.z)
			ExecuteCommandEvent:FireServer("BuildZone", coord, endCoord, currentMode, buildingRotation)
			target.Color = Color3.new(0, 0, 1)
			removeGhost()
			clearAll()
			currentMode = nil
			--buildModeToggleEvent:Fire(false)
			BuildMenuUI.OnHide()
		else
			-- Generic "BuildZone" path (e.g., Residential/Commercial/etc.)
			table.insert(selectedCoords, {x = x_grid, z = z_grid})
			print("Zone selection: Coord added:", x_grid, z_grid)
			target.Color = Color3.new(1, 0, 0)

			highlightZoneRange(selectedCoords[1])

			if #selectedCoords == 2 then
				-- 1) compute rectangle size in cells
				local width  = math.abs(selectedCoords[2].x - selectedCoords[1].x) + 1
				local depth  = math.abs(selectedCoords[2].z - selectedCoords[1].z) + 1

				-- 2) compute total cost (normalized)
				local costPerCell = asNumber(Balance.costPerGrid[currentMode])
				local totalCost   = width * depth * costPerCell

				-- 3) if they can’t afford it, open PremiumShop instead
				if playerBalance < totalCost then
					openPremiumShop()

					-- reset selection
					selectedCoords = {}
					clearZoneHighlights()
					clearGrid()
					currentMode = nil
					return
				end

				-- 4) otherwise proceed with the build
				ExecuteCommandEvent:FireServer("BuildZone", selectedCoords[1], selectedCoords[2], currentMode)
				selectedCoords = {}
				clearZoneHighlights()
				clearGrid()
				--buildModeToggleEvent:Fire(false)
				BuildMenuUI.OnHide()
			end
		end
	end
end

ReplicatedStorage.Events.BindableEvents.MobileClick.Event:Connect(function()
	click(targetMobile)
end)


local function onInputBegan(input, gameProcessed)
	if gameProcessed and input.KeyCode ~= Enum.KeyCode.ButtonA then return end
	if debounce then return end

	debounce = true
	task.delay(DEBOUNCE_TIME, function()
		debounce = false
	end)

	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonA then
		click(mouse.Target)

	elseif input.UserInputType == Enum.UserInputType.Touch then
		targetMobile = mouse.Target
	end
end


-- CANCEL & ROTATE SHORTCUTS

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	-- If R is pressed, rotate the ghost
	if input.KeyCode == Enum.KeyCode.R then
		if ghostModel then
			rotateGhost()
		end
	end

	-- If X is pressed, cancel
	if input.KeyCode == Enum.KeyCode.X then
		print("Cancel selection, clearing grid.")
		removeGhost()
		clearAll()
		currentMode = nil
	end
end)


-- CONNECT MAIN INPUT

UserInputService.InputBegan:Connect(onInputBegan)


-- DISPLAY GRID EVENT

displayGridEvent.OnClientEvent:Connect(function(mode)

	removeGhost()
	clearAll()

	currentMode = mode
	print("Displaying grid for mode:", mode)
	createGrid(mode)

	local newGhost = BuildingGhostManager.getGhostModel(mode)
	if newGhost then
		ghostModel = newGhost
		ghostModel.Parent = Workspace
		startGhostMovement()
	end

end)



-- PLOT ASSIGNED EVENT

plotAssignedEvent.OnClientEvent:Connect(function(plotName, unlockData)
	PlotAssignedAck:FireServer()
	print("GridVisualizer: Received plot name", plotName, unlockData)
	local plot
	repeat
		local playerPlotsFolder = Workspace:WaitForChild("PlayerPlots")
		plot = playerPlotsFolder:FindFirstChild(plotName)
		if not plot then
			task.wait(0.1)
		end
	until plot

	playerPlot = plot
	print("GridVisualizer: Found plot", playerPlot.Name)
	findMetroEntrances()

	local roadStart = playerPlot:WaitForChild("RoadStart", 5)
	if roadStart then
		GridConfig.setStableAnchorFromPart(roadStart)
	else
		warn(("GridVisualizer: RoadStart missing on plot %s – falling back to first‑terrain logic.")
			:format(plotName))
	end

	terrains = {}

	local liveUnlocks = {}
	local ok, result = pcall(function()
		return requestAllUnlocksRF:InvokeServer()
	end)
	if ok and type(result) == "table" then
		liveUnlocks = result
	else
		warn("GridVisualizer: RequestAllUnlocks failed; using initial snapshot")
		liveUnlocks = unlockData or {}
	end

	rebuildTerrainsFromUnlocks(liveUnlocks)
end)

unlocksUpdatedEvent.OnClientEvent:Connect(function(newUnlockTable)
	-- Update terrains immediately when unlocks change in-session
	rebuildTerrainsFromUnlocks(newUnlockTable)

	-- If a grid is currently shown (currentMode set), re-render it so the player sees the new area
	if currentMode then
		createGrid(currentMode)
	end
end)
