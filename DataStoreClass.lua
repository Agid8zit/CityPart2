local DataStoreClass = {}
DataStoreClass.__index = DataStoreClass

-- Roblox Services
local DataStoreService = game:GetService("DataStoreService")

-- Helper Function
local function WaitForBudget(BudgetType: Enum.DataStoreRequestType): boolean
	local Attempts = 4
	local Success = false
	local Budget = nil

	while not Success and Attempts > 0 do
		Success, Budget = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(BudgetType)
		end)
		if Success then
			if Budget > 1 then return true end
		end
		-- wait and try again
		Attempts -= 1
		task.wait(5)
	end

	return false
end

-- Module Functions
function DataStoreClass.new(DataStoreName: string, ScopeName: string?)
	
	local DataStore = nil;
	local Success, ErrMsg = pcall(function()
		DataStore = DataStoreService:GetDataStore(DataStoreName, ScopeName)
	end)
	if not Success then
		warn(ErrMsg)
		return nil
	end
	
	local Data = {
		DataStoreName = DataStoreName,
		ScopeName = ScopeName or "",
		DataStore = DataStore,
	}
	setmetatable(Data, DataStoreClass)
	return Data
end

function DataStoreClass:_SafelyCallAsync(AsyncFunction: () -> (), Key: string, FunctionName: string)
	local Success, Result = pcall(function()
		return AsyncFunction()
	end)

	if not Success then
		local ErrorCode = tonumber(string.sub(tostring(Result), 1, 3)) or 0
		if math.floor(ErrorCode / 100) == 1 then
			warn(ErrorCode .. " [" .. tostring(Key) .. "]")
			return nil
		else
			warn(tostring(Result) .. " [" .. tostring(Key) .. "]")
			for Index = 1, 7 do
				task.wait(Index)
				local Success2, Ret = pcall(AsyncFunction)
				if Success2 then return Ret, true end
			end
			warn("Failed to call ("..FunctionName..") ["..self.DataStoreName.."]["..self.ScopeName.."]")
			return nil, false
		end
	else
		return Result, true
	end
end

function DataStoreClass:GetAsync(Key: string) : (any?, boolean)
	if not WaitForBudget(Enum.DataStoreRequestType.GetAsync) then
		return nil, false
	end
	return self:_SafelyCallAsync(function()
		return self.DataStore:GetAsync(Key)
	end, Key, "GetAsync")
end

function DataStoreClass:SetAsync(Key: string, Value: any) : (any?, boolean)
	if not WaitForBudget(Enum.DataStoreRequestType.SetIncrementAsync) then
		return nil, false
	end
	return self:_SafelyCallAsync(function()
		return self.DataStore:SetAsync(Key, Value)
	end, Key, "SetAsync")
end

function DataStoreClass:IncrementAsync(Key: string, Delta: number?) : (any?, boolean)
	return self:_SafelyCallAsync(function()
		return self.DataStore:IncrementAsync(Key, Delta)
	end, Key, "IncrementAsync")
end

function DataStoreClass:RemoveAsync(Key: string) : (any?, boolean)
	return self:_SafelyCallAsync(function()
		return self.DataStore:RemoveAsync(Key)
	end, Key, "RemoveAsync")
end

function DataStoreClass:UpdateAsync(Key: string, Value: any, TransformFunction: (OriginalValue: any?, Value: any) -> ())
	if not WaitForBudget(Enum.DataStoreRequestType.UpdateAsync) then
		return nil, false
	end
	return self:_SafelyCallAsync(function()
		return self.DataStore:UpdateAsync(Key, function(OriginalValue)
			return TransformFunction(OriginalValue, Value)
		end)
	end, Key, "UpdateAsync")
end

return DataStoreClass
