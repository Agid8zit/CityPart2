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

local RF_FilterCityName: RemoteFunction  = ensureRF("FilterCityName")
local RF_ConfirmCityName: RemoteFunction = ensureRF("ConfirmCityName")

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

-- Mutex per player
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

-- Filter + validation --------------------------------------------------
local function filterText(raw: string, fromUserId: number): string
	if raw == "" then return "" end
	local ok, result = pcall(function()
		local res = TextService:FilterStringAsync(raw, fromUserId)
		return res:GetNonChatStringForBroadcastAsync()
	end)
	if ok and typeof(result) == "string" then
		return result
	end
	return ""
end

local MIN_LEN = 3
local MAX_LEN = 32
local function isBadName(filtered: string): boolean
	if filtered == "" then return true end
	local trimmed = filtered:gsub("^%s+", ""):gsub("%s+$", "")
	if trimmed:gsub("%s+", "") == "" then return true end
	local n = #trimmed
	return (n < MIN_LEN) or (n > MAX_LEN)
end

-- Remotes --------------------------------------------------------------
RF_FilterCityName.OnServerInvoke = function(player: Player, raw: any): string
	local s = tostring(raw or "")
	return filterText(s, player.UserId)
end

RF_ConfirmCityName.OnServerInvoke = function(player: Player, rawName: any)
	-- mutex wrapper you already had, simplified here for brevity:
	local PlayerDataService: any = require(ServerScriptService.Services.PlayerDataService)
	local DefaultData: any       = PlayerDataService.GetDefaultData()

	local function filterText(raw: string, fromUserId: number): string
		local TextService = game:GetService("TextService")
		if raw == "" then return "" end
		local ok, result = pcall(function()
			local res = TextService:FilterStringAsync(raw, fromUserId)
			return res:GetNonChatStringForBroadcastAsync()
		end)
		return (ok and typeof(result) == "string") and (result :: string) or ""
	end

	local MIN_LEN, MAX_LEN = 3, 32
	local function isBadName(s: string): boolean
		if s == "" then return true end
		local t = s:gsub("^%s+",""):gsub("%s+$","")
		if t:gsub("%s+","") == "" then return true end
		local n = #t
		return (n < MIN_LEN) or (n > MAX_LEN)
	end

	local pd = PlayerDataService.GetData(player)
	if not pd then
		return { ok = false, reason = "no-playerdata" }
	end

	local filtered = filterText(tostring(rawName or ""), player.UserId)
	if isBadName(filtered) then
		return { ok = false, reason = "BAD_NAME", min = MIN_LEN, max = MAX_LEN }
	end

	local slotId: string = pd.currentSaveFile or "1"
	if pd.savefiles[slotId] == nil then
		local fresh = DefaultData.newSaveFile()
		PlayerDataService.ModifyData(player, "savefiles/"..slotId, fresh)
	end

	local now = os.time()
	PlayerDataService.ModifySaveData(player, "cityName",   filtered)
	PlayerDataService.ModifySaveData(player, "lastPlayed", now)

	print(("[CityNameEndpoints] ConfirmCityName OK by %s: '%s' (slot %s)")
		:format(player.Name, filtered, slotId))

	-- Slight delay to avoid overlapping the SwitchToSlot save in progress
	local EventsFolder = ReplicatedStorage:WaitForChild("Events")
	local BindableEvents = EventsFolder:WaitForChild("BindableEvents")
	local ManualSaveBE = BindableEvents:WaitForChild("ManualSave") :: BindableEvent

	task.delay(0.35, function()
		ManualSaveBE:Fire(player)
	end)

	return { ok = true, slotId = slotId, cityName = filtered, lastPlayed = now }
end

Players.PlayerRemoving:Connect(function(plr: Player)
	busy[plr] = nil
end)