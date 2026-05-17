--!strict
-- Walkable map collectibles for DNA, Power, Luck boosts, and rare Rebirth shards.

export type CollectibleDef = {
	id: string,
	displayName: string,
	kind: string,
	amount: number,
	weight: number,
	color: Color3,
	size: number,
	respawnSec: number,
}

local CollectibleConfig = {}

CollectibleConfig.RebirthShardsPerRebirth = 10
CollectibleConfig.MaxActivePerZone = 4
CollectibleConfig.SpawnIntervalSec = 6

-- Schluessel = neue Zonen-Ids (1 Zone pro Area, siehe ZoneConfig/AreaConfig).
-- Zone 1 behaelt die Id "StartZone".
CollectibleConfig.ZoneMultiplier = {
	StartZone = 1,
	Area2 = 2,
	Area3 = 4,
	Area4 = 7,
	Area5 = 12,
	Area6 = 18,
	Area7 = 26,
	Area8 = 40,
	Area9 = 65,
	Area10 = 100,
}

CollectibleConfig.Collectibles = {
	{ id = "SmallDnaOrb", displayName = "DNA Orb", kind = "Dna", amount = 40, weight = 42, color = Color3.fromRGB(100, 255, 210), size = 3.2, respawnSec = 14 },
	{ id = "LargeDnaOrb", displayName = "Large DNA Orb", kind = "Dna", amount = 140, weight = 18, color = Color3.fromRGB(75, 225, 255), size = 4.4, respawnSec = 18 },
	{ id = "PowerCrystal", displayName = "Power Crystal", kind = "Power", amount = 85, weight = 28, color = Color3.fromRGB(255, 220, 85), size = 3.8, respawnSec = 16 },
	{ id = "LuckOrb", displayName = "Luck Orb", kind = "Luck", amount = 60, weight = 9, color = Color3.fromRGB(255, 110, 235), size = 3.6, respawnSec = 24 },
	{ id = "RebirthShard", displayName = "Rebirth Shard", kind = "RebirthShard", amount = 1, weight = 1.2, color = Color3.fromRGB(255, 90, 90), size = 4.8, respawnSec = 42 },
}

function CollectibleConfig.getZoneMultiplier(zoneId: string): number
	return CollectibleConfig.ZoneMultiplier[zoneId] or 1
end

function CollectibleConfig.roll(rng: Random): CollectibleDef
	local total = 0
	for _, def in ipairs(CollectibleConfig.Collectibles) do
		total += def.weight
	end
	local roll = rng:NextNumber(0, total)
	local acc = 0
	for _, def in ipairs(CollectibleConfig.Collectibles) do
		acc += def.weight
		if roll <= acc then
			return def
		end
	end
	return CollectibleConfig.Collectibles[1]
end

return CollectibleConfig
