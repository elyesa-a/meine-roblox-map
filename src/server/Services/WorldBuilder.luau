--!strict
-- WorldBuilder: erzeugt Zonen, Portale, Trainingsbetten und einen ClickerHub.
-- Wird einmal beim Server-Start aufgerufen. Alle Objekte landen unter Workspace.
--
-- Phase 5 Polish:
--  * Atmosphere / Lighting-Profil
--  * Neon-Glow-Streifen am Zonenrand
--  * Dekoration: Pillars an den Ecken
--  * Trainingsbetten mit Bett-Geometrie + permanenten Partikeln
--  * Portale mit Atmospheric SurfaceLight
--  * Geschlossener Laborraum mit zentraler Training-Reihe
--  * Kontrolliertes Neon, Naehe-Labels und EggCatchArea

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local ZoneConfig = require(Configs:WaitForChild("ZoneConfig"))
local TrainingBedConfig = require(Configs:WaitForChild("TrainingBedConfig"))

local WorldBuilder = {}

local ROOM_CENTER = Vector3.new(0, 0, 0)
local ROOM_SIZE = Vector3.new(1080, 1, 430)
local ROOM_WALL_HEIGHT = 74
local ROOM_WALL_THICKNESS = 6
local ROOM_CEILING_THICKNESS = 3
local ROOM_FLOOR_Y = -0.55
local START_AREA_CENTER = Vector3.new(0, 0, -165)
local EGG_AREA_CENTER = Vector3.new(-420, 0, 130)

local LABEL_DISTANCE_ZONE = 45
local LABEL_DISTANCE_TRAINING = 34
local LABEL_DISTANCE_INSTRUCTION = 24

local function makeFolder(name: string, parent: Instance): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing :: Folder
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function applyLighting()
	Lighting.Ambient = Color3.fromRGB(92, 96, 116)
	Lighting.OutdoorAmbient = Color3.fromRGB(112, 116, 134)
	Lighting.Brightness = 1.85
	Lighting.GlobalShadows = true
	Lighting.ExposureCompensation = 0
	Lighting.ClockTime = 14

	-- Bestehende Effekte entfernen, damit Re-Start sauber bleibt.
	for _, name in ipairs({ "VirusBloom", "VirusAtm", "VirusColor" }) do
		local existing = Lighting:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "VirusBloom"
	bloom.Intensity = 0.22
	bloom.Size = 8
	bloom.Threshold = 1.2
	bloom.Parent = Lighting

	local atm = Instance.new("Atmosphere")
	atm.Name = "VirusAtm"
	atm.Density = 0.12
	atm.Offset = 0.15
	atm.Color = Color3.fromRGB(200, 220, 255)
	atm.Decay = Color3.fromRGB(96, 104, 128)
	atm.Glare = 0.05
	atm.Haze = 0.35
	atm.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "VirusColor"
	cc.Saturation = 0.06
	cc.Contrast = 0.03
	cc.Parent = Lighting
end

local function addBillboardLabel(adornee: BasePart, text: string, color: Color3, maxDistance: number?)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(220, 60)
	billboard.StudsOffset = Vector3.new(0, 6, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = maxDistance or LABEL_DISTANCE_TRAINING
	billboard.Adornee = adornee
	billboard.Parent = adornee

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.Parent = billboard
end

local function addGlowStrip(parent: Instance, center: Vector3, length: number, axis: string, color: Color3)
	local strip = Instance.new("Part")
	strip.Anchored = true
	strip.CanCollide = false
	if axis == "X" then
		strip.Size = Vector3.new(length, 0.4, 1)
	else
		strip.Size = Vector3.new(1, 0.4, length)
	end
	strip.Position = center
	strip.Material = Enum.Material.Neon
	strip.Color = color
	strip.Transparency = 0.28
	strip.TopSurface = Enum.SurfaceType.Smooth
	strip.BottomSurface = Enum.SurfaceType.Smooth
	strip.Parent = parent
end

local function addPillar(parent: Instance, pos: Vector3, color: Color3)
	local pillar = Instance.new("Part")
	pillar.Anchored = true
	pillar.CanCollide = true
	pillar.Size = Vector3.new(3, 16, 3)
	pillar.Position = pos + Vector3.new(0, 8, 0)
	pillar.Material = Enum.Material.SmoothPlastic
	pillar.Color = Color3.fromRGB(30, 30, 40)
	pillar.Parent = parent

	local cap = Instance.new("Part")
	cap.Anchored = true
	cap.CanCollide = false
	cap.Size = Vector3.new(3.4, 0.6, 3.4)
	cap.Position = pillar.Position + Vector3.new(0, 8.3, 0)
	cap.Material = Enum.Material.Neon
	cap.Color = color
	cap.Transparency = 0.18
	cap.Parent = parent

	local light = Instance.new("PointLight")
	light.Brightness = 0.75
	light.Range = 12
	light.Color = color
	light.Parent = cap
end

local function makeRoomPart(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function addCeilingLight(parent: Instance, x: number, z: number)
	local topY = ROOM_FLOOR_Y + ROOM_SIZE.Y / 2 + ROOM_WALL_HEIGHT
	local lightPanel = makeRoomPart(
		parent,
		"CeilingLight",
		Vector3.new(52, 0.35, 10),
		Vector3.new(x, topY - 1.2, z),
		Color3.fromRGB(130, 210, 230),
		Enum.Material.Neon
	)
	lightPanel.CanCollide = false
	lightPanel.Transparency = 0.18

	local light = Instance.new("SurfaceLight")
	light.Name = "DownLight"
	light.Face = Enum.NormalId.Bottom
	light.Brightness = 1.35
	light.Range = 46
	light.Angle = 100
	light.Color = Color3.fromRGB(210, 245, 255)
	light.Parent = lightPanel
end

local function buildLabRoom(roomFolder: Folder)
	for _, child in ipairs(roomFolder:GetChildren()) do
		child:Destroy()
	end

	local floorTopY = ROOM_FLOOR_Y + ROOM_SIZE.Y / 2
	local wallCenterY = floorTopY + ROOM_WALL_HEIGHT / 2
	local wallColor = Color3.fromRGB(44, 50, 64)
	local floorColor = Color3.fromRGB(58, 66, 78)

	local floor = makeRoomPart(
		roomFolder,
		"MainLabFloor",
		ROOM_SIZE,
		Vector3.new(ROOM_CENTER.X, ROOM_FLOOR_Y, ROOM_CENTER.Z),
		floorColor,
		Enum.Material.SmoothPlastic
	)
	floor.Locked = true

	local startPad = makeRoomPart(
		roomFolder,
		"StartAreaPad",
		Vector3.new(150, 0.45, 66),
		START_AREA_CENTER + Vector3.new(0, 0.1, 0),
		Color3.fromRGB(35, 74, 88),
		Enum.Material.SmoothPlastic
	)
	startPad.CanCollide = true

	local halfX = ROOM_SIZE.X / 2
	local halfZ = ROOM_SIZE.Z / 2
	local wallT = ROOM_WALL_THICKNESS

	makeRoomPart(
		roomFolder,
		"LeftWall",
		Vector3.new(wallT, ROOM_WALL_HEIGHT, ROOM_SIZE.Z + wallT * 2),
		Vector3.new(ROOM_CENTER.X - halfX - wallT / 2, wallCenterY, ROOM_CENTER.Z),
		wallColor,
		Enum.Material.SmoothPlastic
	)
	makeRoomPart(
		roomFolder,
		"RightWall",
		Vector3.new(wallT, ROOM_WALL_HEIGHT, ROOM_SIZE.Z + wallT * 2),
		Vector3.new(ROOM_CENTER.X + halfX + wallT / 2, wallCenterY, ROOM_CENTER.Z),
		wallColor,
		Enum.Material.SmoothPlastic
	)
	makeRoomPart(
		roomFolder,
		"FrontWall",
		Vector3.new(ROOM_SIZE.X + wallT * 2, ROOM_WALL_HEIGHT, wallT),
		Vector3.new(ROOM_CENTER.X, wallCenterY, ROOM_CENTER.Z - halfZ - wallT / 2),
		wallColor,
		Enum.Material.SmoothPlastic
	)
	makeRoomPart(
		roomFolder,
		"BackWall",
		Vector3.new(ROOM_SIZE.X + wallT * 2, ROOM_WALL_HEIGHT, wallT),
		Vector3.new(ROOM_CENTER.X, wallCenterY, ROOM_CENTER.Z + halfZ + wallT / 2),
		wallColor,
		Enum.Material.SmoothPlastic
	)

	local ceiling = makeRoomPart(
		roomFolder,
		"Ceiling",
		Vector3.new(ROOM_SIZE.X + wallT * 2, ROOM_CEILING_THICKNESS, ROOM_SIZE.Z + wallT * 2),
		Vector3.new(ROOM_CENTER.X, floorTopY + ROOM_WALL_HEIGHT + ROOM_CEILING_THICKNESS / 2, ROOM_CENTER.Z),
		Color3.fromRGB(52, 58, 70),
		Enum.Material.SmoothPlastic
	)
	ceiling.Locked = true

	for _, x in ipairs({ -390, -234, -78, 78, 234, 390 }) do
		addCeilingLight(roomFolder, x, -35)
	end
	for _, x in ipairs({ -260, 0, 260 }) do
		addCeilingLight(roomFolder, x, 120)
	end
end

local function buildEggCatchArea(area: Folder)
	for _, child in ipairs(area:GetChildren()) do
		child:Destroy()
	end

	local pad = makeRoomPart(
		area,
		"Pad",
		Vector3.new(150, 0.55, 76),
		EGG_AREA_CENTER + Vector3.new(0, 0.15, 0),
		Color3.fromRGB(30, 70, 76),
		Enum.Material.SmoothPlastic
	)

	local halfX = pad.Size.X / 2
	local halfZ = pad.Size.Z / 2
	local stripY = pad.Position.Y + 0.45
	local accentColor = Color3.fromRGB(80, 225, 210)
	addGlowStrip(area, Vector3.new(EGG_AREA_CENTER.X, stripY, EGG_AREA_CENTER.Z - halfZ), pad.Size.X, "X", accentColor)
	addGlowStrip(area, Vector3.new(EGG_AREA_CENTER.X, stripY, EGG_AREA_CENTER.Z + halfZ), pad.Size.X, "X", accentColor)
	addGlowStrip(area, Vector3.new(EGG_AREA_CENTER.X - halfX, stripY, EGG_AREA_CENTER.Z), pad.Size.Z, "Z", accentColor)
	addGlowStrip(area, Vector3.new(EGG_AREA_CENTER.X + halfX, stripY, EGG_AREA_CENTER.Z), pad.Size.Z, "Z", accentColor)

	for _, dx in ipairs({ -44, 0, 44 }) do
		local base = makeRoomPart(
			area,
			"FutureEggMachineBase",
			Vector3.new(22, 0.8, 18),
			EGG_AREA_CENTER + Vector3.new(dx, 0.75, -20),
			Color3.fromRGB(34, 44, 56),
			Enum.Material.SmoothPlastic
		)
		local line = makeRoomPart(
			area,
			"MachineAccent",
			Vector3.new(18, 0.3, 1.2),
			base.Position + Vector3.new(0, 0.55, 7),
			accentColor,
			Enum.Material.Neon
		)
		line.CanCollide = false
		line.Transparency = 0.25
	end
end

local function makeDecorPart(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material, canCollide: boolean?): Part
	local part = makeRoomPart(parent, name, size, position, color, material)
	part.CanCollide = if canCollide == nil then false else canCollide
	return part
end

local function addTrainingDecorStation(parent: Instance, name: string, pos: Vector3, color: Color3, theme: string)
	local station = Instance.new("Model")
	station.Name = name
	station.Parent = parent

	local base = makeDecorPart(
		station,
		"Base",
		Vector3.new(12, 0.8, 8),
		pos + Vector3.new(0, 0.45, 0),
		Color3.fromRGB(38, 44, 54),
		Enum.Material.SmoothPlastic,
		true
	)

	if theme == "Bed" then
		makeDecorPart(station, "Mattress", Vector3.new(9, 0.8, 4.5), base.Position + Vector3.new(0, 0.8, 0), color, Enum.Material.SmoothPlastic, true)
		makeDecorPart(station, "Pillow", Vector3.new(3, 0.8, 3.8), base.Position + Vector3.new(-3, 1.45, 0), Color3.fromRGB(210, 218, 226), Enum.Material.SmoothPlastic, true)
		local rail = makeDecorPart(station, "SoftAccent", Vector3.new(9, 0.25, 0.4), base.Position + Vector3.new(0, 1.55, 2.4), color, Enum.Material.Neon, false)
		rail.Transparency = 0.35
	elseif theme == "Tank" then
		local tank = makeDecorPart(station, "Capsule", Vector3.new(5, 10, 5), base.Position + Vector3.new(0, 5.3, 0), color, Enum.Material.Glass, false)
		tank.Shape = Enum.PartType.Cylinder
		tank.Transparency = 0.45
		local core = makeDecorPart(station, "SampleCore", Vector3.new(2.2, 5.5, 2.2), base.Position + Vector3.new(0, 5.1, 0), color, Enum.Material.Neon, false)
		core.Shape = Enum.PartType.Ball
		core.Transparency = 0.28
	elseif theme == "Quarantine" then
		makeDecorPart(station, "Chamber", Vector3.new(8, 7, 5), base.Position + Vector3.new(0, 3.9, 0), Color3.fromRGB(46, 50, 58), Enum.Material.SmoothPlastic, true)
		local stripeA = makeDecorPart(station, "WarningStripe", Vector3.new(8.4, 0.25, 0.5), base.Position + Vector3.new(0, 7.6, -2.7), color, Enum.Material.Neon, false)
		local stripeB = makeDecorPart(station, "WarningStripe", Vector3.new(8.4, 0.25, 0.5), base.Position + Vector3.new(0, 1.4, 2.7), color, Enum.Material.Neon, false)
		stripeA.Transparency = 0.35
		stripeB.Transparency = 0.35
	elseif theme == "Glitch" then
		local slab = makeDecorPart(station, "DigitalBed", Vector3.new(9, 0.6, 4.2), base.Position + Vector3.new(0, 1.05, 0), Color3.fromRGB(34, 38, 52), Enum.Material.SmoothPlastic, true)
		for i, offset in ipairs({ -3.5, -1.5, 1.5, 3.5 }) do
			local bit = makeDecorPart(station, "FloatingBit" .. tostring(i), Vector3.new(1.3, 1.3, 1.3), slab.Position + Vector3.new(offset, 3 + (i % 2), 0), color, Enum.Material.Neon, false)
			bit.Transparency = 0.25
		end
	else
		local core = makeDecorPart(station, "VirusCore", Vector3.new(5.5, 5.5, 5.5), base.Position + Vector3.new(0, 3.5, 0), color, Enum.Material.Neon, false)
		core.Shape = Enum.PartType.Ball
		core.Transparency = 0.32
		makeDecorPart(station, "CoreStand", Vector3.new(3, 4, 3), base.Position + Vector3.new(0, 2.2, 0), Color3.fromRGB(36, 40, 50), Enum.Material.SmoothPlastic, true)
	end
end

local function addTrainingDecor(model: Model, bed, worldPos: Vector3)
	local folder = Instance.new("Folder")
	folder.Name = "VisualTrainingObjects"
	folder.Parent = model

	local theme = "Bed"
	if bed.id == "MutationBed" or bed.id == "InfectionBed" then
		theme = "Tank"
	elseif bed.id == "QuarantineBed" then
		theme = "Quarantine"
	elseif bed.id == "GlitchBed" then
		theme = "Glitch"
	elseif bed.id == "EndgameBed" then
		theme = "Core"
	end

	local offsets = {
		Vector3.new(-34, 0, -24),
		Vector3.new(-17, 0, 26),
		Vector3.new(0, 0, -28),
		Vector3.new(17, 0, 26),
		Vector3.new(34, 0, -24),
	}
	for i, offset in ipairs(offsets) do
		addTrainingDecorStation(folder, "TrainingObject" .. tostring(i), worldPos + offset, bed.color, theme)
	end
end

local function buildZone(zone, zonesFolder: Folder)
	if not zone.enabled then
		return
	end
	local zoneModel = Instance.new("Model")
	zoneModel.Name = zone.id
	zoneModel.Parent = zonesFolder

	local ground = Instance.new("Part")
	ground.Name = "Ground"
	ground.Anchored = true
	ground.CanCollide = true
	ground.Size = zone.size
	ground.Position = zone.center
	ground.Color = zone.color
	ground.Material = Enum.Material.SmoothPlastic
	ground.TopSurface = Enum.SurfaceType.Smooth
	ground.Parent = zoneModel

	-- Glow-Streifen rundherum.
	local halfX = zone.size.X / 2
	local halfZ = zone.size.Z / 2
	local stripY = zone.center.Y + 0.6
	addGlowStrip(zoneModel, Vector3.new(zone.center.X, stripY, zone.center.Z - halfZ), zone.size.X, "X", zone.color)
	addGlowStrip(zoneModel, Vector3.new(zone.center.X, stripY, zone.center.Z + halfZ), zone.size.X, "X", zone.color)
	addGlowStrip(zoneModel, Vector3.new(zone.center.X - halfX, stripY, zone.center.Z), zone.size.Z, "Z", zone.color)
	addGlowStrip(zoneModel, Vector3.new(zone.center.X + halfX, stripY, zone.center.Z), zone.size.Z, "Z", zone.color)

	-- Eck-Pillars.
	for _, dx in ipairs({ -1, 1 }) do
		for _, dz in ipairs({ -1, 1 }) do
			addPillar(
				zoneModel,
				Vector3.new(zone.center.X + dx * (halfX - 2), zone.center.Y, zone.center.Z + dz * (halfZ - 2)),
				zone.color
			)
		end
	end

	-- Schild mit Zonen-Namen.
	local sign = Instance.new("Part")
	sign.Name = "Sign"
	sign.Anchored = true
	sign.CanCollide = false
	sign.Size = Vector3.new(10, 8, 1)
	sign.Position = zone.center + Vector3.new(0, 10, halfZ - 1)
	sign.Color = zone.color
	sign.Material = Enum.Material.SmoothPlastic
	sign.Parent = zoneModel
	addBillboardLabel(sign, zone.displayName, Color3.fromRGB(255, 255, 255), LABEL_DISTANCE_ZONE)

	-- SpawnPoint fuer die StartZone, damit Spieler dort respawnen.
	if zone.id == "StartZone" then
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "StartSpawn"
		spawn.Anchored = true
		spawn.CanCollide = false
		spawn.Size = Vector3.new(8, 1, 8)
		spawn.Position = START_AREA_CENTER + Vector3.new(0, 1, 0)
		spawn.Color = Color3.fromRGB(60, 220, 100)
		spawn.Material = Enum.Material.Neon
		spawn.Transparency = 0.35
		spawn.TopSurface = Enum.SurfaceType.Smooth
		spawn.Parent = zoneModel

		-- Glow am Spawn.
		local light = Instance.new("PointLight")
		light.Brightness = 1.1
		light.Range = 14
		light.Color = Color3.fromRGB(120, 255, 160)
		light.Parent = spawn
	end
end

local function buildPortal(zone, portalsFolder: Folder)
	if not zone.enabled or zone.id == "StartZone" then
		return
	end
	local portal = Instance.new("Part")
	portal.Name = zone.id .. "_Portal"
	portal.Anchored = true
	portal.CanCollide = false
	portal.Size = Vector3.new(10, 14, 2)
	portal.Position = zone.center - Vector3.new(zone.size.X / 2 + 4, -7, 0)
	portal.Color = zone.color
	portal.Material = Enum.Material.ForceField
	portal.Transparency = 0.42
	portal.Parent = portalsFolder

	portal:SetAttribute("ZoneId", zone.id)
	portal:SetAttribute("RequiredRebirth", zone.requiredRebirth)

	-- Light innen.
	local light = Instance.new("PointLight")
	light.Brightness = 1.25
	light.Range = 16
	light.Color = zone.color
	light.Parent = portal

	-- Schwebende Partikel im Portal.
	local att = Instance.new("Attachment")
	att.Parent = portal
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(zone.color)
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Rate = 8
	emitter.Speed = NumberRange.new(1, 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.LightEmission = 0.7
	emitter.Parent = att

	addBillboardLabel(
		portal,
		string.format("%s\nRebirth %d benoetigt", zone.displayName, zone.requiredRebirth),
		Color3.fromRGB(255, 255, 255),
		LABEL_DISTANCE_ZONE
	)
end

local function buildBed(bed, bedsFolder: Folder)
	if not bed.enabled then
		return
	end
	local zone = ZoneConfig.getById(bed.zoneId)
	if not zone or not zone.enabled then
		return
	end
	local model = Instance.new("Model")
	model.Name = bed.id
	model.Parent = bedsFolder

	local worldPos = zone.center + bed.localPosition

	-- Bett-Basis (Matratze).
	local frame = Instance.new("Part")
	frame.Name = "Frame"
	frame.Anchored = true
	frame.CanCollide = true
	frame.Size = Vector3.new(8, 1.2, 4)
	frame.Position = worldPos + Vector3.new(0, 0.6, 0)
	frame.Color = bed.color
	frame.Material = Enum.Material.SmoothPlastic
	frame.TopSurface = Enum.SurfaceType.Smooth
	frame.Parent = model

	-- Kopfteil.
	local headboard = Instance.new("Part")
	headboard.Name = "Headboard"
	headboard.Anchored = true
	headboard.CanCollide = true
	headboard.Size = Vector3.new(8, 4, 0.8)
	headboard.Position = worldPos + Vector3.new(0, 2.6, -2)
	headboard.Color = Color3.fromRGB(30, 30, 40)
	headboard.Material = Enum.Material.SmoothPlastic
	headboard.Parent = model

	-- Beine.
	for _, dx in ipairs({ -1, 1 }) do
		for _, dz in ipairs({ -1, 1 }) do
			local leg = Instance.new("Part")
			leg.Anchored = true
			leg.CanCollide = true
			leg.Size = Vector3.new(0.6, 1.2, 0.6)
			leg.Position = worldPos + Vector3.new(dx * 3.7, 0, dz * 1.7)
			leg.Color = Color3.fromRGB(30, 30, 40)
			leg.Material = Enum.Material.SmoothPlastic
			leg.Parent = model
		end
	end

	-- Decken-Highlight (Neon-Streifen oben am Kopfteil).
	local accent = Instance.new("Part")
	accent.Name = "Accent"
	accent.Anchored = true
	accent.CanCollide = false
	accent.Size = Vector3.new(8, 0.4, 0.4)
	accent.Position = headboard.Position + Vector3.new(0, 2.2, 0.4)
	accent.Color = bed.color
	accent.Material = Enum.Material.Neon
	accent.Transparency = 0.25
	accent.Parent = model

	-- Permanenter sanfter Pulse-Emitter ueber dem Bett.
	local att = Instance.new("Attachment")
	att.Position = Vector3.new(0, 2, 0)
	att.Parent = frame
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(bed.color)
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Rate = 3
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Size = NumberSequence.new(0.5, 0.1)
	emitter.Transparency = NumberSequence.new(0.4, 1)
	emitter.LightEmission = 0.25
	emitter.Parent = att

	-- Hitbox (unsichtbar) ueber dem Bett: hier wird Training getriggert.
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.Transparency = 1
	hitbox.Size = Vector3.new(8, 6, 4)
	hitbox.Position = worldPos + Vector3.new(0, 3, 0)
	hitbox.Parent = model
	hitbox:SetAttribute("BedId", bed.id)
	hitbox:SetAttribute("PowerPerSecond", bed.powerPerSecond)
	hitbox:SetAttribute("RequiredRebirth", bed.requiredRebirth)

	addBillboardLabel(
		frame,
		string.format("%s\n+%d Kraft/s", bed.id, bed.powerPerSecond),
		Color3.fromRGB(255, 255, 255),
		LABEL_DISTANCE_TRAINING
	)

	addTrainingDecor(model, bed, worldPos)
end

local function buildClickerHub(_startZone, parent: Instance)
	local pad = Instance.new("Part")
	pad.Name = "ClickerHub"
	pad.Anchored = true
	pad.CanCollide = false
	pad.Size = Vector3.new(14, 1, 14)
	pad.Position = START_AREA_CENTER + Vector3.new(34, 0.85, 20)
	pad.Color = Color3.fromRGB(255, 90, 90)
	pad.Material = Enum.Material.Neon
	pad.Transparency = 0.38
	pad.Parent = parent

	-- Pulsierendes Ring-Visual.
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Anchored = true
	ring.CanCollide = false
	ring.Size = Vector3.new(16, 0.4, 16)
	ring.Position = pad.Position + Vector3.new(0, 0.4, 0)
	ring.Color = Color3.fromRGB(255, 140, 140)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.58
	ring.Parent = parent

	local light = Instance.new("PointLight")
	light.Brightness = 1.1
	light.Range = 16
	light.Color = Color3.fromRGB(255, 120, 120)
	light.Parent = pad

	addBillboardLabel(pad, "KLICK-PAD\n(Knopf unten auf dem Bildschirm)", Color3.fromRGB(255, 255, 255), LABEL_DISTANCE_INSTRUCTION)
end

local function buildPetEgg(_startZone, parent: Instance): BasePart
	local egg = Instance.new("Part")
	egg.Name = "PetEgg"
	egg.Anchored = true
	egg.CanCollide = false
	egg.Shape = Enum.PartType.Ball
	egg.Size = Vector3.new(6, 6, 6)
	egg.Position = EGG_AREA_CENTER + Vector3.new(0, 5.2, 10)
	egg.Color = Color3.fromRGB(105, 235, 220)
	egg.Material = Enum.Material.Neon
	egg.Transparency = 0.18
	egg.Parent = parent

	local light = Instance.new("PointLight")
	light.Brightness = 1.2
	light.Range = 14
	light.Color = Color3.fromRGB(120, 245, 230)
	light.Parent = egg

	-- Schwebepartikel um das Ei.
	local att = Instance.new("Attachment")
	att.Parent = egg
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(125, 245, 230))
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Rate = 6
	emitter.Speed = NumberRange.new(1, 2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.6, 0.1)
	emitter.Transparency = NumberSequence.new(0.35, 1)
	emitter.LightEmission = 0.35
	emitter.Parent = att

	local clicker = Instance.new("ClickDetector")
	clicker.Name = "OpenEgg"
	clicker.MaxActivationDistance = 16
	clicker.Parent = egg

	addBillboardLabel(egg, "PET EGG\nClick to open", Color3.fromRGB(255, 255, 255), LABEL_DISTANCE_INSTRUCTION)
	return egg
end

function WorldBuilder.build()
	applyLighting()

	local roomFolder = makeFolder("LabRoom", Workspace)
	local zonesFolder = makeFolder("Zones", Workspace)
	local portalsFolder = makeFolder("Portals", Workspace)
	local bedsFolder = makeFolder("TrainingBeds", Workspace)
	local eggAreaFolder = makeFolder("EggCatchArea", Workspace)

	buildLabRoom(roomFolder)
	buildEggCatchArea(eggAreaFolder)

	for _, zone in ipairs(ZoneConfig) do
		buildZone(zone, zonesFolder)
		buildPortal(zone, portalsFolder)
	end

	for _, bed in ipairs(TrainingBedConfig) do
		buildBed(bed, bedsFolder)
	end

	local startZone = ZoneConfig.getById("StartZone")
	if startZone then
		buildClickerHub(startZone, Workspace)
		WorldBuilder.PetEgg = buildPetEgg(startZone, eggAreaFolder)
	end

	print("[WorldBuilder] Welt erzeugt.")
end

return WorldBuilder
