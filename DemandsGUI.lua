local Demands = {}

-- Roblox Services
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies
local Utility = require(ReplicatedStorage.Scripts.Utility)
local UtilityGUI = require(ReplicatedStorage.Scripts.UI.UtilityGUI)
local BoomboxMusic = require(ReplicatedStorage.Scripts.BoomboxMusic)
local SoundController = require(ReplicatedStorage.Scripts.Controllers.SoundController)
local PlayerDataController = require(ReplicatedStorage.Scripts.Controllers.PlayerDataController)

-- NEW: Balance + unlock status event (same sources Build Menu uses)
local Balancing = ReplicatedStorage:WaitForChild("Balancing")
local BalanceEconomy = require(Balancing:WaitForChild("BalanceEconomy"))
local Events = ReplicatedStorage:WaitForChild("Events")
local RE = Events:WaitForChild("RemoteEvents")
local FUS = RE:WaitForChild("FeatureUnlockStatus") -- server pushes full unlock map here
local UIUpdate_RemoteEvent = RE:WaitForChild("UpdateStatsUI") -- carries { level = ... }

-- Defines
local UI = script.Parent

-- UI References
local UI_Exit = UI.MainFrame.Exit

local UI_Tab_DemandsButton = UI.MainFrame.Container.Tabs.Demands
local UI_Tab_PowerButton = UI.MainFrame.Container.Tabs.Power
local UI_Tab_WaterButton = UI.MainFrame.Container.Tabs.Water

local UI_Tab_Demands = UI.MainFrame.Container.Demands
local UI_Tab_Power = UI.MainFrame.Container.Power
local UI_Tab_Water = UI.MainFrame.Container.Water

local UI_Demands_ResDReq = UI_Tab_Demands.ResDReq
local UI_Demands_CommDReq = UI_Tab_Demands.CommDReq
local UI_Demands_IndusDReq = UI_Tab_Demands.IndusDReq
local UI_Demands_ResDText = UI_Tab_Demands.ResDense
local UI_Demands_CommDText = UI_Tab_Demands.CommDense
local UI_Demands_IndusDText = UI_Tab_Demands.IndusDense

-- NEW: Local state for unlock decisions (robust even if FUS comes before/after Init)
local CurrentLevel = 0
local UnlockedTypes = {} -- featureName -> bool
local BuildingLevelRequirement = {} -- featureName -> min level it unlocks at

-- NEW: Precompute min level per feature from BalanceEconomy (same approach as Build Menu)
for level, featureList in pairs(BalanceEconomy.ProgressionConfig.unlocksByLevel) do
	for _, feature in ipairs(featureList) do
		-- keep the lowest level if a feature appears more than once
		if BuildingLevelRequirement[feature] == nil or level < BuildingLevelRequirement[feature] then
			BuildingLevelRequirement[feature] = level
		end
	end
end

-- NEW: Helper — determine if a feature is unlocked (prefer server’s FUS map; fall back to level gate)
local function IsUnlocked(featureName: string): boolean
	-- authoritative when available
	if UnlockedTypes[featureName] ~= nil then
		return UnlockedTypes[featureName] == true
	end
	-- fallback by city level
	local req = BuildingLevelRequirement[featureName]
	if req == nil then
		-- if no entry exists, be conservative (treat as locked)
		return false
	end
	return (CurrentLevel >= req)
end

-- NEW: Toggle visibility for each dense demand widget pair
local function RefreshDenseDemandVisibility()
	local resDenseUnlocked = IsUnlocked("ResDense")
	local commDenseUnlocked = IsUnlocked("CommDense")
	local indusDenseUnlocked = IsUnlocked("IndusDense")

	if UI_Demands_ResDReq then UI_Demands_ResDReq.Visible = resDenseUnlocked end
	if UI_Demands_ResDText then UI_Demands_ResDText.Visible = resDenseUnlocked end

	if UI_Demands_CommDReq then UI_Demands_CommDReq.Visible = commDenseUnlocked end
	if UI_Demands_CommDText then UI_Demands_CommDText.Visible = commDenseUnlocked end

	if UI_Demands_IndusDReq then UI_Demands_IndusDReq.Visible = indusDenseUnlocked end
	if UI_Demands_IndusDText then UI_Demands_IndusDText.Visible = indusDenseUnlocked end
end

-- NEW: Start hidden by default (so players below the unlock level never see them)
local function HideDenseDemandWidgetsInitially()
	if UI_Demands_ResDReq then UI_Demands_ResDReq.Visible = false end
	if UI_Demands_ResDText then UI_Demands_ResDText.Visible = false end
	if UI_Demands_CommDReq then UI_Demands_CommDReq.Visible = false end
	if UI_Demands_CommDText then UI_Demands_CommDText.Visible = false end
	if UI_Demands_IndusDReq then UI_Demands_IndusDReq.Visible = false end
	if UI_Demands_IndusDText then UI_Demands_IndusDText.Visible = false end
end

-- Helper Functions
local function SetTab(TabName: string)
	local IsDemands = (TabName == "Demands")
	local IsPower = (TabName == "Power")
	local IsWater = (TabName == "Water")

	UI_Tab_Demands.Visible = IsDemands
	UI_Tab_Power.Visible = IsPower
	UI_Tab_Water.Visible = IsWater

	TweenService:Create(UI_Tab_DemandsButton.underline, TweenInfo.new(0.2), {
		Size = IsDemands and UDim2.new(1, 0, 0, 2) or UDim2.new(0, 0, 0, 2)
	}):Play()

	TweenService:Create(UI_Tab_PowerButton.underline, TweenInfo.new(0.2), {
		Size = IsPower and UDim2.new(1, 0, 0, 2) or UDim2.new(0, 0, 0, 2)
	}):Play()

	TweenService:Create(UI_Tab_WaterButton.underline, TweenInfo.new(0.2), {
		Size = IsWater and UDim2.new(1, 0, 0, 2) or UDim2.new(0, 0, 0, 2)
	}):Play()

	-- NEW: Anytime the Demands tab is shown, ensure the visibility reflects current unlocks
	if IsDemands then
		RefreshDenseDemandVisibility()
	end
end

-- Module Functions
function Demands.OnShow()
	UI.Enabled = true
	SetTab("Demands")
	-- NEW: Also force a refresh when opening (safe even if already correct)
	RefreshDenseDemandVisibility()
end

function Demands.OnHide()
	UI.Enabled = false
end

function Demands.Toggle()
	if UI.Enabled then
		Demands.OnHide()
	else
		Demands.OnShow()
	end
end

function Demands.Init()
	-- NEW: Begin with dense widgets hidden
	HideDenseDemandWidgetsInitially()

	-- NEW: Prime CurrentLevel from save file if available (works before server events arrive)
	do
		local SaveData = PlayerDataController.GetSaveFileData()
		if SaveData then
			-- your Progression.lua uses SaveData.cityLevel; UpdateStatsUI pushes "data.level"
			CurrentLevel = tonumber(SaveData.cityLevel or SaveData.level) or 0
		end
	end

	-- NEW: Listen for full unlock map (same event Build Menu consumes)
	FUS.OnClientEvent:Connect(function(unlockStatus)
		for k, v in pairs(unlockStatus) do
			UnlockedTypes[k] = v
		end
		RefreshDenseDemandVisibility()
	end)

	-- NEW: Track level changes as a fallback signal (e.g., if this module missed the first FUS)
	UIUpdate_RemoteEvent.OnClientEvent:Connect(function(data)
		if data and data.level ~= nil then
			CurrentLevel = tonumber(data.level) or CurrentLevel
			RefreshDenseDemandVisibility()
		end
	end)

	-- Inputs
	UserInputService.InputBegan:Connect(function(InputObject)
		if not UI.Enabled then return end
		if InputObject.KeyCode == Enum.KeyCode.ButtonB then
			Demands.OnHide()
		end
	end)

	-- Exit Button
	UI_Exit.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		Demands.OnHide()
	end)

	-- Exit Button VFX
	UtilityGUI.VisualMouseInteraction(
		UI_Exit, UI_Exit.TextLabel,
		TweenInfo.new(0.15),
		{ Size = UDim2.fromScale(1.25, 1.25) },
		{ Size = UDim2.fromScale(0.5, 0.5) }
	)

	-- Set Tab
	UI_Tab_DemandsButton.MouseButton1Down:Connect(function()
		SetTab("Demands")
	end)
	UI_Tab_PowerButton.MouseButton1Down:Connect(function()
		SetTab("Power")
	end)
	UI_Tab_WaterButton.MouseButton1Down:Connect(function()
		SetTab("Water")
	end)

	-- Tab Button VFX
	UtilityGUI.VisualMouseInteraction(
		UI_Tab_DemandsButton, UI_Tab_DemandsButton.offsetContainer,
		TweenInfo.new(0.15),
		{ Size = UDim2.fromScale(0, 1.25) }
	)
	UtilityGUI.VisualMouseInteraction(
		UI_Tab_PowerButton, UI_Tab_PowerButton.offsetContainer,
		TweenInfo.new(0.15),
		{ Size = UDim2.fromScale(0, 1.25) }
	)
	UtilityGUI.VisualMouseInteraction(
		UI_Tab_WaterButton, UI_Tab_WaterButton.offsetContainer,
		TweenInfo.new(0.15),
		{ Size = UDim2.fromScale(0, 1.25) }
	)

	-- NEW: One more safeguard refresh at the end of Init
	RefreshDenseDemandVisibility()
end

return Demands
