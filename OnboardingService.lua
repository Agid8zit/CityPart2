local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- === CONFIG: set your real badge IDs here ===
local ONBOARDING_COMPLETED_BADGE_ID = 0  -- TODO: set real ID
local ONBOARDING_SKIPPED_BADGE_ID   = 0  -- TODO: set real ID

-- --------------------------------------------------------------------------
-- Server-safe profile accessor (tries likely server modules; never touches client controllers)
-- --------------------------------------------------------------------------
local function _tryRequire(path: Instance?): any
	if not path then return nil end
	local ok, mod = pcall(require, path)
	if ok then return mod end
	return nil
end

-- Attempt a few common server-side data modules in your project:
local _SaveManager =
	_tryRequire(ServerScriptService:FindFirstChild("SaveManager")) or
	_tryRequire((ServerScriptService:FindFirstChild("Players") or ServerScriptService):FindFirstChild("SaveManager")) or
	_tryRequire((ServerScriptService:FindFirstChild("Services") or ServerScriptService):FindFirstChild("PlayerDataService")) or
	_tryRequire(ServerScriptService:FindFirstChild("PlayerDataService"))

local function getProfile(player: Player): table?
	-- Prefer a canonical server API if present
	if _SaveManager then
		-- Try common method names you've used before
		if typeof(_SaveManager.GetProfile) == "function" then
			return _SaveManager:GetProfile(player)
		elseif typeof(_SaveManager.GetData) == "function" then
			return _SaveManager:GetData(player)
		elseif typeof(_SaveManager.ProfileFor) == "function" then
			return _SaveManager:ProfileFor(player)
		end
	end
	-- As a safe fallback, return nil; caller will simply no-op
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

-- Initialize the onboarding blob in the player's profile if missing.
local function ensureOnboardingBlob(profile)
	profile.Onboarding = profile.Onboarding or {
		version      = 1,
		state        = "NotStarted",
		steps        = {},
		firstSeenAt  = os.time(),
		completedAt  = nil,
		completionAwarded = false,
		skipAwarded       = false,
		progress     = { sequences = {} }, -- <-- ADD
	}
	-- If existing saves are missing progress, ensure it exists.
	profile.Onboarding.progress = profile.Onboarding.progress or { sequences = {} }
	return profile.Onboarding
end

-- Helpful internal: Badge award with debounce+pcall.
local function safeUserHasBadgeAsync(userId: number, badgeId: number): boolean
	if badgeId == 0 then return false end -- not configured
	local ok, has = pcall(BadgeService.UserHasBadgeAsync, BadgeService, userId, badgeId)
	return ok and has == true
end

local function safeAwardBadge(userId: number, badgeId: number)
	if badgeId == 0 then return end
	-- Double-check before award, then award, then re-check guards on profile fields.
	local has = safeUserHasBadgeAsync(userId, badgeId)
	if has then return end
	pcall(function()
		BadgeService:AwardBadge(userId, badgeId)
	end)
end

-- --------------------------------------------------------------------------
-- Public API
-- --------------------------------------------------------------------------

-- Call on PlayerAdded (after profile is loaded) IF you want gated kickoff.
-- You said you'll hook later; leaving this intact is harmless.
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
		-- award skip badge once
		if not ob.skipAwarded then
			-- BadgeService check + award
			if not safeUserHasBadgeAsync(player.UserId, ONBOARDING_SKIPPED_BADGE_ID) then
				safeAwardBadge(player.UserId, ONBOARDING_SKIPPED_BADGE_ID)
			end
			ob.skipAwarded = true
		end
		-- Clear the audit flag so we don't keep re-awarding
		pcall(function()
			AUDIT_STORE:SetAsync(key, { pendingSkip = false, skipAt = record.skipAt })
		end)
		-- Optionally, reset their onboarding for fresh run if you want:
		if ob.state ~= "Completed" then
			ob.state = "NotStarted"
			ob.steps = {}
			ob.completedAt = nil
			-- Don't touch completionAwarded/skipAwarded—they are historical
		end
	end

	-- 2) If already completed from a past run, ensure they get the completion badge
	if ob.state == "Completed" then
		if not ob.completionAwarded then
			if not safeUserHasBadgeAsync(player.UserId, ONBOARDING_COMPLETED_BADGE_ID) then
				safeAwardBadge(player.UserId, ONBOARDING_COMPLETED_BADGE_ID)
			end
			ob.completionAwarded = true
		end
		return -- nothing more to do
	end

	-- 3) Otherwise, we transition to InProgress if not started yet.
	if ob.state == "NotStarted" then
		ob.state = "InProgress"
	end

	-- (Optional) If you want this to immediately prompt the client:
	-- fireClientState(player, "CityNaming")
end

-- Use this NOW while you're not gating with StartIfNeeded.
-- It simply tells the client to show the city-naming prompt.
function OnboardingService.KickoffCityNaming(player: Player)
	-- No profile dependency; this just nudges the client UX.
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

	if not ob.completionAwarded then
		if not safeUserHasBadgeAsync(player.UserId, ONBOARDING_COMPLETED_BADGE_ID) then
			safeAwardBadge(player.UserId, ONBOARDING_COMPLETED_BADGE_ID)
		end
		ob.completionAwarded = true
	end
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
	-- Notify the client which step the server wants to show
	fireClientState(player, stepName, payload)
end

-- Call this EXACTLY when the player presses "Delete Save" WHILE onboarding is InProgress.
-- It writes to the audit store that is not cleared by your wipe.
function OnboardingService.RecordDeletionDuringOnboarding(userId: number)
	local key = ("onboarding_audit:%d"):format(userId)
	local now = os.time()
	pcall(function()
		local current = AUDIT_STORE:GetAsync(key) or {}
		current.pendingSkip = true
		current.skipAt = now
		AUDIT_STORE:SetAsync(key, current)
	end)
end

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

function OnboardingService.RecordGuardProgress(player: Player, seq: string, idx: number, total: number?)
	local profile = getProfile(player); if not profile then return end
	local ob = ensureOnboardingBlob(profile)
	ob.progress = ob.progress or { sequences = {} }
	local rec = ob.progress.sequences[seq] or {}
	rec.lastIndex = idx
	if type(total) == "number" and total > 0 then rec.total = total end
	ob.progress.sequences[seq] = rec
end

function OnboardingService.GetGuardProgress(player: Player, seq: string): (number?, number?)
	local profile = getProfile(player); if not profile then return nil end
	local ob = ensureOnboardingBlob(profile)
	local rec = ob.progress and ob.progress.sequences and ob.progress.sequences[seq]
	if not rec then return nil end
	return rec.lastIndex, rec.total
end

function OnboardingService.HasStep(player: Player, stepId: string): boolean
	local profile = getProfile(player); if not profile then return false end
	local ob = ensureOnboardingBlob(profile)
	return ob.steps and ob.steps[stepId] == true
end

return OnboardingService