-- ServerScriptService/Players/OnboardingServerBridge.server.lua

-- Services
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local Players              = game:GetService("Players")
local ServerScriptService  = game:GetService("ServerScriptService")
local RunService           = game:GetService("RunService")

-- Modules
local ZoneReq     = require(ServerScriptService.Build.Zones.ZoneManager.ZoneRequirementsCheck)
local ZoneTracker = require(ServerScriptService.Build.Zones.ZoneManager.ZoneTracker)

-- Events / Remotes
local RE = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents")
local RF = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteFunctions")
local BE = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents")

local StepCompleted   = RE:WaitForChild("OnboardingStepCompleted")   -- client -> server
local StateChanged    = RE:WaitForChild("OnboardingStateChanged")     -- server -> client
local ToggleRE        = RE:WaitForChild("OnboardingToggle")           -- server -> client
local OnboardingAdmin = RF:FindFirstChild("OnboardingAdmin")
local BE_StatsChanged = BE:FindFirstChild("StatsChanged")

-- >>> ADD: listen for SaveManager-driven world reloads (SaveEndpoints fires this)
local ReloadFromCurrentBE = BE:FindFirstChild("RequestReloadFromCurrent")

local WHITELIST = {
	[40044289170] = true, -- optionally put userIds here for live test, e.g. [12345678] = true
}

-- Service (server-side, account-wide state + badges)
local OnboardingService = require(ServerScriptService.Players.OnboardingService)

-- --------------------------------------------------------------------------------------
-- Per-player enable + transient
-- --------------------------------------------------------------------------------------
local ONBOARDING_ENABLED  : {[number]: boolean} = {}
local roadPending         : {[number]: boolean} = {}
local lastPulsed          : {[number]: string}  = {}
local barrageStarted      : {[number]: boolean} = {}

-- Barrage 2 state
local barrage2Started     : {[number]: boolean} = {}
local barrage2Conn        : {[number]: RBXScriptConnection?} = {}
local barrage1Completed   : {[number]: boolean} = {}

-- B2 hint cadence state
local b2Phase             : {[number]: string} = {}
local b2LastPrintAt       : {[number]: number} = {}
local b2LastHintAt        : {[number]: number} = {}
local b2GlobalHintAt      : {[number]: number} = {}
local b2LastHintKey       : {[number]: string} = {}
local b2LastHintTag       : {[number]: string} = {}
local b2LastGateKey       : {[number]: string} = {}
local b2LastExampleWater  : {[number]: string} = {}
local b2LastExamplePower  : {[number]: string} = {}
local b2LastState         : {[number]: string} = {}
local b2EvalQueued        : {[number]: boolean} = {}

-- Tunables (B2)
local B2_PRINT_HEARTBEAT       = 5.0
local B2_GLOBAL_HINT_COOLDOWN  = 5.0
local B2_HINT_COOLDOWN         = 6.0

-- --------------------------------------------------------------------------------------
-- Barrage 3 (Industrial zone then connect it)
-- --------------------------------------------------------------------------------------
-- State
local barrage3Started   : {[number]: "placing"|"connect"|nil} = {}
local barrage3Conn      : {[number]: RBXScriptConnection?} = {}
local b3ZoneId          : {[number]: string?} = {}
local b3KnownZones      : {[number]: {[string]: boolean}} = {}
local b3EvalQueued      : {[number]: boolean} = {}
local b3LastPrintAt     : {[number]: number} = {}
local b3LastHintAt      : {[number]: number} = {}
local b3LastHintKey     : {[number]: string} = {}

-- Tunables (B3)
local B3_PRINT_HEARTBEAT = 5.0
local B3_HINT_COOLDOWN   = 6.0
local BARRAGE3_STEP_COUNT = 8

-- --------------------------------------------------------------------------------------
-- Barrage 1 idempotency / debounce + tunables
-- --------------------------------------------------------------------------------------
local b1LastKickIdx     : {[number]: number} = {}
local b1KickCooldownAt  : {[number]: number} = {}
local B1_KICK_DEBOUNCE  = 1.0  -- seconds; prevents rapid re-kicks while UI registers targets

-- New tunables to control automatic starts
local B1_AUTOSTART_ON_JOIN       = false  -- keep false to avoid auto-routing without a click
local B1_AUTOSTART_ON_FIRST_OPEN = false  -- reserved for client parity; not used here by default

-- --------------------------------------------------------------------------------------
-- Helpers
-- --------------------------------------------------------------------------------------
local function onboardingActive(p: Player): boolean
	return ONBOARDING_ENABLED[p.UserId] == true
end

local function _clearB2Caches(uid: number)
	b2Phase[uid] = nil
	b2LastPrintAt[uid], b2GlobalHintAt[uid], b2LastHintAt[uid] = nil, nil, nil
	b2LastHintKey[uid], b2LastHintTag[uid], b2LastGateKey[uid] = nil, nil, nil
	b2LastExampleWater[uid], b2LastExamplePower[uid] = nil, nil
	b2LastState[uid] = nil
	b2EvalQueued[uid] = nil
end

local function setOnboardingEnabled(player: Player, enabled: boolean)
	local want = (enabled ~= false)
	ONBOARDING_ENABLED[player.UserId] = want
	ToggleRE:FireClient(player, want)
	if not want then
		StateChanged:FireClient(player, "BuildMenu_GateClear")
		StateChanged:FireClient(player, "UIPulse_Stop", { key = "BM_DirtRoad" })
		StateChanged:FireClient(player, "HideArrow")
		roadPending[player.UserId]    = nil
		lastPulsed[player.UserId]     = nil
		barrageStarted[player.UserId] = nil
		local uid = player.UserId
		if barrage2Conn[uid] then barrage2Conn[uid]:Disconnect(); barrage2Conn[uid] = nil end
		barrage2Started[uid] = nil
		barrage1Completed[uid] = nil
		_clearB2Caches(uid)

		-- B3 cleanup
		if barrage3Conn[uid] then barrage3Conn[uid]:Disconnect(); barrage3Conn[uid] = nil end
		barrage3Started[uid] = nil
		b3ZoneId[uid], b3KnownZones[uid] = nil, nil
		b3EvalQueued[uid], b3LastPrintAt[uid], b3LastHintAt[uid], b3LastHintKey[uid] = nil, nil, nil, nil

		-- B1 debounce cleanup
		b1LastKickIdx[uid], b1KickCooldownAt[uid] = nil, nil
	end
end

local function showBuildArrow(p: Player) StateChanged:FireClient(p, "ShowArrow_BuildMenu") end
local function hideArrow(p: Player)      StateChanged:FireClient(p, "HideArrow")          end

local function pulseItem(p: Player, name: string)
	if lastPulsed[p.UserId] == name then return end
	StateChanged:FireClient(p, "Pulse_Item", { item = name })
	lastPulsed[p.UserId] = name
end
local function stopPulseItem(p: Player, name: string)
	StateChanged:FireClient(p, "Stop_Pulse_Item", { item = name })
	if lastPulsed[p.UserId] == name then lastPulsed[p.UserId] = nil end
end

-- Stamp kick idx + cooldown
local function startBarrage1(p: Player, resumeAt: number?)
	local uid = p.UserId
	barrageStarted[uid] = true
	if type(resumeAt) == "number" then
		b1LastKickIdx[uid] = resumeAt
	else
		b1LastKickIdx[uid] = 1
	end
	b1KickCooldownAt[uid] = os.clock()

	if type(resumeAt) == "number" then
		StateChanged:FireClient(p, "Onboarding_StartBarrage1", { resumeAt = resumeAt })
	else
		StateChanged:FireClient(p, "Onboarding_StartBarrage1")
	end
end

-- Race-safe re-emitter: prevent restarts while already running / recently kicked
local function ensureBarrage1Running(p: Player)
	local uid = p.UserId
	local idx, total
	pcall(function()
		if OnboardingService.GetGuardProgress then
			idx, total = OnboardingService.GetGuardProgress(p, "barrage1")
		end
	end)

	-- With snapshot: compute the step we need to resume at
	if type(idx) == "number" and idx >= 0 then
		local desired = idx + 1

		-- Already kicked this (or a later) step? Just refresh the current gate.
		if barrageStarted[uid] and (b1LastKickIdx[uid] or 0) >= desired then
			StateChanged:FireClient(p, "BuildMenu_GateOnly_Current")
			return
		end
		-- Debounce rapid re-kicks
		if (os.clock() - (b1KickCooldownAt[uid] or 0)) < B1_KICK_DEBOUNCE then
			StateChanged:FireClient(p, "BuildMenu_GateOnly_Current")
			return
		end

		if not total or idx < total then
			startBarrage1(p, desired)
		else
			-- Completed snapshot; don't restart, just show the current gate.
			StateChanged:FireClient(p, "BuildMenu_GateOnly_Current")
		end
		return
	end

	-- No snapshot: if already running, only show current gate.
	if barrageStarted[uid] then
		StateChanged:FireClient(p, "BuildMenu_GateOnly_Current")
		return
	end

	-- Fresh start
	startBarrage1(p)
end

-- ===== Barrage 2 helpers =====
local function _uid(p: Player?) return p and p.UserId end
local function _count(t) local n=0; for _ in pairs(t or {}) do n+=1 end; return n end

local function powerBudgetOK(p: Player)
	local produced = (ZoneReq.getEffectiveProduction(p) or {}).power or 0
	local required = (ZoneReq.getEffectiveTotals(p)     or {}).power or 0
	return produced >= required, produced, required
end
local function allBuildingsPowered(p: Player)
	local zones = ZoneTracker.getAllZones(p)
	local anyBuilding, missing = false, {}
	for zid, z in pairs(zones) do
		if ZoneReq.isBuildingZone(z.mode) then
			anyBuilding = true
			local ok = z.requirements and z.requirements.Power == true
			if not ok then missing[zid] = z.mode end
		end
	end
	local allOK = anyBuilding and next(missing) == nil
	return allOK, missing
end

local function waterBudgetOK(p: Player)
	local produced = (ZoneReq.getEffectiveProduction(p) or {}).water or 0
	local required = (ZoneReq.getEffectiveTotals(p)     or {}).water or 0
	return produced >= required, produced, required
end
local function allBuildingsWatered(p: Player)
	local zones = ZoneTracker.getAllZones(p)
	local anyBuilding, missing = false, {}
	for zid, z in pairs(zones) do
		if ZoneReq.isBuildingZone(z.mode) then
			anyBuilding = true
			local ok = z.requirements and z.requirements.Water == true
			if not ok then missing[zid] = z.mode end
		end
	end
	local allOK = anyBuilding and next(missing) == nil
	return allOK, missing
end

local function _pickStableExample(uid: number, missing: {[string]: any}, kind: "water"|"power")
	local last = (kind == "water") and b2LastExampleWater[uid] or b2LastExamplePower[uid]
	if last and missing[last] then return last end
	local best, bestNum
	for zid,_ in pairs(missing or {}) do
		local num = tonumber(string.match(zid, ".*_(%d+)$") or "")
		if num then
			if not bestNum or num < bestNum then bestNum, best = num, zid end
		elseif not best then
			best = zid
		end
	end
	if kind == "water" then b2LastExampleWater[uid] = best else b2LastExamplePower[uid] = best end
	return best
end

local function _gateOnce(p: Player, itemID: string?)
	if not itemID or itemID == "" then return end
	local uid = p.UserId
	if b2LastGateKey[uid] ~= itemID then
		StateChanged:FireClient(p, "BuildMenu_GateOnly", { itemID = itemID })
		b2LastGateKey[uid] = itemID
	end
end

local function _makeHintKey(tag, payload)
	if string.find(tag, "Connect", 1, true) then
		return ("%s|%s"):format(tag, tostring(payload and payload.zoneId or ""))
	elseif string.find(tag, "Deficit", 1, true) then
		local req = payload and payload.required or ""
		local pro = payload and payload.produced or ""
		return ("%s|%s/%s"):format(tag, tostring(req), tostring(pro))
	end
	return tag
end

local function maybePushB2Hint(p: Player, tag: string, payload: table?)
	local uid = p.UserId
	local now = os.clock()
	local key = _makeHintKey(tag, payload)
	if (now - (b2GlobalHintAt[uid] or 0)) < B2_GLOBAL_HINT_COOLDOWN then return end
	if b2LastHintKey[uid] == key and (now - (b2LastHintAt[uid] or 0)) < B2_HINT_COOLDOWN then return end
	if tag == "Onboarding_ShowHint_WaterDeficit" then
		print(("[OB_B2] HINT → WATER DEFICIT (%d/%d)"):format(payload.produced or 0, payload.required or 0))
	elseif tag == "Onboarding_ShowHint_PowerDeficit" then
		print(("[OB_B2] HINT → POWER DEFICIT (%d/%d)"):format(payload.produced or 0, payload.required or 0))
	elseif tag == "Onboarding_ShowHint_ConnectBuildingsToWater" then
		print(("[OB_B2] HINT → CONNECT WATER (example zone=%s)"):format(tostring(payload.zoneId)))
	elseif tag == "Onboarding_ShowHint_ConnectBuildingsToPower" then
		print(("[OB_B2] HINT → CONNECT POWER (example zone=%s)"):format(tostring(payload.zoneId)))
	end
	StateChanged:FireClient(p, tag, payload)
	b2GlobalHintAt[uid] = now
	b2LastHintTag[uid]  = tag
	b2LastHintKey[uid]  = key
	b2LastHintAt[uid]   = now
end

-- --------------------------------------------------------------------------------------
-- Barrage 3 helpers
-- --------------------------------------------------------------------------------------
local function _snapshotZones(p: Player): {[string]: boolean}
	local zones = ZoneTracker.getAllZones(p) or {}
	local set = {}
	for zid,_ in pairs(zones) do set[tostring(zid)] = true end
	return set
end

local function _findNewIndustrialZone(p: Player, baseline: {[string]: boolean}, rectFrom: {x:number,z:number}?, rectTo: {x:number,z:number}?)
	local zones = ZoneTracker.getAllZones(p) or {}
	local bestId, bestScore
	local minx, maxx, minz, maxz = nil, nil, nil, nil
	if rectFrom and rectTo then
		minx = math.min(rectFrom.x, rectTo.x); maxx = math.max(rectFrom.x, rectTo.x)
		minz = math.min(rectFrom.z, rectTo.z); maxz = math.max(rectFrom.z, rectTo.z)
	end
	for zid, z in pairs(zones) do
		if not (baseline and baseline[tostring(zid)]) then
			if tostring(z.mode) == "Industrial" then
				local score = 1
				-- Prefer exact bounds match if available
				if z.bounds and z.bounds.min and z.bounds.max and minx then
					local zb = z.bounds
					local match = (zb.min.x == minx and zb.min.z == minz and zb.max.x == maxx and zb.max.z == maxz)
					if match then score += 10000 end
				end
				-- Prefer larger cell count if no bounds interface
				if z.cells and type(z.cells) == "table" then
					local n = 0; for _ in pairs(z.cells) do n += 1 end
					score += n
				end
				if not bestScore or score > bestScore then bestScore, bestId = score, tostring(zid) end
			end
		end
	end
	return bestId
end

local function _maybePushB3Hint(p: Player, key: string, payload: table?)
	local uid = p.UserId
	local now = os.clock()
	if (now - (b3LastHintAt[uid] or 0)) < B3_HINT_COOLDOWN then return end
	if b3LastHintKey[uid] == key then return end
	StateChanged:FireClient(p, key, payload)
	b3LastHintAt[uid]  = now
	b3LastHintKey[uid] = key
end

local function _zoneReqFlags(z): (boolean, boolean, boolean)
	local req = (z and z.requirements) or {}
	return req.Road == true, req.Water == true, req.Power == true
end

local function _roadAdjacencyHeuristic(p: Player, z): ("none"|"adjacent_isolated"|"connected")
	local ok1, adj   = pcall(function() return ZoneReq and ZoneReq.hasAdjacentRoad and ZoneReq.hasAdjacentRoad(p, z) end)
	local ok2, netok = pcall(function() return ZoneReq and ZoneReq.isRoadConnectedToNetwork and ZoneReq.isRoadConnectedToNetwork(p, z) end)
	if ok2 and netok == true then return "connected" end
	if ok1 and adj == true then return "adjacent_isolated" end
	return "none"
end

local function startBarrage3(p: Player, resumeAt: number?)
	local uid = p.UserId
	if barrage3Started[uid] then return end
	print("[OB_B3] ▶ begin for", p.Name)
	barrage3Started[uid] = "placing"
	b3ZoneId[uid]     = nil
	b3KnownZones[uid] = _snapshotZones(p)
	b3LastPrintAt[uid], b3LastHintAt[uid], b3LastHintKey[uid] = 0, 0, nil
	pcall(function()
		if OnboardingService and OnboardingService.SetB3Stage then
			OnboardingService.SetB3Stage(p, "placing")
		end
	end)

	StateChanged:FireClient(p, "Onboarding_B3_Begin")
	-- Single rect guard to place Industrial at required coords
	StateChanged:FireClient(p, "Onboarding_StartBarrage3", {
		from = { x = -5, z =  6 },
		to   = { x = -8, z = 15 },
		resumeAt = resumeAt,
	})
end

-- --------------------------------------------------------------------------------------
-- Barrage 2 main
-- --------------------------------------------------------------------------------------
local BARRAGE2_STEP_COUNT = 3

local function checkBarrage2(p: Player): boolean
	local uid, now = p.UserId, os.clock()
	local phase = b2Phase[uid] or "water"
	local pOK, pProd, pReq = powerBudgetOK(p)
	local wOK, wProd, wReq = waterBudgetOK(p)
	local pAll, missP      = allBuildingsPowered(p)
	local wAll, missW      = allBuildingsWatered(p)
	local allOK = (pOK and pAll and wOK and wAll)
	if not allOK and (now - (b2LastPrintAt[uid] or 0)) >= B2_PRINT_HEARTBEAT then
		print(("[OB_B2] phase=%s | PWR %d/%d (budget=%s cover=%s miss=%d) | WTR %d/%d (budget=%s cover=%s miss=%d)")
			:format(phase, pProd, pReq, tostring(pOK), tostring(pAll), _count(missP), wProd, wReq, tostring(wOK), tostring(wAll), _count(missW)))
		b2LastPrintAt[uid] = now
	end
	if allOK then
		print("[OB_B2] ✅ Utilities satisfied: ALL buildings have Water & Power.")
		pcall(function()
			if OnboardingService and OnboardingService.MarkStep then
				OnboardingService.MarkStep(p, "Barrage2_Utilities_OK")
			end
			if OnboardingService and OnboardingService.SetB2Phase then
				OnboardingService.SetB2Phase(p, "")
			end
		end)
		StateChanged:FireClient(p, "Onboarding_B2_Complete")
		if barrage2Conn[uid] then barrage2Conn[uid]:Disconnect(); barrage2Conn[uid] = nil end
		barrage2Started[uid] = nil
		_clearB2Caches(uid)

		-- ▶ Begin Barrage 3 after B2 completes
		task.defer(function()
			if onboardingActive(p) then
				startBarrage3(p)
			end
		end)
		return true
	end
	if phase == "water" then
		if wOK and wAll then
			b2Phase[uid] = "power"
			StateChanged:FireClient(p, "Onboarding_B2_WaterPhaseDone")
			StateChanged:FireClient(p, "Onboarding_B2_PowerPhaseBegin")
			pcall(function()
				if OnboardingService and OnboardingService.SetB2Phase then
					OnboardingService.SetB2Phase(p, "power")
				end
			end)
			b2GlobalHintAt[uid], b2LastHintKey[uid], b2LastHintAt[uid], b2LastHintTag[uid] = 0, nil, 0, nil
			b2LastGateKey[uid] = nil
			phase = "power"
		else
			if not wOK then
				maybePushB2Hint(p, "Onboarding_ShowHint_WaterDeficit", { produced = wProd, required = wReq, deficit = math.max(0, wReq - wProd) })
				_gateOnce(p, "WaterTower")
			else
				local example = _pickStableExample(uid, missW, "water")
				maybePushB2Hint(p, "Onboarding_ShowHint_ConnectBuildingsToWater", { zoneId = example })
				_gateOnce(p, "WaterPipe")
			end
			return false
		end
	end
	if phase == "power" then
		if not pOK then
			maybePushB2Hint(p, "Onboarding_ShowHint_PowerDeficit", { produced = pProd, required = pReq, deficit = math.max(0, pReq - pProd) })
			_gateOnce(p, "WindTurbine")
		elseif not pAll then
			local example = _pickStableExample(uid, missP, "power")
			maybePushB2Hint(p, "Onboarding_ShowHint_ConnectBuildingsToPower", { zoneId = example })
			_gateOnce(p, "PowerLines")
		end
	end
	return false
end

local function startBarrage2(p: Player, resumeAt: number?, persistedPhase: string?)
	local uid = _uid(p); if not uid then return end
	if barrage2Started[uid] then return end
	barrage2Started[uid] = true
	local stepCount = BARRAGE2_STEP_COUNT
	local resumeIdx = tonumber(resumeAt)
	if resumeIdx then
		resumeIdx = math.clamp(math.floor(resumeIdx), 1, stepCount)
	else
		resumeIdx = nil
	end
	local phase = (persistedPhase == "power") and "power" or "water"
	b2Phase[uid] = phase
	print(("[OB_B2] ▶ begin for %s (resumeAt=%s phase=%s)"):format(p.Name, tostring(resumeIdx), phase))

	local payload = nil
	if resumeIdx and resumeIdx > 1 then
		payload = { resumeAt = resumeIdx }
	end
	StateChanged:FireClient(p, "Onboarding_B2_Begin", payload)
	StateChanged:FireClient(p, "Onboarding_B2_WaterPhaseBegin")
	if phase == "power" then
		StateChanged:FireClient(p, "Onboarding_B2_WaterPhaseDone")
		StateChanged:FireClient(p, "Onboarding_B2_PowerPhaseBegin")
	end
	if not persistedPhase then
		pcall(function()
			if OnboardingService and OnboardingService.SetB2Phase then
				OnboardingService.SetB2Phase(p, "water")
			end
		end)
	end
	local statsBE = BE:FindFirstChild("StatsChanged") :: BindableEvent
	if not statsBE then
		statsBE = Instance.new("BindableEvent")
		statsBE.Name = "StatsChanged"
		statsBE.Parent = BE
	end
	b2LastPrintAt[uid], b2GlobalHintAt[uid], b2LastHintAt[uid] = 0, 0, 0
	b2LastHintKey[uid], b2LastHintTag[uid], b2LastGateKey[uid] = nil, nil, nil
	b2LastExampleWater[uid], b2LastExamplePower[uid] = nil, nil
	b2LastState[uid] = nil
	b2EvalQueued[uid] = nil
	if barrage2Conn[uid] then barrage2Conn[uid]:Disconnect(); barrage2Conn[uid] = nil end
	barrage2Conn[uid] = statsBE.Event:Connect(function(pp: Player)
		if pp ~= p then return end
		if b2EvalQueued[uid] then return end
		b2EvalQueued[uid] = true
		task.defer(function()
			if barrage2Started[uid] then checkBarrage2(p) end
			b2EvalQueued[uid] = nil
		end)
	end)
	checkBarrage2(p)
end

-- --------------------------------------------------------------------------------------
-- Barrage 3 main
-- --------------------------------------------------------------------------------------
local function checkBarrage3(p: Player, rectFrom, rectTo): boolean
	local uid, now = p.UserId, os.clock()
	local zones = ZoneTracker.getAllZones(p) or {}

	local zid = b3ZoneId[uid]
	if not zid or not zones[zid] then
		zid = _findNewIndustrialZone(p, b3KnownZones[uid] or {}, rectFrom, rectTo)
		if zid then b3ZoneId[uid] = zid end
	end
	local z = (zid and zones[zid]) or nil
	if not z then
		if (now - (b3LastPrintAt[uid] or 0)) >= B3_PRINT_HEARTBEAT then
			print("[OB_B3] Waiting for Industrial zone to appear…")
			b3LastPrintAt[uid] = now
		end
		return false
	end

	local roadOK, waterOK, powerOK = _zoneReqFlags(z)
	local wBudgetOK, wProd, wReq   = waterBudgetOK(p)
	local pBudgetOK, pProd, pReq   = powerBudgetOK(p)

	if (now - (b3LastPrintAt[uid] or 0)) >= B3_PRINT_HEARTBEAT then
		print(("[OB_B3] zone=%s | Road=%s Water=%s Power=%s | Budgets W %d/%d P %d/%d")
			:format(tostring(zid), tostring(roadOK), tostring(waterOK), tostring(powerOK), wProd, wReq, pProd, pReq))
		b3LastPrintAt[uid] = now
	end

	-- Complete when zone is satisfied and budgets are OK
	if roadOK and waterOK and powerOK and wBudgetOK and pBudgetOK then
		print("[OB_B3] ✅ Industrial zone fully connected.")
		pcall(function()
			if OnboardingService and OnboardingService.MarkStep then
				OnboardingService.MarkStep(p, "Barrage3_Industrial_Connected")
			end
			if OnboardingService and OnboardingService.SetB3Stage then
				OnboardingService.SetB3Stage(p, "")
			end
			if OnboardingService and OnboardingService.Complete then
				OnboardingService.Complete(p)
			end
		end)
		setOnboardingEnabled(p, false)
		StateChanged:FireClient(p, "Onboarding_B3_Complete", { zoneId = zid })
		if barrage3Conn[uid] then barrage3Conn[uid]:Disconnect(); barrage3Conn[uid] = nil end
		barrage3Started[uid] = nil
		b3ZoneId[uid], b3KnownZones[uid] = nil, nil
		return true
	end

	-- Coaching path
	if not roadOK then
		local roadState = _roadAdjacencyHeuristic(p, z)
		if roadState == "adjacent_isolated" then
			_maybePushB3Hint(p, "Onboarding_B3_Hint_RoadConnectNetwork", { zoneId = zid })
			_gateOnce(p, "DirtRoad")
		else
			_maybePushB3Hint(p, "Onboarding_B3_Hint_RoadPlace", { zoneId = zid })
			_gateOnce(p, "DirtRoad")
		end
		return false
	end

	if not waterOK then
		if not wBudgetOK then
			maybePushB2Hint(p, "Onboarding_ShowHint_WaterDeficit", { produced = wProd, required = wReq, deficit = math.max(0, wReq - wProd) })
			_gateOnce(p, "WaterTower")
		else
			_maybePushB3Hint(p, "Onboarding_B3_Hint_ConnectWater", { zoneId = zid })
			_gateOnce(p, "WaterPipe")
		end
		return false
	end

	if not powerOK then
		if not pBudgetOK then
			maybePushB2Hint(p, "Onboarding_ShowHint_PowerDeficit", { produced = pProd, required = pReq, deficit = math.max(0, pReq - pProd) })
			_gateOnce(p, "WindTurbine")
		else
			_maybePushB3Hint(p, "Onboarding_B3_Hint_ConnectPower", { zoneId = zid })
			_gateOnce(p, "PowerLines")
		end
		return false
	end

	return false
end

local function _beginBarrage3Connectivity(p: Player, rectFrom, rectTo)
	local uid = p.UserId
	barrage3Started[uid] = "connect"
	b3ZoneId[uid] = _findNewIndustrialZone(p, b3KnownZones[uid] or {}, rectFrom, rectTo)
	pcall(function()
		if OnboardingService and OnboardingService.SetB3Stage then
			OnboardingService.SetB3Stage(p, "connect", { zoneId = b3ZoneId[uid] })
		end
	end)

	-- Ensure StatsChanged fanout
	local statsBE = BE:FindFirstChild("StatsChanged") :: BindableEvent
	if not statsBE then
		statsBE = Instance.new("BindableEvent"); statsBE.Name = "StatsChanged"; statsBE.Parent = BE
	end

	if barrage3Conn[uid] then barrage3Conn[uid]:Disconnect(); barrage3Conn[uid] = nil end
	b3EvalQueued[uid] = nil
	barrage3Conn[uid] = statsBE.Event:Connect(function(pp: Player)
		if pp ~= p then return end
		if b3EvalQueued[uid] then return end
		b3EvalQueued[uid] = true
		task.defer(function()
			if barrage3Started[uid] then
				checkBarrage3(p, rectFrom, rectTo)
			end
			b3EvalQueued[uid] = nil
		end)
	end)

	-- Kick once
	checkBarrage3(p, rectFrom, rectTo)
end

-- --------------------------------------------------------------------------------------
-- Reseed onboarding after SaveManager reload (slot switch/delete)
-- --------------------------------------------------------------------------------------
-- Reseed onboarding after SaveManager reload (slot switch/delete)
local function _reseedOnboardingFor(plr: Player)
	if not plr or not plr.Parent then return end

	-- Ensure account-wide onboarding state exists
	pcall(function()
		OnboardingService.StartIfNeeded(plr)
	end)

	-- Decide enabled vs completed/skipped
	local completed, skipped = false, false
	pcall(function()
		completed = OnboardingService.IsCompleted and OnboardingService.IsCompleted(plr) or false
		skipped   = OnboardingService.IsSkipped   and OnboardingService.IsSkipped(plr)   or false
	end)

	-- Disable onboarding entirely if either Completed or Skipped
	setOnboardingEnabled(plr, not (completed or skipped))

	if not onboardingActive(plr) then
		-- Completed or Skipped + ensure client UI is clean
		StateChanged:FireClient(plr, 'BuildMenu_GateClear')
		StateChanged:FireClient(plr, 'UIPulse_Stop', { key = 'BM_DirtRoad' })
		StateChanged:FireClient(plr, 'HideArrow')
		return
	end

	-- If enabled, resume where appropriate
	local resumeAt: number? = nil
	pcall(function()
		if OnboardingService.GetGuardProgress then
			local idx, total = OnboardingService.GetGuardProgress(plr, 'barrage1')
			if type(idx) == 'number' and idx >= 1 then
				if type(total) == 'number' and idx >= total then
					barrage1Completed[plr.UserId] = true
				else
					resumeAt = idx + 1
				end
			end
		end
	end)

	local b2ResumeAt: number? = nil
	pcall(function()
		if OnboardingService.GetGuardProgress then
			local idx, total = OnboardingService.GetGuardProgress(plr, 'barrage2')
			if type(idx) == 'number' and idx >= 1 then
				local steps = BARRAGE2_STEP_COUNT
				if type(total) == 'number' and total > 0 then
					steps = total
				end
				b2ResumeAt = math.clamp(math.floor(idx) + 1, 1, steps)
			end
		end
	end)

	local savedB2Phase: string? = nil
	pcall(function()
		if OnboardingService.GetB2Phase then
			local phase = OnboardingService.GetB2Phase(plr)
			if phase == 'water' or phase == 'power' then
				savedB2Phase = phase
			end
		end
	end)

	local b3ResumeAt: number? = nil
	local b3Stage: string? = nil
	local b3SeqSteps = BARRAGE3_STEP_COUNT
	local b3SeqCompleted = false
	pcall(function()
		if OnboardingService.GetGuardProgress then
			local idx, total = OnboardingService.GetGuardProgress(plr, 'barrage3')
			if type(total) == 'number' and total > 0 then
				b3SeqSteps = total
			end
			if type(idx) == 'number' and idx >= 1 then
				b3SeqCompleted = (idx >= b3SeqSteps)
				b3ResumeAt = math.clamp(math.floor(idx) + 1, 1, b3SeqSteps)
			end
		end
	end)
	pcall(function()
		if OnboardingService.GetB3Stage then
			local stage, payload = OnboardingService.GetB3Stage(plr)
			if type(stage) == 'string' then
				b3Stage = stage
			elseif type(stage) == 'table' and type(stage.stage) == 'string' then
				b3Stage = stage.stage
			elseif type(payload) == 'table' and type(payload.stage) == 'string' then
				b3Stage = payload.stage
			end
		end
	end)

	local uid = plr.UserId
	local stageStr = tostring(b3Stage or '')
	local resumeConnect = (stageStr == 'connect') or (b3SeqCompleted and stageStr ~= 'placing')
	local resumePlacement = (stageStr == 'placing') or (b3ResumeAt ~= nil and not b3SeqCompleted)

	if resumeConnect then
		print('[OB_B3] Reseed: resume Industrial connectivity checks')
		hideArrow(plr)
		roadPending[uid] = false
		barrage1Completed[uid] = true
		_clearB2Caches(uid)
		barrage2Started[uid] = nil
		StateChanged:FireClient(plr, 'Onboarding_B3_Begin')
		_beginBarrage3Connectivity(plr, {x=-5,z=6}, {x=-8,z=15})
	elseif resumePlacement then
		local resumeStep = b3ResumeAt or 1
		print(('[OB_B3] Reseed: resume Industrial placement at step %d'):format(resumeStep))
		hideArrow(plr)
		roadPending[uid] = false
		barrage1Completed[uid] = true
		startBarrage3(plr, resumeStep)
	elseif barrage1Completed[plr.UserId] then
		print('[OB_B2] Reseed: B1 previously complete + starting B2')
		hideArrow(plr)
		roadPending[plr.UserId] = false
		if not barrage2Started[plr.UserId] then
			startBarrage2(plr, b2ResumeAt, savedB2Phase)
		end
	elseif resumeAt then
		print('[OB] Reseed: Resuming Barrage 1 at step', resumeAt)
		hideArrow(plr)
		roadPending[plr.UserId] = false
		startBarrage1(plr, resumeAt)
	else
		-- Fresh resume, no auto-start to avoid auto-routing
		print('[OB] Reseed: nudge Build (no auto-start)')
		showBuildArrow(plr)
		StateChanged:FireClient(plr, 'BuildMenu_GateClear')
		if B1_AUTOSTART_ON_JOIN then
			task.defer(function()
				if plr.Parent and onboardingActive(plr)
					and not barrage2Started[plr.UserId]
				then
					ensureBarrage1Running(plr)
				end
			end)
		end
	end
end

local function hookReloadFromCurrent(event: Instance?)
	if not event or not event:IsA("BindableEvent") then
		return false
	end

	event.Event:Connect(function(plr: Player)
		-- Let SaveManager finish swapping live data before we inspect state again.
		task.delay(0.25, function()
			pcall(_reseedOnboardingFor, plr)
		end)
	end)

	return true
end

-- --------------------------------------------------------------------------------------
-- Lifecycle
-- --------------------------------------------------------------------------------------
Players.PlayerAdded:Connect(function(plr: Player)
	if not plr:GetAttribute("_PlayerDataLoaded") then
		plr:GetAttributeChangedSignal("_PlayerDataLoaded"):Wait()
	end
	-- >>> CHANGE: unify join behavior with reload behavior
	_reseedOnboardingFor(plr)
end)

Players.PlayerRemoving:Connect(function(plr: Player)
	local uid = plr.UserId
	roadPending[uid], lastPulsed[uid], barrageStarted[uid] = nil, nil, nil
	ONBOARDING_ENABLED[uid] = nil
	if barrage2Conn[uid] then barrage2Conn[uid]:Disconnect(); barrage2Conn[uid] = nil end
	barrage2Started[uid], barrage1Completed[uid] = nil, nil
	_clearB2Caches(uid)

	-- B3 cleanup
	if barrage3Conn[uid] then barrage3Conn[uid]:Disconnect(); barrage3Conn[uid] = nil end
	barrage3Started[uid] = nil
	b3ZoneId[uid], b3KnownZones[uid] = nil, nil
	b3EvalQueued[uid], b3LastPrintAt[uid], b3LastHintAt[uid], b3LastHintKey[uid] = nil, nil, nil, nil

	-- B1 debounce cleanup
	b1LastKickIdx[uid], b1KickCooldownAt[uid] = nil, nil
end)

local BE_Toggle = BE:FindFirstChild("OnboardingToggle")
if BE_Toggle then
	BE_Toggle.Event:Connect(function(enabled)
		for _, p in ipairs(Players:GetPlayers()) do
			setOnboardingEnabled(p, enabled ~= false)
		end
	end)
end

local BE_ForceDisable = BE:FindFirstChild("ForceDisableOnboarding")
if BE_ForceDisable then
	BE_ForceDisable.Event:Connect(function(target)
		if typeof(target) == "Instance" and target:IsA("Player") then
			setOnboardingEnabled(target, false)
		elseif typeof(target) == "table" then
			for _, plr in ipairs(target) do
				if typeof(plr) == "Instance" and plr:IsA("Player") then
					setOnboardingEnabled(plr, false)
				end
			end
		end
	end)
else
	warn("[Onboarding] ForceDisableOnboarding bindable missing; delete flow will not clear onboarding immediately.")
end

-- >>> ADD: reseed when SaveEndpoints asks the server to reload the active slot
if not hookReloadFromCurrent(ReloadFromCurrentBE) then
	BE.ChildAdded:Connect(function(child)
		if child.Name == "RequestReloadFromCurrent" then
			hookReloadFromCurrent(child)
		end
	end)
end


-- --------------------------------------------------------------------------------------
-- Main bridge (client -> server)
-- --------------------------------------------------------------------------------------
StepCompleted.OnServerEvent:Connect(function(player: Player, stepName: any, data: any)
	if typeof(stepName) ~= "string" then return end
	if not onboardingActive(player) then return end

	-- Optional: client can ask for a start/re-emit if it detects "not running" locally
	if stepName == "OB_ReemitStartWanted" then
		ensureBarrage1Running(player)
		return
	end

	-- Tool picks clear gates; if B1 is running, do NOT restart it (gate-only refresh)
	if stepName == "WaterToolSelected" then
		print("[OB_B2] Water tool selected by", player.Name)
		-- For barrage2/3, keep the current gate/pulse intact so the selected tool keeps pulsing.
		if barrage2Started[player.UserId] or barrage3Started[player.UserId] then
			StateChanged:FireClient(player, "BuildMenu_GateOnly_Current")
		else
			StateChanged:FireClient(player, "BuildMenu_GateClear")
			if barrageStarted[player.UserId] then
				StateChanged:FireClient(player, "BuildMenu_GateOnly_Current")
			end
		end
		return
	end
	if stepName == "PowerToolSelected" then
		print("[OB_B2] Power tool selected by", player.Name)
		-- For barrage2/3, keep the current gate/pulse intact so the selected tool keeps pulsing.
		if barrage2Started[player.UserId] or barrage3Started[player.UserId] then
			StateChanged:FireClient(player, "BuildMenu_GateOnly_Current")
		else
			StateChanged:FireClient(player, "BuildMenu_GateClear")
			if barrageStarted[player.UserId] then
				StateChanged:FireClient(player, "BuildMenu_GateOnly_Current")
			end
		end
		return
	end

	if stepName == "CityNamed" then
		showBuildArrow(player)
		return
	end

	if stepName == "BuildMenuOpened" then
		-- If we are beyond B1:
		--   - Never repulse/gate for DirtRoad
		--   - Keep the current gate when B2/B3 is active so routing stays on Supply/Power/Water
		if barrage1Completed[player.UserId] or barrage2Started[player.UserId] or barrage3Started[player.UserId] then
			StateChanged:FireClient(player, "UIPulse_Stop", { key = "BM_DirtRoad" })
			stopPulseItem(player, "DirtRoad")
			if barrage2Started[player.UserId] or barrage3Started[player.UserId] then
				StateChanged:FireClient(player, "BuildMenu_GateOnly_Current")
			else
				StateChanged:FireClient(player, "BuildMenu_GateClear")
			end
			return
		end

		hideArrow(player)

		-- If Barrage1 is already running, only refresh the current gate.
		if barrageStarted[player.UserId] then
			StateChanged:FireClient(player, "BuildMenu_GateOnly_Current")
			return
		end

		-- If there is saved progress, DO NOT kick here; only gate to current.
		local idx, total
		local ok = pcall(function()
			if OnboardingService.GetGuardProgress then
				idx, total = OnboardingService.GetGuardProgress(player, "barrage1")
			end
		end)
		if ok and type(idx) == "number" and (not total or idx < total) then
			StateChanged:FireClient(player, "BuildMenu_GateOnly_Current")
			return
		end

		-- Truly fresh: do not start B1 on open. Just clear (client can do passive pulse).
		StateChanged:FireClient(player, "BuildMenu_GateClear")
		-- If you *really* want auto-start on first open, turn on B1_AUTOSTART_ON_FIRST_OPEN and call ensure here.
		-- (left disabled by default to prevent auto-routing on open)
		return
	end

	if stepName == "RoadToolSelected" then
		-- If we are in B2 or B3 phases, just clear the gate and let those phases coach.
		if barrage1Completed[player.UserId] or barrage2Started[player.UserId] or barrage3Started[player.UserId] then
			StateChanged:FireClient(player, "BuildMenu_GateClear")
			return
		end
		pcall(function()
			if OnboardingService.MarkStep then
				OnboardingService.MarkStep(player, "RoadToolSelected")
			end
		end)
		roadPending[player.UserId] = false
		stopPulseItem(player, "DirtRoad")
		StateChanged:FireClient(player, "BuildMenu_GateClear")
		StateChanged:FireClient(player, "UIPulse_Stop", { key = "BM_DirtRoad" })
		if not barrageStarted[player.UserId] then
			StateChanged:FireClient(player, "ShowHint_SelectRoad_Done")
			startBarrage1(player)
		else
			StateChanged:FireClient(player, "BuildMenu_GateOnly_Current")
		end
		return
	end

	if stepName == "GuardStepDone" and typeof(data) == "table" then
		local seq   = tostring(data.seq or "")
		local index = tonumber(data.index or 0) or 0
		local total = tonumber(data.total or 0) or 0
		if seq ~= "" and index > 0 then
			pcall(function()
				if OnboardingService.RecordGuardProgress then
					OnboardingService.RecordGuardProgress(player, seq, index, total)
				end
			end)
		end
		return
	end

	-- Accelerator: client reports that the B3 Industrial rect was placed
	if stepName == "B3_ZonePlaced" then
		local uid = player.UserId
		if barrage3Started[uid] == "placing" then
			print("[OB_B3] Zone placement reported; switching to connectivity checks")
			_beginBarrage3Connectivity(player, {x=-5,z=6}, {x=-8,z=15})
		end
		return
	end

	if stepName == "OnboardingFinished" then
		local uid = player.UserId
		if barrageStarted[uid] then
			pcall(function()
				if OnboardingService and OnboardingService.MarkStep then
					OnboardingService.MarkStep(player, "Barrage1_Complete")
				end
			end)
			barrageStarted[uid], roadPending[uid], lastPulsed[uid] = nil, nil, nil
			barrage1Completed[uid] = true
			startBarrage2(player, nil, nil)
			return
		end
		-- If we just finished the B3 "place Industrial rect" guard, begin connectivity checks
		if barrage3Started[uid] == "placing" then
			print("[OB_B3] Rect guard finished; switching to connectivity checks")
			_beginBarrage3Connectivity(player, {x=-5,z=6}, {x=-8,z=15})
			return
		end
		return
	end
end)

local function _isAllowedInvoker(plr: Player)
	if RunService:IsStudio() then return true end
	return WHITELIST[plr.UserId] == true
end

if OnboardingAdmin then
	OnboardingAdmin.OnServerInvoke = function(plr: Player, cmd: string, args: any)
		if not _isAllowedInvoker(plr) then
			return false, "Not allowed"
		end
		cmd = tostring(cmd or ""):lower()

		if cmd == "reset" or cmd == "resetonboarding" then
			local okReset, err = require(ServerScriptService.Players.OnboardingService).Reset(plr)
			if not okReset then return false, err or "Reset failed" end

			-- Clear all running flows/watchers and set onboarding ON
			local uid = plr.UserId

			-- Kill B2 watchers
			if barrage2Conn[uid] then barrage2Conn[uid]:Disconnect(); barrage2Conn[uid] = nil end
			barrage2Started[uid] = nil
			_clearB2Caches(uid)

			-- Kill B3 watchers
			if barrage3Conn[uid] then barrage3Conn[uid]:Disconnect(); barrage3Conn[uid] = nil end
			barrage3Started[uid] = nil
			b3ZoneId[uid], b3KnownZones[uid] = nil, nil
			b3EvalQueued[uid], b3LastPrintAt[uid], b3LastHintAt[uid], b3LastHintKey[uid] = nil, nil, nil, nil

			-- Clear Barrage1 locals
			roadPending[uid], lastPulsed[uid], barrageStarted[uid] = nil, nil, nil
			barrage1Completed[uid] = nil

			-- B1 debounce cleanup
			b1LastKickIdx[uid], b1KickCooldownAt[uid] = nil, nil

			-- Re-enable onboarding for this session and nudge the Build button
			setOnboardingEnabled(plr, true)
			showBuildArrow(plr)
			StateChanged:FireClient(plr, "BuildMenu_GateClear")

			-- Optional: auto-start immediately after reset (off by default)
			if B1_AUTOSTART_ON_JOIN then
				task.delay(0.75, function()
					if plr.Parent and onboardingActive(plr) then
						ensureBarrage1Running(plr)
					end
				end)
			end

			return true, "Onboarding reset"
		end

		return false, "Unknown command"
	end
else
	warn("[Onboarding] OnboardingAdmin RemoteFunction not found; admin commands disabled.")
end

