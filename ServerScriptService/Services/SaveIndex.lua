local DataStoreService = game:GetService("DataStoreService")
local SavePolicy = require(script.Parent.Parent.Config.SavePolicy)

local SaveIndex = {}

local BUDGET_TIMEOUT_SEC = 8
local BUDGET_POLL_SEC = 0.2

local function _ds()
	return DataStoreService:GetDataStore(SavePolicy.INDEX_STORE)
end

local function keyFor(userId)
	return ("index:%s"):format(tostring(userId))
end

local function waitForBudget(requestType: Enum.DataStoreRequestType, minBudget: number?, timeoutSec: number?)
	minBudget = math.max(1, tonumber(minBudget) or 1)
	local deadline = os.clock() + (timeoutSec or BUDGET_TIMEOUT_SEC)
	repeat
		local ok, budget = pcall(DataStoreService.GetRequestBudgetForRequestType, DataStoreService, requestType)
		if ok and budget >= minBudget then
			return true
		end
		task.wait(BUDGET_POLL_SEC)
	until os.clock() >= deadline
	return false
end

local function callWithBudget(requestType: Enum.DataStoreRequestType, label: string, fn: () -> any)
	if not waitForBudget(requestType, 1, BUDGET_TIMEOUT_SEC) then
		warn(("[SaveIndex] Budget low for %s; request may be queued"):format(label))
	end
	local ok, result = pcall(fn)
	if not ok then
		warn(("[SaveIndex] %s failed: %s"):format(label, tostring(result)))
		return nil, false, result
	end
	return result, true
end

function SaveIndex.read(userId)
	local store = _ds()
	local key = keyFor(userId)
	local val, ok = callWithBudget(
		Enum.DataStoreRequestType.GetAsync,
		("GetAsync:%s"):format(key),
		function()
			return store:GetAsync(key)
		end
	)
	if ok and val then
		return val
	end
	return { userId = tostring(userId), slots = {}, updatedAt = os.time() }
end

function SaveIndex.write(userId, index)
	if SavePolicy.APPLY_CHANGES ~= true then
		return true
	end
	local store = _ds()
	local key = keyFor(userId)
	index.updatedAt = os.time()
	local _, ok, err = callWithBudget(
		Enum.DataStoreRequestType.SetIncrementAsync,
		("SetAsync:%s"):format(key),
		function()
			return store:SetAsync(key, index)
		end
	)
	return ok, err
end

return SaveIndex
