--!strict
-- CityNameEndpoints.server.lua

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TextService         = game:GetService("TextService")
local Players             = game:GetService("Players")

-- Folders ---------------------------------------------------------------
local Events: Folder = (function()
	local f = ReplicatedStorage:FindFirstChild("Events")
	if f and f:IsA("Folder") then return f end
	local nf = Instance.new("Folder")
	nf.Name = "Events"
	nf.Parent = ReplicatedStorage
	return nf
end)()

local RemoteFunctions: Folder = (function()
	local f = Events:FindFirstChild("RemoteFunctions")
	if f and f:IsA("Folder") then return f end
	local nf = Instance.new("Folder")
	nf.Name = "RemoteFunctions"
	nf.Parent = Events
	return nf
end)()

local BindableEvents: Folder = (function()
	local f = Events:FindFirstChild("BindableEvents")
	if f and f:IsA("Folder") then return f end
	local nf = Instance.new("Folder")
	nf.Name = "BindableEvents"
	nf.Parent = Events
	return nf
end)()

local function ensureRF(name: string): RemoteFunction
	local inst = RemoteFunctions:FindFirstChild(name)
	if inst and inst:IsA("RemoteFunction") then return inst end
	-- compat: RF possibly (wrongly) placed under RemoteEvents in old builds
	local reFolder = Events:FindFirstChild("RemoteEvents")
	if reFolder and reFolder:IsA("Folder") then
		local rf2 = reFolder:FindFirstChild(name)
		if rf2 and rf2:IsA("RemoteFunction") then return rf2 end
	end
	local rf = Instance.new("RemoteFunction")
	rf.Name = name
	rf.Parent = RemoteFunctions
	return rf
end

-- Remotes
local RF_FilterCityName: RemoteFunction      = ensureRF("FilterCityName")
local RF_ConfirmCityName: RemoteFunction     = ensureRF("ConfirmCityName")
local RF_FilterNameForViewer: RemoteFunction = ensureRF("FilterNameForViewer") -- NEW (per-viewer)

-- Save hook
local ManualSaveBE: BindableEvent = (function()
	local inst = BindableEvents:FindFirstChild("ManualSave")
	if inst and inst:IsA("BindableEvent") then return inst end
	local be = Instance.new("BindableEvent")
	be.Name = "ManualSave"
	be.Parent = BindableEvents
	return be
end)()

-- Deps
local PlayerDataService: any = require(ServerScriptService.Services.PlayerDataService)
local DefaultData: any       = PlayerDataService.GetDefaultData()

-- Types
type ConfirmOk = { ok: true, slotId: string, cityName: string, lastPlayed: number }
type ConfirmErr = { ok: false, reason: string, min: number?, max: number? }
type ConfirmResult = ConfirmOk | ConfirmErr

-- Mutex per player ------------------------------------------------------
local busy: {[Player]: boolean} = {}

local function withMutex<T>(plr: Player, fn: () -> T, fallback: T): T
	if busy[plr] then return fallback end
	busy[plr] = true
	local ok, res = pcall(fn)
	busy[plr] = nil
	if ok then return res else
		warn("[CityNameEndpoints] error: ", res)
		return fallback
	end
end

-- Validation + Filtering helpers ---------------------------------------
local MIN_LEN = 3
local MAX_LEN = 32

local function trimAndNormalize(raw: string): string
	-- remove control chars, trim ends, collapse whitespace
	local s = tostring(raw or "")
	s = s:gsub("[%z\1-\31]", "")             -- strip ASCII control chars
	s = s:gsub("^%s+", ""):gsub("%s+$", "")  -- trim ends
	s = s:gsub("%s+", " ")                   -- collapse runs of whitespace
	return s
end

local function isBadName(candidate: string): boolean
	if candidate == "" then return true end
	local n = (utf8.len(candidate) :: number?) or #candidate
	return (n < MIN_LEN) or (n > MAX_LEN)
end

local function looksFiltered(s: string): boolean
	-- Roblox typically replaces disallowed characters with '#', and may return empty.
	return (s == "") or (s:find("#") ~= nil)
end

local function filterBroadcast(raw: string, fromUserId: number): (boolean, string)
	-- Use PublicChat context when the text will be visible to everyone.
	if raw == "" then return true, "" end
	local ok, outOrErr = pcall(function()
		local res = TextService:FilterStringAsync(raw, fromUserId, Enum.TextFilterContext.PublicChat)
		return res:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		warn("[CityNameEndpoints] filterBroadcast failed: ", outOrErr)
		return false, ""
	end
	return true, outOrErr :: string
end

local function filterForUser(raw: string, fromUserId: number, toUserId: number): (boolean, string)
	-- Useful when the text might vary by viewer (age/region).
	if raw == "" then return true, "" end
	local ok, outOrErr = pcall(function()
		local res = TextService:FilterStringAsync(raw, fromUserId, Enum.TextFilterContext.PublicChat)
		return res:GetNonChatStringForUserAsync(toUserId)
	end)
	if not ok then
		warn("[CityNameEndpoints] filterForUser failed: ", outOrErr)
		return false, ""
	end
	return true, outOrErr :: string
end

local function ensureSlot(pd: any, plr: Player): string
	local slotId: string = pd.currentSaveFile or "1"
	if pd.savefiles and pd.savefiles[slotId] == nil then
		local fresh = DefaultData.newSaveFile()
		PlayerDataService.ModifyData(plr, "savefiles/"..slotId, fresh)
	end
	return slotId
end

-- Remotes ---------------------------------------------------------------
RF_FilterCityName.OnServerInvoke = function(player: Player, raw: any): string
	local normalized = trimAndNormalize(tostring(raw or ""))
	local ok, filtered = filterBroadcast(normalized, player.UserId)
	if not ok then
		return ""
	end
	return filtered
end

RF_ConfirmCityName.OnServerInvoke = function(player: Player, rawName: any)
	return withMutex(player, function(): ConfirmResult
		local pd = PlayerDataService.GetData(player)
		if not pd then
			return { ok = false, reason = "no-playerdata" }
		end

		local normalized = trimAndNormalize(tostring(rawName or ""))

		if isBadName(normalized) then
			return { ok = false, reason = "BAD_NAME", min = MIN_LEN, max = MAX_LEN }
		end

		-- Strict, non-chat, visible-to-all filtering
		local okFilter, filtered = filterBroadcast(normalized, player.UserId)
		if not okFilter or looksFiltered(filtered) then
			-- Reject rather than saving "####" as the city name.
			return { ok = false, reason = "REJECTED_BY_FILTER", min = MIN_LEN, max = MAX_LEN }
		end

		local slotId = ensureSlot(pd, player)
		local now = os.time()

		-- Compatibility: keep filtered `cityName`, but also store raw+author for re-filtering later.
		PlayerDataService.ModifySaveData(player, "cityName",            filtered)         -- legacy/compat
		PlayerDataService.ModifySaveData(player, "cityNameRaw",         normalized)       -- NEW
		PlayerDataService.ModifySaveData(player, "cityNameAuthorId",    player.UserId)    -- NEW
		PlayerDataService.ModifySaveData(player, "lastPlayed",          now)

		print(("[CityNameEndpoints] ConfirmCityName OK by %s: '%s' (slot %s)")
			:format(player.Name, filtered, slotId))

		-- Slight delay to avoid overlapping the SwitchToSlot save in progress
		task.delay(0.35, function()
			ManualSaveBE:Fire(player)
		end)

		return { ok = true, slotId = slotId, cityName = filtered, lastPlayed = now }
	end, { ok = false, reason = "busy" })
end

-- NEW: per-viewer filter you can call to safely display any stored raw text to a specific viewer
RF_FilterNameForViewer.OnServerInvoke = function(viewer: Player, rawName: any, authorUserId: any): string
	local normalized = trimAndNormalize(tostring(rawName or ""))
	local fromId = tonumber(authorUserId) or viewer.UserId
	local ok, filtered = filterForUser(normalized, fromId, viewer.UserId)
	if not ok then
		return ""
	end
	return filtered
end

Players.PlayerRemoving:Connect(function(plr: Player)
	busy[plr] = nil
end)
