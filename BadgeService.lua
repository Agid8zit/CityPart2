local BadgeService = {}

local RobloxBadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
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
	AthleticCity         = "AthleticCity",
	Coexist              = "Coexist",
	PoliceState          = "PoliceState",
	Patriotism           = "Patriotism",
	HitTheGriddy         = "HitTheGriddy",
	PropagandaMachine    = "PropagandaMachine",
	AmericanHealthcare   = "AmericanHealthcare",
	Utopia               = "Utopia",
	IndusValley          = "IndusValley",
	Overpopulation       = "Overpopulation",
	AmericanDream        = "AmericanDream",
	PerfectlyBalanced    = "PerfectlyBalanced",
	Money10K             = "Money10K",
	Money100K            = "Money100K",
	Money1M              = "Money1M",
	Money100M            = "Money100M",
	Money1B              = "Money1B",
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

	[ BADGE_KEYS.AthleticCity ] = {
		id = 165399849653735,
		name = "Athletic City",
		description = "Have at least one of every sports building",
	},

	[ BADGE_KEYS.Coexist ] = {
		id = 1366401095268910,
		name = "Coexist",
		description = "Have at least one of every religious building",
	},

	[ BADGE_KEYS.PoliceState ] = {
		id = 3976308414335611,
		name = "Police State",
		description = "Own 10 or more police stations",
	},

	[ BADGE_KEYS.Patriotism ] = {
		id = 3644205302097905,
		name = "Patriotism",
		description = "Place a flag in your city",
	},

	[ BADGE_KEYS.HitTheGriddy ] = {
		id = 162658626447666,
		name = "Hit The Griddy",
		description = "Cover every tile of your map with builds",
	},

	[ BADGE_KEYS.PropagandaMachine ] = {
		id = 3966348419588151,
		name = "Propaganda Machine",
		description = "Own at least 15 News Stations",
	},

	[ BADGE_KEYS.AmericanHealthcare ] = {
		id = 3744214650378218,
		name = "American Healthcare",
		description = "Reach 100k population with no health buildings",
	},

	[ BADGE_KEYS.Utopia ] = {
		id = 2550350680176380,
		name = "Utopia",
		description = "Meet every citizen need with 100k+ population",
	},

	[ BADGE_KEYS.IndusValley ] = {
		id = 3729690528911253,
		name = "Indus Valley",
		description = "Cover 80% of the map with Industrial zones",
	},

	[ BADGE_KEYS.Overpopulation ] = {
		id = 1781552303955516,
		name = "Overpopulation",
		description = "Cover 80% of the map with Residential zones",
	},

	[ BADGE_KEYS.AmericanDream ] = {
		id = 1738353506989084,
		name = "The American Dream",
		description = "Cover 80% of the map with Commercial zones",
	},

	[ BADGE_KEYS.PerfectlyBalanced ] = {
		id = 0,
		name = "Perfectly Balanced",
		description = "Have equal coverage across all six zone types",
	},

	[ BADGE_KEYS.Money10K ] = {
		id = 3194536879767856,
		name = "Making Some Cash",
		description = "Hold at least $10,000",
	},

	[ BADGE_KEYS.Money100K ] = {
		id = 3921526033360994,
		name = "Money Maker",
		description = "Hold at least $100,000",
	},

	[ BADGE_KEYS.Money1M ] = {
		id = 4366510871200022,
		name = "Millionaire",
		description = "Hold at least $1,000,000",
	},

	[ BADGE_KEYS.Money100M ] = {
		id = 3305238027901035,
		name = "Part Of The 1%",
		description = "Hold at least $100,000,000",
	},

	[ BADGE_KEYS.Money1B ] = {
		id = 701963810946097,
		name = "Billionaire",
		description = "Hold at least $1,000,000,000",
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

function BadgeService.AwardAthleticCity(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.AthleticCity)
end

function BadgeService.AwardCoexist(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.Coexist)
end

function BadgeService.AwardPoliceState(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.PoliceState)
end

function BadgeService.AwardPatriotism(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.Patriotism)
end

function BadgeService.AwardHitTheGriddy(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.HitTheGriddy)
end

function BadgeService.AwardPropagandaMachine(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.PropagandaMachine)
end

function BadgeService.AwardAmericanHealthcare(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.AmericanHealthcare)
end

function BadgeService.AwardUtopia(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.Utopia)
end

function BadgeService.AwardIndusValley(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.IndusValley)
end

function BadgeService.AwardOverpopulation(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.Overpopulation)
end

function BadgeService.AwardAmericanDream(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.AmericanDream)
end

function BadgeService.AwardPerfectlyBalanced(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.PerfectlyBalanced)
end

function BadgeService.AwardMoney10K(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.Money10K)
end

function BadgeService.AwardMoney100K(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.Money100K)
end

function BadgeService.AwardMoney1M(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.Money1M)
end

function BadgeService.AwardMoney100M(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.Money100M)
end

function BadgeService.AwardMoney1B(player: Player)
	return BadgeService.Award(player, BADGE_KEYS.Money1B)
end

-- Ensure the first-session badge gets attempted for everyone as soon as their data is ready.
local function awardFirstSessionOnJoin(player: Player)
	if not player then
		return
	end
	if PlayerDataService.WaitForPlayerData and not PlayerDataService.WaitForPlayerData(player) then
		warn(string.format("[BadgeService] Skipping first-session badge; data failed to load for %s", player.Name))
		return
	end
	local ok, reason = BadgeService.AwardFirstSession(player)
	if not ok and reason ~= "AlreadyRecorded" and reason ~= "AlreadyOwned" then
		warn(string.format("[BadgeService] Failed to award first-session badge to %s (%s)", player.Name, tostring(reason)))
	end
end

Players.PlayerAdded:Connect(function(player)
	task.defer(awardFirstSessionOnJoin, player)
end)
for _, plr in ipairs(Players:GetPlayers()) do
	task.defer(awardFirstSessionOnJoin, plr)
end

return BadgeService
