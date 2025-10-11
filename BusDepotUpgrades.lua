local BusDepotUpgrades = {}

-- Base within-tier difficulty curve
local BASE_COST   = 100      -- baseline for Level 0→1 in Tier 1
local LEVEL_STEP  = 100      -- incremental growth per level
local QUAD_TERM   = 0        -- quadratic growth component (optional)
local TIER_MULT   = 1.35     -- each tier is 1.35× harder than the previous

-- Safe clamp
local function clamp(n: number, lo: number, hi: number): number
	if n < lo then return lo end
	if n > hi then return hi end
	return n
end

-- Ticket income per level (unchanged for now)
function BusDepotUpgrades.GetEarnedTicketSec(level: number): number
	level = math.max(0, math.floor(level or 0))
	return (level * 30) + 30
end

-- Calculates the cost to upgrade from `level` → `level + 1`.
-- Tier scaling: each tier multiplies total cost by (1.35)^(tierIndex - 1)
function BusDepotUpgrades.GetUpgradeCost(level: number, tierIndex: number?): number
	tierIndex = tonumber(tierIndex) or 1
	level = math.max(0, math.floor(level or 0))

	local tierFactor = TIER_MULT ^ math.max(tierIndex - 1, 0)
	local baseCost = BASE_COST + LEVEL_STEP * level + QUAD_TERM * (level * level)

	local finalCost = math.floor(baseCost * tierFactor + 0.5)
	return finalCost
end

-- (Optional helper) total cumulative cost to reach a certain level within a tier
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
