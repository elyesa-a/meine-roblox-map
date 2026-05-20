--!strict
-- Zonen-Definition -- jetzt 1 Zone pro Virus-Labor-Area (10 Stueck), linear.
--
-- Die ZoneDef-Form und getById bleiben UNVERAENDERT, damit bestehende
-- Systeme (ZoneLockService, TrainingZoneService, Client ProgressionPanel)
-- ohne Aenderung weiterlaufen. Nur Anzahl/Werte der Zonen wurden neu
-- ausgerichtet auf die 10 Areale (siehe AreaConfig).
--
-- Zone i deckt das komplette Area-Segment ab (Trainingsbereich + Gegner-
-- Halle). requiredRebirth = Trainings-Rebirth der Area. Die Zonen liegen
-- contiguous und ueberlappen nicht (Layout aus AreaConfig).

local AreaConfig = require(script.Parent:WaitForChild("AreaConfig"))

export type ZoneDef = {
	id: string,
	displayName: string,
	requiredRebirth: number,
	requiredPower: number,
	zoneMultiplier: number,
	color: Color3,
	center: Vector3,
	size: Vector3,
	enabled: boolean,
}

local ZoneConfig: { [number]: ZoneDef } = {}

local zoneMultipliers = { 1, 2, 4, 7, 12, 18, 26, 40, 65, 100 }
local span = AreaConfig.Layout.AreaSpan

for i, area in ipairs(AreaConfig.Areas) do
	ZoneConfig[i] = {
		-- Zone 1 behaelt die Id "StartZone", damit ZoneConfig.getById("StartZone")
		-- (von ZoneLockService genutzt) weiterhin aufloest.
		id = if i == 1 then "StartZone" else "Area" .. tostring(i),
		displayName = area.displayName,
		requiredRebirth = area.trainingRebirth,
		requiredPower = area.requiredPower,
		zoneMultiplier = zoneMultipliers[i] or 1,
		color = area.primaryColor,
		-- Segment-Mitte = Gegner-Halle; deckt Trainingsbereich + Halle ab.
		center = Vector3.new(area.hallCenterX, 0, 0),
		size = Vector3.new(span, 1, 200),
		enabled = true,
	}
end

function ZoneConfig.getById(id: string): ZoneDef?
	for _, z in ipairs(ZoneConfig) do
		if z.id == id then
			return z
		end
	end
	return nil
end

return ZoneConfig
