local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Players    = game:GetService("Players")
local player     = Players.LocalPlayer

-- Lightweight, no-network perf tier signal.
-- We only bucket by device type + simple FPS sampling (no memory/ping).

local BASE_TIER_TOUCH   = "mobile-low"
local BASE_TIER_DESKTOP = "desktop-high"

local windowSeconds = 3
local frameTimes    = table.create(180)
local idx, count    = 0, 0

local tier = BASE_TIER_DESKTOP

local function baseTier()
	if GuiService:IsTenFootInterface() then
		return "desktop-balanced"
	end
	if UIS.TouchEnabled then
		return BASE_TIER_TOUCH
	end
	return BASE_TIER_DESKTOP
end

local function pushFrame(dt)
	idx += 1
	if idx > #frameTimes then idx = 1 end
	frameTimes[idx] = dt
	count = math.min(count + 1, #frameTimes)
end

local function medianFPS()
	if count < 30 then return nil end
	local copy = table.create(count)
	for i = 1, count do copy[i] = frameTimes[i] end
	table.sort(copy)
	local m = copy[math.floor(#copy/2)]
	return 1 / m
end

local function refreshTier()
	local newTier = baseTier()
	local fps = medianFPS()
	if fps then
		if fps < 25 then
			newTier = UIS.TouchEnabled and "mobile-low" or "desktop-low"
		elseif fps < 40 then
			newTier = UIS.TouchEnabled and "mobile-low" or "desktop-balanced"
		end
	end
	if newTier ~= tier then
		tier = newTier
		player:SetAttribute("PerfTier", tier)
	end
end

RunService.RenderStepped:Connect(pushFrame)

-- Prime immediately
player:SetAttribute("PerfTier", baseTier())

while true do
	refreshTier()
	task.wait(windowSeconds)
end
