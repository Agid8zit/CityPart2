-- Game Specific Logic for PlayerData
local PlayerDataInterfaceService = {}

-- Roblox Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local ServerScriptService = game:GetService("ServerScriptService")

-- Dependencies
local Constants = require(ReplicatedStorage.Scripts.Constants)
local Gamepasses = require(ReplicatedStorage.Scripts.Gamepasses)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local BadgeServiceModule = require(ServerScriptService.Services.BadgeService)
local OnboardingServiceOk, OnboardingService = pcall(function()
	return require(ServerScriptService.Players.OnboardingService)
end)
if not OnboardingServiceOk then
	OnboardingService = nil
end

local EventsFolder = ReplicatedStorage:WaitForChild("Events")
local BindableEvents = EventsFolder:WaitForChild("BindableEvents")
local function ensureBE(name: string): BindableEvent
	local be = BindableEvents:FindFirstChild(name)
	if be and be:IsA("BindableEvent") then
		return be
	end
	local nb = Instance.new("BindableEvent")
	nb.Name = name
	nb.Parent = BindableEvents
	return nb
end
local ForceDisableOnboardingBE: BindableEvent = ensureBE("ForceDisableOnboarding")

local MoneyBadgeThresholds = {
	{ amount = 1000000000, award = BadgeServiceModule.AwardMoney1B },
	{ amount = 100000000,  award = BadgeServiceModule.AwardMoney100M },
	{ amount = 1000000,    award = BadgeServiceModule.AwardMoney1M },
	{ amount = 100000,     award = BadgeServiceModule.AwardMoney100K },
	{ amount = 10000,      award = BadgeServiceModule.AwardMoney10K },
}

local function checkMoneyBadges(player, amount)
	if not player or type(amount) ~= "number" then return end
	for _, entry in ipairs(MoneyBadgeThresholds) do
		if amount >= entry.amount then
			entry.award(player)
		end
	end
end

-- ======================================================================
-- Transit helpers (per-tier schema normalized to NUMERIC levels)
-- ======================================================================
local MAX_TIERS = 10
local MAX_TIER_LEVEL = 100
local LEVELS_PER_TIER_UNLOCK = 3

local function _ensureTransitNode(saveFile, key) -- key = "busDepot" | "airport"
	saveFile.transit = saveFile.transit or {}
	local node = saveFile.transit[key]
	if typeof(node) ~= "table" then
		node = { unlock = 0, tiers = { [1] = 0 } }
		saveFile.transit[key] = node
	else
		node.unlock = tonumber(node.unlock) or 0
		if typeof(node.tiers) ~= "table" then
			node.tiers = { [1] = 0 }
		elseif node.tiers[1] == nil then
			node.tiers[1] = 0
		end
		-- Normalize legacy object shape {level = n} -> numeric n
		for ti, rec in pairs(node.tiers) do
			if typeof(rec) == "table" then
				local lv = tonumber(rec.level) or 0
				node.tiers[ti] = math.clamp(lv, 0, MAX_TIER_LEVEL)
			else
				node.tiers[ti] = math.clamp(tonumber(rec) or 0, 0, MAX_TIER_LEVEL)
			end
		end
	end
	return node
end

local function _unlockedTiers(unlock)
	local t = math.floor(math.max(0, tonumber(unlock) or 0) / LEVELS_PER_TIER_UNLOCK) + 1
	return math.clamp(t, 1, MAX_TIERS)
end

-- Module Functions
function PlayerDataInterfaceService.OnLoad(Player: Player, PlayerData)
	-- Round any currency decimals
	--PlayerData.Coins = math.round(PlayerData.Coins)
	warn("!!! START WITH EVERYTHING FOR TESTING !!!")

	PlayerData.OwnedBadges = PlayerData.OwnedBadges or {}
	local SaveFile = PlayerData.savefiles[PlayerData.currentSaveFile]
	if SaveFile and SaveFile.economy then
		checkMoneyBadges(Player, SaveFile.economy.money or 0)
	end

	_ensureTransitNode(SaveFile, "busDepot")
	_ensureTransitNode(SaveFile, "airport")
	-- ==================================================================

	SaveFile.xp         = 9999999
	SaveFile.cityLevel  = 26
	SaveFile.economy = {
		money        = 9950000,
		bustickets   = 3000000,
		planetickets = 3000000,
	}
	SaveFile.exclusiveLocations = {
		["FirePrecinct"] = 420,
		["PolicePrecinct"] = 420,
		["MajorHospital"] = 420,
		["Museum"] = 420,
		["FootballStadium"] = 420,
		["StatueOfLiberty"] = 420,
		["EiffelTower"] = 420,
		["NuclearPowerPlant"] = 420,
		["MolecularWaterPlant"] = 420,
	}

	return PlayerData
end

function PlayerDataInterfaceService.OnSave(Player: Player, PlayerData)
	-- Flag FirstTimeJoined as false
	--PlayerData.FirstTimeJoined = false
	return PlayerData
end

function PlayerDataInterfaceService.PlayerLeavingAfterSaving(Player: Player)

end

function PlayerDataInterfaceService.HasGamepass(Player: Player, GamepassName: string)
	assert(Gamepasses.Has(GamepassName), "Gamepass Not Found ("..GamepassName..")")
	--
	local PlayerData = PlayerDataService.AllPlayerData[Player]
	if not PlayerData then return end

	return PlayerData.OwnedGamepasses[GamepassName]
end

function PlayerDataInterfaceService.RemoveGamepass(Player: Player, GamepassName: string)
	assert(Gamepasses.Has(GamepassName), "Gamepass Not Found ("..GamepassName..")")
	--
	local PlayerData = PlayerDataService.AllPlayerData[Player]
	if not PlayerData then return end
	-- not owned
	if not PlayerData.OwnedGamepasses[GamepassName] then return end

	PlayerDataService.ModifyData(Player, "OwnedGamepasses/"..GamepassName, nil) -- own
end

function PlayerDataInterfaceService.GiveGamepass(Player: Player, GamepassName: string)
	assert(Gamepasses.Has(GamepassName), "Gamepass Not Found ("..GamepassName..")")
	--
	local PlayerData = PlayerDataService.AllPlayerData[Player]
	if not PlayerData then return end
	-- already owned
	if PlayerData.OwnedGamepasses[GamepassName] then return end

	PlayerDataService.ModifyData(Player, "OwnedGamepasses/"..GamepassName, true) -- own
end

function PlayerDataInterfaceService.GiveMissingGamepasses(Player: Player)
	-- Data check
	local PlayerData = PlayerDataService.AllPlayerData[Player]
	if not PlayerData then return end

	-- If a Player bought a gamepass from the web store or they had data issues, give them the gamepass manually
	for GamepassName, Data in Gamepasses.GetGamepassesRaw() do
		local GamepassID = Data.ID

		-- If already own, ignore
		--print(Player, GamepassName, GamepassID)
		if PlayerData.OwnedGamepasses[GamepassName] then continue end

		-- Owns it in store
		local Success, Result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(Player.UserId, GamepassID)
		end)
		--print(Success, Result)
		if Success and Result then
			print("[Gamepass] Gave Online Gamepass ("..GamepassName..") to Player ("..Player.Name..")")
			--PlayerDataService.ModifyData(Player, "OwnedGamepasses/"..GamepassName, true) -- own
			require(ServerScriptService.Services.PurchasesService).HandleGamepassPurchased(Player, GamepassID)
		end
	end
end

function PlayerDataInterfaceService.GiveBadge(Player: Player, BadgeKey: string)
	local success, reason = BadgeServiceModule.Award(Player, BadgeKey)
	if not success then
		warn(string.format("[PlayerDataInterface] Failed to award badge %s to %s (%s)", BadgeKey, Player.Name, tostring(reason)))
	end
	return success, reason
end

function PlayerDataInterfaceService.GiveMissingBadges(Player: Player)
	BadgeServiceModule.SyncOwnedBadges(Player)
	BadgeServiceModule.AwardFirstSession(Player)
end

function PlayerDataInterfaceService.GetCoinsInSaveData(Player: Player)
	-- Data check
	local PlayerData = PlayerDataService.AllPlayerData[Player]
	if not PlayerData then return end

	local saveFile = PlayerData.savefiles[PlayerData.currentSaveFile]
	if not saveFile then return false end

	return saveFile.economy.money
end

local RE_PlayerDataChanged_Money = ReplicatedStorage.Events.RemoteEvents.PlayerDataChanged_Money
function PlayerDataInterfaceService.IncrementCoinsInSaveData(Player: Player, IncrementAmount: number)
	-- Data check
	local PlayerData = PlayerDataService.AllPlayerData[Player]
	if not PlayerData then return end

	local saveFile = PlayerData.savefiles[PlayerData.currentSaveFile]
	if not saveFile then return false end

	local Coins = (saveFile.economy.money or 0) + (IncrementAmount or 0)
	PlayerDataService.ModifySaveData(Player, "economy/money", Coins)

	RE_PlayerDataChanged_Money:FireClient(Player, Coins)
	checkMoneyBadges(Player, Coins)
end

function PlayerDataInterfaceService.SetCoinsInSaveData(Player: Player, NewAmount: number)
	local PlayerData = PlayerDataService.AllPlayerData[Player]
	if not PlayerData then return end

	local saveFile = PlayerData.savefiles[PlayerData.currentSaveFile]
	if not saveFile then return false end

	local clamped = math.max(0, tonumber(NewAmount) or 0)
	PlayerDataService.ModifySaveData(Player, "economy/money", clamped)
	RE_PlayerDataChanged_Money:FireClient(Player, clamped)
	checkMoneyBadges(Player, clamped)
end

-- Relative adjust (used by EconomyService.adjustBalance)
function PlayerDataInterfaceService.AdjustCoinsInSaveData(Player: Player, Delta: number)
	-- Reuse Increment path; both fire the RemoteEvent
	PlayerDataInterfaceService.IncrementCoinsInSaveData(Player, Delta or 0)
end

local RE_PlayerDataChanged_PlaneTickets = ReplicatedStorage.Events.RemoteEvents.PlayerDataChanged_PlaneTickets
function PlayerDataInterfaceService.IncrementPlaneTicketsInSaveData(Player: Player, IncrementAmount: number)
	-- Data check
	local PlayerData = PlayerDataService.AllPlayerData[Player]
	if not PlayerData then return end

	local saveFile = PlayerData.savefiles[PlayerData.currentSaveFile]
	if not saveFile then return false end

	local Coins = (saveFile.economy.planetickets or 0) + (IncrementAmount or 0)
	PlayerDataService.ModifySaveData(Player, "economy/planetickets", Coins)

	RE_PlayerDataChanged_PlaneTickets:FireClient(Player, Coins)
end

local RE_PlayerDataChanged_BusTickets = ReplicatedStorage.Events.RemoteEvents.PlayerDataChanged_BusTickets
function PlayerDataInterfaceService.IncrementBusTicketsInSaveData(Player: Player, IncrementAmount: number)
	-- Data check
	local PlayerData = PlayerDataService.AllPlayerData[Player]
	if not PlayerData then return end

	local saveFile = PlayerData.savefiles[PlayerData.currentSaveFile]
	if not saveFile then return false end

	local Coins = (saveFile.economy.bustickets or 0) + (IncrementAmount or 0)
	PlayerDataService.ModifySaveData(Player, "economy/bustickets", Coins)

	RE_PlayerDataChanged_BusTickets:FireClient(Player, Coins)
end

local RE_PlayerDataChanged_ExclusiveLocations = ReplicatedStorage.Events.RemoteEvents.PlayerDataChanged_ExclusiveLocations
function PlayerDataInterfaceService.IncrementExclusiveLocation(Player: Player, ExclusiveLocationName: string, IncrementAmount: number)
	-- Data check
	local PlayerData = PlayerDataService.AllPlayerData[Player]
	if not PlayerData then return end

	local saveFile = PlayerData.savefiles[PlayerData.currentSaveFile]
	if not saveFile then return false end

	local CurrentAmount = saveFile.exclusiveLocations[ExclusiveLocationName]
	if CurrentAmount == nil then
		error("Invalid Exclusive Location! ".. ExclusiveLocationName)
	end

	PlayerDataService.ModifySaveData(Player, "exclusiveLocations/"..ExclusiveLocationName, CurrentAmount + (IncrementAmount or 0))
	RE_PlayerDataChanged_ExclusiveLocations:FireClient(Player, ExclusiveLocationName, CurrentAmount + (IncrementAmount or 0))
end

function PlayerDataInterfaceService.GetExclusiveLocationAmount(Player: Player, ExclusiveLocationName: string)
	-- Data check
	local PlayerData = PlayerDataService.AllPlayerData[Player]
	if not PlayerData then return end

	local saveFile = PlayerData.savefiles[PlayerData.currentSaveFile]
	if not saveFile then return 0 end

	return saveFile.exclusiveLocations[ExclusiveLocationName]
end

function PlayerDataInterfaceService.PlayerBoughtSomething(Player: Player)
	-- Data check
	local PlayerData = PlayerDataService.AllPlayerData[Player]
	if not PlayerData then return end

	-- If first check
	if PlayerData.hasBoughtSomethingWithRobux == 0 then
		-- Networking
		local RE_ThanksForSupportingUs = ReplicatedStorage.Events.RemoteEvents.ThanksForSupportingUs
		RE_ThanksForSupportingUs:FireClient(Player)
	end

	PlayerDataService.ModifyData(Player, "hasBoughtSomethingWithRobux", (PlayerData.hasBoughtSomethingWithRobux or 0) + 1)
end

-- [GAME] --
local RF_DeleteSaveFile = ReplicatedStorage.Events.RemoteEvents.DeleteSaveFile
RF_DeleteSaveFile.OnServerInvoke = function(Player: Player, SlotID: string)
	local PlayerData = PlayerDataService.GetData(Player)
	if not PlayerData then return false end
	if not PlayerData.savefiles[SlotID] then return false end

	local function markDeletionDuringOnboarding()
		if OnboardingService then
			local okRecord, err = pcall(function()
				OnboardingService.RecordDeletionDuringOnboarding(Player.UserId, Player)
			end)
			if not okRecord then
				warn("[PlayerDataInterface] RecordDeletionDuringOnboarding failed: ", err)
			end
		else
			warn("[PlayerDataInterface] OnboardingService missing; forcing disable only")
		end
		ForceDisableOnboardingBE:Fire(Player)
	end

	-- remove the slot
	PlayerDataService.ModifyData(Player, "savefiles/"..SlotID, nil)

	-- if deleting current slot, recreate a fresh one in the same position
	if PlayerData.currentSaveFile == SlotID then
		markDeletionDuringOnboarding()
		local DefaultDataModule = require(ServerScriptService.PlayerDataService.DefaultData)
		local EmptySaveFile = DefaultDataModule.newSaveFile()
		EmptySaveFile.cityName = ""
		PlayerDataService.ModifyData(Player, "savefiles/"..SlotID, EmptySaveFile)
	end
	return true
end

local RF_CreateSaveFile = ReplicatedStorage.Events.RemoteEvents.CreateSaveFile
RF_CreateSaveFile.OnServerInvoke = function(Player: Player, SlotID: string)
	local PlayerData = PlayerDataService.GetData(Player)
	if not PlayerData then return false end

	local SlotIndex = tonumber(SlotID)
	if not SlotIndex then return false end
	if SlotIndex < 1 or SlotIndex > Constants.MAX_SAVE_FILES then return false end

	-- already exists
	if PlayerData.savefiles[SlotID] then return false end

	-- create new save file via factory (avoids shared nested tables)
	local DefaultDataModule = require(ServerScriptService.PlayerDataService.DefaultData)
	local EmptySaveFile = DefaultDataModule.newSaveFile()
	PlayerDataService.ModifyData(Player, "savefiles/"..SlotID, EmptySaveFile)
	return true
end

local RF_LoadSaveFile = ReplicatedStorage.Events.RemoteEvents.LoadSaveFile
RF_LoadSaveFile.OnServerInvoke = function(Player: Player, SlotID: string)
	local PlayerData = PlayerDataService.GetData(Player)
	if not PlayerData then return false end
	if not PlayerData.savefiles[SlotID] then return false end

	-- 1) Flush current slot to avoid writing to the wrong one after we switch
	PlayerDataService.SaveFlush(Player, "SwitchToSlot:pre")
	PlayerDataService.WaitForSavesToDrain(Player, 15)

	-- 2) Switch the active slot
	PlayerDataService.ModifyData(Player, "currentSaveFile", SlotID)

	-- 3) Tell SaveManager to wipe and reload from the *current* slot
	local BEFolder = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("BindableEvents")
	local ReloadBE = BEFolder and BEFolder:FindFirstChild("RequestReloadFromCurrent")
	if ReloadBE and ReloadBE:IsA("BindableEvent") then
		ReloadBE:Fire(Player)
	else
		warn("[RF_LoadSaveFile] RequestReloadFromCurrent not found; world will not be reloaded!")
	end
	return true
end

-- Player Changed
function PlayerDataInterfaceService.PlayerAdded(Player: Player)

end

function PlayerDataInterfaceService.PlayerRemoved(Player: Player)

end

-- ======================================================================
-- [ADDED] Optional public helpers (non-breaking; ignore if you don’t need)
-- ======================================================================
function PlayerDataInterfaceService.GetTransitUnlock(Player: Player, mode: "busDepot"|"airport")
	local pd = PlayerDataService.AllPlayerData[Player]; if not pd then return 0 end
	local sf = pd.savefiles[pd.currentSaveFile]; if not sf then return 0 end
	return _ensureTransitNode(sf, mode).unlock
end

function PlayerDataInterfaceService.SetTransitUnlock(Player: Player, mode: "busDepot"|"airport", unlock: number)
	local pd = PlayerDataService.AllPlayerData[Player]; if not pd then return end
	local sf = pd.savefiles[pd.currentSaveFile]; if not sf then return end
	local node = _ensureTransitNode(sf, mode)
	unlock = math.max(0, math.floor(tonumber(unlock) or 0))
	if node.unlock ~= unlock then
		node.unlock = unlock
		PlayerDataService.ModifySaveData(Player, ("transit/%s/unlock"):format(mode), node.unlock)
	end
end

function PlayerDataInterfaceService.GetTransitTierLevel(Player: Player, mode: "busDepot"|"airport", tierIndex: number)
	local pd = PlayerDataService.AllPlayerData[Player]; if not pd then return 0 end
	local sf = pd.savefiles[pd.currentSaveFile]; if not sf then return 0 end
	local node = _ensureTransitNode(sf, mode)

	local ti = math.clamp(math.floor(tonumber(tierIndex) or 1), 1, MAX_TIERS)
	local need = math.clamp(math.floor((node.unlock or 0) / LEVELS_PER_TIER_UNLOCK) + 1, 1, MAX_TIERS)

	if node.tiers[ti] == nil and ti <= need then node.tiers[ti] = 0 end
	return tonumber(node.tiers[ti]) or 0
end

function PlayerDataInterfaceService.SetTransitTierLevel(Player: Player, mode: "busDepot"|"airport", tierIndex: number, newLevel: number)
	local pd = PlayerDataService.AllPlayerData[Player]; if not pd then return end
	local sf = pd.savefiles[pd.currentSaveFile]; if not sf then return end
	local node = _ensureTransitNode(sf, mode)

	local ti = math.clamp(math.floor(tonumber(tierIndex) or 1), 1, MAX_TIERS)
	local need = math.clamp(math.floor((node.unlock or 0) / LEVELS_PER_TIER_UNLOCK) + 1, 1, MAX_TIERS)
	if ti > need then return end

	local clamped = math.clamp(tonumber(newLevel) or 0, 0, MAX_TIER_LEVEL)
	if tonumber(node.tiers[ti]) ~= clamped then
		node.tiers[ti] = clamped
		-- IMPORTANT: numeric value path (no /level)
		PlayerDataService.ModifySaveData(Player, ("transit/%s/tiers/%d"):format(mode, ti), clamped)
	end
end

return PlayerDataInterfaceService
