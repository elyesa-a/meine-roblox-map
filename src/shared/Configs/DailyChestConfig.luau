--!strict
-- Daily Chest: 7-Tage-Streak mit steigenden Belohnungen.
-- streakDay = 1..7, danach loopt es zurueck zu 1.
-- Wenn der Spieler einen Tag verpasst (> 48h), faellt der Streak zurueck.

export type ChestReward = {
	streakDay: number,
	dna: number,
	power: number,
	-- Optional: bonus Spin oder Pet etc.
	bonusText: string?,
}

local DailyChestConfig = {}

DailyChestConfig.CooldownSec = 24 * 60 * 60 -- 24h
DailyChestConfig.ResetAfterSec = 48 * 60 * 60 -- > 48h ohne Claim = Streak zurueck

DailyChestConfig.Rewards = {
	{ streakDay = 1, dna = 25, power = 100 },
	{ streakDay = 2, dna = 50, power = 250 },
	{ streakDay = 3, dna = 100, power = 600 },
	{ streakDay = 4, dna = 200, power = 1500 },
	{ streakDay = 5, dna = 400, power = 3500 },
	{ streakDay = 6, dna = 800, power = 8000 },
	{ streakDay = 7, dna = 2000, power = 25000, bonusText = "+1 Pet" },
} :: { ChestReward }

function DailyChestConfig.getReward(streakDay: number): ChestReward
	local idx = ((streakDay - 1) % #DailyChestConfig.Rewards) + 1
	return DailyChestConfig.Rewards[idx]
end

return DailyChestConfig
