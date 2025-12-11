-- Localizes any world TextLabel/TextButton/TextBox that carries a LangKey attribute.
-- This is for 3D text (SurfaceGui/BillboardGui) on buildings in the player's plot.
-- It listens for language changes and new descendants so newly placed buildings stay translated.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalizationLoader = require(ReplicatedStorage.Localization.Localizing)

local LOCAL_PLAYER = Players.LocalPlayer
local PLAYER_PLOTS = Workspace:FindFirstChild("PlayerPlots")

local TEXT_CLASSES = {
	TextLabel = true,
	TextButton = true,
	TextBox = true,
}

local function currentLanguage(): string
	local lang = LOCAL_PLAYER:GetAttribute("Language")
	if type(lang) ~= "string" or lang == "" then
		lang = "English"
	end
	return lang
end

local function resolveText(key: string): string
	local lang = currentLanguage()

	local localized
	local ok, value = pcall(LocalizationLoader.get, key, lang)
	if ok and type(value) == "string" and value ~= "" then
		localized = value
	end

	if not localized then
		local okEng, eng = pcall(LocalizationLoader.get, key, "English")
		if okEng and type(eng) == "string" and eng ~= "" then
			localized = eng
		end
	end

	return localized or key
end

local function applyToLabel(label: TextLabel | TextButton | TextBox)
	local key = label:GetAttribute("LangKey")
	if type(key) ~= "string" or key == "" then
		return
	end
	label.Text = resolveText(key)
end

local function watchLabel(label: Instance)
	applyToLabel(label :: any)
	label:GetAttributeChangedSignal("LangKey"):Connect(function()
		applyToLabel(label :: any)
	end)
end

local function maybeHandle(inst: Instance)
	if not inst:IsDescendantOf(Workspace) then return end
	if not TEXT_CLASSES[inst.ClassName] then return end
	if inst:GetAttribute("LangKey") then
		watchLabel(inst)
	end
end

local function scanPlot(plot: Instance)
	for _, desc in ipairs(plot:GetDescendants()) do
		maybeHandle(desc)
	end
end

local function attachPlot(plot: Instance)
	scanPlot(plot)
	plot.DescendantAdded:Connect(maybeHandle)
end

local function getOrWaitForPlot(): Instance?
	if not PLAYER_PLOTS then
		PLAYER_PLOTS = Workspace:FindFirstChild("PlayerPlots")
	end
	if not PLAYER_PLOTS then return nil end

	local plotName = "Plot_" .. tostring(LOCAL_PLAYER.UserId)
	local plot = PLAYER_PLOTS:FindFirstChild(plotName)
	if plot then return plot end

	local ok, found = pcall(function()
		return PLAYER_PLOTS:WaitForChild(plotName, 15)
	end)
	if ok then return found end
	return nil
end

local function refreshAll()
	local plot = getOrWaitForPlot()
	if plot then
		scanPlot(plot)
	end
end

-- Main entry
do
	local plot = getOrWaitForPlot()
	if plot then
		attachPlot(plot)
	end

	-- Re-translate everything on language change.
	LOCAL_PLAYER:GetAttributeChangedSignal("Language"):Connect(refreshAll)
end
