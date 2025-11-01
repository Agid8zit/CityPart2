-- PlayerGui/Notifications/Logic
-- Full module: receives server LangKey payloads and renders TextLabel notifications
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local NotificationGui = {}

-- === UI refs (strict, fail-fast) ===
local UI : ScreenGui               = script.Parent
local Arrow : GuiObject            = UI:WaitForChild("OnboardingArrow") :: GuiObject

local NotificationFrame : Frame    = UI:WaitForChild("notifications") :: Frame
local NotifTemplate : Instance     = NotificationFrame:WaitForChild("template")
local NotifCont : Frame            = NotifTemplate:WaitForChild("container") :: Frame
local NotificationStack : Frame    = NotifCont:WaitForChild("Notifications") :: Frame

-- Remote lookup (NotificationStack preferred; fallbacks allowed)
local Events : Folder              = ReplicatedStorage:WaitForChild("Events")
local RE     : Folder              = Events:WaitForChild("RemoteEvents")
local NotifyRE : RemoteEvent?      = RE:FindFirstChild("NotificationStack")
	or RE:FindFirstChild("PushNotification")
	or RE:FindFirstChild("Notify")

-- === internal state (arrow gating kept) ===
local _arrowAlive : boolean = false
local _arrowTask  : thread? = nil
local _arrowEnabled : boolean = false
local _remoteBound : boolean = false

-- ===== Client defaults: durations only (NO TEXT FALLBACKS) =====
-- We do NOT provide text here; localization owns strings via LangKey.
local NOTIFY_DEFAULTS : {[string]: {duration: number?}} = {
	["Cant overlap zones"]             = { duration = 4 },
	["Cant build on roads"]            = { duration = 4 },
	["Cant build on unique buildings"] = { duration = 4 },

	-- Optional: generic/system
	["Invalid player"]                 = { duration = 3 },
	["Invalid params"]                 = { duration = 3 },
	["No valid area"]                  = { duration = 3 },
	["Blocked"]                        = { duration = 3 },
}

-- ========= ARROW PUBLIC TOGGLES =========
function NotificationGui.EnableArrow()  _arrowEnabled = true end
function NotificationGui.DisableArrow()
	_arrowEnabled = false
	if Arrow then Arrow.Visible = false end
	_arrowAlive = false
end

-- ============== helpers ==============
local function _hardenLayering()
	UI.ResetOnSpawn = false
	UI.IgnoreGuiInset = true
	UI.ZIndexBehavior = Enum.ZIndexBehavior.Global
	if UI.DisplayOrder < 1000 then UI.DisplayOrder = 1000 end
	if Arrow and Arrow.ZIndex < 100 then Arrow.ZIndex = 100 end
end

local function _stopArrowLoop()
	_arrowAlive = false
	_arrowTask = nil
	pcall(function()
		TweenService:Create(Arrow, TweenInfo.new(0.01), { Position = Arrow.Position }):Play()
	end)
end

local function _ensureArrowVisible(visible: boolean)
	if not _arrowEnabled then
		if Arrow.Visible then Arrow.Visible = false end
		return
	end
	if Arrow.Visible ~= visible then
		Arrow.Visible = visible
	end
end

-- ============== lifecycle ==============
function NotificationGui.Init(_screenGui: ScreenGui?)
	_hardenLayering()
	if Arrow then Arrow.Visible = false end
	UI.Enabled = true
	NotificationGui.BindRemoteOnce() -- auto-wire server events
end

function NotificationGui.OnShow(_screenGui: ScreenGui?)
	_hardenLayering()
	UI.Enabled = true
end

function NotificationGui.OnHide(_screenGui: ScreenGui?)
	UI.Enabled = false
end

-- ============== public API (arrow) ==============
function NotificationGui.IsArrowVisible(): boolean
	return Arrow.Visible == true
end

function NotificationGui.ShowArrowBounce(posA, posB, sizeUD, rotationDeg)
	if not _arrowEnabled then
		_stopArrowLoop()
		if Arrow then Arrow.Visible = false end
		return
	end
	_stopArrowLoop()
	_hardenLayering()
	UI.Enabled = true
	Arrow.Visible = true
	Arrow.Position = posA
	Arrow.Size = sizeUD
	Arrow.Rotation = rotationDeg or 0
	_arrowAlive = true

	task.spawn(function()
		while _arrowAlive do
			local tweenOut = TweenService:Create(Arrow, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = posB})
			tweenOut:Play(); tweenOut.Completed:Wait()
			if not _arrowAlive then break end
			local tweenBack = TweenService:Create(Arrow, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = posA})
			tweenBack:Play(); tweenBack.Completed:Wait()
		end
	end)
end

function NotificationGui.ShowArrowAt(target: GuiObject, offset: UDim2?)
	if not _arrowEnabled then
		_stopArrowLoop()
		if Arrow then Arrow.Visible = false end
		return false
	end
	if not (target and target:IsA("GuiObject") and target.Parent) then
		return false
	end
	_stopArrowLoop()
	_hardenLayering()
	UI.Enabled = true
	_ensureArrowVisible(true)

	-- Default look if not set
	if Arrow.Size.X.Scale == 0 and Arrow.Size.Y.Scale == 0 and Arrow.Size.X.Offset == 0 and Arrow.Size.Y.Offset == 0 then
		Arrow.Size = UDim2.new(0.053, 0, 0.1, 0)
	end
	if Arrow.Rotation == 0 then Arrow.Rotation = 180 end

	-- Screen-space center of target
	local center = target.AbsolutePosition + target.AbsoluteSize/2
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
	local rel = UDim2.new(center.X / math.max(vp.X, 1), 0, center.Y / math.max(vp.Y, 1), 0)
	Arrow.Position = rel + (offset or UDim2.new(0, 0, -0.12, 0))
	return true
end

function NotificationGui.HideArrow()
	_stopArrowLoop()
	_ensureArrowVisible(false)
end

-- Find the primary TextLabel under a cloned notification node
local function _getNotifLabel(node: Instance): TextLabel?
	if node:IsA("TextLabel") then
		return node
	end
	return node:FindFirstChildWhichIsA("TextLabel", true)
end

-- ============== notification helpers (client-owned duration, LangKey for text) ==============
local function _cloneTemplateWithTextAndLangKey(text: string?, langKey: string, duration: number?)
	local node = NotifTemplate:Clone()
	node.Visible = true
	node.Parent = NotificationStack  -- parent first (some templates mutate on Parent)

	-- Only touch the TextLabel
	local label = _getNotifLabel(node)
	if label then
		label:SetAttribute("LangKey", langKey or "Unknown")
		-- IMPORTANT: only set Text when the server explicitly provides it
		-- nil means “let the localization system fill from LangKey”
		if text ~= nil then
			label.Text = text
		end
	end

	-- fade & remove
	local dur = duration or 4
	task.delay(dur, function()
		if not node or not node.Parent then return end
		local tws = {}
		local function pushTween(inst, props)
			local ok, tw = pcall(function()
				return TweenService:Create(inst, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
			end)
			if ok and tw then table.insert(tws, tw); tw:Play() end
		end

		if label then
			pushTween(label, { TextTransparency = 1, BackgroundTransparency = 1 })
		end
		for _, child in ipairs(node:GetDescendants()) do
			if child:IsA("ImageLabel") or child:IsA("ImageButton") then
				pushTween(child, { ImageTransparency = 1, BackgroundTransparency = 1 })
			elseif child:IsA("Frame") then
				pushTween(child, { BackgroundTransparency = 1 })
			end
		end

		for _, tw in ipairs(tws) do tw.Completed:Wait() end
		if node and node.Parent then node:Destroy() end
	end)
end

function NotificationGui.ShowLangKey(langKey: string, opts: { text: string?, duration: number? }?)
	-- If opts.text is provided, we respect it; otherwise we let LangKey drive text.
	local d = (NOTIFY_DEFAULTS[langKey] and NOTIFY_DEFAULTS[langKey].duration) or 4
	local duration = (opts and opts.duration) or d
	local text = (opts and opts.text) -- could be nil (preferred) or explicit string override
	_cloneTemplateWithTextAndLangKey(text, langKey, duration)
end

-- Wire to server RemoteEvent once
function NotificationGui.BindRemoteOnce()
	if _remoteBound then return end
	_remoteBound = true

	if not NotifyRE then
		warn("[NotificationGui] No Notification RemoteEvent found (NotificationStack/PushNotification/Notify).")
		return
	end

	NotifyRE.OnClientEvent:Connect(function(payload)
		local key, txt, dur
		if typeof(payload) == "string" then
			key = payload
		elseif typeof(payload) == "table" then
			key = payload.LangKey or payload.Key or payload.Code
			txt = payload.Text -- only use if server sends an explicit override
			dur = payload.Duration
		end
		if not key or key == "" then key = "Unknown" end
		local duration = dur or (NOTIFY_DEFAULTS[key] and NOTIFY_DEFAULTS[key].duration) or 4

		-- CRITICAL: do NOT fall back to any client text here.
		-- Pass nil if no explicit txt -> Localizer will resolve from LangKey.
		_cloneTemplateWithTextAndLangKey(txt, key, duration)
	end)
end

-- Legacy helpers (still available)
function NotificationGui.ShowHint(text: string)
	if not text or text == "" then return end
	_cloneTemplateWithTextAndLangKey(text, "LegacyHint", 4)
end

function NotificationGui.ClearHints()
	for _, child in ipairs(NotificationStack:GetChildren()) do
		if child ~= NotifTemplate then
			child:Destroy()
		end
	end
end

return NotificationGui
