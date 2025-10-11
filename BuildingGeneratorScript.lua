local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Events = ReplicatedStorage:WaitForChild("Events")
local BindableEvents = Events:WaitForChild("BindableEvents")
local linesPlacedEvent   = BindableEvents:WaitForChild("LinesPlaced")
local linesRemovedEvent  = BindableEvents:WaitForChild("LinesRemoved")

local BuildingGeneratorModule = require(script.Parent:WaitForChild("BuildingGenerator"))
local ZoneTrackerModule = require(script.Parent.Parent.Parent.Parent.ZoneManager:WaitForChild("ZoneTracker"))
local S3 = game:GetService("ServerScriptService")
local CC = S3.Build.Zones.CoreConcepts.PowerGen
local PowerLinePath = require(CC.PowerLinePath)
local PowerGeneratorModule = require(CC.PowerGenerator)

-- Commands (for standard “Zone_<uid>_<n>” creation path)  -- ADD
local CmdRoot                = S3.Build.Zones.Commands      -- ADD
local PlayerCommandManager   = require(CmdRoot.PlayerCommandManager) -- ADD
local BuildZoneCommand       = require(CmdRoot.BuildZoneCommand)     -- ADD

local Players = game:GetService("Players")

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

local zoneCreatedEvent   = BindableEvents:WaitForChild("ZoneCreated")
local zoneRemovedEvent   = BindableEvents:WaitForChild("ZoneRemoved")
local zoneReCreatedEvent = BindableEvents:WaitForChild("ZoneReCreated")

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
	-- Look up the zone to know its mode and gridList
	local z = ZoneTrackerModule.getZoneById(player, zoneId)
	if not z then return end
	if not buildingZoneTypes[z.mode] then return end

	-- Only bother if this zone actually overlaps at least one power line path
	if not _zoneTouchesAnyPowerLine(player, z.gridList or {}) then return end

	-- Walk that zone’s populated folder and spawn pad poles on eligible buildings
	local plot = workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId); if not plot then return end
	local populated = plot:FindFirstChild("Buildings") and plot.Buildings:FindFirstChild("Populated"); if not populated then return end
	local zoneFolder = populated:FindFirstChild(zoneId); if not zoneFolder then return end

	for _, bld in ipairs(zoneFolder:GetChildren()) do
		if (bld:IsA("Model") or bld:IsA("BasePart"))
			and bld:GetAttribute("ZoneId") == zoneId
			and bld:FindFirstChild("ConcretePad")
			and not bld:FindFirstChild("PadPole")            -- idempotent
		then
			-- nil prefab => module uses its default
			BuildingGeneratorModule.spawnPadPowerPoles(bld, nil, {
				ZoneId = zoneId,
				GridX  = bld:GetAttribute("GridX"),
				GridZ  = bld:GetAttribute("GridZ"),
			})
			-- NOTE: PowerGeneratorModule already listens to PadPoleSpawned and will auto-bridge
		end
	end
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

	if buildingZoneTypes[mode] then
		PowerGeneratorModule.suppressPolesOnGridList(player, zoneId, gridList)
		local zoneData = ZoneTrackerModule.getZoneById(player, zoneId)
		if not zoneData then
			warn(string.format("BuildingGeneratorScript: No zoneData found for zoneId '%s'.", zoneId))
			return
		end

		if predefinedBuildings then
			print(string.format(
				"BuildingGeneratorScript: Re-populating Zone '%s' for player '%s' with predefined buildings",
				zoneId, player.Name
				))
			BuildingGeneratorModule.populateZone(player, zoneId, mode, gridList, predefinedBuildings, rotation)
		else
			print(string.format(
				"BuildingGeneratorScript: Populating Zone '%s' for player '%s'",
				zoneId, player.Name
				))
			BuildingGeneratorModule.populateZone(player, zoneId, mode, gridList, nil, rotation)
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
				if z and buildingZoneTypes[z.mode] then
					touchedBldZoneIds[otherId] = true
				end
			end
		end
	end

	-- 2) For each building zone touched by this power line, spawn pad-poles on its buildings
	for bldZoneId, _ in pairs(touchedBldZoneIds) do
		local folder = populated:FindFirstChild(bldZoneId)
		if folder then
			for _, bld in ipairs(folder:GetChildren()) do
				if (bld:IsA("Model") or bld:IsA("BasePart"))
					and bld:GetAttribute("ZoneId") == bldZoneId
					and bld:FindFirstChild("ConcretePad")
					and not bld:FindFirstChild("PadPole")    -- idempotent
				then
					-- nil polePrefab is fine; the module defaults to its prefab
					BuildingGeneratorModule.spawnPadPowerPoles(bld, nil, {
						ZoneId = bldZoneId,
						GridX  = bld:GetAttribute("GridX"),
						GridZ  = bld:GetAttribute("GridZ"),
					})
				end
			end
		end
	end

	-- (Optional) if you also want utility buildings to get padpoles, uncomment:
	-- local utilities = populated:FindFirstChild("Utilities")
	-- if utilities then ... same loop as above ...
end)

-- When a zone is removed, only remove buildings if it's truly a building zone.
zoneRemovedEvent.Event:Connect(function(player, zoneId, mode, gridList)
	if buildingZoneTypes[mode] then
		-- Use the snapshot provided by ZoneTracker (this is the ONLY reliable mask)
		local removedGrid = gridList or {}

		print(("[BuildingGeneratorScript] Removing buildings for Zone '%s' for player '%s'")
			:format(zoneId, player.Name))

		BuildingGeneratorModule.removeBuilding(player, zoneId)

		-- Recreate power poles on just-freed cells that lie on recorded power paths
		PowerGeneratorModule.ensurePolesNearGridList(player, removedGrid)
	end
end)

print("BuildingGeneratorScript loaded.")
