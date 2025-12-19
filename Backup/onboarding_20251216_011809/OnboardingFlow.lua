local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Events   = ReplicatedStorage:WaitForChild("Events")
local RE       = Events:WaitForChild("RemoteEvents")
local BEFolder = Events:WaitForChild("BindableEvents")

local BE_GridGuard   = BEFolder:WaitForChild("OBGridGuard")
local BE_GridGuardFB = BEFolder:WaitForChild("OBGuardFeedback")

local BF_CheckItemAllowed = BEFolder:WaitForChild("OBCheckItemAllowed")
local StepCompleted       = RE:WaitForChild("OnboardingStepCompleted")

-- Sequence label used server-side for persistence
local SEQ_NAME = "barrage1"

-- =============================================================================
-- Debug helpers
-- =============================================================================

local function fmtBool(v) return v and "true" or "false" end
local function obf(fmt, ...)
	if select("#", ...) > 0 then
		print("[OB_FLOW] " .. string.format(fmt, ...))
	else
		print("[OB_FLOW] " .. tostring(fmt))
	end
end

local function safeToString(v)
	local ok, s = pcall(function() return tostring(v) end)
	return ok and s or "<tostring-failed>"
end

local function stepBrief(step)
	if not step then return "<nil-step>" end
	local item = safeToString(step.item)
	local mode = safeToString(step.mode)
	local kind = safeToString(step.kind)
	local from = (step.from and ("("..safeToString(step.from.x)..","..safeToString(step.from.z)..")")) or "-"
	local to   = (step.to   and ("("..safeToString(step.to.x)..","..safeToString(step.to.z)..")"))   or "-"
	local exact= (step.requireExactEnd == false) and "loose" or "exact"
	return string.format("item=%s mode=%s kind=%s from=%s to=%s %s", item, mode, kind, from, to, exact)
end

-- =============================================================================
-- Module state
-- =============================================================================

local OnboardingFlow = {}

type Step = {
	item: any?,
	mode: any?,
	kind: "line"|"rect"|"point"|string?,
	from: {x:number, z:number}?,
	to:   {x:number, z:number}?,
	requireExactEnd: boolean?,
}

local stepList: {Step} = {}
local stepIdx: number  = 0
local expectedItemID: string? = nil
local running: boolean = false

-- Prefer concrete tool/mode id (e.g., "DirtRoad") over abstract item ("Road")
local function _expectedFromStep(step: Step?): string?
	if not step then return nil end
	local v = step.mode or step.item
	if v == nil then return nil end
	return tostring(v)
end

BF_CheckItemAllowed.OnInvoke = function(itemID: string)
	local sItem = tostring(itemID)
	if not running or not expectedItemID or expectedItemID == "" then
		obf("BF_CheckItemAllowed(%s) -> allowed=true (flow not running or no expected)", sItem)
		return { allowed = true }
	end
	local allowed = (sItem == expectedItemID)
	if allowed then
		obf("BF_CheckItemAllowed(%s) -> allowed=true (expected=%s)", sItem, expectedItemID)
		return { allowed = true }
	else
		local msg = ("Use %s for this step."):format(expectedItemID)
		obf("BF_CheckItemAllowed(%s) -> allowed=false (expected=%s)", sItem, expectedItemID)
		return { allowed = false, msg = msg }
	end
end

local function _emitGuard(how: "start"|"advance"|"stop", step: Step?)
	if how ~= "stop" then
		obf("Emit %s -> %s", how, stepBrief(step))
	else
		obf("Emit stop")
	end

	if how == "stop" then
		BE_GridGuard:Fire("stop")
		return
	end

	local spec = {
		item = step and step.item,
		mode = step and step.mode,
		kind = step and step.kind,
		from = step and step.from,
		to   = step and step.to,
		requireExactEnd = step and (step.requireExactEnd ~= false) or true,
	}
	BE_GridGuard:Fire(how, spec)
end

local function _advanceInternal()
	if not running then
		obf("advance() called but running=false -> ignored (idx=%d len=%d)", stepIdx, #stepList)
		return
	end

	stepIdx += 1
	local step: Step? = stepList[stepIdx]

	if not step then
		obf("advance(): no step at idx=%d (len=%d) -> STOP + OnboardingFinished", stepIdx, #stepList)
		expectedItemID = nil
		running = false
		_emitGuard("stop", nil)
		pcall(function() StepCompleted:FireServer("OnboardingFinished") end)
		return
	end

	expectedItemID = _expectedFromStep(step)

	if stepIdx == 1 then
		_emitGuard("start", step)
	else
		_emitGuard("advance", step)
	end
end

-- Start (or resume) a sequence. If resumeAt is provided (1-based),
-- we seed the internal index so the next advance lands on resumeAt.
function OnboardingFlow.StartSequence(steps: {Step}, resumeAt: number?)
	if typeof(steps) ~= "table" then
		obf("StartSequence called with invalid steps (%s) -> ignoring", typeof(steps))
		return
	end

	stepList = steps

	-- Seed to the last-completed index so _advanceInternal() lands on resumeAt.
	local seedIdx = 0
	if typeof(resumeAt) == "number" then
		local n = math.clamp(math.floor(resumeAt), 1, #stepList)
		seedIdx = n - 1
	end
	stepIdx  = seedIdx
	running  = (#stepList > 0)

	obf("StartSequence len=%d resumeAt=%s -> running=%s (seed idx=%d)",
		#stepList, tostring(resumeAt), fmtBool(running), stepIdx)

	if running then
		_advanceInternal()
	else
		expectedItemID = nil
		_emitGuard("stop", nil)
	end
end

function OnboardingFlow.StopSequence()
	obf("StopSequence (running=%s idx=%d len=%d)", fmtBool(running), stepIdx, #stepList)
	expectedItemID = nil
	stepList = {}
	stepIdx  = 0
	if running then
		_emitGuard("stop", nil)
	end
	running = false
end

function OnboardingFlow.GetState()
	local st = {
		index    = stepIdx,
		total    = #stepList,
		expected = running and expectedItemID or nil,
		current  = running and stepList[stepIdx] or nil,
		running  = running,
	}
	obf("GetState -> idx=%d/%d running=%s expected=%s",
		st.index, st.total, fmtBool(st.running), tostring(st.expected))
	return st
end

-- Feedback from GridVisualizer (GV) to advance / re-guard
BE_GridGuardFB.Event:Connect(function(tag: string, info: any?)
	local infoItem = nil
	if info and typeof(info) == "table" then
		-- Prefer concrete tool id reported by GV
		infoItem = tostring(info.mode or info.item or "")
	end

	obf("GuardFB tag=%s running=%s idx=%d len=%d infoItem=%s expected=%s",
		tostring(tag), fmtBool(running), stepIdx, #stepList, tostring(infoItem), tostring(expectedItemID))

	if not running then
		obf("GuardFB ignored (flow not running)")
		return
	end

	if infoItem and expectedItemID and infoItem ~= "" and infoItem ~= expectedItemID then
		obf("GuardFB ignored (infoItem=%s does not match expected=%s)", infoItem, expectedItemID)
		return
	end

	if tag == "done" then
		-- Persist Barrage 1 progress (account-wide) before advancing
		local justFinished = stepIdx
		if justFinished >= 1 then
			pcall(function()
				StepCompleted:FireServer("GuardStepDone", {
					seq   = SEQ_NAME,
					index = justFinished,
					total = #stepList,
				})
			end)
		end
		_advanceInternal()

	elseif tag == "canceled" then
		local cur = stepList[math.max(stepIdx, 1)]
		if cur then
			obf("GuardFB canceled -> re-guard current: %s", stepBrief(cur))
			expectedItemID = _expectedFromStep(cur)
			_emitGuard("start", cur)
		else
			obf("GuardFB canceled but no current step -> ignoring")
		end

	elseif tag == "cleared" then
		local targetIdx = stepIdx
		if infoItem and infoItem ~= "" then
			for i = 1, #stepList do
				if _expectedFromStep(stepList[i]) == infoItem then
					targetIdx = i
					break
				end
			end
		else
			targetIdx = math.max(stepIdx - 1, 1)
		end

		obf("GuardFB cleared -> rollback to step %d (from %d)", targetIdx, stepIdx)
		stepIdx = targetIdx - 1
		_advanceInternal()

	else
		obf("GuardFB unknown tag=%s (ignored)", tostring(tag))
	end
end)

return OnboardingFlow
