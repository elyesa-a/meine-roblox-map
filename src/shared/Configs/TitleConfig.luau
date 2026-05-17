--!strict
-- Collectible player titles. Titles are unlocked by real milestones and can
-- provide small bonuses while equipped.

export type TitleBonus = {
	Power: number?,
	Dna: number?,
	Luck: number?,
}

export type TitleDef = {
	id: string,
	displayName: string,
	rarity: string,
	category: string,
	unlockText: string,
	color: Color3,
	bonus: TitleBonus?,
	condition: { kind: string, key: string?, value: number? }?,
}

local TitleConfig = {}

TitleConfig.RarityColors = {
	Common = Color3.fromRGB(245, 245, 245),
	Rare = Color3.fromRGB(90, 170, 255),
	Epic = Color3.fromRGB(205, 115, 255),
	Legendary = Color3.fromRGB(255, 210, 80),
	Mythic = Color3.fromRGB(255, 90, 210),
}

TitleConfig.Titles = {
	{ id = "Rookie", displayName = "Rookie", rarity = "Common", category = "Starter", unlockText = "Join the lab", color = TitleConfig.RarityColors.Common, condition = { kind = "Auto" } },
	{ id = "LabRookie", displayName = "Lab Rookie", rarity = "Common", category = "Starter", unlockText = "Reach 250 Power", color = TitleConfig.RarityColors.Common, condition = { kind = "Power", value = 250 } },
	{ id = "DNABeginner", displayName = "DNA Beginner", rarity = "Common", category = "Starter", unlockText = "Hold 1K DNA", color = TitleConfig.RarityColors.Common, bonus = { Dna = 0.02 }, condition = { kind = "Dna", value = 1000 } },
	{ id = "TestSubject", displayName = "Test Subject", rarity = "Common", category = "Starter", unlockText = "Train 50 times", color = TitleConfig.RarityColors.Common, condition = { kind = "Stat", key = "TrainTicks", value = 50 } },

	{ id = "PowerRookie", displayName = "Power Rookie", rarity = "Common", category = "Power", unlockText = "Reach 2.5K Power", color = TitleConfig.RarityColors.Common, bonus = { Power = 0.01 }, condition = { kind = "Power", value = 2500 } },
	{ id = "StrongMutant", displayName = "Strong Mutant", rarity = "Rare", category = "Power", unlockText = "Reach 10K Power", color = TitleConfig.RarityColors.Rare, bonus = { Power = 0.02 }, condition = { kind = "Power", value = 10000 } },
	{ id = "DNAWarrior", displayName = "DNA Warrior", rarity = "Rare", category = "Power", unlockText = "Reach 50K Power", color = TitleConfig.RarityColors.Rare, bonus = { Dna = 0.02 }, condition = { kind = "Power", value = 50000 } },
	{ id = "MutationFighter", displayName = "Mutation Fighter", rarity = "Epic", category = "Power", unlockText = "Reach 250K Power", color = TitleConfig.RarityColors.Epic, bonus = { Power = 0.03 }, condition = { kind = "Power", value = 250000 } },
	{ id = "BioCrusher", displayName = "Bio Crusher", rarity = "Epic", category = "Power", unlockText = "Reach 1M Power", color = TitleConfig.RarityColors.Epic, bonus = { Dna = 0.03 }, condition = { kind = "Power", value = 1000000 } },
	{ id = "GeneticBeast", displayName = "Genetic Beast", rarity = "Legendary", category = "Power", unlockText = "Reach 10M Power", color = TitleConfig.RarityColors.Legendary, bonus = { Power = 0.04 }, condition = { kind = "Power", value = 10000000 } },

	{ id = "Reborn", displayName = "Reborn", rarity = "Rare", category = "Rebirth", unlockText = "Perform 1 Rebirth", color = TitleConfig.RarityColors.Rare, bonus = { Dna = 0.03 }, condition = { kind = "Rebirth", value = 1 } },
	{ id = "RebirthHunter", displayName = "Rebirth Hunter", rarity = "Epic", category = "Rebirth", unlockText = "Reach 5 Rebirths", color = TitleConfig.RarityColors.Epic, bonus = { Power = 0.03 }, condition = { kind = "Rebirth", value = 5 } },
	{ id = "EvolutionMaster", displayName = "Evolution Master", rarity = "Epic", category = "Rebirth", unlockText = "Reach 15 Rebirths", color = TitleConfig.RarityColors.Epic, bonus = { Dna = 0.04 }, condition = { kind = "Rebirth", value = 15 } },
	{ id = "MutationAscended", displayName = "Mutation Ascended", rarity = "Legendary", category = "Rebirth", unlockText = "Reach 35 Rebirths", color = TitleConfig.RarityColors.Legendary, bonus = { Power = 0.04 }, condition = { kind = "Rebirth", value = 35 } },
	{ id = "ImmortalDNA", displayName = "Immortal DNA", rarity = "Mythic", category = "Rebirth", unlockText = "Reach 100 Rebirths", color = TitleConfig.RarityColors.Mythic, bonus = { Dna = 0.05, Power = 0.03 }, condition = { kind = "Rebirth", value = 100 } },

	{ id = "Shockborn", displayName = "Shockborn", rarity = "Rare", category = "Aura", unlockText = "Own Electric Aura", color = TitleConfig.RarityColors.Rare, bonus = { Power = 0.03 }, condition = { kind = "Aura", key = "Electric" } },
	{ id = "FrostCore", displayName = "Frost Core", rarity = "Rare", category = "Aura", unlockText = "Own Blizzard Aura", color = TitleConfig.RarityColors.Rare, bonus = { Power = 0.03 }, condition = { kind = "Aura", key = "Blizzard" } },
	{ id = "ToxicSoul", displayName = "Toxic Soul", rarity = "Epic", category = "Aura", unlockText = "Own Poison Aura", color = TitleConfig.RarityColors.Epic, bonus = { Dna = 0.03 }, condition = { kind = "Aura", key = "Poison" } },
	{ id = "MagmaBlood", displayName = "Magma Blood", rarity = "Epic", category = "Aura", unlockText = "Own Magma Aura", color = TitleConfig.RarityColors.Epic, bonus = { Power = 0.04 }, condition = { kind = "Aura", key = "Magma" } },
	{ id = "GlitchedOne", displayName = "Glitched One", rarity = "Legendary", category = "Aura", unlockText = "Own Glitch Aura", color = TitleConfig.RarityColors.Legendary, bonus = { Luck = 0.04 }, condition = { kind = "Aura", key = "Glitch" } },
	{ id = "RainbowEntity", displayName = "Rainbow Entity", rarity = "Mythic", category = "Aura", unlockText = "Own Rainbow Aura", color = TitleConfig.RarityColors.Mythic, bonus = { Luck = 0.05 }, condition = { kind = "Aura", key = "Rainbow" } },

	{ id = "BacteriaBreaker", displayName = "Bacteria Breaker", rarity = "Rare", category = "Boss", unlockText = "Defeat Bacteria King", color = TitleConfig.RarityColors.Rare, bonus = { Dna = 0.02 }, condition = { kind = "Boss", key = "MiniAntibodyKing" } },
	{ id = "VirusHunter", displayName = "Virus Hunter", rarity = "Epic", category = "Boss", unlockText = "Defeat Virus Brute", color = TitleConfig.RarityColors.Epic, bonus = { Dna = 0.03 }, condition = { kind = "Boss", key = "WhiteCellTitan" } },
	{ id = "ToxicSurvivor", displayName = "Toxic Survivor", rarity = "Epic", category = "Boss", unlockText = "Defeat Toxic Mutant", color = TitleConfig.RarityColors.Epic, bonus = { Power = 0.03 }, condition = { kind = "Boss", key = "DNAGuardianBoss" } },
	{ id = "MagmaCrusher", displayName = "Magma Crusher", rarity = "Legendary", category = "Boss", unlockText = "Defeat Magma Beast", color = TitleConfig.RarityColors.Legendary, bonus = { Power = 0.04 }, condition = { kind = "Boss", key = "LockdownBoss" } },
	{ id = "GlitchSlayer", displayName = "Glitch Slayer", rarity = "Legendary", category = "Boss", unlockText = "Defeat Glitch Overlord", color = TitleConfig.RarityColors.Legendary, bonus = { Luck = 0.04 }, condition = { kind = "Boss", key = "AntiVirusCore" } },
	{ id = "FinalMutation", displayName = "Final Mutation", rarity = "Mythic", category = "Boss", unlockText = "Defeat Final Experiment", color = TitleConfig.RarityColors.Mythic, bonus = { Dna = 0.05, Power = 0.05 }, condition = { kind = "Boss", key = "OmegaImmuneBoss" } },

	{ id = "LuckySpinner", displayName = "Lucky Spinner", rarity = "Epic", category = "Flex", unlockText = "Win a Rebirth from Lucky Wheel", color = TitleConfig.RarityColors.Epic, bonus = { Luck = 0.03 }, condition = { kind = "Stat", key = "RebirthSpinWins", value = 1 } },
	{ id = "RichDNA", displayName = "Rich DNA", rarity = "Legendary", category = "Flex", unlockText = "Hold 100K DNA", color = TitleConfig.RarityColors.Legendary, bonus = { Dna = 0.04 }, condition = { kind = "Dna", value = 100000 } },
	{ id = "DailyRookie", displayName = "Daily Rookie", rarity = "Common", category = "Daily", unlockText = "Complete 1 Daily Quest", color = TitleConfig.RarityColors.Common, condition = { kind = "Stat", key = "DailyQuestClaims", value = 1 } },
	{ id = "ConsistentSubject", displayName = "Consistent Subject", rarity = "Rare", category = "Daily", unlockText = "Complete 7 Daily Quests", color = TitleConfig.RarityColors.Rare, bonus = { Dna = 0.02 }, condition = { kind = "Stat", key = "DailyQuestClaims", value = 7 } },
	{ id = "DailyGrinder", displayName = "Daily Grinder", rarity = "Epic", category = "Daily", unlockText = "Complete 25 Daily Quests", color = TitleConfig.RarityColors.Epic, bonus = { Power = 0.03 }, condition = { kind = "Stat", key = "DailyQuestClaims", value = 25 } },
	{ id = "LabEmployee", displayName = "Lab Employee", rarity = "Legendary", category = "Daily", unlockText = "Complete 50 Daily Quests", color = TitleConfig.RarityColors.Legendary, bonus = { Dna = 0.04 }, condition = { kind = "Stat", key = "DailyQuestClaims", value = 50 } },
}

local byId: { [string]: TitleDef } = {}

for _, title in ipairs(TitleConfig.Titles) do
	byId[title.id] = title
end

function TitleConfig.getById(id: string): TitleDef?
	return byId[id]
end

return TitleConfig
