local ReplicatedStorage = game:GetService("ReplicatedStorage")
local selectZoneEvent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents"):WaitForChild("SelectZoneType")

local BuildingMasterList = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("BuildingManager"):WaitForChild("BuildingMasterList"))
local GridConfig = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Grid"):WaitForChild("GridConfig"))
local GRID_SIZE = GridConfig.GRID_SIZE

-- Simple helper to calculate the bounding box of a Model
local function getBoundingBox(model: Model)
	-- If the model has a PrimaryPart, Roblox .GetExtentsSize() is simplest
	-- or you can manually iterate all BaseParts for exact bounding box.
	local size = model:GetExtentsSize()
	return size
end

local function onSelectZone(player, buildingName)
	if buildingName == "WaterTower" then
		-- Find the building data for the WaterTower under Utilities -> Water -> Default
		local waterTowerList = BuildingMasterList.getUtilityBuilding("Water", "Default", "WaterTower")
		local waterTowerData = waterTowerList[1]

		if waterTowerData and waterTowerData.stages and waterTowerData.stages.Stage3 then
			local finalModel = waterTowerData.stages.Stage3  -- The actual Model/Prefab

			-- Clone so we can measure it
			local clone = finalModel:Clone()
			clone.Parent = workspace

			-- For a clean measurement, pivot it to (0,100,0) so it doesn’t intersect anything else
			clone:PivotTo(CFrame.new(0, 100, 0))

			-- Get bounding box in studs
			local bbSize = getBoundingBox(clone)

			-- Convert bounding box dimensions to “number of grid cells”
			local gridWidth  = math.ceil(bbSize.X / GRID_SIZE)
			local gridLength = math.ceil(bbSize.Z / GRID_SIZE)

			print(("WaterTower spans approximately %dx%d grid cells"):format(gridWidth, gridLength))

			-- If you only needed the clone for measurement, you can clean it up now
			clone:Destroy()
		else
			warn("Could not find WaterTower data in BuildingMasterList!")
		end
	end
end

selectZoneEvent.OnServerEvent:Connect(onSelectZone)
