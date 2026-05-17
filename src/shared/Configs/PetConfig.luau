--!strict
-- Pet-Definitionen + Raritaets-Farben + Egg-Gewichte fuer Drops.

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary" | "Mythic"

export type PetDef = {
	id: string,
	displayName: string,
	rarity: Rarity,
	multiplier: number,
}

local PetConfig = {}

PetConfig.MaxInventorySize = 50
PetConfig.MaxEquipped = 3

PetConfig.RarityColor = {
	Common = Color3.fromRGB(180, 180, 180),
	Rare = Color3.fromRGB(80, 160, 255),
	Epic = Color3.fromRGB(180, 100, 255),
	Legendary = Color3.fromRGB(255, 200, 60),
	Mythic = Color3.fromRGB(255, 80, 140),
} :: { [string]: Color3 }

-- Drop-Gewichte fuer das Egg (Summe muss nicht 100 sein, wir normalisieren).
PetConfig.RarityWeights = {
	Common = 60,
	Rare = 25,
	Epic = 10,
	Legendary = 4,
	Mythic = 1,
} :: { [string]: number }

PetConfig.Pets = {
	{ id = "MiniVirus", displayName = "Mini Virus", rarity = "Common", multiplier = 1.2 },
	{ id = "BacteriaBuddy", displayName = "Bacteria Buddy", rarity = "Common", multiplier = 1.3 },
	{ id = "SporeFly", displayName = "Spore Fly", rarity = "Rare", multiplier = 1.5 },
	{ id = "SlimeMutant", displayName = "Slime Mutant", rarity = "Rare", multiplier = 2.0 },
	{ id = "PoisonVirus", displayName = "Poison Virus", rarity = "Epic", multiplier = 3.0 },
	{ id = "PlasmaWorm", displayName = "Plasma Worm", rarity = "Epic", multiplier = 4.0 },
	{ id = "GlitchVirus", displayName = "Glitch Virus", rarity = "Legendary", multiplier = 8.0 },
	{ id = "NeonHorror", displayName = "Neon Phantom", rarity = "Legendary", multiplier = 6.0 },
	{ id = "MegaMutant", displayName = "Mega Mutant", rarity = "Mythic", multiplier = 15.0 },
}

function PetConfig.getById(id: string): PetDef?
	for _, def in ipairs(PetConfig.Pets) do
		if def.id == id then
			return def :: PetDef
		end
	end
	return nil
end

function PetConfig.getPetsByRarity(rarity: Rarity): { PetDef }
	local result: { PetDef } = {}
	for _, def in ipairs(PetConfig.Pets) do
		if def.rarity == rarity then
			table.insert(result, def :: PetDef)
		end
	end
	return result
end

-- Rolls a random PetDef using rarity weights. Returns nil only if config leer.
function PetConfig.rollRandomPet(rng: Random?): PetDef?
	rng = rng or Random.new()
	local totalWeight = 0
	for _, w in pairs(PetConfig.RarityWeights) do
		totalWeight += w
	end
	if totalWeight <= 0 then
		return nil
	end
	local roll = (rng :: Random):NextNumber(0, totalWeight)
	local chosenRarity: Rarity? = nil
	local acc = 0
	for rarity, w in pairs(PetConfig.RarityWeights) do
		acc += w
		if roll <= acc then
			chosenRarity = rarity :: Rarity
			break
		end
	end
	if not chosenRarity then
		return nil
	end
	local candidates = PetConfig.getPetsByRarity(chosenRarity :: Rarity)
	if #candidates == 0 then
		return nil
	end
	local idx = (rng :: Random):NextInteger(1, #candidates)
	return candidates[idx]
end

return PetConfig
