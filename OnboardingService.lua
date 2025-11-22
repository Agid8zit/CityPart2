local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BadgeServiceModule = require(ServerScriptService.Services.BadgeService)

-- --------------------------------------------------------------------------
-- Server-safe module accessor + smart invoker (supports ":" and ".")
-- --------------------------------------------------------------------------
local function _tryRequire(path: Instance?): any
	if not path then return nil end
	local ok, mod = pcall(require, path)
	if ok then return mod end
	return nil
end

-- Try common locations in your project
local _SaveManager =
	_tryRequire(ServerScriptService:FindFirstChild("SaveManager")) or
	_tryRequire((ServerScriptService:FindFirstChild("Players") or ServerScriptService):FindFirstChild("SaveManager")) or
	_tryRequire((ServerScriptService:FindFirstChild("Services") or ServerScriptService):FindFirstChild("PlayerDataService")) or
	_tryRequire(ServerScriptService:FindFirstChild("PlayerDataService"))

-- Call a module function that might be defined with "." or ":".
-- We try method style first (":"), then function style (".").
-- FIX: capture varargs and pass them to pcall without a closure (prevents '... outside of vararg').
local function _smartCall(mod, fnName: string, player: Player, ...)
	if not mod then return nil end
	local f = mod[fnName]
	if typeof(f) ~= "function" then return nil end

	local args = table.pack(...)

	-- 1) Try method-call style (adds 'self' = mod)
	local ok, res = pcall(f, mod, player, table.unpack(args, 1, args.n))
	if ok and res ~= nil then
		return res
	end

	-- 2) Try function-call style (no 'self')
	ok, res = pcall(f, player, table.unpack(args, 1, args.n))
	if ok then
		return res
	end

	return nil
end

local function getProfile(player: Player): table?
	-- Prefer canonical server API if present
	if _SaveManager then
		-- Try common method names you've used before (both ":" and ".")
		local prof = _smartCall(_SaveManager, "GetProfile", player)
			or _smartCall(_SaveManager, "GetData", player)
			or _smartCall(_SaveManager, "ProfileFor", player)
		if typeof(prof) == "table" then
			return prof
		end
	end
	-- Safe fallback -> nil (callers no-op)
	return nil
end

-- --------------------------------------------------------------------------
-- Stores / module table
-- --------------------------------------------------------------------------
-- Audit store that is NOT deleted by "Delete Save" in your UI:
local AUDIT_STORE = DataStoreService:GetDataStore("OnboardingAudit_v1")

local OnboardingService = {}
OnboardingService.__index = OnboardingService

-- --------------------------------------------------------------------------
-- Client fanout + helpers
-- --------------------------------------------------------------------------
local function fireClientState(player: Player, stepName: string, payload: any?)
	local REFolder = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents")
	local StateChanged = REFolder:WaitForChild("OnboardingStateChanged")
	StateChanged:FireClient(player, stepName, payload)
end

-- Initialize the onboarding blob in the player's (account‑wide) profile if missing.
local function ensureOnboardingBlob(profile: table)
	-- Add or normalize structure (account‑wide)
	profile.Onboarding = profile.Onboarding or {}
	local ob = profile.Onboarding

	-- Core envelope
	ob.version  = ob.version or 1
	ob.state    = ob.state or "NotStarted"   -- "NotStarted" | "InProgress" | "Completed" | "Skipped"
	ob.steps    = ob.steps or {}
	ob.firstSeenAt  = ob.firstSeenAt or os.time()
	ob.completedAt  = ob.completedAt or nil
	ob.skippedAt    = ob.skippedAt or nil   -- when we consumed "skip" from the audit store
	ob.completionAwarded = ob.completionAwarded == true
	ob.skipAwarded       = ob.skipAwarded == true

	-- Progress: sequences and B2 phase
	ob.progress = ob.progress or {}
	ob.progress.sequences = ob.progress.sequences or {}           -- { [seq] = { lastIndex, total } }
	ob.progress.lastStage = ob.progress.lastStage or {            -- convenience mirror
		seq   = "",
		index = 0,
		total = 0,
	}
	ob.progress.b2 = ob.progress.b2 or {                          -- Barrage 2 coarse resume
		phase = "",                                              -- "" | "water" | "power"
		lastSeenAt = 0,
	}
	ob.progress.b3 = ob.progress.b3 or {                          -- Barrage 3 coarse resume
		stage = "",                                               -- "" | "placing" | "connect"
		zoneId = "",
		lastSeenAt = 0,
	}

	return ob
end

local function awardCompletionBadge(player: Player?, ob)
	if not player or ob.completionAwarded then return end
	local success = select(1, BadgeServiceModule.AwardOnboardingCompleted(player))
	if success then
		ob.completionAwarded = true
	end
end

local function awardSkipBadge(player: Player?, ob)
	if not player or ob.skipAwarded then return end
	local success = select(1, BadgeServiceModule.AwardOnboardingSkipped(player))
	if success then
		ob.skipAwarded = true
	end
end

-- --------------------------------------------------------------------------
-- Public API
-- --------------------------------------------------------------------------

-- Call on PlayerAdded (after profile is loaded) IF you want gated kickoff.
function OnboardingService.StartIfNeeded(player: Player)
	local profile = getProfile(player)
	if not profile then return end

	local ob = ensureOnboardingBlob(profile)

	-- 1) Consume any pending "skip" flag from audit store
	local key = ("onboarding_audit:%d"):format(player.UserId)
	local record
	pcall(function()
		record = AUDIT_STORE:GetAsync(key)
	end)
	if record and record.pendingSkip == true then
		-- Historical "skip" — persist account‐wide facts
		awardSkipBadge(player, ob)
		ob.state     = (ob.state == "Completed") and "Completed" or "Skipped"
		ob.skippedAt = record.skipAt or os.time()

		-- Clear the audit flag (so we don't keep reprocessing)
		pcall(function()
			AUDIT_STORE:SetAsync(key, { pendingSkip = false, skipAt = ob.skippedAt })
		end)
		-- NOTE: We do NOT reset steps/progress here; "Skipped" is terminal until you explicitly re‑enable.
	end

	-- 2) If already completed from a past run, ensure they get the completion badge
	if ob.state == "Completed" then
		awardCompletionBadge(player, ob)
		return
	end

	-- 3) Otherwise, ensure we are InProgress (unless Skipped)
	if ob.state == "NotStarted" then
		ob.state = "InProgress"
	end
end

-- Use this NOW while you're not gating with StartIfNeeded.
-- It simply tells the client to show the city-naming prompt.
function OnboardingService.KickoffCityNaming(player: Player)
	fireClientState(player, "CityNaming")
end

-- Mark a tutorial step as completed; can be called multiple times safely
function OnboardingService.MarkStep(player: Player, stepId: string)
	local profile = getProfile(player)
	if not profile then return end
	local ob = ensureOnboardingBlob(profile)
	if ob.state ~= "InProgress" then return end
	ob.steps[stepId] = true
end

-- Finish onboarding and award completion badge once
function OnboardingService.Complete(player: Player)
	local profile = getProfile(player)
	if not profile then return end
	local ob = ensureOnboardingBlob(profile)
	ob.state = "Completed"
	ob.completedAt = ob.completedAt or os.time()

	-- Clear coarse B2 phase tracker (not strictly required)
	if ob.progress and ob.progress.b2 then
		ob.progress.b2.phase = ""
		ob.progress.b2.lastSeenAt = os.time()
	end
	-- Clear B3 coarse stage tracker
	if ob.progress and ob.progress.b3 then
		ob.progress.b3.stage = ""
		ob.progress.b3.zoneId = ""
		ob.progress.b3.lastSeenAt = os.time()
	end

	awardCompletionBadge(player, ob)
end

-- Drive a logical step and notify the client (used by your bridge/server logic)
function OnboardingService.Advance(player: Player, stepName: string, payload: any?)
	local profile = getProfile(player)
	if not profile then
		-- Even if profile isn't ready, you may still want to nudge client UI:
		fireClientState(player, stepName, payload)
		return
	end
	local ob = ensureOnboardingBlob(profile)
	-- Do NOT mark Completed here; just move through named steps.
	if ob.state == "NotStarted" then
		ob.state = "InProgress"
	end
	ob.steps[stepName] = true
	fireClientState(player, stepName, payload)
end

-- Exactly when the player presses "Delete Save" WHILE onboarding is InProgress.
-- Writes to an audit store not cleared by your per-save wipe.
function OnboardingService.RecordDeletionDuringOnboarding(userId: number, player: Player?)
	local key = ("onboarding_audit:%d"):format(userId)
	local now = os.time()
	pcall(function()
		local current = AUDIT_STORE:GetAsync(key) or {}
		current.pendingSkip = true
		current.skipAt = now
		AUDIT_STORE:SetAsync(key, current)
	end)

	-- If the player is online, immediately reflect the skip locally so onboarding
	-- stops gating this session instead of waiting for a reload/rejoin.
	if player then
		local profile = getProfile(player)
		if profile then
			local ob = ensureOnboardingBlob(profile)
			if ob.state ~= "Completed" then
				ob.state = "Skipped"
				ob.skippedAt = now
				awardSkipBadge(player, ob)
			end
		end
	end
end

-- === Progress (Barrage 1 guard) ============================================

function OnboardingService.RecordGuardProgress(player: Player, seq: string, idx: number, total: number?)
	local profile = getProfile(player); if not profile then return end
	local ob = ensureOnboardingBlob(profile)
	ob.progress = ob.progress or { sequences = {} }
	local rec = ob.progress.sequences[seq] or {}
	rec.lastIndex = idx
	if type(total) == "number" and total > 0 then rec.total = total end
	ob.progress.sequences[seq] = rec

	-- Mirror into lastStage (coarse, for dashboards)
	ob.progress.lastStage = {
		seq   = seq,
		index = idx,
		total = rec.total or total or 0,
	}
end

function OnboardingService.GetGuardProgress(player: Player, seq: string): (number?, number?)
	local profile = getProfile(player); if not profile then return nil end
	local ob = ensureOnboardingBlob(profile)
	local rec = ob.progress and ob.progress.sequences and ob.progress.sequences[seq]
	if not rec then return nil end
	return rec.lastIndex, rec.total
end

-- === Progress (Barrage 2 coarse phase) =====================================

function OnboardingService.SetB2Phase(player: Player, phase: "water"|"power"|""?)
	local profile = getProfile(player); if not profile then return end
	local ob = ensureOnboardingBlob(profile)
	ob.progress = ob.progress or {}
	ob.progress.b2 = ob.progress.b2 or { phase = "", lastSeenAt = 0 }
	ob.progress.b2.phase = phase or ""
	ob.progress.b2.lastSeenAt = os.time()
end

function OnboardingService.GetB2Phase(player: Player): string?
	local profile = getProfile(player); if not profile then return nil end
	local ob = ensureOnboardingBlob(profile)
	return ob.progress and ob.progress.b2 and ob.progress.b2.phase or nil
end

-- === Progress (Barrage 3 coarse stage) =====================================

function OnboardingService.SetB3Stage(player: Player, stage: "placing"|"connect"|""?, info: {zoneId: string?}?)
	local profile = getProfile(player); if not profile then return end
	local ob = ensureOnboardingBlob(profile)
	ob.progress = ob.progress or {}
	ob.progress.b3 = ob.progress.b3 or { stage = "", zoneId = "", lastSeenAt = 0 }
	ob.progress.b3.stage = stage or ""
	ob.progress.b3.zoneId = (info and info.zoneId) or ob.progress.b3.zoneId or ""
	ob.progress.b3.lastSeenAt = os.time()
end

function OnboardingService.GetB3Stage(player: Player): (string?, {zoneId: string?, lastSeenAt: number?}?)
	local profile = getProfile(player); if not profile then return nil end
	local ob = ensureOnboardingBlob(profile)
	local b3 = ob.progress and ob.progress.b3
	if not b3 then return nil end
	return b3.stage or "", { zoneId = b3.zoneId, lastSeenAt = b3.lastSeenAt }
end

-- === Queries ================================================================

function OnboardingService.IsCompleted(player: Player): boolean
	local profile = getProfile(player); if not profile then return false end
	local ob = ensureOnboardingBlob(profile)
	return ob.state == "Completed"
end

function OnboardingService.IsInProgress(player: Player): boolean
	local profile = getProfile(player); if not profile then return false end
	local ob = ensureOnboardingBlob(profile)
	return ob.state == "InProgress"
end

function OnboardingService.IsSkipped(player: Player): boolean
	local profile = getProfile(player); if not profile then return false end
	local ob = ensureOnboardingBlob(profile)
	return (ob.state == "Skipped") or (ob.skipAwarded == true)
end

-- Returns a compact account-wide status snapshot
function OnboardingService.GetStatus(player: Player): table
	local profile = getProfile(player)
	if not profile then
		return { state = "Unknown" }
	end
	local ob = ensureOnboardingBlob(profile)
	local idx, total = OnboardingService.GetGuardProgress(player, "barrage1")
	return {
		state       = ob.state,                        -- "NotStarted" | "InProgress" | "Completed" | "Skipped"
		completed   = ob.state == "Completed",
		skipped     = (ob.state == "Skipped") or (ob.skipAwarded == true),
		completedAt = ob.completedAt,
		skippedAt   = ob.skippedAt,
		stage = {
			seq   = idx and "barrage1" or nil,
			index = idx,
			total = total,
			b2    = { phase = OnboardingService.GetB2Phase(player) },
		}
	}
end

function OnboardingService.Reset(player: Player)
	local profile = getProfile(player)
	if not profile then return false, "No profile" end

	-- Ensure blob exists, then hard‑reset it
	local ob = ensureOnboardingBlob(profile)

	ob.state    = "NotStarted"
	ob.steps    = {}
	ob.firstSeenAt = ob.firstSeenAt or os.time() -- keep firstSeenAt for analytics if you want
	ob.completedAt = nil
	ob.skippedAt   = nil

	-- You generally can’t “unaward” badges, but clearing these booleans prevents your code
	-- from treating the profile as completed/skipped next time.
	ob.completionAwarded = false
	ob.skipAwarded       = false

	-- Progress reset
	ob.progress = {
		sequences = {},                     -- clears barrage1 guard progress
		lastStage = { seq = "", index = 0, total = 0 },
		b2 = { phase = "", lastSeenAt = os.time() },
		b3 = { stage = "", zoneId = "", lastSeenAt = os.time() },
	}

	-- Also clear the audit “pending skip” record so StartIfNeeded won’t skip again
	local key = ("onboarding_audit:%d"):format(player.UserId)
	pcall(function()
		AUDIT_STORE:SetAsync(key, { pendingSkip = false, skipAt = nil })
	end)

	return true
end

return OnboardingService
