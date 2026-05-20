--!strict
-- PetConfig: area-based hatch eggs, rarity chances, and Power multipliers.
--
-- Existing saved pets use instance IDs in DataService. Pet IDs remain stable
-- and old pet definitions stay present so older profiles keep rendering.

local AreaConfig = require(script.Parent:WaitForChild("AreaConfig"))

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"
export type EggTier = "Common" | "Rare" | "Epic"

export type PetDef = {
	id: string,
	displayName: string,
	rarity: Rarity,
	powerMultiplier: number,
	multiplier: number,
	areaIndex: number?,
	eggTier: EggTier?,
}

export type EggDef = {
	id: string,
	displayName: string,
	areaIndex: number,
	areaId: string,
	areaDisplayName: string,
	tier: EggTier,
	cost: number,
	requiredPower: number,
	requiredRebirth: number,
	color: Color3,
	pool: { [Rarity]: { string } },
}

local PetConfig = {}

PetConfig.MaxInventorySize = 100
PetConfig.MaxEquipped = 3
PetConfig.EggCooldownSec = 2

-- Compatibility fallback for the old spawn egg click.
PetConfig.DefaultEggId = "Area1CommonEgg"
PetConfig.EggCost = 100

PetConfig.RarityOrder = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythic = 6,
} :: { [string]: number }

PetConfig.RarityColor = {
	Common = Color3.fromRGB(235, 238, 240),
	Uncommon = Color3.fromRGB(90, 220, 125),
	Rare = Color3.fromRGB(70, 155, 255),
	Epic = Color3.fromRGB(175, 90, 255),
	Legendary = Color3.fromRGB(255, 172, 45),
	Mythic = Color3.fromRGB(255, 70, 125),
} :: { [string]: Color3 }

PetConfig.EggTierOrder = {
	Common = PetConfig.RarityOrder.Common,
	Rare = PetConfig.RarityOrder.Rare,
	Epic = PetConfig.RarityOrder.Epic,
} :: { [string]: number }

-- Base V1 hatch chances. The server uses this table for weighted rolls.
PetConfig.RarityChances = {
	{ rarity = "Common" :: Rarity, chance = 55 },
	{ rarity = "Uncommon" :: Rarity, chance = 25 },
	{ rarity = "Rare" :: Rarity, chance = 13 },
	{ rarity = "Epic" :: Rarity, chance = 5 },
	{ rarity = "Legendary" :: Rarity, chance = 1.5 },
	{ rarity = "Mythic" :: Rarity, chance = 0.5 },
}

PetConfig.RarityWeights = {} :: { [Rarity]: number }
for _, entry in ipairs(PetConfig.RarityChances) do
	PetConfig.RarityWeights[entry.rarity] = entry.chance
end

local tierData = {
	Common = { cost = 100, bonus = 0, label = "Starter" },
	Rare = { cost = 500, bonus = 0.08, label = "Mutated" },
	Epic = { cost = 2500, bonus = 0.18, label = "Elite" },
} :: { [EggTier]: { cost: number, bonus: number, label: string } }

local tierOrder = { "Common" :: EggTier, "Rare" :: EggTier, "Epic" :: EggTier }

local rarityBonus = {
	Common = 0.08,
	Uncommon = 0.14,
	Rare = 0.24,
	Epic = 0.38,
	Legendary = 0.65,
	Mythic = 1.0,
} :: { [Rarity]: number }

-- Rarity-Suffixe: virus-/lab-thematisch und progressiv staerker.
-- Saved-Daten referenzieren PET-IDs, NICHT displayName -> Aenderungen hier
-- sind safe.
local rarityName = {
	Common = "Microbe",
	Uncommon = "Spore",
	Rare = "Strain",
	Epic = "Mutant",
	Legendary = "Apex",
	Mythic = "Overmind",
} :: { [Rarity]: string }

local areaPetRoots = {
	[1] = "Bacteria",
	[2] = "Cell",
	[3] = "Gene",
	[4] = "Toxic",
	[5] = "Virus",
	[6] = "Glitch",
	[7] = "Biohazard",
	[8] = "Shadow",
	[9] = "Omega",
	[10] = "Containment",
}

local tierColor = {
	Common = PetConfig.RarityColor.Common,
	Rare = PetConfig.RarityColor.Rare,
	Epic = PetConfig.RarityColor.Epic,
} :: { [EggTier]: Color3 }

local function round2(n: number): number
	return math.floor(n * 100 + 0.5) / 100
end

local function petId(areaIndex: number, tier: EggTier, rarity: Rarity): string
	return string.format("A%d%s%sPet", areaIndex, tier, rarity)
end

function PetConfig.getEggId(areaIndex: number, tier: string?): string
	local safeTier = if tier == "Rare" or tier == "Epic" then tier else "Common"
	return string.format("Area%d%sEgg", areaIndex, safeTier)
end

PetConfig.Pets = {} :: { PetDef }
PetConfig.Eggs = {} :: { EggDef }

local function addPet(def: PetDef)
	table.insert(PetConfig.Pets, def)
end

local function addEgg(def: EggDef)
	table.insert(PetConfig.Eggs, def)
end

for _, area in ipairs(AreaConfig.Areas) do
	local areaIndex = area.index
	local areaRoot = areaPetRoots[areaIndex] or ("Area" .. tostring(areaIndex))
	local areaBonus = (areaIndex - 1) * 0.06

	for _, tier in ipairs(tierOrder) do
		local tierInfo = tierData[tier]
		local pool = {} :: { [Rarity]: { string } }

		for _, chanceDef in ipairs(PetConfig.RarityChances) do
			local rarity = chanceDef.rarity
			local id = petId(areaIndex, tier, rarity)
			local powerMultiplier = round2(1 + rarityBonus[rarity] + areaBonus + tierInfo.bonus)
			local displayName = string.format("%s %s %s", tierInfo.label, areaRoot, rarityName[rarity])
			addPet({
				id = id,
				displayName = displayName,
				rarity = rarity,
				powerMultiplier = powerMultiplier,
				multiplier = powerMultiplier,
				areaIndex = areaIndex,
				eggTier = tier,
			})
			pool[rarity] = { id }
		end

		local factor = 4 ^ (areaIndex - 1)
		addEgg({
			id = PetConfig.getEggId(areaIndex, tier),
			displayName = string.format("%s %s Egg", area.displayName, tierInfo.label),
			areaIndex = areaIndex,
			areaId = area.id,
			areaDisplayName = area.displayName,
			tier = tier,
			cost = tierInfo.cost * factor,
			requiredPower = area.requiredPower,
			requiredRebirth = area.trainingRebirth,
			color = tierColor[tier],
			pool = pool,
		})
	end
end

-- Legacy IDs from the previous single-egg system. Kept for old saved profiles.
local legacyPets = {
	{ id = "MiniVirus", displayName = "Mini Virus", rarity = "Common" :: Rarity, powerMultiplier = 1.2 },
	{ id = "BacteriaBuddy", displayName = "Bacteria Buddy", rarity = "Common" :: Rarity, powerMultiplier = 1.3 },
	{ id = "SporeFly", displayName = "Spore Fly", rarity = "Rare" :: Rarity, powerMultiplier = 1.5 },
	{ id = "SlimeMutant", displayName = "Slime Mutant", rarity = "Rare" :: Rarity, powerMultiplier = 2.0 },
	{ id = "PoisonVirus", displayName = "Poison Virus", rarity = "Epic" :: Rarity, powerMultiplier = 3.0 },
	{ id = "PlasmaWorm", displayName = "Plasma Worm", rarity = "Epic" :: Rarity, powerMultiplier = 4.0 },
	{ id = "GlitchVirus", displayName = "Glitch Virus", rarity = "Legendary" :: Rarity, powerMultiplier = 8.0 },
	{ id = "FrostCell", displayName = "Frost Cell", rarity = "Legendary" :: Rarity, powerMultiplier = 6.0 },
	{ id = "MagmaCell", displayName = "Magma Cell", rarity = "Legendary" :: Rarity, powerMultiplier = 7.0 },
	{ id = "MegaMutant", displayName = "Mega Mutant", rarity = "Mythic" :: Rarity, powerMultiplier = 15.0 },
	{ id = "DnaDragon", displayName = "DNA Dragon", rarity = "Mythic" :: Rarity, powerMultiplier = 18.0 },
}

for _, def in ipairs(legacyPets) do
	addPet({
		id = def.id,
		displayName = def.displayName,
		rarity = def.rarity,
		powerMultiplier = def.powerMultiplier,
		multiplier = def.powerMultiplier,
	})
end

local petsById: { [string]: PetDef } = {}
local eggsById: { [string]: EggDef } = {}

for _, def in ipairs(PetConfig.Pets) do
	petsById[def.id] = def
end

for _, def in ipairs(PetConfig.Eggs) do
	eggsById[def.id] = def
end

function PetConfig.getById(id: string): PetDef?
	return petsById[id]
end

function PetConfig.getEggById(id: string): EggDef?
	return eggsById[id]
end

function PetConfig.getEggSortOrder(egg: EggDef): number
	return egg.areaIndex * 100 + (PetConfig.EggTierOrder[egg.tier] or 50)
end

function PetConfig.getSortedEggs(): { EggDef }
	local eggs = table.clone(PetConfig.Eggs)
	table.sort(eggs, function(a, b)
		local aOrder = PetConfig.getEggSortOrder(a)
		local bOrder = PetConfig.getEggSortOrder(b)
		if aOrder ~= bOrder then
			return aOrder < bOrder
		end
		return a.id < b.id
	end)
	return eggs
end

function PetConfig.getPetsByRarity(rarity: Rarity): { PetDef }
	local result: { PetDef } = {}
	for _, def in ipairs(PetConfig.Pets) do
		if def.rarity == rarity then
			table.insert(result, def)
		end
	end
	return result
end

local function rollRarity(rng: Random): Rarity?
	local totalWeight = 0
	for _, entry in ipairs(PetConfig.RarityChances) do
		totalWeight += entry.chance
	end
	if totalWeight <= 0 then
		return nil
	end

	local roll = rng:NextNumber(0, totalWeight)
	local acc = 0
	for _, entry in ipairs(PetConfig.RarityChances) do
		acc += entry.chance
		if roll <= acc then
			return entry.rarity
		end
	end
	return PetConfig.RarityChances[1].rarity
end

local function rollOnceFromEgg(egg: EggDef, rng: Random): PetDef?
	local rarity = rollRarity(rng)
	if not rarity then
		return nil
	end
	local pool = egg.pool[rarity]
	if not pool or #pool == 0 then
		return nil
	end
	local chosenId = pool[rng:NextInteger(1, #pool)]
	return PetConfig.getById(chosenId)
end

function PetConfig.rollRandomPetForEgg(eggId: string, rng: Random?, luckMultiplier: number?): PetDef?
	local egg = PetConfig.getEggById(eggId)
	if not egg then
		return nil
	end
	local rollRng = rng or Random.new()
	local best = rollOnceFromEgg(egg, rollRng)
	local extraRolls = math.clamp(math.floor((luckMultiplier or 1) - 1), 0, 5)

	for _ = 1, extraRolls do
		local candidate = rollOnceFromEgg(egg, rollRng)
		if candidate and best
			and (PetConfig.RarityOrder[candidate.rarity] or 0) > (PetConfig.RarityOrder[best.rarity] or 0) then
			best = candidate
		elseif candidate and not best then
			best = candidate
		end
	end

	return best
end

-- Compatibility helper used by older call sites.
function PetConfig.rollRandomPet(rng: Random?): PetDef?
	return PetConfig.rollRandomPetForEgg(PetConfig.DefaultEggId, rng, 1)
end

return PetConfig
