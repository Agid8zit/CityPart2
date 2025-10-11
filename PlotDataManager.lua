-- PlotDataManager.lua
local PlotDataManager = {}
PlotDataManager.playerPlots = {} -- Maps player UserId to plot

-- Assigns a plot to a player
function PlotDataManager:AssignPlot(player, plot)
	self.playerPlots[player.UserId] = plot
end

-- Retrieves the assigned plot for a player
function PlotDataManager:GetPlot(player)
	return self.playerPlots[player.UserId]
end

-- Removes the plot assignment for a player
function PlotDataManager:RemovePlot(player)
	self.playerPlots[player.UserId] = nil
end

-- Checks if a plot is already assigned
function PlotDataManager:IsPlotAssigned(plot)
	for _, assignedPlot in pairs(self.playerPlots) do
		if assignedPlot == plot then
			return true
		end
	end
	return false
end

-- Determines if a model is a valid plot based on naming convention
function PlotDataManager:IsPlot(plot)
	-- Define your criteria for a plot. For example, plots might start with "Plot" in their name
	return plot:IsA("Model") and plot.Name:sub(1, 4) == "Plot"
end

-- **New Method: Retrieves a plot by its name**
function PlotDataManager:GetPlotByName(plotName)
	for _, plot in pairs(self.playerPlots) do
		if plot.Name == plotName then
			return plot
		end
	end
	return nil
end

return PlotDataManager
