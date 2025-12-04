--[[
Script Order: 1
Script Name: ZoneTracker
Description: Core module that tracks zones and grid occupancy.
Dependencies: None
Dependents: ZoneValidation.lua, ZoneRequirementsCheck.lua, ZoneManager.lua, ZoneTrackerScript.lua
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RoadTypes = require(script.Parent:WaitForChild("RoadTypes"))
local S3 = game:GetService("ServerScriptService")

-- Grid Utilities
local Scripts = ReplicatedStorage:WaitForChild("Scripts")
local GridConf = Scripts:WaitForChild("Grid")
local GridUtils = require(GridConf:WaitForChild("GridUtil"))
local Balancing = ReplicatedStorage.Balancing
local Balance = require(Balancing.BalanceEconomy)
local BalanceInteractions  = require(Balancing:WaitForChild("BalanceInteractions"))
local DemandEngine = require(script.Parent:WaitForChild("DemandEngine"))

local Compressor = require(S3.Compress.Compressor)

local ZoneTrackerModule = {}
ZoneTrackerModule.__index = ZoneTrackerModule

-- Configuration
local DEBUG = false

-- Custom debug print function
local function debugPrint(...)
	if DEBUG then
		print("[ZoneTrackerModule]", ...)
	end
end

local function yieldEveryN(index: number, interval: number?)
	interval = interval or 100
	if interval > 0 and index % interval == 0 then
		task.wait()
	end
end


function ZoneTrackerModule.getNextZoneId(player, prefix)
    prefix = prefix or "Zone"
    local n = 1
    while ZoneTrackerModule.getZoneById(player, prefix .. n) do
        n += 1
    end
    return prefix .. n           -- guaranteed free
end


-- Utility Function: Validate Player
local function isValidPlayer(player)
	return player and typeof(player) == "Instance" and player:IsA("Player")
end

-- State Variables
ZoneTrackerModule.allZones = {}
ZoneTrackerModule.occupiedGrid = {}
local _announced = {}

local _tombstones = {}  -- [userId][zoneId] = os.clock()
local _demandSuppress = {} -- [userId] = depth counter for demand suppression
local _demandDirty = {}    -- [userId] = true if a publish was skipped while suppressed
local _demandCooldownAt = {} -- [userId] = last publish time
local _demandPendingTimer = {} -- [userId] = task token for delayed publish

local function _uid(p) return p and p.UserId end

local function _perfTier(player)
	-- Use '.' for the existence check; ':' requires args
	local t = player and player.GetAttribute and player:GetAttribute("PerfTier")
	if t == "mobile" then return "mobile-low" end
	if t == "desktop" then return "desktop-high" end
	if t == "desktop-high" or t == "desktop-balanced" or t == "desktop-low" or t == "mobile-low" then
		return t
	end
	return "desktop-high"
end

local DEMAND_COOLDOWN = {
	["mobile-low"]      = 0.8,
	["desktop-low"]     = 0.5,
	["desktop-balanced"] = 0.35,
	["desktop-high"]    = 0.0,
}

local function _scheduleDemand(player, delaySec)
	local uid = _uid(player)
	if not uid then return end
	if _demandPendingTimer[uid] then return end
	_demandPendingTimer[uid] = task.delay(delaySec, function()
		_demandPendingTimer[uid] = nil
		ZoneTrackerModule.publishDemand(player, { force = true })
	end)
end

local function isDemandSuppressed(player)
	local uid = _uid(player)
	return uid and (_demandSuppress[uid] or 0) > 0
end

local function markDemandDirty(player)
	local uid = _uid(player)
	if uid then
		_demandDirty[uid] = true
	end
end

local function clearDemandDirty(player)
	local uid = _uid(player)
	if uid then
		_demandDirty[uid] = nil
	end
end

local OVERLAY_SILENT_DEFAULT = {
	power = true, water = true, pipe = true,
	metro = true, metrotunnel = true, tunnel = true,
	powerlines = true, powerline = true, waterpipe = true,
	utility = true,
}

function ZoneTrackerModule.tombstoneZone(player, zoneId)
	local uid = _uid(player); if not uid or type(zoneId)~="string" then return end
	_tombstones[uid] = _tombstones[uid] or {}
	_tombstones[uid][zoneId] = os.clock()
end

function ZoneTrackerModule.isZoneTombstoned(player, zoneId)
	local uid = _uid(player); if not uid or type(zoneId)~="string" then return false end
	return _tombstones[uid] and _tombstones[uid][zoneId] ~= nil or false
end

function ZoneTrackerModule.clearTombstone(player, zoneId)
	local uid = _uid(player); if not uid or type(zoneId)~="string" then return end
	if _tombstones[uid] then _tombstones[uid][zoneId] = nil end
end

-- Suppress demand publishes (per player) while rebuilding/wiping worlds.
function ZoneTrackerModule.pushDemandSuppression(player)
	local uid = _uid(player); if not uid then return end
	_demandSuppress[uid] = (_demandSuppress[uid] or 0) + 1
end

function ZoneTrackerModule.popDemandSuppression(player, opts)
	local uid = _uid(player); if not uid then return end
	local publishIfDirty = opts and opts.publishIfDirty
	local forcePublish   = opts and opts.forcePublish
	local cur = _demandSuppress[uid] or 0
	if cur <= 1 then
		_demandSuppress[uid] = nil
		if publishIfDirty and (_demandDirty[uid] or forcePublish) then
			ZoneTrackerModule.publishDemand(player)
		else
			clearDemandDirty(player)
		end
	else
		_demandSuppress[uid] = cur - 1
	end
end

function ZoneTrackerModule.isDemandSuppressed(player)
	return isDemandSuppressed(player)
end

-- Event signals for zone addition and removal
local Events = ReplicatedStorage:WaitForChild("Events")
local BindableEvents = Events:WaitForChild("BindableEvents")

-- Create BindableEvents for ZoneAdded and ZoneRemoved if they don't exist
if not BindableEvents:FindFirstChild("ZoneAdded") then
	local zoneAddedEvent = Instance.new("BindableEvent")
	zoneAddedEvent.Name = "ZoneAdded"
	zoneAddedEvent.Parent = BindableEvents
	debugPrint("BindableEvent 'ZoneAdded' created.")
end

if not BindableEvents:FindFirstChild("ZoneRemoved") then
	local zoneRemovedEvent = Instance.new("BindableEvent")
	zoneRemovedEvent.Name = "ZoneRemoved"
	zoneRemovedEvent.Parent = BindableEvents
	debugPrint("BindableEvent 'ZoneRemoved' created.")
end

if not BindableEvents:FindFirstChild("ZoneRequirementChanged") then
	local requirementChanged = Instance.new("BindableEvent")
	requirementChanged.Name = "ZoneRequirementChanged"
	requirementChanged.Parent = BindableEvents
	debugPrint("BindableEvent 'ZoneRequirementChanged' created.")
end

local zonePopulatedBindable = BindableEvents:WaitForChild("ZonePopulated")

ZoneTrackerModule.zoneAddedEvent = BindableEvents:FindFirstChild("ZoneAdded")
ZoneTrackerModule.zoneRemovedEvent = BindableEvents:FindFirstChild("ZoneRemoved")
ZoneTrackerModule.zoneRequirementChangedEvent = BindableEvents:FindFirstChild("ZoneRequirementChanged")
ZoneTrackerModule.demandUpdatedEvent = BindableEvents:FindFirstChild("DemandUpdated")

-- Returns when the refund window should start for the given zone
local function refundClockAt(zoneData)
	if not zoneData then
		return nil
	end

	if typeof(zoneData.refundClockAt) == "number" and zoneData.refundClockAt > 0 then
		return zoneData.refundClockAt
	end

	-- If we don't have an explicit timestamp yet but the zone is already populated,
	-- fall back to creation time so legacy zones keep their original window.
	if zoneData.requirements and zoneData.requirements.Populated then
		return zoneData.createdAt
	end

	return nil
end




-- Occupant Layering Functions


-- Get the occupant stack at a given grid cell
local function getOccupantStack(occupiedGrid, x, z)
	local key = tostring(x) .. "," .. tostring(z)
	return occupiedGrid[key]
end

-- Return the top occupant at a grid cell (the last one in the stack)
local function getTopOccupant(occupiedGrid, x, z)
	local stack = getOccupantStack(occupiedGrid, x, z)
	if stack and #stack > 0 then
		return stack[#stack]
	end
	return nil
end

-- Remove a specific occupant (by type and id) from a cell's stack
local function removeOccupantFromStack(occupiedGrid, x, z, occupantType, occupantId)
	local stack = getOccupantStack(occupiedGrid, x, z)
	if not stack then return false end

	for i, occ in ipairs(stack) do
		if occ.occupantType == occupantType and occ.occupantId == occupantId then
			table.remove(stack, i)
			return true
		end
	end
	return false
end

-- Check if a cell is occupied (at least one occupant)
local function cellIsOccupied(occupiedGrid, x, z)
	local stack = getOccupantStack(occupiedGrid, x, z)
	return stack and #stack > 0
end

function ZoneTrackerModule.getZoneIdAtCoord(player, x, z)
	for zoneId, zone in pairs(ZoneTrackerModule.allZones[player.UserId] or {}) do
		for _, coord in ipairs(zone.gridList) do
			if coord.x == x and coord.z == z then
				return zoneId
			end
		end
	end
	return nil
end


function ZoneTrackerModule.setZonePopulating(player, zoneId, state)
	local zone = ZoneTrackerModule.getZoneById(player, zoneId)
	if zone then
		zone.isPopulating = state
	end
end

function ZoneTrackerModule.isZonePopulating(player, zoneId)
	local zone = ZoneTrackerModule.getZoneById(player, zoneId)
	return zone and zone.isPopulating
end

function ZoneTrackerModule.setZonePopulated(player, zoneId, state)
	local z = ZoneTrackerModule.getZoneById(player, zoneId)
	if z then
		z.requirements.Populated = state
		-- Start the refund clock the first time the zone is marked populated
		if state and not refundClockAt(z) then
			z.refundClockAt = os.time()
		end
		-- NEW: population flips change demand pressures immediately
		ZoneTrackerModule.publishDemand(player)
	end
end

function ZoneTrackerModule.isZonePopulated(player, zoneId)
	local z = ZoneTrackerModule.getZoneById(player, zoneId)
	return z and z.requirements.Populated or false
end

-- Returns the timestamp that should be used for refund-window age checks
function ZoneTrackerModule.getRefundClockAt(player, zoneId)
	return refundClockAt(ZoneTrackerModule.getZoneById(player, zoneId))
end

function ZoneTrackerModule.addZone(player, zoneId, mode, gridList, props)
	if DEBUG then
		warn(("[ZT] addZone %s (%s)  call-site:\n%s")
			:format(zoneId, tostring(player), debug.traceback("", 2)))
	end

	-- Input Validation
	if not (player and player:IsA("Player")) then
		warn("ZoneTrackerModule:addZone - Invalid player provided.")
		return false
	end
	if not (type(zoneId) == "string" and type(mode) == "string" and type(gridList) == "table") then
		warn("ZoneTrackerModule:addZone - Invalid parameters. Expected (Player, string, string, table).")
		return false
	end

	local userId = player.UserId
	ZoneTrackerModule.allZones[userId] = ZoneTrackerModule.allZones[userId] or {}

	if ZoneTrackerModule.allZones[userId][zoneId] then
		warn("ZoneTrackerModule:addZone - Zone already exists:", zoneId)
		return false
	end

	-- Build full zone record once (includes createdAt for refund/undo windows)
	local createdAt = os.time()
	if props and typeof(props.createdAt) == "number" and props.createdAt > 0 then
		createdAt = props.createdAt
	end
	local refundClock = nil
	if props and typeof(props.refundClockAt) == "number" and props.refundClockAt > 0 then
		refundClock = props.refundClockAt
	end
	if not refundClock and props and typeof(props.requirements) == "table" and props.requirements.Populated then
		refundClock = createdAt
	end
	local zoneData = {
		zoneId       = zoneId,
		player       = player,
		mode         = mode,
		gridList     = gridList,
		requirements = { Road = false, Water = false, Power = false, Populated = false },
		wealth       = {},
		createdAt    = createdAt,
		refundClockAt= refundClock,
		isPopulating = false,
	}

	-- Initialize per-tile wealth (default "Poor")
	for _, coord in ipairs(gridList) do
		if coord and typeof(coord) == "table" then
			local key = tostring(coord.x) .. "," .. tostring(coord.z)
			zoneData.wealth[key] = "Poor"
		end
	end

	-- Store
	ZoneTrackerModule.allZones[userId][zoneId] = zoneData
	ZoneTrackerModule.clearTombstone(player, zoneId)
	debugPrint(string.format("Added zone '%s' for player '%s'.", zoneId, player.Name))

	-- Mark grids occupied
	for _, coord in ipairs(gridList) do
		if coord and typeof(coord) == "table" and type(coord.x) == "number" and type(coord.z) == "number" then
			ZoneTrackerModule.markGridOccupied(player, coord.x, coord.z, "zone", zoneId, mode)
		else
			warn("ZoneTrackerModule:addZone - Invalid grid coordinates:", tostring(coord))
		end
	end

	-- Fire ZoneAdded (once per zone)
	_announced[userId] = _announced[userId] or {}
	if not _announced[userId][zoneId] then
		ZoneTrackerModule.zoneAddedEvent:Fire(player, zoneId, zoneData)
		_announced[userId][zoneId] = true
		debugPrint("ZoneAdded event fired for zoneId:", zoneId)
	else
		debugPrint("ZoneAdded event suppressed (already announced) for zoneId:", zoneId)
	end
	
	ZoneTrackerModule.publishDemand(player)

	return true
end

function ZoneTrackerModule.removeZoneById(player, zoneId)
	if not isValidPlayer(player) or type(zoneId) ~= "string" then
		warn("ZoneTrackerModule:removeZoneById - bad args")
		return false
	end

	local userId     = player.UserId
	local playerZones= ZoneTrackerModule.allZones[userId]
	if not playerZones then
		warn("ZoneTrackerModule:removeZoneById - no zones table for player:", player.Name)
		return false
	end

	local zone = playerZones[zoneId]
	if not zone then
		warn("ZoneTrackerModule:removeZoneById - zone does not exist:", zoneId)
		return false
	end

	-- Ground truth from stored data
	local mode     = zone.mode
	local gridList = zone.gridList
	ZoneTrackerModule.tombstoneZone(player, zoneId)

	-- Unmark grid occupancy safely
	local userGrid = ZoneTrackerModule.occupiedGrid[userId]
	if userGrid then
		for i, coord in ipairs(gridList) do
			if coord and typeof(coord) == "table" and type(coord.x)=="number" and type(coord.z)=="number" then
				local ok = removeOccupantFromStack(userGrid, coord.x, coord.z, "zone", zoneId)
				if ok then
					local key   = tostring(coord.x)..","..tostring(coord.z)
					local stack = userGrid[key]
					if stack and #stack == 0 then
						userGrid[key] = nil
					end
				else
					-- non-fatal: we log but still proceed to delete zone state
					debugPrint(("[ZT] removeZoneById: no matching occupant at (%d,%d) for %s")
						:format(coord.x, coord.z, zoneId))
				end
			end
			yieldEveryN(i, 250)
		end
	else
		debugPrint("[ZT] removeZoneById: no occupiedGrid yet for player; skipping unmark loop")
	end

	-- Delete zone state + announced flag
	playerZones[zoneId] = nil
	if _announced[userId] then
		_announced[userId][zoneId] = nil
	end

	-- Fire a single canonical ZoneRemoved (player, zoneId, mode, gridList)
	if ZoneTrackerModule.zoneRemovedEvent then
		ZoneTrackerModule.forceClearZoneFootprint(player, zoneId, gridList)
		ZoneTrackerModule.zoneRemovedEvent:Fire(player, zoneId, mode, gridList)
		debugPrint("[ZT] ZoneRemoved fired for:", zoneId)
	end
	
	ZoneTrackerModule.publishDemand(player)

	return true
end

-- Canonical wipe: remove every zone via removeZoneById (fires ZoneRemoved with mode+gridList)
function ZoneTrackerModule.removeAllZonesForPlayer(player)
	if not isValidPlayer(player) then return 0 end
	local list = {}
	for id, _ in pairs(ZoneTrackerModule.getAllZones(player)) do
		list[#list+1] = id
	end
	local removed = 0
	for i, id in ipairs(list) do
		if ZoneTrackerModule.removeZoneById(player, id) then
			removed += 1
		end
		yieldEveryN(i, 25)
	end
	return removed
end

function ZoneTrackerModule.removeZone(player, zoneId, _mode, _gridList)
	-- ignore _mode/_gridList; use stored truth
	return ZoneTrackerModule.removeZoneById(player, zoneId)
end

function ZoneTrackerModule.getAllZones(player)
	if not (isValidPlayer(player)) then
		warn("ZoneTrackerModule:getAllZones - Invalid player provided.")
		return {}
	end
	return ZoneTrackerModule.allZones[player.UserId] or {}
end

function ZoneTrackerModule.getZoneById(player, zoneId)
	debugPrint("getZoneById called with:", player, zoneId)
	if not (isValidPlayer(player)) then
		warn("ZoneTrackerModule:getZoneById - Invalid player provided. Player value:", player, typeof(player))
		return nil
	end
	if not (type(zoneId) == "string") then
		warn("ZoneTrackerModule:getZoneById - Invalid zoneId. Expected a string.")
		return nil
	end

	local playerZones = ZoneTrackerModule.allZones[player.UserId]
	if playerZones then
		return playerZones[zoneId]
	end
	return nil
end

function ZoneTrackerModule.getGridWealth(player, zoneId, x, z)
	local zone = ZoneTrackerModule.getZoneById(player, zoneId)
	if not zone then return nil end
	local key = tostring(x)..","..tostring(z)
	return zone.wealth[key]
end
 
-- Updates the stored WealthState for that tile
function ZoneTrackerModule.setGridWealth(player, zoneId, x, z, newState)
	local zone = ZoneTrackerModule.getZoneById(player, zoneId)
	if not zone then return end
	local key = tostring(x)..","..tostring(z)
	zone.wealth[key] = newState
end


function ZoneTrackerModule.getZoneAtGrid(player, x, z)
	if not (isValidPlayer(player)) then
		warn("ZoneTrackerModule:getZoneAtGrid - Invalid player provided.")
		return nil
	end
	if not (type(x) == "number" and type(z) == "number") then
		warn("ZoneTrackerModule:getZoneAtGrid - Invalid coordinates. Expected numbers.")
		return nil
	end

	local userId = player.UserId
	local playerOccupiedGrid = ZoneTrackerModule.occupiedGrid[userId]
	if playerOccupiedGrid then
		local topOcc = getTopOccupant(playerOccupiedGrid, x, z)
		if topOcc and topOcc.occupantType == 'zone' then
			return ZoneTrackerModule.allZones[userId][topOcc.occupantId]
		end
	end
	return nil
end

function ZoneTrackerModule.getAnyZoneAtGrid(player, x, z)
	if not (isValidPlayer(player)) then
		warn("ZoneTrackerModule:getAnyZoneAtGrid - Invalid player provided.")
		return nil
	end
	if not (type(x) == "number" and type(z) == "number") then
		warn("ZoneTrackerModule:getAnyZoneAtGrid - Invalid coordinates. Expected numbers.")
		return nil
	end

	local userId = player.UserId
	local playerOccupiedGrid = ZoneTrackerModule.occupiedGrid[userId]
	if playerOccupiedGrid then
		-- Check all occupants in this cell for a zone occupant
		local stack = getOccupantStack(playerOccupiedGrid, x, z)
		if stack then
			for _, occ in ipairs(stack) do
				if occ.occupantType == 'zone' then
					return ZoneTrackerModule.allZones[userId][occ.occupantId]
				end
			end
		end
	end
	return nil
end

function ZoneTrackerModule.isGridOccupied(player, x, z, options)
	if not (isValidPlayer(player)) then
		warn("ZoneTrackerModule:isGridOccupied - Invalid player provided.")
		return false
	end
	if type(x)~="number" or type(z)~="number" then
		warn("ZoneTrackerModule:isGridOccupied - Bad coords")
		return false
	end
	if options and typeof(options) ~= "table" then
		warn("ZoneTrackerModule:isGridOccupied - Options should be a table.")
		return false
	end
	options = options or {}

	local uid   = player.UserId
	local grid  = ZoneTrackerModule.occupiedGrid[uid]
	if not grid then return false end

	local key   = tostring(x)..","..tostring(z)
	local stack = grid[key]
	if not stack or #stack == 0 then return false end

	local changed = false

	-- Support either a single occupantType string or a table (array or set) of types
	local function _isExcludedType(occType)
		local ex = options.excludeOccupantType
		if not ex then
			return false
		end
		local t = type(ex)
		if t == "string" then
			return occType == ex
		elseif t == "table" then
			-- set-style table wins
			if ex[occType] ~= nil then
				return ex[occType] == true
			end
			-- otherwise treat as array
			for _, v in ipairs(ex) do
				if v == occType then
					return true
				end
			end
		end
		return false
	end

	-- Normalize prefix exclusions (string or array of strings)
	local function _hasExcludedPrefix(occId)
		local pref = options.excludeOccupantIdPrefix
		if not pref or type(occId) ~= "string" then
			return false
		end
		if type(pref) == "string" then
			return occId:sub(1, #pref) == pref
		elseif type(pref) == "table" then
			for _, p in ipairs(pref) do
				if type(p) == "string" and occId:sub(1, #p) == p then
					return true
				end
			end
		end
		return false
	end

	-- Scan stack top → bottom
	for i = #stack, 1, -1 do
		local occ = stack[i]
		if occ then
			-- Exclusion filters
			if _isExcludedType(occ.occupantType) then
				-- skip this occupant, but keep it in stack
			elseif options.excludeOccupantId and occ.occupantId == options.excludeOccupantId then
				-- skip
			elseif _hasExcludedPrefix(occ.occupantId) then
				-- skip occupants with the provided prefix(es)
			elseif options.excludeZoneTypes and occ.zoneType and options.excludeZoneTypes[occ.zoneType] then
				-- skip
			else
				-- If it's a zone, drop it if it no longer exists or is tombstoned
				if occ.occupantType == "zone" then
					local alive = ZoneTrackerModule.getZoneById(player, occ.occupantId) ~= nil
					local tomb  = ZoneTrackerModule.isZoneTombstoned and ZoneTrackerModule.isZoneTombstoned(player, occ.occupantId)
					if not alive then
						table.remove(stack, i)
						changed = true
					else
						-- zone exists -> treat as valid, ignore tombstone
						return true
					end
				else
					-- Non-zone occupant and not excluded = blocking
					return true
				end
			end
		end
	end

	if changed and #stack == 0 then
		grid[key] = nil
	end
	return false
end

function ZoneTrackerModule.markGridOccupied(player, x, z, occupantType, occupantId, zoneType)
	if not (isValidPlayer(player)) then
		warn("ZoneTrackerModule:markGridOccupied - Invalid player provided.")
		return
	end
	if not (type(x) == "number" and type(z) == "number" and type(occupantType) == "string" and type(occupantId) == "string") then
		warn("ZoneTrackerModule:markGridOccupied - Invalid parameters. Expected (Player, number, number, string, string, [string]).")
		return
	end

	local userId = player.UserId
	ZoneTrackerModule.occupiedGrid[userId] = ZoneTrackerModule.occupiedGrid[userId] or {}
	local key = tostring(x) .. "," .. tostring(z)

	-- If no occupant stack exists for this cell, create one
	if not ZoneTrackerModule.occupiedGrid[userId][key] then
		ZoneTrackerModule.occupiedGrid[userId][key] = {}
	end

	-- Push the new occupant onto the stack
	table.insert(ZoneTrackerModule.occupiedGrid[userId][key], {
		occupantType = occupantType,
		occupantId = occupantId,
		zoneType = zoneType
	})

	debugPrint(string.format("Grid (%d, %d) now has occupant '%s' by '%s'.", x, z, occupantType, occupantId))
end

function ZoneTrackerModule.unmarkGridOccupied(player, x, z, occupantType, occupantId, opts)
	if not (isValidPlayer(player)) then
		warn("ZoneTrackerModule:unmarkGridOccupied - Invalid player provided.")
		return
	end
	if not (type(x) == "number" and type(z) == "number" and type(occupantType) == "string" and type(occupantId) == "string") then
		warn("ZoneTrackerModule:unmarkGridOccupied - Invalid parameters. Expected (Player, number, number, string, string[, table]).")
		return
	end

	opts = opts or {}
	local occTypeLower = string.lower(occupantType)
	-- Default: overlays quiet; zones/buildings/roads loud unless opts.silent = true.
	local silentDefault = (occupantType ~= "zone" and occupantType ~= "building" and occTypeLower ~= "road")
	local silent = (opts.silent == true) or (opts.silent == nil and (OVERLAY_SILENT_DEFAULT[occTypeLower] or silentDefault))

	local userId = player.UserId
	local grid   = ZoneTrackerModule.occupiedGrid[userId]
	if not grid then
		if not silent then
			warn("ZoneTrackerModule:unmarkGridOccupied - No occupied grids found for player:", player.Name)
		end
		return
	end

	local key   = tostring(x)..","..tostring(z)
	local stack = grid[key]
	if not stack or #stack == 0 then
		-- idempotent: nothing to remove
		return
	end

	-- First try exact match.
	local removed = removeOccupantFromStack(grid, x, z, occupantType, occupantId)

	-- Helper: robust match (prefix-tolerant for zone/building)
	local function matches(occ)
		if not occ or occ.occupantType ~= occupantType then return false end
		local occId = occ.occupantId
		if type(occId) ~= "string" then return false end
		if occId == occupantId then return true end

		if occupantType == "zone" then
			-- Accept prefix match for zones.
			return occId:sub(1, #occupantId) == occupantId
		elseif occupantType == "building" then
			-- Accept either direction for buildings.
			return (occId:sub(1, #occupantId) == occupantId) or (occupantId:sub(1, #occId) == occId)
		end
		return false
	end

	-- If exact failed, sweep with tolerant matching (zones/buildings only).
	if not removed and (occupantType == "zone" or occupantType == "building") then
		for i = #stack, 1, -1 do
			if matches(stack[i]) then
				table.remove(stack, i)
				removed = true
			end
		end
	end

	if removed then
		-- prune empty cell
		if #stack == 0 then grid[key] = nil end
	else
		if not silent then
			warn(("ZoneTrackerModule:unmarkGridOccupied - No matching occupant at grid: %d %d (wanted %s/%s)")
				:format(x, z, occupantType, occupantId))
		end
	end
end


function ZoneTrackerModule.forceClearZoneFootprint(player, zoneId, gridList)
	if not isValidPlayer(player) or type(zoneId) ~= "string" or type(gridList) ~= "table" then return end

	local userId = player.UserId
	local grid   = ZoneTrackerModule.occupiedGrid[userId]
	if not grid then return end

	-- Support both current ("Zone_<uid>_<n>_<gx>_<gz>") and legacy ("building/Zone_<...>") building IDs
	local legacyBuildingPrefix = "building/" .. zoneId
	local idPrefix             = zoneId .. "_"

	for _, coord in ipairs(gridList) do
		local x, z = coord.x, coord.z
		local key  = tostring(x) .. "," .. tostring(z)
		local stack = grid[key]
		if stack then
			for i = #stack, 1, -1 do
				local occ = stack[i]
				if occ and type(occ.occupantId) == "string" then
					local id = occ.occupantId
					local kill = false

					if occ.occupantType == "zone" then
						-- exact zone or anything prefixed with it
						kill = (id == zoneId) or (id:sub(1, #zoneId) == zoneId)

					elseif occ.occupantType == "building" then
						-- current scheme: "<zoneId>_<gx>_<gz>"
						-- legacy scheme:  "building/<zoneId>..."
						if id:sub(1, #idPrefix) == idPrefix
							or id:sub(1, #legacyBuildingPrefix) == legacyBuildingPrefix then
							kill = true
						end
					end

					if kill then
						table.remove(stack, i)
					end
				end
			end
			if #stack == 0 then
				grid[key] = nil
			end
		end
	end
end


function ZoneTrackerModule.getZoneTypeAtGrid(player, x, z)
	if not (isValidPlayer(player)) then
		warn("ZoneTrackerModule:getZoneTypeAtGrid - Invalid player provided.")
		return nil
	end
	if not (type(x) == "number" and type(z) == "number") then
		warn("ZoneTrackerModule:getZoneTypeAtGrid - Invalid coordinates. Expected numbers.")
		return nil
	end

	local userId = player.UserId
	local playerOccupiedGrid = ZoneTrackerModule.occupiedGrid[userId]
	if playerOccupiedGrid then
		local topOcc = getTopOccupant(playerOccupiedGrid, x, z)
		local zoneType = topOcc and topOcc.zoneType or nil
		debugPrint(string.format("getZoneTypeAtGrid(%d, %d) = %s", x, z, tostring(zoneType)))
		return zoneType
	end
	return nil
end

function ZoneTrackerModule.getOtherZoneIdAtGrid(player, x, z, excludeZoneId)
	-- validate
	if not isValidPlayer(player) then return nil end
	if type(x) ~= "number" or type(z) ~= "number" then return nil end

	local userId   = player.UserId
	local grid     = ZoneTrackerModule.occupiedGrid[userId]
	if not grid then return nil end

	local stack = getOccupantStack(grid, x, z)
	if not stack then return nil end

	for i = #stack, 1, -1 do              -- walk from top-most → bottom
		local occ = stack[i]
		if occ.occupantType == "zone"
			and occ.occupantId ~= excludeZoneId
		then
			return occ.occupantId          -- the underlying zone we “hit”
		end
	end
	return nil
end


function ZoneTrackerModule.markZoneRequirement(player, zoneId, requirement, status)
	if not (isValidPlayer(player)) then
		warn("ZoneTrackerModule:markZoneRequirement - Invalid player provided.")
		return
	end
	if not (type(zoneId) == "string" and type(requirement) == "string" and type(status) == "boolean") then
		warn("ZoneTrackerModule:markZoneRequirement - Invalid parameters. Expected (Player, string, string, boolean).")
		return
	end

	local userId = player.UserId
	local zone = ZoneTrackerModule.allZones[userId] and ZoneTrackerModule.allZones[userId][zoneId]
	if zone and zone.requirements[requirement] ~= nil then
		if zone.requirements[requirement] ~= status then
			zone.requirements[requirement] = status
			debugPrint(string.format("Requirement '%s' for zone '%s' set to %s.", requirement, zoneId, tostring(status)))
			if ZoneTrackerModule.zoneRequirementChangedEvent then
				ZoneTrackerModule.zoneRequirementChangedEvent:Fire(player, zoneId, requirement, status)
			end
		end
		--ZoneTrackerModule.publishDemand(player)
	else
		warn(string.format("ZoneTrackerModule: Cannot set requirement '%s' for zone '%s' of player '%s'.", requirement, zoneId, player.Name))
	end
end

local function _tileKey(gx, gz)  -- keep it local to this module
	return ("%d_%d"):format(gx, gz)
end

-- save one flag on one tile
function ZoneTrackerModule.markTileRequirement(player, zoneId, gx, gz, reqName, value)
	local zone = ZoneTrackerModule.getZoneById(player, zoneId)
	if not zone then return end

	zone.tileRequirements            = zone.tileRequirements or {}
	zone.tileRequirements[_tileKey(gx,gz)] =
		zone.tileRequirements[_tileKey(gx,gz)] or { Road=false, Water=false, Power=false }

	zone.tileRequirements[_tileKey(gx,gz)][reqName] = value
end

-- read it back (optional utility)
function ZoneTrackerModule.getTileRequirement(player, zoneId, gx, gz, reqName)
	local zone = ZoneTrackerModule.getZoneById(player, zoneId)
	if not zone or not zone.tileRequirements then return nil end
	local t = zone.tileRequirements[_tileKey(gx,gz)]
	return t and t[reqName]
end

function ZoneTrackerModule.addPendingZone(zoneId, player, mode, gridList)
	if not (isValidPlayer(player)) then
		warn("ZoneTrackerModule:addPendingZone - Invalid player provided.")
		return false
	end
	if not (type(zoneId) == "string" and type(mode) == "string" and type(gridList) == "table") then
		warn("ZoneTrackerModule:addPendingZone - Invalid parameters. Expected (Player, string, string, table).")
		return false
	end

	return ZoneTrackerModule.addZone(player, zoneId, mode, gridList)
end

function ZoneTrackerModule.isGridOccupiedByOccupantType(player, x, z, occupantType)
	if not (isValidPlayer(player)) then
		warn("ZoneTrackerModule:isGridOccupiedByOccupantType - Invalid player provided.")
		return false
	end
	if not (type(x) == "number" and type(z) == "number" and type(occupantType) == "string") then
		warn("ZoneTrackerModule:isGridOccupiedByOccupantType - Invalid parameters. Expected (Player, number, number, string).")
		return false
	end

	local userId = player.UserId
	local playerOccupiedGrid = ZoneTrackerModule.occupiedGrid[userId]
	if playerOccupiedGrid then
		local stack = getOccupantStack(playerOccupiedGrid, x, z)
		if stack then
			for _, occ in ipairs(stack) do
				if occ.occupantType == occupantType then
					debugPrint(string.format("isGridOccupiedByOccupantType(%d, %d, '%s') = true", x, z, occupantType))
					return true
				end
			end
		end
	end
	debugPrint(string.format("isGridOccupiedByOccupantType(%d, %d, '%s') = false", x, z, occupantType))
	return false
end

function ZoneTrackerModule.getGridOccupantTypes(player, x, z)
	if not isValidPlayer(player) then
		warn("ZoneTrackerModule:getGridOccupantTypes - Invalid player.")
		return {}
	end

	local userId = player.UserId
	local grid = ZoneTrackerModule.occupiedGrid[userId]
	if not grid then return {} end

	local key = tostring(x) .. "," .. tostring(z)
	local stack = grid[key]
	if not stack then return {} end

	local types = {}
	for _, occ in ipairs(stack) do
		types[occ.occupantType] = true
	end

	return types
end

local function tableToString(tbl)
	local result = "{"
	local first = true
	for k, v in pairs(tbl) do
		if not first then
			result = result .. ", "
		else
			first = false
		end
		result = result .. tostring(k) .. "=" .. tostring(v)
	end
	result = result .. "}"
	return result
end

function ZoneTrackerModule.getZoneTypeCounts(player)
	if not (isValidPlayer(player)) then
		warn("ZoneTrackerModule:getZoneTypeCounts - Invalid player provided.")
		return {}
	end

	local counts = {}
	local zones = ZoneTrackerModule.getAllZones(player)
	for _, zoneData in pairs(zones) do
		local mode = zoneData.mode
		counts[mode] = (counts[mode] or 0) + 1
	end

	-- Use the helper function to print the table contents
	debugPrint("DEBUG: zoneCounts = " .. tableToString(counts) .. ", type: " .. typeof(counts))
	return counts
end

-- Returns a count of unique zone types (how many different types the player has)
function ZoneTrackerModule.getUniqueZoneTypeCount(player)
	local counts = ZoneTrackerModule.getZoneTypeCounts(player)
	local uniqueCount = 0
	for _, _ in pairs(counts) do
		uniqueCount = uniqueCount + 1
	end
	return uniqueCount
end

-- Returns true if the player has *all* of the specified zone types
function ZoneTrackerModule.hasAllZoneTypes(player, requiredTypes)
	if not isValidPlayer(player) then
		warn("ZoneTrackerModule:hasAllZoneTypes - Invalid player provided.")
		return false
	end
	if type(requiredTypes) ~= "table" then
		warn("ZoneTrackerModule:hasAllZoneTypes - requiredTypes must be a table of strings.")
		return false
	end

	local counts = ZoneTrackerModule.getZoneTypeCounts(player)
	for _, mode in ipairs(requiredTypes) do
		if not counts[mode] then
			return false
		end
	end
	return true
end

function ZoneTrackerModule.clearPlayerData(player)
	local userId = player.UserId
	ZoneTrackerModule.allZones[userId]   = nil
	ZoneTrackerModule.occupiedGrid[userId] = nil
	_announced[userId]                   = nil
	_demandSuppress[userId]              = nil
	_demandDirty[userId]                 = nil
	ZoneTrackerModule.publishDemand(player)
end

function ZoneTrackerModule.sweepStaleBuildingOccupants(player)
	if not isValidPlayer(player) then return end
	local uid  = player.UserId
	local grid = ZoneTrackerModule.occupiedGrid[uid]
	if not grid then return end

	for key, stack in pairs(grid) do
		for i = #stack, 1, -1 do
			local occ = stack[i]
			if occ and occ.occupantType == "building" and type(occ.occupantId) == "string" then
				local zid = occ.occupantId:match("^(.-)_%d+_%d+$")
				if zid and ZoneTrackerModule.getZoneById(player, zid) == nil then
					table.remove(stack, i)
				end
			end
		end
		if stack and #stack == 0 then grid[key] = nil end
	end
end

-- Demands stuff
-- count how many individual grid squares the player has for each mode
function ZoneTrackerModule.getGridCounts(player)
	if not isValidPlayer(player) then
		warn("ZoneTrackerModule:getGridCounts – invalid player")
		return {}
	end

	local counts = {}
	for _, zone in pairs(ZoneTrackerModule.getAllZones(player)) do
		local n = #zone.gridList                -- how many tiles in this zone
		counts[zone.mode] = (counts[zone.mode] or 0) + n
	end
	return counts
end

-- target share of *total* zoned tiles
local _TARGET = Balance.ZoneShareTargets
local uxpBackPressure = nil

-- NEW: full demand snapshot (base share demand + cross-pressures + dense cascade + infra strain)
function ZoneTrackerModule.getZoneDemandFull(player)
	if not isValidPlayer(player) then
		return {
			demand = {
				Residential=1, ResDense=1, Commercial=1, CommDense=1, Industrial=1, IndusDense=1
			},
			pressure = { share = {}, cascade = {}, toCommercial = 0, toIndustrial = 0, total = 0 },
			suggestAdvisor = false,
		}
	end

	local countsTiles = ZoneTrackerModule.getGridCounts(player)                 -- per-mode *tile* counts
	local demandCfg   = BalanceInteractions and BalanceInteractions.DemandConfig or nil 

	-- ✅ Pass demandCfg into the engine so designers can tune the new dense behavior
	local snap = DemandEngine.computeSnapshot(
		countsTiles,       -- countsTiles
		_TARGET,           -- targets  (Balance.ZoneShareTargets)
		demandCfg,         -- cfg (NOW passed through)
		nil,               -- unlocks (or supply your table if you gate dense unlocks)
		uxpBackPressure    -- optional back-pressure (nil if unused)
	)

	return snap
end

-- returns a table of demand values in the range 0..1
function ZoneTrackerModule.getZoneDemand(player)
	local snap = ZoneTrackerModule.getZoneDemandFull(player)
	return snap.demand
end

-- Publish current snapshot to listeners (UI / Advisor)
function ZoneTrackerModule.publishDemand(player, opts)
	local force = opts and opts.force

	if not force and isDemandSuppressed(player) then
		markDemandDirty(player)
		return
	end

	local tier = _perfTier(player)
	local cooldown = (not force) and (DEMAND_COOLDOWN[tier] or 0) or 0
	local uid = _uid(player)
	if not force and cooldown > 0 and uid then
		local now = os.clock()
		local last = _demandCooldownAt[uid] or 0
		if (now - last) < cooldown then
			markDemandDirty(player)
			_scheduleDemand(player, cooldown - (now - last) + 0.05)
			return
		end
	end

	if not ZoneTrackerModule.demandUpdatedEvent then
		clearDemandDirty(player)
		return
	end

	clearDemandDirty(player)
	local snap = ZoneTrackerModule.getZoneDemandFull(player)
	ZoneTrackerModule.demandUpdatedEvent:Fire(player, snap.demand, snap)
	if uid then _demandCooldownAt[uid] = os.clock() end

	-- Optional advisory nudge purely on high demand
	local Events   = ReplicatedStorage:WaitForChild("Events")
	local Bindings = Events:WaitForChild("BindableEvents")
	local scanEvt  = Bindings:FindFirstChild("CivicRequestsScanRequested")
	if scanEvt and snap.suggestAdvisor then
		scanEvt:Fire(player)
	end
end


function ZoneTrackerModule.hasPopulatingConflict(player, coordList)
	-- coordList is an array of {x = int, z = int}
	if not isValidPlayer(player) then
		return false, nil
	end
	for _, c in ipairs(coordList) do
		local zid = ZoneTrackerModule.getZoneIdAtCoord(player, c.x, c.z)
		if zid and ZoneTrackerModule.isZonePopulating(player, zid) then
			return true, zid
		end
	end
	return false, nil
end

function ZoneTrackerModule.DebugSave(player)
	local uid   = player.UserId
	local zones = ZoneTrackerModule.allZones[uid] or {}
	local out   = {}

	for zId, zData in pairs(zones) do
		out[#out+1] = {
			i = Compressor.ShortTag(zId),                      -- 8
			m = Compressor.ShortTag(zData.mode, 2),            -- 8
			g = Compressor.Vec2ListToString(zData.gridList),   -- 1‑5
			r = Compressor.EncodeInt(                          -- 4(!) after bit‑pack
				Compressor.PackFlags(
					zData.requirements,
					{"Road","Water","Power", "Populated"})),            -- 7
			-- add any other fields you want to test
		}
	end

	print("=== ZONE DEBUG SAVE ===")
	local compressed = Compressor.Finalise(out, true, true)  -- debug=true prints before/after sizes, table
	return compressed
end

-- Diagnostic: Load zone data (no actual game state, just print info)
function ZoneTrackerModule.DebugLoad(compressedString)
	print("=== ZONE DEBUG LOAD ===")
	local decoded = Compressor.Definalise(compressedString, true, true)  -- debug=true prints after decompression
	-- If you want to compare before/after, you can also return decoded.
	return decoded
end

--[[function ZoneTrackerModule.DebugSloadRoundTrip(player)
	local HttpService = game:GetService("HttpService")
	local Sload       = require(game.ServerScriptService.Compress.Sload)
	local Compressor  = require(game.ServerScriptService.Compress.Compressor)
	local DataSizes   = require(game.ServerScriptService.Compress.DataSizes)

	-- Make sure the flag order is consistent with schema
	DataSizes.Zone.flags.order = { "Road", "Water", "Power" }

	local uid = player.UserId
	local zones = ZoneTrackerModule.allZones[uid] or {}
	local zoneList = {}

	--  Convert live zone state to compressed schema
	for zoneId, data in pairs(zones) do
		table.insert(zoneList, {
			id     = Compressor.ShortTag(zoneId, 6),
			mode   = data.mode,                 -- string (e.g., "Residential")
			coords = data.gridList,            -- usually 2 points
			flags  = data.requirements         -- { Road = bool, Water = bool, Power = bool }
		})
	end

	--  Show structured compression stats
	print("Compressor.DebugRoundTrip:")
	local _, decompressedTable = Compressor.DebugRoundTrip(zoneList, true)

	--  Save as raw binary buffer
	print("Saving with Sload (raw binary)...")
	local buffer = Sload.Save("Zone", zoneList)

	--  Buffer size output
	print("Final buffer size:", #buffer, "bytes")
	print("First 24 bytes (Base64):", Compressor.b64encode(buffer:sub(1, 24)))

	-- Load buffer into decompressed format
	print("Loading with Sload...")
	local loaded = Sload.Load("Zone", buffer)

	-- Print decompressed rows
	print("Round-trip result:")
	for i, row in ipairs(loaded) do
		print(string.format("  Zone %d:", i))
		for k, v in pairs(row) do
			local str = typeof(v) == "table" and HttpService:JSONEncode(v) or tostring(v)
			print("   ", k, str)
		end
	end
end
]]

function ZoneTrackerModule.getZoneGridList(player, zoneId)
	local z = ZoneTrackerModule.getZoneById(player, zoneId)
	return z and z.gridList or {}
end

function ZoneTrackerModule.computeInfrastructureHappiness(player)
	if not (player and player:IsA("Player")) then return 100 end

	-- Only count building zones in happiness
	local BUILDING_ZONE = {
		Residential = true, Commercial = true, Industrial = true,
		ResDense    = true, CommDense  = true, IndusDense  = true,
	}

	-- Weighting that sums to 100 per tile (integer-safe)
	local WEIGHT = { Road = 33, Water = 33, Power = 34 }

	-- During load, tile flags may be nil. To avoid a startup “0%” dip,
	-- count nil as satisfied until requirements have been computed.
	local TREAT_NIL_AS_SATISFIED = true

	local function scoreFlag(v, key)
		if v == false then return 0 end
		if v == nil then
			return TREAT_NIL_AS_SATISFIED and WEIGHT[key] or 0
		end
		-- v == true
		return WEIGHT[key]
	end

	local totalPointsPossible = 0
	local totalPointsEarned   = 0

	for _, zone in pairs(ZoneTrackerModule.getAllZones(player)) do
		if BUILDING_ZONE[zone.mode] then
			for _, coord in ipairs(zone.gridList or {}) do
				-- Each building tile contributes up to 100 points
				totalPointsPossible += (WEIGHT.Road + WEIGHT.Water + WEIGHT.Power)

				local road  = ZoneTrackerModule.getTileRequirement(player, zone.zoneId, coord.x, coord.z, "Road")
				local water = ZoneTrackerModule.getTileRequirement(player, zone.zoneId, coord.x, coord.z, "Water")
				local power = ZoneTrackerModule.getTileRequirement(player, zone.zoneId, coord.x, coord.z, "Power")

				totalPointsEarned += scoreFlag(road,  "Road")
				totalPointsEarned += scoreFlag(water, "Water")
				totalPointsEarned += scoreFlag(power, "Power")
			end
		end
	end

	if totalPointsPossible == 0 then
		return 100 -- brand-new city
	end

	-- Convert to percentage with standard rounding
	local pct = (totalPointsEarned / totalPointsPossible) * 100
	return math.floor(pct + 0.5)
end

--[[REMOVE
ZoneTrackerModule.AirportTickets    = AirportTickets
ZoneTrackerModule.BusDepotTickets   = BusDepotTickets]]
ZoneTrackerModule.PackFlags         = Compressor.PackFlags
ZoneTrackerModule.UnpackFlags       = Compressor.UnpackFlags



return ZoneTrackerModule
