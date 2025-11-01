local Utility = {}

-- Roblox Services
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

-- Defines
local RNG = Random.new()

-- Module Functions
function Utility.CalculateShopSeed(): number
	local UTC_Seconds = os.time() -- Seconds
	local UTC_Minutes = (UTC_Seconds / 60) -- Minutes
	local UTC_Hours = (UTC_Minutes / 60) -- Hours
	local ShopClockHash = math.floor(UTC_Hours / 8) -- every 8 hours
	return ShopClockHash
end

function Utility.CalculateShopChangeTimeLeft(): number
	local UTC_Seconds = os.time() -- Seconds
	local UTC_Minutes = (UTC_Seconds / 60) -- Minutes
	local UTC_Hours = (UTC_Minutes / 60) -- Hours
	local ShopClockHash = (UTC_Hours / 8)
	--local ShopClockHash_CurrentSeconds = math.floor(ShopClockHash) * 8 * 60 * 60
	local ShopClockHash_NextSeconds = math.ceil(ShopClockHash) * 8 * 60 * 60
	return ShopClockHash_NextSeconds - os.time()
end

function Utility.StringToHashNumber(String: string)
	local h = 5381;
	for Index = 1, string.len(String) do
		local c = string.sub(String, Index, Index)
		h = (bit32.lshift(h, 5) + h) + string.byte(c)
	end
	return h
end
--- Bounded between [0, 2^32)
--function Hash.HashString(str: string): number
--	local hash = 0x811c9dc5

--	for i = 1, #str do
--		hash = bit32.bxor(hash, string.byte(str, i))
--		hash = (hash * 0x01000193) % 2^32
--	end

--	return hash
--end

function Utility.IntegerToColor3(int)
	return Color3.fromRGB(
		math.floor(int/256^2)%256,
		math.floor(int/256)%256,
		math.floor(int)%256
	)
end

function Utility.Color3ToInteger(Color: Color3)
	return math.floor(Color.R * 255) * 256^2 + math.floor(Color.G * 255) * 256 + math.floor(Color.B * 255)
end

function Utility.PutBooleansIntoBit32(BooleanArray)
	assert(#BooleanArray > 0 and #BooleanArray <= 12, "BooleanArray, is not 12 or less array elements")
	local Bit32Value = 0
	for Index, Value in BooleanArray do
		if Value then
			Bit32Value += math.pow(2, (Index - 1))
		end
	end
	return Bit32Value
end

function Utility.Bit32ToBooleanArray(Bit32Value)
	local BooleanArray = {}
	for i = 1, 32 do
		if (bit32.rshift(Bit32Value, (i - 1)) % 2) == 1 then
			table.insert(BooleanArray, true)
		else
			table.insert(BooleanArray, false)
		end
	end
	return BooleanArray
end

function Utility.DoTablesMatch(o1, o2)
	if o1 == o2 then return true end
	local o1Type = type(o1)
	local o2Type = type(o2)
	if o1Type ~= o2Type then return false end
	if o1Type ~= 'table' then return false end

	local keySet = {}

	for key1, value1 in pairs(o1) do
		local value2 = o2[key1]
		if value2 == nil or Utility.DoTablesMatch(value1, value2) == false then
			return false
		end
		keySet[key1] = true
	end

	for key2, _ in pairs(o2) do
		if not keySet[key2] then return false end
	end
	return true
end

function Utility.GetDescendantsCount_ReplicatedSafe(Model)
	local Count = 0
	for _, Object in Model:GetDescendants() do
		if Object:IsA("TouchTransmitter") then continue end
		if Object:HasTag("SafeWorkspaceLoopedAudio") then continue end
		Count += 1
	end
	return Count
end

function Utility.CustomTaggedAtomicWait(Model: Model): boolean
	-- Wait a bit in case the tag takes a second to appear
	local WaitForTag = os.clock() + 2
	while Model:HasTag("AtomicModel") == nil and os.clock() < WaitForTag do
		task.wait()
		--print(Model:HasTag("AtomicModel") == nil, os.clock() < WaitForTag)
	end

	-- If available read the descendant count and compare
	if Model:HasTag("AtomicModel") then
		local AtomicCount = Model:GetAttribute("_AtomicCount")
		local Timeout = os.clock() + 5
		while AtomicCount == nil or AtomicCount ~= Utility.GetDescendantsCount_ReplicatedSafe(Model) do
			--print(Model.Name, AtomicCount, '/', GetDescendantsCount(Model))
			task.wait()
			-- if took too long, just abort
			if os.clock() > Timeout then return false end
			-- if missing
			if not Model.Parent then return false end
		end
		return true

		-- no atomic tag, something has gone wrong
	else
		warn("failed: ", Model.Name, Model.Parent and Model.Parent.Name or "no parent")
		return false
	end
end

function Utility.MergeTables(SrcTable, DestTable)
	local Mixed = DestTable
	if Mixed == nil then
		return SrcTable
	end
	for Key, Value in SrcTable do
		if typeof(Value) == "table" then
			local ChildMixed = Utility.MergeTables(SrcTable[Key], DestTable[Key])
			Mixed[Key] = ChildMixed
		else
			Mixed[Key] = Value
		end
	end
	return Mixed
end

function Utility.PrettyPrintTable(RawTable)
	-- Pack Contents
	--for Key, Value in table.pack(...) do
	--	if Key == "n" then continue end

	--end

	-- Normal Print if Studio
	if RunService:IsStudio() then
		print(RawTable)
		return
	end

	local function PrettyPrint(Table, Depth)
		local Prefix = ""
		for i = 1, Depth * 4 do
			Prefix ..= " "
		end

		if type(Table) == 'table' then
			local s = '{\n'
			for k, v in (Table) do
				if type(k) ~= 'number' then k = '"'..k..'"' end
				s = s .. Prefix.. '['..k..'] = ' .. PrettyPrint(v, Depth + 1) .. ',\n'
			end
			return s .. string.sub(Prefix, 1, string.len(Prefix) - 4).. '}'
		else
			return tostring(Table)
		end
	end
	print(PrettyPrint(RawTable, 0))
end

function Utility.RoundNumberToDecimal(Number: number, Decimals: number)
	local Modifier = math.pow(10, Decimals)
	return math.round(Number * Modifier) / Modifier
end

function Utility.WaitForPrimaryPart(Model: Model, Timeout: number)
	local TimeoutEnd = os.clock() + Timeout
	while not Model.PrimaryPart do
		task.wait()
		if os.clock() > TimeoutEnd then return false end
	end

	return true
end

function Utility.CalculateAssemblyFromCFrameChange(Step: number, CFrame1: CFrame, CFrame2: CFrame, ApplyPart: BasePart)

	local PosDelta = CFrame2.Position - CFrame1.Position
	local RotDelta = CFrame2.Rotation * CFrame1.Rotation:Inverse()
	local EulerX, EulerY, EulerZ = RotDelta:ToEulerAngles()

	ApplyPart.AssemblyLinearVelocity = PosDelta / Step
	ApplyPart.AssemblyAngularVelocity = Vector3.new(EulerX, EulerY, EulerZ) / Step

end

function Utility.GetPartBoundingBoxMinX(Part: BasePart)
	return Part.Position.X
	- (math.abs(Part.CFrame.XVector.X) * Part.Size.X / 2)
	- (math.abs(Part.CFrame.YVector.X) * Part.Size.Y / 2)
	- (math.abs(Part.CFrame.ZVector.X) * Part.Size.Z / 2)
end

function Utility.GetPartBoundingBoxMaxX(Part: BasePart)
	return Part.Position.X
		+ (math.abs(Part.CFrame.XVector.X) * Part.Size.X / 2)
		+ (math.abs(Part.CFrame.YVector.X) * Part.Size.Y / 2)
		+ (math.abs(Part.CFrame.ZVector.X) * Part.Size.Z / 2)
end

function Utility.Get2DVecLocalSpace_DownIsOrigin(VecNormal: Vector2, VecToBecomeLocalSpace: Vector2)

	local AngleFromDown = Vector2.new(0, -1):Angle(VecNormal, true)

	return Vector2.new(
		VecToBecomeLocalSpace.X * math.cos(-AngleFromDown) - VecToBecomeLocalSpace.Y * math.sin(-AngleFromDown),
		VecToBecomeLocalSpace.X * math.sin(-AngleFromDown) + VecToBecomeLocalSpace.Y * math.cos(-AngleFromDown)	
	)
end

-- Base64 encoding/decoding
-- https://devforum.roblox.com/t/base64-encoding-and-decoding-in-lua/1719860

-- this function converts a string to base64
function Utility.to_base64(data)
	local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
	return ((data:gsub('.', function(x) 
		local r,b='',x:byte()
		for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
		return r;
	end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
		if (#x < 6) then return '' end
		local c=0
		for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
		return b:sub(c+1,c+1)
	end)..({ '', '==', '=' })[#data%3+1])
end

-- this function converts base64 to string
function Utility.from_base64(data)
	local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
	data = string.gsub(data, '[^'..b..'=]', '')
	return (data:gsub('.', function(x)
		if (x == '=') then return '' end
		local r,f='',(b:find(x)-1)
		for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
		return r;
	end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
		if (#x ~= 8) then return '' end
		local c=0
		for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
		return string.char(c)
	end))
end

function Utility.SetNetworkOwnershipAuto_Safe(Part)
	if Part.Anchored then return end
	local Objects = Part:GetConnectedParts(true)
	for _, Object in Objects do
		if Object.Anchored then return end
	end
	Part:SetNetworkOwnershipAuto()
end

function Utility.CloneTable(Src)
	if typeof(Src) ~= "table" then
		return Src
	end

	local Dest = {}
	for Key, Value in pairs(Src) do
		Dest[Key] = Utility.CloneTable(Value)
	end
	return Dest
end

local Temp = Instance.new("Part")
Temp.CastShadow = false
Temp.CanCollide = false
Temp.CanQuery = false
Temp.CanTouch = false
Temp.Anchored = true
Temp.Size = Vector3.zero
Temp.Massless = true
Temp.Transparency = 1

-- Destroys a model in a way that is visually pleasing (waits for emitters/trails/effects to end)
function Utility.DestroyModelVisually(Model: Model, MinimumLifetime: number?)
	task.spawn(function()
		local Lifetime = MinimumLifetime or 0
		local Lights = {}
		local Beams = {}
		for _, Child in Model:GetDescendants() do
			if Child:IsA("BasePart") then
				Child.Transparency = 1
			elseif Child:IsA("ParticleEmitter") then
				Child.Enabled = false
				Lifetime = math.max(Child.Lifetime.Max, Lifetime)
			elseif Child:IsA("Trail") then
				Lifetime = math.max(Child.Lifetime, Lifetime)
			elseif Child:IsA("Light") then
				table.insert(Lights, Child)
			elseif Child:IsA("Beam") then
				table.insert(Beams, Child)
			elseif Child:IsA("Decal") or Child:IsA("Texture") then
				TweenService:Create(Child, TweenInfo.new(0.25), {
					Transparency = 1.0
				}):Play()
			elseif Child:IsA("Sound") then
				local SoundTemp = Temp:Clone()
				SoundTemp.Position = Child.Parent.Position
				SoundTemp.Parent = workspace._Misc
				Child.Parent = SoundTemp
				TweenService:Create(Child, TweenInfo.new(0.5), {
					Volume = 0
				}):Play()
				task.delay(0.5, SoundTemp.Destroy, SoundTemp)
			end
		end
		for _, Light in Lights do
			TweenService:Create(Light, TweenInfo.new(Lifetime), {
				Brightness = 0
			}):Play()
		end
		for _, Beam in Beams do
			TweenService:Create(Beam, TweenInfo.new(Lifetime), {
				Width0 = 0,
				Width1 = 0,
			}):Play()
		end

		task.delay(Lifetime, Model.Destroy, Model)
	end)
end

function Utility.IsPointInSafeZone(Position: Vector3, ScaleZone: Vector3?)
	for _, Zone in workspace._SafeZones:GetChildren() do
		if Utility.IsPointInPart(Position, Zone, ScaleZone or Vector3.zero) then
			return true
		end
	end
	return false
end

function Utility.PickRandomOptionFromWeightTable(WeightTable: {}, PreCalculatedTotalWeight: number?, Seed: number)
	local RNG_Local = Random.new(Seed)

	-- Get total weight
	local TotalWeight = 0
	if PreCalculatedTotalWeight then
		TotalWeight = PreCalculatedTotalWeight
	else
		for Name, Weight in WeightTable do
			TotalWeight += Weight
		end
	end

	-- select a random weight
	local SelectedWeight = RNG_Local:NextInteger(0, TotalWeight)

	-- if selected weight is <=, choose it, otherwise, reduce selected weight
	for Name, Weight in WeightTable do
		if SelectedWeight <= Weight then
			return Name
		end
		SelectedWeight -= Weight
	end
	warn(WeightTable)
	error("WeightTable Catastrophic Failure")
end

function Utility.HasAtLeastNKeys(Table, KeyAmount: number)
	local Count = 0
	for _ in Table do
		Count += 1
		if Count == KeyAmount then return true end
	end
	return false
end

function Utility.AddValues(Table)
	local TotalValue = 0
	for _, Value in Table do
		TotalValue += Value
	end
	return TotalValue
end

function Utility.GetClosestNodeFromASet(NodeSet: {}, Position: Vector3)
	local ClosestNode = nil
	local ClosestDistance = math.huge
	for Node in NodeSet do
		assert(Node:IsA("BasePart"), "Node must be a basepart")
		local Distance = (Position - Node.Position)
		Distance = Distance:Dot(Distance)
		if Distance < ClosestDistance then
			ClosestDistance = Distance
			ClosestNode = Node
		end
	end
	return ClosestNode
end

function Utility.GetRandomKeyFromTable(Table)
	local Array = {}
	for Key in Table do
		table.insert(Array, Key)
	end
	return Array[RNG:NextInteger(1, #Array)]
end

function Utility.CountKeys(Table)
	local Count = 0
	for _ in Table do
		Count += 1
	end
	return Count
end

function Utility.GetAllHierarchyPaths(Path: string)
	local Sections = string.split(Path, '/')
	if #Sections > 1 then
		local Paths = {}
		local BroaderPath = ""
		for Index, Section in Sections do
			if Index ~= 1 then BroaderPath ..= "/" end
			BroaderPath ..= Section
			table.insert(Paths, BroaderPath)
		end
		return Paths
	else
		return { Path }
	end
end

function Utility.GetValueFromPath(Table, Path, Yield: boolean?)
	local Keys = string.split(Path, '/')
	local Pointer = Table
	local LastKey = Keys[#Keys]
	for Index, Key in Keys do
		if Index == #Keys then continue end
		if Yield then
			Pointer = Pointer:WaitForChild(Key)
		else
			Pointer = Pointer[Key]
		end
	end
	assert(Pointer ~= nil, "Failed to Modify Path ("..Path..") for Table")
	if Yield then
		return Pointer:WaitForChild(LastKey)
	else
		return Pointer[LastKey]
	end
end

function Utility.ModifyTableByPath(Table, Path, Value)
	assert(Path, "Path is missing for ModifyTableByPath")

	local Keys = string.split(Path, '/')
	local Pointer = Table
	local LastKey = Keys[#Keys]
	for Index, Key in Keys do
		if Index == #Keys then continue end
		Pointer = Pointer[Key]
	end
	assert(Pointer ~= nil, "Failed to Modify Path ("..Path..") for Table")
	Pointer[LastKey] = Value
end

function Utility.TweenOneAfterAnother(...)
	local tweens = {...}
	for index, tween in tweens do
		if index == #tweens then continue end

		tween.Completed(function()
			tweens[index + 1]:Play()
		end)
	end
	tweens[1]:Play()
end

local LocalAnimations = {} -- [KeyframeSequence] = true
function Utility.LoadLocalAnimation(KeyframeSequence: KeyframeSequence) : Animation?
	if not RunService:IsStudio() then
		warn("Attempting to load LocalAnimation (" .. KeyframeSequence.Name .. ") in a Live Game")
		return nil
	end

	if LocalAnimations[KeyframeSequence] then
		return LocalAnimations[KeyframeSequence]
	end

	warn("[!] Loading Local Animation: " .. KeyframeSequence.Name)
	local HashID = KeyframeSequenceProvider:RegisterKeyframeSequence(KeyframeSequence)
	if HashID then
		local LocalAnimation = Instance.new("Animation")
		LocalAnimation.Name = KeyframeSequence.Name
		LocalAnimation.AnimationId = HashID
		LocalAnimations[KeyframeSequence] = LocalAnimation
		return LocalAnimation
	else
		return nil
	end
end

function Utility.LoadAnimationSafe(Animator: Animator, AnimationOrKeyframes: Animation | KeyframeSequence) : AnimationTrack?
	-- Check if Local
	if AnimationOrKeyframes:IsA("KeyframeSequence") then
		local Animation = Utility.LoadLocalAnimation(AnimationOrKeyframes)
		if not Animation then return end
		local Success, Result = pcall(function()
			return Animator:LoadAnimation(Animation)
		end) 
		if Success then
			return Result
		else
			error(Result)
		end

		-- Normal Animation
	elseif AnimationOrKeyframes:IsA("Animation") then
		local Success, Result = pcall(function()
			return Animator:LoadAnimation(AnimationOrKeyframes)
		end) 
		if Success then
			return Result
		else
			error(Result)
		end

	else
		error("Invalid Instance Type (" .. AnimationOrKeyframes.ClassName .. ") for Loading Animation: " .. AnimationOrKeyframes.Name)
	end
end

function Utility.RemoveTrailingZeroesOfDecimalString(StringNumber: string)
	if string.find(StringNumber, '.', 1, true) then
		return StringNumber:gsub("%.?0+$", "")
	else
		return StringNumber
	end
end

-- 1000 = 1k, 15000 = 1.5k, etc..
local Abbreviations = {
	"K", -- 4 digits
	"M", -- 7 digits
	"B", -- 10 digits
	"T", -- 13 digits
	"QD", -- 16 digits
	"QT", -- 19 digits
	"SXT", -- 22 digits
	"SEPT", -- 25 digits
	"OCT", -- 28 digits
	"NON", -- 31 digits
	"DEC", -- 34 digits
	"UDEC", -- 37 digits
	"DDEC", -- 40 digits
	"???", -- too many
}
function Utility.AbbreviateLargeNumber(Number: number, Decimals: number?)
	-- Sanity
	if not Number then return nil end

	local FinalDecimals = Decimals or 0
	local Visible = nil
	local Suffix = nil
	if Number < 1000 then
		Visible = Number * math.pow(10, FinalDecimals)
		Suffix = ""
	else
		local Digits = math.floor(math.log10(Number)) + 1
		local Index = math.min(#Abbreviations, math.floor((Digits - 1) / 3))
		Visible = Number / math.pow(10, Index * 3 - FinalDecimals)
		Suffix = Abbreviations[Index] --.. "+"
	end
	local Front = Visible / math.pow(10, FinalDecimals)
	local Back = Visible % math.pow(10, FinalDecimals)

	if FinalDecimals > 0 then
		local Raw = string.format("%i.%0." .. tostring(FinalDecimals) .. "i", Front, Back)
		return Utility.RemoveTrailingZeroesOfDecimalString(Raw)..Suffix
	else
		return string.format("%i%s", Front, Suffix)
	end
end

function Utility.AtomicPathWait(Parent: Instance, PathTable: {}, Timeout: number?): boolean
	-- Default
	Timeout = Timeout or 5

	local function CheckPath(SetParent: Instance, SetTable: {}): boolean
		for Key, Value in SetTable do
			local Child = SetParent:WaitForChild(Key, Timeout)
			if not Child then warn("Could not find ("..Key.."") return false end
			if typeof(Value) == "table" then
				return CheckPath(Child, Value) 
			end
		end
		return true
	end
	return CheckPath(Parent, PathTable)
end

function Utility.TagToAddRemoveFunctions(TagName: string, AddFunc: (any) -> (), RemoveFunc: (any) -> ()?)
	-- Listeners
	CollectionService:GetInstanceAddedSignal(TagName):Connect(AddFunc)
	if RemoveFunc then
		CollectionService:GetInstanceRemovedSignal(TagName):Connect(RemoveFunc)
	end

	-- Directly add existing ones
	for _, Part in CollectionService:GetTagged(TagName) do
		task.spawn(function()
			AddFunc(Part)
		end)
	end
end

function Utility.CreateArrayFromSet(SetTable)
	local Array = {}
	for Key in SetTable do
		table.insert(Array, Key)
	end
	return Array
end

function Utility.GetOBBExtents(cframe: CFrame, size: Vector3) : (Vector3, Vector3)
	local abs = math.abs

	local sx, sy, sz = size.X, size.Y, size.Z -- this causes 3 Lua->C++ invocations

	local x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22 = cframe:GetComponents() -- this causes 1 Lua->C++ invocations and gets all components of cframe in one go, with no allocations

	-- https://zeuxcg.org/2010/10/17/aabb-from-obb-with-component-wise-abs/
	local wsx = 0.5 * (abs(R00) * sx + abs(R01) * sy + abs(R02) * sz) -- this requires 3 Lua->C++ invocations to call abs, but no hash lookups since we cached abs value above; otherwise this is just a bunch of local ops
	local wsy = 0.5 * (abs(R10) * sx + abs(R11) * sy + abs(R12) * sz) -- same
	local wsz = 0.5 * (abs(R20) * sx + abs(R21) * sy + abs(R22) * sz) -- same

	-- just a bunch of local ops
	local minx = x - wsx
	local miny = y - wsy
	local minz = z - wsz

	local maxx = x + wsx
	local maxy = y + wsy
	local maxz = z + wsz

	-- return min, max
	return Vector3.new(minx, miny, minz), Vector3.new(maxx, maxy, maxz)
end

function Utility.GetPartExtents(part: Part)
	return Utility.GetOBBExtents(part.CFrame, part.Size)
end

function Utility.SetCFramePosY(SetCFrame, NewY)
	local P = Vector3.new(SetCFrame.Position.X, NewY, SetCFrame.Position.Z)
	return SetCFrame.Rotation + P
end

function Utility.ShuffleArray(TableObject: {any}): {any}
	for i = #TableObject, 2, -1 do
		local j = math.random(i)
		TableObject[i], TableObject[j] = TableObject[j], TableObject[i]
	end
	return TableObject
end

function Utility.Motor6DInPlace(Src: BasePart, Dest: BasePart): Weld
	local Weld = Instance.new("Motor6D")
	Weld.C0 = Src.CFrame:ToObjectSpace(Dest.CFrame)
	Weld.Part0 = Src
	Weld.Part1 = Dest
	Weld.Name = Dest.Name
	Weld.Parent = Src
	return Weld
end

function Utility.WeldInPlace(Src: BasePart, Dest: BasePart): Weld
	local Weld = Instance.new("Weld")
	Weld.C0 = Src.CFrame:ToObjectSpace(Dest.CFrame)
	Weld.Part0 = Src
	Weld.Part1 = Dest
	Weld.Name = Dest.Name
	Weld.Parent = Src
	return Weld
end

function Utility.WeldModelTogether(Model: Model)
	assert(Model.PrimaryPart ~= nil, "Model is missing PrimaryPart!")
	for _, Part in Model:GetDescendants() do
		if Part == Model.PrimaryPart then continue end
		if Part:IsA("BasePart") then
			Utility.WeldInPlace(Model.PrimaryPart, Part)
		end
	end
end

function Utility.WeldModelTogether_IgnoreExistingWelds(Model: Model)
	assert(Model.PrimaryPart ~= nil, "Model is missing PrimaryPart!")

	local IgnoreParts = {} -- Set<Part>
	--local Parts = {} -- Set<Part>
	for _, Part in Model:GetDescendants() do
		if Part:IsA("Weld") or Part:IsA("Motor6D") then
			if Part.Part0 == Model.PrimaryPart then
				IgnoreParts[Part.Part1] = true
			elseif Part.Part1 == Model.PrimaryPart then
				IgnoreParts[Part.Part0] = true
			end
		end
	end
	for _, Child in Model:GetChildren() do
		if IgnoreParts[Child] then continue end
		if Child == Model.PrimaryPart then continue end
		if Child:IsA("Model") then
			assert(Child.PrimaryPart, "Missing PrimaryPart for Child Model of ("..Model.Name..")")
			for _, SubChild in Child:GetChildren() do
				if IgnoreParts[SubChild] then continue end
				if SubChild == Child.PrimaryPart then
					Utility.WeldInPlace(Child.PrimaryPart, Model.PrimaryPart)
				else
					Utility.WeldInPlace(Child.PrimaryPart, SubChild)
				end
			end

		elseif Child:IsA("BasePart") then
			Utility.WeldInPlace(Model.PrimaryPart, Child)
		end
	end
end

function Utility.EvaluateColorSequence(sequence: ColorSequence, time: number)
	-- If time is 0 or 1, return the first or last value respectively
	if time == 0 then
		return sequence.Keypoints[1].Value
	elseif time == 1 then
		return sequence.Keypoints[#sequence.Keypoints].Value
	end

	-- Otherwise, step through each sequential pair of keypoints
	for i = 1, #sequence.Keypoints - 1 do
		local thisKeypoint = sequence.Keypoints[i]
		local nextKeypoint = sequence.Keypoints[i + 1]
		if time >= thisKeypoint.Time and time < nextKeypoint.Time then
			-- Calculate how far alpha lies between the points
			local alpha = (time - thisKeypoint.Time) / (nextKeypoint.Time - thisKeypoint.Time)
			-- Evaluate the real value between the points using alpha
			return Color3.new(
				(nextKeypoint.Value.R - thisKeypoint.Value.R) * alpha + thisKeypoint.Value.R,
				(nextKeypoint.Value.G - thisKeypoint.Value.G) * alpha + thisKeypoint.Value.G,
				(nextKeypoint.Value.B - thisKeypoint.Value.B) * alpha + thisKeypoint.Value.B
			)
		end
	end
end

--function Utility.EvaluateCFrameSequence(CFrameSequence, Time: number, Duration: number)

--	-- If time is 0 or 1, return the first or last value respectively
--	if Time == 0 then
--		return CFrameSequence[1].Value
--	elseif Time >= Duration then
--		return CFrameSequence[#CFrameSequence].Value
--	end

--	-- Otherwise, step through each sequential pair of keypoints
--	for i = 1, #CFrameSequence - 1 do
--		local Keypoint = CFrameSequence[i]
--		local NextKeypoint = CFrameSequence[i + 1]

--		if Time >= Keypoint.Time and Time < NextKeypoint.Time then
--			local Alpha = (Time - Keypoint.Time) / (NextKeypoint.Time - Keypoint.Time)
--			if NextKeypoint.Curve then -- Curve affecting the alpha of the result
--				Alpha = Curves[NextKeypoint.Curve](Alpha)
--			end

--			return Keypoint.Value:Lerp(NextKeypoint.Value, Alpha)
--		end
--	end
--	error("CFrameSequence catastrophic failure! ["..Time.."]::["..Duration.."]")
--end

-- COLLISION DETECTION --
-------------------------

function Utility.GetRandomPointInBlock(Part: Part)
	assert(Part.Shape == Enum.PartType.Block, "Wrong Part Type")

	return Part.Position
		+ Part.CFrame.RightVector * Part.Size.X * RNG:NextNumber(-0.5, 0.5)
		+ Part.CFrame.UpVector * Part.Size.Y * RNG:NextNumber(-0.5, 0.5)
		+ Part.CFrame.LookVector * Part.Size.Z * RNG:NextNumber(-0.5, 0.5)
end

local function getSeparatingPlane(relativepos, plane, box1, box2)
	return math.abs(relativepos:Dot(plane)) > 
		(
			math.abs((box1.X):Dot(plane)) +
			math.abs((box1.Y):Dot(plane)) +
			math.abs((box1.Z):Dot(plane)) +
			math.abs((box2.X):Dot(plane)) +
			math.abs((box2.Y):Dot(plane)) +
			math.abs((box2.Z):Dot(plane))
		);
end

function Utility.IsOBBInOBB(CFrameA: CFrame, SizeA: Vector3, CFrameB: CFrame, SizeB: Vector3): boolean

	local relativepos = CFrameB.Position - CFrameA.Position
	local obb1 = {
		X = CFrameA.XVector * SizeA.X / 2,
		Y = CFrameA.YVector * SizeA.Y / 2,
		Z = CFrameA.ZVector * SizeA.Z / 2,
	}
	local obb2 = {
		X = CFrameB.XVector * SizeB.X / 2,
		Y = CFrameB.YVector * SizeB.Y / 2,
		Z = CFrameB.ZVector * SizeB.Z / 2,
	}
	-- All passes must fail to get correct intersection
	return not(getSeparatingPlane(relativepos, CFrameA.XVector, obb1, obb2) or
		getSeparatingPlane(relativepos, CFrameA.YVector, obb1, obb2) or
		getSeparatingPlane(relativepos, CFrameA.ZVector, obb1, obb2) or
		getSeparatingPlane(relativepos, CFrameB.XVector, obb1, obb2) or
		getSeparatingPlane(relativepos, CFrameB.YVector, obb1, obb2) or
		getSeparatingPlane(relativepos, CFrameB.ZVector, obb1, obb2) or
		getSeparatingPlane(relativepos, CFrameA.XVector:Cross(CFrameB.XVector), obb1, obb2) or
		getSeparatingPlane(relativepos, CFrameA.XVector:Cross(CFrameB.YVector), obb1, obb2) or
		getSeparatingPlane(relativepos, CFrameA.XVector:Cross(CFrameB.ZVector), obb1, obb2) or
		getSeparatingPlane(relativepos, CFrameA.YVector:Cross(CFrameB.XVector), obb1, obb2) or
		getSeparatingPlane(relativepos, CFrameA.YVector:Cross(CFrameB.YVector), obb1, obb2) or
		getSeparatingPlane(relativepos, CFrameA.YVector:Cross(CFrameB.ZVector), obb1, obb2) or
		getSeparatingPlane(relativepos, CFrameA.ZVector:Cross(CFrameB.XVector), obb1, obb2) or
		getSeparatingPlane(relativepos, CFrameA.ZVector:Cross(CFrameB.YVector), obb1, obb2) or
		getSeparatingPlane(relativepos, CFrameA.ZVector:Cross(CFrameB.ZVector), obb1, obb2));
end

function Utility.IsAABBInAABB(AABBCenterA: Vector3, AABBSizeA: Vector3, AABBCenterB: Vector3, AABBSizeB: Vector3): boolean

	local HalfSizeA = AABBSizeA / 2
	local HalfSizeB = AABBSizeB / 2

	-- X Check
	if (AABBCenterA.X + HalfSizeA.X) < (AABBCenterB.X - HalfSizeB.X) then return false end
	if (AABBCenterA.X - HalfSizeA.X) > (AABBCenterB.X + HalfSizeB.X) then return false end

	-- Z Check
	if (AABBCenterA.Z + HalfSizeA.Z) < (AABBCenterB.Z - HalfSizeB.Z) then return false end
	if (AABBCenterA.Z - HalfSizeA.Z) > (AABBCenterB.Z + HalfSizeB.Z) then return false end

	-- Y Check
	if (AABBCenterA.Y + HalfSizeA.Y) < (AABBCenterB.Y - HalfSizeB.Y) then return false end
	if (AABBCenterA.Y - HalfSizeA.Y) > (AABBCenterB.Y + HalfSizeB.Y) then return false end

	return true
end

function Utility.IsAABBInCylinderYUp(AABBCenter: Vector3, AABBSize: Vector3, CylinderPosition: Vector3, Height: number, Radius: number): boolean
	-- Check if AABB OVerlap first
	if not Utility.IsAABBInAABB(AABBCenter, AABBSize, CylinderPosition, Vector3.new(Radius * 2, Height, Radius * 2)) then return false end

	local CircleLocalPosition = Vector2.new(CylinderPosition.X - AABBCenter.X, CylinderPosition.Z - AABBCenter.Z)

	-- We can just check the XZ plane (circle to AABB)
	local ClampedPosition = Vector2.new(
		math.clamp(CircleLocalPosition.X, -AABBSize.X/2, AABBSize.X/2),
		math.clamp(CircleLocalPosition.Y, -AABBSize.Z/2, AABBSize.Z/2)
	)
	local DistSquaredClampedtoSphere = (ClampedPosition - CircleLocalPosition)
	DistSquaredClampedtoSphere = DistSquaredClampedtoSphere:Dot(DistSquaredClampedtoSphere)

	return DistSquaredClampedtoSphere <= (Radius * Radius)
end

function Utility.IsAABBInSphere(AABBPosition: Vector3, OBBSize: Vector3, SpherePosition: Vector3, SphereRadius: number): boolean
	-- Bring position to localspace
	local SphereLocalPosition = SpherePosition - AABBPosition

	-- clamp sphere center to all points
	local ClampedPosition = Vector3.new(
		math.clamp(SphereLocalPosition.X, -OBBSize.X/2, OBBSize.X/2),
		math.clamp(SphereLocalPosition.Y, -OBBSize.Y/2, OBBSize.Y/2),
		math.clamp(SphereLocalPosition.Z, -OBBSize.Z/2, OBBSize.Z/2)
	)
	local DistSquaredClampedtoSphere = (ClampedPosition - SphereLocalPosition)
	DistSquaredClampedtoSphere = DistSquaredClampedtoSphere:Dot(DistSquaredClampedtoSphere)

	return DistSquaredClampedtoSphere <= (SphereRadius * SphereRadius)
end

function Utility.IsPointInAABB(Position: Vector3, TargetPosition: Vector3, TargetSize: Vector3): boolean
	-- size means must have matching positions
	if TargetSize == Vector3.zero then return Position == TargetPosition end

	-- set to uniform space for easy math
	local P = Position / TargetSize
	return 
		math.abs(P.X) <= 1
		or math.abs(P.Y) <= 1
		or math.abs(P.Z) <= 1
end

function Utility.GetHitPoint_OBBInSphere(OBBCFrame: CFrame, OBBSize: Vector3, SpherePosition: Vector3, SphereRadius: number): Vector3?
	local SphereLocalPosition = OBBCFrame:Inverse() * SpherePosition
	local ClampedPosition = Vector3.new(
		math.clamp(SphereLocalPosition.X, -OBBSize.X/2, OBBSize.X/2),
		math.clamp(SphereLocalPosition.Y, -OBBSize.Y/2, OBBSize.Y/2),
		math.clamp(SphereLocalPosition.Z, -OBBSize.Z/2, OBBSize.Z/2)
	)
	-- Hit Position
	local HitPosition = OBBCFrame * ClampedPosition

	local DistSquaredClampedtoSphere = (ClampedPosition - SphereLocalPosition)
	DistSquaredClampedtoSphere = DistSquaredClampedtoSphere:Dot(DistSquaredClampedtoSphere)

	if DistSquaredClampedtoSphere <= (SphereRadius * SphereRadius) then
		return HitPosition
	else
		return nil
	end
end

function Utility.IsOBBInSphere(OBBCFrame: CFrame, OBBSize: Vector3, SpherePosition: Vector3, SphereRadius: number): boolean
	-- Bring Sphere to OBB's local space
	local SphereLocalPosition = OBBCFrame:Inverse() * SpherePosition

	-- Simply shrink sphere to a point and add size to aabb
	--local SphereDiameter = SphereRadius * 2
	--return Utility.IsPointInAABB(SpherePosition, AABBCFrame_Local.Position, OBBSize + Vector3.one * SphereDiameter)

	-- (v cheaper method v)

	-- clamp sphere center to all points
	local ClampedPosition = Vector3.new(
		math.clamp(SphereLocalPosition.X, -OBBSize.X/2, OBBSize.X/2),
		math.clamp(SphereLocalPosition.Y, -OBBSize.Y/2, OBBSize.Y/2),
		math.clamp(SphereLocalPosition.Z, -OBBSize.Z/2, OBBSize.Z/2)
	)
	local DistSquaredClampedtoSphere = (ClampedPosition - SphereLocalPosition)
	DistSquaredClampedtoSphere = DistSquaredClampedtoSphere:Dot(DistSquaredClampedtoSphere)

	return DistSquaredClampedtoSphere <= (SphereRadius * SphereRadius)
end

function Utility.GetHitPoint_WedgeInSphere(WedgeCFrame: CFrame, WedgeSize: Vector3, SpherePosition: Vector3, SphereRadius: number): Vector3?
	-- Check if spheres closest point to wedge tangent crosses the tangent
	local SphereLocalPosition = WedgeCFrame:Inverse() * SpherePosition	

	local WedgeNormal = Vector3.new(0, WedgeSize.Y, -WedgeSize.Z).Unit
	local SphereClosestPoint = SphereLocalPosition - WedgeNormal * SphereRadius

	local Dot = SphereClosestPoint:Dot(WedgeNormal)
	if Dot >= 0 then return nil end

	-- full obb in sphere check
	local HitPointCore = Utility.GetHitPoint_OBBInSphere(WedgeCFrame, WedgeSize, SpherePosition, SphereRadius)
	if not HitPointCore then return nil end

	Dot = SphereLocalPosition:Dot(WedgeNormal)
	if Dot >= 0 then
		-- clamp to tangent
		local WedgeTangentHalf = Vector3.new(0, WedgeSize.Y / 2, WedgeSize.Z / 2)
		local WedgeTangentHalfLength = WedgeTangentHalf.Magnitude
		local P = shared.GetModule("Math").Project(SphereLocalPosition, WedgeTangentHalf.Unit)
		if P.Magnitude > WedgeTangentHalfLength then P = P.Unit * WedgeTangentHalfLength end

		local WorldP = (WedgeCFrame * P)
		return Vector3.new(HitPointCore.X, WorldP.Y, WorldP.Z)

	else
		return HitPointCore
	end
end

--task.spawn(function()
--	while task.wait() do
--		local p = Utility.GetHitPoint_WedgeInSphere(workspace.WEDGE.CFrame, workspace.WEDGE.Size, workspace.SPHERE.Position, workspace.SPHERE.Size.X / 2)
--		warn(p)
--		if p then
--			workspace.CONTACT.Position = p

--		else
--			workspace.CONTACT.Position = Vector3.new(10000000000, 0, 0)
--		end
--	end
--end)

function Utility.IsWedgeInSphere(WedgeCFrame: CFrame, WedgeSize: Vector3, SpherePosition: Vector3, SphereRadius: number): boolean

	-- Check if spheres closest point to wedge tangent crosses the tangent
	local SphereLocalPosition = WedgeCFrame:Inverse() * SpherePosition	

	local WedgeNormal = Vector3.new(0, WedgeSize.Y, -WedgeSize.Z).Unit
	local SphereClosestPoint = SphereLocalPosition - WedgeNormal * SphereRadius

	local Dot = SphereClosestPoint:Dot(WedgeNormal)
	if Dot >= 0 then return false end

	-- full obb in sphere check
	if not Utility.IsOBBInSphere(WedgeCFrame, WedgeSize, SpherePosition, SphereRadius) then return false end

	return true
end

function Utility.IsPointInCapsule(Position: Vector3, CapsulePosition1: Vector3, CapsulePosition2: Vector3, Radius: number): boolean

	local LengthVector  = (CapsulePosition2 - CapsulePosition1)
	local LengthSquared = LengthVector:Dot(LengthVector)

	if LengthSquared == 0 then return false end

	local ProjectionLength = (Position - CapsulePosition1):Dot(LengthVector) / LengthSquared
	local ClampedProjectionLength = math.clamp(ProjectionLength, 0, 1)

	local LineProjection = CapsulePosition1 + LengthVector * ClampedProjectionLength

	local ToLine = (Position - LineProjection)
	return ToLine:Dot(ToLine) <= (Radius * Radius)
end

function Utility.IsPointInOBB(Position: Vector3, TargetCFrame: CFrame, TargetSize: Vector3): boolean
	local encodedOBB = CFrame.fromMatrix(
		TargetCFrame.Position,
		TargetCFrame.XVector / TargetSize.X,
		TargetCFrame.YVector / TargetSize.Y,
		TargetCFrame.ZVector / TargetSize.Z
	):Inverse()

	local objPos = encodedOBB * Position
	return
		math.abs(objPos.x) <= 0.5 and
		math.abs(objPos.y) <= 0.5 and
		math.abs(objPos.z) <= 0.5
end

function Utility.IsPointInPart(Position: Vector3, Part: Part, SizeOffset: Vector3?): boolean
	if typeof(Position) ~= "Vector3" then error("Vector3 is invalid") end
	if typeof(Part) ~= "Instance" then error("Part is invalid") end
	local RealSizeOffset = SizeOffset or Vector3.zero

	if Part.Shape == Enum.PartType.Block then
		-- CFrame.fromMatrix constructs a CFrame from column vectors
		local encodedOBB = CFrame.fromMatrix(
			Part.CFrame.Position,
			Part.CFrame.XVector / (Part.Size.X + RealSizeOffset.X),
			Part.CFrame.YVector / (Part.Size.Y + RealSizeOffset.Y),
			Part.CFrame.ZVector / (Part.Size.Z + RealSizeOffset.Z)
		):Inverse()

		local objPos = encodedOBB * Position
		return
			math.abs(objPos.x) <= 0.5 and
			math.abs(objPos.y) <= 0.5 and
			math.abs(objPos.z) <= 0.5

	elseif Part.Shape == Enum.PartType.Ball then
		local Diff = Vector3.new(Position.X - Part.Position.X, Position.Y - Part.Position.Y, Position.Z - Part.Position.Z)
		local DistanceSquared = Diff:Dot(Diff)
		local MinSize = math.min(Part.Size.X + RealSizeOffset.X, math.min(Part.Size.Y + RealSizeOffset.Y, Part.Size.Z + RealSizeOffset.Z))
		return DistanceSquared <= (MinSize * MinSize * 0.25)

	elseif Part.Shape == Enum.PartType.Cylinder then
		local Point = Part.CFrame:PointToObjectSpace(Position)
		-- Check along X-axis
		local XCheck = (math.abs(Point.X) <= (Part.Size.X + RealSizeOffset.X) / 2)
		if not XCheck then return false end
		-- Check along YZ-axis (radius)
		local YZVec = Vector2.new(Point.Y, Point.Z)
		local DistanceSquared = YZVec:Dot(YZVec)
		local BlockRadius = math.min(Part.Size.Y + RealSizeOffset.Y, Part.Size.Z + RealSizeOffset.Z) * 0.5
		return DistanceSquared <= (BlockRadius * BlockRadius)
	else

		error("Invalid Shape Type")
		return false
	end
end

-- Circular Lerp
function Utility.Clerp(startAngle, endAngle, alpha)
	--local min = 0.0;
	--local max = 360.0;
	local half = 180-- math.abs((max - min) / 2.0) -- half the distance between min and max
	local retval = 0.0;
	local diff = 0.0;

	if ((endAngle - startAngle) < -half) then

		diff = ((360 - startAngle) + endAngle) * alpha
		retval = startAngle + diff

	elseif ((endAngle - startAngle) > half) then

		diff = -((360 - endAngle) + startAngle) * alpha
		retval = startAngle + diff

	else
		retval = startAngle + (endAngle - startAngle) * alpha
	end

	return retval
end

function Utility.CFrameTween(TweenInfo: TweenInfo, AnimPart, EndCFrame: CFrame)
	local StartCFrame = AnimPart:IsA("BasePart") and AnimPart.CFrame or AnimPart:GetPivot()
	local IsModel = AnimPart:IsA("Model")

	if IsModel then
		Utility.RawTween(TweenInfo, function(Alpha, DeltaTime)
			if not AnimPart:IsDescendantOf(workspace) then return end
			AnimPart:PivotTo(StartCFrame:Lerp(EndCFrame, Alpha))
		end)
	else
		Utility.RawTween(TweenInfo, function(Alpha, DeltaTime)
			if not AnimPart:IsDescendantOf(workspace) then return end
			AnimPart.CFrame = (StartCFrame:Lerp(EndCFrame, Alpha))
		end)
	end
end

function Utility.RawTween(tweenInfo: TweenInfo, tweenCallback: (tweenAlpha: number, deltaTime: number) -> nil)
	local tweenEasingStyle = tweenInfo.EasingStyle
	local tweenEasingDirection = tweenInfo.EasingDirection

	local tweenRepeatCount = tweenInfo.RepeatCount
	local tweenIndefinitely = tweenRepeatCount<=-1

	local tweenDelay = tweenInfo.DelayTime
	local tweenDuration = tweenDelay + tweenInfo.Time
	local tweenReverses = tweenInfo.Reverses

	if tweenReverses then
		tweenDuration += tweenInfo.Time
	end

	local TweenService = game:GetService("TweenService")

	local tweensRemaining = tweenRepeatCount + 1
	while tweenIndefinitely or tweensRemaining > 0 do
		local startTime = tick() + tweenDelay
		local endTime = (startTime - tweenDelay) + tweenDuration
		local deltaTimeStamp = tick()
		while tick() < endTime do
			local deltaTime = tick() - deltaTimeStamp
			deltaTimeStamp = tick()
			local timeElapsed = tick() - startTime
			if timeElapsed > 0 then
				local currentAlpha = timeElapsed / (tweenDuration - tweenDelay)
				if tweenReverses then
					currentAlpha = if currentAlpha > 0.5 then -2 * currentAlpha + 2 else 2 * currentAlpha
				end
				local tweenAlpha = TweenService:GetValue(currentAlpha, tweenEasingStyle, tweenEasingDirection)
				tweenCallback(tweenAlpha, deltaTime)
			else
				tweenCallback(0, deltaTime)
			end
			task.wait()
		end
		tweensRemaining = math.max(tweensRemaining - 1, 0)
	end
	--ensures the last tweenAlpha is an integer and not a float
	tweenCallback(if tweenReverses then 0 else 1, 0)
end

return Utility
