local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Events = ReplicatedStorage:WaitForChild("Events")
local RemoteEvents = Events:WaitForChild("RemoteEvents")

local remote = RemoteEvents:FindFirstChild("GetDeleteRefundPreview")
if not remote then
	remote = Instance.new("RemoteFunction")
	remote.Name = "GetDeleteRefundPreview"
	remote.Parent = RemoteEvents
end

local Bld = ServerScriptService:WaitForChild("Build")
local Districts = Bld:WaitForChild("Districts")
local Stats = Districts:WaitForChild("Stats")
local Zones = Bld:WaitForChild("Zones")
local ZoneMgr = Zones:WaitForChild("ZoneManager")

local ZoneTracker = require(ZoneMgr:WaitForChild("ZoneTracker"))
local EconomyService = require(ZoneMgr:WaitForChild("EconomyService"))
local XPManager = require(Stats:WaitForChild("XPManager"))

local COIN_REFUND_WINDOW = 60
local LATE_REFUND_MODES = {
	Airport = 0.25,
	BusDepot = 0.25,
}

local OWNERSHIP_PREFIXES = {
	"Zone_",
	"RoadZone_",
	"PipeZone_",
	"PowerLinesZone_",
	"MetroTunnelZone_",
	"MetroEntranceZone_",
}

local function isOwner(player: Player, zoneId: string): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	if typeof(zoneId) ~= "string" then
		return false
	end

	local uid = player.UserId
	for _, prefix in ipairs(OWNERSHIP_PREFIXES) do
		local want = prefix .. uid .. "_"
		if zoneId:sub(1, #want) == want then
			return true
		end
	end

	return false
end

local function computeAgeSeconds(player: Player, zoneId: string, zoneData)
	if typeof(zoneData) == "table" then
		local createdAt = zoneData.createdAt
		if typeof(createdAt) == "number" and createdAt > 0 then
			return os.time() - createdAt
		end
	end

	local awardedAt = XPManager.getZoneAwardTimestamp(player, zoneId)
	if typeof(awardedAt) == "number" and awardedAt > 0 then
		return os.time() - awardedAt
	end

	return math.huge
end

local function computeCoinRefund(mode, cost, ageSeconds)
	if typeof(cost) ~= "number" or cost <= 0 then
		return 0
	end

	if ageSeconds <= COIN_REFUND_WINDOW then
		return cost
	end

	local pct = LATE_REFUND_MODES[mode]
	if pct then
		return math.floor(cost * pct)
	end

	return 0
end

local function buildPreview(player: Player, zoneId: string)
	local zoneData = ZoneTracker.getZoneById(player, zoneId)
	if not zoneData then
		return {
			ok = false,
			reason = "ZoneMissing",
		}
	end

	local gridList = (typeof(zoneData.gridList) == "table") and zoneData.gridList or {}
	local gridCount = #gridList
	local mode = zoneData.mode
	local cost = EconomyService.getCost(mode, gridCount)
	local ageSeconds = computeAgeSeconds(player, zoneId, zoneData)

	local withinWindow = ageSeconds <= COIN_REFUND_WINDOW
	local isExclusive = EconomyService.isRobuxExclusiveBuilding(mode) == true

	local coinRefund = computeCoinRefund(mode, cost, ageSeconds)

	return {
		ok = true,
		zoneId = zoneId,
		mode = mode,
		gridCount = gridCount,
		withinWindow = withinWindow,
		ageSeconds = ageSeconds,
		coinRefund = coinRefund,
		cost = cost,
		isExclusive = isExclusive,
		refundWindowSeconds = COIN_REFUND_WINDOW,
	}
end

remote.OnServerInvoke = function(player: Player, zoneId: string)
	if not isOwner(player, zoneId) then
		return {
			ok = false,
			reason = "NotOwner",
		}
	end

	return buildPreview(player, zoneId)
end
