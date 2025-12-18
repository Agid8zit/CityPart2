-- PlayerDataService.lua
local PlayerDataService = {}

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- Dependencies
local DefaultData = require(script.DefaultData)
local Utility = require(ReplicatedStorage.Scripts.Utility)
local DataStoreClass = require(ServerScriptService.DataStore.DataStoreClass)
local SavePolicy = require(ServerScriptService.Config.SavePolicy)
local SaveEnvelope = require(game.ReplicatedStorage.Systems.SaveEnvelope)
local SaveKeyNames = require(ServerScriptService.Services.SaveKeyNames)
local SaveIndex = require(ServerScriptService.Services.SaveIndex)
local PlayerDataInterfaceService = nil

-- Constants
local DEBUG_PRINT_PLAYERDATA_LOAD = false
local DEBUG_PRINT_PLAYERDATA_SAVE = false

local DEBUG_IGNORE_PLAYERDATA_DATASTORES = false
local DEBUG_IGNORE_SESSION_LOCKING = false
local DEBUG_IGNORE_PLAYERDATA_SAVE = false
local DEBUG_IGNORE_PLAYERDATA_LOAD = false

local VERBOSE_LOG = false
local function log(...)
	if VERBOSE_LOG then print(...) end
end

local DEFAULT_PLAYER_DS = RunService:IsStudio() and "PlayerData_PublicTest2" or "PlayerData_Release2"
local PLAYERDATA_DATASTORE = SavePolicy.PLAYER_DS_BY_ENV[SavePolicy.ENV] or DEFAULT_PLAYER_DS
local SLOT_ID = "player"
local PER_USER_PRUNE_INTERVAL = 90
local PER_USER_PRUNE_BATCH = 2
local SESSION_LOCK_TTL = 30 -- seconds; aligns with server shutdown window
local function _findExistingPlotForPlayer(player: Player)
	if not player then
		return nil
	end
	local plotName = ("plot_%s"):format(player.UserId)
	-- try common containers first to avoid deep scans
	local plotsFolder = Workspace:FindFirstChild("Plots")
	if plotsFolder then
		local hit = plotsFolder:FindFirstChild(plotName) or plotsFolder:FindFirstChild(player.Name) or plotsFolder:FindFirstChild(tostring(player.UserId))
		if hit then
			return hit
		end
	end
	-- fallback: shallow search at root, then recursive
	return Workspace:FindFirstChild(plotName) or Workspace:FindFirstChild(player.Name) or Workspace:FindFirstChild(tostring(player.UserId)) or Workspace:FindFirstChild(plotName, true)
end

-- Fail-safe: world reload staging should be brief; auto-heal if it ever gets stuck.
local NO_COMMIT_TIMEOUT_SEC = 60

-- Defines
PlayerDataService.AllPlayerData = {} -- [Player] = PlayerData

-- >>> CHANGED: Saving state reworked to coalesce/flush
PlayerDataService.SavingMutex = {} -- Set<Player> (back-compat)
local _saving = {}                -- [Player] = true when actively saving
local _pending = {}               -- [Player] = true when a save was requested while _saving is true
local _waiters = {}               -- [Player] = BindableEvent fired when a save completes (for waits)
local function _get_waiter(plr)
	local ev = _waiters[plr]
	if not ev then
		ev = Instance.new("BindableEvent")
		_waiters[plr] = ev
	end
	return ev
end

PlayerDataService.PlayerDataFailed = {} -- Set<Player>
local SessionLocking = nil -- DataStoreObject
local SessionLockingLoading = false
local _lastEnvelopeMeta = {} -- [Player] = { hash, updatedAt, approxBytes }
local _highChurnTouches = {} -- [Player] = os.time()
local _sessionStart = {} -- [Player] = os.clock()
local _pruneQueue = {} -- [userId] = true
local function _isCityStoragePath(path: string?)
	return type(path) == "string" and string.find(path, "cityStorage", 1, true) ~= nil
end

-- Trim large cityStorage blobs before sending to clients to avoid RECV spikes.
local function _copyForClient(pd: any)
	if type(pd) ~= "table" then
		return pd
	end

	local copy = {}
	for k, v in pairs(pd) do
		if k == "savefiles" and type(v) == "table" then
			local slots = {}
			for slotId, slot in pairs(v) do
				if type(slot) == "table" then
					local slotCopy = {}
					for sk, sv in pairs(slot) do
						if sk ~= "cityStorage" then
							slotCopy[sk] = sv
						end
					end
					slots[slotId] = slotCopy
				else
					slots[slotId] = slot
				end
			end
			copy.savefiles = slots
		else
			copy[k] = v
		end
	end

	return copy
end

-- Networking
local RE_UpdatePlayerData = ReplicatedStorage.Events.RemoteEvents.UpdatePlayerData
local RF_RequestReload = ReplicatedStorage.Events.RemoteEvents.RequestReload

-- Throttle UpdatePlayerData bursts (per-player coalescing)
local UPDATE_DEBOUNCE_SEC = 0.1
local _pendingPdUpdates = {}      -- [Player] = { [path] = value }
local _pendingPdFlush = {}        -- [Player] = true when flush scheduled

local function _queueUpdatePlayerData(Player: Player, Path: string, NewValue: any)
	local q = _pendingPdUpdates[Player]
	if not q then
		q = {}
		_pendingPdUpdates[Player] = q
	end
	q[Path] = NewValue

	if _pendingPdFlush[Player] then return end
	_pendingPdFlush[Player] = true

	task.delay(UPDATE_DEBOUNCE_SEC, function()
		_pendingPdFlush[Player] = nil
		local queued = _pendingPdUpdates[Player]
		_pendingPdUpdates[Player] = nil
		if not queued then return end
		for path, value in pairs(queued) do
			RE_UpdatePlayerData:FireClient(Player, value, path)
		end
	end)
end

-- >>> CHANGED: No‑commit window (staging + rollback) ------------------------
-- We treat WorldReloadBegin..WorldReloadEnd as a "no-commit" window:
-- * ModifySaveData writes are STAGED (not applied to live slot)
-- * On End we COMMIT staged patches and refresh last-good snapshot
-- * If the player leaves before End, we ROLLBACK to last-good
local _noCommitWindow = {}                 -- [Player] = true
local _stagedPatches = {}                  -- [Player] = { [path] = value }
local _lastGoodSlotSnapshot = {}           -- [Player] = deep clone of current savefile (slot table)
local _noCommitEnteredAt = {}              -- [Player] = os.clock() timestamp

local function _getSaveData(Player: Player)
	local pd = PlayerDataService.AllPlayerData[Player]
	if not pd then return nil, nil, nil end
	local cur = pd.currentSaveFile
	if not cur then return pd, nil, nil end
	local sf = pd.savefiles and pd.savefiles[cur]
	return pd, cur, sf
end

local function _playerStore()
	return DataStoreService:GetDataStore(PLAYERDATA_DATASTORE)
end

local function _primaryKey(userId)
	return SaveKeyNames.primary(userId, SLOT_ID)
end

local function _slotIdForPlayer()
	return SLOT_ID
end

local function _deepClone(v)
	if Utility and Utility.CloneTable then
		return Utility.CloneTable(v)
	end
	-- Fallback shallow
	return v
end

local function _markHighChurn(player, path)
	if not path then
		return
	end
	for trackedPath in pairs(SavePolicy.HIGH_CHURN_PATHS) do
		if string.sub(path, 1, #trackedPath) == trackedPath then
			_highChurnTouches[player] = os.time()
			return
		end
	end
end

local function _sessionDurationFor(userId: number)
	for player, startedAt in pairs(_sessionStart) do
		if player.UserId == userId then
			return math.max(0, os.clock() - startedAt)
		end
	end
	return 0
end

-- Budget helpers need to be defined before any DataStore calls use them.
local function _waitForBudget(requestType: Enum.DataStoreRequestType, minBudget: number?, timeoutSec: number?)
	minBudget = math.max(1, tonumber(minBudget) or 1)
	local deadline = os.clock() + (timeoutSec or 8)
	repeat
		local ok, budget = pcall(DataStoreService.GetRequestBudgetForRequestType, DataStoreService, requestType)
		if ok and budget >= minBudget then
			return true
		end
		task.wait(0.2)
	until os.clock() >= deadline
	return false
end

local function _dsCallWithBudget(requestType: Enum.DataStoreRequestType, label: string, fn: () -> any)
	if not _waitForBudget(requestType, 1, 8) then
		warn(("[PlayerDataService] Budget low for %s; letting Roblox queue the request"):format(label))
	end
	local ok, result = pcall(fn)
	if not ok then
		warn(("[PlayerDataService] %s failed: %s"):format(label, tostring(result)))
		return nil, false, result
	end
	return result, true
end

local DEFAULT_DS_RETRIES = 3
local function _dsCallWithRetry(requestType: Enum.DataStoreRequestType, label: string, fn: () -> any, maxAttempts: number?)
	local attempts = math.clamp(math.floor(maxAttempts or DEFAULT_DS_RETRIES), 1, 5)
	local delaySec = 0.5
	local lastErr = nil

	for attempt = 1, attempts do
		local result, ok, err = _dsCallWithBudget(requestType, label, fn)
		if ok ~= false then
			return result, ok, err
		end

		lastErr = err
		if attempt < attempts then
			local jitter = math.random() * 0.25
			task.wait(delaySec + jitter)
			delaySec = math.min(delaySec * 2, 4)
		end
	end

	return nil, false, lastErr
end

local function _hasPendingOrphans(idx)
	if not idx or not idx.slots then
		return false
	end
	for _, record in pairs(idx.slots) do
		if record and record.orphanBackups and #record.orphanBackups > 0 then
			return true
		end
	end
	return false
end

local function _markPruneNeeded(userId)
	if not userId then
		return
	end
	_pruneQueue[tostring(userId)] = true
end

local function _detectExistingOrphans(userId)
	task.spawn(function()
		local idx = SaveIndex.read(userId)
		if _hasPendingOrphans(idx) then
			_markPruneNeeded(userId)
		end
	end)
end

local function _pruneBackupsForUserId(userId)
	userId = tonumber(userId) or userId
	if SavePolicy.APPLY_CHANGES ~= true then
		return false
	end
	local idx = SaveIndex.read(userId)
	if not _hasPendingOrphans(idx) then
		_pruneQueue[tostring(userId)] = nil
		return false
	end
	local store = _playerStore()
	local mutated = false
	idx.slots = idx.slots or {}
	for slotId, slotRecord in pairs(idx.slots) do
		local pending = slotRecord and slotRecord.orphanBackups
		if pending and #pending > 0 then
			local survivors = {}
			for _, key in ipairs(pending) do
				local _, removed = _dsCallWithRetry(
					Enum.DataStoreRequestType.SetIncrementAsync,
					("PruneBackup:%s"):format(key),
					function()
						return store:RemoveAsync(key)
					end
				)
				if removed then
					mutated = true
					log(("[RETENTION][USER] Deleted orphaned backup for %s slot=%s key=%s"):format(userId, tostring(slotId), key))
				else
					warn("[RETENTION][ERROR] per-user delete failed", userId, key)
					table.insert(survivors, key)
				end
				task.wait(SavePolicy.YIELD_BETWEEN_DELETES)
			end
			if #survivors > 0 then
				slotRecord.orphanBackups = survivors
			else
				slotRecord.orphanBackups = nil
			end
		end
	end
	if mutated or not _hasPendingOrphans(idx) then
		SaveIndex.write(userId, idx)
	end
	if not _hasPendingOrphans(idx) then
		_pruneQueue[tostring(userId)] = nil
	end
	return mutated
end

local function _pruneSweep()
	if SavePolicy.APPLY_CHANGES ~= true then
		return
	end
	local queueIds = {}
	for userId in pairs(_pruneQueue) do
		table.insert(queueIds, tonumber(userId) or userId)
	end
	if #queueIds == 0 then
		return
	end
	table.sort(queueIds, function(a, b)
		return _sessionDurationFor(tonumber(a) or 0) > _sessionDurationFor(tonumber(b) or 0)
	end)
	local processed = 0
	for _, userId in ipairs(queueIds) do
		_pruneBackupsForUserId(userId)
		processed += 1
		if processed >= PER_USER_PRUNE_BATCH then
			break
		end
	end
end

task.spawn(function()
	while true do
		task.wait(PER_USER_PRUNE_INTERVAL)
		_pruneSweep()
	end
end)

local function _enterNoCommitWindow(Player: Player)
	-- idempotent
	if _noCommitWindow[Player] then return end
	local _, _, sf = _getSaveData(Player)
	if not sf then return end
	_noCommitWindow[Player] = true
	_stagedPatches[Player] = {}
	_lastGoodSlotSnapshot[Player] = _deepClone(sf)
	_noCommitEnteredAt[Player] = os.clock()
end

local function _commitNoCommitWindow(Player: Player)
	if not _noCommitWindow[Player] then return end
	local pd, cur, _ = _getSaveData(Player)
	if not pd or not cur then
		_noCommitWindow[Player] = nil
		_stagedPatches[Player] = nil
		return
	end

	local patches = _stagedPatches[Player]
	if patches then
		for path, value in pairs(patches) do
			-- Apply into live player data
			Utility.ModifyTableByPath(pd, ("savefiles/%s/%s"):format(cur, path), value)
		end
	end

	-- Refresh last-good to the newly committed slot
	local sfNow = pd.savefiles[cur]
	_lastGoodSlotSnapshot[Player] = _deepClone(sfNow)

	-- Sync to the client (single full snapshot is simplest & robust)
	RE_UpdatePlayerData:FireClient(Player, _copyForClient(pd), nil)

	-- Clear window
	_stagedPatches[Player] = nil
	_noCommitWindow[Player] = nil
	_noCommitEnteredAt[Player] = nil
end

local function _rollbackNoCommitWindow(Player: Player)
	if not _noCommitWindow[Player] then return end
	local pd, cur, _ = _getSaveData(Player)
	local snap = _lastGoodSlotSnapshot[Player]
	if pd and cur and snap then
		pd.savefiles[cur] = _deepClone(snap)
	end
	_stagedPatches[Player] = nil
	_noCommitWindow[Player] = nil
	_noCommitEnteredAt[Player] = nil
end

-- Guard: if WorldReloadEnd never fires, do not leave the player read-only forever.
local function _maybeAutoCommitNoCommitWindow(Player: Player)
	if not _noCommitWindow[Player] then return false end
	local enteredAt = _noCommitEnteredAt[Player]
	if not enteredAt then
		_noCommitEnteredAt[Player] = os.clock()
		return false
	end
	if (os.clock() - enteredAt) >= NO_COMMIT_TIMEOUT_SEC then
		warn(("[PlayerDataService] Auto-committing stale no-commit window after %.1fs for %s"):format(os.clock() - enteredAt, Player.Name))
		_commitNoCommitWindow(Player)
		return true
	end
	return false
end

function PlayerDataService.IsInNoCommitWindow(Player: Player): boolean
	return _noCommitWindow[Player] == true
end
-- ---------------------------------------------------------------------------

local function _rememberEnvelopeMeta(Player, env)
	if not env or not env._envelope then
		return
	end
	_lastEnvelopeMeta[Player] = {
		hash = env._envelope.hash,
		updatedAt = env._envelope.updatedAt or env._envelope.createdAt,
		approxBytes = env._envelope.approxBytes,
	}
end

local function _fetchKeyValue(store, key)
	local value, ok = _dsCallWithRetry(
		Enum.DataStoreRequestType.GetAsync,
		("GetAsync:%s"):format(tostring(key)),
		function()
			return store:GetAsync(key)
		end
	)
	if ok == false then
		return nil, false
	end
	return value, true
end

local function _loadPrimaryEnvelope(Player)
	local store = _playerStore()
	local key = _primaryKey(Player.UserId)
	local raw, ok = _fetchKeyValue(store, key)
	if ok == false then
		return nil, false
	end
	if not raw then
		return nil, true
	end
	if raw._envelope and raw.data then
		return raw, true
	end
	-- Legacy/non-enveloped payload
	return SaveEnvelope.wrap(_slotIdForPlayer(), raw, raw.Version or 1), true
end

local function _recoverFromBackups(Player)
	local idx = SaveIndex.read(Player.UserId)
	local slotRecord = idx.slots and idx.slots[_slotIdForPlayer()]
	if not slotRecord then
		return nil
	end
	local backups = slotRecord.backups or {}
	if #backups == 0 then
		return nil
	end
	local store = _playerStore()
	local hadError = false
	for i = #backups, 1, -1 do
		local key = backups[i]
		local env, ok = _fetchKeyValue(store, key)
		if ok == false then
			hadError = true
		elseif env then
			if SavePolicy.APPLY_CHANGES == true then
				local _, wrote = _dsCallWithRetry(
					Enum.DataStoreRequestType.SetIncrementAsync,
					("RestorePrimary:%s"):format(Player.UserId),
					function()
						return store:SetAsync(_primaryKey(Player.UserId), SaveEnvelope.touch(env))
					end
				)
				if not wrote then
					warn("[DEDUP][ERROR] restore primary failed", Player.UserId)
				else
					log(("[DEDUP] Restored primary for %s from %s"):format(Player.UserId, key))
				end
			else
				log(("[AUDIT] Would restore primary for %s from %s"):format(Player.UserId, key))
			end
			return env, true
		end
	end
	return nil, not hadError
end

local function _updateIndexWithBackup(Player, primaryKey, backupKey)
	local idx = SaveIndex.read(Player.UserId)
	idx.slots = idx.slots or {}
	idx.slots[_slotIdForPlayer()] = idx.slots[_slotIdForPlayer()] or { primary = nil, backups = {} }
	local slotRecord = idx.slots[_slotIdForPlayer()]
	slotRecord.primary = primaryKey
	slotRecord.backups = slotRecord.backups or {}
	table.insert(slotRecord.backups, backupKey)
	local evicted = {}
	while #slotRecord.backups > SavePolicy.MAX_BACKUPS_PER_SLOT do
		table.insert(evicted, table.remove(slotRecord.backups, 1))
	end
	if #evicted > 0 then
		slotRecord.orphanBackups = slotRecord.orphanBackups or {}
		for _, key in ipairs(evicted) do
			table.insert(slotRecord.orphanBackups, key)
		end
		_markPruneNeeded(Player.UserId)
	end
	SaveIndex.write(Player.UserId, idx)
end

-- Helper Functions
local function DebugPrintLoad(PrefixString: string, RawTable, ...)
	if DEBUG_PRINT_PLAYERDATA_LOAD then
		if PrefixString then
			print(PrefixString)
		end
		if RawTable then
			Utility.PrettyPrintTable(RawTable)
		end
		local PostStrings = table.pack(...)
		if PostStrings then
			for Key, Value in PostStrings do
				if Key == "n" then continue end
				print(Value)
			end
		end
	end
end

local function DebugPrintSave(PrefixString: string, RawTable, ...)
	if DEBUG_PRINT_PLAYERDATA_SAVE then
		if PrefixString then
			print(PrefixString)
		end
		if RawTable then
			Utility.PrettyPrintTable(RawTable)
		end
		local PostStrings = table.pack(...)
		if PostStrings then
			for Key, Value in PostStrings do
				if Key == "n" then continue end
				print(Value)
			end
		end
	end
end

local function ShouldUseSessionLocking()
	return
		not DEBUG_IGNORE_SESSION_LOCKING
		and not DEBUG_IGNORE_PLAYERDATA_DATASTORES
		and not DEBUG_IGNORE_PLAYERDATA_LOAD
		and not RunService:IsStudio()
end

local function _ensurePlayerWide(pd: table)
	pd.PlayerWide = pd.PlayerWide or {}
	pd.PlayerWide.saveSlots = pd.PlayerWide.saveSlots or {}
	local ss = pd.PlayerWide.saveSlots
	ss.default   = tonumber(ss.default)   or 2
	ss.purchased = tonumber(ss.purchased) or 0
	ss.bonus     = tonumber(ss.bonus)     or 0
	ss.total     = ss.default + ss.purchased + ss.bonus

	pd.PlayerWide.styles = pd.PlayerWide.styles or { owned = {}, equipped = "" }
	pd.PlayerWide.styles.owned = pd.PlayerWide.styles.owned or {}
	if type(pd.PlayerWide.styles.equipped) ~= "string" then
		pd.PlayerWide.styles.equipped = ""
	end

	local used = 0
	for k, v in pairs(pd.savefiles or {}) do
		if type(k) == "string" and type(v) == "table" then
			used += 1
		end
	end
	ss.used = used

	if not pd.currentSaveFile or not pd.savefiles[pd.currentSaveFile] then
		local minKey = nil
		for k,_ in pairs(pd.savefiles) do
			local n = tonumber(k)
			if n and (not minKey or n < minKey) then minKey = n end
		end
		pd.currentSaveFile = minKey and tostring(minKey) or "1"
	end
end

local function _countUsedSlots(pd: table): number
	local used = 0
	for k, v in pairs(pd.savefiles or {}) do
		if type(k) == "string" and type(v) == "table" then
			used += 1
		end
	end
	return used
end

local function _stampCurrentSlotLastPlayed(Player: Player)
	local pd = PlayerDataService.AllPlayerData[Player]
	if not pd then return end
	local cur = pd.currentSaveFile
	if not cur then return end
	local sf = pd.savefiles and pd.savefiles[cur]
	if not sf then return end
	local now = os.time()
	PlayerDataService.ModifyData(Player, ("savefiles/%s/lastPlayed"):format(cur), now)
end

local function _getSlotCap(pd: table): number
	local ss = (pd.PlayerWide and pd.PlayerWide.saveSlots) or {}
	return (ss.default or 1) + (ss.purchased or 0) + (ss.bonus or 0)
end

function PlayerDataService.GetSaveSlotCap(Player: Player): number
	local pd = PlayerDataService.AllPlayerData[Player]
	if not pd then return 0 end
	_ensurePlayerWide(pd)
	return _getSlotCap(pd)
end

function PlayerDataService.GetSaveSlotsUsed(Player: Player): number
	local pd = PlayerDataService.AllPlayerData[Player]
	if not pd then return 0 end
	return _countUsedSlots(pd)
end

function PlayerDataService.CanCreateNewSaveFile(Player: Player): boolean
	local pd = PlayerDataService.AllPlayerData[Player]
	if not pd then return false end
	_ensurePlayerWide(pd)
	return _countUsedSlots(pd) < _getSlotCap(pd)
end

function PlayerDataService.CreateNewSaveFile(Player: Player): string?
	local pd = PlayerDataService.AllPlayerData[Player]
	if not pd then return nil end
	_ensurePlayerWide(pd)

	local cap = _getSlotCap(pd)
	local used = _countUsedSlots(pd)
	if used >= cap then
		warn(("CreateNewSaveFile: capacity reached (%d/%d)"):format(used, cap))
		return nil
	end

	local taken = {}
	for k,_ in pairs(pd.savefiles) do
		local n = tonumber(k)
		if n then taken[n] = true end
	end
	local nextN = 1
	while taken[nextN] do nextN += 1 end

	local slotId = tostring(nextN)
	pd.savefiles[slotId] = PlayerDataService.GetDefaultData().newSaveFile()
	pd.currentSaveFile = slotId

	_ensurePlayerWide(pd)
	PlayerDataService.ModifyData(Player, nil, pd)
	return slotId
end

local function CreateSessionLockingDataStoreIfNoneExists()
	if not ShouldUseSessionLocking() then return true end

	if SessionLocking ~= nil then return true end
	if SessionLockingLoading then return true end
	SessionLockingLoading = true
	SessionLocking = DataStoreClass.new("PlayerSesionLock")
	SessionLockingLoading = false

	return SessionLocking ~= nil
end

local function _acquireSessionLock(Player: Player): boolean
	if not ShouldUseSessionLocking() then
		return true
	end

	while not SessionLocking do task.wait() end

	local myJob = game.JobId
	local deadline = os.time() + SESSION_LOCK_TTL + 1
	local lock, success = SessionLocking:GetAsync(Player.UserId)

	-- Wait while another server holds a fresh lock
	while success and lock and lock.jobId and lock.jobId ~= myJob and (os.time() - (lock.at or 0)) < SESSION_LOCK_TTL and os.time() < deadline do
		warn(("[!] Player (%s | %d) session locked by %s; waiting..."):format(Player.Name, Player.UserId, tostring(lock.jobId)))
		task.wait(4)
		lock, success = SessionLocking:GetAsync(Player.UserId)
	end

	-- If still locked by someone else within TTL, fail
	if success and lock and lock.jobId and lock.jobId ~= myJob and (os.time() - (lock.at or 0)) < SESSION_LOCK_TTL then
		warn(("[!] Session lock held by another server for %s (%d); aborting load."):format(Player.Name, Player.UserId))
		return false
	end

	-- Claim the lock for this job
	local _, okSet = SessionLocking:SetAsync(Player.UserId, { jobId = myJob, at = os.time() })
	if not okSet then
		warn(("[!] Failed to set session lock for %s (%d)"):format(Player.Name, Player.UserId))
		return false
	end

	return true
end

local function CreatePlayerDataDataStoreIfNoneExists(Player: Player): boolean
	-- Keys are derived on demand now; nothing to initialize per-player
	return true
end

local function CheckIfShouldNotSavePlayerData(Player: Player): boolean
	return PlayerDataService.PlayerDataFailed[Player]
		or PlayerDataService.AllPlayerData[Player] == nil
end

-- Module Functions
function PlayerDataService.GetDefaultData()
	return DefaultData
end

function PlayerDataService.GetData(Player: Player)
	return PlayerDataService.AllPlayerData[Player]
end

function PlayerDataService.GetSaveFileData(Player: Player)
	local playerdata = PlayerDataService.AllPlayerData[Player]
	if not playerdata then return nil end
	return playerdata.savefiles[playerdata.currentSaveFile]
end

function PlayerDataService.IsPlayerDataLoaded(Player: Player): boolean
	return PlayerDataService.AllPlayerData[Player] ~= nil
end

function PlayerDataService.WaitForPlayerData(Player: Player)
	local Timeout = os.time() + 30.0
	while not PlayerDataService.AllPlayerData[Player] do
		task.wait()
		if os.time() > Timeout then return false end
	end
	return true
end

function PlayerDataService.ModifyData(Player: Player, Path: string?, NewValue: any)
	if Path then
		if not PlayerDataService.AllPlayerData[Player] then
			warn("!!! ModyfData called when PlayerData ("..Player.Name..") is empty")
			return
		end
		Utility.ModifyTableByPath(PlayerDataService.AllPlayerData[Player], Path, NewValue)
		-- Skip cityStorage replication to avoid large network spikes
		if _isCityStoragePath(Path) then
			return
		end
		_queueUpdatePlayerData(Player, Path, NewValue)
	else
		PlayerDataService.AllPlayerData[Player] = NewValue
		RE_UpdatePlayerData:FireClient(Player, _copyForClient(NewValue), nil)
	end
end

-- >>> CHANGED: ModifySaveData now stages writes during reload ---------------
function PlayerDataService.ModifySaveData(Player: Player, Path: string, NewValue: any)
	local PlayerData = PlayerDataService.AllPlayerData[Player]
	if not PlayerData then return end
	local curSlot = PlayerData.currentSaveFile
	if not curSlot then return end

	local SaveData = PlayerData.savefiles[curSlot]
	if not SaveData then return end
	_markHighChurn(Player, Path)
	local fullPath = ("savefiles/%s/%s"):format(curSlot, Path)

	-- If a reload is in progress for this player, stage the mutation.
	if _noCommitWindow[Player] then
		-- Auto-heal any stuck windows instead of silently dropping live updates (e.g., income).
		if _maybeAutoCommitNoCommitWindow(Player) then
			-- committed + window cleared; fall through to normal path below
		else
			local patches = _stagedPatches[Player]
			if not patches then patches = {}; _stagedPatches[Player] = patches end
			-- shallow copy is fine for our paths (strings/numbers/encoded blobs)
			patches[Path] = (Utility and Utility.CloneTable) and Utility.CloneTable(NewValue) or NewValue
			-- Keep live data/UI in sync even while staging (prevents income pauses).
			PlayerDataService.ModifyData(Player, fullPath, NewValue)
			return
		end
	end

	-- Normal path: mutate live data and notify client
	PlayerDataService.ModifyData(Player, fullPath, NewValue)
end
-- ---------------------------------------------------------------------------

function PlayerDataService.Reset(Player: Player)
	local PlayerData = Utility.CloneTable(DefaultData.StartingData)
	PlayerData = PlayerDataInterfaceService.OnLoad(Player, PlayerData)
	PlayerDataService.ModifyData(Player, nil, PlayerData)
	PlayerDataInterfaceService.GiveMissingGamepasses(Player)
	PlayerDataInterfaceService.GiveMissingBadges(Player)
end

function PlayerDataService.RequestReload(Player: Player): boolean
	if PlayerDataService.PlayerDataFailed[Player] ~= true then return false end
	PlayerDataService.PlayerDataFailed[Player] = nil
	if not DEBUG_IGNORE_PLAYERDATA_LOAD and not DEBUG_IGNORE_PLAYERDATA_DATASTORES then
		if not CreatePlayerDataDataStoreIfNoneExists(Player) then
			warn("[!] Cannot access player datastore for reload")
			PlayerDataService.PlayerDataFailed[Player] = true
			return false
		end
	end
	PlayerDataService.Load(Player)
	return true
end

function PlayerDataService.Load(Player: Player)
	if not CreateSessionLockingDataStoreIfNoneExists() then
		warn("[!] Cannot Load PlayerData until SessionLocking has not been loaded")
		return
	end
	if ShouldUseSessionLocking() then
		if not _acquireSessionLock(Player) then
			PlayerDataService.PlayerDataFailed[Player] = true
			pcall(function()
				Player:Kick("Data failed to load. Please rejoin.")
			end)
			return
		end
	end
	if not DEBUG_IGNORE_PLAYERDATA_LOAD and not DEBUG_IGNORE_PLAYERDATA_DATASTORES then
		if not CreatePlayerDataDataStoreIfNoneExists(Player) then
			warn("[!] Cannot access player datastore for load")
			PlayerDataService.PlayerDataFailed[Player] = true
			if ShouldUseSessionLocking() and SessionLocking then
				SessionLocking:SetAsync(Player.UserId, false)
			end
			return
		end
	end

	local PlayerData = Utility.CloneTable(DefaultData.StartingData)

	if DEBUG_IGNORE_PLAYERDATA_LOAD or DEBUG_IGNORE_PLAYERDATA_DATASTORES then
		DebugPrintLoad("[NO LOAD] Ignoring PlayerData ("..Player.UserId..")")
	else
	log("[LOAD] PlayerData ("..Player.UserId..")")
		local env, ok = _loadPrimaryEnvelope(Player)
		if ok ~= false and not env then
			env, ok = _recoverFromBackups(Player)
		end

		if ok == false then
			PlayerDataService.PlayerDataFailed[Player] = true
			warn("[LOAD FAIL] PlayerData ("..Player.UserId..")")
			if ShouldUseSessionLocking() and SessionLocking then
				SessionLocking:SetAsync(Player.UserId, false)
			end
			pcall(function()
				Player:Kick("Data failed to load. Please rejoin.")
			end)
			return
		elseif env and env.data then
			PlayerData = Utility.MergeTables(env.data, PlayerData)
			PlayerDataService.PlayerDataFailed[Player] = nil
			_rememberEnvelopeMeta(Player, env)
			DebugPrintLoad("[LOAD SUCCESS] PlayerData ("..Player.UserId..")")
		else
			PlayerDataService.PlayerDataFailed[Player] = nil
			DebugPrintLoad("[NEW] PlayerData ("..Player.UserId..")")
			warn(("[LOAD] No datastore payload for %s (%d); using defaults"):format(Player.Name, Player.UserId))
		end
	end

	PlayerData = PlayerDataInterfaceService.OnLoad(Player, PlayerData)
	PlayerDataService.ModifyData(Player, nil, PlayerData)
	PlayerDataInterfaceService.GiveMissingGamepasses(Player)
	PlayerDataInterfaceService.GiveMissingBadges(Player)
	Player:SetAttribute("_PlayerDataLoaded", true)
end

-- >>> CHANGED: Coalescing Save + Flush/Wait support
local function _do_save_now(Player: Player, reason: string?, flush: boolean?)
	-- PRE: caller ensured not _saving[Player]
	_saving[Player] = true
	PlayerDataService.SavingMutex[Player] = true -- back-compat flag

	if DEBUG_IGNORE_PLAYERDATA_SAVE or DEBUG_IGNORE_PLAYERDATA_DATASTORES then
		DebugPrintSave("[NO SAVE] PlayerData ("..Player.UserId..")")
	else
	log(("[SAVE] PlayerData (%d) %s"):format(Player.UserId, reason or ""))
		PlayerDataService.AllPlayerData[Player] = PlayerDataInterfaceService.OnSave(Player, PlayerDataService.AllPlayerData[Player])

		local pd = PlayerDataService.AllPlayerData[Player]
		if pd then _ensurePlayerWide(pd) end

		local dataSnapshot = PlayerDataService.AllPlayerData[Player]
		local env = SaveEnvelope.wrap(_slotIdForPlayer(), dataSnapshot, dataSnapshot.Version or 1)
		local meta = _lastEnvelopeMeta[Player]
		local now = os.time()

		-- Hard guard: never overwrite a good save with an oversized payload (common when a player leaves mid-load).
		local oversize = env._envelope.approxBytes > SavePolicy.LIMITS.PER_SAVE_BYTES
		if oversize then
			warn(("[DEDUP][SIZE] payload exceeds soft limit (%d bytes) for %s; skipping commit"):format(env._envelope.approxBytes, Player.UserId))
		end

		if not oversize and SavePolicy.DEDUPE_BY_HASH and meta and meta.hash == env._envelope.hash and not flush then
			log(("[DEDUP] Skip unchanged save user=%s reason=%s"):format(Player.UserId, tostring(reason)))
		elseif not oversize then
			local lastTime = meta and meta.updatedAt or 0
			local since = now - lastTime
			if not flush and lastTime > 0 and since < SavePolicy.MIN_COMMIT_INTERVAL_SECONDS then
				local suffix = ""
				if _highChurnTouches[Player] and (now - _highChurnTouches[Player]) < SavePolicy.MIN_COMMIT_INTERVAL_SECONDS then
					suffix = " (high-churn staged)"
				end
				log(("[DEDUP] Skip due to min interval (%ds)%s user=%s"):format(SavePolicy.MIN_COMMIT_INTERVAL_SECONDS, suffix, Player.UserId))
			else
				local store = _playerStore()
				local primaryKey = _primaryKey(Player.UserId)
				local backupKey = SaveKeyNames.backup(Player.UserId, _slotIdForPlayer())

				if SavePolicy.APPLY_CHANGES ~= true then
					log(("[DEDUP][DRY-RUN] would write backup=%s primary=%s reason=%s"):format(backupKey, primaryKey, tostring(reason)))
					_rememberEnvelopeMeta(Player, env)
				else
					local _, okBackup, errBackup = _dsCallWithRetry(
						Enum.DataStoreRequestType.SetIncrementAsync,
						("BackupWrite:%s"):format(backupKey),
						function()
							return store:SetAsync(backupKey, env)
						end
					)
					if not okBackup then
						warn("[DEDUP][ERROR] backup write failed", backupKey, errBackup)
					end

					env = SaveEnvelope.touch(env)
					local _, okPrimary, errPrimary = _dsCallWithRetry(
						Enum.DataStoreRequestType.SetIncrementAsync,
						("PrimaryWrite:%s"):format(primaryKey),
						function()
							return store:SetAsync(primaryKey, env)
						end
					)
					if not okPrimary then
						warn("[DEDUP][ERROR] primary write failed", primaryKey, errPrimary)
					else
						log(("[DEDUP] Saved primary=%s backup=%s bytes=%d"):format(primaryKey, backupKey, env._envelope.approxBytes))
						_updateIndexWithBackup(Player, primaryKey, backupKey)
						_rememberEnvelopeMeta(Player, env)
					end
				end
			end
		end
	end

	PlayerDataService.SavingMutex[Player] = nil
	_saving[Player] = nil
	_get_waiter(Player):Fire()
end

function PlayerDataService.Save(Player: Player, opts: any)
	local reason = (opts and opts.reason) or nil
	local flush = (opts and opts.flush) == true

	if not CreateSessionLockingDataStoreIfNoneExists() then
		warn("[!] Cannot Save PlayerData until SessionLocking has not been loaded")
		return
	end
	if not DEBUG_IGNORE_PLAYERDATA_SAVE and not DEBUG_IGNORE_PLAYERDATA_DATASTORES then
		if not CreatePlayerDataDataStoreIfNoneExists(Player) then
			warn("[!] Cannot access player datastore for save")
			return
		end
	end

	if CheckIfShouldNotSavePlayerData(Player) then
		DebugPrintSave("[NO SAVE] Not Saving PlayerData ("..Player.UserId..")")
		return
	end

	-- If a save is in-flight, coalesce
	if _saving[Player] then
		_pending[Player] = true
		if flush then
			-- wait for in-flight to complete, then we'll proceed to do a final save below
			local deadline = os.clock() + 25.0
			while _saving[Player] and os.clock() < deadline do
				_get_waiter(Player).Event:Wait()
			end
			-- proceed to final save
		else
			DebugPrintSave("[QUEUE] Coalesced save request for ("..Player.UserId..")")
			return
		end
	end

	-- Drain pending saves: loop until no new pending flag appears
	repeat
		_pending[Player] = nil
		_do_save_now(Player, reason, flush)
	until not _pending[Player]
end

function PlayerDataService.SaveFlush(Player: Player, reason: string?)
	return PlayerDataService.Save(Player, { flush = true, reason = reason or "SaveFlush" })
end

function PlayerDataService.WaitForSavesToDrain(Player: Player, timeoutSeconds: number?)
	local deadline = os.clock() + (timeoutSeconds or 25.0)
	while ( _saving[Player] or _pending[Player] ) and os.clock() < deadline do
		_get_waiter(Player).Event:Wait()
	end
	return not _saving[Player] and not _pending[Player]
end

function PlayerDataService.PlayerAdded(Player: Player)
	_sessionStart[Player] = os.clock()
	local ghostPlot = _findExistingPlotForPlayer(Player)
	if ghostPlot then
		warn(("[WORLD] Existing plot detected for %s (%d): %s (destroying to avoid stale assignment)"):format(Player.Name, Player.UserId, ghostPlot:GetFullName()))
		task.spawn(function()
			pcall(function()
				ghostPlot:Destroy()
			end)
		end)
	end
	if not DEBUG_IGNORE_PLAYERDATA_DATASTORES then
		if not CreatePlayerDataDataStoreIfNoneExists(Player) then
			warn("[!] Cannot access player datastore during join")
			PlayerDataService.PlayerDataFailed[Player] = true
			return
		end
	end

	PlayerDataService.Load(Player)

	-- Per-user retention: delete any evicted/orphaned backup keys as soon as the user joins.
	-- (Avoids relying on the global SaveGC tool or long sweep intervals.)
	task.defer(function()
		_pruneBackupsForUserId(Player.UserId)
	end)
end

function PlayerDataService.PlayerRemoved(Player: Player)
	-- >>> CHANGED: if reload in progress, restore last-good before final flush
	if _noCommitWindow[Player] then
		_rollbackNoCommitWindow(Player)
	end

	-- Clean waiter
	local ev = _waiters[Player]
	if ev then
		_waiters[Player] = nil
		pcall(function() ev:Destroy() end)
	end

	-- Save on removal
	PlayerDataService.SaveFlush(Player, "PlayerRemoved")
	PlayerDataInterfaceService.PlayerLeavingAfterSaving(Player)

	PlayerDataService.AllPlayerData[Player] = nil
	PlayerDataService.PlayerDataFailed[Player] = nil
	_lastEnvelopeMeta[Player] = nil
	_highChurnTouches[Player] = nil
	_sessionStart[Player] = nil
	_pendingPdUpdates[Player] = nil
	_pendingPdFlush[Player] = nil
	_pruneBackupsForUserId(Player.UserId)

	if ShouldUseSessionLocking() then
		SessionLocking:SetAsync(Player.UserId, false)
	end

	-- Clear no-commit artifacts
	_noCommitWindow[Player] = nil
	_stagedPatches[Player] = nil
	_lastGoodSlotSnapshot[Player] = nil
	_noCommitEnteredAt[Player] = nil
end

function PlayerDataService.Init()
	task.spawn(function()
		PlayerDataInterfaceService = require(ServerScriptService.Services.PlayerDataInterfaceService)
	end)
	CreateSessionLockingDataStoreIfNoneExists()

	-- >>> CHANGED: Hook reload lifecycle (staging/commit)
	local EventsFolder = ReplicatedStorage:WaitForChild("Events")
	local BindableEvents = EventsFolder:WaitForChild("BindableEvents")
	local WorldReloadBeginBE = BindableEvents:WaitForChild("WorldReloadBegin")
	local WorldReloadEndBE   = BindableEvents:WaitForChild("WorldReloadEnd")

	WorldReloadBeginBE.Event:Connect(function(player: Player)
		_enterNoCommitWindow(player)
	end)
	WorldReloadEndBE.Event:Connect(function(player: Player)
		_commitNoCommitWindow(player)
	end)
end

-- Networking
RF_RequestReload.OnServerInvoke = PlayerDataService.RequestReload

return PlayerDataService
