local ReplicatedStorage = game:GetService("ReplicatedStorage")
local S3 = game:GetService("ServerScriptService")
local Build = S3:WaitForChild("Build")
local Zones = Build:WaitForChild("Zones")
local ZoneMgr = Zones:WaitForChild("ZoneManager")
local FuncTestGroundRS = ReplicatedStorage:WaitForChild("FuncTestGroundRS")
local Alarms = FuncTestGroundRS:WaitForChild("Alarms")
local FireTemplate = Alarms:WaitForChild("Fire")

local Events = ReplicatedStorage:WaitForChild("Events")
local BE = Events:WaitForChild("BindableEvents")
local ZonePopulatedEvent = BE:WaitForChild("ZonePopulated")

local ZoneTrackerModule = require(ZoneMgr:WaitForChild("ZoneTracker"))

local FireSupportUnlocked = BE:WaitForChild("FireSupportUnlocked")

local FireHandler = {}
FireHandler.__index = FireHandler

local IGNORED_BUILDING_NAMES = {
	["FireDept"] = true,
	["FireStation"] = true,
	["FirePrecinct"] = true,
}

local activePlayersWithFireSupport = {}

--  Infinite Fire Loop
task.spawn(function()
	while true do
		task.wait(120) -- adjust the interval (in seconds) as desired

		for player, _ in pairs(activePlayersWithFireSupport) do
			local success, err = pcall(function()
				local playerPlot = workspace:FindFirstChild("PlayerPlots"):FindFirstChild("Plot_" .. player.UserId)
				if not playerPlot then return end

				local populatedFolder = playerPlot:FindFirstChild("Buildings") and playerPlot.Buildings:FindFirstChild("Populated")
				if not populatedFolder then return end

				-- Collect all eligible models across all valid fire zones
				local validModels = {}

				local allZones = ZoneTrackerModule.getAllZones(player)
				for zoneId, zoneData in pairs(allZones) do
					if zoneData and zoneData.mode and (zoneData.mode == "Residential" or zoneData.mode == "FireStation" or zoneData.mode == "FirePrecinct") then
						local zoneFolder = populatedFolder:FindFirstChild(zoneId)
						if zoneFolder then
							for _, model in ipairs(zoneFolder:GetChildren()) do
								if model:IsA("Model") and model.PrimaryPart and not IGNORED_BUILDING_NAMES[model.Name] then
									table.insert(validModels, model)
								end
							end
						end
					end
				end

				-- Pick a random one and spawn a fire
				if #validModels > 0 then
					local chosenModel = validModels[math.random(1, #validModels)]
					local fireClone = FireTemplate:Clone()
					fireClone.Anchored = true
					fireClone.CFrame = CFrame.new(chosenModel.PrimaryPart.Position + Vector3.new(0, 2, 0))
					fireClone.Parent = chosenModel

					local clickDetector = Instance.new("ClickDetector")
					clickDetector.MaxActivationDistance = 32
					clickDetector.Parent = fireClone

					clickDetector.MouseClick:Connect(function(clickedPlayer)
						if clickedPlayer == player then
							fireClone:Destroy()
							print("[FireHandler] Fire extinguished by", player.Name)
						end
					end)

					print("[FireHandler] Fire randomly spawned on", chosenModel.Name, "for", player.Name)
				end
			end)
			if not success then
				warn("[FireHandler] Error during fire spawn loop:", err)
			end
		end
	end
end)

-- Called when zone gets populated
function FireHandler.onFireSupportUnlocked(player)
	activePlayersWithFireSupport[player] = true
end

FireSupportUnlocked.Event:Connect(function(player)
	print("[FireHandler] FireSupportUnlocked triggered for", player.Name)
	FireHandler.onFireSupportUnlocked(player)
end)

return FireHandler
