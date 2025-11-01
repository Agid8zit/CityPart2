-- GuiSetup.client.lua (enhanced, resilient to late GUI cloning)

-- Init Modules (safe requires)
local function safeRequire(path: Instance)
	local ok, mod = pcall(require, path)
	if not ok then
		warn(("[GuiSetup] require failed for %s: %s"):format(path:GetFullName(), tostring(mod)))
		return nil
	end
	return mod
end

do
	local RepScripts = game:GetService("ReplicatedStorage"):WaitForChild("Scripts")
	local Controllers = RepScripts:WaitForChild("Controllers")
	safeRequire(Controllers:WaitForChild("InputController"))
	safeRequire(Controllers:WaitForChild("PlayerDataController"))
end

-- Constants
local GUI_TO_INITIALIZE: {[string]: boolean} = {
	-- ScreenGuiName = Default Visibility
	LoadMenu = false,
	ControlHintGui = true,
	Main = true,
	PremiumShopGui = false,
	BuildMenu = false,
	TopBarGui = true,
	Airport = false,
	BusDepot = false,
	BoomboxSelection = false,
	Demands = false,
	RobuxThanks = false,
	SocialMedia = false,
	Credits = false,
	UnlockGui = false,
	CityName = false,
	Notifications = true,
}

-- Tunables
local FIRST_PASS_TIMEOUT      = 6.0   -- seconds to look for each GUI at startup (avoids "infinite yield" warnings)
local POLL_INTERVAL           = 0.25  -- polling cadence while waiting
local LATE_BIND_LISTEN_WINDOW = 120.0 -- keep listening for late-added GUIs for this long

-- Services / Defines
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer: Player = Players.LocalPlayer
local PlayerGui: PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Disable Core PlayerList (you can re-enable later in-game if needed)
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

-- Utilities ---------------------------------------------------------------

local function log(...) print("[GuiSetup]", ...) end

-- Calls mod[fn](ScreenGui) if it exists and is a function
local function try(mod: any, fn: string, screenGui: ScreenGui?)
	if type(mod) ~= "table" then return false end
	local f = mod[fn]
	if type(f) ~= "function" then return false end
	local ok, err = pcall(f, screenGui)
	if not ok then
		warn(("[GuiSetup] %s() threw: %s"):format(fn, tostring(err)))
		return false
	end
	return true
end

-- Resolves a ScreenGui in PlayerGui with a bounded wait
local function resolveGui(name: string, timeout: number): ScreenGui?
	local elapsed = 0
	local found = PlayerGui:FindFirstChild(name)
	while not found and elapsed < timeout do
		-- Use short WaitForChild windows to avoid long blocking + Studio warning
		PlayerGui:WaitForChild(name, POLL_INTERVAL)
		found = PlayerGui:FindFirstChild(name)
		elapsed += POLL_INTERVAL
	end
	return found and found:IsA("ScreenGui") and found :: ScreenGui or nil
end

-- Initializes one GUI (idempotent)
local Initialized: {[string]: boolean} = {}

local function initializeGui(guiName: string, defaultVisible: boolean)
	if Initialized[guiName] then return end

	local screenGui = PlayerGui:FindFirstChild(guiName)
	if not screenGui or not screenGui:IsA("ScreenGui") then return end

	-- Optional module under the ScreenGui
	local modScript = screenGui:FindFirstChild("Logic")
	local mod = (modScript and modScript:IsA("ModuleScript")) and safeRequire(modScript) or nil
	if not mod then
		warn(("[GuiSetup] %s has no usable Logic module"):format(guiName))
	end
	
	if guiName == "Notifications" then
		pcall(function()
			screenGui.ResetOnSpawn   = false
			screenGui.IgnoreGuiInset = true
			screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
			if screenGui.DisplayOrder < 1000 then
				screenGui.DisplayOrder = 1000
			end
		end)
	end
	
	-- Call Init if present
	try(mod, "Init", screenGui)

	-- Visibility / lifecycle
	if defaultVisible == true then
		if not try(mod, "OnShow", screenGui) then
			screenGui.Enabled = true
		end
	else
		if not try(mod, "OnHide", screenGui) then
			screenGui.Enabled = false
		end
	end

	Initialized[guiName] = true
	log(("Initialized %s (visible=%s)"):format(guiName, tostring(defaultVisible)))
end

-- Main --------------------------------------------------------------------

-- First pass: bounded waits (prevents "Infinite yield possible..." warnings)
do
	for guiName, state in pairs(GUI_TO_INITIALIZE) do
		local sg = resolveGui(guiName, FIRST_PASS_TIMEOUT)
		if sg then
			initializeGui(guiName, state)
		else
			warn(("[GuiSetup] %s not present after %.1fs; will listen for late add"):format(guiName, FIRST_PASS_TIMEOUT))
		end
	end
end

-- Second pass: listen for GUIs that spawn later (e.g., created by scripts)
do
	local deadline = time() + LATE_BIND_LISTEN_WINDOW

	local conn; conn = PlayerGui.ChildAdded:Connect(function(child)
		if time() > deadline then
			if conn then conn:Disconnect() end
			return
		end
		local name = child.Name
		local want = GUI_TO_INITIALIZE[name]
		if want ~= nil and not Initialized[name] and child:IsA("ScreenGui") then
			-- Give Roblox a beat to finish property replication before init
			task.defer(function()
				initializeGui(name, want)
			end)
		end
	end)

	-- Optional: hard stop the listener after the window
	task.delay(LATE_BIND_LISTEN_WINDOW, function()
		if conn then conn:Disconnect() end
	end)
end
