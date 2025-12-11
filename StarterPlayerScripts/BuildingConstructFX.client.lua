local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local Events = ReplicatedStorage:WaitForChild("Events", 5)
local RemoteEvents = Events and Events:FindFirstChild("RemoteEvents")
local BuildFXRE = RemoteEvents and (RemoteEvents:FindFirstChild("BuildingConstructFX") or RemoteEvents:WaitForChild("BuildingConstructFX", 5))
if not BuildFXRE then
	return
end

local Scripts = ReplicatedStorage:WaitForChild("Scripts")
local Sounds = require(Scripts:WaitForChild("Sounds"))

local fxFolder = Workspace:FindFirstChild("_ClientBuildFX")
if not fxFolder then
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "_ClientBuildFX"
	fxFolder.Parent = Workspace
end

local rng = Random.new()

local CONSTRUCTION_SFX_VARIANCE = {
	pitchMin  = 0.92,
	pitchMax  = 1.08,
	volumeMin = 0.9,
	volumeMax = 1.1,
}
local CONSTRUCTION_SFX_VOLUME_MULT = 0.6

local function assignToSFXGroup(sound)
	local masterGroup = SoundService:FindFirstChild("Master")
	if not masterGroup then
		return
	end
	local sfxGroup = masterGroup:FindFirstChild("SFX")
	if sfxGroup and sfxGroup:IsA("SoundGroup") then
		sound.SoundGroup = sfxGroup
	end
end

local function collectAnimations(root: Instance?): {Animation}
	if not root then return {} end
	local out = {}
	for _, desc in ipairs(root:GetDescendants()) do
		if desc:IsA("Animation") then
			table.insert(out, desc)
		end
	end
	return out
end

local function averagePosition(positions: {Vector3}?): Vector3?
	local total = Vector3.new()
	local count = 0
	for _, pos in ipairs(positions or {}) do
		total += pos
		count += 1
	end
	if count == 0 then
		return nil
	end
	return total / count
end

local function startConstructionSound(positions: {Vector3}?): { sound: Sound, anchor: BasePart }?
	local soundData = Sounds.Misc and Sounds.Misc.Construction
	if not soundData then
		return nil
	end
	local center = averagePosition(positions)
	if not center then
		return nil
	end

	local anchor = Instance.new("Part")
	anchor.Name = "_ClientConstructionSoundAnchor"
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Anchored = true
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(center)
	anchor.Parent = fxFolder

	local sound = Instance.new("Sound")
	sound.Name = "_ClientConstructionSound"
	sound.SoundId = soundData.SoundId
	sound.RollOffMaxDistance = soundData.RollOffMaxDistance or sound.RollOffMaxDistance
	sound.RollOffMinDistance = soundData.RollOffMinDistance or sound.RollOffMinDistance
	local volumeScale = rng:NextNumber(CONSTRUCTION_SFX_VARIANCE.volumeMin, CONSTRUCTION_SFX_VARIANCE.volumeMax)
	sound.Volume = (soundData.Volume or sound.Volume) * volumeScale * CONSTRUCTION_SFX_VOLUME_MULT
	sound.Looped = true
	sound.PlaybackSpeed = rng:NextNumber(CONSTRUCTION_SFX_VARIANCE.pitchMin, CONSTRUCTION_SFX_VARIANCE.pitchMax)
	assignToSFXGroup(sound)
	sound.Parent = anchor
	sound:Play()

	return {
		sound = sound,
		anchor = anchor,
	}
end

local function stopConstructionSound(handle: { sound: Sound?, anchor: BasePart? }?)
	if not handle then
		return
	end
	local sound = handle.sound
	if sound then
		pcall(function()
			sound:Stop()
		end)
		sound:Destroy()
	end
	local anchor = handle.anchor
	if anchor then
		anchor:Destroy()
	end
end

local function speedTrackToDuration(track: AnimationTrack, baseSpeed: number, desiredDuration: number)
	if not track then return end
	desiredDuration = math.max(desiredDuration or 0, 0.05)

	local function apply(len)
		-- ensure the clip finishes within the desired window; never slower than baseSpeed
		local target = baseSpeed
		if len and len > 0 then
			target = math.max(baseSpeed, len / desiredDuration)
		end
		if target > 0 then
			track:AdjustSpeed(target)
		end
	end

	local len = track.Length
	if len and len > 0 then
		apply(len)
	else
		-- Some tracks report 0 until after first frame; poll briefly
		task.spawn(function()
			local deadline = os.clock() + 0.3
			repeat
				task.wait(0.02)
				len = track.Length
				if len and len > 0 then
					apply(len)
					return
				end
			until os.clock() > deadline
			apply(0)
		end)
	end
end

local function spawnStage1Clones(payload, playbackSpeed: number, desiredDuration: number)
	local clones = {}
	local tracks = {}
	local stage1 = payload.stage1
	if not (stage1 and payload.stage1Positions) then
		return clones, tracks
	end
	local rotY = math.rad(payload.rotationY or 0)
	for _, pos in ipairs(payload.stage1Positions) do
		local preview = stage1:Clone()
		if preview:IsA("Model") and preview.PrimaryPart then
			preview:SetPrimaryPartCFrame(CFrame.new(pos) * CFrame.Angles(0, rotY, 0))
		elseif preview:IsA("BasePart") then
			preview.CFrame = CFrame.new(pos) * CFrame.Angles(0, rotY, 0)
		end
		preview.Parent = fxFolder
		table.insert(clones, preview)

		local animator, animations = nil, {}
		local animController = preview:FindFirstChild("AnimationController", true)
		if animController then
			animator   = animController:FindFirstChildOfClass("Animator", true)
			animations = collectAnimations(animator or animController)
		end
		if (not animator) or #animations == 0 then
			local humanoid = preview:FindFirstChildOfClass("Humanoid", true)
			if humanoid then
				animator   = humanoid:FindFirstChildOfClass("Animator", true) or humanoid
				animations = collectAnimations(animator)
			end
		end
		if animator and #animations > 0 then
			local track = animator:LoadAnimation(animations[1])
			table.insert(tracks, track)
			track:Play(0, 1, playbackSpeed)
			if playbackSpeed ~= 1 then
				track:AdjustSpeed(playbackSpeed)
			end
			if desiredDuration and desiredDuration > 0 then
				speedTrackToDuration(track, playbackSpeed, desiredDuration)
			end
		end
	end
	return clones, tracks
end

local function spawnStage2Clone(payload)
	local stage2 = payload.stage2
	if not (stage2 and payload.finalCFrame) then
		return nil
	end
	local clone = stage2:Clone()
	if clone:IsA("Model") and clone.PrimaryPart then
		clone:SetPrimaryPartCFrame(payload.finalCFrame)
	elseif clone:IsA("BasePart") then
		clone.CFrame = payload.finalCFrame
	end
	if clone:IsA("BasePart") then
		clone.Anchored = true
		clone.CanCollide = false
	elseif clone:IsA("Model") then
		for _, bp in ipairs(clone:GetDescendants()) do
			if bp:IsA("BasePart") then
				bp.Anchored = true
				bp.CanCollide = false
			end
		end
	end
	clone.Parent = fxFolder
	return clone
end

local function destroyList(list)
	for _, inst in ipairs(list or {}) do
		if inst and inst.Parent then
			inst:Destroy()
		end
	end
end

local function scaleDuration(payload, seconds)
	if payload.buildSpeedEnabled and payload.buildSpeedMultiplier then
		return seconds / payload.buildSpeedMultiplier
	end
	return seconds
end

BuildFXRE.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	-- Only render FX for the local player's own builds to keep memory/CPU in check
	if payload.userId and LocalPlayer and payload.userId ~= LocalPlayer.UserId then
		return
	end

	local playbackSpeed = (payload.buildSpeedEnabled and payload.buildSpeedMultiplier) or 1
	local stage1Duration = payload.stage1Duration or 0
	local stage2Duration = payload.stage2Duration or 0
	local stage1Seconds = scaleDuration(payload, stage1Duration)
	local stage2Seconds = scaleDuration(payload, stage2Duration)

	local stage1Clones, tracks = spawnStage1Clones(payload, playbackSpeed, stage1Seconds)
	local soundHandle = payload.playSound and startConstructionSound(payload.stage1Positions) or nil

	task.spawn(function()
		task.wait(stage1Seconds)

		stopConstructionSound(soundHandle)
		for _, track in ipairs(tracks) do
			pcall(function() track:Stop() end)
			pcall(function() track:Destroy() end)
		end
		destroyList(stage1Clones)

		local stage2Clone = spawnStage2Clone(payload)
		if stage2Clone then
			task.wait(stage2Seconds)
			if stage2Clone.Parent then
				stage2Clone:Destroy()
			end
		end
	end)
end)
