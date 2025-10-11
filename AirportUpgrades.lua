-- ReplicatedStorage/Scripts/AirportUpgrades.lua
-- Mirrors BusDepotUpgrades: same earnings, same tier-scaled costs, same helpers.

local AirportUpgrades = {}

-- Base within-tier difficulty curve (kept identical to BusDepot)
local BASE_COST   = 100      -- baseline for Level 0→1 in Tier 1
local LEVEL_STEP  = 100      -- incremental growth per level
local QUAD_TERM   = 0        -- quadratic growth component (optional)
local TIER_MULT   = 1.35     -- each tier is 1.35× harder than the previous

local function clamp(n: number, lo: number, hi: number): number
	if n < lo then return lo end
	if n > hi then return hi end
	return n
end

-- Ticket income per level (same as BusDepot)
function AirportUpgrades.GetEarnedTicketSec(level: number): number
	level = math.max(0, math.floor(level or 0))
	return (level * 30) + 30
end

-- Cost to upgrade from `level` → `level + 1`
-- Matches BusDepot signature and scaling (server already calls with tierIndex)
function AirportUpgrades.GetUpgradeCost(level: number, tierIndex: number?): number
	tierIndex = tonumber(tierIndex) or 1
	level = math.max(0, math.floor(level or 0))

	local tierFactor = TIER_MULT ^ math.max(tierIndex - 1, 0)
	local baseCost = BASE_COST + LEVEL_STEP * level + QUAD_TERM * (level * level)

	return math.floor(baseCost * tierFactor + 0.5)
end

-- Optional helper: cumulative cost to reach targetLevel within a tier
function AirportUpgrades.GetTotalCostToLevel(targetLevel: number, tierIndex: number?): number
	tierIndex = tonumber(tierIndex) or 1
	targetLevel = math.max(0, math.floor(targetLevel or 0))
	local sum = 0
	for l = 0, targetLevel - 1 do
		sum += AirportUpgrades.GetUpgradeCost(l, tierIndex)
	end
	return sum
end

return AirportUpgrades
