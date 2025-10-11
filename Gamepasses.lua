local Gamepasses = {}

-- Roblox Services
local MarketplaceService = game:GetService("MarketplaceService")

-- type
type GamepassContent = {
	IsLoaded: boolean,
	IsForSale: boolean?,
	Name: string?,
	Image: string?,
	Description: string?,
	Price: number?,
}

-- Constants
local GAMEPASS_RAW = {
	-- Name = GamepassID
	["Boombox Music Player"] = {ID = 1288490257, LayoutOrder = 0};
	["x2 Population"] = {ID = 1285252572, LayoutOrder = 0};
	["x2 EXP"] = {ID = 1283096662, LayoutOrder = 0};
	["x2 Money"] = {ID = 1284316601, LayoutOrder = 0};
	["Premium World Maps"] = {ID = 1284994534, LayoutOrder = 0};
}
local GAMEPASS_ID_FROM_NAME = {} -- [GamepassID] = GamepassName


-- Defines
local AllGamepasses: {[string]: GamepassContent} = {} -- [GamepassName] = {Data}

-- Helper Functions
local function LoadGamepass(GamepassName: string)
	assert(GAMEPASS_RAW[GamepassName], "Gamepass Name ("..GamepassName..") does not exist")
	local GamepassID = GAMEPASS_RAW[GamepassName].ID
	
	local ProductInfo = nil
	local Success, ErrMsg = pcall(function()
		ProductInfo = MarketplaceService:GetProductInfo(GamepassID, Enum.InfoType.GamePass)
	end)
	if not Success then
		warn("Failed Gamepass ("..GamepassID..");"..ErrMsg)
	end

	if Success and ProductInfo then
		AllGamepasses[GamepassName] = {
			IsLoaded = true,
			IsForSale = ProductInfo.IsForSale or false,
			Name = ProductInfo.Name or "???",
			Image = "rbxassetid://"..(ProductInfo.IconImageAssetId or "0"),
			Description = ProductInfo.Description or "???",
			Price = ProductInfo.PriceInRobux or "???",
		}
	else
		AllGamepasses[GamepassName] = {
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
	--	["Created"] = "2024-03-25T11:30:22.027Z",
	--	["Creator"] =  ▶ {...},
	--	["Description"] = "Gives you a RPG spawner obstacle that you can place down in the obby! Each explosion ragdolls and blows away any players it hits!",
	--	["IconImageAssetId"] = 16866882231,
	--	["IsForSale"] = true,
	--	["IsLimited"] = false,
	--	["IsLimitedUnique"] = false,
	--	["IsNew"] = false,
	--	["IsPublicDomain"] = false,
	--	["MinimumMembershipLevel"] = 0,
	--	["Name"] = "RPG Giver!",
	--	["PriceInRobux"] = 989, -- only if IsForSale == true
	--	["ProductId"] = 1785882175,
	--	["ProductType"] = "Game Pass",
	--	["Sales"] = 0,
	--	["TargetId"] = 755209195,
	--	["Updated"] = "2024-03-25T11:30:40.35Z"
end

local function GetSafe(GamepassName: string)
	-- Not loaded = attempt reload
	if AllGamepasses[GamepassName].IsLoaded == false then LoadGamepass(GamepassName) end
	return AllGamepasses[GamepassName].IsLoaded
end

-- Module Functions
function Gamepasses.Has(GamepassName: string) : boolean
	return GAMEPASS_RAW[GamepassName] ~= nil
end

function Gamepasses.GetLayoutOrder(GamepassName: string)
	assert(GAMEPASS_RAW[GamepassName], "GamepassName Name ("..GamepassName..") does not exist in LayoutOrder Array")
	return GAMEPASS_RAW[GamepassName].LayoutOrder
end

function Gamepasses.GetGamepassesRaw()
	return GAMEPASS_RAW
end

function Gamepasses.IsLoaded(GamepassName: string)
	assert(GAMEPASS_RAW[GamepassName], "Gamepass Name ("..GamepassName..") does not exist")
	-- Not loaded = attempt reload
	if AllGamepasses[GamepassName].IsLoaded == false then LoadGamepass(GamepassName) end

	return AllGamepasses[GamepassName].IsLoaded
end

function Gamepasses.GetGamepassID(GamepassName: string)
	assert(GAMEPASS_RAW[GamepassName], "Gamepass Name ("..GamepassName..") does not exist")
	return GAMEPASS_RAW[GamepassName].ID
end

function Gamepasses.GetNameFromID(GamepassID: number)
	assert(GAMEPASS_ID_FROM_NAME[GamepassID], "Gamepass ID ("..GamepassID..") does not exist")
	return GAMEPASS_ID_FROM_NAME[GamepassID]
end

function Gamepasses.GetDisplayName(GamepassName: string)
	assert(GAMEPASS_RAW[GamepassName], "Gamepass Name ("..GamepassName..") does not exist")
	if not GetSafe(GamepassName) then
		return "???"
	end
	-- Success
	return AllGamepasses[GamepassName].Name
end

function Gamepasses.GetImage(GamepassName: string)
	assert(GAMEPASS_RAW[GamepassName], "Gamepass Name ("..GamepassName..") does not exist")
	if not GetSafe(GamepassName) then
		return ""
	end
	-- Success
	return AllGamepasses[GamepassName].Image
end

function Gamepasses.GetDescription(GamepassName: string)
	assert(GAMEPASS_RAW[GamepassName], "Gamepass Name ("..GamepassName..") does not exist")
	if not GetSafe(GamepassName) then
		return "???"
	end
	-- Success
	return AllGamepasses[GamepassName].Description
end

function Gamepasses.GetPrice(GamepassName: string)
	assert(GAMEPASS_RAW[GamepassName], "Gamepass Name ("..GamepassName..") does not exist")
	if not GetSafe(GamepassName) then
		return 0
	end
	-- Success
	if AllGamepasses[GamepassName].IsForSale then
		return AllGamepasses[GamepassName].Price
	else
		return 0
	end
end

function Gamepasses.IsForSale(GamepassName: string)
	assert(GAMEPASS_RAW[GamepassName], "Gamepass Name ("..GamepassName..") does not exist")
	if not GetSafe(GamepassName) then
		return false
	end
	-- Success
	return AllGamepasses[GamepassName].IsForSale
end

-- Init
do
	-- Load gamepasses
	for GamepassName, Data in GAMEPASS_RAW do
		GAMEPASS_ID_FROM_NAME[Data.ID] = GamepassName
		-- Default
		AllGamepasses[GamepassName] = {
			IsLoaded = false,
		}
		task.spawn(function()
			LoadGamepass(GamepassName)
		end)
	end
end

return Gamepasses
