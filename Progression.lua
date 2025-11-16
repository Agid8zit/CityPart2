-- ServerScriptService/…/Progression.lua

local Players              = game:GetService("Players")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local ServerScriptService  = game:GetService("ServerScriptService")

local PlayerDataService    = require(ServerScriptService.Services.PlayerDataService)
local XPManager            = require(script.Parent.XPManager)

local Balancing            = ReplicatedStorage:WaitForChild("Balancing")
local Balance              = require(Balancing:WaitForChild("BalanceEconomy"))
local Events               = ReplicatedStorage:WaitForChild("Events")
local RE                   = Events:WaitForChild("RemoteEvents")
local FUS                  = RE:WaitForChild("FeatureUnlockStatus")
local NewUnlocks           = RE:WaitForChild("NewUnlocks")  -- placed in Studio; just wait for it

local Progression = {}
Progression.__index = Progression

----------------------------------------------------------------
-- 1) CONFIG
----------------------------------------------------------------
local Config       = Balance.ProgressionConfig
local dynamicStart = Config.dynamicStartLevel or #Config.xpThresholds
local growthFactor = Config.growthFactor or 1.05

-- Safe placeholder example beyond dynamicStart (optional)
Config.unlocksByLevel[dynamicStart + 1] = Config.unlocksByLevel[dynamicStart + 1] or {
	"PlaceholderOptionA","PlaceholderOptionB","PlaceholderOptionC"
}

----------------------------------------------------------------
-- 2) PRECOMPUTE CUMULATIVE XP (static segment)
----------------------------------------------------------------
local staticCumulative = {}
do
	local sum = 0
	for i = 1, #Config.xpThresholds do
		sum += Config.xpThresholds[i]
		staticCumulative[i] = sum
	end
end

local function getThreshold(level)
	if level <= #Config.xpThresholds then
		return Config.xpThresholds[level]
	else
		local prev = Config.xpThresholds[#Config.xpThresholds]
		for _ = #Config.xpThresholds + 1, level do
			prev = math.floor(prev * growthFactor)
		end
		return prev
	end
end

local function getCumulative(level)
	if level <= #staticCumulative then
		return staticCumulative[level]
	else
		local sum = staticCumulative[#staticCumulative]
		local prev = Config.xpThresholds[#Config.xpThresholds]
		for _ = #staticCumulative + 1, level do
			prev = math.floor(prev * growthFactor)
			sum += prev
		end
		return sum
	end
end

----------------------------------------------------------------
-- 3) FEATURE → MIN LEVEL MAP
----------------------------------------------------------------
local minLevel = {}
for lvl, list in pairs(Config.unlocksByLevel) do
	for _, feature in ipairs(list) do
		if minLevel[feature] == nil or lvl < minLevel[feature] then
			minLevel[feature] = lvl
		end
	end
end
setmetatable(minLevel, { __index = function() return 0 end })

local function normalizeFeatureName(featureName)
	if type(featureName) == "string" and string.sub(featureName, 1, 5) == "Flag:" then
		return "Flags"
	end
	return featureName
end

local function sanitizeRequiredLevel(level)
	level = tonumber(level)
	if not level or level ~= level or level == math.huge or level == -math.huge then
		return 0
	end
	if level < 0 then
		return 0
	end
	return math.floor(level)
end

----------------------------------------------------------------
-- 4) LEVEL CALCS (0-based)
----------------------------------------------------------------
function Progression.getLevelFromXP(xp)
	-- static range
	for i, cumXP in ipairs(staticCumulative) do
		if xp < cumXP then
			return i - 1
		end
	end
	-- dynamic range
	local lvl  = #staticCumulative
	local sum  = staticCumulative[#staticCumulative]
	local prev = Config.xpThresholds[#Config.xpThresholds]
	while true do
		lvl += 1
		prev = math.floor(prev * growthFactor)
		sum  += prev
		if xp < sum then
			return lvl - 1
		end
	end
end

----------------------------------------------------------------
-- 5) QUERIES
----------------------------------------------------------------
function Progression.getRequiredLevel(featureName)
	local normalized = normalizeFeatureName(featureName)
	return sanitizeRequiredLevel(minLevel[normalized])
end

function Progression.playerHasUnlock(player, featureName)
	local requiredLevel = Progression.getRequiredLevel(featureName)
	local SaveData = PlayerDataService.GetSaveFileData(player)
	if not SaveData then return false end
	local cityLevel = tonumber(SaveData.cityLevel) or 0
	return cityLevel >= requiredLevel
end

function Progression.getAllUnlockStatus(player)
	local status = {}
	for featureName in pairs(minLevel) do
		status[featureName] = Progression.playerHasUnlock(player, featureName)
	end
	return status
end

----------------------------------------------------------------
-- 6) LEVEL-UP HANDLER
----------------------------------------------------------------
function Progression.checkAndApplyLevelUp(player)
	local SaveData = PlayerDataService.GetSaveFileData(player)
	if not SaveData then return end

	local oldLevel = tonumber(SaveData.cityLevel) or 0
	local newLevel = Progression.getLevelFromXP(XPManager.getXP(player))

	if newLevel ~= oldLevel then
		PlayerDataService.ModifySaveData(player, "cityLevel", newLevel)
		RE.LevelUpEvent:FireClient(player, newLevel)
		warn(("[PROG] %s level changed: %d → %d"):format(player.Name, oldLevel, newLevel))

		-- compute delta across all jumped levels
		local unlockedNow = {}
		for lvl = oldLevel + 1, newLevel do
			local list = Config.unlocksByLevel[lvl]
			if list then
				for _, feature in ipairs(list) do
					table.insert(unlockedNow, feature)
				end
			end
		end

		-- always sync full unlock map for BuildMenu
		FUS:FireClient(player, Progression.getAllUnlockStatus(player))

		-- open Unlock GUI on client if anything actually unlocked
		if #unlockedNow > 0 then
			NewUnlocks:FireClient(player, {
				level    = newLevel,
				features = unlockedNow,
			})
		end
	end
end

----------------------------------------------------------------
-- 7) INIT & BINDINGS
----------------------------------------------------------------
Players.PlayerAdded:Connect(function(plr)
	-- ensure level field is consistent on join and push initial unlock map
	Progression.checkAndApplyLevelUp(plr)
	FUS:FireClient(plr, Progression.getAllUnlockStatus(plr))
end)

XPManager.XPChanged.Event:Connect(function(plr)
	Progression.checkAndApplyLevelUp(plr)
end)

----------------------------------------------------------------
-- 8) HELPERS
----------------------------------------------------------------
function Progression.getXPForLevel(level)
	return getThreshold(level + 1)
end

function Progression.getXPAtLevelStart(level)
	return (level >= 1) and getCumulative(level) or 0
end

function Progression.getXPToReachLevel(level)
	return getCumulative(level + 1)
end

function Progression.getNextLevelXP(player)
	local SaveData = PlayerDataService.GetSaveFileData(player)
	if not SaveData then return end
	return Progression.getXPToReachLevel(SaveData.cityLevel or 0)
end

function Progression.getXPtoNextLevel(player)
	local SaveData = PlayerDataService.GetSaveFileData(player)
	if not SaveData then return end
	local lvl = SaveData.cityLevel or 0
	local need = Progression.getXPToReachLevel(lvl)
	local xp   = XPManager.getXP(player)
	return math.max(0, need - xp)
end

----------------------------------------------------------------
Progression.Config = Config
return Progression
