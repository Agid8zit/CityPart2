-- ReplicatedStorage/Scripts/AirportUpgrades.lua
-- Cost + income driven from BalanceEconomy.
-- Uses geometric per-level cost growth via Balance.TransitCosts.Airport.levelMult
-- (No levelStep / quadTerm)

local AirportUpgrades = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Balancing        = ReplicatedStorage:WaitForChild("Balancing")
local Balance          = require(Balancing:WaitForChild("BalanceEconomy"))

-- ===================== helpers =====================
local function toNum(v, d)
	v = tonumber(v)
	if v == nil or v ~= v then return d end -- handles nil/NaN
	return v
end

-- Read cost knobs (ONLY baseCost, levelMult, tierMult, fallbackStep).
-- Supports optional per-tier overrides via Balance.TransitCosts.Airport.byTier[tier].
local function getCostCfg(tierIndex: number?)
	local ti = math.max(1, math.floor(tonumber(tierIndex) or 1))

	local root = (Balance.TransitCosts and Balance.TransitCosts.Airport) or {}
	local over = (root.byTier and root.byTier[ti]) or {}

	local baseCost     = toNum(over.baseCost     or root.baseCost,     400)
	local levelMult    = toNum(over.levelMult    or root.levelMult,    1.35)
	local tierMult     = toNum(over.tierMult     or root.tierMult,     1.00)
	local fallbackStep = toNum(over.fallbackStep or root.fallbackStep, 40)

	-- sanitize
	if baseCost < 1 then baseCost = 1 end
	if levelMult < 0 then levelMult = 1 end
	if tierMult  <= 0 then tierMult  = 1 end
	if fallbackStep < 0 then fallbackStep = 0 end

	return baseCost, levelMult, tierMult, fallbackStep
end

-- ===================== income ======================
function AirportUpgrades.GetEarnedTicketSec(level: number, tierIndex: number?): number
	level     = math.max(0, math.floor(level or 0))
	tierIndex = math.max(1, math.floor(tonumber(tierIndex) or 1))

	local cfg       = (Balance.TransitIncome and Balance.TransitIncome.Airport) or {}
	local base      = toNum(cfg.base,      30)
	local tierMult  = toNum(cfg.tierMult,  1.0)
	local levelAdd  = toNum(cfg.levelAdd,  0.0)
	local levelMult = toNum(cfg.levelMult, 1.0)

	local tierFactor   = tierMult ^ (tierIndex - 1)
	local linearFactor = 1 + level * levelAdd
	if linearFactor < 0 then linearFactor = 0 end
	local expoFactor   = levelMult ^ level

	return math.floor(base * tierFactor * linearFactor * expoFactor + 0.5)
end

-- ====================== cost =======================
-- Cost from `level` -> `level + 1`
function AirportUpgrades.GetUpgradeCost(level: number, tierIndex: number?): number
	level     = math.max(0, math.floor(level or 0))
	tierIndex = math.max(1, math.floor(tonumber(tierIndex) or 1))

	local BASE, LMUL, TMUL, FALLBACK = getCostCfg(tierIndex)

	-- geometric per-level growth; if LMUL==1 this is flat, so apply a gentle fallback slope
	local cost = (LMUL ~= 1) and (BASE * (LMUL ^ level)) or (BASE + FALLBACK * level)

	local tierFactor = TMUL ^ (tierIndex - 1)
	return math.max(1, math.floor(cost * tierFactor + 0.5))
end

-- Cumulative cost to reach targetLevel (sum of per-level costs)
function AirportUpgrades.GetTotalCostToLevel(targetLevel: number, tierIndex: number?): number
	targetLevel = math.max(0, math.floor(targetLevel or 0))
	tierIndex   = math.max(1, math.floor(tonumber(tierIndex) or 1))
	local sum = 0
	for l = 0, targetLevel - 1 do
		sum += AirportUpgrades.GetUpgradeCost(l, tierIndex)
	end
	return sum
end

return AirportUpgrades
