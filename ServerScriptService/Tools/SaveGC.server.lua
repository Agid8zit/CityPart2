local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local SavePolicy = require(script.Parent.Parent.Config.SavePolicy)
local SaveIndex = require(script.Parent.Parent.Services.SaveIndex)
local SaveKeyNames = require(script.Parent.Parent.Services.SaveKeyNames)

-- This tool is expensive (lists every key) and can be destructive (RemoveAsync).
-- Only run when explicitly enabled.
if not SavePolicy.RUN_GC_ON_BOOT then
	warn("[RETENTION] SaveGC skipped: RUN_GC_ON_BOOT=false")
	return
end

-- Extra safety: never hammer production servers automatically.
if not RunService:IsStudio() and not SavePolicy.ALLOW_GC_OUTSIDE_STUDIO then
	warn("[RETENTION] SaveGC skipped outside Studio (set ALLOW_GC_OUTSIDE_STUDIO=true to override)")
	return
end

local function withLock(name, ttlSeconds, fn)
	-- Use a DataStore lock so only one server runs GC at a time.
	local lockStoreName = SavePolicy.GC_LOCK_STORE or "SaveGC_Lock_v1"
	local lockStore = DataStoreService:GetDataStore(lockStoreName)
	local token = HttpService:GenerateGUID(false)
	local now = os.time()
	local key = "lock:" .. tostring(name)

	local okLock, lockValOrErr = pcall(function()
		return lockStore:UpdateAsync(key, function(old)
			if type(old) == "table" and type(old.expiresAt) == "number" and old.expiresAt > now then
				return old
			end
			return { token = token, expiresAt = now + ttlSeconds }
		end)
	end)

	if not okLock then
		warn(("[RETENTION] GC lock acquisition failed (%s): %s"):format(tostring(name), tostring(lockValOrErr)))
		return false, "lock_error"
	end

	if type(lockValOrErr) ~= "table" or lockValOrErr.token ~= token then
		warn(("[RETENTION] GC lock held (%s); skipping run"):format(tostring(name)))
		return false, "locked"
	end

	local ok, err = pcall(fn)

	-- Best-effort release (still protected by token); TTL remains a safety net if this fails.
	pcall(function()
		lockStore:UpdateAsync(key, function(old)
			if type(old) == "table" and old.token == token then
				return nil
			end
			return old
		end)
	end)

	return ok, err
end

local function _sleepBackoff(attempt: number)
	local base = tonumber(SavePolicy.GC_LIST_RETRY_BASE_DELAY_SEC) or 0.5
	local maxDelay = tonumber(SavePolicy.GC_LIST_RETRY_MAX_DELAY_SEC) or 8
	local waitSec = math.min(maxDelay, base * (2 ^ math.max(0, attempt - 1)))
	task.wait(waitSec)
end

local function listKeysWithRetry(ds, storeName: string)
	local maxAttempts = math.clamp(math.floor(tonumber(SavePolicy.GC_LIST_RETRIES) or 10), 1, 25)
	for attempt = 1, maxAttempts do
		local ok, pagesOrErr = pcall(function()
			return ds:ListKeysAsync(nil, SavePolicy.LIST_PAGE_SIZE, nil, true)
		end)
		if ok and pagesOrErr then
			return pagesOrErr
		end
		warn(("[RETENTION] ListKeysAsync failed for %s (attempt %d/%d): %s")
			:format(storeName, attempt, maxAttempts, tostring(pagesOrErr)))
		_sleepBackoff(attempt)
	end
	return nil
end

local function advancePageWithRetry(pages, storeName: string): boolean
	local maxAttempts = math.clamp(math.floor(tonumber(SavePolicy.GC_ADVANCE_RETRIES) or 10), 1, 25)
	for attempt = 1, maxAttempts do
		local ok, err = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
		if ok then
			return true
		end
		warn(("[RETENTION] AdvanceToNextPageAsync failed for %s (attempt %d/%d): %s")
			:format(storeName, attempt, maxAttempts, tostring(err)))
		_sleepBackoff(attempt)
	end
	return false
end

local function collectStore(storeName, doDeletes: boolean)
	local ds = DataStoreService:GetDataStore(storeName)
	local keysByUser = {}

	local pages = listKeysWithRetry(ds, storeName)
	if not pages then
		warn('[RETENTION] Cannot list keys for', storeName)
		return
	end

	while true do
		local pageOk, page = pcall(function()
			return pages:GetCurrentPage()
		end)
		if pageOk and page then
			for _, info in ipairs(page) do
				local parsed = SaveKeyNames.parse(info.KeyName)
				if parsed then
					local u = parsed.userId
					local s = parsed.slot
					keysByUser[u] = keysByUser[u] or {}
					local bucket = keysByUser[u][s]
					if not bucket then
						bucket = { primaries = {}, backups = {} }
						keysByUser[u][s] = bucket
					end
					if parsed.kind == 'primary' then
						table.insert(bucket.primaries, info.KeyName)
					else
						table.insert(bucket.backups, info.KeyName)
					end
				end
			end
		end
		if pages.IsFinished then
			break
		end
		if not advancePageWithRetry(pages, storeName) then
			break
		end
		task.wait(SavePolicy.YIELD_BETWEEN_PAGES)
	end

	local planned = {}
	local now = os.time()

	for userId, slots in pairs(keysByUser) do
		for slot, bucket in pairs(slots) do
			table.sort(bucket.primaries)
			table.sort(bucket.backups)

			for i = 1, math.max(0, #bucket.primaries - 1) do
				table.insert(planned, { store = storeName, key = bucket.primaries[i], reason = 'extra-primary' })
			end

			local extra = #bucket.backups - SavePolicy.MAX_BACKUPS_PER_SLOT
			for i = 1, math.max(0, extra) do
				table.insert(planned, { store = storeName, key = bucket.backups[i], reason = 'exceeds-backup-count' })
			end

			for _, key in ipairs(bucket.backups) do
				local parts = {}
				for token in string.gmatch(key, '([^:]+)') do
					table.insert(parts, token)
				end
				local iso = parts[5]
				if iso then
					local y, mo, d, h, mi, se = string.match(iso, "(%d+)%-(%d+)%-(%d+)T(%d+)%-([%d]+)%-([%d]+)Z")
					if y then
						local when = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = tonumber(se) })
						if (now - when) > SavePolicy.MAX_BACKUP_AGE_SECONDS then
							table.insert(planned, { store = storeName, key = key, reason = 'exceeds-backup-age' })
						end
					end
				end
			end

			local idx = SaveIndex.read(userId)
			idx.slots = idx.slots or {}
			idx.slots[slot] = idx.slots[slot] or { primary = nil, backups = {} }
			idx.slots[slot].primary = bucket.primaries[#bucket.primaries]
			idx.slots[slot].backups = {}
			local start = math.max(1, #bucket.backups - SavePolicy.MAX_BACKUPS_PER_SLOT + 1)
			for i = start, #bucket.backups do
				table.insert(idx.slots[slot].backups, bucket.backups[i])
			end
			if doDeletes then
				SaveIndex.write(userId, idx)
			end
		end
	end

	print(('[RETENTION] %s planned deletions=%d'):format(storeName, #planned))

	if not doDeletes then
		for i = 1, math.min(#planned, 20) do
			local p = planned[i]
			print(('[RETENTION][DRY-RUN] would delete %s %s (%s)'):format(p.store, p.key, p.reason))
		end
		return
	end

	local deleted = 0
	for _, p in ipairs(planned) do
		local okRemove, err = pcall(function()
			DataStoreService:GetDataStore(p.store):RemoveAsync(p.key)
		end)
		if okRemove then
			deleted += 1
			if (deleted % SavePolicy.GC_BATCH_SIZE) == 0 then
				task.wait(SavePolicy.YIELD_BETWEEN_DELETES)
			end
		else
			warn('[RETENTION][ERROR] delete failed', p.store, p.key, err)
		end
	end
	print(('[RETENTION] %s deletions applied=%d'):format(storeName, deleted))
end

local doDeletes = (SavePolicy.APPLY_CHANGES == true) and (SavePolicy.GC_APPLY_CHANGES == true)

withLock("global", tonumber(SavePolicy.GC_LOCK_TTL_SECONDS) or 3600, function()
	if not doDeletes then
		print("[RETENTION] Running in dry-run mode; no deletions or index writes will occur. (set GC_APPLY_CHANGES=true to enable)")
	end
	for _, name in ipairs(SavePolicy.PLAYER_DS_ALL) do
		collectStore(name, doDeletes)
	end
end)
