local VersionedDataStoreClass = {}
VersionedDataStoreClass.__index = VersionedDataStoreClass

-- Dependencies
local DataStoreClass = require(game.ServerScriptService.DataStore.DataStoreClass)
local OrderedDataStoreClass = require(game.ServerScriptService.DataStore.OrderedDataStoreClass)

-- Module Functions
function VersionedDataStoreClass.new(DataStoreName: string, ScopeName: string)

	local DataStore = DataStoreClass.new(DataStoreName, ScopeName)
	local OrderedDataStore = OrderedDataStoreClass.new(DataStoreName, ScopeName)

	if not DataStore or not OrderedDataStore then return nil end

	local Data = {
		DataStoreName = DataStoreName,
		ScopeName = ScopeName or "",
		DataStore = DataStore,
		OrderedDataStore = OrderedDataStore,
	}
	setmetatable(Data, VersionedDataStoreClass)
	return Data
end

function VersionedDataStoreClass:GetLatestTimeStamp(): (number?, boolean)
	-- Get Latest TimeStamp from highest ordered TimeStamp
	local Pages = self.OrderedDataStore:GetSortedPagesAsync(false, 1, 1)
	if not Pages then return nil, false end

	-- Check if Loaded Successfully vs Errored
	local LoadedFirstPage = Pages.WasFirstPageLoaded()

	local Contents = Pages.GetContents(1)
	if not Contents then return nil, LoadedFirstPage end

	local FirstContent = Contents[1]
	if not FirstContent then return nil, LoadedFirstPage end

	return FirstContent.Value, true
end

function VersionedDataStoreClass:GetAsync() : (any?, boolean, number?)
	local TimeStamp, Success = self:GetLatestTimeStamp()
	if not TimeStamp then return nil, Success, TimeStamp end
	
	local NewValue, Success2 = self.DataStore:GetAsync(tostring(TimeStamp))
	return NewValue, Success2, TimeStamp
end
function VersionedDataStoreClass:SetAsync_OverwriteLatest(NewData: boolean): (any?, boolean)
	local TimeStamp = self:GetLatestTimeStamp()
	if not TimeStamp then return nil, false end

	local _, Success = self.DataStore:SetAsync(tostring(TimeStamp), NewData)
	if not Success then
		warn("(Failed to Overwrite VersionDataStore)")
		return nil, false
	end
	return true, true
end

function VersionedDataStoreClass:SetAsync_NewSave(NewData, TimeStamp: number): boolean
	-- Core write
	local _, Success = self.DataStore:SetAsync(tostring(TimeStamp), NewData)
	if not Success then
		warn("(Failed to Save VersionDataStore - Core)")
		self.DataStore:RemoveAsync(tostring(TimeStamp))
		return false
	end

	-- Ordered index write
	local _, Success2 = self.OrderedDataStore:SetAsync(tostring(TimeStamp), TimeStamp)
	if not Success2 then
		warn("(Failed to Save VersionDataStore - Time)")
		self.DataStore:RemoveAsync(tostring(TimeStamp))
		return false
	end

	return true
end

function VersionedDataStoreClass:RollbackToTimeStamp(GivenTimeStamp: number)
	warn("<-- TODO -->")
	-- get 100 page long of timestamps
	-- do binary search to find the one right before the given time stamp
		-- make sure to check first and last at the start
	-- Once that timestamp has been found, load the associated data
		-- if the loaded data is nil, go back a timestamp
	-- if all good, call SetAsync with the current data
	-- if cannot roll far back enough to account for given timestamp, call SetAsync an empty table 
end

return VersionedDataStoreClass
