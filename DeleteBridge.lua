-- ServerScriptService/Build/Zones/ZoneManager/DeleteBridge.lua
local Replicated      = game:GetService("ReplicatedStorage")
local S3 			  = game:GetService("ServerScriptService")
local Bld 			  = S3.Build
local Zone 			  = Bld.Zones
local Cmd 			  = Zone.Commands
local RemoteEvents    = Replicated:WaitForChild("Events"):WaitForChild("RemoteEvents")
local reqDelete       = RemoteEvents:WaitForChild("RequestDeleteZone")
local confirmDelete   = RemoteEvents:WaitForChild("ConfirmDeleteZone")


local ZoneManager     = require(script.Parent:WaitForChild("ZoneManager"))

local PlayerCmdMgr       = require(Cmd.PlayerCommandManager)
local DeleteZoneCommand  = require(Cmd.DeleteZoneCom)


---------------------------------------------------------------------
-- sanity helper: only owner may delete their own zone
---------------------------------------------------------------------
local function isOwner(player, zoneId)
	local uid = player.UserId
	local prefixes = {
		"Zone_",            -- generic zones
		"RoadZone_",        -- roads
		"PipeZone_",        -- water pipes
		"PowerLinesZone_",  -- power lines 
		"MetroTunnelZone_", -- METRO TUNNELS
		"MetroEntranceZone_"
	}
	for _, p in ipairs(prefixes) do
		local want = p .. uid .. "_"
		if zoneId:sub(1, #want) == want then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------
-- request handler
---------------------------------------------------------------------
reqDelete.OnServerEvent:Connect(function(player, zoneId)
	if type(zoneId) ~= "string" or not isOwner(player, zoneId) then return end

	-- hand the action to the player’s command manager
	local mgr = PlayerCmdMgr:getManager(player)
	mgr:enqueueCommand(DeleteZoneCommand.new(player, zoneId))
end)
