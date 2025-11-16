local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Events            = ReplicatedStorage:WaitForChild("Events")
local BindableEvents    = Events:WaitForChild("BindableEvents")

local TrashSupportUnlocked = BindableEvents:WaitForChild("TrashSupportUnlocked")

local TrashHandler = {}
TrashHandler.__index = TrashHandler

local activePlayersWithTrash = {}

function TrashHandler.onSupportUnlocked(player)
	activePlayersWithTrash[player] = true
end

function TrashHandler.hasSupport(player)
	return activePlayersWithTrash[player] == true
end

TrashSupportUnlocked.Event:Connect(function(player)
	if player then
		TrashHandler.onSupportUnlocked(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	activePlayersWithTrash[player] = nil
end)

return TrashHandler
