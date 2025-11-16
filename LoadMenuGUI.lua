local LoadMenu = {}

-- Services
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local TweenService        = game:GetService("TweenService")
local UserInputService    = game:GetService("UserInputService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local LocalizationService = game:GetService("LocalizationService")
local CityLoader = require(ReplicatedStorage.Scripts.UI.CityLoader)

-- Optional deps
local ConstantsOk, ConstantsAny = pcall(function()
	return require(ReplicatedStorage.Scripts.Constants)
end)
local Constants: any = ConstantsOk and ConstantsAny or { MAX_SAVE_FILES = 6 }

local UtilityGUIOk, UtilityGUI: any = pcall(function()
	return require(ReplicatedStorage.Scripts.UI.UtilityGUI)
end)

-- Types
type SaveRow = { id: string, cityName: string?, lastPlayed: number? }
type SlotsResp = { current: string, slots: {SaveRow} }

local BUTTON_COLOR_NEW    = Color3.fromRGB(255, 255, 255)
local BUTTON_COLOR_DELETE = Color3.fromRGB(220, 70, 70)

-- UI
local LocalPlayer: Player = Players.LocalPlayer
local PlayerGui: PlayerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
local UI: ScreenGui = script.Parent :: ScreenGui

local UI_Main: Frame = UI:WaitForChild("Main") :: Frame
local UI_Exit: GuiButton = UI_Main:WaitForChild("Exit") :: GuiButton
local UI_DeleteSaveBtn: GuiButton = UI_Main:WaitForChild("DeleteSave") :: GuiButton

local UI_Container: Frame = UI_Main:WaitForChild("Container") :: Frame
local UI_Invite: Frame = UI_Container:WaitForChild("Invite") :: Frame
local UI_Saves: Frame = UI_Invite:WaitForChild("Saves") :: Frame
local UI_ScrollingFrame: ScrollingFrame = UI_Saves:WaitForChild("ScrollingFrame") :: ScrollingFrame
local UI_Template: Frame = UI_ScrollingFrame:WaitForChild("ref_templateNew") :: Frame
UI_Template.Visible = false

local UI_LoadingScreen: Frame = UI:WaitForChild("LoadingScreen") :: Frame
local UI_LoadingIcon: ImageLabel = UI_LoadingScreen:WaitForChild("ImageLabel") :: ImageLabel
local UI_LoadingText: TextLabel = UI_LoadingScreen:WaitForChild("LoadingText") :: TextLabel

local UI_DeleteModal: Frame = UI:WaitForChild("DeleteSave") :: Frame
local UI_DeleteModal_Yes: Instance = UI_DeleteModal:WaitForChild("Yes")
local UI_DeleteModal_No: Instance  = UI_DeleteModal:WaitForChild("No")

-- Remotes
local EventsFolder: Folder = ReplicatedStorage:WaitForChild("Events") :: Folder
local function findRF(name: string): RemoteFunction?
	local f = EventsFolder:FindFirstChild("RemoteFunctions")
	if f and f:IsA("Folder") then
		local rf = f:FindFirstChild(name)
		if rf and rf:IsA("RemoteFunction") then return rf end
	end
	local fe = EventsFolder:FindFirstChild("RemoteEvents")
	if fe and fe:IsA("Folder") then
		local rf2 = fe:FindFirstChild(name)
		if rf2 and rf2:IsA("RemoteFunction") then return rf2 end
	end
	return nil
end

local RemoteEvents: Folder = EventsFolder:WaitForChild("RemoteEvents")
local WorldReloadRE: RemoteEvent = RemoteEvents:WaitForChild("WorldReload") :: RemoteEvent
local RF_GetSaveSlots: RemoteFunction?   = findRF("GetSaveSlots")
local RF_SwitchToSlot: RemoteFunction?   = findRF("SwitchToSlot")
local RF_DeleteSaveFile: RemoteFunction? = findRF("DeleteSaveFile")

local isReloading = false
WorldReloadRE.OnClientEvent:Connect(function(kind: string, a: any, b: any)
	if kind == "begin" then
		isReloading = true
		CityLoader.Show({ delay = 0, message = "Loading City" })

	elseif kind == "progress" then
		-- a = percent number, b = label string
		local pct = tonumber(a) or 0
		local label = (typeof(b) == "string" and b) or nil
		-- Update bar + (optional) label
		CityLoader.SetProgress(pct, label)

	elseif kind == "end" then
		isReloading = false
		CityLoader.Hide()
	end
end)

-- Spinner tween
local SpinTween: Tween = TweenService:Create(
	UI_LoadingIcon,
	TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0),
	{ Rotation = 359 }
)
SpinTween.Completed:Connect(function()
	UI_LoadingIcon.Rotation = 0
	SpinTween:Play()
end)

local LoadingHB: RBXScriptConnection? = nil
local LoadMutex = false

-- Delete Mode state
local DeleteMode = false
local PendingDeleteSlotId: string? = nil

-- Helpers ------------------------------------------------------------------

-- Preferred locale with sensible defaults
local function getPreferredLocale(): string
	local loc = LocalizationService.RobloxLocaleId
	if typeof(loc) ~= "string" or loc == "" then
		-- some environments expose SystemLocaleId; use it if present
		local ok, sys = pcall(function() return LocalizationService.SystemLocaleId end)
		if ok and typeof(sys) == "string" and sys ~= "" then
			loc = sys
		else
			loc = "en-us"
		end
	end
	return string.lower(loc)
end

-- Trim name and fall back to "City <slotId>"
local function resolveSaveDisplayName(raw: any, slotId: string): string
	local text = ""
	if typeof(raw) == "string" then
		-- remove leading/trailing whitespace
		text = raw:gsub("^%s+", ""):gsub("%s+$", "")
	end
	if text == "" then
		return ("City %s"):format(slotId)
	end
	return text
end

-- Locale-aware "Last Played" label with seconds/ms handling
local function formatLastPlayedLabel(timestamp: any): string
	local value = tonumber(timestamp)
	if not value or value <= 0 then
		return "Last Played: -"
	end

	local ok, dt
	if value > 1e12 then
		-- looks like milliseconds
		ok, dt = pcall(DateTime.fromUnixTimestampMillis, value)
	else
		ok, dt = pcall(DateTime.fromUnixTimestamp, value)
	end
	if not ok or not dt then
		return "Last Played: —"
	end

	local locale = getPreferredLocale()
	local okFmt, formatted = pcall(function()
		-- "LLL" = localized long date + time (e.g., "Sep 12, 2025 3:45 PM")
		return dt:FormatLocalTime("LLL", locale)
	end)
	if not okFmt or typeof(formatted) ~= "string" or formatted == "" then
		-- conservative fallback
		local okFmt2; okFmt2, formatted = pcall(function()
			return dt:FormatLocalTime("yyyy-MM-dd HH:mm", locale)
		end)
		if not okFmt2 then
			return "Last Played: —"
		end
	end

	return ("Last Played: %s"):format(formatted)
end

local INLINE_DATE_COLOR_HEX = "B6BDC7"

local function escapeRichText(text: any): string
	if typeof(text) ~= "string" then
		if text == nil then
			text = ""
		else
			text = tostring(text)
		end
	end
	return (text :: string)
		:gsub("&", "&amp;")
		:gsub("<", "&lt;")
		:gsub(">", "&gt;")
end

local function applyNameAndLastPlayed(frame: Frame, displayName: string, lastPlayedStamp: any)
	local nameLbl = frame:FindFirstChild("name")
	local dateLbl = frame:FindFirstChild("date")
	local formattedDate = formatLastPlayedLabel(lastPlayedStamp)

	if dateLbl and dateLbl:IsA("TextLabel") then
		dateLbl.Visible = true
		dateLbl.TextTransparency = 0
		dateLbl.Text = formattedDate
		if nameLbl and nameLbl:IsA("TextLabel") then
			nameLbl.RichText = false
			nameLbl.TextWrapped = true
			nameLbl.TextTruncate = Enum.TextTruncate.None
			nameLbl.TextYAlignment = Enum.TextYAlignment.Top
			nameLbl.Text = displayName
		end
		return
	end

	if nameLbl and nameLbl:IsA("TextLabel") then
		nameLbl.RichText = true
		nameLbl.TextWrapped = true
		nameLbl.TextTruncate = Enum.TextTruncate.None
		nameLbl.TextYAlignment = Enum.TextYAlignment.Top
		nameLbl.Text = string.format(
			"%s\n<font color=\"#%s\" size=\"18\">%s</font>",
			escapeRichText(displayName),
			INLINE_DATE_COLOR_HEX,
			escapeRichText(formattedDate)
		)
	end
end

local function resolveGuiButton(obj: Instance?): GuiButton?
	if not obj then return nil end
	if obj:IsA("GuiButton") then return obj end
	-- find first TextButton or ImageButton anywhere inside
	return (obj:FindFirstChildWhichIsA("TextButton", true) :: GuiButton?)
		or (obj:FindFirstChildWhichIsA("ImageButton", true) :: GuiButton?)
end

local function openCityNameGui(): ScreenGui?
	local g = PlayerGui:FindFirstChild("CityName")
	if g and g:IsA("ScreenGui") then
		(g :: ScreenGui).Enabled = true
		return g :: ScreenGui
	end
	warn("[LoadMenu] 'CityName' GUI not found")
	return nil
end

local function showLoading(afterSeconds: number?)
	-- same UX as before: don't flash UI for ultra‑fast calls
	CityLoader.Show({
		delay = afterSeconds or 0.6,
		message = "Loading Save", -- text inside the fancy UI's "Loading..." label
	})
end

local function hideLoading()
	CityLoader.Hide()
end

-- Data ---------------------------------------------------------------------
local function fetchSlots(): SlotsResp?
	if not RF_GetSaveSlots then
		warn("[LoadMenu] RF_GetSaveSlots missing")
		return nil
	end
	local ok, res = pcall(function() return (RF_GetSaveSlots :: RemoteFunction):InvokeServer() end)
	if ok and typeof(res) == "table" then
		return res :: SlotsResp
	end
	warn("[LoadMenu] GetSaveSlots failed: ", res)
	return nil
end

-- UI painters --------------------------------------------------------------
local function clearTiles()
	for _, child in ipairs(UI_ScrollingFrame:GetChildren()) do
		if child:IsA("Frame") and child ~= UI_Template then
			child:Destroy()
		end
	end
end

local function makeTile(order: number): Frame
	local f = UI_Template:Clone()
	f.Visible = true
	f.LayoutOrder = order
	f.Parent = UI_ScrollingFrame
	return f
end

local function paintAsSave(frame: Frame, s: SaveRow, isCurrent: boolean, inDeleteMode: boolean)
	local icon = frame:FindFirstChild("icon") :: ImageLabel?
	local right = frame:FindFirstChild("right")
	local btn = (right and right:FindFirstChildWhichIsA("ImageButton")) :: ImageButton?
	local btnText = (btn and btn:FindFirstChildWhichIsA("TextLabel")) :: TextLabel?
	local displayName = resolveSaveDisplayName(s.cityName, s.id)

	if icon then
		icon.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", LocalPlayer.UserId)
	end
	applyNameAndLastPlayed(frame, displayName, s.lastPlayed)

	if not (btn and btnText) then return end

	if inDeleteMode then
		-- DELETE MODE
		btn.Active = true
		btn.AutoButtonColor = true
		btn.BackgroundColor3 = BUTTON_COLOR_DELETE
		btnText.Text = "DELETE"
		btn.Activated:Connect(function()
			if LoadMutex then return end
			if not RF_DeleteSaveFile then
				warn("[LoadMenu] RF_DeleteSaveFile missing")
				return
			end
			PendingDeleteSlotId = s.id
			UI_DeleteModal.Visible = true
		end)
	else
		-- NORMAL LOAD MODE
		if isCurrent then
			btn.Active = false
			btn.AutoButtonColor = false
			btn.BackgroundColor3 = Color3.new(1, 1, 1)
			btnText.Text = "LOADED"
		else
			btn.Active = true
			btn.AutoButtonColor = true
			btn.BackgroundColor3 = Color3.new(1, 1, 1)
			btnText.Text = "LOAD"
			btn.Activated:Connect(function()
				if LoadMutex then return end
				if not RF_SwitchToSlot then
					warn("[LoadMenu] RF_SwitchToSlot missing")
					return
				end
				LoadMutex = true

				-- Show right away for snappy UX; the server will keep it up during the reload window
				CityLoader.Show({ delay = 0, message = "Switching Save" })

				local ok, res = pcall(function()
					return (RF_SwitchToSlot :: RemoteFunction):InvokeServer(s.id, false)
				end)
				LoadMutex = false

				if not ok or res ~= true then
					-- No reload will happen on failure, so hide the loader
					CityLoader.Hide()
					warn("[LoadMenu] Load failed: ", tostring(res))
					return
				end

				-- Success: do NOT hide here. We wait for WorldReloadRE "end".
				UI.Enabled = false
			end)
		end
	end
end

local function paintAsNew(frame: Frame)
	local icon = frame:FindFirstChild("icon") :: ImageLabel?
	local right = frame:FindFirstChild("right")
	local btn = (right and right:FindFirstChildWhichIsA("ImageButton")) :: ImageButton?
	local btnText = (btn and btn:FindFirstChildWhichIsA("TextLabel")) :: TextLabel?
	local displayName = "New Save"

	if icon then
		icon.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", LocalPlayer.UserId)
	end
	applyNameAndLastPlayed(frame, displayName, nil)

	if btn and btnText then
		btn.Active = true
		btn.AutoButtonColor = true
		btn.BackgroundColor3 = BUTTON_COLOR_NEW
		btnText.Text = "NEW"
		btn.Activated:Connect(function()
			if LoadMutex then return end
			LoadMutex = true

			local g = openCityNameGui()
			if not g then
				LoadMutex = false
				return
			end

			local resp = fetchSlots()
			if not resp then
				LoadMutex = false
				return
			end
			local taken: {[number]: boolean} = {}
			for _, row in ipairs(resp.slots) do
				local n = tonumber(row.id)
				if n then taken[n] = true end
			end
			local cap = tonumber(Constants.MAX_SAVE_FILES) or 6
			local free: string? = nil
			for i = 1, cap do
				if not taken[i] then free = tostring(i) break end
			end
			if not free then
				warn("[LoadMenu] No free slot available")
				LoadMutex = false
				return
			end

			g:SetAttribute("PendingSlotId", free)
			g:SetAttribute("PendingSlotName", "New Save")
			print("[LoadMenu] NEW clicked -> staged PendingSlotId =", free)

			UI.Enabled = false
			LoadMutex = false
		end)
	end
end

local function adjustCanvas()
	local grid = UI_ScrollingFrame:FindFirstChildWhichIsA("UIGridLayout")
	if grid then
		local layout = grid :: UIGridLayout
		local function refresh()
			local s = layout.AbsoluteContentSize
			UI_ScrollingFrame.CanvasSize = UDim2.fromOffset(s.X, s.Y)
		end
		refresh()
		layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refresh)
	else
		UI_ScrollingFrame.CanvasSize = UDim2.new(0, 0, 1, 0)
	end
end

local function buildTiles()
	clearTiles()

	local resp = fetchSlots()
	local placed = 0
	local cap = tonumber(Constants.MAX_SAVE_FILES) or 6

	if resp then
		-- sort: current first, then by lastPlayed desc
		table.sort(resp.slots, function(a: SaveRow, b: SaveRow)
			if a.id == resp.current then return true end
			if b.id == resp.current then return false end
			return (tonumber(a.lastPlayed or 0) or 0) > (tonumber(b.lastPlayed or 0) or 0)
		end)

		for i, s in ipairs(resp.slots) do
			local f = makeTile(i)
			paintAsSave(f, s, s.id == resp.current, DeleteMode)
			placed += 1
		end

		if (not DeleteMode) and placed < cap then
			local f = makeTile(placed + 1)
			paintAsNew(f)
		end
	else
		local f = makeTile(1)
		paintAsNew(f)
	end

	adjustCanvas()
end

local function setDeleteMode(on: boolean)
	DeleteMode = on
	local lbl = UI_DeleteSaveBtn:FindFirstChildWhichIsA("TextLabel")
	if lbl then
		lbl.Text = on and "Done" or "Delete"
	end
	print("[LoadMenu] DeleteMode =", DeleteMode)
	task.defer(buildTiles)
end

-- Public API ---------------------------------------------------------------
function LoadMenu.OnShow(): ()
	UI.Enabled = true
	buildTiles()
end

function LoadMenu.OnHide(): ()
	UI.Enabled = false
	if DeleteMode then setDeleteMode(false) end
	PendingDeleteSlotId = nil
end

function LoadMenu.Toggle(): ()
	UI.Enabled = not UI.Enabled
	if UI.Enabled then buildTiles() end
end

function LoadMenu.Init(): ()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not UI.Enabled or processed then return end
		if input.KeyCode == Enum.KeyCode.ButtonB then
			LoadMenu.OnHide()
		end
	end)

	if UtilityGUIOk and UtilityGUI and typeof(UtilityGUI.VisualMouseInteraction) == "function" then
		local exitLabel = UI_Exit:FindFirstChildWhichIsA("TextLabel") :: TextLabel?
		UtilityGUI.VisualMouseInteraction(
			UI_Exit,
			exitLabel,
			TweenInfo.new(0.1),
			{ Size = UDim2.fromScale(1.2, 1.2) },
			{ Size = UDim2.fromScale(0.6, 0.6) }
		)
	end

	UI_Exit.Activated:Connect(function() LoadMenu.OnHide() end)

	-- SINGLE wiring for toolbar delete toggle
	UI_DeleteSaveBtn.Active = true
	UI_DeleteSaveBtn.AutoButtonColor = true
	UI_DeleteSaveBtn.Activated:Connect(function()
		setDeleteMode(not DeleteMode)
	end)

	-- Modal actions (robust to Yes/No being frames or buttons)
	do
		local YesBtn = resolveGuiButton(UI_DeleteModal_Yes)
		local NoBtn  = resolveGuiButton(UI_DeleteModal_No)

		local function onNo()
			UI_DeleteModal.Visible = false
			PendingDeleteSlotId = nil
		end

		local function onYes()
			if not PendingDeleteSlotId then
				UI_DeleteModal.Visible = false
				return
			end
			if not RF_DeleteSaveFile then
				warn("[LoadMenu] RF_DeleteSaveFile missing (must be a RemoteFunction)")
				UI_DeleteModal.Visible = false
				PendingDeleteSlotId = nil
				return
			end

			CityLoader.Show({ delay = 0.15, message = "Deleting Save" })
			local ok, res, reason = pcall(function()
				return (RF_DeleteSaveFile :: RemoteFunction):InvokeServer(PendingDeleteSlotId :: string)
			end)

			-- If the delete does NOT trigger a world reload, we hide now.
			-- If the server does trigger a reload, our WorldReloadRE listener keeps it up and hides on "end".
			if not ok or res ~= true then
				CityLoader.Hide()
				warn("[LoadMenu] Delete failed: ", tostring(reason or res))
				PendingDeleteSlotId = nil
				buildTiles()
				return
			else
				-- small defer to allow a possible "begin" to arrive; if none, hide
				task.defer(function()
					if not isReloading then
						CityLoader.Hide()
					end
				end)
			end

			UI_DeleteModal.Visible = false
			if not ok or res ~= true then
				warn("[LoadMenu] Delete failed: ", tostring(reason or res))
				PendingDeleteSlotId = nil
				buildTiles() -- keep delete mode on so they can retry
				return
			end

			PendingDeleteSlotId = nil
			setDeleteMode(false) -- exit delete mode on success
		end

		if YesBtn then
			YesBtn.Activated:Connect(onYes)
			if YesBtn:IsA("TextButton") or YesBtn:IsA("ImageButton") then
				YesBtn.MouseButton1Click:Connect(onYes)
			end
		else
			warn("[LoadMenu] Delete modal YES is not a button (check its hierarchy)")
		end

		if NoBtn then
			NoBtn.Activated:Connect(onNo)
			if NoBtn:IsA("TextButton") or NoBtn:IsA("ImageButton") then
				NoBtn.MouseButton1Click:Connect(onNo)
			end
		else
			warn("[LoadMenu] Delete modal NO is not a button (check its hierarchy)")
		end
	end

	-- Initial state
	UI.Enabled = false
	UI_LoadingScreen.Visible = false
	UI_DeleteModal.Visible = false

	-- First draw
	buildTiles()
end

return LoadMenu
