local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local S3      = game:GetService("ServerScriptService")

local Events  = RS:WaitForChild("Events")
local RE      = Events:WaitForChild("RemoteEvents")
local SetLanguage = RE:WaitForChild("SetLanguage")

local UI = S3:WaitForChild("UI")

local PlayerDataService = require(S3.Services.PlayerDataService)
local Localizing        = require(RS.Localization.Localizing)

local function reseedCivBubblesFor(player: Player)
	-- Use the same BindableEvent the bubble script created
	local BE = RS:WaitForChild("Events"):WaitForChild("BindableEvents")
	local RequestRandomBubbleLine = BE:WaitForChild("RequestRandomBubbleLine")

	local plots = workspace:FindFirstChild("PlayerPlots")
	local plot  = plots and plots:FindFirstChild("Plot_" .. player.UserId)
	if not plot then
		warn(("[LangSwitch] No plot found for %s (%d)"):format(player.Name, player.UserId))
		return
	end

	local seeded = 0
	for _, mdl in ipairs(plot:GetDescendants()) do
		if mdl:IsA("Model")
			and mdl:GetAttribute("CivAlive") == true
			and mdl:GetAttribute("OwnerUserId") == player.UserId
		then
			-- clear any previously assigned dialect so the civ re-picks in the new language
			mdl:SetAttribute("CivDialect", nil)
			-- ask the service to seed a fresh line right now
			RequestRandomBubbleLine:Fire(mdl)
			seeded += 1
		end
	end
	print(("[LangSwitch] Re-seeded %d civilian bubbles for %s"):format(seeded, player.Name))
end

-- When a player picks a language in-game
SetLanguage.OnServerEvent:Connect(function(player, language)
	-- Sanity
	if not Localizing.isValidLanguage(language) then return end
	if not PlayerDataService.WaitForPlayerData(player) then return end

	-- Persist to save data
	PlayerDataService.ModifyData(player, "Language", language)

	-- Mirror to attribute (this is what the chatter/bubbles read)
	player:SetAttribute("Language", language)
	print(player.Name .. " set language to:", language)

	-------------------------------------------------------------------
	-- 🔹 Refresh all existing civilian bubbles immediately
	-------------------------------------------------------------------
	local BE = RS:WaitForChild("Events"):WaitForChild("BindableEvents")
	local RequestRandomBubbleLine = BE:WaitForChild("RequestRandomBubbleLine")

	local plots = workspace:FindFirstChild("PlayerPlots")
	local plot  = plots and plots:FindFirstChild("Plot_" .. player.UserId)
	if plot then
		local reseeded = 0
		for _, mdl in ipairs(plot:GetDescendants()) do
			if mdl:IsA("Model")
				and mdl:GetAttribute("CivAlive") == true
				and mdl:GetAttribute("OwnerUserId") == player.UserId then

				-- remove old dialect so a new one is chosen for the new language
				mdl:SetAttribute("CivDialect", nil)

				-- trigger an immediate re-seed (causes new localized text + dialect print)
				RequestRandomBubbleLine:Fire(mdl)
				reseeded += 1
			end
		end
		print(("[LangSwitch] Re-seeded %d civilians for %s (%s)"):format(
			reseeded, player.Name, language))
	else
		warn(("[LangSwitch] No plot found for %s"):format(player.Name))
	end
	-------------------------------------------------------------------

	-- Existing UI push
	local CentralUIStatsModule = require(UI:WaitForChild("UIDisplay"))
	CentralUIStatsModule.sendStatsToUI(player)
end)

-- On join: after PlayerData is ready, mirror the saved language to a replicated attribute
Players.PlayerAdded:Connect(function(player)
	-- Wait until PlayerDataService has loaded this player's data
	if not PlayerDataService.WaitForPlayerData(player) then return end

	local data = PlayerDataService.GetData(player)
	local savedLang = (data and data.Language) or "English"

	-- Replicate it so the client sees it (and your LocalScript can translate immediately)
	player:SetAttribute("Language", savedLang)
end)
