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

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local ZoneConfig = require(Configs:WaitForChild("ZoneConfig"))
local TrainingBedConfig = require(Configs:WaitForChild("TrainingBedConfig"))

local WorldBuilder = {}

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
	Lighting.Ambient = Color3.fromRGB(40, 40, 60)
	Lighting.OutdoorAmbient = Color3.fromRGB(60, 60, 90)
	Lighting.Brightness = 2
	Lighting.GlobalShadows = true
	Lighting.ExposureCompensation = 0.2
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
	bloom.Intensity = 0.6
	bloom.Size = 16
	bloom.Threshold = 0.95
	bloom.Parent = Lighting

	local atm = Instance.new("Atmosphere")
	atm.Name = "VirusAtm"
	atm.Density = 0.3
	atm.Offset = 0.25
	atm.Color = Color3.fromRGB(200, 220, 255)
	atm.Decay = Color3.fromRGB(106, 112, 142)
	atm.Glare = 0.15
	atm.Haze = 1
	atm.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "VirusColor"
	cc.Saturation = 0.15
	cc.Contrast = 0.05
	cc.Parent = Lighting
end

local function addBillboardLabel(adornee: BasePart, text: string, color: Color3)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(220, 60)
	billboard.StudsOffset = Vector3.new(0, 6, 0)
	billboard.AlwaysOnTop = true
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
	cap.Parent = parent

	local light = Instance.new("PointLight")
	light.Brightness = 2
	light.Range = 18
	light.Color = color
	light.Parent = cap
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
	sign.Material = Enum.Material.Neon
	sign.Parent = zoneModel
	addBillboardLabel(sign, zone.displayName, Color3.fromRGB(255, 255, 255))

	-- SpawnPoint fuer die StartZone, damit Spieler dort respawnen.
	if zone.id == "StartZone" then
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "StartSpawn"
		spawn.Anchored = true
		spawn.CanCollide = false
		spawn.Size = Vector3.new(8, 1, 8)
		spawn.Position = zone.center + Vector3.new(0, 1.5, 0)
		spawn.Color = Color3.fromRGB(60, 220, 100)
		spawn.Material = Enum.Material.Neon
		spawn.Transparency = 0.2
		spawn.TopSurface = Enum.SurfaceType.Smooth
		spawn.Parent = zoneModel

		-- Glow am Spawn.
		local light = Instance.new("PointLight")
		light.Brightness = 3
		light.Range = 20
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
	portal.Transparency = 0.2
	portal.Parent = portalsFolder

	portal:SetAttribute("ZoneId", zone.id)
	portal:SetAttribute("RequiredRebirth", zone.requiredRebirth)

	-- Light innen.
	local light = Instance.new("PointLight")
	light.Brightness = 4
	light.Range = 22
	light.Color = zone.color
	light.Parent = portal

	-- Schwebende Partikel im Portal.
	local att = Instance.new("Attachment")
	att.Parent = portal
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(zone.color)
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Rate = 18
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
		Color3.fromRGB(255, 255, 255)
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
	accent.Parent = model

	-- Permanenter sanfter Pulse-Emitter ueber dem Bett.
	local att = Instance.new("Attachment")
	att.Position = Vector3.new(0, 2, 0)
	att.Parent = frame
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(bed.color)
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Rate = 6
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Size = NumberSequence.new(0.5, 0.1)
	emitter.Transparency = NumberSequence.new(0.4, 1)
	emitter.LightEmission = 0.4
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
		Color3.fromRGB(255, 255, 255)
	)
end

local function buildClickerHub(startZone, parent: Instance)
	local pad = Instance.new("Part")
	pad.Name = "ClickerHub"
	pad.Anchored = true
	pad.CanCollide = false
	pad.Size = Vector3.new(14, 1, 14)
	pad.Position = startZone.center + Vector3.new(0, 0.6, 20)
	pad.Color = Color3.fromRGB(255, 90, 90)
	pad.Material = Enum.Material.Neon
	pad.Transparency = 0.1
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
	ring.Transparency = 0.4
	ring.Parent = parent

	local light = Instance.new("PointLight")
	light.Brightness = 3
	light.Range = 24
	light.Color = Color3.fromRGB(255, 120, 120)
	light.Parent = pad

	addBillboardLabel(pad, "KLICK-PAD\n(Knopf unten auf dem Bildschirm)", Color3.fromRGB(255, 255, 255))
end

local function buildPetEgg(startZone, parent: Instance): BasePart
	local egg = Instance.new("Part")
	egg.Name = "PetEgg"
	egg.Anchored = true
	egg.CanCollide = false
	egg.Shape = Enum.PartType.Ball
	egg.Size = Vector3.new(6, 6, 6)
	egg.Position = startZone.center + Vector3.new(-20, 4, 10)
	egg.Color = Color3.fromRGB(255, 220, 90)
	egg.Material = Enum.Material.Neon
	egg.Parent = parent

	local light = Instance.new("PointLight")
	light.Brightness = 4
	light.Range = 18
	light.Color = Color3.fromRGB(255, 220, 90)
	light.Parent = egg

	-- Schwebepartikel um das Ei.
	local att = Instance.new("Attachment")
	att.Parent = egg
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Rate = 14
	emitter.Speed = NumberRange.new(1, 2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.6, 0.1)
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.LightEmission = 0.6
	emitter.Parent = att

	local clicker = Instance.new("ClickDetector")
	clicker.Name = "OpenEgg"
	clicker.MaxActivationDistance = 16
	clicker.Parent = egg

	addBillboardLabel(egg, "PET-EI\n(Klicken zum Oeffnen)", Color3.fromRGB(255, 255, 255))
	return egg
end

function WorldBuilder.build()
	applyLighting()

	local zonesFolder = makeFolder("Zones", Workspace)
	local portalsFolder = makeFolder("Portals", Workspace)
	local bedsFolder = makeFolder("TrainingBeds", Workspace)

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
		WorldBuilder.PetEgg = buildPetEgg(startZone, Workspace)
	end

	print("[WorldBuilder] Welt erzeugt.")
end

return WorldBuilder
