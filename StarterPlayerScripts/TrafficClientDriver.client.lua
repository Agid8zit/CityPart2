local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents")
local TrafficClientDrive = RemoteEvents:WaitForChild("TrafficClientDrive")
local TrafficClientAck   = RemoteEvents:WaitForChild("TrafficClientDriveAck")
local TrafficClientArrived = RemoteEvents:WaitForChild("TrafficClientArrived")

local DEBUG = false
local CONFIG = {
	speed = 10,              -- studs/sec (kept in sync with server CarMovement)
	bfsLaneOffset = 1,       -- lane offset distance
	swapEastWestLanes = true -- mirrors lane side on E/W legs for two-way feel
}

-- Lightweight lock tables (mirrors server CarMovement so stops/headways still work client-side)
local _intersectionLocks = {} -- [nodeKey] = true
local _edgeLocks = {}         -- [edgeKey] = true
local _edgeReleasedAt = {}    -- [edgeKey] = timestamp

local function asVector3(v)
	if typeof(v) == "Vector3" then return v end
	if typeof(v) == "table" and typeof(v.x) == "number" and typeof(v.y) == "number" and typeof(v.z) == "number" then
		return Vector3.new(v.x, v.y, v.z)
	end
	return nil
end

local function alive(car: Model?): boolean
	return car ~= nil
		and car.Parent ~= nil
		and car.PrimaryPart ~= nil
		and car.PrimaryPart.Parent ~= nil
end

-- Orientation helpers (copied from server CarMovement for lane offsets)
local function computeOrientationCFrame(startPos, endPos)
	local offset = endPos - startPos
	if offset.Magnitude < 0.001 then
		return CFrame.Angles(0, 0, 0)
	end
	local dir = Vector3.new(offset.X, 0, offset.Z).Unit
	local yaw
	if math.abs(dir.X) > math.abs(dir.Z) then
		yaw = (dir.X >= 0) and 0 or math.pi -- East / West
	else
		yaw = (dir.Z >= 0) and math.pi / 2 or -math.pi / 2 -- South / North
	end
	return CFrame.Angles(0, yaw, 0)
end

local function isEastWest(startPos, endPos)
	local offset = endPos - startPos
	if offset.Magnitude < 0.001 then return false end
	local dir = Vector3.new(offset.X, 0, offset.Z).Unit
	return math.abs(dir.X) > math.abs(dir.Z)
end

local function getSideVector(startPos, endPos)
	local forward = Vector3.new(endPos.X - startPos.X, 0, endPos.Z - startPos.Z).Unit
	local up = Vector3.new(0, 1, 0)
	return forward:Cross(up).Unit
end

local function acquireLock(tbl, key, car)
	if not key then return true end
	while tbl[key] do
		if not alive(car) then return false end
		RunService.RenderStepped:Wait()
	end
	tbl[key] = true
	return true
end

local function releaseLock(tbl, key)
	if key then tbl[key] = nil end
end

local function waitAlive(duration, car)
	local deadline = tick() + duration
	while tick() < deadline do
		if not alive(car) then
			return false
		end
		RunService.RenderStepped:Wait()
	end
	return true
end

local function honorHeadway(edgeKey, minHeadway, car)
	if not edgeKey or minHeadway <= 0 then return true end
	local last = _edgeReleasedAt[edgeKey]
	if last then
		local dt = tick() - last
		if dt < minHeadway then
			return waitAlive(minHeadway - dt, car)
		end
	end
	return true
end

local function stepCar(car: Model, path: {Vector3}, opts)
	if not car or not car.PrimaryPart then return end
	local speed = (opts and opts.speed) or CONFIG.speed
	local hrp = car.PrimaryPart
	local stopSeconds = (opts and opts.stopSeconds) or 0
	local minEdgeHeadwaySec = (opts and opts.minEdgeHeadwaySec) or 0

	-- Precompute stop/edge data
	local preStopSet = {}
	if opts and opts.preStopIndices then
		for _, idx in ipairs(opts.preStopIndices) do
			preStopSet[idx] = true
		end
	end
	local preStopKeysByIdx = (opts and opts.preStopKeysByIdx) or {}
	local edgeKeyByIndex = (opts and opts.edgeKeyByIndex) or {}

	-- Initial placement with lane offset (matches server tween pathing)
	local firstOrientation = computeOrientationCFrame(path[1], path[2])
	local firstSideVec = getSideVector(path[1], path[2])
	if isEastWest(path[1], path[2]) then
		firstOrientation = firstOrientation * CFrame.Angles(0, math.pi, 0)
		if not CONFIG.swapEastWestLanes then
			firstSideVec = firstSideVec * -1
		end
	end
	local currentPos = path[1] + (firstSideVec * CONFIG.bfsLaneOffset)
	hrp.CFrame = CFrame.new(currentPos) * firstOrientation

	for i = 1, #path - 1 do
		local a = path[i]
		local b = path[i + 1]

		local orientation = computeOrientationCFrame(a, b)
		local sideVec = getSideVector(a, b)
		if isEastWest(a, b) then
			orientation = orientation * CFrame.Angles(0, math.pi, 0)
			if not CONFIG.swapEastWestLanes then
				sideVec = sideVec * -1
			end
		end
		local targetPos = b + (sideVec * CONFIG.bfsLaneOffset)

		-- Intersection stop (pre-node)
		local pendingIntersectionKey = nil
		if preStopSet[i] and stopSeconds > 0 then
			local lockKey = preStopKeysByIdx[i]
			if lockKey then
				if not acquireLock(_intersectionLocks, lockKey, car) then return end
				if not waitAlive(stopSeconds, car) then
					releaseLock(_intersectionLocks, lockKey)
					return
				end
				pendingIntersectionKey = lockKey
			end
		end

		-- Edge occupancy + headway
		local edgeKey = edgeKeyByIndex[i]
		if edgeKey then
			if not honorHeadway(edgeKey, minEdgeHeadwaySec, car) then
				if pendingIntersectionKey then releaseLock(_intersectionLocks, pendingIntersectionKey) end
				return
			end
			if not acquireLock(_edgeLocks, edgeKey, car) then
				if pendingIntersectionKey then releaseLock(_intersectionLocks, pendingIntersectionKey) end
				return
			end
		end

		local delta = targetPos - currentPos
		local dist = delta.Magnitude
		if dist >= 1e-3 then
			local duration = math.max(0.05, dist / speed)
			local start = tick()
			while true do
				if not alive(car) then
					if edgeKey then releaseLock(_edgeLocks, edgeKey) end
					if pendingIntersectionKey then releaseLock(_intersectionLocks, pendingIntersectionKey) end
					return
				end
				local alpha = math.clamp((tick() - start) / duration, 0, 1)
				local pos = currentPos + delta * alpha
				hrp.CFrame = CFrame.new(pos) * orientation
				if alpha >= 1 then break end
				RunService.RenderStepped:Wait()
			end
		end

		currentPos = targetPos

		if edgeKey then
			releaseLock(_edgeLocks, edgeKey)
			_edgeReleasedAt[edgeKey] = tick()
		end
		if pendingIntersectionKey then
			releaseLock(_intersectionLocks, pendingIntersectionKey)
		end
	end
	TrafficClientArrived:FireServer(car)
end

TrafficClientDrive.OnClientEvent:Connect(function(car: Model, rawPath, opts, pathId)
	if typeof(car) ~= "Instance" or not car:IsA("Model") then return end
	if typeof(rawPath) ~= "table" or #rawPath < 2 then return end

	local path = {}
	for i = 1, #rawPath do
		local v = asVector3(rawPath[i])
		if not v then return end
		path[i] = v
	end

	if DEBUG then
		print(string.format("[TrafficClient] drive start car=%s pts=%d", tostring(car), #path))
	end
	TrafficClientAck:FireServer(car)
	stepCar(car, path, opts)
end)
