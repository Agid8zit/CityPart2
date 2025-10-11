local MusicController = {}

-- Roblox Services
local TweenService = game:GetService("TweenService")

-- Music
local MUSIC_PLAYLIST = {
	{SoundId = "rbxassetid://9043887091", Volume = 0.5, },
	{SoundId = "rbxassetid://1845341094", Volume = 0.5, },
	{SoundId = "rbxassetid://9046862941", Volume = 0.5, },
	{SoundId = "rbxassetid://9046863253", Volume = 0.5, },
}

-- Defines
local LocalPlayer: Player = shared.LocalPlayer
local RNG = Random.new()
local CurrentMusic = nil
local CurrentMusicIndex = nil
local BE_SetMusic = Instance.new("BindableEvent")

-- Module Functions
function MusicController.IsPlaying()
	if not CurrentMusic then return end
	
	return CurrentMusic.IsPlaying
end

function MusicController.Play()
	if not CurrentMusic then return end
	
	CurrentMusic:Play()
end

function MusicController.Pause()
	if not CurrentMusic then return end

	CurrentMusic:Pause()
end

function MusicController.SkipSong()
	if CurrentMusicIndex then
		local NewIndex = CurrentMusicIndex + 1
		if NewIndex > #MUSIC_PLAYLIST then NewIndex = 1 end
		BE_SetMusic:Fire(NewIndex)
	else
		local NewIndex = RNG:NextInteger(1, #MUSIC_PLAYLIST)
		BE_SetMusic:Fire(NewIndex)
	end
end

function MusicController.SetMusic(SpecificIndex: number?)
	-- Fade out existing music
	if CurrentMusic then
		local PastMusic = CurrentMusic
		TweenService:Create(PastMusic, TweenInfo.new(1.5), {
			Volume = 0
		}):Play()
		task.delay(1.5, PastMusic.Destroy, PastMusic)
	end
	CurrentMusic = nil
	
	-- Index
	local FinalIndex = SpecificIndex
	if not SpecificIndex then
		FinalIndex = RNG:NextInteger(1, #MUSIC_PLAYLIST)
	else
		assert(SpecificIndex >= 1 and SpecificIndex <= #MUSIC_PLAYLIST, "Index Invalid ("..SpecificIndex..")")
	end
	
	CurrentMusic = Instance.new("Sound")
	CurrentMusic.SoundId = MUSIC_PLAYLIST[FinalIndex].SoundId
	CurrentMusic.Volume = 0
	CurrentMusic.Parent = workspace._Misc

	-- Fade In
	TweenService:Create(CurrentMusic, TweenInfo.new(0.5), {
		Volume = MUSIC_PLAYLIST[FinalIndex].Volume
	}):Play()

	-- On Finish
	CurrentMusic.Ended:Connect(function()
		task.wait() -- break up stack to prevent stack overflow
		local NewIndex = FinalIndex + 1
		if NewIndex > #MUSIC_PLAYLIST then NewIndex = 1 end
		BE_SetMusic:Fire(NewIndex)
	end)

	-- Play
	CurrentMusicIndex = FinalIndex
	CurrentMusic:Play()
	
	return CurrentMusic
end

-- Init
do
	-- Default Music
	local m = MusicController.SetMusic(nil)
	if game.ReplicatedStorage.StartMusicMuted.Value then
		m:Pause()
	end
	
	-- Event
	BE_SetMusic.Event:Connect(MusicController.SetMusic)
end

return MusicController