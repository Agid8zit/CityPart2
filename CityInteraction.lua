local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

-- Script/module tree
local Scripts       = ReplicatedStorage:WaitForChild("Scripts")
local Grid          = Scripts:WaitForChild("Grid")
local GridConfig    = require(Grid:WaitForChild("GridConfig"))
local GridUtil      = require(Grid:WaitForChild("GridUtil"))  -- used for grid→world conversion

local Events        = ReplicatedStorage:WaitForChild("Events")
local BindableEvents= Events:WaitForChild("BindableEvents")
local RemoteEvents  = Events:WaitForChild("RemoteEvents")
local NotifyPlayerEvent = RemoteEvents:FindFirstChild("NotifyPlayer")
local PlayUISoundRE = RemoteEvents:FindFirstChild("PlayUISound")
local UxpAlarmRE    = RemoteEvents:FindFirstChild("UxpAlarm")
if not UxpAlarmRE then
	-- create a dedicated RemoteEvent so upgrade/downgrade alarms can be client-only (no workspace replication)
	UxpAlarmRE = Instance.new("RemoteEvent")
	UxpAlarmRE.Name = "UxpAlarm"
	UxpAlarmRE.Parent = RemoteEvents
end

local S3            = game:GetService("ServerScriptService")
local Build         = S3:WaitForChild("Build")
local DST           = Build:WaitForChild("Districts")
local STS           = DST:WaitForChild("Stats")
local ZonesFolder   = Build:WaitForChild("Zones")
local CC            = ZonesFolder:WaitForChild("CoreConcepts")
local Districts     = CC:WaitForChild("Districts")
local BuildingGen   = Districts:WaitForChild("Building Gen")

-- External modules (typed as any to avoid strict type mismatches across boundaries)
local ZoneTracker: any             = require(script.Parent:WaitForChild("ZoneTracker"))
local XPManager: any               = require(STS:WaitForChild("XPManager"))
local BuildingGeneratorModule: any = require(BuildingGen:WaitForChild("BuildingGenerator"))
local Balance: any                 = require(ReplicatedStorage:WaitForChild("Balancing"):WaitForChild("BalanceEconomy"))
local Interactions				   = require(ReplicatedStorage:WaitForChild("Balancing"):WaitForChild("BalanceInteractions"))

-- Grid
local GRID_SIZE: number = GridConfig.GRID_SIZE

local _applyLock: { [Player]: { [string]: boolean } } = {}
-- player -> zoneId -> "x|z" -> wealth ("Poor"|"Medium"|"Wealthy")
local _pendingWealth: { [Player]: { [string]: { [string]: string } } } = {}
-- player -> zoneId = awaiting first ZonePopulated
local _pendingPopulate: { [Player]: { [string]: boolean } } = {}
-- player -> zoneId queued for a deferred bulk rebuild (zone still populating)
local _pendingBulkRebuild: { [Player]: { [string]: boolean } } = {}

local function _markZonePending(player: Player, zoneId: string)
	if not (player and typeof(zoneId) == "string") then return end
	_pendingPopulate[player] = _pendingPopulate[player] or {}
	_pendingPopulate[player][zoneId] = true
end

local function _clearZonePending(player: Player, zoneId: string)
	local map = _pendingPopulate[player]
	if not map then return end
	map[zoneId] = nil
	if not next(map) then
		_pendingPopulate[player] = nil
	end
end

local function _isZonePending(player: Player, zoneId: string): boolean
	local map = _pendingPopulate[player]
	return (map and map[zoneId]) or false
end

local function _queueBulkRebuild(player: Player, zoneId: string)
	if not (player and typeof(zoneId) == "string") then return end
	_pendingBulkRebuild[player] = _pendingBulkRebuild[player] or {}
	_pendingBulkRebuild[player][zoneId] = true
end

-- ==== Tunables / Guardrails ====
local ADJACENCY_RADIUS = 5 -- interpreted as *diameter in cells*; the circular radius is floor(ADJACENCY_RADIUS/2)
local BULK_REBUILD_THRESHOLD = 4

local DOWNGRADE_GRACE_SEC = 20
local HYSTERESIS = {
	MediumUp   = 0,  WealthUp   = 0,
	MediumDown = 2,  WealthDown = 2,
}

-- === Pollution CLOCK (repeaters) ===
local POLLUTION_CLOCK_PERIOD_SEC       = 10     -- seconds between re-alarms
local POLLUTION_CLOCK_JITTER_SEC       = 2.0    -- +/- jitter to de-sync zone clocks
local POLLUTION_CLOCK_SILENCE_AFTER_OK = 3      -- stop the clock after N consecutive OK checks
local POLLUTION_CLOCK_MAX_PER_TICK     = 30

-- Exclusions
local IGNORE_ZONE_TYPES: { [string]: boolean } = {
	WaterPipe  = true,
	PowerLines = true,
	DirtRoad   = true,
}
local UXP_IGNORE_ZONE_TYPES: { [string]: boolean } = {
	WaterPipe  = true,
	PowerLines = true,
	DirtRoad   = true,
}

-- Synergy
local SYNERGY_UPGRADE_THRESHOLD = 10
local VALID_ZONE_TYPES: { [string]: boolean } = {
	Residential  = true,
	Commercial   = true,
	Industrial   = true,
	ResDense     = true,
	CommDense    = true,
	IndusDense   = true,
	WaterTower   = true, -- participates in synergy
}

local WEALTHED_ZONES: { [string]: boolean } = {
	Residential = true, Commercial = true, Industrial = true,
	ResDense    = true, CommDense   = true, IndusDense   = true,
}


-- ===== Types =====
type GridTile = { x: number, z: number }
type BoundingBox = { minX: number, maxX: number, minZ: number, maxZ: number }
type ZoneData = {
	zoneId: string,
	mode: string,
	gridList: { GridTile },
	player: Player,
	boundingBox: BoundingBox,
}

-- ===== Config wires with safe fallbacks =====
local UXP_RADIUS     = (Balance and Balance.UxpConfig and Balance.UxpConfig.Radius) or {}
local UXP_VALUES     = (Balance and Balance.UxpConfig and Balance.UxpConfig.Value) or {}
local BUILDING_TIERS = (Balance and Balance.UxpConfig and Balance.UxpConfig.Tier) or {}
local CATEGORY       = (Balance and Balance.UxpConfig and Balance.UxpConfig.Category) or {}
local WEALTH_THRESHOLDS = (Balance and Balance.UxpConfig and Balance.UxpConfig.WealthThresholds) or {}

-- Fallback per-zone thresholds
local GRID_THRESHOLDS: { [string]: { Medium: number, Wealthy: number } } = {
	Default     = { Medium = 10, Wealthy = 20 },
	Residential = { Medium = 5,  Wealthy = 10 },
	Commercial  = { Medium = 12, Wealthy = 24 },
	Industrial  = { Medium = 8,  Wealthy = 18 },
	ResDense    = { Medium = 15, Wealthy = 30 },
	CommDense   = { Medium = 15, Wealthy = 30 },
	IndusDense  = { Medium = 12, Wealthy = 25 },
}

-- Synergy mapping (positive = helps, negative = harms)
local synergyMapping: { [string]: { [string]: number } } = {
	Residential = {
		Residential = 0,   Commercial  = 10,  Industrial = -10,
		ResDense    = 0,   CommDense   = 10,  IndusDense = -20,
		WaterTower  = 20,
	},
	Commercial = {
		Residential = 10,  Commercial  = 0,   Industrial = -10,
		ResDense    = 10,  CommDense   = 0,   IndusDense = -20,
		WaterTower  = 15,
	},
	Industrial = {
		Residential = -10, Commercial  = -10, Industrial = 0,
		ResDense    = -5,  CommDense   = -5,  IndusDense = 0,
		WaterTower  = 8,
	},
	ResDense = {
		Residential = 0,   Commercial  = 10,  Industrial = -5,
		ResDense    = 0,   CommDense   = 10,  IndusDense = -20,
		WaterTower  = 25,
	},
	CommDense = {
		Residential = 10,  Commercial  = 0,   Industrial = -5,
		ResDense    = 10,  CommDense   = 0,   IndusDense = -20,
		WaterTower  = 20,
	},
	IndusDense = {
		Residential = -20, Commercial  = -20, Industrial = 0,
		ResDense    = -20, CommDense   = -20, IndusDense = 0,
		WaterTower  = 5,
	},
	WaterTower = {
		Residential = 20,  Commercial  = 15,  Industrial = 8,
		ResDense    = 25,  CommDense   = 20,  IndusDense = 5,
		WaterTower  = 0,
	},
}


-- ===== Debug flags & printers =====
local DEBUG_UXP = false
local DEBUG_SYNERGY = false
local DEBUG_UXP_ALARMS = false
local VERBOSE_LOG = false

local function log(...)
	if VERBOSE_LOG then print(...) end
end

-- Load-safe mode (during join/reload): suppress FX & heavy work briefly
local LOAD_SAFE_GRACE_SEC = 8
local LOAD_SAFE_CLUSTER_MAX = 16
local LOAD_SAFE_CLUSTER_YIELD = 0.01
local UXP_STEP_BUDGET_SEC = 0.006 -- per-loop yield budget for UXP passes
local _loadSafeUntil: { [Player]: number } = {}

local function dprintUXP(...: any) if DEBUG_UXP then print("[GridUXP]", ...) end end
local function dprintSYN(...: any) if DEBUG_SYNERGY then print("[Synergy]", ...) end end
local function dprintFX (...: any) if DEBUG_UXP_ALARMS then print("[UxpFX]", ...) end end

-- ===== Runtime state =====
local _loadPhase: { [Player]: boolean } = {}
local _graceUntil: { [Player]: number } = {}
local _pollutionClock: { [Player]: { [string]: { token: number } } } = {}
local _pollutionNotice: { [Player]: { [string]: boolean } } = {}
local POLLUTION_NOTICE_LANG_KEY = "ZonePollutedByIndustry"

local function _markPollutionNotice(player: Player, zoneId: string, state: boolean?): boolean
	if not (player and zoneId) then return false end
	if state then
		_pollutionNotice[player] = _pollutionNotice[player] or {}
		if _pollutionNotice[player][zoneId] then return false end
		_pollutionNotice[player][zoneId] = true
		return true
	end

	local bucket = _pollutionNotice[player]; if not bucket then return false end
	bucket[zoneId] = nil
	if not next(bucket) then _pollutionNotice[player] = nil end
	return true
end

local function _notifyPollution(player: Player, zoneId: string)
	if not NotifyPlayerEvent then return end
	-- Only notify once per polluted period for this zone
	local fresh = _markPollutionNotice(player, zoneId, true)
	if not fresh then return end
	NotifyPlayerEvent:FireClient(player, {
		LangKey   = POLLUTION_NOTICE_LANG_KEY,
		Text      = "A zone is being polluted by a nearby industrial zone.",
		ForceText = true,
	})
end
local _incomePollutionTiles: { [Player]: { [string]: { [string]: number } } } = {}
local _pollTickCursor: { [Player]: { [string]: number } } = {}

-- NEW: per-(player, zone) mutex + queue for seeded gap refills to ensure a single _refillZoneGaps runs at a time.
local _refillLock: { [Player]: { [string]: boolean } } = {}
-- pending format: _refillPending[player][zoneId][wealth]["x|z"] = true
local _refillPending: { [Player]: { [string]: { [string]: { [string]: boolean } } } } = {}
local _refillEpoch: { [Player]: { [string]: number } } = {}
local _WEALTH_ORDER = { "Poor", "Medium", "Wealthy" }
local RefillQueue = {}

local function _isInLoad(player: Player): boolean
	return _loadPhase[player] == true
end
local function _isLoadSafe(player: Player): boolean
	if _isInLoad(player) then return true end
	local untilT = _loadSafeUntil[player]
	return untilT ~= nil and os.clock() < untilT
end
local function _canDowngradeNow(player: Player): boolean
	local t = _graceUntil[player]
	return t == nil or os.clock() >= t
end

-- ===== Helpers =====
local function computeBoundingBox(gridList: { GridTile }): BoundingBox
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	for _, t in ipairs(gridList) do
		if t.x < minX then minX = t.x end
		if t.x > maxX then maxX = t.x end
		if t.z < minZ then minZ = t.z end
		if t.z > maxZ then maxZ = t.z end
	end
	return { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
end

local function aabbOverlap(bb1: BoundingBox, bb2: BoundingBox, expand: number?): boolean
	local e = expand or 0
	return not (
		(bb1.maxX + e < bb2.minX) or
			(bb1.minX - e > bb2.maxX) or
			(bb1.maxZ + e < bb2.minZ) or
			(bb1.minZ - e > bb2.maxZ)
	)
end

local function getInfluenceWidth(mode: string): number
	local w = (UXP_RADIUS :: any)[mode]
	if type(w) ~= "number" or w < 1 then
		return ADJACENCY_RADIUS
	end
	return math.max(1, math.floor(w))
end

local function getSynergyWidth(mode: string): number
	local conf  = (Interactions and Interactions.Synergy) or nil
	local per   = conf and conf.Radius or nil
	local deflt = conf and conf.DefaultRadius or nil
	local w     = (per and per[mode]) or deflt or ADJACENCY_RADIUS
	if type(w) ~= "number" or w < 1 then w = ADJACENCY_RADIUS end
	return math.max(1, math.floor(w))
end

local function _maxInfluenceRadius()
	local maxR = ADJACENCY_RADIUS
	for mode, _ in pairs(UXP_VALUES :: any) do
		local r = getInfluenceWidth(mode)
		if r > maxR then maxR = r end
	end
	return maxR
end

local function _buildSynergyRadiusMap()
	local out = {}
	for targetMode, row in pairs(synergyMapping) do
		local maxR = ADJACENCY_RADIUS
		for neighborMode, _ in pairs(row) do
			local r = getSynergyWidth(neighborMode)
			if r > maxR then maxR = r end
		end
		out[targetMode] = maxR
	end
	return out
end

local function _maxPositiveRadius()
	local cfg = Interactions and Interactions.IncomeBonus
	if not cfg then return ADJACENCY_RADIUS end
	local maxR = ADJACENCY_RADIUS
	for _, row in pairs(cfg) do
		if type(row) == "table" then
			for neighborMode, _ in pairs(row) do
				local r = getSynergyWidth(neighborMode)
				if r > maxR then maxR = r end
			end
		end
	end
	return maxR
end

local MAX_UXP_QUERY_RADIUS = _maxInfluenceRadius()
local MAX_POSITIVE_QUERY_RADIUS = _maxPositiveRadius()
local MAX_SYNERGY_RADIUS_BY_TARGET = _buildSynergyRadiusMap()

local function _pollutionAllowed(targetMode: string, sourceMode: string): boolean
	local pol = (Interactions and Interactions.Pollution and Interactions.Pollution.AllowedSources)
	if not pol then
		if DEBUG_SYNERGY then print("[Pollution] no AllowedSources table; block", targetMode, "<-", sourceMode) end
		return false
	end
	local row = pol[targetMode]
	if not row then
		if DEBUG_SYNERGY then print("[Pollution] no target row; block", targetMode, "<-", sourceMode) end
		return false
	end
	local ok = row[sourceMode] == true
	if DEBUG_SYNERGY then
		log(("[Pollution] allow? %s <- %s : %s"):format(targetMode, sourceMode, tostring(ok)))
	end
	return ok
end

local function getPollutionWidth(sourceMode: string): number
	local pol = (Interactions and Interactions.Pollution) or nil
	local per = pol and pol.Radius or nil
	local def = pol and pol.DefaultRadius or nil
	local w   = (per and per[sourceMode]) or def
	if type(w) == "number" and w >= 1 then
		if DEBUG_SYNERGY then print(("[PollutionWidth] %s -> %d (module)"):format(sourceMode, w)) end
		return math.max(1, math.floor(w))
	end
	local uxpw = getInfluenceWidth(sourceMode)
	if DEBUG_SYNERGY then print(("[PollutionWidth] %s -> %d (fallback UXP)"):format(sourceMode, uxpw)) end
	return uxpw
end



local function isNearby(tileA: GridTile, tileB: GridTile, sideLen: number): boolean
	-- Convert legacy "side length in cells" to a radius in cells.
	-- (Keeping existing configs untouched: sideLen is still passed everywhere.)
	local r = math.max(0, math.floor(sideLen * 0.5))

	-- Euclidean disc test on grid centers: dx^2 + dz^2 <= r^2
	local dx = tileA.x - tileB.x
	local dz = tileA.z - tileB.z
	return (dx*dx + dz*dz) <= (r*r)
end

local function getWealthThresholdsForMode(mode: string): { Medium: number, Wealthy: number }
	local wt = (WEALTH_THRESHOLDS :: any)[mode]
	if wt and wt.Medium and wt.Wealthy then
		return wt
	end
	return GRID_THRESHOLDS[mode] or GRID_THRESHOLDS.Default
end

-- ===== Refill queue helpers (ensure single _refillZoneGaps per zone) =====
local function _cellKey(x: number, z: number): string
	return tostring(x).."|"..tostring(z)
end

-- ==== Seed Clustering (proximity-based batching) ====
local SEED_CLUSTERING = {
	enabled       = true,   -- turn off to revert to old behavior
	max_cluster   = 64,     -- hard cap per cluster (your “max bucket size”)
	diagonal      = false,  -- 4-neighbor connectivity; set true for 8-neighbor
	yield_between = 0.02,   -- short cooperative yield after each cluster
}

local function _seedClusterCfgFor(player: Player)
	if _isLoadSafe(player) then
		return {
			enabled = true,
			max_cluster = LOAD_SAFE_CLUSTER_MAX,
			diagonal = SEED_CLUSTERING.diagonal,
			yield_between = LOAD_SAFE_CLUSTER_YIELD,
		}
	end
	return SEED_CLUSTERING
end

local function _neighborsFor(x: number, z: number, diagonal: boolean)
	if diagonal then
		return {
			{x+1, z}, {x-1, z}, {x, z+1}, {x, z-1},
			{x+1, z+1}, {x-1, z+1}, {x+1, z-1}, {x-1, z-1},
		}
	else
		return { {x+1, z}, {x-1, z}, {x, z+1}, {x, z-1} }
	end
end

-- Returns { { {x=..,z=..}, ... }, ... } clusters, each <= max_cluster and connected by grid adjacency.
local function _clusterSeedCells(cells: { {x: number, z: number} }, cfg): { { {x: number, z: number} } }
	if not (cells and #cells > 0) then return {} end
	cfg = cfg or SEED_CLUSTERING
	local diag = cfg.diagonal == true
	local maxN = math.max(1, math.floor(tonumber(cfg.max_cluster or 64) or 64))

	-- Build a presence map for O(1) membership & a deterministic visit order.
	local remain: { [string]: {x: number, z: number} } = {}
	for _, c in ipairs(cells) do remain[_cellKey(c.x, c.z)] = { x = c.x, z = c.z } end

	local clusters = {}

	-- Stable traversal: sort by x,z so runs are deterministic across servers.
	table.sort(cells, function(a,b) return (a.x < b.x) or (a.x == b.x and a.z < b.z) end)

	for _, seed in ipairs(cells) do
		local key = _cellKey(seed.x, seed.z)
		local start = remain[key]
		if start then
			remain[key] = nil
			local queue  = { start }
			local cursor = 1
			local pack   = {}

			while cursor <= #queue do
				local p = queue[cursor]; cursor += 1
				table.insert(pack, p)

				-- Split oversized components into fixed-size sub-clusters
				if #pack >= maxN then
					table.insert(clusters, pack)
					pack = {}
				end

				for _, n in ipairs(_neighborsFor(p.x, p.z, diag)) do
					local nk = _cellKey(n[1], n[2])
					local nextCell = remain[nk]
					if nextCell then
						remain[nk] = nil
						table.insert(queue, nextCell)
					end
				end
			end

			if #pack > 0 then
				table.insert(clusters, pack)
			end
		end
	end

	-- Optional: order clusters by their min (x,z) for locality-friendly scheduling
	table.sort(clusters, function(A,B)
		local ax, az = math.huge, math.huge
		for i = 1, #A do local a = A[i]; if a.x < ax or (a.x == ax and a.z < az) then ax, az = a.x, a.z end end
		local bx, bz = math.huge, math.huge
		for i = 1, #B do local b = B[i]; if b.x < bx or (b.x == bx and b.z < bz) then bx, bz = b.x, b.z end end
		return (ax < bx) or (ax == bx and az < bz)
	end)

	return clusters
end

function RefillQueue.addCells(player: Player, zoneId: string, wealth: string, cells: { { x: number, z: number } }?)
	if not cells or #cells == 0 then return end
	_refillPending[player] = _refillPending[player] or {}
	_refillPending[player][zoneId] = _refillPending[player][zoneId] or {}
	_refillPending[player][zoneId][wealth] = _refillPending[player][zoneId][wealth] or {}
	local bucket = _refillPending[player][zoneId][wealth]
	for _, c in ipairs(cells) do
		if c and typeof(c.x) == "number" and typeof(c.z) == "number" then
			bucket[_cellKey(c.x, c.z)] = true
		end
	end
end

function RefillQueue.hasAny(player: Player, zoneId: string): boolean
	local z = _refillPending[player] and _refillPending[player][zoneId]
	if not z then return false end
	for _, set in pairs(z) do
		if set and next(set) ~= nil then return true end
	end
	return false
end

function RefillQueue.popOne(player: Player, zoneId: string): (string?, { { x: number, z: number } }?)
	local z = _refillPending[player] and _refillPending[player][zoneId]
	if not z then return nil, nil end
	for _, wealth in ipairs(_WEALTH_ORDER) do
		local set = z[wealth]
		if set and next(set) ~= nil then
			local arr = {}
			for key, _ in pairs(set) do
				local sep = string.find(key, "|", 1, true)
				local x = tonumber(string.sub(key, 1, sep - 1))
				local zz = tonumber(string.sub(key, sep + 1))
				table.insert(arr, { x = x, z = zz })
				set[key] = nil
			end
			return wealth, arr
		end
	end
	return nil, nil
end

function RefillQueue.unlock(player: Player, zoneId: string)
	if _refillLock[player] then
		_refillLock[player][zoneId] = nil
		if not next(_refillLock[player]) then _refillLock[player] = nil end
	end
	-- tidy pending table if empty
	if _refillPending[player] and _refillPending[player][zoneId] and not RefillQueue.hasAny(player, zoneId) then
		_refillPending[player][zoneId] = nil
		if not next(_refillPending[player]) then _refillPending[player] = nil end
	end
end

function RefillQueue.getEpoch(player: Player, zoneId: string): number
	local per = _refillEpoch[player]
	if per then
		return per[zoneId] or 0
	end
	return 0
end

function RefillQueue.bumpEpoch(player: Player, zoneId: string): number
	if not (player and zoneId) then return 0 end
	_refillEpoch[player] = _refillEpoch[player] or {}
	local nextVal = (_refillEpoch[player][zoneId] or 0) + 1
	_refillEpoch[player][zoneId] = nextVal
	return nextVal
end

function RefillQueue.clearPending(player: Player, zoneId: string)
	local per = _refillPending[player]
	if per then
		per[zoneId] = nil
		if not next(per) then
			_refillPending[player] = nil
		end
	end
end

function RefillQueue.cancel(player: Player, zoneId: string)
	if not (player and zoneId) then return end
	RefillQueue.bumpEpoch(player, zoneId)
	RefillQueue.clearPending(player, zoneId)
	if _refillLock[player] then
		_refillLock[player][zoneId] = nil
		if not next(_refillLock[player]) then
			_refillLock[player] = nil
		end
	end
end

-- ===== Module =====
local CityInteractions = {}
CityInteractions.__index = CityInteractions

-- Player → Array<ZoneData>
local zoneCacheByPlayer: { [Player]: { ZoneData } } = {}


local function _getZoneDataFromCache(player: Player, zoneId: string): ZoneData?
	local cache = zoneCacheByPlayer[player]; if not cache then return nil end
	for _, z in ipairs(cache) do if z.zoneId == zoneId then return z end end
	return nil
end

-- ===== Spatial index for fast neighborhood queries =====
local SPATIAL_CELL_SIZE = 8

type SpatialEntry = {
	zone: ZoneData,
	cells: { { x: number, z: number } },
}

local SpatialIndex = {}
SpatialIndex.__index = SpatialIndex

function SpatialIndex.new(cellSize)
	return setmetatable({
		cellSize = cellSize or SPATIAL_CELL_SIZE,
		cells = {} :: { [number]: { [number]: { ZoneData } } },
		byId = {} :: { [string]: SpatialEntry },
	}, SpatialIndex)
end

function SpatialIndex:_cell(x: number, z: number): (number, number)
	return math.floor(x / self.cellSize), math.floor(z / self.cellSize)
end

function SpatialIndex:_touchCell(cx: number, cz: number)
	self.cells[cx] = self.cells[cx] or {}
	self.cells[cx][cz] = self.cells[cx][cz] or {}
	return self.cells[cx][cz]
end

function SpatialIndex:add(zone: ZoneData)
	if not zone or not zone.boundingBox then return end
	if self.byId[zone.zoneId] then
		self:remove(zone.zoneId)
	end

	local bb = zone.boundingBox
	local minCellX = math.floor(bb.minX / self.cellSize)
	local maxCellX = math.floor(bb.maxX / self.cellSize)
	local minCellZ = math.floor(bb.minZ / self.cellSize)
	local maxCellZ = math.floor(bb.maxZ / self.cellSize)

	local stamped = {}
	for cx = minCellX, maxCellX do
		for cz = minCellZ, maxCellZ do
			local bucket = self:_touchCell(cx, cz)
			table.insert(bucket, zone)
			table.insert(stamped, { x = cx, z = cz })
		end
	end

	self.byId[zone.zoneId] = { zone = zone, cells = stamped }
end

function SpatialIndex:remove(zoneId: string)
	local entry = self.byId[zoneId]
	if not entry then return end
	for _, cell in ipairs(entry.cells or {}) do
		local col = self.cells[cell.x]
		if col and col[cell.z] then
			for i = #col[cell.z], 1, -1 do
				if col[cell.z][i].zoneId == zoneId then
					table.remove(col[cell.z], i)
				end
			end
			if #col[cell.z] == 0 then
				col[cell.z] = nil
			end
		end
		if col and next(col) == nil then
			self.cells[cell.x] = nil
		end
	end
	self.byId[zoneId] = nil
end

function SpatialIndex:update(zone: ZoneData)
	if not zone then return end
	self:remove(zone.zoneId)
	self:add(zone)
end

local function _collectFromCells(cells: { [number]: { [number]: { ZoneData } } }, minCellX, maxCellX, minCellZ, maxCellZ)
	local out = {}
	local seen = {}
	for cx = minCellX, maxCellX do
		local col = cells[cx]
		if col then
			for cz = minCellZ, maxCellZ do
				local bucket = col[cz]
				if bucket then
					for _, zone in ipairs(bucket) do
						if not seen[zone.zoneId] then
							seen[zone.zoneId] = true
							table.insert(out, zone)
						end
					end
				end
			end
		end
	end
	return out
end

function SpatialIndex:queryAabb(bb: BoundingBox, expand: number?): { ZoneData }
	if not bb then return {} end
	local e = expand or 0
	local minCellX = math.floor((bb.minX - e) / self.cellSize)
	local maxCellX = math.floor((bb.maxX + e) / self.cellSize)
	local minCellZ = math.floor((bb.minZ - e) / self.cellSize)
	local maxCellZ = math.floor((bb.maxZ + e) / self.cellSize)
	return _collectFromCells(self.cells, minCellX, maxCellX, minCellZ, maxCellZ)
end

function SpatialIndex:queryRadius(x: number, z: number, radius: number): { ZoneData }
	radius = math.max(0, radius or 0)
	local minCellX = math.floor((x - radius) / self.cellSize)
	local maxCellX = math.floor((x + radius) / self.cellSize)
	local minCellZ = math.floor((z - radius) / self.cellSize)
	local maxCellZ = math.floor((z + radius) / self.cellSize)
	return _collectFromCells(self.cells, minCellX, maxCellX, minCellZ, maxCellZ)
end

function SpatialIndex:clear()
	self.cells = {}
	self.byId = {}
end

local zoneSpatialIndexByPlayer: { [Player]: SpatialIndex } = {}

local function _getSpatialIndex(player: Player, create: boolean?): SpatialIndex?
	if not player then return nil end
	local idx = zoneSpatialIndexByPlayer[player]
	if not idx and create then
		idx = SpatialIndex.new(SPATIAL_CELL_SIZE)
		zoneSpatialIndexByPlayer[player] = idx
		local cache = zoneCacheByPlayer[player]
		if cache then
			for _, zone in ipairs(cache) do
				idx:add(zone)
			end
		end
	end
	return idx
end

-- ===== Positive income cache =====
local _positiveBonusTiles: { [Player]: { [string]: { [string]: number } } } = {}
local IncomeBonusCfg = Interactions and Interactions.IncomeBonus
local POSITIVE_MAX_BONUS = (IncomeBonusCfg and tonumber(IncomeBonusCfg.MaxBonus)) or 0.30

local function _setTilePositiveBonus(player: Player, zoneId: string, key: string, bonus: number)
	_positiveBonusTiles[player] = _positiveBonusTiles[player] or {}
	_positiveBonusTiles[player][zoneId] = _positiveBonusTiles[player][zoneId] or {}
	_positiveBonusTiles[player][zoneId][key] = bonus
end

local function _clearZonePositiveBonus(player: Player, zoneId: string)
	if _positiveBonusTiles[player] then
		_positiveBonusTiles[player][zoneId] = nil
		if not next(_positiveBonusTiles[player]) then
			_positiveBonusTiles[player] = nil
		end
	end
end

local function _getTilePositiveBonus(player: Player, zoneId: string, key: string): number?
	return _positiveBonusTiles[player]
		and _positiveBonusTiles[player][zoneId]
		and _positiveBonusTiles[player][zoneId][key]
		or nil
end

local function _tileHasNeighborOfModeInRange(tile: GridTile, neighbor: ZoneData, width: number): boolean
	-- Quick AABB gate
	local bb = neighbor.boundingBox
	if tile.x < bb.minX - width or tile.x > bb.maxX + width
		or tile.z < bb.minZ - width or tile.z > bb.maxZ + width then
		return false
	end
	-- Per-tile proximity check
	for _, tB in ipairs(neighbor.gridList) do
		if isNearby(tile, tB, width) then return true end
	end
	return false
end

local function _computeTilePositiveBonus(player: Player, zoneData: ZoneData, tile: GridTile): number
	if not IncomeBonusCfg then return 0 end
	local perTarget = IncomeBonusCfg[zoneData.mode]
	if type(perTarget) ~= "table" then return 0 end

	local total = 0
	for neighborMode, bonus in pairs(perTarget) do
		if type(bonus) == "number" and bonus > 0 then
			local width = getSynergyWidth(neighborMode)
			local candidates
			local idx = _getSpatialIndex(player, false)
			if idx then
				candidates = idx:queryRadius(tile.x, tile.z, width)
			else
				candidates = zoneCacheByPlayer[player] or {}
			end

			for _, neighbor in ipairs(candidates) do
				if neighbor.zoneId ~= zoneData.zoneId
					and neighbor.mode == neighborMode
					and _tileHasNeighborOfModeInRange(tile, neighbor, width)
				then
					total += bonus
					break
				end
			end
		end
	end

	if total > POSITIVE_MAX_BONUS then
		total = POSITIVE_MAX_BONUS
	elseif total < 0 then
		total = 0
	end
	return total
end

-- Persist last per-tile UXP so we can detect up/down deltas
local _lastTileUXP: { [Player]: { [string]: { [string]: number } } } = {}
local function _tkey(x: number, z: number): string
	return tostring(x).."|"..tostring(z)
end

--For Pollution/synnergy not UXP
local function _tkey2(x: number, z: number): string
	return tostring(x).."|"..tostring(z)
end



local function _refreshPositiveIncomeForZone(player: Player, zoneData: ZoneData)
	if not player or not zoneData then return end
	if not IncomeBonusCfg or not IncomeBonusCfg[zoneData.mode] then
		_clearZonePositiveBonus(player, zoneData.zoneId)
		return
	end

	local idx = _getSpatialIndex(player, false)
	if not idx then
		_clearZonePositiveBonus(player, zoneData.zoneId)
		return
	end

	if not zoneData.gridList then
		_clearZonePositiveBonus(player, zoneData.zoneId)
		return
	end

	for _, tile in ipairs(zoneData.gridList) do
		local key = _tkey(tile.x, tile.z)
		local bonus = _computeTilePositiveBonus(player, zoneData, tile)
		_setTilePositiveBonus(player, zoneData.zoneId, key, bonus)
	end
end

local function _recalcPositiveBonusesAround(player: Player, pivot: ZoneData?, boundsOverride: BoundingBox?)
	if not player then return end
	local idx = _getSpatialIndex(player, false)
	if not idx then return end

	local visited = {}
	local function touch(zone: ZoneData?)
		if not zone or visited[zone.zoneId] then return end
		visited[zone.zoneId] = true
		_refreshPositiveIncomeForZone(player, zone)
	end

	if pivot then
		touch(pivot)
	end

	local bb = boundsOverride or (pivot and pivot.boundingBox)
	if not bb then return end

	local influence = pivot and getSynergyWidth(pivot.mode) or MAX_POSITIVE_QUERY_RADIUS
	local neighbors = idx:queryAabb(bb, influence)
	for _, zone in ipairs(neighbors) do
		touch(zone)
	end
end



-- =========================================================================================
-- UXP FLASH ALARM SYSTEM  (AlarmUpgrade / AlarmDowngrade / AlarmPolution [reserved])
-- =========================================================================================

local Fx = {
	SOUND_COOLDOWN = 0.9, -- seconds between Upgrade/Downgrade SFX buckets per player
	ALARM_FOLDER_NAME = "TempUxpAlarms",
	FADE_IN_TIME = 0.15,
	PULSE_UP_TIME = 0.25,
	PULSE_DOWN_TIME = 0.25,
	PULSE_CYCLES = 2, -- gentle, not spammy
	FADE_OUT_TIME = 0.18,
	PULSE_SCALE = 0.18, -- 18% bigger at peak
	BASE_ALPHA = 0.15,  -- end-of-fade-in target (semi-opaque)
	PEAK_ALPHA = 0.00,  -- most visible at pulse peak (0 = fully opaque for Image, 0 = fully opaque bg if you invert)
	EASING = Enum.EasingStyle.Sine,
	THROTTLE_PER_TILE = 0.12,
	POLLUTION_TYPES = { AlarmPolution = true, AlarmPollution = true },
	ALARM_OFFSET_Y = 6,
	POLLUTION_OFFSET_Y = 9, -- higher Y only for pollution
	POLLUTION_HOLD_TIME = 3.5, -- seconds to stay visible
	POLLUTION_BASE_ALPHA = 0.22, -- slightly more visible while lingering
	POLLUTION_FADE_IN = 0.18,
	POLLUTION_FADE_OUT = 0.22,
	COLOR_STEPS = 6, -- equal steps (e.g., 6 = 0%, 20%, 40%, 60%, 80%, 100%)
	COLOR_DARK_ORANGE = Color3.fromRGB(220, 130, 0),
	COLOR_GREEN = Color3.fromRGB(0, 200, 120),
	COLOR_RED = Color3.fromRGB(215, 50, 50),
}
Fx.ALARM_TTL = Fx.FADE_IN_TIME + (Fx.PULSE_UP_TIME + Fx.PULSE_DOWN_TIME) * Fx.PULSE_CYCLES + Fx.FADE_OUT_TIME + 0.05
Fx.POLLUTION_TTL = Fx.POLLUTION_FADE_IN + Fx.POLLUTION_HOLD_TIME + Fx.POLLUTION_FADE_OUT + 0.05
local _uxpSoundLastAt: {[Player]: {[string]: number}} = {}

local function playUxpSound(player: Player?, kind: "Upgrade" | "Downgrade")
	if not player or not PlayUISoundRE then
		return
	end

	local now = os.clock()
	local perPlayer = _uxpSoundLastAt[player]
	if not perPlayer then
		perPlayer = {}
		_uxpSoundLastAt[player] = perPlayer
	end

	local last = perPlayer[kind] or 0
	if now - last < Fx.SOUND_COOLDOWN then
		return
	end

	perPlayer[kind] = now
	PlayUISoundRE:FireClient(player, "Misc", kind)
end

Players.PlayerRemoving:Connect(function(plr)
	_uxpSoundLastAt[plr] = nil
end)

-- FX behavior:
--    fade-in → pulse (scale up/down smoothly) for N cycles → fade-out → return to pool
--    POLLUTION-ONLY: fade-in → hold (linger) → fade-out → return to pool


-- Timing / pulse shape (gentle vibe)

-- === NEW: pollution-only style ===

-- Raise pollution alarms higher than default

-- Linger profile (no pulse): fade in, HOLD, fade out

-- === Progress color ramp (discrete steps) ===

-- Anchors for ramps

-- still used as a “default red” elsewhere if needed
CityInteractions._DOWNGRADE_COLOR = Color3.fromRGB(220, 64, 64)

-- tiny utilities
local function _clamp01(x:number) return (x < 0 and 0) or (x > 1 and 1) or x end
local function _q01(x:number, steps:number)
	steps = math.max(1, math.floor(steps))
	return math.floor(_clamp01(x) * steps + 0.5) / steps
end
local function _lerp(a:number,b:number,t:number) return a + (b-a)*t end
local function _lerpC(c0:Color3, c1:Color3, t:number): Color3
	return Color3.new(_lerp(c0.R, c1.R, t), _lerp(c0.G, c1.G, t), _lerp(c0.B, c1.B, t))
end

-- Progress (0..1) → discrete color for UPGRADE (dark orange → green)
function CityInteractions._progressColorUp(p:number): Color3
	local t = _q01(p, Fx.COLOR_STEPS)
	return _lerpC(Fx.COLOR_DARK_ORANGE, Fx.COLOR_GREEN, t)
end

-- Progress (0..1) → discrete color for DOWNGRADE (dark orange → red)
function CityInteractions._progressColorDown(p:number): Color3
	local t = _q01(p, Fx.COLOR_STEPS)
	return _lerpC(Fx.COLOR_DARK_ORANGE, Fx.COLOR_RED, t)
end

-- we accept both spellings for future-proofing
local VALID_UXP_ALARM_TYPES = {
	AlarmUpgrade   = true,
	AlarmDowngrade = true,
	AlarmPolution  = true,
	AlarmPollution = true,
}

-- bounds/terrain cache (module-local, duplicated from ZRC to keep modules decoupled)
local _boundsCache: { [Instance]: { bounds: any, terrains: { BasePart } } } = {}

local function _getGlobalBoundsForPlot(plot: Instance)
	local cached = _boundsCache[plot]
	if cached then return cached.bounds, cached.terrains end
	local terrains = {}
	local unlocks  = plot:FindFirstChild("Unlocks")
	if unlocks then
		for _, zone in ipairs(unlocks:GetChildren()) do
			for _, seg in ipairs(zone:GetChildren()) do
				if seg:IsA("BasePart") and seg.Name:match("^Segment%d+$") then
					table.insert(terrains, seg)
				end
			end
		end
	end
	local testTerrain = plot:FindFirstChild("TestTerrain")
	if #terrains == 0 and testTerrain then
		table.insert(terrains, testTerrain)
	end
	local gb = GridConfig.calculateGlobalBounds(terrains)
	_boundsCache[plot] = { bounds = gb, terrains = terrains }
	return gb, terrains
end



local function _getZoneModelFor(player: Player, zoneId: string): (Model?, Instance?)
	local plotFolder = workspace:FindFirstChild("PlayerPlots")
	local playerPlot = plotFolder and plotFolder:FindFirstChild("Plot_" .. player.UserId)
	if not playerPlot then return nil, nil end
	local zoneModelFolder = playerPlot:FindFirstChild("PlayerZones")
	local zoneModel = zoneModelFolder and zoneModelFolder:FindFirstChild(zoneId)
	return zoneModel, playerPlot
end

local function _zoneTrackerIsPopulated(player: Player, zoneId: string): boolean?
	if not ZoneTracker then return nil end
	local trackerAny = ZoneTracker :: any

	if type(trackerAny.isZonePopulated) == "function" then
		local ok, res = pcall(function()
			return trackerAny.isZonePopulated(player, zoneId)
		end)
		if ok and type(res) == "boolean" then
			return res
		end
	end

	if type(trackerAny.getZoneById) == "function" then
		local ok, zone = pcall(function()
			return trackerAny.getZoneById(player, zoneId)
		end)
		if ok and type(zone) == "table" then
			local req = zone.requirements
			if req and type(req) == "table" and req.Populated ~= nil then
				return req.Populated == true
			end
		end
	end

	return nil
end

-- ==== Upgrade batching / epoch de-dupe ====
local _passEpoch: number = 0
-- player → zoneId → tileKey ("x|z") → lastSeenEpoch
local _seenEpoch: { [Player]: { [string]: { [string]: number } } } = {}

local function _nextEpoch(): number
	_passEpoch += 1
	return _passEpoch
end

local _activeEpoch: number? = nil
local _epochDepth: number = 0

local function _beginPass()
	-- start a new epoch only for the outermost pass
	if _epochDepth == 0 then
		_activeEpoch = _nextEpoch()
	end
	_epochDepth += 1
end

local function _currentPassEpoch(): number?
	return _activeEpoch
end

local function _endPass()
	if _epochDepth > 0 then
		_epochDepth -= 1
		if _epochDepth == 0 then
			_activeEpoch = nil
		end
	end
end

-- returns true if this (player, zone, tileKey) has NOT been seen in this epoch (and marks it)
local function _markSeenThisEpoch(player: Player, zoneId: string, tileKey: string, epoch: number): boolean
	_seenEpoch[player] = _seenEpoch[player] or {}
	_seenEpoch[player][zoneId] = _seenEpoch[player][zoneId] or {}
	local last = _seenEpoch[player][zoneId][tileKey]
	if last == epoch then return false end
	_seenEpoch[player][zoneId][tileKey] = epoch
	return true
end



-- Hard guard: do not upgrade if Stage3 "populated" is not confirmed yet.
local function _isStage3Populated(player: Player, zoneId: string): boolean
	local zm = select(1, _getZoneModelFor(player, zoneId))
	if zm then
		local a = zm:GetAttribute("populated")
		if a == true then return true elseif a == false then return false end

		local bv = zm:FindFirstChild("populated")
		if bv and bv:IsA("BoolValue") then return bv.Value end

		local s3 = zm:FindFirstChild("Stage3")
		if s3 then
			local a2 = (s3 :: any).GetAttribute and (s3 :: any):GetAttribute("populated") or nil
			if a2 == true then return true elseif a2 == false then return false end
			local bv2 = s3:FindFirstChild("populated")
			if bv2 and bv2:IsA("BoolValue") then return bv2.Value end
		end
	end

	-- ZoneTracker keeps authoritative requirement flags even if the workspace model isn't streamed in.
	do
		local trackerFlag = _zoneTrackerIsPopulated(player, zoneId)
		if trackerFlag ~= nil then
			return trackerFlag
		end
	end

	-- Optional: allow ZoneTracker to provide truth if available
	if ZoneTracker and type((ZoneTracker :: any).isStage3Populated) == "function" then
		local ok, res = pcall(function()
			return (ZoneTracker :: any).isStage3Populated(player, zoneId)
		end)
		if ok and type(res) == "boolean" then return res end
	end

	-- Default SAFE: not populated → block upgrades
	return false
end

local function _demandRadiusForTargetMode(targetMode: string): number
	local dm = Interactions and Interactions.DemandMix
	if not dm then return 5 end
	local r = (dm.Radius and dm.Radius[targetMode]) or dm.DefaultRadius or 5
	return math.max(1, math.floor(tonumber(r) or 5))
end

-- Presence check: is there at least one neighbor of neighborMode within 'width' of tile?
local function _tileHasNeighborMode(tile: GridTile, neighborList: { ZoneData }, neighborMode: string, width: number): boolean
	for _, other in ipairs(neighborList) do
		if other.mode == neighborMode then
			local bb = other.boundingBox
			if tile.x >= bb.minX - width and tile.x <= bb.maxX + width
				and tile.z >= bb.minZ - width and tile.z <= bb.maxZ + width then
				for _, tB in ipairs(other.gridList) do
					if isNearby(tile, tB, width) then return true end
				end
			end
		end
	end
	return false
end

-- Public: 1.0 + summed bonus (capped) for Water or Power at a specific tile
function CityInteractions.getTileDemandMultiplier(
	player: Player, zoneId: string, x: number, z: number, targetMode: string, networkType: string
): number
	local dm = Interactions and Interactions.DemandMix
	if not dm then return 1.0 end
	local perNet = dm[networkType]; if not perNet then return 1.0 end

	local row = perNet[targetMode]; if not row then return 1.0 end
	local maxBonus = (dm.MaxBonus and dm.MaxBonus[networkType]) or 0.0

	-- find neighbors once
	local cache = zoneCacheByPlayer[player] or {}
	local tile = { x = x, z = z }
	local width = _demandRadiusForTargetMode(targetMode)

	local add = 0.0
	for neighborMode, pct in pairs(row) do
		if type(pct) == "number" and pct > 0 then
			if _tileHasNeighborMode(tile, cache, neighborMode, width) then
				add += pct
			end
		end
	end

	if maxBonus > 0 then add = math.min(add, maxBonus) end
	if add < 0 then add = 0 end
	return 1.0 + add
end

local function _gridToWorld(playerPlot: Instance, gx: number, gz: number): Vector3
	local referenceTerrain = playerPlot:FindFirstChild("TestTerrain")
	if not referenceTerrain then
		return Vector3.new(0, GridConfig.Y_OFFSET, 0)
	end
	local gb, terrains = _getGlobalBoundsForPlot(playerPlot)
	local worldX, _, worldZ = GridUtil.globalGridToWorldPosition(gx, gz, gb, terrains)
	local worldY = referenceTerrain.Position.Y + (referenceTerrain.Size.Y / 2) + GridConfig.Y_OFFSET
	return Vector3.new(worldX, worldY, worldZ)
end

-- Pool + active registry
local UxpAlarmPool: { [string]: { BasePart } } = {}
local ActiveUxp   : { [BasePart]: { token: number, expires: number } } = {}
local _lastFlashAt: { [string]: number } = {} -- key: userId|zoneId|type|x|z → time
local TweenService = game:GetService("TweenService")

local function _borrowUxpAlarm(alarmType: string): BasePart?
	local alarmsRoot = ReplicatedStorage:WaitForChild("FuncTestGroundRS"):WaitForChild("Alarms")
	local template = alarmsRoot:FindFirstChild(alarmType)
	if not template and alarmType == "AlarmPolution" then
		template = alarmsRoot:FindFirstChild("AlarmPollution")
	elseif not template and alarmType == "AlarmPollution" then
		template = alarmsRoot:FindFirstChild("AlarmPolution")
	end
	if not template then
		warn("[UxpFX] Missing template for", alarmType)
		return nil end

	UxpAlarmPool[alarmType] = UxpAlarmPool[alarmType] or {}
	local pool = UxpAlarmPool[alarmType]
	local part = table.remove(pool)
	if part then return part end

	local clone = template:Clone()
	if clone:IsA("BasePart") then
		clone.Anchored  = true
		clone.CanCollide = false
		return clone
	end
	clone:Destroy()
	warn("[UxpFX] Template is not a BasePart for", alarmType)
	return nil
end

local function _returnUxpAlarm(part: BasePart)
	if not part then return end
	ActiveUxp[part] = nil
	part.Parent = nil
	local alarmType = part.Name:match("^(Alarm%u%l+)")
	if not alarmType then
		part:Destroy()
		return
	end
	UxpAlarmPool[alarmType] = UxpAlarmPool[alarmType] or {}
	table.insert(UxpAlarmPool[alarmType], part)
end

local function _ensureUxpFolder(zoneModel: Instance): Folder
	local f = zoneModel:FindFirstChild(Fx.ALARM_FOLDER_NAME)
	if not f then
		f = Instance.new("Folder")
		f.Name = Fx.ALARM_FOLDER_NAME
		f.Parent = zoneModel
	end
	return f
end

-- Helpers to safely set transparency on common fields
local function _setGuiAlpha(billboard: BillboardGui?, alpha: number)
	if not billboard then return end
	-- Prefer child Icon inside Frame; fall back to a top-level Icon
	local frame = billboard:FindFirstChild("Frame")
	local icon  = frame and frame:FindFirstChild("icon") or billboard:FindFirstChild("icon")

	-- Only control the image’s transparency. Do NOT touch Frame backgrounds.
	if icon and icon:IsA("ImageLabel") then
		icon.ImageTransparency = math.clamp(alpha, 0, 1)
	elseif icon and icon:IsA("ImageButton") then
		icon.ImageTransparency = math.clamp(alpha, 0, 1)
	else
		-- If your Icon isn't an ImageLabel/ImageButton, do nothing here to avoid white boxes.
	end
end

local function _prepBillboard(billboard: BillboardGui)
	-- Render predictably over the world
	billboard.AlwaysOnTop    = true
	billboard.LightInfluence = 0

	-- If you want to force pixel sizing, uncomment the next line.
	-- billboard.Size = UDim2.fromOffset(28, 28)

	-- Nuke any background fills that could flash white
	local frame = billboard:FindFirstChild("Frame")
	if frame and frame:IsA("Frame") then
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
	end

	local icon = frame and frame:FindFirstChild("icon") or billboard:FindFirstChild("icon")
	if icon and icon:IsA("GuiObject") then
		icon.BackgroundTransparency = 1
		icon.BorderSizePixel = 0
	end
end

local function _tween(obj: Instance, ti: TweenInfo, props: any)
	local tw = TweenService:Create(obj, ti, props)
	tw:Play()
	return tw
end

-- NEW: gentle pulse coroutine (fade-in → cycles of size pulse & alpha → fade-out)
local function _pulseGui(billboard: BillboardGui, cycles: number, token: number, part: BasePart)
	-- Capture baseline size and decide pixel vs scale mode
	local baseSize = billboard.Size
	local usePixels = (baseSize.X.Offset ~= 0) or (baseSize.Y.Offset ~= 0)

	local grown: UDim2
	local preGrow: UDim2

	if usePixels then
		-- Pixel pulse: add a few pixels so it looks the same at all distances
		local basePxX = baseSize.X.Offset
		local basePxY = baseSize.Y.Offset
		local maxBase = math.max(math.abs(basePxX), math.abs(basePxY), 1)
		local growPx  = math.max(2, math.floor(maxBase * Fx.PULSE_SCALE + 0.5))
		local prePx   = math.max(1, math.floor(growPx * 0.1 + 0.5))

		grown   = UDim2.fromOffset(basePxX + growPx, basePxY + growPx)
		preGrow = UDim2.fromOffset(basePxX + prePx,  basePxY + prePx)
	else
		-- Scale pulse: multiply the scale channels
		grown   = UDim2.new(baseSize.X.Scale * (1 + Fx.PULSE_SCALE), baseSize.X.Offset,
			baseSize.Y.Scale * (1 + Fx.PULSE_SCALE), baseSize.Y.Offset)
		preGrow = UDim2.new(baseSize.X.Scale * 1.02, baseSize.X.Offset,
			baseSize.Y.Scale * 1.02, baseSize.Y.Offset)
	end

	-- Start fully hidden, then fade-in (Icon only; backgrounds untouched)
	_setGuiAlpha(billboard, 1.0) -- 1.0 = fully hidden for ImageTransparency

	local tiIn = TweenInfo.new(Fx.FADE_IN_TIME, Fx.EASING, Enum.EasingDirection.Out)
	local targetAlpha = Fx.BASE_ALPHA
	billboard.Size = baseSize
	_tween(billboard, tiIn, { Size = preGrow })

	-- manual alpha tween to avoid per-child tweens
	local fadeInStart = os.clock()
	while os.clock() - fadeInStart < Fx.FADE_IN_TIME do
		local t = (os.clock() - fadeInStart) / Fx.FADE_IN_TIME
		local aNow = (1 - t) * 1.0 + t * targetAlpha
		_setGuiAlpha(billboard, aNow)
		task.wait(0.016)
		local a = ActiveUxp[part]; if not a or a.token ~= token then return end
	end
	_setGuiAlpha(billboard, targetAlpha)

	-- Pulse cycles: grow to peak (more visible) → shrink to base (slightly dimmer)
	for _ = 1, cycles do
		local a = ActiveUxp[part]; if not a or a.token ~= token then return end
		-- UP: size to 'grown', alpha to PEAK
		local tiUp = TweenInfo.new(Fx.PULSE_UP_TIME, Fx.EASING, Enum.EasingDirection.Out)
		_tween(billboard, tiUp, { Size = grown })
		local upStart = os.clock()
		while os.clock() - upStart < Fx.PULSE_UP_TIME do
			local t = (os.clock() - upStart) / Fx.PULSE_UP_TIME
			local eased = math.sin(t * math.pi * 0.5) -- easeOutSine
			local aNow = targetAlpha + (Fx.PEAK_ALPHA - targetAlpha) * eased
			_setGuiAlpha(billboard, aNow)
			task.wait(0.016)
			local a2 = ActiveUxp[part]; if not a2 or a2.token ~= token then return end
		end
		_setGuiAlpha(billboard, Fx.PEAK_ALPHA)

		local a3 = ActiveUxp[part]; if not a3 or a3.token ~= token then return end
		-- DOWN: size back to base, alpha back to base target
		local tiDown = TweenInfo.new(Fx.PULSE_DOWN_TIME, Fx.EASING, Enum.EasingDirection.In)
		_tween(billboard, tiDown, { Size = baseSize })
		local dnStart = os.clock()
		while os.clock() - dnStart < Fx.PULSE_DOWN_TIME do
			local t = (os.clock() - dnStart) / Fx.PULSE_DOWN_TIME
			local eased = 1 - math.cos(t * math.pi * 0.5) -- easeInSine
			local aNow = Fx.PEAK_ALPHA + (targetAlpha - Fx.PEAK_ALPHA) * eased
			_setGuiAlpha(billboard, aNow)
			task.wait(0.016)
			local a4 = ActiveUxp[part]; if not a4 or a4.token ~= token then return end
		end
		_setGuiAlpha(billboard, targetAlpha)
	end

	-- Fade out gently, keep size at base
	local tiOut = TweenInfo.new(Fx.FADE_OUT_TIME, Fx.EASING, Enum.EasingDirection.In)
	_tween(billboard, tiOut, { Size = baseSize })
	local outStart = os.clock()
	while os.clock() - outStart < Fx.FADE_OUT_TIME do
		local t = (os.clock() - outStart) / Fx.FADE_OUT_TIME
		local eased = 1 - math.cos(t * math.pi * 0.5)
		local aNow = targetAlpha + (1.0 - targetAlpha) * eased
		_setGuiAlpha(billboard, aNow)
		task.wait(0.016)
		local a5 = ActiveUxp[part]; if not a5 or a5.token ~= token then return end
	end
	_setGuiAlpha(billboard, 1.0) -- fully hidden before cleanup
end

-- NEW: pollution-only linger coroutine (fade-in → HOLD → fade-out)
local function _lingerGui(billboard: BillboardGui, holdSeconds: number, token: number, part: BasePart)
	-- Start fully hidden; fade in to pollution base alpha
	_setGuiAlpha(billboard, 1.0)
	local tiIn = TweenInfo.new(Fx.POLLUTION_FADE_IN, Fx.EASING, Enum.EasingDirection.Out)
	_tween(billboard, tiIn, {}) -- keep size; only alpha via loop

	local fadeInStart = os.clock()
	while os.clock() - fadeInStart < Fx.POLLUTION_FADE_IN do
		local t = (os.clock() - fadeInStart) / Fx.POLLUTION_FADE_IN
		local aNow = (1 - t) * 1.0 + t * Fx.POLLUTION_BASE_ALPHA
		_setGuiAlpha(billboard, aNow)
		task.wait(0.016)
		local a = ActiveUxp[part]; if not a or a.token ~= token then return end
	end
	_setGuiAlpha(billboard, Fx.POLLUTION_BASE_ALPHA)

	-- Hold visibly
	local holdStart = os.clock()
	while os.clock() - holdStart < holdSeconds do
		task.wait(0.05)
		local a = ActiveUxp[part]; if not a or a.token ~= token then return end
	end

	-- Fade out
	local tiOut = TweenInfo.new(Fx.POLLUTION_FADE_OUT, Fx.EASING, Enum.EasingDirection.In)
	_tween(billboard, tiOut, {})
	local outStart = os.clock()
	while os.clock() - outStart < Fx.POLLUTION_FADE_OUT do
		local t = (os.clock() - outStart) / Fx.POLLUTION_FADE_OUT
		local aNow = Fx.POLLUTION_BASE_ALPHA + (1.0 - Fx.POLLUTION_BASE_ALPHA) * t
		_setGuiAlpha(billboard, aNow)
		task.wait(0.016)
		local a2 = ActiveUxp[part]; if not a2 or a2.token ~= token then return end
	end
	_setGuiAlpha(billboard, 1.0)
end

local function _throttleKey(player: Player, zoneId: string, alarmType: string, x: number, z: number): string
	return tostring(player.UserId).."|"..zoneId.."|"..alarmType.."|"..tostring(x).."|"..tostring(z)
end

local function _spawnUxpAlarm(player: Player, zoneId: string, x: number, z: number, alarmType: string, tint: Color3?)
	-- Suppress FX during load-safe window
	if _isLoadSafe(player) then return end
	if not VALID_UXP_ALARM_TYPES[alarmType] then return end
	local now = os.clock()
	local key = _throttleKey(player, zoneId, alarmType, x, z)
	if (_lastFlashAt[key] or 0) + Fx.THROTTLE_PER_TILE > now then
		return -- rate-limit micro-spam on rapid recompute
	end
	_lastFlashAt[key] = now

	-- Upgrade/downgrade: push to client via RemoteEvent to avoid world replication spam.
	if (alarmType == "AlarmUpgrade" or alarmType == "AlarmDowngrade") and UxpAlarmRE then
		local tintData = tint and { tint.R, tint.G, tint.B } or nil
		UxpAlarmRE:FireClient(player, alarmType, zoneId, x, z, tintData)
		return
	end

	local zoneModel, playerPlot = _getZoneModelFor(player, zoneId)
	if not (zoneModel and playerPlot) then return end

	local container = _ensureUxpFolder(zoneModel)
	local name = string.format("%s_%d_%d", alarmType, x, z)
	local existing = container:FindFirstChild(name)

	local part: BasePart
	if existing and existing:IsA("BasePart") then
		part = existing
	else
		local p = _borrowUxpAlarm(alarmType)
		if not p then return end
		part = p
		part.Name   = name
		part.Parent = container
	end

	-- position (pollution sits higher)
	local offsetY = Fx.POLLUTION_TYPES[alarmType] and Fx.POLLUTION_OFFSET_Y or Fx.ALARM_OFFSET_Y
	local pos = _gridToWorld(playerPlot, x, z) + Vector3.new(0, offsetY, 0)
	part.Position = pos

	-- pulse/linger selection
	local billboard = part:FindFirstChild("BillboardGui")
	local token = ((ActiveUxp[part] and ActiveUxp[part].token) or 0) + 1

	-- Per-type TTL
	local ttl = Fx.POLLUTION_TYPES[alarmType] and Fx.POLLUTION_TTL or Fx.ALARM_TTL
	ActiveUxp[part] = { token = token, expires = now + ttl }

	if billboard and billboard:IsA("BillboardGui") then
		_prepBillboard(billboard)

		-- Apply per-grid tint (discrete progress color), fallback to sensible default
		local frame = billboard:FindFirstChild("Frame")
		local icon  = frame and frame:FindFirstChild("icon") or billboard:FindFirstChild("icon")
		if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
			if tint then
				dprintFX("Applying tint:", tint, alarmType)
				icon.ImageColor3 = tint
			else
				if alarmType == "AlarmUpgrade" then
					icon.ImageColor3 = Color3.fromRGB(32, 210, 120)
				elseif alarmType == "AlarmDowngrade" then
					icon.ImageColor3 = CityInteractions._DOWNGRADE_COLOR
				elseif Fx.POLLUTION_TYPES[alarmType] then
					-- Keep existing icon color if your template encodes a specific pollution hue.
					-- (No change = respect template styling.)
				end
			end
		end
	end

	task.spawn(function()
		if billboard and billboard:IsA("BillboardGui") then
			if Fx.POLLUTION_TYPES[alarmType] then
				_lingerGui(billboard, Fx.POLLUTION_HOLD_TIME, token, part)
			else
				_pulseGui(billboard, Fx.PULSE_CYCLES, token, part)
			end
		end
	end)

	-- schedule auto-return (refreshed if retriggered)
	task.delay(ttl, function()
		local a = ActiveUxp[part]
		if not a or a.token ~= token then return end
		_returnUxpAlarm(part)
	end)
end

function CityInteractions._clearUxpAlarmsForZone(player: Player, zoneId: string)
	local zoneModel = select(1, _getZoneModelFor(player, zoneId))
	if not zoneModel then return end
	local f = zoneModel:FindFirstChild(Fx.ALARM_FOLDER_NAME)
	if not f then return end
	for _, ch in ipairs(f:GetChildren()) do
		if ch:IsA("BasePart") then
			_returnUxpAlarm(ch)
		else
			ch:Destroy()
		end
	end
	f:Destroy()
end

local function _computeTileIncomePositiveBonus(player: Player, zoneId: string, x: number, z: number, targetMode: string): number
	local zdata = _getZoneDataFromCache(player, zoneId)
	if not zdata then return 0 end
	return _computeTilePositiveBonus(player, zdata, { x = x, z = z })
end

-- Public: positive-income multiplier (1 + bonus)
function CityInteractions.getTileIncomePositiveMultiplier(
	player: Player, zoneId: string, x: number, z: number, targetMode: string
): number
	local key = _tkey(x, z)
	local cached = _getTilePositiveBonus(player, zoneId, key)
	if cached == nil then
		local bonus = _computeTileIncomePositiveBonus(player, zoneId, x, z, targetMode)
		_setTilePositiveBonus(player, zoneId, key, bonus)
		cached = bonus
	end
	return 1 + cached
end

-- Public: convenience net multiplier = (1 - penalty) * (1 + bonus)
function CityInteractions.getTileIncomeNetMultiplier(
	player: Player, zoneId: string, x: number, z: number, targetMode: string
): number
	local neg = CityInteractions.getTileIncomePollutionMultiplier(player, zoneId, x, z) -- existing
	local pos = CityInteractions.getTileIncomePositiveMultiplier(player, zoneId, x, z, targetMode)
	return math.max(0, neg * pos)
end

local function _piRule(targetMode: string, sourceMode: string)
	local cfg = (Interactions and Interactions.PollutionIncome) or nil
	if not cfg then return nil end
	local t = cfg[targetMode]; if not t then return nil end
	return t[sourceMode]
end

local function _piRecoveryPerTick(): number
	local cfg = (Interactions and Interactions.PollutionIncome) or nil
	local r = cfg and cfg.RecoveryPerTick
	return (type(r) == "number" and r >= 0) and r or 0.02
end

local function _piBatchSizeFor(z: ZoneData): number
	local cfg = (Interactions and Interactions.PollutionIncome) or nil
	local N = #z.gridList
	if N <= 0 then return 0 end

	-- Prefer absolute BatchSize when provided
	local bs = cfg and cfg.BatchSize
	if type(bs) == "number" and bs >= 1 then
		return math.max(1, math.min(N, math.floor(bs)))
	end

	-- Else use BatchFrac (default ~25% of tiles per tick), clamped
	local frac = cfg and cfg.BatchFrac
	if type(frac) ~= "number" or frac <= 0 or frac > 1 then
		frac = 0.25  -- sane default
	end
	return math.max(1, math.min(N, math.floor(N * frac + 0.5)))
end

local function _pollutionSourcesAtTile(tile: GridTile, neighbors: { ZoneData }): { Industrial: boolean, IndusDense: boolean }
	local present = { Industrial = false, IndusDense = false }

	-- Industrial
	do
		local w  = getPollutionWidth("Industrial")
		for _, other in ipairs(neighbors) do
			if other.mode == "Industrial" then
				local bb = other.boundingBox
				if tile.x >= bb.minX - w and tile.x <= bb.maxX + w
					and tile.z >= bb.minZ - w and tile.z <= bb.maxZ + w then
					for _, tB in ipairs(other.gridList) do
						if isNearby(tile, tB, w) then present.Industrial = true; break end
					end
					if present.Industrial then break end
				end
			end
		end
	end

	-- IndusDense
	do
		local w  = getPollutionWidth("IndusDense")
		for _, other in ipairs(neighbors) do
			if other.mode == "IndusDense" then
				local bb = other.boundingBox
				if tile.x >= bb.minX - w and tile.x <= bb.maxX + w
					and tile.z >= bb.minZ - w and tile.z <= bb.maxZ + w then
					for _, tB in ipairs(other.gridList) do
						if isNearby(tile, tB, w) then present.IndusDense = true; break end
					end
					if present.IndusDense then break end
				end
			end
		end
	end

	return present
end

-- Apply one tick of decay/recovery to a specific tile
local function _tickIncomePollutionTile(player: Player, z: ZoneData, tile: GridTile, neighbors: { ZoneData }, pollutedNow: boolean)
	_incomePollutionTiles[player] = _incomePollutionTiles[player] or {}
	_incomePollutionTiles[player][z.zoneId] = _incomePollutionTiles[player][z.zoneId] or {}
	local tkey = _tkey2(tile.x, tile.z)
	local cur  = _incomePollutionTiles[player][z.zoneId][tkey] or 0
	local newP = cur

	if pollutedNow then
		local prs  = _pollutionSourcesAtTile(tile, neighbors)
		local add  = 0
		local cap  = 0
		local r

		-- Industrial contribution (if allowed for this target mode)
		r = _piRule(z.mode, "Industrial")
		if prs.Industrial and r then
			add += (r.RatePerTick or 0)
			cap  = math.max(cap, r.Cap or 0)
		end

		-- IndusDense contribution
		r = _piRule(z.mode, "IndusDense")
		if prs.IndusDense and r then
			add += (r.RatePerTick or 0)
			cap  = math.max(cap, r.Cap or 0)
		end

		newP = math.min(cap, cur + add)
	else
		newP = math.max(0, cur - _piRecoveryPerTick())
	end

	if newP ~= cur then
		_incomePollutionTiles[player][z.zoneId][tkey] = newP
		if DEBUG_SYNERGY then
			print(("[IncomePollutionTile] %s (%s) @ (%d,%d): %.3f → %.3f")
				:format(z.zoneId, z.mode, tile.x, tile.z, cur, newP))
		end
	end
end

-- Tick a *slice* of tiles, rotating across ticks so the whole zone is covered over time.
local function _tickIncomePollutionBatch(player: Player, z: ZoneData, neighbors: { ZoneData }, pollutedNow: boolean)
	local tiles = z.gridList
	local N = #tiles
	if N == 0 then return end

	-- batch size per zone
	local batch = _piBatchSizeFor(z)
	if batch <= 0 then return end

	-- get/advance cursor
	_pollTickCursor[player] = _pollTickCursor[player] or {}
	local cur = _pollTickCursor[player][z.zoneId] or 1
	if cur > N then cur = 1 end

	-- tick [cur .. cur+batch-1] modulo N
	local i = cur
	for c = 1, batch do
		_tickIncomePollutionTile(player, z, tiles[i], neighbors, pollutedNow)
		i = i + 1
		if i > N then i = 1 end
	end

	_pollTickCursor[player][z.zoneId] = i
end
-- =========================================================================================
-- END UXP FLASH ALARM SYSTEM
-- =========================================================================================

-- NEW: public getters for per-tile income pollution
function CityInteractions.getTileIncomePollutionPenalty(player: Player, zoneId: string, x: number, z: number): number
	local m = _incomePollutionTiles[player]
	local zmap = m and m[zoneId]
	return (zmap and zmap[_tkey2(x, z)]) or 0
end

function CityInteractions.getTileIncomePollutionMultiplier(player: Player, zoneId: string, x: number, z: number): number
	local p = CityInteractions.getTileIncomePollutionPenalty(player, zoneId, x, z)
	return math.max(0, 1 - p)
end

local function _isZonePopulating(player: Player, zoneId: string): boolean
	if _isZonePending(player, zoneId) then
		if _isStage3Populated(player, zoneId) then
			_clearZonePending(player, zoneId)
		else
			return true
		end
	end
	-- Prefer ZoneTracker API if available
	if ZoneTracker and type((ZoneTracker :: any).isZonePopulating) == "function" then
		local ok, res = pcall(function()
			return (ZoneTracker :: any).isZonePopulating(player, zoneId)
		end)
		if ok and type(res) == "boolean" then return res end
	end
	-- Fallback: treat as populating until we know Stage3 is populated
	return not _isStage3Populated(player, zoneId)
end

local function _shouldDeferWealthChanges(player: Player, zoneId: string): boolean
	return _isZonePopulating(player, zoneId)
end

local function _drainBulkRebuild(player: Player, zoneId: string)
	local map = _pendingBulkRebuild[player]
	if not (map and map[zoneId]) then return end
	map[zoneId] = nil
	if not next(map) then
		_pendingBulkRebuild[player] = nil
	end
	task.defer(function()
		-- guard again in case the zone went back into populate mode mid-yield
		if not _shouldDeferWealthChanges(player, zoneId) then
			CityInteractions.bulkWealthRebuild(player, zoneId)
		else
			_queueBulkRebuild(player, zoneId)
		end
	end)
end

local function _queueWealthChanges(
	player: Player, zoneId: string, changes: { { x: number, z: number, wealth: string } }
)
	_pendingWealth[player] = _pendingWealth[player] or {}
	_pendingWealth[player][zoneId] = _pendingWealth[player][zoneId] or {}
	for _, ch in ipairs(changes) do
		_pendingWealth[player][zoneId][_tkey(ch.x, ch.z)] = ch.wealth
	end
end

local function _augmentBucketsWithModelMismatches(
	player: Player,
	zoneId: string,
	zoneData: ZoneData?,
	intents: { [string]: string },
	changedSet: { [string]: boolean },
	buckets: { [string]: { { x: number, z: number } } }
)
	if next(changedSet) then return end
	if not (zoneData and zoneData.gridList and #zoneData.gridList > 0) then return end
	if not (BuildingGeneratorModule and BuildingGeneratorModule.collectInstancesTouchingTiles) then return end

	local tileSet = {}
	for _, coord in ipairs(zoneData.gridList) do
		tileSet[_tkey(coord.x, coord.z)] = true
	end

	local touching = BuildingGeneratorModule.collectInstancesTouchingTiles(player, zoneId, tileSet)
	if typeof(touching) ~= "table" then return end

	for _, rec in ipairs(touching) do
		local key = _tkey(rec.originGX, rec.originGZ)
		local intended = intents[key]
		if intended then
			local inst = rec.inst
			local current = (inst and inst:GetAttribute("WealthState"))
				or ZoneTracker.getGridWealth(player, zoneId, rec.originGX, rec.originGZ)
				or "Poor"
			if current ~= intended then
				if not changedSet[key] then
					changedSet[key] = true
					buckets[intended] = buckets[intended] or {}
					table.insert(buckets[intended], { x = rec.originGX, z = rec.originGZ })
				end
			end
		end
	end
end

function CityInteractions._flushPendingWealthForZone(player: Player, zoneId: string)
	_applyLock[player] = _applyLock[player] or {}
	if _applyLock[player][zoneId] then return end
	_applyLock[player][zoneId] = true

	local function _unlock()
		if _applyLock[player] then
			_applyLock[player][zoneId] = nil
			if not next(_applyLock[player]) then _applyLock[player] = nil end
		end
	end

	local zoneMap = _pendingWealth[player] and _pendingWealth[player][zoneId]
	if not zoneMap or not next(zoneMap) then
		_unlock()
		return
	end

	-- Resolve mode
	local zdata = _getZoneDataFromCache(player, zoneId)
	if not zdata then
		CityInteractions.rebuildCacheFromTracker(player)
		zdata = _getZoneDataFromCache(player, zoneId)
	end
	local mode = zdata and zdata.mode
	if not mode then
		local z = ZoneTracker.getZoneById and ZoneTracker.getZoneById(player, zoneId)
		mode = z and z.mode or "Residential"
	end

	-- Materialize queued intents (deduped already as a map)
	local list = {}
	for key, wealth in pairs(zoneMap) do
		local sep = string.find(key, "|", 1, true)
		local x = tonumber(string.sub(key, 1, sep - 1))
		local z = tonumber(string.sub(key, sep + 1))
		table.insert(list, { x = x, z = z, wealth = wealth })
	end

	-- Clear queue for this zone before we mutate the world
	_pendingWealth[player][zoneId] = nil
	if not next(_pendingWealth[player]) then _pendingWealth[player] = nil end

	-- Compute XP for upward moves (mirrors calculateGridUXP batching)
	local batchXP = 0
	do
		local statConf = (Balance and Balance.StatConfig and Balance.StatConfig[mode]) or nil
		if statConf then
			local TIER = { Poor = 0, Medium = 1, Wealthy = 2 }
			for _, ch in ipairs(list) do
				local oldState = ZoneTracker.getGridWealth(player, zoneId, ch.x, ch.z) or "Poor"
				local delta = (TIER[ch.wealth] or 0) - (TIER[oldState] or 0)
				if delta > 0 then
					local cfg = statConf[ch.wealth]
					local exp = (cfg and cfg.exp) or 0
					if type(exp) == "number" and exp > 0 then batchXP += exp end
				end
			end
		end
	end

	-- If many tiles changed, do an atomic, local bulk rebuild instead of piecemeal applies.
	if #list >= BULK_REBUILD_THRESHOLD then
		-- Bulk path recomputes the intent, removes all touching instances in one sweep,
		-- sets tracker truth, and refills strictly by seeded cells per wealth bucket.
		CityInteractions.bulkWealthRebuild(player, zoneId)
		if batchXP > 0 then
			XPManager.addXP(player, batchXP, zoneId)
		end
		_unlock()
		return
	end

	-- Small change set: keep precise per-tile apply pipeline
	local ok, err = pcall(function()
		CityInteractions._applyWealthBatch(player, zoneId, mode, list)
	end)
	if not ok then
		warn(("[GridUXP] _applyWealthBatch failed for %s (%d changes): %s")
			:format(zoneId, #list, tostring(err)))
	else
		if batchXP > 0 then
			XPManager.addXP(player, batchXP, zoneId)
		end
	end

	_unlock()
end



-- ===== Cache maintenance =====
function CityInteractions.rebuildCacheFromTracker(player: Player)
	zoneCacheByPlayer[player] = {}
	_positiveBonusTiles[player] = nil
	local zonesAny: any = ZoneTracker.getAllZones(player)
	local idx = _getSpatialIndex(player, true)
	if idx then idx:clear() end
	for _, z in pairs(zonesAny) do
		local mode: string = z.mode
		if not IGNORE_ZONE_TYPES[mode] then
			local gridList: { GridTile } = z.gridList
			local entry = {
				zoneId      = z.zoneId,
				mode        = mode,
				gridList    = gridList,
				player      = player,
				boundingBox = computeBoundingBox(gridList),
			}
			table.insert(zoneCacheByPlayer[player], entry)
			if idx then idx:add(entry) end
		end
	end
	if idx then
		for _, entry in ipairs(zoneCacheByPlayer[player]) do
			_refreshPositiveIncomeForZone(player, entry)
		end
	end
end

-- ===== Synergy (unchanged) =====
local function computeAggregateSynergy(target: ZoneData, neighbors: { ZoneData }): number
	if not VALID_ZONE_TYPES[target.mode] then return 0 end
	local map = synergyMapping[target.mode]; if not map then return 0 end

	local candidateList = neighbors
	local idx = _getSpatialIndex(target.player, false)
	if idx and target.boundingBox then
		local radius = MAX_SYNERGY_RADIUS_BY_TARGET[target.mode] or ADJACENCY_RADIUS
		candidateList = idx:queryAabb(target.boundingBox, radius)
	end

	local total = 0
	for _, other in ipairs(candidateList) do
		if other.zoneId ~= target.zoneId and VALID_ZONE_TYPES[other.mode] and not IGNORE_ZONE_TYPES[other.mode] then
			-- Use the *emitter's* synergy width for both AABB precheck and per-tile proximity
			local w  = getSynergyWidth(other.mode)
			local bb = other.boundingBox

			-- Fast AABB check: expand 'other' bounds by its influence width
			if target.boundingBox.maxX >= bb.minX - w and target.boundingBox.minX <= bb.maxX + w
				and target.boundingBox.maxZ >= bb.minZ - w and target.boundingBox.minZ <= bb.maxZ + w then

				-- Per-tile proximity using emitter's width
				local adjacent = false
				for _, tA in ipairs(target.gridList) do
					for _, tB in ipairs(other.gridList) do
						if isNearby(tA, tB, w) then adjacent = true break end
					end
					if adjacent then break end
				end

				if adjacent then
					local s = map[other.mode] or 0
					if s ~= 0 then
						total += s
						dprintSYN(string.format("+ Synergy %s→%s = %+d (running=%d)", target.mode, other.mode, s, total))
					end
				end
			end
		end
	end
	return total
end

local function computeAggregatePollution(target: ZoneData, neighbors: { ZoneData }): number
	if not VALID_ZONE_TYPES[target.mode] then return 0 end
	local map = synergyMapping[target.mode]; if not map then return 0 end

	if DEBUG_SYNERGY then
		print(("[PollutionAgg] Target %s (%s) tiles=%d"):format(target.zoneId, target.mode, #target.gridList))
	end

	local candidateList = neighbors
	local idx = _getSpatialIndex(target.player, false)
	if idx and target.boundingBox then
		local radius = MAX_SYNERGY_RADIUS_BY_TARGET[target.mode] or ADJACENCY_RADIUS
		candidateList = idx:queryAabb(target.boundingBox, radius)
	end

	local total = 0
	for _, other in ipairs(candidateList) do
		if other.zoneId ~= target.zoneId
			and VALID_ZONE_TYPES[other.mode]
			and not IGNORE_ZONE_TYPES[other.mode]
			and _pollutionAllowed(target.mode, other.mode)
		then
			local w  = getPollutionWidth(other.mode)
			local bb = other.boundingBox

			local aabbHit = (target.boundingBox.maxX >= bb.minX - w and target.boundingBox.minX <= bb.maxX + w
				and target.boundingBox.maxZ >= bb.minZ - w and target.boundingBox.minZ <= bb.maxZ + w)

			if DEBUG_SYNERGY then
				print(("[PollutionAgg]   src=%s w=%d aabb=%s"):format(other.mode, w, tostring(aabbHit)))
			end

			if aabbHit then
				local adjacent = false
				for _, tA in ipairs(target.gridList) do
					for _, tB in ipairs(other.gridList) do
						if isNearby(tA, tB, w) then adjacent = true break end
					end
					if adjacent then break end
				end
				if DEBUG_SYNERGY then
					print(("[PollutionAgg]   src=%s adjacent=%s"):format(other.mode, tostring(adjacent)))
				end

				if adjacent then
					local s = map[other.mode] or 0
					if s < 0 then
						total += s
						if DEBUG_SYNERGY then
							print(("[PollutionAgg]   src=%s contributes %d (running %d)"):format(other.mode, s, total))
						end
					else
						if DEBUG_SYNERGY then
							print(("[PollutionAgg]   src=%s has non-negative map=%d (ignored for pollution)"):format(other.mode, s))
						end
					end
				end
			end
		elseif DEBUG_SYNERGY and other.zoneId ~= target.zoneId then
			print(("[PollutionAgg]   src=%s allowed=%s ignored=%s"):format(other.mode,tostring(_pollutionAllowed(target.mode, other.mode)),tostring(IGNORE_ZONE_TYPES[other.mode] == true)))
		end
	end

	if DEBUG_SYNERGY then
		print(("[PollutionAgg] TOTAL for %s = %d"):format(target.zoneId, total))
	end
	return total
end

local function computeTileNegativeSynergy(target: ZoneData, neighbors: { ZoneData }, tile: GridTile): number
	if not VALID_ZONE_TYPES[target.mode] then return 0 end
	local map = synergyMapping[target.mode]; if not map then return 0 end

	local negSum = 0
	local candidateList = neighbors
	local idx = _getSpatialIndex(target.player, false)
	if idx then
		local radius = MAX_SYNERGY_RADIUS_BY_TARGET[target.mode] or ADJACENCY_RADIUS
		candidateList = idx:queryRadius(tile.x, tile.z, radius)
	end
	for _, other in ipairs(candidateList) do
		if other.zoneId ~= target.zoneId
			and VALID_ZONE_TYPES[other.mode]
			and not IGNORE_ZONE_TYPES[other.mode]
			and _pollutionAllowed(target.mode, other.mode)
		then
			local w  = getPollutionWidth(other.mode)
			local bb = other.boundingBox

			local inAabb = (tile.x >= bb.minX - w and tile.x <= bb.maxX + w
				and tile.z >= bb.minZ - w and tile.z <= bb.maxZ + w)

			if inAabb then
				for _, tB in ipairs(other.gridList) do
					if isNearby(tile, tB, w) then
						local s = map[other.mode] or 0
						if s < 0 then
							negSum += s
							if DEBUG_SYNERGY then
								print(("[PollutionTile] %s (%d,%d) hit by %s w=%d add=%d total=%d")
									:format(target.zoneId, tile.x, tile.z, other.mode, w, s, negSum))
							end
						elseif DEBUG_SYNERGY then
							print(("[PollutionTile] %s (%d,%d) map non-negative from %s (%d) — ignored")
								:format(target.zoneId, tile.x, tile.z, other.mode, s))
						end
						break
					end
				end
			elseif DEBUG_SYNERGY then
				print(("[PollutionTile] %s (%d,%d) outside AABB of %s w=%d")
					:format(target.zoneId, tile.x, tile.z, other.mode, w))
			end
		end
	end
	return negSum
end

local function _startPollutionClock(player: Player, zoneId: string)
	_pollutionClock[player] = _pollutionClock[player] or {}

	-- If already ticking, don't spawn a second loop.
	if _pollutionClock[player][zoneId] then return end

	_notifyPollution(player, zoneId)
	_pollutionClock[player][zoneId] = { token = 1 }
	local myToken = 1

	task.spawn(function()
		local okStreak = 0
		while true do
			-- still active?
			local slot = _pollutionClock[player] and _pollutionClock[player][zoneId]
			if not slot or slot.token ~= myToken then break end

			-- wait with jitter
			local waitFor = POLLUTION_CLOCK_PERIOD_SEC + (math.random() * 2 - 1) * POLLUTION_CLOCK_JITTER_SEC
			task.wait(math.max(0.5, waitFor))

			-- still active?
			slot = _pollutionClock[player] and _pollutionClock[player][zoneId]
			if not slot or slot.token ~= myToken then break end

			-- lookup zone + re-evaluate pollution using current cache
			local z = _getZoneDataFromCache(player, zoneId); if not z then break end
			local cache = zoneCacheByPlayer[player] or {}
			local pollutionSum = computeAggregatePollution(z, cache)
			if DEBUG_SYNERGY then
				print(("[PollutionClock] zone=%s sum=%d thresh=%d"):format(z.zoneId, pollutionSum, -SYNERGY_UPGRADE_THRESHOLD))
			end

			if pollutionSum <= -SYNERGY_UPGRADE_THRESHOLD then
				----------------------------------------------------------------------
				-- POLLUTED: tick per-tile income penalty upward (decay income)
				----------------------------------------------------------------------
				_tickIncomePollutionBatch(player, z, cache, true)

				-- Re-arm only tiles actually under negative influence (alarmed sampling)
				local n = 0
				for i = 1, #z.gridList, 2 do -- sample every 2nd tile
					local tile = z.gridList[i]
					local tSum = computeTileNegativeSynergy(z, cache, tile)
					if tSum <= -SYNERGY_UPGRADE_THRESHOLD then
						_spawnUxpAlarm(player, zoneId, tile.x, tile.z, "AlarmPollution")
						n += 1
						if n >= POLLUTION_CLOCK_MAX_PER_TICK then break end
					end
				end

				okStreak = 0
			else
				----------------------------------------------------------------------
				-- CLEAN: tick per-tile income penalty downward (recover income)
				----------------------------------------------------------------------
				_tickIncomePollutionBatch(player, z, cache, false)

				okStreak += 1
				if okStreak >= POLLUTION_CLOCK_SILENCE_AFTER_OK then
					break -- stop after a few consecutive OK checks
				end
			end
		end

		-- cleanup for this zoneId
		if _pollutionClock[player] then
			_pollutionClock[player][zoneId] = nil
			if not next(_pollutionClock[player]) then _pollutionClock[player] = nil end
		end
	end)
end

local function _stopPollutionClock(player: Player, zoneId: string)
	local m = _pollutionClock[player]; if not m then return end
	local slot = m[zoneId]; if not slot then return end
	slot.token += 1 -- invalidate loop
	m[zoneId] = nil
	if not next(m) then _pollutionClock[player] = nil end
	_markPollutionNotice(player, zoneId, false)
end

-- Optional: after load, seed clocks for any zones that already have negative synergy.
local function _kickPollutionClocksForPlayer(player: Player)
	local cache = zoneCacheByPlayer[player]; if not cache then return end
	for _, z in ipairs(cache) do
		if VALID_ZONE_TYPES[z.mode] then
			local pol = computeAggregatePollution(z, cache) -- pollution-only
			if pol <= -SYNERGY_UPGRADE_THRESHOLD then
				_startPollutionClock(player, z.zoneId)
			else
				_stopPollutionClock(player, z.zoneId)
			end
		end
	end
end


function CityInteractions.calculateZoneSynergy(player: Player, newZoneData: ZoneData)
	if IGNORE_ZONE_TYPES[newZoneData.mode] then dprintSYN("Skipping synergy for excluded type: " .. newZoneData.mode) return end
	if not VALID_ZONE_TYPES[newZoneData.mode] then dprintSYN("Irrelevant synergy type: " .. newZoneData.mode) return end
	local allZones = zoneCacheByPlayer[player]; if not allZones or #allZones == 0 then dprintSYN("No cached zones; skipping synergy.") return end

	-- Optional: compute synergy ONLY for debug/logging (no upgrades here)
	local sum = computeAggregateSynergy(newZoneData, allZones)
	if sum ~= 0 then
		dprintSYN(string.format("Aggregate synergy for %s (%s) = %d", newZoneData.zoneId, newZoneData.mode, sum))
	end

	-- Use pollution-only aggregate for alarms/clock
	local pollutionSum = computeAggregatePollution(newZoneData, allZones)
	if DEBUG_SYNERGY then
		print(("[PollutionCalc] zone=%s sum=%d thresh=%d"):format(newZoneData.zoneId, pollutionSum, -SYNERGY_UPGRADE_THRESHOLD))
	end
	if pollutionSum <= -SYNERGY_UPGRADE_THRESHOLD then
		-- visualize “bad neighbor” only where tiles are actually under negative influence
		do
			local n = 0
			for i = 1, #newZoneData.gridList, 2 do
				local t = newZoneData.gridList[i]
				local ts = computeTileNegativeSynergy(newZoneData, allZones, t)
				if ts <= -SYNERGY_UPGRADE_THRESHOLD then
					if DEBUG_SYNERGY then
						print(("[PollutionCalc] spawn @ (%d,%d) zone=%s ts=%d"):format(t.x, t.z, newZoneData.zoneId, ts))
					end
					_spawnUxpAlarm(newZoneData.player, newZoneData.zoneId, t.x, t.z, "AlarmPollution")
					n += 1
					if n >= POLLUTION_CLOCK_MAX_PER_TICK then break end
				end
			end
		end
		_startPollutionClock(player, newZoneData.zoneId)
	else
		_stopPollutionClock(player, newZoneData.zoneId)
	end
end

local function _isWealthedMode(mode: string): boolean
	return WEALTHED_ZONES and WEALTHED_ZONES[mode] == true
end

-- Find Populated/{zoneId} and Populated/Utilities for this player's plot.
local function _getPopulatedContainers(player: Player, zoneId: string): (Folder?, Folder?, Instance?)
	local plotFolder = workspace:FindFirstChild("PlayerPlots")
	local playerPlot = plotFolder and plotFolder:FindFirstChild("Plot_" .. player.UserId)
	if not playerPlot then return nil, nil, nil end

	local buildings = playerPlot:FindFirstChild("Buildings")
	local populated = buildings and buildings:FindFirstChild("Populated")
	if not populated then return nil, nil, playerPlot end

	local zoneFolder      = populated:FindFirstChild(zoneId)
	local utilitiesFolder = populated:FindFirstChild("Utilities")
	return zoneFolder, utilitiesFolder, playerPlot
end

-- Does a world AABB contain an XZ point?
local function _aabbContainsXZ(center: Vector3, size: Vector3, p: Vector3): boolean
	return math.abs(p.X - center.X) <= size.X * 0.5
		and math.abs(p.Z - center.Z) <= size.Z * 0.5
end

-- Try to find the placed instance that "covers" grid (gx,gz) in this zone and return its WealthState.
-- Prefers exact origin (GridX/GridZ) match; falls back to a bounding-box test.
function CityInteractions._getTileInstanceWealth(player: Player, zoneId: string, gx: number, gz: number): (Instance?, string?)
	local zoneFolder, utilitiesFolder, playerPlot = _getPopulatedContainers(player, zoneId)
	if not playerPlot then return nil, nil end

	-- Where is the centre of the clicked tile (worldspace)?
	local tileWorld = _gridToWorld(playerPlot, gx, gz)

	local function probeFolder(folder: Instance?): (Instance?, string?)
		if not folder then return nil, nil end
		for _, inst in ipairs(folder:GetChildren()) do
			if (inst:IsA("Model") or inst:IsA("BasePart")) and inst:GetAttribute("ZoneId") == zoneId then
				-- (1) fast path: exact origin match
				if inst:GetAttribute("GridX") == gx and inst:GetAttribute("GridZ") == gz then
					return inst, inst:GetAttribute("WealthState")
				end

				-- (2) coverage fallback: bounding box contains tile centre
				local cf, size
				if inst:IsA("Model") then
					cf, size = inst:GetBoundingBox()
				else
					cf, size = inst.CFrame, inst.Size
				end
				if cf and size and _aabbContainsXZ(cf.Position, Vector3.new(size.X, 0, size.Z), tileWorld) then
					return inst, inst:GetAttribute("WealthState")
				end
			end
		end
		return nil, nil
	end

	-- Prefer the zone's folder, but also consider Utilities (roads, etc.) if they host this tile.
	local inst, wealth = probeFolder(zoneFolder)
	if inst then return inst, wealth end
	return probeFolder(utilitiesFolder)
end

-- Ensure a specific tile ends up at target wealth:
--  • If a building covers the tile and already matches -> noop.
--  • If a building covers the tile but wealth differs   -> call upgradeGrid (handles coverage/origin).
--  • If no building covers the tile                     -> report "gap" so the caller can back-fill.
function CityInteractions._ensureTileWealthAt(
	player: Player, zoneId: string, mode: string, gx: number, gz: number, targetWealth: string
): boolean
	local inst, currentWealth = CityInteractions._getTileInstanceWealth(player, zoneId, gx, gz)

	-- If something is there and already correct, we're done
	if inst and (currentWealth or "Poor") == targetWealth then
		return true
	end

	if inst then
		-- Let the generator do the heavy lifting (origin/coverage math, occupancy, backfill-on-shrink)
		BuildingGeneratorModule.upgradeGrid(player, zoneId, gx, gz, targetWealth, mode, "Default")
		-- ===========================================================
		-- FIX 2: re-verify coverage/wealth after upgradeGrid
		-- (if still wrong/empty, treat as a gap so we will backfill)
		-- ===========================================================
		local inst2, wealth2 = CityInteractions._getTileInstanceWealth(player, zoneId, gx, gz)
		if inst2 and (wealth2 or "Poor") == targetWealth then
			return true
		else
			return false
		end
	end

	-- Nothing covers the tile: tell caller this is a gap.
	return false
end

-- === NEW (FIX 3): local neighborhood gap sweep ===========================================
-- Catches newly orphaned tiles created by multi-cell model footprint changes in the small-batch path.
local LOCAL_GAP_SWEEP_RADIUS_CELLS = 3
local function _sweepLocalGapsAround(player: Player, zoneId: string, mode: string, changed: { { x: number, z: number, wealth: string } })
	if not changed or #changed == 0 then return end
	local z = _getZoneDataFromCache(player, zoneId)
	if not z then
		CityInteractions.rebuildCacheFromTracker(player)
		z = _getZoneDataFromCache(player, zoneId)
		if not z then return end
	end

	-- Build fast membership set for this zone’s tiles
	local zoneSet: { [string]: boolean } = {}
	for _, t in ipairs(z.gridList) do zoneSet[_tkey(t.x, t.z)] = true end

	local visited: { [string]: boolean } = {}
	local toFillByWealth: { [string]: { { x: number, z: number } } } = {}

	for _, ch in ipairs(changed) do
		for x = ch.x - LOCAL_GAP_SWEEP_RADIUS_CELLS, ch.x + LOCAL_GAP_SWEEP_RADIUS_CELLS do
			for zz = ch.z - LOCAL_GAP_SWEEP_RADIUS_CELLS, ch.z + LOCAL_GAP_SWEEP_RADIUS_CELLS do
				local key = _tkey(x, zz)
				if zoneSet[key] and not visited[key] then
					visited[key] = true
					local inst, _w = CityInteractions._getTileInstanceWealth(player, zoneId, x, zz)
					if not inst then
						-- Use the tracker’s current truth for the wealth we want to refill with.
						local intended = ZoneTracker.getGridWealth(player, zoneId, x, zz) or "Poor"
						toFillByWealth[intended] = toFillByWealth[intended] or {}
						table.insert(toFillByWealth[intended], { x = x, z = zz })
					end
				end
			end
		end
	end

	for w, cells in pairs(toFillByWealth) do
		if cells and #cells > 0 then
			CityInteractions._fillZoneGapsAtWealth(player, zoneId, mode, w, cells)
		end
	end
end
-- ===========================================================================================

-- Back-fill any empty tiles in the zone using the requested wealth (uses your exported helper).
-- SERIALIZED per-(player, zone): queues gap cells and flushes them in-order to ensure only one
-- BuildingGeneratorModule._refillZoneGaps runs at a time for that zone.
function CityInteractions._fillZoneGapsAtWealth(
	player: Player, zoneId: string, mode: string, wealth: string, gapCells: { { x: number, z: number } }?
)
	-- Accumulate cells in the per-zone pending queue.
	if gapCells and #gapCells > 0 then
		RefillQueue.addCells(player, zoneId, wealth, gapCells)
	else
		-- No seeds were provided (legacy callers). We intentionally do nothing here to avoid whole-zone
		-- sweeps from this path; CityInteractions only ever calls with seeds now.
		return
	end

	-- ======================================================
	-- FIX 4: safe lock init + single in-flight guard
	-- ======================================================
	_refillLock[player] = _refillLock[player] or {}
	if _refillLock[player][zoneId] then
		-- already flushing; the pending seeds we just added will be picked up
		return
	end
	_refillLock[player][zoneId] = true

	local epochAtStart = RefillQueue.getEpoch(player, zoneId)
	local function shouldRefillStop(): boolean
		if RefillQueue.getEpoch(player, zoneId) ~= epochAtStart then
			return true
		end
		if not ZoneTracker.getZoneById(player, zoneId) then
			return true
		end
		return false
	end

	local aborted = false
	while RefillQueue.hasAny(player, zoneId) do
		if shouldRefillStop() then
			aborted = true
			break
		end
		local wealthToRun, cellsToRun = RefillQueue.popOne(player, zoneId)
		if not wealthToRun or not cellsToRun or #cellsToRun == 0 then break end

		-- NEW: cluster & cap batch size (smaller during load-safe)
		local cfg = _seedClusterCfgFor(player)
		local clusters = cfg.enabled and _clusterSeedCells(cellsToRun, cfg) or { cellsToRun }
		for _, cluster in ipairs(clusters) do
			if shouldRefillStop() then
				aborted = true
				break
			end
			if type((BuildingGeneratorModule :: any)._refillZoneGaps) == "function" then
				(BuildingGeneratorModule :: any)._refillZoneGaps(
					player, zoneId, mode, wealthToRun,
					nil, "Default",
					nil,         -- refillSourceZoneId (none for UXP path)
					cluster      -- ← seed whitelist (cluster)
				)
			end
			if shouldRefillStop() then
				aborted = true
				break
			end
			-- polite yield to keep the server responsive
			task.wait((cfg and cfg.yield_between) or 0.02)
		end
		if aborted then break end
	end
	if aborted then
		RefillQueue.clearPending(player, zoneId)
	end
	RefillQueue.unlock(player, zoneId)
end

-- Apply a batch of {x,z,wealth} intentions by:
--   (a) aligning any existing models to the intended wealth via upgradeGrid, and
--   (b) filling any gaps per-wealth across the zone (so newly empty tiles also get populated properly).
function CityInteractions._applyWealthBatch(
	player: Player,
	zoneId: string,
	mode: string,
	changes: { { x: number, z: number, wealth: string } }
)
	if not changes or #changes == 0 then return end

	-- Track whether we saw gaps for each wealth bucket
	local gapsByWealth: { [string]: { { x: number, z: number } } } = {}

	for _, chg in ipairs(changes) do
		local ok = CityInteractions._ensureTileWealthAt(player, zoneId, mode, chg.x, chg.z, chg.wealth)
		if not ok then
			gapsByWealth[chg.wealth] = gapsByWealth[chg.wealth] or {}
			table.insert(gapsByWealth[chg.wealth], { x = chg.x, z = chg.z })
		end
		-- Mirror intention immediately
		ZoneTracker.setGridWealth(player, zoneId, chg.x, chg.z, chg.wealth)
	end

	-- Seeded back-fill: only the actual gap cells per wealth (serialized per zone)
	for w, cells in pairs(gapsByWealth) do
		if cells and #cells > 0 then
			CityInteractions._fillZoneGapsAtWealth(player, zoneId, mode, w, cells)
		end
	end

	-- =========================================================
	-- FIX 3: micro-sweep around changed tiles to catch *newly*
	-- orphaned cells created by multi-cell footprint changes.
	-- Skip during load-safe to avoid extra work; gaps will be
	-- handled by later bulk/scheduled passes.
	-- =========================================================
	if not _isLoadSafe(player) then
		_sweepLocalGapsAround(player, zoneId, mode, changes)
	end
end

-- ===== UXP (with delta-triggered pulse) =====
function CityInteractions.calculateGridUXP(player: Player, zoneData: ZoneData)
	local epochId = _currentPassEpoch() or _nextEpoch()
	if _isInLoad(player) then dprintUXP("(load fence) skipping UXP during load for " .. zoneData.zoneId) return end
	if UXP_IGNORE_ZONE_TYPES[zoneData.mode] then dprintUXP("Skipping UXP calculation for ignored type: " .. zoneData.mode) return end

	-- Fallback map, keeps visuals safe even if WEALTHED_ZONES wasn’t wired
	local _WEALTHED_ZONES = WEALTHED_ZONES or {
		Residential = true, Commercial = true, Industrial = true,
		ResDense    = true, CommDense   = true, IndusDense   = true,
	}

	dprintUXP((">> calculateGridUXP for %s (%s)"):format(zoneData.zoneId, zoneData.mode))

	local wt = getWealthThresholdsForMode(zoneData.mode)
	local M = wt.Medium
	local W = wt.Wealthy

	-- Ensure cache exists (rebuild once if empty)
	local allZones = zoneCacheByPlayer[player]
	if not allZones or #allZones == 0 then
		CityInteractions.rebuildCacheFromTracker(player)
		allZones = zoneCacheByPlayer[player]
		if not allZones or #allZones == 0 then dprintUXP("No zones cached for player – abort") return end
	end

	-- per-zone UXP memory
	_lastTileUXP[player] = _lastTileUXP[player] or {}
	_lastTileUXP[player][zoneData.zoneId] = _lastTileUXP[player][zoneData.zoneId] or {}

	local idx = _getSpatialIndex(player, true)

	-- ===== NEW: batching + guards =====
	-- Explicit “wealthed” guard (only such modes can change wealth tiers)
	local allowWealthUpgrades = (WEALTHED_ZONES and WEALTHED_ZONES[zoneData.mode]) or (_WEALTHED_ZONES[zoneData.mode] == true)

	-- Per-pass batch buffers (and hard de-dupe key set)
	local batchChanges: { { x: number, z: number, wealth: string } } = {}
	local batchKeyed: { [string]: boolean } = {}

	-- Accumulate XP for all UP upgrades in this commit
	local batchXP = 0
	local statConf = (Balance and Balance.StatConfig and Balance.StatConfig[zoneData.mode]) or nil

	-- === helper to enqueue (dedup + XP-on-up only) ===
	local function _enqueueChange(x: number, z: number, intendedState: string, oldState: string)
		local key = _tkey(x, z)
		if _markSeenThisEpoch(player, zoneData.zoneId, key, epochId) and not batchKeyed[key] then
			batchKeyed[key] = true
			table.insert(batchChanges, { x = x, z = z, wealth = intendedState })
			dprintUXP(("   !!! queue %s → %s @ (%d,%d)"):format(oldState, intendedState, x, z))

			-- XP only for upward moves
			local TIER = { Poor = 0, Medium = 1, Wealthy = 2 }
			local delta = (TIER[intendedState] or 0) - (TIER[oldState] or 0)
			if delta > 0 then
				local cfg = statConf and statConf[intendedState] or nil
				local exp = (cfg and cfg.exp) or 0
				if type(exp) == "number" and exp > 0 then batchXP = batchXP + exp end
			end
		else
			dprintUXP("   (dedupe) already queued this tile this pass")
		end
	end

	-- ===== MAIN PER-TILE PASS =====
	local lastYieldAt = os.clock()
	for _, currentTile in ipairs(zoneData.gridList) do
		if os.clock() - lastYieldAt > UXP_STEP_BUDGET_SEC then
			task.wait()
			lastYieldAt = os.clock()
		end
		dprintUXP(("• Checking tile %d, %d"):format(currentTile.x, currentTile.z))

		-- Track best tier per category
		local bestTierScore: { [string]: number } = {}
		local bestBuilding: { [string]: string } = {}
		for categoryName, _ in pairs(CATEGORY :: any) do bestTierScore[categoryName] = 0 end

		local candidates = (idx and idx:queryRadius(currentTile.x, currentTile.z, MAX_UXP_QUERY_RADIUS)) or allZones
		for _, otherZone in ipairs(candidates) do
			if otherZone.zoneId ~= zoneData.zoneId
				and (UXP_VALUES :: any)[otherZone.mode]
				and not UXP_IGNORE_ZONE_TYPES[otherZone.mode]
			then
				local bb = otherZone.boundingBox
				local w  = getInfluenceWidth(otherZone.mode)
				if currentTile.x >= bb.minX - w and currentTile.x <= bb.maxX + w
					and currentTile.z >= bb.minZ - w and currentTile.z <= bb.maxZ + w
				then
					for _, otherTile in ipairs(otherZone.gridList) do
						if isNearby(currentTile, otherTile, w) then
							for categoryName, set in pairs(CATEGORY :: any) do
								if set[otherZone.mode] then
									local tier = (BUILDING_TIERS :: any)[otherZone.mode] or 0
									local bestSoFar = bestTierScore[categoryName] or 0
									if tier > bestSoFar then
										bestTierScore[categoryName] = tier
										bestBuilding[categoryName]  = otherZone.mode
										dprintUXP(("      ↑ best %s now %s (tier %d)"):format(categoryName, otherZone.mode, tier))
									end
								end
							end
							break
						end
					end
				end
			end
		end

		-- Sum UXP
		local uxpTotal = 0
		for _, btype in pairs(bestBuilding) do
			local val = (UXP_VALUES :: any)[btype]
			if type(val) == "number" then uxpTotal += val end
		end
		dprintUXP("   >>> tile total UXP = " .. tostring(uxpTotal))

		-- Pulse on delta (independent of tier)
		do
			-- Always record latest UXP so future diffs are correct
			local key  = _tkey(currentTile.x, currentTile.z)
			local prev = _lastTileUXP[player][zoneData.zoneId][key]
			_lastTileUXP[player][zoneData.zoneId][key] = uxpTotal

			-- No visuals for non-wealthed modes (still recorded above)
			if not WEALTHED_ZONES[zoneData.mode] or prev == nil then
				-- either non-wealthed zone or first sample (no diff yet) → nothing to show
			else
				-- Per-grid progress toward next tier (UP) and deficit below floor (DOWN), with hysteresis
				local currentState: string = ZoneTracker.getGridWealth(player, zoneData.zoneId, currentTile.x, currentTile.z) or "Poor"

				-- Upward targets (respect Up hysteresis so the color reflects real “upgrade needed”)
				local wt2 = getWealthThresholdsForMode(zoneData.mode)
				local M_up = wt2.Medium + (HYSTERESIS.MediumUp  or 0)
				local W_up = wt2.Wealthy + (HYSTERESIS.WealthUp or 0)

				-- Downward floors (respect Down hysteresis so the color reflects “we’re losing this tier”)
				local M_dn = wt2.Medium - (HYSTERESIS.MediumDown  or 0)
				local W_dn = wt2.Wealthy - (HYSTERESIS.WealthDown or 0)

				-- UPGRADE progress (0..1 toward next tier threshold)
				local baseUp, nextUp
				if currentState == "Poor" then
					baseUp, nextUp = 0, M_up
				elseif currentState == "Medium" then
					baseUp, nextUp = wt2.Medium, W_up
				else -- Wealthy (top tier)
					baseUp, nextUp = W_up, nil
				end
				local progressUp = 1
				if nextUp then
					local denom = math.max(1, nextUp - baseUp)
					progressUp = math.clamp((uxpTotal - baseUp) / denom, 0, 1)
				end

				-- DOWNGRADE progress (0..1 how far below the floor toward losing current band)
				local floorDn, prevBase
				if currentState == "Wealthy" then
					floorDn, prevBase = W_dn, wt2.Medium
				elseif currentState == "Medium" then
					floorDn, prevBase = M_dn, 0
				else
					floorDn, prevBase = 0, 0
				end
				local progressDown = 0
				if uxpTotal < floorDn then
					local denom = math.max(1, floorDn - prevBase)
					progressDown = math.clamp((floorDn - uxpTotal) / denom, 0, 1)
				end

				local diff = uxpTotal - prev
				if diff > 0 then
					-- UPGRADE: dark orange → green, quantized
					local tintUp = CityInteractions._progressColorUp(progressUp)
					dprintFX(string.format(" + UXP ↑ at %s (%d,%d) : %d→%d [prog=%.2f]",
						zoneData.zoneId, currentTile.x, currentTile.z, prev, uxpTotal, progressUp))
					_spawnUxpAlarm(player, zoneData.zoneId, currentTile.x, currentTile.z, "AlarmUpgrade", tintUp)
					playUxpSound(player, "Upgrade")
				elseif diff < 0 then
					-- DOWNGRADE: dark orange → red, quantized by deficit below floor
					local tintDn = CityInteractions._progressColorDown(progressDown)
					dprintFX(string.format(" - UXP ↓ at %s (%d,%d) : %d→%d [def=%.2f]",
						zoneData.zoneId, currentTile.x, currentTile.z, prev, uxpTotal, progressDown))
					_spawnUxpAlarm(player, zoneData.zoneId, currentTile.x, currentTile.z, "AlarmDowngrade", tintDn)
					playUxpSound(player, "Downgrade")
				end
			end
		end

		-- Wealth intent + explicit thresholds + hysteresis (prevents spike chatter)
		local intendedState = "Poor"
		if uxpTotal >= (W + HYSTERESIS.WealthUp) then
			intendedState = "Wealthy"
		elseif uxpTotal >= (M + HYSTERESIS.MediumUp) then
			intendedState = "Medium"
		end

		local oldState: string = ZoneTracker.getGridWealth(player, zoneData.zoneId, currentTile.x, currentTile.z) or "Poor"
		if intendedState ~= oldState then
			local TIER: { [string]: number } = { Poor = 0, Medium = 1, Wealthy = 2 }
			local delta = (TIER[intendedState] or 0) - (TIER[oldState] or 0)

			local canChange = true
			if delta < 0 then
				if not _canDowngradeNow(player) then
					dprintUXP("   downgrade suppressed by grace window") canChange = false
				elseif oldState == "Wealthy" and uxpTotal >= (W - HYSTERESIS.WealthDown) then
					dprintUXP("   downgrade suppressed by wealth hysteresis") canChange = false
				elseif oldState == "Medium" and uxpTotal >= (M - HYSTERESIS.MediumDown) then
					dprintUXP("   downgrade suppressed by medium hysteresis") canChange = false
				end
			end

			if canChange then
				-- For UPGRADES: only require wealthed mode; commit stage will reconcile models and fill gaps.
				-- For DOWNGRADES: commit as before (grace/hysteresis already applied).
				if delta > 0 then
					if not allowWealthUpgrades then
						dprintUXP(("   [skipped] wealth %s → %s (non-wealthed mode: %s)")
							:format(oldState, intendedState, zoneData.mode))
					else
						_enqueueChange(currentTile.x, currentTile.z, intendedState, oldState)
					end
				else
					_enqueueChange(currentTile.x, currentTile.z, intendedState, oldState)
				end
			else
				dprintUXP("   (no change; suppressed)")
			end
		else
			dprintUXP("   (no change)")
		end
	end

	-- ===== SINGLE COMMIT (atomic apply) =====
	-- Apply tile intentions by aligning models to intended wealth and filling any gaps at the correct wealth.
	if #batchChanges > 0 then
		-- ==========================================================
		-- FIX 1: consistent bulk cutover (>= threshold, not >)
		-- ==========================================================
		if #batchChanges >= BULK_REBUILD_THRESHOLD then
			dprintUXP(("   [bulk] %d changes meet/exceed threshold (%d) – running bulkWealthRebuild")
				:format(#batchChanges, BULK_REBUILD_THRESHOLD))

			-- If zone is still populating, queue normal batch and exit; bulk will be run later.
			if _shouldDeferWealthChanges(player, zoneData.zoneId) then
				dprintUXP(("   [bulk] zone is populating; deferring %d change(s)"):format(#batchChanges))
				_queueWealthChanges(player, zoneData.zoneId, batchChanges)
			else
				-- Atomic: compute intents, remove all instances touching changed tiles, refill by wealth buckets.
				CityInteractions.bulkWealthRebuild(player, zoneData.zoneId)
				if batchXP > 0 then
					XPManager.addXP(player, batchXP, zoneData.zoneId)
				end
			end
			return
		end

		-- Small change set: keep existing precise per-tile apply pipeline
		if _shouldDeferWealthChanges(player, zoneData.zoneId) then
			dprintUXP(("   [defer] zone '%s' is populating; queueing %d change(s) for post-populate")
				:format(zoneData.zoneId, #batchChanges))
			_queueWealthChanges(player, zoneData.zoneId, batchChanges)
		else
			dprintUXP(("   [batch] committing %d grid change(s) for %s"):format(#batchChanges, zoneData.zoneId))
			local ok, err = pcall(function()
				CityInteractions._applyWealthBatch(player, zoneData.zoneId, zoneData.mode, batchChanges)
			end)
			if not ok then
				warn(("[GridUXP] _applyWealthBatch failed for %s (%d changes): %s")
					:format(zoneData.zoneId, #batchChanges, tostring(err)))
			else
				if batchXP > 0 then
					XPManager.addXP(player, batchXP, zoneData.zoneId)
					dprintUXP(("   >>> +%d XP (batched)"):format(batchXP))
				end
			end
		end
	end

	dprintUXP("<< finished " .. zoneData.zoneId)
end


-- ===== Targeted UXP recompute helpers =====
local function recalcUXPForImpactedZonesAround(player: Player, seed: ZoneData)
	local cache = zoneCacheByPlayer[player]; if not cache then return end
	local influence = getInfluenceWidth(seed.mode)
	local bb = seed.boundingBox
	local infMinX, infMaxX = bb.minX - influence, bb.maxX + influence
	local infMinZ, infMaxZ = bb.minZ - influence, bb.maxZ + influence

	local impacted = 0
	_beginPass()  -- NEW
	for _, z in ipairs(cache) do
		if not UXP_IGNORE_ZONE_TYPES[z.mode] then
			local bb = z.boundingBox
			local sep = (bb.maxX < infMinX) or (bb.minX > infMaxX) or (bb.maxZ < infMinZ) or (bb.minZ > infMaxZ)
			if not sep then CityInteractions.calculateGridUXP(player, z) impacted += 1 end
		end
	end
	_endPass()
end

function CityInteractions.recalculateUXPAfterRemoval(player: Player, removed: ZoneData?)
	if not removed or UXP_IGNORE_ZONE_TYPES[removed.mode] then
		dprintUXP("(removed zone type ignored for UXP; no recalc needed)")
		return
	end

	local removedBB = removed.boundingBox or computeBoundingBox(removed.gridList or {})
	local cache = zoneCacheByPlayer[player]; if not cache then return end

	local influence = getInfluenceWidth(removed.mode)
	local infMinX, infMaxX = removedBB.minX - influence, removedBB.maxX + influence
	local infMinZ, infMaxZ = removedBB.minZ - influence, removedBB.maxZ + influence

	-- Optional tidy: drop any epoch marks for this removed zone so future passes don't carry stale keys
	if _seenEpoch[player] then
		_seenEpoch[player][removed.zoneId] = nil
	end

	local impacted = 0
	_beginPass()  -- share epoch across this whole cascade
	for _, z in ipairs(cache) do
		if not UXP_IGNORE_ZONE_TYPES[z.mode] then
			local bb = z.boundingBox
			local sep = (bb.maxX < infMinX) or (bb.minX > infMaxX) or (bb.maxZ < infMinZ) or (bb.minZ > infMaxZ)
			if not sep then
				CityInteractions.calculateGridUXP(player, z)
				impacted += 1
			end
		end
	end
	_endPass()

	dprintUXP(("Recalculated UXP for %d impacted zone(s) after removal of %s"):format(impacted, tostring(removed.zoneId)))
end

-- ===== Event entry points =====
function CityInteractions.onZoneCreated(player: Player, zoneId: string, mode: string, gridList: { GridTile })
	if IGNORE_ZONE_TYPES[mode] then log("[CityInteractions] Skipping cache and logic for excluded type:", mode) return end
	log("[CityInteractions] onZoneCreated:", zoneId, mode, player.Name)
	RefillQueue.cancel(player, zoneId)

	if VALID_ZONE_TYPES[mode] then
		_markZonePending(player, zoneId)
	end

	local newZoneData: ZoneData = {
		zoneId      = zoneId,
		mode        = mode,
		gridList    = gridList,
		player      = player,
		boundingBox = computeBoundingBox(gridList),
	}

	if not zoneCacheByPlayer[player] then zoneCacheByPlayer[player] = {} end
	table.insert(zoneCacheByPlayer[player], newZoneData)
	local idx = _getSpatialIndex(player, true)
	if idx then idx:add(newZoneData) end
	_recalcPositiveBonusesAround(player, newZoneData)

	if VALID_ZONE_TYPES[mode] then CityInteractions.calculateZoneSynergy(player, newZoneData) end

	_beginPass()  -- NEW: share epoch across this cascade
	if not UXP_IGNORE_ZONE_TYPES[mode] then
		CityInteractions.calculateGridUXP(player, newZoneData)
		recalcUXPForImpactedZonesAround(player, newZoneData)
	end
	_endPass()
end

-- ===== Event entry points =====
function CityInteractions.onZoneRecreated(player: Player, zoneId: string, mode: string, gridList: { GridTile })
	-- defensive skip for excluded types
	if IGNORE_ZONE_TYPES[mode] then
		if DEBUG_SYNERGY then print("[CityInteractions] ZoneReCreated ignored for excluded type:", mode) end
		return
	end
	RefillQueue.cancel(player, zoneId)

	if VALID_ZONE_TYPES[mode] then
		_markZonePending(player, zoneId)
	end

	-- Update cache entry for this zone (replace its grid & bbox)
	local cache = zoneCacheByPlayer[player]
	if not cache then zoneCacheByPlayer[player] = {} cache = zoneCacheByPlayer[player] end
	_pollTickCursor[player] = _pollTickCursor[player] or {}
	_pollTickCursor[player][zoneId] = 1
	local bb = computeBoundingBox(gridList)
	local found = false
	local zdata: ZoneData? = nil
	for i = 1, #cache do
		if cache[i].zoneId == zoneId then
			cache[i] = {
				zoneId      = zoneId,
				mode        = mode,
				gridList    = gridList,
				player      = player,
				boundingBox = bb,
			}
			zdata = cache[i]
			found = true
			break
		end
	end
	if not found then
		local entry: ZoneData = {
			zoneId      = zoneId,
			mode        = mode,
			gridList    = gridList,
			player      = player,
			boundingBox = bb,
		}
		table.insert(cache, entry)
		zdata = entry
	end

	-- Clear any stale per-zone UXP visuals (they’ll be respawned if needed)
	CityInteractions._clearUxpAlarmsForZone(player, zoneId)

	-- IMPORTANT ORDER: UXP first (zone + impacted), then pollution/synergy alarms
	_beginPass()
	if zdata then
		do
			local idx = _getSpatialIndex(player, true)
			if idx then idx:update(zdata) end
		end
		_recalcPositiveBonusesAround(player, zdata)
		if not UXP_IGNORE_ZONE_TYPES[mode] then
			CityInteractions.calculateGridUXP(player, zdata)
			recalcUXPForImpactedZonesAround(player, zdata)
		end

		-- Now run pollution/synergy alarms for the updated geometry
		if VALID_ZONE_TYPES[mode] then
			CityInteractions.calculateZoneSynergy(player, zdata)
		end
	end
	_endPass()
end


function CityInteractions.onZoneRemoved(player: Player, zoneId: string, mode: string, gridList: { GridTile }?)
	if IGNORE_ZONE_TYPES[mode] then
		log("[CityInteractions] Skipping zone removal for excluded type:", mode)
		return
	end
	log(string.format("[CityInteractions] onZoneRemoved: '%s' (%s)", zoneId, mode))
	RefillQueue.cancel(player, zoneId)
	_clearZonePending(player, zoneId)

	-- Clear gentle pulse parts for this zone
	CityInteractions._clearUxpAlarmsForZone(player, zoneId)

	local removedZoneData: ZoneData = {
		zoneId      = zoneId,
		mode        = mode,
		gridList    = gridList or {},
		player      = player,
		boundingBox = gridList and computeBoundingBox(gridList) or { minX = 0, maxX = 0, minZ = 0, maxZ = 0 },
	}

	-- Evict from cache
	local cache = zoneCacheByPlayer[player]
	if cache then
		for i = #cache, 1, -1 do
			if cache[i].zoneId == zoneId then
				table.remove(cache, i)
				break
			end
		end
	end

	-- Optional memory tidy: drop any epoch marks & last-UXP memory for this zone
	if _seenEpoch[player] then
		_seenEpoch[player][zoneId] = nil
	end
	if _lastTileUXP[player] then
		_lastTileUXP[player][zoneId] = nil
	end
	_stopPollutionClock(player, zoneId)
	-- Recalculate UXP around the removed zone
	CityInteractions.recalculateUXPAfterRemoval(player, removedZoneData)
	if _pendingWealth[player] then
		_pendingWealth[player][zoneId] = nil
		if not next(_pendingWealth[player]) then _pendingWealth[player] = nil end
	end
	if _applyLock[player] then
		_applyLock[player][zoneId] = nil
		if not next(_applyLock[player]) then _applyLock[player] = nil end
	end
	if _pollTickCursor[player] then
		_pollTickCursor[player][zoneId] = nil
		if not next(_pollTickCursor[player]) then _pollTickCursor[player] = nil end
	end
	do
		local idx = _getSpatialIndex(player, false)
		if idx then idx:remove(zoneId) end
	end
	_clearZonePositiveBonus(player, zoneId)
	if _incomePollutionTiles[player] then
		_incomePollutionTiles[player][zoneId] = nil
		if not next(_incomePollutionTiles[player]) then
			_incomePollutionTiles[player] = nil
		end
	end
	_recalcPositiveBonusesAround(player, nil, removedZoneData.boundingBox)
end

-- ===== BindableEvents wiring =====
do


	local zonePopulatedEvent = BindableEvents:WaitForChild("ZonePopulated")
	zonePopulatedEvent.Event:Connect(function(player: Player, zoneId: string, _placed: any)
		-- 1) apply deferred wealth (from UXP computations)
		CityInteractions._flushPendingWealthForZone(player, zoneId)
		_clearZonePending(player, zoneId)
		_drainBulkRebuild(player, zoneId)

		-- 2) safety: if the zone exists in cache, run pollution/synergy pass now that models are surely present
		local z = _getZoneDataFromCache(player, zoneId)
		if z and VALID_ZONE_TYPES[z.mode] then
			if DEBUG_SYNERGY then print("[CityInteractions] ZonePopulated → recompute UXP+pollution for", zoneId) end
			_beginPass()
			-- UXP zone-only (impacted zones will be hit by the builder's own calls if needed)
			if not UXP_IGNORE_ZONE_TYPES[z.mode] then
				CityInteractions.calculateGridUXP(player, z)
			end
			-- pollution/synergy alarms
			CityInteractions.calculateZoneSynergy(player, z)
			_endPass()
		end
	end)

	local zoneCreatedEvent = BindableEvents:WaitForChild("ZoneCreated", 5)
	if zoneCreatedEvent then
		(zoneCreatedEvent :: any).Event:Connect(function(player: Player, zoneId: string, mode: string, gridList: { GridTile })
			CityInteractions.onZoneCreated(player, zoneId, mode, gridList)
		end)
	end


	local zoneRemovedEvent = BindableEvents:WaitForChild("ZoneRemoved", 5)
	if zoneRemovedEvent then
		(zoneRemovedEvent :: any).Event:Connect(function(player: Player, zoneId: string, mode: string, gridList: { GridTile }?)
			CityInteractions.onZoneRemoved(player, zoneId, mode, gridList)
		end)
	end
end

-- ===== Quiet synergy during load phase =====
do
	local _origCalcSynergy = CityInteractions.calculateZoneSynergy
	function CityInteractions.calculateZoneSynergy(player: Player, newZoneData: ZoneData)
		if _isInLoad(player) then return end
		return _origCalcSynergy(player, newZoneData)
	end
end

-- ===== City load lifecycle =====
function CityInteractions.onCityPreload(player: Player)
	_loadPhase[player]  = true
	_graceUntil[player] = os.clock() + DOWNGRADE_GRACE_SEC
	_loadSafeUntil[player] = os.clock() + LOAD_SAFE_GRACE_SEC
end

function CityInteractions.onCityPostload(player: Player)
	_loadPhase[player] = false
	-- Keep a short load-safe window after postload for FX/CPU throttle
	local target = os.clock() + LOAD_SAFE_GRACE_SEC
	local existing = _loadSafeUntil[player]
	if not existing or existing < target then
		_loadSafeUntil[player] = target
	end
	CityInteractions.rebuildCacheFromTracker(player)
	local cache = zoneCacheByPlayer[player]
	if cache then
		-- NEW: seed pollution clocks for any zones that are already “bad” after load
		_kickPollutionClocksForPlayer(player)

		_beginPass()
		for _, z in ipairs(cache) do
			if not UXP_IGNORE_ZONE_TYPES[z.mode] then
				CityInteractions.calculateGridUXP(player, z)
			end
		end
		_endPass()
	end
end

-- ===== Cleanup =====
Players.PlayerRemoving:Connect(function(plr: Player)
	_loadPhase[plr]        = nil :: any
	_graceUntil[plr]       = nil :: any
	zoneCacheByPlayer[plr] = nil :: any
	_lastTileUXP[plr]      = nil :: any
	_seenEpoch[plr]        = nil :: any
	_pollutionClock[plr]   = nil
	_refillLock[plr]       = nil
	_refillPending[plr]    = nil
	_refillEpoch[plr]      = nil
	_pendingWealth[plr]    = nil
	_pendingPopulate[plr]  = nil
	_applyLock[plr]        = nil
	_incomePollutionTiles[plr] = nil
	_pollTickCursor[plr]   = nil
	_positiveBonusTiles[plr] = nil
	zoneSpatialIndexByPlayer[plr] = nil
	_loadSafeUntil[plr]    = nil
end)

-- === INTENT-ONLY PASS: compute intended wealth for every tile (no side effects) ===
function CityInteractions.computeIntendedWealthMap(player: Player, zoneId: string): { [string]: string }
	local z = (function()
		local cache = zoneCacheByPlayer[player]
		if not cache then CityInteractions.rebuildCacheFromTracker(player) cache = zoneCacheByPlayer[player] end
		if not cache then return nil end
		for _, item in ipairs(cache) do if item.zoneId == zoneId then return item end end
		return nil
	end)()
	if not z then return {} end

	local wt = getWealthThresholdsForMode(z.mode)
	local M, W = wt.Medium, wt.Wealthy

	-- prepare neighbor cache once
	local allZones = zoneCacheByPlayer[player]
	if not allZones or #allZones == 0 then
		CityInteractions.rebuildCacheFromTracker(player)
		allZones = zoneCacheByPlayer[player]
	end

	local intents = {} -- ["x|z"] = "Poor"|"Medium"|"Wealthy"

	for _, t in ipairs(z.gridList) do
		-- compute UXP exactly like calculateGridUXP does (best-per-category sum)
		local bestTierScore: { [string]: number } = {}
		local bestBuilding:  { [string]: string } = {}
		for categoryName, _ in pairs(CATEGORY :: any) do bestTierScore[categoryName] = 0 end

		for _, other in ipairs(allZones) do
			if other.zoneId ~= z.zoneId and (UXP_VALUES :: any)[other.mode] and not UXP_IGNORE_ZONE_TYPES[other.mode] then
				local w = getInfluenceWidth(other.mode)
				local bb = other.boundingBox
				if t.x >= bb.minX - w and t.x <= bb.maxX + w and t.z >= bb.minZ - w and t.z <= bb.maxZ + w then
					for _, ot in ipairs(other.gridList) do
						if isNearby(t, ot, w) then
							for categoryName, set in pairs(CATEGORY :: any) do
								if set[other.mode] then
									local tier = (BUILDING_TIERS :: any)[other.mode] or 0
									if tier > (bestTierScore[categoryName] or 0) then
										bestTierScore[categoryName] = tier
										bestBuilding[categoryName]  = other.mode
									end
								end
							end
							break
						end
					end
				end
			end
		end

		local uxpTotal = 0
		for _, btype in pairs(bestBuilding) do
			local val = (UXP_VALUES :: any)[btype]
			if type(val) == "number" then uxpTotal += val end
		end

		local intended = "Poor"
		if uxpTotal >= (W + (HYSTERESIS.WealthUp or 0)) then
			intended = "Wealthy"
		elseif uxpTotal >= (M + (HYSTERESIS.MediumUp or 0)) then
			intended = "Medium"
		end
		intents[tostring(t.x).."|"..tostring(t.z)] = intended
	end

	return intents
end

-- === ATOMIC, ZONE-LOCAL REBUILD ===
-- Computes intents, finds changes, removes touching instances, refills by wealth, and syncs tracker.
function CityInteractions.bulkWealthRebuild(player: Player, zoneId: string)
	-- Resolve mode + grid
	local z = _getZoneDataFromCache(player, zoneId)
	if not z then
		CityInteractions.rebuildCacheFromTracker(player)
		z = _getZoneDataFromCache(player, zoneId)
	end
	if not z then warn("[bulkWealthRebuild] no zone data for "..zoneId) return end

	-- Defer if the zone is currently populating
	if _shouldDeferWealthChanges(player, zoneId) then
		warn("[bulkWealthRebuild] zone is populating; queuing rebuild for later")
		_queueBulkRebuild(player, zoneId)
		return
	end

	-- 1) intents
	local intents = CityInteractions.computeIntendedWealthMap(player, zoneId)

	-- 2) diff vs tracker to get CHANGED tiles only
	local changedSet = {}   -- ["x|z"]=true
	local buckets    = { Poor = {}, Medium = {}, Wealthy = {} }
	for _, t in ipairs(z.gridList) do
		local key = _tkey(t.x, t.z)
		local intended = intents[key]
		if intended then
			local curr = ZoneTracker.getGridWealth(player, zoneId, t.x, t.z) or "Poor"
			if curr ~= intended then
				changedSet[key] = true
				table.insert(buckets[intended], { x = t.x, z = t.z })
			end
		end
	end

	_augmentBucketsWithModelMismatches(player, zoneId, z, intents, changedSet, buckets)

	if not next(changedSet) then
		return -- nothing to do
	end

	-- 3) collect and remove all instances touching any changed tile
	local touching = BuildingGeneratorModule.collectInstancesTouchingTiles(player, zoneId, changedSet)
	BuildingGeneratorModule.bulkRemoveInstances(player, zoneId, touching)

	-- 4) tracker mirror (so later systems see the intended truth immediately)
	for _, wealth in ipairs({ "Poor", "Medium", "Wealthy" }) do
		for _, cell in ipairs(buckets[wealth]) do
			ZoneTracker.setGridWealth(player, zoneId, cell.x, cell.z, wealth)
		end
	end

	-- 5) refill per wealth bucket (strict wealth override)
	BuildingGeneratorModule.seededRefillByWealth(player, zoneId, z.mode, buckets)
end

return CityInteractions
