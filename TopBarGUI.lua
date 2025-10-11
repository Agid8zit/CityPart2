local TopBarGui = {}

-- Roblox Services
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies
local events = ReplicatedStorage:WaitForChild("Events")
local UIUpdateEvent = events.RemoteEvents:WaitForChild("UpdateStatsUI")
local LocalizationLoader = require(ReplicatedStorage.Localization.Localizing)
local TopBarPlus = require(game.ReplicatedStorage.ThirdPartyClient.TopBarPlus)
local SoundController = require(game.ReplicatedStorage.Scripts.Controllers.SoundController)
local MusicController = require(game.ReplicatedStorage.Scripts.Controllers.MusicController)

-- Constants
local SETTINGS_ICON = 13003751476
local BADGES_ICON = 74353593927183
local MUTE_ICON = 12413825961
local UNMUTE_ICON = 12413824440
local SKIP_MUSIC_ICON = 16974371534 
local FLAG_ICON = 113984632305816

-- Defines
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer.PlayerGui
local UI = script.Parent

local TBP_Settings;

local IsViewedTracker = {} -- Set<Icon>
local IsViewed = false

-- Helper Functions
local function IconIsViewed(Icon, State: boolean?)
	IsViewedTracker[Icon] = State
	IsViewed = next(IsViewedTracker) ~= nil
end

-- Module Functions
function TopBarGui.IsViewed()
	return IsViewed
end

function TopBarGui.OnShow()
	if UI.Enabled then return end
	UI.Enabled = true
	
	if TBP_Settings then
		TBP_Settings:setEnabled(true)
	end
end

function TopBarGui.OnHide()
	if not UI.Enabled then return end
	UI.Enabled = false
	
	if TBP_Settings then
		TBP_Settings:setEnabled(false)
	end
end

-- Init
function TopBarGui.Init()
	
	TBP_Settings = TopBarPlus.new()

	local MobileMute;
	MobileMute = TopBarPlus.new()
		:setImage(MUTE_ICON)
		:setLabel("Mute")
		:bindEvent("selected", function()
			SoundController.PlaySoundOnce("UI", "SmallClick")
			if MusicController.IsPlaying() then
				MusicController.Pause()
				MobileMute:setCaption("Unmute")
				MobileMute:setImage(UNMUTE_ICON)
			else
				MusicController.Play()
				MobileMute:setCaption("Mute")
				MobileMute:setImage(MUTE_ICON)
			end
		end)

	local MobileSkipSong = TopBarPlus.new()
		:setLabel("Skip Song")
		:setImage(SKIP_MUSIC_ICON)
		:bindEvent("selected", function()
			SoundController.PlaySoundOnce("UI", "SmallClick")
			MusicController.SkipSong()
		end)
	
	local SocialMedia = TopBarPlus.new()
		:setLabel("Social Media")
		:setImage("rbxassetid://2802466058")
		:bindEvent("selected", function()
			SoundController.PlaySoundOnce("UI", "SmallClick")
			TBP_Settings:deselect()
			require(PlayerGui.SocialMedia.Logic).Toggle()
		end)
	
	local ChangeLanguage = TopBarPlus.new()
		:setLabel("Language")
		:setImage(FLAG_ICON)
		:bindEvent("selected", function()
			SoundController.PlaySoundOnce("UI", "SmallClick")
			TBP_Settings:deselect()
			if PlayerGui:FindFirstChild("Language") then
				PlayerGui.Language.Enabled = not PlayerGui.Language.Enabled
			end
		end)
	
	local Credits = TopBarPlus.new()
		:setLabel("Credits")
		:setImage("rbxassetid://17024204551")
		:bindEvent("selected", function()
			SoundController.PlaySoundOnce("UI", "SmallClick")
			TBP_Settings:deselect()
			require(PlayerGui.Credits.Logic).Toggle()
		end)
	
	local Contents = {
		MobileMute,
		MobileSkipSong,
		SocialMedia,
		ChangeLanguage,
		Credits
	}

	TBP_Settings
		:setImage(SETTINGS_ICON)
		--:setCaption("Settings")
		--:oneClick()
		:modifyTheme({"Dropdown", "MaxIcons", #Contents})
		:modifyChildTheme({"Widget", "MinimumWidth", 158})
		:setDropdown(Contents)
	
	-- Localization
	UIUpdateEvent.OnClientEvent:Connect(function(data)
		local lang = data.lang or "_default"
		
		MobileMute:setLabel(LocalizationLoader.get("Mute", lang))
		MobileSkipSong:setLabel(LocalizationLoader.get("Skip Song", lang))
		SocialMedia:setLabel(LocalizationLoader.get("Social Media", lang))
		ChangeLanguage:setLabel(LocalizationLoader.get("Language", lang))
		Credits:setLabel(LocalizationLoader.get("Credits", lang))
	end)
end


return TopBarGui
