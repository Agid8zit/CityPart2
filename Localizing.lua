local lang = script.Parent:WaitForChild("Languages")

local Loader = {}

-- Lazy-loaded language libraries
local Languages = {
	English       = require(lang.English),			--Twitter
	Chinese       = require(lang.Chinese),			--Verify
	Hindi         = require(lang.Hindi),			--Verify
	Spanish       = require(lang.Spanish),
	Arabic        = require(lang.Arabic),         	--Twitter
	French        = require(lang.French),
	Portuguese    = require(lang.Portuguese),     	--Twitter
	Russian       = require(lang.Russian),
	Indonesian    = require(lang.Indonesian),
	Swahili       = require(lang.Swahili),
	German        = require(lang.German),         	--Twitter
	Japanese      = require(lang.Japanese),       	--Twitter
	Persian       = require(lang.Persian),
	Turkish       = require(lang.Turkish),
	Korean        = require(lang.Korean),         	--Twitter
	--Thai add thai, marathi, bengali, and urdu
	
	Vietnamese    = require(lang.Vietnamese),
	Tamil         = require(lang.Tamil),
	Italian       = require(lang.Italian),
	Hausa         = require(lang.Hausa),
	Polish        = require(lang.Polish), --20 w. Thai
	Pashto        = require(lang.Pashto),
	Yoruba        = require(lang.Yoruba),
	Azerbaijani   = require(lang.Azerbaijani),
	Dutch         = require(lang.Dutch),
	Khmer         = require(lang.Khmer),
	Greek         = require(lang.Greek),
	Kazakh        = require(lang.Kazakh),			--Verify
	Mongolian     = require(lang.Mongolian),
	Hebrew        = require(lang.Hebrew),
	Serbian       = require(lang.Serbian),
	Tibetan       = require(lang.Tibetan),
	
	Quechua       = require(lang.Quechua),--
	Finnish       = require(lang.Finnish),
	Norwegian     = require(lang.Norwegian),
	Croatian      = require(lang.Croatian),
	Georgian      = require(lang.Georgian),
	Bosnian       = require(lang.Bosnian),
	Montenegrin   = require(lang.Montenegrin),
	Basque        = require(lang.Basque),
	Icelandic     = require(lang.Icelandic),
	Cree          = require(lang.Cree),--
	Faroese       = require(lang.Faroese),--
	ScottishGaelic= require(lang.ScottishGaelic),--
	Abenaki       = require(lang.Abenaki),--
	Latin         = require(lang.Latin),--
	Gothic        = require(lang.Gothic),--
}

local FALLBACK_LANGUAGE = "English"

function Loader.isValidLanguage(language: string): boolean
	return Languages[language] ~= nil
end

local LANG_KEY_ALIASES = {
	-- CamelCase → Spaced
	["PrivateSchool"]         = "Private School",
	["MiddleSchool"]          = "Middle School",
	["NewsStation"]           = "News Station",
	["PolicePrecinct"]        = "Police Precinct",
	["MolecularWaterPlant"]   = "Molecular Water Plant",

	-- Spelling / wording mismatches
	["Movie Theatre"]         = "Movie Theater",
	["Power Lines"]           = "Power Line",
	["Fire Depth"]            = "Fire Dept",

	-- Density IDs → Display keys (in case these leak through anywhere)
	["ResDense"]              = "Dense Residential Zone",
	["CommDense"]             = "Dense Commercial Zone",
	["IndusDense"]            = "Dense Industrial Zone",
}

function Loader.get(key, language, dialect)
	-- A) normalize incoming keys first
	key = LANG_KEY_ALIASES[key] or key

	local langModule = Languages[language]
	local fallbackModule = Languages[FALLBACK_LANGUAGE]

	-- Get default dialect from the language module
	local defaultDialect = langModule and langModule.__default_dialect or nil

	-- Helper to detect if a value is just a placeholder
	local function isPlaceholder(value)
		return value == nil or value == "..."
	end

	-- Try getting the key from the selected language
	local data = langModule and langModule[key]
	if data then
		if type(data) == "table" then
			-- 1. Try dialect override
			if dialect and not isPlaceholder(data[dialect]) then
				return data[dialect]
			end

			-- 2. Try default dialect from the module
			if defaultDialect and not isPlaceholder(data[defaultDialect]) then
				return data[defaultDialect]
			end

			-- 3. Try _default
			if not isPlaceholder(data["_default"]) then
				return data["_default"]
			end
		elseif not isPlaceholder(data) then
			-- If it's a raw string (not a table)
			return data
		end
	end

	-- Fallback to English
	local fallbackData = fallbackModule and fallbackModule[key]
	if fallbackData then
		if type(fallbackData) == "table" then
			return fallbackData["_default"] or key
		else
			return fallbackData
		end
	end

	-- Final fallback: return the key itself
	return key
end

return Loader
