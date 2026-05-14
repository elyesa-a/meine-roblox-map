--!strict
-- Stufen-System: Kosten der naechsten Stufe basierend auf aktuellem Level.

local LevelConfig = {}

function LevelConfig.getCost(level: number): number
	return math.floor(100 * level ^ 1.6)
end

return LevelConfig
