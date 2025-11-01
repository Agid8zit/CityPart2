-- ServerScriptService/Players/OnboardingServerBridge.server.lua
-- Unified pulse + flow kick: arrow -> pulse "DirtRoad" -> start barrage1 after selection.
-- Idempotent and toggle-aware. Uses per-player enable based on account-wide onboarding state.

-- Services
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local Players              = game:GetService("Players")
local ServerScriptService  = game:GetService("ServerScriptService")

-- Events / Remotes
local RE = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents")
local BE = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents")

local StepCompleted = RE:WaitForChild("OnboardingStepCompleted")   -- client -> server
local StateChanged  = RE:WaitForChild("OnboardingStateChanged")    -- server -> client
local ToggleRE      = RE:WaitForChild("OnboardingToggle")          -- server -> client (centralized toggle)

-- Service (server-side, account-wide state + badges)
local OnboardingService = require(ServerScriptService.Players.OnboardingService)

-- --------------------------------------------------------------------------------------
-- Per-player enable flag (authoritative on server). Do NOT overwrite this table en masse.
-- --------------------------------------------------------------------------------------
local ONBOARDING_ENABLED: {[number]: boolean} = {}

-- Per-player transient state (server-only)
local roadPending     : {[number]: boolean} = {}
local lastPulsed      : {[number]: string}  = {} -- prevent duplicate item pulses
local barrageStarted  : {[number]: boolean} = {}

-- --------------------------------------------------------------------------------------
-- Helpers
-- --------------------------------------------------------------------------------------
local function onboardingActive(player: Player): boolean
	return ONBOARDING_ENABLED[player.UserId] == true
end

local function setOnboardingEnabled(player: Player, enabled: boolean)
	local want = (enabled ~= false)
	ONBOARDING_ENABLED[player.UserId] = want
	-- Tell the client to turn the onboarding UI/pulses on/off
	ToggleRE:FireClient(player, want)

	if not want then
		-- be aggressive about clearing any UI the server started
		StateChanged:FireClient(player, "BuildMenu_GateClear")
		StateChanged:FireClient(player, "UIPulse_Stop", { key = "BM_DirtRoad" })
		StateChanged:FireClient(player, "HideArrow")
		roadPending[player.UserId]    = nil
		lastPulsed[player.UserId]     = nil
		barrageStarted[player.UserId] = nil
	end
end

-- UI helpers (server->client)
local function showBuildArrow(player: Player)
	StateChanged:FireClient(player, "ShowArrow_BuildMenu")
end

local function hideArrow(player: Player)
	StateChanged:FireClient(player, "HideArrow")
end

local function pulseItem(player: Player, itemName: string)
	-- Avoid duplicate pulses for same item
	if lastPulsed[player.UserId] == itemName then return end
	StateChanged:FireClient(player, "Pulse_Item", { item = itemName })
	lastPulsed[player.UserId] = itemName
end

local function stopPulseItem(player: Player, itemName: string)
	-- Controller is idempotent; safe to send even if not current
	StateChanged:FireClient(player, "Stop_Pulse_Item", { item = itemName })
	if lastPulsed[player.UserId] == itemName then
		lastPulsed[player.UserId] = nil
	end
end

local function startBarrage1(player: Player, resumeAt: number?)
	-- Allow re-sends if we need to reposition the client to a later step
	barrageStarted[player.UserId] = true
	if type(resumeAt) == "number" then
		StateChanged:FireClient(player, "Onboarding_StartBarrage1", { resumeAt = resumeAt })
	else
		StateChanged:FireClient(player, "Onboarding_StartBarrage1")
	end
end

local function cleanupPlayer(userId: number)
	roadPending[userId]    = nil
	lastPulsed[userId]     = nil
	barrageStarted[userId] = nil
	ONBOARDING_ENABLED[userId] = nil
end

-- --------------------------------------------------------------------------------------
-- Lifecycle: join/leave
-- --------------------------------------------------------------------------------------

Players.PlayerAdded:Connect(function(plr: Player)
	-- Wait for PlayerData to load (flag set by PlayerDataService.Load)
	if not plr:GetAttribute("_PlayerDataLoaded") then
		plr:GetAttributeChangedSignal("_PlayerDataLoaded"):Wait()
	end

	-- Reconcile server-side audit state (skip/completion + badge once)
	pcall(function()
		OnboardingService.StartIfNeeded(plr)
	end)

	-- Enable if account hasn't completed onboarding
	local completed = false
	local ok, res = pcall(function() return OnboardingService.IsCompleted and OnboardingService.IsCompleted(plr) end)
	if ok and res == true then completed = true end

	setOnboardingEnabled(plr, not completed)
	
	local resumeAt: number? = nil
	pcall(function()
		if OnboardingService.GetGuardProgress then
			local idx, total = OnboardingService.GetGuardProgress(plr, "barrage1")
			if type(idx) == "number" and idx >= 1 then
				if type(total) == "number" and idx >= total then
					-- Sequence already finished; disable onboarding
					setOnboardingEnabled(plr, false)
				else
					resumeAt = idx + 1
				end
			end
		end
	end)

	if onboardingActive(plr) then
		if resumeAt then
			hideArrow(plr)
			roadPending[plr.UserId] = false
			startBarrage1(plr, resumeAt)
		else
			showBuildArrow(plr)
		end
	end
	
	-- First nudge if enabled (client-side gates will suppress if Build Menu is already open)
	if onboardingActive(plr) then
		showBuildArrow(plr)
	end
end)

Players.PlayerRemoving:Connect(function(plr: Player)
	cleanupPlayer(plr.UserId)
end)

-- --------------------------------------------------------------------------------------
-- Optional server-wide toggle (studio/ops). This is a BindableEvent under ReplicatedStorage.
-- If present and fired by a server script, it broadcasts enable/disable to all current players.
-- --------------------------------------------------------------------------------------
local BE_Toggle = BE:FindFirstChild("OnboardingToggle")
if BE_Toggle then
	BE_Toggle.Event:Connect(function(enabled)
		for _, p in ipairs(Players:GetPlayers()) do
			setOnboardingEnabled(p, enabled ~= false)
		end
	end)
end

-- --------------------------------------------------------------------------------------
-- Main event bridge (client -> server)
-- --------------------------------------------------------------------------------------
StepCompleted.OnServerEvent:Connect(function(player: Player, stepName: any, data: any)
	if typeof(stepName) ~= "string" then return end
	if not onboardingActive(player) then return end

	-- 1) After the city gets named, nudge to open Build Menu
	if stepName == "CityNamed" then
		showBuildArrow(player)
		return
	end

	-- 2) When Build Menu opens, gate/pulse DirtRoad as the first required tool
	if stepName == "BuildMenuOpened" then
		hideArrow(player)

		-- If barrage already started this session, gate to the current guarded step
		if barrageStarted[player.UserId] then
			StateChanged:FireClient(player, "BuildMenu_GateOnly_Current")
			return
		end

		-- If we have saved progress, start + gate to the right step now
		local idx, total
		local ok = pcall(function()
			if OnboardingService.GetGuardProgress then
				idx, total = OnboardingService.GetGuardProgress(player, "barrage1")
			end
		end)
		if ok and type(idx) == "number" and (not total or idx < total) then
			startBarrage1(player, (idx + 1))
			StateChanged:FireClient(player, "BuildMenu_GateOnly_Current")
			return
		end

		-- Fall back to the initial nudge (first time only)
		StateChanged:FireClient(player, "UIPulse_Start", { key = "BM_DirtRoad", offset = UDim2.new(0, 0, -0.12, 0) })
		StateChanged:FireClient(player, "BuildMenu_GateOnly", { itemID = "DirtRoad" })
		if not roadPending[player.UserId] then
			roadPending[player.UserId] = true
			pulseItem(player, "DirtRoad")
		end
		return
	end

	-- 3) When the player picks the Road tool, clear pulses/gate and start Barrage 1
	if stepName == "RoadToolSelected" then
		pcall(function()
			if OnboardingService.MarkStep then
				OnboardingService.MarkStep(player, "RoadToolSelected")
			end
		end)
		roadPending[player.UserId] = false
		stopPulseItem(player, "DirtRoad")
		StateChanged:FireClient(player, "BuildMenu_GateClear")
		StateChanged:FireClient(player, "UIPulse_Stop", { key = "BM_DirtRoad" })
		StateChanged:FireClient(player, "ShowHint_SelectRoad_Done")
		startBarrage1(player)
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

	-- 4) Flow completion (client reports the scripted sequence finished)
	if stepName == "OnboardingFinished" then
		pcall(function()
			if OnboardingService.Complete then
				OnboardingService.Complete(player)
			end
		end)
		setOnboardingEnabled(player, false)
		return
	end
end)
