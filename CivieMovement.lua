local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunServiceScheduler = require(ReplicatedStorage.Scripts.RunServiceScheduler)

local CivilianMovement = {}

-- ---------- Facing helpers ----------
local function lookCF(fromPos: Vector3, toPos: Vector3): CFrame
	return CFrame.lookAt(fromPos, Vector3.new(toPos.X, fromPos.Y, toPos.Z))
end

local function flatDirXZ(a: Vector3, b: Vector3): Vector3
	local d = b - a
	d = Vector3.new(d.X, 0, d.Z)
	if d.Magnitude < 1e-6 then return Vector3.new(1,0,0) end
	return d.Unit
end

local function yawOnlyCF(fromPos: Vector3, faceDir: Vector3): CFrame
	local target = fromPos + Vector3.new(faceDir.X, 0, faceDir.Z)
	return CFrame.lookAt(fromPos, target)
end

local function yawDeltaDegrees(currentCF: CFrame, targetDirXZ: Vector3): number
	local cur = Vector3.new(currentCF.LookVector.X, 0, currentCF.LookVector.Z)
	if cur.Magnitude < 1e-6 then cur = Vector3.new(1,0,0) end
	cur = cur.Unit
	local dot = math.clamp(cur:Dot(targetDirXZ.Unit), -1, 1)
	return math.deg(math.acos(dot))
end

-- ---------- Config ----------
local CONFIG = {
	DefaultWalkSpeed = 3.5,
	FadeOutTime      = 1.25,
	Debug            = false,

	-- path smoothing
	MinStepStuds     = 0.25,
	SnapYToHRP       = true,

	-- animation
	WalkAnimationId  = "rbxassetid://121106814853748",
	BlendInTime      = 0.10,
	BlendOutTime     = 0.20,

	-- turning (smoother)
	TurnSpeedDegPerSec = 240,                         -- slower => smoother
	TurnTimeMin        = 0.12,
	TurnTimeMax        = 0.60,
	TurnEaseStyle      = Enum.EasingStyle.Quad,       -- smoother than Sine Out
	TurnEaseDirection  = Enum.EasingDirection.InOut,  -- ease-in/out
	PauseWalkAnimDuringTurn = false,                  -- keep loop visible; we’ll soften instead

	-- approach easing (Humanoid only)
	ApproachSlowRadius  = 2.0,  -- studs from node where we start easing
	ApproachSpeedFactor = 0.9,  -- % of WalkSpeed near node
}

local function dprint(...) if CONFIG.Debug then print("[CivilianMovement]", ...) end end
local function dwarn (...) if CONFIG.Debug then warn ("[CivilianMovement]", ...) end end

local approachMonitors = {}
local approachConn = nil

local function detachApproachConnection()
	if approachConn then
		disconnectHandle(approachConn)
		approachConn = nil
	end
end

local function removeApproachMonitor(key, info, restoreSpeed)
	local monitor = approachMonitors[key]
	if monitor then
		if restoreSpeed and monitor.humanoid then
			local base = monitor.baseWS or CONFIG.DefaultWalkSpeed
			monitor.humanoid.WalkSpeed = base
		end
		approachMonitors[key] = nil
	end
	if info then
		info.approachActive = nil
	end
	if approachConn and next(approachMonitors) == nil then
		detachApproachConnection()
	end
end

local function ensureApproachLoop()
	if approachConn then return end
	approachConn = RunServiceScheduler.onHeartbeat(function()
		if not next(approachMonitors) then
			detachApproachConnection()
			return
		end
		for key, monitor in pairs(approachMonitors) do
			local info = monitor.info
			if not info or info.cancelled or not monitor.hrp or not monitor.hrp.Parent then
				approachMonitors[key] = nil
			else
				local dist = (monitor.target - monitor.hrp.Position).Magnitude
				if dist <= CONFIG.ApproachSlowRadius and not monitor.slowed then
					monitor.slowed = true
					pcall(function()
						monitor.humanoid.WalkSpeed = math.max(0.1, monitor.baseWS * CONFIG.ApproachSpeedFactor)
					end)
					if monitor.track then
						pcall(function() monitor.track:AdjustSpeed(0.85) end)
					end
				end
				if dist <= 0.15 then
					approachMonitors[key] = nil
					info.approachActive = nil
				end
			end
		end
		if next(approachMonitors) == nil then
			detachApproachConnection()
		end
	end)
end

local function addApproachMonitor(key, info, hum, hrp, target, baseWS, track)
	approachMonitors[key] = {
		info = info,
		humanoid = hum,
		hrp = hrp,
		target = target,
		baseWS = baseWS,
		track = track,
		slowed = false,
	}
	info.approachActive = true
	ensureApproachLoop()
end

local function disconnectHandle(handle)
	if not handle then return end
	local handleType = typeof(handle)
	if handleType == "RBXScriptConnection" then
		local ok, err = pcall(function() handle:Disconnect() end)
		if not ok then warn("[CivilianMovement] Failed to disconnect connection:", err) end
	elseif handleType == "function" then
		local ok, err = pcall(handle)
		if not ok then warn("[CivilianMovement] Failed to run cleanup handler:", err) end
	end
end

-- activeMoves[key] = { conns={}, cancelled, animTrack, tween, runConn, moveConn, approachActive }
local activeMoves = {}

-- ---------- Rig helpers ----------
local function ensurePrimary(model)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp then model.PrimaryPart = hrp; return hrp end
	local any = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if any then model.PrimaryPart = any end
	return any
end

local function getHumanoid(model)
	return model:FindFirstChildWhichIsA("Humanoid")
end

local function getAnimator(model)
	local hum = getHumanoid(model)
	if hum then
		return hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 1)
	end
	local ac = model:FindFirstChildWhichIsA("AnimationController")
	if ac then
		return ac:FindFirstChildOfClass("Animator") or ac:WaitForChild("Animator", 1)
	end
	return nil
end

-- ---------- Animation control ----------
local function startWalkAnimation(model, key)
	local animator = getAnimator(model)
	if not animator then
		dwarn("No Animator/Humanoid found; cannot play walk animation")
		return nil
	end

	local anim = Instance.new("Animation")
	anim.Name = "LittleGuyWalk"
	anim.AnimationId = CONFIG.WalkAnimationId
	pcall(function() anim.Priority = Enum.AnimationPriority.Movement end)

	local track
	local ok, err = pcall(function() track = animator:LoadAnimation(anim) end)
	anim:Destroy()
	if not ok or not track then
		dwarn("Failed to load walk animation: ", err)
		return nil
	end

	track.Looped = true
	track:Play(CONFIG.BlendInTime)
	pcall(function()
		track:AdjustWeight(1, 0.05)
		track:AdjustSpeed(1.0)
	end)

	activeMoves[key].animTrack = track
	return track
end

local function ensureWalkPlaying(info, blend)
	local tr = info and info.animTrack
	if not tr then return end
	blend = blend or CONFIG.BlendInTime
	pcall(function()
		if not tr.IsPlaying then tr:Play(blend) end
		tr:AdjustSpeed(1.0)
		tr:AdjustWeight(1, 0.05)
	end)
end

local function stopWalkAnimation(key)
	local info = activeMoves[key]
	if not info then return end
	local tr = info.animTrack
	if tr then
		pcall(function() tr:Stop(CONFIG.BlendOutTime) end)
		pcall(function() tr:Destroy() end)
		info.animTrack = nil
	end
end

-- ---------- Path coalescing ----------
local function coalescePath(points, snapY, minStep)
	if not points or #points < 2 then return points end
	minStep = minStep or CONFIG.MinStepStuds

	local function flat(v) return Vector3.new(v.X, snapY or v.Y, v.Z) end
	local out = {}

	local prev = flat(points[1])
	local function pushIfFar(p)
		if (#out == 0) then out[1] = p return true end
		if (p - out[#out]).Magnitude >= minStep then
			out[#out+1] = p; return true
		end
		return false
	end
	pushIfFar(prev)

	local function dir(a,b)
		local d = (b - a); d = Vector3.new(d.X, 0, d.Z)
		local m = d.Magnitude
		if m < 1e-6 then return nil end
		return d / m
	end

	local lastDir = dir(prev, flat(points[2])) or Vector3.new(1,0,0)
	for i = 2, #points do
		local p = flat(points[i])
		local curDir = dir(prev, p)
		if not curDir then
			if i == #points then pushIfFar(p) end
		else
			local isTurn = (curDir - lastDir).Magnitude > 1e-3
			if isTurn then pushIfFar(prev); lastDir = curDir end
		end
		prev = p
	end
	pushIfFar(prev)

	if #out >= 2 then
		local cleaned = { out[1] }
		for i = 2, #out do
			if (out[i] - cleaned[#cleaned]).Magnitude >= minStep then
				cleaned[#cleaned+1] = out[i]
			end
		end
		out = cleaned
	end
	return out
end

-- ---------- Fade ----------
local function fadeOut(model, t, cb)
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("MeshPart") or d:IsA("Decal") then
			table.insert(parts, d)
		end
	end
	local info = TweenInfo.new(t, Enum.EasingStyle.Linear)
	local tweens = {}
	for _, p in ipairs(parts) do
		table.insert(tweens, TweenService:Create(p, info, {Transparency = 1}))
	end
	for _, tw in ipairs(tweens) do tw:Play() end
	if #tweens > 0 then
		tweens[1].Completed:Connect(function() if cb then cb() end end)
	else
		if cb then cb() end
	end
end

-- ---------- Turn tween helper (smoother) ----------
local function tweenTurnOnly(hrp: BasePart, targetDirXZ: Vector3, key: string, onComplete: ()->())
	local ang = yawDeltaDegrees(hrp.CFrame, targetDirXZ)
	local dur = math.clamp(ang / math.max(1, CONFIG.TurnSpeedDegPerSec), CONFIG.TurnTimeMin, CONFIG.TurnTimeMax)

	local targetCF = yawOnlyCF(hrp.Position, targetDirXZ)
	local info = TweenInfo.new(dur, CONFIG.TurnEaseStyle, CONFIG.TurnEaseDirection)
	local tw = TweenService:Create(hrp, info, {CFrame = targetCF})

	activeMoves[key].tween = tw
	tw.Completed:Connect(function()
		if activeMoves[key] and activeMoves[key].tween == tw then
			activeMoves[key].tween = nil
		end
		if onComplete then onComplete() end
	end)
	tw:Play()
end

-- ---------- Movement ----------
-- opts = { WalkSpeed?, OnComplete?, DestroyAtEnd? }
function CivilianMovement.moveAlongPath(model, points, key, opts)
	opts = opts or {}
	if not model or not points or #points < 1 then return end
	activeMoves[key] = activeMoves[key] or {
		conns = {}, cancelled = false, animTrack = nil, tween = nil,
		runConn = nil, moveConn = nil
	}

	local info = activeMoves[key]
	info.key = key
	local hrp = ensurePrimary(model)
	if not hrp then
		dwarn("Model has no PrimaryPart/HRP")
		if opts.OnComplete then opts.OnComplete(model) end
		return
	end

	local hum = getHumanoid(model)
	if hum then
		info.humanoid = hum
		info.origWalkSpeed = hum.WalkSpeed
		hum.WalkSpeed = math.max(0.1, tonumber(opts.WalkSpeed) or CONFIG.DefaultWalkSpeed)
		hum.AutoRotate = true
	else
		info.humanoid = nil
		info.origWalkSpeed = nil
		dwarn("Model has no Humanoid; falling back to tween")
	end

	-- Preprocess
	local targetY = CONFIG.SnapYToHRP and hrp.Position.Y or nil
	local path = coalescePath(points, targetY, CONFIG.MinStepStuds)
	if not path or #path < 2 then
		if opts.OnComplete then opts.OnComplete(model) end
		return
	end

	-- initial facing
	hrp.CFrame = yawOnlyCF(path[1], flatDirXZ(path[1], path[2]))

	-- Start walk animation
	local track = startWalkAnimation(model, key)

	local idx = 1

	local function finish()
		-- clean monitors
		if info.approachActive then
			removeApproachMonitor(key, info, true)
		end
		if info.runConn then pcall(function() info.runConn:Disconnect() end); info.runConn = nil end
		if info.moveConn then pcall(function() info.moveConn:Disconnect() end); info.moveConn = nil end

		if info.humanoid and info.origWalkSpeed then
			info.humanoid.WalkSpeed = info.origWalkSpeed
		end
		info.humanoid = nil
		info.origWalkSpeed = nil

		stopWalkAnimation(key)
		if opts.DestroyAtEnd then
			fadeOut(model, CONFIG.FadeOutTime, function()
				if model and model.Parent then model:Destroy() end
				if opts.OnComplete then opts.OnComplete(model) end
			end)
		else
			if opts.OnComplete then opts.OnComplete(model) end
		end
	end

	local function gotoNext()
		if info.cancelled then return end
		idx += 1
		if idx > #path then finish(); return end

		local target = path[idx]
		local faceDir = flatDirXZ(hrp.Position, target)

		-- 1) TURN-IN-PLACE (soften anim instead of pausing)
		if track then pcall(function() track:AdjustSpeed(0.8) end) end

		if hum then
			local prevAuto = hum.AutoRotate
			hum.AutoRotate = false

			tweenTurnOnly(hrp, faceDir, key, function()
				if info.cancelled then return end

				-- make sure walk is visibly running
				ensureWalkPlaying(info)

				-- guarantee yaw at move start
				hrp.CFrame = yawOnlyCF(hrp.Position, flatDirXZ(hrp.Position, target))

				-- 2) MOVE (approach easing)
				if info.moveConn then pcall(function() info.moveConn:Disconnect() end); info.moveConn = nil end
				if info.runConn  then pcall(function() info.runConn:Disconnect() end);  info.runConn  = nil end
				local baseWS = hum.WalkSpeed

				hum:MoveTo(target)
				hum.AutoRotate = prevAuto

				addApproachMonitor(key, info, hum, hrp, target, baseWS, track)

				info.moveConn = hum.MoveToFinished:Connect(function(_reached)
					removeApproachMonitor(key, info, true)
					if track then pcall(function() track:AdjustSpeed(1.0) end) end
					if not info.cancelled then gotoNext() end
				end)
				table.insert(info.conns, info.moveConn)

				-- animation speed mapping to actual motion
				info.runConn = hum.Running:Connect(function(speed)
					local tr = info.animTrack
					if not tr then return end
					if speed > 0.05 then
						if not tr.IsPlaying then tr:Play(CONFIG.BlendInTime) end
						local ws = math.max(0.1, hum.WalkSpeed)
						local norm = math.clamp(speed / ws, 0, 2)
						tr:AdjustSpeed(0.6 + 0.6 * norm) -- 0.6..1.2x
						tr:AdjustWeight(1, 0.05)
					else
						tr:AdjustSpeed(0.25) -- tiny shuffle when nearly stopped
					end
				end)
				table.insert(info.conns, info.runConn)
			end)
		else
			-- NON-HUMANOID: turn tween, then translate tween while facing the *current* node
			tweenTurnOnly(hrp, faceDir, key, function()
				if info.cancelled then return end

				ensureWalkPlaying(info)

				local dist = (target - hrp.Position).Magnitude
				local spd  = math.max(0.1, tonumber(opts.WalkSpeed) or CONFIG.DefaultWalkSpeed)
				local t    = math.max(0.05, dist / spd)

				local holdDir = flatDirXZ(hrp.Position, target)
				local startCF = yawOnlyCF(hrp.Position, holdDir)
				local endCF   = yawOnlyCF(target,      holdDir)

				-- approach easing by easing curve (keeps velocity perception smooth)
				local moveInfo = TweenInfo.new(t, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

				hrp.CFrame = startCF
				if info.tween then pcall(function() info.tween:Cancel() end); info.tween = nil end

				local tw = TweenService:Create(hrp, moveInfo, {CFrame = endCF})
				info.tween = tw
				tw:Play()
				local conn; conn = tw.Completed:Connect(function()
					if conn then conn:Disconnect() end
					if not info.cancelled then gotoNext() end
				end)
				table.insert(info.conns, conn)
			end)
		end
	end

	gotoNext()
end

function CivilianMovement.stopMovesForKey(key)
	local info = activeMoves[key]
	if not info then return end
	info.cancelled = true

	if info.tween   then pcall(function() info.tween:Cancel() end);   info.tween   = nil end
	if info.moveConn then pcall(function() info.moveConn:Disconnect() end); info.moveConn = nil end
	if info.runConn  then pcall(function() info.runConn:Disconnect() end);  info.runConn  = nil end
	if info.approachActive then
		removeApproachMonitor(key, info, true)
	end

	if info.humanoid and info.origWalkSpeed then
		info.humanoid.WalkSpeed = info.origWalkSpeed
	end
	info.humanoid = nil
	info.origWalkSpeed = nil

	stopWalkAnimation(key)

	for _, c in ipairs(info.conns) do
		disconnectHandle(c)
	end
	activeMoves[key] = nil
end

return CivilianMovement
