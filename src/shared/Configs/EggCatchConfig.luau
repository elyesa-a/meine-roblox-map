--!strict
-- EggCatchConfig: 3 Egg-Catch-Systeme pro Area (Common / Rare / Epic).
--
-- Kosten skalieren pro Area *4 (Vorgabe):
--   Area 1: Common 100  / Rare 500   / Epic 2.500
--   Area 2: Common 400  / Rare 2.000 / Epic 10.000
--   Area 3: Common 1.600/ Rare 8.000 / Epic 40.000  ...
--
-- HINWEIS: Das bestehende Pet-Egg-System (PetService.openEgg) nutzt einen
-- einzelnen globalen EggCost. Diese Tabelle liefert die Map-/Anzeige-Daten
-- (Seltenheit, Kosten, Farbe). Die Stationen werden ueber EggCatchService an
-- PetService.openEgg gekoppelt, damit sie echte Funktion haben -- die hier
-- gelisteten Kosten sind Anzeige-/Datenwerte (Platzhalter-Oekonomie).

export type EggTier = "Common" | "Rare" | "Epic"

export type EggStationDef = {
	tier: EggTier,
	cost: number,
	color: Color3,
}

local EggCatchConfig = {}

EggCatchConfig.TierColor = {
	Common = Color3.fromRGB(150, 220, 255),
	Rare = Color3.fromRGB(170, 120, 255),
	Epic = Color3.fromRGB(255, 170, 70),
}

local BASE = {
	{ tier = "Common", base = 100 },
	{ tier = "Rare", base = 500 },
	{ tier = "Epic", base = 2500 },
}

-- EggCatchConfig.ForArea[areaIndex] = { EggStationDef, EggStationDef, EggStationDef }
EggCatchConfig.ForArea = {} :: { [number]: { EggStationDef } }

for areaIndex = 1, 10 do
	local factor = 4 ^ (areaIndex - 1)
	local stations: { EggStationDef } = {}
	for _, entry in ipairs(BASE) do
		table.insert(stations, {
			tier = entry.tier :: EggTier,
			cost = entry.base * factor,
			color = EggCatchConfig.TierColor[entry.tier],
		})
	end
	EggCatchConfig.ForArea[areaIndex] = stations
end

function EggCatchConfig.getForArea(areaIndex: number): { EggStationDef }
	return EggCatchConfig.ForArea[areaIndex] or {}
end

return EggCatchConfig
