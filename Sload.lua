local BufferWriter = require(script.Parent.BufferWriter)
local BufferReader = require(script.Parent.BufferReader)
local Compressor   = require(script.Parent.Compressor)
local DataSizes    = require(script.Parent.DataSizes)

local Sload = {}

-- Save: Module → Buffer → (string)
function Sload.Save(moduleName: string, rawTable: { [number]: table }): string
	local schema = DataSizes[moduleName]
	assert(schema, "No DataSizes defined for module: " .. moduleName)

	local writer = BufferWriter.new()

	for _, entry in ipairs(rawTable) do
		for _, field in ipairs(schema.order) do
			local def = schema[field]
			local val = entry[field]

			-- Compress (encode) if requested by schema
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

	return writer:GetBuffer()
end

-- Helpers -----------------------------------------------------

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

-- Plausibility checks for optional u8 lists -------------------

local function _isPlausibleWealthList(u8list: {number}, coordsCount: number?): boolean
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

local function _isPlausibleTileFlagsList(u8list: {number}, coordsCount: number?): boolean
	if type(u8list) ~= "table" then return false end
	local n = #u8list
	if n == 0 then return true end
	if coordsCount and n ~= coordsCount then return false end
	return true
end

-- Dynamic string readers -------------------------------------

local function _tryReadDynamicString(reader, countType)
	local prefixPos = reader._pos
	local len = reader:ReadAuto(countType)
	if type(len) ~= "number" or len < 0 then
		reader._pos = prefixPos
		return nil
	end

	local payloadEnd = reader._pos + len - 1
	if payloadEnd > reader._len then
		reader._pos = prefixPos
		return nil
	end

	return reader:ReadString(len)
end

-- CRITICAL FIX:
-- • Try primary countType; if that fails, try legacyCountType (if provided).
-- • If both fail, DO NOT consume the remaining buffer. Return "" and leave cursor at original position.
local function _readDynamicStringWithFallback(reader, def, fieldName)
	local primary = def.countType or "u16"
	local legacy  = def.legacyCountType
	local pos0    = reader._pos

	-- Try primary
	local s = _tryReadDynamicString(reader, primary)
	if s ~= nil then
		return s
	end

	-- Try legacy if specified
	if legacy and legacy ~= primary then
		reader._pos = pos0
		local s2 = _tryReadDynamicString(reader, legacy)
		if s2 ~= nil then
			return s2
		end
	end

	-- Do not corrupt stream: rewind and return empty
	reader._pos = pos0
	warn(("[Sload] Failed to read dynamic string field '%s' (primary=%s, legacy=%s). Treating as empty string.")
		:format(tostring(fieldName or "?"), tostring(primary), tostring(legacy)))
	return ""
end

-- Optional u8List reader with plausibility guard --------------
local function _tryReadOptionalU8List(reader, def, plausibilityFn, coordsCount)
	local pos0 = reader._pos

	-- Read raw u8List (with specified countType)
	local okRead, raw = pcall(function()
		local countType = def.countType or "u16"
		return reader:ReadAuto(def.type, countType)
	end)
	if not okRead then
		reader._pos = pos0
		return nil
	end

	-- Attempt to decode via Compressor if decoder exists
	local decoded = raw
	if def.decode and Compressor[def.decode] then
		local okDec, out = pcall(Compressor[def.decode], raw, def.order or nil)
		if okDec then
			decoded = out
		else
			decoded = nil
		end
	end

	-- If decoded successfully, minimally check length for wealth lists
	if decoded and type(decoded) == "table" then
		if plausibilityFn == _isPlausibleWealthList then
			if coordsCount and #decoded > 0 and #decoded ~= coordsCount then
				reader._pos = pos0
				return nil
			end
		end
		return decoded
	end

	-- Fall back to plausibility check on raw numeric list
	if plausibilityFn(raw, coordsCount) then
		if def.decode and Compressor[def.decode] then
			decoded = Compressor[def.decode](raw, def.order or nil)
		else
			decoded = raw
		end
		return decoded
	end

	reader._pos = pos0
	return nil
end

-- Load: Buffer → Reader → rows -------------------------------
function Sload.Load(moduleName: string, buffer: string): { [number]: table }
	local schema = DataSizes[moduleName]
	assert(schema, "No DataSizes defined for module: " .. moduleName)

	local reader = BufferReader.new(buffer)
	local out = {}

	local totalRowBytes = _readFixedRowBytes(schema)

	while reader._pos + totalRowBytes - 1 <= reader._len do
		local row = {}
		local coordsCount = nil

		for _, field in ipairs(schema.order) do
			local def = schema[field]

			-- Back-compat for optional u8 lists (older saves may not have them)
			if moduleName == "Zone" and def.type == "u8List" and (field == "wealth" or field == "tileFlags") then
				local plausibility = (field == "wealth") and _isPlausibleWealthList or _isPlausibleTileFlagsList
				local decoded = _tryReadOptionalU8List(reader, def, plausibility, coordsCount)
				row[field] = decoded or {}

			else
				local val
				if def.size == "dynamic" then
					if def.type == "string" then
						val = _readDynamicStringWithFallback(reader, def, field)
					else
						local readSize = def.countType or "u16"
						val = reader:ReadAuto(def.type, readSize)
					end
				else
					val = reader:ReadAuto(def.type, def.size)
				end

				if def.decode and Compressor[def.decode] then
					val = Compressor[def.decode](val, def.order or nil)
				end

				row[field] = val

				if field == "coords" and type(val) == "table" then
					coordsCount = #val
				end
			end
		end

		out[#out+1] = row
	end

	return out
end

return Sload
