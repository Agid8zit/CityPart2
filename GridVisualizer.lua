-- Services THIS HAS GHOSTING
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui") -- Added: fallback notification path
local RunServiceScheduler = require(ReplicatedStorage.Scripts.RunServiceScheduler)

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

-- Onboarding bindables & alarm model
local BE = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents")
local BE_GridGuard  = BE:WaitForChild("OBGridGuard")        -- step specs: start/advance/stop
local BE_GuardFB    = BE:WaitForChild("OBGuardFeedback")    -- feedback: done/canceled
local BE_ToggleOB   = BE:WaitForChild("OnboardingToggle")   -- true/false

local FuncRS        = ReplicatedStorage:WaitForChild("FuncTestGroundRS")
local AlarmsFolder  = FuncRS:WaitForChild("Alarms")
local OnboardAlarmTemplate = AlarmsFolder:WaitForChild("OnboardAlarm")

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

local ZERO_EPSILON = 1e-6
local function normalizeGridIndex(value)
	if math.abs(value) < ZERO_EPSILON then
		return 0
	end
	return value
end

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
		if zoneFolder:IsA("Folder") and zoneFolder.Name:match("^MetroTunnelZone_") then
			for _, inst in ipairs(zoneFolder:GetDescendants()) do
				if inst:IsA("BasePart") then
					local gx = inst:GetAttribute("GridX")
					local gz = inst:GetAttribute("GridZ")
					local key
					if gx and gz then
						key = _key(gx, gz)
					else
						key = _nearestGridKeyFromWorld(inst.Position)
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
		if zoneFolder:IsA("Folder") and zoneFolder.Name:match("^Zone_") then
			for _, inst in ipairs(zoneFolder:GetChildren()) do
				if inst:IsA("Model") and string.lower(inst.Name) == "metro entrance" then
					local pp = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
					if pp then
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


-- === Guided step (reusable: line / rect / point) ============================
local guard = { active=false, spec=nil, stage=nil }
local guardMarks = {}  -- [BasePart] = true
local alarmModel = nil
local YELLOW = Color3.new(1,1,0)
local _pendingPointGuardPayload = nil

local function _gridPartAt(coord)
	if not coord then return nil end
	return gridLookup[tostring(coord.x)..","..tostring(coord.z)]
end

local function _mark(part)
	if not part then return end
	if part:GetAttribute("_GuardOrigR") == nil then
		local c = part.Color
		part:SetAttribute("_GuardOrigR", c.R)
		part:SetAttribute("_GuardOrigG", c.G)
		part:SetAttribute("_GuardOrigB", c.B)
		part:SetAttribute("_GuardOrigT", part.Transparency)
	end
	part.Color = YELLOW
	part.Transparency = 0.3
	guardMarks[part] = true
end

local function _unmarkAll()
	for p,_ in pairs(guardMarks) do
		local r = p:GetAttribute("_GuardOrigR")
		local g = p:GetAttribute("_GuardOrigG")
		local b = p:GetAttribute("_GuardOrigB")
		local t = p:GetAttribute("_GuardOrigT")
		if r and g and b then p.Color = Color3.new(r,g,b) end
		if t ~= nil then p.Transparency = t end
	end
	table.clear(guardMarks)
end

-- === visuals that extend to the next target =======================
local function _markLineInclusive(a, b)
	if not a or not b then return end
	if a.x == b.x then
		local step = (b.z >= a.z) and 1 or -1
		for z = a.z, b.z, step do
			_mark(_gridPartAt({ x = a.x, z = z }))
		end
	elseif a.z == b.z then
		local step = (b.x >= a.x) and 1 or -1
		for x = a.x, b.x, step do
			_mark(_gridPartAt({ x = x, z = a.z }))
		end
	end
end

local function _markRectInclusive(a, b)
	if not a or not b then return end
	local minx, maxx = math.min(a.x, b.x), math.max(a.x, b.x)
	local minz, maxz = math.min(a.z, b.z), math.max(a.z, b.z)
	for x = minx, maxx do
		for z = minz, maxz do
			_mark(_gridPartAt({ x = x, z = z }))
		end
	end
end

local function _destroyAlarm()
	if alarmModel then alarmModel:Destroy(); alarmModel = nil end
end

local function _spawnOrMoveAlarmAtCoord(coord)
	if not coord or not globalBounds then return end
	local x,y,z = GridUtil.globalGridToWorldPosition(coord.x, coord.z, globalBounds, terrains)
	if not alarmModel then
		local ok, m = pcall(function() return OnboardAlarmTemplate:Clone() end)
		if not ok or not m then return end
		alarmModel = m
		alarmModel.Parent = Workspace
	end
	alarmModel:PivotTo(CFrame.new(x, y + 0.5, z))
end

local function _clearGuardUI()
	_unmarkAll()
	_destroyAlarm()
end

local function _activateGuard(spec)
	guard.active = true
	guard.spec   = spec
	guard.stage  = (spec.kind == "line" and "await_first")
		or (spec.kind == "rect" and "await_first")
		or "await_point"

	-- If the correct grid is already visible, prime highlight + alarm now.
	if currentMode == spec.mode and next(gridLookup) ~= nil then
		local first = spec.from or spec.point or spec.one
		local p = _gridPartAt(first)
		if p then _mark(p) end
		_spawnOrMoveAlarmAtCoord(first)
	end
end

local function _finishGuard(done)
	local payload = guard.spec and { item = guard.spec.item or guard.spec.mode, mode = guard.spec.mode } or nil
	_clearGuardUI()
	guard.active=false; guard.spec=nil; guard.stage=nil
	if done then
		pcall(function() BE_GuardFB:Fire("done", payload) end)
	else
		pcall(function() BE_GuardFB:Fire("canceled", payload) end)
	end
end

-- Listen for guard steps (generic; NOT road-only)
BE_GridGuard.Event:Connect(function(action, spec)
	if action == "start" or action == "advance" then
		_clearGuardUI()
		_activateGuard(spec)
	elseif action == "stop" then
		-- Break the stop<->canceled echo loop with OnboardingController.
		_clearGuardUI()
		guard.active = false
		guard.spec   = nil
		guard.stage  = nil
		-- NOTE: do NOT call _finishGuard(false) here (which fires BE_GuardFB).
	end
end)

-- If onboarding is globally disabled (skip/completed), immediately release any active guard so
-- GridVisualizer stops gating player input.
BE_ToggleOB.Event:Connect(function(enabled)
	if enabled ~= false then
		return
	end
	_clearGuardUI()
	guard.active = false
	guard.spec   = nil
	guard.stage  = nil
end)
-- ============================================================================

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
			mod.OnShow()
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

-- [ADDED] ======== Line/Path cost helpers for Roads/Pipes/PowerLines =========
local function lineCellCount(startCoord, endCoord)
	-- Cardinal lines only; includes both endpoints
	if not startCoord or not endCoord then return 0 end
	local dx = math.abs((endCoord.x or 0) - (startCoord.x or 0))
	local dz = math.abs((endCoord.z or 0) - (startCoord.z or 0))
	return dx + dz + 1
end

local function costPerGridFor(mode)
	return asNumber(COST_PER_GRID[mode]) or 0
end

local function canAffordLine(startCoord, endCoord, mode)
	local cells = lineCellCount(startCoord, endCoord)
	local cpg   = costPerGridFor(mode)
	local total = cells * cpg
	return (playerBalance >= total), total, cells, cpg
end

-- [ADDED] Truncate a desired end to the maximum affordable length in the same cardinal direction.
local function truncateEndToBudget(startCoord, desiredEnd, mode)
	local cpg = costPerGridFor(mode)
	if cpg <= 0 then
		local cells = lineCellCount(startCoord, desiredEnd)
		return desiredEnd, cells, 0, false, false  -- end, cells, cost, cannotAffordAny, truncated
	end
	local affordableCells = math.floor(playerBalance / cpg)
	if affordableCells <= 0 then
		return nil, 0, 0, true, false
	end

	local desiredCells = lineCellCount(startCoord, desiredEnd)
	local cellsToBuild = math.min(desiredCells, affordableCells)

	if cellsToBuild == desiredCells then
		return desiredEnd, cellsToBuild, cellsToBuild * cpg, false, false
	else
		local dx, dz = 0, 0
		if desiredEnd.x ~= startCoord.x then
			dx = (desiredEnd.x > startCoord.x) and 1 or -1
		elseif desiredEnd.z ~= startCoord.z then
			dz = (desiredEnd.z > startCoord.z) and 1 or -1
		end
		local truncated = {
			x = startCoord.x + dx * (cellsToBuild - 1),
			z = startCoord.z + dz * (cellsToBuild - 1)
		}
		return truncated, cellsToBuild, cellsToBuild * cpg, false, true
	end
end
-- ============================================================================

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

	local costKey = (type(currentMode)=="string" and currentMode:sub(1,5)=="Flag:") and "Flags" or currentMode
	local cost = asNumber(Balance.costPerGrid[costKey])
	if cost <= 0 then return end

	local maxCells = math.floor(playerBalance / cost)
	if maxCells <= 0 then return end

	for _, part in ipairs(gridParts) do
		local gx, gz = part:GetAttribute("GridX"), part:GetAttribute("GridZ")

		if gx == startCoord.x and gz == startCoord.z then
			-- leave start red
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
local function getBuildingFootprint(model, rotationDegrees)
	if not model or not model.PrimaryPart then
		return 1, 1
	end
	rotationDegrees = rotationDegrees or 0
	local sizeX = model.PrimaryPart.Size.X
	local sizeZ = model.PrimaryPart.Size.Z

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
		moveConnection()
		moveConnection = nil
	end

	moveConnection = RunServiceScheduler.onRenderStepped(function()
		if ghostModel and ghostModel.PrimaryPart then
			local target = mouse.Target
			if target and (target.Name == "GridSquare" or target.Name == "CardinalGridSquare") then
				local gx = target:GetAttribute("GridX")
				local gz = target:GetAttribute("GridZ")
				if gx and gz and globalBounds and terrains then

					local w, d = getBuildingFootprint(ghostModel, buildingRotation)
					local x, y, z = GridUtil.globalGridToWorldPosition(gx, gz, globalBounds, terrains)
					local ax, az = GridConfig.getAxisDirectionsForPlot(playerPlot)
					local offX = ax * (w - 1) * GRID_SIZE * 0.5
					local offZ = az * (d - 1) * GRID_SIZE * 0.5
					local pivotOffset = CFrame.new(offX, 0, offZ)

					ghostModel:SetPrimaryPartCFrame(
						CFrame.new(x, y, z)
							* pivotOffset
							* CFrame.Angles(0, math.rad(buildingRotation), 0)
					)
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
		moveConnection()
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
	removeGhost()
	clearAll()
	local _ = zoneType
	currentMode = nil
	warn(("%s is locked. Reach city level %d to unlock it."):format(zoneType, requiredLevel))
end)

-- CREATE GRID
local function createGrid(mode)
	if not terrains or #terrains == 0 then
		warn("GridVisualizer: No terrains are defined.")
		return
	end

	globalBounds = GridConfig.calculateGlobalBounds(terrains)

	print("=== globalBounds ===")
	printTable(globalBounds)
	print("====================")

	for _, part in ipairs(gridParts) do
		part:Destroy()
	end
	gridParts = {}

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

	local gridFolder = workspace.PlayerPlots.GridParts
	-- Logical axis for this plot
	local ax, az = GridConfig.getAxisDirectionsForPlot(playerPlot)

	for i = 0, displayGridSizeX - 1 do
		for j = 0, displayGridSizeZ - 1 do
			local worldX = absMinX + (i + 0.5) * step
			local worldZ = absMinZ + (j + 0.5) * step

			-- Raw indices relative to the stable anchor
			local rawGX = math.floor((worldX - anchorMinX) / step)
			local rawGZ = math.floor((worldZ - anchorMinZ) / step)

			-- Logical, parity-aligned indices exposed to UI/placement
			local gridX = rawGX * (ax or 1)
			local gridZ = rawGZ * (az or 1)
			gridX = normalizeGridIndex(gridX)
			gridZ = normalizeGridIndex(gridZ)

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

		for key, _ in pairs(metroEntranceCells) do
			local part = gridLookup[key]
			if part then
				part.Color = Color3.fromRGB(255, 220, 0)
				part.Transparency = 0.25
			end
		end

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
	local ax, az = GridConfig.getAxisDirectionsForPlot(playerPlot)

	local directions = {
		{1, 0},   -- East
		{-1, 0},  -- West
		{0, 1},   -- South
		{0, -1},  -- North
	}

	-- [ADDED] Budget cap for line modes (roads/pipes/power)
	local budgetSteps -- nil means unlimited (no cap)
	if currentMode == "DirtRoad" or currentMode == "Pavement" or currentMode == "Highway"
		or currentMode == "WaterPipe" or currentMode == "PowerLines" then
		local cpg = costPerGridFor(currentMode)
		if cpg > 0 then
			local affordableCells = math.floor(playerBalance / cpg)
			-- steps from the start in one direction; start cell is already counted
			budgetSteps = math.max(0, affordableCells - 1)
		end
	end

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
		local steps = 0

		while true do
			x = x + dx
			z = z + dz
			steps += 1

			-- [ADDED] stop showing beyond the affordable steps (if capped)
			if budgetSteps and steps > budgetSteps then
				break
			end

			local rx = x * (ax or 1)
			local rz = z * (az or 1)
			if rx < minGridX or rx > maxGridX or rz < minGridZ or rz > maxGridZ then
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

			gridPart:SetAttribute("GridX", normalizeGridIndex(x))
			gridPart:SetAttribute("GridZ", normalizeGridIndex(z))
			gridPart.Parent = cardinalFolder
			table.insert(cardinalGridParts, gridPart)
		end
	end
end

-- INPUT HANDLER
RunServiceScheduler.onHeartbeat(function()
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

		-- === Guided lock (generic) ==========================================
		if guard.active and guard.spec and currentMode == guard.spec.mode then
			local gx, gz = x_grid, z_grid
			local spec = guard.spec

			if spec.kind == "line" then
				-- first click must be EXACT start
				if guard.stage == "await_first" then
					if gx ~= spec.from.x or gz ~= spec.from.z then return end
					_unmarkAll()
					_markLineInclusive(spec.from, spec.to)   -- show full path now
					_spawnOrMoveAlarmAtCoord(spec.to)        -- alarm moves to the end
					guard.stage = "await_second"
					return -- swallow base logic
				else
					-- second click: exact end (unless explicitly relaxed)
					local exact = (spec.requireExactEnd ~= false)
					local ok = (gx == spec.to.x and gz == spec.to.z)
					if not ok and not exact then
						if (gx == spec.from.x) ~= (gz == spec.from.z) then
							ok = true
							spec.to = { x = gx, z = gz }
						end
					end
					if not ok then return end

					if spec.mode == "WaterPipe" then
						buildPipeEvent:FireServer(spec.from, spec.to, "WaterPipe")
					elseif spec.mode == "PowerLines" then
						ExecuteCommandEvent:FireServer("BuildPowerLine", spec.from, spec.to, "PowerLines")
					elseif spec.mode == "MetroTunnel" then
						ExecuteCommandEvent:FireServer("BuildMetroTunnel", spec.from, spec.to, "MetroTunnel")
					else
						ExecuteCommandEvent:FireServer("BuildRoad", spec.from, spec.to, spec.mode)
					end
					_finishGuard(true)
					clearAll()
					return
				end

			elseif spec.kind == "rect" then
				if guard.stage == "await_first" then
					if gx ~= spec.from.x or gz ~= spec.from.z then return end
					_unmarkAll()
					_markRectInclusive(spec.from, spec.to)   -- show whole rectangle now
					_spawnOrMoveAlarmAtCoord(spec.to)
					guard.stage = "await_second"
					return
				else
					if gx ~= spec.to.x or gz ~= spec.to.z then return end
					ExecuteCommandEvent:FireServer("BuildZone", spec.from, spec.to, spec.mode)
					_finishGuard(true)
					clearAll()
					return
				end

			else
				-- point (e.g., WaterTower). Require exact cell; then defer "done"
				-- until the actual placement call runs in the base logic below.
				local p = spec.point or spec.from
				if not p or gx ~= p.x or gz ~= p.z then return end

				-- Stash a payload so we can report completion after placement.
				_pendingPointGuardPayload = {
					item = spec.item or spec.mode,
					mode = spec.mode,
				}

				-- Clear visuals now; let normal placement path run next.
				_clearGuardUI()
				guard.active=false
				guard.spec=nil
				guard.stage=nil
				-- fall through to base logic for the actual BuildZone call
			end
		end
		-- === end Guided lock ================================================

		if currentMode == "DirtRoad" or currentMode == "Pavement" or currentMode == "Highway" then
			if not selectedCoord then
				selectedCoord = {x = x_grid, z = z_grid}
				print("Road start:", selectedCoord.x, selectedCoord.z)
				target.Color = Color3.new(1, 0, 0)
				showCardinalGrids(selectedCoord)
			else
				if (target.Name == "CardinalGridSquare")
					or (target.Name == "GridSquare" and selectedCoord.x == x_grid and selectedCoord.z == z_grid) then

					local desiredEnd = {x = x_grid, z = z_grid}
					-- [ADDED] truncate to budget
					local newEnd, cells, cost, cannot, truncated =
						truncateEndToBudget(selectedCoord, desiredEnd, currentMode)

					if cannot then
						openPremiumShop()
						clearAll()
						currentMode = nil
						return
					end

					if truncated then
						pcall(function()
							StarterGui:SetCore("SendNotification", {
								Title = "Road length limited",
								Text  = ("Built %d tile(s) within budget."):format(cells),
								Duration = 3
							})
						end)
					end

					print("Road end:", newEnd.x, newEnd.z, "cells=", cells, "cost=", cost)
					ExecuteCommandEvent:FireServer("BuildRoad", selectedCoord, newEnd, currentMode)
					clearAll()
				else
					print("Please select a cardinal grid.")
				end
			end

		elseif currentMode == "WaterPipe" then
			if not selectedCoord then
				selectedCoord = { x = x_grid, z = z_grid }
				print("WaterPipe start:", selectedCoord.x, selectedCoord.z)
				target.Color = Color3.new(1, 0, 0)
				showCardinalGrids(selectedCoord)
			else
				if (target.Name == "CardinalGridSquare")
					or (target.Name == "GridSquare" and selectedCoord.x == x_grid and selectedCoord.z == z_grid) then

					local desiredEnd = { x = x_grid, z = z_grid }
					-- [ADDED] truncate to budget
					local newEnd, cells, cost, cannot, truncated =
						truncateEndToBudget(selectedCoord, desiredEnd, currentMode)

					if cannot then
						openPremiumShop()
						clearAll()
						currentMode = nil
						return
					end

					if truncated then
						pcall(function()
							StarterGui:SetCore("SendNotification", {
								Title = "Pipe length limited",
								Text  = ("Built %d tile(s) within budget."):format(cells),
								Duration = 3
							})
						end)
					end

					print("WaterPipe end:", newEnd.x, newEnd.z, "cells=", cells, "cost=", cost)
					buildPipeEvent:FireServer(selectedCoord, newEnd, currentMode)
					clearAll()
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
				if (target.Name == "CardinalGridSquare")
					or (target.Name == "GridSquare" and selectedCoord.x == x_grid and selectedCoord.z == z_grid) then

					local desiredEnd = {x = x_grid, z = z_grid}
					-- [ADDED] truncate to budget
					local newEnd, cells, cost, cannot, truncated =
						truncateEndToBudget(selectedCoord, desiredEnd, currentMode)

					if cannot then
						openPremiumShop()
						clearAll()
						currentMode = nil
						return
					end

					if truncated then
						pcall(function()
							StarterGui:SetCore("SendNotification", {
								Title = "Power line limited",
								Text  = ("Built %d tile(s) within budget."):format(cells),
								Duration = 3
							})
						end)
					end

					print("PowerLines end:", newEnd.x, newEnd.z, "cells=", cells, "cost=", cost)
					ExecuteCommandEvent:FireServer("BuildPowerLine", selectedCoord, newEnd, currentMode)
					clearAll()
				else
					print("Please select a cardinal grid.")
				end
			end

		elseif currentMode == "MetroTunnel" then
			if not selectedCoord then
				findMetroEntrances()
				findMetroTunnels()

				local hasEntrances = _countKeys(metroEntranceCells) > 0
				local hasTunnels   = _countKeys(metroTunnelCells)   > 0
				local onEntrance   = _isEntranceCell(x_grid, z_grid)
				local nearTunnel   = _isAdjacentToTunnel(x_grid, z_grid)

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
				if (target.Name == "CardinalGridSquare")
					or (target.Name == "GridSquare" and selectedCoord.x == x_grid and selectedCoord.z == z_grid) then
					local startCoord = selectedCoord
					local endCoord   = {x = x_grid, z = z_grid}

					if not _isValidMetroStart(startCoord.x, startCoord.z) and _isValidMetroStart(endCoord.x, endCoord.z) then
						startCoord, endCoord = endCoord, startCoord
					end

					print("MetroTunnel end:", endCoord.x, endCoord.z)
					-- NOTE: if you also want budget-truncation for MetroTunnel, I can mirror it here.
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

			local costKey  = (type(currentMode)=="string" and currentMode:sub(1,5)=="Flag:") and "Flags" or currentMode
			local totalCost = asNumber(Balance.costPerGrid[costKey])

			if playerBalance < totalCost then
				openPremiumShop()
				removeGhost()
				clearAll()
				currentMode = nil
				return
			end

			print("Placing", currentMode, "from:", coord.x, coord.z, "to", endCoord.x, endCoord.z)
			ExecuteCommandEvent:FireServer("BuildZone", coord, endCoord, currentMode, buildingRotation)

			if _pendingPointGuardPayload and _pendingPointGuardPayload.mode == currentMode then
				pcall(function() BE_GuardFB:Fire("done", _pendingPointGuardPayload) end)
				_pendingPointGuardPayload = nil
			end


			target.Color = Color3.new(0, 0, 1)
			removeGhost()
			clearAll()
			currentMode = nil
			BuildMenuUI.OnHide()
		else
			-- Generic "BuildZone" path (e.g., Residential/Commercial/etc.)
			table.insert(selectedCoords, {x = x_grid, z = z_grid})
			print("Zone selection: Coord added:", x_grid, z_grid)
			target.Color = Color3.new(1, 0, 0)

			highlightZoneRange(selectedCoords[1])

			if #selectedCoords == 2 then
				local width  = math.abs(selectedCoords[2].x - selectedCoords[1].x) + 1
				local depth  = math.abs(selectedCoords[2].z - selectedCoords[1].z) + 1

				local costPerCell = asNumber(Balance.costPerGrid[currentMode])
				local totalCost   = width * depth * costPerCell

				if playerBalance < totalCost then
					openPremiumShop()
					selectedCoords = {}
					clearZoneHighlights()
					clearGrid()
					currentMode = nil
					return
				end

				ExecuteCommandEvent:FireServer("BuildZone", selectedCoords[1], selectedCoords[2], currentMode)
				selectedCoords = {}
				clearZoneHighlights()
				clearGrid()
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
	if input.KeyCode == Enum.KeyCode.R then
		if ghostModel then
			rotateGhost()
		end
	end
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

	--Onboarding
	if guard.active and guard.spec and guard.spec.mode == currentMode then
		local first = guard.spec.from or guard.spec.point or guard.spec.one
		local p = _gridPartAt(first)
		if p then _mark(p) end
		_spawnOrMoveAlarmAtCoord(first)
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

	-- Seed per-plot axis (Odd = +1,+1, Even = -1,-1)
	local ax = playerPlot:GetAttribute("GridAxisDirX") or 1
	local az = playerPlot:GetAttribute("GridAxisDirZ") or 1
	GridConfig.setAxisDirectionsForPlot(playerPlot, ax, az)

	local roadStart = playerPlot:WaitForChild("RoadStart", 5)
	if roadStart then
		GridConfig.setStableAnchorFromPart(roadStart)
	else
		warn(("GridVisualizer: RoadStart missing on plot %s – falling back to first-terrain logic.")
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
	rebuildTerrainsFromUnlocks(newUnlockTable)
	if currentMode then
		createGrid(currentMode)
	end
end)
