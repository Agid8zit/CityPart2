local folder = game.ReplicatedStorage.FuncTestGroundRS.Buildings.Individual.Default:WaitForChild("Flags")

local sourceName = "Flag America"
local source = folder:FindFirstChild(sourceName)
if not source then
	error(("Source '%s' not found under %s"):format(sourceName, folder:GetFullName()))
end


local targets = {}
for _, inst in ipairs(folder:GetChildren()) do
	if inst ~= source and inst:IsA("Instance") then
		table.insert(targets, inst)
	end
end


local srcAttrs = source:GetAttributes()
for name, value in pairs(srcAttrs) do
	local t = typeof(value)
	local supported = (
		t == "boolean" or t == "number" or t == "string" or
		t == "BrickColor" or t == "Color3" or t == "Vector3" or
		t == "UDim" or t == "UDim2" or t == "NumberSequence" or
		t == "ColorSequence" or t == "NumberRange" or t == "Rect"
	)
	if not supported then
		warn(("Attribute '%s' has unsupported type '%s' (skipped)."):format(name, t))
	else
		for _, target in ipairs(targets) do
			target:SetAttribute(name, value)
		end
	end
end

print(("Copied %d supported attributes from '%s' to %d targets.")
	:format(#(function()
		local c=0; for _ in pairs(srcAttrs) do c+=1 end; return {c}
	end)()[1], sourceName, #targets))