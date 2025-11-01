local DevProducts = {}

-- Roblox Services
local MarketplaceService = game:GetService("MarketplaceService")

-- type 
type DevProductContent = {
	IsLoaded: boolean,
	IsForSale: boolean?,
	Name: string?,
	Image: string?,
	Description: string?,
	Price: number?,
}

-- Constants
local DEVPRODUCTS_RAW = {
	-- Name = DevProductID
	["Coin Option1"] = {ID = 3280553599, EarnedCoins = 10000, LayoutOrder = 1};
	["Coin Option2"] = {ID = 3280553720, EarnedCoins = 50000, LayoutOrder = 2};
	["Coin Option3"] = {ID = 3280554426, EarnedCoins = 150000, LayoutOrder = 3};
	["Coin Option4"] = {ID = 3280554937, EarnedCoins = 500000, LayoutOrder = 4};
	["Coin Option5"] = {ID = 3280555256, EarnedCoins = 1000000, LayoutOrder = 5};
	["Coin Option6"] = {ID = 3280555633, EarnedCoins = 2000000, LayoutOrder = 6};
	
	["FirePrecinct"] = {ID = 3296251177};
	["PolicePrecinct"] = {ID = 3296251266};
	["MajorHospital"] = {ID = 3296251773};
	["Museum"] = {ID = 3296251901};
	["FootballStadium"] = {ID = 3296252018};
	["StatueOfLiberty"] = {ID = 3296252147};
	["EiffelTower"] = {ID = 3296252310};
	["NuclearPowerPlant"] = {ID = 3296252477};
	["MolecularWaterPlant"] = {ID = 3296252612};
}
local DEVPRODUCT_ID_FROM_NAME = {} -- [DevProductID] = DevProductName

-- Defines
local AllDevProducts: {[string]: DevProductContent} = {} -- [DevProductName] = {Data}

-- Helper Functions
local function LoadDevProduct(DevProductName: string)
	local DevProductID = DEVPRODUCTS_RAW[DevProductName].ID
	assert(DevProductID, "DevProduct Name ("..DevProductName..") does not exist")
	
	local ProductInfo = nil
	local Success, ErrMsg = pcall(function()
		ProductInfo = MarketplaceService:GetProductInfo(DevProductID, Enum.InfoType.Product)
	end)
	if not Success then
		warn("Failed DevProduct ("..DevProductName..");"..ErrMsg)
	end
	
	if Success and ProductInfo then
		AllDevProducts[DevProductName] = {
			IsLoaded = true,
			IsForSale = ProductInfo.IsForSale or false,
			Name = ProductInfo.Name or "???",
			Image = "rbxassetid://"..(ProductInfo.IconImageAssetId or "0"),
			Description = ProductInfo.Description or "???",
			Price = ProductInfo.PriceInRobux or "???",
		}
	else
		AllDevProducts[DevProductName] = {
			IsLoaded = false,
			IsForSale = false,
			Name = "???",
			Image = "",
			Description = "???",
			Price = 0,
		}
	end
	--	["AssetId"] = 0,
	--	["AssetTypeId"] = 0,
	--	["Created"] = "2024-03-29T19:54:21.0855995Z",
	--	["Creator"] =  ▶ {...},
	--	["Description"] = "description",
	--	["DisplayDescription"] = "description",
	--	["DisplayIconImageAssetId"] = 16926485306,
	--	["DisplayName"] = "Coin1",
	--	["IconImageAssetId"] = 16926485306,
	--	["IsForSale"] = true,
	--	["IsLimited"] = false,
	--	["IsLimitedUnique"] = false,
	--	["IsNew"] = true,
	--	["IsPublicDomain"] = false,
	--	["MinimumMembershipLevel"] = 0,
	--	["Name"] = "Coin1",
	--	["PriceInRobux"] = 999,
	--	["ProductId"] = 1789750832,
	--	["ProductType"] = "Developer Product",
	--	["TargetId"] = 51355087,
	--	["Updated"] = "2024-03-29T19:54:23.3740472Z"
end

local function GetSafe(DevProductName: string)
	-- Not loaded = attempt reload
	if AllDevProducts[DevProductName].IsLoaded == false then LoadDevProduct(DevProductName) end
	return AllDevProducts[DevProductName].IsLoaded
end

-- Module Functions
function DevProducts.Has(DevProductName: string) : boolean
	return DEVPRODUCTS_RAW[DevProductName] ~= nil
end

function DevProducts.GetEarnedCoins(DevProductName: string)
	assert(DEVPRODUCTS_RAW[DevProductName], "DevProduct Name ("..DevProductName..") does not exist")
	return DEVPRODUCTS_RAW[DevProductName].EarnedCoins
end

function DevProducts.GetLayoutOrder(DevProductName: string)
	assert(DEVPRODUCTS_RAW[DevProductName], "DevProduct Name ("..DevProductName..") does not exist")
	return DEVPRODUCTS_RAW[DevProductName].LayoutOrder
end

function DevProducts.GetDevProductsRaw()
	return DEVPRODUCTS_RAW
end

function DevProducts.IsLoaded(DevProductName: string)
	assert(DEVPRODUCTS_RAW[DevProductName], "DevProduct Name ("..DevProductName..") does not exist")
	-- Not loaded = attempt reload
	if AllDevProducts[DevProductName].IsLoaded == false then LoadDevProduct(DevProductName) end

	return AllDevProducts[DevProductName].IsLoaded
end

function DevProducts.GetDevProductID(DevProductName: string)
	assert(DEVPRODUCTS_RAW[DevProductName], "DevProduct Name ("..DevProductName..") does not exist")
	return DEVPRODUCTS_RAW[DevProductName].ID
end

function DevProducts.GetNameFromID(DevProductID: number)
	assert(DEVPRODUCT_ID_FROM_NAME[DevProductID], "DevProduct ID ("..DevProductID..") does not exist")
	return DEVPRODUCT_ID_FROM_NAME[DevProductID]
end

function DevProducts.GetDisplayName(DevProductName: string)
	assert(DEVPRODUCTS_RAW[DevProductName], "DevProduct Name ("..DevProductName..") does not exist")
	if not GetSafe(DevProductName) then
		return "???"
	end
	-- Success
	return AllDevProducts[DevProductName].Name
end

function DevProducts.GetImage(DevProductName: string)
	assert(DEVPRODUCTS_RAW[DevProductName], "DevProduct Name ("..DevProductName..") does not exist")
	if not GetSafe(DevProductName) then
		return ""
	end
	-- Success
	return AllDevProducts[DevProductName].Image
end

function DevProducts.GetDescription(DevProductName: string)
	assert(DEVPRODUCTS_RAW[DevProductName], "DevProduct Name ("..DevProductName..") does not exist")
	if not GetSafe(DevProductName) then
		return "???"
	end
	-- Success
	return AllDevProducts[DevProductName].Description
end

function DevProducts.GetPrice(DevProductName: string)
	assert(DEVPRODUCTS_RAW[DevProductName], "DevProduct Name ("..DevProductName..") does not exist")
	if not GetSafe(DevProductName) then
		return 0
	end
	-- Success
	if AllDevProducts[DevProductName].IsForSale then
		return AllDevProducts[DevProductName].Price
	else
		return 0
	end
end

function DevProducts.IsForSale(DevProductName: string)
	assert(DEVPRODUCTS_RAW[DevProductName], "DevProduct Name ("..DevProductName..") does not exist")
	if not GetSafe(DevProductName) then
		return false
	end
	-- Success
	return AllDevProducts[DevProductName].IsForSale
end

-- Init
do
	-- Load Devproducts
	for DevProductName, Data in DEVPRODUCTS_RAW do
		DEVPRODUCT_ID_FROM_NAME[Data.ID] = DevProductName
		AllDevProducts[DevProductName] = {
			IsLoaded = false,
		}
		task.spawn(function()
			LoadDevProduct(DevProductName)
		end)
	end
end

return DevProducts
