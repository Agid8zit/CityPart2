local DefaultData = {}

-- ======================================================================
-- Save schema constants
-- ======================================================================
-- Bump when you change how the SaveManager encodes its buffers.
local CITY_STORAGE_SCHEMA = 1

-- Transit progression constants (used by both BusDepot and Airport)
local MAX_TIERS       = 10     -- Tier 1..10
local MAX_TIER_LEVEL  = 100    -- Each tier levels 0..100
local START_UNLOCK    = 0      -- 0 => unlockedTiers = floor(0/10)+1 = 1 tier at start

-- ======================================================================
-- Utilities
-- ======================================================================
local function deepClone(t: any): any
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do
		c[k] = (type(v) == "table") and deepClone(v) or v
	end
	return c
end

local function makeTransitNode()
	-- transit.<mode>:
	--   unlock : number  (drives how many tiers exist: floor(unlock/10)+1)
	--   tiers  : array-like table { [1] = {level=0}, [2] = {level=0}, ... }
	-- We seed Tier 1 at level 0; higher tiers appear as unlock rises.
	local tiers = { [1] = { level = 0 } }
	return {
		unlock = START_UNLOCK,
		tiers  = tiers,
	}
end

-- ======================================================================
-- SaveFile template (single city slot)
-- ======================================================================
DefaultData.SaveFile = {
	-- Which island / map plot this city is built on
	saveSlotPosition = {
		id = "", -- e.g. "Plot3"
	},

	-- Basic info
	cityName   = "My City",
	lastPlayed = 0, -- set at creation in newSaveFile()
	xp         = 0,
	cityLevel  = 0,

	-- Progression (human-readable list for UI/analytics)
	unlocks = {},

	-- Economy
	economy = {
		money        = 0,
		bustickets   = 0,
		planetickets = 0,
	},

	-- =========================
	-- TRANSIT (restructured)
	-- =========================
	-- Old (legacy) shape:
	--   transit = { busDepot = { level = 0 }, airport = { level = 0 } }
	-- New (per-tier):
	--   transit = {
	--     busDepot = { unlock = 0, tiers = { [1]={level=0}, ... } },
	--     airport  = { unlock = 0, tiers = { [1]={level=0}, ... } },
	--   }
	transit = {
		busDepot = makeTransitNode(),
		airport  = makeTransitNode(),
	},

	-- One-off/exclusive counters (PER SAVE — as you intended)
	exclusiveLocations = {
		FirePrecinct        = 0,
		PolicePrecinct      = 0,
		MajorHospital       = 0,
		Museum              = 0,
		FootballStadium     = 0,
		StatueOfLiberty     = 0,
		EiffelTower         = 0,
		NuclearPowerPlant   = 0,
		MolecularWaterPlant = 0,
	},

	-- (Optional) high-level mirrors; SaveManager persists authoritative state via cityStorage
	zones           = {},
	roads           = {},
	powerLines      = {},
	UniqueBuildings = {},

	-- Stats
	stats = {
		population = 0,
		happiness  = 100,
	},

	-- === SaveManager payloads (authoritative packed buffers) ===
	-- These hold compact, buffer-packed data serialized by Sload.Save and b64-wrapped.
	cityStorage = {
		zonesB64   = "", -- Sload.Save("Zone", ...)  |> b64
		roadsB64   = "", -- Sload.Save("RoadSnapshot", ...) |> b64
		unlocksB64 = "", -- Sload.Save("Unlock", ...) |> b64
		schema     = CITY_STORAGE_SCHEMA,
	},
}

-- ======================================================================
-- Factory for a fresh savefile. Ensures unique tables per slot.
-- ======================================================================
function DefaultData.newSaveFile(): table
	local sf = deepClone(DefaultData.SaveFile)
	sf.lastPlayed = os.time()

	-- fresh containers
	sf.unlocks = {}
	sf.zones = {}
	sf.roads = {}
	sf.powerLines = {}
	sf.UniqueBuildings = {}

	sf.economy = {
		money        = 0,
		bustickets   = 0,
		planetickets = 0,
	}

	-- Transit: seed Tier 1 at level 0 for both modes; unlock=0 → 1 visible tier
	sf.transit = {
		busDepot = makeTransitNode(),
		airport  = makeTransitNode(),
	}

	sf.exclusiveLocations = {
		FirePrecinct        = 0,
		PolicePrecinct      = 0,
		MajorHospital       = 0,
		Museum              = 0,
		FootballStadium     = 0,
		StatueOfLiberty     = 0,
		EiffelTower         = 0,
		NuclearPowerPlant   = 0,
		MolecularWaterPlant = 0,
	}

	sf.cityStorage = {
		zonesB64   = "",
		roadsB64   = "",
		unlocksB64 = "",
		schema     = CITY_STORAGE_SCHEMA,
	}
	return sf
end

-- ======================================================================
-- Top-level player profile (non-compressed)
-- ======================================================================
DefaultData.StartingData = {
	-- Meta (keep integer for future migrations if needed)
	Version = 1,

	Language = "English",

	-- Monetization (ACCOUNT-WIDE)
	OwnedGamepasses = {},

	-- === Player-wide section (ACCOUNT-WIDE, NOT per save) ===
	PlayerWide = {
		saveSlots = {
			default   = 3,   -- shipped capacity
			purchased = 0,   -- paid capacity across account
			bonus     = 0,   -- promo or staff/QA grants
			total     = 1,   -- auto-maintained: default+purchased+bonus
			used      = 1,   -- auto-maintained: count of keys in savefiles
		},

		-- Global cosmetic ownership & preferences (ACCOUNT-WIDE)
		styles = {
			owned    = {},  -- set-like table of style keys: { ["NeoCity"]=true, ... }
			equipped = "",  -- active/equipped style key (UI can show)
		},
	},

	currentSaveFile = "1",

	-- NOTE: use newSaveFile() to avoid shared nested tables.
	savefiles = {
		["1"] = DefaultData.newSaveFile(), -- one populated slot by default
		-- additional keys "2","3",... will be added by CreateNewSaveFile()
	},

	hasBoughtSomethingWithRobux = 0,
}

-- ======================================================================
-- Developer notes (paths for services/modules)
-- ======================================================================
-- Bus Depot
--   transit/busDepot/unlock                      : number
--   transit/busDepot/tiers/<tierIndex>/level     : number (0..100)
--
-- Airport
--   transit/airport/unlock                       : number
--   transit/airport/tiers/<tierIndex>/level      : number (0..100)
--
-- Unlocked tier count (both):
--   unlockedTiers = math.floor(unlock/10) + 1   -- clamp to 1..MAX_TIERS
--
-- Earnings rule (suggested; server authoritative):
--   totalTicketsPerSec = sum_{for each unlocked tier}( BusDepotUpgrades.GetEarnedTicketSec(level) )
--   (Airport analogously with AirportUpgrades)
--
-- UI rule (client):
--   - Render one "Template" per unlocked tier (1..unlockedTiers).
--   - Each template shows its own Level (0..100) and Upgrade button until it hits 100.
--   - A new tier appears each time unlock crosses 10, 20, 30, ... (you choose how unlock increases).
--
-- Unlock progression source (choose one, server-side):
--   A) Tie unlock to city progression / quests / milestones → write transit/<mode>/unlock directly.
--   B) Tie unlock to total tier progress (e.g., sum of all tier levels).
--      Example: unlock = math.min( sum(levels), 1000 )  -- every +10 unlocks a new tier.
--
-- ======================================================================

return DefaultData