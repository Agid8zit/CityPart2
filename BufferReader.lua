local bit32 = bit32

local BufferReader = {}
BufferReader.__index = BufferReader

-- ─────────────────────────────────────────
function BufferReader.new(blob : string?)
	blob = blob or ""
	return setmetatable({
		_blob = blob,      -- raw string
		_len  = #blob,     -- cached length
		_pos  = 1,         -- read cursor (1‑based)
	}, BufferReader)
end


function BufferReader:_readByte()
	if self._pos > self._len then
		return 0                 -- or error("read past end")
	end
	local byte = string.byte(self._blob, self._pos)
	self._pos += 1
	return byte
end



-- Strings -----------------------------------------------------
function BufferReader:ReadString(size: number)
	local chars = table.create(size)
	for i = 1, size do
		chars[i] = string.char(self:_readByte())
	end
	-- NEW: drop trailing NULs added by fixed‑width fields
	return (table.concat(chars)):gsub("%z+$", "")
end

-- UInt / Int --------------------------------------------------
function BufferReader:ReadUInt(size: number)
	local n = 0
	for _ = 1, size do
		n = bit32.lshift(n, 8) + self:_readByte()
	end
	return n
end

function BufferReader:ReadInt(size: number)
	local u      = self:ReadUInt(size)
	local signBit = bit32.lshift(1, size * 8 - 1)
	if u >= signBit then
		return u - bit32.lshift(1, size * 8)
	else
		return u
	end
end

-- ZigZag (unsigned → signed) ---------------------------------
local function ZigZagDecode(u, size)
	-- u is unsigned; LSB holds the sign flag
	local value = bit32.rshift(u, 1)
	if bit32.band(u, 1) == 0 then
		return value              -- positive
	else
		return -(value + 1)       -- negative
	end
end

function BufferReader:ReadZigZag(size: number)
	return ZigZagDecode(self:ReadUInt(size), size)
end

-- Floats ------------------------------------------------------
function BufferReader:_readBlob(n)
	local from, to = self._pos, self._pos + n - 1
	self._pos = to + 1
	return string.sub(self._blob, from, to)
end


function BufferReader:ReadFloat32() return (string.unpack(">f", self:_readBlob(4))) end
function BufferReader:ReadFloat64() return (string.unpack(">d", self:_readBlob(8))) end

-- ─────────────────────────────────────────
--  Convenience auto‑reader
-- ─────────────────────────────────────────
function BufferReader:ReadAuto(typeHint: string, byteSize: number?)
	if typeHint == "string" then
		if type(byteSize) == "string" then               -- u8 / u16 / u32 header
			local len = self:ReadAuto(byteSize)          -- read length prefix
			return self:ReadString(len)                  -- payload
		end
		return self:ReadString(byteSize)    

	elseif typeHint == "u8"   then return self:ReadUInt(1)
	elseif typeHint == "i8"   then return self:ReadInt (1)
	elseif typeHint == "u16"  then return self:ReadUInt(2)
	elseif typeHint == "i16"  then return self:ReadInt (2)
	elseif typeHint == "u24"  then return self:ReadUInt(3)
	elseif typeHint == "i24"  then return self:ReadInt (3)
	elseif typeHint == "u32"  then return self:ReadUInt(4)
	elseif typeHint == "i32"  then return self:ReadInt (4)

	elseif typeHint == "f32"  then return self:ReadFloat32()
	elseif typeHint == "f64"  then return self:ReadFloat64()

	elseif typeHint == "vec2" then
		local x = self:ReadZigZag(3) / 1000
		local z = self:ReadZigZag(3) / 1000
		return { x = x, z = z }

	elseif typeHint == "vec3" then
		local x = self:ReadFloat32()
		local y = self:ReadFloat32()
		local z = self:ReadFloat32()
		return Vector3.new(x, y, z)

	elseif typeHint == "cframe" then
		local x = self:ReadFloat32()
		local y = self:ReadFloat32()
		local z = self:ReadFloat32()
		return CFrame.new(x, y, z)

	elseif typeHint == "vec2List" then
		local countSize = (byteSize == "u8" and 1)
			or (byteSize == "u16" and 2)
			or (byteSize == "u32" and 4)
			or 2 -- fallback default

		local count = self:ReadUInt(countSize)
		local list = {}
		for _ = 1, count do
			local x = self:ReadZigZag(3) / 1000
			local z = self:ReadZigZag(3) / 1000
			table.insert(list, { x = x, z = z })
		end
		return list
		
	elseif typeHint == "u8List" then
		local countType = byteSize or "u16"
		local count     = self:ReadAuto(countType)   -- list length header
		local out       = table.create(count)
		for i = 1, count do
			out[i] = self:ReadAuto("u8")
		end
		return out

	else
		error("BufferReader: unknown typeHint '" .. tostring(typeHint) .. "'")
	end
end

return BufferReader
