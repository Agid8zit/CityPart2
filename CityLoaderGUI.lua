--!strict
-- ReplicatedStorage/Scripts/UI/CityLoader.lua
-- Fancy loading UI as a reusable Show/Hide API (for use from LoadMenu, etc.).

local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local TweenService    = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

local CityLoader = {}

-- ===== CONFIG ===============================================================

local RNG = Random.new()

-- If you change the UI asset names, keep the WaitForChild lookups below in sync,
-- not this list.
local PRELOAD_ASSETS: {string} = {
	"rbxassetid://6586979979",      -- pop
	"rbxassetid://80281677741848",  -- woosh
	"rbxassetid://112844807562193", -- roads
	"rbxassetid://11181171441",     -- fill bar
	"rbxassetid://11181171441",     -- fill bar drop shadow
	"rbxassetid://115781226506183", -- tree1
	"rbxassetid://117236742548683", -- tree2
	"rbxassetid://92973934677440",  -- car1
	"rbxassetid://103876640729602", -- car2
	"rbxassetid://72424058297780",  -- car3
	"rbxassetid://84316478596852",  -- car4
	"rbxassetid://110904517458791", -- car5
	"rbxassetid://126182988804689", -- car6
	"rbxassetid://82082935964049",  -- building1
	"rbxassetid://119295999162301", -- building2
	"rbxassetid://134435360105788", -- building3
	"rbxassetid://125828872386045", -- building4
	"rbxassetid://107238035215550", -- building5
	"rbxassetid://88445168652719",  -- building6
	"rbxassetid://121325972613226", -- building7
	"rbxassetid://140426692476468", -- building8
	"rbxassetid://80948003006739",  -- building9
	"rbxassetid://102458499958280", -- building10
	"rbxassetid://86335652733746",  -- building11
	"rbxassetid://138591763775934", -- building12
	"rbxassetid://98112102515026",  -- building13
	"rbxassetid://96416881219071",  -- building14
	"rbxassetid://118716009054758", -- building15
	"rbxassetid://116825043465939", -- building16
	"rbxassetid://81109269876260",  -- building17
}

local IMAGELABEL_SIZE_POP_STRENGTH = 4     -- 0 = linear; larger = more pop
local IMAGELABEL_POS_JUMP_STRENGTH = 0.10  -- "hop" magnitude
local IMAGELABEL_POS_TWEEN_DURATION = 0.5

-- ===== STATE ================================================================

type ImageData = { ImageLabel: ImageLabel, DefaultSizeY: number }

local _state = {
	-- lifecycle
	intentVisible = false,
	mounted       = false,
	finishing     = false,

	-- ui refs
	UI = nil :: ScreenGui?,
	UI_Background = nil :: Frame?,
	UI_LoadingScreen = nil :: Frame?,
	UI_BlackTop = nil :: Frame?,
	UI_BlackBot = nil :: Frame?,
	UI_Fill = nil :: Frame?,
	UI_LoadingText = nil :: TextLabel?,
	UI_LoadingPercentage = nil :: TextLabel?,

	-- content buckets
	_buildings = {} :: {ImageData},
	_cars = {} :: {ImageData},
	_trees = {} :: {ImageData},
	_totalImages = 0,

	-- anim/progress
	percent = 0,
	dotConn = nil :: RBXScriptConnection?,
	popDebounce = 0.0,

	-- messaging
	baseMessage = "Loading",

	-- external progress control
	externalProgress = false,
}

-- ===== UTILS ================================================================

local function remap(x: number, inMin: number, inMax: number, outMin: number, outMax: number): number
	if inMax == inMin then return outMin end
	local alpha = (x - inMin) / (inMax - inMin)
	return outMin + (outMax - outMin) * alpha
end

local function playPop(sfxSpeed: number)
	if os.clock() < _state.popDebounce then return end
	_state.popDebounce = os.clock() + 0.05
	local src = script:FindFirstChild("PopSound")
	if src and src:IsA("Sound") then
		local s = src:Clone()
		s.PlayOnRemove = true
		s.PlaybackSpeed = sfxSpeed
		s.Parent = workspace
		task.defer(function() s:Destroy() end)
	end
end

local function playWoosh()
	local src = script:FindFirstChild("Woosh")
	if src and src:IsA("Sound") then
		local s = src:Clone()
		s.PlayOnRemove = true
		s.Parent = workspace
		task.defer(function() s:Destroy() end)
	end
end

local function imageTweenEffect(img: ImageLabel, startY: number, endSizeY: number, sfxSpeed: number)
	-- sfx
	playPop(sfxSpeed)

	-- hop + scale
	local started = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function()
		local alpha = math.clamp((os.clock() - started) / IMAGELABEL_POS_TWEEN_DURATION, 0, 1)
		local alphasine = math.sin(alpha * math.pi)
		local alphaSubOne = alpha - 1
		local alphabounce = alphaSubOne * alphaSubOne * (alpha * IMAGELABEL_SIZE_POP_STRENGTH + alphaSubOne) + 1

		local p = startY - IMAGELABEL_POS_JUMP_STRENGTH * alphasine
		local s = endSizeY * alphabounce

		if alpha >= 1.0 then
			if conn then conn:Disconnect() end
			img.Position = UDim2.fromScale(img.Position.X.Scale, startY)
			img.Size = UDim2.fromScale(img.Size.X.Scale, endSizeY)
		else
			img.Position = UDim2.fromScale(img.Position.X.Scale, p)
			img.Size = UDim2.fromScale(img.Size.X.Scale, s)
		end
	end)
end

local function setPercent(p: number)
	if not _state.UI then return end
	local pct = math.clamp(p, 0, 100)
	_state.percent = pct

	-- text
	local pctLabel = _state.UI_LoadingPercentage
	if pctLabel then
		pctLabel.Text = string.format("%d%%", math.floor(pct + 0.5))
	end

	-- fill bar
	local fill = _state.UI_Fill
	if fill then
		TweenService:Create(fill, TweenInfo.new(0.15), {
			Size = UDim2.fromScale(pct / 100, fill.Size.Y.Scale),
		}):Play()
	end

	-- staged reveals
	local alpha = math.clamp(math.floor(pct + 0.5) / 100, 0, 1)
	local idx   = math.floor(remap(alpha, 0, 1, 0, _state._totalImages) + 0.5)

	-- Trees first
	local treeCount = #_state._trees
	local toTree = math.min(idx, treeCount)
	for i = 1, toTree do
		local d = _state._trees[i]
		if d and d.ImageLabel.Size.Y.Scale == 0 then
			imageTweenEffect(d.ImageLabel, d.ImageLabel.Position.Y.Scale, d.DefaultSizeY, 2)
		end
	end

	-- Buildings next
	local toBuilding = math.clamp(idx - treeCount, 0, #_state._buildings)
	for i = 1, toBuilding do
		local d = _state._buildings[i]
		if d and d.ImageLabel.Size.Y.Scale == 0 then
			imageTweenEffect(d.ImageLabel, d.ImageLabel.Position.Y.Scale, d.DefaultSizeY, RNG:NextNumber(0.5, 0.8))
		end
	end

	-- Cars last
	local toCars = math.clamp(idx - treeCount - #_state._buildings, 0, #_state._cars)
	for i = 1, toCars do
		local d = _state._cars[i]
		if d and d.ImageLabel.Size.Y.Scale == 0 then
			imageTweenEffect(d.ImageLabel, d.ImageLabel.Position.Y.Scale, d.DefaultSizeY, 1)
		end
	end
end

-- ===== MOUNT / UNMOUNT ======================================================

local function mountUI(initialMessage: string?)
	if _state.mounted then return end

	local template = script:WaitForChild("LoadingScreen") :: ScreenGui
	local ui = template:Clone()
	ui.ResetOnSpawn = false
	ui.IgnoreGuiInset = true
	ui.Enabled = true
	ui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	_state.UI = ui
	_state.UI_Background     = ui:WaitForChild("Background") :: Frame
	_state.UI_LoadingScreen  = ui:WaitForChild("LoadingScreen") :: Frame
	_state.UI_BlackTop       = ui:WaitForChild("BlackTop") :: Frame
	_state.UI_BlackBot       = ui:WaitForChild("BlackBot") :: Frame

	local bar = (_state.UI_LoadingScreen :: Frame):WaitForChild("Bar") :: Frame
	_state.UI_Fill               = bar:WaitForChild("Fill") :: Frame
	_state.UI_LoadingText        = bar:WaitForChild("Loading") :: TextLabel
	-- NOTE: original UI uses "LoadingPercentange" (typo); keep it.
	_state.UI_LoadingPercentage  = (_state.UI_LoadingScreen :: Frame):WaitForChild("LoadingPercentange") :: TextLabel

	-- Prepare image folders and zero their Y scale
	local buildings = (_state.UI_LoadingScreen :: Frame):WaitForChild("Buildings")
	local cars      = (_state.UI_LoadingScreen :: Frame):WaitForChild("Cars")
	local trees     = (_state.UI_LoadingScreen :: Frame):WaitForChild("Trees")

	_state._buildings = {}
	_state._cars = {}
	_state._trees = {}
	_state._totalImages = 0

	local function primeFolder(folder: Instance, bucket: {ImageData})
		for _, inst in ipairs(folder:GetChildren()) do
			if inst:IsA("ImageLabel") then
				_state._totalImages += 1
				table.insert(bucket, {
					ImageLabel = inst,
					DefaultSizeY = inst.Size.Y.Scale,
				})
				inst.Size = UDim2.fromScale(inst.Size.X.Scale, 0)
			end
		end
	end

	primeFolder(buildings, _state._buildings)
	primeFolder(cars, _state._cars)
	primeFolder(trees, _state._trees)

	-- Defaults
	local fill = _state.UI_Fill
	if fill then
		fill.Size = UDim2.fromScale(0, fill.Size.Y.Scale)
	end

	_state.baseMessage = (initialMessage and initialMessage ~= "" and initialMessage) or "Loading"

	local loadingText = _state.UI_LoadingText
	if loadingText then
		loadingText.Text = _state.baseMessage .. "..."
	end

	local loadingPct = _state.UI_LoadingPercentage
	if loadingPct then
		loadingPct.Text = "0%"
	end

	_state.mounted = true
end

local function unmountUI()
	if not _state.mounted then return end

	if _state.dotConn then _state.dotConn:Disconnect() end
	_state.dotConn = nil

	if _state.UI then
		_state.UI:Destroy()
	end

	-- reset state
	_state.UI = nil
	_state.UI_Background = nil
	_state.UI_LoadingScreen = nil
	_state.UI_BlackTop = nil
	_state.UI_BlackBot = nil
	_state.UI_Fill = nil
	_state.UI_LoadingText = nil
	_state.UI_LoadingPercentage = nil
	_state._buildings = {}
	_state._cars = {}
	_state._trees = {}
	_state._totalImages = 0
	_state.percent = 0
	_state.mounted = false
	_state.finishing = false
	_state.baseMessage = "Loading"
	_state.externalProgress = false
end

local function animateOutAndCleanup()
	if not _state.mounted or not _state.UI_BlackTop or not _state.UI_BlackBot then
		unmountUI()
		return
	end

	-- small pause so 100% is visible
	task.wait(0.25)

	-- curtains in
	TweenService:Create(_state.UI_BlackTop, TweenInfo.new(1.0), { Size = UDim2.fromScale(1, 0.6) }):Play()
	TweenService:Create(_state.UI_BlackBot, TweenInfo.new(1.0), { Size = UDim2.fromScale(1, 0.6) }):Play()
	playWoosh()
	task.wait(1.2)

	-- drop the middle content
	if _state.UI_Background then _state.UI_Background:Destroy() end
	if _state.UI_LoadingScreen then _state.UI_LoadingScreen:Destroy() end

	-- curtains out
	if _state.UI_BlackTop and _state.UI_BlackBot then
		TweenService:Create(_state.UI_BlackTop, TweenInfo.new(1.0), { Size = UDim2.fromScale(1, 0) }):Play()
		TweenService:Create(_state.UI_BlackBot, TweenInfo.new(1.0), { Size = UDim2.fromScale(1, 0) }):Play()
		playWoosh()
		task.wait(1.2)
	end

	unmountUI()
end

-- ===== PUBLIC API ===========================================================

-- CityLoader.Show({ delay: number? = 0.6, message: string? = "Loading" })
function CityLoader.Show(opts: {delay: number?, message: string?}?): ()
	-- If already requested, just update the message (no duplicate mounting).
	if _state.intentVisible then
		local msg = (opts and opts.message) or nil
		if msg and msg ~= "" then
			_state.baseMessage = msg
			local lbl = _state.UI_LoadingText
			if lbl then lbl.Text = msg .. "..." end
		end
		return
	end

	_state.intentVisible = true
	_state.baseMessage = (opts and opts.message) or "Loading"
	local delayS = (opts and opts.delay) or 0.6

	task.spawn(function()
		-- show only if the op lasts long enough (prevents flicker)
		task.wait(delayS)
		if not _state.intentVisible then return end

		mountUI(_state.baseMessage)

		-- preload assets (best-effort)
		pcall(function() ContentProvider:PreloadAsync(PRELOAD_ASSETS) end)

		-- "Loading..." dot‑dot‑dot
		local dotTimer = 0.0
		local dotCount = 3
		_state.dotConn = RunService.Heartbeat:Connect(function()
			if os.clock() < dotTimer then return end
			dotTimer = os.clock() + 0.2
			dotCount += 1
			if dotCount == 4 then dotCount = 1 end

			local lbl = _state.UI_LoadingText
			if lbl then
				local base = _state.baseMessage
				if dotCount == 1 then
					lbl.Text = base .. "."
				elseif dotCount == 2 then
					lbl.Text = base .. ".."
				else
					lbl.Text = base .. "..."
				end
			end
		end)

		-- progress driver: indeterminate up to ~85% (paused if externalProgress), then on Hide() finish to 100%
		task.spawn(function()
			local p = 0
			while _state.intentVisible and not _state.finishing do
				if _state.externalProgress then
					task.wait(0.05) -- wait for external updates
				else
					task.wait(RNG:NextNumber(0.02, 0.04))
					p = math.min(85, p + RNG:NextInteger(1, 3))
					-- don't regress if external already set a higher value
					if p < _state.percent then
						p = _state.percent
					end
					setPercent(p)
				end
			end

			-- If we got cancelled before mounting, don't try to animate out
			if not _state.mounted then
				_state.intentVisible = false
				_state.finishing = false
				_state.externalProgress = false
				return
			end

			-- finish to 100% smoothly once finishing is signaled
			for i = math.floor(_state.percent) + 1, 100 do
				task.wait(RNG:NextNumber(0.01, 0.02))
				setPercent(i)
			end

			-- fade out & cleanup
			animateOutAndCleanup()
			_state.intentVisible = false
			_state.finishing = false
			_state.externalProgress = false
		end)
	end)
end

-- Update the message while visible (e.g., "Deleting Save")
function CityLoader.UpdateMessage(msg: string?): ()
	if not msg or msg == "" then return end
	_state.baseMessage = msg
	local lbl = _state.UI_LoadingText
	if lbl then lbl.Text = msg .. "..." end
end

-- Set externally-driven progress (e.g., server A→F phase updates).
-- Keeps the loader visible (shows immediately if needed), pauses auto-progress,
-- and never regresses the bar.
function CityLoader.SetProgress(percent: number, message: string?): ()
	local p = math.clamp(math.floor(percent + 0.5), 0, 100)

	-- Ensure visible promptly
	if not _state.intentVisible then
		CityLoader.Show({ delay = 0, message = message or _state.baseMessage })
	end

	_state.externalProgress = true
	if message and message ~= "" then
		CityLoader.UpdateMessage(message)
	end

	-- Apply after mount (or immediately if already mounted)
	if _state.mounted then
		-- don't regress visual percent
		if p < _state.percent then p = _state.percent end
		setPercent(p)
	else
		task.spawn(function()
			-- wait briefly for mount to complete
			local deadline = os.clock() + 1.0
			while not _state.mounted and os.clock() < deadline do
				RunService.Heartbeat:Wait()
			end
			if _state.mounted then
				if p < _state.percent then p = _state.percent end
				setPercent(p)
			end
		end)
	end
end

-- CityLoader.Hide() — finish to 100% and fade out; if still in delay window, cancels showing.
function CityLoader.Hide(): ()
	-- If we're not even mounted yet, cancel the pending show to avoid flash.
	if not _state.mounted then
		_state.intentVisible = false
		_state.finishing = false
		_state.externalProgress = false
		return
	end
	-- Otherwise, signal the progress loop to finish.
	_state.finishing = true
end

return CityLoader
