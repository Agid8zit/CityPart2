local Command = require(script.Parent.Command)

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local Build          = ServerScriptService:WaitForChild("Build")
local ZonesFolder    = Build:WaitForChild("Zones")
local ZoneMgrFolder  = ZonesFolder:WaitForChild("ZoneManager")
local ZoneManager    = require(ZoneMgrFolder:WaitForChild("ZoneManager"))
local EconomyService = require(ZoneMgrFolder:WaitForChild("EconomyService"))

local RemoteEvents         = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents")
local notifyZoneCreatedEvt = RemoteEvents:WaitForChild("NotifyZoneCreated")

local PlaceWaterTowerCommand = {}
PlaceWaterTowerCommand.__index = PlaceWaterTowerCommand
setmetatable(PlaceWaterTowerCommand, Command)
PlaceWaterTowerCommand.__className = "PlaceWaterTowerCommand"

function PlaceWaterTowerCommand.new(player, gridPosition)
	local self = setmetatable({}, PlaceWaterTowerCommand)
	self.player       = player
	self.gridPosition = gridPosition
	self.waterTowerId = nil
	self.cost         = 0
	return self
end

function PlaceWaterTowerCommand:toData()
	return {
		CommandType = "PlaceWaterTowerCommand",
		Parameters  = {
			gridPosition = { x = self.gridPosition.x, z = self.gridPosition.z },
			waterTowerId = self.waterTowerId,
		},
		Timestamp = os.time(),
	}
end

function PlaceWaterTowerCommand.fromData(player, parameters)
	local pos = Vector2.new(parameters.gridPosition.x, parameters.gridPosition.z)
	local cmd = PlaceWaterTowerCommand.new(player, pos)
	cmd.waterTowerId = parameters.waterTowerId
	return cmd
end

function PlaceWaterTowerCommand:execute()
	-- Charge player
	local cost = EconomyService.getCost("waterTower", 1)
	self.cost = cost
	if not EconomyService.chargePlayer(self.player, cost) then
		error("Insufficient funds for water tower. Required: "..cost)
	end

	-- Place
	local success, msg = ZoneManager.onPlaceWaterTower(self.player, self.gridPosition)
	if success then
		self.waterTowerId = msg.zoneId
		notifyZoneCreatedEvt:FireClient(self.player, self.waterTowerId, {})
	else
		error("Failed to place water tower – "..tostring(msg))
	end
end

function PlaceWaterTowerCommand:undo()
	if self.waterTowerId then
		local ok = ZoneManager.removeWaterTower(self.player, self.waterTowerId)
		if ok then
			-- Refund
			if self.cost and self.cost > 0 then
				EconomyService.adjustBalance(self.player, self.cost)
			end
		else
			warn("[PlaceWaterTowerCommand] Failed undo for waterTowerId:", self.waterTowerId)
		end
	else
		warn("[PlaceWaterTowerCommand] No waterTowerId to undo.")
	end
end

return PlaceWaterTowerCommand
