local SoundController = {}

-- Roblox Services
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies
local Sounds = require(ReplicatedStorage.Scripts.Sounds)
local Timer = require(ReplicatedStorage.Scripts.Timer)
--local Remotes = shared.GetModule("Remotes")

-- Constants
local SPAM_DEBOUNCER = 0.1

-- Defines
local AntiSpamSFXDebouncers = {} -- [SoundCategory][SoundName] = Timer

-- Module Functions
function SoundController.CreateSound(SoundCategory: string, SoundName: string, Params: {}?, IsMusic: boolean?)
	local CurrentCategory = Sounds[SoundCategory]
	if not CurrentCategory then warn("[!] Invalid Sound Category ("..SoundCategory..")") end
	assert(typeof(CurrentCategory) == "table", "SoundCategory ("..tostring(SoundCategory)..") not found")

	local SoundData = CurrentCategory[SoundName]
	if not SoundData then warn("[!] Invalid Sound Name ("..SoundName..")") end
	assert(typeof(SoundData) == "table", "Sound Name ("..tostring(SoundName)..") not found in category ("..tostring(SoundCategory)..")")

	local Sound = Instance.new("Sound")
	Sound.Name = SoundName
	Sound.RollOffMode = Enum.RollOffMode.InverseTapered
	if IsMusic then
		Sound.SoundGroup = game.SoundService.Master.Music
	else
		Sound.SoundGroup = game.SoundService.Master.SFX
	end

	-- Default Params
	for Key, Value in SoundData do
		if Key == "Effects" then continue end -- Custom Logic
		Sound[Key] = Value
	end

	-- Custom Params
	if Params then
		for Key, Value in Params do
			Sound[Key] = Value
		end
	end

	if SoundData.Effects then
		for EffectName, Parameters in SoundData.Effects do
			local Effect = Instance.new(EffectName)
			for Key, Value in Parameters do
				Effect[Key] = Value
			end
			Effect.Parent = Sound
		end
	end
	
	return Sound
end

function SoundController.PlaySoundOnce(SoundCategory: string, SoundName: string, Params: {}?, FadeTime: number?, AudioPostEffect: {}?)
	-- Spam Preventer
	if not AntiSpamSFXDebouncers[SoundCategory] then AntiSpamSFXDebouncers[SoundCategory] = {} end
	if not AntiSpamSFXDebouncers[SoundCategory][SoundName] then AntiSpamSFXDebouncers[SoundCategory][SoundName] = Timer.new(SPAM_DEBOUNCER, true) end
	if AntiSpamSFXDebouncers[SoundCategory][SoundName]:IsNotDone() then return end
	AntiSpamSFXDebouncers[SoundCategory][SoundName]:Reset()
	
	-- Create
	local Sound = SoundController.CreateSound(SoundCategory, SoundName)

	-- Defaults
	Sound.Parent = workspace._Misc
	Sound.Looped = false

	-- Params
	if Params then
		for Key, Value in Params do
			Sound[Key] = Value
		end
	end

	-- Post Effect
	if AudioPostEffect then
		for EffectName, DataSet in AudioPostEffect do
			local Effect = Instance.new(EffectName)
			for Key, Value in DataSet do
				Effect[Key] = Value
			end
			Effect.Parent = Sound
		end
	end

	-- Wait for Loading to Play it
	task.spawn(function()
		if not Sound.IsLoaded then Sound.Loaded:Wait() end
		Sound:Play()

		-- End case
		if FadeTime then
			task.delay(math.max(0, Sound.TimeLength - FadeTime), function()
				TweenService:Create(Sound, TweenInfo.new(FadeTime), {
					Volume = 0.0;
				}):Play()
				task.delay(0.1, function()
					if Sound.Parent then Sound:Destroy() end
				end)
			end)
		else
			task.delay(math.max(0, Sound.TimeLength), function()
				if Sound.Parent then Sound:Destroy() end
			end)
		end
	end)

	--return Sound
end

function SoundController.PlaySoundOnceAtPosition(SoundCategory: string, SoundName: string, Position: Vector3 | Player, Params: {}?, FadeTime: number?, AudioPostEffect: {}?)
	-- Spam Preventer
	if not AntiSpamSFXDebouncers[SoundCategory] then AntiSpamSFXDebouncers[SoundCategory] = {} end
	if not AntiSpamSFXDebouncers[SoundCategory][SoundName] then AntiSpamSFXDebouncers[SoundCategory][SoundName] = Timer.new(SPAM_DEBOUNCER, true) end
	if AntiSpamSFXDebouncers[SoundCategory][SoundName]:IsNotDone() then return end
	AntiSpamSFXDebouncers[SoundCategory][SoundName]:Reset()

	-- Create
	local Sound = SoundController.CreateSound(SoundCategory, SoundName)

	-- Attachment
	local Attachment = nil
	if typeof(Position) == "Vector3" then
		Attachment = Instance.new("Attachment")
		Attachment.Position = Position
		Attachment.Parent = workspace.Terrain
	elseif typeof(Position) == "Instance" then
		if Position and Position.Character and Position.Character.PrimaryPart then
			Attachment = Instance.new("Attachment")
			--Attachment.Position = Position.Character.PrimaryPart.Position
			Attachment.Parent = Position.Character.PrimaryPart
		else
			return
		end
	else
		error("Position is invalid type for PlaySoundOnceAtPosition")
	end


	-- Params
	if Params then
		for Key, Value in Params do
			Sound[Key] = Value
		end
	end

	-- Post Effect
	if AudioPostEffect then
		for EffectName, DataSet in AudioPostEffect do
			local Effect = Instance.new(EffectName)
			for Key, Value in DataSet do
				Effect[Key] = Value
			end
			Effect.Parent = Sound
		end
	end

	-- Requirements
	Sound.Looped = false
	Sound.Parent = Attachment
	Sound.Ended:Connect(function()
		Attachment:Destroy()
	end)

	-- Wait for Loading to Play it
	task.spawn(function()
		if not Sound.IsLoaded then Sound.Loaded:Wait() end
		Sound:Play()

		-- End case
		if FadeTime then
			task.delay(math.max(0, Sound.TimeLength - FadeTime), function()
				TweenService:Create(Sound, TweenInfo.new(FadeTime), {
					Volume = 0.0;
				}):Play()
				task.delay(0.1, function()
					if Attachment then Attachment:Destroy() end
				end)
			end)
		else
			task.delay(math.max(0, Sound.TimeLength), function()
				if Attachment then Attachment:Destroy() end
			end)
		end
	end)

	--return Sound, Attachment
end

function SoundController.PlaySoundOnceOnPart(SoundCategory: string, SoundName: string, BasePart: BasePart, Params: {}?, FadeTime: number?, AudioPostEffect: {}?)
	-- Spam Preventer
	if not AntiSpamSFXDebouncers[SoundCategory] then AntiSpamSFXDebouncers[SoundCategory] = {} end
	if not AntiSpamSFXDebouncers[SoundCategory][SoundName] then AntiSpamSFXDebouncers[SoundCategory][SoundName] = Timer.new(SPAM_DEBOUNCER, true) end
	if AntiSpamSFXDebouncers[SoundCategory][SoundName]:IsNotDone() then return end
	AntiSpamSFXDebouncers[SoundCategory][SoundName]:Reset()
	
	-- Create
	local Sound = SoundController.CreateSound(SoundCategory, SoundName)

	-- Params
	if Params then
		for Key, Value in Params do
			Sound[Key] = Value
		end
	end

	-- Post Effect
	if AudioPostEffect then
		for EffectName, DataSet in AudioPostEffect do
			local Effect = Instance.new(EffectName)
			for Key, Value in DataSet do
				Effect[Key] = Value
			end
			Effect.Parent = Sound
		end
	end

	-- SoundNode
	local SoundNode = script.SoundNode:Clone()
	SoundNode.Position = BasePart.Position
	SoundNode.Parent = workspace._Misc
	
	-- Move/Update SoundNode
	local Heartbeat;
	Heartbeat = RunService.Heartbeat:Connect(function()
		if not BasePart.Parent then
			Heartbeat:Disconnect()
			Heartbeat = nil
		else
			SoundNode.Position = BasePart.Position
		end
	end)
	
	-- Requirements
	Sound.Parent = SoundNode
	Sound.Looped = false
	Sound.Ended:Connect(function()
		SoundNode:Destroy()
	end)

	-- Wait for Loading to Play it
	task.spawn(function()
		if not Sound.IsLoaded then Sound.Loaded:Wait() end
		Sound:Play()

		-- End case
		if FadeTime then
			task.delay(math.max(0, Sound.TimeLength - FadeTime), function()
				TweenService:Create(Sound, TweenInfo.new(FadeTime), {
					Volume = 0.0;
				}):Play()
				task.delay(0.1, function()
					if Heartbeat then
						Heartbeat:Disconnect()
						Heartbeat = nil
					end
					if SoundNode then
						SoundNode:Destroy()
					end
				end)
			end)
		else
			task.delay(math.max(0, Sound.TimeLength), function()
				if Heartbeat then
					Heartbeat:Disconnect()
					Heartbeat = nil
				end
				if SoundNode then
					SoundNode:Destroy()
				end
			end)
		end
	end)
	
	--return Sound
end

function SoundController.PlaySoundLooped(SoundCategory: string, SoundName: string, Params: {}?, Duration: number?, FadeTime: number?)
	-- Spam Preventer
	if not AntiSpamSFXDebouncers[SoundCategory] then AntiSpamSFXDebouncers[SoundCategory] = {} end
	if not AntiSpamSFXDebouncers[SoundCategory][SoundName] then AntiSpamSFXDebouncers[SoundCategory][SoundName] = Timer.new(SPAM_DEBOUNCER, true) end
	if AntiSpamSFXDebouncers[SoundCategory][SoundName]:IsNotDone() then return end
	AntiSpamSFXDebouncers[SoundCategory][SoundName]:Reset()
	
	-- Create
	local Sound = SoundController.CreateSound(SoundCategory, SoundName)

	-- Params
	if Params then
		for Key, Value in Params do
			Sound[Key] = Value
		end
	end

	-- Requirements
	Sound.Parent = workspace._Misc
	Sound.Looped = true

	-- Wait for Loading to Play it
	task.spawn(function()
		if not Sound.IsLoaded then Sound.Loaded:Wait() end
		Sound:Play()

		if Duration then
			if FadeTime then
				task.delay(math.max(0, Duration - FadeTime), function()
					TweenService:Create(Sound, TweenInfo.new(FadeTime), {
						Volume = 0.0;
					}):Play()
					task.delay(0.1, function()
						if Sound.Parent then Sound:Destroy() end
					end)
				end)
			else
				task.delay(math.max(0, Duration), function()
					if Sound.Parent then Sound:Destroy() end
				end)
			end
		end
	end)

	return Sound
end

function SoundController.PlaySoundLoopedAtPosition(SoundCategory: string, SoundName: string, Position: Vector3 | Player, Params: {}?, Duration: number?, FadeTime: number?)
	-- Spam Preventer
	if not AntiSpamSFXDebouncers[SoundCategory] then AntiSpamSFXDebouncers[SoundCategory] = {} end
	if not AntiSpamSFXDebouncers[SoundCategory][SoundName] then AntiSpamSFXDebouncers[SoundCategory][SoundName] = Timer.new(SPAM_DEBOUNCER, true) end
	if AntiSpamSFXDebouncers[SoundCategory][SoundName]:IsNotDone() then return nil end
	AntiSpamSFXDebouncers[SoundCategory][SoundName]:Reset()
	
	-- Create
	local Sound = SoundController.CreateSound(SoundCategory, SoundName)

	-- Attachment
	local Attachment = nil
	if typeof(Position) == "Vector3" then
		Attachment = Instance.new("Attachment")
		Attachment.Position = Position
	elseif typeof(Position) == "Instance" then
		if Position and Position.Character and Position.Character.PrimaryPart then
			Attachment = Instance.new("Attachment")
			Attachment.Position = Position.Character.PrimaryPart.Position
		else
			return
		end
	else
		error("Position is invalid type for PlaySoundLoopedAtPosition")
	end
	Attachment.Parent = workspace.Terrain

	-- Params
	if Params then
		for Key, Value in Params do
			Sound[Key] = Value
		end
	end

	-- Requirements
	Sound.Looped = true
	Sound.Parent = Attachment

	-- Wait for Loading to Play it
	task.spawn(function()
		if not Sound.IsLoaded then Sound.Loaded:Wait() end
		Sound:Play()

		if Duration then
			if FadeTime then
				task.delay(math.max(0, Duration - FadeTime), function()
					TweenService:Create(Sound, TweenInfo.new(FadeTime), {
						Volume = 0.0;
					}):Play()
					task.delay(0.1, function()
						if Attachment then Attachment:Destroy() end
					end)
				end)
			else
				task.delay(math.max(0, Duration), function()
					if Attachment then Attachment:Destroy() end
				end)
			end
		end
	end)

	--return Sound, Attachment
end

-- Networking
--Remotes.Listen("PlaySoundOnce", SoundController.PlaySoundOnce)
--Remotes.Listen("PlaySoundOnceAtPosition", SoundController.PlaySoundOnceAtPosition)
--Remotes.Listen("PlaySoundOnceOnPart", SoundController.PlaySoundOnceOnPart)
--Remotes.Listen("PlaySoundLooped", SoundController.PlaySoundLooped)
--Remotes.Listen("PlaySoundLoopedAtPosition", SoundController.PlaySoundLoopedAtPosition)

return SoundController