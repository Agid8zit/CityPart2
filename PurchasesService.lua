local PurchasesService = {}

-- Roblox Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local ServerScriptService = game:GetService("ServerScriptService")

-- Dependencies
local Gamepasses = require(ReplicatedStorage.Scripts.Gamepasses)
local DevProducts = require(ReplicatedStorage.Scripts.DevProducts)
local PlayerDataInterfaceService = require(ServerScriptService.Services.PlayerDataInterfaceService)

-- Constants
local GAMEPASS_RESOLVE = {
	--
	["Boombox Music Player"] = function(Player)
		-- Example
		Player:SetAttribute("HasBoomboxMusicPlayer", true)
	end;
	["x2 Population"] =function(Player)
		-- Example
	end;
	["x2 EXP"] = function(Player)
		-- Example
	end;
	["x2 Money"] = function(Player)
		-- Example
	end;
	["Premium World Maps"] = function(Player)
		-- Example
	end;
}
local GAMEPASS_REMOVED = {
	--
	["Boombox Music Player"] = function(Player)
		-- Example
		Player:SetAttribute("HasBoomboxMusicPlayer", nil)
	end;
}

local DEVPRODUCTS_RESOLVE = {
	--
	["Coin Option1"] = function(Player)
		local CoinsToAward = DevProducts.GetEarnedCoins("Coin Option1")
		PlayerDataInterfaceService.IncrementCoinsInSaveData(Player, CoinsToAward)
	end;
	["Coin Option2"] = function(Player)
		local CoinsToAward = DevProducts.GetEarnedCoins("Coin Option2")
		PlayerDataInterfaceService.IncrementCoinsInSaveData(Player, CoinsToAward)
	end;
	["Coin Option3"] = function(Player)
		local CoinsToAward = DevProducts.GetEarnedCoins("Coin Option3")
		PlayerDataInterfaceService.IncrementCoinsInSaveData(Player, CoinsToAward)
	end;
	["Coin Option4"] = function(Player)
		local CoinsToAward = DevProducts.GetEarnedCoins("Coin Option4")
		PlayerDataInterfaceService.IncrementCoinsInSaveData(Player, CoinsToAward)
	end;
	["Coin Option5"] = function(Player)
		local CoinsToAward = DevProducts.GetEarnedCoins("Coin Option5")
		PlayerDataInterfaceService.IncrementCoinsInSaveData(Player, CoinsToAward)
	end;
	["Coin Option6"] = function(Player)
		local CoinsToAward = DevProducts.GetEarnedCoins("Coin Option6")
		PlayerDataInterfaceService.IncrementCoinsInSaveData(Player, CoinsToAward)
	end;
	
	["FirePrecinct"] = function(Player)
		PlayerDataInterfaceService.IncrementExclusiveLocation(Player, "FirePrecinct", 1)
	end,
	["PolicePrecinct"] = function(Player)
		PlayerDataInterfaceService.IncrementExclusiveLocation(Player, "PolicePrecinct", 1)
	end,
	["MajorHospital"] = function(Player)
		PlayerDataInterfaceService.IncrementExclusiveLocation(Player, "MajorHospital", 1)
	end,
	["Museum"] = function(Player)
		PlayerDataInterfaceService.IncrementExclusiveLocation(Player, "Museum", 1)
	end,
	["FootballStadium"] = function(Player)
		PlayerDataInterfaceService.IncrementExclusiveLocation(Player, "FootballStadium", 1)
	end,
	["StatueOfLiberty"] = function(Player)
		PlayerDataInterfaceService.IncrementExclusiveLocation(Player, "StatueOfLiberty", 1)
	end,
	["EiffelTower"] = function(Player)
		PlayerDataInterfaceService.IncrementExclusiveLocation(Player, "EiffelTower", 1)
	end,
	["NuclearPowerPlant"] = function(Player)
		PlayerDataInterfaceService.IncrementExclusiveLocation(Player, "NuclearPowerPlant", 1)
	end,
	["MolecularWaterPlant"] = function(Player)
		PlayerDataInterfaceService.IncrementExclusiveLocation(Player, "MolecularWaterPlant", 1)
	end,
	["SaveSlot+1"] = function(Player) -- example product name; adjust to your catalog
		-- increment PlayerWide.saveSlots.purchased by 1
		local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
		local pd = PlayerDataService.GetData(Player)
		if not pd then return end
		pd.PlayerWide = pd.PlayerWide or {}
		pd.PlayerWide.saveSlots = pd.PlayerWide.saveSlots or {}
		pd.PlayerWide.saveSlots.purchased = tonumber(pd.PlayerWide.saveSlots.purchased) or 0
		pd.PlayerWide.saveSlots.purchased += 1
		-- recompute total/used
		local ss = pd.PlayerWide.saveSlots
		ss.default = tonumber(ss.default) or 1
		ss.bonus   = tonumber(ss.bonus) or 0
		ss.total   = ss.default + ss.purchased + ss.bonus

		-- push to client
		PlayerDataService.ModifyData(Player, nil, pd)
	end,

	["NewStyles"] = function(Player)
		-- grant global style ownership (account-wide)
		local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
		local pd = PlayerDataService.GetData(Player)
		if not pd then return end
		pd.PlayerWide = pd.PlayerWide or {}
		pd.PlayerWide.styles = pd.PlayerWide.styles or { owned = {}, equipped = "" }
		pd.PlayerWide.styles.owned = pd.PlayerWide.styles.owned or {}
		pd.PlayerWide.styles.owned["NeoCity"] = true

		-- OPTIONAL: auto-equip if nothing equipped
		if pd.PlayerWide.styles.equipped == "" then
			pd.PlayerWide.styles.equipped = "NeoCity"
		end

		PlayerDataService.ModifyData(Player, nil, pd)
	end,
}

-- Defines
local RNG = Random.new()
local SavedReceipts_DS = nil;
local FailedDevProductSaves = {}

-- Helper Functions
local function PurchaseFanFareForPlayer(Player: Player)
	---- VFX
	--task.spawn(function()
	--	ParticleGuiService.SpawnPreset(Player, "FallingScore")
	--	ParticleGuiService.SpawnPreset(Player, "FallingCoins")
	--	task.wait(0.15)
	--	ParticleGuiService.SpawnPreset(Player, "FallingScore")
	--	ParticleGuiService.SpawnPreset(Player, "FallingCoins")
	--	task.wait(0.15)
	--	ParticleGuiService.SpawnPreset(Player, "FallingScore")
	--	ParticleGuiService.SpawnPreset(Player, "FallingCoins")

	--end)
	---- More VFX
	--for _ = 1, 5 do
	--	local Pos = Vector2.new(
	--		RNG:NextNumber(0.2, 0.8),
	--		RNG:NextNumber(0.1, 0.6)
	--	) 
	--	ParticleGuiService.SpawnPreset(Player, "SimpleConfetti", Pos)
	--end

	---- SFX
	--SoundService.PlaySoundOnceForPlayer(Player, "Misc", "Cha-ching")
	--SoundService.PlaySoundOnceForPlayer(Player, "Misc", "Awarded")
end

-- Module Functions
function PurchasesService.HandleGamepassPurchased(Player: Player, GamepassID: number)
	local GamepassName = Gamepasses.GetNameFromID(GamepassID)
	PlayerDataInterfaceService.GiveGamepass(Player, GamepassName)
	print("SET player data's owned gamepasses ("..GamepassID..")")
	
	-- Dedicated Logic
	if GAMEPASS_RESOLVE[GamepassName] then
		GAMEPASS_RESOLVE[GamepassName](Player)
	end
	
	-- Analytics
	--AnalyticsService.CustomEvent(Player, Enums.CUSTOM_EVENT.BOUGHT_A_GAMEPASS)
end

function PurchasesService.HandleGamepassRemoved(Player: Player, GamepassID: number)
	local GamepassName = Gamepasses.GetNameFromID(GamepassID)
	PlayerDataInterfaceService.RemoveGamepass(Player, GamepassName)
	print("REMOVE player data's owned gamepasses ("..GamepassID..")")
	
	if GAMEPASS_REMOVED[GamepassName] then
		GAMEPASS_REMOVED[GamepassName](Player)
	end
end

function PurchasesService.HandleDevProductPurchased(Player: Player, ProductID: number)
	local DevProductName = DevProducts.GetNameFromID(ProductID)
	
	-- Dedicated Logic
	if DEVPRODUCTS_RESOLVE[DevProductName] then
		DEVPRODUCTS_RESOLVE[DevProductName](Player)
	end
	
	-- Analytics
	--AnalyticsService.CustomEvent(Player, Enums.CUSTOM_EVENT.BOUGHT_A_DEVPRODUCT)
end

function PurchasesService.Init()
	if not SavedReceipts_DS then
		SavedReceipts_DS = require(ServerScriptService.DataStore.DataStoreClass).new("SavedReceipts")
	end
end

-- Init
do
	-- Gamepass Bought
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(Player: Player, GamepassID: number, WasPurchased: boolean)
		local HandlePurchase = WasPurchased

		-- If not purchased, fallback to check if they own it from api, this is a roblox recommended action
		if not HandlePurchase then
			-- Owns it in store
			local Success, Result = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(Player.UserId, GamepassID)
			end)
			if Success then	
				HandlePurchase = Result
			end
		end

		if HandlePurchase then
			-- Give
			PurchasesService.HandleGamepassPurchased(Player, GamepassID)
			
			-- Special Case
			PlayerDataInterfaceService.PlayerBoughtSomething(Player)
			
			-- VFX + SFX
			PurchaseFanFareForPlayer(Player)

			print("[Gamepass] Gave In-game Gamepass ("..Gamepasses.GetNameFromID(GamepassID)..") to Player ("..Player.Name..")")
		else
			print("[Gamepass] Player ("..Player.Name..") did not receive a Gamepass ("..Gamepasses.GetNameFromID(GamepassID)..")")
		end
	end)
	
	-- DevProduct Bought
	MarketplaceService.ProcessReceipt = function(ReceiptInfo)
		if ReceiptInfo == nil then return Enum.ProductPurchaseDecision.NotProcessedYet end
		
		-- Player must be in the server
		local Player = Players:GetPlayerByUserId(ReceiptInfo.PlayerId)
		if not Player then
			warn("Failed to Acquire Player by UserID ("..ReceiptInfo.PlayerId..") for DevProduct Purchse")
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		
		if not RunService:IsStudio() then
			if SavedReceipts_DS == nil then return Enum.ProductPurchaseDecision.NotProcessedYet end
			
			-- Unique PurchaseID
			local UniquePurchaseID = ReceiptInfo.PlayerId .. "_" .. os.time() --.. "_" .. ReceiptInfo.PurchaseId
			local PurchaseData, Success = SavedReceipts_DS:GetAsync(UniquePurchaseID)

			-- Unique PurchaseID duplicate
			if PurchaseData ~= nil then return Enum.ProductPurchaseDecision.NotProcessedYet end

			-- PURCHASE GOOD --
			-------------------

			-- Save to a datastore
			_, Success = SavedReceipts_DS:SetAsync(UniquePurchaseID, {
				ProductId = ReceiptInfo.ProductId or "?",
				CurrencySpent = ReceiptInfo.CurrencySpent or "?",
				TimeStamp = os.date(),
			})
			if not Success then
				warn("Failed to save PurchaseID for ("..ReceiptInfo.PlayerId.."), ProductId: ("..ReceiptInfo.ProductId.."), Currency: ("..ReceiptInfo.CurrencySpent..")")
				table.insert(FailedDevProductSaves, {
					UniquePurchaseID = UniquePurchaseID,
					PlayerId = ReceiptInfo.PlayerId,
					PurchaseId = ReceiptInfo.PurchaseId,
					ProductId = ReceiptInfo.ProductId or "?",
					CurrencySpent = ReceiptInfo.CurrencySpent or "?",
				})
			else
				print("[!] Saved DevProduct Purchase in DataStore")
			end
		end
		
		print("[DevProduct] Gave In-game Devproduct ("..DevProducts.GetNameFromID(ReceiptInfo.ProductId)..") to Player ("..Player.Name..")")
		
		-- Player Data in Server
		PurchasesService.HandleDevProductPurchased(Player, ReceiptInfo.ProductId)
		
		-- Special Case
		PlayerDataInterfaceService.PlayerBoughtSomething(Player)
		
		-- VFX + SFX
		PurchaseFanFareForPlayer(Player)
		
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	
	-- Check Failed DevProduct purchases
	local CheckFailedDevproductTimer = 0
	RunService.Heartbeat:Connect(function()
		-- Debounce Timer
		if os.clock() < CheckFailedDevproductTimer then return end
		CheckFailedDevproductTimer = os.clock() + 3
		
		if #FailedDevProductSaves == 0 then return end -- Nothing to check
		
		local _FailedDevProductSaves = FailedDevProductSaves;
		FailedDevProductSaves = {}
		
		for _, Data in _FailedDevProductSaves do
			local _, Success = SavedReceipts_DS:SetAsync(Data.UniquePurchaseID, {
				ProductId = Data.ProductId,
				CurrencySpent = Data.CurrencySpent,
			})
			if not Success then
				warn("Failed to save PurchaseID for ("..Data.PlayerId.."), ProductId: ("..Data.ProductId.."), Currency: ("..Data.CurrencySpent..") - retry attempt")
				table.insert(FailedDevProductSaves, Data)
			end
		end
		
	end)
end

return PurchasesService
