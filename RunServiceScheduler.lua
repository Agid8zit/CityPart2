local RunService = game:GetService("RunService")

local Scheduler = {}

local slots = {
	Heartbeat = {
		signal = RunService.Heartbeat,
		callbacks = {},
		connection = nil,
	},
	Stepped = {
		signal = RunService.Stepped,
		callbacks = {},
		connection = nil,
	},
}

if RunService:IsClient() then
	slots.RenderStepped = {
		signal = RunService.RenderStepped,
		callbacks = {},
		connection = nil,
	}
else
	-- RenderStepped is client-only; keep a placeholder so accidental usage is obvious.
	slots.RenderStepped = {
		signal = nil,
		callbacks = {},
		connection = nil,
		clientOnly = true,
	}
end

local nextToken = 0

local function disconnectSlotIfIdle(slot)
	if slot.connection and not next(slot.callbacks) then
		slot.connection:Disconnect()
		slot.connection = nil
	end
end

local function ensureConnection(slotName)
	local slot = slots[slotName]
	if not slot then
		error(string.format("[RunServiceScheduler] Unknown slot '%s'", tostring(slotName)))
	end
	if slot.connection or not slot.signal then
		return
	end

	slot.connection = slot.signal:Connect(function(...)
		for token, callback in next, slot.callbacks do
			if callback ~= nil then
				local ok, err = pcall(callback, ...)
				if not ok then
					warn(string.format("[RunServiceScheduler] %s callback (%s) failed: %s", slotName, tostring(token), err))
				end
			end
		end
	end)
end

local function bind(slotName, callback)
	assert(type(callback) == "function", "callback must be a function")
	local slot = slots[slotName]
	if not slot then
		error(string.format("[RunServiceScheduler] Unknown slot '%s'", tostring(slotName)))
	end
	if slot.clientOnly and slot.signal == nil then
		error(string.format("[RunServiceScheduler] %s is only available on the client", slotName))
	end

	nextToken += 1
	local token = string.format("%s_%d", slotName, nextToken)
	slot.callbacks[token] = callback

	ensureConnection(slotName)

	return function()
		if slot.callbacks[token] ~= nil then
			slot.callbacks[token] = nil
			disconnectSlotIfIdle(slot)
		end
	end
end

function Scheduler.onHeartbeat(callback)
	return bind("Heartbeat", callback)
end

function Scheduler.onRenderStepped(callback)
	return bind("RenderStepped", callback)
end

function Scheduler.onStepped(callback)
	return bind("Stepped", callback)
end

return Scheduler
