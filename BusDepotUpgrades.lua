local BusDepotUpgrades = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Balancing = ReplicatedStorage:WaitForChild("Balancing")
local Balance   = require(Balancing:WaitForChild("BalanceEconomy"))

-- ========= utils =========
local function clamp(n: number, lo: number, hi: number): number
	if n < lo then return lo end
	if n > hi then return hi end
	return n
end

-- ========= earnings (unchanged; tier + level multipliers from Balance) =========
function BusDepotUpgrades.GetEarnedTicketSec(level: number, tierIndex: number?): number
	level = math.max(0, math.floor(level or 0))
	tierIndex = math.max(1, math.floor(tonumber(tierIndex) or 1))

	local cfg       = (Balance.TransitIncome and Balance.TransitIncome.BusDepot) or {}
	local base      = tonumber(cfg.base)      or 30
	local tierMult  = tonumber(cfg.tierMult)  or 1.0
	local levelAdd  = tonumber(cfg.levelAdd)  or 0.0
	local levelMult = tonumber(cfg.levelMult) or 1.0

	local tierFactor   = tierMult ^ (tierIndex - 1)
	local linearFactor = 1 + level * levelAdd
	if linearFactor < 0 then linearFactor = 0 end
	local expoFactor   = levelMult ^ level

	return math.floor(base * tierFactor * linearFactor * expoFactor + 0.5)
end

-- ========= costs (NEW: geometric per-level via levelMult; legacy additive fallback) =========
local function getCostCfg()
	local c = (Balance.TransitCosts and Balance.TransitCosts.BusDepot) or {}
	-- primary knobs
	local baseCost     = tonumber(c.baseCost)     or 400
	local levelMult    = tonumber(c.levelMult)    or 1.0     -- NEW
	local tierMult     = tonumber(c.tierMult)     or 1.35
	local fallbackStep = tonumber(c.fallbackStep) or 40
	-- legacy additive knobs kept for backward-compat (ignored when levelMult ~= 1)
	local levelStep    = tonumber(c.levelStep)    or 0
	local quadTerm     = tonumber(c.quadTerm)     or 0

	if baseCost < 1 then baseCost = 1 end
	if tierMult <= 0 then tierMult = 1 end
	if levelMult < 0 then levelMult = 1 end

	return baseCost, levelMult, tierMult, fallbackStep, levelStep, quadTerm
end

-- Cost to upgrade from `level` -> `level+1`
function BusDepotUpgrades.GetUpgradeCost(level: number, tierIndex: number?): number
	level = math.max(0, math.floor(level or 0))
	tierIndex = math.max(1, math.floor(tonumber(tierIndex) or 1))

	local BASE, LMUL, TIERM, FALLBACK, STEP, QUAD = getCostCfg()

	-- geometric per-level (what you asked for)
	local cost
	if LMUL and LMUL ~= 1 then
		cost = BASE * (LMUL ^ level)
	else
		-- legacy additive fallback (kept so configs that still set step/quad continue to work)
		if STEP == 0 and QUAD == 0 then
			cost = BASE + FALLBACK * level
		else
			cost = BASE + STEP * level + QUAD * (level * level)
		end
	end

	-- per-tier multiplier at the end
	local tierFactor = TIERM ^ (tierIndex - 1)

	return math.max(1, math.floor(cost * tierFactor + 0.5))
end

-- Total cumulative cost to reach targetLevel within a tier
function BusDepotUpgrades.GetTotalCostToLevel(targetLevel: number, tierIndex: number?): number
	tierIndex = tonumber(tierIndex) or 1
	targetLevel = math.max(0, math.floor(targetLevel or 0))
	local sum = 0
	for l = 0, targetLevel - 1 do
		sum += BusDepotUpgrades.GetUpgradeCost(l, tierIndex)
	end
	return sum
end

return BusDepotUpgrades