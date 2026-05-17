--!strict
-- Spin-Wheel rewards. weight = relative chance.
-- type can be "Dna", "Power", "Luck", or "Rebirth".

export type SpinReward = {
	id: string,
	displayName: string,
	type: string,
	amount: number,
	rarity: string,
	boostSeconds: number?,
	weight: number,
	color: Color3,
}

local SpinConfig = {}

SpinConfig.CooldownSec = 1800 -- 30 Minuten zwischen Free-Spins

SpinConfig.Rewards = {
	{ id = "DnaSmall", displayName = "+100 DNA", type = "Dna", amount = 100, rarity = "Common", weight = 32, color = Color3.fromRGB(245, 248, 255) },
	{ id = "PowerSmall", displayName = "+250 Power", type = "Power", amount = 250, rarity = "Common", weight = 24, color = Color3.fromRGB(70, 155, 255) },
	{ id = "LuckSmall", displayName = "+25 Luck", type = "Luck", amount = 25, boostSeconds = 300, rarity = "Common", weight = 18, color = Color3.fromRGB(245, 70, 80) },
	{ id = "DnaMedium", displayName = "+500 DNA", type = "Dna", amount = 500, rarity = "Rare", weight = 12, color = Color3.fromRGB(245, 248, 255) },
	{ id = "PowerMedium", displayName = "+2.5K Power", type = "Power", amount = 2500, rarity = "Rare", weight = 8, color = Color3.fromRGB(70, 155, 255) },
	{ id = "LuckBig", displayName = "+100 Luck", type = "Luck", amount = 100, boostSeconds = 900, rarity = "Rare", weight = 5, color = Color3.fromRGB(245, 70, 80) },
	{ id = "DnaBig", displayName = "+5K DNA", type = "Dna", amount = 5000, rarity = "Epic", weight = 2.5, color = Color3.fromRGB(245, 248, 255) },
	{ id = "RebirthOne", displayName = "+1 Rebirth", type = "Rebirth", amount = 1, rarity = "Epic", weight = 1.2, color = Color3.fromRGB(70, 155, 255) },
	{ id = "RebirthFive", displayName = "+5 Rebirths", type = "Rebirth", amount = 5, rarity = "Legendary", weight = 0.35, color = Color3.fromRGB(245, 70, 80) },
	{ id = "RebirthTen", displayName = "+10 Rebirths", type = "Rebirth", amount = 10, rarity = "Mythic", weight = 0.08, color = Color3.fromRGB(245, 248, 255) },
}

function SpinConfig.totalWeight(): number
	local total = 0
	for _, r in ipairs(SpinConfig.Rewards) do
		total += r.weight
	end
	return total
end

return SpinConfig
