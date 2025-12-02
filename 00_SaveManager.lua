----------------------------------------------------------------
--  Init / Logging
----------------------------------------------------------------
local START_TIME = os.clock()
local Debug      = false
local function LOG(...)
	if Debug then
		print(("[SaveManager][+%.3fs] "):format(os.clock() - START_TIME), ...)
	end
end
LOG("==== INIT SaveManager script ====")

local function expectChild(parent: Instance, childName: string, className: string, timeout: number?)
	local inst = parent:FindFirstChild(childName)
	if inst and inst:IsA(className) then
		return inst
	end
	local ok, result = pcall(parent.WaitForChild, parent, childName, timeout or 5)
	if ok and result and result:IsA(className) then
		return result
	end
	error(string.format("SaveManager missing %s '%s' under %s", className, childName, parent:GetFullName()))
end

----------------------------------------------------------------
--  Core services
----------------------------------------------------------------
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local Workspace          = game:GetService("Workspace")
local ServerStorage      = game:GetService("ServerStorage")
local HttpService        = game:GetService("HttpService")
local RunService         = game:GetService("RunService")
local RunServiceScheduler = require(ReplicatedStorage.Scripts.RunServiceScheduler)

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

-- Internal stage notifications to listeners (suspend/resume consumers)
local WorldReloadBeginBE = expectChild(BindableEvents, "WorldReloadBegin", "BindableEvent")
local WorldReloadEndBE   = expectChild(BindableEvents, "WorldReloadEnd", "BindableEvent")

-- Remote to relay world reload + progress to client
local WorldReloadRE = expectChild(RemoteEvents, "WorldReload", "RemoteEvent")

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
local LayerManager        = require(Bld:WaitForChild("LayerManager"))
local CoreConcepts        = Zones:WaitForChild("CoreConcepts")
local PowerGenFolder      = CoreConcepts:WaitForChild("PowerGen")
local PowerGeneratorModule = require(PowerGenFolder:WaitForChild("PowerGenerator"))

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

local _saveQueuedOnReloadEnd : { [Player]: boolean } = {}

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
	local name = player:GetAttribute("PlotName")
	if name then
		return name
	end

	local deadline = os.clock() + (timeoutSec or 5)
	local signal = player:GetAttributeChangedSignal("PlotName")
	local conn

	conn = signal:Connect(function()
		local current = player:GetAttribute("PlotName")
		if current then
			name = current
		end
	end)

	while not name and os.clock() < deadline do
		RunService.Heartbeat:Wait()
	end

	if conn then
		conn:Disconnect()
	end

	return name or player:GetAttribute("PlotName")
end

local function safeB64(s: string?): string
	local okd, out = pcall(b64dec, s or "")
	return (okd and out) or ""
end

local function isValidB64(s: string?): boolean
	local ok = pcall(b64dec, s or "")
	return ok == true
end

-- If serialization fails, prefer a previous valid snapshot; otherwise fall back to empty cityStorage.
local function finalizeCityStorageBuffer(newBuffer: string?, prevB64: string?, prevValid: boolean, label: string): string
	local buf = (type(newBuffer) == "string") and newBuffer or ""
	local prior = (type(prevB64) == "string") and prevB64 or ""

	if buf ~= "" then
		return b64enc(buf)
	end

	if prevValid and prior ~= "" then
		warn(("[SaveManager] %s save failed; reusing previous snapshot"):format(label))
		return prior
	end

	if prior ~= "" then
		warn(("[SaveManager] %s save failed; previous snapshot invalid; writing empty cityStorage"):format(label))
	end
	return ""
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

-- [FIX] Treat Metro tunnels as network/non-building style zones too.
local function isNetworkId(id: string?): boolean
	local s = id or ""
	return (s:match("^PowerLinesZone_") ~= nil)
		or (s:match("^PipeZone_") ~= nil)
		or (s:match("^WaterLinesZone_") ~= nil)
		or (s:match("^MetroTunnelZone_") ~= nil) -- [NEW]
end

-- [ENHANCEMENT] Shallow-normalizing copy of a blueprint array (defensive)
local function copyBlueprintList(list: {any}?): {any}
	if type(list) ~= "table" then return {} end
	local out = table.create(#list)
	for i, b in ipairs(list) do
		out[i] = {
			buildingName = b.buildingName,
			gridX        = b.gridX,
			gridZ        = b.gridZ,
			rotation     = b.rotation or 0,
			isUtility    = b.isUtility or false,
			wealth       = b.wealth,
		}
	end
	return out
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

-- [ENHANCEMENT] Cache of last known building blueprints per player+zone
local LastBlueprintByUid : { [number]: { [string]: { [number]: any } } } = {}

local function readUnlockTableFor(player: Player): { [string]: boolean }
	if not GetUnlocksForPlayer:IsA("BindableFunction") then
		warn("[SaveManager] GetUnlocksForPlayer is not a BindableFunction (is "..GetUnlocksForPlayer.ClassName..")")
		return LastUnlockCacheByUid[player.UserId] or {}
	end
	local ok, t = pcall(function() return GetUnlocksForPlayer:Invoke(player) end)
	-- Accept empty tables as authoritative (fresh cities); only fall back on errors or bad types.
	if ok and type(t) == "table" then
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

-- [ENHANCEMENT] Record final placed blueprints right when a zone finishes populating
ZonePopulated.Event:Connect(function(player: Player, zoneId: string)
	if not player or not zoneId then return end
	local uid = player.UserId
	local captured = collectBuildings(player, zoneId)
	if type(captured) == "table" and #captured > 0 then
		LastBlueprintByUid[uid] = LastBlueprintByUid[uid] or {}
		LastBlueprintByUid[uid][zoneId] = copyBlueprintList(captured)
		LOG("ZonePopulated: cached blueprint for", zoneId, "(n="..tostring(#captured)..")")
	end
end)

-- [ENHANCEMENT] Also cache when a zone is reconstructed from a predefined list
ZoneReCreated.Event:Connect(function(player: Player, zoneId: string, mode: string, _coords: any, predefined: any, _rot: any)
	if player and zoneId and predefined and type(predefined) == "table"
		and not ROAD_MODES[mode] and not isNetworkId(zoneId) and #predefined > 0 then
		local uid = player.UserId
		LastBlueprintByUid[uid] = LastBlueprintByUid[uid] or {}
		LastBlueprintByUid[uid][zoneId] = copyBlueprintList(predefined)
		LOG("ZoneReCreated: seeded cache for", zoneId, "(n="..tostring(#predefined)..")")
	end
end)

-- Decode previous zones rows into a fast map for per‑zone fallback.
local function decodePrevZoneRows(prevB64: string?): { [string]: any }
	local map = {}
	if not prevB64 or prevB64 == "" then return map end
	local blob = safeB64(prevB64)
	if blob == "" then return map end
	local ok, rowsOrErr = pcall(function() return Sload.Load("Zone", blob) end)
	if ok and typeof(rowsOrErr) == "table" then
		for _, r in ipairs(rowsOrErr) do
			if r and r.id then map[r.id] = r end
		end
	end
	return map
end

-- [NEW] Decode previous road snapshots (per-zone map: zoneId -> snapshot table)
local function decodePrevRoadRows(prevB64: string?): { [string]: any }
	local map = {}
	if not prevB64 or prevB64 == "" then return map end
	local blob = safeB64(prevB64)
	if blob == "" then return map end
	local ok, rowsOrErr = pcall(function() return Sload.Load("RoadSnapshot", blob) end)
	if ok and typeof(rowsOrErr) == "table" then
		for _, rr in ipairs(rowsOrErr) do
			if rr and rr.zoneId and rr.snapshot and rr.snapshot ~= "" then
				local okJ, snap = pcall(HttpService.JSONDecode, HttpService, rr.snapshot)
				if okJ and typeof(snap) == "table" then
					map[rr.zoneId] = snap
				end
			end
		end
	end
	return map
end

-- [FIX] makeZoneRows now accepts prevRowsById and does **per‑zone** fallback instead of global.
local function makeZoneRows(player: Player): ({any}, { [string]: boolean })
	local rows = {}
	local missingSet : { [string]: boolean } = {}
	local uid = player.UserId

	for id, z in pairs(ZoneTracker.getAllZones(player)) do
		local wealthArr, reqArr = {}, {}
		for _, vec in ipairs(z.gridList) do
			local wealthKey = ("%d,%d"):format(vec.x, vec.z)
			local tileKey   = ("%d_%d"):format(vec.x, vec.z)
			wealthArr[#wealthArr+1] = ZoneTracker.getGridWealth(player, id, vec.x, vec.z)
			reqArr  [#reqArr  +1]   = (z.tileRequirements and z.tileRequirements[tileKey])
				or { Road = false, Water = false, Power = false }
		end

		-- Live capture
		local captured = {}
		local okCap, capErr = pcall(function()
			captured = collectBuildings(player, id)
		end)
		if not okCap then
			warn("[SaveManager] collectBuildings failed for zone", id, capErr)
			captured = {}
		end

		-- If empty, try last-good cached blueprint, else mark as missing for per-zone fallback
		if (type(captured) ~= "table" or #captured == 0) and (not ROAD_MODES[z.mode]) and (not isNetworkId(id)) then
			local cached = LastBlueprintByUid[uid] and LastBlueprintByUid[uid][id]
			if cached and #cached > 0 then
				LOG("[SaveManager] Using cached blueprint for", id, "(n="..tostring(#cached)..")")
				captured = cached
			else
				missingSet[id] = true
				warn("[SaveManager] No buildings captured for zone", id, "; will attempt per-zone fallback to previous save.")
				captured = {} -- keep empty for now; we may fill from prev save in savePlayer()
			end
		end

		local okB, buildingsJSON = pcall(function()
			return HttpService:JSONEncode(captured)
		end)
		if not okB then
			warn("[SaveManager] JSONEncode buildings failed for zone", id, "; defaulting to empty array.")
			buildingsJSON = "[]"
		end

		rows[#rows+1] = {
			id        = id,
			mode      = z.mode,
			coords    = z.gridList,
			flags     = z.requirements,
			refundClockAt = z.refundClockAt or (z.requirements and z.requirements.Populated and z.createdAt),
			createdAt = z.createdAt or os.time(),
			wealth    = wealthArr,
			tileFlags = reqArr,
			buildings = buildingsJSON,
		}
	end

	return rows, missingSet
end

local function makeRoadRows(player: Player, prevByZone: { [string]: any }?)
	local rows = {}
	for id, z in pairs(ZoneTracker.getAllZones(player)) do
		if ROAD_MODES[z.mode] then
			local snap = nil

			-- 1) Prefer exact, in-memory snapshot if the generator saved one
			local okGet, memSnap = pcall(function()
				if typeof(RoadGeneratorModule.getSnapshot) == "function" then
					return RoadGeneratorModule.getSnapshot(player, id)
				end
				return nil
			end)
			if okGet and typeof(memSnap) == "table" and typeof(memSnap.segments) == "table" and #memSnap.segments > 0 then
				snap = memSnap
			else
				-- 2) Fall back to a fresh world capture
				local okCap, cap = pcall(RoadGeneratorModule.captureRoadZoneSnapshot, player, id)
				if okCap and typeof(cap) == "table" then
					snap = cap
				else
					warn("[SaveManager] captureRoadZoneSnapshot failed for", id, cap)
					snap = { version = 1, zoneId = id, segments = {}, interDecos = {}, strDecos = {}, timeCaptured = os.clock() }
				end
			end

			-- 3) If still empty, reuse previous saved snapshot for this zone
			if (not snap.segments) or (#snap.segments == 0) then
				local prev = prevByZone and prevByZone[id]
				if prev and typeof(prev.segments) == "table" and #prev.segments > 0 then
					snap = prev
					LOG("[SaveManager] RoadSnapshot fallback applied for", id, "(prev segments=", tostring(#prev.segments), ")")
				end
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
	--print(("---- Loaded zones for %s (%d) ----"):format(player.Name, player.UserId))
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
		--print(("%s  mode=%s  tiles=%d  req=%s  first=%s"):format(zoneId, z.mode, tiles, reqStr, coordStr))
	end
	--print("----------------------------------")
end

----------------------------------------------------------------
--  SAVE
----------------------------------------------------------------

local function _countTilesForPlayer(player: Player): number
	local n = 0
	for _, z in pairs(ZoneTracker.getAllZones(player)) do
		n += #z.gridList
	end
	return n
end

-- [TRACKING] in-flight population jobs and reload windows
local InflightPopByUid : { [number]: number } = {}
local InReload         : { [Player]: boolean } = {}

----------------------------------------------------------------
--  Reload occlusion cube (to force culling while world swaps)
----------------------------------------------------------------
local OcclusionCubeByPlayer : { [Player]: Model } = {}

local function findOcclusionCubeTemplate(): Model?
	local container = ServerStorage:FindFirstChild("CUBE CONTAINMENT")
	if not container then
		container = ReplicatedStorage:FindFirstChild("CUBE CONTAINMENT")
	end
	if not container then
		return nil
	end

	local cube = container:FindFirstChild("THE CUBE")
	if cube and cube:IsA("Model") then
		return cube
	end
	return nil
end

local function destroyOcclusionCube(player: Player)
	local existing = OcclusionCubeByPlayer[player]
	if existing then
		OcclusionCubeByPlayer[player] = nil
		existing:Destroy()
	end
end

local function placeOcclusionCube(player: Player)
	local template = findOcclusionCubeTemplate()
	if not (template and player) then return end

	local plotsFolder = Workspace:FindFirstChild("PlayerPlots")
	local plot = plotsFolder and plotsFolder:FindFirstChild("Plot_" .. player.UserId)
	if not plot then return end

	destroyOcclusionCube(player)

	local clone = template:Clone()
	clone.Parent = plot

	-- Compute target from placement attributes so it matches manual drop-in.
	local px = plot:GetAttribute("PlacementPosX")
	local py = plot:GetAttribute("PlacementPosY")
	local pz = plot:GetAttribute("PlacementPosZ")
	local yawDeg = plot:GetAttribute("PlacementYaw") or 0

	local basePos = (typeof(px) == "number" and typeof(py) == "number" and typeof(pz) == "number")
		and Vector3.new(px, py, pz)
		or ((plot.PrimaryPart and plot.PrimaryPart.Position) or plot:GetPivot().Position)

	-- Hardcoded targets per known plot placement (rounded PlacementPosX/Z key).
	local anchorKey = string.format("%d|%d", math.floor((px or basePos.X) + 0.5), math.floor((pz or basePos.Z) + 0.5))
	local targetPos = nil
	local TARGETS = {
		["205|-4615"]   = Vector3.new(204.766, 13.945, -4743),
		["209|-4387"]   = Vector3.new(204.766, 12.545, -4254.8),
		["-295|-4615"]  = Vector3.new(-295.234, 13.945, -4743),
		["-291|-4387"]  = Vector3.new(-290.766, 13.995, -4259),
		["-795|-4615"]  = Vector3.new(-795.234, 13.945, -4743),
		["-791|-4387"]  = Vector3.new(-790.766, 13.995, -4259),
		["-1295|-4615"] = Vector3.new(-1295.234, 13.945, -4743),
		["-1291|-4387"] = Vector3.new(-1290.766, 13.995, -4259),
	}
	targetPos = TARGETS[anchorKey]

	-- Fallback to generic offset if we don't have a hardcoded target.
	if not targetPos then
		local CUBE_LOCAL_OFFSET = Vector3.new(0.234, 15.445, 128.0)
		local yawRad = math.rad(yawDeg)
		local baseCF = CFrame.new(basePos) * CFrame.Angles(0, yawRad, 0)
		local worldOffset = baseCF:VectorToWorldSpace(CUBE_LOCAL_OFFSET)
		targetPos = basePos + worldOffset
	end

	local yawRad = math.rad(yawDeg)
	local targetCF = CFrame.new(targetPos) * CFrame.Angles(0, yawRad + math.pi, 0)
	local ok, err = pcall(function()
		clone:PivotTo(targetCF)
	end)
	if not ok then
		warn("[SaveManager] Failed to position occlusion cube:", err)
	end

	OcclusionCubeByPlayer[player] = clone
end

-- Drain barrier: wait briefly for zone population pipeline to quiesce
local function awaitZonePipelinesToDrain(player: Player, timeoutSec: number?): boolean
	local uid = player.UserId
	local deadline = os.clock() + (timeoutSec or 2.5)
	while os.clock() < deadline do
		local n = InflightPopByUid[uid] or 0
		if n <= 0 then return true end
		task.wait(0.05)
	end
	return false
end

-- Hook population counters
ZoneCreated.Event:Connect(function(player: Player, _zoneId: string, _mode: string, _coords: any)
	if player then
		local uid = player.UserId
		InflightPopByUid[uid] = (InflightPopByUid[uid] or 0) + 1
	end
end)

-- ADD THIS: also count rebuild/populate that comes via ZoneReCreated
ZoneReCreated.Event:Connect(function(player: Player, _zoneId: string, _mode: string, _coords: any, _predef: any, _rotation: any)
	if player then
		local uid = player.UserId
		InflightPopByUid[uid] = (InflightPopByUid[uid] or 0) + 1
	end
end)

ZonePopulated.Event:Connect(function(player: Player, _zoneId: string)
	if player then
		local uid = player.UserId
		local cur = InflightPopByUid[uid] or 0
		if cur > 0 then InflightPopByUid[uid] = cur - 1 else InflightPopByUid[uid] = 0 end
	end
end)

-- Hook reload window (relay to client)
WorldReloadBeginBE.Event:Connect(function(player: Player)
	InReload[player] = true
	placeOcclusionCube(player)
	WorldReloadRE:FireClient(player, "begin")
	-- Optional early seed of progress band A:
	WorldReloadRE:FireClient(player, "progress", 2, "LOAD_Preparing")
end)
WorldReloadEndBE.Event:Connect(function(player: Player)
	destroyOcclusionCube(player)
	InReload[player] = nil
	WorldReloadRE:FireClient(player, "end")
end)

local function waitAllZonesSettled(player: Player, timeoutSec: number?): boolean
	local deadline = os.clock() + (timeoutSec or 2.5)
	while os.clock() < deadline do
		local busy = false
		for id, _ in pairs(ZoneTracker.getAllZones(player)) do
			if typeof(ZoneTracker.isZonePopulating) == "function" and ZoneTracker.isZonePopulating(player, id) then
				busy = true; break
			end
		end
		if not busy then return true end
		task.wait(0.05)
	end
	return false
end

----------------------------------------------------------------
-- [NEW] Blueprint‑dirty coalescer & on‑the‑spot save
----------------------------------------------------------------
local _refreshDebounce : { [Player]: { [string]: boolean } } = {}
local _lastSaveAt      : { [Player]: number } = {}
local savePlayer: (Player, boolean?, {[string]: any}?) -> ()

local function _refreshZoneBlueprintAndMaybeSave(player: Player, zoneId: string, reason: string)
	if not player or not zoneId or not player.Parent then return end

	-- Coalesce per zone
	_refreshDebounce[player] = _refreshDebounce[player] or {}
	if _refreshDebounce[player][zoneId] then return end
	_refreshDebounce[player][zoneId] = true

	task.spawn(function()
		-- Tiny debounce so attributes land; if actively populating, wait briefly.
		task.wait(0.10)
		local deadline = os.clock() + 3.0
		while typeof(ZoneTracker.isZonePopulating) == "function"
			and ZoneTracker.isZonePopulating(player, zoneId)
			and os.clock() < deadline
		do
			task.wait(0.05)
		end

		-- Refresh cache from live world
		local uid = player.UserId
		local captured = collectBuildings(player, zoneId)
		LastBlueprintByUid[uid] = LastBlueprintByUid[uid] or {}
		LastBlueprintByUid[uid][zoneId] = copyBlueprintList(captured)

		LOG("[Blueprint] refreshed for", zoneId, "n=", tostring(#captured or 0), "reason=", reason)

		-- Save (throttled) – if reloading, queue for end
		local now = os.clock()
		if InReload[player] then
			_saveQueuedOnReloadEnd[player] = true
		else
			if not _lastSaveAt[player] or (now - _lastSaveAt[player] > 2.5) then
				savePlayer(player, false, {
					reason = "BlueprintChanged:"..tostring(reason or "?"),
					awaitPipelines = false,
					skipWorldWhenReloading = true,
				})
				pcall(function() PlayerDataService.Save(player, { reason = "BlueprintChanged" }) end)
				_lastSaveAt[player] = now
			end
		end

		_refreshDebounce[player][zoneId] = nil
	end)
end

-- Wire up signals that imply blueprint changes.
local function _connectIfBE(name: string, fn)
	local ev = BindableEvents:FindFirstChild(name)
	if ev and ev:IsA("BindableEvent") then
		ev.Event:Connect(fn)
		LOG("Hooked BE:", name)
	end
end

-- Your BuildingGenerator fires this per building; we coalesce per zone.
_connectIfBE("Wigw8mPlaced", function(player: Player, zoneId: string, _payload: any)
	_refreshZoneBlueprintAndMaybeSave(player, zoneId, "Wigw8mPlaced")
end)

-- Fires periodically during populate; coalesce per zone.
_connectIfBE("BuildingsPlaced", function(player: Player, zoneId: string, _count: number)
	_refreshZoneBlueprintAndMaybeSave(player, zoneId, "BuildingsPlaced")
end)

-- **Call this when a bucket/cluster finishes** (recommended).
local ZoneBlueprintChangedBE = expectChild(BindableEvents, "ZoneBlueprintChanged", "BindableEvent")
ZoneBlueprintChangedBE.Event:Connect(function(player: Player, zoneId: string, opts: any)
	_refreshZoneBlueprintAndMaybeSave(player, zoneId, (opts and opts.reason) or "ZoneBlueprintChanged")
end)

----------------------------------------------------------------
--  SAVE pipeline (full snapshot path; still used by manual/leave/etc.)
----------------------------------------------------------------
savePlayer = function(player: Player, isFinal: boolean?, opts: {[string]: any}?)
	opts = opts or {}
	local reason = opts.reason or (isFinal and "FinalSave" or "Save")
	local awaitPipelines = (opts.awaitPipelines ~= false)
	local tiles = _countTilesForPlayer(player)
	local base = 2.5
	local perTile = 0.04  -- ~40ms per tile budget
	local pipelinesTimeout = math.min(20, (opts.pipelinesTimeoutSec or (base + perTile * tiles)))
	local skipWorldWhenReloading = (opts.skipWorldWhenReloading ~= false)
	local force = (opts.force == true)

	-- [BARRIER] If requested, give zone pipelines a brief chance to finish so attributes exist.
	if awaitPipelines then
		local drained = awaitZonePipelinesToDrain(player, pipelinesTimeout)
		if not drained then
			LOG(("Save barrier timed out (%.1fs) for %s; proceeding."), pipelinesTimeout, player.Name)
		end
	end
	-- tiny yield to allow last attribute sets to commit
	task.wait(0.03)

	-- [GUARD] Don't clobber a good save with a partial world while loading/reloading.
	if skipWorldWhenReloading and (InReload[player] or false) and not force then
		LOG("Skipping world snapshot for", player.Name, "(reload in progress). Saving only session metadata.")
		PlayerDataService.ModifySaveData(player, "lastPlayed", os.time())

		-- keep a plain unlocks list refreshed from cache (cheap and safe)
		local unlockNames  = {}
		for name, on in pairs(LastUnlockCacheByUid[player.UserId] or {}) do
			if on then unlockNames[#unlockNames+1] = name end
		end
		PlayerDataService.ModifySaveData(player, "unlocks", unlockNames)

		if isFinal and PlayerSaved then PlayerSaved:Fire(player) end
		return
	end

	if awaitPipelines then
		waitAllZonesSettled(player, pipelinesTimeout)
	end

	-- Capture snapshots into PlayerData (world snapshot path)
	local bufferZone = ""
	local bufferRoad = ""
	local bufferUnlock = ""
	local unlockNames  = {}
	local missingSetForSummary : { [string]: boolean }? = nil

	-- Keep a reference to previous cityStorage in case we need to retain it
	local prevZonesB64, prevRoadsB64, prevUnlocksB64 = "", "", ""
	local prevZonesValid, prevRoadsValid, prevUnlocksValid = false, false, false
	pcall(function()
		local sf = PlayerDataService.GetSaveFileData(player)
		local storage = sf and sf.cityStorage
		if storage then
			prevZonesB64   = storage.zonesB64 or ""
			prevRoadsB64   = storage.roadsB64 or ""
			prevUnlocksB64 = storage.unlocksB64 or ""
		end
		prevZonesValid   = isValidB64(prevZonesB64)
		prevRoadsValid   = isValidB64(prevRoadsB64)
		prevUnlocksValid = isValidB64(prevUnlocksB64)
	end)
	
	-- [NEW] Decode previous rows once for **per-zone fallback**
	local prevRowsById = decodePrevZoneRows(prevZonesB64)
	local prevRoadById = decodePrevRoadRows(prevRoadsB64)
	
	-- Zones & buildings
	do
		local zoneRows, missingSet = makeZoneRows(player)
		missingSetForSummary = missingSet

		-- If any zones are missing buildings, stitch from previous for those zones only.
		if next(missingSet) ~= nil and prevZonesB64 ~= "" then
			for _, r in ipairs(zoneRows) do
				local prev = prevRowsById[r.id]
				if missingSet[r.id] and prev and prev.buildings and prev.buildings ~= "" then
					r.buildings = prev.buildings
					LOG("[SaveManager] Per-zone fallback applied for", r.id)
				elseif missingSet[r.id] then
					LOG("[SaveManager] No previous buildings for", r.id, "— leaving empty array.")
				end
			end
		end

		local okZ, outOrErr = pcall(function()
			return Sload.Save("Zone", zoneRows)
		end)
		if okZ then
			bufferZone = outOrErr
		else
			warn("[SaveManager] Zone save skipped:", outOrErr)
			bufferZone = ""
		end
	end

	-- Roads
	do
		local okRoad, outOrErr = pcall(function()
			-- [FIX] robust road snapshotting with in-memory + per-zone previous fallback
			return Sload.Save("RoadSnapshot", makeRoadRows(player, prevRoadById))
		end)
		if okRoad then
			bufferRoad = outOrErr
		else
			warn("[SaveManager] RoadSnapshot save skipped:", outOrErr)
			bufferRoad = ""
		end
	end

	-- Unlocks
	do
		local okU, outOrErr = pcall(function()
			local rows = (function(player: Player)
				local rows, t = {}, readUnlockTableFor(player)
				for name, on in pairs(t) do
					if on then rows[#rows+1] = { name = name } end
				end
				return rows
			end)(player)
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

	local zonesB64Out   = finalizeCityStorageBuffer(bufferZone,   prevZonesB64,   prevZonesValid,   "Zone")
	local roadsB64Out   = finalizeCityStorageBuffer(bufferRoad,   prevRoadsB64,   prevRoadsValid,   "RoadSnapshot")
	local unlocksB64Out = finalizeCityStorageBuffer(bufferUnlock, prevUnlocksB64, prevUnlocksValid, "Unlock")

	-- Apply to save object
	pcall(function() PlayerDataService.ModifySaveData(player, "cityStorage/zonesB64",   zonesB64Out) end)
	pcall(function() PlayerDataService.ModifySaveData(player, "cityStorage/roadsB64",   roadsB64Out) end)
	pcall(function() PlayerDataService.ModifySaveData(player, "cityStorage/unlocksB64", unlocksB64Out) end)
	pcall(function() PlayerDataService.ModifySaveData(player, "cityStorage/schema",     1) end)
	pcall(function() PlayerDataService.ModifySaveData(player, "lastPlayed",             os.time()) end)
	pcall(function() PlayerDataService.ModifySaveData(player, "unlocks",                unlockNames) end)

	do
		local nZones, nMissing = 0, 0
		for _ in pairs(ZoneTracker.getAllZones(player)) do
			nZones += 1
		end
		if missingSetForSummary then
			for _ in pairs(missingSetForSummary) do nMissing += 1 end
		end
		LOG(("Save summary: zones=%d  missingFallbacks=%d  roadBytes=%d  unlockBytes=%d")
			:format(nZones, nMissing, #bufferRoad, #bufferUnlock))
	end

	--print(("savePlayer[%s]: zones=%d  roadBytes=%d  unlockBytes=%d"):format(reason, count(ZoneTracker.getAllZones(player)), #bufferRoad, #bufferUnlock))

	if isFinal and PlayerSaved then PlayerSaved:Fire(player) end
end

-- Consume any queued save once the world is fully rebuilt
WorldReloadEndBE.Event:Connect(function(plr: Player)
	if _saveQueuedOnReloadEnd[plr] then
		_saveQueuedOnReloadEnd[plr] = nil
		-- small delay to ensure _loading is cleared by Phase F completion
		task.delay(0.1, function()
			if plr and plr.Parent then
				savePlayer(plr, false, { reason = "QueuedAfterReload" })
				PlayerDataService.SaveFlush(plr, "QueuedAfterReload")
			end
		end)
	end
end)

----------------------------------------------------------------
--  HARD WIPE before LOAD (critical for slot switching)
----------------------------------------------------------------
local ZoneRemovedBE = expectChild(BindableEvents, "ZoneRemoved", "BindableEvent")

-- [NEW] Per-player coalescer for saves triggered by zone deletions
local _zoneDeleteSaveCoalesce : { [Player]: boolean } = {}

-- [ENHANCED] Drop blueprint cache when zones are removed (wipe/switch) **and trigger a coalesced save**
ZoneRemovedBE.Event:Connect(function(player: Player, zoneId: string)
	local uid = player and player.UserId
	if uid and LastBlueprintByUid[uid] then
		LastBlueprintByUid[uid][zoneId] = nil
		LOG("ZoneRemoved: cleared cached blueprint for", zoneId)
	end

	-- If we're reloading, don't snapshot; queue for the end of reload.
	if InReload[player] then
		_saveQueuedOnReloadEnd[player] = true
		return
	end

	-- Coalesce burst deletions (drag delete/multi delete)
	if _zoneDeleteSaveCoalesce[player] then return end
	_zoneDeleteSaveCoalesce[player] = true

	task.delay(0.25, function()
		_zoneDeleteSaveCoalesce[player] = nil
		if not player or not player.Parent then return end

		-- Throttle quick repeats
		local now = os.clock()
		if not _lastSaveAt[player] or (now - _lastSaveAt[player] > 1.0) then
			savePlayer(player, false, {
				reason = "ZoneRemoved:"..tostring(zoneId),
				awaitPipelines = false,            -- nothing to wait for on delete
				skipWorldWhenReloading = true,
			})
			pcall(function() PlayerDataService.Save(player, { reason = "ZoneRemoved" }) end)
			_lastSaveAt[player] = now
		end
	end)
end)

local function wipeLiveWorld(player: Player)
	-- Canonical world wipe (removes every zone; fires ZoneRemoved with mode+gridList for listeners)
	local removed = ZoneTracker.removeAllZonesForPlayer(player)
	LOG(("Wipe: removed %d zones via ZoneTracker (canonical)"):format(removed))
	task.wait(0.05) -- give listeners a breath

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

	-- Drop any archived layer data for this player to avoid cross-session restores
	LayerManager.clearPlayer(player)
end

----------------------------------------------------------------
--  Progressive LOAD scheduler (server-wide wheel + per-player slicing)
----------------------------------------------------------------
-- You can tune these safely.
local LOAD_WHEEL_DIV              = 2   -- fewer buckets = more work per frame per player
local LOAD_BUDGET_MS_PER_SLICE    = 12  -- per-bucket budget in ms
local LOAD_MAX_ROADS_PER_SLICE    = 40
local LOAD_MAX_BUILDINGS_PER_SLICE= 20
local LOAD_MAX_NETWORKS_PER_SLICE = 20

-- Internal structures (LOAD)
local _loading : { [Player]: boolean } = {}
local _activeStates : { [Player]: any } = {}
local _bucketByPlayer : { [Player]: number } = {}
local _wheelIndex = 0
local _wheelCursor = 0

-- Helpers
local function isRoadRow(r)    return ROAD_MODES[r.mode] or ((r.id or ""):match("^RoadZone_") ~= nil) end
-- [FIX] Treat metro tunnels as network rows for Phase E (network overlays)
local function isNetworkRow(r)
	local id = r.id or ""
	return id:match("^PowerLinesZone_")
		or id:match("^PipeZone_")
		or id:match("^WaterLinesZone_")
		or id:match("^MetroTunnelZone_") -- [NEW]
end

-- Remote for early UI handoff (+ ack)
local PlotAssignedEvent = expectChild(RemoteEvents, "PlotAssigned", "RemoteEvent")
local PlotAssignedAck   = expectChild(RemoteEvents, "PlotAssignedAck", "RemoteEvent")
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

-- Phase progress bands (A..F) shown to the player
local PHASE_RANGES = {
	A = {min= 2, max= 5,  key="LOAD_Preparing"},
	B = {min= 5, max=25,  key="LOAD_SettingUpZones"},
	C = {min=25, max=55,  key="LOAD_BuildingRoads"},
	D = {min=55, max=90,  key="LOAD_PlacingBuildings"},
	E = {min=90, max=96,  key="LOAD_LayingUtilities"},
	F = {min=96, max=100, key="LOAD_Finalizing"},
}

local function _blend(range, frac)
	frac = math.clamp(frac or 0, 0, 1)
	return range.min + (range.max - range.min) * frac
end

local function _sendProgress(state, pct, label)
	local player = state.player
	if not player or not player.Parent then return end
	pct = math.clamp(math.floor(pct + 0.5), 0, 100)

	-- Throttle to avoid event spam
	local now = os.clock()
	if state._lastProgressPct ~= pct or not state._lastProgressAt or (now - state._lastProgressAt) > 0.20 then
		state._lastProgressPct = pct
		state._lastProgressAt  = now
		WorldReloadRE:FireClient(player, "progress", pct, label)
	end
end

-- Build an initial load state (blocking prep in a coroutine; the scheduler consumes slices after)
local function buildInitialLoadState(player: Player)
	PlayerDataService.WaitForPlayerData(player)

	-- Notify listeners we’re about to rebuild this player’s world
	WorldReloadBeginBE:Fire(player)

	-- Preload lifecycle + wipe world to truly switch slots/worlds
	CityInteractions.onCityPreload(player)
	wipeLiveWorld(player)

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

	local roadSnapByZone, hasAnyRoadDecos = {}, false
	local zonesNeedingIntersections = {}  -- << NEW
	if bufferRoad ~= "" then
		local okR, rowsOrErr = pcall(function() return Sload.Load("RoadSnapshot", bufferRoad) end)
		if okR and typeof(rowsOrErr) == "table" then
			for _, rr in ipairs(rowsOrErr) do
				local okJ, snap = pcall(HttpService.JSONDecode, HttpService, rr.snapshot)
				if okJ and typeof(snap) == "table" then
					roadSnapByZone[rr.zoneId] = snap
					-- any decos at all?
					if (snap.interDecos and #snap.interDecos > 0) or (snap.strDecos and #snap.strDecos > 0) then
						hasAnyRoadDecos = true
					end
					-- specifically missing INTERSECTION decos? queue for one-time rebuild
					if not (snap.interDecos and #snap.interDecos > 0) then
						table.insert(zonesNeedingIntersections, rr.zoneId)
					end
				end
			end
		else
			warn("[SaveManager] RoadSnapshot load skipped:", rowsOrErr)
		end
	end

	LOG(("Load payload sizes: Zone=%d  Roads=%d  Unlocks=%d")
		:format(#bufferZone, #bufferRoad, #bufferUnlock))

	-- Unlocks (build table now; apply early in Phase A)
	local unlockTable = {}
	for _, ur in ipairs(unlockRows) do
		if ur.name and ur.name ~= "" then unlockTable[ur.name] = true end
	end
	LastUnlockCacheByUid[player.UserId] = unlockTable

	local totalZones, totalRoads, totalBuildings, totalNetworks = #zoneRows, 0, 0, 0
	for _, r in ipairs(zoneRows) do
		if isRoadRow(r) then
			totalRoads += 1
		elseif isNetworkRow(r) then
			totalNetworks += 1
		else
			totalBuildings += 1
		end
	end

	-- state
	local state = {
		phase = "A",
		player = player,
		zoneRows = zoneRows,
		unlockRows = unlockRows,
		roadSnapByZone = roadSnapByZone,
		hasAnyRoadDecos = hasAnyRoadDecos, -- << NEW
		zonesNeedingIntersections = zonesNeedingIntersections,
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
		totalZones      = totalZones,
		totalRoads      = totalRoads,
		totalBuildings  = totalBuildings,
		totalNetworks   = totalNetworks,

		doneSkeleton    = 0,
		doneRoads       = 0,
		doneBuildings   = 0,
		doneNetworks    = 0,

		_lastProgressPct = nil,
		_lastProgressAt  = nil,
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
		else
			local preview = string.sub(row.buildings, 1, 120)
			if #row.buildings > 120 then
				preview ..= "..."
			end
			warn(("[SaveManager] Predefined decode failed for %s (len=%d): %s | %s")
				:format(zoneId, #row.buildings, okJSON and ("decoded type " .. typeof(decoded)) or tostring(decoded), preview))
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

	-- Prefer full snapshot when available and non-empty
	if state.havePopulateFromSave
		and snap and typeof(snap) == "table"
		and typeof(snap.segments) == "table" and #snap.segments > 0
	then
		payload = snap
	elseif snap and typeof(snap) == "table" and typeof(snap.segments) == "table" then
		-- degrade to placed list for older generators
		local arr = {}
		for _, seg in ipairs(snap.segments) do
			arr[#arr+1] = {
				roadName = seg.roadName,
				rotation = seg.rotation,
				gridX    = seg.gridX,
				gridZ    = seg.gridZ,
			}
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
		if not state.unlockDispatchScheduled then
			state.unlockDispatchScheduled = true
			task.spawn(function()
				if not player or not player.Parent then return end
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
			end)
		end

		if not state.sentPlotAssigned then
			state.sentPlotAssigned = true
			task.spawn(function()
				if not player or not player.Parent then return end
				local plotName = player:GetAttribute("PlotName") or waitForPlotName(player, 3)
				if plotName then
					if not player or not player.Parent then return end
					local okAck, err = pcall(function()
						sendPlotAssignedWithAck(player, plotName, state.unlockTable)
					end)
					if not okAck then
						warn("[SaveManager] PlotAssigned dispatch failed:", err)
					end
				else
					warn(("[SaveManager] PlotName not set for %s within timeout; continuing."):format(player.Name))
				end
			end)
		end

		_sendProgress(state, PHASE_RANGES.A.min, PHASE_RANGES.A.key)
		state.phase = "B" -- advance
		return false -- not done yet
	end

	-- Phase B: add zone skeletons (IDs, coords, flags/wealth/tileFlags) progressively
	if state.phase == "B" then
		while state.idxSkeleton <= #state.zoneRows do
			local r = state.zoneRows[state.idxSkeleton]
			ZoneTracker.addZone(player, r.id, r.mode, r.coords, {
				createdAt     = r.createdAt,
				refundClockAt = r.refundClockAt,
				requirements  = r.flags,
			})

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

			-- progress
			state.doneSkeleton += 1
			local fracB = (state.totalZones == 0) and 1 or (state.doneSkeleton / state.totalZones)
			_sendProgress(state, _blend(PHASE_RANGES.B, fracB), PHASE_RANGES.B.key)

			state.idxSkeleton += 1
			if os.clock() >= deadline then return false end
		end

		-- keep ZoneN numbering contiguous
		ZoneManager.playerZoneCounters = ZoneManager.playerZoneCounters or {}
		ZoneManager.playerZoneCounters[player.UserId] = state.maxZoneIdx + 1

		-- end of phase B -> snap to B.max
		_sendProgress(state, PHASE_RANGES.B.max, PHASE_RANGES.B.key)

		state.phase = "C"
		return false
	end

	-- Phase C: ROADS
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
				ZoneReCreated:Fire(player, r.id, r.mode, r.coords, ensureRoadPayloadFor(state, r), 0, true)

				-- progress
				state.doneRoads += 1
				local fracC = (state.totalRoads == 0) and 1 or (state.doneRoads / state.totalRoads)
				_sendProgress(state, _blend(PHASE_RANGES.C, fracC), PHASE_RANGES.C.key)

				processed += 1
				if processed >= LOAD_MAX_ROADS_PER_SLICE then break end
			end
			state.idxRoads += 1
			if os.clock() >= deadline then break end
		end

		if state.idxRoads > #state.zoneRows then
			-- end of phase C -> snap to C.max
			_sendProgress(state, PHASE_RANGES.C.max, PHASE_RANGES.C.key)
			state.phase = "D"
		end
		return false
	end

	-- Phase D: Buildings
	if state.phase == "D" then
		local processed = 0
		while state.idxBuild <= #state.zoneRows do
			local r = state.zoneRows[state.idxBuild]
			if (not isRoadRow(r)) and (not isNetworkRow(r)) then
				local predefined = ensurePredefinedCache(state, r.id, r)
				if predefined and #predefined > 0 then
					ZoneReCreated:Fire(player, r.id, r.mode, r.coords, predefined, 0, true)
				else
					ZoneReCreated:Fire(player, r.id, r.mode, r.coords, nil, 0, true)
				end

				-- progress
				state.doneBuildings += 1
				local fracD = (state.totalBuildings == 0) and 1 or (state.doneBuildings / state.totalBuildings)
				_sendProgress(state, _blend(PHASE_RANGES.D, fracD), PHASE_RANGES.D.key)

				processed += 1
				if processed >= LOAD_MAX_BUILDINGS_PER_SLICE then break end
			end
			state.idxBuild += 1
			if os.clock() >= deadline then break end
		end

		if state.idxBuild > #state.zoneRows then
			-- end of phase D -> snap to D.max
			_sendProgress(state, PHASE_RANGES.D.max, PHASE_RANGES.D.key)
			state.phase = "E"
		end
		return false
	end

	-- Phase E: Networks
	if state.phase == "E" then
		local processed = 0
		while state.idxNet <= #state.zoneRows do
			local r = state.zoneRows[state.idxNet]
			if isNetworkRow(r) then
				ZoneReCreated:Fire(player, r.id, r.mode, r.coords, nil, 0, true)

				-- progress
				state.doneNetworks += 1
				local fracE = (state.totalNetworks == 0) and 1 or (state.doneNetworks / state.totalNetworks)
				_sendProgress(state, _blend(PHASE_RANGES.E, fracE), PHASE_RANGES.E.key)

				processed += 1
				if processed >= LOAD_MAX_NETWORKS_PER_SLICE then break end
			end
			state.idxNet += 1
			if os.clock() >= deadline then break end
		end

		if state.idxNet > #state.zoneRows then
			-- end of phase E -> snap to E.max
			_sendProgress(state, PHASE_RANGES.E.max, PHASE_RANGES.E.key)
			state.phase = "F"
		end
		return false
	end

	-- Phase F: post-load hooks
	if state.phase == "F" then
		-- Top off to 100% and "Finalizing"
		_sendProgress(state, PHASE_RANGES.F.max, PHASE_RANGES.F.key)

		local NetworksPostLoadBE = expectChild(BindableEvents, "NetworksPostLoad", "BindableEvent")
		NetworksPostLoadBE:Fire(player)

		if typeof(PowerGeneratorModule.rebuildRopesForAll) == "function" then
			pcall(function()
				PowerGeneratorModule.rebuildRopesForAll(player)
			end)
		end

		-- [ADD] One-time, full-plot intersection/deco rebuild only for old saves with no deco snapshot
		if state.zonesNeedingIntersections and #state.zonesNeedingIntersections > 0 then
			pcall(function()
				if typeof(RoadGeneratorModule.recalculateIntersectionsForPlot) == "function" then
					RoadGeneratorModule.recalculateIntersectionsForPlot(player, state.zonesNeedingIntersections)
				end
			end)
		end

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

		return true
	end

	return false
end

-- Kick off a progressive load (or restart current)
local function enqueueLoad(player: Player, reason: string?)
	if not player or not player.Parent then return end

	_activeStates[player] = nil

	_loading[player] = true
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

----------------------------------------------------------------
--  Progressive SAVE scheduler (bucketed + sliced autosave)
----------------------------------------------------------------
-- Tunables
local SAVE_WHEEL_DIV                    = 2   -- bucket players into two groups (e.g., 3 -> 2+1, 4 -> 2+2)
local SAVE_BUDGET_MS_PER_SLICE          = 6
local SAVE_MAX_ZONE_ROWS_PER_SLICE      = 14
local SAVE_MAX_ROAD_SNAPSHOTS_PER_SLICE = 20
local SAVE_REVERSE_OF_LOAD              = true -- true: Networks->Buildings->Roads; false: Buildings->Roads->Networks

-- Internal structures (SAVE)
local _activeSaves        : { [Player]: any } = {}
local _saveBucketByPlayer : { [Player]: number } = {}
local _saveWheelIndex = 0
local _saveRound = 0

-- Mark zones dirty for in-flight progressive autosaves
ZoneBlueprintChangedBE.Event:Connect(function(player: Player, zoneId: string, _opts: any)
	local st = _activeSaves[player]
	if st and zoneId then st.dirty[zoneId] = true end
end)
-- Also mark on reconstructed zones (roads/buildings/utilities)
ZoneReCreated.Event:Connect(function(player: Player, zoneId: string)
	local st = _activeSaves[player]
	if st and zoneId then st.dirty[zoneId] = true end
end)

local function classifyZonesFor(player: Player)
	local roads, nets, builds = {}, {}, {}
	for id, z in pairs(ZoneTracker.getAllZones(player)) do
		if isRoadRow({id=id, mode=z.mode}) then
			roads[#roads+1] = id
		elseif isNetworkRow({id=id}) then
			nets[#nets+1] = id
		else
			builds[#builds+1] = id
		end
	end
	table.sort(roads)
	table.sort(nets)
	table.sort(builds)
	return roads, nets, builds
end

local function captureZoneRowForSave(player: Player, id: string, prevRowsById: { [string]: any }, missingSet: { [string]: boolean })
	local z = ZoneTracker.getZoneById(player, id)
	if not z then return nil end

	local wealthArr, reqArr = {}, {}
	for _, vec in ipairs(z.gridList or {}) do
		wealthArr[#wealthArr+1] = ZoneTracker.getGridWealth(player, id, vec.x, vec.z)
		local tileKey = ("%d_%d"):format(vec.x, vec.z)
		reqArr[#reqArr+1] = (z.tileRequirements and z.tileRequirements[tileKey])
			or { Road=false, Water=false, Power=false }
	end

	local buildingsJSON = "[]"
	local needBuildings = (not ROAD_MODES[z.mode]) and (not isNetworkId(id))

	if needBuildings then
		local captured = {}
		local okCap, capErr = pcall(function()
			captured = collectBuildings(player, id)
		end)
		if not okCap then
			warn("[ProgSave] collectBuildings failed for", id, capErr)
			captured = {}
		end
		if type(captured) ~= "table" or #captured == 0 then
			local uid = player.UserId
			local cached = LastBlueprintByUid[uid] and LastBlueprintByUid[uid][id]
			if cached and #cached > 0 then
				captured = cached
			else
				missingSet[id] = true
			end
		end
		local okB, out = pcall(function() return HttpService:JSONEncode(captured) end)
		buildingsJSON = okB and out or "[]"
	end

	-- Per-zone fallback from previous save if we had no live/cached buildings
	if missingSet[id] and prevRowsById then
		local prev = prevRowsById[id]
		if prev and prev.buildings and prev.buildings ~= "" then
			buildingsJSON = prev.buildings
			LOG("[ProgSave] Per-zone fallback applied for", id)
		end
	end

	return {
		id        = id,
		mode      = z.mode,
		coords    = z.gridList,
		flags     = z.requirements,
		wealth    = wealthArr,
		tileFlags = reqArr,
		buildings = buildingsJSON,
	}
end

local function captureRoadSnapshotRow(player: Player, id: string, prevByZone: { [string]: any }?)
	-- 1) Prefer in-memory exact snapshot
	local snap = nil
	local okGet, memSnap = pcall(function()
		if typeof(RoadGeneratorModule.getSnapshot) == "function" then
			return RoadGeneratorModule.getSnapshot(player, id)
		end
		return nil
	end)
	if okGet and typeof(memSnap) == "table" and typeof(memSnap.segments) == "table" and #memSnap.segments > 0 then
		snap = memSnap
	else
		-- 2) Fresh world capture
		local okSnap, cap = pcall(RoadGeneratorModule.captureRoadZoneSnapshot, player, id)
		if okSnap and typeof(cap) == "table" then
			snap = cap
		else
			warn("[ProgSave] captureRoadZoneSnapshot failed for", id, cap)
			snap = { version = 1, zoneId = id, segments = {}, interDecos = {}, strDecos = {}, timeCaptured = os.clock() }
		end
	end

	-- 3) If empty, reuse previous saved snapshot
	if (not snap.segments) or (#snap.segments == 0) then
		local prev = prevByZone and prevByZone[id]
		if prev and typeof(prev.segments) == "table" and #prev.segments > 0 then
			snap = prev
			LOG("[ProgSave] RoadSnapshot fallback applied for", id, "(prev segments=", tostring(#prev.segments), ")")
		end
	end

	local okJSON, blob = pcall(HttpService.JSONEncode, HttpService, snap)
	if not okJSON then
		warn("[ProgSave] JSONEncode road snapshot failed for", id, blob)
		blob = "{}"
	end
	return { zoneId = id, snapshot = blob }
end

local function buildInitialSaveStateForAutosave(player: Player)
	-- Skip if reloading or already guarded elsewhere
	if _loading[player] or InReload[player] then
		_saveQueuedOnReloadEnd[player] = true
		return nil
	end

	-- Decode previous cityStorage for per-zone fallback + write fallback
	local prevZonesB64, prevRoadsB64, prevUnlocksB64 = "", "", ""
	local prevZonesValid, prevRoadsValid, prevUnlocksValid = false, false, false
	pcall(function()
		local sf = PlayerDataService.GetSaveFileData(player)
		local storage = sf and sf.cityStorage
		if storage then
			prevZonesB64   = storage.zonesB64 or ""
			prevRoadsB64   = storage.roadsB64 or ""
			prevUnlocksB64 = storage.unlocksB64 or ""
		end
		prevZonesValid   = isValidB64(prevZonesB64)
		prevRoadsValid   = isValidB64(prevRoadsB64)
		prevUnlocksValid = isValidB64(prevUnlocksB64)
	end)
	local prevRowsById = decodePrevZoneRows(prevZonesB64)
	local prevRoadById = decodePrevRoadRows(prevRoadsB64)

	-- Classify ids now; we re-validate existence on capture
	local roadIds, netIds, buildIds = classifyZonesFor(player)

	-- Order: reverse-of-load by default: Networks→Buildings→Roads
	local phases = SAVE_REVERSE_OF_LOAD
		and { "Z_NET", "Z_BLD", "Z_RD", "ROAD_SNAP", "UNLOCKS", "FINALIZE" }
		or  { "Z_BLD", "Z_RD", "Z_NET", "ROAD_SNAP", "UNLOCKS", "FINALIZE" }

	return {
		player    = player,
		phase     = phases[1],
		phases    = phases,
		phaseIdx  = 1,

		netIds    = netIds,
		buildIds  = buildIds,
		roadIds   = roadIds,

		idxNet    = 1,
		idxBuild  = 1,
		idxRoad   = 1,
		idxRoadSnap = 1,

		outZoneRows   = {},
		outZoneIndex  = {}, -- zoneId -> index in outZoneRows
		outRoadRows   = {},
		missingSet    = {},
		prevRowsById  = prevRowsById,
		prevRoadById  = prevRoadById,
		prevZonesB64   = prevZonesB64,
		prevRoadsB64   = prevRoadsB64,
		prevUnlocksB64 = prevUnlocksB64,
		prevZonesValid   = prevZonesValid,
		prevRoadsValid   = prevRoadsValid,
		prevUnlocksValid = prevUnlocksValid,
		dirty         = {},

		startedAt = os.clock(),
	}
end

local function _advanceSavePhase(state)
	state.phaseIdx += 1
	state.phase = state.phases[state.phaseIdx]
end

local function runSaveSlice(state, budgetMs)
	local player = state.player
	if not player or not player.Parent then return true end -- done/abort
	if InReload[player] then return true end -- abort autosave during reload

	local deadline = os.clock() + (budgetMs / 1000.0)

	-- Phase: zone rows (Networks / Buildings / Roads)
	if state.phase == "Z_NET" or state.phase == "Z_BLD" or state.phase == "Z_RD" then
		local list =
			(state.phase == "Z_NET" and state.netIds)
			or (state.phase == "Z_BLD" and state.buildIds)
			or state.roadIds

		local idxName =
			(state.phase == "Z_NET" and "idxNet") or
			(state.phase == "Z_BLD" and "idxBuild") or
			"idxRoad"

		local processed = 0
		while state[idxName] <= #list do
			local zoneId = list[state[idxName]]

			-- Only capture if zone still exists
			local z = ZoneTracker.getZoneById(player, zoneId)
			if z then
				local row = captureZoneRowForSave(player, zoneId, state.prevRowsById, state.missingSet)
				if row then
					-- Store or replace (if we recaptured a dirty one earlier)
					local curIndex = state.outZoneIndex[zoneId]
					if curIndex then
						state.outZoneRows[curIndex] = row
					else
						table.insert(state.outZoneRows, row)
						state.outZoneIndex[zoneId] = #state.outZoneRows
					end
				end
			end

			state[idxName] += 1
			processed += 1

			if processed >= SAVE_MAX_ZONE_ROWS_PER_SLICE or os.clock() >= deadline then
				return false -- not done yet
			end
		end
		_advanceSavePhase(state)
		return false
	end

	-- Phase: road snapshots
	if state.phase == "ROAD_SNAP" then
		local processed = 0
		while state.idxRoadSnap <= #state.roadIds do
			local zoneId = state.roadIds[state.idxRoadSnap]
			-- Only capture if zone still exists
			if ZoneTracker.getZoneById(player, zoneId) then
				local rr = captureRoadSnapshotRow(player, zoneId, state.prevRoadById)
				if rr then table.insert(state.outRoadRows, rr) end
			end
			state.idxRoadSnap += 1
			processed += 1
			if processed >= SAVE_MAX_ROAD_SNAPSHOTS_PER_SLICE or os.clock() >= deadline then
				return false
			end
		end
		_advanceSavePhase(state)
		return false
	end

	-- Phase: unlocks (cheap)
	if state.phase == "UNLOCKS" then
		state.unlockRows = {}
		state.unlockNames = {}
		local t = readUnlockTableFor(player)
		for name, on in pairs(t) do
			if on then
				state.unlockRows[#state.unlockRows+1] = { name = name }
				state.unlockNames[#state.unlockNames+1] = name
			end
		end
		_advanceSavePhase(state)
		return false
	end

	-- Phase: finalize (re-check dirties, serialize, commit)
	if state.phase == "FINALIZE" then
		-- Re-capture dirty zones (if they still exist)
		for zoneId, _ in pairs(state.dirty) do
			local z = ZoneTracker.getZoneById(player, zoneId)
			if z then
				local row = captureZoneRowForSave(player, zoneId, state.prevRowsById, state.missingSet)
				if row then
					local i = state.outZoneIndex[zoneId]
					if i then state.outZoneRows[i] = row
					else
						table.insert(state.outZoneRows, row)
						state.outZoneIndex[zoneId] = #state.outZoneRows
					end
				end
			else
				-- Zone was removed; drop from saved rows if present
				local i = state.outZoneIndex[zoneId]
				if i then
					state.outZoneRows[i] = nil
					state.outZoneIndex[zoneId] = nil
				end
			end
		end

		-- Compact outZoneRows in case we niled any
		local compact = {}
		for _, r in ipairs(state.outZoneRows) do
			if r then compact[#compact+1] = r end
		end
		state.outZoneRows = compact

		-- Serialize & commit
		local bufferZone, bufferRoad, bufferUnlock = "", "", ""

		local okZ, outZ = pcall(function() return Sload.Save("Zone", state.outZoneRows) end)
		if okZ then bufferZone = outZ else warn("[ProgSave] Zone Save skipped:", outZ) end

		local okR, outR = pcall(function() return Sload.Save("RoadSnapshot", state.outRoadRows) end)
		if okR then bufferRoad = outR else warn("[ProgSave] RoadSnapshot Save skipped:", outR) end

		local okU, outU = pcall(function() return Sload.Save("Unlock", state.unlockRows or {}) end)
		if okU then bufferUnlock = outU else warn("[ProgSave] Unlock Save skipped:", outU) end

		local zonesB64Out   = finalizeCityStorageBuffer(bufferZone,   state.prevZonesB64 or "",   state.prevZonesValid == true,   "Zone")
		local roadsB64Out   = finalizeCityStorageBuffer(bufferRoad,   state.prevRoadsB64 or "",   state.prevRoadsValid == true,   "RoadSnapshot")
		local unlocksB64Out = finalizeCityStorageBuffer(bufferUnlock, state.prevUnlocksB64 or "", state.prevUnlocksValid == true, "Unlock")

		-- Apply to savefile (will stage automatically if a reload window is open)
		pcall(function() PlayerDataService.ModifySaveData(player, "cityStorage/zonesB64",   zonesB64Out) end)
		pcall(function() PlayerDataService.ModifySaveData(player, "cityStorage/roadsB64",   roadsB64Out) end)
		pcall(function() PlayerDataService.ModifySaveData(player, "cityStorage/unlocksB64", unlocksB64Out) end)
		pcall(function() PlayerDataService.ModifySaveData(player, "cityStorage/schema",     1) end)
		pcall(function() PlayerDataService.ModifySaveData(player, "lastPlayed",             os.time()) end)
		pcall(function() PlayerDataService.ModifySaveData(player, "unlocks",                state.unlockNames or {}) end)

		-- Coalesced DataStore write (non-flush)
		PlayerDataService.Save(player, { reason = "AutoSave" })

		LOG(("[ProgSave] Commit complete for %s  zones=%d  roads=%d  unlocks=%d")
			:format(player.Name, #state.outZoneRows, #state.outRoadRows, #(state.unlockRows or {})))

		return true -- done
	end

	return true -- safety: unknown phase -> done
end

----------------------------------------------------------------
--  Global scheduler (LOAD + SAVE wheels)
----------------------------------------------------------------
RunServiceScheduler.onHeartbeat(function(_dt)
	-- LOAD wheel (existing)
	_wheelIndex = (_wheelIndex % LOAD_WHEEL_DIV) + 1
	local budgetMsLoad = LOAD_BUDGET_MS_PER_SLICE

	for plr, state in pairs(_activeStates) do
		if plr and plr.Parent and _bucketByPlayer[plr] == _wheelIndex then
			local done = false
			local ok, err = pcall(function()
				done = runLoadSlice(state, budgetMsLoad)
			end)
			if not ok then
				warn("[SaveManager] load slice failed for ", plr.Name, " : ", err)
				done = true
			end
			if done then
				_activeStates[plr] = nil
				_loading[plr] = nil
				LOG("Load complete for", plr.Name)
			end
		end
	end

	-- SAVE wheel (new)
	_saveWheelIndex = (_saveWheelIndex % SAVE_WHEEL_DIV) + 1
	local budgetMsSave = SAVE_BUDGET_MS_PER_SLICE
	for plr, st in pairs(_activeSaves) do
		if plr and plr.Parent and _saveBucketByPlayer[plr] == _saveWheelIndex then
			local done = false
			local ok, err = pcall(function()
				done = runSaveSlice(st, budgetMsSave)
			end)
			if not ok then
				warn("[SaveManager] save slice failed for ", plr.Name, " : ", err)
				done = true
			end
			if done then
				_activeSaves[plr] = nil
				LOG("Autosave complete for", plr.Name)
			end
		end
	end
end)

----------------------------------------------------------------
--  BindToClose / Manual save hooks
----------------------------------------------------------------
game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do
		if not _loading[plr] then
			savePlayer(plr, false, { reason = "BindToClose" })
		else
			LOG("BindToClose: skipping world snapshot for", plr.Name, "(still loading)")
		end
		PlayerDataService.SaveFlush(plr, "BindToClose")
	end
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
		if _loading[plr] then
			_saveQueuedOnReloadEnd[plr] = true
			LOG("ManualSave deferred until reload end for", plr.Name)
			return
		end
		savePlayer(plr, false, { reason = "ManualSave" })
		PlayerDataService.SaveFlush(plr, "ManualSave")
	end)
end

----------------------------------------------------------------
--  NEW: external reload hook used by SwitchToSlot
----------------------------------------------------------------
local RequestReloadFromCurrent = expectChild(BindableEvents, "RequestReloadFromCurrent", "BindableEvent")

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
	InflightPopByUid[plr.UserId] = 0
	enqueueLoad(plr, "PlayerAdded")
end)

Players.PlayerRemoving:Connect(function(plr)
	LOG("Players.PlayerRemoving", plr.Name)
	_activeStates[plr] = nil

	InflightPopByUid[plr.UserId] = 0
	InReload[plr] = nil
	destroyOcclusionCube(plr)

	local firedPlayerSaved = false

	if _loading[plr] then
		LOG("PlayerRemoving: skipping world snapshot for", plr.Name, "(still loading)")
	else
		local needsSettle = false
		for id, _ in pairs(ZoneTracker.getAllZones(plr)) do
			if typeof(ZoneTracker.isZonePopulating) == "function" and ZoneTracker.isZonePopulating(plr, id) then
				needsSettle = true; break
			end
		end
		if needsSettle then
			task.wait(0.1)
			pcall(function() waitAllZonesSettled(plr, 10.0) end)
		end

		savePlayer(plr, true, {
			skipWorldWhenReloading = true,
			awaitPipelines = true,
			reason = "PlayerRemoving",
		})
		firedPlayerSaved = true
	end

	_loading[plr] = nil

	PlayerDataService.SaveFlush(plr, "PlayerRemoving")
	PlayerDataService.WaitForSavesToDrain(plr, 25)

	-- Ensure listeners (PlotAssigner/cleanup) run even if we skipped the world snapshot.
	if PlayerSaved and not firedPlayerSaved then
		PlayerSaved:Fire(plr)
	end
end)

----------------------------------------------------------------
--  Autosave round driver (bucketed + progressive)
----------------------------------------------------------------
task.spawn(function()
	while true do
		local dt = 120 + math.random(0, 10)
		LOG("Autosave loop sleeping", dt, "seconds")
		task.wait(dt)

		local list = Players:GetPlayers()
		if #list == 0 then continue end

		-- Round-robin the first bucket so the same players aren't always saved first
		_saveRound += 1
		if (_saveRound % 2) == 1 then
			local rev = table.create(#list)
			for i = #list, 1, -1 do rev[#rev+1] = list[i] end
			list = rev
		end

		local half = math.ceil(#list / 2)
		for i, plr in ipairs(list) do
			if _loading[plr] then
				_saveQueuedOnReloadEnd[plr] = true
				LOG("Autosave deferred (loading) for", plr.Name)
			else
				if not _activeSaves[plr] then
					local st = buildInitialSaveStateForAutosave(plr)
					if st then
						_activeSaves[plr] = st
						_saveBucketByPlayer[plr] = (i <= half) and 1 or 2
						LOG("Enqueued progressive autosave for", plr.Name, ("bucket=%d"):format(_saveBucketByPlayer[plr]))
					end
				end
			end
			task.wait(0.02) -- light pacing between enqueue ops
		end
	end
end)

LOG("==== SaveManager fully initialised ====")
