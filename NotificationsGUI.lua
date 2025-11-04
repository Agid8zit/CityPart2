-- PlayerGui/Notifications/Logic
-- Notifications with first-frame localization and robust Loader discovery/injection.
-- This version explicitly prefers ReplicatedStorage.Localization.Localizing.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui        = game:GetService("StarterGui")
local TweenService      = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

local Notification = {}

-- ===== duration config (strings come from Loader) =====
local DEFAULT_DUR = 4
local DURATION_BY_KEY = {
	["Cant overlap zones"]             = 4,
	["Cant build on roads"]            = 4,
	["Cant build on unique buildings"] = 4,
	["Invalid player"]                 = 3,
	["Invalid params"]                 = 3,
	["No valid area"]                  = 3,
	["Blocked"]                        = 3,
}

-- ===== state =====
local UI        -- ScreenGui
local Stack     -- Frame
local Template  -- Frame

local BoundRemotes = {}   -- [Instance] = true
local _tok         = {}   -- channel tokens for ShowSingleton dedupe

-- Localization wiring
local _language   -- string?
local _dialect    -- string?
local _loaderMod  -- ModuleScript? (the module we adopted)
local _loaderTbl  -- table?      (require(_loaderMod))
local _resolveFn  -- function?   (optional external resolver)

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

local function makeAlphaVisibleOnly(root: Instance)
	for _, obj in ipairs(root:GetDescendants()) do
		if obj:IsA("TextLabel") or obj:IsA("TextButton") then
			obj.TextTransparency = 0
		elseif obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
			obj.ImageTransparency = 0
		end
	end
end

local function raiseZIndex(root: Instance, base: number)
	for _, obj in ipairs(root:GetDescendants()) do
		if obj:IsA("GuiObject") and obj.ZIndex < base then
			obj.ZIndex = base
		end
	end
end

local function ensureRichTextIfNeeded(label: TextLabel, text: string)
	if string.find(text, "<[^>]+>") then
		label.RichText = true
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
		elseif child:IsA("TextLabel") and child ~= mainLabel then
			pushTween(child, { TextTransparency = 1 })
		end
	end
	for _, tw in ipairs(tws) do tw.Completed:Wait() end
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
-- Your loader is ReplicatedStorage.Localization.Localizing. Prefer that first.
local CANDIDATE_NAMES = {
	-- Highest priority first:
	["Localizing"] = true,
	-- Keep common aliases as fallbacks:
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
	-- Must be require-able and return a table with a .get function
	local tbl = safeRequire(mod)
	if type(tbl) ~= "table" or type(tbl.get) ~= "function" then
		return nil
	end
	return tbl
end

local function collectCandidatesFrom(root: Instance, bag: {ModuleScript})
	-- DFS collecting all ModuleScripts with candidate names
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
	-- 0) EXPLICIT: ReplicatedStorage.Localization.Localizing (your real module)
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

	-- 1) Conventional extras (kept as fallback): ReplicatedStorage.Localization.Loader etc.
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

	-- 2) broader search across common roots
	local candidates = {}
	if rs then collectCandidatesFrom(rs, candidates) end
	collectCandidatesFrom(StarterGui, candidates)

	-- If UI exists, search under it; also scan PlayerGui
	if UI then collectCandidatesFrom(UI, candidates) end
	if LocalPlayer then
		local pg = LocalPlayer:FindFirstChild("PlayerGui")
		if pg then collectCandidatesFrom(pg, candidates) end
	end

	-- 3) Prefer those that visibly accompany a "Languages" folder
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

-- Public setter (lets other code inject the loader deterministically)
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

local function resolveNow(langKey: string)
	-- Optional override resolver
	if _resolveFn then
		local ok, val = pcall(_resolveFn, langKey)
		if ok and type(val) == "string" and val ~= "" then return val end
	end

	-- Lazy discovery if we don't have a loader yet
	if not _loaderTbl then
		discoverLoader()
	end

	if _loaderTbl and type(_loaderTbl.get) == "function" then
		local ok, val = pcall(_loaderTbl.get, langKey, _language, _dialect)
		if ok and type(val) == "string" and val ~= "" then return val end
	end

	return nil
end

-- ===== spawn =====
local function spawnNode(langKey: string, explicitText: string?, duration: number?)
	if not Stack then error("Notification stack not initialized") end
	if not Template then error("Notification template not initialized") end

	local node = Template:Clone()
	node.Visible = true
	node.Parent  = Stack

	makeAlphaVisibleOnly(node)
	raiseZIndex(node, 1000)

	local label = getPreferredLabel(node)
	if label then
		label:SetAttribute("LangKey", langKey or "Unknown")

		-- Priority: explicit server text -> Loader.get -> fallback to key
		local textToShow = explicitText
		if not textToShow or textToShow == "" then
			textToShow = resolveNow(langKey)
		end
		if not textToShow or textToShow == "" then
			textToShow = langKey
		end
		label.Text = textToShow
		ensureRichTextIfNeeded(label, textToShow)
	else
		warn("[Notifications] No TextLabel under template; toast will be empty.")
	end

	task.defer(function()
		if label then
			print(("[Notifications] Spawn: key='%s' -> text='%s' TT=%.2f")
				:format(langKey, label.Text, label.TextTransparency))
			if _loaderMod then
				print(("[Notifications] (localized via) %s"):format(_loaderMod:GetFullName()))
			else
				print("[Notifications] (localized via) <none: fell back>")
			end
		end
	end)

	local dur = duration or DURATION_BY_KEY[langKey] or DEFAULT_DUR
	task.delay(dur, function()
		tweenOutAndDestroy(node, 0.3)
	end)

	return node
end

-- ===== Remote wiring =====
function Notification.BindRemote(ev: RemoteEvent)
	if not ev or not ev:IsA("RemoteEvent") then return end
	if BoundRemotes[ev] then return end
	BoundRemotes[ev] = true

	local remoteName = ev.Name
	print(("[Notifications] Bound RemoteEvent: %s"):format(remoteName))

	ev.OnClientEvent:Connect(function(payload)
		local key; local txt; local dur; local channel

		if typeof(payload) == "string" then
			key = payload
		elseif typeof(payload) == "table" then
			key     = payload.LangKey or payload.Key or payload.Code
			txt     = payload.Text
			dur     = payload.Duration
			channel = payload.Channel
		end
		if not key or key == "" then key = "Unknown" end

		print(("[Notifications] <- %s : %s"):format(remoteName, key))

		if channel and channel ~= "" then
			Notification.ShowSingleton(channel, key, { text = txt, duration = dur })
		else
			Notification.Show(key, { text = txt, duration = dur })
		end
	end)
end

function Notification.AutoBindAllKnownRemotes()
	local events = ReplicatedStorage:FindFirstChild("Events")
	local reFolder = events and events:FindFirstChild("RemoteEvents")
	if not reFolder then
		warn("[Notifications] Missing ReplicatedStorage/Events/RemoteEvents")
		return
	end
	local names = { "Notify", "NotificationStack", "PushNotification" }
	for _, name in ipairs(names) do
		local candidate = reFolder:FindFirstChild(name)
		if typeof(candidate) == "Instance" and candidate:IsA("RemoteEvent") then
			Notification.BindRemote(candidate)
		end
	end
end

-- ===== public API =====
-- Init(screenGui) OR Init({ screenGui=?, remote=?, displayOrder=?, loader=?, language=?, dialect=?, resolve=? })
function Notification.Init(arg1, arg2)
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

	-- hygiene
	hardenUI()
	ensureLayout()

	-- options
	if type(opts) == "table" then
		if typeof(opts.displayOrder) == "number" then
			UI.DisplayOrder = opts.displayOrder
		end
		if typeof(opts.loader) == "Instance" and opts.loader:IsA("ModuleScript") then
			Notification.SetLoader(opts.loader)  -- deterministic wiring
		end
		if type(opts.language) == "string" then _language = opts.language end
		if type(opts.dialect)  == "string" then _dialect  = opts.dialect  end
		if type(opts.resolve)  == "function" then _resolveFn = opts.resolve end

		local maybeRemote = opts.remote
		if typeof(maybeRemote) == "Instance" and maybeRemote:IsA("RemoteEvent") then
			Notification.BindRemote(maybeRemote)
		end
	end

	-- Always bind default remotes and try discovery (in case no explicit loader was given)
	Notification.AutoBindAllKnownRemotes()
	if not _loaderTbl then
		discoverLoader()
	end

	print(("[Notifications] Init OK. UI=%s | Stack=%s | Template=%s")
		:format(UI:GetFullName(), Stack:GetFullName(), Template:GetFullName()))
end

function Notification.Show(langKey: string, opts)
	local txt = opts and opts.text or nil
	local dur = opts and opts.duration or nil
	return spawnNode(langKey, txt, dur)
end

local function findSingleton(channel: string)
	if not Stack then return nil end
	for _, child in ipairs(Stack:GetChildren()) do
		if child ~= Template and child:GetAttribute("SingletonChannel") == channel then
			return child
		end
	end
	return nil
end

function Notification.ShowSingleton(channel: string, langKey: string, opts)
	if not channel or channel == "" then channel = "default" end
	local txt = opts and opts.text or nil
	local dur = opts and opts.duration or nil

	local node = findSingleton(channel)
	if not node then
		node = spawnNode(langKey, txt, dur)
		if node then node:SetAttribute("SingletonChannel", channel) end
	else
		local label = getPreferredLabel(node)
		if label then
			label:SetAttribute("LangKey", langKey or label:GetAttribute("LangKey") or "Unknown")
			local textToShow = txt
			if not textToShow or textToShow == "" then
				textToShow = resolveNow(langKey)
			end
			if not textToShow or textToShow == "" then
				textToShow = langKey
			end
			label.Text = textToShow
			ensureRichTextIfNeeded(label, textToShow)
		end
	end

	local token = (_tok[channel] or 0) + 1
	_tok[channel] = token
	task.spawn(function()
		local keep = dur or DURATION_BY_KEY[langKey] or DEFAULT_DUR
		task.wait(keep)
		if _tok[channel] == token then
			if node then tweenOutAndDestroy(node, 0.3) end
		end
	end)
end

function Notification.ClearChannel(channel: string)
	if not channel or channel == "" then return end
	_tok[channel] = (_tok[channel] or 0) + 1
	local node = findSingleton(channel)
	if node then tweenOutAndDestroy(node, 0.3) end
end

function Notification.ClearAll()
	if not Stack then return end
	for _, child in ipairs(Stack:GetChildren()) do
		if child ~= Template then child:Destroy() end
	end
end

function Notification.SetLanguage(language: string?, dialect: string?)
	_language = language
	_dialect  = dialect
end

function Notification.SetResolver(fn)
	if type(fn) == "function" then _resolveFn = fn end
end

return Notification
