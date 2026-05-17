--!strict
-- Zonen-Definition.
-- Layout: Progressions-Zonen liegen als klare Sektor-Reihe im Laborraum.
-- Nicht jede Zone braucht ein Trainingsbett; einige sind Boss-/Atmosphaeren-
-- Sektoren fuer die groessere DNA Mutation Facility.

export type ZoneDef = {
	id: string,
	displayName: string,
	requiredRebirth: number,
	requiredPower: number,
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
		displayName = "Lab Entry",
		requiredRebirth = 0,
		requiredPower = 0,
		zoneMultiplier = 1,
		color = Color3.fromRGB(120, 200, 255),
		center = Vector3.new(-595, 0, -8),
		size = Vector3.new(126, 1, 126),
		enabled = true,
	},
	{
		id = "HospitalZone",
		displayName = "Bacteria Sector",
		requiredRebirth = 3,
		requiredPower = 500,
		zoneMultiplier = 2,
		color = Color3.fromRGB(120, 255, 170),
		center = Vector3.new(-425, 0, -8),
		size = Vector3.new(126, 1, 126),
		enabled = true,
	},
	{
		id = "MutationLabZone",
		displayName = "Virus Chamber",
		requiredRebirth = 10,
		requiredPower = 5000,
		zoneMultiplier = 5,
		color = Color3.fromRGB(230, 70, 90),
		center = Vector3.new(-255, 0, -8),
		size = Vector3.new(126, 1, 126),
		enabled = true,
	},
	{
		id = "QuarantineZone",
		displayName = "Toxic Facility",
		requiredRebirth = 25,
		requiredPower = 25000,
		zoneMultiplier = 12,
		color = Color3.fromRGB(150, 255, 70),
		center = Vector3.new(-85, 0, -8),
		size = Vector3.new(126, 1, 126),
		enabled = true,
	},
	{
		id = "FrostLabZone",
		displayName = "Frost Lab",
		requiredRebirth = 30,
		requiredPower = 100000,
		zoneMultiplier = 16,
		color = Color3.fromRGB(160, 235, 255),
		center = Vector3.new(85, 0, -8),
		size = Vector3.new(126, 1, 126),
		enabled = true,
	},
	{
		id = "MagmaReactorZone",
		displayName = "Magma Reactor",
		requiredRebirth = 40,
		requiredPower = 500000,
		zoneMultiplier = 22,
		color = Color3.fromRGB(255, 105, 45),
		center = Vector3.new(255, 0, -8),
		size = Vector3.new(126, 1, 126),
		enabled = true,
	},
	{
		id = "GlitchZone",
		displayName = "Glitch Core",
		requiredRebirth = 50,
		requiredPower = 2000000,
		zoneMultiplier = 30,
		color = Color3.fromRGB(255, 80, 200),
		center = Vector3.new(425, 0, -8),
		size = Vector3.new(126, 1, 126),
		enabled = true,
	},
	{
		id = "EndgameZone",
		displayName = "Final Mutation Core",
		requiredRebirth = 100,
		requiredPower = 10000000,
		zoneMultiplier = 100,
		color = Color3.fromRGB(255, 60, 60),
		center = Vector3.new(595, 0, -8),
		size = Vector3.new(126, 1, 126),
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
