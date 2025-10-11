local bit32 = bit32
local round = math.round or function(n) return n >= 0 and math.floor(n + .5) or math.ceil(n - .5) end

local BufferWriter = {}
BufferWriter.__index = BufferWriter

-- ─────────────────────────────────────────
--  Constructor / helpers
-- ─────────────────────────────────────────
function BufferWriter.new(reserveBytes: number?)
	return setmetatable({
		_buffer = table.create(reserveBytes or 64), -- pre‑alloc
		_pos    = 1,
	}, BufferWriter)
end

function BufferWriter:Reserve(n: number)
	-- Extend capacity and advance write head
	for i = 1, n do
		self._buffer[self._pos] = "\0"
		self._pos += 1
	end
end

function BufferWriter:GetSize()   return self._pos - 1 end
function BufferWriter:GetBuffer() return table.concat(self._buffer, "", 1, self._pos - 1) end

-- ─────────────────────────────────────────
--  Core byte writers
-- ─────────────────────────────────────────
function BufferWriter:WriteUInt(n: number, size: number)
	for i = size - 1, 0, -1 do
		local byte = bit32.extract(n, i * 8, 8)
		self._buffer[self._pos] = string.char(byte)
		self._pos += 1
	end
end

local function maskForSize(size)
	if size == 4 then
		return 0xFFFFFFFF
	else
		return bit32.lshift(1, size * 8) - 1
	end
end

function BufferWriter:WriteInt(n: number, size: number)
	local encoded = (n < 0) and (maskForSize(size) + n + 1) or n
	self:WriteUInt(encoded, size)
end

-- size‑aware ZigZag (signed → unsigned)
local function ZigZagEncode(n, size)
	-- width in bits (24 for your 3‑byte coords)
	local bits = size * 8
	-- (n << 1) ^ (n >> (bits‑1))   – arithmetic shift for the sign
	local zz   = bit32.bxor(bit32.lshift(n, 1), bit32.arshift(n, bits-1))
	-- keep only the lowest <bits> bits so we never overflow the field
	return bit32.band(zz, bit32.lshift(1, bits) - 1)
end

function BufferWriter:WriteZigZag(n: number, size: number)
	self:WriteUInt(ZigZagEncode(n, size), size)
end

-- Floats ------------------------------------------------------
function BufferWriter:WriteFloat32(f) self:_writeBlob(string.pack(">f", f)) end
function BufferWriter:WriteFloat64(f) self:_writeBlob(string.pack(">d", f)) end
function BufferWriter:_writeBlob(s)
	for i = 1, #s do
		self._buffer[self._pos] = s:sub(i, i)
		self._pos += 1
	end
end

-- Strings -----------------------------------------------------
function BufferWriter:WriteString(str: string, size: number?)
	local n = size or #str
	str = str:sub(1, n)
	for i = 1, n do
		self._buffer[self._pos] = string.char(string.byte(str, i) or 0)
		self._pos += 1
	end
end

-- ─────────────────────────────────────────
--  Convenience auto‑writer
-- ─────────────────────────────────────────
function BufferWriter:WriteAuto(val, typeHint: string, byteSize: number?)
	if val == nil then
		error("BufferWriter: value for typeHint '" .. tostring(typeHint) .. "' is nil")
	end

	if typeHint == "string" then
		if self._countType then                          -- dynamic‑length
			local ct = self._countType ; self._countType = nil
			self:WriteAuto(#val, ct)                     -- length prefix
			self:WriteString(val)                        -- payload
		else                                             -- fixed‑width
			self:WriteString(val, byteSize)
		end
		return            

	elseif typeHint == "u8"   then self:WriteUInt(val, 1)
	elseif typeHint == "i8"   then self:WriteInt (val, 1)
	elseif typeHint == "u16"  then self:WriteUInt(val, 2)
	elseif typeHint == "i16"  then self:WriteInt (val, 2)
	elseif typeHint == "u24"  then self:WriteUInt(val, 3)
	elseif typeHint == "i24"  then self:WriteInt (val, 3)
	elseif typeHint == "u32"  then self:WriteUInt(val, 4)
	elseif typeHint == "i32"  then self:WriteInt (val, 4)

	elseif typeHint == "f32"  then self:WriteFloat32(val)
	elseif typeHint == "f64"  then self:WriteFloat64(val)

	elseif typeHint == "vec2" then
		if type(val) ~= "table" or val.x == nil or val.z == nil then
			error("BufferWriter: 'vec2' must be a table with 'x' and 'z'")
		end
		self:WriteZigZag(round(val.x * 1000), 3)
		self:WriteZigZag(round(val.z * 1000), 3)

	elseif typeHint == "vec3" then
		if typeof(val) ~= "Vector3" then
			error("BufferWriter: 'vec3' expects a Vector3")
		end
		self:WriteFloat32(val.X)
		self:WriteFloat32(val.Y)
		self:WriteFloat32(val.Z)

	elseif typeHint == "cframe" then
		if typeof(val) ~= "CFrame" then
			error("BufferWriter: 'cframe' expects a CFrame")
		end
		local p = val.Position
		self:WriteFloat32(p.X)
		self:WriteFloat32(p.Y)
		self:WriteFloat32(p.Z)

	elseif typeHint == "vec2List" then
		if type(val) ~= "table" then
			error("BufferWriter: 'vec2List' must be a table of {x, z}")
		end

		-- Determine count type (default to u16)
		local countType = self._countType or "u16"
		local countSize = (countType == "u8" and 1)
			or (countType == "u16" and 2)
			or (countType == "u32" and 4)
			or error("Unknown countType: " .. tostring(countType))

		self:WriteUInt(#val, countSize)

		for _, vec in ipairs(val) do
			self:WriteZigZag(round(vec.x * 1000), 3)
			self:WriteZigZag(round(vec.z * 1000), 3)
		end
		
	elseif typeHint == "u8List" then
		-- sizeOverride is **ignored** for the actual elements – it tells
		-- WriteAuto what integer type to use for the COUNT header.
		local countType = self._countType or "u16"   -- was set by Sload.Save
		self:WriteAuto(#val, countType)            -- write list length first
		for i = 1, #val do
			self:WriteUInt(val[i], 1)              -- each entry is a single byte
		end

	else
		error("BufferWriter: unknown typeHint '" .. tostring(typeHint) .. "'")
	end
end

return BufferWriter	
