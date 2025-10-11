-- ReplicatedStorage/Balancing/BalanceInteractions.lua
local BalanceInt = {}

---------------------------------------------------------------------
-- Synergy (emitter-based) radius in GRID CELLS
-- Used by: synergy math and pollution math (emitter width)
---------------------------------------------------------------------
BalanceInt.Synergy = {
	DefaultRadius = 5,
	Radius = {
		Residential  = 5,
		Commercial   = 5,
		Industrial   = 7,
		ResDense     = 6,
		CommDense    = 6,
		IndusDense   = 7,
		WaterTower   = 5,
	},
}

BalanceInt.IncomeBonus = {
	-- Per-target bonuses
	-- Residential: +5% if near Comm, +10% if near CommDense
	Residential = {
		Commercial = 0.05,
		CommDense  = 0.10,
	},

	-- ResDense: a bit smaller than Residential
	ResDense = {
		Commercial = 0.03,
		CommDense  = 0.06,
	},

	-- hard cap so it can’t snowball
	MaxBonus = 0.30,
}

BalanceInt.DemandMix = {
	-- default / per-target radius in GRID cells (same “emitter width” idea)
	DefaultRadius = 5,
	Radius = {
		Residential = 5,
		Commercial  = 5,
		ResDense    = 6,
		CommDense   = 6,
	},

	-- clamp caps per network so things don’t run away
	MaxBonus = {
		Water = 0.25,  -- up to +25% water demand per tile
		Power = 0.25,  -- up to +15% power demand per tile
	},

	-- WATER demand: Res/Comm help each other (dense gives a bigger bump)
	Water = {
		Residential = { Commercial = 0.05, CommDense = 0.10 },
		Commercial  = { Residential = 0.05, ResDense  = 0.10 },
		ResDense    = { Commercial = 0.03, CommDense = 0.06 },
		CommDense   = { Residential = 0.03, ResDense  = 0.06 },
	},

	-- POWER demand: same pattern, but more modest (and independent cap)
	Power = {
		Residential = { Commercial = 0.5, CommDense = 0.06 },
		Commercial  = { Residential = 0.03, ResDense  = 0.06 },
		ResDense    = { Commercial = 0.02, CommDense = 0.04 },
		CommDense   = { Residential = 0.02, ResDense  = 0.04 },
	},
}

---------------------------------------------------------------------
-- Pollution routing rules (source -> target allowlist)
-- Only these pairs can generate POLLUTION alarms/effects
---------------------------------------------------------------------
BalanceInt.Pollution = {

	DefaultRadius = 5,
	Radius = {
		Industrial = 7,
		IndusDense = 7,
		-- add/override per source mode as needed...
	},

	-- AllowedSources[targetMode][sourceMode] = true
	AllowedSources = {
		Residential = { Industrial = true, IndusDense = true },
		Commercial  = { Industrial = true, IndusDense = true },
		ResDense    = { IndusDense  = true },
		CommDense   = { IndusDense  = true },
		-- Any other target mode omitted here will not receive pollution.
	}
}

BalanceInt.PollutionIncome = {
	-- Global recovery when not polluted
	RecoveryPerTick = 0.02,   -- 2% back per clock tick when clean

	-- Per-target-mode source weights: RatePerTick and Cap (maximum penalty).
	-- Residential
	Residential = {
		Industrial = { RatePerTick = 0.02, Cap = 0.30 },  -- -2%/tick up to -30%
		IndusDense = { RatePerTick = 0.05, Cap = 0.60 },  -- -5%/tick up to -60%
	},
	-- Commercial (less than Residential)
	Commercial = {
		Industrial = { RatePerTick = 0.015, Cap = 0.20 }, -- -1.5%/tick up to -20%
		IndusDense = { RatePerTick = 0.040, Cap = 0.40 }, -- -4%/tick up to -40%
	},
	-- ResDense: ignore Industrial; IndusDense like Residential:Industrial
	ResDense = {
		-- Industrial = ignored
		IndusDense = { RatePerTick = 0.02, Cap = 0.30 },  -- same as Res:Industrial
	},
	-- CommDense: ignore Industrial; IndusDense like Commercial:Industrial
	CommDense = {
		-- Industrial = ignored
		IndusDense = { RatePerTick = 0.015, Cap = 0.20 }, -- same as Comm:Industrial
	},
}

BalanceInt.ProductionSynergy = {
	-- Search radius per *producer* mode; falls back to this default, then UXP width.
	DefaultRadius = 6,
	Radius = {
		-- Example overrides per plant/turbine:
		WaterTower             = 6,
		WaterPlant             = 8,
		PurificationWaterPlant = 8,
		MolecularWaterPlant    = 10,
		WindTurbine            = 6,
		SolarPanels            = 6,
		CoalPowerPlant         = 8,
		GasPowerPlant          = 8,
		GeothermalPowerPlant   = 8,
		NuclearPowerPlant      = 10,
	},

	-- Per neighbor type production deltas (additive), dense beats non-dense.
	-- Final multiplier = clamp( 1 + sum(deltas), 1-MaxPenalty, 1+MaxBonus )
	Deltas = {
		Residential = -0.10,
		ResDense    = -0.20,

		Commercial  = -0.10,
		CommDense   = -0.15,

		Industrial  =  0.10,
		IndusDense  =  0.20,
	},

	-- Clamp limits to avoid runaway stacking
	MaxBonus   = 0.50,  -- up to +50%
}

---------------------------------------------------------------------
-- DEMAND CONFIG: loop strengths, dense→dense, base-follow, saturation, advisor
-- (Used by DemandEngine; separated from BalanceEconomy)
---------------------------------------------------------------------
BalanceInt.DemandConfig = {
	-- Policy: whether demand bars use target shares
	Policy = {
		UseTargetsForBase  = false,  -- base types may use targets
		UseTargetsForDense = false, -- dense types never use targets
	},

	-- Core loop strengths (ebb & flow)
	Loop = {
		R_to_C = 0.90, -- Residential -> Commercial (big)
		R_to_I = 0.06, -- Residential -> Industrial (small)
		C_to_R = 0.25, -- Commercial  -> Residential (small)
		C_to_I = 0.75, -- Commercial  -> Industrial (moderate)
		I_to_R = 0.55, -- Industrial  -> Residential (mid)
		I_to_C = 0.18, -- Industrial  -> Commercial  (small)
	},

	-- Dense -> Base cascades (small nudges into base bars)
	DenseCascade = {
		ResDense  = { Residential = 0.16, Commercial = 0.28, Industrial = 0.08 },
		CommDense = { Commercial  = 0.20, Industrial = 0.24, Residential = 0.06 },
		IndusDense= { Industrial  = 0.22, Commercial  = 0.10 },
	},

	-- Dense -> Dense drivers (trimmed so dense doesn’t overwhelm)
	DenseToDense = {
		ResDense  = { CommDense = 0.40, IndusDense = 0.08 },
		CommDense = { ResDense  = 0.30, IndusDense = 0.40 },
		IndusDense= { ResDense  = 0.20, CommDense  = 0.20 },
	},

	-- Dense bars follow a fraction of their base bars
	DenseBaseFromBase = {
		ResDense   = 0.30,
		CommDense  = 0.35,
		IndusDense = 0.20,
	},

	-- Saturation (automatic damping as shares get high)
	Saturation = {
		IndustrialBase = 1.40, -- damp total Industrial pressure
		IndusDenseBar  = 1.20, -- damp IndusDense bar
	},

	-- Dense shaping & caps (keep dense visually/behaviorally contained)
	DenseShaping = {
		Elasticity = 0.85, -- compresses large dense values (x -> x^0.85)
		Cap = {
			ResDense   = 0.70,
			CommDense  = 0.70,
			IndusDense = 0.60,
		},
	},

	-- Advisor threshold for “high demand” hints
	HighDemandThreshold = 0.80,
}

return BalanceInt
