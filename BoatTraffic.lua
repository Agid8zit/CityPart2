-- BoatTraffic.lua
-- Lightweight boat spawner independent of UnifiedTraffic.
-- Spawns 1–2 boats per player (max 8 global) once the player owns Unlock_6/7/8.
-- Boats travel from Alcatraz1/2 to the nearest matching ROCKS marker for the player’s plot.

local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")
local RunService        = game:GetService("RunService")

local BindableEvents = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents")
local GetUnlocksForPlayer = BindableEvents:FindFirstChild("GetUnlocksForPlayer") -- BindableFunction
local UnlockChanged       = BindableEvents:FindFirstChild("UnlockChanged")       -- BindableEvent
local RequestReloadFromCurrentEvt = BindableEvents:FindFirstChild("RequestReloadFromCurrent")
local NetworksPostLoadEvt         = BindableEvents:FindFirstChild("NetworksPostLoad")

local ZoneTrackerModule = require(game.ServerScriptService.Build.Zones.ZoneManager.ZoneTracker)

-- Assets
local BoatsRoot = ReplicatedStorage:WaitForChild("FuncTestGroundRS"):WaitForChild("Boats")
local DevRoot   = Workspace:WaitForChild("_Dev")
local Alcatraz = {
	[1] = DevRoot:WaitForChild("Alcatraz1"),
	[2] = DevRoot:WaitForChild("Alcatraz2"),
}
local RocksFolder = DevRoot:WaitForChild("ROCKS")

-- Config
local PER_PLAYER_CAP = 2
local GLOBAL_CAP     = 8
local MIN_SPAWN_DELAY = 8
local MAX_SPAWN_DELAY = 14
local BOAT_SPEED_STUDS_PER_SEC = 40
local BOAT_WATERLINE_Y = 4.4
local HEADING_Y_OFFSET_DEG = -90 -- boat model forward needs this yaw offset to align with travel vector
local FREEZE_MOVEMENT = false -- set true to stop tweening for spawn/facing tuning
local FROZEN_LIFETIME = 180   -- safety cleanup when frozen (seconds)
local REQUIRED_UNLOCKS = { "Unlock_6", "Unlock_7", "Unlock_8" }
local BASE_BOAT_COUNT = 8 -- Boat1..Boat8
local SPECIAL_WEIGHT  = 3 -- bias for dense boats over randoms

-- Optional runtime toggle (BindableEvents/BoatTrafficFreeze boolean)
local function setFreeze(on)
	FREEZE_MOVEMENT = not not on
end
do
	local evt = BindableEvents:FindFirstChild("BoatTrafficFreeze")
	if evt and evt.IsA and evt:IsA("BindableEvent") then
		evt.Event:Connect(setFreeze)
	end
end

-- Placeholder anchors (captured at startup for plot→rock lookup)
local placeholderAnchors = {}
do
	local plotsFolder = Workspace:FindFirstChild("Plots")
	if plotsFolder then
		for _, placeholder in ipairs(plotsFolder:GetChildren()) do
			local num = tonumber(placeholder.Name:match("Plot(%d+)"))
			local pp = placeholder.PrimaryPart or placeholder:FindFirstChildWhichIsA("BasePart", true)
			if num and pp then
				table.insert(placeholderAnchors, {
					index = num,
					pos   = pp.Position,
				})
			end
		end
	end
end

-- Parse rocks into a table once
local rockTargets = {}
local rockById = {}
for _, inst in ipairs(RocksFolder:GetChildren()) do
	if inst:IsA("BasePart") or inst:IsA("Model") then
		local name = inst.Name
		local prefix, plotsStr, suffix = name:match("^(A[12])P(%d+)([A-Za-z]*)$")
		if prefix and plotsStr then
			local plots = {}
			for digit in plotsStr:gmatch("%d") do
				local n = tonumber(digit)
				if n then plots[n] = true end
			end
			local rec = {
				id       = name,
				alcatraz = tonumber(prefix:sub(2)),
				part     = inst:IsA("Model") and inst.PrimaryPart or inst,
				plots    = plots,
			}
			table.insert(rockTargets, rec)
			rockById[name] = rec
		end
	end
end

-- Detour specs for every marked "hypotenuse" note; each target rock lists anchors it must pass through.
local DETOUR_SPECS = {
	A1P1B = { anchors = { "A1P1Y" }, wavy = true },
	A1P1R = { anchors = { "A1P1Y" }, wavy = true },
	A1P7I = { anchors = { "A1P7V" }, wavy = true },
	A1P7Y = { anchors = { "A1P7V" }, wavy = true },
	A2P2B = { anchors = { "A2P2Q" }, wavy = true },
	A2P2Z = { anchors = { "A2P2Q" }, wavy = true },
	A2P8J = { anchors = { "A2P8T" }, wavy = true },
	A2P8Z = { anchors = { "A2P8T" }, wavy = true },
}

local function getPlayerPlot(player: Player): Model?
	local plots = Workspace:FindFirstChild("PlayerPlots")
	if not plots then return nil end
	return plots:FindFirstChild("Plot_" .. player.UserId)
end

local function nearestPlaceholderIndex(plot: Model?): number?
	if not plot or #placeholderAnchors == 0 then return nil end
	local pivot = plot:GetPivot()
	local bestIdx, bestDist
	for _, rec in ipairs(placeholderAnchors) do
		local d = (rec.pos - pivot.Position).Magnitude
		if not bestDist or d < bestDist then
			bestDist = d
			bestIdx  = rec.index
		end
	end
	return bestIdx
end

local function chooseRockTarget(player: Player, ctx)
	local plot = getPlayerPlot(player)
	if not plot or #rockTargets == 0 then return nil end
	local placeholderIdx = nearestPlaceholderIndex(plot)

	local matches = {}
	local fallback = {}
	for _, rec in ipairs(rockTargets) do
		local part = rec.part
		if part then
			if placeholderIdx and rec.plots[placeholderIdx] then
				table.insert(matches, rec)
			end
			table.insert(fallback, rec)
		end
	end
	local pool = (#matches > 0) and matches or fallback
	if #pool == 0 then return nil end

	-- Avoid repeating the exact same rock consecutively if we have choices
	local idx = math.random(1, #pool)
	if ctx and ctx.lastRockId and #pool > 1 then
		for i = 1, #pool do
			local cand = pool[idx]
			if cand.id ~= ctx.lastRockId then break end
			idx = (idx % #pool) + 1
		end
	end
	local picked = pool[idx]
	if ctx then ctx.lastRockId = picked and picked.id or nil end
	return picked
end

local function hasRequiredUnlocks(player: Player): boolean
	if not (GetUnlocksForPlayer and GetUnlocksForPlayer.Invoke) then
		return false
	end
	local ok, unlocks = pcall(function()
		return GetUnlocksForPlayer:Invoke(player)
	end)
	if not ok or type(unlocks) ~= "table" then
		return false
	end
	for _, key in ipairs(REQUIRED_UNLOCKS) do
		if not unlocks[key] then
			return false
		end
	end
	return true
end

local function buildBoatPool(player: Player)
	local pool = {}
	for i = 1, BASE_BOAT_COUNT do
		local node = BoatsRoot:FindFirstChild("Boat" .. tostring(i))
		if node then
			table.insert(pool, { model = node, weight = 1 })
		end
	end

	local counts = ZoneTrackerModule.getZoneTypeCounts(player) or {}
	local function addSpecial(name, present)
		if not present then return end
		local node = BoatsRoot:FindFirstChild(name)
		if node then
			table.insert(pool, { model = node, weight = SPECIAL_WEIGHT })
		end
	end

	addSpecial("BoatResDense", counts.ResDense and counts.ResDense > 0)
	addSpecial("BoatCommDense", counts.CommDense and counts.CommDense > 0)
	addSpecial("BoatIndusDense", counts.IndusDense and counts.IndusDense > 0)

	return pool
end

local function pickBoatTemplate(pool)
	local total = 0
	for _, rec in ipairs(pool) do
		total += (rec.weight or 1)
	end
	if total <= 0 then return nil end
	local r = math.random() * total
	for _, rec in ipairs(pool) do
		r -= (rec.weight or 1)
		if r <= 0 then
			return rec.model
		end
	end
	return pool[#pool] and pool[#pool].model or nil
end

local globalCount = 0
local ctxByUserId = {}

local function destroyBoat(ctx, boat)
	if not ctx or not boat then return end
	if boat.Parent then boat:Destroy() end
	if ctx.boats and ctx.boats[boat] then
		ctx.boats[boat] = nil
		ctx.boatCount = math.max(0, (ctx.boatCount or 1) - 1)
		globalCount = math.max(0, globalCount - 1)
	end
end

local function fadeAndDestroy(ctx, boat, duration)
	if not (boat and boat.PrimaryPart) then
		destroyBoat(ctx, boat)
		return
	end
	local pp = boat.PrimaryPart
	local tween = TweenService:Create(pp, TweenInfo.new(duration or 0.6), { Transparency = 1 })
	tween:Play()
	tween.Completed:Connect(function()
		destroyBoat(ctx, boat)
	end)
end

local BoatFolder = Workspace:FindFirstChild("BoatTraffic")
if not BoatFolder then
	BoatFolder = Instance.new("Folder")
	BoatFolder.Name = "BoatTraffic"
	BoatFolder.Parent = Workspace
end

local function findRockById(id: string)
	return id and rockById[id]
end

local function flattenToWaterline(pos: Vector3)
	return Vector3.new(pos.X, BOAT_WATERLINE_Y or pos.Y, pos.Z)
end

-- Compute a perpendicular detour anchor between two points (XZ plane).
-- Useful when no explicit detour marker exists: pushes path around land corners.
local function perpendicularAnchorBetween(a: Vector3, b: Vector3, side: number?)
	local delta = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local mag = delta.Magnitude
	if mag < 1e-3 then return nil end

	local dir = delta / mag
	local perp = Vector3.new(-dir.Z, 0, dir.X) * (side or 1)
	local offset = math.clamp(mag * 0.35, 40, 180)
	local mid = (a + b) * 0.5

	return flattenToWaterline(mid + perp * offset)
end

local function buildPathEvaluator(points: { Vector3 }, applyWave: boolean)
	points = points or {}
	if #points < 2 then
		local a = points[1] or Vector3.new()
		local b = points[2] or a
		local delta = b - a
		return function(t: number)
			return a + delta * t, delta
		end, delta.Magnitude
	end

	-- Precompute tangents for Hermite interpolation to force passing through control anchors.
	local tangents = {}
	for i = 1, #points do
		local prev = points[i - 1] or points[i]
		local next = points[i + 1] or points[i]
		tangents[i] = (next - prev) * 0.5
	end

	-- Base segment lengths (chord lengths) to map t -> segment
	local segMeta = {}
	local chordTotal = 0
	for i = 1, #points - 1 do
		local len = (points[i + 1] - points[i]).Magnitude
		segMeta[i] = {
			p0 = points[i],
			p1 = points[i + 1],
			m0 = tangents[i],
			m1 = tangents[i + 1],
			chord = len,
		}
		chordTotal += len
	end
	if chordTotal < 1e-3 then chordTotal = 1 end

	local function hermite(p0, p1, m0, m1, u)
		local u2 = u * u
		local u3 = u2 * u
		local h00 = 2 * u3 - 3 * u2 + 1
		local h10 = u3 - 2 * u2 + u
		local h01 = -2 * u3 + 3 * u2
		local h11 = u3 - u2
		local pos = p0 * h00 + m0 * h10 + p1 * h01 + m1 * h11

		local dh00 = 6 * u2 - 6 * u
		local dh10 = 3 * u2 - 4 * u + 1
		local dh01 = -6 * u2 + 6 * u
		local dh11 = 3 * u2 - 2 * u
		local tan = p0 * dh00 + m0 * dh10 + p1 * dh01 + m1 * dh11
		return pos, tan
	end

	local function rawEval(t: number)
		if t <= 0 then
			local seg = segMeta[1]
			return hermite(seg.p0, seg.p1, seg.m0, seg.m1, 0)
		end
		if t >= 1 then
			local seg = segMeta[#segMeta]
			return hermite(seg.p0, seg.p1, seg.m0, seg.m1, 1)
		end

		local distance = t * chordTotal
		local acc = 0
		local segIndex = 1
		for i = 1, #segMeta do
			local nextAcc = acc + segMeta[i].chord
			if distance <= nextAcc then
				segIndex = i
				break
			end
			acc = nextAcc
		end

		local seg = segMeta[segIndex]
		local segLen = seg.chord > 1e-3 and seg.chord or 1
		local u = (distance - acc) / segLen
		local pos, tan = hermite(seg.p0, seg.p1, seg.m0, seg.m1, u)

		if applyWave then
			local side = Vector3.new(tan.Z, 0, -tan.X)
			local sideMag = side.Magnitude
			if sideMag > 1e-3 then
				side = side / sideMag
				-- Keep the wave subtle relative to the segment chord length.
				local amp = math.clamp(segLen * 0.4, 20, 250)
				-- Use sin^2 so derivative is zero at endpoints (keeps initial facing aligned).
				local s = math.sin(math.pi * u)
				local wave = (s * s) * amp
				pos += side * wave
				tan += side * (amp * math.pi * math.sin(2 * math.pi * u))
			end
		end

		return pos, tan
	end

	-- Build an arc-length table so movement stays roughly constant-speed across curves.
	local samples = math.max(64, (#segMeta) * 32)
	local tSamples = {}
	local lenSamples = {}
	local prevPos = select(1, rawEval(0))
	local accum = 0
	for i = 0, samples do
		local t = i / samples
		local pos = select(1, rawEval(t))
		if i > 0 then
			accum += (pos - prevPos).Magnitude
		end
		prevPos = pos
		tSamples[i + 1] = t
		lenSamples[i + 1] = accum
	end
	local totalLen = accum
	if totalLen < 1e-5 then
		-- Degenerate path; just fall back to the raw evaluator without arc remap.
		return rawEval, math.max(totalLen, 0)
	end

	local function evalByArc(tNorm: number)
		if tNorm <= 0 then
			return rawEval(0)
		elseif tNorm >= 1 then
			return rawEval(1)
		end

		local targetLen = tNorm * totalLen
		-- binary search in lenSamples
		local lo, hi = 1, #lenSamples
		while hi - lo > 1 do
			local mid = math.floor((lo + hi) * 0.5)
			if lenSamples[mid] < targetLen then
				lo = mid
			else
				hi = mid
			end
		end

		local lenLo = lenSamples[lo]
		local lenHi = lenSamples[hi]
		local tLo = tSamples[lo]
		local tHi = tSamples[hi]
		local segLen = lenHi - lenLo
		if segLen < 1e-6 then
			return rawEval(tLo)
		end

		local alpha = (targetLen - lenLo) / segLen
		local tInterp = tLo + (tHi - tLo) * alpha
		return rawEval(tInterp)
	end

	return evalByArc, totalLen
end

local function initialBoatFrame(pathEval, headingDir: Vector3?)
	local pos, tangent = pathEval(0)
	local dir = headingDir
	if not dir or dir.Magnitude < 1e-3 then
		dir = Vector3.new(tangent.X, 0, tangent.Z)
	end
	if dir.Magnitude < 1e-3 then
		dir = Vector3.new(0, 0, -1)
	else
		dir = dir.Unit
	end
	return CFrame.lookAt(pos, pos + dir, Vector3.new(0, 1, 0)) * CFrame.Angles(0, math.rad(HEADING_Y_OFFSET_DEG), 0)
end

local function runBoatPath(ctx, boat, pathEval, pathLength, headingDir: Vector3?)
	if not (boat and boat.PrimaryPart) then
		destroyBoat(ctx, boat)
		return
	end

	if FREEZE_MOVEMENT then
		boat:SetAttribute("BoatFrozen", true)
		boat.PrimaryPart.Anchored = true
		Debris:AddItem(boat, FROZEN_LIFETIME)
		return
	end

	local duration = math.max(2, pathLength / BOAT_SPEED_STUDS_PER_SEC)
	local startTime = time()
	local cancelled = false
	local lastDir = Vector3.new(0, 0, -1)
	local hbConn

	local function finalize(fadeOut: boolean)
		if cancelled then return end
		cancelled = true
		if hbConn then hbConn:Disconnect() end
		if fadeOut then
			fadeAndDestroy(ctx, boat, 0.6)
		else
			destroyBoat(ctx, boat)
		end
	end

	hbConn = RunService.Heartbeat:Connect(function()
		if cancelled then return end
		local t = math.clamp((time() - startTime) / duration, 0, 1)
		local pos, tangent = pathEval(t)
		local dir = headingDir
		if not dir or dir.Magnitude < 1e-3 then
			dir = Vector3.new(tangent.X, 0, tangent.Z)
		end
		if dir.Magnitude < 1e-3 then
			dir = lastDir
		else
			dir = dir.Unit
			lastDir = dir
		end

		boat:PivotTo(CFrame.lookAt(pos, pos + dir, Vector3.new(0, 1, 0)) * CFrame.Angles(0, math.rad(HEADING_Y_OFFSET_DEG), 0))

		if t >= 1 then
			finalize(true)
		end
	end)

	task.delay(duration + 5, function()
		if not cancelled then
			finalize(true)
		end
	end)

	boat.AncestryChanged:Connect(function(_, parent)
		if not parent then
			finalize(false)
		end
	end)
end

local function launchBoat(player: Player, ctx)
	if ctx.suspended or not ctx.unlocksReady then return end
	if globalCount >= GLOBAL_CAP or (ctx.boatCount or 0) >= PER_PLAYER_CAP then
		return
	end

	local rock = chooseRockTarget(player, ctx)
	if not rock or not rock.part then return end
	local startModel = Alcatraz[rock.alcatraz]
	if not startModel then return end
	local startPart = startModel.PrimaryPart or startModel:FindFirstChildWhichIsA("BasePart", true)
	if not startPart then return end

	local pool = buildBoatPool(player)
	local template = pickBoatTemplate(pool)
	if not template then return end

	local boat = template:Clone()
	local primary = boat.PrimaryPart or boat:FindFirstChildWhichIsA("BasePart", true)
	if not primary then
		boat:Destroy()
		return
	end
	boat.PrimaryPart = primary
	primary.Anchored = true
	boat:SetAttribute("IsBoatTraffic", true)
	boat:SetAttribute("BoatOwner", player.UserId)
	boat.Parent = BoatFolder

	local startPos = flattenToWaterline(startPart.Position)
	local targetPos = flattenToWaterline(rock.part.Position)

	local points = { startPos }
	local useWave = false

	local detourSpec = DETOUR_SPECS[rock.id]
	local detourAdded = false
	if detourSpec and detourSpec.anchors then
		for _, anchorId in ipairs(detourSpec.anchors) do
			local detour = findRockById(anchorId)
			if detour and detour.part then
				table.insert(points, flattenToWaterline(detour.part.Position))
				detourAdded = true
			end
		end
		useWave = (detourSpec.wavy == nil) and true or detourSpec.wavy
	end

	-- If this is a marked detour but no explicit anchor was found, synthesize a perpendicular bend.
	if detourSpec and not detourAdded then
		local perp = perpendicularAnchorBetween(startPos, targetPos, detourSpec.side)
		if perp then
			table.insert(points, perp)
			detourAdded = true
			useWave = true
		end
	end

	table.insert(points, targetPos)
	if #points > 2 then
		useWave = true
	end

	-- For detours (curved paths), allow heading to follow the path tangent; otherwise lock to straight vector.
	local headingDir
	if not detourSpec then
		headingDir = Vector3.new(targetPos.X - startPos.X, 0, targetPos.Z - startPos.Z)
		if headingDir.Magnitude > 1e-3 then
			headingDir = headingDir.Unit
		else
			headingDir = Vector3.new(0, 0, -1)
		end
	end

	local pathEval, pathLength = buildPathEvaluator(points, useWave)
	boat:PivotTo(initialBoatFrame(pathEval, headingDir))

	ctx.boats[boat] = true
	ctx.boatCount = (ctx.boatCount or 0) + 1
	globalCount += 1

	runBoatPath(ctx, boat, pathEval, pathLength, headingDir)
end

local function ensureLoop(player: Player)
	local uid = player.UserId
	local ctx = ctxByUserId[uid]
	if not ctx or ctx.loopRunning then return end

	ctx.loopRunning = true
	task.spawn(function()
		while ctx.loopRunning do
			if ctx.suspended or not ctx.unlocksReady then
				task.wait(1.0)
			else
				launchBoat(player, ctx)
				task.wait(math.random(MIN_SPAWN_DELAY, MAX_SPAWN_DELAY))
			end
		end
	end)
end

local function stopLoop(ctx)
	if not ctx then return end
	ctx.loopRunning = false
end

local function clearBoats(ctx)
	if not ctx or not ctx.boats then return end
	for boat in pairs(ctx.boats) do
		destroyBoat(ctx, boat)
	end
end

local function refreshUnlockState(player: Player)
	local ctx = ctxByUserId[player.UserId]
	if not ctx then return end
	ctx.unlocksReady = hasRequiredUnlocks(player)
	if not ctx.unlocksReady then
		clearBoats(ctx)
	else
		ensureLoop(player)
	end
end

local function suspendPlayer(player: Player)
	local ctx = ctxByUserId[player.UserId]
	if not ctx then return end
	ctx.suspended = true
	clearBoats(ctx)
end

local function resumePlayer(player: Player)
	local ctx = ctxByUserId[player.UserId]
	if not ctx then return end
	ctx.suspended = false
	refreshUnlockState(player)
end

local function onPlayerAdded(player: Player)
	ctxByUserId[player.UserId] = {
		boats = {},
		boatCount = 0,
		suspended = false,
		unlocksReady = false,
	}
	refreshUnlockState(player)
	ensureLoop(player)
end

local function onPlayerRemoving(player: Player)
	local uid = player.UserId
	local ctx = ctxByUserId[uid]
	if ctx then
		stopLoop(ctx)
		ctx.suspended = true
		clearBoats(ctx)
		ctxByUserId[uid] = nil
	end
end

-- Unlock change listener
if UnlockChanged and UnlockChanged.Event then
	UnlockChanged.Event:Connect(function(player: Player, unlockName: string, state: boolean)
		if not player then return end
		for _, key in ipairs(REQUIRED_UNLOCKS) do
			if key == unlockName then
				refreshUnlockState(player)
				return
			end
		end
	end)
end

-- Save reload gates
if RequestReloadFromCurrentEvt then
	RequestReloadFromCurrentEvt.Event:Connect(function(player: Player)
		if player then suspendPlayer(player) end
	end)
end

local function attachNetworksPostLoad(ev)
	if ev and ev.IsA and ev:IsA("BindableEvent") then
		ev.Event:Connect(function(player: Player)
			if player then resumePlayer(player) end
		end)
	end
end
attachNetworksPostLoad(NetworksPostLoadEvt)
BindableEvents.ChildAdded:Connect(function(ch)
	if ch.Name == "NetworksPostLoad" and ch:IsA("BindableEvent") then
		attachNetworksPostLoad(ch)
	end
end)

-- Player lifecycle
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, p in ipairs(Players:GetPlayers()) do
	onPlayerAdded(p)
end

-- Periodic safety net to recalc unlock + zone state
task.spawn(function()
	while true do
		task.wait(30)
		for _, p in ipairs(Players:GetPlayers()) do
			refreshUnlockState(p)
		end
	end
end)

print("[BoatTraffic] online - gated by Unlock_6/7/8; cap per-player="..PER_PLAYER_CAP..", global="..GLOBAL_CAP)
