local ZoneTracker       = require(game.ServerScriptService.Build.Zones.ZoneManager.ZoneTracker)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- === Debug flag & helper ===
local DEBUG = false
local function dprint(...)
	if DEBUG then
		print(...)
	end
end

-- === Events / BE ===
local Events         = ReplicatedStorage:WaitForChild("Events")
local BindableEvents = Events:WaitForChild("BindableEvents")
local RE = Events.RemoteEvents

-- Utilities 
local function ensureBindableEvent(container: Instance, name: string): BindableEvent
	local ev = container:FindFirstChild(name)
	if ev and ev:IsA("BindableEvent") then
		return ev
	end
	ev = Instance.new("BindableEvent")
	ev.Name = name
	ev.Parent = container
	return ev
end

-- Unlock events (created if missing) 
local FireSupportUnlocked   = ensureBindableEvent(BindableEvents, "FireSupportUnlocked")
local PoliceSupportUnlocked = ensureBindableEvent(BindableEvents, "PoliceSupportUnlocked")
local HealthSupportUnlocked = ensureBindableEvent(BindableEvents, "HealthSupportUnlocked")
local TrashSupportUnlocked  = ensureBindableEvent(BindableEvents, "TrashSupportUnlocked")
local BusSupportUnlocked    = ensureBindableEvent(BindableEvents, "BusSupportUnlocked")
local AirSupportUnlocked    = ensureBindableEvent(BindableEvents, "AirSupportUnlocked")

-- External interaction handlers 
local UniqueZoneInteractions = script:WaitForChild("UniqueZoneInteractions")
local FireHandler    = require(UniqueZoneInteractions:WaitForChild("Fire"))
local PoliceHandler  = require(UniqueZoneInteractions:WaitForChild("Police"))
local HealthHandler  = require(UniqueZoneInteractions:WaitForChild("Health"))
local TrashHandler   = require(UniqueZoneInteractions:WaitForChild("Trash"))
local BusHandler     = require(UniqueZoneInteractions:WaitForChild("Bus"))
local AirportHandler = require(UniqueZoneInteractions:WaitForChild("Airport"))

-- Unlock events (created if missing) 
-- NEW: Revocation events for Bus/Air
local BusSupportRevoked = ensureBindableEvent(BindableEvents, "BusSupportRevoked")
local AirSupportRevoked = ensureBindableEvent(BindableEvents, "AirSupportRevoked")
local RE_BusSupportStatus = RE.BusSupportStatus
local RE_AirSupportStatus = RE.AirSupportStatus
local RE_MetroSupportStatus = RE.MetroSupportStatus

-- Per-player unlock caches (prevents double-firing) 
local unlockedCache = {
	Fire   = {}, -- remains unlock-only
	Police = {},
	Health = {},
	Trash  = {},
	Bus    = {}, -- boolean flag per UserId when unlocked
	Air    = {}, -- boolean flag per UserId when unlocked
	Metro = {},
}

-- Zone type groups (edit to taste) 
local GROUPS = {
	Fire   = { "FireDept", "FirePrecinct", "FireStation" },
	Police = { "PoliceDept", "PolicePrecinct", "PoliceStation" },
	Health = { "SmallClinic", "LocalHospital", "CityHospital", "MajorHospital" },
	Trash  = { "Industrial", "IndusDense" },
	Bus    = { "BusDepot" },
	Air    = { "Airport" },
	Metro = { "MetroEntrance" },
}

local UniqueZones = {}
UniqueZones.__index = UniqueZones 

-- Returns true if player owns at least one zone whose type is in list 
local function anyTypeOwned(player, typesList: {string})
	local counts = ZoneTracker.getZoneTypeCounts(player)
	for _, t in ipairs(typesList) do
		if counts[t] and counts[t] > 0 then
			return true
		end
	end
	return false
end

local function unlockSupportOnce(player, cacheKey: string, label: string, event: BindableEvent?, handler)
	local hasAny = anyTypeOwned(player, GROUPS[cacheKey])
	dprint(("Has %s Support: %s"):format(label, hasAny and "Yes" or "No"))
	if hasAny and not unlockedCache[cacheKey][player.UserId] then
		unlockedCache[cacheKey][player.UserId] = true
		if event then event:Fire(player) end
		dprint(string.format("[UniqueZones] Fired %sSupportUnlocked for %s", label, player.Name))
		if handler and handler.onSupportUnlocked then
			handler.onSupportUnlocked(player)
		end
	end
	return hasAny
end

-- Internal: reevaluate with unlock + revoke (Bus/Air only) 
local function reevaluateSupport(player, supportKey: "Bus" | "Air" | "Metro")
	local group = GROUPS[supportKey]
	local hasAny = anyTypeOwned(player, group)
	local cache  = unlockedCache[supportKey]
	local uid    = player.UserId

	if supportKey == "Bus" then
		if hasAny and not cache[uid] then
			cache[uid] = true
			BusSupportUnlocked:Fire(player)
			dprint(("[UniqueZones] Fired BusSupportUnlocked for %s"):format(player.Name))
			if BusHandler and BusHandler.onSupportUnlocked then
				BusHandler.onSupportUnlocked(player)
			end
			if RE_BusSupportStatus then RE_BusSupportStatus:FireClient(player, true) end
		elseif (not hasAny) and cache[uid] then
			cache[uid] = nil
			BusSupportRevoked:Fire(player)
			dprint(("[UniqueZones] Fired BusSupportRevoked for %s"):format(player.Name))
			if BusHandler and BusHandler.onSupportRevoked then
				BusHandler.onSupportRevoked(player)
			end
			if RE_BusSupportStatus then RE_BusSupportStatus:FireClient(player, false) end
		end

	elseif supportKey == "Air" then
		if hasAny and not cache[uid] then
			cache[uid] = true
			AirSupportUnlocked:Fire(player)
			dprint(("[UniqueZones] Fired AirSupportUnlocked for %s"):format(player.Name))
			if AirportHandler and AirportHandler.onSupportUnlocked then
				AirportHandler.onSupportUnlocked(player)
			end
			if RE_AirSupportStatus then RE_AirSupportStatus:FireClient(player, true) end
		elseif (not hasAny) and cache[uid] then
			cache[uid] = nil
			AirSupportRevoked:Fire(player)
			dprint(("[UniqueZones] Fired AirSupportRevoked for %s"):format(player.Name))
			if AirportHandler and AirportHandler.onSupportRevoked then
				AirportHandler.onSupportRevoked(player)
			end
			if RE_AirSupportStatus then RE_AirSupportStatus:FireClient(player, false) end
		end

	elseif supportKey == "Metro" then  -- NEW
		if hasAny and not cache[uid] then
			cache[uid] = true
			-- your MetroUnlocked BindableEvent should be fired by the specific feature code if you want;
			-- here we broadcast client status
			if RE_MetroSupportStatus then RE_MetroSupportStatus:FireClient(player, true) end
		elseif (not hasAny) and cache[uid] then
			cache[uid] = nil
			-- likewise for MetroRevoked BE if you choose; we just inform the client status here
			if RE_MetroSupportStatus then RE_MetroSupportStatus:FireClient(player, false) end
		end
	end
end

-- Print a breakdown + evaluate unlocks 
-- NOTE: Fire remains unlock-only. Bus/Air use symmetric unlock/revoke.
function UniqueZones.printZoneTypeCounts(player)
	local zoneCounts = ZoneTracker.getZoneTypeCounts(player)
	dprint(string.format("Zone Stats for %s (UserId %s):", player.Name, player.UserId))
	for zt, ct in pairs(zoneCounts) do
		dprint(string.format("  %s: %d", zt, ct))
	end

	local uniqueCount = ZoneTracker.getUniqueZoneTypeCount(player)
	dprint("Unique Zone Types:", uniqueCount)

	-- === Fire / Police / Health / Trash support (unlock-only; no revoke) ===
	unlockSupportOnce(player, "Fire", "Fire", FireSupportUnlocked, FireHandler)
	unlockSupportOnce(player, "Police", "Police", PoliceSupportUnlocked, PoliceHandler)
	unlockSupportOnce(player, "Health", "Health", HealthSupportUnlocked, HealthHandler)
	unlockSupportOnce(player, "Trash", "Trash", TrashSupportUnlocked, TrashHandler)

	-- === Bus support (unlock + revoke) ===
	dprint("Has Bus Support:", anyTypeOwned(player, GROUPS.Bus) and "Yes" or "No")
	reevaluateSupport(player, "Bus")

	-- === Air support (unlock + revoke) ===
	dprint("Has Air Support:", anyTypeOwned(player, GROUPS.Air) and "Yes" or "No")
	reevaluateSupport(player, "Air")

	dprint("Has Metro Support:", anyTypeOwned(player, GROUPS.Metro) and "Yes" or "No")
	reevaluateSupport(player, "Metro")
end

-- Optional for UI/logs 
function UniqueZones.getZoneSummaryString(player)
	local zoneCounts = ZoneTracker.getZoneTypeCounts(player)
	local lines = { string.format("Zone Summary for %s (UserId %s):", player.Name, player.UserId) }
	for zoneType, count in pairs(zoneCounts) do
		table.insert(lines, string.format("  %s: %d", zoneType, count))
	end
	local uniqueCount = ZoneTracker.getUniqueZoneTypeCount(player)
	table.insert(lines, "Unique Zone Types: " .. tostring(uniqueCount))
	return table.concat(lines, "\n")
end

-- Check if a player has all required zone types 
function UniqueZones.checkZoneMilestone(player, requiredTypes)
	if typeof(requiredTypes) ~= "table" then
		warn("[UniqueZones] checkZoneMilestone: requiredTypes must be a table")
		return false
	end
	return ZoneTracker.hasAllZoneTypes(player, requiredTypes)
end

-- Check if player owns any from the provided list 
function UniqueZones.checkIfAnyZoneMatches(player, matchingTypes)
	if typeof(matchingTypes) ~= "table" then
		warn("[UniqueZones] checkIfAnyZoneMatches: matchingTypes must be a table")
		return false
	end
	return anyTypeOwned(player, matchingTypes)
end

-- Re-evaluate on add/remove 
ZoneTracker.zoneAddedEvent.Event:Connect(function(player, zoneId, zoneData)
	dprint("[UniqueZones] Zone added – updating stats for", player.Name)
	UniqueZones.printZoneTypeCounts(player) -- Fire unlock-only; Bus/Air unlock/revoke
end)

ZoneTracker.zoneRemovedEvent.Event:Connect(function(player, zoneId, mode, gridList)
	dprint("[UniqueZones] Zone removed – updating stats for", player.Name)
	UniqueZones.printZoneTypeCounts(player) -- Fire unchanged; Bus/Air may revoke here
end)

game:GetService("Players").PlayerAdded:Connect(function(plr)
	task.defer(function()
		local counts = ZoneTracker.getZoneTypeCounts(plr)
		local hasBus = counts and (counts.BusDepot or 0) > 0
		if hasBus then unlockedCache.Bus[plr.UserId] = true end
		if RE_BusSupportStatus then RE_BusSupportStatus:FireClient(plr, hasBus) end

		local hasAir = counts and (counts.Airport or 0) > 0          -- NEW
		if hasAir then unlockedCache.Air[plr.UserId] = true end       -- NEW
		if RE_AirSupportStatus then RE_AirSupportStatus:FireClient(plr, hasAir) end  -- NEW

		local hasMetro = counts and (counts.MetroEntrance or 0) > 0
		if hasMetro then unlockedCache.Metro[plr.UserId] = true end
		if RE_MetroSupportStatus then RE_MetroSupportStatus:FireClient(plr, hasMetro) end

	end)
end)

return UniqueZones
