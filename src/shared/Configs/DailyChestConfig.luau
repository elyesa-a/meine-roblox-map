--!strict
-- Daily Chest: 7-Tage-Streak mit steigenden Belohnungen.
-- streakDay = 1..7, danach loopt es zurueck zu 1.
-- Wenn der Spieler einen Tag verpasst (> 48h), faellt der Streak zurueck.

export type ChestReward = {
	streakDay: number,
	dna: number,
	power: number,
	rebirths: number?,
	-- Optional: short display-only bonus text.
	bonusText: string?,
}

local DailyChestConfig = {}

DailyChestConfig.CooldownSec = 24 * 60 * 60 -- 24h
DailyChestConfig.ResetAfterSec = 48 * 60 * 60 -- > 48h ohne Claim = Streak zurueck

DailyChestConfig.Rewards = {
	{ streakDay = 1, dna = 25, power = 100 },
	{ streakDay = 2, dna = 5_000, power = 25_000 },
	{ streakDay = 3, dna = 10_000, power = 60_000 },
	{ streakDay = 4, dna = 20_000, power = 150_000 },
	{ streakDay = 5, dna = 40_000, power = 350_000 },
	{ streakDay = 6, dna = 80_000, power = 800_000 },
	{ streakDay = 7, dna = 200_000, power = 2_500_000, rebirths = 1_000, bonusText = "+1K Rebirths" },
} :: { ChestReward }

function DailyChestConfig.getReward(streakDay: number): ChestReward
	local idx = ((streakDay - 1) % #DailyChestConfig.Rewards) + 1
	return DailyChestConfig.Rewards[idx]
end

return DailyChestConfig
