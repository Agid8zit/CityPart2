local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local S3 = game:GetService("ServerScriptService")
local Maint = S3:WaitForChild("Maintenance")
local PlayerCleanupService = require(Maint:WaitForChild("PlayerCleanUp"))
local GridScripts        = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Grid")
local GridConfig         = require(GridScripts:WaitForChild("GridConfig"))

local Events = ReplicatedStorage:FindFirstChild("Events")
if not Events then
	error("Events folder not found in ReplicatedStorage.")
end

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")


local REFolder = Events:WaitForChild("RemoteEvents")
local BEFolder = Events:WaitForChild("BindableEvents")
local plotAssignedEvent = REFolder:FindFirstChild("PlotAssigned")
local plotAssignedBE = BEFolder:FindFirstChild("PlotAssignedBE")
local PlayerSavedEvent = BEFolder:FindFirstChild("PlayerSaved")

if not plotAssignedEvent then
	error("RemoteEvent 'PlotAssigned' not found in ReplicatedStorage.Events.RemoteEvents.")
end

if not plotAssignedBE then
	error("BindableEvent 'PlotAssignedBE' not found in ReplicatedStorage.Events.BindableEvents.")
end

-- Reference to the Plot Data Module
local PlotDataModule = require(script.Parent:WaitForChild("PlotDataManager"))

-- Folder where actual in-use plots will be placed
local plotsFolder = Workspace:FindFirstChild("PlayerPlots")

-- Reference to the Plot Template in ServerStorage
local plotTemplateFolder = ServerStorage:FindFirstChild("PlotTemplates")
if not plotTemplateFolder then
	warn("PlotAssigner: 'PlotTemplates' folder not found in ServerStorage.")
	return
end

local plotTemplate = plotTemplateFolder:FindFirstChild("TestTerrain")
if not plotTemplate then
	warn("PlotAssigner: 'TestTerrain' template not found in ServerStorage.PlotTemplates.")
	return
end

-- Reference to Placeholder Plots in Workspace.Plots
local placeholderPlotsFolder = Workspace:FindFirstChild("Plots")
if not placeholderPlotsFolder then
	error("Plots folder not found in Workspace. Please ensure there are placeholder plots in Workspace.Plots.")
end

local placeholderPlots = placeholderPlotsFolder:GetChildren()
table.sort(placeholderPlots, function(a, b)
	-- Sort plots numerically based on their names (e.g., Plot1, Plot2, ...)
	local aNum = tonumber(a.Name:match("Plot(%d+)")) or 0
	local bNum = tonumber(b.Name:match("Plot(%d+)")) or 0
	return aNum < bNum
end)

-- Ensure each placeholder has a PrimaryPart set
for _, placeholder in ipairs(placeholderPlots) do
	if not placeholder.PrimaryPart then
		local firstPart = placeholder:FindFirstChildWhichIsA("BasePart", true)
		if firstPart then
			placeholder.PrimaryPart = firstPart
			--print(string.format("Set PrimaryPart of placeholder '%s' to '%s'.", placeholder.Name, firstPart.Name))
		else
			--warn(string.format("Placeholder '%s' has no BaseParts to set as PrimaryPart.", placeholder.Name))
		end
	end
end

-- Function to find the next available placeholder plot
local function getNextAvailablePlot()
	for _, placeholder in ipairs(placeholderPlots) do
		if not placeholder:GetAttribute("Assigned") then
			return placeholder
		end
	end
	return nil -- No available plots
end

-- Resolve which part to use as the placement anchor for a placeholder.
-- If the physical placeholder is rotated/offset (plots 3+), you can set
-- PlacementPrimaryPartName on the placeholder to force a specific anchor.
local function resolvePlacementPrimaryPart(placeholder: Model): BasePart?
	if not placeholder then return nil end
	local overrideName = placeholder:GetAttribute("PlacementPrimaryPartName")
	if typeof(overrideName) == "string" and overrideName ~= "" then
		local found = placeholder:FindFirstChild(overrideName, true)
		if found and found:IsA("BasePart") then
			return found
		end
	end
	if placeholder.PrimaryPart then
		return placeholder.PrimaryPart
	end
	return placeholder:FindFirstChildWhichIsA("BasePart", true)
end

-- Build the desired placement CFrame for the player plot. The placeholder can
-- override position/yaw via attributes so we don't inherit bad physical
-- orientation from the map:
--   PlacementPosX/PlacementPosY/PlacementPosZ : target world position
--   PlacementYaw : yaw in degrees
--   PlacementOffsetX/PlacementOffsetY/PlacementOffsetZ : small post-pivot offset
--   PlacementPrimaryPartName : optional anchor part name
local function getPlacementCFrame(placeholder: Model): CFrame?
	if not placeholder then return nil end
	local anchor = resolvePlacementPrimaryPart(placeholder)
	if not anchor then return nil end

	local px = placeholder:GetAttribute("PlacementPosX")
	local py = placeholder:GetAttribute("PlacementPosY")
	local pz = placeholder:GetAttribute("PlacementPosZ")
	local basePos
	if typeof(px) == "number" and typeof(py) == "number" and typeof(pz) == "number" then
		basePos = Vector3.new(px, py, pz)
	else
		basePos = anchor.Position
	end

	local yaw = placeholder:GetAttribute("PlacementYaw")
	if typeof(yaw) ~= "number" then
		yaw = anchor.Orientation.Y
	end

	local cf = CFrame.new(basePos) * CFrame.Angles(0, math.rad(yaw), 0)

	local ox = placeholder:GetAttribute("PlacementOffsetX")
	local oy = placeholder:GetAttribute("PlacementOffsetY")
	local oz = placeholder:GetAttribute("PlacementOffsetZ")
	if typeof(ox) == "number" or typeof(oy) == "number" or typeof(oz) == "number" then
		cf = cf * CFrame.new(ox or 0, oy or 0, oz or 0)
	end

	return cf
end

-- Function to teleport player to their plot
local function teleportPlayerToPlot(player, plot)
	local character = player.Character
	if not character then
		warn(string.format("Teleport: Player '%s' has no character.", player.Name))
		return
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChild("Humanoid")

	if not humanoidRootPart or not humanoid then
		warn(string.format("Teleport: Player '%s' is missing Humanoid or HumanoidRootPart.", player.Name))
		return
	end

	-- Wait until the character is fully loaded and alive
	if humanoid.Health <= 0 then
		humanoid.Died:Wait()
		-- Character died before teleportation
		return
	end

	-- Ensure the plot has a PrimaryPart
	if not plot.PrimaryPart then
		warn(string.format("Teleport: Plot '%s' has no PrimaryPart set.", plot.Name))
		return
	end

	-- Calculate spawn position relative to the plot's PrimaryPart
	local spawnOffset = Vector3.new(0, 5, 0)  -- Adjust Y as needed
	local targetCFrame = plot.PrimaryPart.CFrame * CFrame.new(spawnOffset)

	-- Teleport the character
	character:PivotTo(targetCFrame)
	--humanoidRootPart.CFrame = targetCFrame

	print(string.format("Teleported '%s' to their plot '%s' at position %s.", player.Name, plot.Name, tostring(targetCFrame.Position)))
end

local function teleportPlayerToTheirPlot(player: Player)
	for _, model in workspace.PlayerPlots:GetChildren() do
		if model.Name == "Plot_" .. player.UserId then
			teleportPlayerToPlot(player, model)
			return
		end
	end
end

-- Create a RemoteFunction for clients to request their assigned plot
local GetAssignedPlotFunction = REFolder:FindFirstChild("GetAssignedPlot")
if not GetAssignedPlotFunction then
	GetAssignedPlotFunction = Instance.new("RemoteFunction")
	GetAssignedPlotFunction.Name = "GetAssignedPlot"
	GetAssignedPlotFunction.Parent = REFolder
end

-- Implement the RemoteFunction
GetAssignedPlotFunction.OnServerInvoke = function(player)
	local plot = PlotDataModule:GetPlot(player)
	if plot then
		return plot.Name
	else
		return nil
	end
end

-- Track which placeholder each player is using so we can
local assignedPlaceholders = {}

local function disableQueryingInPlot(plotModel)
	-- Set CanQuery = false on the model itself if applicable
	if plotModel:IsA("BasePart") then
		plotModel.CanQuery = false
	end

	-- Set CanQuery = false for all BaseParts in the model
	for _, descendant in ipairs(plotModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanQuery = false
		end
	end

	-- Specifically disable CanQuery in NatureZones
	local natureZones = plotModel:FindFirstChild("NatureZones")
	if natureZones then
		for _, obj in ipairs(natureZones:GetDescendants()) do
			if obj:IsA("BasePart") then
				obj.CanQuery = false
			end
		end
	end

	-- Disable CanQuery in Unlocks > Unlock# > Segment#
	local unlocksFolder = plotModel:FindFirstChild("Unlocks")
	if unlocksFolder then
		for _, unlock in ipairs(unlocksFolder:GetChildren()) do
			if unlock:IsA("Model") then
				for _, segment in ipairs(unlock:GetChildren()) do
					if segment:IsA("Model") then
						for _, part in ipairs(segment:GetDescendants()) do
							if part:IsA("BasePart") then
								part.CanQuery = false
							end
						end
					end
				end
			end
		end
	end
end

local function setPlotOddEvenAttributes(plotModel: Model?)
	if not plotModel then return end
	local primaryPart = plotModel.PrimaryPart
	if not primaryPart then return end

	local orientationY = primaryPart.Orientation.Y % 360
	if orientationY < 0 then orientationY += 360 end

	local tolerance = 1e-3
	local isOddOrientation  = math.abs(orientationY - 180) <= tolerance
	local isEvenOrientation = (orientationY <= tolerance) or (orientationY >= (360 - tolerance))

	plotModel:SetAttribute("Odd",  isOddOrientation)
	plotModel:SetAttribute("Even", isEvenOrientation)
end

assert(ServerStorage.PlotTemplates.TestTerrain.PrimaryPart, "Missing PrimaryPart for ServerStorage/PlotTemplates/TestTerrain")

-- Event: Player Added
Players.PlayerAdded:Connect(function(player)
	--print(string.format("PlayerAdded: '%s' has joined the game.", player.Name))

	-- Find the next available placeholder plot
	local placeholder = getNextAvailablePlot()
	if not placeholder then
		warn(string.format("No available plots to assign to player '%s'. Consider adding more placeholder plots.", player.Name))
		-- Optionally, notify the player via RemoteEvent
		plotAssignedEvent:FireClient(player, nil, "No available plots at the moment.")
		return
	end

	-- Clone the plot template
	local playerPlot = plotTemplate:Clone()
	disableQueryingInPlot(playerPlot)
	playerPlot.Name = "Plot_" .. player.UserId
	playerPlot:SetAttribute("IsPlayerPlot", true)
	playerPlot:SetAttribute("PlotOwnerId", player.UserId)
	playerPlot.OwnerSign.SurfaceGui.TextLabel.Text = player.Name.."'s Plot"
	playerPlot.Parent = plotsFolder

	local buildingsFolder = Instance.new("Folder")
	buildingsFolder.Name = "Buildings"
	buildingsFolder.Parent = playerPlot

	local PipesFolder = Instance.new("Folder")
	PipesFolder.Name = "Pipes"
	PipesFolder.Parent = playerPlot

	local zoneFolder = Instance.new("Folder")
	zoneFolder.Name = "PlayerZones"
	zoneFolder.Parent = playerPlot

	local WaterPipeZonesFolder = Instance.new("Folder")
	WaterPipeZonesFolder.Name = "WaterPipeZones"
	WaterPipeZonesFolder.Parent = playerPlot

	local PowerLinesZonesFolder = Instance.new("Folder")
	PowerLinesZonesFolder.Name = "PowerLinesZones"
	PowerLinesZonesFolder.Parent = playerPlot

	-- Ensure the template has a PrimaryPart set
	--if not playerPlot.PrimaryPart then
	--	local firstPart = playerPlot:FindFirstChildWhichIsA("BasePart", true)
	--	if firstPart then
	--		playerPlot.PrimaryPart = firstPart
	--		print(string.format("Set PrimaryPart of plot '%s' to '%s'.", playerPlot.Name, firstPart.Name))
	--	else
	--		warn("PlotAssigner: Plot template has no BaseParts to set as PrimaryPart.")
	--		playerPlot:Destroy()
	--		return
	--	end
	--end



	local function disableQueryingInPlot(plotModel)
		-- Set CanQuery = false on the model itself if applicable
		if plotModel:IsA("BasePart") then
			plotModel.CanQuery = false
		end

		-- Set CanQuery = false for all BaseParts in the model
		for _, descendant in ipairs(plotModel:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.CanQuery = false
			end
		end

		-- Specifically disable CanQuery in NatureZones
		local natureZones = plotModel:FindFirstChild("NatureZones")
		if natureZones then
			for _, obj in ipairs(natureZones:GetDescendants()) do
				if obj:IsA("BasePart") then
					obj.CanQuery = false
				end
			end
		end

		-- Disable CanQuery in Unlocks > Unlock# > Segment#
		local unlocksFolder = plotModel:FindFirstChild("Unlocks")
		if unlocksFolder then
			for _, unlock in ipairs(unlocksFolder:GetChildren()) do
				if unlock:IsA("Model") then
					for _, segment in ipairs(unlock:GetChildren()) do
						if segment:IsA("Model") then
							for _, part in ipairs(segment:GetDescendants()) do
								if part:IsA("BasePart") then
									part.CanQuery = false
								end
							end
						end
					end
				end
			end
		end
	end



	-- Set an attribute to inform the client of the PrimaryPart
	playerPlot:SetAttribute("PrimaryPartName", playerPlot.PrimaryPart.Name)

	-- Position the plot at the placeholder's position
	local targetCF = getPlacementCFrame(placeholder)
	if not targetCF then
		targetCF = placeholder.PrimaryPart and placeholder.PrimaryPart.CFrame or placeholder:GetPivot()
	end
	playerPlot:PivotTo(targetCF)
	setPlotOddEvenAttributes(playerPlot)

	-- Determine axis directions based on actual orientation so Odd is canonical (+1,+1)
	local isOddOrientation = playerPlot:GetAttribute("Odd") == true

	local axisDirX = placeholder:GetAttribute("GridAxisDirX")
	if axisDirX ~= 1 and axisDirX ~= -1 then
		axisDirX = isOddOrientation and 1 or -1
	end

	local axisDirZ = placeholder:GetAttribute("GridAxisDirZ")
	if axisDirZ ~= 1 and axisDirZ ~= -1 then
		axisDirZ = isOddOrientation and 1 or -1
	end

	playerPlot:SetAttribute("GridAxisDirX", axisDirX)
	playerPlot:SetAttribute("GridAxisDirZ", axisDirZ)
	GridConfig.setAxisDirectionsForPlot(playerPlot, axisDirX, axisDirZ)

	local GridConfigServer = require(ReplicatedStorage.Scripts.Grid.GridConfig)

	local roadStart = playerPlot:WaitForChild("RoadStart", 2)
	if roadStart then
		GridConfigServer.setStableAnchorFromPart(roadStart)
	else
		warn("PlotAssigner: RoadStart missing on "..playerPlot.Name)
	end

	--playerPlot:SetPrimaryPartCFrame(placeholder.PrimaryPart.CFrame)
	print(string.format("Assigned plot '%s' to placeholder '%s'.", playerPlot.Name, placeholder.Name))

	-- Assign the plot using the PlotDataModule
	PlotDataModule:AssignPlot(player, playerPlot)

	-- Mark the placeholder as assigned and remove it from the workspace
	placeholder:SetAttribute("Assigned", true)
	assignedPlaceholders[player.UserId] = placeholder
	placeholder.Parent = nil  -- Removes the placeholder model from Workspace

	-- Set the player's PlotName attribute so that the unlock manager can find the plot later.
	player:SetAttribute("PlotName", playerPlot.Name)

	-- Function to handle teleportation when the character is added
	local function onCharacterAdded(character)

		local Timeout = os.time() + 10
		while not character.PrimaryPart
			and not character:FindFirstChildWhichIsA("Humanoid")
			and not character:IsDescendantOf(workspace)
		do
			if os.time() > Timeout then return end
			task.wait()
		end

		game:GetService("RunService").Stepped:Wait()

		teleportPlayerToPlot(player, playerPlot)

		--print(string.format("CharacterAdded: '%s' character spawned.", player.Name))
		-- Use a coroutine to ensure teleportation happens after a short delay
		--coroutine.wrap(function()
		--	-- Small delay to ensure character parts are fully loaded
		--	task.wait(1)
		--	teleportPlayerToPlot(player, playerPlot)
		--end)()
	end

	-- Connect CharacterAdded before checking if player.Character exists
	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterAppearanceLoaded:Connect(onCharacterAdded)

	-- If the character already exists, teleport them immediately
	if player.Character then
		onCharacterAdded(player.Character)
	end

	-- Notify the client about the assigned plot using its name
	--plotAssignedEvent:FireClient(player, playerPlot.Name)

	-- Fire the BindableEvent to notify server-side modules
	plotAssignedBE:Fire(player, playerPlot)

	--print(string.format("PlotAssigner: Assigned plot '%s' to player '%s' at placeholder '%s'.", playerPlot.Name, player.Name, placeholder.Name))
end)

local function cleanupPlotForPlayer(player)
	-- The body below is 100 % identical to what you had inside
	-- Players.PlayerRemoving.  Only indentation was changed.
	local plot = PlotDataModule:GetPlot(player)
	if plot then
		-- restore placeholder
		local placeholder = assignedPlaceholders[player.UserId]
		if placeholder then
			placeholder.Parent = placeholderPlotsFolder
			placeholder:SetAttribute("Assigned", false)
			assignedPlaceholders[player.UserId] = nil
			print(string.format("Cleared assignment and restored placeholder '%s'.", placeholder.Name))
		end

		-- destroy cloned plot
		plot:Destroy()
		print(string.format("PlotAssigner: Removed plot '%s' for player '%s'.", plot.Name, player.Name))
		PlotDataModule:RemovePlot(player)
	else
		print(string.format("PlotAssigner: No plot found for player '%s' to remove.", player.Name))
	end

	-- extra clean-up handled by the service
	PlayerCleanupService.cleanupPlayer(player)
end


-- Event: Player Removing
PlayerSavedEvent.Event:Connect(cleanupPlotForPlayer)

--
ReplicatedStorage.Events.RemoteEvents.TeleportToHomePlot.OnServerEvent:Connect(function(Player: Player)
	teleportPlayerToTheirPlot(Player)
end)

-- Optional: Handle Server Shutdown to clean up plots
game:BindToClose(function()
	print("Server is shutting down. Cleaning up plots...")

	for userId, plot in pairs(PlotDataModule.playerPlots) do
		if plot then
			plot:Destroy()
			print(string.format("PlotAssigner: Cleaned up plot '%s' for user ID '%d' on shutdown.", 
				plot.Name, userId))
		end
	end

	-- Also restore placeholder models back to the folder if they were removed
	for userId, placeholder in pairs(assignedPlaceholders) do
		if placeholder then
			placeholder.Parent = placeholderPlotsFolder
			placeholder:SetAttribute("Assigned", false)
			print(string.format("PlotAssigner: Restored placeholder '%s' for user ID '%d' on shutdown.", 
				placeholder.Name, userId))
		end
	end
end)
