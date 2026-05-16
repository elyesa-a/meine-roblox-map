--!strict
-- Zonen-Definition.
-- Layout: alle Progressions-Zonen liegen als klare horizontale Reihe im
-- geschlossenen Laborraum. Die Reihenfolge entspricht der Training-Progression.

export type ZoneDef = {
	id: string,
	displayName: string,
	requiredRebirth: number,
	zoneMultiplier: number,
	color: Color3,
	-- Position des Zonen-Bodens (Mittelpunkt).
	center: Vector3,
	size: Vector3,
	enabled: boolean,
}

local ZoneConfig: { [number]: ZoneDef } = {
	{
		id = "StartZone",
		displayName = "Startzone",
		requiredRebirth = 0,
		zoneMultiplier = 1,
		color = Color3.fromRGB(120, 200, 255),
		center = Vector3.new(-300, 0, 0),
		size = Vector3.new(96, 1, 92),
		enabled = true,
	},
	{
		id = "HospitalZone",
		displayName = "Krankenhaus",
		requiredRebirth = 3,
		zoneMultiplier = 2,
		color = Color3.fromRGB(120, 255, 170),
		center = Vector3.new(-180, 0, 0),
		size = Vector3.new(96, 1, 92),
		enabled = true,
	},
	{
		id = "MutationLabZone",
		displayName = "Mutationslabor",
		requiredRebirth = 10,
		zoneMultiplier = 5,
		color = Color3.fromRGB(200, 120, 255),
		center = Vector3.new(-60, 0, 0),
		size = Vector3.new(96, 1, 92),
		enabled = true,
	},
	{
		id = "QuarantineZone",
		displayName = "Quarantaene",
		requiredRebirth = 25,
		zoneMultiplier = 12,
		color = Color3.fromRGB(255, 200, 80),
		center = Vector3.new(60, 0, 0),
		size = Vector3.new(96, 1, 92),
		enabled = true,
	},
	{
		id = "GlitchZone",
		displayName = "Glitch-Virus-Dimension",
		requiredRebirth = 50,
		zoneMultiplier = 30,
		color = Color3.fromRGB(255, 80, 200),
		center = Vector3.new(180, 0, 0),
		size = Vector3.new(96, 1, 92),
		enabled = true,
	},
	{
		id = "EndgameZone",
		displayName = "Endgame",
		requiredRebirth = 100,
		zoneMultiplier = 100,
		color = Color3.fromRGB(255, 60, 60),
		center = Vector3.new(300, 0, 0),
		size = Vector3.new(96, 1, 92),
		enabled = true,
	},
}

function ZoneConfig.getById(id: string): ZoneDef?
	for _, z in ipairs(ZoneConfig) do
		if z.id == id then
			return z
		end
	end
	return nil
end

return ZoneConfig
