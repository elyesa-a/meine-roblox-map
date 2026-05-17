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
local EnemyConfig = require(Configs:WaitForChild("EnemyConfig"))
local AuraConfig = require(Configs:WaitForChild("AuraConfig"))

local WorldBuilder = {}

local ROOM_CENTER = Vector3.new(0, 0, 0)
local ROOM_SIZE = Vector3.new(1320, 1, 760)
local ROOM_WALL_HEIGHT = 74
local ROOM_WALL_THICKNESS = 6
local ROOM_CEILING_THICKNESS = 3
local ROOM_FLOOR_Y = -0.55
local START_AREA_CENTER = Vector3.new(0, 0, -165)
local EGG_AREA_CENTER = Vector3.new(540, 0, -210)
local ENEMY_ROW_Z = 205
local BOSS_ROW_Z = 318

local LABEL_DISTANCE_ZONE = 45
local LABEL_DISTANCE_TRAINING = 34
local LABEL_DISTANCE_INSTRUCTION = 24
local LABEL_DISTANCE_MAIN_SIGN = 80
local LABEL_DISTANCE_PORTAL_SIGN = 60

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

local function addBillboardLabel(
	adornee: BasePart,
	text: string,
	color: Color3,
	maxDistance: number?,
	size: UDim2?,
	studsOffset: Vector3?
)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = size or UDim2.fromOffset(220, 60)
	billboard.StudsOffset = studsOffset or Vector3.new(0, 6, 0)
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

local function addPanel(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3): Part
	local panel = makeRoomPart(parent, name, size, position, color, Enum.Material.SmoothPlastic)
	panel.CanCollide = false
	return panel
end

local function addPanelFrame(parent: Instance, center: Vector3, width: number, height: number, color: Color3, orientation: string)
	local thick = 0.35
	local depth = 0.35
	if orientation == "X" then
		for _, y in ipairs({ -1, 1 }) do
			local part = makeRoomPart(parent, "PanelBorder", Vector3.new(width, thick, depth), center + Vector3.new(0, y * height / 2, 0), color, Enum.Material.Neon)
			part.CanCollide = false
			part.Transparency = 0.2
		end
		for _, x in ipairs({ -1, 1 }) do
			local part = makeRoomPart(parent, "PanelBorder", Vector3.new(thick, height, depth), center + Vector3.new(x * width / 2, 0, 0), color, Enum.Material.Neon)
			part.CanCollide = false
			part.Transparency = 0.2
		end
	else
		for _, y in ipairs({ -1, 1 }) do
			local part = makeRoomPart(parent, "PanelBorder", Vector3.new(depth, thick, width), center + Vector3.new(0, y * height / 2, 0), color, Enum.Material.Neon)
			part.CanCollide = false
			part.Transparency = 0.2
		end
		for _, z in ipairs({ -1, 1 }) do
			local part = makeRoomPart(parent, "PanelBorder", Vector3.new(depth, height, thick), center + Vector3.new(0, 0, z * width / 2), color, Enum.Material.Neon)
			part.CanCollide = false
			part.Transparency = 0.2
		end
	end
end

local function addWallTextPanel(
	parent: Instance,
	name: string,
	position: Vector3,
	size: Vector3,
	color: Color3,
	title: string,
	subtitle: string,
	maxDistance: number?,
	orientation: string
)
	local panel = addPanel(parent, name, size, position, Color3.fromRGB(28, 34, 46))
	panel.Transparency = 0.05
	addPanelFrame(parent, position, if orientation == "X" then size.X else size.Z, size.Y, color, orientation)
	addBillboardLabel(
		panel,
		title .. "\n" .. subtitle,
		Color3.fromRGB(255, 255, 255),
		maxDistance or LABEL_DISTANCE_MAIN_SIGN,
		UDim2.fromOffset(360, 100),
		Vector3.new(0, 0, 0)
	)
	return panel
end

local function addCartoonVirus(parent: Instance, center: Vector3, color: Color3, scale: number)
	local core = makeRoomPart(parent, "CartoonVirusCore", Vector3.new(scale, scale, scale), center, color, Enum.Material.Neon)
	core.Shape = Enum.PartType.Ball
	core.CanCollide = false
	core.Transparency = 0.24

	for _, offset in ipairs({
		Vector3.new(scale * 0.75, 0, 0),
		Vector3.new(-scale * 0.75, 0, 0),
		Vector3.new(0, scale * 0.75, 0),
		Vector3.new(0, -scale * 0.75, 0),
		Vector3.new(scale * 0.52, scale * 0.52, 0),
		Vector3.new(-scale * 0.52, scale * 0.52, 0),
		Vector3.new(scale * 0.52, -scale * 0.52, 0),
		Vector3.new(-scale * 0.52, -scale * 0.52, 0),
	}) do
		local spike = makeRoomPart(parent, "CartoonVirusSpike", Vector3.new(scale * 0.25, scale * 0.25, scale * 0.25), center + offset, color, Enum.Material.Neon)
		spike.Shape = Enum.PartType.Ball
		spike.CanCollide = false
		spike.Transparency = 0.18
	end
end

local function addDnaDecoration(parent: Instance, center: Vector3, colorA: Color3, colorB: Color3)
	for i = 1, 8 do
		local y = (i - 4.5) * 2.4
		local x = if i % 2 == 0 then -5 else 5
		local a = makeRoomPart(parent, "DnaNode", Vector3.new(1.4, 1.4, 1.4), center + Vector3.new(x, y, 0), if i % 2 == 0 then colorA else colorB, Enum.Material.Neon)
		a.Shape = Enum.PartType.Ball
		a.CanCollide = false
		a.Transparency = 0.2
		local b = makeRoomPart(parent, "DnaNode", Vector3.new(1.4, 1.4, 1.4), center + Vector3.new(-x, y, 0), if i % 2 == 0 then colorB else colorA, Enum.Material.Neon)
		b.Shape = Enum.PartType.Ball
		b.CanCollide = false
		b.Transparency = 0.2
		local rung = makeRoomPart(parent, "DnaRung", Vector3.new(10, 0.25, 0.25), center + Vector3.new(0, y, 0), Color3.fromRGB(210, 255, 250), Enum.Material.Neon)
		rung.CanCollide = false
		rung.Transparency = 0.35
	end
end

local function addRotatingDnaCore(parent: Instance, center: Vector3)
	local model = Instance.new("Model")
	model.Name = "RotatingDnaCore"
	model.Parent = parent

	local pivot = makeRoomPart(model, "Pivot", Vector3.new(1, 1, 1), center, Color3.fromRGB(120, 255, 230), Enum.Material.Neon)
	pivot.Transparency = 1
	pivot.CanCollide = false
	model.PrimaryPart = pivot

	for i = 1, 10 do
		local y = (i - 5.5) * 3.2
		local angle = i * math.pi * 0.72
		local xA = math.cos(angle) * 8
		local zA = math.sin(angle) * 8
		local xB = -xA
		local zB = -zA
		local colorA = if i % 2 == 0 then Color3.fromRGB(90, 255, 230) else Color3.fromRGB(180, 110, 255)
		local colorB = if i % 2 == 0 then Color3.fromRGB(180, 110, 255) else Color3.fromRGB(90, 255, 230)
		local nodeA = makeRoomPart(model, "DnaOrbA", Vector3.new(2.2, 2.2, 2.2), center + Vector3.new(xA, y, zA), colorA, Enum.Material.Neon)
		nodeA.Shape = Enum.PartType.Ball
		nodeA.CanCollide = false
		local nodeB = makeRoomPart(model, "DnaOrbB", Vector3.new(2.2, 2.2, 2.2), center + Vector3.new(xB, y, zB), colorB, Enum.Material.Neon)
		nodeB.Shape = Enum.PartType.Ball
		nodeB.CanCollide = false
		local rung = makeRoomPart(model, "DnaBridge", Vector3.new(15, 0.32, 0.32), center + Vector3.new(0, y, 0), Color3.fromRGB(225, 255, 250), Enum.Material.Neon)
		rung.CanCollide = false
		rung.CFrame = CFrame.lookAt(rung.Position, nodeA.Position) * CFrame.Angles(0, math.pi / 2, 0)
	end

	addBillboardLabel(pivot, "DNA CORE", Color3.fromRGB(255, 255, 255), 55, UDim2.fromOffset(180, 48), Vector3.new(0, 24, 0))

	task.spawn(function()
		local angle = 0
		while model.Parent do
			angle += math.rad(1.5)
			model:PivotTo(CFrame.new(center) * CFrame.Angles(0, angle, 0))
			task.wait(0.08)
		end
	end)
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

local function addArrowStrip(parent: Instance, center: Vector3, color: Color3)
	local shaft = makeRoomPart(parent, "DirectionArrow", Vector3.new(18, 0.25, 1.1), center, color, Enum.Material.Neon)
	shaft.CanCollide = false
	shaft.Transparency = 0.25
	local headA = makeRoomPart(parent, "DirectionArrowHead", Vector3.new(4, 0.25, 1.1), center + Vector3.new(9, 0, 2.2), color, Enum.Material.Neon)
	headA.CanCollide = false
	headA.Transparency = 0.25
	local headB = makeRoomPart(parent, "DirectionArrowHead", Vector3.new(4, 0.25, 1.1), center + Vector3.new(9, 0, -2.2), color, Enum.Material.Neon)
	headB.CanCollide = false
	headB.Transparency = 0.25
end

local function formatShort(n: number): string
	if n >= 1000000 then
		local text = string.format("%.1fM", n / 1000000)
		return text:gsub("%.0M", "M")
	elseif n >= 1000 then
		local text = string.format("%.1fK", n / 1000)
		return text:gsub("%.0K", "K")
	end
	return tostring(math.floor(n))
end

local function addWallArt(wallArtFolder: Folder)
	for _, child in ipairs(wallArtFolder:GetChildren()) do
		child:Destroy()
	end

	local halfX = ROOM_SIZE.X / 2
	local halfZ = ROOM_SIZE.Z / 2
	local frontZ = ROOM_CENTER.Z - halfZ + 1.2
	local backZ = ROOM_CENTER.Z + halfZ - 1.2
	local leftX = ROOM_CENTER.X - halfX + 1.2
	local rightX = ROOM_CENTER.X + halfX - 1.2

	addWallTextPanel(
		wallArtFolder,
		"MainBrandSign",
		Vector3.new(0, 40, frontZ),
		Vector3.new(250, 38, 0.6),
		Color3.fromRGB(80, 245, 210),
		"VIRUS LAB",
		"TRAIN • EVOLVE • REBIRTH",
		LABEL_DISTANCE_MAIN_SIGN,
		"X"
	)
	addCartoonVirus(wallArtFolder, Vector3.new(-170, 40, frontZ + 1.2), Color3.fromRGB(90, 245, 170), 14)
	addDnaDecoration(wallArtFolder, Vector3.new(170, 40, frontZ + 1.2), Color3.fromRGB(100, 245, 230), Color3.fromRGB(180, 120, 255))
	for _, x in ipairs({ -55, 0, 55 }) do
		addArrowStrip(wallArtFolder, Vector3.new(x, 0.25, START_AREA_CENTER.Z + 58), Color3.fromRGB(120, 245, 225))
	end

	addWallTextPanel(wallArtFolder, "TrainingSectorSign", Vector3.new(leftX, 45, -250), Vector3.new(0.6, 24, 118), Color3.fromRGB(255, 210, 80), "TRAINING SECTOR", "GAIN POWER", LABEL_DISTANCE_MAIN_SIGN, "Z")
	addWallTextPanel(wallArtFolder, "LevelProgressSign", Vector3.new(leftX, 45, -15), Vector3.new(0.6, 24, 118), Color3.fromRGB(120, 220, 255), "LVL 1 -> LVL 100", "NOOB TO PRO", LABEL_DISTANCE_MAIN_SIGN, "Z")
	addWallTextPanel(wallArtFolder, "DnaBoostAreaSign", Vector3.new(leftX, 45, 235), Vector3.new(0.6, 24, 118), Color3.fromRGB(120, 255, 150), "DNA BOOST AREA", "COLLECT • UPGRADE • EVOLVE", LABEL_DISTANCE_MAIN_SIGN, "Z")

	local zoneSigns = {
		{ x = -425, title = "BACTERIA SECTOR", subtitle = "500 POWER • REBIRTH 3", color = Color3.fromRGB(120, 255, 210) },
		{ x = -255, title = "VIRUS CHAMBER", subtitle = "5K POWER • REBIRTH 10", color = Color3.fromRGB(255, 95, 110) },
		{ x = -85, title = "TOXIC FACILITY", subtitle = "25K POWER • REBIRTH 25", color = Color3.fromRGB(160, 255, 80) },
		{ x = 85, title = "FROST LAB", subtitle = "100K POWER • REBIRTH 30", color = Color3.fromRGB(160, 235, 255) },
		{ x = 255, title = "MAGMA REACTOR", subtitle = "500K POWER • REBIRTH 40", color = Color3.fromRGB(255, 120, 60) },
		{ x = 425, title = "GLITCH CORE", subtitle = "2M POWER • REBIRTH 50", color = Color3.fromRGB(255, 90, 220) },
		{ x = 595, title = "FINAL MUTATION", subtitle = "10M POWER • REBIRTH 100", color = Color3.fromRGB(255, 80, 110) },
	}
	for _, sign in ipairs(zoneSigns) do
		addWallTextPanel(
			wallArtFolder,
			sign.title:gsub(" ", "") .. "WallSign",
			Vector3.new(sign.x, 43, backZ),
			Vector3.new(110, 24, 0.6),
			sign.color,
			sign.title,
			sign.subtitle,
			LABEL_DISTANCE_PORTAL_SIGN,
			"X"
		)
	end

	addWallTextPanel(wallArtFolder, "PetEggLabSign", Vector3.new(rightX, 44, -255), Vector3.new(0.6, 24, 108), Color3.fromRGB(100, 230, 255), "PET EGG LAB", "COLLECT VIRUS PETS", LABEL_DISTANCE_MAIN_SIGN, "Z")
	addWallTextPanel(wallArtFolder, "AuraVaultSign", Vector3.new(rightX, 44, -85), Vector3.new(0.6, 24, 108), Color3.fromRGB(220, 120, 255), "AURA VAULT", "EQUIP EPIC BOOSTS", LABEL_DISTANCE_MAIN_SIGN, "Z")
	addWallTextPanel(wallArtFolder, "UpgradeChamberSign", Vector3.new(rightX, 44, 95), Vector3.new(0.6, 24, 108), Color3.fromRGB(120, 255, 140), "UPGRADE CHAMBER", "BECOME UNSTOPPABLE", LABEL_DISTANCE_MAIN_SIGN, "Z")
	addWallTextPanel(wallArtFolder, "BoostShopSign", Vector3.new(rightX, 44, 265), Vector3.new(0.6, 24, 108), Color3.fromRGB(255, 140, 80), "BOOST SHOP", "POWER • DNA • LUCK", LABEL_DISTANCE_MAIN_SIGN, "Z")

	addGlowStrip(wallArtFolder, Vector3.new(0, 0.28, 78), 445, "Z", Color3.fromRGB(90, 225, 245))
	addGlowStrip(wallArtFolder, Vector3.new(0, 0.3, ENEMY_ROW_Z - 42), 980, "X", Color3.fromRGB(110, 245, 190))
	addGlowStrip(wallArtFolder, Vector3.new(0, 0.3, BOSS_ROW_Z - 48), 980, "X", Color3.fromRGB(255, 120, 210))
end

local function buildLabRoom(roomFolder: Folder, wallsFolder: Folder)
	for _, child in ipairs(roomFolder:GetChildren()) do
		child:Destroy()
	end
	for _, child in ipairs(wallsFolder:GetChildren()) do
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
		wallsFolder,
		"LeftWall",
		Vector3.new(wallT, ROOM_WALL_HEIGHT, ROOM_SIZE.Z + wallT * 2),
		Vector3.new(ROOM_CENTER.X - halfX - wallT / 2, wallCenterY, ROOM_CENTER.Z),
		wallColor,
		Enum.Material.SmoothPlastic
	)
	makeRoomPart(
		wallsFolder,
		"RightWall",
		Vector3.new(wallT, ROOM_WALL_HEIGHT, ROOM_SIZE.Z + wallT * 2),
		Vector3.new(ROOM_CENTER.X + halfX + wallT / 2, wallCenterY, ROOM_CENTER.Z),
		wallColor,
		Enum.Material.SmoothPlastic
	)
	makeRoomPart(
		wallsFolder,
		"FrontWall",
		Vector3.new(ROOM_SIZE.X + wallT * 2, ROOM_WALL_HEIGHT, wallT),
		Vector3.new(ROOM_CENTER.X, wallCenterY, ROOM_CENTER.Z - halfZ - wallT / 2),
		wallColor,
		Enum.Material.SmoothPlastic
	)
	makeRoomPart(
		wallsFolder,
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

	for _, z in ipairs({ -250, -95, 60, 215, 330 }) do
		for _, x in ipairs({ -540, -324, -108, 108, 324, 540 }) do
			addCeilingLight(roomFolder, x, z)
		end
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

local function addTrainingSectionWalls(model: Model, bed, worldPos: Vector3, zone)
	local folder = Instance.new("Folder")
	folder.Name = "TransparentSectionWalls"
	folder.Parent = model

	local width = zone.size.X - 12
	local depth = zone.size.Z - 14
	local height = 12
	local y = worldPos.Y + height / 2 + 0.6
	local color = bed.color
	local panelColor = Color3.fromRGB(
		math.floor((color.R * 255 + 170) / 2),
		math.floor((color.G * 255 + 190) / 2),
		math.floor((color.B * 255 + 210) / 2)
	)

	local function glassPanel(name: string, size: Vector3, pos: Vector3)
		local panel = makeRoomPart(folder, name, size, pos, panelColor, Enum.Material.Glass)
		panel.CanCollide = false
		panel.Transparency = 0.72
		return panel
	end

	glassPanel("LeftGlassWall", Vector3.new(0.6, height, depth), worldPos + Vector3.new(-width / 2, y, 0))
	glassPanel("RightGlassWall", Vector3.new(0.6, height, depth), worldPos + Vector3.new(width / 2, y, 0))
	glassPanel("BackGlassWall", Vector3.new(width, height, 0.6), worldPos + Vector3.new(0, y, depth / 2))
	glassPanel("FrontLeftGlassWall", Vector3.new(width * 0.28, height, 0.6), worldPos + Vector3.new(-width * 0.36, y, -depth / 2))
	glassPanel("FrontRightGlassWall", Vector3.new(width * 0.28, height, 0.6), worldPos + Vector3.new(width * 0.36, y, -depth / 2))

	local borderY = worldPos.Y + 0.9
	addGlowStrip(folder, worldPos + Vector3.new(0, borderY, depth / 2), width, "X", color)
	addGlowStrip(folder, worldPos + Vector3.new(-width / 2, borderY, 0), depth, "Z", color)
	addGlowStrip(folder, worldPos + Vector3.new(width / 2, borderY, 0), depth, "Z", color)
	addGlowStrip(folder, worldPos + Vector3.new(-width * 0.36, borderY, -depth / 2), width * 0.28, "X", color)
	addGlowStrip(folder, worldPos + Vector3.new(width * 0.36, borderY, -depth / 2), width * 0.28, "X", color)

	local signTextByBed = {
		StandardBed = "BASIC TRAINING",
		InfectionBed = "INFECTION TRAINING",
		MutationBed = "MUTATION TRAINING",
		QuarantineBed = "QUARANTINE TRAINING",
		GlitchBed = "GLITCH TRAINING",
		EndgameBed = "ENDGAME TRAINING",
	}
	local sign = makeRoomPart(
		folder,
		"EntranceSign",
		Vector3.new(22, 5, 0.6),
		worldPos + Vector3.new(0, 7, -depth / 2 - 1.6),
		Color3.fromRGB(34, 40, 52),
		Enum.Material.SmoothPlastic
	)
	sign.CanCollide = false
	addBillboardLabel(sign, signTextByBed[bed.id] or "TRAINING", Color3.fromRGB(255, 255, 255), LABEL_DISTANCE_TRAINING)

	if bed.id == "GlitchBed" then
		for i, x in ipairs({ -28, -12, 14, 32 }) do
			local block = makeRoomPart(folder, "GlitchPanel" .. tostring(i), Vector3.new(5, 5, 0.5), worldPos + Vector3.new(x, 9 + (i % 2) * 4, depth / 2 + 0.4), color, Enum.Material.Neon)
			block.CanCollide = false
			block.Transparency = 0.35
		end
	end
end

local function getZoneColorById(zoneId: string): Color3
	local zone = ZoneConfig.getById(zoneId)
	return if zone then zone.color else Color3.fromRGB(120, 220, 255)
end

type EnemyGroupDisplay = {
	title: string,
	subtitle: string,
	lines: { string },
	bottom: string,
	symbol: string,
}

local ENEMY_GROUP_DISPLAYS: { [string]: EnemyGroupDisplay } = {
	StartEnemies = {
		title = "NANO SPORE VIRUS",
		subtitle = "COMBAT POWER: 80 - 1K",
		lines = {
			"Tiny Antibody - 80 Power",
			"Lab Germ - 150 Power",
			"Mini Cell Guard - 300 Power",
			"Weak Cure Bot - 700 Power",
		},
		bottom = "Defeat enemies to earn DNA",
		symbol = "Nano",
	},
	HospitalEnemies = {
		title = "MEDI-MITE STRAIN",
		subtitle = "COMBAT POWER: 1.5K - 15K",
		lines = {
			"Antibody Soldier - 1.5K Power",
			"White Cell Guard - 3K Power",
			"Cleanse Drone - 7K Power",
			"Hospital Defender - 15K Power",
		},
		bottom = "Stronger enemies give more DNA",
		symbol = "Medi",
	},
	MutationEnemies = {
		title = "MUTAGEN-X VIRUS",
		subtitle = "COMBAT POWER: 30K - 300K",
		lines = {
			"DNA Mutant - 30K Power",
			"Mutation Beast - 70K Power",
			"Toxic Cell - 150K Power",
			"DNA Guardian - 300K Power",
		},
		bottom = "Mutate your power and fight stronger",
		symbol = "Mutation",
	},
	QuarantineEnemies = {
		title = "LOCKDOWN STRAIN",
		subtitle = "COMBAT POWER: 700K - 6M",
		lines = {
			"Quarantine Bot - 700K Power",
			"Red Alert Guard - 1.5M Power",
			"Sterile Titan - 3M Power",
			"Lockdown Boss - 6M Power",
		},
		bottom = "Hold E near bosses to start fights",
		symbol = "Lockdown",
	},
	GlitchEnemies = {
		title = "CYBER PLAGUE VIRUS",
		subtitle = "COMBAT POWER: 15M - 60M",
		lines = {
			"Glitch Hunter - 15M Power",
			"Firewall Beast - 30M Power",
			"Anti-Virus Core - 60M Power",
		},
		bottom = "Glitch enemies drop high DNA",
		symbol = "Glitch",
	},
	EndgameEnemies = {
		title = "OMEGA CORE VIRUS",
		subtitle = "COMBAT POWER: 250M+",
		lines = {
			"Omega Immune Boss - 250M Power",
		},
		bottom = "Final boss challenge",
		symbol = "Omega",
	},
}

local function addEnemyGroupSymbol(parent: Instance, symbol: string, center: Vector3, color: Color3)
	if symbol == "Medi" then
		addCartoonVirus(parent, center + Vector3.new(-5, 0, 0), color, 4.8)
		local crossColor = Color3.fromRGB(235, 255, 245)
		local barA = makeRoomPart(parent, "MedicalCross", Vector3.new(2.2, 12, 0.4), center + Vector3.new(8, 0, 0), crossColor, Enum.Material.Neon)
		barA.CanCollide = false
		barA.Transparency = 0.18
		local barB = makeRoomPart(parent, "MedicalCross", Vector3.new(10, 2.2, 0.4), center + Vector3.new(8, 0, 0), crossColor, Enum.Material.Neon)
		barB.CanCollide = false
		barB.Transparency = 0.18
	elseif symbol == "Mutation" then
		addDnaDecoration(parent, center, Color3.fromRGB(230, 120, 255), Color3.fromRGB(120, 255, 170))
		for _, offset in ipairs({ -11, 11 }) do
			local arrow = makeRoomPart(parent, "MutationArrow", Vector3.new(8, 0.45, 0.45), center + Vector3.new(offset, 12, 0), color, Enum.Material.Neon)
			arrow.CanCollide = false
			arrow.Transparency = 0.28
		end
	elseif symbol == "Lockdown" then
		local shield = makeRoomPart(parent, "ShieldIcon", Vector3.new(14, 14, 0.45), center, Color3.fromRGB(42, 45, 55), Enum.Material.SmoothPlastic)
		shield.CanCollide = false
		for i, y in ipairs({ -5, 0, 5 }) do
			local stripe = makeRoomPart(parent, "WarningStripe" .. tostring(i), Vector3.new(14, 1.1, 0.55), center + Vector3.new(0, y, -0.05), color, Enum.Material.Neon)
			stripe.CanCollide = false
			stripe.Transparency = 0.25
		end
	elseif symbol == "Glitch" then
		for i, offset in ipairs({
			Vector3.new(-9, 5, 0),
			Vector3.new(-2, -4, 0),
			Vector3.new(6, 7, 0),
			Vector3.new(11, -6, 0),
			Vector3.new(0, 2, 0),
		}) do
			local square = makeRoomPart(parent, "GlitchPixel" .. tostring(i), Vector3.new(5, 5, 0.45), center + offset, color, Enum.Material.Neon)
			square.CanCollide = false
			square.Transparency = 0.22 + (i % 2) * 0.18
		end
	elseif symbol == "Omega" then
		local core = makeRoomPart(parent, "OmegaCoreIcon", Vector3.new(9, 9, 9), center, Color3.fromRGB(255, 70, 90), Enum.Material.Neon)
		core.Shape = Enum.PartType.Ball
		core.CanCollide = false
		core.Transparency = 0.2
		for _, angle in ipairs({ 0, 45, 90, 135 }) do
			local ray = makeRoomPart(parent, "CoreRay", Vector3.new(19, 0.75, 0.45), center, Color3.fromRGB(255, 215, 90), Enum.Material.Neon)
			ray.Orientation = Vector3.new(0, 0, angle)
			ray.CanCollide = false
			ray.Transparency = 0.3
		end
	else
		addCartoonVirus(parent, center, color, 5.4)
		for i, offset in ipairs({ -11, -5, 5, 11 }) do
			local dot = makeRoomPart(parent, "DnaDot" .. tostring(i), Vector3.new(1.7, 1.7, 1.7), center + Vector3.new(offset, -12, 0), Color3.fromRGB(190, 255, 250), Enum.Material.Neon)
			dot.Shape = Enum.PartType.Ball
			dot.CanCollide = false
			dot.Transparency = 0.25
		end
	end
end

local function addEnemyGroupWallDisplay(parent: Instance, areaName: string, center: Vector3, color: Color3)
	local display = ENEMY_GROUP_DISPLAYS[areaName]
	if not display then
		return
	end

	local panelCenter = center + Vector3.new(0, 20, 48)
	local panel = addPanel(parent, "EnemyGroupWallDisplay", Vector3.new(136, 36, 0.8), panelCenter, Color3.fromRGB(22, 27, 36))
	panel.Transparency = 0.02
	addPanelFrame(parent, panelCenter, 136, 36, color, "X")

	local textLines = {
		display.title,
		display.subtitle,
		table.concat(display.lines, "\n"),
		display.bottom,
	}
	addBillboardLabel(
		panel,
		table.concat(textLines, "\n"),
		Color3.fromRGB(255, 255, 255),
		68,
		UDim2.fromOffset(520, 250),
		Vector3.new(0, 0, 0)
	)
	addEnemyGroupSymbol(parent, display.symbol, panelCenter + Vector3.new(-54, 4, 0.7), color)
end

local function buildEnemyModel(parent: Instance, def, position: Vector3, color: Color3)
	local model = Instance.new("Model")
	model.Name = def.Id
	model.Parent = parent
	model:SetAttribute("EnemyId", def.Id)
	model:SetAttribute("AreaName", def.AreaName)
	model:SetAttribute("IsBoss", def.IsBoss)

	local scale = if def.IsBoss then 1.8 else 1
	local root = makeRoomPart(
		model,
		"EnemyCore",
		Vector3.new(5 * scale, 5 * scale, 5 * scale),
		position + Vector3.new(0, 4 * scale, 0),
		color,
		Enum.Material.Neon
	)
	root.Shape = Enum.PartType.Ball
	root.CanCollide = false
	root.Transparency = if def.IsBoss then 0.14 else 0.24
	model.PrimaryPart = root

	for _, offset in ipairs({
		Vector3.new(4, 0, 0),
		Vector3.new(-4, 0, 0),
		Vector3.new(0, 4, 0),
		Vector3.new(0, -4, 0),
		Vector3.new(2.8, 2.8, 0),
		Vector3.new(-2.8, 2.8, 0),
		Vector3.new(2.8, -2.8, 0),
		Vector3.new(-2.8, -2.8, 0),
	}) do
		local spike = makeRoomPart(model, "VirusSpike", Vector3.new(1.1 * scale, 1.1 * scale, 1.1 * scale), root.Position + offset * scale, color, Enum.Material.Neon)
		spike.Shape = Enum.PartType.Ball
		spike.CanCollide = false
		spike.Transparency = 0.2
	end

	local barBack = makeRoomPart(
		model,
		"HealthBarBack",
		Vector3.new(14 * scale, 0.8, 0.45),
		root.Position + Vector3.new(0, 7.2 * scale, 0),
		Color3.fromRGB(18, 22, 28),
		Enum.Material.SmoothPlastic
	)
	barBack.CanCollide = false
	local barFill = makeRoomPart(
		model,
		"HealthBarFill",
		Vector3.new(13.2 * scale, 0.45, 0.65),
		barBack.Position + Vector3.new(0, 0.02, -0.05),
		Color3.fromRGB(95, 255, 125),
		Enum.Material.Neon
	)
	barFill.CanCollide = false
	barFill.Transparency = 0.12
	barFill:SetAttribute("MaxWidth", 13.2 * scale)
	barFill:SetAttribute("FullCenterX", barFill.Position.X)

	local clicker = Instance.new("ClickDetector")
	clicker.Name = "AttackClick"
	clicker.MaxActivationDistance = EnemyConfig.AttackDistance
	clicker.Parent = root

	if def.IsBoss then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "StartBossFight"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 1
		prompt.ActionText = "Start Fight"
		prompt.ObjectText = def.DisplayName
		prompt.MaxActivationDistance = EnemyConfig.BossPromptDistance
		prompt.RequiresLineOfSight = false
		prompt.Parent = root
	end

	addBillboardLabel(
		root,
		string.format("%s\nHP: %s\nNeed %s Power\nReward %s DNA", def.DisplayName, tostring(def.MaxHealth), tostring(def.RequiredPower), tostring(def.DNAReward)),
		Color3.fromRGB(255, 255, 255),
		if def.IsBoss then 50 else 35,
		UDim2.fromOffset(if def.IsBoss then 280 else 230, if def.IsBoss then 100 else 82),
		Vector3.new(0, 8 * scale, 0)
	)
end

local function buildEnemyArea(parent: Instance, areaName: string, folderName: string, displayName: string, zoneId: string, center: Vector3)
	local defs = EnemyConfig.getByArea(areaName)
	if #defs == 0 then
		return
	end

	local color = getZoneColorById(zoneId)
	local area = Instance.new("Folder")
	area.Name = folderName
	area:SetAttribute("AreaName", areaName)
	area.Parent = parent

	local pad = makeRoomPart(area, "AreaPad", Vector3.new(138, 0.45, 64), center + Vector3.new(0, 0.12, 0), Color3.fromRGB(38, 48, 60), Enum.Material.SmoothPlastic)
	pad.CanCollide = true
	local halfX = pad.Size.X / 2
	local halfZ = pad.Size.Z / 2
	local stripY = pad.Position.Y + 0.45
	addGlowStrip(area, Vector3.new(center.X, stripY, center.Z - halfZ), pad.Size.X, "X", color)
	addGlowStrip(area, Vector3.new(center.X, stripY, center.Z + halfZ), pad.Size.X, "X", color)
	addGlowStrip(area, Vector3.new(center.X - halfX, stripY, center.Z), pad.Size.Z, "Z", color)
	addGlowStrip(area, Vector3.new(center.X + halfX, stripY, center.Z), pad.Size.Z, "Z", color)

	local sign = makeRoomPart(area, "AreaSign", Vector3.new(34, 6, 0.6), center + Vector3.new(0, 7, -halfZ - 2), Color3.fromRGB(32, 38, 50), Enum.Material.SmoothPlastic)
	sign.CanCollide = false
	addBillboardLabel(sign, displayName .. "\nFight for DNA", Color3.fromRGB(255, 255, 255), 45)
	addEnemyGroupWallDisplay(area, areaName, center, color)

	local spacing = 32
	local startX = center.X - spacing * (#defs - 1) / 2
	for i, def in ipairs(defs) do
		buildEnemyModel(area, def, Vector3.new(startX + spacing * (i - 1), center.Y, center.Z + 2), color)
	end
end

local function buildBossField(parent: Instance, areaName: string, folderName: string, zoneId: string, center: Vector3)
	local defs = EnemyConfig.getByArea(areaName)
	local def = defs[1]
	if not def then
		return
	end

	local color = getZoneColorById(zoneId)
	local field = Instance.new("Folder")
	field.Name = folderName
	field:SetAttribute("AreaName", areaName)
	field.Parent = parent

	local pad = makeRoomPart(field, "BossPad", Vector3.new(112, 0.55, 58), center + Vector3.new(0, 0.16, 0), Color3.fromRGB(42, 42, 56), Enum.Material.SmoothPlastic)
	pad.CanCollide = true
	local halfX = pad.Size.X / 2
	local halfZ = pad.Size.Z / 2
	local stripY = pad.Position.Y + 0.5
	addGlowStrip(field, Vector3.new(center.X, stripY, center.Z - halfZ), pad.Size.X * 0.32, "X", color)
	addGlowStrip(field, Vector3.new(center.X, stripY, center.Z + halfZ), pad.Size.X, "X", color)
	addGlowStrip(field, Vector3.new(center.X - halfX, stripY, center.Z), pad.Size.Z, "Z", color)
	addGlowStrip(field, Vector3.new(center.X + halfX, stripY, center.Z), pad.Size.Z, "Z", color)

	for _, dx in ipairs({ -halfX + 8, halfX - 8 }) do
		local tower = makeRoomPart(field, "BossArenaTower", Vector3.new(5, 22, 5), center + Vector3.new(dx, 11, halfZ - 5), Color3.fromRGB(30, 32, 42), Enum.Material.Metal)
		tower.CanCollide = true
		local lamp = makeRoomPart(field, "BossArenaLamp", Vector3.new(5.6, 1.5, 5.6), tower.Position + Vector3.new(0, 11.5, 0), color, Enum.Material.Neon)
		lamp.CanCollide = false
		lamp.Transparency = 0.16
		local light = Instance.new("PointLight")
		light.Color = color
		light.Brightness = 0.75
		light.Range = 18
		light.Parent = lamp
	end

	local sign = makeRoomPart(field, "BossSign", Vector3.new(42, 7, 0.6), center + Vector3.new(0, 9, -halfZ - 2), Color3.fromRGB(32, 38, 50), Enum.Material.SmoothPlastic)
	sign.CanCollide = false
	addBillboardLabel(
		sign,
		string.format("%s\nNeed %s Power\nReward %s DNA", def.DisplayName, tostring(def.RequiredPower), tostring(def.DNAReward)),
		Color3.fromRGB(255, 255, 255),
		50,
		UDim2.fromOffset(290, 92)
	)

	buildEnemyModel(field, def, center + Vector3.new(0, 0, 8), color)
end

local function buildEnemyAndBossAreas(enemyFolder: Folder, bossFolder: Folder)
	for _, child in ipairs(enemyFolder:GetChildren()) do
		child:Destroy()
	end
	for _, child in ipairs(bossFolder:GetChildren()) do
		child:Destroy()
	end

	local areas = {
		{ area = "StartEnemies", folder = "StartEnemyArea", title = "LAB ENTRY ENEMIES", zoneId = "StartZone" },
		{ area = "HospitalEnemies", folder = "HospitalEnemyArea", title = "BACTERIA ENEMIES", zoneId = "HospitalZone" },
		{ area = "MutationEnemies", folder = "MutationEnemyArea", title = "VIRUS ENEMIES", zoneId = "MutationLabZone" },
		{ area = "QuarantineEnemies", folder = "QuarantineEnemyArea", title = "TOXIC ENEMIES", zoneId = "QuarantineZone" },
		{ area = "GlitchEnemies", folder = "GlitchEnemyArea", title = "GLITCH ENEMIES", zoneId = "GlitchZone" },
		{ area = "EndgameEnemies", folder = "EndgameEnemyArea", title = "FINAL ENEMIES", zoneId = "EndgameZone" },
	}
	for _, area in ipairs(areas) do
		local zone = ZoneConfig.getById(area.zoneId)
		if zone then
			buildEnemyArea(enemyFolder, area.area, area.folder, area.title, area.zoneId, Vector3.new(zone.center.X, 0, ENEMY_ROW_Z))
		end
	end

	local bossFields = {
		{ area = "StartBoss", folder = "BacteriaBossField", zoneId = "HospitalZone" },
		{ area = "HospitalBoss", folder = "VirusBossField", zoneId = "MutationLabZone" },
		{ area = "QuarantineBoss", folder = "ToxicBossField", zoneId = "QuarantineZone" },
		{ area = "FrostBoss", folder = "FrostBossField", zoneId = "FrostLabZone" },
		{ area = "MagmaBoss", folder = "MagmaBossField", zoneId = "MagmaReactorZone" },
		{ area = "GlitchBoss", folder = "GlitchBossField", zoneId = "GlitchZone" },
		{ area = "EndgameBoss", folder = "EndgameBossField", zoneId = "EndgameZone" },
	}
	for _, boss in ipairs(bossFields) do
		local zone = ZoneConfig.getById(boss.zoneId)
		if zone then
			buildBossField(bossFolder, boss.area, boss.folder, boss.zoneId, Vector3.new(zone.center.X, 0, BOSS_ROW_Z))
		end
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
	portal:SetAttribute("RequiredPower", zone.requiredPower)

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
		string.format("NEXT: %s\nREQUIRED: %s Power • Rebirth %d", zone.displayName, formatShort(zone.requiredPower), zone.requiredRebirth),
		Color3.fromRGB(255, 255, 255),
		LABEL_DISTANCE_ZONE
	)

	local gateFolder = Instance.new("Folder")
	gateFolder.Name = zone.id .. "_GateFrame"
	gateFolder.Parent = portalsFolder
	for _, dx in ipairs({ -8, 8 }) do
		local pillar = makeRoomPart(gateFolder, "GatePillar", Vector3.new(2.2, 19, 2.2), portal.Position + Vector3.new(dx, 2.5, 0), Color3.fromRGB(28, 32, 40), Enum.Material.Metal)
		pillar.CanCollide = true
		local glow = makeRoomPart(gateFolder, "GatePillarGlow", Vector3.new(1, 16, 1), pillar.Position, zone.color, Enum.Material.Neon)
		glow.CanCollide = false
		glow.Transparency = 0.35
	end
	local top = makeRoomPart(gateFolder, "GateHeader", Vector3.new(21, 2.2, 2.2), portal.Position + Vector3.new(0, 13.2, 0), zone.color, Enum.Material.Neon)
	top.CanCollide = false
	top.Transparency = 0.18
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
		string.format("%s\n+%d Power/s", bed.id, bed.powerPerSecond),
		Color3.fromRGB(255, 255, 255),
		LABEL_DISTANCE_TRAINING
	)

	addTrainingDecor(model, bed, worldPos)
	addTrainingSectionWalls(model, bed, worldPos, zone)
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

	addBillboardLabel(pad, "CLICK PAD\nUse the button below", Color3.fromRGB(255, 255, 255), LABEL_DISTANCE_INSTRUCTION)
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

local function addWarningLight(parent: Instance, pos: Vector3, color: Color3)
	local pole = makeRoomPart(parent, "WarningLightPole", Vector3.new(1.2, 7, 1.2), pos + Vector3.new(0, 3.5, 0), Color3.fromRGB(30, 32, 38), Enum.Material.Metal)
	pole.CanCollide = false
	local lamp = makeRoomPart(parent, "WarningLight", Vector3.new(3, 1.4, 3), pos + Vector3.new(0, 7.4, 0), color, Enum.Material.Neon)
	lamp.Shape = Enum.PartType.Ball
	lamp.CanCollide = false
	lamp.Transparency = 0.18
	local light = Instance.new("PointLight")
	light.Brightness = 0.65
	light.Range = 14
	light.Color = color
	light.Parent = lamp
end

local function addBioBarrel(parent: Instance, pos: Vector3, color: Color3)
	local barrel = makeRoomPart(parent, "BiohazardBarrel", Vector3.new(5, 7, 5), pos + Vector3.new(0, 3.5, 0), Color3.fromRGB(42, 48, 46), Enum.Material.Metal)
	barrel.Shape = Enum.PartType.Cylinder
	barrel.CanCollide = true
	local band = makeRoomPart(parent, "BarrelBioBand", Vector3.new(5.3, 0.6, 5.3), pos + Vector3.new(0, 5.5, 0), color, Enum.Material.Neon)
	band.Shape = Enum.PartType.Cylinder
	band.CanCollide = false
	band.Transparency = 0.25
	addBillboardLabel(barrel, "BIO\nSAMPLE", Color3.fromRGB(255, 255, 255), 24, UDim2.fromOffset(90, 50), Vector3.new(0, 5, 0))
end

local function addLabTank(parent: Instance, pos: Vector3, color: Color3, labelText: string)
	local base = makeRoomPart(parent, "TankBase", Vector3.new(13, 1.2, 13), pos + Vector3.new(0, 0.7, 0), Color3.fromRGB(32, 36, 44), Enum.Material.Metal)
	base.CanCollide = true
	local glass = makeRoomPart(parent, "MutationTank", Vector3.new(8, 18, 8), pos + Vector3.new(0, 10, 0), color, Enum.Material.Glass)
	glass.Shape = Enum.PartType.Cylinder
	glass.Transparency = 0.48
	glass.CanCollide = false
	local core = makeRoomPart(parent, "FloatingSample", Vector3.new(3.8, 3.8, 3.8), pos + Vector3.new(0, 10, 0), color, Enum.Material.Neon)
	core.Shape = Enum.PartType.Ball
	core.CanCollide = false
	core.Transparency = 0.2
	local att = Instance.new("Attachment")
	att.Parent = core
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Rate = 5
	emitter.Speed = NumberRange.new(0.5, 1.4)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.45, 0.08)
	emitter.Transparency = NumberSequence.new(0.3, 1)
	emitter.LightEmission = 0.35
	emitter.Parent = att
	addBillboardLabel(glass, labelText, Color3.fromRGB(255, 255, 255), 32, UDim2.fromOffset(170, 56), Vector3.new(0, 12, 0))
end

local function addToxicPuddle(parent: Instance, pos: Vector3, color: Color3)
	local puddle = makeRoomPart(parent, "ToxicPuddle", Vector3.new(18, 0.18, 10), pos + Vector3.new(0, 0.14, 0), color, Enum.Material.Neon)
	puddle.Shape = Enum.PartType.Cylinder
	puddle.CanCollide = false
	puddle.Transparency = 0.46
	local att = Instance.new("Attachment")
	att.Parent = puddle
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(color)
	mist.Lifetime = NumberRange.new(1.2, 2)
	mist.Rate = 4
	mist.Speed = NumberRange.new(0.4, 1.1)
	mist.SpreadAngle = Vector2.new(80, 80)
	mist.Size = NumberSequence.new(1.7, 0.25)
	mist.Transparency = NumberSequence.new(0.62, 1)
	mist.Parent = att
end

local function addPipeRun(parent: Instance, startPos: Vector3, length: number, color: Color3)
	local pipe = makeRoomPart(parent, "WallPipe", Vector3.new(length, 2, 2), startPos, Color3.fromRGB(28, 32, 38), Enum.Material.Metal)
	pipe.CanCollide = false
	local valve = makeRoomPart(parent, "ValveWheel", Vector3.new(5, 5, 0.5), startPos + Vector3.new(length * 0.22, 0, 1.2), color, Enum.Material.Neon)
	valve.Shape = Enum.PartType.Cylinder
	valve.CanCollide = false
	valve.Transparency = 0.35
end

local function addHubStation(parent: Instance, name: string, pos: Vector3, color: Color3, title: string, subtitle: string)
	local platform = makeRoomPart(parent, name .. "Platform", Vector3.new(62, 0.5, 34), pos + Vector3.new(0, 0.2, 0), Color3.fromRGB(34, 42, 52), Enum.Material.SmoothPlastic)
	platform.CanCollide = true
	addGlowStrip(parent, pos + Vector3.new(0, 0.65, -17), 62, "X", color)
	addGlowStrip(parent, pos + Vector3.new(0, 0.65, 17), 62, "X", color)
	local terminal = makeRoomPart(parent, name .. "Terminal", Vector3.new(18, 11, 4), pos + Vector3.new(0, 5.8, 4), Color3.fromRGB(28, 32, 42), Enum.Material.Metal)
	terminal.CanCollide = true
	local screen = makeRoomPart(parent, name .. "Screen", Vector3.new(15, 7, 0.5), terminal.Position + Vector3.new(0, 1.4, -2.25), color, Enum.Material.Neon)
	screen.CanCollide = false
	screen.Transparency = 0.18
	addBillboardLabel(screen, title .. "\n" .. subtitle, Color3.fromRGB(255, 255, 255), 42, UDim2.fromOffset(190, 68), Vector3.new(0, 3.8, 0))
end

local function addAuraShowcase(parent: Instance)
	local baseCenter = EGG_AREA_CENTER + Vector3.new(0, 0, 76)
	local platform = makeRoomPart(parent, "AuraVaultPlatform", Vector3.new(160, 0.5, 38), baseCenter + Vector3.new(0, 0.25, 0), Color3.fromRGB(34, 34, 52), Enum.Material.SmoothPlastic)
	platform.CanCollide = true
	addGlowStrip(parent, baseCenter + Vector3.new(0, 0.75, -19), 160, "X", Color3.fromRGB(210, 110, 255))
	addGlowStrip(parent, baseCenter + Vector3.new(0, 0.75, 19), 160, "X", Color3.fromRGB(210, 110, 255))
	addBillboardLabel(platform, "AURA VAULT\nPREVIEW AURAS", Color3.fromRGB(255, 255, 255), 48, UDim2.fromOffset(220, 58), Vector3.new(0, 8, 0))

	local startX = baseCenter.X - 60
	for i, aura in ipairs(AuraConfig.Auras) do
		local x = startX + (i - 1) * 20
		local stand = makeRoomPart(parent, "AuraDisplayStand", Vector3.new(8, 1.2, 8), Vector3.new(x, 1, baseCenter.Z), Color3.fromRGB(28, 30, 42), Enum.Material.Metal)
		stand.CanCollide = true
		local orb = makeRoomPart(parent, "AuraDisplayOrb", Vector3.new(5, 5, 5), Vector3.new(x, 6.2, baseCenter.Z), aura.color, Enum.Material.Neon)
		orb.Shape = Enum.PartType.Ball
		orb.CanCollide = false
		orb.Transparency = 0.18
		local att = Instance.new("Attachment")
		att.Parent = orb
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = aura.colorSequence or ColorSequence.new(aura.color)
		emitter.Lifetime = NumberRange.new(0.6, 1.1)
		emitter.Rate = if aura.id == "Rainbow" or aura.id == "Glitch" then 9 else 5
		emitter.Speed = NumberRange.new(0.8, 1.8)
		emitter.SpreadAngle = Vector2.new(130, 130)
		emitter.Size = NumberSequence.new(0.35, 0.06)
		emitter.Transparency = NumberSequence.new(0.15, 1)
		emitter.LightEmission = 0.55
		emitter.Parent = att
		addBillboardLabel(orb, aura.displayName, Color3.fromRGB(255, 255, 255), 22, UDim2.fromOffset(120, 34), Vector3.new(0, 4, 0))
	end
end

local function buildLabDecor(decorFolder: Folder)
	for _, child in ipairs(decorFolder:GetChildren()) do
		child:Destroy()
	end

	addRotatingDnaCore(decorFolder, START_AREA_CENTER + Vector3.new(0, 22, 0))
	addHubStation(decorFolder, "DailyQuest", START_AREA_CENTER + Vector3.new(-86, 0, 20), Color3.fromRGB(255, 190, 75), "DAILY QUESTS", "COMPLETE LAB TASKS")
	addHubStation(decorFolder, "Titles", START_AREA_CENTER + Vector3.new(-86, 0, -28), Color3.fromRGB(255, 225, 95), "TITLE TERMINAL", "SHOW YOUR MUTATION")
	addHubStation(decorFolder, "LuckyWheel", START_AREA_CENTER + Vector3.new(86, 0, -28), Color3.fromRGB(95, 160, 255), "LUCKY WHEEL", "SPIN FOR REWARDS")
	addHubStation(decorFolder, "Rebirth", START_AREA_CENTER + Vector3.new(86, 0, 20), Color3.fromRGB(255, 90, 120), "EVOLUTION CORE", "REBIRTH TO EVOLVE")
	addAuraShowcase(decorFolder)

	for _, x in ipairs({ -450, -245, -40, 165, 370, 560 }) do
		addPipeRun(decorFolder, Vector3.new(x, 19, -350), 84, Color3.fromRGB(95, 245, 210))
	end

	local zoneDecor = {
		{ center = Vector3.new(-595, 0, 72), color = Color3.fromRGB(120, 205, 255), label = "LAB SAMPLE", kind = "Clean" },
		{ center = Vector3.new(-425, 0, 72), color = Color3.fromRGB(95, 255, 145), label = "BACTERIA SECTOR", kind = "Bacteria" },
		{ center = Vector3.new(-255, 0, 72), color = Color3.fromRGB(255, 90, 110), label = "VIRUS CHAMBER", kind = "Virus" },
		{ center = Vector3.new(-85, 0, 72), color = Color3.fromRGB(150, 255, 70), label = "TOXIC FACILITY", kind = "Toxic" },
		{ center = Vector3.new(85, 0, 72), color = Color3.fromRGB(160, 235, 255), label = "FROST LAB", kind = "Frost" },
		{ center = Vector3.new(255, 0, 72), color = Color3.fromRGB(255, 120, 60), label = "MAGMA REACTOR", kind = "Magma" },
		{ center = Vector3.new(425, 0, 72), color = Color3.fromRGB(95, 220, 255), label = "GLITCH CORE", kind = "Glitch" },
		{ center = Vector3.new(595, 0, 72), color = Color3.fromRGB(255, 90, 90), label = "FINAL CORE", kind = "Final" },
	}
	for _, zone in ipairs(zoneDecor) do
		addLabTank(decorFolder, zone.center + Vector3.new(-38, 0, 0), zone.color, zone.label)
		addBioBarrel(decorFolder, zone.center + Vector3.new(44, 0, -8), zone.color)
		addWarningLight(decorFolder, zone.center + Vector3.new(58, 0, 26), zone.color)
		if zone.kind == "Toxic" or zone.kind == "Bacteria" or zone.kind == "Virus" then
			addToxicPuddle(decorFolder, zone.center + Vector3.new(0, 0, 28), zone.color)
		end
		if zone.kind == "Frost" then
			addToxicPuddle(decorFolder, zone.center + Vector3.new(0, 0, 28), Color3.fromRGB(205, 245, 255))
		end
		if zone.kind == "Magma" then
			addToxicPuddle(decorFolder, zone.center + Vector3.new(0, 0, 28), Color3.fromRGB(255, 85, 35))
		end
		if zone.kind == "Glitch" then
			for i, offset in ipairs({ -16, -4, 12, 26 }) do
				local pixel = makeRoomPart(decorFolder, "FloatingGlitchPixel" .. tostring(i), Vector3.new(5, 5, 0.8), zone.center + Vector3.new(offset, 15 + i * 2, 38), zone.color, Enum.Material.Neon)
				pixel.CanCollide = false
				pixel.Transparency = 0.32
			end
		end
		if zone.kind == "Final" then
			addCartoonVirus(decorFolder, zone.center + Vector3.new(0, 18, 38), Color3.fromRGB(255, 90, 110), 9)
		end
	end
end

function WorldBuilder.build()
	applyLighting()

	local mapFolder = makeFolder("Map", Workspace)
	local wallsFolder = makeFolder("Walls", mapFolder)
	local wallArtFolder = makeFolder("WallArt", mapFolder)
	local roomFolder = makeFolder("LabRoom", Workspace)
	local zonesFolder = makeFolder("Zones", Workspace)
	local portalsFolder = makeFolder("Portals", Workspace)
	local bedsFolder = makeFolder("TrainingBeds", Workspace)
	local eggAreaFolder = makeFolder("EggCatchArea", Workspace)
	local enemyFolder = makeFolder("EnemyAreas", Workspace)
	local bossFolder = makeFolder("BossFields", Workspace)
	local decorFolder = makeFolder("LabDecor", Workspace)

	buildLabRoom(roomFolder, wallsFolder)
	addWallArt(wallArtFolder)
	buildEggCatchArea(eggAreaFolder)
	buildLabDecor(decorFolder)

	for _, zone in ipairs(ZoneConfig) do
		buildZone(zone, zonesFolder)
		buildPortal(zone, portalsFolder)
	end

	for _, bed in ipairs(TrainingBedConfig) do
		buildBed(bed, bedsFolder)
	end
	buildEnemyAndBossAreas(enemyFolder, bossFolder)

	local startZone = ZoneConfig.getById("StartZone")
	if startZone then
		buildClickerHub(startZone, Workspace)
		WorldBuilder.PetEgg = buildPetEgg(startZone, eggAreaFolder)
	end

	print("[WorldBuilder] Welt erzeugt.")
end

return WorldBuilder
