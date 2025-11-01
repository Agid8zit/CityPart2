print("[Income] Module loaded (incremental)")

--// Services
local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local S3             = game:GetService("ServerScriptService")
local RS             = game:GetService("ReplicatedStorage")

--// Server modules
local Build          = S3:WaitForChild("Build")
local Zones          = Build:WaitForChild("Zones")
local ZoneMgr        = Zones:WaitForChild("ZoneManager")
local ZoneTracker    = require(ZoneMgr:WaitForChild("ZoneTracker"))
local CityInteractions = require(ZoneMgr:WaitForChild("CityInteraction"))
local EconomyService = require(ZoneMgr:WaitForChild("EconomyService"))

local DistrictStatsModule = require(script.Parent:WaitForChild("DistrictStatsModule"))
local PlayerDataService = require(S3.Services.PlayerDataService)
local ZoneRequirementsChecker = require(ZoneMgr:WaitForChild("ZoneRequirementsCheck"))

--// Events & data
local Events          = RS:WaitForChild("Events")
local BindableEvents  = Events:WaitForChild("BindableEvents")
local StatsChanged    = BindableEvents:WaitForChild("StatsChanged")
local Balancing 	  = RS:WaitForChild("Balancing")

local Balance = require(Balancing:WaitForChild("BalanceEconomy"))
local PlayerDataInterfaceService = require(game.ServerScriptService.Services.PlayerDataInterfaceService)

--// =========================
--// Configuration
--// =========================
local TICK_INTERVAL = 5                -- seconds between income payouts
local CACHE_SWEEP_TARGET = 3.0         -- seconds to cover a player's whole tile queue once
local WORKLIST_REFRESH_INTERVAL = 30   -- seconds between passive worklist refresh (if no events)
local MIN_ITEMS_PER_STEP = 10          -- per-player minimum tile computations per Heartbeat
local MAX_ITEMS_PER_STEP = 1000        -- guardrail per-player maximum per Heartbeat (avoid spikes)

--// =========================
--// Internal state
--// =========================
local lastPayoutTick = 0
local lastWorklistRefresh = 0

-- Per-player rolling state
-- playerWork[playerId] = { queue = { {zoneId, mode, x, z, key}... }, idx = 1, keySet = { [key]=true } }
local playerWork = {}

-- Caches
-- tileIncomeCache[playerId][tileKey] = integer income for that tile (rounded, post tile multipliers)
local tileIncomeCache = {}
-- tileZoneIndex[playerId][tileKey] = zoneId (for fast removal from zone sums)
local tileZoneIndex = {}
-- zoneSums[playerId][zoneId] = sum of tile incomes in that zone (integer)
local zoneSums = {}
-- playerBaseIncome[playerId] = sum of all zoneSums (integer), *before* coverage/rate and *before* x2 Money?  (we apply x2 later to match your semantics)
local playerBaseIncome = {}
-- what you already had; exposed via getIncomePerSecond
local playerIncomeCache = {} -- [userId] = pay awarded per tick (integer)

-- =========================
-- Helpers
-- =========================
local function tileKey(zoneId, gx, gz)
	return tostring(zoneId) .. ":" .. tostring(gx) .. "," .. tostring(gz)
end

local function tileHasAllRequirements(player, zoneId, gx, gz)
	return ZoneTracker.getTileRequirement(player, zoneId, gx, gz, "Road")  == true
		and ZoneTracker.getTileRequirement(player, zoneId, gx, gz, "Water") == true
		and ZoneTracker.getTileRequirement(player, zoneId, gx, gz, "Power") == true
end

local function computeSingleTileIncome(player, mode, zoneId, gx, gz)
	if not tileHasAllRequirements(player, zoneId, gx, gz) then
		return 0
	end

	local state = ZoneTracker.getGridWealth(player, zoneId, gx, gz) or "Poor"
	local conf  = Balance.StatConfig[mode] and Balance.StatConfig[mode][state]
	local base  = (conf and conf.income) or 0

	local mulNeg = CityInteractions.getTileIncomePollutionMultiplier(player, zoneId, gx, gz)
	local mulPos = CityInteractions.getTileIncomePositiveMultiplier(player, zoneId, gx, gz, mode)

	-- Per-tile rounding preserved
	local tileIncome = math.floor(base * mulNeg * mulPos + 0.5)
	return tileIncome
end

local function ensurePlayerTables(playerId)
	tileIncomeCache[playerId] = tileIncomeCache[playerId] or {}
	zoneSums[playerId]        = zoneSums[playerId] or {}
	playerBaseIncome[playerId] = playerBaseIncome[playerId] or 0
	tileZoneIndex[playerId]   = tileZoneIndex[playerId] or {}
	playerWork[playerId]      = playerWork[playerId] or { queue = {}, idx = 1, keySet = {} }
end

local function clearPlayerState(playerId)
	playerWork[playerId] = nil
	tileIncomeCache[playerId] = nil
	zoneSums[playerId] = nil
	playerBaseIncome[playerId] = nil
	tileZoneIndex[playerId] = nil
	playerIncomeCache[playerId] = nil
end

-- Build / refresh the tile worklist (cheap compared to computing income)
local function rebuildWorklistForPlayer(player)
	local playerId = player.UserId
	ensurePlayerTables(playerId)

	local work      = playerWork[playerId]
	local newQueue  = {}
	local newKeySet = {}

	-- We iterate zones using your stats table keys because it's already per-player scoped
	local statsByZone = DistrictStatsModule.getStatsForPlayer(playerId)
	for zoneId, _ in pairs(statsByZone) do
		local zone = ZoneTracker.getZoneById(player, zoneId)
		if zone and zone.gridList then
			for _, coord in ipairs(zone.gridList) do
				local key = tileKey(zoneId, coord.x, coord.z)
				newKeySet[key] = true
				table.insert(newQueue, {
					zoneId = zoneId,
					mode = zone.mode,
					x = coord.x,
					z = coord.z,
					key = key,
				})
			end
		end
	end

	-- Drop any cached tiles that no longer exist in the world
	local tCache = tileIncomeCache[playerId]
	local zSums  = zoneSums[playerId]
	local zIndex = tileZoneIndex[playerId]
	local baseSum = playerBaseIncome[playerId] or 0

	for key, oldVal in pairs(tCache) do
		if not newKeySet[key] then
			-- This tile vanished; subtract from sums
			local oldIncome = oldVal or 0
			local zId = zIndex[key]
			if zId ~= nil then
				zSums[zId] = (zSums[zId] or 0) - oldIncome
			end
			baseSum = baseSum - oldIncome
			tCache[key] = nil
			zIndex[key] = nil
		end
	end

	playerBaseIncome[playerId] = baseSum
	work.queue = newQueue
	work.keySet = newKeySet

	-- Keep idx within bounds
	if work.idx > #work.queue then
		work.idx = 1
	end
end

-- Process a bounded number of tiles for a given player
local function processTilesForPlayer(player, dt)
	local playerId = player.UserId
	local work = playerWork[playerId]
	if not work or #work.queue == 0 then
		return
	end

	-- target to sweep the whole queue in CACHE_SWEEP_TARGET seconds
	local targetPerSecond = math.max(#work.queue / CACHE_SWEEP_TARGET, MIN_ITEMS_PER_STEP)
	local itemsThisStep = math.floor(targetPerSecond * math.max(dt, 1/60))
	itemsThisStep = math.max(itemsThisStep, MIN_ITEMS_PER_STEP)
	itemsThisStep = math.min(itemsThisStep, MAX_ITEMS_PER_STEP, #work.queue)

	local tCache = tileIncomeCache[playerId]
	local zSums  = zoneSums[playerId]
	local zIndex = tileZoneIndex[playerId]

	local baseSum = playerBaseIncome[playerId] or 0
	local idx = work.idx

	for i = 1, itemsThisStep do
		local item = work.queue[idx]
		if not item then
			-- Should not happen, but guard
			idx = 1
			item = work.queue[idx]
			if not item then break end
		end

		local newIncome = computeSingleTileIncome(player, item.mode, item.zoneId, item.x, item.z)

		local oldIncome = tCache[item.key]
		if oldIncome ~= newIncome then
			-- update zone and player sums
			local delta = (newIncome or 0) - (oldIncome or 0)
			zSums[item.zoneId] = (zSums[item.zoneId] or 0) + delta
			baseSum = baseSum + delta
			tCache[item.key] = newIncome
			zIndex[item.key] = item.zoneId
		end

		idx = idx + 1
		if idx > #work.queue then idx = 1 end
	end

	work.idx = idx
	playerBaseIncome[playerId] = baseSum
end

-- Coverage computation preserved from your original logic
local function computeCoverage(player)
	local totalsReq  = DistrictStatsModule.getTotalsForPlayer(player)
	local produced   = ZoneRequirementsChecker.getEffectiveProduction(player)
		or DistrictStatsModule.getUtilityProduction(player)

	local coverW = (totalsReq.water  > 0) and math.min(1, (produced.water or 0) / totalsReq.water)  or 1
	local coverP = (totalsReq.power  > 0) and math.min(1, (produced.power or 0) / totalsReq.power)  or 1

	return math.min(coverW, coverP)
end

-- =========================
-- Legacy exact calculation (kept for ops / diagnostics)
-- =========================
local function calculateZoneIncome_exact(player, zoneData)
	local total = 0
	for _, coord in ipairs(zoneData.gridList) do
		if tileHasAllRequirements(player, zoneData.zoneId, coord.x, coord.z) then
			local state = ZoneTracker.getGridWealth(player, zoneData.zoneId, coord.x, coord.z) or "Poor"
			local conf  = Balance.StatConfig[zoneData.mode] and Balance.StatConfig[zoneData.mode][state]
			local base  = (conf and conf.income) or 0

			local mulNeg = CityInteractions.getTileIncomePollutionMultiplier(player, zoneData.zoneId, coord.x, coord.z)
			local mulPos = CityInteractions.getTileIncomePositiveMultiplier(player, zoneData.zoneId, coord.x, coord.z, zoneData.mode)
			local tileIncome = math.floor(base * mulNeg * mulPos + 0.5)

			total += tileIncome
		end
	end

	if PlayerDataInterfaceService.HasGamepass(player, "x2 Money") then
		total = total * 2
	end

	return total
end

-- =========================
-- Income payout (authoritative)
-- =========================
local function doPayout()
	for _, player in ipairs(Players:GetPlayers()) do
		local SaveData = PlayerDataService.GetSaveFileData(player)
		if not SaveData then
			continue
		end

		local playerId = player.UserId
		ensurePlayerTables(playerId)

		-- 1) Get base income from cache (sum of per-tile rounded incomes)
		local baseTotal = playerBaseIncome[playerId] or 0

		-- 2) Gamepass
		if PlayerDataInterfaceService.HasGamepass(player, "x2 Money") then
			baseTotal = baseTotal * 2
		end

		-- 3) Coverage and global rate scaling
		local coverage = computeCoverage(player)
		local rate = Balance.IncomeRate and Balance.IncomeRate.TICK_INCOME or 1

		local pay = math.floor(baseTotal * coverage * rate + 0.5)

		-- cache per-tick
		playerIncomeCache[playerId] = pay

		-- 4) Apply and 5) notify
		EconomyService.adjustBalance(player, pay)
		StatsChanged:Fire(player)
	end
end

-- =========================
-- Event hooks (optional but recommended)
-- =========================
-- If your game broadcasts build/zone changes, hook here so the worklist updates immediately
local function tryConnectBuildEvents()
	local BuildChanged = BindableEvents:FindFirstChild("BuildChanged")  -- e.g., payload: {player, zoneId, action, coords}
	if BuildChanged and BuildChanged.Event then
		BuildChanged.Event:Connect(function(player)
			if player and player.UserId then
				rebuildWorklistForPlayer(player)
			end
		end)
	end

	local ZoneWealthChanged = BindableEvents:FindFirstChild("ZoneWealthChanged") -- e.g., {player, zoneId, x, z}
	if ZoneWealthChanged and ZoneWealthChanged.Event then
		ZoneWealthChanged.Event:Connect(function(player, zoneId, gx, gz)
			-- Fast-path: push that one tile to the front to update ASAP
			if player and player.UserId and zoneId and gx and gz then
				local pId = player.UserId
				ensurePlayerTables(pId)
				local work = playerWork[pId]
				if work and work.keySet then
					local key = tileKey(zoneId, gx, gz)
					if work.keySet[key] then
						-- Put it next in line by moving idx back one step (cheap heuristic)
						work.idx = math.max(1, work.idx - 1)
					else
						-- If unknown, trigger a refresh (layout changed)
						rebuildWorklistForPlayer(player)
					end
				end
			end
		end)
	end
end

-- =========================
-- Heartbeat loop
-- =========================
RunService.Heartbeat:Connect(function(dt)
	-- 1) Continuous incremental processing
	for _, player in ipairs(Players:GetPlayers()) do
		local SaveData = PlayerDataService.GetSaveFileData(player)
		if SaveData then
			ensurePlayerTables(player.UserId)
			processTilesForPlayer(player, dt)
		end
	end

	-- 2) Periodic payout
	lastPayoutTick += dt
	if lastPayoutTick >= TICK_INTERVAL then
		doPayout()
		lastPayoutTick = 0
	end

	-- 3) Low-frequency passive worklist refresh (only if you don't have events)
	lastWorklistRefresh += dt
	if lastWorklistRefresh >= WORKLIST_REFRESH_INTERVAL then
		for _, player in ipairs(Players:GetPlayers()) do
			local SaveData = PlayerDataService.GetSaveFileData(player)
			if SaveData then
				rebuildWorklistForPlayer(player)
			end
		end
		lastWorklistRefresh = 0
	end
end)

-- =========================
-- Player lifecycle
-- =========================
Players.PlayerAdded:Connect(function(player)
	ensurePlayerTables(player.UserId)
	-- Build initial worklist a tiny bit later to allow upstream systems to initialize, if needed
	task.defer(function()
		rebuildWorklistForPlayer(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	clearPlayerState(player.UserId)
end)

-- =========================
-- Public API
-- =========================
local Income = {}

function Income.getBalance(player)
	return EconomyService.getBalance(player)
end

function Income.getIncomePerSecond(player)
	local incomePerTick = playerIncomeCache[player.UserId] or 0
	local perSecond     = incomePerTick / TICK_INTERVAL
	print(("[INCOME/s] %s: %d"):format(player.Name, perSecond))
	return perSecond
end

function Income.setBalance(player, amount)
	EconomyService.setBalance(player, amount)
	print(("[SET] %s balance to %d"):format(player.Name, amount))
end

function Income.addMoney(player, amount)
	EconomyService.adjustBalance(player, amount)
	print(("[ADD] %s: +%d → %d"):format(
		player.Name, amount, EconomyService.getBalance(player)
		))
end

function Income.removeMoney(player, amount)
	EconomyService.adjustBalance(player, -amount)
	print(("[REMOVE] %s: -%d → %d"):format(
		player.Name, amount, EconomyService.getBalance(player)
		))
end

-- ===== Optional ops/debug helpers =====
function Income.forceRebuildQueue(player)
	rebuildWorklistForPlayer(player)
end

function Income.forceFullRecalcForPlayer(player)
	-- Slow but exact; also refreshes caches to the exact values
	local playerId = player.UserId
	ensurePlayerTables(playerId)

	local total = 0
	local statsByZone = DistrictStatsModule.getStatsForPlayer(playerId)

	local tCache = tileIncomeCache[playerId]
	local zSums  = zoneSums[playerId]
	local zIndex = tileZoneIndex[playerId]
	local baseSum = 0

	-- Clear existing caches
	for k in pairs(tCache) do tCache[k] = nil end
	for z in pairs(zSums) do zSums[z] = 0 end
	for k in pairs(zIndex) do zIndex[k] = nil end

	for zoneId, _ in pairs(statsByZone) do
		local zone = ZoneTracker.getZoneById(player, zoneId)
		if zone and zone.gridList then
			local zTotal = calculateZoneIncome_exact(player, zone)
			zSums[zoneId] = zTotal
			total += zTotal

			-- Rebuild per-tile cache exactly (costly, but for diagnostic correctness)
			for _, coord in ipairs(zone.gridList) do
				local key = tileKey(zoneId, coord.x, coord.z)
				local income = computeSingleTileIncome(player, zone.mode, zoneId, coord.x, coord.z)
				tCache[key] = income
				zIndex[key] = zoneId
			end
		end
	end

	playerBaseIncome[playerId] = total
	rebuildWorklistForPlayer(player)
end

function Income.debugGetPlayerCacheStats(player)
	local pid = player.UserId
	local work  = playerWork[pid]
	local tiles = tileIncomeCache[pid]
	local zones = zoneSums[pid]
	return {
		queueSize = work and #work.queue or 0,
		tileCacheSize = tiles and (function(t) local c=0; for _ in pairs(t) do c+=1 end; return c end)(tiles) or 0,
		zoneCount = zones and (function(t) local c=0; for _ in pairs(t) do c+=1 end; return c end)(zones) or 0,
		baseIncome = playerBaseIncome[pid] or 0,
	}
end

-- Initialize optional event hooks
tryConnectBuildEvents()

return Income
