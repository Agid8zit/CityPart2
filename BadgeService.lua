local BadgeService = {}

local RobloxBadgeService = game:GetService("BadgeService")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)

local BADGE_KEYS = {
	FirstSession         = "TheStartOfSomethingGreat",
	OnboardingCompleted  = "Educated",
	OnboardingSkipped    = "Truancy",
	CityBeginnings       = "BeginningsOfCivilization",
	AirportMaxTier       = "RuleTheSkies",
	BusMaxTier           = "MoreBuses",
	FirstMapExpansion    = "Expansionism",
	AllMapExpansions     = "TheCityMustGrow",
	CleanEnergyOnly      = "GreenThumb",
	DirtyEnergyOnly      = "TheOilMustFlow",
}

-- All badge metadata lives here so every system asks the same source of truth.
local BADGE_DEFINITIONS = {
	[ BADGE_KEYS.FirstSession ] = {
		id = 1785021154316254,
		name = "The Start Of Something Great",
		description = "Play the game for the first time",
	},

	[ BADGE_KEYS.OnboardingCompleted ] = {
		id = 2914107394347487,
		name = "Educated",
		description = "Complete the tutorial",
	},

	[ BADGE_KEYS.OnboardingSkipped ] = {
		id = 3450856680616995,
		name = "Truancy",
		description = "You skipped the tutorial",
	},

	[ BADGE_KEYS.CityBeginnings ] = {
		id = 4123419860081954,
		name = "Beginnings Of Civilization",
		description = "Operate a functioning city with every core service online",
	},

	[ BADGE_KEYS.AirportMaxTier ] = {
		id = 2062629610979940,
		name = "Rule The Skies",
		description = "Reach level 100 in any airport tier",
	},

	[ BADGE_KEYS.BusMaxTier ] = {
		id = 3911874665950428,
		name = "More Buses",
		description = "Reach level 100 in any bus depot tier",
	},

	[ BADGE_KEYS.FirstMapExpansion ] = {
		id = 3476902852514320,
		name = "Expansionism",
		description = "Buy your first map expansion",
	},

	[ BADGE_KEYS.AllMapExpansions ] = {
		id = 1758864881128564,
		name = "The City Must Grow",
		description = "Buy every map expansion",
	},

	[ BADGE_KEYS.CleanEnergyOnly ] = {
		id = 3844520474440192,
		name = "Green Thumb",
		description = "Produce 500k W using only clean energy",
	},

	[ BADGE_KEYS.DirtyEnergyOnly ] = {
		id = 2549639871056238,
		name = "The Oil Must Flow",
		description = "Produce 500k W using only dirty energy",
	},
}

BadgeService.Badges = BADGE_DEFINITIONS
BadgeService.Keys = BADGE_KEYS

local function ensureOwnedBadgeTable(player: Player)
	local playerData = PlayerDataService.AllPlayerData[player]
	if not playerData then
		return nil
	end
	playerData.OwnedBadges = playerData.OwnedBadges or {}
	return playerData.OwnedBadges
end

local function markBadgeOwned(player: Player, badgeKey: string)
	local owned = ensureOwnedBadgeTable(player)
	if not owned then
		warn(string.format("[BadgeService] Player data missing while recording %s for %s", badgeKey, player.Name))
		return false
	end
	if owned[badgeKey] then
		return true
	end

	owned[badgeKey] = true
	PlayerDataService.ModifyData(player, "OwnedBadges/" .. badgeKey, true)
	return true
end

local function safeUserHasBadge(userId: number, badgeId: number?)
	if not badgeId or badgeId <= 0 then
		return false
	end
	local ok, has = pcall(RobloxBadgeService.UserHasBadgeAsync, RobloxBadgeService, userId, badgeId)
	if not ok then
		warn(string.format("[BadgeService] UserHasBadgeAsync failed for %d (%s)", userId, tostring(has)))
		return false
	end
	return has == true
end

local function shouldUseLiveAwarding()
	return not RunService:IsStudio()
end

local function doRobloxAward(userId: number, badgeId: number)
	if badgeId <= 0 then
		return false, "BadgeIdMissing"
	end
	if not shouldUseLiveAwarding() then
		return true, "StudioSkip"
	end
	return pcall(RobloxBadgeService.AwardBadge, RobloxBadgeService, userId, badgeId)
end

function BadgeService.GetBadgeInfo(badgeKey: string)
	return BADGE_DEFINITIONS[badgeKey]
end

function BadgeService.Award(player: Player, badgeKey: string): (boolean, string?)
	local definition = BADGE_DEFINITIONS[badgeKey]
	if not definition then
		return false, "UnknownBadgeKey"
	end

	local owned = ensureOwnedBadgeTable(player)
	if owned and owned[badgeKey] then
		return true, "AlreadyRecorded"
	end

	if safeUserHasBadge(player.UserId, definition.id) then
		markBadgeOwned(player, badgeKey)
		return true, "AlreadyOwned"
	end

	if not definition.id or definition.id <= 0 then
		return false, "BadgeIdUnconfigured"
	end

	local success, err = doRobloxAward(player.UserId, definition.id)
	if not success then
		warn(string.format("[BadgeService] Failed to award %s to %s (%s)", badgeKey, player.Name, tostring(err)))
		return false, tostring(err)
	end

	markBadgeOwned(player, badgeKey)
	return true, "Awarded"
end

function BadgeService.RecordOwned(player: Player, badgeKey: string)
	return markBadgeOwned(player, badgeKey)
end

function BadgeService.SyncOwnedBadges(player: Player)
	local owned = ensureOwnedBadgeTable(player)
	if not owned then
		return
	end
	for key, data in pairs(BADGE_DEFINITIONS) do
		if owned[key] ~= true and data.id and data.id > 0 then
			if safeUserHasBadge(player.UserId, data.id) then
				markBadgeOwned(player, key)
			end
		end
	end
end

function BadgeService.AwardFirstSession(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.FirstSession)
end

function BadgeService.AwardOnboardingCompleted(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.OnboardingCompleted)
end

function BadgeService.AwardOnboardingSkipped(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.OnboardingSkipped)
end

function BadgeService.AwardCityBeginnings(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.CityBeginnings)
end

function BadgeService.AwardAirportMaxTier(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.AirportMaxTier)
end

function BadgeService.AwardBusMaxTier(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.BusMaxTier)
end

function BadgeService.AwardFirstMapExpansion(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.FirstMapExpansion)
end

function BadgeService.AwardAllMapExpansions(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.AllMapExpansions)
end

function BadgeService.AwardCleanEnergyBadge(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.CleanEnergyOnly)
end

function BadgeService.AwardDirtyEnergyBadge(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.DirtyEnergyOnly)
end

return BadgeService
