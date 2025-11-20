-- BuildingGeneratorModule.lua line 1
local BuildingGeneratorModule = {}
BuildingGeneratorModule.__index = BuildingGeneratorModule

-- References
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local BuildingManager = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("BuildingManager")
local SoundEmitter = require(ReplicatedStorage.Scripts.SoundEmitter)
local EventsFolder = ReplicatedStorage:WaitForChild("Events")
local RemoteEvents = EventsFolder:WaitForChild("RemoteEvents")
local PlayUISoundRE = RemoteEvents:FindFirstChild("PlayUISound")
local ServerScriptService = game:GetService("ServerScriptService")
local BE = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents")
local zoneRemovedEvent = BE:WaitForChild("ZoneRemoved")
local PadPoleSpawned = BE:WaitForChild("PadPoleSpawned")
-- Added for enhancements:
local zonePopulatedEvent = BE:WaitForChild("ZonePopulated")

-- BuildingsPlaced Event
local buildingsPlacedEvent = BE:WaitForChild("BuildingsPlaced")
local worldDirtyEvent = BE:FindFirstChild("WorldDirty")
local Wigw8mPlacedEvent = BE:WaitForChild("Wigw8mPlaced")

-- Grid Utilities
local Scripts = ReplicatedStorage:WaitForChild("Scripts")
local Sounds = require(Scripts:WaitForChild("Sounds"))
local GridConf = Scripts:WaitForChild("Grid")
local GridUtils = require(GridConf:WaitForChild("GridUtil"))
local GridConfig = require(GridConf:WaitForChild("GridConfig"))

-- Central Services
local QuadtreeService = require(ReplicatedStorage.Scripts.Optimize.Quadtree.QuadTreeSvc)

-- Building Master List
local BuildingMasterList = require(BuildingManager:WaitForChild("BuildingMasterList"))

-- Zone Tracker
local Build = script.Parent.Parent.Parent.Parent
local ZoneManager = Build:WaitForChild("ZoneManager")
local ZoneTrackerModule = require(ZoneManager:WaitForChild("ZoneTracker"))
local ZoneValidation 	= require(ZoneManager:WaitForChild("ZoneValidation"))
local ZoneDisplay		=require(ZoneManager:WaitForChild("ZoneDisplay"))
local Bld = ServerScriptService.Build
local LayerManagerModule = require(Bld.LayerManager)
local OverlayZoneTypes   = ZoneValidation.OverlayZoneTypes

-- Configuration
local BUILDING_INTERVAL = 0.25  -- seconds between stages (0.25)
local function getBuildingInterval()
	-- Use waitScaled where we actually sleep; this gives us a single source of truth.
	return BUILDING_INTERVAL
end
local GRID_SIZE = GridConfig.GRID_SIZE -- Ensure this matches your grid size in GridVisualizer
local Y_OFFSET = 0.4 -- Adjust as needed
local STAGE1_Y_OFFSET = -0.38

-- Configuration for Concrete Pad
local CONCRETE_PAD_HEIGHT = 0.2
local CONCRETE_PAD_MATERIAL = Enum.Material.Concrete
local CONCRETE_PAD_COLOR = Color3.fromRGB(128, 128, 128) -- Grey color
local OverlapExclusions = {
	WaterPipe       = true,
	Pipe            = true,
	PipeZone        = true,   -- some trackers store the literal zone type
	PowerLines      = true,
	MetroTunnel     = true,   -- << ADD`
	MetroTunnelZone = true,   -- << ADD (some systems prefix/alias the zoneType)
}


-- Debug Configuration
local DEBUG = false
local function debugPrint(...)
	if DEBUG then
		print("[BuildingGenerator]", ...)
	end
end

local AmbientZoneSoundConfig = {
	WindTurbine = {
		name = "Windmill",
		category = "Misc",
		volume = 0.2,
		RollOffMaxDistance = 350,
		RollOffMinDistance = 35,
		pitchRange = {0.95, 1.05},
		tag = "Ambient_Windmill",
	},
	GeothermalPowerPlant = {
		name = "Windmill",
		category = "Misc",
		volume = 0.12,
		RollOffMaxDistance = 275,
		RollOffMinDistance = 30,
		pitchRange = {0.9, 1.02},
		tag = "Ambient_Geo",
	},
	CoalPowerPlant = {
		name = "Factory",
		category = "Misc",
		volume = 0.25,
		RollOffMaxDistance = 400,
		RollOffMinDistance = 45,
		pitchRange = {0.95, 1.0},
		tag = "Ambient_Coal",
	},
}

local function addAmbientLoopForZone(zoneType: string, model: Instance?)
	local soundConfig = AmbientZoneSoundConfig[zoneType]
	if not soundConfig then
		return
	end
	if not model then
		return
	end

	local target = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not target then
		return
	end

	SoundEmitter.attachLoop({
		category = soundConfig.category,
		name = soundConfig.name,
		targetInstance = target,
		tag = soundConfig.tag,
		volume = soundConfig.volume,
		RollOffMaxDistance = soundConfig.RollOffMaxDistance,
		RollOffMinDistance = soundConfig.RollOffMinDistance,
		pitchRange = soundConfig.pitchRange,
	})
end

local function playBuildUISound(player: Player?)
	if PlayUISoundRE and player then
		PlayUISoundRE:FireClient(player, "Misc", "Build")
	end
end

local rng = Random.new()
local CONSTRUCTION_SFX_VARIANCE = {
	pitchMin = 0.92,
	pitchMax = 1.08,
	volumeMin = 0.9,
	volumeMax = 1.1,
}
local CONSTRUCTION_SFX_VOLUME_MULT = 0.6

local function assignToSFXGroup(sound: Sound)
	local masterGroup = SoundService:FindFirstChild("Master")
	if not masterGroup then
		return
	end
	local sfxGroup = masterGroup:FindFirstChild("SFX")
	if sfxGroup and sfxGroup:IsA("SoundGroup") then
		sound.SoundGroup = sfxGroup
	end
end

local function averageStagePosition(instances: { Instance }): Vector3?
	local total = Vector3.new()
	local count = 0
	for _, inst in ipairs(instances) do
		local cf
		if inst:IsA("Model") then
			local primary = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
			if primary then
				cf = primary.CFrame
			end
		elseif inst:IsA("BasePart") then
			cf = inst.CFrame
		end
		if cf then
			total += cf.Position
			count += 1
		end
	end
	if count == 0 then
		return nil
	end
	return total / count
end

local function startConstructionSound(stageClones: { Instance }, parentFolder: Instance?): { sound: Sound, anchor: BasePart }?
	local soundData = Sounds.Misc and Sounds.Misc.Construction
	if not soundData then
		return nil
	end

	local center = averageStagePosition(stageClones)
	if not center then
		return nil
	end

	local anchor = Instance.new("Part")
	anchor.Name = "_ConstructionSoundAnchor"
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Anchored = true
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(center)
	anchor.Parent = parentFolder or Workspace

	local sound = Instance.new("Sound")
	sound.Name = "_ConstructionSound"
	sound.SoundId = soundData.SoundId
	sound.RollOffMaxDistance = soundData.RollOffMaxDistance or sound.RollOffMaxDistance
	sound.RollOffMinDistance = soundData.RollOffMinDistance or sound.RollOffMinDistance
	local volumeScale = rng:NextNumber(CONSTRUCTION_SFX_VARIANCE.volumeMin, CONSTRUCTION_SFX_VARIANCE.volumeMax)
	sound.Volume = (soundData.Volume or sound.Volume) * volumeScale * CONSTRUCTION_SFX_VOLUME_MULT
	sound.Looped = true
	sound.PlaybackSpeed = rng:NextNumber(CONSTRUCTION_SFX_VARIANCE.pitchMin, CONSTRUCTION_SFX_VARIANCE.pitchMax)
	assignToSFXGroup(sound)
	sound.Parent = anchor
	sound:Play()

	return {
		sound = sound,
		anchor = anchor,
	}
end

local function stopConstructionSound(handle: { sound: Sound?, anchor: BasePart? }?)
	if not handle then
		return
	end
	local sound = handle.sound
	if sound then
		pcall(function()
			sound:Stop()
		end)
		sound:Destroy()
	end
	local anchor = handle.anchor
	if anchor then
		anchor:Destroy()
	end
end

-- Infrastructure-only zones do not need the 3D construction SFX.
local SILENT_BUILD_MODES = {
	DirtRoad    = true,
	Pavement    = true,
	Highway     = true,
	Road        = true,
	RoadZone    = true,
	PowerLines  = true,
	WaterPipe   = true,
	Utilities   = true,
	MetroTunnel = true,
}

local function shouldPlayConstructionAudio(mode: string?): boolean
	if not mode then
		return true
	end
	return not SILENT_BUILD_MODES[mode]
end

local BUILD_UI_MUTED_MODES = {
	Residential = true,
	Commercial  = true,
	Industrial  = true,
	ResDense    = true,
	CommDense   = true,
	IndusDense  = true,
}

local function shouldPlayBuildUISound(mode: string?): boolean
	if not mode then
		return true
	end
	return not BUILD_UI_MUTED_MODES[mode]
end

local BuildSpeed = {
	enabled    = true,  -- true in Studio, false on live by default
	multiplier = 10.0,                    -- 1.0 = normal; 4.0 = 4x faster; 0.5 = slower
}

local _refillBusy     = {}  -- key: uid|zoneId -> boolean
local _refillSeeds    = {}  -- key: uid|zoneId -> { [wealth]=set("x|z") }
local _refillFullScan = {}  -- key: uid|zoneId -> { mode=..., rotation=..., style=..., source=... }


local function _key(player, zoneId)
	local uid = (player and player.UserId) or 0
	return tostring(uid) .. "|" .. tostring(zoneId)
end

-- === Local helper inside BuildingGeneratorModule ===
local function _k(x, z) return tostring(x).."|"..tostring(z) end
local function _neighbors4(x, z)
	return { {x+1,z}, {x-1,z}, {x,z+1}, {x,z-1} }
end

-- keep cluster default aligned with CityInteractions
local CLUSTER_CONF = {
	max_cluster   = 64,
	diagonal      = false,   -- 4-neighbor connectivity by default
	yield_between = 0.02,    -- cooperative yield between clusters
}

local function _clusterCells(cells, conf)
	if not (cells and #cells > 0) then return {} end
	conf = conf or CLUSTER_CONF
	local diag = conf.diagonal
	local maxN = math.max(1, math.floor(tonumber(conf.max_cluster or 64) or 64))

	local remain = {}
	for _, c in ipairs(cells) do remain[_k(c.x, c.z)] = {x=c.x, z=c.z} end

	-- stable order for determinism
	table.sort(cells, function(a,b) return (a.x < b.x) or (a.x == b.x and a.z < b.z) end)

	local out = {}
	for _, seed in ipairs(cells) do
		local key = _k(seed.x, seed.z)
		local start = remain[key]
		if start then
			remain[key] = nil
			local q = { start }
			local i = 1
			local pack = {}
			while i <= #q do
				local p = q[i]; i += 1
				table.insert(pack, p)
				if #pack >= maxN then table.insert(out, pack); pack = {} end

				-- 4- or 8-neighbor
				local nbrs = _neighbors4(p.x, p.z)
				if diag then
					nbrs[#nbrs+1] = {p.x+1, p.z+1}
					nbrs[#nbrs+1] = {p.x-1, p.z+1}
					nbrs[#nbrs+1] = {p.x+1, p.z-1}
					nbrs[#nbrs+1] = {p.x-1, p.z-1}
				end
				for _, n in ipairs(nbrs) do
					local nk = _k(n[1], n[2])
					local nextCell = remain[nk]
					if nextCell then
						remain[nk] = nil
						table.insert(q, nextCell)
					end
				end
			end
			if #pack > 0 then table.insert(out, pack) end
		end
	end
	return out
end


local ROAD_ORIENTATION_RADIUS_CELLS = 4
local ROAD_ORIENTATION_RADIUS_STUDS = ROAD_ORIENTATION_RADIUS_CELLS * GRID_SIZE

local ROAD_ZONE_TYPES = {
	DirtRoad = true,
	Pavement = true,
	Highway = true,
}

local function _clampMult(m)
	m = tonumber(m) or 1
	if m < 0.01 then m = 0.01 end
	if m > 100 then m = 100 end
	return m
end

-- Public API (you can call these from anywhere)
function BuildingGeneratorModule.EnableFastBuild(on)
	BuildSpeed.enabled = not not on
end

function BuildingGeneratorModule.SetBuildSpeedMultiplier(m)
	BuildSpeed.multiplier = _clampMult(m)
end

function BuildingGeneratorModule.GetBuildSpeedMultiplier()
	return BuildSpeed.multiplier
end

-- Scaled waiting
local function waitScaled(seconds)
	seconds = tonumber(seconds) or 0
	if BuildSpeed.enabled then
		return task.wait(seconds / BuildSpeed.multiplier)
	else
		return task.wait(seconds)
	end
end

local function scaleDuration(seconds)
	seconds = tonumber(seconds) or 0
	if BuildSpeed.enabled then
		return seconds / BuildSpeed.multiplier
	else
		return seconds
	end
end

-- Optional: allow a BindableEvent to toggle at runtime if you already have a hub
-- (This is "listen if present"; it won't error if you don't create it.)
local okBE, EventsFolder = pcall(function()
	return ReplicatedStorage:FindFirstChild("Events")
end)
if okBE and EventsFolder and EventsFolder:FindFirstChild("BindableEvents") then
	local BE_local = EventsFolder.BindableEvents
	-- Create this optionally: ReplicatedStorage/Events/BindableEvents/SetBuildSpeed (BindableEvent)
	local SetBuildSpeed = BE_local:FindFirstChild("SetBuildSpeed")
	if SetBuildSpeed and SetBuildSpeed:IsA("BindableEvent") then
		SetBuildSpeed.Event:Connect(function(onOrMult, maybeMult)
			-- Accept either: SetBuildSpeed:Fire(true, 5) or SetBuildSpeed:Fire(5)
			if type(onOrMult) == "boolean" then
				BuildingGeneratorModule.EnableFastBuild(onOrMult)
				if maybeMult ~= nil then BuildingGeneratorModule.SetBuildSpeedMultiplier(maybeMult) end
			else
				BuildingGeneratorModule.EnableFastBuild(true)
				BuildingGeneratorModule.SetBuildSpeedMultiplier(onOrMult)
			end
		end)
	end
end

local STRICT_ABORT_ON_MISSING_ZONE = false

local Abort = {}  -- Abort[userId][zoneId] = true

local function _uid(p) return p and p.UserId end

local function markAbort(player, zoneId)
	local uid = _uid(player); if not uid or type(zoneId) ~= "string" then return end
	Abort[uid] = Abort[uid] or {}
	Abort[uid][zoneId] = true
end

local function clearAbort(player, zoneId)
	local uid = _uid(player); if not uid or type(zoneId) ~= "string" then return end
	if Abort[uid] then Abort[uid][zoneId] = nil end
end

local function shouldAbort(player, zoneId)
	-- explicit tombstone (ZoneRemoved) always wins
	local uid = _uid(player)
	if uid and Abort[uid] and Abort[uid][zoneId] then
		if DEBUG then
			print(("[BuildingGenerator][Abort] explicit tombstone for %s (user=%s)"):format(zoneId, tostring(uid)))
		end
		return true
	end

	-- tracker missing: only abort if policy says to do so
	local exists = ZoneTrackerModule.getZoneById(player, zoneId) ~= nil
	if not exists then
		if DEBUG then
			print(("[BuildingGenerator][Abort?] ZoneTracker missing entry for %s (STRICT=%s)"):format(
				zoneId, tostring(STRICT_ABORT_ON_MISSING_ZONE)))
		end
		return STRICT_ABORT_ON_MISSING_ZONE
	end

	return false
end

local function BuildingOccId(zoneId: string, gx: number, gz: number): string
	return ("building/%s_%d_%d"):format(zoneId, gx, gz)
end

-- Table to hold removed NatureZones (for undo)
local DECORATION_WEIGHT = 0.05   -- 5 % chance relative to normal; set to 0 to ban
local DEFAULT_WEIGHT    = 1
local boundsCache = {}

zoneRemovedEvent.Event:Connect(function(player, zoneId)
	-- Any in-flight populate for this zone should stop ASAP
	markAbort(player, zoneId)
end)

local function getGlobalBoundsForPlot(plot)
	local cached = boundsCache[plot]
	if cached then return cached.bounds, cached.terrains end

	local terrains = {}
	local unlocks  = plot:FindFirstChild("Unlocks")
	if unlocks then
		for _, zone in ipairs(unlocks:GetChildren()) do
			for _, seg in ipairs(zone:GetChildren()) do
				if seg:IsA("BasePart") and seg.Name:match("^Segment%d+$") then
					table.insert(terrains, seg)
				end
			end
		end
	end
	local testTerrain = plot:FindFirstChild("TestTerrain")
	if #terrains == 0 and testTerrain then
		table.insert(terrains, testTerrain)
	end

	local gb = GridConfig.calculateGlobalBounds(terrains)
	boundsCache[plot] = { bounds = gb, terrains = terrains }
	return gb, terrains
end

local function weightFor(building)
	-- Detect decorations by explicit flag, WealthState or folder name
	if building.isDecoration
		or (building.wealthState and building.wealthState == "Decorations")
		or (building.zoneType and building.zoneType == "Decorations")
	then
		return DECORATION_WEIGHT
	end
	return building.weight or DEFAULT_WEIGHT
end

local function chooseWeightedBuilding(list)
	local total = 0
	for _, b in ipairs(list) do
		local w = weightFor(b)
		if w > 0 then total += w end
	end
	if total == 0 then return nil end
	local r = math.random() * total
	for _, b in ipairs(list) do
		local w = weightFor(b)
		if w > 0 then
			r -= w
			if r <= 0 then return b end
		end
	end
	return list[#list]  
end

---------------------------------------------------------------------------
-- QUOTA SYSTEM (caps)
-- - Commercial: ComM1 <= 20% of all buildings placed in zone
-- - Commercial (Wealthy): ComW4 <= 20% of all buildings placed in zone
-- - CommDense: (HComP6 + HComP12 + HComP1) <= 20% of all buildings placed
---------------------------------------------------------------------------
local QUOTA_CAP = 0.20
local DECORATION_CAP = 0.20

local COMM_DENSE_CAP_MEMBERS = {
	HComP6  = true,
	HComP12 = true,
	HComP1  = true,
}

local function isDecorationName(mode, name)
	if not name or not mode then return false end
	-- Your naming scheme uses ResDec*, ComDec*, IndDec*
	local prefix = ({
		Residential = "ResDec",
		Commercial  = "ComDec",
		Industrial  = "IndDec",
		ResDense    = "ResDec",
		CommDense   = "ComDec",
		IndusDense  = "IndDec",
	})[mode]
	return prefix and string.sub(name, 1, #prefix) == prefix or false
end

local function newQuotaContext(mode, player, zoneId)
	return {
		mode   = mode,
		player = player,
		zoneId = zoneId,
		total  = 0,
		byName = {},
		group  = { CommDense = 0 },
	}
end

local function scanZoneCountsInto(ctx)
	local player = ctx.player
	local zoneId = ctx.zoneId
	if not player or not zoneId then return end
	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId)
	if not plot then return end
	local populated = plot:FindFirstChild("Buildings")
		and plot.Buildings:FindFirstChild("Populated")
	if not populated then return end

	-- init groups if missing
	ctx.group = ctx.group or {}
	ctx.group.CommDense   = ctx.group.CommDense or 0
	ctx.group.Decorations = ctx.group.Decorations or 0

	for _, folder in ipairs(populated:GetChildren()) do
		for _, inst in ipairs(folder:GetChildren()) do
			if (inst:IsA("Model") or inst:IsA("BasePart"))
				and inst:GetAttribute("ZoneId") == zoneId
			then
				ctx.total += 1
				local nm = inst:GetAttribute("BuildingName")
				if nm then
					ctx.byName[nm] = (ctx.byName[nm] or 0) + 1
					if ctx.mode == "CommDense" and COMM_DENSE_CAP_MEMBERS[nm] then
						ctx.group.CommDense = (ctx.group.CommDense or 0) + 1
					end
					if isDecorationName(ctx.mode, nm) then
						ctx.group.Decorations = (ctx.group.Decorations or 0) + 1
					end
				end
			end
		end
	end
end

local function wouldViolateQuota(ctx, mode, wealth, buildingName)
	if ctx and ctx.strictRestore then
		return false  -- never block saved blueprints
	end

	if not ctx then return false end
	local totalAfter = (ctx.total or 0) + 1

	-- Commercial (Wealthy): limit ComW4
	if mode == "Commercial" and wealth == "Wealthy" and buildingName == "ComW4" then
		local curr = ctx.byName["ComW4"] or 0
		if ((curr + 1) / totalAfter) > QUOTA_CAP then
			return true
		end
	end

	-- Commercial: limit ComM1 (any wealth) to 20%
	if mode == "Commercial" and wealth == "Medium" and buildingName == "ComM1" then
		local curr = ctx.byName["ComM1"] or 0
		if ((curr + 1) / totalAfter) > QUOTA_CAP then
			return true
		end
	end

	-- CommDense: limit aggregate HComP6/HComP12/HComP1
	if mode == "CommDense" and COMM_DENSE_CAP_MEMBERS[buildingName] then
		local curr = ctx.group.CommDense or 0
		if ((curr + 1) / totalAfter) > 0.1 then
			return true
		end
	end

	-- Decorations: max 20% across zone
	if isDecorationName(mode, buildingName) then
		local curr = ctx.group.Decorations or 0
		if ((curr + 1) / totalAfter) > DECORATION_CAP then
			return true
		end
	end

	return false
end

local function chooseWeightedBuildingWithQuota(list, mode, wealth, ctx)
	local pool, totalW = {}, 0
	for _, b in ipairs(list or {}) do
		if b and b.name and not wouldViolateQuota(ctx, mode, wealth, b.name) then
			local w = weightFor(b)
			if w > 0 then
				totalW += w
				table.insert(pool, { b = b, w = w })
			end
		end
	end
	if totalW <= 0 then
		return nil -- defer this cell; second pass will try again
	end
	local r = math.random() * totalW
	for _, rec in ipairs(pool) do
		r -= rec.w
		if r <= 0 then return rec.b end
	end
	return pool[#pool].b
end

local function recordQuotaPlacement(ctx, mode, wealth, buildingName)
	if not ctx then return end
	ctx.total = (ctx.total or 0) + 1
	if buildingName then
		ctx.byName[buildingName] = (ctx.byName[buildingName] or 0) + 1
		if mode == "CommDense" and COMM_DENSE_CAP_MEMBERS[buildingName] then
			ctx.group.CommDense = (ctx.group.CommDense or 0) + 1
		end
	end
end
-- /QUOTA SYSTEM
---------------------------------------------------------------------------

local function _getInstanceCFrame(inst : Instance) : CFrame?
	if inst:IsA("Model") then
		local ok, cf = pcall(function() return inst:GetPivot() end)
		if ok and typeof(cf) == "CFrame" then
			return cf
		end
		if inst.PrimaryPart then
			return inst.PrimaryPart.CFrame
		end
		return nil
	elseif inst:IsA("BasePart") then
		return inst.CFrame
	end
	return nil
end

-- Helper function to wait for a specified duration
local function waitFor(seconds)
	task.wait(seconds)
end

--Rotation Helper
local RANDOM_ROTATION_ZONES = {
	Residential   = true, Commercial = true, Industrial = true,
	ResDense      = true, CommDense   = true, IndusDense = true,
}

local CARDINALS = { 0, 90, 180, 270 }

local function pickRotation(zoneMode : string, requested : number?)
	-- zoneMode     : "Residential", "Road", ...
	-- requested    : what the caller supplied, may be nil

	if RANDOM_ROTATION_ZONES[zoneMode] then
		-- Engine decides ⇒ ignore anything the caller sent.
		return CARDINALS[math.random(#CARDINALS)]
	end

	-- Player‑driven zone: insist on a caller‑supplied heading
	if requested == nil then
		warn(("[BuildingGenerator] No rotation supplied for zone type ‘%s’; defaulting to 0°")
			:format(zoneMode))
		return 0
	end

	-- Normalise to [0,360)
	local rot = requested % 360
	if rot % 90 ~= 0 then
		warn(("[BuildingGenerator] Rotation %d for zone ‘%s’ is not a multiple of 90; rounding")
			:format(rot, zoneMode))
		rot = CARDINALS[math.floor((rot+45)/90) % 4 + 1]        -- 28°→0, 134°→90 …
	end
	return rot
end

--Helpers 09262025
local function _stage3FootprintCells(buildingName : string, rotY : number)
	rotY = (rotY or 0) % 360
	local data = BuildingMasterList.getBuildingByName(buildingName)
	if not data or not data.stages or not data.stages.Stage3 then
		return 1, 1 -- safe fallback
	end
	local stg3 = data.stages.Stage3
	local size = (stg3:IsA("Model") and stg3.PrimaryPart and stg3.PrimaryPart.Size) or stg3.Size
	if not size then return 1, 1 end

	local w = math.ceil(size.X / GRID_SIZE)
	local d = math.ceil(size.Z / GRID_SIZE)
	if rotY == 90 or rotY == 270 then w, d = d, w end
	return w, d
end

local function isIndividualMode(mode : string?)
	if not mode then return false end
	if RANDOM_ROTATION_ZONES[mode] then return false end
	if mode == "Road" or mode == "Utilities" then return false end
	return true
end

-- Square test using building *data* (not an instance)
local function isSquareFootprintByData(buildingData) : boolean
	if not (buildingData and buildingData.stages and buildingData.stages.Stage3) then
		return false
	end
	local stg3 = buildingData.stages.Stage3
	local size = (stg3:IsA("Model") and stg3.PrimaryPart and stg3.PrimaryPart.Size) or stg3.Size
	if not size then return false end
	local w = math.ceil(size.X / GRID_SIZE)
	local d = math.ceil(size.Z / GRID_SIZE)
	return w == d
end

-- Snap any angle to the closer of {0, 180}
local function snapTo0or180(deg : number) : number
	local m = ((deg or 0) % 360 + 360) % 360
	local dist0   = math.min(m, 360 - m)       -- circular distance to 0°
	local dist180 = math.abs(180 - m)
	return (dist180 <= dist0) and 180 or 0
end

BuildingGeneratorModule._stage3FootprintCells = _stage3FootprintCells

-- Helper: remove ZoneTracker occupancy & quadtree for a single placed instance
local function _clearOccupancyForInstance(player, zoneId, inst : Instance)
	if not inst then return end
	local gx = inst:GetAttribute("GridX")
	local gz = inst:GetAttribute("GridZ")
	local rotY = inst:GetAttribute("RotationY") or 0
	local bname = inst:GetAttribute("BuildingName")
	if not (gx and gz and bname) then return end

	local w, d = _stage3FootprintCells(bname, rotY)
	local buildingId = ("%s_%d_%d"):format(zoneId, gx, gz)

	for x = gx, gx + w - 1 do
		for z = gz, gz + d - 1 do
			ZoneTrackerModule.unmarkGridOccupied(player, x, z, 'building', buildingId)
		end
	end

	-- Best-effort: remove from quadtree if a remover exists
	if QuadtreeService and typeof(QuadtreeService.removeById) == "function" then
		pcall(function() QuadtreeService:removeById(buildingId) end)
	end
end


local function removeAndArchiveUnderlyingBuildings(player, zoneId, gridX, gridZ, width, depth)
	-- overlay rectangle
	local ax1, az1 = gridX, gridZ
	local ax2, az2 = gridX + width  - 1, gridZ + depth - 1

	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId)
	if not plot then return {} end

	local populated = plot:FindFirstChild("Buildings")
		and plot.Buildings:FindFirstChild("Populated")
	if not populated then return {} end

	local impactedZones = {}

	-- axis-aligned rectangle overlap (grid space)
	local function rectsOverlap(bx1, bz1, bw, bd)
		local bx2, bz2 = bx1 + bw - 1, bz1 + bd - 1
		return not (bx2 < ax1 or bx1 > ax2 or bz2 < az1 or bz1 > az2)
	end

	for _, folder in ipairs(populated:GetChildren()) do
		for _, inst in ipairs(folder:GetChildren()) do
			if (inst:IsA("Model") or inst:IsA("BasePart")) then
				local gx   = inst:GetAttribute("GridX")
				local gz   = inst:GetAttribute("GridZ")
				local rotY = inst:GetAttribute("RotationY") or 0
				local bnm  = inst:GetAttribute("BuildingName")

				if gx and gz and bnm then
					-- compute this instance’s footprint in grid cells
					local w, d = _stage3FootprintCells(bnm, rotY)
					if rectsOverlap(gx, gz, w, d) then
						-- remember which original zone we’re about to affect
						local originalZoneId = inst:GetAttribute("ZoneId")
						if originalZoneId and originalZoneId ~= zoneId then
							impactedZones[originalZoneId] = true
						end

						-- capture transform before destroying
						local cf = _getInstanceCFrame(inst)

						-- build an occupancy id consistent with generateBuilding()
						local occId = (originalZoneId or "Unknown") .. "_" .. tostring(gx) .. "_" .. tostring(gz)

						-- archive the full record so an undo can faithfully restore
						LayerManagerModule.storeRemovedObject("Buildings", zoneId, {
							instanceClone  = inst:Clone(),
							parentName     = folder.Name, -- e.g. "Zone_..."/"Utilities"
							cframe         = cf,
							gridX          = gx,
							gridZ          = gz,
							rotation       = rotY,
							wealthState    = inst:GetAttribute("WealthState"),
							isUtility      = inst:GetAttribute("IsUtility") or false,
							occupantType   = "building",
							occupantId     = occId,
							mode           = (function()
								if originalZoneId then
									local z = ZoneTrackerModule.getZoneById(player, originalZoneId)
									return z and z.mode or nil
								end
							end)(),
							zoneId         = originalZoneId,
						})

						-- clear occupancy & quadtree for the whole footprint
						_clearOccupancyForInstance(player, originalZoneId or zoneId, inst)

						-- remove the instance
						inst:Destroy()
					end
				end
			end
		end
	end

return impactedZones
end

local function footprintHasBlockingOccupant(player, zoneId, startX, startZ, width, depth)
	if not player then return false end
	for x = startX, startX + width - 1 do
		for z = startZ, startZ + depth - 1 do
			if ZoneTrackerModule.isGridOccupied(player, x, z, {
				excludeOccupantId = zoneId,
				excludeOccupantType = "zone",
			}) then
				return true
			end
		end
	end
	return false
end

-- Helper: Check 2D AABB u (only X and Z axes)
local function aabbOverlap2D(pos1, size1, pos2, size2)
	local half1 = size1 * 0.5
	local half2 = size2 * 0.5
	if math.abs(pos1.X - pos2.X) <= (half1.X + half2.X) and math.abs(pos1.Z - pos2.Z) <= (half1.Z + half2.Z) then
		return true
	end
	return false
end

-- Helper function to create a concrete pad beneath the building (accounting for rotation)
local function createConcretePad(buildingModel)
	local primaryPart = buildingModel.PrimaryPart
	if not primaryPart then
		warn("createConcretePad: Building model does not have a PrimaryPart.")
		return
	end

	-- Calculate the size of the pad based on the PrimaryPart's size
	local padSize = Vector3.new(primaryPart.Size.X, CONCRETE_PAD_HEIGHT, primaryPart.Size.Z)

	-- Create the pad
	local concretePad = Instance.new("Part")
	concretePad.Name = "ConcretePad"
	concretePad.Size = padSize
	concretePad.Anchored = true
	concretePad.Material = CONCRETE_PAD_MATERIAL
	concretePad.Color = CONCRETE_PAD_COLOR
	concretePad.CanCollide = false
	concretePad.CanQuery = false

	-- Compute how far down the pad should go, in local space
	local yOffset = (primaryPart.Size.Y / 2) - 0.01 + (CONCRETE_PAD_HEIGHT / 2)

	-- Create an offset CFrame that just moves us down in local space
	local offsetCFrame = CFrame.new(0, -yOffset, 0)

	-- Position the pad relative to the building's PrimaryPart, preserving rotation
	concretePad.CFrame = primaryPart.CFrame * offsetCFrame

	-- Parent the pad to the building model
	concretePad.Parent = buildingModel
end

--Powerline integration start---------------------------------------------------------------------------------------------------

local MAX_DROPS_PER_POLE = 1        -- how many buildings per pad-pole
local MAX_DROP_DISTANCE  = 45       -- studs from pole to building centre
local ROOF_CLEARANCE     = 1.2      -- studs above roof for nicer sag
local IGNORE_FOR_SERVICE_DROP = { ConcretePad = true }

local DECOR_PADPOLE_CHANCE = 0.10

local prefab  = BuildingMasterList.getPowerLinesByStyle("Default")[1]and BuildingMasterList.getPowerLinesByStyle("Default")[1].stages.Stage3
local electricBoxPrefab = BuildingMasterList.getIndividualBuildingByName("Power", "Default", "ElectricBox") and BuildingMasterList.getIndividualBuildingByName("Power", "Default", "ElectricBox")[1]

-- Spawns extra, unconnected "ambient" pad-poles in a single building zone
-- chance: 0.0–1.0 (default 0.10)
function BuildingGeneratorModule.spawnAmbientPadPolesInZone(player, bldZoneId, chance)
	chance = tonumber(chance) or 0.10
	if chance < 0 then chance = 0 end
	if chance > 1 then chance = 1 end

	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId); if not plot then return end
	local populated = plot:FindFirstChild("Buildings") and plot.Buildings:FindFirstChild("Populated"); if not populated then return end
	local zoneFolder = populated:FindFirstChild(bldZoneId); if not zoneFolder then return end

	local function _hasPadPole(model: Instance): boolean
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("Model") and (d.Name == "PadPole" or d:GetAttribute("IsPadPole") == true) then
				return true
			end
		end
		return false
	end

	local function _randCornerOffset(pad: BasePart)
		local dx, dz = pad.Size.X * 0.5, pad.Size.Z * 0.5
		local corners = {
			Vector3.new( dx, pad.Size.Y * 0.5,  dz),
			Vector3.new(-dx, pad.Size.Y * 0.5,  dz),
			Vector3.new( dx, pad.Size.Y * 0.5, -dz),
			Vector3.new(-dx, pad.Size.Y * 0.5, -dz),
		}
		return corners[math.random(#corners)]
	end

	for _, b in ipairs(zoneFolder:GetChildren()) do
		if (b:IsA("Model") or b:IsA("BasePart")) and b:GetAttribute("ZoneId") == bldZoneId then
			-- only consider buildings that actually have a ConcretePad and no pad-pole yet
			local pad = b:FindFirstChild("ConcretePad")
			if pad and not _hasPadPole(b) then
				if math.random() < chance then
					-- clone the default pole prefab; do not stamp PowerLineZoneId
					local poleStage = prefab
					if poleStage then
						local pole = poleStage:Clone()
						pole.Name = "PadPole"
						local cf = pad.CFrame * CFrame.new(_randCornerOffset(pad))
						if pole:IsA("Model") and pole.PrimaryPart then
							pole:SetPrimaryPartCFrame(cf)
						elseif pole:IsA("BasePart") then
							pole.CFrame = cf
						end
						pole.Parent = b
						pole:SetAttribute("IsPadPole", true)
						pole:SetAttribute("AmbientPadPole", true) -- helpful tag for debugging/cleanup
						-- NOTE: no PadPoleSpawned event and no service-drop ropes → remains unconnected by design
					end
				end
			end
		end
	end
end


local function spawnDecorPadPole(buildingModel: Model, polePrefab: Instance)
	if not (buildingModel and polePrefab) then return end
	local pad = buildingModel:FindFirstChild("ConcretePad")
	if not (pad and pad:IsA("BasePart")) then return end

	-- Prefer a corner away from any existing PadPoles on this building
	local function _poleWorldPos(m: Instance)
		if m:IsA("Model") then
			return (m.PrimaryPart and m.PrimaryPart.Position) or m:GetPivot().Position
		elseif m:IsA("BasePart") then
			return m.Position
		end
		return nil
	end

	local existing = {}
	for _, d in ipairs(buildingModel:GetDescendants()) do
		if d:IsA("Model") and (d.Name == "PadPole" or d:GetAttribute("IsPadPole") == true) then
			table.insert(existing, d)
		end
	end

	local dx, dz = pad.Size.X * 0.5, pad.Size.Z * 0.5
	local corners = {
		Vector3.new( dx, pad.Size.Y * 0.5,  dz),
		Vector3.new(-dx, pad.Size.Y * 0.5,  dz),
		Vector3.new( dx, pad.Size.Y * 0.5, -dz),
		Vector3.new(-dx, pad.Size.Y * 0.5, -dz),
	}

	-- Choose the corner farthest from any existing PadPole (simple spacing)
	local bestIdx, bestScore = 1, -math.huge
	for i, off in ipairs(corners) do
		local wpos = (pad.CFrame * CFrame.new(off)).Position
		local minDist = math.huge
		for _, p in ipairs(existing) do
			local pp = _poleWorldPos(p)
			if pp then
				local d = (pp - wpos).Magnitude
				if d < minDist then minDist = d end
			end
		end
		local score = (minDist == math.huge) and 9e9 or minDist
		if score > bestScore then bestScore, bestIdx = score, i end
	end

	local off = corners[bestIdx]
	local pole = polePrefab:Clone()
	pole.Name = "PadPole"
	if pole:IsA("Model") and pole.PrimaryPart then
		pole:SetPrimaryPartCFrame(pad.CFrame * CFrame.new(off))
	elseif pole:IsA("BasePart") then
		pole.CFrame = pad.CFrame * CFrame.new(off)
	end
	pole.Parent = buildingModel

	-- Tag but DO NOT connect; no service drops; no PadPoleSpawned event
	pole:SetAttribute("IsPadPole", true)
	pole:SetAttribute("IsDecorPadPole", true) -- marker (optional)
	pole:SetAttribute("NoAutoLink", true)     -- marker (optional)
end

local function parentPlot(inst)
	-- climb ancestors until we hit “Plot_12345”, or nil
	local ptr = inst
	while ptr and ptr.Parent do
		if ptr.Name:match("^Plot_%d+$") then return ptr end
		ptr = ptr.Parent
	end
end

local function buildingCenter(model : Model)
	-- use full bounding box instead of PrimaryPart alone
	local cf, _ = model:GetBoundingBox()
	return cf.Position
end

local WEALTHED_ZONES : { [string]: boolean } = {
	Residential = true, Commercial = true, Industrial = true,
	ResDense    = true, CommDense   = true, IndusDense   = true,
}

---------------------------------------------------------------------
-- gather candidate buildings *only inside the same plot* and
-- return them sorted by distance (nearest first) -------------------
---------------------------------------------------------------------

local function hasGrassPart(model : Model) : boolean
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local mat = d.Material
			if mat == Enum.Material.Grass      -- classic grass
				or mat == Enum.Material.LeafyGrass   -- newer material
			then
				return true
			end
		end
	end
	return false
end

local function getGrassPart(model : Model)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local m = p.Material
			if m == Enum.Material.Grass or m == Enum.Material.LeafyGrass then
				return p
			end
		end
	end
	return nil
end

local function _hasDecToken(s : any) : boolean
	return type(s) == "string" and string.find(string.lower(s), "dec", 1, true) ~= nil
end

local function _tileWealthForPlacement(mode, defaultWealthState, player, zoneId, x, z)
	local w = defaultWealthState or "Poor"
	if WEALTHED_ZONES[mode] and typeof(ZoneTrackerModule.getGridWealth) == "function" then
		local isPop = typeof(ZoneTrackerModule.isZonePopulating) == "function"
			and ZoneTrackerModule.isZonePopulating(player, zoneId)
		if not isPop then
			w = ZoneTrackerModule.getGridWealth(player, zoneId, x, z) or w
		end
	end
	return w
end

local function isDecorModel(model : Instance) : boolean
	if not (model and model:IsA("Model")) then return false end
	-- Heuristics: model name, WealthState attribute, or any descendant part name
	if _hasDecToken(model.Name) then return true end
	local ws = model:GetAttribute("WealthState")
	if ws and tostring(ws) == "Decorations" then return true end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and _hasDecToken(d.Name) then
			return true
		end
	end
	return false
end

local function getPoleAttachmentsOnBaseParts(padPole : Instance)
	local found = {}
	for _, a in ipairs(padPole:GetDescendants()) do
		if a:IsA("Attachment") and (a.Name == "1" or a.Name == "2") then
			if a.Parent and a.Parent:IsA("BasePart") then
				table.insert(found, a)
			end
		end
	end
	table.sort(found, function(a,b) return a.Name < b.Name end) -- "1" then "2"
	return found
end

---------------------------------------------------------------------
-- build-side helper: fabricate a random “ServiceIn” attachment
---------------------------------------------------------------------
local function createRoofAttachment(model : Model, exclude : Instance?)
	-- helper: is this BasePart OK to use?
	local function ok(p : Instance)
		return p:IsA("BasePart")
			and not IGNORE_FOR_SERVICE_DROP[p.Name]     
			and not (exclude and p:IsDescendantOf(exclude))  
			and not _hasDecToken(p.Name)                     
	end

	-- Prefer PrimaryPart if valid
	local pp = model.PrimaryPart
	if pp and ok(pp) then
		local att = Instance.new("Attachment")
		att.Name     = "ServiceIn"
		att.Position = Vector3.new(0, pp.Size.Y * 0.5 + ROOF_CLEARANCE, 0) -- local space
		att.Parent   = pp
		return att
	end

	-- Otherwise pick the top-most valid BasePart (not the pole, not the pad)
	local host, topY = nil, -math.huge
	for _, p in ipairs(model:GetDescendants()) do
		if ok(p) then
			local y = p.Position.Y + p.Size.Y * 0.5
			if y > topY then host, topY = p, y end
		end
	end
	if not host then return nil end

	local rx = (math.random() - 0.5) * host.Size.X
	local rz = (math.random() - 0.5) * host.Size.Z
	local att = Instance.new("Attachment")
	att.Name     = "ServiceIn"
	att.Position = Vector3.new(rx, host.Size.Y * 0.5 + ROOF_CLEARANCE, rz) -- local
	att.Parent   = host
	return att
end

---------------------------------------------------------------------
-- single rope helper
---------------------------------------------------------------------
local function makeDropRope(att0 : Attachment, att1 : Attachment)
	local rope            = Instance.new("RopeConstraint")
	rope.Attachment0      = att0
	rope.Attachment1      = att1
	rope.Visible          = true
	rope.Color            = BrickColor.new("Black")
	rope.Thickness        = 0.05
	rope.WinchEnabled     = false
	rope.Restitution      = 0
	local span            = (att0.WorldPosition - att1.WorldPosition).Magnitude
	rope.Length           = span + 0.75          -- small slack
	rope.Parent           = att0.Parent
end
---------------------------------------------------------------------
-- gather candidate buildings around a point (no pre-tagging needed)
---------------------------------------------------------------------
local function findNearbyBuildings(padPole : Instance, radius : number)
	local plot   = parentPlot(padPole)
	if not plot then return {} end

	local origin = (padPole:IsA("Model") and padPole.PrimaryPart and padPole.PrimaryPart.Position)
		or (padPole:IsA("BasePart") and padPole.Position)
	if not origin then return {} end

	local populated = plot:FindFirstChild("Buildings")
		and plot.Buildings:FindFirstChild("Populated")
	if not populated then return {} end

	local candidates = {}
	for _, folder in ipairs(populated:GetChildren()) do
		for _, inst in ipairs(folder:GetChildren()) do
			if inst:IsA("Model") and not hasGrassPart(inst) then
				local centre = buildingCenter(inst)
				local dist   = (centre - origin).Magnitude
				if dist <= radius then
					table.insert(candidates, {m = inst, d = dist})
				end
			end
		end
	end
	table.sort(candidates, function(a,b) return a.d < b.d end)   -- nearest first
	return candidates
end

---------------------------------------------------------------------
-- PUBLIC: call from spawnPadPowerPoles after you parent the new pole
---------------------------------------------------------------------
local function attachRandomServiceDrops(padPole : Instance)
	local poleAtt = getPoleAttachmentsOnBaseParts(padPole)
	if #poleAtt < 2 then
		warn("attachRandomServiceDrops: need attachments '1' and '2' on BaseParts")
		return
	end

	local cand = findNearbyBuildings(padPole, MAX_DROP_DISTANCE)
	if #cand == 0 then return end

	-- walk outward until we find a non-Dec house with a valid roof attachment
	local roofAtt, targetModel
	for _, rec in ipairs(cand) do
		if not isDecorModel(rec.m) then
			local att = createRoofAttachment(rec.m, padPole) -- still excludes the pole/pad
			if att then
				roofAtt     = att
				targetModel = rec.m
				break
			end
		end
	end
	if not roofAtt then return end

	makeDropRope(poleAtt[1], roofAtt)
	makeDropRope(poleAtt[2], roofAtt)

	if DEBUG then
		print("[ServiceDrop]",
			"target:", targetModel and targetModel.Name or "nil",
			"span:", (poleAtt[1].WorldPosition - roofAtt.WorldPosition).Magnitude
		)
	end
end

local function spawnElectricBox(buildingModel : Model, prefab, targetPart : BasePart)
	if not (prefab and targetPart) then return end

	-- Stage 3 of the prefab
	local box = prefab.stages
		and prefab.stages.Stage3
		and prefab.stages.Stage3:Clone()
	if not box then return end

	-- ↑ This is the only line you need to tweak ↓
	if box:IsA("Model") and box.PrimaryPart then
		box:SetPrimaryPartCFrame(targetPart.CFrame * CFrame.new(0, 0.5, 0))
	else
		box.CFrame = targetPart.CFrame * CFrame.new(0, 0.5, 0)
	end

	box.Name   = "ElectricBox"
	box.Parent = buildingModel
end


--Spawn powerpoles at concrete pad helper function
local function spawnPadPowerPoles(buildingModel, polePrefab)
	local grassPart = getGrassPart(buildingModel)
	if grassPart then
		if math.random() < 0.25 then                   -- 25 % roll
			spawnElectricBox(buildingModel, electricBoxPrefab, grassPart)
		end
		return                                         -- never place a pole on grass
	end

	local pad = buildingModel:FindFirstChild("ConcretePad")
	if not (pad and polePrefab) then return end           -- nothing to do

	-- 25 % chance that *this pad* gets a pole
	if math.random() >= 0.25 then return end

	-- local-space corner offsets (pad Y centre == top face)
	local dx, dz  =  pad.Size.X * 0.5,  pad.Size.Z * 0.5
	local offsets = {
		Vector3.new( dx, pad.Size.Y * 0.5,  dz),
		Vector3.new(-dx, pad.Size.Y * 0.5,  dz),
		Vector3.new( dx, pad.Size.Y * 0.5, -dz),
		Vector3.new(-dx, pad.Size.Y * 0.5, -dz),
	}

	-- choose one corner at random
	local off = offsets[math.random(#offsets)]

	local pole = polePrefab:Clone()
	pole.Name  = "PadPole"
	if pole:IsA("Model") and pole.PrimaryPart then
		pole:SetPrimaryPartCFrame(pad.CFrame * CFrame.new(off))
	else
		pole.CFrame = pad.CFrame * CFrame.new(off)
	end
	pole.Parent = buildingModel
	pole:SetAttribute("IsPadPole", true)
	attachRandomServiceDrops(pole)

	local zid = buildingModel:GetAttribute("ZoneId")
	if zid then
		local uidStr = zid:match("_(%d+)_") or zid:match("_(%d+)$")
		local uid    = uidStr and tonumber(uidStr)
		if uid then
			local plr = game:GetService("Players"):GetPlayerByUserId(uid)
			if plr then
				PadPoleSpawned:Fire(plr, pole)
			end
		end
	end

end



function BuildingGeneratorModule.spawnPadPowerPoles(buildingModel, polePrefab, attrTable)
	-- Use default power line prefab if none is supplied
	polePrefab = polePrefab or prefab

	-- Helper: find the building's ConcretePad (we place on pad corners)
	local pad = buildingModel:FindFirstChild("ConcretePad")
	-- Helper: get any existing PadPole on this building
	local function _findExistingPadPole(model: Instance)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("Model") and d.Name == "PadPole" then
				return d
			end
			-- a safety alias: some prefabs might stamp IsPadPole
			if (d:IsA("Model") or d:IsA("BasePart")) and d:GetAttribute("IsPadPole") == true then
				-- bubble up to the Model if the attr was set on a BasePart
				local m = d:IsA("Model") and d or d:FindFirstAncestorOfClass("Model")
				if m then return m end
			end
		end
		return nil
	end

	-- Helper: choose the corner offset of the pad nearest to a world position
	local function _nearestPadCornerOffset(padPart: BasePart, targetWorld: Vector3)
		local dx, dz = padPart.Size.X * 0.5, padPart.Size.Z * 0.5
		local corners = {
			Vector3.new( dx, padPart.Size.Y * 0.5,  dz),
			Vector3.new(-dx, padPart.Size.Y * 0.5,  dz),
			Vector3.new( dx, padPart.Size.Y * 0.5, -dz),
			Vector3.new(-dx, padPart.Size.Y * 0.5, -dz),
		}
		if typeof(targetWorld) ~= "Vector3" then
			return corners[1]
		end
		local best, bestIdx = math.huge, 1
		for i, c in ipairs(corners) do
			local wpos = (padPart.CFrame * CFrame.new(c)).Position
			local d    = (wpos - targetWorld).Magnitude
			if d < best then best, bestIdx = d, i end
		end
		return corners[bestIdx]
	end

	-- Are we being told to *guarantee* a pad-pole on this building?
	local force = attrTable and (attrTable.ForceSpawn == true or attrTable.ForcePadPole == true) or false
	local targetWorld = attrTable and attrTable.TargetWorldPos

	-- If NOT forced, keep legacy (random) behavior by delegating to the internal helper.
	if not force then
		-- This is your existing local helper defined above in the same module.
		-- It places at 25% chance and adds service‑drop ropes.
		spawnPadPowerPoles(buildingModel, polePrefab)
		return
	end

	-- From here on: **Forced** (100%) placement.
	if not polePrefab then
		warn("[PadPoleWrapper] No polePrefab available; cannot ForceSpawn.")
		return
	end
	if not pad then
		warn("[PadPoleWrapper] ForceSpawn requested but building has no ConcretePad.")
		return
	end

	-- Reuse existing pole if present; otherwise create one.
	local pole = _findExistingPadPole(buildingModel)
	local cornerOffset = _nearestPadCornerOffset(pad, targetWorld)

	if pole then
		-- Reposition existing pole to the nearest corner when a TargetWorldPos was provided
		if typeof(targetWorld) == "Vector3" then
			if pole:IsA("Model") then
				pole:PivotTo(pad.CFrame * CFrame.new(cornerOffset))
			elseif pole:IsA("BasePart") then
				pole.CFrame = pad.CFrame * CFrame.new(cornerOffset)
			end
		end
	else
		-- Create the pole at the chosen corner
		pole = polePrefab:Clone()
		pole.Name = "PadPole"
		if pole:IsA("Model") and pole.PrimaryPart then
			pole:SetPrimaryPartCFrame(pad.CFrame * CFrame.new(cornerOffset))
		elseif pole:IsA("BasePart") then
			pole.CFrame = pad.CFrame * CFrame.new(cornerOffset)
		end
		pole.Parent = buildingModel
		pole:SetAttribute("IsPadPole", true)

		-- Add the house service‑drop ropes the same as before
		attachRandomServiceDrops(pole)
	end

	-- Apply any attributes passed via attrTable (including PowerLineZoneId)
	if attrTable then
		for k, v in pairs(attrTable) do
			pole:SetAttribute(k, v)
		end
	end

	-- Emit spawn event so PowerGeneratorModule can link this pad‑pole into the correct power zone immediately
	do
		local zid = buildingModel:GetAttribute("ZoneId")
		if zid then
			local uidStr = zid:match("_(%d+)_") or zid:match("_(%d+)$")
			local uid    = uidStr and tonumber(uidStr)
			if uid then
				local plr = game:GetService("Players"):GetPlayerByUserId(uid)
				if plr then
					PadPoleSpawned:Fire(plr, pole)
				end
			end
		end
	end
end


--Powerline integration end

-- Function to check if a building can be placed at the given grid coordinates
function BuildingGeneratorModule.canPlaceBuilding(player, zoneBounds, buildingSize, startX, startZ, zoneId, mode)
	local endX = startX + buildingSize.width  - 1
	local endZ = startZ + buildingSize.depth - 1
	if  startX < zoneBounds.minX or startZ < zoneBounds.minZ
		or endX > zoneBounds.maxX  or endZ > zoneBounds.maxZ
	then
		return false
	end

	-- Overlay may sit on others, but still must not trample an active reservation
	if OverlayZoneTypes[mode] then
		return not GridUtils.anyReservationsBlocked(player, zoneId, startX, startZ, buildingSize.width, buildingSize.depth)
	end

	for x = startX, endX do
		for z = startZ, endZ do
			if GridUtils.isReservedByOther(player, zoneId, x, z) then
				return false
			end
			if ZoneTrackerModule.isGridOccupied(
				player, x, z,
				{ excludeOccupantId = zoneId, excludeZoneTypes = OverlapExclusions }
				) then
				return false
			end
		end
	end
	return true
end

-- Generate buildings at specific Grid Coordinates
function BuildingGeneratorModule.generateBuilding(
	terrain, parentFolder, player, zoneId, mode, gridCoord, buildingData,
	isUtility, rotationY, onPlaced, wealthState, skipStages, existingReservationHandle,
	quotaCtx
)
	skipStages = skipStages or false
	rotationY  = rotationY or 0

	-- Adopt any passed-in reservation handle immediately and install helpers
	local resHandle = existingReservationHandle
	local function _releaseReservation()
		if resHandle then
			GridUtils.releaseReservation(resHandle)
			resHandle = nil
		end
	end
	local function _abortEarly(msg)
		if msg then warn(msg) end
		_releaseReservation()
		return
	end

	-- Early checks (safe to abort without leaking a passed-in handle)
	if shouldAbort(player, zoneId) then
		return _abortEarly("zone tombstoned/aborted")
	end

	if typeof(gridCoord) ~= "table" or gridCoord.x == nil or gridCoord.z == nil then
		warn("BuildingGeneratorModule: Invalid gridCoord provided.", gridCoord)
		return _abortEarly("invalid gridCoord")
	end

	if not terrain then
		warn("BuildingGeneratorModule: 'terrain' parameter is nil.")
		return _abortEarly("no terrain")
	end

	local playerPlot = terrain.Parent
	local gBounds, gTerrains = getGlobalBoundsForPlot(playerPlot)

	local terrainSize = terrain.Size
	local terrainPos  = terrain.Position

	-- Retrieve building size dynamically from Stage3
	local finalStage = (buildingData and buildingData.stages) and buildingData.stages.Stage3
	if not finalStage then
		warn(string.format(
			"BuildingGeneratorModule: Stage3 missing for '%s' (will skip placement).",
			buildingData and tostring(buildingData.name) or "nil"
			))
		return _abortEarly("Stage3 missing")
	end

	-- Calculate the extents size of the final stage
	local buildingSizeVector
	if finalStage:IsA("Model") then
		if finalStage.PrimaryPart then
			buildingSizeVector = finalStage.PrimaryPart.Size
		else
			warn(string.format("BuildingGeneratorModule: Stage3 of '%s' does not have a PrimaryPart.", buildingData.name))
			return _abortEarly("Stage3 model has no PrimaryPart")
		end
	else
		buildingSizeVector = finalStage.Size
		if not buildingSizeVector then
			warn(string.format("BuildingGeneratorModule: Stage3 of '%s' is not a Model and lacks Size property.", buildingData.name))
			return _abortEarly("Stage3 part has no Size")
		end
	end

	-- Calculate building size in grid units (ceil)
	local buildingWidth = math.floor(buildingSizeVector.X / GRID_SIZE)
	local buildingDepth = math.floor(buildingSizeVector.Z / GRID_SIZE)
	if buildingSizeVector.X % GRID_SIZE > 0 then buildingWidth += 1 end
	if buildingSizeVector.Z % GRID_SIZE > 0 then buildingDepth += 1 end

	-- Adjust dimensions based on rotation
	local rotatedWidth, rotatedDepth = buildingWidth, buildingDepth
	if rotationY == 90 or rotationY == 270 then
		rotatedWidth, rotatedDepth = buildingDepth, buildingWidth
	end

	-- Overlay handling (remove underlying stuff before we actually place)
	local impactedZones
	if OverlayZoneTypes[mode] then
		impactedZones = removeAndArchiveUnderlyingBuildings(
			player, zoneId,
			gridCoord.x, gridCoord.z,
			rotatedWidth, rotatedDepth
		)
	end

	-- Ensure we hold a reservation for the exact footprint (assume ownership and release)
	if not resHandle then
		resHandle = select(1, GridUtils.reserveFootprint(
			player, zoneId, "building",
			gridCoord.x, gridCoord.z,
			rotatedWidth, rotatedDepth,
			{ ttl = 15.0 }
			))
		if not resHandle then
			debugPrint(("[reserve] %s @(%d,%d) blocked"):format(
				buildingData and buildingData.name or "?", gridCoord.x, gridCoord.z))
			return _abortEarly("reserveFootprint failed")
		end
	end

	----------------------------------------------------------------------
	-- From here on: **protected section** — make sure we never leak resHandle
	----------------------------------------------------------------------
	local ok, err = xpcall(function()

		-- Compute building's world position (axis-aware for odd plots)
		local cellCenterX, _, cellCenterZ =
			GridUtils.globalGridToWorldPosition(gridCoord.x, gridCoord.z, gBounds, gTerrains)

		local axisDirX, axisDirZ = 1, 1
		if type(gTerrains) == "table" then
			for _, inst in ipairs(gTerrains) do
				if typeof(inst) == "Instance" then
					axisDirX, axisDirZ = GridConfig.getAxisDirectionsForInstance(inst)
					break
				end
			end
		end

		local offsetX = axisDirX * ((rotatedWidth - 1) * GRID_SIZE * 0.5)
		local offsetZ = axisDirZ * ((rotatedDepth - 1) * GRID_SIZE * 0.5)

		local finalPosition = Vector3.new(
			cellCenterX + offsetX,
			terrainPos.Y + (terrainSize.Y / 2) + 0.1 + Y_OFFSET,
			cellCenterZ + offsetZ
		)

		-- Helper to place a stage at the correct position/rotation
		local function placeStage(stageModel)
			local stageClone = stageModel:Clone()
			if stageClone:IsA("Model") then
				stageClone:SetPrimaryPartCFrame(
					CFrame.new(finalPosition) * CFrame.Angles(0, math.rad(rotationY), 0)
				)
			else
				stageClone.Position    = finalPosition
				stageClone.Orientation = Vector3.new(0, rotationY, 0)
			end
			stageClone.Parent = parentFolder
			stageClone:SetAttribute("ZoneId", zoneId)
			stageClone:SetAttribute("BuildingName", buildingData.name)
			stageClone:SetAttribute("WealthState", wealthState or "Poor")
			if isUtility then stageClone:SetAttribute("IsUtility", true) end
			return stageClone
		end

		-- Stage flow
		local finalStageClone
		if not skipStages then
			local stage1Clones = {}
			local allTracks    = {}

			local function collectAnimations(root)
				local out = {}
				for _, desc in ipairs(root:GetDescendants()) do
					if desc:IsA("Animation") then
						table.insert(out, desc)
					end
				end
				return out
			end

			for dx = 0, rotatedWidth - 1 do
				for dz = 0, rotatedDepth - 1 do
					local cx, _, cz = GridUtils.globalGridToWorldPosition(
						gridCoord.x + dx,
						gridCoord.z + dz,
						gBounds, gTerrains
					)
					local pos = Vector3.new(
						cx,
						terrainPos.Y + (terrainSize.Y / 2) + 0.1 + Y_OFFSET,
						cz
					)

					local preview = buildingData.stages.Stage1:Clone()
					if preview:IsA("Model") and preview.PrimaryPart then
						preview:SetPrimaryPartCFrame(
							CFrame.new(pos + Vector3.new(0, STAGE1_Y_OFFSET, 0)) *
								CFrame.Angles(0, math.rad(rotationY), 0)
						)
					else
						preview.CFrame =
							CFrame.new(pos + Vector3.new(0, STAGE1_Y_OFFSET, 0)) *
							CFrame.Angles(0, math.rad(rotationY), 0)
					end
					preview.Parent = parentFolder
					preview:SetAttribute("ZoneId", zoneId)
					preview:SetAttribute("BuildingName", buildingData.name)
					preview:SetAttribute("WealthState", wealthState or "Poor")
					preview:SetAttribute("GridX", gridCoord.x)
					preview:SetAttribute("GridZ", gridCoord.z)
					preview:SetAttribute("RotationY", rotationY)
					if isUtility then preview:SetAttribute("IsUtility", true) end

					table.insert(stage1Clones, preview)

					-- Try to gather an animation to play
					local animator, animations = nil, {}
					local animController = preview:FindFirstChild("AnimationController", true)
					if animController then
						animator   = animController:FindFirstChildOfClass("Animator", true)
						animations = collectAnimations(animator or animController)
					end
					if (not animator) or #animations == 0 then
						local humanoid = preview:FindFirstChildOfClass("Humanoid", true)
						if humanoid then
							animator   = humanoid:FindFirstChildOfClass("Animator", true) or humanoid
							animations = collectAnimations(animator)
						end
					end
					if animator and #animations > 0 then
						local track = animator:LoadAnimation(animations[1])
						table.insert(allTracks, track)
					end
				end
			end

			local waitDuration = 0
			local constructionSoundHandle
			if #allTracks > 0 then
				if shouldPlayConstructionAudio(mode) then
					constructionSoundHandle = startConstructionSound(stage1Clones, parentFolder)
				end
				local playbackSpeed = BuildSpeed.enabled and BuildSpeed.multiplier or 1
				for _, track in ipairs(allTracks) do
					-- Some rigs report Length=0 until the first frame; poll briefly
					while track.Length == 0 do waitScaled(0.02) end
					waitDuration = math.max(waitDuration, track.Length)
					-- Force the animation to actually play at the fast-build speed so later
					-- keyframes (like the construction SFX trigger) still fire.
					track:Play(0, 1, playbackSpeed)
					if playbackSpeed ~= 1 then
						track:AdjustSpeed(playbackSpeed)
					end
				end
				-- Even though we sped the track, Roblox keeps Length as the authoring length.
				-- So we scale the *wait* duration ourselves:
				waitScaled(waitDuration)
			else
				waitScaled(getBuildingInterval())
			end

			if constructionSoundHandle then
				stopConstructionSound(constructionSoundHandle)
				constructionSoundHandle = nil
			end

			if shouldAbort(player, zoneId) then
				for _, preview in ipairs(stage1Clones) do
					if preview and preview.Parent then preview:Destroy() end
				end
				ZoneTrackerModule.setZonePopulating(player, zoneId, false)
				return _abortEarly("aborted during Stage1")
			end

			for _, preview in ipairs(stage1Clones) do
				preview:Destroy()
			end

			-- Stage 2
			local stage2 = placeStage(buildingData.stages.Stage2)
			stage2.Anchored   = true
			stage2.CanCollide = false

			-- Stage 3
			waitScaled(getBuildingInterval())
			finalStageClone = placeStage(buildingData.stages.Stage3)
			stage2:Destroy()
		else
			finalStageClone = placeStage(buildingData.stages.Stage3)
		end

		-- Concrete pad
		createConcretePad(finalStageClone)

		-- Remove overlapping NatureZones (archive for undo)
		local plotName  = "Plot_" .. player.UserId
		local playerPlot2 = Workspace.PlayerPlots:FindFirstChild(plotName)
		if playerPlot2 then
			local natureZonesFolder = playerPlot2:FindFirstChild("NatureZones")
			if natureZonesFolder then
				for _, nz in ipairs(natureZonesFolder:GetChildren()) do
					local nzCFrame, nzSize
					if nz:IsA("Model") then
						nzCFrame, nzSize = nz:GetBoundingBox()
					elseif nz:IsA("BasePart") then
						nzCFrame, nzSize = nz.CFrame, nz.Size
					end
					if nzCFrame and nzSize then
						local buildingPrimary = finalStageClone.PrimaryPart or finalStageClone
						if buildingPrimary then
							if aabbOverlap2D(buildingPrimary.Position, buildingPrimary.Size, nzCFrame.Position, nzSize) then
								local nzClone = nz:Clone()
								LayerManagerModule.storeRemovedObject("NatureZones", zoneId, {
									instanceClone  = nzClone,
									originalParent = nz.Parent,
									cframe         = nzCFrame
								})
								nz:Destroy()
							end
						end
					end
				end
			end
		end

		-- Quadtree insert
		local buildingObject = {
			x = gridCoord.x,
			y = gridCoord.z,
			width = rotatedWidth,
			height = rotatedDepth,
			buildingId = zoneId .. "_" .. gridCoord.x .. "_" .. gridCoord.z
		}
		-- Overlay zones can arrive without a clean reservation/clear, so run an explicit guard.
		if OverlayZoneTypes[mode] and impactedZones and next(impactedZones) then
			local function _footprintBlocked()
				return footprintHasBlockingOccupant(player, zoneId, gridCoord.x, gridCoord.z, rotatedWidth, rotatedDepth)
			end
			if _footprintBlocked() then
				-- Best-effort second sweep: something reoccupied the footprint between removal/reservation.
				local extraImpact = removeAndArchiveUnderlyingBuildings(
					player, zoneId, gridCoord.x, gridCoord.z, rotatedWidth, rotatedDepth
				)
				if extraImpact and next(extraImpact) then
					impactedZones = impactedZones or {}
					for originalZoneId in pairs(extraImpact) do
						impactedZones[originalZoneId] = true
					end
				end
			end
			if _footprintBlocked() then
				if finalStageClone and finalStageClone.Parent then
					finalStageClone:Destroy()
				end
				return _abortEarly("footprint occupied before placement")
			end
		end
		QuadtreeService:insert(buildingObject)

		-- Abort check before marking occupancy
		if shouldAbort(player, zoneId) then
			if finalStageClone and finalStageClone.Parent then
				finalStageClone:Destroy()
			end
			return _abortEarly("aborted before occupancy")
		end

		-- Mark grid as occupied for the building's area
		local buildingId = buildingObject.buildingId
		for x = gridCoord.x, gridCoord.x + rotatedWidth - 1 do
			for z = gridCoord.z, gridCoord.z + rotatedDepth - 1 do
				ZoneTrackerModule.markGridOccupied(player, x, z, 'building', buildingId, mode)
			end
		end

		-- If this was an overlay, ask the impacted original zone(s) to refill *their* gaps.
		-- We pass the overlay zoneId as `refillSourceZoneId` so those refills can be tagged & later removed on undo.
		if OverlayZoneTypes[mode] and impactedZones and next(impactedZones) and BuildingGeneratorModule._refillZoneGaps then
			task.defer(function()
				for originalZoneId in pairs(impactedZones) do
					local zd = ZoneTrackerModule.getZoneById(player, originalZoneId)
					if zd then
						BuildingGeneratorModule._refillZoneGaps(player, originalZoneId, zd.mode, nil, nil, nil, zoneId)
					end
				end
			end)
		end

		-- IMPORTANT: release reservation here (assumed ownership even if passed-in)
		_releaseReservation()

		-- Stamp rebuild attrs
		finalStageClone:SetAttribute("GridX", gridCoord.x)
		finalStageClone:SetAttribute("GridZ", gridCoord.z)
		finalStageClone:SetAttribute("RotationY", rotationY)
		finalStageClone:SetAttribute("BaseRotationY", rotationY)

		if finalStageClone:IsA("Model") then
			local pivotCF = finalStageClone:GetPivot()
			local _, yRot = select(1, pivotCF:ToEulerAnglesXYZ())
			finalStageClone:SetAttribute("OriginalOrientationY", math.deg(yRot))
			finalStageClone:SetAttribute("OriginalPivot", pivotCF)
		else
			finalStageClone:SetAttribute("OriginalOrientationY", finalStageClone.Orientation.Y)
		end

		addAmbientLoopForZone(mode, finalStageClone)

		recordQuotaPlacement(quotaCtx, mode, wealthState or "Poor", buildingData and buildingData.name)

		task.defer(function()
			Wigw8mPlacedEvent:Fire(player, zoneId, {
				mode         = mode,
				building     = finalStageClone,
				buildingName = buildingData.name,
				gridX        = gridCoord.x,
				gridZ        = gridCoord.z,
				rotationY    = rotationY,
				isUtility    = isUtility and true or false,
				wealthState  = wealthState or "Poor",
			})
		end)

		debugPrint(string.format(
			"BuildingGeneratorModule: Placed building '%s' at Grid (%d, %d) with rotation %d degrees%s.",
			buildingData.name, gridCoord.x, gridCoord.z, rotationY, isUtility and " [Utility]" or ""
			))

		if onPlaced then onPlaced() end
	end, debug.traceback)

	-- Guaranteed cleanup on unexpected runtime errors
	if not ok then
		_releaseReservation() -- idempotent
		warn(("[generateBuilding] runtime error while placing '%s':\n%s")
			:format(buildingData and buildingData.name or "?", tostring(err)))
		return
	end
end

local ROTATION_BLOCKING_ZONES = {
	RoadZone = true,       -- any zoneId starting with "RoadZone_"
	-- Uncomment if you also want to block on utilities overlays:
	-- PowerLinesZone = true,
	-- PipeZone       = true,
}

-- Find the player's Plot_#### folder for any instance
local function getOwningPlotFor(inst : Instance) : Instance?
	local ptr = inst
	while ptr and ptr.Parent do
		if ptr.Name:match("^Plot_%d+$") then
			return ptr
		end
		ptr = ptr.Parent
	end
	return nil
end

-- Build the worldspace rectangle (center + XZ size) this building would occupy
-- if it were rotated to `angleY` (0/90/180/270), keeping the SAME center.
local function proposedFootprintXZ(buildingInstance : Instance, angleY : number)
	-- pull stage3 size from the master list using attributes already stamped
	local bname = buildingInstance:GetAttribute("BuildingName")
	local rotY  = angleY % 360
	if not bname then
		-- Fallback to current bounds if we can't resolve the official footprint.
		local cf, size
		if buildingInstance:IsA("Model") then
			cf, size = buildingInstance:GetBoundingBox()
		else
			cf   = buildingInstance.CFrame
			size = buildingInstance.Size
		end
		return cf.Position, Vector3.new(size.X, 0, size.Z)
	end

	local wCells, dCells = _stage3FootprintCells(bname, rotY)
	local sizeXZ = Vector3.new(wCells * GRID_SIZE, 0, dCells * GRID_SIZE)

	-- center is current pivot position
	local pivotCF = buildingInstance:IsA("Model") and buildingInstance:GetPivot() or buildingInstance.CFrame
	return pivotCF.Position, sizeXZ
end

-- Generic XZ AABB test for a hypothetical building rotation against a given instance
local function overlapsInstanceXZ(proposedCenter : Vector3, proposedSizeXZ : Vector3, other : Instance)
	local cf, size
	if other:IsA("Model") then
		cf, size = other:GetBoundingBox()
	else
		cf, size = other.CFrame, other.Size
	end
	return aabbOverlap2D(
		proposedCenter,
		Vector3.new(proposedSizeXZ.X, 0, proposedSizeXZ.Z),
		cf.Position,
		Vector3.new(size.X, 0, size.Z)
	)
end

-- Detect if rotating to angleY would overlap any blocking zone objects (e.g., Roads)
local function rotationWouldOverlapBlockingZones(buildingInstance : Instance, angleY : number)
	local plot = getOwningPlotFor(buildingInstance)
	if not plot then return false end

	-- Where roads (and some utilities) live in your structure:
	-- populateZone() parents ROADS under Buildings/Populated/Utilities and stamps ZoneId.
	local populated = plot:FindFirstChild("Buildings")
		and plot.Buildings:FindFirstChild("Populated")
	if not populated then return false end

	local utilities = populated:FindFirstChild("Utilities")
	if not utilities then return false end

	local proposedCenter, proposedSizeXZ = proposedFootprintXZ(buildingInstance, angleY)

	for _, inst in ipairs(utilities:GetChildren()) do
		-- We only block on objects that clearly belong to certain zone types.
		local zid = inst:GetAttribute("ZoneId")
		if type(zid) == "string" then
			-- Normalize to a short key (e.g., "RoadZone")
			local key = zid:match("^([A-Za-z]+Zone)_") or zid
			if ROTATION_BLOCKING_ZONES[key] then
				if overlapsInstanceXZ(proposedCenter, proposedSizeXZ, inst) then
					return true
				end
			end
		end
	end

	return false
end

-- Resolve Player from a building instance by walking up to Plot_<userid>
local function getPlayerFromInstance(inst : Instance)
	local plot = getOwningPlotFor(inst)
	if not plot then return nil end
	local uid = tonumber(plot.Name:match("^Plot_(%d+)$"))
	if not uid then return nil end
	return game:GetService("Players"):GetPlayerByUserId(uid)
end

-- Modes where we only allow rotation if Stage3 footprint is square (n x n cells) or 180° flips otherwise
local SQUARE_ONLY_MODES : { [string]: boolean } = {
	Residential = true, Commercial = true, Industrial = true,
	ResDense    = true, CommDense   = true, IndusDense   = true,
}

-- True if the building's Stage3 footprint at its current RotationY is n x n cells
local function isSquareFootprint(buildingInstance : Instance) : boolean
	local bname = buildingInstance:GetAttribute("BuildingName")
	local rotY  = buildingInstance:GetAttribute("RotationY") or 0
	if bname then
		local w, d = _stage3FootprintCells(bname, rotY)
		return w == d
	end
	-- Fallback: infer from current bounds
	local _, size
	if buildingInstance:IsA("Model") then
		_, size = buildingInstance:GetBoundingBox()
	else
		size = buildingInstance.Size
	end
	if not size then return false end
	local w = math.ceil(size.X / GRID_SIZE)
	local d = math.ceil(size.Z / GRID_SIZE)
	return w == d
end
--Road Orientation from build or grid upgrade

local function isRoadInstance(inst : Instance) : boolean
	if not (inst and (inst:IsA("Model") or inst:IsA("BasePart"))) then return false end
	local zid = inst:GetAttribute("ZoneId")
	if type(zid) == "string" and zid:match("^RoadZone_") then
		return true
	end
	local zType = inst:GetAttribute("ZoneType")
	if type(zType) == "string" and ROAD_ZONE_TYPES[zType] then
		return true
	end
	return type(inst.Name) == "string" and inst.Name:match("^RoadZone_") ~= nil
end

local function nearestRoadTargetFor(buildingInstance : Instance, maxDistanceStuds : number?) : Vector3?
	local plot = getOwningPlotFor(buildingInstance)
	if not plot then return nil end
	local populated = plot:FindFirstChild("Buildings")
		and plot.Buildings:FindFirstChild("Populated")
	if not populated then return nil end

	local candidateFolders = {}

	local playerZones = plot:FindFirstChild("PlayerZones")
	if playerZones then
		table.insert(candidateFolders, { folder = playerZones, descend = false })
	end

	local roadsFolder = plot:FindFirstChild("Roads")
	if roadsFolder then
		table.insert(candidateFolders, { folder = roadsFolder, descend = true })
	end

	if #candidateFolders == 0 then
		return nil
	end

	local pivotCF = buildingInstance:IsA("Model") and buildingInstance:GetPivot() or buildingInstance.CFrame
	local bpos = pivotCF.Position

	local bestPos
	local bestDistSq
	local maxDistSq = maxDistanceStuds and (maxDistanceStuds * maxDistanceStuds) or nil

	for _, entry in ipairs(candidateFolders) do
		local folder = entry.folder
		local descend = entry.descend
		local children = descend and folder:GetDescendants() or folder:GetChildren()

		for _, inst in ipairs(children) do
			if isRoadInstance(inst) then
				local cf = inst:IsA("Model") and select(1, inst:GetBoundingBox()) or inst.CFrame
				local pos = cf.Position
				local dx = pos.X - bpos.X
				local dz = pos.Z - bpos.Z
				local distSq = dx * dx + dz * dz
				if not maxDistSq or distSq <= maxDistSq then
					if not bestDistSq or distSq < bestDistSq then
						bestDistSq, bestPos = distSq, pos
					end
				end
			end
		end
	end

	return bestPos
end

local function orientZoneBuildingsTowardRoads(player, zoneId)
	local zd = ZoneTrackerModule.getZoneById(player, zoneId)
	if not zd then return end
	local mode = zd.mode
	-- Only process for the modes you requested
	if not (mode and SQUARE_ONLY_MODES[mode]) then return end

	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_" .. player.UserId)
	if not plot then return end
	local populated = plot:FindFirstChild("Buildings")
		and plot.Buildings:FindFirstChild("Populated")
	if not populated then return end
	local zoneFolder = populated:FindFirstChild(zoneId)
	if not zoneFolder then return end

	for _, inst in ipairs(zoneFolder:GetChildren()) do
		if (inst:IsA("Model") or inst:IsA("BasePart"))
			and inst:GetAttribute("ZoneId") == zoneId
		then
			local target = nearestRoadTargetFor(inst, ROAD_ORIENTATION_RADIUS_STUDS)
			if target then
				BuildingGeneratorModule.orientBuildingToward(inst, target)
			end
		end
	end
end

--Road Orient from build or grid upgrade end

local function orientBuildingOnPlacement(player, zoneId, payload)
	if not player or not zoneId or not payload then return end
	if payload.isUtility then return end

	local building = payload.building
	if not (building and (building:IsA("Model") or building:IsA("BasePart"))) then return end
	if not building.Parent then return end

	local zd = ZoneTrackerModule.getZoneById(player, zoneId)
	local mode = payload.mode or (zd and zd.mode)
	if not (mode and SQUARE_ONLY_MODES[mode]) then return end

	local target = nearestRoadTargetFor(building, ROAD_ORIENTATION_RADIUS_STUDS)
	if target then
		BuildingGeneratorModule.orientBuildingToward(building, target)
	end
end

Wigw8mPlacedEvent.Event:Connect(orientBuildingOnPlacement)

function BuildingGeneratorModule.orientBuildingToward(buildingInstance: Instance, targetPos: Vector3)
	-- Safety checks
	if not buildingInstance or not buildingInstance.Parent then return end

	-- === Determine mode & square-ness once ===
	local zid  = buildingInstance:GetAttribute("ZoneId")
	local plr  = zid and getPlayerFromInstance(buildingInstance) or nil
	local zd   = (plr and zid) and ZoneTrackerModule.getZoneById(plr, zid) or nil
	local mode = zd and zd.mode or nil

	local restrictRotation = (mode and SQUARE_ONLY_MODES[mode]) or isIndividualMode(mode)
	local isSquare         = isSquareFootprint(buildingInstance)
	-- Get building center position
	local pivotCF
	if buildingInstance:IsA("Model") then
		pivotCF = buildingInstance:GetPivot()
	else
		pivotCF = buildingInstance.CFrame
	end
	local buildingPos = pivotCF.Position

	-- Direction to target (projected onto XZ plane)
	local dir = Vector3.new(targetPos.X - buildingPos.X, 0, targetPos.Z - buildingPos.Z)
	if dir.Magnitude < 1e-6 then return end -- don't rotate if target is "here"

	-- Compute "face the road" angle in degrees (0 = +Z, 90 = +X, 180 = -Z, 270 = -X)
	local desired = math.deg(math.atan2(dir.X, dir.Z)) -- +Z is 0°
	-- Snap to nearest 90°
	local snapped = math.floor((desired + 45) / 90) * 90
	-- Keep in [0,360)
	snapped = (snapped + 360) % 360
	-- Your historical 180° flip:
	snapped = (snapped + 180) % 360

	-- Current RotY (what we stamped on placement; fall back to reading pivot)
	local curY = buildingInstance:GetAttribute("RotationY")
	if curY == nil then
		-- derive current yaw from pivotCF (robust enough here)
		local _, yaw, _ = pivotCF:ToOrientation()
		curY = (math.deg(yaw) % 360 + 360) % 360
	end

	-- === NEW: For non-square footprints in the listed modes, forbid 90/270. Use 180° if needed.
	if restrictRotation and not isSquare then
		-- propose 180° flip instead of 90°/270°
		local delta = (snapped - curY) % 360
		if delta == 90 or delta == 270 then
			local alt = (curY + 180) % 360
			if rotationWouldOverlapBlockingZones(buildingInstance, alt) then
				if DEBUG then
					warn(("[orientBuildingToward] skip: non-square & 180° alt overlaps (curY=%d, alt=%d)"):format(curY, alt))
				end
				return
			end
			snapped = alt
		end
	end

	-- Guard: bail if this rotation would overlap blocking zones (roads, etc.)
	if rotationWouldOverlapBlockingZones(buildingInstance, snapped) then
		if DEBUG then
			warn(("[orientBuildingToward] blocked rotation to %d° due to overlap with a blocking zone."):format(snapped))
		end
		return
	end

	-- Keep the zone plate synchronized if present
	if zid then
		-- walk up until we reach the player's plot folder (“Plot_12345”)
		local ptr = buildingInstance.Parent
		while ptr and not ptr.Name:match("^Plot_%d+$") do ptr = ptr.Parent end
		if ptr then
			ZoneDisplay.updateZonePartRotation(ptr, zid, snapped)
		end
	end

	-- Apply rotation
	local newCF = CFrame.new(buildingPos) * CFrame.Angles(0, math.rad(snapped), 0)
	if buildingInstance:IsA("Model") then
		buildingInstance:PivotTo(newCF)
	else
		buildingInstance.CFrame = newCF
	end
	-- Stamp attribute so future footprint checks use the true orientation
	buildingInstance:SetAttribute("RotationY", snapped)

	--print("[orientBuildingToward]",buildingInstance.Name,"Snapped rotation:", snapped,"Pivot after orientation =", buildingInstance:GetPivot())
end
-- Reverts orientation to the building’s originally stored attribute
function BuildingGeneratorModule.revertBuildingOrientation(buildingInstance: Instance)
	if not buildingInstance then return end

	local function syncZonePlate(rotY)
		local zoneId = buildingInstance:GetAttribute("ZoneId")
		if not zoneId then return end

		-- climb the hierarchy until we hit “Plot_<UserId>”
		local plot = buildingInstance.Parent
		while plot and not plot.Name:match("^Plot_%d+$") do
			plot = plot.Parent
		end
		if plot then
			ZoneDisplay.updateZonePartRotation(plot, zoneId, rotY % 360)
		end
	end

	local pivotCF = buildingInstance:GetAttribute("OriginalPivot")
	if pivotCF then
		if buildingInstance:IsA("Model") then
			buildingInstance:PivotTo(pivotCF)
		else
			buildingInstance.CFrame = pivotCF
		end
		return
	end

	-- If you only stored the Y rotation
	local origY = buildingInstance:GetAttribute("OriginalOrientationY")
	if origY then
		if buildingInstance:IsA("Model") then
			local currentPos = buildingInstance:GetPivot().Position
			buildingInstance:PivotTo(
				CFrame.new(currentPos)
					* CFrame.Angles(0, math.rad(origY), 0)
			)
		else
			local currentPos = buildingInstance.Position
			buildingInstance.CFrame =
				CFrame.new(currentPos)
				* CFrame.Angles(0, math.rad(origY), 0)
		end
	end
end




-- (The rest of the module remains unchanged.)
-- Helper function for first pass building placement
-- Helper function for first pass building placement (ENHANCED with reservations)
-- Helper function for first pass building placement (ENHANCED: true O(#seeds) when tileWhitelist is given)
local function placeBuildings(
	player, zoneId, mode, buildingsList, isUtility,
	terrain, zoneFolder, utilitiesFolder,
	minX, maxX, minZ, maxZ,
	onBuildingPlaced, rotation,
	style, defaultWealthState,
	quotaCtx,
	tileWhitelist -- optional set { ["x|z"]=true } to restrict work to specific cells
)
	local function _k(x, z) return tostring(x).."|"..tostring(z) end
	local useWhitelist = (type(tileWhitelist) == "table" and next(tileWhitelist) ~= nil)

	local leftoverCells = {} -- cells to retry in second pass

	-- Small local shuffle to spread work a bit if desired (used only for whitelist mode)
	local function _shuffle(arr)
		for i = #arr, 2, -1 do
			local j = math.random(i)
			arr[i], arr[j] = arr[j], arr[i]
		end
	end

	-- Per-cell worker. Returns the vertical depth placed at (x,z) if a multi-tile building was placed (for scan-skip),
	-- or nil/1 if nothing special about skipping is needed.
	local function processCell(x, z)
		if shouldAbort(player, zoneId) then
			return "ABORT"
		end

		-- occupancy gate (overlay may float over others)
		if not (OverlayZoneTypes[mode]
			or not ZoneTrackerModule.isGridOccupied(
				player, x, z,
				{ excludeOccupantId = zoneId, excludeZoneTypes = OverlapExclusions }
			))
		then
			-- blocked now; try again in second pass
			table.insert(leftoverCells, { x = x, z = z })
			return 1
		end

		-- placement chance (currently always 1.0 as before; keep hook)
		local placementChance = isUtility and 1.0 or 1.0
		if math.random() >= placementChance then
			table.insert(leftoverCells, { x = x, z = z })
			return 1
		end

		-- resolve tile wealth
		local tileWealth = _tileWealthForPlacement(mode, defaultWealthState, player, zoneId, x, z)
		if WEALTHED_ZONES[mode] and typeof(ZoneTrackerModule.getGridWealth) == "function" then
			tileWealth = ZoneTrackerModule.getGridWealth(player, zoneId, x, z) or tileWealth
		end

		-- per-tile list (wealth bucket if applicable)
		local listForTile = buildingsList
		if WEALTHED_ZONES[mode] then
			local wl = BuildingMasterList.getBuildingsByZone(mode, style or "Default", tileWealth)
			if wl and #wl > 0 then listForTile = wl end
		end

		-- pick with quotas
		local selectedBuilding = chooseWeightedBuildingWithQuota(listForTile, mode, tileWealth, quotaCtx)
		if not selectedBuilding then
			table.insert(leftoverCells, { x = x, z = z })
			return 1
		end

		-- rotation
		local rotationY = pickRotation(mode, rotation)
		if (rotationY % 90) ~= 0 then
			rotationY = CARDINALS[math.floor((rotationY + 45) / 90) % 4 + 1]
		end

		-- footprint from Stage3 extents
		local finalStage = selectedBuilding.stages.Stage3
		local buildingSizeVector =
			(finalStage:IsA("Model") and finalStage.PrimaryPart and finalStage.PrimaryPart.Size)
			or finalStage.Size

		if not buildingSizeVector then
			warn(string.format(
				"BuildingGeneratorModule: Stage3 of '%s' lacks a Size or PrimaryPart.",
				selectedBuilding.name
				))
			table.insert(leftoverCells, { x = x, z = z })
			return 1
		end

		local buildingWidth  = math.ceil(buildingSizeVector.X / GRID_SIZE)
		local buildingDepth  = math.ceil(buildingSizeVector.Z / GRID_SIZE)
		if rotationY == 90 or rotationY == 270 then
			buildingWidth, buildingDepth = buildingDepth, buildingWidth
		end

		-- bounds/occupancy gate for this footprint
		local okSpot = BuildingGeneratorModule.canPlaceBuilding(
			player,
			{ minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ },
			{ width = buildingWidth, depth = buildingDepth },
			x, z, zoneId, mode
		)
		if not okSpot then
			table.insert(leftoverCells, { x = x, z = z })
			return 1
		end

		-- pre-reserve exact footprint; hand pass to generator (generator owns release)
		local preHandle = GridUtils.reserveFootprint(
			player, zoneId, "building", x, z, buildingWidth, buildingDepth, { ttl = 10.0 }
		)
		if not preHandle then
			table.insert(leftoverCells, { x = x, z = z })
			return 1
		end

		local parentFolder = isUtility and utilitiesFolder or zoneFolder
		local ok, err = pcall(function()
			BuildingGeneratorModule.generateBuilding(
				terrain,
				parentFolder,
				player,
				zoneId,
				mode,
				{ x = x, z = z },
				selectedBuilding,
				isUtility,
				rotationY,
				onBuildingPlaced,
				tileWealth,
				nil,          -- skipStages
				preHandle,    -- reservation ownership transferred
				quotaCtx
			)
		end)

		if not ok then
			GridUtils.releaseReservation(preHandle)
			warn("[placeBuildings] generateBuilding error:", err)
			-- try again later
			table.insert(leftoverCells, { x = x, z = z })
			return 1
		end

		-- If we’re in the full-scan path, the caller can skip covered Z cells for multi-depth
		return buildingDepth
	end

	-- === MAIN DISPATCH ===
	if useWhitelist then
		-- Build seed list from whitelist and iterate ONLY those cells (true O(#seeds))
		local seeds = {}
		for key, _ in pairs(tileWhitelist) do
			local sep = string.find(key, "|", 1, true)
			local gx = tonumber(string.sub(key, 1, sep - 1))
			local gz = tonumber(string.sub(key, sep + 1))
			if gx and gz then table.insert(seeds, { x = gx, z = gz }) end
		end

		-- Deterministic—but feel free to shuffle for load-spreading
		table.sort(seeds, function(a,b) return (a.x < b.x) or (a.x == b.x and a.z < b.z) end)
		-- _shuffle(seeds) -- uncomment if you prefer randomized seed order

		for i = 1, #seeds do
			local res = processCell(seeds[i].x, seeds[i].z)
			if res == "ABORT" then return leftoverCells end
			-- No z-skipping in whitelist mode (we’re not scanning a row)
			if (i % 25) == 0 then task.wait() end
		end
	else
		-- Original full scan (preserved behavior), with z-skip optimization for multi-depth placements
		for x = minX, maxX do
			local z = minZ
			while z <= maxZ do
				local res = processCell(x, z)
				if res == "ABORT" then
					return leftoverCells
				end
				-- res may be multi-depth; skip covered cells in the same column
				if type(res) == "number" and res > 1 then
					z = z + res
				else
					z = z + 1
				end

				if ((x - minX) % 10 == 0) and ((z - minZ) % 10 == 0) then
					task.wait()
				end
			end
		end
	end

	return leftoverCells
end


BuildingGeneratorModule._placeBuildings = placeBuildings

-- Second pass placement without fallback cube
local function placeBuildingsSecondPass(
	player, zoneId, mode, buildingsList, isUtility,
	terrain, zoneFolder, utilitiesFolder, leftoverCells,
	minX, maxX, minZ, maxZ,
	onBuildingPlaced, rotation,
	style, defaultWealthState,
	quotaCtx
)
	if not RANDOM_ROTATION_ZONES[mode] then
		return
	end

	local maxAttemptsPerCell = 3

	for _, cell in ipairs(leftoverCells) do
		local x, z = cell.x, cell.z

		local tileWealth = _tileWealthForPlacement(mode, defaultWealthState, player, zoneId, x, z)
		if WEALTHED_ZONES[mode] and typeof(ZoneTrackerModule.getGridWealth) == "function" then
			tileWealth = ZoneTrackerModule.getGridWealth(player, zoneId, x, z) or tileWealth
		end

		local listForTile = buildingsList
		if WEALTHED_ZONES[mode] then
			local wl = BuildingMasterList.getBuildingsByZone(mode, style or "Default", tileWealth)
			if wl and #wl > 0 then listForTile = wl end
		end

		if shouldAbort(player, zoneId) then
			return
		end

		local buildingPlaced = false

		-- Try only if this cell is usable for this zone
		if OverlayZoneTypes[mode]
			or not ZoneTrackerModule.isGridOccupied(
				player, x, z,
				{
					excludeOccupantId = zoneId,
					excludeZoneTypes  = OverlapExclusions, -- ignore WaterPipe only
				}
			) then

			-- Attempt loop with quota-aware weighted picks
			for attempt = 1, maxAttemptsPerCell do
				local selectedBuilding = chooseWeightedBuildingWithQuota(listForTile, mode, tileWealth, quotaCtx)
				if selectedBuilding then
					local rotationY = pickRotation(mode, rotation)
					if (rotationY % 90) ~= 0 then
						rotationY = CARDINALS[math.floor((rotationY + 45) / 90) % 4 + 1]
					end
					local finalStage = selectedBuilding.stages.Stage3
					local buildingSizeVector

					if finalStage:IsA("Model") then
						if finalStage.PrimaryPart then
							buildingSizeVector = finalStage.PrimaryPart.Size
						else
							warn(string.format("BuildingGeneratorModule: Stage3 of '%s' lacks a PrimaryPart.", selectedBuilding.name))
							continue
						end
					else
						buildingSizeVector = finalStage.Size
						if not buildingSizeVector then
							warn(string.format("BuildingGeneratorModule: Stage3 of '%s' is not a Model and lacks Size property.", selectedBuilding.name))
							continue
						end
					end

					local buildingWidth = math.ceil(buildingSizeVector.X / GRID_SIZE)
					local buildingDepth = math.ceil(buildingSizeVector.Z / GRID_SIZE)
					if rotationY == 90 or rotationY == 270 then
						buildingWidth, buildingDepth = buildingDepth, buildingWidth
					end

					local canPlace = BuildingGeneratorModule.canPlaceBuilding(player, {
						minX = minX,
						maxX = maxX,
						minZ = minZ,
						maxZ = maxZ
					}, { width = buildingWidth, depth = buildingDepth }, x, z, zoneId, mode)

					if canPlace then
						local parentFolder = isUtility and utilitiesFolder or zoneFolder
						BuildingGeneratorModule.generateBuilding(
							terrain,
							parentFolder,
							player,
							zoneId,
							mode,
							{ x = x, z = z },
							selectedBuilding,
							isUtility,
							rotationY,
							onBuildingPlaced,
							tileWealth,
							nil,
							nil,
							quotaCtx
						)
						buildingPlaced = true
						break
					end
				end

				task.wait()
			end

			-- Fallback loop if attempts failed: scan all candidates and rotations (guarded by quota)
			if not buildingPlaced then
				for _, sb in ipairs(listForTile) do
					if not (sb and sb.name and wouldViolateQuota(quotaCtx, mode, tileWealth, sb.name)) then
						local rotationCandidates = {0, 90, 180, 270}
						for _, rotationY in ipairs(rotationCandidates) do
							local finalStage = sb.stages.Stage3
							local buildingSizeVector

							if finalStage:IsA("Model") then
								if finalStage.PrimaryPart then
									buildingSizeVector = finalStage.PrimaryPart.Size
								else
									warn(string.format("BuildingGeneratorModule: Stage3 of '%s' lacks a PrimaryPart.", sb.name))
									continue
								end
							else
								buildingSizeVector = finalStage.Size
								if not buildingSizeVector then
									warn(string.format("BuildingGeneratorModule: Stage3 of '%s' is not a Model and lacks Size property.", sb.name))
									continue
								end
							end

							local buildingWidth = math.ceil(buildingSizeVector.X / GRID_SIZE)
							local buildingDepth = math.ceil(buildingSizeVector.Z / GRID_SIZE)
							if rotationY == 90 or rotationY == 270 then
								buildingWidth, buildingDepth = buildingDepth, buildingWidth
							end

							local canPlace = BuildingGeneratorModule.canPlaceBuilding(player, {
								minX = minX,
								maxX = maxX,
								minZ = minZ,
								maxZ = maxZ
							}, { width = buildingWidth, depth = buildingDepth }, x, z, zoneId, mode)

							if canPlace then
								local parentFolder = isUtility and utilitiesFolder or zoneFolder
								BuildingGeneratorModule.generateBuilding(
									terrain,
									parentFolder,
									player,
									zoneId,
									mode,
									{ x = x, z = z },
									sb,
									isUtility,
									rotationY,
									onBuildingPlaced,
									tileWealth,
									nil,
									nil,
									quotaCtx
								)
								buildingPlaced = true
								break
							end
						end

						if buildingPlaced then
							break
						end
					end
				end
			end

			-- Per-cell throttle and warn if still nothing placed
			if not buildingPlaced and RANDOM_ROTATION_ZONES[mode] then
				warn(string.format("BuildingGeneratorModule: Could not place any building at Grid (%d, %d).", x, z))
			end

			if (x - minX) % 10 == 0 and (z - minZ) % 10 == 0 then
				task.wait()
			end
		end -- occupancy check
	end -- for each leftover cell
end
BuildingGeneratorModule._placeBuildingsSecondPass = placeBuildingsSecondPass

-- Populates a Zone with Buildings
function BuildingGeneratorModule.populateZone(
	player,
	zoneId,
	mode,
	gridList,
	predefinedBuildings,
	rotation,
	skipStages,
	wealthOverride -- NEW: optional wealth tier for this population pass ("Poor"|"Medium"|"Wealthy")
)
	-- Ignore non-building zones here, as before
	if zoneId:match("^RoadZone_")
		or zoneId:match("^PowerLinesZone_")
		or zoneId:match("^PipeZone_")
		or zoneId:match("^MetroTunnelZone_")
	then
		return
	end

	skipStages = skipStages or false
	clearAbort(player, zoneId)
	-- If a tombstone/abort is already set (rare but safe), don’t start
	if shouldAbort(player, zoneId) then
		return
	end

	do
		local zd = ZoneTrackerModule.getZoneById(player, zoneId)
		if not zd then
			if DEBUG then
				warn(("[BuildingGenerator] populateZone starting without ZoneTracker entry for '%s' (mode=%s). " ..
					"Proceeding; aborts will only occur on explicit ZoneRemoved."):format(zoneId, tostring(mode)))
			end
		end
	end

	task.spawn(function()
		if shouldAbort(player, zoneId) then
			ZoneTrackerModule.setZonePopulating(player, zoneId, false)
			zonePopulatedEvent:Fire(player, zoneId, {})
			return
		end

		ZoneTrackerModule.setZonePopulating(player, zoneId, true)
		debugPrint(string.format("BuildingGeneratorModule: Populating Zone '%s' for mode '%s'%s.",
			zoneId, mode, wealthOverride and (" (wealth="..tostring(wealthOverride)..")") or ""))

		local plotName   = "Plot_" .. player.UserId
		local playerPlot = Workspace.PlayerPlots:FindFirstChild(plotName)
		if not playerPlot then
			warn("BuildingGeneratorModule: Player plot '" .. plotName .. "' not found in Workspace.PlayerPlots.")
			ZoneTrackerModule.setZonePopulating(player, zoneId, false)
			zonePopulatedEvent:Fire(player, zoneId, {})
			return
		end

		local terrain = playerPlot:FindFirstChild("TestTerrain")
		if not terrain then
			warn("BuildingGeneratorModule: 'TestTerrain' not found in player plot '" .. plotName .. "'.")
			ZoneTrackerModule.setZonePopulating(player, zoneId, false)
			zonePopulatedEvent:Fire(player, zoneId, {})
			return
		end

		local buildingsFolder = playerPlot:FindFirstChild("Buildings")
		if not buildingsFolder then
			ZoneTrackerModule.setZonePopulating(player, zoneId, false)
			zonePopulatedEvent:Fire(player, zoneId, {})
			return
		end

		local populatedFolder = buildingsFolder:FindFirstChild("Populated")
		if not populatedFolder then
			populatedFolder = Instance.new("Folder")
			populatedFolder.Name = "Populated"
			populatedFolder.Parent = buildingsFolder
		end

		local zoneFolder = populatedFolder:FindFirstChild(zoneId)
		if not zoneFolder then
			zoneFolder = Instance.new("Folder")
			zoneFolder.Name = zoneId
			zoneFolder.Parent = populatedFolder
		end

		local utilitiesFolder = populatedFolder:FindFirstChild("Utilities")
		if not utilitiesFolder then
			utilitiesFolder = Instance.new("Folder")
			utilitiesFolder.Name = "Utilities"
			utilitiesFolder.Parent = populatedFolder
		end

		local defaultStyle        = "Default"
		local defaultWealthState  = wealthOverride or "Poor"

		-- NEW: initialize quota context for this zone population
		local quotaCtx = newQuotaContext(mode, player, zoneId)
		scanZoneCountsInto(quotaCtx)

		-- Detect whether we are replaying saved blueprints
		local replay = (type(predefinedBuildings) == "table" and #predefinedBuildings > 0)

		-- (Optional) Make procedural RNG deterministic only when NOT replaying
		if not replay then
			local uid = tonumber(player.UserId) or 0
			local h = 0
			for i = 1, #zoneId do h = (h * 131 + string.byte(zoneId, i)) % 0x7fffffff end
			math.randomseed(bit32.bxor(uid, h))
		end

		local buildingsList       = {}
		local isUtility           = false

		-- Mode routing (unchanged behavior)
		if mode == "WaterTower" then
			local utilityType = "Water"
			local style = "Default"
			local buildingName = "WaterTower"
			buildingsList = BuildingMasterList.getUtilityBuilding(utilityType, style, buildingName)
			isUtility = true
		elseif mode == "Utilities" then
			local utilityType = "Water"
			buildingsList = BuildingMasterList.getUtilitiesByType(utilityType, defaultStyle)
			isUtility = true
		elseif mode == "Road" then
			buildingsList = BuildingMasterList.getRoadsByStyle(defaultStyle)
			isUtility = true

			-- Individual buildings (unchanged)
		elseif mode == "FireDept" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Fire", defaultStyle, "FireDept")
		elseif mode == "FirePrecinct" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Fire", defaultStyle, "FirePrecinct")
		elseif mode == "FireStation" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Fire", defaultStyle, "FireStation")
		elseif mode == "MetroEntrance" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Metro", defaultStyle, "Metro Entrance")
		elseif mode == "BusDepot" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Bus", defaultStyle, "Bus Depot")
		elseif mode == "MiddleSchool" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Education", defaultStyle, "Middle School")
		elseif mode == "Museum" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Education", defaultStyle, "Museum")
		elseif mode == "NewsStation" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Education", defaultStyle, "News Station")
		elseif mode == "PrivateSchool" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Education", defaultStyle, "Private School")
		elseif mode == "CityHospital" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Health", defaultStyle, "City Hospital")
		elseif mode == "LocalHospital" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Health", defaultStyle, "Local Hospital")
		elseif mode == "MajorHospital" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Health", defaultStyle, "Major Hospital")
		elseif mode == "SmallClinic" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Health", defaultStyle, "Small Clinic")
		elseif mode == "Bank" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Landmark", defaultStyle, "Bank")
		elseif mode == "CNTower" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Landmark", defaultStyle, "CN Tower")
		elseif mode == "EiffelTower" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Landmark", defaultStyle, "Eiffel Tower")
		elseif mode == "EmpireStateBuilding" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Landmark", defaultStyle, "Empire State Building")
		elseif mode == "FerrisWheel" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Landmark", defaultStyle, "Ferris Wheel")
		elseif mode == "GasStation" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Landmark", defaultStyle, "Gas Station")
		elseif mode == "ModernSkyscraper" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Landmark", defaultStyle, "Modern Skyscraper")
		elseif mode == "NationalCapital" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Landmark", defaultStyle, "National Capital")
		elseif mode == "Obelisk" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Landmark", defaultStyle, "Obelisk")
		elseif mode == "SpaceNeedle" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Landmark", defaultStyle, "Space Needle")
		elseif mode == "StatueOfLiberty" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Landmark", defaultStyle, "Statue Of Liberty")
		elseif mode == "TechOffice" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Landmark", defaultStyle, "Tech Office")
		elseif mode == "WorldTradeCenter" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Landmark", defaultStyle, "World Trade Center")
		elseif mode == "Church" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Leisure", defaultStyle, "Church")
		elseif mode == "Hotel" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Leisure", defaultStyle, "Hotel")
		elseif mode == "Mosque" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Leisure", defaultStyle, "Mosque")
		elseif mode == "MovieTheater" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Leisure", defaultStyle, "Movie Theater")
		elseif mode == "ShintoTemple" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Leisure", defaultStyle, "Shinto Temple")
		elseif mode == "BuddhaStatue" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Leisure", defaultStyle, "Buddha Statue")
		elseif mode == "HinduTemple" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Leisure", defaultStyle, "Hindu Temple")
		elseif mode == "Courthouse" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Police", defaultStyle, "Courthouse")
		elseif mode == "PoliceDept" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Police", defaultStyle, "Police Dept")
		elseif mode == "PolicePrecinct" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Police", defaultStyle, "Police Precinct")
		elseif mode == "PoliceStation" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Police", defaultStyle, "Police Station")
		elseif mode == "ArcheryRange" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Sports", defaultStyle, "Archery Range")
		elseif mode == "BasketballCourt" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Sports", defaultStyle, "Basketball Court")
		elseif mode == "BasketballStadium" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Sports", defaultStyle, "Basketball Stadium")
		elseif mode == "FootballStadium" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Sports", defaultStyle, "Football Stadium")
		elseif mode == "GolfCourse" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Sports", defaultStyle, "Golf Course")
		elseif mode == "PublicPool" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Sports", defaultStyle, "Public Pool")
		elseif mode == "SkatePark" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Sports", defaultStyle, "Skate Park")
		elseif mode == "SoccerStadium" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Sports", defaultStyle, "Soccer Stadium")
		elseif mode == "TennisCourt" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Sports", defaultStyle, "Tennis Court")
		elseif mode == "Airport" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Airport", defaultStyle, "Airport")
		elseif mode == "WaterPlant" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Water", defaultStyle, "Water Plant")
		elseif mode == "PurificationWaterPlant" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Water", defaultStyle, "Purification Water Plant")
		elseif mode == "MolecularWaterPlant" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Water", defaultStyle, "Molecular Water Plant")
		elseif mode == "CoalPowerPlant" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Power", defaultStyle, "Coal Power Plant")
		elseif mode == "GasPowerPlant" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Power", defaultStyle, "Gas Power Plant")
		elseif mode == "GeothermalPowerPlant" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Power", defaultStyle, "Geothermal Power Plant")
		elseif mode == "NuclearPowerPlant" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Power", defaultStyle, "Nuclear Power Plant")
		elseif mode == "SolarPanels" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Power", defaultStyle, "Solar Panels")
		elseif mode == "WindTurbine" then
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Power", defaultStyle, "Wind Turbine")

			-- FLAGS (Individual.Default.Flags)
		elseif mode == "Flags" then
			buildingsList = BuildingMasterList.getIndividualBuildingsByType("Flags", defaultStyle)
		elseif typeof(mode) == "string" and string.sub(mode,1,5) == "Flag:" then
			local flagName = string.sub(mode, 6)
			buildingsList = BuildingMasterList.getIndividualBuildingByName("Flags", defaultStyle, flagName)
		else
			-- NEW: pull zone-set at the chosen wealth (so the actual models match the wealth tier)
			buildingsList = BuildingMasterList.getBuildingsByZone(mode, defaultStyle, defaultWealthState)
		end

		if (#buildingsList == 0) and not predefinedBuildings then
			warn(string.format("BuildingGeneratorModule: No buildings available for mode '%s'.", mode))
			ZoneTrackerModule.setZonePopulating(player, zoneId, false)
			zonePopulatedEvent:Fire(player, zoneId, {})
			return
		end

		-- Compute zone bounds from grid list
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		for _, coord in ipairs(gridList) do
			minX = math.min(minX, coord.x)
			maxX = math.max(maxX, coord.x)
			minZ = math.min(minZ, coord.z)
			maxZ = math.max(maxZ, coord.z)
		end

		local placedBuildingsData   = {}
		local buildingsPlacedCounter = 0
		local nextEventThreshold     = math.random(3, 5)

		local function onBuildingPlaced()
			buildingsPlacedCounter += 1
			if buildingsPlacedCounter >= nextEventThreshold then
				buildingsPlacedEvent:Fire(player, zoneId, buildingsPlacedCounter)
				if shouldPlayBuildUISound(mode) then
					playBuildUISound(player)
				end
				debugPrint(string.format("Fired BuildingsPlaced event for Zone '%s' after %d buildings placed.",
					zoneId, buildingsPlacedCounter))
				buildingsPlacedCounter = 0
				nextEventThreshold = math.random(3, 5)
			end
		end

		local previewsPlaced = 0

		local function normalizeWealth(w)
			if w == nil then return nil end
			if typeof(w) == "number" then
				if w == 0 then return "Poor" end
				if w == 1 then return "Medium" end
				if w == 2 then return "Wealthy" end
			end
			if w == "0" then return "Poor" end
			if w == "1" then return "Medium" end
			if w == "2" then return "Wealthy" end
			if w == "Poor" or w == "Medium" or w == "Wealthy" then return w end
			return nil
		end

		----------------------------------------------------------------
		-- 4) Strictly restore any provided blueprints first
		----------------------------------------------------------------
		if replay and #predefinedBuildings > 0 then
			-- Disable quotas only while restoring saved entries
			quotaCtx.strictRestore = true

			-- Wealth-aware lookup helper
			local function findByNameInWealth(zoneMode, style, wealth, name)
				if not WEALTHED_ZONES[zoneMode] then return nil end
				local list = BuildingMasterList.getBuildingsByZone(zoneMode, style, wealth) or {}
				for _, cand in ipairs(list) do
					if cand and cand.name == name then return cand end
				end
				return nil
			end

			for _, bData in ipairs(predefinedBuildings) do
				local parentFolder = bData.isUtility and utilitiesFolder or zoneFolder

				-- Decide wealth for this tile (override → saved → tracker → default)
				local savedWealth = normalizeWealth(bData.wealth)
				local cellWealth =
					wealthOverride
					or savedWealth
					or ZoneTrackerModule.getGridWealth(player, zoneId, bData.gridX, bData.gridZ)
					or defaultWealthState

				-- Prefer wealth-aware exact match, else hydrate by name, else fallback to bucket
				local selected
				if WEALTHED_ZONES[mode] then
					selected = findByNameInWealth(mode, defaultStyle, cellWealth, bData.buildingName)
						or findByNameInWealth(mode, defaultStyle, "Poor",    bData.buildingName)
						or findByNameInWealth(mode, defaultStyle, "Medium",  bData.buildingName)
						or findByNameInWealth(mode, defaultStyle, "Wealthy", bData.buildingName)
				end
				if not selected then
					selected = BuildingMasterList.getBuildingByName(bData.buildingName)
					if selected and (not selected.stages or not selected.stages.Stage3) then
						local stages = WEALTHED_ZONES[mode]
							and BuildingMasterList.loadBuildingStages(mode, defaultStyle, selected.name, cellWealth)
							or  BuildingMasterList.loadBuildingStages("Individual", defaultStyle, selected.name)
						if stages and stages.Stage3 then
							selected.stages = stages
						end
					end
				end
				if (not selected) or (not selected.stages) or (not selected.stages.Stage3) then
					warn(("[restore/strict] cannot resolve Stage3 for saved '%s' (mode=%s, wealth=%s) @(%d,%d) in zone %s; skipped.")
						:format(tostring(bData.buildingName), tostring(mode), tostring(cellWealth),
							tonumber(bData.gridX) or -1, tonumber(bData.gridZ) or -1, tostring(zoneId)))
					selected = nil
				end

				-- During strict restore, we *never* swap to an alternate due to quotas
				-- (that’s the point of quotaCtx.strictRestore = true)
				debugPrint(("[restore] %s @(%s,%s) wealth=%s selected=%s (st3=%s)")
					:format(
						tostring(bData.buildingName),
						tostring(bData.gridX or bData.x or "?"),
						tostring(bData.gridZ or bData.z or "?"),
						tostring(cellWealth),
						(selected and selected.name) or "nil",
						((selected and selected.stages and selected.stages.Stage3) and "ok") or "nil"
					))

				if selected and selected.stages and selected.stages.Stage3 then
					local rotForThis = bData.rotation
					if rotForThis == nil then rotForThis = 0 end
					if (rotForThis % 90) ~= 0 then
						rotForThis = CARDINALS[math.floor((rotForThis + 45) / 90) % 4 + 1]
					end

					BuildingGeneratorModule.generateBuilding(
						terrain, parentFolder, player, zoneId, mode,
						{ x = bData.gridX, z = bData.gridZ },
						selected,
						bData.isUtility,
						rotForThis,
						onBuildingPlaced,
						cellWealth,
						skipStages,
						nil,
						quotaCtx
					)

					previewsPlaced += 1
					table.insert(placedBuildingsData, {
						buildingName = bData.buildingName,
						rotation     = bData.rotation,
						gridX        = bData.gridX,
						gridZ        = bData.gridZ,
						isUtility    = bData.isUtility
					})
				else
					warn("[BuildingGenerator] restore: failed to select/hydrate Stage3 for", bData.buildingName)
				end
			end

			-- IMPORTANT: re-enable quotas for any subsequent procedural fill
			quotaCtx.strictRestore = false
		end

		----------------------------------------------------------------
		-- 5) Finish populating any remaining empty cells
		----------------------------------------------------------------
		local function record(folder)
			for _, child in ipairs(folder:GetChildren()) do
				if (child:IsA("Model") or child:IsA("BasePart"))
					and child:GetAttribute("ZoneId") == zoneId
				then
					if wealthOverride then
						child:SetAttribute("WealthState", wealthOverride)
					end
					table.insert(placedBuildingsData, {
						buildingName = child:GetAttribute("BuildingName"),
						rotation     = child:GetAttribute("RotationY") or 0,
						gridX        = child:GetAttribute("GridX"),
						gridZ        = child:GetAttribute("GridZ"),
						isUtility    = child:GetAttribute("IsUtility") or false
					})
				end
			end
		end

		-- ✅ CHANGE: always allow continuing build when there are unfilled cells,
		-- even if we restored some predefined buildings.
		if previewsPlaced < #gridList then
			local leftover = placeBuildings(
				player, zoneId, mode, buildingsList, isUtility,
				terrain, zoneFolder, utilitiesFolder,
				minX, maxX, minZ, maxZ,
				onBuildingPlaced, rotation,
				defaultStyle, defaultWealthState,
				quotaCtx
			)

			placeBuildingsSecondPass(
				player, zoneId, mode, buildingsList, isUtility,
				terrain, zoneFolder, utilitiesFolder, leftover,
				minX, maxX, minZ, maxZ,
				onBuildingPlaced, rotation,
				defaultStyle, defaultWealthState,
				quotaCtx
			)

			-- capture everything that was just generated (and normalize WealthState attr)
			record(zoneFolder)
			record(utilitiesFolder)
		end

		----------------------------------------------------------------
		-- 6) Done – mark & notify
		----------------------------------------------------------------
		debugPrint("BuildingGeneratorModule: Zone population complete.")
		debugPrint(string.format(
			"BuildingGeneratorModule: Firing zonePopulatedEvent for zone '%s' with %d buildings.",
			zoneId, #placedBuildingsData
			))

		orientZoneBuildingsTowardRoads(player, zoneId)

		if buildingsPlacedCounter > 0 then
			buildingsPlacedEvent:Fire(player, zoneId, buildingsPlacedCounter)
			if shouldPlayBuildUISound(mode) then
				playBuildUISound(player)
			end
			debugPrint(string.format(
				"Flushed BuildingsPlaced for Zone '%s' with final batch of %d.",
				zoneId, buildingsPlacedCounter
				))
			buildingsPlacedCounter = 0
		end

		ZoneTrackerModule.setZonePopulating(player, zoneId, false)
		zonePopulatedEvent:Fire(player, zoneId, placedBuildingsData)
		ZoneTrackerModule.setZonePopulated(player, zoneId, true)
		worldDirtyEvent:Fire(player, "PopulateZone|" .. tostring(zoneId))
	end)
end

-- Remove buildings associated with a zone
function BuildingGeneratorModule.removeBuilding(player, zoneId, zoneData)
	local plotName = "Plot_" .. player.UserId
	local playerPlot = Workspace.PlayerPlots:FindFirstChild(plotName)
	if not playerPlot then
		warn("BuildingGeneratorModule: Player plot '" .. plotName .. "' not found.")
		return
	end

	local buildingsFolder = playerPlot:FindFirstChild("Buildings")
	if not buildingsFolder then return end

	local populatedFolder = buildingsFolder:FindFirstChild("Populated")
	if not populatedFolder then return end

	local foldersToCheck = {
		populatedFolder:FindFirstChild(zoneId),
		populatedFolder:FindFirstChild("Utilities"),
	}

	for _, folder in ipairs(foldersToCheck) do
		if folder then
			for _, child in ipairs(folder:GetChildren()) do
				if child:IsA("Model") or child:IsA("BasePart") then
					if child:GetAttribute("ZoneId") == zoneId then
						_clearOccupancyForInstance(player, zoneId, child)
						local concretePad = child:FindFirstChild("ConcretePad")
						if concretePad then
							concretePad:Destroy()
						end
						child:Destroy()
					end
				end
			end

			-- If it's the specific zone folder and it's now empty, remove it
			if folder.Name == zoneId and #folder:GetChildren() == 0 then
				folder:Destroy()
			end
		end
	end

	debugPrint("BuildingGeneratorModule: Buildings removed for zone:", zoneId)
end

local nonUpgradeableZoneTypes = {
	WaterTower = true,
	-- Add more zone types here if needed
}

	--[[function BuildingGeneratorModule.upgradeBuilding(player, zoneId, buildingName, newWealthState, mode, style)
		debugPrint(string.format(
			"upgradeBuilding called for '%s' in Zone '%s' to wealth '%s'.",
			buildingName, zoneId, newWealthState
			))

		-- Block upgrade if the zone type should never be upgraded
		if nonUpgradeableZoneTypes[mode] then
			debugPrint("Upgrade blocked: zone type '" .. mode .. "' is non-upgradeable.")
			return
		end

		-- Validate wealth state
		if newWealthState ~= "Poor" and newWealthState ~= "Medium" and newWealthState ~= "Wealthy" then
			warn("Invalid wealth state: " .. newWealthState)
			return
		end

		-- Locate the zone folder
		local plotName = "Plot_" .. player.UserId
		local playerPlot = Workspace.PlayerPlots:FindFirstChild(plotName)
		if not playerPlot then return warn("Plot not found: " .. plotName) end

		local buildingsFolder = playerPlot:FindFirstChild("Buildings")
		if not buildingsFolder then return warn("Missing 'Buildings' folder in plot.") end

		local populatedFolder = buildingsFolder:FindFirstChild("Populated")
		if not populatedFolder then return warn("Missing 'Populated' folder in buildings.") end

		local zoneFolder = populatedFolder:FindFirstChild(zoneId)
		if not zoneFolder then return warn("Zone folder '" .. zoneId .. "' not found.") end

		-- Find the target building inside this zone
		local targetStage3 = nil
		for _, child in ipairs(zoneFolder:GetChildren()) do
			if (child:IsA("Model") or child:IsA("BasePart")) and
				child:GetAttribute("ZoneId") == zoneId and
				child:GetAttribute("BuildingName") == buildingName then
				targetStage3 = child
				break
			end
		end
		if not targetStage3 then return warn("Target building not found in zone.") end

		-- Check for NoUpgrade flag
		if targetStage3:GetAttribute("NoUpgrade") then
			debugPrint("Upgrade blocked: building is flagged as 'NoUpgrade'.")
			return
		end

		-- Get new buildings for the target wealth state
		local upgradeOptions = BuildingMasterList.getBuildingsByZone(mode, style, newWealthState)
		if #upgradeOptions == 0 then
			return warn("No upgrade options found for this mode/style/wealth state.")
		end

		-- Pick a random replacement
		local newBuilding = upgradeOptions[math.random(#upgradeOptions)]
		if not newBuilding.stages or not newBuilding.stages.Stage3 then
			return warn("Replacement building is missing Stage3.")
		end

		-- Record position and remove old building
		local position = targetStage3.PrimaryPart and targetStage3.PrimaryPart.Position or targetStage3.Position
		local isUtility = targetStage3:GetAttribute("IsUtility") or false
		targetStage3:Destroy()

		-- Determine parent folder for the new building
		local parentFolder = isUtility and (populatedFolder:FindFirstChild("Utilities") or Instance.new("Folder")) or zoneFolder
		if isUtility and not parentFolder.Parent then
			parentFolder.Name = "Utilities"
			parentFolder.Parent = populatedFolder
		end

		-- Place the new upgraded building
		local newStage3 = newBuilding.stages.Stage3:Clone()
		if newStage3.PrimaryPart then
			newStage3:SetPrimaryPartCFrame(CFrame.new(position))
		else
			newStage3.Position = position
			newStage3.Orientation = Vector3.new(0, newStage3:GetAttribute("RotationY") or 0, 0)
		end

		newStage3.Parent = parentFolder
		newStage3:SetAttribute("ZoneId", zoneId)
		newStage3:SetAttribute("BuildingName", newBuilding.name)
		if isUtility then newStage3:SetAttribute("IsUtility", true) end

		-- Create or adjust concrete pad
		if newStage3.PrimaryPart then
			createConcretePad(newStage3)
		end

		debugPrint(string.format(
			"Upgrade complete: '%s' → '%s' in Zone '%s' (Wealth: %s)",
			buildingName, newBuilding.name, zoneId, newWealthState
			))
	end
	]]


function BuildingGeneratorModule.upgradeZone(player, zoneId, newWealthState, mode, style)
	debugPrint(string.format("Upgrading zone '%s' to wealth '%s'...", zoneId, newWealthState))

	if not WEALTHED_ZONES[mode] then
		debugPrint(("upgradeZone: ignoring wealth change for non-wealthed mode '%s'"):format(tostring(mode)))
		return
	end

	if nonUpgradeableZoneTypes[mode] then
		debugPrint("Upgrade blocked: zone type is non-upgradeable.")
		return
	end
	if not (newWealthState == "Poor" or newWealthState == "Medium" or newWealthState == "Wealthy") then
		warn("Invalid wealth state: " .. tostring(newWealthState))
		return
	end

	local plotName = "Plot_" .. player.UserId
	local playerPlot = Workspace.PlayerPlots:FindFirstChild(plotName)
	if not playerPlot then return warn("Player plot not found: " .. plotName) end

	local gridList = ZoneTrackerModule.getZoneGridList(player, zoneId)
	if not gridList or #gridList == 0 then return warn("No grid data for zone " .. zoneId) end

	-- 1) Clear instances *and* occupancy
	BuildingGeneratorModule.removeBuilding(player, zoneId)

	-- 2) Re-run full population pipeline with wealth override
	-- NOTE: We keep the old monkey-patch path below purely as a documented fallback.
	BuildingGeneratorModule.populateZone(player, zoneId, mode, gridList, nil, nil, false, newWealthState)

	zonePopulatedEvent:Fire(player, zoneId, {})
	if worldDirtyEvent then worldDirtyEvent:Fire(player, "UpgradeZone|" .. tostring(zoneId)) end

		--[[ LEGACY MONKEY-PATCH PATH (kept for backward compatibility documentation):
		local prev = BuildingMasterList.getBuildingsByZone
		BuildingMasterList.getBuildingsByZone = function(zType, zStyle, wealthState)
			return prev(zType, zStyle, newWealthState)
		end
		BuildingGeneratorModule.populateZone(player, zoneId, mode, gridList, nil)
		BuildingMasterList.getBuildingsByZone = prev
		]]
end

-- Small helpers for the coalescer
local function _mapAddSeedSet(dstSet, cells)
	for _, c in ipairs(cells or {}) do
		if c and typeof(c.x) == "number" and typeof(c.z) == "number" then
			dstSet[tostring(c.x).."|"..tostring(c.z)] = true
		end
	end
end

local function _setToArray(setMap)
	local out = {}
	for key,_ in pairs(setMap) do
		local sep = string.find(key, "|", 1, true)
		local gx = tonumber(string.sub(key, 1, sep - 1))
		local gz = tonumber(string.sub(key, sep + 1))
		if gx and gz then table.insert(out, { x = gx, z = gz }) end
	end
	return out
end

-- Keep wealth normalization aligned with the core behavior
local function _normWealth(w)
	if w == nil then return "Poor" end
	local s = tostring(w)
	if s == "0" then return "Poor" end
	if s == "1" then return "Medium" end
	if s == "2" then return "Wealthy" end
	if s == "Poor" or s == "Medium" or s == "Wealthy" then return s end
	return "Poor"
end

----------------------------------------------------------------
-- 1) RENAME your existing (enhanced) _refillZoneGaps to CORE --
----------------------------------------------------------------
-- Find your current definition:
--   local function _refillZoneGaps(player, zoneId, mode, wealthOverride, rotation, styleOverride, refillSourceZoneId, seededCells)
-- and change ONLY its name to _refillZoneGapsCore. Do not change its body.
local function _refillZoneGapsCore(
	player,
	zoneId,
	mode,
	wealthOverride,
	rotation,
	styleOverride,
	refillSourceZoneId,
	seededCells -- optional array { {x=.., z=..}, ... } to restrict to these cells
)
	-- If this refill was triggered by an overlay and that overlay no longer exists (e.g., undo),
	-- drop out early to prevent late-arriving refills.
	if refillSourceZoneId and not ZoneTrackerModule.getZoneById(player, refillSourceZoneId) then
		return
	end

	-- === Config for batching/cluster behavior ===
	local MAX_CLUSTER = 64          -- hard cap for cluster size (“max bucket”)
	local YIELD_BETWEEN = 0.02      -- cooperative yield between clusters (seconds)
	local DIAGONAL = false          -- 4-neighbor clusters; set true for 8-neighbor

	-- === Locate plot/containers ===
	local plotName = "Plot_" .. player.UserId
	local plot = Workspace.PlayerPlots:FindFirstChild(plotName)
	if not plot then return end

	local terrain = plot:FindFirstChild("TestTerrain")
	if not terrain then return end

	local buildingsFolder = plot:FindFirstChild("Buildings")
	if not buildingsFolder then return end

	local populatedFolder = buildingsFolder:FindFirstChild("Populated")
	if not populatedFolder then return end

	local zoneFolder = populatedFolder:FindFirstChild(zoneId)
	if not zoneFolder then
		zoneFolder = Instance.new("Folder")
		zoneFolder.Name = zoneId
		zoneFolder.Parent = populatedFolder
	end

	local utilitiesFolder = populatedFolder:FindFirstChild("Utilities")
	if not utilitiesFolder then
		utilitiesFolder = Instance.new("Folder")
		utilitiesFolder.Name = "Utilities"
		utilitiesFolder.Parent = populatedFolder
	end

	-- === Compute zone grid bounds ===
	local gridList = ZoneTrackerModule.getZoneGridList(player, zoneId)
	if not gridList or #gridList == 0 then return end

	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, c in ipairs(gridList) do
		if c.x < minX then minX = c.x end
		if c.x > maxX then maxX = c.x end
		if c.z < minZ then minZ = c.z end
		if c.z > maxZ then maxZ = c.z end
	end

	-- === Normalize wealth input ===
	local function normalizeWealth(w)
		if w == nil then return nil end
		local s = tostring(w)
		if s == "0" then return "Poor" end
		if s == "1" then return "Medium" end
		if s == "2" then return "Wealthy" end
		if s == "Poor" or s == "Medium" or s == "Wealthy" then return s end
		return nil
	end

	local style  = styleOverride or "Default"
	local wealth = normalizeWealth(wealthOverride) or "Poor"

	-- === Mode routing: pick list at requested style/wealth ===
	local isUtility = false
	local buildingsList
	if mode == "Utilities" then
		local utilityType = "Water"
		buildingsList = BuildingMasterList.getUtilitiesByType(utilityType, style)
		isUtility = true
	elseif mode == "Road" then
		buildingsList = BuildingMasterList.getRoadsByStyle(style)
		isUtility = true
	else
		buildingsList = BuildingMasterList.getBuildingsByZone(mode, style, wealth)
	end
	if not buildingsList or #buildingsList == 0 then return end

	-- === Quota context based on current zone contents ===
	local quotaCtx = newQuotaContext(mode, player, zoneId)
	scanZoneCountsInto(quotaCtx)

	-- === Helpers for clustering & whitelist ===
	local function _k(x, z) return tostring(x).."|"..tostring(z) end

	local function _neighbors(x, z)
		if DIAGONAL then
			return {
				{x+1, z}, {x-1, z}, {x, z+1}, {x, z-1},
				{x+1, z+1}, {x-1, z+1}, {x+1, z-1}, {x-1, z-1},
			}
		else
			return { {x+1, z}, {x-1, z}, {x, z+1}, {x, z-1} }
		end
	end

	local function _clusterSeeds(cells)
		-- Returns array of clusters: each cluster is an array of {x,z}, capped at MAX_CLUSTER
		if not (cells and #cells > 0) then return {} end

		-- Stable order for determinism
		table.sort(cells, function(a,b) return (a.x < b.x) or (a.x == b.x and a.z < b.z) end)

		-- Presence map
		local remain = {}
		for _, c in ipairs(cells) do remain[_k(c.x, c.z)] = { x = c.x, z = c.z } end

		local out = {}
		for _, seed in ipairs(cells) do
			local key = _k(seed.x, seed.z)
			local start = remain[key]
			if start then
				remain[key] = nil
				local q = { start }
				local qi = 1
				local pack = {}

				while qi <= #q do
					local p = q[qi]; qi += 1
					table.insert(pack, p)
					if #pack >= MAX_CLUSTER then
						table.insert(out, pack)
						pack = {}
					end
					for _, n in ipairs(_neighbors(p.x, p.z)) do
						local nk = _k(n[1], n[2])
						local nxt = remain[nk]
						if nxt then
							remain[nk] = nil
							table.insert(q, nxt)
						end
					end
				end

				if #pack > 0 then
					table.insert(out, pack)
				end
			end
		end

		-- Order clusters by their min (x,z) for locality-friendly scheduling
		table.sort(out, function(A,B)
			local ax, az = math.huge, math.huge
			for i = 1, #A do local a = A[i]; if a.x < ax or (a.x == ax and a.z < az) then ax, az = a.x, a.z end end
			local bx, bz = math.huge, math.huge
			for i = 1, #B do local b = B[i]; if b.x < bx or (b.x == bx and b.z < bz) then bx, bz = b.x, b.z end end
			return (ax < bx) or (ax == bx and az < bz)
		end)

		return out
	end

	-- === Prefer exported helpers; fall back to locals if needed ===
	local pass1 = (BuildingGeneratorModule and BuildingGeneratorModule._placeBuildings) or placeBuildings
	local pass2 = (BuildingGeneratorModule and BuildingGeneratorModule._placeBuildingsSecondPass) or placeBuildingsSecondPass
	if type(pass1) ~= "function" or type(pass2) ~= "function" then
		warn("[_refillZoneGaps] placement helpers not available; aborting.")
		return
	end

	-- === Snapshot existing origin cells before we place (for RefilledBy tagging) ===
	local preKeys = {}
	local function collectPre(folder)
		if not folder then return end
		for _, inst in ipairs(folder:GetChildren()) do
			if (inst:IsA("Model") or inst:IsA("BasePart"))
				and inst:GetAttribute("ZoneId") == zoneId
			then
				local gx = inst:GetAttribute("GridX")
				local gz = inst:GetAttribute("GridZ")
				if gx and gz then
					preKeys[gx .. "_" .. gz] = true
				end
			end
		end
	end
	collectPre(zoneFolder)
	collectPre(utilitiesFolder)

	-- === Run in either full-scan mode (no seeds) or clustered whitelist mode ===
	local function runOneWhitelist(whitelistMap)
		local function noop() end
		local leftover = pass1(
			player, zoneId, mode, buildingsList, isUtility,
			terrain, zoneFolder, utilitiesFolder,
			minX, maxX, minZ, maxZ,
			noop, rotation,
			style, wealth,
			quotaCtx,
			whitelistMap   -- ONLY these tiles
		)

		pass2(
			player, zoneId, mode, buildingsList, isUtility,
			terrain, zoneFolder, utilitiesFolder, leftover,
			minX, maxX, minZ, maxZ,
			noop, rotation,
			style, wealth,
			quotaCtx
		)
	end

	if type(seededCells) == "table" and #seededCells > 0 then
		-- Cluster seeds and process cluster-by-cluster
		local clusters = _clusterSeeds(seededCells)
		for _, cluster in ipairs(clusters) do
			-- Build whitelist map for this cluster only
			local wl = {}
			for i = 1, #cluster do
				local c = cluster[i]
				wl[_k(c.x, c.z)] = true
			end
			runOneWhitelist(wl)
			task.wait(YIELD_BETWEEN)
		end
	else
		-- No seeds provided → full-zone pass (legacy behavior)
		runOneWhitelist(nil)
	end

	-- === Normalize WealthState attributes so upgrades read correct tier ===
	local function normalizeWealthAttr(folder)
		if not folder then return end
		for _, inst in ipairs(folder:GetChildren()) do
			if (inst:IsA("Model") or inst:IsA("BasePart"))
				and inst:GetAttribute("ZoneId") == zoneId
			then
				if (inst:GetAttribute("WealthState") or "Poor") ~= wealth then
					inst:SetAttribute("WealthState", wealth)
				end
			end
		end
	end
	normalizeWealthAttr(zoneFolder)
	normalizeWealthAttr(utilitiesFolder)

	-- === Tag only *newly created* instances so overlay undo can remove them cleanly ===
	if refillSourceZoneId then
		local function tagNew(folder)
			if not folder then return end
			for _, inst in ipairs(folder:GetChildren()) do
				if (inst:IsA("Model") or inst:IsA("BasePart"))
					and inst:GetAttribute("ZoneId") == zoneId
				then
					local gx = inst:GetAttribute("GridX")
					local gz = inst:GetAttribute("GridZ")
					if gx and gz and not preKeys[gx .. "_" .. gz] then
						inst:SetAttribute("RefilledBy", refillSourceZoneId)
					end
				end
			end
		end
		tagNew(zoneFolder)
		tagNew(utilitiesFolder)
	end

	-- === Optional: keep visuals consistent after fills ===
	if typeof(orientZoneBuildingsTowardRoads) == "function" then
		orientZoneBuildingsTowardRoads(player, zoneId)
	end
	zonePopulatedEvent:Fire(player, zoneId, {})
	if worldDirtyEvent then
		worldDirtyEvent:Fire(player, "UpgradeZone|" .. tostring(zoneId))
	end
end

----------------------------------------------------------------
-- 2) COALESCING WRAPPER (new)                                --
----------------------------------------------------------------
-- NEW public wrapper: coalesces seeds and serializes per zone
local function _refillZoneGaps(
	player,
	zoneId,
	mode,
	wealthOverride,
	rotation,
	styleOverride,
	refillSourceZoneId,
	seededCells -- optional { {x,z}, ... }
)
	-- compute the per-zone key once
	local k = _key(player, zoneId)

	-- Merge seeds into per-zone queue (bucket by wealth)
	if seededCells and #seededCells > 0 then
		local w = _normWealth(wealthOverride)
		_refillSeeds[k] = _refillSeeds[k] or {}
		_refillSeeds[k][w] = _refillSeeds[k][w] or {}
		_mapAddSeedSet(_refillSeeds[k][w], seededCells)
	else
		-- No seeds => a full-scan request. If a worker exists, coalesce the request;
		-- otherwise we must enqueue it now so the first drain loop actually runs it.
		local req = {
			mode     = mode,
			rotation = rotation,
			style    = styleOverride,
			source   = refillSourceZoneId,
		}
		if _refillBusy[k] then
			_refillFullScan[k] = req
			return
		else
			_refillFullScan[k] = req   -- <-- **FIX** enqueue even when idle
		end
	end

	-- If someone is already processing this zone, they'll pick up our merged seeds/full-scan.
	if _refillBusy[k] then return end

	-- Acquire the per-zone worker lock
	_refillBusy[k] = true

	-- Drain loop: process seeds in wealth-tier order until empty; finally do any coalesced full-scan.
	local ok, err = pcall(function()
		local tierOrder = { "Poor", "Medium", "Wealthy" }
		while true do
			-- Pick the next wealth bucket with seeds
			local pickedWealth, setMap = nil, nil
			for _, w in ipairs(tierOrder) do
				if _refillSeeds[k] and _refillSeeds[k][w] and next(_refillSeeds[k][w]) then
					pickedWealth = w
					setMap       = _refillSeeds[k][w]
					_refillSeeds[k][w] = {} -- clear bucket; newly arriving seeds go into a fresh map
					break
				end
			end

			-- No seeds left — maybe a full-scan is pending?
			if not pickedWealth then
				local fs = _refillFullScan[k]
				if fs then
					-- run exactly one coalesced full-scan
					_refillFullScan[k] = nil
					_refillZoneGapsCore(
						player, zoneId,
						fs.mode or mode,
						nil,                 -- nil wealth => let core choose/default
						fs.rotation, fs.style, fs.source,
						nil                  -- no whitelist
					)
					-- loop again: handle anything that arrived while core ran
					continue
				end
				break -- nothing left to do
			end

			-- Convert set map → array of seeds and run the core in seeded/whitelist mode
			local seeds = _setToArray(setMap)
			if #seeds > 0 then
				_refillZoneGapsCore(
					player, zoneId, mode,
					pickedWealth, rotation, styleOverride, refillSourceZoneId,
					seeds
				)
			end

			-- Loop continues to pick up any newly arrived seeds.
			continue
		end
	end)

	-- Always release lock (clear per-zone buffers)
	_refillBusy[k]      = nil
	_refillSeeds[k]     = nil
	_refillFullScan[k]  = nil

	if not ok then
		warn("[_refillZoneGaps] coalescer error for zone "..tostring(zoneId)..": "..tostring(err))
	end
end

-- Re-bind the public entry point
BuildingGeneratorModule._refillZoneGaps = _refillZoneGaps
math.randomseed(os.clock())

function BuildingGeneratorModule.removeRefillPlacementsForOverlay(player, sourceZoneId)
	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_" .. player.UserId)
	if not plot then return end

	local populated = plot:FindFirstChild("Buildings")
		and plot.Buildings:FindFirstChild("Populated")
	if not populated then return end

	for _, folder in ipairs(populated:GetChildren()) do
		for _, inst in ipairs(folder:GetChildren()) do
			if (inst:IsA("Model") or inst:IsA("BasePart"))
				and inst:GetAttribute("RefilledBy") == sourceZoneId
			then
				-- Clear occupancy for the whole footprint, then delete the instance.
				local zid = inst:GetAttribute("ZoneId")
				_clearOccupancyForInstance(player, zid or sourceZoneId, inst)
				inst:Destroy()
			end
		end
	end
end

local function shuffle(t)
	for i = #t, 2, -1 do
		local j = math.random(i)
		t[i], t[j] = t[j], t[i]
	end
end

function BuildingGeneratorModule.upgradeGrid(player, zoneId, gridX, gridZ, newWealthState, mode, style)
	debugPrint(("upgradeGrid → Zone '%s' @ (%d,%d) to wealth '%s'"):format(zoneId, gridX, gridZ, newWealthState))

	local plotName = "Plot_" .. player.UserId
	local plot = Workspace.PlayerPlots:FindFirstChild(plotName)
	if not plot then return warn("upgradeGrid: no plot for", player.UserId) end

	local populated = plot:FindFirstChild("Buildings")
		and plot.Buildings:FindFirstChild("Populated")
	if not populated then return warn("upgradeGrid: no Populated folder") end

	local function rotationCandidatesFor(mode, cand)
		-- Only restrict square-only zone modes; Individual may use all four.
		if SQUARE_ONLY_MODES[mode] and not isSquareFootprintByData(cand) then
			return {0, 180}
		end
		return {0, 90, 180, 270}
	end

	-- Identify target instance (exact match or coverage)
	local target, parentName, originGX, originGZ, coverageHit = nil, nil, nil, nil, false

	for _, fn in ipairs({ zoneId, "Utilities" }) do
		local folder = populated:FindFirstChild(fn)
		if not folder then continue end

		for _, inst in ipairs(folder:GetChildren()) do
			if inst:GetAttribute("ZoneId") == zoneId
				and inst:GetAttribute("GridX") == gridX
				and inst:GetAttribute("GridZ") == gridZ
			then
				target, parentName, originGX, originGZ = inst, fn, gridX, gridZ
				break
			end
		end

		if not target then
			for _, inst in ipairs(folder:GetChildren()) do
				if (inst:IsA("Model") or inst:IsA("BasePart"))
					and inst:GetAttribute("ZoneId") == zoneId
				then
					local gx, gz = inst:GetAttribute("GridX"), inst:GetAttribute("GridZ")
					local rotY = inst:GetAttribute("RotationY") or 0
					local bnm = inst:GetAttribute("BuildingName")
					if gx and gz and bnm then
						local w, d = _stage3FootprintCells(bnm, rotY)
						if gridX >= gx and gridX < gx + w and gridZ >= gz and gridZ < gz + d then
							target, parentName, originGX, originGZ, coverageHit = inst, fn, gx, gz, true
							break
						end
					end
				end
			end
		end

		if target then break end
	end

	if not target then
		return debugPrint("upgradeGrid: no building at", gridX, gridZ)
	end

	if coverageHit then
		debugPrint(("upgradeGrid: coverage hit origin (%d,%d) for click (%d,%d)")
			:format(originGX, originGZ, gridX, gridZ))
	end

	if not originGX or not originGZ then
		originGX = target:GetAttribute("GridX") or gridX
		originGZ = target:GetAttribute("GridZ") or gridZ
	end

	if (target:GetAttribute("WealthState") or "Poor") == newWealthState then
		debugPrint("upgradeGrid: tile already " .. tostring(newWealthState))
		return
	end

	local quotaCtx = newQuotaContext(mode, player, zoneId)
	scanZoneCountsInto(quotaCtx)

	local zoneData = ZoneTrackerModule.getZoneById(player, zoneId)
	if not zoneData then return warn("upgradeGrid: no ZoneTracker data for", zoneId) end

	local bounds = { minX = math.huge, maxX = -math.huge, minZ = math.huge, maxZ = -math.huge }
	for _, c in ipairs(zoneData.gridList) do
		bounds.minX = math.min(bounds.minX, c.x)
		bounds.maxX = math.max(bounds.maxX, c.x)
		bounds.minZ = math.min(bounds.minZ, c.z)
		bounds.maxZ = math.max(bounds.maxZ, c.z)
	end

	style = style or "Default"

	-- Archive the old instance for undo
	LayerManagerModule.storeRemovedObject("Buildings", zoneId, {
		instanceClone = target:Clone(),
		parentName = parentName,
		gridX = originGX,
		gridZ = originGZ,
		rotationY = target:GetAttribute("RotationY") or 0,
		wealthState = target:GetAttribute("WealthState"),
	})

	-- Unmark occupancy for the old building (and try to drop it from the quadtree)
	local oldName, oldRot = target:GetAttribute("BuildingName"), target:GetAttribute("RotationY") or 0
	local oldData = BuildingMasterList.getBuildingByName(oldName)
	if oldData and oldData.stages and oldData.stages.Stage3 then
		local stg3 = oldData.stages.Stage3
		local sizeV = (stg3:IsA("Model") and stg3.PrimaryPart and stg3.PrimaryPart.Size) or stg3.Size
		if sizeV then
			local w, d = math.ceil(sizeV.X / GRID_SIZE), math.ceil(sizeV.Z / GRID_SIZE)
			if oldRot == 90 or oldRot == 270 then w, d = d, w end
			local oldBuildingId = zoneId .. "_" .. originGX .. "_" .. originGZ
			for x = originGX, originGX + w - 1 do
				for z = originGZ, originGZ + d - 1 do
					ZoneTrackerModule.unmarkGridOccupied(player, x, z, 'building', oldBuildingId)
				end
			end
			-- Best-effort quadtree removal
			pcall(function() if QuadtreeService and QuadtreeService.removeById then QuadtreeService:removeById(oldBuildingId) end end)
		end
	end

	-- Remove the old instance (pad goes with it)
	target:Destroy()

	-- Candidate selection at the new wealth tier
	local DECORATION_WEIGHT_FACTOR = 0.5
	local function getWeight(zoneMode, wealth, buildingName)
		local base = 1
		if isDecorationName(zoneMode, buildingName) then
			return base * DECORATION_WEIGHT_FACTOR
		end
		return base
	end

	local options = BuildingMasterList.getBuildingsByZone(mode, style, newWealthState) or {}

	local function footprint(cand, rot)
		if not cand or not cand.stages or not cand.stages.Stage3 then return 1, 1 end
		local stg3 = cand.stages.Stage3
		local sv = (stg3:IsA("Model") and stg3.PrimaryPart and stg3.PrimaryPart.Size) or stg3.Size
		if not sv then return 1, 1 end
		local w, d = math.ceil(sv.X / GRID_SIZE), math.ceil(sv.Z / GRID_SIZE)
		if rot == 90 or rot == 270 then w, d = d, w end
		return w, d
	end

	local viable = {}
	for _, cand in ipairs(options) do
		if cand and cand.stages and cand.stages.Stage3 then
			if not (isDecorationName(mode, cand.name)
				and wouldViolateQuota(quotaCtx, mode, newWealthState, cand.name))
			then
				local fitting = {}
				for _, rot in ipairs(rotationCandidatesFor(mode, cand)) do
					local w, d = footprint(cand, rot)
					if BuildingGeneratorModule.canPlaceBuilding(
						player, bounds, { width = w, depth = d }, originGX, originGZ, zoneId, mode
						) then
						table.insert(fitting, rot)
					end
				end
				if #fitting > 0 then
					table.insert(viable, {
						building = cand,
						rotations = fitting,
						weight = getWeight(mode, newWealthState, cand.name),
					})
				end
			end
		end
	end

	if #viable == 0 then return warn("upgradeGrid: no fitting building for", mode, newWealthState) end

	local total, chosen, chosenRotation = 0, nil, nil
	for _, v in ipairs(viable) do total += v.weight end
	local r = math.random() * total
	for _, v in ipairs(viable) do
		r -= v.weight
		if r <= 0 then
			chosen, chosenRotation = v.building, v.rotations[math.random(#v.rotations)]
			break
		end
	end
	chosen = chosen or viable[1].building
	chosenRotation = chosenRotation or viable[1].rotations[1]

	-- Ensure the destination folder exists
	local outFolder = populated:FindFirstChild(parentName)
	if not outFolder then
		outFolder = Instance.new("Folder")
		outFolder.Name = parentName
		outFolder.Parent = populated
	end

	-- Place the replacement
	BuildingGeneratorModule.generateBuilding(
		plot:FindFirstChild("TestTerrain"),
		outFolder,
		player,
		zoneId,
		mode,
		{ x = originGX, z = originGZ },
		chosen,
		parentName == "Utilities",
		chosenRotation,
		nil,              -- onPlaced
		newWealthState,   -- wealth for the new placement
		nil,              -- skipStages
		quotaCtx
	)

	-- Compute old vs new footprint (for vacated tiles)
	local oldW, oldD = 1, 1
	if oldData and oldData.stages and oldData.stages.Stage3 then
		oldW, oldD = footprint(oldData, oldRot)
	end
	local newW, newD = footprint(chosen, chosenRotation)

	-- === REFILL VACATED CELLS (seeded & quota/wealth aware via UXP coalescer) ===
	do
		-- Build buckets of vacated cells by wealth
		local buckets = { Poor = {}, Medium = {}, Wealthy = {} }

		for dx = 0, oldW - 1 do
			for dz = 0, oldD - 1 do
				-- cell is in the old footprint but NOT covered by the new one
				if not (dx < newW and dz < newD) then
					local x, z = originGX + dx, originGZ + dz

					-- keep within this zone's bounds
					if x >= bounds.minX and x <= bounds.maxX and z >= bounds.minZ and z <= bounds.maxZ then
						-- Do not refill if something (not from this zone or excluded overlay) already occupies it
						local occ = ZoneTrackerModule.isGridOccupied(
							player, x, z,
							{ excludeOccupantId = zoneId, excludeZoneTypes = OverlapExclusions }
						)
						if not occ then
							-- Resolve tile wealth (prefer tracker per-tile, fallback to newWealthState, else Poor)
							local w = WEALTHED_ZONES[mode]
								and ZoneTrackerModule.getGridWealth(player, zoneId, x, z)
								or nil
							w = w or newWealthState or "Poor"

							-- normalize (accept numbers 0/1/2 and strings)
							if w == 0 or w == "0" then
								w = "Poor"
							elseif w == 1 or w == "1" then
								w = "Medium"
							elseif w == 2 or w == "2" then
								w = "Wealthy"
							elseif w ~= "Poor" and w ~= "Medium" and w ~= "Wealthy" then
								w = "Poor"
							end

							buckets[w] = buckets[w] or {}
							table.insert(buckets[w], { x = x, z = z })
						end
					end
				end
			end
		end

		-- Dispatch seeds to the coalescer
		local countSeeds = #(buckets.Poor or {}) + #(buckets.Medium or {}) + #(buckets.Wealthy or {})
		if countSeeds > 0 then
			if WEALTHED_ZONES[mode] then
				-- Wealthed zones: use per-tier seeded refills (clusters + quotas)
				BuildingGeneratorModule.seededRefillByWealth(player, zoneId, mode, buckets)
			else
				-- Non-wealthed: pass all seeds in one shot
				local seeds = {}
				for _, arr in pairs(buckets) do
					for i = 1, #arr do seeds[#seeds + 1] = arr[i] end
				end
				if #seeds > 0 then
					BuildingGeneratorModule._refillZoneGaps(
						player, zoneId, mode,
						nil,           -- wealthOverride
						nil,           -- rotation
						"Default",     -- style
						nil,           -- refillSourceZoneId
						seeds          -- seededCells
					)
				end
			end
		end
	end

	-- Keep visuals consistent after change
	if typeof(orientZoneBuildingsTowardRoads) == "function" then
		orientZoneBuildingsTowardRoads(player, zoneId)
	end
	zonePopulatedEvent:Fire(player, zoneId, {})
	if worldDirtyEvent then worldDirtyEvent:Fire(player, "Refill|" .. tostring(zoneId)) end
end



	--[[Upgrade building function
	function BuildingGeneratorModule.upgradeBuilding(player, zoneId, buildingName, newWealthState, mode, style)
		debugPrint(string.format("upgradeBuilding called for building '%s' in Zone '%s' to wealth state '%s'.", buildingName, zoneId, newWealthState))
		if newWealthState ~= "Poor" and newWealthState ~= "Medium" and newWealthState ~= "Wealthy" then
			warn(string.format("BuildingGeneratorModule: Invalid wealth state '%s'.", newWealthState))
			return
		end
		local plotName = "Plot_" .. player.UserId
		local playerPlot = Workspace.PlayerPlots:FindFirstChild(plotName)
		if not playerPlot then
			warn("BuildingGeneratorModule: Player plot '" .. plotName .. "' not found in Workspace.PlayerPlots.")
			return
		end
		local buildingsFolder = playerPlot:FindFirstChild("Buildings")
		if not buildingsFolder then
			warn("BuildingGeneratorModule: 'Buildings' folder not found under player plot '" .. plotName .. "'.")
			return
		end
		local populatedFolder = buildingsFolder:FindFirstChild("Populated")
		if not populatedFolder then
			warn("BuildingGeneratorModule: 'Populated' folder not found.")
			return
		end
		local zoneFolder = populatedFolder:FindFirstChild(zoneId)
		if not zoneFolder then
			warn(string.format("BuildingGeneratorModule: Zone folder '%s' not found under 'Populated'.", zoneId))
			return
		end
		local targetStage3
		for _, child in ipairs(zoneFolder:GetChildren()) do
			if child:IsA("Model") or child:IsA("BasePart") then
				if child:GetAttribute("ZoneId") == zoneId and child:GetAttribute("BuildingName") == buildingName then
					targetStage3 = child
					break
				end
			end
		end
		if not targetStage3 then
			warn(string.format("BuildingGeneratorModule: Building '%s' not found in Zone '%s'.", buildingName, zoneId))
			return
		end
		local newBuildings = BuildingMasterList.getBuildingsByZone(mode, style, newWealthState)
		if #newBuildings == 0 then
			warn(string.format("BuildingGeneratorModule: No building data found for '%s' in wealth state '%s'.", buildingName, newWealthState))
			return
		end
		local newBuildingInfo
		for _, building in ipairs(newBuildings) do
			if building.name == buildingName then
				newBuildingInfo = building
				break
			end
		end
		if not newBuildingInfo then
			warn(string.format("BuildingGeneratorModule: Building '%s' does not have a model in wealth state '%s'.", buildingName, newWealthState))
			return
		end
		if not newBuildingInfo.stages.Stage3 then
			warn(string.format("BuildingGeneratorModule: 'Stage3' for building '%s' in wealth state '%s' is missing.", buildingName, newWealthState))
			return
		end
		local currentPosition = targetStage3.PrimaryPart and targetStage3.PrimaryPart.Position or targetStage3.Position
		local isUtility = targetStage3:GetAttribute("IsUtility") or false
		local parentFolder
		if isUtility then
			parentFolder = populatedFolder:FindFirstChild("Utilities")
			if not parentFolder then
				parentFolder = Instance.new("Folder")
				parentFolder.Name = "Utilities"
				parentFolder.Parent = populatedFolder
			end
		else
			parentFolder = zoneFolder
		end
		targetStage3:Destroy()
		local newStage3 = newBuildingInfo.stages.Stage3:Clone()
		if newStage3.PrimaryPart then
			newStage3:SetPrimaryPartCFrame(CFrame.new(currentPosition))
		else
			newStage3.Position = currentPosition
			newStage3.Orientation = Vector3.new(0, newStage3:GetAttribute("RotationY") or 0, 0)
		end
		newStage3.Parent = parentFolder
		newStage3:SetAttribute("ZoneId", zoneId)
		newStage3:SetAttribute("BuildingName", newBuildingInfo.name)
		if isUtility then
			newStage3:SetAttribute("IsUtility", true)
		end
		local concretePad = parentFolder:FindFirstChild("ConcretePad")
		if concretePad and newStage3.PrimaryPart then
			concretePad.Size = Vector3.new(newStage3.PrimaryPart.Size.X, CONCRETE_PAD_HEIGHT, newStage3.PrimaryPart.Size.Z)
			concretePad.Position = newStage3.PrimaryPart.Position - Vector3.new(0, (newStage3.PrimaryPart.Size.Y / 2) + (CONCRETE_PAD_HEIGHT / 2), 0)
		elseif newStage3.PrimaryPart then
			createConcretePad(newStage3)
		end
		debugPrint(string.format("BuildingGeneratorModule: Upgraded building '%s' in Zone '%s' to wealth state '%s'.", buildingName, zoneId, newWealthState))
	end
	]]

-- Returns a list of { inst, parentName, originGX, originGZ } for all instances whose Stage3 footprint touches any tile in tileSet.
-- tileSet: { ["x|z"]=true, ... }
function BuildingGeneratorModule.collectInstancesTouchingTiles(player, zoneId, tileSet)
	local out = {}
	local plot = Workspace:FindFirstChild("PlayerPlots")
	plot = plot and plot:FindFirstChild("Plot_"..player.UserId)
	if not plot then return out end

	local populated = plot:FindFirstChild("Buildings")
	populated = populated and populated:FindFirstChild("Populated")
	if not populated then return out end

	local function footprintCells(inst)
		local gx = inst:GetAttribute("GridX")
		local gz = inst:GetAttribute("GridZ")
		local rotY = inst:GetAttribute("RotationY") or 0
		local bnm  = inst:GetAttribute("BuildingName")
		if not (gx and gz and bnm) then return nil end
		local w, d = BuildingGeneratorModule._stage3FootprintCells(bnm, rotY)
		return gx, gz, w, d
	end

	for _, folder in ipairs(populated:GetChildren()) do
		for _, inst in ipairs(folder:GetChildren()) do
			if (inst:IsA("Model") or inst:IsA("BasePart")) and inst:GetAttribute("ZoneId") == zoneId then
				local gx, gz, w, d = footprintCells(inst)
				if gx then
					local touches = false
					for x = gx, gx + w - 1 do
						for z = gz, gz + d - 1 do
							if tileSet[ tostring(x).."|"..tostring(z) ] then
								touches = true; break
							end
						end
						if touches then break end
					end
					if touches then
						table.insert(out, {
							inst       = inst,
							parentName = folder.Name,
							originGX   = gx,
							originGZ   = gz,
						})
					end
				end
			end
		end
	end
	return out
end

-- Archives + clears occupancy/quadtree + destroys all instances in the list.
function BuildingGeneratorModule.bulkRemoveInstances(player, zoneId, instanceList)
	for _, rec in ipairs(instanceList or {}) do
		local inst      = rec.inst
		local parentStr = rec.parentName or "Zone"
		local gx        = rec.originGX
		local gz        = rec.originGZ
		if inst and inst.Parent then
			-- Archive for undo
			LayerManagerModule.storeRemovedObject("Buildings", zoneId, {
				instanceClone = inst:Clone(),
				parentName    = parentStr,
				gridX         = gx,
				gridZ         = gz,
				rotationY     = inst:GetAttribute("RotationY") or 0,
				wealthState   = inst:GetAttribute("WealthState"),
			})
			-- Clear occupancy for full footprint
			local rotY = inst:GetAttribute("RotationY") or 0
			local bnm  = inst:GetAttribute("BuildingName")
			if gx and gz and bnm then
				local w, d = BuildingGeneratorModule._stage3FootprintCells(bnm, rotY)
				local buildingId = ("%s_%d_%d"):format(zoneId, gx, gz)
				for x = gx, gx + w - 1 do
					for z = gz, gz + d - 1 do
						ZoneTrackerModule.unmarkGridOccupied(player, x, z, 'building', buildingId)
					end
				end
				-- Best-effort quadtree remove
				local buildingObjectId = buildingId
				pcall(function() QuadtreeService:removeById(buildingObjectId) end)
			end
			-- remove pad (visual tidy)
			local pad = inst:FindFirstChild("ConcretePad")
			if pad then pad:Destroy() end
			inst:Destroy()
		end
	end
end

CLUSTER_CONF.max_cluster   = 64        -- set 32/128/etc
CLUSTER_CONF.diagonal      = false     -- set true for 8-neighbors
CLUSTER_CONF.yield_between = 0.02      -- bump to 0.05 if you want snappier input

-- Buckets = { Poor = { {x=..,z=..}, ... }, Medium = {...}, Wealthy = {...} }
-- Uses the existing seeded gap filler, strict to the wealth you pass.
function BuildingGeneratorModule.seededRefillByWealth(player, zoneId, mode, buckets)
	if type(BuildingGeneratorModule._refillZoneGaps) ~= "function" then
		warn("[seededRefillByWealth] _refillZoneGaps not available"); return
	end

	for _, wealth in ipairs({ "Poor", "Medium", "Wealthy" }) do
		local cells = buckets[wealth]
		if cells and #cells > 0 then
			local clusters = _clusterCells(cells, CLUSTER_CONF)
			for _, cluster in ipairs(clusters) do
				-- style="Default", rotation=nil, refillSourceZoneId=nil, whitelist=cluster
				BuildingGeneratorModule._refillZoneGaps(
					player, zoneId, mode, wealth, nil, "Default", nil, cluster
				)
				-- Respect fast-build scaling during huge jobs
				waitScaled(CLUSTER_CONF.yield_between or 0.02)
			end
		end
	end
end


return BuildingGeneratorModule
--Line 3308
