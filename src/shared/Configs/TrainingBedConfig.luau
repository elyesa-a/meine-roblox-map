--!strict
-- Trainingsbetten: jedes Bett liegt in einer Zone und produziert pro Sekunde Kraft.
-- Multiplikatoren (Rebirth, Zone, etc.) werden im StatService oben drauf gerechnet.

export type BedDef = {
	id: string,
	zoneId: string,
	requiredRebirth: number,
	powerPerSecond: number,
	-- Lokale Position relativ zur Zone (wird vom WorldBuilder + Zone-Center kombiniert).
	localPosition: Vector3,
	color: Color3,
	enabled: boolean,
}

local TrainingBedConfig: { [number]: BedDef } = {
	{
		id = "StandardBed",
		zoneId = "StartZone",
		requiredRebirth = 0,
		powerPerSecond = 5,
		localPosition = Vector3.new(0, 1.5, -20),
		color = Color3.fromRGB(220, 220, 220),
		enabled = true,
	},
	{
		id = "InfectionBed",
		zoneId = "HospitalZone",
		requiredRebirth = 3,
		powerPerSecond = 50,
		localPosition = Vector3.new(0, 1.5, -20),
		color = Color3.fromRGB(120, 255, 170),
		enabled = true,
	},
	{
		id = "MutationBed",
		zoneId = "MutationLabZone",
		requiredRebirth = 10,
		powerPerSecond = 500,
		localPosition = Vector3.new(0, 1.5, -20),
		color = Color3.fromRGB(200, 120, 255),
		enabled = true,
	},
	{
		id = "QuarantineBed",
		zoneId = "QuarantineZone",
		requiredRebirth = 25,
		powerPerSecond = 5000,
		localPosition = Vector3.new(0, 1.5, -20),
		color = Color3.fromRGB(255, 200, 80),
		enabled = false,
	},
	{
		id = "GlitchBed",
		zoneId = "GlitchZone",
		requiredRebirth = 50,
		powerPerSecond = 50000,
		localPosition = Vector3.new(0, 1.5, -20),
		color = Color3.fromRGB(255, 80, 200),
		enabled = false,
	},
	{
		id = "EndgameBed",
		zoneId = "EndgameZone",
		requiredRebirth = 100,
		powerPerSecond = 500000,
		localPosition = Vector3.new(0, 1.5, -20),
		color = Color3.fromRGB(255, 60, 60),
		enabled = false,
	},
}

return TrainingBedConfig
