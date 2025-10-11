--[[──────────────────────────────────────────────────────────
    • 1  Millistud ×1000  → int
    • 2  Round (float‑error guard)
    • 3  Strip Y‑axis (Vec3 → Vec2)
    • 4  Custom 64‑digit int codec   (signed supported via ZigZag)
    • 5  Comma‑join flat arrays
    • 6  JSON‑wrap
    • 7  Bit‑pack booleans (bit32.* API—native in Luau)
    • 8  ≤6‑char short‑tag helper
    • 9  Optional final Base‑64 (pure Luau, maths‑only)

    Public table:  EncodeInt / DecodeInt, Vec2ListToString /
                   StringToVec2List, PackFlags / UnpackFlags,
                   ShortTag, Finalise, Definalise, DebugRoundTrip
────────────────────────────────────────────────────────────]]--

local HttpService = game:GetService("HttpService")

----------------------------------------------------------------
--  General helpers
----------------------------------------------------------------
local round = math.round or function(n: number): number
	return n >= 0 and math.floor(n + 0.5) or math.ceil(n - 0.5)
end

-- Debug pretty‑print (optional)
local function _pp(val, indent)
	indent = indent or ""
	if typeof(val) ~= "table" then
		return tostring(val)
	end
	local parts = {"{"}
	for k, v in pairs(val) do
		parts[#parts + 1] = indent .. "  " .. tostring(k) .. " = " .. _pp(v, indent .. "  ")
	end
	parts[#parts + 1] = indent .. "}"
	return table.concat(parts, "\n")
end

----------------------------------------------------------------
--  Custom 64‑digit alphabet for **integer** encoding
----------------------------------------------------------------
local INT_ALPH = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+/"
local INT_LOOK = {}
for i = 1, #INT_ALPH do
	INT_LOOK[INT_ALPH:sub(i, i)] = i - 1
end

----------------------------------------------------------------
--  ZigZag mapping  (signed <‑‑> unsigned)
----------------------------------------------------------------
local function zigzag(n: number): number       --   0 → 0,  -1 → 1,  1 → 2 …
	return n >= 0 and n * 2 or (-n * 2 - 1)
end
local function unzigzag(u: number): number
	local half = math.floor(u / 2)
	return (u % 2 == 0) and half or -(half + 1)
end

----------------------------------------------------------------
--  Unsigned int  ↔  base‑64 string  (no bit ops)
----------------------------------------------------------------
local function uIntEncode(n: number): string
	if n == 0 then return "0" end
	local chars = {}
	while n > 0 do
		local r = n % 64
		chars[#chars + 1] = INT_ALPH:sub(r + 1, r + 1)
		n = math.floor(n / 64)
	end
	-- built LSB‑first ⇒ reverse in‑place
	for i = 1, #chars // 2 do
		chars[i], chars[#chars - i + 1] = chars[#chars - i + 1], chars[i]
	end
	return table.concat(chars)
end

local function uIntDecode(s: string): number
	local n = 0
	for i = 1, #s do
		n = n * 64 + INT_LOOK[s:sub(i, i)]
	end
	return n
end

-- Signed helpers (public)
local function sIntEncode(n: number): string
	return uIntEncode(zigzag(n))
end
local function sIntDecode(s: string): number
	return unzigzag(uIntDecode(s))
end

----------------------------------------------------------------
--  Vec2 list  ↔  compact comma string  (stages 1‑5)
----------------------------------------------------------------
local function vec2ListToString(list: { {x: number, z: number} }): string
	if not list or #list == 0 then return "" end
	local out = table.create(#list * 2)
	for _, v in ipairs(list) do
		out[#out + 1] = sIntEncode(round(v.x * 1000))
		out[#out + 1] = sIntEncode(round(v.z * 1000))
	end
	return table.concat(out, ",")
end

local function stringToVec2List(str: string): { {x: number, z: number} }
	if not str or str == "" then return {} end
	local arr, out = string.split(str, ","), {}
	for i = 1, #arr, 2 do
		out[#out + 1] = {
			x = sIntDecode(arr[i])     / 1000,
			z = sIntDecode(arr[i + 1]) / 1000,
		}
	end
	return out
end

----------------------------------------------------------------
--  Bit‑pack booleans  (bit32 API is native in Luau)
----------------------------------------------------------------
local function packFlags(tbl: {[string]: boolean}, order: {string}): number
	local byte = 0
	for i, key in ipairs(order) do
		if tbl[key] then
			byte = bit32.bor(byte, bit32.lshift(1, i - 1))
		end
	end
	return byte
end

local function unpackFlags(byte: number, order: {string}): {[string]: boolean}
	local out = {}
	for i, key in ipairs(order) do
		out[key] = bit32.band(byte, bit32.lshift(1, i - 1)) ~= 0
	end
	return out
end

----------------------------------------------------------------
--  ≤6‑char tag helper
----------------------------------------------------------------
local function shortTag(s: string, maxLen: number?): string
	maxLen = maxLen or 6
	return (#s <= maxLen) and s or s:sub(1, maxLen)
end

----------------------------------------------------------------
--  Pure‑Luau Base‑64 for stage 9  (maths‑only, no bit ops)
----------------------------------------------------------------
local B64_ALPH = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_LOOK = {}
for i = 1, #B64_ALPH do
	B64_LOOK[B64_ALPH:sub(i, i)] = i - 1
end

local function b64encode(bin: string): string
	local len, out = #bin, table.create(((#bin + 2) // 3) * 4)
	for i = 1, len, 3 do
		local b1 = bin:byte(i    ) or 0
		local b2 = bin:byte(i + 1) or 0
		local b3 = bin:byte(i + 2) or 0

		local c1 = math.floor(b1 / 4)
		local c2 = (b1 % 4)      * 16 + math.floor(b2 / 16)
		local c3 = (b2 % 16)     * 4  + math.floor(b3 / 64)
		local c4 =  b3 % 64

		out[#out + 1] = B64_ALPH:sub(c1 + 1, c1 + 1)
		out[#out + 1] = B64_ALPH:sub(c2 + 1, c2 + 1)
		out[#out + 1] = (i + 1 <= len) and B64_ALPH:sub(c3 + 1, c3 + 1) or "="
		out[#out + 1] = (i + 2 <= len) and B64_ALPH:sub(c4 + 1, c4 + 1) or "="
	end
	return table.concat(out)
end

local function b64decode(text: string): string
	text = text:gsub("[%s\n]", "")
	local len, out = #text, table.create((#text // 4) * 3)

	for i = 1, len, 4 do
		local c1 = B64_LOOK[text:sub(i, i)]       or 0
		local c2 = B64_LOOK[text:sub(i + 1, i + 1)] or 0
		local c3 = (text:sub(i + 2, i + 2) ~= "=") and (B64_LOOK[text:sub(i + 2, i + 2)] or 0) or nil
		local c4 = (text:sub(i + 3, i + 3) ~= "=") and (B64_LOOK[text:sub(i + 3, i + 3)] or 0) or nil

		local b1 = c1 * 4 + math.floor(c2 / 16)
		local b2 = (c2 % 16) * 16 + (c3 and math.floor(c3 / 4) or 0)
		local b3 = (c3 and (c3 % 4) * 64 or 0) + (c4 or 0)

		out[#out + 1] = string.char(b1)
		if c3 then out[#out + 1] = string.char(b2) end
		if c4 then out[#out + 1] = string.char(b3) end
	end
	return table.concat(out)
end

----------------------------------------------------------------
--  Optional raw‑table size estimator (debug only)
----------------------------------------------------------------
local function sizeof(val, seen)
	local t = typeof(val)
	if t == "string"  then return #val
	elseif t == "number"  then return 8
	elseif t == "boolean" then return 1
	elseif t == "table" then
		seen = seen or {}
		if seen[val] then return 0 end
		seen[val] = true
		local bytes = 0
		for k, v in pairs(val) do
			bytes += sizeof(k, seen) + sizeof(v, seen)
		end
		return bytes
	else
		return 0
	end
end


local _WEALTH_ENUM = { Poor = 0, Medium = 1, Wealthy = 2 }
local _WEALTH_STR  = { [0] = "Poor", [1] = "Medium", [2] = "Wealthy" }

local function encodeWealthList(list: {string}): {number}
	if not list then return {} end
	local out = table.create(#list)
	for i, state in ipairs(list) do
		local n = _WEALTH_ENUM[state]
		if n == nil then
			error(("EncodeWealthList: unknown wealth value “%s” at index %d")
				:format(tostring(state), i))
		end
		out[i] = n
	end
	return out            -- {u8, u8, …}
end

local function decodeWealthList(arr: {number}): {string}
	if not arr then return {} end
	local out = table.create(#arr)
	for i, n in ipairs(arr) do
		local s = _WEALTH_STR[n]
		if s == nil then
			error(("DecodeWealthList: unknown wealth enum %d at index %d"):format(n, i))
		end
		out[i] = s
	end
	return out
end

----------------------------------------------------------------
--  Per‑tile requirement flags list  ↔  numeric u8 list
----------------------------------------------------------------
local function encodeTileFlagsList(list: { {[string]: boolean} }, order: {string}): {number}
	order = order or { "Road", "Water", "Power", "Populated" }
	if not list then return {} end
	local out = table.create(#list)
	for i, flags in ipairs(list) do
		out[i] = packFlags(flags, order)   -- returns 0‑255
	end
	return out
end

local function decodeTileFlagsList(arr: {number}, order: {string}): { {[string]: boolean} }
	order = order or { "Road", "Water", "Power", "Populated" }
	if not arr then return {} end
	local out = table.create(#arr)
	for i, byte in ipairs(arr) do
		out[i] = unpackFlags(byte, order)
	end
	return out
end

----------------------------------------------------------------
--  Public API table
----------------------------------------------------------------
local Compressor = {
	-- integer helpers
	EncodeInt   = sIntEncode,
	DecodeInt   = sIntDecode,
	EncodeUInt  = uIntEncode,
	DecodeUInt  = uIntDecode,

	-- coordinate helpers
	Vec2ListToString = vec2ListToString,
	StringToVec2List = stringToVec2List,

	-- flag helpers
	PackFlags   = packFlags,
	UnpackFlags = unpackFlags,

	-- tag helper
	ShortTag    = shortTag,

	-- compression stages
	Finalise    = nil, -- filled below
	Definalise  = nil,
	DebugRoundTrip = nil,

	-- expose b64 for debug usage
	b64encode   = b64encode,
	b64decode   = b64decode,
	
	-- list encoders / decoders
	EncodeWealthList     = encodeWealthList,
	DecodeWealthList     = decodeWealthList,
	EncodeTileFlagsList  = encodeTileFlagsList,
	DecodeTileFlagsList  = decodeTileFlagsList,
}
----------------------------------------------------------------
--  Finalise  /  Definalise
----------------------------------------------------------------
function Compressor.Finalise(tbl: any, useB64: boolean?, debug: boolean?, binaryWriter: any?): string
	local json = HttpService:JSONEncode(tbl)           -- stage 6
	local result = (useB64 == false) and json or b64encode(json)

	if debug then
		print("▼▼  Compressor Debug  ▼▼")
		print("  • Raw table bytes :", sizeof(tbl))
		print("  • JSON bytes      :", #json)
		if useB64 ~= false then
			print("  • Base64 bytes    :", #result)
		end
		if binaryWriter then
			print("  • Buffer bytes    :", binaryWriter:GetSize())
		end
		print("TABLE BEFORE COMPRESSION ↓\n" .. _pp(tbl))
	end
	return result
end

function Compressor.Definalise(str: string, useB64: boolean?, debug: boolean?): any
	local json = (useB64 == false) and str or b64decode(str)
	local tbl  = HttpService:JSONDecode(json)
	if debug then
		print("TABLE AFTER DECOMPRESSION ↓\n" .. _pp(tbl))
	end
	return tbl
end

function Compressor.DebugRoundTrip(tbl: any, useB64: boolean?)
	local packed   = Compressor.Finalise(tbl, useB64, true)
	local unpacked = Compressor.Definalise(packed, useB64, true)
	return packed, unpacked
end


return Compressor
