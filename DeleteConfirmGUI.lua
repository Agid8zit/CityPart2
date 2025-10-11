local Players     = game:GetService("Players")
local SoundCtrl   = require(game.ReplicatedStorage.Scripts.Controllers.SoundController)

local player      = Players.LocalPlayer
local gui         = player.PlayerGui:WaitForChild("DeleteConfirm")   -- ScreenGui
local Main		  = gui.MainFrame
local cont		  = Main.Container
local yesButton   = cont.Delete
local noButton    = cont.Dismiss
gui.Enabled       = false

local currentCB   = nil      -- callback we call with true/false

local function pop(result)
	if currentCB then
		currentCB(result)
		currentCB = nil
	end
	gui.Enabled = false
end

yesButton.MouseButton1Click:Connect(function()
	SoundCtrl.PlaySoundOnce("UI", "SmallClick")
	pop(true)
end)
noButton.MouseButton1Click:Connect(function()
	SoundCtrl.PlaySoundOnce("UI", "SmallClick")
	pop(false)
end)

return {
	Prompt = function(zoneId, cb)
		currentCB     = cb
		gui.Enabled   = true
	end
}