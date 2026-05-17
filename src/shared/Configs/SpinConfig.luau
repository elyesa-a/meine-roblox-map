--!strict
-- Spin-Wheel-Belohnungen. weight = relative Wahrscheinlichkeit.
-- type kann sein: "Dna", "Power", "Pet"
-- Bei "Pet": id im SpinReward verweist auf PetConfig.id; nil = zufaelliges Pet.

export type SpinReward = {
	id: string,
	displayName: string,
	type: string,
	amount: number,
	-- Optional, fuer Pet-Belohnungen
	petId: string?,
	weight: number,
	color: Color3,
}

local SpinConfig = {}

SpinConfig.CooldownSec = 1800 -- 30 Minuten zwischen Free-Spins

SpinConfig.Rewards = {
	{ id = "DnaSmall", displayName = "+25 DNA", type = "Dna", amount = 25, weight = 40, color = Color3.fromRGB(80, 160, 255) },
	{ id = "DnaMedium", displayName = "+100 DNA", type = "Dna", amount = 100, weight = 20, color = Color3.fromRGB(80, 160, 255) },
	{ id = "DnaBig", displayName = "+500 DNA", type = "Dna", amount = 500, weight = 5, color = Color3.fromRGB(60, 120, 255) },
	{ id = "PowerSmall", displayName = "+250 Power", type = "Power", amount = 250, weight = 15, color = Color3.fromRGB(255, 100, 100) },
	{ id = "PowerMedium", displayName = "+1.5K Power", type = "Power", amount = 1500, weight = 10, color = Color3.fromRGB(255, 100, 100) },
	{ id = "PowerBig", displayName = "+10K Power", type = "Power", amount = 10000, weight = 4, color = Color3.fromRGB(255, 60, 60) },
	{ id = "PetCommon", displayName = "Pet (Common+)", type = "Pet", amount = 1, weight = 5, color = Color3.fromRGB(200, 120, 255) },
	{ id = "PetEpic", displayName = "Pet (Epic+)", type = "Pet", amount = 1, weight = 1, color = Color3.fromRGB(255, 80, 200) },
}

function SpinConfig.totalWeight(): number
	local total = 0
	for _, r in ipairs(SpinConfig.Rewards) do
		total += r.weight
	end
	return total
end

return SpinConfig
