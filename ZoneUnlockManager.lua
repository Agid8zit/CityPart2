-- Unlocks.server.lua  (enhanced to use Balance.UnlockCosts)

local Players             = game:GetService("Players")
local Workspace           = game:GetService("Workspace")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage       = game:GetService("ServerStorage")

---------------------------------------------------------------------
-- External deps
---------------------------------------------------------------------
local S3        = ServerScriptService
local ZoneMgr   = S3.Build.Zones.ZoneManager
local EconomyService = require(ZoneMgr:WaitForChild("EconomyService"))
local BadgeServiceModule = require(ServerScriptService.Services.BadgeService)

local Balancing = ReplicatedStorage:WaitForChild("Balancing")
local Balance   = require(Balancing:WaitForChild("BalanceEconomy"))

---------------------------------------------------------------------
-- Events folders (race-proof; create-or-get singletons)
---------------------------------------------------------------------
local EventsFolder = ReplicatedStorage:FindFirstChild("Events")
local RemoteEventsFolder = EventsFolder:FindFirstChild("RemoteEvents")
local BindableFolder = EventsFolder:FindFirstChild("BindableEvents")

---------------------------------------------------------------------
-- Remotes / Bindables API (normalize types)
---------------------------------------------------------------------
-- Client -> Server: menu-driven unlock requests
local UnlockEvent = RemoteEventsFolder:FindFirstChild("UnlockEvent")

-- Enforce: RequestAllUnlocks must be a RemoteFunction
do
	local existing = RemoteEventsFolder:FindFirstChild("RequestAllUnlocks")
	if existing and not existing:IsA("RemoteFunction") then
		warn(("[Unlocks] '%s' is a %s; replacing with RemoteFunction"):format(existing.Name, existing.ClassName))
		existing:Destroy()
	end
end
local RequestAllUnlocks = RemoteEventsFolder:FindFirstChild("RequestAllUnlocks")


-- Server -> Client push when unlocks change
local UnlocksUpdated = RemoteEventsFolder:FindFirstChild("UnlocksUpdated")


-- Bindables SaveManager expects
local GetUnlocksForPlayer = BindableFolder:FindFirstChild("GetUnlocksForPlayer")


local SetUnlocksForPlayer = BindableFolder:FindFirstChild("SetUnlocksForPlayer")


local UnlockChanged = BindableFolder:FindFirstChild("UnlockChanged")


-- Optional BE from PlotAssigner
local PlotAssignedBE = BindableFolder:FindFirstChild("PlotAssignedBE")
-- Optional BE fired by SaveManager after it persists
local PlayerSavedBE = BindableFolder:FindFirstChild("PlayerSaved")

---------------------------------------------------------------------
-- In-memory canonical state (runtime only; SaveManager persists)
---------------------------------------------------------------------
-- { [Player] = { [unlockName] = true } }
local InMemoryUnlocks : { [Player] : { [string]: boolean } } = {}

local MAP_EXPANSION_UNLOCKS = {
	Unlock_1 = true,
	Unlock_2 = true,
	Unlock_3 = true,
	Unlock_4 = true,
	Unlock_5 = true,
	Unlock_6 = true,
}

local TOTAL_MAP_EXPANSIONS = 0
for _ in pairs(MAP_EXPANSION_UNLOCKS) do
	TOTAL_MAP_EXPANSIONS += 1
end

local function _checkMapExpansionBadges(player: Player)
	if not BadgeServiceModule then return end
	local ownedTable = InMemoryUnlocks[player]
	if not ownedTable then return end

	local ownedCount = 0
	for unlockName in pairs(MAP_EXPANSION_UNLOCKS) do
		if ownedTable[unlockName] then
			ownedCount += 1
		end
	end

	if ownedCount > 0 then
		BadgeServiceModule.AwardFirstMapExpansion(player)
	end

	if TOTAL_MAP_EXPANSIONS > 0 and ownedCount >= TOTAL_MAP_EXPANSIONS then
		BadgeServiceModule.AwardAllMapExpansions(player)
	end
end

local function _pushUnlocksToClient(player: Player)
	UnlocksUpdated:FireClient(player, InMemoryUnlocks[player] or {})
end

---------------------------------------------------------------------
-- Template reference (read-only)
---------------------------------------------------------------------
local PlotTemplates = ServerStorage:FindFirstChild("PlotTemplates")
local TemplateModel = PlotTemplates and PlotTemplates:FindFirstChild("TestTerrain") -- adjust if needed

local function getPlayerPlot(player: Player): Model?
	local plotName = player:GetAttribute("PlotName"); if not plotName then return nil end
	local plots = Workspace:FindFirstChild("PlayerPlots"); if not plots then return nil end
	local inst = plots:FindFirstChild(plotName)
	if inst and inst:IsA("Model") then return inst end
	return nil
end

---------------------------------------------------------------------
-- Helpers: robust, stable pivots and owning-plot discovery
---------------------------------------------------------------------
local function findOwningPlot(inst: Instance): Model?
	local plots = Workspace:FindFirstChild("PlayerPlots")
	if not plots then return nil end
	local p: Instance? = inst
	while p and p ~= plots do
		if p.Parent == plots and p:IsA("Model") then
			return p :: Model
		end
		p = p.Parent
	end
	return nil
end

local function pivotOf(inst: Instance): CFrame
	if inst:IsA("Model") then
		local m = inst :: Model
		if m.PrimaryPart then
			return m:GetPivot()
		else
			local bboxCf = m:GetBoundingBox()
			return bboxCf
		end
	elseif inst:IsA("BasePart") then
		return (inst :: BasePart).CFrame
	else
		return CFrame.new()
	end
end

---------------------------------------------------------------------
-- Plot-root–relative placement of a single child (e.g. "Unlock")
---------------------------------------------------------------------
local function ensureChildFromTemplate(dstModel: Instance, srcModel: Instance, childName: string)
	if not (TemplateModel and dstModel and srcModel) then return end
	local srcChild = srcModel:FindFirstChild(childName)
	if not srcChild then return end

	-- 1) Identify the destination player plot (owning root for dstModel)
	local dstPlot = findOwningPlot(dstModel)
	if not dstPlot then return end

	-- 2) Compute child's pose relative to TEMPLATE plot root
	local srcPlotPivot  = pivotOf(TemplateModel)
	local srcChildPivot = pivotOf(srcChild)
	local relToPlot     = srcPlotPivot:ToObjectSpace(srcChildPivot)

	-- 3) Re-express that pose in the PLAYER plot's frame
	local dstPlotPivot  = pivotOf(dstPlot)
	local desiredWorld  = dstPlotPivot * relToPlot

	-- 4) Ensure destination child exists and snap it to the computed world CFrame
	local dstChild = dstModel:FindFirstChild(childName)
	if not dstChild then
		dstChild = srcChild:Clone()
		dstChild.Parent = dstModel
	end

	if dstChild:IsA("Model") then
		(dstChild :: Model):PivotTo(desiredWorld)
	elseif dstChild:IsA("BasePart") then
		local bp = dstChild :: BasePart
		bp.Anchored = true
		bp.CFrame   = desiredWorld
	end
end

---------------------------------------------------------------------
-- Sync minimal tree (only what we need for relock/apply)
---------------------------------------------------------------------
local function syncUnlockTreeFromTemplate(player: Player)
	if not TemplateModel then return end
	local plot = getPlayerPlot(player); if not plot then return end

	local dstUnlocks = plot:FindFirstChild("Unlocks")
	local srcUnlocks = TemplateModel:FindFirstChild("Unlocks")
	if not (dstUnlocks and srcUnlocks) then return end

	-- 1) Clone missing unlock models
	for _, srcUnlockModel in ipairs(srcUnlocks:GetChildren()) do
		if srcUnlockModel:IsA("Model") then
			if not dstUnlocks:FindFirstChild(srcUnlockModel.Name) then
				local newM = Instance.new("Model")
				newM.Name = srcUnlockModel.Name
				newM.Parent = dstUnlocks
			end
		end
	end

	-- 2) Ensure segment folders/models exist
	for _, srcUnlockModel in ipairs(srcUnlocks:GetChildren()) do
		if srcUnlockModel:IsA("Model") then
			local dstUnlockModel = dstUnlocks:FindFirstChild(srcUnlockModel.Name)
			if dstUnlockModel and dstUnlockModel:IsA("Model") then
				for _, srcSeg in ipairs(srcUnlockModel:GetChildren()) do
					if srcSeg:IsA("Model") then
						if not dstUnlockModel:FindFirstChild(srcSeg.Name) then
							local newSeg = Instance.new("Model")
							newSeg.Name = srcSeg.Name
							newSeg.Parent = dstUnlockModel
						end
					end
				end
			end
		end
	end

	-- 3) Ensure each unlock model/segment has an `Unlock` part (placed via template pose)
	for _, srcUnlockModel in ipairs(srcUnlocks:GetChildren()) do
		if srcUnlockModel:IsA("Model") then
			local dstUnlockModel = dstUnlocks:FindFirstChild(srcUnlockModel.Name)
			if dstUnlockModel and dstUnlockModel:IsA("Model") then
				if srcUnlockModel:FindFirstChild("Unlock") then
					ensureChildFromTemplate(dstUnlockModel, srcUnlockModel, "Unlock")
				end
				for _, srcSeg in ipairs(srcUnlockModel:GetChildren()) do
					if srcSeg:IsA("Model") and srcSeg:FindFirstChild("Unlock") then
						local dstSeg = dstUnlockModel:FindFirstChild(srcSeg.Name)
						if dstSeg and dstSeg:IsA("Model") then
							ensureChildFromTemplate(dstSeg, srcSeg, "Unlock")
						end
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- Relock: recreate blockers for *locked* zones (plot-root–relative)
---------------------------------------------------------------------
local function relockFromTemplate(player: Player, unlockTable: {[string]: boolean})
	if not TemplateModel then return end
	local plot = getPlayerPlot(player); if not plot then return end

	local dstUnlocks = plot:FindFirstChild("Unlocks")
	local srcUnlocks = TemplateModel:FindFirstChild("Unlocks")
	if not (dstUnlocks and srcUnlocks) then return end

	for _, srcUnlockModel in ipairs(srcUnlocks:GetChildren()) do
		if srcUnlockModel:IsA("Model") then
			local unlockName = srcUnlockModel.Name
			local enabled = unlockTable and unlockTable[unlockName] == true
			if not enabled then
				local dstUnlockModel = dstUnlocks:FindFirstChild(unlockName)
				if dstUnlockModel and dstUnlockModel:IsA("Model") then
					if srcUnlockModel:FindFirstChild("Unlock") then
						ensureChildFromTemplate(dstUnlockModel, srcUnlockModel, "Unlock")
					end
					for _, srcSeg in ipairs(srcUnlockModel:GetChildren()) do
						if srcSeg:IsA("Model") and srcSeg:FindFirstChild("Unlock") then
							local dstSeg = dstUnlockModel:FindFirstChild(srcSeg.Name)
							if dstSeg and dstSeg:IsA("Model") then
								ensureChildFromTemplate(dstSeg, srcSeg, "Unlock")
							end
						end
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- Apply unlocks (remove blockers where unlocked)
---------------------------------------------------------------------
local function applyUnlocksToPlot(player: Player, unlockTable: {[string]: boolean})
	local plot = getPlayerPlot(player); if not plot then return end
	local unlocksFolder = plot:FindFirstChild("Unlocks"); if not unlocksFolder then return end

	for unlockName, enabled in pairs(unlockTable) do
		if enabled then
			local model = unlocksFolder:FindFirstChild(unlockName)
			if model then
				local direct = model:FindFirstChild("Unlock")
				if direct then direct:Destroy() end
				for _, seg in ipairs(model:GetChildren()) do
					if seg:IsA("Model") then
						local part = seg:FindFirstChild("Unlock")
						if part then part:Destroy() end
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- Cost helper (reads Balance.UnlockCosts)
---------------------------------------------------------------------
local function getUnlockCost(unlockName: string): number
	local costs = Balance and Balance.UnlockCosts
	if type(costs) == "table" then
		local v = costs[unlockName]
		if typeof(v) == "number" then
			return v
		end
	end
	return 0
end

---------------------------------------------------------------------
-- Proximity Prompt setup (optional unlock UX)
---------------------------------------------------------------------
local function setupProximityPromptsForUnlock(unlockModel: Instance)
	local unlockPart = unlockModel:FindFirstChild("Unlock")
	if not unlockPart then return end

	local prompt = unlockPart:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "UnlockPrompt"
		local cost = getUnlockCost(unlockModel.Name)
		prompt.ActionText = (cost > 0) and ("Unlock ($%d)"):format(cost) or "Unlock"
		prompt.ObjectText = unlockModel.Name
		prompt.KeyboardKeyCode = Enum.KeyCode.F
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = math.max((unlockPart:IsA("BasePart") and unlockPart.Size.X or 8), 8)
		prompt.RequiresLineOfSight = false
		prompt.Parent = unlockPart
	end

	prompt.Triggered:Connect(function(player: Player)
		local nameToUnlock = unlockModel.Name
		local cost = getUnlockCost(nameToUnlock)
		if cost > 0 and not EconomyService.chargePlayer(player, cost) then
			return
		end
		-- grant locally; SaveManager persistence is separate
		local tbl = InMemoryUnlocks[player] or {}
		InMemoryUnlocks[player] = tbl
		if not tbl[nameToUnlock] then
			tbl[nameToUnlock] = true
			applyUnlocksToPlot(player, tbl)
			UnlocksUpdated:FireClient(player, tbl)
			UnlockChanged:Fire(player, nameToUnlock, true)
		end
	end)
end

local function ensurePromptsForPlot(player: Player)
	local plot = getPlayerPlot(player); if not plot then return end
	local unlocksFolder = plot:FindFirstChild("Unlocks"); if not unlocksFolder then return end
	for _, unlockModel in ipairs(unlocksFolder:GetChildren()) do
		if unlockModel:IsA("Model") then
			setupProximityPromptsForUnlock(unlockModel)
			for _, seg in ipairs(unlockModel:GetChildren()) do
				if seg:IsA("Model") then
					setupProximityPromptsForUnlock(seg)
				end
			end
		end
	end
end

-- Optional: first-time scan + future plots
local function setupPromptsForExistingPlots()
	local playerPlotsFolder = Workspace:FindFirstChild("PlayerPlots"); if not playerPlotsFolder then return end
	for _, plot in ipairs(playerPlotsFolder:GetChildren()) do
		if plot:IsA("Model") then
			local unlocksFolder = plot:FindFirstChild("Unlocks")
			if unlocksFolder then
				for _, unlockModel in ipairs(unlocksFolder:GetChildren()) do
					if unlockModel:IsA("Model") then
						setupProximityPromptsForUnlock(unlockModel)
						for _, seg in ipairs(unlockModel:GetChildren()) do
							if seg:IsA("Model") then
								setupProximityPromptsForUnlock(seg)
							end
						end
					end
				end
			end
		end
	end
end
setupPromptsForExistingPlots()
do
	local playerPlotsFolder = Workspace:FindFirstChild("PlayerPlots")
	if playerPlotsFolder then
		playerPlotsFolder.ChildAdded:Connect(function(plot)
			if plot:IsA("Model") then
				local unlocksFolder = plot:WaitForChild("Unlocks", 10)
				if unlocksFolder then
					for _, unlockModel in ipairs(unlocksFolder:GetChildren()) do
						if unlockModel:IsA("Model") then
							setupProximityPromptsForUnlock(unlockModel)
							for _, seg in ipairs(unlockModel:GetChildren()) do
								if seg:IsA("Model") then
									setupProximityPromptsForUnlock(seg)
								end
							end
						end
					end
				end
			end
		end)
	end
end

---------------------------------------------------------------------
-- RF/RE Handlers
---------------------------------------------------------------------
GetUnlocksForPlayer.OnInvoke = function(player: Player)
	return InMemoryUnlocks[player] or {}
end

RequestAllUnlocks.OnServerInvoke = function(player: Player)
	print("[Unlocks] RequestAllUnlocks from", player and player.Name)
	return InMemoryUnlocks[player] or {}
end

---------------------------------------------------------------------
-- Grant flow via RemoteEvent (menu)
---------------------------------------------------------------------
-- (Local table removed; now read from Balance.UnlockCosts exclusively.)

local function grantUnlock(player: Player, unlockName: string)
	if type(unlockName) ~= "string" or unlockName == "" then return end
	local tbl = InMemoryUnlocks[player]
	if not tbl then
		tbl = {}
		InMemoryUnlocks[player] = tbl
	end
	if tbl[unlockName] then return end -- idempotent

	tbl[unlockName] = true
	applyUnlocksToPlot(player, tbl)
	_pushUnlocksToClient(player)
	UnlockChanged:Fire(player, unlockName, true)
	if MAP_EXPANSION_UNLOCKS[unlockName] then
		_checkMapExpansionBadges(player)
	end
end

UnlockEvent.OnServerEvent:Connect(function(player: Player, unlockName: string)
	if type(unlockName) ~= "string" or unlockName == "" then return end
	local cost = getUnlockCost(unlockName)
	if cost > 0 and not EconomyService.chargePlayer(player, cost) then
		return -- insufficient funds
	end
	grantUnlock(player, unlockName)
end)

---------------------------------------------------------------------
-- Player lifecycle (in-memory only)
---------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	InMemoryUnlocks[player] = InMemoryUnlocks[player] or {} -- SaveManager will hydrate via SetUnlocksForPlayer
end)

-- Clear AFTER SaveManager persists
if PlayerSavedBE and PlayerSavedBE:IsA("BindableEvent") then
	PlayerSavedBE.Event:Connect(function(player: Player)
		InMemoryUnlocks[player] = nil
	end)
else
	game:BindToClose(function()
		InMemoryUnlocks = {}
	end)
end

-- When plot is assigned/spawned, re-apply table and ensure relock + prompts
if PlotAssignedBE and PlotAssignedBE:IsA("BindableEvent") then
	PlotAssignedBE.Event:Connect(function(player: Player, _plotModel: Instance)
		local t = InMemoryUnlocks[player] or {}
		syncUnlockTreeFromTemplate(player)
		relockFromTemplate(player, t)
		applyUnlocksToPlot(player, t)
		ensurePromptsForPlot(player)
	end)
end

---------------------------------------------------------------------
-- SaveManager hydrate / replace unlock table (slot load)
---------------------------------------------------------------------
SetUnlocksForPlayer.OnInvoke = function(player: Player, newTable: {[string]: boolean}?)
	-- Normalize to { [name]=true }
	local t: {[string]: boolean} = {}
	if type(newTable) == "table" then
		for k, v in pairs(newTable) do
			if v then t[k] = true end
		end
	end
	InMemoryUnlocks[player] = t

	-- IMPORTANT ORDER:
	syncUnlockTreeFromTemplate(player)
	relockFromTemplate(player, t)
	applyUnlocksToPlot(player, t)
	ensurePromptsForPlot(player)
	UnlocksUpdated:FireClient(player, t)
	_checkMapExpansionBadges(player)
	return true
end
