	-- BuildingGhostManager.lua
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Workspace = game:GetService("Workspace")


	-- Cached RangeVisual template for ghost effects
	local FuncTestRS = ReplicatedStorage:WaitForChild("FuncTestGroundRS")
	local AlarmsFolder = FuncTestRS:WaitForChild("Alarms")
	local RangeVisualTemplate = AlarmsFolder:WaitForChild("RangeVisual")
	local Balancing = ReplicatedStorage:WaitForChild("Balancing")
	local Balance = require(Balancing:WaitForChild("BalanceEconomy"))

	local GridConfig = require(ReplicatedStorage.Scripts.Grid.GridConfig)
	local BuildingMasterList = require(script.Parent:WaitForChild("BuildingMasterList"))

	local IGNORED_MODES = {
		["PowerLines"] = true,
		["Residential"] = true,
		["Commercial"] = true,
		["Industrial"] = true,
		["ResDense"] = true,
		["CommDense"] = true,
		["IndusDense"] = true,
		["WaterPipe"] = true,
		["DirtRoad"] = true,
	}

	local BuildingGhostManager = {}

	-- Metadata configuration
	local buildingConfigs = {
		WaterTower = {
			type = "utility",
			zone = "Water",
			style = "Default",
			name = "WaterTower",
		},
		
		WaterPlant = {
			type = "named",
			zone = "Water",
			style = "Default",
			name = "Water Plant"
		},
		PurificationWaterPlant = {
			type = "named",
			zone = "Water",
			style = "Default",
			name = "Purification Water Plant"
		},
		MolecularWaterPlant = {
			type = "named",
			zone = "Water",
			style = "Default",
			name = "Molecular Water Plant"
		},
	--Fire
		FireDept = {
			type = "individual",
			zone = "Fire",
			style = "Default",
			name = "FireDept"
		},
		FirePrecinct = {
			type = "named",
			zone = "Fire",
			style = "Default",
			name = "FirePrecinct"
		},
		FireStation = {
			type = "named",
			zone = "Fire",
			style = "Default",
			name = "FireStation"
		},
	--Education
		MiddleSchool = {
			type = "named",
			zone = "Education",
			style = "Default",
			name = "Middle School"
		},
		Museum = {
			type = "named",
			zone = "Education",
			style = "Default",
			name = "Museum"
		},
		NewsStation = {
			type = "named",
			zone = "Education",
			style = "Default",
			name = "News Station"
		},
		PrivateSchool = {
			type = "named",
			zone = "Education",
			style = "Default",
			name = "Private School"
		},
	--Health
		CityHospital = {
			type = "named",
			zone = "Health",
			style = "Default",
			name = "City Hospital"
		},
		LocalHospital = {
			type = "named",
			zone = "Health",
			style = "Default",
			name = "Local Hospital"
		},
		MajorHospital = {
			type = "named",
			zone = "Health",
			style = "Default",
			name = "Major Hospital"
		},
		SmallClinic = {
			type = "named",
			zone = "Health",
			style = "Default",
			name = "Small Clinic"
		},
	--Landmark
		Bank = {
			type = "named",
			zone = "Landmark",
			style = "Default",
			name = "Bank"
		},
		CNTower = {
			type = "named",
			zone = "Landmark",
			style = "Default",
			name = "CN Tower"
		},
		EiffelTower = {
			type = "named",
			zone = "Landmark",
			style = "Default",
			name = "Eiffel Tower"
		},
		EmpireStateBuilding = {
			type = "named",
			zone = "Landmark",
			style = "Default",
			name = "Empire State Building"
		},
		FerrisWheel = {
			type = "named",
			zone = "Landmark",
			style = "Default",
			name = "Ferris Wheel"
		},
		GasStation = {
			type = "named",
			zone = "Landmark",
			style = "Default",
			name = "Gas Station"
		},
		ModernSkyscraper = {
			type = "named",
			zone = "Landmark",
			style = "Default",
			name = "Modern Skyscraper"
		},
		NationalCapital = {
			type = "named",
			zone = "Landmark",
			style = "Default",
			name = "National Capital"
		},
		Obelisk = {
			type = "named",
			zone = "Landmark",
			style = "Default",
			name = "Obelisk"
		},
		SpaceNeedle = {
			type = "named",
			zone = "Landmark",
			style = "Default",
			name = "Space Needle"
		},
		StatueOfLiberty = {
			type = "named",
			zone = "Landmark",
			style = "Default",
			name = "Statue Of Liberty"
		},
		TechOffice = {
			type = "named",
			zone = "Landmark",
			style = "Default",
			name = "Tech Office"
		},
		WorldTradeCenter = {
			type = "named",
			zone = "Landmark",
			style = "Default",
			name = "World Trade Center"
		},
	--Leisure
		Church = {
			type = "named",
			zone = "Leisure",
			style = "Default",
			name = "Church"
		},
		Hotel = {
			type = "named",
			zone = "Leisure",
			style = "Default",
			name = "Hotel"
		},
		Mosque = {
			type = "named",
			zone = "Leisure",
			style = "Default",
			name = "Mosque"
		},
		MovieTheater = {
			type = "named",
			zone = "Leisure",
			style = "Default",
			name = "Movie Theater"
		},
		ShintoTemple = {
			type = "named",
			zone = "Leisure",
			style = "Default",
			name = "Shinto Temple"
		},
		BuddhaStatue = {
			type = "named",
			zone = "Leisure",
			style = "Default",
			name = "Buddha Statue"
		},
		HinduTemple = {
			type = "named",
			zone = "Leisure",
			style = "Default",
			name = "Hindu Temple"
		},
	--Police
		Courthouse = {
			type = "named",
			zone = "Police",
			style = "Default",
			name = "Courthouse"
		},
		PoliceDept = {
			type = "named",
			zone = "Police",
			style = "Default",
			name = "Police Dept"
		},
		PolicePrecinct = {
			type = "named",
			zone = "Police",
			style = "Default",
			name = "Police Precinct"
		},
		PoliceStation = {
			type = "named",
			zone = "Police",
			style = "Default",
			name = "Police Station"
		},
	--Sports
		ArcheryRange = {
			type = "named",
			zone = "Sports",
			style = "Default",
			name = "Archery Range"
		},
		BasketballCourt = {
			type = "named",
			zone = "Sports",
			style = "Default",
			name = "Basketball Court"
		},
		BasketballStadium = {
			type = "named",
			zone = "Sports",
			style = "Default",
			name = "Basketball Stadium"
		},
		FootballStadium = {
			type = "named",
			zone = "Sports",
			style = "Default",
			name = "Football Stadium"
		},
		GolfCourse = {
			type = "named",
			zone = "Sports",
			style = "Default",
			name = "Golf Course"
		},
		PublicPool = {
			type = "named",
			zone = "Sports",
			style = "Default",
			name = "Public Pool"
		},
		SkatePark = {
			type = "named",
			zone = "Sports",
			style = "Default",
			name = "Skate Park"
		},
		SoccerStadium = {
			type = "named",
			zone = "Sports",
			style = "Default",
			name = "Soccer Stadium"
		},
		TennisCourt = {
			type = "named",
			zone = "Sports",
			style = "Default",
			name = "Tennis Court"
		},
		Airport = {
			type = "named",
			zone = "Airport",
			style = "Default",
			name = "Airport"
		},
		BusDepot = {
			type = "named",
			zone = "Bus",
			style = "Default",
			name = "Bus Depot"
		},
		MetroEntrance = {
			type = "named",
			zone = "Metro",
			style = "Default",
			name = "Metro Entrance"
		},
		CoalPowerPlant = {
			type = "named",
			zone = "Power",
			style = "Default",
			name = "Coal Power Plant"
		},
		GasPowerPlant = {
			type = "named",
			zone = "Power",
			style = "Default",
			name = "Gas Power Plant"
		},
		GeothermalPowerPlant = {
			type = "named",
			zone = "Power",
			style = "Default",
			name = "Geothermal Power Plant"
		},
		NuclearPowerPlant = {
			type = "named",
			zone = "Power",
			style = "Default",
			name = "Nuclear Power Plant"
		},
		SolarPanels = {
			type = "named",
			zone = "Power",
			style = "Default",
			name = "Solar Panels"
		},
		WindTurbine = {
			type = "named",
			zone = "Power",
			style = "Default",
			name = "Wind Turbine"
		},
	}

	-- Returns the ghost model (unparented)
	function BuildingGhostManager.getGhostModel(mode)
		if IGNORED_MODES[mode] then
			return nil
		end
		local config = buildingConfigs[mode]
		if not config then
			warn("[GhostManager] No config found for mode:", mode)
			return nil
		end

		local buildingData
		if config.type == "utility" then
			buildingData = BuildingMasterList.getUtilityBuilding(config.zone, config.style, config.name)[1]
		elseif config.type == "individual" then
			buildingData = BuildingMasterList.getIndividualBuildingsByType(config.zone, config.style)[1]
		elseif config.type == "named" then
			buildingData = BuildingMasterList.getIndividualBuildingByName(config.zone, config.style, config.name)[1]
		end

		if not (buildingData and buildingData.stages and buildingData.stages.Stage3) then
			warn("[GhostManager] Missing Stage3 for mode:", mode)
			return nil
		end
	
		local ghost = buildingData.stages.Stage3:Clone()
		ghost.Name = mode .. "Ghost"

		-- Ensure PrimaryPart
		if not ghost.PrimaryPart then
			local root = ghost:FindFirstChildWhichIsA("BasePart")
			ghost.PrimaryPart = root
		end

		-- Make ghost transparent and uncollidable
		for _, part in ipairs(ghost:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Transparency = 0.5
				part.CanCollide = false
				part.CanQuery = false
			end
		end
		
		local radius = Balance.UxpConfig and Balance.UxpConfig.Radius[mode]
		if radius then
			config.range = Vector3.new((radius*GridConfig.GRID_SIZE), 1, (radius*GridConfig.GRID_SIZE))
		end

		-- Spawn RangeVisual
		if config.range and ghost.PrimaryPart then
			local rv = RangeVisualTemplate:Clone()
			rv.Name        = mode .. "RangeVisual"
			rv.Size        = config.range
			rv.CFrame      = ghost.PrimaryPart.CFrame
			rv.Anchored    = true
			rv.CanCollide  = false
			rv.CanQuery    = false
			rv.Transparency = 1
			rv.Parent      = ghost
		end

		return ghost
	end

	-- Returns the footprint of a model in grid tiles, accounting for rotation
	function BuildingGhostManager.getFootprint(model, rotationDegrees)
		local GRID_SIZE = GridConfig.GRID_SIZE
		if not (model and model.PrimaryPart) then
			return 1, 1
		end
		rotationDegrees = rotationDegrees or 0
		local sizeX = model.PrimaryPart.Size.X
		local sizeZ = model.PrimaryPart.Size.Z
		local modRot = rotationDegrees % 180
		if modRot == 90 then
			return math.ceil(sizeZ / GRID_SIZE), math.ceil(sizeX / GRID_SIZE)
		else
			return math.ceil(sizeX / GRID_SIZE), math.ceil(sizeZ / GRID_SIZE)
		end
	end

	-- Returns true if the mode is supported by BuildingGhostManager
	function BuildingGhostManager.isGhostable(mode)
		return buildingConfigs[mode] ~= nil
	end

	return BuildingGhostManager