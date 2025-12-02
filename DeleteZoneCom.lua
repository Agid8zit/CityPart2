local Command        = require(script.Parent.Command)
local S3             = game:GetService("ServerScriptService")
local Bld            = S3.Build
local Dist           = Bld.Districts
local Stats          = Dist.Stats
local Zone           = Bld.Zones
local ZoneMgr        = Zone.ZoneManager

local ZoneManager    = require(ZoneMgr.ZoneManager)
local ZoneTracker    = require(ZoneMgr.ZoneTracker)
local ZoneDisplay    = require(ZoneMgr.ZoneDisplay)

local EconomyService = require(ZoneMgr.EconomyService)
local XPManager      = require(Stats.XPManager)
local PlayerDataInterfaceService = require(S3.Services.PlayerDataInterfaceService)

local RS             = game:GetService("ReplicatedStorage")
local BindableEvents = RS:WaitForChild("Events"):WaitForChild("BindableEvents")
local ZoneRemovedEvt = BindableEvents:WaitForChild("ZoneRemoved")
local ZoneCreatedEvt = BindableEvents:WaitForChild("ZoneCreated")
local ConfirmDelete  = RS.Events.RemoteEvents:WaitForChild("ConfirmDeleteZone")

local DeleteZoneCommand  = {}
DeleteZoneCommand.__index     = DeleteZoneCommand
DeleteZoneCommand.__className = "DeleteZoneCommand"
setmetatable(DeleteZoneCommand, Command)

local COIN_REFUND_WINDOW = 60
local LATE_REFUND_MODES = {
	Airport = 0.25,
	BusDepot = 0.25,
}
local DEBUG = true
local function d(...) if DEBUG then print("[DeleteZoneCommand]", ...) end end

--------------------------------------------------------------------- ctor
function DeleteZoneCommand.new(player, zoneId)
	local self = setmetatable({}, DeleteZoneCommand)
	self.player     = player
	self.zoneId     = zoneId
	self.zoneData   = nil   -- filled in execute()
	self.skipQueue  = true  -- run immediately like BuildZoneCommand
	-- bookkeeping to support symmetric undo
	self._coinRefundAmount = 0
	self._returnedExclusive = 0
	return self
end

--------------------------------------------------------------------- helpers
local function computeAgeSeconds(self)
	-- Prefer the refund clock (starts on population); if the zone never populated, treat age as 0.
	local populated = self.zoneData and self.zoneData.requirements and self.zoneData.requirements.Populated

	local startAt = ZoneTracker.getRefundClockAt(self.player, self.zoneId)
	if not startAt and self.zoneData then
		-- Allow a late-set refund clock from persisted data (populated-on-save)
		startAt = self.zoneData.refundClockAt
		-- Only fall back to createdAt if the zone was already populated in the snapshot
		if not startAt and populated then
			startAt = self.zoneData.createdAt
		end
	end

	if type(startAt) == "number" and startAt > 0 then
		return math.max(0, os.time() - startAt)
	end

	-- If never populated, do NOT fall back to XP timestamps; window hasn’t started.
	if not populated then
		return 0
	end

	local t0 = XPManager.getZoneAwardTimestamp(self.player, self.zoneId)
	if type(t0) == "number" and t0 > 0 then
		return math.max(0, os.time() - t0)
	end

	return 0
end

local function removeZone(self)
	-- ① remove from managers / trackers
	if ZoneManager.onRemoveZone(self.player, self.zoneId) then
		-- Trigger XP auto-undo window in XPManager
		ZoneRemovedEvt:Fire(self.player, self.zoneId, self.zoneData.mode, self.zoneData.gridList)

		-- Server visuals cleanup
		ZoneDisplay.removeZonePart(self.player, self.zoneId)

		-- ② Financials & exclusives per policy
		if self.zoneData then
			local mode     = self.zoneData.mode
			local gridList = (type(self.zoneData.gridList) == "table") and self.zoneData.gridList or {}
			local cost     = EconomyService.getCost(mode, #gridList)
			local age      = computeAgeSeconds(self)

			local refund   = 0

			-- Coins: refund within window; after window allow partial for specific modes
			if cost ~= "ROBUX" and type(cost) == "number" and cost > 0 then
				if age <= COIN_REFUND_WINDOW then
					refund = cost
				else
					local pct = LATE_REFUND_MODES[mode]
					if pct then
						refund = math.floor(cost * pct)
					end
				end
			end

			if refund > 0 then
				EconomyService.adjustBalance(self.player, refund)
				self._coinRefundAmount = refund
				d(("Coins refunded %d (age=%ds, mode=%s)"):format(refund, age, tostring(mode)))
			else
				self._coinRefundAmount = 0
				d(("Coins not refunded (cost=%s, age=%ds)"):format(tostring(cost), age))
			end

			-- Robux-exclusive: ALWAYS return 1 for this delete
			if EconomyService.isRobuxExclusiveBuilding(mode) then
				PlayerDataInterfaceService.IncrementExclusiveLocation(self.player, mode, 1)
				self._returnedExclusive += 1
				d(("Returned exclusive '%s' x1"):format(tostring(mode)))
			end
		end

		-- Client confirmation / FX
		ConfirmDelete:FireAllClients(self.zoneId, true)
		self._removed = true
	else
		error("DeleteZoneCommand: could not delete "..self.zoneId)
	end
end

local function rebuildZone(self)
	if not self._removed then return end

	-- ① register again (server state)
	assert(ZoneManager.onAddZone(
		self.player, self.zoneId, self.zoneData.mode, self.zoneData.gridList),
		"DeleteZoneCommand: failed restore")

	-- ② fire creation so XPManager awards again (single source of XP)
	ZoneCreatedEvt:Fire(
		self.player,
		self.zoneId,
		self.zoneData.mode,
		self.zoneData.gridList,
		self.zoneData.buildings or {},
		0
	)

	-- ③ re-apply *only* what we actually refunded/returned
	-- Coins: charge back only if we had refunded during delete
	if self._coinRefundAmount and self._coinRefundAmount > 0 then
		local mode = self.zoneData.mode
		EconomyService.chargePlayer(self.player, self._coinRefundAmount)
		d(("Charged back %d coins on undo (mode=%s)"):format(self._coinRefundAmount, tostring(mode)))
		self._coinRefundAmount = 0
	end
	-- Robux-exclusive: if we returned one on delete, re-consume it now
	if self._returnedExclusive > 0 then
		PlayerDataInterfaceService.IncrementExclusiveLocation(self.player, self.zoneData.mode, -self._returnedExclusive)
		d(("Re-consumed exclusive '%s' x%d on undo"):format(self.zoneData.mode, self._returnedExclusive))
	end

	self._removed = false
end

--------------------------------------------------------------------- Command API
function DeleteZoneCommand:execute()
	d("execute", self.player.Name, self.zoneId)

	-- cache everything we will need for undo *once*, before deletion
	self.zoneData = ZoneTracker.getZoneById(self.player, self.zoneId)
	assert(self.zoneData, "Zone not found: "..tostring(self.zoneId))

	removeZone(self)
end

function DeleteZoneCommand:undo()
	d("undo", self.zoneId)
	rebuildZone(self)
end

function DeleteZoneCommand:containsZone(z)
	return z == self.zoneId
end

return DeleteZoneCommand
