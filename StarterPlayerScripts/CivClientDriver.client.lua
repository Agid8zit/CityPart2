local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents")
local CivClientDrive = RemoteEvents:WaitForChild("CivClientDrive")
local CivClientArrived = RemoteEvents:WaitForChild("CivClientArrived")
local CivClientAck = RemoteEvents:WaitForChild("CivClientDriveAck")

local DEBUG = true

local active = {} :: {[Model]: { cancelled: boolean }}
local WALK_ANIM_ID = "rbxassetid://121106814853748"

local function ensureAnimator(model: Model)
	local hum = model:FindFirstChildWhichIsA("Humanoid")
	if hum then
		local animator = hum:FindFirstChildOfClass("Animator") or hum:FindFirstChild("Animator")
		if animator then return animator end
		local new = Instance.new("Animator")
		new.Parent = hum
		return new
	end
	local ac = model:FindFirstChildOfClass("AnimationController")
	if not ac then
		ac = Instance.new("AnimationController")
		ac.Parent = model
	end
	local animator = ac:FindFirstChildOfClass("Animator") or ac:FindFirstChild("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = ac
	end
	return animator
end

local function playWalk(model: Model)
	local animator = ensureAnimator(model)
	if not animator then return nil end

	local anim = Instance.new("Animation")
	anim.AnimationId = WALK_ANIM_ID
	local track
	local ok = pcall(function()
		track = animator:LoadAnimation(anim)
	end)
	anim:Destroy()
	if not ok or not track then return nil end

	track.Looped = true
	pcall(function() track.Priority = Enum.AnimationPriority.Movement end)
	track:Play(0.1)
	pcall(function() track:AdjustSpeed(1.0) end)
	return track
end

local function asVector3(v)
	if typeof(v) == "Vector3" then return v end
	if typeof(v) == "table" and typeof(v.x) == "number" and typeof(v.y) == "number" and typeof(v.z) == "number" then
		return Vector3.new(v.x, v.y, v.z)
	end
	return nil
end

local function stepModel(model: Model, path: {Vector3}, speed: number)
	if active[model] then
		active[model].cancelled = true
	end

	local state = { cancelled = false }
	active[model] = state

	local track = playWalk(model)
	local function cleanup()
		if track then
			pcall(function() track:Stop(0.15) end)
			pcall(function() track:Destroy() end)
		end
		active[model] = nil
	end

	task.spawn(function()
		local hrp = model and model.PrimaryPart
		if not (hrp and hrp.Parent) then
			if DEBUG then print("[CivClient] abort: missing HRP/parent", model) end
			cleanup()
			return
		end

		for i = 1, #path - 1 do
			if state.cancelled then cleanup() return end
			if not (model and model.Parent) then cleanup() return end

			local a = path[i]
			local b = path[i + 1]
			local delta = b - a
			local dist = delta.Magnitude
			if dist < 1e-3 then continue end

			local duration = math.max(0.05, dist / speed)
			local startTime = tick()
			while true do
				if state.cancelled then cleanup() return end
				if not (model and model.Parent and hrp.Parent) then cleanup() return end

				local alpha = math.clamp((tick() - startTime) / duration, 0, 1)
				local pos = a + delta * alpha
				local dir = delta.Unit
				local cf = CFrame.lookAt(pos, pos + Vector3.new(dir.X, 0, dir.Z))
				hrp.CFrame = cf

				if alpha >= 1 then
					break
				end
				RunService.RenderStepped:Wait()
			end
		end

		if not state.cancelled and model and model.Parent then
			if DEBUG then print("[CivClient] arrived; notifying server", model) end
			CivClientArrived:FireServer(model)
		end
		cleanup()
	end)
end

CivClientDrive.OnClientEvent:Connect(function(model: Model, rawPath, speed: number)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
	if typeof(speed) ~= "number" or speed <= 0 then return end
	if typeof(rawPath) ~= "table" or #rawPath < 2 then return end

	-- Ensure model is present/streamed and has an HRP before we ack.
	local deadline = tick() + 2.0
	while (not model.Parent) and tick() < deadline do
		RunService.RenderStepped:Wait()
	end
	local hrp = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	while (not hrp) and tick() < deadline do
		hrp = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
		RunService.RenderStepped:Wait()
	end
	if not hrp then
		if DEBUG then print("[CivClient] no HRP/PrimaryPart after wait; abort", model) end
		return
	end
	-- Ensure PrimaryPart set locally for consistent PivotTo.
	if not model.PrimaryPart then
		pcall(function() model.PrimaryPart = hrp end)
	end

	local path = {}
	for i = 1, #rawPath do
		local v = asVector3(rawPath[i])
		if not v then
			if DEBUG then print("[CivClient] malformed path; abort", model) end
			return -- malformed path; abort
		end
		path[i] = v
	end

	if DEBUG then
		print(string.format("[CivClient] drive start model=%s pts=%d speed=%.2f", tostring(model), #path, speed))
	end
	-- Ack so server knows to avoid fallback.
	CivClientAck:FireServer(model)
	stepModel(model, path, speed)
end)
