local ControlHintGui = {}

-- Roblox Services
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies
local InputIcons = require(ReplicatedStorage.Scripts.InputIcons)
local InputController = require(ReplicatedStorage.Scripts.Controllers.InputController)

-- Constants
local GROUPS = {
	--["GroupName"] = {
	--	{"ActionName", PCKeyCode, GamepadKeyCode},
	--},
	
	["Default"] = {
		_Priority = 1,
		--{"Interact", Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonX},
		--{"Jump", Enum.KeyCode.Space, Enum.KeyCode.ButtonA},
	},
}
local GROUP_PRIORITIES = {}
for GroupID, Data in GROUPS do
	assert(Data._Priority, "_Priority Missing for Group ("..GroupID..")")
	GROUP_PRIORITIES[GroupID] = Data._Priority
	Data._Priority = nil
end

-- Defines
local UI = script.Parent
local ActiveControlHints = {} -- [ControlName] = Frame
local CurrentGroupName = nil -- GroupName?
local CurrentGroups = {} -- [GroupName] = PriorityNumber

-- UI references
local UI_MainFrame = UI:WaitForChild("MainFrame")
local UI_HintTemplate = UI:WaitForChild("MainFrame"):WaitForChild("Hint_Template")
UI_HintTemplate.Visible = false

-- Helper Functions
local function UpdateMainFrameVisible()
	UI_MainFrame.Visible = InputController.GetInputType() ~= "Mobile"
end

-- Module Functions
function ControlHintGui.OnShow()
	UI.Enabled = true
end

function ControlHintGui.OnHide()
	UI.Enabled = false
end

function ControlHintGui.AddControlHint(ControlName: string, ControlInputPC, ControlInputGamepad, LayoutOrder: number)
	assert(ActiveControlHints[ControlName] == nil, "Duplicate ControlHint ("..ControlName..")")
	
	local HintFrame = UI_HintTemplate:Clone()
	HintFrame.Name = ControlName
	HintFrame.Visible = true
	HintFrame.ActionNameBG.Text = ControlName
	HintFrame.ActionNameBG.ActionNameFG.Text = ControlName
	
	if ControlInputPC then
		HintFrame.InputIconBG_Keyboard.Image = InputIcons[ControlInputPC]
		HintFrame.InputIconBG_Keyboard.InputIconFG.Image = InputIcons[ControlInputPC]
	else
		HintFrame.InputIconBG_Keyboard:Destroy()
	end
	if ControlInputGamepad then
		HintFrame.InputIconBG_Xbox.Image = InputIcons[ControlInputGamepad]
		HintFrame.InputIconBG_Xbox.InputIconFG.Image = InputIcons[ControlInputGamepad]
		HintFrame.InputIconBG_PlayStation.Image = InputIcons.PlayStation[ControlInputGamepad]
		HintFrame.InputIconBG_PlayStation.InputIconFG.Image = InputIcons.PlayStation[ControlInputGamepad]
	else
		HintFrame.InputIconBG_Xbox:Destroy()
		HintFrame.InputIconBG_PlayStation:Destroy()
	end
	
	HintFrame.Parent = UI_HintTemplate.Parent
	
	ActiveControlHints[ControlName] = {
		HintFrame = HintFrame,
		InputBegan = UserInputService.InputBegan:Connect(function(InputObject)
			if InputObject.KeyCode == ControlInputPC
				or InputObject.KeyCode == ControlInputGamepad
				or InputObject.UserInputType == ControlInputPC
				or InputObject.UserInputType == ControlInputGamepad
			then
				if ControlInputPC then
					TweenService:Create(HintFrame.InputIconBG_Keyboard.InputIconFG, TweenInfo.new(0.1), {
						Size = UDim2.fromScale(0.8, 0.8),
						Rotation = 15,
					}):Play()
				end
				if ControlInputGamepad then
					TweenService:Create(HintFrame.InputIconBG_Xbox.InputIconFG, TweenInfo.new(0.1), {
						Size = UDim2.fromScale(0.8, 0.8)
					}):Play()
					TweenService:Create(HintFrame.InputIconBG_PlayStation.InputIconFG, TweenInfo.new(0.1), {
						Size = UDim2.fromScale(0.8, 0.8)
					}):Play()
				end
				TweenService:Create(HintFrame.ActionNameBG, TweenInfo.new(0.1), {
					BackgroundColor3 = Color3.fromRGB(255, 255, 255)	
				}):Play()
			end
		end),
		InputEnded = UserInputService.InputEnded:Connect(function(InputObject)
			if InputObject.KeyCode == ControlInputPC
				or InputObject.KeyCode == ControlInputGamepad
				or InputObject.UserInputType == ControlInputPC
				or InputObject.UserInputType == ControlInputGamepad
			then
				if ControlInputPC then
					TweenService:Create(HintFrame.InputIconBG_Keyboard.InputIconFG, TweenInfo.new(0.1), {
						Size = UDim2.fromScale(1, 1),
						Rotation = 0,
					}):Play()
				end
				if ControlInputGamepad then
					TweenService:Create(HintFrame.InputIconBG_Xbox.InputIconFG, TweenInfo.new(0.1), {
						Size = UDim2.fromScale(1, 1)
					}):Play()
					TweenService:Create(HintFrame.InputIconBG_PlayStation.InputIconFG, TweenInfo.new(0.1), {
						Size = UDim2.fromScale(1, 1)
					}):Play()
				end
				TweenService:Create(HintFrame.ActionNameBG, TweenInfo.new(0.1), {
					BackgroundColor3 = Color3.fromRGB(0, 0, 0)	
				}):Play()
			end
		end),
	}
end

function ControlHintGui.RemoveControlHint(ControlName: string)
	assert(ActiveControlHints[ControlName] ~= nil, "ControlHint Missing ("..ControlName..")")
	
	ActiveControlHints[ControlName].HintFrame:Destroy()
	ActiveControlHints[ControlName].InputBegan:Disconnect()
	ActiveControlHints[ControlName].InputEnded:Disconnect()
	ActiveControlHints[ControlName] = nil
end

function ControlHintGui.SetCurrentGroup(GroupName: string, Enabled: boolean?)
	assert(GROUPS[GroupName], "Invalid GroupName ("..GroupName..")")
	
	local GroupPriority = GROUP_PRIORITIES[GroupName]
	
	-- Add Group
	if Enabled and not CurrentGroups[GroupName] then
		CurrentGroups[GroupName] = GroupPriority
		
	-- Remove Gorup
	elseif not Enabled and CurrentGroups[GroupName] then
		CurrentGroups[GroupName] = nil
		
	end
	
	-- Find Best newest group
	local NewCurrentGroupName = nil
	local BestPriority = nil
	for ExistingGroupName, Priority in CurrentGroups do
		if not BestPriority or Priority > BestPriority then
			BestPriority = Priority
			NewCurrentGroupName = ExistingGroupName
		end
	end
	
	-- Apply modifications if change has occurred
	if CurrentGroupName ~= NewCurrentGroupName then
		CurrentGroupName = NewCurrentGroupName
		
		-- Clear Current Hints
		for ControlName in ActiveControlHints do
			ControlHintGui.RemoveControlHint(ControlName)
		end
		-- Add New Hints
		if CurrentGroupName then
			for Index, Data in GROUPS[CurrentGroupName] do
				ControlHintGui.AddControlHint(Data[1], Data[2], Data[3], -Index)
			end
		end
	end
end

function ControlHintGui.Init()
	
	
	-- Input Changed
	InputController.ListenForInputTypeChanged(UpdateMainFrameVisible)
	UpdateMainFrameVisible()
	
	-- Default
	ControlHintGui.SetCurrentGroup("Default", true)
end

return ControlHintGui
