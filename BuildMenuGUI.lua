local BuildMenu = {}

-- Roblox Services
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local RunServiceScheduler = require(ReplicatedStorage.Scripts.RunServiceScheduler)
local PlayerPlotsFolder = Workspace:WaitForChild("PlayerPlots")


-- Dependencies
local Abr = require(ReplicatedStorage.Scripts.UI.Abrv)
local UtilityGUI = require(ReplicatedStorage.Scripts.UI.UtilityGUI)
local DevProducts = require(ReplicatedStorage.Scripts.DevProducts)
local SoundController = require(ReplicatedStorage.Scripts.Controllers.SoundController)
local PlayerDataController = require(ReplicatedStorage.Scripts.Controllers.PlayerDataController)
local LocalizationLoader = require(ReplicatedStorage.Localization.Localizing)

local Balancing = ReplicatedStorage:WaitForChild("Balancing")
local BalanceEconomy = require(Balancing:WaitForChild("BalanceEconomy"))
local selectZoneEvent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents"):WaitForChild("SelectZoneType")
local Events = ReplicatedStorage:WaitForChild("Events")
local RE = Events:WaitForChild("RemoteEvents")
local RF = Events:WaitForChild("RemoteFunctions")
local BE = Events:WaitForChild("BindableEvents")
local BF = Events:WaitForChild("BindableFunctions")
local FUS = RE:WaitForChild("FeatureUnlockStatus")
local RE_BusSupportStatus = RE:WaitForChild("BusSupportStatus")
local RE_MetroSupportStatus = RE:FindFirstChild("MetroSupportStatus")
local RangeVisualsClient = require(ReplicatedStorage.Scripts.UI.RangeVisualsClient)
local UITargetRegistry = require(ReplicatedStorage.Scripts.UI.UITargetRegistry)
local RE_OnboardingStepCompleted = RE:WaitForChild("OnboardingStepCompleted")

-- [ADDED] bring in UpdateStatsUI for balance cache (you were already using this later)
local UIUpdate_RemoteEvent = RE:WaitForChild("UpdateStatsUI")

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
local CachedBalance = 0               -- [ADDED] numeric balance cache
local UI_PlaceButton = UI.main.PlaceButton

local function _resolveLang(key: string?, fallback: string?)
	if type(key) ~= "string" or key == "" then
		return fallback
	end

	local lang: string? = nil
	local player = LocalPlayer
	if player then
		local attr = player:GetAttribute("Language")
		if type(attr) == "string" and attr ~= "" then
			lang = attr
		end
	end

	if not lang or lang == "" then
		local data = PlayerDataController.GetData()
		if type(data) == "table" then
			local savedLang = data.Language
			if type(savedLang) == "string" and savedLang ~= "" then
				lang = savedLang
			end
		end
	end

	if not lang or lang == "" then
		lang = "English"
	end

	if LocalizationLoader and LocalizationLoader.isValidLanguage then
		local ok, valid = pcall(LocalizationLoader.isValidLanguage, lang)
		if ok and not valid then
			lang = "English"
		end
	end

	local localized
	if LocalizationLoader and LocalizationLoader.get then
		local ok, value = pcall(LocalizationLoader.get, key, lang)
		if ok and type(value) == "string" and value ~= "" then
			localized = value
		end
	end

	if localized then
		return localized
	end

	if LocalizationLoader and LocalizationLoader.get then
		local okEnglish, englishValue = pcall(LocalizationLoader.get, key, "English")
		if okEnglish and type(englishValue) == "string" and englishValue ~= "" then
			return englishValue
		end
	end

	if type(fallback) == "string" and fallback ~= "" then
		return fallback
	end

	return key
end


local OBArrow = UI.OnboardingArrow
local ARROW_VERTICAL_OFFSET = -5
local ARROW_BOUNCE_AMPLITUDE = 4
local ARROW_BOUNCE_SPEED = 2

local BE_TabChanged   = BE:WaitForChild("OBBuildMenuTabChanged")       -- :Fire("major", "Zones" | "Transport" | "Supply" | "Services")
local BF_GetMajorTab  = BF:WaitForChild("OBBuildMenuGetMajorTab")      -- :Invoke() -> string?
local BF_GetHub = BF:FindFirstChild("OBBuildMenuGetHub")

BF_GetMajorTab.OnInvoke = function()
	return MajorCurrentTabName
end

-- Return "Water" or "Power" when Supply is the context; nil otherwise.
BF_GetHub.OnInvoke = function(majorName)
	majorName = tostring(majorName or MajorCurrentTabName)
	if majorName == "Supply" then
		if CurrentTabName == "Water" then return "Water" end
		if CurrentTabName == "Power" then return "Power" end
	end
	return nil
end

local function ensureDisableDeleteModeEvent(): BindableEvent
	local evt = BE:FindFirstChild("DisableDeleteMode")
	if not evt then
		evt = Instance.new("BindableEvent")
		evt.Name = "DisableDeleteMode"
		evt.Parent = BE
	end
	return evt
end

-- === PULSE: token-safe UI pulse controller ===================================
local _pulseTargets: {[string]: GuiObject?} = {}   -- key -> GuiObject

-- [ADDED] local arrow tracking state for OBArrow
local _obArrowConn = nil
local _obArrowOwnerKey = nil
local _obArrowToken = 0

local function _regTarget(key: string, gui: GuiObject?)
	_pulseTargets[key] = gui
	pcall(function() UITargetRegistry.Register(key, gui) end)
end
local PULSE_COLOR = Color3.fromRGB(90, 255, 120)

-- Forward-declare: other code calls this before we assign it.
local _updatePulses: (() -> ())? = nil

local function _ensurePulseRing(gui: GuiObject)
	local ring = gui:FindFirstChild("_PulseRing")
	if ring and ring:IsA("Frame") then
		local stroke = ring:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = PULSE_COLOR
			stroke.Thickness = 3
			stroke.Transparency = 0.6
		end
		return ring, stroke
	end
	ring = Instance.new("Frame")
	ring.Name = "_PulseRing"
	ring.BackgroundTransparency = 1
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(1, 1)
	ring.ZIndex = (gui.ZIndex or 1) + 5
	local baseCorner = gui:FindFirstChildOfClass("UICorner")
	if baseCorner then
		local c = Instance.new("UICorner")
		c.CornerRadius = baseCorner.CornerRadius
		c.Parent = ring
	end
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = PULSE_COLOR
	stroke.Thickness = 3
	stroke.Transparency = 0.6
	stroke.Parent = ring
	ring.Parent = gui
	return ring, stroke
end

-- [FIX] central arrow release so we can hide even if the GUI target is gone
local function _releaseArrowIfOwner(key: string?)
	if _obArrowOwnerKey and (_obArrowOwnerKey == key or key == nil) then
		if _obArrowConn then _obArrowConn() end
		_obArrowConn = nil
		_obArrowOwnerKey = nil
		_obArrowToken += 1
		if OBArrow and OBArrow:IsA("GuiObject") then
			OBArrow.Visible = false
		end
	end
end

local function _startPulseFor(gui: GuiObject?, key: string)
	-- If no target exists, make sure any previous arrow owned by this key is gone.
	if not gui or not gui.Parent then
		_releaseArrowIfOwner(key)
		return false
	end

	local token = (gui:GetAttribute("_PulseToken") or 0) + 1
	gui:SetAttribute("_PulseToken", token)
	gui:SetAttribute("_PulseKey", key)

	local ring, stroke = _ensurePulseRing(gui)
	ring.Visible = true
	stroke.Color = PULSE_COLOR
	stroke.Thickness = 3
	ring.Size = UDim2.fromScale(1, 1)

	-- Position & show our local arrow over the pulsing button
	if OBArrow and OBArrow:IsA("GuiObject") then
		if _obArrowConn then _obArrowConn() end
		_obArrowToken += 1
		_obArrowOwnerKey = key
		OBArrow.Visible = true
		OBArrow.Rotation = 180
		pcall(function() OBArrow.AnchorPoint = Vector2.new(0.5, 1) end)
		OBArrow.ZIndex = math.max((gui.ZIndex or 1) + 10, OBArrow.ZIndex or 1)
		local myToken = _obArrowToken
		local myKey = key

		_obArrowConn = RunServiceScheduler.onRenderStepped(function()
			-- Abort if ownership changed
			if _obArrowToken ~= myToken then return end

			-- If the target or arrow went away, hide immediately
			if not (gui.Parent and OBArrow.Parent) then
				_releaseArrowIfOwner(myKey)
				return
			end

			local pos = gui.AbsolutePosition
			local size = gui.AbsoluteSize
			local bounce = math.sin(os.clock() * ARROW_BOUNCE_SPEED) * ARROW_BOUNCE_AMPLITUDE
			OBArrow.Position = UDim2.fromOffset(pos.X + size.X * 0.5, pos.Y + ARROW_VERTICAL_OFFSET + bounce)
		end)
	end

	task.spawn(function()
		while gui.Parent and gui:GetAttribute("_PulseToken") == token do
			local tIn = TweenService:Create(stroke, TweenInfo.new(0.42, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Transparency = 0.15 })
			tIn:Play(); tIn.Completed:Wait()
			if not (gui.Parent and gui:GetAttribute("_PulseToken") == token) then break end
			local tOut = TweenService:Create(stroke, TweenInfo.new(0.58, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { Transparency = 0.65 })
			tOut:Play(); tOut.Completed:Wait()
		end
		if gui:GetAttribute("_PulseToken") == token then
			stroke.Transparency = 0.65
			ring.Visible = true
		end
	end)

	return true
end

local function _stopPulseForKey(key: string)
	local gui = _pulseTargets[key]

	-- If we still have the GUI reference, stop its ring tween/token.
	if gui then
		local token = (gui:GetAttribute("_PulseToken") or 0) + 1
		gui:SetAttribute("_PulseToken", token)
		gui:SetAttribute("_PulseKey", nil)
		local ring = gui:FindFirstChild("_PulseRing")
		if ring and ring:IsA("Frame") then
			local stroke = ring:FindFirstChildOfClass("UIStroke")
			if stroke then
				local t = TweenService:Create(stroke, TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Transparency = 1 })
				t:Play()
				t.Completed:Connect(function()
					if ring and ring.Parent then
						ring.Visible = false
					end
				end)
			else
				ring.Visible = false
			end
		end
	end

	-- Always hide the arrow if this key owned it, even if the GUI is gone.
	if _obArrowOwnerKey == key then
		_releaseArrowIfOwner(key)
	end
end

local function _stopAllPulses()
	for key, gui in pairs(_pulseTargets) do
		if gui then _stopPulseForKey(key) else
			-- key registered but no gui; still ensure arrow gets released if it was owned by this key
			if _obArrowOwnerKey == key then _releaseArrowIfOwner(key) end
		end
	end
	_releaseArrowIfOwner(nil) -- absolute guarantee
end


-- === Gate + pulse targets ====================================================
local _obEnabled: boolean = false
local _obGateItemID: string? = nil  -- single source of truth

local function _refreshPulseTargets()
	-- Transport
	local transportBtn; pcall(function() transportBtn = UI.main.tabs.transport.Background end)
	if not transportBtn then pcall(function() transportBtn = UI.main.tabs.transpot and UI.main.tabs.transpot.Background end) end
	_regTarget("BM_Transport", transportBtn)

	-- Zones
	local zonesBtn; pcall(function() zonesBtn = UI.main.tabs.zones.Background end)
	_regTarget("BM_Zones", zonesBtn)

	-- Services / Supply (optional)
	local servicesBtn; pcall(function() servicesBtn = UI.main.tabs.services.Background end)
	_regTarget("BM_Services", servicesBtn)

	local supplyBtn; pcall(function() supplyBtn = UI.main.tabs.supply.Background end)
	_regTarget("BM_Supply", supplyBtn)

	-- Road button
	local roadBtn = FrameButtons and FrameButtons["DirtRoad"] or nil
	_regTarget("BM_DirtRoad", roadBtn)

	-- Core onboarding items (so gates/hints have real targets)
	_regTarget("BM_WaterPipe",    FrameButtons and FrameButtons["WaterPipe"] or nil)
	_regTarget("BM_WaterTower",   FrameButtons and FrameButtons["WaterTower"] or nil)
	_regTarget("BM_WindTurbine",  FrameButtons and FrameButtons["WindTurbine"] or nil)
	_regTarget("BM_PowerLines",   FrameButtons and FrameButtons["PowerLines"] or nil)
	_regTarget("BM_SolarPanels",  FrameButtons and FrameButtons["SolarPanels"] or nil)
	_regTarget("BM_Industrial",   FrameButtons and FrameButtons["Industrial"] or nil)

	-- Supply hubs (use Supply tab as fallback if a dedicated hub button is missing)
	_regTarget("BM_Supply_Power", supplyBtn)
	_regTarget("BM_Supply_Water", supplyBtn)

	-- Mobile confirm / placement button
	_regTarget("BM_PlaceButton", UI_PlaceButton)
end

-- BuildMenu is being gated to a specific next-step item while onboarding runs
function BuildMenu.ApplyGateVisual(itemID: string?)
	if type(itemID) == "string" and itemID ~= "" then
		_obGateItemID = itemID
	else
		_obGateItemID = nil
	end
	if _updatePulses then _updatePulses() end
end

-- React to onboarding enable/disable so gates/pulses clear when onboarding ends
local function _setOnboardingEnabled(enabled: boolean)
	_obEnabled = (enabled ~= false)
	if not _obEnabled then
		_obGateItemID = nil
		_stopAllPulses()
	end
	if _updatePulses then _updatePulses() end
end

local BE_OnboardingToggle = BE:FindFirstChild("OnboardingToggle")
if BE_OnboardingToggle and BE_OnboardingToggle:IsA("BindableEvent") then
	BE_OnboardingToggle.Event:Connect(function(enabled)
		_setOnboardingEnabled(enabled)
	end)
end

-- Default pulsing logic (gate ALWAYS wins)
_updatePulses = function()
	_refreshPulseTargets()

	-- If UI is hidden, or onboarding is disabled, stop everything.
	if not UI.Enabled or _obEnabled == false then
		_stopAllPulses()
		return
	end

	-- Gate active → suppress BuildMenu's default nudge (server/client onboarding scripts will drive gates)
	if _obGateItemID ~= nil then
		_stopAllPulses()
		return
	end

	-- Default nudge (only when onboarding is enabled AND no gate is active)
	if MajorCurrentTabName ~= "Transport" then
		_stopPulseForKey("BM_DirtRoad")
		_startPulseFor(_pulseTargets["BM_Transport"], "BM_Transport")
	else
		_stopPulseForKey("BM_Transport")
		_startPulseFor(_pulseTargets["BM_DirtRoad"], "BM_DirtRoad")
	end
end

-- Listen to onboarding toggle (optional; does not modify gate)
do
	local ev = BE:FindFirstChild("OnboardingToggle")
	if ev and ev:IsA("BindableEvent") then
		ev.Event:Connect(function(enabled)
			_obEnabled = (enabled ~= false)
			if _updatePulses then _updatePulses() end
		end)
	end
end
-- ============================================================================

-- [ADDED] helpers mirrored from Grid script so we can pre-check affordability at click time
local function parseAbbrev(str)
	-- “50k” → 50000, “1.2m” → 1200000
	local num, suffix = tonumber(str:match("^([%d%.]+)")), str:match("([kmbt])$")
	if not num then return 0 end
	local mults = { k = 1e3, m = 1e6, b = 1e9, t = 1e12 }
	return num * (mults[suffix] or 1)
end

local function asNumber(val)
	if type(val) == "number" then return val end
	if type(val) == "string" then return tonumber(val) or parseAbbrev(val) or 0 end
	return 0
end

local function openPremiumShop()
	local pg = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui")

	-- Preferred (module-driven) shop
	local premiumShopGui = pg:FindFirstChild("PremiumShopGui")
	if premiumShopGui and premiumShopGui:FindFirstChild("Logic") then
		local ok, mod = pcall(function() return require(premiumShopGui.Logic) end)
		if ok and mod and type(mod.OnShow) == "function" then
			mod.OnShow()
			return true
		end
	end

	-- Legacy ScreenGui fallback
	local legacyShop = pg:FindFirstChild("PremiumShop")
	if legacyShop then
		legacyShop.Enabled = true
		return true
	end

	-- Last-resort feedback so players always see something
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", {
			Title = "Not enough cash",
			Text = "You don't have enough funds for this action.",
			Duration = 4
		})
	end)
	return false
end

-- [ADDED] zones/lines known to be variable-cost; we skip pre-click affordability
local VARIABLE_COST_IDS = {
	-- Lines:
	DirtRoad = true, Pavement = true, Highway = true, WaterPipe = true, PowerLines = true, MetroTunnel = true,
	-- Area zones:
	Residential = true, Commercial = true, Industrial = true,
	ResDense = true, CommDense = true, IndusDense = true,
}

local function isZoneOrLinear(itemID)
	if type(itemID) ~= "string" then return false end
	-- dynamic flags are fixed price per placement (we DO pre-check those), so exclude them here
	if itemID:sub(1,5) == "Flag:" then return false end
	return VARIABLE_COST_IDS[itemID] == true
end

local BuildingLevelRequirement = {} -- [BuildingID] = MinLevel
-- Populate Level Requirements
local UnlockOrderIndex = {}        -- [BuildingID] = global sort index to preserve config ordering

local unlocksByLevel = BalanceEconomy.ProgressionConfig.unlocksByLevel
local levelKeys = {}
for level in pairs(unlocksByLevel) do
	levelKeys[#levelKeys + 1] = tonumber(level) or 0
end
table.sort(levelKeys)

local function getUnlockList(levelNumber: number)
	return unlocksByLevel[levelNumber] or unlocksByLevel[tostring(levelNumber)]
end

local orderSeed = 0
for _, levelNumber in ipairs(levelKeys) do
	local buildingList = getUnlockList(levelNumber)
	if type(buildingList) == "table" then
		for _, buildingID in ipairs(buildingList) do
			BuildingLevelRequirement[buildingID] = levelNumber
			orderSeed += 1
			UnlockOrderIndex[buildingID] = orderSeed
		end
	end
end

local function shouldAnnounceUnlock(featureID: string): boolean
	-- Treat anything missing from the config as level 0 (starter content)
	return (BuildingLevelRequirement[featureID] or 0) > 0
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
	["Flags"]     = "Flags"
}

-- Common folders you used in BuildMenu
local IND  = BLD:WaitForChild("Individual"):WaitForChild("Default")
local EDUC = IND:WaitForChild("Education")
local FIRE = IND:WaitForChild("Fire")
local POLI = IND:WaitForChild("Police")
local HLTH = IND:WaitForChild("Health")
local LAND = IND:WaitForChild("Landmark")
local LEIS = IND:WaitForChild("Leisure")
local SPRT = IND:WaitForChild("Sports")
local POWR = IND:WaitForChild("Power")
local WATR = IND:WaitForChild("Water")
local TRAN = IND:FindFirstChild("Transport") -- only if you have it
local FLAGS = IND:WaitForChild("Flags")

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
	["Flags"]  = "Services",

	-- Supply sub-sections
	Power = "Supply",
	Water = "Supply",

	-- Transport sub-sections
	Road  = "Transport",
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
local markItemSeen -- forward declaration

local function markSectionSeen(sectionName: string)
	local uiSection = TabSections[sectionName]
	if not uiSection then return end

	-- Clearing a section now happens per-item via markItemSeen; kept for compatibility if ever invoked.
	for itemID in pairs(PendingByItem) do
		if ItemToSection[itemID] == sectionName then
			-- markItemSeen will update dots and badges for us
			markItemSeen(itemID)
		end
	end
end

-- Clear a single item's pending dot only after the user actually looks at it (hover/click).
markItemSeen = function(itemID: string)
	if not (itemID and PendingByItem[itemID]) then return end
	PendingByItem[itemID] = nil

	local btn = FrameButtons[itemID]
	if btn then
		local dot = btn:FindFirstChild("notification")
		if dot then dot.Visible = false end
	end

	local section = ItemToSection[itemID]
	if section then
		local anyPending = false
		for id, pending in pairs(PendingByItem) do
			if pending and ItemToSection[id] == section then
				anyPending = true
				break
			end
		end
		SectionHasPending[section] = anyPending

		local hubBtn = CategoryButtonForSection[section]
		if hubBtn then
			local dot = hubBtn:FindFirstChild("notification")
			if dot then dot.Visible = anyPending end
		end
	end

	recomputeTopTabBadges()
end

local function entriesFor(features: {string}, labelsById: {[string]: string}?)
	local arr = {}
	for _, id in ipairs(features) do
		-- Prefer icon for these
		local icon = FeatureIcons[id]
		if icon then
			local label = (labelsById and labelsById[id]) or id
			arr[#arr+1] = { image = icon, label = label }
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

-- Build a readable label for unlock popups that pairs the hub/section with the item.
local function hubAwareLabel(itemID: string)
	local friendly = tostring(itemID)
	do
		local btn = FrameButtons[itemID]
		local nameLabel = btn and btn.info and btn.info.itemName
		if nameLabel then
			local langKey = nameLabel:GetAttribute("LangKey")
			local text = nameLabel.Text
			local resolved = _resolveLang(langKey, text or itemID)
			if type(resolved) == "string" and resolved ~= "" then
				friendly = resolved
			elseif type(text) == "string" and text ~= "" then
				friendly = text
			end
		end
	end

	local hub = ItemToSection[itemID]
	if hub and hub ~= "" then
		return hub .. " - " .. friendly
	end
	return friendly
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

	local labelsById = {}
	local displayList = {}
	for _, id in ipairs(gainedList) do
		local label = hubAwareLabel(id)
		labelsById[id] = label
		displayList[#displayList + 1] = label
	end

	local title = (#displayList == 1) and (displayList[1] .. " Unlocked!") or "New items unlocked!"
	local desc  = table.concat(displayList, ", ")

	local iconsOrModels = entriesFor(gainedList, labelsById)
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
local pipesfoldervisible = false
local waterpipeszones = nil
local waterpipeszonesVisible = false
local powerlineszones = nil
local powerlineszonesVisible = false
local buildings = nil
local buildingVisible = false
local buildingsNoQueryActive = false
local metroTunnelsFolder = nil
local metroTunnelsVisible = false

local InfraVisibilityControllers: {[Instance]: {visible: boolean, conn: RBXScriptConnection?}} = {}
local ForeignPlotChildConns: {[Instance]: RBXScriptConnection?} = {}
local ForeignRangeVisualConns: {[Instance]: RBXScriptConnection?} = {}

local function applyLocalTransparency(inst: Instance, visible: boolean)
	if inst:IsA("BasePart") then
		inst.LocalTransparencyModifier = visible and 0 or 1
		if not visible then
			inst.Transparency = 1
			inst.CanCollide = false
			inst.CanTouch = false
			inst.CanQuery = false
			inst.CastShadow = false
		end
	elseif inst:IsA("Decal") or inst:IsA("Texture") then
		if not visible then
			inst.Transparency = 1
		end
	elseif inst:IsA("Beam") or inst:IsA("Trail") or inst:IsA("ParticleEmitter") then
		inst.Enabled = visible
	end
end

local function ensureInfraController(folder: Instance)
	local controller = InfraVisibilityControllers[folder]
	if controller then
		return controller
	end

	controller = {
		visible = true,
		conn = nil,
	}

	controller.conn = folder.DescendantAdded:Connect(function(inst)
		applyLocalTransparency(inst, controller.visible)
	end)

	folder.Destroying:Connect(function()
		local stored = InfraVisibilityControllers[folder]
		if not stored then return end
		if stored.conn then
			stored.conn:Disconnect()
		end
		InfraVisibilityControllers[folder] = nil
	end)

	InfraVisibilityControllers[folder] = controller
	return controller
end

local function setInfraFolderVisible(folder: Instance?, visible: boolean)
	if not folder then return end
	local controller = ensureInfraController(folder)
	controller.visible = visible and true or false
	for _, desc in ipairs(folder:GetDescendants()) do
		applyLocalTransparency(desc, controller.visible)
	end
end

local function hideForeignInfrastructure(plot: Instance)
	if not plot or not plot:IsA("Model") then return end
	local ownerId = tonumber((plot.Name or ""):match("^Plot_(%d+)$"))
	if not ownerId or ownerId == LocalPlayer.UserId then
		return
	end
	if ForeignPlotChildConns[plot] then
		return
	end

	local function hideChild(child: Instance)
		if not child then return end
		local name = child.Name
		if name == "Pipes" or name == "MetroTunnels" then
			setInfraFolderVisible(child, false)
		end
	end

	for _, child in ipairs(plot:GetChildren()) do
		hideChild(child)
	end

	ForeignPlotChildConns[plot] = plot.ChildAdded:Connect(hideChild)
	plot.Destroying:Connect(function()
		local conn = ForeignPlotChildConns[plot]
		if conn then
			conn:Disconnect()
		end
		ForeignPlotChildConns[plot] = nil
	end)
end

for _, plot in ipairs(PlayerPlotsFolder:GetChildren()) do
	hideForeignInfrastructure(plot)
end

PlayerPlotsFolder.ChildAdded:Connect(function(child)
	hideForeignInfrastructure(child)
end)

local buildingTransparencyMode = false
local storedBuildingTransparency = {} -- [Instance] = number
local storedBuildingCanCollide = {}   -- [Instance] = boolean   -- [ADDED]
local storedBuildingCanQuery   = {}   -- [Instance] = boolean   -- [ADDED]

local function isRangeVisualPart(inst: Instance): boolean
	if not (inst and inst:IsA("BasePart")) then return false end
	local inner  = inst:FindFirstChild("Inner")
	local outter = inst:FindFirstChild("Outter") or inst:FindFirstChild("Outer")
	return (inner and inner:IsA("SurfaceGui")) or (outter and outter:IsA("SurfaceGui"))
end

local function _disableRangeSurfaceGuis(part: BasePart)
	local inner = part:FindFirstChild("Inner")
	if inner and inner:IsA("SurfaceGui") then inner.Enabled = false end
	local outer = part:FindFirstChild("Outer") or part:FindFirstChild("Outter")
	if outer and outer:IsA("SurfaceGui") then outer.Enabled = false end
end

local function hideRangeVisualPartLocally(inst: Instance)
	if isRangeVisualPart(inst) then
		inst.LocalTransparencyModifier = 1
		if inst:IsA("BasePart") then
			_disableRangeSurfaceGuis(inst)
			inst.Transparency = 1
			inst.CanCollide = false
			inst.CanTouch = false
			inst.CanQuery = false
			inst.CastShadow = false
		end
	end
end

local function _plotOwnerId(plot: Instance)
	if not (plot and plot:IsA("Model")) then return nil end
	local attr = plot:GetAttribute("Owner") or plot:GetAttribute("OwnerId") or plot:GetAttribute("PlayerId") or plot:GetAttribute("UserId")
	if type(attr) == "number" then return attr end
	if type(attr) == "string" then
		local n = tonumber(attr)
		if n then return n end
	end
	return tonumber((plot.Name or ""):match("(%d+)"))
end

local function hideForeignRangeVisuals(plot: Instance)
	if not plot or not plot:IsA("Model") then return end
	local ownerId = _plotOwnerId(plot)
	if not ownerId or ownerId == LocalPlayer.UserId or (myPlot and plot == myPlot) then
		return
	end
	if ForeignRangeVisualConns[plot] then
		return
	end

	for _, desc in ipairs(plot:GetDescendants()) do
		hideRangeVisualPartLocally(desc)
	end

	ForeignRangeVisualConns[plot] = plot.DescendantAdded:Connect(function(inst)
		if inst:IsA("SurfaceGui") then
			local p = inst:FindFirstAncestorWhichIsA("BasePart")
			if p then hideRangeVisualPartLocally(p) end
		else
			hideRangeVisualPartLocally(inst)
		end
	end)

	plot.Destroying:Connect(function()
		local conn = ForeignRangeVisualConns[plot]
		if conn then
			conn:Disconnect()
		end
		ForeignRangeVisualConns[plot] = nil
	end)
end

task.spawn(function()
	for _, plot in ipairs(PlayerPlotsFolder:GetChildren()) do
		hideForeignRangeVisuals(plot)
	end
	PlayerPlotsFolder.ChildAdded:Connect(hideForeignRangeVisuals)
end)

local function SetBuildingsTransparent(state: boolean)
	if not buildings then return end
	if buildingTransparencyMode == state then return end
	buildingTransparencyMode = state

	for _, inst in ipairs(buildings:GetDescendants()) do
		if inst:IsA("BasePart") then
			-- SKIP range-visual parts entirely
			if isRangeVisualPart(inst) then
				-- do nothing
			else
				if state then
					storedBuildingTransparency[inst] = inst.Transparency
					storedBuildingCanCollide[inst]   = inst.CanCollide
					storedBuildingCanQuery[inst]     = inst.CanQuery
					inst.Transparency = 0.75
					inst.CanCollide   = false
					inst.CanQuery     = false
				else
					local t = storedBuildingTransparency[inst]
					if t ~= nil then inst.Transparency = t; storedBuildingTransparency[inst] = nil end
					local cc = storedBuildingCanCollide[inst]
					if cc ~= nil then inst.CanCollide = cc; storedBuildingCanCollide[inst] = nil end
					local cq = storedBuildingCanQuery[inst]
					if cq ~= nil then inst.CanQuery = cq;   storedBuildingCanQuery[inst]   = nil end
				end
			end
		end
	end
end

if buildings then
	buildings.DescendantAdded:Connect(function(inst)
		if not buildingTransparencyMode then return end
		if inst:IsA("BasePart") then
			-- SKIP range-visual parts entirely
			if isRangeVisualPart(inst) then return end
			storedBuildingTransparency[inst] = inst.Transparency
			storedBuildingCanCollide[inst]   = inst.CanCollide
			storedBuildingCanQuery[inst]     = inst.CanQuery
			inst.Transparency = 0.75
			inst.CanCollide   = false
			inst.CanQuery     = false
		end
	end)
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

local function zoneAlpha(visible: boolean): number
	return visible and 0.75 or 1.0
end

local function applyZoneFolderVisibility(folder: Folder?, shouldShow: boolean)
	if not folder then return end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") and not isRangeVisualPart(child) then
			child.Transparency = zoneAlpha(shouldShow)
		end
	end
end

local function playerZonesShouldRender(): boolean
	return playerzonesVisible and (UI and UI.Enabled)
end

local function waterZonesShouldRender(): boolean
	return waterpipeszonesVisible and (UI and UI.Enabled)
end

local function powerZonesShouldRender(): boolean
	return powerlineszonesVisible and (UI and UI.Enabled)
end

local function applyPlayerZoneVisibility()
	applyZoneFolderVisibility(playerzones, playerZonesShouldRender())
end

local function applyWaterZoneVisibility()
	applyZoneFolderVisibility(waterpipeszones, waterZonesShouldRender())
end

local function applyPowerZoneVisibility()
	applyZoneFolderVisibility(powerlineszones, powerZonesShouldRender())
end

local function applyAllZoneVisibilities()
	applyPlayerZoneVisibility()
	applyWaterZoneVisibility()
	applyPowerZoneVisibility()
end

if UI and UI.GetPropertyChangedSignal then
	UI:GetPropertyChangedSignal("Enabled"):Connect(applyAllZoneVisibilities)
end

local function ShowPipesModels(State: boolean)
	pipesfoldervisible = State == true
	if not pipesfolder then return end
	if pipesfoldervisible and myPlot then
		pipesfolder.Parent = myPlot
	else
		pipesfolder.Parent = nil
	end
end
ShowPipesModels(false)

local function ShowMetroModels(State: boolean)
	metroTunnelsVisible = State == true
	if not metroTunnelsFolder then return end
	if metroTunnelsVisible and myPlot then
		metroTunnelsFolder.Parent = myPlot
	else
		metroTunnelsFolder.Parent = nil
	end
end
ShowMetroModels(false)

task.spawn(function()
	local player = Players.LocalPlayer
	local plots = PlayerPlotsFolder
	myPlot = plots:WaitForChild("Plot_" .. player.UserId)
	playerzones = myPlot:WaitForChild("PlayerZones")
	waterpipeszones = myPlot:WaitForChild("WaterPipeZones")
	powerlineszones = myPlot:WaitForChild("PowerLinesZones")
	buildings = myPlot:WaitForChild("Buildings")
	pipesfolder = myPlot:WaitForChild("Pipes")
	ShowPipesModels(pipesfoldervisible)
	metroTunnelsFolder = myPlot:WaitForChild("MetroTunnels", 3) or metroTunnelsFolder
	if metroTunnelsFolder then
		ShowMetroModels(metroTunnelsVisible)
	end

	myPlot.ChildAdded:Connect(function(child)
		if child.Name == "Pipes" and child:IsA("Folder") then
			pipesfolder = child
			ShowPipesModels(pipesfoldervisible)
		elseif child.Name == "MetroTunnels" and child:IsA("Folder") then
			metroTunnelsFolder = child
			ShowMetroModels(metroTunnelsVisible)
		end
	end)

	local function looksLikeRV(part: Instance): boolean
		if not (part and part:IsA("BasePart")) then return false end
		if string.find(part.Name, "RangeVisual", 1, true) then return true end
		local inner = part:FindFirstChild("Inner")
		if inner and inner:IsA("SurfaceGui") then return true end
		local outer = part:FindFirstChild("Outer") or part:FindFirstChild("Outter")
		if outer and outer:IsA("SurfaceGui") then return true end
		for _, d in ipairs(part:GetDescendants()) do
			if d:IsA("SurfaceGui") then return true end
		end
		return false
	end

	local function ensureIsRV(part: BasePart)
		if looksLikeRV(part) and part:GetAttribute("IsRangeVisual") ~= true then
			pcall(function() part:SetAttribute("IsRangeVisual", true) end)
		end
	end

	-- retro-tag anything already under PlayerZones
	for _, inst in ipairs(playerzones:GetDescendants()) do
		if inst:IsA("BasePart") then
			ensureIsRV(inst)
		end
	end

	-- live: if a BasePart or its SurfaceGui appears later, stamp the attr
	playerzones.DescendantAdded:Connect(function(inst)
		if inst:IsA("BasePart") then
			ensureIsRV(inst)
		elseif inst:IsA("SurfaceGui") then
			local p = inst:FindFirstAncestorWhichIsA("BasePart")
			if p then ensureIsRV(p) end
		end
	end)

	-- === RangeVisual SurfaceGui hard-off under PlayerZones ===
	local function isRVGuiName(n) return n == "Inner" or n == "Outter" or n == "Outer" end

	local function disableRVGuisUnder(instance: Instance)
		for _, d in ipairs(instance:GetDescendants()) do
			if d:IsA("SurfaceGui") and isRVGuiName(d.Name) then
				d.Enabled = false
			end
		end
	end

	local function disableAllZoneSurfaceGuis()
		if not playerzones then return end
		disableRVGuisUnder(playerzones)
	end
	disableAllZoneSurfaceGuis()

	playerzones.DescendantAdded:Connect(function(inst)
		if inst:IsA("SurfaceGui") and isRVGuiName(inst.Name) then
			inst.Enabled = false
			return
		end
		if inst:IsA("BasePart") and inst.Name == "RangeVisual" then
			disableRVGuisUnder(inst)
			inst.DescendantAdded:Connect(function(d)
				if d:IsA("SurfaceGui") and isRVGuiName(d.Name) then
					d.Enabled = false
				end
			end)
		end
	end)

	playerzones.DescendantAdded:Connect(function(inst)
		if inst:IsA("SurfaceGui") and (inst.Name == "Inner" or inst.Name == "Outter") then
			inst.Enabled = false
		end
	end)

	if buildings then
		buildings.ChildAdded:Connect(function(child)
			if not buildingsNoQueryActive then return end
			for _, inst in ipairs(child:GetDescendants()) do
				if inst:IsA("BasePart") or inst:IsA("Model") then
					pcall(function() inst:SetAttribute("noquery", true) end)
				end
			end
			if child:IsA("BasePart") or child:IsA("Model") then
				pcall(function() child:SetAttribute("noquery", true) end)
			end
		end)
	end

	playerzones.ChildAdded:Connect(function(Part)
		if not Part:IsA("BasePart") then return end
		if isRangeVisualPart(Part) then return end
		Part.Transparency = zoneAlpha(playerZonesShouldRender())
	end)
	waterpipeszones.ChildAdded:Connect(function(Part)
		if not Part:IsA("BasePart") then return end
		if isRangeVisualPart(Part) then return end
		Part.Transparency = zoneAlpha(waterZonesShouldRender())
	end)
	powerlineszones.ChildAdded:Connect(function(Part)
		if not Part:IsA("BasePart") then return end
		if isRangeVisualPart(Part) then return end
		Part.Transparency = zoneAlpha(powerZonesShouldRender())
	end)

	applyAllZoneVisibilities()
end)

local function findScreenGui(container, name)
	local obj = container:FindFirstChild(name)
	if obj and obj:IsA("ScreenGui") then return obj end
	if obj then
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

-- ==== Bus Depot GUI helpers ====

local function OpenBusDepotGUI()
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
	if not gui or not gui:IsA("ScreenGui") then
		if forceState == false then return end
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
	playerzonesVisible = State == true
	applyPlayerZoneVisibility()
end

local function SetWaterPipesZonesVisible(State: boolean)
	waterpipeszonesVisible = State == true
	applyWaterZoneVisibility()
end

local function SetPowerLinesZonesVisible(State: boolean)
	powerlineszonesVisible = State == true
	applyPowerZoneVisibility()
end

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
	Landmarks              = { Bank=true, CNTower=true, EiffelTower=true, EmpireStateBuilding=true,
		FerrisWheel=true, GasStation=true, ModernSkyscraper=true, NationalCapital=true,
		Obelisk=true, SpaceNeedle=true, WorldTradeCenter=true, TechOffice=true, StatueOfLiberty=true },
	Leisure                = { Church=true, Hotel=true, Mosque=true, MovieTheater=true, ShintoTemple=true, HinduTemple=true,},
	Police                 = { Courthouse=true, PoliceDept=true, PolicePrecinct=true, PoliceStation=true },
	Sports = { ArcheryRange=true, BasketballCourt=true, BasketballStadium=true,
		FootballStadium=true, GolfCourse=true, PublicPool=true,
		SkatePark=true, SoccerStadium=true, TennisCourt=true },
	Transport              = { Airport=true, BusDepot=true, MetroEntrance=true },
	Road = {DirtRoad = true,},
	Power  = { CoalPowerPlant=true, GasPowerPlant=true, GeothermalPowerPlant=true,
		NuclearPowerPlant=true, SolarPanels=true, WindTurbine=true },

	Water                  = { WaterTower=true, WaterPlant=true, PurificationWaterPlant=true, MolecularWaterPlant=true },
}

local RV_SECTIONS = {
	Fire = true, Police = true, Health = true, Education = true,
	Leisure = true, Sports = true, Landmarks = true, Flags = true,
}

local DefaultZoneTypes = {
	Residential     = true, Commercial   = true, Industrial   = true,
	ResDense        = true, CommDense    = true, IndusDense   = true,
}

local _activeCategory
local _suppressSeen = false

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
		if isRangeVisualPart(part) then continue end
		local zt = part:GetAttribute("ZoneType")
		if not zt then continue end

		local shouldShow
		if _activeCategory then
			local map = ZoneCategories[_activeCategory]
			shouldShow = map and map[zt]
		else
			shouldShow = DefaultZoneTypes[zt]
		end

		part.Transparency = shouldShow and 0.75 or 1.0
	end
end

function BuildMenu.ShowZoneCategory(categoryName : string?)
	if categoryName and ZoneCategories[categoryName] then
		if _activeCategory == categoryName then
			_activeCategory = nil
		else
			_activeCategory = categoryName
		end
	else
		_activeCategory = nil
	end

	_refreshCategoryVisibility()

	if _activeCategory and RV_SECTIONS[_activeCategory] then
		RangeVisualsClient.applyCategory(_activeCategory)
		RangeVisualsClient.debugDump()
	else
		RangeVisualsClient.hideAll()
	end
end

function BuildMenu.ShowRangeVisualsOnly(selectedType)
	local plot = myPlot
	if not plot then return end
	local b = buildings
	if not b then return end

	for _, model in ipairs(b:GetChildren()) do
		if model:IsA("Model") then
			local id = model:GetAttribute("BuildingID")
			if type(id) ~= "string" or id == "" then
				id = (model.Name or ""):gsub("%s+",""):gsub("_?Stage%d+$","")
			end
			local match = (id == selectedType)

			for _, desc in ipairs(model:GetDescendants()) do
				if desc:IsA("BasePart") and desc.Name == "RangeVisual" then
					local inner = desc:FindFirstChild("Inner")
					if inner and inner:IsA("SurfaceGui") then inner.Enabled = match end
					local outter = desc:FindFirstChild("Outter") or desc:FindFirstChild("Outer")
					if outter and outter:IsA("SurfaceGui") then outter.Enabled = match end
				end
			end
		end
	end
end

-- Helper Functions
local function UpdateLocks()
	local playerLevel = tonumber(CachedLevel) or 0

	for itemID, Frame in pairs(FrameButtons) do
		local LevelCost = tonumber(BuildingLevelRequirement[itemID])
		if LevelCost ~= nil then
			local IsLocked = playerLevel < LevelCost

			local locked = Frame:FindFirstChild("Locked")
			if locked then locked.Visible = IsLocked end

			local lvlLock = Frame:FindFirstChild("LevelLocked")
			if lvlLock then
				lvlLock.Visible = IsLocked
				local asLabel = lvlLock:IsA("TextLabel") and lvlLock
					or lvlLock:FindFirstChildWhichIsA("TextLabel", true)
				if asLabel and IsLocked then
					asLabel.Text = "Lv. "..tostring(LevelCost)
				end
			end

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

local function _setPriceVisible(itemID: string, visible: boolean)
	local btn = FrameButtons[itemID]
	if not btn then return end
	local priceLabel = btn.info and btn.info:FindFirstChild("price")
	if priceLabel then priceLabel.Visible = visible end
end

local function UpdateBusDepotButton()
	local btn = FrameButtons["BusDepot"]
	if btn and btn.info and btn.info.itemName then
		local langKey = HasBusDepot and "Bus Depot Owned" or "Bus Depot"
		btn.info.itemName:SetAttribute("LangKey", langKey)
		local fallback = HasBusDepot and "Bus Depot (Owned)" or "Bus Depot"
		btn.info.itemName.Text = _resolveLang(langKey, fallback)
	end
	_setPriceVisible("BusDepot", not HasBusDepot)
end

local function UpdateAirportButton()
	local btn = FrameButtons["Airport"]
	if btn and btn.info and btn.info.itemName then
		local langKey = HasAirport and "Airport Owned" or "Airport"
		btn.info.itemName:SetAttribute("LangKey", langKey)
		local fallback = HasAirport and "Airport (Owned)" or "Airport"
		btn.info.itemName.Text = _resolveLang(langKey, fallback)
	end
	_setPriceVisible("Airport", not HasAirport)
end

local function UpdateMetroButton()
	local btn = FrameButtons["MetroEntrance"]
	if btn and btn.info and btn.info.itemName then
		local langKey = HasMetro and "Metro Owned" or "Metro"
		btn.info.itemName:SetAttribute("LangKey", langKey)
		local fallback = HasMetro and "Metro (Owned)" or "Metro"
		btn.info.itemName.Text = _resolveLang(langKey, fallback)
	end
	_setPriceVisible("MetroEntrance", not HasMetro)
end

local function CreateTabSection(SectionName: string, Choices) -- {itemname, price, image, modelref}
	local UISection = UI_TabChoicesContainer:Clone()
	UISection.Name = "TabSection_"..SectionName
	UISection.Visible = false

	local ChoiceTemplate = UISection.Template
	ChoiceTemplate.Visible = false

	local PrintedLangKeys = {}

	for _, Data in Choices do
		local Choice = ChoiceTemplate:Clone()
		Choice.Name = Data.itemName
		Choice.Visible = true
		local key = tostring(Data.itemName)
		Choice.info.itemName:SetAttribute("LangKey", key)
		Choice.info.itemName.Text = _resolveLang(key, key)
		if not PrintedLangKeys[key] then
			PrintedLangKeys[key] = true
			--print("[LangKey]", key)
		end

		if Data.priceInRobux then
			Choice.info.price.Text = "..."
			task.spawn(function()
				Choice.info.price.Text = "\u{E002} ".. DevProducts.GetPrice(Data.priceInRobux)
			end)
			Choice.info.price.TextColor3 = Color3.fromRGB(255, 237, 99)
			Choice.FreeAmounts.Visible = true

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
					if Data.itemID then markItemSeen(Data.itemID) end
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
					if Data.itemID then markItemSeen(Data.itemID) end
					-- [ADDED] Pre-click affordability gate for fixed-cost, non-robux, individual buildings.
					-- We DO NOT block zones/lines here because their final cost is variable.
					if Data.itemID and not isZoneOrLinear(Data.itemID) then
						local need = asNumber(Data.price) -- authoritatively passed in your Choices
						if need > 0 and (tonumber(CachedBalance) or 0) < need then
							openPremiumShop()
							return
						end
					end
					if Data.itemID then SetBuildingsTransparent(true) end
					Data.onClick()
				end)
			end
		end

		-- FLAGS FIRST: dynamic “Flag:*” items are never level-gated and should not warn
		if type(Data.itemID) == "string" and string.sub(Data.itemID, 1, 5) == "Flag:" then
			Choice.Locked.Visible = false
			Choice.LevelLocked.Visible = false

		elseif Data.itemID ~= nil then
			local LevelCost = BuildingLevelRequirement[Data.itemID]
			if LevelCost ~= nil then
				Choice.Locked.Visible = (tonumber(CachedLevel) or 0) < LevelCost
				Choice.LevelLocked.Text = "Lv. " .. tostring(LevelCost)
				Choice.LevelLocked.Visible = Choice.Locked.Visible
			else
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

		local dot = ensureButtonNotif(Choice)

		if Data.itemID then
			FrameButtons[Data.itemID] = Choice
			ItemToSection[Data.itemID] = SectionName

			if type(Data.itemID) == "string" and Data.itemID ~= "" then
				_regTarget("BM_" .. Data.itemID, Choice)
			end

			-- Clear the pending dot only when the player actually hovers or clicks the item.
			Choice.MouseEnter:Connect(function()
				markItemSeen(Data.itemID)
			end)

			if PendingByItem[Data.itemID] then
				dot.Visible = true
				SectionHasPending[SectionName] = true
			end
		else
			local target = (ITEMNAME_TO_SECTION[Data.itemName] or Data.itemName)
			CategoryButtonForSection[target] = Choice
			_regTarget("BM_" .. target, Choice)
			if SectionHasPending[target] then
				dot.Visible = true
			end
		end
	end

	UISection.Parent = UI_TabChoicesContainer.Parent
	TabSections[SectionName] = UISection
end

-- Build the flags list from the folder on demand
local function _flagsChoices()
	local arr = {}
	local children = FLAGS and FLAGS:GetChildren() or {}
	table.sort(children, function(a,b) return a.Name < b.Name end)
	for _, m in ipairs(children) do
		if m:IsA("Model") then
			local flagName = m.Name
			table.insert(arr, {
				itemID   = "Flag:" .. flagName,
				itemName = flagName,
				price    = BalanceEconomy.costPerGrid.Flags or 0,
				modelref = m,
				onClick  = function()
					selectZoneEvent:FireServer("Flag:" .. flagName)
				end,
			})
		end
	end
	return arr
end

local function _rebuildFlagsTab()
	local old = TabSections["Flags"]
	if old and old.Parent then old:Destroy() end
	TabSections["Flags"] = nil
	CreateTabSection("Flags", _flagsChoices())
	if CurrentTabName == "Flags" then
		BuildMenu.SetTab("Flags")
	end
	UpdateLocks()
end

if FLAGS then
	FLAGS.ChildAdded:Connect(_rebuildFlagsTab)
	FLAGS.ChildRemoved:Connect(_rebuildFlagsTab)
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
	local wasMajor = MajorCurrentTabName
	if CurrentTabName == TabName then return end

	local isMajor = (TabName == "Services" or TabName == "Supply" or TabName == "Transport" or TabName == "Zones")
	local hasConcrete = TabSections[TabName] ~= nil

	if not isMajor then
		local parentMajor = SECTION_TO_MAJOR[TabName]
		if parentMajor == "Supply" then
			BE_TabChanged:Fire("hub", TabName)  -- "Water" or "Power"
		end
	end

	CurrentTabName = TabName

	for sectionName, uiSection in pairs(TabSections) do
		uiSection.Visible = (sectionName == TabName)
	end

	if UI.Enabled then
		if (not isMajor) and RV_SECTIONS[TabName] then
			BuildMenu.ShowZoneCategory(TabName)
		else
			_activeCategory = nil
			_refreshCategoryVisibility()
			RangeVisualsClient.hideAll()
		end
	else
		_activeCategory = nil
		_refreshCategoryVisibility()
		RangeVisualsClient.hideAll()
	end

	if isMajor then
		local wasMajor = MajorCurrentTabName  -- <-- ADD

		MajorCurrentTabName = TabName
		UI.main.tabs.services.Background.BackgroundColor3  = (MajorCurrentTabName == "Services")  and Color3.fromRGB(100,100,100) or Color3.fromRGB(0,0,0)
		UI.main.tabs.supply.Background.BackgroundColor3    = (MajorCurrentTabName == "Supply")    and Color3.fromRGB(100,100,100) or Color3.fromRGB(0,0,0)
		UI.main.tabs.transport.Background.BackgroundColor3 = (MajorCurrentTabName == "Transport") and Color3.fromRGB(100,100,100) or Color3.fromRGB(0,0,0)
		UI.main.tabs.zones.Background.BackgroundColor3     = (MajorCurrentTabName == "Zones")     and Color3.fromRGB(100,100,100) or Color3.fromRGB(0,0,0)

		-- NEW: notify onboarding when the major tab actually changed
		if wasMajor ~= MajorCurrentTabName then
			BE_TabChanged:Fire("major", MajorCurrentTabName)
		end
	end

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

	if TabName == "Water" or TabName == "Power" then
		RangeVisualsClient.hideAll()
	else
		if _activeCategory then
			RangeVisualsClient.applyCategory(_activeCategory)
			RangeVisualsClient.debugDump()
		end
	end

	if typeof(_refreshCategoryVisibility) == "function" then
		_refreshCategoryVisibility()
	end
	_updatePulses()
end

function BuildMenu.OnShow()
	if UI.Enabled then return end
	local disableDeleteModeEvent = ensureDisableDeleteModeEvent()
	if disableDeleteModeEvent then
		disableDeleteModeEvent:Fire()
	end
	UI.Enabled = true
	SetPlayerZonesVisible(true)
	_activeCategory = nil
	_refreshCategoryVisibility()
	game:GetService("GamepadService"):EnableGamepadCursor(nil)
	task.defer(_updatePulses)
end

function BuildMenu.OnHide()
	if not UI.Enabled then return end
	UI.Enabled = false
	_stopAllPulses()
	local disableBuildModeEvent = BE:FindFirstChild("DisableBuildMode")
	if disableBuildModeEvent then
		disableBuildModeEvent:Fire()
	end
	SetPlayerZonesVisible(false)
	SetPowerLinesZonesVisible(false)
	SetWaterPipesZonesVisible(false)
	ShowPipesModels(false)
	ShowMetroModels(false)
	ShowBuildingModels(true)
	SetBuildingsNoQuery(false)
	SetBuildingsTransparent(false)
	_activeCategory = nil
	RangeVisualsClient.hideAll()
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
	for k, v in pairs(unlockStatus) do
		UnlockedTypes[k] = v
	end

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

	local gained = {}
	local firstSync = (next(PrevUnlocks) == nil)
	if firstSync then
		for feature, now in pairs(unlockStatus) do
			PrevUnlocks[feature] = now == true
		end
	else
		for feature, now in pairs(unlockStatus) do
			local wasUnlocked = PrevUnlocks[feature] == true
			local isUnlocked  = now == true
			if isUnlocked and not wasUnlocked and shouldAnnounceUnlock(feature) then
				table.insert(gained, feature)
			end
			-- Merge the latest snapshot without dropping keys that were missing in this payload.
			if now ~= nil then
				PrevUnlocks[feature] = isUnlocked
			end
		end
	end

	if #gained > 0 then
		table.sort(gained, function(a: string, b: string)
			local levelA = BuildingLevelRequirement[a] or math.huge
			local levelB = BuildingLevelRequirement[b] or math.huge
			if levelA ~= levelB then
				return levelA < levelB
			end

			local orderA = UnlockOrderIndex[a] or levelA
			local orderB = UnlockOrderIndex[b] or levelB
			if orderA ~= orderB then
				return orderA < orderB
			end

			return tostring(a) < tostring(b)
		end)

		for _, feature in ipairs(gained) do
			PendingByItem[feature] = true
			local btn = FrameButtons[feature]
			if btn then
				ensureButtonNotif(btn).Visible = true
			end
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
		openUnlockModal(gained)
	end
end)

if RE_AirSupportStatus then
	RE_AirSupportStatus.OnClientEvent:Connect(function(isUnlocked: boolean)
		HasAirport = isUnlocked
		UpdateAirportButton()
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
	if not isUnlocked then
		CloseBusDepotGUI()
	end
end)

function BuildMenu.Init()
	RangeVisualsClient.init()
	RangeVisualsClient.debugDump()
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

	UserInputService.InputBegan:Connect(function(InputObject, GameProcessedEvent)
		if not UI.Enabled then return end
		if GameProcessedEvent then return end

		if InputObject.KeyCode == Enum.KeyCode.ButtonB then
			SoundController.PlaySoundOnce("UI", "SmallClick")
			BuildMenu.OnHide()

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

	RunServiceScheduler.onHeartbeat(function(Step)
		if not UI.Enabled then return end

		local UISection = TabSections[CurrentTabName]
		if not UISection then return end

		if UI_TabScroll_Left.GuiState == Enum.GuiState.Press and UI_TabScroll_Right.GuiState ~= Enum.GuiState.Press then
			UISection.CanvasPosition -= Vector2.new(Step * BUTTON_SCROLL_SPEED, 0)

		elseif UI_TabScroll_Left.GuiState ~= Enum.GuiState.Press and UI_TabScroll_Right.GuiState == Enum.GuiState.Press then
			UISection.CanvasPosition += Vector2.new(Step * BUTTON_SCROLL_SPEED, 0)
		end
	end)

	BuildMenu.SetServicesTabNotification(false)
	BuildMenu.SetSupplyTabNotification(false)
	BuildMenu.SetTranspotTabNotification(false)
	BuildMenu.SetZonesTabNotification(false)
	recomputeTopTabBadges()

	-- Sections (unchanged from your version, omitted for brevity if you keep as-is)
	-- NOTE: keep your existing CreateTabSection(...) blocks exactly as you had them.
	-- I haven’t removed or renamed anything there—only the affordability check above changes behavior.

	-- ... [your existing CreateTabSection calls unchanged] ...

	-- (I keep your full list here; leaving as-is to meet your “don’t skip” requirement)
	-- Transport
	CreateTabSection("Transport", {
		{
			itemID = "DirtRoad",
			itemName = "Road",
			price = BalanceEconomy.costPerGrid.DirtRoad,
			image = "rbxassetid://96596073659362",
			onClick = function()
				SetPlayerZonesVisible(true)
				selectZoneEvent:FireServer("DirtRoad")
				pcall(function() RE_OnboardingStepCompleted:FireServer("RoadToolSelected") end)
			end,
		},
		{
			itemID = "BusDepot",
			itemName = "Bus Depot",
			price = BalanceEconomy.costPerGrid.BusDepot,
			image = "rbxassetid://72399175872104",
			onClick = function()
				if HasBusDepot then
					ToggleBusDepotGUI()
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
			price = (BalanceEconomy.costPerGrid.Metro),
			image = "rbxassetid://85773891248333",
			onClick = function()
				ShowMetroModels(false)
				if HasMetro then
					ShowMetroModels(true)
					selectZoneEvent:FireServer("MetroTunnel")
				else
					ShowMetroModels(false)
					selectZoneEvent:FireServer("MetroEntrance")
					BuildMenu.ShowRangeVisualsOnly("MetroEntrance")
				end
			end,
		},
		{
			itemID = "Airport",
			itemName = "Airport",
			price = BalanceEconomy.costPerGrid.Airport,
			image = "rbxassetid://100366195302554",
			onClick = function()
				ShowMetroModels(false)
				if HasAirport then
					ToggleAirportGUI()
					SoundController.PlaySoundOnce("UI", "SmallClick")
					return
				end
				selectZoneEvent:FireServer("Airport")
				BuildMenu.ShowRangeVisualsOnly("Airport")
			end,
		},
	})

	_refreshPulseTargets()
	_updatePulses()

	-- Zones
	CreateTabSection("Zones", {
		{
			itemID = "Residential",
			itemName = "Residential Zone",
			price = BalanceEconomy.costPerGrid.Residential,
			image = "rbxassetid://94434560138213",
			onClick = function()
				selectZoneEvent:FireServer("Residential")
			end,
		},
		{
			itemID = "Commercial",
			itemName = "Commercial Zone",
			price = BalanceEconomy.costPerGrid.Commercial,
			image = "rbxassetid://80804212045512",
			onClick = function()
				selectZoneEvent:FireServer("Commercial")
			end,
		},
		{
			itemID = "Industrial",
			itemName = "Industrial Zone",
			price = BalanceEconomy.costPerGrid.Industrial,
			image = "rbxassetid://81164152585346",
			onClick = function()
				selectZoneEvent:FireServer("Industrial")
			end,
		},
		{
			itemID = "ResDense",
			itemName = "Dense Residential Zone",
			price = BalanceEconomy.costPerGrid.ResDense,
			image = "rbxassetid://111951665644294",
			onClick = function()
				selectZoneEvent:FireServer("ResDense")
			end,
		},
		{
			itemID = "CommDense",
			itemName = "Dense Commercial Zone",
			price = BalanceEconomy.costPerGrid.CommDense,
			image = "rbxassetid://133436787771849",
			onClick = function()
				selectZoneEvent:FireServer("CommDense")
			end,
		},
		{
			itemID = "IndusDense",
			itemName = "Dense Industrial Zone",
			price = BalanceEconomy.costPerGrid.IndusDense,
			image = "rbxassetid://139640185589881",
			onClick = function()
				selectZoneEvent:FireServer("IndusDense")
			end,
		},
	})

	-- Services (hub)
	CreateTabSection("Services", {
		{ itemName = "Leisure",   image = "rbxassetid://113537788739611", onClick = function() BuildMenu.SetTab("Leisure") end, },
		{ itemName = "Fire Dept", image = "rbxassetid://116690108033034", onClick = function() BuildMenu.SetTab("Fire") end, },
		{ itemName = "Police",    image = "rbxassetid://138433123584716", onClick = function() BuildMenu.SetTab("Police") end, },
		{ itemName = "Health",    image = "rbxassetid://133504700689023", onClick = function() BuildMenu.SetTab("Health") end, },
		{ itemName = "Education", image = "rbxassetid://134842512535450", onClick = function() BuildMenu.SetTab("Education") end, },
		{ itemName = "Sports",    image = "rbxassetid://100131265691612", onClick = function() BuildMenu.SetTab("Sports") end, },
		{ itemName = "Landmarks", image = "rbxassetid://120327423932825", onClick = function() BuildMenu.SetTab("Landmarks") end, },
	})

	-- Supply (hub)
	CreateTabSection("Supply", {
		{ itemName = "Power", image = "rbxassetid://82323091054475", onClick = function() BuildMenu.SetTab("Power") end, },
		{ itemName = "Water", image = "rbxassetid://88752537536614", onClick = function() BuildMenu.SetTab("Water") end, },
	})

	-- Education
	CreateTabSection("Education", {
		{
			itemID = "PrivateSchool",
			itemName = "PrivateSchool",
			price = BalanceEconomy.costPerGrid.PrivateSchool,
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
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Education.Museum,
			onClick = function()
				selectZoneEvent:FireServer("Museum")
				BuildMenu.ShowRangeVisualsOnly("Museum")
			end,
		},
	})

	-- Fire
	CreateTabSection("Fire", {
		{
			itemID = "FireDept",
			itemName = "Fire Depth",
			price = BalanceEconomy.costPerGrid.FireDept,
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
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Fire.FirePrecinct,
			onClick = function()
				selectZoneEvent:FireServer("FirePrecinct")
				BuildMenu.ShowRangeVisualsOnly("FirePrecinct")
			end,
		},
	})

	-- Health
	CreateTabSection("Health", {
		{
			itemID = "SmallClinic",
			itemName = "Small Clinic",
			price = BalanceEconomy.costPerGrid.SmallClinic,
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
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Health["Major Hospital"],
			onClick = function()
				selectZoneEvent:FireServer("MajorHospital")
				BuildMenu.ShowRangeVisualsOnly("MajorHospital")
			end,
		},
	})

	-- Landmarks
	CreateTabSection("Landmarks", {
		{
			itemID = "FerrisWheel",
			itemName = "Ferris Wheel",
			price = BalanceEconomy.costPerGrid.FerrisWheel,
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
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Landmark["CN Tower"],
			onClick = function()
				selectZoneEvent:FireServer("CNTower")
				BuildMenu.ShowRangeVisualsOnly("CNTower")
			end,
		},
		{
			itemID = "StatueOfLiberty",
			itemName = "Statue of Liberty",
			priceInRobux = "StatueOfLiberty",
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
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Landmark["Eiffel Tower"],
			onClick = function()
				selectZoneEvent:FireServer("EiffelTower")
				BuildMenu.ShowRangeVisualsOnly("EiffelTower")
			end,
		},
	})

	-- Leisure
	CreateTabSection("Leisure", {
		{ itemName = "Flags", image = "rbxassetid://135306019964679", onClick = function() BuildMenu.SetTab("Flags") end, },
		{
			itemID = "Church",
			itemName = "Church",
			price = BalanceEconomy.costPerGrid.Church,
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
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Leisure["Movie Theater"],
			onClick = function()
				selectZoneEvent:FireServer("MovieTheater")
				BuildMenu.ShowRangeVisualsOnly("MovieTheater")
			end,
		},
	})

	-- Police
	CreateTabSection("Police", {
		{
			itemID = "PoliceDept",
			itemName = "Police Dept",
			price = BalanceEconomy.costPerGrid.PoliceDept,
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
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Police["Courthouse"],
			onClick = function()
				selectZoneEvent:FireServer("Courthouse")
				BuildMenu.ShowRangeVisualsOnly("Courthouse")
			end,
		},
	})

	-- Flags
	CreateTabSection("Flags", _flagsChoices())

	-- Power
	CreateTabSection("Power", {
		{
			itemID = "PowerLines",
			itemName = "Power Lines",
			price = BalanceEconomy.costPerGrid.PowerLines,
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Power.Default.Decorations.PowerLines,
			onClick = function()
				selectZoneEvent:FireServer("PowerLines")
			end,
		},
		{
			itemID = "WindTurbine",
			itemName = "Wind Turbine",
			price = BalanceEconomy.costPerGrid.WindTurbine,
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
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Power["Geothermal Power Plant"],
			onClick = function()
				selectZoneEvent:FireServer("GeothermalPowerPlant")
			end,
		},
		{
			itemID = "NuclearPowerPlant",
			itemName = "Nuclear Power Plant",
			priceInRobux = "NuclearPowerPlant",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Power["Nuclear Power Plant"],
			onClick = function()
				selectZoneEvent:FireServer("NuclearPowerPlant")
			end,
		},
	})

	-- Sports
	CreateTabSection("Sports", {
		{
			itemID = "SkatePark",
			itemName = "Skate Park",
			price = BalanceEconomy.costPerGrid.SkatePark,
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
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Sports["Soccer Stadium"],
			onClick = function()
				selectZoneEvent:FireServer("SoccerStadium")
				BuildMenu.ShowRangeVisualsOnly("SoccerStadium")
			end,
		},
		{
			itemID = "BasketballStadium",
			itemName = "Basketball Stadium",
			price = BalanceEconomy.costPerGrid.BasketballStadium,
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Sports["Basketball Stadium"],
			onClick = function()
				selectZoneEvent:FireServer("BasketballStadium")
				BuildMenu.ShowRangeVisualsOnly("BasketballStadium")
			end,
		},
		{
			itemID = "FootballStadium",
			itemName = "Football Stadium",
			priceInRobux = "FootballStadium",
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Sports["Football Stadium"],
			onClick = function()
				selectZoneEvent:FireServer("FootballStadium")
				BuildMenu.ShowRangeVisualsOnly("FootballStadium")
			end,
		},
	})

	-- Water
	CreateTabSection("Water", {
		{
			itemID = "WaterPipe",
			itemName = "Water Pipes",
			price = BalanceEconomy.costPerGrid.WaterPipe,
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Water.WaterPipe,
			onClick = function()
				selectZoneEvent:FireServer("WaterPipe")
			end,
		},
		{
			itemID = "WaterTower",
			itemName = "Water Tower",
			price = BalanceEconomy.costPerGrid.WaterTower,
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Water["Water Tower"],
			onClick = function()
				selectZoneEvent:FireServer("WaterTower")
			end,
		},
		{
			itemID = "WaterPlant",
			itemName = "Water Plant",
			price = BalanceEconomy.costPerGrid.WaterPlant,
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Water["Water Plant"],
			onClick = function()
				selectZoneEvent:FireServer("WaterPlant")
			end,
		},
		{
			itemID = "PurificationWaterPlant",
			itemName = "Purification Water Plant",
			price = BalanceEconomy.costPerGrid.PurificationWaterPlant,
			modelref = ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default.Water["Purification Water Plant"],
			onClick = function()
				selectZoneEvent:FireServer("PurificationWaterPlant")
			end,
		},
		{
			itemID = "MolecularWaterPlant",
			itemName = "MolecularWaterPlant",
			priceInRobux = "MolecularWaterPlant",
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

	UI_Exit.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		BuildMenu.Toggle()
	end)

	if UI.main and UI.main.tabs and UI.main.tabs.transport and UI.main.tabs.transport.Background then
		UI.main.tabs.transport.Background.AncestryChanged:Connect(function()
			task.defer(function()
				_refreshPulseTargets()
				_updatePulses()
			end)
		end)
	end

	UtilityGUI.VisualMouseInteraction(
		UI_Exit, UI_Exit.TextLabel,
		TweenInfo.new(0.15),
		{ Size = UDim2.fromScale(1.25, 1.25) },
		{ Size = UDim2.fromScale(0.5, 0.5) }
	)

	-- [CHANGED] single handler: update both level and balance
	UIUpdate_RemoteEvent.OnClientEvent:Connect(function(data)
		if not data then return end
		if data.level ~= nil then
			CachedLevel = tonumber(data.level) or 0
		end
		-- balance may be a number or an abbreviated string; normalize to number
		if data.balance ~= nil then
			if type(data.balance) == "string" then
				CachedBalance = parseAbbrev(data.balance)
			else
				CachedBalance = tonumber(data.balance) or 0
			end
		end
		UpdateLocks()
		UpdateBusDepotButton()
		UpdateAirportButton()
		UpdateMetroButton()
	end)

	-- initialize from save if present
	local save = PlayerDataController.GetSaveFileData()
	if save then
		if save.cityLevel ~= nil then
			CachedLevel = tonumber(save.cityLevel) or 0
		end
		if save.balance ~= nil then
			if type(save.balance) == "string" then
				CachedBalance = parseAbbrev(save.balance)
			else
				CachedBalance = tonumber(save.balance) or 0
			end
		end
	end

	UpdateLocks()
	UpdateBusDepotButton()
	UpdateAirportButton()
	UpdateMetroButton()
end

RE_PlayerDataChanged_ExclusiveLocations.OnClientEvent:Connect(function(ExclusiveLocationName: string, Amount: number)
	local Choice = FrameButtons[ExclusiveLocationName]
	if Choice and Choice:FindFirstChild("FreeAmounts") then
		Choice.FreeAmounts.Text = "x"..Amount
	end
end)

return BuildMenu
