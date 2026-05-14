--!strict
-- Kompakte Zahlenformatierung: 1.2K, 3.4M, 2.1B, ...

local NumberFormatter = {}

local suffixes = {
	{ value = 1e15, suffix = "Qa" },
	{ value = 1e12, suffix = "T" },
	{ value = 1e9, suffix = "B" },
	{ value = 1e6, suffix = "M" },
	{ value = 1e3, suffix = "K" },
}

function NumberFormatter.format(n: number): string
	if n < 0 then
		return "-" .. NumberFormatter.format(-n)
	end
	for _, entry in ipairs(suffixes) do
		if n >= entry.value then
			local v = n / entry.value
			-- 1 Nachkommastelle, aber kein nachgestelltes .0
			local s = string.format("%.1f", v)
			if s:sub(-2) == ".0" then
				s = s:sub(1, -3)
			end
			return s .. entry.suffix
		end
	end
	return tostring(math.floor(n))
end

return NumberFormatter
