-- ServerScriptService/Build/Zones/ZoneManager/DemandEngine.lua
local DemandEngine = {}
DemandEngine.__index = DemandEngine

-- perf
DemandEngine.RETURN_COPIES = false
DemandEngine.SKIP_ADVISOR  = false

-- utils
local function clamp01(x)
	if x ~= x then return 0 end
	if x < 0 then return 0 elseif x > 1 then return 1 else return x end
end
local function nz(x) return (type(x) == "number" and x) or 0 end
local function pow(x, e)
	if x <= 0 then return 0 end
	return x ^ e
end

-- keys
local K_BASE  = { "Residential","Commercial","Industrial" }
local K_DENSE = { "ResDense","CommDense","IndusDense" }
local K_ALL   = { "Residential","Commercial","Industrial","ResDense","CommDense","IndusDense" }

-- ==========================
-- DEFAULT CONFIG (sane, soft)
-- ==========================
-- Base loop (R→I small, C→I moderate)
local DEFAULT_LOOP = {
	R_to_C = 0.90, R_to_I = 0.06,   -- smaller than before
	C_to_R = 0.25, C_to_I = 0.75,   -- toned down
	I_to_R = 0.55, I_to_C = 0.18,   -- small I→C nudge keeps ebb/flow
}

-- Dense → Base cascades (kept conservative)
local DEFAULT_DENSE_CASCADE = {
	ResDense  = { Residential = 0.16, Commercial = 0.28, Industrial = 0.08 },
	CommDense = { Commercial  = 0.20, Industrial = 0.24, Residential = 0.06 },
	IndusDense= { Industrial  = 0.22, Commercial  = 0.10 },
}

-- Dense → Dense (heavily reduced)
local DEFAULT_DENSE_TO_DENSE = {
	ResDense  = { CommDense = 0.40, IndusDense = 0.08 },
	CommDense = { ResDense  = 0.30, IndusDense = 0.40 },
	IndusDense= { ResDense  = 0.20, CommDense  = 0.20 },
}

-- Dense follows a fraction of base bars (reduced)
local DEFAULT_DENSE_BASE_FROM_BASE = {
	ResDense  = 0.30,
	CommDense = 0.35,
	IndusDense= 0.20,
}

-- Saturation + shaping
local DEFAULT_SATURATION = {
	IndustrialBase = 1.40,  -- damp Industrial pressure when I share is high
	IndusDenseBar  = 1.20,  -- damp IndusDense bar when share is high
}

-- NEW: dense shaping & caps
local DEFAULT_DENSE_SHAPING = {
	Elasticity = 0.85, -- compress dense bars: x -> x^0.85 (so big values shrink a bit)
	Cap = {            -- hard caps so dense can’t dominate UI even if input is noisy
		ResDense  = 0.70,
		CommDense = 0.70,
		IndusDense= 0.60,
	}
}

-- Advisor threshold
local DEFAULT_ADVISOR = 0.80

-- Policy flags
local DEFAULT_POLICY = {
	UseTargetsForBase  = true,  -- you can flip to false to ignore targets entirely for base
	UseTargetsForDense = false, -- dense NEVER uses targets (your request)
}

local DEFAULT_CFG = {
	Loop                = DEFAULT_LOOP,
	DenseCascade        = DEFAULT_DENSE_CASCADE,
	DenseToDense        = DEFAULT_DENSE_TO_DENSE,
	DenseBaseFromBase   = DEFAULT_DENSE_BASE_FROM_BASE,
	Saturation          = DEFAULT_SATURATION,
	DenseShaping        = DEFAULT_DENSE_SHAPING,
	HighDemandThreshold = DEFAULT_ADVISOR,
	Policy              = DEFAULT_POLICY,
}

-- scratch
local S_norm = { total = 0, share = {
	Residential=0, Commercial=0, Industrial=0,
	ResDense=0, CommDense=0, IndusDense=0
}}
local OUT_demand = {
	Residential=0, Commercial=0, Industrial=0,
	ResDense=0, CommDense=0, IndusDense=0
}
local OUT_pressure = {
	toResidential=0, toCommercial=0, toIndustrial=0,
	cascade = { Residential=0, Commercial=0, Industrial=0 },
	share   = S_norm.share,
	total   = 0,
}
local OUT = { demand=OUT_demand, pressure=OUT_pressure, suggestAdvisor=false }

-- normalize shares
local function _normalizeCounts_into(counts)
	local s = S_norm.share
	local total = 0
	for i = 1, #K_ALL do total += nz(counts and counts[K_ALL[i]]) end
	S_norm.total = total
	if total <= 0 then
		s.Residential,s.Commercial,s.Industrial,s.ResDense,s.CommDense,s.IndusDense = 0,0,0,0,0,0
		return S_norm
	end
	s.Residential = nz(counts.Residential) / total
	s.Commercial  = nz(counts.Commercial)  / total
	s.Industrial  = nz(counts.Industrial)  / total
	s.ResDense    = nz(counts.ResDense)    / total
	s.CommDense   = nz(counts.CommDense)   / total
	s.IndusDense  = nz(counts.IndusDense)  / total
	return S_norm
end

-- base target demand (deficit vs targets; BASE ONLY)
local function _baseDemand_into(countsTiles, targets, useTargetsForBase)
	local s = _normalizeCounts_into(countsTiles).share
	local out = OUT_demand
	out.Residential,out.Commercial,out.Industrial = 0,0,0
	-- never fill dense here (we ignore dense targets entirely)

	if not useTargetsForBase or type(targets) ~= "table" then
		return out -- zeros; rely purely on loop/cascades/back-pressure
	end

	for i = 1, #K_BASE do
		local k      = K_BASE[i]
		local target = targets[k]
		if target and target > 0 then
			local have = nz(s[k])
			local deficit = target - have
			out[k] = (deficit > 0) and clamp01(deficit / target) or 0
		end
	end
	return out
end

-- gating
local function _denseAllowed(unlocks, key)
	return not unlocks or unlocks[key] == true
end

-- MAIN
-- countsTiles      : per-mode tile counts
-- targets          : (optional) base share targets (ignored for dense)
-- cfg              : config (can come from BalanceInteractions.DemandConfig)
-- unlocks          : { ResDense=?, CommDense=?, IndusDense=? } or nil
-- uxpBackPressure  : { Residential=?, Commercial=?, Industrial=? } or nil
function DemandEngine.computeSnapshot(countsTiles, targets, cfg, unlocks, uxpBackPressure)
	-- seed (empty city → Res + ResDense only)
	local tot = 0
	for i=1,#K_ALL do tot += nz(countsTiles and countsTiles[K_ALL[i]]) end
	if tot <= 0 then
		return {
			demand = { Residential=1, Commercial=0, Industrial=0, ResDense=1, CommDense=0, IndusDense=0 },
			pressure = {
				toResidential=0, toCommercial=0, toIndustrial=0,
				cascade = { Residential=0, Commercial=0, Industrial=0 },
				share   = { Residential=0, Commercial=0, Industrial=0, ResDense=0, CommDense=0, IndusDense=0 },
				total   = 0,
			},
			suggestAdvisor = false,
		}
	end

	cfg = cfg or DEFAULT_CFG
	local Policy   = cfg.Policy or DEFAULT_POLICY
	local Loop     = cfg.Loop or DEFAULT_LOOP
	local Sat      = cfg.Saturation or DEFAULT_SATURATION
	local DenseCas = cfg.DenseCascade or DEFAULT_DENSE_CASCADE
	local D2D      = cfg.DenseToDense or DEFAULT_DENSE_TO_DENSE
	local BaseFrom = cfg.DenseBaseFromBase or DEFAULT_DENSE_BASE_FROM_BASE
	local DenseSh  = cfg.DenseShaping or DEFAULT_DENSE_SHAPING

	-- 1) base targets (BASE ONLY; dense NEVER uses targets)
	_baseDemand_into(countsTiles, targets, Policy.UseTargetsForBase)

	-- 2) cross-pressures for base loop (+ saturation)
	local s = _normalizeCounts_into(countsTiles).share

	local toC = nz(Loop.R_to_C) * s.Residential
	local toI = nz(Loop.R_to_I) * s.Residential
	toI       = toI + nz(Loop.C_to_I) * s.Commercial
	local toR = nz(Loop.C_to_R) * s.Commercial
	toR       = toR + nz(Loop.I_to_R) * s.Industrial
	toC       = toC + nz(Loop.I_to_C) * s.Industrial

	-- Saturate Industrial pressure when Industrial is already common
	local GI = nz(Sat.IndustrialBase)
	if GI > 0 then
		local damp = (1 - clamp01(s.Industrial)) ^ GI
		toI = toI * damp
	end

	-- 3) dense → base cascades (small nudges only)
	local hasRD = nz(countsTiles and countsTiles.ResDense)   > 0
	local hasCD = nz(countsTiles and countsTiles.CommDense)  > 0
	local hasID = nz(countsTiles and countsTiles.IndusDense) > 0
	local anyDenseExists = hasRD or hasCD or hasID

	local casR, casC, casI = 0,0,0
	if _denseAllowed(unlocks, "ResDense") and hasRD then
		local row = DenseCas.ResDense or {}
		casR += nz(row.Residential) * s.ResDense
		casC += nz(row.Commercial ) * s.ResDense
		casI += nz(row.Industrial ) * s.ResDense
	end
	if _denseAllowed(unlocks, "CommDense") and hasCD then
		local row = DenseCas.CommDense or {}
		casC += nz(row.Commercial ) * s.CommDense
		casI += nz(row.Industrial ) * s.CommDense
		casR += nz(row.Residential) * s.CommDense
	end
	if _denseAllowed(unlocks, "IndusDense") and hasID then
		local row = DenseCas.IndusDense or {}
		casI += nz(row.Industrial ) * s.IndusDense
		casC += nz(row.Commercial ) * s.IndusDense
	end

	OUT_pressure.toCommercial  = clamp01(toC)
	OUT_pressure.toIndustrial  = clamp01(toI)
	OUT_pressure.toResidential = clamp01(toR)
	OUT_pressure.cascade.Residential = clamp01(casR)
	OUT_pressure.cascade.Commercial  = clamp01(casC)
	OUT_pressure.cascade.Industrial  = clamp01(casI)
	OUT_pressure.total = S_norm.total

	-- 4) compose base bars
	local bp = uxpBackPressure or {}
	OUT_demand.Residential = clamp01(nz(OUT_demand.Residential) + toR + casR + nz(bp.Residential))
	OUT_demand.Commercial  = clamp01(nz(OUT_demand.Commercial)  + toC + casC + nz(bp.Commercial))
	OUT_demand.Industrial  = clamp01(nz(OUT_demand.Industrial)  + toI + casI + nz(bp.Industrial))

	-- 5) dense bars (NO TARGETS): follow base + dense→dense, then shape + cap
	local wantRD_fromBase = nz(BaseFrom.ResDense)  * OUT_demand.Residential
	local wantCD_fromBase = nz(BaseFrom.CommDense) * OUT_demand.Commercial
	local wantID_fromBase = nz(BaseFrom.IndusDense)* OUT_demand.Industrial

	local wantRD_fromDense, wantCD_fromDense, wantID_fromDense = 0,0,0
	if hasRD then
		local row = D2D.ResDense or {}
		wantCD_fromDense += nz(row.CommDense)  * s.ResDense
		wantID_fromDense += nz(row.IndusDense) * s.ResDense
	end
	if hasCD then
		local row = D2D.CommDense or {}
		wantRD_fromDense += nz(row.ResDense)   * s.CommDense
		wantID_fromDense += nz(row.IndusDense) * s.CommDense
	end
	if hasID then
		local row = D2D.IndusDense or {}
		wantRD_fromDense += nz(row.ResDense)   * s.IndusDense
		wantCD_fromDense += nz(row.CommDense)  * s.IndusDense
	end

	local dense_RD = clamp01(wantRD_fromBase + wantRD_fromDense)
	local dense_CD = clamp01(wantCD_fromBase + wantCD_fromDense)
	local dense_ID = clamp01(wantID_fromBase + wantID_fromDense)

	-- Saturate IndusDense bar if IndusDense share already high
	local Gd = nz((cfg.Saturation or DEFAULT_SATURATION).IndusDenseBar)
	if Gd > 0 then
		local dampD = (1 - clamp01(s.IndusDense)) ^ Gd
		dense_ID = dense_ID * dampD
	end

	-- Elastic compress and cap all dense bars
	local elast = nz(DenseSh.Elasticity) > 0 and nz(DenseSh.Elasticity) or 1
	if elast ~= 1 then
		dense_RD = clamp01(pow(dense_RD, elast))
		dense_CD = clamp01(pow(dense_CD, elast))
		dense_ID = clamp01(pow(dense_ID, elast))
	end
	local cap = (DenseSh.Cap or {})
	dense_RD = math.min(dense_RD, nz(cap.ResDense)  > 0 and cap.ResDense  or 1)
	dense_CD = math.min(dense_CD, nz(cap.CommDense) > 0 and cap.CommDense or 1)
	dense_ID = math.min(dense_ID, nz(cap.IndusDense)> 0 and cap.IndusDense or 1)

	-- Gate
	if _denseAllowed(unlocks, "ResDense") then
		OUT_demand.ResDense = dense_RD
	else
		OUT_demand.ResDense = 0
	end

	if anyDenseExists and _denseAllowed(unlocks, "CommDense") then
		OUT_demand.CommDense = dense_CD
	else
		OUT_demand.CommDense = 0
	end

	if anyDenseExists and _denseAllowed(unlocks, "IndusDense") then
		OUT_demand.IndusDense = dense_ID
	else
		OUT_demand.IndusDense = 0
	end

	-- 6) advisor (base only)
	if DemandEngine.SKIP_ADVISOR then
		OUT.suggestAdvisor = false
	else
		local th = (cfg.HighDemandThreshold or DEFAULT_ADVISOR)
		OUT.suggestAdvisor =
			(OUT_demand.Residential >= th) or
			(OUT_demand.Commercial  >= th) or
			(OUT_demand.Industrial  >= th)
	end

	if not DemandEngine.RETURN_COPIES then
		return OUT
	end
	return {
		demand        = { Residential=OUT_demand.Residential, Commercial=OUT_demand.Commercial, Industrial=OUT_demand.Industrial, ResDense=OUT_demand.ResDense, CommDense=OUT_demand.CommDense, IndusDense=OUT_demand.IndusDense },
		pressure      = { toResidential=OUT_pressure.toResidential, toCommercial=OUT_pressure.toCommercial, toIndustrial=OUT_pressure.toIndustrial, cascade={ Residential=OUT_pressure.cascade.Residential, Commercial=OUT_pressure.cascade.Commercial, Industrial=OUT_pressure.cascade.Industrial }, share = { Residential=S_norm.share.Residential, Commercial=S_norm.share.Commercial, Industrial=S_norm.share.Industrial, ResDense=S_norm.share.ResDense, CommDense=S_norm.share.CommDense, IndusDense=S_norm.share.IndusDense }, total = OUT_pressure.total },
		suggestAdvisor= OUT.suggestAdvisor,
	}
end

return DemandEngine
