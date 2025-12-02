-- AirTraffic.lua
-- Lightweight plane spawner for Airports. Inspired by BoatTraffic, but airport-specific anchors.

local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Debris            = game:GetService("Debris")

local Events         = ReplicatedStorage:WaitForChild("Events")
local BindableEvents = Events:WaitForChild("BindableEvents")

local ZoneTracker = require(game.ServerScriptService.Build.Zones.ZoneManager.ZoneTracker)

-- Assets
local AirRoot = ReplicatedStorage:WaitForChild("FuncTestGroundRS"):WaitForChild("Air")

-- Config
local PER_PLAYER_CAP    = 1
local GLOBAL_CAP        = 4
local MIN_SPAWN_DELAY   = 12
local MAX_SPAWN_DELAY   = 18
local TAXI_SPEED        = 15      -- slowed down taxi
local TAKEOFF_SPEED     = 40      -- slowed down climb
local TAKEOFF_ARC_HEIGHT = 12     -- extra height for the parabolic arc
local PLANE_YAW_OFFSET  = 0       -- adjust if plane forward axis differs from look vector
local DEBUG_LOG         = false

local function log(...)
	if DEBUG_LOG then
		print("[AirTraffic]", ...)
	end
end

-- Ensure events exist (load-order safe)
local function ensureBindable(container: Instance, name: string): BindableEvent
	local ev = container:FindFirstChild(name)
	if ev and ev:IsA("BindableEvent") then return ev end
	ev = Instance.new("BindableEvent")
	ev.Name = name
	ev.Parent = container
	return ev
end
local AirSupportUnlocked = ensureBindable(BindableEvents, "AirSupportUnlocked")
local AirSupportRevoked  = ensureBindable(BindableEvents, "AirSupportRevoked")
local RequestReloadFromCurrent = BindableEvents:FindFirstChild("RequestReloadFromCurrent")
local NetworksPostLoad         = BindableEvents:FindFirstChild("NetworksPostLoad")

local AirTrafficFolder = Workspace:FindFirstChild("AirTraffic")
if not AirTrafficFolder then
	AirTrafficFolder = Instance.new("Folder")
	AirTrafficFolder.Name = "AirTraffic"
	AirTrafficFolder.Parent = Workspace
end

-- Utility: player plot lookup
local function getPlayerPlot(player: Player): Model?
	local plots = Workspace:FindFirstChild("PlayerPlots")
	if not plots then return nil end
	return plots:FindFirstChild("Plot_" .. player.UserId)
end

local function isAirportName(name: string): boolean
	return name == "Airport" or name == "Airfield"
end

-- Anchor discovery inside an airport model
local function findAnchors(airportModel: Model)
	if not airportModel or not airportModel:IsA("Model") then return nil end

	-- Prefer anchors directly under the airport model; fall back to the old Meshes/Airport_SPW... path.
	local function findPart(name: string): BasePart?
		-- direct child (requested change)
		local direct = airportModel:FindFirstChild(name)
		if direct and direct:IsA("BasePart") then return direct end

		-- legacy path under Meshes/Airport_SPW_Urban_Airport_Runway
		local meshes = airportModel:FindFirstChild("Meshes")
		local runwayContainer = (meshes and meshes:FindFirstChild("Airport_SPW_Urban_Airport_Runway"))
			or airportModel:FindFirstChild("Airport_SPW_Urban_Airport_Runway", true)
		if runwayContainer then
			local p = runwayContainer:FindFirstChild(name) or runwayContainer:FindFirstChild(name, true)
			if p and p:IsA("BasePart") then return p end
		end

		-- last resort: any descendant by name
		local deep = airportModel:FindFirstChild(name, true)
		if deep and deep:IsA("BasePart") then return deep end
		return nil
	end

	local anchors = {
		bunker  = findPart("Bunker"),
		bunker2 = findPart("Bunker2"),
		tug     = findPart("Tug"),
		tug2    = findPart("Tug2"),
		runway  = findPart("Runway"),
	}

	if not anchors.runway then return nil end
	if not (anchors.bunker or anchors.bunker2) then return nil end
	if not anchors.tug then return nil end

	return anchors
end

local function collectAirportAnchors(player: Player)
	local airports = {}
	local plot = getPlayerPlot(player)
	if not plot then return airports end

	for _, inst in ipairs(plot:GetDescendants()) do
		if inst:IsA("Model") and isAirportName(inst.Name) then
			local anchors = findAnchors(inst)
			if anchors then
				table.insert(airports, { model = inst, anchors = anchors })
			end
		end
	end
	return airports
end

-- Plane selection
local planeTemplates = {}
for _, name in ipairs({ "PlaneSmallBlue", "PlaneSmallRed" }) do
	local tpl = AirRoot:FindFirstChild(name)
	if tpl then table.insert(planeTemplates, tpl) end
end

local function pickPlaneTemplate()
	if #planeTemplates == 0 then return nil end
	return planeTemplates[math.random(1, #planeTemplates)]
end

local globalCount = 0
local ctxByUserId = {}

local function destroyPlane(ctx, plane)
	if plane and plane.Parent then
		pcall(function() plane:Destroy() end)
	end
	if ctx and ctx.planes and ctx.planes[plane] then
		ctx.planes[plane] = nil
		ctx.planeCount = math.max(0, (ctx.planeCount or 1) - 1)
		globalCount = math.max(0, globalCount - 1)
	end
end

local function computeLook(pos: Vector3, dir: Vector3)
	local dirFlat = dir
	if not dirFlat or dirFlat.Magnitude < 1e-3 then
		dirFlat = Vector3.new(0, 0, -1)
	else
		dirFlat = dirFlat.Unit
	end
	local cf = CFrame.lookAt(pos, pos + dirFlat, Vector3.new(0, 1, 0))
	if PLANE_YAW_OFFSET ~= 0 then
		cf *= CFrame.Angles(0, math.rad(PLANE_YAW_OFFSET), 0)
	end
	return cf
end

-- Move a plane through a list of points at constant speed. Returns false if aborted.
local function moveThroughPoints(ctx, plane, points: {Vector3}, speed: number, forwardDirs: {Vector3}?)
	if not plane or not plane.Parent or #points < 2 then return false end

	local function pickDir(idx, fallback)
		local d = forwardDirs and forwardDirs[idx]
		if d and d.Magnitude >= 1e-3 then return d.Unit end
		if fallback and fallback.Magnitude >= 1e-3 then return fallback.Unit end
		return Vector3.new(0, 0, -1)
	end

	for i = 1, #points - 1 do
		local a = points[i]
		local b = points[i + 1]
		local delta = b - a
		local segLen = delta.Magnitude
		local segDir = segLen >= 1e-3 and (delta / segLen) or Vector3.new(0, 0, -1)
		local startDir = pickDir(i, segDir)
		local endDir   = pickDir(i + 1, segDir)

		if segLen < 1e-3 then
			plane:PivotTo(computeLook(b, endDir))
			continue
		end

		local duration = math.max(0.05, segLen / speed)
		local startTime = time()

		while true do
			if not plane.Parent or ctx.suspended then
				return false
			end
			local t = math.clamp((time() - startTime) / duration, 0, 1)
			local pos = a + delta * t
			local dir = (startDir:Lerp(endDir, t))
			if dir.Magnitude < 1e-3 then dir = segDir end
			plane:PivotTo(computeLook(pos, dir))
			if t >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end
	end
	return true
end

-- Parabolic takeoff arc to a target point (world space)
local function takeoff(ctx, plane, startPos: Vector3, targetPos: Vector3)
	if not plane or not plane.Parent then
		destroyPlane(ctx, plane)
		return
	end

	local flatDir = Vector3.new(targetPos.X - startPos.X, 0, targetPos.Z - startPos.Z)
	if flatDir.Magnitude < 1e-3 then
		flatDir = Vector3.new(0, 0, -1)
	else
		flatDir = flatDir.Unit
	end

	local duration = math.max(2.5, (targetPos - startPos).Magnitude / TAKEOFF_SPEED)
	local control = (startPos + targetPos) * 0.5 + Vector3.new(0, TAKEOFF_ARC_HEIGHT, 0)
	local startTime = time()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not plane.Parent or ctx.suspended then
			if conn then conn:Disconnect() end
			destroyPlane(ctx, plane)
			return
		end

		local t = math.clamp((time() - startTime) / duration, 0, 1)
		-- Quadratic Bezier
		local p0 = startPos
		local p1 = control
		local p2 = targetPos
		local oneMinus = 1 - t
		local pos = oneMinus * oneMinus * p0 + 2 * oneMinus * t * p1 + t * t * p2
		-- Derivative for facing
		local dp = 2 * oneMinus * (p1 - p0) + 2 * t * (p2 - p1)
		if dp.Magnitude < 1e-3 then dp = flatDir end
		plane:PivotTo(computeLook(pos, dp))

		if t >= 1 then
			if conn then conn:Disconnect() end
			Debris:AddItem(plane, 2)
			destroyPlane(ctx, plane)
		end
	end)
end

local function chooseAirport(ctx, airports)
	if #airports == 0 then return nil end
	ctx.lastAirportIndex = (ctx.lastAirportIndex or 0) + 1
	if ctx.lastAirportIndex > #airports then ctx.lastAirportIndex = 1 end
	return airports[ctx.lastAirportIndex]
end

-- Base local offsets (relative to the bunker start) derived from the provided example airport.
local BASE_OFFSETS = {
	Vector3.new(0, 0, 0),
	Vector3.new(1.316, -0.095, -4.086),
	Vector3.new(1.316, -0.095, -4.086),
	Vector3.new(1.316, -0.095, -16.486),
	Vector3.new(1.316, -0.095, -16.486),
	Vector3.new(-1.477, 0.107, -18.75),
}
local TAKEOFF_OFFSET = Vector3.new(-35.588, 2.577, -18.75)
local BASE_FORWARD_VECS = {
	Vector3.new(0, 0, -4.141),
	Vector3.new(-2.069, -29.935, -3.588),
	Vector3.new(0, 0, -4.141),
	Vector3.new(0, 0, -4.141),
	Vector3.new(2.069, 29.935, -3.588),
	Vector3.new(4.141, 90, 0),
}

local function buildPathPoints(airportModel: Model, startPart: BasePart?)
	if not airportModel or not startPart then return nil end
	local pivotCF = airportModel:GetPivot()
	local startLocal = pivotCF:PointToObjectSpace(startPart.Position)

	local pts = {}
	local fwds = {}
	for _, off in ipairs(BASE_OFFSETS) do
		local p = startLocal + off
		table.insert(pts, pivotCF:PointToWorldSpace(p))
	end
	for _, dir in ipairs(BASE_FORWARD_VECS) do
		local d = dir
		if d.Magnitude < 1e-3 then
			d = Vector3.new(0, 0, -1)
		end
		table.insert(fwds, pivotCF:VectorToWorldSpace(d).Unit)
	end
	local takeoffTarget = pivotCF:PointToWorldSpace(startLocal + TAKEOFF_OFFSET)
	return pts, takeoffTarget, fwds
end

local function launchPlane(player: Player, ctx)
	if ctx.suspended or not ctx.allowed then return end
	if globalCount >= GLOBAL_CAP or (ctx.planeCount or 0) >= PER_PLAYER_CAP then return end

	local airports = collectAirportAnchors(player)
	if #airports == 0 then return end
	local airport = chooseAirport(ctx, airports)
	if not airport then return end
	local anchors = airport.anchors

	local useBunker2 = anchors.bunker2 and anchors.tug2 and (math.random() < 0.5)
	local startPart = (useBunker2 and anchors.bunker2) or anchors.bunker
	if not startPart then return end

	local path, takeoffTarget, fwds = buildPathPoints(airport.model, startPart)
	if not path or not takeoffTarget then return end

	local template = pickPlaneTemplate()
	if not template then
		log("No plane template available; aborting spawn.")
		return
	end

	local plane = template:Clone()
	local primary = plane.PrimaryPart or plane:FindFirstChildWhichIsA("BasePart", true)
	if not primary then
		plane:Destroy()
		return
	end
	plane.PrimaryPart = primary
	primary.Anchored = true
	plane:SetAttribute("IsAirTraffic", true)
	plane:SetAttribute("PlaneOwner", player.UserId)
	plane.Parent = AirTrafficFolder

	local initialDir = (fwds and fwds[1]) or ((path[2] or anchors.runway.Position) - path[1])
	plane:PivotTo(computeLook(path[1], initialDir))

	ctx.planes[plane] = true
	ctx.planeCount = (ctx.planeCount or 0) + 1
	globalCount += 1

	task.spawn(function()
		local ok = moveThroughPoints(ctx, plane, path, TAXI_SPEED, fwds)
		if ok and plane and plane.Parent then
			takeoff(ctx, plane, path[#path], takeoffTarget)
		else
			destroyPlane(ctx, plane)
		end
	end)
end

local function ensureLoop(player: Player)
	local uid = player.UserId
	local ctx = ctxByUserId[uid]
	if not ctx or ctx.loopRunning then return end

	ctx.loopRunning = true
	task.spawn(function()
		while ctx.loopRunning do
			if ctx.suspended or not ctx.allowed then
				task.wait(1)
			else
				launchPlane(player, ctx)
				task.wait(math.random(MIN_SPAWN_DELAY, MAX_SPAWN_DELAY))
			end
		end
	end)
end

local function stopLoop(ctx)
	if not ctx then return end
	ctx.loopRunning = false
end

local function clearPlanes(ctx)
	if not ctx or not ctx.planes then return end
	for plane in pairs(ctx.planes) do
		destroyPlane(ctx, plane)
	end
end

local function suspendPlayer(player: Player)
	local ctx = ctxByUserId[player.UserId]
	if not ctx then return end
	ctx.suspended = true
	clearPlanes(ctx)
end

local function resumePlayer(player: Player)
	local ctx = ctxByUserId[player.UserId]
	if not ctx then return end
	ctx.suspended = false
end

local function onSupportUnlocked(player: Player)
	local uid = player.UserId
	local ctx = ctxByUserId[uid]
	if not ctx then
		ctx = {
			planes = {},
			planeCount = 0,
			suspended = false,
			allowed = true,
			loopRunning = false,
			lastAirportIndex = 0,
		}
		ctxByUserId[uid] = ctx
	else
		ctx.allowed = true
	end
	ensureLoop(player)
end

local function onSupportRevoked(player: Player)
	local uid = player.UserId
	local ctx = ctxByUserId[uid]
	if not ctx then return end
	ctx.allowed = false
	ctx.suspended = true
	stopLoop(ctx)
	clearPlanes(ctx)
end

local function onPlayerAdded(player: Player)
	ctxByUserId[player.UserId] = {
		planes = {},
		planeCount = 0,
		suspended = false,
		allowed = false,
		loopRunning = false,
		lastAirportIndex = 0,
	}

	-- If the player already owns an airport, enable immediately.
	task.defer(function()
		local counts = ZoneTracker.getZoneTypeCounts(player)
		if counts and (counts.Airport or 0) > 0 then
			onSupportUnlocked(player)
		end
	end)
end

local function onPlayerRemoving(player: Player)
	local uid = player.UserId
	local ctx = ctxByUserId[uid]
	if ctx then
		stopLoop(ctx)
		ctx.suspended = true
		clearPlanes(ctx)
		ctxByUserId[uid] = nil
	end
end

-- Bindable gates for saving/loading
if RequestReloadFromCurrent then
	RequestReloadFromCurrent.Event:Connect(function(player: Player)
		if player then suspendPlayer(player) end
	end)
end

local function attachNetworksPostLoad(ev)
	if ev and ev.IsA and ev:IsA("BindableEvent") then
		ev.Event:Connect(function(player: Player)
			if player then
				resumePlayer(player)
				ensureLoop(player)
			end
		end)
	end
end
attachNetworksPostLoad(NetworksPostLoad)
BindableEvents.ChildAdded:Connect(function(ch)
	if ch.Name == "NetworksPostLoad" and ch:IsA("BindableEvent") then
		attachNetworksPostLoad(ch)
	end
end)

-- Unlock listeners
AirSupportUnlocked.Event:Connect(function(player: Player)
	if player then onSupportUnlocked(player) end
end)
AirSupportRevoked.Event:Connect(function(player: Player)
	if player then onSupportRevoked(player) end
end)

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, p in ipairs(Players:GetPlayers()) do
	onPlayerAdded(p)
end

-- Periodic refresh of eligibility (in case counts change unexpectedly)
task.spawn(function()
	while true do
		task.wait(20)
		for _, p in ipairs(Players:GetPlayers()) do
			local ctx = ctxByUserId[p.UserId]
			if ctx and not ctx.allowed then
				local counts = ZoneTracker.getZoneTypeCounts(p)
				if counts and (counts.Airport or 0) > 0 then
					onSupportUnlocked(p)
				end
			end
		end
	end
end)

print(string.format("[AirTraffic] online - cap per-player=%d, global=%d", PER_PLAYER_CAP, GLOBAL_CAP))
