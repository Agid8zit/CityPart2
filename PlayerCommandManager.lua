local CommandManager = require(script.Parent.CommandManager)

------------------------------------------------------------
-- MODULE TABLE  (acts as the singleton)
------------------------------------------------------------
local PlayerCommandManager = {}
PlayerCommandManager.__index = PlayerCommandManager

-- Shared state lives in up‑values so both the singleton and any
-- extra instances see the same data if you want that.
local _managers = setmetatable({}, { __mode = "k" })   -- weak keys

------------------------------------------------------------
-- Singleton‑style helpers
------------------------------------------------------------
local DEBUG = false
local function dprint(...)
	if DEBUG then
		print("[PlayerCommandManager]", ...)
	end
end

-- Called as   PlayerCommandManager:getManager(player)
function PlayerCommandManager:getManager(player)
	if not _managers[player] then
		dprint("Creating new CommandManager for player:", player.Name)
		_managers[player] = CommandManager.new()
	else
		dprint("Retrieved existing CommandManager for player:", player.Name)
	end
	return _managers[player]
end

function PlayerCommandManager:removeManager(player)
	dprint("Removing CommandManager for player:", player.Name)
	_managers[player] = nil     -- garbage‑collect when nothing else references it
end

------------------------------------------------------------
-- OPTIONAL: keep the OOP constructor for advanced use‑cases
--           (you can delete everything below if you never need it)
------------------------------------------------------------
function PlayerCommandManager.new()
	local self = setmetatable({}, PlayerCommandManager)
	-- Each instance gets its *own* table; change to `_managers`
	-- if you want all instances to share the same data.
	self.managers = setmetatable({}, { __mode = "k" })
	return self
end

-- Instance methods forward to the shared logic unless you want
-- totally isolated stacks per instance.
function PlayerCommandManager:getManagerInstance(player)
	local pool = self.managers   -- instance‑local table
	if not pool[player] then
		pool[player] = CommandManager.new()
	end
	return pool[player]
end

function PlayerCommandManager:removeManagerInstance(player)
	self.managers[player] = nil
end

return PlayerCommandManager
