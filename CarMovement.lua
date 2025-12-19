local TweenService = game:GetService("TweenService")

local CarMovement = {}

local _intersectionLocks = {}   -- ["x_z"] = true
local _edgeLocks         = {}   -- ["x_z->x2_z2"] = true (DIRECTED)
local _edgeReleasedAt    = {}   -- ["x_z->x2_z2"] = os.clock() timestamp for headway
local _locksByCar        = {}   -- [car] = { edge=..., intersection=... }

-- Configuration
local CONFIG = {
	SPEED_STUDS_PER_SEC    = 10,     -- Speed of the car in studs per second
	BFS_LANE_OFFSET        = 1,      -- Lane offset distance
	SWAP_EAST_WEST_LANES   = true,   -- Toggle to swap East-West lanes
	DEBUG             = false,   -- Toggle all debug prints/warns on/off
}

-- Debug helper functions
local function debugPrint(...)
	if CONFIG.DEBUG then
		print(...)
	end
end

local function debugWarn(...)
	if CONFIG.DEBUG then
		warn(...)
	end
end

-- Table to Track Active Tweens
-- Structure: activeTweens[zoneId] = { tween1, tween2, ... }
local activeTweens = {}

-- Utility: normalizeAngle(angle)
-- Ensures the angle is within [0, 2π) radians.
local function normalizeAngle(radians)
	radians = radians % (2 * math.pi)
	return radians
end


-- 1) SINGLE-ROAD MOVEMENT

function CarMovement.moveCar(car, endPos, travelTime, onCompleteCallback, zoneId)
	if not car or not car.PrimaryPart then
		debugWarn("[CarMovement] Invalid car or missing PrimaryPart.")
		if onCompleteCallback then
			onCompleteCallback(car)
		end
		return
	end

	local startCFrame = car.PrimaryPart.CFrame
	local rx, ry, rz = startCFrame:ToOrientation()
	ry = normalizeAngle(ry)

	-- Preserve yaw only
	local orientationOnly = CFrame.Angles(0, ry, 0)
	local endCFrame = CFrame.new(endPos) * orientationOnly

	-- Create Tween
	local tweenInfo = TweenInfo.new(travelTime, Enum.EasingStyle.Linear)
	local tweenGoal = { CFrame = endCFrame }
	local tween = TweenService:Create(car.PrimaryPart, tweenInfo, tweenGoal)
	tween:Play()

	-- Initialize zone's tween list if not present
	activeTweens[zoneId] = activeTweens[zoneId] or {}
	table.insert(activeTweens[zoneId], tween)

	tween.Completed:Connect(function(status)
		-- Remove tween from activeTweens
		for i, t in ipairs(activeTweens[zoneId] or {}) do
			if t == tween then
				table.remove(activeTweens[zoneId], i)
				break
			end
		end

		if status == Enum.PlaybackState.Completed then
			if onCompleteCallback then
				onCompleteCallback(car)
			end
		else
			debugWarn("[CarMovement] Tween did not complete successfully.")
			if onCompleteCallback then
				onCompleteCallback(car)
			end
		end
	end)
end


-- 2) BFS MULTI-SEGMENT MOVEMENT


-- A) Compute cardinal orientation (standard)
local function computeOrientationCFrame(startPos, endPos)
	local offset = endPos - startPos
	if offset.Magnitude < 0.001 then
		debugPrint("[CarMovement] BFS orientation: offset too small; using default 0 yaw.")
		return CFrame.Angles(0, 0, 0)
	end

	local dir = Vector3.new(offset.X, 0, offset.Z).Unit

	-- Standard cardinal snap:
	-- East = 0°, West = π, South = +π/2, North = -π/2
	local yaw
	if math.abs(dir.X) > math.abs(dir.Z) then
		-- East/West
		if dir.X >= 0 then
			yaw = 0            -- East
		else
			yaw = math.pi      -- West
		end
	else
		-- North/South
		if dir.Z >= 0 then
			yaw = math.pi / 2  -- South
		else
			yaw = -math.pi / 2 -- North
		end
	end

	return CFrame.Angles(0, yaw, 0)
end

-- B) Check if a segment is East-West
local function isEastWest(startPos, endPos)
	local offset = endPos - startPos
	if offset.Magnitude < 0.001 then return false end
	local dir = Vector3.new(offset.X, 0, offset.Z).Unit
	return math.abs(dir.X) > math.abs(dir.Z)
end

-- C) BFS lane offset: forward:Cross(up)
local function getSideVector(startPos, endPos)
	local forward = Vector3.new(endPos.X - startPos.X, 0, endPos.Z - startPos.Z).Unit
	local up = Vector3.new(0, 1, 0)

	local side = forward:Cross(up).Unit
	debugPrint(string.format(
		"[CarMovement] getSideVector: forward=(%.2f, %.2f, %.2f), side=(%.2f, %.2f, %.2f)",
		forward.X, forward.Y, forward.Z,
		side.X, side.Y, side.Z
		))
	return side
end

-- D) moveCarAlongPath
local function _acquireLock(tbl, key, car)
	while tbl[key] do
		if not car or not car.Parent or not car.PrimaryPart then return false end
		task.wait(0.05)
	end
	tbl[key] = true
	return true
end
local function _releaseLock(tbl, key)
	if key then tbl[key] = nil end
end

local function _rememberLock(car, edgeKey, intersectionKey)
	if not car then return end
	local rec = _locksByCar[car]
	if not rec then
		rec = {}
		_locksByCar[car] = rec
		car.AncestryChanged:Connect(function(_, parent)
			if parent ~= nil then return end
			-- car deleted; release any locks it was holding so others can proceed
			if rec.edge then _releaseLock(_edgeLocks, rec.edge) end
			if rec.intersection then _releaseLock(_intersectionLocks, rec.intersection) end
			_locksByCar[car] = nil
		end)
	end
	if edgeKey then rec.edge = edgeKey end
	if intersectionKey then rec.intersection = intersectionKey end
end

local function _clearRememberedLock(car, which)
	local rec = car and _locksByCar[car]
	if not rec then return end
	if which == "edge" then
		rec.edge = nil
	elseif which == "intersection" then
		rec.intersection = nil
	else
		rec.edge, rec.intersection = nil, nil
	end
	if not rec.edge and not rec.intersection then
		_locksByCar[car] = nil
	end
end


-- Backward-compatible:
-- moveCarAlongPath(car, path, [optionsOrOnDone], [onDoneOrZoneId], [maybeZoneId])
-- options: { stopIndices = {i,...}, stopKeysByIndex = {[i]="x_z"}, stopSeconds = number }
function CarMovement.moveCarAlongPath(car, path, arg3, arg4, arg5)
	local options, onPathComplete, zoneId
	if type(arg3) == "function" or arg3 == nil then
		options = nil
		onPathComplete = arg3
		zoneId = arg4
	else
		options = arg3 or {}
		onPathComplete = arg4
		zoneId = arg5
	end

	if not car or not car.PrimaryPart then
		debugWarn("[CarMovement] Invalid car or missing PrimaryPart.")
		if onPathComplete then onPathComplete(car) end
		return
	end
	if not path or #path < 2 then
		debugWarn("[CarMovement] BFS path is invalid or too short.")
		if onPathComplete then onPathComplete(car) end
		return
	end

	local preStopSet = {}
	if options and options.preStopIndices then
		for _, idx in ipairs(options.preStopIndices) do preStopSet[idx] = true end
	end
	local preStopKeysByIdx   = options and options.preStopKeysByIdx or {}
	local edgeKeyByIndex     = options and options.edgeKeyByIndex   or {}
	local stopSeconds        = (options and options.stopSeconds) or 0
	local minEdgeHeadwaySec  = (options and options.minEdgeHeadwaySec) or 0

	local currentIndex = 1

	local function moveToNext()
		if not car or not car.PrimaryPart then return end
		if currentIndex >= #path then
			if onPathComplete then onPathComplete(car) end
			return
		end

		local thisPos = path[currentIndex]
		local nextPos = path[currentIndex + 1]

		-- 1) PRE-INTERSECTION STOP (stop BEFORE entering nextPos if nextPos is an intersection)
		local pendingIntersectionKey = nil
		if preStopSet[currentIndex] and stopSeconds > 0 then
			local lockKey = preStopKeysByIdx[currentIndex]
			if lockKey then
				if not _acquireLock(_intersectionLocks, lockKey, car) then return end
				_rememberLock(car, nil, lockKey)
				local untilT = os.clock() + stopSeconds
				while os.clock() < untilT do
					if not car or not car.Parent or not car.PrimaryPart then
						_releaseLock(_intersectionLocks, lockKey)
						_clearRememberedLock(car, "intersection")
						return
					end
					task.wait(0.05)
				end
				-- Keep intersection lock while traversing into the node, release on arrival
				pendingIntersectionKey = lockKey
			end
		end

		-- 2) EDGE LOCK (directed segment occupancy + optional headway)
		local edgeKey = edgeKeyByIndex[currentIndex]
		if edgeKey then
			-- honor headway: wait until enough time passed since last release
			if minEdgeHeadwaySec > 0 then
				local relAt = _edgeReleasedAt[edgeKey]
				if relAt then
					local dt = os.clock() - relAt
					if dt < minEdgeHeadwaySec then
						local toWait = minEdgeHeadwaySec - dt
						local untilT = os.clock() + toWait
						while os.clock() < untilT do
							if not car or not car.Parent or not car.PrimaryPart then return end
							task.wait(0.05)
						end
					end
				end
			end
			if not _acquireLock(_edgeLocks, edgeKey, car) then
				-- car died
				return
			end
			_rememberLock(car, edgeKey, nil)
		end

		-- 3) Orientation & lane offset (same as before)
		local orientation = computeOrientationCFrame(thisPos, nextPos)
		local sideVec = getSideVector(thisPos, nextPos)
		if isEastWest(thisPos, nextPos) then
			orientation = orientation * CFrame.Angles(0, math.pi, 0)
			if not CONFIG.SWAP_EAST_WEST_LANES then
				sideVec = sideVec * -1
			end
		end
		local finalPos = nextPos + (sideVec * CONFIG.BFS_LANE_OFFSET)

		local distance = (finalPos - car.PrimaryPart.Position).Magnitude
		local travelTime = distance / CONFIG.SPEED_STUDS_PER_SEC

		local endCFrame = CFrame.new(finalPos) * orientation
		local tweenInfo = TweenInfo.new(travelTime, Enum.EasingStyle.Linear)
		local tweenGoal = { CFrame = endCFrame }
		local tween = TweenService:Create(car.PrimaryPart, tweenInfo, tweenGoal)
		tween:Play()

		if zoneId ~= nil then
			activeTweens[zoneId] = activeTweens[zoneId] or {}
			table.insert(activeTweens[zoneId], tween)
		end

		tween.Completed:Connect(function(status)
			-- remove active tween record
			if zoneId ~= nil then
				for i, t in ipairs(activeTweens[zoneId] or {}) do
					if t == tween then table.remove(activeTweens[zoneId], i); break end
				end
			end

			-- Release locks on arrival
			if edgeKey then
				_releaseLock(_edgeLocks, edgeKey)
				_edgeReleasedAt[edgeKey] = os.clock() -- mark for headway timing
				_clearRememberedLock(car, "edge")
				edgeKey = nil
			end
			if pendingIntersectionKey then
				_releaseLock(_intersectionLocks, pendingIntersectionKey)
				_clearRememberedLock(car, "intersection")
				pendingIntersectionKey = nil
			end

			if status ~= Enum.PlaybackState.Completed then
				debugWarn("[CarMovement] Segment tween did not complete successfully.")
				if onPathComplete then onPathComplete(car) end
				return
			end

			currentIndex += 1
			moveToNext()
		end)
	end

	-- Initial placement (unchanged)
	local firstOrientation = computeOrientationCFrame(path[1], path[2])
	local firstSideVec = getSideVector(path[1], path[2])
	if isEastWest(path[1], path[2]) then
		firstOrientation = firstOrientation * CFrame.Angles(0, math.pi, 0)
		if not CONFIG.SWAP_EAST_WEST_LANES then
			firstSideVec = firstSideVec * -1
		end
	end
	local startPos = path[1] + (firstSideVec * CONFIG.BFS_LANE_OFFSET)
	car:SetPrimaryPartCFrame(CFrame.new(startPos) * firstOrientation)

	moveToNext()
end


-- Cleanup Function to Stop All Tweens for a Given Zone

function CarMovement.stopMovementsForZone(zoneId)
	if not activeTweens[zoneId] then
		return
	end

	for _, tween in ipairs(activeTweens[zoneId]) do
		if tween and tween.PlaybackState == Enum.PlaybackState.Playing then
			tween:Cancel()
		end
	end

	activeTweens[zoneId] = nil
	debugPrint(string.format("[CarMovement] All movements stopped for Zone '%s'.", zoneId))
end

return CarMovement
