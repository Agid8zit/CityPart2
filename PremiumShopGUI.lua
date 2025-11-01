local PremiumShopGui = {}

-- Roblox Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

-- Dependencies
local Abrv = require(ReplicatedStorage.Scripts.UI.Abrv)
local Utility = require(ReplicatedStorage.Scripts.Utility)
local UtilityGUI = require(ReplicatedStorage.Scripts.UI.UtilityGUI)
local Gamepasses = require(ReplicatedStorage.Scripts.Gamepasses)
local DevProducts = require(ReplicatedStorage.Scripts.DevProducts)
local SoundController = require(ReplicatedStorage.Scripts.Controllers.SoundController)
local InputController = require(ReplicatedStorage.Scripts.Controllers.InputController)
local PlayerDataController = require(ReplicatedStorage.Scripts.Controllers.PlayerDataController)

-- Constants
local TAB_SELECTED = Color3.fromRGB(255, 255, 255)
local TAB_UNSELECTED = Color3.fromRGB(170, 170, 170)

-- Defines
local LocalPlayer: Player = Players.LocalPlayer
local UI = script.Parent
local TabSection = nil
local GamepassFrames = {} -- [GamepassName] = Frame
local DevproductFrames = {} -- [DevproductName] = Frame

local OnExitFunctions = {} -- Array<Function>

local AllGamepassChoicesOrdered = {} -- Array<Frame>
local AllDevproductsChoiceOrdered = {} -- Array<Frame>
local CurrentGamepassSelectionIndex = nil -- number?
local CurrentDevproductSelectionIndex = nil -- number?

local BuyCallbackFromFrame = {} -- [Frame] = ...

-- UI references
local UI_Exit = UI.MainFrame.Exit

local UI_Gamepass_ScrollingFrame = UI.MainFrame.Container.Content.GamepassCategory

local UI_TabBtnMoneyCategory = UI.MainFrame.Container.Tabs.MoneyCategory
local UI_TabBtnGamepassCategory = UI.MainFrame.Container.Tabs.GamepassCategory

local UI_TabMoneyCategory = UI.MainFrame.Container.Content.MoneyCategory
local UI_TabGamepassCategory = UI.MainFrame.Container.Content.GamepassCategory

local UI_DevProductChoice1 = UI.MainFrame.Container.Content.MoneyCategory.Container.Choice1
local UI_DevProductChoice2 = UI.MainFrame.Container.Content.MoneyCategory.Container.Choice2
local UI_DevProductChoice3 = UI.MainFrame.Container.Content.MoneyCategory.Container.Choice3
local UI_DevProductChoice4 = UI.MainFrame.Container.Content.MoneyCategory.Container.Choice4
local UI_DevProductChoice5 = UI.MainFrame.Container.Content.MoneyCategory.Container.Choice5
local UI_DevProductChoice6 = UI.MainFrame.Container.Content.MoneyCategory.Container.Choice6

local DEVPRODUCT_BUTTONS = {
	-- Button = DevProductName
	[UI_DevProductChoice1] = {DevProductName = "Coin Option1"},
	[UI_DevProductChoice2] = {DevProductName = "Coin Option2"},
	[UI_DevProductChoice3] = {DevProductName = "Coin Option3"},
	[UI_DevProductChoice4] = {DevProductName = "Coin Option4"},
	[UI_DevProductChoice5] = {DevProductName = "Coin Option5"},
	[UI_DevProductChoice6] = {DevProductName = "Coin Option6"},
}

local UI_GamepassTemplate = UI.MainFrame.Container.Content.GamepassCategory.GamepassTemplate; UI_GamepassTemplate.Visible = false

-- Helper Functions
--local function SetGamepassSelection(Index: number?)
--	if CurrentGamepassSelectionIndex == Index then return end
	
--	-- unselect
--	if CurrentGamepassSelectionIndex then
--		local Choice = AllGamepassChoicesOrdered[CurrentGamepassSelectionIndex].Choice
--		Choice.UIStroke.Color = Color3.fromRGB(147, 147, 147)
--	end
	
--	CurrentGamepassSelectionIndex = Index
	
--	-- select
--	if CurrentGamepassSelectionIndex then
--		local Choice = AllGamepassChoicesOrdered[CurrentGamepassSelectionIndex].Choice
--		Choice.UIStroke.Color = Color3.fromRGB(217, 140, 52)
		
--		-- adjust canvas
--		UtilityGUI.AdjustScrollingFramePositionToLookAtAFrame(UI_Gamepass_ScrollingFrame, Choice)
--	end
--end

--local function SetDevproductSelection(Index: number?)
--	if CurrentDevproductSelectionIndex == Index then return end

--	-- unselect
--	if CurrentDevproductSelectionIndex then
--		local Choice = AllDevproductsChoiceOrdered[CurrentDevproductSelectionIndex].Choice
--		Choice.OutlineSelection.Visible = false
--	end

--	CurrentDevproductSelectionIndex = Index

--	-- select
--	if CurrentDevproductSelectionIndex then
--		local Choice = AllDevproductsChoiceOrdered[CurrentDevproductSelectionIndex].Choice
--		Choice.OutlineSelection.Visible = true
--	end
--end

local function SetTabGamepass()
	SoundController.PlaySoundOnce("UI", "SmallClick")
	
	TabSection = "Gamepass"
	
	-- Fix Tab Colors
	UI_TabBtnMoneyCategory.Container.Icon.ImageColor3 = TAB_UNSELECTED
	UI_TabBtnMoneyCategory.Container.TextLabel.TextColor3 = TAB_UNSELECTED		
	TweenService:Create(UI_TabBtnMoneyCategory.Underline, TweenInfo.new(0.5), {
		Size = UDim2.new(0, 0, 0, 2)
	}):Play()
	
	UI_TabBtnGamepassCategory.Container.Icon.ImageColor3 = TAB_SELECTED
	UI_TabBtnGamepassCategory.Container.TextLabel.TextColor3 = TAB_SELECTED
	TweenService:Create(UI_TabBtnGamepassCategory.Underline, TweenInfo.new(0.5), {
		Size = UDim2.new(1, 0, 0, 2)
	}):Play()
	
	-- Visible Update
	UI_TabMoneyCategory.Visible = false
	UI_TabGamepassCategory.Visible = true
	
	-- Default Selection
	--if InputController.GetInputType() == "Gamepad" then
	--	SetGamepassSelection(1)
	--else
	--	SetGamepassSelection(nil)
	--end
	--SetDevproductSelection(nil)
end
local function SetTabMoney()
	SoundController.PlaySoundOnce("UI", "SmallClick")
	
	TabSection = "Money"
	
	-- Fix Tab Colors
	UI_TabBtnMoneyCategory.Container.Icon.ImageColor3 = TAB_SELECTED
	UI_TabBtnMoneyCategory.Container.TextLabel.TextColor3 = TAB_SELECTED		
	TweenService:Create(UI_TabBtnMoneyCategory.Underline, TweenInfo.new(0.5), {
		Size = UDim2.new(1, 0, 0, 2)
	}):Play()
	
	UI_TabBtnGamepassCategory.Container.Icon.ImageColor3 = TAB_UNSELECTED
	UI_TabBtnGamepassCategory.Container.TextLabel.TextColor3 = TAB_UNSELECTED
	TweenService:Create(UI_TabBtnGamepassCategory.Underline, TweenInfo.new(0.5), {
		Size = UDim2.new(0, 0, 0, 2)
	}):Play()
	
	-- Visible Update
	UI_TabMoneyCategory.Visible = true
	UI_TabGamepassCategory.Visible = false
	
	-- Default Selection
	--if InputController.GetInputType() == "Gamepad" then
	--	SetDevproductSelection(1)
	--else
	--	SetDevproductSelection(nil)
	--end
	--SetGamepassSelection(nil)
end

--local function NavigateGamepad_Left()
--	if not UI.Enabled then return end

--	if TabSection == "Gamepass" and CurrentGamepassSelectionIndex then
--		-- none
	
--	elseif TabSection == "Money" and CurrentDevproductSelectionIndex then
--		SoundController.PlaySoundOnce("UI", "SmallClick")
		
--		local Index = CurrentDevproductSelectionIndex - 1
--		if Index < 1 then Index = #AllDevproductsChoiceOrdered end
--		SetDevproductSelection(Index)
--	end
--end
--local function NavigateGamepad_Right()
--	if not UI.Enabled then return end

--	if TabSection == "Gamepass" and CurrentGamepassSelectionIndex then
--		-- none

--	elseif TabSection == "Money" and CurrentDevproductSelectionIndex then
--		SoundController.PlaySoundOnce("UI", "SmallClick")
		
--		local Index = CurrentDevproductSelectionIndex + 1
--		if Index > #AllDevproductsChoiceOrdered then Index = 1 end
--		SetDevproductSelection(Index)
--	end
--end
--local function NavigateGamepad_Down()
--	if not UI.Enabled then return end
	
--	if TabSection == "Gamepass" and CurrentGamepassSelectionIndex then
--		SoundController.PlaySoundOnce("UI", "SmallClick")
		
--		local Index = CurrentGamepassSelectionIndex + 1
--		if Index > #AllGamepassChoicesOrdered then Index = 1 end
--		SetGamepassSelection(Index)
		
--	elseif TabSection == "Money" and CurrentDevproductSelectionIndex then
--		SoundController.PlaySoundOnce("UI", "SmallClick")
		
--		local RowLength = 3
--		local Index = CurrentDevproductSelectionIndex + RowLength
--		if Index > #AllDevproductsChoiceOrdered then
--			while Index >= 1 do
--				Index -= RowLength
--			end
--			Index += RowLength
--		end

--		SetDevproductSelection(Index)
--	end
	
--end
--local function NavigateGamepad_Up()
--	if not UI.Enabled then return end

--	if TabSection == "Gamepass" and CurrentGamepassSelectionIndex then
--		SoundController.PlaySoundOnce("UI", "SmallClick")
		
--		local Index = CurrentGamepassSelectionIndex - 1
--		if Index < 1 then Index = #AllGamepassChoicesOrdered end
--		SetGamepassSelection(Index)
		
--	elseif TabSection == "Money" and CurrentDevproductSelectionIndex then
--		SoundController.PlaySoundOnce("UI", "SmallClick")
		
--		local RowLength = 3
--		local Index = CurrentDevproductSelectionIndex - RowLength
--		if Index < 1 then 
--			while Index <= #AllDevproductsChoiceOrdered do
--				Index += RowLength
--			end
--			Index -= RowLength
--		end 

--		SetDevproductSelection(Index)
--	end
--end

-- Module Functions
function PremiumShopGui.OnShow(SetTabSection: string?)
	UI.Enabled = true
	
	SoundController.PlaySoundOnce("UI", "SmallClick")
	
	SetTabSection = SetTabSection or "Money"
	
	if SetTabSection == "Gamepass" then
		SetTabGamepass()
	elseif SetTabSection == "Money" then
		SetTabMoney()
	end
	
	-- Analytics
	--AnalyticsController.FunnlEventOnce(Enums.FUNNEL_EVENT_RECURRING.OPENED_PREMIUM_SHOP)
end

function PremiumShopGui.OnHide()
	UI.Enabled = false
	
	SoundController.PlaySoundOnce("UI", "SmallClick")
	
	for _, Function in OnExitFunctions do
		Function()
	end
end

function PremiumShopGui.Toggle()
	if UI.Enabled then
		PremiumShopGui.OnHide()
	else
		PremiumShopGui.OnShow()
	end
end

local function AddGamepassFrame(GamepassName: string)

	local GamepassFrame = UI_GamepassTemplate:Clone()
	GamepassFrame.LayoutOrder = Gamepasses.GetLayoutOrder(GamepassName)
	GamepassFrame.GamepassIcon.Image = Gamepasses.GetImage(GamepassName)
	GamepassFrame.GamepassName.Text = Gamepasses.GetDisplayName(GamepassName)
	GamepassFrame.Description.Text = Gamepasses.GetDescription(GamepassName)
	GamepassFrame.BuyButton.FG.Cost.Text = Gamepasses.GetPrice(GamepassName)
	GamepassFrame.Visible = true
	
	GamepassFrame.Parent = UI_GamepassTemplate.Parent
	
	-- Button
	GamepassFrame.BuyButton.Button.MouseButton1Down:Connect(function()
		local GamepassID = Gamepasses.GetGamepassID(GamepassName)
		local Success = pcall(function()
			MarketplaceService:PromptGamePassPurchase(LocalPlayer, GamepassID)
		end)
	end)
	GamepassFrame.BGButton.MouseButton1Down:Connect(function()
		local GamepassID = Gamepasses.GetGamepassID(GamepassName)
		local Success = pcall(function()
			MarketplaceService:PromptGamePassPurchase(LocalPlayer, GamepassID)
		end)
	end)
	
	-- Outline
	GamepassFrame.BuyButton.Button.MouseEnter:Connect(function()
		TweenService:Create(GamepassFrame.UIStroke, TweenInfo.new(0.15), {
			Color = Color3.fromRGB(255, 255, 255),
		}):Play()
	end)
	GamepassFrame.BuyButton.Button.MouseLeave:Connect(function()
		TweenService:Create(GamepassFrame.UIStroke, TweenInfo.new(0.15), {
			Color = Color3.fromRGB(147, 147, 147),
		}):Play()
	end)
	
	-- VFX
	table.insert(OnExitFunctions, UtilityGUI.VisualMouseInteraction(
		GamepassFrame.BuyButton.Button, GamepassFrame.BuyButton.FG,
		TweenInfo.new(0.1),
		{Position = UDim2.fromScale(0.5, 0.45)},
		{Position = UDim2.fromScale(0.5, 0.5)}
		))
	
	
	return GamepassFrame
end

function PremiumShopGui.Init()
	
	-- Exit Button
	table.insert(OnExitFunctions, UtilityGUI.VisualMouseInteraction(
		UI_Exit, UI_Exit.TextLabel,
		TweenInfo.new(0.1),
		{Size = UDim2.fromScale(1.2, 1.2)},
		{Size = UDim2.fromScale(0.8, 0.8)}
		))
	UI_Exit.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		PremiumShopGui.OnHide()
	end)

	-- Tabs
	UI_TabBtnMoneyCategory:GetPropertyChangedSignal("GuiState"):Connect(function()
		if UI_TabBtnMoneyCategory.GuiState == Enum.GuiState.Hover then
			TweenService:Create(UI_TabBtnMoneyCategory.Container, TweenInfo.new(0.15), {
				Position = UDim2.fromScale(0, -0.1)
			}):Play()
		else
			TweenService:Create(UI_TabBtnMoneyCategory.Container, TweenInfo.new(0.15), {
				Position = UDim2.fromScale(0, 0)
			}):Play()
		end
	end)
	UI_TabBtnMoneyCategory.MouseButton1Down:Connect(SetTabMoney)

	UI_TabBtnGamepassCategory:GetPropertyChangedSignal("GuiState"):Connect(function()
		if UI_TabBtnGamepassCategory.GuiState == Enum.GuiState.Hover then
			TweenService:Create(UI_TabBtnGamepassCategory.Container, TweenInfo.new(0.15), {
				Position = UDim2.fromScale(0, -0.1)
			}):Play()
		else
			TweenService:Create(UI_TabBtnGamepassCategory.Container, TweenInfo.new(0.15), {
				Position = UDim2.fromScale(0, 0)
			}):Play()
		end
	end)
	UI_TabBtnGamepassCategory.MouseButton1Down:Connect(SetTabGamepass)

	-- Defaults if using gamepad
	--InputController.ListenForInputTypeChanged(function(NewInputType)
	--	if not UI.Enabled then return end
	--	if NewInputType == "Gamepad" then
	--		if TabSection == "Gamepass" then
	--			SetGamepassSelection(1)
	--			SetDevproductSelection(nil)
	--		elseif TabSection == "Money" then
	--			SetDevproductSelection(1)
	--			SetGamepassSelection(nil)
	--		end
	--	else
	--		SetGamepassSelection(nil)
	--		SetDevproductSelection(nil)
	--	end
	--end)

	-- Navigation
	--InputController.ListenForLeftAnalog_Left(NavigateGamepad_Left)
	--InputController.ListenForLeftAnalog_Right(NavigateGamepad_Right)
	--InputController.ListenForLeftAnalog_Down(NavigateGamepad_Down)
	--InputController.ListenForLeftAnalog_Up(NavigateGamepad_Up)

	-- Inputs
	UserInputService.InputBegan:Connect(function(InputObject)
		if not UI.Enabled then return end
		
		-- Exit Input
		if InputObject.KeyCode == Enum.KeyCode.ButtonB then
			SoundController.PlaySoundOnce("UI", "SmallClick")
			PremiumShopGui.OnHide()
		end

		-- Set Tabs from buttons
		if TabSection == "Money" and InputObject.KeyCode == Enum.KeyCode.ButtonR1 then
			SetTabGamepass()
		elseif TabSection == "Gamepass" and InputObject.KeyCode == Enum.KeyCode.ButtonL1 then
			SetTabMoney()
		end

		---- Dpad Traversal
		--if InputObject.KeyCode == Enum.KeyCode.DPadLeft then
		--	NavigateGamepad_Left()

		--elseif InputObject.KeyCode == Enum.KeyCode.DPadRight then
		--	NavigateGamepad_Right()

		--elseif InputObject.KeyCode == Enum.KeyCode.DPadDown then
		--	NavigateGamepad_Down()

		--elseif InputObject.KeyCode == Enum.KeyCode.DPadUp then
		--	NavigateGamepad_Up()
		--end

		-- Accept
		--if TabSection == "Gamepass" and CurrentGamepassSelectionIndex then

		--	-- Gamepad Buy
		--	if InputObject.KeyCode == Enum.KeyCode.ButtonA and CurrentGamepassSelectionIndex then
		--		SoundController.PlaySoundOnce("UI", "SmallClick")

		--		local Choice = AllGamepassChoicesOrdered[CurrentGamepassSelectionIndex].Choice
		--		if BuyCallbackFromFrame[Choice] then
		--			BuyCallbackFromFrame[Choice]()
		--		end
		--	end

		--elseif TabSection == "Money" and CurrentDevproductSelectionIndex then

		--	-- Gamepad Buy
		--	if InputObject.KeyCode == Enum.KeyCode.ButtonA and CurrentDevproductSelectionIndex then

		--		local Choice = AllDevproductsChoiceOrdered[CurrentDevproductSelectionIndex].Choice
		--		if BuyCallbackFromFrame[Choice] then
		--			BuyCallbackFromFrame[Choice]()
		--		end
		--	end
		--end

	end)
	
	-- Add Gamepass Choices
	for GamepassName, Data in Gamepasses.GetGamepassesRaw() do
		while not Gamepasses.IsLoaded(GamepassName) do task.wait() end
		local Choice = AddGamepassFrame(GamepassName)
		-- Cache
		GamepassFrames[GamepassName] = Choice
		BuyCallbackFromFrame[Choice] = function()
			local GamepassID = Gamepasses.GetGamepassID(GamepassName)
			local Success = pcall(function()
				MarketplaceService:PromptGamePassPurchase(LocalPlayer, GamepassID)
			end)
		end

		local LayoutOrder = Gamepasses.GetLayoutOrder(GamepassName)
		table.insert(AllGamepassChoicesOrdered, {
			LayoutOrder = LayoutOrder,
			Choice = Choice,
		})
	end
	-- Sort
	table.sort(AllGamepassChoicesOrdered, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	
	-- Add Devproducts
	for DevProductChoiceButton, Data in DEVPRODUCT_BUTTONS do
		
		while not DevProducts.IsLoaded(Data.DevProductName) do task.wait() end
		
		-- Update UI
		DevProductChoiceButton.Frame.Robux.cost.Text = DevProducts.GetPrice(Data.DevProductName)
		DevProductChoiceButton.Frame.Header.Header.Text = "$"..Abrv.abbreviateNumber(DevProducts.GetEarnedCoins(Data.DevProductName))
		
		-- Click effects
		table.insert(OnExitFunctions, UtilityGUI.VisualMouseInteraction(
			DevProductChoiceButton, DevProductChoiceButton.Frame.IconContainer.Icon,
			TweenInfo.new(0.1),
			{Size = UDim2.fromScale(1.2, 1.2)},
			{Size = UDim2.fromScale(0.8, 0.8)}
			))
		table.insert(OnExitFunctions, UtilityGUI.VisualMouseInteraction(
			DevProductChoiceButton, DevProductChoiceButton.Outline.UIStroke,
			TweenInfo.new(0.1),
			{Color = Color3.fromRGB(255, 255, 255)},
			{Color = Color3.fromRGB(0, 0, 0)}
			))
		DevProductChoiceButton.MouseButton1Down:Connect(function()
			SoundController.PlaySoundOnce("UI", "SmallClick")
			BuyCallbackFromFrame[DevProductChoiceButton]()
		end)
		BuyCallbackFromFrame[DevProductChoiceButton] = function()
			local DevProductID = DevProducts.GetDevProductID(Data.DevProductName)
			if not DevProductID then return false, 2 end

			local Success = pcall(function()
				MarketplaceService:PromptProductPurchase(LocalPlayer, DevProductID)
			end)
		end
		
		-- Glow Rotate On Hover 
		local h = nil
		DevProductChoiceButton.MouseEnter:Connect(function()
			if h == nil then
				h = RunService.Heartbeat:Connect(function(Step)
					DevProductChoiceButton.Frame.IconContainer.Glow.Rotation += Step * 60
				end)
			end
		end)
		DevProductChoiceButton.MouseLeave:Connect(function()
			if h ~= nil then
				h:Disconnect()
				h = nil
			end
		end)
		
		-- Store
		table.insert(AllDevproductsChoiceOrdered, {
			LayoutOrder = DevProducts.GetLayoutOrder(Data.DevProductName),
			Choice = DevProductChoiceButton,
		})
	end
	-- Sort
	table.sort(AllDevproductsChoiceOrdered, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	
	-- Update Owned Gamepasses
	local function CheckOwnedGamepass(GamepassName: string)
		local PlayerData = PlayerDataController.GetData()
		if not PlayerData then return false end

		return PlayerDataController.GetData().OwnedGamepasses[GamepassName]
	end
	
	local function UpdateGamepassFrame(GamepassName: string)
		local Choice = GamepassFrames[GamepassName]
		local IsOwned = CheckOwnedGamepass(GamepassName)
		Choice.GamepassIcon.Checkmark.Visible = IsOwned
		Choice.GamepassIcon.ImageTransparency = IsOwned and 0.5 or 0.0

		Choice.Description.TextColor3 = IsOwned and Color3.fromRGB(127, 127, 127) or Color3.fromRGB(255, 255, 255)
		Choice.GamepassName.TextColor3 = IsOwned and Color3.fromRGB(127, 127, 127) or Color3.fromRGB(255, 255, 255)

		if Gamepasses.IsForSale(GamepassName) then
			Choice.BuyButton.Visible = not IsOwned
			Choice.BGButton.Visible = not IsOwned
			Choice.Offsale.Visible = false
		else
			Choice.BuyButton.Visible = false
			Choice.BGButton.Visible = false
			Choice.Offsale.Visible = true
		end

		Choice.LayoutOrder = Gamepasses.GetLayoutOrder(GamepassName)
		if IsOwned then Choice.LayoutOrder += 1000 end
	end
	
	for GamepassName in GamepassFrames do
		UpdateGamepassFrame(GamepassName)
	end
	
	PlayerDataController.ListenForDataChange("OwnedGamepasses", function()
		for GamepassName, Choice in GamepassFrames do
			UpdateGamepassFrame(GamepassName)
		end
	end)
end

return PremiumShopGui