-- BusDepot.client.lua  — uses server schema (tiersTbl, unlock) without changing aesthetics.

local BusDepot = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Utility              = require(ReplicatedStorage.Scripts.Utility)
local UtilityGUI           = require(ReplicatedStorage.Scripts.UI.UtilityGUI)
local BusDepotUpgrades     = require(ReplicatedStorage.Scripts.BusDepotUpgrades)
local SoundController      = require(ReplicatedStorage.Scripts.Controllers.SoundController)
local PlayerDataController = require(ReplicatedStorage.Scripts.Controllers.PlayerDataController)

-- Per-tier art (1..10). Leave as-is to preserve art style.
local ICONS = {
	"rbxassetid://72982367530900",
	"rbxassetid://98270554732974",
	"rbxassetid://76055200204867",
	"rbxassetid://103022839880154",
	"rbxassetid://81595042606802",
	"rbxassetid://95847129383688",
	"rbxassetid://102056879193439",
	"rbxassetid://116104348609423",
	"rbxassetid://87254740735003",
	"rbxassetid://121078607768550",
}
local MAX_TIERS = #ICONS
local MAX_TIER_LEVEL = 100
local LEVELS_PER_TIER_UNLOCK = 3

-- UI paths (unchanged)
local UI = script.Parent
local ExitBtn = UI.Main.Exit
local ResultTickets = UI.Main.Container.ResultFrame.Tickets
local ResultGain    = UI.Main.Container.ResultFrame.Gain

local Template : Frame = UI.Main.Container.Container.ScrollingFrame.Template
Template.Visible = false

-- Events (schema already created on server)
local RE = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RemoteEvents")
local RE_AddedBusDepot            = RE:WaitForChild("AddedBusDepot")     -- (zoneId, tiersTbl, unlock)
local RE_RemovedBusDepot          = RE:WaitForChild("RemovedBusDepot")   -- (zoneId)
local RE_UpgradeBusDepot          = RE:WaitForChild("UpgradeBusDepot")   -- C->S: (zoneId, tierIndex) ; S->C: (zoneId, tiersTbl, unlock)
local RE_BusDepotSync             = RE:WaitForChild("BusDepotSync")      -- (zoneId, tiersTbl, unlock)
local RE_PlayerDataChanged_Tix    = RE:WaitForChild("PlayerDataChanged_BusTickets")
local RE_ToggleBusDepotGui        = RE:FindFirstChild("ToggleBusDepotGui")

-- Internal state
type ZoneState = {
	Tiers: {[number]: number},   -- levels per tier (numeric)
	Unlock: number,              -- unlock counter from server
	Frames: {[number]: Frame},   -- UI frame per unlocked tier
	OrderBase: number,
}
local Zones : {[string]: ZoneState} = {}
local LayoutCursor = 0

-- Button connection cache (no Attributes storing RBXScriptConnection)
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
	local t = math.floor(math.max(0, tonumber(unlock) or 0) / LEVELS_PER_TIER_UNLOCK) + 1
	if t < 1 then t = 1 end
	if t > MAX_TIERS then t = MAX_TIERS end
	return t
end

local function setTickets(n: number)
	ResultTickets.Text = Utility.AbbreviateLargeNumber(n, 1) .. " Tickets"
end

local function recomputeTotalGain()
	local sum = 0
	for _, z in pairs(Zones) do
		local ut = unlockedTiers(z.Unlock)
		for ti = 1, ut do
			sum += BusDepotUpgrades.GetEarnedTicketSec(z.Tiers[ti] or 0)
		end
	end
	ResultGain.Text = "+ " .. Utility.AbbreviateLargeNumber(sum, 1) .. " Tickets/s"
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
		pcall(function() (img :: any).ImageContent = art end) -- if you use this property
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
	f.Name = ("BusDepot_%s_Tier%02d"):format(zoneId, tier)
	f.LayoutOrder = orderBase + tier -- respects whatever layout you already had
	f.Parent = Template.Parent       -- same ScrollingFrame as Template
	return f
end

local function setIfExistsTextLabel(parent: Instance, name: string, text: string)
	local l = parent:FindFirstChild(name)
	if l and l:IsA("TextLabel") then l.Text = text; l.Visible = true end
end

local function paintTier(z: ZoneState, zoneId: string, tier: number)
	local f = z.Frames[tier]; if not f then return end
	local lvl = clamp(z.Tiers[tier] or 0, 0, MAX_TIER_LEVEL)

	-- Icons: strictly by this tier's level
	local iconCount = clamp(math.floor(lvl / 10) + 1, 1, 10)
	local iconsHolder = f:FindFirstChild("Icons") :: Frame
	assert(iconsHolder and iconsHolder:IsA("Frame"), "Template must contain 'Icons' frame")
	local art = ICONS[(tier - 1) % #ICONS + 1]
	ensureIcons(iconsHolder, iconCount, art)

	-- Text: write only to labels that exist; do NOT change layout
	-- Common patterns supported:
	--   "Tier" + "Level" pair, or just "Level", and "Gain", and cost label under "UpgradeContainer/Tickets"
	setIfExistsTextLabel(f, "Tier",  ("Tier %d"):format(tier))
	-- >>> exact format requested: Level (n)
	setIfExistsTextLabel(f, "Level", ("Level %d"):format(lvl))
	setIfExistsTextLabel(f, "Gain",  "+ " .. BusDepotUpgrades.GetEarnedTicketSec(lvl) .. " Tickets/s")

	-- Upgrade block: toggle button only; never move it.
	local uc = f:FindFirstChild("UpgradeContainer")
	if uc and uc:IsA("Frame") then
		setIfExistsTextLabel(uc, "Tickets", BusDepotUpgrades.GetUpgradeCost(lvl, tier) .. " Tickets")

		local btn = uc:FindFirstChildWhichIsA("ImageButton")
		if btn then
			btn.Visible = lvl < MAX_TIER_LEVEL
			btn.Active  = lvl < MAX_TIER_LEVEL
			disconnectButton(btn)
			if lvl < MAX_TIER_LEVEL then
				BtnConns[btn] = btn.MouseButton1Down:Connect(function()
					local pd = PlayerDataController.GetSaveFileData(); if not pd then return end
					local bal = (pd.economy and pd.economy.bustickets) or 0
					local cost = BusDepotUpgrades.GetUpgradeCost(z.Tiers[tier] or 0, tier)
					if bal < cost then return end
					RE_UpgradeBusDepot:FireServer(zoneId, tier)
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
function BusDepot.OnShow() UI.Enabled = true  recomputeTotalGain() end
function BusDepot.OnHide() UI.Enabled = false end
function BusDepot.Toggle() if UI.Enabled then BusDepot.OnHide() else BusDepot.OnShow() end end

function BusDepot.Init()
	ExitBtn.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI","SmallClick")
		BusDepot.Toggle()
	end)
	UtilityGUI.VisualMouseInteraction(
		ExitBtn, ExitBtn.TextLabel, TweenInfo.new(0.15),
		{Size = UDim2.fromScale(1.25,1.25)}, {Size = UDim2.fromScale(0.5,0.5)}
	)

	task.spawn(function()
		PlayerDataController.WaitForPlayerData()
		local pd = PlayerDataController.GetSaveFileData()
		if pd then setTickets(pd.economy.bustickets or 0) end
	end)

	if RE_ToggleBusDepotGui then
		RE_ToggleBusDepotGui.OnClientEvent:Connect(function(forceOpen: boolean?)
			if forceOpen then BusDepot.OnShow() else BusDepot.Toggle() end
		end)
	end
end

-- Net hooks (new schema: unlock instead of aggregate)
RE_AddedBusDepot.OnClientEvent:Connect(function(zoneId: string, tiersTbl, unlock: number)
	upsertZone(zoneId, tiersTbl, unlock)
end)

RE_BusDepotSync.OnClientEvent:Connect(function(zoneId: string, tiersTbl, unlock: number)
	upsertZone(zoneId, tiersTbl, unlock)
end)

RE_UpgradeBusDepot.OnClientEvent:Connect(function(zoneId: string, tiersTbl, unlock: number)
	upsertZone(zoneId, tiersTbl, unlock)
end)

RE_RemovedBusDepot.OnClientEvent:Connect(function(zoneId: string)
	removeZone(zoneId)
end)

RE_PlayerDataChanged_Tix.OnClientEvent:Connect(function(bal: number)
	setTickets(bal)
end)

return BusDepot
