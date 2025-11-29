local LayerManager = {}

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")
local GridFolder = ScriptsFolder:WaitForChild("Grid")
local GridConfig = require(GridFolder:WaitForChild("GridConfig"))

local Build = ServerScriptService:WaitForChild("Build")
local Zones = Build:WaitForChild("Zones")
local ZoneManager = Zones:WaitForChild("ZoneManager")
local ZoneTrackerModule = require(ZoneManager:WaitForChild("ZoneTracker"))

local GRID_SIZE = GridConfig.GRID_SIZE or 1

-- Track removed objects per player/session to avoid cross-player leakage
-- Shape: _removedByOwner[ownerKey][zoneId][objectType] = { records }
local _removedByOwner : { [string]: { [string]: { [string]: { [number]: table } } } } = {}

local function _ownerKey(player: Player?, zoneId: string?)
	if player and player.UserId then
		return tostring(player.UserId)
	end
	if type(zoneId) == "string" then
		-- Common zone id patterns: "Zone_<uid>_<n>", "RoadZone_<uid>_<n>", "PowerLinesZone_<uid>_<n>"
		local m = zoneId:match("_(%d+)_")
		if not m then
			m = zoneId:match("(%d+)")
		end
		if m then
			return m
		end
	end
	return "__global"
end

local function _ensureOwnerBucket(player: Player?, zoneId: string?)
	local key = _ownerKey(player, zoneId)
	_removedByOwner[key] = _removedByOwner[key] or {}
	return _removedByOwner[key], key
end

local function getPlayerPlot(player: Player): Instance?
	if not player then return nil end
	local plots = Workspace:FindFirstChild("PlayerPlots")
	if not plots then return nil end
	return plots:FindFirstChild("Plot_" .. player.UserId)
end

local function resolveParent(player: Player, containerName: string?, record: table): Instance?
	if record.originalParent and record.originalParent.Parent then
		return record.originalParent
	end

	local plot = getPlayerPlot(player)
	if not plot then
		return nil
	end

	local parentName = record.parentName
	if typeof(containerName) == "string" and containerName ~= "" then
		if containerName == "Buildings" then
			local buildings = plot:FindFirstChild("Buildings")
			if buildings then
				local populated = buildings:FindFirstChild("Populated")
				if parentName and populated then
					local zoneFolder = populated:FindFirstChild(parentName)
					if zoneFolder then
						return zoneFolder
					end
				end
				if populated then
					return populated
				end
				return buildings
			end
		else
			local folder = plot:FindFirstChild(containerName)
			if folder then
				if parentName and folder:FindFirstChild(parentName) then
					return folder:FindFirstChild(parentName)
				end
				return folder
			end
		end
	end

	if parentName and plot:FindFirstChild(parentName, true) then
		return plot:FindFirstChild(parentName, true)
	end

	return plot
end

local function applyTransform(instanceClone: Instance, record: table)
	if not instanceClone or not record then return end
	if record.cframe then
		if instanceClone:IsA("Model") then
			local ok, err = pcall(function()
				instanceClone:PivotTo(record.cframe)
			end)
			if not ok then
				warn("[LayerManager] PivotTo failed:", err)
			end
		elseif instanceClone:IsA("BasePart") then
			instanceClone.CFrame = record.cframe
		end
	end
end

local function applyAttributes(instanceClone: Instance, record: table)
	if not instanceClone or not record then return end

	local function setAttr(attrName: string, value: any)
		if value ~= nil and instanceClone.SetAttribute then
			instanceClone:SetAttribute(attrName, value)
		end
	end

	setAttr("GridX", record.gridX)
	setAttr("GridZ", record.gridZ)
	setAttr("ZoneId", record.zoneId)
	setAttr("RotationY", record.rotation or record.rotationY)
	setAttr("WealthState", record.wealthState)
	setAttr("IsUtility", record.isUtility)
end

local function computeFootprint(record: table): (number?, number?)
	if not record or record.footprintWidth or record.footprintDepth then
		return record and record.footprintWidth, record and record.footprintDepth
	end

	if record.occupantType ~= "building" then
		return nil, nil
	end

	local clone = record.instanceClone
	if not clone then
		return nil, nil
	end

	local size: Vector3? = nil
	if clone:IsA("Model") then
		local _, bbox = clone:GetBoundingBox()
		size = bbox
	elseif clone:IsA("BasePart") then
		size = clone.Size
	end

	if not size then
		return nil, nil
	end

	local width = math.max(1, math.floor((size.X / GRID_SIZE) + 0.5))
	local depth = math.max(1, math.floor((size.Z / GRID_SIZE) + 0.5))
	return width, depth
end

local function applyOccupancy(player: Player, record: table)
	if not record then return end
	local occupantType = record.occupantType
	local occupantId = record.occupantId
	if type(occupantType) ~= "string" or type(occupantId) ~= "string" then
		local clone = record.instanceClone
		if clone and clone.GetAttribute then
			if record.objectType == "PowerLines" then
				occupantType = occupantType or "power"
				local zoneIdAttr = record.zoneId or clone:GetAttribute("ZoneId")
				local gxAttr     = record.gridX or clone:GetAttribute("GridX")
				local gzAttr     = record.gridZ or clone:GetAttribute("GridZ")
				if zoneIdAttr then zoneIdAttr = tostring(zoneIdAttr) end
				if typeof(gxAttr) == "number" and typeof(gzAttr) == "number" and zoneIdAttr then
					occupantId     = occupantId or string.format("%s_power_%d_%d", zoneIdAttr, gxAttr, gzAttr)
					record.gridX   = record.gridX or gxAttr
					record.gridZ   = record.gridZ or gzAttr
					record.zoneId  = record.zoneId or zoneIdAttr
				end

			elseif record.objectType == "WaterPipe" then
				occupantType = occupantType or "pipe"
				local zoneIdAttr = record.zoneId or clone:GetAttribute("ZoneId")
				local gxAttr     = record.gridX or clone:GetAttribute("GridX")
				local gzAttr     = record.gridZ or clone:GetAttribute("GridZ")
				if zoneIdAttr then zoneIdAttr = tostring(zoneIdAttr) end
				if typeof(gxAttr) == "number" and typeof(gzAttr) == "number" and zoneIdAttr then
					occupantId     = occupantId or string.format("%s_pipe_%d_%d", zoneIdAttr, gxAttr, gzAttr)
					record.gridX   = record.gridX or gxAttr
					record.gridZ   = record.gridZ or gzAttr
					record.zoneId  = record.zoneId or zoneIdAttr
				end

			elseif record.objectType == "MetroTunnel" then
				occupantType = occupantType or "metro"
				local zoneIdAttr = record.zoneId or clone:GetAttribute("ZoneId")
				local gxAttr     = record.gridX or clone:GetAttribute("GridX")
				local gzAttr     = record.gridZ or clone:GetAttribute("GridZ")
				if zoneIdAttr then zoneIdAttr = tostring(zoneIdAttr) end
				if typeof(gxAttr) == "number" and typeof(gzAttr) == "number" and zoneIdAttr then
					occupantId     = occupantId or string.format("%s_metro_%d_%d", zoneIdAttr, gxAttr, gzAttr)
					record.gridX   = record.gridX or gxAttr
					record.gridZ   = record.gridZ or gzAttr
					record.zoneId  = record.zoneId or zoneIdAttr
				end

			elseif record.objectType == "Buildings" then
				occupantType = occupantType or "building"
				local zoneIdAttr = record.zoneId or clone:GetAttribute("ZoneId")
				local gxAttr     = record.gridX or clone:GetAttribute("GridX")
				local gzAttr     = record.gridZ or clone:GetAttribute("GridZ")
				if zoneIdAttr then zoneIdAttr = tostring(zoneIdAttr) end
				if typeof(gxAttr) == "number" and typeof(gzAttr) == "number" and zoneIdAttr then
					occupantId     = occupantId or string.format("%s_%d_%d", zoneIdAttr, gxAttr, gzAttr)
					record.gridX   = record.gridX or gxAttr
					record.gridZ   = record.gridZ or gzAttr
					record.zoneId  = record.zoneId or zoneIdAttr
				end
			end
		end
	end

	if type(occupantType) ~= "string" or type(occupantId) ~= "string" then
		return
	end

	local gridX, gridZ = record.gridX, record.gridZ
	if type(gridX) ~= "number" or type(gridZ) ~= "number" then
		return
	end

	record.occupantType = occupantType
	record.occupantId = occupantId

	local width, depth = record.footprintWidth, record.footprintDepth
	if not width or not depth then
		width, depth = computeFootprint(record)
	end
	width = width or 1
	depth = depth or 1

	local zoneType = record.mode or record.zoneType or record.objectType
	for x = gridX, gridX + width - 1 do
		for z = gridZ, gridZ + depth - 1 do
			ZoneTrackerModule.markGridOccupied(player, x, z, occupantType, occupantId, zoneType)
		end
	end
end

function LayerManager.storeRemovedObject(objectType: string, zoneId: string, data: table, player: Player?)
	if type(objectType) ~= "string" or type(zoneId) ~= "string" then
		warn("[LayerManager] storeRemovedObject requires objectType and zoneId strings")
		return
	end
	if type(data) ~= "table" then
		warn("[LayerManager] storeRemovedObject requires a data table")
		return
	end
	local clone = data.instanceClone
	if typeof(clone) ~= "Instance" then
		warn("[LayerManager] storeRemovedObject missing instanceClone for", objectType, zoneId)
		return
	end

	clone.Parent = nil

	local record = {}
	for k, v in pairs(data) do
		record[k] = v
	end
	record.objectType = objectType
	record.footprintWidth = record.footprintWidth or data.footprintWidth
	record.footprintDepth = record.footprintDepth or data.footprintDepth

	if record.occupantType == "building" then
		local width, depth = computeFootprint(record)
		record.footprintWidth = record.footprintWidth or width
		record.footprintDepth = record.footprintDepth or depth
	end

	local ownerBucket = _ensureOwnerBucket(player, zoneId)

	ownerBucket[zoneId] = ownerBucket[zoneId] or {}
	local byType = ownerBucket[zoneId]
	byType[objectType] = byType[objectType] or {}
	table.insert(byType[objectType], record)
end

function LayerManager.restoreRemovedObjects(player: Player, zoneId: string, objectType: string, containerName: string?)
	if not player or type(zoneId) ~= "string" or type(objectType) ~= "string" then
		return 0
	end

	local ownerKey = _ownerKey(player, zoneId)
	local ownerBucket = _removedByOwner[ownerKey]
	if not ownerBucket then
		return 0
	end

	local zoneBucket = ownerBucket[zoneId]
	if not zoneBucket then
		return 0
	end
	local items = zoneBucket[objectType]
	if not items or #items == 0 then
		return 0
	end

	local restored = 0
	for _, record in ipairs(items) do
		local clone = record.instanceClone
		if clone and clone.Parent == nil then
			local parent = resolveParent(player, containerName, record)
			if parent then
				clone.Parent = parent
				applyAttributes(clone, record)
				applyTransform(clone, record)
				applyOccupancy(player, record)
				restored += 1
			else
				warn(string.format("[LayerManager] No parent found for restored %s in zone %s", objectType, zoneId))
				clone:Destroy()
			end
		end
	end

	zoneBucket[objectType] = nil
	if not next(zoneBucket) then
		ownerBucket[zoneId] = nil
	end
	if not next(ownerBucket) then
		_removedByOwner[ownerKey] = nil
	end

	return restored
end

function LayerManager.clearZone(zoneId: string, player: Player?)
	if type(zoneId) ~= "string" then return end
	local ownerKey = _ownerKey(player, zoneId)
	local ownerBucket = _removedByOwner[ownerKey]
	if not ownerBucket then return end

	ownerBucket[zoneId] = nil
	if not next(ownerBucket) then
		_removedByOwner[ownerKey] = nil
	end
end

-- Clear all cached removals for a player (used on reload/cleanup)
function LayerManager.clearPlayer(player: Player)
	if not player then return end
	_removedByOwner[tostring(player.UserId)] = nil
end

return LayerManager
