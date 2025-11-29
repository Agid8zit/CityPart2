local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local SavePolicy = require(script.Parent.Parent.Config.SavePolicy)
local SaveKeyNames = require(script.Parent.Parent.Services.SaveKeyNames)
local SaveEnvelope = require(game.ReplicatedStorage.Systems.SaveEnvelope)

-- This tool is expensive (lists every key + GetAsync). Only run when explicitly enabled.
if not SavePolicy.RUN_AUDIT_ON_BOOT then
	warn("[AUDIT] SaveAuditor skipped: RUN_AUDIT_ON_BOOT=false")
	return
end

-- Extra safety: never hammer production servers automatically.
if not RunService:IsStudio() then
	warn("[AUDIT] SaveAuditor skipped outside Studio")
	return
end

local function approxSize(value)
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(value)
	end)
	if not ok or not encoded then
		return -1
	end
	return #encoded
end

local function listAllKeys(storeName, onKey)
	local ds = DataStoreService:GetDataStore(storeName)
	local ok, pages = pcall(function()
		return ds:ListKeysAsync(nil, SavePolicy.LIST_PAGE_SIZE)
	end)
	if not ok or not pages then
		warn("[AUDIT] ListKeysAsync failed for", storeName, pages)
		return
	end
	while true do
		local pageOk, current = pcall(function()
			return pages:GetCurrentPage()
		end)
		if pageOk and current then
			for _, info in ipairs(current) do
				onKey(ds, info.KeyName)
			end
		end
		if pages.IsFinished then
			break
		end
		local advOk = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
		if not advOk then
			break
		end
		task.wait(SavePolicy.YIELD_BETWEEN_PAGES)
	end
end

local function warnIfOverBudget(storeName, totalBytes, uniqueUsers)
	local capBytes = (100 + uniqueUsers) * 1024 * 1024
	local usageMb = totalBytes / (1024 * 1024)
	local capMb = capBytes / (1024 * 1024)
	if capBytes <= 0 then
		return
	end
	local fraction = usageMb / capMb
	if fraction >= SavePolicy.STORAGE_BUDGET_WARN_FRACTION then
		print(('[AUDIT][WARN] %s using %.2f MB of %.2f MB budget (users=%d, %.0f%%)')
			:format(storeName, usageMb, capMb, uniqueUsers, fraction * 100))
	end
end

local function auditStore(storeName)
	local totals = { keys = 0, bytes = 0 }
	local counts = { primary = 0, backup = 0, other = 0 }
	local offenders = {}
	local uniqueUsers = {}

	print(('[AUDIT] Scanning %s'):format(storeName))
	listAllKeys(storeName, function(ds, key)
		totals.keys += 1
		local ok, value = pcall(function()
			return ds:GetAsync(key)
		end)
		if not ok then
			warn('[AUDIT] GetAsync failed for', storeName, key)
			return
		end
		local sz = approxSize(value)
		if sz > 0 then
			totals.bytes += sz
		end
		local parsed = SaveKeyNames.parse(key)
		if parsed then
			uniqueUsers[parsed.userId] = true
			if parsed.kind == 'primary' then
				counts.primary += 1
			else
				counts.backup += 1
			end
			local env = value
			if env and env._envelope and env.data then
				local roads = env.data.savefiles and env.data.savefiles['1'] and env.data.savefiles['1'].cityStorage and env.data.savefiles['1'].cityStorage.roadsB64
				local zones = env.data.savefiles and env.data.savefiles['1'] and env.data.savefiles['1'].cityStorage and env.data.savefiles['1'].cityStorage.zonesB64
				if (roads and #roads > SavePolicy.LIMITS.ROADS_B64_MAX)
					or (zones and #zones > SavePolicy.LIMITS.ZONES_B64_MAX)
					or (sz > SavePolicy.LIMITS.PER_SAVE_BYTES) then
					table.insert(offenders, { key = key, size = sz, hash = env._envelope.hash })
				end
			else
				counts.other += 1
			end
		else
			counts.other += 1
		end
		if (totals.keys % SavePolicy.GC_BATCH_SIZE) == 0 then
			task.wait(SavePolicy.YIELD_BETWEEN_DELETES)
		end
	end)

	local uniqueCount = 0
	for _ in pairs(uniqueUsers) do
		uniqueCount += 1
	end

	print(('[AUDIT] %s -> keys=%d, approxMiB=%.2f, primary=%d, backup=%d, other=%d, users=%d')
		:format(storeName, totals.keys, totals.bytes / (1024 * 1024), counts.primary, counts.backup, counts.other, uniqueCount))

	warnIfOverBudget(storeName, totals.bytes, uniqueCount)

	table.sort(offenders, function(a, b)
		return a.size > b.size
	end)
	for i = 1, math.min(#offenders, 10) do
		local o = offenders[i]
		print(('[AUDIT][TOP] %s size=%d hash=%s'):format(o.key, o.size, o.hash))
	end
end

print('[AUDIT] ===== BEGIN ===== (Dry-run, no writes)')
for _, name in ipairs(SavePolicy.PLAYER_DS_ALL) do
	auditStore(name)
end
for _, name in ipairs(SavePolicy.OTHER_DS) do
	auditStore(name)
end
print('[AUDIT] ===== END =====')
