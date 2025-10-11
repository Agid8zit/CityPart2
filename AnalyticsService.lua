local AnalyticsService = {}

-- Roblox Services
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxAnalyticsService = game:GetService("AnalyticsService")

-- Dependencies
--local Enums = shared.GetModule("Enums")
--local Remotes = shared.GetModule("Remotes")
--local DebugFlags = shared.GetModule("DebugFlags")

-- Defines
local SessionID = HttpService:GenerateGUID(false)

-- Module Functions
function AnalyticsService.LogEconomyEvent_GainedCoinsFromGame(Player: Player, CoinsGained: number, Category: string)
	if CoinsGained <= 0 then return end -- sometimes you can get zero coins
	
	--print("[Log Economy] Gained Coins "..CoinsGained.." from: "..Category)
	local Success, ErrMsg = pcall(function()
		if RunService:IsStudio() then return true end

		RobloxAnalyticsService:LogEconomyEvent(
			Player,
			Enum.AnalyticsEconomyFlowType.Source,
			"Coins", -- Currency name
			CoinsGained, -- Amount earned
			shared.GetModule("PlayerDataInterfaceService").GetCoins(Player), -- Current balance
			Enum.AnalyticsEconomyTransactionType.Gameplay.Name, -- Transaction type
			Category
		)
	end)
	if not Success then
		warn(ErrMsg)
	end
end

function AnalyticsService.LogEconomyEvent_SpentCoinsOnItem(Player: Player, CoinsSpent: number, PurchasedItemName: string)
	--print("[Log Economy] Spent Coins "..CoinsSpent.." on: "..PurchasedItemName)
	local Success, ErrMsg = pcall(function()
		if RunService:IsStudio() then return true end
		
		RobloxAnalyticsService:LogEconomyEvent(
			Player,
			Enum.AnalyticsEconomyFlowType.Sink,
			"Coins", -- Currency name
			CoinsSpent, -- Amount Spent
			shared.GetModule("PlayerDataInterfaceService").GetCoins(Player), -- Current balance
			Enum.AnalyticsEconomyTransactionType.Shop.Name, -- Transaction type
			PurchasedItemName
		)
	end)
	if not Success then
		warn(ErrMsg)
	end
end

function AnalyticsService.CustomEvent(Player: Player, CustomEventName: string)

	-- Ignore Studio
	if RunService:IsStudio() then
		print("[!] Studio Analytics - ["..Player.Name.."]["..CustomEventName.."]")
		return
	end
	
	local Success, ErrMsg = pcall(function()
		RobloxAnalyticsService:LogCustomEvent(
			Player,
			CustomEventName,
			1
		)
	end)
	if not Success then
		warn(ErrMsg)
	end
end

--function AnalyticsService.FunnelEventOnce(Player: Player, EventType: number, Step: number?)
--	-- Sanity
--	assert(EventType, "Nil Param was given for AnalyticsService.FunnlEventOnce")
--	if not Enums.ONE_TIME_FUNNELS_STR[EventType] then warn("bad custom event: "..tostring(EventType)) return end
	
--	if DebugFlags.DEBUG_PRINT_FUNNEL_EVENTS then
--		print("[Analytics](Server) -> Triggered OneTime Funnel ("..Enums.ONE_TIME_FUNNELS_STR[EventType]..")")
--	end
	
--	-- Avoid Duplicates
--	shared.GetModule("PlayerDataInterfaceService").CanDoOneTimeFunnelEvent(Player, EventType)
	
--	-- Ignore Studio
--	if RunService:IsStudio() then return end
	
--	local Success, ErrMsg = pcall(function()
--		RobloxAnalyticsService:LogFunnelStepEvent(
--			Player,
--			Enums.ONE_TIME_FUNNELS_STR[EventType], -- Funnel Name
--			SessionID,
--			Step or 1, -- Step #
--			Enums.ONE_TIME_FUNNELS_STR[EventType] -- Step Name
--		)
--	end)
--	if not Success then
--		warn(ErrMsg)
--	end
	
--	-- 4th param is custom fields, unused atm
--	-- example:
--	-- Levels: 1, 2, 3
--	-- Player class: Warrior, Mage, Archer
--	-- Weapon type: SMG, Pistol, Rocket Launcher

--	--local customFields = {

--	--	[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = "value1",

--	--	[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = "value2",

--	--	[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = "value3",

--	--}
--end



-- Networking
local Localizing = require(ReplicatedStorage.Localization.Localizing)
local SelectedLanguage = {} -- Player = LanguageName
ReplicatedStorage.Events.RemoteEvents.SetLanguage.OnServerEvent:Connect(function(Player: Player, LanguageName: string)

	if not Localizing.isValidLanguage(LanguageName) then return end
	
	SelectedLanguage[Player] = LanguageName
end)
task.spawn(function()
	while task.wait(60) do
		for Player, LanguageName in SelectedLanguage do
			AnalyticsService.CustomEvent(Player, "SetLanguage_"..LanguageName)
		end
		SelectedLanguage = {}
	end
end)

-- Player Events
game.Players.PlayerAdded:Connect(function(Player)
	AnalyticsService.CustomEvent(Player, "PLAYER_JOINED")
end)
game.Players.PlayerRemoving:Connect(function(Player)
	SelectedLanguage[Player] = nil
end)

return AnalyticsService
