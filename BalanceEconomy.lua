local Balance = {}

Balance.StatConfig = {
	Residential = {
		["nil"]   = {population = 0,   income = 0,   water = 0,  power = 0,  exp = 0}, -- Wrong ####### its now your xp per zone per wealthstate now
		Poor      = {population = 40,   income = 2,  water = 10,  power = 2,  exp = 0},
		Medium    = {population = 80,   income = 3,  water = 15,  power = 3,  exp = 0},
		Wealthy   = {population = 120,  income = 4,  water = 20,  power = 4,  exp = 0},
	},
	Commercial = {
		["nil"]   = {population = 0,   income = 0,   water = 0,  power = 0,  exp = 0},
		Poor      = {population = 4,   income = 2,  water = 10,  power = 2,  exp = 0},
		Medium    = {population = 8,   income = 3, water = 15,  power = 3,  exp = 0},
		Wealthy   = {population = 12,   income = 4, water = 20,  power = 4,  exp = 0},
	},
	Industrial = {
		["nil"]   = {population = 0,   income = 0,   water = 0,  power = 0,  exp = 0},
		Poor      = {population = 4,   income = 2,  water = 10,  power = 3,  exp = 0},
		Medium    = {population = 8,   income = 3, water = 15,  power = 5,  exp = 0},
		Wealthy   = {population = 12,   income = 4, water = 20,  power = 6, exp = 0},
	},
	ResDense = {
		["nil"]   = {population = 0,   income = 0,   water = 0,  power = 0,  exp = 0},
		Poor      = {population = 120,   income = 4,  water = 20,  power = 4,  exp = 0},
		Medium    = {population = 240,   income = 6,  water = 30,  power = 6,  exp = 0},
		Wealthy   = {population = 360,  income = 8,  water = 40,  power = 8,  exp = 0},
	},
	CommDense = {
		["nil"]   = {population = 0,   income = 0,   water = 0,  power = 0,  exp = 0},
		Poor      = {population = 12,   income = 4,  water = 20,  power = 4,  exp = 0},
		Medium    = {population = 24,   income = 6, water = 30,  power = 6,  exp = 0},
		Wealthy   = {population = 36,   income = 8, water = 40,  power = 8,  exp = 0},
	},
	IndusDense = {
		["nil"]   = {population = 0,   income = 0,   water = 0,  power = 0,  exp = 0},
		Poor      = {population = 12,   income = 4,  water = 20,  power = 6,  exp = 0},
		Medium    = {population = 24,   income = 6, water = 30,  power = 10,  exp = 0},
		Wealthy   = {population = 36,   income = 8, water = 40,  power = 12, exp = 0},
	}
}

-- Utility building production values ----------------------------------------------------
Balance.ProductionConfig = {
	WaterTower = {
		type = "water",
		amount = 2000
	},
	WaterPlant = {
		type = "water",
		amount = 12000
	},
	PurificationWaterPlant = {
		type = "water",
		amount = 30000
	},
	MolecularWaterPlant = {
		type = "water",
		amount = 1000000
	},


	WindTurbine = {
		type = "power",
		amount = 100
	},
	SolarPanels = {
		type = "power",
		amount = 200
	},
	CoalPowerPlant = {
		type = "power",
		amount = 1500
	},
	GasPowerPlant = {
		type = "power",
		amount = 10000
	},
	GeothermalPowerPlant = {
		type = "power",
		amount = 100000
	},
	NuclearPowerPlant = {
		type = "power",
		amount = 1000000
	},
}

Balance.costPerGrid = {
	-- Base Zones
	Residential = 100,
	Commercial = 100,
	Industrial = 100,
	ResDense = 400,
	CommDense = 400,
	IndusDense = 400,

	-- Roads & Utilities
	DirtRoad = 20,
	Pavement = 20,
	Highway = 20,

	WaterPipe = 50,
	WaterTower = 1500,
	WaterPlant = 10000,
	PurificationWaterPlant = 2000000,
	MolecularWaterPlant = "ROBUX",

	PowerLines = 50,
	WindTurbine = 1500,
	SolarPanels = 3200,
	CoalPowerPlant = 20000,
	GasPowerPlant = 70000,
	GeothermalPowerPlant = 3000000,
	NuclearPowerPlant = "ROBUX",
	
	Flags = 1000,
	
	-- Individual Buildings
	FireDept = 2000,
	FireStation = 22000,
	FirePrecinct = "ROBUX",

	PoliceDept = 2600,
	PoliceStation = 36000,
	PolicePrecinct = "ROBUX",
	Courthouse = 80000,

	SmallClinic = 5200,
	LocalHospital = 45000,
	CityHospital = 1500000,
	MajorHospital = "ROBUX",

	PrivateSchool = 8000,
	MiddleSchool = 50000,
	NewsStation = 300000,
	Museum = "ROBUX",

	FerrisWheel = 6000,
	GasStation = 12000,
	Bank = 40000,
	TechOffice = 75000,
	NationalCapital = 250000,
	Obelisk = 2000000,
	ModernSkyscraper = 3000000,
	EmpireStateBuilding = 4000000,
	SpaceNeedle = 5000000,
	WorldTradeCenter = 7500000,
	CNTower = 10000000,
	StatueOfLiberty = "ROBUX",
	EiffelTower = "ROBUX",

	Church = 1500,
	Mosque = 1500,
	ShintoTemple = 1500,
	BuddhaStatue = 1500,
	HinduTemple = 1500,
	Hotel = 30000,
	MovieTheater = 2000000,

	-- Sports & Recreation
	SkatePark = 500,
	TennisCourt = 4000,
	PublicPool = 14000,
	ArcheryRange = 18000,
	BasketballCourt = 30000,
	GolfCourse = 50000,
	SoccerStadium = 500000,
	BasketballStadium = 1300000,
	FootballStadium = "ROBUX",

	-- Transport
	Airport = 1000000,
	BusDepot = 16000,
	Metro = 1000000,
}


-- NOT USED FOR ZONES, THIS IS FOR CITY LEVEL, NAME IS OLD ----------------------------------------------------
Balance.ZoneXP = {
	-- Base Zones
	Residential = 7,
	Commercial = 7,
	Industrial = 7,
	ResDense = 20,
	CommDense = 20,
	IndusDense = 20,

	-- Roads & Utilities
	DirtRoad = 2,
	WaterPipe = 2,
	PowerLines = 2,

	-- Fire
	FireDept = 20,
	FirePrecinct = 500,
	FireStation = 800,
	
	-- Education
	MiddleSchool = 20,
	Museum = 500,
	NewsStation = 500,
	PrivateSchool = 40,
	
	--Health
	CityHospital = 800,
	LocalHospital = 80,
	MajorHospital = 500,
	SmallClinic = 40,
	
	--Landmark
	Bank = 800,
	CNTower = 1000,
	EiffelTower = 1000,
	EmpireStateBuilding = 1000,
	FerrisWheel = 30,
	GasStation = 40,
	ModernSkyscraper = 1000,
	NationalCapital = 1000,
	Obelisk = 800,
	SpaceNeedle = 1000,
	StatueOfLiberty = 1000,
	TechOffice = 800,
	WorldTradeCenter = 1000,
	
	--Leisure
	Church = 50,
	Hotel = 50,
	Mosque = 50,
	MovieTheater = 800,
	ShintoTemple = 50,
	
	--Police
	Courthouse = 1200,
	PoliceDept = 40,
	PolicePrecinct = 500,
	PoliceStation = 800,

	-- Sports & Recreation
	ArcheryRange = 40,
	BasketballCourt = 100,
	BasketballStadium = 800,
	FootballStadium = 500,
	GolfCourse = 100,
	PublicPool = 40,
	SkatePark = 40,
	SoccerStadium = 500,
	TennisCourt = 40,

	-- Transport
	Airport = 5000,
	BusDepot = 300,
	Metro = 10,

	-- Power Plants
	CoalPowerPlant = 100,
	GasPowerPlant = 500,
	GeothermalPowerPlant = 800,
	NuclearPowerPlant = 500,
	SolarPanels = 50,
	WindTurbine = 50,
	
	-- Water
	WaterTower = 50,
	WaterPlant = 400,
	PurificationWaterPlant = 800,
	MolecularWaterPlant = 500,
}

-- THIS SETS THE UPGRADE XP FOR BUILDINGS
Balance.UxpConfig = {
	Radius = {
		FireDept               = 20,
		FireStation            = 40,
		FirePrecinct           = 80,

		Courthouse             = 50,
		PoliceDept             = 20,
		PolicePrecinct         = 80,
		PoliceStation          = 40,

		MiddleSchool           = 40,
		Museum                 = 80,
		NewsStation            = 60,
		PrivateSchool          = 20,

		CityHospital           = 60,
		LocalHospital          = 40,
		MajorHospital          = 80,
		SmallClinic            = 20,

		Bank                   = 20,
		CNTower                = 11,
		EiffelTower            = 100,
		EmpireStateBuilding    = 50,
		FerrisWheel            = 10,
		GasStation             = 16,
		ModernSkyscraper       = 10,
		NationalCapital        = 32,
		Obelisk                = 40,
		SpaceNeedle            = 60,
		StatueOfLiberty        = 100,
		TechOffice             = 26,
		WorldTradeCenter       = 10,

		Church                 = 20,
		Hotel                  = 40,
		Mosque                 = 20,
		HinduTemple            = 20,
		BuddhaStatue           = 20,
		MovieTheater           = 60,
		ShintoTemple           = 20,

		ArcheryRange           = 26,
		BasketballCourt        = 32,
		BasketballStadium      = 80,
		FootballStadium        = 100,
		GolfCourse             = 40,
		PublicPool             = 20,
		SkatePark              = 10,
		SoccerStadium          = 60,
		TennisCourt            = 16,

		Airport                = 60,
		BusDepot               = 40,
		Metro                  = 10,

		WaterTower             = 0,
		WaterPlant             = 0,
		CoalPowerPlant         = 0,
		GasPowerPlant          = 0,
		GeothermalPowerPlant   = 0,
		NuclearPowerPlant      = 0,
		SolarPanels            = 0,
		WindTurbine            = 0,
		PurificationWaterPlant = 0,
		MolecularWaterPlant    = 0,
		Flags				   = 10,
	},
	Value = {
		FireDept               = 10,
		FireStation            = 20,
		FirePrecinct           = 20,

		Courthouse             = 30,
		PoliceDept             = 10,
		PolicePrecinct         = 30,
		PoliceStation          = 20,

		MiddleSchool           = 20,
		Museum                 = 30,
		NewsStation            = 30,
		PrivateSchool          = 10,

		CityHospital           = 30,
		LocalHospital          = 20,
		MajorHospital          = 30,
		SmallClinic            = 10,

		Bank                   = 10,
		CNTower                = 30,
		EiffelTower            = 30,
		EmpireStateBuilding    = 30,
		FerrisWheel            = 10,
		GasStation             = 10,
		ModernSkyscraper       = 20,
		NationalCapital        = 20,
		Obelisk                = 20,
		SpaceNeedle            = 30,
		StatueOfLiberty        = 30,
		TechOffice             = 10,
		WorldTradeCenter       = 30,

		Church                 = 10,
		Hotel                  = 20,
		Mosque                 = 10,
		HinduTemple            = 10,
		BuddhaStatue           = 10,
		MovieTheater           = 30,
		ShintoTemple           = 10,

		ArcheryRange           = 10,
		BasketballCourt        = 20,
		BasketballStadium      = 30,
		FootballStadium        = 30,
		GolfCourse             = 20,
		PublicPool             = 10,
		SkatePark              = 10,
		SoccerStadium          = 30,
		TennisCourt            = 10,

		Airport                = 20,
		BusDepot               = 20,
		Metro                  = 10,

		WaterTower             = 0,
		WaterPlant             = 0,
		CoalPowerPlant         = 0,
		GasPowerPlant          = 0,
		GeothermalPowerPlant   = 0,
		NuclearPowerPlant      = 0,
		SolarPanels            = 0,
		WindTurbine            = 0,
		PurificationWaterPlant = 0,
		MolecularWaterPlant    = 0,
	},
	Tier = {
		FireDept               = 1,
		FireStation            = 2,
		FirePrecinct           = 3,

		Courthouse             = 4,
		PoliceDept             = 1,
		PolicePrecinct         = 3,
		PoliceStation          = 2,

		MiddleSchool           = 2,
		Museum                 = 4,
		NewsStation            = 3,
		PrivateSchool          = 1,

		CityHospital           = 3,
		LocalHospital          = 2,
		MajorHospital          = 4,
		SmallClinic            = 1,

		Bank                   = 3,
		CNTower                = 11,
		EiffelTower            = 16,
		EmpireStateBuilding    = 8,
		FerrisWheel            = 1,
		GasStation             = 2,
		ModernSkyscraper       = 7,
		NationalCapital        = 5,
		Obelisk                = 6,
		SpaceNeedle            = 9,
		StatueOfLiberty        = 15,
		TechOffice             = 4,
		WorldTradeCenter       = 10,

		Church                 = 1,
		Hotel                  = 2,
		Mosque                 = 1,
		HinduTemple            = 1,
		BuddhaStatue           = 1,
		MovieTheater           = 3,
		ShintoTemple           = 1,

		ArcheryRange           = 4,
		BasketballCourt        = 5,
		BasketballStadium      = 8,
		FootballStadium        = 9,
		GolfCourse             = 6,
		PublicPool             = 3,
		SkatePark              = 1,
		SoccerStadium          = 7,
		TennisCourt            = 2,

		Airport                = 0,
		BusDepot               = 0,
		Metro                  = 0,

		WaterTower             = 0,
		WaterPlant             = 0,
		CoalPowerPlant         = 0,
		GasPowerPlant          = 0,
		GeothermalPowerPlant   = 0,
		NuclearPowerPlant      = 0,
		SolarPanels            = 0,
		WindTurbine            = 0,
		PurificationWaterPlant = 0,
		MolecularWaterPlant          = 0,

	},
	Category = {
		Fire                   = { 	FireDept=true, FirePrecinct=true, FireStation=true },
		Education              = { 	MiddleSchool=true, Museum=true, NewsStation=true, PrivateSchool=true },
		Health                 = { 	CityHospital=true, LocalHospital=true, MajorHospital=true, SmallClinic=true },
		Landmark               = {	Bank=true, CNTower=true, EiffelTower=true, EmpireStateBuilding=true,
									FerrisWheel=true, GasStation=true, ModernSkyscraper=true, NationalCapital=true,
									Obelisk=true, SpaceNeedle=true, StatueOfLiberty=true, TechOffice=true, WorldTradeCenter=true
								},
		Leisure                = { 	Church=true, Hotel=true, Mosque=true, MovieTheater=true, ShintoTemple=true, HinduTemple = true, BuddhaStatue = true, },
		Police                 = { 	Courthouse=true, PoliceDept=true, PolicePrecinct=true, PoliceStation=true },
		SportsAndRecreation    = {	ArcheryRange=true, BasketballCourt=true, BasketballStadium=true, FootballStadium=true,
									GolfCourse=true, PublicPool=true, SkatePark=true, SoccerStadium=true, TennisCourt=true
								},
		Transport              = { 	Airport=true, BusDepot=true, Metro=true },
		PowerPlants            = {	CoalPowerPlant=true, GasPowerPlant=true, GeothermalPowerPlant=true,
									NuclearPowerPlant=true, SolarPanels=true, WindTurbine=true
								},
		Water                  = { WaterTower=true, WaterPlant=true, PurificationWaterPlant=true, MolecularWaterPlant=true },
	},
	
	WealthThresholds = {
		Default     = { Medium = 40, Wealthy = 80 },

		Residential = { Medium = 40, Wealthy = 80 },
		Commercial  = { Medium = 40, Wealthy = 80 },
		Industrial  = { Medium = 40, Wealthy = 80 },
		ResDense    = { Medium = 80, Wealthy = 140 },
		CommDense   = { Medium = 80, Wealthy = 140 },
		IndusDense  = { Medium = 80, Wealthy = 140 },
	}
}

Balance.ProgressionConfig = {
	
	-- first level to switch from hard‑coded thresholds to exponential growth
	dynamicStartLevel = 30,
	-- per‑level multiplier beyond dynamicStartLevel
	growthFactor      = 1.1,


	-- XP required *within* each level.  With level‑0 start, the first
	-- threshold (16) means you must earn 16 XP to reach level 1.
	xpThresholds = {
		500,    -- Level 1
		800,    -- Level 2
		1200,    -- Level 3
		1700,    -- Level 4
		2500,    -- Level 5
		3500,   -- Level 6
		4500,   -- Level 7
		5500,   -- Level 8
		7500,   -- Level 9
		8500,   -- Level 10
		10000,   -- Level 11
		12000,   -- Level 12
		10000,   -- Level 13
		9000,   -- Level 14
		8000,   -- Level 15
		8000,   -- Level 16
		8000,   -- Level 17
		8000,   -- Level 18
		8000,   -- Level 19
		8000,   -- Level 20
		10000,   -- Level 21
		10000,   -- Level 22
		10000,   -- Level 23
		10000,   -- Level 24
		10000,   -- Level 25
		10000,   -- Level 26
		10000,   -- Level 27
		10000,   -- Level 28
		10000,   -- Level 29
		10000,   -- Level 30
	},

	-- Write your unlocks **by level**.  Anything you omit is usable at
	-- level 0.  Add or remove entries here only.
	unlocksByLevel = {
		[0] = {"Residential", "Commercial", "Industrial", "DirtRoad", "WaterTower", "WaterPipe","WindTurbine", "PowerLines", "NuclearPowerPlant", "MolecularWaterPlant", "FirePrecinct", "PolicePrecinct", "MajorHospital", "Museum", "EiffelTower", "StatueOfLiberty", "FootballStadium", "Flags"},
		[1] = {"SolarPanels", "FireDept", "SkatePark", "Church", "Mosque", "ShintoTemple", "HinduTemple", "BuddhaStatue"},
		[2] = {"PoliceDept", "BusDepot", "TennisCourt", "FerrisWheel"},
		[3] = {"PrivateSchool", "PublicPool", "GasStation"},
		[4] = {"CoalPowerPlant","WaterPlant", "ArcheryRange", "SmallClinic"},
		[5] = {"ResDense", "CommDense", "IndusDense", "BasketballCourt"},
		[6] = {"MiddleSchool", "Bank", "GolfCourse", "FireStation",},
		[7] = {"GasPowerPlant", "Hotel", "SoccerStadium", "PoliceStation"},
		[8] = {"TechOffice", "LocalHospital"},
		[9] = {"NewsStation", "BasketballStadium"},
		[10] = {"NationalCapital", "PurificationWaterPlant", "Airport"},
		[11] = {"GeothermalPowerPlant", "FootballStadium"},
		[12] = {"MetroEntrance", "CityHospital"},
		[13] = {"MovieTheater"},
		[14] = {"Courthouse"},
		[15] = {"Obelisk"},
		[16] = {"ModernSkyscraper"},
		[17] = {"EmpireStateBuilding"},
		[18] = {"SpaceNeedle"},
		[19] = {"WorldTradeCenter"},
		[20] = {"CNTower"},
		[21] = {},
		[22] = {},
		[23] = {},
		[24] = {},
		[25] = {},
		[26] = {},
		[27] = {},
		[28] = {},
		[29] = {},
		[30] = {},
		[31] = {},
		[32] = {},
		[33] = {},
		[34] = {},
		[35] = {},
		[36] = {},
		[37] = {},
		[38] = {},
		[39] = {},
		[40] = {},
		[41] = {},
		[42] = {},
		[43] = {},
		[44] = {},
		[45] = {},
		[46] = {},
		[47] = {},
		[48] = {},
		[49] = {},
		[50] = {},
		[51] = {},
		[52] = {},
		[53] = {},
		[54] = {},
		[55] = {},
		[56] = {},
		[57] = {},
		[58] = {},
		[59] = {},
		[60] = {},
		[61] = {},
		[62] = {},
		[63] = {},
		[64] = {},
		[65] = {},
		[66] = {},
		[67] = {},
		[68] = {},
		[69] = {},
		[70] = {},
		[71] = {},
		[72] = {},
		[73] = {},
		[74] = {},
		[75] = {},
		[76] = {},
		[77] = {},
		[78] = {},
		[79] = {},
		[80] = {},
		[81] = {},
		[82] = {},
		[83] = {},
		[84] = {},
		[85] = {},
		[86] = {},
		[87] = {},
		[88] = {},
		[89] = {},
		[90] = {},
		[91] = {},
		[92] = {},
		[93] = {},
		[94] = {},
		[95] = {},
		[96] = {},
		[97] = {},
		[98] = {},
		[99] = {},
		[100] = {},
		[101] = {},
		-- add more as needed
	},
}

--For the unlockable areas
Balance.UnlockCosts = {
	Unlock_1 =  5000,
	Unlock_2 = 10000,
	Unlock_3 = 25000,
	Unlock_4 =  100000,
	Unlock_5 = 250000,
	Unlock_6 = 1000000,
	Unlock_7 = 1000000,
	Unlock_8 = 250000,
}

--Demands
Balance.ZoneShareTargets = {
	Residential = 0.50,   ResDense   = 0.25,   -- 1/2 overall, 2/4 of that dense
	Commercial  = 0.25,   CommDense  = 0.125,  -- 1/4 overall, 2/4 of that dense
	Industrial  = 0.25,   IndusDense = 0.125,
}

Balance.IncomeRate = {
	TICK_INCOME = 1,
}

Balance.TransitCosts = {
	BusDepot = {
		baseCost     = 400,   -- cost for L0->1 in Tier 1
		levelMult    = 1.35,  -- × per level (geometric). Set to 1.0 to disable.
		tierMult     = 1.25,  -- × per tier (Tier2=^1, Tier3=^2, ...)
		fallbackStep = 40,    -- used only if levelStep==0 & quadTerm==0 & levelMult==1
	},

	Airport = {
		baseCost     = 400,
		levelMult    = 1.35, 
		tierMult     = 1.25,
		fallbackStep = 40,
	},
}

Balance.TransitIncome = {
	BusDepot = {
		base       = 10,     -- Tier1, Level0 base tickets/sec
		tierMult   = 1.25,   -- per-tier multiplier (Tier2=+15%, Tier3=+32.25%, ...)
		levelAdd   = 0,   -- +10% per level (linear term). Set to 0 to disable.
		levelMult  = 1.25,   -- x1.00^level (no exponential by default). Set e.g. 1.02 for gentle compounding.
	},

	Airport = {
		base       = 10,    
		tierMult   = 1.25,
		levelAdd   = 0,
		levelMult  = 1.25,
	},
}

return Balance
