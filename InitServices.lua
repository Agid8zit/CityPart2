
local ServiceModule = {} -- [ModuleName] = Module
local ServiceModule_PlayersAdded = {} -- [ModuleName] = Module
local ServiceModule_PlayersRemoved = {} -- [ModuleName] = Module

for _, ModuleScript in game.ServerScriptService.Services:GetChildren() do
	local Module = require(ModuleScript)
	ServiceModule[ModuleScript.Name] = Module
	if Module.Init then
		Module.Init()
	end
	if Module.PlayerAdded then
		ServiceModule_PlayersAdded[ModuleScript.Name] = Module
	end
	if Module.PlayerRemoved then
		ServiceModule_PlayersRemoved[ModuleScript.Name] = Module
	end
end


game.Players.PlayerAdded:Connect(function(Player)
	for _, Module in ServiceModule_PlayersAdded do
		Module.PlayerAdded(Player)
	end
end)
for _, Player in game.Players:GetPlayers() do
	for _, Module in ServiceModule_PlayersAdded do
		Module.PlayerAdded(Player)
	end
end

game.Players.PlayerRemoving:Connect(function(Player)
	for _, Module in ServiceModule_PlayersRemoved do
		Module.PlayerRemoved(Player)
	end
end)