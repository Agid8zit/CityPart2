local OrderedDataStoreClass = {}
OrderedDataStoreClass.__index = OrderedDataStoreClass

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
			if Budget > 2 then return true end
		end
		-- wait and try again
		Attempts -= 1
		task.wait(5)
	end
	
	return false
end

-- Module Functions
function OrderedDataStoreClass.new(DataStoreName: string, ScopeName: string)

	local DataStore = nil;
	local Success, ErrMsg = pcall(function()
		DataStore = DataStoreService:GetOrderedDataStore(DataStoreName, ScopeName)
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
	setmetatable(Data, OrderedDataStoreClass)
	return Data
end

function OrderedDataStoreClass:_SafelyCallAsync(AsyncFunction: () -> (), Key: string, FunctionName: string)
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

function OrderedDataStoreClass:GetAsync(Key: string) : (any?, boolean)
	-- Ask DataStore if can request it, if not, try to wait for it
	if not WaitForBudget(Enum.DataStoreRequestType.GetAsync) then
		return nil, false
	end
	
	return self:_SafelyCallAsync(function()
		return self.DataStore:GetAsync(Key)
	end, Key, "GetAsync")
end

function OrderedDataStoreClass:SetAsync(Key: string, Integer: any) : (any?, boolean)
	assert(Integer == math.floor(Integer), "SetAsync ["..Key.."] call has received a non-Integer Value ("..tostring(Integer)..")")
	if not WaitForBudget(Enum.DataStoreRequestType.GetAsync) then
		return nil, false
	end
	return self:_SafelyCallAsync(function()
		return self.DataStore:SetAsync(Key, Integer)
	end, Key, "SetAsync")
end

function OrderedDataStoreClass:IncrementAsync(Key: string, Delta: number?) : (any?, boolean)
	return self:_SafelyCallAsync(function()
		return self.DataStore:IncrementAsync(Key, Delta)
	end, Key, "IncrementAsync")
end

function OrderedDataStoreClass:RemoveAsync(Key: string) : (any?, boolean)
	return self:_SafelyCallAsync(function()
		return self.DataStore:RemoveAsync(Key)
	end, Key, "RemoveAsync")
end

function OrderedDataStoreClass:UpdateAsync(Key: string, Value: any, TransformFunction: (OriginalValue: any?, Value: any) -> ()) : (any?, boolean)
	-- Ask DataStore if can request it, if not, try to wait for it
	if not WaitForBudget(Enum.DataStoreRequestType.UpdateAsync) then
		return nil, false
	end
	
	return self:_SafelyCallAsync(function()
		return self.DataStore:UpdateAsync(Key, function(OriginalValue)
			return TransformFunction(OriginalValue, Value)
		end)
	end, Key, "UpdateAsync")
end

function OrderedDataStoreClass:GetSortedPagesAsync(Ascending: boolean, PageSize: number, DefaultPagesToLoad: number, MinValue: any?, MaxValue: any?): any?
	assert(PageSize >= 1 and PageSize <= 100, "[OrderdDataStore] Page Size must be between 1 and 100")
	
	-- Ask DataStore if can request it, if not, try to wait for it
	if not WaitForBudget(Enum.DataStoreRequestType.GetSortedAsync) then
		return nil
	end
	
	local PagePointer = self:_SafelyCallAsync(function()
		return self.DataStore:GetSortedAsync(Ascending, PageSize, MinValue, MaxValue)
	end, "N/A", "GetSortedAsync")
	
	if not PagePointer then return nil end
	
	local Pages = {}
	Pages.PagePointer = PagePointer;
	Pages.CurrentPage = nil
	Pages.CachedContents = {}
	Pages.FirstPageLoaded = false
	Pages.IsFinishedFlag = false
	
	function Pages.GetContents(PageIndex: number)
		return Pages.CachedContents[PageIndex]
	end
	
	function Pages.GetTotalPages()
		return #Pages.CachedContents
	end
	
	function Pages.WasFirstPageLoaded()
		return Pages.FirstPageLoaded
	end
	
	function Pages.IsFinished()
		return Pages.IsFinishedFlag
	end
	
	function Pages.AcquireNextPage()
		-- No more to read
		--if typeof(Pages.PagePointer) ~= "Instance" then return end
		
		-- Read current page
		local NextPage = self:_SafelyCallAsync(function()
			return Pages.PagePointer:GetCurrentPage()
		end, "N/A", "GetCurrentPage")
		
		if NextPage then
			Pages.FirstPageLoaded = true
			Pages.CurrentPage = NextPage
		else
			return
		end
		
		-- Cache all contents from page
		local PageContents = {}
		for _, Data in Pages.CurrentPage do
			table.insert(PageContents, {
				Key = Data.key,
				Value = Data.value
			})
		end
		table.insert(Pages.CachedContents, PageContents)
		
		-- Next Page or Finish
		if Pages.PagePointer.IsFinished then
			Pages.PagePointer = nil
			Pages.IsFinishedFlag = true
		else
			local Success, ErrMsg = pcall(function()
				Pages.PagePointer:AdvanceToNextPageAsync()
			end)
			if not Success then warn(ErrMsg) end
		end
	end
	
	-- Initial Pages being read since you'll likely want to already do that at the same time
	for _ = 1, DefaultPagesToLoad do
		Pages.AcquireNextPage()
	end
	
	return Pages
end

return OrderedDataStoreClass
