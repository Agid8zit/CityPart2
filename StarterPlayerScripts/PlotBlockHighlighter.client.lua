-- Locally hide the PlotBlock that matches the player's assigned plot.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local PLAYER_BLOCK_TRANSPARENCY = 1
local OTHER_BLOCK_TRANSPARENCY  = 1
local DEBUG = true

local events = ReplicatedStorage:WaitForChild("Events", 5)
local remoteEvents = events and events:FindFirstChild("RemoteEvents")
local getAssignedPlot = remoteEvents and remoteEvents:FindFirstChild("GetAssignedPlot")

-- Wait longer for streamed-in parts
local blockFolder = workspace:WaitForChild("BlockPlot", 30)
if not blockFolder then
	warn("[PlotBlockHighlighter] Workspace.BlockPlot missing.")
	return
end

local plotBlocks = {}

local function dprint(...)
	if DEBUG then
		print("[PlotBlockHighlighter]", ...)
	end
end

local function collectBlocks()
	local blocks = {}
	for _, child in ipairs(blockFolder:GetChildren()) do
		local idx = tonumber(child.Name:match("^PlotBlock(%d+)$"))
		if idx then
			local targetPart = child
			if child:IsA("Model") then
				targetPart = child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart")
			end
			if targetPart and targetPart:IsA("BasePart") then
				table.insert(blocks, { index = idx, part = targetPart })
			end
		end
	end
	return blocks
end

local function refreshBlocks()
	plotBlocks = collectBlocks()
	dprint(("Refreshed blocks, found %d PlotBlock parts."):format(#plotBlocks))
end

refreshBlocks()
if #plotBlocks == 0 then
	warn("[PlotBlockHighlighter] No PlotBlock parts found yet; waiting for stream.")
end

local function getPlotName()
	local attr = player:GetAttribute("PlotName")
	if attr then return attr end
	if getAssignedPlot then
		local ok, name = pcall(function()
			return getAssignedPlot:InvokeServer()
		end)
		if ok and typeof(name) == "string" and name ~= "" then
			return name
		end
	end
	return nil
end

local function getPlotModel(plotName: string?)
	if not plotName then return nil end
	local plotsFolder = workspace:FindFirstChild("PlayerPlots") or workspace:FindFirstChild("PlayerPlots", true)
	if not plotsFolder then return nil end
	return plotsFolder:FindFirstChild(plotName)
end

local function getPositionFromInstance(inst: Instance?)
	if not inst then return nil end
	if inst:IsA("BasePart") then
		return inst.Position
	end
	if inst:IsA("Model") then
		local pp = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
		return pp and pp.Position or inst:GetPivot().Position
	end
	return nil
end

local function updateTransparency()
	dprint("updateTransparency fired.")
	local plotName = getPlotName()
	dprint("PlotName attribute:", plotName)
	local plotModel = getPlotModel(plotName)
	if not plotModel then
		dprint("Plot model missing for name:", plotName)
	end
	local plotPos = getPositionFromInstance(plotModel)
	if not plotPos then
		dprint("Plot position unavailable.")
		return false
	end

	local bestIdx, bestDist
	for _, block in ipairs(plotBlocks) do
		local pos = getPositionFromInstance(block.part)
		if pos then
			local dist = (pos - plotPos).Magnitude
			dprint(("Block %s dist: %.2f"):format(tostring(block.index), dist))
			if not bestDist or dist < bestDist then
				bestDist = dist
				bestIdx = block.index
			end
		end
	end

	if not bestIdx then
		dprint("No bestIdx found.")
		return false
	end
	dprint("Best block index is", bestIdx, "distance", bestDist)

	for _, block in ipairs(plotBlocks) do
		local targetTransparency = (block.index == bestIdx) and PLAYER_BLOCK_TRANSPARENCY or OTHER_BLOCK_TRANSPARENCY
		block.part.LocalTransparencyModifier = targetTransparency
		block.part.Transparency = targetTransparency
		dprint(("Set PlotBlock%s transparency to %s"):format(block.index, targetTransparency))
	end

	return true
end

-- Initial attempt and retry a few times in case the plot or attributes arrive late.
task.spawn(function()
	for _ = 1, 20 do
		if updateTransparency() then
			break
		end
		task.wait(0.5)
	end
end)

player:GetAttributeChangedSignal("PlotName"):Connect(function()
	updateTransparency()
end)

-- Optional: respond to PlotAssigned event when server fires it.
if remoteEvents then
	local plotAssigned = remoteEvents:FindFirstChild("PlotAssigned")
	if plotAssigned and plotAssigned:IsA("RemoteEvent") then
		plotAssigned.OnClientEvent:Connect(function()
			updateTransparency()
		end)
	end
end

-- Rebuild block list if the folder streams in new children
blockFolder.ChildAdded:Connect(function()
	refreshBlocks()
	updateTransparency()
end)
blockFolder.ChildRemoved:Connect(function()
	refreshBlocks()
	updateTransparency()
end)

-- Retry after character spawns/world reload
player.CharacterAdded:Connect(function()
	task.defer(function()
		for _ = 1, 10 do
			if updateTransparency() then break end
			task.wait(0.5)
		end
	end)
end)

-- Retry when plots stream in (handle late creation)
task.spawn(function()
	local playerPlots = workspace:WaitForChild("PlayerPlots", 30)
	if not playerPlots then return end
	playerPlots.ChildAdded:Connect(function()
		updateTransparency()
	end)
	playerPlots.ChildRemoved:Connect(function()
		updateTransparency()
	end)
	-- in case plots were already present when we attached
	updateTransparency()
end)
