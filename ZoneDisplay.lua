--[[
Updated Script: ZoneDisplay.lua (Grid-Aligned Version)
Matches BuildingGeneratorModule placement logic (grid-aligned center point).
Server now spawns a sibling RangeVisual part for supported modes.
]]--

local DEBUG = false
local function debugPrint(...) if DEBUG then print("[ZoneDisplayModule]", ...) end end

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

-- Events
local Events = ReplicatedStorage:WaitForChild("Events")
local RemoteEvents = Events:WaitForChild("RemoteEvents")
local ZoneDisplayEvent = RemoteEvents:WaitForChild("ZoneDisplay")
local ZoneRemoveDisplayEvent = RemoteEvents:WaitForChild("ZoneRemoveDisplay")

-- Bindables
local zoneRemovedEvent = Events:WaitForChild("BindableEvents"):WaitForChild("ZoneRemoved")
local zoneAddedEvent = Events:WaitForChild("BindableEvents"):WaitForChild("ZoneAdded")

-- Grid Modules
local GridScripts = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Grid")
local GridConfig = require(GridScripts:WaitForChild("GridConfig"))
local GridUtils = require(GridScripts:WaitForChild("GridUtil"))

local Balancing = ReplicatedStorage:WaitForChild("Balancing")
local Balance  = require(Balancing:WaitForChild("BalanceEconomy"))

-- [RV] Template for server-made range visuals
local FuncTestRS = ReplicatedStorage:WaitForChild("FuncTestGroundRS")
local AlarmsFolder = FuncTestRS:WaitForChild("Alarms")
local RangeVisualTemplate = AlarmsFolder:WaitForChild("RangeVisual")

-- Colours
local zoneColours = {
	New 		= Color3.new(0,0,0),

	--Zones
	Residential = Color3.new(0.227, 0.49, 0.082),
	Commercial  = Color3.new(0.2, 0.345, 0.51),
	Industrial  = Color3.new(0.486, 0.361, 0.275),
	ResDense    = Color3.new(0.153, 0.275, 0.176),
	CommDense   = Color3.new(0.063, 0.165, 0.863),
	IndusDense  = Color3.new(0.69, 0.471, 0),

	-- Road Utility
	DirtRoad    = Color3.new(0.561, 0.561, 0.561),
	Pavement    = Color3.new(0.561, 0.561, 0.561),
	Highway     = Color3.new(0.561, 0.561, 0.561),

	-- Power Utility (yellow)
	PowerLines  			= Color3.new(1, 1, 0),
	CoalPowerPlant     		= Color3.new(1, 1, 0),
	GasPowerPlant      		= Color3.new(1, 1, 0),
	GeothermalPowerPlant 	= Color3.new(1, 1, 0),
	NuclearPowerPlant  		= Color3.new(1, 1, 0),
	SolarPanels        		= Color3.new(1, 1, 0),
	WindTurbine        		= Color3.new(1, 1, 0),

	-- Water Utility (cyan)
	WaterPipe  		= Color3.new(0, 0.667, 1),
	WaterPlant 		= Color3.new(0, 0.667, 1),
	WaterTower 		= Color3.new(0, 0.667, 1),
	PurificationWaterPlant	= Color3.new(0, 0.667, 1),
	MolecularWaterPlant		= Color3.new(0, 0.667, 1),

	-- Fire (orange)
	FireDept           = Color3.new(1, 0.4, 0),
	FirePrecinct       = Color3.new(1, 0.4, 0),
	FireStation        = Color3.new(1, 0.4, 0),

	-- Police (blue)
	PoliceDept         = Color3.new(0, 0, 1),
	PolicePrecinct     = Color3.new(0, 0, 1),
	PoliceStation      = Color3.new(0, 0, 1),
	Courthouse         = Color3.new(0, 0, 1),

	-- Education (light green)
	MiddleSchool       = Color3.new(0.4, 0.9, 0.4),
	PrivateSchool      = Color3.new(0.4, 0.9, 0.4),

	-- Hospitals/Clinics (pinkish-red)
	CityHospital       = Color3.new(1, 0.7, 0.7),
	LocalHospital      = Color3.new(1, 0.7, 0.7),
	MajorHospital      = Color3.new(1, 0.7, 0.7),
	SmallClinic        = Color3.new(1, 0.7, 0.7),

	-- Landmarks (violet)
	Museum             = Color3.new(0.784314, 0.439216, 1),
	Bank               = Color3.new(0.784314, 0.439216, 1),
	NewsStation        = Color3.new(0.784314, 0.439216, 1),
	CNTower            = Color3.new(0.784314, 0.439216, 1),
	EiffelTower        = Color3.new(0.784314, 0.439216, 1),
	EmpireStateBuilding= Color3.new(0.784314, 0.439216, 1),
	FerrisWheel        = Color3.new(0.784314, 0.439216, 1),
	ModernSkyscraper   = Color3.new(0.784314, 0.439216, 1),
	NationalCapital    = Color3.new(0.784314, 0.439216, 1),
	Obelisk            = Color3.new(0.784314, 0.439216, 1),
	SpaceNeedle        = Color3.new(0.784314, 0.439216, 1),
	StatueOfLiberty    = Color3.new(0.784314, 0.439216, 1),
	TechOffice         = Color3.new(0.784314, 0.439216, 1),
	WorldTradeCenter   = Color3.new(0.784314, 0.439216, 1),

	-- Leisure (white)
	Church				= Color3.new(1, 1, 1),
	Mosque				= Color3.new(1, 1, 1),
	ShintoTemple 		= Color3.new(1, 1, 1),
	HinduTemple			= Color3.new(1, 1, 1),
	BuddhaStatue 		= Color3.new(1, 1, 1),
	Hotel               = Color3.new(1, 1, 1),
	MovieTheater        = Color3.new(1, 1, 1),

	-- Sports (bright green)
	ArcheryRange       = Color3.new(0.2, 0.8, 0.2),
	BasketballCourt    = Color3.new(0.2, 0.8, 0.2),
	BasketballStadium  = Color3.new(0.2, 0.8, 0.2),
	FootballStadium    = Color3.new(0.2, 0.8, 0.2),
	GolfCourse         = Color3.new(0.2, 0.8, 0.2),
	PublicPool         = Color3.new(0.2, 0.8, 0.2),
	SkatePark          = Color3.new(0.2, 0.8, 0.2),
	SoccerStadium      = Color3.new(0.2, 0.8, 0.2),
	TennisCourt        = Color3.new(0.2, 0.8, 0.2),

	-- Transportation (dark gray)
	Airport            = Color3.new(0.4, 0.4, 0.4),
	BusDepot           = Color3.new(0.4, 0.4, 0.4),
	Metro              = Color3.new(0.4, 0.4, 0.4),
	MetroEntrance      = Color3.new(0.4, 0.4, 0.4),
	MetroTunnel		   = Color3.new(0.4, 0.4, 0.4)
}

--=== Overlap helpers ==========================================================
local function aabbOverlap(aPos: Vector3, aSize: Vector3, bPos: Vector3, bSize: Vector3, eps: number?)
	eps = eps or 0
	local aHalf = aSize * 0.5
	local bHalf = bSize * 0.5
	local aMin = aPos - aHalf
	local aMax = aPos + aHalf
	local bMin = bPos - bHalf
	local bMax = bPos + bHalf
	local xOK = (aMin.X <= bMax.X + eps) and (bMin.X <= aMax.X + eps)
	local yOK = (aMin.Y <= bMax.Y + eps) and (bMin.Y <= aMax.Y + eps)
	local zOK = (aMin.Z <= bMax.Z + eps) and (bMin.Z <= aMax.Z + eps)
	return xOK and yOK and zOK
end

local function getAllZoneFolders(plot: Folder): {Folder}
	local out = {}
	for _, name in ipairs({ "PlayerZones", "PowerLinesZones", "WaterPipeZones" }) do
		local f = plot:FindFirstChild(name)
		if f then table.insert(out, f) end
	end
	return out
end

local function collectOverlapsAgainstExisting(plot: Folder, newPart: BasePart, ignoreMode: string?): {BasePart}
	local hits = {}
	for _, folder in ipairs(getAllZoneFolders(plot)) do
		for _, child in ipairs(folder:GetChildren()) do
			if child ~= newPart and child:IsA("BasePart") then
				if ignoreMode == nil or (child:GetAttribute("ZoneType") == ignoreMode) then
					if aabbOverlap(newPart.Position, newPart.Size, child.Position, child.Size, 0) then
						table.insert(hits, child)
					end
				end
			end
		end
	end
	return hits
end
--===========================================================================---

local ZoneDisplayModule = {}

local function getContainerForMode(playerPlot: Folder, mode: string): Folder?
	if mode == "PowerLines" then
		return playerPlot:FindFirstChild("PowerLinesZones")
	elseif mode == "WaterPipe" then
		return playerPlot:FindFirstChild("WaterPipeZones")
	else
		return playerPlot:FindFirstChild("PlayerZones")
	end
end

-- [RV] Category map matching your BuildMenu.ZoneCategories
local ZoneCategories = {
	Fire                   = { FireDept=true, FirePrecinct=true, FireStation=true },
	Education              = { MiddleSchool=true, Museum=true, NewsStation=true, PrivateSchool=true },
	Health                 = { CityHospital=true, LocalHospital=true, MajorHospital=true, SmallClinic=true },
	Landmarks              = { Bank=true, CNTower=true, EiffelTower=true, EmpireStateBuilding=true,
		FerrisWheel=true, GasStation=true, ModernSkyscraper=true, NationalCapital=true,
		Obelisk=true, SpaceNeedle=true, StatueOfLiberty=true, TechOffice=true, WorldTradeCenter=true },
	Leisure                = { Church=true, Hotel=true, Mosque=true, MovieTheater=true, ShintoTemple=true, BuddhaStatue=true, HinduTemple=true },
	Police                 = { Courthouse=true, PoliceDept=true, PolicePrecinct=true, PoliceStation=true },
	Sports = { ArcheryRange=true, BasketballCourt=true, BasketballStadium=true, FootballStadium=true,
		GolfCourse=true, PublicPool=true, SkatePark=true, SoccerStadium=true, TennisCourt=true },
	Transport              = { Airport=true, BusDepot=true, MetroEntrance=true },
	Power  = { CoalPowerPlant=true, GasPowerPlant=true, GeothermalPowerPlant=true,
		NuclearPowerPlant=true, SolarPanels=true, WindTurbine=true },
	Water                  = { WaterTower=true, WaterPlant=true, PurificationWaterPlant=true, MolecularWaterPlant=true },
}

-- [RV] Determine a high-level category name from a mode (for convenience tags)
local function resolveCategoryForMode(mode: string): string?
	for cat, set in pairs(ZoneCategories) do
		if set[mode] then return cat end
	end
	return nil
end

-- [RV] Build a sibling RangeVisual if mode has a configured radius; return the part or nil.
local function createSiblingRangeVisual(parentFolder: Instance, zonePart: BasePart, mode: string, zoneId: string): BasePart?
	if not (parentFolder and zonePart and zonePart:IsA("BasePart")) then return nil end

	-- require a radius entry
	local radiusMap = (Balance.UxpConfig and Balance.UxpConfig.Radius) or {}
	local radius = radiusMap[mode]
	if not radius then return nil end

	local rv = RangeVisualTemplate:Clone()
	rv.Name        = tostring(zoneId) .. "_RangeVisual"
	rv.Anchored    = true
	rv.CanCollide  = false
	rv.CanQuery    = false
	rv.Transparency= 1 -- hidden by default; client toggles by category
	rv.Size        = Vector3.new(radius * GridConfig.GRID_SIZE, 1, radius * GridConfig.GRID_SIZE)
	rv.CFrame      = zonePart.CFrame
	rv.Parent      = parentFolder

	-- Tag useful attributes for client-side filters
	rv:SetAttribute("ZoneId", zoneId)
	rv:SetAttribute("ZoneType", mode)
	local cat = resolveCategoryForMode(mode)
	if cat then rv:SetAttribute("Category", cat) end

	return rv
end

-- [RV] Find sibling range visual by convention
local function findSiblingRangeVisual(parentFolder: Instance, zoneId: string): BasePart?
	if not parentFolder then return nil end
	return parentFolder:FindFirstChild(tostring(zoneId) .. "_RangeVisual")
end

function ZoneDisplayModule.displayZone(player, zoneId, mode, gridList, rotationYDeg)
	rotationYDeg = rotationYDeg or 0

	-- 0) guard clauses
	if not player or not zoneId or not mode or not gridList or #gridList == 0 then
		warn("ZoneDisplay: Invalid arguments.")
		return
	end

	-- 1) grid-space bounds
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, c in ipairs(gridList) do
		minX = math.min(minX, c.x)
		maxX = math.max(maxX, c.x)
		minZ = math.min(minZ, c.z)
		maxZ = math.max(maxZ, c.z)
	end

	-- 2) locate player plot
	local plotFolder = Workspace:FindFirstChild("PlayerPlots")
	local playerPlot = plotFolder and plotFolder:FindFirstChild("Plot_" .. player.UserId)
	if not playerPlot then
		warn("ZoneDisplay: Player plot not found for", player.Name)
		return
	end

	-- 3) collect terrain pieces
	local terrains = {}
	local unlocks = playerPlot:FindFirstChild("Unlocks")
	if unlocks then
		for _, z in ipairs(unlocks:GetChildren()) do
			for _, p in ipairs(z:GetChildren()) do
				if p:IsA("BasePart") and p.Name:match("^Segment%d+$") then
					table.insert(terrains, p)
				end
			end
		end
	end
	local testTerrain = playerPlot:FindFirstChild("TestTerrain")
	if #terrains == 0 and testTerrain then table.insert(terrains, testTerrain) end
	if #terrains == 0 then
		warn("ZoneDisplay: No terrain found.")
		return
	end

	-- 4) world-space centre (Y comes from plot terrain)
	local globalBounds = GridConfig.calculateGlobalBounds(terrains)
	local cx = (minX + maxX) / 2
	local cz = (minZ + maxZ) / 2
	local worldX, worldY, worldZ =
		GridUtils.globalGridToWorldPosition(cx, cz, globalBounds, terrains)

	-- 5) dimensions & rotation-aware swap
	local rawWidth  = (maxX - minX + 1) * GridConfig.GRID_SIZE
	local rawDepth  = (maxZ - minZ + 1) * GridConfig.GRID_SIZE
	local rotIsOdd  = (rotationYDeg % 180) ~= 0
	local dispWidth = rotIsOdd and rawDepth or rawWidth
	local dispDepth = rotIsOdd and rawWidth or rawDepth

	local zoneHeight = (mode == "WaterPipe" or mode == "PowerLines") and 1 or 10
	local zoneY      = 1.5

	-- 6) choose bucket folder
	local parentFolder
	if mode == "WaterPipe"   then parentFolder = playerPlot:FindFirstChild("WaterPipeZones")
	elseif mode == "PowerLines" then parentFolder = playerPlot:FindFirstChild("PowerLinesZones")
	else                           parentFolder = playerPlot:FindFirstChild("PlayerZones")
	end
	if not parentFolder then
		warn("ZoneDisplay: Missing destination folder for mode", mode)
		return
	end

	-- 7) create / configure part
	local zonePart = Instance.new("Part")
	zonePart.Name        = zoneId
	zonePart.Anchored    = true
	zonePart.CanCollide  = false
	zonePart.CanQuery    = false
	zonePart.CanTouch    = false
	zonePart.Material    = Enum.Material.Neon
	zonePart.Size        = Vector3.new(dispWidth, zoneHeight, dispDepth)
	zonePart.CFrame      = CFrame.new(worldX, zoneY, worldZ) * CFrame.Angles(0, math.rad(rotationYDeg), 0)
	zonePart.Color       = zoneColours[mode] or Color3.fromRGB(255, 0, 255)
	zonePart.Transparency= 1
	zonePart.Parent      = parentFolder
	zonePart:SetAttribute("ZoneType",  mode)
	zonePart:SetAttribute("RotationY", rotationYDeg)
	local overlaps = collectOverlapsAgainstExisting(playerPlot, zonePart, nil)
	local hasOverlap = (#overlaps > 0)
	zonePart:SetAttribute("HasOverlap", hasOverlap)
	local NO_ROT_ZONES = {
		Residential = true, Commercial = true, Industrial = true,
		ResDense    = true, CommDense = true, IndusDense = true,
	}
	if NO_ROT_ZONES[mode] then
		zonePart:SetAttribute("LockOrientation", true)
	end

	debugPrint(string.format(
		"ZoneDisplay: Created '%s' [%s] @ (%.1f, %.1f, %.1f)  size=(%d×%d) rot=%d°",
		mode, zoneId, worldX, zoneY, worldZ, dispWidth, dispDepth, rotationYDeg
		))

	-- [RV] Create a sibling RangeVisual if the mode has a configured radius
	createSiblingRangeVisual(parentFolder, zonePart, mode, zoneId)

	-- 8) notify client
	ZoneDisplayEvent:FireClient(player, {
		zoneId      = zoneId,
		zoneType    = mode,
		bounds      = { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ },
		rotationY   = rotationYDeg,
	})
end

function ZoneDisplayModule.clearZoneParts(player)
	local plotFolder = Workspace:FindFirstChild("PlayerPlots")
	local playerPlot = plotFolder and plotFolder:FindFirstChild("Plot_" .. player.UserId)
	if not playerPlot then return end

	local zoneFolder = playerPlot:FindFirstChild("PlayerZones")
	if zoneFolder then
		zoneFolder:ClearAllChildren()
		print("ZoneDisplay: Cleared all zone parts for player:", player.Name)
	end
	local pwr = playerPlot:FindFirstChild("PowerLinesZones")
	if pwr then pwr:ClearAllChildren() end
	local wtr = playerPlot:FindFirstChild("WaterPipeZones")
	if wtr then wtr:ClearAllChildren() end
end

function ZoneDisplayModule.removeZonePart(player, zoneId, mode)
	local plotFolder = Workspace:FindFirstChild("PlayerPlots")
	local playerPlot = plotFolder and plotFolder:FindFirstChild("Plot_" .. player.UserId)
	if not playerPlot then return end

	local container = getContainerForMode(playerPlot, mode)
	if container then
		local p = container:FindFirstChild(zoneId)
		if p then p:Destroy() end
		-- [RV] also remove sibling RV
		local rv = findSiblingRangeVisual(container, zoneId)
		if rv then rv:Destroy() end
		if p then return end
	end

	-- Fallback: search all known containers
	for _, folderName in ipairs({"PlayerZones","PowerLinesZones","WaterPipeZones"}) do
		local f = playerPlot:FindFirstChild(folderName)
		if f then
			local p = f:FindFirstChild(zoneId)
			if p then p:Destroy() end
			local rv = findSiblingRangeVisual(f, zoneId)
			if rv then rv:Destroy() end
			if p or rv then return end
		end
	end
end

Players.PlayerRemoving:Connect(function(leavingPlayer)
	ZoneDisplayModule.clearZoneParts(leavingPlayer)
end)

function ZoneDisplayModule.recheckOverlapFor(plotFolder: Folder, zoneId: string): (boolean, {BasePart})
	if not plotFolder then return false, {} end
	local plate = nil
	for _, folder in ipairs(getAllZoneFolders(plotFolder)) do
		local candidate = folder:FindFirstChild(zoneId)
		if candidate then plate = candidate break end
	end
	if not (plate and plate:IsA("BasePart")) then
		return false, {}
	end

	local overlaps = collectOverlapsAgainstExisting(plotFolder, plate, nil)
	local has = (#overlaps > 0)
	plate:SetAttribute("HasOverlap", has)
	return has, overlaps
end

function ZoneDisplayModule.updateZonePartRotation(plotFolder: Folder, zoneId: string, newRotY: number)
	if not plotFolder then return end

	-- We primarily rotate plates in PlayerZones (utility plates are flat, but keep parity)
	local containers = { "PlayerZones", "PowerLinesZones", "WaterPipeZones" }
	for _, folderName in ipairs(containers) do
		local zoneFolder = plotFolder:FindFirstChild(folderName)
		if zoneFolder then
			local plate = zoneFolder:FindFirstChild(zoneId)
			if plate and plate:IsA("BasePart") then
				if plate:GetAttribute("LockOrientation") then
					return
				end
				plate.CFrame = CFrame.new(plate.Position) * CFrame.Angles(0, math.rad(newRotY), 0)
				plate:SetAttribute("RotationY", newRotY)

				-- [RV] Keep sibling RV aligned
				local rv = findSiblingRangeVisual(zoneFolder, zoneId)
				if rv and rv:IsA("BasePart") then
					rv.CFrame = plate.CFrame
				end
				return
			end
		end
	end
end

zoneAddedEvent.Event:Connect(function(player, zoneId, zoneData)
	if not (player and zoneId and zoneData) then return end

	local plotFolder   = Workspace:WaitForChild("PlayerPlots", 20)
	local playerPlot   = plotFolder and plotFolder:WaitForChild("Plot_" .. player.UserId, 20)
	if not playerPlot then
		warn("[ZoneDisplay] plot not ready for", player.Name, "(will retry once)")
		task.defer(function()
			if player.Parent then
				ZoneDisplayModule.displayZone(player, zoneId, zoneData.mode, zoneData.gridList)
			end
		end)
		return
	end

	ZoneDisplayModule.displayZone(player, zoneId, zoneData.mode, zoneData.gridList)
end)

if zoneRemovedEvent then
	zoneRemovedEvent.Event:Connect(function(player, zoneId, mode, _gridList)
		if typeof(zoneId) ~= "string" then return end
		ZoneDisplayModule.removeZonePart(player, zoneId, mode)
		if ZoneRemoveDisplayEvent then
			ZoneRemoveDisplayEvent:FireClient(player, zoneId)
		end
	end)
end

return ZoneDisplayModule
