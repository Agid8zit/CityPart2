-- Preloads a curated set of assets (UI images, key icons, common sounds) early
-- in the client session so ContentProvider requests are smoothed out.

local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

local function dedupeAppend(target: {string}, seen: {[string]: boolean}, source: {string})
	for _, id in ipairs(source) do
		if id and not seen[id] then
			seen[id] = true
			table.insert(target, id)
		end
	end
end

local assets: {string} = {}
local seen: {[string]: boolean} = {}

-- Loading screen textures/sfx (mirrors CityLoader).
dedupeAppend(assets, seen, {
	"rbxassetid://6586979979", -- pop
	"rbxassetid://80281677741848", -- woosh
	"rbxassetid://112844807562193", -- roads
	"rbxassetid://11181171441", -- fill bar
	"rbxassetid://115781226506183",
	"rbxassetid://117236742548683",
	"rbxassetid://92973934677440",
	"rbxassetid://103876640729602",
	"rbxassetid://72424058297780",
	"rbxassetid://84316478596852",
	"rbxassetid://110904517458791",
	"rbxassetid://126182988804689",
	"rbxassetid://82082935964049",
	"rbxassetid://119295999162301",
	"rbxassetid://134435360105788",
	"rbxassetid://125828872386045",
	"rbxassetid://107238035215550",
	"rbxassetid://88445168652719",
	"rbxassetid://121325972613226",
	"rbxassetid://140426692476468",
	"rbxassetid://80948003006739",
	"rbxassetid://102458499958280",
	"rbxassetid://86335652733746",
	"rbxassetid://138591763775934",
	"rbxassetid://98112102515026",
	"rbxassetid://96416881219071",
	"rbxassetid://118716009054758",
	"rbxassetid://116825043465939",
	"rbxassetid://81109269876260",
})

-- Build menu category icons (highly visible).
dedupeAppend(assets, seen, {
	"rbxassetid://80804212045512",
	"rbxassetid://81164152585346",
	"rbxassetid://111951665644294",
	"rbxassetid://133436787771849",
	"rbxassetid://139640185589881",
	"rbxassetid://96596073659362",
	"rbxassetid://72399175872104",
	"rbxassetid://85773891248333",
	"rbxassetid://100366195302554",
	"rbxassetid://94434560138213",
	"rbxassetid://113537788739611",
	"rbxassetid://116690108033034",
	"rbxassetid://138433123584716",
	"rbxassetid://133504700689023",
	"rbxassetid://134842512535450",
	"rbxassetid://100131265691612",
	"rbxassetid://120327423932825",
	"rbxassetid://82323091054475",
	"rbxassetid://88752537536614",
	"rbxassetid://135306019964679",
})

-- Transport menu icons.
dedupeAppend(assets, seen, {
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
})

-- Core control/input icons (limit to the commonly shown keys/buttons).
dedupeAppend(assets, seen, {
	"rbxassetid://8980895852", -- A
	"rbxassetid://8980893601", -- D
	"rbxassetid://8980885574", -- S
	"rbxassetid://8980883792", -- W
	"rbxassetid://8980886018", -- Q
	"rbxassetid://8980893460", -- E
	"rbxassetid://8980884737", -- Space
	"rbxassetid://8980888083", -- Mouse1
	"rbxassetid://8980887792", -- Mouse2
	"rbxassetid://8981033124", -- Gamepad A
	"rbxassetid://8981032988", -- Gamepad B
	"rbxassetid://8981031512", -- Gamepad X
	"rbxassetid://8981031340", -- Gamepad Y
})

-- Top bar / utility icons.
dedupeAppend(assets, seen, {
	"rbxassetid://2802466058",
	"rbxassetid://17024204551",
})

-- Common UI sounds (kept short).
dedupeAppend(assets, seen, {
	"rbxassetid://4048494255",
	"rbxassetid://128533327576149",
	"rbxassetid://4612384022",
	"rbxassetid://5530025800",
	"rbxassetid://79849708789930",
	"rbxassetid://8223773319",
	"rbxassetid://2977012439",
	"rbxassetid://4614051739",
	"rbxassetid://1210852193",
	"rbxassetid://3269373680",
})

local BATCH_SIZE = 40
local function preloadBatch(batch: {string})
	if #batch == 0 then return end
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(batch)
	end)
	if not ok then
		warn("[ContentPreloader] PreloadAsync failed: ", err)
	end
end

-- Defer slightly so we do not contend with initial spawn.
task.delay(1, function()
	local batch = {}
	for _, id in ipairs(assets) do
		table.insert(batch, id)
		if #batch >= BATCH_SIZE then
			preloadBatch(batch)
			table.clear(batch)
			RunService.Heartbeat:Wait()
		end
	end
	preloadBatch(batch)
end)
