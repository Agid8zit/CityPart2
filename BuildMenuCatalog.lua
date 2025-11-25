-- Helper module that centralizes BuildMenu data/tables to keep BuildMenuGUI lean.
local Catalog = {}

Catalog.UnlockState = {
	requirement = {}, -- [BuildingID] = min level
	order       = {}, -- [BuildingID] = global sort index
	types       = {}, -- unlocked flags
	prev        = {}, -- previous unlock snapshot
}

local function getCatalog()
	-- Services
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	-- World assets
	local RS  = ReplicatedStorage
	local FT  = RS:WaitForChild("FuncTestGroundRS")
	local BLD = FT:WaitForChild("Buildings")
	local IND = BLD:WaitForChild("Individual"):WaitForChild("Default")

	-- Category folders
	local EDUC = IND:WaitForChild("Education")
	local FIRE = IND:WaitForChild("Fire")
	local POLI = IND:WaitForChild("Police")
	local HLTH = IND:WaitForChild("Health")
	local LAND = IND:WaitForChild("Landmark")
	local LEIS = IND:WaitForChild("Leisure")
	local SPRT = IND:WaitForChild("Sports")
	local POWR = IND:WaitForChild("Power")
	local WATR = IND:WaitForChild("Water")
	local TRAN = IND:FindFirstChild("Transport") -- optional
	local FLAGS = IND:WaitForChild("Flags")

	-- Model map used by unlock previews
	local FeatureModels = {
		-- Education
		PrivateSchool = EDUC["Private School"],
		MiddleSchool  = EDUC["Middle School"],
		NewsStation   = EDUC["News Station"],
		Museum        = EDUC.Museum,

		-- Fire
		FireDept      = FIRE["FireDept"],
		FireStation   = FIRE["FireStation"],
		FirePrecinct  = FIRE["FirePrecinct"],

		-- Leisure
		Church        = LEIS["Church"],
		Mosque        = LEIS["Mosque"],
		ShintoTemple  = LEIS["Shinto Temple"],
		HinduTemple   = LEIS["Hindu Temple"],
		BuddhaStatue  = LEIS["Buddha Statue"],
		Hotel         = LEIS["Hotel"],
		MovieTheater  = LEIS["Movie Theater"],

		-- Police
		PoliceDept     = POLI["Police Dept"],
		PoliceStation  = POLI["Police Station"],
		PolicePrecinct = POLI["Police Precinct"],
		Courthouse     = POLI["Courthouse"],

		-- Health
		SmallClinic   = HLTH["Small Clinic"],
		LocalHospital = HLTH["Local Hospital"],
		CityHospital  = HLTH["City Hospital"],
		MajorHospital = HLTH["Major Hospital"],

		-- Sports
		SkatePark         = SPRT["Skate Park"],
		TennisCourt       = SPRT["Tennis Court"],
		PublicPool        = SPRT["Public Pool"],
		ArcheryRange      = SPRT["Archery Range"],
		GolfCourse        = SPRT["Golf Course"],
		BasketballCourt   = SPRT["Basketball Court"],
		SoccerStadium     = SPRT["Soccer Stadium"],
		FootballStadium   = SPRT["Football Stadium"],
		BasketballStadium = SPRT["Basketball Stadium"],

		-- Landmarks
		FerrisWheel          = LAND["Ferris Wheel"],
		GasStation           = LAND["Gas Station"],
		Bank                 = LAND["Bank"],
		TechOffice           = LAND["Tech Office"],
		NationalCapital      = LAND["National Capital"],
		Obelisk              = LAND["Obelisk"],
		ModernSkyscraper     = LAND["Modern Skyscraper"],
		EmpireStateBuilding  = LAND["Empire State Building"],
		SpaceNeedle          = LAND["Space Needle"],
		WorldTradeCenter     = LAND["World Trade Center"],
		CNTower              = LAND["CN Tower"],
		StatueOfLiberty      = LAND["Statue Of Liberty"],
		EiffelTower          = LAND["Eiffel Tower"],

		-- Supply: Power
		WindTurbine          = POWR["Wind Turbine"],
		SolarPanels          = POWR["Solar Panels"],
		CoalPowerPlant       = POWR["Coal Power Plant"],
		GasPowerPlant        = POWR["Gas Power Plant"],
		GeothermalPowerPlant = POWR["Geothermal Power Plant"],
		NuclearPowerPlant    = POWR["Nuclear Power Plant"],

		-- Supply: Water
		WaterTower             = WATR["Water Tower"] or WATR:FindFirstChild("Water Tower"),
		WaterPlant             = WATR["Water Plant"],
		PurificationWaterPlant = WATR["Purification Water Plant"],
		MolecularWaterPlant    = WATR["Molecular Water Plant"],

		-- Transport (optional)
		Airport       = TRAN and TRAN:FindFirstChild("Airport") or nil,
		BusDepot      = TRAN and TRAN:FindFirstChild("Bus Depot") or nil,
		MetroEntrance = TRAN and TRAN:FindFirstChild("Metro Entrance") or nil,
	}

	-- Range visual template (shared by BuildMenu + ZoneDisplay)
	local alarmsFolder = FT:WaitForChild("Alarms")
	local RangeVisualTemplate = alarmsFolder:WaitForChild("RangeVisual")

	-- optional name normalization for hub buttons whose label != section name
	local ITEMNAME_TO_SECTION = {
		["Fire Dept"] = "Fire",
		["Police"]    = "Police",
		["Health"]    = "Health",
		["Education"] = "Education",
		["Leisure"]   = "Leisure",
		["Sports"]    = "Sports",
		["Landmarks"] = "Landmarks",
		["Power"]     = "Power",
		["Water"]     = "Water",
		["Flags"]     = "Flags",
	}

	return FeatureModels, RangeVisualTemplate, FLAGS, ITEMNAME_TO_SECTION
end

function Catalog.getCatalog()
	return getCatalog()
end

return Catalog
