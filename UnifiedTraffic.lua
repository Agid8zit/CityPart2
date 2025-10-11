--==========================================--
-- UnifiedTraffic (your second chunk) ENHANCED
--==========================================--
local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

--// Modules
local GridConfig        = require(ReplicatedStorage.Scripts.Grid.GridConfig)
local GridUtil          = require(ReplicatedStorage.Scripts.Grid.GridUtil)
local ZoneTrackerModule = require(game.ServerScriptService.Build.Zones.ZoneManager.ZoneTracker)
local PathingModule     = require(script.Parent.PathingModule)   -- existing
local CarMovement       = require(script.Parent.CarMovement)     -- existing

--// Events
local BindableEvents       = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents")
local RemoteEvents         = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents")
local ZoneAddedEvt         = BindableEvents:WaitForChild("ZoneAdded")
local ZoneRemovedEvt       = BindableEvents:WaitForChild("ZoneRemoved")
local ZoneReCreatedEvt     = BindableEvents:WaitForChild("ZoneReCreated")
local ZonePopulatedEvt     = BindableEvents:WaitForChild("ZonePopulated")
local FireSupportEvt       = BindableEvents:WaitForChild("FireSupportUnlocked")
local BusSupportUnlocked   = BindableEvents:WaitForChild("BusSupportUnlocked")
local BusSupportRevoked    = BindableEvents:WaitForChild("BusSupportRevoked")
local SpawnCarToFarthestEvt = RemoteEvents:FindFirstChild("SpawnCarToFarthest")
local CameraAttachEvt       = RemoteEvents:FindFirstChild("CameraAttachToCar")

-- Save reload gates (optional, but your stack has them)
local RequestReloadFromCurrentEvt = BindableEvents:FindFirstChild("RequestReloadFromCurrent")
local NetworksPostLoadEvt         = BindableEvents:FindFirstChild("NetworksPostLoad")

--// Template Roots
local CarsRoot          = ReplicatedStorage:WaitForChild("FuncTestGroundRS"):WaitForChild("Cars")
local DefaultCarsFolder = CarsRoot:WaitForChild("RedTestCar")
local UniqueCarsFolder  = CarsRoot:FindFirstChild("UniqueCars")
local BusesFolder       = CarsRoot:FindFirstChild("Buses") or CarsRoot:FindFirstChild("Busses")

--======================================================================
--  CONFIG (tune to taste)
--======================================================================
local FIXED_Y_OFFSET            = 1.5

local MIN_PATH_CELLS            = 6       -- don’t spawn for trivial hops
local SPAWN_INTERVAL_SEC        = 2.0     -- target average (per player)
local RANDOM_JITTER_SEC         = 1.25    -- jitter to avoid sync bursts
local MAX_CONCURRENT_PER_PLAYER = 10      -- live cars cap per player
local TOKEN_BUCKET_RATE         = 0.5     -- tokens/sec added
local TOKEN_BUCKET_MAX          = 5       -- max tokens
local CAR_LIFETIME_SEC          = 300     -- hard cleanup fallback
local FADE_OUT_TIME             = 1.5     -- despawn fade
local RECOMPUTE_DEBOUNCE        = 0.1     -- recompute coalescing
local RESCAN_PERIODIC_SEC       = 45      -- periodic safety net

-- Two-way options (kept; ignored in zone-based modes below)
local BUS_SPAWN_CHANCE          = 0.25
local FIRE_SPAWN_CHANCE         = 0.15
local TWO_WAY_ENABLED           = true
local TWO_WAY_MODE              = "mirror"        -- "mirror" or "chance"
local TWO_WAY_CHANCE            = 0.5

-- Prefer sinks from endpoints; allow near-zone sinks
local PREFER_ENDPOINT_SINKS     = true

-- Source of the road network (must be covered by a road tile to be "live").
-- In zone-based modes this acts as the DESTINATION.
local SOURCE_COORD = { x = 0, z = 0 }

-- NEW: how close (in grid cells) a non-road zone center must be to “snap” to a road node as a zone source
local NEAR_ZONE_MAX_DIST_CELLS  = 3
-- Optionally cap how many near-zone sources we consider
local MAX_NEAR_ZONE_SINKS       = 16

-- NEW: Dispatch mode. Choose ONE.
--   "ZoneToOriginOnly"     -> spawn near-zone -> drive to SOURCE_COORD (your request)
--   "ZoneToOriginAndBack"  -> also mirror a return trip SOURCE_COORD -> the same zone
--   "OriginToSinks"        -> legacy behavior (SOURCE_COORD -> sinks [+ optional mirror])
local DISPATCH_MODE = "ZoneToOriginAndBack"

--======================================================================
--  STATE
--======================================================================
local fireSupport = {}  -- [userId] = true when Fire unlocked
local busSupport  = {}  -- [userId] = true when Bus unlocked
local _busWarnedMissing = false

local ctxByUserId = {}

local templates = {
	default = {},
	fire    = {},
	bus     = {},
}

--======================================================================
--  ALL-WAY STOP CONFIG + HELPERS
--======================================================================
local ALL_WAY_STOP_SEC       = 0.30
local STOP_JITTER_SEC        = 0.35
local INCLUDE_TURNS_AS_STOPS = false

--========================
-- [DRIVE MODE] CONFIG
--========================
local DRIVE_RESPAWN_DELAY   = 1.0     -- time between trips
local DRIVE_MOVE_DIST_STOP  = 6.0     -- studs from start pos (2D)
local DRIVE_MOVE_SPEED_STOP = 7.0     -- studs/sec (rough walking+)

--======================================================================
--  UTILITIES
--======================================================================
local function dprint(...) end

local function getPlotForUserId(uid)
	local plots = Workspace:FindFirstChild("PlayerPlots")
	return plots and plots:FindFirstChild("Plot_"..tostring(uid))
end

local boundsCache = {} -- [plot] = { bounds=..., terrains={...} }
local function getGlobalBoundsForPlot(plot)
	if not plot then return nil, nil end
	local cached = boundsCache[plot]
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
	boundsCache[plot] = { bounds = gb, terrains = terrains }
	return gb, terrains
end

local function gridToWorld(plot, coord)
	local gb, terrains = getGlobalBoundsForPlot(plot)
	if not gb then
		local worldX, worldZ = GridUtil.gridToWorldPosition(coord.x, coord.z, 0, 0)
		return Vector3.new(worldX, FIXED_Y_OFFSET, worldZ)
	end
	local wx, _, wz = GridUtil.globalGridToWorldPosition(coord.x, coord.z, gb, terrains)
	return Vector3.new(wx, FIXED_Y_OFFSET, wz)
end


-- Token bucket
local function addTokens(ctx)
	local t = os.clock()
	local dt = t - (ctx.last or t)
	ctx.tokens = math.min(TOKEN_BUCKET_MAX, (ctx.tokens or 0) + dt * TOKEN_BUCKET_RATE)
	ctx.last = t
end
local function trySpend(ctx, cost)
	addTokens(ctx)
	if ctx.tokens >= cost then
		ctx.tokens -= cost
		return true
	end
	return false
end

local function buildEdgeKeysForPath(gridPath)
	if not gridPath or #gridPath < 2 then return {} end
	local edgeKeys = {}
	for k = 1, #gridPath - 1 do
		local a = gridPath[k]
		local b = gridPath[k+1]
		edgeKeys[k] = string.format("%d_%d->%d_%d", a.x, a.z, b.x, b.z)
	end
	return edgeKeys
end

local function computePreIntersectionStops(gridPath)
	if not gridPath or #gridPath < 3 then return {}, {} end
	local preStops, keysByIdx = {}, {}
	for i = 2, #gridPath - 1 do
		local c = gridPath[i]
		local cls = PathingModule.classifyNode(c)
		if cls == "4Way" or cls == "3Way" or (INCLUDE_TURNS_AS_STOPS and cls == "Turn") then
			local preIdx = i - 1
			if preIdx >= 1 then
				preStops[#preStops+1] = preIdx
				keysByIdx[preIdx] = PathingModule.nodeKey(c)
			end
		end
	end
	if #preStops > 1 then
		local compact = { preStops[1] }
		for k = 2, #preStops do
			if preStops[k] ~= preStops[k-1] then
				compact[#compact+1] = preStops[k]
			end
		end
		preStops = compact
	end
	return preStops, keysByIdx
end

local function newPathId(uid)
	return ("P%s_%d"):format(uid, math.floor(os.clock()*1000))
end

local function reversedGridPath(path)
	if not path or #path < 2 then return nil end
	local out = table.create(#path)
	for i = #path, 1, -1 do
		out[#out + 1] = { x = path[i].x, z = path[i].z }
	end
	return out
end

-- Templates
local function clear(list) for i=#list,1,-1 do list[i]=nil end end
local function repackChildren(folder, into)
	if not folder then return end
	for _, ch in ipairs(folder:GetChildren()) do
		if ch:IsA("Model") then
			table.insert(into, ch)
		elseif ch:IsA("Folder") then
			for _, m in ipairs(ch:GetChildren()) do
				if m:IsA("Model") then table.insert(into, m) end
			end
		end
	end
end

local function refreshTemplateCache()
	clear(templates.default); repackChildren(DefaultCarsFolder, templates.default)
	clear(templates.fire)
	if UniqueCarsFolder then
		local fireNode = UniqueCarsFolder:FindFirstChild("Fire")
		if fireNode then
			if fireNode:IsA("Model") then table.insert(templates.fire, fireNode)
			else repackChildren(fireNode, templates.fire) end
		end
	end
	clear(templates.bus)
	if BusesFolder then repackChildren(BusesFolder, templates.bus) end
end
refreshTemplateCache()
local function watchFolder(folder)
	if not folder then return end
	folder.ChildAdded:Connect(function() task.defer(refreshTemplateCache) end)
	folder.ChildRemoved:Connect(function() task.defer(refreshTemplateCache) end)
end
watchFolder(DefaultCarsFolder); watchFolder(UniqueCarsFolder); watchFolder(BusesFolder)

local function pickTemplateForPlayer(player)
	local uid = player.UserId
	if busSupport[uid] and #templates.bus > 0 and math.random() < BUS_SPAWN_CHANCE then
		return templates.bus[math.random(1, #templates.bus)], "Bus"
	end
	if busSupport[uid] and #templates.bus == 0 and not _busWarnedMissing then
		warn("[UnifiedTraffic] Bus support enabled but no bus models found under Cars.Buses/Busses; falling back to cars.")
		_busWarnedMissing = true
	end
	if fireSupport[uid] and #templates.fire > 0 and math.random() < FIRE_SPAWN_CHANCE then
		return templates.fire[math.random(1, #templates.fire)], "Fire"
	end
	if #templates.default == 0 then
		warn("[UnifiedTraffic] DefaultCarsFolder is empty; cannot spawn traffic.")
		return nil, nil
	end
	return templates.default[math.random(1, #templates.default)], "Default"
end

--======================================================================
--  GRAPH / OWNERSHIP FILTERING
--======================================================================
local function refreshOwnRoadZones(player, ctx)
	local set = {}
	for zid, z in pairs(ZoneTrackerModule.getAllZones(player)) do
		if z.mode == "DirtRoad" or z.mode == "Pavement" or z.mode == "Highway" then
			set[zid] = true
		end
	end
	ctx.ownRoadZoneIds = set
end

local function nodeOwnedByPlayer(player, key)
	local meta = PathingModule.nodeMeta and PathingModule.nodeMeta[key]
	if not meta then return false end
	local zid = meta.groupId
	if not zid then return false end
	return ZoneTrackerModule.getZoneById(player, zid) ~= nil
end

local function bfsPathOwned(player, startCoord, endCoord)
	local startKey = PathingModule.nodeKey(startCoord)
	local endKey   = PathingModule.nodeKey(endCoord)
	local adj = PathingModule.globalAdjacency
	if not (adj and adj[startKey] and adj[endKey]) then return nil end
	if not nodeOwnedByPlayer(player, startKey) then return nil end
	if not nodeOwnedByPlayer(player, endKey)   then return nil end

	local q, seen, parent = { startKey }, { [startKey]=true }, {}
	while #q > 0 do
		local cur = table.remove(q, 1)
		if cur == endKey then
			local keys, k = {}, cur
			while k do keys[#keys+1] = k; k = parent[k] end
			for i=1, math.floor(#keys/2) do keys[i], keys[#keys-i+1] = keys[#keys-i+1], keys[i] end
			local path = {}
			for i=1,#keys do local xz = string.split(keys[i], "_"); path[i] = { x=tonumber(xz[1]), z=tonumber(xz[2]) } end
			return path
		end
		local nbrs = adj[cur]
		if nbrs then
			for i=1,#nbrs do
				local nb = nbrs[i]
				if not seen[nb] and nodeOwnedByPlayer(player, nb) then
					seen[nb] = true
					parent[nb] = cur
					table.insert(q, nb)
				end
			end
		end
	end
	return nil
end

local function pathIsValid(player, path)
	if not path or #path < 2 then return false end
	local adj = PathingModule.globalAdjacency
	if not adj then return false end
	for i = 1, #path do
		local k = PathingModule.nodeKey(path[i])
		if not (adj[k] and nodeOwnedByPlayer(player, k)) then
			return false
		end
	end
	return true
end

-- BFS to a specific target (re-derive a path when shortcuts were added)
local function bfsToTarget(player, targetCoord)
	if not targetCoord then return nil end
	return bfsPathOwned(player, SOURCE_COORD, targetCoord)
end

local function originLiveForPlayer(player)
	local key = PathingModule.nodeKey(SOURCE_COORD)
	local adj = PathingModule.globalAdjacency
	return adj and adj[key] ~= nil and nodeOwnedByPlayer(player, key)
end

local function zoneCenterCoord(z)
	local cells = z.gridList or z.cells or z.grid or z.coords
	if type(cells) ~= "table" or #cells == 0 then return nil end
	local sx, sz = 0, 0
	for i=1,#cells do
		local c = cells[i]
		if c and type(c.x)=="number" and type(c.z)=="number" then
			sx += c.x; sz += c.z
		end
	end
	return { x = math.floor(sx/#cells + 0.5), z = math.floor(sz/#cells + 0.5) }
end

local function collectNearZoneSinks(player)
	local sinks, count = {}, 0
	for _, z in pairs(ZoneTrackerModule.getAllZones(player)) do
		if z.mode ~= "DirtRoad" and z.mode ~= "Pavement" and z.mode ~= "Highway" then
			local center = zoneCenterCoord(z)
			if center then
				local near = PathingModule.findNearestRoadNode(center, NEAR_ZONE_MAX_DIST_CELLS)
				if near and nodeOwnedByPlayer(player, near.key) then
					sinks[#sinks+1] = { x = near.x, z = near.z }
					count += 1
					if count >= MAX_NEAR_ZONE_SINKS then break end
				end
			end
		end
	end
	return sinks
end

local function computeSinksForPlayer(player)
	local ranked = {}
	local function tryRank(coord)
		if coord and type(coord.x)=="number" and type(coord.z)=="number" then
			local p = bfsPathOwned(player, SOURCE_COORD, coord)
			if p and #p >= MIN_PATH_CELLS then
				table.insert(ranked, { coord = coord, len = #p })
			end
		end
	end
	if PREFER_ENDPOINT_SINKS then
		for _, coord in ipairs(PathingModule.getOwnedDeadEnds(player)) do
			tryRank(coord)
		end
	end
	if #ranked == 0 then
		for _, coord in ipairs(collectNearZoneSinks(player)) do tryRank(coord) end
	end
	if #ranked == 0 then
		local adj = PathingModule.globalAdjacency or {}
		local sampled = 0
		for key,_ in pairs(adj) do
			if nodeOwnedByPlayer(player, key) then
				local xz = string.split(key, "_")
				local c = { x = tonumber(xz[1]), z = tonumber(xz[2]) }
				tryRank(c)
				sampled += 1
				if sampled >= 128 then break end
			end
		end
	end
	table.sort(ranked, function(a,b) return a.len > b.len end)
	if #ranked >= 4 then
		local keep = math.max(4, math.floor(#ranked * 0.25 + 0.5))
		while #ranked > keep do table.remove(ranked) end
	end
	local sinks = {}
	for i=1,#ranked do sinks[i] = ranked[i].coord end
	return sinks
end

local function computeZoneSourcesForPlayer(player)
	local ranked = {}
	for _, sourceCoord in ipairs(collectNearZoneSinks(player)) do
		local p = bfsPathOwned(player, sourceCoord, SOURCE_COORD)
		if p and #p >= MIN_PATH_CELLS then
			table.insert(ranked, { coord = sourceCoord, len = #p })
		end
	end
	table.sort(ranked, function(a,b) return a.len > b.len end)
	if #ranked >= 4 then
		local keep = math.max(4, math.floor(#ranked * 0.25 + 0.5))
		while #ranked > keep do table.remove(ranked) end
	end
	local sources = {}
	for i=1,#ranked do sources[i] = ranked[i].coord end
	return sources
end


--======================================================================
--  SPAWN / MOVE / CLEANUP
--======================================================================
local function fadeOutAndDestroy(model, t)
	if not model then return end
	local info  = TweenInfo.new(t, Enum.EasingStyle.Linear)
	local tweens = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("MeshPart") or d:IsA("Decal") then
			table.insert(tweens, TweenService:Create(d, info, {Transparency = 1}))
		end
	end
	for i=1,#tweens do tweens[i]:Play() end
	if #tweens > 0 then
		tweens[1].Completed:Connect(function() pcall(function() model:Destroy() end) end)
	else
		pcall(function() model:Destroy() end)
	end
end

local function worldPathFor(plot, gridPath)
	if not gridPath or #gridPath == 0 then return nil end
	local out = table.create(#gridPath)
	for i=1,#gridPath do out[i] = gridToWorld(plot, gridPath[i]) end
	return out
end

local function spawnCarAlongPath(player, ctx, gridPath, worldPath, variantLabel)
	if ctx.suspended then return end
	if not worldPath or #worldPath < 2 then return end
	if not trySpend(ctx, 1.0) then return end

	local live = 0 for _ in pairs(ctx.cars) do live += 1 end
	if live >= MAX_CONCURRENT_PER_PLAYER then return end

	local template, chosenVariant = pickTemplateForPlayer(player)
	if not template then return end
	variantLabel = variantLabel or chosenVariant or "Default"

	local car = template:Clone()
	car.Name = ("Traffic_P%s_%s_%d"):format(player.UserId, variantLabel, math.random(1,999999))
	car.PrimaryPart = car.PrimaryPart or car:FindFirstChildWhichIsA("BasePart")
	car:SetAttribute("IsTraffic", true)
	car:SetAttribute("TrafficOwner", player.UserId)
	car:SetAttribute("TrafficVariant", variantLabel)
	car.Parent = ctx.plot
	car:SetPrimaryPartCFrame(CFrame.new(worldPath[1]))

	ctx.cars[car] = true
	Debris:AddItem(car, CAR_LIFETIME_SEC)

	local preStopIndices, preStopKeys = computePreIntersectionStops(gridPath)
	local edgeKeyByIndex = buildEdgeKeysForPath(gridPath)

	local opts = {
		preStopIndices   = preStopIndices,
		preStopKeysByIdx = preStopKeys,
		edgeKeyByIndex   = edgeKeyByIndex,
		stopSeconds      = ALL_WAY_STOP_SEC + math.random() * STOP_JITTER_SEC,
		minEdgeHeadwaySec = 0.25,
	}

	local pathId = newPathId(player.UserId)
	CarMovement.moveCarAlongPath(car, worldPath, opts, function(arrived)
		ctx.cars[car] = nil
		fadeOutAndDestroy(arrived, FADE_OUT_TIME)
	end, pathId)
	return car
end

local function spawnOnceOriginToSinksMode(player, ctx)
	if ctx.suspended then return end
	if not originLiveForPlayer(player) then return end
	if not ctx.sinks or #ctx.sinks == 0 then return end

	local sink = ctx.sinks[math.random(1, #ctx.sinks)]
	local gridPath = bfsPathOwned(player, SOURCE_COORD, sink)
	if (not gridPath or #gridPath < MIN_PATH_CELLS) and #ctx.sinks > 1 then
		sink = ctx.sinks[math.random(1, #ctx.sinks)]
		gridPath = bfsPathOwned(player, SOURCE_COORD, sink)
	end
	if not gridPath or #gridPath < MIN_PATH_CELLS then return end

	local worldPath = worldPathFor(ctx.plot, gridPath)
	spawnCarAlongPath(player, ctx, gridPath, worldPath, nil)

	if not TWO_WAY_ENABLED then return end
	if TWO_WAY_MODE == "chance" and math.random() >= TWO_WAY_CHANCE then return end

	local revGrid = reversedGridPath(gridPath)
	if not revGrid or #revGrid < MIN_PATH_CELLS then return end
	local revWorld = worldPathFor(ctx.plot, revGrid)
	local revCar = spawnCarAlongPath(player, ctx, revGrid, revWorld, nil)
	if revCar then revCar:SetAttribute("DriveSession", true) end -- harmless tag
end

local function spawnOnceZoneToOriginMode(player, ctx)
	if ctx.suspended then return end
	if not originLiveForPlayer(player) then return end
	if not ctx.zoneSources or #ctx.zoneSources == 0 then return end

	local sourceCoord = ctx.zoneSources[math.random(1, #ctx.zoneSources)]
	local gridPath = bfsPathOwned(player, sourceCoord, SOURCE_COORD)
	if (not gridPath or #gridPath < MIN_PATH_CELLS) and #ctx.zoneSources > 1 then
		sourceCoord = ctx.zoneSources[math.random(1, #ctx.zoneSources)]
		gridPath = bfsPathOwned(player, sourceCoord, SOURCE_COORD)
	end
	if not gridPath or #gridPath < MIN_PATH_CELLS then return end

	local worldPath = worldPathFor(ctx.plot, gridPath)
	spawnCarAlongPath(player, ctx, gridPath, worldPath, nil)

	if DISPATCH_MODE ~= "ZoneToOriginAndBack" then return end
	local revGrid = reversedGridPath(gridPath)
	if not revGrid or #revGrid < MIN_PATH_CELLS then return end
	local revWorld = worldPathFor(ctx.plot, revGrid)
	local revCar = spawnCarAlongPath(player, ctx, revGrid, revWorld, nil)
	if revCar then revCar:SetAttribute("DriveSession", true) end -- harmless tag
end

local function spawnOnce(player, ctx)
	if DISPATCH_MODE == "OriginToSinks" then
		return spawnOnceOriginToSinksMode(player, ctx)
	else
		return spawnOnceZoneToOriginMode(player, ctx)
	end
end

local function killAllTraffic(ctx)
	for car,_ in pairs(ctx.cars) do
		if car and car.Parent then fadeOutAndDestroy(car, 0.5) end
	end
	ctx.cars = {}
end

local function hardKillTrafficInPlot(plot)
	if not plot then return end
	for _, inst in ipairs(plot:GetDescendants()) do
		if (inst:IsA("Model") or inst:IsA("Folder")) and inst:GetAttribute("IsTraffic") == true then
			pcall(function() inst:Destroy() end)
		end
	end
end

--=== FARTEST-POINT FROM ORIGIN HELPERS =================================
local function computeFarthestOwnedPathFromOrigin(player)
	if not originLiveForPlayer(player) then return nil end
	local candidates = PathingModule.getOwnedDeadEnds(player)
	if #candidates == 0 then
		candidates = {}
		for _, node in ipairs(PathingModule.iterAllRoadCoords()) do
			if nodeOwnedByPlayer(player, node.key) then
				table.insert(candidates, { x = node.x, z = node.z })
			end
		end
	end
	local bestPath, bestLen = nil, -1
	for _, coord in ipairs(candidates) do
		local p = bfsPathOwned(player, SOURCE_COORD, coord)
		if p and #p > bestLen then
			bestPath, bestLen = p, #p
		end
	end
	if bestPath and #bestPath >= MIN_PATH_CELLS then
		return bestPath
	end
	return nil
end

local function spawnOnce_OriginToFarthest(player, ctx)
	if ctx.suspended then return end
	if not originLiveForPlayer(player) then return end
	local gridPath = computeFarthestOwnedPathFromOrigin(player)
	if not gridPath then return end
	local worldPath = worldPathFor(ctx.plot, gridPath)
	local car = spawnCarAlongPath(player, ctx, gridPath, worldPath, "Farthest")
	if car then car:SetAttribute("DriveSession", true) end
	if TWO_WAY_ENABLED then
		if TWO_WAY_MODE == "mirror" or (TWO_WAY_MODE == "chance" and math.random() < TWO_WAY_CHANCE) then
			local revGrid = reversedGridPath(gridPath)
			if revGrid and #revGrid >= MIN_PATH_CELLS then
				local revWorld = worldPathFor(ctx.plot, revGrid)
				local revCar = spawnCarAlongPath(player, ctx, revGrid, revWorld, "Farthest")
				if revCar then revCar:SetAttribute("DriveSession", true) end
			end
		end
	end
end

--======================================================================
--  RECOMPUTE / SCHEDULER
--======================================================================
local recomputeQueued = {} -- [uid] = true

local function ensureCtx(player)
	local uid = player.UserId
	local ctx = ctxByUserId[uid]
	if not ctx then
		ctx = {
			plot = getPlotForUserId(uid),
			suspended = false,
			tokens = TOKEN_BUCKET_MAX * 0.5,
			last = os.clock(),
			cars = {},
			sinks = {},
			zoneSources = {},
			nextSpawnAt = os.clock() + math.random() * RANDOM_JITTER_SEC,

			-- [DRIVE MODE] per-player session
			drive = nil, -- { active=bool, loopTask=thread, startPos=Vector3, firstAttach=bool }
		}
		ctxByUserId[uid] = ctx
	end
	-- keep a reference to player (for camera reset on stop)
	ctx.player = player
	if not ctx.plot or ctx.plot.Parent == nil then
		ctx.plot = getPlotForUserId(uid)
	end
	return ctx
end

local function recomputeForPlayer(player)
	local ctx = ensureCtx(player)
	if ctx.suspended then return end
	refreshOwnRoadZones(player, ctx)

	if originLiveForPlayer(player) then
		if DISPATCH_MODE == "OriginToSinks" then
			ctx.sinks = computeSinksForPlayer(player)
			ctx.zoneSources = {}
			dprint(("Player %s sinks=%d (origin->sinks mode)"):format(player.Name, #ctx.sinks))
		else
			ctx.zoneSources = computeZoneSourcesForPlayer(player)
			ctx.sinks = {}
			dprint(("Player %s zoneSources=%d (zone->origin mode)"):format(player.Name, #ctx.zoneSources))
		end
	else
		ctx.sinks = {}
		ctx.zoneSources = {}
	end
end

local function scheduleRecompute(player, delaySec)
	local uid = player.UserId
	if recomputeQueued[uid] then return end
	recomputeQueued[uid] = true
	task.delay(delaySec or RECOMPUTE_DEBOUNCE, function()
		recomputeQueued[uid] = nil
		pcall(function() recomputeForPlayer(player) end)
	end)
end

local function ensureSpawnLoop(player)
	local uid = player.UserId
	local ctx = ensureCtx(player)
	if ctx.spawnLoop then return end
	ctx.spawnLoop = task.spawn(function()
		while Players:GetPlayerByUserId(uid) do
			if not ctx.suspended and os.clock() >= (ctx.nextSpawnAt or 0) then
				pcall(function() spawnOnce(player, ctx) end)
				ctx.nextSpawnAt = os.clock() + SPAWN_INTERVAL_SEC + math.random() * RANDOM_JITTER_SEC
			end
			task.wait(0.2)
		end
	end)
end

--========================
-- [DRIVE MODE] helpers
--========================
local function getHRP(player)
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart")
end

local function movedTooMuch(player, ctx)
	if not ctx.drive or not ctx.drive.startPos then return false end
	local hrp = getHRP(player)
	if not hrp then return false end
	-- 2D distance (XZ) + linear speed check
	local a = Vector2.new(hrp.Position.X, hrp.Position.Z)
	local b = Vector2.new(ctx.drive.startPos.X, ctx.drive.startPos.Z)
	local dist = (a - b).Magnitude
	local speed = hrp.AssemblyLinearVelocity.Magnitude
	return (dist >= DRIVE_MOVE_DIST_STOP) or (speed >= DRIVE_MOVE_SPEED_STOP)
end

local function stopDriveMode(ctx)
	if not ctx or not ctx.drive then return end
	ctx.drive.active = false
	if ctx.drive.loopTask then
		task.cancel(ctx.drive.loopTask)
	end
	ctx.drive.loopTask = nil

	-- destroy cars spawned by drive mode
	if ctx.plot then
		for _, inst in ipairs(ctx.plot:GetDescendants()) do
			if inst:IsA("Model")
				and inst:GetAttribute("IsTraffic")
				and inst:GetAttribute("DriveSession")
			then
				pcall(function() inst:Destroy() end)
			end
		end
	end

	-- reset client camera immediately using existing event (send nil)
	if CameraAttachEvt and ctx.player then
		CameraAttachEvt:FireClient(ctx.player, nil)
	end

	-- >>> ADD THESE THREE LINES RIGHT HERE <<<
	ctx.drive.lockForward = nil
	ctx.drive.lockReverse = nil
	ctx.drive.lockTarget  = nil
end

local function startDriveMode(player, ctx)
	ctx.drive = ctx.drive or {}
	ctx.drive.active = true
	local hrp = getHRP(player)
	ctx.drive.startPos = hrp and hrp.Position or nil
	ctx.drive.firstAttach = true

	if ctx.drive.loopTask then
		task.cancel(ctx.drive.loopTask)
	end

	ctx.drive.loopTask = task.spawn(function()
		while ctx.drive.active and Players:GetPlayerByUserId(player.UserId) do
			pcall(function() recomputeForPlayer(player) end)

			if not originLiveForPlayer(player) then
				task.wait(1.0)
			else
				-- Decide which forward path to use this trip
				local forwardPath, reversePath

				-- 1) Reuse previously locked route if still valid
				if ctx.drive.lockForward and pathIsValid(player, ctx.drive.lockForward) then
					forwardPath = ctx.drive.lockForward
					reversePath = ctx.drive.lockReverse  -- reverse we cached earlier
				else
					-- 2) Try to rebuild to the same endpoint if we had one
					if ctx.drive.lockTarget then
						local rebuilt = bfsToTarget(player, ctx.drive.lockTarget)
						if rebuilt and #rebuilt >= MIN_PATH_CELLS then
							forwardPath = rebuilt
						end
					end
					-- 3) Otherwise (or rebuild failed), pick a fresh farthest and lock it
					if not forwardPath then
						forwardPath = computeFarthestOwnedPathFromOrigin(player)
						if forwardPath and #forwardPath >= MIN_PATH_CELLS then
							-- Lock this target for the rest of the session
							ctx.drive.lockTarget = forwardPath[#forwardPath]  -- last coord
						end
					end

					-- Cache forward & reverse for future trips (if found)
					if forwardPath then
						ctx.drive.lockForward = forwardPath
						local rev = reversedGridPath(forwardPath)
						ctx.drive.lockReverse = (rev and #rev >= MIN_PATH_CELLS) and rev or nil
					end
				end

				-- If we still failed to get a path, wait & retry
				if not forwardPath or #forwardPath < MIN_PATH_CELLS then
					task.wait(1.0)
				else
					local worldPath = worldPathFor(ctx.plot, forwardPath)
					local car = spawnCarAlongPath(player, ctx, forwardPath, worldPath, "Farthest")
					if car then car:SetAttribute("DriveSession", true) end

					-- Always attach on forward legs while active
					if ctx.drive.active and car and car.Parent and CameraAttachEvt then
						CameraAttachEvt:FireClient(player, car)
					end

					-- Mirror leg uses the locked reverse (when we have it)
					if TWO_WAY_ENABLED and ctx.drive.lockReverse then
						if TWO_WAY_MODE == "mirror" or (TWO_WAY_MODE == "chance" and math.random() < TWO_WAY_CHANCE) then
							local revWorld = worldPathFor(ctx.plot, ctx.drive.lockReverse)
							local revCar = spawnCarAlongPath(player, ctx, ctx.drive.lockReverse, revWorld, "Farthest")
							if revCar then revCar:SetAttribute("DriveSession", true) end
						end
					end

					-- Wait for forward car to finish / cancel conditions
					local t0 = os.clock()
					while ctx.drive.active and car and car.Parent and (os.clock() - t0) < CAR_LIFETIME_SEC do
						if movedTooMuch(player, ctx) then
							ctx.drive.active = false
							if CameraAttachEvt and ctx.player then
								CameraAttachEvt:FireClient(ctx.player, nil)
							end
							break
						end
						task.wait(0.2)
					end

					-- Small pacing
					local untilT = os.clock() + DRIVE_RESPAWN_DELAY
					while ctx.drive.active and os.clock() < untilT do
						if movedTooMuch(player, ctx) then
							ctx.drive.active = false
							if CameraAttachEvt and ctx.player then
								CameraAttachEvt:FireClient(ctx.player, nil)
							end
							break
						end
						task.wait(0.05)
					end
				end
			end
		end
	end)
end

-- Suspend/unsuspend during save reloads
local function suspendPlayerTraffic(player)
	local ctx = ensureCtx(player)
	ctx.suspended = true
	killAllTraffic(ctx)
	hardKillTrafficInPlot(ctx.plot)
	-- [DRIVE MODE] pause/stop on suspend
	stopDriveMode(ctx)
end
local function unsuspendPlayerTraffic(player)
	local ctx = ensureCtx(player)
	ctx.suspended = false
	scheduleRecompute(player, 0.05)
end

--======================================================================
--  EVENT WIRING
--======================================================================
-- Feature flags
FireSupportEvt.Event:Connect(function(player)
	fireSupport[player.UserId] = true
	print(("[UnifiedTraffic] Fire support ENABLED for %s."):format(player.Name))
end)
BusSupportUnlocked.Event:Connect(function(player)
	busSupport[player.UserId] = true
	print(("[UnifiedTraffic] Bus support ENABLED for %s."):format(player.Name))
	if #templates.bus == 0 and not _busWarnedMissing then
		warn("[UnifiedTraffic] Bus support enabled but no bus models found under Cars.Buses/Busses.")
		_busWarnedMissing = true
	end
end)
BusSupportRevoked.Event:Connect(function(player)
	busSupport[player.UserId] = nil
	print(("[UnifiedTraffic] Bus support DISABLED for %s."):format(player.Name))
end)

-- [DRIVE MODE] Toggle on the same event:
--   1st click -> enable loop (attach camera on first leg)
--   2nd click -> disable loop (kill drive cars + reset camera)
SpawnCarToFarthestEvt.OnServerEvent:Connect(function(player)
	local ctx = ensureCtx(player)

	-- If not active, turn ON and start loop, attach camera on first leg
	if not ctx.drive or not ctx.drive.active then
		startDriveMode(player, ctx)
		print(("[UnifiedTraffic] DriveMode ENABLED for %s"):format(player.Name))
		return
	end

	-- If already active, turn OFF (hard stop)
	stopDriveMode(ctx)
	print(("[UnifiedTraffic] DriveMode DISABLED for %s"):format(player.Name))
end)

-- Zone graph changes → recompute
local function onZoneAdded(player, zoneId, zoneData)           scheduleRecompute(player, RECOMPUTE_DEBOUNCE) end
local function onZoneRemoved(player, zoneId, mode, gridList)   scheduleRecompute(player, RECOMPUTE_DEBOUNCE) end
local function onZoneReCreated(player, zoneId, mode, gridList) scheduleRecompute(player, RECOMPUTE_DEBOUNCE) end
local function onZonePopulated(player, zoneId, _)              scheduleRecompute(player, RECOMPUTE_DEBOUNCE) end

ZoneAddedEvt.Event:Connect(onZoneAdded)
ZoneRemovedEvt.Event:Connect(onZoneRemoved)
ZoneReCreatedEvt.Event:Connect(onZoneReCreated)
ZonePopulatedEvt.Event:Connect(onZonePopulated)

-- Save reload gates
if RequestReloadFromCurrentEvt then
	RequestReloadFromCurrentEvt.Event:Connect(function(player) suspendPlayerTraffic(player) end)
end
local function attachNetworksPostLoad(ev)
	if ev and ev.IsA and ev:IsA("BindableEvent") then
		ev.Event:Connect(function(player) unsuspendPlayerTraffic(player) end)
	end
end
attachNetworksPostLoad(NetworksPostLoadEvt)
BindableEvents.ChildAdded:Connect(function(ch)
	if ch.Name == "NetworksPostLoad" and ch:IsA("BindableEvent") then
		attachNetworksPostLoad(ch)
	end
end)

-- Player lifecycle
Players.PlayerAdded:Connect(function(plr)
	local ctx = ensureCtx(plr)
	scheduleRecompute(plr, 0.25)
	ensureSpawnLoop(plr)
end)
Players.PlayerRemoving:Connect(function(plr)
	local uid = plr.UserId
	local ctx = ctxByUserId[uid]
	if ctx then
		ctx.suspended = true
		killAllTraffic(ctx)
		stopDriveMode(ctx) -- [DRIVE MODE] cleanup
		ctxByUserId[uid] = nil
	end
	fireSupport[uid] = nil
	busSupport[uid]  = nil
end)

for _, p in ipairs(Players:GetPlayers()) do
	local ctx = ensureCtx(p)
	scheduleRecompute(p, 0.25)
	ensureSpawnLoop(p)
end

task.spawn(function()
	while true do
		task.wait(RESCAN_PERIODIC_SEC)
		for _, p in ipairs(Players:GetPlayers()) do
			scheduleRecompute(p, 0)
		end
	end
end)

print(("[UnifiedTraffic] online – DispatchMode=%s; origin=(%d,%d) – Bus/Fire variants where supported")
	:format(DISPATCH_MODE, SOURCE_COORD.x, SOURCE_COORD.z))
