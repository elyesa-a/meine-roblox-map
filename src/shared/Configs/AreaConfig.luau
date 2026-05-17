--!strict
-- AreaConfig: zentrale Daten-Tabelle fuer das Virus-Labor.
--
-- 10 Areale, linear entlang +X angeordnet. Jede Area hat:
--  * Identitaet (id, displayName, bossName)
--  * Akzentfarben (primary + secondary)
--  * Training-Rebirth-Anforderung (Trainingsbereich der Area)
--  * Layout-Position (Mittelpunkt der Gegner-Halle in der Welt)
--
-- DNA-Anforderungen der Gates/Borders werden datenbasiert aus EnemyConfig
-- abgeleitet (DNA-Drop des jeweils naechsten Gegners), damit es nur eine
-- Quelle der Wahrheit fuer das *4-Scaling gibt.

export type AreaDef = {
	index: number,
	id: string,
	displayName: string,
	bossName: string,
	primaryColor: Color3,
	secondaryColor: Color3,
	-- Rebirth-Anforderung fuer den Trainingsbereich dieser Area.
	trainingRebirth: number,
	-- Welt-X der Mitte der Gegner-Halle dieser Area.
	hallCenterX: number,
}

local AreaConfig = {}

-- ----- Layout-Konstanten (eine Quelle der Wahrheit) ------------------------
AreaConfig.Layout = {
	AreaSpan = 520, -- X-Abstand zwischen zwei Area-Mittelpunkten
	FirstHallX = 260, -- X der ersten Gegner-Halle (Area 1)
	EnemySpacing = 32, -- X-Abstand zwischen zwei Gegnern
	EnemiesPerArea = 10,
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

-- Reihenfolge & Farben exakt nach Vorgabe.
local areaData = {
	{ name = "Bacteria Lab", boss = "Bacteria Overlord", rb = 0, p = rgb(90, 230, 120), s = rgb(190, 255, 205) },
	{ name = "Infected Cells", boss = "Cell Breaker", rb = 3, p = rgb(80, 220, 235), s = rgb(195, 245, 250) },
	{ name = "Mutation Sector", boss = "Mutation Brute", rb = 6, p = rgb(175, 110, 245), s = rgb(220, 195, 255) },
	{ name = "Toxic Storage", boss = "Toxic Crusher", rb = 9, p = rgb(200, 230, 70), s = rgb(235, 250, 170) },
	{ name = "Virus Chamber", boss = "Virus Reaper", rb = 12, p = rgb(235, 70, 70), s = rgb(255, 185, 185) },
	{ name = "Corrupted Lab", boss = "Corrupted Beast", rb = 15, p = rgb(255, 150, 55), s = rgb(255, 210, 160) },
	{ name = "Biohazard Core", boss = "Biohazard Titan", rb = 18, p = rgb(150, 255, 70), s = rgb(210, 255, 170) },
	{ name = "Dark Mutation", boss = "Dark Mutation King", rb = 21, p = rgb(120, 60, 170), s = rgb(180, 130, 220) },
	{ name = "Omega Virus Lab", boss = "Omega Virus", rb = 24, p = rgb(200, 45, 55), s = rgb(70, 70, 80) },
	{ name = "Final Containment", boss = "Final DNA Destroyer", rb = 30, p = rgb(255, 70, 120), s = rgb(90, 230, 245) },
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
