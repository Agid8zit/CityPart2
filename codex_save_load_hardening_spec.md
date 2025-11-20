# CODEx Task Blob — Save/Load Hardening + Retention (Dry‑Run Default)

**Purpose:** Provide a non‑destructive, drop‑in set of modules + instructions that let a code assistant (Codex) audit your current saving/loading, recommend minimal diffs, and — when a single flag is flipped — enforce safe retention (limited backups, dedupe, orphan cleanup) **without changing game semantics**.

---

## Context (authoritative)

- Active DataStores right now are limited to the ones still in use:  
  `PlayerData_PublicTest2` (Studio runs), `PlayerData_Release1` (live servers), `PlayerSesionLock`, `OnboardingAudit_v1`, and `SavedReceipts`.  
  All other historical stores (e.g. `PlayerCities`, `UnlockDataStore`, `ZoneDataV1`, numbered PlayerData variants) are legacy and currently being scrubbed.
- Player payloads have a top‑level **Onboarding** (per‑player) and per‑slot **savefiles** with compressed strings like `roadsB64`, `zonesB64`. We **must keep** the B64 blobs. We want: safe retention (few backups), deduplicated writes, and reliable deletion of stale/orphaned keys.
- This task must **not change gameplay behavior** or the client‑visible schema. Changes are additive wrappers, guards, background maintenance. **Dry‑run is default**.

---

## Goals

1. **Dry‑run auditor** (no writes): enumerate keys, sample/parse values, measure sizes, detect duplicates, stale backups, or orphans, and print a structured report.
2. **Retention policy** (behind a single `APPLY_CHANGES` flag): for each player slot, keep at most **N backups** and remove backups older than **T**; skip if dry‑run.
3. **Write dedupe**: skip saves that do not change data (hash‑based), and **rate‑limit** commits (e.g., min interval).
4. **Indexing**: maintain a lightweight **per‑user index** of primary + backups to enable fast cleanup and orphan detection. (Do not break existing loads; the index supplements current logic.)
5. **Key naming hygiene**: predictable keys for primaries and backups; keep existing names working.
6. **Safety**: single-server GC via MemoryStore lock; defensive throttling; `pcall` around all I/O.
7. **Churn-aware commits**: separate/stage high-churn counters (money, tickets, etc.) and respect a minimum commit interval so only consolidated snapshots hit the DataStores; low-churn state can still flush immediately.

---

## Acceptance Criteria

- With `APPLY_CHANGES = false` (default), **no DataStore mutations** happen. Auditor runs and prints a compact summary per store + a per‑user/slot table of what would be deleted.
- With `APPLY_CHANGES = true`, the GC removes only: backups beyond the configured **count** and **age**, and **orphaned** keys not referenced in the per‑user index—leaving the most recent valid primary/backup intact.
- Saves that are byte‑identical to the last committed payload are **skipped** (no duplicate backups).
- All new writes are wrapped in an **envelope** that logs metadata (hash, approx size, timestamps) without altering the inner payload contract.
- Clear structured logs: `[AUDIT]`, `[RETENTION]`, `[DEDUP]`, `[GC]`, `[ERROR]`.
- No change to client‑visible fields or semantics.

---

## Files / Modules to add (non‑breaking)

> Place these paths verbatim. The code below is scaffolding + concrete helpers; Codex should expand where indicated.

### 1) `ReplicatedStorage/Systems/SaveEnvelope.lua` — minimal metadata wrapper
```lua
-- SaveEnvelope.lua
-- Non-breaking wrapper that attaches metadata to any payload without altering game semantics.
local HttpService = game:GetService("HttpService")

local SaveEnvelope = {}

-- Very simple 32-bit rolling hash (fast, not cryptographic) to dedupe identical saves.
local function fastHash(str)
	local a, b = 1, 0
	for i = 1, #str do
		a = (a + string.byte(str, i)) % 65521; b = (b + a) % 65521
	end
	return string.format("%08x%08x", a, b)
end

function SaveEnvelope.wrap(slotId, payloadTable, schemaVersion: number)
	local encoded = HttpService:JSONEncode(payloadTable)
	local approxBytes = #encoded
	return {
		_envelope = {
			version = 1, -- envelope version
			schema = schemaVersion or (payloadTable.Version or 1),
			slot = tostring(slotId),
			createdAt = os.time(),
			updatedAt = os.time(),
			hash = fastHash(encoded),
			approxBytes = approxBytes,
		},
		data = payloadTable, -- original, untouched payload
	}
end

function SaveEnvelope.touch(enveloped)
	if enveloped and enveloped._envelope then
		enveloped._envelope.updatedAt = os.time()
	end
	return enveloped
end

function SaveEnvelope.hashOf(envelopedOrTable)
	local HttpService = game:GetService("HttpService")
	if envelopedOrTable and envelopedOrTable._envelope and envelopedOrTable.data then
		return envelopedOrTable._envelope.hash
	end
	local encoded = HttpService:JSONEncode(envelopedOrTable)
	return fastHash(encoded)
end

return SaveEnvelope
```

### 2) `ServerScriptService/Config/SavePolicy.lua` — single source of truth for retention & safety
```lua
-- SavePolicy.lua
return {
	-- Non-destructive by default:
	APPLY_CHANGES = false,

	-- Environment selector for base datastore family. Keep your current families but prefer one canonical per env.
	ENV = "Release", -- "Studio" | "Release"

	-- Map the canonical player DS for each env (only the active ones remain).
	PLAYER_DS_BY_ENV = {
		Studio = "PlayerData_PublicTest2",
		Release = "PlayerData_Release1",
	},

	-- Limited list since legacy families are being purged.
	PLAYER_DS_ALL = {
		"PlayerData_PublicTest2",
		"PlayerData_Release1",
	},

	-- Other stores still in play (legacy ones are being scrubbed).
	OTHER_DS = {
		"OnboardingAudit_v1","PlayerSesionLock","SavedReceipts",
	},

	-- Retention:
	MAX_BACKUPS_PER_SLOT = 3,            -- keep newest N backups
	MAX_BACKUP_AGE_SECONDS = 14*24*3600, -- also drop backups older than this
	MIN_COMMIT_INTERVAL_SECONDS = 120,   -- skip saves more frequent than this
	DEDUPE_BY_HASH = true,               -- skip if hash unchanged

	-- Size guards (approximate; keep generous):
	LIMITS = {
		PER_SAVE_BYTES = 250 * 1024,      -- total envelope+payload soft ceiling
		ROADS_B64_MAX = 200 * 1024,
		ZONES_B64_MAX = 200 * 1024,
	},

	-- Index & reporting stores (additive, won’t break existing loads):
	INDEX_STORE = "PlayerIndex_v1",
	REPORT_STORE = "AuditReports_v1",

	-- Pagination & throttling:
	LIST_PAGE_SIZE = 100,
	GC_BATCH_SIZE = 100,
	YIELD_BETWEEN_DELETES = 0.05,
	YIELD_BETWEEN_PAGES = 0.25,

	-- Slot limits:
	MAX_SLOTS_PER_PLAYER = 3,
}
```

### 3) `ServerScriptService/Services/SaveIndex.lua` — per‑user index for primaries + backups
```lua
-- SaveIndex.lua
-- Tracks, per user, the primary key and backup keys per slot. Non-breaking helper for GC & audits.
local DataStoreService = game:GetService("DataStoreService")
local SavePolicy = require(script.Parent.Parent.Config.SavePolicy)

local SaveIndex = {}

local function _ds()
	return DataStoreService:GetDataStore(SavePolicy.INDEX_STORE)
end

-- Shape:
-- index = {
--   userId = "123",
--   slots = {
--     ["1"] = { primary = "p:123:s:1:v1", backups = {"b:123:s:1:2025-11-19T12-01-02Z:abc", ...} },
--     ...
--   },
--   updatedAt = 1700000000
-- }
function SaveIndex.read(userId)
	local store = _ds()
	local key = ("index:%s"):format(tostring(userId))
	local ok, val = pcall(function() return store:GetAsync(key) end)
	if ok and val then return val end
	return { userId = tostring(userId), slots = {}, updatedAt = os.time() }
end

function SaveIndex.write(userId, index)
	if SavePolicy.APPLY_CHANGES ~= true then
		-- Dry-run: do nothing.
		return true
	end
	local store = _ds()
	local key = ("index:%s"):format(tostring(userId))
	index.updatedAt = os.time()
	local ok, err = pcall(function() store:SetAsync(key, index) end)
	return ok, err
end

return SaveIndex
```

### 4) `ServerScriptService/Services/SaveKeyNames.lua` — predictable keys
```lua
-- SaveKeyNames.lua
-- Centralizes key naming so backups/primaries are predictable & easy to GC.
local SaveKeyNames = {}

-- Primary save (one per slot): "p:<userId>:s:<slotId>:v1"
function SaveKeyNames.primary(userId, slotId)
	return ("p:%s:s:%s:v1"):format(tostring(userId), tostring(slotId))
end

-- Backup save (many per slot): "b:<userId>:s:<slotId>:<ISO8601-ish>:<rand>"
function SaveKeyNames.backup(userId, slotId)
	local ts = os.date("!%Y-%m-%dT%H-%M-%SZ")
	local rand = tostring(math.random(100000,999999))
	return ("b:%s:s:%s:%s:%s"):format(tostring(userId), tostring(slotId), ts, rand)
end

-- Optional: derive user/slot from a key for auditing.
function SaveKeyNames.parse(key)
	-- p:123:s:1:v1 or b:123:s:1:2025-...:abc
	local t = {}
	for token in string.gmatch(key, "([^:]+)") do table.insert(t, token) end
	if t[1] == "p" then return {kind="primary", userId=t[2], slot=t[4]} end
	if t[1] == "b" then return {kind="backup",  userId=t[2], slot=t[4]} end
	return nil
end

return SaveKeyNames
```

### 5) `ServerScriptService/Tools/SaveAuditor.server.lua` — **dry‑run** audit (no writes)
```lua
-- SaveAuditor.server.lua (Dry-run ONLY)
-- Enumerates configured DataStores, samples/reads values, sizes them, and prints a report.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local SavePolicy = require(script.Parent.Parent.Config.SavePolicy)
local SaveKeyNames = require(script.Parent.Parent.Services.SaveKeyNames)
local SaveEnvelope = require(game.ReplicatedStorage.Systems.SaveEnvelope)

local function listAllKeys(storeName: string, pageSize: number, onKey)
	local ds = DataStoreService:GetDataStore(storeName)
	local ok, pagesOrErr = pcall(function()
		return ds:ListKeysAsync(nil, pageSize)
	end)
	if not ok or not pagesOrErr then
		warn("[AUDIT] ListKeysAsync failed for", storeName, pagesOrErr)
		return
	end

	local pages = pagesOrErr
	while true do
		local ok2, current = pcall(function() return pages:GetCurrentPage() end)
		if ok2 and current then
			for _, keyInfo in ipairs(current) do
				local key = keyInfo.KeyName
				onKey(ds, key)
			end
		end
		if pages.IsFinished then break end
		local ok3 = pcall(function() pages:AdvanceToNextPageAsync() end)
		if not ok3 then break end
		task.wait(SavePolicy.YIELD_BETWEEN_PAGES)
	end
end

local function approxSize(value)
	local ok, encoded = pcall(function() return HttpService:JSONEncode(value) end)
	if not ok or not encoded then return -1 end
	return #encoded
end

local totals = {}
local offenders = {} -- large saves/backups
local counts = {}

local function bump(map, key, delta)
	map[key] = (map[key] or 0) + (delta or 1)
end

local function auditStore(storeName: string)
	print(("[AUDIT] Scanning %s"):format(storeName))
	totals[storeName] = {keys=0, bytes=0}
	counts[storeName] = {primary=0, backup=0, other=0}

	listAllKeys(storeName, SavePolicy.LIST_PAGE_SIZE, function(ds, key)
		bump(totals[storeName], "keys", 1)

		local ok, value = pcall(function() return ds:GetAsync(key) end)
		if not ok then
			warn("[AUDIT]", storeName, key, "GetAsync failed")
			return
		end
		local sz = approxSize(value)
		if sz > 0 then bump(totals[storeName], "bytes", sz) end

		local parsed = SaveKeyNames.parse(key)
		if parsed == nil then
			bump(counts[storeName], "other", 1)
		else
			bump(counts[storeName], parsed.kind == "primary" and "primary" or "backup", 1)

			-- If value is enveloped, we can inspect hash and inner blobs:
			local env = value
			local hash = SaveEnvelope.hashOf(env.data and env or value)
			local roads = env.data and env.data.savefiles and env.data.savefiles["1"] and env.data.savefiles["1"].cityStorage and env.data.savefiles["1"].cityStorage.roadsB64
			local zones = env.data and env.data.savefiles and env.data.savefiles["1"] and env.data.savefiles["1"].cityStorage and env.data.savefiles["1"].cityStorage.zonesB64
			if roads and #roads > SavePolicy.LIMITS.ROADS_B64_MAX or zones and #zones > SavePolicy.LIMITS.ZONES_B64_MAX or sz > SavePolicy.LIMITS.PER_SAVE_BYTES then
				table.insert(offenders, {store=storeName, key=key, size=sz, hash=hash})
			end
		end

		if (totals[storeName].keys % SavePolicy.GC_BATCH_SIZE) == 0 then
			task.wait(SavePolicy.YIELD_BETWEEN_DELETES)
		end
	end)

	print(("[AUDIT] %s → keys=%d, approxMiB=%.2f, primary=%d, backup=%d, other=%d")
		:format(
			storeName,
			totals[storeName].keys,
			(totals[storeName].bytes / (1024*1024)),
			counts[storeName].primary, counts[storeName].backup, counts[storeName].other
		))
end

-- ENTRYPOINT
task.spawn(function()
	print("[AUDIT] ===== BEGIN ===== (Dry-run, no writes)")
	for _, name in ipairs(SavePolicy.PLAYER_DS_ALL) do auditStore(name) end
	for _, name in ipairs(SavePolicy.OTHER_DS) do auditStore(name) end
	table.sort(offenders, function(a,b) return a.size > b.size end)
	for i=1, math.min(#offenders, 50) do
		local o = offenders[i]
		print(("[AUDIT][TOP] %s %s size=%d hash=%s"):format(o.store, o.key, o.size, o.hash))
	end
	print("[AUDIT] ===== END =====")
end)
```

### 6) `ServerScriptService/Tools/SaveGC.server.lua` — retention & cleanup (**respects APPLY_CHANGES**)
```lua
-- SaveGC.server.lua
-- Enforces retention (max backups, max age) and removes orphans. Safe by default unless APPLY_CHANGES=true.
local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local SavePolicy = require(script.Parent.Parent.Config.SavePolicy)
local SaveIndex = require(script.Parent.Parent.Services.SaveIndex)
local SaveKeyNames = require(script.Parent.Parent.Services.SaveKeyNames)

local function withGlobalLock(name, ttlSeconds, fn)
	local scope = MemoryStoreService:GetQueue("global-lock:" .. name)
	-- Poor-man's single-runner: try to push+pop a token
	local token = tostring(math.random())
	local okPush = pcall(function() scope:AddAsync(token, 1, ttlSeconds) end)
	if not okPush then return false, "lock-failed" end
	local ok, err = pcall(fn)
	-- we let the lock expire naturally
	return ok, err
end

local function listKeys(storeName, pageSize)
	local ds = DataStoreService:GetDataStore(storeName)
	local results = {}
	local ok, pages = pcall(function() return ds:ListKeysAsync(nil, pageSize) end)
	if not ok or not pages then return results end
	while true do
		local ok2, current = pcall(function() return pages:GetCurrentPage() end)
		if ok2 and current then
			for _, info in ipairs(current) do table.insert(results, info.KeyName) end
		end
		if pages.IsFinished then break end
		local ok3 = pcall(function() pages:AdvanceToNextPageAsync() end); if not ok3 then break end
		task.wait(SavePolicy.YIELD_BETWEEN_PAGES)
	end
	return results
end

local function enforceRetentionOnStore(storeName)
	local ds = DataStoreService:GetDataStore(storeName)
	print("[RETENTION] scanning", storeName)
	local keys = listKeys(storeName, SavePolicy.LIST_PAGE_SIZE)

	-- Group by user/slot using parsed names
	local buckets = {} -- buckets[userId][slot] = {primaries={}, backups={}}
	for _, key in ipairs(keys) do
		local parsed = SaveKeyNames.parse(key)
		if parsed then
			local u = parsed.userId
			local s = parsed.slot
			buckets[u] = buckets[u] or {}
			buckets[u][s] = buckets[u][s] or {primaries={}, backups={}}
			if parsed.kind == "primary" then
				table.insert(buckets[u][s].primaries, key)
			else
				table.insert(buckets[u][s].backups, key)
			end
		end
	end

	-- Evaluate deletions (dry-run first)
	local now = os.time()
	local planned = {}

	for userId, slots in pairs(buckets) do
		for slot, grp in pairs(slots) do
			-- Keep newest primary (if multiple exist, keep lexicographically last by key or fetch updatedAt if enveloped)
			table.sort(grp.primaries) -- simple heuristic
			for i=1, #grp.primaries-1 do
				table.insert(planned, {store=storeName, key=grp.primaries[i], reason="extra-primary"})
			end

			-- Backups: sort newest last (keys contain ISO time), then keep last N and younger than age
			table.sort(grp.backups)
			local toDeleteCount = math.max(0, #grp.backups - SavePolicy.MAX_BACKUPS_PER_SLOT)
			for i=1, #grp.backups - SavePolicy.MAX_BACKUPS_PER_SLOT do
				table.insert(planned, {store=storeName, key=grp.backups[i], reason="exceeds-backup-count"})
			end

			-- Age filter: parse date portion if present.
			for _, key in ipairs(grp.backups) do
				local parts = {}
				for token in string.gmatch(key, "([^:]+)") do table.insert(parts, token) end
				local iso = parts[5] -- b:<uid>:s:<slot>:<iso>:<rand>
				if iso then
					local y,mo,d,h,mi,se = string.match(iso, "(%d+)%-(%d+)%-(%d+)T(%d+)%-([%d]+)%-([%d]+)Z")
					if y then
						local when = os.time({year=tonumber(y), month=tonumber(mo), day=tonumber(d), hour=tonumber(h), min=tonumber(mi), sec=tonumber(se)})
						if (now - when) > SavePolicy.MAX_BACKUP_AGE_SECONDS then
							table.insert(planned, {store=storeName, key=key, reason="exceeds-backup-age"})
						end
					end
				end
			end

			-- Update index (dry-run writes are no-ops inside SaveIndex.write)
			local idx = SaveIndex.read(userId)
			idx.slots[slot] = idx.slots[slot] or {primary=nil, backups={}}
			idx.slots[slot].primary = grp.primaries[#grp.primaries] or nil
			idx.slots[slot].backups = {}
			for i=math.max(1, #grp.backups - SavePolicy.MAX_BACKUPS_PER_SLOT + 1), #grp.backups do
				table.insert(idx.slots[slot].backups, grp.backups[i])
			end
			SaveIndex.write(userId, idx)
		end
	end

	print(("[RETENTION] %s planned deletions: %d"):format(storeName, #planned))
	-- Apply if allowed
	if SavePolicy.APPLY_CHANGES ~= true then
		for i=1, math.min(#planned, 50) do
			local p = planned[i]
			print(("[RETENTION][DRY-RUN] would delete %s %s (%s)"):format(p.store, p.key, p.reason))
		end
		return
	end

	-- Execute deletions
	local deleted = 0
	for _, p in ipairs(planned) do
		local ds = DataStoreService:GetDataStore(p.store)
		local ok, err = pcall(function() ds:RemoveAsync(p.key) end)
		if ok then
			deleted += 1
			if (deleted % SavePolicy.GC_BATCH_SIZE) == 0 then
				task.wait(SavePolicy.YIELD_BETWEEN_DELETES)
			end
		else
			warn("[RETENTION][ERROR] delete failed", p.store, p.key, err)
		end
	end
	print(("[RETENTION] %s deletions applied: %d"):format(storeName, deleted))
end

-- ENTRYPOINT (single-run lock for safety)
task.spawn(function()
	withGlobalLock("save-gc", 300, function()
		for _, name in ipairs(SavePolicy.PLAYER_DS_ALL) do
			enforceRetentionOnStore(name)
		end
	end)
end)
```

### 7) Diff hooks for your existing SaveManager — dedupe + retention‑aware writes (non‑breaking)
```lua
-- Pseudocode/patch for your existing SaveManager where you perform the final Save (SetAsync/UpdateAsync):
local DataStoreService = game:GetService("DataStoreService")
local SavePolicy = require(script.Parent.Config.SavePolicy)
local SaveEnvelope = require(game.ReplicatedStorage.Systems.SaveEnvelope)
local SaveKeyNames = require(script.Parent.Services.SaveKeyNames)
local SaveIndex = require(script.Parent.Services.SaveIndex)
local HttpService = game:GetService("HttpService")

local function commitPlayerSlot(userId, slotId, payloadTable)
	-- 1) Envelope & hash for dedupe:
	local env = SaveEnvelope.wrap(slotId, payloadTable, payloadTable.Version or 1)
	local encoded = HttpService:JSONEncode(env.data)
	local sz = #encoded

	-- 2) Size guards (soft): log but don't fail gameplay
	if sz > SavePolicy.LIMITS.PER_SAVE_BYTES then
		warn("[DEDUP][SIZE] payload exceeds soft limit", userId, slotId, sz)
	end

	-- 3) Read last primary to dedupe (optional fetch)
	local playerStoreName = SavePolicy.PLAYER_DS_BY_ENV[SavePolicy.ENV]
	local store = DataStoreService:GetDataStore(playerStoreName)
	local primaryKey = SaveKeyNames.primary(userId, slotId)

	local lastEnv = nil
	pcall(function() lastEnv = store:GetAsync(primaryKey) end)
	if SavePolicy.DEDUPE_BY_HASH and lastEnv ~= nil then
		local lastHash = SaveEnvelope.hashOf(lastEnv.data and lastEnv or lastEnv)
		if lastHash == env._envelope.hash then
			-- Optional: rate-limit identical writes:
			print(("[DEDUP] Skip unchanged save user=%s slot=%s"):format(userId, slotId))
			return true
		end
	end

	-- 4) Rate limit saves:
	if lastEnv and lastEnv._envelope and lastEnv._envelope.updatedAt then
		local since = os.time() - (lastEnv._envelope.updatedAt or 0)
		if since < SavePolicy.MIN_COMMIT_INTERVAL_SECONDS then
			print(("[DEDUP] Skip due to min interval (%ds) user=%s slot=%s"):format(SavePolicy.MIN_COMMIT_INTERVAL_SECONDS, userId, slotId))
			return true
		end
	end

	-- 5) Create a backup first (crash safety); then update primary.
	local backupKey = SaveKeyNames.backup(userId, slotId)

	-- Respect dry-run: do nothing if APPLY_CHANGES=false
	if SavePolicy.APPLY_CHANGES ~= true then
		print(("[DEDUP][DRY-RUN] would write backup=%s and primary=%s"):format(backupKey, primaryKey))
		return true
	end

	local ok1, err1 = pcall(function() store:SetAsync(backupKey, env) end)
	if not ok1 then warn("[DEDUP][ERROR] backup write failed", backupKey, err1) end

	-- Primary last (the authoritative one)
	env = SaveEnvelope.touch(env)
	local ok2, err2 = pcall(function() store:SetAsync(primaryKey, env) end)
	if not ok2 then warn("[DEDUP][ERROR] primary write failed", primaryKey, err2) end

	-- 6) Update index (best-effort)
	local idx = SaveIndex.read(userId)
	idx.slots[tostring(slotId)] = idx.slots[tostring(slotId)] or {primary=nil, backups={}}
	idx.slots[tostring(slotId)].primary = primaryKey
	-- Append backup to index tail:
	table.insert(idx.slots[tostring(slotId)].backups, backupKey)
	SaveIndex.write(userId, idx)

	return ok2
end
```

---

## Surgical changes Codex should make

- **SaveManager.lua / PlayerDataService.lua** (where the final save occurs):
  - Wrap outgoing payloads via `SaveEnvelope.wrap`.
  - Lookup `primaryKey` via `SaveKeyNames.primary(userId, slotId)`.
  - Before writing, **dedupe** (compare `hash`) and **rate‑limit** (compare `updatedAt`).
  - On actual save (only if `APPLY_CHANGES=true`): write **backup first**, then update **primary**, then call `SaveIndex.write`.

- **Loading path**:
  - Prefer reading your current **primary** key.
  - If the value has an `_envelope`, pass `value.data` to existing deserialization so game code remains unchanged.
  - If no `_envelope` (old saves), treat the whole value as `data` (backward compatible).
  - If primary missing/corrupt, **fallback**: scan backups for same slot, pick **newest** (largest ISO segment or most recent `updatedAt`) and restore to primary (*only if* `APPLY_CHANGES=true`; otherwise just log recommendation).

- **GC/Audit scheduling**:
  - Ensure `SaveAuditor.server.lua` runs on server start (safe; dry‑run).
  - `SaveGC.server.lua` may also run on server start; it will **no‑op** unless `APPLY_CHANGES=true`.
  - Both scripts yield and are throttled to avoid rate limits.

---

## Retention & cleanup rules

- **Backups**: keep at most `MAX_BACKUPS_PER_SLOT` (default 3); everything older is deletable. Independently, delete any backup older than `MAX_BACKUP_AGE_SECONDS` (default 14 days).
- **Primaries**: keep the newest one; if multiple primaries exist, delete older ones.
- **Orphans**: any key not referenced by the current per-user index and not the newest by name/time is safe to delete.
- **No-change dedupe**: when a save’s `hash` matches the last primary’s hash, skip the write entirely.
- **Min interval**: do not commit a new primary if the last `updatedAt` is newer than `MIN_COMMIT_INTERVAL_SECONDS`.

---

## High-churn vs low-churn handling

- Treat balances, tickets, or other rapidly changing counters as **high-churn**: stage updates server-side and only flush the staged snapshot after the `MIN_COMMIT_INTERVAL_SECONDS` window or on an explicit flush (player leave, manual save). Within the window you simply refresh the staged data; no DataStore writes occur.
- Stable structures (city layout, cosmetics, unlock flags) are **low-churn** and can commit immediately when they change.
- If a counter truly needs per-transaction durability, keep using a lightweight store (e.g., `UpdateAsync` delta or MemoryStore tally) and merge it back into the enveloped payload just before the staged commit. This keeps the main slot hash from changing every second while preserving correctness.

---

## Storage budget guard

- Roblox enforces `Total latest version storage limit = 100 MB + 1 MB * lifetime user count`. Track your approximate usage by summing the envelope sizes the auditor reports per store.
- Extend `SaveAuditor` to fetch (or approximate) the lifetime user count and log whenever usage exceeds a chosen threshold (e.g., 80% of that computed ceiling). Example: `[AUDIT][WARN] PlayerData_Release1 using 82 MB of 105 MB budget (lifetime users=5)`.
- Persist the budget report in `REPORT_STORE` so you can track trends and confirm retention/dedupe changes are keeping the live footprint under the cap.

---
## Onboarding notes

- Keep `Onboarding` at top level (per player) — correct placement.
- After completion, optionally compact to `{state="Completed", version=+1, completionAwarded=true}` in a future apply phase. Keep this **dry‑run** until approved.

---

## Do **not** change

- Client‑facing fields or gameplay logic.
- Compression formats (`roadsB64`, `zonesB64`) or slot schema.
- Existing DataStore names (use wrappers & indexing instead).
- Any data when `APPLY_CHANGES=false`.

---

## How to run

1. Drop the new files in the listed paths.
2. Leave `SavePolicy.APPLY_CHANGES = false`. Publish, start a **private server**, observe `[AUDIT]` and `[RETENTION][DRY-RUN]` logs.
3. After review, set `APPLY_CHANGES = true` to enforce retention + cleanup.
4. Remove once‑off tools later if desired; keep the SaveManager dedupe.

## Useful info
The storage limit will be calculated using the formula Total latest version storage limit = 100 MB + 1 MB * lifetime user count. `[AUDIT] logs should emit (and persist) warnings whenever estimated payload size approaches or exceeds this computed ceiling.

*End of Codex task blob.*
