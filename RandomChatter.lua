-- ServerScriptService/SocialChatterLoop.server.lua
-- Periodic random chatter to TextDialog bubbles (no GUI required).

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

-- Require the service that knows how to pick lines & fire bubbles:
local ok, Social = pcall(function()
	return require(script.Parent.SocialMedia)
end)
if not ok then
	warn("[SocialChatterLoop] SocialMediaService missing:", Social)
	return
end

-- CONFIG ----------------------------------------------------------------
local MIN_GAP_SEC        = 8.0     -- min seconds between posts per player
local MAX_GAP_SEC        = 16.0    -- max seconds between posts per player
local INCLUDE_STRUCTURED = true    -- also pull from Police/Fire/… families
local USE_RANDOM_LINES   = true    -- include KEYS.Random.lines if non-empty
-- -----------------------------------------------------------------------

local loops = {} -- per-player loop tokens

local function waitRand(minS, maxS)
	local d = maxS - minS
	return minS + math.random() * (d >= 0 and d or 0)
end

local function postOne(plr)
	-- Prefer your free-form Random.lines if asked & present, otherwise “anything random”.
	if USE_RANDOM_LINES then
		Social.postRandomBucket(plr, "lines")  -- no-op if empty
	end
	if INCLUDE_STRUCTURED then
		Social.postRandom(plr)                 -- picks from all families with content (incl. Random)
	end
end

local function startLoop(plr)
	if loops[plr] then return end
	local token = {}
	loops[plr] = token

	task.spawn(function()
		while loops[plr] == token and plr.Parent do
			postOne(plr)
			task.wait(waitRand(MIN_GAP_SEC, MAX_GAP_SEC))
		end
		if loops[plr] == token then
			loops[plr] = nil
		end
	end)
end

local function stopLoop(plr)
	loops[plr] = nil
end

-- Start for current & future players
for _, p in ipairs(Players:GetPlayers()) do startLoop(p) end
Players.PlayerAdded:Connect(startLoop)
Players.PlayerRemoving:Connect(stopLoop)

print("[SocialChatterLoop] running: bubbles will show random city chatter.")
