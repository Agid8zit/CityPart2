local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Client-side bobbing for alarm parts. Server now only tags BobBase.
local BOB_SPEED = 2            -- radians/sec
local BOB_AMPLITUDE = 0.5      -- studs
local CLUSTER_FLAG_ATTR = "ClusteredAlarm"
local CLUSTER_GUI_MULT   = 1.35 -- keep in sync with server ALARM_CLUSTER_SIZE_MULT

local tracked = {} :: {[BasePart]: { base: Vector3, phase: number }}
local heartbeatConn: RBXScriptConnection? = nil
local clusterConns: {[BasePart]: RBXScriptConnection} = {}

local function stopHeartbeatIfIdle()
	if heartbeatConn and next(tracked) == nil then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
end

local function detach(part: BasePart?)
	if part then
		tracked[part] = nil
	end
	stopHeartbeatIfIdle()
	if clusterConns[part] then
		clusterConns[part]:Disconnect()
		clusterConns[part] = nil
	end
end

local function applyClusterVisuals(part: BasePart)
	local isCluster = part:GetAttribute(CLUSTER_FLAG_ATTR) == true

	local function scaleGui(gui: BillboardGui)
		local base = gui:GetAttribute("BaseSize")
		if typeof(base) ~= "UDim2" then
			base = gui.Size
			gui:SetAttribute("BaseSize", base)
		end
		if typeof(base) == "UDim2" then
			local mult = isCluster and CLUSTER_GUI_MULT or 1
			gui.Size = UDim2.new(
				base.X.Scale * mult,
				base.X.Offset * mult,
				base.Y.Scale * mult,
				base.Y.Offset * mult
			)
		end
	end

	for _, gui in ipairs(part:GetDescendants()) do
		if gui:IsA("BillboardGui") then
			scaleGui(gui)
		end
	end
end

local function ensureHeartbeat()
	if heartbeatConn then return end
	heartbeatConn = RunService.RenderStepped:Connect(function()
		local tnow = os.clock()
		for part, info in pairs(tracked) do
			if not part or not part.Parent then
				tracked[part] = nil
			else
				local dy = math.sin(tnow * BOB_SPEED + info.phase) * BOB_AMPLITUDE
				part.Position = info.base + Vector3.new(0, dy, 0)
			end
		end
		stopHeartbeatIfIdle()
	end)
end

local function attach(part: BasePart)
	if tracked[part] then return end
	local base = part:GetAttribute("BobBase")
	if typeof(base) ~= "Vector3" then
		base = part.Position
	end
	tracked[part] = {
		base = base,
		phase = math.random() * math.pi * 2,
	}
	applyClusterVisuals(part)
	clusterConns[part] = part:GetAttributeChangedSignal(CLUSTER_FLAG_ATTR):Connect(function()
		applyClusterVisuals(part)
	end)
	part.AncestryChanged:Connect(function(_, parent)
		if not parent then
			detach(part)
		end
	end)
	ensureHeartbeat()
end

local function consider(inst: Instance)
	if not inst:IsA("BasePart") then return end
	if inst.Name:match("^Alarm") or typeof(inst:GetAttribute("BobBase")) == "Vector3" then
		attach(inst)
	end
end

for _, inst in ipairs(Workspace:GetDescendants()) do
	consider(inst)
end
Workspace.DescendantAdded:Connect(consider)
