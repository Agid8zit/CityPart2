local PowerGeneratorModule = {}
PowerGeneratorModule.__index = PowerGeneratorModule

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

---------------------------------------------------------------------
--  Services / modules
---------------------------------------------------------------------
local BE = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents")
local zonePopulatedEvent = BE:WaitForChild("ZonePopulated")
local linesPlacedEvent   = BE:WaitForChild("LinesPlaced")
local linesRemovedEvent  = BE:WaitForChild("LinesRemoved")
local PadPoleSpawned	 = BE:WaitForChild("PadPoleSpawned")

local S3            = game:GetService("ServerScriptService")
local Build         = S3:WaitForChild("Build")
local Zones         = Build:WaitForChild("Zones")
local ZoneMgr       = Zones:WaitForChild("ZoneManager")
local ZoneTrackerModule = require(ZoneMgr:WaitForChild("ZoneTracker"))

local GridConf   = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Grid")
local GridUtils  = require(GridConf:WaitForChild("GridUtil"))
local GridConfig = require(GridConf:WaitForChild("GridConfig"))
local GRID_SIZE = GridConfig.GRID_SIZE or 4

local BuildingManager    = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("BuildingManager")
local BuildingMasterList = require(BuildingManager:WaitForChild("BuildingMasterList"))
local LayerManagerModule = require(Build.LayerManager)

local PowerLinePath = require(script.Parent:WaitForChild("PowerLinePath"))

---------------------------------------------------------------------
--  Normalization helpers / exclusions
---------------------------------------------------------------------
local function _normkey(s: any): string
	local v = tostring(s or "")
	v = string.lower(v)
	-- remove whitespace, underscores, hyphens and punctuation so "Water Pipe", "water_pipe" all match
	v = v:gsub("[%s%p_%-]", "")
	return v
end

-- Raw mode names as they actually exist in your game:
local OverlapExclusionsRaw = {
	WaterPipe   = true,
	MetroTunnel = true,
}

-- Occupant-type exclusions (grid occupant type strings), keep minimal:
local OverlapTypeExclusions = {
	pipe      = true,
	water     = true,
	waterpipe = true,
	pipezone  = true,
}

-- Normalized lookup for mode-name checks (use ONLY for our own comparisons)
local OverlapExclusions = {}
for k,_ in pairs(OverlapExclusionsRaw) do
	OverlapExclusions[_normkey(k)] = true
end

---------------------------------------------------------------------
--  Constants
---------------------------------------------------------------------
local DEBUG_LOGS    = false
local BUILD_INTERVAL = 0.1
local Y_OFFSET       = 0.01
local AVOID_ROPES_THROUGH_NON_ROAD = true
local BRIDGE_TO_NEAREST_PADPOLE    = false -- These are BUILDING ZONE SPECIFIC these are not the normal poles
local PADPOLE_LINK_MAX_GRIDS       = 2
local BUILDING_PADPOLE_MAX_GRIDS   = 3
local PADPOLE_LINK_MAX_DISTANCE    = PADPOLE_LINK_MAX_GRIDS * GRID_SIZE
print("[PowerGeneratorModule] Loaded")

---------------------------------------------------------------------
--  Direction → rotationY
---------------------------------------------------------------------
local function getRotationForDirection(direction)
	if     direction == "North"     then return 0
	elseif direction == "East"      then return 90
	elseif direction == "South"     then return 180
	elseif direction == "West"      then return 270
	elseif direction == "NorthEast" then return 45
	elseif direction == "SouthEast" then return 135
	elseif direction == "SouthWest" then return 225
	elseif direction == "NorthWest" then return 315 end
	return 0              -- "End", "Undefined", etc.
end

---------------------------------------------------------------------
--  Debug print
---------------------------------------------------------------------
local function debugPrint(...)
	if DEBUG_LOGS then
		print("[PowerGeneratorModule]", ...)
	end
end

local function yieldEveryN(counter: number, interval: number?)
	interval = interval or 200
	if interval > 0 and counter % interval == 0 then
		task.wait()
	end
end

local function _dumpTypes(t)
	local a = {}
	for k,v in pairs(t or {}) do if v then table.insert(a, k) end end
	table.sort(a)
	return table.concat(a, ",")
end

---------------------------------------------------------------------
--  Cached global-bounds lookup per plot
---------------------------------------------------------------------
local boundsCache = {}
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


---------------------------------------------------------------------
--  Helpers
---------------------------------------------------------------------

local _queuedRopeRebuilds = {}
local function _queueRopeRebuild(player, powerZoneId)
	local key = tostring(player.UserId) .. "|" .. tostring(powerZoneId)
	if _queuedRopeRebuilds[key] then return end
	_queuedRopeRebuilds[key] = true
	task.defer(function()
		_queuedRopeRebuilds[key] = nil
		PowerGeneratorModule.rebuildRopesForZone(player, powerZoneId)
		PowerGeneratorModule.ensureOverlapBoxesForPowerZone(player, powerZoneId)
	end)
end

local function isRoadCell(occupantTypes)
	if not occupantTypes then return false end
	return occupantTypes.road ~= nil
end

-- “Non-road” = has *any* occupant that isn’t road (building, water, park, etc.)
local function hasAnyNonRoad(occupantTypes)
	if not occupantTypes then return false end
	for k, v in pairs(occupantTypes) do
		if v and k ~= "road" and k ~= "power" then
			local lk = string.lower(k)
			if not OverlapTypeExclusions[lk] then
				return true
			end
		end
	end
	return false
end

local function _isExcludedZone(player, zoneId: string?): boolean
	if not zoneId then return false end
	local z = ZoneTrackerModule.getZoneById(player, zoneId)
	if not z then return false end
	return OverlapExclusions[_normkey(z.mode)] == true
end

-- Small utility to find a free neighbor tile that still belongs to this power zone's gridList
local function findFreeNeighborInside(gridSet, lastCoord)
	local offsets = {
		{1,0}, {-1,0}, {0,1}, {0,-1}
	}
	for _, o in ipairs(offsets) do
		local nx, nz = lastCoord.x + o[1], lastCoord.z + o[2]
		if gridSet[nx..","..nz] then
			return {x = nx, z = nz}
		end
	end
	return lastCoord -- fallback: same tile (won't look as nice, but is safe)
end

local function planarGridDistance(posA: Vector3, posB: Vector3): number
	local dx = math.abs(posA.X - posB.X)
	local dz = math.abs(posA.Z - posB.Z)
	return math.max(dx, dz) / GRID_SIZE
end

-- Building-population guards (used to defer rope rebuilds / pad-pole links during reload)
local INFRA_MODES = {
	DirtRoad   = true,
	Pavement   = true,
	Highway    = true,
	Road       = true,
	RoadZone   = true,
	PowerLines = true,
	WaterPipe  = true,
	MetroTunnel= true,
	MetroEntrance = true,
}

local function _isBuildingMode(mode: any): boolean
	if not mode then return false end
	return INFRA_MODES[mode] ~= true
end

local function _hasPopulatingBuildingZone(player): boolean
	for _, z in pairs(ZoneTrackerModule.getAllZones(player)) do
		if z and z.isPopulating and _isBuildingMode(z.mode) then
			return true
		end
	end
	return false
end

local _pendingRebuildAfterBuildings = {} -- [uid] = true
local _rebuildAllInProgress        = {} -- [uid] = true
local _rebuildAllPending           = {} -- [uid] = true
local _queuedPadPoleLinks = {}           -- [uid] = { [buildingZoneId] = { padPole, ... } }

local function _queuePadPoleLink(player, buildingZoneId, padPole)
	if not (player and buildingZoneId and padPole) then return false end
	local uid = player.UserId
	local perPlayer = _queuedPadPoleLinks[uid]
	if not perPlayer then
		perPlayer = {}
		_queuedPadPoleLinks[uid] = perPlayer
	end
	local perZone = perPlayer[buildingZoneId]
	if not perZone then
		perZone = {}
		perPlayer[buildingZoneId] = perZone
	end
	perZone[#perZone+1] = padPole
	return true
end

local function _drainQueuedPadPoleLinks(player, buildingZoneId)
	local uid = player and player.UserId
	if not (uid and buildingZoneId) then return end
	local perPlayer = _queuedPadPoleLinks[uid]
	if not perPlayer then return end
	local pending = perPlayer[buildingZoneId]
	if not pending then return end
	perPlayer[buildingZoneId] = nil
	if not next(perPlayer) then
		_queuedPadPoleLinks[uid] = nil
	end
	for _, pole in ipairs(pending) do
		if pole and pole.Parent then
			PowerGeneratorModule.connectPadPoleToPowerZone(player, pole)
		end
	end
end

-- Try to locate a padpole model in the player's plot. Adapt the name/attribute checks to your prefab.
local function findNearestPadPole(plot, fromPos)
	local nearest, best = nil, math.huge
	for _, m in ipairs(plot:GetDescendants()) do
		if m:IsA("Model") and (m:GetAttribute("IsPadPole") or m.Name:match("[Pp]ad[Pp]ole")) then
			local p = m.PrimaryPart and m.PrimaryPart.Position or m:GetPivot().Position
			local d = (p - fromPos).Magnitude
			if d < best then best, nearest = d, m end
		end
	end
	return nearest
end

function PowerGeneratorModule.suppressPolesOnGridList(player, suppressorZoneId, gridList)
	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId); if not plot then return end
	local powerFolder = plot:FindFirstChild("PowerLines");                         if not powerFolder then return end
	local set = (function(list)
		local s = {}
		for _, c in ipairs(list or {}) do if c.x and c.z then s[c.x..","..c.z] = true end end
		return s
	end)(gridList)

	local touched = false

	for _, zoneFolder in ipairs(powerFolder:GetChildren()) do
		if not zoneFolder:IsA("Folder") then continue end
		local powerZoneId = zoneFolder.Name
		local changed = false

		for _, inst in ipairs(zoneFolder:GetChildren()) do
			if (inst:IsA("Model") or inst:IsA("BasePart"))
				and (inst.Name == "PowerLines" or inst:GetAttribute("LineType"))
			then
				local gx = inst:GetAttribute("GridX")
				local gz = inst:GetAttribute("GridZ")
				if gx and gz and set[gx..","..gz] then
					-- Archive for undo tooling (optional but nice to have)
					LayerManagerModule.storeRemovedObject("PowerLines", suppressorZoneId, {
						instanceClone  = inst:Clone(),
						originalParent = inst.Parent,
						cframe         = (inst:IsA("Model") and inst:GetPivot() or inst.CFrame),
					}, player)
					-- Unmark occupancy
					local pzid  = inst:GetAttribute("ZoneId") or powerZoneId
					local occId = string.format("%s_power_%d_%d", tostring(pzid), gx, gz)
					ZoneTrackerModule.unmarkGridOccupied(player, gx, gz, "power", occId)

					inst:Destroy()
					changed = true
				end
			end
		end

		if changed then
			-- Rebuild ropes; your rebuild guards prevent crossing gaps
			PowerGeneratorModule.rebuildRopesForZone(player, powerZoneId)
			touched = true
		end
	end

	if touched then
		PowerGeneratorModule.ensureOverlapBoxesForAll(player)
	end
end

local function getRoadZoneIdAtCell(player, gx, gz)
	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId)
	if not plot then return nil end
	local roadsFolder = plot:FindFirstChild("Roads"); if not roadsFolder then return nil end

	local fallback = nil
	for _, obj in ipairs(roadsFolder:GetDescendants()) do
		if (obj:IsA("Model") or obj:IsA("BasePart"))
			and obj:GetAttribute("GridX") == gx
			and obj:GetAttribute("GridZ") == gz
			and not obj:GetAttribute("IsRoadDecoration")
		then
			local zid = obj:GetAttribute("ZoneId")
			if not zid then
				-- If ZoneId attribute is missing, infer from the zone subfolder
				local f = obj:FindFirstAncestorWhichIsA("Folder")
				if f and f.Parent == roadsFolder then zid = f.Name end
			end
			if zid then
				-- Prefer visible (not hidden by an intersection)
				if not obj:GetAttribute("IsHiddenByIntersection") then
					return zid
				end
				fallback = fallback or zid
			end
		end
	end
	return fallback
end

---------------------------------------------------------------------
--  Electric boxes for road↔power overlaps (2 boxes when run ≥ 2)
---------------------------------------------------------------------
local BOX_DEBUG        = false
local BOX_ASSET_NAMES  = { "ElectricalBox", "ElectricalCabinet", "TransformerBox", "UtilityBox" }
local BOX_SIDE_OFFSET  = 2.6   -- shift off the centerline so it isn't on top of the road
local BOX_Y_OFFSET     = 1.3   -- final absolute height for box placement

-- NEW: how far a box will search for a pole to hook into
local BOX_LINK_MAX_DISTANCE = 24

local function _box_dprint(...) if BOX_DEBUG then print("[PowerBox]", ...) end end
local function _ovKey(x,z) return string.format("%d,%d", x, z) end

local function _gridToWorld(player, gx, gz)
	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId)
	if not plot then return Vector3.zero end
	local gb, terrains = getGlobalBoundsForPlot(plot)
	local wx, wy, wz   = GridUtils.globalGridToWorldPosition(gx, gz, gb, terrains)
	return Vector3.new(wx, wy, wz)
end

local function _getBoxAsset()
	-- Use the electric box under Power → Default → ElectricBox
	local data = BuildingMasterList.getIndividualBuildingByName("Power", "Default", "ElectricBox")
	if data and data[1] and data[1].stages and data[1].stages.Stage3 then
		return data[1], "ElectricBox"
	end
	-- Fallback (optional): keep the old search as a safety net
	for _, name in ipairs(BOX_ASSET_NAMES) do
		local a = BuildingMasterList.getBuildingByName(name)
		if a then
			if not (a.stages and a.stages.Stage3) then
				a.stages = BuildingMasterList.loadBuildingStages("Road", "Default", name)
			end
			if a.stages and a.stages.Stage3 then
				return a, name
			end
		end
	end
	return nil, nil
end

-- Per-road-zone sets of visible road cells (skip decorations/hidden)
local function _listRoadZoneCellSets(player)
	local result = {}
	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId); if not plot then return result end
	local roadsFolder = plot:FindFirstChild("Roads"); if not roadsFolder then return result end

	for _, zf in ipairs(roadsFolder:GetChildren()) do
		if zf:IsA("Folder") then
			local set = {}
			for _, obj in ipairs(zf:GetDescendants()) do
				if (obj:IsA("Model") or obj:IsA("BasePart")) then
					if obj:GetAttribute("IsRoadDecoration") then continue end
					if obj:GetAttribute("IsHiddenByIntersection") then continue end
					local gx = obj:GetAttribute("GridX")
					local gz = obj:GetAttribute("GridZ")
					if gx and gz then set[_ovKey(gx,gz)] = true end
				end
			end
			result[zf.Name] = set
		end
	end
	return result
end

local function _getPowerPathCells(powerZoneId)
	local net = PowerLinePath.getLineNetworks()[powerZoneId] or PowerLinePath.getLineData(powerZoneId) or {}
	local segs = net.segments or net.pathCoords or {}
	local path = {}
	for _, s in ipairs(segs) do
		local x = (s.coord and s.coord.x) or s.x
		local z = (s.coord and s.coord.z) or s.z
		if x and z then path[#path+1] = { x = x, z = z } end
	end
	return path
end

local function _getPowerZoneFolder(player, powerZoneId)
	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId); if not plot then return nil end
	local pf   = plot:FindFirstChild("PowerLines"); if not pf then return nil end
	return pf:FindFirstChild(powerZoneId)
end

local function _indexExistingBoxes(zoneFolder, powerZoneId)
	local map = {}
	for _, inst in ipairs(zoneFolder:GetDescendants()) do
		if (inst:IsA("Model") or inst:IsA("BasePart"))
			and inst:GetAttribute("IsPowerRoadBox") == true
			and inst:GetAttribute("ZoneId") == powerZoneId
		then
			local k = inst:GetAttribute("OverlapKey")
			if k then map[k] = inst end
		end
	end
	return map
end

local function _ensureBox(player, zoneFolder, asset, assetName, powerZoneId, roadZoneId, axis, endpoint, startCell, endCell, cell, existingByKey, validKeys)
	local runKey = string.format("%s|%s|%d,%d>%d,%d", powerZoneId, roadZoneId, startCell.x, startCell.z, endCell.x, endCell.z)
	local key    = runKey .. "|" .. endpoint
	validKeys[key] = true

	local yaw
	if axis == "EW" then
		yaw = (endpoint == "Start") and  90 or -90
	else
		yaw = (endpoint == "Start") and   0 or 180
	end
	-- Opposite sides for start/end for easy readability
	local side = (endpoint == "Start") and 1 or -1

	-- Base lateral offset (same as before; Y handled separately to stay absolute)
	local offset = (axis == "EW")
		and Vector3.new(0, 0, side * BOX_SIDE_OFFSET)
		or  Vector3.new(side * BOX_SIDE_OFFSET, 0, 0)

	-- NEW: small forward/backward (Z) bias for visual alignment
	-- e.g., +0.4 for one endpoint, -0.4 for the other
	local BOX_Z_OFFSET = 0.4
	if axis == "EW" then
		-- east-west runs → adjust along X (road direction)
		offset += Vector3.new((endpoint == "Start") and -BOX_Z_OFFSET or BOX_Z_OFFSET, 0, 0)
	else
		-- north-south runs → adjust along Z
		offset += Vector3.new(0, 0, (endpoint == "Start") and -BOX_Z_OFFSET or BOX_Z_OFFSET)
	end

	local world = _gridToWorld(player, cell.x, cell.z)
	local pos   = Vector3.new(world.X + offset.X, BOX_Y_OFFSET, world.Z + offset.Z)
	local cf    = CFrame.new(pos) * CFrame.Angles(0, math.rad(yaw), 0)

	local inst = existingByKey[key]
	if not inst then
		local clone = asset.stages.Stage3:Clone()
		clone.Name = assetName
		clone:SetAttribute("ZoneId", powerZoneId)
		clone:SetAttribute("IsPowerRoadBox", true)
		clone:SetAttribute("LinkedRoadZoneId", roadZoneId)
		clone:SetAttribute("RunKey", runKey)
		clone:SetAttribute("OverlapKey", key)
		clone:SetAttribute("Endpoint", endpoint)
		clone:SetAttribute("GridX", cell.x)
		clone:SetAttribute("GridZ", cell.z)
		if clone:IsA("Model") then
			-- Prefer PivotTo so we work even when no PrimaryPart is set on the asset
			if clone.PrimaryPart then
				clone:SetPrimaryPartCFrame(cf)
			else
				pcall(function() clone:PivotTo(cf) end)
			end
		elseif clone:IsA("BasePart") then
			clone.CFrame = cf
		end
		for _, p in ipairs(clone:GetDescendants()) do
			if p:IsA("BasePart") then p.CanQuery = false end
		end
		clone.Parent = zoneFolder
		existingByKey[key] = clone
		_box_dprint("Spawned box:", key, "at", cell.x, cell.z, "axis", axis)
	else
		-- refresh transform if it moved
		if inst:IsA("Model") and inst.PrimaryPart then
			inst:SetPrimaryPartCFrame(cf)
		elseif inst:IsA("BasePart") then
			inst.CFrame = cf
		end
		inst:SetAttribute("GridX", cell.x)
		inst:SetAttribute("GridZ", cell.z)
	end
end

---------------------------------------------------------------------
-- NEW: Generic attachment utilities + box→pole linking
---------------------------------------------------------------------

local function _listAttachments(model: Instance)
	local atts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Attachment") and d.Parent and d.Parent:IsA("BasePart") then
			table.insert(atts, d)
		end
	end
	return atts
end

local function _detachAllRopesFromModel(m: Instance)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("RopeConstraint") then d:Destroy() end
	end
end

local function _modelPos(m: Instance): Vector3
	return (m.PrimaryPart and m.PrimaryPart.Position) or m:GetPivot().Position
end

local function _isPole(inst: Instance): boolean
	if not (inst and (inst:IsA("Model") or inst:IsA("BasePart"))) then return false end
	if inst.Name == "PowerLines" then return true end
	if inst:GetAttribute("LineType") ~= nil then return true end
	return false
end

local function _nearestPoleModel(zoneFolder: Instance, fromPos: Vector3, maxDist: number)
	local best, bestModel = math.huge, nil
	for _, child in ipairs(zoneFolder:GetChildren()) do
		if _isPole(child) then
			local pos = _modelPos(child)
			local d = (pos - fromPos).Magnitude
			if d < best and d <= maxDist then
				best, bestModel = d, child
			end
		end
	end
	return bestModel, best
end

function PowerGeneratorModule.connectPadPoleToPowerZone(player, padPole)
	if not (player and padPole) then return end

	local powerZoneId = padPole:GetAttribute("PowerLineZoneId")
	-- If not stamped yet, try to keep idempotency by leaving it nil,
	-- but we won't guess here. (Spawn path stamps it for us.)
	if not powerZoneId then return end

	local owningZoneId = padPole:GetAttribute("ZoneId") or padPole:GetAttribute("BuildingZoneId")
	if owningZoneId then
		local owningZone = ZoneTrackerModule.getZoneById(player, owningZoneId)
		if owningZone then
			local populating = ZoneTrackerModule.isZonePopulating(player, owningZoneId)
			local populated  = ZoneTrackerModule.isZonePopulated(player, owningZoneId)
			if populating or (not populated) then
				_queuePadPoleLink(player, owningZoneId, padPole)
				return
			end
		end
	end

	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId); if not plot then return end
	local pf   = plot:FindFirstChild("PowerLines"); if not pf then return end
	local zoneFolder = pf:FindFirstChild(powerZoneId); if not zoneFolder then return end

	-- Find the nearest pole inside this *specific* zone folder
	local pos = (padPole.PrimaryPart and padPole.PrimaryPart.Position) or padPole:GetPivot().Position
	local pole = _nearestPoleModel(zoneFolder, pos, PADPOLE_LINK_MAX_DISTANCE)
	if not pole then return end

	local linkGridDelta = planarGridDistance(_modelPos(pole), pos)
	if linkGridDelta > PADPOLE_LINK_MAX_GRIDS then
		if DEBUG_LOGS then
			debugPrint(string.format(
				"PadPole->zone link suppressed; %.2f grids away (limit=%d)",
				linkGridDelta,
				PADPOLE_LINK_MAX_GRIDS
			))
		end
		return
	end

	-- Ensure the stamp is present
	if padPole:GetAttribute("PowerLineZoneId") ~= powerZoneId then
		padPole:SetAttribute("PowerLineZoneId", powerZoneId)
	end

	-- Create the two span ropes (uses attachments "1"/"2" with criss‑cross guards)
	linkPoles(pole, padPole)
end

-- Find the nearest attachment on any *pole* in zoneFolder to 'fromAtt', within maxDist.
local function _nearestPoleAttachment(zoneFolder: Instance, fromAtt: Attachment, maxDist: number)
	local best, bestAtt = math.huge, nil
	for _, child in ipairs(zoneFolder:GetChildren()) do
		if _isPole(child) and child ~= fromAtt.Parent then
			for _, att in ipairs(_listAttachments(child)) do
				local d = (att.WorldPosition - fromAtt.WorldPosition).Magnitude
				if d < best and d <= maxDist then
					best, bestAtt = d, att
				end
			end
		end
	end
	return bestAtt
end

-- Hook a box to the nearest pole with 1–2 ropes, depending on box/pole attachments available.
local function _connectBoxToNearestPoles(zoneFolder: Instance, boxModel: Instance)
	local boxAtts = _listAttachments(boxModel)
	if #boxAtts == 0 then return end

	for _, bAtt in ipairs(boxAtts) do
		local poleAtt = _nearestPoleAttachment(zoneFolder, bAtt, BOX_LINK_MAX_DISTANCE)
		if poleAtt then
			-- Avoid duplicates
			local function _hasRope(a0, a1)
				for _, d in ipairs(a0.Parent:GetDescendants()) do
					if d:IsA("RopeConstraint") and d.Attachment0 == a0 and d.Attachment1 == a1 then
						return true
					end
				end
				for _, d in ipairs(a1.Parent:GetDescendants()) do
					if d:IsA("RopeConstraint") and d.Attachment0 == a0 and d.Attachment1 == a1 then
						return true
					end
				end
				return false
			end
			if not _hasRope(bAtt, poleAtt) then
				createRope(bAtt, poleAtt)
			end
		end
	end
end

-- Public: recompute 2-box endpoints for all overlap runs (len≥2) between this power zone and all road zones
function PowerGeneratorModule.ensureOverlapBoxesForPowerZone(player, powerZoneId)
	local zoneFolder = _getPowerZoneFolder(player, powerZoneId); if not zoneFolder then return end
	local path = _getPowerPathCells(powerZoneId); if #path == 0 then return end

	local roadSetsByZone = _listRoadZoneCellSets(player)
	local asset, assetName = _getBoxAsset()
	if not asset then
		warn("[PowerGenerator] No electrical box asset (tried: " .. table.concat(BOX_ASSET_NAMES, ", ") .. ")")
		return
	end

	local existingByKey = _indexExistingBoxes(zoneFolder, powerZoneId)
	local validKeys = {}

	-- ===== helpers (scoped) =====
	local function _modelPos(m: Instance): Vector3
		return (m.PrimaryPart and m.PrimaryPart.Position) or m:GetPivot().Position
	end
	local function _isPole(inst: Instance): boolean
		if not (inst and (inst:IsA("Model") or inst:IsA("BasePart"))) then return false end
		if inst.Name == "PowerLines" then return true end
		if inst:GetAttribute("LineType") ~= nil then return true end
		return false
	end
	local function _listAttachments(model: Instance)
		local atts = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("Attachment") and d.Parent and d.Parent:IsA("BasePart") then
				table.insert(atts, d)
			end
		end
		return atts
	end
	local function _getTwoAttachments(model: Instance)
		-- prefer explicitly named "1" and "2"
		local a1, a2
		for _, a in ipairs(_listAttachments(model)) do if a.Name == "1" then a1 = a break end end
		for _, a in ipairs(_listAttachments(model)) do if a.Name == "2" then a2 = a break end end
		if a1 and a2 then return a1, a2 end
		local all = _listAttachments(model)
		if #all >= 2 then return all[1], all[2] end
		return nil, nil
	end
	local function _nearestPoleModel(folder: Instance, fromPos: Vector3, maxDist: number)
		local best, bestModel = math.huge, nil
		for _, child in ipairs(folder:GetChildren()) do
			if _isPole(child) then
				local d = (_modelPos(child) - fromPos).Magnitude
				if d < best and d <= maxDist then best, bestModel = d, child end
			end
		end
		return bestModel, best
	end
	local function _detachAllRopesFromModel(m: Instance)
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("RopeConstraint") then d:Destroy() end
		end
	end
	local function _connectBoxToNearestPole(folder: Instance, boxModel: Instance, maxDist: number)
		local pole, dist = _nearestPoleModel(folder, _modelPos(boxModel), maxDist or BOX_LINK_MAX_DISTANCE)
		if not pole then
			_detachAllRopesFromModel(boxModel)
			return false
		end
		local b1, b2 = _getTwoAttachments(boxModel)
		local p1, p2 = _getTwoAttachments(pole)
		if not (b1 and b2 and p1 and p2) then return false end

		-- lateral sort to avoid criss-cross
		local boxPos  = _modelPos(boxModel)
		local polePos = _modelPos(pole)
		local dir     = (polePos - boxPos); if dir.Magnitude < 1e-6 then dir = Vector3.zAxis end
		local u       = dir.Unit
		local left    = Vector3.yAxis:Cross(u); if left.Magnitude < 1e-6 then left = Vector3.xAxis end
		left = left.Unit

		local B = {b1, b2}
		table.sort(B, function(a, c) return (a.WorldPosition - boxPos):Dot(left) < (c.WorldPosition - boxPos):Dot(left) end)
		local P = {p1, p2}
		table.sort(P, function(a, c) return (a.WorldPosition - polePos):Dot(left) < (c.WorldPosition - polePos):Dot(left) end)

		_detachAllRopesFromModel(boxModel)
		createRope(B[1], P[1])
		createRope(B[2], P[2])
		return true
	end
	local function _distToNearestPole(folder: Instance, model: Instance)
		local _, d = _nearestPoleModel(folder, _modelPos(model), BOX_LINK_MAX_DISTANCE)
		return d or math.huge
	end
	-- ===== end helpers =====

	-- scan overlapped runs, place 2 boxes at endpoints
	for roadZoneId, rset in pairs(roadSetsByZone) do
		local i = 1
		while i <= #path do
			local k1 = _ovKey(path[i].x, path[i].z)
			if not rset[k1] then i += 1; continue end

			local axis
			if i < #path then
				local dx = path[i+1].x - path[i].x
				local dz = path[i+1].z - path[i].z
				if math.abs(dx) == 1 and dz == 0 then axis = "EW"
				elseif math.abs(dz) == 1 and dx == 0 then axis = "NS" end
			end

			if not axis then
				i += 1
			else
				local startCell = path[i]
				local j = i
				while j < #path do
					local cur = path[j]
					local nxt = path[j+1]
					if not rset[_ovKey(nxt.x, nxt.z)] then break end
					local dx = nxt.x - cur.x
					local dz = nxt.z - cur.z
					local ok = (axis == "EW" and math.abs(dx) == 1 and dz == 0)
						or (axis == "NS" and math.abs(dz) == 1 and dx == 0)
					if not ok then break end
					j += 1
				end
				local endCell = path[j]
				local runLen = math.max(math.abs(endCell.x - startCell.x), math.abs(endCell.z - startCell.z)) + 1
				if runLen >= 2 then
					_ensureBox(player, zoneFolder, asset, assetName, powerZoneId, roadZoneId, axis, "Start", startCell, endCell, startCell, existingByKey, validKeys)
					_ensureBox(player, zoneFolder, asset, assetName, powerZoneId, roadZoneId, axis, "End",   startCell, endCell, endCell,   existingByKey, validKeys)
				end
				i = j + 1
			end
		end
	end

	-- remove stale
	for k, inst in pairs(existingByKey) do
		if not validKeys[k] then
			_box_dprint("Removing stale overlap box:", k)
			inst:Destroy()
		end
	end

	-- group boxes by RunKey
	local boxesByRun = {}
	for _, inst in ipairs(zoneFolder:GetChildren()) do
		if inst:GetAttribute("IsPowerRoadBox") then
			local key = inst:GetAttribute("RunKey")
			if key then
				boxesByRun[key] = boxesByRun[key] or {}
				table.insert(boxesByRun[key], inst)
			end
		end
	end

	-- ONLY the nearest endpoint in each run gets ropes; others are cleaned
	for _, pair in pairs(boxesByRun) do
		table.sort(pair, function(a, b)
			return _distToNearestPole(zoneFolder, a) < _distToNearestPole(zoneFolder, b)
		end)
		for i, box in ipairs(pair) do
			if i == 1 then
				_connectBoxToNearestPoles(zoneFolder, box, BOX_LINK_MAX_DISTANCE)
				box:SetAttribute("IsPrimaryLinkEndpoint", true)
			else
				_detachAllRopesFromModel(box)
				box:SetAttribute("IsPrimaryLinkEndpoint", false)
			end
		end
	end
end

-- Public: recompute for all power zones on the plot (use this after roads change)
function PowerGeneratorModule.ensureOverlapBoxesForAll(player)
	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId); if not plot then return end
	local pf   = plot:FindFirstChild("PowerLines"); if not pf then return end
	for _, zf in ipairs(pf:GetChildren()) do
		if zf:IsA("Folder") then
			PowerGeneratorModule.ensureOverlapBoxesForPowerZone(player, zf.Name)
		end
	end
end

-- Public: remove all road-power boxes belonging to this power zone (use when power zone removed if needed elsewhere)
function PowerGeneratorModule.removeBoxesForPowerZone(player, powerZoneId)
	local zoneFolder = _getPowerZoneFolder(player, powerZoneId); if not zoneFolder then return end
	for _, inst in ipairs(zoneFolder:GetDescendants()) do
		if (inst:IsA("Model") or inst:IsA("BasePart"))
			and inst:GetAttribute("IsPowerRoadBox") == true
			and inst:GetAttribute("ZoneId") == powerZoneId
		then
			inst:Destroy()
		end
	end
end

---------------------------------------------------------------------
--  Generate (place) a single pole/segment
---------------------------------------------------------------------
function PowerGeneratorModule.generatePowerSegment(
	terrain, parentFolder, player, zoneId, mode,
	gridCoord, powerData, rotationY, onPlaced
)
	rotationY = rotationY or 0

	local playerPlot        = terrain.Parent
	local gb, terrains      = getGlobalBoundsForPlot(playerPlot)
	local cellX, _, cellZ   = GridUtils.globalGridToWorldPosition(gridCoord.x, gridCoord.z, gb, terrains)
	local finalPos          = Vector3.new(cellX,
		terrain.Position.Y + (terrain.Size.Y*0.5) + Y_OFFSET,
		cellZ)

	local instance = powerData.stages and powerData.stages.Stage3
	if not instance then
		warn("generatePowerSegment: 'Stage3' missing for", powerData.name or "<unknown>")
		return
	end

	local clone
	if instance:IsA("Model") then
		clone = instance:Clone()
		clone.Name = "PowerLines"
		if clone.PrimaryPart then
			clone:SetPrimaryPartCFrame(
				CFrame.new(finalPos) * CFrame.Angles(0, math.rad(rotationY), 0))
		end
	elseif instance:IsA("BasePart") then
		clone           = instance:Clone()
		clone.Name      = "PowerLines"
		clone.Position  = finalPos
		clone.Orientation = Vector3.new(0, rotationY, 0)
	else
		warn("Invalid power segment instance type:", instance.ClassName); return
	end

	for _, part in ipairs(clone:GetDescendants()) do
		if part:IsA("BasePart") then part.CanQuery = false end
	end

	clone:SetAttribute("ZoneId",  zoneId)
	clone:SetAttribute("LineType",mode)
	clone:SetAttribute("GridX",   gridCoord.x)
	clone:SetAttribute("GridZ",   gridCoord.z)
	clone.Parent = parentFolder

	-- mark grid as occupied
	local occId = zoneId.."_power_"..gridCoord.x.."_"..gridCoord.z
	ZoneTrackerModule.markGridOccupied(player, gridCoord.x, gridCoord.z, "power", occId, mode)

	if onPlaced then onPlaced() end
end

---------------------------------------------------------------------
-- Dynamic rope-linking utilities
---------------------------------------------------------------------
-- Returns the attachment with smallest and largest projection onto `dir`
local function getExtremes(model, dir)
	local minDot, maxDot = math.huge, -math.huge
	local minAtt, maxAtt = nil, nil
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("Attachment") then
			local d = obj.WorldPosition:Dot(dir)
			if d < minDot then minDot, minAtt = d, obj end
			if d > maxDot then maxDot, maxAtt = d, obj end
		end
	end
	return minAtt, maxAtt  -- back, front
end

local LINE_SLACK_DEFAULT = 0.05   -- 5% slack when clear
local LINE_SLACK_MIN     = 0.01   -- ~taut when obstructed
local LINE_SCAN_WIDTH    = 8      -- studs
local LINE_SCAN_EXTRA_H  = 60     -- studs

local function _needsTautLine(a0: Attachment, a1: Attachment, excludeFolder: Instance?)
	local p0, p1 = a0.WorldPosition, a1.WorldPosition
	local v      = p1 - p0
	local d      = v.Magnitude
	if d < 1e-3 then return false end

	local mid  = (p0 + p1) * 0.5
	local look = CFrame.lookAt(mid, mid + v.Unit, Vector3.yAxis)
	local size = Vector3.new(
		LINE_SCAN_WIDTH,
		math.max(LINE_SCAN_EXTRA_H, math.abs(p0.Y - p1.Y) + LINE_SCAN_EXTRA_H),
		d + 2
	)

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludeFolder and { excludeFolder } or {}

	for _, part in ipairs(Workspace:GetPartBoundsInBox(look, size, params)) do
		if part:IsA("BasePart") and part.CanCollide then
			local n = string.lower(part.Name)
			-- ignore our own power/rope bits
			if not (n:find("rope") or n:find("powerline") or n:find("padpole") or n:find("guide") or n:find("pipe")) then
				return true
			end
		end
	end
	return false
end

local function _hasRopeBetween(a0: Attachment, a1: Attachment): boolean
	for _, d in ipairs(a0.Parent:GetDescendants()) do
		if d:IsA("RopeConstraint") and d.Attachment0 == a0 and d.Attachment1 == a1 then
			return true
		end
	end
	for _, d in ipairs(a1.Parent:GetDescendants()) do
		if d:IsA("RopeConstraint") and d.Attachment0 == a0 and d.Attachment1 == a1 then
			return true
		end
	end
	return false
end

function createRope(a0, a1)
	if not a0 or not a1 then return end
	if a0.Parent == a1.Parent then
		-- Prevent “self”-linking (same pole’s two ends shouldn’t be bridged by road logic)
		-- If you *do* want local crossbars, comment this out.
		return
	end
	if _hasRopeBetween(a0, a1) then return end

	local rope         = Instance.new("RopeConstraint")
	rope.Attachment0   = a0
	rope.Attachment1   = a1
	rope.Visible       = true
	rope.Color         = BrickColor.new("Black")
	rope.Thickness     = 0.05
	rope.WinchEnabled  = false
	rope.Restitution   = 0

	local span         = (a0.WorldPosition - a1.WorldPosition).Magnitude
	local needsTaut    = _needsTautLine(a0, a1, a0.Parent)
	local slack        = needsTaut and LINE_SLACK_MIN or LINE_SLACK_DEFAULT
	rope.Length        = span * (1 + slack)

	rope.Parent        = a0.Parent
end

-- === Obstruction scan + inline mid-pole helpers ===
local INLINE_POLE_IF_OBSTRUCTED = true
local SCAN_WIDTH  = 8      -- studs: corridor width for obstacle scan
local SCAN_Y_EXTRA= 60     -- studs: extra scan height
local TAUT_SLACK  = 0.01   -- 1% slack when we split spans
local KEEP_SLACK  = 0.05   -- 5% slack if we don't split

-- Fast attachment lookup by name ("1" or "2")
local function _findAtt(model: Instance, attName: string)
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("Attachment") and obj.Name == attName then
			return obj
		end
	end
end

-- Scan a corridor between attachments; return (hasHit, bestT, topY)
local function _scanSpan(att0: Attachment, att1: Attachment, excludeFolder: Instance?)
	local p0, p1 = att0.WorldPosition, att1.WorldPosition
	local v  = p1 - p0
	local d  = v.Magnitude
	if d < 1e-3 then return false end

	local mid  = (p0 + p1) * 0.5
	local look = CFrame.lookAt(mid, mid + v.Unit, Vector3.yAxis)
	local size = Vector3.new(
		SCAN_WIDTH,
		math.max(SCAN_Y_EXTRA, math.abs(p0.Y - p1.Y) + SCAN_Y_EXTRA),
		d + 2
	)

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludeFolder and { excludeFolder } or {}

	local bestT, topY = 0.5, -math.huge
	for _, part in ipairs(Workspace:GetPartBoundsInBox(look, size, params)) do
		if part:IsA("BasePart") and part.CanCollide then
			local n = string.lower(part.Name)
			if not (n:find("rope") or n:find("powerline") or n:find("padpole") or n:find("pipe")) then
				local ty = part.Position.Y + part.Size.Y * 0.5
				if ty > topY then
					topY = ty
					local t = ((part.Position - p0):Dot(v.Unit)) / d
					bestT = math.clamp(t, 0.2, 0.8)
				end
			end
		end
	end
	return (topY > -math.huge), bestT, topY
end

-- Snap a rotation (deg) from two points to nearest 90°
local function _snapRotFrom(a: Vector3, b: Vector3)
	local angle = math.deg(math.atan2(b.X - a.X, b.Z - a.Z))
	return (math.floor((angle + 45) / 90) * 90) % 360
end

-- Find the nearest grid cell (from gridList) to a world point
local function _nearestGridInList(worldPos: Vector3, gridList: {{x:number,z:number}}, gb, terrains)
	local best, bestC = math.huge, nil
	for _, c in ipairs(gridList) do
		local wx, _, wz = GridUtils.globalGridToWorldPosition(c.x, c.z, gb, terrains)
		local d = (worldPos - Vector3.new(wx, worldPos.Y, wz)).Magnitude
		if d < best then best, bestC = d, c end
	end
	return bestC
end

local function _getTwoAttachments(model: Instance)
	local onBase = {}
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("Attachment") and obj.Parent and obj.Parent:IsA("BasePart") then
			table.insert(onBase, obj)
		end
	end
	-- Prefer explicit "1"/"2"
	local a1, a2
	for _, a in ipairs(onBase) do if a.Name == "1" then a1 = a break end end
	for _, a in ipairs(onBase) do if a.Name == "2" then a2 = a break end end
	if a1 and a2 then return a1, a2 end
	-- Fallback: first two
	if #onBase >= 2 then return onBase[1], onBase[2] end
	return nil, nil
end

local function _connectBoxToNearestPole(zoneFolder: Instance, boxModel: Instance)
	if not (zoneFolder and boxModel) then return false end

	local boxPos = _modelPos(boxModel)
	local pole, dist = _nearestPoleModel(zoneFolder, boxPos, BOX_LINK_MAX_DISTANCE)
	if not pole then
		_detachAllRopesFromModel(boxModel) -- keep box clean if nothing nearby
		return false
	end

	-- Find two usable attachments on each
	local b1, b2 = _getTwoAttachments(boxModel)
	local p1, p2 = _getTwoAttachments(pole)
	if not (b1 and b2 and p1 and p2) then
		local ba = _listAttachments(boxModel)
		local pa = _listAttachments(pole)
		b1, b2 = ba[1], ba[2]
		p1, p2 = pa[1], pa[2]
		if not (b1 and b2 and p1 and p2) then return false end
	end

	-- Sort left→right on a lateral axis, then pair (avoids criss-cross)
	local dir = (_modelPos(pole) - boxPos)
	if dir.Magnitude < 1e-6 then dir = Vector3.zAxis end
	local u = dir.Unit
	local left = Vector3.yAxis:Cross(u)
	if left.Magnitude < 1e-6 then left = Vector3.xAxis end
	left = left.Unit

	local b = {b1, b2}
	table.sort(b, function(a, c) return (a.WorldPosition - boxPos):Dot(left) < (c.WorldPosition - boxPos):Dot(left) end)

	local polePos = _modelPos(pole)
	local p = {p1, p2}
	table.sort(p, function(a, c) return (a.WorldPosition - polePos):Dot(left) < (c.WorldPosition - polePos):Dot(left) end)

	-- Freshen ropes on this box, then connect
	_detachAllRopesFromModel(boxModel)
	createRope(b[1], p[1])
	createRope(b[2], p[2])
	return true
end

-- Fast XZ segment intersection test (final guard against criss-cross)
local function _xzCross(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3): boolean
	local function orient(p, q, r)
		return (q.X - p.X) * (r.Z - p.Z) - (q.Z - p.Z) * (r.X - p.X)
	end
	local o1 = orient(a0, a1, b0)
	local o2 = orient(a0, a1, b1)
	local o3 = orient(b0, b1, a0)
	local o4 = orient(b0, b1, a1)
	-- treat collinear as non-cross for our use case
	return (o1 * o2 < 0 and o3 * o4 < 0)
end

-- Dynamic: works for any heading (N, S, E, W, diagonals, bends…)
function linkPoles(prevPole: Instance, currPole: Instance)
	if not (prevPole and currPole) then return end

	local p1a, p1b = _getTwoAttachments(prevPole)
	local p2a, p2b = _getTwoAttachments(currPole)
	if not (p1a and p1b and p2a and p2b) then
		warn("linkPoles: could not find two valid attachments on each pole"); return
	end

	-- Direction from prev → curr (world space)
	local P = _modelPos(prevPole)
	local C = _modelPos(currPole)
	local dir = (C - P)
	if dir.Magnitude < 1e-6 then dir = Vector3.zAxis end
	local u = dir.Unit

	-- "Left" axis in world space to sort attachments laterally (consistent pairing)
	local left = Vector3.yAxis:Cross(u)
	if left.Magnitude < 1e-6 then left = Vector3.xAxis end
	left = left.Unit

	-- Sort each pole’s two attachments by lateral offset (leftmost first)
	local p1 = {p1a, p1b}
	table.sort(p1, function(a, b)
		return (a.WorldPosition - P):Dot(left) < (b.WorldPosition - P):Dot(left)
	end)
	local p2 = {p2a, p2b}
	table.sort(p2, function(a, b)
		return (a.WorldPosition - C):Dot(left) < (b.WorldPosition - C):Dot(left)
	end)

	local a1, a2 = p1[1], p1[2]
	local b1, b2 = p2[1], p2[2]

	local function totalLen(x1, y1, x2, y2)
		return (x1.WorldPosition - y1.WorldPosition).Magnitude
			+ (x2.WorldPosition - y2.WorldPosition).Magnitude
	end

	-- Prefer lateral pairing; if ambiguous use shorter total length; guard against crossing
	local L_sorted  = totalLen(a1, b1, a2, b2)
	local L_swapped = totalLen(a1, b2, a2, b1)
	local sortedCrosses = _xzCross(a1.WorldPosition, b1.WorldPosition, a2.WorldPosition, b2.WorldPosition)

	local useSorted = not sortedCrosses and (L_sorted <= L_swapped)

	local pair1a, pair2a, pair1b, pair2b
	if useSorted then
		pair1a, pair2a = a1, b1
		pair1b, pair2b = a2, b2
	else
		pair1a, pair2a = a1, b2
		pair1b, pair2b = a2, b1
	end

	createRope(pair1a, pair2a)
	createRope(pair1b, pair2b)
end

local MAX_BRIDGE_DISTANCE = PADPOLE_LINK_MAX_DISTANCE

local function modelWorldPos(m: Instance)
	return (m.PrimaryPart and m.PrimaryPart.Position) or m:GetPivot().Position
end

local function findNearestLineOnPlot(plot: Instance, fromPos: Vector3)
	local powerFolder = plot:FindFirstChild("PowerLines"); if not powerFolder then return end
	local nearest, best = nil, math.huge
	for _, m in ipairs(powerFolder:GetDescendants()) do
		if m:IsA("Model") and (m.Name == "PowerLines" or m:GetAttribute("LineType")) then
			local d = (modelWorldPos(m) - fromPos).Magnitude
			if d < best then best, nearest = d, m end
		end
	end
	return nearest, best
end

local function bridgePadPoleToNearestLine(plot: Instance, padPole: Model)
	if not (plot and padPole) then return end
	if padPole:GetAttribute("BridgedToLine") then return end -- avoid dup ropes

	local pos = modelWorldPos(padPole)
	local line, dist = findNearestLineOnPlot(plot, pos)
	if line and dist <= MAX_BRIDGE_DISTANCE then
		local linePos = modelWorldPos(line)
		local gridDelta = planarGridDistance(linePos, pos)
		if gridDelta <= PADPOLE_LINK_MAX_GRIDS then
			linkPoles(line, padPole)           -- uses your existing "1"/"2" attachments
			padPole:SetAttribute("BridgedToLine", true)
		elseif DEBUG_LOGS then
			debugPrint(string.format(
				"Skipping padpole bridge (%.2f grids away; limit=%d)",
				gridDelta,
				PADPOLE_LINK_MAX_GRIDS
			))
		end
	end
end

---------------------------------------------------------------------
--  Main placement routine
---------------------------------------------------------------------
function PowerGeneratorModule.populateZone(player, zoneId, mode, gridList, _predefinedLines, _rotation, _skipStages, isReload)
	--print("[PowerGeneratorModule] populateZone CALLED:", player, zoneId, mode)

	task.spawn(function()
		local isFastReload = isReload == true
		debugPrint("Populating Power Zone:", zoneId, "(mode:", mode, ")")

		-----------------------------------------------------------------
		--  NEW: mark as populating + guard against concurrent populates
		-----------------------------------------------------------------
		ZoneTrackerModule.setZonePopulating(player, zoneId, true) -- NEW

		local _powerReserve = select(1, GridUtils.reserveArea(player, zoneId, "power", gridList or {}, { ttl = 20.0 }))
		if not _powerReserve and not isFastReload then
			local tries = 0
			while tries < 5 do
				task.wait(0.2); tries += 1
				_powerReserve = select(1, GridUtils.reserveArea(player, zoneId, "power", gridList or {}, { ttl = 20.0 }))
				if _powerReserve then break end
			end
			if not _powerReserve then
				warn(("[PowerGenerator] %s could not obtain reservation; proceeding best-effort"):format(zoneId))
			end
		end

		-----------------------------------------------------------------
		--  Validation / setup
		-----------------------------------------------------------------
		local playerPlot = Workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId)
		if not playerPlot then
			warn("Player plot not found for", player)
			zonePopulatedEvent:Fire(player, zoneId, {})
			if _powerReserve then GridUtils.releaseReservation(_powerReserve) end
			ZoneTrackerModule.setZonePopulating(player, zoneId, false)
			return
		end

		local terrain = playerPlot:FindFirstChild("TestTerrain")
		if not terrain then
			warn("TestTerrain not found in plot", playerPlot.Name)
			zonePopulatedEvent:Fire(player, zoneId, {})
			if _powerReserve then GridUtils.releaseReservation(_powerReserve) end
			ZoneTrackerModule.setZonePopulating(player, zoneId, false)
			return
		end

		-----------------------------------------------------------------
		--  NEW: pre-clear any stale footprint for this zone (idempotent)
		-----------------------------------------------------------------
		if type(gridList) == "table" and #gridList > 0 then
			ZoneTrackerModule.forceClearZoneFootprint(player, zoneId, gridList) -- NEW
		end

		local powerFolder = playerPlot:FindFirstChild("PowerLines")
		if not powerFolder then
			powerFolder      = Instance.new("Folder")
			powerFolder.Name = "PowerLines"
			powerFolder.Parent = playerPlot
		end

		-- Idempotent visuals folder for this zone
		local zoneFolder = powerFolder:FindFirstChild(zoneId)
		if zoneFolder then
			zoneFolder:Destroy()
		end
		zoneFolder      = Instance.new("Folder")
		zoneFolder.Name = zoneId
		zoneFolder.Parent = powerFolder

		local powerList = BuildingMasterList.getPowerLinesByStyle("Default")
		if #powerList == 0 then
			warn("No power lines found for style 'Default'")
			zonePopulatedEvent:Fire(player, zoneId, {})
			if _powerReserve then GridUtils.releaseReservation(_powerReserve) end
			ZoneTrackerModule.setZonePopulating(player, zoneId, false)
			return
		end

		local basePower
		for _, p in ipairs(powerList) do
			if (p.name or p.Name) == "PowerLines" then basePower = p; break end
		end
		if not basePower then
			warn("No entry named 'PowerLines' in BuildingMasterList.")
			zonePopulatedEvent:Fire(player, zoneId, {})
			if _powerReserve then GridUtils.releaseReservation(_powerReserve) end
			ZoneTrackerModule.setZonePopulating(player, zoneId, false)
			return
		end

		-----------------------------------------------------------------
		--  Ensure path registered in PowerLinePath
		-----------------------------------------------------------------
		local existing = PowerLinePath.getLineData(zoneId)
		if not (existing and existing.pathCoords) then
			if gridList and #gridList > 0 then
				local startCoord, endCoord = gridList[1], gridList[#gridList]
				PowerLinePath.registerLine(zoneId, mode, gridList, startCoord, endCoord)
			else
				warn("PowerGeneratorModule: No gridList provided; cannot register PowerLinePath for", zoneId)
			end
		end

		-----------------------------------------------------------------
		--  NEW: last-minute conflict guard (other zone currently populating)
		-----------------------------------------------------------------
		--[[
		local conflict, otherId = ZoneTrackerModule.hasPopulatingConflict(player, gridList)
		if conflict and otherId ~= zoneId then
			local oz = ZoneTrackerModule.getZoneById(player, otherId)
			if oz and (oz.mode == "PowerLines" or oz.mode == "DirtRoad" or oz.mode == "Pavement" or oz.mode == "Highway") then
				warn(("[PowerGenerator] %s blocked by in-flight %s zone %s; skipping")
					:format(zoneId, tostring(oz.mode), tostring(otherId)))
				zonePopulatedEvent:Fire(player, zoneId, {})
				ZoneTrackerModule.setZonePopulating(player, zoneId, false)
				return
			end
		end
		]]
		local network   = PowerLinePath.getLineNetworks()[zoneId] or {}
		local segments  = network.segments or {}

		-- Helper: rotation for a given cell from segments
		local function computeRotationForCell(cell)
			local rotationY = 0
			for iSeg, seg in ipairs(segments) do
				if seg.coord.x == cell.x and seg.coord.z == cell.z then
					local dir = seg.direction
					if dir == "End" and iSeg > 1 then dir = segments[iSeg-1].direction end
					rotationY = getRotationForDirection(dir)
					break
				end
			end
			return rotationY
		end

		local gridSet = {}
		for _, c in ipairs(gridList) do
			gridSet[c.x..","..c.z] = true
		end

		-----------------------------------------------------------------
		--  Placement state
		-----------------------------------------------------------------
		local placedLinesData   = {}
		local lineCount         = 0
		local nextEventThreshold= math.random(5,10)
		local function onLinePlaced()
			lineCount += 1
			if lineCount >= nextEventThreshold then
				linesPlacedEvent:Fire(player, zoneId, lineCount)
				lineCount = 0; nextEventThreshold = math.random(5,10)
			end
		end

		local firstPoleInstance, lastPoleInstance, lastPlacedPole
		local lastPlacedCoord = nil
		local bridgedZones    = {}
		local touchedZones = {}

		local function isPowerZoneId(zid)
			return type(zid) == "string" and zid:sub(1, #"PowerLinesZone_") == "PowerLinesZone_"
		end

		-----------------------------------------------------------------
		--  Iterate over grid cells
		-----------------------------------------------------------------
		for i = 1, #gridList do
			local cell = gridList[i]

			-- ignore our own prior power occupancy so recreate never blocks
			local occupied = ZoneTrackerModule.isGridOccupied(
				player, cell.x, cell.z,
				{
					excludeOccupantId   = zoneId,
					excludeOccupantType = "power",
					-- pass RAW mode names to the tracker
					excludeZoneTypes    = OverlapExclusionsRaw,
				}
			)

			local types    = ZoneTrackerModule.getGridOccupantTypes(player, cell.x, cell.z) or {}
			local hasRoad, hasBuilding = types.road ~= nil, types.building ~= nil

			local foreignZoneId = ZoneTrackerModule.getOtherZoneIdAtGrid(player, cell.x, cell.z, zoneId)
			local crossesOther  = foreignZoneId and foreignZoneId ~= zoneId
			local crossesOtherPower = crossesOther and isPowerZoneId(foreignZoneId)
			local crossesOtherExcluded = crossesOther and _isExcludedZone(player, foreignZoneId)

			local crossesBuildingLike = false
			if crossesOther then
				local oz = ZoneTrackerModule.getZoneById(player, foreignZoneId)
				if oz
					and (oz.mode ~= "DirtRoad" and oz.mode ~= "Pavement" and oz.mode ~= "Highway" and oz.mode ~= "Road" and oz.mode ~= "PowerLines")
					and not _isExcludedZone(player, foreignZoneId)
				then
					crossesBuildingLike = true
				end
			end

			if DEBUG_LOGS and crossesOther then
				local oz = ZoneTrackerModule.getZoneById(player, foreignZoneId)
				debugPrint(string.format(
					"foreign@(%d,%d): id=%s mode=%s excluded=%s types=[%s]",
					cell.x, cell.z,
					tostring(foreignZoneId),
					tostring(oz and oz.mode),
					tostring(crossesOtherExcluded),
					_dumpTypes(types)
					))
			end

			-- Treat *only* non-excluded foreign stuff as non-power blockers
			local occupiedByNonPower = occupied and (
				hasRoad
					or hasBuilding
					or ((not crossesOtherExcluded) and hasAnyNonRoad(types))
			)

			local enteringBuilding = false
			if i < #gridList then
				local n = gridList[i+1]
				-- Use occupant types first (more robust than mode names across zone kinds)
				local nTypes = ZoneTrackerModule.getGridOccupantTypes(player, n.x, n.z) or {}
				local nzid   = ZoneTrackerModule.getOtherZoneIdAtGrid(player, n.x, n.z, zoneId)
				local nextExcluded = _isExcludedZone(player, nzid)

				if nTypes.building or ((not nextExcluded) and hasAnyNonRoad(nTypes)) then
					enteringBuilding = true
				else
					-- Fallback: if a foreign zone is recorded on the next cell and it's not a road/power/excluded, treat as building-like
					if nzid then
						local nz = ZoneTrackerModule.getZoneById(player, nzid)
						if nz
							and (nz.mode ~= "DirtRoad" and nz.mode ~= "Pavement" and nz.mode ~= "Highway" and nz.mode ~= "Road" and nz.mode ~= "PowerLines")
							and not _isExcludedZone(player, nzid)
						then
							enteringBuilding = true
						end
					end
				end
			end

			-- Non-road crossing block (explicit variable to reuse consistently)
			local nonRoadCrossBlock =
				(crossesOther and not crossesOtherPower and not crossesOtherExcluded)
				and (hasAnyNonRoad(types) and not isRoadCell(types))
				or false

			-----------------------------------------------------------------
			--  VIRTUAL SUPPRESSION (key fix)
			-----------------------------------------------------------------
			if hasRoad then
				local roadZoneId = getRoadZoneIdAtCell(player, cell.x, cell.z)
				if roadZoneId then
					local yaw = computeRotationForCell(cell)

					-- Compute same placement CF as generatePowerSegment would
					local gb, terrains = getGlobalBoundsForPlot(playerPlot)
					local wx, wy, wz   = GridUtils.globalGridToWorldPosition(cell.x, cell.z, gb, terrains)
					local finalPos     = Vector3.new(wx, terrain.Position.Y + (terrain.Size.Y*0.5) + Y_OFFSET, wz)
					local cf           = CFrame.new(finalPos) * CFrame.Angles(0, math.rad(yaw), 0)

					local ghost = basePower.stages and basePower.stages.Stage3 and basePower.stages.Stage3:Clone()
					if ghost then
						ghost.Name = "PowerLines"
						ghost:SetAttribute("ZoneId", zoneId)
						ghost:SetAttribute("LineType", mode)
						ghost:SetAttribute("GridX", cell.x)
						ghost:SetAttribute("GridZ", cell.z)
						ghost:SetAttribute("SuppressedByRoadId", roadZoneId)

						-- Store as if a road suppressed it; do NOT parent it now.
						LayerManagerModule.storeRemovedObject("PowerLines", roadZoneId, {
							instanceClone  = ghost,
							originalParent = zoneFolder,
							cframe         = cf,
						}, player)
						bridgedZones[roadZoneId] = true
						-- do not place the pole in-world here
					end
				end
			end

			-- AVOID_ROPES_THROUGH_NON_ROAD guard (honors exclusions)
			if AVOID_ROPES_THROUGH_NON_ROAD and (not crossesOtherPower) and (not crossesOtherExcluded) and crossesOther then
				if nonRoadCrossBlock then
					if BRIDGE_TO_NEAREST_PADPOLE and lastPlacedPole and lastPlacedCoord and not bridgedZones[foreignZoneId] then
						local jumperCoord = findFreeNeighborInside(gridSet, lastPlacedCoord)
						local gb, terrains = getGlobalBoundsForPlot(playerPlot)
						local jumperWorldPos
						if gb then
							local jx, jy, jz = GridUtils.globalGridToWorldPosition(jumperCoord.x, jumperCoord.z, gb, terrains)
							jumperWorldPos = Vector3.new(jx, jy, jz)
						end

						local padpole = jumperWorldPos and findNearestPadPole(playerPlot, jumperWorldPos) or nil
						local canBridge = false
						local gridDelta
						if padpole and jumperWorldPos then
							gridDelta = planarGridDistance(jumperWorldPos, modelWorldPos(padpole))
							canBridge = gridDelta <= BUILDING_PADPOLE_MAX_GRIDS
							if not canBridge and DEBUG_LOGS then
								debugPrint(string.format(
									"Padpole bridge blocked for %s: %.2f grids away (limit=%d)",
									tostring(foreignZoneId), gridDelta, BUILDING_PADPOLE_MAX_GRIDS
								))
							end
						elseif DEBUG_LOGS then
							debugPrint(string.format(
								"Padpole bridge blocked for %s: no candidate within range",
								tostring(foreignZoneId)
							))
						end

						if canBridge and padpole then
							local before = zoneFolder:GetChildren()
							PowerGeneratorModule.generatePowerSegment(
								terrain, zoneFolder, player, zoneId, mode,
								jumperCoord, basePower, 0, onLinePlaced
							)
							local jumperInstance
							for _, inst in ipairs(zoneFolder:GetChildren()) do
								if not table.find(before, inst) then jumperInstance = inst; break end
							end
							if jumperInstance then
								linkPoles(lastPlacedPole, jumperInstance)
								linkPoles(jumperInstance, padpole)
								lastPlacedPole   = nil
								lastPlacedCoord  = nil
								bridgedZones[foreignZoneId] = true
							end
						else
							if not padpole then
								warn("No padpole found to bridge to; jumper suppressed.")
							end
							lastPlacedPole  = nil
							lastPlacedCoord = nil
						end
					else
						lastPlacedPole  = nil
						lastPlacedCoord = nil
					end
				end
				-- IMPORTANT: no "else" here — benign overlaps shouldn't wipe linking state
			end

			-----------------------------------------------------------------
			--  Place pole if not blocked by non-power or road/building
			-----------------------------------------------------------------
			if not (occupiedByNonPower or hasRoad or hasBuilding or enteringBuilding or crossesBuildingLike or nonRoadCrossBlock) then
				local rotationY = computeRotationForCell(cell)

				local before = zoneFolder:GetChildren()
				PowerGeneratorModule.generatePowerSegment(
					terrain, zoneFolder, player, zoneId, mode,
					cell, basePower, rotationY, onLinePlaced
				)

				local newInstance
				for _, inst in ipairs(zoneFolder:GetChildren()) do
					if not table.find(before, inst) then newInstance = inst; break end
				end

				if newInstance then
					if lastPlacedPole then linkPoles(lastPlacedPole, newInstance) end
					lastPlacedPole = newInstance
					lastPlacedCoord = { x = cell.x, z = cell.z }
				end

				if not firstPoleInstance then firstPoleInstance = newInstance end
				lastPoleInstance = newInstance

				table.insert(placedLinesData, {lineName = basePower.name or "PowerLines", gridX = cell.x, gridZ = cell.z})
				if not isFastReload then
					task.wait(BUILD_INTERVAL)
				end
			else
				debugPrint(("Skipping (%d,%d) — occ:%s road:%s bld:%s")
					:format(cell.x, cell.z, tostring(occupied), tostring(hasRoad), tostring(hasBuilding)))
			end
		end

		if BRIDGE_TO_NEAREST_PADPOLE then
			for _, m in ipairs(playerPlot:GetDescendants()) do
				if m:IsA("Model") and (m:GetAttribute("IsPadPole") or m.Name:match("[Pp]ad[Pp]ole")) then
					bridgePadPoleToNearestLine(playerPlot, m)
				end
			end
		end

		-- Events
		for zId in pairs(touchedZones) do
			print(("[PowerGeneratorModule] finished – power line for %s touched neighbouring zone %s")
				:format(zoneId, zId))
			linesPlacedEvent:Fire(player, zId, placedLinesData)
		end

		debugPrint("Placement loop complete for zone", zoneId)
		zonePopulatedEvent:Fire(player, zoneId, placedLinesData)
		linesPlacedEvent:Fire(player, zoneId, placedLinesData)

		-- Overlap boxes for THIS power zone
		PowerGeneratorModule.ensureOverlapBoxesForPowerZone(player, zoneId)

		-- Mark populated & clear populating flag
		ZoneTrackerModule.setZonePopulated(player, zoneId, true)
		if _powerReserve then GridUtils.releaseReservation(_powerReserve) end
		ZoneTrackerModule.setZonePopulating(player, zoneId, false)
	end)
end


---------MORE
---------------------------------------------------------------------
--  INTERNAL util used by rebuilders
---------------------------------------------------------------------
local function _findPoleInZone(zoneFolder: Instance, gx: number, gz: number)
	for _, inst in ipairs(zoneFolder:GetChildren()) do
		if (inst:IsA("Model") or inst:IsA("BasePart"))
			and inst:GetAttribute("GridX") == gx
			and inst:GetAttribute("GridZ") == gz
			and (inst.Name == "PowerLines" or inst:GetAttribute("LineType"))
		then
			return inst
		end
	end
	return nil
end

local function _hasPoleInZone(zoneFolder: Instance, gx: number, gz: number): boolean
	for _, inst in ipairs(zoneFolder:GetChildren()) do
		if (inst:IsA("Model") or inst:IsA("BasePart"))
			and (inst.Name == "PowerLines" or inst:GetAttribute("LineType"))
			and inst:GetAttribute("GridX") == gx
			and inst:GetAttribute("GridZ") == gz
		then
			return true
		end
	end
	return false
end

local function _indexOfSeg(segs, gx, gz)
	for i, seg in ipairs(segs or {}) do
		local x = (seg.coord and seg.coord.x) or seg.x
		local z = (seg.coord and seg.coord.z) or seg.z
		if x == gx and z == gz then return i end
	end
	return nil
end

-- Return true iff all cells between [iA+1, iB-1] are "bridgeable" (road/empty/excluded), and contain no pole.
local function _cellsBetweenAreRoadOnly(player, zoneFolder, segs, iA, iB)
	if not iA or not iB or iB - iA <= 1 then return false end
	for k = iA + 1, iB - 1 do
		local seg = segs[k]
		local gx = (seg.coord and seg.coord.x) or seg.x
		local gz = (seg.coord and seg.coord.z) or seg.z

		-- If any pole still exists mid-run, we don't bridge over it.
		if _findPoleInZone(zoneFolder, gx, gz) then
			return false
		end

		-- Check occupant types
		local types = ZoneTrackerModule.getGridOccupantTypes(player, gx, gz) or {}
		-- If there is any non-road occupant (not in exclusions), don't bridge.
		if hasAnyNonRoad(types) and not isRoadCell(types) then
			return false
		end
	end
	return true
end

-- Bridge across **this** removed cell if possible.
local function _bridgeAcrossRoadGapAt(player, powerZoneId, gx, gz)
	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId); if not plot then return end
	local powerFolder = plot:FindFirstChild("PowerLines");                         if not powerFolder then return end
	local zoneFolder  = powerFolder:FindFirstChild(powerZoneId);                   if not zoneFolder  then return end

	local net  = PowerLinePath.getLineNetworks()[powerZoneId] or PowerLinePath.getLineData(powerZoneId) or {}
	local segs = net.segments or net.pathCoords or {}
	if #segs == 0 then return end

	local i0 = _indexOfSeg(segs, gx, gz); if not i0 then return end

	-- Scan backward to nearest existing pole
	local iL, leftPole = nil, nil
	for i = i0 - 1, 1, -1 do
		local s = segs[i]; local x = (s.coord and s.coord.x) or s.x; local z = (s.coord and s.coord.z) or s.z
		local pole = _findPoleInZone(zoneFolder, x, z)
		if pole then iL, leftPole = i, pole; break end
	end

	-- Scan forward to nearest existing pole
	local iR, rightPole = nil, nil
	for i = i0 + 1, #segs do
		local s = segs[i]; local x = (s.coord and s.coord.x) or s.x; local z = (s.coord and s.coord.z) or s.z
		local pole = _findPoleInZone(zoneFolder, x, z)
		if pole then iR, rightPole = i, pole; break end
	end

	if not (leftPole and rightPole and iL and iR) then return end

	-- Only bridge if all the in-between path cells are road/empty/excluded
	if not _cellsBetweenAreRoadOnly(player, zoneFolder, segs, iL, iR) then return end

	-- Directly link the two neighbors across the road gap
	linkPoles(leftPole, rightPole)
end

function PowerGeneratorModule.suppressPoleForRoad(player, roadZoneId, gx, gz)
	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId); if not plot then return nil end
	local powerFolder = plot:FindFirstChild("PowerLines");                         if not powerFolder then return nil end

	-- find the pole that occupies this exact cell
	local target, zoneFolder
	for _, zf in ipairs(powerFolder:GetChildren()) do
		for _, inst in ipairs(zf:GetChildren()) do
			if (inst:IsA("Model") or inst:IsA("BasePart"))
				and inst:GetAttribute("GridX") == gx
				and inst:GetAttribute("GridZ") == gz
				and (inst.Name == "PowerLines" or inst:GetAttribute("LineType"))
			then
				target, zoneFolder = inst, zf
				break
			end
		end
		if target then break end
	end
	if not target then return nil end

	local pZoneId = target:GetAttribute("ZoneId") or (zoneFolder and zoneFolder.Name)

	-- clear any ropes hanging off this pole (we will rebuild the whole span)
	for _, d in ipairs(target:GetDescendants()) do
		if d:IsA("RopeConstraint") then d:Destroy() end
	end

	-- tag so we can recognize the restored pole post-road-removal
	target:SetAttribute("SuppressedByRoadId", roadZoneId)

	-- store a clone so the road's LayerManager restore can put it back later
	LayerManagerModule.storeRemovedObject("PowerLines", roadZoneId, {
		instanceClone  = target:Clone(),
		originalParent = target.Parent,
		cframe         = (target:IsA("Model") and target:GetPivot() or target.CFrame),
	}, player)

	-- unmark power occupancy for this grid
	local occId = string.format("%s_power_%d_%d", tostring(pZoneId), gx, gz)
	ZoneTrackerModule.unmarkGridOccupied(player, gx, gz, "power", occId)

	-- remove the single conflicting pole
	target:Destroy()

	-- try an immediate targeted bridge across the just-removed cell
	_bridgeAcrossRoadGapAt(player, pZoneId, gx, gz)

	-- rope the span across the new road gap
	_queueRopeRebuild(player, pZoneId)

	-- NEW: recompute boxes for this power zone since a road just suppressed a pole on it
	PowerGeneratorModule.ensureOverlapBoxesForPowerZone(player, pZoneId)

	return pZoneId
end

---------------------------------------------------------------------
--  PUBLIC: rebuild ropes for one power zone by following its path segments.
--          We destroy all ropes in the zone and re-link consecutive *existing* poles.
---------------------------------------------------------------------
local function _gridSetFromList(list)
	local set = {}
	for _, c in ipairs(list or {}) do
		if c.x and c.z then set[c.x..","..c.z] = true end
	end
	return set
end

function PowerGeneratorModule.rebuildRopesForZone(player, powerZoneId)
	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId); if not plot then return end
	local powerFolder = plot:FindFirstChild("PowerLines");                         if not powerFolder then return end
	local zoneFolder  = powerFolder:FindFirstChild(powerZoneId);                   if not zoneFolder  then return end

	-- purge all ropes in this zone
	for _, d in ipairs(zoneFolder:GetDescendants()) do
		if d:IsA("RopeConstraint") then d:Destroy() end
	end

	-- get the recorded path for this line
	local net  = PowerLinePath.getLineNetworks()[powerZoneId] or PowerLinePath.getLineData(powerZoneId) or {}
	local segs = net.segments or net.pathCoords or {}
	if #segs == 0 then return end

	local function cx(seg) return seg.coord and seg.coord.x or seg.x end
	local function cz(seg) return seg.coord and seg.coord.z or seg.z end
	local occTypeCache = {}
	local function _getOccupantTypesCached(gx, gz)
		local k = tostring(gx)..","..tostring(gz)
		local cached = occTypeCache[k]
		if cached ~= nil then return cached end
		local types = ZoneTrackerModule.getGridOccupantTypes(player, gx, gz) or {}
		occTypeCache[k] = types
		return types
	end

	-- Manhattan adjacency (keep original intent when no gap)
	local function _manhattan1(ax, az, bx, bz)
		return (math.abs(ax - bx) + math.abs(az - bz)) == 1
	end

	-- Internal util from earlier in this module:
	--   _findPoleInZone(zoneFolder, gx, gz)
	--   hasAnyNonRoad(occupantTypes)
	--   isRoadCell(occupantTypes)
	-- are already defined above; we use them here.

	----------------------------------------------------------------------
	-- NEW: allow bridging across a run of ONLY road (or empty/excluded)
	--       between the last real pole and the next real pole.
	----------------------------------------------------------------------
	local function _canBridgeAcrossRoadOnly(lastIdx, currIdx)
		if not lastIdx or not currIdx or (currIdx - lastIdx) <= 1 then return false end
		for k = lastIdx + 1, currIdx - 1 do
			local seg = segs[k]; local gx, gz = cx(seg), cz(seg)
			if _findPoleInZone(zoneFolder, gx, gz) then return false end
			local types = _getOccupantTypesCached(gx, gz)
			if DEBUG_LOGS then
				local typeList = {}
				for k, v in pairs(types) do
					if v then
						table.insert(typeList, k)
					end
				end
				print(("gap %d,%d types: %s"):format(gx, gz, table.concat(typeList, ",")))
			end
			if hasAnyNonRoad(types) and not isRoadCell(types) then return false end
		end
		return true
	end

	-- Prevent last→first (loop) and any re-entrance into already-visited poles
	local visited = {}          -- key: "x,z" -> true
	local function key(x,z) return tostring(x)..","..tostring(z) end

	local lastPole        = nil
	local lastGX, lastGZ  = nil, nil
	local lastIdx         = nil

	for i, seg in ipairs(segs) do
		local gx, gz = cx(seg), cz(seg)
		local curr = _findPoleInZone(zoneFolder, gx, gz)

		if curr then
			local k = key(gx, gz)

			-- Skip linking into an already-visited pole (prevents wrap/dupes)
			if not visited[k] then
				local adjacent = (lastGX and _manhattan1(lastGX, lastGZ, gx, gz)) or false
				local canBridge = false

				-- If not adjacent, consider a bridge if the gap is ONLY road / empty / excluded
				if lastIdx and (not adjacent) then
					canBridge = _canBridgeAcrossRoadOnly(lastIdx, i)
				end

				if lastPole and (adjacent or canBridge) then
					-- linkPoles handles any heading and your attachment pairing logic
					linkPoles(lastPole, curr)
				end

				visited[k]   = true
				lastPole     = curr
				lastGX, lastGZ = gx, gz
				lastIdx      = i
			else
				-- Already visited: reset link source so we don't bridge across a loop re-entry
				lastPole, lastGX, lastGZ, lastIdx = curr, gx, gz, i
			end
		else
			-- Missing pole at this path cell → do nothing here; we may bridge over it later
		end
	end

	----------------------------------------------------------------------
	-- Re-attach boxes smartly (unchanged behavior, just rerun after ropes)
	----------------------------------------------------------------------
	local function _modelPos(m: Instance)
		return (m.PrimaryPart and m.PrimaryPart.Position) or m:GetPivot().Position
	end
	local function _nearestPoleModel(folder: Instance, fromPos: Vector3, maxDist: number)
		local best, bestModel = math.huge, nil
		for _, child in ipairs(folder:GetChildren()) do
			if _isPole(child) then
				local d = (_modelPos(child) - fromPos).Magnitude
				if d < best and d <= (maxDist or BOX_LINK_MAX_DISTANCE) then best, bestModel = d, child end
			end
		end
		return bestModel, best
	end

	local boxesByRun = {}
	local descCount = 0
	for _, inst in ipairs(zoneFolder:GetDescendants()) do
		if (inst:IsA("Model") or inst:IsA("BasePart")) and inst:GetAttribute("IsPowerRoadBox") == true then
			local rkey = inst:GetAttribute("RunKey")
			if rkey then
				boxesByRun[rkey] = boxesByRun[rkey] or {}
				table.insert(boxesByRun[rkey], inst)
			end
		end
		descCount += 1
		yieldEveryN(descCount, 200)
	end

	for _, pair in pairs(boxesByRun) do
		table.sort(pair, function(a, b)
			local _, da = _nearestPoleModel(zoneFolder, _modelPos(a), BOX_LINK_MAX_DISTANCE)
			local _, db = _nearestPoleModel(zoneFolder, _modelPos(b), BOX_LINK_MAX_DISTANCE)
			da, db = da or math.huge, db or math.huge
			return da < db
		end)
		for iBox, box in ipairs(pair) do
			if iBox == 1 then
				-- reuse the helper that pairs two attachments without criss-cross
				_connectBoxToNearestPole(zoneFolder, box)
				box:SetAttribute("IsPrimaryLinkEndpoint", true)
			else
				_detachAllRopesFromModel(box)
				box:SetAttribute("IsPrimaryLinkEndpoint", false)
			end
		end
	end

	----------------------------------------------------------------------
	-- NEW: Re-attach pad-poles that belong to this power zone
	--      (their ropes were purged by the zone rope clear above)
	----------------------------------------------------------------------
	do
		local populated = plot:FindFirstChild("Buildings") and plot.Buildings:FindFirstChild("Populated")
		if populated then
			local scanCount = 0
			for _, f in ipairs(populated:GetChildren()) do
				for _, inst in ipairs(f:GetDescendants()) do
					if (inst:IsA("Model") or inst:IsA("BasePart")) then
						local isPadPole = (inst.Name == "PadPole") or (inst:GetAttribute("IsPadPole") == true)
						if isPadPole and inst:GetAttribute("PowerLineZoneId") == powerZoneId then
							-- Recreate the two ropes from this pad-pole to the nearest pole in this power zone
							PowerGeneratorModule.connectPadPoleToPowerZone(player, inst)
						end
					end
					scanCount += 1
					yieldEveryN(scanCount, 250)
				end
			end
		end
	end
end

function PowerGeneratorModule.ensurePolesNearGridList(player, freedGridList)
	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId); if not plot then return end
	local terrain = plot:FindFirstChild("TestTerrain");                            if not terrain then return end

	local powerFolder = plot:FindFirstChild("PowerLines");                         if not powerFolder then return end
	local freed = _gridSetFromList(freedGridList)
	if not next(freed) then return end

	-- Resolve base prefab once
	local powerList = BuildingMasterList.getPowerLinesByStyle("Default") or {}
	local basePower
	for _, p in ipairs(powerList) do
		if (p.name or p.Name) == "PowerLines" then basePower = p; break end
	end
	if not basePower or not (basePower.stages and basePower.stages.Stage3) then return end

	-- For each power zone, check its recorded path and recreate on freed cells
	for _, zoneFolder in ipairs(powerFolder:GetChildren()) do
		if not zoneFolder:IsA("Folder") then continue end
		local powerZoneId = zoneFolder.Name

		local net  = PowerLinePath.getLineNetworks()[powerZoneId] or PowerLinePath.getLineData(powerZoneId) or {}
		local segs = net.segments or net.pathCoords or {}
		if #segs == 0 then continue end

		local function cx(seg) return (seg.coord and seg.coord.x) or seg.x end
		local function cz(seg) return (seg.coord and seg.coord.z) or seg.z end

		local function computeRot(gx, gz)
			for i, seg in ipairs(segs) do
				if cx(seg) == gx and cz(seg) == gz then
					local dir = seg.direction
					if dir == "End" and i > 1 then dir = segs[i-1].direction end
					return getRotationForDirection(dir)
				end
			end
			return 0
		end

		local didPlace = false

		for _, seg in ipairs(segs) do
			local gx, gz = cx(seg), cz(seg)
			if not freed[gx..","..gz] then continue end  -- only on just-freed cells

			-- Skip if a pole already exists here
			if _hasPoleInZone(zoneFolder, gx, gz) then continue end

			-- Still blocked by some non-road occupant? (don’t place)
			local types = ZoneTrackerModule.getGridOccupantTypes(player, gx, gz) or {}
			local blockedByNonRoad = false
			for k, v in pairs(types) do
				if v and k ~= "road" and k ~= "power" and not OverlapTypeExclusions[string.lower(k)] then
					blockedByNonRoad = true; break
				end
			end
			if blockedByNonRoad then continue end

			-- Place the pole
			local rotationY = computeRot(gx, gz)
			PowerGeneratorModule.generatePowerSegment(
				terrain, zoneFolder, player, powerZoneId, net.mode or "Default",
				{ x = gx, z = gz }, basePower, rotationY, nil
			)
			didPlace = true
		end

		if didPlace then
			PowerGeneratorModule.rebuildRopesForZone(player, powerZoneId)
		end
	end
end

function PowerGeneratorModule.refillAfterBuildingRemoval(player, freedGridList)
	return PowerGeneratorModule.ensurePolesNearGridList(player, freedGridList)
end

---------------------------------------------------------------------
--  PUBLIC: rebuild ropes for *all* power zones on the player's plot
---------------------------------------------------------------------
function PowerGeneratorModule.rebuildRopesForAll(player)
	local uid = player and player.UserId
	if not uid then return end
	if _rebuildAllInProgress[uid] then
		_rebuildAllPending[uid] = true
		return
	end
	_rebuildAllInProgress[uid] = true

	repeat
		_rebuildAllPending[uid] = nil

		local plot = Workspace.PlayerPlots:FindFirstChild("Plot_"..uid); if not plot then break end
		local powerFolder = plot:FindFirstChild("PowerLines");           if not powerFolder then break end
		if _hasPopulatingBuildingZone(player) then
			_pendingRebuildAfterBuildings[uid] = true
			break
		end
		_pendingRebuildAfterBuildings[uid] = nil
		for _, zf in ipairs(powerFolder:GetChildren()) do
			if zf:IsA("Folder") then
				local zid = zf.Name
				PowerGeneratorModule.rebuildRopesForZone(player, zid)
			end
		end
	until not _rebuildAllPending[uid]

	_rebuildAllInProgress[uid] = nil
end

---------------------------------------------------------------------
--  PUBLIC: after a road zone is removed and the LayerManager has restored
--          its suppressed power poles, re-mark occupancy and rebuild ropes
--          only for the affected power zones.
---------------------------------------------------------------------
function PowerGeneratorModule.reviveSuppressedPolesForRoad(player, roadZoneId)
	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId); if not plot then return end
	local powerFolder = plot:FindFirstChild("PowerLines");                         if not powerFolder then return end

	local touched = {}
	local scanned = 0
	for _, inst in ipairs(powerFolder:GetDescendants()) do
		if (inst:IsA("Model") or inst:IsA("BasePart"))
			and inst:GetAttribute("SuppressedByRoadId") == roadZoneId
		then
			local gx, gz  = inst:GetAttribute("GridX"),  inst:GetAttribute("GridZ")
			local pzid    = inst:GetAttribute("ZoneId")
			if gx and gz and pzid then
				local occId = string.format("%s_power_%d_%d", tostring(pzid), gx, gz)
				ZoneTrackerModule.markGridOccupied(player, gx, gz, "power", occId, inst:GetAttribute("LineType") or "Default")
				inst:SetAttribute("SuppressedByRoadId", nil)
				touched[pzid] = true
			end
		end
		scanned += 1
		yieldEveryN(scanned, 200)
	end

	for zid in pairs(touched) do
		PowerGeneratorModule.rebuildRopesForZone(player, zid)
	end

	-- NEW: after roads have been removed and poles revived, recompute boxes globally
	PowerGeneratorModule.ensureOverlapBoxesForAll(player)
end

---------------------------------------------------------------------
--  Cleanup function (zone removed)
---------------------------------------------------------------------
function PowerGeneratorModule.removeLines(player, zoneId)
	local playerPlot  = Workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId); if not playerPlot then return end
	local powerFolder = playerPlot:FindFirstChild("PowerLines");                         if not powerFolder then return end
	local zoneFolder  = powerFolder:FindFirstChild(zoneId);                              if not zoneFolder  then return end

	-- Remove poles/boxes in this power zone folder (existing behavior)
	for _, child in ipairs(zoneFolder:GetChildren()) do
		if (child:IsA("Model") or child:IsA("BasePart")) and child:GetAttribute("ZoneId") == zoneId then
			-- Unmark occupancy if this pole carried GridX/GridZ
			local gx = tonumber(child:GetAttribute("GridX"))
			local gz = tonumber(child:GetAttribute("GridZ"))
			if gx and gz then
				local occId = string.format("%s_power_%d_%d", zoneId, gx, gz)
				ZoneTrackerModule.unmarkGridOccupied(player, gx, gz, "power", occId)
			end
			child:Destroy()
		end
	end
	if #zoneFolder:GetChildren() == 0 then zoneFolder:Destroy() end

	---------------------------------------------------------------------
	-- NEW: also remove any PadPoles under Buildings/Populated that were
	--      stamped with PowerLineZoneId == this zoneId
	---------------------------------------------------------------------
	do
		local bFolder = playerPlot:FindFirstChild("Buildings")
		local populated = bFolder and bFolder:FindFirstChild("Populated") or nil
		if populated then
			local removed = 0
			for _, f in ipairs(populated:GetChildren()) do
				for _, inst in ipairs(f:GetDescendants()) do
					if (inst:IsA("Model") or inst:IsA("BasePart")) then
						local isPadPole = (inst.Name == "PadPole") or (inst:GetAttribute("IsPadPole") == true)
						if isPadPole and inst:GetAttribute("PowerLineZoneId") == zoneId then
							inst:Destroy()
							removed += 1
						end
					end
				end
			end
			if DEBUG_LOGS then
				print(("[PowerGeneratorModule] Removed %d PadPoles tagged to power zone %s"):format(removed, tostring(zoneId)))
			end
		end
	end

	debugPrint("Removed power lines for zone:", zoneId)
	linesRemovedEvent:Fire(player, zoneId)
end

-- Hook: when a pad pole appears, bridge it to its owning power zone (if tagged)
local _hookedPadPole = false
if not _hookedPadPole then
	_hookedPadPole = true
	PadPoleSpawned.Event:Connect(function(player, padPole)
		if not (player and padPole) then return end

		-- Preferred path: targeted link into the correct power line zone
		if padPole:GetAttribute("PowerLineZoneId") then
			PowerGeneratorModule.connectPadPoleToPowerZone(player, padPole)
			return
		end

		-- Legacy fallback: optional global nearest-bridge if you ever spawn an untagged pole
		if BRIDGE_TO_NEAREST_PADPOLE then
			local plot = Workspace.PlayerPlots:FindFirstChild("Plot_"..player.UserId)
			if plot then bridgePadPoleToNearestLine(plot, padPole) end
		end
	end)
end

-- Hook: when any zone populates and it’s a road-type, refresh overlap boxes
local _hookedRoadOverlap = false
if not _hookedRoadOverlap then
	_hookedRoadOverlap = true
	zonePopulatedEvent.Event:Connect(function(player, zoneId, _payload)
		local z = ZoneTrackerModule.getZoneById(player, zoneId)
		local mode = z and z.mode

		if z and _isBuildingMode(mode) then
			_drainQueuedPadPoleLinks(player, zoneId)
			if _pendingRebuildAfterBuildings[player.UserId] and (not _hasPopulatingBuildingZone(player)) then
				PowerGeneratorModule.rebuildRopesForAll(player)
			end
		end

		if mode == "DirtRoad" or mode == "Pavement" or mode == "Highway" or mode == "Road" then
			-- NEW: after the road zone is fully placed, do one authoritative pass
			PowerGeneratorModule.rebuildRopesForAll(player)
			PowerGeneratorModule.ensureOverlapBoxesForAll(player)
		end
	end)
end

return PowerGeneratorModule
