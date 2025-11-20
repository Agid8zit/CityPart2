local SaveKeyNames = {}

function SaveKeyNames.primary(userId, slotId)
	return ("p:%s:s:%s:v1"):format(tostring(userId), tostring(slotId))
end

function SaveKeyNames.backup(userId, slotId)
	local ts = os.date("!%Y-%m-%dT%H-%M-%SZ")
	local rand = tostring(math.random(100000, 999999))
	return ("b:%s:s:%s:%s:%s"):format(tostring(userId), tostring(slotId), ts, rand)
end

function SaveKeyNames.parse(key)
	local tokens = {}
	for token in string.gmatch(key, "([^:]+)") do
		table.insert(tokens, token)
	end
	if tokens[1] == "p" then
		return { kind = "primary", userId = tokens[2], slot = tokens[4] }
	end
	if tokens[1] == "b" then
		return { kind = "backup", userId = tokens[2], slot = tokens[4] }
	end
	return nil
end

return SaveKeyNames
