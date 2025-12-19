-- Client-side region visibility toggler driven by server-provided mapping.
-- Server fires RemoteEvent "RegionVisUpdate" with mapping { [regionTag] = { "Plot_<uid>", ... } }.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local LOCAL_PLAYER = Players.LocalPlayer
local SCAN_INTERVAL = 0.25

local EventsFolder = ReplicatedStorage:WaitForChild("Events")
local RemoteEvents = EventsFolder:WaitForChild("RemoteEvents")
local RegionVisUpdate = RemoteEvents:WaitForChild("RegionVisUpdate")

local regionVolumes = {}
local regionContent = {}
local activeTag = nil
local lastCheck = 0

local function gatherVolumes(tag)
	local vols = {}
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		if inst:IsA("BasePart") then
			table.insert(vols, inst)
		end
	end
	return vols
end

local function gatherPlotParts(plot)
	local parts = {}
	local pop = plot:FindFirstChild("Buildings")
	pop = pop and pop:FindFirstChild("Populated")
	if not pop then return parts end
	for _, inst in ipairs(pop:GetDescendants()) do
		if inst:IsA("BasePart") then
			table.insert(parts, inst)
		end
	end
	return parts
end

local function setPartsVisible(parts, visible)
	for _, part in ipairs(parts) do
		part.LocalTransparencyModifier = visible and 0 or 1
	end
end

local function hideAllRegions(exceptTag)
	for tag, parts in pairs(regionContent) do
		if tag ~= exceptTag and tag ~= "_fallback" then
			setPartsVisible(parts, false)
		end
	end
end

local function rebuildCaches(mapping)
	regionVolumes = {}
	regionContent = {}

	local plotsFolder = Workspace:FindFirstChild("PlayerPlots")
	if not plotsFolder then
		return
	end

	for tag, plotNames in pairs(mapping) do
		regionVolumes[tag] = gatherVolumes(tag)
		local parts = {}
		for _, plotName in ipairs(plotNames) do
			local plot = plotsFolder:FindFirstChild(plotName)
			if plot and plot:IsA("Model") then
				for _, part in ipairs(gatherPlotParts(plot)) do
					table.insert(parts, part)
				end
			end
		end
		regionContent[tag] = parts
	end

	-- fallback to own plot if present
	local ownPlot = plotsFolder:FindFirstChild("Plot_" .. LOCAL_PLAYER.UserId)
	if ownPlot then
		regionContent._fallback = gatherPlotParts(ownPlot)
	end

	hideAllRegions(nil)
	if regionContent._fallback then
		setPartsVisible(regionContent._fallback, false)
	end
	activeTag = nil
end

RegionVisUpdate.OnClientEvent:Connect(rebuildCaches)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now - lastCheck < SCAN_INTERVAL then return end
	lastCheck = now

	local hrp = LOCAL_PLAYER.Character and LOCAL_PLAYER.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { hrp }

	local newTag = nil
	for tag, vols in pairs(regionVolumes) do
		for _, vol in ipairs(vols) do
			if vol.Parent and vol:IsDescendantOf(Workspace) then
				local touching = Workspace:GetPartsInPart(vol, overlapParams)
				if touching and #touching > 0 then
					newTag = tag
					break
				end
			end
		end
		if newTag then break end
	end

	if newTag == activeTag then
		return
	end

	if newTag and regionContent[newTag] then
		hideAllRegions(newTag)
		setPartsVisible(regionContent[newTag], true)
		if regionContent._fallback then setPartsVisible(regionContent._fallback, false) end
	else
		hideAllRegions(nil)
		if regionContent._fallback then setPartsVisible(regionContent._fallback, true) end
	end

	activeTag = newTag
end)
