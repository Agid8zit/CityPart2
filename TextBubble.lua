local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

---------------------------------------------------------------------
-- Config (offset only; everything else comes from your template)
---------------------------------------------------------------------
local OFFSET = Vector3.new(0, 6, 0)   -- vertical offset above civ

-- Reading speed config
local WORDS_PER_MINUTE = 230
local MIN_HOLD_SECONDS = 2.5          -- floor so short lines don't vanish
local FADE_IN_SECONDS  = 0.25
local FADE_OUT_SECONDS = 0.35

---------------------------------------------------------------------
-- Template lookup (error fast if missing)
---------------------------------------------------------------------
local AlarmsFolder = ReplicatedStorage:WaitForChild("FuncTestGroundRS"):WaitForChild("Alarms")
local TextDialogTemplate = AlarmsFolder:WaitForChild("TextDialog")  -- MUST exist and contain Attachment -> BillboardGui -> MainFrame -> TextLabel

---------------------------------------------------------------------
-- Optional external control: update text via BindableEvent
-- Fire with: UpdateTextDialog:Fire(targetModelOrName, "New line of text")
---------------------------------------------------------------------
local EventsFolder   = ReplicatedStorage:FindFirstChild("Events") or Instance.new("Folder", ReplicatedStorage)
EventsFolder.Name    = "Events"
local BindableEvents = EventsFolder:FindFirstChild("BindableEvents") or Instance.new("Folder", EventsFolder)
BindableEvents.Name  = "BindableEvents"

local UpdateTextDialog = BindableEvents:FindFirstChild("UpdateTextDialog") or Instance.new("BindableEvent", BindableEvents)
UpdateTextDialog.Name  = "UpdateTextDialog"

local RequestRandomBubbleLine = BindableEvents:FindFirstChild("RequestRandomBubbleLine")
	or Instance.new("BindableEvent", BindableEvents)
RequestRandomBubbleLine.Name = "RequestRandomBubbleLine"

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function findAnchor(model: Model): BasePart?
	-- Prefer Head if present
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then return head end

	-- Then HRP
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then return hrp end

	-- Then PrimaryPart
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then return model.PrimaryPart end

	-- Fallback to any BasePart
	return model:FindFirstChildWhichIsA("BasePart")
end

local function isCiv(model: Instance): boolean
	return model
		and model:IsA("Model")
		and model:GetAttribute("CivAlive") == true
		and (model:GetAttribute("OwnerUserId") ~= nil)
end

local function getBillboard(root: Instance): BillboardGui?
	local att = root:FindFirstChild("Attachment")
	if not (att and att:IsA("Attachment")) then return nil end
	local bb = att:FindFirstChild("BillboardGui")
	if bb and bb:IsA("BillboardGui") then
		bb.Adornee = att
		bb.Enabled = true -- ensure it can render
	end
	return (bb and bb:IsA("BillboardGui")) and bb or nil
end

local function getTextLabel(root: Instance): TextLabel?
	local bb = getBillboard(root)
	if not bb then return nil end
	-- Robust: search recursively anywhere under the BillboardGui
	local tl = bb:FindFirstChildWhichIsA("TextLabel", true)
	return tl
end

-- Walk all GuiObjects under the billboard so we can fade everything coherently
local function collectGuiObjectsForFade(root: Instance): {GuiObject}
	local list = {}
	local bb = getBillboard(root)
	if not bb then return list end
	for _, d in ipairs(bb:GetDescendants()) do
		if d:IsA("GuiObject") then
			table.insert(list, d)
		end
	end
	return list
end

-- Apply an alpha to all supported transparency channels
local function setGuiAlpha(guiList: {GuiObject}, alpha: number)
	for _, obj in ipairs(guiList) do
		-- Background
		if obj.BackgroundTransparency ~= nil then
			obj.BackgroundTransparency = math.clamp(alpha, 0, 1)
		end
		-- Text
		if obj:IsA("TextLabel") or obj:IsA("TextButton") then
			if obj.TextTransparency ~= nil then
				obj.TextTransparency = math.clamp(alpha, 0, 1)
			end
			if obj.TextStrokeTransparency ~= nil then
				-- keep stroke slightly less opaque than text during fade-in, but still track alpha
				obj.TextStrokeTransparency = math.clamp(math.min(1, alpha + 0.15), 0, 1)
			end
		end
		-- Image
		if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
			if obj.ImageTransparency ~= nil then
				obj.ImageTransparency = math.clamp(alpha, 0, 1)
			end
		end
	end
end

-- Tween alpha for all relevant GuiObjects at once; returns active tween list
local function tweenGuiAlpha(guiList: {GuiObject}, fromAlpha: number, toAlpha: number, duration: number): {Tween}
	if duration <= 0 then
		setGuiAlpha(guiList, toAlpha)
		return {}
	end
	-- We tween a NumberValue and bind Changed to update all children—prevents dozens of individual tweens.
	local driver = Instance.new("NumberValue")
	driver.Value = fromAlpha
	local tweens = {}
	local ti = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tw = TweenService:Create(driver, ti, { Value = toAlpha })
	driver.Changed:Connect(function(v)
		setGuiAlpha(guiList, v)
	end)
	tw.Completed:Connect(function()
		driver:Destroy()
	end)
	tw:Play()
	table.insert(tweens, tw)
	return tweens
end

-- NEW: search a plot recursively for a civ model by name
local function findCivByNameInPlot(plot: Instance, name: string): Model?
	for _, inst in ipairs(plot:GetDescendants()) do
		if inst:IsA("Model") and inst.Name == name and isCiv(inst) then
			return inst
		end
	end
	return nil
end

-- NEW: search all plots recursively for a civ model by name
local function findCivByNameAllPlots(name: string): Model?
	local pp = Workspace:FindFirstChild("PlayerPlots")
	if not pp then return nil end
	for _, plot in ipairs(pp:GetChildren()) do
		local m = findCivByNameInPlot(plot, name)
		if m then return m end
	end
	return nil
end

---------------------------------------------------------------------
-- Core: ensure a civ has a following TextDialog cloned from template
---------------------------------------------------------------------
local function ensureTextDialogOn(model: Model)
	-- Reuse if already present
	if model:FindFirstChild("TextDialog") then return end

	local anchor = findAnchor(model)
	if not anchor then
		-- Wait for a BasePart to appear, then retry once
		local con; con = model.DescendantAdded:Connect(function(desc)
			if desc:IsA("BasePart") then
				con:Disconnect()
				ensureTextDialogOn(model)
			end
		end)
		return
	end

	-- Clone template (Part with Attachment -> BillboardGui -> MainFrame -> TextLabel)
	local clone = TextDialogTemplate:Clone()
	clone.Name = "TextDialog"
	clone.Parent = model

	-- Weld to anchor so it follows the civ; position via Attachment offset
	clone.Anchored = false
	clone.Massless = true
	clone.CanCollide = false
	clone.CanQuery  = false
	clone.CanTouch  = false

	clone.CFrame = anchor.CFrame -- put it on the anchor; offset comes from Attachment

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = clone
	weld.Part1 = anchor
	weld.Parent = clone

	-- Set the Attachment offset to lift the dialog to the desired height
	local att = clone:FindFirstChild("Attachment")
	if att and att:IsA("Attachment") then
		att.Position = OFFSET
		-- ensure BillboardGui adorns this attachment (explicitly set, though it usually auto-adorns)
		local bb = att:FindFirstChild("BillboardGui")
		if bb and bb:IsA("BillboardGui") then
			bb.Adornee = att
			bb.Enabled = true
		end
	end
	RequestRandomBubbleLine:Fire(model)
end

---------------------------------------------------------------------
-- Text animation state
---------------------------------------------------------------------
-- Per-model sequence number so a newer line cancels older animations.
local ActiveSeq = setmetatable({}, { __mode = "k" }) -- weak keys so models can GC

local function words_in(s: string): number
	local n = 0
	for _ in string.gmatch(s, "%S+") do n += 1 end
	return n
end

local function compute_hold_seconds(text: string): number
	local w = words_in(text)
	local seconds = (w / WORDS_PER_MINUTE) * 60.0
	if seconds < MIN_HOLD_SECONDS then seconds = MIN_HOLD_SECONDS end
	return seconds
end

local function show_then_fade(model: Model, root: Instance, text: string)
	-- bump sequence
	local seq = (ActiveSeq[model] or 0) + 1
	ActiveSeq[model] = seq

	-- Collect gui objects for fading
	local guiList = collectGuiObjectsForFade(root)
	-- Start hidden
	setGuiAlpha(guiList, 1.0)

	-- Fade in
	local fadeInTweens = tweenGuiAlpha(guiList, 1.0, 0.0, FADE_IN_SECONDS)

	-- Hold for reading time
	local holdSeconds = compute_hold_seconds(text)

	task.spawn(function()
		-- Wait fade in + hold
		task.wait(FADE_IN_SECONDS + holdSeconds)
		-- If a newer line arrived, abort
		if ActiveSeq[model] ~= seq then return end
		-- Fade out
		tweenGuiAlpha(guiList, 0.0, 1.0, FADE_OUT_SECONDS)
	end)
end

---------------------------------------------------------------------
-- Text update API
---------------------------------------------------------------------
local function setDialogText(target: Instance | string, newText: string)
	if typeof(newText) ~= "string" then return end

	local model: Model?
	if typeof(target) == "Instance" and target:IsA("Model") then
		model = target
	elseif typeof(target) == "string" then
		-- CHANGED: search recursively across all plots
		model = findCivByNameAllPlots(target)
	end
	if not model or not model.Parent then return end

	-- Make sure it has a TextDialog first
	ensureTextDialogOn(model)
	local root = model:FindFirstChild("TextDialog")
	if not root then return end

	-- Set the text
	local label = getTextLabel(root)
	if label then
		label.Text = newText
	end

	-- Animate bubble: fade-in, hold (based on 230 WPM), fade-out
	show_then_fade(model, root, newText)
end

UpdateTextDialog.Event:Connect(setDialogText)

---------------------------------------------------------------------
-- Plot monitoring: attach on existing and future civilians
---------------------------------------------------------------------
local function attachToExisting(plot: Instance)
	for _, inst in ipairs(plot:GetDescendants()) do
		if inst:IsA("Model") and isCiv(inst) then
			ensureTextDialogOn(inst)
			RequestRandomBubbleLine:Fire(inst)  -- NEW: seed immediately even if TextDialog already existed
		end
	end
end

local function monitorPlot(plot: Instance)
	attachToExisting(plot)

	-- CHANGED: DescendantAdded to catch civs spawned under nested folders
	plot.DescendantAdded:Connect(function(inst)
		if inst:IsA("Model") then
			-- give attributes a tick to appear
			RunService.Heartbeat:Wait()
			if isCiv(inst) then
				ensureTextDialogOn(inst)
			end
		end
	end)
end

local function initPlotsWatcher()
	local pp = Workspace:FindFirstChild("PlayerPlots")
	if not pp then
		local con; con = Workspace.ChildAdded:Connect(function(ch)
			if ch.Name == "PlayerPlots" then
				con:Disconnect()
				initPlotsWatcher()
			end
		end)
		return
	end
	for _, plot in ipairs(pp:GetChildren()) do
		if plot:IsA("Folder") or plot:IsA("Model") then
			monitorPlot(plot)
		end
	end
	pp.ChildAdded:Connect(function(plot)
		if plot:IsA("Folder") or plot:IsA("Model") then
			monitorPlot(plot)
		end
	end)
end

-- Boot
initPlotsWatcher()
