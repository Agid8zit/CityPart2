local CoroutineManager = {}
CoroutineManager.__index = CoroutineManager

function CoroutineManager.new()
	local self = setmetatable({}, CoroutineManager)
	self.coroutines = {}
	return self
end

-- Add a new coroutine
function CoroutineManager:addCoroutine(func)
	local co = coroutine.create(func)
	table.insert(self.coroutines, co)
end

-- Run all active coroutines
function CoroutineManager:run()
	for i = #self.coroutines, 1, -1 do	
		local co = self.coroutines[i]
		if coroutine.status(co) ~= "dead" then
			local success, message = coroutine.resume(co)
			if not success then
				warn("Coroutine Error:", message)
				table.remove(self.coroutines, i)
			elseif coroutine.status(co) == "dead" then
				table.remove(self.coroutines, i)
			end
		else
			table.remove(self.coroutines, i)
		end
	end
end

return CoroutineManager