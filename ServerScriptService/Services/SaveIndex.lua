local DataStoreService = game:GetService("DataStoreService")
local SavePolicy = require(script.Parent.Parent.Config.SavePolicy)

local SaveIndex = {}

local function _ds()
	return DataStoreService:GetDataStore(SavePolicy.INDEX_STORE)
end

local function keyFor(userId)
	return ("index:%s"):format(tostring(userId))
end

function SaveIndex.read(userId)
	local store = _ds()
	local ok, val = pcall(function()
		return store:GetAsync(keyFor(userId))
	end)
	if ok and val then
		return val
	end
	return { userId = tostring(userId), slots = {}, updatedAt = os.time() }
end

function SaveIndex.write(userId, index)
	if SavePolicy.APPLY_CHANGES ~= true then
		return true
	end
	local store = _ds()
	index.updatedAt = os.time()
	local ok, err = pcall(function()
		store:SetAsync(keyFor(userId), index)
	end)
	return ok, err
end

return SaveIndex
