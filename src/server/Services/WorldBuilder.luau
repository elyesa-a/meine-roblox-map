--!strict
-- WorldBuilder: erzeugt Zonen, Portale, Trainingsbetten und einen ClickerHub.
-- Wird einmal beim Server-Start aufgerufen. Alle Objekte landen unter Workspace.

local Workspace = game:GetService("Workspace")
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
	ground.Parent = zoneModel

	-- Schild mit Zonen-Namen.
	local sign = Instance.new("Part")
	sign.Name = "Sign"
	sign.Anchored = true
	sign.CanCollide = false
	sign.Size = Vector3.new(8, 8, 1)
	sign.Position = zone.center + Vector3.new(0, 8, zone.size.Z / 2 - 1)
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
		spawn.Size = Vector3.new(6, 1, 6)
		spawn.Position = zone.center + Vector3.new(0, 1.5, 0)
		spawn.Color = Color3.fromRGB(60, 220, 100)
		spawn.Material = Enum.Material.Neon
		spawn.Transparency = 0.2
		spawn.TopSurface = Enum.SurfaceType.Smooth
		spawn.Parent = zoneModel
	end
end

local function buildPortal(zone, portalsFolder: Folder)
	-- Portale fuehren ZU einer Zone. Die StartZone hat kein Eingangs-Portal.
	if not zone.enabled or zone.id == "StartZone" then
		return
	end
	local portal = Instance.new("Part")
	portal.Name = zone.id .. "_Portal"
	portal.Anchored = true
	portal.CanCollide = false
	-- Portal sitzt am Rand der vorherigen Zone, also etwas vor der Zonenmitte.
	portal.Size = Vector3.new(8, 12, 2)
	portal.Position = zone.center - Vector3.new(zone.size.X / 2 + 4, -6, 0)
	portal.Color = zone.color
	portal.Material = Enum.Material.ForceField
	portal.Transparency = 0.3
	portal.Parent = portalsFolder

	-- Tag mit ZoneId, damit ZoneLockService das Portal eindeutig zuordnen kann.
	portal:SetAttribute("ZoneId", zone.id)
	portal:SetAttribute("RequiredRebirth", zone.requiredRebirth)

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

	-- Bett-Basis.
	local frame = Instance.new("Part")
	frame.Name = "Frame"
	frame.Anchored = true
	frame.CanCollide = true
	frame.Size = Vector3.new(8, 2, 4)
	frame.Position = worldPos
	frame.Color = bed.color
	frame.Material = Enum.Material.SmoothPlastic
	frame.Parent = model

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
	-- Optisches Pad in der StartZone, das anzeigt, wo der Klick-Spot ist.
	local pad = Instance.new("Part")
	pad.Name = "ClickerHub"
	pad.Anchored = true
	pad.CanCollide = false
	pad.Size = Vector3.new(12, 1, 12)
	pad.Position = startZone.center + Vector3.new(0, 0.6, 20)
	pad.Color = Color3.fromRGB(255, 90, 90)
	pad.Material = Enum.Material.Neon
	pad.Transparency = 0.1
	pad.Parent = parent

	addBillboardLabel(pad, "KLICK-PAD\n(klicke den Knopf auf dem Bildschirm)", Color3.fromRGB(255, 255, 255))
end

local function buildPetEgg(startZone, parent: Instance): BasePart
	-- Pet-Egg in der StartZone. ClickDetector triggert serverseitig openEgg().
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

	local clicker = Instance.new("ClickDetector")
	clicker.Name = "OpenEgg"
	clicker.MaxActivationDistance = 16
	clicker.Parent = egg

	addBillboardLabel(egg, "PET-EI\n(Klicken zum Oeffnen)", Color3.fromRGB(255, 255, 255))
	return egg
end

function WorldBuilder.build()
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
