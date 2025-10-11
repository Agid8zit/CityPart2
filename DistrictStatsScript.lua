local DistrictStatsModule = require(script.Parent:WaitForChild("DistrictStatsModule"))
local UniqueZones = require(script.Parent.UniqueZones)
local Income = require(script.Parent:WaitForChild("Income"))

local SC = game:GetService("ServerScriptService")
local UI = SC:WaitForChild("UI")


local CentralUIStats = require(UI:WaitForChild("UIDisplay"))

game.Players.PlayerAdded:Connect(function(player)
	wait(10) -- give time for zones to load
	UniqueZones.printZoneTypeCounts(player)

	if UniqueZones.checkZoneMilestone(player, {"Residential", "Commercial", "Industrial"}) then
		print(player.Name, "has built a complete basic city layout!")
	end
end)

-- Initialize the module
DistrictStatsModule.init()
CentralUIStats.init()
