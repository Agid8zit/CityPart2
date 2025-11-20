local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local I18N      = require(ReplicatedStorage.Localization.Localizing)
local SoundCtrl = require(ReplicatedStorage.Scripts.Controllers.SoundController)
local Abr       = require(ReplicatedStorage.Scripts.UI.Abrv)

local player = Players.LocalPlayer
local gui    = player.PlayerGui:WaitForChild("DeleteConfirm") -- ScreenGui

local Main         = gui.MainFrame
local cont         = Main.Container
local contf        = cont.Container
local yesButton    = cont.Delete
local noButton     = cont.Dismiss
local ContentFrame = contf.Content
local ConfirmLbl   = ContentFrame.body1 :: TextLabel
local AmountLbl    = ContentFrame.body2 :: TextLabel

local CURRENT_LANGUAGE = "English"

local Events = ReplicatedStorage:WaitForChild("Events", 5)
local RemoteEvents = Events and Events:WaitForChild("RemoteEvents", 5)
local RF_GetPreview = RemoteEvents and RemoteEvents:WaitForChild("GetDeleteRefundPreview", 5)

local function localizedFormat(key, language, dialect, ...)
	local template = I18N.get(key, language, dialect)
	if type(template) ~= "string" then
		return template
	end

	local args = { ... }
	local ok, formatted = pcall(function()
		return string.format(template, table.unpack(args))
	end)

	if ok then
		return formatted
	end

	return template
end

local function _formatMoney(n)
	if typeof(n) ~= "number" then return "???" end
	if n < 0 then n = 0 end
	return "$" .. tostring(Abr.abbreviateNumber(n))
end

local UNKNOWN_REFUND = "???"
local ZERO_REFUND = "$0"

local function refundLine(preview)
	if preview and preview.ok and typeof(preview.coinRefund) == "number" then
		if preview.coinRefund > 0 then
			return localizedFormat("Refund_Amount", CURRENT_LANGUAGE, nil, _formatMoney(preview.coinRefund))
		end
		return localizedFormat("Refund_Amount", CURRENT_LANGUAGE, nil, ZERO_REFUND)
	end

	if preview then
		if preview.withinWindow == false then
			return localizedFormat("Refund_Amount", CURRENT_LANGUAGE, nil, ZERO_REFUND)
		end

		if preview.isExclusive then
			return localizedFormat("Refund_Amount", CURRENT_LANGUAGE, nil, UNKNOWN_REFUND)
		end
	end

	return localizedFormat("Refund_Amount", CURRENT_LANGUAGE, nil, UNKNOWN_REFUND)
end

if ConfirmLbl then ConfirmLbl.RichText = true end
if AmountLbl then AmountLbl.RichText = true end

gui.Enabled = false

local currentCB = nil

local function closeWith(result: boolean)
	if currentCB then
		currentCB(result)
		currentCB = nil
	end
	gui.Enabled = false
end

yesButton.MouseButton1Click:Connect(function()
	SoundCtrl.PlaySoundOnce("UI", "SmallClick")
	closeWith(true)
end)

noButton.MouseButton1Click:Connect(function()
	SoundCtrl.PlaySoundOnce("UI", "SmallClick")
	closeWith(false)
end)

return {
	Prompt = function(zoneId: string, cb: (boolean)->())
		currentCB   = cb
		gui.Enabled = true

		ConfirmLbl.Text = I18N.get("ConfirmDelete", CURRENT_LANGUAGE)
		AmountLbl.Text  = localizedFormat("Refund_Amount", CURRENT_LANGUAGE, nil, "???")

		local preview = nil
		if RF_GetPreview and RF_GetPreview:IsA("RemoteFunction") then
			local ok, res = pcall(function()
				return RF_GetPreview:InvokeServer(zoneId)
			end)
			if ok and res then
				preview = res
			end
		end

		AmountLbl.Text = refundLine(preview)
	end,
}
