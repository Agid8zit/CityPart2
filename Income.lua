local VERBOSE_LOG = false
local function log(...)
	if VERBOSE_LOG then print(...) end
end

log("[Income] Module loaded (sharded + scheduled)")

--// Services
local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local S3             = game:GetService("ServerScriptService")
local RS             = game:GetService("ReplicatedStorage")
local RunServiceScheduler = require(RS.Scripts.RunServiceScheduler)

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
local RemoteEvents    = Events:FindFirstChild("RemoteEvents")
local Balancing       = RS:WaitForChild("Balancing")

local Balance = require(Balancing:WaitForChild("BalanceEconomy"))
local PlayerDataInterfaceService = require(game.ServerScriptService.Services.PlayerDataInterfaceService)

--// =========================
--// Configuration
--// =========================

-- How often the authoritative payout applies (seconds)
local TICK_INTERVAL = 5

-- Aim to sweep each player's entire tile queue in this time (seconds)
local CACHE_SWEEP_TARGET = 3.0

-- Passive fallback worklist refresh if no events are fired (seconds)
local WORKLIST_REFRESH_INTERVAL = 30

-- Per-player min/max tiles computed when that player is processed
local MIN_ITEMS_PER_STEP = 10
local MAX_ITEMS_PER_STEP = 1000

-- -------------------------
-- Scheduler / budgeting
-- -------------------------
-- Target: visit each player roughly this often (seconds).
-- The tile processor uses actual per-player dt, so this is a soft target.
local PLAYER_VISIT_TARGET_SEC = 1.0

-- Hard cap on CPU time spent inside Heartbeat’s per-frame work (ms)
local HEARTBEAT_BUDGET_MS = 2.5

-- When doing long, low-frequency loops (payout / rebuild),
-- yield every this many ms to avoid long stalls
local LONG_TASK_CHUNK_MS = 4.0

-- =========================
-- Internal state
-- =========================
-- Per-player rolling state
-- playerWork[playerId] = { queue = {...}, idx = 1, keySet = { [key]=true }, lastProcessedAt = time() }
local playerWork = {}

-- Caches
-- tileIncomeCache[playerId][tileKey] = integer income for that tile (rounded, post tile multipliers)
local tileIncomeCache = {}
-- tileZoneIndex[playerId][tileKey] = zoneId (for fast removal from zone sums)
local tileZoneIndex = {}
-- zoneSums[playerId][zoneId] = sum of tile incomes in that zone (integer)
local zoneSums = {}
-- playerBaseIncome[playerId] = sum of all zoneSums (integer) before coverage/rate and pre x2 Money
local playerBaseIncome = {}
-- per-tick payout cache (authoritative pay last applied)
local playerIncomeCache = {} -- [userId] = pay per tick (integer)
local playerLastPayoutAt = {} -- [userId] = time() last payout was applied
local _coverageWarnAt = {}    -- [userId] = os.clock() last warn (to rate-limit)

-- Active player roster for round-robin scheduling
local activePlayers = {}       -- array of Player
local activeIndexByUserId = {} -- [userId] = index in activePlayers
local rrIndex = 1              -- round-robin cursor (1-based)

-- Debounced rebuild flags (optional coalescing when many events fire)
local pendingRebuild = {}      -- [userId] = true

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
	tileIncomeCache[playerId]  = tileIncomeCache[playerId] or {}
	zoneSums[playerId]         = zoneSums[playerId] or {}
	playerBaseIncome[playerId] = playerBaseIncome[playerId] or 0
	playerLastPayoutAt[playerId] = playerLastPayoutAt[playerId] or time()
	tileZoneIndex[playerId]    = tileZoneIndex[playerId] or {}
	if not playerWork[playerId] then
		playerWork[playerId] = { queue = {}, idx = 1, keySet = {}, lastProcessedAt = time() }
	else
		playerWork[playerId].lastProcessedAt = playerWork[playerId].lastProcessedAt or time()
	end
end

local function clearPlayerState(playerId)
	playerWork[playerId] = nil
	tileIncomeCache[playerId] = nil
	zoneSums[playerId] = nil
	playerBaseIncome[playerId] = nil
	tileZoneIndex[playerId] = nil
	playerIncomeCache[playerId] = nil
	playerLastPayoutAt[playerId] = nil
	pendingRebuild[playerId] = nil
end

-- Active roster helpers
local function addActivePlayer(player)
	local pid = player.UserId
	if activeIndexByUserId[pid] then return end
	table.insert(activePlayers, player)
	activeIndexByUserId[pid] = #activePlayers
	ensurePlayerTables(pid)
	-- Build initial worklist a tiny bit later to allow upstream systems to initialize
	task.defer(function()
		if player.Parent then
			-- Queue a rebuild to coalesce with other joins/changes
			pendingRebuild[pid] = true
		end
	end)
end

local function removeActivePlayer(player)
	local pid = player.UserId
	local idx = activeIndexByUserId[pid]
	if not idx then return end

	-- compact remove
	local lastIndex = #activePlayers
	local lastPlayer = activePlayers[lastIndex]
	activePlayers[idx] = lastPlayer
	activePlayers[lastIndex] = nil
	activeIndexByUserId[pid] = nil
	if lastPlayer then
		activeIndexByUserId[lastPlayer.UserId] = idx
	end

	-- keep rrIndex in range
	if rrIndex > #activePlayers then
		rrIndex = 1
	end

	clearPlayerState(pid)
end

-- Build / refresh the tile worklist (cheap compared to computing income)
local function rebuildWorklistForPlayer(player)
	local playerId = player.UserId
	ensurePlayerTables(playerId)

	local work      = playerWork[playerId]
	local newQueue  = {}
	local newKeySet = {}

	-- per-player stats table holds the zones we care about
	local statsByZone = DistrictStatsModule.getStatsForPlayer(playerId)
	for zoneId, _ in pairs(statsByZone) do
		local zone = ZoneTracker.getZoneById(player, zoneId)
		if zone and zone.gridList then
			for _, coord in ipairs(zone.gridList) do
				local key = tileKey(zoneId, coord.x, coord.z)
				newKeySet[key] = true
				newQueue[#newQueue + 1] = {
					zoneId = zoneId,
					mode = zone.mode,
					x = coord.x,
					z = coord.z,
					key = key,
				}
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
local function processTilesForPlayer(player, dtForPlayer)
	local playerId = player.UserId
	local work = playerWork[playerId]
	if not work or #work.queue == 0 then
		work.lastProcessedAt = time()
		return
	end

	-- target to sweep the whole queue in CACHE_SWEEP_TARGET seconds
	local targetPerSecond = math.max(#work.queue / CACHE_SWEEP_TARGET, MIN_ITEMS_PER_STEP)
	local itemsThisStep = math.floor(targetPerSecond * math.max(dtForPlayer, 1/60))
	itemsThisStep = math.max(itemsThisStep, MIN_ITEMS_PER_STEP)
	itemsThisStep = math.min(itemsThisStep, MAX_ITEMS_PER_STEP, #work.queue)

	local tCache = tileIncomeCache[playerId]
	local zSums  = zoneSums[playerId]
	local zIndex = tileZoneIndex[playerId]

	local baseSum = playerBaseIncome[playerId] or 0
	local idx = work.idx

	for _ = 1, itemsThisStep do
		local item = work.queue[idx]
		if not item then
			idx = 1
			item = work.queue[idx]
			if not item then break end
		end

		local newIncome = computeSingleTileIncome(player, item.mode, item.zoneId, item.x, item.z)

		local oldIncome = tCache[item.key]
		if oldIncome ~= newIncome then
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
	work.lastProcessedAt = time()
end

-- Coverage computation preserved
local function computeCoverage(player)
	-- Use served demand only so disconnected zones don't tank coverage.
	local totalsReq  = ZoneRequirementsChecker.getEffectiveServedTotals(player)
		or DistrictStatsModule.getTotalsForPlayer(player)
	local produced   = ZoneRequirementsChecker.getEffectiveProduction(player)
		or DistrictStatsModule.getUtilityProduction(player)

	local coverW = (totalsReq.water  > 0) and math.min(1, (produced.water or 0) / totalsReq.water)  or 1
	local coverP = (totalsReq.power  > 0) and math.min(1, (produced.power or 0) / totalsReq.power)  or 1

	return math.min(coverW, coverP)
end

-- =========================
-- Payout helpers (shared between scheduled + interactive triggers)
-- =========================
local function computePayPerTickForPlayer(player)
	local playerId = player.UserId
	ensurePlayerTables(playerId)

	local baseTotal = playerBaseIncome[playerId] or 0

	if PlayerDataInterfaceService.HasGamepass(player, "x2 Money") then
		baseTotal = baseTotal * 2
	end

	local coverage = computeCoverage(player)
	local rate = Balance.IncomeRate and Balance.IncomeRate.TICK_INCOME or 1

	local payPerTick = math.floor(baseTotal * coverage * rate + 0.5)

	-- Cache the per-tick value for clients/diagnostics
	playerIncomeCache[playerId] = payPerTick

	return payPerTick, coverage, baseTotal
end

local function payoutPlayerNow(player, now, reason, saveData)
	if not player or not player.Parent then
		return 0, 0
	end

	-- Require a live save to avoid charging/paying ghost players
	saveData = saveData or PlayerDataService.GetSaveFileData(player)
	if not saveData then
		return 0, 0
	end

	now = now or time()
	local playerId = player.UserId
	ensurePlayerTables(playerId)

	local payPerTick, coverage, baseTotal = computePayPerTickForPlayer(player)
	local lastPaidAt = playerLastPayoutAt[playerId] or now
	local dt = math.max(0, now - lastPaidAt)

	-- Pro-rate against the configured tick interval so ad-hoc payouts stay fair
	local payoutAmount = math.floor(payPerTick * (dt / TICK_INTERVAL) + 0.5)
	playerLastPayoutAt[playerId] = now

	-- Throttled warning for collapsed income/coverage
	if coverage < 0.15 or payPerTick == 0 then
		local nowClock = os.clock()
		local lastWarn = _coverageWarnAt[playerId] or 0
		if nowClock - lastWarn >= 10 then
			_coverageWarnAt[playerId] = nowClock
			local statsByZone = DistrictStatsModule.getStatsForPlayer(playerId)
			local zoneCount = 0
			for _ in pairs(statsByZone) do zoneCount += 1 end
			local totalsReq = ZoneRequirementsChecker.getEffectiveServedTotals(player)
				or DistrictStatsModule.getTotalsForPlayer(player)
				or { water = 0, power = 0 }
			local produced = ZoneRequirementsChecker.getEffectiveProduction(player)
				or DistrictStatsModule.getUtilityProduction(player)
				or { water = 0, power = 0 }

			warn(string.format(
				"[Income] Low coverage/pay for %s (uid=%d): coverage=%.3f pay=%d base=%d zones=%d reqW/P=%.1f/%.1f prodW/P=%.1f/%.1f",
				player.Name,
				playerId,
				coverage,
				payPerTick,
				baseTotal,
				zoneCount,
				(totalsReq.water or 0),
				(totalsReq.power or 0),
				(produced.water or 0),
				(produced.power or 0)
			))
		end
	end

	if payoutAmount ~= 0 then
		EconomyService.adjustBalance(player, payoutAmount)
	end
	StatsChanged:Fire(player)

	if VERBOSE_LOG and reason then
		log(("[PAY %s] %s dt=%.2fs payPerTick=%d applied=%d"):format(
			reason,
			player.Name,
			dt,
			payPerTick,
			payoutAmount
		))
	end

	return payoutAmount, payPerTick
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
-- Income payout (authoritative, chunked)
-- =========================
local function doPayoutChunked()
	local startCpu = os.clock()
	for i = 1, #activePlayers do
		local player = activePlayers[i]
		-- Guard per-player payout so a single bad entry cannot kill the whole loop.
		local ok, err = pcall(function()
			if not player or not player.Parent then
				return
			end

			local saveData = PlayerDataService.GetSaveFileData(player)
			if not saveData then
				return
			end

			payoutPlayerNow(player, time(), "scheduled", saveData)
		end)

		if not ok then
			warn(("[Income] payout skipped for %s: %s"):format(
				(player and player.Name) or ("player#" .. tostring(i)),
				tostring(err)
				))
		end

		-- Yield cooperatively under long-task budget
		if (os.clock() - startCpu) * 1000.0 >= LONG_TASK_CHUNK_MS then
			startCpu = os.clock()
			task.wait() -- yield to the scheduler
		end
	end
end

-- =========================
-- Event hooks (optional but recommended)
-- =========================
local function tryConnectBuildEvents()
	local BuildChanged = BindableEvents:FindFirstChild("BuildChanged")  -- payload: {player, ...}
	if BuildChanged and BuildChanged.Event then
		BuildChanged.Event:Connect(function(player)
			if player and player.UserId then
				pendingRebuild[player.UserId] = true
			end
		end)
	end

	local ZoneWealthChanged = BindableEvents:FindFirstChild("ZoneWealthChanged") -- {player, zoneId, x, z}
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
						-- If unknown, trigger a refresh (layout likely changed)
						pendingRebuild[pId] = true
					end
				end
			end
		end)
	end
end

local function tryConnectInteractivePayoutEvents()
	if not RemoteEvents then
		return
	end

	local selectZoneEvent = RemoteEvents:FindFirstChild("SelectZoneType")
	if selectZoneEvent then
		selectZoneEvent.OnServerEvent:Connect(function(player)
			payoutPlayerNow(player, time(), "SelectZoneType")
		end)
	end

	local gridSelectionEvent = RemoteEvents:FindFirstChild("GridSelection")
	if gridSelectionEvent then
		gridSelectionEvent.OnServerEvent:Connect(function(player)
			payoutPlayerNow(player, time(), "GridSelection")
		end)
	end
end

-- =========================
-- Heartbeat: round-robin per-player sharded processing
-- =========================
RunServiceScheduler.onHeartbeat(function(dt)
	-- Nothing to do if no active players
	local n = #activePlayers
	if n == 0 then return end

	local frameStart = os.clock()

	-- Derive how many players to visit this frame from the target period
	local framesToSweepAll = math.max(1, math.floor(PLAYER_VISIT_TARGET_SEC / math.max(dt, 1/120)))
	local playersThisFrame = math.max(1, math.ceil(n / framesToSweepAll))

	-- Round-robin over the activePlayers ring
	for _ = 1, playersThisFrame do
		if n == 0 then break end
		if rrIndex > n then rrIndex = 1 end

		local player = activePlayers[rrIndex]
		rrIndex = rrIndex + 1

		if player and player.Parent then
			local SaveData = PlayerDataService.GetSaveFileData(player)
			if SaveData then
				local pid = player.UserId
				ensurePlayerTables(pid)
				local work = playerWork[pid]
				local now = time()
				local dtForPlayer = now - (work.lastProcessedAt or now)
				-- Bound dtForPlayer to avoid massive bursts if a player was idle long
				if dtForPlayer > 2.0 then dtForPlayer = 2.0 end
				processTilesForPlayer(player, dtForPlayer)
			end
		end

		-- Respect per-frame CPU budget
		if (os.clock() - frameStart) * 1000.0 >= HEARTBEAT_BUDGET_MS then
			break
		end
	end
end)

-- =========================
-- Scheduled loops (off-Heartbeat)
-- =========================
local function startPayoutLoop()
	task.spawn(function()
		while true do
			task.wait(TICK_INTERVAL)
			local ok, err = pcall(doPayoutChunked)
			if not ok then
				warn("[Income] payout loop error: " .. tostring(err))
			end
		end
	end)
end

local function startPassiveWorklistRefreshLoop()
	task.spawn(function()
		while true do
			task.wait(WORKLIST_REFRESH_INTERVAL)
			-- Chunked rebuild across players to avoid stalls
			local startCpu = os.clock()
			for i = 1, #activePlayers do
				local player = activePlayers[i]
				if player and player.Parent then
					local SaveData = PlayerDataService.GetSaveFileData(player)
					if SaveData then
						rebuildWorklistForPlayer(player)
					end
				end
				if (os.clock() - startCpu) * 1000.0 >= LONG_TASK_CHUNK_MS then
					startCpu = os.clock()
					task.wait()
				end
			end
		end
	end)
end

-- Coalesced flush for pending rebuild requests from events
local function startRebuildFlushLoop()
	task.spawn(function()
		while true do
			task.wait(0.2) -- small debounce window to batch bursts
			local startCpu = os.clock()
			for pid, flagged in pairs(pendingRebuild) do
				if flagged then
					pendingRebuild[pid] = nil
					-- Only rebuild if the player is still around
					local idx = activeIndexByUserId[pid]
					if idx then
						local player = activePlayers[idx]
						if player and player.Parent then
							rebuildWorklistForPlayer(player)
						end
					end
				end
				if (os.clock() - startCpu) * 1000.0 >= LONG_TASK_CHUNK_MS then
					startCpu = os.clock()
					task.wait()
				end
			end
		end
	end)
end

-- =========================
-- Player lifecycle
-- =========================
Players.PlayerAdded:Connect(function(player)
	addActivePlayer(player)
end)

Players.PlayerRemoving:Connect(function(player)
	removeActivePlayer(player)
end)

-- Seed current players (in case the module loads after some have joined)
for _, p in ipairs(Players:GetPlayers()) do
	addActivePlayer(p)
end

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
	log(("[INCOME/s] %s: %d"):format(player.Name, perSecond))
	return perSecond
end

-- Immediate payout helper (pro-rated to avoid double-paying)
function Income.payoutNow(player, reason)
	return payoutPlayerNow(player, time(), reason or "manual")
end

function Income.setBalance(player, amount)
	EconomyService.setBalance(player, amount)
	log(("[SET] %s balance to %d"):format(player.Name, amount))
end

function Income.addMoney(player, amount)
	EconomyService.adjustBalance(player, amount)
	log(("[ADD] %s: +%d → %d"):format(
		player.Name, amount, EconomyService.getBalance(player)
		))
end

function Income.removeMoney(player, amount)
	EconomyService.adjustBalance(player, -amount)
	log(("[REMOVE] %s: -%d → %d"):format(
		player.Name, amount, EconomyService.getBalance(player)
		))
end

-- ===== Optional ops/debug helpers =====
function Income.forceRebuildQueue(player)
	if player and player.UserId then
		pendingRebuild[player.UserId] = true
	end
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

	-- Clear existing caches (mutate in place)
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
	pendingRebuild[playerId] = true
end

function Income.debugGetPlayerCacheStats(player)
	local pid = player.UserId
	local work  = playerWork[pid]
	local tiles = tileIncomeCache[pid]
	local zones = zoneSums[pid]
	local function count(t) local c=0; for _ in pairs(t or {}) do c+=1 end; return c end
	return {
		queueSize = work and #work.queue or 0,
		tileCacheSize = count(tiles),
		zoneCount = count(zones),
		baseIncome = playerBaseIncome[pid] or 0,
		lastProcessedAgo = work and (time() - (work.lastProcessedAt or time())) or nil,
	}
end

-- Initialize optional event hooks and scheduled loops
tryConnectBuildEvents()
tryConnectInteractivePayoutEvents()
startRebuildFlushLoop()
startPassiveWorklistRefreshLoop()
startPayoutLoop()

return Income
