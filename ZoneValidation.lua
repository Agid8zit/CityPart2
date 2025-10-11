-- ZoneValidation.lua
--[[
Script Order: 2
Script Name: ZoneValidation.lua
Description: Module for validating zone creation and merging.
Dependencies: ZoneTracker.lua, RoadTypes.lua
Dependents: ZoneManager.lua, ZoneManagerScript.lua
]]--

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local GridConfig        = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Grid"):WaitForChild("GridConfig"))
local ZoneTrackerModule = require(script.Parent:WaitForChild("ZoneTracker"))
local RoadTypes         = require(script.Parent:WaitForChild("RoadTypes"))

-- Grid Utilities
local Scripts = ReplicatedStorage:WaitForChild("Scripts")
local GridConf = Scripts:WaitForChild("Grid")
local GridUtils = require(GridConf:WaitForChild("GridUtil"))

local ZoneValidationModule = {}
ZoneValidationModule.__index = ZoneValidationModule

-- Configuration
local DEBUG = false  -- Set to true for detailed debugging
local EPS   = 1e-6  -- tiny nudge to avoid boundary ties

-- Custom debug print function
local function debugPrint(...)
	if DEBUG then
		print("[ZoneValidationModule]", ...)
	end
end

-- Configuration for infrastructure requirements
local RequiredInfrastructure = {
	Roads = true,
	Water = true,
	Power = true,
	-- Add other infrastructure types as needed
}

-- Local Function: Validate Player
local function isValidPlayer(player)
	return player and typeof(player) == "Instance" and player:IsA("Player")
end

-- Function to check if required infrastructure is nearby
local function hasRequiredInfrastructure(gridList)
	-- Implement actual logic to check infrastructure connections
	-- Placeholder: always returns true
	debugPrint("Checking for required infrastructure...")
	return true
end

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
	boundsCache[plot] = { bounds = gb, terrains = terrains }
	return gb, terrains
end

local function convertGridToWorld(player, gx, gz)
	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_" .. player.UserId)
	if not plot then return Vector3.zero end

	local gb, terrains = getGlobalBoundsForPlot(plot)
	local wx, wy, wz = GridUtils.globalGridToWorldPosition(gx, gz, gb, terrains)

	-- hover a hair above the surface, like the old script did
	return Vector3.new(wx, 1.025, wz)
end

-- Function to determine if two sets of coordinates overlap (AABB coarse check)
local function zonesOverlap(coords1, coords2)
	local function getBounds(coords)
		if not coords then
			warn("getBounds: coords is nil")
			return nil, nil, nil, nil
		end

		local minX, maxX = math.huge, -math.huge
		local minZ, maxZ = math.huge, -math.huge

		for _, coord in ipairs(coords) do
			if type(coord) ~= "table" or type(coord.x) ~= "number" or type(coord.z) ~= "number" then
				warn("getBounds: Invalid coordinate detected:", tostring(coord))
				return nil, nil, nil, nil
			end
			if coord.x < minX then minX = coord.x end
			if coord.x > maxX then maxX = coord.x end
			if coord.z < minZ then minZ = coord.z end
			if coord.z > maxZ then maxZ = coord.z end
		end
		return minX, maxX, minZ, maxZ
	end

	local minX1, maxX1, minZ1, maxZ1 = getBounds(coords1)
	local minX2, maxX2, minZ2, maxZ2 = getBounds(coords2)

	if not minX1 or not minX2 then
		warn("zonesOverlap: One of the coordinate lists is invalid.")
		return false
	end

	-- Check for Axis-Aligned Bounding Box (AABB) overlap
	if maxX1 < minX2 or maxX2 < minX1 then return false end
	if maxZ1 < minZ2 or maxZ2 < minZ1 then return false end

	debugPrint("Zones overlap detected (AABB).")
	return true
end

-- Function to merge zones of the same type
local function mergeZones(newZone, overlappingZones)
	debugPrint("Merging zones...")
	-- Create a set to track unique coordinates
	local coordSet = {}
	local uniqueGridList = {}

	-- Add coordinates from newZone.gridList
	for _, coord in ipairs(newZone.gridList) do
		local key = coord.x .. "," .. coord.z
		if not coordSet[key] then
			coordSet[key] = true
			table.insert(uniqueGridList, coord)
		end
	end

	for _, zone in pairs(overlappingZones) do
		-- Merge logic: combine gridList of newZone and existing zone
		for _, coord in ipairs(zone.gridList) do
			local key = coord.x .. "," .. coord.z
			if not coordSet[key] then
				coordSet[key] = true
				table.insert(uniqueGridList, coord)
			end
		end
		-- Remove the existing zone from ZoneTracker
		ZoneTrackerModule.removeZone(zone.player, zone.zoneId)
		debugPrint(string.format("Merged zone '%s' into '%s'.", zone.zoneId, newZone.zoneId))
	end

	-- Update newZone.gridList with unique coordinates
	newZone.gridList = uniqueGridList

	return newZone
end

-- === Enhanced math helpers (new local helpers; no API changes) ===

-- treat only *footprint* parts as unlock cells (legacy fallback)
local function isUnlockFootprintPart(part)
	if part.Name:match("^Segment%d+$") then return true end
	if part:GetAttribute("UnlockCell") == true then return true end
	if CollectionService:HasTag(part, "UnlockCell") then return true end
	return false
end

-- nearest-grid mapping (use rounding, not floor) to avoid edge bias
local function worldToNearestGridIndex(worldCoord, axisMin, grid)
	-- add a tiny EPS to break ties deterministically toward the interior
	local t = (worldCoord - axisMin) / grid
	return math.floor(t + 0.5 + EPS)
end

-- 2D (XZ) AABB for a part, accounting for rotation (conservative projection)
local function getPartAABB2D(part)
	local cf = part.CFrame
	local px, pz = cf.Position.X, cf.Position.Z
	local sx, sy, sz = part.Size.X * 0.5, part.Size.Y * 0.5, part.Size.Z * 0.5

	-- World basis vectors
	local r = cf.RightVector
	local u = cf.UpVector
	local f = cf.LookVector

	-- Half-extent projected on world X and Z axes
	local hx = math.abs(r.X) * sx + math.abs(u.X) * sy + math.abs(f.X) * sz
	local hz = math.abs(r.Z) * sx + math.abs(u.Z) * sy + math.abs(f.Z) * sz

	local minX, maxX = px - hx, px + hx
	local minZ, maxZ = pz - hz, pz + hz
	return minX, maxX, minZ, maxZ
end

-- Function: build set of locked cells from Unlocks folder
-- NEW behavior:
--   1) Prefer rasterizing BaseParts named EXACTLY "Unlock" (ignores models named "Unlock_#")
--   2) If none found, fall back to legacy footprint (Segment/attributes/tag) method
--   3) For "Unlock" parts, we mark ONLY cells whose **center** lies strictly inside the part AABB (half-open)
local function getUnlockGridSet(player)
	-----------------------------------------------------------------
	-- 1) Locate Plot_<UserId>/Unlocks
	-----------------------------------------------------------------
	local plotsRoot = Workspace:FindFirstChild("PlayerPlots")
	if not plotsRoot then return {} end

	local plot = plotsRoot:FindFirstChild("Plot_" .. player.UserId)
	if not plot then return {} end

	local unlockFolder = plot:FindFirstChild("Unlocks")
	if not unlockFolder then return {} end

	-----------------------------------------------------------------
	-- 2) Plot bounds and grid sizes for clamping
	-----------------------------------------------------------------
	local globalBounds = select(1, getGlobalBoundsForPlot(plot))
	local gridSize     = GridConfig.GRID_SIZE or 4

	local plotWidthX   = (globalBounds.maxX - globalBounds.minX)
	local plotWidthZ   = (globalBounds.maxZ - globalBounds.minZ)
	local gridSizeX    = math.max(0, math.floor(plotWidthX / gridSize))
	local gridSizeZ    = math.max(0, math.floor(plotWidthZ / gridSize))

	-----------------------------------------------------------------
	-- 3) Build set using "Unlock" parts if present (center-sample)
	-----------------------------------------------------------------
	local set       = {}
	local whoFilled = {} -- for debug attribution

	local function mark(gx, gz, src)
		if gx < 0 or gz < 0 or gx >= gridSizeX or gz >= gridSizeZ then return end
		local k = gx .. "," .. gz
		set[k] = true
		if DEBUG and not whoFilled[k] then whoFilled[k] = src end
	end

	local unlockPartCount = 0

	for _, inst in ipairs(unlockFolder:GetDescendants()) do
		if inst:IsA("BasePart") and inst.Name == "Unlock" then
			unlockPartCount += 1

			-- Take the 2D AABB footprint of the part
			local minX, maxX, minZ, maxZ = getPartAABB2D(inst)

			-- Clamp to plot bounds
			minX = math.max(minX, globalBounds.minX)
			maxX = math.min(maxX, globalBounds.maxX)
			minZ = math.max(minZ, globalBounds.minZ)
			maxZ = math.min(maxZ, globalBounds.maxZ)

			-- Convert to candidate grid index ranges (loose, then center-test)
			local startGX = math.max(0, math.floor((minX - globalBounds.minX) / gridSize) - 1)
			local endGX   = math.min(gridSizeX - 1, math.floor((maxX - globalBounds.minX) / gridSize) + 1)
			local startGZ = math.max(0, math.floor((minZ - globalBounds.minZ) / gridSize) - 1)
			local endGZ   = math.min(gridSizeZ - 1, math.floor((maxZ - globalBounds.minZ) / gridSize) + 1)

			-- Half-open interval test on cell centers to avoid boundary bleed
			for gx = startGX, endGX do
				local centerX = globalBounds.minX + (gx + 0.5) * gridSize
				if centerX >= (minX - EPS) and centerX < (maxX - EPS) then
					for gz = startGZ, endGZ do
						local centerZ = globalBounds.minZ + (gz + 0.5) * gridSize
						if centerZ >= (minZ - EPS) and centerZ < (maxZ - EPS) then
							mark(gx, gz, inst:GetFullName())
						end
					end
				end
			end
		end
	end

	-----------------------------------------------------------------
	-- 4) Legacy fallback if no "Unlock" parts are present:
	--     Use center-based raster of *footprint* parts ONLY
	-----------------------------------------------------------------
	if unlockPartCount == 0 then
		for _, model in ipairs(unlockFolder:GetChildren()) do
			if model:IsA("Model") and model:FindFirstChild("Unlock", true) then
				for _, part in ipairs(model:GetDescendants()) do
					if part:IsA("BasePart") and isUnlockFootprintPart(part) then
						-- map the *center* of the footprint tile to a single grid cell
						local pos = part.Position
						local gx  = worldToNearestGridIndex(pos.X, globalBounds.minX, gridSize)
						local gz  = worldToNearestGridIndex(pos.Z, globalBounds.minZ, gridSize)
						mark(gx, gz, part:GetFullName())
					end
				end
			end
		end
	end

	-- debug: summarize and (optionally) inspect
	if DEBUG then
		local n = 0; for _ in pairs(set) do n += 1 end
		print(string.format("[ZoneValidation] Locked grid count = %d (UnlockParts=%d)", n, unlockPartCount))
	end

	return set
end

-- ②  True if any coord in gridList collides with an unlock grid
local function overlapsUnlocks(player, gridList)
	local unlocks = getUnlockGridSet(player)
	for _, c in ipairs(gridList) do
		if unlocks[c.x .. "," .. c.z] then
			return true
		end
	end
	return false
end

-- True if any coord in gridList collides with ANY existing road grid
local function overlapsAnyRoad(player, gridList)
	-- Build a set of all road cells for this player
	local roadSet = {}
	local allZones = ZoneTrackerModule.getAllZones(player)
	for _, zone in pairs(allZones) do
		if RoadTypes[zone.mode] then
			for _, c in ipairs(zone.gridList) do
				roadSet[c.x .. "," .. c.z] = true
			end
		end
	end
	-- Check exact cell intersection
	for _, c in ipairs(gridList) do
		if roadSet[c.x .. "," .. c.z] then
			return true
		end
	end
	return false
end

-- Function to split a new zone around existing roads
local function splitZoneAroundRoad(newZoneGridList, roadGridList)
	debugPrint("Splitting zone around roads.")

	local splitZones = {}
	local visited = {}
	local roadSet = {}

	-- Create a set for quick road grid lookup
	for _, coord in ipairs(roadGridList) do
		local key = coord.x .. "," .. coord.z
		roadSet[key] = true
	end

	-- Create a set for the new zone grids excluding roads
	local zoneSet = {}
	for _, coord in ipairs(newZoneGridList) do
		local key = coord.x .. "," .. coord.z
		if not roadSet[key] then
			zoneSet[key] = true
		end
	end

	-- Depth-First Search to find connected components
	local function dfs(coord, currentZone)
		local key = coord.x .. "," .. coord.z
		if visited[key] or not zoneSet[key] then return end
		visited[key] = true
		table.insert(currentZone, coord)

		local neighbors = {
			{ x = coord.x + 1, z = coord.z },
			{ x = coord.x - 1, z = coord.z },
			{ x = coord.x, z = coord.z + 1 },
			{ x = coord.x, z = coord.z - 1 },
		}

		for _, neighbor in ipairs(neighbors) do
			local neighborKey = neighbor.x .. "," .. neighbor.z
			if zoneSet[neighborKey] and not visited[neighborKey] then
				dfs(neighbor, currentZone)
			end
		end
	end

	-- Iterate through all zone grids to identify connected components
	for _, coord in ipairs(newZoneGridList) do
		local key = coord.x .. "," .. coord.z
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
}

-- NEW: the six *building* zone types we explicitly allow roads to cross
local BuildZoneTypes = {
	Residential = true,  ResDense  = true,
	Commercial  = true,  CommDense = true,
	Industrial  = true,  IndusDense= true,
}

ZoneValidationModule.OverlayZoneTypes = IgnoreValidation

-- Function to validate zone creation
function ZoneValidationModule.validateZone(player, mode, gridList)
	debugPrint("Validating zone for player:", player.Name, "Mode:", mode)

	-- 1) Basic checks
	if not isValidPlayer(player) then
		warn("validateZone: Invalid player provided.")
		return false, "Invalid player."
	end
	if not (type(mode) == "string" and type(gridList) == "table") then
		warn("validateZone: Invalid parameters. Expected (Player, string, table).")
		return false, "Invalid parameters."
	end
	if not gridList or #gridList == 0 then
		warn("validateZone: gridList is nil or empty.")
		return false, "Invalid grid selection."
	end
	for _, coord in ipairs(gridList) do
		if type(coord) ~= "table" or type(coord.x) ~= "number" or type(coord.z) ~= "number" then
			warn("validateZone: Invalid coordinate detected:", tostring(coord))
			return false, "Invalid coordinates provided."
		end
	end

	-- Reject any overlap with Unlock parts (or legacy locked cells)
	if overlapsUnlocks(player, gridList) then
		if DEBUG then
			local u = getUnlockGridSet(player)
			for _, c in ipairs(gridList) do
				local k = c.x .. "," .. c.z
				if u[k] then print("[DEBUG] Overlap at", k) end
			end
		end
		warn("validateZone: Selection overlaps an unlock part for player:", player.Name)
		return false, "You cannot build over an unlockable item."
	end

	-- 2) Short-circuit rules with overlay-vs-road restriction
	-- Pipes & power lines may be built through anything (unchanged).
	if mode == "WaterPipe" or mode == "PowerLines" or mode == "MetroTunnel" then
		debugPrint(mode, "can be built through other zones. Validation passed.")
		return true, ("Valid %s placement."):format(mode)
	end

	-- Overlay/IgnoreValidation types cannot cross roads and cannot overlap *any* existing non-road zone.
	if IgnoreValidation[mode] then
		if overlapsAnyRoad(player, gridList) then
			warn(("validateZone: %s overlaps a road. Not allowed."):format(mode))
			return false, ("You cannot place %s on top of roads."):format(mode)
		end

		-- Allow overlays to be placed over BUILDING zones; still block non-crossables.
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
				return false, ("You cannot place %s on top of existing zones."):format(mode)
			end
		end

		debugPrint(mode, "is an overlay type; no road crossing and no stacking. Validation passed.")
		return true, ("Valid %s placement (no road crossing, no stacking)."):format(mode)
	end

	-- 3) Check for required infrastructure (placeholder check)
	if not hasRequiredInfrastructure(gridList) then
		warn("validateZone: Required infrastructure missing for player:", player.Name)
		return false, "Required infrastructure is not nearby."
	end

	-- 4) Gather overlapping zones, ignoring water pipes, power lines, and metro tunnels
	local allZones = ZoneTrackerModule.getAllZones(player)
	local overlappingZones = {}
	local sameTypeZones = {}
	local roadOverlaps = {}

	for _, zone in pairs(allZones) do
		-- Ignore underground/utility for overlap logic
		if zone.mode ~= "WaterPipe" and zone.mode ~= "PowerLines" and zone.mode ~= "MetroTunnel" then
			if zonesOverlap(zone.gridList, gridList) then
				table.insert(overlappingZones, zone)
				if zone.mode == mode then
					table.insert(sameTypeZones, zone)
				end
				if RoadTypes[zone.mode] then
					table.insert(roadOverlaps, zone)
				end
			end
		end
	end

	debugPrint(string.format("Found %d overlapping zones, %d same-type, %d are roads.",
		#overlappingZones, #sameTypeZones, #roadOverlaps))

	-- 5) If we’re building a non-road zone and found overlaps:
	if #overlappingZones > 0 and not RoadTypes[mode] then
		-- Possibly split around roads
		if #roadOverlaps > 0 then
			debugPrint("Zone overlaps with roads. Splitting into multiple zones.")
			-- Combine all road coords
			local allRoadGridsSet = {}
			local allRoadGridList = {}
			for _, roadZone in ipairs(roadOverlaps) do
				for _, c in ipairs(roadZone.gridList) do
					local key = c.x .. "," .. c.z
					if not allRoadGridsSet[key] then
						allRoadGridsSet[key] = true
						table.insert(allRoadGridList, c)
					end
				end
			end
			-- Attempt to split
			local splitZones = splitZoneAroundRoad(gridList, allRoadGridList)
			if splitZones and #splitZones > 1 then
				return true, "Zone split due to road overlap.", splitZones
			end
		end

		-- Check for any overlapping zones that are *not* the same mode & not roads
		local hasNonRoadOverlap = false
		for _, zone in ipairs(overlappingZones) do
			if not RoadTypes[zone.mode] and zone.mode ~= mode then
				hasNonRoadOverlap = true
				debugPrint("Overlapping a different non-road zone. Not allowed.")
				break
			end
		end
		if hasNonRoadOverlap then
			warn("validateZone: Overlapping with different type zones. Validation failed.")
			return false, "Selected area overlaps with existing zones of a different type."
		end

		if #sameTypeZones > 0 then
			debugPrint("Overlapping with same-type zones. Merging them.")
			return true, "Zones will be merged.", sameTypeZones
		end
	end

	-- 6) Exclude pipes & lines from occupant checks (like roads)
	local OverlapExclusions = {}
	for roadTypeName, _ in pairs(RoadTypes) do
		OverlapExclusions[roadTypeName] = true
	end
	OverlapExclusions["WaterPipe"]   = true
	OverlapExclusions["PowerLines"]  = true
	OverlapExclusions["MetroTunnel"] = true

	-- === Road placement through *building* zones ===
	if RoadTypes[mode] then
		-- Allow crossing the six building zone types by excluding them from occupancy checks.
		for zt, _ in pairs(BuildZoneTypes) do
			OverlapExclusions[zt] = true
		end

		debugPrint("Building a Road: permitting crossing of building zones (Res/Com/Ind + Dense).")

		-- Filter out ONLY cells blocked by non-crossable things (e.g., landmarks/overlays), not buildings.
		local filteredGridList = {}
		for _, coord in ipairs(gridList) do
			local occupied = ZoneTrackerModule.isGridOccupied(
				player, coord.x, coord.z,
				{ excludeZoneTypes = OverlapExclusions }
			)
			if not occupied then
				table.insert(filteredGridList, coord)
			else
				debugPrint(string.format("Excluding grid (%d, %d) – blocked by non-crossable occupant.", coord.x, coord.z))
			end
		end

		if #filteredGridList == 0 then
			warn("validateZone: All selected grids are blocked by non-crossable occupants.")
			return false, "All selected grids are blocked by non-crossable items."
		end

		-- Split into connected components
		local connectedComponents = GridUtils.splitIntoConnectedComponents(filteredGridList)
		if #connectedComponents == 0 then
			warn("validateZone: No valid areas to create roads after exclusions.")
			return false, "No valid areas to create roads."
		end

		-- Validate each component (using the same exclusions)
		local validComponents = {}
		for _, component in ipairs(connectedComponents) do
			local cIsValid = true
			for _, coord in ipairs(component) do
				if ZoneTrackerModule.isGridOccupied(
					player, coord.x, coord.z,
					{ excludeZoneTypes = OverlapExclusions }
					) then
					cIsValid = false
					debugPrint(string.format("Grid (%d, %d) in this component is blocked by a non-crossable item.", coord.x, coord.z))
					break
				end
			end
			if cIsValid then
				table.insert(validComponents, component)
			end
		end

		if #validComponents == 0 then
			warn("validateZone: No valid road segments found after occupant checks.")
			return false, "No valid road segments."
		end

		return true, "Valid road components found.", validComponents
	else
		-- 8) Non-road, non-pipe zone => do occupant checks excluding roads/pipes/lines
		local connectedComponents = GridUtils.splitIntoConnectedComponents(gridList)
		if #connectedComponents == 0 then
			warn("validateZone: No valid areas to create zones.")
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
			if cIsValid then
				table.insert(validComponents, component)
			end
		end

		if #validComponents == 0 then
			warn("validateZone: No valid areas to create zones after excluding roads/pipes/lines.")
			return false, "No valid areas to create zones."
		end

		return true, "Valid zone components found.", validComponents
	end
end

-- Function to handle zone merging
function ZoneValidationModule.handleMerging(player, mode, zoneId, gridList, sameTypeZones)
	debugPrint("Handling merging for zone:", zoneId)

	-- Input Validation
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

	-- Create new zone data
	local newZone = {
		zoneId = zoneId,
		player = player,
		mode = mode,
		gridList = gridList,
		requirements = {
			Roads = true,
			Water = true,
			Power = true,
			-- Add other requirements as needed
		}
	}

	-- Merge with existing zones
	newZone = mergeZones(newZone, sameTypeZones)

	-- Add the merged zone to ZoneTracker
	local success = ZoneTrackerModule.addZone(player, newZone.zoneId, newZone.mode, newZone.gridList)
	if success then
		debugPrint("Merged zone added successfully.")
		return newZone
	else
		warn("handleMerging: Failed to add merged zone.")
		return nil
	end
end

-- Function to validate a single grid position (utility function)
function ZoneValidationModule.validateSingleGrid(player, mode, gridPosition)
	debugPrint("Validating single grid for player:", player.Name, "Mode:", mode)

	-- Input Validation
	if not isValidPlayer(player) then
		warn("validateSingleGrid: Invalid player provided.")
		return false, "Invalid player."
	end
	if not (type(gridPosition) == "table" and type(gridPosition.x) == "number" and type(gridPosition.z) == "number") then
		warn("validateSingleGrid: Invalid grid position.")
		return false, "Invalid grid position."
	end

	-- Overlay/IgnoreValidation types ignore roads but MAY NOT overlap existing zones (non-road/pipe/line/metro).
	if IgnoreValidation[mode] then
		if overlapsAnyRoad(player, { gridPosition }) then
			return false, ("You cannot place %s on top of roads."):format(mode)
		end
		if overlapsUnlocks(player, { gridPosition }) then
			return false, "That spot is reserved for an unlockable item."
		end

		-- Allow overlays to stack on BUILDING zones; still prevent stacking over other overlays/landmarks.
		local exclusions = {}
		for k,_ in pairs(RoadTypes) do exclusions[k] = true end
		exclusions["WaterPipe"]   = true
		exclusions["PowerLines"]  = true
		exclusions["MetroTunnel"] = true
		for zt,_ in pairs(BuildZoneTypes) do exclusions[zt] = true end  -- <— ADD THIS

		if ZoneTrackerModule.isGridOccupied(
			player, gridPosition.x, gridPosition.z,
			{ excludeZoneTypes = exclusions }
			) then
			return false, ("You cannot place %s on top of existing zones."):format(mode)
		end

		debugPrint("Grid position is valid for overlay type (no road crossing, no stacking).")
		return true, "Valid grid position."
	end

	-- Roads: allow crossing buildings; block only non-crossable items
	if RoadTypes[mode] then
		if overlapsUnlocks(player, {gridPosition}) then
			return false, "That spot is reserved for an unlockable item."
		end
		local exclusions = {}
		for k,_ in pairs(RoadTypes) do exclusions[k] = true end
		exclusions["WaterPipe"]   = true
		exclusions["PowerLines"]  = true
		exclusions["MetroTunnel"] = true
		for zt,_ in pairs(BuildZoneTypes) do exclusions[zt] = true end

		local blocked = ZoneTrackerModule.isGridOccupied(
			player, gridPosition.x, gridPosition.z, { excludeZoneTypes = exclusions }
		)
		if blocked then
			return false, "Blocked by a non-crossable item."
		end
		return true, "Valid road cell."
	end

	-- Default behavior for all other types:
	if ZoneTrackerModule.isGridOccupied(player, gridPosition.x, gridPosition.z) then
		warn(string.format(
			"validateSingleGrid: Grid position (%d, %d) is already occupied.",
			gridPosition.x, gridPosition.z
			))
		return false, "Selected grid is already occupied."
	end

	if overlapsUnlocks(player, {gridPosition}) then
		return false, "That spot is reserved for an unlockable item."
	end

	debugPrint("Grid position is valid.")
	return true, "Valid grid position."
end

return ZoneValidationModule
