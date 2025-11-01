-- DataSizes.lua  –  binary schema definitions (currencies centralized)

local DataSizes = {

	--  PER-ZONE INFORMATION  (one Zone record per zone the player owns)
	Zone = {
		order = { "id", "mode", "coords", "flags", "wealth", "tileFlags", "buildings"},

		id     = { size = 32, type = "string" },        -- free-form id (e.g., "RoadZone_...")

		mode   = { size = 25, type = "string" },        -- "Residential", "Airport", "BusDepot", etc.

		coords = {                                      -- grid path cells of this zone
			type      = "vec2List",
			size      = "dynamic",
			each      = 6,        -- 3B x + 3B z (millistuds, zigzag)
			countType = "u16",
		},

		flags = {                                       -- zone-level requirements
			size   = 1,
			type   = "u8",
			encode = "PackFlags",
			decode = "UnpackFlags",
			order  = { "Road", "Water", "Power", "Populated" },
		},

		-- NEW FIELDS (still per-zone; not currencies)
		wealth = {                                      -- per-tile wealth state (0..2)
			type      = "u8List",
			size      = "dynamic",
			each      = 1,
			countType = "u16",
			encode    = "EncodeWealthList",
			decode    = "DecodeWealthList",
		},

		tileFlags = {                                   -- per-tile requirement bits
			type      = "u8List",
			size      = "dynamic",
			each      = 1,
			countType = "u16",
			encode    = "EncodeTileFlagsList",
			decode    = "DecodeTileFlagsList",
		},

		-- IMPORTANT:
		--   • New saves write a u32 length prefix.
		--   • We still *read* legacy u16 safely to avoid silent corruption.
		--   • If you truly don't want legacy, you can drop legacyCountType later,
		--     but leaving it in does not harm new saves.
		buildings = {
			type            = "string",
			size            = "dynamic",
			countType       = "u32",   -- current format
		},
	},

	--  EXACT ROAD SNAPSHOT (per road-zone)
	RoadSnapshot = {
		order = { "zoneId", "snapshot" },
		zoneId   = { size = 32, type = "string" },                 -- id of a road zone
		snapshot = { size = "dynamic", type = "string", countType = "u32" }, -- JSON snapshot of segments/decos
	},

	--  PLAYER-LEVEL CURRENCIES (single row per player)
	--  No Economy module required; this is the canonical save.
	PlayerEconomy = {
		order = { "money", "planeTickets", "busTickets" },

		-- Choose ranges you like; u32 gives 0..4,294,967,295
		money        = { size = 4, type = "u32" },
		planeTickets = { size = 4, type = "u32" },
		busTickets   = { size = 4, type = "u32" },
	},

	--  UNLOCK KEYS (tiny rows)
	Unlock = {
		order = { "name" },
		name = { size = 24, type = "string" },
	},

	--  FILE HEADER / FOOTER
	Metadata = {
		order = { "version", "timestamp" },
		version   = { size = 1, type = "u8"  },
		timestamp = { size = 4, type = "u32" },
	},
}

return DataSizes
