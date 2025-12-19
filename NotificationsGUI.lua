-- PlayerGui/Notifications/Logic.lua
-- Notifications with first-frame localization, world-ready gating, and hard singleton (one-at-a-time).
-- Prefers ReplicatedStorage.Localization.Localizing and prefers localization over server text.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui        = game:GetService("StarterGui")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local RunServiceScheduler = require(ReplicatedStorage.Scripts.RunServiceScheduler)
local LocalPlayer = Players.LocalPlayer

local UI = script.Parent
local notifFr = UI:WaitForChild("notifications")
local tempFr = notifFr:WaitForChild("template")
local contFr = tempFr:WaitForChild("container")
local dropshadow : ImageLabel = contFr:WaitForChild("dropshadow")

-- Ensure template's dropshadow default style: Template never renders its own shadow (clones will).
pcall(function()
	dropshadow.ImageTransparency = 1
	dropshadow.Visible = false
end)

local Notification = {}

-- ===== behavior/config =====
local DEFAULT_DUR = 4
local DURATION_BY_KEY = {
	["Cant overlap zones"]             = 2,
	["Cant build on roads"]            = 2,
	["Cant build on unique buildings"] = 2,
	["Invalid player"]                 = 2,
	["Invalid params"]                 = 2,
	["No valid area"]                  = 2,
	["Blocked"]                        = 2,
}

-- Force everything through a single channel so only one toast is ever visible.
local ENFORCE_SINGLETON       = true
local DEFAULT_CHANNEL         = "global"
-- Prefer localization over server-provided Text unless payload.ForceText == true
local PREFER_LOCALIZATION     = true
-- Ignore duplicate keys that arrive within this window (seconds)
local COALESCE_WINDOW_SECONDS = 0.8
local COALESCE_WINDOW_BY_KEY = {
	["Cant overlap zones"]             = 0,
	["Cant build on roads"]            = 0,
	["Cant build on unique buildings"] = 0,
}
-- Candidate BoolValue names we treat as "world ready" gates (false = pause/queue, true = show)
local READY_FLAG_NAMES = { "WorldReady", "CityReady", "WorldLoaded", "Loaded", "IsLoaded", "IsReady" }
-- Grace period after reload before showing notifications
local RELOAD_GRACE_SECONDS = 3.0

-- ===== state =====
local UI        -- ScreenGui
local Stack     -- Frame
local Template  -- Frame

local BoundRemotes = {}   -- [Instance] = true
local _tok         = {}   -- channel tokens for dedupe/timer control

-- Localization wiring
local _language   -- string?
local _dialect    -- string?
local _loaderMod  -- ModuleScript? (the module we adopted)
local _loaderTbl  -- table?      (require(_loaderMod))
local _resolveFn  -- function?   (optional external resolver)

-- Ready/queue state
local _readyValue   -- BoolValue?
local _paused       = false -- if true: queue incoming toasts
local _pending      = nil   -- last pending toast while paused {channel, key, opts}
local _lastKeyAt    = {}    -- key -> wall-clock timestamp (seconds) for coalescing
local _worldReloadCooldown = false -- block toasts during/just-after reload

-- Active singleton node
local _singletonNode  -- Frame?
local _currentChannel = DEFAULT_CHANNEL

-- Init guard
local _didInit = false

-- Forward decl for ordering
local hideAndClearSingleton

-- ===== utils =====
local function hardenUI()
	UI.ResetOnSpawn    = false
	UI.IgnoreGuiInset  = true
	UI.ZIndexBehavior  = Enum.ZIndexBehavior.Global
	if UI.DisplayOrder < 1000 then UI.DisplayOrder = 1000 end
end

local function getPreferredLabel(node: Instance)
	local named = node:FindFirstChild("Notifications", true)
	if named and named:IsA("TextLabel") then return named end
	return node:FindFirstChildWhichIsA("TextLabel", true)
end

-- Only make alpha visible for non-shadow images; shadow is managed explicitly to avoid pre-show flicker.
local function makeAlphaVisibleOnly(root: Instance)
	for _, obj in ipairs(root:GetDescendants()) do
		if obj:IsA("TextLabel") or obj:IsA("TextButton") then
			obj.TextTransparency = 0
		elseif obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
			if obj.Name ~= "dropshadow" then
				obj.ImageTransparency = 0
			end
		end
	end
end

-- Ensure all content floats above the drop shadow.
local function raiseZIndex(root: Instance, base: number)
	for _, obj in ipairs(root:GetDescendants()) do
		if obj:IsA("GuiObject") and obj.ZIndex < base then
			obj.ZIndex = base
		end
	end
end

-- keep drop shadow behind content regardless of layout changes (no visibility/alpha change here)
local function enforceShadowZ(root: Instance, baseForContent: number)
	local container = root:FindFirstChild("container", true)
	if not container then return end
	local shadow = container:FindFirstChild("dropshadow")
	if shadow and shadow:IsA("GuiObject") then
		shadow.ZIndex = math.max(0, baseForContent - 1)
	end
end

local function ensureRichTextIfNeeded(label: TextLabel, text: string)
	if string.find(text, "<[^>]+>") then
		label.RichText = true
		if not label.TextFits then label.TextFits = label.TextFits end
	end
end

local function resetToastVisualState(node: Instance?)
	if not node then return end
	if node:IsA("GuiObject") then
		node.Visible = true
		node.BackgroundTransparency = node.BackgroundTransparency
	end
	for _, obj in ipairs(node:GetDescendants()) do
		if obj:IsA("TextLabel") or obj:IsA("TextButton") then
			obj.TextTransparency = 0
			obj.Visible = true
		elseif obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
			if obj.Name ~= "dropshadow" then
				obj.ImageTransparency = 0
				obj.Visible = true
			else
				obj.ImageTransparency = 0.3
				obj.Visible = true
			end
		end
	end
end

local function tweenOutAndDestroy(node: Instance, dur: number?)
	if not (node and node.Parent) then return end
	local tws = {}

	local function pushTween(inst: Instance, props)
		local ok, tw = pcall(function()
			return TweenService:Create(inst, TweenInfo.new(dur or 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
		end)
		if ok and tw then
			table.insert(tws, tw)
			tw:Play()
		end
	end

	local mainLabel = getPreferredLabel(node)
	if mainLabel then
		pushTween(mainLabel, { TextTransparency = 1 })
	end
	for _, child in ipairs(node:GetDescendants()) do
		if child:IsA("ImageLabel") or child:IsA("ImageButton") then
			pushTween(child, { ImageTransparency = 1 })
			-- kill the shadow immediately to avoid 1-frame ghosting during fade
			if child.Name == "dropshadow" then
				child.Visible = false
			end
		elseif child:IsA("TextLabel") and child ~= mainLabel then
			pushTween(child, { TextTransparency = 1 })
		end
	end
	-- Also hide the node to prevent any late-frame blips while tweens complete
	if node:IsA("GuiObject") then
		node.Visible = false
	end
	for _, tw in ipairs(tws) do
		tw.Completed:Wait()
	end
	if node and node.Parent then node:Destroy() end
end

local function ensureLayout()
	if not Stack then return end
	if not Stack:FindFirstChildOfClass("UIListLayout") then
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding   = UDim.new(0, 6)
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		layout.VerticalAlignment   = Enum.VerticalAlignment.Bottom
		layout.Parent = Stack
	end
end

-- ===== Loader discovery/injection =====
local CANDIDATE_NAMES = {
	["Localizing"] = true,
	["Loader"] = true, ["Localizer"] = true, ["LanguageLoader"] = true,
	["Localization"] = true, ["Strings"] = true, ["i18n"] = true,
}

local function safeRequire(mod: ModuleScript)
	local ok, res = pcall(require, mod)
	if not ok then
		warn("[Notifications] Loader require failed for:", mod:GetFullName(), res)
		return nil
	end
	return res
end

local function hasLanguagesSiblingOrChild(mod: ModuleScript)
	local p = mod.Parent
	if p and p:FindFirstChild("Languages") then return true end
	if mod:FindFirstChild("Languages") then return true end
	return false
end

local function isGoodLoader(mod: ModuleScript)
	local tbl = safeRequire(mod)
	if type(tbl) ~= "table" or type(tbl.get) ~= "function" then
		return nil
	end
	return tbl
end

local function collectCandidatesFrom(root: Instance, bag: {ModuleScript})
	local stack = { root }
	while #stack > 0 do
		local cur = table.remove(stack)
		if cur:IsA("ModuleScript") and CANDIDATE_NAMES[cur.Name] then
			table.insert(bag, cur)
		end
		for _, ch in ipairs(cur:GetChildren()) do
			table.insert(stack, ch)
		end
	end
end

local function discoverLoader()
	-- 0) Explicit: ReplicatedStorage.Localization.Localizing
	local rs = ReplicatedStorage
	if rs then
		local locFolder = rs:FindFirstChild("Localization")
		if locFolder and locFolder:IsA("Folder") then
			local localizing = locFolder:FindFirstChild("Localizing")
			if localizing and localizing:IsA("ModuleScript") then
				if hasLanguagesSiblingOrChild(localizing) then
					local tbl = isGoodLoader(localizing)
					if tbl then
						_loaderMod = localizing
						_loaderTbl = tbl
						print(("[Notifications] Using Loader at %s"):format(localizing:GetFullName()))
						return
					end
				end
			end
		end
	end

	-- 1) Conventional fallbacks
	local conventional = {}
	if rs then
		local loc = rs:FindFirstChild("Localization")
		if loc and loc:IsA("Folder") then
			local m = loc:FindFirstChild("Loader")
			if m and m:IsA("ModuleScript") then table.insert(conventional, m) end
		end
		local scripts = rs:FindFirstChild("Scripts")
		if scripts and scripts:IsA("Folder") then
			local loc2 = scripts:FindFirstChild("Localization")
			if loc2 and loc2:IsA("Folder") then
				local m2 = loc2:FindFirstChild("Loader")
				if m2 and m2:IsA("ModuleScript") then table.insert(conventional, m2) end
			end
		end
	end

	for _, mod in ipairs(conventional) do
		if hasLanguagesSiblingOrChild(mod) then
			local tbl = isGoodLoader(mod)
			if tbl then
				_loaderMod = mod
				_loaderTbl = tbl
				print(("[Notifications] Using Loader at %s"):format(mod:GetFullName()))
				return
			end
		end
	end

	-- 2) broader search
	local candidates = {}
	if rs then collectCandidatesFrom(rs, candidates) end
	collectCandidatesFrom(StarterGui, candidates)
	if UI then collectCandidatesFrom(UI, candidates) end
	if LocalPlayer then
		local pg = LocalPlayer:FindFirstChild("PlayerGui")
		if pg then collectCandidatesFrom(pg, candidates) end
	end

	-- 3) Prefer those with a "Languages" folder
	local withLangs, others = {}, {}
	for _, mod in ipairs(candidates) do
		if hasLanguagesSiblingOrChild(mod) then
			table.insert(withLangs, mod)
		else
			table.insert(others, mod)
		end
	end
	local ordered = {}
	for _, m in ipairs(withLangs) do table.insert(ordered, m) end
	for _, m in ipairs(others)    do table.insert(ordered, m) end

	for _, mod in ipairs(ordered) do
		local tbl = isGoodLoader(mod)
		if tbl then
			_loaderMod = mod
			_loaderTbl = tbl
			print(("[Notifications] Using Loader at %s"):format(mod:GetFullName()))
			return
		end
	end
end

function Notification.SetLoader(loaderModuleScript: ModuleScript)
	if typeof(loaderModuleScript) ~= "Instance" or not loaderModuleScript:IsA("ModuleScript") then
		warn("[Notifications] SetLoader expected a ModuleScript.")
		return
	end
	local tbl = isGoodLoader(loaderModuleScript)
	if not tbl then
		warn("[Notifications] SetLoader: module did not return a table with .get")
		return
	end
	_loaderMod = loaderModuleScript
	_loaderTbl = tbl
	print(("[Notifications] Using Loader at %s (SetLoader)"):format(loaderModuleScript:GetFullName()))
end

-- ===== language wiring =====
local function adoptLanguageFromAttribute()
	local langAttr = LocalPlayer and LocalPlayer:GetAttribute("Language")
	if type(langAttr) == "string" and langAttr ~= "" then
		_language = langAttr
	end
end

local function reResolveVisibleIfAny()
	if not _singletonNode then return end
	local label = getPreferredLabel(_singletonNode)
	if not label then return end
	local langKey = label:GetAttribute("LangKey")
	if not langKey or langKey == "" then return end

	local resolved
	if _resolveFn then
		local ok, val = pcall(_resolveFn, langKey)
		if ok and type(val) == "string" and val ~= "" then
			resolved = val
		end
	end
	if not resolved then
		if not _loaderTbl then discoverLoader() end
		if _loaderTbl and type(_loaderTbl.get) == "function" then
			local ok, val = pcall(_loaderTbl.get, langKey, _language, _dialect)
			if ok and type(val) == "string" and val ~= "" then
				resolved = val
			end
		end
	end
	if not resolved then resolved = langKey end
	label.Text = resolved
	ensureRichTextIfNeeded(label, resolved)
end

local function hookLanguageAttribute()
	if not LocalPlayer then return end
	adoptLanguageFromAttribute()
	LocalPlayer:GetAttributeChangedSignal("Language"):Connect(function()
		local prev = _language
		adoptLanguageFromAttribute()
		if _language ~= prev then
			reResolveVisibleIfAny()
		end
	end)
end

-- ===== ready gate / queue =====
local function tryAutoFindReadyFlag(): BoolValue?
	local roots = {
		ReplicatedStorage,
		ReplicatedStorage:FindFirstChild("State"),
		workspace,
		LocalPlayer,
		UI,
	}
	for _, root in ipairs(roots) do
		if typeof(root) == "Instance" and root ~= nil then
			for _, name in ipairs(READY_FLAG_NAMES) do
				local v = root:FindFirstChild(name)
				if v and v:IsA("BoolValue") then
					return v
				end
			end
		end
	end
	return nil
end

-- helper: flush any queued toast
local function _flushPending()
	if _pending then
		local p = _pending
		_pending = nil
		Notification.ShowSingleton(p.channel or DEFAULT_CHANNEL, p.key, p.opts)
	end
end

-- hook world reload begin/end to block and then release notifications
local function hookWorldReloadSignals()
	local events = ReplicatedStorage:FindFirstChild("Events")
	if not events then return end
	local be = events:FindFirstChild("BindableEvents")
	if not be then return end

	local beginBE = be:FindFirstChild("WorldReloadBegin")
	local endBE   = be:FindFirstChild("WorldReloadEnd")

	if beginBE and beginBE:IsA("BindableEvent") then
		beginBE.Event:Connect(function()
			_worldReloadCooldown = true
			-- hide any currently visible toast during reload window
			hideAndClearSingleton()
		end)
	end

	if endBE and endBE:IsA("BindableEvent") then
		endBE.Event:Connect(function()
			-- small grace before allowing toasts
			task.delay(RELOAD_GRACE_SECONDS, function()
				_worldReloadCooldown = false
				_flushPending()
			end)
		end)
	end
end

local function isReadyNow()
	if _paused then return false end
	if _worldReloadCooldown then return false end
	if _readyValue and _readyValue:IsA("BoolValue") then
		return _readyValue.Value == true
	end
	-- If we have no explicit gate, be conservative: treat as ready once game is loaded
	return game:IsLoaded()
end

local function setPaused(paused: boolean)
	_paused = paused and true or false
	if not _paused and not _worldReloadCooldown then
		_flushPending()
	end
end

-- Expose a public hook in case you want to drive the gate externally.
function Notification.SetReadySource(obj)
	-- obj may be BoolValue OR a function that returns boolean
	if typeof(obj) == "Instance" and obj:IsA("BoolValue") then
		_readyValue = obj
		setPaused(not _readyValue.Value)
		_readyValue.Changed:Connect(function()
			setPaused(not _readyValue.Value)
		end)
	elseif type(obj) == "function" then
		_readyValue = nil
		-- poll function lightly on heartbeat; pause when false
		RunServiceScheduler.onRenderStepped(function()
			local ok, val = pcall(obj)
			if ok then
				setPaused(not (val and true or false))
			end
		end)
	end
end

-- ===== resolve text =====
local function resolveNow(langKey: string)
	-- Optional external resolver
	if _resolveFn then
		local ok, val = pcall(_resolveFn, langKey)
		if ok and type(val) == "string" and val ~= "" then return val end
	end

	-- Lazy discovery if needed
	if not _loaderTbl then
		discoverLoader()
	end

	if _loaderTbl and type(_loaderTbl.get) == "function" then
		local ok, val = pcall(_loaderTbl.get, langKey, _language, _dialect)
		if ok and type(val) == "string" and val ~= "" then return val end
	end

	return nil
end

-- ===== singleton plumbing =====

-- Hard cleanup pass to prevent "thousands of templates" from accumulating when re-Init happens.
local function _purgeStrayTemplates()
	if not Stack or not Template then return end
	for _, child in ipairs(Stack:GetChildren()) do
		if child ~= Template then
			if child.Name == "template" or child.Name == "Template" or child:GetAttribute("IsToast") == true then
				pcall(function() child:Destroy() end)
			end
		end
	end
	_singletonNode = nil
end

-- Find an existing toast for the current channel if one exists
local function _findExistingToastForChannel(channel: string)
	for _, child in ipairs(Stack:GetChildren()) do
		if child ~= Template and child:GetAttribute("SingletonChannel") == channel and child:GetAttribute("IsToast") == true then
			return child
		end
	end
	return nil
end

local function ensureSingletonNode()
	-- Reuse existing toast for this channel if present
	local existing = _findExistingToastForChannel(_currentChannel)
	if existing and existing.Parent then
		enforceShadowZ(existing, 1001)
		_singletonNode = existing
		return existing
	end

	-- Reuse live reference if valid
	if _singletonNode and _singletonNode.Parent then
		enforceShadowZ(_singletonNode, 1001)
		return _singletonNode
	end

	-- Clone a fresh toast from Template
	local node = Template:Clone()
	node.Name = "toast"
	node.Visible = true
	node.Parent  = Stack
	node:SetAttribute("SingletonChannel", _currentChannel)
	node:SetAttribute("IsToast", true)

	makeAlphaVisibleOnly(node)
	-- Ensure the clone's shadow starts hidden until show path sets it (prevents pre-show flicker)
	pcall(function()
		local c = node:FindFirstChild("container", true)
		local s = c and c:FindFirstChild("dropshadow")
		if s and s:IsA("ImageLabel") then
			s.ImageTransparency = 1
			s.Visible = false
		end
	end)

	-- Raise content higher than global base and keep shadow just beneath it
	local contentBase = 1001
	raiseZIndex(node, contentBase)
	enforceShadowZ(node, contentBase)

	_singletonNode = node
	return _singletonNode
end

local function coalesceWindowFor(langKey: string?): number
	if not langKey then return COALESCE_WINDOW_SECONDS end
	local override = COALESCE_WINDOW_BY_KEY[langKey]
	if type(override) == "number" then
		return override
	end
	return COALESCE_WINDOW_SECONDS
end

-- ===== spawn/update toast =====
local function showOrReplaceToast(langKey: string, explicitText: string?, duration: number?, forceDisplay: boolean?, forceText: boolean?)
	-- Coalesce identical keys within a short window to avoid spam (per-key overrides)
	local window = coalesceWindowFor(langKey)
	forceDisplay = forceDisplay or forceText
	if not forceDisplay and window > 0 then
		local now = time()
		local last = _lastKeyAt[langKey]
		if last and (now - last) < window then
			return
		end
		_lastKeyAt[langKey] = now
	else
		_lastKeyAt[langKey] = time()
	end

	local node = ensureSingletonNode()
	resetToastVisualState(node)
	local label = getPreferredLabel(node)
	if label then
		label.TextTransparency = 0
		label.Visible = true
		label:SetAttribute("LangKey", langKey or "Unknown")

		-- Priority: (optional) forced server text -> localization -> explicit server text -> key
		local textToShow
		if forceText and explicitText and explicitText ~= "" then
			textToShow = explicitText
		elseif PREFER_LOCALIZATION then
			textToShow = resolveNow(langKey)
			if (not textToShow or textToShow == "") and explicitText and explicitText ~= "" then
				textToShow = explicitText
			end
		else
			textToShow = explicitText or resolveNow(langKey)
		end
		if not textToShow or textToShow == "" then
			textToShow = langKey
		end

		label.Text = textToShow
		ensureRichTextIfNeeded(label, textToShow)
	else
		warn("[Notifications] No TextLabel under template; toast will be empty.")
	end

	-- keep layering correct
	enforceShadowZ(node, 1001)

	-- Ensure the clone's shadow is visible at 0.3 when the toast shows
	pcall(function()
		local c = node:FindFirstChild("container", true)
		local s = c and c:FindFirstChild("dropshadow")
		if s and s:IsA("ImageLabel") then
			s.ZIndex = 1000
			s.ImageTransparency = 0.3
			s.Visible = true
		end
	end)

	-- reset lifetime for singleton node
	local keep = duration or DURATION_BY_KEY[langKey] or DEFAULT_DUR

	local ch = _currentChannel              -- capture at schedule time
	local token = (_tok[ch] or 0) + 1
	_tok[ch] = token

	task.spawn(function()
		task.wait(keep)
		if _tok[ch] == token then
			hideAndClearSingleton(ch)        -- hide the toast for the same channel we showed on
		end
	end)

	task.defer(function()
		if label then
			print(("[Notifications] Toast '%s' text='%s' (via %s)")
				:format(langKey, label.Text, _loaderMod and _loaderMod:GetFullName() or "<fallback>"))
		end
	end)

	return _singletonNode
end

-- ===== Remote wiring =====
function Notification.BindRemote(ev: RemoteEvent)
	if not ev or not ev:IsA("RemoteEvent") then return end
	if BoundRemotes[ev] then return end
	BoundRemotes[ev] = true

	local remoteName = ev.Name
	print(("[Notifications] Bound RemoteEvent: %s"):format(remoteName))

	ev.OnClientEvent:Connect(function(payload)
		local key; local txt; local dur; local channel; local forceText; local forceDisplay

		if typeof(payload) == "string" then
			key = payload
		elseif typeof(payload) == "table" then
			key       = payload.LangKey or payload.Key or payload.Code
			txt       = payload.Text
			dur       = payload.Duration
			channel   = payload.Channel
			forceText = payload.ForceText
			forceDisplay = payload.ForceDisplay == true
		end
		if not key or key == "" then key = "Unknown" end

		print(("[Notifications] <- %s : %s"):format(remoteName, key))

		-- Gate against reload; keep only the most-recent pending
		if not isReadyNow() then
			_pending = {
				channel = channel or DEFAULT_CHANNEL,
				key = key,
				opts = {
					text = txt,
					duration = dur,
					force = forceDisplay or forceText, -- forceText also skips coalesce
					forceText = forceText,
				},
			}
			return
		end

		-- Enforce singleton by default
		Notification.ShowSingleton(
			channel or DEFAULT_CHANNEL,
			key,
			{ text = txt, duration = dur, force = forceDisplay or forceText, forceText = forceText }
		)
	end)
end

function Notification.AutoBindAllKnownRemotes()
	local events = ReplicatedStorage:FindFirstChild("Events")
	local reFolder = events and events:FindFirstChild("RemoteEvents")
	if not reFolder then
		warn("[Notifications] Missing ReplicatedStorage/Events/RemoteEvents")
		return
	end
	-- Include legacy/alternate event names that servers may still fire (e.g., ZoneRequirementsCheck uses NotifyPlayer)
	local names = { "Notify", "NotificationStack", "PushNotification", "Toast", "PushToast", "NotifyPlayer" }
	for _, name in ipairs(names) do
		local candidate = reFolder:FindFirstChild(name)
		if typeof(candidate) == "Instance" and candidate:IsA("RemoteEvent") then
			Notification.BindRemote(candidate)
		end
	end
end

-- ===== public API =====
-- Init(screenGui) OR Init({ screenGui=?, remote=?, displayOrder=?, loader=?, language=?, dialect=?, resolve=?, readySource=? })
function Notification.Init(arg1, arg2)
	-- Prevent duplicate Init from creating duplicate templates/toasts
	if _didInit then
		-- Allow opts-only updates without re-binding everything
		if type(arg1) == "table" then
			local opts = arg1
			if type(opts.resolve)  == "function" then _resolveFn = opts.resolve end
			if type(opts.language) == "string"  then _language = opts.language end
			if type(opts.dialect)  == "string"  then _dialect  = opts.dialect  end
			if opts.readySource ~= nil then Notification.SetReadySource(opts.readySource) end
		end
		return
	end
	_didInit = true

	local passedScreenGui
	local opts

	if typeof(arg1) == "Instance" and arg1:IsA("ScreenGui") then
		passedScreenGui = arg1
		if type(arg2) == "table" then opts = arg2 end
	elseif type(arg1) == "table" then
		opts = arg1
		if opts and typeof(opts.screenGui) == "Instance" and opts.screenGui:IsA("ScreenGui") then
			passedScreenGui = opts.screenGui
		end
	end
	if not passedScreenGui then
		error("Notification.Init requires a ScreenGui (pass ScreenGui or {screenGui=...}).", 2)
	end

	UI = passedScreenGui

	-- Find stack + template (support lowercase/uppercase)
	local s1 = UI:FindFirstChild("notifications")
	local s2 = UI:FindFirstChild("Notifications")
	if s1 and s1:IsA("Frame") then
		Stack = s1
	elseif s2 and s2:IsA("Frame") then
		Stack = s2
	else
		error(("Expected a Frame named 'notifications' (or 'Notifications') under %s"):format(UI:GetFullName()), 2)
	end

	local t1 = Stack:FindFirstChild("template")
	local t2 = Stack:FindFirstChild("Template")
	if t1 and t1:IsA("Frame") then
		Template = t1
	elseif t2 and t2:IsA("Frame") then
		Template = t2
	else
		error(("Expected a Frame named 'template' (or 'Template') under %s"):format(Stack:GetFullName()), 2)
	end
	Template.Visible = false
	Template.Archivable = true

	-- hygiene
	hardenUI()
	ensureLayout()
	_purgeStrayTemplates() -- nuke leftover clones on (re)Init

	-- options
	if type(opts) == "table" then
		if typeof(opts.displayOrder) == "number" then
			UI.DisplayOrder = opts.displayOrder
		end
		if typeof(opts.loader) == "Instance" and opts.loader:IsA("ModuleScript") then
			Notification.SetLoader(opts.loader)
		end
		if type(opts.language) == "string" then _language = opts.language end
		if type(opts.dialect)  == "string" then _dialect  = opts.dialect  end
		if type(opts.resolve)  == "function" then _resolveFn = opts.resolve end
		if opts.readySource ~= nil then
			Notification.SetReadySource(opts.readySource)
		end

		local maybeRemote = opts.remote
		if typeof(maybeRemote) == "Instance" and maybeRemote:IsA("RemoteEvent") then
			Notification.BindRemote(maybeRemote)
		end
	end

	-- Language attribute hook (keeps _language in sync with the player's chosen language)
	hookLanguageAttribute()

	-- Always bind default remotes and try discovery (in case no explicit loader was given)
	Notification.AutoBindAllKnownRemotes()
	if not _loaderTbl then
		discoverLoader()
	end

	-- If no explicit readySource was provided, auto-discover a BoolValue gate
	if not _readyValue then
		local found = tryAutoFindReadyFlag()
		if found then
			Notification.SetReadySource(found)
		end
	end

	-- hook reload signals for cooldown gating
	hookWorldReloadSignals()

	-- Ensure the Template's shadow remains hidden (Studio test safety)
	pcall(function()
		local c = Template:FindFirstChild("container", true)
		local s = c and c:FindFirstChild("dropshadow")
		if s and s:IsA("GuiObject") then
			s.Visible = false
			s.ImageTransparency = 1
		end
	end)

	print(("[Notifications] Init OK. UI=%s | Stack=%s | Template=%s | ReadyGate=%s")
		:format(UI:GetFullName(), Stack:GetFullName(), Template:GetFullName(), _readyValue and _readyValue:GetFullName() or "<none>"))
end

-- Show now uses singleton by default (to enforce 'only one' policy)
function Notification.Show(langKey: string, opts)
	local txt = opts and opts.text or nil
	local dur = opts and opts.duration or nil
	local force = opts and opts.force or false
	local forceText = opts and opts.forceText or false

	if not isReadyNow() then
		_pending = {
			channel = DEFAULT_CHANNEL,
			key = langKey,
			opts = { text = txt, duration = dur, force = force, forceText = forceText },
		}
		return
	end

	-- Route through ShowSingleton so we always reuse an existing toast for channel
	return Notification.ShowSingleton(DEFAULT_CHANNEL, langKey, { text = txt, duration = dur, force = force, forceText = forceText })
end

local function findSingleton(channel: string)
	if _singletonNode and _singletonNode.Parent and _singletonNode:GetAttribute("SingletonChannel") == channel then
		return _singletonNode
	end
	return _findExistingToastForChannel(channel)
end



-- implement hide + optional channel param
function hideAndClearSingleton(channel: string?)
	local ch = channel or _currentChannel or DEFAULT_CHANNEL
	_tok[ch] = (_tok[ch] or 0) + 1 -- invalidate timers

	local node = (function()
		if _singletonNode and _singletonNode.Parent and _singletonNode:GetAttribute("SingletonChannel") == ch then
			return _singletonNode
		end
		for _, child in ipairs(Stack:GetChildren()) do
			if child ~= Template and child:GetAttribute("IsToast") == true and child:GetAttribute("SingletonChannel") == ch then
				return child
			end
		end
		return nil
	end)()

	if node then
		tweenOutAndDestroy(node, 0.25)
		if node == _singletonNode then _singletonNode = nil end
	end
end

function Notification.ShowSingleton(channel: string, langKey: string, opts)
	if not Stack then error("Notification stack not initialized") end
	if not Template then error("Notification template not initialized") end

	if not channel or channel == "" then channel = DEFAULT_CHANNEL end
	_currentChannel = channel

	local txt = opts and opts.text or nil
	local dur = opts and opts.duration or nil
	local force = opts and opts.force or false
	local forceText = opts and opts.forceText or false

	if not isReadyNow() then
		_pending = {
			channel = channel,
			key = langKey,
			opts = { text = txt, duration = dur, force = force, forceText = forceText },
		}
		return
	end

	local node = findSingleton(channel)
	if not node then
		node = ensureSingletonNode()
		if node then node:SetAttribute("SingletonChannel", channel) end
	else
		_singletonNode = node
	end

	return showOrReplaceToast(langKey, txt, dur, force, forceText)
end

function Notification.ClearChannel(channel: string)
	if not channel or channel == "" then return end
	_tok[channel] = (_tok[channel] or 0) + 1
	local node = findSingleton(channel)
	if node then tweenOutAndDestroy(node, 0.25) end
	if channel == _currentChannel then _singletonNode = nil end
end

function Notification.ClearAll()
	if not Stack then return end
	for _, child in ipairs(Stack:GetChildren()) do
		if child ~= Template and child:GetAttribute("IsToast") == true then child:Destroy() end
	end
	_singletonNode = nil
end

function Notification.SetLanguage(language: string?, dialect: string?)
	_language = language
	_dialect  = dialect
	reResolveVisibleIfAny()
end

function Notification.SetResolver(fn)
	if type(fn) == "function" then _resolveFn = fn end
end

return Notification
