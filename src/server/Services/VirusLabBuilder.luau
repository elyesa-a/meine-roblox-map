--!nonstrict
-- VirusLabBuilder: datenbasierter Aufbau des Virus-Labor-Simulators.
--
-- Linearer Parcours entlang +X:
--   Spawn Lab (hinten) -> Trainingsbereich 1 -> Labor-Luke 1 ->
--   Area 1 (10 Gegner + DNA-Borders + 3 Egg-Catch) -> Luke/Training 2 ->
--   Area 2 -> ... -> Area 10 (Final Containment, Final Boss).
--
-- Erzeugt exakt die Strukturen, die bestehende Services erwarten:
--   * Workspace.EnemyAreas   -> EnemyService (Model.EnemyId, EnemyCore,
--                               AttackClick, StartBossFight, HealthBar*)
--   * Workspace.TrainingBeds -> TrainingZoneService (Model + Hitbox-Attrs)
--   * Workspace.Portals      -> leer, damit ZoneLockService nicht haengt
--   * Workspace.Map.ZoneTriggers -> Client CurrentAreaLabel (DisplayName-Attr)
--   * SpawnLocation          -> Spieler-Spawn
-- Neu (von BorderService / EggCatchService genutzt):
--   * Workspace.EnemyBorders -> Parts mit Attribut RequiredDNA
--   * Workspace.AreaGates    -> Parts mit RequiredDNA / RequiredRebirth
--   * Workspace.EggStations  -> ClickDetector "OpenEgg" + Egg-Attribute
--
-- Das bestehende UI / die RemoteEvents werden NICHT angefasst.

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local AreaConfig = require(Configs:WaitForChild("AreaConfig"))
local EnemyConfig = require(Configs:WaitForChild("EnemyConfig"))
local EggCatchConfig = require(Configs:WaitForChild("EggCatchConfig"))
local TrainingBedConfig = require(Configs:WaitForChild("TrainingBedConfig"))
local NumberFormatter = require(Modules:WaitForChild("NumberFormatter"))

local VirusLabBuilder = {}

local L = AreaConfig.Layout

-- ---- Basis-Farben (sauberes Labor) ---------------------------------------
local LAB_WHITE = Color3.fromRGB(208, 214, 218)
local LAB_PANEL = Color3.fromRGB(190, 198, 202)
local LAB_TRIM = Color3.fromRGB(150, 160, 166)
local LAB_DARK = Color3.fromRGB(26, 32, 40)
local LAB_CYAN = Color3.fromRGB(120, 245, 255)
local LAB_GREEN = Color3.fromRGB(95, 255, 150)
local ACCESS_UNLOCKED = Color3.fromRGB(80, 255, 140)
local ACCESS_UNLOCKED_SOFT = Color3.fromRGB(170, 255, 205)
local ACCESS_LOCKED = Color3.fromRGB(255, 85, 85)
local ACCESS_LOCKED_SOFT = Color3.fromRGB(255, 170, 170)
local FLOOR_Y = 0 -- Oberkante Boden
local CORRIDOR_MIN_Z = -85
local CORRIDOR_MAX_Z = 130 -- inkl. Egg-Catch-Alkoven (+Z Seite)
local FLOOR_CENTER_Z = (CORRIDOR_MIN_Z + CORRIDOR_MAX_Z) / 2
local FLOOR_SIZE_Z = CORRIDOR_MAX_Z - CORRIDOR_MIN_Z
local BARRIER_SIZE_Z = FLOOR_SIZE_Z + 8

-- ---- kleine Helfer --------------------------------------------------------

local function makeFolder(name: string, parent: Instance): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function clearChildren(inst: Instance)
	for _, c in ipairs(inst:GetChildren()) do
		c:Destroy()
	end
end

local function makePart(parent, name, size, pos, color, material, canCollide)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = canCollide == true
	p.Size = size
	p.Position = pos
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function neonStrip(parent, size, pos, color, transparency)
	local p = makePart(parent, "Neon", size, pos, color, Enum.Material.Neon, false)
	p.Transparency = transparency or 0.35
	return p
end

local function label(adornee, text, color, maxDistance, sizeOffset, studsOffset)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Label"
	bb.Size = sizeOffset or UDim2.fromOffset(240, 70)
	bb.StudsOffset = studsOffset or Vector3.new(0, 6, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = maxDistance or 60
	bb.Adornee = adornee
	bb.Parent = adornee

	local tl = Instance.new("TextLabel")
	tl.BackgroundTransparency = 1
	tl.Size = UDim2.fromScale(1, 1)
	tl.Text = text
	tl.Font = Enum.Font.GothamBold
	tl.TextScaled = true
	tl.TextColor3 = color
	tl.TextStrokeColor3 = Color3.new(0, 0, 0)
	tl.TextStrokeTransparency = 0.2
	tl.Parent = bb
	return tl
end

local function tint(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, math.clamp(t, 0, 1))
end

local function markAreaVisual(part: BasePart, areaId: string?)
	if areaId then
		part:SetAttribute("AreaVisualId", areaId)
	end
end

local function addLabTrim(parent, centerX, lengthX)
	for _, z in ipairs({ CORRIDOR_MIN_Z + 0.2, CORRIDOR_MAX_Z - 0.2 }) do
		local panelZ = if z < FLOOR_CENTER_Z then CORRIDOR_MIN_Z + 0.35 else CORRIDOR_MAX_Z - 0.35
		for i = 0, 3 do
			local panelWidth = lengthX / 4 - 8
			local px = centerX - lengthX / 2 + lengthX * (i + 0.5) / 4
			local panelColor = if i % 2 == 0 then Color3.fromRGB(218, 224, 226) else LAB_WHITE
			makePart(parent, "WallLabPanel", Vector3.new(panelWidth, 15, 0.35), Vector3.new(px, FLOOR_Y + 14.5, panelZ), panelColor, Enum.Material.SmoothPlastic, false)
		end
		for _, y in ipairs({ FLOOR_Y + 4, FLOOR_Y + L.WallHeight - 8 }) do
			makePart(parent, "WallBlackTrim", Vector3.new(lengthX, 1.1, 0.35), Vector3.new(centerX, y, z), LAB_DARK, Enum.Material.SmoothPlastic, false)
		end
		neonStrip(parent, Vector3.new(lengthX - 16, 0.35, 0.35), Vector3.new(centerX, FLOOR_Y + L.WallHeight - 13, panelZ), LAB_CYAN, 0.25)
		for i = 1, 3 do
			local px = centerX - lengthX / 2 + lengthX * i / 4
			makePart(parent, "WallPanelSeam", Vector3.new(0.75, L.WallHeight - 8, 0.35), Vector3.new(px, FLOOR_Y + L.WallHeight / 2, z), LAB_TRIM, Enum.Material.Metal, false)
		end
	end
	for _, z in ipairs({ CORRIDOR_MIN_Z + 4, CORRIDOR_MAX_Z - 4 }) do
		makePart(parent, "CeilingEdgeTrim", Vector3.new(lengthX, 0.7, 0.7), Vector3.new(centerX, FLOOR_Y + L.WallHeight - 0.65, z), LAB_DARK, Enum.Material.SmoothPlastic, false)
	end
end

local function addFloorGuides(parent, centerX, lengthX, color, areaId: string?)
	for _, z in ipairs({ -48, 48 }) do
		makePart(parent, "FloorLaneBase", Vector3.new(lengthX - 28, 0.08, 2.8), Vector3.new(centerX, FLOOR_Y + 0.07, z), LAB_DARK, Enum.Material.SmoothPlastic, false)
		markAreaVisual(neonStrip(parent, Vector3.new(lengthX - 32, 0.14, 0.65), Vector3.new(centerX, FLOOR_Y + 0.16, z), color, 0.18), areaId)
	end
end

local function addCeilingLabLights(parent, centerX, lengthX, color)
	for _, z in ipairs({ CORRIDOR_MIN_Z + 36, FLOOR_CENTER_Z, CORRIDOR_MAX_Z - 36 }) do
		makePart(parent, "RoofDarkBeam", Vector3.new(lengthX, 0.9, 2.6), Vector3.new(centerX, FLOOR_Y + L.WallHeight - 2.2, z), LAB_DARK, Enum.Material.Metal, false)
		neonStrip(parent, Vector3.new(lengthX - 24, 0.35, 0.55), Vector3.new(centerX, FLOOR_Y + L.WallHeight - 2.85, z), color, 0.12)
	end
	for i = 1, 4 do
		local px = centerX - lengthX / 2 + lengthX * i / 5
		makePart(parent, "RoofCrossTruss", Vector3.new(3.5, 1.4, FLOOR_SIZE_Z - 10), Vector3.new(px, FLOOR_Y + L.WallHeight - 1.7, FLOOR_CENTER_Z), LAB_DARK, Enum.Material.Metal, false)
		for _, z in ipairs({ CORRIDOR_MIN_Z + 34, FLOOR_CENTER_Z, CORRIDOR_MAX_Z - 34 }) do
			makePart(parent, "RoofLightPanel", Vector3.new(24, 0.28, 10), Vector3.new(px, FLOOR_Y + L.WallHeight - 2.95, z), LAB_CYAN, Enum.Material.Neon, false).Transparency = 0.08
			makePart(parent, "RoofPanelFrame", Vector3.new(29, 0.22, 14), Vector3.new(px, FLOOR_Y + L.WallHeight - 2.75, z), LAB_DARK, Enum.Material.SmoothPlastic, false)
		end
	end
end

-- ---- Boden, Waende, Decken-Akzent pro Segment ----------------------------

local function buildShellSegment(parent, centerX, lengthX, primary, secondary, withCorridorLines, areaId: string?, startsLocked: boolean?)
	local visualPrimary = primary
	local visualSecondary = secondary
	if areaId then
		visualPrimary = if startsLocked then ACCESS_LOCKED else ACCESS_UNLOCKED
		visualSecondary = if startsLocked then ACCESS_LOCKED_SOFT else ACCESS_UNLOCKED_SOFT
	end

	-- Boden.
	local floor = makePart(
		parent,
		"LabFloor",
		Vector3.new(lengthX, 2, FLOOR_SIZE_Z),
		Vector3.new(centerX, FLOOR_Y - 1, FLOOR_CENTER_Z),
		LAB_PANEL,
		Enum.Material.SmoothPlastic,
		true
	)
	floor.TopSurface = Enum.SurfaceType.Smooth

	-- Geschlossene, helle Decke: Labor statt offener Arena.
	makePart(
		parent,
		"LabCeiling",
		Vector3.new(lengthX, 2, FLOOR_SIZE_Z),
		Vector3.new(centerX, FLOOR_Y + L.WallHeight + 1, FLOOR_CENTER_Z),
		Color3.fromRGB(218, 226, 228),
		Enum.Material.SmoothPlastic,
		true
	)
	for i = 0, 3 do
		local sx = centerX - lengthX / 2 + (lengthX * i / 3)
		makePart(
			parent,
			"CeilingSupport",
			Vector3.new(2.4, 1.2, FLOOR_SIZE_Z),
			Vector3.new(sx, FLOOR_Y + L.WallHeight - 0.7, FLOOR_CENTER_Z),
			LAB_TRIM,
			Enum.Material.Metal,
			false
		)
	end
	for i = 0, 2 do
		local px = centerX - lengthX / 2 + lengthX * (i + 0.5) / 3
		makePart(
			parent,
			"CeilingPanel",
			Vector3.new(lengthX / 3 - 10, 0.18, FLOOR_SIZE_Z - 18),
			Vector3.new(px, FLOOR_Y + L.WallHeight - 0.15, FLOOR_CENTER_Z),
			Color3.fromRGB(198, 207, 211),
			Enum.Material.SmoothPlastic,
			false
		)
	end

	-- Seitenwaende.
	makePart(
		parent,
		"LabWallLeft",
		Vector3.new(lengthX, L.WallHeight, 4),
		Vector3.new(centerX, FLOOR_Y + L.WallHeight / 2, CORRIDOR_MIN_Z - 2),
		LAB_WHITE,
		Enum.Material.SmoothPlastic,
		true
	)
	makePart(
		parent,
		"LabWallRight",
		Vector3.new(lengthX, L.WallHeight, 4),
		Vector3.new(centerX, FLOOR_Y + L.WallHeight / 2, CORRIDOR_MAX_Z + 2),
		LAB_WHITE,
		Enum.Material.SmoothPlastic,
		true
	)
	addLabTrim(parent, centerX, lengthX)

	-- Dezente Neon-Leitlinien an den Waenden (Orientierung, keine Disco).
	markAreaVisual(neonStrip(parent, Vector3.new(lengthX, 0.5, 0.5), Vector3.new(centerX, FLOOR_Y + 6, CORRIDOR_MIN_Z - 0.1), visualPrimary, 0.45), areaId)
	markAreaVisual(neonStrip(parent, Vector3.new(lengthX, 0.5, 0.5), Vector3.new(centerX, FLOOR_Y + 6, CORRIDOR_MAX_Z + 0.1), visualPrimary, 0.45), areaId)

	-- Boden-Leitlinie entlang des Laufwegs.
	if withCorridorLines then
		markAreaVisual(neonStrip(parent, Vector3.new(lengthX, 0.12, 1.4), Vector3.new(centerX, FLOOR_Y + 0.06, 0), visualPrimary, 0.25), areaId)
		addFloorGuides(parent, centerX, lengthX, visualPrimary, areaId)
	end
	addCeilingLabLights(parent, centerX, lengthX, tint(visualPrimary, LAB_CYAN, 0.55))

	-- Decken-Lichtbalken.
	for i = 0, 2 do
		local lx = centerX - lengthX / 2 + lengthX * (i + 0.5) / 3
		local beam = makePart(
			parent,
			"CeilBeam",
			Vector3.new(18, 0.6, FLOOR_SIZE_Z),
			Vector3.new(lx, FLOOR_Y + L.WallHeight - 1, FLOOR_CENTER_Z),
			tint(visualPrimary, visualSecondary, 0.5),
			Enum.Material.Neon,
			false
		)
		markAreaVisual(beam, areaId)
		beam.Transparency = 0.4
		local pl = Instance.new("PointLight")
		pl.Brightness = 0.7
		pl.Range = 40
		pl.Color = tint(visualPrimary, visualSecondary, 0.4)
		pl.Parent = beam
	end

	return floor
end

-- ---- Gegner-Modell (Vertrag fuer EnemyService) ---------------------------

local function buildEnemyModel(parent, def, basePos, primary, secondary)
	local model = Instance.new("Model")
	model.Name = def.Id
	model:SetAttribute("EnemyId", def.Id)
	model:SetAttribute("AreaName", def.AreaName)
	model:SetAttribute("IsBoss", def.IsBoss)
	model.Parent = parent

	local color = tint(primary, secondary, math.min(0.6, def.EnemyIndex / 14))
	local s = if def.IsBoss then 14 else (4 + def.EnemyIndex * 0.5)
	local coreY = basePos.Y + s * 0.6 + 1
	local corePos = Vector3.new(basePos.X, coreY, basePos.Z)

	local shape = def.Shape
	local rootSize
	if shape == "Crawler" then
		rootSize = Vector3.new(s * 1.4, s * 0.8, s)
	elseif shape == "Drone" then
		rootSize = Vector3.new(s * 1.1, s, s * 1.1)
	elseif shape == "Brute" or shape == "Boss" then
		rootSize = Vector3.new(s * 1.2, s * 1.3, s)
	else
		rootSize = Vector3.new(s, s, s)
	end

	local root = makePart(model, "EnemyCore", rootSize, corePos, color, Enum.Material.SmoothPlastic, false)
	root.Transparency = 0.05
	if shape == "Blob" or shape == "Slime" or shape == "Spiky" or shape == "Boss" then
		root.Shape = Enum.PartType.Ball
	end
	model.PrimaryPart = root

	-- Form-Variation.
	if shape == "Spiky" then
		for _, off in ipairs({
			Vector3.new(s * 0.7, 0, 0), Vector3.new(-s * 0.7, 0, 0),
			Vector3.new(0, s * 0.7, 0), Vector3.new(0, 0, s * 0.7),
			Vector3.new(0, 0, -s * 0.7),
		}) do
			local sp = makePart(model, "Spike", Vector3.new(s * 0.3, s * 0.3, s * 0.3), corePos + off, LAB_WHITE, Enum.Material.SmoothPlastic, false)
			sp.Shape = Enum.PartType.Ball
		end
	elseif shape == "Slime" then
		root.Material = Enum.Material.Glass
		root.Transparency = 0.25
		for i = -1, 1 do
			local b = makePart(model, "Bubble", Vector3.new(s * 0.3, s * 0.3, s * 0.3), corePos + Vector3.new(i * s * 0.4, s * 0.2, -s * 0.4), tint(primary, secondary, 0.7), Enum.Material.Neon, false)
			b.Shape = Enum.PartType.Ball
			b.Transparency = 0.3
		end
	elseif shape == "Crawler" then
		for _, side in ipairs({ -1, 1 }) do
			for i = 1, 3 do
				local leg = makePart(model, "Leg", Vector3.new(s * 0.18, s * 0.18, s * 0.9), corePos + Vector3.new(side * s * 0.7, -s * 0.2, (i - 2) * s * 0.4), LAB_TRIM, Enum.Material.Metal, false)
				leg.Orientation = Vector3.new(0, side * 20, side * 15)
			end
		end
	elseif shape == "Drone" then
		root.Material = Enum.Material.Metal
		for _, side in ipairs({ -1, 1 }) do
			makePart(model, "Wing", Vector3.new(s * 0.9, s * 0.15, s * 0.5), corePos + Vector3.new(side * s * 0.9, 0, 0), LAB_WHITE, Enum.Material.Metal, false)
		end
		local eye = makePart(model, "Scanner", Vector3.new(s * 0.4, s * 0.4, s * 0.2), corePos + Vector3.new(0, 0, -s * 0.55), tint(primary, secondary, 0.8), Enum.Material.Neon, false)
		eye.Shape = Enum.PartType.Ball
	elseif shape == "Brute" then
		for _, side in ipairs({ -1, 1 }) do
			makePart(model, "Arm", Vector3.new(s * 0.3, s * 0.9, s * 0.3), corePos + Vector3.new(side * s * 0.75, -s * 0.1, 0), LAB_TRIM, Enum.Material.Metal, false)
		end
	end

	-- Augen (Charakter).
	for _, ex in ipairs({ -1, 1 }) do
		local eye = makePart(model, "Eye", Vector3.new(s * 0.16, s * 0.16, s * 0.1), corePos + Vector3.new(ex * s * 0.22, s * 0.12, -s * 0.5), Color3.fromRGB(18, 22, 28), Enum.Material.SmoothPlastic, false)
		eye.Shape = Enum.PartType.Ball
	end

	-- Boss-Aufwertung: leuchten + eigene Plattform.
	if def.IsBoss then
		root.Material = Enum.Material.Neon
		root.Transparency = 0.12
		local plat = makePart(model, "BossPad", Vector3.new(s * 2.4, 1, s * 2.4), Vector3.new(basePos.X, FLOOR_Y + 0.5, basePos.Z), LAB_DARK, Enum.Material.Metal, true)
		plat.Shape = Enum.PartType.Cylinder
		plat.Orientation = Vector3.new(0, 0, 90)
		local ring = makePart(model, "BossRing", Vector3.new(s * 2.6, 0.4, s * 2.6), Vector3.new(basePos.X, FLOOR_Y + 1.1, basePos.Z), color, Enum.Material.Neon, false)
		ring.Shape = Enum.PartType.Cylinder
		ring.Orientation = Vector3.new(0, 0, 90)
		ring.Transparency = 0.3
		local gl = Instance.new("PointLight")
		gl.Brightness = 2
		gl.Range = 30
		gl.Color = color
		gl.Parent = root
	end

	-- Health-Bar (Vertrag mit EnemyService.updateEnemy).
	local barScale = if def.IsBoss then 1.8 else 1
	local barY = corePos.Y + rootSize.Y / 2 + 3
	local barBack = makePart(model, "HealthBarBack", Vector3.new(13 * barScale, 0.8, 0.4), Vector3.new(corePos.X, barY, corePos.Z), Color3.fromRGB(16, 20, 26), Enum.Material.SmoothPlastic, false)
	local barFill = makePart(model, "HealthBarFill", Vector3.new(12.4 * barScale, 0.5, 0.55), Vector3.new(corePos.X, barY + 0.02, corePos.Z - 0.06), Color3.fromRGB(95, 255, 125), Enum.Material.Neon, false)
	barFill.Transparency = 0.12
	barFill:SetAttribute("MaxWidth", 12.4 * barScale)
	barFill:SetAttribute("FullCenterX", barFill.Position.X)

	-- Klick-Detector / Boss-Prompt.
	local clicker = Instance.new("ClickDetector")
	clicker.Name = "AttackClick"
	clicker.MaxActivationDistance = EnemyConfig.AttackDistance
	clicker.Parent = root

	if def.IsBoss then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "StartBossFight"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 1
		prompt.ActionText = "Start Boss Fight"
		prompt.ObjectText = def.DisplayName
		prompt.MaxActivationDistance = EnemyConfig.BossPromptDistance
		prompt.RequiresLineOfSight = false
		prompt.Parent = root
	end

	-- Label: Name / HP / Strength / DNA Drop (abgekuerzt).
	local prefix = if def.IsBoss then "★ BOSS ★\n" else ""
	label(
		root,
		string.format(
			"%s%s\nHP: %s\nSTR: %s\nDNA: %s",
			prefix,
			def.DisplayName,
			NumberFormatter.format(def.MaxHealth),
			NumberFormatter.format(def.Strength),
			NumberFormatter.format(def.DNAReward)
		),
		Color3.fromRGB(255, 255, 255),
		if def.IsBoss then 70 else 45,
		UDim2.fromOffset(if def.IsBoss then 300 else 240, if def.IsBoss then 120 else 96),
		Vector3.new(0, rootSize.Y / 2 + 6, 0)
	)
end

-- ---- DNA-Border zwischen zwei Gegnern ------------------------------------

local function buildBorder(parent, def, x, primary)
	local model = Instance.new("Model")
	model.Name = "Border_" .. def.Id
	model.Parent = parent

	-- Schmale Labor-Sicherheitsbarriere (Glas/Neon), nicht riesig.
	local height = 15
	for _, z in ipairs({ CORRIDOR_MIN_Z - 2, CORRIDOR_MAX_Z + 2 }) do
		makePart(model, "BorderPillar", Vector3.new(2, height + 4, 2), Vector3.new(x, FLOOR_Y + (height + 4) / 2, z), LAB_TRIM, Enum.Material.Metal, true)
	end
	makePart(model, "BorderBeam", Vector3.new(2.4, 2, BARRIER_SIZE_Z), Vector3.new(x, FLOOR_Y + height + 3, FLOOR_CENTER_Z), LAB_TRIM, Enum.Material.Metal, true)

	-- Glas-/Neon-Wand = Trigger (CanCollide=false, BorderService prueft DNA).
	local wall = makePart(model, "BorderField", Vector3.new(1.2, height, BARRIER_SIZE_Z), Vector3.new(x, FLOOR_Y + height / 2 + 0.5, FLOOR_CENTER_Z), ACCESS_LOCKED, Enum.Material.ForceField, false)
	wall.Transparency = 0.45
	wall.CanTouch = true
	wall:SetAttribute("RequiredDNA", def.RequiredDNA)

	local sign = makePart(model, "BorderSign", Vector3.new(12, 4, 0.6), Vector3.new(x, FLOOR_Y + height + 4, FLOOR_CENTER_Z), LAB_DARK, Enum.Material.SmoothPlastic, false)
	label(
		sign,
		string.format("⚠ DNA GATE\nRequired: %s DNA", NumberFormatter.format(def.RequiredDNA)),
		ACCESS_LOCKED_SOFT,
		55,
		UDim2.fromOffset(230, 80),
		Vector3.new(0, 0, 0)
	)
end

-- ---- Labor-Luke / Gate zwischen Training und Gegner-Halle -----------------

local function buildGate(parent, area, x, requiredDna)
	local model = Instance.new("Model")
	model.Name = "Gate_" .. area.id
	model:SetAttribute("AreaId", area.id)
	model.Parent = parent

	local primary = if area.index == 1 then ACCESS_UNLOCKED else ACCESS_LOCKED
	local height = 22

	-- Zwei seitliche Saeulen + oberer Balken.
	for _, z in ipairs({ CORRIDOR_MIN_Z - 3, CORRIDOR_MAX_Z + 3 }) do
		local col = makePart(model, "GatePillar", Vector3.new(6, height, 6), Vector3.new(x, FLOOR_Y + height / 2, z), LAB_WHITE, Enum.Material.Metal, true)
		local inwardZ = if z < FLOOR_CENTER_Z then 3.2 else -3.2
		neonStrip(model, Vector3.new(0.6, height - 4, 0.6), col.Position + Vector3.new(0, 0, inwardZ), primary, 0.3)
	end
	makePart(model, "GateTopBeam", Vector3.new(8, 6, BARRIER_SIZE_Z + 8), Vector3.new(x, FLOOR_Y + height + 2, FLOOR_CENTER_Z), LAB_WHITE, Enum.Material.Metal, true)

	-- Glas-Schleuse als Trigger.
	local field = makePart(model, "GateField", Vector3.new(1.6, height - 2, BARRIER_SIZE_Z), Vector3.new(x, FLOOR_Y + (height - 2) / 2 + 0.5, FLOOR_CENTER_Z), primary, Enum.Material.ForceField, false)
	field.Transparency = 0.5
	field.CanTouch = true
	field:SetAttribute("RequiredDNA", requiredDna)
	field:SetAttribute("RequiredRebirth", 0)
	field:SetAttribute("AreaName", area.displayName)

	-- Kleines Kontrollpanel.
	local panel = makePart(model, "GateControlPanel", Vector3.new(6, 7, 1), Vector3.new(x - 3, FLOOR_Y + 5, CORRIDOR_MIN_Z + 8), LAB_DARK, Enum.Material.Metal, true)
	neonStrip(model, Vector3.new(4.4, 4.4, 0.3), panel.Position + Vector3.new(0, 0.4, -0.7), primary, 0.25)

	-- Beschriftung.
	local sign = makePart(model, "GateSign", Vector3.new(20, 7, 0.7), Vector3.new(x, FLOOR_Y + height + 7, FLOOR_CENTER_Z), LAB_DARK, Enum.Material.SmoothPlastic, false)
	label(
		sign,
		string.format(
			"AREA %d: %s\nRequired: %s DNA",
			area.index,
			string.upper(area.displayName),
			NumberFormatter.format(requiredDna)
		),
		primary,
		90,
		UDim2.fromOffset(320, 96),
		Vector3.new(0, 0, 0)
	)
end

-- ---- Trainingsbereich (mit Rebirth-Gate) ---------------------------------

local function buildTrainingArea(parent, bedsFolder, gatesFolder, area, x)
	local bedDef = TrainingBedConfig[area.index]
	local primary = area.primaryColor
	local model = Instance.new("Model")
	model.Name = "Training_" .. area.id
	model.Parent = parent

	-- Kompakte Trainings-Plattform.
	local pad = makePart(model, "TrainingPad", Vector3.new(70, 0.6, 90), Vector3.new(x, FLOOR_Y + 0.35, FLOOR_CENTER_Z), tint(LAB_PANEL, primary, 0.18), Enum.Material.SmoothPlastic, true)
	for _, dz in ipairs({ -1, 1 }) do
		neonStrip(model, Vector3.new(70, 0.12, 0.6), Vector3.new(x, FLOOR_Y + 0.7, FLOOR_CENTER_Z + dz * 44), primary, 0.3)
	end

	-- Drei klare Trainings-Pads + Beschriftung.
	local padInfos = {
		{ name = "POWER TRAINING", short = "PWR", dz = -28, c = Color3.fromRGB(255, 120, 120) },
		{ name = "DNA TRAINING", short = "DNA", dz = 0, c = Color3.fromRGB(120, 235, 160) },
		{ name = "LUCK / BOOST", short = "BOOST", dz = 30, c = Color3.fromRGB(255, 215, 110) },
	}
	for _, info in ipairs(padInfos) do
		local tp = makePart(model, "TrainPad", Vector3.new(16, 0.5, 16), Vector3.new(x, FLOOR_Y + 0.75, FLOOR_CENTER_Z + info.dz), info.c, Enum.Material.Neon, false)
		tp.Transparency = 0.45
		local stationBase = makePart(model, "TrainStationBase", Vector3.new(24, 0.25, 22), tp.Position + Vector3.new(0, -0.18, 0), LAB_DARK, Enum.Material.Metal, false)
		stationBase.Transparency = 0.08
		for _, edgeZ in ipairs({ -10.8, 10.8 }) do
			neonStrip(model, Vector3.new(19, 0.16, 0.36), tp.Position + Vector3.new(0, 0.12, edgeZ), info.c, 0.16)
		end
		for _, edgeX in ipairs({ -11.8, 11.8 }) do
			neonStrip(model, Vector3.new(0.36, 0.16, 18), tp.Position + Vector3.new(edgeX, 0.12, 0), info.c, 0.22)
		end
		for _, edgeX in ipairs({ -9, 9 }) do
			local scannerPost = makePart(model, "TrainScannerPost", Vector3.new(0.7, 6.8, 0.7), tp.Position + Vector3.new(edgeX, 3.5, -9.4), LAB_DARK, Enum.Material.Metal, false)
			neonStrip(model, Vector3.new(0.35, 4.7, 0.28), scannerPost.Position + Vector3.new(0, 0.2, -0.42), info.c, 0.22)
		end
		local scannerBeam = makePart(model, "TrainScannerBeam", Vector3.new(19, 0.7, 0.8), tp.Position + Vector3.new(0, 6.9, -9.4), LAB_DARK, Enum.Material.Metal, false)
		neonStrip(model, Vector3.new(14, 0.22, 0.36), scannerBeam.Position + Vector3.new(0, 0.45, -0.38), info.c, 0.18)
		local terminal = makePart(model, "TrainTerminal", Vector3.new(5.6, 3.2, 3.8), tp.Position + Vector3.new(23, 1.65, 0), LAB_DARK, Enum.Material.Metal, false)
		local screen = makePart(model, "TrainTerminalScreen", Vector3.new(0.38, 2.4, 3), terminal.Position + Vector3.new(-2.95, 1.15, 0), info.c, Enum.Material.Neon, false)
		screen.Transparency = 0.16
		label(screen, info.short, Color3.fromRGB(255, 255, 255), 32, UDim2.fromOffset(90, 34), Vector3.new(0, 0, 0))
		local post = makePart(model, "TrainSignPost", Vector3.new(0.6, 6, 0.6), tp.Position + Vector3.new(0, 3, 0), LAB_TRIM, Enum.Material.Metal, false)
		label(post, info.name, info.c, 40, UDim2.fromOffset(180, 44), Vector3.new(0, 3, 0))
	end

	-- Hauptschild.
	local sign = makePart(model, "TrainingSign", Vector3.new(26, 9, 0.8), Vector3.new(x, FLOOR_Y + 9, FLOOR_CENTER_Z - 46), LAB_DARK, Enum.Material.SmoothPlastic, false)
	label(
		sign,
		string.format(
			"TRAINING %d\n%s\n%s PWR/s | %s",
			area.index,
			string.upper(area.displayName),
			NumberFormatter.format(bedDef.powerPerSecond),
			if bedDef.requiredRebirth > 0 then "Requires Rebirth " .. bedDef.requiredRebirth else "Open"
		),
		primary,
		70,
		UDim2.fromOffset(280, 96),
		Vector3.new(0, 0, 0)
	)

	-- Trainings-Bett (Vertrag mit TrainingZoneService): Model + Hitbox-Part.
	local bedModel = Instance.new("Model")
	bedModel.Name = bedDef.id
	bedModel.Parent = bedsFolder
	local hitbox = makePart(bedModel, "Hitbox", Vector3.new(60, 8, 78), Vector3.new(x, FLOOR_Y + 4, FLOOR_CENTER_Z), primary, Enum.Material.SmoothPlastic, false)
	hitbox.Transparency = 1
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox:SetAttribute("RequiredRebirth", bedDef.requiredRebirth)
	hitbox:SetAttribute("PowerPerSecond", bedDef.powerPerSecond)

	-- Rebirth-Gate vor dem Training (nur wenn Anforderung > 0).
	if bedDef.requiredRebirth > 0 then
		local gateX = x - 70
		local gm = Instance.new("Model")
		gm.Name = "TrainingGate_" .. area.id
		gm.Parent = gatesFolder
		for _, z in ipairs({ CORRIDOR_MIN_Z - 3, CORRIDOR_MAX_Z + 3 }) do
			makePart(gm, "TGatePillar", Vector3.new(5, 20, 5), Vector3.new(gateX, FLOOR_Y + 10, z), LAB_WHITE, Enum.Material.Metal, true)
		end
		makePart(gm, "TGateBeam", Vector3.new(6, 5, BARRIER_SIZE_Z + 8), Vector3.new(gateX, FLOOR_Y + 21, FLOOR_CENTER_Z), LAB_WHITE, Enum.Material.Metal, true)
		local field = makePart(gm, "TrainingGateField", Vector3.new(1.6, 18, BARRIER_SIZE_Z), Vector3.new(gateX, FLOOR_Y + 9.5, FLOOR_CENTER_Z), Color3.fromRGB(255, 170, 90), Enum.Material.ForceField, false)
		field.Color = ACCESS_LOCKED
		field.Transparency = 0.5
		field.CanTouch = true
		field:SetAttribute("RequiredDNA", 0)
		field:SetAttribute("RequiredRebirth", bedDef.requiredRebirth)
		field:SetAttribute("AreaName", area.displayName .. " Training")
		local s = makePart(gm, "TGateSign", Vector3.new(18, 6, 0.7), Vector3.new(gateX, FLOOR_Y + 26, FLOOR_CENTER_Z), LAB_DARK, Enum.Material.SmoothPlastic, false)
		label(
			s,
			string.format("TRAINING LOCK\nRequires Rebirth %d", bedDef.requiredRebirth),
			ACCESS_LOCKED_SOFT,
			80,
			UDim2.fromOffset(260, 76),
			Vector3.new(0, 0, 0)
		)
	end
end

-- ---- Egg-Catch-Station ----------------------------------------------------

local function buildEggStation(parent, areaIndex, stationIndex, eggDef, pos)
	local model = Instance.new("Model")
	model.Name = string.format("Egg_A%d_%s", areaIndex, eggDef.tier)
	model.Parent = parent

	local base = makePart(model, "EggBase", Vector3.new(12, 1.2, 12), pos, LAB_DARK, Enum.Material.Metal, true)
	base.Shape = Enum.PartType.Cylinder
	base.Orientation = Vector3.new(0, 0, 90)

	local ring = makePart(model, "EggRing", Vector3.new(12.6, 0.5, 12.6), pos + Vector3.new(0, 0.8, 0), eggDef.color, Enum.Material.Neon, false)
	ring.Shape = Enum.PartType.Cylinder
	ring.Orientation = Vector3.new(0, 0, 90)
	ring.Transparency = 0.3

	-- Ei / Kapsel in der Mitte.
	local capsule = makePart(model, "EggCapsule", Vector3.new(5, 6.5, 5), pos + Vector3.new(0, 4.5, 0), eggDef.color, Enum.Material.SmoothPlastic, false)
	capsule.Shape = Enum.PartType.Ball
	capsule.Transparency = 0.1
	local glow = Instance.new("PointLight")
	glow.Brightness = 1.4
	glow.Range = 14
	glow.Color = eggDef.color
	glow.Parent = capsule

	-- Egg-Daten + Klick-Hook (EggCatchService verbindet "OpenEgg").
	model:SetAttribute("AreaIndex", areaIndex)
	model:SetAttribute("EggTier", eggDef.tier)
	model:SetAttribute("EggCost", eggDef.cost)
	local cd = Instance.new("ClickDetector")
	cd.Name = "OpenEgg"
	cd.MaxActivationDistance = 14
	cd.Parent = capsule

	label(
		capsule,
		string.format("%s EGG\nCost: %s DNA", string.upper(eggDef.tier), NumberFormatter.format(eggDef.cost)),
		eggDef.color,
		40,
		UDim2.fromOffset(200, 70),
		Vector3.new(0, 5.5, 0)
	)
end

local function buildConsole(parent, name, pos, accent, text)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local base = makePart(model, "ConsoleBase", Vector3.new(9, 4, 5), pos + Vector3.new(0, 2, 0), LAB_DARK, Enum.Material.Metal, true)
	makePart(model, "ConsoleTop", Vector3.new(9.5, 0.6, 5.5), pos + Vector3.new(0, 4.3, 0), LAB_TRIM, Enum.Material.Metal, true)
	local screen = makePart(model, "ConsoleScreen", Vector3.new(6.5, 3.5, 0.45), pos + Vector3.new(0, 6.1, -2.75), accent, Enum.Material.Neon, false)
	screen.Transparency = 0.18
	label(screen, text, Color3.fromRGB(255, 255, 255), 35, UDim2.fromOffset(140, 38), Vector3.new(0, 0, 0))
	neonStrip(model, Vector3.new(6.5, 0.25, 0.35), base.Position + Vector3.new(0, 1.4, -2.75), accent, 0.15)
end

local function buildTestTubeRack(parent, name, center, accent)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	makePart(model, "TubeRackBase", Vector3.new(20, 1.1, 7), center + Vector3.new(0, 0.55, 0), LAB_DARK, Enum.Material.Metal, true)
	for i = -2, 2 do
		local tube = makePart(model, "SampleTube", Vector3.new(2.4, 8, 2.4), center + Vector3.new(i * 3.6, 5, 0), Color3.fromRGB(180, 235, 245), Enum.Material.Glass, false)
		tube.Shape = Enum.PartType.Cylinder
		tube.Transparency = 0.45
		local fluid = makePart(model, "SampleGlow", Vector3.new(1.7, 3.2, 1.7), center + Vector3.new(i * 3.6, 2.9, 0), accent, Enum.Material.Neon, false)
		fluid.Shape = Enum.PartType.Cylinder
		fluid.Transparency = 0.2
	end
end

local function buildContainmentTube(parent, name, center, accent, text)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local base = makePart(model, "ContainmentBase", Vector3.new(13, 1.2, 13), center + Vector3.new(0, 0.6, 0), LAB_DARK, Enum.Material.Metal, true)
	base.Shape = Enum.PartType.Cylinder
	base.Orientation = Vector3.new(0, 0, 90)
	local glass = makePart(model, "ContainmentGlass", Vector3.new(9, 18, 9), center + Vector3.new(0, 10, 0), Color3.fromRGB(170, 235, 245), Enum.Material.Glass, false)
	glass.Shape = Enum.PartType.Cylinder
	glass.Transparency = 0.55
	local top = makePart(model, "ContainmentTop", Vector3.new(12, 1.1, 12), center + Vector3.new(0, 19.5, 0), LAB_DARK, Enum.Material.Metal, true)
	top.Shape = Enum.PartType.Cylinder
	top.Orientation = Vector3.new(0, 0, 90)
	for _, ox in ipairs({ -4.8, 4.8 }) do
		neonStrip(model, Vector3.new(0.4, 16.5, 0.4), center + Vector3.new(ox, 10, 0), accent, 0.2)
	end
	local sample = makePart(model, "FloatingSample", Vector3.new(3.5, 3.5, 3.5), center + Vector3.new(0, 10.5, 0), accent, Enum.Material.Neon, false)
	sample.Shape = Enum.PartType.Ball
	sample.Transparency = 0.15
	local sign = makePart(model, "ContainmentSign", Vector3.new(16, 3.4, 0.6), center + Vector3.new(0, 22, -6.8), LAB_DARK, Enum.Material.SmoothPlastic, false)
	label(sign, text, accent, 45, UDim2.fromOffset(180, 40), Vector3.new(0, 0, 0))
end

local function buildCrateStack(parent, name, origin, accent)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local offsets = {
		Vector3.new(0, 1.5, 0),
		Vector3.new(6.2, 1.5, 0),
		Vector3.new(3.1, 4.6, 0),
		Vector3.new(0, 1.5, 5.8),
	}
	for i, off in ipairs(offsets) do
		local crate = makePart(model, "LabCrate" .. i, Vector3.new(5.6, 3, 5.2), origin + off, LAB_TRIM, Enum.Material.Metal, true)
		makePart(model, "CrateTrim" .. i, Vector3.new(5.9, 0.35, 5.5), crate.Position + Vector3.new(0, 1.2, 0), LAB_DARK, Enum.Material.SmoothPlastic, false)
		neonStrip(model, Vector3.new(3.6, 0.25, 0.35), crate.Position + Vector3.new(0, 0.15, -2.75), accent, 0.25)
	end
end

local function addSpawnFloorArrows(parent, cx, accent)
	for i = 0, 4 do
		local x = cx + 20 + i * 24
		makePart(parent, "GuideArrowBody", Vector3.new(15, 0.12, 3.6), Vector3.new(x, FLOOR_Y + 0.21, 0), LAB_DARK, Enum.Material.SmoothPlastic, false)
		local glow = neonStrip(parent, Vector3.new(10, 0.16, 0.8), Vector3.new(x, FLOOR_Y + 0.31, 0), accent, 0.08)
		glow.Orientation = Vector3.new(0, 0, -20)
		local tip = makePart(parent, "GuideArrowTip", Vector3.new(5, 0.14, 5), Vector3.new(x + 8, FLOOR_Y + 0.32, 0), accent, Enum.Material.Neon, false)
		tip.Orientation = Vector3.new(0, 45, 0)
		tip.Transparency = 0.12
	end
end

local function addBackWallLabFeature(parent, cx)
	local wallX = cx - 147.4
	for _, z in ipairs({ -54, 0, 54 }) do
		local panel = makePart(parent, "SpawnFeaturePanel", Vector3.new(0.8, 19, 42), Vector3.new(wallX, FLOOR_Y + 15.5, z), Color3.fromRGB(225, 230, 232), Enum.Material.SmoothPlastic, false)
		makePart(parent, "FeaturePanelFrame", Vector3.new(1, 20.5, 44), panel.Position + Vector3.new(-0.15, 0, 0), LAB_DARK, Enum.Material.SmoothPlastic, false).Transparency = 0.05
		neonStrip(parent, Vector3.new(0.55, 0.45, 32), panel.Position + Vector3.new(-0.55, 7.3, 0), LAB_CYAN, 0.15)
	end
	local banner = makePart(parent, "SpawnWallBanner", Vector3.new(1, 6, 86), Vector3.new(wallX - 0.4, FLOOR_Y + 27.5, FLOOR_CENTER_Z), LAB_DARK, Enum.Material.SmoothPlastic, false)
	label(banner, "VIRUS SIMULATOR LAB", Color3.fromRGB(170, 255, 225), 80, UDim2.fromOffset(380, 64), Vector3.new(0, 0, 0))
end

local function addCeilingConduits(parent, cx)
	for _, z in ipairs({ -66, -18, 30, 78 }) do
		makePart(parent, "CeilingPipe", Vector3.new(230, 1.1, 1.1), Vector3.new(cx - 24, FLOOR_Y + L.WallHeight - 5.4, z), LAB_DARK, Enum.Material.Metal, false)
		neonStrip(parent, Vector3.new(212, 0.25, 0.25), Vector3.new(cx - 18, FLOOR_Y + L.WallHeight - 4.65, z), LAB_GREEN, 0.35)
	end
end

-- ---- Spawn Lab ------------------------------------------------------------

local function buildSpawnLab(parent, bedsFolder)
	local cx = L.SpawnCenterX
	local model = Instance.new("Model")
	model.Name = "SpawnLab"
	model.Parent = parent

	-- Boden + Shell des Spawn-Raums (reicht bis Area 1 bei X = 0).
	local floorLen = math.abs(0 - (cx - 150)) -- (cx-150) .. 0
	local floorCx = (cx - 150 + 0) / 2
	buildShellSegment(model, floorCx, floorLen, Color3.fromRGB(95, 230, 200), Color3.fromRGB(150, 255, 220), true)
	addBackWallLabFeature(model, cx)
	addCeilingConduits(model, cx)
	addSpawnFloorArrows(model, cx, LAB_GREEN)

	-- Rueckwand hinter dem Spawn.
	makePart(model, "SpawnBackWall", Vector3.new(4, L.WallHeight, FLOOR_SIZE_Z), Vector3.new(cx - 150, FLOOR_Y + L.WallHeight / 2, FLOOR_CENTER_Z), LAB_WHITE, Enum.Material.SmoothPlastic, true)

	-- SpawnLocation.
	local spawnLoc = Instance.new("SpawnLocation")
	spawnLoc.Name = "LabSpawn"
	spawnLoc.Anchored = true
	spawnLoc.CanCollide = true
	spawnLoc.Neutral = true
	spawnLoc.Enabled = true
	spawnLoc.Size = Vector3.new(14, 1, 14)
	spawnLoc.Position = Vector3.new(cx, FLOOR_Y + 0.5, 0)
	spawnLoc.Color = Color3.fromRGB(150, 255, 200)
	spawnLoc.Material = Enum.Material.Neon
	spawnLoc.Transparency = 0.25
	spawnLoc.TopSurface = Enum.SurfaceType.Smooth
	spawnLoc.Parent = model

	-- Zentraler DNA-Core (Deko).
	local reactorPad = makePart(model, "ReactorFloorPad", Vector3.new(30, 0.35, 30), Vector3.new(cx, FLOOR_Y + 0.18, -45), LAB_DARK, Enum.Material.Metal, true)
	reactorPad.Shape = Enum.PartType.Cylinder
	reactorPad.Orientation = Vector3.new(0, 0, 90)
	local reactorGlow = makePart(model, "ReactorGlowRing", Vector3.new(31, 0.18, 31), Vector3.new(cx, FLOOR_Y + 0.48, -45), LAB_CYAN, Enum.Material.Neon, false)
	reactorGlow.Shape = Enum.PartType.Cylinder
	reactorGlow.Orientation = Vector3.new(0, 0, 90)
	reactorGlow.Transparency = 0.45
	local coreBase = makePart(model, "DNACoreBase", Vector3.new(18, 1.4, 18), Vector3.new(cx, FLOOR_Y + 0.7, -45), LAB_PANEL, Enum.Material.Metal, true)
	coreBase.Shape = Enum.PartType.Cylinder
	coreBase.Orientation = Vector3.new(0, 0, 90)
	local coreBaseTrim = makePart(model, "DNACoreBaseTrim", Vector3.new(19.2, 0.45, 19.2), Vector3.new(cx, FLOOR_Y + 1.55, -45), LAB_DARK, Enum.Material.Metal, true)
	coreBaseTrim.Shape = Enum.PartType.Cylinder
	coreBaseTrim.Orientation = Vector3.new(0, 0, 90)
	local glass = makePart(model, "DNACoreGlass", Vector3.new(10, 16, 10), Vector3.new(cx, FLOOR_Y + 9, -45), Color3.fromRGB(120, 255, 200), Enum.Material.Glass, false)
	glass.Shape = Enum.PartType.Cylinder
	glass.Transparency = 0.6
	local coreTop = makePart(model, "DNACoreTopCap", Vector3.new(12, 1.2, 12), Vector3.new(cx, FLOOR_Y + 17.4, -45), LAB_DARK, Enum.Material.Metal, true)
	coreTop.Shape = Enum.PartType.Cylinder
	coreTop.Orientation = Vector3.new(0, 0, 90)
	neonStrip(model, Vector3.new(7.5, 0.35, 0.35), Vector3.new(cx, FLOOR_Y + 17.95, -45), Color3.fromRGB(120, 245, 255), 0.15)
	for _, ox in ipairs({ -2.2, 2.2 }) do
		neonStrip(model, Vector3.new(0.35, 13.5, 0.35), Vector3.new(cx + ox, FLOOR_Y + 9, -45), Color3.fromRGB(120, 245, 255), 0.25)
	end
	for i = 0, 12 do
		local angle = i * math.pi / 3
		local y = FLOOR_Y + 3 + i * 1.05
		local x1 = cx + math.cos(angle) * 3.2
		local z1 = -45 + math.sin(angle) * 3.2
		local x2 = cx - math.cos(angle) * 3.2
		local z2 = -45 - math.sin(angle) * 3.2
		local n1 = makePart(model, "DNAHelixNode", Vector3.new(0.9, 0.9, 0.9), Vector3.new(x1, y, z1), LAB_CYAN, Enum.Material.Neon, false)
		n1.Shape = Enum.PartType.Ball
		local n2 = makePart(model, "DNAHelixNode", Vector3.new(0.9, 0.9, 0.9), Vector3.new(x2, y, z2), LAB_GREEN, Enum.Material.Neon, false)
		n2.Shape = Enum.PartType.Ball
		local rung = makePart(model, "DNAHelixRung", Vector3.new(6.4, 0.18, 0.18), Vector3.new(cx, y, -45), Color3.fromRGB(210, 255, 250), Enum.Material.Neon, false)
		rung.Orientation = Vector3.new(0, math.deg(-angle), 0)
		rung.Transparency = 0.15
	end
	local core = makePart(model, "DNACore", Vector3.new(5, 5, 5), Vector3.new(cx, FLOOR_Y + 9, -45), Color3.fromRGB(90, 255, 170), Enum.Material.Neon, false)
	core.Shape = Enum.PartType.Ball
	local coreLight = Instance.new("PointLight")
	coreLight.Brightness = 2.1
	coreLight.Range = 34
	coreLight.Color = LAB_CYAN
	coreLight.Parent = core
	local particles = Instance.new("ParticleEmitter")
	particles.Name = "ReactorSparkles"
	particles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	particles.Color = ColorSequence.new(LAB_CYAN, LAB_GREEN)
	particles.LightEmission = 0.45
	particles.Rate = 5
	particles.Lifetime = NumberRange.new(1.1, 1.8)
	particles.Speed = NumberRange.new(0.8, 1.6)
	particles.SpreadAngle = Vector2.new(35, 35)
	particles.Size = NumberSequence.new(0.35, 0.05)
	particles.Parent = core
	label(core, "DNA CORE", Color3.fromRGB(255, 255, 255), 50, UDim2.fromOffset(180, 44), Vector3.new(0, 6, 0))

	-- Einfache Glas-Zellen als Labor-Deko.
	for i, dz in ipairs({ -1, 1 }) do
		local gx = cx - 70
		local cell = makePart(model, "GlassCell" .. i, Vector3.new(10, 14, 10), Vector3.new(gx, FLOOR_Y + 7, dz * 60), Color3.fromRGB(180, 220, 230), Enum.Material.Glass, false)
		cell.Transparency = 0.55
		makePart(model, "CellBase" .. i, Vector3.new(11, 1, 11), Vector3.new(gx, FLOOR_Y + 0.5, dz * 60), LAB_TRIM, Enum.Material.Metal, true)
		local cellSign = makePart(model, "CellSign" .. i, Vector3.new(16, 4, 0.7), Vector3.new(gx, FLOOR_Y + 15.5, dz * 60), LAB_DARK, Enum.Material.SmoothPlastic, false)
		label(cellSign, if i == 1 then "RESEARCH" else "VIRUS STORAGE", Color3.fromRGB(160, 245, 255), 45, UDim2.fromOffset(180, 44), Vector3.new(0, 0, 0))
	end
	buildContainmentTube(model, "ContainmentTubeA", Vector3.new(cx - 108, FLOOR_Y, -54), LAB_CYAN, "SAMPLE A")
	buildContainmentTube(model, "ContainmentTubeB", Vector3.new(cx - 108, FLOOR_Y, 20), LAB_GREEN, "MUTATION")
	buildConsole(model, "MutationConsole", Vector3.new(cx + 34, FLOOR_Y, -48), LAB_CYAN, "CORE")
	buildConsole(model, "StorageConsole", Vector3.new(cx - 112, FLOOR_Y, 92), LAB_GREEN, "SCAN")
	buildTestTubeRack(model, "SampleTubeRack", Vector3.new(cx + 42, FLOOR_Y, 96), LAB_GREEN)
	buildCrateStack(model, "LabStorageCratesA", Vector3.new(cx + 88, FLOOR_Y, -76), LAB_CYAN)
	buildCrateStack(model, "LabStorageCratesB", Vector3.new(cx + 92, FLOOR_Y, 88), LAB_GREEN)

	-- Dediziertes Pet-Egg (bestehendes System; Main verdrahtet "OpenEgg").
	local eggBase = makePart(model, "PetEggBase", Vector3.new(12, 1.4, 12), Vector3.new(cx + 70, FLOOR_Y + 0.7, 55), LAB_DARK, Enum.Material.Metal, true)
	eggBase.Shape = Enum.PartType.Cylinder
	eggBase.Orientation = Vector3.new(0, 0, 90)
	local egg = makePart(model, "PetEgg", Vector3.new(7, 9, 7), Vector3.new(cx + 70, FLOOR_Y + 6, 55), Color3.fromRGB(180, 230, 255), Enum.Material.SmoothPlastic, false)
	egg.Shape = Enum.PartType.Ball
	egg.Transparency = 0.05
	local cd = Instance.new("ClickDetector")
	cd.Name = "OpenEgg"
	cd.MaxActivationDistance = 16
	cd.Parent = egg
	label(egg, "PET EGG\nClick to open", Color3.fromRGB(180, 230, 255), 40, UDim2.fromOffset(190, 60), Vector3.new(0, 7, 0))
	VirusLabBuilder.PetEgg = egg

	-- Wegweiser Richtung Area 1.
	local arrowSign = makePart(model, "StartArrow", Vector3.new(20, 6, 0.7), Vector3.new(cx + 110, FLOOR_Y + 6, 0), LAB_DARK, Enum.Material.SmoothPlastic, false)
	label(arrowSign, "→ TRAINING & AREA 1", Color3.fromRGB(150, 255, 200), 60, UDim2.fromOffset(240, 56), Vector3.new(0, 0, 0))

	local headerSign = makePart(model, "SpawnLabHeader", Vector3.new(0.7, 5, 38), Vector3.new(cx - 148, FLOOR_Y + L.WallHeight - 7, FLOOR_CENTER_Z), LAB_DARK, Enum.Material.SmoothPlastic, false)
	label(headerSign, "MUTATION LAB", Color3.fromRGB(150, 255, 220), 75, UDim2.fromOffset(300, 54), Vector3.new(0, 0, 0))
end

-- ---- Lighting -------------------------------------------------------------

local function applyLighting()
	Lighting.Ambient = Color3.fromRGB(140, 146, 156)
	Lighting.OutdoorAmbient = Color3.fromRGB(160, 168, 176)
	Lighting.Brightness = 1.9
	Lighting.GlobalShadows = true
	Lighting.ClockTime = 14

	for _, n in ipairs({ "VirusBloom", "VirusAtm" }) do
		local e = Lighting:FindFirstChild(n)
		if e then
			e:Destroy()
		end
	end
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "VirusBloom"
	bloom.Intensity = 0.15
	bloom.Size = 7
	bloom.Threshold = 1.4
	bloom.Parent = Lighting
	local atm = Instance.new("Atmosphere")
	atm.Name = "VirusAtm"
	atm.Density = 0.08
	atm.Color = Color3.fromRGB(212, 224, 234)
	atm.Decay = Color3.fromRGB(135, 148, 160)
	atm.Haze = 0.2
	atm.Parent = Lighting
end

-- ---- Master Build ---------------------------------------------------------

function VirusLabBuilder.build()
	applyLighting()

	-- Folder-Struktur.
	local mapFolder = makeFolder("Map", Workspace)
	local zoneTriggers = makeFolder("ZoneTriggers", mapFolder)
	clearChildren(zoneTriggers)
	local labFolder = makeFolder("VirusLab", Workspace)
	clearChildren(labFolder)
	local enemyFolder = makeFolder("EnemyAreas", Workspace)
	clearChildren(enemyFolder)
	local bossFolder = makeFolder("BossFields", Workspace) -- leer, EnemyService scannt es
	clearChildren(bossFolder)
	local bordersFolder = makeFolder("EnemyBorders", Workspace)
	clearChildren(bordersFolder)
	local gatesFolder = makeFolder("AreaGates", Workspace)
	clearChildren(gatesFolder)
	local eggFolder = makeFolder("EggStations", Workspace)
	clearChildren(eggFolder)
	local bedsFolder = makeFolder("TrainingBeds", Workspace)
	clearChildren(bedsFolder)
	-- Portals MUSS existieren, sonst haengt ZoneLockService.start (WaitForChild).
	makeFolder("Portals", Workspace)

	local spawnFolder = makeFolder("SpawnLab", labFolder)
	buildSpawnLab(spawnFolder, bedsFolder)

	-- Spawn-ZoneTrigger.
	do
		-- Deckt [SpawnCenterX-150, 0] ab -> nahtlos an Area-1-Trigger.
		local t = makePart(zoneTriggers, "Spawn", Vector3.new(330, 60, FLOOR_SIZE_Z), Vector3.new(L.SpawnCenterX + 15, FLOOR_Y + 30, FLOOR_CENTER_Z), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, false)
		t.Transparency = 1
		t.CanCollide = false
		t.CanTouch = false
		t:SetAttribute("DisplayName", "Spawn Lab")
	end

	-- 10 Areale aufbauen.
	for _, area in ipairs(AreaConfig.Areas) do
		local hallX = area.hallCenterX
		local primary = area.primaryColor
		local secondary = area.secondaryColor
		local areaModel = makeFolder(area.id, labFolder)

		-- Shell-Segment der Area.
		buildShellSegment(areaModel, hallX, L.AreaSpan, primary, secondary, true, area.id, area.index > 1)

		-- Trainingsbereich (vor der Halle) + ggf. Rebirth-Gate.
		buildTrainingArea(areaModel, bedsFolder, gatesFolder, area, hallX + L.TrainingOffsetX)

		-- Gegner dieser Area.
		local defs = EnemyConfig.getByArea(area.id)
		local enemyAreaFolder = makeFolder(area.id, enemyFolder)
		local startX = hallX - (L.EnemySpacing * (L.EnemiesPerArea - 1)) / 2

		-- Labor-Luke: DNA-Anforderung = Drop des ersten Gegners der Area.
		local gateReq = if #defs > 0 then defs[1].RequiredDNA else 0
		buildGate(gatesFolder, area, hallX + L.GateOffsetX, gateReq)

		for i, def in ipairs(defs) do
			local ex = startX + L.EnemySpacing * (i - 1)
			buildEnemyModel(enemyAreaFolder, def, Vector3.new(ex, FLOOR_Y, 0), primary, secondary)
			-- DNA-Border VOR jedem Gegner ab dem 2. (Vorgabe).
			if i >= 2 then
				buildBorder(bordersFolder, def, ex - L.EnemySpacing / 2, primary)
			end
		end

		-- 3 Egg-Catch-Stationen seitlich (nicht im Weg).
		local eggDefs = EggCatchConfig.getForArea(area.index)
		local eggXs = { hallX - 90, hallX, hallX + 90 }
		for si, eggDef in ipairs(eggDefs) do
			buildEggStation(eggFolder, area.index, si, eggDef, Vector3.new(eggXs[si], FLOOR_Y + 0.6, L.EggZ))
		end

		-- ZoneTrigger fuer das HUD (CurrentAreaLabel liest DisplayName).
		local trig = makePart(zoneTriggers, area.id, Vector3.new(L.AreaSpan, 60, FLOOR_SIZE_Z), Vector3.new(hallX, FLOOR_Y + 30, FLOOR_CENTER_Z), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, false)
		trig.Transparency = 1
		trig.CanCollide = false
		trig.CanTouch = false
		trig:SetAttribute("DisplayName", area.displayName)

		-- Abschlusswand nach der letzten Area.
		if area.index == AreaConfig.count() then
			makePart(areaModel, "FinalWall", Vector3.new(4, L.WallHeight, FLOOR_SIZE_Z), Vector3.new(hallX + L.AreaSpan / 2, FLOOR_Y + L.WallHeight / 2, FLOOR_CENTER_Z), LAB_DARK, Enum.Material.Metal, true)
		end
	end

	print(string.format(
		"[VirusLabBuilder] %d Areale, %d Gegner, Borders + Gates + Egg-Stationen erzeugt.",
		AreaConfig.count(),
		#EnemyConfig.Enemies
	))
end

return VirusLabBuilder
