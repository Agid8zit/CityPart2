-- StarterPlayerScripts/OnboardingController.client.lua
-- Single-source-of-truth for onboarding UI pulses, arrows, and BuildMenu gating.
-- Minimal, defensive, and race-safe. (Localization-first: NO literal UI strings here.)
-- [DEBUG] Deep instrumentation for arrow/pulse/gate decisions, BuildMenu open/close,
--         route showcases, and committed tab/hub detection. HideArrow accepts an
--         optional 'reason' string for clearer traces. Memory-safe arrow retries.

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
local TRACE_ARROW_STACKS = false -- set true to include stack traces on Show/Hide arrow

local function _ts()
	-- os.clock() is deterministic CPU-time; good enough for step ordering
	local t = os.clock()
	return string.format("%6.2f", t)
end

-- FIX: robust dbg printer that never drops args and never mis-formats
local function dbg(...)
	if not DEBUG then return end
	local n = select("#", ...)
	if n == 0 then return end
	local prefix = "[OB " .. _ts() .. "] "
	local first = ...
	-- If first arg is a format string with % and there are additional args, try string.format
	if type(first) == "string" and n > 1 and first:find("%%") then
		local ok, s = pcall(string.format, ...)
		if ok then
			print(prefix .. s)
			return
		end
	end
	-- Fallback: tostring every arg so table.concat never errors
	local parts = table.create(n)
	for i = 1, n do
		parts[i] = tostring(select(i, ...))
	end
	print(prefix .. table.concat(parts, " "))
end

local function dbg_arrow(fmt, ...)
	if not DEBUG then return end
	if fmt then
		dbg("[ARROW] " .. fmt, ...)
	else
		dbg("[ARROW] (no message)")
	end
end

local function dbg_bm(fmt, ...)
	if not DEBUG then return end
	if fmt then
		dbg("[BM] " .. fmt, ...)
	else
		dbg("[BM] (no message)")
	end
end

local function dbg_route(fmt, ...) if DEBUG then dbg("[ROUTE] " .. fmt, ...) end end
local function dbg_gate(fmt, ...)  if DEBUG then dbg("[GATE] "  .. fmt, ...) end end
local function dbg_ui(fmt, ...)    if DEBUG then dbg("[UI] "    .. fmt, ...) end end
local function dbg_res(fmt, ...)   if DEBUG then dbg("[RESOLVE] ".. fmt, ...) end end
local function dbg_fb(fmt, ...)    if DEBUG then dbg("[GUARD_FB] ".. fmt, ...) end end

local function bools(x) return x and "true" or "false" end

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

local BF_CheckItemAllowed = ensureBindable("BindableFunction", "OBCheckItemAllowed") -- kept in BE for backward compat
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
	-- (Legacy examples)
	OB1_ROAD_SELECT    = "OB_SelectRoad",
	OB1_ROAD_SELECT_OK = "OB_SelectRoad_Done",

	-- Barrage 2
	OB2_BEGIN          = "OB2_Begin",
	OB2_COMPLETE       = "OB2_Complete",
	OB2_WATER_DEFICIT  = "OB2_WaterDeficit",
	OB2_CONNECT_WATER  = "OB2_ConnectWater",
	OB2_POWER_DEFICIT  = "OB2_PowerDeficit",
	OB2_CONNECT_POWER  = "OB2_ConnectPower",

	-- Barrage 1
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

	-- Generic routing hints
	OB_OPEN_BUILD_MENU     = "OB_OpenBuildMenu",
	OB_OPEN_TRANSPORT_TAB  = "OB_OpenTransportTab",
	OB_OPEN_ZONES_TAB      = "OB_OpenZonesTab",
	OB_OPEN_SUPPLY_TAB     = "OB_OpenSupplyTab",
	OB_OPEN_SERVICES_TAB   = "OB_OpenServicesTab",
	OB_OPEN_WATER_HUB      = "OB_OpenWaterHub",
	OB_OPEN_POWER_HUB      = "OB_OpenPowerHub",

	-- Barrage 3
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
		dbg("[TOAST] channel=%s key=%s dur=%.2f", tostring(channel), tostring(langKey), tonumber(duration or 4))
		pcall(NotificationGui.ShowSingleton, channel, langKey, { duration = duration or 4 })
	end
end

local function clearChannel(channel: string)
	if NotificationGui and type(NotificationGui.ClearSingleton) == "function" then
		dbg("[TOAST] clear channel=%s", tostring(channel))
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

-- FIX: broadened candidates so we can actually find your buttons
local MAJOR_KEY_CANDIDATES = {
	Transport = { "BM_Transport","BM_Tab_Transport","BMTabs_Transport","BMCategory_Transport","BM_TransportTab","BMHub_Transport","BM_TransportIcon" },
	Zones     = { "BM_Zones","BM_Tab_Zones","BMTabs_Zones","BMCategory_Zones","BM_ZonesTab","BMHub_Zones","BM_ZonesIcon" },
	Supply    = { "BM_Supply","BM_Tab_Supply","BMTabs_Supply","BMCategory_Supply","BM_SupplyTab","BMHub_Supply","BM_SupplyIcon" },
	Services  = { "BM_Services","BM_Tab_Services","BMTabs_Services","BMCategory_Services","BM_ServicesTab","BMHub_Services","BM_ServicesIcon" },
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

local function getFlowState()
	if not OnboardingFlow then
		local ok, mod = pcall(function()
			return require(ReplicatedStorage.Scripts.Onboarding.OnboardingFlow)
		end)
		if ok then OnboardingFlow = mod end
	end
	if OnboardingFlow and type(OnboardingFlow.GetState) == "function" then
		return OnboardingFlow.GetState()
	end
	return nil
end

local function getFlowItem()
	local st = getFlowState()
	-- Prefer mode (concrete tool id) over abstract item
	return st and st.current and canonItem(st.current.mode or st.current.item) or nil
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

-- FIX: ignore nil pulses (and log clearly)
local function Pulse(item)
	if item == nil or item == "" then
		if DEBUG then dbg_ui("Pulse (ignored) -> <nil>") end
		return
	end
	dbg_ui("Pulse -> %s", tostring(item))
	BE_PulseItem:Fire(item)
end

-- FIX: ignore Stop(nil) but allow wildcard
local function Stop(item)
	if item == nil or item == "" then return end
	dbg_ui("Stop -> %s", tostring(item))
	BE_StopPulseItem:Fire(item)
end

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

local function _traceStackIfEnabled(tag)
	if TRACE_ARROW_STACKS then
		local ok, tb = pcall(function() return debug.traceback(tag or "", 2) end)
		if ok and tb then
			for line in string.gmatch(tb, "[^\n]+") do
				dbg_arrow("    %s", line)
			end
		end
	end
end

local function HideArrow(reason)
	dbg_arrow("HideArrow (reason=%s, owner=%s, lastKey=%s)", tostring(reason or "unspecified"), tostring(arrowOwner), tostring(lastArrowKey))
	_traceStackIfEnabled("HideArrow")
	pcall(NotificationGui.HideArrow)
end

local function ShowArrowAtKey(key, offset)
	local target = getUITarget(key)
	if target then
		dbg_arrow("ShowArrowAtKey key=%s target=%s offset=%s", tostring(key), target:GetFullName(), tostring(offset))
		_traceStackIfEnabled("ShowArrowAtKey->ShowArrowAt")

		-- >>> ADD: don't call nil functions (prevents loop + error spam)
		if not (NotificationGui and type(NotificationGui.ShowArrowAt) == "function") then
			dbg_arrow("ShowArrowAtKey: suppress (ShowArrowAt missing) for key=%s", tostring(key))
			return false
		end

		local ok, placed = pcall(NotificationGui.ShowArrowAt, target, offset or UDim2.new(0,0,-0.12,0))
		dbg_arrow("ShowArrowAt returned ok=%s placed=%s", bools(ok), tostring(placed))
		if ok and placed == true then
			return true
		end
	else
		dbg_arrow("ShowArrowAtKey key=%s target=<nil>, will fallback bounce", tostring(key))
	end

	_traceStackIfEnabled("ShowArrowAtKey->ShowArrowBounce(fallback)")

	-- >>> ADD: guard fallback too
	if not (NotificationGui and type(NotificationGui.ShowArrowBounce) == "function") then
		dbg_arrow("ShowArrowAtKey: suppress bounce (ShowArrowBounce missing) for key=%s", tostring(key))
		return false
	end

	local ok2, bounced = pcall(NotificationGui.ShowArrowBounce, POS_A, POS_B, SIZE, ROT)
	dbg_arrow("ShowArrowBounce returned ok=%s bounced=%s", bools(ok2), tostring(bounced))
	return ok2 and bounced == true
end

-- FIX: make retry connection self-cleaning if target never appears (avoid leaks)
local function ShowArrowAtKeyTracked(key, offset)
	lastArrowKey = key
	dbg_arrow("Tracked show: key=%s offset=%s", tostring(key), tostring(offset))
	if ShowArrowAtKey(key, offset) then
		dbg_arrow("Tracked show placed for key=%s", tostring(key))
		return
	end
	local myKey = key
	local conn
	local canceled = false
	conn = UITargetRegistry.Changed():Connect(function(chKey)
		if canceled then return end
		if chKey == myKey then
			dbg_arrow("Retried show after UITargetRegistry change for key=%s", tostring(myKey))
			ShowArrowAtKey(myKey, offset)
			if conn then conn:Disconnect() end
			canceled = true
		end
	end)
	-- Auto-timeout in case the UITarget never registers
	task.delay(5, function()
		if not canceled and conn then
			dbg_arrow("Tracked show timeout; disconnecting retry for key=%s", tostring(myKey))
			conn:Disconnect()
		end
	end)
end

-------------------
-- Pulse Manager  --
-------------------
local PULSE_GREEN = Color3.fromRGB(0,255,140)
local pulseByKey, wantPulse, arrowOffset = {}, {}, {}
local BM_LocalArrow = { gui=nil, ownerKey=nil, conn=nil, token=0 }
local ARROW_VERTICAL_OFFSET   = 50
local ARROW_BOUNCE_AMPLITUDE  = 6
local ARROW_BOUNCE_SPEED_HZ   = 0.9
local ARROW_FOLLOW_LERP_SPEED = 12

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
	if type(r)=="number" and type(g)=="number" then
		return Color3.new(r,g,b)
	end
	return Color3.new(1,1,1)
end

local function attachLocalBMArrowFor(targetGui: GuiObject, key: string)
	local bm = PlayerGui:FindFirstChild("BuildMenu")
	local obArrow = bm and bm:FindFirstChild("OnboardingArrow", true)
	if not (obArrow and obArrow:IsA("GuiObject")) then
		dbg_arrow("BM local arrow missing; cannot attach. key=%s", tostring(key))
		return
	end

	if BM_LocalArrow.conn then BM_LocalArrow.conn:Disconnect() end

	BM_LocalArrow.token += 1
	BM_LocalArrow.ownerKey = key
	BM_LocalArrow.gui      = obArrow
	BM_LocalArrow.phase    = 0
	BM_LocalArrow.prevPos  = nil

	obArrow.Visible = true
	obArrow.Rotation = 180
	pcall(function() obArrow.AnchorPoint = Vector2.new(0.5, 1) end)
	obArrow.ZIndex = math.max((targetGui.ZIndex or 1) + 10, obArrow.ZIndex or 1)
	dbg_arrow("Attach BM local arrow → key=%s z=%d", tostring(key), tonumber(obArrow.ZIndex or 0))

	local my = BM_LocalArrow.token
	BM_LocalArrow.conn = RunService.RenderStepped:Connect(function(dt)
		if BM_LocalArrow.token ~= my then return end
		if not (obArrow.Parent and targetGui.Parent) then return end

		local pos, size = targetGui.AbsolutePosition, targetGui.AbsoluteSize
		local targetPos = Vector2.new(pos.X + size.X * 0.5, pos.Y + ARROW_VERTICAL_OFFSET)

		local alpha = math.clamp(dt * ARROW_FOLLOW_LERP_SPEED, 0, 1)
		local smoothPos = BM_LocalArrow.prevPos and BM_LocalArrow.prevPos:Lerp(targetPos, alpha) or targetPos
		BM_LocalArrow.prevPos = smoothPos

		BM_LocalArrow.phase += dt * (ARROW_BOUNCE_SPEED_HZ * 2 * math.pi)
		local bob = (1 - math.cos(BM_LocalArrow.phase)) * 0.5 * ARROW_BOUNCE_AMPLITUDE

		obArrow.Position = UDim2.fromOffset(smoothPos.X, smoothPos.Y + bob)
	end)
end

local UIPulse = {}
function UIPulse.start(key, opts)
	local target = getUITarget(key); if not target then dbg_ui("UIPulse.start ignored; key=%s target=<nil>", tostring(key)); return false end
	local rec = pulseByKey[key]
	if type(key) == "string" and string.sub(key,1,3) == "BM_" then
		attachLocalBMArrowFor(target, key)
	end
	if rec and rec.running then dbg_ui("UIPulse.start already running; key=%s", tostring(key)); return true end
	local stroke = ensureStroke(target)
	local token  = (rec and rec.token or 0) + 1
	rec = { stroke=stroke, token=token, running=true, tween=nil }
	pulseByKey[key] = rec
	local cA = (opts and opts.colorA) or PULSE_GREEN
	local cB = (opts and opts.colorB) or origColor(stroke)
	local tA = (opts and opts.tA) or 0.5
	local tB = (opts and opts.tB) or 0.6
	dbg_ui("UIPulse.start key=%s tA=%.2f tB=%.2f", tostring(key), tA, tB)
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
	dbg_ui("UIPulse.stop key=%s", tostring(key))
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
			dbg_arrow("Detach BM local arrow; key=%s", tostring(key))
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
		local res = not (bm and bm.Enabled)
		dbg_gate("KeyGate[BuildButton] -> %s (bm=%s)", bools(res), bm and tostring(bm.Enabled) or "nil")
		return res
	end,
}
local function gateAllows(key)
	if type(key)=="string" and string.sub(key,1,3)=="BM_" then
		local bm = buildMenu()
		local allowed = bm and bm.Enabled == true
		dbg_gate("GateAllows[%s] -> %s (BM open=%s)", tostring(key), bools(allowed), bm and bools(bm.Enabled) or "nil")
		return allowed
	end
	local g = KEY_GATES[key]; if not g then dbg_gate("GateAllows[%s] -> true (no gate)", tostring(key)); return true end
	local ok, allowed = pcall(g)
	dbg_gate("GateAllows[%s] -> %s (ok=%s)", tostring(key), bools(allowed == true), bools(ok))
	return ok and allowed == true
end

local function requestPulseAndArrow(key, offset)
	if not _G.OB_ENABLED then dbg_ui("requestPulseAndArrow ignored; onboarding disabled. key=%s", tostring(key)); return end
	wantPulse[key]   = true
	arrowOffset[key] = offset or UDim2.new(0,0,-0.12,0)
	local allowed = gateAllows(key)
	dbg_arrow("requestPulseAndArrow key=%s allowed=%s owner=%s", tostring(key), bools(allowed), tostring(arrowOwner))
	if allowed then
		UIPulse.start(key)
		if arrowOwner ~= key and not (type(key)=="string" and string.sub(key,1,3)=="BM_") then
			dbg_arrow("Owner change: %s -> %s", tostring(arrowOwner), tostring(key))
			ShowArrowAtKeyTracked(key, arrowOffset[key])
			arrowOwner = key
		else
			dbg_arrow("Arrow owner unchanged or BM_* arrow handled locally; key=%s", tostring(key))
		end
	else
		UIPulse.stop(key)
	end
end

local function clearPulseAndArrow(key)
	wantPulse[key] = nil
	UIPulse.stop(key)
	if arrowOwner == key then
		dbg_arrow("clearPulseAndArrow hides global arrow for key=%s", tostring(key))
		HideArrow("clearPulseAndArrow")
		arrowOwner = nil
	end
end
local function clearBuildMenuPulsesExcept(keep)
	for k in pairs(wantPulse) do
		if type(k)=="string" and string.sub(k,1,3)=="BM_" and k ~= keep then
			dbg_ui("clearBuildMenuPulsesExcept stopping k=%s keep=%s", tostring(k), tostring(keep))
			clearPulseAndArrow(k)
		end
	end
end
local function clearAllUIPulses()
	dbg_ui("clearAllUIPulses()")
	for k in pairs(wantPulse) do UIPulse.stop(k) end
	table.clear(wantPulse)
	if BM_LocalArrow.conn then BM_LocalArrow.conn:Disconnect() end
	BM_LocalArrow.conn = nil
	if BM_LocalArrow.gui then BM_LocalArrow.gui.Visible = false end
	BM_LocalArrow.ownerKey = nil
	BM_LocalArrow.token += 1
	HideArrow("clearAllUIPulses")
	arrowOwner = nil
end

-----------------------
-- BuildMenu helpers --
-----------------------
local function getBMLogic()
	local bm = buildMenu(); if not bm then dbg_bm("getBMLogic -> <nil> (BM missing)"); return nil end
	local ok, mod = pcall(function() return require(bm.Logic) end)
	dbg_bm("getBMLogic ok=%s", bools(ok))
	return ok and mod or nil
end

local function applyGate(allowedItemID)
	-- cache intended gate only
	currentGateId = allowedItemID and canonItem(allowedItemID) or nil
	dbg_gate("applyGate id=%s", tostring(currentGateId))

	-- only apply visuals if the BuildMenu is actually open
	local bm = buildMenu()
	if not (bm and bm.Enabled) then dbg_gate("applyGate deferred (BM not open)"); return end

	local mod = getBMLogic()
	if mod and type(mod.ApplyGateVisual) == "function" then
		dbg_gate("ApplyGateVisual(%s)", tostring(currentGateId))
		-- Contract: visual-only gate
		mod.ApplyGateVisual(currentGateId)
	else
		dbg_gate("ApplyGateVisual missing on BM logic")
	end
end

local function getCurrentMajor(quiet)
	local bf = BF_GetMajor or BFOLDER:FindFirstChild("OBBuildMenuGetMajorTab")
	if bf and bf:IsA("BindableFunction") then
		local ok, cur = pcall(function() return bf:Invoke() end)
		if not quiet then dbg_bm("getCurrentMajor via BF ok=%s cur=%s", bools(ok), tostring(cur)) end
		if ok and type(cur)=="string" and cur~="" then return cur end
	end
	if not quiet then dbg_bm("getCurrentMajor -> <nil>") end
	return nil
end

local function getCurrentHub(major, quiet)
	local bf = BF_GetHub or BFOLDER:FindFirstChild("OBBuildMenuGetHub")
	if bf and bf:IsA("BindableFunction") then
		local ok, hub = pcall(function() return bf:Invoke(major) end)
		if not quiet then dbg_bm("getCurrentHub(%s) via BF ok=%s hub=%s", tostring(major), bools(ok), tostring(hub)) end
		if ok and type(hub)=="string" and hub~="" then return hub end
	end
	local mod = getBMLogic()
	if mod then
		if type(mod.GetCurrentHub)=="function" then
			local ok, h = pcall(mod.GetCurrentHub)
			if not quiet then dbg_bm("getCurrentHub(%s) via Logic ok=%s hub=%s", tostring(major), bools(ok), tostring(h)) end
			if ok and type(h)=="string" and h~="" then return h end
		end
		if type(mod.State)=="table" and type(mod.State.hub)=="string" and mod.State.hub~="" then
			if not quiet then dbg_bm("getCurrentHub(%s) via State -> %s", tostring(major), tostring(mod.State.hub)) end
			return mod.State.hub
		end
	end
	if not quiet then dbg_bm("getCurrentHub(%s) -> <nil>", tostring(major)) end
	return nil
end

-- ===== Committed (click-confirmed) selection =====
local committedMajor, committedHub = nil, nil
local function setCommitted(major, hub)
	if type(major) == "string" and major ~= "" then
		committedMajor = major
		dbg_bm("[COMMIT] major=%s", tostring(major))
	end
	if type(hub)   == "string" and hub   ~= "" then
		committedHub   = hub
		dbg_bm("[COMMIT] hub=%s", tostring(hub))
	end
end

local function getCommittedMajor() return committedMajor end
local function getCommittedHub(_)  return committedHub  end

-- FIX: resolve majors using broadened candidate keys
local function resolveMajorKey(major)
	local candidates = MAJOR_KEY_CANDIDATES[major]
	if candidates then
		for _,k in ipairs(candidates) do
			if getUITarget(k) then dbg_res("resolveMajorKey(%s) -> %s (candidate)", tostring(major), tostring(k)); return k end
		end
	end
	local fallback = MAJOR_TO_KEY[major] or "BM_Transport"
	dbg_res("resolveMajorKey(%s) -> %s (fallback)", tostring(major), tostring(fallback))
	return fallback
end

local function resolveHubKey(major, hub)
	local candidates = major and hub and HUB_KEY_CANDIDATES[major] and HUB_KEY_CANDIDATES[major][hub]
	if candidates then
		for _,k in ipairs(candidates) do if getUITarget(k) then dbg_res("resolveHubKey(%s,%s) -> %s (candidate)", tostring(major), tostring(hub), tostring(k)); return k end end
	end
	local fb = hub and ("BM_"..hub) or nil
	dbg_res("resolveHubKey(%s,%s) -> %s (fallback)", tostring(major), tostring(hub), tostring(fb))
	return fb
end

---------------------------
-- Barrage‑1 route helper --
---------------------------
local arrowAndGateToCurrentStep -- fwd decl

local BARRAGE1_ROUTE_STEPS = {
	[3] = { -- WaterTower step itself: nudge to Supply→Water→(WaterTower) if needed
		{ kind = "major", major = "Supply" },
		{ kind = "hub",   major = "Supply", hub = "Water" },
		{ kind = "item" },
	},
	[4] = { -- WaterPipe A: explicit Supply→Water→item
		{ kind = "major", major = "Supply" },
		{ kind = "hub",   major = "Supply", hub = "Water" },
		{ kind = "item" },
	},
	[5] = { { kind = "item" }, }, -- WaterPipe B: just the tile
	[6] = {
		{ kind = "major", major = "Supply" },
		{ kind = "hub",   major = "Supply", hub = "Power" },
		{ kind = "item" },
	},
	[7] = {
		{ kind = "major", major = "Supply" },
		{ kind = "hub",   major = "Supply", hub = "Power" },
		{ kind = "item" },
	},
	[8] = { { kind = "item" }, },
}

local ROUTE_STAGE_DURATION = 0.45
local COMMIT_TIMEOUT       = 4.0
local COMMIT_STABLE        = 0.18

local barrage1RouteToken = 0
local barrage1RouteActive = false
local barrage1LastIndex = 0

-- ADD: one‑time showcase memory per Barrage‑1 step
local barrage1Showcased = {} -- [stepIdx] = true once the showcase runs for that step

local function cancelBarrage1Route()
	if barrage1RouteActive then
		dbg_route("cancelBarrage1Route()")
		barrage1RouteToken += 1
		barrage1RouteActive = false
		clearBuildMenuPulsesExcept(nil)
	end
end

local function resolveRouteStageKey(stage, id, wantMajor, wantHub)
	if not stage then return nil, nil end
	if stage.kind == "major" then
		local major = stage.major or wantMajor
		if major then
			local key = resolveMajorKey(major) -- FIX: use robust resolver
			return key, UDim2.new(0,0,-0.12,0)
		end
	elseif stage.kind == "hub" then
		local major = stage.major or wantMajor
		local hub   = stage.hub or wantHub
		if hub then
			local key = resolveHubKey(major or wantMajor, hub)
			return key or resolveMajorKey("Supply"), UDim2.new(0,0,-0.12,0)
		end
	elseif stage.kind == "item" then
		local itemId = stage.item and canonItem(stage.item) or id
		if itemId then
			return "BM_" .. itemId, stage.offset or UDim2.new(0,0,-0.18,0)
		end
	end
	return nil, nil
end

local function startBarrage1RouteSequence(idx, id, wantMajor, wantHub)
	local route = BARRAGE1_ROUTE_STEPS[idx]
	if not route or #route == 0 or not id then
		barrage1LastIndex = idx or 0
		return
	end

	cancelBarrage1Route()
	barrage1RouteToken += 1
	local myToken = barrage1RouteToken
	barrage1RouteActive = true
	barrage1LastIndex = idx

	-- ADD: mark this step as having shown the showcase once
	barrage1Showcased[idx] = true

	dbg_route("start route idx=%d id=%s wantMajor=%s wantHub=%s", tonumber(idx or -1), tostring(id), tostring(wantMajor), tostring(wantHub))

	task.spawn(function()
		for _, stage in ipairs(route) do
			if barrage1RouteToken ~= myToken then dbg_route("route token mismatch; abort"); return end
			local key, offset = resolveRouteStageKey(stage, id, wantMajor, wantHub)
			dbg_route("stage kind=%s -> key=%s", tostring(stage.kind), tostring(key))
			if key then
				requestPulseAndArrow(key, offset)
				clearBuildMenuPulsesExcept(key)
			end
			task.wait(stage.duration or ROUTE_STAGE_DURATION)
		end

		if barrage1RouteToken ~= myToken then dbg_route("route token mismatch post-stage; abort"); return end

		barrage1RouteActive = false
		clearBuildMenuPulsesExcept(nil)
		dbg_route("route finished; hand back to orchestrator")
		-- Keep the orchestrator in charge after the showcase; avoid immediately starting the route again.
		task.defer(function()
			if arrowAndGateToCurrentStep then
				arrowAndGateToCurrentStep(true) -- keep this 'true' here to prevent a route loop
			end
		end)
	end)
end

------------------------
-- Guard router events --
------------------------
local function emitGuard(how, step)
	if step then BE_GridGuard:Fire(how, step) end
end

-- Show a routing hint (tab/hub) for a desired item, based on committed BuildMenu state.
local function showRoutingHintsForItemId(id)
	local wantMajor = majorForItem(id)
	local wantHub   = hubForItem(id)
	local curMajor  = getCommittedMajor()
	local curHub    = getCommittedHub(curMajor)
	dbg_route("Routing hints: id=%s wantMajor=%s wantHub=%s curMajor=%s curHub=%s",
		tostring(id), tostring(wantMajor), tostring(wantHub), tostring(curMajor), tostring(curHub))

	if wantMajor and curMajor ~= wantMajor then
		local k = MAJOR_HINT_KEYS[wantMajor]
		if k then showOB1(k, DUR.ROUTE) end
	elseif wantHub and curHub ~= wantHub then
		local k = HUB_HINT_KEYS[wantHub]
		if k then showOB1(k, DUR.ROUTE) end
	end
end

-- If the same tool remains selected into the next step, visibly repulse its tile
local function repulseSameToolIfNeeded(id)
	if not id then return end
	local bm = buildMenu()
	if bm and bm.Enabled and _G.OB_CurrentTool == id then
		dbg_ui("RepulseSameTool id=%s (already selected)", tostring(id))
		UIPulse.stop("BM_"..id)
		requestPulseAndArrow("BM_"..id, UDim2.new(0,0,-0.18,0))
		clearBuildMenuPulsesExcept("BM_"..id)
	end
end

-- Deterministic repulse on guard start (covers Flow advance)
BE_GridGuard.Event:Connect(function(how, step)
	if not _G.OB_ENABLED then return end
	if how == "start" and step then
		local id = canonItem(step.mode or step.item)
		if id then
			dbg_fb("BE_GridGuard start -> pulse %s", tostring(id))
			task.defer(function()
				Pulse(id)
				guardPulseItem = id
			end)
		end
	end
end)

-- GuardStart with resumeAt support + immediate pulse
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

	local cur = guardSeq[guardIdx]
	if activeSeq == "barrage1" and guardIdx == 1 then
		showOB1(LANG.OB1_BEGIN, DUR.BEGIN)
	end

	if cur then
		if activeSeq == "barrage1" then
			local hintKey = OB1_STEP_HINT_KEYS[guardIdx]
			if hintKey then showOB1(hintKey, DUR.HINT) end
		elseif activeSeq == "barrage2" then
			local id = canonItem(cur.mode or cur.item)
			if id == "WindTurbine" or id == "PowerLines" then
				showB2(LANG.OB2_CONNECT_POWER, DUR.HINT)
			elseif id == "WaterPipe" then
				showB2(LANG.OB2_CONNECT_WATER, DUR.HINT)
			end
		elseif activeSeq == "barrage3" then
			showB3(LANG.OB3_Industrial_Hint, DUR.HINT)
		end

		local id = canonItem(cur.mode or cur.item)
		if id then
			showRoutingHintsForItemId(id)
			Pulse(id)                 -- initial pulse
			guardPulseItem = id
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

-- Debounced polling helper
local function pollCommittedEquality(getter, want, timeout, stableWindow)
	local start = os.clock()
	local stableAt = nil
	local last = nil
	timeout = timeout or COMMIT_TIMEOUT
	stableWindow = stableWindow or COMMIT_STABLE
	dbg_bm("pollCommitted: want=%s timeout=%.2f stable=%.2f", tostring(want), timeout, stableWindow)
	while os.clock() - start < timeout do
		task.wait(0.05)
		local cur = getter()
		if cur == want then
			if last ~= want then
				last = want
				stableAt = os.clock()
			elseif os.clock() - stableAt >= stableWindow then
				dbg_bm("pollCommitted: satisfied want=%s", tostring(want))
				return true
			end
		else
			last = cur
			stableAt = nil
		end
	end
	dbg_bm("pollCommitted: timeout want=%s", tostring(want))
	return false
end

-- CLEAN + FIXED: balanced ends, and showcase gated to once-per-step + skip on open/gate-only
arrowAndGateToCurrentStep = function(skipRoute)
	dbg_route("orchestrate (skipRoute=%s) activeSeq=%s owner=%s lastKey=%s",
		tostring(skipRoute), tostring(activeSeq), tostring(arrowOwner), tostring(lastArrowKey))

	-- If asked, cancel any in‑progress route (showcase)
	if skipRoute == true and barrage1RouteActive then
		cancelBarrage1Route()
	end

	local skipBarrageRoute = (skipRoute == true)

	-- Prefer guard/flow hints when present; fall back to explicit server gates (B2/B3).
	local guardItem = guardCurrentItem()
	local flowState = (activeSeq == "barrage1") and getFlowState() or nil
	local flowItem  = flowState and flowState.current and canonItem(flowState.current.mode or flowState.current.item) or nil
	local id        = guardItem or flowItem or currentGateId
	dbg_route("choose id: guard=%s flow=%s gate=%s -> id=%s",
		tostring(guardItem), tostring(flowItem), tostring(currentGateId), tostring(id))

	if not id then
		cancelBarrage1Route()
		dbg_route("no id to guide; exit")
		return
	end

	applyGate(id)

	if activeSeq ~= "barrage1" then
		barrage1LastIndex = 0
	end

	-- If user already has the correct tool selected
	if _G.OB_CurrentTool == id then
		cancelBarrage1Route()
		clearBuildMenuPulsesExcept(nil)
		if activeSeq == "barrage1" then
			dbg_route("tool already selected (%s), repulse tile", tostring(id))
			repulseSameToolIfNeeded(id)
		else
			dbg_route("tool already selected (%s), hide global arrow", tostring(id))
			HideArrow("tool-already-selected")
		end
		return
	end

	-- If Build Menu is closed, just nudge the Build button
	local bm = buildMenu()
	if not (bm and bm.Enabled) then
		cancelBarrage1Route()
		if activeSeq == "barrage1" then
			barrage1LastIndex = 0
		end
		dbg_route("BM closed; nudge BuildButton")
		requestPulseAndArrow("BuildButton", UDim2.new(0,0,-0.12,0))
		clearBuildMenuPulsesExcept(nil)
		return
	end

	local wantMajor = majorForItem(id)
	local wantHub   = hubForItem(id)
	local curMajor  = getCommittedMajor()
	local curHub    = getCommittedHub(curMajor)
	dbg_route("routing id=%s wantMajor=%s wantHub=%s curMajor=%s curHub=%s",
		tostring(id), tostring(wantMajor), tostring(wantHub), tostring(curMajor), tostring(curHub))

	-- In B1, run a short showcase route ONCE per step if allowed
	if activeSeq == "barrage1" then
		local running = flowState and flowState.running == true
		if not skipBarrageRoute and running then
			local idx = tonumber(flowState.index)
			if idx and idx >= 1 then
				if BARRAGE1_ROUTE_STEPS[idx] and not barrage1Showcased[idx] then
					dbg_route("B1 showcase route idx=%d (first time for this step)", idx)
					startBarrage1RouteSequence(idx, id, wantMajor, wantHub)
				else
					dbg_route("B1 showcase suppressed for idx=%d (already shown or no route)", tonumber(idx or -1))
					barrage1LastIndex = idx
					cancelBarrage1Route()
				end
			end
		else
			if not running then
				barrage1LastIndex = 0
				cancelBarrage1Route()
			end
		end
	else
		cancelBarrage1Route()
	end

	if barrage1RouteActive and skipRoute ~= true then
		dbg_route("route active; skip explicit targeting")
		return
	end

	-- Target appropriate UI (major → hub → item)
	local targetKey
	if (not wantMajor) or (curMajor ~= wantMajor) then
		targetKey = resolveMajorKey(wantMajor or "Transport")
		dbg_route("target major key=%s", tostring(targetKey))
		requestPulseAndArrow(targetKey, UDim2.new(0,0,-0.12,0))

		-- Watch for stable commit into the correct major
		hubWatchToken += 1
		local my = hubWatchToken
		local want = wantMajor
		task.spawn(function()
			if my ~= hubWatchToken then return end
			local ok = pollCommittedEquality(function() return getCurrentMajor(true) end, want, COMMIT_TIMEOUT, COMMIT_STABLE)
			if ok and my == hubWatchToken then
				setCommitted(want, nil)
				arrowAndGateToCurrentStep(true)
			end
		end)
	else
		if wantHub and curHub ~= wantHub then
			targetKey = resolveHubKey(wantMajor, wantHub) or resolveMajorKey("Supply")
			dbg_route("target hub key=%s", tostring(targetKey))
			requestPulseAndArrow(targetKey, UDim2.new(0,0,-0.12,0))

			-- Watch for stable commit into the correct hub
			hubWatchToken += 1
			local my = hubWatchToken
			task.spawn(function()
				if my ~= hubWatchToken then return end
				local ok = pollCommittedEquality(function() return getCurrentHub(wantMajor, true) end, wantHub, COMMIT_TIMEOUT, COMMIT_STABLE)
				if ok and my == hubWatchToken then
					setCommitted(nil, wantHub)
					arrowAndGateToCurrentStep(true)
				end
			end)
		else
			targetKey = "BM_" .. id
			dbg_route("target item key=%s", tostring(targetKey))
			requestPulseAndArrow(targetKey, UDim2.new(0,0,-0.18,0))
		end
	end

	clearBuildMenuPulsesExcept(targetKey)
end

local function clearArrowAndGate()
	dbg_route("clearArrowAndGate()")
	applyGate(nil)
	cancelBarrage1Route()
	if activeSeq == "barrage1" then
		barrage1LastIndex = 0
	end
	if lastArrowKey then clearPulseAndArrow(lastArrowKey) end
	HideArrow("clearArrowAndGate")
end

----------------------------
-- Registry rebind handling
----------------------------
UITargetRegistry.Changed():Connect(function(chKey, inst)
	dbg_ui("UITargetRegistry changed: key=%s inst=%s", tostring(chKey), inst and inst:GetFullName() or "<nil>")
	if wantPulse[chKey] then
		UIPulse.stop(chKey)
		if gateAllows(chKey) then UIPulse.start(chKey) end
	end
end)

------------------------------
-- BuildMenu open/close hook --
------------------------------
local bmOpenHintShown = false

local _bmFlipAt = nil
local _bmHoldSeconds = 0.30
local function _bmStable()
	return (not _bmFlipAt) or ((os.clock() - _bmFlipAt) > _bmHoldSeconds)
end

task.defer(function()
	local bm = buildMenu() or PlayerGui:WaitForChild("BuildMenu")
	if not (bm and bm:IsA("ScreenGui")) then dbg_bm("BuildMenu not found; abort hook"); return end

	-- Prevent re-entrancy if Enabled flips rapidly
	local applyBusy = false
	local function apply()
		if applyBusy then dbg_bm("apply() ignored (busy)"); return end
		applyBusy = true

		dbg_bm("apply() BM.Enabled=%s OB_ENABLED=%s", tostring(bm.Enabled), bools(_G.OB_ENABLED))

		-- If onboarding is disabled, hard-clear any UI artifacts and bail
		if not _G.OB_ENABLED then
			dbg_bm("OB disabled → clear all UI traces")
			clearAllUIPulses()
			clearArrowAndGate()
			HideArrow("OB-disabled")
			applyBusy = false
			return
		end

		if bm.Enabled then
			dbg_bm("BM OPEN: clear BuildButton nudge, snapshot commits, applyGate(%s), then orchestrate", tostring(currentGateId))
			-- Menu just opened: remove the BuildButton nudge and re-apply visual gate
			bmOpenHintShown = false
			clearPulseAndArrow("BuildButton")

			-- Snapshot whatever BM currently considers selected as a committed baseline
			setCommitted(getCurrentMajor(), getCurrentHub(getCurrentMajor()))

			-- Visual-only: highlight/lock allowed button without mutating tab/hub
			if currentGateId then
				applyGate(currentGateId)
			end

			-- Defer routing until BuildMenu has fully realized its layout
			task.defer(function()
				-- IMPORTANT: skip showcase route on open
				arrowAndGateToCurrentStep(true)
			end)
		else
			dbg_bm("BM CLOSE: request BuildButton arrow + hint")
			-- Menu closed: nudge user to open it
			requestPulseAndArrow("BuildButton", UDim2.new(0,0,-0.12,0))
			if not bmOpenHintShown then
				showOB1(LANG.OB_OPEN_BUILD_MENU, DUR.ROUTE)
				bmOpenHintShown = true
			end
			clearBuildMenuPulsesExcept("BuildButton")
		end

		applyBusy = false
	end

	bm:GetPropertyChangedSignal("Enabled"):Connect(function()
		_bmFlipAt = os.clock()               -- ← add this line
		dbg_bm("BM.Enabled changed -> %s", tostring(bm.Enabled))
		apply()
	end)
	apply()
end)

----------------------------
-- Global toggle handling  --
----------------------------
_G.OB_ENABLED = false
local function applyToggle(enabled)
	_G.OB_ENABLED = (enabled ~= false)
	dbg_bm("applyToggle -> %s", bools(_G.OB_ENABLED))
	if not _G.OB_ENABLED then
		if guardPulseItem  then Stop(guardPulseItem);  guardPulseItem  = nil end
		if serverPulseItem then Stop(serverPulseItem); serverPulseItem = nil end
		clearAllUIPulses()
		clearArrowAndGate()
		clearB2()
		clearB3()
		-- reset one-time showcases when disabling
		barrage1Showcased = {}
	else
		local id = guardCurrentItem() or getFlowItem()
		if id then
			Pulse(id)      -- pulse on enable
			guardPulseItem = id
		end
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
do
	if not OnboardingFlow then
		local ok, mod = pcall(function()
			return require(ReplicatedStorage.Scripts.Onboarding.OnboardingFlow)
		end)
		if ok and type(mod) == "table" then
			OnboardingFlow = mod
		end
	end
end

-- FIX: restructured and de-bugged guard feedback handler (no mismatched ends)
BE_GuardFB.Event:Connect(function(tag, info)
	if not _G.OB_ENABLED then return end

	-- Normalize feedback + figure out what the guard expects right now
	local fbItem   = info and canonItem(info.item or info.mode)
	local expected = guardCurrentItem() or getFlowItem() -- prefer our guard; fall back to flow

	dbg_fb("tag=%s fbItem=%s expected=%s idx=%d/%d",
		tostring(tag), tostring(fbItem), tostring(expected), guardIdx, #guardSeq)

	-- Drop stale feedback
	if fbItem and expected and fbItem ~= expected then
		dbg_fb("ignore stale feedback for %s (expect %s)", tostring(fbItem), tostring(expected))
		return
	end

	-- Is Flow running (B1 canonical progression)?
	local flowRunning = false
	do
		local F = OnboardingFlow
		if not F then
			local ok, mod = pcall(function() return require(ReplicatedStorage.Scripts.Onboarding.OnboardingFlow) end)
			if ok then F = mod; OnboardingFlow = mod end
		end
		if F and type(F.GetState)=="function" then
			local st = F.GetState()
			flowRunning = (st and st.running) == true
		end
	end

	-- ===== DONE =====
	if tag == "done" then
		if flowRunning then
			local reportedItem = fbItem
			local prevExpected = expected
			task.defer(function()
				local F = OnboardingFlow
				if not (F and type(F.GetState)=="function") then return end
				local st = F.GetState()
				local justDone = math.max(((st and st.index) or 1) - 1, 1)
				dbg_fb("flow done justDone=%d", justDone)

				-- Sequence-specific "done" toast
				if activeSeq == "barrage1" then
					local doneKey = OB1_STEP_DONE_KEYS[justDone]
					if doneKey then showOB1(doneKey, DUR.DONE) end
				elseif activeSeq == "barrage3" then
					showB3(LANG.OB3_Industrial_Done, DUR.DONE)
				end

				-- Stop any pulse for the reported (or expected) item
				local id = reportedItem or (st and st.expected and canonItem(st.expected)) or prevExpected
				if id then Stop(id); if guardPulseItem == id then guardPulseItem = nil end end

				-- Keep routing fresh: cancel any old showcase and allow a new Supply→Water→Item chain
				clearBuildMenuPulsesExcept(nil)
				cancelBarrage1Route()
				local bm = buildMenu()
				if bm and bm.Enabled then
					arrowAndGateToCurrentStep() -- NOTE: allow the route to run
				else
					requestPulseAndArrow("BuildButton", UDim2.new(0,0,-0.12,0))
					showOB1(LANG.OB_OPEN_BUILD_MENU, DUR.ROUTE)
				end

				-- Next step hint + re‑pulse next expected item (persists until the next step)
				if st and st.running and st.current and activeSeq == "barrage1" then
					local nextIdx = math.min(st.index, #OB1_STEP_HINT_KEYS)
					local hintKey = OB1_STEP_HINT_KEYS[nextIdx]
					if hintKey then showOB1(hintKey, DUR.HINT) end
					local nextId = canonItem(st.current.mode or st.current.item)
					if nextId then
						showRoutingHintsForItemId(nextId)
						task.defer(function()
							Pulse(nextId)
							guardPulseItem = nextId
							-- If same tool remains selected, visibly repulse the tile again
							repulseSameToolIfNeeded(nextId)
						end)
					end
				elseif activeSeq == "barrage1" then
					showOB1(LANG.OB1_COMPLETE, DUR.COMPLETE)
				end
			end)
			return
		end

		-- ===== Legacy / local guard driver path (B2/B3 or pre‑Flow) =====
		local justDone = math.max(guardIdx, 1)
		dbg_fb("legacy done justDone=%d", justDone)

		if activeSeq == "barrage1" then
			local doneKey = OB1_STEP_DONE_KEYS[justDone]
			if doneKey then showOB1(doneKey, DUR.DONE) end
		elseif activeSeq == "barrage3" then
			showB3(LANG.OB3_Industrial_Done, DUR.DONE)
			pcall(function() StepCompleted:FireServer("B3_ZonePlaced") end)
		elseif activeSeq == "barrage2" then
			-- Contextual next coaching for B2
			if justDone == 1 then
				showB2(LANG.OB2_CONNECT_POWER, DUR.HINT)
			elseif justDone == 2 then
				showB2(LANG.OB2_CONNECT_WATER, DUR.HINT)
			end
		end

		pcall(function()
			StepCompleted:FireServer("GuardStepDone", {
				seq   = activeSeq or "barrage1",
				index = justDone,
				total = #guardSeq,
			})
		end)

		local id = fbItem or expected
		if id then Stop(id); if guardPulseItem == id then guardPulseItem = nil end end

		local wasLast = justDone >= #guardSeq
		if wasLast then
			if activeSeq ~= "barrage2" then
				pcall(function() StepCompleted:FireServer("OnboardingFinished") end)
			else
				pcall(function() StepCompleted:FireServer("B2_LocalSequenceFinished") end)
			end
		end
		GuardAdvance()

		clearBuildMenuPulsesExcept(nil)
		local bm = buildMenu()
		if bm and bm.Enabled then
			arrowAndGateToCurrentStep()
		else
			requestPulseAndArrow("BuildButton", UDim2.new(0,0,-0.12,0))
			showOB1(LANG.OB_OPEN_BUILD_MENU, DUR.ROUTE)
		end

		if guardSeq[guardIdx] then
			if activeSeq == "barrage1" then
				local hintKey = OB1_STEP_HINT_KEYS[guardIdx]
				if hintKey then showOB1(hintKey, DUR.HINT) end
			elseif activeSeq == "barrage2" then
				local nid = canonItem(guardSeq[guardIdx].mode or guardSeq[guardIdx].item)
				if nid == "PowerLines" then
					showB2(LANG.OB2_CONNECT_POWER, DUR.HINT)
				elseif nid == "WaterPipe" then
					showB2(LANG.OB2_CONNECT_WATER, DUR.HINT)
				end
			end
			local nextId = canonItem(guardSeq[guardIdx].mode or guardSeq[guardIdx].item)
			if nextId then
				showRoutingHintsForItemId(nextId)
				Pulse(nextId)
				guardPulseItem = nextId
			end
		else
			if activeSeq == "barrage1" then
				showOB1(LANG.OB1_COMPLETE, DUR.COMPLETE)
			end
		end

		-- ===== CANCELED =====
	elseif tag == "canceled" then
		if flowRunning then
			if fbItem then
				Stop(fbItem)
				if guardPulseItem == fbItem then guardPulseItem = nil end
			end
			barrage1LastIndex = 0
			local bm = buildMenu()
			if bm and bm.Enabled then arrowAndGateToCurrentStep(true) end
			return
		end

		if fbItem then
			Stop(fbItem)
			if guardPulseItem == fbItem then guardPulseItem = nil end
		end

		local cur = guardSeq[math.max(guardIdx, 1)]
		if cur then
			dbg_fb("re-guarding current step after canceled")
			emitGuard("start", cur)

			local want = canonItem(cur.mode or cur.item)
			if want then
				Pulse(want); guardPulseItem = want
				local bm = buildMenu()
				if bm and bm.Enabled then
					arrowAndGateToCurrentStep(true)
				end
			end
		end

		-- ===== CLEARED =====
	elseif tag == "cleared" then
		if flowRunning then
			local F = OnboardingFlow
			local st = F and F.GetState and F.GetState() or nil
			if fbItem then Stop(fbItem) end
			if st and st.current then
				local want = canonItem(st.current.mode or st.current.item)
				if want then Pulse(want); guardPulseItem = want end
			end
			barrage1LastIndex = 0
			local bm = buildMenu()
			if bm and bm.Enabled then arrowAndGateToCurrentStep(true) end
			return
		end

		local cur = guardSeq[math.max(guardIdx, 1)]
		if cur then
			if fbItem then Stop(fbItem) end
			dbg_fb("cleared → re-guard current step")
			emitGuard("start", cur)
			local want = canonItem(cur.mode or cur.item)
			if want then Pulse(want); guardPulseItem = want end
		end

	else
		dbg_fb("unknown tag=%s (ignored)", tostring(tag))
	end
end)

-----------------------------
-- Tool selection feedback --
-----------------------------
DisplayGrid.OnClientEvent:Connect(function(mode)
	if not _G.OB_ENABLED then return end
	local item = canonItem(mode)
	_G.OB_CurrentTool = item
	dbg_ui("DisplayGrid.OnClientEvent item=%s", tostring(item))
	if item == "DirtRoad" then pcall(function() StepCompleted:FireServer("RoadToolSelected") end) end
	-- Also clear gate when selecting WaterTower/WindTurbine
	if item == "WaterPipe"  or item == "WaterTower"  then pcall(function() StepCompleted:FireServer("WaterToolSelected") end)  end
	if item == "PowerLines" or item == "WindTurbine" then pcall(function() StepCompleted:FireServer("PowerToolSelected") end) end
	if item == "WaterPipe" or item == "WaterTower" then dbg_ui("Water tool picked: %s", item) end
	if item == "PowerLines" or item == "WindTurbine" then dbg_ui("Power tool picked: %s", item) end
	if guardPulseItem and item == guardPulseItem then Stop(guardPulseItem); guardPulseItem = nil end
	if serverPulseItem and item == serverPulseItem then Stop(serverPulseItem); serverPulseItem = nil end
	-- FIX: remove Stop(nil); keep global stop only
	Stop("*")
	clearBuildMenuPulsesExcept(nil)

	-- User action should immediately cut any staged routing and re-evaluate
	if activeSeq == "barrage1" then
		cancelBarrage1Route()
		arrowAndGateToCurrentStep(true)
	end
end)

----------------------------
-- Server → Client nudges  --
----------------------------
local function bmGateOnly(id, offset)
	applyGate(id)
	local bm = buildMenu()
	if not (bm and bm.Enabled) then
		dbg_bm("bmGateOnly(%s) while BM closed → orchestrate()", tostring(id))
		-- IMPORTANT: skip showcase route if BM is closed
		arrowAndGateToCurrentStep(true)
		return
	end

	local wantMajor, wantHub = majorForItem(id), hubForItem(id)
	local curMajor = getCommittedMajor()
	local curHub   = getCommittedHub(curMajor)
	dbg_bm("bmGateOnly id=%s wantMajor=%s wantHub=%s curMajor=%s curHub=%s", tostring(id), tostring(wantMajor), tostring(wantHub), tostring(curMajor), tostring(curHub))

	-- If already on the item, gentle BM repulse in B1 to reaffirm the step
	if _G.OB_CurrentTool == id then
		clearBuildMenuPulsesExcept(nil)
		if activeSeq == "barrage1" then
			dbg_bm("bmGateOnly repulse same tool %s", tostring(id))
			repulseSameToolIfNeeded(id)
		else
			dbg_bm("bmGateOnly hide global arrow; same tool already selected")
			HideArrow("bmGateOnly-same-tool")
		end
		return
	end

	local key
	if wantMajor and (curMajor ~= wantMajor) then
		key = resolveMajorKey(wantMajor) -- FIX: robust major key
		dbg_bm("bmGateOnly target major key=%s", tostring(key))
		requestPulseAndArrow(key, offset or UDim2.new(0,0,-0.12,0))

		-- Always watch for stable commit
		hubWatchToken += 1
		local my = hubWatchToken
		local want = wantMajor
		task.spawn(function()
			if my ~= hubWatchToken then return end
			local ok = pollCommittedEquality(function() return getCurrentMajor(true) end, want, COMMIT_TIMEOUT, COMMIT_STABLE)
			if ok and my == hubWatchToken then
				setCommitted(want, nil)
				bmGateOnly(id, offset)
			end
		end)

	else
		if wantHub and (curHub ~= wantHub) then
			key = resolveHubKey(wantMajor or "Supply", wantHub) or resolveMajorKey("Supply")
			dbg_bm("bmGateOnly target hub key=%s", tostring(key))
			requestPulseAndArrow(key, offset or UDim2.new(0,0,-0.12,0))

			hubWatchToken += 1
			local my = hubWatchToken
			task.spawn(function()
				if my ~= hubWatchToken then return end
				local ok = pollCommittedEquality(function() return getCurrentHub(wantMajor) end, wantHub, COMMIT_TIMEOUT, COMMIT_STABLE)
				if ok and my == hubWatchToken then
					setCommitted(nil, wantHub)
					bmGateOnly(id, offset)
				end
			end)
		else
			key = "BM_"..id
			dbg_bm("bmGateOnly target item key=%s", tostring(key))
			requestPulseAndArrow(key, offset or UDim2.new(0,0,-0.18,0))
		end
	end
	clearBuildMenuPulsesExcept(key)
end

StateChanged.OnClientEvent:Connect(function(stepName, payload)
	dbg("[STATE] %s", tostring(stepName))
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
	if stepName == "HideArrow" then HideArrow("server-asked"); return end
	if stepName == "BuildMenu_GateOnly" and typeof(payload)=="table" then
		local id = canonItem(payload.itemID or payload.item)
		if id then bmGateOnly(id, payload.offset) end
		return
	end
	if stepName == "BuildMenu_GateOnly_Current" then
		-- Gate only; do not trigger a showcase route
		arrowAndGateToCurrentStep(true)
		return
	end
	if stepName == "BuildMenu_GateClear"        then clearArrowAndGate(); return end

	-- Barrage 1 (Flow-driven; resume supported)
	if stepName == "Onboarding_StartBarrage1" then
		if guardPulseItem  then Stop(guardPulseItem);  guardPulseItem  = nil end
		if serverPulseItem then Stop(serverPulseItem); serverPulseItem = nil end
		activeSeq = "barrage1"
		cancelBarrage1Route()
		barrage1LastIndex = 0
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

		-- Flow is the canonical source of truth for B1
		local Flow = OnboardingFlow or (function()
			local ok, mod = pcall(function()
				return require(ReplicatedStorage.Scripts.Onboarding.OnboardingFlow)
			end)
			if ok then OnboardingFlow = mod end
			return OnboardingFlow
		end)()

		-- Let Flow own BE_GridGuard emissions & persistence.
		guardSeq, guardIdx = {}, 0
		if Flow and type(Flow.StartSequence)=="function" then
			pcall(function() Flow.StartSequence(barrage1(), resumeAt) end)
		end

		-- Begin banner only on a true start (not resume)
		if resumeAt <= 1 then showOB1(LANG.OB1_BEGIN, DUR.BEGIN) end

		-- ADD: reset one-time showcases on fresh start
		if resumeAt <= 1 then
			barrage1Showcased = {}
		end

		-- Pulse & route to the current expected tool.
		local st = (Flow and type(Flow.GetState)=="function") and Flow.GetState() or nil
		local cur = st and st.current
		if cur then
			local id = canonItem(cur.mode or cur.item)
			if id then
				Pulse(id)
				guardPulseItem = id
			end
		end

		-- Only run the showcase automatically on a true start; skip when resuming
		if resumeAt <= 1 then
			arrowAndGateToCurrentStep()
		else
			arrowAndGateToCurrentStep(true)
		end
		return
	end

	-- ===== Barrage 2 (Utilities) =====
	if stepName == "Onboarding_B2_Begin" or stepName == "Onboarding_StartBarrage2" then
		if guardPulseItem  then Stop(guardPulseItem);  guardPulseItem  = nil end
		if serverPulseItem then Stop(serverPulseItem); serverPulseItem = nil end
		if not _G.OB_ENABLED then applyToggle(true) end
		activeSeq = "barrage2"
		cancelBarrage1Route()
		barrage1LastIndex = 0

		local function barrage2()
			return {
				{ item="WindTurbine", mode="WindTurbine", kind="point", from={x=3,  z=0} },
				{ item="PowerLines",  mode="PowerLines",  kind="line",  from={x=3,  z=10}, to={x=3, z=22}, requireExactEnd=true },
				{ item="WaterPipe",   mode="WaterPipe",   kind="line",  from={x=3,  z=10}, to={x=3, z=22}, requireExactEnd=true },
			}
		end
		local resumeAt = (typeof(payload)=="table" and tonumber(payload.resumeAt)) or 1

		GuardStart(barrage2(), resumeAt)
		local cur = guardSeq[guardIdx]; if cur then local id = canonItem(cur.mode or cur.item); Pulse(id); guardPulseItem = id end
		arrowAndGateToCurrentStep()
		return
	end

	-- Barrage 2 legacy hints (no-op if barrage2 running)
	if stepName == "Onboarding_B2_Begin_LegacyHint" then
		dbg("[OB] Barrage 2 legacy coaching")
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
		dbg("[OB] Barrage 2 complete: all buildings have Water & Power")
		showB2(LANG.OB2_COMPLETE, 2)
		task.delay(2, clearB2)
		clearArrowAndGate()
		return
	end

	if stepName == "Onboarding_ShowHint_WaterDeficit" and typeof(payload)=="table" then
		if activeSeq == "barrage2" then return end
		dbg("[OB] Water deficit → produced=%s required=%s", tostring(payload.produced), tostring(payload.required))
		showB2(LANG.OB2_WATER_DEFICIT, 5)
		bmGateOnly("WaterTower", UDim2.new(0,0,-0.12,0))
		return
	end

	if stepName == "Onboarding_ShowHint_ConnectBuildingsToWater" and typeof(payload)=="table" then
		if activeSeq == "barrage2" then return end
		dbg("[OB] Connect WATER to buildings; example zone:", tostring(payload.zoneId))
		showB2(LANG.OB2_CONNECT_WATER, 5)
		bmGateOnly("WaterPipe", UDim2.new(0,0,-0.12,0))
		return
	end

	if stepName == "Onboarding_ShowHint_PowerDeficit" and typeof(payload)=="table" then
		if activeSeq == "barrage2" then return end
		dbg("[OB] Power deficit → produced=%s required=%s", tostring(payload.produced), tostring(payload.required))
		showB2(LANG.OB2_POWER_DEFICIT, 5)
		bmGateOnly("WindTurbine", UDim2.new(0,0,-0.12,0))
		return
	end

	if stepName == "Onboarding_ShowHint_ConnectBuildingsToPower" and typeof(payload)=="table" then
		if activeSeq == "barrage2" then return end
		dbg("[OB] Connect POWER to buildings; example zone:", tostring(payload.zoneId))
		showB2(LANG.OB2_CONNECT_POWER, 5)
		bmGateOnly("PowerLines", UDim2.new(0,0,-0.12,0))
		return
	end

	-- ===== Barrage 3 (Industrial) =====
	if stepName == "Onboarding_B3_Begin" then
		dbg("[OB] Barrage 3 begin: Industrial placement + connectivity")
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
		local cur = guardSeq[guardIdx]; if cur then local id = canonItem(cur.mode or cur.item); Pulse(id); guardPulseItem = id end
		arrowAndGateToCurrentStep()
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
			dbg_bm("self-nudge seed: request BuildButton arrow")
			requestPulseAndArrow("BuildButton", UDim2.new(0,0,-0.12,0))
			showOB1(LANG.OB_OPEN_BUILD_MENU, DUR.ROUTE)
		end
	end
end)

-- Use explicit tab change events as committed selection when available
task.defer(function()
	if BE_TabChanged and BE_TabChanged:IsA("BindableEvent") then
		BE_TabChanged.Event:Connect(function(a, b)
			-- Some emitters send ("major","Transport") or ("hub","Water") or (major, hub)
			dbg_bm("BE_TabChanged a=%s b=%s", tostring(a), tostring(b))
			if a == "major" then
				setCommitted(b, nil)
			elseif a == "hub" then
				setCommitted(nil, b)
			else
				setCommitted(a, b)
			end
			-- A real click should immediately cancel staged routing and re-evaluate.
			if _G.OB_ENABLED and buildMenu() and buildMenu().Enabled then
				cancelBarrage1Route()
				arrowAndGateToCurrentStep(true)
			end
		end)
	end
end)
