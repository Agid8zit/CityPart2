-- StarterPlayerScripts/OnboardingController.client.lua
-- Single-source-of-truth for onboarding UI pulses, arrows, and BuildMenu gating.
-- Minimal, defensive, and race-safe. (Localization-first: NO literal UI strings here.)

----------------------------
-- Services / Short-hands --
----------------------------
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local LocalPlayer       = Players.LocalPlayer
local PlayerGui         = LocalPlayer:WaitForChild("PlayerGui")

local currentGateId: string? = nil

----------------
-- Debugging  --
----------------
local DEBUG = false
local function dbg(...)
	if not DEBUG then return end
	local n = select("#", ...)
	if n == 0 then return end
	local s = (type((...)) == "string" and n > 1) and (string.format(...)) or table.concat({ ... }, " ")
	print("[OB] " .. tostring(s))
end

----------------
-- Dependencies
----------------
local UITargetRegistry = require(ReplicatedStorage.Scripts.UI.UITargetRegistry)

---------------
-- Structure --
---------------
local function ensureFolder(parent, name)
	local f = parent:FindFirstChild(name)
	if f and f:IsA("Folder") then return f end
	local nf = Instance.new("Folder")
	nf.Name = name
	nf.Parent = parent
	return nf
end

local Events  = ensureFolder(ReplicatedStorage, "Events")
local RE      = ensureFolder(Events, "RemoteEvents")
local BE      = ensureFolder(Events, "BindableEvents")
local BFOLDER = ensureFolder(Events, "BindableFunctions")

-- Remotes
local RE_Toggle     = RE:WaitForChild("OnboardingToggle")
local StateChanged  = RE:WaitForChild("OnboardingStateChanged")
local StepCompleted = RE:WaitForChild("OnboardingStepCompleted")
local DisplayGrid   = RE:WaitForChild("DisplayGrid")

-- Bindables (owned here)
local function ensureBindable(className, name)
	local obj = BE:FindFirstChild(name)
	if obj then return obj end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = BE
	return inst
end

local BF_CheckItemAllowed = ensureBindable("BindableFunction", "OBCheckItemAllowed")
local BE_PulseItem        = ensureBindable("BindableEvent", "OBPulseItem")
local BE_StopPulseItem    = ensureBindable("BindableEvent", "OBStopPulseItem")
local BE_GridGuard        = ensureBindable("BindableEvent", "OBGridGuard")
local BE_GuardFB          = ensureBindable("BindableEvent", "OBGuardFeedback")
local BE_Toggle           = ensureBindable("BindableEvent", "OnboardingToggle")

-- Bindables (owned by BuildMenu; optional)
local BE_TabChanged = BE:FindFirstChild("OBBuildMenuTabChanged")
local BF_GetMajor   = BFOLDER:FindFirstChild("OBBuildMenuGetMajorTab")
local BF_GetHub     = BFOLDER:FindFirstChild("OBBuildMenuGetHub")

-----------------
-- Notifications
-----------------
local NotificationGui do
	-- Deterministically inject ReplicatedStorage.Localization.Localizing as the loader for Notifications.
	local ok, mod = pcall(function()
		local root  = PlayerGui:WaitForChild("Notifications", 3)
		local logic = root and (root:FindFirstChild("Logic") or root:FindFirstChildOfClass("ModuleScript"))
		local m = logic and require(logic) or nil

		if m and type(m) == "table" and type(m.Init) == "function" and root then
			local locFolder  = ReplicatedStorage:FindFirstChild("Localization")
			local localizing = locFolder and locFolder:FindFirstChild("Localizing")
			if localizing and localizing:IsA("ModuleScript") then
				pcall(m.Init, root, { loader = localizing })
			else
				pcall(m.Init, root)
			end
		end

		-- API compat: alias ClearSingleton if only ClearChannel exists.
		if m and type(m) == "table" then
			if type(m.ClearSingleton) ~= "function" and type(m.ClearChannel) == "function" then
				m.ClearSingleton = m.ClearChannel
			end
		end

		return m
	end)

	if ok and type(mod) == "table" then
		NotificationGui = mod
	else
		NotificationGui = {
			ShowArrowAt     = function() return false end,
			HideArrow       = function() end,
			ShowArrowBounce = function() return false end,
			ShowSingleton   = function() end,
			ClearSingleton  = function() end,
		}
	end
end

-- ====== Localization keys & singleton channels ======
local LANG = {
	-- (Legacy example keys kept as-is)
	OB1_ROAD_SELECT    = "OB_SelectRoad",
	OB1_ROAD_SELECT_OK = "OB_SelectRoad_Done",

	-- Barrage 2 (existing)
	OB2_BEGIN          = "OB2_Begin",
	OB2_COMPLETE       = "OB2_Complete",
	OB2_WATER_DEFICIT  = "OB2_WaterDeficit",
	OB2_CONNECT_WATER  = "OB2_ConnectWater",
	OB2_POWER_DEFICIT  = "OB2_PowerDeficit",
	OB2_CONNECT_POWER  = "OB2_ConnectPower",

	-- Barrage 1 (new, step-by-step + banners)
	OB1_BEGIN          = "OB1_Begin",
	OB1_COMPLETE       = "OB1_Complete",

	OB1_S1_ROAD_HINT   = "OB1_S1_Road_Hint",
	OB1_S1_ROAD_DONE   = "OB1_S1_Road_Done",

	OB1_S2_RES_HINT    = "OB1_S2_Residential_Hint",
	OB1_S2_RES_DONE    = "OB1_S2_Residential_Done",

	OB1_S3_TOWER_HINT  = "OB1_S3_WaterTower_Hint",
	OB1_S3_TOWER_DONE  = "OB1_S3_WaterTower_Done",

	OB1_S4_PIPEA_HINT  = "OB1_S4_WaterPipe_A_Hint",
	OB1_S4_PIPEA_DONE  = "OB1_S4_WaterPipe_A_Done",

	OB1_S5_PIPEB_HINT  = "OB1_S5_WaterPipe_B_Hint",
	OB1_S5_PIPEB_DONE  = "OB1_S5_WaterPipe_B_Done",

	OB1_S6_TURB_HINT   = "OB1_S6_WindTurbine_Hint",
	OB1_S6_TURB_DONE   = "OB1_S6_WindTurbine_Done",

	OB1_S7_LINEA_HINT  = "OB1_S7_PowerLines_A_Hint",
	OB1_S7_LINEA_DONE  = "OB1_S7_PowerLines_A_Done",

	OB1_S8_LINEB_HINT  = "OB1_S8_PowerLines_B_Hint",
	OB1_S8_LINEB_DONE  = "OB1_S8_PowerLines_B_Done",

	OB1_S9_ROAD2_HINT  = "OB1_S9_Road2_Hint",
	OB1_S9_ROAD2_DONE  = "OB1_S9_Road2_Done",

	OB1_S10_COMM_HINT  = "OB1_S10_Commercial_Hint",
	OB1_S10_COMM_DONE  = "OB1_S10_Commercial_Done",

	-- Generic routing hints (tabs/hubs)
	OB_OPEN_BUILD_MENU     = "OB_OpenBuildMenu",
	OB_OPEN_TRANSPORT_TAB  = "OB_OpenTransportTab",
	OB_OPEN_ZONES_TAB      = "OB_OpenZonesTab",
	OB_OPEN_SUPPLY_TAB     = "OB_OpenSupplyTab",
	OB_OPEN_SERVICES_TAB   = "OB_OpenServicesTab",
	OB_OPEN_WATER_HUB      = "OB_OpenWaterHub",
	OB_OPEN_POWER_HUB      = "OB_OpenPowerHub",

	-- Barrage 3 (Industrial placement + connectivity)
	OB3_BEGIN                 = "OB3_Begin",
	OB3_Industrial_Hint       = "OB3_Industrial_Hint",
	OB3_Industrial_Done       = "OB3_Industrial_Done",
	OB3_ConnectRoad           = "OB3_ConnectRoad",
	OB3_ConnectRoadNetwork    = "OB3_ConnectRoadNetwork",
	OB3_ConnectWater          = "OB3_ConnectWater",
	OB3_ConnectPower          = "OB3_ConnectPower",
	OB3_Complete              = "OB3_Complete",
}

local OB1_CHANNEL = "OB1"
local OB2_CHANNEL = "OB2"
local OB3_CHANNEL = "OB3"

local DUR = {
	HINT     = 5,
	DONE     = 2,
	BEGIN    = 5,
	COMPLETE = 3,
	ROUTE    = 4,
}

local function showLangInChannel(channel: string, langKey: string, duration: number?)
	if NotificationGui and type(NotificationGui.ShowSingleton) == "function" then
		pcall(NotificationGui.ShowSingleton, channel, langKey, { duration = duration or 4 })
	end
end

local function clearChannel(channel: string)
	if NotificationGui and type(NotificationGui.ClearSingleton) == "function" then
		pcall(NotificationGui.ClearSingleton, channel)
	end
end

local function showOB1(key, dur) showLangInChannel(OB1_CHANNEL, key, dur or DUR.HINT) end
local function showB2(key,  dur) showLangInChannel(OB2_CHANNEL, key,  dur or DUR.HINT) end
local function showB3(key,  dur) showLangInChannel(OB3_CHANNEL, key,  dur or DUR.HINT) end
local function clearB2() clearChannel(OB2_CHANNEL) end
local function clearB3() clearChannel(OB3_CHANNEL) end

-- Step → keys map
local OB1_STEP_HINT_KEYS = {
	[1]  = LANG.OB1_S1_ROAD_HINT,
	[2]  = LANG.OB1_S2_RES_HINT,
	[3]  = LANG.OB1_S3_TOWER_HINT,
	[4]  = LANG.OB1_S4_PIPEA_HINT,
	[5]  = LANG.OB1_S5_PIPEB_HINT,
	[6]  = LANG.OB1_S6_TURB_HINT,
	[7]  = LANG.OB1_S7_LINEA_HINT,
	[8]  = LANG.OB1_S8_LINEB_HINT,
	[9]  = LANG.OB1_S9_ROAD2_HINT,
	[10] = LANG.OB1_S10_COMM_HINT,
}
local OB1_STEP_DONE_KEYS = {
	[1]  = LANG.OB1_S1_ROAD_DONE,
	[2]  = LANG.OB1_S2_RES_DONE,
	[3]  = LANG.OB1_S3_TOWER_DONE,
	[4]  = LANG.OB1_S4_PIPEA_DONE,
	[5]  = LANG.OB1_S5_PIPEB_DONE,
	[6]  = LANG.OB1_S6_TURB_DONE,
	[7]  = LANG.OB1_S7_LINEA_DONE,
	[8]  = LANG.OB1_S8_LINEB_DONE,
	[9]  = LANG.OB1_S9_ROAD2_DONE,
	[10] = LANG.OB1_S10_COMM_DONE,
}

local MAJOR_HINT_KEYS = {
	Transport = LANG.OB_OPEN_TRANSPORT_TAB,
	Zones     = LANG.OB_OPEN_ZONES_TAB,
	Supply    = LANG.OB_OPEN_SUPPLY_TAB,
	Services  = LANG.OB_OPEN_SERVICES_TAB,
}
local HUB_HINT_KEYS = { Water = LANG.OB_OPEN_WATER_HUB, Power = LANG.OB_OPEN_POWER_HUB }

----------------
-- Canonicals --
----------------
local MODE_TO_ITEM = { Road = "DirtRoad" }
local function canonItem(x)
	if x == nil then return nil end
	local s = tostring(x); return MODE_TO_ITEM[s] or s
end

local ITEM_TO_MAJOR = {
	-- Transport
	DirtRoad="Transport", BusDepot="Transport", MetroEntrance="Transport", MetroTunnel="Transport", Airport="Transport",
	-- Zones
	Residential="Zones", Commercial="Zones", Industrial="Zones",
	ResDense="Zones", CommDense="Zones", IndusDense="Zones",
	-- Supply (Power)
	PowerLines="Supply", WindTurbine="Supply", SolarPanels="Supply", CoalPowerPlant="Supply",
	GasPowerPlant="Supply", GeothermalPowerPlant="Supply", NuclearPowerPlant="Supply",
	-- Supply (Water)
	WaterPipe="Supply", WaterTower="Supply", WaterPlant="Supply", PurificationWaterPlant="Supply", MolecularWaterPlant="Supply",
	-- Services
	PrivateSchool="Services", MiddleSchool="Services", Museum="Services", NewsStation="Services",
	FireDept="Services", FireStation="Services", FirePrecinct="Services",
	PoliceDept="Services", PoliceStation="Services", PolicePrecinct="Services", Courthouse="Services",
	SmallClinic="Services", LocalHospital="Services", CityHospital="Services", MajorHospital="Services",
	FerrisWheel="Services", GasStation="Services", Bank="Services", TechOffice="Services",
	NationalCapital="Services", Obelisk="Services", ModernSkyscraper="Services",
	EmpireStateBuilding="Services", SpaceNeedle="Services", WorldTradeCenter="Services",
	CNTower="Services", StatueOfLiberty="Services", EiffelTower="Services",
	Church="Services", Mosque="Services", ShintoTemple="Services", HinduTemple="Services",
	BuddhaStatue="Services", Hotel="Services", MovieTheater="Services",
	SkatePark="Services", TennisCourt="Services", PublicPool="Services",
	ArcheryRange="Services", BasketballCourt="Services", GolfCourse="Services",
	SoccerStadium="Services", BasketballStadium="Services", FootballStadium="Services",
	["Flag:*"]="Services",
}
local MAJOR_TO_KEY = { Transport="BM_Transport", Zones="BM_Zones", Supply="BM_Supply", Services="BM_Services" }

local ITEM_TO_HUB = {
	PowerLines="Power", WindTurbine="Power", SolarPanels="Power",
	CoalPowerPlant="Power", GasPowerPlant="Power", GeothermalPowerPlant="Power", NuclearPowerPlant="Power",
	WaterPipe="Water", WaterTower="Water", WaterPlant="Water", PurificationWaterPlant="Water", MolecularWaterPlant="Water",
}
local HUB_KEY_CANDIDATES = {
	Supply = {
		Power = { "BM_Power", "BM_Supply_Power", "BMSupply_Power", "BMHub_Power", "BM_PowerHub", "BM_Supply_PowerTab" },
		Water = { "BM_Water", "BM_Supply_Water", "BMSupply_Water", "BMHub_Water", "BM_WaterHub", "BM_Supply_WaterTab" },
	}
}

local function majorForItem(id)
	if not id then return nil end
	if string.sub(id,1,5)=="Flag:" then return ITEM_TO_MAJOR["Flag:*"] end
	return ITEM_TO_MAJOR[id]
end
local function hubForItem(id) return id and ITEM_TO_HUB[id] end

-------------------------
-- Flow / Guard state  --
-------------------------
local OnboardingFlow
local function getFlowItem()
	if not OnboardingFlow then
		local ok, mod = pcall(function() return require(ReplicatedStorage.Scripts.Onboarding.OnboardingFlow) end)
		if ok then OnboardingFlow = mod end
	end
	if OnboardingFlow and type(OnboardingFlow.GetState)=="function" then
		local st = OnboardingFlow.GetState()
		return st and st.current and canonItem(st.current.item or st.current.mode) or nil
	end
	return nil
end

local guardSeq, guardIdx, guardEver, activeSeq = {}, 0, false, nil
local function guardCurrentItem()
	if guardIdx ~= 0 and guardSeq[guardIdx] then
		return canonItem(guardSeq[guardIdx].mode or guardSeq[guardIdx].item)
	end
	return nil
end

-- global tool memory (avoids typed locals)
_G.OB_CurrentTool = _G.OB_CurrentTool

----------------------
-- Pulse primitives --
----------------------
local guardPulseItem, serverPulseItem = nil, nil
local function Pulse(item)  dbg("Pulse ->", item);  BE_PulseItem:Fire(item) end
local function Stop(item)   dbg("Stop ->", item);   BE_StopPulseItem:Fire(item) end

-----------------------
-- UI Target Helpers --
-----------------------
local POS_A, POS_B, SIZE, ROT = UDim2.new(0.501,0,0.841,0), UDim2.new(0.501,0,0.875,0), UDim2.new(0.053,0,0.1,0), 180
local lastArrowKey, arrowOwner = nil, nil

local function getUITarget(key)
	local inst = UITargetRegistry.Get(key)
	if inst and inst:IsA("GuiObject") then return inst end
	local bf = BFOLDER:FindFirstChild("OB_GetUITarget")
	if bf and bf:IsA("BindableFunction") then
		local ok, alt = pcall(function() return bf:Invoke(key) end)
		if ok and alt and alt:IsA("GuiObject") then return alt end
	end
	return nil
end

local function HideArrow() pcall(NotificationGui.HideArrow) end

local function ShowArrowAtKey(key, offset)
	local target = getUITarget(key)
	if target then
		local ok, placed = pcall(NotificationGui.ShowArrowAt, target, offset or UDim2.new(0,0,-0.12,0))
		if ok and placed == true then
			return true
		end
	end
	local ok2, bounced = pcall(NotificationGui.ShowArrowBounce, POS_A, POS_B, SIZE, ROT)
	return ok2 and bounced == true
end

local function ShowArrowAtKeyTracked(key, offset)
	lastArrowKey = key
	if ShowArrowAtKey(key, offset) then return end
	local myKey = key
	local conn; conn = UITargetRegistry.Changed():Connect(function(chKey)
		if chKey == myKey then
			ShowArrowAtKey(myKey, offset)
			if conn then conn:Disconnect() end
		end
	end)
end

-------------------
-- Pulse Manager  --
-------------------
local PULSE_GREEN = Color3.fromRGB(0,255,140)
local pulseByKey, wantPulse, arrowOffset = {}, {}, {}
local BM_LocalArrow = { gui=nil, ownerKey=nil, conn=nil, token=0 }

local function ensureStroke(gui)
	local stroke = gui:FindFirstChild("_OBStroke")
	if not (stroke and stroke:IsA("UIStroke")) then
		stroke = gui:FindFirstChildOfClass("UIStroke")
		if not (stroke and stroke:IsA("UIStroke")) then
			stroke = Instance.new("UIStroke")
			stroke.Name = "_OBStroke"
			stroke.Thickness = 2
			stroke.Color = Color3.new(1,1,1)
			stroke.Parent = gui
		end
	end
	if stroke:GetAttribute("_OB_OrigR") == nil then
		local c = stroke.Color
		stroke:SetAttribute("_OB_OrigR", c.R)
		stroke:SetAttribute("_OB_OrigG", c.G)
		stroke:SetAttribute("_OB_OrigB", c.B)
	end
	return stroke
end
local function origColor(stroke)
	local r = stroke:GetAttribute("_OB_OrigR")
	local g = stroke:GetAttribute("_OB_OrigG")
	local b = stroke:GetAttribute("_OB_OrigB")
	if type(r)=="number" and type(g)=="number" and type(b)=="number" then
		return Color3.new(r,g,b)
	end
	return Color3.new(1,1,1)
end

local function attachLocalBMArrowFor(targetGui: GuiObject, key: string)
	local bm = PlayerGui:FindFirstChild("BuildMenu")
	local obArrow = bm and bm:FindFirstChild("OnboardingArrow", true)
	if not (obArrow and obArrow:IsA("GuiObject")) then return end
	if BM_LocalArrow.conn then BM_LocalArrow.conn:Disconnect() end
	BM_LocalArrow.token += 1
	BM_LocalArrow.ownerKey = key
	BM_LocalArrow.gui = obArrow
	obArrow.Visible = true
	obArrow.Rotation = 180
	pcall(function() obArrow.AnchorPoint = Vector2.new(0.5, 1) end)
	obArrow.ZIndex = math.max((targetGui.ZIndex or 1) + 10, obArrow.ZIndex or 1)
	local my = BM_LocalArrow.token
	BM_LocalArrow.conn = RunService.RenderStepped:Connect(function()
		if BM_LocalArrow.token ~= my then return end
		if not (obArrow.Parent and targetGui.Parent) then return end
		local pos, size = targetGui.AbsolutePosition, targetGui.AbsoluteSize
		obArrow.Position = UDim2.fromOffset(pos.X + size.X * 0.5, pos.Y - 2)
	end)
end

local UIPulse = {}
function UIPulse.start(key, opts)
	local target = getUITarget(key); if not target then return false end
	local rec = pulseByKey[key]
	if type(key) == "string" and string.sub(key,1,3) == "BM_" then
		attachLocalBMArrowFor(target, key)
	end
	if rec and rec.running then return true end
	local stroke = ensureStroke(target)
	local token  = (rec and rec.token or 0) + 1
	rec = { stroke=stroke, token=token, running=true, tween=nil }
	pulseByKey[key] = rec
	local cA = (opts and opts.colorA) or PULSE_GREEN
	local cB = (opts and opts.colorB) or origColor(stroke)
	local tA = (opts and opts.tA) or 0.5
	local tB = (opts and opts.tB) or 0.6
	task.spawn(function()
		while pulseByKey[key] and pulseByKey[key].token == token do
			rec.tween = TweenService:Create(stroke, TweenInfo.new(tA, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Color=cA})
			rec.tween:Play(); rec.tween.Completed:Wait()
			if not (pulseByKey[key] and pulseByKey[key].token == token) then break end
			rec.tween = TweenService:Create(stroke, TweenInfo.new(tB, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {Color=cB})
			rec.tween:Play(); rec.tween.Completed:Wait()
		end
		pcall(function() stroke.Color = origColor(stroke) end)
		rec.tween = nil
	end)
	return true
end
function UIPulse.stop(key)
	local rec = pulseByKey[key]; if not rec then return end
	rec.token += 1; rec.running = false
	if rec.tween then pcall(function() rec.tween:Cancel() end) end
	if rec.stroke then pcall(function() rec.stroke.Color = origColor(rec.stroke) end) end
	pulseByKey[key] = nil
	if type(key) == "string" and string.sub(key,1,3) == "BM_" then
		if BM_LocalArrow.ownerKey == key then
			if BM_LocalArrow.conn then BM_LocalArrow.conn:Disconnect() end
			BM_LocalArrow.conn = nil
			if BM_LocalArrow.gui then BM_LocalArrow.gui.Visible = false end
			BM_LocalArrow.ownerKey = nil
			BM_LocalArrow.token += 1
		end
	end
end

-----------------------
-- Gates & UI wiring --
-----------------------
local function buildMenu()
	local bm = PlayerGui:FindFirstChild("BuildMenu")
	return bm and bm:IsA("ScreenGui") and bm or nil
end

local KEY_GATES = {
	BuildButton = function()
		local bm = buildMenu()
		return not (bm and bm.Enabled)
	end,
}
local function gateAllows(key)
	if type(key)=="string" and string.sub(key,1,3)=="BM_" then
		local bm = buildMenu()
		return bm and bm.Enabled == true
	end
	local g = KEY_GATES[key]; if not g then return true end
	local ok, allowed = pcall(g)
	return ok and allowed == true
end

local function requestPulseAndArrow(key, offset)
	if not _G.OB_ENABLED then return end
	wantPulse[key]   = true
	arrowOffset[key] = offset or UDim2.new(0,0,-0.12,0)
	if gateAllows(key) then
		UIPulse.start(key)
		if arrowOwner ~= key and not (type(key)=="string" and string.sub(key,1,3)=="BM_") then
			ShowArrowAtKeyTracked(key, arrowOffset[key])
			arrowOwner = key
		end
	else
		UIPulse.stop(key)
	end
end

local function clearPulseAndArrow(key)
	wantPulse[key] = nil
	UIPulse.stop(key)
	if arrowOwner == key then HideArrow(); arrowOwner = nil end
end
local function clearBuildMenuPulsesExcept(keep)
	for k in pairs(wantPulse) do
		if type(k)=="string" and string.sub(k,1,3)=="BM_" and k ~= keep then
			clearPulseAndArrow(k)
		end
	end
end
local function clearAllUIPulses()
	for k in pairs(wantPulse) do UIPulse.stop(k) end
	table.clear(wantPulse)
	if BM_LocalArrow.conn then BM_LocalArrow.conn:Disconnect() end
	BM_LocalArrow.conn = nil
	if BM_LocalArrow.gui then BM_LocalArrow.gui.Visible = false end
	BM_LocalArrow.ownerKey = nil
	BM_LocalArrow.token += 1
	HideArrow(); arrowOwner = nil
end

-----------------------
-- BuildMenu helpers --
-----------------------
local function getBMLogic()
	local bm = buildMenu(); if not bm then return nil end
	local ok, mod = pcall(function() return require(bm.Logic) end)
	return ok and mod or nil
end

local function applyGate(allowedItemID)
	-- Cache the canonical gate so we can respect it when the menu opens.
	currentGateId = allowedItemID and canonItem(allowedItemID) or nil

	local mod = getBMLogic()
	if mod and type(mod.ApplyGateVisual) == "function" then
		mod.ApplyGateVisual(currentGateId)
	end
end

local function getCurrentMajor()
	local bf = BF_GetMajor or BFOLDER:FindFirstChild("OBBuildMenuGetMajorTab")
	if bf and bf:IsA("BindableFunction") then
		local ok, cur = pcall(function() return bf:Invoke() end)
		if ok and type(cur)=="string" and cur~="" then return cur end
	end
	return nil
end
local function getCurrentHub(major)
	local bf = BF_GetHub or BFOLDER:FindFirstChild("OBBuildMenuGetHub")
	if bf and bf:IsA("BindableFunction") then
		local ok, hub = pcall(function() return bf:Invoke(major) end)
		if ok and type(hub)=="string" and hub~="" then return hub end
	end
	local mod = getBMLogic()
	if mod then
		if type(mod.GetCurrentHub)=="function" then
			local ok, h = pcall(mod.GetCurrentHub); if ok and type(h)=="string" and h~="" then return h end
		end
		if type(mod.State)=="table" and type(mod.State.hub)=="string" and mod.State.hub~="" then
			return mod.State.hub
		end
	end
	return nil
end
local function resolveHubKey(major, hub)
	local candidates = major and hub and HUB_KEY_CANDIDATES[major] and HUB_KEY_CANDIDATES[major][hub]
	if candidates then
		for _,k in ipairs(candidates) do if getUITarget(k) then return k end end
	end
	return hub and ("BM_"..hub) or nil
end

------------------------
-- Guard router events --
------------------------
local function emitGuard(how, step)
	if step then BE_GridGuard:Fire(how, step) end
end

-- Show a routing hint (tab/hub) for a desired item, based on current BuildMenu state.
local function showRoutingHintsForItemId(id)
	local wantMajor = majorForItem(id)
	local wantHub   = hubForItem(id)
	local curMajor  = getCurrentMajor()
	local curHub    = getCurrentHub(curMajor)

	if wantMajor and curMajor ~= wantMajor then
		local k = MAJOR_HINT_KEYS[wantMajor]
		if k then showOB1(k, DUR.ROUTE) end
	elseif wantHub and curHub ~= wantHub then
		local k = HUB_HINT_KEYS[wantHub]
		if k then showOB1(k, DUR.ROUTE) end
	end
end

-- FIX: allow starting at a supplied resume index (1‑based)
local function GuardStart(seq, resumeAt)
	guardSeq = seq or {}
	if #guardSeq == 0 then
		guardIdx = 0
		return
	end
	local idx = tonumber(resumeAt)
	if idx then
		idx = math.clamp(math.floor(idx), 1, #guardSeq)
	else
		idx = 1
	end
	guardIdx = idx
	emitGuard("start", guardSeq[guardIdx])

	-- Sequence-specific banners + first step hint
	local cur = guardSeq[guardIdx]
	if activeSeq == "barrage1" then
		if guardIdx == 1 then showOB1(LANG.OB1_BEGIN, DUR.BEGIN) end
		if cur then
			local hintKey = OB1_STEP_HINT_KEYS[guardIdx]
			if hintKey then showOB1(hintKey, DUR.HINT) end
			local id = canonItem(cur.mode or cur.item)
			if id then showRoutingHintsForItemId(id) end
		end
	elseif activeSeq == "barrage3" then
		-- B3: Industrial placement hint
		showB3(LANG.OB3_Industrial_Hint, DUR.HINT)
		if cur then
			local id = canonItem(cur.mode or cur.item)
			if id then showRoutingHintsForItemId(id) end
		end
	else
		-- Other sequences default to routing only
		if cur then
			local id = canonItem(cur.mode or cur.item)
			if id then showRoutingHintsForItemId(id) end
		end
	end
end

local function GuardAdvance()
	if guardIdx == 0 then return end
	guardIdx += 1
	if guardSeq[guardIdx] then
		emitGuard("advance", guardSeq[guardIdx])
	else
		BE_GridGuard:Fire("stop"); guardSeq = {}; guardIdx = 0
	end
end

local function GuardCancel()
	if guardIdx ~= 0 then BE_GridGuard:Fire("stop") end
	guardSeq = {}; guardIdx = 0
end

-------------------------------
-- Arrow/Gate main orchestror --
-------------------------------
local hubWatchToken = 0

local function arrowAndGateToCurrentStep()
	-- Prefer the explicit gate (B2/B3), else Barrage‑1 guard/flow.
	local id = currentGateId or guardCurrentItem() or getFlowItem()
	if not id then return end

	applyGate(id)

	if _G.OB_CurrentTool == id then
		clearBuildMenuPulsesExcept(nil)
		HideArrow()
		return
	end

	local wantMajor = majorForItem(id)
	local wantHub   = hubForItem(id)
	local curMajor  = getCurrentMajor()
	local curHub    = getCurrentHub(curMajor)

	local targetKey
	if not wantMajor or curMajor ~= wantMajor then
		targetKey = MAJOR_TO_KEY[wantMajor or "Transport"] or "BM_Transport"
		requestPulseAndArrow(targetKey, UDim2.new(0,0,-0.12,0))
		hubWatchToken += 1
		local my = hubWatchToken
		local want = wantMajor
		task.spawn(function()
			local t0 = os.clock()
			while my == hubWatchToken and os.clock() - t0 < 6 do
				task.wait(0.25)
				if getCurrentMajor() == want then
					arrowAndGateToCurrentStep()
					return
				end
			end
		end)
	else
		if wantHub and curHub ~= wantHub then
			targetKey = resolveHubKey(wantMajor, wantHub) or "BM_Supply"
			requestPulseAndArrow(targetKey, UDim2.new(0,0,-0.12,0))
			hubWatchToken += 1
			local my = hubWatchToken
			task.spawn(function()
				local t0 = os.clock()
				while my == hubWatchToken and os.clock() - t0 < 6 do
					task.wait(0.25)
					if getCurrentHub(wantMajor) == wantHub then
						arrowAndGateToCurrentStep()
						return
					end
				end
			end)
		else
			targetKey = "BM_"..id
			requestPulseAndArrow(targetKey, UDim2.new(0,0,-0.18,0))
		end
	end

	clearBuildMenuPulsesExcept(targetKey)
end

local function clearArrowAndGate()
	applyGate(nil)
	if lastArrowKey then clearPulseAndArrow(lastArrowKey) end
	HideArrow()
end

----------------------------
-- Registry rebind handling
----------------------------
UITargetRegistry.Changed():Connect(function(chKey, inst)
	if wantPulse[chKey] then
		UIPulse.stop(chKey)
		if gateAllows(chKey) then UIPulse.start(chKey) end
	end
end)

------------------------------
-- BuildMenu open/close hook --
------------------------------
local bmOpenHintShown = false

task.defer(function()
	local bm = buildMenu() or PlayerGui:WaitForChild("BuildMenu")
	if not (bm and bm:IsA("ScreenGui")) then return end

	local function apply()
		if not _G.OB_ENABLED then HideArrow(); return end
		if bm.Enabled then
			bmOpenHintShown = false
			local id = currentGateId or guardCurrentItem() or getFlowItem()
			if not id then id = "DirtRoad" end
			applyGate(id)
			if _G.OB_CurrentTool == id then
				clearBuildMenuPulsesExcept(nil)
				HideArrow()
				return
			end
			local wantMajor, wantHub = majorForItem(id), hubForItem(id)
			local curMajor, curHub = getCurrentMajor(), getCurrentHub(getCurrentMajor())
			local key
			if wantMajor and (curMajor ~= wantMajor) then
				key = MAJOR_TO_KEY[wantMajor] or "BM_Transport"
				requestPulseAndArrow(key, UDim2.new(0,0,-0.12,0))
			else
				if wantHub and curHub ~= wantHub then
					key = resolveHubKey(wantMajor or "Supply", wantHub)
					requestPulseAndArrow(key or "BM_Supply", UDim2.new(0,0,-0.12,0))
				else
					key = "BM_"..id
					requestPulseAndArrow(key, UDim2.new(0,0,-0.18,0))
				end
			end
			clearBuildMenuPulsesExcept(key)
		else
			if _G.OB_ENABLED then
				local id = currentGateId or guardCurrentItem() or getFlowItem()
				applyGate(id)
				requestPulseAndArrow("BuildButton", UDim2.new(0,0,-0.12,0))
				if not bmOpenHintShown then
					showOB1(LANG.OB_OPEN_BUILD_MENU, DUR.ROUTE)
					bmOpenHintShown = true
				end
				clearBuildMenuPulsesExcept(nil)
			else
				clearAllUIPulses()
			end
		end
	end

	bm:GetPropertyChangedSignal("Enabled"):Connect(apply)
	apply()
end)

----------------------------
-- Global toggle handling  --
----------------------------
_G.OB_ENABLED = false
local function applyToggle(enabled)
	_G.OB_ENABLED = (enabled ~= false)
	if not _G.OB_ENABLED then
		if guardPulseItem  then Stop(guardPulseItem);  guardPulseItem  = nil end
		if serverPulseItem then Stop(serverPulseItem); serverPulseItem = nil end
		clearAllUIPulses()
		clearArrowAndGate()
		clearB2()
		clearB3()
	else
		local id = guardCurrentItem() or getFlowItem()
		if id then Pulse(id) end
		local bm = buildMenu()
		if bm and bm.Enabled then
			arrowAndGateToCurrentStep()
		else
			requestPulseAndArrow("BuildButton", UDim2.new(0,0,-0.12,0))
			showOB1(LANG.OB_OPEN_BUILD_MENU, DUR.ROUTE)
		end
		for key in pairs(wantPulse) do
			if gateAllows(key) then UIPulse.start(key) end
		end
	end
	pcall(function() BE_Toggle:Fire(_G.OB_ENABLED) end)
end
RE_Toggle.OnClientEvent:Connect(applyToggle)

------------------------
-- Guard FB → advance --
------------------------
BE_GuardFB.Event:Connect(function(tag, info)
	if not _G.OB_ENABLED then return end

	-- Normalize feedback + figure out what the guard expects right now
	local fbItem   = info and canonItem(info.item or info.mode)
	local expected = guardCurrentItem() or getFlowItem() -- prefer our guard; fall back to flow

	if DEBUG then
		dbg("[GUARD_FB] tag=%s fbItem=%s expected=%s idx=%d/%d",
			tostring(tag), tostring(fbItem), tostring(expected), guardIdx, #guardSeq)
	end

	-- Drop feedback from stale watchers (e.g. previous step still finishing up)
	if fbItem and expected and fbItem ~= expected then
		if DEBUG then dbg("[GUARD_FB] ignore stale feedback for %s (expect %s)", tostring(fbItem), tostring(expected)) end
		return
	end

	-- =========================================================
	-- DONE  → advance (unchanged logic, with minor safety)
	-- =========================================================
	if tag == "done" then
		local justDone = math.max(guardIdx, 1)

		-- Sequence-specific "done" toast
		if activeSeq == "barrage1" then
			local doneKey = OB1_STEP_DONE_KEYS[justDone]
			if doneKey then showOB1(doneKey, DUR.DONE) end
		elseif activeSeq == "barrage3" then
			-- Zone rectangle placed
			showB3(LANG.OB3_Industrial_Done, DUR.DONE)
			pcall(function() StepCompleted:FireServer("B3_ZonePlaced") end)
		end

		-- Persist progress for this step
		pcall(function()
			StepCompleted:FireServer("GuardStepDone", {
				seq   = activeSeq or "barrage1",
				index = justDone,
				total = #guardSeq,
			})
		end)

		-- Stop any pulse for the reported (or expected) item
		local id = fbItem or expected
		if id then Stop(id); if guardPulseItem == id then guardPulseItem = nil end end

		-- Advance sequence (and optionally notify server if this was the last one)
		local wasLast = justDone >= #guardSeq
		if wasLast then
			pcall(function() StepCompleted:FireServer("OnboardingFinished") end)
		end
		GuardAdvance()

		-- Refresh UI routing/pulses
		clearBuildMenuPulsesExcept(nil)
		local bm = buildMenu()
		if bm and bm.Enabled then
			arrowAndGateToCurrentStep()
		else
			requestPulseAndArrow("BuildButton", UDim2.new(0,0,-0.12,0))
			showOB1(LANG.OB_OPEN_BUILD_MENU, DUR.ROUTE)
		end

		-- Next step hint (or sequence complete)
		if guardSeq[guardIdx] then
			if activeSeq == "barrage1" then
				local hintKey = OB1_STEP_HINT_KEYS[guardIdx]
				if hintKey then showOB1(hintKey, DUR.HINT) end
			end
			local nextId = canonItem(guardSeq[guardIdx].mode or guardSeq[guardIdx].item)
			if nextId then showRoutingHintsForItemId(nextId) end
		else
			if activeSeq == "barrage1" then
				showOB1(LANG.OB1_COMPLETE, DUR.COMPLETE)
			end
			-- For barrage3 we intentionally don't show "complete" here;
			-- the server will enter the connectivity phase and drive hints.
		end

		-- =========================================================
		-- CANCELED → re‑guard the current step (do NOT kill loop)
		-- =========================================================
	elseif tag == "canceled" then
		-- Stop any pulse for what was attempted
		if fbItem then
			Stop(fbItem)
			if guardPulseItem == fbItem then guardPulseItem = nil end
		end

		-- Re-assert the current guard so the grid can rebind cleanly
		local cur = guardSeq[math.max(guardIdx, 1)]
		if cur then
			if DEBUG then dbg("[GUARD_FB] re-guarding current step after canceled") end
			emitGuard("start", cur)

			-- Re-pulse the expected tool and re-aim the BuildMenu arrow/gate if open
			local want = canonItem(cur.mode or cur.item)
			if want then
				Pulse(want); guardPulseItem = want
				local bm = buildMenu()
				if bm and bm.Enabled then
					arrowAndGateToCurrentStep()
				end
			end
		else
			if DEBUG then dbg("[GUARD_FB] canceled but no current step; ignoring") end
		end

		-- =========================================================
		-- CLEARED → gentle re‑guard (mirror OnboardingFlow behavior)
		-- =========================================================
	elseif tag == "cleared" then
		-- Don’t mutate indices here; just re-issue the current guard.
		local cur = guardSeq[math.max(guardIdx, 1)]
		if cur then
			if fbItem then Stop(fbItem) end
			if DEBUG then dbg("[GUARD_FB] cleared → re-guard current step") end
			emitGuard("start", cur)
			local want = canonItem(cur.mode or cur.item)
			if want then Pulse(want); guardPulseItem = want end
		end

		-- =========================================================
		-- Unknown tags → ignore (safe no-op)
		-- =========================================================
	else
		if DEBUG then dbg("[GUARD_FB] unknown tag=%s (ignored)", tostring(tag)) end
	end
end)



-----------------------------
-- Tool selection feedback --
-----------------------------
DisplayGrid.OnClientEvent:Connect(function(mode)
	if not _G.OB_ENABLED then return end
	local item = canonItem(mode)
	_G.OB_CurrentTool = item
	if item == "DirtRoad" then pcall(function() StepCompleted:FireServer("RoadToolSelected") end) end
	-- Also clear gate when selecting WaterTower/WindTurbine
	if item == "WaterPipe"  or item == "WaterTower"  then pcall(function() StepCompleted:FireServer("WaterToolSelected") end)  end
	if item == "PowerLines" or item == "WindTurbine" then pcall(function() StepCompleted:FireServer("PowerToolSelected") end) end
	if item == "WaterPipe" or item == "WaterTower" then print("[OB] Water tool picked:", item) end
	if item == "PowerLines" or item == "WindTurbine" then print("[OB] Power tool picked:", item) end
	if guardPulseItem and item == guardPulseItem then Stop(guardPulseItem); guardPulseItem = nil end
	if serverPulseItem and item == serverPulseItem then Stop(serverPulseItem); serverPulseItem = nil end
	Stop(nil); Stop("*")
	clearBuildMenuPulsesExcept(nil)
end)

----------------------------
-- Server → Client nudges  --
----------------------------
local function bmGateOnly(id, offset)
	applyGate(id)
	local bm = buildMenu()
	if not (bm and bm.Enabled) then return end
	if _G.OB_CurrentTool == id then
		clearBuildMenuPulsesExcept(nil)
		HideArrow()
		return
	end
	local wantMajor, wantHub = majorForItem(id), hubForItem(id)
	local curMajor = getCurrentMajor()
	local curHub   = getCurrentHub(curMajor)
	local key
	if wantMajor and (curMajor ~= wantMajor) then
		key = MAJOR_TO_KEY[wantMajor] or "BM_Transport"
		requestPulseAndArrow(key, offset or UDim2.new(0,0,-0.12,0))
		hubWatchToken += 1
		local my = hubWatchToken
		local want = wantMajor
		task.spawn(function()
			local t0 = os.clock()
			while my == hubWatchToken and os.clock() - t0 < 6.0 do
				task.wait(0.25)
				if getCurrentMajor() == want then
					bmGateOnly(id, offset)
					return
				end
			end
		end)
	else
		if wantHub and (curHub ~= wantHub) then
			key = resolveHubKey(wantMajor or "Supply", wantHub) or "BM_Supply"
			requestPulseAndArrow(key, offset or UDim2.new(0,0,-0.12,0))
		else
			key = "BM_"..id
			requestPulseAndArrow(key, offset or UDim2.new(0,0,-0.18,0))
		end
	end
	clearBuildMenuPulsesExcept(key)
end

StateChanged.OnClientEvent:Connect(function(stepName, payload)
	if stepName == "ShowArrow_BuildMenu" then
		if not _G.OB_ENABLED then applyToggle(true) end
		requestPulseAndArrow("BuildButton", UDim2.new(0,0,-0.12,0))
		showOB1(LANG.OB_OPEN_BUILD_MENU, DUR.ROUTE)
		return
	end
	if stepName == "UIPulse_Start" and typeof(payload)=="table" and type(payload.key)=="string" then
		requestPulseAndArrow(payload.key, payload.offset); return
	end
	if stepName == "UIPulse_Stop" and typeof(payload)=="table" and type(payload.key)=="string" then
		clearPulseAndArrow(payload.key); return
	end
	if not _G.OB_ENABLED and stepName ~= "CityNaming" then return end
	if stepName == "CityNaming" then return end
	if stepName == "HideArrow" then HideArrow(); return end
	if stepName == "BuildMenu_GateOnly" and typeof(payload)=="table" then
		local id = canonItem(payload.itemID or payload.item)
		if id then bmGateOnly(id, payload.offset) end
		return
	end
	if stepName == "BuildMenu_GateOnly_Current" then arrowAndGateToCurrentStep(); return end
	if stepName == "BuildMenu_GateClear"        then clearArrowAndGate(); return end

	-- Honor resumeAt from the server so we don't restart from step 1
	if stepName == "Onboarding_StartBarrage1" then
		if guardPulseItem  then Stop(guardPulseItem);  guardPulseItem  = nil end
		if serverPulseItem then Stop(serverPulseItem); serverPulseItem = nil end
		activeSeq = "barrage1"
		local function barrage1()
			return {
				{item="Road",        mode="DirtRoad",    kind="line",  from={x=0,  z=0},  to={x=0, z=21}, requireExactEnd=true },
				{item="Residential", mode="Residential", kind="rect",  from={x=1,  z=1},  to={x=4, z=10} },
				{item="WaterTower",  mode="WaterTower",  kind="point", from={x=-1, z=1} },
				{item="WaterPipe",   mode="WaterPipe",   kind="line",  from={x=0,  z=1},  to={x=5, z=1} },
				{item="WaterPipe",   mode="WaterPipe",   kind="line",  from={x=3,  z=1},  to={x=3, z=11} },
				{item="WindTurbine", mode="WindTurbine", kind="point", from={x=-1, z=9} },
				{item="PowerLines",  mode="PowerLines",  kind="line",  from={x=0,  z=9},  to={x=3, z=9} },
				{item="PowerLines",  mode="PowerLines",  kind="line",  from={x=3,  z=8},  to={x=3, z=1} },
				{item="DirtRoad",    mode="DirtRoad",    kind="line",  from={x=0,  z=11}, to={x=4, z=11}, requireExactEnd=false },
				{item="Commercial",  mode="Commercial",  kind="rect",  from={x=1,  z=12}, to={x=4, z=21} },
			}
		end
		local resumeAt = (typeof(payload)=="table" and tonumber(payload.resumeAt)) or 1
		GuardStart(barrage1(), resumeAt)
		local cur = guardSeq[guardIdx]; if cur then Pulse(canonItem(cur.mode or cur.item)) end
		return
	end

	-- Barrage 2 coaching (existing)
	if stepName == "Onboarding_B2_Begin" then
		print("[OB] Barrage 2 begin: Utilities coaching")
		showB2(LANG.OB2_BEGIN, 5)
		local bm = buildMenu()
		if bm and bm.Enabled then
			bmGateOnly("WaterTower", UDim2.new(0,0,-0.12,0))
		else
			requestPulseAndArrow("BuildButton", UDim2.new(0,0,-0.12,0))
		end
		return
	end

	if stepName == "Onboarding_B2_Complete" then
		print("[OB] Barrage 2 complete: all buildings have Water & Power")
		showB2(LANG.OB2_COMPLETE, 2)
		task.delay(2, clearB2)
		clearArrowAndGate()
		return
	end

	if stepName == "Onboarding_ShowHint_WaterDeficit" and typeof(payload)=="table" then
		print(("[OB] Water deficit → produced=%s required=%s"):format(tostring(payload.produced), tostring(payload.required)))
		showB2(LANG.OB2_WATER_DEFICIT, 5)
		bmGateOnly("WaterTower", UDim2.new(0,0,-0.12,0))
		return
	end

	if stepName == "Onboarding_ShowHint_ConnectBuildingsToWater" and typeof(payload)=="table" then
		print("[OB] Connect WATER to buildings; example zone:", tostring(payload.zoneId))
		showB2(LANG.OB2_CONNECT_WATER, 5)
		bmGateOnly("WaterPipe", UDim2.new(0,0,-0.12,0))
		return
	end

	if stepName == "Onboarding_ShowHint_PowerDeficit" and typeof(payload)=="table" then
		print(("[OB] Power deficit → produced=%s required=%s"):format(tostring(payload.produced), tostring(payload.required)))
		showB2(LANG.OB2_POWER_DEFICIT, 5)
		bmGateOnly("WindTurbine", UDim2.new(0,0,-0.12,0))
		return
	end

	if stepName == "Onboarding_ShowHint_ConnectBuildingsToPower" and typeof(payload)=="table" then
		print("[OB] Connect POWER to buildings; example zone:", tostring(payload.zoneId))
		showB2(LANG.OB2_CONNECT_POWER, 5)
		bmGateOnly("PowerLines", UDim2.new(0,0,-0.12,0))
		return
	end

	-- ===== Barrage 3 (Industrial) =====
	if stepName == "Onboarding_B3_Begin" then
		print("[OB] Barrage 3 begin: Industrial placement + connectivity")
		showB3(LANG.OB3_BEGIN, 5)
		local bm = buildMenu()
		if bm and bm.Enabled then
			bmGateOnly("Industrial", UDim2.new(0,0,-0.12,0))
		else
			requestPulseAndArrow("BuildButton", UDim2.new(0,0,-0.12,0))
		end
		return
	end

	if stepName == "Onboarding_StartBarrage3" and typeof(payload)=="table" then
		if guardPulseItem  then Stop(guardPulseItem);  guardPulseItem  = nil end
		if serverPulseItem then Stop(serverPulseItem); serverPulseItem = nil end
		activeSeq = "barrage3"
		local from = payload.from or {x=-5,z=6}
		local to   = payload.to   or {x=-8,z=15}
		local function barrage3()
			return {
				{ item="Industrial", mode="Industrial", kind="rect", from=from, to=to, requireExactEnd=true },
			}
		end
		GuardStart(barrage3(), 1)
		local cur = guardSeq[guardIdx]; if cur then Pulse(canonItem(cur.mode or cur.item)) end
		return
	end

	if stepName == "Onboarding_B3_Hint_RoadPlace" then
		showB3(LANG.OB3_ConnectRoad, 5)
		bmGateOnly("DirtRoad", UDim2.new(0,0,-0.12,0))
		return
	end
	if stepName == "Onboarding_B3_Hint_RoadConnectNetwork" then
		showB3(LANG.OB3_ConnectRoadNetwork, 5)
		bmGateOnly("DirtRoad", UDim2.new(0,0,-0.12,0))
		return
	end
	if stepName == "Onboarding_B3_Hint_ConnectWater" then
		showB3(LANG.OB3_ConnectWater, 5)
		bmGateOnly("WaterPipe", UDim2.new(0,0,-0.12,0))
		return
	end
	if stepName == "Onboarding_B3_Hint_ConnectPower" then
		showB3(LANG.OB3_ConnectPower, 5)
		bmGateOnly("PowerLines", UDim2.new(0,0,-0.12,0))
		return
	end
	if stepName == "Onboarding_B3_Complete" then
		showB3(LANG.OB3_Complete, DUR.COMPLETE)
		task.delay(2, clearB3)
		clearArrowAndGate()
		applyToggle(false)
		return
	end
end)

---------------------
-- Self‑nudge seed --
---------------------
task.delay(0.40, function()
	if _G.OB_ENABLED then
		local gate = KEY_GATES.BuildButton and KEY_GATES.BuildButton()
		if gate then
			requestPulseAndArrow("BuildButton", UDim2.new(0,0,-0.12,0))
			showOB1(LANG.OB_OPEN_BUILD_MENU, DUR.ROUTE)
		end
	end
end)
