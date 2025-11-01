local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService        = game:GetService("TweenService")
local Workspace           = game:GetService("Workspace")

-- ZoneTracker signals (listen-only)
local Build       = ServerScriptService:WaitForChild("Build")
local Zones       = Build:WaitForChild("Zones")
local ZoneMgr     = Zones:WaitForChild("ZoneManager")
local ZoneTracker = require(ZoneMgr:WaitForChild("ZoneTracker"))

-- Services
local PlayerDataInterfaceService = require(ServerScriptService.Services.PlayerDataInterfaceService)
local PlayerDataService          = require(ServerScriptService.Services.PlayerDataService)

-- Upgrades
local AirportUpgrades  = require(ReplicatedStorage.Scripts.AirportUpgrades)
local BusDepotUpgrades = require(ReplicatedStorage.Scripts.BusDepotUpgrades)

-- Events
local Events       = ReplicatedStorage:WaitForChild("Events")
local RemoteEvents = Events:WaitForChild("RemoteEvents")
local function ensureRE(name: string): RemoteEvent
	local ev = RemoteEvents:FindFirstChild(name)
	if not ev then ev = Instance.new("RemoteEvent"); ev.Name = name; ev.Parent = RemoteEvents end
	return ev
end

local RE_AddedAirport    = ensureRE("AddedAirport")   -- (zoneId, tiersTbl, unlock)
local RE_RemovedAirport  = ensureRE("RemovedAirport")
local RE_UpgradeAirport  = ensureRE("UpgradeAirport") -- C->S: (zoneId, tierIndex) ; S->C: (zoneId, tiersTbl, unlock)
local RE_AirportSync     = ensureRE("AirportSync")    -- (zoneId, tiersTbl, unlock)

local RE_AddedBusDepot   = ensureRE("AddedBusDepot")  -- (zoneId, tiersTbl, unlock)
local RE_RemovedBusDepot = ensureRE("RemovedBusDepot")
local RE_UpgradeBusDepot = ensureRE("UpgradeBusDepot")-- C->S: (zoneId, tierIndex) ; S->C: (zoneId, tiersTbl, unlock)
local RE_BusDepotSync    = ensureRE("BusDepotSync")   -- (zoneId, tiersTbl, unlock)

local BindableEvents     = Events:WaitForChild("BindableEvents")
local ZonePopulatedEvent = BindableEvents:WaitForChild("ZonePopulated")
local ZoneReCreatedEvent = BindableEvents:WaitForChild("ZoneReCreated")

-- ===================================================================
local MAX_TIERS = 10
local MAX_TIER_LEVEL = 100

local function unlockedTiers(unlock: number): number
	local t = math.floor(math.max(0, tonumber(unlock) or 0) / 10) + 1
	if t < 1 then t = 1 end
	if t > MAX_TIERS then t = MAX_TIERS end
	return t
end

local function clamp(n: number, lo: number, hi: number)
	if n < lo then return lo end
	if n > hi then return hi end
	return n
end

-- ===================================================================
-- In-memory state
-- ===================================================================
-- rec: { unlock:number, tiers:{[number]:number} }   <-- tiers are NUMBERS
local AirportState  = {} :: {[Player]: {[string]: {unlock:number, tiers:{[number]: number}}}}
local BusDepotState = {} :: {[Player]: {[string]: {unlock:number, tiers:{[number]: number}}}}

local zonePopulated = {}        -- [uid][zoneId] = true
local pendingUpgradeAlarms = {} -- [uid][zoneId] = true
local UpgradeAlarmParts = {}    -- [uid][zoneId] = BasePart

-- ===================================================================
-- Alarm bobbing & pool
-- ===================================================================
local USE_SHARED_BOBBING = 1==1
local BOB_SPEED = 2
local BOB_AMPLITUDE = 0.5
local ActiveUpgradeBobs = {} :: {[BasePart]: {base: Vector3, phase: number}}
local heartbeatConn: RBXScriptConnection? = nil
local function ensureHeartbeat()
	if heartbeatConn then return end
	heartbeatConn = RunService.Heartbeat:Connect(function()
		if not USE_SHARED_BOBBING then return end
		local tnow = os.clock()
		for part, info in pairs(ActiveUpgradeBobs) do
			if part.Parent then
				local dy = math.sin(tnow * BOB_SPEED + info.phase) * BOB_AMPLITUDE
				part.Position = info.base + Vector3.new(0, dy, 0)
			else
				ActiveUpgradeBobs[part] = nil
			end
		end
		if next(ActiveUpgradeBobs) == nil then heartbeatConn:Disconnect(); heartbeatConn = nil end
	end)
end
local function startBobbing(part: BasePart, basePos: Vector3)
	ActiveUpgradeBobs[part] = { base = basePos, phase = math.random() * math.pi * 2 }
	ensureHeartbeat()
end

local AlarmPool = {}
local function borrowAlarm(folder: Folder, name: string): BasePart?
	AlarmPool[name] = AlarmPool[name] or {}
	local pool = AlarmPool[name]
	local p = table.remove(pool)
	if p then return p end
	local t = folder:FindFirstChild(name)
	if not t then warn("[TransitTickets] Missing alarm template:", name) return nil end
	local clone = t:Clone()
	if clone:IsA("BasePart") then clone.Anchored = true; clone.CanCollide = false end
	return clone :: BasePart
end
local function returnAlarm(part: Instance?)
	if not part or not part:IsA("BasePart") then return end
	ActiveUpgradeBobs[part] = nil
	part.Parent = nil
	local key = part.Name:match("^(Alarm%u%l+)") or "AlarmUpgrade"
	AlarmPool[key] = AlarmPool[key] or {}
	table.insert(AlarmPool[key], part)
end

local function getZoneModelFor(player: Player, zoneId: string): Model?
	local plots = Workspace:FindFirstChild("PlayerPlots")
	local plot = plots and plots:FindFirstChild("Plot_"..player.UserId)
	if not plot then return nil end
	local zonesFolder = plot:FindFirstChild("PlayerZones"); if not zonesFolder then return nil end
	return zonesFolder:FindFirstChild(zoneId) :: Model?
end
local function getZoneModelPosition(model: Instance?): Vector3?
	if not model then return nil end
	if model:IsA("Model") then
		if model.PrimaryPart then return model.PrimaryPart.Position end
		local cf = model:GetBoundingBox(); return cf.Position
	elseif model:IsA("BasePart") then
		return model.Position
	end
	return nil
end
local function getTemplateFolder(): Folder?
	local root = ReplicatedStorage:FindFirstChild("FuncTestGroundRS")
	return root and root:FindFirstChild("Alarms") :: Folder?
end

local function hideUpgradeAlarm(player: Player, zoneId: string)
	local uid = player.UserId
	local map = UpgradeAlarmParts[uid]
	if not map then return end
	local part = map[zoneId]
	if part then map[zoneId] = nil; returnAlarm(part) end
	if pendingUpgradeAlarms[uid] then
		pendingUpgradeAlarms[uid][zoneId] = nil
		if next(pendingUpgradeAlarms[uid]) == nil then pendingUpgradeAlarms[uid] = nil end
	end
end

-- Frontier unlock rule (shared): only current frontier tier can unlock next.
-- Unlock becomes exactly 10 * tierIndex (tier 2 => 20) the first time frontier reaches >=10.
local function bumpUnlockIfThresholdCrossed(rec, tierIndex: number, oldLevel: number, newLevel: number): boolean
	local frontier = unlockedTiers(rec.unlock)           -- 1..MAX_TIERS
	if tierIndex ~= frontier then return false end

	local targetUnlock = math.min(MAX_TIER_LEVEL, tierIndex * 10) -- 10,20,30,...
	if rec.unlock >= targetUnlock then return false end

	if newLevel >= 10 then
		rec.unlock = targetUnlock
		return true
	end
	return false
end

-- Optional: catch-up on load if a player already crossed a frontier-10 but unlock is behind.
local function reconcileUnlockFromTiersFrontier(rec)
	-- Walk contiguous tiers from 1 upward; stop at first tier with level <10.
	local k = 1
	while rec.tiers[k] ~= nil and (rec.tiers[k] or 0) >= 10 and k < MAX_TIERS do
		k += 1
	end
	local desiredUnlock = (k - 1) * 10  -- 0,10,20,...
	if desiredUnlock > rec.unlock then
		rec.unlock = desiredUnlock
	end
	-- Ensure tiers exist up to unlocked count
	local ut = unlockedTiers(rec.unlock)
	for ti = 1, ut do
		if rec.tiers[ti] == nil then rec.tiers[ti] = 0 end
	end
end

local function showUpgradeAlarmNow(player: Player, zoneId: string)
	local model = getZoneModelFor(player, zoneId); if not model then return end
	local pos = getZoneModelPosition(model); if not pos then return end
	local folder = getTemplateFolder(); if not folder then return end
	UpgradeAlarmParts[player.UserId] = UpgradeAlarmParts[player.UserId] or {}
	local existing = UpgradeAlarmParts[player.UserId][zoneId]
	local base = pos + Vector3.new(0, 8, 0)
	if existing and existing.Parent then
		existing.Position = base
		if ActiveUpgradeBobs[existing] then ActiveUpgradeBobs[existing].base = base end
		return
	end
	local alarm = borrowAlarm(folder, "AlarmUpgrade"); if not alarm then return end
	alarm.Name = "AlarmUpgrade_"..zoneId
	alarm.Parent = model
	alarm.Position = base
	startBobbing(alarm, base)
	UpgradeAlarmParts[player.UserId][zoneId] = alarm
end
local function requestShowUpgradeAlarm(player: Player, zoneId: string)
	local uid = player.UserId
	if zonePopulated[uid] and zonePopulated[uid][zoneId] then
		showUpgradeAlarmNow(player, zoneId)
	else
		pendingUpgradeAlarms[uid] = pendingUpgradeAlarms[uid] or {}
		pendingUpgradeAlarms[uid][zoneId] = true
	end
end

-- Affordability across any unlocked tier
local function getTicketBalances(data)
	local plane  = (data and data.economy and data.economy.planetickets) or 0
	local bus    = (data and data.economy and data.economy.bustickets)   or 0
	return plane, bus
end
local function anyAirportTierAffordable(data, rec): boolean
	local plane = getTicketBalances(data)
	local ut = unlockedTiers(rec.unlock)
	for ti = 1, ut do
		local lvl = clamp(rec.tiers[ti] or 0, 0, MAX_TIER_LEVEL)
		if lvl < MAX_TIER_LEVEL then
			local cost = AirportUpgrades.GetUpgradeCost(lvl, ti)
			if plane >= cost then return true end
		end
	end
	return false
end
local function anyBusTierAffordable(data, rec): boolean
	local _, bus = getTicketBalances(data)
	local ut = unlockedTiers(rec.unlock)
	for ti = 1, ut do
		local lvl = clamp(rec.tiers[ti] or 0, 0, MAX_TIER_LEVEL)
		if lvl < MAX_TIER_LEVEL then
			local cost = BusDepotUpgrades.GetUpgradeCost(lvl, ti)
			if bus >= cost then return true end
		end
	end
	return false
end

local function recomputeUpgradeAlarmForZone(player: Player, zoneId: string, mode: string)
	local data = PlayerDataService.GetSaveFileData(player)
	if not data then hideUpgradeAlarm(player, zoneId) return end
	if mode == "Airport" then
		local rec = AirportState[player] and AirportState[player][zoneId]
		if not rec then hideUpgradeAlarm(player, zoneId) return end
		if anyAirportTierAffordable(data, rec) then requestShowUpgradeAlarm(player, zoneId) else hideUpgradeAlarm(player, zoneId) end
	elseif mode == "BusDepot" or mode == "Bus Depot" then
		local rec = BusDepotState[player] and BusDepotState[player][zoneId]
		if not rec then hideUpgradeAlarm(player, zoneId) return end
		if anyBusTierAffordable(data, rec) then requestShowUpgradeAlarm(player, zoneId) else hideUpgradeAlarm(player, zoneId) end
	end
end

local function flushPendingUpgradeAlarm(player: Player, zoneId: string)
	local uid = player.UserId
	local pend = pendingUpgradeAlarms[uid]
	if not (pend and pend[zoneId]) then return end
	pend[zoneId] = nil
	if next(pend) == nil then pendingUpgradeAlarms[uid] = nil end
	local z = ZoneTracker.getZoneById(player, zoneId); if not z then return end
	recomputeUpgradeAlarmForZone(player, zoneId, z.mode)
end

-- Lifecycle
local function onPlayerAdded(plr: Player)
	AirportState[plr]  = AirportState[plr]  or {}
	BusDepotState[plr] = BusDepotState[plr] or {}
	zonePopulated[plr.UserId] = zonePopulated[plr.UserId] or {}
	UpgradeAlarmParts[plr.UserId] = UpgradeAlarmParts[plr.UserId] or {}
end
local function clearPlayerAlarms(plr: Player)
	local uid = plr.UserId
	if UpgradeAlarmParts[uid] then for _,p in pairs(UpgradeAlarmParts[uid]) do returnAlarm(p) end end
	UpgradeAlarmParts[uid] = nil
	pendingUpgradeAlarms[uid] = nil
	zonePopulated[uid] = nil
end
local function onPlayerRemoving(plr: Player)
	AirportState[plr]  = nil
	BusDepotState[plr] = nil
	clearPlayerAlarms(plr)
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, plr in ipairs(Players:GetPlayers()) do onPlayerAdded(plr) end
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Seed helpers
local function readTransitNode(sf, key)
	-- ACCEPTS BOTH:
	--   legacy: sf.transit[key].tiers[ti] == { level = number }
	--   new:    sf.transit[key].tiers[ti] == number
	-- RETURNS: tiers[ti] as NUMBER
	sf.transit = sf.transit or {}
	local node = sf.transit[key]
	local out = { unlock = 0, tiers = {} }

	if typeof(node) ~= "table" then
		out.unlock = 0
		out.tiers[1] = 0
		return out
	end

	out.unlock = tonumber(node.unlock) or 0
	local ut = unlockedTiers(out.unlock)

	-- normalize each tier entry to numeric
	for ti = 1, math.max(1, ut) do
		local rec = node.tiers and node.tiers[ti]
		local lv
		if typeof(rec) == "table" then
			lv = tonumber(rec.level) or 0
		else
			lv = tonumber(rec) or 0
		end
		out.tiers[ti] = clamp(lv, 0, MAX_TIER_LEVEL)
	end

	return out
end

local function fireAirportSnapshot(player: Player, zoneId: string, rec)
	RE_AddedAirport:FireClient(player, zoneId, rec.tiers, rec.unlock)
	RE_AirportSync:FireClient(player, zoneId, rec.tiers, rec.unlock)
end
local function fireBusSnapshot(player: Player, zoneId: string, rec)
	RE_AddedBusDepot:FireClient(player, zoneId, rec.tiers, rec.unlock)
	RE_BusDepotSync:FireClient(player, zoneId, rec.tiers, rec.unlock)
end

-- Zone hooks
ZoneTracker.zoneAddedEvent.Event:Connect(function(player: Player, zoneId: string, zoneData)
	if not player or not zoneData or type(zoneData.mode) ~= "string" then return end
	local data = PlayerDataService.GetSaveFileData(player); if not data then return end

	if zoneData.mode == "Airport" then
		local rec = readTransitNode(data, "airport")
		reconcileUnlockFromTiersFrontier(rec) -- catch-up if needed
		AirportState[player][zoneId] = rec
		fireAirportSnapshot(player, zoneId, rec)
		recomputeUpgradeAlarmForZone(player, zoneId, "Airport")

	elseif zoneData.mode == "BusDepot" or zoneData.mode == "Bus Depot" then
		local rec = readTransitNode(data, "busDepot")
		-- (bus already behaved; keep as-is or add reconcile if desired)
		BusDepotState[player][zoneId] = rec
		fireBusSnapshot(player, zoneId, rec)
		recomputeUpgradeAlarmForZone(player, zoneId, "BusDepot")
	end
end)

ZoneTracker.zoneRemovedEvent.Event:Connect(function(player: Player, zoneId: string, mode: string)
	if not player or type(mode) ~= "string" then return end
	if mode == "Airport" then
		RE_RemovedAirport:FireClient(player, zoneId)
		if AirportState[player] then AirportState[player][zoneId] = nil end
		hideUpgradeAlarm(player, zoneId)
	elseif mode == "BusDepot" or mode == "Bus Depot" then
		RE_RemovedBusDepot:FireClient(player, zoneId)
		if BusDepotState[player] then BusDepotState[player][zoneId] = nil end
		hideUpgradeAlarm(player, zoneId)
	end
end)

-- Per-second accrual + alarms
local NextTick = os.time() + 1
RunService.Heartbeat:Connect(function()
	if os.time() < NextTick then return end
	NextTick = os.time() + 1

	for player, zones in pairs(AirportState) do
		local total = 0
		for _, rec in pairs(zones) do
			local ut = unlockedTiers(rec.unlock)
			for ti = 1, ut do
				local lvl = clamp(rec.tiers[ti] or 0, 0, MAX_TIER_LEVEL)
				-- CHANGED: pass tierIndex
				local earned = AirportUpgrades.GetEarnedTicketSec(lvl, ti)
				if typeof(earned) == "number" then total += earned end
			end
		end
		if total > 0 then PlayerDataInterfaceService.IncrementPlaneTicketsInSaveData(player, total) end
		for zoneId, _ in pairs(zones) do recomputeUpgradeAlarmForZone(player, zoneId, "Airport") end
	end

	for player, zones in pairs(BusDepotState) do
		local total = 0
		for _, rec in pairs(zones) do
			local ut = unlockedTiers(rec.unlock)
			for ti = 1, ut do
				local lvl = clamp(rec.tiers[ti] or 0, 0, MAX_TIER_LEVEL)
				-- CHANGED: pass tierIndex
				local earned = BusDepotUpgrades.GetEarnedTicketSec(lvl, ti)
				if typeof(earned) == "number" then total += earned end
			end
		end
		if total > 0 then PlayerDataInterfaceService.IncrementBusTicketsInSaveData(player, total) end
		for zoneId, _ in pairs(zones) do recomputeUpgradeAlarmForZone(player, zoneId, "BusDepot") end
	end
end)

-- Upgrades (write entire tiers table as NUMBERS)
RE_UpgradeAirport.OnServerEvent:Connect(function(player: Player, zoneId: string, tierIndex: number)
	if typeof(zoneId) ~= "string" then return end
	local zones = AirportState[player]; if not zones then return end
	local rec = zones[zoneId]; if not rec then return end

	tierIndex = clamp(math.floor(tonumber(tierIndex) or 0), 1, MAX_TIERS)
	local ut = unlockedTiers(rec.unlock); if tierIndex > ut then return end

	local data = PlayerDataService.GetSaveFileData(player); if not data then return end
	local lvl = clamp(rec.tiers[tierIndex] or 0, 0, MAX_TIER_LEVEL)
	if lvl >= MAX_TIER_LEVEL then return end

	local cost = AirportUpgrades.GetUpgradeCost(lvl, tierIndex)
	local plane = (data.economy and data.economy.planetickets) or 0
	if plane < cost then return end

	PlayerDataInterfaceService.IncrementPlaneTicketsInSaveData(player, -cost)

	-- increment level
	local newLevel = lvl + 1
	rec.tiers[tierIndex] = newLevel

	-- bump unlock if frontier tier reached >=10 (first time), map to 10 * tierIndex
	local bumped = bumpUnlockIfThresholdCrossed(rec, tierIndex, lvl, newLevel)
	if bumped then
		-- Persist unlock first
		PlayerDataService.ModifySaveData(player, "transit/airport/unlock", rec.unlock)

		-- Pre-seed all tiers up to the newly unlocked count at level 0
		local newlyUnlockedCount = unlockedTiers(rec.unlock)
		for ti = 1, newlyUnlockedCount do
			if rec.tiers[ti] == nil then
				rec.tiers[ti] = 0
			end
		end
	end

	-- Persist tiers table (numeric)
	PlayerDataService.ModifySaveData(player, "transit/airport/tiers", rec.tiers)

	-- Send snapshot (now includes updated unlock when applicable)
	RE_UpgradeAirport:FireClient(player, zoneId, rec.tiers, rec.unlock)
	RE_AirportSync:FireClient(player, zoneId, rec.tiers, rec.unlock)

	recomputeUpgradeAlarmForZone(player, zoneId, "Airport")
end)

RE_UpgradeBusDepot.OnServerEvent:Connect(function(player: Player, zoneId: string, tierIndex: number)
	if typeof(zoneId) ~= "string" then return end
	local zones = BusDepotState[player]; if not zones then return end
	local rec = zones[zoneId]; if not rec then return end

	tierIndex = clamp(math.floor(tonumber(tierIndex) or 0), 1, MAX_TIERS)
	local ut = unlockedTiers(rec.unlock); if tierIndex > ut then return end

	local data = PlayerDataService.GetSaveFileData(player); if not data then return end
	local lvl = clamp(rec.tiers[tierIndex] or 0, 0, MAX_TIER_LEVEL)
	if lvl >= MAX_TIER_LEVEL then return end

	local cost = BusDepotUpgrades.GetUpgradeCost(lvl, tierIndex)
	local bus = (data.economy and data.economy.bustickets) or 0
	if bus < cost then return end

	PlayerDataInterfaceService.IncrementBusTicketsInSaveData(player, -cost)

	-- increment level
	local newLevel = lvl + 1
	rec.tiers[tierIndex] = newLevel

	-- bump unlock if frontier tier reached >=10 (first time), map to 10 * tierIndex
	local bumped = bumpUnlockIfThresholdCrossed(rec, tierIndex, lvl, newLevel)
	if bumped then
		PlayerDataService.ModifySaveData(player, "transit/busDepot/unlock", rec.unlock)
		local newlyUnlockedCount = unlockedTiers(rec.unlock)
		for ti = 1, newlyUnlockedCount do
			if rec.tiers[ti] == nil then
				rec.tiers[ti] = 0
			end
		end
	end

	-- Persist tiers table (numeric)
	PlayerDataService.ModifySaveData(player, "transit/busDepot/tiers", rec.tiers)

	-- Send snapshot (now includes updated unlock when applicable)
	RE_UpgradeBusDepot:FireClient(player, zoneId, rec.tiers, rec.unlock)
	RE_BusDepotSync:FireClient(player, zoneId, rec.tiers, rec.unlock)

	recomputeUpgradeAlarmForZone(player, zoneId, "BusDepot")
end)

ZonePopulatedEvent.Event:Connect(function(player: Player, zoneId: string)
	local uid = player.UserId
	zonePopulated[uid] = zonePopulated[uid] or {}
	zonePopulated[uid][zoneId] = true
	flushPendingUpgradeAlarm(player, zoneId)
end)

ZoneReCreatedEvent.Event:Connect(function(player: Player, zoneId: string, mode: string)
	recomputeUpgradeAlarmForZone(player, zoneId, mode)
end)

local function seedExistingZonesForPlayer(player: Player)
	local zones = ZoneTracker.getAllZones(player)
	AirportState[player]  = AirportState[player]  or {}
	BusDepotState[player] = BusDepotState[player] or {}

	local data = PlayerDataService.GetSaveFileData(player)
	for zoneId, z in pairs(zones) do
		if z.mode == "Airport" and not AirportState[player][zoneId] then
			local rec = readTransitNode(data, "airport")
			reconcileUnlockFromTiersFrontier(rec) -- catch-up for airport too
			AirportState[player][zoneId] = rec
			fireAirportSnapshot(player, zoneId, rec)
			recomputeUpgradeAlarmForZone(player, zoneId, "Airport")
		elseif (z.mode == "BusDepot" or z.mode == "Bus Depot") and not BusDepotState[player][zoneId] then
			local rec = readTransitNode(data, "busDepot")
			BusDepotState[player][zoneId] = rec
			fireBusSnapshot(player, zoneId, rec)
			recomputeUpgradeAlarmForZone(player, zoneId, "BusDepot")
		end
	end
end

for _, plr in ipairs(Players:GetPlayers()) do seedExistingZonesForPlayer(plr) end
Players.PlayerAdded:Connect(function(plr) task.defer(seedExistingZonesForPlayer, plr) end)

local TransitTickets = {}
TransitTickets.AirportState      = AirportState
TransitTickets.BusDepotState     = BusDepotState
TransitTickets._ShowUpgradeAlarm = showUpgradeAlarmNow
TransitTickets._HideUpgradeAlarm = hideUpgradeAlarm
TransitTickets._RecomputeForZone = recomputeUpgradeAlarmForZone
return TransitTickets
