local InputController = {}

-- Roblox Services
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies
local Utility = require(ReplicatedStorage.Scripts.Utility)

-- Constants
local DEBUG_SHOW_MOBILE_BUTTONS = false
local IS_PLAYSTATION = UserInputService:GetStringForKeyCode(Enum.KeyCode.ButtonA) == "ButtonCross"

local INPUT_TYPES = {
	KEYBOARD_AND_MOUSE = "KeyboardMouse",
	GAMEPAD = "Gamepad",
	MOBILE = "Mobile",
}

local VALID_INPUT_TYPES = {
	[Enum.UserInputType.Keyboard] = INPUT_TYPES.KEYBOARD_AND_MOUSE,
	[Enum.UserInputType.TextInput] = INPUT_TYPES.KEYBOARD_AND_MOUSE,
	[Enum.UserInputType.Focus] = INPUT_TYPES.KEYBOARD_AND_MOUSE,

	[Enum.UserInputType.MouseMovement] = INPUT_TYPES.KEYBOARD_AND_MOUSE,
	[Enum.UserInputType.MouseButton1] = INPUT_TYPES.KEYBOARD_AND_MOUSE,
	[Enum.UserInputType.MouseButton2] = INPUT_TYPES.KEYBOARD_AND_MOUSE,

	[Enum.UserInputType.Gamepad1] = INPUT_TYPES.GAMEPAD,

	[Enum.UserInputType.Touch] = INPUT_TYPES.MOBILE,
}

-- Defines
local InputType = nil;
local InputTypeChangedListeners = {} -- Array<Listener>

local InputHint_Keyboard_GuiObjects = {} -- Set<GuiObject>
local InputHint_Xbox_GuiObjects = {} -- Set<GuiObject>
local InputHint_PlayStation_GuiObjects = {} -- Set<GuiObject>
local InputHint_Mobile_GuiObjects = {} -- Set<GuiObject>

local ListenersFunctions_OnBegan = {} -- [UID] = Listener
local ListeningInputs_OnBegan = {} -- [Input] = Set<UID>

local ListenersFunctions_OnEnded = {} -- [UID] = Listener
local ListeningInputs_OnEnded = {} -- [Input] = Set<UID>

local ListenersFunctions_OnTouchStarted = {} -- [UID] = Listener
local ListeningInputs_OnTouchStarted = {} -- [Input] = Set<UID>

local ListenersFunctions_OnTouchEnded = {} -- [UID] = Listener
local ListeningInputs_OnTouchEnded = {} -- [Input] = Set<UID>

-- Helper Functions
local function UpdateInputType(NewInputTypeRaw)
	local NewInputType = VALID_INPUT_TYPES[NewInputTypeRaw]
	if not NewInputType then return end

	local LastInputType = InputType
	InputType = NewInputType
	
	-- Update Listeners
	for _, Listener in InputTypeChangedListeners do
		Listener(InputType)
	end

	-- Update Hint Objects
	local EnabledHints = {}
	
	if LastInputType == INPUT_TYPES.KEYBOARD_AND_MOUSE or InputType == INPUT_TYPES.KEYBOARD_AND_MOUSE then
		for GuiObject in InputHint_Keyboard_GuiObjects do
			GuiObject.Visible = InputType == INPUT_TYPES.KEYBOARD_AND_MOUSE
			if GuiObject.Visible then EnabledHints[GuiObject] = true end
		end
	end
	if not IS_PLAYSTATION and (LastInputType == INPUT_TYPES.GAMEPAD or InputType == INPUT_TYPES.GAMEPAD) then
		for GuiObject in InputHint_Xbox_GuiObjects do
			if EnabledHints[GuiObject] then continue end
			GuiObject.Visible = InputType == INPUT_TYPES.GAMEPAD and not IS_PLAYSTATION
			if GuiObject.Visible then EnabledHints[GuiObject] = true end
		end
	end
	if IS_PLAYSTATION and (LastInputType == INPUT_TYPES.GAMEPAD or InputType == INPUT_TYPES.GAMEPAD) then
		for GuiObject in InputHint_PlayStation_GuiObjects do
			if EnabledHints[GuiObject] then continue end
			GuiObject.Visible = InputType == INPUT_TYPES.GAMEPAD and IS_PLAYSTATION
			if GuiObject.Visible then EnabledHints[GuiObject] = true end
		end
	end
	if LastInputType == INPUT_TYPES.MOBILE or InputType == INPUT_TYPES.MOBILE then
		for GuiObject in InputHint_Mobile_GuiObjects do
			if EnabledHints[GuiObject] then continue end
			GuiObject.Visible = InputType == INPUT_TYPES.MOBILE
			if GuiObject.Visible then EnabledHints[GuiObject] = true end
		end
	end
end

-- Module Functions
function InputController.IsPlaystation()
	return IS_PLAYSTATION
end

function InputController.GetInputType()
	return InputType
end

function InputController.ListenForInputTypeChanged(ListenFunc: () -> ())
	table.insert(InputTypeChangedListeners, ListenFunc)
end

function InputController.InputBegan(UID: string, ListenerFunction: () -> (), InputsArray)
	assert(ListenersFunctions_OnBegan[UID] == nil, "Listener UID already exists ("..UID..")")
	ListenersFunctions_OnBegan[UID] = ListenerFunction

	assert(InputsArray, "Missing InputsArray")
	for _, InputType in InputsArray do
		if not ListeningInputs_OnBegan[InputType] then
			ListeningInputs_OnBegan[InputType] = {}
		end
		ListeningInputs_OnBegan[InputType][UID] = true
	end
end

function InputController.InputEnded(UID: string, ListenerFunction: () -> (), InputsArray)
	assert(ListenersFunctions_OnEnded[UID] == nil, "Listener UID already exists ("..UID..")")
	ListenersFunctions_OnEnded[UID] = ListenerFunction

	assert(InputsArray, "Missing InputsArray")
	for _, InputType in InputsArray do
		if not ListeningInputs_OnEnded[InputType] then
			ListeningInputs_OnEnded[InputType] = {}
		end
		ListeningInputs_OnEnded[InputType][UID] = true
	end
end

function InputController.TouchStarted(UID: string, ListenerFunction: () -> (), InputsArray)
	assert(ListenersFunctions_OnTouchStarted[UID] == nil, "Listener UID already exists ("..UID..")")
	ListenersFunctions_OnTouchStarted[UID] = ListenerFunction

	assert(InputsArray, "Missing InputsArray")
	for _, InputType in InputsArray do
		if not ListeningInputs_OnTouchStarted[InputType] then
			ListeningInputs_OnTouchStarted[InputType] = {}
		end
		ListeningInputs_OnTouchStarted[InputType][UID] = true
	end
end

function InputController.TouchEnded(UID: string, ListenerFunction: () -> (), InputsArray)
	assert(ListenersFunctions_OnTouchEnded[UID] == nil, "Listener UID already exists ("..UID..")")
	ListenersFunctions_OnTouchEnded[UID] = ListenerFunction

	assert(InputsArray, "Missing InputsArray")
	for _, InputType in InputsArray do
		if not ListeningInputs_OnTouchEnded[InputType] then
			ListeningInputs_OnTouchEnded[InputType] = {}
		end
		ListeningInputs_OnTouchEnded[InputType][UID] = true
	end
end

function InputController.AddMobileButton(PriorityNumber: number, ButtonData)
	if not (UserInputService.TouchEnabled or DEBUG_SHOW_MOBILE_BUTTONS) then return end

	local MobileButtonsGui = shared.GetModule("GuiController").GetModule("MobileButtonsGui")

	MobileButtonsGui.AddButton(PriorityNumber, ButtonData)
end

function InputController.RemoveMobileButton(PriorityNumber: number)
	if not (UserInputService.TouchEnabled or DEBUG_SHOW_MOBILE_BUTTONS) then return end

	local MobileButtonsGui = shared.GetModule("GuiController").GetModule("MobileButtonsGui")

	MobileButtonsGui.RemoveButton(PriorityNumber)
end

function InputController.HasMobileButton(PriorityNumber: number)
	if not (UserInputService.TouchEnabled or DEBUG_SHOW_MOBILE_BUTTONS) then return false end

	local MobileButtonsGui = shared.GetModule("GuiController").GetModule("MobileButtonsGui")

	return MobileButtonsGui.HasButton(PriorityNumber)
end

function InputController.RemoveInputBegan(UID: string)
	ListenersFunctions_OnBegan[UID] = nil

	for InputType, _ in ListeningInputs_OnBegan do
		ListeningInputs_OnBegan[InputType][UID] = nil
	end
end

function InputController.RemoveInputEnded(UID: string)
	ListenersFunctions_OnEnded[UID] = nil

	for InputType, _ in ListeningInputs_OnEnded do
		ListeningInputs_OnEnded[InputType][UID] = nil
	end
end

local AnalogDirectionListeners = {
	Left = {},
	Right = {},
	Down = {},
	Up = {},
}
function InputController.ListenForLeftAnalog_Left(Listener: () -> ())
	table.insert(AnalogDirectionListeners.Left, Listener)
end
function InputController.ListenForLeftAnalog_Right(Listener: () -> ())
	table.insert(AnalogDirectionListeners.Right, Listener)
end
function InputController.ListenForLeftAnalog_Down(Listener: () -> ())
	table.insert(AnalogDirectionListeners.Down, Listener)
end
function InputController.ListenForLeftAnalog_Up(Listener: () -> ())
	table.insert(AnalogDirectionListeners.Up, Listener)
end

-- Init
do
	-- Input Type Changed
	UserInputService.LastInputTypeChanged:Connect(UpdateInputType)
	if UserInputService.TouchEnabled then
		UpdateInputType(Enum.UserInputType.Touch)
	else
		UpdateInputType(UserInputService:GetLastInputType())
	end

	-- Input Start
	UserInputService.TouchStarted:Connect(function(InputObject, GameProcessedEvent)
		if GameProcessedEvent then return end

		local UIDs = ListeningInputs_OnTouchStarted[InputObject.KeyCode]
		if UIDs then
			for UID in UIDs do
				ListenersFunctions_OnTouchStarted[UID](InputObject)
			end
		end

		UIDs = ListeningInputs_OnTouchStarted[InputObject.UserInputType]
		if UIDs then
			for UID in UIDs do
				ListenersFunctions_OnTouchStarted[UID](InputObject)
			end
		end
	end)

	UserInputService.TouchEnded:Connect(function(InputObject)

		local UIDs = ListeningInputs_OnTouchEnded[InputObject.KeyCode]
		if UIDs then
			for UID in UIDs do
				ListenersFunctions_OnTouchEnded[UID](InputObject)
			end
		end

		UIDs = ListeningInputs_OnTouchEnded[InputObject.UserInputType]
		if UIDs then
			for UID in UIDs do
				ListenersFunctions_OnTouchEnded[UID](InputObject)
			end
		end
	end)

	UserInputService.InputBegan:Connect(function(InputObject, GameProcessedEvent)
		if GameProcessedEvent then return end

		local UIDs = ListeningInputs_OnBegan[InputObject.KeyCode]
		if UIDs then
			for UID in UIDs do
				ListenersFunctions_OnBegan[UID](InputObject)
			end
		end

		UIDs = ListeningInputs_OnBegan[InputObject.UserInputType]
		if UIDs then
			for UID in UIDs do
				ListenersFunctions_OnBegan[UID](InputObject)
			end
		end
	end)

	-- Input Ended
	UserInputService.InputEnded:Connect(function(InputObject)

		local UIDs = ListeningInputs_OnEnded[InputObject.KeyCode]
		if UIDs then
			for UID in UIDs do
				ListenersFunctions_OnEnded[UID](InputObject)
			end
		end

		UIDs = ListeningInputs_OnEnded[InputObject.UserInputType]
		if UIDs then
			for UID in UIDs do
				ListenersFunctions_OnEnded[UID](InputObject)
			end
		end
	end)
	
	local CacheX = 0
	local CacheY = 0
	UserInputService.InputChanged:Connect(function(InputObject)
		if InputObject.KeyCode == Enum.KeyCode.Thumbstick1 then
			if CacheX ~= 1 and InputObject.Position.X == 1 then
				for _, Listener in AnalogDirectionListeners.Right do
					Listener()
				end
			elseif CacheX ~= -1 and InputObject.Position.X == -1 then
				for _, Listener in AnalogDirectionListeners.Left do
					Listener()
				end
			end
			
			if CacheY ~= 1 and InputObject.Position.Y == 1 then
				for _, Listener in AnalogDirectionListeners.Up do
					Listener()
				end
			elseif CacheY ~= -1 and InputObject.Position.Y == -1 then
				for _, Listener in AnalogDirectionListeners.Down do
					Listener()
				end
			end
			
			CacheX = InputObject.Position.X
			CacheY = InputObject.Position.Y
		end
	end)

	local function UpdateGuiObjectVisible(GuiObject)
		GuiObject.Visible =
			(GuiObject:HasTag("Input_Keyboard") and (InputType == INPUT_TYPES.KEYBOARD_AND_MOUSE))
			or (GuiObject:HasTag("Input_Xbox") and (InputType == INPUT_TYPES.GAMEPAD) and not IS_PLAYSTATION)
			or (GuiObject:HasTag("Input_PlayStation") and (InputType == INPUT_TYPES.GAMEPAD) and IS_PLAYSTATION)
			or (GuiObject:HasTag("Input_Mobile") and (InputType == INPUT_TYPES.MOBILE))
	end

	local function AddKeyboardInput(GuiObject: GuiObject)
		InputHint_Keyboard_GuiObjects[GuiObject] = true
		UpdateGuiObjectVisible(GuiObject)
	end

	local function AddXboxInput(GuiObject: GuiObject)
		InputHint_Xbox_GuiObjects[GuiObject] = true
		UpdateGuiObjectVisible(GuiObject)
	end

	local function AddPlayStationInput(GuiObject: GuiObject)
		InputHint_PlayStation_GuiObjects[GuiObject] = true
		UpdateGuiObjectVisible(GuiObject)
	end

	local function AddMobileInput(GuiObject: GuiObject)
		InputHint_Mobile_GuiObjects[GuiObject] = true
		UpdateGuiObjectVisible(GuiObject)
	end

	local function RemoveInput(GuiObject: GuiObject)
		InputHint_Keyboard_GuiObjects[GuiObject] = nil
		InputHint_Xbox_GuiObjects[GuiObject] = nil
		InputHint_PlayStation_GuiObjects[GuiObject] = nil
		InputHint_Mobile_GuiObjects[GuiObject] = nil
	end

	Utility.TagToAddRemoveFunctions("Input_Keyboard", AddKeyboardInput, RemoveInput)
	Utility.TagToAddRemoveFunctions("Input_Xbox", AddXboxInput, RemoveInput)
	Utility.TagToAddRemoveFunctions("Input_PlayStation", AddPlayStationInput, RemoveInput)
	Utility.TagToAddRemoveFunctions("Input_Mobile", AddMobileInput, RemoveInput)
end

return InputController