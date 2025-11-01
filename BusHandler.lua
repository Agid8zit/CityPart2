-- ServerScriptService.Build.Districts.Stats.UniqueZones.UniqueZoneInteractions.Bus

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local S3                = game:GetService("ServerScriptService")

local Build      = S3:WaitForChild("Build")
local Zones      = Build:WaitForChild("Zones")
local ZoneMgr    = Zones:WaitForChild("ZoneManager")
local ZoneTracker= require(ZoneMgr:WaitForChild("ZoneTracker"))

local FuncTestGroundRS = ReplicatedStorage:WaitForChild("FuncTestGroundRS")
local Alarms           = FuncTestGroundRS:WaitForChild("Alarms")
local BusTemplate      = Alarms:FindFirstChild("Bus")

local Events   = ReplicatedStorage:WaitForChild("Events")
local BE       = Events:WaitForChild("BindableEvents")
local REFolder = Events:WaitForChild("RemoteEvents")

--=== Transit tier reads (bus depot) ===================================
local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService:WaitForChild("Services")
local PlayerDataInterfaceService = require(Services:WaitForChild("PlayerDataInterfaceService"))

--=== Asset roots ======================================================
local CarsRoot    = ReplicatedStorage:WaitForChild("FuncTestGroundRS"):WaitForChild("Cars")
local BusesFolder = CarsRoot:FindFirstChild("Buses") or CarsRoot:FindFirstChild("Busses") -- tolerate typo

--=== Config ===========================================================
local MAX_BUS_TIERS = 10                 -- schema supports up to 10
local SLOTS_TO_SHOW = 6                  -- placeholders named Tier1..Tier6
local TIER_NAME_PATTERN = "^Tier(%d+)$"  -- fallback scanning
local CLICK_NAME = "OpenBusDepotClick"
local CLICK_DIST = 128
local DEBUG_LOG  = false

-- When no bus is spawned in the slot, show these placeholder slots by default:
-- Tier1, Tier2, Tier5, Tier6 visible; Tier3, Tier4 hidden
local PLACEHOLDER_VISIBLE_IF_EMPTY = {1, 2, 5, 6}

-- Internal state
local activePlayersWithSupport: {[Player]: boolean} = {}
local watchers: {[Player]: {conn: RBXScriptConnection?}} = {}

--=====================
-- Utilities / logging
--=====================
local function log(...)
	if DEBUG_LOG then warn("[BusHandler]", ...) end
end

-- Create/ensure RemoteEvent used to toggle the BusDepot GUI on the client
local function ensureRemoteEvent(parent: Instance, name: string): RemoteEvent
	local ev = parent:FindFirstChild(name)
	if ev and ev:IsA("RemoteEvent") then return ev end
	ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = parent
	return ev
end
local RE_ToggleBusDepotGui = ensureRemoteEvent(REFolder, "ToggleBusDepotGui")

-- Ensure bindable exists (for load-order safety)
local function ensureBindableEvent(container: Instance, name: string): BindableEvent
	local ev = container:FindFirstChild(name)
	if ev and ev:IsA("BindableEvent") then return ev end
	ev = Instance.new("BindableEvent")
	ev.Name = name
	ev.Parent = container
	return ev
end
local BusSupportUnlockedEvent = ensureBindableEvent(BE, "BusSupportUnlocked")

--=====================
-- Plot helpers
--=====================
local function getPlayerPlot(player: Player): Instance?
	local plots = workspace:FindFirstChild("PlayerPlots")
	if not plots then return nil end
	return plots:FindFirstChild("Plot_" .. player.UserId)
end

local function getPlayerPopulatedFolder(player: Player): Folder?
	local plots = workspace:FindFirstChild("PlayerPlots")
	if not plots then return nil end
	local plot = plots:FindFirstChild("Plot_" .. player.UserId)
	if not plot then return nil end
	local buildings = plot:FindFirstChild("Buildings")
	if not buildings then return nil end
	return buildings:FindFirstChild("Populated")
end

--=====================
-- Depot name check
--=====================
local function isDepotName(name: string): boolean
	return name == "Bus Depot" or name == "BusDepot"
end

--=====================
-- “Incident” markers
--=====================
local function collectEligibleModels(player: Player): {Model}
	local valid = {}
	local populated = getPlayerPopulatedFolder(player); if not populated then return valid end
	for _, folder in ipairs(populated:GetChildren()) do
		if folder:IsA("Folder") then
			for _, child in ipairs(folder:GetDescendants()) do
				if child:IsA("Model") and child.PrimaryPart then
					table.insert(valid, child)
				end
			end
		end
	end
	return valid
end

task.spawn(function()
	if not BusTemplate then
		log("Missing FuncTestGroundRS/Alarms/Bus – incidents disabled")
		return
	end
	while true do
		task.wait(150)
		for player in pairs(activePlayersWithSupport) do
			local ok, err = pcall(function()
				local c = collectEligibleModels(player)
				if #c == 0 then return end
				local target = c[math.random(1,#c)]
				local marker = BusTemplate:Clone()
				marker.Anchored = true
				marker.CFrame = CFrame.new(target.PrimaryPart.Position + Vector3.new(0,2,0))
				marker.Parent = target
				local cd = Instance.new("ClickDetector")
				cd.Name = "BusIncidentClick"
				cd.MaxActivationDistance = CLICK_DIST
				cd.Parent = marker
				cd.MouseClick:Connect(function(clicker)
					if clicker == player then marker:Destroy() end
				end)
			end)
			if not ok then log("incident loop error:", err) end
		end
	end
end)

--=====================
-- Click binding
--=====================
local function bindDetectorToDepot(player: Player, depotModel: Model, cd: ClickDetector)
	if not cd or not cd:IsA("ClickDetector") then return end
	if cd:GetAttribute("BusBound") then return end
	cd.MaxActivationDistance = CLICK_DIST
	cd:SetAttribute("BusBound", true)

	cd.MouseHoverEnter:Connect(function(plr)
		if plr == player then log("hover:", depotModel:GetFullName(), "via", cd:GetFullName()) end
	end)

	cd.MouseClick:Connect(function(plr)
		if plr ~= player then return end
		log("CLICK from", plr.Name, "on", depotModel:GetFullName(), "via", cd:GetFullName())
		RE_ToggleBusDepotGui:FireClient(player, true) -- force OPEN
	end)
end

--=====================
-- Tier math (unlock/level)
--=====================
local function unlockedTiersFromUnlockValue(unlockNum: number): number
	local t = math.floor(math.max(0, tonumber(unlockNum) or 0) / 10) + 1
	return math.clamp(t, 1, MAX_BUS_TIERS)
end

-- Return array of up to 6 highest tiers (largest index first) the player has level>0 in and is unlocked for.
local function topSixActiveBusTiers(player: Player): {number}
	local unlock  = PlayerDataInterfaceService.GetTransitUnlock(player, "busDepot") or 0
	local maxTier = unlockedTiersFromUnlockValue(unlock)
	local top = {}
	for ti = maxTier, 1, -1 do
		local lv = PlayerDataInterfaceService.GetTransitTierLevel(player, "busDepot", ti) or 0
		if lv > 0 then
			table.insert(top, ti)
			if #top >= SLOTS_TO_SHOW then break end
		end
	end
	return top
end

--=====================
-- Depot slot discovery
--=====================
local function findDepotSlots(depot: Model): {Instance}
	local slots = {}
	local meshes = depot:FindFirstChild("Meshes")
	if meshes then
		for i=1, SLOTS_TO_SHOW do
			local slot = meshes:FindFirstChild(("Tier%d"):format(i)) or meshes:FindFirstChild(("Tier%d"):format(i), true)
			if slot then table.insert(slots, slot) end
		end
		-- If strict Tier1..Tier6 not found, fall back to any six children
		if #slots == 0 then
			for _, ch in ipairs(meshes:GetChildren()) do
				if #slots >= SLOTS_TO_SHOW then break end
				table.insert(slots, ch)
			end
		end
		return slots
	end

	-- No "Meshes" container: collect direct Tier* children on the model
	local tiers = {}
	for _, ch in ipairs(depot:GetChildren()) do
		local m = string.match(ch.Name, TIER_NAME_PATTERN)
		if m then table.insert(tiers, ch) end
	end
	table.sort(tiers, function(a,b) return a.Name < b.Name end)
	for i=1, math.min(#tiers, SLOTS_TO_SHOW) do slots[i] = tiers[i] end
	if #slots > 0 then return slots end

	-- Last resort: any 6 visible-ish children
	for _, ch in ipairs(depot:GetChildren()) do
		if #slots >= SLOTS_TO_SHOW then break end
		if ch:IsA("BasePart") or ch:IsA("Model") or ch:IsA("Folder") then
			table.insert(slots, ch)
		end
	end
	return slots
end

--=====================
-- Placeholder visibility
--=====================
local function setPlaceholderVisible(slot: Instance, visible: boolean)
	if not slot then return end
	for _, d in ipairs(slot:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("MeshPart") then
			d.Transparency = visible and 0 or 1
			d.CanCollide = false
		elseif d:IsA("Decal") then
			d.Transparency = visible and 0 or 1
		end
	end
end

local function hideSlot(slot: Instance) setPlaceholderVisible(slot, false) end

--=====================
-- Bus model selection
--=====================
local BUS_MODEL_NAME_RX = "^Bus(%d+)$"
local _busModelIndex = nil

local function indexBusModels()
	local byTier = {}  -- [tierNum] = Model
	if BusesFolder then
		for _, m in ipairs(BusesFolder:GetChildren()) do
			if m:IsA("Model") then
				local n = tonumber(string.match(m.Name, BUS_MODEL_NAME_RX))
				if n then byTier[n] = m end
			end
		end
	end
	return byTier
end

-- Prefer exact tier model; else step down to lower tiers
local function bestBusModelForTier(desiredTier: number): Instance?
	_busModelIndex = _busModelIndex or indexBusModels()
	for t = desiredTier, 1, -1 do
		if _busModelIndex[t] then return _busModelIndex[t] end
	end
	return nil
end

-- Inside BusN, prefer child "BusLevelN"; else use the model itself
local function extractVisualFromBusModel(model: Instance): Instance
	if not model then return nil end
	local n = tonumber(string.match(model.Name, BUS_MODEL_NAME_RX))
	if n then
		local child = model:FindFirstChild(("BusLevel%d"):format(n), true)
		if child then return child end
	end
	return model
end

--=====================
-- Spawning / positioning
--=====================
local function getOrCreateSpawnFolder(depot: Model): Folder
	local f = depot:FindFirstChild("SpawnedBuses")
	if f and f:IsA("Folder") then return f end
	f = Instance.new("Folder")
	f.Name = "SpawnedBuses"
	f.Parent = depot
	return f
end

local function spawnBusAtSlot(depot: Model, slot: Instance, busModel: Instance, tag: string)
	local holder = getOrCreateSpawnFolder(depot)

	-- clear previous for this slot tag
	for _, ch in ipairs(holder:GetChildren()) do
		if (ch:IsA("Model") or ch:IsA("Folder")) and ch:GetAttribute("DepotSlotTag") == tag then
			pcall(function() ch:Destroy() end)
		end
	end

	local toClone = extractVisualFromBusModel(busModel)
	local vis = toClone:Clone()
	vis.Name = ("DepotBus_%s"):format(tag)
	vis:SetAttribute("DepotSlotTag", tag)
	vis.Parent = holder

	-- derive pivot from slot (BasePart / Attachment / Model.PrimaryPart / first BasePart / depot pivot)
	local pivotCF
	if slot:IsA("BasePart") or slot:IsA("MeshPart") then
		pivotCF = slot.CFrame
	elseif slot:IsA("Attachment") then
		pivotCF = slot.WorldCFrame
	elseif slot:IsA("Model") and slot.PrimaryPart then
		pivotCF = slot.PrimaryPart.CFrame
	else
		local pp = slot:FindFirstChildWhichIsA("BasePart", true)
		pivotCF = pp and pp.CFrame or depot:GetPivot()
	end

	if vis:IsA("Model") then
		if not vis.PrimaryPart then
			local pp = vis:FindFirstChildWhichIsA("BasePart", true)
			if pp then vis.PrimaryPart = pp end
		end
		vis:PivotTo(pivotCF)
	elseif vis:IsA("BasePart") then
		vis.CFrame = pivotCF
	else
		-- wrap misc content into a model and position that
		local wrap = Instance.new("Model")
		wrap.Name = vis.Name .. "_Wrap"
		vis.Parent = wrap
		wrap.Parent = holder
		local pp = wrap:FindFirstChildWhichIsA("BasePart", true)
		if pp then wrap.PrimaryPart = pp; wrap:PivotTo(pivotCF) end
		wrap:SetAttribute("DepotSlotTag", tag)
	end
end

--=====================
-- Apply tiers → depot
--=====================
local function applyDepotTiersVisuals(player: Player, depot: Model)
	if not depot or not depot:IsA("Model") then return end
	if not isDepotName(depot.Name) then return end

	local slots = findDepotSlots(depot)
	if #slots == 0 then return end

	-- pick top 6 active tiers for this player
	local topTiers = topSixActiveBusTiers(player) -- e.g. {6,5,3}

	-- Assign highest tiers to slots 1..6; when no tier for a slot, apply placeholder defaults
	for i = 1, SLOTS_TO_SHOW do
		local slot = slots[i]
		if not slot then break end
		local tag  = ("Slot%d"):format(i)
		local tier = topTiers[i]

		if tier then
			local model = bestBusModelForTier(tier)
			if model then
				spawnBusAtSlot(depot, slot, model, tag)
				setPlaceholderVisible(slot, false) -- hide shell when a bus is present
			else
				-- No model available for this tier -> leave placeholder as per default visibility
				local show = table.find(PLACEHOLDER_VISIBLE_IF_EMPTY, i) ~= nil
				setPlaceholderVisible(slot, show)
			end
		else
			-- No active tier mapped to this slot -> default placeholder visibility (Tier1,2,5,6 visible; 3,4 hidden)
			local show = table.find(PLACEHOLDER_VISIBLE_IF_EMPTY, i) ~= nil
			setPlaceholderVisible(slot, show)

			-- Also clear any stale spawned visual for this slot tag
			local holder = depot:FindFirstChild("SpawnedBuses")
			if holder then
				for _, ch in ipairs(holder:GetChildren()) do
					if (ch:IsA("Model") or ch:IsA("Folder")) and ch:GetAttribute("DepotSlotTag") == tag then
						pcall(function() ch:Destroy() end)
					end
				end
			end
		end
	end
end

--=====================
-- Depot attach / scan
--=====================
local function attachClickToDepot(player: Player, depotModel: Model)
	if not depotModel or not depotModel:IsA("Model") then return end
	if not isDepotName(depotModel.Name) then return end

	-- 1) Ensure/hoist a ClickDetector directly under the MODEL
	local cd: ClickDetector? = depotModel:FindFirstChild(CLICK_NAME) :: ClickDetector
	if not cd then
		local deep = depotModel:FindFirstChild(CLICK_NAME, true)
		if deep and deep:IsA("ClickDetector") then
			cd = deep
			cd.Parent = depotModel
			log("Hoisted ClickDetector to model root:", depotModel:GetFullName())
		else
			cd = Instance.new("ClickDetector")
			cd.Name = CLICK_NAME
			cd.Parent = depotModel
			log("Created model-level ClickDetector on:", depotModel:GetFullName())
		end
	end
	bindDetectorToDepot(player, depotModel, cd)

	-- Apply tier visuals now
	applyDepotTiersVisuals(player, depotModel)

	-- 2) ALSO bind to ANY other ClickDetector that already exists deeper in the model
	for _, d in ipairs(depotModel:GetDescendants()) do
		if d:IsA("ClickDetector") then
			bindDetectorToDepot(player, depotModel, d)
		end
	end

	-- 3) If future detectors/parts get added under this depot, bind them too
	if not depotModel:GetAttribute("BusCDWatcher") then
		depotModel:SetAttribute("BusCDWatcher", true)
		depotModel.DescendantAdded:Connect(function(inst: Instance)
			if inst:IsA("ClickDetector") then
				bindDetectorToDepot(player, depotModel, inst)
			end
		end)
	end
end

local function scanAndAttachDepotClickers(player: Player)
	local plot = getPlayerPlot(player)
	if not plot then
		log("scan: plot not found yet for", player.Name, "— will retry")
		task.spawn(function()
			while player.Parent and not getPlayerPlot(player) do task.wait(0.5) end
			if player.Parent then scanAndAttachDepotClickers(player) end
		end)
		return
	end

	local n = 0
	for _, inst in ipairs(plot:GetDescendants()) do
		if inst:IsA("Model") and isDepotName(inst.Name) then
			attachClickToDepot(player, inst)
			-- ensure visuals even if binder returned early previously
			applyDepotTiersVisuals(player, inst)
			n += 1
		end
	end
	if n > 0 then
		log(("scan: attached to %d depot model(s) for %s"):format(n, player.Name))
	else
		log("scan: no depot models found yet for", player.Name)
	end
end

--=====================
-- Watchers / lifecycle
--=====================
local function startWatchingPlayer(player: Player)
	-- clear old watcher
	if watchers[player] and watchers[player].conn then
		watchers[player].conn:Disconnect()
	end
	watchers[player] = watchers[player] or {}

	local plot = getPlayerPlot(player)
	if not plot then
		log("watch: plot not found for", player.Name, "— waiting for it to exist")
		task.spawn(function()
			while player.Parent and not getPlayerPlot(player) do task.wait(0.5) end
			if player.Parent then startWatchingPlayer(player) end
		end)
		return
	end

	-- initial sweep
	scanAndAttachDepotClickers(player)

	-- watch new depots or clickdetectors under depots
	watchers[player].conn = plot.DescendantAdded:Connect(function(inst: Instance)
		if inst:IsA("Model") and isDepotName(inst.Name) then
			log("watch: new depot model appeared:", inst:GetFullName())
			attachClickToDepot(player, inst)
		elseif inst:IsA("ClickDetector")
			and inst.Parent and inst.Parent:IsA("Model")
			and isDepotName(inst.Parent.Name) then
			log("watch: detector added under depot:", inst:GetFullName())
			attachClickToDepot(player, inst.Parent)
		end
	end)
end

-- Zone add assist
ZoneTracker.zoneAddedEvent.Event:Connect(function(player: Player, _zoneId: string, zoneData)
	if not player then return end
	if not zoneData or (zoneData.mode ~= "BusDepot" and zoneData.mode ~= "Bus Depot") then return end
	task.defer(scanAndAttachDepotClickers, player)
end)

-- Public API
local BusHandler = {}
BusHandler.__index = BusHandler

function BusHandler.onSupportUnlocked(player: Player)
	activePlayersWithSupport[player] = true
	startWatchingPlayer(player)
	-- refresh visuals on any existing depots
	local plot = getPlayerPlot(player)
	if plot then
		for _, inst in ipairs(plot:GetDescendants()) do
			if inst:IsA("Model") and isDepotName(inst.Name) then
				applyDepotTiersVisuals(player, inst)
			end
		end
	end
end

function BusHandler.onSupportRevoked(player: Player)
	activePlayersWithSupport[player] = nil
	if watchers[player] and watchers[player].conn then
		watchers[player].conn:Disconnect()
	end
	watchers[player] = nil

	-- optional cleanup of old clickers (safe)
	local plot = workspace:FindFirstChild("PlayerPlots")
	local myPlot = plot and plot:FindFirstChild("Plot_" .. player.UserId)
	if myPlot then
		for _, inst in ipairs(myPlot:GetDescendants()) do
			if inst:IsA("ClickDetector") and (inst.Name == CLICK_NAME or inst.Name == "BusIncidentClick") then
				inst:Destroy()
			end
		end
	end
	-- (we do not delete SpawnedBuses here so the art remains if you prefer; add cleanup if desired)
end

-- Live refresh when tiers/levels change
-- Live refresh when tiers/levels change (create-or-attach, and attach if added later)
local function attachTierChanged(ev: BindableEvent)
	if not ev or not ev:IsA("BindableEvent") then return end
	if ev:GetAttribute("BusHandlerWired") then return end -- avoid double-connecting
	ev:SetAttribute("BusHandlerWired", true)

	ev.Event:Connect(function(player: Player)
		local plot = getPlayerPlot(player)
		if not plot then return end
		for _, inst in ipairs(plot:GetDescendants()) do
			if inst:IsA("Model") and isDepotName(inst.Name) then
				applyDepotTiersVisuals(player, inst)
			end
		end
	end)
end

-- Ensure the event exists and attach now
local TransitBusTierChanged = ensureBindableEvent(BE, "TransitBusTierChanged")
attachTierChanged(TransitBusTierChanged)

-- If something recreates the BE children later, hook that too
BE.ChildAdded:Connect(function(ch)
	if ch.Name == "TransitBusTierChanged" and ch:IsA("BindableEvent") then
		attachTierChanged(ch)
	end
end)

-- Bindable to unlock
BusSupportUnlockedEvent.Event:Connect(function(player: Player)
	BusHandler.onSupportUnlocked(player)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	BusHandler.onSupportRevoked(player)
end)

return BusHandler
