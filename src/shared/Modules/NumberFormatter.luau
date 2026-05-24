--!strict
-- Kompakte Zahlenformatierung: 1.2K, 3.4M, 2.1B, ...
--
-- Erweitert fuer das Virus-Labor (100 Gegner, *4 Scaling). Gegner 100 erreicht
-- ~4e61, deshalb reicht die Suffix-Tabelle bis weit ueber Dc hinaus.
-- WICHTIG: rein additiv -- kleine Zahlen werden exakt wie vorher formatiert,
-- damit das bestehende UI unveraendert bleibt.

local NumberFormatter = {}

local function trimTrailingZeroes(text: string): string
	while text:sub(-1) == "0" do
		text = text:sub(1, -2)
	end
	if text:sub(-1) == "." then
		text = text:sub(1, -2)
	end
	return text
end

-- Reihenfolge: groesster Wert zuerst (die Schleife nimmt den ersten Treffer).
local suffixes = {
	{ value = 1e63, suffix = "Vg" },
	{ value = 1e60, suffix = "NoDc" },
	{ value = 1e57, suffix = "OcDc" },
	{ value = 1e54, suffix = "SpDc" },
	{ value = 1e51, suffix = "SxDc" },
	{ value = 1e48, suffix = "QiDc" },
	{ value = 1e45, suffix = "QaDc" },
	{ value = 1e42, suffix = "TDc" },
	{ value = 1e39, suffix = "DDc" },
	{ value = 1e36, suffix = "UDc" },
	{ value = 1e33, suffix = "Dc" },
	{ value = 1e30, suffix = "No" },
	{ value = 1e27, suffix = "Oc" },
	{ value = 1e24, suffix = "Sp" },
	{ value = 1e21, suffix = "Sx" },
	{ value = 1e18, suffix = "Qi" },
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
	if n ~= n or n == math.huge then
		-- NaN / inf defensiv abfangen, damit Labels nie crashen.
		return "∞"
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

function NumberFormatter.formatDecimal(n: number, maxDecimals: number?): string
	if n < 0 then
		return "-" .. NumberFormatter.formatDecimal(-n, maxDecimals)
	end
	if n ~= n or n == math.huge then
		return "∞"
	end

	local decimals = math.floor(maxDecimals or 2)
	decimals = math.clamp(decimals, 0, 6)

	local scale = 10 ^ decimals
	local rounded = math.floor(n * scale + 0.5) / scale
	if decimals == 0 then
		return tostring(math.floor(rounded))
	end

	return trimTrailingZeroes(string.format("%." .. tostring(decimals) .. "f", rounded))
end

return NumberFormatter
