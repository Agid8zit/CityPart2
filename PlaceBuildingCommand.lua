local Command = require(script.Parent.Command)
local ZoneManager = require(game.ServerScriptService.Build.Zones.ZoneManager.ZoneManager)
local Workspace = game:GetService("Workspace")

local S3 = game:GetService("ServerScriptService")
local ServerScriptService = game:GetService("ServerScriptService")

--Bld Gen
local Bld = S3:WaitForChild("Build")
local Zn = Bld:WaitForChild("Zones")
local CC = Zn:WaitForChild("CoreConcepts")
local Di = CC:WaitForChild("Districts")
local BldGen = Di:WaitForChild("Building Gen")
local BuildingGeneratorModule = require(BldGen:WaitForChild("BuildingGenerator"))

local RS = game:GetService("ReplicatedStorage")
local Sc = RS:WaitForChild("Scripts")
local BldMgr = Sc:WaitForChild("BuildingManager")
local BuildingMasterList = BldMgr:WaitForChild("BuildingMasterList")


local PlaceBuildingCommand = {}
PlaceBuildingCommand.__index = PlaceBuildingCommand
setmetatable(PlaceBuildingCommand, Command)

-- Constructor
function PlaceBuildingCommand.new(player, gridPosition, buildingType)
	local self = setmetatable({}, PlaceBuildingCommand)
	self.player = player
	self.gridPosition = gridPosition
	self.buildingType = buildingType
	self.buildingId = nil
	return self
end

-- Execute method
function PlaceBuildingCommand:execute()
	local placementFunction = ZoneManager["onPlace" .. self.buildingType]
	if typeof(placementFunction) == "function" then
		local success, result = placementFunction(self.player, self.gridPosition)
		if success then
			self.buildingId = result.zoneId or result.buildingId or result
			-- Cache additional data for redo
			self.zoneId = result.zoneId
			self.buildingName = result.buildingName
			self.rotation = result.rotation or 0
			self.gridX = self.gridPosition.x
			self.gridZ = self.gridPosition.z
			self.isUtility = result.isUtility or false
		else
			error("PlaceBuildingCommand: Failed to place " .. self.buildingType .. " - " .. tostring(result))
		end
	else
		error("PlaceBuildingCommand: No handler found for building type: " .. tostring(self.buildingType))
	end
end

function PlaceBuildingCommand:redo()
	if self.zoneId and self.buildingName then
		local buildingData = require(BuildingMasterList).getBuildingByName(self.buildingName)
		if not buildingData then
			warn("Redo failed: Building data not found for", self.buildingName)
			return
		end

		-- Get terrain
		local plotName = "Plot_" .. self.player.UserId
		local plot = Workspace:FindFirstChild("PlayerPlots") and Workspace.PlayerPlots:FindFirstChild(plotName)
		if not plot then
			warn("Redo failed: Player plot not found")
			return
		end
		local terrain = plot:FindFirstChild("TestTerrain")
		if not terrain then
			warn("Redo failed: Terrain not found")
			return
		end

		-- Build again
		local zoneFolder = plot:FindFirstChild("Buildings") and plot.Buildings:FindFirstChild("Populated") and plot.Buildings.Populated:FindFirstChild(self.zoneId)
		if not zoneFolder then
			warn("Redo failed: Zone folder not found")
			return
		end

		BuildingGeneratorModule.generateBuilding(
			terrain,
			zoneFolder,
			self.player,
			self.zoneId,
			self.buildingType,
			{ x = self.gridX, z = self.gridZ },
			buildingData,
			self.isUtility,
			self.rotation
		)
	else
		warn("Redo failed: Incomplete data")
	end
end

-- Undo method
function PlaceBuildingCommand:undo()
	if self.buildingId then
		local removalFunction = ZoneManager["remove" .. self.buildingType]
		if typeof(removalFunction) == "function" then
			local success = removalFunction(self.player, self.buildingId)
			if not success then
				warn("PlaceBuildingCommand: Failed to undo " .. self.buildingType .. " placement for ID:", self.buildingId)
			end
		else
			warn("PlaceBuildingCommand: No removal function found for building type:", self.buildingType)
		end
	else
		warn("PlaceBuildingCommand: No buildingId to undo.")
	end
end

return PlaceBuildingCommand