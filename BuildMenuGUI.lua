local BuildMenu = {}

-- Roblox Services
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

-- Dependencies
local Abr = require(ReplicatedStorage.Scripts.UI.Abrv)
local UtilityGUI = require(ReplicatedStorage.Scripts.UI.UtilityGUI)
local DevProducts = require(ReplicatedStorage.Scripts.DevProducts)
local SoundController = require(ReplicatedStorage.Scripts.Controllers.SoundController)
local PlayerDataController = require(ReplicatedStorage.Scripts.Controllers.PlayerDataController)

local Balancing = ReplicatedStorage:WaitForChild("Balancing")
local BalanceEconomy = require(Balancing:WaitForChild("BalanceEconomy"))
local selectZoneEvent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents"):WaitForChild("SelectZoneType")
local Events = ReplicatedStorage:WaitForChild("Events")
local RE = Events:WaitForChild("RemoteEvents")
local FUS = RE:WaitForChild("FeatureUnlockStatus")
local RE_BusSupportStatus = RE:WaitForChild("BusSupportStatus")
local RE_MetroSupportStatus = RE:FindFirstChild("MetroSupportStatus")

-- Constant
local BUTTON_SCROLL_SPEED = 300

-- Defines
local UI = script.Parent
local LocalPlayer = Players.LocalPlayer
local MajorCurrentTabName = nil
local CurrentTabName = nil
local TabSections = {} -- [TabName] = FrameContainer
local FrameButtons = {} -- [BuildingID] = Frame
local CachedLevel = 0

local BuildingLevelRequirement = {} -- [BuildingID] = MinLevel
-- Populate Level Requirements
for level, buildingList in pairs(BalanceEconomy.ProgressionConfig.unlocksByLevel) do
	local lvlNum = tonumber(level) or 0
	for _, buildingID in ipairs(buildingList) do
		BuildingLevelRequirement[buildingID] = lvlNum
	end
end
-- UI References
local UI_Exit = UI.main.exit

local UI_Tab_Services = UI.main.tabs.services
local UI_Tab_Supply = UI.main.tabs.supply
local UI_Tab_Transpot = UI.main.tabs.transport
local UI_Tab_Zones = UI.main.tabs.zones

local UI_TabScroll_Left = UI.main.container.Left
local UI_TabScroll_Right = UI.main.container.Right

local UI_TabChoicesContainer = UI.main.container.TabChoices.Template;
UI_TabChoicesContainer.Visible = false

local UI_PlaceButton = UI.main.PlaceButton

local UnlockedTypes = {}
local PrevUnlocks = {}  -- feature -> bool
local BE = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents")

-- === Model catalog for unlock popups ===
local RS  = game:GetService("ReplicatedStorage")
local FT  = RS:WaitForChild("FuncTestGroundRS")
local BLD = FT:WaitForChild("Buildings")

local CategoryButtonForSection: {[string]: Frame} = {}

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
}

-- Common folders you used in BuildMenu
local IND  = BLD:WaitForChild("Individual"):WaitForChild("Default")
local EDUC = IND:WaitForChild("Education")
local FIRE = IND:WaitForChild("Fire")
local POLI = IND:WaitForChild("Police")
local HLTH = IND:WaitForChild("Health")
local LAND = IND:WaitForChild("Landmark")
local POWR = IND:WaitForChild("Power")
local WATR = IND:WaitForChild("Water")
local TRAN = IND:FindFirstChild("Transport") -- only if you have it

-- Map feature IDs (as used in Progression.unlocksByLevel) to models
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

	-- Transport (if present)
	Airport               = TRAN and TRAN["Airport"] or nil,
	BusDepot              = TRAN and TRAN["Bus Depot"] or nil,
	MetroEntrance         = TRAN and TRAN["Metro Entrance"] or nil,
}

local FeatureIcons = {
	Commercial  = "rbxassetid://80804212045512",
	Industrial  = "rbxassetid://81164152585346",
	ResDense    = "rbxassetid://111951665644294",
	CommDense   = "rbxassetid://133436787771849",
	IndusDense  = "rbxassetid://139640185589881",
}

local ItemToSection: {[string]: string} = {}      -- "PoliceDept" -> "Police"
local PendingByItem: {[string]: boolean} = {}     -- per-item pending
local SectionHasPending: {[string]: boolean} = {} -- "Fire" -> true if any item pending in Fire

-- Map a section to its top tab for hierarchical badges
local SECTION_TO_MAJOR = {
	-- Major sections
	Services  = "Services",
	Supply    = "Supply",
	Transport = "Transport",
	Zones     = "Zones",

	-- Services sub-sections
	Fire       = "Services",
	Education  = "Services",
	Health     = "Services",
	Landmarks  = "Services",
	Leisure    = "Services",
	Police     = "Services",
	Sports     = "Services",

	-- Supply sub-sections
	Power = "Supply",
	Water = "Supply",

	-- Transport sub-sections
	Road  = "Transport",

	-- (No need to map "Transport" or "Zones" to themselves again)
}

-- Ensure every button gets a "notification" Frame (red dot) once
local function ensureButtonNotif(btn: Frame)
	local dot = btn:FindFirstChild("notification")
	if dot then return dot end
	dot = Instance.new("Frame")
	dot.Name = "notification"
	dot.Size = UDim2.fromOffset(10, 10)
	dot.AnchorPoint = Vector2.new(1, 0)
	dot.Position = UDim2.fromScale(1, 0)
	dot.BackgroundColor3 = Color3.fromRGB(255, 64, 64)
	dot.BorderSizePixel = 0
	dot.Visible = false
	local uic = Instance.new("UICorner")
	uic.CornerRadius = UDim.new(1, 0)
	uic.Parent = dot
	dot.Parent = btn
	return dot
end

-- Toggle top-tab pips based on any pending underneath
local function setTopTabNotification(major: string, state: boolean)
	if major == "Services" then
		BuildMenu.SetServicesTabNotification(state)
	elseif major == "Supply" then
		BuildMenu.SetSupplyTabNotification(state)
	elseif major == "Transport" then
		BuildMenu.SetTranspotTabNotification(state)
	elseif major == "Zones" then
		BuildMenu.SetZonesTabNotification(state)
	end
end

-- Recompute the *major* tab pips from SectionHasPending
local function recomputeTopTabBadges()
	local anyServices = false
	local anySupply   = false
	local anyTransport= false
	local anyZones    = false
	for section, has in pairs(SectionHasPending) do
		if has then
			local major = SECTION_TO_MAJOR[section]
			if major == "Services"  then anyServices  = true
			elseif major == "Supply"   then anySupply   = true
			elseif major == "Transport"then anyTransport= true
			elseif major == "Zones"    then anyZones    = true
			end
		end
	end
	setTopTabNotification("Services",  anyServices)
	setTopTabNotification("Supply",    anySupply)
	setTopTabNotification("Transport", anyTransport)
	setTopTabNotification("Zones",     anyZones)
end

-- When user opens a section, mark everything in that section as "seen"
local function markSectionSeen(sectionName: string)
	local uiSection = TabSections[sectionName]
	if not uiSection then return end

	-- Clear per-button dots + pending flags for items in this section
	for itemID, btn in pairs(FrameButtons) do
		if ItemToSection[itemID] == sectionName then
			PendingByItem[itemID] = nil
			local dot = btn:FindFirstChild("notification")
			if dot then dot.Visible = false end
		end
	end

	SectionHasPending[sectionName] = false
	recomputeTopTabBadges()
end

local function entriesFor(features: {string})
	local arr = {}
	for _, id in ipairs(features) do
		-- Prefer icon for these
		local icon = FeatureIcons[id]
		if icon then
			arr[#arr+1] = { image = icon, label = id }
		else
			-- Fall back to model if mapped
			local m = FeatureModels[id]
			if m and m:IsA("Model") then
				arr[#arr+1] = m
			end
		end
	end
	return arr
end

local function shallowCopy(t)
	local c = {}
	for k, v in pairs(t) do c[k] = v end
	return c
end

local function openUnlockModal(gainedList)
	if #gainedList == 0 then return end

	-- Locate/prepare the UnlockGUI ScreenGui
	local pg  = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = pg:FindFirstChild("UnlockGui")
	if not gui then
		warn("[Unlocks] UnlockGUI ScreenGui not found in PlayerGui or ReplicatedStorage")
		return
	end
	if not gui:IsDescendantOf(pg) then
		gui = gui:Clone()
		gui.ResetOnSpawn = false
		gui.Parent = pg
	end

	-- Require the UnlockGui module (ModuleScript inside the ScreenGui)
	local ok, Mod = pcall(function()
		return require(gui:FindFirstChild("UnlockGui") or gui:FindFirstChildOfClass("ModuleScript"))
	end)
	if not ok or not Mod then
		warn("[Unlocks] Failed to require UnlockGui module:", ok, Mod)
		return
	end
	if Mod.Init then pcall(Mod.Init) end

	local title = (#gainedList == 1) and (gainedList[1] .. " Unlocked!") or "New items unlocked!"
	local desc  = table.concat(gainedList, ", ")

	local iconsOrModels = entriesFor(gainedList)
	pcall(Mod.OnShow, title, desc, iconsOrModels)
end


-- Networking
local RE_PlayerDataChanged_ExclusiveLocations = ReplicatedStorage.Events.RemoteEvents.PlayerDataChanged_ExclusiveLocations
local RE_ToggleBusDepotGui = RE:WaitForChild("ToggleBusDepotGui")
local RE_ToggleAirportGui  = RE:WaitForChild("ToggleAirportGui")
local RE_AirSupportStatus  = RE:FindFirstChild("AirSupportStatus")
-- In the BuildMenu table:
local myPlot = nil
local playerzones = nil
local playerzonesVisible = false
local pipesfolder = nil
local pipesfoldervisible = true
local waterpipeszones = nil
local waterpipeszonesVisible = false
local powerlineszones = nil
local powerlineszonesVisible = false
local buildings = nil
local buildingVisible = false
local buildingsNoQueryActive = false
local metroTunnelsFolder = nil
local metroTunnelsVisible = false

local buildingTransparencyMode = false
local storedBuildingTransparency = {} -- [Instance] = number
local storedBuildingCanCollide = {}   -- [Instance] = boolean   -- [ADDED]
local storedBuildingCanQuery   = {}   -- [Instance] = boolean   -- [ADDED]

local function SetBuildingsTransparent(state: boolean)
	if not buildings then return end
	if buildingTransparencyMode == state then return end
	buildingTransparencyMode = state

	for _, inst in ipairs(buildings:GetDescendants()) do
		if inst:IsA("BasePart") then
			if state then
				-- store originals
				storedBuildingTransparency[inst] = inst.Transparency
				storedBuildingCanCollide[inst]   = inst.CanCollide
				storedBuildingCanQuery[inst]     = inst.CanQuery
				-- apply placement-friendly state
				inst.Transparency = 0.75
				inst.CanCollide   = false
				inst.CanQuery     = false
			else
				-- restore stored values if present
				local t = storedBuildingTransparency[inst]
				if t ~= nil then
					inst.Transparency = t
					storedBuildingTransparency[inst] = nil
				end

				local cc = storedBuildingCanCollide[inst]
				if cc ~= nil then
					inst.CanCollide = cc
					storedBuildingCanCollide[inst] = nil
				end

				local cq = storedBuildingCanQuery[inst]
				if cq ~= nil then
					inst.CanQuery = cq
					storedBuildingCanQuery[inst] = nil
				end
			end
		end
	end
end

-- keep stored values updated when new parts are added
if buildings then
	buildings.DescendantAdded:Connect(function(inst)
		if not buildingTransparencyMode then return end
		if inst:IsA("BasePart") then
			-- store originals
			storedBuildingTransparency[inst] = inst.Transparency
			storedBuildingCanCollide[inst]   = inst.CanCollide
			storedBuildingCanQuery[inst]     = inst.CanQuery
			-- apply placement-friendly state
			inst.Transparency = 0.75
			inst.CanCollide   = false
			inst.CanQuery     = false
		end
	end)
end

local function SetBuildingsNoQuery(state: boolean)
	if not buildings then return end
	if buildingsNoQueryActive == state then return end
	buildingsNoQueryActive = state

	for _, inst in ipairs(buildings:GetDescendants()) do
		-- tag both parts and container models, in case your query layer checks either
		if inst:IsA("BasePart") or inst:IsA("Model") then
			-- pcall so we don't care if something is locked down / lacks attributes
			pcall(function()
				inst:SetAttribute("noquery", state)
			end)
		end
	end
end

task.spawn(function()
	local player = Players.LocalPlayer
	local plots = Workspace:WaitForChild("PlayerPlots")
	myPlot = plots:WaitForChild("Plot_" .. player.UserId)
	playerzones = myPlot:WaitForChild("PlayerZones")
	waterpipeszones = myPlot:WaitForChild("WaterPipeZones")
	powerlineszones = myPlot:WaitForChild("PowerLinesZones")
	buildings = myPlot:WaitForChild("Buildings")
	pipesfolder = myPlot:WaitForChild("Pipes")
	metroTunnelsFolder = myPlot:WaitForChild("MetroTunnels")
	
	metroTunnelsFolder = myPlot:FindFirstChild("MetroTunnels")
	if not metroTunnelsFolder then
		-- try a short timed wait first (optional)
		metroTunnelsFolder = myPlot:WaitForChild("MetroTunnels", 3)
	end

	-- if still nil after timeout, listen for when it appears
	if not metroTunnelsFolder then
		myPlot.ChildAdded:Connect(function(child)
			if child.Name == "MetroTunnels" and child:IsA("Folder") then
				metroTunnelsFolder = child
				-- if your UI was waiting to show tunnels, you can call:
				-- ShowMetroModels(metroTunnelsVisible)  -- re-apply desired state
			end
		end)
	end
	
	buildings.ChildAdded:Connect(function(child)
		if not buildingsNoQueryActive then return end
		for _, inst in ipairs(child:GetDescendants()) do
			if inst:IsA("BasePart") or inst:IsA("Model") then
				pcall(function()
					inst:SetAttribute("noquery", true)
				end)
			end
		end
		-- also tag the immediate child if relevant
		if child:IsA("BasePart") or child:IsA("Model") then
			pcall(function()
				child:SetAttribute("noquery", true)
			end)
		end
	end)
	
	playerzones.ChildAdded:Connect(function(Part)
		if not Part:IsA("BasePart") then return end
		if playerzonesVisible then
			Part.Transparency = 0.75
		else
			Part.Transparency = 1.0
		end
	end)
	waterpipeszones.ChildAdded:Connect(function(Part)
		if not Part:IsA("BasePart") then return end
		if waterpipeszonesVisible then
			Part.Transparency = 0.75
		else
			Part.Transparency = 1.0
		end
	end)
	powerlineszones.ChildAdded:Connect(function(Part)
		if not Part:IsA("BasePart") then return end
		if powerlineszonesVisible then
			Part.Transparency = 0.75
		else
			Part.Transparency = 1.0
		end
	end)
end)

local function findScreenGui(container, name)
	-- Return a ScreenGui named `name` under `container`, or nil.
	local obj = container:FindFirstChild(name)
	if obj and obj:IsA("ScreenGui") then
		return obj
	end
	if obj then
		-- If something else (e.g., Folder/StringValue) has that name, look inside it.
		local nested = obj:FindFirstChildWhichIsA("ScreenGui", true)
		if nested then return nested end
	end
	return nil
end

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local HasBusDepot = false
local HasAirport  = false
local HasMetro   = false
local BUS_DEPOT_GUI_NAME = "BusDepot"
local AIRPORT_GUI_NAME = "Airport"

local function OpenAirportGUI()
	local gui = PlayerGui:FindFirstChild(AIRPORT_GUI_NAME)
	if not gui or not gui:IsA("ScreenGui") then
		local template = ReplicatedStorage:FindFirstChild(AIRPORT_GUI_NAME)
			or game:GetService("StarterGui"):FindFirstChild(AIRPORT_GUI_NAME)
		if template and template:IsA("ScreenGui") then
			gui = template:Clone()
			gui.ResetOnSpawn = false
			gui.Parent = PlayerGui
		else
			warn("[BuildMenu] Airport ScreenGui not found.")
			return
		end
	end
	-- one-time init of Airport module inside the ScreenGui (so Exit button works)
	if not gui:GetAttribute("AirportInit") then
		local mod = gui:FindFirstChild("Airport")
		if mod and mod:IsA("ModuleScript") then
			local ok, api = pcall(require, mod)
			if ok and api and type(api.Init) == "function" then
				pcall(api.Init)
				gui:SetAttribute("AirportInit", true)
			end
		end
	end

	gui.Enabled = true
	local root = gui:FindFirstChildWhichIsA("Frame", true)
	if root then root.Visible = true end
end

local function CloseAirportGUI()
	local gui = PlayerGui:FindFirstChild(AIRPORT_GUI_NAME)
	if gui and gui:IsA("ScreenGui") then
		gui.Enabled = false
	end
end

local function ToggleAirportGUI(forceState)
	local gui = PlayerGui:FindFirstChild(AIRPORT_GUI_NAME)
	if not gui or not gui:IsA("ScreenGui") then
		if forceState == false then return end
		OpenAirportGUI()
		return
	end
	local wantOpen = (forceState ~= nil) and forceState or (not gui.Enabled)
	if wantOpen then OpenAirportGUI() else CloseAirportGUI() end
end

-- ==== Bus Depot GUI helpers (single source of truth) ====
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local BUS_DEPOT_GUI_NAME = "BusDepot"

local function OpenBusDepotGUI()
	-- If you really never destroy it, this could just be a FindFirstChild + Enabled=true.
	-- Leaving create-if-missing here so a stray Destroy() or testing doesn't wedge you.
	local gui = PlayerGui:FindFirstChild(BUS_DEPOT_GUI_NAME)
	if not gui or not gui:IsA("ScreenGui") then
		local template = ReplicatedStorage:FindFirstChild(BUS_DEPOT_GUI_NAME)
			or game:GetService("StarterGui"):FindFirstChild(BUS_DEPOT_GUI_NAME)
		if template and template:IsA("ScreenGui") then
			gui = template:Clone()
			gui.ResetOnSpawn = false
			gui.Parent = PlayerGui
		else
			warn("[BuildMenu] BusDepot ScreenGui not found.")
			return
		end
	end
	gui.Enabled = true

	-- If your exit button hides a root frame, make one visible again.
	local root = gui:FindFirstChildWhichIsA("Frame", true)
	if root then root.Visible = true end
end

local function CloseBusDepotGUI()
	local gui = PlayerGui:FindFirstChild(BUS_DEPOT_GUI_NAME)
	if gui and gui:IsA("ScreenGui") then
		gui.Enabled = false
	end
end

local function ToggleBusDepotGUI(forceState: boolean?)
	local gui = PlayerGui:FindFirstChild(BUS_DEPOT_GUI_NAME)

	-- If we don't have it and we were told to close, do nothing.
	if not gui or not gui:IsA("ScreenGui") then
		if forceState == false then return end
		-- Otherwise create it by opening.
		OpenBusDepotGUI()
		return
	end

	local wantOpen = (forceState ~= nil) and forceState or (not gui.Enabled)
	if wantOpen then OpenBusDepotGUI() else CloseBusDepotGUI() end
end


RE_ToggleBusDepotGui.OnClientEvent:Connect(function(forceState)
	print("[BuildMenu] RE_ToggleBusDepotGui received", forceState)
	ToggleBusDepotGUI(forceState)
end)

RE_ToggleAirportGui.OnClientEvent:Connect(function(forceState)
	ToggleAirportGUI(forceState)
end)

local function SetPlayerZonesVisible(State: boolean)
	if playerzones == nil then return end
	if playerzonesVisible == State then return end
	playerzonesVisible = State
	
	for _, Child in playerzones:GetChildren() do
		if not Child:IsA("BasePart") then continue end
		if playerzonesVisible then
			Child.Transparency = 0.75
		else
			Child.Transparency = 1.0
		end
	end
end

local function SetWaterPipesZonesVisible(State: boolean)
	if waterpipeszones == nil then return end
	if waterpipeszonesVisible == State then return end
	waterpipeszonesVisible = State

	for _, Child in waterpipeszones:GetChildren() do
		if not Child:IsA("BasePart") then continue end
		if waterpipeszonesVisible then
			Child.Transparency = 0.75
		else
			Child.Transparency = 1.0
		end
	end
end

local function SetPowerLinesZonesVisible(State: boolean)
	if powerlineszones == nil then return end
	if powerlineszonesVisible == State then return end
	powerlineszonesVisible = State

	for _, Child in powerlineszones:GetChildren() do
		if not Child:IsA("BasePart") then continue end
		if powerlineszonesVisible then
			Child.Transparency = 0.75
		else
			Child.Transparency = 1.0
		end
	end
end

local function ShowPipesModels(State: boolean)
	if not pipesfolder then return end
	if State then
		pipesfolder.Parent = myPlot
	else
		pipesfolder.Parent = nil
	end
end
ShowPipesModels(false)

local function ShowMetroModels(State: boolean)
	if not metroTunnelsFolder then return end
	if State then
		metroTunnelsFolder.Parent = myPlot
	else
		metroTunnelsFolder.Parent = nil
	end
end
ShowMetroModels(false)

local function ShowBuildingModels(State: boolean)
	if not buildings then return end
	
	if buildingVisible == State then return end
	buildingVisible = State
	
	if State then
		buildings.Parent = myPlot
	else
		buildings.Parent = nil
	end
end

local ZoneCategories = {
	Fire                   = { FireDept=true, FirePrecinct=true, FireStation=true },
	Education              = { MiddleSchool=true, Museum=true, NewsStation=true, PrivateSchool=true },
	Health                 = { CityHospital=true, LocalHospital=true, MajorHospital=true, SmallClinic=true },
	Landmark               = { Bank=true, CNTower=true, EiffelTower=true, EmpireStateBuilding=true,
		FerrisWheel=true, GasStation=true, ModernSkyscraper=true, NationalCapital=true,
		Obelisk=true, SpaceNeedle=true, StatueOfLiberty=true, TechOffice=true, WorldTradeCenter=true },
	Leisure                = { Church=true, Hotel=true, Mosque=true, MovieTheater=true, ShintoTemple=true },
	Police                 = { Courthouse=true, PoliceDept=true, PolicePrecinct=true, PoliceStation=true },
	Sports = { ArcheryRange=true, BasketballCourt=true, BasketballStadium=true,
		FootballStadium=true, GolfCourse=true, PublicPool=true,
		SkatePark=true, SoccerStadium=true, TennisCourt=true },
	Transport              = { Airport=true, BusDepot=true, MetroEntrance=true },
	Road = {Road = true, DirtRoad = true,Residential = true, Commercial = true, Industrial = true,ResDense    = true, CommDense  = true, IndusDense = true,},
	Power  = { CoalPowerPlant=true, GasPowerPlant=true, GeothermalPowerPlant=true,
		NuclearPowerPlant=true, SolarPanels=true, WindTurbine=true },

	Water                  = { WaterTower=true, WaterPlant=true, PurificationWaterPlant=true, MolecularWaterPlant=true },
}

-- 2) The default group that is always ON unless another category is active
local DefaultZoneTypes = {
	Residential     = true, Commercial   = true, Industrial   = true,
	ResDense        = true, CommDense    = true, IndusDense   = true,
}

-- 3) State holder
local _activeCategory -- nil = defaults shown
local _suppressSeen = false

-- 4) Core worker
local function _refreshCategoryVisibility()
	if not playerzones then return end
	if not UI.Enabled then
		for _, part in ipairs(playerzones:GetChildren()) do
			if part:IsA("BasePart") then
				part.Transparency = 1.0
			end
		end
		return
	end
	
	for _, part in ipairs(playerzones:GetChildren()) do
		if not part:IsA("BasePart") then continue end
		local zt = part:GetAttribute("ZoneType")
		if not zt then continue end

		local shouldShow
		if _activeCategory then
			-- show only the chosen category
			local map = ZoneCategories[_activeCategory]
			shouldShow = map and map[zt]
		else
			-- no category selected ⇒ show defaults
			shouldShow = DefaultZoneTypes[zt]
		end

		part.Transparency = shouldShow and 0.75 or 1.0
	end
end

-- 5) Public helper (toggle behaviour)
function BuildMenu.ShowZoneCategory(categoryName : string?)
	if categoryName and ZoneCategories[categoryName] then
		-- click same button twice to return to defaults
		if _activeCategory == categoryName then
			_activeCategory = nil     -- toggle off ⇒ revert to defaults
		else
			_activeCategory = categoryName
		end
	else
		_activeCategory = nil
	end
	_refreshCategoryVisibility()
end


function BuildMenu.ShowRangeVisualsOnly(selectedType)
	local player = Players.LocalPlayer
	local plot   = Workspace:FindFirstChild("PlayerPlots")
		and Workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId)
	if not plot then return end

	local zoneFolder = plot:FindFirstChild("PlayerZones")
	if not zoneFolder then return end

	for _, candidate in ipairs(zoneFolder:GetChildren()) do
		-- pick out the RangeVisuals by checking the Tier attribute
		if candidate:GetAttribute("Tier") then
			local isMatch = candidate:GetAttribute("ZoneType") == selectedType
			-- show matches…
			candidate.Transparency = isMatch and 0.3 or 1
			for _, desc in ipairs(candidate:GetDescendants()) do
				pcall(function() desc.Enabled = isMatch end)
			end
		end
	end
end

-- Helper Functions
local function UpdateLocks()
	-- guard the incoming level; never allow nil to propagate
	local playerLevel = tonumber(CachedLevel) or 0

	for itemID, Frame in pairs(FrameButtons) do
		local LevelCost = tonumber(BuildingLevelRequirement[itemID])
		if LevelCost ~= nil then
			local IsLocked = playerLevel < LevelCost

			-- These children can differ by template; find them safely.
			local locked = Frame:FindFirstChild("Locked")
			if locked then
				locked.Visible = IsLocked
			end

			local lvlLock = Frame:FindFirstChild("LevelLocked")
			if lvlLock then
				lvlLock.Visible = IsLocked
				-- If LevelLocked is/contains a TextLabel, show the level nicely.
				local asLabel = lvlLock:IsA("TextLabel") and lvlLock
					or lvlLock:FindFirstChildWhichIsA("TextLabel", true)
				if asLabel and IsLocked then
					asLabel.Text = "Lv. "..tostring(LevelCost)
				end
			end

			-- Optional preview bits; only set if present.
			local vp = Frame:FindFirstChild("ModelPreview")
			if vp and vp:IsA("ViewportFrame") then
				vp.ImageTransparency = IsLocked and 0.5 or 0.0
			end

			local img = Frame:FindFirstChild("ImageLabel")
			if img and img:IsA("ImageLabel") then
				img.ImageTransparency = IsLocked and 0.5 or 0.0
			end
		end
	end
end

local function UpdateBusDepotButton()
	local btn = FrameButtons["BusDepot"]
	if not btn then return end
	if btn.info and btn.info.itemName then
		btn.info.itemName.Text = HasBusDepot and "Bus Depot (Owned)" or "Bus Depot"
	end
end

local function UpdateAirportButton()
	local btn = FrameButtons["Airport"]
	if not btn then return end
	if btn.info and btn.info.itemName then
		btn.info.itemName.Text = HasAirport and "Airport (Owned)" or "Airport"
	end
end

local function UpdateMetroButton()
	local btn = FrameButtons["MetroEntrance"]
	if not btn then return end
	if btn.info and btn.info.itemName then
		btn.info.itemName.Text = HasMetro and "Metro (Owned)" or "Metro"
	end
end

local function CreateTabSection(SectionName: string, Choices) -- {itemname, price, image, modelref}
	local UISection = UI_TabChoicesContainer:Clone()
	UISection.Name = "TabSection_"..SectionName
	UISection.Visible = false

	local ChoiceTemplate = UISection.Template
	ChoiceTemplate.Visible = false	

	for _, Data in Choices do
		local Choice = ChoiceTemplate:Clone()
		Choice.Name = Data.itemName
		Choice.Visible = true
		Choice.info.itemName.Text = tostring(Data.itemName)
		
		local PrintedLangKeys = {}
		--Print langkey for now
		-- inside CreateTabSection, right after this line:
		Choice.info.itemName:SetAttribute("LangKey", tostring(Data.itemName))--Leave only this after lang key
		-- add this:
		local key = tostring(Data.itemName)
		if not PrintedLangKeys[key] then
			PrintedLangKeys[key] = true
			print("[LangKey]", key)
		end
		--Print langkey for now
		if Data.priceInRobux then
			Choice.info.price.Text = "..."
			task.spawn(function()
				Choice.info.price.Text = "\u{E002} ".. DevProducts.GetPrice(Data.priceInRobux)
			end)
			Choice.info.price.TextColor3 = Color3.fromRGB(255, 237, 99)
			Choice.FreeAmounts.Visible = true

			-- Mark Exclusive Locations
			local SaveFileData = PlayerDataController.GetSaveFileData()
			if SaveFileData and SaveFileData.exclusiveLocations[Data.priceInRobux] > 0 then
				Choice.FreeAmounts.Text = "x"..SaveFileData.exclusiveLocations[Data.priceInRobux]
			else
				Choice.FreeAmounts.Text = "x0"
			end
			
		elseif Data.price then
			Choice.info.price.Text = "$"..tostring(Abr.abbreviateNumber(Data.price))
		else
			Choice.info.price.Visible = false
		end

		if Data.image then
			Choice.ImageLabel.Image = Data.image
		end

		if Data.modelref then
			local VisualModel = Data.modelref:Clone()
			UtilityGUI.SetupViewportFrameForModelWithAttributes(Choice.ModelPreview, VisualModel)
		end

		if Data.onClick then
			SoundController.PlaySoundOnce("UI", "SmallClick")
			if Data.priceInRobux then
				Choice.MouseButton1Down:Connect(function()
					-- check if you own the exclusive building to place
					local SaveFileData = PlayerDataController.GetSaveFileData()
					if SaveFileData and SaveFileData.exclusiveLocations[Data.priceInRobux] > 0 then
						if Data.itemID then SetBuildingsTransparent(true) end
						Data.onClick()
					else
						local DevProductID = DevProducts.GetDevProductID(Data.itemID)
						MarketplaceService:PromptProductPurchase(Players.LocalPlayer, DevProductID)
					end
				end)
			else
				Choice.MouseButton1Down:Connect(function()
					if Data.itemID then SetBuildingsTransparent(true) end -- [ADDED]
					Data.onClick()
				end)
			end
		end
		
		if Data.itemID then
			--warn(Data.itemID, Data.itemName)
			local LevelCost = BuildingLevelRequirement[Data.itemID]
			if LevelCost then
				Choice.Locked.Visible = CachedLevel < LevelCost
				Choice.LevelLocked.Text = "Lv. "..LevelCost
			else
				warn("Module BalanceEconomy -> table Config.unlocksByLevel is missing this ID ("..Data.itemID..")")
				Choice.Locked.Visible = false
				Choice.LevelLocked.Visible = false
			end
		else
			Choice.Locked.Visible = false
			Choice.LevelLocked.Visible = false
		end

		UtilityGUI.VisualMouseInteraction(
			Choice, Choice.ModelPreview,
			TweenInfo.new(0.15),
			{ Size = UDim2.fromScale(1.25, 1.25) },
			{ Size = UDim2.fromScale(0.75, 0.75) }
		)
		UtilityGUI.VisualMouseInteraction(
			Choice, Choice.info,
			TweenInfo.new(0.15),
			{ Position = UDim2.fromScale(0.5, 0.8) }
		)
		UtilityGUI.VisualMouseInteraction(
			Choice, Choice.ImageLabel,
			TweenInfo.new(0.15),
			{ Size = UDim2.fromScale(1.25, 1.25) },
			{ Size = UDim2.fromScale(0.75, 0.75) }
		)
		UtilityGUI.VisualMouseInteraction(
			Choice, Choice.UIStroke,
			TweenInfo.new(0.15),
			{ Thickness = 4 },
			{ Thickness = 0 }
		)

		Choice.Parent = ChoiceTemplate.Parent

		-- always ensure a dot exists (works for concrete items and category buttons)
		local dot = ensureButtonNotif(Choice)

		if Data.itemID then
			-- concrete buildable item
			FrameButtons[Data.itemID] = Choice
			ItemToSection[Data.itemID] = SectionName

			-- if this item was already pending from an earlier FUS, show it now
			if PendingByItem[Data.itemID] then
				dot.Visible = true
				SectionHasPending[SectionName] = true  -- keep hierarchy accurate
			end
		else
			-- hub/category entry that navigates to another section
			local target = (ITEMNAME_TO_SECTION[Data.itemName] or Data.itemName)
			CategoryButtonForSection[target] = Choice

			-- if the whole section is pending, show the hub dot immediately
			if SectionHasPending[target] then
				dot.Visible = true
			end
		end
	end

	UISection.Parent = UI_TabChoicesContainer.Parent

	TabSections[SectionName] = UISection
end


-- Module Functions
function BuildMenu.SetServicesTabNotification(State: boolean)
	UI_Tab_Services.notification.Visible = State
end

function BuildMenu.SetSupplyTabNotification(State: boolean)
	UI_Tab_Supply.notification.Visible = State
end

function BuildMenu.SetTranspotTabNotification(State: boolean)
	UI_Tab_Transpot.notification.Visible = State
end

function BuildMenu.SetZonesTabNotification(State: boolean)
	UI_Tab_Zones.notification.Visible = State
end

function BuildMenu.SetTab(TabName: string)
	-- no-op if we're already on it
	if CurrentTabName == TabName then return end

	local isMajor = (TabName == "Services" or TabName == "Supply" or TabName == "Transport" or TabName == "Zones")
	local hasConcrete = TabSections[TabName] ~= nil  -- section actually has buttons

	if not isMajor and not hasConcrete then
		warn(("[BuildMenu] SetTab('%s'): no such section"):format(tostring(TabName)))
		return
	end

	CurrentTabName = TabName

	-- show only the target section
	for sectionName, uiSection in pairs(TabSections) do
		uiSection.Visible = (sectionName == TabName)
	end

	--BuildMenu.ShowZoneCategory(TabName)
	
	if UI.Enabled then
		BuildMenu.ShowZoneCategory(TabName)
	else
		_activeCategory = nil
		_refreshCategoryVisibility()  -- ensures everything stays hidden
	end

	-- major highlight
	if isMajor then
		MajorCurrentTabName = TabName
		UI.main.tabs.services.Background.BackgroundColor3  = (MajorCurrentTabName == "Services")  and Color3.fromRGB(100,100,100) or Color3.fromRGB(0,0,0)
		UI.main.tabs.supply.Background.BackgroundColor3    = (MajorCurrentTabName == "Supply")    and Color3.fromRGB(100,100,100) or Color3.fromRGB(0,0,0)
		UI.main.tabs.transport.Background.BackgroundColor3 = (MajorCurrentTabName == "Transport") and Color3.fromRGB(100,100,100) or Color3.fromRGB(0,0,0)
		UI.main.tabs.zones.Background.BackgroundColor3     = (MajorCurrentTabName == "Zones")     and Color3.fromRGB(100,100,100) or Color3.fromRGB(0,0,0)
	end

	-- world overlay toggles (unchanged)
	if TabName == "Water" then
		SetBuildingsTransparent(true)
	else
		SetBuildingsTransparent(false)
	end
	SetPowerLinesZonesVisible(TabName == "Power")
	SetWaterPipesZonesVisible(TabName == "Water")
	ShowPipesModels(TabName == "Water")
	ShowMetroModels(false)
	SetBuildingsNoQuery(TabName == "Power")
	if TabName == "Road" then
		SetPlayerZonesVisible(true)
	end

	-- CLEAR NOTIFICATIONS:
	-- If this tab is a concrete section (has real item buttons), mark it seen.
	-- This includes major tabs that are also concrete (e.g., Transport, Zones).
	if not _suppressSeen and hasConcrete and typeof(markSectionSeen) == "function" then
		markSectionSeen(TabName)

		local hubBtn = CategoryButtonForSection[TabName]
		if hubBtn then
			local dot = hubBtn:FindFirstChild("notification")
			if dot then dot.Visible = false end
		end
	end

	if typeof(_refreshCategoryVisibility) == "function" then
		_refreshCategoryVisibility()
	end
end

local BE_DisableBuildMode = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents"):WaitForChild("DisableBuildMode")

function BuildMenu.OnShow()
	if UI.Enabled then return end
	UI.Enabled = true
	SetPlayerZonesVisible(true)
	_activeCategory = nil  -- reset
	_refreshCategoryVisibility()
	
	game:GetService("GamepadService"):EnableGamepadCursor(nil)
end

function BuildMenu.OnHide()
	if not UI.Enabled then return end
	UI.Enabled = false
	BE_DisableBuildMode:Fire()
	SetPlayerZonesVisible(false)
	SetPowerLinesZonesVisible(false)
	SetWaterPipesZonesVisible(false)
	ShowPipesModels(false)
	ShowMetroModels(false)
	ShowBuildingModels(true)
	SetBuildingsNoQuery(false)
	SetBuildingsTransparent(false)
	_activeCategory = nil

	_suppressSeen = true
	BuildMenu.SetTab("Transport")
	_suppressSeen = false
	for _, UISection in pairs(TabSections) do
		UISection.CanvasPosition = Vector2.new(0, 0)
	end
	
	game:GetService("GamepadService"):DisableGamepadCursor()
end

function BuildMenu.Toggle()
	if UI.Enabled then
		BuildMenu.OnHide()
	else
		BuildMenu.OnShow()
	end
end

FUS.OnClientEvent:Connect(function(unlockStatus)
	-- 1) Persist full unlock map locally (as you already did)
	for k, v in pairs(unlockStatus) do
		UnlockedTypes[k] = v
	end

	-- 2) Apply lock/visual state to all visible buttons (unchanged)
	for _, UISection in pairs(TabSections) do
		for _, btn in ipairs(UISection:GetChildren()) do
			if btn:IsA("Frame") and btn.info and btn.info.itemName then
				local itemType = btn.Name
				local unlocked = UnlockedTypes[itemType]

				if btn.ModelPreview then
					btn.ModelPreview.Visible = unlocked
				end
				if btn.LockedIcon then
					btn.LockedIcon.Visible = not unlocked
				end

				btn.Active = unlocked
				btn.BackgroundTransparency = unlocked and 0 or 0.5
			end
		end
	end
	UpdateBusDepotButton()
	UpdateAirportButton()
	-- 3) Detect newly gained features (false -> true) and pop the UnlockGUI
	local gained = {}

	-- First-sync guard: if PrevUnlocks is empty, treat this as baseline and don't notify
	local firstSync = (next(PrevUnlocks) == nil)
	if firstSync then
		PrevUnlocks = shallowCopy(unlockStatus)
	else
		for feature, now in pairs(unlockStatus) do
			local before = PrevUnlocks[feature] == true
			if now and not before then
				table.insert(gained, feature)
			end
		end
		PrevUnlocks = shallowCopy(unlockStatus)
	end

	if #gained > 0 then
		-- Light per-button dots and mark sections as pending
		for _, feature in ipairs(gained) do
			PendingByItem[feature] = true

			-- per-item button dot
			local btn = FrameButtons[feature]
			if btn then
				ensureButtonNotif(btn).Visible = true
			end

			-- record the section and light its hub button
			local section = ItemToSection[feature]
			if section then
				SectionHasPending[section] = true

				local hubBtn = CategoryButtonForSection[section]
				if hubBtn then
					ensureButtonNotif(hubBtn).Visible = true
				end
			end
		end
		recomputeTopTabBadges()

		-- Pop the unlock modal (icons/models already handled)
		openUnlockModal(gained)
	end
end)

if RE_AirSupportStatus then
	RE_AirSupportStatus.OnClientEvent:Connect(function(isUnlocked: boolean)
		HasAirport = isUnlocked
		UpdateAirportButton() -- NEW
		-- optional: ToggleAirportGUI(isUnlocked)
	end)
end

if RE_MetroSupportStatus then
	RE_MetroSupportStatus.OnClientEvent:Connect(function(isUnlocked: boolean)
		HasMetro = isUnlocked
		UpdateMetroButton()
	end)
end

RE_BusSupportStatus.OnClientEvent:Connect(function(isUnlocked: boolean)
	HasBusDepot = isUnlocked
	UpdateBusDepotButton()
	if isUnlocked then
		-- auto-open the GUI when the first depot is placed
		OpenBusDepotGUI()
	else
		-- close GUI and allow placing another if last depot removed
		CloseBusDepotGUI()
	end
end)



function BuildMenu.Init()
	
	-- Place
	UI_PlaceButton.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		ReplicatedStorage.Events.BindableEvents.MobileClick:Fire()
	end)
	UI_PlaceButton.Visible = false
	if UserInputService.TouchEnabled then
		task.spawn(function()
			local CardinalFolder = workspace.PlayerPlots.GridParts

			UI_PlaceButton.Visible = #CardinalFolder:GetChildren() > 0
			CardinalFolder.ChildAdded:Connect(function(Child)
				if #CardinalFolder:GetChildren() > 0 then 
					UI_PlaceButton.Visible = true
				else
					UI_PlaceButton.Visible = false
				end
			end)
			CardinalFolder.ChildRemoved:Connect(function(Child)
				if #CardinalFolder:GetChildren() > 0 then 
					UI_PlaceButton.Visible = true
				else
					UI_PlaceButton.Visible = false
				end
			end)
		end)
	end
	
	--UI.main.container.TabChoices.Visible = true
	
	UserInputService.InputBegan:Connect(function(InputObject, GameProcessedEvent)
		if not UI.Enabled then return end
		if GameProcessedEvent then return end
			
		if InputObject.KeyCode == Enum.KeyCode.ButtonB then
			SoundController.PlaySoundOnce("UI", "SmallClick")
			BuildMenu.OnHide()
			
			-- cycle categories
		elseif InputObject.KeyCode == Enum.KeyCode.ButtonL2 then
			if MajorCurrentTabName == "Transport" then
				BuildMenu.SetTab("Supply")

			elseif MajorCurrentTabName == "Zones" then
				BuildMenu.SetTab("Transport")

			elseif MajorCurrentTabName == "Services" then
				BuildMenu.SetTab("Zones")

			elseif MajorCurrentTabName == "Supply" then
				BuildMenu.SetTab("Services")
			end
			
		elseif InputObject.KeyCode == Enum.KeyCode.ButtonR2 then
			if MajorCurrentTabName == "Transport" then
				BuildMenu.SetTab("Zones")
				
			elseif MajorCurrentTabName == "Zones" then
				BuildMenu.SetTab("Services")
				
			elseif MajorCurrentTabName == "Services" then
				BuildMenu.SetTab("Supply")
				
			elseif MajorCurrentTabName == "Supply" then
				BuildMenu.SetTab("Transport")
			end
		end
	end)
	
	-- Scrolling Buttons
	RunService.Heartbeat:Connect(function(Step)
		if not UI.Enabled then return end

		local UISection = TabSections[CurrentTabName]
		if not UISection then return end

		if UI_TabScroll_Left.GuiState == Enum.GuiState.Press and UI_TabScroll_Right.GuiState ~= Enum.GuiState.Press then
			UISection.CanvasPosition -= Vector2.new(Step * BUTTON_SCROLL_SPEED, 0)

		elseif UI_TabScroll_Left.GuiState ~= Enum.GuiState.Press and UI_TabScroll_Right.GuiState == Enum.GuiState.Press then
			UISection.CanvasPosition += Vector2.new(Step * BUTTON_SCROLL_SPEED, 0)
		end
	end)

	-- Notifications
	BuildMenu.SetServicesTabNotification(false)
	BuildMenu.SetSupplyTabNotification(false)
	BuildMenu.SetTranspotTabNotification(false)
	BuildMenu.SetZonesTabNotification(false)
	recomputeTopTabBadges()

	-- Create Tab Section
	CreateTabSection("Transport", {
		{
			itemName = "Road",
			price = nil,
			image = "rbxassetid://96596073659362",
			--modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.CommDense.Default.Medium.HComM1,
			onClick = function()
				BuildMenu.SetTab("Road")
			end,
		},
		{
			itemID = "BusDepot",
			itemName = "Bus Depot",
			price = nil,
			image = "rbxassetid://72399175872104",
			onClick = function()
				if HasBusDepot then
					ToggleBusDepotGUI() -- unified open/close for the GUI
					SoundController.PlaySoundOnce("UI", "SmallClick")
					return
				end
				selectZoneEvent:FireServer("BusDepot")
				BuildMenu.ShowRangeVisualsOnly("BusDepot")
			end,
		},
		{
			itemID = "MetroEntrance",
			itemName = "Metro",
			price = nil,
			image = "rbxassetid://85773891248333",
			--modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.CommDense.Default.Medium.HComM1,
			onClick = function()
				ShowMetroModels(false)
				if HasMetro then
					-- owned: go to linear infrastructure placement mode
					ShowMetroModels(true)                    -- <<< SHOW TUNNELS NOW (like pipes)
					selectZoneEvent:FireServer("MetroTunnel")
					-- (no range visuals for linear infra)
				else
					-- not owned yet: place the unique Metro entrance
					ShowMetroModels(false)                   -- ensure hidden until owned
					selectZoneEvent:FireServer("MetroEntrance")
					BuildMenu.ShowRangeVisualsOnly("MetroEntrance")
				end
			end,
		},
		{
			itemID = "Airport",
			itemName = "Airport",
			price = nil,
			image = "rbxassetid://100366195302554",
			onClick = function()
				ShowMetroModels(false)
				if HasAirport then
					ToggleAirportGUI()  -- unified open/close
					SoundController.PlaySoundOnce("UI", "SmallClick")
					return
				end
				selectZoneEvent:FireServer("Airport")
				BuildMenu.ShowRangeVisualsOnly("Airport")
			end,
		},

		-- Train: rbxassetid://83218584677943
	})
	CreateTabSection("Zones", {
		{
			itemID = "Residential",
			itemName = "Residential Zone",
			price = BalanceEconomy.costPerGrid.Residential,
			image = "rbxassetid://94434560138213",
			--modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.CommDense.Default.Medium.HComM1,
			onClick = function()
				selectZoneEvent:FireServer("Residential")
			end,
		},
		{
			itemID = "Commercial",
			itemName = "Commercial Zone",
			price = BalanceEconomy.costPerGrid.Commercial,
			image = "rbxassetid://80804212045512",
			--modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.CommDense.Default.Medium.HComM1,
			onClick = function()
				selectZoneEvent:FireServer("Commercial")
			end,
		},
		{
			itemID = "Industrial",
			itemName = "Industrial Zone",
			price = BalanceEconomy.costPerGrid.Industrial,
			image = "rbxassetid://81164152585346",
			--modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.CommDense.Default.Medium.HComM1,
			onClick = function()
				selectZoneEvent:FireServer("Industrial")
			end,
		},
		{
			itemID = "ResDense",
			itemName = "Dense Residential Zone",
			price = BalanceEconomy.costPerGrid.ResDense,
			image = "rbxassetid://111951665644294",
			--modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.CommDense.Default.Medium.HComM1,
			onClick = function()
				selectZoneEvent:FireServer("ResDense")
			end,
		},
		{
			itemID = "CommDense",
			itemName = "Dense Commercial Zone",
			price = BalanceEconomy.costPerGrid.CommDense,
			image = "rbxassetid://133436787771849",
			--modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.CommDense.Default.Medium.HComM1,
			onClick = function()
				selectZoneEvent:FireServer("CommDense")
			end,
		},
		{
			itemID = "IndusDense",
			itemName = "Dense Industrial Zone",
			price = BalanceEconomy.costPerGrid.IndusDense,
			image = "rbxassetid://139640185589881",
			--modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.CommDense.Default.Medium.HComM1,
			onClick = function()
				selectZoneEvent:FireServer("IndusDense")
			end,
		},
	})
	CreateTabSection("Services", {
		{
			itemName = "Leisure",
			image = "rbxassetid://113537788739611",
			--modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.CommDense.Default.Medium.HComM1,
			onClick = function()
				BuildMenu.SetTab("Leisure")
			end,
		},
		{
			itemName = "Fire Dept",
			image = "rbxassetid://116690108033034",
			--modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.CommDense.Default.Medium.HComM1,
			onClick = function()
				BuildMenu.SetTab("Fire")
			end,
		},
		{
			itemName = "Police",
			image = "rbxassetid://138433123584716",
			--modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.CommDense.Default.Medium.HComM1,
			onClick = function()
				BuildMenu.SetTab("Police")
			end,
		},
		{
			itemName = "Health",
			image = "rbxassetid://133504700689023",
			--modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.CommDense.Default.Medium.HComM1,
			onClick = function()
				BuildMenu.SetTab("Health")
			end,
		},
		{
			itemName = "Education",
			image = "rbxassetid://134842512535450",
			--modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.CommDense.Default.Medium.HComM1,
			onClick = function()
				BuildMenu.SetTab("Education")
			end,
		},
		{
			itemName = "Sports",
			image = "rbxassetid://100131265691612",
			--modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.CommDense.Default.Medium.HComM1,
			onClick = function()
				BuildMenu.SetTab("Sports")
			end,
		},
		{
			itemName = "Landmarks",
			image = "rbxassetid://120327423932825",
			--modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.CommDense.Default.Medium.HComM1,
			onClick = function()
				BuildMenu.SetTab("Landmarks")
			end,
		},
	})
	CreateTabSection("Supply", {
		{
			itemName = "Power",
			image = "rbxassetid://82323091054475",
			--modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.CommDense.Default.Medium.HComM1,
			onClick = function()
				BuildMenu.SetTab("Power")
			end,
		},
		{
			itemName = "Water",
			image = "rbxassetid://88752537536614",
			--modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.CommDense.Default.Medium.HComM1,
			onClick = function()
				BuildMenu.SetTab("Water")
			end,
		},
		-- garbage rbxassetid://117322815175246
		-- graves rbxassetid://118319710170855
	}) 

	CreateTabSection("Education", {
		{
			itemID = "PrivateSchool",
			itemName = "PrivateSchool",
			price = BalanceEconomy.costPerGrid.PrivateSchool,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Education["Private School"],
			onClick = function()
				selectZoneEvent:FireServer("PrivateSchool")
				BuildMenu.ShowRangeVisualsOnly("PrivateSchool")
			end,
		},
		{
			itemID = "MiddleSchool",
			itemName = "MiddleSchool",
			price = BalanceEconomy.costPerGrid.MiddleSchool,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Education["Middle School"],
			onClick = function()
				selectZoneEvent:FireServer("MiddleSchool")
				BuildMenu.ShowRangeVisualsOnly("MiddleSchool")
			end,
		},
		{
			itemID = "NewsStation",
			itemName = "NewsStation",
			price = BalanceEconomy.costPerGrid.NewsStation,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Education["News Station"],
			onClick = function()
				selectZoneEvent:FireServer("NewsStation")
				BuildMenu.ShowRangeVisualsOnly("NewsStation")
			end,
		},
		{
			itemID = "Museum",
			itemName = "Museum",
			priceInRobux = "Museum",
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Education.Museum,
			onClick = function()
				selectZoneEvent:FireServer("Museum")
				BuildMenu.ShowRangeVisualsOnly("Museum")
			end,
		},
	})
	CreateTabSection("Fire", {
		{
			itemID = "FireDept",
			itemName = "Fire Depth",
			price = BalanceEconomy.costPerGrid.FireDept,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Fire.FireDept,
			onClick = function()
				selectZoneEvent:FireServer("FireDept")
				BuildMenu.ShowRangeVisualsOnly("FireDept")
			end,
		},
		{
			itemID = "FireStation",
			itemName = "Fire Station",
			price = BalanceEconomy.costPerGrid.FireStation,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Fire.FireStation,
			onClick = function()
				selectZoneEvent:FireServer("FireStation")
				BuildMenu.ShowRangeVisualsOnly("FireStation")
			end,
		},
		{
			itemID = "FirePrecinct",
			itemName = "Fire Precinct",
			priceInRobux = "FirePrecinct",
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Fire.FirePrecinct,
			onClick = function()
				selectZoneEvent:FireServer("FirePrecinct")
				BuildMenu.ShowRangeVisualsOnly("FirePrecinct")
			end,
		},
	})
	CreateTabSection("Health", {
		{
			itemID = "SmallClinic",
			itemName = "Small Clinic",
			price = BalanceEconomy.costPerGrid.SmallClinic,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Health["Small Clinic"],
			onClick = function()
				selectZoneEvent:FireServer("SmallClinic")
				BuildMenu.ShowRangeVisualsOnly("SmallClinic")
			end,
		},
		{
			itemID = "LocalHospital",
			itemName = "Local Hospital",
			price = BalanceEconomy.costPerGrid.LocalHospital,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Health["Local Hospital"],
			onClick = function()
				selectZoneEvent:FireServer("LocalHospital")
				BuildMenu.ShowRangeVisualsOnly("LocalHospital")
			end,
		},
		{
			itemID = "CityHospital",
			itemName = "City Hospital",
			price = BalanceEconomy.costPerGrid.CityHospital,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Health["City Hospital"],
			onClick = function()
				selectZoneEvent:FireServer("CityHospital")
				BuildMenu.ShowRangeVisualsOnly("CityHospital")
			end,
		},
		{
			itemID = "MajorHospital",
			itemName = "Major Hospital",
			priceInRobux = "MajorHospital",
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Health["Major Hospital"],
			onClick = function()
				selectZoneEvent:FireServer("MajorHospital")
				BuildMenu.ShowRangeVisualsOnly("MajorHospital")
			end,
		},
	})
	CreateTabSection("Landmarks", {
		{
			itemID = "FerrisWheel",
			itemName = "Ferris Wheel",
			price = BalanceEconomy.costPerGrid.FerrisWheel,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Landmark["Ferris Wheel"],
			onClick = function()
				selectZoneEvent:FireServer("FerrisWheel")
				BuildMenu.ShowRangeVisualsOnly("FerrisWheel")
			end,
		},
		{
			itemID = "GasStation",
			itemName = "Gas Station",
			price = BalanceEconomy.costPerGrid.GasStation,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Landmark["Gas Station"],
			onClick = function()
				selectZoneEvent:FireServer("GasStation")
				BuildMenu.ShowRangeVisualsOnly("GasStation")
			end,
		},
		{
			itemID = "Bank",
			itemName = "Bank",
			price = BalanceEconomy.costPerGrid.Bank,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Landmark.Bank,
			onClick = function()
				selectZoneEvent:FireServer("Bank")
				BuildMenu.ShowRangeVisualsOnly("Bank")
			end,
		},
		{
			itemID = "TechOffice",
			itemName = "Tech Office",
			price = BalanceEconomy.costPerGrid.TechOffice,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Landmark["Tech Office"],
			onClick = function()
				selectZoneEvent:FireServer("TechOffice")
				BuildMenu.ShowRangeVisualsOnly("TechOffice")
			end,
		},
		{
			itemID = "NationalCapital",
			itemName = "National Capital",
			price = BalanceEconomy.costPerGrid.NationalCapital,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Landmark["National Capital"],
			onClick = function()
				selectZoneEvent:FireServer("NationalCapital")
				BuildMenu.ShowRangeVisualsOnly("NationalCapital")
			end,
		},
		{
			itemID = "Obelisk",
			itemName = "Obelisk",
			price = BalanceEconomy.costPerGrid.Obelisk,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Landmark["Obelisk"],
			onClick = function()
				selectZoneEvent:FireServer("Obelisk")
				BuildMenu.ShowRangeVisualsOnly("Obelisk")
			end,
		},
		{
			itemID = "ModernSkyscraper",
			itemName = "Modern Skyscraper",
			price = BalanceEconomy.costPerGrid.ModernSkyscraper,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Landmark["Modern Skyscraper"],
			onClick = function()
				selectZoneEvent:FireServer("ModernSkyscraper")
				BuildMenu.ShowRangeVisualsOnly("ModernSkyscraper")
			end,
		},
		{
			itemID = "EmpireStateBuilding",
			itemName = "Empire State Building",
			price = BalanceEconomy.costPerGrid.EmpireStateBuilding,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Landmark["Empire State Building"],
			onClick = function()
				selectZoneEvent:FireServer("EmpireStateBuilding")
				BuildMenu.ShowRangeVisualsOnly("EmpireStateBuilding")
			end,
		},
		{
			itemID = "SpaceNeedle",
			itemName = "Space Needle",
			price = BalanceEconomy.costPerGrid.SpaceNeedle,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Landmark["Space Needle"],
			onClick = function()
				selectZoneEvent:FireServer("SpaceNeedle")
				BuildMenu.ShowRangeVisualsOnly("SpaceNeedle")
			end,
		},
		{
			itemID = "WorldTradeCenter",
			itemName = "World Trade Center",
			price = BalanceEconomy.costPerGrid.WorldTradeCenter,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Landmark["World Trade Center"],
			onClick = function()
				selectZoneEvent:FireServer("WorldTradeCenter")
				BuildMenu.ShowRangeVisualsOnly("WorldTradeCenter")
			end,
		},
		{
			itemID = "CNTower",
			itemName = "CN Tower",
			price = BalanceEconomy.costPerGrid.CNTower,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Landmark["CN Tower"],
			onClick = function()
				selectZoneEvent:FireServer("CNTower")
				BuildMenu.ShowRangeVisualsOnly("CNTower")
			end,
		},
		{
			itemID = "StatueOfLiberty",
			itemName = "Statue of Liberty",
			--price = BalanceEconomy.costPerGrid.StatueOfLiberty,
			priceInRobux = "StatueOfLiberty",
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Landmark["Statue Of Liberty"],
			onClick = function()
				selectZoneEvent:FireServer("StatueOfLiberty")
				BuildMenu.ShowRangeVisualsOnly("StatueOfLiberty")
			end,
		},
		{
			itemID = "EiffelTower",
			itemName = "Eiffel Tower",
			priceInRobux = "EiffelTower",
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Landmark["Eiffel Tower"],
			onClick = function()
				selectZoneEvent:FireServer("EiffelTower")
				BuildMenu.ShowRangeVisualsOnly("EiffelTower")
			end,
		},
	})
	CreateTabSection("Leisure", {
		{
			itemID = "Church",
			itemName = "Church",
			price = BalanceEconomy.costPerGrid.Church,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Leisure["Church"],
			onClick = function()
				selectZoneEvent:FireServer("Church")
				BuildMenu.ShowRangeVisualsOnly("Church")
			end,
		},
		{
			itemID = "Mosque",
			itemName = "Mosque",
			price = BalanceEconomy.costPerGrid.Mosque,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Leisure["Mosque"],
			onClick = function()
				selectZoneEvent:FireServer("Mosque")
				BuildMenu.ShowRangeVisualsOnly("Mosque")
			end,
		},
		{
			itemID = "ShintoTemple",
			itemName = "Shinto Temple",
			price = BalanceEconomy.costPerGrid.ShintoTemple,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Leisure["Shinto Temple"],
			onClick = function()
				selectZoneEvent:FireServer("ShintoTemple")
				BuildMenu.ShowRangeVisualsOnly("ShintoTemple")
			end,
		},
		{
			itemID = "HinduTemple",
			itemName = "Hindu Temple",
			price = BalanceEconomy.costPerGrid.HinduTemple,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Leisure["Hindu Temple"],
			onClick = function()
				selectZoneEvent:FireServer("HinduTemple")
				BuildMenu.ShowRangeVisualsOnly("HinduTemple")
			end,
		},
		{
			itemID = "BuddhaStatue",
			itemName = "Buddha Statue",
			price = BalanceEconomy.costPerGrid.BuddhaStatue,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Leisure["Buddha Statue"],
			onClick = function()
				selectZoneEvent:FireServer("BuddhaStatue")
				BuildMenu.ShowRangeVisualsOnly("BuddhaStatue")
			end,
		},
		{
			itemID = "Hotel",
			itemName = "Hotel",
			price = BalanceEconomy.costPerGrid.Hotel,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Leisure["Hotel"],
			onClick = function()
				selectZoneEvent:FireServer("Hotel")
				BuildMenu.ShowRangeVisualsOnly("Hotel")
			end,
		},
		{
			itemID = "MovieTheater",
			itemName = "Movie Theatre",
			price = BalanceEconomy.costPerGrid.MovieTheater,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Leisure["Movie Theater"],
			onClick = function()
				selectZoneEvent:FireServer("MovieTheater")
				BuildMenu.ShowRangeVisualsOnly("MovieTheater")
			end,
		},
	})
	CreateTabSection("Police", {
		{
			itemID = "PoliceDept",
			itemName = "Police Dept",
			price = BalanceEconomy.costPerGrid.PoliceDept,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Police["Police Dept"],
			onClick = function()
				selectZoneEvent:FireServer("PoliceDept")
				BuildMenu.ShowRangeVisualsOnly("PoliceDept")
			end,
		},
		{
			itemID = "PoliceStation",
			itemName = "Police Station",
			price = BalanceEconomy.costPerGrid.PoliceStation,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Police["Police Station"],
			onClick = function()
				selectZoneEvent:FireServer("PoliceStation")
				BuildMenu.ShowRangeVisualsOnly("PoliceStation")
			end,
		},
		{
			itemID = "PolicePrecinct",
			itemName = "PolicePrecinct",
			priceInRobux = "PolicePrecinct",
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Police["Police Precinct"],
			onClick = function()
				selectZoneEvent:FireServer("PolicePrecinct")
				BuildMenu.ShowRangeVisualsOnly("PolicePrecinct")
			end,
		},
		{
			itemID = "Courthouse",
			itemName = "Courthouse",
			price = BalanceEconomy.costPerGrid.Courthouse,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Police["Courthouse"],
			onClick = function()
				selectZoneEvent:FireServer("Courthouse")
				BuildMenu.ShowRangeVisualsOnly("Courthouse")
			end,
		},
	})
	CreateTabSection("Power", {
		{
			itemID = "PowerLines",
			itemName = "Power Lines",
			price = BalanceEconomy.costPerGrid.PowerLines,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Power.Default.Decorations.PowerLines,
			onClick = function()
				selectZoneEvent:FireServer("PowerLines")
			end,
		},
		{
			itemID = "WindTurbine",
			itemName = "Wind Turbine",
			price = BalanceEconomy.costPerGrid.WindTurbine,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Power["Wind Turbine"],
			onClick = function()
				selectZoneEvent:FireServer("WindTurbine")
				BuildMenu.ShowRangeVisualsOnly("WindTurbine")
			end,
		},
		{
			itemID = "SolarPanels",
			itemName = "Solar Panels",
			price = BalanceEconomy.costPerGrid.SolarPanels,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Power["Solar Panels"],
			onClick = function()
				selectZoneEvent:FireServer("SolarPanels")
				BuildMenu.ShowRangeVisualsOnly("SolarPanels")
			end,
		},
		{
			itemID = "CoalPowerPlant",
			itemName = "Coal Power Plant",
			price = BalanceEconomy.costPerGrid.CoalPowerPlant,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Power["Coal Power Plant"],
			onClick = function()
				selectZoneEvent:FireServer("CoalPowerPlant")
				BuildMenu.ShowRangeVisualsOnly("CoalPowerPlant")
			end,
		},
		{
			itemID = "GasPowerPlant",
			itemName = "Gas Power Plant",
			price = BalanceEconomy.costPerGrid.GasPowerPlant,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Power["Gas Power Plant"],
			onClick = function()
				selectZoneEvent:FireServer("GasPowerPlant")
				BuildMenu.ShowRangeVisualsOnly("GasPowerPlant")
			end,
		},
		{
			itemID = "GeothermalPowerPlant",
			itemName = "Geothermal Power Plant",
			price = BalanceEconomy.costPerGrid.GeothermalPowerPlant,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Power["Geothermal Power Plant"],
			onClick = function()
				selectZoneEvent:FireServer("GeothermalPowerPlant")
			end,
		},
		{
			itemID = "NuclearPowerPlant",
			itemName = "Nuclear Power Plant",
			priceInRobux = "NuclearPowerPlant",
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Power["Nuclear Power Plant"],
			onClick = function()
				selectZoneEvent:FireServer("NuclearPowerPlant")
			end,
		},
	})
	CreateTabSection("Road", {
		{
			itemID = "DirtRoad",
			itemName = "Dirt Road",
			price = BalanceEconomy.costPerGrid.DirtRoad,
			image = "rbxassetid://96596073659362",
			--modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Power["Power Line"],
			onClick = function()
				selectZoneEvent:FireServer("DirtRoad")
				
			end,
		},
	})
	CreateTabSection("Sports", {
		{
			itemID = "SkatePark",
			itemName = "Skate Park",
			price = BalanceEconomy.costPerGrid.SkatePark,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Sports["Skate Park"],
			onClick = function()
				selectZoneEvent:FireServer("SkatePark")
				BuildMenu.ShowRangeVisualsOnly("SkatePark")
			end,
		},
		{
			itemID = "TennisCourt",
			itemName = "Tennis Court",
			price = BalanceEconomy.costPerGrid.TennisCourt,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Sports["Tennis Court"],
			onClick = function()
				selectZoneEvent:FireServer("TennisCourt")
				BuildMenu.ShowRangeVisualsOnly("TennisCourt")
			end,
		},
		{
			itemID = "PublicPool",
			itemName = "Public Pool",
			price = BalanceEconomy.costPerGrid.PublicPool,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Sports["Public Pool"],
			onClick = function()
				selectZoneEvent:FireServer("PublicPool")
				BuildMenu.ShowRangeVisualsOnly("PublicPool")
			end,
		},
		{
			itemID = "ArcheryRange",
			itemName = "Archery Range",
			price = BalanceEconomy.costPerGrid.ArcheryRange,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Sports["Archery Range"],
			onClick = function()
				selectZoneEvent:FireServer("ArcheryRange")
				BuildMenu.ShowRangeVisualsOnly("ArcheryRange")
			end,
		},
		{
			itemID = "BasketballCourt",
			itemName = "Basketball Court",
			price = BalanceEconomy.costPerGrid.BasketballCourt,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Sports["Basketball Court"],
			onClick = function()
				selectZoneEvent:FireServer("BasketballCourt")
				BuildMenu.ShowRangeVisualsOnly("BasketballCourt")
			end,
		},
		{
			itemID = "GolfCourse",
			itemName = "Golf Course",
			price = BalanceEconomy.costPerGrid.GolfCourse,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Sports["Golf Course"],
			onClick = function()
				selectZoneEvent:FireServer("GolfCourse")
				BuildMenu.ShowRangeVisualsOnly("GolfCourse")
			end,
		},
		{
			itemID = "SoccerStadium",
			itemName = "Soccer Stadium",
			price = BalanceEconomy.costPerGrid.SoccerStadium,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Sports["Soccer Stadium"],
			onClick = function()
				selectZoneEvent:FireServer("SoccerStadium")
				BuildMenu.ShowRangeVisualsOnly("SoccerStadium")
			end,
		},
		{
			itemID = "BasketballStadium", -- BalanceEconomy
			itemName = "Basketball Stadium",
			price = BalanceEconomy.costPerGrid.BasketballStadium,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Sports["Basketball Stadium"],
			onClick = function()
				selectZoneEvent:FireServer("BasketballStadium")
				BuildMenu.ShowRangeVisualsOnly("BasketballStadium")
			end,
		},
		{
			itemID = "FootballStadium", -- BalanceEconomy
			itemName = "Football Stadium",
			priceInRobux = "FootballStadium",
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Sports["Football Stadium"],
			onClick = function()
				selectZoneEvent:FireServer("FootballStadium")
				BuildMenu.ShowRangeVisualsOnly("FootballStadium")
			end,
		},
	})
	CreateTabSection("Water", {
		{
			itemID = "WaterTower", -- BalanceEconomy
			itemName = "Water Tower",
			price = BalanceEconomy.costPerGrid.WaterTower,
			--image = "rbxassetid://15011943540",
			--modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Water[""],
			onClick = function()
				selectZoneEvent:FireServer("WaterTower")
			end,
		},
		{
			itemID = "WaterPipe", -- BalanceEconomy
			itemName = "Water Pipes",
			price = BalanceEconomy.costPerGrid.WaterPipe,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Water.WaterPipe,
			onClick = function()
				selectZoneEvent:FireServer("WaterPipe")
			end,
		},
		{
			itemID = "WaterPlant", -- BalanceEconomy
			itemName = "Water Plant",
			price = BalanceEconomy.costPerGrid.WaterPlant,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Water["Water Plant"],
			onClick = function()
				selectZoneEvent:FireServer("WaterPlant")
			end,
		},
		{
			itemID = "PurificationWaterPlant", -- BalanceEconomy
			itemName = "Purification Water Plant",
			price = BalanceEconomy.costPerGrid.PurificationWaterPlant,
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Water["Purification Water Plant"],
			onClick = function()
				selectZoneEvent:FireServer("PurificationWaterPlant")
			end,
		},
		{
			itemID = "MolecularWaterPlant", -- BalanceEconomy
			itemName = "MolecularWaterPlant",
			priceInRobux = "MolecularWaterPlant",
			--image = "rbxassetid://15011943540",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Water["Molecular Water Plant"],
			onClick = function()
				selectZoneEvent:FireServer("MolecularWaterPlant")
			end,
		},
	})

	-- Tab Buttons
	BuildMenu.SetTab("Transport")

	UI_Tab_Services.Background.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		BuildMenu.SetTab("Services")
	end)
	UI_Tab_Supply.Background.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		BuildMenu.SetTab("Supply")
	end)
	UI_Tab_Transpot.Background.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		BuildMenu.SetTab("Transport")
	end)
	UI_Tab_Zones.Background.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		BuildMenu.SetTab("Zones")
	end)


	-- Exit Button
	UI_Exit.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		BuildMenu.Toggle()
	end)

	-- Exit Button VFX
	UtilityGUI.VisualMouseInteraction(
		UI_Exit, UI_Exit.TextLabel,
		TweenInfo.new(0.15),
		{ Size = UDim2.fromScale(1.25, 1.25) },
		{ Size = UDim2.fromScale(0.5, 0.5) }
	)
	
	local UIUpdate_RemoteEvent = ReplicatedStorage.Events.RemoteEvents.UpdateStatsUI
	local UIUpdate_RemoteEvent = ReplicatedStorage.Events.RemoteEvents.UpdateStatsUI
	UIUpdate_RemoteEvent.OnClientEvent:Connect(function(data)
		if not data then return end

		-- Only update when the server actually sent a level
		if data.level ~= nil then
			CachedLevel = tonumber(data.level) or 0
		end

		UpdateLocks()
		UpdateBusDepotButton()
		UpdateAirportButton()
		UpdateMetroButton()
	end)
	UpdateLocks()
	UpdateBusDepotButton()
	UpdateAirportButton()
	UpdateMetroButton()
	local save = PlayerDataController.GetSaveFileData()
	if save and save.cityLevel ~= nil then
		CachedLevel = tonumber(save.cityLevel) or 0
	end
	UpdateLocks()
	
	-- Tag exclusive Locations
	--local Choice = FrameButtons["FirePrecinct"]
	--local SaveFileData = PlayerDataController.GetSaveFileData()
	--if SaveFileData and SaveFileData.exclusiveLocations["FirePrecinct"] > 0 then
	--	Choice.FreeAmounts.Text = "x"..SaveFileData.exclusiveLocations["FirePrecinct"]
	--end

end

RE_PlayerDataChanged_ExclusiveLocations.OnClientEvent:Connect(function(ExclusiveLocationName: string, Amount: number)
	local Choice = FrameButtons[ExclusiveLocationName]
	if Choice and Choice:FindFirstChild("FreeAmounts") then
		Choice.FreeAmounts.Text = "x"..Amount
	end
end)

return BuildMenu