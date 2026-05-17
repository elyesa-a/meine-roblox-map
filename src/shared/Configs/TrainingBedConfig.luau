--!strict
-- Trainingsbetten: ein Trainingsbereich pro Area (10 Stueck).
--
-- Die BedDef-Form bleibt unveraendert. Der VirusLabBuilder liest diese
-- Tabelle fuer Rate, Rebirth-Anforderung und Farbe; TrainingZoneService
-- liest zur Laufzeit die Hitbox-Attribute (RequiredRebirth/PowerPerSecond),
-- die der Builder daraus setzt.
--
-- Rebirth-Anforderung exakt nach Vorgabe:
--   Area 1 Training: Rebirth 0  (direkt nach Spawn)
--   Area 2 Training: Rebirth 3
--   Area 3 Training: Rebirth 6  ... +3 je Area ... Area 9: 24
--   Area 10 Training: Rebirth 30

local AreaConfig = require(script.Parent:WaitForChild("AreaConfig"))

export type BedDef = {
	id: string,
	zoneId: string,
	requiredRebirth: number,
	powerPerSecond: number,
	localPosition: Vector3,
	color: Color3,
	enabled: boolean,
}

local TrainingBedConfig: { [number]: BedDef } = {}

for i, area in ipairs(AreaConfig.Areas) do
	TrainingBedConfig[i] = {
		id = "Area" .. tostring(i) .. "TrainingBed",
		zoneId = if i == 1 then "StartZone" else "Area" .. tostring(i),
		requiredRebirth = area.trainingRebirth,
		-- Skaliert deutlich pro Area (jeder Trainingsbereich ist staerker).
		powerPerSecond = math.floor(5 * (6 ^ (i - 1))),
		localPosition = Vector3.new(0, 1.5, 0),
		color = area.primaryColor,
		enabled = true,
	}
end

return TrainingBedConfig
