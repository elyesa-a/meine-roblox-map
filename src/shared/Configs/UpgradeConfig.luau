--!strict
-- Upgrades: dauerhafte Steigerungen, gekauft mit DNA-Coins.

export type UpgradeDef = {
	id: string,
	displayName: string,
	-- Pro Level wird der Effekt um perLevelDelta erhoeht (additiv).
	-- Level 0 = 1x, Level 1 = 1+delta, ...
	perLevelDelta: number,
	color: Color3,
}

local UpgradeConfig = {}

UpgradeConfig.MaxLevel = 50

UpgradeConfig.Upgrades = {
	{ id = "PowerBoost", displayName = "More Power", perLevelDelta = 0.1, color = Color3.fromRGB(255, 90, 90) },
	{ id = "DnaBoost", displayName = "More DNA", perLevelDelta = 0.1, color = Color3.fromRGB(80, 160, 255) },
	{ id = "LuckBoost", displayName = "More Luck", perLevelDelta = 0.15, color = Color3.fromRGB(255, 215, 60) },
	{ id = "TrainingSpeed", displayName = "Faster Training", perLevelDelta = 0.1, color = Color3.fromRGB(80, 220, 130) },
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
function UpgradeConfig.getCost(level: number): number
	return math.floor(100 * (level + 1) ^ 1.8)
end

function UpgradeConfig.getMultiplier(level: number, perLevelDelta: number): number
	return 1 + level * perLevelDelta
end

return UpgradeConfig
