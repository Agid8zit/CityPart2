-- SaveManager.server.lua
-- Enhanced: progressive per-player phased load, per-server 1/3 wheel, early UI handoff,
-- flush-on-leave, BindToClose reliability, and safe world switching on slot change.

----------------------------------------------------------------
--  Init / Logging
----------------------------------------------------------------
local START_TIME = os.clock()
local Debug      = true
local function LOG(...)
	if Debug then
		print(("[SaveManager][+%.3fs] "):format(os.clock() - START_TIME), ...)
	end
end
LOG("==== INIT SaveManager script ====")

----------------------------------------------------------------
--  Core services
----------------------------------------------------------------
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local Workspace          = game:GetService("Workspace")
local HttpService        = game:GetService("HttpService")
local RunService         = game:GetService("RunService")

local EventsFolder    = ReplicatedStorage:WaitForChild("Events")
local BindableEvents  = EventsFolder:WaitForChild("BindableEvents")
local RemoteEvents    = EventsFolder:WaitForChild("RemoteEvents")

local ZoneCreated       = BindableEvents:WaitForChild("ZoneCreated")
local ZonePopulated     = BindableEvents:WaitForChild("ZonePopulated")
local ZoneReCreated     = BindableEvents:WaitForChild("ZoneReCreated")
local PlayerSaved       = BindableEvents:FindFirstChild("PlayerSaved")
local NetworksPostLoad0 = BindableEvents:FindFirstChild("NetworksPostLoad")

-- External (from UnlockManager.server.lua)
local GetUnlocksForPlayer = BindableEvents:WaitForChild("GetUnlocksForPlayer") -- BindableFunction

-- Local/internal safety helpers to ensure events exist
local function ensureBindableEvent(folder: Instance, name: string): BindableEvent
	local ev = folder:FindFirstChild(name)
	if not ev then
		ev = Instance.new("BindableEvent")
		ev.Name = name
		ev.Parent = folder
	end
	return ev :: BindableEvent
end

local function ensureFolder(parent: Instance, name: string): Instance
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

local function ensureRemoteEvent(eventsRoot: Instance, sub: string, name: string): RemoteEvent
	local folder = ensureFolder(eventsRoot, sub)
	local ev = folder:FindFirstChild(name)
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = folder
	end
	return ev :: RemoteEvent
end

-- Internal stage notifications to listeners (suspend/resume consumers)
-- (Added to avoid reusing RequestReloadFromCurrent which triggers reloads.)
local WorldReloadBeginBE = ensureBindableEvent(BindableEvents, "WorldReloadBegin")
local WorldReloadEndBE   = ensureBindableEvent(BindableEvents, "WorldReloadEnd")
----------------------------------------------------------------
--  Dependencies
----------------------------------------------------------------
local S3                  = game:GetService("ServerScriptService")
local PlayerDataService   = require(S3.Services.PlayerDataService)

local Bld                 = S3:WaitForChild("Build")
local Zones               = Bld:WaitForChild("Zones")
local ZoneMgr             = Zones:WaitForChild("ZoneManager")
local ZoneManager         = require(ZoneMgr:WaitForChild("ZoneManager"))
local ZoneTracker         = require(ZoneMgr:WaitForChild("ZoneTracker"))
local ZoneRequirementsCheck = require(ZoneMgr:WaitForChild("ZoneRequirementsCheck"))
local EconomyService      = require(ZoneMgr:WaitForChild("EconomyService"))
local CityInteractions    = require(ZoneMgr:WaitForChild("CityInteraction"))

local Transport           = Bld:WaitForChild("Transport")
local Roads               = Transport:WaitForChild("Roads")
local RoadsCore           = Roads:WaitForChild("CoreConcepts")

local Pathing             = RoadsCore:WaitForChild("Pathing")
local PathingModule       = require(Pathing:WaitForChild("PathingModule"))
local CarMovement         = require(Pathing:WaitForChild("CarMovement"))

local Rds                 = RoadsCore:WaitForChild("Roads")
local Roadgen             = Rds:WaitForChild("RoadGen")
local RoadGeneratorModule = require(Roadgen:WaitForChild("RoadGenerator"))

-- Which zone modes are “roads”
local ROAD_MODES = { DirtRoad = true, Pavement = true, Highway = true }
LOG("Core services fetched")

----------------------------------------------------------------
--  Buffer/Schema bridge
----------------------------------------------------------------
local Sload               = require(script.Parent.Sload)
local Compressor          = require(script.Parent.Compressor)
local b64enc, b64dec      = Compressor.b64encode, Compressor.b64decode

----------------------------------------------------------------
--  Undo stack integration
----------------------------------------------------------------
local PlayerCmdMgr    = require(game.ServerScriptService.Build.Zones.Commands.PlayerCommandManager)
local BuildZoneCmdMod = require(game.ServerScriptService.Build.Zones.Commands.BuildZoneCommand)

----------------------------------------------------------------
--  Utilities
----------------------------------------------------------------
local function count(tbl)
	local n = 0
	for _ in pairs(tbl or {}) do n += 1 end
	return n
end

local function waitForPlotName(player: Player, timeoutSec: number?): string?
	local t0, T = os.clock(), (timeoutSec or 5)
	local name = player:GetAttribute("PlotName")
	while not name and os.clock() - t0 < T do
		task.wait(0.1)
		name = player:GetAttribute("PlotName")
	end
	return name
end

local function safeB64(s: string?): string
	local okd, out = pcall(b64dec, s or "")
	return (okd and out) or ""
end

local function toWealthString(w: any): string?
	if w == nil then return nil end
	if typeof(w) == "number" then
		if w == 0 then return "Poor" end
		if w == 1 then return "Medium" end
		if w == 2 then return "Wealthy" end
		return tostring(w)
	elseif typeof(w) == "string" then
		if w == "0" then return "Poor" end
		if w == "1" then return "Medium" end
		if w == "2" then return "Wealthy" end
		return w
	end
	return nil
end

----------------------------------------------------------------
--  Capture (for SAVE)
----------------------------------------------------------------
local function collectBuildings(player: Player, zoneId: string)
	local out  = {}
	local plot = Workspace:FindFirstChild("PlayerPlots")
	plot = plot and plot:FindFirstChild("Plot_"..player.UserId)
	if not plot then return out end
	local pop  = plot:FindFirstChild("Buildings")
	pop = pop and pop:FindFirstChild("Populated")
	if not pop then return out end

	for _, folder in ipairs({ pop:FindFirstChild(zoneId), pop:FindFirstChild("Utilities") }) do
		if folder then
			for _, inst in ipairs(folder:GetChildren()) do
				if (inst:IsA("Model") or inst:IsA("BasePart"))
					and inst:GetAttribute("ZoneId") == zoneId
				then
					out[#out+1] = {
						buildingName = inst:GetAttribute("BuildingName"),
						gridX        = inst:GetAttribute("GridX"),
						gridZ        = inst:GetAttribute("GridZ"),
						rotation     = inst:GetAttribute("RotationY") or 0,
						isUtility    = inst:GetAttribute("IsUtility") or false,
						wealth       = inst:GetAttribute("WealthState")
					}
				end
			end
		end
	end
	return out
end

-- Unlocks safety cache (prevents empty table races)
local LastUnlockCacheByUid : { [number]: { [string]: boolean } } = {}

local function readUnlockTableFor(player: Player): { [string]: boolean }
	if not GetUnlocksForPlayer:IsA("BindableFunction") then
		warn("[SaveManager] GetUnlocksForPlayer is not a BindableFunction (is "..GetUnlocksForPlayer.ClassName..")")
		return LastUnlockCacheByUid[player.UserId] or {}
	end
	local ok, t = pcall(function() return GetUnlocksForPlayer:Invoke(player) end)
	if ok and type(t) == "table" and next(t) then
		return t
	end
	return LastUnlockCacheByUid[player.UserId] or {}
end

local UnlockChangedBE = BindableEvents:FindFirstChild("UnlockChanged")
if UnlockChangedBE and UnlockChangedBE:IsA("BindableEvent") then
	UnlockChangedBE.Event:Connect(function(player: Player, unlockName: string, state: boolean)
		local uid = player.UserId
		local t = LastUnlockCacheByUid[uid]
		if not t then t = {}; LastUnlockCacheByUid[uid] = t end
		if state then t[unlockName] = true else t[unlockName] = nil end
	end)
end

local function makeUnlockRows(player: Player)
	local rows, t = {}, readUnlockTableFor(player)
	for name, on in pairs(t) do
		if on then rows[#rows+1] = { name = name } end
	end
	return rows
end

local function makeZoneRows(player: Player)
	local rows = {}
	for id, z in pairs(ZoneTracker.getAllZones(player)) do
		local wealthArr, reqArr = {}, {}
		for _, vec in ipairs(z.gridList) do
			local wealthKey = ("%d,%d"):format(vec.x, vec.z)
			local tileKey   = ("%d_%d"):format(vec.x, vec.z)
			wealthArr[#wealthArr+1] = ZoneTracker.getGridWealth(player, id, vec.x, vec.z)
			reqArr  [#reqArr  +1]   = (z.tileRequirements and z.tileRequirements[tileKey])
				or { Road = false, Water = false, Power = false }
		end
		rows[#rows+1] = {
			id        = id,
			mode      = z.mode,
			coords    = z.gridList,
			flags     = z.requirements,
			wealth    = wealthArr,
			tileFlags = reqArr,
			buildings = HttpService:JSONEncode(collectBuildings(player, id)),
		}
	end
	return rows
end

local function makeRoadRows(player: Player)
	local rows = {}
	for id, z in pairs(ZoneTracker.getAllZones(player)) do
		if ROAD_MODES[z.mode] then
			local okSnap, snap = pcall(RoadGeneratorModule.captureRoadZoneSnapshot, player, id)
			if not okSnap then
				warn("[SaveManager] captureRoadZoneSnapshot failed for", id, snap)
				snap = { version = 1, zoneId = id, segments = {}, interDecos = {}, strDecos = {}, timeCaptured = os.clock() }
			end
			local okJSON, blob = pcall(HttpService.JSONEncode, HttpService, snap)
			if not okJSON then
				warn("[SaveManager] JSONEncode snapshot failed for", id, blob)
				blob = "{}"
			end
			rows[#rows+1] = { zoneId = id, snapshot = blob }
		end
	end
	return rows
end

local function dumpZones(player: Player)
	print(("---- Loaded zones for %s (%d) ----"):format(player.Name, player.UserId))
	for zoneId, z in pairs(ZoneTracker.getAllZones(player)) do
		local req = z.requirements
		local reqStr = ("%s%s%s"):format(
			req.Road  and "R" or "_",
			req.Water and "W" or "_",
			req.Power and "P" or "_"
		)
		local tiles = #z.gridList
		local first = z.gridList[1]
		local coordStr = first and ("(%d,%d)"):format(first.x, first.z) or "nil"
		print(("%s  mode=%s  tiles=%d  req=%s  first=%s")
			:format(zoneId, z.mode, tiles, reqStr, coordStr))
	end
	print("----------------------------------")
end

----------------------------------------------------------------
--  SAVE
----------------------------------------------------------------
local function savePlayer(player: Player, isFinal: boolean?)
	-- Capture snapshots into PlayerData
	local bufferZone   = Sload.Save("Zone", makeZoneRows(player))

	local bufferRoad = ""
	do
		local okRoad, outOrErr = pcall(function()
			return Sload.Save("RoadSnapshot", makeRoadRows(player))
		end)
		if okRoad then
			bufferRoad = outOrErr
		else
			warn("[SaveManager] RoadSnapshot save skipped:", outOrErr)
			bufferRoad = ""
		end
	end

	local bufferUnlock = ""
	local unlockNames  = {}
	do
		local okU, outOrErr = pcall(function()
			local rows = makeUnlockRows(player)
			for _, r in ipairs(rows) do unlockNames[#unlockNames+1] = r.name end
			return Sload.Save("Unlock", rows)
		end)
		if okU then
			bufferUnlock = outOrErr
		else
			warn("[SaveManager] Unlock save skipped:", outOrErr)
			bufferUnlock = ""
		end
	end

	PlayerDataService.ModifySaveData(player, "cityStorage/zonesB64",   b64enc(bufferZone))
	PlayerDataService.ModifySaveData(player, "cityStorage/roadsB64",   b64enc(bufferRoad))
	PlayerDataService.ModifySaveData(player, "cityStorage/unlocksB64", b64enc(bufferUnlock))
	PlayerDataService.ModifySaveData(player, "cityStorage/schema",     1)
	PlayerDataService.ModifySaveData(player, "lastPlayed",             os.time())
	PlayerDataService.ModifySaveData(player, "unlocks",                unlockNames)

	print(("savePlayer: zones=%d  roadBytes=%d  unlockBytes=%d")
		:format(count(ZoneTracker.getAllZones(player)), #bufferRoad, #bufferUnlock))

	-- Caller decides flush/await; only final calls force flush here
	if isFinal then
		PlayerDataService.SaveFlush(player, "savePlayer(isFinal)")
		if PlayerSaved then PlayerSaved:Fire(player) end
	end
end

----------------------------------------------------------------
--  HARD WIPE before LOAD (critical for slot switching)
----------------------------------------------------------------
local ZoneRemovedBE = ensureBindableEvent(BindableEvents, "ZoneRemoved")

local function wipeLiveWorld(player: Player)
	-- collect current zones BEFORE clearing ZoneTracker
	local ids = {}
	for id, _ in pairs(ZoneTracker.getAllZones(player)) do
		ids[#ids+1] = id
	end
	if #ids > 0 then
		for _, id in ipairs(ids) do
			-- fire standard removal pipeline (Roads/Power/Pipes/Plates/CarSpawner listen to this)
			ZoneRemovedBE:Fire(player, id)
		end
		LOG("Wipe: fired ZoneRemoved for", #ids, "zones")
		task.wait(0.05) -- give listeners a breath to clean up
	end

	-- defensive cleanup for any leftover instances (including dynamic traffic)
	local plots = Workspace:FindFirstChild("PlayerPlots")
	local plot  = plots and plots:FindFirstChild("Plot_"..player.UserId)
	if plot then
		for _, inst in ipairs(plot:GetDescendants()) do
			if inst.GetAttribute then
				if inst:GetAttribute("ZoneId") ~= nil then
					pcall(function() inst:Destroy() end)
				elseif inst:GetAttribute("IsTraffic") == true then
					pcall(function() inst:Destroy() end)
				end
			end
			if typeof(inst.Name) == "string" and string.sub(inst.Name, 1, 8) == "Traffic_" then
				pcall(function() inst:Destroy() end)
			end
		end
	end
end

----------------------------------------------------------------
--  Progressive LOAD scheduler (server-wide wheel + per-player slicing)
----------------------------------------------------------------
-- You can tune these safely.
local LOAD_WHEEL_DIV              = 3      -- only ~1/3 of players advance per heartbeat
local LOAD_BUDGET_MS_PER_SLICE    = 6      -- soft time budget per player per slice
local LOAD_MAX_ROADS_PER_SLICE    = 28     -- cap per slice to avoid bursty rebuilds
local LOAD_MAX_BUILDINGS_PER_SLICE= 10
local LOAD_MAX_NETWORKS_PER_SLICE = 20

-- Internal structures
local _loading : { [Player]: boolean } = {}
local _activeStates : { [Player]: any } = {}
local _bucketByPlayer : { [Player]: number } = {}
local _wheelIndex = 0
local _wheelCursor = 0

-- Helpers
local function isRoadRow(r)    return ROAD_MODES[r.mode] or ((r.id or ""):match("^RoadZone_") ~= nil) end
local function isNetworkRow(r) local id = r.id or ""; return id:match("^PowerLinesZone_") or id:match("^PipeZone_") or id:match("^WaterLinesZone_") end

-- Remote for early UI handoff (+ ack)
local PlotAssignedEvent = ensureRemoteEvent(EventsFolder, "RemoteEvents", "PlotAssigned")
local PlotAssignedAck   = ensureRemoteEvent(EventsFolder, "RemoteEvents", "PlotAssignedAck")
local function sendPlotAssignedWithAck(plr: Player, plotName: string, unlocks: table)
	local gotAck = false
	local conn : RBXScriptConnection? = nil
	conn = PlotAssignedAck.OnServerEvent:Connect(function(p)
		if p == plr then
			gotAck = true
			local c = conn; conn = nil
			if c then c:Disconnect() end
		end
	end)
	for _ = 1, 3 do
		PlotAssignedEvent:FireClient(plr, plotName, unlocks)
		local t0 = os.clock()
		while not gotAck and os.clock() - t0 < 1.0 do task.wait(0.05) end
		if gotAck then return true end
	end
	if conn then conn:Disconnect(); conn = nil end
	warn(("[SaveManager] PlotAssigned no ack from %s; proceeding anyway."):format(plr.Name))
	return false
end

-- Build an initial load state (blocking prep in a coroutine; the scheduler consumes slices after)
local function buildInitialLoadState(player: Player)
	PlayerDataService.WaitForPlayerData(player)

	-- Notify listeners we’re about to rebuild this player’s world
	WorldReloadBeginBE:Fire(player)

	-- Preload lifecycle + wipe world to truly switch slots/worlds
	CityInteractions.onCityPreload(player)
	wipeLiveWorld(player)
	ZoneTracker.clearPlayerData(player)

	-- Get savefile payload (current slot)
	local sf        = PlayerDataService.GetSaveFileData(player)
	local b64Zone   = (sf and sf.cityStorage and sf.cityStorage.zonesB64)   or ""
	local b64Road   = (sf and sf.cityStorage and sf.cityStorage.roadsB64)   or ""
	local b64Unlock = (sf and sf.cityStorage and sf.cityStorage.unlocksB64) or ""

	-- Decode
	local bufferZone   = safeB64(b64Zone)
	local bufferRoad   = safeB64(b64Road)
	local bufferUnlock = safeB64(b64Unlock)

	-- Deserialize
	local zoneRows = {}
	if bufferZone ~= "" then
		local okZ, rowsOrErr = pcall(function() return Sload.Load("Zone", bufferZone) end)
		if okZ and typeof(rowsOrErr) == "table" then zoneRows = rowsOrErr else warn("[SaveManager] Zone load skipped:", rowsOrErr) end
	end

	local unlockRows = {}
	if bufferUnlock ~= "" then
		local okU, rowsOrErr = pcall(function() return Sload.Load("Unlock", bufferUnlock) end)
		if okU and typeof(rowsOrErr) == "table" then unlockRows = rowsOrErr else warn("[SaveManager] Unlock load skipped:", rowsOrErr) end
	end

	local roadSnapByZone = {}
	if bufferRoad ~= "" then
		local okR, rowsOrErr = pcall(function() return Sload.Load("RoadSnapshot", bufferRoad) end)
		if okR and typeof(rowsOrErr) == "table" then
			for _, rr in ipairs(rowsOrErr) do
				local okJ, snap = pcall(HttpService.JSONDecode, HttpService, rr.snapshot)
				if okJ and typeof(snap) == "table" then
					roadSnapByZone[rr.zoneId] = snap
				end
			end
		else
			warn("[SaveManager] RoadSnapshot load skipped:", rowsOrErr)
		end
	end

	print(("Load payload sizes: Zone=%d  Roads=%d  Unlocks=%d")
		:format(#bufferZone, #bufferRoad, #bufferUnlock))

	-- Unlocks (build table now; apply early in Phase A)
	local unlockTable = {}
	for _, ur in ipairs(unlockRows) do
		if ur.name and ur.name ~= "" then unlockTable[ur.name] = true end
	end
	LastUnlockCacheByUid[player.UserId] = unlockTable

	-- state
	local state = {
		phase = "A",
		player = player,
		zoneRows = zoneRows,
		unlockRows = unlockRows,
		roadSnapByZone = roadSnapByZone,
		havePopulateFromSave = (typeof(RoadGeneratorModule.populateZoneFromSave) == "function"),
		-- indices for progressive loops
		idxSkeleton = 1,
		idxRoads    = 1,
		idxBuild    = 1,
		idxNet      = 1,
		maxZoneIdx  = 0,
		predefinedCacheByZone = {}, -- lazy JSON decode cache
		roadPayloadByZone     = {}, -- lazily prepared
		unlockTable = unlockTable,
		sentPlotAssigned = false,
		pathingResetDone = false,
	}
	return state
end

local function assignBucket(player: Player)
	_wheelCursor += 1
	local bucket = ((_wheelCursor - 1) % LOAD_WHEEL_DIV) + 1
	_bucketByPlayer[player] = bucket
	return bucket
end

local function ensurePredefinedCache(state, zoneId: string, row)
	local cache = state.predefinedCacheByZone
	if cache[zoneId] ~= nil then return cache[zoneId] end
	local predefined = {}
	if row.buildings and row.buildings ~= "" then
		local okJSON, decoded = pcall(HttpService.JSONDecode, HttpService, row.buildings)
		if okJSON and typeof(decoded) == "table" then
			predefined = decoded
		end
	end
	cache[zoneId] = predefined
	return predefined
end

local function ensureRoadPayloadFor(state, row)
	local zoneId = row.id
	if state.roadPayloadByZone[zoneId] ~= nil then
		return state.roadPayloadByZone[zoneId]
	end
	local payload = nil
	local snap = state.roadSnapByZone[zoneId]
	if state.havePopulateFromSave then
		payload = snap
	elseif snap and typeof(snap) == "table" and snap.segments then
		local arr = {}
		for _, seg in ipairs(snap.segments) do
			arr[#arr+1] = { roadName = seg.roadName, rotation = seg.rotation, gridX = seg.gridX, gridZ = seg.gridZ }
		end
		if #arr > 0 then payload = arr end
	end
	state.roadPayloadByZone[zoneId] = payload
	return payload
end

local function runLoadSlice(state, budgetMs)
	local player = state.player
	local deadline = os.clock() + (budgetMs / 1000.0)

	-- Phase A: Early handoff (pre-commit unlocks, early PlotAssigned)
	if state.phase == "A" then
		-- Apply unlocks now so UI can reflect them immediately
		local SetUnlocksForPlayer = BindableEvents:FindFirstChild("SetUnlocksForPlayer")
		if SetUnlocksForPlayer and SetUnlocksForPlayer:IsA("BindableFunction") then
			local okSet, err = pcall(function()
				return SetUnlocksForPlayer:Invoke(player, state.unlockTable, false)
			end)
			if not okSet then
				warn("[SaveManager] SetUnlocksForPlayer failed:", err)
			end
		else
			warn("[SaveManager] SetUnlocksForPlayer not available; unlock visuals may lag.")
		end

		-- Early UI handoff: fire PlotAssigned before we start rebuilding zones
		if not state.sentPlotAssigned then
			local plotName = player:GetAttribute("PlotName") or waitForPlotName(player, 3)
			if plotName then
				sendPlotAssignedWithAck(player, plotName, state.unlockTable)
			else
				warn(("[SaveManager] PlotName not set for %s within timeout; continuing."):format(player.Name))
			end
			state.sentPlotAssigned = true
		end

		state.phase = "B" -- advance
		return false -- not done yet
	end

	-- Phase B: add zone skeletons (IDs, coords, flags/wealth/tileFlags) progressively
	if state.phase == "B" then
		while state.idxSkeleton <= #state.zoneRows do
			local r = state.zoneRows[state.idxSkeleton]
			ZoneTracker.addZone(player, r.id, r.mode, r.coords)

			-- track contiguous numbering
			local idx = tonumber(r.id and r.id:match("(%d+)$"))
			if idx and idx > state.maxZoneIdx then state.maxZoneIdx = idx end

			-- patch wealth/tile flags onto the in-memory zone
			local z = ZoneTracker.getZoneById(player, r.id)
			if z then
				z.requirements     = r.flags or {}
				z.tileRequirements = z.tileRequirements or {}
				for i, vec in ipairs(r.coords) do
					local wealthKey = ("%d,%d"):format(vec.x, vec.z)
					local tileKey   = ("%d_%d"):format(vec.x, vec.z)
					local decodedWealth = toWealthString(r.wealth and r.wealth[i])
					if decodedWealth ~= nil then
						z.wealth[wealthKey] = decodedWealth
					end
					z.tileRequirements[tileKey] =
						(r.tileFlags and r.tileFlags[i])
						or z.tileRequirements[tileKey]
						or { Road=false, Water=false, Power=false }
				end
			end

			state.idxSkeleton += 1
			if os.clock() >= deadline then return false end
		end

		-- keep ZoneN numbering contiguous
		ZoneManager.playerZoneCounters = ZoneManager.playerZoneCounters or {}
		ZoneManager.playerZoneCounters[player.UserId] = state.maxZoneIdx + 1

		state.phase = "C"
		return false
	end

	-- Phase C: ROADS (time-sliced + optional graph reset)
	if state.phase == "C" then
		if not state.pathingResetDone then
			-- Prefer per-player reset if available, else global
			local okPP = pcall(function()
				if typeof(PathingModule.resetForPlayer) == "function" then
					PathingModule.resetForPlayer(player)
					return true
				end
				return false
			end)
			if not okPP or okPP == false then
				pcall(function() PathingModule.reset() end)
			end
			state.pathingResetDone = true
		end

		local processed = 0
		while state.idxRoads <= #state.zoneRows do
			local r = state.zoneRows[state.idxRoads]
			if isRoadRow(r) then
				ZoneReCreated:Fire(player, r.id, r.mode, r.coords, ensureRoadPayloadFor(state, r), 0)
				processed += 1
				if processed >= LOAD_MAX_ROADS_PER_SLICE then break end
			end
			state.idxRoads += 1
			if os.clock() >= deadline then break end
		end

		if state.idxRoads > #state.zoneRows then
			state.phase = "D"
		end
		return false
	end

	-- Phase D: BUILDINGS (non-road, non-network) in slices
	if state.phase == "D" then
		local processed = 0
		while state.idxBuild <= #state.zoneRows do
			local r = state.zoneRows[state.idxBuild]
			if (not isRoadRow(r)) and (not isNetworkRow(r)) then
				local z = ZoneTracker.getZoneById(player, r.id)
				local predefined = ensurePredefinedCache(state, r.id, r)
				if not (z and z.requirements and z.requirements.Populated) or #predefined > 0 then
					ZoneReCreated:Fire(player, r.id, r.mode, r.coords, predefined, 0)
				end
				processed += 1
				if processed >= LOAD_MAX_BUILDINGS_PER_SLICE then break end
			end
			state.idxBuild += 1
			if os.clock() >= deadline then break end
		end

		if state.idxBuild > #state.zoneRows then
			state.phase = "E"
		end
		return false
	end

	-- Phase E: NETWORK OVERLAYS in slices
	if state.phase == "E" then
		local processed = 0
		while state.idxNet <= #state.zoneRows do
			local r = state.zoneRows[state.idxNet]
			if isNetworkRow(r) then
				ZoneReCreated:Fire(player, r.id, r.mode, r.coords, nil, 0)
				processed += 1
				if processed >= LOAD_MAX_NETWORKS_PER_SLICE then break end
			end
			state.idxNet += 1
			if os.clock() >= deadline then break end
		end

		if state.idxNet > #state.zoneRows then
			state.phase = "F"
		end
		return false
	end

	-- Phase F: post-load hooks (unsuspend listeners, ropes rebuild, advisor, undo seed, dump)
	if state.phase == "F" then
		-- post-load hooks: unsuspend network listeners, rebuild ordered polylines
		local NetworksPostLoadBE = ensureBindableEvent(BindableEvents, "NetworksPostLoad")
		NetworksPostLoadBE:Fire(player)

		-- optional power rope rebuild
		local okPower, PowerGeneratorModule2 = pcall(function()
			local CC = Zones:WaitForChild("CoreConcepts")
			local PG = CC:FindFirstChild("PowerGen")
			return PG and require(PG:WaitForChild("PowerGenerator"))
		end)
		if okPower and PowerGeneratorModule2 and typeof(PowerGeneratorModule2.rebuildRopesForAll) == "function" then
			pcall(function() PowerGeneratorModule2.rebuildRopesForAll(player) end)
		end

		-- seed undo stack (unchanged behavior)
		local mgr = PlayerCmdMgr:getManager(player)
		for i = 1, math.min(2, #state.zoneRows) do
			local zr = state.zoneRows[i]
			local predefined = ensurePredefinedCache(state, zr.id, zr)
			local cmd = BuildZoneCmdMod.fromExistingZone(player, zr.id, zr.mode, zr.coords, predefined)
			cmd._pushedToStack = true
			table.insert(mgr.undoStack, cmd)
		end

		CityInteractions.onCityPostload(player)
		dumpZones(player)

		WorldReloadEndBE:Fire(player)

		return true -- DONE
	end

	return false
end

-- Kick off a progressive load (or restart current)
local function enqueueLoad(player: Player, reason: string?)
	if not player or not player.Parent then return end

	-- cancel any existing job
	_activeStates[player] = nil

	_loading[player] = true
	-- Build initial state in its own coroutine (may yield on WaitForPlayerData)
	task.spawn(function()
		local state = buildInitialLoadState(player)
		if not state then
			_loading[player] = nil
			return
		end
		_activeStates[player] = state
		assignBucket(player)
		LOG("Enqueued progressive load for", player.Name, reason and ("("..reason..")") or "")
	end)
end

-- Public safe entry (compat with existing callers)
local function loadPlayer(player: Player)
	enqueueLoad(player, "loadPlayer()")
end

-- Global scheduler: rotates a 3-step wheel across heartbeats
RunService.Heartbeat:Connect(function(_dt)
	_wheelIndex = (_wheelIndex % LOAD_WHEEL_DIV) + 1
	local budgetMs = LOAD_BUDGET_MS_PER_SLICE

	for plr, state in pairs(_activeStates) do
		if plr and plr.Parent and _bucketByPlayer[plr] == _wheelIndex then
			local done = false
			-- Protect each slice
			local ok, err = pcall(function()
				done = runLoadSlice(state, budgetMs)
			end)
			if not ok then
				warn("[SaveManager] load slice failed for ", plr.Name, " : ", err)
				done = true -- abort this job; avoid stuck state
			end
			if done then
				_activeStates[plr] = nil
				_loading[plr] = nil
				LOG("Load complete for", plr.Name)
			end
		end
	end
end)

----------------------------------------------------------------
--  BindToClose / Manual save hooks
----------------------------------------------------------------
game:BindToClose(function()
	-- capture -> SaveFlush -> wait-for-drain for each player
	for _, plr in ipairs(Players:GetPlayers()) do
		savePlayer(plr, false)
		PlayerDataService.SaveFlush(plr, "BindToClose")
	end
	-- Ensure all saves drained before returning
	local deadline = os.clock() + 25
	for _, plr in ipairs(Players:GetPlayers()) do
		if not PlayerDataService.WaitForSavesToDrain(plr, math.max(0, deadline - os.clock())) then
			warn("[SaveManager] BindToClose: timed out waiting for save drain for", plr.Name)
		end
	end
end)

local manualSaveBE = BindableEvents:FindFirstChild("ManualSave")
if manualSaveBE and manualSaveBE:IsA("BindableEvent") then
	manualSaveBE.Event:Connect(function(plr: Player)
		savePlayer(plr, false)
		PlayerDataService.SaveFlush(plr, "ManualSave")
	end)
end

----------------------------------------------------------------
--  NEW: external reload hook used by SwitchToSlot
----------------------------------------------------------------
local RequestReloadFromCurrent = ensureBindableEvent(BindableEvents, "RequestReloadFromCurrent")

RequestReloadFromCurrent.Event:Connect(function(plr: Player)
	LOG("ReloadFromCurrent requested for", plr and plr.Name or "<nil>")
	task.spawn(function()
		enqueueLoad(plr, "RequestReloadFromCurrent")
	end)
end)

----------------------------------------------------------------
--  Lifecycle
----------------------------------------------------------------
Players.PlayerAdded:Connect(function(plr)
	LOG("Players.PlayerAdded", plr.Name)
	enqueueLoad(plr, "PlayerAdded")
end)

Players.PlayerRemoving:Connect(function(plr)
	LOG("Players.PlayerRemoving", plr.Name)
	-- cancel any inflight progressive job
	_activeStates[plr] = nil
	_loading[plr] = nil

	-- capture -> SaveFlush -> wait-for-drain to avoid dropped saves
	savePlayer(plr, false)
	PlayerDataService.SaveFlush(plr, "PlayerRemoving")
	PlayerDataService.WaitForSavesToDrain(plr, 25)
end)

-- autosave loop (unchanged behavior; PDS coalescing removes data loss risk)
task.spawn(function()
	while true do
		local dt = 120 + math.random(0, 10)
		LOG("Autosave loop sleeping", dt, "seconds")
		task.wait(dt)
		for _, plr in ipairs(Players:GetPlayers()) do
			savePlayer(plr, false)
			PlayerDataService.Save(plr, { reason = "AutoSave" })
			task.wait(0.15)
		end
	end
end)

LOG("==== SaveManager fully initialised ====")
