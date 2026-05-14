--!strict
-- Rebirth balancing: 0 bis 100, +0.5x Multiplikator pro Rebirth.

local RebirthConfig = {}

RebirthConfig.MaxRebirth = 100
RebirthConfig.MultiplierPerRebirth = 0.5

function RebirthConfig.getMultiplier(rebirth: number): number
	return 1 + rebirth * RebirthConfig.MultiplierPerRebirth
end

-- Kosten fuer den naechsten Rebirth-Schritt, d.h. wenn der Spieler aktuell
-- Rebirth `r` hat, gibt diese Funktion die Kraft zurueck, die er fuer den
-- Aufstieg auf `r + 1` braucht.
function RebirthConfig.getCost(currentRebirth: number): number
	return math.floor(1000 * (currentRebirth + 1) ^ 2.15)
end

function RebirthConfig.getDnaReward(currentRebirth: number): number
	return 25 + currentRebirth * 10
end

return RebirthConfig
