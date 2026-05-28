--!strict
-- PetConfig: one stage egg per area, rarity chances, and Power multipliers.
--
-- Saved pets reference pet IDs. New hatch pools use one pet per rarity per
-- stage egg. The old generated pet IDs and older handcrafted IDs remain as
-- legacy definitions so existing inventories still render and equip.

local AreaConfig = require(script.Parent:WaitForChild("AreaConfig"))
local EnemyConfig = require(script.Parent:WaitForChild("EnemyConfig"))

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"
export type EggTier = "Stage" | "Common" | "Rare" | "Epic"

export type PetDef = {
	id: string,
	displayName: string,
	rarity: Rarity,
	powerMultiplier: number,
	multiplier: number,
	areaIndex: number?,
	eggTier: EggTier?,
	legacy: boolean?,
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
	requiredBossDefeated: number,
	color: Color3,
	pool: { [Rarity]: { string } },
}

local PetConfig = {}

PetConfig.MaxInventorySize = 100
PetConfig.MaxEquipped = 3
PetConfig.EggCooldownSec = 2

-- Compatibility fallback for older call sites. This now points at the single
-- Stage 1 egg instead of the old Common/Rare/Epic split.
PetConfig.DefaultEggId = "Area1Egg"
PetConfig.EggCost = 1000

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
	Stage = 1,
	Common = 100,
	Rare = 200,
	Epic = 300,
} :: { [string]: number }

-- Server-side weighted rarity chances used by all stage eggs.
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

-- Stage 1 baseline required by design.
PetConfig.StageOnePowerMultipliers = {
	Common = 1.5,
	Uncommon = 1.75,
	Rare = 2.0,
	Epic = 2.5,
	Legendary = 2.75,
	Mythic = 3.0,
} :: { [Rarity]: number }

local function roundToCleanEggPrice(value: number): number
	if value <= 0 then
		return 0
	end

	local scale = 1
	while value / scale >= 10 do
		scale *= 10
	end

	local scaled = value / scale
	local roundedHalfStep = math.floor(scaled * 2 + 0.5) / 2
	return math.max(1, math.floor(roundedHalfStep * scale + 0.5))
end

local function getBossDnaReward(areaIndex: number): number?
	for _, enemy in ipairs(EnemyConfig.Enemies) do
		if enemy.AreaIndex == areaIndex and enemy.IsBoss then
			return enemy.DNAReward
		end
	end
	return nil
end

local function buildStageEggCosts(): { [number]: number }
	local costs = {} :: { [number]: number }
	for _, area in ipairs(AreaConfig.Areas) do
		local bossReward = getBossDnaReward(area.index)
		local fallback = 1000 * (5 ^ (area.index - 1))
		costs[area.index] = roundToCleanEggPrice(bossReward or fallback)
	end
	return costs
end

-- Stage-Egg Preise orientieren sich am Boss-DNA-Reward der jeweiligen Area,
-- aber werden auf saubere Simulator-Zahlen gerundet:
-- z.B. 1.1K -> 1K, 1.4K -> 1.5K, 1.9K -> 2K.
PetConfig.StageEggCosts = buildStageEggCosts()

local stageEggNames = {
	[1] = "Beginner Virus Egg",
	[2] = "Infected Cell Egg",
	[3] = "Mutation Strain Egg",
	[4] = "Toxic Sample Egg",
	[5] = "Virus Chamber Egg",
	[6] = "Corrupted Specimen Egg",
	[7] = "Biohazard Core Egg",
	[8] = "Dark Mutation Egg",
	[9] = "Omega Virus Egg",
	[10] = "Final Containment Egg",
}

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

local function round2(n: number): number
	return math.floor(n * 100 + 0.5) / 100
end

local function stagePetId(areaIndex: number, rarity: Rarity): string
	return string.format("A%d%sPet", areaIndex, rarity)
end

function PetConfig.getEggId(areaIndex: number, _tier: string?): string
	return string.format("Area%dEgg", areaIndex)
end

function PetConfig.getStagePowerMultiplier(areaIndex: number, rarity: Rarity): number
	local baseline = PetConfig.StageOnePowerMultipliers[rarity] or 1
	if areaIndex <= 1 then
		return baseline
	end

	-- Later stages grow both by rarity value and by a moderate flat stage bonus.
	-- This makes every new area egg feel better without exploding the additive
	-- equipped-pet stack.
	local stageOffset = math.max(0, areaIndex - 1)
	local rarityScale = 1 + stageOffset * 0.28
	local stageBonus = stageOffset * 0.35
	return round2(1 + (baseline - 1) * rarityScale + stageBonus)
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
	local pool = {} :: { [Rarity]: { string } }

	for _, chanceDef in ipairs(PetConfig.RarityChances) do
		local rarity = chanceDef.rarity
		local id = stagePetId(areaIndex, rarity)
		local powerMultiplier = PetConfig.getStagePowerMultiplier(areaIndex, rarity)
		addPet({
			id = id,
			displayName = string.format("%s %s", areaRoot, rarityName[rarity]),
			rarity = rarity,
			powerMultiplier = powerMultiplier,
			multiplier = powerMultiplier,
			areaIndex = areaIndex,
			eggTier = "Stage",
		})
		pool[rarity] = { id }
	end

	addEgg({
		id = PetConfig.getEggId(areaIndex),
		displayName = stageEggNames[areaIndex] or (area.displayName .. " Egg"),
		areaIndex = areaIndex,
		areaId = area.id,
		areaDisplayName = area.displayName,
		tier = "Stage",
		cost = PetConfig.StageEggCosts[areaIndex] or math.floor(1000 * (5 ^ (areaIndex - 1))),
		requiredPower = area.requiredPower,
		requiredRebirth = area.trainingRebirth,
		requiredBossDefeated = math.max(0, areaIndex - 1),
		color = area.primaryColor,
		pool = pool,
	})
end

-- Legacy generated pet IDs from the old Common/Rare/Epic egg split. These are
-- intentionally not part of any new hatch pool.
local legacyTierData = {
	Common = { bonus = 0, label = "Starter" },
	Rare = { bonus = 0.08, label = "Mutated" },
	Epic = { bonus = 0.18, label = "Elite" },
} :: { [EggTier]: { bonus: number, label: string } }

local legacyTierOrder = { "Common" :: EggTier, "Rare" :: EggTier, "Epic" :: EggTier }

local legacyRarityBonus = {
	Common = 0.08,
	Uncommon = 0.14,
	Rare = 0.24,
	Epic = 0.38,
	Legendary = 0.65,
	Mythic = 1.0,
} :: { [Rarity]: number }

local function legacyPetId(areaIndex: number, tier: EggTier, rarity: Rarity): string
	return string.format("A%d%s%sPet", areaIndex, tier, rarity)
end

for _, area in ipairs(AreaConfig.Areas) do
	local areaIndex = area.index
	local areaRoot = areaPetRoots[areaIndex] or ("Area" .. tostring(areaIndex))
	local areaBonus = (areaIndex - 1) * 0.06

	for _, tier in ipairs(legacyTierOrder) do
		local tierInfo = legacyTierData[tier]
		if not tierInfo then
			continue
		end
		for _, chanceDef in ipairs(PetConfig.RarityChances) do
			local rarity = chanceDef.rarity
			local powerMultiplier = round2(1 + legacyRarityBonus[rarity] + areaBonus + tierInfo.bonus)
			addPet({
				id = legacyPetId(areaIndex, tier, rarity),
				displayName = string.format("%s %s %s", tierInfo.label, areaRoot, rarityName[rarity]),
				rarity = rarity,
				powerMultiplier = powerMultiplier,
				multiplier = powerMultiplier,
				areaIndex = areaIndex,
				eggTier = tier,
				legacy = true,
			})
		end
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
		legacy = true,
	})
end

PetConfig.LegacyEggIdMap = {} :: { [string]: string }
for _, area in ipairs(AreaConfig.Areas) do
	for _, tier in ipairs(legacyTierOrder) do
		PetConfig.LegacyEggIdMap[string.format("Area%d%sEgg", area.index, tier)] = PetConfig.getEggId(area.index)
	end
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
	local egg = eggsById[id]
	if egg then
		return egg
	end
	local mappedId = PetConfig.LegacyEggIdMap[id]
	if mappedId then
		return eggsById[mappedId]
	end
	return nil
end

function PetConfig.getEggSortOrder(egg: EggDef): number
	return egg.areaIndex * 100 + (PetConfig.EggTierOrder[egg.tier] or 1)
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
