local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TestGrounds = ReplicatedStorage:WaitForChild("FuncTestGroundRS")
local BuildingFolder = TestGrounds:WaitForChild("Buildings")

local BuildingMasterList = {}
BuildingMasterList.__index = BuildingMasterList

-- Define Wealth States
local WEALTH_STATES = {
	Poor    = "Poor",
	Medium  = "Medium",
	Wealthy = "Wealthy"
}

-- Function to load Stage1 and Stage2 from STAGES_Placeholder
local function loadSharedStages()
	local stages = {}
	local stagesPlaceholder = BuildingFolder:FindFirstChild("STAGES_Placeholder")
	if not stagesPlaceholder then
		warn("BuildingMasterList: 'STAGES_Placeholder' folder not found in Buildings.")
		return stages
	end

	local defaultFolder = stagesPlaceholder:FindFirstChild("Default")
	if not defaultFolder then
		warn("BuildingMasterList: 'Default' folder not found in 'STAGES_Placeholder'.")
		return stages
	end

	local Stage1 = defaultFolder:FindFirstChild("Stage1")
	if not Stage1 then
		warn("BuildingMasterList: 'Stage1' not found in 'STAGES_Placeholder -> Default'.")
	end

	local Stage2 = defaultFolder:FindFirstChild("Stage2")
	if not Stage2 then
		warn("BuildingMasterList: 'Stage2' not found in 'STAGES_Placeholder -> Default'.")
	end

	stages.Stage1 = Stage1
	stages.Stage2 = Stage2

	return stages
end


-- Special loader for Roads: skip wealth states & decorations
-- Only require a single final model (Stage3).

local function loadRoadStage3(style, roadName)
	local roadFolder = BuildingFolder:FindFirstChild("Road")
	if not roadFolder then
		warn("BuildingMasterList: 'Road' folder not found in Buildings.")
		return nil
	end

	local styleFolder = roadFolder:FindFirstChild(style)
	if not styleFolder then
		warn(string.format("BuildingMasterList: Style '%s' not found under 'Road'.", style))
		return nil
	end

	local model = styleFolder:FindFirstChild(roadName)
	if not model then
		for _, subFolder in ipairs(styleFolder:GetChildren()) do
			local found = subFolder:FindFirstChild(roadName)
			if found then
				model = found
				break
			end
		end
	end

	-- New: Check for Decorations folder if no model found or if you want decoration variant
	if not model then
		local decorationsFolder = styleFolder:FindFirstChild("Decorations")
		if decorationsFolder then
			model = decorationsFolder:FindFirstChild(roadName)
		end
	end

	if not model then
		warn(string.format("BuildingMasterList: Road '%s' not found under style '%s'.", roadName, style))
		return nil
	end

	if model:IsA("Folder") then
		local child = model:FindFirstChildWhichIsA("Model") or model:FindFirstChildWhichIsA("BasePart")
		if not child then
			warn("BuildingMasterList: No suitable Model/Part in folder '" .. model.Name .. "' for road '" .. roadName .. "'.")
			return nil
		end
		model = child
	end

	return model
end


-- Original function to load Stage3 for normal buildings & utilities

local function loadStage3(zoneType, style, buildingName, wealthState)
	local stages = {}
	local zoneFolder = BuildingFolder:FindFirstChild(zoneType)
	if not zoneFolder then
		warn(string.format("BuildingMasterList: Zone Type '%s' not found in Buildings folder.", zoneType))
		return stages
	end

	-- Attempt to find the style folder; if not found, use zoneFolder
	local styleFolder = zoneFolder:FindFirstChild(style)
	if not styleFolder then
		warn(string.format("BuildingMasterList: Style '%s' not found in Zone '%s'. Attempting to proceed without style.", style, zoneType))
		styleFolder = zoneFolder
	end

	--Individual Building loading logic
	if zoneType == "Individual" then
		local buildingModel = styleFolder:FindFirstChild(buildingName)
		if not buildingModel then
			-- NEW: Search any subfolders (e.g., "Fire", "Police", "Landmark" etc.)
			for _, subFolder in ipairs(styleFolder:GetChildren()) do
				if subFolder:IsA("Folder") then
					local possible = subFolder:FindFirstChild(buildingName)
					if possible then
						buildingModel = possible
						break
					end
				end
			end
		end

		if not buildingModel then
			warn(string.format(
				"BuildingMasterList: Individual building '%s' not found under Zone '%s' > Style '%s'.",
				buildingName, zoneType, style
				))
			return stages
		end

		if buildingModel:IsA("Folder") then
			local childModel = buildingModel:FindFirstChildWhichIsA("Model")
				or buildingModel:FindFirstChildWhichIsA("BasePart")
			if not childModel then
				warn(string.format("BuildingMasterList: No suitable Model/Part in folder '%s'.", buildingModel.Name))
				return stages
			end
			buildingModel = childModel
		end

		stages.Stage3 = buildingModel
		return stages
	end

	local buildingModel

	if wealthState then
		local wealthFolder = styleFolder:FindFirstChild(wealthState)
		if not wealthFolder then
			warn(string.format("BuildingMasterList: Wealth State '%s' not found in Zone '%s' > Style '%s'.", wealthState, zoneType, style))
			return stages
		end
		buildingModel = wealthFolder:FindFirstChild(buildingName)
	else
		-- Attempt to find the building under Decorations
		local decorationsFolder = styleFolder:FindFirstChild("Decorations")
		if decorationsFolder then
			buildingModel = decorationsFolder:FindFirstChild(buildingName)
		else
			warn(string.format("BuildingMasterList: 'Decorations' folder not found in Zone '%s' > Style '%s'.", zoneType, style))
			return stages
		end
	end

	-- If buildingModel not found, check if there's a folder with the building's name
	if not buildingModel then
		if wealthState then
			local parentFolder = styleFolder:FindFirstChild(wealthState)
			buildingModel = parentFolder and parentFolder:FindFirstChild(buildingName)
		else
			local decorationsFolder = styleFolder:FindFirstChild("Decorations")
			buildingModel = decorationsFolder and decorationsFolder:FindFirstChild(buildingName)
		end

		if not buildingModel then
			warn(string.format("BuildingMasterList: Building '%s' not found in Zone '%s' > Style '%s'%s.",
				buildingName, zoneType, style,
				wealthState and (" > Wealth State '" .. wealthState .. "'") or " > Decorations"))
			return stages
		end
	end

	-- Handle if buildingModel is a Folder
	if buildingModel:IsA("Folder") then
		local childModel = buildingModel:FindFirstChildWhichIsA("Model") or buildingModel:FindFirstChildWhichIsA("Part")
		if childModel then
			buildingModel = childModel
		else
			warn(string.format("BuildingMasterList: No suitable Model or Part found inside folder '%s'.", buildingModel.Name))
			return stages
		end
	end

	-- Assign Stage3
	stages.Stage3 = buildingModel

	return stages
end


-- Main loadBuildingStages: If road -> do single-stage
-- Else -> do normal building/utility approach

function BuildingMasterList.loadBuildingStages(zoneType, style, buildingName, wealthState)
	-- If it's a road, we skip wealth states & Stage1/Stage2
	if zoneType == "Road" then
		local model = loadRoadStage3(style, buildingName)
		local stages = {}
		if model then
			stages.Stage3 = model
		end
		return stages
	end

	
	-- Otherwise, normal building / utility logic:
	
	local stages = {}

	-- Load shared stages for buildings/utilities
	local sharedStages = loadSharedStages()
	stages.Stage1 = sharedStages.Stage1
	stages.Stage2 = sharedStages.Stage2

	-- If Stage1/Stage2 are missing, you'll see warnings (normal).
	if not stages.Stage1 then
		warn("BuildingMasterList: 'Stage1' is missing from shared stages.")
	end
	if not stages.Stage2 then
		warn("BuildingMasterList: 'Stage2' is missing from shared stages.")
	end

	-- Then load Stage3 from normal logic
	local stage3Stages = loadStage3(zoneType, style, buildingName, wealthState)
	stages.Stage3 = stage3Stages.Stage3

	-- If Stage3 missing, we warn (normal).
	if not stages.Stage3 then
		warn(string.format("BuildingMasterList: 'Stage3' is missing for building '%s'.", buildingName))
	end

	return stages
end


--[[ Skeleton for adding zones and w.e.
ZONE = {
		STYLE = {
			Poor = {
				{
					name = "BLDGP1",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
			},
			Medium = {
				{
					name = "BLDGM1",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
			},
			Wealthy = {
				{
					name = "BLDGW1",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
			},
		},
		STYLE2 = {
			--Repeat
		},
	},
]]

-- Buildings Data Structure with Nested Wealth States
local buildings = {
	Residential = {
		Default = {
			Poor = {
				{
					name = "ResP1",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				}, 
				{
					name = "ResP2",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResP3",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResP4",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResP5",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResP6",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResP7",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResP8",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResP9",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResP10",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResP11",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResP12",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResP13",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResP14",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResP15",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
			},
			Medium = {
				{
					name = "ResM1",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				}, 
				{
					name = "ResM2",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResM3",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResM4",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResM5",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResM6",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResM7",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResM8",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResM9",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResM10",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResM11",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResM12",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResM13",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResM14",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResM15",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResM16",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
				{
					name = "ResM17",
					tier = 1,
					cost = { money = 1000, wood = 20 },
					stats = { wealthGeneration = 10, happinessIncrease = 5, wealthCost = 2 },
					requirements = { power = 5, water = 10, happiness = 0, jobs = 0, population = 2 },
				},
			},
			Wealthy = {
				{
					name = "ResW1",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ResW2",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ResW3",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ResW4",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ResW5",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ResW6",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ResW7",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ResW8",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ResW9",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ResW10",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ResW11",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ResW12",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ResW13",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ResW14",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ResW15",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ResW16",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
			},
			Decorations = {
				{
					name = "ResDec1",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec2",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec3",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec4",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec5",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec6",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec7",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec8",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec9",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec10",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec11",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec12",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec13",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec14",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec15",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
			},
		},
		Style2 = {
			-- Add buildings for Style2 here
		},
	},
	Commercial = {
		Default = {
			Poor = {
				{
					name = "ComP1",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP2",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP3",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP4",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP5",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP6",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP7",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP8",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP9",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP10",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP11",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP12",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP13",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP14",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP15",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP16",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP17",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP18",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP19",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP20",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP21",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP22",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP23",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP24",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP25",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP26",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP27",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP28",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComP29",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
			},
			Medium = {
				{
					name = "ComM1",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComM2",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComM3",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComM4",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComM5",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComM6",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComM7",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComM8",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComM9",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComM10",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComM11",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComM12",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComM13",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComM14",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComM15",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComM16",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComM17",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
			},
			Wealthy = {
				{
					name = "ComW1",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComW2",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComW3",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComW4",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComW5",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComW6",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComW7",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComW8",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComW9",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComW10",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComW11",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComW12",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComW13",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComW14",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComW15",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComW16",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComW17",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComW18",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComW19",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComW20",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComW21",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "ComW22",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
			},
			Decorations = {
				{
					name = "ComDec1",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec2",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec3",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec4",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec5",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec6",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec7",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec8",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec9",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec10",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec11",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec12",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec13",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec14",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec15",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec16",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
			},
		},
		Style2 = {
			-- Add buildings for Style2 here
		},
	},
	Industrial = {
		Default = {
			Poor = {
				{
					name = "IndP1",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndP2",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndP3",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndP4",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndP5",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndP6",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndP7",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndP8",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndP9",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndP10",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndP11",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndP12",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndP13",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
			},
			Medium = {
				{
					name = "IndM1",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndM2",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndM3",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndM4",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndM5",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndM6",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndM7",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndM8",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndM9",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndM10",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndM11",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndM12",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndM13",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndM14",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndM15",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndM16",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndM17",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndM18",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndM19",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
			},
			Wealthy = {
				{
					name = "IndW1",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndW2",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndW3",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndW4",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndW5",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndW6",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndW7",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndW8",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndW9",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndW10",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndW11",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndW12",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndW13",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndW14",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndW15",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndW16",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndW17",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndW18",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "IndW19",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
			},
			Decorations = {
				{
					name = "IndDec1",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "IndDec2",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "IndDec3",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "IndDec4",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "IndDec5",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "IndDec6",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "IndDec7",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
			},
		},
		STYLE2 = {
			--Repeat
		},
	},
	ResDense = {
		Default = {
			Poor = {
				{
					name = "HResP1",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResP2",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResP3",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResP4",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResP5",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResP6",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResP7",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResP8",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResP9",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResP10",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResP11",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResP12",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResP13",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResP14",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResP15",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResP16",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResP17",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResP18",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResP19",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResP20",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResP21",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResP22",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
			},
			Medium = {
				{
					name = "HResM1",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResM2",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResM3",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResM4",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResM5",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResM6",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResM7",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResM8",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResM9",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResM10",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResM11",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResM12",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResM13",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResM14",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResM15",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResM16",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResM17",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResM18",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResM19",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResM20",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResM21",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResM22",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResM23",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResM24",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResM25",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
			},
			Wealthy = {
				{
					name = "HResW1",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW2",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW3",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW4",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW5",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW6",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW7",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW8",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW9",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW10",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW11",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW12",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW13",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW14",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW15",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW16",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW17",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW18",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW19",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW20",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW21",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW22",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW23",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW24",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW25",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HResW26",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
			},
			Decorations = {
				{
					name = "ResDec1",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec2",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec3",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec4",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec5",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec6",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec7",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec8",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec9",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec10",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec11",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec12",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec13",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec14",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ResDec15",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
			},
		},
		STYLE2 = {
			--Repeat
		},
	},
	CommDense = {
		Default = {
			Poor = {
				{
					name = "HComP1",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComP2",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComP3",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComP4",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComP5",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComP6",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComP7",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComP8",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComP9",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComP10",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComP11",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComP12",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComP13",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComP14",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComP15",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComP16",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComP17",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComP18",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
			},
			Medium = {
				{
					name = "HComM1",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM2",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM3",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM4",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM5",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM6",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM7",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM8",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM9",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM10",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM11",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM12",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM13",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM14",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM15",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM16",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM17",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM18",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM19",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM20",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM21",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM22",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM23",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM24",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM25",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM26",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM27",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM28",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM29",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComM30",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
			},
			Wealthy = {
				{
					name = "HComW1",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW2",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW3",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW4",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW5",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW6",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW7",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW8",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW9",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW10",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW11",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW12",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW13",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW14",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW15",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW16",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW17",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW18",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW19",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW20",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW21",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW22",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW23",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW24",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW25",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW26",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW27",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW28",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW29",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW30",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW31",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW32",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW33",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW34",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW35",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HComW36",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
			},
			Decorations = {
				{
					name = "ComDec1",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec2",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec3",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec4",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec5",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec6",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec7",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec8",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec9",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec10",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec11",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec12",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec13",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec14",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec15",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "ComDec16",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
			},
		},
		STYLE2 = {
			--Repeat
		},
	},
	IndusDense = {
		Default = {
			Poor = {
				{
					name = "HIndP1",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndP2",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndP3",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndP4",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndP5",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndP6",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndP7",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndP8",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndP9",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndP10",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndP11",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndP12",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndP13",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndP14",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndP15",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndP16",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndP17",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndP18",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndP19",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndP20",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndP21",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndP22",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndP23",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
			},
			Medium = {
				{
					name = "HIndM1",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndM2",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndM3",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndM4",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndM5",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndM6",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndM7",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndM8",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndM9",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndM10",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndM11",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndM12",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndM13",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndM14",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndM15",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndM16",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndM17",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndM18",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndM19",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndM20",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndM21",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndM22",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndM23",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
			},
			Wealthy = {
				{
					name = "HIndW1",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndW2",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndW3",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndW4",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndW5",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndW6",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndW7",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndW8",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndW9",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndW10",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndW11",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndW12",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndW13",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndW14",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndW15",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndW16",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndW17",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndW18",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndW19",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndW20",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndW21",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndW22",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
				{
					name = "HIndW23",
					tier = 3,
					cost = { money = 3000, metal = 50 },
					stats = { wealthGeneration = 25, happinessIncrease = 15, wealthCost = 5 },
					requirements = { power = 15, water = 25, happiness = 0, jobs = 0, population = 5 },
				},
			},
			Decorations = {
				{
					name = "IndDec1",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "IndDec2",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "IndDec3",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "IndDec4",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "IndDec5",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "IndDec6",
					tier = 1,
					cost = { money = 150, metal = 15 },
					stats = { aesthetic = 15 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
				{
					name = "IndDec7",
					tier = 1,
					cost = { money = 100, metal = 10 },
					stats = { aesthetic = 10 },
					requirements = { power = 0, water = 0, happiness = 0, jobs = 0, population = 0 },
				},
			},
		},
		STYLE2 = {
			--Repeat
		},
	},
	Utilities = {
		Water = {
			Default = {
				WaterTower ={
					{
						name = "WaterTower",
						tier = 1,
						stats = { waterSupply = 100 },
					},			
				},
			},
		},
		Power = {
			Default = {
				Solar = {
					{
						name = "Solar Panel",
						tier = 1,
						stats = { powerGeneration = 70 },
					},
				},
				Wind = {
					{
						name = "Wind Turbine",
						tier = 1,
						stats = { powerGeneration = 50 },
					},
				},
				PowerLines = {
					name = "PowerLines",
					tier = 1,
					stats = { powerGeneration = 50 },
				}
			},
		},
	},
	Road = {
		Default = {
			DirtRoad ={
				{
					name = "Road",
					tier = 1,
					stats = { travelSpeed = 10 },
				},
				{
					name = "3Way",
					tier = 1,
					stats = { travelSpeed = 10 },
				},
				{
					name = "4Way",
					tier = 1,
					stats = { travelSpeed = 10 },
				},
				{
					name = "Turn",
					tier = 1,
					stats = { travelSpeed = 10 },
				},
				{
					name = "Bridge",
					tier = 1,
					stats = { travelSpeed = 10 },
				},
			},
			Decorations = {
				{
					name = "StopLight",
					tier = 1,
					stats = { travelSpeed = 10 },
				},
				{
					name = "StopSign",
					tier = 1,
					stats = { travelSpeed = 10 },
				},
				{
					name = "Billboard",
					tier = 1,
					stats = { travelSpeed = 10 },
				},
				{
					name = "BillboardStanding",
					tier = 1,
					stats = { travelSpeed = 10 },
				},
				{
					name = "Ad1",
					tier = 1,
					stats = { travelSpeed = 10 },
				},
				{
					name = "Ad2",
					tier = 1,
					stats = { travelSpeed = 10 },
				},
				{
					name = "Ad3",
					tier = 1,
					stats = { travelSpeed = 10 },
				},
				{
					name = "Ad4",
					tier = 1,
					stats = { travelSpeed = 10 },
				},
				{
					name = "Ad5",
					tier = 1,
					stats = { travelSpeed = 10 },
				},
			},
		},
	},

	Individual = {
		Default ={
			Education ={
				{
					name = "Middle School",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Museum",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "News Station",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Private School",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
			},
			Fire ={
				{
					name = "FireDept",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "FirePrecinct",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "FireStation",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
			},
			Health = {
				{
					name = "City Hospital",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Local Hospital",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Major Hospital",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Small Clinic",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
			},
			Landmark = {
				{
					name = "Bank",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "CN Tower",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Eiffel Tower",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Empire State Building",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Ferris Wheel",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Gas Station",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Modern Skyscraper",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "National Capital",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Obelisk",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Space Needle",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Statue Of Liberty",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Tech Office",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "World Trade Center",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
			},
			Leisure = {
				{
					name = "Church",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Hotel",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Mosque",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Movie Theater",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Shinto Temple",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Buddha Statue",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Hindu Temple",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
			},
			Police = {
				{
					name = "Courthouse",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Police Dept",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Police Precinct",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Police Station",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
			},
			Sports ={
				{
					name = "Archery Range",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Basketball Court",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Basketball Stadium",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Football Stadium",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Golf Course",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Public Pool",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Skate Park",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Soccer Stadium",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Tennis Court",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				
			},
			Airport = {
				{
					name = "Airport",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
			},
			Bus = {
				{
					name = "Bus Depot",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
			},
			Metro = {
				{
				name = "Metro Entrance",
				tier = 1,
				stats = { xp = 9000, upgrade = 90000 },
				},
			},
			Power = {
				{
					name = "Coal Power Plant",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Gas Power Plant",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Geothermal Power Plant",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Nuclear Power Plant",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Solar Panels",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Wind Turbine",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "ElectricBox",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
			},
			Water = {
				{
					name = "Water Plant",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Purification Water Plant",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
				{
					name = "Molecular Water Plant",
					tier = 1,
					stats = { xp = 9000, upgrade = 90000 },
				},
			},

		},
	},
}

-- Function to retrieve buildings by zone type, style, and wealth state
function BuildingMasterList.getBuildingsByZone(zoneType, style, wealthState)
	local zoneBuildings = buildings[zoneType]
	if not zoneBuildings then
		warn(string.format("BuildingMasterList: Zone Type '%s' does not exist.", zoneType))
		return {}
	end

	local styleBuildings = zoneBuildings[style]
	if not styleBuildings then
		warn(string.format("BuildingMasterList: Style '%s' does not exist under Zone Type '%s'.", style, zoneType))
		return {}
	end

	local populatedList = {}

	-- Retrieve buildings based on wealthState
	if wealthState then
		local wealthBuildings = styleBuildings[wealthState]
		if not wealthBuildings then
			warn(string.format("BuildingMasterList: Wealth State '%s' does not exist under Zone Type '%s' > Style '%s'.", wealthState, zoneType, style))
		else
			for _, building in ipairs(wealthBuildings) do
				-- Load stages dynamically
				local stages = BuildingMasterList.loadBuildingStages(zoneType, style, building.name, wealthState)
				if stages and stages.Stage1 and stages.Stage2 and stages.Stage3 then
					building.stages = stages
					table.insert(populatedList, building)
				else
					warn(string.format("BuildingMasterList: Incomplete stages for building '%s'.", building.name))
				end
			end
		end
	end

	-- Retrieve Decorations (no wealthState)
	local decorations = styleBuildings.Decorations
	if decorations then
		for _, decoration in ipairs(decorations) do
			local stages = BuildingMasterList.loadBuildingStages(zoneType, style, decoration.name)
			if stages and stages.Stage1 and stages.Stage2 and stages.Stage3 then
				decoration.stages = stages
				table.insert(populatedList, decoration)
			else
				warn(string.format("BuildingMasterList: Incomplete stages for decoration '%s'.", decoration.name))
			end
		end
	end

	return populatedList
end

-- Function to retrieve utilities by type and style
function BuildingMasterList.getUtilitiesByType(utilityType, style)
	local utilities = buildings.Utilities
	if not utilities then
		warn("BuildingMasterList: 'Utilities' category does not exist.")
		return {}
	end

	local typeUtilities = utilities[utilityType]
	if not typeUtilities then
		warn(string.format("BuildingMasterList: Utility Type '%s' does not exist.", utilityType))
		return {}
	end

	local styleUtilities = typeUtilities[style]
	if not styleUtilities then
		warn(string.format("BuildingMasterList: Style '%s' does not exist under Utility Type '%s'.", style, utilityType))
		return {}
	end

	local populatedList = {}

	for _, utility in ipairs(styleUtilities) do
		-- Load stages dynamically (Stage1/Stage2/Stage3 for normal utilities)
		local stages = BuildingMasterList.loadBuildingStages(utilityType, style, utility.name)
		if stages and stages.Stage1 and stages.Stage2 and stages.Stage3 then
			utility.stages = stages
			table.insert(populatedList, utility)
		else
			warn(string.format("BuildingMasterList: Incomplete stages for utility '%s'.", utility.name))
		end
	end

	return populatedList
end

-- Function to retrieve a specific utility building by name
function BuildingMasterList.getUtilityBuilding(utilityType, style, buildingName)
    -- Reference the local buildings.Utilities table (not BuildingMasterList.Utilities).
    local utilities = buildings.Utilities
    if not utilities then
        warn("BuildingMasterList: 'Utilities' category does not exist.")
        return {}
    end

    local typeUtilities = utilities[utilityType]
    if not typeUtilities then
        warn("Utility type not found:", utilityType)
        return {}
    end

    -- Support fallback to "Default" style if needed
    local styleGroup = typeUtilities[style] or typeUtilities["Default"]
    if not styleGroup then
        warn(string.format("Style '%s' not found for utility '%s'.", style, utilityType))
        return {}
    end

    -- Since styleGroup can now be something like:
    -- {
    --   WaterTower = {
    --       { name = "WaterTower", tier=1, stats = {...} }
    --   }
    -- }
    -- we loop over all subkeys in styleGroup:
    for _, buildingList in pairs(styleGroup) do
        -- buildingList is the array of building definitions under WaterTower = { ... }
        if type(buildingList) == "table" then
            for _, building in ipairs(buildingList) do
                if building.name == buildingName then
                    -- Optionally ensure the building's stages are loaded:
                    if not building.stages then
                        -- Load them now:
                        local stages = BuildingMasterList.loadBuildingStages(utilityType, style, building.name)
                        building.stages = stages
                    end

                    -- Make sure we have a Stage3
                    if building.stages and building.stages.Stage3 then
                        -- Return it in a single-element array, matching your existing API
                        return { building }
                    else
                        warn(string.format("Building '%s' found but missing Stage3!", buildingName))
                        return {}
                    end
                end
            end
        end
    end

    warn(string.format("Building '%s' not found under utility '%s' (style: '%s').",
        buildingName, utilityType, style))
    return {}
end

-- Function to retrieve roads by style
function BuildingMasterList.getRoadsByStyle(style)
	local roads = buildings.Road
	if not roads then
		warn("BuildingMasterList: 'Road' category does not exist.")
		return {}
	end

	local styleFolders = roads[style]
	if not styleFolders then
		warn(string.format("BuildingMasterList: Style '%s' does not exist under 'Road'.", style))
		return {}
	end

	local populatedList = {}

	-- e.g. roads["Default"] -> { DirtRoad = { { name="Road" }, { name="3Way"}, ... } }
	for subStyleName, roadDefs in pairs(styleFolders) do
		for _, roadDef in ipairs(roadDefs) do
			-- We do loadBuildingStages( "Road", style, roadDef.name )
			-- That calls our special logic for roads
			local stages = BuildingMasterList.loadBuildingStages("Road", style, roadDef.name)
			if stages and stages.Stage3 then
				-- For roads, we only need Stage3
				roadDef.stages = stages
				table.insert(populatedList, roadDef)
			else
				warn(string.format("BuildingMasterList: Incomplete stage(s) for road '%s'.", roadDef.name))
			end
		end
	end

	return populatedList
end

--Individual Buildings
function BuildingMasterList.getIndividualBuildingsByType(individualType, style)
	local individual = buildings.Individual
	if not individual then
		warn("BuildingMasterList: 'Individual' category does not exist.")
		return {}
	end

	local styleFolder = individual[style]
	if not styleFolder then
		warn(string.format("BuildingMasterList: Style '%s' does not exist under 'Individual'.", style))
		return {}
	end

	-- e.g. individualType = "Education", "Fire", "Health", ...
	local buildingList = styleFolder[individualType]
	if not buildingList then
		warn(string.format(
			"BuildingMasterList: Individual type '%s' does not exist under style '%s' in 'Individual'.",
			individualType, style
			))
		return {}
	end

	local populatedList = {}
	for _, building in ipairs(buildingList) do
		-- loadStage3 for "Individual" buildings. No wealthState is passed:
		local stages = BuildingMasterList.loadBuildingStages("Individual", style, building.name)
		if stages and stages.Stage3 then
			building.stages = stages
			table.insert(populatedList, building)
		else
			warn(string.format("BuildingMasterList: Incomplete stages for individual building '%s'.", building.name))
		end
	end

	return populatedList
end

-- Function to retrieve a single Individual building by name
function BuildingMasterList.getIndividualBuildingByName(individualType, style, buildingName)
	local individual = buildings.Individual
	if not individual then
		warn("BuildingMasterList: 'Individual' category does not exist.")
		return {}
	end

	local styleFolder = individual[style]
	if not styleFolder then
		warn(string.format("BuildingMasterList: Style '%s' does not exist under 'Individual'.", style))
		return {}
	end

	local buildingList = styleFolder[individualType]
	if not buildingList then
		warn(string.format(
			"BuildingMasterList: Individual type '%s' does not exist under style '%s' in 'Individual'.",
			individualType, style
			))
		return {}
	end

	for _, building in ipairs(buildingList) do
		if building.name == buildingName then
			-- Make sure stages are loaded
			if not building.stages then
				local stages = BuildingMasterList.loadBuildingStages("Individual", style, buildingName)
				building.stages = stages
			end
			if building.stages and building.stages.Stage3 then
				-- Return in a single-element array, matching your existing "getXBuilding" style
				return { building }
			else
				warn(string.format("Building '%s' found but missing Stage3!", buildingName))
				return {}
			end
		end
	end

	warn(string.format("Building '%s' not found under Individual -> Style '%s' -> Type '%s'.", 
		buildingName, style, individualType))
	return {}
end


-- Function to retrieve a building by its name
function BuildingMasterList.getBuildingByName(buildingName)
	for zoneType, styleBuildings in pairs(buildings) do
		if zoneType ~= "Utilities" and zoneType ~= "Road" then
			-- Normal buildings
			for style, wealthBuildings in pairs(styleBuildings) do
				for wealthState, buildingList in pairs(wealthBuildings) do
					for _, building in ipairs(buildingList) do
						if building.name == buildingName then
							return building
						end
					end
				end
			end
		elseif zoneType == "Utilities" then
			for utilityType, styleUtilities in pairs(styleBuildings) do
				for style, utilityList in pairs(styleUtilities) do
					for _, utility in ipairs(utilityList) do
						if utility.name == buildingName then
							return utility
						end
					end
				end
			end
		elseif zoneType == "Road" then
			-- Roads
			for styleKey, subFolders in pairs(styleBuildings) do
				for subFolderName, roadList in pairs(subFolders) do
					for _, roadEntry in ipairs(roadList) do
						if roadEntry.name == buildingName then
							return roadEntry
						end
					end
				end
			end
		end
	end
	return nil
end

function BuildingMasterList.getPowerLinesByStyle(style)
	local utilities = buildings.Utilities
	if not utilities then
		warn("BuildingMasterList: 'Utilities' category does not exist.")
		return {}
	end

	local powerUtilities = utilities["Power"]
	if not powerUtilities then
		warn("BuildingMasterList: 'Power' utility type does not exist.")
		return {}
	end

	local styleGroup = powerUtilities[style]
	if not styleGroup then
		warn(string.format("BuildingMasterList: Style '%s' not found under Power utilities.", style))
		return {}
	end

	local powerLineDefs = styleGroup["PowerLines"]
	if not powerLineDefs then
		warn(string.format("BuildingMasterList: No 'PowerLines' entries found under Power > %s.", style))
		return {}
	end

	local populatedList = {}

	local function loadAndInsert(def)
		local stages = BuildingMasterList.loadBuildingStages("Power", style, def.name)
		if stages and stages.Stage3 then
			def.stages = stages
			table.insert(populatedList, def)
		else
			warn(string.format("BuildingMasterList: Missing Stage3 for PowerLines '%s'", def.name))
		end
	end

	-- Single object or array of objects
	if typeof(powerLineDefs) == "table" and #powerLineDefs > 0 then
		for _, def in ipairs(powerLineDefs) do
			loadAndInsert(def)
		end
	elseif typeof(powerLineDefs) == "table" and powerLineDefs.name then
		-- Single object case
		loadAndInsert(powerLineDefs)
	else
		warn("BuildingMasterList: Unexpected format for PowerLines definitions.")
	end

	return populatedList
end

-- Validation Function to Ensure All Building Parts Exist, Including Decorations
function BuildingMasterList.validateMasterList()
	--
	-- Validate normal buildings (skip 'Utilities' & 'Road' here)
	--
	for zoneType, styleBuildings in pairs(buildings) do
		if zoneType ~= "Utilities" and zoneType ~= "Road" then
			for style, wealthBuildings in pairs(styleBuildings) do
				for wealthState, buildingList in pairs(wealthBuildings) do
					if wealthState ~= "Decorations" then
						for _, building in ipairs(buildingList) do
							local stages = BuildingMasterList.loadBuildingStages(zoneType, style, building.name, wealthState)
							if stages then
								if not stages.Stage1 then
									warn(string.format(
										"Validation Error: 'Stage1' is missing for building '%s' in Zone '%s' > Style '%s' > Wealth State '%s'.",
										building.name, zoneType, style, wealthState
										))
								end
								if not stages.Stage2 then
									warn(string.format(
										"Validation Error: 'Stage2' is missing for building '%s' in Zone '%s' > Style '%s' > Wealth State '%s'.",
										building.name, zoneType, style, wealthState
										))
								end
								if not stages.Stage3 then
									warn(string.format(
										"Validation Error: 'Stage3' is missing for building '%s' in Zone '%s' > Style '%s' > Wealth State '%s'.",
										building.name, zoneType, style, wealthState
										))
								end
							else
								warn(string.format(
									"Validation Error: Failed to load stages for building '%s' in Zone '%s' > Style '%s' > Wealth State '%s'.",
									building.name, zoneType, style, wealthState
									))
							end
						end
					end
				end

				-- Validate Decorations
				local decorations = wealthBuildings.Decorations
				if decorations then
					for _, decoration in ipairs(decorations) do
						local stages = BuildingMasterList.loadBuildingStages(zoneType, style, decoration.name)
						if stages then
							if not stages.Stage1 then
								warn(string.format(
									"Validation Error: 'Stage1' is missing for decoration '%s' in Zone '%s' > Style '%s'.",
									decoration.name, zoneType, style
									))
							end
							if not stages.Stage2 then
								warn(string.format(
									"Validation Error: 'Stage2' is missing for decoration '%s' in Zone '%s' > Style '%s'.",
									decoration.name, zoneType, style
									))
							end
							if not stages.Stage3 then
								warn(string.format(
									"Validation Error: 'Stage3' is missing for decoration '%s' in Zone '%s' > Style '%s'.",
									decoration.name, zoneType, style
									))
							end
						else
							warn(string.format(
								"Validation Error: Failed to load stages for decoration '%s' in Zone '%s' > Style '%s'.",
								decoration.name, zoneType, style
								))
						end
					end
				end
			end
		end
	end

	--
	-- Validate utilities
	--
	local utilities = buildings.Utilities
	if utilities then
		for utilityType, styleUtilities in pairs(utilities) do
			for style, utilityList in pairs(styleUtilities) do
				for _, utility in ipairs(utilityList) do
					local stages = BuildingMasterList.loadBuildingStages(utilityType, style, utility.name)
					if stages then
						if not stages.Stage1 then
							warn(string.format("Validation Error: 'Stage1' is missing for utility '%s' of type '%s' > Style '%s'.",
								utility.name, utilityType, style))
						end
						if not stages.Stage2 then
							warn(string.format("Validation Error: 'Stage2' is missing for utility '%s' of type '%s' > Style '%s'.",
								utility.name, utilityType, style))
						end
						if not stages.Stage3 then
							warn(string.format("Validation Error: 'Stage3' is missing for utility '%s' of type '%s' > Style '%s'.",
								utility.name, utilityType, style))
						end
					else
						warn(string.format("Validation Error: Failed to load stages for utility '%s' of type '%s' > Style '%s'.",
							utility.name, utilityType, style))
					end
				end
			end
		end
	else
		warn("BuildingMasterList: No utilities found for validation.")
	end

	--
	-- Validate roads (only require Stage3)
	--
	local roads = buildings.Road
	if roads then
		for style, subFoldersOrArrays in pairs(roads) do
			for subStyleName, arrayOfRoads in pairs(subFoldersOrArrays) do
				for _, roadDef in ipairs(arrayOfRoads) do
					local stages = BuildingMasterList.loadBuildingStages("Road", style, roadDef.name)
					-- For roads, we do NOT require Stage1 or Stage2
					if stages then
						if not stages.Stage3 then
							warn(string.format(
								"Validation Error: 'Stage3' is missing for road '%s' > Style '%s' > Subfolder '%s'.",
								roadDef.name, style, subStyleName
								))
						end
					else
						warn(string.format(
							"Validation Error: Failed to load stage for road '%s' > Style '%s' > Subfolder '%s'.",
							roadDef.name, style, subStyleName
							))
					end
				end
			end
		end
	else
		warn("BuildingMasterList: No roads found for validation.")
	end

	--Individual
	local individual = buildings.Individual
	if individual then
		for style, individualTypes in pairs(individual) do
			for individualType, buildingList in pairs(individualTypes) do
				for _, building in ipairs(buildingList) do
					local stages = BuildingMasterList.loadBuildingStages("Individual", style, building.name)
					if stages then
						if not stages.Stage1 then
							warn(string.format(
								"Validation Error: 'Stage1' is missing for individual building '%s' (type '%s') in style '%s'.",
								building.name, individualType, style
								))
						end
						if not stages.Stage2 then
							warn(string.format(
								"Validation Error: 'Stage2' is missing for individual building '%s' (type '%s') in style '%s'.",
								building.name, individualType, style
								))
						end
						if not stages.Stage3 then
							warn(string.format(
								"Validation Error: 'Stage3' is missing for individual building '%s' (type '%s') in style '%s'.",
								building.name, individualType, style
								))
						end
					else
						warn(string.format(
							"Validation Error: Failed to load stages for individual building '%s' (type '%s') in style '%s'.",
							building.name, individualType, style
							))
					end
				end
			end
		end
	end

	print("BuildingMasterList: Validation complete.")
end

-- Call validation upon script load
BuildingMasterList.validateMasterList()

return BuildingMasterList