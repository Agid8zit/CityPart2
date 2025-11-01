-- PlayerDataService.lua
local PlayerDataService = {}

-- Roblox Services
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Dependencies
local DefaultData = require(script.DefaultData)
local Utility = require(ReplicatedStorage.Scripts.Utility)
local DataStoreClass = require(ServerScriptService.DataStore.DataStoreClass)
local VersionedDataStoreClass = require(ServerScriptService.DataStore.VersionedDataStoreClass)
local PlayerDataInterfaceService = nil

-- Constants
local DEBUG_PRINT_PLAYERDATA_LOAD = false
local DEBUG_PRINT_PLAYERDATA_SAVE = true

local DEBUG_IGNORE_PLAYERDATA_DATASTORES = false
local DEBUG_IGNORE_SESSION_LOCKING = false
local DEBUG_IGNORE_PLAYERDATA_SAVE = false
local DEBUG_IGNORE_PLAYERDATA_LOAD = false

local PLAYERDATA_DATASTORE = RunService:IsStudio() and "PlayerData_Test2" or "PlayerData_Release"

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
local VersionDataStores = {} -- [Player] = VersionedDataStoreObject
local VersionDataStoreLoading = {} -- Set<Player>
local SessionLocking = nil -- DataStoreObject
local SessionLockingLoading = false

-- Networking
local RE_UpdatePlayerData = ReplicatedStorage.Events.RemoteEvents.UpdatePlayerData
local RF_RequestReload = ReplicatedStorage.Events.RemoteEvents.RequestReload

-- >>> CHANGED: No‑commit window (staging + rollback) ------------------------
-- We treat WorldReloadBegin..WorldReloadEnd as a "no-commit" window:
-- * ModifySaveData writes are STAGED (not applied to live slot)
-- * On End we COMMIT staged patches and refresh last-good snapshot
-- * If the player leaves before End, we ROLLBACK to last-good
local _noCommitWindow = {}                 -- [Player] = true
local _stagedPatches = {}                  -- [Player] = { [path] = value }
local _lastGoodSlotSnapshot = {}           -- [Player] = deep clone of current savefile (slot table)

local function _getSaveData(Player: Player)
	local pd = PlayerDataService.AllPlayerData[Player]
	if not pd then return nil, nil, nil end
	local cur = pd.currentSaveFile
	if not cur then return pd, nil, nil end
	local sf = pd.savefiles and pd.savefiles[cur]
	return pd, cur, sf
end

local function _deepClone(v)
	if Utility and Utility.CloneTable then
		return Utility.CloneTable(v)
	end
	-- Fallback shallow
	return v
end

local function _enterNoCommitWindow(Player: Player)
	-- idempotent
	if _noCommitWindow[Player] then return end
	local _, _, sf = _getSaveData(Player)
	if not sf then return end
	_noCommitWindow[Player] = true
	_stagedPatches[Player] = {}
	_lastGoodSlotSnapshot[Player] = _deepClone(sf)
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
	RE_UpdatePlayerData:FireClient(Player, pd, nil)

	-- Clear window
	_stagedPatches[Player] = nil
	_noCommitWindow[Player] = nil
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
end

function PlayerDataService.IsInNoCommitWindow(Player: Player): boolean
	return _noCommitWindow[Player] == true
end
-- ---------------------------------------------------------------------------

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

local function CreatePlayerDataDataStoreIfNoneExists(Player: Player): boolean
	if VersionDataStores[Player] ~= nil then return true end
	if VersionDataStoreLoading[Player] then return true end
	VersionDataStoreLoading[Player] = true
	VersionDataStores[Player] = VersionedDataStoreClass.new(PLAYERDATA_DATASTORE, tostring(Player.UserId))
	VersionDataStoreLoading[Player] = false
	return VersionDataStores[Player] ~= nil
end

local function CheckIfShouldNotSavePlayerData(Player: Player): boolean
	return PlayerDataService.PlayerDataFailed[Player]
		or VersionDataStores[Player] == nil
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
		RE_UpdatePlayerData:FireClient(Player, NewValue, Path)
	else
		PlayerDataService.AllPlayerData[Player] = NewValue
		RE_UpdatePlayerData:FireClient(Player, NewValue, nil)
	end
end

-- >>> CHANGED: ModifySaveData now stages writes during reload ---------------
function PlayerDataService.ModifySaveData(Player: Player, Path: string, NewValue: any)
	local PlayerData = PlayerDataService.AllPlayerData[Player]
	if not PlayerData then return end
	local SaveData = PlayerData.savefiles[PlayerData.currentSaveFile]
	if not SaveData then return end

	-- If a reload is in progress for this player, stage the mutation.
	if _noCommitWindow[Player] then
		local patches = _stagedPatches[Player]
		if not patches then patches = {}; _stagedPatches[Player] = patches end
		-- shallow copy is fine for our paths (strings/numbers/encoded blobs)
		patches[Path] = (Utility and Utility.CloneTable) and Utility.CloneTable(NewValue) or NewValue
		return
	end

	-- Normal path: mutate live data and notify client
	PlayerDataService.ModifyData(Player, "savefiles/"..PlayerData.currentSaveFile.."/"..Path, NewValue)
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
			warn("[!] Cannot Load PlayerData because their VersionedDataStore has not been loaded")
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
	if not DEBUG_IGNORE_PLAYERDATA_LOAD and not DEBUG_IGNORE_PLAYERDATA_DATASTORES then
		if not CreatePlayerDataDataStoreIfNoneExists(Player) then
			warn("[!] Cannot Load PlayerData because their VersionedDataStore has not been loaded")
			PlayerDataService.PlayerDataFailed[Player] = true
			return
		end
	end

	local PlayerData = Utility.CloneTable(DefaultData.StartingData)

	if DEBUG_IGNORE_PLAYERDATA_LOAD or DEBUG_IGNORE_PLAYERDATA_DATASTORES then
		DebugPrintLoad("[NO LOAD] Ignoring PlayerData ("..Player.UserId..")")
	else
		print("[LOAD] PlayerData ("..Player.UserId..")")
		local LoadedData, Success, TimeStamp = VersionDataStores[Player]:GetAsync()
		DebugPrintLoad("[Pre-Load]", LoadedData, Success, TimeStamp)

		if Success then
			PlayerDataService.PlayerDataFailed[Player] = nil
		else
			PlayerDataService.PlayerDataFailed[Player] = true
		end

		if not Success then
			DebugPrintLoad("[LOAD FAIL] PlayerData ("..Player.UserId..")")
		elseif not TimeStamp then
			DebugPrintLoad("[NEW-1] PlayerData ("..Player.UserId..")")
		elseif not LoadedData then
			DebugPrintLoad("[NEW-2] PlayerData ("..Player.UserId..")")
		elseif typeof(LoadedData) == "table" then
			PlayerData = Utility.MergeTables(LoadedData, PlayerData)
			DebugPrintLoad("[LOAD SUCCESS] PlayerData ("..Player.UserId..")")
			DebugPrintLoad("[LOAD] PlayerData:", PlayerData)
		else
			warn("[???] PlayerData ("..Player.UserId..")")
		end
	end

	PlayerData = PlayerDataInterfaceService.OnLoad(Player, PlayerData)
	PlayerDataService.ModifyData(Player, nil, PlayerData)
	PlayerDataInterfaceService.GiveMissingGamepasses(Player)
	PlayerDataInterfaceService.GiveMissingBadges(Player)
	Player:SetAttribute("_PlayerDataLoaded", true)
end

-- >>> CHANGED: Coalescing Save + Flush/Wait support
local function _do_save_now(Player: Player, reason: string?)
	-- PRE: caller ensured not _saving[Player]
	_saving[Player] = true
	PlayerDataService.SavingMutex[Player] = true -- back-compat flag

	if DEBUG_IGNORE_PLAYERDATA_SAVE or DEBUG_IGNORE_PLAYERDATA_DATASTORES then
		DebugPrintSave("[NO SAVE] PlayerData ("..Player.UserId..")")
	else
		print(("[SAVE] PlayerData (%d) %s"):format(Player.UserId, reason or ""))
		PlayerDataService.AllPlayerData[Player] = PlayerDataInterfaceService.OnSave(Player, PlayerDataService.AllPlayerData[Player])

		local pd = PlayerDataService.AllPlayerData[Player]
		if pd then _ensurePlayerWide(pd) end

		local TimeStamp = os.time()
		local DataToSave = PlayerDataService.AllPlayerData[Player]

		DebugPrintSave("[SAVE TIMESTAMP] ".. TimeStamp)
		DebugPrintSave("[SAVE] PlayerData: ", DataToSave)

		local Success = VersionDataStores[Player]:SetAsync_NewSave(DataToSave, TimeStamp)

		if Success then
			DebugPrintSave("[SAVE DONE] PlayerData ("..Player.UserId..")")
		else
			DebugPrintSave("[SAVE FAILED] PlayerData ("..Player.UserId..")")
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
			warn("[!] Cannot Save PlayerData because their VersionedDataStore has not been loaded")
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
		_do_save_now(Player, reason)
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
	if ShouldUseSessionLocking() then
		while not SessionLocking do task.wait() end
		local IsLocked, Success = SessionLocking:GetAsync(Player.UserId)
		if IsLocked == true or not Success then
			local deadline = os.time() + 31
			while (IsLocked == true or not Success) and os.time() < deadline do
				warn(("[!] Player (%s | %d) session locked; waiting... locked=%s success=%s")
					:format(Player.Name, Player.UserId, tostring(IsLocked), tostring(Success)))
				task.wait(4)
				IsLocked, Success = SessionLocking:GetAsync(Player.UserId)
			end
			if IsLocked == true or not Success then
				warn(("[!] Session lock wait timed out for %s (%d); continuing without confirmed unlock."):format(Player.Name, Player.UserId))
			end
		end
		task.spawn(function()
			SessionLocking:SetAsync(Player.UserId, false)
		end)
	end

	if not DEBUG_IGNORE_PLAYERDATA_DATASTORES then
		if not CreatePlayerDataDataStoreIfNoneExists(Player) then
			warn("[!] Cannot Load PlayerData because their VersionedDataStore has not been loaded")
			PlayerDataService.PlayerDataFailed[Player] = true
			return
		end
	end

	PlayerDataService.Load(Player)
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

	VersionDataStores[Player] = nil
	VersionDataStoreLoading[Player] = nil
	PlayerDataService.AllPlayerData[Player] = nil
	PlayerDataService.PlayerDataFailed[Player] = nil

	if ShouldUseSessionLocking() then
		SessionLocking:SetAsync(Player.UserId, false)
	end

	-- Clear no-commit artifacts
	_noCommitWindow[Player] = nil
	_stagedPatches[Player] = nil
	_lastGoodSlotSnapshot[Player] = nil
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
