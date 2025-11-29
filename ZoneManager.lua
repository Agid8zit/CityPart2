--[[
Script Order: 5
Script Name: ZoneManager.lua
Description: Main module that handles zone selection and grid interactions.
Dependencies: ZoneValidation.lua, ZoneTracker.lua, ZoneDisplay.lua, RoadTypes.lua
Dependents: ZoneManagerScript.lua
]]--

-- Configuration
local DEBUG = true  

-- Debug print function toggle the stuff above
local function debugPrint(...)
	if DEBUG then
		print("[ZoneManager]", ...)
	end
end

local ZoneManager = {}
ZoneManager.__index = ZoneManager

-- References
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEvents = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents")
local BindableEvents = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents")
local S3 = game:GetService("ServerScriptService")
local Build    = S3:WaitForChild("Build")
local Zones    = Build:WaitForChild("Zones")

local zoneCreatedEvent = BindableEvents:WaitForChild("ZoneCreated")
local displayGridEvent = RemoteEvents:WaitForChild("DisplayGrid")
local notifyZoneCreatedEvent = RemoteEvents:WaitForChild("NotifyZoneCreated")
local placeWaterTowerEvent = RemoteEvents:WaitForChild("PlaceWaterTower")
local RoadGen = require(S3.Build.Transport.Roads.CoreConcepts.Roads.RoadGen.RoadGenerator)

local success, ZoneValidationModule = pcall(require, script.Parent:WaitForChild("ZoneValidation"))
if not success then
	error("ZoneManager: Failed to load ZoneValidation module.")
end

local success, ZoneTrackerModule = pcall(require, script.Parent:WaitForChild("ZoneTracker"))
if not success then
	error("ZoneManager: Failed to load ZoneTracker module.")
end

local RoadTypes = require(script.Parent:WaitForChild("RoadTypes"))

-- Grid Utilities
local Scripts = ReplicatedStorage:WaitForChild("Scripts")
local GridConf = Scripts:WaitForChild("Grid")
local GridUtils = require(GridConf:WaitForChild("GridUtil"))

local PathingModule = require(S3:WaitForChild("Build"):WaitForChild("Transport"):WaitForChild("Roads"):WaitForChild("CoreConcepts"):WaitForChild("Pathing"):WaitForChild("PathingModule"))
local CC = Zones:WaitForChild("CoreConcepts"):WaitForChild("PowerGen")
local PowerLinePath = require(CC:WaitForChild("PowerLinePath"))
-- Current Mode per player
local playerModes = {}

-- Unique Zone Identifier per player
ZoneManager.playerZoneCounters = {}

-- Configuration for different zone types
local ZoneTypes = {
	--Zones
	Residential = {
		displayName = "Residential",
		gridType = "Residential",
	},
	Commercial = {
		displayName = "Commercial",
		gridType = "Commercial",
	},
	Industrial = {
		displayName = "Industrial",
		gridType = "Industrial",
	},
	ResDense = {
		displayName = "Residential High Density",
		gridType = "ResDense",
	},
	CommDense = {
		displayName = "Commercial High Density",
		gridType = "CommDense",
	},
	IndusDense = {
		displayName = "Industrial High Density",
		gridType = "IndusDense",
	},
	-- Utility
	DirtRoad = {
		displayName = "Dirt Road",
		gridType = "DirtRoad",
	},
	Pavement = {
		displayName = "Pavement",
		gridType = "Pavement",
	},
	Highway = {
		displayName = "Highway",
		gridType = "Highway",
	},
	WaterTower = {
		displayName = "Water Tower",
		gridType = "WaterTower",
	},
	WaterPipe = {
		displayName = "Water Pipe",
		gridType = "WaterPipe",
	},
	PowerLines = {
		displayName = "Power Line",
		gridType = "PowerLines",
	},
	
	
	--Individual
	--Fire
	FireDept = {
		displayName = "Fire Dept",
		gridType = "FireDept",
	},
	FirePrecinct = {
		displayName = "Fire Precinct",
		gridType = "FirePrecinct",
	},
	FireStation = {
		displayName = "Fire Station",
		gridType = "FireStation",
	},
	--Education
	MiddleSchool = {
		displayName = "Middle School",
		gridType = "MiddleSchool",
	},
	Museum = {
		displayName = "Museum",
		gridType = "Museum",
	},
	NewsStation = {
		displayName = "News Station",
		gridType = "NewsStation",
	},
	PrivateSchool = {
		displayName = "Private School",
		gridType = "PrivateSchool",
	},
	--Health
	CityHospital = {
		displayName = "City Hospital",
		gridType = "CityHospital",
	},
	LocalHospital = {
		displayName = "Local Hospital",
		gridType = "LocalHospital",
	},
	MajorHospital = {
		displayName = "Major Hospital",
		gridType = "MajorHospital",
	},
	SmallClinic = {
		displayName = "Small Clinic",
		gridType = "SmallClinic",
	},
	--Landmark
	Bank = {
		displayName = "Bank",
		gridType = "Bank",
	},
	CNTower = {
		displayName = "CN Tower",
		gridType = "CNTower",
	},
	EiffelTower = {
		displayName = "Eiffel Tower",
		gridType = "EiffelTower",
	},
	EmpireStateBuilding = {
		displayName = "Empire State Building",
		gridType = "EmpireStateBuilding",
	},
	FerrisWheel = {
		displayName = "Ferris Wheel",
		gridType = "FerrisWheel",
	},
	GasStation = {
		displayName = "Gas Station",
		gridType = "GasStation",
	},
	ModernSkyscraper = {
		displayName = "Modern Skyscraper",
		gridType = "ModernSkyscraper",
	},
	NationalCapital = {
		displayName = "National Capital",
		gridType = "NationalCapital",
	},
	Obelisk = {
		displayName = "Obelisk",
		gridType = "Obelisk",
	},
	SpaceNeedle = {
		displayName = "Space Needle",
		gridType = "SpaceNeedle",
	},
	StatueOfLiberty = {
		displayName = "Statue Of Liberty",
		gridType = "StatueOfLiberty",
	},
	TechOffice = {
		displayName = "Tech Office",
		gridType = "TechOffice",
	},
	WorldTradeCenter = {
		displayName = "World Trade Center",
		gridType = "WorldTradeCenter",
	},
	--Leisure
	Church = {
		displayName = "Church",
		gridType = "Church",
	},
	Hotel = {
		displayName = "Hotel",
		gridType = "Hotel",
	},
	Mosque = {
		displayName = "Mosque",
		gridType = "Mosque",
	},
	MovieTheater = {
		displayName = "Movie Theater",
		gridType = "MovieTheater",
	},
	ShintoTemple = {
		displayName = "Shinto Temple",
		gridType = "ShintoTemple",
	},
	HinduTemple = {
		displayName = "Hindu Temple",
		gridType = "HinduTemple",
	},
	BuddhaStatue = {
		displayName = "BuddhaStatue",
		gridType = "Buddha Statue",
	},
	--Police
	Courthouse = {
		displayName = "Courthouse",
		gridType = "Courthouse",
	},
	PoliceDept = {
		displayName = "Police Dept",
		gridType = "PoliceDept",
	},
	PolicePrecinct = {
		displayName = "Police Precinct",
		gridType = "PolicePrecinct",
	},
	PoliceStation = {
		displayName = "Police Station",
		gridType = "PoliceStation",
	},
	-- Flags (category)
	Flags = {
		displayName = "Flags",
		gridType = "Flags",
	},
	--Sports
	ArcheryRange = {
		displayName = "Archery Range",
		gridType = "ArcheryRange",
	},
	BasketballCourt = {
		displayName = "Basketball Court",
		gridType = "BasketballCourt",
	},
	BasketballStadium = {
		displayName = "Basketball Stadium",
		gridType = "BasketballStadium",
	},
	FootballStadium = {
		displayName = "Football Stadium",
		gridType = "FootballStadium",
	},
	GolfCourse = {
		displayName = "Golf Course",
		gridType = "GolfCourse",
	},
	PublicPool = {
		displayName = "Public Pool",
		gridType = "PublicPool",
	},
	SkatePark = {
		displayName = "Skate Park",
		gridType = "SkatePark",
	},
	SoccerStadium = {
		displayName = "Soccer Stadium",
		gridType = "SoccerStadium",
	},
	TennisCourt = {
		displayName = "Tennis Court",
		gridType = "TennisCourt",
	},
	--Transportation
	Airport = {
		displayName = "Airport",
		gridType = "Airport",
	},
	BusDepot = {
		displayName = "Bus Depot",
		gridType = "BusDepot",
	},
	Metro = {
		displayName = "Metro",
		gridType = "Metro",
	},
	MetroTunnel = {
		displayName = "Metro Tunnel",
		gridType = "MetroTunnel",
	},
	--Power
	CoalPowerPlant = {
		displayName = "Coal Power Plant",
		gridType = "CoalPowerPlant",
	},
	GasPowerPlant = {
		displayName = "Gas Power Plant",
		gridType = "GasPowerPlant",
	},
	GeothermalPowerPlant = {
		displayName = "Geothermal Power Plant",
		gridType = "GeothermalPowerPlant",
	},
	NuclearPowerPlant = {
		displayName = "Nuclear Power Plant",
		gridType = "NuclearPowerPlant",
	},
	SolarPanels = {
		displayName = "Solar Panels",
		gridType = "SolarPanels",
	},
	WindTurbine = {
		displayName = "Wind Turbine",
		gridType = "WindTurbine",
	},
	--Water stuff
	WaterPlant ={
		displayName = "Water Plant",
		gridType = "WaterPlant",
	},
	PurificationWaterPlant = {
		displayName = "Water Purification Plant",
		gridtype = "PurificationWaterPlant",
	},
	MolecularWaterPlant = {
		displayName = "Molecular Water Plant",
		gridType = "MolecularWaterPlant",
	},
	
	-- Add more zone types as needed
}

-- Handler for SelectZoneType
function ZoneManager.onSelectZoneType(player, zoneType)
	debugPrint("Player", player.Name, "selected zone type:", zoneType)

	local selectedZone = ZoneTypes[zoneType]
	
	local isDynamicFlag = (type(zoneType)=="string" and zoneType:sub(1,5)=="Flag:")
	if isDynamicFlag then
		playerModes[player.UserId] = zoneType
		local gridType = "Flags"
		if displayGridEvent then
			displayGridEvent:FireClient(player, gridType)
			debugPrint("'DisplayGrid' event fired to player:", player.Name, "GridType:", gridType)
		else
			warn("DisplayGrid RemoteEvent not found")
		end
		return
	end

	if selectedZone then
		playerModes[player.UserId] = zoneType

		-- Display Grid Client Side with appropriate grid type
		if displayGridEvent then
			local gridType = selectedZone.gridType or zoneType
			displayGridEvent:FireClient(player, gridType)
			debugPrint("'DisplayGrid' event fired to player:", player.Name, "GridType:", gridType)
		else
			warn("DisplayGrid RemoteEvent not found")
		end
	else
		warn("Unsupported zone type selected by player:", player.Name, zoneType)
	end
end

-- Handler for GridSelection
function ZoneManager.onGridSelection(player, selectedCoords)
	debugPrint("Player", player.Name, "selected coordinates:", selectedCoords)

	-- Retrieve the current mode for the player
	local mode = playerModes[player.UserId]
	if not mode then
		warn("Player has not selected a zone type:", player.Name)
		return
	end

	-- Retrieve the zone configuration based on the selected mode
	local selectedZone = ZoneTypes[mode]
	if not selectedZone then
		warn("Invalid zone type for player:", player.Name, mode)
		return
	end

	-- Validate the format of selectedCoords
	if type(selectedCoords) ~= "table" or not selectedCoords.start or not selectedCoords.finish then
		warn("Invalid selectedCoords provided by player:", player.Name)
		if notifyZoneCreatedEvent then
			notifyZoneCreatedEvent:FireClient(player, "ValidationFailed", "Invalid coordinate format.")
		end
		return
	end

	-- Generate Grid List Using GridUtils
	local gridList = GridUtils.getGridList(selectedCoords.start, selectedCoords.finish)
	debugPrint("Generated grid list:")
	for _, coord in ipairs(gridList) do
		debugPrint(string.format("  Grid (%d, %d)", coord.x, coord.z))
	end

	-- Validate the zone with gridList
	local isValid, message, validComponents = ZoneValidationModule.validateZone(player, mode, gridList)
	if not isValid then
		-- Notify the player about validation failure
		if notifyZoneCreatedEvent then
			notifyZoneCreatedEvent:FireClient(player, "ValidationFailed", message)
			debugPrint("Validation failed for player:", player.Name, "Reason:", message)
		else
			warn("NotifyZoneCreated RemoteEvent not found")
		end
		return
	end

	if message == "Zones will be merged." then
		-- Handle merging zones
		local userId = player.UserId
		ZoneManager.playerZoneCounters[userId] = (ZoneManager.playerZoneCounters[userId] or 0) + 1
		local zoneId = "Zone_" .. userId .. "_" .. ZoneManager.playerZoneCounters[userId]
		local mergedZone = ZoneValidationModule.handleMerging(player, mode, zoneId, gridList, validComponents)
		if mergedZone then
			-- Notify the player about the merged zone
			if notifyZoneCreatedEvent then
				notifyZoneCreatedEvent:FireClient(player, "ZoneCreated", {
					zoneId = mergedZone.zoneId,
					mode = mergedZone.mode,
					gridList = mergedZone.gridList
				})
				debugPrint("'NotifyZoneCreated' RemoteEvent fired to player:", player.Name, "ZoneId:", mergedZone.zoneId)
			else
				warn("NotifyZoneCreated RemoteEvent not found")
			end
		else
			warn("Zone merging failed for player:", player.Name)
			if notifyZoneCreatedEvent then
				notifyZoneCreatedEvent:FireClient(player, "ValidationFailed", "Zone merging failed.")
			end
		end
	elseif message == "Zone split due to road overlap." then
		-- Handle zone splitting
		local userId = player.UserId

		for _, splitZoneGrid in ipairs(validComponents) do
			-- Increment the zone counter for each new zone
			ZoneManager.playerZoneCounters[userId] = (ZoneManager.playerZoneCounters[userId] or 0) + 1
			local zoneId = "Zone_" .. userId .. "_" .. ZoneManager.playerZoneCounters[userId]

			-- Fire BindableEvent to notify other modules about the new split zone
			if zoneCreatedEvent then
				zoneCreatedEvent:Fire(player, zoneId, mode, splitZoneGrid)
				debugPrint("'ZoneCreated' BindableEvent fired for split zone:", zoneId)
			else
				warn("ZoneCreated BindableEvent not found")
			end

			-- Notify the specific player about zone creation via RemoteEvent
			if notifyZoneCreatedEvent then
				notifyZoneCreatedEvent:FireClient(player, "ZoneCreated", {
					zoneId = zoneId,
					mode = mode,
					gridList = splitZoneGrid
				})
				debugPrint("'NotifyZoneCreated' RemoteEvent fired to player:", player.Name, "ZoneId:", zoneId)
			else
				warn("NotifyZoneCreated RemoteEvent not found")
			end
		end
	else
		-- Assign a Unique Zone ID using per-player zone counter
		local userId = player.UserId
		local newZoneIds = {}  -- To keep track of newly created zone IDs

		for _, componentGridList in ipairs(validComponents) do
			ZoneManager.playerZoneCounters[userId] = (ZoneManager.playerZoneCounters[userId] or 0) + 1
			local zoneId = "Zone_" .. userId .. "_" .. ZoneManager.playerZoneCounters[userId]
			table.insert(newZoneIds, zoneId)

			-- Fire BindableEvent to notify other modules about the new zone
			if zoneCreatedEvent then
				zoneCreatedEvent:Fire(player, zoneId, mode, componentGridList)
				debugPrint("'ZoneCreated' BindableEvent fired for player:", player.Name, "Mode:", mode, "ZoneId:", zoneId)
			else
				warn("ZoneCreated BindableEvent not found")
			end

			-- Notify the specific player about zone creation via RemoteEvent
			if notifyZoneCreatedEvent then
				notifyZoneCreatedEvent:FireClient(player, "ZoneCreated", {
					zoneId = zoneId,
					mode = mode,
					gridList = componentGridList
				})
				debugPrint("'NotifyZoneCreated' RemoteEvent fired to player:", player.Name, "ZoneId:", zoneId)
			else
				warn("NotifyZoneCreated RemoteEvent not found")
			end
		end

		-- Notify the player about the split zones if multiple zones were created
		if #newZoneIds > 1 and notifyZoneCreatedEvent then
			notifyZoneCreatedEvent:FireClient(player, "ZoneSplit", {
				originalZoneId = newZoneIds[1],  -- Assuming the first zone ID is the original
				newZoneIds = newZoneIds
			})
			debugPrint("Player notified about zone split due to road overlaps.")
		end
	end

	-- Reset Player Mode
	playerModes[player.UserId] = nil
end

-- Function to handle building roads
function ZoneManager.buildRoad(player, startCoord, endCoord, mode)
	if not RoadTypes[mode] then
		debugPrint("Invalid road type attempted:", mode)
		return false, "Invalid road type."
	end

	-- Validate startCoord and endCoord
	if type(startCoord) ~= "table" or type(endCoord) ~= "table" then
		debugPrint("Invalid coordinates provided for road.")
		return false, "Invalid coordinates."
	end

	-- Calculate the path between start and end coordinates
	local pathCoords = GridUtils.getGridList(startCoord, endCoord)
	if not pathCoords or #pathCoords == 0 then
		debugPrint("Invalid path provided for road.")
		return false, "Invalid path."
	end

	-- Validate the road placement using ZoneValidationModule
	local isValid, message, validComponents = ZoneValidationModule.validateZone(player, mode, pathCoords)
	if not isValid then
		debugPrint("Road validation failed:", message)
		-- Handle specific road validation failure messages
		if message == "Cannot build road through existing zones." and notifyZoneCreatedEvent then
			notifyZoneCreatedEvent:FireClient(player, "CannotBuildRoad", "Cannot build road through existing zones.")
		elseif notifyZoneCreatedEvent then
			notifyZoneCreatedEvent:FireClient(player, "ValidationFailed", message)
		end
		return false, message
	end

	local firstZoneId = nil

	-- Proceed with road creation for each valid component
	for _, component in ipairs(validComponents) do
		-- Assign a Unique Zone ID using per-player counter
		local userId = player.UserId
		ZoneManager.playerZoneCounters[userId] = (ZoneManager.playerZoneCounters[userId] or 0) + 1
		local zoneId = "RoadZone_" .. userId .. "_" .. ZoneManager.playerZoneCounters[userId]

		-- Register the Road with PathingModule BEFORE firing the event
		PathingModule.registerRoad(zoneId, mode, component, startCoord, endCoord, userId)
		debugPrint("Road registered with PathingModule.")

		-- Fire the ZoneCreated event
		if zoneCreatedEvent then
			zoneCreatedEvent:Fire(player, zoneId, mode, component)
			debugPrint("'ZoneCreated' event fired for road zone:", zoneId)
		else
			warn("ZoneCreated BindableEvent not found")
			return false, "Internal error: ZoneCreated event not found."
		end

		-- Notify the player about the successful road creation
		if notifyZoneCreatedEvent then
			notifyZoneCreatedEvent:FireClient(player, "ZoneCreated", {
				zoneId = zoneId,
				mode = mode,
				gridList = component
			})
			debugPrint("'NotifyZoneCreated' RemoteEvent fired to player:", player.Name, "ZoneId:", zoneId)
		else
			warn("NotifyZoneCreated RemoteEvent not found")
		end

		-- If this is the first successful road, store its zoneId
		if not firstZoneId then
			firstZoneId = zoneId
		end
	end

	-- If no road segments were created (validComponents empty), return false
	if not firstZoneId then
		debugPrint("No valid road segments created.")
		return false, "No valid road segments."
	end

	-- Return true along with the first created zoneId
	return true, firstZoneId
end

-- Function to remove a road (used by BuildRoadCommand's undo)
function ZoneManager.removeRoad(player, roadId)
	local zoneData = ZoneTrackerModule.getZoneById(player, roadId)
	if not zoneData then
		warn("ZoneManager: Attempted to remove non-existent road:", roadId)
		return false
	end

	local mode = zoneData.mode
	local gridList = zoneData.gridList

	local success = ZoneTrackerModule.removeZone(player, roadId, mode, gridList)
	if success then
		PathingModule.unregisterRoad(roadId, player and player.UserId)
		RoadGen.recalculateIntersectionsForPlot(player)
		-- Fire the zoneRemoveDisplayEvent with just the zoneId
		--[[
		local zoneRemoveDisplayEvent = RemoteEvents:WaitForChild("ZoneRemoveDisplay")
		zoneRemoveDisplayEvent:FireClient(player, roadId)
		]]
		return true
	else
		warn("ZoneManager: Failed to remove road:", roadId)
		return false
	end
end

-- Function to handle building pipes
function ZoneManager.buildPipe(player, startCoord, endCoord, mode)
	-- 1) Confirm it really is "WaterPipe"
	if mode ~= "WaterPipe" then
		debugPrint("Invalid pipe type attempted:", mode)
		return false, "Invalid pipe type."
	end

	-- 2) Validate start/end coords
	if type(startCoord) ~= "table" or type(endCoord) ~= "table" then
		debugPrint("Invalid coordinates provided for pipe.")
		return false, "Invalid coordinates."
	end

	-- 3) Get list of all grid cells from startCoord to endCoord
	local pathCoords = GridUtils.getGridList(startCoord, endCoord)
	if not pathCoords or #pathCoords == 0 then
		debugPrint("Invalid path provided for pipe.")
		return false, "Invalid path."
	end

	-- 4) (OPTIONAL) If you want to check with ZoneValidation so it fully ignores overlap:
	--    This will skip all overlap checks because your ZoneValidation treats "WaterPipe" as free.
	--    If you're certain you want no checks at all, you can skip this step. 
	local isValid, message = ZoneValidationModule.validateZone(player, "WaterPipe", pathCoords)
	if not isValid then
		debugPrint("Pipe validation failed:", message)
		if notifyZoneCreatedEvent then
			notifyZoneCreatedEvent:FireClient(player, "ValidationFailed", message)
		end
		return false, message
	end

	-- 5) Create a unique ID for this pipe zone
	local userId = player.UserId
	ZoneManager.playerZoneCounters[userId] = (ZoneManager.playerZoneCounters[userId] or 0) + 1
	local zoneId = "PipeZone_" .. userId .. "_" .. ZoneManager.playerZoneCounters[userId]

	-- 6) Fire "ZoneCreated" so the game spawns/visualizes the pipe
	if zoneCreatedEvent then
		zoneCreatedEvent:Fire(player, zoneId, mode, pathCoords)
		debugPrint("'ZoneCreated' BindableEvent fired for pipe zone:", zoneId)
	else
		warn("ZoneCreated BindableEvent not found")
		return false, "Internal error: ZoneCreated event not found."
	end

	-- 7) Notify the player that the pipe was created
	if notifyZoneCreatedEvent then
		notifyZoneCreatedEvent:FireClient(player, "ZoneCreated", {
			zoneId = zoneId,
			mode = mode,
			gridList = pathCoords
		})
		debugPrint("'NotifyZoneCreated' RemoteEvent fired to player:", player.Name, "ZoneId:", zoneId)
	else
		warn("NotifyZoneCreated RemoteEvent not found")
	end

	return true, zoneId
end

function ZoneManager.removePipe(player, pipeId)
	local zoneData = ZoneTrackerModule.getZoneById(player, pipeId)
	if not zoneData then
		warn("ZoneManager: Failed to find zone data for zoneId:", pipeId)
		return false
	end

	local success = ZoneTrackerModule.removeZone(player, pipeId, zoneData.mode, zoneData.gridList)
	if success then
		-- Fire ZoneRemoved so NetworkManager can update graphs
		local zoneRemovedEvent = BindableEvents:FindFirstChild("ZoneRemoved")
		if zoneRemovedEvent then
			zoneRemovedEvent:Fire(player, pipeId, zoneData.mode, zoneData.gridList)
		end

		-- Notify client to remove pipe visualization
		if notifyZoneCreatedEvent then
			notifyZoneCreatedEvent:FireClient(player, "ZoneRemoved", pipeId)
		end
		return true
	else
		warn("ZoneManager: Failed to remove pipe:", pipeId)
		return false
	end
end

function ZoneManager.buildPowerLine(player, startCoord, endCoord, mode)
	-- 1) Confirm it really is "PowerLines"
	if mode ~= "PowerLines" then
		debugPrint("Invalid power line type attempted:", mode)
		return false, "Invalid power line type."
	end

	-- 2) Validate start/end coords
	if type(startCoord) ~= "table" or type(endCoord) ~= "table" then
		debugPrint("Invalid coordinates provided for power line.")
		return false, "Invalid coordinates."
	end

	-- 3) Get list of all grid cells from startCoord to endCoord
	local pathCoords = GridUtils.getGridList(startCoord, endCoord)
	if not pathCoords or #pathCoords == 0 then
		debugPrint("Invalid path provided for power line.")
		return false, "Invalid path."
	end

	-- 4) (Optional) If you want to do some type of validation, like skipping overlap checks,
	--    you can replicate what 'buildPipe' does. Or do something more specialized for power lines.
	local isValid, message = ZoneValidationModule.validateZone(player, "PowerLines", pathCoords)
	if not isValid then
		debugPrint("Power line validation failed:", message)
		if notifyZoneCreatedEvent then
			notifyZoneCreatedEvent:FireClient(player, "ValidationFailed", message)
		end
		return false, message
	end

	-- 5) Create a unique ID for this power line zone
	local userId = player.UserId
	ZoneManager.playerZoneCounters[userId] = (ZoneManager.playerZoneCounters[userId] or 0) + 1
	local zoneId = "PowerLinesZone_" .. userId .. "_" .. ZoneManager.playerZoneCounters[userId]

	local start = startCoord
	local finish = endCoord
	
	PowerLinePath.registerLine(zoneId, mode, pathCoords, start, finish)
	
	-- 6) Fire "ZoneCreated" so the game spawns/visualizes the power line
	if zoneCreatedEvent then
		zoneCreatedEvent:Fire(player, zoneId, mode, pathCoords)
		debugPrint("'ZoneCreated' BindableEvent fired for power line zone:", zoneId)
	else
		warn("ZoneCreated BindableEvent not found")
		return false, "Internal error: ZoneCreated event not found."
	end

	-- 7) Notify the player that the power line was created
	if notifyZoneCreatedEvent then
		notifyZoneCreatedEvent:FireClient(player, "ZoneCreated", {
			zoneId = zoneId,
			mode = mode,
			gridList = pathCoords
		})
		debugPrint("'NotifyZoneCreated' RemoteEvent fired to player:", player.Name, "ZoneId:", zoneId)
	else
		warn("NotifyZoneCreated RemoteEvent not found")
	end

	return true, zoneId
end

function ZoneManager.removePowerLine(player, lineId)
	local zoneData = ZoneTrackerModule.getZoneById(player, lineId)
	if not zoneData then
		warn("ZoneManager: Failed to find zone data for zoneId:", lineId)
		return false
	end

	local mode = zoneData.mode
	local gridList = zoneData.gridList

	local success = ZoneTrackerModule.removeZone(player, lineId, mode, gridList)
	if success then
		-- FIRE THIS:
		local zoneRemovedEvent = BindableEvents:FindFirstChild("ZoneRemoved")
		if zoneRemovedEvent then
			zoneRemovedEvent:Fire(player, lineId, mode, gridList)
			print("[ZoneManager] Fired ZoneRemoved BindableEvent for:", lineId)
		else
			warn("[ZoneManager] ZoneRemoved event not found!")
		end

		return true
	else
		warn("ZoneManager: Failed to remove power line:", lineId)
		return false
	end
end

function ZoneManager.buildMetroTunnel(player, startCoord, endCoord, mode)
	-- 1) Ensure correct mode
	if mode ~= "MetroTunnel" then
		debugPrint("Invalid metro tunnel type attempted:", mode)
		return false, "Invalid metro tunnel type."
	end

	-- 2) Validate coords
	if type(startCoord) ~= "table" or type(endCoord) ~= "table" then
		debugPrint("Invalid coordinates provided for metro tunnel.")
		return false, "Invalid coordinates."
	end

	-- 3) Build path (cardinal or Bresenham same as pipes/power)
	local pathCoords = GridUtils.getGridList(startCoord, endCoord)
	if not pathCoords or #pathCoords == 0 then
		debugPrint("Invalid path provided for metro tunnel.")
		return false, "Invalid path."
	end

	-- 4) Validation (treat like a free-overlap utility, or tailor in ZoneValidation if needed)
	local isValid, message = ZoneValidationModule.validateZone(player, "MetroTunnel", pathCoords)
	if not isValid then
		debugPrint("MetroTunnel validation failed:", message)
		if notifyZoneCreatedEvent then
			notifyZoneCreatedEvent:FireClient(player, "ValidationFailed", message)
		end
		return false, message
	end

	-- 5) Unique ID
	local userId = player.UserId
	ZoneManager.playerZoneCounters[userId] = (ZoneManager.playerZoneCounters[userId] or 0) + 1
	local zoneId = "MetroTunnelZone_" .. userId .. "_" .. ZoneManager.playerZoneCounters[userId]

	-- 6) Spawn (server-side generator can listen to ZoneCreated like your pipe gen)
	if zoneCreatedEvent then
		zoneCreatedEvent:Fire(player, zoneId, mode, pathCoords)
		debugPrint("'ZoneCreated' BindableEvent fired for metro tunnel:", zoneId)
	else
		warn("ZoneCreated BindableEvent not found")
		return false, "Internal error: ZoneCreated event not found."
	end

	-- 7) Client notify
	if notifyZoneCreatedEvent then
		notifyZoneCreatedEvent:FireClient(player, "ZoneCreated", {
			zoneId = zoneId,
			mode   = mode,
			gridList = pathCoords
		})
		debugPrint("'NotifyZoneCreated' fired to player:", player.Name, "ZoneId:", zoneId)
	end

	return true, zoneId
end



-- Function to handle placing Water Towers
function ZoneManager.onPlaceWaterTower(player, gridPosition)
	debugPrint("Player", player.Name, "attempting to place Water Tower at:", gridPosition)

	-- Validate the grid position
	if type(gridPosition) ~= "table" or type(gridPosition.x) ~= "number" or type(gridPosition.z) ~= "number" then
		warn("Invalid grid position provided by player:", player.Name)
		if notifyZoneCreatedEvent then
			notifyZoneCreatedEvent:FireClient(player, "ValidationFailed", "Invalid grid position.")
		end
		return false, "Invalid grid position"
	end

	local isValid, message = ZoneValidationModule.validateSingleGrid(player, "WaterTower", gridPosition)
	if not isValid then
		if notifyZoneCreatedEvent then
			notifyZoneCreatedEvent:FireClient(player, "ValidationFailed", message)
			debugPrint("Validation failed for player:", player.Name, "Reason:", message)
		else
			warn("NotifyZoneCreated RemoteEvent not found")
		end
		return false, message
	end

	local userId = player.UserId
	ZoneManager.playerZoneCounters[userId] = (ZoneManager.playerZoneCounters[userId] or 0) + 1
	local zoneId = "WaterTowerZone_" .. userId .. "_" .. ZoneManager.playerZoneCounters[userId]

	if zoneCreatedEvent then
		local gridList = { gridPosition }
		zoneCreatedEvent:Fire(player, zoneId, "WaterTower", gridList)
		debugPrint("'ZoneCreated' BindableEvent fired for player:", player.Name, "Mode:", "WaterTower", "ZoneId:", zoneId)
	else
		warn("ZoneCreated BindableEvent not found")
	end

	if notifyZoneCreatedEvent then
		notifyZoneCreatedEvent:FireClient(player, "ZoneCreated", {
			zoneId = zoneId,
			mode = "WaterTower",
			gridList = { gridPosition }
		})
		debugPrint("'NotifyZoneCreated' RemoteEvent fired to player:", player.Name, "ZoneId:", zoneId)
	else
		warn("NotifyZoneCreated RemoteEvent not found")
	end

	return true, { zoneId = zoneId }
end

function ZoneManager.removeWaterTower(player, zoneId)
	local zoneData = ZoneTrackerModule.getZoneById(player, zoneId)
	if not zoneData then
		warn("ZoneManager: Failed to find zone data for zoneId:", zoneId)
		return false
	end

	local success = ZoneTrackerModule.removeZone(player, zoneId, "WaterTower", zoneData.gridList)
	if not success then
		warn("ZoneManager: Failed to remove water tower:", zoneId)
		return false
	end

	return true
end



function ZoneManager.onAddZone(player, zoneId, mode, gridList)
	local success = ZoneTrackerModule.addZone(player, zoneId, mode, gridList)
	if success then
		-- Notify client to display the zone
		notifyZoneCreatedEvent:FireClient(player, "ZoneCreated", {
			zoneId = zoneId,
			mode = mode,
			gridList = gridList
		})
		return true
	else
		warn("ZoneManager: Failed to add zone:", zoneId)
		return false
	end
end

function ZoneManager.onRemoveZone(player, zoneId)
	local z = ZoneTrackerModule.getZoneById(player, zoneId)
	if not z then
		warn("ZoneManager.onRemoveZone: zone not found:", zoneId)
		return false
	end

	local mode = z.mode

	-- Route to specialized removers first (they know how to clean up systems)
	if mode == "DirtRoad" or mode == "Pavement" or mode == "Highway" then
		return ZoneManager.removeRoad(player, zoneId)

	elseif mode == "WaterPipe" then
		return ZoneManager.removePipe(player, zoneId)

	elseif mode == "PowerLines" then
		return ZoneManager.removePowerLine(player, zoneId)

	else
		-- Generic zones fall back to ID-only removal
		local ok = ZoneTrackerModule.removeZoneById(player, zoneId)
		if ok then
			-- Optional: client visual teardown
			local notifyEvt = RemoteEvents:FindFirstChild("NotifyZoneCreated")
			if notifyEvt then notifyEvt:FireClient(player, "ZoneRemoved", zoneId) end
			print("ZoneManager: Zone removed:", zoneId)
			return true
		end
		warn("ZoneManager: Failed to remove zone:", zoneId)
		return false
	end
end

-- Handle player disconnects
game.Players.PlayerRemoving:Connect(function(player)
	debugPrint("Player removing:", player.Name)
	playerModes[player.UserId] = nil
	ZoneManager.playerZoneCounters[player.UserId] = nil
end)

return ZoneManager
