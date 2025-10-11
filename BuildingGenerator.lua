	-- BuildingGeneratorModule.lua line 1
	local BuildingGeneratorModule = {}
	BuildingGeneratorModule.__index = BuildingGeneratorModule

	-- References
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Workspace = game:GetService("Workspace")
	local BuildingManager = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("BuildingManager")
	local ServerScriptService = game:GetService("ServerScriptService")
	local BE = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents")
	local zoneRemovedEvent = BE:WaitForChild("ZoneRemoved")
	local PadPoleSpawned = BE:WaitForChild("PadPoleSpawned")
	-- Added for enhancements:
	local zonePopulatedEvent = BE:WaitForChild("ZonePopulated")

	-- BuildingsPlaced Event
	local buildingsPlacedEvent = BE:WaitForChild("BuildingsPlaced")
	local Wigw8mPlacedEvent = BE:WaitForChild("Wigw8mPlaced")

	-- Grid Utilities
	local Scripts = ReplicatedStorage:WaitForChild("Scripts")
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
		MetroTunnel     = true,   -- << ADD
		MetroTunnelZone = true,   -- << ADD (some systems prefix/alias the zoneType)
	}


	-- Debug Configuration
	local DEBUG = false
	local function debugPrint(...)
		if DEBUG then
			print("[BuildingGenerator]", ...)
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
	if not ctx then return false end
	local totalAfter = (ctx.total or 0) + 1

	-- Commercial (Wealthy): limit ComW4
	if mode == "Commercial" and wealth == "Wealthy" and buildingName == "ComW4" then
		local curr = ctx.byName["ComW4"] or 0
		if ((curr + 1) / totalAfter) > QUOTA_CAP then
			return true
		end
	end

	-- CommDense: limit aggregate HComP6/HComP12/HComP1
	if mode == "CommDense" and COMM_DENSE_CAP_MEMBERS[buildingName] then
		local curr = ctx.group.CommDense or 0
		if ((curr + 1) / totalAfter) > QUOTA_CAP then
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

	local prefab  = BuildingMasterList.getPowerLinesByStyle("Default")[1]and BuildingMasterList.getPowerLinesByStyle("Default")[1].stages.Stage3
	local electricBoxPrefab = BuildingMasterList.getIndividualBuildingByName("Power", "Default", "ElectricBox") and BuildingMasterList.getIndividualBuildingByName("Power", "Default", "ElectricBox")[1]

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
		polePrefab = polePrefab or prefab
		local seen = {}
		for _, d in ipairs(buildingModel:GetDescendants()) do
			if d.Name == "PadPole" then seen[d] = true end
		end

		-- Call the original local helper
		spawnPadPowerPoles(buildingModel, polePrefab)

		-- Tag only the poles that were just created
		if attrTable then
			for _, d in ipairs(buildingModel:GetDescendants()) do
				if d.Name == "PadPole" and not seen[d] then
					for k, v in pairs(attrTable) do
						d:SetAttribute(k, v)
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

			-- Compute building's world position
			local cellCenterX, _, cellCenterZ =
				GridUtils.globalGridToWorldPosition(gridCoord.x, gridCoord.z, gBounds, gTerrains)

			local topLeftWorldX = cellCenterX - (GRID_SIZE / 2)
			local topLeftWorldZ = cellCenterZ - (GRID_SIZE / 2)

			local buildingWidthWorld  = rotatedWidth * GRID_SIZE
			local buildingDepthWorld  = rotatedDepth * GRID_SIZE
			local halfWidthWorld      = buildingWidthWorld * 0.5
			local halfDepthWorld      = buildingDepthWorld * 0.5

			local finalPosition = Vector3.new(
				topLeftWorldX + halfWidthWorld,
				terrainPos.Y + (terrainSize.Y / 2) + 0.1 + Y_OFFSET,
				topLeftWorldZ + halfDepthWorld
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
				if #allTracks > 0 then
					for _, track in ipairs(allTracks) do
						while track.Length == 0 do task.wait() end
						waitDuration = math.max(waitDuration, track.Length)
						track:Play()
					end
					task.wait(waitDuration)
				else
					task.wait(BUILDING_INTERVAL)
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
				task.wait(BUILDING_INTERVAL)
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
	return type(zid) == "string" and zid:match("^RoadZone_") ~= nil
end

local function nearestRoadTargetFor(buildingInstance : Instance) : Vector3?
	local plot = getOwningPlotFor(buildingInstance)
	if not plot then return nil end
	local populated = plot:FindFirstChild("Buildings")
		and plot.Buildings:FindFirstChild("Populated")
	if not populated then return nil end
	local utilities = populated:FindFirstChild("Utilities")
	if not utilities then return nil end

	local pivotCF = buildingInstance:IsA("Model") and buildingInstance:GetPivot() or buildingInstance.CFrame
	local bpos = pivotCF.Position

	local bestPos, bestD
	for _, inst in ipairs(utilities:GetChildren()) do
		if isRoadInstance(inst) then
			local cf
			if inst:IsA("Model") then
				cf = (inst:GetBoundingBox())
			else
				cf = inst.CFrame
			end
			local pos = cf.Position
			local d = (pos - bpos).Magnitude
			if not bestD or d < bestD then
				bestD, bestPos = d, pos
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
			local target = nearestRoadTargetFor(inst)
			if target then
				BuildingGeneratorModule.orientBuildingToward(inst, target)
			end
		end
	end
end

--Road Orient from build or grid upgrade end


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
local function placeBuildings(
	player, zoneId, mode, buildingsList, isUtility,
	terrain, zoneFolder, utilitiesFolder,
	minX, maxX, minZ, maxZ,
	onBuildingPlaced, rotation,
	style, defaultWealthState,
	quotaCtx
)
		local leftoverCells = {} -- Will store cells that ended up empty after the first pass

		for x = minX, maxX do
			for z = minZ, maxZ do
				if shouldAbort(player, zoneId) then
					return leftoverCells
				end

				if OverlayZoneTypes[mode]
					or not ZoneTrackerModule.isGridOccupied(
						player, x, z,
						{
							excludeOccupantId = zoneId,
							excludeZoneTypes  = OverlapExclusions, -- ignore WaterPipe only
						}
					)
				then
					local placementChance = isUtility and 1.0 or 1.0
				if math.random() < placementChance then
					-- === NEW: choose per-tile wealth ===
					local tileWealth = _tileWealthForPlacement(mode, defaultWealthState, player, zoneId, x, z)
					if WEALTHED_ZONES[mode] and typeof(ZoneTrackerModule.getGridWealth) == "function" then
						tileWealth = ZoneTrackerModule.getGridWealth(player, zoneId, x, z) or tileWealth
					end

					local listForTile = buildingsList
					if WEALTHED_ZONES[mode] then
						local wl = BuildingMasterList.getBuildingsByZone(mode, style or "Default", tileWealth)
						if wl and #wl > 0 then listForTile = wl end
					end

					local selectedBuilding = chooseWeightedBuildingWithQuota(listForTile, mode, tileWealth, quotaCtx)
					if not selectedBuilding then
						-- nothing quota‑safe right now; try again in second pass
						table.insert(leftoverCells, { x = x, z = z })
					else
						local rotationY = pickRotation(mode, rotation)
						
						if isIndividualMode(mode) and not isSquareFootprintByData(selectedBuilding) then
							if (rotationY % 180) ~= 0 then
								rotationY = snapTo0or180(rotationY)
							end
						end

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
							else
								local buildingWidth = math.ceil(buildingSizeVector.X / GRID_SIZE)
								local buildingDepth = math.ceil(buildingSizeVector.Z / GRID_SIZE)
								if rotationY == 90 or rotationY == 270 then
									buildingWidth, buildingDepth = buildingDepth, buildingWidth
								end

								local canPlace = BuildingGeneratorModule.canPlaceBuilding(
									player,
									{ minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ },
									{ width = buildingWidth, depth = buildingDepth },
									x, z, zoneId, mode
								)

								if canPlace then
									-- === NEW: pre-reserve the exact footprint to avoid check-then-place races
									local preHandle = GridUtils.reserveFootprint(
										player, zoneId, "building",
										x, z, buildingWidth, buildingDepth,
										{ ttl = 10.0 }
									)

									if preHandle then
										local parentFolder = isUtility and utilitiesFolder or zoneFolder

										-- Generate the building; generator OWNS the reservation and must release it
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
											tileWealth,   -- << wealthState per tile
											nil,          -- skipStages
											preHandle,    -- << hand off reservation ownership
											quotaCtx      -- << NEW quota context
										)
									end)

										if not ok then
											-- If generator errored before releasing, free it here.
											GridUtils.releaseReservation(preHandle)
											warn("[placeBuildings] generateBuilding error:", err)
										end

										-- Skip ahead for multi-depth buildings to avoid re-checking covered cells
										if buildingDepth > 1 then
											z = z + buildingDepth - 1
										end
									else
										-- Someone else reserved this footprint first; try it later in second pass
										table.insert(leftoverCells, { x = x, z = z })
									end
								else
									table.insert(leftoverCells, { x = x, z = z })
								end
							end
						end
					else
						table.insert(leftoverCells, { x = x, z = z })
					end
				end

				if (x - minX) % 10 == 0 and (z - minZ) % 10 == 0 then
					task.wait()
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
					if isIndividualMode(mode) and not isSquareFootprintByData(selectedBuilding) then
						if (rotationY % 180) ~= 0 then
							rotationY = snapTo0or180(rotationY)
						end
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
						if isIndividualMode(mode) and not isSquareFootprintByData(sb) then
							rotationCandidates = {0, 180}
						end
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
	if zoneId:match("^RoadZone_")
		or zoneId:match("^PowerLinesZone_")
		or zoneId:match("^PipeZone_")
		or zoneId:match("^MetroTunnelZone_")     -- << ADD
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
				-- We won't hard-abort here (since STRICT=false by default), but we will log loudly.
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
				-- If you want auto-create, uncomment below 3 lines:
				-- buildingsFolder = Instance.new("Folder")
				-- buildingsFolder.Name = "Buildings"
				-- buildingsFolder.Parent = playerPlot
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
			local defaultWealthState  = wealthOverride or "Poor"   -- NEW: honor wealth override

			-- NEW: initialize quota context for this zone population
			local quotaCtx = newQuotaContext(mode, player, zoneId)
			scanZoneCountsInto(quotaCtx)

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
				-- assume string
				if w == "0" then return "Poor" end
				if w == "1" then return "Medium" end
				if w == "2" then return "Wealthy" end
				if w == "Poor" or w == "Medium" or w == "Wealthy" then return w end
				return nil
			end

			-- Any predefined placements (blueprints) first
			if predefinedBuildings and #predefinedBuildings > 0 then
				-- Wealthed zones where wealth matters (others: Individual/Utilities handled elsewhere)
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
						or defaultWealthState -- "Poor" if nothing else

					-- 1) Prefer a wealth-aware match so the entry already has stages
					local selected
					if WEALTHED_ZONES[mode] then
						selected = findByNameInWealth(mode, defaultStyle, cellWealth, bData.buildingName)
							or findByNameInWealth(mode, defaultStyle, "Poor",    bData.buildingName)
							or findByNameInWealth(mode, defaultStyle, "Medium",  bData.buildingName)
							or findByNameInWealth(mode, defaultStyle, "Wealthy", bData.buildingName)
					end

					-- 2) Fall back to global name lookup (no stages attached yet)
					if not selected then
						selected = BuildingMasterList.getBuildingByName(bData.buildingName)
						-- If we found a def by name, HYDRATE its stages for this wealth/zone.
						if selected and (not selected.stages or not selected.stages.Stage3) then
							local stages = WEALTHED_ZONES[mode]
								and BuildingMasterList.loadBuildingStages(mode, defaultStyle, selected.name, cellWealth)
								or  BuildingMasterList.loadBuildingStages("Individual", defaultStyle, selected.name)
							if stages and stages.Stage3 then
								selected.stages = stages
							end
						end
					end

					-- 3) Last-ditch: pick any building from the correct wealth bucket
					if (not selected) or (not selected.stages) or (not selected.stages.Stage3) then
						if WEALTHED_ZONES[mode] then
							local list = BuildingMasterList.getBuildingsByZone(mode, defaultStyle, cellWealth) or {}
							selected = chooseWeightedBuildingWithQuota(list, mode, cellWealth, quotaCtx)
							if not selected then
								warn(("[BuildingGenerator] restore: missing '%s' @(%d,%d) zone '%s'; no wealth fallback available")
									:format(tostring(bData.buildingName), bData.gridX, bData.gridZ, zoneId))
							else
								warn(("[BuildingGenerator] restore: missing '%s' @(%d,%d) zone '%s'; using %s/%s fallback '%s'")
									:format(tostring(bData.buildingName), bData.gridX, bData.gridZ, zoneId,
										mode, tostring(cellWealth), selected and selected.name or "nil"))
							end
						end
					end
					
					if selected and selected.name and wouldViolateQuota(quotaCtx, mode, cellWealth, selected.name) then
						local altList = WEALTHED_ZONES[mode] and BuildingMasterList.getBuildingsByZone(mode, defaultStyle, cellWealth) or buildingsList
						selected = chooseWeightedBuildingWithQuota(altList, mode, cellWealth, quotaCtx)
					end
					
					-- Debug: show wealth + whether we actually got Stage3
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
					if isIndividualMode(mode) and not isSquareFootprintByData(selected) then
						rotForThis = snapTo0or180(rotForThis or 0)
					end
						BuildingGeneratorModule.generateBuilding(
							terrain,
							parentFolder,
							player,
							zoneId,
							mode,
							{ x = bData.gridX, z = bData.gridZ },
							selected,
							bData.isUtility,
							bData.rotation,
							onBuildingPlaced,
							cellWealth,   -- stamp WealthState on the placed instance
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
			end

			----------------------------------------------------------------
			-- 5) Finish populating any remaining empty cells
			----------------------------------------------------------------
			local function record(folder)
				for _, child in ipairs(folder:GetChildren()) do
					if (child:IsA("Model") or child:IsA("BasePart"))
						and child:GetAttribute("ZoneId") == zoneId
					then
						-- Ensure WealthState attribute reflects the effective wealth for this pass
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
				zoneId, #placedBuildingsData))
		
				orientZoneBuildingsTowardRoads(player, zoneId)

		
			if buildingsPlacedCounter > 0 then
				buildingsPlacedEvent:Fire(player, zoneId, buildingsPlacedCounter)
				debugPrint(string.format(
					"Flushed BuildingsPlaced for Zone '%s' with final batch of %d.",
					zoneId, buildingsPlacedCounter
					))
				buildingsPlacedCounter = 0
			end
			
			ZoneTrackerModule.setZonePopulating(player, zoneId, false)
			zonePopulatedEvent:Fire(player, zoneId, placedBuildingsData)
			ZoneTrackerModule.setZonePopulated(player, zoneId, true)
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

		--[[ LEGACY MONKEY-PATCH PATH (kept for backward compatibility documentation):
		local prev = BuildingMasterList.getBuildingsByZone
		BuildingMasterList.getBuildingsByZone = function(zType, zStyle, wealthState)
			return prev(zType, zStyle, newWealthState)
		end
		BuildingGeneratorModule.populateZone(player, zoneId, mode, gridList, nil)
		BuildingMasterList.getBuildingsByZone = prev
		]]
	end

	local function _refillZoneGaps(player, zoneId, mode, wealthOverride, rotation, styleOverride, refillSourceZoneId)
		-- If this refill was triggered by an overlay and that overlay no longer exists (e.g., undo),
		-- drop out early to prevent late-arriving refills.
		if refillSourceZoneId and not ZoneTrackerModule.getZoneById(player, refillSourceZoneId) then
			return
		end

		-- Locate plot/containers
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

		-- Compute zone grid bounds
		local gridList = ZoneTrackerModule.getZoneGridList(player, zoneId)
		if not gridList or #gridList == 0 then return end

		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		for _, c in ipairs(gridList) do
			if c.x < minX then minX = c.x end
			if c.x > maxX then maxX = c.x end
			if c.z < minZ then minZ = c.z end
			if c.z > maxZ then maxZ = c.z end
		end

		-- Small helper to normalize wealth inputs (supports 0/1/2 or strings)
		local function normalizeWealth(w)
			if w == nil then return nil end
			local s = tostring(w)
			if s == "0" then return "Poor" end
			if s == "1" then return "Medium" end
			if s == "2" then return "Wealthy" end
			if s == "Poor" or s == "Medium" or s == "Wealthy" then return s end
			return nil
		end

		-- Resolve overrides (style/wealth)
		local style  = styleOverride or "Default"
		local wealth = normalizeWealth(wealthOverride) or "Poor"

		-- Mode routing to pick a proper list at the requested style/wealth
		local isUtility = false
		local buildingsList
		if mode == "Utilities" then
			-- mirrors populateZone’s default utility type
			local utilityType = "Water"
			buildingsList = BuildingMasterList.getUtilitiesByType(utilityType, style)
			isUtility = true
		elseif mode == "Road" then
			buildingsList = BuildingMasterList.getRoadsByStyle(style)
			isUtility = true
		else
			-- Wealth‑aware zone set
			buildingsList = BuildingMasterList.getBuildingsByZone(mode, style, wealth)
		end
		if not buildingsList or #buildingsList == 0 then return end
		
		local quotaCtx = newQuotaContext(mode, player, zoneId)
		scanZoneCountsInto(quotaCtx)

		-- Prefer exported helpers; fall back to locals if needed
		local pass1 = (BuildingGeneratorModule and BuildingGeneratorModule._placeBuildings) or placeBuildings
		local pass2 = (BuildingGeneratorModule and BuildingGeneratorModule._placeBuildingsSecondPass) or placeBuildingsSecondPass
		if type(pass1) ~= "function" or type(pass2) ~= "function" then
			warn("[_refillZoneGaps] placement helpers not available; aborting.")
			return
		end

		-- Capture what already exists in this zone before the refill (by origin GridX/Z)
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

		-- Run both passes (occupancy checks inside helpers prevent duplicates)
		local function noop() end
		local leftover = pass1(
			player, zoneId, mode, buildingsList, isUtility,
			terrain, zoneFolder, utilitiesFolder,
			minX, maxX, minZ, maxZ,
			noop, rotation,
			style, wealth,
			quotaCtx
		)

		pass2(
			player, zoneId, mode, buildingsList, isUtility,
			terrain, zoneFolder, utilitiesFolder, leftover,
			minX, maxX, minZ, maxZ,
			noop, rotation,
			style, wealth,
			quotaCtx
		)

		-- Normalize WealthState attribute so later systems (e.g. upgrades) read the correct tier.
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

		-- Tag only the *newly created* instances so undo can remove them cleanly later.
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
	end

	BuildingGeneratorModule._refillZoneGaps = _refillZoneGaps
	math.randomseed(tick())

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
		if isIndividualMode(mode) and not isSquareFootprintByData(cand) then
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
		debugPrint("upgradeGrid: tile already " .. newWealthState)
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

	LayerManagerModule.storeRemovedObject("Buildings", zoneId, {
		instanceClone = target:Clone(),
		parentName = parentName,
		gridX = originGX,
		gridZ = originGZ,
		rotationY = target:GetAttribute("RotationY") or 0,
		wealthState = target:GetAttribute("WealthState"),
	})

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
		end
	end

	target:Destroy()

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

	local outFolder = populated:FindFirstChild(parentName)
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
		nil,
		newWealthState,
		nil,
		quotaCtx
	)

	local oldW, oldD = 1, 1
	if oldData and oldData.stages and oldData.stages.Stage3 then
		oldW, oldD = footprint(oldData, oldRot)
	end
	local newW, newD = footprint(chosen, chosenRotation)

	local leftovers = {}
	for dx = 0, oldW - 1 do
		for dz = 0, oldD - 1 do
			if not (dx < newW and dz < newD) then
				local x, z = originGX + dx, originGZ + dz
				if not ZoneTrackerModule.isGridOccupied(player, x, z, { excludeOccupantId = zoneId }) then
					table.insert(leftovers, { x = x, z = z })
				end
			end
		end
	end

	if #leftovers > 0 then
		for _, cell in ipairs(leftovers) do
			for _, cand in ipairs(options) do
				if not (isDecorationName(mode, cand.name)
					and wouldViolateQuota(quotaCtx, mode, newWealthState, cand.name))
				then
					for _, rot in ipairs(rotationCandidatesFor(mode, cand)) do
						local w, d = footprint(cand, rot)
						if BuildingGeneratorModule.canPlaceBuilding(
							player, bounds, { width = w, depth = d }, cell.x, cell.z, zoneId, mode
							) then
							BuildingGeneratorModule.generateBuilding(
								plot:FindFirstChild("TestTerrain"),
								outFolder,
								player,
								zoneId,
								mode,
								{ x = cell.x, z = cell.z },
								cand,
								parentName == "Utilities",
								rot,
								nil,
								newWealthState,
								nil,
								quotaCtx
							)
							break
						end
					end
				end
			end
		end
	end
	
	for _, cand in ipairs(options) do
	-- cap guard: skip decorations if the 20% would be exceeded
	if isDecorationName(mode, cand.name)
		and wouldViolateQuota(quotaCtx, mode, newWealthState, cand.name)
	then
		continue -- Luau keyword; skips to next cand
	end

	for _, rot in ipairs({0, 90, 180, 270}) do
		-- try placements...
	end
end
	
	if typeof(orientZoneBuildingsTowardRoads) == "function" then
		orientZoneBuildingsTowardRoads(player, zoneId)
	end

	if (newW * newD) < (oldW * oldD) then
		task.spawn(function()
			_refillZoneGaps(player, zoneId, mode, newWealthState, nil)
		end)
	end
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
return BuildingGeneratorModule
	--Line 1857