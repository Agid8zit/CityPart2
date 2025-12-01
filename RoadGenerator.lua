-- RoadGeneratorModule.lua
local RoadGeneratorModule = {}
RoadGeneratorModule.__index = RoadGeneratorModule

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BE = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents")
local zonePopulatedEvent = BE:WaitForChild("ZonePopulated")
local roadsPlacedEvent   = BE:WaitForChild("BuildingsPlaced")

local QuadtreeService = require(ReplicatedStorage.Scripts.Optimize.Quadtree.QuadTreeSvc)

local S3      	= game:GetService("ServerScriptService")
local Build    	= S3:WaitForChild("Build")
local Zones    	= Build:WaitForChild("Zones")
local CC 	   	= Zones:WaitForChild("CoreConcepts")
local Districts = CC:WaitForChild("Districts")
local BG		=Districts:WaitForChild("Building Gen")
local BuildingGeneratorModule = require(BG:WaitForChild("BuildingGenerator"))
local ZoneMgr  	= Zones:WaitForChild("ZoneManager")
local ZoneTrackerModule = require(ZoneMgr:WaitForChild("ZoneTracker"))

local Transport = Build:WaitForChild("Transport")
local Roads     = Transport:WaitForChild("Roads")
local RoadsCore = Roads:WaitForChild("CoreConcepts")
local Pathing   = RoadsCore:WaitForChild("Pathing")

local GridConf   = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Grid")
local GridUtils  = require(GridConf:WaitForChild("GridUtil"))
local GridConfig = require(GridConf:WaitForChild("GridConfig"))

local BuildingManager    = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("BuildingManager")
local BuildingMasterList = require(BuildingManager:WaitForChild("BuildingMasterList"))

local PathingModule = require(Pathing:WaitForChild("PathingModule"))
local PowerGen = CC:WaitForChild("PowerGen")
local PowerGeneratorModule2 = require(PowerGen:WaitForChild("PowerGenerator"))

-- NEW: External Layer Manager (adjust path as needed)
local LayerManagerModule = require(Build.LayerManager)

-- Debug toggles
local DEBUG_LOGS          = false
local DEBUG_ROAD_ROTATION = false

local GRID_SIZE      = GridConfig.GRID_SIZE
local BUILD_INTERVAL = 0.1
local Y_OFFSET       = 0.625
local SEARCH_RADIUS  = 4 
local INTERSECTION_RESCAN_RADIUS = 8  -- how far around a newly placed cell we re-evaluate intersections

local function debugPrint(...)
	if DEBUG_LOGS then
		print("[RoadGeneratorModule]", ...)
	end
end

local ENTRY_HINTS = {
	["0,0"] = { up = true },  -- This is ONLY for the origin to make it aesthetically pleasing to connect to highway
}

-- This is ONLY for the origin to make it aesthetically pleasing to connect to highway
local function applyEntryHints(flags, cell)
	-- flags is a table like {up=?,down=?,left=?,right=?}
	if not cell or not flags then return end
	local key = string.format("%d,%d", cell.x, cell.z)
	local hint = ENTRY_HINTS[key]
	if hint then
		-- Only ever turn neighbors on; never force them off.
		if hint.up    then flags.up    = true end
		if hint.down  then flags.down  = true end
		if hint.left  then flags.left  = true end
		if hint.right then flags.right = true end
	end
end

local HALF_GRID = Vector3.new(GRID_SIZE * 0.5, 0, GRID_SIZE * 0.5)

local SUPPRESSIBLE = {
	Residential = true, Commercial = true, Industrial = true,
	ResDense    = true, CommDense   = true, IndusDense   = true,
}

local boundsCache = {}

local PREFER_STORED_STRAIGHT_YAW = true
local DEBUG_INTER_ROT = false              -- prints for intersection/yaw decisions

local function norm360(d) d = d % 360; if d < 0 then d = d + 360 end; return d end

local function degForDir(dir)
	local da = PathingModule.directionAngles
	if type(da) == "table" and type(da[dir]) == "number" then return norm360(da[dir]) end
	local fallback = { East = 0, South = 90, West = 180, North = 270 }
	return fallback[dir] or 0
end

local ASSET_YAW_OFFSETS = { Road = 0, Bridge = 0, Turn = 0, ["3Way"]=0, ["4Way"]=0 }
local function withAssetOffset(name, yaw)
	return norm360((yaw or 0) + (ASSET_YAW_OFFSETS[name] or 0))
end

-- 180° symmetric => straight pieces look same either way
local function isColinear(y1, y2)
	if not y1 or not y2 then return false end
	local d = math.abs((y1 - y2) % 360)
	d = math.min(d, 360 - d)
	return (d < 1.0) or (math.abs(d - 180) < 1.0)
end

local function dprint(...)
	if DEBUG_INTER_ROT then
		print("[RoadRotate]", ...)
	end
end


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

-- Overlapping-object removal now uses the layer manager
local function removeOverlappingObjects(player, zoneId, roadPos, gridCoord)
	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_" .. player.UserId)
	if not plot then return end

	-- Local helper: store + destroy items from a given folder & objectType
	local function storeAndDestroy(folderName, objectType)
		local folder = plot:FindFirstChild(folderName)
		if not folder then return end
		for _, item in ipairs(folder:GetDescendants()) do
			if folderName == "Buildings" then
				-- suppress any building (including multi‑cell) whose footprint covers this road cell
				if item:IsA("Model") or item:IsA("BasePart") then
					local gx   = item:GetAttribute("GridX")
					local gz   = item:GetAttribute("GridZ")
					local rotY = item:GetAttribute("RotationY") or 0
					local bnm  = item:GetAttribute("BuildingName")
					local origZoneId = item:GetAttribute("ZoneId")

					if gx and gz and bnm and origZoneId and origZoneId ~= zoneId then
						local zd   = ZoneTrackerModule.getZoneById(player, origZoneId)
						local mode = zd and zd.mode or nil
						if mode and SUPPRESSIBLE[mode] then
							local w, d = 1, 1
							if BuildingGeneratorModule and BuildingGeneratorModule._stage3FootprintCells then
								w, d = BuildingGeneratorModule._stage3FootprintCells(bnm, rotY)
							end

							-- Does the road cell land inside the building’s footprint?
							if gridCoord.x >= gx and gridCoord.x < gx + w
								and gridCoord.z >= gz and gridCoord.z < gz + d
							then
								local occId = ("%s_%d_%d"):format(origZoneId, gx, gz)
								local cf = (item:IsA("Model") and item:GetPivot()) or item.CFrame

								-- Archive full metadata so we can restore the instance and occupancy exactly
								LayerManagerModule.storeRemovedObject(objectType, zoneId, {
									instanceClone  = item:Clone(),
									originalParent = item.Parent,
									parentName     = item.Parent and item.Parent.Name or nil,
									cframe         = cf,
									gridX          = gx,
									gridZ          = gz,
									rotation       = rotY,
									wealthState    = item:GetAttribute("WealthState"),
									isUtility      = item:GetAttribute("IsUtility") or false,
									occupantType   = "building",
									occupantId     = occId,
									mode           = mode,
									zoneId         = origZoneId,
								}, player)

								-- Clear occupancy & quadtree for the entire footprint
								for x = gx, gx + w - 1 do
									for z = gz, gz + d - 1 do
										ZoneTrackerModule.unmarkGridOccupied(player, x, z, "building", occId)
									end
								end
								if QuadtreeService and typeof(QuadtreeService.removeById) == "function" then
									pcall(function() QuadtreeService:removeById(occId) end)
								end

								-- Remove the instance
								item:Destroy()

								-- If we suppressed a multi‑cell, back‑fill that zone’s now‑empty gaps
								if (w * d) > 1 and BuildingGeneratorModule and BuildingGeneratorModule._refillZoneGaps then
									task.defer(function()
										-- Pass the road zoneId so new fillers are tagged as RefilledBy=<roadZoneId>
										BuildingGeneratorModule._refillZoneGaps(player, origZoneId, mode, nil, nil, nil, zoneId)
									end)
								end
							end
						end
					end
				end

			else
				-- NatureZones: do a tight AABB check in X/Z only
				local itemCF, itemSize
				if item:IsA("Model") then
					itemCF, itemSize = item:GetBoundingBox()
				elseif item:IsA("BasePart") then
					itemCF, itemSize = item.CFrame, item.Size
				else
					continue
				end

				local halfItem = itemSize * 0.5
				if math.abs(roadPos.X - itemCF.Position.X) <= (HALF_GRID.X + halfItem.X)
					and math.abs(roadPos.Z - itemCF.Position.Z) <= (HALF_GRID.Z + halfItem.Z)
				then
					LayerManagerModule.storeRemovedObject(objectType, zoneId, {
						instanceClone  = item:Clone(),
						originalParent = item.Parent,
						cframe         = itemCF,
					}, player)
					item:Destroy()
				end
			end
		end
	end
	
	
	-- Instead of local tables, store items via layer manager
	storeAndDestroy("Buildings",   "Buildings")
	storeAndDestroy("NatureZones", "NatureZones")
	if PowerGeneratorModule2 and PowerGeneratorModule2.suppressPoleForRoad then
		PowerGeneratorModule2.suppressPoleForRoad(player, zoneId, gridCoord.x, gridCoord.z)
	end
end


local function logPartBelow(part : BasePart)
	-- Cast from just below the road’s bottom face
	local origin    = part.Position - Vector3.new(0, part.Size.Y * 0.5 + 0.05, 0)
	local direction = Vector3.new(0, -100, 0)

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { part }          -- ignore the road itself
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = false

	local result = workspace:Raycast(origin, direction, params)
	if not result then
		debugPrint("[Road‑Diag] Nothing under part – hit the void")
		return
	end

	local hit      = result.Instance
	local material = result.Material         -- <- voxel / part material
	local matName  = material and material.Name or "Unknown"

	-- 1) Terrain water ‑ the most common case
	if hit:IsA("Terrain") and material == Enum.Material.Water then
		debugPrint("[Road‑Diag] Road is directly over WATER (terrain voxel)")
		return
	end

	-- 2) Separate water parts (e.g. a transparent Part with Material = Water)
	if not hit:IsA("Terrain") and hit.Material == Enum.Material.Water then
		debugPrint(("[Road‑Diag] Road is directly over WATER part «%s» (%s)")
			:format(hit.Name, hit.Parent and hit.Parent.Name or "no parent"))
		return
	end

	-- 3) Anything else
	debugPrint(("[Road‑Diag] Road is directly over «%s» (%s) — material = %s")
		:format(hit.Name, hit.Parent and hit.Parent.Name or "no parent", matName))
end

local function getSupportTypeForCell(part : BasePart)
	-- Same ray spec you already use
	local origin    = part.Position - Vector3.new(0, part.Size.Y*0.5 + 0.05, 0)
	local direction = Vector3.new(0, -100, 0)

	local p = RaycastParams.new()
	p.FilterDescendantsInstances = { part }
	p.FilterType  = Enum.RaycastFilterType.Exclude
	p.IgnoreWater = false

	local hit = workspace:Raycast(origin, direction, p)
	if not hit then      return "Void" end

	-- Mesh cliffs live in folders called “Cliffs” (adjust as needed)
	local inst = hit.Instance
	if inst:IsA("MeshPart") or inst:IsA("Part") then
		if (inst.Name:lower():find("cliff") or
			(inst.Parent and inst.Parent.Name:lower():find("cliff"))) then
			return "Cliff"
		end
		if inst.Material == Enum.Material.Water then
			return "Water"
		end
		return "Land"
	end

	-- Terrain voxel
	if hit.Material == Enum.Material.Water then
		return "Water"
	else
		return "Land"
	end
end

--Ohaiyo gozaimasu! Genkideska?


local function getBuildingZonesNearCell(player, cx, cz, radius)
	local results = {}
	local allZones = ZoneTrackerModule.getAllZones(player)

	debugPrint("getBuildingZonesNearCell: checking all zones for building zones near (",
		cx, cz, ") radius=", radius, " total zones=", (allZones and #allZones or "<table>"))

	for zoneId, data in pairs(allZones) do
		-- If you want to skip roads or certain zone types, do that check here:
		if data.mode ~= "DirtRoad" then
			-- Now let's see if any cell is within radius
			for _, cell in ipairs(data.gridList or {}) do
				local dx = cell.x - cx
				local dz = cell.z - cz
				if (dx*dx + dz*dz) <= (radius * radius) then
					debugPrint("  -> Found building zone", zoneId, 
						"within radius at cell (", cell.x, cell.z, ")")
					table.insert(results, {
						zoneId   = zoneId,
						gridList = data.gridList,
					})
					break
				end
			end
		end
	end
	debugPrint("getBuildingZonesNearCell: found", #results, "zones near (",cx,cz,")")
	return results
end


-- 2) Find the specific building Instance at (gridX, gridZ) for a given zoneId.
--    Assumes buildings live in "Buildings/Populated/ZoneId" or "Utilities"
local function findBuildingInstanceAtCell(player, zoneId, gridX, gridZ)
	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_" .. player.UserId)
	if not plot then
		debugPrint("findBuildingInstanceAtCell: No plot for player", player.Name)
		return nil
	end

	local buildingsFolder = plot:FindFirstChild("Buildings")
	if not buildingsFolder then
		debugPrint("findBuildingInstanceAtCell: No 'Buildings' folder under plot")
		return nil
	end

	local populatedFolder = buildingsFolder:FindFirstChild("Populated")
	if not populatedFolder then
		debugPrint("findBuildingInstanceAtCell: No 'Populated' folder under 'Buildings'")
		return nil
	end

	local foldersToCheck = {
		populatedFolder:FindFirstChild(zoneId),
		populatedFolder:FindFirstChild("Utilities"),
	}

	for _, folder in ipairs(foldersToCheck) do
		if folder then
			for _, child in ipairs(folder:GetChildren()) do
				if (child:IsA("Model") or child:IsA("BasePart"))
					and child:GetAttribute("ZoneId") == zoneId
					and child:GetAttribute("GridX") == gridX
					and child:GetAttribute("GridZ") == gridZ
				then
					debugPrint(("findBuildingInstanceAtCell: Found building in folder '%s' => %s")
						:format(folder.Name, child.Name))
					return child
				end
			end
		end
	end

	debugPrint("findBuildingInstanceAtCell: No building found for zone=", zoneId,
		"at cell=", gridX, gridZ)
	return nil
end


-- 3) Find the closest road cell to (gx, gz) within 'radius'
local function getClosestRoadCell(player, gx, gz, radius)
	local allZones = ZoneTrackerModule.getAllZones(player)
	local bestDist = math.huge
	local bestCell = nil

	for zoneId, data in pairs(allZones) do
		if data.mode == "DirtRoad" then
			for _, rCell in ipairs(data.gridList or {}) do
				local dx = rCell.x - gx
				local dz = rCell.z - gz
				local dist = dx*dx + dz*dz
				if dist <= (radius * radius) and dist < bestDist then
					bestDist = dist
					bestCell = rCell
				end
			end
		end
	end

	if bestCell then
		debugPrint("getClosestRoadCell: Found nearest road cell at (",
			bestCell.x, bestCell.z, ") for building cell=", gx, gz)
		return bestCell, math.sqrt(bestDist)
	end

	debugPrint("getClosestRoadCell: No road found within radius for building cell=",
		gx, gz, " radius=", radius)
	return nil, nil
end

-- 4) Convert grid coords to world space, using the player's terrain as reference
local function convertGridToWorld(player, gx, gz)
	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_" .. player.UserId)
	if not plot then return Vector3.zero end

	local gb, terrains = getGlobalBoundsForPlot(plot)
	local wx, wy, wz = GridUtils.globalGridToWorldPosition(gx, gz, gb, terrains)

	-- hover a hair above the surface, like the old script did
	return Vector3.new(wx, 1.025, wz)   
end

local function _plotAxisDirs(player)
	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_" .. player.UserId)
	if not plot then
		return 1, 1
	end

	-- Prefer the GridConfig context (mirrors BuildingGenerator axis handling)
	local ax, az = GridConfig.getAxisDirectionsForPlot(plot)

	-- Fallback to attributes if the context was never seeded for this plot
	if ax ~= 1 and ax ~= -1 then
		ax = plot:GetAttribute("GridAxisDirX")
	end
	if az ~= 1 and az ~= -1 then
		az = plot:GetAttribute("GridAxisDirZ")
	end

	-- Last resort: derive from any terrain instance (matches BuildingGenerator fallback)
	if (ax ~= -1 and ax ~= 1) or (az ~= -1 and az ~= 1) then
		local _, terrains = getGlobalBoundsForPlot(plot)
		for _, inst in ipairs(terrains or {}) do
			if typeof(inst) == "Instance" then
				ax, az = GridConfig.getAxisDirectionsForInstance(inst)
				break
			end
		end
	end

	-- Normalize to either -1 or +1
	if ax ~= -1 then ax = 1 end
	if az ~= -1 then az = 1 end
	return ax, az
end

-- Axis-aware yaw adjustment: mirror yaw when plot axes are flipped (even plots)
local function _adjustYawForAxis(yaw, axisDirX, axisDirZ)
	yaw = norm360(yaw or 0)
	if axisDirX == -1 then
		yaw = 180 - yaw
	end
	if axisDirZ == -1 then
		yaw = -yaw
	end
	return norm360(yaw)
end

local function _normalizeLegacyList(entries, axisDir, field)
	if axisDir ~= -1 then
		return false
	end
	if type(entries) ~= "table" then
		return false
	end

	for _, rec in ipairs(entries) do
		local value = rec[field]
		if type(value) == "number" and value > 0 then
			for _, mutate in ipairs(entries) do
				local current = mutate[field]
				if type(current) == "number" then
					mutate[field] = -current
				end
			end
			return true
		end
	end

	return false
end

local function normalizeLegacyEvenPlotData(player, gridList, saved)
	-- New-format snapshots already store logical, parity-normalized coords; don't flip them.
	if type(saved) == "table" and saved.version ~= nil then
		return
	end

	local axisDirX, axisDirZ = _plotAxisDirs(player)

	_normalizeLegacyList(gridList, axisDirX, "x")
	_normalizeLegacyList(gridList, axisDirZ, "z")

	if type(saved) ~= "table" then
		return
	end

	if saved.segments then
		_normalizeLegacyList(saved.segments, axisDirX, "gridX")
		_normalizeLegacyList(saved.segments, axisDirZ, "gridZ")
	end
	if saved.interDecos then
		_normalizeLegacyList(saved.interDecos, axisDirX, "gridX")
		_normalizeLegacyList(saved.interDecos, axisDirZ, "gridZ")
	end
	if saved.strDecos then
		_normalizeLegacyList(saved.strDecos, axisDirX, "gridX")
		_normalizeLegacyList(saved.strDecos, axisDirZ, "gridZ")
	end

	if saved.segments == nil and #saved > 0 and saved[1] and saved[1].gridX ~= nil then
		_normalizeLegacyList(saved, axisDirX, "gridX")
		_normalizeLegacyList(saved, axisDirZ, "gridZ")
	end
end

local function refreshRoadStartTransparency(player)
	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_" .. player.UserId)
	if not plot then return end

	local roadsFolder = plot:FindFirstChild("Roads")
	local hasRoadAtOrigin = false
	if roadsFolder then
		for _, obj in ipairs(roadsFolder:GetDescendants()) do
			if (obj:IsA("Model") or obj:IsA("BasePart"))
				and obj:GetAttribute("IsRoadDecoration") ~= true
				and obj:GetAttribute("GridX") == 0
				and obj:GetAttribute("GridZ") == 0
			then
				hasRoadAtOrigin = true
				break
			end
		end
	end

	local rs = plot:FindFirstChild("RoadStart", true)
	if not rs then return end
	local alpha = hasRoadAtOrigin and 1 or 0.8
	if rs:IsA("BasePart") then
		rs.Transparency = alpha
	else
		for _, d in ipairs(rs:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Transparency = alpha
			end
		end
	end
end

--Recreate
local _SnapshotStore = {}
local function _store(uid) _SnapshotStore[uid] = _SnapshotStore[uid] or {}; return _SnapshotStore[uid] end

function RoadGeneratorModule.saveSnapshot(player, zoneId, snapshot)
	_store(player.UserId)[zoneId] = snapshot
end
function RoadGeneratorModule.getSnapshot(player, zoneId)
	return _store(player.UserId)[zoneId]
end
function RoadGeneratorModule.clearSnapshot(player, zoneId)
	_store(player.UserId)[zoneId] = nil
end

local function _keyXZ(x,z) return string.format("%d,%d", x, z) end
local function _yawDeg(cf) local _,y,_=cf:ToEulerAnglesYXZ(); y=math.deg(y); if y~=y then y=0 end; return y end
local function _localCF(baseCF, worldCF) return baseCF:ToObjectSpace(worldCF) end
local function _applyLocal(baseCF, localCF) return baseCF * localCF end
local function _baseCellCF(player, gx, gz, yawDeg)
	local pos = convertGridToWorld(player, gx, gz)
	return CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg or 0), 0)
end

--------------------------------------------------------------------------------
-- updateNearbyBuildingsOrientation
--------------------------------------------------------------------------------
function RoadGeneratorModule.updateNearbyBuildingsOrientation(player, changedRoadCells: {any})
	debugPrint("updateNearbyBuildingsOrientation: Start. #changedRoadCells=", #changedRoadCells)

	local buildingRadius = SEARCH_RADIUS
	for _, roadCell in ipairs(changedRoadCells) do
		debugPrint("  Checking near roadCell (", roadCell.x, ",", roadCell.z, ")")

		local buildingZones = getBuildingZonesNearCell(player, roadCell.x, roadCell.z, buildingRadius)
		for _, bZone in ipairs(buildingZones) do
			local zoneData = ZoneTrackerModule.getZoneById(player, bZone.zoneId)
			if not zoneData then
				debugPrint("    No zoneData found for zoneId=", bZone.zoneId)
			else
				debugPrint(("    Scanning building zone '%s' with %d cells")
					:format(bZone.zoneId, #zoneData.gridList))
				for _, bCell in ipairs(zoneData.gridList) do
					-- If bCell is within radius of the changed road cell
					local dx = bCell.x - roadCell.x
					local dz = bCell.z - roadCell.z
					local distSq = dx*dx + dz*dz
					if distSq <= (buildingRadius * buildingRadius) then
						debugPrint(("      --> building cell (%d,%d) is within distance^2=%d")
							:format(bCell.x, bCell.z, distSq))

						local buildingInstance = findBuildingInstanceAtCell(
							player, bZone.zoneId, bCell.x, bCell.z
						)
						if buildingInstance then
							debugPrint("         Found building instance", buildingInstance.Name,
								"-> Checking roads around it...")
							local nearestRoadCell, _ = getClosestRoadCell(
								player, bCell.x, bCell.z, buildingRadius
							)
							if nearestRoadCell then
								local roadWorldPos = convertGridToWorld(player,
									nearestRoadCell.x, nearestRoadCell.z)
								debugPrint("            --> orienting building to face (",
									nearestRoadCell.x, nearestRoadCell.z, ") in worldSpace=", roadWorldPos)
								BuildingGeneratorModule.orientBuildingToward(
									buildingInstance, roadWorldPos
								)
							else
								debugPrint("            --> No road found in range. Reverting orientation.")
								BuildingGeneratorModule.revertBuildingOrientation(buildingInstance)
							end
						end
					end
				end
			end
		end
	end

	debugPrint("updateNearbyBuildingsOrientation: Done.")
end



-- SINGLE ROAD SEGMENT PLACEMENT
function RoadGeneratorModule.generateRoadSegment(
	terrain,
	parentFolder,
	player,
	zoneId,
	mode,
	gridCoord,
	roadData,
	rotationY,
	onPlaced
)
	rotationY = rotationY or 0

	----------------------------------------------------------------------
	-- Helpers (safe fallbacks if you didn't add the globals earlier)
	----------------------------------------------------------------------
	local function _norm360(d) d = d % 360; if d < 0 then d = d + 360 end; return d end
	-- If you've declared `withAssetOffset(name, yaw)` globally, use it; otherwise no-op
	local function _applyAssetOffset(assetName, yaw)
		if type(withAssetOffset) == "function" then
			return _norm360(withAssetOffset(assetName, yaw))
		end
		return _norm360(yaw or 0)
	end
	local function _dprint(...)
		if DEBUG_LOGS or DEBUG_ROAD_ROTATION then
			print("[RoadGenerator] ", ...)
		end
	end

	local finalPosition = convertGridToWorld(player, gridCoord.x, gridCoord.z)
	removeOverlappingObjects(player, zoneId, finalPosition, gridCoord)
	local actualInstance = roadData.stages and roadData.stages.Stage3
	if not actualInstance then
		warn("generateRoadSegment: 'Stage3' missing for", roadData.name or "<unknown>")
		return
	end

	local assetName = roadData.name or roadData.Name or "Road"
	local yawApplied = _applyAssetOffset(assetName, rotationY)

	if DEBUG_ROAD_ROTATION then
		_dprint(string.format(
			"generateRoadSegment => Placing '%s' at grid (%d,%d), reqYaw=%.1f, yawApplied=%d",
			assetName, gridCoord.x, gridCoord.z, rotationY, yawApplied
			))
	end

	----------------------------------------------------------------------
	-- Create / position the instance
	----------------------------------------------------------------------
	local roadClone
	if actualInstance:IsA("Model") then
		roadClone = actualInstance:Clone()
		roadClone.Name = "Road"

		if roadClone.PrimaryPart then
			roadClone:SetPrimaryPartCFrame(
				CFrame.new(finalPosition) * CFrame.Angles(0, math.rad(yawApplied), 0)
			)
		else
			local ref = actualInstance.PrimaryPart
			if ref then
				for _, part in ipairs(roadClone:GetDescendants()) do
					if part:IsA("BasePart") then
						local offset = part.Position - ref.Position
						part.CFrame = CFrame.new(finalPosition + offset)
							* CFrame.Angles(0, math.rad(yawApplied), 0)
					end
				end
			else
				warn("No PrimaryPart found; manual offset logic may fail if model pieces vary.")
			end
		end

	else
		-- BasePart
		roadClone = actualInstance:Clone()
		roadClone.Name = "Road"
		roadClone.Position    = finalPosition
		roadClone.Orientation = Vector3.new(0, yawApplied, 0)
	end

	----------------------------------------------------------------------
	-- Diagnostics: what is under this piece?
	----------------------------------------------------------------------
	if DEBUG_LOGS then
		local probePart = (roadClone:IsA("Model") and roadClone.PrimaryPart)
			or (roadClone:IsA("BasePart") and roadClone)
		if probePart then
			logPartBelow(probePart)
		else
			_dprint("logPartBelow: no suitable BasePart to probe")
		end
	end

	----------------------------------------------------------------------
	-- Optimisation flags
	----------------------------------------------------------------------
	for _, part in ipairs(roadClone:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanQuery = false
		end
	end
	if roadClone:IsA("BasePart") then
		roadClone.CanQuery = false
	end

	----------------------------------------------------------------------
	-- Attributes + parenting
	----------------------------------------------------------------------
	roadClone.Parent = parentFolder
	roadClone:SetAttribute("ZoneId", zoneId)
	roadClone:SetAttribute("RoadType", mode)
	roadClone:SetAttribute("GridX", gridCoord.x)
	roadClone:SetAttribute("GridZ", gridCoord.z)
	roadClone:SetAttribute("TimePlaced", os.clock())
	roadClone:SetAttribute("YawBuilt", yawApplied)  -- <<< STICKY yaw
	
	-- if we just placed at (0,0), update the RoadStart transparency
	if gridCoord.x == 0 and gridCoord.z == 0 then
		refreshRoadStartTransparency(player)
	end

	_dprint(string.format(
		"Placed %s :: zone=%s cell=(%d,%d) yawBuilt=%d",
		assetName, tostring(zoneId), gridCoord.x, gridCoord.z, yawApplied
		))

	----------------------------------------------------------------------
	-- Occupancy + quadtree
	----------------------------------------------------------------------
	local occupantId = ("%s_road_%d_%d"):format(zoneId, gridCoord.x, gridCoord.z)
	ZoneTrackerModule.markGridOccupied(player, gridCoord.x, gridCoord.z, "road", occupantId, mode)

	QuadtreeService:insert({
		x = gridCoord.x,
		y = gridCoord.z,
		width = 1,
		height = 1,
		roadId = occupantId
	})

	if onPlaced then
		onPlaced()
	end
end



-- getIntersectionRotation
function RoadGeneratorModule.getIntersectionRotation(cellCoord, classification, ownerId)
	-- --- safe local helpers (don’t collide with any globals you may already have)
	local function _norm360(d) d = (d or 0) % 360; if d < 0 then d = d + 360 end; return d end
	local function _iprint(...)
		if DEBUG_LOGS or DEBUG_ROAD_ROTATION then
			print("[getIntersectionRotation]", ...)
		end
	end

	-- Resolve neighbor keys
	local neighbors = {
		up    = PathingModule.nodeKey({ x = cellCoord.x,   z = cellCoord.z - 1 }),
		down  = PathingModule.nodeKey({ x = cellCoord.x,   z = cellCoord.z + 1 }),
		left  = PathingModule.nodeKey({ x = cellCoord.x-1, z = cellCoord.z     }),
		right = PathingModule.nodeKey({ x = cellCoord.x+1, z = cellCoord.z     }),
	}

	local adjacency = PathingModule.getAdjacencyForOwner(ownerId) or PathingModule.globalAdjacency
	if not adjacency then
		warn("getIntersectionRotation: adjacency data not found!")
		return 0
	end

	local cellKey      = PathingModule.nodeKey(cellCoord)
	local neighborKeys = adjacency[cellKey] or {}

	local flags = {
		up    = table.find(neighborKeys, neighbors.up)    ~= nil,
		down  = table.find(neighborKeys, neighbors.down)  ~= nil,
		left  = table.find(neighborKeys, neighbors.left)  ~= nil,
		right = table.find(neighborKeys, neighbors.right) ~= nil,
	}
	applyEntryHints(flags, cellCoord) -- FIX: respect origin hint even when using adjacency
	local up, down, left, right = flags.up, flags.down, flags.left, flags.right

	-- Base assumption: your assets are authored with these “zero” poses:
	-- Turn(0°) connects (down + left); 3Way(0°) is “missing UP”; 4Way(0°) is symmetric.
	local rotation = 0

	if classification == "Turn" then
		if up and left        then rotation = 270
		elseif up and right   then rotation = 180
		elseif down and right then rotation =  90
		elseif down and left  then rotation =   0
		else rotation = 0 end

	elseif classification == "3Way" then
		if (not up) and left and right and down then
			rotation = 0
		elseif up and (not right) and left and down then
			rotation = 270
		elseif up and right and left and (not down) then
			rotation = 180
		elseif up and right and down and (not left) then
			rotation =  90
		else
			rotation = 0
		end

	elseif classification == "4Way" then
		rotation = 0
	else
		rotation = 0
	end

	rotation = _norm360(rotation)

	_iprint(string.format(
		"cell(%d,%d) class=%s  neigh: U=%s D=%s L=%s R=%s  -> rot=%d",
		cellCoord.x, cellCoord.z, tostring(classification),
		tostring(up), tostring(down), tostring(left), tostring(right), rotation
		))

	return rotation
end



-- attachRandomAd


local function attachRandomAd(billboardModel)
	local adNames = { "Ad1", "Ad2", "Ad3", "Ad4", "Ad5" }
	local getAdAsset = BuildingMasterList.getBuildingByName

	local adsPart = billboardModel:FindFirstChild("ADS", true)
	if not adsPart then
		warn("Billboard model missing 'ADS' part.")
		return
	end

	adsPart.Transparency = 1

	local chosenAdName = adNames[math.random(1, #adNames)]
	local adAsset = getAdAsset(chosenAdName)
	if not adAsset or not adAsset.stages or not adAsset.stages.Stage3 then
		warn("Missing ad asset or Stage3 for:", chosenAdName)
		return
	end

	local adClone = adAsset.stages.Stage3:Clone()
	adClone.Name = chosenAdName
	adClone.CFrame = adsPart.CFrame
	adClone:SetAttribute("AdName", chosenAdName)
	billboardModel:SetAttribute("AdName", chosenAdName)
	adClone.Parent = billboardModel
	
	--local billboardCF = billboardModel:GetPivot()
	--local _, rotY, _ = billboardCF:ToEulerAnglesXYZ()
	--local pos = adsPart.Position
	--local angleDeg = math.deg(rotY) % 360

	---- Round to nearest cardinal direction
	--local roundedDeg = math.floor((angleDeg + 45) / 90) * 90 % 360

	---- Flip ad if facing North or South
	--local flipAd = (roundedDeg == 0 or roundedDeg == 180)
	--local finalCFrame = CFrame.new(pos) * CFrame.Angles(0, rotY + (flipAd and math.rad(180) or 0), 0)

	--if adClone:IsA("Model") and adClone.PrimaryPart then
	--	adClone:SetPrimaryPartCFrame(finalCFrame)
	--elseif adClone:IsA("BasePart") then
	--	adClone.CFrame = finalCFrame
	--end

	adClone.Parent = billboardModel
end



-- placeStraightRoadDecorations


local function placeStraightRoadDecorations(player, zoneFolder, placedRoadsData, zoneId)
	-- East-West orientation
	local eastWestOffsetA = Vector3.new(2.5, 0, 3)
	local eastWestOffsetB = Vector3.new(-2.5, 0, -3)
	local eastWestRotA = math.rad(90)
	local eastWestRotB = math.rad(-90)

	-- North-South orientation
	local northSouthOffsetA = Vector3.new(-3, 0, -2.5)
	local northSouthOffsetB = Vector3.new(3, 0, 2.5)
	local northSouthRotA = math.rad(0)
	local northSouthRotB = math.rad(180)

	local toggle = true
	local sequences = {}
	local currentSeq = {}
	local lastDir = nil
	
	local YAW_JITTER_POS = math.rad(-30)
	local YAW_JITTER_NEG = math.rad(-30)
	
	table.sort(placedRoadsData, function(a, b)
		if a.gridX == b.gridX then
			return a.gridZ < b.gridZ
		end
		return a.gridX < b.gridX
	end)

	for i = 1, (#placedRoadsData - 1) do
		local curr = placedRoadsData[i]
		local nxt  = placedRoadsData[i + 1]
		local dir = PathingModule.getRoadDirection(
			{ x = curr.gridX, z = curr.gridZ },
			{ x = nxt.gridX,  z = nxt.gridZ  }
		)

		if dir == lastDir then
			table.insert(currentSeq, curr)
		else
			if #currentSeq >= 3 then
				table.insert(sequences, currentSeq)
			end
			currentSeq = { curr }
		end
		lastDir = dir
	end

	if #currentSeq >= 3 then
		table.insert(sequences, currentSeq)
	end
	
	local decorationSpacing = math.random(3, 9)
	for _, seq in ipairs(sequences) do
		for i = 2, (#seq - 1), decorationSpacing do
			decorationSpacing = math.random(3, 9)
			
			local cell = seq[i]
			
			local basePos = convertGridToWorld(player, cell.gridX, cell.gridZ) + Vector3.new(0, 3, 0)
			
			local prev = seq[i - 1]
			local nxt  = seq[i + 1]
			local dir
			if prev and nxt then
				dir = PathingModule.getRoadDirection(
					{ x = prev.gridX, z = prev.gridZ },
					{ x = nxt.gridX,  z = nxt.gridZ  }
				)
			else
				dir = "Undefined"
			end
			
			local placeThisOne = (math.random() >= (1/3))
			
			if placeThisOne then
				local offset, rotationY
				if dir == "East" or dir == "West" then
					offset    = toggle and eastWestOffsetA or eastWestOffsetB
					rotationY = (toggle and eastWestRotA or eastWestRotB)
						+ (toggle and YAW_JITTER_POS or YAW_JITTER_NEG)
				elseif dir == "North" or dir == "South" then
					offset    = toggle and northSouthOffsetA or northSouthOffsetB
					rotationY = (toggle and northSouthRotA or northSouthRotB)
						+ (toggle and YAW_JITTER_POS or YAW_JITTER_NEG)
				else
					offset    = Vector3.new(0, 0, 0)
					rotationY = 0
				end

				local decorationCF = CFrame.new(basePos + offset)
					* CFrame.Angles(0, rotationY, 0)
				toggle = not toggle

				local decorationName = (math.random() < 0.5) and "Billboard" or "BillboardStanding"
				local deco = BuildingMasterList.getBuildingByName(decorationName)
				if deco and deco.stages and deco.stages.Stage3 then
					local clone = deco.stages.Stage3:Clone()
					clone.Name = decorationName
					clone:SetAttribute("ZoneId", zoneId)
					clone:SetAttribute("IsRoadDecoration", true)
					clone:SetAttribute("GridX", cell.gridX)
					clone:SetAttribute("GridZ", cell.gridZ)
					

				if clone:IsA("Model") and clone.PrimaryPart then
					clone:SetPrimaryPartCFrame(decorationCF)
				elseif clone:IsA("BasePart") then
					clone.CFrame = decorationCF
				end

				for _, p in ipairs(clone:GetDescendants()) do
					if p:IsA("BasePart") then
						p.CanQuery = false
					end
				end
					
					if decorationName == "Billboard" then
						-- Alternate the lateral offset: one side +1.2, the other -1.2 (in LOCAL Z)
						-- Decide side from which road-side offset we chose above
						local sideSign
						if     offset == eastWestOffsetA or offset == northSouthOffsetA then
							sideSign =  1
						else
							sideSign = -1
						end

						if clone:IsA("Model") and clone.PrimaryPart then
							-- Move in local space: down 1.5, then ±1.2 forward (model’s Z)
							clone:SetPrimaryPartCFrame(clone:GetPrimaryPartCFrame() * CFrame.new(0, -1.5, 1.2 * sideSign))
						elseif clone:IsA("BasePart") then
							-- Same idea for a lone part
							clone.CFrame = clone.CFrame * CFrame.new(0, -1.5, 1.2 * sideSign)
						end
					end

				clone.Parent = zoneFolder
				attachRandomAd(clone)
				debugPrint(
					"[placeStraightRoadDecorations] Placed",
					decorationName,
					"at",
					cell.gridX,
					cell.gridZ
				)
				else
					warn("Missing model or Stage3 for decoration:", decorationName)
				end
			end
		end
	end  -- closes outer for (sequences)
end



-- updateIntersections

function RoadGeneratorModule.updateIntersections(zoneId, placedRoadsData, roadsFolder, opts)
	opts = opts or {}
	local SPAWN_INTERSECTION_DECOS = (opts.noDecorations ~= true)
	if typeof(placedRoadsData) ~= "table" then
		placedRoadsData = {}
	end

	local recalcRadius = tonumber(opts.recalcRadius)
	if recalcRadius then
		recalcRadius = math.max(1, math.floor(recalcRadius))
	else
		recalcRadius = 1
	end

	-- Axis directions for this plot (needed to mirror yaw on even plots)
	local axisDirX, axisDirZ = 1, 1
	if roadsFolder and roadsFolder.Parent then
		axisDirX, axisDirZ = GridConfig.getAxisDirectionsForPlot(roadsFolder.Parent)
	end

	local ownerId = opts.ownerId
	if not ownerId and roadsFolder and roadsFolder.Parent then
		local match = tostring(roadsFolder.Parent.Name):match("Plot_(%d+)")
		if match then ownerId = tonumber(match) end
	end
	if not ownerId and zoneId then
		local match = tostring(zoneId):match("_(%d+)_") or tostring(zoneId):match("_(%d+)$")
		if match then ownerId = tonumber(match) end
	end
	local adjacency = PathingModule.getAdjacencyForOwner(ownerId) or PathingModule.globalAdjacency

	----------------------------------------------------------------------
	-- Index existing road-ish objects (visible pieces) by cell
	----------------------------------------------------------------------
	local cellIndex, visibleSet = {}, {}
	for _, obj in ipairs(roadsFolder:GetDescendants()) do
		if (obj:IsA("Model") or obj:IsA("BasePart"))
			and not obj:GetAttribute("IsRoadDecoration") then
			local gx, gz = obj:GetAttribute("GridX"), obj:GetAttribute("GridZ")
			if gx and gz then
				local key = tostring(gx) .. "," .. tostring(gz)
				local bucket = cellIndex[key]
				if not bucket then
					bucket = {}
					cellIndex[key] = bucket
				end
				table.insert(bucket, obj)
				if not obj:GetAttribute("IsHiddenByIntersection") then
					visibleSet[key] = true
				end
			end
		end
	end

	local function hasVisibleRoadAt(gx, gz)
		return visibleSet[tostring(gx) .. "," .. tostring(gz)] == true
	end

	----------------------------------------------------------------------
	-- NEW: index all decorations by cell so we can remove/reparent fast
	----------------------------------------------------------------------
	local function isIntersectionDeco(inst)
		return inst
			and inst:GetAttribute("IsRoadDecoration") == true
			and (inst.Name == "StopLight" or inst.Name == "StopSign")
	end

	local decorIndex = {}
	for _, obj in ipairs(roadsFolder:GetDescendants()) do
		if (obj:IsA("Model") or obj:IsA("BasePart")) and obj:GetAttribute("IsRoadDecoration") then
			local gx, gz = obj:GetAttribute("GridX"), obj:GetAttribute("GridZ")
			if gx and gz then
				local k = tostring(gx) .. "," .. tostring(gz)
				local t = decorIndex[k]
				if not t then
					t = {}
					decorIndex[k] = t
				end
				table.insert(t, obj)
			end
		end
	end

	local function removeIntersectionDecosAtCell(gx, gz)
		local k = tostring(gx) .. "," .. tostring(gz)
		local list = decorIndex[k]
		if not list then return end
		for _, inst in ipairs(list) do
			if isIntersectionDeco(inst) and inst.Parent then
				inst:Destroy()
			end
		end
		decorIndex[k] = nil
	end

	local function reparentIntersectionDecosToHost(gx, gz, hostModel)
		local k = tostring(gx) .. "," .. tostring(gz)
		local list = decorIndex[k]
		if not list then return end
		for _, inst in ipairs(list) do
			if isIntersectionDeco(inst) and inst.Parent ~= hostModel then
				inst.Parent = hostModel -- world CFrame is preserved on reparent
			end
		end
	end

	----------------------------------------------------------------------
	-- apply per-asset yaw offsets if helper is present
	----------------------------------------------------------------------
	local function _applyOffset(name, yaw)
		if type(withAssetOffset) == "function" then
			return norm360(withAssetOffset(name, yaw))
		end
		return norm360(yaw or 0)
	end

	----------------------------------------------------------------------
	-- Helper: neighbor flags based on current visibility
	----------------------------------------------------------------------
	local function neighborFlagsVisible(cellCoord)
		local f = {
			up    = hasVisibleRoadAt(cellCoord.x,   cellCoord.z - 1),
			down  = hasVisibleRoadAt(cellCoord.x,   cellCoord.z + 1),
			left  = hasVisibleRoadAt(cellCoord.x-1, cellCoord.z     ),
			right = hasVisibleRoadAt(cellCoord.x+1, cellCoord.z     ),
		}
		applyEntryHints(f, cellCoord)
		return f
	end

	local function classifyFromFlags(f)
		local n = 0
		if f.up    then n += 1 end
		if f.down  then n += 1 end
		if f.left  then n += 1 end
		if f.right then n += 1 end
		if n == 4 then return "4Way" end
		if n == 3 then return "3Way" end
		if n == 2 then
			if (f.left and f.right) or (f.up and f.down) then
				return "Straight"
			else
				return "Turn"
			end
		end
		if n == 1 then return "DeadEnd" end
		return "Isolated"
	end

	local function rotationFromFlags(kind, f)
		if kind == "Turn" then
			if     f.down and f.left  then return 0
			elseif f.down and f.right then return 90
			elseif f.up   and f.right then return 180
			elseif f.up   and f.left  then return 270
			else return 0 end
		elseif kind == "3Way" then
			local missingUp    = (not f.up)    and f.left and f.right and f.down
			local missingRight = (not f.right) and f.up   and f.left  and f.down
			local missingDown  = (not f.down)  and f.up   and f.left  and f.right
			local missingLeft  = (not f.left)  and f.up   and f.right and f.down
			if     missingUp    then return 0
			elseif missingRight then return 270
			elseif missingDown  then return 180
			elseif missingLeft  then return 90
			else return 0 end
		else
			return 0
		end
	end

	----------------------------------------------------------------------
	-- Optional: adjacency flags (kept for parity with your debug paths)
	----------------------------------------------------------------------
	local function neighborFlagsFromAdjacency(cellCoord)
		local cellKey   = PathingModule.nodeKey(cellCoord)
		local neighborKeys = adjacency and adjacency[cellKey] or {}
		local upKey    = PathingModule.nodeKey({ x = cellCoord.x,   z = cellCoord.z - 1 })
		local downKey  = PathingModule.nodeKey({ x = cellCoord.x,   z = cellCoord.z + 1 })
		local leftKey  = PathingModule.nodeKey({ x = cellCoord.x-1, z = cellCoord.z     })
		local rightKey = PathingModule.nodeKey({ x = cellCoord.x+1, z = cellCoord.z     })
		return {
			up    = table.find(neighborKeys, upKey)    ~= nil,
			down  = table.find(neighborKeys, downKey)  ~= nil,
			left  = table.find(neighborKeys, leftKey)  ~= nil,
			right = table.find(neighborKeys, rightKey) ~= nil,
		}
	end

	local function flagsPreferAdj(cellCoord)
		local cellKey = PathingModule.nodeKey(cellCoord)
		if adjacency and adjacency[cellKey] then
			return neighborFlagsFromAdjacency(cellCoord), "adj"
		else
			return neighborFlagsVisible(cellCoord), "vis"
		end
	end

	----------------------------------------------------------------------
	-- Helper: spawn decoration. PARENT IS NOW THE HOST MODEL (4Way clone)
	----------------------------------------------------------------------
	local function spawnDecoration(decorationName, positionCF, parentInstance, gridX, gridZ, zoneOwnerId)
		local decorationAsset = BuildingMasterList.getBuildingByName(decorationName)
		if not decorationAsset then
			warn("[updateIntersections] Decoration data for '".. decorationName .."' not found.")
			return
		end
		if not decorationAsset.stages or not decorationAsset.stages.Stage3 then
			local fallbackStages = BuildingMasterList.loadBuildingStages("Road", "Default", decorationName)
			decorationAsset.stages = fallbackStages
		end
		if not (decorationAsset.stages and decorationAsset.stages.Stage3) then
			warn("[updateIntersections] Decoration '" .. decorationName .. "' has no Stage3 model.")
			return
		end

		local decClone = decorationAsset.stages.Stage3:Clone()
		decClone.Name = decorationName
		decClone:SetAttribute("ZoneId", zoneOwnerId)
		decClone:SetAttribute("IsRoadDecoration", true)
		decClone:SetAttribute("GridX", gridX)
		decClone:SetAttribute("GridZ", gridZ)

		if decClone:IsA("Model") and decClone.PrimaryPart then
			decClone:SetPrimaryPartCFrame(positionCF)
		elseif decClone:IsA("BasePart") then
			decClone.CFrame = positionCF
		end

		for _, part in ipairs(decClone:GetDescendants()) do
			if part:IsA("BasePart") then part.CanQuery = false end
		end
		decClone.Parent = parentInstance -- <<<<<< key change: attach to host
		if DEBUG_LOGS then
			print("[updateIntersections] Spawned decoration", decorationName, "at cell", gridX, gridZ, "under", parentInstance.Name)
		end
	end

	----------------------------------------------------------------------
	-- Helper: swap a base piece with an intersection model (Turn/3Way/4Way)
	-- NOTE: When swapping to 4Way we parent decos *under the 4Way clone*.
	----------------------------------------------------------------------
	local function swapRoadModel(oldPart, newRoadName, cellCoord, customRotation)
		local newAsset = BuildingMasterList.getBuildingByName(newRoadName)
		if not (newAsset and newAsset.stages and newAsset.stages.Stage3) then
			local stages = BuildingMasterList.loadBuildingStages("Road", "Default", newRoadName)
			if stages then newAsset = { name = newRoadName, style = "Default", stages = stages } end
			if not (newAsset and newAsset.stages and newAsset.stages.Stage3) then
				warn("[updateIntersections] Could not find Stage3 for '".. newRoadName .."'!")
				return nil
			end
		end

		local function _norm360(d) d = (d or 0) % 360; if d < 0 then d = d + 360 end; return d end
		local function _applyOffset(name, yaw)
			if type(withAssetOffset) == "function" then
				return _norm360(withAssetOffset(name, yaw))
			end
			return _norm360(yaw)
		end
		local function _dprint(...) if DEBUG_LOGS or DEBUG_ROAD_ROTATION then print("[swapRoadModel]", ...) end end

		local oldPos      = (oldPart:IsA("Model") and oldPart:GetPivot().Position) or oldPart.Position
		local oldZoneId   = oldPart:GetAttribute("ZoneId")   or zoneId
		local oldRoadType = oldPart:GetAttribute("RoadType") or "DirtRoad"
		local oldTime     = oldPart:GetAttribute("TimePlaced") or os.clock()
		local prevYaw     = tonumber(oldPart:GetAttribute("YawBuilt"))

		_dprint(string.format("old=%s → new=%s @ (%d,%d) prevYaw=%s custom=%s",
			tostring(oldPart.Name), tostring(newRoadName), cellCoord.x, cellCoord.z,
			tostring(prevYaw), tostring(customRotation)))

		oldPart:Destroy()

		local clone = newAsset.stages.Stage3:Clone()
		clone.Name = newRoadName
		clone:SetAttribute("ZoneId",     oldZoneId)
		clone:SetAttribute("RoadType",   oldRoadType)
		clone:SetAttribute("GridX",      cellCoord.x)
		clone:SetAttribute("GridZ",      cellCoord.z)
		clone:SetAttribute("TimePlaced", oldTime)

		local parentFolder = roadsFolder:FindFirstChild(oldZoneId) or roadsFolder
		clone.Parent = parentFolder

		if clone:IsA("Model") and not clone.PrimaryPart then
			local pp = Instance.new("Part")
			pp.Name, pp.Size, pp.Transparency, pp.Anchored = "Pivot", Vector3.new(1,1,1), 1, true
			pp.CFrame = clone:GetPivot()
			pp.Parent = clone
			clone.PrimaryPart = pp
		end

		local chosenYaw = customRotation
		if chosenYaw == nil then
			if prevYaw ~= nil then chosenYaw = prevYaw end
			chosenYaw = _applyOffset(newRoadName, chosenYaw or 0)
			chosenYaw = _adjustYawForAxis(chosenYaw, axisDirX, axisDirZ)
		else
			chosenYaw = norm360(chosenYaw)
		end

		if clone:IsA("Model") and clone.PrimaryPart then
			clone:SetPrimaryPartCFrame(CFrame.new(oldPos) * CFrame.Angles(0, math.rad(chosenYaw), 0))
		elseif clone:IsA("BasePart") then
			clone.Position    = oldPos
			clone.Orientation = Vector3.new(0, chosenYaw, 0)
		end
		clone:SetAttribute("YawBuilt", chosenYaw)

		_dprint(string.format("applied yaw=%d  (new=%s  zone=%s  cell=%d,%d)",
			chosenYaw, newRoadName, tostring(oldZoneId), cellCoord.x, cellCoord.z))

		-- When upgrading to a 4Way, first purge any orphan intersection decos from older code,
		-- then spawn fresh ones under the 4Way clone so they are auto-destroyed on swap/delete.
		if newRoadName == "4Way" and SPAWN_INTERSECTION_DECOS then
			removeIntersectionDecosAtCell(cellCoord.x, cellCoord.z)

			local baseCF = clone:IsA("Model") and clone:GetPivot() or CFrame.new(oldPos)
			local stopLightCorners = {
				{ offset = CFrame.new(-2,  0, -0.5), rotationY =  90 },
				{ offset = CFrame.new( 0.6,0, -2  ), rotationY =   0 },
				{ offset = CFrame.new( 2,  0,  0.5), rotationY = 270 },
				{ offset = CFrame.new(-0.5,0,  2  ), rotationY = 180 },
			}
			local stopSignCorners = {
				{ offset = CFrame.new(-2.2, -0.72, -1.8), rotationY =  90 },
				{ offset = CFrame.new( 1.8, -0.72, -2.1), rotationY =   0 },
				{ offset = CFrame.new( 2.2, -0.72,  1.8), rotationY = 270 },
				{ offset = CFrame.new(-1.3, -0.72,  2.1), rotationY = 180 },
			}
			local yOffset = 1.6
			local useStopSigns  = (math.random() < 0.9)
			local stopSignPairs = { {1,3}, {2,4} }
			local chosenPair    = stopSignPairs[math.random(1, #stopSignPairs)]

			for i = 1, #stopLightCorners do
				local decorationName = "StopLight"
				local corner = stopLightCorners[i]
				if useStopSigns and (i == chosenPair[1] or i == chosenPair[2]) then
					decorationName = "StopSign"
					corner = stopSignCorners[i]
				end

				local finalCF = baseCF * corner.offset + Vector3.new(0, yOffset, 0)
				finalCF = finalCF * CFrame.Angles(0, math.rad(corner.rotationY), 0)

				-- PARENT UNDER THE NEW 4Way CLONE
				spawnDecoration(decorationName, finalCF, clone, cellCoord.x, cellCoord.z, oldZoneId)
			end
		end
		return clone
	end

	----------------------------------------------------------------------
	-- neighbor flags source (visible preferred unless adjacency present)
	----------------------------------------------------------------------
	local function flagsForCell(cellCoord)
		local cellKey = PathingModule.nodeKey(cellCoord)
		if adjacency and adjacency[cellKey] then
			local f = neighborFlagsFromAdjacency(cellCoord)
			applyEntryHints(f, cellCoord)
			return f, "adj"
		else
			return neighborFlagsVisible(cellCoord), "vis"
		end
	end

	----------------------------------------------------------------------
	-- 1) Expand cells to check
	----------------------------------------------------------------------
	local unique, finalCellsToCheck = {}, {}
	local function addCell(x, z)
		local key = string.format("%d_%d", x, z)
		if unique[key] then return end
		unique[key] = true
		table.insert(finalCellsToCheck, { x = x, z = z })
	end

	for _, cellInfo in ipairs(placedRoadsData) do
		local gx, gz = cellInfo.gridX, cellInfo.gridZ
		if gx and gz then
			for dx = -recalcRadius, recalcRadius do
				for dz = -recalcRadius, recalcRadius do
					addCell(gx + dx, gz + dz)
				end
			end
		end
	end

	----------------------------------------------------------------------
	-- 2) Per cell: classify and swap/rotate + DECORATION CLEANUP/OWNERSHIP
	----------------------------------------------------------------------
	for _, cellCoord in ipairs(finalCellsToCheck) do
		local key = tostring(cellCoord.x) .. "," .. tostring(cellCoord.z)
		local cellRoadParts = cellIndex[key]
		if not cellRoadParts or #cellRoadParts == 0 then
			continue
		end

		-- pick newest by TimePlaced
		local newestPart, newestTime = nil, -math.huge
		for _, rp in ipairs(cellRoadParts) do
			local t = tonumber(rp:GetAttribute("TimePlaced"))
			if t and t > newestTime then newestTime, newestPart = t, rp end
		end
		if not newestPart then continue end

		local flags, _ = flagsForCell(cellCoord)
		local kind = classifyFromFlags(flags)
		local zoneOwnerId = newestPart:GetAttribute("ZoneId") or zoneId

		if kind == "3Way" or kind == "4Way" or kind == "Turn" then
			local rotFromVis = (kind == "4Way") and 0 or rotationFromFlags(kind, flags)
			local finalYaw   = _applyOffset(kind, rotFromVis)
			finalYaw = _adjustYawForAxis(finalYaw, axisDirX, axisDirZ)

			if newestPart.Name ~= kind then
				-- If we are moving AWAY from 4Way, clear any leftover intersection decos.
				if newestPart.Name == "4Way" and kind ~= "4Way" then
					removeIntersectionDecosAtCell(cellCoord.x, cellCoord.z)
				end
				newestPart = swapRoadModel(newestPart, kind, cellCoord, finalYaw)
			else
				if newestPart:IsA("Model") and newestPart.PrimaryPart then
					newestPart:SetPrimaryPartCFrame(
						CFrame.new(newestPart.PrimaryPart.Position) * CFrame.Angles(0, math.rad(finalYaw), 0))
				elseif newestPart:IsA("BasePart") then
					newestPart.Orientation = Vector3.new(0, finalYaw, 0)
				end
				newestPart:SetAttribute("YawBuilt", finalYaw)
			end

			-- If the final classification **is not** 4Way, make sure no intersection decos remain.
			if kind ~= "4Way" then
				removeIntersectionDecosAtCell(cellCoord.x, cellCoord.z)
			else
				-- If it *is* a 4Way and we didn't swap (so no fresh spawn),
				-- reparent any stray decos under this 4Way so they get auto-destroyed later.
				if newestPart and newestPart.Name == "4Way" then
					reparentIntersectionDecosToHost(cellCoord.x, cellCoord.z, newestPart)
				end
			end

			-- hide any vanilla “Road” in this cell
			for _, leftover in ipairs(cellRoadParts) do
				if leftover ~= newestPart and leftover.Name == "Road" then
					if leftover:IsA("BasePart") then
						leftover.Transparency = 1
						leftover.CanCollide   = false
						leftover.CastShadow   = false
					end
					for _, d in ipairs(leftover:GetDescendants()) do
						if d:IsA("BasePart") then
							d.Transparency = 1
							d.CanCollide   = false
							d.CastShadow   = false
						elseif d:IsA("Decal") or d:IsA("Texture") then
							d.Transparency = 1
						end
					end
					leftover.Name = "Road_Hidden"
					leftover:SetAttribute("IsHiddenByIntersection", true)
				end
			end

		else
			-- Straight / DeadEnd / Isolated
			local f = flags
			local canonicalYaw
			if     (f.left and f.right) then
				canonicalYaw = degForDir("East")
			elseif (f.up   and f.down)  then
				canonicalYaw = degForDir("South")
			elseif f.up then
				canonicalYaw = degForDir("North")
			elseif f.right then
				canonicalYaw = degForDir("East")
			elseif f.down then
				canonicalYaw = degForDir("South")
			elseif f.left then
				canonicalYaw = degForDir("West")
			else
				canonicalYaw = 0
			end
			canonicalYaw = norm360(canonicalYaw)

			local prevYawInCell = nil
			for _, rp in ipairs(cellRoadParts) do
				if (rp.Name == "Road" or rp.Name == "Road_Hidden") then
					local y = tonumber(rp:GetAttribute("YawBuilt"))
					if y then prevYawInCell = y end
				end
			end
			local newestPrevYaw = tonumber(newestPart:GetAttribute("YawBuilt")) or prevYawInCell

			local noNeighbors = not (f.up or f.down or f.left or f.right)
			local finalYaw = canonicalYaw
			if noNeighbors and newestPrevYaw then
				finalYaw = norm360(newestPrevYaw)
			elseif PREFER_STORED_STRAIGHT_YAW and newestPrevYaw and isColinear(newestPrevYaw, canonicalYaw) then
				finalYaw = norm360(newestPrevYaw)
			end
			finalYaw = _applyOffset(newestPart.Name or "Road", finalYaw)
			finalYaw = _adjustYawForAxis(finalYaw, axisDirX, axisDirZ)

			if newestPart.Name ~= "Road" then
				newestPart = swapRoadModel(newestPart, "Road", cellCoord, finalYaw)
			else
				if newestPart:IsA("Model") and newestPart.PrimaryPart then
					newestPart:SetPrimaryPartCFrame(
						CFrame.new(newestPart.PrimaryPart.Position) * CFrame.Angles(0, math.rad(finalYaw), 0))
				elseif newestPart:IsA("BasePart") then
					newestPart.Orientation = Vector3.new(0, finalYaw, 0)
				end
				newestPart:SetAttribute("YawBuilt", finalYaw)
			end

			-- Straight-ish cells should NEVER have intersection decos; nuke any leftovers.
			removeIntersectionDecosAtCell(cellCoord.x, cellCoord.z)

			-- Unhide any old vanilla road in this cell
			for _, rp in ipairs(cellRoadParts) do
				if rp:GetAttribute("IsHiddenByIntersection") then
					if rp:IsA("BasePart") then
						rp.Transparency, rp.CanCollide, rp.CastShadow = 0, true, true
					end
					for _, d in ipairs(rp:GetDescendants()) do
						if d:IsA("BasePart") then
							d.Transparency, d.CanCollide, d.CastShadow = 0, true, true
						elseif d:IsA("Decal") or d:IsA("Texture") then
							d.Transparency = 0
						end
					end
					rp.Name = "Road"
					rp:SetAttribute("IsHiddenByIntersection", false)
				end
			end
		end
	end
end


-- populateZone
function RoadGeneratorModule.populateZone(player, zoneId, mode, gridList, predefinedRoads, rotation, skipStages, isReload)
	task.spawn(function()
		local isFastReload = isReload == true
		local _roadReserve = nil
		-- ===== pre-populate guards / cleanup =====================================
		ZoneTrackerModule.setZonePopulating(player, zoneId, true)
		-- Reserve the footprint so we can safely coexist with power/others (roads only block roads)
		local _roadReserve = select(1, GridUtils.reserveArea(player, zoneId, "road", gridList, { ttl = 20.0 }))
		if not _roadReserve and not isFastReload then
			-- One gentle retry after transient in-flight work clears
			local tries = 0
			while tries < 5 do
				task.wait(0.2); tries += 1
				_roadReserve = select(1, GridUtils.reserveArea(player, zoneId, "road", gridList, { ttl = 20.0 }))
				if _roadReserve then break end
			end
			if not _roadReserve then
				warn(("[RoadGen] %s could not obtain reservation; proceeding best-effort"):format(zoneId))
			end
		end

		-- Clear any stale occupants from *this* zone footprint (zone/building legacy-safe).
		if type(gridList) == "table" and #gridList > 0 then
			ZoneTrackerModule.forceClearZoneFootprint(player, zoneId, gridList)
		end

		debugPrint(string.format("Populating Road Zone '%s' (mode: %s)", zoneId, mode))

		-- ===== containers / terrain ==============================================
		local plotName   = "Plot_" .. player.UserId
		local playerPlot = Workspace.PlayerPlots:FindFirstChild(plotName)
		if not playerPlot then
			warn("RoadGeneratorModule: Player plot '" .. plotName .. "' not found.")
			zonePopulatedEvent:Fire(player, zoneId, {})
			if _roadReserve then GridUtils.releaseReservation(_roadReserve) end
			ZoneTrackerModule.setZonePopulating(player, zoneId, false)
			return
		end

		local terrain = playerPlot:FindFirstChild("TestTerrain")
		if not terrain then
			warn("RoadGeneratorModule: 'TestTerrain' not found in plot:", plotName)
			zonePopulatedEvent:Fire(player, zoneId, {})
			if _roadReserve then GridUtils.releaseReservation(_roadReserve) end
			ZoneTrackerModule.setZonePopulating(player, zoneId, false)
			return
		end

		local roadsFolder = playerPlot:FindFirstChild("Roads")
		if not roadsFolder then
			roadsFolder = Instance.new("Folder")
			roadsFolder.Name = "Roads"
			roadsFolder.Parent = playerPlot
		end

		-- Idempotent: kill any old zone subfolder (visuals) before re-place
		local zoneFolder = roadsFolder:FindFirstChild(zoneId)
		if zoneFolder then
			zoneFolder:Destroy()
		end
		zoneFolder = Instance.new("Folder")
		zoneFolder.Name = zoneId
		zoneFolder.Parent = roadsFolder

		-- ===== assets =============================================================
		local defaultStyle = "Default"
		local roadsList = BuildingMasterList.getRoadsByStyle(defaultStyle)
		if #roadsList == 0 then
			warn(string.format("No roads found for style '%s'.", defaultStyle))
			zonePopulatedEvent:Fire(player, zoneId, {})
			if _roadReserve then GridUtils.releaseReservation(_roadReserve) end
			ZoneTrackerModule.setZonePopulating(player, zoneId, false)
			return
		end

		local forcedRoad
		for _, rd in ipairs(roadsList) do
			if (rd.name or rd.Name) == "Road" then
				forcedRoad = rd
				break
			end
		end
		if not forcedRoad then
			warn("No entry with name='Road'. Cannot place.")
			zonePopulatedEvent:Fire(player, zoneId, {})
			if _roadReserve then GridUtils.releaseReservation(_roadReserve) end
			ZoneTrackerModule.setZonePopulating(player, zoneId, false)
			return
		end

		local bridgeAsset = BuildingMasterList.getBuildingByName("Bridge")
		if bridgeAsset then
			if not (bridgeAsset.stages and bridgeAsset.stages.Stage3) then
				bridgeAsset.stages = BuildingMasterList.loadBuildingStages("Road","Default","Bridge")
			end
			local m = bridgeAsset.stages.Stage3
			if m:IsA("Model") and not m.PrimaryPart then
				local pp = Instance.new("Part")
				pp.Name, pp.Size, pp.Transparency, pp.Anchored = "Pivot", Vector3.new(1,1,1), 1, true
				pp.CFrame = m:GetPivot()
				pp.Parent = m
				m.PrimaryPart = pp
			end
		end

		-- ===== placement loop =====================================================
		local placedRoadsData = {}
		local roadCount = 0
		local nextEventThreshold = math.random(5, 10)

		local function onRoadPlaced()
			roadCount += 1
			if roadCount >= nextEventThreshold then
				roadsPlacedEvent:Fire(player, zoneId, roadCount)
				debugPrint(string.format("Fired roadsPlacedEvent after placing %d roads in zone '%s'", roadCount, zoneId))
				roadCount = 0
				nextEventThreshold = math.random(5, 10)
			end
		end

		if predefinedRoads then
			for _, rData in ipairs(predefinedRoads) do
				local selectedAsset = BuildingMasterList.getBuildingByName(rData.roadName)
				if selectedAsset then
					RoadGeneratorModule.generateRoadSegment(
						terrain, zoneFolder, player, zoneId, mode,
						{ x = rData.gridX, z = rData.gridZ },
						selectedAsset, rData.rotation, onRoadPlaced
					)
					table.insert(placedRoadsData, {
						roadName = rData.roadName, rotation = rData.rotation,
						gridX    = rData.gridX,    gridZ    = rData.gridZ
					})
				else
					warn("Could not find road by name:", rData.roadName)
					-- not an early return; keep building the rest
				end
			end
		else
			-- Road / Bridge state machine
			local bridging = false
			local function needsBridge(supportType)
				return supportType == "Cliff" or supportType == "Water" or supportType == "Void"
			end

			for i, cell in ipairs(gridList) do
				-- Roads are allowed to overlap overlays/utilities; only block on non-utility conflicts.
				local types = ZoneTrackerModule.getGridOccupantTypes(player, cell.x, cell.z)
				if types and types.road then
					continue
				end
				
				
				-- If a power pole is here, suppress it BEFORE placing the road so ropes re-link cleanly.
				if types and types.power and PowerGeneratorModule2 and PowerGeneratorModule2.suppressPoleForRoad then
					PowerGeneratorModule2.suppressPoleForRoad(player, zoneId, cell.x, cell.z)
				end

				-- 1) Probe support type (land/void/water/cliff)
				local worldPos = convertGridToWorld(player, cell.x, cell.z)
				local probe = Instance.new("Part")
				probe.Size, probe.Position, probe.Anchored = Vector3.new(1,1,1), worldPos, true
				probe.Transparency, probe.CanCollide, probe.Parent = 1, false, Workspace
				local support = getSupportTypeForCell(probe)
				probe:Destroy()

				-- 2) Choose asset & toggle bridging based on terrain support
				local spanCell = needsBridge(support)
				if not bridging and spanCell and bridgeAsset then
					bridging = true
				end

				local asset = (bridging and bridgeAsset) or forcedRoad
				if bridging and not spanCell then
					bridging = false -- first land cell after a span gets the tail piece
				end

				-- 3) Compute rotation
				local rotationY = 0
				if i < #gridList then
					local dir = PathingModule.getRoadDirection(cell, gridList[i+1])
					rotationY = PathingModule.directionAngles[dir] or 0
				elseif i > 1 then
					local dir = PathingModule.getRoadDirection(gridList[i-1], cell)
					rotationY = PathingModule.directionAngles[dir] or 0
				end

				-- 4) Place
				RoadGeneratorModule.generateRoadSegment(
					terrain, zoneFolder, player, zoneId, mode, cell, asset, rotationY, onRoadPlaced
				)

				table.insert(placedRoadsData, {
					roadName = asset.name or asset.Name,
					rotation = rotationY,
					gridX    = cell.x,
					gridZ    = cell.z
				})

				if not isFastReload then
					task.wait(BUILD_INTERVAL)
				end
			end
		end

		debugPrint(string.format("Road generation finished for zone '%s'. Placed: %d segments", zoneId, #placedRoadsData))

		-- ===== pathing / intersections / deco / orientation ======================
		if #placedRoadsData > 0 then
			local coordsForAdj = {}
			for _, rData in ipairs(placedRoadsData) do
				coordsForAdj[#coordsForAdj+1] = { x = rData.gridX, z = rData.gridZ }
			end
			PathingModule.registerRoad(zoneId, mode, coordsForAdj, coordsForAdj[1], coordsForAdj[#coordsForAdj], player and player.UserId)
		end

		RoadGeneratorModule.updateIntersections(zoneId, placedRoadsData, roadsFolder, {
			recalcRadius = INTERSECTION_RESCAN_RADIUS,
		})
		pcall(function()
			placeStraightRoadDecorations(player, zoneFolder, placedRoadsData, zoneId)
		end)

		local changedRoadCells = {}
		for _, rData in ipairs(placedRoadsData) do
			changedRoadCells[#changedRoadCells+1] = { x = rData.gridX, z = rData.gridZ }
		end
		RoadGeneratorModule.updateNearbyBuildingsOrientation(player, changedRoadCells)
		-- ===== finalize ==========================================================
		local snap = RoadGeneratorModule.captureRoadZoneSnapshot(player, zoneId)
		RoadGeneratorModule.saveSnapshot(player, zoneId, snap)
		zonePopulatedEvent:Fire(player, zoneId, placedRoadsData)
		if _roadReserve then GridUtils.releaseReservation(_roadReserve) end
		ZoneTrackerModule.setZonePopulating(player, zoneId, false)
	end)
end


function RoadGeneratorModule.populateZoneFromSave(player, zoneId, mode, gridList, saved, rotation, isReload)
	normalizeLegacyEvenPlotData(player, gridList, saved)
	-- Case A: full snapshot
	if typeof(saved) == "table" and saved.segments and #saved.segments > 0 then
		return RoadGeneratorModule.recreateZoneExact(player, zoneId, mode, saved)
	end
	-- Case B: legacy "placedRoadsData" list
	if typeof(saved) == "table" and #saved > 0 and saved[1].gridX then
		return RoadGeneratorModule.populateZone(player, zoneId, mode, gridList, saved, rotation, true, isReload)
	end
	-- Fallback: procedural
	return RoadGeneratorModule.populateZone(player, zoneId, mode, gridList, nil, rotation, true, isReload)
end

function RoadGeneratorModule.recalculateIntersectionsForPlot(player, zoneWhitelist)  -- zoneWhitelist: array of zoneIds or nil
	print(("[RoadFix] Re-calculating intersections for %s"):format(player.Name))

	local function _norm360(d) d = (tonumber(d) or 0) % 360; if d < 0 then d = d + 360 end; return d end
	local function _dprint(...)
		if DEBUG_LOGS or DEBUG_ROAD_ROTATION then
			print("[RoadFix][Recalc]", ...)
		end
	end

	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_" .. player.UserId)
	if not plot then
		_dprint("No plot for player.")
		return
	end

	local roadsFolder = plot:FindFirstChild("Roads")
	if not roadsFolder then
		_dprint("No Roads folder.")
		return
	end
	
	local allowed = nil
	if typeof(zoneWhitelist) == "table" then
		allowed = {}
		for _, z in ipairs(zoneWhitelist) do allowed[z] = true end
	end
	
	-- Build a synthetic placedRoadsData table from *visible road pieces only*
	local placedRoadsData = {}
	local nScanned, nAdded, nSkipped = 0, 0, 0

	for _, obj in ipairs(roadsFolder:GetDescendants()) do
		if obj:IsA("Model") or obj:IsA("BasePart") then
			nScanned += 1

			-- Skip decorations; they carry GridX/Z but shouldn't drive intersections
			if obj:GetAttribute("IsRoadDecoration") == true then
				nSkipped += 1
				continue
			end
			
			if allowed then
				local zid = obj:GetAttribute("ZoneId")
				if not (zid and allowed[zid]) then
					nSkipped += 1
					continue
				end
			end


			local gx, gz = obj:GetAttribute("GridX"), obj:GetAttribute("GridZ")
			if gx and gz then
				-- Prefer sticky yaw; fall back to live orientation
				local yaw = obj:GetAttribute("YawBuilt")
				if yaw == nil then
					if obj:IsA("Model") and obj.PrimaryPart then
						yaw = obj.PrimaryPart.Orientation.Y
					elseif obj:IsA("BasePart") then
						yaw = obj.Orientation.Y
					else
						yaw = 0
					end
				end
				yaw = _norm360(yaw)

				table.insert(placedRoadsData, {
					roadName = obj.Name,  -- "Road","Bridge","Turn","3Way","4Way"
					rotation = yaw,
					gridX    = gx,
					gridZ    = gz,
				})
				nAdded += 1
			else
				nSkipped += 1
			end
		end
	end

	if DEBUG_LOGS or DEBUG_ROAD_ROTATION then
		_dprint(string.format("Scanned=%d  Added=%d  Skipped=%d", nScanned, nAdded, nSkipped))
	end

	-- Nothing left → nothing to do
	if #placedRoadsData == 0 then
		_dprint("No road cells found; aborting.")
		return
	end

	-- Run the existing intersection logic against the reconstructed data.
	-- We pass nil for zoneId; swapRoadModel will pull ZoneId from each part as needed.
	RoadGeneratorModule.updateIntersections(nil, placedRoadsData, roadsFolder)
end


-- Capture a precise snapshot of what exists for this zone (visible piece per cell + decos)
function RoadGeneratorModule.captureRoadZoneSnapshot(player, zoneId)
	local snapshot = {
		version = 1,
		zoneId  = zoneId,
		timeCaptured = os.clock(),
		segments   = {}, -- array of { gridX, gridZ, roadName, rotation, timePlaced }
		interDecos = {}, -- array of { gridX, gridZ, type, localPos={x,y,z}, localYaw }
		strDecos   = {}, -- array of { gridX, gridZ, modelName, localPos={x,y,z}, localYaw, adName }
	}

	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_" .. player.UserId)
	if not plot then return snapshot end
	local roadsFolder = plot:FindFirstChild("Roads"); if not roadsFolder then return snapshot end
	local zoneFolder  = roadsFolder:FindFirstChild(zoneId); if not zoneFolder then return snapshot end

	-- 1) latest visible piece per cell
	local latest = {} -- key -> {inst, time}
	for _, obj in ipairs(zoneFolder:GetChildren()) do
		if (obj:IsA("Model") or obj:IsA("BasePart"))
			and obj:GetAttribute("ZoneId") == zoneId
			and not obj:GetAttribute("IsRoadDecoration")
			and not obj:GetAttribute("IsHiddenByIntersection")
		then
			local gx,gz = obj:GetAttribute("GridX"), obj:GetAttribute("GridZ")
			if gx and gz then
				local k = _keyXZ(gx,gz)
				local t = tonumber(obj:GetAttribute("TimePlaced")) or 0
				if not latest[k] or t > latest[k].time then latest[k] = { inst = obj, time = t } end
			end
		end
	end
	for _, rec in pairs(latest) do
		local obj = rec.inst
		-- Prefer sticky yaw if present; it’s what you wrote at place time
		local rot = tonumber(obj:GetAttribute("YawBuilt"))
		if rot == nil then
			if obj:IsA("Model") and obj.PrimaryPart then
				rot = obj.PrimaryPart.Orientation.Y
			elseif obj:IsA("BasePart") then
				rot = obj.Orientation.Y
			else
				rot = 0
			end
		end
		table.insert(snapshot.segments, {
			gridX = obj:GetAttribute("GridX"),
			gridZ = obj:GetAttribute("GridZ"),
			roadName = obj.Name,                -- "Road","Bridge","Turn","3Way","4Way"
			rotation = rot,
			timePlaced = rec.time,
		})
	end

	-- Helper: get host yaw (from snapshot we just collected)
	local hostYawByCell = {}
	for _, seg in ipairs(snapshot.segments) do hostYawByCell[_keyXZ(seg.gridX,seg.gridZ)] = seg.rotation end

	-- 2) decorations (relative offsets to host cell CF)
	for _, obj in ipairs(zoneFolder:GetDescendants()) do
		if (obj:IsA("Model") or obj:IsA("BasePart"))
			and obj:GetAttribute("ZoneId") == zoneId
			and obj:GetAttribute("IsRoadDecoration") == true
		then
			local gx,gz = obj:GetAttribute("GridX"), obj:GetAttribute("GridZ")
			if gx and gz then
				local hostYaw = hostYawByCell[_keyXZ(gx,gz)] or 0
				local hostCF  = _baseCellCF(player, gx, gz, hostYaw)
				local worldCF = (obj:IsA("Model") and obj:GetPivot()) or obj.CFrame
				local lcf     = _localCF(hostCF, worldCF)
				local lp      = lcf.Position
				local lyaw    = _yawDeg(lcf)

				if obj.Name == "StopLight" or obj.Name == "StopSign" then
					table.insert(snapshot.interDecos, {
						gridX=gx, gridZ=gz, type=obj.Name,
						localPos={x=lp.X,y=lp.Y,z=lp.Z}, localYaw=lyaw,
					})
				elseif (obj.Name == "BillboardStanding" or obj.Name == "Billboard") then
					table.insert(snapshot.strDecos, {
						gridX = gx, gridZ = gz, modelName = obj.Name,  -- << keep the real model name
						localPos = { x = lp.X, y = lp.Y, z = lp.Z }, localYaw = lyaw,
						adName = obj:GetAttribute("AdName"),
					})
				end
			end
		end
	end
	
	if DEBUG_LOGS then
		print(string.format(
			"[RoadSnapshot] zone=%s segments=%d interDecos=%d strDecos=%d",
			zoneId, #snapshot.segments, #snapshot.interDecos, #snapshot.strDecos))
	end

	return snapshot
end

function RoadGeneratorModule.regenerateRoadSegment(player, zoneId, mode, segData)
	-- Helpers (safe fallbacks; won't clash with globals if you already defined them)
	local function _norm360(d) d = (d or 0) % 360; if d < 0 then d = d + 360 end; return d end
	local function _applyOffset(assetName, yaw)
		if type(withAssetOffset) == "function" then
			return _norm360(withAssetOffset(assetName, yaw))
		end
		return _norm360(yaw or 0)
	end
	local function _dprint(...)
		if DEBUG_LOGS or DEBUG_ROAD_ROTATION then
			print("[regenRoadSegment]", ...)
		end
	end

	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_" .. player.UserId)
	if not plot then return nil end

	local roadsFolder = plot:FindFirstChild("Roads")
	if not roadsFolder then
		roadsFolder = Instance.new("Folder")
		roadsFolder.Name = "Roads"
		roadsFolder.Parent = plot
	end

	local zoneFolder = roadsFolder:FindFirstChild(zoneId)
	if not zoneFolder then
		zoneFolder = Instance.new("Folder")
		zoneFolder.Name = zoneId
		zoneFolder.Parent = roadsFolder
	end

	-- Resolve asset by name ("Road","Bridge","Turn","3Way","4Way")
	local asset = BuildingMasterList.getBuildingByName(segData.roadName)
	if asset and not (asset.stages and asset.stages.Stage3) then
		asset.stages = BuildingMasterList.loadBuildingStages("Road","Default", segData.roadName)
	end
	if not (asset and asset.stages and asset.stages.Stage3) then
		warn("[regenerateRoadSegment] Missing asset for:", segData.roadName)
		return nil
	end

	-- Compute world position and yaw to apply (respect per-asset zero pose)
	local worldPos  = convertGridToWorld(player, segData.gridX, segData.gridZ)
	local yawInput  = tonumber(segData.rotation) or 0
	local yawApply
	if segData._rotationIsApplied == true then
		yawApply = _norm360(yawInput)
	else
		yawApply = _applyOffset(segData.roadName or "Road", yawInput)
	end

	_dprint(string.format("zone=%s cell=(%d,%d) asset=%s yawIn=%d yawApply=%d",
		tostring(zoneId), segData.gridX, segData.gridZ, tostring(segData.roadName), yawInput, yawApply))

	-- Clone and place
	local modelOrPart = asset.stages.Stage3:Clone()
	modelOrPart.Name = segData.roadName

	if modelOrPart:IsA("Model") then
		if not modelOrPart.PrimaryPart then
			-- add a pivot if needed
			local pp = Instance.new("Part")
			pp.Name, pp.Size, pp.Transparency, pp.Anchored = "Pivot", Vector3.new(1,1,1), 1, true
			pp.CFrame = modelOrPart:GetPivot()
			pp.Parent = modelOrPart
			modelOrPart.PrimaryPart = pp
		end
		modelOrPart:SetPrimaryPartCFrame(CFrame.new(worldPos) * CFrame.Angles(0, math.rad(yawApply), 0))
	else
		modelOrPart.Position    = worldPos
		modelOrPart.Orientation = Vector3.new(0, yawApply, 0)
	end

	-- Clear overlaps at this cell
	removeOverlappingObjects(player, zoneId, worldPos, { x = segData.gridX, z = segData.gridZ })

	-- Optimisation flags
	for _, p in ipairs(modelOrPart:GetDescendants()) do
		if p:IsA("BasePart") then p.CanQuery = false end
	end
	if modelOrPart:IsA("BasePart") then modelOrPart.CanQuery = false end

	-- Attributes + parenting
	modelOrPart.Parent = zoneFolder
	modelOrPart:SetAttribute("ZoneId", zoneId)
	modelOrPart:SetAttribute("RoadType", mode)
	modelOrPart:SetAttribute("GridX", segData.gridX)
	modelOrPart:SetAttribute("GridZ", segData.gridZ)
	modelOrPart:SetAttribute("TimePlaced", segData.timePlaced or os.clock())
	modelOrPart:SetAttribute("YawBuilt", yawApply)  -- <<< sticky yaw for future salvage
	
	-- handle origin during replay-from-save, too
	if segData.gridX == 0 and segData.gridZ == 0 then
		refreshRoadStartTransparency(player)
	end
	
	-- Occupancy + quadtree
	local occId = ("%s_road_%d_%d"):format(zoneId, segData.gridX, segData.gridZ)
	ZoneTrackerModule.markGridOccupied(player, segData.gridX, segData.gridZ, "road", occId, mode)
	QuadtreeService:insert({ x = segData.gridX, y = segData.gridZ, width = 1, height = 1, roadId = occId })

	return modelOrPart
end

-- Recreate one intersection decoration ("StopLight" / "StopSign")
-- d = { gridX, gridZ, type, localPos={x,y,z}, localYaw }
function RoadGeneratorModule.recreateIntersectionDecoration(player, zoneId, hostRotation, d)
	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_" .. player.UserId)
	if not plot then return end
	local roadsFolder = plot:FindFirstChild("Roads"); if not roadsFolder then return end
	local zoneFolder  = roadsFolder:FindFirstChild(zoneId); if not zoneFolder then return end

	local asset = BuildingMasterList.getBuildingByName(d.type)
	if asset and not (asset.stages and asset.stages.Stage3) then
		asset.stages = BuildingMasterList.loadBuildingStages("Road","Default",d.type)
	end
	if not (asset and asset.stages and asset.stages.Stage3) then
		warn("[recreateIntersectionDecoration] Missing asset for:", d.type); return
	end

	-- Build transforms
	local hostCF  = _baseCellCF(player, d.gridX, d.gridZ, hostRotation or 0)
	local localCF = CFrame.new(Vector3.new(d.localPos.x, d.localPos.y, d.localPos.z))
		* CFrame.Angles(0, math.rad(d.localYaw or 0), 0)
	local finalCF = _applyLocal(hostCF, localCF)

	-- Prefer to parent under the actual 4Way in this cell (if present)
	local hostModel = nil
	for _, child in ipairs(zoneFolder:GetChildren()) do
		if (child.Name == "4Way")
			and child:GetAttribute("GridX") == d.gridX
			and child:GetAttribute("GridZ") == d.gridZ
		then
			hostModel = child
			break
		end
	end

	local clone = asset.stages.Stage3:Clone()
	clone.Name = d.type
	clone:SetAttribute("ZoneId", zoneId)
	clone:SetAttribute("IsRoadDecoration", true)
	clone:SetAttribute("GridX", d.gridX)
	clone:SetAttribute("GridZ", d.gridZ)

	if clone:IsA("Model") and clone.PrimaryPart then
		clone:SetPrimaryPartCFrame(finalCF)
	elseif clone:IsA("BasePart") then
		clone.CFrame = finalCF
	end

	for _, p in ipairs(clone:GetDescendants()) do
		if p:IsA("BasePart") then p.CanQuery = false end
	end

	-- Parent under host 4Way if it exists, else fall back to zone folder
	clone.Parent = hostModel or zoneFolder
end

-- Recreate one straight-road decoration (BillboardStanding) WITH SAME AD
-- d = { gridX, gridZ, modelName="BillboardStanding", localPos, localYaw, adName }
function RoadGeneratorModule.recreateStraightDecoration(player, zoneId, hostRotation, d)
	local plot = Workspace.PlayerPlots:FindFirstChild("Plot_" .. player.UserId)
	if not plot then return end
	local roadsFolder = plot:FindFirstChild("Roads"); if not roadsFolder then return end
	local zoneFolder  = roadsFolder:FindFirstChild(zoneId); if not zoneFolder then return end

	local asset = BuildingMasterList.getBuildingByName(d.modelName)
	if asset and not (asset.stages and asset.stages.Stage3) then
		asset.stages = BuildingMasterList.loadBuildingStages("Road","Default",d.modelName)
	end
	if not (asset and asset.stages and asset.stages.Stage3) then
		warn("[recreateStraightDecoration] Missing asset:", d.modelName); return
	end

	local hostCF  = _baseCellCF(player, d.gridX, d.gridZ, hostRotation or 0)
	local localCF = CFrame.new(Vector3.new(d.localPos.x, d.localPos.y, d.localPos.z))
		* CFrame.Angles(0, math.rad(d.localYaw or 0), 0)
	local finalCF = _applyLocal(hostCF, localCF)

	local clone = asset.stages.Stage3:Clone()
	clone.Name = d.modelName
	clone:SetAttribute("ZoneId", zoneId)
	clone:SetAttribute("IsRoadDecoration", true)
	clone:SetAttribute("GridX", d.gridX)
	clone:SetAttribute("GridZ", d.gridZ)

	if clone:IsA("Model") and clone.PrimaryPart then
		clone:SetPrimaryPartCFrame(finalCF)
	elseif clone:IsA("BasePart") then
		clone.CFrame = finalCF
	end
	for _, p in ipairs(clone:GetDescendants()) do
		if p:IsA("BasePart") then p.CanQuery = false end
	end
	clone.Parent = zoneFolder

	-- Attach the same ad (leave your random ad code untouched)
	local adsPart = clone:FindFirstChild("ADS", true)
	if adsPart and d.adName then
		-- tiny helper to attach a specific ad
		local adAsset = BuildingMasterList.getBuildingByName(d.adName)
		if adAsset and not (adAsset.stages and adAsset.stages.Stage3) then
			adAsset.stages = BuildingMasterList.loadBuildingStages("Road","Default", d.adName)
		end
		if adAsset and adAsset.stages and adAsset.stages.Stage3 then
			local adClone = adAsset.stages.Stage3:Clone()
			adClone.Name = d.adName
			adClone:SetAttribute("AdName", d.adName)
			clone:SetAttribute("AdName", d.adName)
			adClone.CFrame = adsPart.CFrame
			adClone.Parent = clone
		else
			warn("[recreateStraightDecoration] Missing ad asset for:", d.adName)
		end
	end
end

function RoadGeneratorModule.recreateZoneExact(player, zoneId, mode, snapshot)
	
	-- ===== guards / inputs ======================================================
	if not (snapshot and snapshot.segments and #snapshot.segments > 0) then
		warn("[recreateZoneExact] Empty snapshot for ".. tostring(zoneId) .." – falling back to procedural.")
		local zd = ZoneTrackerModule.getZoneById(player, zoneId)
		local gridList = zd and zd.gridList or {}
		return RoadGeneratorModule.populateZone(player, zoneId, mode, gridList, nil)
	end

	-- Mark this zone as in-flight to prevent concurrent populates on same cells
	ZoneTrackerModule.setZonePopulating(player, zoneId, true)

	-- Build coord list from snapshot for conflict/cleanup
	local coordsForAdj, hostYawByCell = {}, {}
	for _, seg in ipairs(snapshot.segments) do
		coordsForAdj[#coordsForAdj+1] = { x = seg.gridX, z = seg.gridZ }
	end

	-- Reservation (roads only block roads) — use coordsForAdj (NOT gridList)
	local _roadReserve = nil
	if #coordsForAdj > 0 then
		_roadReserve = select(1, GridUtils.reserveArea(player, zoneId, "road", coordsForAdj, { ttl = 20.0 }))
		if not _roadReserve then
			local tries = 0
			while tries < 5 do
				task.wait(0.2); tries += 1
				_roadReserve = select(1, GridUtils.reserveArea(player, zoneId, "road", coordsForAdj, { ttl = 20.0 }))
				if _roadReserve then break end
			end
			if not _roadReserve then
				warn(("[RoadGen] %s recreate: could not obtain reservation; proceeding best-effort"):format(zoneId))
			end
		end
	end

	-- Helper to ensure we always clean up reservation + flag before returning
	local function _cleanupAndReturn()
		if _roadReserve then GridUtils.releaseReservation(_roadReserve) end
		ZoneTrackerModule.setZonePopulating(player, zoneId, false)
		return
	end

	-- Clear any stale occupants from *this* zone footprint (zone/building legacy-safe)
	if #coordsForAdj > 0 then
		ZoneTrackerModule.forceClearZoneFootprint(player, zoneId, coordsForAdj)
	end

	-- Kill old visuals folder if present to ensure idempotent re-place
	do
		local plot = Workspace.PlayerPlots:FindFirstChild("Plot_" .. player.UserId)
		if plot then
			local roadsFolder = plot:FindFirstChild("Roads")
			if roadsFolder then
				local zf = roadsFolder:FindFirstChild(zoneId)
				if zf then zf:Destroy() end
			end
		end
	end

	-- ===== local helpers (safe fallbacks) =======================================
	local function _norm360(d)
		d = (tonumber(d) or 0) % 360
		if d < 0 then d = d + 360 end
		return d
	end

	local function _applyOffset(assetName, yaw)
		if type(withAssetOffset) == "function" then
			return _norm360(withAssetOffset(assetName, yaw))
		end
		return _norm360(yaw or 0)
	end

	local function _dprint(...)
		if DEBUG_LOGS or DEBUG_ROAD_ROTATION then
			print("[recreateZoneExact]", ...)
		end
	end

	-- ===== 1) Lay segments exactly as captured (use recorded world yaw verbatim) =====
	table.clear(hostYawByCell)
	for _, seg in ipairs(snapshot.segments) do
		local yawRecorded = _norm360(tonumber(seg.rotation) or 0)  -- world yaw we captured
		local s = {
			roadName = seg.roadName,
			rotation = yawRecorded,
			gridX    = seg.gridX,
			gridZ    = seg.gridZ,
			timePlaced = seg.timePlaced,
			_rotationIsApplied = true, -- << tells regenerateRoadSegment NOT to add asset offset again
		}
		RoadGeneratorModule.regenerateRoadSegment(player, zoneId, mode, s)

		-- Use the recorded world yaw as the host yaw for deco transforms
		hostYawByCell[("%d,%d"):format(seg.gridX, seg.gridZ)] = yawRecorded
	end

	-- ===== 2) Register with pathing so adjacency matches the exact layout =======
	if #coordsForAdj > 0 then
		PathingModule.registerRoad(zoneId, mode, coordsForAdj, coordsForAdj[1], coordsForAdj[#coordsForAdj], player and player.UserId)
	end

	-- ===== 3) Recreate intersection decorations ================================
	for _, d in ipairs(snapshot.interDecos or {}) do
		local hostYaw = hostYawByCell[("%d,%d"):format(d.gridX, d.gridZ)] or 0
		RoadGeneratorModule.recreateIntersectionDecoration(player, zoneId, hostYaw, d)
	end

	-- ===== 4) Recreate straight-road decorations (with same ad) ================
	for _, d in ipairs(snapshot.strDecos or {}) do
		local hostYaw = hostYawByCell[("%d,%d"):format(d.gridX, d.gridZ)] or 0
		RoadGeneratorModule.recreateStraightDecoration(player, zoneId, hostYaw, d)
	end

	-- ===== 4.5) Align models immediately via intersection updater ===============
	do
		local plot = Workspace.PlayerPlots:FindFirstChild("Plot_" .. player.UserId)
		if plot then
			local roadsFolder = plot:FindFirstChild("Roads")
			if roadsFolder then
				local placed = {}
				for _, seg in ipairs(snapshot.segments) do
					local yawApplied = _applyOffset(seg.roadName or "Road", seg.rotation or 0)
					placed[#placed+1] = {
						roadName = seg.roadName,
						rotation = yawApplied, -- feed the applied yaw
						gridX    = seg.gridX,
						gridZ    = seg.gridZ,
					}
				end
				--RoadGeneratorModule.updateIntersections(zoneId, placed, roadsFolder, { noDecorations = true })
			end
		end
	end

	-- ===== 5) Notify & re-snapshot (in case assets add attributes at load) =====
	zonePopulatedEvent:Fire(player, zoneId, coordsForAdj)
	local fresh = RoadGeneratorModule.captureRoadZoneSnapshot(player, zoneId)
	RoadGeneratorModule.saveSnapshot(player, zoneId, fresh)

	-- Mark lifecycle flags to keep downstream systems happy (undo/redo/load)
	ZoneTrackerModule.setZonePopulated(player, zoneId, true)
	if _roadReserve then GridUtils.releaseReservation(_roadReserve) end
	ZoneTrackerModule.setZonePopulating(player, zoneId, false)
end


-- REMOVE ROAD
function RoadGeneratorModule.removeRoad(player, zoneId)
	local plotName   = "Plot_" .. player.UserId
	local playerPlot = Workspace.PlayerPlots:FindFirstChild(plotName)
	if not playerPlot then
		warn("Could not find plot for player:", plotName)
		return
	end

	local roadsFolder = playerPlot:FindFirstChild("Roads")
	if not roadsFolder then return end

	local zoneFolder = roadsFolder:FindFirstChild(zoneId)
	if not zoneFolder then return end

	-- Optional: track cells we truly removed (in case you want a localized recalc)
	-- local removedCells = {}

	for _, child in ipairs(zoneFolder:GetChildren()) do
		if (child:IsA("Model") or child:IsA("BasePart"))
			and child:GetAttribute("ZoneId") == zoneId
		then
			-- 0) Skip decorations entirely – they were never marked as "road" occupants
			if child:GetAttribute("IsRoadDecoration") == true then
				if DEBUG_LOGS then
					print(("[RoadRemove] skipping decoration %s @ (%s,%s)")
						:format(child.Name, tostring(child:GetAttribute("GridX")), tostring(child:GetAttribute("GridZ"))))
				end
				child:Destroy()
				continue
			end

			-- 0.5) Skip hidden duplicates (the visible piece already owns the occId)
			if child:GetAttribute("IsHiddenByIntersection") == true then
				if DEBUG_LOGS then
					print(("[RoadRemove] skipping hidden duplicate %s @ (%s,%s)")
						:format(child.Name, tostring(child:GetAttribute("GridX")), tostring(child:GetAttribute("GridZ"))))
				end
				child:Destroy()
				continue
			end

			------------------------------------------------------------------
			-- 1) Read grid coordinates (only unmark if we actually have them)
			------------------------------------------------------------------
			local gx = tonumber(child:GetAttribute("GridX"))
			local gz = tonumber(child:GetAttribute("GridZ"))

			if gx and gz then
				local occId = ("%s_road_%d_%d"):format(zoneId, gx, gz)

				-- (optional) If you maintain a quadtree remove API, do it here:
				-- QuadtreeService:remove(occId)

				------------------------------------------------------------------
				-- 2) Pop the “road” occupant off the stack
				------------------------------------------------------------------
				if DEBUG_LOGS then
					print(("[RoadRemove] unmark road occId=%s @ (%d,%d)"):format(occId, gx, gz))
				end
				ZoneTrackerModule.unmarkGridOccupied(player, gx, gz, "road", occId)

				-- table.insert(removedCells, { x = gx, z = gz })
			else
				-- No coordinates – just destroy without trying to unmark
				if DEBUG_LOGS then
					print(("[RoadRemove] %s lacks GridX/GridZ; destroying without unmark"):format(child.Name))
				end
			end

			------------------------------------------------------------------
			-- 3) Finally kill the visual object
			------------------------------------------------------------------
			child:Destroy()
		end
	end

	-- If the zone folder is empty, clean it up
	if #zoneFolder:GetChildren() == 0 then
		zoneFolder:Destroy()
	end
	
	if BuildingGeneratorModule and BuildingGeneratorModule.removeRefillPlacementsForOverlay then
		BuildingGeneratorModule.removeRefillPlacementsForOverlay(player, zoneId)
	end

	-- Restore layers removed during road placement
	LayerManagerModule.restoreRemovedObjects(player, zoneId, "NatureZones", "NatureZones")
	LayerManagerModule.restoreRemovedObjects(player, zoneId, "Buildings",   "Buildings")

	-- NEW: restore suppressed power poles for this road and rebuild ropes
	LayerManagerModule.restoreRemovedObjects(player, zoneId, "PowerLines",  "PowerLines")
	if PowerGeneratorModule2 and PowerGeneratorModule2.reviveSuppressedPolesForRoad then
		PowerGeneratorModule2.reviveSuppressedPolesForRoad(player, zoneId)
	else
		-- fallback: rebuild all ropes if the targeted helper isn't available
		if PowerGeneratorModule2 and PowerGeneratorModule2.rebuildRopesForAll then
			PowerGeneratorModule2.rebuildRopesForAll(player)
		end
	end
	
	debugPrint("Removed roads for zone:", zoneId)
	refreshRoadStartTransparency(player)
end


return RoadGeneratorModule
