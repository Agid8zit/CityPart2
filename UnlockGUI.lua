-- UnlockGUI/UnlockGui.lua
local UnlockGui = {}

-- Services
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Root & deps
local UI = script.Parent :: ScreenGui
local UtilityGUI = require(ReplicatedStorage.Scripts.UI.UtilityGUI)

-- Config
local MIN_OPEN_SEC      = 1.0
local MAX_ICONS         = 12          -- cap to avoid spam frames
local SPIN_A_DPS        = 80
local SPIN_B_DPS        = 50

-- State
local OpenTime          = 0
local SpinConn          : RBXScriptConnection? = nil
local ResizeConn        : RBXScriptConnection? = nil
local InputConn         : RBXScriptConnection? = nil
local TempFrames        : {Instance} = {}
local ActiveTweens      : {Tween} = {}
local Showing           = false
local Queue             : { {title:string, desc:string, models:{Instance}?} } = {}

-- UI refs (defensive fetch; don’t crash on nils)
local function ref(path : {Instance}, name : string)
	for _, inst in ipairs(path) do
		local f = inst:FindFirstChild(name)
		if f then return f end
	end
	return nil
end

local Root             = UI:FindFirstChild("UnlockedItem")
local UI_CloseBG       = UI:FindFirstChild("CloseBG")
local UI_UnlockName    = Root and Root:FindFirstChild("UnlockedName")
local UI_Description   = Root and Root:FindFirstChild("Description")
local UI_SpinA         = Root and Root:FindFirstChild("a")
local UI_SpinB         = Root and Root:FindFirstChild("b")
local IconArray        = Root and Root:FindFirstChild("IconArray")
local UI_ModelTemplate = IconArray and IconArray:FindFirstChild("ModelPreviewTemplate")
local UI_ListLayout    = IconArray and IconArray:FindFirstChild("UIListLayout")
local UnlockSound      = script:FindFirstChild("UnlockSound")

-- Cache default sizes safely
local DefaultSize = {
	Name        = UI_UnlockName and UI_UnlockName.Size or UDim2.fromScale(1, 0.2),
	Desc        = UI_Description and UI_Description.Size or UDim2.fromScale(1, 0.2),
	SpinA       = UI_SpinA and UI_SpinA.Size or UDim2.fromScale(0.1, 0.1),
	SpinB       = UI_SpinB and UI_SpinB.Size or UDim2.fromScale(0.1, 0.1),
}

-- Utils
local function stopTweens()
	for i = #ActiveTweens, 1, -1 do
		local t = ActiveTweens[i]
		pcall(function() t:Cancel() end)
		table.remove(ActiveTweens, i)
	end
end

local function destroyTempFrames()
	for i = #TempFrames, 1, -1 do
		local f = TempFrames[i]
		pcall(function() f:Destroy() end)
		table.remove(TempFrames, i)
	end
end

local function disconnectSignals()
	if SpinConn then SpinConn:Disconnect(); SpinConn = nil end
	if InputConn then InputConn:Disconnect(); InputConn = nil end
	-- Keep ResizeConn alive after Init (one shared listener), don’t kill it in OnHide.
end

local function pushTween(t: Tween)
	table.insert(ActiveTweens, t)
	t:Play()
end

local function updateListLayoutCenter()
	if not (UI_ListLayout and IconArray) then return end
	if UI_ListLayout.AbsoluteContentSize.X > IconArray.AbsoluteSize.X then
		UI_ListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	else
		UI_ListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	end
end

-- Queue driver
local function popNext()
	if Showing then return end
	local item = table.remove(Queue, 1)
	if not item then return end
	Showing = true
	UnlockGui._present(item.title, item.desc, item.models or {})
end

----------------------------------------------------------------------
-- Public: Init
----------------------------------------------------------------------
function UnlockGui.Init()
	-- Defensive defaults
	if UI_ModelTemplate then
		UI_ModelTemplate.Visible = false
	end

	-- Single viewport resize listener (idempotent)
	if not ResizeConn then
		ResizeConn = workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateListLayoutCenter)
	end

	-- Start hidden
	UI.Enabled = false
end

----------------------------------------------------------------------
-- Internal: render modal for one payload
----------------------------------------------------------------------
function UnlockGui._present(UnlockName: string, Description: string, Entries: {any})
	-- SFX (fire-and-forget)
	if UnlockSound then
		local sfx = UnlockSound:Clone()
		sfx.PlayOnRemove = true
		sfx.Parent = workspace:FindFirstChild("_Misc") or workspace
		sfx:Destroy()
	end

	-- Clear previous state
	stopTweens()
	destroyTempFrames()
	disconnectSignals()

	-- Icons
	if UI_ModelTemplate and IconArray then
		local count = 0
		for _, entry in ipairs(Entries) do
			if count >= MAX_ICONS then break end

			if typeof(entry) == "Instance" and entry:IsA("Model") then
				count += 1
				local vp = UI_ModelTemplate:Clone()
				vp.Visible = true

				local text = vp:FindFirstChild("TextLabel")
				if text then
					text.Text = entry.Name
					text.Parent = nil -- keep out during viewport setup
				end

				local ok2, cloned = pcall(function() return entry:Clone() end)
				if ok2 and cloned and UtilityGUI and UtilityGUI.SetupViewportFrameForModelWithAttributes then
					pcall(UtilityGUI.SetupViewportFrameForModelWithAttributes, vp, cloned)
				end
				if text then text.Parent = vp end

				vp.Parent = IconArray
				table.insert(TempFrames, vp)

			elseif type(entry) == "table" and type(entry.image) == "string" then
				count += 1
				-- flat image card for icon-only entries
				local imageCard = Instance.new("Frame")
				imageCard.Name = "IconCard"
				imageCard.BackgroundTransparency = 1
				imageCard.Size = UI_ModelTemplate.Size

				local img = Instance.new("ImageLabel")
				img.Name = "Icon"
				img.BackgroundTransparency = 1
				img.Size = UDim2.fromScale(1, 1)
				img.Image = entry.image
				img.Parent = imageCard

				if entry.label then
					local label = Instance.new("TextLabel")
					label.BackgroundTransparency = 1
					label.Size = UDim2.new(1, 0, 0, 18)
					label.AnchorPoint = Vector2.new(0.5, 1)
					label.Position = UDim2.fromScale(0.5, 1)
					label.Text = tostring(entry.label)
					label.TextScaled = true
					label.Parent = imageCard
				end

				imageCard.Parent = IconArray
				table.insert(TempFrames, imageCard)
			end
		end
	end

	updateListLayoutCenter()

	-- Texts
	if UI_UnlockName then UI_UnlockName.Text = UnlockName end
	if UI_Description then UI_Description.Text = Description end

	-- Defaults
	OpenTime = os.clock()
	if UI_CloseBG then UI_CloseBG.BackgroundTransparency = 1 end
	if UI_UnlockName then UI_UnlockName.Size = UDim2.fromScale(0, 0) end
	if UI_Description then UI_Description.Size = UDim2.fromScale(0, 0) end
	if UI_SpinA then UI_SpinA.Size = UDim2.fromScale(0, 0) end
	if UI_SpinB then UI_SpinB.Size = UDim2.fromScale(0, 0) end

	-- Show
	UI.Enabled = true

	-- Tweens
	if UI_CloseBG then
		pushTween(TweenService:Create(UI_CloseBG, TweenInfo.new(0.8), {
			BackgroundTransparency = 0.35
		}))
	end
	if UI_Description then
		pushTween(TweenService:Create(UI_Description, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0.3), {
			Size = DefaultSize.Desc
		}))
	end
	if UI_UnlockName then
		pushTween(TweenService:Create(UI_UnlockName, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0.3), {
			Size = DefaultSize.Name
		}))
	end
	if UI_SpinA then
		pushTween(TweenService:Create(UI_SpinA, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = DefaultSize.SpinA
		}))
	end
	if UI_SpinB then
		pushTween(TweenService:Create(UI_SpinB, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = DefaultSize.SpinB
		}))
	end

	-- Spin
	if not SpinConn and (UI_SpinA or UI_SpinB) then
		SpinConn = RunService.Heartbeat:Connect(function(dt)
			if UI_SpinA then UI_SpinA.Rotation += SPIN_A_DPS * dt end
			if UI_SpinB then UI_SpinB.Rotation += SPIN_B_DPS * dt end
		end)
	end

	-- Dismiss inputs after min time
	if not InputConn then
		InputConn = UserInputService.InputBegan:Connect(function(io, gpe)
			if gpe then return end
			local elapsed = os.clock() - OpenTime
			if elapsed < MIN_OPEN_SEC then return end
			if io.UserInputType == Enum.UserInputType.MouseButton1
				or io.KeyCode == Enum.KeyCode.Escape
				or io.KeyCode == Enum.KeyCode.ButtonB
			then
				UnlockGui.OnHide()
			end
		end)
	end
	-- Also allow clicking the dim background (if you have a button there)
	if UI_CloseBG and (UI_CloseBG:IsA("TextButton") or UI_CloseBG:IsA("ImageButton")) then
		UI_CloseBG.AutoButtonColor = false
		UI_CloseBG.MouseButton1Down:Connect(function()
			if (os.clock() - OpenTime) >= MIN_OPEN_SEC then
				UnlockGui.OnHide()
			end
		end)
	end
end

----------------------------------------------------------------------
-- Public: OnShow (queued)
----------------------------------------------------------------------
function UnlockGui.OnShow(UnlockName: string, Description: string, Entries: {any}?)
	table.insert(Queue, { title=tostring(UnlockName or "Unlocked"), desc=tostring(Description or ""), models = Entries or {} })
	task.defer(popNext)
end

----------------------------------------------------------------------
-- Public: OnHide
----------------------------------------------------------------------
function UnlockGui.OnHide()
	UI.Enabled = false
	stopTweens()
	destroyTempFrames()
	disconnectSignals()
	Showing = false
	-- show next, if any
	task.defer(popNext)
end

return UnlockGui
