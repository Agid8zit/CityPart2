-- ModuleScript: CityName

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
local PlayerDataControllerOk, PlayerDataController: any = pcall(function()
	return require(ReplicatedStorage.Scripts.Controllers.PlayerDataController)
end)

-- UI
local UI: ScreenGui = script.Parent :: ScreenGui
local LocalPlayer: Player = Players.LocalPlayer
local PlayerGui: PlayerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

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

local REFolder = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents")
local StepCompleted = REFolder:WaitForChild("OnboardingStepCompleted")

-- We no longer call FilterCityName while typing; we only confirm at the end.
local RF_ConfirmCityName: RemoteFunction? = findRF("ConfirmCityName")
local RF_SwitchToSlot: RemoteFunction?    = findRF("SwitchToSlot")

-- Local state
-- RENAMED: we now store the user's *raw* local text (not filtered).
local storedRawText: string = ""
local userHasLocalOverride = false
local suppressTextSignal = false

-- Helpers ------------------------------------------------------------------
local MIN_LEN = 3
local MAX_LEN = 32

local function playClick()
	if SoundControllerOk and SoundController and typeof(SoundController.PlaySoundOnce) == "function" then
		SoundController.PlaySoundOnce("UI", "SmallClick")
	end
end

local function normalizeName(value: any): string
	if typeof(value) ~= "string" then return "" end
	-- keep trimming only; the server will collapse internal whitespace during confirm
	return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function setStoredRaw(value: any)
	storedRawText = normalizeName(value)
end

local function applyServerCityName(text: string?)
	suppressTextSignal = true
	UI_SearchBox.Text = text or ""
	suppressTextSignal = false
	setStoredRaw(UI_SearchBox.Text)
	userHasLocalOverride = false
end

local function ulen(s: string): number
	local ok, n = pcall(function() return utf8.len(s) end)
	if ok and n then return n :: number end
	return #s
end

local function isBadNameLocal(raw: string): boolean
	local trimmed = normalizeName(raw)
	if trimmed == "" then return true end
	-- reject pure whitespace after collapsing visually
	if trimmed:gsub("%s+", "") == "" then return true end
	local n = ulen(trimmed)
	return (n < MIN_LEN) or (n > MAX_LEN)
end

local function needsPromptName(current: any): boolean
	local trimmed = normalizeName(current)
	if trimmed == "" then return true end
	return (ulen(trimmed) < MIN_LEN)
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
	userHasLocalOverride = false
	UI:SetAttribute("PendingSlotId", nil) -- clear staged
	if GuiService.SelectedObject then
		GuiService.SelectedObject = nil
	end
	task.delay(0.1, function() exitDebounce = false end)
end

local function closeLoadMenuGui()
	local loadGui = PlayerGui:FindFirstChild("LoadMenu")
	if not (loadGui and loadGui:IsA("ScreenGui")) then
		return
	end

	local logic = loadGui:FindFirstChild("Logic")
	if logic and logic:IsA("ModuleScript") then
		local ok, loadMenu = pcall(function()
			return require(logic)
		end)
		if ok and type(loadMenu) == "table" and type(loadMenu.OnHide) == "function" then
			local success, err = pcall(loadMenu.OnHide)
			if not success then
				warn("[CityName] LoadMenu.OnHide failed: ", err)
			end
			return
		end
	end

	loadGui.Enabled = false
end

-- Public API ---------------------------------------------------------------
function CityName.OnShow(): ()
	UI.Enabled = true
	if UI_Header:GetAttribute("LangKey") ~= "City Name" then
		UI_Header:SetAttribute("LangKey", "City Name")
	end
	UI_SearchBox.PlaceholderText = ("Enter a name (%d-%d chars)"):format(MIN_LEN, MAX_LEN)
	UI_SearchBox.Text = storedRawText
	pcall(function() UI_SearchBox.ClearTextOnFocus = false end)
	focusForController()
	-- place caret at end for convenience
	pcall(function()
		UI_SearchBox.CursorPosition = #UI_SearchBox.Text + 1
	end)
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

		-- 1) local validate only (no server filtering here)
		local raw = normalizeName(UI_SearchBox.Text or "")
		setStoredRaw(raw)

		if isBadNameLocal(raw) then
			UI_SearchBox.Text = ""
			UI_SearchBox.PlaceholderText = ("Name must be %d-%d chars."):format(MIN_LEN, MAX_LEN)
			return
		end

		-- staged id (if user came from NEW)
		local pendingAttr = UI:GetAttribute("PendingSlotId")
		local pending: string? = (typeof(pendingAttr) == "string") and (pendingAttr :: string) or nil

		print(("[CityName] OK. pending=%s, raw='%s'"):format(tostring(pending), raw))

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

		-- 3) confirm the city name on the *current* slot (server validates + saves + filters)
		if not RF_ConfirmCityName then
			warn("[CityName] RF_ConfirmCityName missing")
			UI_SearchBox.PlaceholderText = "Save failed. Try again."
			return
		end
		local okC, result = pcall(function()
			return (RF_ConfirmCityName :: RemoteFunction):InvokeServer(raw)
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
				UI_SearchBox.PlaceholderText = ("Name must be %d-%d chars."):format(MIN_LEN, MAX_LEN)
			elseif resTbl.reason == "REJECTED_BY_FILTER" then
				-- The raw text filtered to hashes or empty; prompt user to try another name.
				UI_SearchBox.Text = ""
				UI_SearchBox.PlaceholderText = "That name isn’t allowed. Try a different one."
			else
				UI_SearchBox.PlaceholderText = "Save failed. Try again."
			end
			return
		end

		print("[CityName] Name saved.")
		StepCompleted:FireServer("CityNamed")
		-- 4) close
		doExit()
		closeLoadMenuGui()
	end)

	-- While typing, we *only* keep the local raw string in sync (no server filtering).
	UI_SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
		setStoredRaw(UI_SearchBox.Text or "")
		if not UI.Enabled then return end
		if suppressTextSignal then return end
		userHasLocalOverride = true
	end)

	-- On focus lost, just trim locally; do not filter via server.
	UI_SearchBox.FocusLost:Connect(function()
		local trimmed = normalizeName(UI_SearchBox.Text or "")
		if UI_SearchBox.Text ~= trimmed then
			suppressTextSignal = true
			UI_SearchBox.Text = trimmed
			suppressTextSignal = false
		end
		setStoredRaw(trimmed)
	end)

	if PlayerDataControllerOk and PlayerDataController then
		local function handlePlayerData(pd)
			if typeof(pd) ~= "table" then return end
			local currentSlot = pd.currentSaveFile
			if typeof(currentSlot) ~= "string" then return end
			local savefiles = pd.savefiles
			if typeof(savefiles) ~= "table" then return end
			local sf = savefiles[currentSlot]
			if typeof(sf) ~= "table" then return end

			-- Prefer saved filtered cityName if present, otherwise prompt.
			local serverName = tostring(sf.cityName or "")
			if needsPromptName(sf.cityName) then
				local placeholder = ("Enter a name (%d-%d chars)"):format(MIN_LEN, MAX_LEN)
				if not UI.Enabled then
					applyServerCityName("")
					UI_SearchBox.PlaceholderText = placeholder
					CityName.OnShow()
				elseif not userHasLocalOverride then
					applyServerCityName("")
					UI_SearchBox.PlaceholderText = placeholder
				end
				return
			end

			if userHasLocalOverride then
				if normalizeName(storedRawText) ~= normalizeName(serverName) then
					return
				end
				userHasLocalOverride = false
			end

			applyServerCityName(serverName)
		end

		if typeof(PlayerDataController.ListenForAnyDataChange) == "function" then
			PlayerDataController.ListenForAnyDataChange(handlePlayerData)
		end

		if typeof(PlayerDataController.GetData) == "function" then
			local current = PlayerDataController.GetData()
			if current then
				handlePlayerData(current)
			end
		end
	end

	UI.Enabled = false
end

return CityName
