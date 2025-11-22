local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")

local SavePolicy = require(script.Parent.Parent.Config.SavePolicy)
local SaveIndex = require(script.Parent.Parent.Services.SaveIndex)
local SaveKeyNames = require(script.Parent.Parent.Services.SaveKeyNames)

local function withLock(name, ttlSeconds, fn)
	local queue = MemoryStoreService:GetQueue("save-gc:" .. name)
	local token = tostring(math.random())
	local okPush = pcall(function()
		queue:AddAsync(token, 1, ttlSeconds)
	end)
	if not okPush then
		return false, 'lock-failed'
	end
	local ok, err = pcall(fn)
	return ok, err
end

local function collectStore(storeName)
	local ds = DataStoreService:GetDataStore(storeName)
	local keysByUser = {}

	local ok, pages = pcall(function()
		return ds:ListKeysAsync(nil, SavePolicy.LIST_PAGE_SIZE, nil, true)
	end)
	if not ok or not pages then
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
		local advOk = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
		if not advOk then
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
			SaveIndex.write(userId, idx)
		end
	end

	print(('[RETENTION] %s planned deletions=%d'):format(storeName, #planned))

	if SavePolicy.APPLY_CHANGES ~= true then
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

if SavePolicy.APPLY_CHANGES then
	withLock('global', 300, function()
		for _, name in ipairs(SavePolicy.PLAYER_DS_ALL) do
			collectStore(name)
		end
	end)
else
	print('[RETENTION] Running in dry-run mode; no deletions will occur.')
	for _, name in ipairs(SavePolicy.PLAYER_DS_ALL) do
		collectStore(name)
	end
end
