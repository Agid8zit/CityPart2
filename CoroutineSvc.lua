local CoroutineManager = require(script.Parent:WaitForChild("CoroutineManager"))

local CoroutineService = {}
CoroutineService.__index = CoroutineService

function CoroutineService.new()
	local self = setmetatable({}, CoroutineService)
	self.manager = CoroutineManager.new()

	-- Connect to RunService to execute coroutines each frame
	game:GetService("RunService").Heartbeat:Connect(function()
		self.manager:run()
	end)

	return self
end

-- Add a new coroutine to the manager
function CoroutineService:addCoroutine(func)
	self.manager:addCoroutine(func)
end

-- Expose other manager method
function CoroutineService:runCoroutines()
	self.manager:run()
end

-- Instantiate and return the singleton instance
local CoroutineServiceInstance = CoroutineService.new()

return CoroutineServiceInstance