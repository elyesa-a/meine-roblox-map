--!strict
-- Upgrades: dauerhafte Steigerungen, gekauft mit DNA-Coins.

export type UpgradeDef = {
	id: string,
	displayName: string,
	description: string?,
	iconText: string?,
	bonusText: string?,
	statType: string?,
	-- Pro Level wird der Effekt um perLevelDelta erhoeht (additiv).
	-- Level 0 = 1x, Level 1 = 1+delta, ...
	perLevelDelta: number,
	maxLevel: number?,
	costs: { number }?,
	color: Color3,
}

local UpgradeConfig = {}

UpgradeConfig.MaxLevel = 50

UpgradeConfig.Upgrades = {
	{
		id = "Health",
		displayName = "Health",
		description = "Increase your max HP",
		iconText = "HP",
		bonusText = "+100 HP per level",
		statType = "Health",
		perLevelDelta = 0,
		maxLevel = 5,
		costs = { 500, 1000, 2000, 5000, 10000 },
		color = Color3.fromRGB(90, 210, 140),
	},
	{
		id = "PowerBoost",
		displayName = "More Power",
		description = "Increase Power gains",
		iconText = "PWR",
		perLevelDelta = 0.1,
		color = Color3.fromRGB(255, 90, 90),
	},
	{
		id = "DnaBoost",
		displayName = "More DNA",
		description = "Increase DNA rewards",
		iconText = "DNA",
		perLevelDelta = 0.1,
		color = Color3.fromRGB(80, 160, 255),
	},
	{
		id = "LuckBoost",
		displayName = "More Luck",
		description = "Increase luck rewards",
		iconText = "LCK",
		perLevelDelta = 0.15,
		color = Color3.fromRGB(255, 215, 60),
	},
	{
		id = "TrainingSpeed",
		displayName = "Faster Training",
		description = "Train faster",
		iconText = "TRN",
		perLevelDelta = 0.1,
		color = Color3.fromRGB(80, 220, 130),
	},
	{
		id = "SpeedBoost",
		displayName = "Speed",
		description = "Increase walk speed",
		iconText = "SPD",
		perLevelDelta = 0.5,
		maxLevel = 4,
		costs = { 600, 2000, 12000, 30000 },
		color = Color3.fromRGB(90, 245, 210),
	},
}

function UpgradeConfig.getById(id: string): UpgradeDef?
	for _, def in ipairs(UpgradeConfig.Upgrades) do
		if def.id == id then
			return def :: UpgradeDef
		end
	end
	return nil
end

-- Kosten fuer den naechsten Level (bei aktuellem Level `level`, also Level+1).
function UpgradeConfig.getCost(level: number, def: UpgradeDef?): number
	if def and def.costs then
		local customCost = def.costs[level + 1]
		if customCost then
			return customCost
		end
	end
	return math.floor(200 * (level + 1) ^ 1.8)
end

function UpgradeConfig.getMaxLevel(def: UpgradeDef?): number
	return if def and def.maxLevel then def.maxLevel else UpgradeConfig.MaxLevel
end

function UpgradeConfig.getMultiplier(level: number, perLevelDelta: number): number
	return 1 + level * perLevelDelta
end

return UpgradeConfig
