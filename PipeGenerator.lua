local PipeGeneratorModule = {}
PipeGeneratorModule.__index = PipeGeneratorModule

---------------------------------------------------------------------
--  Services & shared modules
---------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local QuadtreeService   = require(ReplicatedStorage.Scripts.Optimize.Quadtree.QuadTreeSvc)
-- local CoroutineService   = require(ReplicatedStorage.Scripts.Optimize.Coroutine.CoroutineSvc)  -- (loaded but unused; kept to avoid reshuffle)
local BuildingManager   = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("BuildingManager")
local BuildingMasterList= require(BuildingManager:WaitForChild("BuildingMasterList"))

local Build             = script.Parent.Parent.Parent
local Zones             = Build:WaitForChild("Zones")
local ZoneManager       = Zones:WaitForChild("ZoneManager")
local ZoneTrackerModule = require(ZoneManager:WaitForChild("ZoneTracker"))

local GridConf          = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Grid")
local GridUtils         = require(GridConf:WaitForChild("GridUtil"))
local GridConfig        = require(GridConf:WaitForChild("GridConfig"))

local plots             = Workspace:FindFirstChild("PlayerPlots")

-- Events
local BE                = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents")
local zoneRemovedEvent  = BE:WaitForChild("ZoneRemoved")
local zonePopulatedEvent= (BE:FindFirstChild("ZonePopulated") or Instance.new("BindableEvent", BE))
zonePopulatedEvent.Name = "ZonePopulated"

---------------------------------------------------------------------
--  Config / constants
---------------------------------------------------------------------
-- Force a single global Y for all pipe pieces, independent of terrain/gb
local Y_TARGET            = 1.4           -- <— ALWAYS land here
local OCCUPANT_TYPE       = "water"       -- distinct occupant type for ZoneTracker
local ZONE_TYPE           = "WaterPipe"   -- must match OverlapExclusions in BuildingGenerator
local RES_TTL             = 8.0           -- seconds for per-cell reservation
local BUILD_INTERVAL      = 0.05          -- gentle yield between placements

-- Asset locations (kept as-is per your project)
--  - WaterPipe4 : 4-way/cross piece
--  - WaterPipe  : 1x straight (we rotate for X-axis)
local PIPE4_PATH = ReplicatedStorage:WaitForChild("FuncTestGroundRS").Buildings.Individual.Default.Water:WaitForChild("WaterPipe4")
local PIPE1_PATH = ReplicatedStorage:WaitForChild("FuncTestGroundRS").Buildings.Individual.Default.Water:WaitForChild("WaterPipe")

---------------------------------------------------------------------
--  Global-bounds cache per plot (same pattern you use elsewhere)
---------------------------------------------------------------------
local _boundsCachePipes = {}
local function getGlobalBoundsForPlot_Pipes(plot)
	local cached = _boundsCachePipes[plot]
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
	_boundsCachePipes[plot] = { bounds = gb, terrains = terrains }
	return gb, terrains
end

---------------------------------------------------------------------
--  Internal helpers
---------------------------------------------------------------------
local function _uid(p) return p and p.UserId end
local function _occId(zoneId, gx, gz) return ("%s_pipe_%d_%d"):format(zoneId, gx, gz) end

-- Preserve rotation, overwrite Y translation
local function _withY(cf: CFrame, y: number): CFrame
	local pos = cf.Position
	return CFrame.new(pos.X, y, pos.Z) * (cf - cf.Position)
end

-- Idempotent per-zone pre-clear: remove visuals + zone/quad occupancy for this zone only
local function _clearZoneFolderAndFootprint(player, zoneId, zoneFolder)
	-- Best-effort: remove any existing instances and unmark their occupancy
	for _, child in ipairs(zoneFolder:GetChildren()) do
		local gx   = tonumber(child:GetAttribute("GridX"))
		local gz   = tonumber(child:GetAttribute("GridZ"))
		local occId= child:GetAttribute("OccId")
		if gx and gz and occId then
			pcall(function()
				ZoneTrackerModule.unmarkGridOccupied(player, gx, gz, OCCUPANT_TYPE, occId)
			end)
			if QuadtreeService and typeof(QuadtreeService.removeById) == "function" then
				pcall(function() QuadtreeService:removeById(occId) end)
			end
		end
		child:Destroy()
	end
end

-- Return world position for the grid cell; we clamp Y to Y_TARGET explicitly
local function _cellWorldCenter(plot, gx, gz, gb, terrains)
	local wx, _, wz = GridUtils.globalGridToWorldPosition(gx, gz, gb, terrains)
	return Vector3.new(wx, Y_TARGET, wz)
end

-- Place a single pipe segment model at a world position, stamp attrs, and mark occupancy
local function _placeSegment(player, zoneId, zoneFolder, prefab, worldPos, gx, gz)
	local seg = prefab:Clone()
	seg.Name = prefab.Name
	seg:SetAttribute("ZoneId", zoneId)
	seg:SetAttribute("GridX",  gx)
	seg:SetAttribute("GridZ",  gz)
	local occId = _occId(zoneId, gx, gz)
	seg:SetAttribute("OccId",  occId)

	-- Position (supports Model or Part)
	if seg:IsA("Model") then
		if seg.PrimaryPart then
			seg:SetPrimaryPartCFrame(_withY(CFrame.new(worldPos), Y_TARGET))
		else
			seg:PivotTo(_withY(CFrame.new(worldPos), Y_TARGET))
		end
	else
		seg.Position = Vector3.new(worldPos.X, Y_TARGET, worldPos.Z)
	end
	seg.Parent = zoneFolder

	-- Quadtree + Occupancy
	pcall(function()
		if QuadtreeService and typeof(QuadtreeService.insert) == "function" then
			QuadtreeService:insert({ id = occId, x = gx, y = gz, width = 1, height = 1, zoneId = zoneId })
		end
	end)
	ZoneTrackerModule.markGridOccupied(player, gx, gz, OCCUPANT_TYPE, occId, ZONE_TYPE)

	return seg
end

-- Reserve a single cell with overlay-friendly semantics (building ↔ water coexist)
local function _reserveCell(player, zoneId, gx, gz)
	if type(GridUtils.reserveArea) ~= "function" then
		return true, nil -- Reservation layer not present → proceed permissively
	end
	local cells = { { x = gx, z = gz } }
	local handle, reason = GridUtils.reserveArea(player, zoneId, OCCUPANT_TYPE, cells, { ttl = RES_TTL })
	return handle, reason
end

local function _releaseHandle(handle)
	if handle and type(GridUtils.releaseReservation) == "function" then
		GridUtils.releaseReservation(handle)
	end
end

---------------------------------------------------------------------
--  Public: remove every piece under plot/Pipes/<zoneId> + occupancy
---------------------------------------------------------------------
function PipeGeneratorModule.removePipeZone(player, zoneId)
	local myPlot = plots and plots:FindFirstChild("Plot_" .. _uid(player))
	if not myPlot then return end

	local pipesFolder = myPlot:FindFirstChild("Pipes"); if not pipesFolder then return end
	local zoneFolder  = pipesFolder:FindFirstChild(zoneId); if not zoneFolder then return end

	_clearZoneFolderAndFootprint(player, zoneId, zoneFolder)
	zoneFolder:Destroy()
end

-- Wire cleanup to ZoneRemoved (signature often includes more args; we only use first two)
zoneRemovedEvent.Event:Connect(function(player, zoneId)
	if player and zoneId then
		PipeGeneratorModule.removePipeZone(player, zoneId)
	end
end)

---------------------------------------------------------------------
--  Public: generatePipe – overlay-friendly, idempotent per zone
--  pathCoords: array of {x=int, z=int}
---------------------------------------------------------------------
function PipeGeneratorModule.generatePipe(player, zoneId, mode, pathCoords)
	-- Validate / locate plot
	local myPlot = plots and plots:FindFirstChild("Plot_" .. _uid(player))
	if not myPlot then return end

	-- Container: Plot/Pipes/<zoneId>
	local pipesFolder = myPlot:FindFirstChild("Pipes")
	if not pipesFolder then
		pipesFolder      = Instance.new("Folder")
		pipesFolder.Name = "Pipes"
		pipesFolder.Parent = myPlot
	end

	local zoneFolder = pipesFolder:FindFirstChild(zoneId)
	if not zoneFolder then
		zoneFolder      = Instance.new("Folder")
		zoneFolder.Name = zoneId
		zoneFolder.Parent = pipesFolder
	else
		-- Idempotency: clean out existing visuals+occupancy for this zone
		_clearZoneFolderAndFootprint(player, zoneId, zoneFolder)
	end

	-- Terrain and bounds
	local terrain = myPlot:FindFirstChild("TestTerrain")
	if not terrain then
		warn("PipeGeneratorModule: 'TestTerrain' not found in plot.")
		zonePopulatedEvent:Fire(player, zoneId, {})
		return
	end
	local gb, terrains = getGlobalBoundsForPlot_Pipes(myPlot)

	-- Pipe assets
	local pipeData4 = PIPE4_PATH
	local pipeData1 = PIPE1_PATH
	if not pipeData4 or not pipeData1 then
		warn("PipeGeneratorModule: Pipe assets missing (WaterPipe4 / WaterPipe).")
		zonePopulatedEvent:Fire(player, zoneId, {})
		return
	end

	local PathSet = {}
	for _, c in ipairs(pathCoords) do
		PathSet[Vector3.new(c.x, 0, c.z)] = true
	end

	-----------------------------------------------------------------
	-- First pass: one segment per cell (use 4-way as temp, then normalize)
	-----------------------------------------------------------------
	local placedList = {}
	for _, coord in ipairs(pathCoords) do
		-- Reserve cell in overlay-friendly way; water vs building never blocks
		local handle = select(1, _reserveCell(player, zoneId, coord.x, coord.z))
		if handle then
			local key = Vector3.new(coord.x, 0, coord.z)
			local L = PathSet[Vector3.new(coord.x - 1, 0, coord.z)] or false
			local R = PathSet[Vector3.new(coord.x + 1, 0, coord.z)] or false
			local F = PathSet[Vector3.new(coord.x, 0, coord.z + 1)] or false
			local B = PathSet[Vector3.new(coord.x, 0, coord.z - 1)] or false

			-- Decide if this cell is a straight (neighbors only along one axis)
			local goSingle = false
			if (L or R) and (not F and not B) then
				goSingle = true
			elseif (F or B) and (not L and not R) then
				goSingle = true
			end

			local pos = _cellWorldCenter(myPlot, coord.x, coord.z, gb, terrains)

			if goSingle then
				-- Pick straight and orient on the X or Z axis
				local seg = pipeData1:Clone()
				seg.Name = "WaterPipe"
				seg:SetAttribute("ZoneId", zoneId)
				seg:SetAttribute("GridX",  coord.x)
				seg:SetAttribute("GridZ",  coord.z)
				seg:SetAttribute("OccId",  _occId(zoneId, coord.x, coord.z))

				if seg:IsA("Model") then
					-- X-axis needs a 90° yaw; Z-axis stays default
					local base = _withY(CFrame.new(pos), Y_TARGET)
					if (L or R) and not (F or B) then
						seg:PivotTo(base * CFrame.Angles(0, math.rad(90), 0))
					else
						seg:PivotTo(base)
					end
				else
					seg.Position = Vector3.new(pos.X, Y_TARGET, pos.Z)
				end
				seg.Parent = zoneFolder

				-- Mark + quadtree like _placeSegment
				pcall(function()
					if QuadtreeService and typeof(QuadtreeService.insert) == "function" then
						QuadtreeService:insert({ id = seg:GetAttribute("OccId"), x = coord.x, y = coord.z, width = 1, height = 1, zoneId = zoneId })
					end
				end)
				ZoneTrackerModule.markGridOccupied(player, coord.x, coord.z, OCCUPANT_TYPE, seg:GetAttribute("OccId"), ZONE_TYPE)
				placedList[#placedList+1] = seg
			else
				-- Junction / corner placeholder → use 4-way
				local seg = _placeSegment(player, zoneId, zoneFolder, pipeData4, pos, coord.x, coord.z)
				placedList[#placedList+1] = seg
			end

			_releaseHandle(handle)
			task.wait(BUILD_INTERVAL)
		end
	end

	-----------------------------------------------------------------
	-- Build coord→model map for neighborhood normalization
	-----------------------------------------------------------------
	local PipesByCoord = {}
	for _, m in ipairs(zoneFolder:GetChildren()) do
		local gx = tonumber(m:GetAttribute("GridX"))
		local gz = tonumber(m:GetAttribute("GridZ"))
		if gx and gz then
			PipesByCoord[Vector3.new(gx, 0, gz)] = m
		end
	end

	-- Neighborhood set = path + 4-neighbors
	local CheckPathCoords = {}
	for _, c in ipairs(pathCoords) do
		local key = Vector3.new(c.x, 0, c.z)
		CheckPathCoords[key] = true
		CheckPathCoords[key + Vector3.new(-1, 0,  0)] = true
		CheckPathCoords[key + Vector3.new( 1, 0,  0)] = true
		CheckPathCoords[key + Vector3.new( 0, 0, -1)] = true
		CheckPathCoords[key + Vector3.new( 0, 0,  1)] = true
	end

	-----------------------------------------------------------------
	-- Normalize: swap 4-way ↔ straight where appropriate
	--   - straight (single) when exactly one axis has neighbors (L/R XOR F/B)
	--   - keep 4-way otherwise (acts as junction/corner placeholder)
	-----------------------------------------------------------------
	for coordVec3, _ in pairs(CheckPathCoords) do
		local model = PipesByCoord[coordVec3]
		if not model then continue end

		local L = PipesByCoord[coordVec3 + Vector3.new(-1, 0, 0)]
		local R = PipesByCoord[coordVec3 + Vector3.new( 1, 0, 0)]
		local F = PipesByCoord[coordVec3 + Vector3.new( 0, 0, 1)]
		local B = PipesByCoord[coordVec3 + Vector3.new( 0, 0,-1)]

		local goSingle = false
		if (L or R) and (not F and not B) then
			goSingle = true
		elseif (F or B) and (not L and not R) then
			goSingle = true
		end

		local gx   = tonumber(model:GetAttribute("GridX"))
		local gz   = tonumber(model:GetAttribute("GridZ"))
		local occId= model:GetAttribute("OccId")

		if model.Name == "WaterPipe4" and goSingle then
			local isXAxis = (L or R) and not (F or B)
			local replacement = pipeData1:Clone()
			replacement.Name = "WaterPipe"
			replacement:SetAttribute("ZoneId", zoneId)
			replacement:SetAttribute("GridX",  gx)
			replacement:SetAttribute("GridZ",  gz)
			replacement:SetAttribute("OccId",  occId)

			local pivot = model:GetPivot()
			local base  = _withY(pivot, Y_TARGET)
			if isXAxis then
				replacement:PivotTo(base * CFrame.Angles(0, math.rad(90), 0))
			else
				replacement:PivotTo(base)
			end
			replacement.Parent = model.Parent
			PipesByCoord[coordVec3] = replacement
			model:Destroy()

		elseif model.Name == "WaterPipe" and not goSingle then
			local replacement = pipeData4:Clone()
			replacement.Name = "WaterPipe4"
			replacement:SetAttribute("ZoneId", zoneId)
			replacement:SetAttribute("GridX",  gx)
			replacement:SetAttribute("GridZ",  gz)
			replacement:SetAttribute("OccId",  occId)

			replacement:PivotTo(_withY(model:GetPivot(), Y_TARGET))
			replacement.Parent = model.Parent
			PipesByCoord[coordVec3] = replacement
			model:Destroy()
		end
	end

	-----------------------------------------------------------------
	-- Final snap: hard-clamp every child to Y_TARGET (defensive)
	-----------------------------------------------------------------
	for _, m in ipairs(zoneFolder:GetChildren()) do
		if m:IsA("Model") then
			m:PivotTo(_withY(m:GetPivot(), Y_TARGET))
		elseif m:IsA("BasePart") then
			local p = m.Position
			m.Position = Vector3.new(p.X, Y_TARGET, p.Z)
		end
	end

	zonePopulatedEvent:Fire(player, zoneId, (function()
		-- return a compact record like your other generators
		local out = {}
		for _, m in ipairs(zoneFolder:GetChildren()) do
			local gx = m:GetAttribute("GridX")
			local gz = m:GetAttribute("GridZ")
			out[#out+1] = { lineName = m.Name, gridX = gx, gridZ = gz }
		end
		return out
	end)())
end

return PipeGeneratorModule