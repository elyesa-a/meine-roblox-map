--!nonstrict
-- VirusLabBuilder: datenbasierter Aufbau des Virus-Labor-Simulators.
--
-- Linearer Parcours entlang +X:
--   Spawn Lab (hinten) -> Trainingsbereich 1 -> Labor-Luke 1 ->
--   Area 1 (10 Gegner + PWR-Borders + 3 Egg-Catch) -> Luke/Training 2 ->
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
--   * Workspace.EnemyBorders -> Parts mit Attribut RequiredPower
--   * Workspace.AreaGates    -> Parts mit RequiredPower / RequiredRebirth
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
local LAB_WHITE = Color3.fromRGB(214, 217, 216)
local LAB_PANEL = Color3.fromRGB(174, 180, 180)
local LAB_TRIM = Color3.fromRGB(112, 120, 122)
local LAB_DARK = Color3.fromRGB(20, 24, 27)
local LAB_CYAN = Color3.fromRGB(125, 180, 184)
local LAB_GREEN = Color3.fromRGB(104, 148, 112)
local LAB_OLIVE = Color3.fromRGB(92, 112, 68)
local LAB_WARNING_YELLOW = Color3.fromRGB(188, 162, 76)
local LAB_WARNING_RED = Color3.fromRGB(115, 38, 38)
local ACCESS_UNLOCKED = Color3.fromRGB(92, 145, 102)
local ACCESS_UNLOCKED_SOFT = Color3.fromRGB(166, 204, 172)
local ACCESS_LOCKED = Color3.fromRGB(135, 54, 54)
local ACCESS_LOCKED_SOFT = Color3.fromRGB(205, 142, 132)
local FLOOR_Y = 0 -- Oberkante Boden

-- ---- Sauberes Boden-Layering (Ursache des schwarzen Flacker-Bugs) ---------
-- Der schwarze Boden unter den Gegnern entstand durch Z-Fighting: mehrere
-- duenne, teils dunkle Flaechen lagen exakt auf derselben oder fast derselben
-- Y-Ebene (Boden-Oberkante, Pfad, Naht, Korridor-Linie ...) UND der Boden
-- (Unterkante Y=-2) lag exakt auf der Baseplate-Oberkante (Y=-2).
--
-- Loesung an der Ursache:
--   * Der LabFloor ist jetzt dick genug, dass seine Unterkante die
--     Baseplate komplett durchdringt (Schnittkoerper statt deckungsgleicher
--     Flaeche -> kein Flimmern, keine schwarze Flaeche).
--   * Jede flache Boden-Deko bekommt eine EINDEUTIGE Hoehe mit klarem
--     Abstand. Es teilen sich nie zwei flache Flaechen eine Y-Ebene.
--   * Die Gegner-Plattform (CHAMBER_TOP) liegt ueber ALLEN Boden-Decals und
--     ist unten im Boden versenkt -> direkt unter dem Gegner ist immer nur
--     eine saubere, helle Flaeche sichtbar.
local FLOOR_THICKNESS = 5 -- Boden dick: Unterkante (-5) durchdringt Baseplate
local LAYER_PATH = FLOOR_Y + 0.16
local LAYER_LANE = FLOOR_Y + 0.22
local LAYER_LANE_GLOW = FLOOR_Y + 0.30
local LAYER_SEAM = FLOOR_Y + 0.36
local LAYER_CORRIDOR = FLOOR_Y + 0.44
local LAYER_ARROW = FLOOR_Y + 0.52
local LAYER_CONTAM = FLOOR_Y + 0.58
local CHAMBER_TOP = FLOOR_Y + 0.74 -- Gegner-Plattform-Oberkante (deckt alle Decals)

local CORRIDOR_MIN_Z = -85
local CORRIDOR_MAX_Z = 130 -- inkl. Egg-Catch-Alkoven (+Z Seite)
local FLOOR_CENTER_Z = (CORRIDOR_MIN_Z + CORRIDOR_MAX_Z) / 2
local FLOOR_SIZE_Z = CORRIDOR_MAX_Z - CORRIDOR_MIN_Z
local BARRIER_SIZE_Z = FLOOR_SIZE_Z + 8
local BACTERIA_PATH_Z = 0
local BACTERIA_CEILING_LIFT = 10
local BACTERIA_LEFT_LIMIT_Z = -38
local BACTERIA_RIGHT_LIMIT_Z = 38

-- ---- Pro-Area-Themen ------------------------------------------------------
-- Jede Area bekommt eine sichtbar eigene Identitaet (Prop-Set, Akzentfarbe,
-- Kontaminations-Staerke, Wandtext, Seiten-Objekt) -- nicht nur Farbwechsel.
-- contam: 0..1 organische Verschmutzung; clean->gefaehrlich pro Tiefe.
-- sideProp: Bestimmt das wiederkehrende Seiten-Hero-Objekt der Halle.
-- ceilingTone: Akzent fuer Decken-Lichtfilter.
local AreaThemes = {
	[1] = { id = "Bacteria", accent = Color3.fromRGB(104, 168, 116), contam = 0.14, sideProp = "BioTank", wallText = "BACTERIA LAB", hazard = "BIOHAZARD LEVEL B" },
	[2] = { id = "Infected", accent = Color3.fromRGB(120, 178, 184), contam = 0.30, sideProp = "ObsGlass", wallText = "INFECTED CELLS", hazard = "CONTAINMENT ACTIVE" },
	[3] = { id = "Mutation", accent = Color3.fromRGB(150, 116, 184), contam = 0.42, sideProp = "MutantTank", wallText = "MUTATION SECTOR", hazard = "UNSTABLE GENOME" },
	[4] = { id = "Toxic", accent = Color3.fromRGB(168, 162, 86), contam = 0.55, sideProp = "ToxicBarrel", wallText = "TOXIC STORAGE", hazard = "TOXIC HAZARD" },
	[5] = { id = "Virus", accent = Color3.fromRGB(150, 78, 78), contam = 0.40, sideProp = "QuarantinePod", wallText = "VIRUS CHAMBER", hazard = "QUARANTINE LOCKDOWN" },
	[6] = { id = "Corrupted", accent = Color3.fromRGB(150, 120, 92), contam = 0.55, sideProp = "BrokenServo", wallText = "CORRUPTED LAB", hazard = "SYSTEM FAILURE" },
	[7] = { id = "Reactor", accent = Color3.fromRGB(120, 176, 120), contam = 0.48, sideProp = "ReactorCore", wallText = "BIOHAZARD CORE", hazard = "HAZARD LEVEL A" },
	[8] = { id = "DarkMut", accent = Color3.fromRGB(118, 86, 158), contam = 0.70, sideProp = "ParasiteGrowth", wallText = "DARK MUTATION", hazard = "DO NOT ENTER" },
	[9] = { id = "Omega", accent = Color3.fromRGB(118, 126, 132), contam = 0.22, sideProp = "ControlBank", wallText = "OMEGA VIRUS LAB", hazard = "TOP SECRET" },
	[10] = { id = "Final", accent = Color3.fromRGB(168, 74, 92), contam = 0.60, sideProp = "FinalReactor", wallText = "FINAL CONTAINMENT", hazard = "CRITICAL CONTAINMENT" },
}

local function themeFor(index: number)
	return AreaThemes[index] or AreaThemes[1]
end

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
	-- Deko (nicht-kollidierend) wird von Kamera-Popper UND Maus-/Raycasts
	-- ignoriert -> die Third-Person-Kamera "klemmt" nicht mehr an dunklen
	-- Panels/Schildern fest (kein schwarzes Sicht-Feld mehr). Echte weisse
	-- Kollisionswaende blockieren die Kamera weiterhin korrekt. Klickbare
	-- Parts (EnemyCore/Egg) setzen CanQuery danach wieder auf true.
	p.CanQuery = canCollide == true
	p.Size = size
	p.Position = pos
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Akzent-Streifen: bewusst MATT (kein echtes Neon). Stark zum Labor-Grau
-- hin entsaettigt + hohe Mindest-Transparenz, damit nie ein Disco-Glow
-- entsteht -- nur dezente technische Linien.
local function neonStrip(parent, size, pos, color, transparency)
	local toned = color:Lerp(Color3.fromRGB(118, 126, 124), 0.62)
	local p = makePart(parent, "InsetAccent", size, pos, toned, Enum.Material.SmoothPlastic, false)
	p.Transparency = math.max(transparency or 0.55, 0.55)
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
		makePart(parent, "FloorLaneBase", Vector3.new(lengthX - 28, 0.08, 2.8), Vector3.new(centerX, LAYER_LANE, z), LAB_DARK, Enum.Material.SmoothPlastic, false)
		markAreaVisual(neonStrip(parent, Vector3.new(lengthX - 32, 0.14, 0.65), Vector3.new(centerX, LAYER_LANE_GLOW, z), color, 0.18), areaId)
	end
end

local function addCeilingLabLights(parent, centerX, lengthX, color)
	for _, z in ipairs({ CORRIDOR_MIN_Z + 36, FLOOR_CENTER_Z, CORRIDOR_MAX_Z - 36 }) do
		makePart(parent, "RoofDarkBeam", Vector3.new(lengthX, 0.9, 2.6), Vector3.new(centerX, FLOOR_Y + L.WallHeight - 2.2, z), LAB_DARK, Enum.Material.Metal, false)
	end
	for i = 1, 4 do
		local px = centerX - lengthX / 2 + lengthX * i / 5
		makePart(parent, "RoofCrossTruss", Vector3.new(3.5, 1.4, FLOOR_SIZE_Z - 10), Vector3.new(px, FLOOR_Y + L.WallHeight - 1.7, FLOOR_CENTER_Z), LAB_DARK, Enum.Material.Metal, false)
		for _, z in ipairs({ CORRIDOR_MIN_Z + 34, FLOOR_CENTER_Z, CORRIDOR_MAX_Z - 34 }) do
			local lightPanel = makePart(parent, "RoofLightPanel", Vector3.new(24, 0.28, 10), Vector3.new(px, FLOOR_Y + L.WallHeight - 2.95, z), Color3.fromRGB(228, 234, 232), Enum.Material.Neon, false)
			lightPanel.Transparency = 0.34
			makePart(parent, "RoofPanelFrame", Vector3.new(29, 0.22, 14), Vector3.new(px, FLOOR_Y + L.WallHeight - 2.75, z), LAB_DARK, Enum.Material.SmoothPlastic, false)
			makePart(parent, "RoofVentGrille", Vector3.new(17, 0.2, 3.2), Vector3.new(px, FLOOR_Y + L.WallHeight - 2.55, z - 8.5), Color3.fromRGB(74, 80, 82), Enum.Material.Metal, false)
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

	-- Boden. Dick genug, dass die Unterkante (FLOOR_Y - FLOOR_THICKNESS) die
	-- dunkle Baseplate (Oberkante Y=-2) als Schnittkoerper durchdringt --
	-- keine deckungsgleiche Flaeche -> kein schwarzes Z-Fighting mehr.
	local floor = makePart(
		parent,
		"LabFloor",
		Vector3.new(lengthX, FLOOR_THICKNESS, FLOOR_SIZE_Z),
		Vector3.new(centerX, FLOOR_Y - FLOOR_THICKNESS / 2, FLOOR_CENTER_Z),
		Color3.fromRGB(168, 173, 172),
		Enum.Material.SmoothPlastic,
		true
	)
	floor.TopSurface = Enum.SurfaceType.Smooth
	floor.BottomSurface = Enum.SurfaceType.Smooth

	-- Geschlossene, helle Decke: Labor statt offener Arena.
	makePart(
		parent,
		"LabCeiling",
		Vector3.new(lengthX, 2, FLOOR_SIZE_Z),
		Vector3.new(centerX, FLOOR_Y + L.WallHeight + 1, FLOOR_CENTER_Z),
		Color3.fromRGB(207, 212, 211),
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
			Color3.fromRGB(186, 192, 191),
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
	markAreaVisual(neonStrip(parent, Vector3.new(lengthX, 0.34, 0.34), Vector3.new(centerX, FLOOR_Y + 6, CORRIDOR_MIN_Z - 0.1), visualPrimary, 0.72), areaId)
	markAreaVisual(neonStrip(parent, Vector3.new(lengthX, 0.34, 0.34), Vector3.new(centerX, FLOOR_Y + 6, CORRIDOR_MAX_Z + 0.1), visualPrimary, 0.72), areaId)

	-- Boden-Leitlinie entlang des Laufwegs.
	if withCorridorLines then
		markAreaVisual(neonStrip(parent, Vector3.new(lengthX, 0.07, 1.2), Vector3.new(centerX, LAYER_CORRIDOR, 0), visualPrimary, 0.78), areaId)
		addFloorGuides(parent, centerX, lengthX, visualPrimary, areaId)
	end
	addCeilingLabLights(parent, centerX, lengthX, tint(visualPrimary, LAB_CYAN, 0.55))

	-- Decken-Lichtbalken.
	for i = 0, 2 do
		local lx = centerX - lengthX / 2 + lengthX * (i + 0.5) / 3
		local beam = makePart(
			parent,
			"CeilBeam",
			Vector3.new(12, 0.36, FLOOR_SIZE_Z - 40),
			Vector3.new(lx, FLOOR_Y + L.WallHeight - 1, FLOOR_CENTER_Z),
			Color3.fromRGB(196, 204, 202),
			Enum.Material.SmoothPlastic,
			false
		)
		markAreaVisual(beam, areaId)
		beam.Transparency = 0.28
		local pl = Instance.new("PointLight")
		pl.Brightness = 0.25
		pl.Range = 24
		pl.Color = Color3.fromRGB(218, 228, 225)
		pl.Parent = beam
	end

	return floor
end

-- ---- Gegner-Modell (Vertrag fuer EnemyService) ---------------------------
--
-- Sieben klar unterscheidbare Virus-/Mutationswesen. Jeder Typ hat eine
-- eigene Silhouette, Koerperform, Augen, Details und Partikel -- keine
-- bloss umgefaerbten Standardkoerper mehr. Der EnemyService-Vertrag bleibt
-- exakt erhalten: Model(def.Id) mit EnemyId/AreaName/IsBoss, PrimaryPart
-- "EnemyCore" (CanQuery=true) + ClickDetector "AttackClick", optionaler
-- ProximityPrompt "StartBossFight", "HealthBarBack" + "HealthBarFill"
-- (MaxWidth/FullCenterX), sowie das Info-Label. Zusaetzlich werden
-- Movement-Attribute fuer den EnemyMovementController gesetzt.

-- Mappt den Daten-Shape auf einen Virus-Archetyp + Bewegungsstil.
local ENEMY_ARCHETYPE = {
	Blob = { kind = "BacteriaCell", move = "Ground" },
	Spiky = { kind = "InfectedCell", move = "Sway" },
	Slime = { kind = "ToxicSlime", move = "Hop" },
	Crawler = { kind = "MutantCrawler", move = "Crawl" },
	Drone = { kind = "VirusDrone", move = "Hover" },
	Brute = { kind = "BiohazardBrute", move = "Ground" },
	Boss = { kind = "BossVirus", move = "Static" },
}

local function ePart(model, name, shape, size, pos, color, material, transparency)
	local p = makePart(model, name, size, pos, color, material or Enum.Material.SmoothPlastic, false)
	if shape then
		p.Shape = shape
	end
	if transparency then
		p.Transparency = transparency
	end
	return p
end

-- Klassisches Mutanten-Auge: weisse Sclera + dunkle Pupille + dezenter Glow.
local function addEye(model, center, diameter, lookColor)
	local sclera = ePart(model, "Eye", Enum.PartType.Ball, Vector3.new(diameter, diameter, diameter), center, Color3.fromRGB(238, 244, 236), Enum.Material.SmoothPlastic)
	local pupil = ePart(model, "EyePupil", Enum.PartType.Ball, Vector3.new(diameter * 0.55, diameter * 0.55, diameter * 0.5), center + Vector3.new(0, 0, -diameter * 0.42), Color3.fromRGB(16, 20, 26), Enum.Material.SmoothPlastic)
	local glow = ePart(model, "EyeGlow", Enum.PartType.Ball, Vector3.new(diameter * 0.28, diameter * 0.28, diameter * 0.28), center + Vector3.new(0, 0, -diameter * 0.55), lookColor or LAB_CYAN, Enum.Material.Neon)
	glow.Transparency = 0.15
	return sclera, pupil
end

local function buildEnemyModel(parent, def, basePos, primary, secondary)
	local model = Instance.new("Model")
	model.Name = def.Id
	model:SetAttribute("EnemyId", def.Id)
	model:SetAttribute("AreaName", def.AreaName)
	model:SetAttribute("IsBoss", def.IsBoss)
	model.Parent = parent

	local arche = ENEMY_ARCHETYPE[def.Shape] or ENEMY_ARCHETYPE.Blob
	local kind = arche.kind
	local color = tint(primary, secondary, math.min(0.6, def.EnemyIndex / 14))
	-- Bio-Tint: jeder Gegner wirkt organisch/viral, nicht nur umgefaerbt.
	local bio = tint(color, LAB_GREEN, 0.32)
	local toxic = Color3.fromRGB(150, 200, 96)
	local vein = tint(LAB_OLIVE, Color3.fromRGB(150, 60, 70), 0.4)
	local s = if def.IsBoss then 15 else (5 + def.EnemyIndex * 0.5)
	local groundY = CHAMBER_TOP

	-- Koerper-Mittelpunkt: Boden-Typen sitzen auf der Plattform, schwebende
	-- Typen darueber. corePos.Y so, dass nichts in den Boden clippt.
	local bodyR = s * 0.55
	local hover = (arche.move == "Hover")
	local coreY = groundY + bodyR + (if hover then s * 0.9 else 0.5)
	local corePos = Vector3.new(basePos.X, coreY, basePos.Z)

	-- Root / EnemyCore -- IMMER vorhanden (EnemyService-Vertrag).
	local rootSize
	if kind == "MutantCrawler" then
		rootSize = Vector3.new(s * 1.5, s * 0.85, s * 1.15)
	elseif kind == "VirusDrone" then
		rootSize = Vector3.new(s * 1.05, s * 0.95, s * 1.05)
	elseif kind == "BiohazardBrute" then
		rootSize = Vector3.new(s * 1.35, s * 1.4, s * 1.15)
	elseif kind == "BossVirus" then
		rootSize = Vector3.new(s * 1.2, s * 1.2, s * 1.2)
	else
		rootSize = Vector3.new(s * 1.1, s * 1.1, s * 1.1)
	end

	local root = makePart(model, "EnemyCore", rootSize, corePos, bio, Enum.Material.SmoothPlastic, false)
	root.CanQuery = true -- anklickbar (AttackClick ClickDetector braucht Maus-Raycast)
	root.Transparency = 0.03
	if kind ~= "MutantCrawler" and kind ~= "VirusDrone" then
		root.Shape = Enum.PartType.Ball
	end
	model.PrimaryPart = root

	-- ---------------------------------------------------------------------
	if kind == "BacteriaCell" then
		-- Runde, leicht suesse, aber mutierte Bakterienzelle: weiche Stummel-
		-- Spikes ringsum, grosse Glubschaugen, Zellkern + Plasma-Flecken.
		for i = 0, 11 do
			local a = i * math.pi / 6
			local up = (i % 3) - 1
			local dir = Vector3.new(math.cos(a), up * 0.5, math.sin(a)).Unit
			local nub = ePart(model, "CellNub", Enum.PartType.Ball, Vector3.new(s * 0.34, s * 0.34, s * 0.34), corePos + dir * bodyR * 1.05, tint(bio, toxic, 0.35), Enum.Material.SmoothPlastic)
			nub.Transparency = 0.05
		end
		local nucleus = ePart(model, "CellNucleus", Enum.PartType.Ball, Vector3.new(s * 0.5, s * 0.5, s * 0.5), corePos + Vector3.new(0, 0, -bodyR * 0.2), tint(toxic, Color3.fromRGB(225, 235, 215), 0.3), Enum.Material.Neon)
		nucleus.Transparency = 0.25
		for _, ex in ipairs({ -1, 1 }) do
			addEye(model, corePos + Vector3.new(ex * s * 0.26, s * 0.2, -bodyR * 0.95), s * 0.34, LAB_CYAN)
		end

	elseif kind == "InfectedCell" then
		-- Unregelmaessige, gefaehrlichere Zelle: Beulen, infizierte Adern,
		-- aufgeplatzte Blasen, ein grosses zorniges Auge.
		root.Color = tint(bio, vein, 0.25)
		for _, off in ipairs({
			Vector3.new(bodyR * 0.7, bodyR * 0.5, 0), Vector3.new(-bodyR * 0.6, bodyR * 0.3, bodyR * 0.4),
			Vector3.new(0, -bodyR * 0.6, bodyR * 0.6), Vector3.new(bodyR * 0.3, -bodyR * 0.4, -bodyR * 0.6),
		}) do
			local lump = ePart(model, "CellLump", Enum.PartType.Ball, Vector3.new(s * 0.6, s * 0.55, s * 0.6), corePos + off, tint(bio, vein, 0.4), Enum.Material.SmoothPlastic)
			lump.Transparency = 0.04
		end
		for i = 1, 5 do
			local a = i * 1.25
			local v = ePart(model, "InfectedVein", nil, Vector3.new(s * 0.12, s * 0.12, bodyR * 1.7), corePos + Vector3.new(math.cos(a) * bodyR * 0.4, math.sin(a) * bodyR * 0.3, 0), vein, Enum.Material.Neon)
			v.Transparency = 0.25
			v.Orientation = Vector3.new(0, math.deg(a) * 1.4, 35 * (i % 2 == 0 and 1 or -1))
		end
		for i = 1, 3 do
			local b = ePart(model, "BurstBubble", Enum.PartType.Ball, Vector3.new(s * 0.3, s * 0.3, s * 0.3), corePos + Vector3.new((i - 2) * s * 0.4, bodyR * 0.7, -bodyR * 0.5), tint(toxic, LAB_OLIVE, 0.5), Enum.Material.Glass)
			b.Transparency = 0.35
		end
		addEye(model, corePos + Vector3.new(0, s * 0.18, -bodyR * 0.98), s * 0.5, Color3.fromRGB(210, 90, 90))

	elseif kind == "ToxicSlime" then
		-- Halbtransparenter Tropfenkoerper, Giftblasen, tropfende Partikel.
		root.Material = Enum.Material.Glass
		root.Color = toxic
		root.Transparency = 0.32
		local head = ePart(model, "SlimeHead", Enum.PartType.Ball, Vector3.new(s * 0.95, s * 0.8, s * 0.95), corePos + Vector3.new(0, bodyR * 0.6, 0), toxic, Enum.Material.Glass)
		head.Transparency = 0.32
		local pool = ePart(model, "SlimePuddle", Enum.PartType.Cylinder, Vector3.new(0.4, s * 1.7, s * 1.7), Vector3.new(corePos.X, groundY + 0.22, corePos.Z), tint(toxic, LAB_OLIVE, 0.45), Enum.Material.SmoothPlastic)
		pool.Orientation = Vector3.new(0, 0, 90)
		pool.Transparency = 0.4
		for i = 1, 5 do
			local a = i * 1.3
			local bub = ePart(model, "ToxicBubble", Enum.PartType.Ball, Vector3.new(s * 0.26, s * 0.26, s * 0.26), corePos + Vector3.new(math.cos(a) * bodyR * 0.7, math.sin(i) * bodyR * 0.4, math.sin(a) * bodyR * 0.7), tint(toxic, Color3.fromRGB(225, 240, 200), 0.3), Enum.Material.Neon)
			bub.Transparency = 0.3
		end
		for _, ex in ipairs({ -1, 1 }) do
			addEye(model, corePos + Vector3.new(ex * s * 0.22, bodyR * 0.7, -bodyR * 0.7), s * 0.3, toxic)
		end
		local drip = Instance.new("ParticleEmitter")
		drip.Name = "ToxicDrip"
		drip.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		drip.Color = ColorSequence.new(toxic, tint(toxic, LAB_OLIVE, 0.6))
		drip.LightEmission = 0.2
		drip.Rate = 6
		drip.Lifetime = NumberRange.new(0.6, 1.1)
		drip.Speed = NumberRange.new(0.5, 1.5)
		drip.Acceleration = Vector3.new(0, -8, 0)
		drip.SpreadAngle = Vector2.new(25, 25)
		drip.Size = NumberSequence.new(0.4, 0.05)
		drip.Parent = root

	elseif kind == "MutantCrawler" then
		-- Kaefer-/spinnenartig: niedriger Panzer-Koerper, mehrere Beine,
		-- Ruecken-Platten, rote/lila Augen.
		root.Color = tint(LAB_TRIM, vein, 0.35)
		for _, side in ipairs({ -1, 1 }) do
			for i = 1, 4 do
				local lz = (i - 2.5) * s * 0.42
				local hip = corePos + Vector3.new(side * s * 0.55, -s * 0.05, lz)
				local foot = Vector3.new(corePos.X + side * s * 0.95, groundY + 0.3, corePos.Z + lz * 1.15)
				local mid = (hip + foot) / 2 + Vector3.new(0, s * 0.18, 0)
				local upper = ePart(model, "CrawlerLeg", nil, Vector3.new(s * 0.16, s * 0.16, (hip - mid).Magnitude * 2), mid, tint(LAB_TRIM, LAB_DARK, 0.4), Enum.Material.Metal)
				upper.CFrame = CFrame.lookAt(mid, foot)
				local knee = ePart(model, "CrawlerKnee", Enum.PartType.Ball, Vector3.new(s * 0.22, s * 0.22, s * 0.22), mid, LAB_DARK, Enum.Material.Metal)
			end
		end
		for i = 1, 4 do
			local plate = ePart(model, "CarapacePlate", nil, Vector3.new(s * (1.0 - i * 0.12), s * 0.25, s * 0.5), corePos + Vector3.new(0, bodyR * 0.55 - i * 0.05, (i - 2.5) * s * 0.34), tint(LAB_DARK, vein, 0.3), Enum.Material.Metal)
			plate.Orientation = Vector3.new(12, 0, 0)
		end
		for _, ex in ipairs({ -1, 1 }) do
			addEye(model, corePos + Vector3.new(ex * s * 0.28, s * 0.1, -bodyR * 0.95), s * 0.26, Color3.fromRGB(220, 70, 90))
		end
		ePart(model, "Mandible", nil, Vector3.new(s * 0.5, s * 0.16, s * 0.4), corePos + Vector3.new(0, -s * 0.18, -bodyR), tint(vein, LAB_DARK, 0.3), Enum.Material.Metal)

	elseif kind == "VirusDrone" then
		-- Halb Maschine, halb Virus: schwebender Kern, Scanner-Auge,
		-- Antennen, rotierende Akzent-Ringe (DNA-Wisp-Anleihen).
		root.Material = Enum.Material.Metal
		root.Color = tint(LAB_PANEL, color, 0.3)
		local shell = ePart(model, "DroneShell", Enum.PartType.Ball, Vector3.new(s * 1.25, s * 1.25, s * 1.25), corePos, tint(LAB_CYAN, color, 0.4), Enum.Material.Glass)
		shell.Transparency = 0.55
		local ring = ePart(model, "DroneRing", nil, Vector3.new(s * 1.7, s * 0.12, s * 1.7), corePos, tint(color, LAB_CYAN, 0.4), Enum.Material.Neon)
		ring.Shape = Enum.PartType.Cylinder
		ring.Orientation = Vector3.new(0, 0, 90)
		ring.Transparency = 0.3
		local scanner = ePart(model, "ScannerEye", Enum.PartType.Ball, Vector3.new(s * 0.55, s * 0.55, s * 0.55), corePos + Vector3.new(0, 0, -bodyR * 0.95), Color3.fromRGB(120, 220, 230), Enum.Material.Neon)
		scanner.Transparency = 0.1
		for _, side in ipairs({ -1, 1 }) do
			local ant = ePart(model, "DroneAntenna", nil, Vector3.new(s * 0.08, s * 0.9, s * 0.08), corePos + Vector3.new(side * s * 0.35, bodyR * 1.1, 0), LAB_DARK, Enum.Material.Metal)
			ant.Orientation = Vector3.new(0, 0, side * 18)
			ePart(model, "AntennaTip", Enum.PartType.Ball, Vector3.new(s * 0.18, s * 0.18, s * 0.18), corePos + Vector3.new(side * s * 0.5, bodyR * 1.5, 0), LAB_CYAN, Enum.Material.Neon)
			ePart(model, "DroneThruster", nil, Vector3.new(s * 0.28, s * 0.28, s * 0.55), corePos + Vector3.new(side * s * 0.7, -s * 0.2, s * 0.3), LAB_DARK, Enum.Material.Metal)
		end
		local sl = Instance.new("PointLight")
		sl.Brightness = 0.7
		sl.Range = 14
		sl.Color = LAB_CYAN
		sl.Parent = scanner

	elseif kind == "BiohazardBrute" then
		-- Grosser, breiter Mini-Boss-Koerper, schwere Arme, Biohazard-Symbol,
		-- pochender Kern.
		root.Color = tint(bio, LAB_OLIVE, 0.4)
		local chest = ePart(model, "BruteChest", nil, Vector3.new(s * 1.5, s * 1.1, s * 1.0), corePos + Vector3.new(0, bodyR * 0.1, 0), tint(bio, LAB_OLIVE, 0.45), Enum.Material.SmoothPlastic)
		for _, side in ipairs({ -1, 1 }) do
			local shoulder = ePart(model, "BruteShoulder", Enum.PartType.Ball, Vector3.new(s * 0.7, s * 0.7, s * 0.7), corePos + Vector3.new(side * s * 0.85, bodyR * 0.4, 0), tint(bio, vein, 0.35), Enum.Material.SmoothPlastic)
			local arm = ePart(model, "BruteArm", nil, Vector3.new(s * 0.45, s * 1.25, s * 0.45), corePos + Vector3.new(side * s * 0.95, -s * 0.25, 0), tint(bio, LAB_OLIVE, 0.5), Enum.Material.SmoothPlastic)
			arm.Orientation = Vector3.new(0, 0, side * 8)
			ePart(model, "BruteFist", Enum.PartType.Ball, Vector3.new(s * 0.6, s * 0.6, s * 0.6), corePos + Vector3.new(side * s * 1.05, -s * 0.95, 0), tint(LAB_DARK, vein, 0.3), Enum.Material.SmoothPlastic)
		end
		local core = ePart(model, "BruteCore", Enum.PartType.Ball, Vector3.new(s * 0.6, s * 0.6, s * 0.6), corePos + Vector3.new(0, bodyR * 0.1, -bodyR * 0.7), toxic, Enum.Material.Neon)
		core.Transparency = 0.15
		local bio1 = ePart(model, "BiohazardMark", nil, Vector3.new(s * 0.7, s * 0.7, 0.2), corePos + Vector3.new(0, bodyR * 0.6, -bodyR * 0.98), LAB_WARNING_YELLOW, Enum.Material.SmoothPlastic)
		bio1.Transparency = 0.1
		for _, ex in ipairs({ -1, 1 }) do
			addEye(model, corePos + Vector3.new(ex * s * 0.24, bodyR * 0.55, -bodyR * 0.85), s * 0.26, Color3.fromRGB(225, 95, 80))
		end

	else -- BossVirus
		-- Imposanter Endgegner: grosser Kapsid mit Spike-Proteinen, DNA-
		-- Spirale, leuchtender Kern, Biohazard-Akzentring (kein Disco).
		root.Material = Enum.Material.Glass
		root.Color = tint(bio, color, 0.4)
		root.Transparency = 0.32
		local capsidR = bodyR * 1.05
		local nucleus = ePart(model, "BossNucleus", Enum.PartType.Ball, Vector3.new(s * 0.9, s * 0.9, s * 0.9), corePos, tint(toxic, Color3.fromRGB(235, 240, 220), 0.25), Enum.Material.Neon)
		nucleus.Transparency = 0.12
		local spikeDirs = {
			Vector3.new(0, 1, 0), Vector3.new(0, -1, 0), Vector3.new(1, 0.4, 0), Vector3.new(-1, 0.4, 0),
			Vector3.new(0, 0.4, 1), Vector3.new(0, 0.4, -1), Vector3.new(1, -0.4, 1), Vector3.new(-1, -0.4, 1),
			Vector3.new(1, -0.4, -1), Vector3.new(-1, -0.4, -1), Vector3.new(0.8, 0.9, 0.8), Vector3.new(-0.8, 0.9, -0.8),
			Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
		}
		for _, d in ipairs(spikeDirs) do
			local u = d.Unit
			local sp = corePos + u * capsidR
			local stalk = ePart(model, "BossSpike", nil, Vector3.new(s * 0.14, s * 0.7, s * 0.14), sp, tint(color, LAB_TRIM, 0.3), Enum.Material.SmoothPlastic)
			local upv = if math.abs(u.Y) > 0.99 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
			stalk.CFrame = CFrame.lookAt(sp, sp + u, upv) * CFrame.Angles(math.rad(90), 0, 0)
			ePart(model, "BossSpikeTip", Enum.PartType.Ball, Vector3.new(s * 0.3, s * 0.3, s * 0.3), corePos + u * (capsidR + s * 0.35), tint(color, Color3.fromRGB(225, 230, 215), 0.4), Enum.Material.SmoothPlastic)
		end
		for i = 0, 13 do
			local t = i / 13 * math.pi * 2.4
			local r = s * 0.95
			for _, sgn in ipairs({ 1, -1 }) do
				ePart(model, "BossHelix", Enum.PartType.Ball, Vector3.new(s * 0.18, s * 0.18, s * 0.18), corePos + Vector3.new(sgn * math.cos(t) * r, (i / 13 - 0.5) * s * 2.0, sgn * math.sin(t) * r), tint(LAB_CYAN, toxic, i % 2), Enum.Material.Neon)
			end
		end
		for _, ex in ipairs({ -1, 1 }) do
			addEye(model, corePos + Vector3.new(ex * s * 0.3, s * 0.18, -capsidR * 0.92), s * 0.42, Color3.fromRGB(225, 90, 90))
		end
		-- Glow-Ring statt zweiter Kollisions-Plattform (BossChamberPad ist
		-- die echte Stand-Plattform). Name "BossPad" -> bleibt sichtbar.
		local ring = ePart(model, "BossPad", Enum.PartType.Cylinder, Vector3.new(0.5, s * 2.6, s * 2.6), Vector3.new(basePos.X, CHAMBER_TOP + 1.25, basePos.Z), color, Enum.Material.Neon)
		ring.Orientation = Vector3.new(0, 0, 90)
		ring.Transparency = 0.35
		local gl = Instance.new("PointLight")
		gl.Brightness = 1.6
		gl.Range = 30
		gl.Color = tint(color, LAB_CYAN, 0.4)
		gl.Parent = nucleus
	end

	-- Sehr dezente "lebende Probe"-Partikel fuer alle (kein Spam).
	if kind ~= "ToxicSlime" then
		local aura = Instance.new("ParticleEmitter")
		aura.Name = "VirusAura"
		aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		aura.Color = ColorSequence.new(tint(bio, toxic, 0.4), bio)
		aura.LightEmission = 0.15
		aura.Rate = if def.IsBoss then 5 else 2
		aura.Lifetime = NumberRange.new(1.0, 1.8)
		aura.Speed = NumberRange.new(0.3, 0.9)
		aura.SpreadAngle = Vector2.new(40, 40)
		aura.Size = NumberSequence.new(0.3, 0.03)
		aura.Parent = root
	end

	-- ---- Bewegungs-Attribute (EnemyMovementController) ------------------
	-- Home = Plattform-Mitte. Reichweiten klein genug, dass der Gegner auf
	-- seiner eigenen Plattform bleibt (Spacing 32, Glaswaende bei z+/-25)
	-- und nie in Spawn/andere Areas oder durch Waende laeuft.
	local ranges = {
		Ground = { rx = 7, rz = 12, sp = 3.2, bob = 0.45 },
		Sway = { rx = 5, rz = 14, sp = 2.4, bob = 0.3 },
		Hop = { rx = 6, rz = 11, sp = 3.6, bob = 2.6 },
		Crawl = { rx = 9, rz = 15, sp = 6.5, bob = 0.25 },
		Hover = { rx = 8, rz = 14, sp = 3.4, bob = 1.9 },
		Static = { rx = 0, rz = 0, sp = 0, bob = 0 },
	}
	local mv = ranges[arche.move] or ranges.Ground
	model:SetAttribute("MoveStyle", arche.move)
	model:SetAttribute("HomeX", corePos.X)
	model:SetAttribute("HomeY", corePos.Y)
	model:SetAttribute("HomeZ", corePos.Z)
	model:SetAttribute("MoveRangeX", mv.rx)
	model:SetAttribute("MoveRangeZ", mv.rz)
	model:SetAttribute("MoveSpeed", mv.sp)
	model:SetAttribute("BobAmp", mv.bob)
	model:SetAttribute("EnemyKind", kind)

	-- Health-Bar (Vertrag mit EnemyService.updateEnemy).
	local barScale = if def.IsBoss then 1.9 else 1
	local barY = corePos.Y + rootSize.Y / 2 + (if def.IsBoss then 5 else 3)
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
		if def.IsBoss then 60 else 34,
		UDim2.fromOffset(if def.IsBoss then 280 else 190, if def.IsBoss then 104 else 76),
		Vector3.new(0, rootSize.Y / 2 + 5, 0)
	)

	return model
end

-- ---- PWR-Border zwischen zwei Gegnern ------------------------------------

local function buildBorder(parent, def, x, primary)
	local model = Instance.new("Model")
	model.Name = "Border_" .. def.Id
	model.Parent = parent

	local borderZ = BACTERIA_RIGHT_LIMIT_Z - BACTERIA_LEFT_LIMIT_Z
	local centerZ = (BACTERIA_LEFT_LIMIT_Z + BACTERIA_RIGHT_LIMIT_Z) / 2
	local height = 12
	local zMin = BACTERIA_LEFT_LIMIT_Z
	local zMax = BACTERIA_RIGHT_LIMIT_Z

	-- Schmale Labor-Sicherheitsbarriere (Glas/Neon), nicht riesig.
	for _, z in ipairs({ zMin, zMax }) do
		makePart(model, "BorderPillar", Vector3.new(2, height + 4, 2), Vector3.new(x, FLOOR_Y + (height + 4) / 2, z), LAB_TRIM, Enum.Material.Metal, true)
	end
	makePart(model, "BorderBeam", Vector3.new(2.4, 1.4, borderZ + 4), Vector3.new(x, FLOOR_Y + height + 2, centerZ), LAB_TRIM, Enum.Material.Metal, true)
	for _, z in ipairs({ zMin + 8, zMax - 8 }) do
		neonStrip(model, Vector3.new(0.35, height + 1.5, 0.35), Vector3.new(x, FLOOR_Y + (height + 1.5) / 2, z), primary, 0.24)
	end

	-- Glas-/Neon-Wand = Trigger (CanCollide=false, BorderService prueft PWR).
	local wall = makePart(model, "BorderField", Vector3.new(1.2, height, borderZ), Vector3.new(x, FLOOR_Y + height / 2 + 0.5, centerZ), ACCESS_LOCKED, Enum.Material.ForceField, false)
	wall.Transparency = 0.5
	wall.CanTouch = true
	wall:SetAttribute("RequiredPower", def.RequiredGatePower)

	local sign = makePart(model, "BorderSign", Vector3.new(11, 3.2, 0.55), Vector3.new(x, FLOOR_Y + height + 3.2, centerZ), LAB_DARK, Enum.Material.SmoothPlastic, false)
	label(
		sign,
		string.format("Required:\n%s PWR", NumberFormatter.format(def.RequiredGatePower)),
		ACCESS_LOCKED_SOFT,
		42,
		UDim2.fromOffset(170, 54),
		Vector3.new(0, 0, 0)
	)
end

-- ---- Labor-Luke / Gate zwischen Training und Gegner-Halle -----------------

local function buildTunnelGate(parent, area, x, requiredPower)
	local model = Instance.new("Model")
	model.Name = "Gate_" .. area.id
	model:SetAttribute("AreaId", area.id)
	model.Parent = parent

	local height = 16
	local gateWidthZ = 86
	local centerZ = BACTERIA_PATH_Z
	local primary = if area.index == 1 then ACCESS_UNLOCKED else ACCESS_LOCKED
	local primarySoft = if area.index == 1 then ACCESS_UNLOCKED_SOFT else ACCESS_LOCKED_SOFT

	for _, z in ipairs({ centerZ - gateWidthZ / 2, centerZ + gateWidthZ / 2 }) do
		local col = makePart(model, "TunnelGatePillar", Vector3.new(5, height, 5), Vector3.new(x, FLOOR_Y + height / 2, z), LAB_WHITE, Enum.Material.Metal, true)
		local inwardZ = if z < centerZ then 2.9 else -2.9
		neonStrip(model, Vector3.new(0.45, height - 4, 0.45), col.Position + Vector3.new(0, 0, inwardZ), primary, 0.36)
	end

	makePart(model, "TunnelGateTopBeam", Vector3.new(7, 4, gateWidthZ + 8), Vector3.new(x, FLOOR_Y + height + 1.5, centerZ), LAB_WHITE, Enum.Material.Metal, true)
	local scan = makePart(model, "TunnelGateScanField", Vector3.new(0.8, height - 3, gateWidthZ - 9), Vector3.new(x, FLOOR_Y + (height - 3) / 2 + 0.8, centerZ), primary, Enum.Material.ForceField, false)
	scan.Transparency = 0.72
	scan.CanTouch = true
	scan:SetAttribute("RequiredPower", requiredPower)
	scan:SetAttribute("RequiredRebirth", 0)
	scan:SetAttribute("AreaName", area.displayName)
	scan:SetAttribute("AreaId", area.id)

	local panel = makePart(model, "TunnelGateControlPanel", Vector3.new(5.5, 6, 1), Vector3.new(x - 4.5, FLOOR_Y + 4.5, centerZ - gateWidthZ / 2 - 8), LAB_DARK, Enum.Material.Metal, true)
	neonStrip(model, Vector3.new(3.8, 3.8, 0.25), panel.Position + Vector3.new(0, 0.35, -0.65), primary, 0.3)
	label(panel, if area.index == 1 then "OPEN\n0 PWR" else "LOCKED\nPWR", primarySoft, 32, UDim2.fromOffset(90, 46), Vector3.new(0, 2.2, 0))

	local sign = makePart(model, "TunnelGateSign", Vector3.new(20, 5, 0.65), Vector3.new(x, FLOOR_Y + height + 5, centerZ), LAB_DARK, Enum.Material.SmoothPlastic, false)
	label(
		sign,
		string.format("%s\nRequired: %s PWR", string.upper(area.displayName), NumberFormatter.format(requiredPower)),
		primarySoft,
		55,
		UDim2.fromOffset(280, 70),
		Vector3.new(0, 0, 0)
	)
end

local function buildGate(parent, area, x, requiredPower)
	buildTunnelGate(parent, area, x, requiredPower)
end

-- ---- Gegner-Tunnel Struktur ----------------------------------------------

-- Designt die Wand DIREKT um den Mob/die Gegner-Zelle -- fuer ALLE Areas,
-- mit Thema-Akzent und mit der Tiefe steigender Kontamination. Cell 10
-- (Boss) bekommt einen klar staerkeren Containment-Look.
local function addBacteriaCellWallDetails(parent, def, basePos, primary)
	local cell = def.EnemyIndex
	local theme = themeFor(def.AreaIndex)
	local accent = theme.accent
	local contam = theme.contam
	local isBoss = def.IsBoss == true
	local x = basePos.X
	local leftWallZ = BACTERIA_LEFT_LIMIT_Z + 1.9
	local rightWallZ = BACTERIA_RIGHT_LIMIT_Z - 1.9
	local panelColor = tint(Color3.fromRGB(30, 35, 36), accent, 0.12)
	local frameColor = Color3.fromRGB(86, 92, 92)
	local cellText = string.format("CELL %02d", cell)

	-- Rueckwand-Panel direkt hinter dem Mob (Zellnummer + Area-Thema).
	local rearW = if isBoss then 24 else 18
	local rearH = if isBoss then 11 else 8
	local rearPanel = makePart(parent, "CellRearWallPanel", Vector3.new(rearW, rearH, 0.45), Vector3.new(x, FLOOR_Y + (if isBoss then 11 else 10), rightWallZ), panelColor, Enum.Material.Metal, false)
	label(
		rearPanel,
		(if isBoss then "⚠ BOSS CONTAINMENT ⚠\n" else cellText .. "\n") .. theme.wallText,
		tint(accent, Color3.fromRGB(222, 228, 218), 0.55),
		if isBoss then 50 else 34,
		UDim2.fromOffset(if isBoss then 230 else 150, if isBoss then 70 else 52),
		Vector3.new(0, 0, 0)
	)
	makePart(parent, "CellRearFrameTop", Vector3.new(rearW + 2, 0.55, 0.65), Vector3.new(x, FLOOR_Y + (if isBoss then 17 else 14.35), rightWallZ), frameColor, Enum.Material.Metal, false)
	makePart(parent, "CellRearFrameBottom", Vector3.new(rearW + 2, 0.55, 0.65), Vector3.new(x, FLOOR_Y + 5.65, rightWallZ), frameColor, Enum.Material.Metal, false)

	-- Biohazard-Schild mit Thema-spezifischem Warntext.
	local bioSign = makePart(parent, "CellBiohazardSign", Vector3.new(9, 3.4, 0.5), Vector3.new(x - 8.6, FLOOR_Y + 16.6, rightWallZ), Color3.fromRGB(58, 54, 38), Enum.Material.SmoothPlastic, false)
	label(bioSign, theme.hazard, LAB_WARNING_YELLOW, 28, UDim2.fromOffset(120, 32), Vector3.new(0, 0, 0))

	-- Linke Seitenwand: Tech-Panel.
	local leftPanel = makePart(parent, "CellLeftTechPanel", Vector3.new(0.55, 6, 11), Vector3.new(x - 8.5, FLOOR_Y + 8.2, leftWallZ), LAB_DARK, Enum.Material.Metal, false)
	makePart(parent, "CellLeftPanelStripe", Vector3.new(0.25, 0.7, 9), leftPanel.Position + Vector3.new(-0.35, 2.4, 0), LAB_WARNING_YELLOW, Enum.Material.SmoothPlastic, false).Transparency = 0.28
	label(leftPanel, "CONTAINMENT", Color3.fromRGB(210, 216, 212), 28, UDim2.fromOffset(120, 34), Vector3.new(0, 0, 0))

	-- Rechte Seitenwand: Kontroll-Modul + Status-/Warnlichter.
	local rightModule = makePart(parent, "CellRightControlModule", Vector3.new(0.6, 5.2, 8), Vector3.new(x + 9.5, FLOOR_Y + 7.6, rightWallZ), Color3.fromRGB(42, 48, 50), Enum.Material.Metal, false)
	makePart(parent, "CellGreenStatusLight", Vector3.new(0.3, 1.1, 1.1), rightModule.Position + Vector3.new(0.42, 1.35, -2.1), LAB_GREEN, Enum.Material.SmoothPlastic, false).Shape = Enum.PartType.Ball
	if isBoss or cell >= 5 or def.AreaIndex >= 5 then
		makePart(parent, "CellRedWarningLight", Vector3.new(0.3, 1, 1), rightModule.Position + Vector3.new(0.42, 1.35, 2.1), LAB_WARNING_RED, Enum.Material.SmoothPlastic, false).Shape = Enum.PartType.Ball
	end

	-- Wand-Probenbehaelter (Thema-Akzent).
	local sample = makePart(parent, "CellWallSampleVial", Vector3.new(0.55, 4.8, 2.1), Vector3.new(x + 10.6, FLOOR_Y + 5.1, leftWallZ), tint(LAB_OLIVE, accent, 0.35), Enum.Material.Glass, false)
	sample.Transparency = 0.5
	makePart(parent, "CellVialCap", Vector3.new(0.65, 0.55, 2.4), sample.Position + Vector3.new(0, 2.65, 0), frameColor, Enum.Material.Metal, false)
	makePart(parent, "CellVialBase", Vector3.new(0.65, 0.55, 2.4), sample.Position + Vector3.new(0, -2.65, 0), frameColor, Enum.Material.Metal, false)

	-- Lueftungsgitter.
	local vent = makePart(parent, "CellVentGrille", Vector3.new(9, 2.2, 0.35), Vector3.new(x + 7.5, FLOOR_Y + 17.6, rightWallZ), Color3.fromRGB(66, 72, 74), Enum.Material.Metal, false)
	for i = -2, 2 do
		makePart(parent, "CellVentSlat", Vector3.new(7.4, 0.14, 0.2), vent.Position + Vector3.new(0, i * 0.38, 0.28), LAB_DARK, Enum.Material.Metal, false)
	end

	-- Boss-Zelle (Cell 10): schwerer Rahmen + Warnbalken + Alarmlichter.
	if isBoss then
		for _, sx in ipairs({ x - rearW / 2 - 1, x + rearW / 2 + 1 }) do
			makePart(parent, "BossCellFramePost", Vector3.new(1.4, rearH + 4, 1.2), Vector3.new(sx, FLOOR_Y + (rearH + 4) / 2, rightWallZ), LAB_DARK, Enum.Material.Metal, false)
		end
		makePart(parent, "BossHazardStripe", Vector3.new(rearW, 0.7, 0.3), Vector3.new(x, FLOOR_Y + 4.4, rightWallZ - 0.4), LAB_WARNING_YELLOW, Enum.Material.SmoothPlastic, false).Transparency = 0.2
		for _, sx in ipairs({ x - 6, x + 6 }) do
			makePart(parent, "BossWarnLight", Vector3.new(1.1, 1.1, 0.3), Vector3.new(sx, FLOOR_Y + rearH + 2.4, rightWallZ), LAB_WARNING_RED, Enum.Material.Neon, false).Shape = Enum.PartType.Ball
		end
	end

	-- Kontamination skaliert mit der Tiefe: frueh clean, spaet organisch.
	if contam >= 0.25 or cell % 2 == 0 then
		local drip = makePart(parent, "CellWallBiofilmDrip", Vector3.new(2.6, 4 + contam * 5, 0.28), Vector3.new(x - 3.8, FLOOR_Y + 7.3, rightWallZ - 0.35), LAB_OLIVE, Enum.Material.SmoothPlastic, false)
		drip.Transparency = math.clamp(0.62 - contam * 0.3, 0.32, 0.62)
	end
	if contam >= 0.4 or cell % 3 == 0 then
		for i = 1, (if contam >= 0.55 then 4 else 3) do
			local spot = makePart(parent, "CellBacteriaSpot", Vector3.new(1.1 + i * 0.25, 1.1 + i * 0.25, 0.22), Vector3.new(x - 8 + i * 2.1, FLOOR_Y + 4.2 + i * 0.8, rightWallZ - 0.35), LAB_OLIVE, Enum.Material.SmoothPlastic, false)
			spot.Shape = Enum.PartType.Ball
			spot.Transparency = math.clamp(0.6 - contam * 0.25, 0.32, 0.6)
		end
	end
	if contam >= 0.6 then
		local growth = makePart(parent, "CellOrganicGrowth", Vector3.new(3.4, 3.4, 0.5), Vector3.new(x + 4.6, FLOOR_Y + 4.4, leftWallZ + 0.3), tint(LAB_OLIVE, accent, 0.3), Enum.Material.SmoothPlastic, false)
		growth.Shape = Enum.PartType.Ball
		growth.Transparency = 0.42
	end
end

local function buildBacteriaEnemyChamber(parent, def, basePos, primary, secondary)
	local model = Instance.new("Model")
	model.Name = "BacteriaChamber_" .. def.Id
	model.Parent = parent

	local z = basePos.Z
	local theme = themeFor(def.AreaIndex)
	local accent = theme.accent
	local isBoss = def.IsBoss == true
	local chamberColor = tint(LAB_PANEL, accent, 0.16)
	-- Plattform: Oberkante = CHAMBER_TOP (ueber ALLEN Boden-Decals),
	-- Unterkante tief im Boden versenkt -> Schnittkoerper, keine
	-- deckungsgleiche Flaeche mit dem Boden, kein schwarzes Flackern.
	local platform = makePart(model, "BacteriaChamberPlatform", Vector3.new(28, 1.4, 52), Vector3.new(basePos.X, CHAMBER_TOP - 0.7, z), chamberColor, Enum.Material.SmoothPlastic, true)
	platform.Transparency = 0
	makePart(model, "ChamberSteelInset", Vector3.new(20, 0.07, 34), Vector3.new(basePos.X, CHAMBER_TOP + 0.1, z), Color3.fromRGB(86, 92, 92), Enum.Material.Metal, false).Transparency = 0.18

	-- Boss-Zelle: eigene erhoehte Plattform + Rahmen (klar besonderer Look).
	if isBoss then
		local bossPad = makePart(model, "BossChamberPad", Vector3.new(22, 1.6, 30), Vector3.new(basePos.X, CHAMBER_TOP + 0.1, z), tint(LAB_DARK, accent, 0.18), Enum.Material.Metal, true)
		bossPad.Transparency = 0
		makePart(model, "BossChamberHazardEdge", Vector3.new(24, 0.1, 32), Vector3.new(basePos.X, CHAMBER_TOP + 1.05, z), LAB_WARNING_YELLOW, Enum.Material.SmoothPlastic, false).Transparency = 0.4
		for _, cxo in ipairs({ -10.5, 10.5 }) do
			for _, czo in ipairs({ -15, 15 }) do
				makePart(model, "BossCornerPillar", Vector3.new(1.6, 16, 1.6), Vector3.new(basePos.X + cxo, FLOOR_Y + 8, z + czo), LAB_DARK, Enum.Material.Metal, false)
			end
		end
	end

	for _, dz in ipairs({ -25, 25 }) do
		local rail = makePart(model, "GlassSideWall", Vector3.new(24, 7, 0.55), Vector3.new(basePos.X, FLOOR_Y + 4, z + dz), tint(LAB_CYAN, accent, 0.4), Enum.Material.Glass, false)
		rail.Transparency = 0.76
		neonStrip(model, Vector3.new(21, 0.14, 0.2), Vector3.new(basePos.X, FLOOR_Y + 7.7, z + dz), tint(accent, LAB_CYAN, 0.35), 0.74)
	end

	-- Plattform-Rand-LEDs LIEGEN AUF der Plattform (ueber CHAMBER_TOP),
	-- nicht darunter -> sichtbar und ohne Z-Fighting.
	for _, xOff in ipairs({ -11.5, 11.5 }) do
		neonStrip(model, Vector3.new(0.28, 0.07, 44), Vector3.new(basePos.X + xOff, CHAMBER_TOP + 0.05, z), tint(primary, LAB_CYAN, 0.28), 0.72)
	end
	for _, zOff in ipairs({ -23.5, 23.5 }) do
		neonStrip(model, Vector3.new(21, 0.07, 0.28), Vector3.new(basePos.X, CHAMBER_TOP + 0.05, z + zOff), tint(primary, LAB_GREEN, 0.25), 0.72)
	end

	local cellSign = makePart(model, "CellFloorLabel", Vector3.new(13, 0.1, 4), Vector3.new(basePos.X, CHAMBER_TOP + 0.13, z - 16), LAB_DARK, Enum.Material.SmoothPlastic, false)
	cellSign.Transparency = 0.12
	label(
		cellSign,
		string.format("CELL %02d", def.EnemyIndex),
		ACCESS_UNLOCKED_SOFT,
		24,
		UDim2.fromOffset(100, 28),
		Vector3.new(0, 1.4, 0)
	)

	local infoZ = if def.EnemyIndex % 2 == 1 then z - 28 else z + 28
	local info = makePart(model, "ChamberInfoPanel", Vector3.new(10, 4.8, 0.5), Vector3.new(basePos.X - 9, FLOOR_Y + 4.8, infoZ), LAB_DARK, Enum.Material.SmoothPlastic, false)
	label(
		info,
		string.format("CELL %02d • %s\n%s", def.EnemyIndex, theme.wallText, string.upper(def.DisplayName)),
		tint(accent, ACCESS_UNLOCKED_SOFT, 0.5),
		32,
		UDim2.fromOffset(150, 56),
		Vector3.new(0, 0, 0)
	)

	if isBoss then
		-- Boss-Backdrop: grosse Containment-/Reaktor-Kapsel hinter dem Boss.
		local tank = makePart(model, "BossSpecimenTank", Vector3.new(9, 16, 9), Vector3.new(basePos.X + 9, FLOOR_Y + 8, z - 19), tint(accent, LAB_OLIVE, 0.3), Enum.Material.Glass, false)
		tank.Shape = Enum.PartType.Cylinder
		tank.Transparency = 0.42
		makePart(model, "BossTankBase", Vector3.new(10.5, 1, 10.5), Vector3.new(basePos.X + 9, FLOOR_Y + 0.7, z - 19), LAB_DARK, Enum.Material.Metal, true).Shape = Enum.PartType.Cylinder
		makePart(model, "BossTankTop", Vector3.new(10.5, 1, 10.5), Vector3.new(basePos.X + 9, FLOOR_Y + 16, z - 19), LAB_DARK, Enum.Material.Metal, false).Shape = Enum.PartType.Cylinder
		local bcore = makePart(model, "BossTankCore", Vector3.new(4, 4, 4), Vector3.new(basePos.X + 9, FLOOR_Y + 8, z - 19), tint(accent, Color3.fromRGB(225, 230, 220), 0.25), Enum.Material.Neon, false)
		bcore.Shape = Enum.PartType.Ball
		local bl = Instance.new("PointLight")
		bl.Brightness = 0.6
		bl.Range = 16
		bl.Color = tint(accent, Color3.fromRGB(220, 225, 215), 0.4)
		bl.Parent = bcore
	elseif def.EnemyIndex % 2 == 0 then
		local tank = makePart(model, "SpecimenCylinder", Vector3.new(5, 8, 5), Vector3.new(basePos.X + 8, FLOOR_Y + 4.1, z - 18), tint(LAB_OLIVE, accent, 0.32), Enum.Material.Glass, false)
		tank.Shape = Enum.PartType.Cylinder
		tank.Orientation = Vector3.new(0, 0, 90)
		tank.Transparency = 0.46
		neonStrip(model, Vector3.new(6, 0.12, 6), Vector3.new(basePos.X + 8, FLOOR_Y + 8.4, z - 18), accent, 0.72)
	else
		local console = makePart(model, "MiniConsole", Vector3.new(6, 2.5, 4), Vector3.new(basePos.X + 8, FLOOR_Y + 1.45, z + 18), LAB_DARK, Enum.Material.Metal, false)
		console.Orientation = Vector3.new(0, 0, -8)
		neonStrip(model, Vector3.new(4.6, 0.12, 2.8), console.Position + Vector3.new(0, 1.4, 0), accent, 0.72)
	end

	if def.EnemyIndex % 3 == 0 then
		local residue = makePart(model, "ControlledBiofilmPatch", Vector3.new(7, 0.05, 4.5), Vector3.new(basePos.X - 5, CHAMBER_TOP + 0.04, z + 13), LAB_OLIVE, Enum.Material.SmoothPlastic, false)
		residue.Transparency = 0.4
	elseif def.EnemyIndex % 4 == 0 then
		local drip = makePart(model, "WallContaminationDrip", Vector3.new(0.35, 4.5, 2.4), Vector3.new(basePos.X + 11.5, FLOOR_Y + 4.3, z - 25), LAB_OLIVE, Enum.Material.SmoothPlastic, false)
		drip.Transparency = 0.42
	end

	addBacteriaCellWallDetails(model, def, basePos, primary)
end

local function liftBacteriaLabCeiling(parent)
	for _, child in ipairs(parent:GetChildren()) do
		if not child:IsA("BasePart") then
			continue
		end

		if child.Name == "LabWallLeft" or child.Name == "LabWallRight" then
			local newHeight = L.WallHeight + BACTERIA_CEILING_LIFT
			child.Size = Vector3.new(child.Size.X, newHeight, child.Size.Z)
			child.Position = Vector3.new(child.Position.X, FLOOR_Y + newHeight / 2, child.Position.Z)
		elseif child.Name == "LabCeiling" then
			child.Position += Vector3.new(0, BACTERIA_CEILING_LIFT, 0)
			child.Color = Color3.fromRGB(224, 230, 232)
		elseif child.Name == "CeilingSupport" then
			child.Position += Vector3.new(0, BACTERIA_CEILING_LIFT, 0)
			child.Size = Vector3.new(child.Size.X, 0.7, child.Size.Z - 36)
			child.Transparency = 0.2
		elseif child.Name == "CeilingPanel" then
			child.Position += Vector3.new(0, BACTERIA_CEILING_LIFT, 0)
			child.Transparency = 0.12
		elseif child.Name == "RoofDarkBeam" or child.Name == "RoofCrossTruss" or child.Name == "RoofPanelFrame" then
			child.Position += Vector3.new(0, BACTERIA_CEILING_LIFT, 0)
			child.Transparency = 0.22
		elseif child.Name == "RoofLightPanel" then
			child.Position += Vector3.new(0, BACTERIA_CEILING_LIFT, 0)
			child.Transparency = 0.42
		elseif child.Name == "CeilBeam" then
			child.Position += Vector3.new(0, BACTERIA_CEILING_LIFT, 0)
			child.Size = Vector3.new(10, 0.35, FLOOR_SIZE_Z - 52)
			child.Transparency = 0.72
			for _, light in ipairs(child:GetChildren()) do
				if light:IsA("PointLight") then
					light.Brightness = 0.35
					light.Range = 28
				end
			end
		end
	end
end

-- Wiederkehrendes Thema-Hero-Objekt der Halle. Jede Area hat ein anderes
-- Set -> die Areale sehen sichtbar unterschiedlich aus (nicht nur Farbe).
-- Steht seitlich an der Hallenwand (Z = +/-30), blockiert Laufweg nicht.
local function buildThemeSideProp(deco, theme, x: number, z: number, accent: Color3)
	local id = theme.sideProp
	local function p(name, size, pos, color, mat, collide)
		return makePart(deco, name, size, pos, color, mat, collide == true)
	end

	if id == "BioTank" then
		local tank = p("SideSampleTank", Vector3.new(8, 13, 8), Vector3.new(x, FLOOR_Y + 6.5, z), tint(LAB_OLIVE, accent, 0.22), Enum.Material.Glass)
		tank.Shape = Enum.PartType.Cylinder
		tank.Orientation = Vector3.new(0, 0, 90)
		tank.Transparency = 0.5
		p("TankBase", Vector3.new(9, 0.7, 9), Vector3.new(x, FLOOR_Y + 0.5, z), LAB_TRIM, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		p("TankTop", Vector3.new(9, 0.7, 9), Vector3.new(x, FLOOR_Y + 12.6, z), LAB_TRIM, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
	elseif id == "ObsGlass" then
		local cap = p("ObsCapsule", Vector3.new(6, 15, 6), Vector3.new(x, FLOOR_Y + 8, z), tint(LAB_CYAN, accent, 0.35), Enum.Material.Glass)
		cap.Shape = Enum.PartType.Cylinder
		cap.Orientation = Vector3.new(0, 0, 90)
		cap.Transparency = 0.62
		p("ObsCapBase", Vector3.new(8, 1.4, 8), Vector3.new(x, FLOOR_Y + 0.7, z), LAB_DARK, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		p("ObsCapTop", Vector3.new(8, 1.4, 8), Vector3.new(x, FLOOR_Y + 15.5, z), LAB_DARK, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		local cell = p("InfectedCellSample", Vector3.new(3, 3, 3), Vector3.new(x, FLOOR_Y + 8, z), tint(accent, LAB_OLIVE, 0.3), Enum.Material.SmoothPlastic)
		cell.Shape = Enum.PartType.Ball
		cell.Transparency = 0.2
	elseif id == "MutantTank" then
		local tank = p("MutationVat", Vector3.new(9, 12, 9), Vector3.new(x, FLOOR_Y + 6.2, z), tint(accent, LAB_OLIVE, 0.4), Enum.Material.Glass)
		tank.Shape = Enum.PartType.Cylinder
		tank.Orientation = Vector3.new(0, 0, 90)
		tank.Transparency = 0.5
		p("MutationVatBase", Vector3.new(10, 1, 10), Vector3.new(x, FLOOR_Y + 0.6, z), LAB_DARK, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		local blob = p("MutantBlob", Vector3.new(4.5, 4, 4.2), Vector3.new(x, FLOOR_Y + 6, z), accent, Enum.Material.SmoothPlastic)
		blob.Shape = Enum.PartType.Ball
		blob.Transparency = 0.25
		local arm = p("MutantTendril", Vector3.new(1, 5, 1), Vector3.new(x + 1.6, FLOOR_Y + 8.5, z), tint(accent, LAB_OLIVE, 0.4), Enum.Material.SmoothPlastic)
		arm.Orientation = Vector3.new(0, 0, 28)
	elseif id == "ToxicBarrel" then
		for i, off in ipairs({ Vector3.new(0, 2, 0), Vector3.new(3.4, 2, 0.6), Vector3.new(1.6, 6, 0) }) do
			local b = p("ToxicBarrel" .. i, Vector3.new(3.6, 4, 3.6), Vector3.new(x, FLOOR_Y, z) + off, tint(LAB_WARNING_YELLOW, LAB_DARK, 0.45), Enum.Material.Metal)
			b.Shape = Enum.PartType.Cylinder
			p("BarrelHazardBand" .. i, Vector3.new(3.8, 0.7, 3.8), b.Position, LAB_WARNING_YELLOW, Enum.Material.SmoothPlastic).Shape = Enum.PartType.Cylinder
		end
		local pool = p("ToxicSpill", Vector3.new(8, 0.06, 6), Vector3.new(x, FLOOR_Y + 0.22, z + 3), tint(LAB_OLIVE, LAB_WARNING_YELLOW, 0.3), Enum.Material.SmoothPlastic)
		pool.Transparency = 0.32
	elseif id == "QuarantinePod" then
		p("QuarantinePodFrame", Vector3.new(8, 16, 1), Vector3.new(x, FLOOR_Y + 8, z), LAB_DARK, Enum.Material.Metal)
		local door = p("QuarantinePodGlass", Vector3.new(6, 13, 0.5), Vector3.new(x, FLOOR_Y + 7.5, z + 0.4), tint(accent, LAB_WHITE, 0.5), Enum.Material.Glass)
		door.Transparency = 0.55
		p("PodRedLight", Vector3.new(1, 1, 0.4), Vector3.new(x, FLOOR_Y + 15, z + 0.6), LAB_WARNING_RED, Enum.Material.Neon).Shape = Enum.PartType.Ball
		local panel = p("PodControlPanel", Vector3.new(2.4, 3, 0.6), Vector3.new(x + 5, FLOOR_Y + 4, z + 0.3), Color3.fromRGB(44, 48, 50), Enum.Material.Metal)
		label(panel, "QUARANTINE", LAB_WARNING_RED, 22, UDim2.fromOffset(70, 26), Vector3.new(0, 0, 0))
	elseif id == "BrokenServo" then
		local box = p("BrokenServoUnit", Vector3.new(7, 9, 5), Vector3.new(x, FLOOR_Y + 4.6, z), tint(LAB_TRIM, LAB_DARK, 0.4), Enum.Material.Metal)
		box.Orientation = Vector3.new(0, 0, -7)
		p("ServoBrokenPanel", Vector3.new(5, 4, 0.3), Vector3.new(x - 0.4, FLOOR_Y + 6, z + 2.6), Color3.fromRGB(30, 33, 34), Enum.Material.Metal).Orientation = Vector3.new(12, 0, -7)
		local spark = p("DeadIndicator", Vector3.new(0.9, 0.9, 0.3), Vector3.new(x + 1.5, FLOOR_Y + 8, z + 2.7), LAB_WARNING_RED, Enum.Material.SmoothPlastic)
		spark.Shape = Enum.PartType.Ball
		spark.Transparency = 0.25
		local rust = p("RustStreak", Vector3.new(3, 4, 0.18), Vector3.new(x, FLOOR_Y + 3, z + 2.7), tint(LAB_OLIVE, Color3.fromRGB(120, 70, 40), 0.5), Enum.Material.SmoothPlastic)
		rust.Transparency = 0.4
	elseif id == "ReactorCore" then
		local col = p("ReactorPillar", Vector3.new(6, 17, 6), Vector3.new(x, FLOOR_Y + 8.5, z), LAB_DARK, Enum.Material.Metal)
		col.Shape = Enum.PartType.Cylinder
		col.Orientation = Vector3.new(0, 0, 90)
		local glass = p("ReactorGlass", Vector3.new(4.4, 11, 4.4), Vector3.new(x, FLOOR_Y + 8.5, z), tint(accent, LAB_WHITE, 0.4), Enum.Material.Glass)
		glass.Shape = Enum.PartType.Cylinder
		glass.Orientation = Vector3.new(0, 0, 90)
		glass.Transparency = 0.5
		local core = p("ReactorCoreBall", Vector3.new(3.4, 3.4, 3.4), Vector3.new(x, FLOOR_Y + 8.5, z), tint(accent, Color3.fromRGB(225, 232, 220), 0.3), Enum.Material.Neon)
		core.Shape = Enum.PartType.Ball
		local rl = Instance.new("PointLight")
		rl.Brightness = 0.5
		rl.Range = 14
		rl.Color = tint(accent, Color3.fromRGB(220, 228, 215), 0.4)
		rl.Parent = core
	elseif id == "ParasiteGrowth" then
		local stalk = p("ParasiteStalk", Vector3.new(4, 14, 4), Vector3.new(x, FLOOR_Y + 7, z), tint(LAB_OLIVE, accent, 0.45), Enum.Material.SmoothPlastic)
		stalk.Shape = Enum.PartType.Cylinder
		stalk.Orientation = Vector3.new(0, 0, 90)
		stalk.Transparency = 0.08
		for i = 1, 3 do
			local pod = p("ParasitePod" .. i, Vector3.new(2.6 + i * 0.3, 2.6 + i * 0.3, 2.6 + i * 0.3), Vector3.new(x + (i - 2) * 1.6, FLOOR_Y + 3 + i * 3, z + 1.4), tint(accent, LAB_OLIVE, 0.3), Enum.Material.SmoothPlastic)
			pod.Shape = Enum.PartType.Ball
			pod.Transparency = 0.18
		end
		local goo = p("ParasiteGoo", Vector3.new(6, 0.07, 5), Vector3.new(x, FLOOR_Y + 0.23, z + 2), tint(LAB_OLIVE, accent, 0.35), Enum.Material.SmoothPlastic)
		goo.Transparency = 0.3
	elseif id == "ControlBank" then
		p("ControlBankBody", Vector3.new(10, 7, 3), Vector3.new(x, FLOOR_Y + 3.7, z), Color3.fromRGB(46, 52, 54), Enum.Material.Metal)
		for i = -1, 1 do
			local mon = p("ControlMonitor", Vector3.new(2.6, 2, 0.3), Vector3.new(x + i * 3, FLOOR_Y + 5, z + 1.6), tint(accent, Color3.fromRGB(40, 48, 50), 0.4), Enum.Material.SmoothPlastic)
			mon.Transparency = 0.18
		end
		p("ControlBankTrim", Vector3.new(10.4, 0.5, 3.2), Vector3.new(x, FLOOR_Y + 7.3, z), LAB_DARK, Enum.Material.Metal)
		p("ControlBankStatus", Vector3.new(0.8, 0.8, 0.3), Vector3.new(x + 4.5, FLOOR_Y + 6.6, z + 1.7), LAB_GREEN, Enum.Material.Neon).Shape = Enum.PartType.Ball
	else -- FinalReactor
		local base = p("FinalReactorBase", Vector3.new(12, 1.4, 12), Vector3.new(x, FLOOR_Y + 0.7, z), LAB_DARK, Enum.Material.Metal)
		base.Shape = Enum.PartType.Cylinder
		base.Orientation = Vector3.new(0, 0, 90)
		local glass = p("FinalReactorGlass", Vector3.new(8, 19, 8), Vector3.new(x, FLOOR_Y + 10, z), tint(accent, LAB_WHITE, 0.35), Enum.Material.Glass)
		glass.Shape = Enum.PartType.Cylinder
		glass.Transparency = 0.48
		local core = p("FinalReactorCore", Vector3.new(4.6, 12, 4.6), Vector3.new(x, FLOOR_Y + 10, z), tint(accent, Color3.fromRGB(230, 220, 220), 0.25), Enum.Material.Neon)
		core.Shape = Enum.PartType.Cylinder
		local fl = Instance.new("PointLight")
		fl.Brightness = 0.7
		fl.Range = 18
		fl.Color = tint(accent, Color3.fromRGB(225, 215, 215), 0.4)
		fl.Parent = core
		p("FinalReactorRedLamp", Vector3.new(1.2, 1.2, 1.2), Vector3.new(x, FLOOR_Y + 20.5, z), LAB_WARNING_RED, Enum.Material.Neon).Shape = Enum.PartType.Ball
	end
end

local function addBacteriaLabDetails(parent, area, hallX, primary)
	local deco = makeFolder("TunnelLabDetails", parent)
	local theme = themeFor(area.index)
	local accent = theme.accent

	local wallStartX = hallX + L.GateOffsetX - 10
	local wallEndX = hallX + (L.EnemySpacing * (L.EnemiesPerArea - 1)) / 2 + 48
	local wallLength = wallEndX - wallStartX
	local wallCenterX = (wallStartX + wallEndX) / 2
	local tunnelWallHeight = L.WallHeight + BACTERIA_CEILING_LIFT - 2
	for _, z in ipairs({ BACTERIA_LEFT_LIMIT_Z, BACTERIA_RIGHT_LIMIT_Z }) do
		local wall = makePart(deco, "BacteriaTunnelWall", Vector3.new(wallLength, tunnelWallHeight, 3.2), Vector3.new(wallCenterX, FLOOR_Y + tunnelWallHeight / 2, z), LAB_WHITE, Enum.Material.SmoothPlastic, true)
		wall.Transparency = 0.02
		makePart(deco, "BacteriaWallDarkBase", Vector3.new(wallLength, 1.4, 3.5), Vector3.new(wallCenterX, FLOOR_Y + 0.8, z), LAB_DARK, Enum.Material.Metal, true)
		makePart(deco, "BacteriaWallTopRail", Vector3.new(wallLength, 1.2, 3.6), Vector3.new(wallCenterX, FLOOR_Y + tunnelWallHeight - 0.6, z), LAB_DARK, Enum.Material.Metal, true)
		neonStrip(deco, Vector3.new(wallLength - 12, 0.18, 0.26), Vector3.new(wallCenterX, FLOOR_Y + 5.8, z), primary, 0.78)
		neonStrip(deco, Vector3.new(wallLength - 16, 0.16, 0.24), Vector3.new(wallCenterX, FLOOR_Y + tunnelWallHeight - 5.5, z), LAB_CYAN, 0.82)
		for i = 1, 4 do
			local sx = wallStartX + wallLength * i / 5
			makePart(deco, "BacteriaWallSupport", Vector3.new(1.6, tunnelWallHeight, 4), Vector3.new(sx, FLOOR_Y + tunnelWallHeight / 2, z), LAB_TRIM, Enum.Material.Metal, true)
		end
		for i = 1, 3 do
			local wx = wallStartX + wallLength * (i + 0.35) / 4
			local window = makePart(deco, "ObservationWindow", Vector3.new(24, 8, 0.45), Vector3.new(wx, FLOOR_Y + 17, z), Color3.fromRGB(118, 137, 137), Enum.Material.Glass, false)
			window.Transparency = 0.58
			makePart(deco, "WindowFrameTop", Vector3.new(26, 0.7, 0.7), Vector3.new(wx, FLOOR_Y + 21.3, z), LAB_DARK, Enum.Material.Metal, false)
			makePart(deco, "WindowFrameBottom", Vector3.new(26, 0.7, 0.7), Vector3.new(wx, FLOOR_Y + 12.7, z), LAB_DARK, Enum.Material.Metal, false)
		end
	end
	for _, x in ipairs({ wallStartX, wallEndX }) do
		local leftWidth = BACTERIA_LEFT_LIMIT_Z - CORRIDOR_MIN_Z
		local rightWidth = CORRIDOR_MAX_Z - BACTERIA_RIGHT_LIMIT_Z
		makePart(deco, "BacteriaTunnelOuterCapLeft", Vector3.new(3, tunnelWallHeight, leftWidth), Vector3.new(x, FLOOR_Y + tunnelWallHeight / 2, (CORRIDOR_MIN_Z + BACTERIA_LEFT_LIMIT_Z) / 2), LAB_WHITE, Enum.Material.SmoothPlastic, true)
		makePart(deco, "BacteriaTunnelOuterCapRight", Vector3.new(3, tunnelWallHeight, rightWidth), Vector3.new(x, FLOOR_Y + tunnelWallHeight / 2, (BACTERIA_RIGHT_LIMIT_Z + CORRIDOR_MAX_Z) / 2), LAB_WHITE, Enum.Material.SmoothPlastic, true)
	end

	-- Boden-Deko: jede flache Flaeche auf EINDEUTIGER Hoehe (LAYER_*), heller
	-- Ton statt fast-Schwarz -> kein dunkles Z-Fighting im Laufweg.
	local pathBase = makePart(deco, "BacteriaMainPath", Vector3.new(L.AreaSpan - 110, 0.07, 18), Vector3.new(hallX + 10, LAYER_PATH, BACTERIA_PATH_Z), Color3.fromRGB(126, 131, 130), Enum.Material.SmoothPlastic, false)
	pathBase.Transparency = 0.12
	for i = 0, 5 do
		local px = wallStartX + wallLength * (i + 0.5) / 6
		makePart(deco, "FloorPlateSeam", Vector3.new(0.35, 0.06, 64), Vector3.new(px, LAYER_SEAM, BACTERIA_PATH_Z), Color3.fromRGB(96, 101, 101), Enum.Material.SmoothPlastic, false)
	end
	for _, dz in ipairs({ -8.8, 8.8 }) do
		neonStrip(deco, Vector3.new(L.AreaSpan - 130, 0.07, 0.32), Vector3.new(hallX + 10, LAYER_LANE_GLOW, BACTERIA_PATH_Z + dz), primary, 0.82)
	end

	for _, x in ipairs({ hallX - 150, hallX - 55, hallX + 40, hallX + 135 }) do
		local arrow = makePart(deco, "TunnelPathArrow", Vector3.new(10, 0.09, 4), Vector3.new(x, LAYER_ARROW, BACTERIA_PATH_Z), LAB_WARNING_YELLOW, Enum.Material.SmoothPlastic, false)
		arrow.Transparency = 0.42
	end

	for i, x in ipairs({ hallX - 132, hallX - 66, hallX, hallX + 66, hallX + 132 }) do
		for _, z in ipairs({ CORRIDOR_MIN_Z + 2, CORRIDOR_MAX_Z - 2 }) do
			local panel = makePart(deco, "ContainmentWallPanel", Vector3.new(34, 9, 0.45), Vector3.new(x, FLOOR_Y + 13, z), LAB_DARK, Enum.Material.SmoothPlastic, false)
			local text = if i % 3 == 1 then theme.wallText .. "\nCONTAINMENT" elseif i % 3 == 2 then "AUTHORIZED\nPERSONNEL ONLY" else string.format("CELL %02d-%02d", math.max(1, i * 2 - 1), math.min(10, i * 2))
			label(panel, text, Color3.fromRGB(206, 214, 210), 42, UDim2.fromOffset(190, 62), Vector3.new(0, 0, 0))
			local module = makePart(deco, "SecurityWallModule", Vector3.new(9, 5.5, 0.55), Vector3.new(x + 24, FLOOR_Y + 7.5, z), Color3.fromRGB(42, 48, 50), Enum.Material.Metal, false)
			makePart(deco, "StatusLightGreen", Vector3.new(1.2, 1.2, 0.25), module.Position + Vector3.new(-2.4, 1.1, 0.35), LAB_GREEN, Enum.Material.SmoothPlastic, false).Shape = Enum.PartType.Ball
			if area.index >= 5 then
				makePart(deco, "StatusLightRed", Vector3.new(1.1, 1.1, 0.25), module.Position + Vector3.new(2.2, 1.1, 0.35), LAB_WARNING_RED, Enum.Material.SmoothPlastic, false).Shape = Enum.PartType.Ball
			end
		end
	end

	-- Wiederkehrendes Thema-Hero-Objekt -> jede Area sieht anders aus.
	for _, x in ipairs({ hallX - 100, hallX + 10, hallX + 120 }) do
		for _, z in ipairs({ BACTERIA_LEFT_LIMIT_Z + 8, BACTERIA_RIGHT_LIMIT_Z - 8 }) do
			buildThemeSideProp(deco, theme, x, z, accent)
		end
	end

	for _, z in ipairs({ BACTERIA_LEFT_LIMIT_Z + 10, BACTERIA_RIGHT_LIMIT_Z - 10 }) do
		makePart(deco, "CeilingPipe", Vector3.new(L.AreaSpan - 110, 0.85, 0.85), Vector3.new(hallX, FLOOR_Y + L.WallHeight + 3, z), Color3.fromRGB(86, 94, 100), Enum.Material.Metal, false)
		makePart(deco, "CableTray", Vector3.new(L.AreaSpan - 165, 0.55, 1.8), Vector3.new(hallX, FLOOR_Y + L.WallHeight + 1.2, z + 7), LAB_DARK, Enum.Material.Metal, false)
	end
	for _, x in ipairs({ hallX - 130, hallX - 10, hallX + 110 }) do
		makePart(deco, "CeilingAccessPanel", Vector3.new(26, 0.22, 14), Vector3.new(x, FLOOR_Y + L.WallHeight + 8.65, BACTERIA_PATH_Z), Color3.fromRGB(70, 76, 78), Enum.Material.Metal, false)
		if area.index >= 4 then
			local warnLight = makePart(deco, "SmallRedWarningLight", Vector3.new(2.2, 0.35, 2.2), Vector3.new(x + 17, FLOOR_Y + L.WallHeight + 8.35, BACTERIA_PATH_Z), LAB_WARNING_RED, Enum.Material.Neon, false)
			warnLight.Transparency = 0.25
		end
	end
	for _, x in ipairs({ hallX - 150, hallX - 20, hallX + 110 }) do
		for _, z in ipairs({ BACTERIA_LEFT_LIMIT_Z + 14, BACTERIA_RIGHT_LIMIT_Z - 14 }) do
			makePart(deco, "BacteriaVent", Vector3.new(18, 0.35, 8), Vector3.new(x, FLOOR_Y + L.WallHeight + 8.8, z), Color3.fromRGB(72, 80, 86), Enum.Material.Metal, false)
			local lamp = makePart(deco, "SoftLabLamp", Vector3.new(14, 0.25, 4), Vector3.new(x, FLOOR_Y + L.WallHeight + 8.4, z + 12), Color3.fromRGB(220, 229, 225), Enum.Material.Neon, false)
			lamp.Transparency = 0.28
		end
	end

	for _, x in ipairs({ hallX - 155, hallX - 35, hallX + 85, hallX + 175 }) do
		local warn = makePart(deco, "BioWarningPanel", Vector3.new(12, 5, 0.45), Vector3.new(x, FLOOR_Y + 8, CORRIDOR_MIN_Z + 1.5), Color3.fromRGB(42, 42, 34), Enum.Material.SmoothPlastic, false)
		label(warn, theme.hazard, LAB_WARNING_YELLOW, 38, UDim2.fromOffset(130, 48), Vector3.new(0, 0, 0))
	end

	if area.index % 2 == 1 then
		for _, x in ipairs({ hallX - 76, hallX + 54 }) do
			local seep = makePart(deco, "SubtleFloorContamination", Vector3.new(10, 0.05, 5.5), Vector3.new(x, LAYER_CONTAM, BACTERIA_LEFT_LIMIT_Z + 5), LAB_OLIVE, Enum.Material.SmoothPlastic, false)
			seep.Transparency = 0.48
			local fleck = makePart(deco, "SmallBacteriaFleck", Vector3.new(3.2, 0.04, 2.6), Vector3.new(x + 7, LAYER_CONTAM + 0.04, BACTERIA_LEFT_LIMIT_Z + 9), LAB_OLIVE, Enum.Material.SmoothPlastic, false)
			fleck.Transparency = 0.58
		end
	else
		for _, x in ipairs({ hallX - 60, hallX + 80 }) do
			local drip = makePart(deco, "SubtleWallBiofilm", Vector3.new(8, 3.6, 0.35), Vector3.new(x, FLOOR_Y + 6, BACTERIA_RIGHT_LIMIT_Z - 1.8), LAB_OLIVE, Enum.Material.SmoothPlastic, false)
			drip.Transparency = 0.52
			local streak = makePart(deco, "ThinWallContaminationStreak", Vector3.new(1.2, 6.5, 0.28), Vector3.new(x + 6, FLOOR_Y + 8.2, BACTERIA_RIGHT_LIMIT_Z - 1.9), LAB_OLIVE, Enum.Material.SmoothPlastic, false)
			streak.Transparency = 0.6
		end
	end
end

-- ---- Trainingsbereich (mit Rebirth-Gate) ---------------------------------

local function buildTrainingArea(parent, bedsFolder, gatesFolder, area, x)
	local bedDef = TrainingBedConfig[area.index]
	local primary = area.primaryColor
	local model = Instance.new("Model")
	model.Name = "Training_" .. area.id
	model.Parent = parent

	-- ---- Seitliche Trainings-Bay (links, -Z) -----------------------------
	-- Bewusst NICHT mittig im Laufweg: eine eigene, abgesetzte Labor-Nische.
	-- Der Spieler macht einen kurzen Abstecher zur Seite, um zu trainieren.
	-- Der Korridor-Mittelweg (Z um 0) bleibt komplett frei.
	local bayZ = -54
	local bayDepthZ = 42
	local bayHalfZ = bayDepthZ / 2
	local bayMouthZ = bayZ + bayHalfZ -- Richtung Laufweg (offene Seite)
	local bayBackZ = bayZ - bayHalfZ
	local bayWidthX = 78

	-- Bay-Boden (klar abgesetzte Plattform).
	makePart(model, "TrainingBayFloor", Vector3.new(bayWidthX, 0.6, bayDepthZ), Vector3.new(x, FLOOR_Y + 0.32, bayZ), tint(LAB_PANEL, primary, 0.14), Enum.Material.SmoothPlastic, true)
	makePart(model, "TrainingBayFloorInset", Vector3.new(bayWidthX - 8, 0.1, bayDepthZ - 7), Vector3.new(x, FLOOR_Y + 0.62, bayZ), Color3.fromRGB(80, 86, 86), Enum.Material.Metal, false).Transparency = 0.2
	-- Gelb-schwarze Schwelle als Eingangsmarkierung zum Laufweg.
	makePart(model, "TrainingBayThreshold", Vector3.new(bayWidthX, 0.08, 1.8), Vector3.new(x, FLOOR_Y + 0.4, bayMouthZ - 1), LAB_WARNING_YELLOW, Enum.Material.SmoothPlastic, false).Transparency = 0.32

	-- Nischen-Architektur (blockiert den Laufweg nicht; Mund bleibt offen).
	makePart(model, "TrainingBayBackWall", Vector3.new(bayWidthX, 17, 1.3), Vector3.new(x, FLOOR_Y + 8.5, bayBackZ), LAB_WHITE, Enum.Material.SmoothPlastic, true)
	makePart(model, "TrainingBayBackBase", Vector3.new(bayWidthX, 1.4, 1.6), Vector3.new(x, FLOOR_Y + 0.9, bayBackZ), LAB_DARK, Enum.Material.Metal, true)
	makePart(model, "TrainingBayBackTopRail", Vector3.new(bayWidthX, 1.1, 1.6), Vector3.new(x, FLOOR_Y + 16.4, bayBackZ), LAB_DARK, Enum.Material.Metal, true)
	for _, sx in ipairs({ x - bayWidthX / 2, x + bayWidthX / 2 }) do
		makePart(model, "TrainingBaySideWall", Vector3.new(1.3, 17, bayDepthZ), Vector3.new(sx, FLOOR_Y + 8.5, bayZ), LAB_WHITE, Enum.Material.SmoothPlastic, true)
		makePart(model, "TrainingBaySideTrim", Vector3.new(1.5, 1.2, bayDepthZ), Vector3.new(sx, FLOOR_Y + 0.85, bayZ), LAB_DARK, Enum.Material.Metal, true)
	end
	-- Glas-Trennscheiben an den Bay-Raendern -> Mitte als Durchgang offen.
	for _, gx in ipairs({ x - 23, x + 23 }) do
		local glass = makePart(model, "TrainingBayGlass", Vector3.new(18, 9, 0.4), Vector3.new(gx, FLOOR_Y + 5.2, bayMouthZ), tint(LAB_CYAN, LAB_WHITE, 0.45), Enum.Material.Glass, false)
		glass.Transparency = 0.68
	end
	makePart(model, "TrainingBayPortalHeader", Vector3.new(bayWidthX, 3, 1.4), Vector3.new(x, FLOOR_Y + 15.5, bayMouthZ), LAB_DARK, Enum.Material.Metal, false)
	for _, ledZ in ipairs({ bayMouthZ }) do
		neonStrip(model, Vector3.new(bayWidthX - 4, 0.3, 0.3), Vector3.new(x, FLOOR_Y + 13.8, ledZ), primary, 0.5)
	end

	-- Ein breiter, klarer Power-Trainingsbereich. DNA/Luck-Training wurde
	-- bewusst entfernt, damit die Bay nicht wie drei getrennte Shops wirkt.
	local center = Vector3.new(x, FLOOR_Y, bayZ)
	local trainColor = LAB_WARNING_RED
	local tp = makePart(model, "TrainPad", Vector3.new(42, 0.5, 20), center + Vector3.new(0, 0.75, 0), trainColor, Enum.Material.SmoothPlastic, false)
	tp.Transparency = 0.34
	local stationBase = makePart(model, "TrainStationBase", Vector3.new(50, 0.25, 24), center + Vector3.new(0, 0.5, 0), LAB_DARK, Enum.Material.Metal, false)
	stationBase.Transparency = 0.08
	makePart(model, "TrainPadStripe", Vector3.new(34, 0.12, 0.55), center + Vector3.new(0, 0.95, 8.6), trainColor, Enum.Material.SmoothPlastic, false).Transparency = 0.3
	for _, edgeX in ipairs({ -21, 21 }) do
		makePart(model, "TrainScannerPost", Vector3.new(0.8, 7.2, 0.8), center + Vector3.new(edgeX, 3.8, -8.7), LAB_DARK, Enum.Material.Metal, false)
	end
	local scannerBeam = makePart(model, "TrainScannerBeam", Vector3.new(43, 0.7, 0.8), center + Vector3.new(0, 7.4, -8.7), LAB_DARK, Enum.Material.Metal, false)
	neonStrip(model, Vector3.new(36, 0.22, 0.34), scannerBeam.Position + Vector3.new(0, -0.45, 0.42), trainColor, 0.5)
	local terminal = makePart(model, "TrainTerminal", Vector3.new(7, 3.4, 3.4), center + Vector3.new(0, 1.7, -10.1), LAB_DARK, Enum.Material.Metal, false)
	local screen = makePart(model, "TrainTerminalScreen", Vector3.new(5.6, 2.4, 0.36), terminal.Position + Vector3.new(0, 1, 1.9), trainColor, Enum.Material.SmoothPlastic, false)
	screen.Transparency = 0.22
	label(screen, "PWR", Color3.fromRGB(255, 255, 255), 30, UDim2.fromOffset(120, 34), Vector3.new(0, 0, 0))
	local cabinet = makePart(model, "TrainingBreakerBox", Vector3.new(4.2, 5.4, 1.1), center + Vector3.new(-18, 3.2, -10.8), Color3.fromRGB(54, 60, 62), Enum.Material.Metal, false)
	label(cabinet, "SYS\nOK", LAB_GREEN, 22, UDim2.fromOffset(56, 34), Vector3.new(0, 0, 0))
	local post = makePart(model, "TrainSignPost", Vector3.new(0.6, 6.4, 0.6), center + Vector3.new(0, 3.2, 9.7), LAB_TRIM, Enum.Material.Metal, false)
	label(post, "POWER TRAINING", trainColor, 44, UDim2.fromOffset(210, 44), Vector3.new(0, 3, 0))

	-- Trainings-Bett (Vertrag mit TrainingZoneService): Model + Hitbox-Part.
	-- Hitbox deckt die Bay ab -> Spieler trainiert, waehrend er in der Bay
	-- steht (Side-Bay-Verhalten). Attribute UNVERAENDERT.
	local bedModel = Instance.new("Model")
	bedModel.Name = bedDef.id
	bedModel.Parent = bedsFolder
	local hitbox = makePart(bedModel, "Hitbox", Vector3.new(bayWidthX - 6, 8, bayDepthZ - 4), Vector3.new(x, FLOOR_Y + 4, bayZ), primary, Enum.Material.SmoothPlastic, false)
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
		field:SetAttribute("RequiredPower", 0)
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

-- Egg-Catch-Station als Labor-Inkubator (Side-Bay). Seltenheit bestimmt die
-- Staerke des Containments: Common = einfache Probe, Rare = bessere Glas-
-- Kammer, Epic = schwere Containment-Kapsel. Vertrag UNVERAENDERT:
-- Model-Attribute (AreaIndex/EggTier/EggCost) + ClickDetector "OpenEgg".
local function buildEggStation(parent, areaIndex, stationIndex, eggDef, pos)
	local model = Instance.new("Model")
	model.Name = string.format("Egg_A%d_%s", areaIndex, eggDef.tier)
	model.Parent = parent

	local tier = eggDef.tier
	local accent = eggDef.color

	-- Eigener Inkubator-Sockel + Rueckpaneel (markiert die Side-Bay).
	local bayPad = makePart(model, "IncubatorBayPad", Vector3.new(15, 0.4, 15), pos + Vector3.new(0, -0.2, 0), tint(LAB_PANEL, accent, 0.12), Enum.Material.SmoothPlastic, true)
	bayPad.Transparency = 0.05
	makePart(model, "IncubatorBayEdge", Vector3.new(15.4, 0.1, 15.4), pos + Vector3.new(0, 0.05, 0), accent:Lerp(LAB_DARK, 0.5), Enum.Material.SmoothPlastic, false).Transparency = 0.4
	local backPanel = makePart(model, "IncubatorBackPanel", Vector3.new(13, 11, 0.5), pos + Vector3.new(0, 6, 7), Color3.fromRGB(40, 45, 46), Enum.Material.Metal, false)
	label(backPanel, string.format("%s INCUBATOR", string.upper(tier)), accent:Lerp(Color3.fromRGB(225, 230, 222), 0.5), 30, UDim2.fromOffset(150, 36), Vector3.new(0, 3.6, 0))

	local base = makePart(model, "EggBase", Vector3.new(12, 1.2, 12), pos, LAB_DARK, Enum.Material.Metal, true)
	base.Shape = Enum.PartType.Cylinder
	base.Orientation = Vector3.new(0, 0, 90)

	local ring = makePart(model, "EggRing", Vector3.new(12.6, 0.5, 12.6), pos + Vector3.new(0, 0.8, 0), accent:Lerp(LAB_TRIM, 0.45), Enum.Material.SmoothPlastic, false)
	ring.Shape = Enum.PartType.Cylinder
	ring.Orientation = Vector3.new(0, 0, 90)
	ring.Transparency = 0.38

	-- Glas-Inkubationskammer um die Probe (Staerke je nach Seltenheit).
	local glassTransparency = if tier == "Common" then 0.74 elseif tier == "Rare" then 0.66 else 0.58
	local chamber = makePart(model, "IncubationGlass", Vector3.new(7, 9, 7), pos + Vector3.new(0, 5, 0), tint(accent, LAB_WHITE, 0.55), Enum.Material.Glass, false)
	chamber.Shape = Enum.PartType.Cylinder
	chamber.Orientation = Vector3.new(0, 0, 90)
	chamber.Transparency = glassTransparency
	makePart(model, "IncubationCapBottom", Vector3.new(8, 0.7, 8), pos + Vector3.new(0, 0.9, 0), LAB_TRIM, Enum.Material.Metal, false).Shape = Enum.PartType.Cylinder
	makePart(model, "IncubationCapTop", Vector3.new(8, 0.7, 8), pos + Vector3.new(0, 9.1, 0), LAB_DARK, Enum.Material.Metal, false).Shape = Enum.PartType.Cylinder

	-- Rare/Epic: zusaetzliche Containment-Streben.
	if tier ~= "Common" then
		local posts = if tier == "Rare" then 2 else 4
		for i = 0, posts - 1 do
			local a = i * (2 * math.pi / posts) + math.pi / 4
			makePart(model, "ContainmentStrut", Vector3.new(0.55, 9.5, 0.55), pos + Vector3.new(math.cos(a) * 4.4, 5, math.sin(a) * 4.4), LAB_DARK, Enum.Material.Metal, false)
		end
	end
	if tier == "Epic" then
		makePart(model, "EpicContainmentCage", Vector3.new(9.4, 0.5, 9.4), pos + Vector3.new(0, 5, 0), accent:Lerp(LAB_DARK, 0.4), Enum.Material.Metal, false).Shape = Enum.PartType.Cylinder
		makePart(model, "EpicStatusLight", Vector3.new(1, 1, 1), pos + Vector3.new(0, 10, 0), LAB_WARNING_RED, Enum.Material.Neon, false).Shape = Enum.PartType.Ball
	else
		makePart(model, "IncubatorStatusLight", Vector3.new(0.9, 0.9, 0.3), pos + Vector3.new(4.6, 2.4, 4.6), LAB_GREEN, Enum.Material.Neon, false).Shape = Enum.PartType.Ball
	end

	-- Kleines Kontroll-Terminal an der Seite.
	local terminal = makePart(model, "IncubatorTerminal", Vector3.new(3, 3.4, 2), pos + Vector3.new(6.5, 1.7, 0), Color3.fromRGB(44, 50, 52), Enum.Material.Metal, false)
	makePart(model, "IncubatorTerminalScreen", Vector3.new(0.3, 2, 1.5), terminal.Position + Vector3.new(-1.6, 0.6, 0), accent, Enum.Material.SmoothPlastic, false).Transparency = 0.2

	-- Ei / Kapsel in der Mitte (Klick-Ziel; Vertrag unveraendert).
	local capsule = makePart(model, "EggCapsule", Vector3.new(5, 6.5, 5), pos + Vector3.new(0, 4.5, 0), accent, Enum.Material.SmoothPlastic, false)
	capsule.CanQuery = true -- anklickbar (OpenEgg ClickDetector)
	capsule.Shape = Enum.PartType.Ball
	capsule.Transparency = 0.1
	local glow = Instance.new("PointLight")
	glow.Brightness = 0.45
	glow.Range = 9
	glow.Color = accent:Lerp(Color3.fromRGB(210, 220, 216), 0.55)
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
		accent,
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
	local screen = makePart(model, "ConsoleScreen", Vector3.new(6.5, 3.5, 0.45), pos + Vector3.new(0, 6.1, -2.75), accent:Lerp(Color3.fromRGB(80, 92, 88), 0.45), Enum.Material.SmoothPlastic, false)
	screen.Transparency = 0.12
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
		local fluid = makePart(model, "SampleFluid", Vector3.new(1.7, 3.2, 1.7), center + Vector3.new(i * 3.6, 2.9, 0), accent:Lerp(LAB_OLIVE, 0.45), Enum.Material.Glass, false)
		fluid.Shape = Enum.PartType.Cylinder
		fluid.Transparency = 0.38
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
	local sample = makePart(model, "FloatingSample", Vector3.new(3.5, 3.5, 3.5), center + Vector3.new(0, 10.5, 0), accent:Lerp(LAB_PANEL, 0.35), Enum.Material.SmoothPlastic, false)
	sample.Shape = Enum.PartType.Ball
	sample.Transparency = 0.25
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
		makePart(parent, "GuideArrowBody", Vector3.new(15, 0.07, 3.6), Vector3.new(x, LAYER_PATH, 0), Color3.fromRGB(96, 101, 101), Enum.Material.SmoothPlastic, false)
		local glow = neonStrip(parent, Vector3.new(10, 0.07, 0.8), Vector3.new(x, LAYER_SEAM, 0), accent, 0.08)
		glow.Orientation = Vector3.new(0, 0, -20)
		local tip = makePart(parent, "GuideArrowTip", Vector3.new(5, 0.07, 5), Vector3.new(x + 8, LAYER_ARROW, 0), accent:Lerp(LAB_TRIM, 0.45), Enum.Material.SmoothPlastic, false)
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

-- ---- Decken-Stufen-Bulkhead ----------------------------------------------
-- Schliesst die senkrechte Lücke zwischen zwei unterschiedlich hohen
-- Korridor-Decken (Spawn-Decke Y=L.WallHeight, Area-Decke nach
-- liftBacteriaLabCeiling Y=L.WallHeight+BACTERIA_CEILING_LIFT). Ohne diese
-- Klappe sieht man oben durch den Stufen-Spalt den Himmel. Das Modul ist
-- bewusst als Bulkhead-Träger gestaltet: helles Labor-Paneel als geschlossene
-- Wand + schwarze Akzentkanten (oben/unten), senkrechte Trim-Stützen die
-- saubere rechteckige Module bilden, Lüftungsgitter, sanfte Decken-Leuchten
-- (matt, kein grelles Neon) und kleine Technikpaneele. Beide Seitenflächen
-- bekommen die Detail-Schicht, damit der Übergang aus beiden Korridoren
-- bewusst designed wirkt -- nicht zusammengeflickt.
local function buildCeilingStepBulkhead(parent, atX, lowHeight, highHeight)
	local stepHeight = highHeight - lowHeight
	if stepHeight <= 0 then
		return
	end
	local centerY = (lowHeight + highHeight) / 2
	local panelThickness = 2.2

	-- Geschlossene, kollidierende Bulkhead-Wand quer über den Korridor.
	-- Verhindert jedes Sky-Leak durch den Stufen-Spalt und blockiert die
	-- Kamera sauber wie eine echte Korridorwand.
	local panel = makePart(
		parent,
		"BulkheadStepPanel",
		Vector3.new(panelThickness, stepHeight, FLOOR_SIZE_Z),
		Vector3.new(atX, centerY, FLOOR_CENTER_Z),
		Color3.fromRGB(214, 219, 218),
		Enum.Material.SmoothPlastic,
		true
	)
	panel.TopSurface = Enum.SurfaceType.Smooth
	panel.BottomSurface = Enum.SurfaceType.Smooth

	-- Schwarze Akzentkanten an Ober- und Unterkante des Bulkheads -- gleicher
	-- Stil wie WallBlackTrim/CeilingEdgeTrim im restlichen Map-Design.
	makePart(
		parent,
		"BulkheadEdgeTrimBottom",
		Vector3.new(panelThickness + 0.5, 0.7, FLOOR_SIZE_Z),
		Vector3.new(atX, lowHeight + 0.35, FLOOR_CENTER_Z),
		LAB_DARK,
		Enum.Material.SmoothPlastic,
		false
	)
	makePart(
		parent,
		"BulkheadEdgeTrimTop",
		Vector3.new(panelThickness + 0.5, 0.7, FLOOR_SIZE_Z),
		Vector3.new(atX, highHeight - 0.35, FLOOR_CENTER_Z),
		LAB_DARK,
		Enum.Material.SmoothPlastic,
		false
	)

	-- Senkrechte Trim-Streben teilen den Bulkhead in saubere, rechteckige
	-- Module (gleiche Logik wie WallPanelSeam/CeilingSupport).
	local moduleCount = 6
	for i = 0, moduleCount do
		local sz = CORRIDOR_MIN_Z + FLOOR_SIZE_Z * i / moduleCount
		makePart(
			parent,
			"BulkheadStrut",
			Vector3.new(panelThickness + 0.4, stepHeight - 1.6, 0.7),
			Vector3.new(atX, centerY, sz),
			LAB_TRIM,
			Enum.Material.Metal,
			false
		)
	end

	-- Beide sichtbaren Flächen (Spawn-Seite -X, Area-Seite +X) bekommen die
	-- gleiche Detail-Schicht, damit der Übergang aus jeder Richtung bewusst
	-- designed wirkt.
	for _, face in ipairs({ -1, 1 }) do
		local faceX = atX + face * (panelThickness / 2 + 0.05)
		for i = 0, moduleCount - 1 do
			local z = CORRIDOR_MIN_Z + FLOOR_SIZE_Z * (i + 0.5) / moduleCount

			-- Inset-Paneel (dunkles Modul-Inneres) -- gibt dem Bulkhead Tiefe.
			makePart(
				parent,
				"BulkheadInsetPanel",
				Vector3.new(0.25, stepHeight - 3.4, 16),
				Vector3.new(faceX, centerY, z),
				Color3.fromRGB(70, 76, 78),
				Enum.Material.Metal,
				false
			)

			-- Lüftungsgitter mittig im Modul (gleicher Stil wie RoofVentGrille).
			makePart(
				parent,
				"BulkheadVentGrille",
				Vector3.new(0.32, math.max(2.2, stepHeight - 5.6), 9),
				Vector3.new(faceX + face * 0.15, centerY, z),
				Color3.fromRGB(74, 80, 82),
				Enum.Material.Metal,
				false
			)

			-- Kleines Technikpaneel unten links im Modul.
			local techPanel = makePart(
				parent,
				"BulkheadTechPanel",
				Vector3.new(0.35, 1.8, 3.4),
				Vector3.new(faceX + face * 0.2, lowHeight + 1.3, z - 5.8),
				Color3.fromRGB(46, 52, 54),
				Enum.Material.Metal,
				false
			)
			-- Winziger grüner Status-Punkt -- matt, kein Glow.
			makePart(
				parent,
				"BulkheadStatusDot",
				Vector3.new(0.36, 0.45, 0.45),
				techPanel.Position + Vector3.new(face * 0.12, 0.45, 1),
				LAB_GREEN,
				Enum.Material.SmoothPlastic,
				false
			)

			-- Sanfte Decken-Lampe direkt unter der Oberkante (matt-weiss,
			-- gleicher Stil wie SoftLabLamp/RoofLightPanel-Frame: leichte
			-- Eigenhelle über hohe Transparenz, KEIN grelles Neon).
			local lamp = makePart(
				parent,
				"BulkheadLabLamp",
				Vector3.new(0.32, 0.55, 12),
				Vector3.new(faceX + face * 0.18, highHeight - 1.7, z),
				Color3.fromRGB(228, 234, 232),
				Enum.Material.SmoothPlastic,
				false
			)
			lamp.Transparency = 0.18
			-- Dunkler Lampen-Rahmen darunter -- konsistent mit RoofPanelFrame.
			makePart(
				parent,
				"BulkheadLabLampFrame",
				Vector3.new(0.3, 0.85, 13),
				Vector3.new(faceX + face * 0.12, highHeight - 1.7, z),
				LAB_DARK,
				Enum.Material.SmoothPlastic,
				false
			)
		end

		-- Durchlaufender Kabelträger unter der Oberkante (gleicher Stil wie
		-- CableTray im Bakterien-Tunnel).
		makePart(
			parent,
			"BulkheadCableTray",
			Vector3.new(0.4, 0.55, FLOOR_SIZE_Z - 12),
			Vector3.new(faceX + face * 0.05, highHeight - 3.2, FLOOR_CENTER_Z),
			LAB_DARK,
			Enum.Material.Metal,
			false
		)
		-- Schwarze Deckenstrebe als waagerechte Akzentkante zur Mitte.
		makePart(
			parent,
			"BulkheadCenterStrut",
			Vector3.new(0.36, 0.5, FLOOR_SIZE_Z - 6),
			Vector3.new(faceX + face * 0.05, centerY, FLOOR_CENTER_Z),
			LAB_DARK,
			Enum.Material.Metal,
			false
		)
	end
end

-- ---- Hero-Objekt: Virus-Statue (Spawn-Landmarke) -------------------------
-- Eine grosse, kontrollierte Virus-Probe in einer Glas-Containment-Kuppel
-- auf dunklem Stufensockel mit Metallrahmen. Bewusst clean + leicht
-- bedrohlich (Resident-Evil-Biohazard-Look), kein Disco-Neon. Dient als
-- klarer Mittelpunkt/Orientierung im Spawn, blockiert keinen Laufweg.
local function buildVirusStatue(parent, center: Vector3, accent: Color3)
	local model = Instance.new("Model")
	model.Name = "VirusStatue"
	model.Parent = parent

	local cx, cz = center.X, center.Z

	-- Sauber eingebetteter Stufensockel: jede Stufe liegt mit klarer
	-- Auflage auf der vorigen, die unterste ist im Boden VERSENKT
	-- (Schnittkoerper, keine deckungsgleiche Flaeche -> kein Flackern,
	-- nichts schwebt, nichts clippt unsauber).
	local tiers = {
		{ r = 30, h = 1.6, color = LAB_DARK }, -- breite Basis (im Boden verankert)
		{ r = 23, h = 1.8, color = LAB_TRIM },
		{ r = 17, h = 1.6, color = LAB_DARK },
	}
	local y = FLOOR_Y - 0.6 -- Unterkante der Basis tief im Boden
	local pedTop = y
	for i, t in ipairs(tiers) do
		local tier = makePart(model, "StatuePedestal" .. i, Vector3.new(t.h, t.r, t.r), Vector3.new(cx, y + t.h / 2, cz), t.color, Enum.Material.Metal, true)
		tier.Shape = Enum.PartType.Cylinder
		tier.Orientation = Vector3.new(0, 0, 90)
		pedTop = y + t.h
		y = pedTop -- naechste Stufe sitzt buendig oben drauf
	end
	-- Schmaler Warn-Rand bündig auf der Basis-Oberkante (eine Ebene, kein
	-- versenkter Disc mehr -> kein Z-Fighting).
	local rim = makePart(model, "StatueHazardRim", Vector3.new(0.18, 31, 31), Vector3.new(cx, FLOOR_Y - 0.6 + 1.6 + 0.09, cz), LAB_WARNING_YELLOW, Enum.Material.SmoothPlastic, false)
	rim.Shape = Enum.PartType.Cylinder
	rim.Orientation = Vector3.new(0, 0, 90)
	rim.Transparency = 0.4
	makePart(model, "StatuePedestalInlay", Vector3.new(0.16, 14, 14), Vector3.new(cx, pedTop + 0.09, cz), tint(LAB_PANEL, accent, 0.25), Enum.Material.SmoothPlastic, false).Shape = Enum.PartType.Cylinder

	-- Vier gruene Status-Lichter rund um den Sockel.
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		local lx = cx + math.cos(a) * 13
		local lz = cz + math.sin(a) * 13
		makePart(model, "StatusLightGreen", Vector3.new(0.9, 0.9, 0.9), Vector3.new(lx, pedTop + 0.5, lz), LAB_GREEN, Enum.Material.Neon, false).Shape = Enum.PartType.Ball
	end

	-- 4 kleine Forschungs-Terminals/Monitore rund um den Sockel (Vorgabe:
	-- "3-4 kleine Terminals/Monitore um die Statue"). Schirme nach aussen.
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		local tx = cx + math.cos(a) * 22
		local tz = cz + math.sin(a) * 22
		local cYb = FLOOR_Y + 2.4
		local body = makePart(model, "StatueTerminal", Vector3.new(4.4, 5.4, 2.4), Vector3.new(tx, cYb, tz), Color3.fromRGB(44, 50, 52), Enum.Material.Metal, true)
		body.CFrame = CFrame.new(Vector3.new(tx, cYb, tz), Vector3.new(cx, cYb, cz))
		local screen = makePart(model, "StatueTerminalScreen", Vector3.new(3.4, 2.6, 0.2), body.Position, tint(accent, Color3.fromRGB(70, 92, 86), 0.4), Enum.Material.Neon, false)
		screen.CFrame = body.CFrame * CFrame.new(0, 0.7, -1.25)
		screen.Transparency = 0.12
		label(screen, (({ "DNA SCAN", "VITALS", "GENOME", "CONTAINMENT" })[i + 1]), Color3.fromRGB(225, 245, 235), 26, UDim2.fromOffset(96, 30), Vector3.new(0, 0, 0))
	end

	-- Glas-Containment-Kuppel + Rahmen.
	local domeY = pedTop + 12
	local glassBaseRing = makePart(model, "DomeBaseRing", Vector3.new(1.4, 24, 24), Vector3.new(cx, pedTop + 0.7, cz), LAB_DARK, Enum.Material.Metal, true)
	glassBaseRing.Shape = Enum.PartType.Cylinder
	glassBaseRing.Orientation = Vector3.new(0, 0, 90)
	local dome = makePart(model, "ContainmentDome", Vector3.new(22, 26, 22), Vector3.new(cx, domeY, cz), tint(LAB_CYAN, Color3.fromRGB(210, 224, 220), 0.5), Enum.Material.Glass, false)
	dome.Shape = Enum.PartType.Ball
	dome.Transparency = 0.74
	for i = 0, 3 do
		local a = i * math.pi / 2
		local sx = cx + math.cos(a) * 11
		local sz = cz + math.sin(a) * 11
		makePart(model, "DomeStrut", Vector3.new(0.7, 25, 0.7), Vector3.new(sx, pedTop + 12, sz), LAB_TRIM, Enum.Material.Metal, true)
	end
	local topRing = makePart(model, "DomeTopRing", Vector3.new(1.4, 7, 7), Vector3.new(cx, pedTop + 24.5, cz), LAB_DARK, Enum.Material.Metal, true)
	topRing.Shape = Enum.PartType.Cylinder
	topRing.Orientation = Vector3.new(0, 0, 90)
	makePart(model, "DomeStatusLamp", Vector3.new(1, 1, 1), Vector3.new(cx, pedTop + 25.6, cz), LAB_GREEN, Enum.Material.Neon, false).Shape = Enum.PartType.Ball

	-- Die Virus-Probe: Kapsid + Spike-Proteine + leuchtender Kern.
	local virusY = domeY
	local shell = makePart(model, "VirusCapsid", Vector3.new(8.4, 8.4, 8.4), Vector3.new(cx, virusY, cz), tint(accent, LAB_OLIVE, 0.35), Enum.Material.Glass, false)
	shell.Shape = Enum.PartType.Ball
	shell.Transparency = 0.34
	local coreBall = makePart(model, "VirusInnerCore", Vector3.new(4.6, 4.6, 4.6), Vector3.new(cx, virusY, cz), tint(accent, Color3.fromRGB(225, 235, 220), 0.25), Enum.Material.Neon, false)
	coreBall.Shape = Enum.PartType.Ball
	coreBall.Transparency = 0.15
	local vlight = Instance.new("PointLight")
	vlight.Brightness = 0.7
	vlight.Range = 18
	vlight.Color = tint(accent, Color3.fromRGB(210, 230, 210), 0.5)
	vlight.Parent = coreBall

	-- Spike-Proteine (ikosaedrisch verteilt, Stiel + Knopf).
	local dirs = {
		Vector3.new(0, 1, 0), Vector3.new(0, -1, 0),
		Vector3.new(1, 0.5, 0), Vector3.new(-1, 0.5, 0),
		Vector3.new(0, 0.5, 1), Vector3.new(0, 0.5, -1),
		Vector3.new(1, -0.4, 1), Vector3.new(-1, -0.4, 1),
		Vector3.new(1, -0.4, -1), Vector3.new(-1, -0.4, -1),
		Vector3.new(0.8, 0.9, 0.8), Vector3.new(-0.8, 0.9, -0.8),
		Vector3.new(0.8, 0.9, -0.8), Vector3.new(-0.8, 0.9, 0.8),
		Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0),
		Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
	}
	for _, d in ipairs(dirs) do
		local u = d.Unit
		local stalkPos = Vector3.new(cx, virusY, cz) + u * 5.4
		local stalk = makePart(model, "VirusSpike", Vector3.new(0.6, 3.2, 0.6), stalkPos, tint(accent, LAB_TRIM, 0.3), Enum.Material.SmoothPlastic, false)
		-- Up-Vektor wechseln, falls Richtung ~ senkrecht (sonst NaN-CFrame).
		local up = if math.abs(u.Y) > 0.99 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
		stalk.CFrame = CFrame.lookAt(stalkPos, stalkPos + u, up) * CFrame.Angles(math.rad(90), 0, 0)
		local knob = makePart(model, "VirusSpikeTip", Vector3.new(1.5, 1.5, 1.5), Vector3.new(cx, virusY, cz) + u * 7.2, tint(accent, Color3.fromRGB(220, 228, 218), 0.4), Enum.Material.SmoothPlastic, false)
		knob.Shape = Enum.PartType.Ball
	end

	-- Dezente DNA-Doppelhelix, die durch die Probe steigt (Labor-Detail).
	for i = 0, 16 do
		local t = i / 16 * math.pi * 3
		local hy = virusY - 7 + i * (14 / 16)
		for _, sgn in ipairs({ 1, -1 }) do
			local node = makePart(model, "StatueHelixNode", Vector3.new(0.7, 0.7, 0.7), Vector3.new(cx + sgn * math.cos(t) * 2.4, hy, cz + sgn * math.sin(t) * 2.4), tint(LAB_CYAN, accent, (i % 2)), Enum.Material.Neon, false)
			node.Shape = Enum.PartType.Ball
			node.Transparency = 0.2
		end
		if i % 2 == 0 then
			local rung = makePart(model, "StatueHelixRung", Vector3.new(0.28, 0.28, 4.8), Vector3.new(cx, hy, cz), tint(accent, LAB_OLIVE, 0.4), Enum.Material.Neon, false)
			rung.CFrame = CFrame.new(cx, hy, cz) * CFrame.Angles(0, t, 0)
			rung.Transparency = 0.3
		end
	end

	-- Sehr dezente "lebende Probe"-Partikel (kein Spam).
	local spore = Instance.new("ParticleEmitter")
	spore.Name = "SpecimenSpores"
	spore.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	spore.Color = ColorSequence.new(tint(accent, LAB_OLIVE, 0.3), accent)
	spore.LightEmission = 0.1
	spore.Rate = 1.5
	spore.Lifetime = NumberRange.new(1.4, 2.2)
	spore.Speed = NumberRange.new(0.4, 1)
	spore.SpreadAngle = Vector2.new(40, 40)
	spore.Size = NumberSequence.new(0.3, 0.04)
	spore.Parent = coreBall

	-- Biohazard-Plakette auf Standfuss (Richtung Laufweg/Spieler, +Z).
	local plaqueZ = cz + 23
	makePart(model, "PlaqueStand", Vector3.new(1.4, 5.6, 1.4), Vector3.new(cx, FLOOR_Y + 2.4, plaqueZ), LAB_DARK, Enum.Material.Metal, true)
	local plaque = makePart(model, "StatuePlaque", Vector3.new(14, 4.6, 0.5), Vector3.new(cx, FLOOR_Y + 6.6, plaqueZ), Color3.fromRGB(34, 38, 38), Enum.Material.Metal, false)
	label(plaque, "SPECIMEN VIRUS-01\n⚠ BIOHAZARD — CONTAINED", tint(accent, Color3.fromRGB(220, 230, 210), 0.45), 60, UDim2.fromOffset(240, 60), Vector3.new(0, 0, 0))

	return model
end

-- ---- Spawn-Hub-Bausteine -------------------------------------------------

-- Achteckige Hub-Plattform als flacher Boden-Inlay (kein Kollisionskoerper,
-- eindeutige Hoehen -> kein Z-Fighting) + Bodenringe + Kabelkanaele.
local function buildHubFloor(parent, cx, hubZ)
	local model = Instance.new("Model")
	model.Name = "SpawnHubFloor"
	model.Parent = parent

	local function octagon(name, radius, yLevel, color, thick, transp)
		for i = 0, 7 do
			local a = i * math.pi / 4
			local nx = cx + math.cos(a) * radius
			local nz = hubZ + math.sin(a) * radius
			local nxt = i + 1
			local bx = cx + math.cos(nxt * math.pi / 4) * radius
			local bz = hubZ + math.sin(nxt * math.pi / 4) * radius
			local mid = Vector3.new((nx + bx) / 2, yLevel, (nz + bz) / 2)
			local len = (Vector3.new(bx, 0, bz) - Vector3.new(nx, 0, nz)).Magnitude
			-- LookVector entlang der Kante -> Size.Z = Kantenlaenge (sonst
			-- stuenden die Segmente quer und das Achteck saehe kaputt aus).
			local seg = makePart(model, name, Vector3.new(1.4, thick, len), mid, color, Enum.Material.SmoothPlastic, false)
			seg.CFrame = CFrame.new(mid, Vector3.new(bx, yLevel, bz))
			seg.Transparency = transp or 0
		end
	end

	-- Heller Hub-Belag: duenn, leicht in den Boden versenkt (kein
	-- deckungsgleicher Flaechen-Konflikt). Alle Ringe liegen mit klarem
	-- Abstand DARUEBER -> kein Z-Fighting / kein schwarzes Flackern.
	local pad = makePart(model, "HubPad", Vector3.new(78, 0.16, 78), Vector3.new(cx, FLOOR_Y + 0.06, hubZ), Color3.fromRGB(206, 212, 211), Enum.Material.SmoothPlastic, false)
	pad.Transparency = 0.05
	octagon("HubRingOuter", 35, FLOOR_Y + 0.20, LAB_DARK, 0.07, 0.05)
	octagon("HubRingOuterGlow", 35, FLOOR_Y + 0.28, LAB_CYAN:Lerp(LAB_PANEL, 0.55), 0.07, 0.45)
	octagon("HubRingInner", 22, FLOOR_Y + 0.36, LAB_DARK, 0.07, 0.05)
	octagon("HubRingInnerGlow", 22, FLOOR_Y + 0.44, LAB_GREEN:Lerp(LAB_PANEL, 0.55), 0.07, 0.45)

	-- Kabelkanaele/Speichen vom Hub-Rand nach aussen.
	for i = 0, 7 do
		local a = i * math.pi / 4 + math.pi / 8
		local dirx, dirz = math.cos(a), math.sin(a)
		local mid = Vector3.new(cx + dirx * 30, FLOOR_Y + 0.52, hubZ + dirz * 30)
		-- LookVector radial nach aussen -> Size.Z (22) liegt entlang der Speiche.
		local spoke = makePart(model, "HubCableChannel", Vector3.new(2.6, 0.07, 22), mid, Color3.fromRGB(78, 84, 86), Enum.Material.SmoothPlastic, false)
		spoke.CFrame = CFrame.new(mid, Vector3.new(cx + dirx * 60, FLOOR_Y + 0.52, hubZ + dirz * 60))
		spoke.Transparency = 0.12
	end
end

-- Dekoratives Labor-Terminal/Monitor (rein optisch, keine Remotes).
local function buildHubTerminal(parent, name, pos, accent, title, subtitle, faceDir)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local look = pos + (faceDir or Vector3.new(0, 0, 1))
	local base = makePart(model, "TermBase", Vector3.new(7, 1.2, 5), pos + Vector3.new(0, 0.4, 0), LAB_DARK, Enum.Material.Metal, true)
	base.CFrame = CFrame.new(base.Position, Vector3.new(look.X, base.Position.Y, look.Z))
	local body = makePart(model, "TermBody", Vector3.new(6.6, 7, 2.2), pos + Vector3.new(0, 4, 0), Color3.fromRGB(46, 52, 54), Enum.Material.Metal, true)
	body.CFrame = CFrame.new(body.Position, Vector3.new(look.X, body.Position.Y, look.Z))
	local screen = makePart(model, "TermScreen", Vector3.new(5.4, 4.4, 0.2), body.Position, tint(accent, Color3.fromRGB(60, 84, 80), 0.4), Enum.Material.Neon, false)
	screen.CFrame = body.CFrame * CFrame.new(0, 0.6, -1.15)
	screen.Transparency = 0.1
	label(screen, title .. "\n" .. subtitle, Color3.fromRGB(232, 246, 240), 40, UDim2.fromOffset(150, 56), Vector3.new(0, 0, 0))
	makePart(model, "TermTrim", Vector3.new(6.8, 0.4, 2.4), pos + Vector3.new(0, 7.6, 0), accent:Lerp(LAB_DARK, 0.4), Enum.Material.SmoothPlastic, false).CFrame = body.CFrame * CFrame.new(0, 3.6, 0)
end

local function makePrompt(parent: BasePart, menuTarget: string, actionText: string, objectText: string)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenMenuPrompt"
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("MenuTarget", menuTarget)
	prompt.Parent = parent
	return prompt
end

local function buildStationNpc(parent, name, pos, accent, npcName, style, faceSign): BasePart
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local face = faceSign or 1

	local suit = if style == "Dark" then Color3.fromRGB(42, 45, 52) else LAB_WHITE
	local trim = if style == "Bot" then LAB_DARK else accent:Lerp(LAB_DARK, 0.35)
	local skin = Color3.fromRGB(226, 190, 150)

	local legs = makePart(model, "Legs", Vector3.new(2.6, 3.2, 1.1), pos + Vector3.new(0, 1.6, 0), Color3.fromRGB(58, 62, 68), Enum.Material.SmoothPlastic, false)
	local torso = makePart(model, "Torso", Vector3.new(3.4, 4.1, 1.5), pos + Vector3.new(0, 5.2, 0), suit, Enum.Material.SmoothPlastic, false)
	local head = makePart(model, "Head", Vector3.new(2.4, 2.4, 2.4), pos + Vector3.new(0, 8.8, 0), if style == "Bot" then Color3.fromRGB(205, 215, 218) else skin, Enum.Material.SmoothPlastic, false)
	head.Shape = Enum.PartType.Ball

	for _, x in ipairs({ -2.35, 2.35 }) do
		makePart(model, "Arm", Vector3.new(0.85, 3.6, 0.9), pos + Vector3.new(x, 5.25, 0), suit, Enum.Material.SmoothPlastic, false)
	end

	local visor = makePart(model, "Visor", Vector3.new(2, 0.35, 0.18), pos + Vector3.new(0, 9.05, 1.12 * face), trim, Enum.Material.SmoothPlastic, false)
	local badge = makePart(model, "Badge", Vector3.new(0.75, 0.75, 0.16), pos + Vector3.new(0.95, 5.75, 0.84 * face), accent, Enum.Material.SmoothPlastic, false)
	local tablet = makePart(model, "Tablet", Vector3.new(2.8, 1.5, 0.22), pos + Vector3.new(0, 4.6, 1.05 * face), LAB_DARK, Enum.Material.Metal, false)
	neonStrip(model, Vector3.new(2, 0.16, 0.16), tablet.Position + Vector3.new(0, 0.15, 0.13 * face), accent, 0.22)

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
		end
	end

	label(head, npcName, accent:Lerp(Color3.fromRGB(235, 245, 240), 0.45), 42, UDim2.fromOffset(170, 34), Vector3.new(0, 2.4, 0))
	return torso
end

-- Interaktiver Labor-Kiosk: Prompt oeffnet vorhandene UI-Menues clientseitig.
local function buildStationKiosk(parent, name, pos, accent, title, hint, menuTarget, actionText, npcName, npcStyle, faceSign)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local face = faceSign or 1
	local pillar = makePart(model, "KioskBody", Vector3.new(8, 9, 6), pos + Vector3.new(0, 4.2, 0), Color3.fromRGB(212, 217, 216), Enum.Material.SmoothPlastic, true)
	makePart(model, "KioskBase", Vector3.new(9.5, 0.8, 7.5), pos + Vector3.new(0, 0.1, 0), LAB_DARK, Enum.Material.Metal, true)
	makePart(model, "KioskDarkTop", Vector3.new(8.4, 1.1, 6.4), pos + Vector3.new(0, 9.2, 0), LAB_DARK, Enum.Material.SmoothPlastic, false)
	neonStrip(model, Vector3.new(7, 0.3, 0.3), pos + Vector3.new(0, 8.4, 3.05 * face), accent, 0.18)
	local screen = makePart(model, "KioskScreen", Vector3.new(5.6, 4.4, 0.25), pos + Vector3.new(0, 5.4, 3.05 * face), tint(accent, Color3.fromRGB(54, 70, 70), 0.4), Enum.Material.Neon, false)
	screen.Transparency = 0.12
	label(screen, title, Color3.fromRGB(236, 248, 242), 50, UDim2.fromOffset(160, 48), Vector3.new(0, 0, 0))

	local marqueePost = makePart(model, "StationMarqueePost", Vector3.new(0.75, 8, 0.75), pos + Vector3.new(-5.5, 4, 0), LAB_TRIM, Enum.Material.Metal, true)
	local marquee = makePart(model, "StationMarquee", Vector3.new(13, 3.6, 0.5), pos + Vector3.new(0, 12.2, 0), LAB_DARK, Enum.Material.SmoothPlastic, false)
	neonStrip(model, Vector3.new(11.4, 0.24, 0.24), marquee.Position + Vector3.new(0, -1.55, -0.3), accent, 0.26)
	label(marquee, title, Color3.fromRGB(245, 250, 248), 80, UDim2.fromOffset(220, 50), Vector3.new(0, 0, 0))

	local npcPromptPart = buildStationNpc(model, "NPC_" .. npcName:gsub("%s+", ""), pos + Vector3.new(0, 0, 7.1 * face), accent, npcName, npcStyle, face)
	npcPromptPart:SetAttribute("MenuTarget", menuTarget)
	makePrompt(npcPromptPart, menuTarget, actionText, npcName)

	local sampleA = makePart(model, "SampleCapsuleA", Vector3.new(1.4, 3.2, 1.4), pos + Vector3.new(-4.7, 2.4, 2.6 * face), Color3.fromRGB(180, 220, 210), Enum.Material.Glass, false)
	sampleA.Shape = Enum.PartType.Cylinder
	sampleA.Transparency = 0.42
	makePart(model, "SampleGlowA", Vector3.new(0.8, 2.1, 0.8), sampleA.Position, accent:Lerp(LAB_GREEN, 0.35), Enum.Material.SmoothPlastic, false).Shape = Enum.PartType.Ball
	local console = makePart(model, "ServiceConsole", Vector3.new(3.4, 2.1, 2.4), pos + Vector3.new(4.9, 1.55, 2.4 * face), LAB_DARK, Enum.Material.Metal, true)
	neonStrip(model, Vector3.new(2.3, 0.18, 0.18), console.Position + Vector3.new(0, 0.8, -1.25 * face), accent, 0.25)

	marqueePost.Transparency = 0
end

local function buildBiohazardDrum(parent, name, pos, accent)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	for i, off in ipairs({ Vector3.new(0, 0, 0), Vector3.new(4.4, 0, 0.8), Vector3.new(2.2, 0, -3.6) }) do
		local drum = makePart(model, "Drum" .. i, Vector3.new(3.6, 5, 3.6), pos + off + Vector3.new(0, 2.5, 0), tint(LAB_WARNING_YELLOW, LAB_DARK, 0.5), Enum.Material.Metal, true)
		drum.Shape = Enum.PartType.Cylinder
		drum.Orientation = Vector3.new(0, 0, 90)
		makePart(model, "DrumBand" .. i, Vector3.new(3.75, 0.7, 3.75), drum.Position, LAB_WARNING_YELLOW, Enum.Material.SmoothPlastic, false).Shape = Enum.PartType.Ball
		makePart(model, "DrumLid" .. i, Vector3.new(3.7, 0.4, 3.7), pos + off + Vector3.new(0, 5.1, 0), LAB_DARK, Enum.Material.Metal, false).Shape = Enum.PartType.Cylinder
	end
end

local function buildTutorialSign(parent, name, pos, text, accent)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	makePart(model, "SignPost", Vector3.new(0.6, 7, 0.6), pos + Vector3.new(0, 3.4, 0), LAB_TRIM, Enum.Material.Metal, true)
	local board = makePart(model, "SignBoard", Vector3.new(11, 4, 0.45), pos + Vector3.new(0, 7.6, 0), LAB_DARK, Enum.Material.SmoothPlastic, false)
	makePart(model, "SignBoardFrame", Vector3.new(11.6, 4.6, 0.3), pos + Vector3.new(0, 7.6, 0.1), accent:Lerp(LAB_DARK, 0.45), Enum.Material.SmoothPlastic, false)
	label(board, text, accent:Lerp(Color3.fromRGB(228, 242, 235), 0.45), 55, UDim2.fromOffset(220, 60), Vector3.new(0, 0, 0))
end

-- ---- Spawn Lab ------------------------------------------------------------

local function buildSpawnLab(parent, bedsFolder, orgFolders)
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

	-- Decken-Stufen-Bulkhead am Übergang Spawn -> Area 1 (X = 0). Die
	-- Spawn-Shell endet mit Decke auf Y = L.WallHeight (Slab 34..36), die
	-- Area-Decke liegt nach liftBacteriaLabCeiling 10 Studs höher (Slab
	-- 44..46). Dazwischen klafft eine senkrechte 8-Stud-Lücke (36..44),
	-- durch die der Himmel scheint. Der Bulkhead sitzt EXAKT in dieser
	-- Lücke (Y = 36..44) -- bündig zwischen den beiden Decken-Slabs, ohne
	-- mit ihnen zu überlappen (kein Z-Fighting wie beim Boden-Bug).
	buildCeilingStepBulkhead(
		model,
		0,
		FLOOR_Y + L.WallHeight + 2,
		FLOOR_Y + L.WallHeight + BACTERIA_CEILING_LIFT
	)

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
	spawnLoc.Color = Color3.fromRGB(170, 190, 178)
	spawnLoc.Material = Enum.Material.SmoothPlastic
	spawnLoc.Transparency = 0.08
	spawnLoc.TopSurface = Enum.SurfaceType.Smooth
	spawnLoc.Parent = model

	-- Hero-Objekt: zentrale Virus-Statue als Spawn-Landmarke (off-path, -Z).
	local heroFolder = makeFolder("HeroObjects", parent)
	buildVirusStatue(heroFolder, Vector3.new(cx, FLOOR_Y, -45), Color3.fromRGB(108, 196, 134))

	-- Einfache Glas-Zelle als Labor-Deko. Die alte "Virus Storage"-Zelle
	-- auf der Stationsseite bleibt weg, damit die Shop-Reihe frei wirkt.
	local gx = cx - 70
	local cell = makePart(model, "GlassCellResearch", Vector3.new(10, 14, 10), Vector3.new(gx, FLOOR_Y + 7, -60), Color3.fromRGB(180, 220, 230), Enum.Material.Glass, false)
	cell.Transparency = 0.55
	makePart(model, "CellBaseResearch", Vector3.new(11, 1, 11), Vector3.new(gx, FLOOR_Y + 0.5, -60), LAB_TRIM, Enum.Material.Metal, true)
	local cellSign = makePart(model, "CellSignResearch", Vector3.new(16, 4, 0.7), Vector3.new(gx, FLOOR_Y + 15.5, -60), LAB_DARK, Enum.Material.SmoothPlastic, false)
	label(cellSign, "RESEARCH", Color3.fromRGB(160, 245, 255), 45, UDim2.fromOffset(180, 44), Vector3.new(0, 0, 0))
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
	egg.CanQuery = true -- anklickbar (OpenEgg ClickDetector; Main verdrahtet)
	egg.Shape = Enum.PartType.Ball
	egg.Transparency = 0.05
	local cd = Instance.new("ClickDetector")
	cd.Name = "OpenEgg"
	cd.MaxActivationDistance = 16
	cd.Parent = egg
	label(egg, "PET EGG\nClick to open", Color3.fromRGB(180, 230, 255), 40, UDim2.fromOffset(190, 60), Vector3.new(0, 7, 0))
	VirusLabBuilder.PetEgg = egg

	local headerSign = makePart(model, "SpawnLabHeader", Vector3.new(0.7, 5, 38), Vector3.new(cx - 148, FLOOR_Y + L.WallHeight - 7, FLOOR_CENTER_Z), LAB_DARK, Enum.Material.SmoothPlastic, false)
	label(headerSign, "MUTATION LAB", Color3.fromRGB(150, 255, 220), 75, UDim2.fromOffset(300, 54), Vector3.new(0, 0, 0))

	-- ===== Hochwertiger Hub-Bereich rund um die Statue ===================
	-- Saubere Struktur in eigenen Map-Ordnern. Laufweg (z um 0) bleibt frei:
	-- alle kollidierenden Props liegen seitlich (z <= -22 bzw. weit hinten).
	local hub = orgFolders.hub
	local coreF = orgFolders.core
	local decoF = orgFolders.deco
	local termF = orgFolders.terminals
	local hubZ = -45
	local accentG = Color3.fromRGB(108, 196, 134)

	buildHubFloor(hub, cx, hubZ)

	-- Vier Hub-Pylonen an den Achteck-Diagonalen (seitlich, off-path).
	for i = 0, 3 do
		local a = math.pi / 4 + i * math.pi / 2
		local px = cx + math.cos(a) * 33
		local pz = hubZ + math.sin(a) * 33
		local pylon = makePart(coreF, "HubPylon", Vector3.new(2.6, 17, 2.6), Vector3.new(px, FLOOR_Y + 8.4, pz), LAB_WHITE, Enum.Material.SmoothPlastic, true)
		makePart(coreF, "HubPylonBase", Vector3.new(4, 1.2, 4), Vector3.new(px, FLOOR_Y + 0.5, pz), LAB_DARK, Enum.Material.Metal, true)
		neonStrip(coreF, Vector3.new(0.4, 12, 0.4), Vector3.new(px, FLOOR_Y + 9, pz - 1.45), LAB_CYAN, 0.2)
		makePart(coreF, "HubPylonCap", Vector3.new(3.4, 1.2, 3.4), Vector3.new(px, FLOOR_Y + 17.4, pz), LAB_DARK, Enum.Material.Metal, false)
		makePart(coreF, "HubPylonLamp", Vector3.new(1, 1, 1), Vector3.new(px, FLOOR_Y + 18.4, pz), LAB_GREEN, Enum.Material.Neon, false).Shape = Enum.PartType.Ball
	end

	-- Forschungs-Terminals / Monitore am Hub (Schirme zum Spieler).
	buildHubTerminal(termF, "HubTerminalGenome", Vector3.new(cx - 30, FLOOR_Y, hubZ + 12), LAB_CYAN, "GENOME", "MAP STABLE", Vector3.new(0, 0, 1))
	buildHubTerminal(termF, "HubTerminalVitals", Vector3.new(cx + 30, FLOOR_Y, hubZ + 12), LAB_GREEN, "VITALS", "ALL OK", Vector3.new(0, 0, 1))
	buildHubTerminal(termF, "HubTerminalContain", Vector3.new(cx, FLOOR_Y, hubZ - 34), LAB_CYAN, "CONTAINMENT", "SEALED", Vector3.new(0, 0, -1))

	-- Interaktive NPC-Stationen: oeffnen clientseitig dieselben Menues wie
	-- die Sidebar. Laufwege bleiben frei; alle Stationen liegen seitlich.
	local stations = {
		{ n = "UpgradeLabStation", t = "UPGRADE LAB", h = "Improve your mutation power", c = LAB_GREEN, dx = -64, z = 82, menu = "Skills", action = "Open Upgrades", npc = "Dr. Upgrade", style = "Lab" },
		{ n = "AuraStation", t = "AURA STATION", h = "Unlock mutation effects", c = Color3.fromRGB(132, 116, 170), dx = -24, z = 82, menu = "Auras", action = "Open Auras", npc = "Aura Dealer", style = "Dark" },
		{ n = "ShopTerminalStation", t = "SHOP", h = "Boosts & Items", c = LAB_CYAN, dx = 16, z = 82, menu = "Shop", action = "Open Shop", npc = "Shop Vendor", style = "Dark" },
		{ n = "DailyRewardStation", t = "DAILY REWARD", h = "Claim free rewards", c = LAB_WARNING_YELLOW, dx = 56, z = 82, menu = "Daily", action = "Claim Daily", npc = "Daily Bot", style = "Bot" },
	}
	for _, st in ipairs(stations) do
		buildStationKiosk(orgFolders.npcStations, st.n, Vector3.new(cx + st.dx, FLOOR_Y, st.z), st.c, st.t, st.h, st.menu, st.action, st.npc, st.style, -1)
	end

	-- Biohazard-Container / Glas-Tank / Kisten als Hub-Deko (off-path).
	buildBiohazardDrum(decoF, "HubBiohazardDrumsA", Vector3.new(cx - 60, FLOOR_Y, hubZ + 6), accentG)
	buildBiohazardDrum(decoF, "HubBiohazardDrumsB", Vector3.new(cx + 56, FLOOR_Y, hubZ + 4), accentG)
	buildContainmentTube(decoF, "HubGlassTankA", Vector3.new(cx - 78, FLOOR_Y, hubZ - 18), LAB_CYAN, "STRAIN A")
	buildContainmentTube(decoF, "HubGlassTankB", Vector3.new(cx + 78, FLOOR_Y, hubZ - 18), LAB_GREEN, "STRAIN B")
	buildCrateStack(decoF, "HubCratesA", Vector3.new(cx - 96, FLOOR_Y, hubZ + 30), LAB_CYAN)
	buildCrateStack(decoF, "HubCratesB", Vector3.new(cx + 90, FLOOR_Y, hubZ + 30), LAB_GREEN)

	-- Tutorial- und Richtungsschilder wurden entfernt, damit der Spawn
	-- cleaner wirkt und die NPC-Stationen nicht verdeckt werden.
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

-- ---- BugFixes-Pass --------------------------------------------------------
-- Sicherheitsnetz GEGEN den schwarzen Boden-Bug + schwebende Teile:
--  * Erzwingt Anchored=true (kein Zittern/Wegfallen von Deko).
--  * Hebt jede flache, nicht-kollidierende Flaeche, die exakt auf der
--    Boden-Oberkante (FLOOR_Y) liegt, auf eine eindeutige Hoehe -> es kann
--    nie wieder zu deckungsgleichem Z-Fighting mit dem Boden kommen.
-- Wirkt nur auf eindeutige Problemfaelle, aendert keine Spiel-Logik.
local function runBugFixes(bugFixes, scanRoots)
	local lifted = 0
	local anchored = 0
	for _, root in ipairs(scanRoots) do
		if root then
			for _, p in ipairs(root:GetDescendants()) do
				if p:IsA("BasePart") then
					if not p.Anchored then
						p.Anchored = true
						anchored += 1
					end
					local isFloor = (p.Name == "LabFloor")
					local flat = p.Size.Y <= 0.34
					local topY = p.Position.Y + p.Size.Y / 2
					if not isFloor and flat and not p.CanCollide and math.abs(topY - FLOOR_Y) <= 0.05 then
						-- Liegt deckungsgleich auf der Boden-Oberkante -> anheben.
						p.Position = Vector3.new(p.Position.X, LAYER_CONTAM + p.Size.Y / 2, p.Position.Z)
						lifted += 1
					end
				end
			end
		end
	end
	local note = makePart(bugFixes, "BugFixReport", Vector3.new(1, 1, 1), Vector3.new(L.SpawnCenterX, FLOOR_Y - 3, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, false)
	note.Transparency = 1
	note.CanTouch = false
	note:SetAttribute("CoplanarFloorPartsLifted", lifted)
	note:SetAttribute("PartsReanchored", anchored)
	note:SetAttribute("Info", "Schwarzer-Boden-Bug: Boden ueberlappt Baseplate, Deko auf eindeutigen LAYER_*-Hoehen, Gegner-Plattform versenkt.")
	print(string.format("[VirusLabBuilder/BugFixes] %d Boden-Decals entzerrt, %d Teile re-anchored.", lifted, anchored))
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

	-- Saubere, vom Nutzer gewuenschte Organisationsstruktur. Service-
	-- kritische Workspace-Ordner (EnemyAreas/EnemyBorders/AreaGates/
	-- EggStations/TrainingBeds/Portals/Map.ZoneTriggers) bleiben UNVERAENDERT
	-- an Ort und Stelle; hier kommen nur die ZUSAETZLICHEN Ordner dazu.
	local moveZones = makeFolder("EnemyMovementZones", Workspace)
	clearChildren(moveZones)
	local patrolPoints = makeFolder("EnemyPatrolPoints", Workspace)
	clearChildren(patrolPoints)
	local bugFixes = makeFolder("BugFixes", mapFolder)
	clearChildren(bugFixes)

	local spawnHub = makeFolder("SpawnHub", mapFolder)
	clearChildren(spawnHub)
	local orgFolders = {
		hub = spawnHub,
		core = makeFolder("SpawnCore", mapFolder),
		deco = makeFolder("SpawnDecor", mapFolder),
		terminals = makeFolder("SpawnTerminals", mapFolder),
		directions = makeFolder("SpawnDirections", mapFolder),
		npcStations = makeFolder("NPCStations", spawnHub),
		stationNPCs = makeFolder("StationNPCs", spawnHub),
		stationSigns = makeFolder("StationSigns", spawnHub),
		stationDecor = makeFolder("StationDecor", spawnHub),
	}
	for key, f in pairs(orgFolders) do
		if key ~= "hub" then
			clearChildren(f)
		end
	end

	local spawnFolder = makeFolder("SpawnLab", labFolder)
	buildSpawnLab(spawnFolder, bedsFolder, orgFolders)

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
		liftBacteriaLabCeiling(areaModel)
		addBacteriaLabDetails(areaModel, area, hallX, primary)

		-- Trainingsbereich (vor der Halle) + ggf. Rebirth-Gate.
		buildTrainingArea(areaModel, bedsFolder, gatesFolder, area, hallX + L.TrainingOffsetX)

		-- Gegner dieser Area.
		local defs = EnemyConfig.getByArea(area.id)
		local enemyAreaFolder = makeFolder(area.id, enemyFolder)
		local startX = hallX - (L.EnemySpacing * (L.EnemiesPerArea - 1)) / 2

		-- Labor-Luke: Power-Anforderung aus der zentralen Area-Progression.
		local gateReq = area.requiredPower
		buildGate(gatesFolder, area, hallX + L.GateOffsetX, gateReq)

		for i, def in ipairs(defs) do
			local ex = startX + L.EnemySpacing * (i - 1)
			local enemyZ = 0
			buildBacteriaEnemyChamber(enemyAreaFolder, def, Vector3.new(ex, FLOOR_Y, enemyZ), primary, secondary)
			local em = buildEnemyModel(enemyAreaFolder, def, Vector3.new(ex, FLOOR_Y, enemyZ), primary, secondary)

			-- Bewegungs-Zone + Patrol-Anker als saubere, unsichtbare Marker
			-- (rein organisatorisch/Debug, keine Kollision/Query).
			if em then
				local rx = em:GetAttribute("MoveRangeX") or 0
				local rz = em:GetAttribute("MoveRangeZ") or 0
				local hx = em:GetAttribute("HomeX") or ex
				local hy = em:GetAttribute("HomeY") or FLOOR_Y
				local hz = em:GetAttribute("HomeZ") or enemyZ
				local zone = makePart(moveZones, def.Id .. "_Zone", Vector3.new(math.max(2, rx * 2), 1, math.max(2, rz * 2)), Vector3.new(hx, CHAMBER_TOP + 0.5, hz), Color3.fromRGB(120, 200, 150), Enum.Material.SmoothPlastic, false)
				zone.Transparency = 1
				zone.CanTouch = false
				zone:SetAttribute("EnemyId", def.Id)
				zone:SetAttribute("MoveStyle", em:GetAttribute("MoveStyle"))
				local pp = makePart(patrolPoints, def.Id .. "_Home", Vector3.new(1, 1, 1), Vector3.new(hx, hy, hz), Color3.fromRGB(120, 200, 150), Enum.Material.SmoothPlastic, false)
				pp.Transparency = 1
				pp.CanTouch = false
				pp:SetAttribute("EnemyId", def.Id)
			end
			-- PWR-Border VOR jedem Gegner ab dem 2. (Progression).
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

		-- Abschlusswand nach der letzten Area. Höhe entspricht der GELIFTETEN
		-- Wand- und Decken-Höhe (L.WallHeight + BACTERIA_CEILING_LIFT), sonst
		-- bleibt oben ein 10-Stud-Spalt zwischen Wand-Oberkante und Decke,
		-- durch den der Himmel sichtbar wäre.
		if area.index == AreaConfig.count() then
			local finalWallHeight = L.WallHeight + BACTERIA_CEILING_LIFT
			makePart(
				areaModel,
				"FinalWall",
				Vector3.new(4, finalWallHeight, FLOOR_SIZE_Z),
				Vector3.new(hallX + L.AreaSpan / 2, FLOOR_Y + finalWallHeight / 2, FLOOR_CENTER_Z),
				LAB_DARK,
				Enum.Material.Metal,
				true
			)
		end
	end

	-- Abschliessender Sicherheits-Pass gegen schwarzen Boden / schwebende
	-- Teile (entzerrt deckungsgleiche Boden-Decals, erzwingt Anchored).
	runBugFixes(bugFixes, {
		labFolder,
		enemyFolder,
		orgFolders.hub,
		orgFolders.core,
		orgFolders.deco,
		orgFolders.terminals,
		orgFolders.directions,
	})

	print(string.format(
		"[VirusLabBuilder] %d Areale, %d Gegner, Borders + Gates + Egg-Stationen erzeugt.",
		AreaConfig.count(),
		#EnemyConfig.Enemies
	))
end

return VirusLabBuilder
