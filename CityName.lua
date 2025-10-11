local CityName = {}

-- Services
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local GuiService        = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Optional deps
local UtilityGUIOk, UtilityGUI: any = pcall(function()
	return require(ReplicatedStorage.Scripts.UI.UtilityGUI)
end)
local SoundControllerOk, SoundController: any = pcall(function()
	return require(ReplicatedStorage.Scripts.Controllers.SoundController)
end)

-- UI
local UI: ScreenGui = script.Parent :: ScreenGui
local LocalPlayer: Player = Players.LocalPlayer

local UI_MainFrame: Frame = UI:WaitForChild("MainFrame") :: Frame
local UI_Inner: Frame = (UI_MainFrame:WaitForChild("Container") :: Frame):WaitForChild("Container") :: Frame
local UI_Content: Frame = UI_Inner:WaitForChild("Content") :: Frame
local UI_Header: TextLabel = UI_Content:WaitForChild("header") :: TextLabel
local UI_SearchBox: TextBox = UI_Content:WaitForChild("searchBox") :: TextBox
local UI_Ok: GuiButton = UI_Content:WaitForChild("Ok") :: GuiButton
local UI_Exit: GuiButton = UI_Inner:WaitForChild("Exit") :: GuiButton

-- Remotes (compat)
local Events = ReplicatedStorage:WaitForChild("Events") :: Folder
local function findRF(name: string): RemoteFunction?
	local rfFolder = Events:FindFirstChild("RemoteFunctions")
	if rfFolder and rfFolder:IsA("Folder") then
		local rf = rfFolder:FindFirstChild(name)
		if rf and rf:IsA("RemoteFunction") then return rf end
	end
	local reFolder = Events:FindFirstChild("RemoteEvents")
	if reFolder and reFolder:IsA("Folder") then
		local rf2 = reFolder:FindFirstChild(name)
		if rf2 and rf2:IsA("RemoteFunction") then return rf2 end
	end
	return nil
end

local RF_FilterCityName: RemoteFunction? = findRF("FilterCityName")
local RF_ConfirmCityName: RemoteFunction? = findRF("ConfirmCityName")
local RF_SwitchToSlot: RemoteFunction?    = findRF("SwitchToSlot")

-- Local state
local storedFilteredText: string = ""
local lastFilterToken = 0

-- Helpers ------------------------------------------------------------------
local function playClick()
	if SoundControllerOk and SoundController and typeof(SoundController.PlaySoundOnce) == "function" then
		SoundController.PlaySoundOnce("UI", "SmallClick")
	end
end

local function filterTextServer(raw: string): string
	if raw == "" then return "" end
	if not RF_FilterCityName then
		warn("[CityName] RF_FilterCityName missing")
		return ""
	end
	local ok, result = pcall(function()
		return (RF_FilterCityName :: RemoteFunction):InvokeServer(raw)
	end)
	if ok and typeof(result) == "string" then
		return result :: string
	end
	warn("[CityName] Filter invoke failed: ", result)
	return ""
end

local MIN_LEN = 3
local MAX_LEN = 32
local function isBadName(filtered: string): boolean
	if filtered == "" then return true end
	local trimmed = filtered:gsub("^%s+", ""):gsub("%s+$", "")
	if trimmed:gsub("%s+", "") == "" then return true end
	local n = #trimmed
	return (n < MIN_LEN) or (n > MAX_LEN)
end

local function debounceFilterApply()
	lastFilterToken += 1
	local token = lastFilterToken
	task.delay(0.25, function()
		if token ~= lastFilterToken then return end
		UI_SearchBox.Text = filterTextServer(UI_SearchBox.Text or "")
		storedFilteredText = UI_SearchBox.Text
	end)
end

local function focusForController()
	UI_SearchBox.Selectable = true
	GuiService.SelectedObject = UI_SearchBox
	UI_Ok.Selectable = true
	UI_Exit.Selectable = true
end

local exitDebounce = false
local function doExit()
	if exitDebounce then return end
	exitDebounce = true
	playClick()
	UI.Enabled = false
	UI:SetAttribute("PendingSlotId", nil) -- clear staged
	if GuiService.SelectedObject then
		GuiService.SelectedObject = nil
	end
	task.delay(0.1, function() exitDebounce = false end)
end

-- Public API ---------------------------------------------------------------
function CityName.OnShow(): ()
	UI.Enabled = true
	if UI_Header:GetAttribute("LangKey") ~= "City Name" then
		UI_Header:SetAttribute("LangKey", "City Name")
	end
	UI_SearchBox.Text = storedFilteredText
	pcall(function() UI_SearchBox.ClearTextOnFocus = false end)
	focusForController()
end

function CityName.OnHide(): ()
	UI.Enabled = false
	if GuiService.SelectedObject then
		GuiService.SelectedObject = nil
	end
end

function CityName.Toggle(): ()
	if UI.Enabled then CityName.OnHide() else CityName.OnShow() end
end

function CityName.Init(): ()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not UI.Enabled or processed then return end
		local kc = input.KeyCode
		if kc == Enum.KeyCode.ButtonB or kc == Enum.KeyCode.Escape then
			doExit()
		end
	end)

	if UtilityGUIOk and UtilityGUI and typeof(UtilityGUI.VisualMouseInteraction) == "function" then
		UtilityGUI.VisualMouseInteraction(
			UI_Exit, UI_Exit,
			TweenInfo.new(0.15),
			{ Size = UDim2.fromScale(0.3, 0.3) },
			{ Size = UDim2.fromScale(0.05, 0.05) }
		)
	end

	UI_Exit.Active = true
	UI_Exit.AutoButtonColor = true
	UI_Exit.Activated:Connect(doExit)

	UI_Ok.Active = true
	UI_Ok.AutoButtonColor = true
	UI_Ok.Activated:Connect(function()
		playClick()

		-- 1) filter + validate
		local filtered = filterTextServer(UI_SearchBox.Text or "")
		UI_SearchBox.Text = filtered
		storedFilteredText = filtered

		if isBadName(filtered) then
			UI_SearchBox.Text = ""
			UI_SearchBox.PlaceholderText = ("Name must be %d–%d chars."):format(MIN_LEN, MAX_LEN)
			return
		end

		-- staged id (if user came from NEW)
		local pendingAttr = UI:GetAttribute("PendingSlotId")
		local pending: string? = (typeof(pendingAttr) == "string") and (pendingAttr :: string) or nil

		print(("[CityName] OK. pending=%s, name='%s'"):format(tostring(pending), filtered))

		-- 2) create/switch NOW (saves current inside SwitchToSlot). Only if NEW was pressed.
		if pending then
			if not RF_SwitchToSlot then
				warn("[CityName] RF_SwitchToSlot missing")
				UI_SearchBox.PlaceholderText = "Switch failed. Try again."
				return
			end
			local okSw, swRes = pcall(function()
				return (RF_SwitchToSlot :: RemoteFunction):InvokeServer(pending, true) -- boolean
			end)
			if not okSw or swRes ~= true then
				warn("[CityName] SwitchToSlot failed: ", tostring(swRes))
				UI_SearchBox.PlaceholderText = "Could not switch/create slot."
				return
			end
			UI:SetAttribute("PendingSlotId", nil)
		end

		-- 3) confirm the city name on the *current* slot (server validates + saves)
		if not RF_ConfirmCityName then
			warn("[CityName] RF_ConfirmCityName missing")
			UI_SearchBox.PlaceholderText = "Save failed. Try again."
			return
		end
		local okC, result = pcall(function()
			return (RF_ConfirmCityName :: RemoteFunction):InvokeServer(filtered)
		end)
		if not okC or typeof(result) ~= "table" then
			warn("[CityName] ConfirmCityName invoke error: ", result)
			UI_SearchBox.PlaceholderText = "Save failed. Try again."
			return
		end

		local resTbl = result :: { ok: boolean, reason: string? }
		if not resTbl.ok then
			if resTbl.reason == "BAD_NAME" then
				UI_SearchBox.Text = ""
				UI_SearchBox.PlaceholderText = ("Name must be %d–%d chars."):format(MIN_LEN, MAX_LEN)
			else
				UI_SearchBox.PlaceholderText = "Save failed. Try again."
			end
			return
		end

		print("[CityName] Name saved.")
		-- 4) close
		doExit()
	end)

	UI_SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
		if not UI.Enabled then return end
		debounceFilterApply()
	end)

	UI_SearchBox.FocusLost:Connect(function()
		local filtered = filterTextServer(UI_SearchBox.Text or "")
		UI_SearchBox.Text = filtered
		storedFilteredText = filtered
	end)

	UI.Enabled = false
end

return CityName