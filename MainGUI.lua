local MainGui = {}

-- Roblox Services
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Dependencies
local Abr = require(ReplicatedStorage.Scripts.UI.Abrv)
local Events = ReplicatedStorage:WaitForChild("Events")
local Balancing = ReplicatedStorage:WaitForChild("Balancing")
local UtilityGUI = require(ReplicatedStorage.Scripts.UI.UtilityGUI)
local BalanceEconomy = require(Balancing:WaitForChild("BalanceEconomy"))
local SoundController = require(ReplicatedStorage.Scripts.Controllers.SoundController)
local InputController = require(ReplicatedStorage.Scripts.Controllers.InputController)

-- Onboarding wires (for resilient Build button pulse/arrow)
local UITargetRegistry = require(ReplicatedStorage.Scripts.UI.UITargetRegistry)
local RE_OnboardingStepCompleted = ReplicatedStorage.Events.RemoteEvents:WaitForChild("OnboardingStepCompleted")

-- Defines
local UI = script.Parent
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer.PlayerGui
local ExitFunctions = {}
local OBArrow = UI.OnboardingArrow

-- UI References
local UI_ChartsButton = UI.right.charts.ImageButton
local UI_DestroyButton = UI.right.removal.ImageButton
local UI_DeleteButton = UI.right.removal.Delete.ImageButton
local UI_RedoButton = UI.right.removal.Redo.ImageButton
local UI_UndoButton = UI.right.removal.Undo.ImageButton

local UI_DeleteGamepadButton = UI.right.DeleteGamepad.ImageButton
local UI_RedoGamepadButton = UI.right.RedoGamepad.ImageButton
local UI_UndoGamepadButton = UI.right.UndoGamepad.ImageButton

local UI_MapButton = UI.right.map.ImageButton
local UI_MapButtonNotification = UI.right.map.ImageButton.notification
local UI_PremiumShopButton = UI.left.premium.ImageButton
local UI_LoadButton = UI.left.load.ImageButton
local UI_BoomboxButton = UI.left.boombox.ImageButton
local UI_BoomboxEditButton = UI.left.boombox.Edit
--local UI_CoopButton = UI.left.coop.ImageButton
local UI_HotbarBuildFrame = UI.hotbarContainer.build
local UI_HotbarBuildButton = UI.hotbarContainer.build.Background
local UI_HotbarBuildButtonNotification = UI.hotbarContainer.build.notification
local UI_HotbarHomeButton = UI.hotbarContainer.home.Background

local UI_ChartsButton_GreenFillbar = UI.right.charts.ImageButton.ImageLabel.GreenBG.Fill
local UI_ChartsButton_BlueFillbar = UI.right.charts.ImageButton.ImageLabel.BlueBG.Fill
local UI_ChartsButton_YellowFillbar = UI.right.charts.ImageButton.ImageLabel.YellowBG.Fill

local UI_Top_HappinessButton = UI.top.mood.Background
local UI_Top_MoneyButton = UI.top.money.Background
local UI_Top_MoneyButtonExtra = UI.top.money.Background.Buy

local UI_Top_Money_Amount_TextLabel = UI.top.money.Background.Amount
local UI_Top_Money_Gain_TextLabel = UI.top.money.Background.Gain
local UI_CityNameLabel = UI.cityLevel.background.CityName

local UI_DriveBtn = UI.left.drive.ImageButton
local UI_PopulationBtn = UI.top.population.Background  -- (already present in your code)

-- Networking
local UIUpdateEvent = ReplicatedStorage.Events.RemoteEvents:WaitForChild("UpdateStatsUI")
local RE_EquipBoombox = ReplicatedStorage.Events.RemoteEvents.EquipBoombox
local RE_PlayerDataChanged_Money = ReplicatedStorage.Events.RemoteEvents:WaitForChild("PlayerDataChanged_Money")

-- Defaults
UI_BoomboxButton.Visible = false
UI_BoomboxEditButton.Visible = false

local reqDelete     = Events.RemoteEvents:WaitForChild("RequestDeleteZone")
local confirmDelete = Events.RemoteEvents:WaitForChild("ConfirmDeleteZone")
local UtilityAlertsRE = ReplicatedStorage.Events.RemoteEvents:WaitForChild("UtilityAlerts")
local SpawnToDrive = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents"):WaitForChild("SpawnCarToFarthest")
local CameraAttachEvt = ReplicatedStorage.Events.RemoteEvents:WaitForChild("CameraAttachToCar")
local camera = workspace.CurrentCamera
local activeFollowConn

local deleteMode   = false
local selectedPart = nil

-- Player plot & zone folders ---------------------------------------------------
local playerPlot  = workspace.PlayerPlots:WaitForChild("Plot_"..LocalPlayer.UserId)

-- NOTE: we now handle ALL zone containers (PlayerZones, PowerLinesZones, WaterPipeZones)
local ZONE_FOLDER_NAMES = { "PlayerZones", "PowerLinesZones", "WaterPipeZones" }

local function getZoneContainers(plot: Instance): {Folder}
	local list = {}
	if not plot then return list end
	for _, name in ipairs(ZONE_FOLDER_NAMES) do
		local f = plot:FindFirstChild(name)
		if f and f:IsA("Folder") then
			table.insert(list, f)
		end
	end
	return list
end

local function forEachZonePart(plot: Instance, fn: (BasePart) -> ())
	if not plot then return end
	for _, folder in ipairs(getZoneContainers(plot)) do
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("BasePart") then
				fn(child)
			end
		end
	end
end

local RED   = Color3.fromRGB(255, 80, 80)
local BLACK = Color3.new(0,0,0)

local function getChartsPulseTarget()
	-- Prefer the visible ImageLabel; fallback to the button if needed.
	local img = UI_ChartsButton:FindFirstChild("ImageLabel")
	if img and img:IsA("ImageLabel") then
		return img, "ImageColor3"
	elseif UI_ChartsButton:IsA("ImageButton") and UI_ChartsButton.Image ~= "" then
		return UI_ChartsButton, "ImageColor3"
	else
		return UI_ChartsButton, "BackgroundColor3"
	end
end

local function setChartsPulse(on: boolean)
	local btn = UI_ChartsButton
	if not btn then return end

	-- cache original bg + transparency once
	if btn:GetAttribute("_pulse_orig_bg_r") == nil then
		btn:SetAttribute("_pulse_orig_bg_r", btn.BackgroundColor3.R)
		btn:SetAttribute("_pulse_orig_bg_g", btn.BackgroundColor3.G)
		btn:SetAttribute("_pulse_orig_bg_b", btn.BackgroundColor3.B)
		btn:SetAttribute("_pulse_orig_bt",  btn.BackgroundTransparency)
	end
	local function origBG()
		return Color3.new(
			btn:GetAttribute("_pulse_orig_bg_r") or 0,
			btn:GetAttribute("_pulse_orig_bg_g") or 0,
			btn:GetAttribute("_pulse_orig_bg_b") or 0
		)
	end
	local function origBT()
		return btn:GetAttribute("_pulse_orig_bt") or 1
	end

	-- token prevents old loops from restoring color late
	local token = (btn:GetAttribute("_PulseToken") or 0) + 1
	btn:SetAttribute("_PulseToken", token)

	if on then
		if btn:GetAttribute("_PulseActive") then return end
		btn:SetAttribute("_PulseActive", true)
		if btn.BackgroundTransparency > 0.6 then
			btn.BackgroundTransparency = 0.6
		end
		task.spawn(function()
			while btn.Parent and btn:GetAttribute("_PulseActive") and (btn:GetAttribute("_PulseToken") == token) do
				TweenService:Create(btn, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
					BackgroundColor3 = RED,
				}):Play()
				task.wait(0.6)
				if not (btn.Parent and btn:GetAttribute("_PulseActive") and (btn:GetAttribute("_PulseToken") == token)) then break end
				TweenService:Create(btn, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
					BackgroundColor3 = BLACK,
				}):Play()
				task.wait(0.8)
			end
			-- final restore only if this is still the latest token
			if btn:GetAttribute("_PulseToken") == token then
				btn.BackgroundColor3 = origBG()
				btn.BackgroundTransparency = origBT()
			end
		end)
	else
		btn:SetAttribute("_PulseActive", false)
		TweenService:Create(btn, TweenInfo.new(0.2, Enum.EasingStyle.Sine), {
			BackgroundColor3 = origBG(),
			BackgroundTransparency = origBT(),
		}):Play()
	end
end


local function isDeleteIgnorable(part: Instance): boolean
	return part
		and part:IsA("BasePart")
		and part:GetAttribute("IsRangeVisual") == true
end


-- Keep new parts in sync across all containers while in delete mode
-- We hook at the container level; if any are created later we’ll also hook them.
local function hookContainerChildAdded(folder: Folder)
	folder.ChildAdded:Connect(function(c)
		if c:IsA("BasePart") then
			-- ensure newly spawned plates reflect current delete-mode
			if deleteMode and not isDeleteIgnorable(c) then
				-- store original fields if first touch
				if c:GetAttribute("_OrigTransparency") == nil then
					c:SetAttribute("_OrigTransparency", c.Transparency)
				end
				if c:GetAttribute("_OrigCanQuery") == nil then
					c:SetAttribute("_OrigCanQuery", c.CanQuery)
				end
				c.Transparency = 0.75
				c.CanQuery     = true
			end
		end
	end)
end

for _, container in ipairs(getZoneContainers(playerPlot)) do
	hookContainerChildAdded(container)
end

-- If these folders might be created dynamically later, also watch for them:
playerPlot.ChildAdded:Connect(function(child)
	if child:IsA("Folder") and table.find(ZONE_FOLDER_NAMES, child.Name) then
		hookContainerChildAdded(child)
	end
end)

-- Helper Functions
local function UpdateSideButtonVisible()
	if PlayerGui.BuildMenu.Enabled then
		UI.left.Visible = false
		UI.right.Visible = false
	else
		UI.left.Visible = true
		UI.right.Visible = true
	end
end
PlayerGui.BuildMenu:GetPropertyChangedSignal("Enabled"):Connect(UpdateSideButtonVisible)
UpdateSideButtonVisible()

local function SideButtonVFX(Button, ButtonDefaultSize)
	table.insert(ExitFunctions, UtilityGUI.VisualMouseInteraction(
		Button, Button,
		TweenInfo.new(0.15),
		{ BackgroundTransparency = 0.8, },
		{ BackgroundTransparency = 0.0, }
		))
	table.insert(ExitFunctions, UtilityGUI.VisualMouseInteraction(
		Button, Button.UIStroke,
		TweenInfo.new(0.15),
		{ Thickness = 4, },
		{ Thickness = 0.5, }
		))
	table.insert(ExitFunctions, UtilityGUI.VisualMouseInteraction(
		Button, Button.ImageLabel,
		TweenInfo.new(0.15),
		{ Rotation = 15, Size = UDim2.fromScale(ButtonDefaultSize.X.Scale * 1.25, ButtonDefaultSize.Y.Scale * 1.25) },
		{ Rotation = -15, Size = UDim2.fromScale(ButtonDefaultSize.X.Scale * 0.5, ButtonDefaultSize.Y.Scale * 0.5) }
		))
end

-- Tint helpers ---------------------------------------------------------------
local function tintZone(part: BasePart?, red: boolean)
	if not part or not part:IsA("BasePart") then return end
	if red then
		if part:GetAttribute("_OrigColor") == nil then
			part:SetAttribute("_OrigColor", part.Color)
		end
		part.Color        = Color3.new(1,0,0)
		part.Transparency = 0.25
	else
		local orig = part:GetAttribute("_OrigColor")
		if orig ~= nil then
			part.Color = orig
		end
		-- transparency restored by toggle below using _OrigTransparency
	end
end

--=== Delete-mode stacking config =========================================
local DELETE_MODE_THICKNESS = 1.5   -- uniform clickable thickness (studs)
local DELETE_MODE_SPACING   = 0.75  -- vertical gap between layers (studs)

-- Order: lower number sits lower; they stack upward
-- Roads lowest, then WaterPipe, then PowerLines highest
local ZONE_LAYER_ORDER = {
	-- roads (your mode names)
	DirtRoad  = 1, Pavement = 1, Highway = 1,
	-- water
	WaterPipe = 2,
	-- power
	PowerLines = 3,

	MetroTunnel = 4,
}

local THICK_ZONE_SET = {
	Residential = true, Commercial = true, Industrial = true,
	ResDense = true,    CommDense  = true, IndusDense  = true,
}

local function getZoneType(part: BasePart): string?
	return part:GetAttribute("ZoneType")
end

local LAYERED_ZONE_SET = {
	DirtRoad  = true, Pavement = true, Highway = true,
	WaterPipe = true, PowerLines = true, MetroTunnel = true,
}

local function isLayeredPart(part: BasePart): boolean
	local zt = getZoneType(part)
	if zt and LAYERED_ZONE_SET[zt] then return true end
	-- folder fallback for utilities if ZoneType missing
	local parent = part.Parent
	if parent and (parent.Name == "WaterPipeZones" or parent.Name == "PowerLinesZones") then
		return true
	end
	return false
end

local function getDeleteThicknessFor(part: BasePart): number
	if isLayeredPart(part) then
		return 1.5
	end
	local zt = getZoneType(part)
	if zt and THICK_ZONE_SET[zt] then
		return 5
	end
	return 10
end

local function resolveLayerForPart(part: BasePart): number
	-- Prefer explicit ZoneType attribute set by ZoneDisplayModule
	local zt = part:GetAttribute("ZoneType")
	if zt and ZONE_LAYER_ORDER[zt] then return ZONE_LAYER_ORDER[zt] end

	-- Fallback to folder name if attributes were missing
	local parent = part.Parent
	if parent and parent.Name == "WaterPipeZones" then return 2 end
	if parent and parent.Name == "PowerLinesZones" then return 3 end
	-- anything else treated like 'roads / ground plates'
	return 1
end

local STACK_QUANTIZE = 1.0  -- studs; 1.0 is safe on grid-aligned plates

local function xyBucketKey(part: BasePart): string
	local px, pz = part.Position.X, part.Position.Z
	-- round to nearest multiple of STACK_QUANTIZE
	local q = STACK_QUANTIZE
	local rx = math.floor((px / q) + 0.5) * q
	local rz = math.floor((pz / q) + 0.5) * q
	return tostring(rx) .. ":" .. tostring(rz)
end

-- Build compacted layer maps per XY bucket for layered (utility/road/tunnel) parts only.
-- Returns: table key -> { order = {baseLayersSorted}, rank = { [baseLayer]=compactIndex (1..n) } }
local function buildCompactedLayerRanks(parts: {BasePart})
	local buckets = {}   -- key -> { present = {[baseLayer]=true} }
	for _, part in ipairs(parts) do
		if isLayeredPart(part) then
			local key = xyBucketKey(part)
			local bucket = buckets[key]
			if not bucket then
				bucket = { present = {} }
				buckets[key] = bucket
			end
			local base = resolveLayerForPart(part)
			bucket.present[base] = true
		end
	end

	local out = {} -- key -> {order={}, rank={}}
	for key, bucket in pairs(buckets) do
		local order = {}
		for base,_ in pairs(bucket.present) do table.insert(order, base) end
		table.sort(order) -- lower baseLayer sits lower
		local rank = {}
		for i, base in ipairs(order) do rank[base] = i end
		out[key] = { order = order, rank = rank }
	end
	return out
end

local CELL_SIZE = 4

local function rectXZ(part: BasePart)
	-- Axis-aligned AABB in XZ (ignores rotation; your plates are grid-aligned)
	local halfX = part.Size.X * 0.5
	local halfZ = part.Size.Z * 0.5
	local x, z  = part.Position.X, part.Position.Z
	return x - halfX, x + halfX, z - halfZ, z + halfZ
end

local function cellsForPart(part: BasePart): {string}
	local minX, maxX, minZ, maxZ = rectXZ(part)
	-- inclusive cell coverage
	local ix0 = math.floor(minX / CELL_SIZE)
	local ix1 = math.floor((maxX - 1e-6) / CELL_SIZE)
	local iz0 = math.floor(minZ / CELL_SIZE)
	local iz1 = math.floor((maxZ - 1e-6) / CELL_SIZE)

	local keys = {}
	for ix = ix0, ix1 do
		for iz = iz0, iz1 do
			keys[#keys+1] = tostring(ix) .. ":" .. tostring(iz)
		end
	end
	return keys
end

-- Build compacted ranks PER CELL for layered parts.
-- Returns: cellKey -> { order = {baseLayersSorted}, rank = { [baseLayer]=compactIndex } }
local function buildCompactedRanksByCell(parts: {BasePart})
	local cells = {} -- cellKey -> { present = {[baseLayer]=true} }
	for _, part in ipairs(parts) do
		if isLayeredPart(part) then
			local baseL = resolveLayerForPart(part)
			for _, key in ipairs(cellsForPart(part)) do
				local bucket = cells[key]
				if not bucket then
					bucket = { present = {} }
					cells[key] = bucket
				end
				bucket.present[baseL] = true
			end
		end
	end

	local out = {}
	for key, bucket in pairs(cells) do
		local order = {}
		for base,_ in pairs(bucket.present) do order[#order+1] = base end
		table.sort(order) -- low layer sits lowest
		local rank = {}
		for i, base in ipairs(order) do rank[base] = i end
		out[key] = { order = order, rank = rank }
	end
	return out
end

-- For a given layered part, get the MAX compact rank across all cells it covers.
local function maxCompactIndexForPart(part: BasePart, ranksByCell: table, baseLayer: number): number
	local maxIdx = 1
	for _, key in ipairs(cellsForPart(part)) do
		local cell = ranksByCell[key]
		if cell then
			local idx = cell.rank[baseLayer]
			if idx and idx > maxIdx then
				maxIdx = idx
			end
		end
	end
	return maxIdx
end

--======================================================================

-- ▲ enable / disable delete mode ----------------------------------------------
local function toggleDeleteMode(on: boolean)
	if deleteMode == on then return end
	deleteMode = on
	print("[toggleDeleteMode] switched to", deleteMode)

	-- flash the button outline
	UI_DeleteButton.UIStroke.Thickness        = on and 4 or 0.5
	UI_DeleteGamepadButton.UIStroke.Thickness = on and 4 or 0.5

	-----------------------------------------------------------------
	-- SHOW/HIDE for ALL ZONE CONTAINERS with compact vertical stacking
	-----------------------------------------------------------------

	-- Pass 0: collect all parts so we can compact layers per XY bucket
	local allParts = {}
	forEachZonePart(playerPlot, function(part: BasePart)
		if not isDeleteIgnorable(part) then
			table.insert(allParts, part)
		end
	end)

	-- Pass 1: ensure originals are saved once
	for _, part in ipairs(allParts) do
		if isDeleteIgnorable(part) then
			-- never touch range visuals in delete mode
			continue
		end

		if part:GetAttribute("_OrigTransparency") == nil then
			part:SetAttribute("_OrigTransparency", part.Transparency)
		end
		if part:GetAttribute("_OrigCanQuery") == nil then
			part:SetAttribute("_OrigCanQuery", part.CanQuery)
		end
		if part:GetAttribute("_OrigSizeX") == nil then
			part:SetAttribute("_OrigSizeX", part.Size.X)
			part:SetAttribute("_OrigSizeY", part.Size.Y)
			part:SetAttribute("_OrigSizeZ", part.Size.Z)
		end
		if part:GetAttribute("_OrigPosX") == nil then
			part:SetAttribute("_OrigPosX", part.Position.X)
			part:SetAttribute("_OrigPosY", part.Position.Y)
			part:SetAttribute("_OrigPosZ", part.Position.Z)
			local rotY = part:GetAttribute("RotationY")
			if rotY == nil then
				rotY = part.Orientation.Y
			end
			part:SetAttribute("_OrigRotY", rotY)
		end
	end

	-- Build compacted ranks for layered parts per XY bucket
	local compactRanksByCell = buildCompactedRanksByCell(allParts)

	-- Pass 2: apply delete-mode or restore
	for _, part in ipairs(allParts) do
		if isDeleteIgnorable(part) then
			-- never modify/touch range visuals during delete-mode
			continue
		end

		if on then
			-- DELETE-MODE: show & click
			part.Transparency = 0.25
			part.CanQuery     = true

			-- thickness by zone class
			local t = getDeleteThicknessFor(part)
			part.Size = Vector3.new(part.Size.X, t, part.Size.Z)

			-- orientation
			local lock = part:GetAttribute("LockOrientation")
			local rotY = part:GetAttribute("_OrigRotY") or 0
			local finalYaw = lock and 0 or rotY

			-- base altitude = original Y
			local baseY = part:GetAttribute("_OrigPosY") or part.Position.Y

			-- compact stack for layered parts
			local newY = baseY
			if isLayeredPart(part) then
				local baseL = resolveLayerForPart(part)
				local compactIdx = maxCompactIndexForPart(part, compactRanksByCell, baseL)

				local anyOrder = nil
				for _, key in ipairs(cellsForPart(part)) do
					local cell = compactRanksByCell[key]
					if cell then anyOrder = cell.order break end
				end

				local lift = 0
				if anyOrder and compactIdx > 1 then
					for i = 1, (compactIdx - 1) do
						lift += 1.5 + DELETE_MODE_SPACING -- utilities use 1.5 in delete-mode
					end
				end
				newY = baseY + lift
			end

			part.CFrame = CFrame.new(part.Position.X, newY, part.Position.Z)
				* CFrame.Angles(0, math.rad(finalYaw), 0)

		else
			-- NORMAL MODE: restore everything exactly
			local ot = part:GetAttribute("_OrigTransparency")
			if ot ~= nil then part.Transparency = ot end
			local oq = part:GetAttribute("_OrigCanQuery")
			if oq ~= nil then part.CanQuery = oq end

			local ox = part:GetAttribute("_OrigSizeX")
			local oy = part:GetAttribute("_OrigSizeY")
			local oz = part:GetAttribute("_OrigSizeZ")
			if ox and oy and oz then
				part.Size = Vector3.new(ox, oy, oz)
			end

			local px = part:GetAttribute("_OrigPosX")
			local py = part:GetAttribute("_OrigPosY")
			local pz = part:GetAttribute("_OrigPosZ")
			local ry = part:GetAttribute("_OrigRotY") or 0
			if px and py and pz then
				local lock = part:GetAttribute("LockOrientation")
				local finalYaw = lock and 0 or ry
				part.CFrame = CFrame.new(px, py, pz) * CFrame.Angles(0, math.rad(finalYaw), 0)
			end
		end
	end

	-- clear highlight when we leave delete-mode
	if not on and selectedPart then
		tintZone(selectedPart,false)
		selectedPart = nil
	end
end


function MainGui.DisableDeleteMode()
	if deleteMode then
		toggleDeleteMode(false)
	end
end

-- Module Functions
function MainGui.SetChartButton_GreenFillbar(Alpha: number)
	TweenService:Create(UI_ChartsButton_GreenFillbar, TweenInfo.new(0.2), {
		Size = UDim2.fromScale(UI_ChartsButton_GreenFillbar.Size.X.Scale, Alpha)
	}):Play()
end
function MainGui.SetChartButton_BlueFillbar(Alpha: number)
	TweenService:Create(UI_ChartsButton_BlueFillbar, TweenInfo.new(0.2), {
		Size = UDim2.fromScale(UI_ChartsButton_BlueFillbar.Size.X.Scale, Alpha)
	}):Play()
end
function MainGui.SetChartButton_YellowFillbar(Alpha: number)
	TweenService:Create(UI_ChartsButton_YellowFillbar, TweenInfo.new(0.2), {
		Size = UDim2.fromScale(UI_ChartsButton_YellowFillbar.Size.X.Scale, Alpha)
	}):Play()
end

UIUpdateEvent.OnClientEvent:Connect(function(payload)
	if not payload then return end
	if payload.zoneDemand then
		local ResidentialDemand = (payload.zoneDemand.ResDense + payload.zoneDemand.Residential) / 2
		MainGui.SetChartButton_GreenFillbar(ResidentialDemand)

		local CommercialDemand = (payload.zoneDemand.CommDense + payload.zoneDemand.Commercial) / 2
		MainGui.SetChartButton_BlueFillbar(CommercialDemand)

		local IndustrialDemand = (payload.zoneDemand.IndusDense + payload.zoneDemand.Industrial) / 2
		MainGui.SetChartButton_YellowFillbar(IndustrialDemand)
	end
	local GetAlertsRF = ReplicatedStorage.Events.RemoteEvents:FindFirstChild("GetUtilityAlertsSnapshot")
	if GetAlertsRF then
		local ok, snap = pcall(function() return GetAlertsRF:InvokeServer() end)
		if ok and snap then
			local anyShort = (snap.waterInsufficient or snap.powerInsufficient) or false
			setChartsPulse(anyShort)
		end
	end
end)

function MainGui.SetBuildButtonNotification(State: boolean)
	UI_HotbarBuildButtonNotification.Visible = State
end

local LevelUpRE = ReplicatedStorage.Events.RemoteEvents:WaitForChild("LevelUpEvent")
LevelUpRE.OnClientEvent:Connect(function(newLevel)
	local nL = tonumber(newLevel)
	if not nL then return end
	for lvl, _ in pairs(BalanceEconomy.ProgressionConfig.unlocksByLevel) do
		if tonumber(lvl) == nL then
			MainGui.SetBuildButtonNotification(true)
			break
		end
	end
end)

function MainGui.SetMapNotification(State: boolean)
	UI_MapButtonNotification.Visible = State
end

--function MainGui.SetCoopButtonVisible(State: boolean)
--	UI.left.coop.Visible = State
--end

function MainGui.OnShow()
	if UI.Enabled then return end
	UI.Enabled = true
end

function MainGui.OnHide()
	if not UI.Enabled then return end
	UI.Enabled = false

	for _, Function in ExitFunctions do
		Function()
	end
end

function MainGui.Init()

	-- == City Name UI reference (added) ========================================
	local UI_CityNameLabel = UI.cityLevel.background.CityName

	-- Helper: set city name safely
	local function _setCityName(name)
		local text = ""
		if typeof(name) == "string" then
			text = name:gsub("^%s+", ""):gsub("%s+$", "")
		end
		if text == "" then
			text = "Unnamed City"
		end
		UI_CityNameLabel.Text = text
	end
	_setCityName("...")

	-- Listen to PlayerData snapshots/deltas and update city name
	-- Your PlayerDataService fires: RE_UpdatePlayerData:FireClient(Player, NewValue, Path)
	local RE_UpdatePlayerData = ReplicatedStorage.Events.RemoteEvents:WaitForChild("UpdatePlayerData")

	-- Cache of last full snapshot so switching slots can pull correct name
	local _lastPD

	local function _applyCityFromFull(pd)
		if type(pd) ~= "table" then return end
		_lastPD = pd
		local cur = pd.currentSaveFile
		if not cur then return end
		local sf = pd.savefiles and pd.savefiles[cur]
		if not sf then return end
		_setCityName(sf.cityName)
	end

	RE_UpdatePlayerData.OnClientEvent:Connect(function(newValue, path)
		-- Full snapshot on load or major changes => path == nil
		if path == nil then
			_applyCityFromFull(newValue)
			return
		end

		-- If the city name for the current slot changes directly
		-- Path pattern: "savefiles/<slotId>/cityName"
		if string.match(path, "^savefiles/[^/]+/cityName$") then
			_setCityName(newValue)
			return
		end

		-- If current slot switched, try to pull city name from the last cached snapshot
		if path == "currentSaveFile" then
			if type(_lastPD) == "table" and _lastPD.savefiles and _lastPD.savefiles[newValue] then
				local sf = _lastPD.savefiles[newValue]
				_setCityName(sf and sf.cityName)
			else
				-- fallback placeholder; next full snapshot will correct it
				_setCityName("...")
			end
			return
		end
	end)

	-- Optional: if your server sends PlotAssigned on reload/switch, we can opportunistically
	-- use it as a temporary label until the full PlayerData snapshot arrives.
	local PlotAssigned = ReplicatedStorage.Events.RemoteEvents:FindFirstChild("PlotAssigned")
	if PlotAssigned then
		PlotAssigned.OnClientEvent:Connect(function(playerPlotName, _unlocks)
			if typeof(playerPlotName) == "string" and playerPlotName ~= "" then
				_setCityName(playerPlotName)
			end
		end)
	end
	-- ==========================================================================


	-- Notifications
	MainGui.SetBuildButtonNotification(false)
	MainGui.SetMapNotification(false)

	-- Input Type Specific
	UI_DestroyButton.Parent.Visible = InputController.GetInputType() ~= "Gamepad"
	UI_DeleteGamepadButton.Parent.Visible = InputController.GetInputType() == "Gamepad"
	UI_RedoGamepadButton.Parent.Visible = InputController.GetInputType() == "Gamepad"
	UI_UndoGamepadButton.Parent.Visible = InputController.GetInputType() == "Gamepad"
	InputController.ListenForInputTypeChanged(function()
		UI_DestroyButton.Parent.Visible = InputController.GetInputType() ~= "Gamepad"
		UI_DeleteGamepadButton.Parent.Visible = InputController.GetInputType() == "Gamepad"
		UI_RedoGamepadButton.Parent.Visible = InputController.GetInputType() == "Gamepad"
		UI_UndoGamepadButton.Parent.Visible = InputController.GetInputType() == "Gamepad"
	end)

	-- UserInputs
	UserInputService.InputBegan:Connect(function(InputObject, GameProcessedEvent)
		if not UI.Enabled then return end
		if GameProcessedEvent then return end

		if InputObject.KeyCode == Enum.KeyCode.E or InputObject.KeyCode == Enum.KeyCode.ButtonY then
			SoundController.PlaySoundOnce("UI", "SmallClick")
			local Demands = PlayerGui.Demands
			Demands.Enabled = not Demands.Enabled
			if Demands.Enabled then
				local ok = pcall(function()
					SoundController.PlaySoundOnce("Misc", "Woosh1")
				end)
				if not ok then
					local mainMenu = UI:FindFirstChild("MainMenu")
					local s = mainMenu and mainMenu:FindFirstChild("Woosh1")
					if s and s:IsA("Sound") then s:Play() end
				end
			end

		elseif InputObject.KeyCode == Enum.KeyCode.V then
			SoundController.PlaySoundOnce("UI", "SmallClick")
			UI.right.removal.Delete.Visible = not UI.right.removal.Delete.Visible
			UI.right.removal.Redo.Visible = not UI.right.removal.Redo.Visible
			UI.right.removal.Undo.Visible = not UI.right.removal.Undo.Visible

		elseif InputObject.KeyCode == Enum.KeyCode.T then
			SoundController.PlaySoundOnce("UI", "SmallClick")
			require(PlayerGui.PremiumShopGui.Logic).Toggle()

		elseif InputObject.KeyCode == Enum.KeyCode.L then
			SoundController.PlaySoundOnce("UI", "SmallClick")
			require(PlayerGui.LoadMenu.Logic).Toggle()

		elseif InputObject.KeyCode == Enum.KeyCode.B then
			if LocalPlayer:GetAttribute("HasBoomboxMusicPlayer") then
				SoundController.PlaySoundOnce("UI", "SmallClick")
				local IsEquipped = LocalPlayer:GetAttribute("EquippedBoombox")
				RE_EquipBoombox:FireServer(not IsEquipped)
			end

			--elseif InputObject.KeyCode == Enum.KeyCode.Q then
			--	SoundController.PlaySoundOnce("UI", "SmallClick")
			--	local Coop = PlayerGui.Coop
			--	Coop.Enabled = not Coop.Enabled

		elseif InputObject.KeyCode == Enum.KeyCode.C or InputObject.KeyCode == Enum.KeyCode.ButtonX then
			SoundController.PlaySoundOnce("UI", "SmallClick")
			MainGui.SetBuildButtonNotification(false)
			MainGui.DisableDeleteMode()
			require(PlayerGui.BuildMenu.Logic).Toggle()

		elseif InputObject.KeyCode == Enum.KeyCode.Z then
			SoundController.PlaySoundOnce("UI", "SmallClick")
			ReplicatedStorage.Events.RemoteEvents.UndoCommand:FireServer()

		elseif InputObject.KeyCode == Enum.KeyCode.Y then
			SoundController.PlaySoundOnce("UI", "SmallClick")
			ReplicatedStorage.Events.RemoteEvents.RedoCommand:FireServer()

		elseif InputObject.KeyCode == Enum.KeyCode.DPadUp then
			SoundController.PlaySoundOnce("UI", "SmallClick")
			warn("TODO")

		elseif InputObject.KeyCode == Enum.KeyCode.DPadRight then
			SoundController.PlaySoundOnce("UI", "SmallClick")
			ReplicatedStorage.Events.RemoteEvents.RedoCommand:FireServer()

		elseif InputObject.KeyCode == Enum.KeyCode.DPadLeft then
			SoundController.PlaySoundOnce("UI", "SmallClick")
			ReplicatedStorage.Events.RemoteEvents.UndoCommand:FireServer()
		end
	end)

	UtilityAlertsRE.OnClientEvent:Connect(function(alert)
		local anyShort = alert and (alert.waterInsufficient or alert.powerInsufficient) or false
		setChartsPulse(anyShort)
	end)

	task.defer(function()
		local GetAlertsRF = ReplicatedStorage.Events.RemoteEvents:FindFirstChild("GetUtilityAlertsSnapshot")
		if not GetAlertsRF then return end
		local ok, snap = pcall(function() return GetAlertsRF:InvokeServer() end)
		if ok and snap then
			setChartsPulse((snap.waterInsufficient or snap.powerInsufficient) or false)
		end
	end)

	local mouse = LocalPlayer:GetMouse()

	mouse.Button1Down:Connect(function()
		if not deleteMode then return end
		if PlayerGui.BuildMenu.Enabled then return end   -- don’t allow while building

		local target = mouse.Target
		if not target or not target:GetAttribute("ZoneType") then return end  -- only zone parts
		if isDeleteIgnorable(target) then return end                          -- ignore range visuals

		-- highlight the newly picked zone, unhighlight previous
		if selectedPart then tintZone(selectedPart,false) end
		selectedPart = target
		tintZone(selectedPart,true)

		-- Confirm GUI -> callback
		require(PlayerGui.DeleteConfirm.Logic).Prompt(target.Name, function(confirmed)
			if confirmed then
				reqDelete:FireServer(target.Name)      -- zoneId == part.Name
			else
				tintZone(selectedPart,false)
				selectedPart = nil
			end
		end)
	end)

	confirmDelete.OnClientEvent:Connect(function(zoneId, wasDeleted)
		if selectedPart and selectedPart.Name == zoneId then
			if wasDeleted then
				-- NEW: success SFX for delete
				SoundController.PlaySoundOnce("Misc", "PurchaseFail")

				selectedPart:Destroy()         -- display part; ZoneDisplayModule will clean too
			else
				tintZone(selectedPart,false)
			end
			selectedPart = nil
			toggleDeleteMode(false)
		end
	end)

	-- Button VFX
	SideButtonVFX(UI_ChartsButton, UI_ChartsButton.ImageLabel.Size)
	SideButtonVFX(UI_DestroyButton, UI_DestroyButton.ImageLabel.Size)
	SideButtonVFX(UI_DeleteButton, UI_DeleteButton.ImageLabel.Size)
	SideButtonVFX(UI_RedoButton, UI_RedoButton.ImageLabel.Size)
	SideButtonVFX(UI_UndoButton, UI_UndoButton.ImageLabel.Size)
	SideButtonVFX(UI_MapButton, UI_MapButton.ImageLabel.Size)
	SideButtonVFX(UI_PremiumShopButton, UI_PremiumShopButton.ImageLabel.Size)
	SideButtonVFX(UI_LoadButton, UI_LoadButton.ImageLabel.Size)
	SideButtonVFX(UI_BoomboxButton, UI_BoomboxButton.ImageLabel.Size)
	SideButtonVFX(UI_BoomboxEditButton, UI_BoomboxEditButton.ImageLabel.Size)
	--SideButtonVFX(UI_CoopButton, UI_CoopButton.ImageButton.Size)

	-- Button Interaction
	UI_ChartsButton.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		local Demands = PlayerGui.Demands
		Demands.Enabled = not Demands.Enabled
		if Demands.Enabled then
			local ok = pcall(function()
				SoundController.PlaySoundOnce("Misc", "Woosh1")
			end)
			if not ok then
				local mainMenu = UI:FindFirstChild("MainMenu")
				local s = mainMenu and mainMenu:FindFirstChild("Woosh1")
				if s and s:IsA("Sound") then s:Play() end
			end
		end
	end)
	
	UI_Top_HappinessButton.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		local Demands = PlayerGui.Demands
		Demands.Enabled = not Demands.Enabled
		if Demands.Enabled then
			local ok = pcall(function()
				SoundController.PlaySoundOnce("Misc", "Woosh1")
			end)
			if not ok then
				local mainMenu = UI:FindFirstChild("MainMenu")
				local s = mainMenu and mainMenu:FindFirstChild("Woosh1")
				if s and s:IsA("Sound") then s:Play() end
			end
		end
	end)
	
	UI_DestroyButton.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		UI.right.removal.Delete.Visible = not UI.right.removal.Delete.Visible
		UI.right.removal.Redo.Visible = not UI.right.removal.Redo.Visible
		UI.right.removal.Undo.Visible = not UI.right.removal.Undo.Visible
	end)

	UI_DeleteButton.MouseButton1Down:Connect(function()
		print("[DeleteButton] CLICKED – current deleteMode =", deleteMode)
		SoundController.PlaySoundOnce("UI", "SmallClick")
		toggleDeleteMode(not deleteMode)
	end)

	UI_DeleteGamepadButton.MouseButton1Down:Connect(function()
		print("[DeleteGamepadButton] CLICKED – current deleteMode =", deleteMode)
		SoundController.PlaySoundOnce("UI", "SmallClick")
		toggleDeleteMode(not deleteMode)
	end)

	UI_RedoButton.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		ReplicatedStorage.Events.RemoteEvents.RedoCommand:FireServer()
	end)
	UI_RedoGamepadButton.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		ReplicatedStorage.Events.RemoteEvents.RedoCommand:FireServer()
	end)

	UI_UndoButton.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		ReplicatedStorage.Events.RemoteEvents.UndoCommand:FireServer()
	end)
	UI_UndoGamepadButton.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		ReplicatedStorage.Events.RemoteEvents.UndoCommand:FireServer()
	end)

	UI_MapButton.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		warn("TODO")
	end)

	UI_PremiumShopButton.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		require(PlayerGui.PremiumShopGui.Logic).Toggle()
	end)

	UI_LoadButton.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		require(PlayerGui.LoadMenu.Logic).Toggle()
	end)

	UI_BoomboxButton.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		local IsEquipped = LocalPlayer:GetAttribute("EquippedBoombox")
		RE_EquipBoombox:FireServer(not IsEquipped)
	end)

	------------------------------------------------------------------
	-- ADDED: SocialMedia open on Population button
	------------------------------------------------------------------
	-- Helper tries a module Toggle() first; if absent, toggles ScreenGui.Enabled.
	local function ToggleSocialMedia()
		-- Prefer a module with Toggle() to keep parity with your other GUIs
		local logicOk, logic = pcall(function()
			local sm = PlayerGui:FindFirstChild("SocialMedia")
			if sm and sm:FindFirstChild("Logic") and sm.Logic:IsA("ModuleScript") then
				return require(sm.Logic)
			end
			-- Some projects keep Logic under PlayerGui.SocialMediaGui.Logic; be tolerant:
			local sm2 = PlayerGui:FindFirstChild("SocialMediaGui")
			if sm2 and sm2:FindFirstChild("Logic") and sm2.Logic:IsA("ModuleScript") then
				return require(sm2.Logic)
			end
			return nil
		end)

		if logicOk and logic and type(logic.Toggle) == "function" then
			logic.Toggle()
			return
		end

		-- Fallback: flip the ScreenGui.Enabled directly
		local screen = PlayerGui:FindFirstChild("SocialMedia") or PlayerGui:FindFirstChild("SocialMediaGui")
		if screen and screen:IsA("ScreenGui") then
			screen.Enabled = not screen.Enabled
		else
			warn("[MainGui] SocialMedia ScreenGui not found under PlayerGui")
		end
	end

	UI_PopulationBtn.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		ToggleSocialMedia()
	end)

	-- Give it consistent hover feedback like other top buttons
	UtilityGUI.VisualMouseInteraction(
		UI_PopulationBtn, UI_PopulationBtn.UIStroke,
		TweenInfo.new(0.15),
		{ Thickness = 4, },
		{ Thickness = 0.5, }
	)
	------------------------------------------------------------------

	--Drive
	local DRIVE_COOLDOWN = 1.0
	local _driveReadyAt = 0

	local function canDrive()
		return time() >= _driveReadyAt
	end
	local function markDriveUsed()
		_driveReadyAt = time() + DRIVE_COOLDOWN
	end

	local function drivePulse()
		-- quick visual nudge on the button
		local img = UI_DriveBtn:FindFirstChild("ImageLabel")
		if not img then return end
		local t1 = TweenService:Create(img, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = img.Size + UDim2.fromScale(0.08, 0.08),
			Rotation = 7,
		})
		local t2 = TweenService:Create(img, TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = img.Size,
			Rotation = 0,
		})
		t1:Play()
		t1.Completed:Connect(function() t2:Play() end)
	end

	local function triggerDrive()
		if not canDrive() then return end
		markDriveUsed()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		drivePulse()
		-- Fire remote; server will compute origin->farthest path and spawn
		SpawnToDrive:FireServer()
	end
	
	local PlayUISoundRE = ReplicatedStorage.Events.RemoteEvents:FindFirstChild("PlayUISound")
	if PlayUISoundRE then
		PlayUISoundRE.OnClientEvent:Connect(function(cat, name)
			pcall(function() SoundController.PlaySoundOnce(cat or "Misc", name or "PurchaseFail") end)
		end)
	end
	
	-- Mouse/touch
	UI_DriveBtn.MouseButton1Down:Connect(triggerDrive)
	-- Gamepad/Touch unified activation
	if UI_DriveBtn.Activated then
		UI_DriveBtn.Activated:Connect(triggerDrive)
	end

	local DRIVER_X_OFFSET      = -2   -- Front-Back
	local DRIVER_Y_FRACTION    = 0.55   -- fraction of car height above base
	local DRIVER_FORWARD_OFFSET = -0.2 -- Left-Right

	-- Smoothness (0-1); higher is snappier
	local LERP_ALPHA = 0.25

	local function computeHeightStats(model: Model)
		local minY, maxY = math.huge, -math.huge
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				local cf, sz = d.CFrame, d.Size
				local yMin, yMax = cf.Position.Y - sz.Y*0.5, cf.Position.Y + sz.Y*0.5
				if yMin < minY then
					minY = yMin
				end
				if yMax > maxY then
					maxY = yMax
				end
			end
		end
		if minY == math.huge then
			local p = model.PrimaryPart
			return (p and p.Position.Y - 1 or 0), (p and p.Position.Y + 1 or 2)
		end
		return minY, maxY
	end

	CameraAttachEvt.OnClientEvent:Connect(function(carModel: Model?)
		-- If server sends nil, that's a hard reset (toggle off / movement cancel)
		if not carModel or not carModel:IsA("Model") or not carModel.PrimaryPart then
			if activeFollowConn then activeFollowConn:Disconnect() end
			camera.CameraType = Enum.CameraType.Custom
			local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
			if hum then camera.CameraSubject = hum end
			return
		end

		camera.CameraType = Enum.CameraType.Scriptable

		local baseY, topY = computeHeightStats(carModel)
		local carHeight = math.max(0.5, topY - baseY)
		local seatY = carHeight * DRIVER_Y_FRACTION
		local ROTATE_LEFT = CFrame.Angles(0, math.rad(90), 0)

		local function desiredCF()
			local rootCF = carModel.PrimaryPart.CFrame
			return rootCF * CFrame.new(DRIVER_X_OFFSET, seatY, -DRIVER_FORWARD_OFFSET) * ROTATE_LEFT
		end

		camera.CFrame = desiredCF()

		if activeFollowConn then activeFollowConn:Disconnect() end
		activeFollowConn = RunService.RenderStepped:Connect(function()
			-- If the car goes away, stop following but DO NOT reset camera type here.
			-- We wait for the next attach, or a server-sent nil.
			if not carModel or not carModel.Parent or not carModel.PrimaryPart then
				activeFollowConn:Disconnect()
				activeFollowConn = nil
				return
			end
			camera.CFrame = camera.CFrame:Lerp(desiredCF(), LERP_ALPHA)
		end)
	end)


	--Drive

	UI_BoomboxButton.Visible = LocalPlayer:GetAttribute("HasBoomboxMusicPlayer")
	LocalPlayer:GetAttributeChangedSignal("HasBoomboxMusicPlayer"):Connect(function()
		UI_BoomboxButton.Visible = LocalPlayer:GetAttribute("HasBoomboxMusicPlayer")
		if not UI_BoomboxButton.Visible then
			require(PlayerGui.BoomboxSelection.Logic).OnHide()
		end
	end)

	UI_BoomboxEditButton.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		require(PlayerGui.BoomboxSelection.Logic).Toggle()
	end)

	UI_BoomboxEditButton.Visible = LocalPlayer:GetAttribute("EquippedBoombox")
	LocalPlayer:GetAttributeChangedSignal("EquippedBoombox"):Connect(function()
		UI_BoomboxEditButton.Visible = LocalPlayer:GetAttribute("EquippedBoombox")
		if not UI_BoomboxEditButton.Visible then
			require(PlayerGui.BoomboxSelection.Logic).OnHide()
		end
	end)
	
	UtilityGUI.VisualMouseInteraction(
		UI_Top_HappinessButton, UI_Top_HappinessButton.UIStroke,
		TweenInfo.new(0.15),
		{ Thickness = 4, },
		{ Thickness = 0.5, }
	)

	UI_Top_MoneyButton.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		require(PlayerGui.PremiumShopGui.Logic).OnShow()
	end)
	UI_Top_MoneyButtonExtra.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		require(PlayerGui.PremiumShopGui.Logic).OnShow()
	end)
	UtilityGUI.VisualMouseInteraction(
		UI_Top_MoneyButton, UI_Top_MoneyButton.UIStroke,
		TweenInfo.new(0.15),
		{ Thickness = 4, },
		{ Thickness = 0.5, }
	)

	-- Display Income/Balance
	local UIUpdate_RemoteEvent = ReplicatedStorage.Events.RemoteEvents.UpdateStatsUI
	UIUpdate_RemoteEvent.OnClientEvent:Connect(function(data)
		if data then
			UI_Top_Money_Amount_TextLabel.Text = "$" .. tostring(Abr.abbreviateNumber(data.balance))
			UI_Top_Money_Gain_TextLabel.Text = "+ $" .. tostring(Abr.abbreviateNumber(data.income))
		end
	end)
	RE_PlayerDataChanged_Money.OnClientEvent:Connect(function(balance)
		if typeof(balance) ~= "number" then
			return
		end
		UI_Top_Money_Amount_TextLabel.Text = "$" .. tostring(Abr.abbreviateNumber(balance))
	end)
	UI_Top_Money_Amount_TextLabel.Text = "..."
	UI_Top_Money_Gain_TextLabel.Text = "..."

	-- Build Button
	UI_HotbarBuildButton.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		MainGui.SetBuildButtonNotification(false)
		MainGui.DisableDeleteMode()
		require(PlayerGui.BuildMenu.Logic).Toggle()
	end)
	-- (Optional) also support Activated for touch/gamepad if present
	if UI_HotbarBuildButton.Activated then
		UI_HotbarBuildButton.Activated:Connect(function()
			SoundController.PlaySoundOnce("UI", "SmallClick")
			MainGui.SetBuildButtonNotification(false)
			MainGui.DisableDeleteMode()
			require(PlayerGui.BuildMenu.Logic).Toggle()
		end)
	end

	UtilityGUI.VisualMouseInteraction(
		UI_HotbarBuildButton, UI_HotbarBuildButton.UIStroke,
		TweenInfo.new(0.15),
		{ Thickness = 4, },
		{ Thickness = 0.5, }
	)

	-- Home Button
	UI_HotbarHomeButton.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		ReplicatedStorage.Events.RemoteEvents.TeleportToHomePlot:FireServer()
	end)
	UtilityGUI.VisualMouseInteraction(
		UI_HotbarHomeButton, UI_HotbarHomeButton.UIStroke,
		TweenInfo.new(0.15),
		{ Thickness = 4, },
		{ Thickness = 0.5, }
	)
	-- Only show if you're close to the playerplot
	UI_HotbarHomeButton.Parent.Visible = false
	local PlayerPlot = workspace.PlayerPlots:FindFirstChild("Plot_" .. LocalPlayer.UserId)
	workspace.PlayerPlots.ChildAdded:Connect(function()
		PlayerPlot = workspace.PlayerPlots:FindFirstChild("Plot_" .. LocalPlayer.UserId)
	end)
	workspace.PlayerPlots.ChildRemoved:Connect(function()
		PlayerPlot = workspace.PlayerPlots:FindFirstChild("Plot_" .. LocalPlayer.UserId)
	end)
	RunService.Heartbeat:Connect(function()
		if not LocalPlayer.Character
			or not LocalPlayer.Character.PrimaryPart
			or not PlayerPlot
			or not PlayerPlot:FindFirstChild("CornerPoint1")
			or not PlayerPlot:FindFirstChild("CornerPoint2")
		then
			UI_HotbarHomeButton.Parent.Visible = false
		end

		UI_HotbarHomeButton.Parent.Visible = true

		local MinX = math.min(PlayerPlot.CornerPoint1.Position.X, PlayerPlot.CornerPoint2.Position.X)
		local MaxX = math.max(PlayerPlot.CornerPoint1.Position.X, PlayerPlot.CornerPoint2.Position.X)
		local MinZ = math.min(PlayerPlot.CornerPoint1.Position.Z, PlayerPlot.CornerPoint2.Position.Z)
		local MaxZ = math.max(PlayerPlot.CornerPoint1.Position.Z, PlayerPlot.CornerPoint2.Position.Z)

		if LocalPlayer.Character.PrimaryPart.Position.X > MinX
			and LocalPlayer.Character.PrimaryPart.Position.X < MaxX
			and LocalPlayer.Character.PrimaryPart.Position.Z > MinZ
			and LocalPlayer.Character.PrimaryPart.Position.Z < MaxZ
		then
			UI_HotbarHomeButton.Parent.Visible = false
		end
	end)

	----------------------------------------------------------------------
	-- ✅ Onboarding: robust Build button target registration + open signal
	----------------------------------------------------------------------

	-- Always keep the Build button registered under the canonical key the
	-- OnboardingController expects ("BuildButton"). This lets the controller
	-- (and Notification/Arrow) re-pin reliably after any UI changes.
	local function _registerBuildButtonTarget()
		-- tolerate missing registry or instance swaps without throwing
		pcall(function()
			if UI_HotbarBuildButton and UI_HotbarBuildButton:IsA("GuiObject") then
				UITargetRegistry.Register("BuildButton", UI_HotbarBuildButton)
			end
		end)
	end

	-- Initial register (deferred so layout is settled)
	task.defer(_registerBuildButtonTarget)

	-- Re-register if the button moves/reparents (e.g., UI reload/skin swap)
	UI_HotbarBuildButton.AncestryChanged:Connect(function()
		task.defer(_registerBuildButtonTarget)
	end)

	-- Mirror visibility of the hotbar build frame with BuildMenu, and:
	--  • Fire "BuildMenuOpened" to the server on open (drives gate + item pulse)
	--  • Re-register the BuildButton target on close to help the client-side
	--    controller repin arrow/pulse immediately (paired with controller gate)
	UI_HotbarBuildFrame.Visible = not PlayerGui.BuildMenu.Enabled
	local _prevBMEnabled = PlayerGui.BuildMenu.Enabled
	PlayerGui.BuildMenu:GetPropertyChangedSignal("Enabled"):Connect(function()
		local enabled = PlayerGui.BuildMenu.Enabled
		UI_HotbarBuildFrame.Visible = not enabled

		if enabled and not _prevBMEnabled then
			-- Tell the server we opened the Build Menu (the OnboardingServerBridge
			-- listens for this and will gate/pulse the first required item).
			RE_OnboardingStepCompleted:FireServer("BuildMenuOpened")
		elseif (not enabled) and _prevBMEnabled then
			-- Menu just closed: ensure the Build button target is fresh so the
			-- controller can immediately repin visuals to "BuildButton".
			_registerBuildButtonTarget()
		end

		_prevBMEnabled = enabled
	end)
	----------------------------------------------------------------------

end

return MainGui
