-- BuildZoneCommand.lua

local BuildZoneCommand = {}
BuildZoneCommand.__index = BuildZoneCommand

-- Services & References
local S3 = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = S3:WaitForChild("Build")
local DST = Build:WaitForChild("Districts")
local Zones = Build:WaitForChild("Zones")
local ZoneMgr = Zones:WaitForChild("ZoneManager")
local ZoneManager = require(ZoneMgr:WaitForChild("ZoneManager"))
local ZoneTrackerModule = require(ZoneMgr:WaitForChild("ZoneTracker"))
local ZoneValidationModule = require(ZoneMgr:WaitForChild("ZoneValidation"))
local RoadTypes = require(ZoneMgr:WaitForChild("RoadTypes"))
local EconomyService = require(ZoneMgr:WaitForChild("EconomyService"))
local ZoneDisplayModule = require(ZoneMgr:WaitForChild("ZoneDisplay"))
local CC = Zones:WaitForChild("CoreConcepts")
local Districts = CC:WaitForChild("Districts")
local Stats = DST:WaitForChild("Stats")

local PlayerDataInterfaceService = require(game.ServerScriptService.Services.PlayerDataInterfaceService)

-- XP Integration
local XPManager = require(Stats:WaitForChild("XPManager"))
local Balancing = ReplicatedStorage:WaitForChild("Balancing")
local Balance = require(Balancing:WaitForChild("BalanceEconomy"))
local XP_REFUND_WINDOW = 60 -- seconds
local COIN_REFUND_WINDOW = 60

local BindableEvents = ReplicatedStorage:WaitForChild("Events"):WaitForChild("BindableEvents")
local RemoteEvents = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents")

local zoneCreatedEvent       = BindableEvents:WaitForChild("ZoneCreated")
local zoneRemovedEvent       = BindableEvents:WaitForChild("ZoneRemoved")
local zonePopulatedEvent     = BindableEvents:WaitForChild("ZonePopulated")
local buildingsPlacedEvent   = BindableEvents:WaitForChild("BuildingsPlaced")
local notifyZoneCreatedEvent = RemoteEvents:WaitForChild("NotifyZoneCreated")

local VERBOSE_LOG = false
local function log(...)
	if VERBOSE_LOG then print(...) end
end

local BldGen                  = Districts:WaitForChild("Building Gen")
local BuildingGeneratorModule = require(BldGen:WaitForChild("BuildingGenerator"))
local LayerManagerModule      = require(S3.Build.LayerManager)

-- Grid Utilities
local Scripts   = ReplicatedStorage:WaitForChild("Scripts")
local GridConf  = Scripts:WaitForChild("Grid")
local GridUtils = require(GridConf:WaitForChild("GridUtil"))

-- Debug flag
local DEBUG = true
local function debugPrint(...)
	if DEBUG then
		log("[BuildZoneCommand]", ...)
	end
end

-- Configuration Parameters
local BASE_GRACE_PERIOD = 30     -- Base grace period in seconds
local TIME_PER_CELL     = 0.1    -- Additional grace time per grid cell
local OVERALL_TIMEOUT   = 300    -- Overall timeout in seconds (5 minutes)

-- Building Generation Parameters
local BUILDING_INTERVAL = 0.25   -- seconds between building stages
local NUMBER_OF_STAGES  = 3      -- Stage1, Stage2, Stage3

-- Helper: Calculate grace period
local function calculateGracePeriod(gridList)
	return BASE_GRACE_PERIOD
		+ (BUILDING_INTERVAL * NUMBER_OF_STAGES)
		+ (#gridList * TIME_PER_CELL)
end

-----------------------------------------------------------------------
-- Constructor
-----------------------------------------------------------------------
function BuildZoneCommand.new(player, startCoord, endCoord, mode, rotation)
	local self = setmetatable({}, BuildZoneCommand)
	self.player        = player
	self.startCoord    = startCoord
	self.endCoord      = endCoord
	self.mode          = mode
	self.rotation      = rotation or 0
	self.createdZones  = {}
	self.cost          = 0
	self.wasCharged    = false
	self.skipQueue     = true

	-- [NEW] Track if the command was canceled (undone) mid‐population
	self.canceled      = false

	return self
end

-- Zone from save
function BuildZoneCommand.fromExistingZone(player, zoneId, mode, gridList, buildings)
	-- We don’t know the original start / end clicks, so use the first & last tile.
	local first = gridList[1]
	local last  = gridList[#gridList]

	local cmd = BuildZoneCommand.new(
		player,
		Vector3.new(first.x, 0, first.z),
		Vector3.new(last .x, 0, last .z),
		mode,
		0                    -- rotation unknown / N/A
	)

	-- Pretend execute() has already run once
	cmd.createdZones = { {
		zoneId    = zoneId,
		mode      = mode,
		gridList  = gridList,
		buildings = buildings or {},
	} }
	cmd.wasCharged   = true        -- don’t try to bill on redo
	cmd.cost         = 0           --   "
	return cmd
end

-----------------------------------------------------------------------
-- Data Serialization
-----------------------------------------------------------------------
function BuildZoneCommand:toData()
	local serializedZones = {}
	for _, zdata in ipairs(self.createdZones) do
		table.insert(serializedZones, {
			zoneId    = zdata.zoneId,
			mode      = zdata.mode,
			gridList  = zdata.gridList,
			buildings = zdata.buildings,
		})
	end

	return {
		CommandType = "BuildZoneCommand",
		Parameters  = {
			startCoord   = { x = self.startCoord.x, z = self.startCoord.z },
			endCoord     = { x = self.endCoord.x,   z = self.endCoord.z   },
			mode         = self.mode,
			createdZones = serializedZones,
		},
		Timestamp = os.time()
	}
end

function BuildZoneCommand.fromData(player, parameters)
	local command = BuildZoneCommand.new(
		player,
		parameters.startCoord,
		parameters.endCoord,
		parameters.mode
	)
	if parameters.createdZones then
		command.createdZones = parameters.createdZones
	end
	return command
end

-----------------------------------------------------------------------
-- Execute
-----------------------------------------------------------------------
function BuildZoneCommand:execute()
	debugPrint("Executing BuildZoneCommand for player:", self.player.Name,
		"Mode:", self.mode,
		"Rotation:", self.rotation)

	-------------------------------------------------------------------
	-- REDO path: if we already have createdZones, re-apply them
	-------------------------------------------------------------------
	if #self.createdZones > 0 then
		for _, zdata in ipairs(self.createdZones) do
			local success = ZoneManager.onAddZone(
				self.player,
				zdata.zoneId,
				zdata.mode,
				zdata.gridList
			)
			if not success then
				error("BuildZoneCommand: Failed to re-add zone "..zdata.zoneId.." during redo.")
			end

			-- Immediately fire ZoneCreated so it’s recognized (XPManager listens)
			zoneCreatedEvent:Fire(
				self.player,
				zdata.zoneId,
				zdata.mode,
				zdata.gridList,
				zdata.buildings,
				self.rotation
			)
			debugPrint("Redo: Fired ZoneCreated with predefinedBuildings for:", zdata.zoneId)
		end

		-- Charge only once on redo if not already charged
		if not self.wasCharged and self.cost and self.cost > 0 then
			if not EconomyService.chargePlayer(self.player, self.cost) then
				error("Insufficient funds on redo. Required: "..self.cost)
			end
			self.wasCharged = true
			debugPrint("Recharged player on redo for cost:", self.cost)
		end
		return
	end

	-------------------------------------------------------------------
	-- FIRST EXECUTION path
	-------------------------------------------------------------------

	-- 1) Compute grid selection (no money yet)
	local gridSelection = {
		start  = { x = self.startCoord.x, z = self.startCoord.z },
		finish = { x = self.endCoord.x,   z = self.endCoord.z   }
	}
	local newGridList = GridUtils.getGridList(gridSelection.start, gridSelection.finish)
	debugPrint("newGridList computed. Number of cells:", #newGridList)

	-- 2) VALIDATE FIRST — no side-effects if invalid
	local isValid, message, validComponents = ZoneValidationModule.validateZone(
		self.player,
		self.mode,
		newGridList
	)
	debugPrint("Validation:", isValid, message, validComponents and #validComponents or 0)
	validComponents = validComponents or { newGridList }

	if not isValid then
		-- Nothing has been charged/decremented yet, so we can just abort.
		error("BuildZoneCommand: Validation failed - "..tostring(message))
	end

	-- 3) Compute cost now that validation passed
	local cost = EconomyService.getCost(self.mode, #newGridList)

	-- Robux exclusive handling: don’t decrement yet; only after first successful create
	local pendingExclusiveDecrement = false
	if cost == "ROBUX" then
		local owned = PlayerDataInterfaceService.GetExclusiveLocationAmount(self.player, self.mode)
		if (owned or 0) <= 0 then
			debugPrint(("Build rejected: no '%s' exclusive available."):format(self.mode))
			return
		end
		cost = 0
		pendingExclusiveDecrement = true
	end

	-- 4) CHARGE COINS now (post-validation, pre-create). Store for undo-window refunds.
	self.cost = cost
	if cost > 0 then
		if not EconomyService.chargePlayer(self.player, cost) then
			error("Insufficient funds. Required: "..cost
				..", Available: "..EconomyService.getBalance(self.player))
		end
		self.wasCharged = true
		debugPrint(string.format("Player charged %d for %d grid cells (%s)", cost, #newGridList, self.mode))
	else
		debugPrint(string.format("No coin charge for %s (cost %d) — proceeding", self.mode, cost))
	end

	-- 5) Prepare zone creation bookkeeping
	local userId = self.player.UserId
	ZoneManager.playerZoneCounters[userId] = ZoneManager.playerZoneCounters[userId] or 0

	local zonesToCapture = {}
	local createdAny = false
	local exclusiveConsumed = false

	-- Listen for population/build data (unchanged)
	local eventConnection
	local buildingsPlacedConnection

	eventConnection = zonePopulatedEvent.Event:Connect(function(playerFired, pZoneId, buildingsData)
		if self.canceled then return end
		if playerFired == self.player then
			for _, zdata in ipairs(zonesToCapture) do
				if zdata.zoneId == pZoneId and not zdata.buildingDataCaptured and not zdata.failed then
					zdata.buildings = buildingsData
					zdata.buildingDataCaptured = true
					zdata.lastEventTime = tick()
					debugPrint("Captured buildings data for zone:", pZoneId)
					break
				end
			end
		end
	end)

	buildingsPlacedConnection = buildingsPlacedEvent.Event:Connect(function(playerFired, zoneIdFired, count)
		if self.canceled then return end
		if playerFired == self.player then
			for _, zdata in ipairs(zonesToCapture) do
				if zdata.zoneId == zoneIdFired and not zdata.failed then
					zdata.lastEventTime = tick()
					debugPrint(string.format("Reset grace period for Zone '%s' after %d buildings placed.", zoneIdFired, count))
					break
				end
			end
		end
	end)

	-- Helper: per-zone create
	local function handleZoneCreation(zoneId, mode, gridList, predefinedBuildings)
		debugPrint("Handling zone creation for zoneId:", zoneId)

		gridList = (type(gridList) == "table") and gridList or {}

		-- Fire creation (XPManager awards once here)
		zoneCreatedEvent:Fire(
			self.player,
			zoneId,
			mode,
			gridList,
			predefinedBuildings,
			self.rotation
		)
		debugPrint("Fired ZoneCreated. zoneId:", zoneId)

		-- Mark that at least one zone was created
		if not createdAny then
			createdAny = true
			-- If this was a Robux-exclusive placement, consume one now (exactly once)
			if pendingExclusiveDecrement then
				PlayerDataInterfaceService.IncrementExclusiveLocation(self.player, self.mode, -1)
				pendingExclusiveDecrement = false
				exclusiveConsumed = true
				debugPrint(string.format("Consumed Robux-exclusive '%s' (decremented by 1).", self.mode))
			end
		end

		-- Building-data watchdog
		local gracePeriod = calculateGracePeriod(gridList)
		table.insert(zonesToCapture, {
			zoneId               = zoneId,
			mode                 = mode,
			gridList             = gridList,
			buildings            = {},
			buildingDataCaptured = false,
			lastEventTime        = tick(),
			gracePeriod          = gracePeriod,
			failed               = false,
		})

		-- Record for undo/redo & refund-window timing
		table.insert(self.createdZones, {
			zoneId    = zoneId,
			mode      = mode,
			gridList  = gridList,
			buildings = {},
			createdAt = os.time(),
		})
	end

	-------------------------------------------------------------------
	-- 6) Create zones (merge / split / standard)
	-------------------------------------------------------------------
	local ok, err = pcall(function()
		if message == "Zones will be merged." then
			ZoneManager.playerZoneCounters[userId] += 1
			local zoneId = "Zone_"..userId.."_"..ZoneManager.playerZoneCounters[userId]

			local mergedZone = ZoneValidationModule.handleMerging(
				self.player,
				self.mode,
				zoneId,
				newGridList,
				validComponents
			)
			if not mergedZone then
				error("BuildZoneCommand: Zone merging failed.")
			end

			handleZoneCreation(mergedZone.zoneId, mergedZone.mode, mergedZone.gridList)

		elseif message == "Zone split due to road overlap." then
			for i, splitGrid in ipairs(validComponents) do
				ZoneManager.playerZoneCounters[userId] += 1
				local zoneId = "Zone_"..userId.."_"..ZoneManager.playerZoneCounters[userId]
				assert(ZoneTrackerModule.addZone(self.player, zoneId, self.mode, splitGrid),
					"BuildZoneCommand: Failed to add split zone "..zoneId)
				handleZoneCreation(zoneId, self.mode, splitGrid)
			end

		else
			-- Standard single zone or multiple components
			for _, comp in ipairs(validComponents) do
				ZoneManager.playerZoneCounters[userId] += 1
				local zoneId = "Zone_"..userId.."_"..ZoneManager.playerZoneCounters[userId]
				assert(ZoneTrackerModule.addZone(self.player, zoneId, self.mode, comp),
					"BuildZoneCommand: Failed to add zone "..zoneId)
				handleZoneCreation(zoneId, self.mode, comp)
			end
		end
	end)

	-- If creation errored and nothing was created, roll back money (and exclusives if any)
	if not ok then
		warn("[BuildZoneCommand] Creation error:", err)
		if not createdAny then
			-- Refund coins immediately since we charged post-validation
			if self.cost and self.cost > 0 then
				EconomyService.adjustBalance(self.player, self.cost)
				debugPrint(string.format("[BuildZoneCommand] Refunded %d due to create failure before any zone was created", self.cost))
			end
			-- If Robux exclusive was pending, we never decremented (pendingExclusiveDecrement==true), so nothing to undo.
		end
		error(err)
	end

	-------------------------------------------------------------------
	-- 7) Wait for building-data or timeout
	-------------------------------------------------------------------
	local startTime = tick()
	while true do
		if self.canceled then
			debugPrint("BuildZoneCommand: Detected cancellation; aborting population wait.")
			break
		end

		local allDone = true
		for _, zdata in ipairs(zonesToCapture) do
			if not zdata.buildingDataCaptured and not zdata.failed then
				local elapsed = tick() - zdata.lastEventTime
				if elapsed > zdata.gracePeriod then
					zdata.failed = true
					warn("BuildZoneCommand: Grace period passed waiting for building data in zone:", zdata.zoneId)
				else
					allDone = false
				end
			end
		end

		if allDone or (tick() - startTime) > OVERALL_TIMEOUT then
			break
		end

		task.wait(0.5)
	end

	-- Disconnect event listeners
	if eventConnection then eventConnection:Disconnect() end
	if buildingsPlacedConnection then buildingsPlacedConnection:Disconnect() end

	-- If canceled, skip final notifications
	if self.canceled then
		debugPrint("BuildZoneCommand: Execution ended early due to cancellation.")
		return
	end

	-------------------------------------------------------------------
	-- 8) Notify client of fully-populated zones
	-------------------------------------------------------------------
	for _, zdata in ipairs(zonesToCapture) do
		if zdata.buildingDataCaptured then
			for _, entry in ipairs(self.createdZones) do
				if entry.zoneId == zdata.zoneId then
					entry.buildings = zdata.buildings
					break
				end
			end

			notifyZoneCreatedEvent:FireClient(self.player, zdata.zoneId, zdata.buildings)
			debugPrint("Notified client about populated zone:", zdata.zoneId)
		else
			warn("BuildZoneCommand: No building data for zone:", zdata.zoneId)
		end
	end

log("BuildZoneCommand: Execution complete for player:", self.player.Name)
end

-----------------------------------------------------------------------
-- Undo
-----------------------------------------------------------------------
function BuildZoneCommand:undo()
	debugPrint("[UNDO START] Undoing BuildZoneCommand for player:", self.player.Name)

	-- Stop any in-flight population logic in execute()
	self.canceled = true
	debugPrint("[UNDO] self.canceled set to true")

	local userId = self.player.UserId
	debugPrint("[UNDO] Number of createdZones:", #self.createdZones)

	-- Track how many Robux-exclusive placements we actually removed (usually 1)
	local robuxExclusiveReturnCount = 0

	for idx, zdata in ipairs(self.createdZones) do
		debugPrint(string.format("[UNDO] %d) Checking zoneId = %s, mode = %s", idx, zdata.zoneId, tostring(zdata.mode)))

		-- Check if the zone is still present
		local zoneData = ZoneTrackerModule.getZoneById(self.player, zdata.zoneId)
		if zoneData then
			debugPrint(string.format("[UNDO] zoneId '%s' exists in ZoneTracker, attempting removal...", zdata.zoneId))

			-- Ensure we aren't mid-population
			ZoneTrackerModule.setZonePopulating(self.player, zdata.zoneId, false)

			-- Remove the zone (server state)
			local ok = ZoneManager.onRemoveZone(self.player, zdata.zoneId)
			debugPrint(string.format("[UNDO] onRemoveZone returned %s for zoneId '%s'", tostring(ok), zdata.zoneId))

			if ok then
				debugPrint("[UNDO] Successfully removed zone:", zdata.zoneId)

				-- Fire ZoneRemoved so XPManager can auto-undo XP if within its window
				if zoneRemovedEvent then
					zoneRemovedEvent:Fire(self.player, zdata.zoneId, zdata.mode, zdata.gridList)
				else
					-- Fallback resolve (defensive, in case the upvalue isn't in scope)
					local BE = game:GetService("ReplicatedStorage"):WaitForChild("Events"):WaitForChild("BindableEvents")
					BE:WaitForChild("ZoneRemoved"):Fire(self.player, zdata.zoneId)
				end

				-- Remove any server-side visuals for the zone
				ZoneDisplayModule.removeZonePart(self.player, zdata.zoneId)
				debugPrint("[UNDO] removeZonePart called for:", zdata.zoneId)

				-- Clean up occupant stacks for this zone footprint
				debugPrint("[UNDO] Cleaning occupant stack for zone:", zdata.zoneId)
				ZoneTrackerModule.forceClearZoneFootprint(self.player, zdata.zoneId, zdata.gridList)
				debugPrint("[UNDO] forceClearZoneFootprint called for:", zdata.zoneId)
				
				BuildingGeneratorModule.removeRefillPlacementsForOverlay(self.player, zdata.zoneId)
				
				-- Restore nature/building layers if they were culled/modified
				debugPrint("[UNDO] Restoring nature parts for zone:", zdata.zoneId)
				LayerManagerModule.restoreRemovedObjects(self.player, zdata.zoneId, "NatureZones", "NatureZones")
				LayerManagerModule.restoreRemovedObjects(self.player, zdata.zoneId, "Buildings",   "Buildings")

				-- Count Robux-exclusive returns for this zone (always return on delete/undo)
				if EconomyService.isRobuxExclusiveBuilding(zdata.mode or self.mode) then
					robuxExclusiveReturnCount += 1
				end
			else
				warn("[UNDO] BuildZoneCommand: Failed to remove zone on undo:", zdata.zoneId)
			end
		else
			debugPrint("[UNDO] zoneId does NOT exist in ZoneTracker:", zdata.zoneId, "Skipping removal.")
		end
	end

	-- Return Robux-exclusive inventory (ALWAYS, no time window), scaled to zones removed
	if robuxExclusiveReturnCount > 0 then
		local modeForReturn = self.mode -- all zdata.mode should match; fallback to command mode
		PlayerDataInterfaceService.IncrementExclusiveLocation(self.player, modeForReturn, robuxExclusiveReturnCount)
		debugPrint(string.format("[UNDO] Returned Robux-exclusive '%s' x%d to %s",
			tostring(modeForReturn), robuxExclusiveReturnCount, self.player.Name))
	end

	-- Windowed coin refund (aggregate for the command)
	-- Use the youngest createdAt among the zones built by this command
	local youngest = 0
	for _, z in ipairs(self.createdZones) do
		if z.createdAt and z.createdAt > youngest then youngest = z.createdAt end
	end
	local age = os.time() - (youngest ~= 0 and youngest or os.time())

	if self.cost and self.cost > 0 and age <= COIN_REFUND_WINDOW then
		debugPrint(string.format("[UNDO] Refunding cost: %d to %s (age=%ds ≤ %ds)",
			self.cost, self.player.Name, age, COIN_REFUND_WINDOW))
		EconomyService.adjustBalance(self.player, self.cost)
	else
		debugPrint(string.format("[UNDO] No coin refund (cost=%s, age=%ds, window=%ds)",
			tostring(self.cost), age, COIN_REFUND_WINDOW))
	end

	debugPrint("[UNDO COMPLETE] Done undoing BuildZoneCommand for player:", self.player.Name)
end

return BuildZoneCommand
