local Players = game:GetService("Players")             -- [ADDED] for client auto-registration
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function ensure(parent: Instance, className: string, name: string)
	local f = parent:FindFirstChild(name)
	if f and f.ClassName == className then
		return f
	end
	if f and f.ClassName ~= className then
		return f
	end
	local x = Instance.new(className)
	x.Name = name
	x.Parent = parent
	return x
end

local Events  = ensure(ReplicatedStorage, "Folder", "Events")
local BFs     = ensure(Events, "Folder", "BindableFunctions")
local BEs     = ensure(Events, "Folder", "BindableEvents")

local BF_Get  = ensure(BFs, "BindableFunction", "OB_GetUITarget")
local BE_Reg  = ensure(BEs, "BindableEvent",    "OB_TargetRegistered")

local UITargetRegistry = {}

local Registry: {[string]: GuiObject} = {}

-- === Core API ===
function UITargetRegistry.Register(key: string, gui: GuiObject?)
	if typeof(key) ~= "string" or key == "" then
		return
	end
	if gui and gui:IsA("GuiObject") then
		Registry[key] = gui
		BE_Reg:Fire(key, gui)
	else
		Registry[key] = nil
		BE_Reg:Fire(key, nil)
	end
	print("[UIReg] Register", key, gui and gui:GetFullName() or "nil")
end

function UITargetRegistry.Get(key: string): GuiObject?
	return Registry[key]
end

function UITargetRegistry.Changed()
	return BE_Reg.Event
end

-- === Bindable bridge ===
BF_Get.OnInvoke = function(key: string)
	return Registry[key]
end

-- ###########################################################################
-- # Client-side auto-registration (Build Button)                           #
-- #                                                                         #
-- # Registers a PlayerGui button as "BuildButton" so onboarding can pulse   #
-- # the HUD entry point even if the BuildMenu module hasn't registered it.  #
-- ###########################################################################

local function _safeText(obj: Instance): string
	local ok, t = pcall(function()
		-- prefer TextLabel/TextButton text if present
		local textObj = obj:FindFirstChildWhichIsA("TextLabel", true)
			or obj:FindFirstChildWhichIsA("TextButton", true)
			or obj
		return tostring((textObj :: any).Text)
	end)
	return (ok and t) or ""
end

local function _looksLikeBuildButton(gui: Instance): boolean
	if not (gui and gui:IsA("GuiObject")) then return false end
	-- Highest-priority: explicit attribute
	if gui:GetAttribute("OB_BuildButton") == true then return true end
	-- Name hint
	if gui.Name == "BuildButton" then return true end
	-- Text heuristic: "Build" somewhere in visible text
	local txt = _safeText(gui):lower()
	if txt:find("build", 1, true) then return true end
	return false
end

local _autoHooked = false
local function _startAutoRegister()
	if _autoHooked then return end
	_autoHooked = true

	local lp = Players.LocalPlayer
	if not lp then return end -- server or during very early bootstrap

	-- Don't block the require; do the wiring shortly after.
	task.defer(function()
		local pg = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui", 5)
		if not pg then return end

		-- Try once immediately (covers cases where HUD was already mounted)
		local first = pg:FindFirstChild("BuildButton", true)
		if first and first:IsA("GuiObject") then
			UITargetRegistry.Register("BuildButton", first)
		else
			-- fallback: scan by attribute/text
			for _, d in ipairs(pg:GetDescendants()) do
				if _looksLikeBuildButton(d) then
					UITargetRegistry.Register("BuildButton", d :: GuiObject)
					break
				end
			end
		end

		-- Live detection for late/async HUD construction
		pg.DescendantAdded:Connect(function(inst)
			if Registry["BuildButton"] then return end  -- already registered; keep first match
			if _looksLikeBuildButton(inst) then
				UITargetRegistry.Register("BuildButton", inst :: GuiObject)
			end
		end)

		-- If the current target is removed, unregister and look for a replacement.
		pg.DescendantRemoving:Connect(function(inst)
			local cur = Registry["BuildButton"]
			if cur and inst == cur then
				-- Unregister old target
				UITargetRegistry.Register("BuildButton", nil)
				-- Find a replacement if one exists
				for _, d in ipairs(pg:GetDescendants()) do
					if _looksLikeBuildButton(d) then
						UITargetRegistry.Register("BuildButton", d :: GuiObject)
						break
					end
				end
			end
		end)
	end)
end

-- Kick off auto-registration on clients only.
pcall(_startAutoRegister)

return UITargetRegistry