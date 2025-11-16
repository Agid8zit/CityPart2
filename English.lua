return {
	-- Key: unique identifier for the string
	-- Value: either a string (if no dialects), or a table of dialects + fallback
	__default_dialect = "_default",
	
--Numbers & Stuff
	["1"] = {
		["_default"] = "..."
	},

	["2"] = {
		["_default"] = "..."
	},

	["3"] = {
		["_default"] = "..."
	},

	["4"] = {
		["_default"] = "..."
	},

	["5"] = {
		["_default"] = "..."
	},

	["6"] = {
		["_default"] = "..."
	},

	["7"] = {
		["_default"] = "..."
	},

	["8"] = {
		["_default"] = "..."
	},
	
	["9"] = {
		["_default"] = "..."
	},

	["0"] = {
		["_default"] = "..."
	},

-- NEW CONTENT

	["⬆️ UPGRADE"] = {
		["_default"] = "⬆️ UPGRADE"
	},

	["Boombox Song"] = {
		["_default"] = "Boombox Song"
	},

	["CREDITS"] = {
		["_default"] = "CREDITS"
	},

	["Delete"] = {
		["_default"] = "Delete"
	},

	["No"] = {
		["_default"] = "No"
	},

	["Delete Save"] = {
		["_default"] = "Delete Save"
	},

	["Cancel"] = {
		["_default"] = "Cancel"
	},

	["Yes"] = {
		["_default"] = "Yes"
	},

	["Offsale"] = {
		["_default"] = "Offsale"
	},

	["To Purchase"] = {
		["_default"] = "To Purchase"
	},

	["x2 Earnings!"] = {
		["_default"] = "x2 Earnings!"
	},

	["Collect"] = {
		["_default"] = "Collect"
	},

	["ON"] = {
		["_default"] = "ON"
	},

	["Template"] = {
		["_default"] = "Template"
	},

	["Settings"] = {
		["_default"] = "Settings"
	},

	["City Name"] = {
		["_default"] = "City Name"
	},

	["Credits"] = {
		["_default"] = "Credits"
	},

	["Language"] = {
		["_default"] = "Language"
	},

	["Mute"] = {
		["_default"] = "Mute"
	},

	["Skip Song"] = {
		["_default"] = "Skip Song"
	},

	["Social Media"] = {
		["_default"] = "Social Media"
	},
	
	["ConfirmDelete"] = {
		["_default"] = 'Are you sure you want to <font color="rgb(255, 75, 75)">Delete</font>  this?'
	},

	["Refund_Amount"] = {
		["_default"] = 'Refund: <font color="rgb(255, 197, 21)">%s</font>'
	},
	
	["Cant overlap zones"] = {
		["_default"] = "You can’t overlap zones EASDASD KEY.",
	},

	["Cant build on roads"] = {
		["_default"] = "You can’t build on roads KEY.",
	},

	["Cant build on unique buildings"] = {
		["_default"] = "That area is reserved for a unique building KEY.",
	},	
	
	-- === Onboarding (Barrage 1) banners ===
	["OB1_Begin"]    = { ["_default"] = "Let’s build your first town. Follow the steps and watch the arrows." },
	["OB1_Complete"] = { ["_default"] = "Great work! Your starter town has water and power." },

	-- === Barrage 1 — Step 1: Road ===
	["OB1_S1_Road_Hint"] = { ["_default"] = "Select Road and draw a straight road to start your main street." },
	["OB1_S1_Road_Done"] = { ["_default"] = "Road placed!" },

	-- === Step 2: Residential zone ===
	["OB1_S2_Residential_Hint"] = { ["_default"] = "Zone Residential along the road. Drag a rectangle to place homes." },
	["OB1_S2_Residential_Done"] = { ["_default"] = "Homes are zoned." },

	-- === Step 3: Water Tower ===
	["OB1_S3_WaterTower_Hint"] = { ["_default"] = "Place a Water Tower to produce water for your city." },
	["OB1_S3_WaterTower_Done"] = { ["_default"] = "Water production online." },

	-- === Step 4: Water Pipe A ===
	["OB1_S4_WaterPipe_A_Hint"] = { ["_default"] = "Lay a water pipe from the tower toward the homes." },
	["OB1_S4_WaterPipe_A_Done"] = { ["_default"] = "Pipe placed." },

	-- === Step 5: Water Pipe B ===
	["OB1_S5_WaterPipe_B_Hint"] = { ["_default"] = "Run a pipe down so every house can connect." },
	["OB1_S5_WaterPipe_B_Done"] = { ["_default"] = "Neighborhood connected to water." },

	-- === Step 6: Wind Turbine ===
	["OB1_S6_WindTurbine_Hint"] = { ["_default"] = "Place a Wind Turbine to produce power." },
	["OB1_S6_WindTurbine_Done"] = { ["_default"] = "Power production online." },

	-- === Step 7: Power Lines A ===
	["OB1_S7_PowerLines_A_Hint"] = { ["_default"] = "Stretch power lines from the turbine toward the homes." },
	["OB1_S7_PowerLines_A_Done"] = { ["_default"] = "Line connected." },

	-- === Step 8: Power Lines B ===
	["OB1_S8_PowerLines_B_Hint"] = { ["_default"] = "Pull a line down so all blocks get power." },
	["OB1_S8_PowerLines_B_Done"] = { ["_default"] = "Neighborhood connected to power." },

	-- === Step 9: Second Road ===
	["OB1_S9_Road2_Hint"] = { ["_default"] = "Add another short road to expand your grid." },
	["OB1_S9_Road2_Done"] = { ["_default"] = "Grid expanded." },

	-- === Step 10: Commercial zone ===
	["OB1_S10_Commercial_Hint"] = { ["_default"] = "Zone a Commercial area near your road for shops." },
	["OB1_S10_Commercial_Done"] = { ["_default"] = "Shops are zoned." },

	-- === Generic routing hints (tabs/hubs) ===
	["OB_OpenBuildMenu"]    = { ["_default"] = "Open the Build Menu to continue." },
	["OB_OpenTransportTab"] = { ["_default"] = "Open the Transport tab." },
	["OB_OpenZonesTab"]     = { ["_default"] = "Open the Zones tab." },
	["OB_OpenSupplyTab"]    = { ["_default"] = "Open the Supply tab." },
	["OB_OpenServicesTab"]  = { ["_default"] = "Open the Services tab." },
	["OB_OpenWaterHub"]     = { ["_default"] = "Choose the Water hub." },
	["OB_OpenPowerHub"]     = { ["_default"] = "Choose the Power hub." },

	-- === Barrage 2 (Utilities coaching) ===
	["OB2_Begin"]         = { ["_default"] = "Utilities 101: keep buildings supplied with Water and Power." },
	["OB2_Complete"]      = { ["_default"] = "Utilities connected. Keep expanding!" },
	["OB2_WaterDeficit"]  = { ["_default"] = "Water deficit: add or upgrade water production." },
	["OB2_ConnectWater"]  = { ["_default"] = "Connect buildings to water with pipes." },
	["OB2_PowerDeficit"]  = { ["_default"] = "Power deficit: add or upgrade power production." },
	["OB2_ConnectPower"]  = { ["_default"] = "Connect buildings to power with lines." },

	-- === Legacy keys you referenced (kept for compatibility) ===
	["OB_SelectRoad"]       = { ["_default"] = "Select the Road tool." },
	["OB_SelectRoad_Done"]  = { ["_default"] = "Road tool selected." },
	
	-- Barrage 3 (Industrial) — add to your English locale
	["OB3_Begin"]                = "Next: Place an Industrial zone and connect it to road, water, and power.",
	["OB3_Industrial_Hint"]      = "Drag to zone the highlighted area as Industrial.",
	["OB3_Industrial_Done"]      = "Industrial zone placed!",
	["OB3_ConnectRoad"]          = "Connect the zone to a road.",
	["OB3_ConnectRoadNetwork"]   = "Connect that road to your city’s road network.",
	["OB3_ConnectWater"]         = "Lay pipes to supply water to the zone.",
	["OB3_ConnectPower"]         = "Run power lines to supply electricity to the zone.",
	["OB3_Complete"]             = "Great! The Industrial zone is fully connected.",
	
	-- === Loader / City load progress ===
	["LOAD_LoadingCity"]      = { ["_default"] = "Loading City" },
	["LOAD_Preparing"]        = { ["_default"] = "Preparing city" },
	["LOAD_SettingUpZones"]   = { ["_default"] = "Setting up zones" },
	["LOAD_BuildingRoads"]    = { ["_default"] = "Building roads" },
	["LOAD_PlacingBuildings"] = { ["_default"] = "Placing buildings" },
	["LOAD_LayingUtilities"]  = { ["_default"] = "Laying utilities" },
	["LOAD_Finalizing"]       = { ["_default"] = "REEEEEEEEEEEEEEEEEEEE" },

	-- === Client-only loader actions ===
	["LOAD_LoadingSave"]      = { ["_default"] = "Loading Save" },
	["LOAD_SwitchingSave"]    = { ["_default"] = "Switching Save" },
	["LOAD_DeletingSave"]     = { ["_default"] = "Deleting Save" },
	
	["Flag Afghanistan"] = { ["_default"] = "Flag Afghanistan" },
	["Flag Albania"] = { ["_default"] = "Flag Albania" },
	["Flag Algeria"] = { ["_default"] = "Flag Algeria" },
	["Flag America"] = { ["_default"] = "Flag America" },
	["Flag Angola"] = { ["_default"] = "Flag Angola" },
	["Flag Argentina"] = { ["_default"] = "Flag Argentina" },
	["Flag Armenia"] = { ["_default"] = "Flag Armenia" },
	["Flag Australia"] = { ["_default"] = "Flag Australia" },
	["Flag Austria"] = { ["_default"] = "Flag Austria" },
	["Flag Azerbaijan"] = { ["_default"] = "Flag Azerbaijan" },
	["Flag Bahrain"] = { ["_default"] = "Flag Bahrain" },
	["Flag Bangladesh"] = { ["_default"] = "Flag Bangladesh" },
	["Flag Belarus"] = { ["_default"] = "Flag Belarus" },
	["Flag Belgium"] = { ["_default"] = "Flag Belgium" },
	["Flag Belize"] = { ["_default"] = "Flag Belize" },
	["Flag Benin"] = { ["_default"] = "Flag Benin" },
	["Flag Bhutanica"] = { ["_default"] = "Flag Bhutanica" },
	["Flag Bolivia"] = { ["_default"] = "Flag Bolivia" },
	["Flag Bosnia"] = { ["_default"] = "Flag Bosnia" },
	["Flag Botswana"] = { ["_default"] = "Flag Botswana" },
	["Flag Brazil"] = { ["_default"] = "Flag Brazil" },
	["Flag Bulgaria"] = { ["_default"] = "Flag Bulgaria" },
	["Flag Burkina Faso"] = { ["_default"] = "Flag Burkina Faso" },
	["Flag Burundi"] = { ["_default"] = "Flag Burundi" },
	["Flag Cambodia"] = { ["_default"] = "Flag Cambodia" },
	["Flag Cameroon"] = { ["_default"] = "Flag Cameroon" },
	["Flag Canada"] = { ["_default"] = "Flag Canada" },
	["Flag Chad"] = { ["_default"] = "Flag Chad" },
	["Flag Chile"] = { ["_default"] = "Flag Chile" },
	["Flag China"] = { ["_default"] = "Flag China" },
	["Flag Colombia"] = { ["_default"] = "Flag Colombia" },
	["Flag Congo"] = { ["_default"] = "Flag Congo" },
	["Flag Costa Rica"] = { ["_default"] = "Flag Costa Rica" },
	["Flag Croatia"] = { ["_default"] = "Flag Croatia" },
	["Flag Cuba"] = { ["_default"] = "Flag Cuba" },
	["Flag Czech"] = { ["_default"] = "Flag Czech" },
	["Flag DR Congo"] = { ["_default"] = "Flag DR Congo" },
	["Flag Denmark"] = { ["_default"] = "Flag Denmark" },
	["Flag Dominican Republic"] = { ["_default"] = "Flag Dominican Republic" },
	["Flag Ecuador"] = { ["_default"] = "Flag Ecuador" },
	["Flag Egypt"] = { ["_default"] = "Flag Egypt" },
	["Flag El Salvador"] = { ["_default"] = "Flag El Salvador" },
	["Flag Eritrea"] = { ["_default"] = "Flag Eritrea" },
	["Flag Estonia"] = { ["_default"] = "Flag Estonia" },
	["Flag Ethiopia"] = { ["_default"] = "Flag Ethiopia" },
	["Flag Finland"] = { ["_default"] = "Flag Finland" },
	["Flag France"] = { ["_default"] = "Flag France" },
	["Flag Gabon"] = { ["_default"] = "Flag Gabon" },
	["Flag Gambia"] = { ["_default"] = "Flag Gambia" },
	["Flag Georgia"] = { ["_default"] = "Flag Georgia" },
	["Flag Germany"] = { ["_default"] = "Flag Germany" },
	["Flag Ghana"] = { ["_default"] = "Flag Ghana" },
	["Flag Greece"] = { ["_default"] = "Flag Greece" },
	["Flag Guatemala"] = { ["_default"] = "Flag Guatemala" },
	["Flag Guinea"] = { ["_default"] = "Flag Guinea" },
	["Flag Honduras"] = { ["_default"] = "Flag Honduras" },
	["Flag Hungary"] = { ["_default"] = "Flag Hungary" },
	["Flag Iceland"] = { ["_default"] = "Flag Iceland" },
	["Flag India"] = { ["_default"] = "Flag India" },
	["Flag Indonesia"] = { ["_default"] = "Flag Indonesia" },
	["Flag Iran"] = { ["_default"] = "Flag Iran" },
	["Flag Iraq"] = { ["_default"] = "Flag Iraq" },
	["Flag Ireland"] = { ["_default"] = "Flag Ireland" },
	["Flag Italy"] = { ["_default"] = "Flag Italy" },
	["Flag Ivory Coast"] = { ["_default"] = "Flag Ivory Coast" },
	["Flag Jamaica"] = { ["_default"] = "Flag Jamaica" },
	["Flag Japan"] = { ["_default"] = "Flag Japan" },
	["Flag Jordan"] = { ["_default"] = "Flag Jordan" },
	["Flag Kazakhstan"] = { ["_default"] = "Flag Kazakhstan" },
	["Flag Kenya"] = { ["_default"] = "Flag Kenya" },
	["Flag Kyrgyzstan"] = { ["_default"] = "Flag Kyrgyzstan" },
	["Flag Laos"] = { ["_default"] = "Flag Laos" },
	["Flag Latvia"] = { ["_default"] = "Flag Latvia" },
	["Flag Lebanon"] = { ["_default"] = "Flag Lebanon" },
	["Flag Liberia"] = { ["_default"] = "Flag Liberia" },
	["Flag Libya"] = { ["_default"] = "Flag Libya" },
	["Flag Lithuania"] = { ["_default"] = "Flag Lithuania" },
	["Flag Malawi"] = { ["_default"] = "Flag Malawi" },
	["Flag Malaysia"] = { ["_default"] = "Flag Malaysia" },
	["Flag Maldova"] = { ["_default"] = "Flag Maldova" },
	["Flag Mali"] = { ["_default"] = "Flag Mali" },
	["Flag Mauritania"] = { ["_default"] = "Flag Mauritania" },
	["Flag Mexico"] = { ["_default"] = "Flag Mexico" },
	["Flag Mongolia"] = { ["_default"] = "Flag Mongolia" },
	["Flag Montenegro"] = { ["_default"] = "Flag Montenegro" },
	["Flag Morocco"] = { ["_default"] = "Flag Morocco" },
	["Flag Mozambique"] = { ["_default"] = "Flag Mozambique" },
	["Flag Myanmar"] = { ["_default"] = "Flag Myanmar" },
	["Flag Namibia"] = { ["_default"] = "Flag Namibia" },
	["Flag Netherlands"] = { ["_default"] = "Flag Netherlands" },
	["Flag New Zealand"] = { ["_default"] = "Flag New Zealand" },
	["Flag Nicaragua"] = { ["_default"] = "Flag Nicaragua" },
	["Flag Nigeria"] = { ["_default"] = "Flag Nigeria" },
	["Flag Norway"] = { ["_default"] = "Flag Norway" },
	["Flag Oman"] = { ["_default"] = "Flag Oman" },
	["Flag Pakistan"] = { ["_default"] = "Flag Pakistan" },
	["Flag Palestine"] = { ["_default"] = "Flag Palestine" },
	["Flag Panama"] = { ["_default"] = "Flag Panama" },
	["Flag Papua New Guinea"] = { ["_default"] = "Flag Papua New Guinea" },
	["Flag Paraguay"] = { ["_default"] = "Flag Paraguay" },
	["Flag Peru"] = { ["_default"] = "Flag Peru" },
	["Flag Philippines"] = { ["_default"] = "Flag Philippines" },
	["Flag Poland"] = { ["_default"] = "Flag Poland" },
	["Flag Qatar"] = { ["_default"] = "Flag Qatar" },
	["Flag Romania"] = { ["_default"] = "Flag Romania" },
	["Flag Russia"] = { ["_default"] = "Flag Russia" },
	["Flag Rwanda"] = { ["_default"] = "Flag Rwanda" },
	["Flag Saudi Arabia"] = { ["_default"] = "Flag Saudi Arabia" },
	["Flag Senegal"] = { ["_default"] = "Flag Senegal" },
	["Flag Serbia"] = { ["_default"] = "Flag Serbia" },
	["Flag Sierra Leone"] = { ["_default"] = "Flag Sierra Leone" },
	["Flag Singapore"] = { ["_default"] = "Flag Singapore" },
	["Flag Slovakia"] = { ["_default"] = "Flag Slovakia" },
	["Flag Somalia"] = { ["_default"] = "Flag Somalia" },
	["Flag South Africa"] = { ["_default"] = "Flag South Africa" },
	["Flag South Korea"] = { ["_default"] = "Flag South Korea" },
	["Flag South Sudan"] = { ["_default"] = "Flag South Sudan" },
	["Flag Spain"] = { ["_default"] = "Flag Spain" },
	["Flag Sri Lanka"] = { ["_default"] = "Flag Sri Lanka" },
	["Flag Sudan"] = { ["_default"] = "Flag Sudan" },
	["Flag Sweden"] = { ["_default"] = "Flag Sweden" },
	["Flag Switzerland"] = { ["_default"] = "Flag Switzerland" },
	["Flag Syria"] = { ["_default"] = "Flag Syria" },
	["Flag Taiwan"] = { ["_default"] = "Flag Taiwan" },
	["Flag Tajikistan"] = { ["_default"] = "Flag Tajikistan" },
	["Flag Tanzania"] = { ["_default"] = "Flag Tanzania" },
	["Flag Thailand"] = { ["_default"] = "Flag Thailand" },
	["Flag Togo"] = { ["_default"] = "Flag Togo" },
	["Flag Tunisia"] = { ["_default"] = "Flag Tunisia" },
	["Flag Turkmenistan"] = { ["_default"] = "Flag Turkmenistan" },
	["Flag Türkiye"] = { ["_default"] = "Flag Türkiye" },
	["Flag Uganda"] = { ["_default"] = "Flag Uganda" },
	["Flag Ukraine"] = { ["_default"] = "Flag Ukraine" },
	["Flag United Kingdom"] = { ["_default"] = "Flag United Kingdom" },
	["Flag United Nations"] = { ["_default"] = "Flag United Nations" },
	["Flag Uruguay"] = { ["_default"] = "Flag Uruguay" },
	["Flag Uzbekistan"] = { ["_default"] = "Flag Uzbekistan" },
	["Flag Venezuela"] = { ["_default"] = "Flag Venezuela" },
	["Flag Vietnam"] = { ["_default"] = "Flag Vietnam" },
	["Flag Yemen"] = { ["_default"] = "Flag Yemen" },
	["Flag Zambia"] = { ["_default"] = "Flag Zambia" },
	["Flag Zimbabwe"] = { ["_default"] = "Flag Zimbabwe" },
	
-- Main UI

	["Build"] = {
		["_default"] = "Build"
	},
	
	["Home"] = {
		["_default"] = "Home"
	},

	["Undo"] = {
		["_default"] = "Undo"
	},

	["Redo"] = {
		["_default"] = "Redo"
	},
	
	--TABS
	
	["Transport"] = {
		["_default"] = "Transport"
	},
	
	["Zones"] = {
		["_default"] = "Zones"
	},
	
	["Services"] = {
		["_default"] = "Services"
	},
	
	["Supply"] = {
		["_default"] = "Supply"
	},
	
	["Road"] = {
		["_default"] = "Road"
	},
	
	["Bus"] = {
		["_default"] = "Bus"
	},
	
	["Metro"] = {
		["_default"] = "Metro"
	},
	
	["METRO"] = {
		["_default"] = "METRO"
	},
	
	["Airport"] = {
		["_default"] = "Airport"
	},
	
	["AIRPORT"] = {
		["_default"] = "AIRPORT"
	},
	
	--Zones

	["Residential Zone"] = {
		["_default"] = "Residential Zone"
	},

	["Commercial Zone"] = {
		["_default"] = "Commercial Zone"
	},

	["Industrial Zone"] = {
		["_default"] = "Industrial Zone"
	},

	["Dense Residential Zone"] = {
		["_default"] = "Dense Residential Zone"
	},

	["Dense Commercial Zone"] = {
		["_default"] = "Dense Commercial Zone"
	},

	["Dense Industrial Zone"] = {
		["_default"] = "Dense Industrial Zone"
	},
	
	
--2nd Batch Essential UI
	["Residential"] = {
		["_default"] = "Residential",
	},

	["Commercial"] = {
		["_default"] = "Commercial",
	},


	["Industrial"] = {
		["_default"] = "Industrial",
	},
	["Fire Precinct"] = {
		["_default"] = "Fire Precinct",
	},

	["Fire Station"] = {
		["_default"] = "Fire Station",
	},

--Health
	["City Hospital"] = {
		["_default"] = "City Hospital",
	},
	
	["Local Hospital"] = {
		["_default"] = "Local Hospital",
	},
	["Major Hospital"] = {
		["_default"] = "Major Hospital",
	},

	["Small Clinic"] = {
		["_default"] = "Small Clinic",
	},

--Education
	["MiddleSchool"] = {
		["_default"] = "Middle School",
	},
	["Museum"] = {
		["_default"] = "Museum",
	},

	["NewsStation"] = {
		["_default"] = "News Station",
	},
	["PrivateSchool"] = {
		["_default"] = "Private School",
	},
	
	--Transport

	["Bus Depot"] = {
		["_default"] = "Bus Depot",
	},
	
	--LandMarks
	["Bank"] = {
		["_default"] = "Bank",
	},
	
	["CN Tower"] = {
		["_default"] = "CN Tower",
	},

	["Eiffel Tower"] = {
		["_default"] = "Eiffel Tower",
	},
	
	["Empire State Building"] = {
		["_default"] = "Empire State Building",
	},
	
	["Ferris Wheel"] = {
		["_default"] = "Ferris Wheel",
	},
	
	["Gas Station"] = {
		["_default"] = "Gas Station",
	},

	["Modern Skyscraper"] = {
		["_default"] = "Modern Skyscraper",
	},
	["National Capital"] = {
		["_default"] = "National Capital",
	},
	["Obelisk"] = {
		["_default"] = "Obelisk",
	},
	["Space Needle"] = {
		["_default"] = "Space Needle",
	},

	["Statue of Liberty"] = {
		["_default"] = "Statue of Liberty",
	},
	["Tech Office"] = {
		["_default"] = "Tech Office",
	},
	["World Trade Center"] = {
		["_default"] = "World Trade Center",
	},
	
--Leisure/Community
	["Church"] = {
		["_default"] = "Church",
	},
	["Hotel"] = {
		["_default"] = "Hotel",
	},

	["Mosque"] = {
		["_default"] = "Mosque",
	},
	
	["Movie Theater"] = {
		["_default"] = "Movie Theater",
	},
	
	["Shinto Temple"] = {
		["_default"] = "Shinto Jinja",
	},
	["Buddha Statue"] = {
		["_default"] = "Buddha Statue"
	},
	["Hindu Temple"] = {
		["_default"] = "Hindu Mandir"
	},
	
--Police
	["Courthouse"] = {
		["_default"] = "Courthouse",
	},

	["PoliceDept"] = {
		["_default"] = "Police Dept",
	},
	
	["PolicePrecinct"] = {
		["_default"] = "Police Precinct",
	},
	
	["PoliceStation"] = {
		["_default"] = "Police Station",
	},

--Sports
		["Archery Range"] = {
			["_default"] = "Archery Range",
		},
		
		["Basketball Court"] = {
			["_default"] = "Basketball Court",
		},
		
		["Basketball Stadium"] = {
			["_default"] = "Basketball Stadium",
		},
		
		["Football Stadium"] = {
			["_default"] = "Football Stadium",
		},
		
		["Golf Course"] = {
			["_default"] = "Golf Course",
		},
		
		["Public Pool"] = {
			["_default"] = "Public Pool",
		},
		
		["Skate Park"] = {
			["_default"] = "Skate Park",
		},
		
		["Soccer Stadium"] = {
			["_default"] = "Soccer Stadium",
		},
		
		["Tennis Court"] = {
			["_default"] = "Tennis Court",
		},
--Power
		["Coal Power Plant"] = {
			["_default"] = "Coal Power Plant",
		},
		
		["Gas Power Plant"] = {
			["_default"] = "Gas Power Plant",
		},
		
		["Geothermal Power Plant"] = {
			["_default"] = "Geothermal Power Plant",
		},
		
		["Nuclear Power Plant"] = {
			["_default"] = "Nuclear Power Plant",
		},
		
		["Solar Panels"] = {
			["_default"] = "Solar Panels",
		},
		
		["Wind Turbine"] = {
			["_default"] = "Wind Turbine",
		},
		["Power Lines"] = {
			["_default"] = "Power Line",
		},
--Water
	["Water Tower"] = {
		["_default"] = "Water Tower",
	},

	["Water Plant"] = {
		["_default"] = "Water Plant",
	},

	["Purification Water Plant"] = {
		["_default"] = "Water Purification Plant",
	},

	["MolecularWaterPlant"] = {
		["_default"] = "Molecular Water Plant",
	},

	["Water Pipes"] = {
		["_default"] = "Water Pipes",
	},


--Services
	["Leisure"] = {
		["_default"] = "Leisure"
	},

	["Fire Dept"] = {
		["_default"] = "Fire Dept"
	},
	
	["Fire Depth"] = {
		["_default"] = "Fire Dept"
	},


	["Police"] = {
		["_default"] = "Police"
	},

	["Health"] = {
		["_default"] = "Health"
	},

	["Education"] = {
		["_default"] = "Education"
	},

	["Sports"] = {
		["_default"] = "Sports"
	},

	["Landmarks"] = {
		["_default"] = "Landmarks"
	},
	
--Supply

	["Power"] = {
		["_default"] = "Power"
	},

	["Water"] = {
		["_default"] = "Water"
	},

	["Garbage"] = {
		["_default"] = "Garbage"
	},

	["Graves"] = {
		["_default"] = "Graves"
	},

--COOP

	["Co-Op"] = {
		["_default"] = "Co-Op"
	},

	["You've been invited to co-op PlayerName"] = {
		["_default"] = "You've been invited to co-op PlayerName"
	},

	["Ignore"] = {
		["_default"] = "Ignore"
	},

	["Accept"] = {
		["_default"] = "Accept"
	},
	
	["Invite Friends"] = {
		["_default"] = "Invite Friends"
	},

	["Leave Co-Op"] = {
		["_default"] = "Leave Co-Op"
	},
	
	["Invite"] = {
		["_default"] = "Invite"
	},
	
--Demands


	["Demands"] = {
		["_default"] = "Demands"
	},

	["Demand = Higher Bar"] = {
		["_default"] = "Demand = Higher Bar"
	},

	["Poor"] = {
		["_default"] = "Poor"
	},

	["Medium"] = {
		["_default"] = "Medium"
	},

	["Wealthy"] = {
		["_default"] = "Wealthy"
	},
	["Normal"] = {
		["_default"] = "Normal"
	},
	["High Density"] = {
		["_default"] = "High Density"
	},


--Power

	["Produced WATER"] = {
		["_default"] = "Produced: %s L"
	},

	["Used WATER"] = {
		["_default"] = "Used: %s L"
	},

	["Usage WATER"] = {
		["_default"] = "Usage %s%%"
	},
	
	["Produced POWER"] = {
		["_default"] = "Produced: %s W"
	},

	["Used POWER"] = {
		["_default"] = "Used: %s W"
	},

	["Usage POWER"] = {
		["_default"] = "Usage %s%%"
	},
	
--Load Menu

	["Build A City"] = {
		["_default"] = "Build A City"
	},

	["Load"] = {
		["_default"] = "Load"
	},

	["New"] = {
		["_default"] = "New"
	},
	
	["New City"] = {
		["_default"] = "New"
	},

	["Last Played"] = {
		["_default"] = "Last Played"
	},
	
--Premium Shop

	["Money"] = {
		["_default"] = "Money"
	},

	["Gamepass"] = {
		["_default"] = "Gamepass"
	},

	["10% More!"] = {
		["_default"] = "10% More!"
	},

	["15% More!"] = {
		["_default"] = "15% More!"
	},
	
	["25% More!"] = {
		["_default"] = "25% More!"
	},

	["Best Deal!"] = {
		["_default"] = "Best Deal!"
	},

	["$"] = {
		["_default"] = "$"
	},

	["Purchase"] = {
		["_default"] = "Purchase"
	},

	["Ok"] = {
		["_default"] = "Ok"
	},
	
--Robux Thanks
	["Thank you!"] = {
		["_default"] = "Thank you!"
	},

	["Thanks for supporting our team, and our charity donations :D"] = {
		["_default"] = "Thanks for supporting our team, and our charity donations :D"
	},

-- Power Line, Industrial, Commercial, Residential, 

--Town Twitter
	-- With dialects
	
--Batch 1
	--No Power
	["A blackout again? I can't even call or email the electrical company when there's no power :("] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["Help, my TV doesn't work when there's no power!"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["Power to the people! How hard is it to build a working power grid? It’s not exactly state of the art technology."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	-- No Water
	["Hey, guys, is the water supposed to be brown and crunchy?"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["Don't I pay my taxes for services like water??? This is absurd!"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["I would think that fresh water is basic stuff, but NO! How long do we have to wait for working water pipes!?"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	
--Crime
	["Ban crime! I want no more crime!"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["I will happily pay some extra taxes, if we can get the crime levels down."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	-- No police coverage / crime problems
	["Every night it’s sirens and shouting. Where are the police?"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Break-ins everywhere. We need a police station closer than the next city over."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Feels like crime’s the only thing booming in this neighborhood."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Every shop’s installing bars on the windows. Maybe build a precinct instead?"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Someone stole my bike again. At this point I should just rent it to them."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- Praise for new / effective coverage
	["Finally, a police precinct opened nearby. Streets already feel calmer."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Just saw officers patrolling downtown. Feels safer than it’s been in years."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Crime dropped fast once the new Police Dept went up. Great work, city!"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Courthouse finally opened! Justice might actually happen now!"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Seeing blue lights used to mean trouble. Now it means peace of mind."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- Funding / response / reform
	["Police doing their best, but there’s only so many of them. Fund the department!"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Response times are slow. Maybe the precinct needs more vehicles."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Wouldn’t mind a few more patrols in the alley behind my store."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["The courthouse backlog is wild! Cases from last year still waiting."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["If they had better funding, maybe the cops could stop using scooters."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- Community / realism / humor
	["The new precinct’s coffee is apparently better than the café’s."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Finally got my wallet back from lost-and-found. Didn’t expect that level of service!"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Saw an officer petting a stray dog on patrol. City’s really turning around."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Funny how crime drops when people realize there’s actually a police station now."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	
--Fire
	-- No fire coverage / danger
	["A single spark out here and the whole block’s gone. Where are the firefighters?"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["My neighbor’s grill caught fire and we had to use buckets. That can’t be normal city life."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["No fire station for miles...guess we’re all volunteers now."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Every time I smell smoke, I start packing. We need a fire dept."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- Fire coverage established / praise
	["Finally, the new Fire Dept opened nearby. Feels good knowing someone’s watching the flames."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["The new Fire Station looks incredible. Hope I never need it, but I’m glad it’s there."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Heard sirens this morning! Quick response, city’s improving!"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Firefighters saved the bakery! Free muffins for heroes."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Finally, hydrants with pressure. My water hose isn’t the first line of defense anymore."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- Funding / resources / staffing
	["Fire Dept’s underfunded. They’re still driving 20-year-old trucks!"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["More firefighters, less fireworks! Give them proper funding!"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Response times are slow lately. Maybe they need more stations."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["If the Fire Precinct had more funding, maybe insurance wouldn’t be this high."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Firefighters are doing their best, but the city’s growing faster than their budget."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- Community / humor / realism
	["Someone left their toast on again. I heard the sirens before the smoke alarm."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["If the Fire Station had a café, I’d stop by just to say thanks."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Shoutout to the Fire Dept! They’re faster than my internet."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
--Health
	["Got sick again and there’s still no clinic in this district."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["The nearest hospital is two bus rides away. Hope I survive the trip."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Can’t even get an appointment. We need more doctors, not more paperwork."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Small Clinic is closed again. Guess I’ll just tough it out."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["No emergency care nearby. If you get hurt here, good luck."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},

-- Praise / satisfaction
["The new City Hospital looks amazing! Finally, real healthcare in town."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Finally, a Local Hospital nearby. No more traveling halfway across the city for a checkup."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Got treated at the Small Clinic today! Fast, clean, and professional. Kudos to the staff!"] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["The Major Hospital opened and it’s already saving lives. Great job, city!"] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Feeling safer just knowing there’s a functioning hospital nearby."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},

-- Funding / staffing / infrastructure
["Doctors are overworked and patients keep piling in! Build another hospital!"] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Clinic’s great, but they could use more nurses. Everyone’s exhausted."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["The ER waiting room looks like a concert lineup. Fund the health system already!"] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Healthcare’s stretched too thin! Patients in hallways again."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["If the City Hospital got better funding, maybe we wouldn’t have two-hour ambulance waits."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},

-- Community / realism / humor
["Big thanks to the clinic nurse who still smiles after twelve-hour shifts."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Someone coughed on the bus and ten people panicked. We really need better hospitals."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["They opened a Major Hospital and the pharmacy lines doubled overnight. Progress?"] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["My kid said the clinic lollipops taste like medicine. Honestly, same."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Doctors and firefighters should get statues before politicians do."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},

--Education
-- General Education: access, overcrowding, praise, funding
["Our kids deserve real classrooms, not overflow in hallways. Build more schools!"] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Buses are shipping students across town again. We need a local school now."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Textbooks are older than the dionsaurs in them. Can we fund education like we mean it?"] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Smaller class sizes would fix half our problems. Build one more school, please."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Proud day for the city! Our kids finally have places to learn close to home."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},

-- Middle School
["The new Middle School looks amazing! Our kids won’t have to commute forever anymore."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Middle School is packed already. Guess we should’ve built two."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Clubs, sports, and science fairs? Middle School is finally a real hub for families."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Heard the Middle School library got new computers. That’s how you build futures."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Drop-off lane at Middle School is chaos. Great school! Now fix the traffic plan!"] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},

-- Private School
["Private School opened its doors and suddenly uniforms are in fashion."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Private School scholarships would go a long way! Talent shouldn’t depend on wallets."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Heard Private School has small classes and serious teachers. Sounds like results incoming."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Not my budget, but I’m glad Private School takes pressure off the public system."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Private School debate team is sweeping tournaments. City pride, fancy blazers edition."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},

-- Museum
["Museum’s finally open! Weekend plans solved!"] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Field trips to the Museum beat worksheets every time. Thank you, city!"] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Rotating exhibits at the Museum keep downtown lively and local businesses busy."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["More late-night hours at the Museum, please some of us work days!"] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["The Museum gift shop is a trap and I’m happily stuck. Education + souvenirs = win."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},

-- News Station
["Local News Station is live finally! City updates that aren’t rumors."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["News Station covering school board meetings means less drama, more facts. Love it."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Traffic and weather from the News Station actually saved me time today. Journalism works!"] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["If the News Station keeps highlighting achievements, more families will move here. Smart play, city."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Shoutout to local reporters asking real questions. Keep schools accountable, keep us informed."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
-- Leisure
	-- General Leisure (non-specific)
	["This city needs more places to unwind before we all burn out."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
	},
	["Weekends feel better when there’s somewhere calm to go and clear your head."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
	},
	["Public spaces pay for themselves in community spirit. Build more, argue less."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
	},
	
-- HOTEL
["Hotel just opened downtown! Tourists incoming and local shops smiling already."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Conference space at the Hotel means real business travel now! Good for the whole city."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["If the Hotel improves transit shuttles, guests won’t flood the streets with taxis. Win-win."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Hotel rooftop views are unreal! Instant postcard material for visitors and locals alike."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Nice to see the Hotel hiring locally! Puts money right back into the neighborhood."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},

-- MOVIE THEATER
["The new movie theater revived date night. Popcorn economy booming!"] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Festival screenings at the theater are drawing crowds! Downtown feels alive again."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Free popcorn would help families! Any chance the theater can make that happen?"] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Love the theater, but staggering showtimes could ease the parking crunch by a lot."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
},
["Community film nights at the theater? Local shorts before the feature would be awesome."] = {
	["_default"] = "",
	["DIALECT1"] = "",
	["DIALECT2"] = "",
	["DIALECT3"] = "",
	},
	
-- Religion
	-- Sentiment 1: Community hub / belonging
	["The Church feels like a real community hub: quiet mornings, helpful people, open doors."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["The Mosque feels like a real community hub: quiet mornings, helpful people, open doors."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["The Shinto Temple feels like a real community hub: quiet mornings, helpful people, open doors."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["The Hindu Temple feels like a real community hub: quiet mornings, helpful people, open doors."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["The Buddha Statue plaza feels like a real community hub: quiet mornings, helpful people, open doors."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- Sentiment 2: Programs / extended hours
	["Could the Church extend weekend hours? Lots of families would appreciate evening programs."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Could the Mosque extend weekend hours? Lots of families would appreciate evening programs."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Could the Shinto Temple extend weekend hours? Lots of families would appreciate evening programs."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Could the Hindu Temple extend weekend hours? Lots of families would appreciate evening programs."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Could the Buddha Statue site extend weekend hours? Lots of families would appreciate evening programs."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- Sentiment 3: Interfaith / open house
	["An interfaith open house at the Church would be great! Meet neighbors, share food, build trust."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["An interfaith open house at the Mosque would be great! Meet neighbors, share food, build trust."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["An interfaith open house at the Shinto Temple would be great! Meet neighbors, share food, build trust."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["An interfaith open house at the Hindu Temple would be great! Meet neighbors, share food, build trust."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["An interfaith open house at the Buddha Statue plaza would be great! Meet neighbors, share food, build trust."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- Sentiment 5: Emergency relief / civic contribution
	["Big thanks to the Church volunteers turning the hall into a relief center during emergencies. Heroes."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Big thanks to the Mosque volunteers turning the hall into a relief center during emergencies. Heroes."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Big thanks to the Shinto Temple volunteers turning the hall into a relief center during emergencies. Heroes."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Big thanks to the Hindu Temple volunteers turning the hall into a relief center during emergencies. Heroes."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Big thanks to the Buddha Statue caretakers turning the grounds into a relief center during emergencies. Heroes."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	
--Transportation
	-- TRANSPORTATION (BusDepot, Airport)

	-- BUS DEPOT

	-- Missing coverage
	["Still no Bus Depot in this district; half the routes end in the middle of nowhere."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["No depot means buses break down on the street. Maybe build one before the fleet collapses?"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Waiting for a bus that never comes. This neighborhood needs proper service."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- Happy to have
	["The new Bus Depot changed everything. Buses actually arrive on time now!"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Depot is open, routes are smooth, and commuting finally feels civilized."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Seeing freshly cleaned buses every morning gives me more faith in the city than most speeches do."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- Wanting upgrades
	["Bus Depot is working overtime. Time to expand before rush hour destroys it."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["We need more electric buses. The depot could lead the way in going green."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Depot is too small for a growing city. Fund upgrades before delays return."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Drivers deserve better facilities too. Fund the depot break rooms and workshops."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- AIRPORT
	-- Missing coverage
	["No Airport means we are cut off from the world. Businesses and tourism are stuck on the ground."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["We have skyscrapers but no Airport. How do people even visit this place?"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Driving to another city just to fly is ridiculous. Build an Airport already!"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- Happy to have
	["Finally, flights are running and the Airport looks incredible."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Airport security is smooth, shops are open, and it actually feels world class."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Seeing planes overhead again feels like the city is truly connected to the world."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["The Airport has boosted local hotels and restaurants overnight. Smart investment!"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- Wanting upgrades
	["Airport is great, but we need a second terminal before travelers start camping on the floor."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Customs lines are brutal. Time for more staff and faster systems."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Airport expansion would mean new routes, new jobs, and fewer layovers. Let's do it."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["The cargo side of the Airport could use more funding too. Exports keep the city running."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},	
	
	-- Wanting a Metro
	["We need a Metro system already. The buses can only do so much."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Traffic is a nightmare. Please, just build a Metro before I lose my mind."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["A Metro would connect the city like nothing else. No more two-hour commutes."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- Happy to have one
	["The Metro opened this week and it already feels like the city leveled up."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Fast, clean, quiet. I cannot believe I am saying this about public transport."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Took the Metro today and got to work early for the first time in years."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Finally, a Metro that makes us feel like a real city. Worth every tax dollar."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- Urban legends / worry / mystery
	["Rode the Metro at night and swear I saw someone staring back from an empty tunnel."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Who keeps talking about Marvin in the tunnels? Is that supposed to be a mascot or a ghost?"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["People say the Metro hums even when the power is off. I am not checking to find out."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Metro maintenance crews keep finding toys down there. No one knows where they come from."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Urban legend says Marvin used to live down there before the Metro opened. Now he just waits."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Heard the Metro has a hidden station that is not on any map. If you see it, do not get off."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- Realistic construction / funding posts
	["Metro construction is noisy but worth it. The city finally feels alive again."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["They say the Metro went over budget again. Still better than sitting in traffic for half my life."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Metro delays again, but at least it is progress. Better late than never."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	
	-- SPORTS (ArcheryRange, BasketballCourt, BasketballStadium,
	-- FootballStadium, GolfCourse, PublicPool, SkatePark, SoccerStadium, TennisCourt)

	-- Archery Range
	["Would love an Archery Range out here. Beats staring at empty lots all weekend."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Archery Range is finally open. Calm, quiet, and precise. Best stress relief in the city."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Archery Range is way better than another mall. Focus over shopping any day."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- Basketball Court
	["The Basketball Court is packed every afternoon. Easily the best community spot around."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Wish we had a Basketball Court nearby. It would keep the kids busy and happy."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Basketball Court beats any gym membership. Free, fun, and friendly."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- Basketball Stadium
	["Basketball Stadium days are the loudest, happiest days this city gets."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["We need a real Basketball Stadium so the team stops borrowing arenas."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["The new Basketball Stadium is incredible. Feels like a major city now."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- Football Stadium
	["Football Stadium crowds are massive. Local economy is loving game days."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Still waiting on a Football Stadium here. Everyone keeps driving to the next city."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["The new Football Stadium puts our city on the map."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- Golf Course
	["Golf Course opened this week. Finally a reason for business meetings outdoors."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["A Golf Course would look great here. Better than another office park."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Golf Course greens make this part of town look alive. Best landscaping in the city."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- Public Pool
	["Public Pool is open and the whole neighborhood showed up. Best summer in years."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["We could use a Public Pool. The kids are melting out here."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["The Public Pool beats every private gym. Cheap, clean, and fun."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- Skate Park
	["The Skate Park finally opened. Now we can stop getting yelled at downtown."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Still no Skate Park here. Guess the stairs will have to do."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Skate Park brings life to this area. Better than another parking lot any day."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- Soccer Stadium
	["Soccer Stadium is packed and electric. Nothing beats game day energy."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Still no Soccer Stadium. Players keep practicing on empty fields."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Our Soccer Stadium puts the whole city in a good mood."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},

	-- Tennis Court
	["The Tennis Court is spotless and full every morning. Great addition to the neighborhood."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["Still no Tennis Court nearby. Guess we will keep using the parking lot lines."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	["The Tennis Court looks great next to the park. Makes the area feel upscale."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",
	},
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
--Random
	["Was there always a road there? I like it."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["Did you know there are more planes in the ocean than submarines in the sky?"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["I like the new coffee shop downtown."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["Everyone has the right to be stupid, it's just some people abuse the privilege."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["My friend said that the old factory has a really cool abandoned tunnel in it. I don't think I'll find out for myself."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["I dont think inside the box or outside the box... I dont even know where the box is..."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["I think I might paint my house blue. I like blue."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["Things just aren’t what they used to be. And probably never were."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["I’ve always wanted to be somebody, but I see now I should’ve been more specific."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["The early bird can have the worm, because worms are gross and mornings are stupid."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["I love the new trees they planted in my neighborhood."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["Be yourself. No one can ever tell you’re doing it wrong."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["My favorite childhood memory, is not paying bills."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["Did you know that birds control time? They do this out of spite."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["If someone makes you happy, make them happier."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["I like bananas because they have no bones."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["A raccoon ate through my trashcan yesterday. It was a really cute raccoon, so I'm not really mad about it."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["Forever is a long time. But not as long as it was yesterday."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["I've heard they're getting rid of Ohio. It's for the best, really."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["Have you seen Marvin? He owes me money."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["Do you think my cat knows about the feminist movement?"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["Norbert has a face you’d want to punch. Not because there is anything wrong with the face itself, but just because it's his and he is mean."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["Refusing to have an opinion, is a way of having one, isn’t it?"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["My name is Len, short for Lenjamin."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["Do you think if we get enough of us together, we could overthrow the gigantic person that runs our city?"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["I cannot become what I need to be, by remaining what I am."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["It’s ok that you’re not who you thought you’d be."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["If you feel like everyone else hates you, you need sleep. If you feel like you hate everyone else, you need to eat."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["Do you think whoever runs this city knows what a penguin looks like? I don't, and I am really curious."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["I think ultimately you become whoever would have saved you that time that no one did."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["I learn something everyday. And a lot of times, it’s that what I learned yesterday, was wrong."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["I know that when the world falls apart, raccoons will never judge me. They will only haunt my waking nightmares with their tiny, tiny hands."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["I've got to be careful going in search of adventure. It’s ridiculously easy to find."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["Latest news: A new type of deodorant has been invented! It does exactly the same thing as the old ones."] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	["If god isn't real then why does the palm of a man fit so perfectly against the throat of a goose?"] = {
		["_default"] = "",
		["DIALECT1"] = "",
		["DIALECT2"] = "",
		["DIALECT3"] = "",

	},
	
--On Boarding
	["You Need to Build A Water Source"] = {
		["_default"] = "You Need to Build A Water Source",
	},
	["You Need to Build Water Pipes"] = {
		["_default"] = "You Need to Build Water Pipes",
	},
	["You Need to Build A Power Source"] = {
		["_default"] = "You Need to Build A Power Source",
	},
	["You Need to Build Power Lines"] = {
		["_default"] = "You Need to Build Power Lines",
	},
	["You Need to Build Roads"] = {
		["_default"] = "You Need to Build Roads",
	}
	
	--[[
		Roads must connect back to the highway or citizens cant travel to your city!
	]]
}
