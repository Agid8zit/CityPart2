local Abbrev = {}

local suffixes = { "", "k", "m", "b", "t" }

function Abbrev.abbreviateNumber(n)
	-- Convert to number if it's a string (and not nil)
	n = tonumber(n)
	if not n then
		return "NaN"
	end
	local sign = n < 0 and "-" or ""
	n = math.abs(n)
	local i = 1
	while n >= 1000 and i < #suffixes do
		n = n / 1000
		i = i + 1
	end
	local str = string.format("%.1f", n):gsub("%.0$", "")
	return sign .. str .. suffixes[i]
end

return Abbrev