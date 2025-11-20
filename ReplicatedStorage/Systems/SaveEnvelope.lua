-- SaveEnvelope.lua
-- Non-breaking wrapper that attaches metadata to any payload without altering game semantics.
local HttpService = game:GetService("HttpService")

local SaveEnvelope = {}

-- Very simple 32-bit rolling hash (Adler-32 style) to dedupe identical saves.
local function fastHash(str)
	local a, b = 1, 0
	for i = 1, #str do
		a = (a + string.byte(str, i)) % 65521
		b = (b + a) % 65521
	end
	return string.format("%08x%08x", a, b)
end

local function encodePayload(payloadTable)
	local encoded = HttpService:JSONEncode(payloadTable)
	return encoded, #encoded
end

function SaveEnvelope.wrap(slotId, payloadTable, schemaVersion)
	local encoded, approxBytes = encodePayload(payloadTable)
	local now = os.time()
	return {
		_envelope = {
			version = 1,
			schema = schemaVersion or (payloadTable.Version or 1),
			slot = tostring(slotId),
			createdAt = now,
			updatedAt = now,
			hash = fastHash(encoded),
			approxBytes = approxBytes,
		},
		data = payloadTable,
	}
end

function SaveEnvelope.touch(enveloped)
	if enveloped and enveloped._envelope then
		enveloped._envelope.updatedAt = os.time()
	end
	return enveloped
end

function SaveEnvelope.hashOf(enveloped)
	if enveloped and enveloped._envelope and enveloped.data then
		return enveloped._envelope.hash
	end
	local encoded = HttpService:JSONEncode(enveloped)
	return fastHash(encoded)
end

function SaveEnvelope.bytesOf(enveloped)
	if enveloped and enveloped._envelope then
		return enveloped._envelope.approxBytes or -1
	end
	local _, approxBytes = encodePayload(enveloped)
	return approxBytes
end

return SaveEnvelope
