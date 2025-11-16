local SoundEmitter = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = require(ReplicatedStorage.Scripts.Sounds)

local rng = Random.new()

local LOOP_PROP_OVERRIDES = {
	Volume = true,
	RollOffMaxDistance = true,
	RollOffMinDistance = true,
	PlaybackSpeed = true,
}

local function tryResolveTarget(target: Instance?): Instance?
	if not target then
		return nil
	end

	if target:IsA("BasePart") or target:IsA("Attachment") then
		return target
	end

	if target:IsA("Model") then
		return target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
	end

	return nil
end

local function applySoundData(sound: Sound, data: {[string]: any})
	for key, value in data do
		if key ~= "Effects" then
			sound[key] = value
		end
	end

	if data.Effects then
		for effectClass, params in data.Effects do
			local ok, effect = pcall(Instance.new, effectClass)
			if ok and effect then
				for key, value in params do
					effect[key] = value
				end
				effect.Parent = sound
			end
		end
	end
end

local function assignSoundGroup(sound: Sound, isMusic: boolean?)
	local masterGroup = SoundService:FindFirstChild("Master")
	if not masterGroup then
		return
	end

	local groupName = isMusic and "Music" or "SFX"
	local subgroup = masterGroup:FindFirstChild(groupName)
	if subgroup and subgroup:IsA("SoundGroup") then
		sound.SoundGroup = subgroup
	end
end

local function createSound(category: string, name: string): Sound
	local categoryData = Sounds[category]
	assert(categoryData, string.format("[SoundEmitter] Unknown sound category '%s'", tostring(category)))

	local soundData = categoryData[name]
	assert(soundData, string.format("[SoundEmitter] Unknown sound '%s.%s'", tostring(category), tostring(name)))

	local sound = Instance.new("Sound")
	sound.Name = string.format("%s_%s", category, name)

	assignSoundGroup(sound, soundData.IsMusic)
	applySoundData(sound, soundData)

	return sound
end

local function applyLoopOverrides(sound: Sound, overrides: {[string]: any}?)
	if not overrides then
		return
	end

	for key, value in overrides do
		if LOOP_PROP_OVERRIDES[key] then
			sound[key] = value
		end
	end

	if overrides.pitchRange then
		local range = overrides.pitchRange
		local min = range.min or range.Min or range[1] or 1
		local max = range.max or range.Max or range[2] or min
		sound.PlaybackSpeed = rng:NextNumber(min, max)
	end
end

function SoundEmitter.attachLoop(opts: {
	category: string?,
	name: string,
	targetInstance: Instance?,
	tag: string?,
	volume: number?,
	PlaybackSpeed: number?,
	RollOffMaxDistance: number?,
	RollOffMinDistance: number?,
	pitchRange: {number}?,
})
	assert(typeof(opts) == "table", "[SoundEmitter] attachLoop expects an options table")

	local target = tryResolveTarget(opts.targetInstance)
	if not target then
		return nil
	end

	local category = opts.category or "Misc"
	local sound = createSound(category, opts.name)

	sound.Looped = true

	local tagName = opts.tag or ("Loop_" .. opts.name)

	local existing = target:FindFirstChild(tagName)
	if existing and existing:IsA("Sound") then
		existing:Destroy()
	end

	sound.Name = tagName

	applyLoopOverrides(sound, {
		Volume = opts.volume,
		RollOffMaxDistance = opts.RollOffMaxDistance,
		RollOffMinDistance = opts.RollOffMinDistance,
		PlaybackSpeed = opts.PlaybackSpeed,
		pitchRange = opts.pitchRange,
	})

	sound.Parent = target
	sound:Play()

	return sound
end

return SoundEmitter
