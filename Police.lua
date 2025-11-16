local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Events            = ReplicatedStorage:WaitForChild("Events")
local BindableEvents    = Events:WaitForChild("BindableEvents")

local PoliceSupportUnlocked = BindableEvents:WaitForChild("PoliceSupportUnlocked")

local PoliceHandler = {}
PoliceHandler.__index = PoliceHandler

local activePlayersWithPolice = {}

function PoliceHandler.onSupportUnlocked(player)
	activePlayersWithPolice[player] = true
end

function PoliceHandler.hasSupport(player)
	return activePlayersWithPolice[player] == true
end

PoliceSupportUnlocked.Event:Connect(function(player)
	if player then
		PoliceHandler.onSupportUnlocked(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	activePlayersWithPolice[player] = nil
end)

return PoliceHandler
