--!strict
-- Daily quest definitions. The service selects one easy, medium, and hard
-- quest each day from this list.

export type QuestDef = {
	id: string,
	displayName: string,
	description: string,
	kind: string,
	target: string?,
	required: number,
	reward: { Dna: number?, Power: number?, Luck: number?, QuestTokens: number? },
	difficulty: string,
}

local DailyQuestConfig = {}

DailyQuestConfig.ResetSec = 24 * 60 * 60
DailyQuestConfig.QuestsPerDay = 3

DailyQuestConfig.Quests = {
	{ id = "CollectDnaEasy", displayName = "Collect DNA", description = "Collect 1,000 DNA", kind = "CollectDna", required = 1000, reward = { Dna = 250 }, difficulty = "Easy" },
	{ id = "TrainEasy", displayName = "Train Power", description = "Train 100 times", kind = "Train", required = 100, reward = { Power = 500 }, difficulty = "Easy" },
	{ id = "SpinWheel", displayName = "Lucky Spin", description = "Spin the Lucky Wheel 1 time", kind = "Spin", required = 1, reward = { Luck = 25 }, difficulty = "Easy" },

	{ id = "DefeatBacteria", displayName = "Clean Lab Entry", description = "Defeat 5 beginner enemies", kind = "DefeatEnemy", target = "StartEnemies", required = 5, reward = { Dna = 600 }, difficulty = "Medium" },
	{ id = "DefeatMutants", displayName = "Stop Mutations", description = "Defeat 8 mutation enemies", kind = "DefeatEnemy", target = "MutationEnemies", required = 8, reward = { Dna = 1500 }, difficulty = "Medium" },
	{ id = "ReachPower", displayName = "Power Sample", description = "Reach 25K Power", kind = "ReachPower", required = 25000, reward = { Power = 2500 }, difficulty = "Medium" },
	{ id = "EquipAura", displayName = "Aura Test", description = "Equip any Aura", kind = "EquipAura", required = 1, reward = { Luck = 50 }, difficulty = "Medium" },

	{ id = "DefeatBoss", displayName = "Boss Research", description = "Defeat 1 Boss", kind = "DefeatBoss", required = 1, reward = { Dna = 2500, QuestTokens = 1 }, difficulty = "Hard" },
	{ id = "PerformRebirth", displayName = "Evolution Trial", description = "Perform 1 Rebirth", kind = "Rebirth", required = 1, reward = { Dna = 4000, QuestTokens = 1 }, difficulty = "Hard" },
	{ id = "ReachToxic", displayName = "Toxic Access", description = "Reach Toxic Facility", kind = "ReachZone", target = "QuarantineZone", required = 1, reward = { Dna = 3000 }, difficulty = "Hard" },
	{ id = "PlayTime", displayName = "Lab Shift", description = "Play for 10 minutes", kind = "PlayMinutes", required = 10, reward = { Dna = 1500, Power = 1500 }, difficulty = "Hard" },
}

local byId: { [string]: QuestDef } = {}
local byDifficulty: { [string]: { QuestDef } } = {}

for _, quest in ipairs(DailyQuestConfig.Quests) do
	byId[quest.id] = quest
	if not byDifficulty[quest.difficulty] then
		byDifficulty[quest.difficulty] = {}
	end
	table.insert(byDifficulty[quest.difficulty], quest)
end

function DailyQuestConfig.getById(id: string): QuestDef?
	return byId[id]
end

function DailyQuestConfig.getByDifficulty(difficulty: string): { QuestDef }
	return byDifficulty[difficulty] or {}
end

return DailyQuestConfig
