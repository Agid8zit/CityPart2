local Airport = {}

-- Roblox Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies
local Utility              = require(ReplicatedStorage.Scripts.Utility)
local UtilityGUI           = require(ReplicatedStorage.Scripts.UI.UtilityGUI)
local AirportUpgrades      = require(ReplicatedStorage.Scripts.AirportUpgrades)
local SoundController      = require(ReplicatedStorage.Scripts.Controllers.SoundController)
local PlayerDataController = require(ReplicatedStorage.Scripts.Controllers.PlayerDataController)

-- Per-tier art (1..10). Kept from your Airport version.
local ICON_VARIANTS = {
	"rbxassetid://75380742299087",
	"rbxassetid://121136773389101",
	"rbxassetid://136113830791152",
	"rbxassetid://122621346093155",
	"rbxassetid://73060422504444",
	"rbxassetid://124382274067571",
	"rbxassetid://114651584889235",
	"rbxassetid://94924093701226",
	"rbxassetid://84140973747456",
	"rbxassetid://108298795141680",
}
local MAX_TIERS = #ICON_VARIANTS
local MAX_TIER_LEVEL = 100

-- UI paths (unchanged)
local UI = script.Parent
local UI_Exit = UI.Main.Exit
local UI_Result_PlaneTickets  = UI.Main.Container.ResultFrame.Tickets
local UI_Result_TicketsGain   = UI.Main.Container.ResultFrame.Gain

local Template : Frame = UI.Main.Container.Container.ScrollingFrame.Template
Template.Visible = false

-- Events (schema: (zoneId, tiersTbl, unlock))
local RE = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents")
local RE_AddedAirport     = RE:WaitForChild("AddedAirport")
local RE_RemovedAirport   = RE:WaitForChild("RemovedAirport")
local RE_UpgradeAirport   = RE:WaitForChild("UpgradeAirport") -- C->S: (zoneId, tierIndex)
local RE_AirportSync      = RE:FindFirstChild("AirportSync")
local RE_PlayerDataChanged_PlaneTickets = RE:WaitForChild("PlayerDataChanged_PlaneTickets")
local RE_ToggleAirportGui = RE:FindFirstChild("ToggleAirportGui") -- optional

-- Internal state (mirrors BusDepot)
type ZoneState = {
	Tiers: {[number]: number},   -- levels per tier (numeric)
	Unlock: number,              -- unlock counter from server (0..100)
	Frames: {[number]: Frame},   -- UI frame per unlocked tier
	OrderBase: number,
}
local Zones : {[string]: ZoneState} = {}
local LayoutCursor = 0

-- Button connection cache
local BtnConns : {[Instance]: RBXScriptConnection} = {}
local function disconnectButton(btn: Instance?)
	if not btn then return end
	local c = BtnConns[btn]
	if c then c:Disconnect(); BtnConns[btn] = nil end
end
local function cleanupConnectionsUnder(root: Instance?)
	if not root then return end
	for inst, conn in pairs(BtnConns) do
		if conn and inst and inst.Parent and inst:IsDescendantOf(root) then
			conn:Disconnect()
			BtnConns[inst] = nil
		end
	end
end

-- Helpers (logic only; no layout changes)
local function clamp(n: number, lo: number, hi: number): number
	if n < lo then return lo end
	if n > hi then return hi end
	return n
end

local function unlockedTiers(unlock: number): number
	local t = math.floor(math.max(0, tonumber(unlock) or 0) / 10) + 1
	if t < 1 then t = 1 end
	if t > MAX_TIERS then t = MAX_TIERS end
	return t
end

local function iconForTier(tier: number): string
	-- Use your airport variant list per tier, cycling safely.
	return ICON_VARIANTS[((tier - 1) % #ICON_VARIANTS) + 1]
end

local function setTotalTickets(n: number)
	UI_Result_PlaneTickets.Text = Utility.AbbreviateLargeNumber(n, 1) .. " Tickets"
end

local function recomputeTotalGain()
	local sum = 0
	for _, z in pairs(Zones) do
		local ut = unlockedTiers(z.Unlock)
		for ti = 1, ut do
			sum += AirportUpgrades.GetEarnedTicketSec(z.Tiers[ti] or 0)
		end
	end
	UI_Result_TicketsGain.Text = "+ " .. Utility.AbbreviateLargeNumber(sum, 1) .. " Tickets/s"
end

-- Do NOT add any UIListLayout; only toggle visibility/contents.
local function ensureIcons(holder: Frame, count: number, art: string)
	-- Base Icon1 must exist in template
	local base = holder:FindFirstChild("Icon1") :: ImageLabel?
	assert(base and base:IsA("ImageLabel"), "Template.Icons.Icon1 required")

	-- Hide all existing icon clones except base; we'll reveal up to count
	for _, ch in ipairs(holder:GetChildren()) do
		if ch:IsA("ImageLabel") and ch.Name:match("^Icon%d+$") then
			ch.Visible = false
		end
	end

	-- Always show Icon1 if count>=1, then clone as needed. Never touch Size/Position/AnchorPoint.
	local function paint(img: ImageLabel)
		img.Image = art
		pcall(function() (img :: any).ImageContent = art end)
		img.Visible = true
	end

	if count >= 1 then paint(base) end
	for i = 2, count do
		local name = "Icon"..i
		local img = holder:FindFirstChild(name) :: ImageLabel?
		if not img then
			img = base:Clone()
			img.Name = name
			img.Parent = holder
		end
		paint(img)
	end
end

local function buildTierFrame(zoneId: string, tier: number, orderBase: number): Frame
	local f = Template:Clone()
	f.Visible = true
	f.Name = ("Airport_%s_Tier%02d"):format(zoneId, tier)
	f.LayoutOrder = orderBase + tier
	f.Parent = Template.Parent
	return f
end

local function setIfExistsTextLabel(parent: Instance, name: string, text: string)
	local l = parent:FindFirstChild(name)
	if l and l:IsA("TextLabel") then l.Text = text; l.Visible = true end
end

local function paintTier(z: ZoneState, zoneId: string, tier: number)
	local f = z.Frames[tier]; if not f then return end
	local lvl = clamp(z.Tiers[tier] or 0, 0, MAX_TIER_LEVEL)

	-- Icons strictly by this tier's level: 0–9 -> 1, 10–19 -> 2, ... up to 10
	local iconCount = clamp(math.floor(lvl / 10) + 1, 1, 10)
	local iconsHolder = f:FindFirstChild("Icons") :: Frame
	assert(iconsHolder and iconsHolder:IsA("Frame"), "Template must contain 'Icons' frame")
	ensureIcons(iconsHolder, iconCount, iconForTier(tier))

	-- Labels: exact format "Level (n)"; Gain uses your math
	setIfExistsTextLabel(f, "Tier",  ("Tier %d"):format(tier))
	setIfExistsTextLabel(f, "Level", ("Level %d"):format(lvl))
	setIfExistsTextLabel(f, "Gain",  "+ " .. AirportUpgrades.GetEarnedTicketSec(lvl) .. " Tickets/s")

	-- Upgrade block
	local uc = f:FindFirstChild("UpgradeContainer")
	if uc and uc:IsA("Frame") then
		setIfExistsTextLabel(uc, "Tickets", AirportUpgrades.GetUpgradeCost(lvl, tier) .. " Tickets")
		local btn = uc:FindFirstChildWhichIsA("ImageButton")
		if btn then
			btn.Visible = lvl < MAX_TIER_LEVEL
			btn.Active  = lvl < MAX_TIER_LEVEL
			disconnectButton(btn)
			if lvl < MAX_TIER_LEVEL then
				BtnConns[btn] = btn.MouseButton1Down:Connect(function()
					local pd = PlayerDataController.GetSaveFileData(); if not pd then return end
					local bal = (pd.economy and pd.economy.planetickets) or 0
					local cost = AirportUpgrades.GetUpgradeCost(z.Tiers[tier] or 0, tier)
					if bal < cost then return end
					RE_UpgradeAirport:FireServer(zoneId, tier)
				end)
			end
		end
	end
end

local function ensureTierFrames(zoneId: string)
	local z = Zones[zoneId]; if not z then return end
	local need = unlockedTiers(z.Unlock)

	-- Create frames for unlocked tiers
	for t = 1, need do
		if not z.Frames[t] then
			z.Frames[t] = buildTierFrame(zoneId, t, z.OrderBase)
		end
	end
	-- Remove frames beyond unlock
	for t = need + 1, MAX_TIERS do
		if z.Frames[t] then
			cleanupConnectionsUnder(z.Frames[t])
			z.Frames[t]:Destroy()
			z.Frames[t] = nil
		end
	end
	-- Paint visible tiers
	for t = 1, need do
		z.Tiers[t] = clamp(z.Tiers[t] or 0, 0, MAX_TIER_LEVEL)
		paintTier(z, zoneId, t)
	end
end

local function upsertZone(zoneId: string, tiersTbl: {[number]:number}, unlock: number)
	if not Zones[zoneId] then
		LayoutCursor += 100
		Zones[zoneId] = { Tiers = {}, Unlock = 0, Frames = {}, OrderBase = LayoutCursor }
	end
	local z = Zones[zoneId]
	z.Unlock = tonumber(unlock) or 0
	for k, v in pairs(tiersTbl or {}) do
		local idx = tonumber(k)
		if idx then z.Tiers[idx] = clamp(tonumber(v) or 0, 0, MAX_TIER_LEVEL) end
	end
	ensureTierFrames(zoneId)
	recomputeTotalGain()
end

local function removeZone(zoneId: string)
	local z = Zones[zoneId]; if not z then return end
	for _, f in pairs(z.Frames) do
		if f then cleanupConnectionsUnder(f); if f.Destroy then f:Destroy() end end
	end
	Zones[zoneId] = nil
	recomputeTotalGain()
end

-- Public toggles (unchanged)
function Airport.OnShow() UI.Enabled = true  recomputeTotalGain() end
function Airport.OnHide() UI.Enabled = false end
function Airport.Toggle() if UI.Enabled then Airport.OnHide() else Airport.OnShow() end end

function Airport.Init()
	-- Exit
	UI_Exit.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI","SmallClick")
		Airport.Toggle()
	end)
	UtilityGUI.VisualMouseInteraction(
		UI_Exit, UI_Exit.TextLabel, TweenInfo.new(0.15),
		{ Size = UDim2.fromScale(1.25, 1.25) },
		{ Size = UDim2.fromScale(0.5, 0.5) }
	)

	-- Seed totals once player data is ready
	task.spawn(function()
		PlayerDataController.WaitForPlayerData()
		local pd = PlayerDataController.GetSaveFileData()
		if pd then setTotalTickets(pd.economy.planetickets or 0) end
	end)

	if RE_ToggleAirportGui then
		RE_ToggleAirportGui.OnClientEvent:Connect(function(forceOpen: boolean?)
			if forceOpen then Airport.OnShow() else Airport.Toggle() end
		end)
	end
end

-- Net hooks (tiersTbl + unlock snapshots)
RE_AddedAirport.OnClientEvent:Connect(function(zoneId: string, tiersTbl, unlock: number)
	upsertZone(zoneId, tiersTbl, unlock)
end)

if RE_AirportSync then
	RE_AirportSync.OnClientEvent:Connect(function(zoneId: string, tiersTbl, unlock: number)
		upsertZone(zoneId, tiersTbl, unlock)
	end)
end

RE_UpgradeAirport.OnClientEvent:Connect(function(zoneId: string, tiersTbl, unlock: number)
	upsertZone(zoneId, tiersTbl, unlock)
end)

RE_RemovedAirport.OnClientEvent:Connect(function(zoneId: string)
	removeZone(zoneId)
end)

RE_PlayerDataChanged_PlaneTickets.OnClientEvent:Connect(function(bal: number)
	setTotalTickets(bal)
end)

return Airport