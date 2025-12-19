local PlayerDataController = {}

-- Roblox Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies
local Utility = require(ReplicatedStorage.Scripts.Utility)

-- Networking
local RE_UpdatePlayerData = ReplicatedStorage.Events.RemoteEvents.UpdatePlayerData

-- Defines
local LocalPlayer: Player = shared.LocalPlayer
PlayerDataController.PlayerData = nil
local Listeners = {} -- [Path] = Array<Listener>
local FullListeners = {} -- Array<Listener> (if entire data is changed)
local AnyListeners = {} -- Array<Listener>

local function setValueAtPath(targetTable, path, value)
	local keys = string.split(path, "/")
	local pointer = targetTable
	for i = 1, #keys do
		local key = keys[i]
		if i == #keys then
			pointer[key] = value
		else
			pointer[key] = pointer[key] or {}
			pointer = pointer[key]
		end
	end
end

-- Helper Functions
local function UpdatePlayerData(NewValue: any, Path: string?)
	if Path then
		-- Ensure a container exists, then update the path (creates missing tables)
		if not PlayerDataController.PlayerData then
			PlayerDataController.PlayerData = {}
		end
		setValueAtPath(PlayerDataController.PlayerData, Path, NewValue)
		
		-- Check for broader paths, ex: a/b/c will trigger a/b and a
		local Paths = Utility.GetAllHierarchyPaths(Path)
		-- Trigger every found path
		for _, SpecificPath in Paths do
			-- Listeners
			if Listeners[SpecificPath] then
				local SpecificValue = Utility.GetValueFromPath(PlayerDataController.PlayerData, SpecificPath)
				for _, Listener in Listeners[SpecificPath] do
					Listener(SpecificValue)
				end
			end
		end
		
	else
		-- Update Data
		PlayerDataController.PlayerData = NewValue
		
		-- Trigger Full Listeners
		for _, Listener in FullListeners do
			Listener(NewValue)
		end
		
		-- Update every single Listener based on whatever value they were looking at
		for SpecificPath, SpecificListeners in Listeners do
			local SpecificValue = Utility.GetValueFromPath(PlayerDataController.PlayerData, SpecificPath)
			for _, Listener in SpecificListeners do
				Listener(SpecificValue)
			end
		end 
	end
	
	-- Trigger all any listeners
	for _, Listener in AnyListeners do
		Listener(PlayerDataController.PlayerData)
	end
end

local function AddListener(Path, Listener: () -> ())
	-- Add listener for specific path
	if not Listeners[Path] then
		Listeners[Path] = { Listener }
	else
		table.insert(Listeners[Path], Listener)
	end
end

-- Module Functions
function PlayerDataController.WaitForPlayerData()
	while not PlayerDataController.PlayerData do
		task.wait()
	end
end

function PlayerDataController.ListenForDataChange(Path: string?, Listener: () -> ())
	if Path then
		AddListener(Path, Listener)
	else
		table.insert(FullListeners, Listener)
	end
end

function PlayerDataController.ListenForAnyDataChange(Listener: () -> ())
	table.insert(AnyListeners, Listener)
end

function PlayerDataController.GetData()
	return PlayerDataController.PlayerData
end

function PlayerDataController.GetSaveFileData()
	if not PlayerDataController.PlayerData then return nil end
	return PlayerDataController.PlayerData.savefiles[PlayerDataController.PlayerData.currentSaveFile]
end

-- Networking
RE_UpdatePlayerData.OnClientEvent:Connect(UpdatePlayerData)

return PlayerDataController
