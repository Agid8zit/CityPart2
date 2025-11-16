local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Events            = ReplicatedStorage:WaitForChild("Events")
local BindableEvents    = Events:WaitForChild("BindableEvents")

local HealthSupportUnlocked = BindableEvents:WaitForChild("HealthSupportUnlocked")

local HealthHandler = {}
HealthHandler.__index = HealthHandler

local activePlayersWithHealth = {}

function HealthHandler.onSupportUnlocked(player)
	activePlayersWithHealth[player] = true
end

function HealthHandler.hasSupport(player)
	return activePlayersWithHealth[player] == true
end

HealthSupportUnlocked.Event:Connect(function(player)
	if player then
		HealthHandler.onSupportUnlocked(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	activePlayersWithHealth[player] = nil
end)

return HealthHandler
