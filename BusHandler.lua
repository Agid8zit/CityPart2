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

local BusHandler = {}
BusHandler.__index = BusHandler

-- === config ===
local CLICK_NAME = "OpenBusDepotClick"
local CLICK_DIST = 128 
local DEBUG_LOG  = false

local activePlayersWithSupport: {[Player]: boolean} = {}
local watchers: {[Player]: {conn: RBXScriptConnection?}} = {}

local function log(...)
	if DEBUG_LOG then warn("[BusHandler]", ...) end
end

-- Utility: Player’s populated folder is where built zone models end up
local function getPlayerPopulatedFolder(player: Player): Folder?
	local plots = workspace:FindFirstChild("PlayerPlots")
	if not plots then return nil end
	local plot = plots:FindFirstChild("Plot_" .. player.UserId)
	if not plot then return nil end
	local buildings = plot:FindFirstChild("Buildings")
	if not buildings then return nil end
	return buildings:FindFirstChild("Populated")
end

-- “Incident” markers logic unchanged
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

-- === Bus Depot clickers (ClickDetector directly under the MODEL) ===

local function getPlayerPlot(player: Player): Instance?
	local plots = workspace:FindFirstChild("PlayerPlots")
	if not plots then return nil end
	return plots:FindFirstChild("Plot_" .. player.UserId)
end

local function isDepotName(name: string): boolean
	return name == "Bus Depot" or name == "BusDepot"
end

-- Bind ANY ClickDetector we find under the depot (model-level or deep).
-- NOTE: Uses the upvalue RE_ToggleBusDepotGui defined at the top.
local function bindDetectorToDepot(player: Player, depotModel: Model, cd: ClickDetector)
	if not cd or not cd:IsA("ClickDetector") then return end
	if cd:GetAttribute("BusBound") then return end

	cd.MaxActivationDistance = CLICK_DIST
	cd:SetAttribute("BusBound", true)

	-- Helpful while testing; remove when happy
	cd.MouseHoverEnter:Connect(function(plr)
		if plr == player then log("hover:", depotModel:GetFullName(), "via", cd:GetFullName()) end
	end)

	cd.MouseClick:Connect(function(plr)
		if plr ~= player then return end
		log("CLICK from", plr.Name, "on", depotModel:GetFullName(), "via", cd:GetFullName())
		RE_ToggleBusDepotGui:FireClient(player, true) -- <<< force OPEN (true), not toggle
	end)
end

local function attachClickToDepot(player: Player, depotModel: Model)
	if not depotModel or not depotModel:IsA("Model") then return end
	if not isDepotName(depotModel.Name) then return end

	-- 1) Ensure/hoist a ClickDetector directly under the MODEL (child of the model, as requested)
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
			n += 1
		end
	end
	if n > 0 then
		log(("scan: attached to %d depot model(s) for %s"):format(n, player.Name))
	else
		log("scan: no depot models found yet for", player.Name)
	end
end

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

	-- initial sweep of the entire plot
	scanAndAttachDepotClickers(player)

	-- watch the entire plot for anything newly added that matches
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
function BusHandler.onSupportUnlocked(player: Player)
	activePlayersWithSupport[player] = true
	startWatchingPlayer(player)
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
end

-- Bindable to unlock
BusSupportUnlockedEvent.Event:Connect(function(player: Player)
	BusHandler.onSupportUnlocked(player)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	BusHandler.onSupportRevoked(player)
end)

return BusHandler
