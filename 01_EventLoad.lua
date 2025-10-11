local RS = game:GetService("ReplicatedStorage")
local function ensure(parent, className, name)
	local obj = parent:FindFirstChild(name)
	if not obj then obj = Instance.new(className); obj.Name = name; obj.Parent = parent end
	return obj
end
local Events   = ensure(RS, "Folder", "Events")
local Bindable = ensure(Events, "Folder", "BindableEvents")
local RemoteEv = ensure(Events, "Folder", "RemoteEvents")
local RemoteFn = ensure(Events, "Folder", "RemoteFunctions")

-- Bindables (you likely already have ZoneAdded/ZoneRemoved)
ensure(Bindable, "BindableEvent", "UniqueZoneChanged")

-- Remotes
ensure(RemoteEv, "RemoteEvent", "PlayerDataSync")
ensure(RemoteEv, "RemoteEvent", "OpenBuildingUI")   -- c->s (request) and s->c (echo with action)
ensure(RemoteEv, "RemoteEvent", "TownFeedUpdated")

ensure(RemoteFn, "RemoteFunction", "TownFeedPost")
ensure(RemoteFn, "RemoteFunction", "TownFeedGet")
ensure(RemoteFn, "RemoteFunction", "RequestBubbleLine") -- optional for bubbles-from-feed
