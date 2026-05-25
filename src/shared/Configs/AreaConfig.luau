--!strict
-- AreaConfig: zentrale Daten-Tabelle fuer das Virus-Labor.
--
-- 10 Areale, linear entlang +X angeordnet. Jede Area hat:
--  * Identitaet (id, displayName, bossName)
--  * Akzentfarben (primary + secondary)
--  * Training-Rebirth-Anforderung (Trainingsbereich der Area)
--  * Layout-Position (Mittelpunkt der Gegner-Halle in der Welt)
--
-- Power/PWR-Anforderungen der Area-Gates liegen zentral hier. DNA bleibt
-- reine Kauf-Waehrung fuer Skills, Pets, Boosts, Eggs und Upgrades.

export type AreaDef = {
	index: number,
	id: string,
	displayName: string,
	bossName: string,
	primaryColor: Color3,
	secondaryColor: Color3,
	-- Rebirth-Anforderung fuer den Trainingsbereich dieser Area.
	trainingRebirth: number,
	-- Power-Anforderung fuer das Area-Gate.
	requiredPower: number,
	-- Welt-X der Mitte der Gegner-Halle dieser Area.
	hallCenterX: number,
}

local AreaConfig = {}

-- ----- Layout-Konstanten (eine Quelle der Wahrheit) ------------------------
AreaConfig.Layout = {
	AreaSpan = 520, -- X-Abstand zwischen zwei Area-Mittelpunkten
	FirstHallX = 260, -- X der ersten Gegner-Halle (Area 1)
	EnemySpacing = 32, -- Alt: X-Abstand zwischen zwei Gegnern (Borders/Decals)
	-- Neuer Layout-Vertrag: 4 normale Gegner gleichmaessig im vorderen Teil,
	-- danach eine deutliche Luecke und der Boss in einem eigenen Raum.
	NormalEnemySpacing = 70, -- X-Abstand zwischen zwei normalen Gegnern (1..4)
	BossOffsetX = 110, -- zusaetzliche X-Distanz vom letzten Normalen zum Boss
	EnemiesPerArea = 5,
	FloorZ = 0, -- Z-Mitte des Laufwegs
	FloorHalfZ = 70, -- halbe Korridor-Breite (Laufweg)
	FloorTopY = 0, -- Oberkante des Bodens
	WallHeight = 34,
	TrainingOffsetX = -250, -- relativ zur Hall-Mitte: Trainingsbereich davor
	TrainingGateOffsetX = -320, -- Rebirth-Gate vor dem Trainingsbereich
	GateOffsetX = -170, -- Labor-Luke zwischen Training und erstem Gegner
	EggZ = 96, -- Z der Egg-Catch-Reihe (seitlich, nicht im Weg)
	SpawnCenterX = -180, -- Spawn-Lab liegt hinten/am Anfang
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Reihenfolge & Farben aus dem Teleport-Menue (TeleportFrame.AREA_ACCENTS).
-- Jede Area hat eine klar eigene Akzentfarbe -> Tunnel/Walls/Border/Gate.
local areaData = {
	{ name = "Bacteria Lab", boss = "Bacteria Overlord", rb = 0, p = rgb(0, 210, 190), s = rgb(170, 245, 235) },
	{ name = "Infected Cells", boss = "Cell Breaker", rb = 3, p = rgb(255, 190, 40), s = rgb(255, 225, 165) },
	{ name = "Mutation Sector", boss = "Mutation Brute", rb = 6, p = rgb(80, 255, 120), s = rgb(190, 255, 210) },
	{ name = "Toxic Storage", boss = "Toxic Crusher", rb = 9, p = rgb(255, 150, 55), s = rgb(255, 210, 160) },
	{ name = "Virus Chamber", boss = "Virus Reaper", rb = 12, p = rgb(115, 210, 255), s = rgb(200, 235, 255) },
	{ name = "Corrupted Lab", boss = "Corrupted Beast", rb = 15, p = rgb(170, 255, 70), s = rgb(220, 255, 180) },
	{ name = "Biohazard Core", boss = "Biohazard Titan", rb = 18, p = rgb(120, 220, 145), s = rgb(210, 245, 220) },
	{ name = "Dark Mutation", boss = "Dark Mutation King", rb = 21, p = rgb(180, 90, 220), s = rgb(225, 180, 245) },
	{ name = "Omega Virus Lab", boss = "Omega Virus", rb = 24, p = rgb(255, 220, 80), s = rgb(255, 240, 180) },
	{ name = "Final Containment", boss = "Final DNA Destroyer", rb = 30, p = rgb(255, 70, 75), s = rgb(255, 180, 185) },
}

AreaConfig.ZoneRequirements = {
	SpawnLab = 0,
	BacteriaLab = 0,
	InfectedCells = 160,
	ToxicSlimeLab = 500,
	MutantChamber = 1500,
	DNAInstabilityLab = 5000,
	FrostLab = 15000,
	BiohazardContainment = 50000,
	VirusCoreSector = 150000,
	OverlordMutationLab = 500000,
}

local requiredPowerByAreaIndex = {
	AreaConfig.ZoneRequirements.BacteriaLab,
	AreaConfig.ZoneRequirements.InfectedCells,
	AreaConfig.ZoneRequirements.ToxicSlimeLab,
	AreaConfig.ZoneRequirements.MutantChamber,
	AreaConfig.ZoneRequirements.DNAInstabilityLab,
	AreaConfig.ZoneRequirements.FrostLab,
	AreaConfig.ZoneRequirements.BiohazardContainment,
	AreaConfig.ZoneRequirements.VirusCoreSector,
	AreaConfig.ZoneRequirements.OverlordMutationLab,
	AreaConfig.ZoneRequirements.OverlordMutationLab,
}

AreaConfig.Areas = {} :: { AreaDef }

for i, data in ipairs(areaData) do
	AreaConfig.Areas[i] = {
		index = i,
		id = "Area" .. tostring(i),
		displayName = data.name,
		bossName = data.boss,
		primaryColor = data.p,
		secondaryColor = data.s,
		trainingRebirth = data.rb,
		requiredPower = requiredPowerByAreaIndex[i] or 0,
		hallCenterX = AreaConfig.Layout.FirstHallX + (i - 1) * AreaConfig.Layout.AreaSpan,
	}
end

function AreaConfig.getByIndex(index: number): AreaDef?
	return AreaConfig.Areas[index]
end

function AreaConfig.getById(id: string): AreaDef?
	for _, area in ipairs(AreaConfig.Areas) do
		if area.id == id then
			return area
		end
	end
	return nil
end

function AreaConfig.count(): number
	return #AreaConfig.Areas
end

return AreaConfig
