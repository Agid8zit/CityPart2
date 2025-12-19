-- CivicRequestsAdvisor.lua

local DEBUG                          = false   -- print why/where things fail
local LOG_PREFIX                     = "[CivicReq]"
local AREA_OFFSET_Y                  = 7      -- studs above ground
local MIN_CLUSTER_SIZE_TILES         = 3      -- ignore tiny noise (set 1 to see everything)
local MAX_CLUSTERS_PER_CATEGORY      = 10     -- cap per scan per category
local MAX_CLUSTERS_PER_CATEGORY_TICK = 4      -- cap per frame per category
local RESCAN_THROTTLE_SEC            = 0.25   -- scan throttle
local REQUEST_TTL_SEC                = 8.0    -- how long icons live unless refreshed
local REQUEST_RESPAWN_COOLDOWN_SEC   = 2.0    -- per centroid cooldown
local USE_SHARED_BOBBING             = true
local BOB_SPEED                      = 2
local BOB_AMPLITUDE                  = 0.5

-- Diagnostics: CANARY spawns one Police icon over first Residential if a scan produces 0 icons.
local DEV_CANARY_ENABLE              = true
local DEV_CANARY_CATEGORY            = "Police"    -- uses RequestPolice template

-- If your zones aren’t marked “populated” yet and you want to see icons anyway:
local FORCE_POPULATED_FOR_TEST       = false

-- Wealth filter (we consider all by default)
local ALLOWED_WEALTH = { Poor = true, Medium = true, Wealthy = true }

-----------------------------
-- ADVISOR CLOCK (weakest-area pings)
-----------------------------
local CLOCK_PERIOD_SEC               = 6.0         -- how often to scout the weakest area
local CLOCK_MAX_CATEGORIES           = 2           -- max categories to pulse per tick
local _clockTasks                    = {}          -- [Player] = true while running

-- Per-zone cool-off so the clock doesn't keep picking the same place
local LAST_PING_COOLDOWN_SEC         = 18.0
local _lastPingAt                    = {}          -- [userId][zoneId] = os.clock()

-- Population cache, fed by ZonePopulated
local _populated                     = {}          -- [userId][zoneId] = true
local _focus                         = {}          -- [userId] = { zoneId, category, cx, cz, nameKey }

-----------------------------
-- SERVICES / MODULES
-----------------------------
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService          = game:GetService("RunService")
local RunServiceScheduler = require(ReplicatedStorage.Scripts.RunServiceScheduler)

local ZoneTracker = require(ServerScriptService.Build.Zones.ZoneManager.ZoneTracker)

local GridScripts = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Grid")
local GridUtil    = require(GridScripts:WaitForChild("GridUtil"))
local GridConfig  = require(GridScripts:WaitForChild("GridConfig"))
local Balance     = require(ReplicatedStorage:WaitForChild("Balancing"):WaitForChild("BalanceEconomy"))

-- Progression module (robust loader). If we cannot resolve it, we will fall back to
-- Balance.ProgressionConfig + PlayerDataService cityLevel instead of silently
-- treating every category as unlocked.
local Progression, triedProgressionLoad = nil, false

local function tryRequireModule(inst: Instance?)
	if not inst then return nil end
	local ok, mod = pcall(require, inst)
	if ok then
		return mod
	end
	return nil
end

local function ensureProgression()
	if Progression or triedProgressionLoad then
		return Progression
	end
	triedProgressionLoad = true

	local candidates = {}

	local direct = ServerScriptService:FindFirstChild("Progression")
	if direct then table.insert(candidates, direct) end

	local build = ServerScriptService:FindFirstChild("Build")
	if build then
		local districts = build:FindFirstChild("Districts")
		local stats     = districts and districts:FindFirstChild("Stats")
		local prog      = stats and stats:FindFirstChild("Progression")
		if prog then table.insert(candidates, prog) end
	end

	local rsProg = ReplicatedStorage:FindFirstChild("Progression")
	if rsProg then table.insert(candidates, rsProg) end

	for _, inst in ipairs(candidates) do
		local mod = tryRequireModule(inst)
		if mod then
			Progression = mod
			return Progression
		end
	end

	return nil
end

-- PlayerDataService (optional) for fallback level checks
local PlayerDataServiceModule, triedPDSLoad = nil, false
local function ensurePlayerDataService()
	if PlayerDataServiceModule or triedPDSLoad then
		return PlayerDataServiceModule
	end
	triedPDSLoad = true

	local candidates = {
		ServerScriptService:FindFirstChild("PlayerDataService"),
		ReplicatedStorage:FindFirstChild("PlayerDataService"),
	}
	for _, inst in ipairs(candidates) do
		local mod = tryRequireModule(inst)
		if mod and type(mod.GetSaveFileData) == "function" then
			PlayerDataServiceModule = mod
			return PlayerDataServiceModule
		end
	end
	return nil
end

local function getCityLevel(player: Player): number
	local pds = ensurePlayerDataService()
	if pds and type(pds.GetSaveFileData) == "function" then
		local ok, data = pcall(pds.GetSaveFileData, player)
		if ok and data and data.cityLevel ~= nil then
			local lvl = tonumber(data.cityLevel)
			if lvl then
				return math.max(0, math.floor(lvl))
			end
		end
	end
	return 0
end

local function normalizeFeatureName(featureName: string?): string?
	if type(featureName) == "string" and string.sub(featureName, 1, 5) == "Flag:" then
		return "Flags"
	end
	return featureName
end

-- Precompute a fallback min-level map from Balance.ProgressionConfig.unlocksByLevel.
local FALLBACK_MIN_LEVEL: { [string]: number } = {}
do
	local cfg = Balance and Balance.ProgressionConfig
	local byLevel = cfg and cfg.unlocksByLevel
	if type(byLevel) == "table" then
		for lvl, list in pairs(byLevel) do
			if type(list) == "table" then
				for _, feat in ipairs(list) do
					local name = normalizeFeatureName(feat)
					if name then
						local cur = FALLBACK_MIN_LEVEL[name]
						local lvln = tonumber(lvl) or 0
						if cur == nil or lvln < cur then
							FALLBACK_MIN_LEVEL[name] = lvln
						end
					end
				end
			end
		end
	end
end

local function fallbackPlayerHasUnlock(player: Player, featureName: string): boolean
	local lvl = getCityLevel(player)
	local required = FALLBACK_MIN_LEVEL[normalizeFeatureName(featureName) or ""] or 0
	return lvl >= required
end

local function progressionPlayerHasUnlock(player: Player, featureName: string): boolean
	local P = ensureProgression()
	if P and type((P :: any).playerHasUnlock) == "function" then
		local ok, unlocked = pcall((P :: any).playerHasUnlock, player, featureName)
		if ok then
			return unlocked == true
		end
	end
	return fallbackPlayerHasUnlock(player, featureName)
end

local function progressionRequiredLevel(featureName: string): number
	local P = ensureProgression()
	if P and type((P :: any).getRequiredLevel) == "function" then
		local ok, lvl = pcall((P :: any).getRequiredLevel, featureName)
		if ok and type(lvl) == "number" then
			return lvl
		end
	end
	return FALLBACK_MIN_LEVEL[normalizeFeatureName(featureName) or ""] or 0
end

-- NEW: try to load DevProducts so we can identify devproduct features by name
local DevProductsModule do
	local ok, mod = pcall(function()
		-- Adjust this require path if your DevProducts module lives elsewhere
		return require(ServerScriptService:FindFirstChild("DevProducts") or error("DevProducts not found"))
	end)
	DevProductsModule = ok and mod or nil
end

-- Cache the explicit level-0 unlock list from Balance so we can spot devproducts even if the module fails.
local LEVEL0_UNLOCKS: { [string]: boolean } = {}
do
	local cfg = Balance and Balance.ProgressionConfig
	local lvl0 = cfg and cfg.unlocksByLevel and cfg.unlocksByLevel[0]
	if type(lvl0) == "table" then
		for _, feature in ipairs(lvl0) do
			if type(feature) == "string" then
				LEVEL0_UNLOCKS[feature] = true
			end
		end
	end
end

-- Some level-0 items are core gameplay (not devproducts) and must never be flagged.
local LEVEL0_WHITELIST = {
	Residential   = true,
	Commercial    = true,
	Industrial    = true,
	DirtRoad      = true,
	WaterTower    = true,
	WaterPipe     = true,
	WindTurbine   = true,
	PowerLines    = true,
	Flags         = true,
}

local Events         = ReplicatedStorage:WaitForChild("Events")
local BindableEvents = Events:WaitForChild("BindableEvents")
local RemoteEvents   = Events:WaitForChild("RemoteEvents")

local function ensureBindable(name: string)
	local b = BindableEvents:FindFirstChild(name)
	if not b then b = Instance.new("BindableEvent"); b.Name = name; b.Parent = BindableEvents end
	return b
end
local function ensureRemote(name: string)
	local r = RemoteEvents:FindFirstChild(name)
	if not r then r = Instance.new("RemoteEvent"); r.Name = name; r.Parent = RemoteEvents end
	return r
end

local EVT_ScanRequested        = ensureBindable("CivicRequestsScanRequested")
local EVT_RequestAlarmsChanged = ensureBindable("CivicRequestsAlarmsChanged")
local RE_AdvisorSay            = ensureRemote("CityAdvisorSay")
local RE_NotifyPlayer          = RemoteEvents:FindFirstChild("NotifyPlayer")

-- Assets root
local AlarmsFolder do
	local f = ReplicatedStorage:FindFirstChild("FuncTestGroundRS")
		and ReplicatedStorage.FuncTestGroundRS:FindFirstChild("Alarms")
	if not f and DEBUG then
		warn(LOG_PREFIX, "Missing ReplicatedStorage/FuncTestGroundRS/Alarms (icons can’t render).")
	end
	AlarmsFolder = f
end

-- Template names you said exist:
local TEMPLATE_BY_CATEGORY = {
	Fire                = "RequestFire",
	Education           = "RequestEducation",
	Health              = "RequestHealth",
	Landmark            = "RequestLandmark",
	Police              = "RequestPolice",
	SportsAndRecreation = "RequestSport",
}

-- Which categories we evaluate (targets get icons for these)
local CATEGORIES = { "Police", "Fire", "Health", "Education", "Landmark", "SportsAndRecreation" }

-- Which zones *receive* services (targets)
local TARGET_BUILDING_MODES = {
	Residential = true, Commercial = true, Industrial = true,
	ResDense    = true, CommDense  = true, IndusDense  = true,
}

-- Modes to ignore entirely as providers/targets here (utilities/networks)
local IGNORE_MODES = {
	WaterPipe=true, WaterTower=true, WaterPlant=true, PurificationWaterPlant=true, MolecularWaterPlant=true,
	PowerLines=true, SolarPanels=true, WindTurbine=true, CoalPowerPlant=true, GasPowerPlant=true,
	GeothermalPowerPlant=true, NuclearPowerPlant=true,
	DirtRoad=true, Pavement=true, Highway=true,
}

-- Balance tables
local CATEGORY   = (Balance and Balance.UxpConfig  and Balance.UxpConfig.Category) or {}
local UXP_RADIUS = (Balance and Balance.UxpConfig  and Balance.UxpConfig.Radius)   or {}
local UXP_TIER   = (Balance and Balance.UxpConfig  and Balance.UxpConfig.Tier)     or {}

-----------------------------
-- UTILS
-----------------------------
local function now() return os.clock() end
local function dprint(...) if DEBUG then print(LOG_PREFIX, ...) end end

local function getPlayerPlot(player: Player): Instance?
	local pf = workspace:FindFirstChild("PlayerPlots")
	return pf and pf:FindFirstChild("Plot_" .. player.UserId)
end

local _boundsCache: { [Instance]: { bounds:any, terrains:{BasePart} } } = {}
local function getGlobalBoundsForPlot(plot: Instance)
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
	if #terrains == 0 and testTerrain then table.insert(terrains, testTerrain) end

	local gb = GridConfig.calculateGlobalBounds(terrains)
	_boundsCache[plot] = { bounds = gb, terrains = terrains }
	return gb, terrains
end

local function gridToWorld(plot: Instance, gx:number, gz:number): Vector3
	local ref = plot and plot:FindFirstChild("TestTerrain")
	if not (plot and ref) then return Vector3.new(0, GridConfig.Y_OFFSET, 0) end
	local gb, terrains = getGlobalBoundsForPlot(plot)
	local wx, _, wz = GridUtil.globalGridToWorldPosition(gx, gz, gb, terrains)
	local wy = ref.Position.Y + (ref.Size.Y/2) + GridConfig.Y_OFFSET
	return Vector3.new(wx, wy, wz)
end

local function keyXZ(x:number,z:number) return tostring(x).."|"..tostring(z) end
local function unkey(k:string) local s=k:find("|"); return tonumber(k:sub(1,s-1)), tonumber(k:sub(s+1)) end

local function aabbFromGridList(gl: { {x:number,z:number} }?)
	if not gl or #gl == 0 then
		return {minX=math.huge, maxX=-math.huge, minZ=math.huge, maxZ=-math.huge}
	end
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	for _, t in ipairs(gl) do
		if t.x < minX then minX = t.x end
		if t.x > maxX then maxX = t.x end
		if t.z < minZ then minZ = t.z end
		if t.z > maxZ then maxZ = t.z end
	end
	return {minX=minX, maxX=maxX, minZ=minZ, maxZ=maxZ}
end

-- 4-neighbour cluster
local function clusterTiles(tileSet: { [string]: boolean })
	local clusters, visited = {}, {}
	local function neigh(x,z) return { {x=x+1,z=z},{x=x-1,z=z},{x=x,z=z+1},{x=x,z=z-1} } end
	for k,_ in pairs(tileSet) do
		if not visited[k] then
			local sx, sz = unkey(k)
			local q, qi = { {x=sx,z=sz} }, 1
			visited[k] = true
			local c = { {x=sx,z=sz} }
			while q[qi] do
				local cx, cz = q[qi].x, q[qi].z
				for _,n in ipairs(neigh(cx,cz)) do
					local nk = keyXZ(n.x,n.z)
					if tileSet[nk] and not visited[nk] then
						visited[nk] = true
						c[#c+1] = {x=n.x,z=n.z}
						q[#q+1] = {x=n.x,z=n.z}
					end
				end
				qi += 1
			end
			clusters[#clusters+1] = c
		end
	end
	return clusters
end

local function centroid(cluster: { {x:number,z:number} })
	local sx, sz = 0, 0
	for _,c in ipairs(cluster) do sx += c.x; sz += c.z end
	local n = math.max(1, #cluster)
	return { x = math.floor(sx/n + 0.5), z = math.floor(sz/n + 0.5) }
end

-- population check (event-backed with safe fallback)
local function isZonePopulated(player: Player, zoneId: string): boolean
	if FORCE_POPULATED_FOR_TEST then return true end
	local uid = player.UserId
	if _populated[uid] and _populated[uid][zoneId] then return true end

	-- Fallback to world state if the event was missed
	local plot = getPlayerPlot(player); if not plot then return false end
	local zf = plot:FindFirstChild("PlayerZones")
	local zm = zf and zf:FindFirstChild(zoneId)
	if not zm then return false end
	local a = zm:GetAttribute("populated")
	if a ~= nil then
		if a == true then
			_populated[uid] = _populated[uid] or {}
			_populated[uid][zoneId] = true
		end
		return a == true
	end
	local bv = zm:FindFirstChild("populated")
	if bv and bv:IsA("BoolValue") then
		if bv.Value then
			_populated[uid] = _populated[uid] or {}
			_populated[uid][zoneId] = true
		end
		return bv.Value
	end
	local s3 = zm:FindFirstChild("Stage3")
	if s3 then
		local a2 = (s3 :: any).GetAttribute and (s3 :: any):GetAttribute("populated")
		if a2 ~= nil then
			if a2 == true then
				_populated[uid] = _populated[uid] or {}
				_populated[uid][zoneId] = true
			end
			return a2 == true
		end
		local bv2 = s3:FindFirstChild("populated")
		if bv2 and bv2:IsA("BoolValue") then
			if bv2.Value then
				_populated[uid] = _populated[uid] or {}
				_populated[uid][zoneId] = true
			end
			return bv2.Value
		end
	end
	return false
end

local function getInfluenceWidth(mode: string): number
	local w = (UXP_RADIUS :: any)[mode]
	if type(w) ~= "number" or w < 1 then return 1 end
	return math.max(1, math.floor(w))
end

----------------------------------------------------------------
-- NEW HELPERS FOR DEVPRODUCT GATING
----------------------------------------------------------------
local function isDevProductFeature(featureName: string): boolean
	if DevProductsModule ~= nil and DevProductsModule.Has ~= nil then
		local ok, result = pcall(DevProductsModule.Has, featureName)
		if ok and result == true then
			return true
		end
	end

	-- Fallback: treat explicit level-0 Balance unlocks (excluding whitelisted basics) as devproducts.
	if LEVEL0_UNLOCKS[featureName] and not LEVEL0_WHITELIST[featureName] then
		return true
	end

	return false
end

local function playerHasBuiltFeature(player: Player, featureName: string): boolean
	local zones = ZoneTracker.getAllZones(player)
	if not zones then return false end
	for zid, z in pairs(zones) do
		if z.mode == featureName and isZonePopulated(player, zid) then
			return true
		end
	end
	return false
end

local function playerHasDevProductPlacement(player: Player, categoryName: string): boolean
	local bag = CATEGORY[categoryName]; if type(bag) ~= "table" then return false end
	for featureName in pairs(bag) do
		if isDevProductFeature(featureName) and playerHasBuiltFeature(player, featureName) then
			return true
		end
	end
	return false
end

-- Returns the highest tier **non-devproduct** feature in this category that the player has unlocked.
-- Tier priority uses Balance.UxpConfig.Tier if present; otherwise falls back to required level.
local function bestUnlockedProgressionFeature(player: Player, categoryName: string): string?
	local bag = CATEGORY[categoryName]; if type(bag) ~= "table" then return nil end
	local bestFeat, bestScore = nil, -math.huge
	for featureName, _ in pairs(bag) do
		if not isDevProductFeature(featureName) then
			local unlocked = progressionPlayerHasUnlock(player, featureName)
			if unlocked then
				local score = ((UXP_TIER :: any)[featureName] or progressionRequiredLevel(featureName))
				if score > bestScore then
					bestScore = score
					bestFeat  = featureName
				end
			end
		end
	end
	return bestFeat
end

-- Absolute top-tier non-dev progression feature for this category (independent of player unlocks).
local _topProgressionCache: { [string]: string | false } = {}
local function topProgressionFeature(categoryName: string): string?
	if _topProgressionCache[categoryName] ~= nil then
		return _topProgressionCache[categoryName] or nil
	end

	local bag = CATEGORY[categoryName]
	local bestName, bestScore = nil, -math.huge
	if type(bag) == "table" then
		for featureName in pairs(bag) do
			if not isDevProductFeature(featureName) then
				local tier = (UXP_TIER :: any)[featureName]
				local score = (type(tier) == "number" and tier) or progressionRequiredLevel(featureName)
				if score > bestScore then
					bestScore = score
					bestName = featureName
				end
			end
		end
	end

	_topProgressionCache[categoryName] = bestName or false
	return bestName
end

----------------------------------------------------------------
-- PERF: PER-CATEGORY PROVIDER TILE INDEX
--  [uid][category] = {
--     modes = {
--        [mode] = { radius = number, tiles = {["x|z"]=true}, minX, maxX, minZ, maxZ }
--     }
--  }
----------------------------------------------------------------
local _providerIndex = {}          -- [number][string] = table
local _providerIndexDirty = {}     -- [number] = { [string]=true } (mark specific cats dirty); special key "*" means all dirty

local function markAllProviderIndexDirty(uid:number)
	_providerIndexDirty[uid] = _providerIndexDirty[uid] or {}
	_providerIndexDirty[uid]["*"] = true
end

local function markProviderIndexDirtyForMode(uid:number, mode:string)
	_providerIndexDirty[uid] = _providerIndexDirty[uid] or {}
	for _, cat in ipairs(CATEGORIES) do
		local bag = CATEGORY[cat]
		if bag and bag[mode] then
			_providerIndexDirty[uid][cat] = true
		end
	end
end

local function isDirty(uid:number, cat:string): boolean
	local d = _providerIndexDirty[uid]
	return (d and (d["*"] or d[cat])) and true or false
end

local function clearDirty(uid:number, cat:string)
	local d = _providerIndexDirty[uid]
	if not d then return end
	d[cat] = nil
	d["*"] = nil
	if next(d) == nil then _providerIndexDirty[uid] = nil end
end

local function ensureProviderIndex(player: Player, categoryName: string)
	local uid = player.UserId
	_providerIndex[uid] = _providerIndex[uid] or {}
	if _providerIndex[uid][categoryName] and not isDirty(uid, categoryName) then
		return _providerIndex[uid][categoryName]
	end

	local bag = CATEGORY[categoryName]
	local all = ZoneTracker.getAllZones(player)
	local idx = { modes = {} }

	if not bag or not all then
		_providerIndex[uid][categoryName] = idx
		clearDirty(uid, categoryName)
		return idx
	end

	-- prepare per-mode buckets
	for mode in pairs(bag) do
		if not IGNORE_MODES[mode] then
			idx.modes[mode] = {
				radius = getInfluenceWidth(mode),
				tiles = {},
				minX = math.huge, maxX = -math.huge,
				minZ = math.huge, maxZ = -math.huge,
			}
		end
	end

	-- ingest provider tiles
	for _, prov in pairs(all) do
		local mode = prov.mode
		local mm = idx.modes[mode]
		if mm and prov.gridList then
			for _, b in ipairs(prov.gridList) do
				local k = keyXZ(b.x, b.z)
				mm.tiles[k] = true
				if b.x < mm.minX then mm.minX = b.x end
				if b.x > mm.maxX then mm.maxX = b.x end
				if b.z < mm.minZ then mm.minZ = b.z end
				if b.z > mm.maxZ then mm.maxZ = b.z end
			end
		end
	end

	_providerIndex[uid][categoryName] = idx
	clearDirty(uid, categoryName)
	return idx
end

----------------------------------------------------------------
-- provider coverage check (FAST: bucketed)
-- Semantics preserved: treat config radius as Chebyshev (L∞) tile radius.
----------------------------------------------------------------
local function hasCategoryCoverage(player: Player, targetZone, categoryName: string): boolean
	local bag = CATEGORY[categoryName]; if not bag then return false end
	local all = ZoneTracker.getAllZones(player); if not all then return false end
	local idx = ensureProviderIndex(player, categoryName)

	-- Quickly compute target zone AABB once
	targetZone._bb = targetZone._bb or aabbFromGridList(targetZone.gridList)
	local tbb = targetZone._bb

	-- If *none* of the provider modes have any tiles or intersect, early-out false
	local anyCandidate = false
	for _, mm in pairs(idx.modes) do
		if mm and next(mm.tiles) ~= nil then
			anyCandidate = true
			break
		end
	end
	if not anyCandidate then
		return false
	end

	-- For each target tile, probe nearby buckets within each mode's radius (O(|A| * sum r^2))
	for _, a in ipairs(targetZone.gridList or {}) do
		for _, mm in pairs(idx.modes) do
			if mm and next(mm.tiles) ~= nil then
				local r = mm.radius
				if not ((a.x + r) < mm.minX or (a.x - r) > mm.maxX or (a.z + r) < mm.minZ or (a.z - r) > mm.maxZ) then
					for dz = -r, r do
						for dx = -r, r do
							if mm.tiles[keyXZ(a.x + dx, a.z + dz)] then
								return true
							end
						end
					end
				end
			end
		end
	end
	return false
end

----------------------------------------------------------------
-- CORRECT CATEGORY UNLOCK CHECK (UPDATED)
----------------------------------------------------------------
local function isCategoryUnlocked(player: Player, categoryName: string): boolean
	local bag = CATEGORY[categoryName]
	if type(bag) ~= "table" then
		return false
	end

	-- 1) Category unlock is driven by **non-devproduct** features unlocked by level.
	--    If the player has ANY non-DP provider unlocked by progression, the category is considered unlocked.
	local bestProg = bestUnlockedProgressionFeature(player, categoryName)
	if bestProg then
		return true
	end

	-- 2) Devproducts must NOT unlock categories by themselves.
	--    We only allow a DP to make the category "advisable" if BOTH:
	--       (a) the player has at least one devproduct instance in this category placed, AND
	--       (b) the current max progression tier for this category is already PRESENT (built) in the city.
	local hasAnyDPPlaced = playerHasDevProductPlacement(player, categoryName)
	if hasAnyDPPlaced then
		-- Require the absolute top non-dev progression feature (from Balance) to be present in the city.
		local topFeat = topProgressionFeature(categoryName)
		if topFeat and playerHasBuiltFeature(player, topFeat) then
			return true
		end
	end

	return false
end

-----------------------------
-- ICON POOL / MODEL SAFE
-----------------------------
-- We support BasePart **or** Model (uses PrimaryPart or first descendant BasePart).
local RequestPool: { [string]: { Instance } } = {}    -- pooled clones (BasePart or Model)
local ActiveReq : { [Instance]: { base:Vector3, token:number, expires:number } } = {}
local _lastAnchorSpawnAt: { [string]: number } = {}
local heartbeatConn

local function findAnyPart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then return inst end
	if inst:IsA("Model") then
		local mdl = inst :: Model
		if mdl.PrimaryPart then return mdl.PrimaryPart end
		for _, d in ipairs(mdl:GetDescendants()) do
			if d:IsA("BasePart") then return d end
		end
		return nil
	end
	-- Folder / others: search first child part
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then return d end
	end
	return nil
end

local function borrowTemplateClone(templateName: string): Instance?
	if not AlarmsFolder then return nil end
	RequestPool[templateName] = RequestPool[templateName] or {}
	local pool = RequestPool[templateName]
	local obj = table.remove(pool)
	if obj then return obj end

	local t = AlarmsFolder:FindFirstChild(templateName)
	if not t then dprint("Template missing:", templateName); return nil end

	local clone = t:Clone()
	-- Set physics flags for all parts inside
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	return clone
end

local function returnTemplateClone(inst: Instance)
	if not inst then return end
	ActiveReq[inst] = nil
	inst.Parent = nil
	local tname = inst:GetAttribute("__TemplateName")
	if not tname then inst:Destroy(); return end
	RequestPool[tname] = RequestPool[tname] or {}
	table.insert(RequestPool[tname], inst)
end

local function ensureAdvisorFolder(plot: Instance): Folder
	local f = plot:FindFirstChild("CivicRequests")
	if not f then f = Instance.new("Folder"); f.Name="CivicRequests"; f.Parent=plot end
	return f
end

local function startHeartbeat()
	if heartbeatConn then return end
	local t = 0
	heartbeatConn = RunServiceScheduler.onHeartbeat(function(dt)
		t += dt
		for inst, info in pairs(ActiveReq) do
			if inst.Parent then
				local part = findAnyPart(inst)
				if part then
					local pos = info.base
					if USE_SHARED_BOBBING then
						pos = info.base + Vector3.new(0, math.sin(t*BOB_SPEED)*BOB_AMPLITUDE, 0)
					end
					-- Move model or part
					if inst:IsA("Model") then
						local mdl = inst :: Model
						local pp = mdl.PrimaryPart or part
						local delta = pos - pp.Position
						mdl:PivotTo(mdl:GetPivot() + delta)
					else
						(part :: BasePart).Position = pos
					end
				end
				if now() >= info.expires then
					returnTemplateClone(inst)
				end
			else
				ActiveReq[inst] = nil
			end
		end
		if next(ActiveReq) == nil and heartbeatConn then
			heartbeatConn()
			heartbeatConn = nil
		end
	end)
end

local function upsertRequestIcon(player: Player, templateName: string, nameKey: string, worldPos: Vector3, jitter: number)
	local plot = getPlayerPlot(player)
	if not plot then dprint("No plot for player", player and player.UserId) return end
	local folder = ensureAdvisorFolder(plot)
	local existing = folder:FindFirstChild(nameKey)

	local inst: Instance
	if existing then
		inst = existing
	else
		local clone = borrowTemplateClone(templateName)
		if not clone then dprint("Borrow failed", templateName); return end
		inst = clone
		inst.Name = nameKey
		inst:SetAttribute("__TemplateName", templateName)
		inst.Parent = folder
	end

	-- Position
	local part = findAnyPart(inst)
	if not part then dprint("No BasePart inside template", templateName); return end
	if inst:IsA("Model") then
		local mdl = inst :: Model
		local pp = mdl.PrimaryPart or part
		mdl:PivotTo(CFrame.new(worldPos))
	else
		(part :: BasePart).Position = worldPos
	end

	local token = ((ActiveReq[inst] and ActiveReq[inst].token) or 0) + 1
	ActiveReq[inst] = { base = worldPos, token = token, expires = now() + REQUEST_TTL_SEC + jitter }
	startHeartbeat()
end

-----------------------------
-- DIALOGUE (minimal)
-----------------------------
local _cd: { [Player]: { [string]: number } } = {}
local COOLDOWN = { Police = 45.0, Advice = 30.0 }
local CrimeLines = {
	["Ban crime! I want no more crime!"] = true,
	["I will happily pay some extra taxes, if we can get the crime levels down."] = true,
}
local function cdOk(player: Player, bucket: string, sec: number): boolean
	_cd[player] = _cd[player] or {}
	local t = _cd[player][bucket] or 0
	if now() < t then return false end
	_cd[player][bucket] = now() + sec
	return true
end
local function randKey(tbl: { [string]: boolean }): string?
	local n=0; for _ in pairs(tbl) do n+=1 end
	if n==0 then return nil end
	local pick = math.random(1,n)
	local i=0; for k in pairs(tbl) do i+=1; if i==pick then return k end end
	return nil
end
local function pushCrime(player: Player)
	if not cdOk(player, "Police", COOLDOWN.Police) then return end
	local line = randKey(CrimeLines) or "Crime is getting out of hand around here!"
	RE_AdvisorSay:FireClient(player, { category = "Crime", text = line })
	if RE_NotifyPlayer then RE_NotifyPlayer:FireClient(player, line) end
end

-----------------------------
-- SCAN LOGIC (city-wide)
-----------------------------
local _lastScanAt: { [Player]: number } = {}

local function buildMissingTiles(player: Player, categoryName: string): ({ [string]: boolean }, string?)
	local allZones = ZoneTracker.getAllZones(player)
	if not allZones then dprint("No zones for player"); return {}, nil end

	local missing: { [string]: boolean } = {}
	local sample: string? = nil
	local bag = CATEGORY[categoryName]
	if not bag then dprint("CATEGORY absent for", categoryName); return {}, nil end

	-- Don’t compute/emit for locked category (updated semantics)
	if not isCategoryUnlocked(player, categoryName) then
		return {}, nil
	end

	for zid, z in pairs(allZones) do
		if TARGET_BUILDING_MODES[z.mode] then
			if not isZonePopulated(player, zid) then
				dprint("Skip (unpopulated)", zid)
			else
				local covered = hasCategoryCoverage(player, z, categoryName)
				if not covered then
					for _, c in ipairs(z.gridList or {}) do
						local w = ZoneTracker.getGridWealth(player, zid, c.x, c.z)
						if ALLOWED_WEALTH[w or ""] then
							missing[keyXZ(c.x, c.z)] = true
							sample = sample or zid
						end
					end
				end
			end
		end
	end
	return missing, sample
end

local function placeCategoryClusters(player: Player, categoryName: string, tileSet: { [string]: boolean }): number
	-- Don’t place icons for locked category (updated semantics)
	if not isCategoryUnlocked(player, categoryName) then
		return 0
	end

	local template = TEMPLATE_BY_CATEGORY[categoryName]
	if not template then dprint("No template mapping for", categoryName); return 0 end
	local plot = getPlayerPlot(player); if not plot then dprint("No plot"); return 0 end

	local clusters = clusterTiles(tileSet)
	local filtered = {}
	for _, cl in ipairs(clusters) do
		if #cl >= MIN_CLUSTER_SIZE_TILES then filtered[#filtered+1] = cl end
	end

	local placed, budget, frameBudget = 0, MAX_CLUSTERS_PER_CATEGORY, MAX_CLUSTERS_PER_CATEGORY_TICK
	for idx, cl in ipairs(filtered) do
		if placed >= budget or frameBudget <= 0 then break end
		local ctr = centroid(cl)
		local wp  = gridToWorld(plot, ctr.x, ctr.z) + Vector3.new(0, AREA_OFFSET_Y, 0)

		local anchorKey = string.format("%d|%s|%d|%d", player.UserId, categoryName, ctr.x, ctr.z)
		local lastAt = _lastAnchorSpawnAt[anchorKey] or 0
		if (now() - lastAt) >= REQUEST_RESPAWN_COOLDOWN_SEC then
			_lastAnchorSpawnAt[anchorKey] = now()
			local nameKey = string.format("Req_%s_%d_%d_%d", categoryName, ctr.x, ctr.z, idx)
			local jitter  = math.random() * 0.75
			upsertRequestIcon(player, template, nameKey, wp, jitter)
			placed += 1
			frameBudget -= 1
			if frameBudget > 0 then task.wait(0.02 + math.random()*0.02) end
		else
			dprint("Anchor cooldown", categoryName, ctr.x, ctr.z)
		end
	end
	return placed
end

-- DEV canary (single pulse) to prove rendering even if coverage logic yields none
local function dev_canary(player: Player)
	if not DEV_CANARY_ENABLE then return end
	-- Respect player level: only canary a category that is unlocked.
	if not isCategoryUnlocked(player, DEV_CANARY_CATEGORY) then
		dprint("DEV canary suppressed; category locked:", DEV_CANARY_CATEGORY)
		return
	end

	local zones = ZoneTracker.getAllZones(player); if not zones then return end
	for zid, z in pairs(zones) do
		if z.mode == "Residential" and z.gridList and #z.gridList > 0 then
			local sx, sz = 0, 0
			for _,c in ipairs(z.gridList) do sx += c.x; sz += c.z end
			local n = #z.gridList
			local cx, cz = math.floor(sx/n + 0.5), math.floor(sz/n + 0.5)
			local plot = getPlayerPlot(player); if not plot then return end
			local wp = gridToWorld(plot, cx, cz) + Vector3.new(0, AREA_OFFSET_Y, 0)
			local template = TEMPLATE_BY_CATEGORY[DEV_CANARY_CATEGORY] or "RequestPolice"
			local nameKey = string.format("Req_%s_%d_%d_dev", DEV_CANARY_CATEGORY, cx, cz)
			upsertRequestIcon(player, template, nameKey, wp, 0.3)
			dprint("DEV canary spawned at", cx, cz, "using", template)
			break
		end
	end
end

-----------------------------
-- WEAKEST-AREA CLOCK
-----------------------------
local function findWeakestZoneAndMissing(player: Player): (any?, {string})
	local zones = ZoneTracker.getAllZones(player)
	if not zones then return nil, {} end

	local uid = player.UserId
	_lastPingAt[uid] = _lastPingAt[uid] or {}

	local weakestZone, weakestMissing, weakestCovered = nil, {}, math.huge
	for zid, z in pairs(zones) do
		if TARGET_BUILDING_MODES[z.mode] and isZonePopulated(player, zid) then
			local lastPing = _lastPingAt[uid][zid] or 0
			if (now() - lastPing) >= LAST_PING_COOLDOWN_SEC then
				local missing, coveredCount = {}, 0
				for _, cat in ipairs(CATEGORIES) do
					if isCategoryUnlocked(player, cat) then
						if hasCategoryCoverage(player, z, cat) then
							coveredCount += 1
						else
							table.insert(missing, cat)
						end
					else
						dprint("Clock skip locked category:", cat)
					end
				end
				if coveredCount < weakestCovered and #missing > 0 then
					weakestCovered = coveredCount
					weakestZone = z
					weakestMissing = missing
				end
			end
		end
	end
	return weakestZone, weakestMissing
end

local function missingCategoriesForZone(player: Player, zone: any): {string}
	local miss = {}
	for _, cat in ipairs(CATEGORIES) do
		if isCategoryUnlocked(player, cat) and not hasCategoryCoverage(player, zone, cat) then
			table.insert(miss, cat)
		end
	end
	return miss
end

-- Revalidate that focus is still valid & still missing
local function focusStillNeeded(player: Player, f: table): boolean
	local zones = ZoneTracker.getAllZones(player); if not zones then return false end
	local z = zones[f.zoneId]; if not z then return false end
	if not (TARGET_BUILDING_MODES[z.mode] and isZonePopulated(player, f.zoneId)) then return false end
	if not isCategoryUnlocked(player, f.category) then return false end
	return not hasCategoryCoverage(player, z, f.category)
end

-- Choose a new focus (weakest zone, then first missing category), record centroid once
local function pickNewFocus(player: Player): table?
	local zone, missing = findWeakestZoneAndMissing(player)
	if not (zone and #missing > 0) then return nil end

	-- Largest contiguous cluster centroid for stability
	local tiles = {}
	for _, c in ipairs(zone.gridList or {}) do tiles[keyXZ(c.x, c.z)] = true end
	local clusters = clusterTiles(tiles); if #clusters == 0 then return nil end
	table.sort(clusters, function(a,b) return #a > #b end)
	local ctr = centroid(clusters[1])

	local cat = missing[1]
	local nameKey = string.format("Focus_%s_%d_%d", cat, ctr.x, ctr.z)

	local f = { zoneId = zone.zoneId or zone.id, category = cat, cx = ctr.x, cz = ctr.z, nameKey = nameKey }
	_focus[player.UserId] = f
	return f
end

-- Ensure (create/refresh) the single focus icon. Returns true if an icon exists after call.
local function ensureFocusIcon(player: Player): boolean
	local uid = player.UserId
	local f = _focus[uid]

	-- If no focus or focus satisfied/invalid, try to pick a new one
	if not (f and focusStillNeeded(player, f)) then
		_focus[uid] = nil
		f = pickNewFocus(player)
		if not f then return false end
	end

	-- Place/refresh the one icon
	local plot = getPlayerPlot(player); if not plot then return false end
	local wp = gridToWorld(plot, f.cx, f.cz) + Vector3.new(0, AREA_OFFSET_Y, 0)

	local template = TEMPLATE_BY_CATEGORY[f.category]
	if not template then return false end

	-- Slight jitter keeps the pulse alive without spamming different anchors
	upsertRequestIcon(player, template, f.nameKey, wp, math.random()*0.4)
	return true
end

-- Place ONE request icon for a given category in a single zone (largest cluster centroid)
local function placeOneRequestForZone(player: Player, zone: any, categoryName: string): boolean
	-- respect level on clock placement
	if not isCategoryUnlocked(player, categoryName) then
		dprint("Clock placement suppressed; locked category:", categoryName)
		return false
	end

	local plot = getPlayerPlot(player); if not plot then return false end
	local template = TEMPLATE_BY_CATEGORY[categoryName]; if not template then return false end

	-- Every eligible tile in this zone is “missing” (since zone-level coverage is false)
	local tiles = {}
	for _, c in ipairs(zone.gridList or {}) do
		local w = ZoneTracker.getGridWealth(player, zone.zoneId or zone.id, c.x, c.z)
		if ALLOWED_WEALTH[w or ""] then
			tiles[keyXZ(c.x, c.z)] = true
		end
	end
	local clusters = clusterTiles(tiles)
	if #clusters == 0 then return false end

	table.sort(clusters, function(a,b) return #a > #b end)
	local ctr = centroid(clusters[1])
	local wp  = gridToWorld(plot, ctr.x, ctr.z) + Vector3.new(0, AREA_OFFSET_Y, 0)
	local nameKey = string.format("Req_%s_%d_%d_tick", categoryName, ctr.x, ctr.z)
	upsertRequestIcon(player, template, nameKey, wp, math.random()*0.6)
	return true
end

local function startClockFor(player: Player)
	if _clockTasks[player] then return end
	_clockTasks[player] = true
	task.spawn(function()
		while _clockTasks[player] do
			ensureFocusIcon(player)
			task.wait(CLOCK_PERIOD_SEC)
		end
	end)
end

local function stopClockFor(player: Player)
	_clockTasks[player] = nil
end

-----------------------------
-- PUBLIC API
-----------------------------
local CivicRequestsAdvisor = {}
CivicRequestsAdvisor.__index = CivicRequestsAdvisor

function CivicRequestsAdvisor.scanCity(player: Player)
	if not (player and player:IsA("Player")) then return end
	local last = _lastScanAt[player] or 0
	if (now() - last) < RESCAN_THROTTLE_SEC then return end
	_lastScanAt[player] = now()

	-- Drive/update the single-focus icon once per scan
	local had = ensureFocusIcon(player)

	-- Emit counts for UI (report 0/1 style per category: focused category=1 if placed this scan)
	local counts = {}
	for _, cat in ipairs(CATEGORIES) do counts[cat] = 0 end
	if had and _focus[player.UserId] then
		local f = _focus[player.UserId]
		if f and counts[f.category] ~= nil then counts[f.category] = 1 end
	end
	EVT_RequestAlarmsChanged:Fire(player, counts)

	-- Optional: say one crime line the first time we create/refresh a Police focus
	if had then
		local f = _focus[player.UserId]
		if f and f.category == "Police" then pushCrime(player) end
	end
end

function CivicRequestsAdvisor.scanImpacted(player: Player, _seedZoneId: string)
	CivicRequestsAdvisor.scanCity(player)
end

-----------------------------
-- WIRING (ZonePopulated-aware + removing noise)
-----------------------------
local function wire()
	local ZonePopulated = BindableEvents:FindFirstChild("ZonePopulated")
	local ZoneRemoved   = BindableEvents:FindFirstChild("ZoneRemoved")

	if ZonePopulated then
		ZonePopulated.Event:Connect(function(player: Player, zoneId: string)
			-- mark populated immediately so future scans consider it
			local uid = player.UserId
			_populated[uid] = _populated[uid] or {}
			_populated[uid][zoneId] = true

			-- detect if this zone is a provider (may satisfy pending needs elsewhere)
			local z = ZoneTracker.getZoneById and ZoneTracker.getZoneById(player, zoneId)
			local isProvider = false
			if z and z.mode then
				for _, cat in ipairs(CATEGORIES) do
					local bag = CATEGORY[cat]
					if bag and bag[z.mode] then
						isProvider = true
						-- PERF: mark index dirty for this provider mode so next coverage check rebuilds
						markProviderIndexDirtyForMode(uid, z.mode)
					end
				end
			end

			-- drop focus if: (a) focused zone just satisfied, or (b) any provider just appeared
			local f = _focus[uid]
			if f and f.zoneId == zoneId and not focusStillNeeded(player, f) then
				_focus[uid] = nil
			end
			if isProvider then
				_focus[uid] = nil
			end

			-- rescan gently (next tick will re-pick/refresh focus)
			task.defer(function()
				if isProvider then
					CivicRequestsAdvisor.scanCity(player)
				else
					CivicRequestsAdvisor.scanImpacted(player, zoneId)
				end
			end)
		end)
	end

	local DemandUpdated = BindableEvents:FindFirstChild("DemandUpdated", 5)
	if DemandUpdated then
		(DemandUpdated :: any).Event:Connect(function(player: Player, demandTbl: any, snapshot: any)
			if snapshot and snapshot.suggestAdvisor then
				CivicRequestsAdvisor.scanCity(player)
			end
		end)
	end

	if ZoneRemoved then
		(ZoneRemoved :: any).Event:Connect(function(p: Player, zid: string)
			local uid = p.UserId
			if _populated[uid] then _populated[uid][zid] = nil end

			-- conservatively mark all categories dirty
			markAllProviderIndexDirty(uid)

			-- drop focus if it was pointing at the removed zone
			local f = _focus[uid]
			if f and f.zoneId == zid then
				_focus[uid] = nil
			end

			task.defer(function()
				CivicRequestsAdvisor.scanImpacted(p, zid)
			end)
		end)
	end

	-- manual trigger
	EVT_ScanRequested.Event:Connect(function(p)
		CivicRequestsAdvisor.scanCity(p)
	end)
end

-- Player lifecycle: start/stop the advisor clock
Players.PlayerAdded:Connect(function(plr)
	task.delay(1.0, function()
		if plr.Parent then startClockFor(plr) end
	end)
end)

Players.PlayerRemoving:Connect(function(plr)
	stopClockFor(plr)
	_lastScanAt[plr] = nil
	_cd[plr] = nil
	_lastPingAt[plr.UserId] = nil
	_populated[plr.UserId] = nil
	_focus[plr.UserId] = nil

	-- Cleanup provider index
	_providerIndex[plr.UserId] = nil
	_providerIndexDirty[plr.UserId] = nil
end)
wire()

function CivicRequestsAdvisor.isCategoryUnlockedPublic(player: Player, categoryName: string): boolean
	return isCategoryUnlocked(player, categoryName)
end

return CivicRequestsAdvisor
