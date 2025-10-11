local UtilityGUI = {}

-- Roblox Services
local TweenService = game:GetService("TweenService")

-- Constant Functions
local INSTANT_TWEEN = TweenInfo.new(0.0)

-- Module Functions
function UtilityGUI.AdjustScrollingFramePositionToLookAtAFrame(ScrollingFrame: ScrollingFrame, ChildFrame: GuiObject)
	-- Center scrolling frame to the selection
	local FramePosY = ChildFrame.AbsolutePosition.Y
	local FrameParent = ChildFrame.Parent
	local FramePosYRelative = FramePosY - FrameParent.AbsolutePosition.Y--UI_ScrollingFrame.Container.AbsolutePosition.Y
	local FramePosYRelativeCenter = FramePosYRelative + (ChildFrame.AbsoluteSize.Y / 2)

	local TargetPosY = FramePosYRelativeCenter - (ScrollingFrame.AbsoluteSize.Y / 2)

	ScrollingFrame.CanvasPosition = Vector2.new(0, TargetPosY)
end

function UtilityGUI.SetupViewportFrameForModelWithAttributes(ViewportFrame: ViewportFrame, Model: Model)
	-- Cleanup
	ViewportFrame:ClearAllChildren()

	-- Get all Properties
	local LightDirection = (Model:GetAttribute("lDir"))
	local Angles = (Model:GetAttribute("vpCam"))
	local Offset = (Model:GetAttribute("vpOffset")) or Vector3.zero
	local CameraZoom = (Model:GetAttribute("zoom"))
	assert(LightDirection, "Missing attribute lDir for Model ("..Model.Name..")")
	assert(Angles, "Missing attribute vpCam for Model ("..Model.Name..")")
	assert(CameraZoom, "Missing attribute zoom for Model ("..Model.Name..")")

	-- Create Camera
	local Camera = Instance.new("Camera")
	Camera.FieldOfView = 1
	Camera.CFrame = CFrame.fromEulerAnglesYXZ(Angles.X, Angles.Y, Angles.Z) * CFrame.new(0, 0, CameraZoom) + Offset
	Camera.Parent = ViewportFrame

	Model:PivotTo(Model:GetPivot().Rotation)
	Model.Parent = ViewportFrame

	-- Final Properties
	ViewportFrame.CurrentCamera = Camera
	ViewportFrame.LightDirection = LightDirection
end

function UtilityGUI.VisualMouseInteraction(ButtonObject: GuiButton, TargetObject: GuiObject | {}, NewTweenInfo: TweenInfo, OnHoverPropertyChanges: {}?, OnClickPropertChanges: {}?)
	-- Sanity
	assert(ButtonObject, "ButtonObject missing for UtilityGUI.VisualMouseInteraction")
	local TargetObjectSafe = nil
	if TargetObject == nil then
		TargetObjectSafe = ButtonObject
	elseif typeof(TargetObject) == "table" then
		for _, Child in TargetObject do
			UtilityGUI.VisualMouseInteraction(ButtonObject, Child, NewTweenInfo, OnHoverPropertyChanges, OnClickPropertChanges)
		end
		return
	else
		TargetObjectSafe = TargetObject
	end

	-- Write original properties for reference
	local OriginalProperties = {}
	if OnHoverPropertyChanges then
		for Key in OnHoverPropertyChanges do
			OriginalProperties[Key] = TargetObjectSafe[Key]
		end
	end
	if OnClickPropertChanges then
		for Key in OnClickPropertChanges do
			OriginalProperties[Key] = TargetObjectSafe[Key]
		end
	end



	-- Interaction Changes
	ButtonObject:GetPropertyChangedSignal("GuiState"):Connect(function()
		if not ButtonObject.Active then return end

		if ButtonObject.GuiState == Enum.GuiState.Hover then
			if OnHoverPropertyChanges then
				TweenService:Create(TargetObjectSafe, NewTweenInfo, OnHoverPropertyChanges):Play()
			else
				TweenService:Create(TargetObjectSafe, NewTweenInfo, OriginalProperties):Play()
			end

		elseif ButtonObject.GuiState == Enum.GuiState.Idle then
			--if UtilityGUI.IsMouseInFrame(ButtonObject) then -- Hack because it doesn't go back to Hover after clicking
			--	TweenService:Create(TargetObjectSafe, NewTweenInfo, OnHoverPropertyChanges):Play()
			--else
			TweenService:Create(TargetObjectSafe, NewTweenInfo, OriginalProperties):Play()
			--end

		elseif ButtonObject.GuiState == Enum.GuiState.Press then
			if OnClickPropertChanges then
				TweenService:Create(TargetObjectSafe, NewTweenInfo, OnClickPropertChanges):Play()
			else
				TweenService:Create(TargetObjectSafe, NewTweenInfo, OriginalProperties):Play()
			end
		end
	end)

	return function()
		TweenService:Create(TargetObjectSafe, INSTANT_TWEEN, OriginalProperties):Play()
	end
end

return UtilityGUI
