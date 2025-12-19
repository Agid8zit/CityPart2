local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Events = ReplicatedStorage:WaitForChild("Events")
local BindableEvents = Events:WaitForChild("BindableEvents")
local linesPlacedEvent   = BindableEvents:WaitForChild("LinesPlaced")
local linesRemovedEvent  = BindableEvents:WaitForChild("LinesRemoved")
local Wigw8mPlacedEvent  = BindableEvents:WaitForChild("Wigw8mPlaced")

local BuildingGeneratorModule = require(script.Parent:WaitForChild("BuildingGenerator"))
local ZoneTrackerModule = require(script.Parent.Parent.Parent.Parent.ZoneManager:WaitForChild("ZoneTracker"))
local S3 = game:GetService("ServerScriptService")
local LayerManagerModule = require(S3.Build:WaitForChild("LayerManager"))
local CC = S3.Build.Zones.CoreConcepts.PowerGen
local PowerLinePath = require(CC.PowerLinePath)
local PowerGeneratorModule = require(CC.PowerGenerator)

-- Commands (for standard “Zone_<uid>_<n>” creation path)
local CmdRoot                = S3.Build.Zones.Commands
local PlayerCommandManager   = require(CmdRoot.PlayerCommandManager)
local BuildZoneCommand       = require(CmdRoot.BuildZoneCommand)

local Players = game:GetService("Players")

-- Grid helpers (we need world positions for power-line cells)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GridScripts  = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Grid")
local GridUtils    = require(GridScripts:WaitForChild("GridUtil"))
local GridConfig   = require(GridScripts:WaitForChild("GridConfig"))

local VERBOSE_LOG = false
local function log(...)
	if VERBOSE_LOG then print(...) end
end

local function _getGlobalBoundsForPlot(plot)
	local terrains = {}
	local unlocks  = plot:FindFirstChild("Unlocks")
	if unlocks then
		for _, zone in ipairs(unlocks:GetChildren()) do
			for _, seg in ipairs(zone:GetChildren()) do
				if seg:IsA("BasePart") and seg.Name:match("^Segment%d+$") then
					table.insert(terrains, seg)
				end
			end
		end
	end
	local testTerrain = plot:FindFirstChild("TestTerrain")
	if #terrains == 0 and testTerrain then
		table.insert(terrains, testTerrain)
	end
	return GridConfig.calculateGlobalBounds(terrains), terrains
end

-- Power path helpers
local function _powerSegmentsFor(zoneId)
	local net = PowerLinePath.getLineNetworks()[zoneId] or PowerLinePath.getLineData(zoneId) or {}
	return net.segments or net.pathCoords or {}
end

local function _allPowerZoneIdsOnPlot(player)
	local plot = workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId)
	if not plot then return {} end
	local pf = plot:FindFirstChild("PowerLines"); if not pf then return {} end
	local out = {}
	for _, zf in ipairs(pf:GetChildren()) do
		if zf:IsA("Folder") then table.insert(out, zf.Name) end
	end
	return out
end

-- Return nearest power-line cell (grid + world) to the given grid (gx,gz) across ONE power zone
local function _nearestCellForPowerZone(player, powerZoneId, gx, gz)
	local plot = workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId); if not plot then return nil end
	local gb, terrains = _getGlobalBoundsForPlot(plot)

	local best, bestCell = math.huge, nil
	for _, s in ipairs(_powerSegmentsFor(powerZoneId)) do
		local x = (s.coord and s.coord.x) or s.x
		local z = (s.coord and s.coord.z) or s.z
		if x and z then
			local d = math.abs(x - gx) + math.abs(z - gz) -- grid Manhattan
			if d < best then best, bestCell = d, {x = x, z = z} end
		end
	end
	if not bestCell then return nil end
	local wx, wy, wz = GridUtils.globalGridToWorldPosition(bestCell.x, bestCell.z, gb, terrains)
	return bestCell, Vector3.new(wx, wy, wz), best
end

-- From all power zones, pick the single (powerZoneId, nearestCellWorld) best for a given building origin grid
local function _nearestPowerLineForBuilding(player, gx, gz)
	local ids = _allPowerZoneIdsOnPlot(player); if #ids == 0 then return nil end
	local best = { dist = math.huge }
	for _, pzid in ipairs(ids) do
		local cell, world, d = _nearestCellForPowerZone(player, pzid, gx, gz)
		if cell and d < best.dist then
			best = { powerZoneId = pzid, world = world, cell = cell, dist = d }
		end
	end
	return (best.powerZoneId and best) or nil
end

-- Choose the single best building inside a building zone for a given power zone
local function _chooseBestBuildingForPowerZone(player, zoneId, powerZoneId)
	local plot = workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId); if not plot then return nil end
	local populated = plot:FindFirstChild("Buildings") and plot.Buildings:FindFirstChild("Populated"); if not populated then return nil end
	local zoneFolder = populated:FindFirstChild(zoneId); if not zoneFolder then return nil end

	local best = { dist = math.huge }
	for _, bld in ipairs(zoneFolder:GetChildren()) do
		if (bld:IsA("Model") or bld:IsA("BasePart"))
			and bld:GetAttribute("ZoneId") == zoneId
			and bld:FindFirstChild("ConcretePad")
		then
			local gx, gz = bld:GetAttribute("GridX"), bld:GetAttribute("GridZ")
			if gx and gz then
				local cell, world, d = _nearestCellForPowerZone(player, powerZoneId, gx, gz)
				if cell and d < best.dist then
					best = { building = bld, targetWorld = world, dist = d }
				end
			end
		end
	end
	return (best.building and best) or nil
end

-- Pad-pole linking requests may arrive while a building zone is still populating.
-- Track them per-player/zone so we can process them once the zone finishes.
local pendingPadPoleRequests = {} -- [userId] = { [zoneId] = { [powerZoneId] = true } }

local function _queuePadPoleRequest(player, zoneId, powerZoneId)
	if not (player and zoneId and powerZoneId) then return end
	local uid = player.UserId
	local perPlayer = pendingPadPoleRequests[uid]
	if not perPlayer then
		perPlayer = {}
		pendingPadPoleRequests[uid] = perPlayer
	end
	local perZone = perPlayer[zoneId]
	if not perZone then
		perZone = {}
		perPlayer[zoneId] = perZone
	end
	perZone[powerZoneId] = true
end

local function _takePadPoleRequests(player, zoneId)
	if not (player and zoneId) then return nil end
	local uid = player.UserId
	local perPlayer = pendingPadPoleRequests[uid]
	if not perPlayer then return nil end
	local perZone = perPlayer[zoneId]
	if not perZone then return nil end
	perPlayer[zoneId] = nil
	if not next(perPlayer) then
		pendingPadPoleRequests[uid] = nil
	end
	return perZone
end

local function _spawnPadPoleForPowerZone(player, zoneId, powerZoneId)
	local pick = _chooseBestBuildingForPowerZone(player, zoneId, powerZoneId)
	if not (pick and pick.building) then return false end
	BuildingGeneratorModule.spawnPadPowerPoles(pick.building, nil, {
		ZoneId          = zoneId,
		GridX           = pick.building:GetAttribute("GridX"),
		GridZ           = pick.building:GetAttribute("GridZ"),
		PowerLineZoneId = powerZoneId,
		ForceSpawn      = true,
		TargetWorldPos  = pick.targetWorld,
	})
	return true
end

local function _processPadPoleRequestSet(player, zoneId, requestSet)
	if not requestSet then return end
	for powerZoneId in pairs(requestSet) do
		_spawnPadPoleForPowerZone(player, zoneId, powerZoneId)
	end
end

Players.PlayerRemoving:Connect(function(player)
	if not player then return end
	pendingPadPoleRequests[player.UserId] = nil
end)

-- Road billboard suppression helpers
local BILLBOARD_NAMES = {
	Billboard = true,
	BillboardStanding = true,
}
local REMOVED_BILLBOARD_TYPE = "RoadBillboard"

local function _getInstanceBoundingBox(inst)
	if not inst then return nil, nil end
	if inst:IsA("Model") then
		local cf, size = inst:GetBoundingBox()
		return cf, size
	elseif inst:IsA("BasePart") then
		return inst.CFrame, inst.Size
	end
	return nil, nil
end

local function _overlapXZ(cfA, sizeA, cfB, sizeB)
	if not (cfA and sizeA and cfB and sizeB) then return false end
	local halfA = sizeA * 0.5
	local halfB = sizeB * 0.5
	local posA, posB = cfA.Position, cfB.Position
	if math.abs(posA.X - posB.X) > (halfA.X + halfB.X) then return false end
	if math.abs(posA.Z - posB.Z) > (halfA.Z + halfB.Z) then return false end
	return true
end

local function _forEachRoadBillboard(player, callback)
	if type(callback) ~= "function" or not player then return end
	local plot = workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId)
	if not plot then return end
	local roads = plot:FindFirstChild("Roads")
	if not roads then return end
	for _, zoneFolder in ipairs(roads:GetChildren()) do
		if zoneFolder:IsA("Folder") then
			for _, inst in ipairs(zoneFolder:GetChildren()) do
				if BILLBOARD_NAMES[inst.Name] and inst:GetAttribute("IsRoadDecoration") == true then
					callback(inst, zoneFolder)
				end
			end
		end
	end
end

local function _recordAndRemoveBillboard(ownerZoneId, inst, player)
	if not (ownerZoneId and inst) then return end
	local cf = select(1, _getInstanceBoundingBox(inst))
	local record = {
		instanceClone  = inst:Clone(),
		parentName     = inst.Parent and inst.Parent.Name or nil,
		originalParent = inst.Parent,
		cframe         = cf,
		gridX          = inst:GetAttribute("GridX"),
		gridZ          = inst:GetAttribute("GridZ"),
		zoneId         = inst:GetAttribute("ZoneId") or (inst.Parent and inst.Parent.Name),
	}
	LayerManagerModule.storeRemovedObject(REMOVED_BILLBOARD_TYPE, ownerZoneId, record, player)
	inst:Destroy()
end

local function _stripBillboardsInBox(player, ownerZoneId, boxCF, boxSize)
	if not (boxCF and boxSize) then return end
	_forEachRoadBillboard(player, function(inst)
		local cf, size = _getInstanceBoundingBox(inst)
		if _overlapXZ(boxCF, boxSize, cf, size) then
			_recordAndRemoveBillboard(ownerZoneId, inst, player)
		end
	end)
end

local function _zoneBoundsToBox(player, gridList)
	if not (player and type(gridList) == "table" and #gridList > 0) then return nil, nil end
	local plot = workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId)
	if not plot then return nil, nil end
	local gb, terrains = _getGlobalBoundsForPlot(plot)
	local minX, maxX, minZ, maxZ
	for _, coord in ipairs(gridList) do
		local gx, gz = coord.x, coord.z
		if typeof(gx) == "number" and typeof(gz) == "number" then
			local wx, _, wz = GridUtils.globalGridToWorldPosition(gx, gz, gb, terrains)
			minX = minX and math.min(minX, wx) or wx
			maxX = maxX and math.max(maxX, wx) or wx
			minZ = minZ and math.min(minZ, wz) or wz
			maxZ = maxZ and math.max(maxZ, wz) or wz
		end
	end
	if not minX then return nil, nil end
	local cellSize = (GridConfig.GRID_SIZE or 1)
	local sizeX = math.max(cellSize, (maxX - minX) + cellSize)
	local sizeZ = math.max(cellSize, (maxZ - minZ) + cellSize)
	local centreX = (minX + maxX) * 0.5
	local centreZ = (minZ + maxZ) * 0.5
	return CFrame.new(centreX, 0, centreZ), Vector3.new(sizeX, 50, sizeZ)
end

local function _stripBillboardsForZone(player, zoneId, gridList)
	local cf, size = _zoneBoundsToBox(player, gridList)
	if cf and size then
		_stripBillboardsInBox(player, zoneId, cf, size)
	end
end

-- List of Building Zones (to avoid crossover with roads, utilities, etc.)
local buildingZoneTypes = {
	-- Zoning types
	Residential = true,
	Commercial  = true,
	Industrial  = true,
	ResDense    = true,
	CommDense   = true,
	IndusDense  = true,
	Utilities   = true,

	-- Individual buildings
	WaterTower = true,
	WaterPlant = true,
	PurificationWaterPlant = true,
	MolecularWaterPlant = true,

	FireDept = true,
	FirePrecinct = true,
	FireStation = true,

	MiddleSchool = true,
	Museum = true,
	NewsStation = true,
	PrivateSchool = true,

	CityHospital = true,
	LocalHospital = true,
	MajorHospital = true,
	SmallClinic = true,

	Bank = true,
	CNTower = true,
	EiffelTower = true,
	EmpireStateBuilding = true,
	FerrisWheel = true,
	GasStation = true,
	ModernSkyscraper = true,
	NationalCapital = true,
	Obelisk = true,
	SpaceNeedle = true,
	StatueOfLiberty = true,
	TechOffice = true,
	WorldTradeCenter = true,

	Church = true,
	Hotel = true,
	Mosque = true,
	MovieTheater = true,
	ShintoTemple = true,
	BuddhaStatue = true,
	HinduTemple = true,

	Courthouse = true,
	PoliceDept = true,
	PolicePrecinct = true,
	PoliceStation = true,

	ArcheryRange = true,
	BasketballCourt = true,
	BasketballStadium = true,
	FootballStadium = true,
	GolfCourse = true,
	PublicPool = true,
	SkatePark = true,
	SoccerStadium = true,
	TennisCourt = true,

	Airport = true,
	BusDepot = true,
	MetroEntrance = true,
	Bus = true,

	CoalPowerPlant = true,
	GasPowerPlant = true,
	GeothermalPowerPlant = true,
	NuclearPowerPlant = true,
	SolarPanels = true,
	WindTurbine = true,
}

-- Helper: treat listed modes AND dynamic "Flag:<Name>" as building modes
local function isBuildingMode(mode : string)
	if buildingZoneTypes[mode] then return true end
	return type(mode)=="string" and string.sub(mode,1,5)=="Flag:"
end

local zoneCreatedEvent   = BindableEvents:WaitForChild("ZoneCreated")
local zoneRemovedEvent   = BindableEvents:WaitForChild("ZoneRemoved")
local zoneReCreatedEvent = BindableEvents:WaitForChild("ZoneReCreated")

local function _waitForZoneData(player, zoneId, timeoutSec)
	local deadline = os.clock() + (timeoutSec or 0.5)
	repeat
		local z = ZoneTrackerModule.getZoneById(player, zoneId)
		if z then return z end
		task.wait(0.05)
	until os.clock() > deadline
	return nil
end

-- Utility: quick set from a gridList
local function _gridSet(list)
	local s = {}
	for _, c in ipairs(list or {}) do
		if c.x and c.z then s[c.x..","..c.z] = true end
	end
	return s
end

local function _enqueueEntranceBuild(player, endCoord)
	if not (endCoord and endCoord.x and endCoord.z) then return end
	local startV3 = Vector3.new(endCoord.x, 0, endCoord.z)
	local endV3   = startV3
	local cmd     = BuildZoneCommand.new(player, startV3, endV3, "MetroEntrance", 0)
	local mgr     = PlayerCommandManager:getManager(player)
	mgr:enqueueCommand(cmd)
end

local function _createEntranceZoneNow(player, endCoord)
	if not (endCoord and endCoord.x and endCoord.z) then return end
	local prefix          = ("MetroEntranceZone_%d_"):format(player.UserId)
	local entranceZoneId  = ZoneTrackerModule.getNextZoneId(player, prefix)
	local entranceGrid    = { endCoord }

	-- 1) Synchronously add to the tracker (eliminates race)
	local ok = ZoneTrackerModule.addZone(player, entranceZoneId, "MetroEntrance", entranceGrid)
	if not ok then
		warn(("[BuildingGeneratorScript] addZone failed for %s"):format(entranceZoneId))
		return
	end

	-- 2) Now broadcast so normal listeners (including this script) run populate path
	zoneCreatedEvent:Fire(player, entranceZoneId, "MetroEntrance", entranceGrid)
end

-- Allocate a unique MetroEntrance zone id scoped to this player
local function _nextMetroEntranceZoneId(player)
	local prefix = ("MetroEntranceZone_%d_"):format(player.UserId)
	return ZoneTrackerModule.getNextZoneId(player, prefix)
end

-- Helper: pick the nearest power line zone to a given building origin grid.
local function _nearestPowerZoneIdToGrid(player, gx, gz)
	if not (player and gx and gz) then return nil end
	local plot = workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId)
	if not plot then return nil end

	local pf = plot:FindFirstChild("PowerLines")
	if not pf then return nil end

	local bestId, bestDist
	for _, zf in ipairs(pf:GetChildren()) do
		if zf:IsA("Folder") then
			local net  = PowerLinePath.getLineNetworks()[zf.Name] or PowerLinePath.getLineData(zf.Name) or {}
			local segs = net.segments or net.pathCoords or {}
			for _, s in ipairs(segs) do
				local x = (s.coord and s.coord.x) or s.x
				local z = (s.coord and s.coord.z) or s.z
				if x and z then
					local d = math.abs(x - gx) + math.abs(z - gz) -- Manhattan distance in grid-space
					if not bestDist or d < bestDist then
						bestDist, bestId = d, zf.Name
					end
				end
			end
		end
	end
	return bestId
end

-- Does this building zone overlap ANY power line path?
local function _zoneTouchesAnyPowerLine(player, zoneGridList)
	local set = _gridSet(zoneGridList)
	local plot = workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId); if not plot then return false end
	local powerFolder = plot:FindFirstChild("PowerLines"); if not powerFolder then return false end

	for _, zf in ipairs(powerFolder:GetChildren()) do
		if zf:IsA("Folder") then
			local net  = PowerLinePath.getLineNetworks()[zf.Name] or PowerLinePath.getLineData(zf.Name) or {}
			local segs = net.segments or net.pathCoords or {}
			for _, s in ipairs(segs) do
				local gx = (s.coord and s.coord.x) or s.x
				local gz = (s.coord and s.coord.z) or s.z
				if gx and gz and set[gx..","..gz] then
					return true
				end
			end
		end
	end
	return false
end

local zonePopulatedEvent = BindableEvents:WaitForChild("ZonePopulated")

zonePopulatedEvent.Event:Connect(function(player, zoneId, _payload)
	-- Drain any deferred pad-pole work now; we'll process it once the zone is ready.
	local deferredRequests = _takePadPoleRequests(player, zoneId)
	-- Look up the zone to know its mode and gridList
	local z = ZoneTrackerModule.getZoneById(player, zoneId)
	if not z then return end
	if not isBuildingMode(z.mode) then return end

	-- Only bother if this zone actually overlaps at least one power line path
	if not _zoneTouchesAnyPowerLine(player, z.gridList or {}) then return end

	local plot = workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId); if not plot then return end
	local populated = plot:FindFirstChild("Buildings") and plot.Buildings:FindFirstChild("Populated"); if not populated then return end
	local zoneFolder = populated:FindFirstChild(zoneId); if not zoneFolder then return end

	-- Choose the single best building + power line pair (closest grid → closest path cell)
	local bestChoice = nil
	for _, bld in ipairs(zoneFolder:GetChildren()) do
		if (bld:IsA("Model") or bld:IsA("BasePart"))
			and bld:GetAttribute("ZoneId") == zoneId
			and bld:FindFirstChild("ConcretePad")
		then
			local gx, gz = bld:GetAttribute("GridX"), bld:GetAttribute("GridZ")
			if gx and gz then
				local pick = _nearestPowerLineForBuilding(player, gx, gz)
				if pick and (not bestChoice or pick.dist < bestChoice.dist) then
					bestChoice = {
						building     = bld,
						powerZoneId  = pick.powerZoneId,
						targetWorld  = pick.world,
						dist         = pick.dist
					}
				end
			end
		end
	end

	if not bestChoice then
		_processPadPoleRequestSet(player, zoneId, deferredRequests)
		return
	end

	-- Force a guaranteed, directed spawn on that building
	BuildingGeneratorModule.spawnPadPowerPoles(bestChoice.building, nil, {
		ZoneId          = zoneId,
		GridX           = bestChoice.building:GetAttribute("GridX"),
		GridZ           = bestChoice.building:GetAttribute("GridZ"),
		PowerLineZoneId = bestChoice.powerZoneId, -- ownership
		ForceSpawn      = true,                   -- << guarantee 100%
		TargetWorldPos  = bestChoice.targetWorld, -- << choose corner nearest to the line
	})

	_processPadPoleRequestSet(player, zoneId, deferredRequests)
end)

local function _hasZoneOfModeAt(player, coord, wantMode)
	if not (coord and coord.x and coord.z) then return false end
	local z = ZoneTrackerModule.getZoneAtGrid(player, coord.x, coord.z)
	return z and z.mode == wantMode
end

-- When a zone is Re-Created (e.g., on load)
zoneReCreatedEvent.Event:Connect(function(
	player, zoneId, mode, gridList, predefinedBuildings, rotation)
	-- We pass a final boolean **true** to mean “skip Stage-1/2”
	BuildingGeneratorModule.populateZone(
		player, zoneId, mode, gridList,
		predefinedBuildings, rotation,  true      -- ← skipStages
	)
end)

-- When a zone is created, populate it with buildings if it's one of the recognized building modes.
zoneCreatedEvent.Event:Connect(function(player, zoneId, mode, gridList, predefinedBuildings, rotation)
	-- MetroTunnel → immediately create a 1-cell MetroEntrance at the end tile
	if mode == "MetroTunnel" then
		if type(gridList) == "table" and #gridList > 0 then
			local endCoord = gridList[#gridList]
			-- Extra safety: avoid duplicates if something else already added it
			if not _hasZoneOfModeAt(player, endCoord, "MetroEntrance") then
				_enqueueEntranceBuild(player, endCoord)
			end
		end
		return  -- tunnel isn’t a building zone
	end

	if isBuildingMode(mode) then
		local zoneData = ZoneTrackerModule.getZoneById(player, zoneId)
		if not zoneData then
			zoneData = _waitForZoneData(player, zoneId, 1)
		end

		local resolvedGrid = (zoneData and zoneData.gridList) or gridList or {}
		local resolvedMode = (zoneData and zoneData.mode) or mode
		if not zoneData then
			warn(string.format("BuildingGeneratorScript: No zoneData found for zoneId '%s' (using event payload).", zoneId))
		end

		_stripBillboardsForZone(player, zoneId, resolvedGrid)
		PowerGeneratorModule.suppressPolesOnGridList(player, zoneId, resolvedGrid)

		if predefinedBuildings then
			log(string.format(
				"BuildingGeneratorScript: Re-populating Zone '%s' for player '%s' with predefined buildings",
				zoneId, player.Name
				))
			BuildingGeneratorModule.populateZone(player, zoneId, resolvedMode, resolvedGrid, predefinedBuildings, rotation)
		else
			log(string.format(
				"BuildingGeneratorScript: Populating Zone '%s' for player '%s'",
				zoneId, player.Name
				))
			BuildingGeneratorModule.populateZone(player, zoneId, resolvedMode, resolvedGrid, nil, rotation)
		end
	else
		-- Not a building zone; do nothing
	end
end)

linesPlacedEvent.Event:Connect(function(player, powerZoneId)
	local plot = workspace.PlayerPlots:FindFirstChild("Plot_" .. player.UserId)
	if not plot then return end

	local populated = plot:FindFirstChild("Buildings")
		and plot.Buildings:FindFirstChild("Populated")
	if not populated then return end

	-- 1) Collect building zoneIds that the power path touches/overlaps
	local touchedBldZoneIds = {}
	do
		local net  = PowerLinePath.getLineNetworks()[powerZoneId] or PowerLinePath.getLineData(powerZoneId) or {}
		local segs = net.segments or net.pathCoords or {}
		local function cx(s) return (s.coord and s.coord.x) or s.x end
		local function cz(s) return (s.coord and s.coord.z) or s.z end

		for _, seg in ipairs(segs) do
			local ox = cx(seg); local oz = cz(seg)
			local otherId = ZoneTrackerModule.getOtherZoneIdAtGrid(player, ox, oz, powerZoneId)
			if otherId and otherId ~= powerZoneId then
				local z = ZoneTrackerModule.getZoneById(player, otherId)
				if z and isBuildingMode(z.mode) then
					touchedBldZoneIds[otherId] = true
				end
			end
		end
	end

	-- 2) For each building zone touched by this power line, spawn exactly one pad‑pole on its nearest building
	for bldZoneId, _ in pairs(touchedBldZoneIds) do
		if ZoneTrackerModule.isZonePopulating(player, bldZoneId) then
			_queuePadPoleRequest(player, bldZoneId, powerZoneId)
		else
			_spawnPadPoleForPowerZone(player, bldZoneId, powerZoneId)
		end
	end
end)

Wigw8mPlacedEvent.Event:Connect(function(player, zoneId, payload)
	if not (player and type(zoneId) == "string") then return end
	if type(payload) ~= "table" then return end
	local mode = payload.mode
	if not (mode and isBuildingMode(mode)) then return end
	local building = payload.building
	if not building then return end
	local cf, size = _getInstanceBoundingBox(building)
	if cf and size then
		_stripBillboardsInBox(player, zoneId, cf, size)
	end
end)

-- When a zone is removed, only remove buildings if it's truly a building zone.
zoneRemovedEvent.Event:Connect(function(player, zoneId, mode, gridList)
	if isBuildingMode(mode) then
		_takePadPoleRequests(player, zoneId)
		-- Use the snapshot provided by ZoneTracker (this is the ONLY reliable mask)
		local removedGrid = gridList or {}

		log(("[BuildingGeneratorScript] Removing buildings for Zone '%s' for player '%s'")
			:format(zoneId, player.Name))

		BuildingGeneratorModule.removeBuilding(player, zoneId)

		-- Recreate power poles on just-freed cells that lie on recorded power paths
		PowerGeneratorModule.ensurePolesNearGridList(player, removedGrid)

		LayerManagerModule.restoreRemovedObjects(player, zoneId, REMOVED_BILLBOARD_TYPE, "Roads")
	end
end)

log("BuildingGeneratorScript loaded.")
