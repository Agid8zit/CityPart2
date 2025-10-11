local RobuxThanks = {}

-- Roblox Services
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies
local UtilityGUI = require(ReplicatedStorage.Scripts.UI.UtilityGUI)
local SoundController = require(ReplicatedStorage.Scripts.Controllers.SoundController)

-- Defines
local UI = script.Parent

-- UI References
local UI_Exit = UI.MainFrame.Container.Container.Exit
local UI_DismissButton = UI.MainFrame.Container.Container.Content.Dismiss

-- Networking
local RE_ThanksForSupportingUs = ReplicatedStorage.Events.RemoteEvents.ThanksForSupportingUs

-- Module Functions
function RobuxThanks.OnShow()
	UI.Enabled = true
end

function RobuxThanks.OnHide()
	UI.Enabled = false
end

function RobuxThanks.Toggle()
	if UI.Enabled then
		RobuxThanks.OnHide()
	else
		RobuxThanks.OnShow()
	end
end

function RobuxThanks.Init()
	UserInputService.InputBegan:Connect(function(InputObject, GameProcessedEvent)
		if not UI.Enabled then return end
		if GameProcessedEvent then return end

		if InputObject.KeyCode == Enum.KeyCode.ButtonB then
			SoundController.PlaySoundOnce("UI", "SmallClick")
			RobuxThanks.OnHide()
		end
	end)
	
	-- Exit Button
	UI_Exit.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		RobuxThanks.OnHide()
	end)

	-- Exit Button VFX
	UtilityGUI.VisualMouseInteraction(
		UI_Exit, UI_Exit,
		TweenInfo.new(0.15),
		{ Size = UDim2.fromScale(0.3, 0.3) },
		{ Size = UDim2.fromScale(0.05, 0.05) }
	)
	
	-- Dismiss Button
	UI_DismissButton.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		RobuxThanks.OnHide()
	end)
	
	-- Networking
	RE_ThanksForSupportingUs.OnClientEvent:Connect(function()
		RobuxThanks.OnShow()
	end)
end

return RobuxThanks
