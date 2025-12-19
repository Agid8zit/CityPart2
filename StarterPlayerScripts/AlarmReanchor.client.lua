-- Client-side re-anchoring for UXP alarms (Upgrade/Downgrade/Pollution).
-- Matches the server placement logic in CityInteraction: first try the actual placed instance
-- covering the grid cell, then fall back to the grid/world conversion for the player's plot.
-- Also supports a debug mode that keeps local clones so you can inspect placement even after
-- the server returns parts to its pool.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Scripts = ReplicatedStorage:WaitForChild("Scripts")
local GridFolder = Scripts:WaitForChild("Grid")
local GridConfig = require(GridFolder:WaitForChild("GridConfig"))
local GridUtil = require(GridFolder:WaitForChild("GridUtil"))
local Events = ReplicatedStorage:WaitForChild("Events")
local RemoteEvents = Events:WaitForChild("RemoteEvents")

local LOCAL_PLAYER = Players.LocalPlayer

local ALARM_OFFSET_Y = 6
local POLLUTION_OFFSET_Y = 9
local POLLUTION_TYPES = {
	AlarmPollution = true,
	AlarmPolution  = true,
}

-- Track which plots we've already seeded into GridConfig on the client.
local _configuredPlots: { [Instance]: boolean } = {}

-- Toggleable: when true, keep a local clone of each alarm so you can inspect positions
-- even after the server cleans up. Clones live under Workspace.DebugAlarms and do not replicate.
local DEBUG_STICKY = false
local ALARM_TTL = 0.15 + ((0.25 + 0.25) * 2) + 0.18 + 0.05 -- mirrors server Fx.ALARM_TTL

-- ===== Helpers pulled from CityInteraction (client-safe) =====
local function _findPlotAncestor(inst: Instance?): Instance?
	local current = inst
	while current do
		if current:IsA("Model") or current:IsA("Folder") then
			local name = current.Name
			if current:GetAttribute("IsPlayerPlot") == true or (typeof(name) == "string" and name:match("^Plot_%d+")) then
				return current
			end
		end
		current = current.Parent
	end
	return nil
end

local function _configurePlotGrid(plot: Instance?)
	if not plot or _configuredPlots[plot] then return end

	-- Apply axis directions from attributes (server sets these in PlotAssigner).
	local ax = plot:GetAttribute("GridAxisDirX")
	local az = plot:GetAttribute("GridAxisDirZ")
	if ax == 1 or ax == -1 or az == 1 or az == -1 then
		GridConfig.setAxisDirectionsForPlot(plot, ax or 1, az or 1)
	end

	-- Seed stable anchor from RoadStart if available to mimic server bounds anchor.
	local roadStart = plot:FindFirstChild("RoadStart")
	if roadStart and roadStart:IsA("BasePart") then
		GridConfig.setStableAnchorFromPart(roadStart)
	end

	_configuredPlots[plot] = true
end

local function _collectTerrains(plot: Instance?): { BasePart }
	local terrains = {}
	if not plot then return terrains end
	local unlocks = plot:FindFirstChild("Unlocks")
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
	if #terrains == 0 and testTerrain and testTerrain:IsA("BasePart") then
		table.insert(terrains, testTerrain)
	end
	return terrains
end

local function _getGlobalBoundsForPlot(plot: Instance)
	local terrains = _collectTerrains(plot)
	return GridConfig.calculateGlobalBounds(terrains), terrains
end

local function _gridToWorld(playerPlot: Instance, gx: number, gz: number): Vector3
	local referenceTerrain = playerPlot:FindFirstChild("TestTerrain")
	local gb, terrains = _getGlobalBoundsForPlot(playerPlot)
	local worldX, _, worldZ = GridUtil.globalGridToWorldPosition(gx, gz, gb, terrains)
	local worldY = referenceTerrain and (referenceTerrain.Position.Y + (referenceTerrain.Size.Y / 2)) or 0
	worldY += GridConfig.Y_OFFSET
	return Vector3.new(worldX, worldY, worldZ)
end

local function _aabbContainsXZ(center: Vector3, size: Vector3, p: Vector3): boolean
	return math.abs(p.X - center.X) <= size.X * 0.5
		and math.abs(p.Z - center.Z) <= size.Z * 0.5
end

local function _getTileInstance(zoneModel: Instance?, zoneId: string, gx: number, gz: number, plot: Instance?): Instance?
	if not plot then return nil end
	local tileWorld = _gridToWorld(plot, gx, gz)

	-- Prefer the server's zone model (PlayerZones/<zoneId>) since that's where CityInteraction works.
	local function probeTree(root: Instance?): Instance?
		if not root then return nil end
		for _, inst in ipairs(root:GetDescendants()) do
			if (inst:IsA("Model") or inst:IsA("BasePart")) and (inst:GetAttribute("ZoneId") == zoneId or inst:GetAttribute("ZoneId") == nil) then
				local gxAttr = inst:GetAttribute("GridX")
				local gzAttr = inst:GetAttribute("GridZ")
				if gxAttr == gx and gzAttr == gz then
					return inst
				end
				local cf, size
				if inst:IsA("Model") then
					cf, size = inst:GetBoundingBox()
				else
					cf, size = inst.CFrame, inst.Size
				end
				if cf and size and _aabbContainsXZ(cf.Position, Vector3.new(size.X, 0, size.Z), tileWorld) then
					return inst
				end
			end
		end
		return nil
	end

	local inst = probeTree(zoneModel)
	if inst then return inst end

	-- Fallback: populated Buildings hierarchy (Utilities/roads/etc.).
	local buildings = plot:FindFirstChild("Buildings")
	local populated = buildings and buildings:FindFirstChild("Populated")
	if populated then
		inst = probeTree(populated:FindFirstChild(zoneId)) or probeTree(populated:FindFirstChild("Utilities"))
	end
	return inst
end

local function _tileWorldPos(zoneId: string, gx: number, gz: number, plot: Instance?): Vector3?
	-- zoneModel is PlayerPlots/PlayerZones/<zoneId> (same parent as server alarms).
	local zoneModel = plot and plot:FindFirstChild("PlayerZones") and plot:FindFirstChild("PlayerZones"):FindFirstChild(zoneId)
	local inst = _getTileInstance(zoneModel, zoneId, gx, gz, plot)
	if inst then
		local cf, size
		if inst:IsA("Model") then
			cf, size = inst:GetBoundingBox()
		else
			cf, size = inst.CFrame, inst.Size
		end
		if cf and size then
			local groundY = cf.Position.Y - (size.Y * 0.5) + GridConfig.Y_OFFSET
			return Vector3.new(cf.Position.X, groundY, cf.Position.Z)
		end
	end
	if plot then
		return _gridToWorld(plot, gx, gz)
	end
	return nil
end

-- ===== Alarm positioning =====
local function parseAlarm(part: BasePart): (string?, number?, number?)
	local alarmType, sx, sz = string.match(part.Name, "^(Alarm%u%l+)_([%-]?%d+)_([%-]?%d+)$")
	if not alarmType then return nil, nil, nil end
	return alarmType, tonumber(sx), tonumber(sz)
end

local debugFolder: Folder? = nil
local function ensureDebugFolder()
	if debugFolder and debugFolder.Parent then return debugFolder end
	debugFolder = Workspace:FindFirstChild("DebugAlarms") :: Folder
	if not debugFolder then
		debugFolder = Instance.new("Folder")
		debugFolder.Name = "DebugAlarms"
		debugFolder.Parent = Workspace
	end
	return debugFolder
end

local function snapshotDebug(part: BasePart, pos: Vector3)
	if not DEBUG_STICKY then return end
	local df = ensureDebugFolder()
	local clone = part:Clone()
	clone.Name = part.Name .. "_DEBUG"
	clone.Anchored = true
	clone.CanCollide = false
	clone.Position = pos
	clone.Parent = df
end

-- Local-only alarm pool for client-spawned upgrade/downgrade arrows.
local alarmsRoot = ReplicatedStorage:WaitForChild("FuncTestGroundRS"):WaitForChild("Alarms")
local localPool: { [string]: { BasePart } } = {}
local localFolder: Folder
do
	localFolder = Workspace:FindFirstChild("LocalAlarms") :: Folder
	if not localFolder then
		localFolder = Instance.new("Folder")
		localFolder.Name = "LocalAlarms"
		localFolder.Parent = Workspace
	end
end

-- Cleanup any lingering debug clones if sticky debug is disabled.
if not DEBUG_STICKY then
	local lingering = Workspace:FindFirstChild("DebugAlarms")
	if lingering then
		lingering:Destroy()
	end
end

local function _borrowLocalAlarm(alarmType: string): BasePart?
	localPool[alarmType] = localPool[alarmType] or {}
	local pool = localPool[alarmType]
	local part = table.remove(pool)
	if part and part.Parent then part.Parent = nil end
	if part then return part end

	-- accept either spelling
	local template = alarmsRoot:FindFirstChild(alarmType)
	if not template and alarmType == "AlarmPolution" then
		template = alarmsRoot:FindFirstChild("AlarmPollution")
	elseif not template and alarmType == "AlarmPollution" then
		template = alarmsRoot:FindFirstChild("AlarmPolution")
	end
	if not template or not template:IsA("BasePart") then
		warn("[AlarmReanchor] Missing alarm template:", alarmType)
		return nil
	end
	local clone = template:Clone()
	clone.Anchored = true
	clone.CanCollide = false
	return clone
end

local function _returnLocalAlarm(part: BasePart)
	if not part then return end
	part.Parent = nil
	local alarmType = part.Name:match("^(Alarm%u%l+)")
	if not alarmType then
		part:Destroy()
		return
	end
	localPool[alarmType] = localPool[alarmType] or {}
	table.insert(localPool[alarmType], part)
end

local pending: { [BasePart]: boolean } = {}

local function spawnLocalAlarm(alarmType: string, zoneId: string, gx: number, gz: number, tint: any?)
	-- Only used for upgrade/downgrade pushed via RemoteEvent to keep them client-side.
	local plot = Workspace.PlayerPlots and Workspace.PlayerPlots:FindFirstChild("Plot_" .. LOCAL_PLAYER.UserId)
	if not plot then
		-- last resort: try to walk from zones once they replicate
		plot = _findPlotAncestor(Workspace:FindFirstChild("PlayerZones"))
	end
	if not plot then return end
	_configurePlotGrid(plot)

	local basePos = _tileWorldPos(zoneId, gx, gz, plot)
	if not basePos then return end

	local part = _borrowLocalAlarm(alarmType)
	if not part then return end
	part.Name = string.format("%s_%d_%d", alarmType, gx, gz)

	local offsetY = POLLUTION_TYPES[alarmType] and POLLUTION_OFFSET_Y or ALARM_OFFSET_Y
	local pos = basePos + Vector3.new(0, offsetY, 0)
	part.Position = pos
	part:SetAttribute("BobBase", pos)

	-- tint icon if provided
	local frame = part:FindFirstChild("BillboardGui")
	local icon = frame and frame:FindFirstChild("Frame") and frame.Frame:FindFirstChild("icon") or frame and frame:FindFirstChild("icon")
	if icon and icon:IsA("GuiObject") and tint and typeof(tint) == "table" then
		local r, g, b = tint[1], tint[2], tint[3]
		if typeof(r) == "number" and typeof(g) == "number" and typeof(b) == "number" then
			icon:SetAttribute("TintApplied", true)
			icon.BackgroundTransparency = 1
			icon.BorderSizePixel = 0
			if icon:IsA("ImageLabel") or icon:IsA("ImageButton") then
				icon.ImageColor3 = Color3.new(r, g, b)
			end
		end
	end

	part.Parent = localFolder

	if DEBUG_STICKY then
		snapshotDebug(part, pos)
	end

	task.delay(ALARM_TTL, function()
		_returnLocalAlarm(part)
	end)
end

local function positionAlarm(part: BasePart): boolean
	local alarmType, gx, gz = parseAlarm(part)
	if not alarmType or not gx or not gz then return false end

	-- zoneId is the zone model's name; container is the TempUxpAlarms folder under it.
	local container = part.Parent
	local zoneModel = container and container.Parent
	if not zoneModel then return false end
	local zoneId = zoneModel.Name
	local plot = _findPlotAncestor(zoneModel)
	if not plot then plot = _findPlotAncestor(container) end
	if not plot then return false end
	_configurePlotGrid(plot)

	local basePos = _tileWorldPos(zoneId, gx, gz, plot)
	if not basePos then
		-- fallback to current part position so we still keep something visible
		basePos = part.Position
	end
	-- Preserve the server-authored Y (already includes its offset), only correct X/Z locally.
	local pos = Vector3.new(basePos.X, part.Position.Y, basePos.Z)
	part.Position = pos
	part:SetAttribute("BobBase", pos) -- keep bobbing centred on our computed position

	if DEBUG_STICKY then
		snapshotDebug(part, pos)
	end

	return true
end

local function consider(inst: Instance)
	if not inst:IsA("BasePart") then return end
	if inst.Name:match("^Alarm") then
		if localFolder and inst:IsDescendantOf(localFolder) then return end -- local alarms already positioned
		pending[inst] = true
	end
end

Workspace.DescendantAdded:Connect(consider)
for _, inst in ipairs(Workspace:GetDescendants()) do
	consider(inst)
end

-- Remote hook for client-only upgrade/downgrade alarms
local UxpAlarmRE = RemoteEvents:FindFirstChild("UxpAlarm")
if UxpAlarmRE then
	UxpAlarmRE.OnClientEvent:Connect(function(alarmType: string, zoneId: string, gx: number, gz: number, tint: any)
		if alarmType == "AlarmUpgrade" or alarmType == "AlarmDowngrade" then
			spawnLocalAlarm(alarmType, zoneId, gx, gz, tint)
		end
	end)
else
	warn("[AlarmReanchor] Missing RemoteEvents.UxpAlarm; upgrade/downgrade alarms will replicate from server")
end

RunService.RenderStepped:Connect(function()
	for part, _ in pairs(pending) do
		if not part or not part.Parent then
			pending[part] = nil
		else
			local ok = positionAlarm(part)
			if ok then
				pending[part] = nil
			end
		end
	end
end)
