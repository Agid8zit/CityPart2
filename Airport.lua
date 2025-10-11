local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local S3                = game:GetService("ServerScriptService")

local Build      = S3:WaitForChild("Build")
local Zones      = Build:WaitForChild("Zones")
local ZoneMgr    = Zones:WaitForChild("ZoneManager")
local ZoneTracker= require(ZoneMgr:WaitForChild("ZoneTracker"))

local Events   = ReplicatedStorage:WaitForChild("Events")
local BE       = Events:WaitForChild("BindableEvents")
local REFolder = Events:WaitForChild("RemoteEvents")

-- Create/ensure RemoteEvent used to toggle the Airport GUI on the client
local function ensureRemoteEvent(parent: Instance, name: string): RemoteEvent
	local ev = parent:FindFirstChild(name)
	if ev and ev:IsA("RemoteEvent") then return ev end
	ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = parent
	return ev
end
local RE_ToggleAirportGui = ensureRemoteEvent(REFolder, "ToggleAirportGui")

-- Ensure bindable exists (for load-order safety)
local function ensureBindableEvent(container: Instance, name: string): BindableEvent
	local ev = container:FindFirstChild(name)
	if ev and ev:IsA("BindableEvent") then return ev end
	ev = Instance.new("BindableEvent")
	ev.Name = name
	ev.Parent = container
	return ev
end
local AirSupportUnlockedEvent = ensureBindableEvent(BE, "AirSupportUnlocked")

local AirportHandler = {}
AirportHandler.__index = AirportHandler

-- === config ===
local CLICK_NAME = "OpenAirportClick"
local CLICK_DIST = 128
local DEBUG_LOG  = false

local activePlayersWithSupport: {[Player]: boolean} = {}
local watchers: {[Player]: RBXScriptConnection?} = {}

local function log(...)
	if DEBUG_LOG then warn("[AirportHandler]", ...) end
end

-- Helpers
local function getPlayerPlot(player: Player): Instance?
	local plots = workspace:FindFirstChild("PlayerPlots")
	if not plots then return nil end
	return plots:FindFirstChild("Plot_" .. player.UserId)
end

local function isAirportName(name: string): boolean
	-- match common airport variants; extend as needed
	return name == "Airport" or name == "Airfield"
end

-- Bind ANY ClickDetector we find under the airport model (root or deep).
local function bindDetectorToAirport(player: Player, airportModel: Model, cd: ClickDetector)
	if not cd or not cd:IsA("ClickDetector") then return end
	if cd:GetAttribute("AirBound") then return end

	cd.MaxActivationDistance = CLICK_DIST
	cd:SetAttribute("AirBound", true)

	-- Debug hover
	cd.MouseHoverEnter:Connect(function(plr)
		if plr == player then log("hover:", airportModel:GetFullName(), "via", cd:GetFullName()) end
	end)

	-- Force OPEN on click (not toggle) so it reliably opens every time
	cd.MouseClick:Connect(function(plr)
		if plr ~= player then return end
		log("CLICK from", plr.Name, "on", airportModel:GetFullName(), "via", cd:GetFullName())
		RE_ToggleAirportGui:FireClient(player, true)
	end)
end

local function attachClickToAirport(player: Player, airportModel: Model)
	if not airportModel or not airportModel:IsA("Model") then return end
	if not isAirportName(airportModel.Name) then return end

	-- 1) Ensure/hoist a ClickDetector directly under the MODEL
	local cd: ClickDetector? = airportModel:FindFirstChild(CLICK_NAME) :: ClickDetector
	if not cd then
		local deep = airportModel:FindFirstChild(CLICK_NAME, true)
		if deep and deep:IsA("ClickDetector") then
			cd = deep
			cd.Parent = airportModel
			log("Hoisted ClickDetector to model root:", airportModel:GetFullName())
		else
			cd = Instance.new("ClickDetector")
			cd.Name = CLICK_NAME
			cd.Parent = airportModel
			log("Created model-level ClickDetector on:", airportModel:GetFullName())
		end
	end
	bindDetectorToAirport(player, airportModel, cd)

	-- 2) Bind to ANY other ClickDetector already deeper in the model
	for _, d in ipairs(airportModel:GetDescendants()) do
		if d:IsA("ClickDetector") then
			bindDetectorToAirport(player, airportModel, d)
		end
	end

	-- 3) Future detectors under this airport model
	if not airportModel:GetAttribute("AirCDWatcher") then
		airportModel:SetAttribute("AirCDWatcher", true)
		airportModel.DescendantAdded:Connect(function(inst: Instance)
			if inst:IsA("ClickDetector") then
				bindDetectorToAirport(player, airportModel, inst)
			end
		end)
	end
end

local function scanAndAttachAirportClickers(player: Player)
	local plot = getPlayerPlot(player)
	if not plot then
		log("scan: plot not found yet for", player.Name, "— will retry")
		task.spawn(function()
			while player.Parent and not getPlayerPlot(player) do task.wait(0.5) end
			if player.Parent then scanAndAttachAirportClickers(player) end
		end)
		return
	end

	local n = 0
	for _, inst in ipairs(plot:GetDescendants()) do
		if inst:IsA("Model") and isAirportName(inst.Name) then
			attachClickToAirport(player, inst)
			n += 1
		end
	end
	if n > 0 then
		log(("scan: attached to %d airport model(s) for %s"):format(n, player.Name))
	else
		log("scan: no airport models found yet for", player.Name)
	end
end

local function startWatchingPlayer(player: Player)
	-- clear old watcher
	if watchers[player] then watchers[player]:Disconnect() end
	watchers[player] = nil

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
	scanAndAttachAirportClickers(player)

	-- watch whole plot for future airport models / detectors
	watchers[player] = plot.DescendantAdded:Connect(function(inst: Instance)
		if inst:IsA("Model") and isAirportName(inst.Name) then
			log("watch: new airport model appeared:", inst:GetFullName())
			attachClickToAirport(player, inst)
		elseif inst:IsA("ClickDetector")
			and inst.Parent and inst.Parent:IsA("Model")
			and isAirportName(inst.Parent.Name) then
			log("watch: detector added under airport:", inst:GetFullName())
			attachClickToAirport(player, inst.Parent)
		end
	end)
end

-- Zone add assist (airport zone placed)
ZoneTracker.zoneAddedEvent.Event:Connect(function(player: Player, _zoneId: string, zoneData)
	if not player then return end
	if not zoneData or (zoneData.mode ~= "Airport" and zoneData.mode ~= "Airfield") then return end
	task.defer(scanAndAttachAirportClickers, player)
end)

-- Public API
function AirportHandler.onSupportUnlocked(player: Player)
	activePlayersWithSupport[player] = true
	startWatchingPlayer(player)
end

function AirportHandler.onSupportRevoked(player: Player)
	activePlayersWithSupport[player] = nil
	if watchers[player] then watchers[player]:Disconnect() end
	watchers[player] = nil

	-- optional cleanup of old clickers (safe)
	local plot = getPlayerPlot(player)
	if plot then
		for _, inst in ipairs(plot:GetDescendants()) do
			if inst:IsA("ClickDetector") and (inst.Name == CLICK_NAME or inst.Name == "AirportIncidentClick") then
				inst:Destroy()
			end
		end
	end
end

-- Bindable to unlock
AirSupportUnlockedEvent.Event:Connect(function(player: Player)
	AirportHandler.onSupportUnlocked(player)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	AirportHandler.onSupportRevoked(player)
end)

return AirportHandler

