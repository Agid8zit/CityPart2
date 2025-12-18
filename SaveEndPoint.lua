-- SaveEndpoints.server.lua

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players             = game:GetService("Players")

-- ========== Folders ==========
local function ensureFolder(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if f and f:IsA("Folder") then return f end
	local nf = Instance.new("Folder")
	nf.Name = name
	nf.Parent = parent
	return nf
end

local EventsFolder: Folder = ensureFolder(ReplicatedStorage, "Events")
local RemoteEvents: Folder = ensureFolder(EventsFolder, "RemoteEvents")
local RemoteFunctions: Folder = ensureFolder(EventsFolder, "RemoteFunctions")
local BindableEvents: Folder = ensureFolder(EventsFolder, "BindableEvents")

-- ========== Remotes ==========
local function findOrCreateRF(name: string): RemoteFunction
	local rf = RemoteFunctions:FindFirstChild(name)
	if rf and rf:IsA("RemoteFunction") then return rf end
	local rf2 = RemoteEvents:FindFirstChild(name)
	if rf2 and rf2:IsA("RemoteFunction") then return rf2 end
	local newRF = Instance.new("RemoteFunction")
	newRF.Name = name
	newRF.Parent = RemoteFunctions
	return newRF
end

local DeleteSaveFileRF: RemoteFunction = findOrCreateRF("DeleteSaveFile")

local function findOrCreateRE(name: string): RemoteEvent
	local re = RemoteEvents:FindFirstChild(name)
	if re and re:IsA("RemoteEvent") then return re end
	local newRE = Instance.new("RemoteEvent")
	newRE.Name = name
	newRE.Parent = RemoteEvents
	return newRE
end

local RequestSaveNow: RemoteEvent    = findOrCreateRE("RequestSaveNow")
local GetSaveSlotsRF: RemoteFunction = findOrCreateRF("GetSaveSlots")
local SwitchToSlotRF: RemoteFunction = findOrCreateRF("SwitchToSlot")

-- Bindables: ManualSave + ReloadFromCurrent
local function ensureBE(name: string): BindableEvent
	local be = BindableEvents:FindFirstChild(name)
	if be and be:IsA("BindableEvent") then return be end
	local nb = Instance.new("BindableEvent")
	nb.Name = name
	nb.Parent = BindableEvents
	return nb
end

local ManualSaveBE: BindableEvent           = ensureBE("ManualSave")
local ReloadFromCurrentBE: BindableEvent    = ensureBE("RequestReloadFromCurrent")

-- Synchronous save (used for slot switching to avoid races with async BindableEvent handlers)
local function ensureBF(name: string): BindableFunction
	local bf = BindableEvents:FindFirstChild(name)
	if bf and bf:IsA("BindableFunction") then return bf end
	local nb = Instance.new("BindableFunction")
	nb.Name = name
	nb.Parent = BindableEvents
	return nb
end
local ManualSaveSyncBF: BindableFunction = ensureBF("ManualSaveSync")

local function manualSaveSync(player: Player, reason: string, timeoutSec: number?): boolean
	if not (player and player.Parent) then return false end
	local deadline = os.clock() + (timeoutSec or 30)
	while os.clock() < deadline do
		local ok, res = pcall(function()
			return ManualSaveSyncBF:Invoke(player, reason)
		end)
		if ok then
			return res == true
		end
		task.wait(0.05)
	end
	return false
end

-- Deps
local PlayerDataService: any = require(ServerScriptService.Services.PlayerDataService)
local PlayerDataInterfaceService: any = require(ServerScriptService.Services.PlayerDataInterfaceService)
local OnboardingService: any = require(ServerScriptService.Players.OnboardingService)
local DefaultData: any       = PlayerDataService.GetDefaultData()

-- Types
type SaveLite = { id: string, cityName: string?, lastPlayed: number?, hasData: boolean? }
type GetSaveSlotsResult = { current: string, slots: {SaveLite} }

local function recordDeletionDuringOnboarding(player: Player)
	if not OnboardingService then
		return
	end

	local okRecord, err = pcall(function()
		OnboardingService.RecordDeletionDuringOnboarding(player.UserId, player)
	end)
	if not okRecord then
		warn("[SaveEndpoints] RecordDeletionDuringOnboarding failed: ", err)
	end
end

-- Simple per-player mutex
local busy: {[Player]: boolean} = {}
local function begin(plr: Player): boolean
	if busy[plr] then return false end
	busy[plr] = true
	return true
end
local function finish(plr: Player)
	busy[plr] = nil
end

-- Event: manual save (unchanged trigger; SaveManager now flushes)
RequestSaveNow.OnServerEvent:Connect(function(player: Player)
	manualSaveSync(player, "RequestSaveNow", 30)
end)

-- RF: list slots
GetSaveSlotsRF.OnServerInvoke = function(player: Player): GetSaveSlotsResult
	local ok, out = pcall(function(): GetSaveSlotsResult
		local pd = PlayerDataService.GetData(player)
		if pd == nil then
			return { current = "1", slots = {} }
		end
		local result: GetSaveSlotsResult = { current = pd.currentSaveFile :: string, slots = {} }
		for slotId, sf in pairs(pd.savefiles or {}) do
			local row: SaveLite = {
				id         = tostring(slotId),
				cityName   = (sf :: any).cityName,
				lastPlayed = tonumber((sf :: any).lastPlayed) or 0,
				hasData    = true,
			}
			table.insert(result.slots, row)
		end
		return result
	end)
	if ok and typeof(out) == "table" then
		return out :: GetSaveSlotsResult
	end
	warn("[SaveEndpoints] GetSaveSlots failed: ", out)
	return { current = "1", slots = {} }
end

-- RF: SAVE(current) -> (optional create) -> SWITCH -> RELOAD
SwitchToSlotRF.OnServerInvoke = function(player: Player, slotId: any, createIfMissing: any): boolean
	if not begin(player) then
		warn("[SaveEndpoints] SwitchToSlot: busy for ", player.Name)
		return false
	end
	-- Prevent overlapping with an active reload (no-commit window) to avoid mixed slot state
	if typeof(PlayerDataService.IsInNoCommitWindow) == "function" and PlayerDataService.IsInNoCommitWindow(player) then
		warn("[SaveEndpoints] SwitchToSlot: reload in progress for ", player.Name)
		finish(player)
		return false
	end

	local ok, success = pcall(function(): boolean
		local target = tostring(slotId or "")
		if target == "" then
			warn("[SaveEndpoints] invalid slot id")
			return false
		end

		print(("[SaveEndpoints] SwitchToSlot slot=%s createIfMissing=%s by %s")
			:format(target, tostring(createIfMissing), player.Name))

		-- 1) Save current city first (flush + wait)
		if not manualSaveSync(player, "SwitchToSlot:pre", 30) then
			warn("[SaveEndpoints] SwitchToSlot: pre-save failed for ", player.Name)
			return false
		end

		-- 2) Ensure target exists (if requested)
		local pd = PlayerDataService.GetData(player)
		if pd == nil then
			warn("[SaveEndpoints] no player data")
			return false
		end

		if (createIfMissing == true) and (pd.savefiles[target] == nil) then
			local fresh = (DefaultData :: any).newSaveFile()
			PlayerDataService.ModifyData(player, "savefiles/"..target, fresh)
		end

		if pd.savefiles[target] == nil then
			warn("[SaveEndpoints] slot not found after create check: ", target)
			return false
		end

		-- Stamp metadata on the destination slot so lists sort correctly post-switch.
		pcall(function()
			PlayerDataService.ModifyData(player, ("savefiles/%s/lastPlayed"):format(target), os.time())
		end)

		-- 3) Switch
		PlayerDataService.ModifyData(player, "currentSaveFile", target)
		local pdNow = PlayerDataService.GetData(player)
		if pdNow then
			PlayerDataService.ModifyData(player, nil, pdNow)
		end
		PlayerDataInterfaceService.ResendCurrentSaveSignals(player)

		-- 4) Ask SaveManager to RELOAD from the *new* current slot
		ReloadFromCurrentBE:Fire(player)

		return true
	end)

	finish(player)
	if ok then
		return success
	else
		warn("[SaveEndpoints] SwitchToSlot crashed: ", success)
		return false
	end
end

-- RF: DELETE slot -> frees capacity; if deleting current, choose a new current and reload
DeleteSaveFileRF.OnServerInvoke = function(player: Player, slotId: any): boolean
	if not begin(player) then
		warn("[SaveEndpoints] DeleteSaveFile: busy for ", player.Name)
		return false
	end
	-- Avoid mutating savefiles while a reload window is active
	if typeof(PlayerDataService.IsInNoCommitWindow) == "function" and PlayerDataService.IsInNoCommitWindow(player) then
		warn("[SaveEndpoints] DeleteSaveFile: reload in progress for ", player.Name)
		finish(player)
		return false
	end

	local ok, success = pcall(function(): boolean
		local target = tostring(slotId or "")
		if target == "" then
			warn("[SaveEndpoints] DeleteSaveFile: bad slot id")
			return false
		end

		local pd = PlayerDataService.GetData(player)
		if pd == nil or pd.savefiles == nil then
			warn("[SaveEndpoints] DeleteSaveFile: no player data")
			return false
		end

		if pd.savefiles[target] == nil then
			warn("[SaveEndpoints] DeleteSaveFile: slot missing: ", target)
			return false
		end

		local count = 0
		for k, v in pairs(pd.savefiles) do
			if type(k) == "string" and type(v) == "table" then count += 1 end
		end
		if count <= 1 then
			recordDeletionDuringOnboarding(player)
			local fresh = (DefaultData :: any).newSaveFile()
			PlayerDataService.ModifyData(player, "savefiles/"..target, fresh)
			local pdNow = PlayerDataService.GetData(player)
			if pdNow then
				PlayerDataService.ModifyData(player, nil, pdNow)
			end
			PlayerDataInterfaceService.ResendCurrentSaveSignals(player)
			task.defer(function()
				ReloadFromCurrentBE:Fire(player)
			end)
			PlayerDataService.SaveFlush(player, "DeleteSaveFile(last-slot)")
			return true
		end

		print(("[SaveEndpoints] DeleteSaveFile slot=%s by %s"):format(target, player.Name))

		local deletingCurrent = (pd.currentSaveFile == target)

		if deletingCurrent then
			recordDeletionDuringOnboarding(player)
		end

		PlayerDataService.ModifyData(player, "savefiles/"..target, nil)

		if deletingCurrent then
			local minN: number? = nil
			for k, v in pairs(pd.savefiles) do
				if type(v) == "table" then
					local n = tonumber(k)
					if n and (minN == nil or n < minN) then
						minN = n
					end
				end
			end
			local newCur = minN and tostring(minN) or nil
			if newCur then
				PlayerDataService.ModifyData(player, "currentSaveFile", newCur)
				local pdNow = PlayerDataService.GetData(player)
				if pdNow then
					PlayerDataService.ModifyData(player, nil, pdNow)
				end
				PlayerDataInterfaceService.ResendCurrentSaveSignals(player)
				task.defer(function()
					ReloadFromCurrentBE:Fire(player)
				end)
			else
				warn("[SaveEndpoints] DeleteSaveFile: no fallback slot after delete")
				return false
			end
		end

		PlayerDataService.SaveFlush(player, "DeleteSaveFile")
		return true
	end)

	finish(player)
	if ok then
		return success
	else
		warn("[SaveEndpoints] DeleteSaveFile crashed: ", success)
		return false
	end
end

Players.PlayerRemoving:Connect(function(plr: Player)
	busy[plr] = nil
end)
