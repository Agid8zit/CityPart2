-- BuildRoadCommand.lua
local BuildRoadCommand = {}
BuildRoadCommand.__index = BuildRoadCommand

-- Services & References
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local Build           = ServerScriptService:WaitForChild("Build")
local ZoneMgr         = Build:WaitForChild("Zones"):WaitForChild("ZoneManager")
local ZoneManager     = require(ZoneMgr:WaitForChild("ZoneManager"))
local ZoneTracker     = require(ZoneMgr:WaitForChild("ZoneTracker"))
local EconomyService  = require(ZoneMgr:WaitForChild("EconomyService"))

local Transport       = Build:WaitForChild("Transport")
local PathingFolder   = Transport:WaitForChild("Roads"):WaitForChild("CoreConcepts"):WaitForChild("Pathing")
local PathingModule   = require(PathingFolder:WaitForChild("PathingModule"))

local Roads       = Transport.Roads
local CC          = Roads.CoreConcepts
local Rds         = CC.Roads
local Roadgen     = Rds.RoadGen
local RoadGeneratorModule  = require(Roadgen.RoadGenerator)  -- required by your file

local BindableEvents       = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents")
local RemoteEvents         = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents")
local zoneCreatedEvent     = BindableEvents:WaitForChild("ZoneCreated")
local notifyZoneCreatedEvt = RemoteEvents:WaitForChild("NotifyZoneCreated")

--================================================================================
-- Constructor / (De)Serialization
--================================================================================
function BuildRoadCommand.new(player, startCoord, endCoord, mode)
	local self = setmetatable({}, BuildRoadCommand)
	self.player     = player
	self.startCoord = startCoord
	self.endCoord   = endCoord
	self.mode       = mode
	self.roadId     = nil
	self.gridList   = nil
	self.cost       = 0
	self.wasCharged = false
	self.snapshot   = nil   -- << exact replay payload (segments + decorations)
	return self
end

function BuildRoadCommand:toData()
	return {
		CommandType = "BuildRoadCommand",
		Parameters  = {
			startCoord = { x = self.startCoord.x, y = self.startCoord.y, z = self.startCoord.z },
			endCoord   = { x = self.endCoord.x,   y = self.endCoord.y,   z = self.endCoord.z   },
			mode       = self.mode,
			roadId     = self.roadId,
			gridList   = self.gridList,
			snapshot   = self.snapshot, -- << serializable Lua table
		},
		Timestamp = os.time(),
	}
end

function BuildRoadCommand.fromData(player, parameters)
	local startCoord = Vector3.new(parameters.startCoord.x, parameters.startCoord.y, parameters.startCoord.z)
	local endCoord   = Vector3.new(parameters.endCoord.x,   parameters.endCoord.y,   parameters.endCoord.z)
	local cmd = BuildRoadCommand.new(player, startCoord, endCoord, parameters.mode)
	cmd.roadId   = parameters.roadId
	cmd.gridList = parameters.gridList
	cmd.snapshot = parameters.snapshot -- << exact snapshot (if previously captured)
	return cmd
end

--================================================================================
-- Execute / Undo
--================================================================================
function BuildRoadCommand:execute()
	------------------------------------------------------------------
	-- 1) FIRST‑TIME BUILD
	------------------------------------------------------------------
	if not self.roadId then
		local ok, zoneIdOrErr = ZoneManager.buildRoad(self.player, self.startCoord, self.endCoord, self.mode)
		if not ok then
			error("Failed to build road – ".. tostring(zoneIdOrErr))
		end

		-- Identify & cache the zone
		self.roadId = zoneIdOrErr
		local zoneData = ZoneTracker.getZoneById(self.player, self.roadId)
		if not zoneData then
			error("Road created but not found in ZoneTracker.")
		end
		self.gridList = zoneData.gridList

		-- Charge once
		self.cost = EconomyService.getCost(self.mode, #self.gridList)
		if not EconomyService.chargePlayer(self.player, self.cost) then
			error("Insufficient funds. Required: ".. self.cost)
		end

		-- Opportunistic snapshot fetch (if generator already captured one)
		if typeof(RoadGeneratorModule.getSnapshot) == "function" then
			self.snapshot = RoadGeneratorModule.getSnapshot(self.player, self.roadId) or self.snapshot
		end

		notifyZoneCreatedEvt:FireClient(self.player, self.roadId, self.gridList)
		return
	end

	------------------------------------------------------------------
	-- 2) REDO (procedural by default; exact when snapshot present)
	------------------------------------------------------------------
	local ok, zoneIdOrErr = ZoneManager.buildRoad(self.player, self.startCoord, self.endCoord, self.mode)
	if not ok then
		warn("[BuildRoadCommand] redo failed – ".. tostring(zoneIdOrErr))
		return
	end

	self.roadId = zoneIdOrErr
	local zoneData = ZoneTracker.getZoneById(self.player, self.roadId)
	if not zoneData then
		warn("[BuildRoadCommand] redo: ZoneTracker entry missing.") ; return
	end

	-- Exact replay path (if we already have a snapshot)
	if self.snapshot and self.snapshot.segments
		and typeof(RoadGeneratorModule.recreateZoneExact) == "function"
	then
		-- (a) sync ZoneTracker grid list to snapshot tiles
		local snapGrid = {}
		for _, seg in ipairs(self.snapshot.segments) do
			snapGrid[#snapGrid+1] = { x = seg.gridX, z = seg.gridZ }
		end
		zoneData.gridList = snapGrid

		-- (b) wipe any procedurals and rebuild exactly
		if typeof(RoadGeneratorModule.removeRoad) == "function" then
			RoadGeneratorModule.removeRoad(self.player, self.roadId)
		end
		RoadGeneratorModule.recreateZoneExact(self.player, self.roadId, self.mode, self.snapshot)
	end

	-- Re‑charge only once per redo cycle
	if not self.wasCharged and self.cost and self.cost > 0 then
		EconomyService.chargePlayer(self.player, self.cost)
		self.wasCharged = true
	end
end

function BuildRoadCommand:undo()
	if self.roadId then
		ZoneManager.removeRoad(self.player, self.roadId)
		-- Refund
		if self.cost and self.cost > 0 then
			EconomyService.adjustBalance(self.player, self.cost)
		end
	else
		warn("[BuildRoadCommand] No roadId to undo.")
	end
end

--================================================================================
-- Helpers (ADD-ONLY)
--================================================================================

--- Capture an exact snapshot of the zone **now** (segments + decorations/ad choices).
--- Call this once population has finished (e.g., from ZonePopulated).
function BuildRoadCommand:captureSnapshotNow()
	if not self.roadId then
		warn("[BuildRoadCommand] captureSnapshotNow: roadId is nil (build not created yet).")
		return
	end
	if typeof(RoadGeneratorModule.captureRoadZoneSnapshot) ~= "function" then
		warn("[BuildRoadCommand] captureSnapshotNow: RoadGeneratorModule.captureRoadZoneSnapshot is missing.")
		return
	end
	local snap = RoadGeneratorModule.captureRoadZoneSnapshot(self.player, self.roadId)
	if snap and typeof(RoadGeneratorModule.saveSnapshot) == "function" then
		RoadGeneratorModule.saveSnapshot(self.player, self.roadId, snap)
	end
	self.snapshot = snap
end

--- Explicit exact‑replay redo that bypasses the procedural decorations randomness.
--- If no snapshot is available, it falls back to normal execute().
function BuildRoadCommand:redoExact()
	if not (self.snapshot and self.snapshot.segments) then
		-- fall back to your existing redo logic
		return self:execute()
	end

	-- 1) create the zone through the normal manager (keeps economy/trackers consistent)
	local ok, zoneIdOrErr = ZoneManager.buildRoad(self.player, self.startCoord, self.endCoord, self.mode)
	if not ok then
		warn("[BuildRoadCommand] redoExact build failed: ".. tostring(zoneIdOrErr))
		return
	end
	self.roadId = zoneIdOrErr

	-- 2) synchronise tracker to snapshot tile set
	local zoneData = ZoneTracker.getZoneById(self.player, self.roadId)
	if not zoneData then
		warn("[BuildRoadCommand] redoExact: ZoneTracker entry missing.") ; return
	end
	local snapGrid = {}
	for _, seg in ipairs(self.snapshot.segments) do
		snapGrid[#snapGrid+1] = { x = seg.gridX, z = seg.gridZ }
	end
	zoneData.gridList = snapGrid

	-- 3) replace procedurals with exact snapshot (segments + decorations)
	if typeof(RoadGeneratorModule.removeRoad) == "function" then
		RoadGeneratorModule.removeRoad(self.player, self.roadId)
	end
	if typeof(RoadGeneratorModule.recreateZoneExact) == "function" then
		RoadGeneratorModule.recreateZoneExact(self.player, self.roadId, self.mode, self.snapshot)
	end

	-- 4) charge once per redo cycle
	if not self.wasCharged and self.cost and self.cost > 0 then
		EconomyService.chargePlayer(self.player, self.cost)
		self.wasCharged = true
	end
end

return BuildRoadCommand
