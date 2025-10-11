local BuildMode = {}

local buildModeEnabled = false
local changeEvent = Instance.new("BindableEvent")  -- fires whenever buildModeEnabled changes
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local globalToggleEvent = ReplicatedStorage
	:WaitForChild("Events")
	:WaitForChild("BindableEvents")
	:WaitForChild("ModeBuild")

-- Other scripts can connect to this event:
BuildMode.OnChanged = changeEvent.Event

-- Functions to get/set/toggle:
function BuildMode.IsEnabled()
	return buildModeEnabled
end

function BuildMode.SetEnabled(enabled)
	if buildModeEnabled == enabled then
		return
	end
	buildModeEnabled = enabled
	changeEvent:Fire(buildModeEnabled)
end

function BuildMode.Enable()
	BuildMode.SetEnabled(true)
end

function BuildMode.Disable()
	BuildMode.SetEnabled(false)
end

function BuildMode.Toggle()
	BuildMode.SetEnabled(not buildModeEnabled)
end


return BuildMode