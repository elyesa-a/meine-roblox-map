--!strict
-- Boosts: zeitlich begrenzte Multiplikatoren, fuer DNA-Coins kaufbar (Phase 4).
-- "affects" kann sein: "Power", "Dna", "Luck"

export type BoostDef = {
	id: string,
	displayName: string,
	multiplier: number,
	affects: string,
	durationSec: number,
	priceDna: number,
	color: Color3,
}

local BoostConfig = {}

BoostConfig.Boosts = {
	{ id = "Power2x", displayName = "2x Kraft", multiplier = 2, affects = "Power", durationSec = 600, priceDna = 200, color = Color3.fromRGB(255, 90, 90) },
	{ id = "Dna2x", displayName = "2x DNA", multiplier = 2, affects = "Dna", durationSec = 600, priceDna = 200, color = Color3.fromRGB(80, 160, 255) },
	{ id = "Luck2x", displayName = "2x Glueck", multiplier = 2, affects = "Luck", durationSec = 600, priceDna = 200, color = Color3.fromRGB(255, 215, 60) },
}

function BoostConfig.getById(id: string): BoostDef?
	for _, def in ipairs(BoostConfig.Boosts) do
		if def.id == id then
			return def :: BoostDef
		end
	end
	return nil
end

return BoostConfig
