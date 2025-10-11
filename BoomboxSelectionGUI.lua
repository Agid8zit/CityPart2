local BoomboxSelection = {}

-- Roblox Services
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Constants
local BUTTON_UNSELECTED_COLOR = Color3.fromRGB(76, 122, 234)
local BUTTON_SELECTED_COLOR = Color3.fromRGB(234, 172, 72)

-- Defines
local UI = script.Parent
local LocalPlayer = Players.LocalPlayer
local ButtonFrames = {} -- [MusicID] = Frame

-- Dependencies
local Utility = require(ReplicatedStorage.Scripts.Utility)
local UtilityGUI = require(ReplicatedStorage.Scripts.UI.UtilityGUI)
local BoomboxMusic = require(ReplicatedStorage.Scripts.BoomboxMusic)
local SoundController = require(ReplicatedStorage.Scripts.Controllers.SoundController)
local PlayerDataController = require(ReplicatedStorage.Scripts.Controllers.PlayerDataController)

-- UI References
local UI_Exit = UI.MainFrame.Exit
local UI_Stop = UI.MainFrame.Stop
local UI_ButtonTemplate = UI.MainFrame.Container.Content.ButtonTemplate; UI_ButtonTemplate.Visible = false
local UI_CurrentSongText = UI.MainFrame.Container.Header.CurentSong

-- Networking
local RE_SetBoomboxMusic = ReplicatedStorage.Events.RemoteEvents.SetBoomboxMusic

-- Module Functions
function BoomboxSelection.OnShow()
	if UI.Enabled then return end
	UI.Enabled = true
end

function BoomboxSelection.OnHide()
	if not UI.Enabled then return end
	UI.Enabled = false
end

function BoomboxSelection.Toggle()
	if UI.Enabled then
		UI.Enabled = false
	else
		UI.Enabled = true
	end
end

function BoomboxSelection.Init()
	-- Inputs
	UserInputService.InputBegan:Connect(function(InputObject)
		if not UI.Enabled then return end
		if InputObject.KeyCode == Enum.KeyCode.ButtonB then
			BoomboxSelection.OnHide()
		end
	end)
	
	-- Exit Button
	UI_Exit.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		BoomboxSelection.OnHide()
	end)

	-- Exit Button VFX
	UtilityGUI.VisualMouseInteraction(
		UI_Exit, UI_Exit.TextLabel,
		TweenInfo.new(0.15),
		{ Size = UDim2.fromScale(1.25, 1.25) },
		{ Size = UDim2.fromScale(0.5, 0.5) }
	)
	
	-- Stop Button
	UI_Stop.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		RE_SetBoomboxMusic:FireServer(nil)
	end)

	-- Exit Button VFX
	UtilityGUI.VisualMouseInteraction(
		UI_Stop, UI_Stop.ImageLabel,
		TweenInfo.new(0.15),
		{ Size = UDim2.fromScale(1.25, 1.25) },
		{ Size = UDim2.fromScale(0.5, 0.5) }
	)
	
	local MusicIDAlphabetical = {}
	for MusicID, Data in BoomboxMusic do
		table.insert(MusicIDAlphabetical, MusicID)
	end
	table.sort(MusicIDAlphabetical)
	
	for _, MusicID in MusicIDAlphabetical do
		local FrameButton = UI_ButtonTemplate:Clone()
		FrameButton.Visible = true
		FrameButton.Text = MusicID
		FrameButton.Parent = UI_ButtonTemplate.Parent
		
		FrameButton.MouseButton1Down:Connect(function()
			RE_SetBoomboxMusic:FireServer(MusicID)
		end)
		
		ButtonFrames[MusicID] = FrameButton
	end
	
	-- Current Song
	if LocalPlayer:GetAttribute("BoomboxMusicID") then
		local MusicID = LocalPlayer:GetAttribute("BoomboxMusicID")
		if MusicID then
			UI_CurrentSongText.Text = "[ "..MusicID.." ]"
		else
			UI_CurrentSongText.Text = "[ ... ]"
		end
		
		for FrameMusicID, FrameButton in ButtonFrames do
			if FrameMusicID == MusicID then
				FrameButton.BackgroundColor3 = BUTTON_SELECTED_COLOR
			else
				FrameButton.BackgroundColor3 = BUTTON_UNSELECTED_COLOR
			end
		end
	end
	LocalPlayer:GetAttributeChangedSignal("BoomboxMusicID"):Connect(function()
		local MusicID = LocalPlayer:GetAttribute("BoomboxMusicID")
		if MusicID then
			UI_CurrentSongText.Text = "[ "..MusicID.." ]"
		else
			UI_CurrentSongText.Text = "[ ... ]"
		end
		
		for FrameMusicID, FrameButton in ButtonFrames do
			if FrameMusicID == MusicID then
				FrameButton.BackgroundColor3 = BUTTON_SELECTED_COLOR
			else
				FrameButton.BackgroundColor3 = BUTTON_UNSELECTED_COLOR
			end
		end
	end)
end

return BoomboxSelection
