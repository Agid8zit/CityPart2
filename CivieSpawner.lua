-- CivilianSpawner.server.lua (Iteration 3.0 – origin-edge spawn + destination-edge despawn; furthest-edge outward push + zone-type exceptions; readiness-decoupled activation, ready-await topups, folder-level lifecycle, queued despawn, TTL jitter)

local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")
local RunService        = game:GetService("RunService")

local GridConfig        = require(ReplicatedStorage.Scripts.Grid.GridConfig)
local GridUtil          = require(ReplicatedStorage.Scripts.Grid.GridUtil)
local CivPathing        = require(script.Parent.CiviePath)        -- (keep name; ensure filename matches)
local ZoneTrackerModule = require(game.ServerScriptService.Build.Zones.ZoneManager.ZoneTracker)
local CivilianMovement  = require(script.Parent.CivieMovement)

-- Events
local BindableEvents       = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents")
local ZoneAddedEvent       = BindableEvents:WaitForChild("ZoneAdded")
local ZoneRemovedEvent     = BindableEvents:WaitForChild("ZoneRemoved")
local ZonePopulatedEvent   = BindableEvents:FindFirstChild("ZonePopulated") or Instance.new("BindableEvent", BindableEvents)
ZonePopulatedEvent.Name    = "ZonePopulated"
local ZoneRecreatedEvent   = BindableEvents:FindFirstChild("ZoneRecreated")

local stopEvt = BindableEvents:FindFirstChild("StopCivilianRoutes") or Instance.new("BindableEvent", BindableEvents)
stopEvt.Name = "StopCivilianRoutes"
local FreezeAllEvt = BindableEvents:FindFirstChild("FreezeAllCivilianMovement") or Instance.new("BindableEvent", BindableEvents)
FreezeAllEvt.Name  = "FreezeAllCivilianMovement"

local ForceCivTest = BindableEvents:FindFirstChild("ForceCivTest") or Instance.new("BindableEvent", BindableEvents)
ForceCivTest.Name  = "ForceCivTest"

local CiviliansFolder   = ReplicatedStorage:WaitForChild("FuncTestGroundRS"):WaitForChild("Civilians")

local CFG = {
	-- populations
	MaxAlivePerZone      = 1,
	TargetMin            = 1,
	TargetMax            = 1,
	ZoneTypesEligible    = { Residential=true, ResDense=true, Commercial=true, CommDense=true, Industrial=true, IndusDense=true },

	-- lifetime & pacing
	LifeSeconds          = 240,
	TTLJitterSeconds     = 60,     -- +/- this amount to smear expiries
	InitialYLift         = 1.5,
	Debug                = false,

	-- pathing
	MinZonePathCells     = 6,      -- require at least this many grid steps for inter-zone route
	GridStrideCells      = 3,      -- only used in Manhattan fallback
	DestinationStrategy  = "nearest",

	-- despawn queue budget (tune to your server perf)
	MaxUnparentPerStep   = 40,     -- how many instances to Parent=nil per Heartbeat
	MaxDestroyPerStep    = 20,     -- how many to Destroy() per Stepped
	DebugFreezeAll       = false,

	-- spawn placement (origin)
	SpawnOnEdgeOutside   = true,   -- spawn outside the origin zone
	EdgePreferPathAlign  = true,   -- bias edge (origin) toward path’s first segment direction (tie-break)
	EdgePushMaxSteps     = 128,    -- how far we’ll keep pushing outward through disallowed zones (spawn & despawn use this)
	-- Whitelist of zone modes we are allowed to spawn/despawn on (do NOT push past these).
	-- If you want the inverse behavior (never land on these), set this table to {}.
	EdgeAllowedZoneModes = { DirtRoad=true, WaterPipe=true, PowerLines=true, MetroTunnel=true },

	-- despawn placement (destination)
	DespawnAtTargetEdge      = true,  -- NEW: clip final waypoint to the border outside the destination zone
	DespawnEdgePreferAlign   = true,  -- NEW: bias dest-edge pick toward final approach vector
}

local function dprint(...) if CFG.Debug then print("[CivilianSpawner]", ...) end end
local function dwarn (...) if CFG.Debug then warn ("[CivilianSpawner]", ...) end end

-- =========================================================
-- Bounds & grid helpers
-- =========================================================
local boundsCache = {}
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

local function gridToWorld(coord, plot)
	local bounds, terrains = getGlobalBoundsForPlot(plot)
	if not bounds then
		local tt = plot and plot:FindFirstChild("TestTerrain")
		local minX, minZ = GridConfig.calculateCoords(tt)
		local wx, wz     = GridUtil.gridToWorldPosition(coord.x, coord.z, minX, minZ)
		return Vector3.new(wx, 0, wz)
	end
	local wx, _, wz = GridUtil.globalGridToWorldPosition(coord.x, coord.z, bounds, terrains)
	return Vector3.new(wx, 0, wz)
end

local function gridPathToWorld(path, plot)
	local out = table.create(#path)
	for i = 1, #path do out[i] = gridToWorld(path[i], plot) end
	return out
end

-- Simple Manhattan (fallback) with stride compression
local function buildManhattanGridPath(a, b)
	local path = {}
	local x, z = a.x, a.z
	path[#path+1] = {x=x, z=z}
	while x ~= b.x do x += (b.x > x) and 1 or -1; path[#path+1] = {x=x, z=z} end
	while z ~= b.z do z += (b.z > z) and 1 or -1; path[#path+1] = {x=x, z=z} end
	if #path <= 2 then return path end

	local kept = { path[1] }
	local function axis(p, q) return (p.x ~= q.x) and "x" or "z" end
	local curAxis = axis(path[1], path[2])

	for i = 2, #path - 1 do
		local a1, a2 = path[i-1], path[i]
		local nextAxis = axis(a1, a2)
		if nextAxis ~= curAxis then
			kept[#kept+1] = a2
			curAxis = nextAxis
		else
			if (i % CFG.GridStrideCells) == 0 then
				kept[#kept+1] = a2
			end
		end
	end

	kept[#kept+1] = path[#path]
	return kept
end

-- readiness gating
local function isZoneReady(player, zoneId)
	local z = ZoneTrackerModule.getZoneById(player, zoneId)
	if not z then return false end
	if not CFG.ZoneTypesEligible[z.mode] then return false end
	if ZoneTrackerModule.isZonePopulating and ZoneTrackerModule.isZonePopulating(player, zoneId) then
		return false
	end
	return true
end

-- Intra-zone wander (world positions)
local function buildZoneWanderWorldPath(plot, zone, hops)
	hops = math.clamp(hops or 4, 2, 8)
	if not zone.gridList or #zone.gridList < 2 then return nil end
	local indices = table.create(#zone.gridList)
	for i = 1, #zone.gridList do indices[i] = i end
	for i = 1, math.min(hops, #indices) do
		local j = math.random(i, #indices)
		indices[i], indices[j] = indices[j], indices[i]
	end
	local world = {}
	for i = 1, math.min(hops, #indices) do
		local c = zone.gridList[indices[i]]
		world[#world+1] = gridToWorld(c, plot)
	end
	return world
end

-- =========================================================
-- Edge-of-zone spawn/despawn helpers
-- =========================================================
local function cellKey(x, z) return tostring(x) .. "," .. tostring(z) end

local function buildCellSet(list)
	local set = {}
	if list then
		for _, c in ipairs(list) do
			set[cellKey(c.x, c.z)] = true
		end
	end
	return set
end

-- Map every non-origin zone cell -> { id=zoneId, mode=zoneMode }
local function buildAllZonesCellMapExcept(player, exceptZoneId)
	local zones = ZoneTrackerModule.getAllZones(player)
	local map = {}
	if zones then
		for zId, z in pairs(zones) do
			if zId ~= exceptZoneId and z and z.gridList then
				for _, c in ipairs(z.gridList) do
					map[cellKey(c.x, c.z)] = { id = zId, mode = z.mode }
				end
			end
		end
	end
	return map
end

local neighbors4 = { {1,0}, {-1,0}, {0,1}, {0,-1} }

-- Collect every *outside neighbor* around the zone boundary (even if it belongs to another zone).
local function collectOutsideEdgeCandidates(plot, zone)
	if not zone or not zone.gridList or #zone.gridList == 0 then return {} end

	local inSet      = buildCellSet(zone.gridList)
	local candidates = {}
	local seen       = {}

	local function mkWorld(x, z)
		return gridToWorld({ x = x, z = z }, plot)
	end

	for _, c in ipairs(zone.gridList) do
		for _, d in ipairs(neighbors4) do
			local nx, nz = c.x + d[1], c.z + d[2]
			if not inSet[cellKey(nx, nz)] then
				-- Dedup by starting cell + outward direction
				local key = cellKey(nx, nz) .. "|" .. tostring(d[1]) .. "," .. tostring(d[2])
				if not seen[key] then
					seen[key] = true
					local pFrom = mkWorld(c.x, c.z)
					local pTo   = mkWorld(nx, nz)
					local dir   = pTo - pFrom
					local dirU  = (dir.Magnitude > 1e-6) and dir.Unit or Vector3.new(d[1], 0, d[2])
					candidates[#candidates+1] = {
						start   = { x = nx, z = nz },       -- outside neighbor cell
						from    = { x = c.x, z = c.z },     -- boundary cell inside zone
						dirGrid = { dx = d[1], dz = d[2] }, -- outward push direction (away from zone)
						dirWorld= dirU,
					}
				end
			end
		end
	end

	return candidates
end

local function isCellAllowedSpawn(x, z, zonesMap, allowedModes)
	local ent = zonesMap[cellKey(x, z)]
	if not ent then return true end                     -- empty cell => allowed
	if allowedModes and allowedModes[ent.mode] then
		return true                                     -- whitelisted zone => allowed
	end
	return false                                        -- belongs to a disallowed zone
end

-- Push outward from a starting neighbor cell until we hit an allowed cell (empty or whitelisted zone),
-- or until we exhaust the step budget.
local function pushOutwardToAllowedOrEmpty(startX, startZ, dx, dz, zonesMap, allowedModes, maxSteps)
	local x, z   = startX, startZ
	local steps  = 0
	while (not isCellAllowedSpawn(x, z, zonesMap, allowedModes)) and steps < maxSteps do
		x += dx; z += dz; steps += 1
	end
	if isCellAllowedSpawn(x, z, zonesMap, allowedModes) then
		return { x = x, z = z }, steps
	end
	return nil, steps
end

-- Origin-side pick: spawn at furthest-most edge outside the origin zone (existing behavior)
local function pickEdgeSpawnOutside(plot, player, zone, zoneId, wpath)
	local zonesMap = buildAllZonesCellMapExcept(player, zoneId)
	local cands    = collectOutsideEdgeCandidates(plot, zone)
	if #cands == 0 then return nil end

	local segDir = nil
	if wpath and wpath[2] then
		local dv = wpath[2] - wpath[1]
		if dv.Magnitude > 1e-6 then segDir = dv.Unit end
	end

	local bestWorld, bestSteps, bestAlign = nil, -1, -1e9
	for _, c in ipairs(cands) do
		local endCell, steps = pushOutwardToAllowedOrEmpty(
			c.start.x, c.start.z,
			c.dirGrid.dx, c.dirGrid.dz,
			zonesMap, CFG.EdgeAllowedZoneModes, CFG.EdgePushMaxSteps
		)
		if endCell then
			local w = gridToWorld(endCell, plot)
			local align = 0
			if segDir and CFG.EdgePreferPathAlign then
				align = segDir:Dot(c.dirWorld) -- higher (closer to 1) is better
			end
			if (steps > bestSteps) or (steps == bestSteps and align > bestAlign) then
				bestWorld, bestSteps, bestAlign = w, steps, align
			end
		end
	end
	return bestWorld
end

-- Destination-side pick: clip final waypoint to the border outside the destination zone.
-- We choose the candidate best aligned with the final approach vector; if that outside neighbor is inside a
-- disallowed zone, we push outward until empty/whitelisted.
local function pickEdgeDespawnOutside(plot, player, destZone, destZoneId, wpath)
	local zonesMap = buildAllZonesCellMapExcept(player, destZoneId)
	local cands    = collectOutsideEdgeCandidates(plot, destZone)
	if #cands == 0 then return nil end
	if not (wpath and #wpath >= 2) then return nil end

	local prev = wpath[#wpath-1]
	local last = wpath[#wpath]
	local approachDir = last - prev
	if approachDir.Magnitude <= 1e-6 then return nil end
	approachDir = approachDir.Unit

	local bestWorld, bestAlign, bestDist = nil, -1e9, 1e12
	for _, c in ipairs(cands) do
		-- outward from dest zone (away from its interior)
		local endCell, _ = pushOutwardToAllowedOrEmpty(
			c.start.x, c.start.z,
			c.dirGrid.dx, c.dirGrid.dz,
			zonesMap, CFG.EdgeAllowedZoneModes, CFG.EdgePushMaxSteps
		)
		if endCell then
			local w = gridToWorld(endCell, plot)
			local dirFromPrev = w - prev
			local align = 0
			if dirFromPrev.Magnitude > 1e-6 then
				align = approachDir:Dot(dirFromPrev.Unit) -- higher is better (heading where the path already points)
			end
			local dist = (w - last).Magnitude
			-- Prefer alignment; if tie, pick the closer endpoint
			local better = (CFG.DespawnEdgePreferAlign and (align > bestAlign + 1e-6))
				or (math.abs(align - bestAlign) <= 1e-6 and dist < bestDist)
			if better then
				bestWorld, bestAlign, bestDist = w, align, dist
			end
		end
	end
	return bestWorld
end

-- =========================================================
-- Steady-state accounting + registry
-- =========================================================
local alivePerZone     = {}   -- zoneId -> current alive
local targetPerZone    = {}   -- zoneId -> desired steady-state
local zoneActive       = {}   -- zoneId -> bool
local zoneOwner        = {}   -- zoneId -> Player (for deferred maintain)
local civByZone        = {}   -- zoneId -> { [Model]=true }
local civFolderByZone  = {}   -- zoneId -> Folder
local folderWatcher    = {}   -- zoneId -> RBXScriptConnection

local function getTargetFor(zoneId)
	local t = targetPerZone[zoneId]
	if not t then
		t = math.random(math.min(CFG.TargetMin, CFG.TargetMax), math.max(CFG.TargetMin, CFG.TargetMax))
		targetPerZone[zoneId] = math.clamp(t, 0, CFG.MaxAlivePerZone)
	end
	return targetPerZone[zoneId]
end

local function setActive(zoneId, v) zoneActive[zoneId] = v and true or nil end
local function incAlive(zoneId, n) alivePerZone[zoneId] = (alivePerZone[zoneId] or 0) + (n or 1) end
local function decAlive(zoneId, n) alivePerZone[zoneId] = math.max(0, (alivePerZone[zoneId] or 0) - (n or 1)) end
local function canSpawn(zoneId)     return (alivePerZone[zoneId] or 0) < CFG.MaxAlivePerZone end

local function registerCiv(zoneId, model)
	civByZone[zoneId] = civByZone[zoneId] or {}
	civByZone[zoneId][model] = true
end

local function unregisterCiv(zoneId, model)
	local bucket = civByZone[zoneId]
	if bucket and bucket[model] then
		bucket[model] = nil
		if next(bucket) == nil then civByZone[zoneId] = nil end
	end
end

-- =========================================================
-- Plot folder helpers
-- =========================================================
local function getPlayerPlot(player)
	return Workspace.PlayerPlots and Workspace.PlayerPlots:FindFirstChild("Plot_" .. player.UserId) or nil
end

local function getOrCreateCivRootFolder(plot)
	if not plot then return nil end
	local root = plot:FindFirstChild("Civilians")
	if not root then
		root = Instance.new("Folder")
		root.Name = "Civilians"
		root.Parent = plot
	end
	return root
end

local function getOrCreateZoneCivFolder(plot, zoneId)
	local root = getOrCreateCivRootFolder(plot)
	if not root then return nil end
	local zf = root:FindFirstChild(zoneId)
	if not zf then
		zf = Instance.new("Folder")
		zf.Name = tostring(zoneId)
		zf.Parent = root
	end
	return zf
end

-- Forward-declare so watcher & awaiter closures can reference it without going global
local maintainZoneSteadyState  -- FIX: explicit local forward declaration

-- folder-level watcher (replaces per-model AncestryChanged)
local function ensureZoneFolderWatcher(zoneId, folder)
	if folderWatcher[zoneId] then
		folderWatcher[zoneId]:Disconnect()
		folderWatcher[zoneId] = nil
	end
	if not folder then return end

	folderWatcher[zoneId] = folder.ChildRemoved:Connect(function(child)
		if not child or not child:IsA("Model") then return end

		-- FIX: drive accounting off registry membership (not the CivAlive attr),
		-- so we still decrement/top-up even if something pre-cleared the attribute.
		local bucket = civByZone[zoneId]
		if not (bucket and bucket[child]) then return end

		-- mark + account exactly once
		child:SetAttribute("CivAlive", false)
		decAlive(zoneId, 1)
		unregisterCiv(zoneId, child)
		dprint(("ChildRemoved: zone %s alive=%d"):format(zoneId, alivePerZone[zoneId] or 0))

		local owner = zoneOwner[zoneId]
		if owner and zoneActive[zoneId] then
			task.defer(function()
				if zoneActive[zoneId] and canSpawn(zoneId) then
					maintainZoneSteadyState(owner, zoneId)
				end
			end)
		end
	end)
end

-- =========================================================
-- Despawn queue (de-replicate now, destroy later) 
-- =========================================================
local unparentQueue = {}  -- instances to Parent=nil
local destroyQueue  = {}  -- instances to Destroy()

local function enqueueDelete(inst)
	if not inst then return end
	unparentQueue[#unparentQueue+1] = inst
end

RunService.Heartbeat:Connect(function()
	local budget = CFG.MaxUnparentPerStep
	while budget > 0 and #unparentQueue > 0 do
		local inst = table.remove(unparentQueue) -- pop end
		if inst then
			if inst.Parent then
				inst.Parent = nil
			end
			destroyQueue[#destroyQueue+1] = inst
		end
		budget -= 1
	end
end)

RunService.Stepped:Connect(function()
	local budget = CFG.MaxDestroyPerStep
	while budget > 0 and #destroyQueue > 0 do
		local inst = table.remove(destroyQueue)
		if inst then
			pcall(function() inst:Destroy() end)
		end
		budget -= 1
	end
end)

-- =========================================================
-- Ready-await helper
-- =========================================================
local readyAwaiters = {}  -- zoneId -> true while a waiter is running

local function scheduleReadyTopUp(player, zoneId, opts)
	-- FIX: schedule a gentle retry loop until the zone reports ready, then call maintain once.
	if readyAwaiters[zoneId] then return end
	readyAwaiters[zoneId] = true

	local sleep    = (opts and opts.sleep) or 0.5
	local maxTries = (opts and opts.maxTries) or 300  -- ~150s by default

	task.spawn(function()
		local tries = 0
		while zoneActive[zoneId] and not isZoneReady(player, zoneId) and tries < maxTries do
			tries += 1
			task.wait(sleep)
		end
		if zoneActive[zoneId] and isZoneReady(player, zoneId) then
			dprint(("[Ready] zone %s became ready after %d tries; topping up"):format(zoneId, tries))
			maintainZoneSteadyState(player, zoneId)
		else
			dprint(("[Ready] zone %s waiter exit (active=%s, tries=%d)"):format(zoneId, tostring(zoneActive[zoneId]), tries))
		end
		readyAwaiters[zoneId] = nil
	end)
end

-- =========================================================
-- Forward decl
-- =========================================================
local spawnOneCivilianFlexible
maintainZoneSteadyState = function(player, zoneId)
	if not zoneActive[zoneId] then return end
	if not isZoneReady(player, zoneId) then return end
	local target  = getTargetFor(zoneId)
	local alive   = alivePerZone[zoneId] or 0
	local deficit = math.max(0, math.min(target, CFG.MaxAlivePerZone) - alive)
	if deficit <= 0 then return end
	dprint(("[Maintain] zone=%s target=%d alive=%d deficit=%d"):format(zoneId, target, alive, deficit))
	local ok, err = pcall(spawnOneCivilianFlexible, player, zoneId)
	if not ok then dwarn("maintain spawn error:", err) end
end

-- =========================================================
-- Spawner internals
-- =========================================================
local function pickCivilian()
	local kids = CiviliansFolder:GetChildren()
	if #kids == 0 then return nil end
	return kids[math.random(1, #kids)]
end

spawnOneCivilianFlexible = function(player, zoneId)
	if not zoneActive[zoneId] then return end
	if not isZoneReady(player, zoneId) then return end
	if not canSpawn(zoneId) then return end

	local zones = ZoneTrackerModule.getAllZones(player)
	local zone  = zones and zones[zoneId]
	if not zone then return end

	local plot = getPlayerPlot(player)
	if not plot then dwarn("No player plot for", player.Name) return end

	-- Ensure per-zone folder present + watched
	local zoneFolder = civFolderByZone[zoneId]
	if not (zoneFolder and zoneFolder.Parent) then
		zoneFolder = getOrCreateZoneCivFolder(plot, zoneId)
		civFolderByZone[zoneId] = zoneFolder
		ensureZoneFolderWatcher(zoneId, zoneFolder)
	end

	local wpath
	local destIdForAttr = nil

	-- Pick destination via CivPathing (nearest with jitter)
	local dest = CivPathing.pickDestinationZone(player, zone, CFG.DestinationStrategy)
	if dest and dest.dist >= CFG.MinZonePathCells then
		destIdForAttr = dest.id
		wpath = CivPathing.hybridZoneToZonePath(plot, player, zone, dest.data, {
			allowDiagonals = true,
			noCornerCut    = true,
			SearchRadius   = 128,
			excludeZoneIds = { [zoneId] = true, [dest.id] = true },
		})
	end

	-- fallbacks
	if (not wpath) or #wpath < 2 then
		local blocked = CivPathing.buildBlockedCellsFromZones(player, {
			excludeZoneIds     = { [zoneId]=true, [dest and dest.id or ""]=true },
			blockAllOtherZones = true,
		})
		local gpath = CivPathing.findGridPathAvoiding(
			dest and dest.a or zone.gridList[1],
			dest and dest.b or zone.gridList[1],
			{ blocked=blocked, allowDiagonals=true, noCornerCut=true }
		)
		if gpath and #gpath >= 2 then
			wpath = gridPathToWorld(gpath, plot)
		else
			wpath = buildZoneWanderWorldPath(plot, zone, 4)
			destIdForAttr = nil
		end
	end

	-- Guard: must have a path
	if (not wpath) or (#wpath < 2) then return end

	-- ===== ORIGIN: shift spawn to the *furthest-most* edge outside the origin zone, pushing past adjacent disallowed zones =====
	local spawnPos = wpath[1]
	if CFG.SpawnOnEdgeOutside then
		local edgePos = pickEdgeSpawnOutside(plot, player, zone, zoneId, wpath)
		if edgePos then
			spawnPos = edgePos
			if #wpath >= 2 then
				wpath[1] = edgePos
			else
				wpath = { edgePos, wpath[1] }
			end
		end
	end
	-- ========================================================================================================================

	-- ===== DESTINATION: clip last waypoint to the border outside the destination zone (never enter the zone) =====
	if CFG.DespawnAtTargetEdge and destIdForAttr then
		local destZone = zones and zones[destIdForAttr]
		if destZone then
			local edgeEnd = pickEdgeDespawnOutside(plot, player, destZone, destIdForAttr, wpath)
			if edgeEnd then
				wpath[#wpath] = edgeEnd
			end
		end
	end
	-- ========================================================================================================================

	-- Spawn + move
	local tpl = pickCivilian()
	if not tpl then
		dwarn("No civilian templates in ReplicatedStorage/FuncTestGroundRS/Civilians")
		return
	end

	local model = tpl:Clone()
	model.Name   = ("Civ_%s_%d"):format(zoneId, os.clock()*1000)
	model.Parent = zoneFolder
	-- smear expiries to avoid burst-destroy every N minutes
	local ttl = math.max(15, CFG.LifeSeconds + math.random(-CFG.TTLJitterSeconds, CFG.TTLJitterSeconds))
	Debris:AddItem(model, ttl)

	-- tag & place
	model:SetAttribute("CivAlive", true)
	model:SetAttribute("OwningZoneId", zoneId)
	model:SetAttribute("DestinationZoneId", destIdForAttr or "")
	model:SetAttribute("OwnerUserId", player.UserId)

	local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if hrp then
		model.PrimaryPart = hrp
		local p = spawnPos -- (may be edge-shifted far outward)
		hrp.CFrame = CFrame.new(p + Vector3.new(0, CFG.InitialYLift, 0))
	end

	incAlive(zoneId, 1)
	registerCiv(zoneId, model)

	if CFG.DebugFreezeAll then
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = 0 end
		return -- no movement; Debris will clean up
	end

	local speed = 5.0 + math.random() * 2.0  -- 5–7 studs/s
	dprint(("[Spawn] zone=%s ws=%.1f ttl=%d pathLen=%d dest=%s originEdge=%s destEdge=%s"):format(
		zoneId, speed, ttl, #wpath, tostring(destIdForAttr), tostring(CFG.SpawnOnEdgeOutside), tostring(CFG.DespawnAtTargetEdge)))
	CivilianMovement.moveAlongPath(model, wpath, zoneId, {
		WalkSpeed    = speed,
		DestroyAtEnd = false,   -- we will enqueue despawn ourselves
		OnComplete   = function()
			-- Do NOT flip CivAlive here. Folder watcher will mark & account on removal.
			enqueueDelete(model)
		end,
	})
end

local function seedTargetAndFill(player, zoneId)
	setActive(zoneId, true)
	getTargetFor(zoneId)
	alivePerZone[zoneId] = alivePerZone[zoneId] or 0
	maintainZoneSteadyState(player, zoneId)
	task.defer(maintainZoneSteadyState, player, zoneId)
end

-- =========================================================
-- Zone lifecycle wiring + hard cleanup
-- =========================================================
local function onZoneCreateOrRecreate(player, zoneId)
	-- Do NOT gate this on isZoneReady(); attach watchers and activate immediately.
	zoneOwner[zoneId] = player

	local plot = getPlayerPlot(player)
	if plot then
		local folder = getOrCreateZoneCivFolder(plot, zoneId)
		civFolderByZone[zoneId] = folder
		ensureZoneFolderWatcher(zoneId, folder)
	end

	seedTargetAndFill(player, zoneId)          -- best-effort immediate try
	scheduleReadyTopUp(player, zoneId)         -- retry until ready, then top-up
end

ZoneAddedEvent.Event:Connect(function(player, zoneId)
	local z = ZoneTrackerModule.getZoneById(player, zoneId)
	if not z or not CFG.ZoneTypesEligible[z.mode] then return end
	onZoneCreateOrRecreate(player, zoneId)
end)

if ZoneRecreatedEvent then
	ZoneRecreatedEvent.Event:Connect(function(player, zoneId)
		local z = ZoneTrackerModule.getZoneById(player, zoneId)
		if not z or not CFG.ZoneTypesEligible[z.mode] then return end
		onZoneCreateOrRecreate(player, zoneId)
	end)
end

-- Optional: kick a top-up right when build pipeline reports populated
if ZonePopulatedEvent then
	ZonePopulatedEvent.Event:Connect(function(player, zoneId)
		local owner = player or zoneOwner[zoneId]
		if not owner then return end
		-- ensure watcher exists (defensive)
		local plot = getPlayerPlot(owner)
		if plot then
			local folder = getOrCreateZoneCivFolder(plot, zoneId)
			civFolderByZone[zoneId] = folder
			ensureZoneFolderWatcher(zoneId, folder)
		end
		setActive(zoneId, true)
		getTargetFor(zoneId)
		alivePerZone[zoneId] = alivePerZone[zoneId] or 0
		maintainZoneSteadyState(owner, zoneId)
	end)
end

local function destroyAllCivsForZone(zoneId)
	-- fast path: unparent entire folder subtree; counters are reset below anyway
	local zFolder = civFolderByZone[zoneId]
	if zFolder then
		if zFolder.Parent then
			enqueueDelete(zFolder) -- de-replicate now, destroy paced
		end
	end
	civFolderByZone[zoneId] = nil

	-- clear registry (defensive)
	civByZone[zoneId] = nil
end

-- When *any* zone is removed, stop moves, prevent respawn, and hard-clean.
ZoneRemovedEvent.Event:Connect(function(player, removedZoneId, _mode, _gridList)
	CivilianMovement.stopMovesForKey(removedZoneId)
	setActive(removedZoneId, false)
	readyAwaiters[removedZoneId] = nil  -- cancel any waiters

	destroyAllCivsForZone(removedZoneId)

	-- destroy any civ currently headed *to* this zone (paced)
	for zoneId, bucket in pairs(civByZone) do
		for mdl in pairs(bucket) do
			if mdl and mdl.Parent and (mdl:GetAttribute("DestinationZoneId") == removedZoneId) then
				mdl:SetAttribute("CivAlive", false)
				enqueueDelete(mdl)
			end
		end
	end

	alivePerZone[removedZoneId]  = 0
	targetPerZone[removedZoneId] = nil
end)

-- Manual stop by zone id
stopEvt.Event:Connect(function(zoneId)
	CivilianMovement.stopMovesForKey(zoneId)
	setActive(zoneId, false)
	readyAwaiters[zoneId] = nil  -- cancel any waiters
	destroyAllCivsForZone(zoneId)
	alivePerZone[zoneId]  = 0
	targetPerZone[zoneId] = nil
end)

-- Force a test spawn against an eligible zone
ForceCivTest.Event:Connect(function(player, zoneId)
	if not ZoneTrackerModule.getZoneById(player, zoneId) then
		warn("[CivTest] unknown zone:", zoneId); return
	end
	zoneOwner[zoneId] = player
	setActive(zoneId, true)
	targetPerZone[zoneId] = math.clamp(getTargetFor(zoneId), 1, CFG.MaxAlivePerZone)
	maintainZoneSteadyState(player, zoneId)
	-- if not ready yet, await readiness then top-up
	if not isZoneReady(player, zoneId) then
		scheduleReadyTopUp(player, zoneId, { sleep = 0.25, maxTries = 240 })
	end
end)

print("CivilianSpawner: Iteration 3.0 online (origin-edge spawn + destination-edge despawn; furthest-edge outward push + zone-type exceptions; always-activate; ready-await topups; folder watchers; queued despawn; TTL jitter; 1 per zone; hybrid roads)")
