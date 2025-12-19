-- Server-side region visibility dispatcher.
-- Computes which plots overlap each tagged region volume and notifies clients.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local REGION_TAGS = { "Region_12", "Region_34", "Region_56", "Region_78" }

local EventsFolder = ReplicatedStorage:WaitForChild("Events")
local RemoteEvents = EventsFolder:WaitForChild("RemoteEvents")
local RegionVisUpdate = RemoteEvents:FindFirstChild("RegionVisUpdate")
if not RegionVisUpdate then
	RegionVisUpdate = Instance.new("RemoteEvent")
	RegionVisUpdate.Name = "RegionVisUpdate"
	RegionVisUpdate.Parent = RemoteEvents
end

local function getAABB(model)
	local cf, size = model:GetBoundingBox()
	return cf, size
end

local function aabbIntersects(cfA, sizeA, cfB, sizeB)
	local halfA = sizeA * 0.5
	local halfB = sizeB * 0.5
	local posA = cfA.Position
	local posB = cfB.Position
	return math.abs(posA.X - posB.X) <= (halfA.X + halfB.X)
		and math.abs(posA.Y - posB.Y) <= (halfA.Y + halfB.Y)
		and math.abs(posA.Z - posB.Z) <= (halfA.Z + halfB.Z)
end

local function computeRegionMapping()
	local mapping = {}
	local volumesByTag = {}
	for _, tag in ipairs(REGION_TAGS) do
		local vols = {}
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do
			if inst:IsA("BasePart") then
				table.insert(vols, inst)
			end
		end
		volumesByTag[tag] = vols
	end

	local plotsFolder = Workspace:FindFirstChild("PlayerPlots")
	if not plotsFolder then
		return mapping
	end

	local plots = {}
	for _, p in ipairs(plotsFolder:GetChildren()) do
		if p:IsA("Model") and p.Name:match("^Plot_") then
			table.insert(plots, p)
		end
	end

	local plotAABBs = {}
	for _, p in ipairs(plots) do
		plotAABBs[p] = { getAABB(p) }
	end

	for _, tag in ipairs(REGION_TAGS) do
		mapping[tag] = {}
		for _, vol in ipairs(volumesByTag[tag]) do
			local vCF, vSize = vol.CFrame, vol.Size
			for _, p in ipairs(plots) do
				local pCF, pSize = table.unpack(plotAABBs[p])
				if aabbIntersects(vCF, vSize, pCF, pSize) then
					table.insert(mapping[tag], p.Name)
				end
			end
		end
	end

	return mapping
end

local function sendMappingTo(player)
	local mapping = computeRegionMapping()
	RegionVisUpdate:FireClient(player, mapping)
end

Players.PlayerAdded:Connect(function(plr)
	-- allow PlotAssigner to create the plot
	task.delay(1, function()
		if plr and plr.Parent then
			sendMappingTo(plr)
		end
	end)
end)

-- Recompute when a player leaves (plots removed) and broadcast to all.
Players.PlayerRemoving:Connect(function(_plr)
	task.defer(function()
		local mapping = computeRegionMapping()
		for _, p in ipairs(Players:GetPlayers()) do
			RegionVisUpdate:FireClient(p, mapping)
		end
	end)
end)
