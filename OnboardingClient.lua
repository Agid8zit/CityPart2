-- StarterPlayerScripts/OnboardingController.client.lua
-- Authoritative fallback: ensures onboarding bindables exist exactly once,
-- owns pulsing start/stop, and prevents race conditions across steps.

-- Services
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

-- Locals
local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- Deps
local UITargetRegistry = require(ReplicatedStorage.Scripts.UI.UITargetRegistry)

-- ========= Folders / Bindables =========

local function ensureFolder(parent: Instance, name: string): Instance
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

local Events   = ensureFolder(ReplicatedStorage, "Events")
local RE       = ensureFolder(Events, "RemoteEvents")
local BE       = ensureFolder(Events, "BindableEvents")
local BFOLDER  = ensureFolder(Events, "BindableFunctions") -- cache once for speed

-- server-authoritative toggle comes from a RemoteEvent
local RE_Toggle = RE:WaitForChild("OnboardingToggle")

local function ensureBindable(className: string, name: string)
	local obj = BE:FindFirstChild(name)
	if obj then
		if obj.ClassName ~= className then
			warn(("[Onboarding] %s exists as %s (expected %s). Using existing to avoid breaking references."):format(
				name, obj.ClassName, className
				))
		end
		return obj
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = BE
	return inst
end

-- For BuildMenu gating (default allow unless Flow overrides later)
local BF_CheckItemAllowed = ensureBindable("BindableFunction", "OBCheckItemAllowed")
BF_CheckItemAllowed.OnInvoke = function(_itemID: string)
	return { allowed = true }
end

-- Item pulse channels (GridVisualizer / Flow)
local BE_PulseItem     = ensureBindable("BindableEvent", "OBPulseItem")
local BE_StopPulseItem = ensureBindable("BindableEvent", "OBStopPulseItem")
local BE_GridGuard     = ensureBindable("BindableEvent", "OBGridGuard")
local BE_GuardFB       = ensureBindable("BindableEvent", "OBGuardFeedback")

-- Global toggle (kept for local fan-out so other client modules can still listen if they want)
local BE_Toggle        = ensureBindable("BindableEvent", "OnboardingToggle")

-- ======== BuildMenu integration: listen to major-tab changes (if available) ===
-- We DO NOT create this; BuildMenu owns it. We only listen if it exists.
local BE_TabChanged = BE:FindFirstChild("OB_BuildMenu_TabChanged") -- :Fire("major", "Transport"|"Zones"|"Supply"|"Services")
-- Query current major (optional).
local BF_GetMajorTab = BFOLDER:FindFirstChild("OB_BuildMenu_GetMajorTab") -- :Invoke() -> string? (Transport|Zones|Supply|Services)

-- ========= Remotes / Notifications =========

local StateChanged  = RE:WaitForChild("OnboardingStateChanged")
local StepCompleted = RE:WaitForChild("OnboardingStepCompleted")
local DisplayGrid   = RE:WaitForChild("DisplayGrid")

-- Use existing Notifications module if present; otherwise, no-op stubs (no new Instances)
local NotificationGui do
	local ok, mod = pcall(function()
		local Notifications = PlayerGui:WaitForChild("Notifications", 3)
		if not Notifications then return nil end
		local logic = Notifications:FindFirstChild("Logic") or Notifications:FindFirstChildOfClass("ModuleScript")
		return logic and require(logic) or nil
	end)
	if ok and type(mod) == "table" and type(mod.ShowHint) == "function" then
		NotificationGui = mod
	else
		NotificationGui = { ShowHint = function() end }
	end
end

-- ========= Global onboarding toggle (declare EARLY so self-nudge sees it) ====
local OB_ENABLED = false

-- ========= Canonical mode->item =========
local MODE_TO_ITEM = { Road = "DirtRoad" }
local function canonItem(x: any): string?
	if x == nil then return nil end
	local s = tostring(x)
	return MODE_TO_ITEM[s] or s
end

-- ========= Item → Major Tab mapping (used to decide where to point the arrow) =
-- NOTE: This intentionally only includes items you present in BuildMenu today.
local ITEM_TO_MAJOR: {[string]: string} = {
	-- Transport
	DirtRoad = "Transport", BusDepot = "Transport", MetroEntrance = "Transport", MetroTunnel = "Transport", Airport = "Transport",

	-- Zones
	Residential = "Zones", Commercial = "Zones", Industrial = "Zones",
	ResDense = "Zones", CommDense = "Zones", IndusDense = "Zones",

	-- Supply: Power
	PowerLines = "Supply",
	WindTurbine = "Supply", SolarPanels = "Supply", CoalPowerPlant = "Supply",
	GasPowerPlant = "Supply", GeothermalPowerPlant = "Supply", NuclearPowerPlant = "Supply",

	-- Supply: Water
	WaterPipe = "Supply",
	WaterTower = "Supply", WaterPlant = "Supply",
	PurificationWaterPlant = "Supply", MolecularWaterPlant = "Supply",

	-- Services: Education
	PrivateSchool = "Services", MiddleSchool = "Services", Museum = "Services", NewsStation = "Services",
	-- Services: Fire
	FireDept = "Services", FireStation = "Services", FirePrecinct = "Services",
	-- Services: Police
	PoliceDept = "Services", PoliceStation = "Services", PolicePrecinct = "Services", Courthouse = "Services",
	-- Services: Health
	SmallClinic = "Services", LocalHospital = "Services", CityHospital = "Services", MajorHospital = "Services",
	-- Services: Landmarks
	FerrisWheel = "Services", GasStation = "Services", Bank = "Services", TechOffice = "Services",
	NationalCapital = "Services", Obelisk = "Services", ModernSkyscraper = "Services",
	EmpireStateBuilding = "Services", SpaceNeedle = "Services", WorldTradeCenter = "Services",
	CNTower = "Services", StatueOfLiberty = "Services", EiffelTower = "Services",
	-- Services: Leisure
	Church = "Services", Mosque = "Services", ShintoTemple = "Services", HinduTemple = "Services",
	BuddhaStatue = "Services", Hotel = "Services", MovieTheater = "Services",
	-- Services: Sports
	SkatePark = "Services", TennisCourt = "Services", PublicPool = "Services",
	ArcheryRange = "Services", BasketballCourt = "Services", GolfCourse = "Services",
	SoccerStadium = "Services", BasketballStadium = "Services", FootballStadium = "Services",
	-- Services: Flags (buttons live under Leisure hub, still major == Services)
	["Flag:*"] = "Services",
}

-- Some experiences register these targets already; if not, we still degrade gracefully.
local MAJOR_TO_KEY = {
	Transport = "BM_Transport",
	Zones     = "BM_Zones",
	Supply    = "BM_Supply",   -- Only used if BuildMenu registers it via UITargetRegistry
	Services  = "BM_Services", -- Only used if BuildMenu registers it via UITargetRegistry
}

local function majorForItem(itemID: string?): string?
	if not itemID then return nil end
	-- wildcard support for dynamic flags (e.g. "Flag:USA")
	if string.sub(itemID, 1, 5) == "Flag:" then return ITEM_TO_MAJOR["Flag:*"] end
	return ITEM_TO_MAJOR[itemID]
end

-- ========= Active Guard state (shared) =======================================
-- Single-step guard bus: sequence + current index (0 means idle)
local _guardSeq = {}
local _guardIdx = 0
local _activeSeqName: string? = nil

local function _currentItemIDFromGuard(): string?
	if _guardIdx ~= 0 and _guardSeq[_guardIdx] then
		return canonItem(_guardSeq[_guardIdx].mode or _guardSeq[_guardIdx].item)
	end
	return nil
end

-- ========= Item pulse plumbing (GridVisualizer) =========

local guardPulseItem  : string? = nil
local serverPulseItem : string? = nil

local function Pulse(itemID: string)
	BE_PulseItem:Fire(itemID)
end

local function StopPulse(itemID: string?)
	-- Forward nil or "*" to downstream listeners (stop-all semantics).
	BE_StopPulseItem:Fire(itemID)
end

-- ========= Optional: re-issue current step pulse (prefer active guard step) ==

local OnboardingFlow
local function repulseCurrentStep()
	-- Prefer the currently guarded step if any
	if _guardIdx ~= 0 and _guardSeq[_guardIdx] then
		local step = _guardSeq[_guardIdx]
		local id = canonItem(step.mode or step.item)
		if id then
			if guardPulseItem and guardPulseItem ~= id then
				StopPulse(guardPulseItem)
			end
			guardPulseItem = id
			Pulse(id)
		end
		return
	end

	-- Fallback to flow (if you still use it elsewhere)
	if not OnboardingFlow then
		local ok, mod = pcall(function()
			return require(ReplicatedStorage.Scripts.Onboarding.OnboardingFlow)
		end)
		if ok then OnboardingFlow = mod end
	end
	if not OnboardingFlow or type(OnboardingFlow.GetState) ~= "function" then return end
	local st = OnboardingFlow.GetState()
	if st and st.current then
		local id = canonItem(st.current.item or st.current.mode)
		if id then
			if guardPulseItem and guardPulseItem ~= id then
				StopPulse(guardPulseItem)
			end
			guardPulseItem = id
			Pulse(id)
		end
	end
end

-- ========= Arrow helpers =========

local POS_A = UDim2.new(0.501, 0, 0.841, 0)
local POS_B = UDim2.new(0.501, 0, 0.875, 0)
local SIZE  = UDim2.new(0.053, 0, 0.1, 0)
local ROT   = 180

local function HideArrow()           pcall(NotificationGui.HideArrow) end
local function ShowHint(msg: string) pcall(NotificationGui.ShowHint, msg) end

local function ShowArrowAtKey(key: string, offset: UDim2?)
	local target = UITargetRegistry.Get(key)
	if not target then
		local BFOLDER_ = ensureFolder(Events, "BindableFunctions")
		local bf = BFOLDER_:FindFirstChild("OB_GetUITarget")
		if bf and bf:IsA("BindableFunction") then
			local ok, inst = pcall(function() return (bf :: BindableFunction):Invoke(key) end)
			if ok and inst and inst:IsA("GuiObject") then
				target = inst
			end
		end
	end

	if target and target:IsA("GuiObject") then
		local ok = pcall(NotificationGui.ShowArrowAt, target, offset or UDim2.new(0, 0, -0.12, 0))
		return ok == true
	end

	pcall(NotificationGui.ShowArrowBounce, POS_A, POS_B, SIZE, ROT)
	return false
end

local _lastArrowKey: string? = nil
local function ShowArrowAtKeyTracked(key: string, offset: UDim2?)
	_lastArrowKey = key
	if ShowArrowAtKey(key, offset) then return end
	-- If not ready yet, re-pin on first registration of that key
	local conn
	conn = UITargetRegistry.Changed():Connect(function(chKey, _inst)
		if chKey == _lastArrowKey then
			ShowArrowAtKey(_lastArrowKey, offset)
			if conn then conn:Disconnect() end
		end
	end)
end

-- ========= Generic UI Pulse (key → GuiObject)  ===============================

local UIPulse = {}
local _pulseRecByKey   = {}            -- key -> { stroke, token, running, tween }
local _wantPulse       = {}            -- requested by step (true/false)
local _arrowOwnerKey   = nil           -- which key currently owns the arrow
local _arrowOffsetByKey= {}            -- key -> UDim2

local PULSE_GREEN = Color3.fromRGB(0, 255, 140)

local function _ensureStroke(target: GuiObject): UIStroke
	local stroke = target:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Name = "_OBStroke"
		stroke.Thickness = 2
		stroke.Color = Color3.new(1,1,1)
		stroke.Parent = target
	end
	-- Sticky original color (saved once). Prevents capturing "green" as orig mid-spam.
	if stroke:GetAttribute("_OB_OrigR") == nil then
		local c = stroke.Color
		stroke:SetAttribute("_OB_OrigR", c.R)
		stroke:SetAttribute("_OB_OrigG", c.G)
		stroke:SetAttribute("_OB_OrigB", c.B)
	end
	return stroke
end

local function _origColor(stroke: UIStroke): Color3
	local r = stroke:GetAttribute("_OB_OrigR")
	local g = stroke:GetAttribute("_OB_OrigG")
	local b = stroke:GetAttribute("_OB_OrigB")
	if type(r)=="number" and type(g)=="number" and type(b)=="number" then
		return Color3.new(r,g,b)
	end
	return Color3.new(1,1,1)
end

function UIPulse.start(key: string, opts)
	local target = UITargetRegistry.Get(key)
	if not (target and target:IsA("GuiObject")) then return false end

	local rec = _pulseRecByKey[key]
	if rec and rec.running then return true end

	local stroke    = _ensureStroke(target)
	local token     = (rec and rec.token or 0) + 1
	rec = { stroke = stroke, token = token, running = true, tween = nil }
	_pulseRecByKey[key] = rec

	local cA = (opts and opts.colorA) or PULSE_GREEN
	local cB = (opts and opts.colorB) or _origColor(stroke)
	local tA = (opts and opts.tA) or 0.5
	local tB = (opts and opts.tB) or 0.6

	task.spawn(function()
		while _pulseRecByKey[key] and _pulseRecByKey[key].token == token do
			rec.tween = TweenService:Create(stroke, TweenInfo.new(tA, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Color = cA })
			rec.tween:Play(); rec.tween.Completed:Wait()
			if not (_pulseRecByKey[key] and _pulseRecByKey[key].token == token) then break end
			rec.tween = TweenService:Create(stroke, TweenInfo.new(tB, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { Color = cB })
			rec.tween:Play(); rec.tween.Completed:Wait()
		end
		-- Hard-restore (even if token changed mid-cycle)
		pcall(function() stroke.Color = _origColor(stroke) end)
		rec.tween = nil
	end)
	return true
end

function UIPulse.stop(key: string)
	local rec = _pulseRecByKey[key]
	if not rec then return end
	rec.token += 1
	rec.running = false
	-- Cancel any in-flight tween immediately to avoid mid-phase color
	if rec.tween then pcall(function() rec.tween:Cancel() end) end
	if rec.stroke then
		pcall(function() rec.stroke.Color = _origColor(rec.stroke) end)
	end
	_pulseRecByKey[key] = nil
end

-- ========= Gates (per key) to decide when pulsing/arrow are allowed =========
-- Build button: only when Build Menu is CLOSED.
local KEY_GATES = {
	BuildButton = function()
		local bm = PlayerGui:FindFirstChild("BuildMenu")
		return not (bm and bm.Enabled == true)
	end,
}

local function _gateAllows(key: string): boolean
	-- Any key that targets BuildMenu items only when BuildMenu is open
	if typeof(key) == "string" and string.sub(key, 1, 3) == "BM_" then
		local bm = PlayerGui:FindFirstChild("BuildMenu")
		return bm and bm:IsA("ScreenGui") and bm.Enabled == true
	end
	-- Default per-key gates
	local g = KEY_GATES[key]
	if not g then return true end
	local ok, allowed = pcall(g)
	return ok and allowed == true
end

local function _enforceForKey(key: string)
	-- If no longer wanted or gate disallows, stop visuals
	if not _wantPulse[key] or not _gateAllows(key) then
		UIPulse.stop(key)
		return
	end

	-- Ensure pulse active
	UIPulse.start(key)

	-- Ensure arrow pinned (only one key owns the arrow at a time)
	if _arrowOwnerKey ~= key then
		ShowArrowAtKeyTracked(key, _arrowOffsetByKey[key] or UDim2.new(0,0,-0.12,0))
		_arrowOwnerKey = key
	end
end

-- don't create new pulses when OB is disabled
local function requestPulseAndArrow(key: string, offset: UDim2?)
	if not OB_ENABLED then return end
	_wantPulse[key] = true
	_arrowOffsetByKey[key] = offset or UDim2.new(0,0,-0.12,0)
	_enforceForKey(key)
end

local function clearPulseAndArrow(key: string)
	_wantPulse[key] = nil
	UIPulse.stop(key)
	if _arrowOwnerKey == key then
		HideArrow()
		_arrowOwnerKey = nil
	end
end

-- ========= BuildMenu gate/arrow to current step (no new Events/Instances) ===

local function _currentItemIDFromFlow(): string?
	if not OnboardingFlow or type(OnboardingFlow.GetState) ~= "function" then return nil end
	local st = OnboardingFlow.GetState()
	if not (st and st.current) then return nil end
	-- Prefer mode when present (your steps set mode="DirtRoad" for Road)
	return canonItem(st.current.mode or st.current.item)
end

local function _applyBuildMenuGate(allowedItemID: string?)
	-- Call BuildMenu API directly; no new events
	local ok, mod = pcall(function() return require(PlayerGui.BuildMenu.Logic) end)
	if ok and mod and type(mod.ApplyGateVisual) == "function" then
		mod.ApplyGateVisual(allowedItemID)
	end
end

local function _getCurrentMajorFromBF(): string?
	local bf = BFOLDER:FindFirstChild("OBBuildMenuGetMajorTab")
	if not (bf and bf:IsA("BindableFunction")) then return nil end
	local ok, cur = pcall(function() return (bf :: BindableFunction):Invoke() end)
	if ok and (type(cur) == "string" and cur ~= "") then return cur end
	return nil
end

local function _arrowAndGateToCurrentStep()
	-- Prefer guard router's current step; fall back to legacy Flow if present
	local id = _currentItemIDFromGuard() or _currentItemIDFromFlow()
	if not id then return end

	_applyBuildMenuGate(id)

	local bm = PlayerGui:FindFirstChild("BuildMenu")
	if not (bm and bm:IsA("ScreenGui") and bm.Enabled) then return end

	local wantMajor = majorForItem(id)
	local curMajor  = _getCurrentMajorFromBF()

	if wantMajor and curMajor and wantMajor ~= curMajor then
		local majorKey = MAJOR_TO_KEY[wantMajor] or "BM_Transport"
		requestPulseAndArrow(majorKey, UDim2.new(0, 0, -0.12, 0))
	else
		requestPulseAndArrow("BM_"..id, UDim2.new(0, 0, -0.18, 0))
	end
end

local function _clearArrowAndGate()
	_applyBuildMenuGate(nil)
	if _lastArrowKey then
		clearPulseAndArrow(_lastArrowKey)
		_lastArrowKey = nil
	end
	HideArrow()
end

-- If a UI target re-registers (late load / swap), re-apply pulse/arrow for that key.
UITargetRegistry.Changed():Connect(function(chKey, _inst)
	if _wantPulse[chKey] then
		UIPulse.stop(chKey) -- restart cleanly on the new instance
		_enforceForKey(chKey)
	end
end)

-- BuildMenu open/close → enforce BuildButton gate AND default repin to DirtRoad if no flow step yet
task.defer(function()
	local bm = PlayerGui:FindFirstChild("BuildMenu") or PlayerGui:WaitForChild("BuildMenu")
	if bm and bm:IsA("ScreenGui") then
		local function _apply()
			-- If OB is disabled, just clear UI affordances; leave gate untouched.
			if not OB_ENABLED then
				HideArrow()
				return
			end

			if bm.Enabled then
				-- Build menu opened: gate to current step and point to the right thing.
				local id = _currentItemIDFromGuard() or _currentItemIDFromFlow() or "DirtRoad"
				_applyBuildMenuGate(id)

				local wantMajor = majorForItem(id)
				local curMajor  = _getCurrentMajorFromBF()

				if wantMajor and curMajor and wantMajor ~= wantMajor then
					-- (typo guard; keep normal path)
				end

				if wantMajor and curMajor and wantMajor ~= curMajor then
					local majorKey = MAJOR_TO_KEY[wantMajor] or "BM_Transport"
					requestPulseAndArrow(majorKey, UDim2.new(0, 0, -0.12, 0))
				else
					requestPulseAndArrow("BM_"..id, UDim2.new(0, 0, -0.18, 0))
				end
			else
				-- Build menu closed: DO NOT clear the gate.
				-- We only hide arrow/pulses so BuildMenu won't revive its defaults.
				if _lastArrowKey then clearPulseAndArrow(_lastArrowKey) end
				HideArrow()
				-- (Optionally nudge Build button; skip it to avoid conflicting pulses)
				-- requestPulseAndArrow("BuildButton", UDim2.new(0,0,-0.12,0))
			end
		end

		bm:GetPropertyChangedSignal("Enabled"):Connect(_apply)
		_apply()
	end
end)

-- ========= Global onboarding toggle (listener) =========

-- central handler; RemoteEvent is authoritative; also fan-out to BindableEvent for legacy clients
local function _applyToggle(enabled: boolean?)
	OB_ENABLED = (enabled ~= false)

	if not OB_ENABLED then
		-- Kill GridVisualizer pulses
		if guardPulseItem  then StopPulse(guardPulseItem);  guardPulseItem  = nil end
		if serverPulseItem then StopPulse(serverPulseItem); serverPulseItem = nil end
		-- Kill UI pulses + arrow and clear BuildMenu gate
		for key in pairs(_pulseRecByKey) do UIPulse.stop(key) end
		_wantPulse = {}
		if _arrowOwnerKey then HideArrow(); _arrowOwnerKey = nil end
		_clearArrowAndGate()
	else
		-- Re-issue current step pulse
		repulseCurrentStep()
		-- If BuildMenu is open, repin gate/arrow to the current step; else default to Build button nudge
		local bm = PlayerGui:FindFirstChild("BuildMenu")
		if bm and bm:IsA("ScreenGui") and bm.Enabled then
			_arrowAndGateToCurrentStep()
		else
			requestPulseAndArrow("BuildButton", UDim2.new(0,0,-0.12,0))
		end
		-- Re-enforce requested UI pulses under their gates
		for key,_ in pairs(_wantPulse) do _enforceForKey(key) end
	end

	-- Fan-out locally so other client scripts listening to the bindable still get notified
	pcall(function() (BE_Toggle :: BindableEvent):Fire(OB_ENABLED) end)
end

-- listen to server toggle
RE_Toggle.OnClientEvent:Connect(_applyToggle)

-- (Removed the old BE_Toggle.Event:Connect handler; BindableEvents do not replicate.)

-- ========= Guard Router (reusable; emits only ONE active step) ===============
local function _emitGuard(how, step)
	if not step then return end
	BE_GridGuard:Fire(how, step) -- step carries: item, mode, kind, from, to, requireExactEnd, …
end

local function GuardStart(seq)
	_guardSeq = seq or {}
	_guardIdx = 1
	if _guardSeq[_guardIdx] then
		_emitGuard("start", _guardSeq[_guardIdx])
	end
end

local function GuardAdvance()
	if _guardIdx == 0 then return end
	_guardIdx += 1
	local step = _guardSeq[_guardIdx]
	if step then
		_emitGuard("advance", step)
	else
		BE_GridGuard:Fire("stop")
		_guardSeq = {}
		_guardIdx = 0
	end
end

local function GuardCancel()
	if _guardIdx ~= 0 then
		BE_GridGuard:Fire("stop")
	end
	_guardSeq = {}
	_guardIdx = 0
end
-- ============================================================================

-- ========= Grid guard lifecycle (item pulses) =========

BE_GridGuard.Event:Connect(function(action, spec)
	if not OB_ENABLED then return end
	local newItem = canonItem(spec and (spec.item or spec.mode))

	if action == "start" or action == "advance" then
		-- Hard reset: prevent lingering "Road still pulsing"
		StopPulse(nil)   -- BuildMenu treats nil as "stop all"
		StopPulse("*")
		serverPulseItem = nil
		guardPulseItem  = newItem
		if guardPulseItem then Pulse(guardPulseItem) end

		-- If BuildMenu is open, also enforce gate/arrow to the current step
		local bm = PlayerGui:FindFirstChild("BuildMenu")
		if bm and bm:IsA("ScreenGui") and bm.Enabled then
			_arrowAndGateToCurrentStep()
		end
	elseif action == "stop" then
		if guardPulseItem then
			StopPulse(guardPulseItem)
			guardPulseItem = nil
		end
	end
end)

BE_GuardFB.Event:Connect(function(tag: string, info)
	if not OB_ENABLED then return end
	if tag == "done" then
		-- Index of the step we just finished (before advancing)
		local justDoneIndex = _guardIdx

		-- Persist progress (so we can resume after rejoin)
		pcall(function()
			StepCompleted:FireServer("GuardStepDone", {
				seq   = _activeSeqName or "barrage1",
				index = justDoneIndex,
				total = #_guardSeq,
			})
		end)

		local id = info and canonItem(info.item or info.mode)
		if id then
			StopPulse(id)
			if guardPulseItem == id then guardPulseItem = nil end
		end

		-- If this was the last step, also notify completion
		if justDoneIndex >= #_guardSeq then
			pcall(function() StepCompleted:FireServer("OnboardingFinished") end)
		end

		GuardAdvance()
		return
	elseif tag == "canceled" then
		local id = info and canonItem(info.item or info.mode)
		if id then
			StopPulse(id)
			if guardPulseItem == id then guardPulseItem = nil end
		end
		GuardCancel()
		return
	end
end)

-- ========= Selecting a tool stops matching item pulses =========

DisplayGrid.OnClientEvent:Connect(function(mode)
	if not OB_ENABLED then return end
	local item = canonItem(mode)

	-- Bootstrap “waiting for Road”
	if item == "DirtRoad" then
		pcall(function() StepCompleted:FireServer("RoadToolSelected") end)
	end

	if guardPulseItem and item == guardPulseItem then
		StopPulse(guardPulseItem);  guardPulseItem  = nil
	end
	if serverPulseItem and item == serverPulseItem then
		StopPulse(serverPulseItem); serverPulseItem = nil
	end
	StopPulse(nil); StopPulse("*")
end)

-- ========= Server → Client nudges (UI + item pulses) =========

StateChanged.OnClientEvent:Connect(function(stepName, payload)
	-- Allow city naming even if disabled elsewhere
	if not OB_ENABLED and stepName ~= "CityNaming" then return end
	if stepName == "CityNaming" then return end

	-- === First barrage / first step (Build button) =========
	if stepName == "ShowArrow_BuildMenu" then
		requestPulseAndArrow("BuildButton", UDim2.new(0,0,-0.12,0))
		return
	end
	if stepName == "HideArrow" then
		HideArrow()
		return
	end

	-- (Scalable) generic keyed API you can use for other buttons later
	if stepName == "UIPulse_Start" and payload and typeof(payload) == "table" and type(payload.key) == "string" then
		requestPulseAndArrow(payload.key, payload.offset)
		return
	end
	if stepName == "UIPulse_Stop" and payload and typeof(payload) == "table" and type(payload.key) == "string" then
		clearPulseAndArrow(payload.key)
		return
	end

	-- (NEW) Gate BuildMenu to a specific item sent by server, and repin arrow to it
	if stepName == "BuildMenu_GateOnly" and payload and typeof(payload) == "table" then
		local id = canonItem(payload.itemID or payload.item)
		if id then
			_applyBuildMenuGate(id)

			local bm = PlayerGui:FindFirstChild("BuildMenu")
			if bm and bm:IsA("ScreenGui") and bm.Enabled then
				local wantMajor = majorForItem(id)
				local curMajor  = _getCurrentMajorFromBF()
				if wantMajor and curMajor and wantMajor ~= curMajor then
					local majorKey = MAJOR_TO_KEY[wantMajor] or "BM_Transport"
					requestPulseAndArrow(majorKey, payload.offset or UDim2.new(0, 0, -0.12, 0))
				else
					requestPulseAndArrow("BM_"..id, payload.offset or UDim2.new(0, 0, -0.18, 0))
				end
			end
		end
		return
	end

	-- Gate BuildMenu to whatever the CURRENT FLOW STEP requires (no hard-coded items)
	if stepName == "BuildMenu_GateOnly_Current" then
		_arrowAndGateToCurrentStep()
		return
	end

	-- Clear BuildMenu gate and stop arrow/pulse
	if stepName == "BuildMenu_GateClear" then
		_clearArrowAndGate()
		return
	end

	-- Hints
	if stepName == "ShowHint_SelectRoad"      then ShowHint("Select the Road tool."); return end
	if stepName == "ShowHint_SelectRoad_Done" then ShowHint("Nice. Now build a straight road from the spawn road."); return end

	-- Item pulse nudges
	if stepName == "Pulse_Item" and payload and typeof(payload) == "table" and payload.item then
		local item = canonItem(payload.item)
		if serverPulseItem and serverPulseItem ~= item then
			StopPulse(serverPulseItem)
		end
		serverPulseItem = item
		if serverPulseItem then Pulse(serverPulseItem) end
		return
	end

	if stepName == "Stop_Pulse_Item" and payload and typeof(payload) == "table" and payload.item then
		local target = canonItem(payload.item)
		StopPulse(target)
		if serverPulseItem == target then serverPulseItem = nil end
		return
	end
end)

-- ========= First barrage orchestration trigger (single‑step guard emit) ======

local function _barrage1()
	return {
		{ item="Road",        mode="DirtRoad",    kind="line",  from={x=0,  z=0},  to={x=0, z=21}, requireExactEnd=true },
		{ item="Residential", mode="Residential", kind="rect",  from={x=1,  z=1},  to={x=4, z=10} },
		{ item="WaterTower",  mode="WaterTower",  kind="point", from={x=-1, z=1} },
		{ item="WaterPipe",   mode="WaterPipe",   kind="line",  from={x=0,  z=1},  to={x=5, z=1} },
		{ item="WaterPipe",   mode="WaterPipe",   kind="line",  from={x=3,  z=1},  to={x=3, z=11} },
		{ item="WindTurbine", mode="WindTurbine", kind="point", from={x=-1, z=9} },
		{ item="PowerLines",  mode="PowerLines",  kind="line",  from={x=0,  z=9},  to={x=3, z=9} },
		{ item="PowerLines",  mode="PowerLines",  kind="line",  from={x=3,  z=8},  to={x=3, z=1} },
		{ item="DirtRoad",    mode="DirtRoad",    kind="line",  from={x=0,  z=11}, to={x=4, z=11}, requireExactEnd=false },
		{ item="Commercial",  mode="Commercial",  kind="rect",  from={x=1,  z=12}, to={x=4, z=21} },
	}
end

StateChanged.OnClientEvent:Connect(function(stepName)
	-- do nothing if disabled
	if not OB_ENABLED then return end

	if stepName == "Onboarding_StartBarrage1" then
		if guardPulseItem  then StopPulse(guardPulseItem);  guardPulseItem  = nil end
		if serverPulseItem then StopPulse(serverPulseItem); serverPulseItem = nil end

		_activeSeqName = "barrage1"

		local seq = _barrage1()
		local startAt = 1
		
		GuardStart(seq)

		-- Skip ahead if resuming
		for _ = 2, startAt do
			GuardAdvance()
		end

		-- Pulse the current step
		local cur = _guardSeq[_guardIdx]
		if cur then
			Pulse(canonItem(cur.mode or cur.item))
		end
		return
	end
end)

-- ========= React to BuildMenu major-tab changes (from BuildMenu) =============
if BE_TabChanged and BE_TabChanged:IsA("BindableEvent") then
	(BE_TabChanged :: BindableEvent).Event:Connect(function(kind, newMajor)
		if kind ~= "major" then return end
		if not OB_ENABLED then return end

		local bm = PlayerGui:FindFirstChild("BuildMenu")
		if not (bm and bm:IsA("ScreenGui") and bm.Enabled) then return end

		-- Prefer the current guarded step; fall back to flow, then DirtRoad
		local id        = _currentItemIDFromGuard() or _currentItemIDFromFlow() or "DirtRoad"
		local wantMajor = majorForItem(id)

		-- Keep the gate fresh on any tab change
		_applyBuildMenuGate(id)

		-- If user navigated away from the required major, guide them back
		if wantMajor and newMajor ~= wantMajor then
			local key = MAJOR_TO_KEY[wantMajor] or "BM_Transport"
			requestPulseAndArrow(key, UDim2.new(0, 0, -0.12, 0))
		else
			-- Right major is active → point at the specific item button
			requestPulseAndArrow("BM_"..id, UDim2.new(0, 0, -0.18, 0))
		end
	end)
end

-- ========= Self-nudge (only if server hasn't nudged yet) =====================
task.delay(0.40, function()
	if OB_ENABLED and KEY_GATES.BuildButton() then
		requestPulseAndArrow("BuildButton", UDim2.new(0,0,-0.12,0))
	end
end)

--Local Script