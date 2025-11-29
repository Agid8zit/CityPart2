local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Workspace           = game:GetService("Workspace")
local CollectionService   = game:GetService("CollectionService")
local HttpService         = game:GetService("HttpService")
local Events              = ReplicatedStorage:WaitForChild("Events")
local RemoteEvents        = Events:WaitForChild("RemoteEvents")

local GridConfig          = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Grid"):WaitForChild("GridConfig"))
local ZoneTrackerModule   = require(script.Parent:WaitForChild("ZoneTracker"))
local RoadTypes           = require(script.Parent:WaitForChild("RoadTypes"))

-- Grid Utilities
local Scripts             = ReplicatedStorage:WaitForChild("Scripts")
local GridConf            = Scripts:WaitForChild("Grid")
local GridUtils           = require(GridConf:WaitForChild("GridUtil"))

local ZoneValidationModule = {}
ZoneValidationModule.__index = ZoneValidationModule

-- Configuration
local DEBUG = false   -- Set to true for detailed debugging
local EPS   = 1e-6    -- tiny nudge to avoid boundary ties

-- ------------------------------------------------------------------
-- Debug helpers
-- ------------------------------------------------------------------
local function debugPrint(...)
	if DEBUG then
		print("[ZoneValidationModule]", ...)
	end
end

-- ------------------------------------------------------------------
-- Notification helper (server -> client, LangKey only)
--   Client owns strings via NotificationGui; we only emit keys.
--   Looks for ReplicatedStorage/Events/RemoteEvents/NotificationStack (preferred),
--   or falls back to PushNotification / Notify.
-- ------------------------------------------------------------------
local NotificationRemote --[[: RemoteEvent? ]]
local PlayUISoundRE --[[: RemoteEvent? ]]

local function getNotificationRemote(): RemoteEvent?
	if NotificationRemote == nil or NotificationRemote.Parent == nil then
		NotificationRemote = RemoteEvents:FindFirstChild("NotificationStack")
			or RemoteEvents:FindFirstChild("PushNotification")
			or RemoteEvents:FindFirstChild("Notify")
	end
	return NotificationRemote
end

local function fireErrorSound(player: Player?)
	if not player then return end
	if not PlayUISoundRE or PlayUISoundRE.Parent == nil then
		PlayUISoundRE = RemoteEvents:FindFirstChild("PlayUISound")
	end
	if PlayUISoundRE then
		PlayUISoundRE:FireClient(player, "Misc", "Error")
	end
end

local function pushLangNotification(player, langKey: string)
	if not player or type(langKey) ~= "string" or langKey == "" then return end

	local notifyRE = getNotificationRemote()
	if notifyRE then
		notifyRE:FireClient(player, { LangKey = langKey })
	else
		warn("[ZoneValidation] Notification RemoteEvent not found (NotificationStack / PushNotification / Notify)")
	end

	fireErrorSound(player)
end

-- ------------------------------------------------------------------
-- Infrastructure (placeholder)
-- ------------------------------------------------------------------
local RequiredInfrastructure = {
	Roads = true,
	Water = true,
	Power = true,
	-- Add other infrastructure types as needed
}

local function hasRequiredInfrastructure(_gridList)
	-- TODO: implement actual infra checks
	debugPrint("Checking for required infrastructure (placeholder = true).")
	return true
end

-- ------------------------------------------------------------------
-- Basic validation helpers
-- ------------------------------------------------------------------
local function isValidPlayer(player)
	return player and typeof(player) == "Instance" and player:IsA("Player")
end

local function coordKey(c) return c.x .. "," .. c.z end

local function buildSet(list)
	local s = {}
	for _, c in ipairs(list or {}) do
		s[coordKey(c)] = true
	end
	return s
end

-- Exact cell intersection (O(n + m))
local function listsIntersectExact(a, b)
	if not a or not b or #a == 0 or #b == 0 then return false end
	-- Build the smaller set
	local small, big = a, b
	if #b < #a then small, big = b, a end
	local s = buildSet(small)
	for _, c in ipairs(big) do
		if s[coordKey(c)] then return true end
	end
	return false
end

-- ------------------------------------------------------------------
-- Plot/global-bounds helpers
-- ------------------------------------------------------------------
local boundsCache = {}

local function getGlobalBoundsForPlot(plot)
	local cached = boundsCache[plot]
	if cached then return cached.bounds, cached.terrains end

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

	local gb = GridConfig.calculateGlobalBounds(terrains)
	local axisDirX, axisDirZ = GridConfig.getAxisDirectionsForPlot(plot)
	gb.axisDirX = axisDirX
	gb.axisDirZ = axisDirZ
	boundsCache[plot] = { bounds = gb, terrains = terrains }
	return gb, terrains
end

local function convertGridToWorld(player, gx, gz)
	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_" .. player.UserId)
	if not plot then return Vector3.zero end

	local gb, terrains = getGlobalBoundsForPlot(plot)
	local wx, _, wz = GridUtils.globalGridToWorldPosition(gx, gz, gb, terrains)
	return Vector3.new(wx, 1.025, wz)
end

-- ------------------------------------------------------------------
-- Unlock rasterization (exact "Unlock" parts prioritized; legacy fallback)
-- ------------------------------------------------------------------
local function isUnlockFootprintPart(part)
	if part.Name:match("^Segment%d+$") then return true end
	if part:GetAttribute("UnlockCell") == true then return true end
	if CollectionService:HasTag(part, "UnlockCell") then return true end
	return false
end

local function worldToNearestGridIndex(worldCoord, axisMin, axisMax, axisDir)
	local idx = GridConfig.worldCoordToGridIndex(worldCoord, axisMin, axisMax, axisDir)
	local rounded = math.floor(idx + 0.5 + EPS)
	local dir = (axisDir == -1) and -1 or 1
	return rounded * dir
end

-- 2D (XZ) AABB for a part, accounting for rotation (conservative projection)
local function getPartAABB2D(part)
	local cf = part.CFrame
	local px, pz = cf.Position.X, cf.Position.Z
	local sx, sy, sz = part.Size.X * 0.5, part.Size.Y * 0.5, part.Size.Z * 0.5

	-- World basis vectors
	local r, u, f = cf.RightVector, cf.UpVector, cf.LookVector

	-- Half-extent projected on world X and Z axes
	local hx = math.abs(r.X) * sx + math.abs(u.X) * sy + math.abs(f.X) * sz
	local hz = math.abs(r.Z) * sx + math.abs(u.Z) * sy + math.abs(f.Z) * sz

	return (px - hx), (px + hx), (pz - hz), (pz + hz)
end

-- Build a set of locked cells for a player's plot
local function getUnlockGridSet(player)
	local plotsRoot = Workspace:FindFirstChild("PlayerPlots")
	if not plotsRoot then return {} end

	local plot = plotsRoot:FindFirstChild("Plot_" .. player.UserId)
	if not plot then return {} end

	local unlockFolder = plot:FindFirstChild("Unlocks")
	if not unlockFolder then return {} end

	local globalBounds = select(1, getGlobalBoundsForPlot(plot))
	local gridSize     = GridConfig.GRID_SIZE or 4
	local rawAxisDirX, rawAxisDirZ = GridConfig.getAxisDirectionsForPlot(plot)
	local axisDirX     = (rawAxisDirX == -1) and -1 or 1
	local axisDirZ     = (rawAxisDirZ == -1) and -1 or 1
	local plotWidthX   = (globalBounds.maxX - globalBounds.minX)
	local plotWidthZ   = (globalBounds.maxZ - globalBounds.minZ)
	local gridSizeX    = math.max(0, math.floor(plotWidthX / gridSize))
	local gridSizeZ    = math.max(0, math.floor(plotWidthZ / gridSize))

	local set       = {}
	local whoFilled = {}

	local function mark(gx, gz, src)
		if gx < 0 or gz < 0 or gx >= gridSizeX or gz >= gridSizeZ then return end
		local logicalGX = (axisDirX == -1) and -gx or gx
		local k = logicalGX .. "," .. gz
		set[k] = true
		if DEBUG and not whoFilled[k] then whoFilled[k] = src end
	end

	-- Pass 1: exact BasePart named "Unlock"
	local unlockPartCount = 0
	for _, inst in ipairs(unlockFolder:GetDescendants()) do
		if inst:IsA("BasePart") and inst.Name == "Unlock" then
			unlockPartCount += 1

			local minX, maxX, minZ, maxZ = getPartAABB2D(inst)
			minX = math.max(minX, globalBounds.minX)
			maxX = math.min(maxX, globalBounds.maxX)
			minZ = math.max(minZ, globalBounds.minZ)
			maxZ = math.min(maxZ, globalBounds.maxZ)

			local startGX = math.max(0, math.floor(GridConfig.worldCoordToGridIndex(minX, globalBounds.minX, globalBounds.maxX, axisDirX)) - 1)
			local endGX   = math.min(gridSizeX - 1, math.floor(GridConfig.worldCoordToGridIndex(maxX, globalBounds.minX, globalBounds.maxX, axisDirX)) + 1)
			local startGZ = math.max(0, math.floor(GridConfig.worldCoordToGridIndex(minZ, globalBounds.minZ, globalBounds.maxZ, axisDirZ)) - 1)
			local endGZ   = math.min(gridSizeZ - 1, math.floor(GridConfig.worldCoordToGridIndex(maxZ, globalBounds.minZ, globalBounds.maxZ, axisDirZ)) + 1)

			for gx = startGX, endGX do
				local centerX = GridConfig.gridIndexToWorldCoord(gx, globalBounds.minX, globalBounds.maxX, axisDirX)
				if centerX >= (minX - EPS) and centerX < (maxX - EPS) then
					for gz = startGZ, endGZ do
						local centerZ = GridConfig.gridIndexToWorldCoord(gz, globalBounds.minZ, globalBounds.maxZ, axisDirZ)
						if centerZ >= (minZ - EPS) and centerZ < (maxZ - EPS) then
							mark(gx, gz, inst:GetFullName())
						end
					end
				end
			end
		end
	end

	-- Pass 2 (fallback): legacy footprint tiles
	if unlockPartCount == 0 then
		for _, model in ipairs(unlockFolder:GetChildren()) do
			if model:IsA("Model") and model:FindFirstChild("Unlock", true) then
				for _, part in ipairs(model:GetDescendants()) do
					if part:IsA("BasePart") and isUnlockFootprintPart(part) then
						local pos = part.Position
						local gx  = worldToNearestGridIndex(pos.X, globalBounds.minX, globalBounds.maxX, axisDirX)
						local gz  = worldToNearestGridIndex(pos.Z, globalBounds.minZ, globalBounds.maxZ, axisDirZ)
						mark(gx, gz, part:GetFullName())
					end
				end
			end
		end
	end

	if DEBUG then
		local n = 0; for _ in pairs(set) do n += 1 end
		print(string.format("[ZoneValidation] Locked grid count = %d (UnlockParts=%d)", n, unlockPartCount))
	end

	return set
end

local function overlapsUnlocks(player, gridList)
	local unlocks = getUnlockGridSet(player)
	for _, c in ipairs(gridList) do
		if unlocks[coordKey(c)] then
			return true
		end
	end
	return false
end

-- True if any coord in gridList collides with ANY existing road grid
local function overlapsAnyRoad(player, gridList)
	local roadSet = {}
	local allZones = ZoneTrackerModule.getAllZones(player)
	for _, zone in pairs(allZones) do
		if RoadTypes[zone.mode] then
			for _, c in ipairs(zone.gridList) do
				roadSet[coordKey(c)] = true
			end
		end
	end
	for _, c in ipairs(gridList) do
		if roadSet[coordKey(c)] then return true end
	end
	return false
end

-- ------------------------------------------------------------------
-- Split utils
-- ------------------------------------------------------------------
local function splitZoneAroundRoad(newZoneGridList, roadGridList)
	debugPrint("Splitting zone around roads.")

	local splitZones = {}
	local visited = {}
	local roadSet = buildSet(roadGridList)

	local zoneSet = {}
	for _, coord in ipairs(newZoneGridList) do
		local key = coordKey(coord)
		if not roadSet[key] then
			zoneSet[key] = true
		end
	end

	local function dfs(coord, currentZone)
		local key = coordKey(coord)
		if visited[key] or not zoneSet[key] then return end
		visited[key] = true
		table.insert(currentZone, coord)

		local neighbors = {
			{ x = coord.x + 1, z = coord.z },
			{ x = coord.x - 1, z = coord.z },
			{ x = coord.x,     z = coord.z + 1 },
			{ x = coord.x,     z = coord.z - 1 },
		}
		for _, n in ipairs(neighbors) do
			if zoneSet[coordKey(n)] and not visited[coordKey(n)] then
				dfs(n, currentZone)
			end
		end
	end

	for _, coord in ipairs(newZoneGridList) do
		local key = coordKey(coord)
		if zoneSet[key] and not visited[key] then
			local currentZone = {}
			dfs(coord, currentZone)
			if #currentZone > 0 then
				table.insert(splitZones, currentZone)
			end
		end
	end

	return splitZones
end

-- ------------------------------------------------------------------
-- Mode groups
-- ------------------------------------------------------------------
local IgnoreValidation = {
	SolarPanels             = true,
	WindTurbine             = true,
	CoalPowerPlant          = true,
	GasPowerPlant           = true,
	GeothermalPowerPlant    = true,
	NuclearPowerPlant       = true,
	WaterTower              = true,
	WaterPlant              = true,
	PurificationWaterPlant  = true,
	MolecularWaterPlant     = true,
	FireDept                = true,
	FirePrecinct            = true,
	FireStation             = true,
	MetroEntrance           = true,
	BusDepot                = true,
	MiddleSchool            = true,
	Museum                  = true,
	NewsStation             = true,
	PrivateSchool           = true,
	CityHospital            = true,
	LocalHospital           = true,
	MajorHospital           = true,
	SmallClinic             = true,
	Bank                    = true,
	CNTower                 = true,
	EiffelTower             = true,
	EmpireStateBuilding     = true,
	FerrisWheel             = true,
	GasStation              = true,
	ModernSkyscraper        = true,
	NationalCapital         = true,
	Obelisk                 = true,
	SpaceNeedle             = true,
	StatueOfLiberty         = true,
	TechOffice              = true,
	WorldTradeCenter        = true,
	Church                  = true,
	Hotel                   = true,
	Mosque                  = true,
	MovieTheater            = true,
	ShintoTemple            = true,
	BuddhaStatue            = true,
	HinduTemple             = true,
	Courthouse              = true,
	PoliceDept              = true,
	PolicePrecinct          = true,
	PoliceStation           = true,
	ArcheryRange            = true,
	BasketballCourt         = true,
	BasketballStadium       = true,
	FootballStadium         = true,
	GolfCourse              = true,
	PublicPool              = true,
	SkatePark               = true,
	SoccerStadium           = true,
	TennisCourt             = true,
	Flags                   = true,
}

-- Six *building* zone types roads may cross
local BuildZoneTypes = {
	Residential = true,  ResDense  = true,
	Commercial  = true,  CommDense = true,
	Industrial  = true,  IndusDense= true,
}

ZoneValidationModule.OverlayZoneTypes = IgnoreValidation

-- ------------------------------------------------------------------
-- Merge helpers (kept, used by both legacy API and atomic flow)
-- ------------------------------------------------------------------
local function mergeZones(newZone, overlappingZones)
	debugPrint("Merging zones...")
	local coordSet = {}
	local uniqueGridList = {}

	for _, coord in ipairs(newZone.gridList) do
		local key = coordKey(coord)
		if not coordSet[key] then
			coordSet[key] = true
			table.insert(uniqueGridList, coord)
		end
	end

	for _, zone in pairs(overlappingZones) do
		for _, coord in ipairs(zone.gridList) do
			local key = coordKey(coord)
			if not coordSet[key] then
				coordSet[key] = true
				table.insert(uniqueGridList, coord)
			end
		end
		ZoneTrackerModule.removeZone(zone.player, zone.zoneId)
		debugPrint(string.format("Merged zone '%s' into '%s'.", zone.zoneId, newZone.zoneId))
	end

	newZone.gridList = uniqueGridList
	return newZone
end

-- ------------------------------------------------------------------
-- Lightweight per-plot mutex to prevent TOCTTOU races
-- ------------------------------------------------------------------
local PlacementLocks = {}

local function withPlotLock(player, fn)
	local userId = player.UserId
	while PlacementLocks[userId] do task.wait() end
	PlacementLocks[userId] = true
	local ok, a, b, c = pcall(fn)
	PlacementLocks[userId] = nil
	if not ok then
		warn("[ZoneValidation] Atomic placement error:", a)
		return false, "Internal error"
	end
	return a, b, c
end

-- ------------------------------------------------------------------
-- PUBLIC: validateZone (legacy preview/UX path)
-- Note: This does NOT commit. Use tryAddZoneAtomic to commit safely.
-- ------------------------------------------------------------------
function ZoneValidationModule.validateZone(player, mode, gridList)
	debugPrint("Validating zone for player:", player and player.Name or "nil", "Mode:", mode)

	-- 1) Basic checks
	if not isValidPlayer(player) then
		warn("validateZone: Invalid player provided.")
		pushLangNotification(player, "Cant overlap zones")
		return false, "Invalid player."
	end
	if not (type(mode) == "string" and type(gridList) == "table") then
		warn("validateZone: Invalid parameters. Expected (Player, string, table).")
		pushLangNotification(player, "Cant overlap zones")
		return false, "Invalid parameters."
	end
	if not gridList or #gridList == 0 then
		warn("validateZone: gridList is nil or empty.")
		pushLangNotification(player, "Cant overlap zones")
		return false, "Invalid grid selection."
	end
	for _, coord in ipairs(gridList) do
		if type(coord) ~= "table" or type(coord.x) ~= "number" or type(coord.z) ~= "number" then
			warn("validateZone: Invalid coordinate detected:", tostring(coord))
			pushLangNotification(player, "Cant overlap zones")
			return false, "Invalid coordinates provided."
		end
	end

	-- Reject any overlap with Unlock parts (or legacy locked cells)
	if overlapsUnlocks(player, gridList) then
		if DEBUG then
			local u = getUnlockGridSet(player)
			for _, c in ipairs(gridList) do
				local k = coordKey(c)
				if u[k] then print("[DEBUG] Overlap at", k) end
			end
		end
		warn("validateZone: Selection overlaps an unlock part for player:", player.Name)
		pushLangNotification(player, "Cant build on unique buildings")
		return false, "You cannot build over an unlockable item."
	end

	-- Utilities can be built anywhere
	if mode == "WaterPipe" or mode == "PowerLines" or mode == "MetroTunnel" then
		debugPrint(mode, "can be built through other zones. Validation passed.")
		return true, ("Valid %s placement."):format(mode)
	end

	-- Overlay/IgnoreValidation types: cannot cross roads and cannot overlap *non-building* zones.
	if IgnoreValidation[mode] then
		if overlapsAnyRoad(player, gridList) then
			warn(("validateZone: %s overlaps a road. Not allowed."):format(mode))
			pushLangNotification(player, "Cant build on roads")
			return false, ("You cannot place %s on top of roads."):format(mode)
		end

		local exclusions = {}
		for k,_ in pairs(RoadTypes) do exclusions[k] = true end
		exclusions["WaterPipe"]   = true
		exclusions["PowerLines"]  = true
		exclusions["MetroTunnel"] = true
		for zt,_ in pairs(BuildZoneTypes) do exclusions[zt] = true end

		for _, coord in ipairs(gridList) do
			if ZoneTrackerModule.isGridOccupied(
				player, coord.x, coord.z,
				{ excludeZoneTypes = exclusions }
				) then
				warn(("validateZone: %s overlaps an existing zone at (%d,%d). Not allowed."):format(mode, coord.x, coord.z))
				pushLangNotification(player, "Cant build on unique buildings")
				return false, ("You cannot place %s on top of existing zones."):format(mode)
			end
		end

		debugPrint(mode, "is an overlay type; no road crossing and no stacking. Validation passed.")
		return true, ("Valid %s placement (no road crossing, no stacking)."):format(mode)
	end

	-- 3) Required infra
	if not hasRequiredInfrastructure(gridList) then
		warn("validateZone: Required infrastructure missing for player:", player.Name)
		pushLangNotification(player, "Cant overlap zones")
		return false, "Required infrastructure is not nearby."
	end

	-- 4) Exact-overlap scan against existing zones (ignoring utilities)
	local allZones = ZoneTrackerModule.getAllZones(player)
	local overlappingZones, sameTypeZones, roadOverlaps = {}, {}, {}

	for _, zone in pairs(allZones) do
		if zone.mode ~= "WaterPipe" and zone.mode ~= "PowerLines" and zone.mode ~= "MetroTunnel" then
			if listsIntersectExact(zone.gridList, gridList) then
				table.insert(overlappingZones, zone)
				if zone.mode == mode then table.insert(sameTypeZones, zone) end
				if RoadTypes[zone.mode] then table.insert(roadOverlaps, zone) end
			end
		end
	end

	debugPrint(string.format("Found %d overlapping zones, %d same-type, %d are roads.",
		#overlappingZones, #sameTypeZones, #roadOverlaps))

	-- 5) If building a non-road zone and overlaps exist:
	if #overlappingZones > 0 and not RoadTypes[mode] then
		-- If any overlap with *same-type* zones, this is INVALID (no merging).
		if #sameTypeZones > 0 then
			warn("validateZone: Overlapping with same-type zones. Validation failed (no merge policy).")
			pushLangNotification(player, "Cant overlap zones")
			return false, "Selected area overlaps with an existing zone of the same type."
		end

		-- Split around roads, if any (only applies if overlap is with roads)
		if #roadOverlaps > 0 then
			debugPrint("Zone overlaps with roads. Splitting into multiple zones.")
			local allRoadGridsSet, allRoadGridList = {}, {}
			for _, roadZone in ipairs(roadOverlaps) do
				for _, c in ipairs(roadZone.gridList) do
					local key = coordKey(c)
					if not allRoadGridsSet[key] then
						allRoadGridsSet[key] = true
						table.insert(allRoadGridList, c)
					end
				end
			end
			local splitZones = splitZoneAroundRoad(gridList, allRoadGridList)
			if splitZones and #splitZones > 1 then
				return true, "Zone split due to road overlap.", splitZones
			end
		end

		-- Different non-road type overlap is illegal
		for _, zone in ipairs(overlappingZones) do
			if not RoadTypes[zone.mode] and zone.mode ~= mode then
				warn("validateZone: Overlapping with different type zones. Validation failed.")
				pushLangNotification(player, "Cant overlap zones")
				return false, "Selected area overlaps with existing zones of a different type."
			end
		end
	end

	-- 6) Exclusions common to non-road placement
	local OverlapExclusions = {}
	for roadTypeName, _ in pairs(RoadTypes) do
		OverlapExclusions[roadTypeName] = true
	end
	OverlapExclusions["WaterPipe"]   = true
	OverlapExclusions["PowerLines"]  = true
	OverlapExclusions["MetroTunnel"] = true

	-- === Roads can cross buildings ===
	if RoadTypes[mode] then
		for zt, _ in pairs(BuildZoneTypes) do
			OverlapExclusions[zt] = true
		end
		debugPrint("Building a Road: permitting crossing of building zones (Res/Com/Ind + Dense).")

		local filteredGridList = {}
		for _, coord in ipairs(gridList) do
			-- Deliberately check building occupants so IgnoreValidation/overlay types (e.g., WindTurbine) still block roads.
			local occupied = ZoneTrackerModule.isGridOccupied(
				player, coord.x, coord.z,
				{
					excludeZoneTypes    = OverlapExclusions,
				}
			)
			if not occupied then
				table.insert(filteredGridList, coord)
			else
				debugPrint(string.format("Excluding grid (%d, %d) - blocked by non-crossable occupant.", coord.x, coord.z))
			end
		end

		if #filteredGridList == 0 then
			warn("validateZone: All selected grids are blocked by non-crossable occupants.")
			pushLangNotification(player, "Cant build on roads")
			return false, "All selected grids are blocked by non-crossable items."
		end

		local connectedComponents = GridUtils.splitIntoConnectedComponents(filteredGridList)
		if #connectedComponents == 0 then
			warn("validateZone: No valid areas to create roads after exclusions.")
			pushLangNotification(player, "Cant build on roads")
			return false, "No valid areas to create roads."
		end

		local validComponents = {}
		for _, component in ipairs(connectedComponents) do
			local cIsValid = true
			for _, coord in ipairs(component) do
				if ZoneTrackerModule.isGridOccupied(
					player, coord.x, coord.z,
					{
						excludeZoneTypes    = OverlapExclusions,
					}
					) then
					cIsValid = false
					debugPrint(string.format("Grid (%d, %d) in this component is blocked by a non-crossable item.", coord.x, coord.z))
					break
				end
			end
			if cIsValid then table.insert(validComponents, component) end
		end

		if #validComponents == 0 then
			warn("validateZone: No valid road segments found after occupant checks.")
			pushLangNotification(player, "Cant build on roads")
			return false, "No valid road segments."
		end

		return true, "Valid road components found.", validComponents
	else
		-- Non-road, non-pipe
		local connectedComponents = GridUtils.splitIntoConnectedComponents(gridList)
		if #connectedComponents == 0 then
			warn("validateZone: No valid areas to create zones.")
			pushLangNotification(player, "Cant overlap zones")
			return false, "No valid areas to create zones."
		end

		local validComponents = {}
		for _, component in ipairs(connectedComponents) do
			local cIsValid = true
			for _, coord in ipairs(component) do
				if ZoneTrackerModule.isGridOccupied(
					player, coord.x, coord.z,
					{ excludeZoneTypes = OverlapExclusions }
					) then
					cIsValid = false
					debugPrint(string.format("Grid (%d, %d) is occupied by a non-road zone. Excluding component.", coord.x, coord.z))
					break
				end
			end
			if cIsValid then table.insert(validComponents, component) end
		end

		if #validComponents == 0 then
			warn("validateZone: No valid areas to create zones after excluding roads/pipes/lines.")
			pushLangNotification(player, "Cant overlap zones")
			return false, "No valid areas to create zones."
		end

		return true, "Valid zone components found.", validComponents
	end
end

-- ------------------------------------------------------------------
-- PUBLIC: handleMerging (legacy). Now runs under lock internally.
-- NOTE: Kept for compatibility but not used when same-type overlap is disallowed.
-- ------------------------------------------------------------------
function ZoneValidationModule.handleMerging(player, mode, zoneId, gridList, sameTypeZones)
	debugPrint("Handling merging for zone:", zoneId)

	if not isValidPlayer(player) then
		warn("handleMerging: Invalid player provided.")
		return nil
	end
	if not (type(mode) == "string" and type(zoneId) == "string" and type(gridList) == "table") then
		warn("handleMerging: Invalid parameters. Expected (Player, string, string, table).")
		return nil
	end
	if not sameTypeZones or #sameTypeZones == 0 then
		warn("handleMerging: No same type zones provided for merging.")
		return nil
	end

	local function doMerge()
		local newZone = {
			zoneId = zoneId,
			player = player,
			mode = mode,
			gridList = gridList,
			requirements = {
				Roads = true, Water = true, Power = true,
			}
		}
		newZone = mergeZones(newZone, sameTypeZones)
		local success = ZoneTrackerModule.addZone(player, newZone.zoneId, newZone.mode, newZone.gridList)
		if success then
			debugPrint("Merged zone added successfully.")
			return newZone
		else
			warn("handleMerging: Failed to add merged zone.")
			return nil
		end
	end

	local ok, res = withPlotLock(player, doMerge)
	if not ok then return nil end
	return res
end

-- ------------------------------------------------------------------
-- PUBLIC: validateSingleGrid (unchanged semantics)
-- ------------------------------------------------------------------
function ZoneValidationModule.validateSingleGrid(player, mode, gridPosition)
	debugPrint("Validating single grid for player:", player and player.Name or "nil", "Mode:", mode)

	if not isValidPlayer(player) then
		warn("validateSingleGrid: Invalid player provided.")
		pushLangNotification(player, "Cant overlap zones")
		return false, "Invalid player."
	end
	if not (type(gridPosition) == "table" and type(gridPosition.x) == "number" and type(gridPosition.z) == "number") then
		warn("validateSingleGrid: Invalid grid position.")
		pushLangNotification(player, "Cant overlap zones")
		return false, "Invalid grid position."
	end

	if IgnoreValidation[mode] then
		if overlapsAnyRoad(player, { gridPosition }) then
			pushLangNotification(player, "Cant build on roads")
			return false, ("You cannot place %s on top of roads."):format(mode)
		end
		if overlapsUnlocks(player, { gridPosition }) then
			pushLangNotification(player, "Cant build on unique buildings")
			return false, "That spot is reserved for an unlockable item."
		end

		local exclusions = {}
		for k,_ in pairs(RoadTypes) do exclusions[k] = true end
		exclusions["WaterPipe"]   = true
		exclusions["PowerLines"]  = true
		exclusions["MetroTunnel"] = true
		for zt,_ in pairs(BuildZoneTypes) do exclusions[zt] = true end

		if ZoneTrackerModule.isGridOccupied(
			player, gridPosition.x, gridPosition.z,
			{ excludeZoneTypes = exclusions }
			) then
			pushLangNotification(player, "Cant build on unique buildings")
			return false, ("You cannot place %s on top of existing zones."):format(mode)
		end

		debugPrint("Grid position is valid for overlay type (no road crossing, no stacking).")
		return true, "Valid grid position."
	end

	if RoadTypes[mode] then
		if overlapsUnlocks(player, {gridPosition}) then
			pushLangNotification(player, "Cant build on unique buildings")
			return false, "That spot is reserved for an unlockable item."
		end
		local exclusions = {}
		for k,_ in pairs(RoadTypes) do exclusions[k] = true end
		exclusions["WaterPipe"]   = true
		exclusions["PowerLines"]  = true
		exclusions["MetroTunnel"] = true
		for zt,_ in pairs(BuildZoneTypes) do exclusions[zt] = true end

		local blocked = ZoneTrackerModule.isGridOccupied(
			player, gridPosition.x, gridPosition.z,
			{
				excludeZoneTypes    = exclusions,
			}
		)
		if blocked then
			pushLangNotification(player, "Cant build on roads")
			return false, "Blocked by a non-crossable item."
		end
		return true, "Valid road cell."
	end

	-- Default
	if ZoneTrackerModule.isGridOccupied(player, gridPosition.x, gridPosition.z) then
		warn(string.format("validateSingleGrid: Grid position (%d, %d) is already occupied.", gridPosition.x, gridPosition.z))
		pushLangNotification(player, "Cant overlap zones")
		return false, "Selected grid is already occupied."
	end

	if overlapsUnlocks(player, {gridPosition}) then
		pushLangNotification(player, "Cant build on unique buildings")
		return false, "That spot is reserved for an unlockable item."
	end

	debugPrint("Grid position is valid.")
	return true, "Valid grid position."
end

-- ------------------------------------------------------------------
-- NEW PUBLIC API: tryAddZoneAtomic
-- Performs final re-validation and commits under a per-plot lock.
-- This prevents race conditions where two placements overlap.
--
-- @param player Player
-- @param mode string
-- @param gridList table of {x,z}
-- @param options? table
--     options.zoneIdPrefix: string (optional) – prefix to use for created zone ids
--     options.allowSplit: boolean (default true) – roads/non-roads may split into components
--     options.allowMerge: boolean (default true) – same-type touching components merge existing
--
-- @return ok:boolean, msg:string, details:any
--   On success: details = { zoneIds = { ... }, components = { ... } }
-- ------------------------------------------------------------------
function ZoneValidationModule.tryAddZoneAtomic(player, mode, gridList, options)
	options = options or {}
	local allowSplit = options.allowSplit ~= false
	local allowMerge = options.allowMerge ~= false -- kept for API shape; ignored for same-type overlap
	local zoneIdPrefix = options.zoneIdPrefix or (mode .. "_" .. tostring(player.UserId) .. "_")

	-- quick parameter guard before entering lock
	if not isValidPlayer(player) then
		pushLangNotification(player, "Cant overlap zones")
		return false, "Invalid player."
	end
	if type(mode) ~= "string" or type(gridList) ~= "table" or #gridList == 0 then
		pushLangNotification(player, "Cant overlap zones")
		return false, "Invalid parameters."
	end
	for _, c in ipairs(gridList) do
		if type(c) ~= "table" or type(c.x) ~= "number" or type(c.z) ~= "number" then
			pushLangNotification(player, "Cant overlap zones")
			return false, "Invalid grid coordinates."
		end
	end
	if overlapsUnlocks(player, gridList) then
		pushLangNotification(player, "Cant build on unique buildings")
		return false, "You cannot build over an unlockable item."
	end
	if mode ~= "WaterPipe" and mode ~= "PowerLines" and mode ~= "MetroTunnel" then
		if not hasRequiredInfrastructure(gridList) then
			pushLangNotification(player, "Cant overlap zones")
			return false, "Required infrastructure is not nearby."
		end
	end

	return withPlotLock(player, function()
		local zoneIdsCommitted = {}
		local componentsCommitted = {}

		-- Build common exclusions
		local OverlapExclusions = {}
		for roadTypeName, _ in pairs(RoadTypes) do
			OverlapExclusions[roadTypeName] = true
		end
		OverlapExclusions["WaterPipe"]   = true
		OverlapExclusions["PowerLines"]  = true
		OverlapExclusions["MetroTunnel"] = true

		-- Utilities: commit as-is
		if mode == "WaterPipe" or mode == "PowerLines" or mode == "MetroTunnel" then
			local zoneId = zoneIdPrefix .. HttpService:GenerateGUID(false)
			local ok = ZoneTrackerModule.addZone(player, zoneId, mode, gridList)
			if not ok then
				pushLangNotification(player, "Cant overlap zones")
				return false, "Failed to add utility zone."
			end
			table.insert(zoneIdsCommitted, zoneId)
			table.insert(componentsCommitted, gridList)
			return true, "Utility placed.", { zoneIds = zoneIdsCommitted, components = componentsCommitted }
		end

		-- Overlays: cannot cross roads, cannot stack over non-building zones
		if IgnoreValidation[mode] then
			if overlapsAnyRoad(player, gridList) then
				pushLangNotification(player, "Cant build on roads")
				return false, ("You cannot place %s on top of roads."):format(mode)
			end
			local exclusions = {}
			for k,_ in pairs(RoadTypes) do exclusions[k] = true end
			exclusions["WaterPipe"]   = true
			exclusions["PowerLines"]  = true
			exclusions["MetroTunnel"] = true
			for zt,_ in pairs(BuildZoneTypes) do exclusions[zt] = true end

			for _, c in ipairs(gridList) do
				if ZoneTrackerModule.isGridOccupied(player, c.x, c.z, { excludeZoneTypes = exclusions }) then
					pushLangNotification(player, "Cant build on unique buildings")
					return false, ("You cannot place %s on top of existing zones."):format(mode)
				end
			end

			local zoneId = zoneIdPrefix .. HttpService:GenerateGUID(false)
			local ok = ZoneTrackerModule.addZone(player, zoneId, mode, gridList)
			if not ok then
				pushLangNotification(player, "Cant overlap zones")
				return false, "Failed to add overlay."
			end
			table.insert(zoneIdsCommitted, zoneId)
			table.insert(componentsCommitted, gridList)
			return true, "Overlay placed.", { zoneIds = zoneIdsCommitted, components = componentsCommitted }
		end

		-- Roads: filter + split + commit
		if RoadTypes[mode] then
			for zt,_ in pairs(BuildZoneTypes) do
				OverlapExclusions[zt] = true
			end

			local filtered = {}
			for _, c in ipairs(gridList) do
				-- Keep building occupants in the check so overlay/IgnoreValidation zones remain blocking.
				local blocked = ZoneTrackerModule.isGridOccupied(
					player, c.x, c.z,
					{ excludeZoneTypes = OverlapExclusions }
				)
				if not blocked then table.insert(filtered, c) end
			end
			if #filtered == 0 then
				pushLangNotification(player, "Cant build on roads")
				return false, "All selected grids are blocked by non-crossable items."
			end

			local components = allowSplit and GridUtils.splitIntoConnectedComponents(filtered) or { filtered }
			if #components == 0 then
				pushLangNotification(player, "Cant build on roads")
				return false, "No valid road segments."
			end

			for _, comp in ipairs(components) do
				-- final per-cell verification
				for _, c in ipairs(comp) do
					local blocked = ZoneTrackerModule.isGridOccupied(
						player, c.x, c.z,
						{ excludeZoneTypes = OverlapExclusions }
					)
					if blocked then
						pushLangNotification(player, "Cant build on roads")
						return false, "A road segment became blocked during placement."
					end
				end
				local zoneId = zoneIdPrefix .. HttpService:GenerateGUID(false)
				local ok = ZoneTrackerModule.addZone(player, zoneId, mode, comp)
				if not ok then
					pushLangNotification(player, "Cant overlap zones")
					return false, "Failed to add road segment."
				end
				table.insert(zoneIdsCommitted, zoneId)
				table.insert(componentsCommitted, comp)
			end

			return true, "Road placed.", { zoneIds = zoneIdsCommitted, components = componentsCommitted }
		end

		-- Non-road building zones: split, check, then commit
		local components = allowSplit and GridUtils.splitIntoConnectedComponents(gridList) or { gridList }
		if #components == 0 then
			pushLangNotification(player, "Cant overlap zones")
			return false, "No valid areas to create zones."
		end

		for _, comp in ipairs(components) do
			-- ensure cells not occupied by non-excluded things
			local compOk = true
			for _, c in ipairs(comp) do
				if ZoneTrackerModule.isGridOccupied(player, c.x, c.z, { excludeZoneTypes = OverlapExclusions }) then
					compOk = false; break
				end
			end
			if not compOk then
				pushLangNotification(player, "Cant overlap zones")
				return false, "Area is no longer free."
			end

			-- Disallow any overlap with same-type zones (no merge policy)
			local allZonesNow = ZoneTrackerModule.getAllZones(player)
			for _, z in pairs(allZonesNow) do
				if z.mode == mode and listsIntersectExact(z.gridList, comp) then
					pushLangNotification(player, "Cant overlap zones")
					return false, "Selected area overlaps with an existing zone of the same type."
				end
			end
			-- Block overlaps with other non-road types
			for _, z in pairs(allZonesNow) do
				if z.mode ~= mode and not RoadTypes[z.mode] and listsIntersectExact(z.gridList, comp) then
					pushLangNotification(player, "Cant overlap zones")
					return false, "Selected area overlaps with existing zones of a different type."
				end
			end

			local zoneId = zoneIdPrefix .. HttpService:GenerateGUID(false)
			local toAdd = { zoneId = zoneId, player = player, mode = mode, gridList = comp }

			-- No merging: commit as-is
			local ok = ZoneTrackerModule.addZone(player, toAdd.zoneId, toAdd.mode, toAdd.gridList)
			if not ok then
				pushLangNotification(player, "Cant overlap zones")
				return false, "Failed to add zone."
			end
			table.insert(zoneIdsCommitted, toAdd.zoneId)
			table.insert(componentsCommitted, toAdd.gridList)
		end

		return true, "Zone placed.", { zoneIds = zoneIdsCommitted, components = componentsCommitted }
	end)
end

return ZoneValidationModule
