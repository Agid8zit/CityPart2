local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Events = ReplicatedStorage:WaitForChild("Events")
local REFolder = Events:WaitForChild("RemoteEvents")
local plotAssignedEvent = REFolder:WaitForChild("PlotAssigned")
local GetAssignedPlotFunction = REFolder:WaitForChild("GetAssignedPlot")

local PlotManager = {}
PlotManager.PlayerPlot = nil

-- Function to assign the plot
local function assignPlot(plotName)
	print("PlotManager: Assigning plot", plotName)

	-- Wait for the plot to appear in the workspace
	local plot
	repeat
		local playerPlotsFolder = workspace:WaitForChild("PlayerPlots")
		plot = playerPlotsFolder:FindFirstChild(plotName)
		if not plot then
			task.wait(0.1)
		end
	until plot

	PlotManager.PlayerPlot = plot
	print("PlotManager: Found plot", plot.Name)

	-- Proceed to set PrimaryPart
	local primaryPartName = plot:GetAttribute("PrimaryPartName")
	if primaryPartName then
		local primaryPart = plot:FindFirstChild(primaryPartName, true)
		if primaryPart then
			plot.PrimaryPart = primaryPart
			print("PlotManager: Set PrimaryPart to", primaryPart.Name)
		else
			warn("PlotManager: Could not find PrimaryPart named", primaryPartName)
		end
	else
		warn("PlotManager: No PrimaryPartName attribute on plot")
	end
end

-- Listen for the plot assigned event
plotAssignedEvent.OnClientEvent:Connect(function(plotName)
	assignPlot(plotName)
end)

-- Check if plot is already assigned (in case the event was missed)
task.defer(function()
	if not PlotManager.PlayerPlot then
		local plotName = GetAssignedPlotFunction:InvokeServer()
		if plotName then
			print("PlotManager: Retrieved plot name from server:", plotName)
			assignPlot(plotName)
		else
			print("PlotManager: No plot assigned to player.")
		end
	end
end)

return PlotManager
