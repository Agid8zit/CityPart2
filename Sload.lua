local BufferWriter = require(script.Parent.BufferWriter)
local BufferReader = require(script.Parent.BufferReader)
local Compressor   = require(script.Parent.Compressor)
local DataSizes    = require(script.Parent.DataSizes)

local Sload = {}

-- Save: Module → Compressor-encoded → Buffer → (string)
function Sload.Save(moduleName: string, rawTable: { [number]: table }): string
	local schema = DataSizes[moduleName]
	assert(schema, "No DataSizes defined for module: " .. moduleName)

	local writer = BufferWriter.new()

	for _, entry in ipairs(rawTable) do
		for _, field in ipairs(schema.order) do
			local def = schema[field]
			local val = entry[field]

			-- Compress value if encoder is defined
			if def.encode and Compressor[def.encode] then
				val = Compressor[def.encode](val, def.order or nil)
			end

			if def.size == "dynamic" then
				writer._countType = def.countType or "u16"
				writer:WriteAuto(val, def.type)
				writer._countType = nil
			else
				writer:WriteAuto(val, def.type, def.size)
			end
		end
	end

	local binary = writer:GetBuffer()
	return binary
end

-- Load helpers (local to this module)
local function _readFixedRowBytes(schema)
	local bytes = 0
	for _, field in ipairs(schema.order) do
		local def = schema[field]
		if type(def.size) == "number" then
			bytes += def.size
		end
	end
	return bytes
end

-- Validate a u8-list that is supposed to be wealth enums (0..2)
local function _isPlausibleWealthList(u8list: {number}, coordsCount: number?): boolean
	-- Accept empty (older saves) or exactly coordsCount entries,
	-- all values in {0,1,2}.
	if type(u8list) ~= "table" then return false end
	local n = #u8list
	if n == 0 then return true end
	if coordsCount and n ~= coordsCount then return false end
	for i = 1, n do
		local v = u8list[i]
		if v ~= 0 and v ~= 1 and v ~= 2 then
			return false
		end
	end
	return true
end

-- Validate a u8-list that is supposed to be tileFlags.
-- Accept empty (older saves) or exactly coordsCount entries.
local function _isPlausibleTileFlagsList(u8list: {number}, coordsCount: number?): boolean
	if type(u8list) ~= "table" then return false end
	local n = #u8list
	if n == 0 then return true end
	if coordsCount and n ~= coordsCount then return false end
	return true
end

-- Attempt to read a dynamic u8List field; if decode fails or looks implausible,
-- rewind the reader and return nil to signal "absent in this save".
local function _tryReadOptionalU8List(reader, def, plausibilityFn, coordsCount)
	local pos0 = reader._pos

	-- Read raw u8List (with the correct countType)
	local okRead, raw = pcall(function()
		local countType = def.countType or "u16"
		return reader:ReadAuto(def.type, countType)
	end)
	if not okRead then
		-- Couldn't read a sane list; rewind and treat as absent
		reader._pos = pos0
		return nil
	end

	-- If a decoder exists, decode defensively
	local decoded = raw
	if def.decode and Compressor[def.decode] then
		local okDec, out = pcall(Compressor[def.decode], raw, def.order or nil)
		if okDec then
			decoded = out
		else
			-- Decoder rejected it; plausibility check on raw numbers next
			decoded = nil
		end
	end

	-- If we decoded into strings successfully, accept immediately
	if decoded and type(decoded) == "table" then
		-- For wealth, decoded will be strings; for tileFlags, booleans-table list.
		-- We still sanity-check length when coordsCount is known.
		if plausibilityFn == _isPlausibleWealthList then
			-- We decoded to strings; length must match or be zero.
			if coordsCount and #decoded > 0 and #decoded ~= coordsCount then
				reader._pos = pos0
				return nil
			end
		end
		return decoded
	end

	-- Fall back to plausibility check on the raw numeric list (pre-decode)
	if plausibilityFn(raw, coordsCount) then
		-- Try decode again but let errors bubble if it's "plausible"
		if def.decode and Compressor[def.decode] then
			decoded = Compressor[def.decode](raw, def.order or nil)
		else
			decoded = raw
		end
		return decoded
	end

	-- Not plausible (likely an older save without this field) → rewind & skip
	reader._pos = pos0
	return nil
end

-- Load: Buffer → Reader → Compressor-decoded → Module
function Sload.Load(moduleName: string, buffer: string): { [number]: table }
	local schema = DataSizes[moduleName]
	assert(schema, "No DataSizes defined for module: " .. moduleName)

	local reader = BufferReader.new(buffer)
	local out = {}

	-- Bytes needed for the fixed-width portion of one row (guard only)
	local totalRowBytes = _readFixedRowBytes(schema)

	while reader._pos + totalRowBytes - 1 <= reader._len do
		local row = {}
		local coordsCount = nil

		for _, field in ipairs(schema.order) do
			local def = schema[field]

			-- Back-compat: for Zone rows, wealth and tileFlags may be absent in older saves.
			if moduleName == "Zone" and def.type == "u8List" and (field == "wealth" or field == "tileFlags") then
				local plausibility = (field == "wealth") and _isPlausibleWealthList or _isPlausibleTileFlagsList
				local decoded = _tryReadOptionalU8List(reader, def, plausibility, coordsCount)

				if decoded == nil then
					-- Treat as absent for this row; leave row[field] as an empty list
					row[field] = {}
				else
					row[field] = decoded
				end

			else
				-- Normal path
				local val
				if def.size == "dynamic" then
					local readSize = def.countType or "u16"
					val = reader:ReadAuto(def.type, readSize)
				else
					val = reader:ReadAuto(def.type, def.size)
				end

				if def.decode and Compressor[def.decode] then
					val = Compressor[def.decode](val, def.order or nil)
				end

				row[field] = val

				-- Track coords length for plausibility checks that follow
				if field == "coords" and type(val) == "table" then
					coordsCount = #val
				end
			end
		end

		table.insert(out, row)
	end

	return out
end

return Sload
