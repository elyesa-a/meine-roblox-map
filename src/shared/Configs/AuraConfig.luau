--!strict
-- Area-tiered aura definitions. Area 1 is available by default; every boss
-- defeat unlocks the next aura tier up to Area 10.

export type AuraDef = {
	id: string,
	displayName: string,
	multiplier: number,
	priceDna: number,
	requiredTier: number,
	requiredBossDefeated: number,
	color: Color3,
	description: string?,
	legacyIds: { string }?,
	colorSequence: ColorSequence?,
}

local AuraConfig = {}

AuraConfig.MaxTier = 10

AuraConfig.Auras = {
	-- Tier 1 / Area 1
	{ id = "Electric", displayName = "Electric Aura", multiplier = 1.5, priceDna = 300, requiredTier = 1, requiredBossDefeated = 0, color = Color3.fromRGB(120, 220, 255), description = "Starter electric mutation field." },
	{ id = "Poison", displayName = "Poison Aura", multiplier = 2.0, priceDna = 450, requiredTier = 1, requiredBossDefeated = 0, color = Color3.fromRGB(90, 255, 120), description = "Toxic starter bio-field." },

	-- Tier 2 / Beat Area 1 Boss
	{ id = "Frost", displayName = "Frost Aura", multiplier = 3.0, priceDna = 1_500, requiredTier = 2, requiredBossDefeated = 1, color = Color3.fromRGB(170, 230, 255), description = "Cold containment energy.", legacyIds = { "Blizzard" } },
	{ id = "Toxic", displayName = "Toxic Aura", multiplier = 3.5, priceDna = 2_700, requiredTier = 2, requiredBossDefeated = 1, color = Color3.fromRGB(105, 235, 95), description = "Unstable lab toxin cloud." },

	-- Tier 3 / Beat Area 2 Boss
	{ id = "Magma", displayName = "Magma Aura", multiplier = 5.0, priceDna = 7_200, requiredTier = 3, requiredBossDefeated = 2, color = Color3.fromRGB(255, 120, 60), description = "Heated mutation pressure." },
	{ id = "Venom", displayName = "Venom Aura", multiplier = 6.0, priceDna = 10_800, requiredTier = 3, requiredBossDefeated = 2, color = Color3.fromRGB(58, 175, 78), description = "Dense venom cell field." },

	-- Tier 4 / Beat Area 3 Boss
	{ id = "Plasma", displayName = "Plasma Aura", multiplier = 8.0, priceDna = 27_000, requiredTier = 4, requiredBossDefeated = 3, color = Color3.fromRGB(115, 210, 255), description = "High-voltage plasma shell.", legacyIds = { "Purple" } },
	{ id = "Biohazard", displayName = "Biohazard Aura", multiplier = 10.0, priceDna = 45_000, requiredTier = 4, requiredBossDefeated = 3, color = Color3.fromRGB(180, 220, 65), description = "Containment breach warning field." },

	-- Tier 5 / Beat Area 4 Boss
	{ id = "Mutation", displayName = "Mutation Aura", multiplier = 13.0, priceDna = 90_000, requiredTier = 5, requiredBossDefeated = 4, color = Color3.fromRGB(80, 255, 160), description = "Pulsing DNA mutation shell." },
	{ id = "VirusCore", displayName = "Virus Core Aura", multiplier = 16.0, priceDna = 144_000, requiredTier = 5, requiredBossDefeated = 4, color = Color3.fromRGB(70, 230, 105), description = "Core virus reactor glow." },

	-- Tier 6 / Beat Area 5 Boss
	{ id = "GlitchDna", displayName = "Glitch DNA Aura", multiplier = 20.0, priceDna = 270_000, requiredTier = 6, requiredBossDefeated = 5, color = Color3.fromRGB(95, 235, 255), description = "Fragmented DNA signal field.", legacyIds = { "Glitch" } },
	{ id = "Corrupted", displayName = "Corrupted Aura", multiplier = 25.0, priceDna = 420_000, requiredTier = 6, requiredBossDefeated = 5, color = Color3.fromRGB(92, 80, 112), description = "Dark corrupted infection cloud." },

	-- Tier 7 / Beat Area 6 Boss
	{ id = "DarkInfection", displayName = "Dark Infection Aura", multiplier = 32.0, priceDna = 720_000, requiredTier = 7, requiredBossDefeated = 6, color = Color3.fromRGB(35, 150, 82), description = "Black-green infection energy." },
	{ id = "Omega", displayName = "Omega Aura", multiplier = 40.0, priceDna = 1_140_000, requiredTier = 7, requiredBossDefeated = 6, color = Color3.fromRGB(80, 235, 220), description = "Omega-tier lab stabilizer." },

	-- Tier 8 / Beat Area 7 Boss
	{ id = "AlienVirus", displayName = "Alien Virus Aura", multiplier = 50.0, priceDna = 1_920_000, requiredTier = 8, requiredBossDefeated = 7, color = Color3.fromRGB(95, 255, 95), description = "Foreign organism energy." },
	{ id = "QuantumDna", displayName = "Quantum DNA Aura", multiplier = 65.0, priceDna = 3_120_000, requiredTier = 8, requiredBossDefeated = 7, color = Color3.fromRGB(90, 190, 255), description = "Quantum DNA orbit field." },

	-- Tier 9 / Beat Area 8 Boss
	{ id = "FinalPlague", displayName = "Final Plague Aura", multiplier = 80.0, priceDna = 5_400_000, requiredTier = 9, requiredBossDefeated = 8, color = Color3.fromRGB(120, 55, 62), description = "Late-stage plague energy." },
	{ id = "Overlord", displayName = "Overlord Aura", multiplier = 100.0, priceDna = 8_400_000, requiredTier = 9, requiredBossDefeated = 8, color = Color3.fromRGB(190, 75, 255), description = "Dominant mutation control field." },

	-- Tier 10 / Beat Area 9 Boss
	{ id = "GodMutation", displayName = "God Mutation Aura", multiplier = 125.0, priceDna = 14_400_000, requiredTier = 10, requiredBossDefeated = 9, color = Color3.fromRGB(245, 245, 210), description = "Elite god mutation stabilizer.", legacyIds = { "Rainbow" } },
	{ id = "ApexVirus", displayName = "Apex Virus Aura", multiplier = 150.0, priceDna = 24_000_000, requiredTier = 10, requiredBossDefeated = 9, color = Color3.fromRGB(255, 70, 85), description = "Final apex virus field." },
} :: { AuraDef }

local byId: { [string]: AuraDef } = {}
for _, def in ipairs(AuraConfig.Auras) do
	byId[def.id] = def
	if def.legacyIds then
		for _, legacyId in ipairs(def.legacyIds) do
			byId[legacyId] = def
		end
	end
end

function AuraConfig.getById(id: string): AuraDef?
	return byId[id]
end

function AuraConfig.matchesId(def: AuraDef, auraId: string?): boolean
	if auraId == nil then
		return false
	end
	if auraId == def.id then
		return true
	end
	if def.legacyIds then
		for _, legacyId in ipairs(def.legacyIds) do
			if auraId == legacyId then
				return true
			end
		end
	end
	return false
end

function AuraConfig.getUnlockedTier(highestBossDefeated: number?): number
	local defeated = if type(highestBossDefeated) == "number" then highestBossDefeated else 0
	return math.clamp(math.floor(defeated) + 1, 1, AuraConfig.MaxTier)
end

function AuraConfig.getLockedText(def: AuraDef): string
	if def.requiredBossDefeated <= 0 then
		return "Unlocked"
	end
	return "Beat Area " .. tostring(def.requiredBossDefeated) .. " Boss to unlock"
end

return AuraConfig
