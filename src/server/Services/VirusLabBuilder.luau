--!nonstrict
-- VirusLabBuilder: datenbasierter Aufbau des Virus-Labor-Simulators.
--
-- Linearer Parcours entlang +X:
--   Spawn Lab (hinten) -> Trainingsbereich 1 -> Labor-Luke 1 ->
--   Area 1 (5 Gegner + PWR-Borders + 1 Pet-Egg-Station) -> Luke/Training 2 ->
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
--   * Workspace.EggStations  -> ClickDetector/Prompt "OpenEgg" + Egg-Attribute
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
local PetConfig = require(Configs:WaitForChild("PetConfig"))
local TrainingBedConfig = require(Configs:WaitForChild("TrainingBedConfig"))
local NumberFormatter = require(Modules:WaitForChild("NumberFormatter"))

local VirusLabBuilder = {}

local L = AreaConfig.Layout

-- ---- Basis-Farben (sauberes Labor) ---------------------------------------
local LAB_WHITE = Color3.fromRGB(232, 234, 234)
local LAB_PANEL = Color3.fromRGB(204, 208, 210)
local LAB_TRIM = Color3.fromRGB(138, 144, 146)
local LAB_DARK = Color3.fromRGB(20, 24, 27)
local LAB_CYAN = Color3.fromRGB(125, 180, 184)
local LAB_PURPLE = Color3.fromRGB(178, 110, 240) -- helles Akzent-Lila fuer Raum-Lichter
local LAB_PURPLE_SOFT = Color3.fromRGB(220, 198, 245) -- gedaempftes Lila fuer Deckenpanels
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
-- accent-Werte sind 1:1 mit den AREA_ACCENTS aus TeleportFrame -> jede Area
-- liest sich farblich genauso wie ihre Teleport-Karte.
local AreaThemes = {
	[1] = { id = "Bacteria", accent = Color3.fromRGB(0, 210, 190), contam = 0.14, sideProp = "BioTank", wallText = "BACTERIA LAB", hazard = "BIOHAZARD LEVEL B" },
	[2] = { id = "Quarantine", accent = Color3.fromRGB(255, 190, 40), contam = 0.05, sideProp = "QuarantineScanner", wallText = "QUARANTINE CORRIDOR", hazard = "BIOHAZARD - LEVEL 2" },
	[3] = { id = "MutationResearch", accent = Color3.fromRGB(80, 255, 120), contam = 0.18, sideProp = "MutationDNA", wallText = "MUTATION RESEARCH WING", hazard = "GENETIC INSTABILITY" },
	[4] = { id = "Processing", accent = Color3.fromRGB(255, 150, 55), contam = 0.30, sideProp = "ProcessingMachine", wallText = "BIOHAZARD PROCESSING", hazard = "HEAVY MACHINERY ACTIVE" },
	[5] = { id = "Cryo", accent = Color3.fromRGB(115, 210, 255), contam = 0.04, sideProp = "CryoCapsule", wallText = "CRYO CONTAINMENT", hazard = "SUB-ZERO - HANDLE WITH CARE" },
	[6] = { id = "ToxicReactor", accent = Color3.fromRGB(170, 255, 70), contam = 0.36, sideProp = "ToxicReactor", wallText = "TOXIC REACTOR FACILITY", hazard = "UNSTABLE REACTOR CORE" },
	[7] = { id = "Greenhouse", accent = Color3.fromRGB(120, 220, 145), contam = 0.42, sideProp = "SporePod", wallText = "INFECTED GREENHOUSE", hazard = "AIRBORNE SPORE WARNING" },
	[8] = { id = "BlackSite", accent = Color3.fromRGB(180, 90, 220), contam = 0.18, sideProp = "BlackSiteChamber", wallText = "BLACK SITE - CLASSIFIED", hazard = "LEVEL OMEGA - RESTRICTED" },
	[9] = { id = "OmegaDNA", accent = Color3.fromRGB(255, 220, 80), contam = 0.06, sideProp = "OmegaHelix", wallText = "OMEGA DNA CORE", hazard = "PROJECT OMEGA - SECURE" },
	[10] = { id = "FinalCore", accent = Color3.fromRGB(255, 70, 75), contam = 0.25, sideProp = "FinalVirusCore", wallText = "FINAL VIRUS CORE", hazard = "MAXIMUM CONTAINMENT" },
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

local function makeSurfaceGui(part: BasePart, name: string, canvas: Vector2, face: Enum.NormalId?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Adornee = part
	gui.Face = face or Enum.NormalId.Right
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = canvas
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = part
	return gui
end

local function surfaceText(parent: Instance, name: string, text: string, pos: UDim2, size: UDim2, color: Color3, textSize: number, bold: boolean?): TextLabel
	local tl = Instance.new("TextLabel")
	tl.Name = name
	tl.BackgroundTransparency = 1
	tl.Position = pos
	tl.Size = size
	tl.Text = text
	tl.Font = if bold == false then Enum.Font.GothamMedium else Enum.Font.GothamBold
	tl.TextColor3 = color
	tl.TextSize = textSize
	tl.TextScaled = false
	tl.TextXAlignment = Enum.TextXAlignment.Left
	tl.TextYAlignment = Enum.TextYAlignment.Center
	tl.TextStrokeTransparency = 1
	tl.Parent = parent
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

local function addLabTrim(parent, centerX, lengthX, primary)
	-- Wand-Paneele und Neon-Streifen voll in der Area-Farbe -> ganzer Korridor
	-- liest sich einheitlich farbig statt fast-weiss.
	local panelTintA = if primary then tint(Color3.fromRGB(218, 224, 226), primary, 0.72) else Color3.fromRGB(218, 224, 226)
	local panelTintB = if primary then tint(LAB_WHITE, primary, 0.58) else LAB_WHITE
	local neonColor = primary or LAB_PURPLE
	for _, z in ipairs({ CORRIDOR_MIN_Z + 0.2, CORRIDOR_MAX_Z - 0.2 }) do
		local panelZ = if z < FLOOR_CENTER_Z then CORRIDOR_MIN_Z + 0.35 else CORRIDOR_MAX_Z - 0.35
		for i = 0, 3 do
			local panelWidth = lengthX / 4 - 8
			local px = centerX - lengthX / 2 + lengthX * (i + 0.5) / 4
			local panelColor = if i % 2 == 0 then panelTintA else panelTintB
			makePart(parent, "WallLabPanel", Vector3.new(panelWidth, 15, 0.35), Vector3.new(px, FLOOR_Y + 14.5, panelZ), panelColor, Enum.Material.SmoothPlastic, false)
		end
		for _, y in ipairs({ FLOOR_Y + 4, FLOOR_Y + L.WallHeight - 8 }) do
			makePart(parent, "WallBlackTrim", Vector3.new(lengthX, 1.1, 0.35), Vector3.new(centerX, y, z), LAB_DARK, Enum.Material.SmoothPlastic, false)
		end
		neonStrip(parent, Vector3.new(lengthX - 16, 0.35, 0.35), Vector3.new(centerX, FLOOR_Y + L.WallHeight - 13, panelZ), neonColor, 0.25)
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
			local lightPanel = makePart(parent, "RoofLightPanel", Vector3.new(24, 0.28, 10), Vector3.new(px, FLOOR_Y + L.WallHeight - 2.95, z), LAB_PURPLE_SOFT, Enum.Material.Neon, false)
			lightPanel.Transparency = 0.18
			-- Echte Lichtquelle: SurfaceLight nach unten beleuchtet den Boden.
			local sl = Instance.new("SurfaceLight")
			sl.Face = Enum.NormalId.Bottom
			sl.Brightness = 2.6
			sl.Range = 38
			sl.Angle = 150
			sl.Color = Color3.fromRGB(238, 226, 255)
			sl.Shadows = false
			sl.Parent = lightPanel
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

	-- Boden + Wand-Tint: pro Area DEUTLICH eingefaerbt, damit die Area schon
	-- aus der Distanz an ihrer Farbe erkennbar ist. Spawn-Lab (kein areaId)
	-- bleibt neutral.
	local floorBase = Color3.fromRGB(202, 206, 208)
	local wallBase = LAB_WHITE
	local ceilingBase = Color3.fromRGB(207, 212, 211)
	local floorColor = if areaId then tint(floorBase, primary, 0.72) else floorBase
	local wallColor = if areaId then tint(wallBase, primary, 0.62) else wallBase
	local ceilingColor = if areaId then tint(ceilingBase, primary, 0.42) else ceilingBase

	-- Boden. Dick genug, dass die Unterkante (FLOOR_Y - FLOOR_THICKNESS) die
	-- dunkle Baseplate (Oberkante Y=-2) als Schnittkoerper durchdringt --
	-- keine deckungsgleiche Flaeche -> kein schwarzes Z-Fighting mehr.
	local floor = makePart(
		parent,
		"LabFloor",
		Vector3.new(lengthX, FLOOR_THICKNESS, FLOOR_SIZE_Z),
		Vector3.new(centerX, FLOOR_Y - FLOOR_THICKNESS / 2, FLOOR_CENTER_Z),
		floorColor,
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
		ceilingColor,
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
	local ceilingPanelBase = Color3.fromRGB(186, 192, 191)
	local ceilingPanelColor = if areaId then tint(ceilingPanelBase, primary, 0.50) else ceilingPanelBase
	for i = 0, 2 do
		local px = centerX - lengthX / 2 + lengthX * (i + 0.5) / 3
		makePart(
			parent,
			"CeilingPanel",
			Vector3.new(lengthX / 3 - 10, 0.18, FLOOR_SIZE_Z - 18),
			Vector3.new(px, FLOOR_Y + L.WallHeight - 0.15, FLOOR_CENTER_Z),
			ceilingPanelColor,
			Enum.Material.SmoothPlastic,
			false
		)
	end

	-- Seitenwaende (Area-getoent ueber wallColor).
	makePart(
		parent,
		"LabWallLeft",
		Vector3.new(lengthX, L.WallHeight, 4),
		Vector3.new(centerX, FLOOR_Y + L.WallHeight / 2, CORRIDOR_MIN_Z - 2),
		wallColor,
		Enum.Material.SmoothPlastic,
		true
	)
	makePart(
		parent,
		"LabWallRight",
		Vector3.new(lengthX, L.WallHeight, 4),
		Vector3.new(centerX, FLOOR_Y + L.WallHeight / 2, CORRIDOR_MAX_Z + 2),
		wallColor,
		Enum.Material.SmoothPlastic,
		true
	)
	addLabTrim(parent, centerX, lengthX, if areaId then primary else nil)

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

-- ---- Norovirus-Set fuer Area 1 ------------------------------------------
-- 5 humanoide Wesen mit progressivem Mutations-/Armor-Look. Groessen (Boden
-- bis Kopfoberkante): 5.0 / 6.2 / 7.4 / 8.6 / 9.8 Studs (jeweils +~1 Robloxkopf).
-- Vertrag bleibt identisch: Model(def.Id) + EnemyCore PrimaryPart (CanQuery)
-- + AttackClick + HealthBar* + Label, fuer Boss zusaetzlich StartBossFight
-- ProximityPrompt und BossPad. MoveStyle wird aus def.Shape uebernommen
-- (Bewegungen bleiben gleich, nur Design aendert sich).
local function buildNorovirusEnemyModel(parent, def, basePos, primary, secondary)
	local model = Instance.new("Model")
	model.Name = def.Id
	model:SetAttribute("EnemyId", def.Id)
	model:SetAttribute("AreaName", def.AreaName)
	model:SetAttribute("IsBoss", def.IsBoss)
	model.Parent = parent

	-- Stage-Daten: 1..4 sind die Mutationsstufen, 5 = Boss.
	local stage = def.EnemyIndex
	local isBoss = def.IsBoss
	local totalHeights = { 5.0, 6.2, 7.4, 8.6, 9.8 }
	local totalH = totalHeights[stage] or 5.0

	-- Koerperproportionen (chibi -> humanoid progression). Boss bekommt
	-- zusaetzliche Breite/Tiefe, damit er optisch deutlich massiger als
	-- Stage 4 wirkt (Reference: Boss ist ~1.5x breiter).
	local legH = 1.6 + (stage - 1) * 0.45
	local headD = 2.0 + (stage - 1) * 0.30 + (if isBoss then 0.6 else 0)
	local torsoH = totalH - legH - headD * 0.45
	if torsoH < 0.8 then
		torsoH = 0.8
	end
	local torsoW = 1.5 + (stage - 1) * 0.35 + (if isBoss then 1.3 else 0)
	local torsoD = torsoW * 0.55 + (if isBoss then 0.5 else 0)
	local legW = 0.62 + (stage - 1) * 0.10 + (if isBoss then 0.35 else 0)

	-- Farben (Norovirus-Palette).
	local bodyGreen = Color3.fromRGB(126, 200, 78)
	local bodyDeep = Color3.fromRGB(82, 140, 52)
	local glowGreen = Color3.fromRGB(190, 255, 88)
	local armorDark = Color3.fromRGB(36, 48, 30)
	local armorMid = Color3.fromRGB(72, 90, 56)
	local spikeColor = Color3.fromRGB(28, 34, 24)
	local hazardYellow = Color3.fromRGB(225, 200, 75)
	local slimeDrip = Color3.fromRGB(160, 230, 80)

	-- Y-Positionen.
	local groundY = CHAMBER_TOP
	local hipY = groundY + legH
	local torsoCenterY = hipY + torsoH / 2
	local neckY = hipY + torsoH
	local headCenterY = neckY + headD / 2 - headD * 0.05

	local cx, cz = basePos.X, basePos.Z

	-- EnemyCore = unsichtbare Bounding-Box ueber das gesamte Wesen. Clicks
	-- treffen via Raycast diese Box (alle Deko-Parts haben CanQuery=false).
	local boxW = math.max(torsoW + 0.8 + (if isBoss then 2.0 else 0), headD + 0.6)
	local boxH = totalH
	local boxD = torsoD + (if stage >= 3 then 0.8 else 0.4) + (if isBoss then 1.2 else 0)
	local root = makePart(model, "EnemyCore", Vector3.new(boxW, boxH, boxD), Vector3.new(cx, groundY + boxH / 2, cz), bodyDeep, Enum.Material.SmoothPlastic, false)
	root.CanQuery = true
	root.Transparency = 1
	model.PrimaryPart = root

	-- ---- Beine ---------------------------------------------------------
	local legSpacing = torsoW * 0.32
	for _, side in ipairs({ -1, 1 }) do
		makePart(model, "NoroLeg", Vector3.new(legW, legH * 0.9, legW), Vector3.new(cx + side * legSpacing, hipY - legH * 0.5, cz), armorMid, Enum.Material.SmoothPlastic, false)
		-- Hueftgelenk-Punkt
		local hip = makePart(model, "NoroHip", Vector3.new(legW * 1.1, legH * 0.18, legW * 1.1), Vector3.new(cx + side * legSpacing, hipY - legH * 0.05, cz), armorDark, Enum.Material.Metal, false)
		hip.Shape = Enum.PartType.Ball
		-- Stiefel
		makePart(model, "NoroBoot", Vector3.new(legW * 1.25, legH * 0.18, legW * 1.4), Vector3.new(cx + side * legSpacing, groundY + legH * 0.09, cz + legW * 0.1), armorDark, Enum.Material.Metal, false)
	end

	-- ---- Torso ---------------------------------------------------------
	local torso = makePart(model, "NoroTorso", Vector3.new(torsoW, torsoH, torsoD), Vector3.new(cx, torsoCenterY, cz), bodyDeep, Enum.Material.SmoothPlastic, false)
	torso.Transparency = 0
	-- Bauch-Lumps (Pickel/Blasen wie auf dem Kopf, vorne aufs Body).
	local bodyLumpCount = 4 + stage
	for i = 1, bodyLumpCount do
		local seed = i * 2.3
		local px = math.sin(seed) * 0.35 * torsoW
		local py = math.cos(seed * 1.1) * 0.4 * torsoH
		local lumpSize = torsoW * (0.18 + (i % 3) * 0.05)
		local lump = makePart(model, "NoroBodyLump", Vector3.new(lumpSize, lumpSize, lumpSize * 0.7), Vector3.new(cx + px, torsoCenterY + py, cz - torsoD / 2 - lumpSize * 0.2), tint(bodyGreen, bodyDeep, (i % 2) * 0.2), Enum.Material.SmoothPlastic, false)
		lump.Shape = Enum.PartType.Ball
	end
	-- Tropfen-Schleim, der von der Unterseite haengt (mehr, dichter, glow).
	local dripCount = 6 + stage * 2 + (if isBoss then 4 else 0)
	for i = 1, dripCount do
		local seed = i * 1.9
		-- Verteilung entlang der Unterkante des Torsos.
		local t = (i - 0.5) / dripCount
		local dx = (t - 0.5) * torsoW * 0.85
		local dz = -torsoD / 2 - 0.05 - math.sin(seed) * 0.15
		local dripH = 0.5 + (i % 4) * 0.35
		local drip = makePart(model, "NoroBellyDrip", Vector3.new(0.22, dripH, 0.22), Vector3.new(cx + dx, torsoCenterY - torsoH / 2 - dripH * 0.45, cz + dz), slimeDrip, Enum.Material.SmoothPlastic, false)
		drip.Transparency = 0.15
		-- Glow-Tropfen-Tip
		makePart(model, "NoroBellyDripTip", Vector3.new(0.28, 0.18, 0.28), Vector3.new(cx + dx, torsoCenterY - torsoH / 2 - dripH * 0.95, cz + dz), glowGreen, Enum.Material.Neon, false).Shape = Enum.PartType.Ball
	end

	-- ---- Schulterpanzer (Stage 2+) ------------------------------------
	if stage >= 2 then
		for _, side in ipairs({ -1, 1 }) do
			local padW = torsoW * 0.42 + (stage - 2) * 0.18 + (if isBoss then 0.8 else 0)
			local padH = torsoH * 0.45 + (stage - 2) * 0.12 + (if isBoss then 0.6 else 0)
			local padX = cx + side * (torsoW * 0.5 + padW * 0.3)
			local padY = torsoCenterY + torsoH * 0.42
			local pad = makePart(model, "NoroShoulderPad", Vector3.new(padW, padH, torsoD * 1.2), Vector3.new(padX, padY, cz), armorDark, Enum.Material.Metal, false)
			pad.Orientation = Vector3.new(0, 0, side * -15)
			-- Stachel oben drauf (Stage 3+)
			if stage >= 3 then
				local spikeCount = stage - 1 + (if isBoss then 2 else 0)
				for k = 1, spikeCount do
					local sx = padX + (k - (spikeCount + 1) / 2) * 0.45
					makePart(model, "NoroShoulderSpike", Vector3.new(0.32, 0.7 + (stage - 3) * 0.25 + (if isBoss then 1.2 else 0), 0.32), Vector3.new(sx, padY + padH * 0.5 + 0.4, cz), spikeColor, Enum.Material.Metal, false)
					makePart(model, "NoroShoulderSpikeTip", Vector3.new(0.36, 0.18, 0.36), Vector3.new(sx, padY + padH * 0.5 + 0.85 + (stage - 3) * 0.25 + (if isBoss then 1.2 else 0), cz), tint(spikeColor, glowGreen, 0.25), Enum.Material.SmoothPlastic, false)
				end
			end
		end
	end

	-- ---- Arme (alle Stages, Detail steigt) ----------------------------
	local armLen = torsoH * 0.95
	local armW = torsoW * 0.22 + (stage - 1) * 0.05
	for _, side in ipairs({ -1, 1 }) do
		local armX = cx + side * (torsoW * 0.55 + armW * 0.3)
		local armY = torsoCenterY - torsoH * 0.05
		makePart(model, "NoroArm", Vector3.new(armW, armLen, armW), Vector3.new(armX, armY, cz), bodyDeep, Enum.Material.SmoothPlastic, false)
		-- Hand / Faust
		local handSize = armW * 1.4
		local handY = armY - armLen * 0.5 - handSize * 0.3
		if stage >= 3 then
			-- Klauenhand (Stage 3+): Hand-Kern + 3 Klauenstacheln nach unten
			local hand = makePart(model, "NoroClawHand", Vector3.new(handSize, handSize * 0.8, handSize), Vector3.new(armX, handY, cz), armorMid, Enum.Material.Metal, false)
			hand.Shape = Enum.PartType.Ball
			for k = -1, 1 do
				local cx_claw = armX + k * handSize * 0.32
				local claw = makePart(model, "NoroClaw", Vector3.new(0.22, handSize * 0.9 + (stage - 3) * 0.25, 0.22), Vector3.new(cx_claw, handY - handSize * 0.55, cz + handSize * 0.1), spikeColor, Enum.Material.Metal, false)
				makePart(model, "NoroClawTip", Vector3.new(0.24, 0.18, 0.24), Vector3.new(cx_claw, handY - handSize * 0.95 - (stage - 3) * 0.15, cz + handSize * 0.1), tint(spikeColor, glowGreen, 0.3), Enum.Material.SmoothPlastic, false)
			end
		else
			-- Einfache Faust (Stage 1-2)
			local fist = makePart(model, "NoroFist", Vector3.new(handSize, handSize, handSize), Vector3.new(armX, handY, cz), armorMid, Enum.Material.SmoothPlastic, false)
			fist.Shape = Enum.PartType.Ball
		end
	end

	-- ---- Brustpanzer (Stage 3+) ---------------------------------------
	if stage >= 3 then
		local plateW = torsoW * 0.85
		local plateH = torsoH * 0.62
		local plate = makePart(model, "NoroChestPlate", Vector3.new(plateW, plateH, 0.18), Vector3.new(cx, torsoCenterY + torsoH * 0.05, cz - torsoD / 2 - 0.12), armorMid, Enum.Material.Metal, false)
		-- Biohazard-Symbol auf der Brust
		local hazard = makePart(model, "NoroHazardSymbol", Vector3.new(plateW * 0.4, plateH * 0.5, 0.06), Vector3.new(cx, torsoCenterY + torsoH * 0.05, cz - torsoD / 2 - 0.22), hazardYellow, Enum.Material.Neon, false)
		hazard.Transparency = 0.15
	end

	-- ---- Glow-Kern auf der Brust (Stage 4+, BOSS sehr prominent) -----
	if stage >= 4 then
		local coreSize = if isBoss then headD * 0.75 else headD * 0.45
		local core = makePart(model, "NoroChestCore", Vector3.new(coreSize, coreSize, coreSize * 0.5), Vector3.new(cx, torsoCenterY + torsoH * 0.08, cz - torsoD / 2 - 0.15), glowGreen, Enum.Material.Neon, false)
		core.Shape = Enum.PartType.Ball
		core.Transparency = 0.1
		-- Aeusserer Glasring
		local outerRing = makePart(model, "NoroChestCoreOuter", Vector3.new(coreSize * 1.4, coreSize * 1.4, coreSize * 0.3), Vector3.new(cx, torsoCenterY + torsoH * 0.08, cz - torsoD / 2 - 0.05), tint(glowGreen, Color3.fromRGB(240, 250, 220), 0.3), Enum.Material.Glass, false)
		outerRing.Shape = Enum.PartType.Ball
		outerRing.Transparency = 0.5
		local pl = Instance.new("PointLight")
		pl.Brightness = if isBoss then 3 else 1.6
		pl.Range = if isBoss then 26 else 14
		pl.Color = glowGreen
		pl.Parent = core
	end

	-- ---- Kopf: stachelige, mit Blasen uebersaete gruene Kugel ---------
	local head = makePart(model, "NoroHead", Vector3.new(headD * 1.02, headD * 1.08, headD), Vector3.new(cx, headCenterY, cz), bodyGreen, Enum.Material.SmoothPlastic, false)
	head.Shape = Enum.PartType.Ball

	-- Lumps / Blasen auf dem Kopf -> Norovirus-Pickel-Look statt glatter Kugel.
	-- Dicht und in unterschiedlichen Groessen, ueberlappen sich teilweise.
	local lumpCount = 14 + stage * 2 + (if isBoss then 8 else 0)
	for i = 1, lumpCount do
		local seed = i * 1.7
		local a = seed
		-- Volle Sphaere abdecken aber Vorderseite klar bevorzugen.
		local up = math.sin(seed * 1.3) * 0.85
		local fwd = 0.2 + math.cos(seed * 0.9) * 0.7
		local dir = Vector3.new(math.cos(a) * fwd, up, math.sin(a) * fwd).Unit
		local lumpSize = headD * (0.25 + (i % 5) * 0.07)
		local lumpCenter = Vector3.new(cx, headCenterY, cz) + dir * headD * 0.46
		local lump = makePart(model, "NoroHeadLump", Vector3.new(lumpSize, lumpSize, lumpSize), lumpCenter, tint(bodyGreen, bodyDeep, (i % 3) * 0.18), Enum.Material.SmoothPlastic, false)
		lump.Shape = Enum.PartType.Ball
	end

	-- Stacheln: dichte Krone oben + zusaetzliche Reihe ringsum.
	local crownCount = 8 + stage * 2 + (if isBoss then 8 else 0)
	local spikeLen = headD * 0.45 + (stage - 1) * 0.08
	-- Obere Krone (steht relativ aufrecht nach oben).
	for i = 1, crownCount do
		local a = (i / crownCount) * math.pi * 2
		local up = 0.85 + math.sin(i * 0.7) * 0.15
		local fwd = math.cos(a) * 0.55
		local dir = Vector3.new(fwd, up, math.sin(a) * 0.55).Unit
		local spikeCenter = Vector3.new(cx, headCenterY, cz) + dir * headD * 0.52
		local spike = makePart(model, "NoroHeadSpike", Vector3.new(spikeLen * 0.36, spikeLen, spikeLen * 0.36), spikeCenter, spikeColor, Enum.Material.Metal, false)
		local upv = if math.abs(dir.Y) > 0.95 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
		spike.CFrame = CFrame.lookAt(spikeCenter, spikeCenter + dir, upv) * CFrame.Angles(math.rad(90), 0, 0)
		makePart(model, "NoroHeadSpikeTip", Vector3.new(spikeLen * 0.4, spikeLen * 0.22, spikeLen * 0.4), spikeCenter + dir * (spikeLen * 0.55), tint(spikeColor, glowGreen, 0.35), Enum.Material.SmoothPlastic, false)
	end
	-- Seitenkranz (kuerzere Stacheln seitlich, ergaenzt die Krone).
	local sideCount = 6 + stage + (if isBoss then 4 else 0)
	local sideLen = spikeLen * 0.7
	for i = 1, sideCount do
		local a = (i / sideCount) * math.pi * 2
		local up = 0.35 + math.sin(i * 0.9) * 0.15
		local fwd = math.cos(a) * 0.85
		local dir = Vector3.new(fwd, up, math.sin(a) * 0.85).Unit
		local spikeCenter = Vector3.new(cx, headCenterY, cz) + dir * headD * 0.55
		local spike = makePart(model, "NoroSideSpike", Vector3.new(sideLen * 0.3, sideLen, sideLen * 0.3), spikeCenter, spikeColor, Enum.Material.Metal, false)
		spike.CFrame = CFrame.lookAt(spikeCenter, spikeCenter + dir, Vector3.new(0, 1, 0)) * CFrame.Angles(math.rad(90), 0, 0)
		makePart(model, "NoroSideSpikeTip", Vector3.new(sideLen * 0.34, sideLen * 0.2, sideLen * 0.34), spikeCenter + dir * (sideLen * 0.55), tint(spikeColor, glowGreen, 0.4), Enum.Material.SmoothPlastic, false)
	end

	-- Gesicht (Vorderseite, -Z): boese Augen + breites Maul mit Zaehnen.
	-- Augen: 2 angewinkelte Parts pro Seite -> Slit-Optik wie im Reference.
	local eyeY = headCenterY + headD * 0.08
	local eyeW = headD * 0.28
	local eyeH = headD * 0.10
	for _, side in ipairs({ -1, 1 }) do
		-- Heller Glow-Hintergrund
		local eyeGlow = makePart(model, "NoroEyeGlow", Vector3.new(eyeW, eyeH * 1.3, 0.12), Vector3.new(cx + side * headD * 0.22, eyeY, cz - headD * 0.48), tint(glowGreen, Color3.fromRGB(240, 255, 180), 0.3), Enum.Material.Neon, false)
		eyeGlow.Transparency = 0.08
		eyeGlow.Orientation = Vector3.new(0, 0, side * -22) -- gefaehrlich verkniffener Blick
		-- Dunkler Slit oben drueber (Augenlid-Effekt)
		local eyeLid = makePart(model, "NoroEyeLid", Vector3.new(eyeW * 1.1, eyeH * 0.7, 0.16), Vector3.new(cx + side * headD * 0.22, eyeY + headD * 0.045, cz - headD * 0.5), spikeColor, Enum.Material.SmoothPlastic, false)
		eyeLid.Orientation = Vector3.new(0, 0, side * -22)
	end

	-- Maul: breiter, leuchtender Schlund mit 7 Zaehnen (Reissmaul-Look).
	local mouthY = headCenterY - headD * 0.26
	local mouthW = headD * 0.72
	local mouthH = headD * 0.22
	local mouth = makePart(model, "NoroMouth", Vector3.new(mouthW, mouthH, 0.14), Vector3.new(cx, mouthY, cz - headD * 0.46), glowGreen, Enum.Material.Neon, false)
	mouth.Transparency = 0.05
	-- Zickzack-Zaehne (oben und unten unterschiedlich) -> Reissmaul
	local toothCount = 7
	for i = 1, toothCount do
		local t = (i - (toothCount + 1) / 2) / toothCount
		local upper = i % 2 == 1
		local toothH_local = mouthH * (if upper then 0.85 else 0.65)
		local toothY = mouthY + (if upper then mouthH * 0.1 else -mouthH * 0.18)
		makePart(model, "NoroTooth", Vector3.new(mouthW * 0.085, toothH_local, 0.2), Vector3.new(cx + t * mouthW * 0.95, toothY, cz - headD * 0.48), tint(Color3.fromRGB(240, 244, 220), spikeColor, 0.1), Enum.Material.SmoothPlastic, false)
	end
	-- Maul-Rahmen (dunkler Rand)
	makePart(model, "NoroMouthFrameTop", Vector3.new(mouthW * 1.05, mouthH * 0.18, 0.18), Vector3.new(cx, mouthY + mouthH * 0.5, cz - headD * 0.47), spikeColor, Enum.Material.SmoothPlastic, false)
	makePart(model, "NoroMouthFrameBottom", Vector3.new(mouthW * 1.05, mouthH * 0.18, 0.18), Vector3.new(cx, mouthY - mouthH * 0.5, cz - headD * 0.47), spikeColor, Enum.Material.SmoothPlastic, false)

	-- ---- BOSS-Extras: massive Schulterspike + Glow-Pad ----------------
	if isBoss then
		-- Grosse Schulter-Spikes aus dem Ruecken (5 pro Seite, fächerförmig).
		for _, side in ipairs({ -1, 1 }) do
			for i = 1, 5 do
				local angle = (i - 3) * 0.28
				local spikeLen2 = totalH * 0.45 + i * 0.15
				local sx = cx + side * (torsoW * 0.6 + i * 0.15)
				local sy = torsoCenterY + torsoH * 0.45 + math.cos(angle) * 0.6
				local sz = cz + math.sin(angle) * 0.5 + 0.4
				local spike = makePart(model, "BossNoroSpike", Vector3.new(0.55, spikeLen2, 0.55), Vector3.new(sx, sy, sz), spikeColor, Enum.Material.Metal, false)
				spike.Orientation = Vector3.new(20, side * 25 + math.deg(angle) * 20, side * 35)
				makePart(model, "BossNoroSpikeTip", Vector3.new(0.62, 0.45, 0.62), spike.Position + Vector3.new(side * 0.25, spikeLen2 * 0.45, 0.1), tint(spikeColor, glowGreen, 0.4), Enum.Material.Neon, false)
			end
		end

		-- Glow-Pad / Ring um den Boss (BossPad bleibt sichtbar, da Name-Whitelist)
		local ring = makePart(model, "BossPad", Vector3.new(0.5, totalH * 1.1, totalH * 1.1), Vector3.new(basePos.X, CHAMBER_TOP + 1.25, basePos.Z), glowGreen, Enum.Material.Neon, false)
		ring.Shape = Enum.PartType.Cylinder
		ring.Orientation = Vector3.new(0, 0, 90)
		ring.Transparency = 0.35
		-- Schleim-Wolke unter dem Boss
		local pool = makePart(model, "BossNoroSlimePool", Vector3.new(0.3, totalH * 1.3, totalH * 1.3), Vector3.new(basePos.X, CHAMBER_TOP + 0.05, basePos.Z), slimeDrip, Enum.Material.SmoothPlastic, false)
		pool.Shape = Enum.PartType.Cylinder
		pool.Orientation = Vector3.new(0, 0, 90)
		pool.Transparency = 0.45
	end

	-- ---- Schleim-Drip-Partikel (alle Stages, intensiver bei Boss) -----
	local drip = Instance.new("ParticleEmitter")
	drip.Name = "NorovirusDrip"
	drip.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	drip.Color = ColorSequence.new(glowGreen, tint(slimeDrip, bodyDeep, 0.5))
	drip.LightEmission = 0.3
	drip.Rate = if isBoss then 14 else 3 + stage
	drip.Lifetime = NumberRange.new(0.8, 1.4)
	drip.Speed = NumberRange.new(0.4, 1.2)
	drip.Acceleration = Vector3.new(0, -6, 0)
	drip.SpreadAngle = Vector2.new(30, 30)
	drip.Size = NumberSequence.new(0.35, 0.05)
	drip.Parent = head

	-- ---- Bewegung uebernehmen aus def.Shape (Movements bleiben gleich)
	local arche = ENEMY_ARCHETYPE[def.Shape] or ENEMY_ARCHETYPE.Blob
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
	model:SetAttribute("HomeX", cx)
	model:SetAttribute("HomeY", root.Position.Y)
	model:SetAttribute("HomeZ", cz)
	model:SetAttribute("MoveRangeX", mv.rx)
	model:SetAttribute("MoveRangeZ", mv.rz)
	model:SetAttribute("MoveSpeed", mv.sp)
	model:SetAttribute("BobAmp", mv.bob)
	model:SetAttribute("EnemyKind", "Norovirus")

	-- ---- Health-Bar (Vertrag mit EnemyService.updateEnemy) ------------
	local barScale = if isBoss then 1.9 else 1
	local barY = groundY + totalH + (if isBoss then 2.4 else 1.6)
	local barBack = makePart(model, "HealthBarBack", Vector3.new(13 * barScale, 0.8, 0.4), Vector3.new(cx, barY, cz), Color3.fromRGB(16, 20, 26), Enum.Material.SmoothPlastic, false)
	local barFill = makePart(model, "HealthBarFill", Vector3.new(12.4 * barScale, 0.5, 0.55), Vector3.new(cx, barY + 0.02, cz - 0.06), Color3.fromRGB(95, 255, 125), Enum.Material.Neon, false)
	barFill.Transparency = 0.12
	barFill:SetAttribute("MaxWidth", 12.4 * barScale)
	barFill:SetAttribute("FullCenterX", barFill.Position.X)

	-- ---- AttackClick + (Boss) StartBossFight Prompt -------------------
	local clicker = Instance.new("ClickDetector")
	clicker.Name = "AttackClick"
	clicker.MaxActivationDistance = EnemyConfig.AttackDistance
	clicker.Parent = root

	if isBoss then
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

	-- ---- Info-Label ---------------------------------------------------
	local prefix = if isBoss then "★ BOSS ★\n" else ""
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
		if isBoss then 60 else 34,
		UDim2.fromOffset(if isBoss then 280 else 190, if isBoss then 104 else 76),
		Vector3.new(0, boxH / 2 + 3, 0)
	)

	return model
end

-- ---- Hantavirus-Set fuer Area 2 -----------------------------------------
-- Ratten-Humanoide in dreckigem Laborkittel mit pinkem Mutationsbefall.
-- Boss bekommt gruene Reagenz-Tubes auf dem Ruecken (Kontrast zu Stage 1-4
-- in pink). Gleiche Stage-Hoehen wie Area 1: 5.0/6.2/7.4/8.6/9.8 Studs.
local function buildHantavirusEnemyModel(parent, def, basePos, primary, secondary)
	local model = Instance.new("Model")
	model.Name = def.Id
	model:SetAttribute("EnemyId", def.Id)
	model:SetAttribute("AreaName", def.AreaName)
	model:SetAttribute("IsBoss", def.IsBoss)
	model.Parent = parent

	local stage = def.EnemyIndex
	local isBoss = def.IsBoss
	local totalHeights = { 5.0, 6.2, 7.4, 8.6, 9.8 }
	local totalH = totalHeights[stage] or 5.0

	local legH = 1.6 + (stage - 1) * 0.45
	local headD = 1.8 + (stage - 1) * 0.28 + (if isBoss then 0.5 else 0)
	local torsoH = totalH - legH - headD * 0.40
	if torsoH < 0.8 then
		torsoH = 0.8
	end
	local torsoW = 1.7 + (stage - 1) * 0.38 + (if isBoss then 1.4 else 0)
	local torsoD = torsoW * 0.58 + (if isBoss then 0.5 else 0)
	local legW = 0.65 + (stage - 1) * 0.12 + (if isBoss then 0.35 else 0)

	-- Hantavirus-Farbpalette: dreckiges Labor + pinke Mutation + roter Glow.
	local furGrey = Color3.fromRGB(96, 84, 78)
	local furDeep = Color3.fromRGB(58, 48, 44)
	local coatWhite = Color3.fromRGB(218, 210, 195)
	local coatShadow = Color3.fromRGB(160, 152, 138)
	local coatDirty = Color3.fromRGB(132, 116, 96)
	local mutationPink = Color3.fromRGB(195, 88, 105)
	local mutationDeep = Color3.fromRGB(140, 50, 60)
	local mutationGlow = Color3.fromRGB(255, 86, 110)
	local bossTubeGreen = Color3.fromRGB(86, 230, 96)
	local armorDark = Color3.fromRGB(45, 38, 35)
	local armorMetal = Color3.fromRGB(95, 85, 78)
	local hazardYellow = Color3.fromRGB(225, 195, 70)
	local tailColor = Color3.fromRGB(160, 75, 90)
	local noseColor = Color3.fromRGB(28, 22, 22)

	local groundY = CHAMBER_TOP
	local hipY = groundY + legH
	local torsoCenterY = hipY + torsoH / 2
	local neckY = hipY + torsoH
	local headCenterY = neckY + headD / 2 - headD * 0.05
	local cx, cz = basePos.X, basePos.Z

	-- EnemyCore = unsichtbare Bounding-Box (Click-Raycast-Ziel).
	local boxW = math.max(torsoW + 0.8 + (if isBoss then 2.0 else 0), headD + 0.8)
	local boxH = totalH
	local boxD = torsoD + (if stage >= 3 then 0.8 else 0.4) + (if isBoss then 1.4 else 0)
	local root = makePart(model, "EnemyCore", Vector3.new(boxW, boxH, boxD), Vector3.new(cx, groundY + boxH / 2, cz), furGrey, Enum.Material.SmoothPlastic, false)
	root.CanQuery = true
	root.Transparency = 1
	model.PrimaryPart = root

	-- ---- Beine (Hose/Stiefel) ------------------------------------------
	local legSpacing = torsoW * 0.32
	local pantsColor = if stage >= 4 then armorMetal else coatDirty
	for _, side in ipairs({ -1, 1 }) do
		makePart(model, "RatLeg", Vector3.new(legW, legH * 0.9, legW), Vector3.new(cx + side * legSpacing, hipY - legH * 0.5, cz), pantsColor, Enum.Material.SmoothPlastic, false)
		-- dunklerer Stiefel
		makePart(model, "RatBoot", Vector3.new(legW * 1.3, legH * 0.22, legW * 1.45), Vector3.new(cx + side * legSpacing, groundY + legH * 0.11, cz + legW * 0.1), armorDark, Enum.Material.Metal, false)
		-- Knie-Akzent (mehr Stage = mehr Sichtbarkeit)
		if stage >= 3 then
			local knee = makePart(model, "RatKneePlate", Vector3.new(legW * 1.05, legH * 0.18, legW * 0.7), Vector3.new(cx + side * legSpacing, hipY - legH * 0.45, cz - legW * 0.3), armorDark, Enum.Material.Metal, false)
		end
		-- Mutationsflecken auf den Hosen (Stage 2+)
		if stage >= 2 then
			for k = 1, 2 do
				local seed = side * 10 + k * 1.7
				local px = cx + side * legSpacing + math.sin(seed) * legW * 0.3
				local py = hipY - legH * (0.3 + (k - 1) * 0.4)
				local pz = cz - legW * 0.5 + math.cos(seed) * legW * 0.1
				makePart(model, "RatMutPatch", Vector3.new(legW * 0.5, legH * 0.22, 0.1), Vector3.new(px, py, pz), mutationDeep, Enum.Material.SmoothPlastic, false).Transparency = 0.1
			end
		end
	end

	-- ---- Torso: Laborkittel oder Armor ---------------------------------
	local torsoColor = if stage >= 4 then armorMetal else coatWhite
	local torso = makePart(model, "RatTorso", Vector3.new(torsoW, torsoH, torsoD), Vector3.new(cx, torsoCenterY, cz), torsoColor, Enum.Material.SmoothPlastic, false)
	torso.Transparency = 0
	-- Kittel-V (offene Lapel-Form, vorne) -> klar erkennbarer Laborkittel.
	if stage < 4 then
		-- Linkes und rechtes Lapel als angewinkelte Dreiecksstreifen.
		for _, side in ipairs({ -1, 1 }) do
			local lapel = makePart(model, "RatCoatLapel", Vector3.new(torsoW * 0.32, torsoH * 0.85, 0.12), Vector3.new(cx + side * torsoW * 0.15, torsoCenterY + torsoH * 0.05, cz - torsoD / 2 - 0.06), coatShadow, Enum.Material.SmoothPlastic, false)
			lapel.Orientation = Vector3.new(0, 0, side * 12)
		end
		-- Dunkles V-Inlay (Hemd/Brust dazwischen sichtbar)
		local innerShirt = makePart(model, "RatCoatVInner", Vector3.new(torsoW * 0.32, torsoH * 0.55, 0.08), Vector3.new(cx, torsoCenterY - torsoH * 0.08, cz - torsoD / 2 - 0.08), furDeep, Enum.Material.SmoothPlastic, false)
		-- Kragen
		makePart(model, "RatCoatCollar", Vector3.new(torsoW * 0.7, 0.28, torsoD * 1.0), Vector3.new(cx, torsoCenterY + torsoH * 0.42, cz), coatShadow, Enum.Material.SmoothPlastic, false)
		-- Mittlere Knopf-Falte / Saum
		makePart(model, "RatCoatHem", Vector3.new(torsoW * 0.95, 0.18, torsoD * 1.02), Vector3.new(cx, torsoCenterY - torsoH * 0.42, cz), coatShadow, Enum.Material.SmoothPlastic, false)
		-- Schmutz/Mutations-Splatter
		for i = 1, 3 + stage do
			local seed = i * 1.9
			local px = math.sin(seed) * 0.42 * torsoW
			local py = math.cos(seed * 1.1) * 0.4 * torsoH
			local splatter = makePart(model, "RatMutSplatter", Vector3.new(torsoW * (0.18 + (i % 3) * 0.04), torsoH * 0.18, 0.06), Vector3.new(cx + px, torsoCenterY + py, cz - torsoD / 2 - 0.06), if i % 2 == 0 then mutationPink else mutationDeep, Enum.Material.SmoothPlastic, false)
			splatter.Transparency = 0.05
		end
	end
	-- Biohazard-Sticker auf der Brust (hell-leuchtend) + dunkler Rand.
	local hazardSize = torsoW * 0.38
	local hazardX = cx + (if stage <= 2 then torsoW * 0.22 else 0)
	-- Dunkler Backing
	makePart(model, "RatHazardBacking", Vector3.new(hazardSize * 1.15, hazardSize * 1.15, 0.06), Vector3.new(hazardX, torsoCenterY + torsoH * 0.08, cz - torsoD / 2 - 0.10), Color3.fromRGB(28, 24, 18), Enum.Material.SmoothPlastic, false)
	local hazard = makePart(model, "RatHazardSticker", Vector3.new(hazardSize, hazardSize, 0.06), Vector3.new(hazardX, torsoCenterY + torsoH * 0.08, cz - torsoD / 2 - 0.14), Color3.fromRGB(252, 218, 78), Enum.Material.Neon, false)
	hazard.Transparency = 0.05
	-- Stage 4 Armor: groesserer Brustpanzer + Akzente
	if stage >= 4 then
		local plate = makePart(model, "RatChestPlate", Vector3.new(torsoW * 0.9, torsoH * 0.7, 0.18), Vector3.new(cx, torsoCenterY, cz - torsoD / 2 - 0.12), armorDark, Enum.Material.Metal, false)
		hazard.Position = Vector3.new(cx, torsoCenterY + torsoH * 0.05, cz - torsoD / 2 - 0.22)
	end

	-- ---- Glow-Kern auf Brust (Stage 4+ und Boss, beim Boss gruen) ------
	if stage >= 4 then
		local coreColor = if isBoss then bossTubeGreen else mutationGlow
		local coreSize = if isBoss then headD * 0.7 else headD * 0.42
		local core = makePart(model, "RatChestCore", Vector3.new(coreSize, coreSize, coreSize * 0.5), Vector3.new(cx, torsoCenterY + torsoH * 0.05, cz - torsoD / 2 - 0.18), coreColor, Enum.Material.Neon, false)
		core.Shape = Enum.PartType.Ball
		core.Transparency = 0.1
		local outerRing = makePart(model, "RatChestCoreOuter", Vector3.new(coreSize * 1.4, coreSize * 1.4, coreSize * 0.3), Vector3.new(cx, torsoCenterY + torsoH * 0.05, cz - torsoD / 2 - 0.07), tint(coreColor, Color3.fromRGB(245, 250, 230), 0.3), Enum.Material.Glass, false)
		outerRing.Shape = Enum.PartType.Ball
		outerRing.Transparency = 0.5
		local pl = Instance.new("PointLight")
		pl.Brightness = if isBoss then 3 else 1.5
		pl.Range = if isBoss then 24 else 12
		pl.Color = coreColor
		pl.Parent = core
	end

	-- ---- Rucksack mit Reagenz-Tanks (Stage 2+) ------------------------
	if stage >= 2 then
		local backW = torsoW * 0.85
		local backH = torsoH * 0.75
		local backD = 0.55 + (stage - 2) * 0.15 + (if isBoss then 0.5 else 0)
		local backX = cx
		local backY = torsoCenterY + torsoH * 0.05
		local backZ = cz + torsoD / 2 + backD * 0.5
		makePart(model, "RatBackpack", Vector3.new(backW, backH, backD), Vector3.new(backX, backY, backZ), armorDark, Enum.Material.Metal, false)
		-- Tanks: pink fuer Stages 2-4, gruen fuer Boss. Anzahl waechst.
		local tankColor = if isBoss then bossTubeGreen else mutationGlow
		local tankCount = if isBoss then 5 elseif stage == 2 then 1 elseif stage == 3 then 2 else 2
		local tankRadius = (if isBoss then 0.45 else 0.4) + (stage - 2) * 0.05
		local tankHeight = if isBoss then totalH * 0.55 else totalH * 0.35 + (stage - 2) * 0.15
		for i = 1, tankCount do
			local tx
			if tankCount == 1 then
				tx = backX + 0.7
			else
				tx = backX + (i - (tankCount + 1) / 2) * (backW / (tankCount + 0.5))
			end
			local ty = backY + backH * 0.3 + (if isBoss then tankHeight * 0.3 else 0)
			local tz = backZ + backD * 0.4
			-- Tank-Aussenhuelle (Glas mit Fluessigkeit)
			local tank = makePart(model, "RatTank", Vector3.new(tankRadius * 2, tankHeight, tankRadius * 2), Vector3.new(tx, ty, tz), tint(tankColor, Color3.fromRGB(248, 252, 240), 0.3), Enum.Material.Glass, false)
			tank.Shape = Enum.PartType.Cylinder
			tank.Orientation = Vector3.new(0, 0, 90)
			tank.Transparency = 0.35
			-- Innen-Fluessigkeit (Neon, leuchtend)
			local fluid = makePart(model, "RatTankFluid", Vector3.new(tankRadius * 1.7, tankHeight * 0.9, tankRadius * 1.7), Vector3.new(tx, ty, tz), tankColor, Enum.Material.Neon, false)
			fluid.Shape = Enum.PartType.Cylinder
			fluid.Orientation = Vector3.new(0, 0, 90)
			fluid.Transparency = 0.15
			-- Tank-Kappe oben/unten
			makePart(model, "RatTankCapTop", Vector3.new(0.25, tankRadius * 2.2, tankRadius * 2.2), Vector3.new(tx, ty + tankHeight * 0.5, tz), armorDark, Enum.Material.Metal, false).Shape = Enum.PartType.Cylinder
			makePart(model, "RatTankCapBottom", Vector3.new(0.25, tankRadius * 2.2, tankRadius * 2.2), Vector3.new(tx, ty - tankHeight * 0.5, tz), armorDark, Enum.Material.Metal, false).Shape = Enum.PartType.Cylinder
			-- Schlauch nach unten/vorne (rudimentaer)
			makePart(model, "RatTankTube", Vector3.new(0.18, tankRadius * 1.8, 0.18), Vector3.new(tx - tankRadius * 0.6, ty - tankHeight * 0.65, tz), armorDark, Enum.Material.SmoothPlastic, false)
			local pl = Instance.new("PointLight")
			pl.Brightness = 1
			pl.Range = 10
			pl.Color = tankColor
			pl.Parent = fluid
		end
	end

	-- ---- Schulterpads (Stage 3+) --------------------------------------
	if stage >= 3 then
		for _, side in ipairs({ -1, 1 }) do
			local padW = torsoW * 0.42 + (stage - 3) * 0.18 + (if isBoss then 0.7 else 0)
			local padH = torsoH * 0.45 + (stage - 3) * 0.1 + (if isBoss then 0.5 else 0)
			local padX = cx + side * (torsoW * 0.5 + padW * 0.3)
			local padY = torsoCenterY + torsoH * 0.42
			local pad = makePart(model, "RatShoulderPad", Vector3.new(padW, padH, torsoD * 1.2), Vector3.new(padX, padY, cz), armorDark, Enum.Material.Metal, false)
			pad.Orientation = Vector3.new(0, 0, side * -15)
			-- Stachel auf Schulter (Stage 4+)
			if stage >= 4 then
				local spikeCount = 2 + (if isBoss then 2 else 0)
				for k = 1, spikeCount do
					local sx = padX + (k - (spikeCount + 1) / 2) * 0.45
					local spikeLen = 0.7 + (stage - 4) * 0.25 + (if isBoss then 1.0 else 0)
					makePart(model, "RatShoulderSpike", Vector3.new(0.3, spikeLen, 0.3), Vector3.new(sx, padY + padH * 0.5 + spikeLen * 0.4, cz), tailColor, Enum.Material.Metal, false)
				end
			end
		end
	end

	-- ---- Arme + Klauen -------------------------------------------------
	local armLen = torsoH * 0.95
	local armW = torsoW * 0.22 + (stage - 1) * 0.05
	for _, side in ipairs({ -1, 1 }) do
		local armX = cx + side * (torsoW * 0.55 + armW * 0.3)
		local armY = torsoCenterY - torsoH * 0.05
		local sleeveColor = if stage >= 4 then armorMetal else coatWhite
		makePart(model, "RatArm", Vector3.new(armW, armLen, armW), Vector3.new(armX, armY, cz), sleeveColor, Enum.Material.SmoothPlastic, false)
		-- Mutationsfleck auf dem Aermel (Stage 2+)
		if stage >= 2 and stage < 4 then
			makePart(model, "RatArmMut", Vector3.new(armW * 1.05, armLen * 0.35, 0.08), Vector3.new(armX, armY - armLen * 0.2, cz - armW * 0.5 - 0.04), mutationDeep, Enum.Material.SmoothPlastic, false).Transparency = 0.1
		end
		local handSize = armW * 1.4
		local handY = armY - armLen * 0.5 - handSize * 0.3
		-- Klauen ab Stage 2 (Ratten-Krallen)
		if stage >= 2 then
			local hand = makePart(model, "RatClawHand", Vector3.new(handSize, handSize * 0.8, handSize), Vector3.new(armX, handY, cz), furDeep, Enum.Material.Metal, false)
			hand.Shape = Enum.PartType.Ball
			local clawCount = 3
			for k = -1, 1 do
				local cx_claw = armX + k * handSize * 0.32
				local clawLen = handSize * (0.95 + (stage - 2) * 0.25)
				local claw = makePart(model, "RatClaw", Vector3.new(0.22, clawLen, 0.22), Vector3.new(cx_claw, handY - clawLen * 0.5, cz + handSize * 0.1), tailColor, Enum.Material.Metal, false)
				makePart(model, "RatClawTip", Vector3.new(0.25, 0.2, 0.25), Vector3.new(cx_claw, handY - clawLen - 0.05, cz + handSize * 0.1), Color3.fromRGB(220, 200, 175), Enum.Material.SmoothPlastic, false)
			end
		else
			local hand = makePart(model, "RatHand", Vector3.new(handSize, handSize, handSize), Vector3.new(armX, handY, cz), furGrey, Enum.Material.SmoothPlastic, false)
			hand.Shape = Enum.PartType.Ball
			-- Mini-Krallen (kleiner Hint)
			for k = -1, 1 do
				local cx_claw = armX + k * handSize * 0.32
				makePart(model, "RatTinyClaw", Vector3.new(0.18, 0.3, 0.18), Vector3.new(cx_claw, handY - handSize * 0.55, cz + handSize * 0.1), tailColor, Enum.Material.Metal, false)
			end
		end
	end

	-- ---- Kopf: Ratten-Schaedel + Schnauze + Ohren ---------------------
	local headBase = makePart(model, "RatHead", Vector3.new(headD * 0.95, headD * 1.0, headD * 1.05), Vector3.new(cx, headCenterY, cz), furGrey, Enum.Material.SmoothPlastic, false)
	headBase.Shape = Enum.PartType.Ball

	-- Schnauze: zwei zylindrische Teile, leicht versetzt nach vorne
	local snoutLen = headD * 0.55
	local snout = makePart(model, "RatSnout", Vector3.new(headD * 0.55, headD * 0.55, snoutLen), Vector3.new(cx, headCenterY - headD * 0.1, cz - headD * 0.5 - snoutLen * 0.4), furGrey, Enum.Material.SmoothPlastic, false)
	-- Nase: dunkler Ball vorne
	local nose = makePart(model, "RatNose", Vector3.new(headD * 0.22, headD * 0.18, headD * 0.18), Vector3.new(cx, headCenterY - headD * 0.08, cz - headD * 0.55 - snoutLen * 0.85), noseColor, Enum.Material.SmoothPlastic, false)
	nose.Shape = Enum.PartType.Ball

	-- Ohren: grosse, schuesselfoermige Halbkugeln oben am Kopf.
	local earSize = headD * 0.62
	for _, side in ipairs({ -1, 1 }) do
		local ear = makePart(model, "RatEar", Vector3.new(earSize * 0.9, earSize, 0.25), Vector3.new(cx + side * headD * 0.38, headCenterY + headD * 0.48, cz + headD * 0.02), furGrey, Enum.Material.SmoothPlastic, false)
		ear.Shape = Enum.PartType.Cylinder
		ear.Orientation = Vector3.new(90, side * 20, 0)
		-- Innere Ohrmuschel (rosa, vorne aufgesetzt)
		local earInner = makePart(model, "RatEarInner", Vector3.new(earSize * 0.65, earSize * 0.75, 0.18), Vector3.new(cx + side * headD * 0.38, headCenterY + headD * 0.46, cz - 0.05), mutationPink, Enum.Material.SmoothPlastic, false)
		earInner.Shape = Enum.PartType.Cylinder
		earInner.Orientation = Vector3.new(90, side * 20, 0)
	end

	-- Augen: kleine leuchtende Slit-Augen (rot/pink, beim Boss heller)
	local eyeColor = if isBoss then mutationGlow else Color3.fromRGB(245, 80, 95)
	local eyeY = headCenterY + headD * 0.05
	for _, side in ipairs({ -1, 1 }) do
		local eyeGlow = makePart(model, "RatEye", Vector3.new(headD * 0.18, headD * 0.10, 0.12), Vector3.new(cx + side * headD * 0.18, eyeY, cz - headD * 0.48), eyeColor, Enum.Material.Neon, false)
		eyeGlow.Transparency = 0.04
		eyeGlow.Orientation = Vector3.new(0, 0, side * -25)
		local pl = Instance.new("PointLight")
		pl.Brightness = 0.7
		pl.Range = 6
		pl.Color = eyeColor
		pl.Parent = eyeGlow
	end

	-- Whiskers / Schnurrhaare (3 pro Seite, duenne Boxen)
	local whiskerLen = headD * 0.85
	for _, side in ipairs({ -1, 1 }) do
		for k = 1, 3 do
			local angle = (k - 2) * math.rad(15)
			local wx = cx + side * (headD * 0.32 + math.cos(angle) * whiskerLen * 0.5)
			local wy = headCenterY - headD * 0.1 + math.sin(angle) * 0.15
			local wz = cz - headD * 0.55 - snoutLen * 0.5
			local whisker = makePart(model, "RatWhisker", Vector3.new(whiskerLen * 0.9, 0.04, 0.04), Vector3.new(wx, wy, wz), Color3.fromRGB(232, 220, 200), Enum.Material.SmoothPlastic, false)
			whisker.Orientation = Vector3.new(0, side * (15 + (k - 2) * 8), 0)
		end
	end

	-- Mutations-Spikes auf Kopf (Stage 2+, mehr je Stage)
	if stage >= 2 then
		local spikeCount = 4 + (stage - 2) * 3 + (if isBoss then 6 else 0)
		for i = 1, spikeCount do
			local a = (i / spikeCount) * math.pi * 1.6 - math.pi * 0.3
			local up = 0.5 + math.abs(math.sin(i * 1.3)) * 0.5
			local fwd = math.cos(a) * 0.7
			local dir = Vector3.new(fwd, up, math.sin(a) * 0.7).Unit
			local spikeLen = headD * 0.35 + (stage - 2) * 0.07
			local spikeCenter = Vector3.new(cx, headCenterY, cz) + dir * headD * 0.55
			local spike = makePart(model, "RatHeadSpike", Vector3.new(spikeLen * 0.32, spikeLen, spikeLen * 0.32), spikeCenter, tailColor, Enum.Material.Metal, false)
			local upv = if math.abs(dir.Y) > 0.95 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
			spike.CFrame = CFrame.lookAt(spikeCenter, spikeCenter + dir, upv) * CFrame.Angles(math.rad(90), 0, 0)
		end
	end

	-- ---- Schwanz mit Spike-Tip ----------------------------------------
	local tailSegs = 4 + (stage - 1)
	local tailStartY = torsoCenterY - torsoH * 0.2
	local tailLen = totalH * 0.7
	local segLen = tailLen / tailSegs
	for s = 0, tailSegs - 1 do
		local t = s / tailSegs
		local tailX = cx + math.sin(t * math.pi) * 0.4
		local tailY = tailStartY - t * tailLen * 0.55
		local tailZ = cz + torsoD / 2 + 0.3 + t * tailLen * 0.85
		local segR = (1 - t * 0.5) * (legW * 0.35) + (if isBoss then 0.1 else 0)
		local seg = makePart(model, "RatTailSeg", Vector3.new(segR * 2, segLen, segR * 2), Vector3.new(tailX, tailY, tailZ), tailColor, Enum.Material.SmoothPlastic, false)
		seg.Orientation = Vector3.new(t * 60, 0, 0)
	end
	-- Schwanzspitze: Spike
	local tipR = legW * 0.22 + (if isBoss then 0.1 else 0)
	local tipPos = Vector3.new(cx, tailStartY - tailLen * 0.55, cz + torsoD / 2 + 0.3 + tailLen * 0.85)
	local tailSpike = makePart(model, "RatTailSpike", Vector3.new(tipR * 1.8, segLen * 1.6, tipR * 1.8), tipPos, tailColor, Enum.Material.Metal, false)
	tailSpike.Orientation = Vector3.new(70, 0, 0)
	makePart(model, "RatTailSpikeTip", Vector3.new(tipR * 1.4, segLen * 0.5, tipR * 1.4), tipPos + Vector3.new(0, -segLen * 0.4, segLen * 0.4), tint(tailColor, Color3.fromRGB(240, 220, 200), 0.3), Enum.Material.SmoothPlastic, false)

	-- ---- BOSS Extras: hohe gruene Tubes hinter dem Kopf + Glow ---------
	if isBoss then
		-- Glow-Pad (BossPad-Vertrag bleibt)
		local ring = makePart(model, "BossPad", Vector3.new(0.5, totalH * 1.1, totalH * 1.1), Vector3.new(basePos.X, CHAMBER_TOP + 1.25, basePos.Z), bossTubeGreen, Enum.Material.Neon, false)
		ring.Shape = Enum.PartType.Cylinder
		ring.Orientation = Vector3.new(0, 0, 90)
		ring.Transparency = 0.35
		-- 3 grosse vertikale Tubes hinter dem Kopf, mit Boegen oben
		for i = -1, 1 do
			local tx = cx + i * 1.6
			local ty = headCenterY + totalH * 0.32
			local tz = cz + torsoD / 2 + 0.9
			local tubeH = totalH * 0.85
			local tubeR = 0.6
			local tube = makePart(model, "BossRatTube", Vector3.new(tubeR * 2, tubeH, tubeR * 2), Vector3.new(tx, ty, tz), tint(bossTubeGreen, Color3.fromRGB(248, 252, 240), 0.25), Enum.Material.Glass, false)
			tube.Shape = Enum.PartType.Cylinder
			tube.Orientation = Vector3.new(0, 0, 90)
			tube.Transparency = 0.32
			local fluid = makePart(model, "BossRatTubeFluid", Vector3.new(tubeR * 1.7, tubeH * 0.9, tubeR * 1.7), Vector3.new(tx, ty, tz), bossTubeGreen, Enum.Material.Neon, false)
			fluid.Shape = Enum.PartType.Cylinder
			fluid.Orientation = Vector3.new(0, 0, 90)
			fluid.Transparency = 0.1
			makePart(model, "BossRatTubeCapTop", Vector3.new(0.3, tubeR * 2.3, tubeR * 2.3), Vector3.new(tx, ty + tubeH * 0.5, tz), armorDark, Enum.Material.Metal, false).Shape = Enum.PartType.Cylinder
			makePart(model, "BossRatTubeCapBottom", Vector3.new(0.3, tubeR * 2.3, tubeR * 2.3), Vector3.new(tx, ty - tubeH * 0.5, tz), armorDark, Enum.Material.Metal, false).Shape = Enum.PartType.Cylinder
			-- Bogen oben
			makePart(model, "BossRatTubeBend", Vector3.new(0.4, 1.4, 0.4), Vector3.new(tx, ty + tubeH * 0.5 + 0.7, tz - 0.4), armorDark, Enum.Material.Metal, false)
			local pl = Instance.new("PointLight")
			pl.Brightness = 2
			pl.Range = 16
			pl.Color = bossTubeGreen
			pl.Parent = fluid
		end
	end

	-- ---- Dampf/Schleim-Partikel ---------------------------------------
	local steam = Instance.new("ParticleEmitter")
	steam.Name = "HantavirusSteam"
	steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
	steam.Color = ColorSequence.new(if isBoss then bossTubeGreen else mutationPink, tint(mutationDeep, Color3.fromRGB(40, 30, 30), 0.4))
	steam.LightEmission = 0.2
	steam.Rate = if isBoss then 10 else 1 + stage
	steam.Lifetime = NumberRange.new(1.0, 1.8)
	steam.Speed = NumberRange.new(0.5, 1.4)
	steam.Acceleration = Vector3.new(0, 2, 0)
	steam.SpreadAngle = Vector2.new(40, 40)
	steam.Size = NumberSequence.new(0.5, 0.1)
	steam.Parent = torso

	-- ---- Bewegung (gleicher Vertrag wie Norovirus) ---------------------
	local arche = ENEMY_ARCHETYPE[def.Shape] or ENEMY_ARCHETYPE.Blob
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
	model:SetAttribute("HomeX", cx)
	model:SetAttribute("HomeY", root.Position.Y)
	model:SetAttribute("HomeZ", cz)
	model:SetAttribute("MoveRangeX", mv.rx)
	model:SetAttribute("MoveRangeZ", mv.rz)
	model:SetAttribute("MoveSpeed", mv.sp)
	model:SetAttribute("BobAmp", mv.bob)
	model:SetAttribute("EnemyKind", "Hantavirus")

	-- ---- Health-Bar ----------------------------------------------------
	local barScale = if isBoss then 1.9 else 1
	local barY = groundY + totalH + (if isBoss then 2.4 else 1.6)
	local barBack = makePart(model, "HealthBarBack", Vector3.new(13 * barScale, 0.8, 0.4), Vector3.new(cx, barY, cz), Color3.fromRGB(16, 20, 26), Enum.Material.SmoothPlastic, false)
	local barFill = makePart(model, "HealthBarFill", Vector3.new(12.4 * barScale, 0.5, 0.55), Vector3.new(cx, barY + 0.02, cz - 0.06), Color3.fromRGB(95, 255, 125), Enum.Material.Neon, false)
	barFill.Transparency = 0.12
	barFill:SetAttribute("MaxWidth", 12.4 * barScale)
	barFill:SetAttribute("FullCenterX", barFill.Position.X)

	-- ---- AttackClick + Boss-Prompt ------------------------------------
	local clicker = Instance.new("ClickDetector")
	clicker.Name = "AttackClick"
	clicker.MaxActivationDistance = EnemyConfig.AttackDistance
	clicker.Parent = root

	if isBoss then
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

	-- ---- Info-Label ---------------------------------------------------
	local prefix = if isBoss then "★ BOSS ★\n" else ""
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
		if isBoss then 60 else 34,
		UDim2.fromOffset(if isBoss then 280 else 190, if isBoss then 104 else 76),
		Vector3.new(0, boxH / 2 + 3, 0)
	)

	return model
end

-- ---- Ebola-Set fuer Area 3 ----------------------------------------------
-- Schwarzer Koerper mit gluehenden roten Rissen, Tentakeln statt Kopf
-- (Stage 2+), rotes Biohazard auf der Brust. Boss bekommt grosse Tentakel-
-- Anordnung + leuchtende rote Scheibe ueber dem Kopf + Glow-Plattform.
local function buildEbolaTentacle(parent, startPos, lookForward, length, baseR, segCount, color, glowColor, archDeg)
	-- Baut eine gekruemmte Tentakel aus Ueberlapp-Kugeln. archDeg < 0 -> die
	-- Tentakel kruemmt sich nach oben/hinten. archDeg > 0 -> nach unten/vorne.
	local segLen = length / segCount
	local cf = CFrame.lookAt(startPos, startPos + lookForward)
	local stepAngle = math.rad(archDeg / segCount)
	local lastPos = startPos
	for i = 1, segCount do
		local t = (i - 0.5) / segCount
		local r = baseR * (1 - t * 0.55) + 0.06
		local segPos = (cf * CFrame.new(0, 0, -segLen / 2)).Position
		local ball = makePart(parent, "EbolaTentacleSeg", Vector3.new(r * 2, r * 2, r * 2), segPos, color, Enum.Material.SmoothPlastic, false)
		ball.Shape = Enum.PartType.Ball
		-- Roter Glow-Riss auf jedem zweiten Segment
		if i % 2 == 0 then
			local crack = makePart(parent, "EbolaTentacleCrack", Vector3.new(r * 1.2, r * 0.4, r * 1.2), segPos, glowColor, Enum.Material.Neon, false)
			crack.Shape = Enum.PartType.Ball
			crack.Transparency = 0.35
		end
		-- Spike auf einem Tentakelteil (Stage-spezifisch -> Caller fuegt das hinzu)
		lastPos = segPos
		cf = cf * CFrame.new(0, 0, -segLen) * CFrame.Angles(stepAngle, 0, 0)
	end
	-- Glow-"Auge" am Ende der Tentakel
	local tipPos = (cf * CFrame.new(0, 0, -segLen * 0.2)).Position
	local eye = makePart(parent, "EbolaTentacleEye", Vector3.new(baseR * 1.6, baseR * 1.6, baseR * 1.6), tipPos, glowColor, Enum.Material.Neon, false)
	eye.Shape = Enum.PartType.Ball
	eye.Transparency = 0.05
	local pl = Instance.new("PointLight")
	pl.Brightness = 1.5
	pl.Range = 8
	pl.Color = glowColor
	pl.Parent = eye
	return tipPos
end

local function buildEbolaEnemyModel(parent, def, basePos, primary, secondary)
	local model = Instance.new("Model")
	model.Name = def.Id
	model:SetAttribute("EnemyId", def.Id)
	model:SetAttribute("AreaName", def.AreaName)
	model:SetAttribute("IsBoss", def.IsBoss)
	model.Parent = parent

	local stage = def.EnemyIndex
	local isBoss = def.IsBoss
	local totalHeights = { 5.0, 6.2, 7.4, 8.6, 9.8 }
	local totalH = totalHeights[stage] or 5.0

	-- Proportionen (Boss deutlich breiter und gewichtiger).
	local legH = 1.6 + (stage - 1) * 0.45
	-- Ab Stage 2 hat der Charakter KEINEN richtigen Kopf -> Kopfteil
	-- schrumpft, dafuer wird die Haupt-Tentakel laenger.
	local headD = if stage == 1 then 1.8 else 1.1
	if isBoss then
		headD = 2.2
	end
	local torsoH = totalH - legH - (if stage == 1 then headD * 0.4 else 0.2)
	if torsoH < 0.8 then
		torsoH = 0.8
	end
	local torsoW = 1.7 + (stage - 1) * 0.38 + (if isBoss then 1.6 else 0)
	local torsoD = torsoW * 0.6 + (if isBoss then 0.6 else 0)
	local legW = 0.7 + (stage - 1) * 0.12 + (if isBoss then 0.35 else 0)

	-- Ebola-Farbpalette: fast schwarz + rot leuchtende Risse.
	local bodyBlack = Color3.fromRGB(20, 20, 22)
	local bodyDark = Color3.fromRGB(40, 38, 40)
	local crackRed = Color3.fromRGB(225, 30, 40)
	local crackGlow = Color3.fromRGB(255, 70, 80)
	local biohazardOrange = Color3.fromRGB(255, 110, 70)
	local armorMetal = Color3.fromRGB(58, 52, 55)
	local spikeColor = Color3.fromRGB(15, 14, 16)
	local clawColor = Color3.fromRGB(180, 30, 40)

	local groundY = CHAMBER_TOP
	local hipY = groundY + legH
	local torsoCenterY = hipY + torsoH / 2
	local neckY = hipY + torsoH
	local headCenterY = neckY + headD / 2 - headD * 0.1
	local cx, cz = basePos.X, basePos.Z

	-- EnemyCore = unsichtbare Bounding-Box.
	local boxW = math.max(torsoW + 0.8 + (if isBoss then 2.4 else 0), headD + 1.0)
	local boxH = totalH + (if isBoss then 2.5 else 1.2) -- Tentakeln bzw. Scheibe oben
	local boxD = torsoD + 0.8 + (if isBoss then 1.4 else 0)
	local root = makePart(model, "EnemyCore", Vector3.new(boxW, boxH, boxD), Vector3.new(cx, groundY + boxH / 2, cz), bodyBlack, Enum.Material.SmoothPlastic, false)
	root.CanQuery = true
	root.Transparency = 1
	model.PrimaryPart = root

	-- Helper: schwarze Box mit rotem Glow-Riss-Akzent.
	local function blackBox(name, size, pos)
		local p = makePart(model, name, size, pos, bodyBlack, Enum.Material.SmoothPlastic, false)
		return p
	end
	local function redCrack(parent_inst, parentSize, parentPos, axis, lengthFrac, offset)
		-- Setzt einen schmalen roten Glow-Streifen "auf" eine Box (subtle Riss-Look).
		local crackSize
		if axis == "Y" then
			crackSize = Vector3.new(parentSize.X * 0.12, parentSize.Y * lengthFrac, 0.12)
		elseif axis == "X" then
			crackSize = Vector3.new(parentSize.X * lengthFrac, parentSize.Y * 0.12, 0.12)
		else
			crackSize = Vector3.new(0.12, parentSize.Y * 0.12, parentSize.Z * lengthFrac)
		end
		local crack = makePart(model, "EbolaCrack", crackSize, parentPos + offset, crackGlow, Enum.Material.Neon, false)
		crack.Transparency = 0.25
		return crack
	end

	-- ---- Beine ---------------------------------------------------------
	local legSpacing = torsoW * 0.32
	for _, side in ipairs({ -1, 1 }) do
		local leg = blackBox("EbolaLeg", Vector3.new(legW, legH * 0.9, legW), Vector3.new(cx + side * legSpacing, hipY - legH * 0.5, cz))
		-- Rote Riss-Streifen vorne
		redCrack(leg, leg.Size, leg.Position, "Y", 0.7, Vector3.new(side * legW * 0.3, 0, -legW * 0.5 - 0.02))
		redCrack(leg, leg.Size, leg.Position, "Y", 0.5, Vector3.new(-side * legW * 0.2, legH * 0.1, -legW * 0.5 - 0.02))
		-- Schwerer Stiefel
		blackBox("EbolaBoot", Vector3.new(legW * 1.35, legH * 0.22, legW * 1.45), Vector3.new(cx + side * legSpacing, groundY + legH * 0.11, cz + legW * 0.1))
		-- Kniepanzer ab Stage 3
		if stage >= 3 then
			blackBox("EbolaKneePlate", Vector3.new(legW * 1.05, legH * 0.22, legW * 0.7), Vector3.new(cx + side * legSpacing, hipY - legH * 0.45, cz - legW * 0.35))
		end
	end

	-- ---- Torso (schwerer Brustpanzer) ---------------------------------
	local torso = blackBox("EbolaTorso", Vector3.new(torsoW, torsoH, torsoD), Vector3.new(cx, torsoCenterY, cz))
	-- Vertikales Riss-Muster auf Brust
	redCrack(torso, torso.Size, torso.Position, "Y", 0.7, Vector3.new(-torsoW * 0.28, 0, -torsoD * 0.55))
	redCrack(torso, torso.Size, torso.Position, "Y", 0.5, Vector3.new(torsoW * 0.32, torsoH * 0.1, -torsoD * 0.55))
	redCrack(torso, torso.Size, torso.Position, "X", 0.6, Vector3.new(0, -torsoH * 0.28, -torsoD * 0.55))
	-- Schulterpanzer (alle Stages, mehr Stage = groesser)
	for _, side in ipairs({ -1, 1 }) do
		local padW = torsoW * 0.32 + (stage - 1) * 0.1 + (if isBoss then 0.6 else 0)
		local padH = torsoH * 0.35 + (stage - 1) * 0.08
		local padX = cx + side * (torsoW * 0.5 + padW * 0.3)
		local padY = torsoCenterY + torsoH * 0.42
		local pad = blackBox("EbolaShoulderPad", Vector3.new(padW, padH, torsoD * 1.15), Vector3.new(padX, padY, cz))
		pad.Orientation = Vector3.new(0, 0, side * -12)
		-- Glow-Punkt mittig auf Schulter (Reference: kleines rotes "Auge" auf Schulter)
		if stage >= 2 then
			local glowDot = makePart(model, "EbolaShoulderGlow", Vector3.new(padW * 0.35, padH * 0.5, padH * 0.5), Vector3.new(padX, padY, cz - torsoD * 0.55), crackGlow, Enum.Material.Neon, false)
			glowDot.Shape = Enum.PartType.Ball
			glowDot.Transparency = 0.1
		end
		-- Schulter-Spikes ab Stage 3 (rot leuchtende Spitzen)
		if stage >= 3 then
			local spikeCount = stage - 1 + (if isBoss then 2 else 0)
			for k = 1, spikeCount do
				local sx = padX + (k - (spikeCount + 1) / 2) * 0.45
				local spikeLen = 0.7 + (stage - 3) * 0.25 + (if isBoss then 0.8 else 0)
				makePart(model, "EbolaShoulderSpike", Vector3.new(0.34, spikeLen, 0.34), Vector3.new(sx, padY + padH * 0.5 + spikeLen * 0.4, cz), spikeColor, Enum.Material.Metal, false)
				makePart(model, "EbolaShoulderSpikeTip", Vector3.new(0.4, 0.25, 0.4), Vector3.new(sx, padY + padH * 0.5 + spikeLen * 0.85, cz), crackGlow, Enum.Material.Neon, false)
			end
		end
	end

	-- ---- Biohazard auf der Brust (gross, hell leuchtend rot-orange) ----
	local hazardSize = torsoW * 0.42 + (if isBoss then 0.6 else 0)
	local hazardBacking = makePart(model, "EbolaHazardBacking", Vector3.new(hazardSize * 1.18, hazardSize * 1.18, 0.05), Vector3.new(cx, torsoCenterY, cz - torsoD / 2 - 0.08), bodyBlack, Enum.Material.SmoothPlastic, false)
	local hazard = makePart(model, "EbolaHazard", Vector3.new(hazardSize, hazardSize, 0.06), Vector3.new(cx, torsoCenterY, cz - torsoD / 2 - 0.12), biohazardOrange, Enum.Material.Neon, false)
	hazard.Transparency = 0.05
	local hazardLight = Instance.new("PointLight")
	hazardLight.Brightness = if isBoss then 2.5 else 1.2
	hazardLight.Range = if isBoss then 18 else 10
	hazardLight.Color = biohazardOrange
	hazardLight.Parent = hazard

	-- ---- Arme + Klauen -------------------------------------------------
	local armLen = torsoH * 0.95
	local armW = torsoW * 0.22 + (stage - 1) * 0.05
	for _, side in ipairs({ -1, 1 }) do
		local armX = cx + side * (torsoW * 0.55 + armW * 0.3)
		local armY = torsoCenterY - torsoH * 0.05
		local arm = blackBox("EbolaArm", Vector3.new(armW, armLen, armW), Vector3.new(armX, armY, cz))
		-- Rote Risse auf Arm
		redCrack(arm, arm.Size, arm.Position, "Y", 0.6, Vector3.new(0, 0, -armW * 0.55))
		-- Hand: schwarze Faust + 3 rote Klauen ab Stage 2
		local handSize = armW * 1.4
		local handY = armY - armLen * 0.5 - handSize * 0.3
		local hand = blackBox("EbolaHand", Vector3.new(handSize, handSize * 0.85, handSize), Vector3.new(armX, handY, cz))
		hand.Shape = Enum.PartType.Ball
		if stage >= 2 then
			local clawCount = 3
			for k = -1, 1 do
				local cxx = armX + k * handSize * 0.32
				local clawLen = handSize * (0.85 + (stage - 2) * 0.25)
				makePart(model, "EbolaClaw", Vector3.new(0.24, clawLen, 0.24), Vector3.new(cxx, handY - clawLen * 0.5, cz + handSize * 0.1), clawColor, Enum.Material.Metal, false)
				makePart(model, "EbolaClawTip", Vector3.new(0.28, 0.22, 0.28), Vector3.new(cxx, handY - clawLen - 0.05, cz + handSize * 0.1), crackGlow, Enum.Material.Neon, false)
			end
		end
	end

	-- ---- Kopf-Bereich --------------------------------------------------
	-- Stage 1: hat noch einen blocky Kopf (mit roten Augen) + 1 Tentakel hinten
	-- Stage 2+: Kopf wird durch Tentakel ersetzt (kleiner Stumpf am Hals)
	if stage == 1 then
		local head = blackBox("EbolaHead", Vector3.new(headD * 0.9, headD * 0.95, headD * 0.95), Vector3.new(cx, headCenterY, cz))
		-- Rote Risse auf Stirn/Wangen
		redCrack(head, head.Size, head.Position, "Y", 0.6, Vector3.new(-headD * 0.2, 0, -headD * 0.48))
		redCrack(head, head.Size, head.Position, "Y", 0.5, Vector3.new(headD * 0.2, -headD * 0.1, -headD * 0.48))
		-- Augen
		for _, side in ipairs({ -1, 1 }) do
			local eye = makePart(model, "EbolaEye", Vector3.new(headD * 0.16, headD * 0.16, 0.12), Vector3.new(cx + side * headD * 0.22, headCenterY + headD * 0.05, cz - headD * 0.48), crackGlow, Enum.Material.Neon, false)
			eye.Shape = Enum.PartType.Ball
		end
	else
		-- Kragen / Hals-Stumpf
		blackBox("EbolaNeckStump", Vector3.new(headD * 1.1, headD * 0.7, headD * 1.1), Vector3.new(cx, neckY + headD * 0.15, cz))
	end

	-- ---- Tentakel (Hauptarchitektur ab Stage 1) -----------------------
	-- Jede Tentakel: Position + Anfangsrichtung + Laenge + Bogenwinkel.
	local tentacleConfigs = {}
	local mainTentLen = totalH * (0.55 + (stage - 1) * 0.07) + (if isBoss then totalH * 0.2 else 0)
	if stage == 1 then
		-- 1 Tentakel: aus dem Oberruecken, ueber den Kopf gebogen.
		table.insert(tentacleConfigs, { startPos = Vector3.new(cx, neckY + 0.2, cz + 0.2), dir = Vector3.new(0, 1, -0.1).Unit, length = mainTentLen, baseR = 0.32, segs = 8, arch = 120 })
	elseif stage == 2 then
		-- 1 grosse Tentakel statt Kopf + 1 kleinere aus dem Ruecken.
		table.insert(tentacleConfigs, { startPos = Vector3.new(cx, neckY + 0.2, cz - 0.1), dir = Vector3.new(0, 1, -0.2).Unit, length = mainTentLen, baseR = 0.38, segs = 9, arch = 140 })
		table.insert(tentacleConfigs, { startPos = Vector3.new(cx - torsoW * 0.3, neckY + 0.1, cz + torsoD * 0.4), dir = Vector3.new(-0.3, 1, 0.2).Unit, length = mainTentLen * 0.5, baseR = 0.22, segs = 5, arch = 70 })
	elseif stage == 3 then
		-- 1 Haupt-Kopftentakel + 2 Schulter-Tentakel.
		table.insert(tentacleConfigs, { startPos = Vector3.new(cx, neckY + 0.2, cz - 0.1), dir = Vector3.new(0, 1, -0.15).Unit, length = mainTentLen, baseR = 0.4, segs = 10, arch = 110 })
		for _, side in ipairs({ -1, 1 }) do
			table.insert(tentacleConfigs, { startPos = Vector3.new(cx + side * torsoW * 0.45, torsoCenterY + torsoH * 0.4, cz + torsoD * 0.3), dir = Vector3.new(side * 0.4, 1, 0.1).Unit, length = mainTentLen * 0.7, baseR = 0.26, segs = 7, arch = 80 })
		end
	elseif stage == 4 then
		-- 1 Haupt + 4 Seiten-Tentakel im Faecher.
		table.insert(tentacleConfigs, { startPos = Vector3.new(cx, neckY + 0.2, cz - 0.05), dir = Vector3.new(0, 1, -0.1).Unit, length = mainTentLen * 1.05, baseR = 0.42, segs = 10, arch = 130 })
		for _, side in ipairs({ -1, 1 }) do
			table.insert(tentacleConfigs, { startPos = Vector3.new(cx + side * torsoW * 0.45, torsoCenterY + torsoH * 0.45, cz + torsoD * 0.3), dir = Vector3.new(side * 0.5, 0.9, 0.2).Unit, length = mainTentLen * 0.75, baseR = 0.28, segs = 7, arch = 90 })
			table.insert(tentacleConfigs, { startPos = Vector3.new(cx + side * torsoW * 0.35, torsoCenterY + torsoH * 0.15, cz + torsoD * 0.4), dir = Vector3.new(side * 0.7, 0.5, 0.4).Unit, length = mainTentLen * 0.55, baseR = 0.22, segs = 5, arch = 60 })
		end
	else -- Boss
		-- Massive Tentakel-Anordnung (6 Stueck) hinter und ueber dem Boss.
		for k = 1, 6 do
			local angle = (k - 3.5) / 5 * math.rad(110)
			local dir = Vector3.new(math.sin(angle), 0.8, math.cos(angle) * 0.3 + 0.4).Unit
			local startX = cx + math.sin(angle) * torsoW * 0.45
			local startY = neckY + 0.2 + math.cos(angle * 0.5) * 0.3
			local startZ = cz + torsoD * 0.25
			table.insert(tentacleConfigs, { startPos = Vector3.new(startX, startY, startZ), dir = dir, length = mainTentLen * (0.85 + math.cos(angle) * 0.15), baseR = 0.42, segs = 11, arch = 100 + math.abs(angle) * 25 })
		end
	end
	for _, tc in ipairs(tentacleConfigs) do
		buildEbolaTentacle(model, tc.startPos, tc.dir, tc.length, tc.baseR, tc.segs, bodyDark, crackGlow, tc.arch)
	end

	-- ---- BOSS Extras: leuchtende rote Halo-Scheibe + Glow-Plattform ----
	if isBoss then
		local haloY = headCenterY + 4.5
		-- Aussenring
		local haloOuter = makePart(model, "BossEbolaHaloOuter", Vector3.new(0.5, 5.4, 5.4), Vector3.new(cx, haloY, cz + 0.2), spikeColor, Enum.Material.Metal, false)
		haloOuter.Shape = Enum.PartType.Cylinder
		haloOuter.Orientation = Vector3.new(0, 0, 90)
		-- Innenscheibe (Neon)
		local haloDisc = makePart(model, "BossEbolaHaloDisc", Vector3.new(0.6, 4.4, 4.4), Vector3.new(cx, haloY, cz + 0.2), crackGlow, Enum.Material.Neon, false)
		haloDisc.Shape = Enum.PartType.Cylinder
		haloDisc.Orientation = Vector3.new(0, 0, 90)
		haloDisc.Transparency = 0.1
		-- Zacken um den Halo (12 Stueck)
		for k = 0, 11 do
			local a = (k / 12) * math.pi * 2
			local zx = cx + math.cos(a) * 2.8
			local zy = haloY + math.sin(a) * 2.8
			local zack = makePart(model, "BossEbolaHaloSpike", Vector3.new(0.45, 0.9, 0.45), Vector3.new(zx, zy, cz + 0.2), bodyBlack, Enum.Material.Metal, false)
			zack.Orientation = Vector3.new(0, 0, math.deg(a) + 90)
		end
		local haloLight = Instance.new("PointLight")
		haloLight.Brightness = 3
		haloLight.Range = 30
		haloLight.Color = crackGlow
		haloLight.Parent = haloDisc
		-- Glow-Plattform unter dem Boss (BossPad-Vertrag)
		local ring = makePart(model, "BossPad", Vector3.new(0.5, totalH * 1.15, totalH * 1.15), Vector3.new(basePos.X, CHAMBER_TOP + 1.25, basePos.Z), crackGlow, Enum.Material.Neon, false)
		ring.Shape = Enum.PartType.Cylinder
		ring.Orientation = Vector3.new(0, 0, 90)
		ring.Transparency = 0.3
		-- Aeusserer Ring-Glow auf dem Boden
		local floor1 = makePart(model, "BossEbolaFloorGlow", Vector3.new(0.25, totalH * 1.6, totalH * 1.6), Vector3.new(basePos.X, CHAMBER_TOP + 0.18, basePos.Z), crackRed, Enum.Material.Neon, false)
		floor1.Shape = Enum.PartType.Cylinder
		floor1.Orientation = Vector3.new(0, 0, 90)
		floor1.Transparency = 0.5
	end

	-- ---- Roter Rauch / Aura Partikel ----------------------------------
	local steam = Instance.new("ParticleEmitter")
	steam.Name = "EbolaAura"
	steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
	steam.Color = ColorSequence.new(crackGlow, tint(crackRed, bodyBlack, 0.6))
	steam.LightEmission = 0.25
	steam.Rate = if isBoss then 14 else 2 + stage
	steam.Lifetime = NumberRange.new(1.0, 1.8)
	steam.Speed = NumberRange.new(0.6, 1.4)
	steam.Acceleration = Vector3.new(0, 1.5, 0)
	steam.SpreadAngle = Vector2.new(40, 40)
	steam.Size = NumberSequence.new(0.5, 0.1)
	steam.Parent = torso

	-- ---- Bewegung -----------------------------------------------------
	local arche = ENEMY_ARCHETYPE[def.Shape] or ENEMY_ARCHETYPE.Blob
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
	model:SetAttribute("HomeX", cx)
	model:SetAttribute("HomeY", root.Position.Y)
	model:SetAttribute("HomeZ", cz)
	model:SetAttribute("MoveRangeX", mv.rx)
	model:SetAttribute("MoveRangeZ", mv.rz)
	model:SetAttribute("MoveSpeed", mv.sp)
	model:SetAttribute("BobAmp", mv.bob)
	model:SetAttribute("EnemyKind", "Ebola")

	-- ---- Health-Bar ---------------------------------------------------
	local barScale = if isBoss then 1.9 else 1
	local barY = groundY + totalH + (if isBoss then 3.4 else 1.8)
	local barBack = makePart(model, "HealthBarBack", Vector3.new(13 * barScale, 0.8, 0.4), Vector3.new(cx, barY, cz), Color3.fromRGB(16, 20, 26), Enum.Material.SmoothPlastic, false)
	local barFill = makePart(model, "HealthBarFill", Vector3.new(12.4 * barScale, 0.5, 0.55), Vector3.new(cx, barY + 0.02, cz - 0.06), Color3.fromRGB(95, 255, 125), Enum.Material.Neon, false)
	barFill.Transparency = 0.12
	barFill:SetAttribute("MaxWidth", 12.4 * barScale)
	barFill:SetAttribute("FullCenterX", barFill.Position.X)

	-- ---- AttackClick + Boss-Prompt ------------------------------------
	local clicker = Instance.new("ClickDetector")
	clicker.Name = "AttackClick"
	clicker.MaxActivationDistance = EnemyConfig.AttackDistance
	clicker.Parent = root

	if isBoss then
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

	-- ---- Info-Label ---------------------------------------------------
	local prefix = if isBoss then "★ BOSS ★\n" else ""
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
		if isBoss then 60 else 34,
		UDim2.fromOffset(if isBoss then 280 else 190, if isBoss then 104 else 76),
		Vector3.new(0, boxH / 2 + 3, 0)
	)

	return model
end

-- ---- Influenza-Set fuer Area 4 -------------------------------------------
-- Humanoide Wesen mit Virus-Spikeprotein-Kopf (rundlich-knubblige Spikes).
-- Progressive Mutation: Stage 1 simpel gruen, ab Stage 2 lila Federbuesche,
-- Stage 3 Gasmaske + Biohazard, Stage 4 Eiskristalle, Boss massiver Fluegel-/
-- Federmantel + leuchtende Hand-Orbs + grosse Krone.
local function buildInfluenzaEnemyModel(parent, def, basePos, primary, secondary)
	local model = Instance.new("Model")
	model.Name = def.Id
	model:SetAttribute("EnemyId", def.Id)
	model:SetAttribute("AreaName", def.AreaName)
	model:SetAttribute("IsBoss", def.IsBoss)
	model.Parent = parent

	local stage = def.EnemyIndex
	local isBoss = def.IsBoss
	local totalHeights = { 5.0, 6.2, 7.4, 8.6, 9.8 }
	local totalH = totalHeights[stage] or 5.0

	local legH = 1.6 + (stage - 1) * 0.45
	local headD = 2.0 + (stage - 1) * 0.30 + (if isBoss then 0.6 else 0)
	local torsoH = totalH - legH - headD * 0.40
	if torsoH < 0.8 then
		torsoH = 0.8
	end
	local torsoW = 1.7 + (stage - 1) * 0.38 + (if isBoss then 1.5 else 0)
	local torsoD = torsoW * 0.6 + (if isBoss then 0.55 else 0)
	local legW = 0.7 + (stage - 1) * 0.12 + (if isBoss then 0.35 else 0)

	-- Influenza-Palette: progressiv gruen -> teal -> dark blue -> purple/cyan.
	local bodyStage = {
		Color3.fromRGB(126, 168, 132), -- 1: sage green
		Color3.fromRGB(82, 124, 124), -- 2: dark teal
		Color3.fromRGB(58, 92, 108), -- 3: deep teal-blue
		Color3.fromRGB(64, 68, 108), -- 4: dark purple-blue
		Color3.fromRGB(48, 52, 88), -- boss
	}
	local headStage = {
		Color3.fromRGB(120, 162, 128),
		Color3.fromRGB(78, 118, 120),
		Color3.fromRGB(60, 90, 108),
		Color3.fromRGB(70, 76, 118),
		Color3.fromRGB(58, 62, 102),
	}
	local bodyColor = bodyStage[stage]
	local headColor = headStage[stage]
	local bodyDark = tint(bodyColor, Color3.fromRGB(10, 12, 18), 0.45)
	local featherPurple = Color3.fromRGB(112, 70, 175)
	local featherDeep = Color3.fromRGB(75, 45, 130)
	local cyanGlow = Color3.fromRGB(95, 225, 235)
	local crystalCyan = Color3.fromRGB(155, 235, 240)
	local eyeGlow = if stage == 1 then Color3.fromRGB(220, 230, 200) elseif isBoss then cyanGlow else Color3.fromRGB(210, 145, 255)
	local armorMetal = Color3.fromRGB(58, 56, 72)
	local armorDark = Color3.fromRGB(28, 28, 38)
	local hazardCyan = Color3.fromRGB(98, 230, 220)

	local groundY = CHAMBER_TOP
	local hipY = groundY + legH
	local torsoCenterY = hipY + torsoH / 2
	local neckY = hipY + torsoH
	local headCenterY = neckY + headD / 2 - headD * 0.05
	local cx, cz = basePos.X, basePos.Z

	-- EnemyCore = unsichtbare Bounding-Box (groesser bei Boss wegen Cape).
	local boxW = math.max(torsoW + 0.8 + (if isBoss then 4 else if stage >= 3 then 1.6 else 0.4), headD + 0.6)
	local boxH = totalH + (if isBoss then 1.5 else 0.5)
	local boxD = torsoD + (if isBoss then 2.5 else if stage >= 3 then 1.4 else 0.6)
	local root = makePart(model, "EnemyCore", Vector3.new(boxW, boxH, boxD), Vector3.new(cx, groundY + boxH / 2, cz), bodyColor, Enum.Material.SmoothPlastic, false)
	root.CanQuery = true
	root.Transparency = 1
	model.PrimaryPart = root

	-- ---- Beine ---------------------------------------------------------
	local legSpacing = torsoW * 0.32
	for _, side in ipairs({ -1, 1 }) do
		local legColor = if stage >= 3 then armorMetal else bodyColor
		makePart(model, "FluLeg", Vector3.new(legW, legH * 0.9, legW), Vector3.new(cx + side * legSpacing, hipY - legH * 0.5, cz), legColor, Enum.Material.SmoothPlastic, false)
		makePart(model, "FluBoot", Vector3.new(legW * 1.3, legH * 0.22, legW * 1.4), Vector3.new(cx + side * legSpacing, groundY + legH * 0.11, cz + legW * 0.1), armorDark, Enum.Material.Metal, false)
		if stage >= 4 then
			-- Eis-Kristall am Knie
			local crystal = makePart(model, "FluKneeCrystal", Vector3.new(0.45, 0.9, 0.45), Vector3.new(cx + side * legSpacing, hipY - legH * 0.55, cz - legW * 0.55), crystalCyan, Enum.Material.Neon, false)
			crystal.Transparency = 0.18
			crystal.Orientation = Vector3.new(-30, 0, side * 15)
		end
	end

	-- ---- Torso ---------------------------------------------------------
	local torsoColor = if stage >= 3 then armorMetal else bodyColor
	local torso = makePart(model, "FluTorso", Vector3.new(torsoW, torsoH, torsoD), Vector3.new(cx, torsoCenterY, cz), torsoColor, Enum.Material.SmoothPlastic, false)
	-- Body-Nubs (Stage 1-2 ueber den ganzen Koerper, virusartig)
	if stage <= 2 then
		for i = 1, 10 do
			local seed = i * 1.7
			local nx = math.sin(seed * 1.1) * 0.45 * torsoW
			local ny = math.cos(seed * 0.8) * 0.45 * torsoH
			local nz = -torsoD / 2 - 0.05
			local nubSize = 0.35 + (i % 3) * 0.06
			local nub = makePart(model, "FluBodyNub", Vector3.new(nubSize, nubSize, nubSize * 0.7), Vector3.new(cx + nx, torsoCenterY + ny, nz + cz), tint(bodyColor, bodyDark, 0.25), Enum.Material.SmoothPlastic, false)
			nub.Shape = Enum.PartType.Ball
		end
	end
	-- Armor-Plattenstrukturen ab Stage 3 (Riegel-Look)
	if stage >= 3 then
		for i = 1, 3 do
			local plateY = torsoCenterY - torsoH * 0.35 + (i - 1) * (torsoH * 0.3)
			makePart(model, "FluArmorPlate", Vector3.new(torsoW * 0.9, torsoH * 0.22, 0.16), Vector3.new(cx, plateY, cz - torsoD / 2 - 0.1), tint(armorMetal, armorDark, 0.3), Enum.Material.Metal, false)
		end
		-- Nieten an den Plattenecken
		for _, side in ipairs({ -1, 1 }) do
			for _, vy in ipairs({ -torsoH * 0.32, torsoH * 0, torsoH * 0.32 }) do
				makePart(model, "FluRivet", Vector3.new(0.18, 0.18, 0.18), Vector3.new(cx + side * torsoW * 0.4, torsoCenterY + vy, cz - torsoD / 2 - 0.16), armorDark, Enum.Material.Metal, false).Shape = Enum.PartType.Ball
			end
		end
	end

	-- ---- Biohazard auf der Brust (Stage 3+) ---------------------------
	if stage >= 3 then
		local hazSize = torsoW * (if isBoss then 0.48 else 0.38)
		makePart(model, "FluHazardBacking", Vector3.new(hazSize * 1.18, hazSize * 1.18, 0.05), Vector3.new(cx, torsoCenterY - torsoH * 0.05, cz - torsoD / 2 - 0.18), armorDark, Enum.Material.SmoothPlastic, false)
		local hazard = makePart(model, "FluHazard", Vector3.new(hazSize, hazSize, 0.06), Vector3.new(cx, torsoCenterY - torsoH * 0.05, cz - torsoD / 2 - 0.22), hazardCyan, Enum.Material.Neon, false)
		hazard.Transparency = 0.05
		local pl = Instance.new("PointLight")
		pl.Brightness = if isBoss then 2.5 else 1.2
		pl.Range = if isBoss then 18 else 10
		pl.Color = hazardCyan
		pl.Parent = hazard
	end

	-- ---- Schulterpanzer (alle Stages, mehr je Stage) ------------------
	for _, side in ipairs({ -1, 1 }) do
		local padW = torsoW * 0.32 + (stage - 1) * 0.1 + (if isBoss then 0.5 else 0)
		local padH = torsoH * 0.35 + (stage - 1) * 0.08
		local padX = cx + side * (torsoW * 0.5 + padW * 0.3)
		local padY = torsoCenterY + torsoH * 0.42
		local padColor = if stage >= 3 then armorMetal else bodyColor
		local pad = makePart(model, "FluShoulderPad", Vector3.new(padW, padH, torsoD * 1.15), Vector3.new(padX, padY, cz), padColor, Enum.Material.SmoothPlastic, false)
		pad.Orientation = Vector3.new(0, 0, side * -12)
		-- Federbuesche ab Stage 2 (mehr je Stage)
		if stage >= 2 then
			local featherCount = 3 + (stage - 2) + (if isBoss then 5 else 0)
			for k = 1, featherCount do
				local fAngle = (k - (featherCount + 1) / 2) * 0.32 + side * 0.1
				local fLen = 1.0 + (stage - 2) * 0.3 + (if isBoss then 1.4 else 0)
				local fOffsetX = side * (padW * 0.6) + math.sin(fAngle) * 0.4
				local fy = padY + padH * 0.4 + math.cos(fAngle) * 0.5
				local fz = cz + 0.3 + (k - 1) * 0.18
				local color = if k % 2 == 0 then featherPurple else featherDeep
				local feather = makePart(model, "FluFeather", Vector3.new(0.18, fLen, 0.5), Vector3.new(padX + fOffsetX, fy + fLen * 0.4, fz), color, Enum.Material.SmoothPlastic, false)
				feather.Orientation = Vector3.new(side * 25, side * 30 + math.deg(fAngle) * 10, math.deg(fAngle) * 35)
			end
		end
		-- Eiskristalle auf den Schulterpads (Stage 4+)
		if stage >= 4 then
			local crystal = makePart(model, "FluShoulderCrystal", Vector3.new(0.5, 1.4 + (if isBoss then 0.6 else 0), 0.5), Vector3.new(padX, padY + padH * 0.5 + 0.7, cz), crystalCyan, Enum.Material.Neon, false)
			crystal.Transparency = 0.15
			crystal.Orientation = Vector3.new(0, 0, side * -10)
			local pl = Instance.new("PointLight")
			pl.Brightness = 1.2
			pl.Range = 8
			pl.Color = cyanGlow
			pl.Parent = crystal
		end
	end

	-- ---- Arme + Haende (Boss mit leuchtenden Orbs) --------------------
	local armLen = torsoH * 0.95
	local armW = torsoW * 0.22 + (stage - 1) * 0.05
	for _, side in ipairs({ -1, 1 }) do
		local armX = cx + side * (torsoW * 0.55 + armW * 0.3)
		local armY = torsoCenterY - torsoH * 0.05
		local sleeveColor = if stage >= 3 then armorMetal else bodyColor
		makePart(model, "FluArm", Vector3.new(armW, armLen, armW), Vector3.new(armX, armY, cz), sleeveColor, Enum.Material.SmoothPlastic, false)
		local handSize = armW * 1.4
		local handY = armY - armLen * 0.5 - handSize * 0.3
		-- Boss: leuchtende Cyan-Orbs in beiden Haenden
		if isBoss then
			local orbSize = handSize * 1.8
			local orb = makePart(model, "BossFluHandOrb", Vector3.new(orbSize, orbSize, orbSize), Vector3.new(armX, handY, cz - handSize * 0.2), cyanGlow, Enum.Material.Neon, false)
			orb.Shape = Enum.PartType.Ball
			orb.Transparency = 0.1
			local orbOuter = makePart(model, "BossFluHandOrbOuter", Vector3.new(orbSize * 1.35, orbSize * 1.35, orbSize * 1.35), Vector3.new(armX, handY, cz - handSize * 0.2), tint(cyanGlow, Color3.fromRGB(245, 250, 240), 0.35), Enum.Material.Glass, false)
			orbOuter.Shape = Enum.PartType.Ball
			orbOuter.Transparency = 0.55
			local pl = Instance.new("PointLight")
			pl.Brightness = 2.6
			pl.Range = 18
			pl.Color = cyanGlow
			pl.Parent = orb
		else
			local hand = makePart(model, "FluHand", Vector3.new(handSize, handSize * 0.85, handSize), Vector3.new(armX, handY, cz), if stage >= 3 then armorMetal else bodyColor, Enum.Material.SmoothPlastic, false)
			hand.Shape = Enum.PartType.Ball
		end
	end

	-- ---- Kopf: Virus-Sphaere mit Spikeprotein-Knubbeln ----------------
	local head = makePart(model, "FluHead", Vector3.new(headD, headD, headD), Vector3.new(cx, headCenterY, cz), headColor, Enum.Material.SmoothPlastic, false)
	head.Shape = Enum.PartType.Ball

	-- Knubbel (12-18 Stueck, rundliche Knaufe verteilt auf der Sphaere).
	local nubCount = 12 + stage * 2 + (if isBoss then 4 else 0)
	for i = 1, nubCount do
		-- Spirale-Verteilung ueber die Sphaere (Fibonacci-aehnlich vereinfacht)
		local t = i / nubCount
		local theta = i * 2.4
		local phi = math.acos(1 - 2 * t)
		local dir = Vector3.new(math.sin(phi) * math.cos(theta), math.cos(phi), math.sin(phi) * math.sin(theta)).Unit
		local stalkLen = headD * 0.22 + (stage - 1) * 0.025
		local stalkCenter = Vector3.new(cx, headCenterY, cz) + dir * (headD * 0.5 + stalkLen * 0.5)
		local stalk = makePart(model, "FluHeadNubStalk", Vector3.new(stalkLen * 0.55, stalkLen, stalkLen * 0.55), stalkCenter, tint(headColor, bodyDark, 0.25), Enum.Material.SmoothPlastic, false)
		local upv = if math.abs(dir.Y) > 0.95 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
		stalk.CFrame = CFrame.lookAt(stalkCenter, stalkCenter + dir, upv) * CFrame.Angles(math.rad(90), 0, 0)
		-- Knauf am Tip (rundlich)
		local knob = makePart(model, "FluHeadNubKnob", Vector3.new(stalkLen * 0.85, stalkLen * 0.85, stalkLen * 0.85), stalkCenter + dir * (stalkLen * 0.55), tint(headColor, Color3.fromRGB(220, 230, 220), 0.2), Enum.Material.SmoothPlastic, false)
		knob.Shape = Enum.PartType.Ball
	end

	-- Krone-Spikes oben am Kopf (Stage 3+, deutlicher beim Boss)
	if stage >= 3 then
		local crownCount = 4 + stage + (if isBoss then 4 else 0)
		local crownLen = headD * 0.4 + (if isBoss then 0.6 else 0)
		for i = 1, crownCount do
			local a = (i / crownCount) * math.pi * 2
			local fwd = math.cos(a) * 0.5
			local dir = Vector3.new(fwd, 0.85, math.sin(a) * 0.5).Unit
			local sc = Vector3.new(cx, headCenterY, cz) + dir * headD * 0.55
			local spike = makePart(model, "FluCrownSpike", Vector3.new(0.34, crownLen, 0.34), sc, armorDark, Enum.Material.Metal, false)
			local upv = if math.abs(dir.Y) > 0.95 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
			spike.CFrame = CFrame.lookAt(sc, sc + dir, upv) * CFrame.Angles(math.rad(90), 0, 0)
			makePart(model, "FluCrownSpikeTip", Vector3.new(0.38, 0.2, 0.38), sc + dir * (crownLen * 0.55), if isBoss then cyanGlow else tint(featherPurple, armorDark, 0.3), Enum.Material.Neon, false)
		end
	end

	-- Augen: kleine leuchtende Slits (Stage 1 hell, Stage 2-4 lila, Boss cyan).
	local eyeY = headCenterY + headD * 0.08
	for _, side in ipairs({ -1, 1 }) do
		local eye = makePart(model, "FluEye", Vector3.new(headD * 0.20, headD * 0.12, 0.12), Vector3.new(cx + side * headD * 0.18, eyeY, cz - headD * 0.48), eyeGlow, Enum.Material.Neon, false)
		eye.Transparency = 0.05
		eye.Orientation = Vector3.new(0, 0, side * -22)
		local pl = Instance.new("PointLight")
		pl.Brightness = 0.6
		pl.Range = 6
		pl.Color = eyeGlow
		pl.Parent = eye
	end

	-- Gasmaske (Stage 3+): 2 Filter-Zylinder unten am Gesicht + Mundpanel.
	if stage >= 3 then
		local maskColor = armorDark
		-- Mundpanel
		local maskCenter = makePart(model, "FluMaskCenter", Vector3.new(headD * 0.6, headD * 0.4, 0.18), Vector3.new(cx, headCenterY - headD * 0.18, cz - headD * 0.48), maskColor, Enum.Material.Metal, false)
		-- Filter-Zylinder
		for _, side in ipairs({ -1, 1 }) do
			local filter = makePart(model, "FluMaskFilter", Vector3.new(0.55, 0.7, 0.55), Vector3.new(cx + side * headD * 0.25, headCenterY - headD * 0.32, cz - headD * 0.55), maskColor, Enum.Material.Metal, false)
			filter.Shape = Enum.PartType.Cylinder
			filter.Orientation = Vector3.new(0, 0, 90)
			-- Filter-Gluehring
			local fg = makePart(model, "FluMaskFilterGlow", Vector3.new(0.6, 0.18, 0.6), Vector3.new(cx + side * headD * 0.25, headCenterY - headD * 0.42, cz - headD * 0.55), if isBoss then cyanGlow else tint(featherPurple, cyanGlow, 0.3), Enum.Material.Neon, false)
			fg.Shape = Enum.PartType.Cylinder
			fg.Orientation = Vector3.new(0, 0, 90)
		end
		-- Schlauch von Filter zur Wange (klein, dekorativ)
		for _, side in ipairs({ -1, 1 }) do
			local hose = makePart(model, "FluMaskHose", Vector3.new(0.22, 0.6, 0.22), Vector3.new(cx + side * headD * 0.32, headCenterY - headD * 0.05, cz - headD * 0.5), armorMetal, Enum.Material.Metal, false)
			hose.Orientation = Vector3.new(0, 0, side * -30)
		end
	end

	-- ---- Feder-Kragen / Mantel (Stage 3+, beim Boss massiv) -----------
	if stage >= 3 then
		-- Halsteil
		local collarFeatherCount = 6 + (stage - 3) * 4 + (if isBoss then 16 else 0)
		for i = 1, collarFeatherCount do
			local a = (i / collarFeatherCount) * math.pi * 1.7 - math.pi * 0.85
			local fLen = 1.6 + (stage - 3) * 0.4 + (if isBoss then 1.8 else 0)
			local fx = cx + math.cos(a) * (torsoW * 0.5 + 0.3)
			local fy = neckY + 0.2 + math.sin(a) * 0.5
			local fz = cz + torsoD * 0.3 + 0.2
			local color = if i % 3 == 0 then featherDeep elseif (i % 3) == 1 then featherPurple else tint(featherPurple, cyanGlow, 0.2)
			local feather = makePart(model, "FluCollarFeather", Vector3.new(0.22, fLen, 0.65), Vector3.new(fx, fy + fLen * 0.4, fz), color, Enum.Material.SmoothPlastic, false)
			feather.Orientation = Vector3.new(math.deg(a) * 0.4, math.deg(a) * 40, math.deg(a) * 20)
		end
	end

	-- ---- BOSS Extras: Cape, Krone, Glow-Plattform ---------------------
	if isBoss then
		-- Cape/Fluegel hinter dem Boss: grosser Faecher aus Federn nach links/rechts/oben.
		local capeCount = 24
		for i = 1, capeCount do
			local a = (i / capeCount) * math.pi - math.pi * 0.5
			local fLen = 3.0 + math.cos(a) * 1.5
			local fx = cx + math.sin(a) * (torsoW * 0.7 + 1.0)
			local fy = torsoCenterY + math.cos(a) * 2.4 + 1.0
			local fz = cz + torsoD * 0.4 + 0.4 + math.abs(math.sin(a)) * 0.6
			local color = if i % 3 == 0 then featherDeep elseif (i % 3) == 1 then featherPurple else tint(featherPurple, cyanGlow, 0.25)
			local feather = makePart(model, "BossFluCapeFeather", Vector3.new(0.3, fLen, 0.75), Vector3.new(fx, fy + fLen * 0.45, fz), color, Enum.Material.SmoothPlastic, false)
			feather.Orientation = Vector3.new(math.deg(a) * 0.3, math.deg(a) * 35, math.deg(a) * 60)
		end
		-- BossPad (Vertrag)
		local ring = makePart(model, "BossPad", Vector3.new(0.5, totalH * 1.15, totalH * 1.15), Vector3.new(basePos.X, CHAMBER_TOP + 1.25, basePos.Z), cyanGlow, Enum.Material.Neon, false)
		ring.Shape = Enum.PartType.Cylinder
		ring.Orientation = Vector3.new(0, 0, 90)
		ring.Transparency = 0.3
		-- Aeusserer Bodenring
		local floor1 = makePart(model, "BossFluFloorGlow", Vector3.new(0.2, totalH * 1.5, totalH * 1.5), Vector3.new(basePos.X, CHAMBER_TOP + 0.15, basePos.Z), crystalCyan, Enum.Material.Neon, false)
		floor1.Shape = Enum.PartType.Cylinder
		floor1.Orientation = Vector3.new(0, 0, 90)
		floor1.Transparency = 0.55
	end

	-- ---- Aura Partikel (Federn/Mist) ----------------------------------
	local mist = Instance.new("ParticleEmitter")
	mist.Name = "InfluenzaMist"
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(if stage >= 4 then cyanGlow else tint(featherPurple, Color3.fromRGB(220, 230, 240), 0.2), tint(featherDeep, Color3.fromRGB(20, 30, 40), 0.5))
	mist.LightEmission = 0.25
	mist.Rate = if isBoss then 14 else 2 + stage
	mist.Lifetime = NumberRange.new(1.0, 1.8)
	mist.Speed = NumberRange.new(0.4, 1.4)
	mist.Acceleration = Vector3.new(0, 1.4, 0)
	mist.SpreadAngle = Vector2.new(40, 40)
	mist.Size = NumberSequence.new(0.5, 0.1)
	mist.Parent = torso

	-- ---- Bewegung -----------------------------------------------------
	local arche = ENEMY_ARCHETYPE[def.Shape] or ENEMY_ARCHETYPE.Blob
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
	model:SetAttribute("HomeX", cx)
	model:SetAttribute("HomeY", root.Position.Y)
	model:SetAttribute("HomeZ", cz)
	model:SetAttribute("MoveRangeX", mv.rx)
	model:SetAttribute("MoveRangeZ", mv.rz)
	model:SetAttribute("MoveSpeed", mv.sp)
	model:SetAttribute("BobAmp", mv.bob)
	model:SetAttribute("EnemyKind", "Influenza")

	-- ---- Health-Bar ---------------------------------------------------
	local barScale = if isBoss then 1.9 else 1
	local barY = groundY + totalH + (if isBoss then 2.8 else 1.8)
	local barBack = makePart(model, "HealthBarBack", Vector3.new(13 * barScale, 0.8, 0.4), Vector3.new(cx, barY, cz), Color3.fromRGB(16, 20, 26), Enum.Material.SmoothPlastic, false)
	local barFill = makePart(model, "HealthBarFill", Vector3.new(12.4 * barScale, 0.5, 0.55), Vector3.new(cx, barY + 0.02, cz - 0.06), Color3.fromRGB(95, 255, 125), Enum.Material.Neon, false)
	barFill.Transparency = 0.12
	barFill:SetAttribute("MaxWidth", 12.4 * barScale)
	barFill:SetAttribute("FullCenterX", barFill.Position.X)

	-- ---- AttackClick + Boss-Prompt ------------------------------------
	local clicker = Instance.new("ClickDetector")
	clicker.Name = "AttackClick"
	clicker.MaxActivationDistance = EnemyConfig.AttackDistance
	clicker.Parent = root

	if isBoss then
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

	-- ---- Info-Label ---------------------------------------------------
	local prefix = if isBoss then "★ BOSS ★\n" else ""
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
		if isBoss then 60 else 34,
		UDim2.fromOffset(if isBoss then 280 else 190, if isBoss then 104 else 76),
		Vector3.new(0, boxH / 2 + 3, 0)
	)

	return model
end

-- ---- Bone Spike Virus-Set fuer Area 5 -----------------------------------
-- Schwarzer Koerper mit Knochenpanzer-Tiles und cyan glowing Risen/Augen.
-- Progressive Mutation: simple Spike-Sphaere (Stage 1) -> Schulter-Knochen
-- (Stage 2) -> Knochen-Helm (Stage 3) -> Krone (Stage 4) -> Cyclops-Boss
-- mit massiver Knochenkrone, Ketten und riesigem Cyan-Auge.
local function buildBoneSpikeEnemyModel(parent, def, basePos, primary, secondary)
	local model = Instance.new("Model")
	model.Name = def.Id
	model:SetAttribute("EnemyId", def.Id)
	model:SetAttribute("AreaName", def.AreaName)
	model:SetAttribute("IsBoss", def.IsBoss)
	model.Parent = parent

	local stage = def.EnemyIndex
	local isBoss = def.IsBoss
	local totalHeights = { 5.0, 6.2, 7.4, 8.6, 9.8 }
	local totalH = totalHeights[stage] or 5.0

	local legH = 1.6 + (stage - 1) * 0.45
	local headD = 2.0 + (stage - 1) * 0.30 + (if isBoss then 0.6 else 0)
	local torsoH = totalH - legH - headD * 0.40
	if torsoH < 0.8 then
		torsoH = 0.8
	end
	local torsoW = 1.7 + (stage - 1) * 0.38 + (if isBoss then 1.5 else 0)
	local torsoD = torsoW * 0.6 + (if isBoss then 0.55 else 0)
	local legW = 0.7 + (stage - 1) * 0.12 + (if isBoss then 0.35 else 0)

	-- Bone Spike-Palette: schwarzer Koerper + Knochen + Cyan Glow.
	local bodyBlack = Color3.fromRGB(22, 22, 25)
	local bodyDark = Color3.fromRGB(42, 40, 44)
	local boneWhite = Color3.fromRGB(228, 220, 198)
	local boneShadow = Color3.fromRGB(172, 160, 132)
	local boneDeep = Color3.fromRGB(108, 98, 78)
	local cyanGlow = Color3.fromRGB(78, 232, 220)
	local cyanDeep = Color3.fromRGB(48, 178, 172)
	local crackGlow = Color3.fromRGB(150, 245, 235)

	local groundY = CHAMBER_TOP
	local hipY = groundY + legH
	local torsoCenterY = hipY + torsoH / 2
	local neckY = hipY + torsoH
	local headCenterY = neckY + headD / 2 - headD * 0.05
	local cx, cz = basePos.X, basePos.Z

	-- EnemyCore = unsichtbare Bounding-Box.
	local boxW = math.max(torsoW + 0.8 + (if isBoss then 3.5 else if stage >= 3 then 1.6 else 0.6), headD + 0.8)
	local boxH = totalH + (if isBoss then 2.2 else 1.0)
	local boxD = torsoD + (if isBoss then 1.8 else if stage >= 3 then 0.8 else 0.4)
	local root = makePart(model, "EnemyCore", Vector3.new(boxW, boxH, boxD), Vector3.new(cx, groundY + boxH / 2, cz), bodyBlack, Enum.Material.SmoothPlastic, false)
	root.CanQuery = true
	root.Transparency = 1
	model.PrimaryPart = root

	-- Helper: setzt eine Knochen-Plate (Scale-Tile) auf eine Position.
	local function bonePlate(name, size, pos, orientation, colorMix)
		local plate = makePart(model, name, size, pos, colorMix or tint(boneWhite, boneShadow, 0.2), Enum.Material.SmoothPlastic, false)
		if orientation then
			plate.Orientation = orientation
		end
		return plate
	end

	-- ---- Beine ---------------------------------------------------------
	local legSpacing = torsoW * 0.32
	for _, side in ipairs({ -1, 1 }) do
		makePart(model, "BoneLeg", Vector3.new(legW, legH * 0.9, legW), Vector3.new(cx + side * legSpacing, hipY - legH * 0.5, cz), bodyBlack, Enum.Material.SmoothPlastic, false)
		makePart(model, "BoneBoot", Vector3.new(legW * 1.3, legH * 0.22, legW * 1.4), Vector3.new(cx + side * legSpacing, groundY + legH * 0.11, cz + legW * 0.1), bodyDark, Enum.Material.Metal, false)
		-- Bone-Plates auf den Knien ab Stage 2
		if stage >= 2 then
			bonePlate("BoneKneePlate", Vector3.new(legW * 1.0, legH * 0.25, legW * 0.5), Vector3.new(cx + side * legSpacing, hipY - legH * 0.4, cz - legW * 0.5), Vector3.new(-15, 0, 0))
		end
		-- Schienbein-Knochen-Stachel ab Stage 3
		if stage >= 3 then
			local spikeLen = 0.7 + (stage - 3) * 0.3
			local spike = makePart(model, "BoneShinSpike", Vector3.new(0.4, spikeLen, 0.4), Vector3.new(cx + side * legSpacing, hipY - legH * 0.7, cz - legW * 0.65), boneWhite, Enum.Material.SmoothPlastic, false)
			spike.Orientation = Vector3.new(35, 0, 0)
		end
	end

	-- ---- Torso ---------------------------------------------------------
	local torso = makePart(model, "BoneTorso", Vector3.new(torsoW, torsoH, torsoD), Vector3.new(cx, torsoCenterY, cz), bodyBlack, Enum.Material.SmoothPlastic, false)

	-- Bone-Scale-Plates auf der Brust (mehr je Stage)
	local plateRows = 2 + math.min(stage - 1, 3)
	local plateCols = 3 + math.min(stage - 1, 2)
	for r = 1, plateRows do
		for c = 1, plateCols do
			local px = cx + (c - (plateCols + 1) / 2) * (torsoW * 0.85 / plateCols)
			local py = torsoCenterY + (r - (plateRows + 1) / 2) * (torsoH * 0.6 / plateRows)
			local plateSize = Vector3.new(torsoW * 0.7 / plateCols, torsoH * 0.5 / plateRows, 0.16)
			local plateColor = tint(boneWhite, boneShadow, (r + c) % 2 * 0.25)
			bonePlate("BoneChestPlate", plateSize, Vector3.new(px, py, cz - torsoD / 2 - 0.12), nil, plateColor)
		end
	end

	-- Cyan Brust-Kern (alle Stages, groesser je Stage)
	local coreSize = headD * (0.22 + (stage - 1) * 0.08) + (if isBoss then 0.3 else 0)
	local coreBack = makePart(model, "BoneCoreSocket", Vector3.new(coreSize * 1.6, coreSize * 1.6, 0.16), Vector3.new(cx, torsoCenterY - torsoH * 0.05, cz - torsoD / 2 - 0.2), bodyBlack, Enum.Material.SmoothPlastic, false)
	-- Knochenring um den Kern (Stage 3+)
	if stage >= 3 then
		for k = 1, 8 do
			local a = (k / 8) * math.pi * 2
			local rx = cx + math.cos(a) * coreSize * 1.0
			local ry = torsoCenterY - torsoH * 0.05 + math.sin(a) * coreSize * 1.0
			local rib = makePart(model, "BoneCoreRib", Vector3.new(0.2, coreSize * 0.55, 0.2), Vector3.new(rx, ry, cz - torsoD / 2 - 0.24), boneWhite, Enum.Material.SmoothPlastic, false)
			rib.Orientation = Vector3.new(0, 0, math.deg(a) + 90)
		end
	end
	local core = makePart(model, "BoneCore", Vector3.new(coreSize, coreSize, coreSize * 0.6), Vector3.new(cx, torsoCenterY - torsoH * 0.05, cz - torsoD / 2 - 0.28), cyanGlow, Enum.Material.Neon, false)
	core.Shape = Enum.PartType.Ball
	core.Transparency = 0.05
	local coreLight = Instance.new("PointLight")
	coreLight.Brightness = if isBoss then 3 else 1.5
	coreLight.Range = if isBoss then 22 else 12
	coreLight.Color = cyanGlow
	coreLight.Parent = core
	-- Glas-Auenhuelle
	local coreOuter = makePart(model, "BoneCoreOuter", Vector3.new(coreSize * 1.5, coreSize * 1.5, coreSize * 0.4), Vector3.new(cx, torsoCenterY - torsoH * 0.05, cz - torsoD / 2 - 0.18), tint(cyanGlow, Color3.fromRGB(240, 250, 240), 0.35), Enum.Material.Glass, false)
	coreOuter.Shape = Enum.PartType.Ball
	coreOuter.Transparency = 0.5

	-- ---- Schulterpanzer + Bone-Spikes ---------------------------------
	for _, side in ipairs({ -1, 1 }) do
		local padW = torsoW * 0.32 + (stage - 1) * 0.12 + (if isBoss then 0.7 else 0)
		local padH = torsoH * 0.35 + (stage - 1) * 0.1
		local padX = cx + side * (torsoW * 0.5 + padW * 0.3)
		local padY = torsoCenterY + torsoH * 0.42
		bonePlate("BoneShoulderPad", Vector3.new(padW, padH, torsoD * 1.15), Vector3.new(padX, padY, cz), Vector3.new(0, 0, side * -12))
		-- Bone-Spikes auf der Schulter (Stage 2+)
		if stage >= 2 then
			local spikeCount = stage - 1 + (if isBoss then 4 else 0)
			for k = 1, spikeCount do
				local a = (k - 1) / math.max(1, spikeCount - 1) * math.pi * 0.6 - math.pi * 0.3
				local spikeLen = 1.0 + (stage - 2) * 0.35 + (if isBoss then 1.2 else 0)
				local sx = padX + side * math.cos(a) * 0.4
				local sy = padY + padH * 0.5 + math.sin(a) * 0.3
				local sz = cz + math.cos(a) * 0.3
				local spike = makePart(model, "BoneShoulderSpike", Vector3.new(0.42, spikeLen, 0.42), Vector3.new(sx + side * 0.3, sy + spikeLen * 0.4, sz), boneWhite, Enum.Material.SmoothPlastic, false)
				spike.Orientation = Vector3.new(15, side * (math.deg(a) * 0.8 + 30), side * -50)
				makePart(model, "BoneShoulderSpikeTip", Vector3.new(0.46, 0.3, 0.46), Vector3.new(sx + side * 0.6, sy + spikeLen * 0.9, sz), boneShadow, Enum.Material.SmoothPlastic, false)
			end
		end
	end

	-- ---- Arme + Haende -------------------------------------------------
	local armLen = torsoH * 0.95
	local armW = torsoW * 0.22 + (stage - 1) * 0.05
	for _, side in ipairs({ -1, 1 }) do
		local armX = cx + side * (torsoW * 0.55 + armW * 0.3)
		local armY = torsoCenterY - torsoH * 0.05
		makePart(model, "BoneArm", Vector3.new(armW, armLen, armW), Vector3.new(armX, armY, cz), bodyBlack, Enum.Material.SmoothPlastic, false)
		-- Arm-Bone-Plate ab Stage 2
		if stage >= 2 then
			bonePlate("BoneArmPlate", Vector3.new(armW * 1.15, armLen * 0.55, 0.18), Vector3.new(armX, armY + armLen * 0.05, cz - armW * 0.55), nil)
		end
		-- Handschuh + Klauen ab Stage 3
		local handSize = armW * 1.4
		local handY = armY - armLen * 0.5 - handSize * 0.3
		local hand = makePart(model, "BoneHand", Vector3.new(handSize, handSize * 0.85, handSize), Vector3.new(armX, handY, cz), bodyBlack, Enum.Material.SmoothPlastic, false)
		hand.Shape = Enum.PartType.Ball
		if stage >= 3 then
			for k = -1, 1 do
				local cxx = armX + k * handSize * 0.32
				local clawLen = handSize * (0.85 + (stage - 3) * 0.25)
				makePart(model, "BoneClaw", Vector3.new(0.24, clawLen, 0.24), Vector3.new(cxx, handY - clawLen * 0.5, cz + handSize * 0.1), boneWhite, Enum.Material.SmoothPlastic, false)
				makePart(model, "BoneClawTip", Vector3.new(0.28, 0.2, 0.28), Vector3.new(cxx, handY - clawLen - 0.05, cz + handSize * 0.1), boneShadow, Enum.Material.SmoothPlastic, false)
			end
		end
	end

	-- ---- Kopf ----------------------------------------------------------
	-- Stage 1-2: Knochen-Sphaere mit Tile-Texture + Cyan Center-Glow
	-- Stage 3+: Knochen-Helm (Schaedel-Optik) ueber dem Kopf
	-- Boss: Cyclops-Auge in der Mitte
	local head = makePart(model, "BoneHead", Vector3.new(headD, headD, headD), Vector3.new(cx, headCenterY, cz), bodyDark, Enum.Material.SmoothPlastic, false)
	head.Shape = Enum.PartType.Ball

	-- Tile-Knochen-Belag (12-20 Stueck rundum, Fibonacci-Verteilung)
	local tileCount = 16 + stage * 2 + (if isBoss then 6 else 0)
	for i = 1, tileCount do
		local t = i / tileCount
		local theta = i * 2.4
		local phi = math.acos(1 - 2 * t)
		local dir = Vector3.new(math.sin(phi) * math.cos(theta), math.cos(phi), math.sin(phi) * math.sin(theta)).Unit
		local tilePos = Vector3.new(cx, headCenterY, cz) + dir * headD * 0.5
		local tileSize = headD * 0.22
		local tile = makePart(model, "BoneHeadTile", Vector3.new(tileSize, tileSize, tileSize * 0.5), tilePos, tint(boneWhite, boneShadow, (i % 3) * 0.2), Enum.Material.SmoothPlastic, false)
		local upv = if math.abs(dir.Y) > 0.95 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
		tile.CFrame = CFrame.lookAt(tilePos, tilePos + dir, upv) * CFrame.Angles(math.rad(90), 0, 0)
	end

	-- Stage 1-2: glowing Center-Augen-Slit (1 zentrales Auge oder 2 kleine?)
	-- Reference Stage 1 hat 1 grosses Auge in der Mitte des Kopfes. Stage 2 auch.
	if stage <= 2 then
		local centerEyeSize = headD * 0.28
		local socket = makePart(model, "BoneEyeSocket", Vector3.new(centerEyeSize * 1.2, centerEyeSize * 1.2, 0.12), Vector3.new(cx, headCenterY, cz - headD * 0.48), bodyBlack, Enum.Material.SmoothPlastic, false)
		local eye = makePart(model, "BoneEye", Vector3.new(centerEyeSize, centerEyeSize, 0.14), Vector3.new(cx, headCenterY, cz - headD * 0.52), cyanGlow, Enum.Material.Neon, false)
		eye.Shape = Enum.PartType.Ball
		eye.Transparency = 0.05
		local pl = Instance.new("PointLight")
		pl.Brightness = 1.2
		pl.Range = 8
		pl.Color = cyanGlow
		pl.Parent = eye
		-- Kleine Bone-Knubbel rund um den Kopf (sichtbare "Knoten")
		if stage >= 1 then
			local nubCount = 4 + stage * 2
			for i = 1, nubCount do
				local a = (i / nubCount) * math.pi * 2
				local up = 0.4 + math.abs(math.sin(i * 0.9)) * 0.5
				local dir = Vector3.new(math.cos(a) * 0.7, up, math.sin(a) * 0.7).Unit
				local nubLen = headD * 0.25
				local nubCenter = Vector3.new(cx, headCenterY, cz) + dir * headD * 0.55
				local nub = makePart(model, "BoneHeadNub", Vector3.new(nubLen * 0.5, nubLen, nubLen * 0.5), nubCenter, boneWhite, Enum.Material.SmoothPlastic, false)
				local upv = if math.abs(dir.Y) > 0.95 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
				nub.CFrame = CFrame.lookAt(nubCenter, nubCenter + dir, upv) * CFrame.Angles(math.rad(90), 0, 0)
			end
		end
	else
		-- Stage 3+: Knochen-Schaedel-Helm. Aus mehreren Plate-Parts gebaut.
		-- Stirnplatte
		bonePlate("BoneHelmTop", Vector3.new(headD * 0.95, headD * 0.55, headD * 0.95), Vector3.new(cx, headCenterY + headD * 0.2, cz), nil)
		-- Wangen/Seitenplatten
		for _, side in ipairs({ -1, 1 }) do
			bonePlate("BoneHelmCheek", Vector3.new(headD * 0.4, headD * 0.5, headD * 0.5), Vector3.new(cx + side * headD * 0.3, headCenterY - headD * 0.05, cz - headD * 0.1), Vector3.new(0, side * 25, 0))
		end
		-- Untere Kiefer-Platte
		bonePlate("BoneHelmJaw", Vector3.new(headD * 0.7, headD * 0.3, headD * 0.5), Vector3.new(cx, headCenterY - headD * 0.3, cz - headD * 0.15), nil)
		-- Augen-Sockets (dunkle Recesses) + Cyan-Glows
		if isBoss then
			-- Cyclops: 1 grosses zentrales Auge
			local socketSize = headD * 0.4
			makePart(model, "BoneEyeSocket", Vector3.new(socketSize * 1.2, socketSize * 1.2, 0.14), Vector3.new(cx, headCenterY + headD * 0.02, cz - headD * 0.5), bodyBlack, Enum.Material.SmoothPlastic, false)
			local bigEye = makePart(model, "BoneBossEye", Vector3.new(socketSize, socketSize, socketSize * 0.6), Vector3.new(cx, headCenterY + headD * 0.02, cz - headD * 0.56), cyanGlow, Enum.Material.Neon, false)
			bigEye.Shape = Enum.PartType.Ball
			bigEye.Transparency = 0.05
			-- Mehrere Innen-Glow-Schichten fuer Tiefe
			local innerGlow = makePart(model, "BoneBossEyeInner", Vector3.new(socketSize * 0.5, socketSize * 0.5, socketSize * 0.4), Vector3.new(cx, headCenterY + headD * 0.02, cz - headD * 0.6), crackGlow, Enum.Material.Neon, false)
			innerGlow.Shape = Enum.PartType.Ball
			local pl = Instance.new("PointLight")
			pl.Brightness = 4
			pl.Range = 28
			pl.Color = cyanGlow
			pl.Parent = bigEye
		else
			-- Stage 3/4: 2 kleine Cyan-Augen
			for _, side in ipairs({ -1, 1 }) do
				local socketSize = headD * 0.18
				makePart(model, "BoneEyeSocket", Vector3.new(socketSize * 1.15, socketSize * 1.15, 0.13), Vector3.new(cx + side * headD * 0.18, headCenterY + headD * 0.05, cz - headD * 0.5), bodyBlack, Enum.Material.SmoothPlastic, false)
				local eye = makePart(model, "BoneEye", Vector3.new(socketSize, socketSize, socketSize * 0.7), Vector3.new(cx + side * headD * 0.18, headCenterY + headD * 0.05, cz - headD * 0.56), cyanGlow, Enum.Material.Neon, false)
				eye.Shape = Enum.PartType.Ball
				eye.Transparency = 0.05
				local pl = Instance.new("PointLight")
				pl.Brightness = 1.5
				pl.Range = 10
				pl.Color = cyanGlow
				pl.Parent = eye
			end
			-- Nasenschlitz (kleines schwarzes Dreieck-Look mittig)
			makePart(model, "BoneNoseSlit", Vector3.new(headD * 0.08, headD * 0.22, 0.1), Vector3.new(cx, headCenterY - headD * 0.1, cz - headD * 0.55), bodyBlack, Enum.Material.SmoothPlastic, false)
		end
	end

	-- ---- Krone aus Knochen-Hoernern (Stage 3+) ------------------------
	if stage >= 3 then
		local hornCount = 4 + (stage - 3) * 2 + (if isBoss then 8 else 0)
		for i = 1, hornCount do
			local a = (i / hornCount) * math.pi * 2
			-- Bias: konzentriert nach hinten/oben fuer Krone-Look
			local up = 0.8 + math.abs(math.sin(i * 0.7)) * 0.2
			local fwd = math.cos(a) * 0.45
			local dir = Vector3.new(fwd, up, math.sin(a) * 0.45 + 0.1).Unit
			local hornLen = headD * (0.55 + (stage - 3) * 0.15) + (if isBoss then 1.0 else 0)
			local hc = Vector3.new(cx, headCenterY, cz) + dir * headD * 0.5
			local horn = makePart(model, "BoneCrownHorn", Vector3.new(0.42, hornLen, 0.42), hc, boneWhite, Enum.Material.SmoothPlastic, false)
			local upv = if math.abs(dir.Y) > 0.95 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
			horn.CFrame = CFrame.lookAt(hc, hc + dir, upv) * CFrame.Angles(math.rad(90), 0, 0)
			makePart(model, "BoneCrownHornTip", Vector3.new(0.46, 0.3, 0.46), hc + dir * (hornLen * 0.55), boneShadow, Enum.Material.SmoothPlastic, false)
		end
	end

	-- ---- BOSS Extras: Ketten, BossPad, Bodenring -----------------------
	if isBoss then
		-- Ketten haengen vom Brustkern nach unten
		for _, side in ipairs({ -1, 1 }) do
			for k = 1, 6 do
				local linkY = torsoCenterY - torsoH * 0.05 - k * 0.55
				local linkX = cx + side * (torsoW * 0.2 + math.sin(k * 0.4) * 0.15)
				local linkZ = cz - torsoD / 2 - 0.5
				local link = makePart(model, "BossBoneChain", Vector3.new(0.32, 0.18, 0.32), Vector3.new(linkX, linkY, linkZ), bodyDark, Enum.Material.Metal, false)
				link.Shape = Enum.PartType.Ball
			end
		end
		-- BossPad (Vertrag)
		local ring = makePart(model, "BossPad", Vector3.new(0.5, totalH * 1.15, totalH * 1.15), Vector3.new(basePos.X, CHAMBER_TOP + 1.25, basePos.Z), cyanGlow, Enum.Material.Neon, false)
		ring.Shape = Enum.PartType.Cylinder
		ring.Orientation = Vector3.new(0, 0, 90)
		ring.Transparency = 0.3
		-- Aeusserer Bodenring
		local floor1 = makePart(model, "BossBoneFloorGlow", Vector3.new(0.22, totalH * 1.55, totalH * 1.55), Vector3.new(basePos.X, CHAMBER_TOP + 0.15, basePos.Z), crackGlow, Enum.Material.Neon, false)
		floor1.Shape = Enum.PartType.Cylinder
		floor1.Orientation = Vector3.new(0, 0, 90)
		floor1.Transparency = 0.55
	end

	-- ---- Aura Partikel (Knochen-Staub/Cyan Mist) ----------------------
	local aura = Instance.new("ParticleEmitter")
	aura.Name = "BoneAura"
	aura.Texture = "rbxasset://textures/particles/smoke_main.dds"
	aura.Color = ColorSequence.new(cyanGlow, tint(boneShadow, Color3.fromRGB(30, 40, 40), 0.5))
	aura.LightEmission = 0.25
	aura.Rate = if isBoss then 14 else 2 + stage
	aura.Lifetime = NumberRange.new(1.0, 1.8)
	aura.Speed = NumberRange.new(0.4, 1.3)
	aura.Acceleration = Vector3.new(0, 1.5, 0)
	aura.SpreadAngle = Vector2.new(40, 40)
	aura.Size = NumberSequence.new(0.5, 0.1)
	aura.Parent = torso

	-- ---- Bewegung -----------------------------------------------------
	local arche = ENEMY_ARCHETYPE[def.Shape] or ENEMY_ARCHETYPE.Blob
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
	model:SetAttribute("HomeX", cx)
	model:SetAttribute("HomeY", root.Position.Y)
	model:SetAttribute("HomeZ", cz)
	model:SetAttribute("MoveRangeX", mv.rx)
	model:SetAttribute("MoveRangeZ", mv.rz)
	model:SetAttribute("MoveSpeed", mv.sp)
	model:SetAttribute("BobAmp", mv.bob)
	model:SetAttribute("EnemyKind", "BoneSpike")

	-- ---- Health-Bar ---------------------------------------------------
	local barScale = if isBoss then 1.9 else 1
	local barY = groundY + totalH + (if isBoss then 3.0 else 1.8)
	local barBack = makePart(model, "HealthBarBack", Vector3.new(13 * barScale, 0.8, 0.4), Vector3.new(cx, barY, cz), Color3.fromRGB(16, 20, 26), Enum.Material.SmoothPlastic, false)
	local barFill = makePart(model, "HealthBarFill", Vector3.new(12.4 * barScale, 0.5, 0.55), Vector3.new(cx, barY + 0.02, cz - 0.06), Color3.fromRGB(95, 255, 125), Enum.Material.Neon, false)
	barFill.Transparency = 0.12
	barFill:SetAttribute("MaxWidth", 12.4 * barScale)
	barFill:SetAttribute("FullCenterX", barFill.Position.X)

	-- ---- AttackClick + Boss-Prompt ------------------------------------
	local clicker = Instance.new("ClickDetector")
	clicker.Name = "AttackClick"
	clicker.MaxActivationDistance = EnemyConfig.AttackDistance
	clicker.Parent = root

	if isBoss then
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

	-- ---- Info-Label ---------------------------------------------------
	local prefix = if isBoss then "★ BOSS ★\n" else ""
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
		if isBoss then 60 else 34,
		UDim2.fromOffset(if isBoss then 280 else 190, if isBoss then 104 else 76),
		Vector3.new(0, boxH / 2 + 3, 0)
	)

	return model
end

-- ---- Plasma Core Virus-Set fuer Area 6 ----------------------------------
-- Dunkler purpur Koerper mit pink leuchtenden Rissen, Virus-Spikeprotein-
-- Kopf mit innerem Plasma-Core, Energie-Halo-Ring (Stage 3+), orbitale
-- Kristall-Shards. Boss bekommt mehrere Ringe + Shard-Schwarm.
local function buildPlasmaCoreEnemyModel(parent, def, basePos, primary, secondary)
	local model = Instance.new("Model")
	model.Name = def.Id
	model:SetAttribute("EnemyId", def.Id)
	model:SetAttribute("AreaName", def.AreaName)
	model:SetAttribute("IsBoss", def.IsBoss)
	model.Parent = parent

	local stage = def.EnemyIndex
	local isBoss = def.IsBoss
	local totalHeights = { 5.0, 6.2, 7.4, 8.6, 9.8 }
	local totalH = totalHeights[stage] or 5.0

	local legH = 1.6 + (stage - 1) * 0.45
	local headD = 2.0 + (stage - 1) * 0.30 + (if isBoss then 0.6 else 0)
	local torsoH = totalH - legH - headD * 0.40
	if torsoH < 0.8 then
		torsoH = 0.8
	end
	local torsoW = 1.7 + (stage - 1) * 0.38 + (if isBoss then 1.5 else 0)
	local torsoD = torsoW * 0.6 + (if isBoss then 0.55 else 0)
	local legW = 0.7 + (stage - 1) * 0.12 + (if isBoss then 0.35 else 0)

	-- Plasma Core-Palette: dunkles Purpur mit pinkem Glow.
	local bodyBlack = Color3.fromRGB(38, 22, 52)
	local bodyMid = Color3.fromRGB(72, 48, 100)
	local bodyDark = Color3.fromRGB(22, 14, 32)
	local plasmaPink = Color3.fromRGB(232, 88, 240)
	local plasmaCoreGlow = Color3.fromRGB(252, 152, 255)
	local plasmaDeep = Color3.fromRGB(170, 60, 210)
	local crystalLight = Color3.fromRGB(222, 168, 252)
	local crystalDark = Color3.fromRGB(118, 70, 168)

	local groundY = CHAMBER_TOP
	local hipY = groundY + legH
	local torsoCenterY = hipY + torsoH / 2
	local neckY = hipY + torsoH
	local headCenterY = neckY + headD / 2 - headD * 0.05
	local cx, cz = basePos.X, basePos.Z

	-- EnemyCore = unsichtbare Bounding-Box (gross bei Boss wegen Halos + Shards).
	local boxW = math.max(torsoW + 0.8 + (if isBoss then 4.5 else if stage >= 3 then 2.6 else 0.6), headD + 0.8)
	local boxH = totalH + (if isBoss then 3.0 else if stage >= 3 then 1.6 else 0.6)
	local boxD = torsoD + (if isBoss then 3.0 else if stage >= 3 then 1.6 else 0.5)
	local root = makePart(model, "EnemyCore", Vector3.new(boxW, boxH, boxD), Vector3.new(cx, groundY + boxH / 2, cz), bodyBlack, Enum.Material.SmoothPlastic, false)
	root.CanQuery = true
	root.Transparency = 1
	model.PrimaryPart = root

	-- Helper: setzt schmale pinke Glow-Risse auf einem Body-Part.
	local function crackOn(parentPos, parentSize, axis, lengthFrac, offset)
		local crackSize
		if axis == "Y" then
			crackSize = Vector3.new(parentSize.X * 0.12, parentSize.Y * lengthFrac, 0.12)
		elseif axis == "X" then
			crackSize = Vector3.new(parentSize.X * lengthFrac, parentSize.Y * 0.12, 0.12)
		else
			crackSize = Vector3.new(0.12, parentSize.Y * 0.12, parentSize.Z * lengthFrac)
		end
		local crack = makePart(model, "PlasmaCrack", crackSize, parentPos + offset, plasmaPink, Enum.Material.Neon, false)
		crack.Transparency = 0.2
		return crack
	end

	-- ---- Beine ---------------------------------------------------------
	local legSpacing = torsoW * 0.32
	for _, side in ipairs({ -1, 1 }) do
		local leg = makePart(model, "PlasmaLeg", Vector3.new(legW, legH * 0.9, legW), Vector3.new(cx + side * legSpacing, hipY - legH * 0.5, cz), bodyBlack, Enum.Material.SmoothPlastic, false)
		-- Mehrere Glow-Risse pro Bein
		crackOn(leg.Position, leg.Size, "Y", 0.7, Vector3.new(side * legW * 0.3, 0, -legW * 0.5 - 0.02))
		crackOn(leg.Position, leg.Size, "Y", 0.45, Vector3.new(-side * legW * 0.25, legH * 0.1, -legW * 0.5 - 0.02))
		crackOn(leg.Position, leg.Size, "X", 0.6, Vector3.new(0, -legH * 0.2, -legW * 0.5 - 0.02))
		-- Schwerer Stiefel
		makePart(model, "PlasmaBoot", Vector3.new(legW * 1.35, legH * 0.22, legW * 1.45), Vector3.new(cx + side * legSpacing, groundY + legH * 0.11, cz + legW * 0.1), bodyDark, Enum.Material.Metal, false)
	end

	-- ---- Torso ---------------------------------------------------------
	local torso = makePart(model, "PlasmaTorso", Vector3.new(torsoW, torsoH, torsoD), Vector3.new(cx, torsoCenterY, cz), bodyBlack, Enum.Material.SmoothPlastic, false)
	-- Mehrere Risse auf Brust (Linien laufen vom Zentrum nach aussen)
	crackOn(torso.Position, torso.Size, "Y", 0.65, Vector3.new(-torsoW * 0.3, 0, -torsoD * 0.55))
	crackOn(torso.Position, torso.Size, "Y", 0.5, Vector3.new(torsoW * 0.32, torsoH * 0.1, -torsoD * 0.55))
	crackOn(torso.Position, torso.Size, "X", 0.6, Vector3.new(0, -torsoH * 0.28, -torsoD * 0.55))
	crackOn(torso.Position, torso.Size, "X", 0.5, Vector3.new(0, torsoH * 0.32, -torsoD * 0.55))
	-- Armor-Platten Stage 3+ (geometrische Riegel)
	if stage >= 3 then
		for i = 1, 3 do
			local plateY = torsoCenterY - torsoH * 0.35 + (i - 1) * (torsoH * 0.3)
			local plate = makePart(model, "PlasmaArmorPlate", Vector3.new(torsoW * 0.9, torsoH * 0.2, 0.16), Vector3.new(cx, plateY, cz - torsoD / 2 - 0.1), tint(bodyMid, bodyDark, 0.3), Enum.Material.Metal, false)
			-- Pinker Trim
			makePart(model, "PlasmaPlateTrim", Vector3.new(torsoW * 0.85, 0.08, 0.18), Vector3.new(cx, plateY + torsoH * 0.1, cz - torsoD / 2 - 0.12), plasmaPink, Enum.Material.Neon, false).Transparency = 0.3
		end
	end

	-- Chest Plasma-Core (Stage 3+, gross beim Boss)
	if stage >= 3 then
		local coreSize = headD * (0.28 + (stage - 3) * 0.08) + (if isBoss then 0.4 else 0)
		local socket = makePart(model, "PlasmaChestSocket", Vector3.new(coreSize * 1.6, coreSize * 1.6, 0.12), Vector3.new(cx, torsoCenterY - torsoH * 0.05, cz - torsoD / 2 - 0.18), bodyDark, Enum.Material.SmoothPlastic, false)
		local core = makePart(model, "PlasmaChestCore", Vector3.new(coreSize, coreSize, coreSize * 0.6), Vector3.new(cx, torsoCenterY - torsoH * 0.05, cz - torsoD / 2 - 0.24), plasmaCoreGlow, Enum.Material.Neon, false)
		core.Shape = Enum.PartType.Ball
		core.Transparency = 0.05
		local outer = makePart(model, "PlasmaChestCoreOuter", Vector3.new(coreSize * 1.45, coreSize * 1.45, coreSize * 0.4), Vector3.new(cx, torsoCenterY - torsoH * 0.05, cz - torsoD / 2 - 0.14), tint(plasmaPink, Color3.fromRGB(248, 240, 252), 0.3), Enum.Material.Glass, false)
		outer.Shape = Enum.PartType.Ball
		outer.Transparency = 0.5
		local pl = Instance.new("PointLight")
		pl.Brightness = if isBoss then 3.5 else 2
		pl.Range = if isBoss then 26 else 14
		pl.Color = plasmaPink
		pl.Parent = core
	end

	-- ---- Schulterpanzer + Spikes ---------------------------------------
	for _, side in ipairs({ -1, 1 }) do
		local padW = torsoW * 0.32 + (stage - 1) * 0.12 + (if isBoss then 0.6 else 0)
		local padH = torsoH * 0.35 + (stage - 1) * 0.08
		local padX = cx + side * (torsoW * 0.5 + padW * 0.3)
		local padY = torsoCenterY + torsoH * 0.42
		local pad = makePart(model, "PlasmaShoulderPad", Vector3.new(padW, padH, torsoD * 1.15), Vector3.new(padX, padY, cz), bodyMid, Enum.Material.SmoothPlastic, false)
		pad.Orientation = Vector3.new(0, 0, side * -12)
		-- Crystal-Spikes auf den Schultern (Stage 4+, mehr beim Boss)
		if stage >= 4 then
			local spikeCount = 3 + (if isBoss then 4 else 0)
			for k = 1, spikeCount do
				local a = (k - 1) / math.max(1, spikeCount - 1) * math.pi * 0.5 - math.pi * 0.25
				local spikeLen = 1.0 + (if isBoss then 1.0 else 0)
				local sx = padX + side * math.cos(a) * 0.3
				local sy = padY + padH * 0.55 + math.sin(a) * 0.2
				local crystal = makePart(model, "PlasmaCrystalSpike", Vector3.new(0.4, spikeLen, 0.4), Vector3.new(sx + side * 0.3, sy + spikeLen * 0.4, cz), crystalLight, Enum.Material.Glass, false)
				crystal.Orientation = Vector3.new(15, side * (math.deg(a) * 0.6 + 25), side * -30)
				crystal.Transparency = 0.25
				makePart(model, "PlasmaCrystalSpikeTip", Vector3.new(0.44, 0.28, 0.44), Vector3.new(sx + side * 0.5, sy + spikeLen * 0.85, cz), plasmaCoreGlow, Enum.Material.Neon, false)
			end
		end
	end

	-- ---- Arme + Haende -------------------------------------------------
	local armLen = torsoH * 0.95
	local armW = torsoW * 0.22 + (stage - 1) * 0.05
	for _, side in ipairs({ -1, 1 }) do
		local armX = cx + side * (torsoW * 0.55 + armW * 0.3)
		local armY = torsoCenterY - torsoH * 0.05
		local arm = makePart(model, "PlasmaArm", Vector3.new(armW, armLen, armW), Vector3.new(armX, armY, cz), bodyBlack, Enum.Material.SmoothPlastic, false)
		crackOn(arm.Position, arm.Size, "Y", 0.55, Vector3.new(0, 0, -armW * 0.55))
		local handSize = armW * 1.4
		local handY = armY - armLen * 0.5 - handSize * 0.3
		local hand = makePart(model, "PlasmaHand", Vector3.new(handSize, handSize * 0.85, handSize), Vector3.new(armX, handY, cz), bodyBlack, Enum.Material.SmoothPlastic, false)
		hand.Shape = Enum.PartType.Ball
		-- Crystal-Klauen (Stage 3+, leuchtend)
		if stage >= 3 then
			for k = -1, 1 do
				local cxx = armX + k * handSize * 0.32
				local clawLen = handSize * (0.85 + (stage - 3) * 0.25)
				makePart(model, "PlasmaClaw", Vector3.new(0.22, clawLen, 0.22), Vector3.new(cxx, handY - clawLen * 0.5, cz + handSize * 0.1), crystalDark, Enum.Material.Glass, false)
				makePart(model, "PlasmaClawTip", Vector3.new(0.26, 0.22, 0.26), Vector3.new(cxx, handY - clawLen - 0.05, cz + handSize * 0.1), plasmaCoreGlow, Enum.Material.Neon, false)
			end
		end
	end

	-- ---- Kopf: Virus-Sphaere mit Spike-Nubs + INNERER Plasma-Core ------
	local head = makePart(model, "PlasmaHead", Vector3.new(headD, headD, headD), Vector3.new(cx, headCenterY, cz), bodyMid, Enum.Material.SmoothPlastic, false)
	head.Shape = Enum.PartType.Ball
	head.Transparency = 0.15 -- leicht transparent, damit innerer Core schimmert
	-- Tile-Plates auf Kopf-Sphaere fuer kantige Optik
	local tileCount = 14 + stage * 2 + (if isBoss then 4 else 0)
	for i = 1, tileCount do
		local t = i / tileCount
		local theta = i * 2.4
		local phi = math.acos(1 - 2 * t)
		local dir = Vector3.new(math.sin(phi) * math.cos(theta), math.cos(phi), math.sin(phi) * math.sin(theta)).Unit
		local tilePos = Vector3.new(cx, headCenterY, cz) + dir * headD * 0.5
		local tileSize = headD * 0.22
		local tile = makePart(model, "PlasmaHeadTile", Vector3.new(tileSize, tileSize, tileSize * 0.4), tilePos, tint(bodyMid, bodyDark, (i % 3) * 0.2), Enum.Material.SmoothPlastic, false)
		local upv = if math.abs(dir.Y) > 0.95 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
		tile.CFrame = CFrame.lookAt(tilePos, tilePos + dir, upv) * CFrame.Angles(math.rad(90), 0, 0)
	end

	-- Virus-Spike-Nubs (Stalk + runder Knauf) rund um die Sphaere
	local nubCount = 12 + stage * 2 + (if isBoss then 4 else 0)
	for i = 1, nubCount do
		local t = (i + 0.5) / nubCount
		local theta = i * 2.4 + 0.3
		local phi = math.acos(1 - 2 * t)
		local dir = Vector3.new(math.sin(phi) * math.cos(theta), math.cos(phi), math.sin(phi) * math.sin(theta)).Unit
		local stalkLen = headD * 0.22 + (stage - 1) * 0.03
		local stalkCenter = Vector3.new(cx, headCenterY, cz) + dir * (headD * 0.5 + stalkLen * 0.5)
		local stalk = makePart(model, "PlasmaHeadNubStalk", Vector3.new(stalkLen * 0.5, stalkLen, stalkLen * 0.5), stalkCenter, bodyDark, Enum.Material.SmoothPlastic, false)
		local upv = if math.abs(dir.Y) > 0.95 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
		stalk.CFrame = CFrame.lookAt(stalkCenter, stalkCenter + dir, upv) * CFrame.Angles(math.rad(90), 0, 0)
		local knob = makePart(model, "PlasmaHeadNubKnob", Vector3.new(stalkLen * 0.85, stalkLen * 0.85, stalkLen * 0.85), stalkCenter + dir * (stalkLen * 0.55), bodyMid, Enum.Material.SmoothPlastic, false)
		knob.Shape = Enum.PartType.Ball
	end

	-- Innerer Plasma-Core (im Kopf-Zentrum, leuchtet durch).
	local headCore = makePart(model, "PlasmaHeadCore", Vector3.new(headD * 0.55, headD * 0.55, headD * 0.55), Vector3.new(cx, headCenterY, cz), plasmaCoreGlow, Enum.Material.Neon, false)
	headCore.Shape = Enum.PartType.Ball
	headCore.Transparency = 0.05
	local coreLight = Instance.new("PointLight")
	coreLight.Brightness = if isBoss then 5 else 2.5
	coreLight.Range = if isBoss then 30 else 16
	coreLight.Color = plasmaPink
	coreLight.Parent = headCore
	-- "Auge"-Glanz vorne (heller Spot)
	local eyeSpot = makePart(model, "PlasmaHeadEyeSpot", Vector3.new(headD * 0.22, headD * 0.22, 0.16), Vector3.new(cx, headCenterY + headD * 0.02, cz - headD * 0.48), Color3.fromRGB(255, 235, 255), Enum.Material.Neon, false)
	eyeSpot.Shape = Enum.PartType.Ball
	eyeSpot.Transparency = 0.05

	-- ---- Crystal-Krone (Stage 4+, mehr Crystal-Spikes oben am Kopf) ----
	if stage >= 4 then
		local crownCount = 4 + (if isBoss then 6 else 0)
		for i = 1, crownCount do
			local a = (i / crownCount) * math.pi * 2
			local up = 0.85
			local fwd = math.cos(a) * 0.45
			local dir = Vector3.new(fwd, up, math.sin(a) * 0.45).Unit
			local hornLen = headD * 0.5 + (if isBoss then 0.5 else 0)
			local hc = Vector3.new(cx, headCenterY, cz) + dir * headD * 0.55
			local horn = makePart(model, "PlasmaCrystalCrown", Vector3.new(0.4, hornLen, 0.4), hc, crystalLight, Enum.Material.Glass, false)
			horn.Transparency = 0.18
			local upv = if math.abs(dir.Y) > 0.95 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
			horn.CFrame = CFrame.lookAt(hc, hc + dir, upv) * CFrame.Angles(math.rad(90), 0, 0)
			makePart(model, "PlasmaCrystalCrownTip", Vector3.new(0.44, 0.28, 0.44), hc + dir * (hornLen * 0.55), plasmaCoreGlow, Enum.Material.Neon, false)
		end
	end

	-- ---- Halo-Ring um den Kopf (Stage 3+, mehrere beim Boss) ----------
	local function buildHalo(ringRadius, ringY, ringTiltZ, segCount, color)
		for i = 0, segCount - 1 do
			local a = (i / segCount) * math.pi * 2
			local rx = cx + math.cos(a) * ringRadius
			local rz = cz + math.sin(a) * ringRadius * 0.7 -- elliptisch (perspektivischer Look)
			local segPart = makePart(model, "PlasmaHaloSeg", Vector3.new(0.6, 0.32, 0.32), Vector3.new(rx, ringY, rz), color, Enum.Material.Neon, false)
			segPart.Orientation = Vector3.new(0, math.deg(a) + 90, ringTiltZ)
			segPart.Transparency = 0.1
		end
	end
	if stage >= 3 then
		local ringR = headD * 0.95 + (stage - 3) * 0.2
		local ringY = headCenterY + headD * 0.3
		buildHalo(ringR, ringY, 12, 18, plasmaPink)
	end
	if isBoss then
		-- Zwei zusaetzliche Ringe in unterschiedlichen Winkeln (Saturn-Look)
		buildHalo(headD * 1.3, headCenterY + headD * 0.05, -15, 22, plasmaPink)
		buildHalo(headD * 1.1, headCenterY - headD * 0.15, 20, 18, plasmaDeep)
	end

	-- ---- Schwebende Crystal-Shards (Stage 3+) -------------------------
	if stage >= 3 then
		local shardCount = 4 + (stage - 3) * 2 + (if isBoss then 14 else 0)
		for i = 1, shardCount do
			local a = (i / shardCount) * math.pi * 2 + (i * 0.7)
			-- Distanz vom Modell (ausserhalb der Schultern)
			local dist = (if isBoss then 3.0 else 2.0) + math.sin(i * 1.3) * 0.5
			local sx = cx + math.cos(a) * dist
			local sz = cz + math.sin(a) * dist * 0.7
			local sy = torsoCenterY + (math.sin(i * 0.9) - 0.2) * (totalH * 0.4)
			local sLen = 0.55 + (i % 3) * 0.15
			local shard = makePart(model, "PlasmaOrbitShard", Vector3.new(0.32, sLen, 0.32), Vector3.new(sx, sy, sz), crystalLight, Enum.Material.Glass, false)
			shard.Transparency = 0.22
			shard.Orientation = Vector3.new(math.deg(a) * 0.3, math.deg(a), 30 + math.sin(i) * 30)
			-- Kleines Glow am Tip
			makePart(model, "PlasmaOrbitShardTip", Vector3.new(0.36, 0.22, 0.36), Vector3.new(sx, sy + sLen * 0.45, sz), plasmaCoreGlow, Enum.Material.Neon, false).Transparency = 0.1
		end
	end

	-- ---- BOSS Extras: Bodenring + Pad ---------------------------------
	if isBoss then
		local ring = makePart(model, "BossPad", Vector3.new(0.5, totalH * 1.15, totalH * 1.15), Vector3.new(basePos.X, CHAMBER_TOP + 1.25, basePos.Z), plasmaPink, Enum.Material.Neon, false)
		ring.Shape = Enum.PartType.Cylinder
		ring.Orientation = Vector3.new(0, 0, 90)
		ring.Transparency = 0.3
		local floor1 = makePart(model, "BossPlasmaFloorGlow", Vector3.new(0.22, totalH * 1.6, totalH * 1.6), Vector3.new(basePos.X, CHAMBER_TOP + 0.15, basePos.Z), plasmaCoreGlow, Enum.Material.Neon, false)
		floor1.Shape = Enum.PartType.Cylinder
		floor1.Orientation = Vector3.new(0, 0, 90)
		floor1.Transparency = 0.55
		local floor2 = makePart(model, "BossPlasmaFloorOuter", Vector3.new(0.18, totalH * 2.0, totalH * 2.0), Vector3.new(basePos.X, CHAMBER_TOP + 0.08, basePos.Z), plasmaDeep, Enum.Material.Neon, false)
		floor2.Shape = Enum.PartType.Cylinder
		floor2.Orientation = Vector3.new(0, 0, 90)
		floor2.Transparency = 0.72
	end

	-- ---- Aura Partikel (pink Plasma-Sparks) ---------------------------
	local aura = Instance.new("ParticleEmitter")
	aura.Name = "PlasmaAura"
	aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	aura.Color = ColorSequence.new(plasmaCoreGlow, tint(plasmaDeep, bodyBlack, 0.5))
	aura.LightEmission = 0.4
	aura.Rate = if isBoss then 18 else 3 + stage
	aura.Lifetime = NumberRange.new(1.0, 1.8)
	aura.Speed = NumberRange.new(0.4, 1.4)
	aura.Acceleration = Vector3.new(0, 2, 0)
	aura.SpreadAngle = Vector2.new(40, 40)
	aura.Size = NumberSequence.new(0.5, 0.1)
	aura.Parent = torso

	-- ---- Bewegung -----------------------------------------------------
	local arche = ENEMY_ARCHETYPE[def.Shape] or ENEMY_ARCHETYPE.Blob
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
	model:SetAttribute("HomeX", cx)
	model:SetAttribute("HomeY", root.Position.Y)
	model:SetAttribute("HomeZ", cz)
	model:SetAttribute("MoveRangeX", mv.rx)
	model:SetAttribute("MoveRangeZ", mv.rz)
	model:SetAttribute("MoveSpeed", mv.sp)
	model:SetAttribute("BobAmp", mv.bob)
	model:SetAttribute("EnemyKind", "PlasmaCore")

	-- ---- Health-Bar ---------------------------------------------------
	local barScale = if isBoss then 1.9 else 1
	local barY = groundY + totalH + (if isBoss then 3.4 else 1.8)
	local barBack = makePart(model, "HealthBarBack", Vector3.new(13 * barScale, 0.8, 0.4), Vector3.new(cx, barY, cz), Color3.fromRGB(16, 20, 26), Enum.Material.SmoothPlastic, false)
	local barFill = makePart(model, "HealthBarFill", Vector3.new(12.4 * barScale, 0.5, 0.55), Vector3.new(cx, barY + 0.02, cz - 0.06), Color3.fromRGB(95, 255, 125), Enum.Material.Neon, false)
	barFill.Transparency = 0.12
	barFill:SetAttribute("MaxWidth", 12.4 * barScale)
	barFill:SetAttribute("FullCenterX", barFill.Position.X)

	-- ---- AttackClick + Boss-Prompt ------------------------------------
	local clicker = Instance.new("ClickDetector")
	clicker.Name = "AttackClick"
	clicker.MaxActivationDistance = EnemyConfig.AttackDistance
	clicker.Parent = root

	if isBoss then
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

	-- ---- Info-Label ---------------------------------------------------
	local prefix = if isBoss then "★ BOSS ★\n" else ""
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
		if isBoss then 60 else 34,
		UDim2.fromOffset(if isBoss then 280 else 190, if isBoss then 104 else 76),
		Vector3.new(0, boxH / 2 + 3, 0)
	)

	return model
end

-- ---- Cyber Phage Virus-Set fuer Area 7 ----------------------------------
-- Digital/Cyborg-Humanoide mit elektrisch-blauem Glow. Progressive Cyber-
-- Mutation: Stage 1 simpel mit Biohazard -> Stage 2 Visor + Plates ->
-- Stage 3 Brust-Core + erste Kabel -> Stage 4 Cross-Hatch-Core + viele
-- Kabel -> Boss mit massiver Kabel-Wolke + Lightning + grossem Helm.
local function buildCyberPhageCable(parent, startPos, lookForward, length, baseR, segCount, cableColor, glowColor, archDeg)
	-- Wie buildEbolaTentacle, aber Tip ist kleiner Cable-Stecker statt grosses Auge.
	local segLen = length / segCount
	local cf = CFrame.lookAt(startPos, startPos + lookForward)
	local stepAngle = math.rad(archDeg / segCount)
	for i = 1, segCount do
		local t = (i - 0.5) / segCount
		local r = baseR * (1 - t * 0.4) + 0.06
		local segPos = (cf * CFrame.new(0, 0, -segLen / 2)).Position
		local ball = makePart(parent, "CyberCableSeg", Vector3.new(r * 2, r * 2, r * 2), segPos, cableColor, Enum.Material.SmoothPlastic, false)
		ball.Shape = Enum.PartType.Ball
		-- Blauer Glow-Ring alle 3 Segmente
		if i % 3 == 0 then
			local crack = makePart(parent, "CyberCableGlow", Vector3.new(r * 1.3, r * 0.35, r * 1.3), segPos, glowColor, Enum.Material.Neon, false)
			crack.Shape = Enum.PartType.Ball
			crack.Transparency = 0.3
		end
		cf = cf * CFrame.new(0, 0, -segLen) * CFrame.Angles(stepAngle, 0, 0)
	end
	-- Stecker am Tip (kleiner Cyan-Glow + dunkler Cap)
	local tipPos = (cf * CFrame.new(0, 0, -segLen * 0.2)).Position
	local plug = makePart(parent, "CyberCablePlug", Vector3.new(baseR * 1.4, baseR * 0.9, baseR * 1.4), tipPos, cableColor, Enum.Material.Metal, false)
	plug.Shape = Enum.PartType.Cylinder
	local glow = makePart(parent, "CyberCablePlugGlow", Vector3.new(baseR * 1.1, baseR * 1.1, baseR * 1.1), tipPos, glowColor, Enum.Material.Neon, false)
	glow.Shape = Enum.PartType.Ball
	glow.Transparency = 0.15
end

local function buildCyberPhageEnemyModel(parent, def, basePos, primary, secondary)
	local model = Instance.new("Model")
	model.Name = def.Id
	model:SetAttribute("EnemyId", def.Id)
	model:SetAttribute("AreaName", def.AreaName)
	model:SetAttribute("IsBoss", def.IsBoss)
	model.Parent = parent

	local stage = def.EnemyIndex
	local isBoss = def.IsBoss
	local totalHeights = { 5.0, 6.2, 7.4, 8.6, 9.8 }
	local totalH = totalHeights[stage] or 5.0

	local legH = 1.6 + (stage - 1) * 0.45
	local headD = 2.0 + (stage - 1) * 0.30 + (if isBoss then 0.6 else 0)
	local torsoH = totalH - legH - headD * 0.40
	if torsoH < 0.8 then
		torsoH = 0.8
	end
	local torsoW = 1.7 + (stage - 1) * 0.38 + (if isBoss then 1.6 else 0)
	local torsoD = torsoW * 0.6 + (if isBoss then 0.6 else 0)
	local legW = 0.7 + (stage - 1) * 0.12 + (if isBoss then 0.35 else 0)

	-- Cyber Phage-Palette: schwarz + elektrisch blau.
	local bodyBlack = Color3.fromRGB(20, 22, 28)
	local bodyDark = Color3.fromRGB(36, 40, 48)
	local circuitBlue = Color3.fromRGB(75, 195, 255)
	local glowCyan = Color3.fromRGB(140, 230, 255)
	local cableGray = Color3.fromRGB(35, 38, 45)
	local armorMetal = Color3.fromRGB(55, 58, 68)

	local groundY = CHAMBER_TOP
	local hipY = groundY + legH
	local torsoCenterY = hipY + torsoH / 2
	local neckY = hipY + torsoH
	local headCenterY = neckY + headD / 2 - headD * 0.05
	local cx, cz = basePos.X, basePos.Z

	-- EnemyCore = unsichtbare Bounding-Box.
	local boxW = math.max(torsoW + 0.8 + (if isBoss then 4 else if stage >= 3 then 1.8 else 0.6), headD + 0.8)
	local boxH = totalH + (if isBoss then 2.4 else if stage >= 3 then 1.4 else 0.6)
	local boxD = torsoD + (if isBoss then 2.4 else if stage >= 3 then 1.4 else 0.5)
	local root = makePart(model, "EnemyCore", Vector3.new(boxW, boxH, boxD), Vector3.new(cx, groundY + boxH / 2, cz), bodyBlack, Enum.Material.SmoothPlastic, false)
	root.CanQuery = true
	root.Transparency = 1
	model.PrimaryPart = root

	-- Helper: schmale blaue Circuit-Lines auf einem Body-Part.
	local function circuitLine(parentPos, parentSize, axis, lengthFrac, offset)
		local crackSize
		if axis == "Y" then
			crackSize = Vector3.new(parentSize.X * 0.10, parentSize.Y * lengthFrac, 0.10)
		elseif axis == "X" then
			crackSize = Vector3.new(parentSize.X * lengthFrac, parentSize.Y * 0.10, 0.10)
		else
			crackSize = Vector3.new(0.10, parentSize.Y * 0.10, parentSize.Z * lengthFrac)
		end
		local line = makePart(model, "CyberCircuit", crackSize, parentPos + offset, circuitBlue, Enum.Material.Neon, false)
		line.Transparency = 0.18
		return line
	end

	-- ---- Beine ---------------------------------------------------------
	local legSpacing = torsoW * 0.32
	for _, side in ipairs({ -1, 1 }) do
		local leg = makePart(model, "CyberLeg", Vector3.new(legW, legH * 0.9, legW), Vector3.new(cx + side * legSpacing, hipY - legH * 0.5, cz), bodyBlack, Enum.Material.SmoothPlastic, false)
		-- Circuit-Lines
		circuitLine(leg.Position, leg.Size, "Y", 0.65, Vector3.new(side * legW * 0.3, 0, -legW * 0.5 - 0.02))
		circuitLine(leg.Position, leg.Size, "X", 0.55, Vector3.new(0, legH * 0.15, -legW * 0.5 - 0.02))
		circuitLine(leg.Position, leg.Size, "X", 0.55, Vector3.new(0, -legH * 0.15, -legW * 0.5 - 0.02))
		makePart(model, "CyberBoot", Vector3.new(legW * 1.35, legH * 0.22, legW * 1.45), Vector3.new(cx + side * legSpacing, groundY + legH * 0.11, cz + legW * 0.1), armorMetal, Enum.Material.Metal, false)
		-- Knie-Plate ab Stage 3
		if stage >= 3 then
			makePart(model, "CyberKneePlate", Vector3.new(legW * 1.05, legH * 0.22, legW * 0.7), Vector3.new(cx + side * legSpacing, hipY - legH * 0.45, cz - legW * 0.35), armorMetal, Enum.Material.Metal, false)
		end
	end

	-- ---- Torso ---------------------------------------------------------
	local torso = makePart(model, "CyberTorso", Vector3.new(torsoW, torsoH, torsoD), Vector3.new(cx, torsoCenterY, cz), bodyBlack, Enum.Material.SmoothPlastic, false)
	-- Circuit-Lines auf der Brust (vertikal + horizontal -> Tech-Pattern)
	circuitLine(torso.Position, torso.Size, "Y", 0.7, Vector3.new(-torsoW * 0.3, 0, -torsoD * 0.55))
	circuitLine(torso.Position, torso.Size, "Y", 0.6, Vector3.new(torsoW * 0.32, torsoH * 0.05, -torsoD * 0.55))
	circuitLine(torso.Position, torso.Size, "X", 0.65, Vector3.new(0, -torsoH * 0.32, -torsoD * 0.55))
	circuitLine(torso.Position, torso.Size, "X", 0.5, Vector3.new(0, torsoH * 0.34, -torsoD * 0.55))
	-- Cyber-Armorplates Stage 2+ (kleine Plate-Streifen mit Glow-Trim)
	if stage >= 2 then
		for _, side in ipairs({ -1, 1 }) do
			local platePos = Vector3.new(cx + side * torsoW * 0.32, torsoCenterY + torsoH * 0.1, cz - torsoD / 2 - 0.1)
			local plate = makePart(model, "CyberSidePlate", Vector3.new(torsoW * 0.25, torsoH * 0.55, 0.16), platePos, bodyDark, Enum.Material.Metal, false)
			-- Trim
			makePart(model, "CyberSidePlateTrim", Vector3.new(0.08, torsoH * 0.5, 0.18), platePos + Vector3.new(side * torsoW * 0.1, 0, -0.04), circuitBlue, Enum.Material.Neon, false).Transparency = 0.25
		end
	end
	-- Schwere Brustplatte Stage 4+ (umrahmt den Core)
	if stage >= 4 then
		makePart(model, "CyberChestArmor", Vector3.new(torsoW * 0.85, torsoH * 0.7, 0.18), Vector3.new(cx, torsoCenterY - torsoH * 0.05, cz - torsoD / 2 - 0.12), bodyDark, Enum.Material.Metal, false)
	end

	-- ---- Biohazard-Symbol auf der Brust (alle Stages, glowt cyan) -----
	local hazSize = torsoW * (if isBoss then 0.45 else 0.38)
	local hazY = torsoCenterY + (if stage <= 2 then torsoH * 0.08 else torsoH * 0.18)
	makePart(model, "CyberHazardBacking", Vector3.new(hazSize * 1.18, hazSize * 1.18, 0.05), Vector3.new(cx, hazY, cz - torsoD / 2 - 0.16), bodyBlack, Enum.Material.SmoothPlastic, false)
	local hazard = makePart(model, "CyberHazard", Vector3.new(hazSize, hazSize, 0.06), Vector3.new(cx, hazY, cz - torsoD / 2 - 0.2), circuitBlue, Enum.Material.Neon, false)
	hazard.Transparency = 0.05
	local hazLight = Instance.new("PointLight")
	hazLight.Brightness = if isBoss then 2.6 else 1.2
	hazLight.Range = if isBoss then 18 else 10
	hazLight.Color = glowCyan
	hazLight.Parent = hazard

	-- ---- Chest Cyan-Core (Stage 3+) -----------------------------------
	if stage >= 3 then
		local coreSize = headD * (0.30 + (stage - 3) * 0.06) + (if isBoss then 0.35 else 0)
		local coreY = torsoCenterY - torsoH * 0.15
		local core = makePart(model, "CyberChestCore", Vector3.new(coreSize, coreSize, coreSize * 0.55), Vector3.new(cx, coreY, cz - torsoD / 2 - 0.24), glowCyan, Enum.Material.Neon, false)
		core.Shape = Enum.PartType.Ball
		core.Transparency = 0.05
		local outer = makePart(model, "CyberChestCoreOuter", Vector3.new(coreSize * 1.45, coreSize * 1.45, coreSize * 0.4), Vector3.new(cx, coreY, cz - torsoD / 2 - 0.14), tint(glowCyan, Color3.fromRGB(240, 250, 255), 0.35), Enum.Material.Glass, false)
		outer.Shape = Enum.PartType.Ball
		outer.Transparency = 0.5
		local pl = Instance.new("PointLight")
		pl.Brightness = if isBoss then 3.5 else 2
		pl.Range = if isBoss then 26 else 14
		pl.Color = glowCyan
		pl.Parent = core
		-- Cross-Hatch um den Core (Stage 4+, Quadrat-Rahmen aus 4 Neon-Linien)
		if stage >= 4 then
			for _, off in ipairs({
				Vector3.new(0, coreSize * 0.95, 0),
				Vector3.new(0, -coreSize * 0.95, 0),
				Vector3.new(coreSize * 0.95, 0, 0),
				Vector3.new(-coreSize * 0.95, 0, 0),
			}) do
				local horizontal = math.abs(off.X) > 0
				local lineSize = if horizontal then Vector3.new(0.1, coreSize * 1.8, 0.16) else Vector3.new(coreSize * 1.8, 0.1, 0.16)
				makePart(model, "CyberCoreHatch", lineSize, Vector3.new(cx, coreY, cz - torsoD / 2 - 0.18) + off, circuitBlue, Enum.Material.Neon, false).Transparency = 0.2
			end
		end
	end

	-- ---- Schulterpads --------------------------------------------------
	for _, side in ipairs({ -1, 1 }) do
		local padW = torsoW * 0.32 + (stage - 1) * 0.12 + (if isBoss then 0.6 else 0)
		local padH = torsoH * 0.38 + (stage - 1) * 0.08
		local padX = cx + side * (torsoW * 0.5 + padW * 0.3)
		local padY = torsoCenterY + torsoH * 0.42
		local pad = makePart(model, "CyberShoulderPad", Vector3.new(padW, padH, torsoD * 1.15), Vector3.new(padX, padY, cz), bodyDark, Enum.Material.Metal, false)
		pad.Orientation = Vector3.new(0, 0, side * -12)
		-- Glow-Trim
		makePart(model, "CyberShoulderTrim", Vector3.new(padW * 1.05, 0.1, torsoD * 1.18), Vector3.new(padX, padY + padH * 0.35, cz), circuitBlue, Enum.Material.Neon, false).Transparency = 0.25
	end

	-- ---- Arme + Haende -------------------------------------------------
	local armLen = torsoH * 0.95
	local armW = torsoW * 0.22 + (stage - 1) * 0.05
	for _, side in ipairs({ -1, 1 }) do
		local armX = cx + side * (torsoW * 0.55 + armW * 0.3)
		local armY = torsoCenterY - torsoH * 0.05
		local arm = makePart(model, "CyberArm", Vector3.new(armW, armLen, armW), Vector3.new(armX, armY, cz), bodyBlack, Enum.Material.SmoothPlastic, false)
		circuitLine(arm.Position, arm.Size, "Y", 0.55, Vector3.new(0, 0, -armW * 0.55))
		local handSize = armW * 1.4
		local handY = armY - armLen * 0.5 - handSize * 0.3
		local hand = makePart(model, "CyberHand", Vector3.new(handSize, handSize * 0.85, handSize), Vector3.new(armX, handY, cz), bodyDark, Enum.Material.Metal, false)
		hand.Shape = Enum.PartType.Ball
		-- Hand-Glow Stage 4+ (Energie-Aufladung)
		if stage >= 4 then
			local energy = makePart(model, "CyberHandEnergy", Vector3.new(handSize * 1.25, handSize * 1.25, handSize * 1.25), Vector3.new(armX, handY, cz), glowCyan, Enum.Material.Neon, false)
			energy.Shape = Enum.PartType.Ball
			energy.Transparency = 0.55
			local pl = Instance.new("PointLight")
			pl.Brightness = 1.4
			pl.Range = 8
			pl.Color = glowCyan
			pl.Parent = energy
		end
	end

	-- ---- Kopf: Cyber-Spikeprotein-Sphaere + Helm/Visor ----------------
	local head = makePart(model, "CyberHead", Vector3.new(headD, headD, headD), Vector3.new(cx, headCenterY, cz), bodyBlack, Enum.Material.SmoothPlastic, false)
	head.Shape = Enum.PartType.Ball
	-- Tile-Plates auf der Sphaere
	local tileCount = 12 + stage * 2 + (if isBoss then 4 else 0)
	for i = 1, tileCount do
		local t = i / tileCount
		local theta = i * 2.4
		local phi = math.acos(1 - 2 * t)
		local dir = Vector3.new(math.sin(phi) * math.cos(theta), math.cos(phi), math.sin(phi) * math.sin(theta)).Unit
		local tilePos = Vector3.new(cx, headCenterY, cz) + dir * headD * 0.5
		local tileSize = headD * 0.22
		local tile = makePart(model, "CyberHeadTile", Vector3.new(tileSize, tileSize, tileSize * 0.4), tilePos, tint(bodyDark, bodyBlack, (i % 3) * 0.3), Enum.Material.Metal, false)
		local upv = if math.abs(dir.Y) > 0.95 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
		tile.CFrame = CFrame.lookAt(tilePos, tilePos + dir, upv) * CFrame.Angles(math.rad(90), 0, 0)
	end
	-- Metallspikes auf oberer Hemisphaere (Spike-Protein-Look)
	local spikeCount = 6 + stage * 2 + (if isBoss then 8 else 0)
	local spikeLen = headD * 0.42 + (stage - 1) * 0.07
	for i = 1, spikeCount do
		local a = (i / spikeCount) * math.pi * 2
		local up = 0.65 + math.abs(math.sin(i * 0.9)) * 0.35
		local fwd = math.cos(a) * 0.55
		local dir = Vector3.new(fwd, up, math.sin(a) * 0.55).Unit
		local sc = Vector3.new(cx, headCenterY, cz) + dir * headD * 0.52
		local spike = makePart(model, "CyberHeadSpike", Vector3.new(0.32, spikeLen, 0.32), sc, armorMetal, Enum.Material.Metal, false)
		local upv = if math.abs(dir.Y) > 0.95 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
		spike.CFrame = CFrame.lookAt(sc, sc + dir, upv) * CFrame.Angles(math.rad(90), 0, 0)
		makePart(model, "CyberHeadSpikeTip", Vector3.new(0.36, 0.22, 0.36), sc + dir * (spikeLen * 0.55), bodyBlack, Enum.Material.Metal, false)
	end

	-- ---- Gesicht: Augen oder Visor ------------------------------------
	if stage == 1 then
		-- 2 simple Glow-Slits
		for _, side in ipairs({ -1, 1 }) do
			local eye = makePart(model, "CyberEye", Vector3.new(headD * 0.18, headD * 0.10, 0.12), Vector3.new(cx + side * headD * 0.18, headCenterY + headD * 0.05, cz - headD * 0.48), glowCyan, Enum.Material.Neon, false)
			eye.Transparency = 0.05
			eye.Orientation = Vector3.new(0, 0, side * -22)
		end
	else
		-- Visor: horizontaler Glow-Streifen quer ueber das Gesicht
		local visorBacking = makePart(model, "CyberVisorBacking", Vector3.new(headD * 0.85, headD * 0.28, 0.12), Vector3.new(cx, headCenterY + headD * 0.05, cz - headD * 0.46), bodyBlack, Enum.Material.SmoothPlastic, false)
		local visor = makePart(model, "CyberVisor", Vector3.new(headD * 0.78, headD * 0.18, 0.14), Vector3.new(cx, headCenterY + headD * 0.05, cz - headD * 0.5), glowCyan, Enum.Material.Neon, false)
		visor.Transparency = 0.05
		-- X-Pattern (Slasher-Augen ueber dem Visor, Stage 4+)
		if stage >= 4 then
			for _, dir in ipairs({ -1, 1 }) do
				makePart(model, "CyberVisorXMark", Vector3.new(headD * 0.06, headD * 0.16, 0.18), Vector3.new(cx + dir * headD * 0.2, headCenterY + headD * 0.05, cz - headD * 0.51), bodyBlack, Enum.Material.SmoothPlastic, false).Orientation = Vector3.new(0, 0, dir * 25)
			end
		end
		local pl = Instance.new("PointLight")
		pl.Brightness = if isBoss then 2.2 else 1.1
		pl.Range = if isBoss then 16 else 9
		pl.Color = glowCyan
		pl.Parent = visor
	end

	-- ---- Helm-Hoerner (Stage 3+, boss bigger) -------------------------
	if stage >= 3 then
		local hornCount = 2 + (if isBoss then 4 else (stage - 3))
		for i = 1, hornCount do
			local a = (i - 0.5) / hornCount * math.pi - math.pi * 0.5
			local up = 0.85
			local fwd = math.cos(a) * 0.4
			local dir = Vector3.new(fwd, up, math.sin(a) * 0.3 - 0.1).Unit
			local hornLen = headD * 0.45 + (if isBoss then 0.5 else 0)
			local hc = Vector3.new(cx, headCenterY, cz) + dir * headD * 0.5
			local horn = makePart(model, "CyberHelmHorn", Vector3.new(0.36, hornLen, 0.36), hc, armorMetal, Enum.Material.Metal, false)
			local upv = if math.abs(dir.Y) > 0.95 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
			horn.CFrame = CFrame.lookAt(hc, hc + dir, upv) * CFrame.Angles(math.rad(90), 0, 0)
			makePart(model, "CyberHelmHornTip", Vector3.new(0.4, 0.25, 0.4), hc + dir * (hornLen * 0.55), circuitBlue, Enum.Material.Neon, false).Transparency = 0.1
		end
	end

	-- ---- Cable-Tubes (Stage 3+, viele beim Boss) ----------------------
	if stage >= 3 then
		local cableConfigs = {}
		if stage == 3 then
			-- 2 Kabel von Schulter zu Kopf
			for _, side in ipairs({ -1, 1 }) do
				table.insert(cableConfigs, { startPos = Vector3.new(cx + side * torsoW * 0.4, neckY + 0.1, cz + torsoD * 0.3), dir = Vector3.new(-side * 0.3, 0.7, 0.5).Unit, length = totalH * 0.45, baseR = 0.22, segs = 6, arch = -60 })
			end
		elseif stage == 4 then
			-- 4-6 Kabel
			for _, side in ipairs({ -1, 1 }) do
				table.insert(cableConfigs, { startPos = Vector3.new(cx + side * torsoW * 0.4, neckY + 0.1, cz + torsoD * 0.3), dir = Vector3.new(-side * 0.3, 0.7, 0.5).Unit, length = totalH * 0.5, baseR = 0.24, segs = 7, arch = -70 })
				table.insert(cableConfigs, { startPos = Vector3.new(cx + side * torsoW * 0.5, torsoCenterY + torsoH * 0.4, cz + torsoD * 0.4), dir = Vector3.new(side * 0.4, 0.6, 0.6).Unit, length = totalH * 0.4, baseR = 0.22, segs = 6, arch = 80 })
			end
		else -- Boss
			-- 10 Kabel in alle Richtungen (Tentakel-Wolke)
			for k = 1, 10 do
				local angle = (k - 5.5) / 9 * math.rad(160)
				local dir = Vector3.new(math.sin(angle), 0.7 + math.cos(angle * 0.5) * 0.3, math.cos(angle) * 0.4 + 0.4).Unit
				local startX = cx + math.sin(angle) * torsoW * 0.45
				local startY = neckY + 0.1 + math.cos(angle * 0.7) * 0.4
				local startZ = cz + torsoD * 0.35
				table.insert(cableConfigs, { startPos = Vector3.new(startX, startY, startZ), dir = dir, length = totalH * (0.7 + math.cos(angle) * 0.15), baseR = 0.28, segs = 10, arch = -90 + math.abs(angle) * 30 })
			end
		end
		for _, c in ipairs(cableConfigs) do
			buildCyberPhageCable(model, c.startPos, c.dir, c.length, c.baseR, c.segs, cableGray, glowCyan, c.arch)
		end
	end

	-- ---- BOSS Extras: Lightning + BossPad -----------------------------
	if isBoss then
		-- Lightning-Bolt-Parts seitlich (Zickzack-Glow)
		for _, side in ipairs({ -1, 1 }) do
			local startX = cx + side * (torsoW * 0.5 + 0.6)
			local startY = torsoCenterY + torsoH * 0.3
			local prevX, prevY = startX, startY
			for k = 1, 5 do
				local nextX = prevX + side * (0.5 + math.sin(k * 1.3) * 0.4)
				local nextY = prevY - (0.6 + math.cos(k * 0.9) * 0.3)
				local mx = (prevX + nextX) / 2
				local my = (prevY + nextY) / 2
				local len = math.sqrt((nextX - prevX) ^ 2 + (nextY - prevY) ^ 2)
				local bolt = makePart(model, "BossCyberLightning", Vector3.new(0.18, len, 0.18), Vector3.new(mx, my, cz + 0.4), circuitBlue, Enum.Material.Neon, false)
				bolt.CFrame = CFrame.new(mx, my, cz + 0.4) * CFrame.Angles(0, 0, math.atan2(nextX - prevX, nextY - prevY))
				bolt.Transparency = 0.2
				prevX, prevY = nextX, nextY
			end
		end
		-- BossPad
		local ring = makePart(model, "BossPad", Vector3.new(0.5, totalH * 1.15, totalH * 1.15), Vector3.new(basePos.X, CHAMBER_TOP + 1.25, basePos.Z), circuitBlue, Enum.Material.Neon, false)
		ring.Shape = Enum.PartType.Cylinder
		ring.Orientation = Vector3.new(0, 0, 90)
		ring.Transparency = 0.3
		-- Doppelter Bodenring
		local floor1 = makePart(model, "BossCyberFloorGlow", Vector3.new(0.22, totalH * 1.6, totalH * 1.6), Vector3.new(basePos.X, CHAMBER_TOP + 0.15, basePos.Z), glowCyan, Enum.Material.Neon, false)
		floor1.Shape = Enum.PartType.Cylinder
		floor1.Orientation = Vector3.new(0, 0, 90)
		floor1.Transparency = 0.55
		local floor2 = makePart(model, "BossCyberFloorOuter", Vector3.new(0.18, totalH * 2.0, totalH * 2.0), Vector3.new(basePos.X, CHAMBER_TOP + 0.08, basePos.Z), circuitBlue, Enum.Material.Neon, false)
		floor2.Shape = Enum.PartType.Cylinder
		floor2.Orientation = Vector3.new(0, 0, 90)
		floor2.Transparency = 0.72
	end

	-- ---- Digital-Spark-Partikel ---------------------------------------
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "CyberSparks"
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(glowCyan, tint(circuitBlue, bodyBlack, 0.5))
	sparks.LightEmission = 0.4
	sparks.Rate = if isBoss then 18 else 2 + stage
	sparks.Lifetime = NumberRange.new(0.8, 1.6)
	sparks.Speed = NumberRange.new(0.4, 1.4)
	sparks.Acceleration = Vector3.new(0, 1.4, 0)
	sparks.SpreadAngle = Vector2.new(40, 40)
	sparks.Size = NumberSequence.new(0.4, 0.08)
	sparks.Parent = torso

	-- ---- Bewegung -----------------------------------------------------
	local arche = ENEMY_ARCHETYPE[def.Shape] or ENEMY_ARCHETYPE.Blob
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
	model:SetAttribute("HomeX", cx)
	model:SetAttribute("HomeY", root.Position.Y)
	model:SetAttribute("HomeZ", cz)
	model:SetAttribute("MoveRangeX", mv.rx)
	model:SetAttribute("MoveRangeZ", mv.rz)
	model:SetAttribute("MoveSpeed", mv.sp)
	model:SetAttribute("BobAmp", mv.bob)
	model:SetAttribute("EnemyKind", "CyberPhage")

	-- ---- Health-Bar ---------------------------------------------------
	local barScale = if isBoss then 1.9 else 1
	local barY = groundY + totalH + (if isBoss then 3.2 else 1.8)
	local barBack = makePart(model, "HealthBarBack", Vector3.new(13 * barScale, 0.8, 0.4), Vector3.new(cx, barY, cz), Color3.fromRGB(16, 20, 26), Enum.Material.SmoothPlastic, false)
	local barFill = makePart(model, "HealthBarFill", Vector3.new(12.4 * barScale, 0.5, 0.55), Vector3.new(cx, barY + 0.02, cz - 0.06), Color3.fromRGB(95, 255, 125), Enum.Material.Neon, false)
	barFill.Transparency = 0.12
	barFill:SetAttribute("MaxWidth", 12.4 * barScale)
	barFill:SetAttribute("FullCenterX", barFill.Position.X)

	-- ---- AttackClick + Boss-Prompt ------------------------------------
	local clicker = Instance.new("ClickDetector")
	clicker.Name = "AttackClick"
	clicker.MaxActivationDistance = EnemyConfig.AttackDistance
	clicker.Parent = root

	if isBoss then
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

	-- ---- Info-Label ---------------------------------------------------
	local prefix = if isBoss then "★ BOSS ★\n" else ""
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
		if isBoss then 60 else 34,
		UDim2.fromOffset(if isBoss then 280 else 190, if isBoss then 104 else 76),
		Vector3.new(0, boxH / 2 + 3, 0)
	)

	return model
end

-- ---- Coronavirus-Set fuer Area 8 ----------------------------------------
-- Klassische Corona-Optik mit roten Knob-Spikes. Stages 1-3 olive Soldaten
-- mit gelbem Biohazard + gruene Reagenz-Kanister. Stage 4 und Boss mutieren
-- zu dunkellila Mech-Form mit lila Glow.
local function buildCoronavirusEnemyModel(parent, def, basePos, primary, secondary)
	local model = Instance.new("Model")
	model.Name = def.Id
	model:SetAttribute("EnemyId", def.Id)
	model:SetAttribute("AreaName", def.AreaName)
	model:SetAttribute("IsBoss", def.IsBoss)
	model.Parent = parent

	local stage = def.EnemyIndex
	local isBoss = def.IsBoss
	local totalHeights = { 5.0, 6.2, 7.4, 8.6, 9.8 }
	local totalH = totalHeights[stage] or 5.0

	local legH = 1.6 + (stage - 1) * 0.45
	local headD = 2.0 + (stage - 1) * 0.30 + (if isBoss then 0.6 else 0)
	local torsoH = totalH - legH - headD * 0.40
	if torsoH < 0.8 then
		torsoH = 0.8
	end
	local torsoW = 1.7 + (stage - 1) * 0.38 + (if isBoss then 1.6 else 0)
	local torsoD = torsoW * 0.6 + (if isBoss then 0.6 else 0)
	local legW = 0.7 + (stage - 1) * 0.12 + (if isBoss then 0.35 else 0)

	-- Mutationsschwelle: Stage 1-3 = oliv-gruen, Stage 4-5 = dunkellila.
	local mutated = stage >= 4
	local bodyOlive = Color3.fromRGB(118, 130, 76)
	local bodyOliveDeep = Color3.fromRGB(78, 94, 50)
	local bodyPurple = Color3.fromRGB(58, 32, 78)
	local bodyPurpleDeep = Color3.fromRGB(38, 18, 52)
	local bodyColor = if mutated then bodyPurple else bodyOlive
	local bodyDark = if mutated then bodyPurpleDeep else bodyOliveDeep
	local headOlive = Color3.fromRGB(124, 138, 72)
	local headPurple = Color3.fromRGB(70, 38, 96)
	local headColor = if mutated then headPurple else headOlive
	local spikeRed = Color3.fromRGB(190, 50, 50)
	local spikeRedDeep = Color3.fromRGB(140, 32, 32)
	local greenGlow = Color3.fromRGB(140, 230, 90)
	local purpleGlow = Color3.fromRGB(210, 95, 248)
	local glowColor = if mutated then purpleGlow else greenGlow
	local hazardYellow = Color3.fromRGB(218, 200, 78)
	local hazardPurple = Color3.fromRGB(220, 100, 248)
	local hazardColor = if mutated then hazardPurple else hazardYellow
	local armorMetal = Color3.fromRGB(48, 42, 38)
	local maskColor = Color3.fromRGB(34, 30, 32)
	local canisterFluid = if mutated then purpleGlow else greenGlow

	local groundY = CHAMBER_TOP
	local hipY = groundY + legH
	local torsoCenterY = hipY + torsoH / 2
	local neckY = hipY + torsoH
	local headCenterY = neckY + headD / 2 - headD * 0.05
	local cx, cz = basePos.X, basePos.Z

	-- EnemyCore = unsichtbare Bounding-Box.
	local boxW = math.max(torsoW + 0.8 + (if isBoss then 3 else if stage >= 2 then 1.6 else 0.5), headD + 0.8)
	local boxH = totalH + (if isBoss then 2.0 else 0.8)
	local boxD = torsoD + (if isBoss then 2.2 else if stage >= 2 then 1.4 else 0.4)
	local root = makePart(model, "EnemyCore", Vector3.new(boxW, boxH, boxD), Vector3.new(cx, groundY + boxH / 2, cz), bodyColor, Enum.Material.SmoothPlastic, false)
	root.CanQuery = true
	root.Transparency = 1
	model.PrimaryPart = root

	-- ---- Beine ---------------------------------------------------------
	local legSpacing = torsoW * 0.32
	for _, side in ipairs({ -1, 1 }) do
		local legColor = if stage >= 3 then bodyDark else bodyColor
		makePart(model, "CoronaLeg", Vector3.new(legW, legH * 0.9, legW), Vector3.new(cx + side * legSpacing, hipY - legH * 0.5, cz), legColor, Enum.Material.SmoothPlastic, false)
		makePart(model, "CoronaBoot", Vector3.new(legW * 1.3, legH * 0.22, legW * 1.4), Vector3.new(cx + side * legSpacing, groundY + legH * 0.11, cz + legW * 0.1), armorMetal, Enum.Material.Metal, false)
		-- Knee armor ab Stage 3
		if stage >= 3 then
			makePart(model, "CoronaKneePlate", Vector3.new(legW * 1.05, legH * 0.22, legW * 0.7), Vector3.new(cx + side * legSpacing, hipY - legH * 0.45, cz - legW * 0.35), armorMetal, Enum.Material.Metal, false)
		end
		-- Rote Mutations-Flecken auf Beinen (Stage 1-3)
		if stage <= 3 then
			for k = 1, 2 do
				local seed = side * 11 + k * 1.8
				local px = cx + side * legSpacing + math.sin(seed) * legW * 0.3
				local py = hipY - legH * (0.3 + (k - 1) * 0.4)
				makePart(model, "CoronaSpot", Vector3.new(legW * 0.45, legH * 0.18, 0.1), Vector3.new(px, py, cz - legW * 0.5 - 0.04), spikeRedDeep, Enum.Material.SmoothPlastic, false).Transparency = 0.1
			end
		end
	end

	-- ---- Torso ---------------------------------------------------------
	local torsoColor = if stage >= 3 then bodyDark else bodyColor
	local torso = makePart(model, "CoronaTorso", Vector3.new(torsoW, torsoH, torsoD), Vector3.new(cx, torsoCenterY, cz), torsoColor, Enum.Material.SmoothPlastic, false)
	-- Rote Mutations-Spots ueberall (Stage 1-3)
	if stage <= 3 then
		for i = 1, 4 + stage do
			local seed = i * 2.3
			local px = math.sin(seed) * 0.4 * torsoW
			local py = math.cos(seed * 1.1) * 0.4 * torsoH
			local spotSize = torsoW * 0.13
			local spot = makePart(model, "CoronaTorsoSpot", Vector3.new(spotSize, spotSize, 0.08), Vector3.new(cx + px, torsoCenterY + py, cz - torsoD / 2 - 0.05), spikeRedDeep, Enum.Material.SmoothPlastic, false)
			spot.Transparency = 0.1
		end
	end
	-- Schwere Brustpanzerung Stage 3+
	if stage >= 3 then
		local plate = makePart(model, "CoronaChestPlate", Vector3.new(torsoW * 0.92, torsoH * 0.85, 0.18), Vector3.new(cx, torsoCenterY, cz - torsoD / 2 - 0.1), bodyDark, Enum.Material.Metal, false)
		-- Hazard-Stripe-Trim oben/unten
		if stage >= 3 then
			makePart(model, "CoronaHazardStripeTop", Vector3.new(torsoW * 0.9, 0.15, 0.18), Vector3.new(cx, torsoCenterY + torsoH * 0.4, cz - torsoD / 2 - 0.13), hazardYellow, Enum.Material.SmoothPlastic, false).Transparency = 0.25
			makePart(model, "CoronaHazardStripeBottom", Vector3.new(torsoW * 0.9, 0.15, 0.18), Vector3.new(cx, torsoCenterY - torsoH * 0.4, cz - torsoD / 2 - 0.13), hazardYellow, Enum.Material.SmoothPlastic, false).Transparency = 0.25
		end
	end

	-- ---- Biohazard auf der Brust (gross) -------------------------------
	local hazSize = torsoW * 0.42 + (if isBoss then 0.5 else 0)
	local hazY = torsoCenterY + torsoH * 0.05
	local hazardMat = if mutated then Enum.Material.Neon else Enum.Material.SmoothPlastic
	makePart(model, "CoronaHazardBacking", Vector3.new(hazSize * 1.18, hazSize * 1.18, 0.05), Vector3.new(cx, hazY, cz - torsoD / 2 - 0.16), bodyDark, Enum.Material.SmoothPlastic, false)
	local hazard = makePart(model, "CoronaHazard", Vector3.new(hazSize, hazSize, 0.06), Vector3.new(cx, hazY, cz - torsoD / 2 - 0.22), hazardColor, hazardMat, false)
	hazard.Transparency = if mutated then 0.05 else 0.1
	if mutated then
		local pl = Instance.new("PointLight")
		pl.Brightness = if isBoss then 2.6 else 1.4
		pl.Range = if isBoss then 20 else 12
		pl.Color = purpleGlow
		pl.Parent = hazard
	end

	-- ---- Schulterpads --------------------------------------------------
	for _, side in ipairs({ -1, 1 }) do
		local padW = torsoW * 0.32 + (stage - 1) * 0.12 + (if isBoss then 0.6 else 0)
		local padH = torsoH * 0.38 + (stage - 1) * 0.08
		local padX = cx + side * (torsoW * 0.5 + padW * 0.3)
		local padY = torsoCenterY + torsoH * 0.42
		local padColor = if stage >= 3 then armorMetal else bodyColor
		local pad = makePart(model, "CoronaShoulderPad", Vector3.new(padW, padH, torsoD * 1.15), Vector3.new(padX, padY, cz), padColor, Enum.Material.Metal, false)
		pad.Orientation = Vector3.new(0, 0, side * -12)
		-- Schulter-Spike beim Boss
		if isBoss then
			makePart(model, "CoronaShoulderSpike", Vector3.new(0.42, 1.2, 0.42), Vector3.new(padX, padY + padH * 0.6, cz), armorMetal, Enum.Material.Metal, false)
		end
	end

	-- ---- Rucksack-Kanister (Stage 2+) ---------------------------------
	if stage >= 2 then
		local backW = torsoW * 0.85
		local backH = torsoH * 0.78
		local backD = 0.55 + (stage - 2) * 0.15 + (if isBoss then 0.55 else 0)
		local backX = cx
		local backY = torsoCenterY + torsoH * 0.05
		local backZ = cz + torsoD / 2 + backD * 0.5
		makePart(model, "CoronaBackpack", Vector3.new(backW, backH, backD), Vector3.new(backX, backY, backZ), armorMetal, Enum.Material.Metal, false)
		-- Kanister auf beiden Seiten (sichtbar von Seite/Front)
		local canisterCount = if isBoss then 6 elseif stage == 2 then 2 elseif stage == 3 then 4 else 4
		local canisterR = 0.36 + (stage - 2) * 0.04 + (if isBoss then 0.08 else 0)
		local canisterH = totalH * 0.32 + (stage - 2) * 0.1 + (if isBoss then 0.5 else 0)
		for i = 1, canisterCount do
			local side = (if i % 2 == 0 then 1 else -1)
			local kIdx = math.ceil(i / 2)
			local tx = backX + side * (torsoW * 0.42 + canisterR * 0.5)
			local ty = backY + (kIdx - 1) * (canisterH * 0.55 - 0.2) + (if isBoss then 0.4 else 0)
			local tz = backZ + (kIdx % 2) * 0.15
			-- Glas-Aussenhuelle
			local tank = makePart(model, "CoronaCanister", Vector3.new(canisterR * 2, canisterH, canisterR * 2), Vector3.new(tx, ty, tz), tint(canisterFluid, Color3.fromRGB(245, 250, 240), 0.3), Enum.Material.Glass, false)
			tank.Shape = Enum.PartType.Cylinder
			tank.Orientation = Vector3.new(0, 0, 90)
			tank.Transparency = 0.35
			-- Neon-Innenfluessigkeit
			local fluid = makePart(model, "CoronaCanisterFluid", Vector3.new(canisterR * 1.7, canisterH * 0.9, canisterR * 1.7), Vector3.new(tx, ty, tz), canisterFluid, Enum.Material.Neon, false)
			fluid.Shape = Enum.PartType.Cylinder
			fluid.Orientation = Vector3.new(0, 0, 90)
			fluid.Transparency = 0.15
			-- Kappen oben/unten
			makePart(model, "CoronaCanisterCap", Vector3.new(0.25, canisterR * 2.2, canisterR * 2.2), Vector3.new(tx, ty + canisterH * 0.5, tz), maskColor, Enum.Material.Metal, false).Shape = Enum.PartType.Cylinder
			makePart(model, "CoronaCanisterCap", Vector3.new(0.25, canisterR * 2.2, canisterR * 2.2), Vector3.new(tx, ty - canisterH * 0.5, tz), maskColor, Enum.Material.Metal, false).Shape = Enum.PartType.Cylinder
			-- PointLight
			local pl = Instance.new("PointLight")
			pl.Brightness = 0.8
			pl.Range = 8
			pl.Color = canisterFluid
			pl.Parent = fluid
		end
	end

	-- ---- Arme + Haende -------------------------------------------------
	local armLen = torsoH * 0.95
	local armW = torsoW * 0.22 + (stage - 1) * 0.05
	for _, side in ipairs({ -1, 1 }) do
		local armX = cx + side * (torsoW * 0.55 + armW * 0.3)
		local armY = torsoCenterY - torsoH * 0.05
		local sleeveColor = if stage >= 3 then bodyDark else bodyColor
		makePart(model, "CoronaArm", Vector3.new(armW, armLen, armW), Vector3.new(armX, armY, cz), sleeveColor, Enum.Material.SmoothPlastic, false)
		local handSize = armW * 1.4
		local handY = armY - armLen * 0.5 - handSize * 0.3
		local handColor = if stage >= 3 then armorMetal else bodyColor
		local hand = makePart(model, "CoronaHand", Vector3.new(handSize, handSize * 0.85, handSize), Vector3.new(armX, handY, cz), handColor, Enum.Material.Metal, false)
		hand.Shape = Enum.PartType.Ball
	end

	-- ---- Kopf: Corona-Spikeprotein-Sphaere mit roten Knobs ------------
	local head = makePart(model, "CoronaHead", Vector3.new(headD, headD, headD), Vector3.new(cx, headCenterY, cz), headColor, Enum.Material.SmoothPlastic, false)
	head.Shape = Enum.PartType.Ball
	-- Kleine Lumps/Spots auf der Sphaere (Mutations-Look)
	local lumpCount = 8 + stage * 2 + (if isBoss then 4 else 0)
	for i = 1, lumpCount do
		local t = i / lumpCount
		local theta = i * 2.4
		local phi = math.acos(1 - 2 * t)
		local dir = Vector3.new(math.sin(phi) * math.cos(theta), math.cos(phi), math.sin(phi) * math.sin(theta)).Unit
		local lumpPos = Vector3.new(cx, headCenterY, cz) + dir * headD * 0.5
		local lumpSize = headD * 0.18
		local lump = makePart(model, "CoronaHeadLump", Vector3.new(lumpSize, lumpSize, lumpSize), lumpPos, tint(headColor, bodyDark, (i % 2) * 0.3), Enum.Material.SmoothPlastic, false)
		lump.Shape = Enum.PartType.Ball
		-- jede zweite Lump ist ein roter Mutations-Fleck
		if i % 3 == 0 then
			lump.Color = spikeRedDeep
		end
	end

	-- Rote Knob-Spikes (Corona-typisch: Stalk + roter Ball-Cap)
	local nubCount = 10 + stage * 3 + (if isBoss then 8 else 0)
	for i = 1, nubCount do
		local t = (i + 0.5) / nubCount
		local theta = i * 2.4 + 0.5
		local phi = math.acos(1 - 2 * t)
		local dir = Vector3.new(math.sin(phi) * math.cos(theta), math.cos(phi), math.sin(phi) * math.sin(theta)).Unit
		local stalkLen = headD * 0.28 + (stage - 1) * 0.04 + (if isBoss then 0.15 else 0)
		local stalkCenter = Vector3.new(cx, headCenterY, cz) + dir * (headD * 0.5 + stalkLen * 0.5)
		local stalk = makePart(model, "CoronaSpikeStalk", Vector3.new(stalkLen * 0.32, stalkLen, stalkLen * 0.32), stalkCenter, spikeRedDeep, Enum.Material.SmoothPlastic, false)
		local upv = if math.abs(dir.Y) > 0.95 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
		stalk.CFrame = CFrame.lookAt(stalkCenter, stalkCenter + dir, upv) * CFrame.Angles(math.rad(90), 0, 0)
		-- Roter Knob
		local knob = makePart(model, "CoronaSpikeKnob", Vector3.new(stalkLen * 0.85, stalkLen * 0.85, stalkLen * 0.85), stalkCenter + dir * (stalkLen * 0.55), spikeRed, Enum.Material.SmoothPlastic, false)
		knob.Shape = Enum.PartType.Ball
	end

	-- ---- Gesicht / Gasmaske -------------------------------------------
	if stage <= 2 then
		-- Stage 1-2: einfache zornige Glow-Augen + leuchtender Frowning-Mund
		for _, side in ipairs({ -1, 1 }) do
			local eye = makePart(model, "CoronaEye", Vector3.new(headD * 0.22, headD * 0.12, 0.14), Vector3.new(cx + side * headD * 0.18, headCenterY + headD * 0.05, cz - headD * 0.48), glowColor, Enum.Material.Neon, false)
			eye.Transparency = 0.05
			eye.Orientation = Vector3.new(0, 0, side * -22)
			local pl = Instance.new("PointLight")
			pl.Brightness = 0.6
			pl.Range = 6
			pl.Color = glowColor
			pl.Parent = eye
		end
		-- Frowning-Mund (gebogener Schlitz: 3 Teilstrips)
		for k = -1, 1 do
			local mx = cx + k * headD * 0.12
			local my = headCenterY - headD * 0.22 + math.abs(k) * headD * 0.04
			makePart(model, "CoronaMouth", Vector3.new(headD * 0.16, headD * 0.06, 0.14), Vector3.new(mx, my, cz - headD * 0.48), bodyDark, Enum.Material.SmoothPlastic, false)
		end
	else
		-- Stage 3+: Gasmaske (Mundpanel + Filter-Zylinder)
		local maskCenter = makePart(model, "CoronaMaskCenter", Vector3.new(headD * 0.7, headD * 0.42, 0.18), Vector3.new(cx, headCenterY - headD * 0.15, cz - headD * 0.46), maskColor, Enum.Material.Metal, false)
		for _, side in ipairs({ -1, 1 }) do
			local filter = makePart(model, "CoronaMaskFilter", Vector3.new(0.6, 0.78, 0.6), Vector3.new(cx + side * headD * 0.28, headCenterY - headD * 0.3, cz - headD * 0.55), maskColor, Enum.Material.Metal, false)
			filter.Shape = Enum.PartType.Cylinder
			filter.Orientation = Vector3.new(0, 0, 90)
			-- Filter-Glow am unteren Ende
			local fg = makePart(model, "CoronaMaskFilterGlow", Vector3.new(0.6, 0.2, 0.6), Vector3.new(cx + side * headD * 0.28, headCenterY - headD * 0.42, cz - headD * 0.55), glowColor, Enum.Material.Neon, false)
			fg.Shape = Enum.PartType.Cylinder
			fg.Orientation = Vector3.new(0, 0, 90)
			-- Schlauch
			local hose = makePart(model, "CoronaMaskHose", Vector3.new(0.22, 0.6, 0.22), Vector3.new(cx + side * headD * 0.34, headCenterY - headD * 0.05, cz - headD * 0.5), maskColor, Enum.Material.Metal, false)
			hose.Orientation = Vector3.new(0, 0, side * -30)
		end
		-- Boese Glow-Augen ueber der Maske
		for _, side in ipairs({ -1, 1 }) do
			local eye = makePart(model, "CoronaMaskEye", Vector3.new(headD * 0.22, headD * 0.13, 0.16), Vector3.new(cx + side * headD * 0.18, headCenterY + headD * 0.08, cz - headD * 0.48), glowColor, Enum.Material.Neon, false)
			eye.Transparency = 0.04
			eye.Orientation = Vector3.new(0, 0, side * -22)
			local pl = Instance.new("PointLight")
			pl.Brightness = if isBoss then 1.5 else 0.8
			pl.Range = if isBoss then 12 else 7
			pl.Color = glowColor
			pl.Parent = eye
		end
	end

	-- ---- BOSS Extras: Aura + Floor-Glow + BossPad ---------------------
	if isBoss then
		-- BossPad
		local ring = makePart(model, "BossPad", Vector3.new(0.5, totalH * 1.15, totalH * 1.15), Vector3.new(basePos.X, CHAMBER_TOP + 1.25, basePos.Z), purpleGlow, Enum.Material.Neon, false)
		ring.Shape = Enum.PartType.Cylinder
		ring.Orientation = Vector3.new(0, 0, 90)
		ring.Transparency = 0.3
		local floor1 = makePart(model, "BossCoronaFloorGlow", Vector3.new(0.22, totalH * 1.6, totalH * 1.6), Vector3.new(basePos.X, CHAMBER_TOP + 0.15, basePos.Z), purpleGlow, Enum.Material.Neon, false)
		floor1.Shape = Enum.PartType.Cylinder
		floor1.Orientation = Vector3.new(0, 0, 90)
		floor1.Transparency = 0.55
		-- Zerfetzte "Robe"-Fransen unten am Boss (lila Fetzen)
		for k = 1, 8 do
			local a = (k / 8) * math.pi * 2
			local fx = cx + math.cos(a) * (torsoW * 0.45)
			local fz = cz + math.sin(a) * (torsoD * 0.45)
			local frag = makePart(model, "BossCoronaRobe", Vector3.new(0.4, 1.0 + (k % 3) * 0.3, 0.18), Vector3.new(fx, hipY - 0.3 - (k % 3) * 0.2, fz), purpleGlow, Enum.Material.Neon, false)
			frag.Transparency = 0.4
			frag.Orientation = Vector3.new((k % 2) * 12, math.deg(a), 0)
		end
	end

	-- ---- Aura Partikel (mutated -> lila Mist, sonst gruener Mist) ------
	local aura = Instance.new("ParticleEmitter")
	aura.Name = "CoronaAura"
	aura.Texture = "rbxasset://textures/particles/smoke_main.dds"
	aura.Color = ColorSequence.new(glowColor, tint(if mutated then bodyPurpleDeep else bodyOliveDeep, Color3.fromRGB(30, 30, 30), 0.4))
	aura.LightEmission = 0.25
	aura.Rate = if isBoss then 16 else 2 + stage
	aura.Lifetime = NumberRange.new(1.0, 1.8)
	aura.Speed = NumberRange.new(0.5, 1.4)
	aura.Acceleration = Vector3.new(0, 1.4, 0)
	aura.SpreadAngle = Vector2.new(40, 40)
	aura.Size = NumberSequence.new(0.5, 0.1)
	aura.Parent = torso

	-- ---- Bewegung -----------------------------------------------------
	local arche = ENEMY_ARCHETYPE[def.Shape] or ENEMY_ARCHETYPE.Blob
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
	model:SetAttribute("HomeX", cx)
	model:SetAttribute("HomeY", root.Position.Y)
	model:SetAttribute("HomeZ", cz)
	model:SetAttribute("MoveRangeX", mv.rx)
	model:SetAttribute("MoveRangeZ", mv.rz)
	model:SetAttribute("MoveSpeed", mv.sp)
	model:SetAttribute("BobAmp", mv.bob)
	model:SetAttribute("EnemyKind", "Coronavirus")

	-- ---- Health-Bar ---------------------------------------------------
	local barScale = if isBoss then 1.9 else 1
	local barY = groundY + totalH + (if isBoss then 2.6 else 1.8)
	local barBack = makePart(model, "HealthBarBack", Vector3.new(13 * barScale, 0.8, 0.4), Vector3.new(cx, barY, cz), Color3.fromRGB(16, 20, 26), Enum.Material.SmoothPlastic, false)
	local barFill = makePart(model, "HealthBarFill", Vector3.new(12.4 * barScale, 0.5, 0.55), Vector3.new(cx, barY + 0.02, cz - 0.06), Color3.fromRGB(95, 255, 125), Enum.Material.Neon, false)
	barFill.Transparency = 0.12
	barFill:SetAttribute("MaxWidth", 12.4 * barScale)
	barFill:SetAttribute("FullCenterX", barFill.Position.X)

	-- ---- AttackClick + Boss-Prompt ------------------------------------
	local clicker = Instance.new("ClickDetector")
	clicker.Name = "AttackClick"
	clicker.MaxActivationDistance = EnemyConfig.AttackDistance
	clicker.Parent = root

	if isBoss then
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

	-- ---- Info-Label ---------------------------------------------------
	local prefix = if isBoss then "★ BOSS ★\n" else ""
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
		if isBoss then 60 else 34,
		UDim2.fromOffset(if isBoss then 280 else 190, if isBoss then 104 else 76),
		Vector3.new(0, boxH / 2 + 3, 0)
	)

	return model
end

-- ---- Cytokine Storm-Set fuer Area 9 -------------------------------------
-- Gold-Theme, jede Stage ist eine andere Form. Stages 1+3 haben einen
-- charakteristischen schwarz-roten Wurm-Tentakel aus dem Kopf, Stages 2+4
-- sprouten Cytokin-Tentakel aus Schultern/Body. Boss bekommt Halo + Mane.
local function buildCytokineWorm(parent, startPos, lookForward, length, baseR, segCount, bodyColor, eyeColor)
	-- Schwarzer Wurm mit rotem Auge am Tip (Cytokine-Worm aus Kopf).
	local segLen = length / segCount
	local cf = CFrame.lookAt(startPos, startPos + lookForward)
	local stepAngle = math.rad(-135 / segCount) -- starke Curve nach hinten
	for i = 1, segCount do
		local t = (i - 0.5) / segCount
		local r = baseR * (1 - t * 0.4) + 0.05
		local segPos = (cf * CFrame.new(0, 0, -segLen / 2)).Position
		local ball = makePart(parent, "CytokineWormSeg", Vector3.new(r * 2, r * 2, r * 2), segPos, bodyColor, Enum.Material.SmoothPlastic, false)
		ball.Shape = Enum.PartType.Ball
		-- Rote Cracks alle 2 Segmente
		if i % 2 == 0 then
			local crack = makePart(parent, "CytokineWormCrack", Vector3.new(r * 1.1, r * 0.35, r * 1.1), segPos, eyeColor, Enum.Material.Neon, false)
			crack.Shape = Enum.PartType.Ball
			crack.Transparency = 0.35
		end
		cf = cf * CFrame.new(0, 0, -segLen) * CFrame.Angles(stepAngle, 0, 0)
	end
	-- Kopf des Wurms: breiter, mit grossem rotem Auge
	local headCF = cf * CFrame.new(0, 0, -segLen * 0.4)
	local headPart = makePart(parent, "CytokineWormHead", Vector3.new(baseR * 2.0, baseR * 1.6, baseR * 2.3), headCF.Position, bodyColor, Enum.Material.SmoothPlastic, false)
	headPart.Shape = Enum.PartType.Ball
	-- Maul-Frill (3 kleine Tentakel-Spitzen vorne)
	for k = -1, 1 do
		local frill = makePart(parent, "CytokineWormFrill", Vector3.new(baseR * 0.5, baseR * 1.2, baseR * 0.5), (headCF * CFrame.new(k * baseR * 0.6, -baseR * 0.3, -baseR * 0.8)).Position, eyeColor, Enum.Material.Neon, false)
		frill.Transparency = 0.2
	end
	-- Rotes Auge am Front
	local eyePos = (headCF * CFrame.new(0, 0, -baseR * 1.2)).Position
	local eye = makePart(parent, "CytokineWormEye", Vector3.new(baseR * 1.0, baseR * 1.0, baseR * 1.0), eyePos, eyeColor, Enum.Material.Neon, false)
	eye.Shape = Enum.PartType.Ball
	eye.Transparency = 0.05
	local pl = Instance.new("PointLight")
	pl.Brightness = 1.4
	pl.Range = 8
	pl.Color = eyeColor
	pl.Parent = eye
end

local function buildCytokineStormEnemyModel(parent, def, basePos, primary, secondary)
	local model = Instance.new("Model")
	model.Name = def.Id
	model:SetAttribute("EnemyId", def.Id)
	model:SetAttribute("AreaName", def.AreaName)
	model:SetAttribute("IsBoss", def.IsBoss)
	model.Parent = parent

	local stage = def.EnemyIndex
	local isBoss = def.IsBoss
	local totalHeights = { 5.0, 6.2, 7.4, 8.6, 9.8 }
	local totalH = totalHeights[stage] or 5.0

	local legH = 1.6 + (stage - 1) * 0.45
	local headD = 2.0 + (stage - 1) * 0.30 + (if isBoss then 0.8 else 0)
	local torsoH = totalH - legH - headD * 0.40
	if torsoH < 0.8 then
		torsoH = 0.8
	end
	local torsoW = 1.7 + (stage - 1) * 0.38 + (if isBoss then 1.7 else 0)
	local torsoD = torsoW * 0.6 + (if isBoss then 0.6 else 0)
	local legW = 0.7 + (stage - 1) * 0.12 + (if isBoss then 0.35 else 0)

	-- Cytokine Storm-Palette: alles Gold + roter Wurm-Akzent.
	local goldBase = Color3.fromRGB(228, 198, 56)
	local goldDeep = Color3.fromRGB(168, 138, 32)
	local goldDark = Color3.fromRGB(105, 82, 16)
	local goldHilite = Color3.fromRGB(252, 232, 110)
	local yellowGlow = Color3.fromRGB(255, 232, 110)
	local yellowNeon = Color3.fromRGB(255, 215, 60)
	local redEye = Color3.fromRGB(255, 42, 38)
	local wormBody = Color3.fromRGB(58, 36, 28)
	local armorEdge = Color3.fromRGB(82, 65, 14)

	local groundY = CHAMBER_TOP
	local hipY = groundY + legH
	local torsoCenterY = hipY + torsoH / 2
	local neckY = hipY + torsoH
	local headCenterY = neckY + headD / 2 - headD * 0.05
	local cx, cz = basePos.X, basePos.Z

	-- EnemyCore = unsichtbare Bounding-Box.
	local boxW = math.max(torsoW + 0.8 + (if isBoss then 4.5 else if stage >= 2 then 1.6 else 0.5), headD + 1.0)
	local boxH = totalH + (if isBoss then 4.5 else if stage >= 1 then 2.5 else 1.5) -- Wurm/Mane extra
	local boxD = torsoD + (if isBoss then 2.4 else 1.0)
	local root = makePart(model, "EnemyCore", Vector3.new(boxW, boxH, boxD), Vector3.new(cx, groundY + boxH / 2, cz), goldBase, Enum.Material.SmoothPlastic, false)
	root.CanQuery = true
	root.Transparency = 1
	model.PrimaryPart = root

	-- ---- Beine ---------------------------------------------------------
	local legSpacing = torsoW * 0.32
	for _, side in ipairs({ -1, 1 }) do
		makePart(model, "CytoLeg", Vector3.new(legW, legH * 0.9, legW), Vector3.new(cx + side * legSpacing, hipY - legH * 0.5, cz), goldBase, Enum.Material.SmoothPlastic, false)
		makePart(model, "CytoBoot", Vector3.new(legW * 1.3, legH * 0.22, legW * 1.4), Vector3.new(cx + side * legSpacing, groundY + legH * 0.11, cz + legW * 0.1), goldDark, Enum.Material.Metal, false)
		-- Armor-Plates ab Stage 2
		if stage >= 2 then
			makePart(model, "CytoKneePlate", Vector3.new(legW * 1.1, legH * 0.25, legW * 0.7), Vector3.new(cx + side * legSpacing, hipY - legH * 0.42, cz - legW * 0.4), goldDeep, Enum.Material.Metal, false)
		end
		-- Hellgold Akzentstreifen
		if stage >= 2 then
			makePart(model, "CytoLegAccent", Vector3.new(0.12, legH * 0.7, 0.12), Vector3.new(cx + side * legSpacing, hipY - legH * 0.45, cz - legW * 0.55), goldHilite, Enum.Material.Neon, false).Transparency = 0.3
		end
	end

	-- ---- Torso ---------------------------------------------------------
	local torsoColor = if stage >= 2 then goldDeep else goldBase
	local torso = makePart(model, "CytoTorso", Vector3.new(torsoW, torsoH, torsoD), Vector3.new(cx, torsoCenterY, cz), torsoColor, Enum.Material.SmoothPlastic, false)
	-- Brustpanzer mit gold Plattenmuster (Stage 2+)
	if stage >= 2 then
		makePart(model, "CytoChestPlate", Vector3.new(torsoW * 0.95, torsoH * 0.85, 0.18), Vector3.new(cx, torsoCenterY, cz - torsoD / 2 - 0.1), goldDeep, Enum.Material.Metal, false)
		-- Trim
		for _, side in ipairs({ -1, 1 }) do
			makePart(model, "CytoChestTrim", Vector3.new(0.15, torsoH * 0.7, 0.2), Vector3.new(cx + side * torsoW * 0.4, torsoCenterY, cz - torsoD / 2 - 0.14), goldHilite, Enum.Material.Neon, false).Transparency = 0.3
		end
	end

	-- Chest-Gem / Glow-Core (Stage 2+)
	if stage >= 2 then
		local gemSize = headD * (0.28 + (stage - 2) * 0.06) + (if isBoss then 0.4 else 0)
		local gem = makePart(model, "CytoChestGem", Vector3.new(gemSize, gemSize, gemSize * 0.6), Vector3.new(cx, torsoCenterY, cz - torsoD / 2 - 0.22), yellowGlow, Enum.Material.Neon, false)
		gem.Shape = Enum.PartType.Ball
		gem.Transparency = 0.05
		local pl = Instance.new("PointLight")
		pl.Brightness = if isBoss then 3 else 1.6
		pl.Range = if isBoss then 22 else 12
		pl.Color = yellowGlow
		pl.Parent = gem
		-- Geprägter Goldrahmen drum
		for k = 0, 7 do
			local a = (k / 8) * math.pi * 2
			local rx = cx + math.cos(a) * gemSize * 0.95
			local ry = torsoCenterY + math.sin(a) * gemSize * 0.95
			local stud = makePart(model, "CytoGemStud", Vector3.new(0.18, 0.18, 0.18), Vector3.new(rx, ry, cz - torsoD / 2 - 0.22), goldHilite, Enum.Material.Metal, false)
			stud.Shape = Enum.PartType.Ball
		end
	end

	-- Biohazard (Stage 3+, gelb leuchtend)
	if stage >= 3 then
		local hazSize = torsoW * 0.32
		local hazY = torsoCenterY - torsoH * 0.18
		makePart(model, "CytoHazardBacking", Vector3.new(hazSize * 1.18, hazSize * 1.18, 0.05), Vector3.new(cx, hazY, cz - torsoD / 2 - 0.18), goldDark, Enum.Material.SmoothPlastic, false)
		local hazard = makePart(model, "CytoHazard", Vector3.new(hazSize, hazSize, 0.06), Vector3.new(cx, hazY, cz - torsoD / 2 - 0.22), yellowNeon, Enum.Material.Neon, false)
		hazard.Transparency = 0.05
	end

	-- ---- Schulterpads --------------------------------------------------
	for _, side in ipairs({ -1, 1 }) do
		local padW = torsoW * 0.34 + (stage - 1) * 0.12 + (if isBoss then 0.7 else 0)
		local padH = torsoH * 0.4 + (stage - 1) * 0.1
		local padX = cx + side * (torsoW * 0.5 + padW * 0.3)
		local padY = torsoCenterY + torsoH * 0.42
		local pad = makePart(model, "CytoShoulderPad", Vector3.new(padW, padH, torsoD * 1.15), Vector3.new(padX, padY, cz), goldDeep, Enum.Material.Metal, false)
		pad.Orientation = Vector3.new(0, 0, side * -12)
		makePart(model, "CytoShoulderPadEdge", Vector3.new(padW * 1.05, 0.1, torsoD * 1.18), Vector3.new(padX, padY + padH * 0.35, cz), goldHilite, Enum.Material.Neon, false).Transparency = 0.25
	end

	-- ---- Arme + Haende -------------------------------------------------
	local armLen = torsoH * 0.95
	local armW = torsoW * 0.22 + (stage - 1) * 0.05
	for _, side in ipairs({ -1, 1 }) do
		local armX = cx + side * (torsoW * 0.55 + armW * 0.3)
		local armY = torsoCenterY - torsoH * 0.05
		makePart(model, "CytoArm", Vector3.new(armW, armLen, armW), Vector3.new(armX, armY, cz), goldBase, Enum.Material.SmoothPlastic, false)
		local handSize = armW * 1.4
		local handY = armY - armLen * 0.5 - handSize * 0.3
		local hand = makePart(model, "CytoHand", Vector3.new(handSize, handSize * 0.85, handSize), Vector3.new(armX, handY, cz), goldDeep, Enum.Material.Metal, false)
		hand.Shape = Enum.PartType.Ball
		-- Demonen-Klauen (Stage 4+)
		if stage >= 4 then
			for k = -1, 1 do
				local cxx = armX + k * handSize * 0.32
				local clawLen = handSize * (1.0 + (if isBoss then 0.4 else 0))
				makePart(model, "CytoClaw", Vector3.new(0.28, clawLen, 0.28), Vector3.new(cxx, handY - clawLen * 0.5, cz + handSize * 0.1), goldDark, Enum.Material.Metal, false)
				makePart(model, "CytoClawTip", Vector3.new(0.32, 0.25, 0.32), Vector3.new(cxx, handY - clawLen - 0.05, cz + handSize * 0.1), goldHilite, Enum.Material.Metal, false)
			end
		end
	end

	-- ---- Kopf-Architektur (variiert pro Stage) -------------------------
	if stage <= 2 then
		-- Stage 1-2: Virus-Spike-Sphaere mit Gold-Tile-Look
		local head = makePart(model, "CytoHead", Vector3.new(headD, headD, headD), Vector3.new(cx, headCenterY, cz), goldBase, Enum.Material.SmoothPlastic, false)
		head.Shape = Enum.PartType.Ball
		-- Tile-Lumps
		local lumpCount = 10 + stage * 2
		for i = 1, lumpCount do
			local t = i / lumpCount
			local theta = i * 2.4
			local phi = math.acos(1 - 2 * t)
			local dir = Vector3.new(math.sin(phi) * math.cos(theta), math.cos(phi), math.sin(phi) * math.sin(theta)).Unit
			local lumpPos = Vector3.new(cx, headCenterY, cz) + dir * headD * 0.5
			local lumpSize = headD * 0.16
			local lump = makePart(model, "CytoHeadLump", Vector3.new(lumpSize, lumpSize, lumpSize), lumpPos, tint(goldBase, goldDeep, (i % 2) * 0.25), Enum.Material.SmoothPlastic, false)
			lump.Shape = Enum.PartType.Ball
		end
		-- Goldene Knob-Spikes (wie Corona-Spikes aber gold)
		local nubCount = 10 + stage * 2
		for i = 1, nubCount do
			local t = (i + 0.5) / nubCount
			local theta = i * 2.4 + 0.5
			local phi = math.acos(1 - 2 * t)
			local dir = Vector3.new(math.sin(phi) * math.cos(theta), math.cos(phi), math.sin(phi) * math.sin(theta)).Unit
			local stalkLen = headD * 0.22 + (stage - 1) * 0.03
			local stalkCenter = Vector3.new(cx, headCenterY, cz) + dir * (headD * 0.5 + stalkLen * 0.5)
			local stalk = makePart(model, "CytoSpikeStalk", Vector3.new(stalkLen * 0.3, stalkLen, stalkLen * 0.3), stalkCenter, goldDeep, Enum.Material.Metal, false)
			local upv = if math.abs(dir.Y) > 0.95 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
			stalk.CFrame = CFrame.lookAt(stalkCenter, stalkCenter + dir, upv) * CFrame.Angles(math.rad(90), 0, 0)
			local knob = makePart(model, "CytoSpikeKnob", Vector3.new(stalkLen * 0.8, stalkLen * 0.8, stalkLen * 0.8), stalkCenter + dir * (stalkLen * 0.55), goldHilite, Enum.Material.SmoothPlastic, false)
			knob.Shape = Enum.PartType.Ball
		end
		-- Gelbe Glow-Augen (zornig) + Frowning-Mund
		for _, side in ipairs({ -1, 1 }) do
			local eye = makePart(model, "CytoEye", Vector3.new(headD * 0.22, headD * 0.12, 0.14), Vector3.new(cx + side * headD * 0.18, headCenterY + headD * 0.06, cz - headD * 0.48), yellowGlow, Enum.Material.Neon, false)
			eye.Transparency = 0.05
			eye.Orientation = Vector3.new(0, 0, side * -22)
			local pl = Instance.new("PointLight")
			pl.Brightness = 0.6
			pl.Range = 6
			pl.Color = yellowGlow
			pl.Parent = eye
		end
		for k = -1, 1 do
			local mx = cx + k * headD * 0.12
			local my = headCenterY - headD * 0.22 + math.abs(k) * headD * 0.04
			makePart(model, "CytoMouth", Vector3.new(headD * 0.16, headD * 0.06, 0.14), Vector3.new(mx, my, cz - headD * 0.48), goldDark, Enum.Material.SmoothPlastic, false)
		end
	elseif stage == 3 then
		-- Stage 3: Gold-Mech-Helm mit Mask-Visor + Wurm oben
		local helmTop = makePart(model, "CytoHelmTop", Vector3.new(headD * 0.95, headD * 0.55, headD * 0.95), Vector3.new(cx, headCenterY + headD * 0.18, cz), goldDeep, Enum.Material.Metal, false)
		helmTop.Shape = Enum.PartType.Ball
		makePart(model, "CytoHelmJaw", Vector3.new(headD * 0.85, headD * 0.4, headD * 0.6), Vector3.new(cx, headCenterY - headD * 0.2, cz - headD * 0.1), goldBase, Enum.Material.Metal, false)
		-- Visor / Augen
		for _, side in ipairs({ -1, 1 }) do
			local eye = makePart(model, "CytoHelmEye", Vector3.new(headD * 0.2, headD * 0.13, 0.16), Vector3.new(cx + side * headD * 0.18, headCenterY + headD * 0.05, cz - headD * 0.5), yellowGlow, Enum.Material.Neon, false)
			eye.Transparency = 0.05
			eye.Orientation = Vector3.new(0, 0, side * -20)
		end
		-- Rohre an der Seite des Helms (mech-Look)
		for _, side in ipairs({ -1, 1 }) do
			local pipe = makePart(model, "CytoHelmPipe", Vector3.new(0.32, headD * 0.5, 0.32), Vector3.new(cx + side * headD * 0.42, headCenterY - headD * 0.05, cz + headD * 0.15), goldDark, Enum.Material.Metal, false)
		end
	else
		-- Stage 4 + Boss: Daemon-Kopf (kein simpler Helm mehr)
		local skull = makePart(model, "CytoDemonSkull", Vector3.new(headD * 1.05, headD * 1.1, headD * 1.1), Vector3.new(cx, headCenterY, cz), goldBase, Enum.Material.SmoothPlastic, false)
		skull.Shape = Enum.PartType.Ball
		-- Reissmaul vorne (gross + Zaehne)
		local mouthW = headD * (if isBoss then 0.85 else 0.6)
		local mouthH = headD * (if isBoss then 0.45 else 0.3)
		local mouthBack = makePart(model, "CytoDemonMaw", Vector3.new(mouthW, mouthH, 0.18), Vector3.new(cx, headCenterY - headD * 0.15, cz - headD * 0.46), Color3.fromRGB(40, 24, 8), Enum.Material.SmoothPlastic, false)
		-- Glow-Innenseite
		local maw = makePart(model, "CytoDemonMawGlow", Vector3.new(mouthW * 0.9, mouthH * 0.85, 0.18), Vector3.new(cx, headCenterY - headD * 0.15, cz - headD * 0.5), yellowGlow, Enum.Material.Neon, false)
		maw.Transparency = 0.15
		-- Zaehne ueber dem Maul (oben + unten)
		local toothCount = if isBoss then 9 else 7
		for k = 1, toothCount do
			local t = (k - (toothCount + 1) / 2) / toothCount
			for _, vSign in ipairs({ 1, -1 }) do
				local toothH_local = mouthH * 0.6
				local toothY = headCenterY - headD * 0.15 + vSign * mouthH * 0.32
				makePart(model, "CytoDemonTooth", Vector3.new(mouthW * 0.08, toothH_local, 0.22), Vector3.new(cx + t * mouthW * 0.95, toothY, cz - headD * 0.5), Color3.fromRGB(240, 230, 200), Enum.Material.SmoothPlastic, false)
			end
		end
		-- Glow-Augen (gelb leuchtend)
		for _, side in ipairs({ -1, 1 }) do
			local eye = makePart(model, "CytoDemonEye", Vector3.new(headD * 0.28, headD * 0.16, 0.18), Vector3.new(cx + side * headD * 0.22, headCenterY + headD * 0.18, cz - headD * 0.45), yellowGlow, Enum.Material.Neon, false)
			eye.Transparency = 0.04
			eye.Orientation = Vector3.new(0, 0, side * -24)
			local pl = Instance.new("PointLight")
			pl.Brightness = if isBoss then 2.4 else 1.2
			pl.Range = if isBoss then 14 else 9
			pl.Color = yellowGlow
			pl.Parent = eye
		end
		-- Mane: viele Hoerner/Stachel rund um den Kopf (Stage 4 weniger, Boss massiv)
		local maneCount = if isBoss then 18 else 10
		for i = 1, maneCount do
			local a = (i / maneCount) * math.pi * 2
			local up = 0.6 + math.abs(math.sin(i * 0.85)) * 0.4
			local dir = Vector3.new(math.cos(a) * 0.7, up, math.sin(a) * 0.7).Unit
			local hornLen = headD * (if isBoss then 0.9 else 0.55) + (i % 3) * 0.2
			local hc = Vector3.new(cx, headCenterY, cz) + dir * headD * 0.55
			local horn = makePart(model, "CytoMaheHorn", Vector3.new(0.36, hornLen, 0.36), hc, goldDeep, Enum.Material.Metal, false)
			local upv = if math.abs(dir.Y) > 0.95 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
			horn.CFrame = CFrame.lookAt(hc, hc + dir, upv) * CFrame.Angles(math.rad(90), 0, 0)
			makePart(model, "CytoMaheHornTip", Vector3.new(0.4, 0.28, 0.4), hc + dir * (hornLen * 0.55), goldHilite, Enum.Material.Metal, false)
		end
	end

	-- ---- Charakteristischer Wurm-Tentakel (Stage 1, 3) ----------------
	if stage == 1 or stage == 3 then
		local startY = neckY + 0.3
		local wormLen = totalH * (if stage == 3 then 0.6 else 0.5)
		local wormR = if stage == 3 then 0.32 else 0.22
		local segs = if stage == 3 then 9 else 7
		buildCytokineWorm(model, Vector3.new(cx + 0.4, startY, cz + 0.2), Vector3.new(0, 1, -0.2).Unit, wormLen, wormR, segs, wormBody, redEye)
	end

	-- ---- Cytokin-Tentakel (Stage 2, 4, Boss) --------------------------
	if stage == 2 then
		-- Kleine gelb leuchtende Tentakel an Schultern/Body
		for _, side in ipairs({ -1, 1 }) do
			for k = 1, 3 do
				local sx = cx + side * (torsoW * 0.5 + 0.2)
				local sy = torsoCenterY + (k - 2) * (torsoH * 0.25)
				local sz = cz + 0.1
				local tendLen = 1.2 + k * 0.2
				local tend = makePart(model, "CytoTendril", Vector3.new(0.28, tendLen, 0.28), Vector3.new(sx + side * 0.4, sy + tendLen * 0.2, sz), yellowGlow, Enum.Material.Neon, false)
				tend.Transparency = 0.18
				tend.Orientation = Vector3.new(side * 30 + k * 8, side * 35, side * -45 + k * 12)
			end
		end
	end
	if stage == 4 or isBoss then
		-- Flammen-Tentakel-Mane hinter dem Kopf (gelb)
		local flameCount = if isBoss then 14 else 8
		for i = 1, flameCount do
			local a = (i / flameCount) * math.pi - math.pi * 0.5
			local fLen = 1.8 + math.cos(a) * 0.6 + (if isBoss then 1.6 else 0)
			local fx = cx + math.sin(a) * (torsoW * 0.4 + 0.6)
			local fy = neckY + 0.5 + math.cos(a) * 1.4 + fLen * 0.4
			local fz = cz + torsoD * 0.3 + 0.4
			local flame = makePart(model, "CytoFlame", Vector3.new(0.36, fLen, 0.36), Vector3.new(fx, fy, fz), yellowGlow, Enum.Material.Neon, false)
			flame.Transparency = 0.22
			flame.Orientation = Vector3.new(math.deg(a) * 0.4, math.deg(a) * 30, math.deg(a) * 25)
		end
	end

	-- ---- BOSS Extras: Halo, Chains, Floor-Glow ------------------------
	if isBoss then
		-- Riesiger Halo hinter dem Kopf (Cylinder als flacher Ring)
		local haloY = headCenterY + 1.2
		local haloOuter = makePart(model, "BossCytoHalo", Vector3.new(0.6, 7.2, 7.2), Vector3.new(cx, haloY, cz + 0.4), yellowGlow, Enum.Material.Neon, false)
		haloOuter.Shape = Enum.PartType.Cylinder
		haloOuter.Orientation = Vector3.new(0, 0, 90)
		haloOuter.Transparency = 0.2
		-- Strahlen ringsum (12 Stueck)
		for k = 0, 11 do
			local a = (k / 12) * math.pi * 2
			local rx = cx + math.cos(a) * 4.5
			local ry = haloY + math.sin(a) * 4.5
			local ray = makePart(model, "BossCytoHaloRay", Vector3.new(0.4, 1.3, 0.4), Vector3.new(rx, ry, cz + 0.4), yellowNeon, Enum.Material.Neon, false)
			ray.Orientation = Vector3.new(0, 0, math.deg(a) + 90)
			ray.Transparency = 0.25
		end
		local haloLight = Instance.new("PointLight")
		haloLight.Brightness = 3
		haloLight.Range = 30
		haloLight.Color = yellowGlow
		haloLight.Parent = haloOuter
		-- Ketten von den Armen herunter
		for _, side in ipairs({ -1, 1 }) do
			for k = 1, 5 do
				local linkY = torsoCenterY - torsoH * 0.2 - k * 0.55
				local linkX = cx + side * (torsoW * 0.45 + math.sin(k * 0.5) * 0.2)
				local linkZ = cz + torsoD / 2 + 0.4
				local link = makePart(model, "BossCytoChain", Vector3.new(0.32, 0.2, 0.32), Vector3.new(linkX, linkY, linkZ), goldDark, Enum.Material.Metal, false)
				link.Shape = Enum.PartType.Ball
			end
		end
		-- BossPad
		local ring = makePart(model, "BossPad", Vector3.new(0.5, totalH * 1.15, totalH * 1.15), Vector3.new(basePos.X, CHAMBER_TOP + 1.25, basePos.Z), yellowGlow, Enum.Material.Neon, false)
		ring.Shape = Enum.PartType.Cylinder
		ring.Orientation = Vector3.new(0, 0, 90)
		ring.Transparency = 0.3
		local floor1 = makePart(model, "BossCytoFloorGlow", Vector3.new(0.22, totalH * 1.7, totalH * 1.7), Vector3.new(basePos.X, CHAMBER_TOP + 0.15, basePos.Z), yellowNeon, Enum.Material.Neon, false)
		floor1.Shape = Enum.PartType.Cylinder
		floor1.Orientation = Vector3.new(0, 0, 90)
		floor1.Transparency = 0.55
	end

	-- ---- Gold-Sparks-Partikel -----------------------------------------
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "CytokineSparks"
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(yellowGlow, tint(goldDeep, Color3.fromRGB(30, 22, 8), 0.4))
	sparks.LightEmission = 0.4
	sparks.Rate = if isBoss then 18 else 2 + stage
	sparks.Lifetime = NumberRange.new(0.8, 1.6)
	sparks.Speed = NumberRange.new(0.5, 1.4)
	sparks.Acceleration = Vector3.new(0, 1.6, 0)
	sparks.SpreadAngle = Vector2.new(40, 40)
	sparks.Size = NumberSequence.new(0.4, 0.08)
	sparks.Parent = torso

	-- ---- Bewegung -----------------------------------------------------
	local arche = ENEMY_ARCHETYPE[def.Shape] or ENEMY_ARCHETYPE.Blob
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
	model:SetAttribute("HomeX", cx)
	model:SetAttribute("HomeY", root.Position.Y)
	model:SetAttribute("HomeZ", cz)
	model:SetAttribute("MoveRangeX", mv.rx)
	model:SetAttribute("MoveRangeZ", mv.rz)
	model:SetAttribute("MoveSpeed", mv.sp)
	model:SetAttribute("BobAmp", mv.bob)
	model:SetAttribute("EnemyKind", "CytokineStorm")

	-- ---- Health-Bar ---------------------------------------------------
	local barScale = if isBoss then 1.9 else 1
	local barY = groundY + totalH + (if isBoss then 4.2 else 2.4)
	local barBack = makePart(model, "HealthBarBack", Vector3.new(13 * barScale, 0.8, 0.4), Vector3.new(cx, barY, cz), Color3.fromRGB(16, 20, 26), Enum.Material.SmoothPlastic, false)
	local barFill = makePart(model, "HealthBarFill", Vector3.new(12.4 * barScale, 0.5, 0.55), Vector3.new(cx, barY + 0.02, cz - 0.06), Color3.fromRGB(95, 255, 125), Enum.Material.Neon, false)
	barFill.Transparency = 0.12
	barFill:SetAttribute("MaxWidth", 12.4 * barScale)
	barFill:SetAttribute("FullCenterX", barFill.Position.X)

	-- ---- AttackClick + Boss-Prompt ------------------------------------
	local clicker = Instance.new("ClickDetector")
	clicker.Name = "AttackClick"
	clicker.MaxActivationDistance = EnemyConfig.AttackDistance
	clicker.Parent = root

	if isBoss then
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

	-- ---- Info-Label ---------------------------------------------------
	local prefix = if isBoss then "★ BOSS ★\n" else ""
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
		if isBoss then 60 else 34,
		UDim2.fromOffset(if isBoss then 280 else 190, if isBoss then 104 else 76),
		Vector3.new(0, boxH / 2 + 3, 0)
	)

	return model
end

-- ---- Biomecha Hive-Lord Set fuer Area 10 (Optimiertes Final-Endgame) ----
-- Biomechanische Verschmelzung: Fleischige Tentakel mit Metall-Panzerung,
-- pulsierender Kern, mechanische Krone und schwebende konzentrische Ringe.

local function buildBiomechaTentacle(parent, startPos, lookForward, length, baseR, segCount, archDeg, isBoss)
    local fleshColor = Color3.fromRGB(130, 40, 50) -- Dunkles Fleisch/Blut
    local armorColor = Color3.fromRGB(30, 35, 40)  -- Dunkles Metall
    
    local segLen = length / segCount
    local cf = CFrame.lookAt(startPos, startPos + lookForward)
    local stepAngle = math.rad(archDeg / segCount)
    
    for i = 1, segCount do
        local t = (i - 0.5) / segCount
        local r = baseR * (1 - t * 0.5) + 0.05
        local segPos = (cf * CFrame.new(0, 0, -segLen / 2)).Position
        
        -- Organisches Fleisch-Segment des Tentakels
        -- Wir nutzen hier makePart, da dies die Hilfsfunktion deines Skripts zu sein scheint
        local flesh = makePart(parent, "BiomechaTentFlesh", Vector3.new(r * 2, r * 2.2, r * 2), segPos, fleshColor, Enum.Material.CorrodedMetal, false)
        flesh.Shape = Enum.PartType.Ball
        
        -- Mechanische Panzerung an der Oberseite (wächst heraus)
        if i % 2 == 1 then
            local armor = makePart(parent, "BiomechaTentArmor", Vector3.new(r * 2.2, r * 0.8, r * 2.2), segPos, armorColor, Enum.Material.Metal, false)
            armor.CFrame = cf * CFrame.new(0, r * 0.8, -segLen / 2)
            
            -- Cyan Tech-Glow Linien in der Rüstung
            local glow = makePart(parent, "BiomechaTentGlow", Vector3.new(r * 0.4, r * 0.9, r * 1.5), armor.Position, Color3.fromRGB(0, 255, 255), Enum.Material.Neon, false)
            glow.CFrame = armor.CFrame
        end
        
        -- Schwarm-Dronen/Käfer auf den Tentakeln (Boss-Exklusiv)
        if isBoss and i % 3 == 0 then
            local bugPos = (cf * CFrame.new(r * 0.8, r * 0.5, -segLen / 2) * CFrame.Angles(0, math.rad(45), 0)).Position
            local bug = makePart(parent, "SwarmDrone", Vector3.new(r * 0.8, r * 0.4, r * 1.2), bugPos, Color3.fromRGB(20, 20, 25), Enum.Material.Metal, false)
            bug.CFrame = cf * CFrame.new(r * 0.8, r * 0.5, -segLen / 2) * CFrame.Angles(0, math.rad(45), 0)
            
            local bugEye = makePart(parent, "SwarmDroneEye", Vector3.new(r * 0.2, r * 0.2, r * 0.2), bug.Position, Color3.fromRGB(255, 0, 50), Enum.Material.Neon, false)
            bugEye.CFrame = bug.CFrame * CFrame.new(0, 0, -r * 0.6)
        end
        
        cf = cf * CFrame.new(0, 0, -segLen) * CFrame.Angles(stepAngle, 0, 0)
    end
    
    -- Spitze: Harte Metall-Klaue
    local tipPos = (cf * CFrame.new(0, 0, -segLen * 0.3)).Position
    local tip = makePart(parent, "BiomechaTentTip", Vector3.new(baseR * 0.8, baseR * 0.8, baseR * 2), tipPos, armorColor, Enum.Material.Metal, false)
    tip.CFrame = cf
end

local function buildCrimsonMawEnemyModel(parent, def, basePos, primary, secondary)
    local model = Instance.new("Model")
    model.Name = def.Id
    model:SetAttribute("EnemyId", def.Id)
    model:SetAttribute("AreaName", def.AreaName)
    model:SetAttribute("IsBoss", def.IsBoss)
    model.Parent = parent

    local stage = def.EnemyIndex
    local isBoss = def.IsBoss
    local totalHeights = { 5.0, 6.2, 7.4, 8.6, 9.8 }
    local totalH = totalHeights[stage] or 5.0
    
    local legH = 1.6 + (stage - 1) * 0.45
    local headD = 2.0 + (stage - 1) * 0.32 + (if isBoss then 0.8 else 0)
    local torsoH = totalH - legH - headD * 0.40
    if torsoH < 0.8 then torsoH = 0.8 end
    local torsoW = 1.7 + (stage - 1) * 0.38 + (if isBoss then 1.8 else 0)
    local torsoD = torsoW * 0.6 + (if isBoss then 0.65 else 0)
    
    local groundY = CHAMBER_TOP
    local hipY = groundY + legH
    local torsoCenterY = hipY + torsoH / 2
    local neckY = hipY + torsoH
    local headCenterY = neckY + headD / 2 - headD * 0.05
    local cx, cz = basePos.X, basePos.Z

    local boxW = math.max(torsoW + 0.8 + (if isBoss then 5.0 else 0), headD + 1.2)
    local boxH = totalH + (if isBoss then 4.0 else 1.5)
    local boxD = torsoD + 0.8 + (if isBoss then 3.0 else 0)

    -- Farb-Konfiguration
    local bodyBlack = Color3.fromRGB(15, 15, 18)
    local armorDark = Color3.fromRGB(30, 35, 40)
    local fleshRed = Color3.fromRGB(150, 20, 40)
    local coreGlow = Color3.fromRGB(220, 0, 100) -- Deep Crimson/Violet
    local cyanGlow = Color3.fromRGB(0, 255, 255)
    
    -- EnemyCore (Wichtig für Klicks & Raycasts!)
    local root = makePart(model, "EnemyCore", Vector3.new(boxW, boxH, boxD), Vector3.new(cx, groundY + boxH / 2, cz), bodyBlack, Enum.Material.SmoothPlastic, false)
    root.CanQuery = true
    root.Transparency = 1
    model.PrimaryPart = root

    -- Basis Torso (Fleisch)
    local torso = makePart(model, "BiomechaTorso", Vector3.new(torsoW, torsoH, torsoD), Vector3.new(cx, torsoCenterY, cz), fleshRed, Enum.Material.CorrodedMetal, false)

    -- Brutale Brustpanzerung
    local chestArmor = makePart(model, "BiomechaChestArmor", Vector3.new(torsoW * 1.1, torsoH * 0.8, torsoD * 0.5), Vector3.new(cx, torsoCenterY, cz - torsoD * 0.4), armorDark, Enum.Material.Metal, false)

    -- Zentralkern (Biomechanisches Herz)
    local coreSize = if isBoss then torsoW * 0.8 else torsoW * 0.45
    local chestCore = makePart(model, "BiomechaHeart", Vector3.new(coreSize, coreSize * 1.2, coreSize * 0.5), Vector3.new(cx, torsoCenterY, cz - torsoD * 0.5), coreGlow, Enum.Material.Neon, false)
    chestCore.Shape = Enum.PartType.Ball
    
    local pl = Instance.new("PointLight")
    pl.Brightness = if isBoss then 4 else 2
    pl.Range = if isBoss then 30 else 15
    pl.Color = coreGlow
    pl.Parent = chestCore

    -- Kopf (Mechanische Basis)
    local head = makePart(model, "BiomechaHead", Vector3.new(headD, headD, headD), Vector3.new(cx, headCenterY, cz), armorDark, Enum.Material.Metal, false)
    head.Shape = Enum.PartType.Ball

    -- Krone & Optik
    if isBoss then
        local crownCount = 8
        for i = 1, crownCount do
            local a = (i / crownCount) * math.pi * 2
            local up = 0.8
            local fwd = math.cos(a) * 0.5
            local dir = Vector3.new(fwd, up, math.sin(a) * 0.5).Unit
            local hornLen = headD * 0.8
            local hc = Vector3.new(cx, headCenterY + headD * 0.2, cz) + dir * headD * 0.5
            
            local horn = makePart(model, "MechaCrownHorn", Vector3.new(0.4, hornLen, 0.4), hc, armorDark, Enum.Material.Metal, false)
            local upv = if math.abs(dir.Y) > 0.95 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
            horn.CFrame = CFrame.lookAt(hc, hc + dir, upv) * CFrame.Angles(math.rad(90), 0, 0)
            
            local glowPos = (horn.CFrame * CFrame.new(0, hornLen * 0.4, 0)).Position
            local hornGlow = makePart(model, "MechaCrownGlow", Vector3.new(0.45, 0.3, 0.45), glowPos, cyanGlow, Enum.Material.Neon, false)
            hornGlow.CFrame = horn.CFrame * CFrame.new(0, hornLen * 0.4, 0)
        end
        
        -- Gewaltiges zentrales Auge (Hive-Lord)
        local bossEye = makePart(model, "MechaEye", Vector3.new(headD * 0.45, headD * 0.45, 0.2), Vector3.new(cx, headCenterY, cz - headD * 0.48), coreGlow, Enum.Material.Neon, false)
        bossEye.Shape = Enum.PartType.Ball
    else
        -- Standard Stages (Leuchtende Augen-Punkte)
        for _, side in ipairs({-1, 1}) do
            local eye = makePart(model, "MechaEye", Vector3.new(headD * 0.2, headD * 0.1, 0.2), Vector3.new(cx + side * headD * 0.25, headCenterY, cz - headD * 0.45), cyanGlow, Enum.Material.Neon, false)
            eye.Orientation = Vector3.new(0, 0, side * -20)
        end
    end

    -- Tentakel-Aufbau
    local tentConfigs = {}
    local mainTentLen = totalH * 0.8
    
    if isBoss then
        -- Massive Biomecha-Tentakel in alle Richtungen
        for k = 1, 10 do
            local angle = (k - 5.5) / 9 * math.rad(220)
            local dir = Vector3.new(math.sin(angle), 0.5 + math.cos(angle * 0.4) * 0.4, math.cos(angle) * 0.4 + 0.3).Unit
            local startX = cx + math.sin(angle) * torsoW * 0.6
            local startY = torsoCenterY + math.cos(angle * 0.6) * 0.5
            local startZ = cz + torsoD * 0.2
            table.insert(tentConfigs, {
                startPos = Vector3.new(startX, startY, startZ),
                dir = dir,
                length = mainTentLen * 1.6,
                baseR = 0.45,
                segs = 12,
                arch = -80 + math.abs(angle) * 20
            })
        end
    else
        -- Normale Stages (Weniger Tentakel)
        local count = 2 + stage
        for k = 1, count do
            local angle = (k - (count+1)/2) / count * math.rad(120)
            local dir = Vector3.new(math.sin(angle), 0.6, math.cos(angle) * 0.3 + 0.3).Unit
            table.insert(tentConfigs, {
                startPos = Vector3.new(cx + math.sin(angle) * torsoW * 0.5, torsoCenterY, cz),
                dir = dir,
                length = mainTentLen,
                baseR = 0.3,
                segs = 8,
                arch = 60
            })
        end
    end
    
    for _, t in ipairs(tentConfigs) do
        buildBiomechaTentacle(model, t.startPos, t.dir, t.length, t.baseR, t.segs, t.arch, isBoss)
    end

    -- Konzentrische Ring-Plattformen (ersetzen die einfachen Glow-Pads)
    if isBoss then
        for k = 1, 3 do
            local ringSize = totalH * 1.2 + (k * 4)
            local name = if k == 1 then "BossPad" else "ConcentricRing" .. k
            local ring = makePart(model, name, Vector3.new(0.4, ringSize, ringSize), Vector3.new(basePos.X, CHAMBER_TOP + 1.25 - (k * 0.3), basePos.Z), coreGlow, Enum.Material.Neon, false)
            ring.Shape = Enum.PartType.Cylinder
            ring.Orientation = Vector3.new(0, 0, 90)
            ring.Transparency = 0.2 + (k * 0.15)
        end
    end

    -- Aura Partikel (Tech-Mist)
    local mist = Instance.new("ParticleEmitter")
    mist.Name = "BiomechaAura"
    mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
    mist.Color = ColorSequence.new(coreGlow, tint(fleshRed, bodyBlack, 0.5))
    mist.LightEmission = 0.5
    mist.Rate = if isBoss then 25 else 5 + stage
    mist.Lifetime = NumberRange.new(1.0, 2.0)
    mist.Speed = NumberRange.new(1.0, 2.0)
    mist.Acceleration = Vector3.new(0, 2, 0)
    mist.SpreadAngle = Vector2.new(45, 45)
    mist.Size = NumberSequence.new(0.8, 0.1)
    mist.Parent = torso

    -- ---- Bewegungs-System ---------------------------------------------
    local arche = ENEMY_ARCHETYPE[def.Shape] or ENEMY_ARCHETYPE.Blob
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
    model:SetAttribute("HomeX", cx)
    model:SetAttribute("HomeY", root.Position.Y)
    model:SetAttribute("HomeZ", cz)
    model:SetAttribute("MoveRangeX", mv.rx)
    model:SetAttribute("MoveRangeZ", mv.rz)
    model:SetAttribute("MoveSpeed", mv.sp)
    model:SetAttribute("BobAmp", mv.bob)
    model:SetAttribute("EnemyKind", "BiomechaHiveLord")

    -- ---- Health-Bar ---------------------------------------------------
    local barScale = if isBoss then 1.9 else 1
    local barY = groundY + totalH + (if isBoss then 3.6 else 2.0)
    
    local barBack = makePart(model, "HealthBarBack", Vector3.new(13 * barScale, 0.8, 0.4), Vector3.new(cx, barY, cz), Color3.fromRGB(16, 20, 26), Enum.Material.SmoothPlastic, false)
    local barFill = makePart(model, "HealthBarFill", Vector3.new(12.4 * barScale, 0.5, 0.55), Vector3.new(cx, barY + 0.02, cz - 0.06), Color3.fromRGB(95, 255, 125), Enum.Material.Neon, false)
    barFill.Transparency = 0.12
    barFill:SetAttribute("MaxWidth", 12.4 * barScale)
    barFill:SetAttribute("FullCenterX", barFill.Position.X)

    -- ---- AttackClick + Boss-Prompt ------------------------------------
    local clicker = Instance.new("ClickDetector")
    clicker.Name = "AttackClick"
    clicker.MaxActivationDistance = EnemyConfig.AttackDistance
    clicker.Parent = root

    if isBoss then
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

    -- ---- Info-Label ---------------------------------------------------
    local prefix = if isBoss then "★ BOSS ★\n" else ""
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
        if isBoss then 60 else 34,
        UDim2.fromOffset(if isBoss then 280 else 190, if isBoss then 104 else 76),
        Vector3.new(0, boxH / 2 + 3, 0)
    )

    return model
end
local function buildEnemyModel(parent, def, basePos, primary, secondary)
	-- Alle 10 Areas haben eigene Designs.
	if def.AreaIndex == 1 then
		return buildNorovirusEnemyModel(parent, def, basePos, primary, secondary)
	elseif def.AreaIndex == 2 then
		return buildHantavirusEnemyModel(parent, def, basePos, primary, secondary)
	elseif def.AreaIndex == 3 then
		return buildEbolaEnemyModel(parent, def, basePos, primary, secondary)
	elseif def.AreaIndex == 4 then
		return buildInfluenzaEnemyModel(parent, def, basePos, primary, secondary)
	elseif def.AreaIndex == 5 then
		return buildBoneSpikeEnemyModel(parent, def, basePos, primary, secondary)
	elseif def.AreaIndex == 6 then
		return buildPlasmaCoreEnemyModel(parent, def, basePos, primary, secondary)
	elseif def.AreaIndex == 7 then
		return buildCyberPhageEnemyModel(parent, def, basePos, primary, secondary)
	elseif def.AreaIndex == 8 then
		return buildCoronavirusEnemyModel(parent, def, basePos, primary, secondary)
	elseif def.AreaIndex == 9 then
		return buildCytokineStormEnemyModel(parent, def, basePos, primary, secondary)
	elseif def.AreaIndex == 10 then
		return buildCrimsonMawEnemyModel(parent, def, basePos, primary, secondary)
	end

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

-- ---- Boss-Schwelle: Archway zwischen letztem Normal-Gegner und Boss -------
-- Klare visuelle Trennung, damit der Spieler weiss: dahinter wartet der Boss.
-- Schwere Hazard-Pfeiler, gelb-schwarz gestreifte Bodenmarkierung, Warn-Beacon
-- und ein grosses Schild ("BOSS ZONE" + Boss-Name) in Thema-Akzent.
local function buildBossThreshold(parent, def, x, theme, accent)
	local model = Instance.new("Model")
	model.Name = "BossThreshold_" .. def.Id
	model.Parent = parent

	local zL, zR = BACTERIA_LEFT_LIMIT_Z + 2, BACTERIA_RIGHT_LIMIT_Z - 2
	local pillarHeight = 22
	local pillarWidth = 5
	local pillarDepth = 5.4
	local topY = FLOOR_Y + pillarHeight

	-- Schwere Pfeiler links/rechts mit gelb-schwarzen Hazard-Stripes.
	for _, pz in ipairs({ zL, zR }) do
		local post = makePart(model, "BossThresholdPost", Vector3.new(pillarWidth, pillarHeight, pillarDepth), Vector3.new(x, FLOOR_Y + pillarHeight / 2, pz), LAB_DARK, Enum.Material.Metal, true)
		for k = 0, 5 do
			local stripeColor = if k % 2 == 0 then LAB_WARNING_YELLOW else LAB_DARK
			makePart(model, "BossThresholdStripe", Vector3.new(pillarWidth + 0.05, 2.6, pillarDepth + 0.05), post.Position + Vector3.new(0, -pillarHeight / 2 + 1.3 + k * 3.4, 0), stripeColor, Enum.Material.SmoothPlastic, false)
		end
		makePart(model, "BossThresholdCap", Vector3.new(pillarWidth + 1.2, 1, pillarDepth + 1.2), Vector3.new(x, FLOOR_Y + pillarHeight - 0.5, pz), Color3.fromRGB(28, 30, 32), Enum.Material.Metal, false)
		makePart(model, "BossThresholdFoot", Vector3.new(pillarWidth + 1.6, 1.4, pillarDepth + 1.6), Vector3.new(x, FLOOR_Y + 0.7, pz), Color3.fromRGB(28, 30, 32), Enum.Material.Metal, false)
	end

	-- Querbalken ueber dem Laufweg, schwere "BOSS"-Beschilderung.
	local beam = makePart(model, "BossThresholdBeam", Vector3.new(pillarWidth + 2, 4, zR - zL + pillarDepth), Vector3.new(x, topY + 2, 0), LAB_DARK, Enum.Material.Metal, true)
	makePart(model, "BossThresholdBeamTop", Vector3.new(pillarWidth + 3, 0.8, zR - zL + pillarDepth + 0.8), Vector3.new(x, topY + 4.4, 0), Color3.fromRGB(18, 20, 22), Enum.Material.Metal, false)
	neonStrip(model, Vector3.new(0.6, 0.5, zR - zL - 6), Vector3.new(x, topY + 0.3, 0), LAB_WARNING_RED, 0.2)

	-- Grosses Boss-Schild auf Spielrichtung.
	local signFront = makePart(model, "BossThresholdSignFront", Vector3.new(pillarWidth + 1.4, 3.2, 18), Vector3.new(x - 2.1, topY + 1.5, 0), Color3.fromRGB(14, 16, 18), Enum.Material.Metal, false)
	label(signFront, "⚠ BOSS ZONE ⚠\n" .. string.upper(def.DisplayName), tint(accent, Color3.fromRGB(245, 248, 244), 0.4), 70, UDim2.fromOffset(420, 90), Vector3.new(-1, 0, 0))
	local signBack = makePart(model, "BossThresholdSignBack", Vector3.new(pillarWidth + 1.4, 3.2, 18), Vector3.new(x + 2.1, topY + 1.5, 0), Color3.fromRGB(14, 16, 18), Enum.Material.Metal, false)
	label(signBack, "← " .. string.upper(theme.wallText), Color3.fromRGB(220, 225, 220), 48, UDim2.fromOffset(280, 56), Vector3.new(1, 0, 0))

	-- Warn-Beacon zentral oben.
	local beacon = makePart(model, "BossThresholdBeacon", Vector3.new(1.6, 1.6, 1.6), Vector3.new(x, topY + 5.5, 0), LAB_WARNING_RED, Enum.Material.Neon, false)
	beacon.Shape = Enum.PartType.Ball
	local light = Instance.new("PointLight")
	light.Brightness = 0.8
	light.Range = 22
	light.Color = LAB_WARNING_RED
	light.Parent = beacon

	-- Boden-Hazardtape unter dem Bogen.
	local tape = makePart(model, "BossThresholdFloorTape", Vector3.new(3, 0.12, zR - zL), Vector3.new(x, LAYER_CONTAM + 0.05, 0), LAB_WARNING_YELLOW, Enum.Material.SmoothPlastic, false)
	tape.Transparency = 0.18
	makePart(model, "BossThresholdFloorEdge", Vector3.new(3.4, 0.08, zR - zL + 1), Vector3.new(x, LAYER_CONTAM + 0.02, 0), LAB_DARK, Enum.Material.SmoothPlastic, false).Transparency = 0.1
end

-- ---- Gegner-Tunnel Struktur ----------------------------------------------

-- Designt die Wand DIREKT um den Mob/die Gegner-Zelle -- fuer ALLE Areas,
-- mit Thema-Akzent und mit der Tiefe steigender Kontamination. Cell 5
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

		-- Hazard-Streifen am Boden um den Boss-Pad (gelb-schwarz, dramatisch).
		for k = 0, 5 do
			local cz = -16 + k * 6.4
			local stripeColor = if k % 2 == 0 then LAB_WARNING_YELLOW else LAB_DARK
			makePart(model, "BossPadFloorStripe", Vector3.new(26, 0.08, 1.4), Vector3.new(basePos.X, CHAMBER_TOP + 0.08, z + cz), stripeColor, Enum.Material.SmoothPlastic, false).Transparency = 0.25
		end

		-- Akzent-Neon-Rahmen um den Boss-Pad (Thema-Akzent).
		for _, dx in ipairs({ -12, 12 }) do
			neonStrip(model, Vector3.new(0.5, 0.08, 32), Vector3.new(basePos.X + dx, CHAMBER_TOP + 0.18, z), accent, 0.32)
		end
		for _, dz in ipairs({ -16, 16 }) do
			neonStrip(model, Vector3.new(24, 0.08, 0.5), Vector3.new(basePos.X, CHAMBER_TOP + 0.18, z + dz), accent, 0.32)
		end

		-- Deckenstrahler ueber dem Boss: heller, breiter Spot.
		local rig = makePart(model, "BossSpotRig", Vector3.new(8, 0.7, 8), Vector3.new(basePos.X, FLOOR_Y + L.WallHeight + BACTERIA_CEILING_LIFT - 4, z), LAB_DARK, Enum.Material.Metal, false)
		local spot = makePart(model, "BossSpotLens", Vector3.new(5.4, 0.4, 5.4), rig.Position + Vector3.new(0, -0.55, 0), tint(accent, Color3.fromRGB(248, 248, 230), 0.4), Enum.Material.Neon, false)
		spot.Transparency = 0.12
		local spotLight = Instance.new("SpotLight")
		spotLight.Brightness = 2.4
		spotLight.Range = 26
		spotLight.Angle = 70
		spotLight.Face = Enum.NormalId.Bottom
		spotLight.Color = tint(accent, Color3.fromRGB(255, 252, 240), 0.5)
		spotLight.Parent = spot

		-- Heavy-Glas-Seitenwaende (boss-spezifisch breiter und hoeher) ZUSAETZLICH
		-- zu den normalen Schienen, weiter aussen platziert -> doppelte Hülle.
		for _, dz in ipairs({ -32, 32 }) do
			local wall = makePart(model, "BossRoomGlass", Vector3.new(30, 14, 0.5), Vector3.new(basePos.X, FLOOR_Y + 7.5, z + dz), tint(accent, LAB_DARK, 0.35), Enum.Material.Glass, false)
			wall.Transparency = 0.7
			makePart(model, "BossRoomGlassFrameTop", Vector3.new(30.6, 0.55, 0.7), Vector3.new(basePos.X, FLOOR_Y + 14.4, z + dz), LAB_DARK, Enum.Material.Metal, false)
			makePart(model, "BossRoomGlassFrameBottom", Vector3.new(30.6, 0.55, 0.7), Vector3.new(basePos.X, FLOOR_Y + 0.6, z + dz), LAB_DARK, Enum.Material.Metal, false)
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
			child.Transparency = 0.2
		elseif child.Name == "CeilBeam" then
			child.Position += Vector3.new(0, BACTERIA_CEILING_LIFT, 0)
			child.Size = Vector3.new(10, 0.35, FLOOR_SIZE_Z - 52)
			child.Transparency = 0.72
			for _, light in ipairs(child:GetChildren()) do
				if light:IsA("PointLight") then
					light.Brightness = 1.6
					light.Range = 40
					light.Color = Color3.fromRGB(232, 218, 255)
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
		-- Area 1: BACTERIA LAB (unangetastet).
		local tank = p("SideSampleTank", Vector3.new(8, 13, 8), Vector3.new(x, FLOOR_Y + 6.5, z), tint(LAB_OLIVE, accent, 0.22), Enum.Material.Glass)
		tank.Shape = Enum.PartType.Cylinder
		tank.Orientation = Vector3.new(0, 0, 90)
		tank.Transparency = 0.5
		p("TankBase", Vector3.new(9, 0.7, 9), Vector3.new(x, FLOOR_Y + 0.5, z), LAB_TRIM, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		p("TankTop", Vector3.new(9, 0.7, 9), Vector3.new(x, FLOOR_Y + 12.6, z), LAB_TRIM, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
	elseif id == "QuarantineScanner" then
		-- Area 2: Decon-Scanner-Saeule mit gelb-schwarzen Warnstreifen.
		local hazard = LAB_WARNING_YELLOW
		p("ScannerPillar", Vector3.new(2.4, 14, 2.4), Vector3.new(x, FLOOR_Y + 7, z), LAB_DARK, Enum.Material.Metal)
		for i = 0, 5 do
			local band = p("ScannerHazardBand", Vector3.new(2.7, 0.9, 2.7), Vector3.new(x, FLOOR_Y + 1.5 + i * 2.2, z), if i % 2 == 0 then hazard else LAB_DARK, Enum.Material.SmoothPlastic)
		end
		p("ScannerCapBase", Vector3.new(4, 0.5, 4), Vector3.new(x, FLOOR_Y + 0.25, z), LAB_DARK, Enum.Material.Metal)
		p("ScannerHead", Vector3.new(4.2, 1.6, 4.2), Vector3.new(x, FLOOR_Y + 14.5, z), Color3.fromRGB(56, 60, 62), Enum.Material.Metal)
		local lens = p("ScannerLens", Vector3.new(2, 0.5, 2), Vector3.new(x, FLOOR_Y + 13.6, z), tint(hazard, accent, 0.4), Enum.Material.Neon)
		lens.Shape = Enum.PartType.Cylinder
		lens.Orientation = Vector3.new(0, 0, 90)
		lens.Transparency = 0.25
		local plate = p("QuarantinePlate", Vector3.new(3.6, 2.4, 0.4), Vector3.new(x, FLOOR_Y + 11, z + 1.3), Color3.fromRGB(36, 38, 38), Enum.Material.Metal)
		label(plate, "QUARANTINE", hazard, 26, UDim2.fromOffset(140, 32), Vector3.new(0, 0, 0))
	elseif id == "MutationDNA" then
		-- Area 3: Glas-Vat mit DNA-Helix-Sample.
		local tank = p("MutationVat", Vector3.new(9, 13, 9), Vector3.new(x, FLOOR_Y + 6.7, z), tint(accent, LAB_WHITE, 0.35), Enum.Material.Glass)
		tank.Shape = Enum.PartType.Cylinder
		tank.Orientation = Vector3.new(0, 0, 90)
		tank.Transparency = 0.55
		p("MutationVatBase", Vector3.new(10, 1.1, 10), Vector3.new(x, FLOOR_Y + 0.6, z), LAB_DARK, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		p("MutationVatCap", Vector3.new(10, 1, 10), Vector3.new(x, FLOOR_Y + 13.5, z), LAB_TRIM, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		for i = 0, 6 do
			local t = i / 6
			local ang = t * math.pi * 2
			local node = p("DNANode" .. i, Vector3.new(1.1, 1.1, 1.1), Vector3.new(x + math.cos(ang) * 1.6, FLOOR_Y + 2.5 + t * 9, z + math.sin(ang) * 0.6), tint(accent, LAB_WHITE, 0.2), Enum.Material.Neon)
			node.Shape = Enum.PartType.Ball
			node.Transparency = 0.18
			local mirror = p("DNANodeM" .. i, Vector3.new(0.95, 0.95, 0.95), Vector3.new(x - math.cos(ang) * 1.6, FLOOR_Y + 2.5 + t * 9, z - math.sin(ang) * 0.6), tint(accent, LAB_OLIVE, 0.45), Enum.Material.Neon)
			mirror.Shape = Enum.PartType.Ball
			mirror.Transparency = 0.28
		end
		local glow = Instance.new("PointLight")
		glow.Brightness = 0.32
		glow.Range = 12
		glow.Color = tint(accent, LAB_WHITE, 0.45)
		glow.Parent = tank
	elseif id == "ProcessingMachine" then
		-- Area 4: industrielle Prozessor-Einheit mit Auspuff und Ventilen.
		local body = p("ProcUnitBody", Vector3.new(9, 9, 6.5), Vector3.new(x, FLOOR_Y + 4.7, z), Color3.fromRGB(80, 86, 90), Enum.Material.Metal)
		p("ProcUnitTop", Vector3.new(9.6, 0.8, 7.2), Vector3.new(x, FLOOR_Y + 9.5, z), LAB_DARK, Enum.Material.Metal)
		p("ProcUnitBase", Vector3.new(10.2, 1.4, 7.6), Vector3.new(x, FLOOR_Y + 0.7, z), LAB_DARK, Enum.Material.Metal)
		local hazardBand = p("ProcHazardBand", Vector3.new(9.2, 1.1, 6.7), Vector3.new(x, FLOOR_Y + 2.3, z), accent, Enum.Material.SmoothPlastic)
		hazardBand.Transparency = 0.05
		local screen = p("ProcScreen", Vector3.new(3.2, 2.2, 0.3), Vector3.new(x, FLOOR_Y + 6.5, z + 3.4), Color3.fromRGB(34, 38, 40), Enum.Material.Metal)
		label(screen, "PROCESS\nACTIVE", accent, 22, UDim2.fromOffset(110, 38), Vector3.new(0, 0, 0))
		for _, vx in ipairs({ -3, 0, 3 }) do
			local pipe = p("ProcExhaust", Vector3.new(1.4, 7, 1.4), Vector3.new(x + vx, FLOOR_Y + 13, z), Color3.fromRGB(92, 96, 96), Enum.Material.Metal)
			pipe.Shape = Enum.PartType.Cylinder
			pipe.Orientation = Vector3.new(0, 0, 90)
			p("ProcExhaustCap", Vector3.new(1.8, 0.8, 1.8), Vector3.new(x + vx, FLOOR_Y + 16.5, z), LAB_DARK, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		end
		local valve = p("ProcValve", Vector3.new(2.2, 2.2, 0.8), Vector3.new(x - 3.2, FLOOR_Y + 3.4, z + 3.4), accent, Enum.Material.Metal)
		valve.Shape = Enum.PartType.Cylinder
		valve.Orientation = Vector3.new(0, 0, 90)
	elseif id == "CryoCapsule" then
		-- Area 5: hohe, gefrorene Kryo-Kapsel mit blauem Innenkern.
		p("CryoCapBase", Vector3.new(8, 1.4, 8), Vector3.new(x, FLOOR_Y + 0.7, z), LAB_DARK, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		p("CryoCapBaseRing", Vector3.new(9, 0.4, 9), Vector3.new(x, FLOOR_Y + 1.6, z), tint(accent, LAB_WHITE, 0.4), Enum.Material.SmoothPlastic).Shape = Enum.PartType.Cylinder
		local glass = p("CryoCapsule", Vector3.new(6.5, 15, 6.5), Vector3.new(x, FLOOR_Y + 8.5, z), tint(accent, LAB_WHITE, 0.55), Enum.Material.Glass)
		glass.Shape = Enum.PartType.Cylinder
		glass.Orientation = Vector3.new(0, 0, 90)
		glass.Transparency = 0.7
		local frost = p("CryoFrostLayer", Vector3.new(6.8, 15.2, 6.8), Vector3.new(x, FLOOR_Y + 8.5, z), Color3.fromRGB(220, 232, 238), Enum.Material.Ice)
		frost.Shape = Enum.PartType.Cylinder
		frost.Orientation = Vector3.new(0, 0, 90)
		frost.Transparency = 0.78
		local core = p("CryoInnerCore", Vector3.new(2.4, 11, 2.4), Vector3.new(x, FLOOR_Y + 8.5, z), tint(accent, Color3.fromRGB(200, 230, 245), 0.3), Enum.Material.Neon)
		core.Shape = Enum.PartType.Cylinder
		core.Orientation = Vector3.new(0, 0, 90)
		core.Transparency = 0.25
		p("CryoCapTop", Vector3.new(8.2, 1.4, 8.2), Vector3.new(x, FLOOR_Y + 16.4, z), LAB_TRIM, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		local lamp = Instance.new("PointLight")
		lamp.Brightness = 0.4
		lamp.Range = 14
		lamp.Color = tint(accent, Color3.fromRGB(220, 240, 250), 0.45)
		lamp.Parent = core
		local mist = p("CryoFloorMist", Vector3.new(9, 0.06, 9), Vector3.new(x, FLOOR_Y + 0.18, z), Color3.fromRGB(220, 232, 238), Enum.Material.SmoothPlastic)
		mist.Shape = Enum.PartType.Cylinder
		mist.Orientation = Vector3.new(0, 0, 90)
		mist.Transparency = 0.55
	elseif id == "ToxicReactor" then
		-- Area 6: kompakter Reaktor-Pillar mit gruenem Energiekern.
		local col = p("ReactorPillar", Vector3.new(6, 17, 6), Vector3.new(x, FLOOR_Y + 8.5, z), LAB_DARK, Enum.Material.Metal)
		col.Shape = Enum.PartType.Cylinder
		col.Orientation = Vector3.new(0, 0, 90)
		local glass = p("ReactorGlass", Vector3.new(4.4, 13, 4.4), Vector3.new(x, FLOOR_Y + 8.5, z), tint(accent, LAB_WHITE, 0.4), Enum.Material.Glass)
		glass.Shape = Enum.PartType.Cylinder
		glass.Orientation = Vector3.new(0, 0, 90)
		glass.Transparency = 0.55
		local core = p("ReactorCoreBall", Vector3.new(3, 3, 3), Vector3.new(x, FLOOR_Y + 8.5, z), tint(accent, Color3.fromRGB(225, 232, 220), 0.25), Enum.Material.Neon)
		core.Shape = Enum.PartType.Ball
		core.Transparency = 0.1
		for i = 0, 3 do
			local ang = i * math.pi / 2
			p("ReactorPipe" .. i, Vector3.new(0.7, 5.5, 0.7), Vector3.new(x + math.cos(ang) * 3.6, FLOOR_Y + 14, z + math.sin(ang) * 3.6), Color3.fromRGB(86, 92, 94), Enum.Material.Metal)
		end
		p("ReactorBaseCap", Vector3.new(8, 1.2, 8), Vector3.new(x, FLOOR_Y + 0.6, z), Color3.fromRGB(58, 62, 64), Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		local lamp = Instance.new("PointLight")
		lamp.Brightness = 0.55
		lamp.Range = 16
		lamp.Color = tint(accent, Color3.fromRGB(220, 240, 200), 0.4)
		lamp.Parent = core
	elseif id == "SporePod" then
		-- Area 7: Glas-Dome mit infiziertem Spore-Wachstum.
		p("SporeDomeBase", Vector3.new(10, 1.2, 10), Vector3.new(x, FLOOR_Y + 0.6, z), LAB_DARK, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		local dome = p("SporeDome", Vector3.new(9, 9, 9), Vector3.new(x, FLOOR_Y + 5.5, z), tint(accent, LAB_WHITE, 0.5), Enum.Material.Glass)
		dome.Shape = Enum.PartType.Ball
		dome.Transparency = 0.6
		local stalk = p("SporeStalk", Vector3.new(1.3, 6, 1.3), Vector3.new(x, FLOOR_Y + 4, z), tint(LAB_OLIVE, accent, 0.4), Enum.Material.SmoothPlastic)
		stalk.Shape = Enum.PartType.Cylinder
		stalk.Orientation = Vector3.new(0, 0, 90)
		for i = 1, 4 do
			local ang = i * math.pi / 2
			local pod = p("SporeBlossom" .. i, Vector3.new(1.6, 1.6, 1.6), Vector3.new(x + math.cos(ang) * 1.6, FLOOR_Y + 5 + (i % 2) * 1.2, z + math.sin(ang) * 1.6), tint(accent, Color3.fromRGB(184, 122, 220), 0.25), Enum.Material.Neon)
			pod.Shape = Enum.PartType.Ball
			pod.Transparency = 0.18
		end
		local cap = p("SporeCap", Vector3.new(3.2, 1.6, 3.2), Vector3.new(x, FLOOR_Y + 8.6, z), tint(accent, Color3.fromRGB(180, 120, 220), 0.35), Enum.Material.SmoothPlastic)
		cap.Shape = Enum.PartType.Ball
		cap.Transparency = 0.1
		local glow = Instance.new("PointLight")
		glow.Brightness = 0.35
		glow.Range = 12
		glow.Color = tint(accent, Color3.fromRGB(190, 150, 220), 0.35)
		glow.Parent = cap
		local roots = p("SporeFloorRoots", Vector3.new(8, 0.06, 8), Vector3.new(x, FLOOR_Y + 0.2, z), tint(LAB_OLIVE, accent, 0.4), Enum.Material.SmoothPlastic)
		roots.Shape = Enum.PartType.Cylinder
		roots.Orientation = Vector3.new(0, 0, 90)
		roots.Transparency = 0.4
	elseif id == "BlackSiteChamber" then
		-- Area 8: dunkle, klassifizierte Versuchskammer mit Rotglas.
		p("BSiteBase", Vector3.new(8, 1.4, 8), Vector3.new(x, FLOOR_Y + 0.7, z), Color3.fromRGB(18, 18, 22), Enum.Material.Metal)
		local frame = p("BSiteFrame", Vector3.new(7.6, 15, 4.4), Vector3.new(x, FLOOR_Y + 8, z), Color3.fromRGB(22, 22, 26), Enum.Material.Metal)
		local glass = p("BSiteGlass", Vector3.new(5.5, 11, 0.45), Vector3.new(x, FLOOR_Y + 8, z + 2.3), tint(accent, Color3.fromRGB(20, 20, 24), 0.55), Enum.Material.Glass)
		glass.Transparency = 0.42
		local glow = p("BSiteInnerGlow", Vector3.new(4, 8, 1.4), Vector3.new(x, FLOOR_Y + 7.5, z + 1.2), tint(accent, Color3.fromRGB(50, 16, 24), 0.35), Enum.Material.Neon)
		glow.Transparency = 0.45
		p("BSiteTopBar", Vector3.new(8, 1.1, 4.6), Vector3.new(x, FLOOR_Y + 15.6, z), LAB_DARK, Enum.Material.Metal)
		local plate = p("BSitePlate", Vector3.new(3.2, 1.6, 0.4), Vector3.new(x, FLOOR_Y + 4.6, z + 2.4), Color3.fromRGB(18, 18, 18), Enum.Material.Metal)
		label(plate, "RESTRICTED", accent, 28, UDim2.fromOffset(140, 26), Vector3.new(0, 0, 0))
		p("BSiteRedLamp", Vector3.new(0.9, 0.9, 0.9), Vector3.new(x, FLOOR_Y + 14.4, z + 2.4), accent, Enum.Material.Neon).Shape = Enum.PartType.Ball
		local lamp = Instance.new("PointLight")
		lamp.Brightness = 0.4
		lamp.Range = 11
		lamp.Color = tint(accent, Color3.fromRGB(140, 30, 40), 0.4)
		lamp.Parent = glow
	elseif id == "OmegaHelix" then
		-- Area 9: golden-weisser DNA-Helix-Pillar, hochwertig und premium.
		p("OmegaBase", Vector3.new(9, 1.2, 9), Vector3.new(x, FLOOR_Y + 0.6, z), Color3.fromRGB(206, 210, 214), Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		p("OmegaBaseRing", Vector3.new(10, 0.4, 10), Vector3.new(x, FLOOR_Y + 1.4, z), accent, Enum.Material.SmoothPlastic).Shape = Enum.PartType.Cylinder
		local glass = p("OmegaGlass", Vector3.new(5.2, 15, 5.2), Vector3.new(x, FLOOR_Y + 9, z), tint(accent, Color3.fromRGB(245, 240, 226), 0.5), Enum.Material.Glass)
		glass.Shape = Enum.PartType.Cylinder
		glass.Orientation = Vector3.new(0, 0, 90)
		glass.Transparency = 0.62
		for i = 0, 9 do
			local t = i / 9
			local ang = t * math.pi * 3.2
			local node = p("OmegaNode" .. i, Vector3.new(0.9, 0.9, 0.9), Vector3.new(x + math.cos(ang) * 1.6, FLOOR_Y + 2.5 + t * 13, z + math.sin(ang) * 0.7), accent, Enum.Material.Neon)
			node.Shape = Enum.PartType.Ball
			node.Transparency = 0.12
			local mirror = p("OmegaNodeM" .. i, Vector3.new(0.9, 0.9, 0.9), Vector3.new(x - math.cos(ang) * 1.6, FLOOR_Y + 2.5 + t * 13, z - math.sin(ang) * 0.7), Color3.fromRGB(245, 240, 220), Enum.Material.Neon)
			mirror.Shape = Enum.PartType.Ball
			mirror.Transparency = 0.18
		end
		p("OmegaCapTop", Vector3.new(7, 1.2, 7), Vector3.new(x, FLOOR_Y + 17, z), Color3.fromRGB(206, 210, 214), Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		local lamp = Instance.new("PointLight")
		lamp.Brightness = 0.55
		lamp.Range = 16
		lamp.Color = tint(accent, Color3.fromRGB(245, 230, 200), 0.35)
		lamp.Parent = glass
	else
		-- Area 10: FinalVirusCore - massiver roter Reaktor-Pillar.
		local base = p("FinalReactorBase", Vector3.new(12, 1.4, 12), Vector3.new(x, FLOOR_Y + 0.7, z), Color3.fromRGB(18, 16, 18), Enum.Material.Metal)
		base.Shape = Enum.PartType.Cylinder
		base.Orientation = Vector3.new(0, 0, 90)
		p("FinalReactorBaseRing", Vector3.new(13, 0.4, 13), Vector3.new(x, FLOOR_Y + 1.5, z), accent, Enum.Material.SmoothPlastic).Shape = Enum.PartType.Cylinder
		local glass = p("FinalReactorGlass", Vector3.new(8, 20, 8), Vector3.new(x, FLOOR_Y + 10.5, z), tint(accent, Color3.fromRGB(36, 22, 26), 0.45), Enum.Material.Glass)
		glass.Shape = Enum.PartType.Cylinder
		glass.Transparency = 0.5
		local core = p("FinalReactorCore", Vector3.new(4.6, 13, 4.6), Vector3.new(x, FLOOR_Y + 10.5, z), tint(accent, Color3.fromRGB(255, 200, 200), 0.2), Enum.Material.Neon)
		core.Shape = Enum.PartType.Cylinder
		core.Transparency = 0.05
		for i = 0, 3 do
			local ang = i * math.pi / 2 + math.pi / 4
			p("FinalReactorRib" .. i, Vector3.new(0.9, 18, 0.9), Vector3.new(x + math.cos(ang) * 3.6, FLOOR_Y + 10, z + math.sin(ang) * 3.6), Color3.fromRGB(28, 22, 24), Enum.Material.Metal)
		end
		p("FinalReactorTop", Vector3.new(10, 1.2, 10), Vector3.new(x, FLOOR_Y + 19, z), Color3.fromRGB(18, 16, 18), Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		local fl = Instance.new("PointLight")
		fl.Brightness = 0.85
		fl.Range = 20
		fl.Color = tint(accent, Color3.fromRGB(255, 200, 200), 0.35)
		fl.Parent = core
		p("FinalReactorRedLamp", Vector3.new(1.4, 1.4, 1.4), Vector3.new(x, FLOOR_Y + 21, z), accent, Enum.Material.Neon).Shape = Enum.PartType.Ball
	end
end

-- ---- Eingangsbogen pro Area (nur Area 2..10) -----------------------------
-- Sitzt direkt nach dem Area-Gate und sorgt fuer das "Boah, neues Gebiet"-
-- Reveal-Moment. Spannt nicht den Laufweg (Z=0) ein -- die Pfeiler stehen am
-- Rand des Korridors (z = +/-34), das Querbalken ueberspannt den Pfad.
local function buildAreaEntranceArch(parent, area, hallX, theme, accent)
	local deco = makeFolder("AreaEntranceArch", parent)
	local archX = hallX + L.GateOffsetX + 20 -- 20 Studs hinter dem Gate
	local archZL, archZR = -34, 34
	local pillarHeight = 28
	local pillarWidth = 3.6
	local pillarDepth = 4.4
	local archTopY = FLOOR_Y + pillarHeight

	local function p(name, size, pos, color, mat, collide)
		return makePart(deco, name, size, pos, color, mat, collide == true)
	end

	-- Pfeiler links/rechts.
	for _, pz in ipairs({ archZL, archZR }) do
		p("ArchPillar", Vector3.new(pillarWidth, pillarHeight, pillarDepth), Vector3.new(archX, FLOOR_Y + pillarHeight / 2, pz), Color3.fromRGB(56, 60, 64), Enum.Material.Metal)
		p("ArchPillarCap", Vector3.new(pillarWidth + 1.2, 0.7, pillarDepth + 1.2), Vector3.new(archX, FLOOR_Y + pillarHeight - 0.35, pz), LAB_DARK, Enum.Material.Metal)
		p("ArchPillarFoot", Vector3.new(pillarWidth + 1.6, 1.2, pillarDepth + 1.6), Vector3.new(archX, FLOOR_Y + 0.6, pz), LAB_DARK, Enum.Material.Metal)
		-- Akzent-LED auf der Pfeiler-Innenseite.
		local insetZ = pz + (if pz < 0 then 1 else -1) * (pillarDepth / 2 + 0.1)
		neonStrip(deco, Vector3.new(0.4, pillarHeight - 6, 0.4), Vector3.new(archX, FLOOR_Y + pillarHeight / 2, insetZ), accent, 0.45)
	end

	-- Querbalken ueber dem Laufweg.
	local beam = p("ArchTopBeam", Vector3.new(pillarWidth + 2, 3.2, archZR - archZL + pillarDepth), Vector3.new(archX, archTopY + 1.6, 0), Color3.fromRGB(28, 30, 32), Enum.Material.Metal)
	p("ArchTopBeamRim", Vector3.new(pillarWidth + 2.6, 0.6, archZR - archZL + pillarDepth + 0.6), Vector3.new(archX, archTopY + 3.3, 0), LAB_DARK, Enum.Material.Metal)

	-- Akzent-Lichtleiste unter dem Balken.
	neonStrip(deco, Vector3.new(0.6, 0.4, archZR - archZL - 4), Vector3.new(archX, archTopY + 0.2, 0), accent, 0.4)

	-- Frontschild mit Area-Bezeichnung (Spielrichtung zugewandt).
	local signFront = p("ArchSignFront", Vector3.new(pillarWidth + 1.4, 2.6, 12), Vector3.new(archX - 1.6, archTopY - 1.3, 0), Color3.fromRGB(18, 20, 22), Enum.Material.Metal)
	label(signFront, theme.wallText, accent:Lerp(Color3.fromRGB(245, 248, 244), 0.35), 80, UDim2.fromOffset(360, 70), Vector3.new(-1, 0, 0))
	-- Rueckschild (sichtbar fuer den Spieler beim Zurueckblicken).
	local signBack = p("ArchSignBack", Vector3.new(pillarWidth + 1.4, 2.6, 12), Vector3.new(archX + 1.6, archTopY - 1.3, 0), Color3.fromRGB(18, 20, 22), Enum.Material.Metal)
	label(signBack, "ZONE " .. tostring(area.index), Color3.fromRGB(220, 225, 220), 60, UDim2.fromOffset(240, 60), Vector3.new(1, 0, 0))

	-- Bodenmarkierung direkt am Eingang -> klare Schwelle ins Gebiet.
	local thresholdColor = if theme.id == "BlackSite" then Color3.fromRGB(120, 30, 40) else accent
	p("ArchFloorThreshold", Vector3.new(2.4, 0.1, archZR - archZL), Vector3.new(archX, LAYER_CONTAM, 0), LAB_DARK, Enum.Material.SmoothPlastic).Transparency = 0.05
	local stripe = p("ArchFloorStripe", Vector3.new(1.2, 0.12, archZR - archZL - 4), Vector3.new(archX, LAYER_CONTAM + 0.04, 0), thresholdColor, Enum.Material.SmoothPlastic)
	stripe.Transparency = 0.3

	-- Pro-Area Akzentlampe oben am Balken.
	local lamp = p("ArchTopLamp", Vector3.new(1.4, 1.4, 1.4), Vector3.new(archX, archTopY + 3.8, 0), accent, Enum.Material.Neon)
	lamp.Shape = Enum.PartType.Ball
	lamp.Transparency = 0.18
	local light = Instance.new("PointLight")
	light.Brightness = 0.5
	light.Range = 18
	light.Color = accent:Lerp(Color3.fromRGB(240, 240, 230), 0.45)
	light.Parent = lamp
end

-- ---- Hero-Centerpiece pro Area (nur Area 2..10) --------------------------
-- Eine einzigartige, deutlich erkennbare Landmark in der Halle. Steht NICHT
-- im Laufweg (Z=0..+/-9) und nicht in den Egg-Stationen (Z=+96). Positioniert
-- in der "Tiefe" der Halle (z = +28), zwischen den wiederkehrenden SideProp-
-- Slots, damit die Silhouette der Area dominant bleibt.
local function buildAreaCenterpiece(parent, area, hallX, theme, accent)
	if area.index <= 1 then
		return
	end
	local deco = makeFolder("AreaCenterpiece", parent)
	local cx = hallX
	local cz = 28 -- inside back tunnel wall (wall at z=+38), nahe an Side-Slots
	local function p(name, size, pos, color, mat, collide)
		return makePart(deco, name, size, pos, color, mat, collide == true)
	end

	local id = theme.id

	-- Sockel + Hintergrundpaneel sind universell -- gibt jeder Landmark Halt.
	local pad = p("CenterPad", Vector3.new(18, 0.5, 12), Vector3.new(cx, FLOOR_Y + 0.25, cz), tint(LAB_PANEL, accent, 0.18), Enum.Material.SmoothPlastic)
	pad.Transparency = 0.05
	p("CenterPadEdge", Vector3.new(18.6, 0.1, 12.6), Vector3.new(cx, FLOOR_Y + 0.55, cz), accent:Lerp(LAB_DARK, 0.45), Enum.Material.SmoothPlastic).Transparency = 0.35
	local backplate = p("CenterBackplate", Vector3.new(20, 14, 0.6), Vector3.new(cx, FLOOR_Y + 7, cz + 6.2), Color3.fromRGB(34, 38, 40), Enum.Material.Metal)
	label(backplate, theme.wallText, accent:Lerp(Color3.fromRGB(238, 242, 236), 0.35), 80, UDim2.fromOffset(360, 60), Vector3.new(0, 4, 0))

	if id == "Quarantine" then
		-- Decon-Bogen mit zwei Saeulen, Scanner-Strahl und Warnstreifen.
		for _, dx in ipairs({ -6, 6 }) do
			local pillar = p("QArchPillar", Vector3.new(2.4, 16, 2.4), Vector3.new(cx + dx, FLOOR_Y + 8, cz), LAB_DARK, Enum.Material.Metal)
			for k = 0, 6 do
				p("QArchStripe", Vector3.new(2.6, 0.7, 2.6), Vector3.new(cx + dx, FLOOR_Y + 1.5 + k * 2.2, cz), if k % 2 == 0 then LAB_WARNING_YELLOW else LAB_DARK, Enum.Material.SmoothPlastic)
			end
		end
		local crossBar = p("QArchCross", Vector3.new(14, 2.4, 2.4), Vector3.new(cx, FLOOR_Y + 16.6, cz), Color3.fromRGB(40, 44, 46), Enum.Material.Metal)
		local scanBeam = p("QScanBeam", Vector3.new(11, 0.5, 0.5), Vector3.new(cx, FLOOR_Y + 8, cz), LAB_WARNING_YELLOW, Enum.Material.Neon)
		scanBeam.Transparency = 0.35
		local lamp = p("QArchLamp", Vector3.new(1.2, 1.2, 1.2), Vector3.new(cx, FLOOR_Y + 18.4, cz), LAB_WARNING_RED, Enum.Material.Neon)
		lamp.Shape = Enum.PartType.Ball
		local light = Instance.new("PointLight"); light.Brightness = 0.55; light.Range = 16; light.Color = Color3.fromRGB(255, 220, 120); light.Parent = scanBeam
	elseif id == "MutationResearch" then
		-- Grosse DNA-Helix in Glaszylinder.
		p("DNATankBase", Vector3.new(10, 1.2, 10), Vector3.new(cx, FLOOR_Y + 0.6, cz), LAB_DARK, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		local glass = p("DNATankGlass", Vector3.new(7, 20, 7), Vector3.new(cx, FLOOR_Y + 11, cz), tint(accent, LAB_WHITE, 0.45), Enum.Material.Glass)
		glass.Shape = Enum.PartType.Cylinder
		glass.Orientation = Vector3.new(0, 0, 90)
		glass.Transparency = 0.6
		for i = 0, 13 do
			local t = i / 13
			local ang = t * math.pi * 3.4
			local node = p("DNANode" .. i, Vector3.new(1.2, 1.2, 1.2), Vector3.new(cx + math.cos(ang) * 2.1, FLOOR_Y + 2 + t * 18, cz + math.sin(ang) * 0.8), tint(accent, LAB_WHITE, 0.2), Enum.Material.Neon)
			node.Shape = Enum.PartType.Ball
			node.Transparency = 0.12
			local mirror = p("DNANodeM" .. i, Vector3.new(1.05, 1.05, 1.05), Vector3.new(cx - math.cos(ang) * 2.1, FLOOR_Y + 2 + t * 18, cz - math.sin(ang) * 0.8), tint(LAB_OLIVE, accent, 0.6), Enum.Material.Neon)
			mirror.Shape = Enum.PartType.Ball
			mirror.Transparency = 0.2
			if i % 2 == 0 then
				local rung = p("DNARung" .. i, Vector3.new(4.2, 0.4, 0.4), Vector3.new(cx, FLOOR_Y + 2 + t * 18, cz + math.sin(ang) * 0.3), tint(accent, LAB_WHITE, 0.55), Enum.Material.Neon)
				rung.Transparency = 0.45
			end
		end
		p("DNATankTop", Vector3.new(10, 1.2, 10), Vector3.new(cx, FLOOR_Y + 21.3, cz), LAB_TRIM, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		local lamp = Instance.new("PointLight"); lamp.Brightness = 0.55; lamp.Range = 22; lamp.Color = tint(accent, LAB_WHITE, 0.45); lamp.Parent = glass
	elseif id == "Processing" then
		-- Industrie-Reaktor: schwere Maschinerie + Rohre + Auspuff.
		p("ProcReactorBase", Vector3.new(14, 1.6, 11), Vector3.new(cx, FLOOR_Y + 0.8, cz), LAB_DARK, Enum.Material.Metal)
		p("ProcReactorBody", Vector3.new(12, 14, 9), Vector3.new(cx, FLOOR_Y + 8, cz), Color3.fromRGB(78, 82, 86), Enum.Material.Metal)
		p("ProcReactorTop", Vector3.new(13, 1.2, 10), Vector3.new(cx, FLOOR_Y + 15.6, cz), Color3.fromRGB(38, 40, 42), Enum.Material.Metal)
		for i = -1, 1 do
			local s = p("ProcReactorBand", Vector3.new(12.4, 1.1, 9.4), Vector3.new(cx, FLOOR_Y + 4 + i * 4, cz), accent, Enum.Material.SmoothPlastic)
			s.Transparency = 0.1
		end
		for _, dx in ipairs({ -4, 0, 4 }) do
			local stack = p("ProcStack", Vector3.new(1.7, 9, 1.7), Vector3.new(cx + dx, FLOOR_Y + 20, cz), Color3.fromRGB(80, 84, 86), Enum.Material.Metal)
			stack.Shape = Enum.PartType.Cylinder
			stack.Orientation = Vector3.new(0, 0, 90)
			p("ProcStackTop", Vector3.new(2.4, 0.8, 2.4), Vector3.new(cx + dx, FLOOR_Y + 24.5, cz), LAB_DARK, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		end
		local glow = p("ProcReactorGlow", Vector3.new(6, 5, 0.4), Vector3.new(cx, FLOOR_Y + 8, cz - 4.5), tint(accent, Color3.fromRGB(245, 200, 140), 0.2), Enum.Material.Neon)
		glow.Transparency = 0.35
		local panel = p("ProcReactorPanel", Vector3.new(4.4, 2.6, 0.4), Vector3.new(cx + 2.8, FLOOR_Y + 4.2, cz - 4.55), Color3.fromRGB(24, 26, 28), Enum.Material.Metal)
		label(panel, "PROCESS\nMODULE", accent, 26, UDim2.fromOffset(150, 50), Vector3.new(0, 0, 0))
		for _, dx in ipairs({ -5.5, 5.5 }) do
			p("ProcReactorRib", Vector3.new(1.4, 14, 1.4), Vector3.new(cx + dx, FLOOR_Y + 8, cz), LAB_DARK, Enum.Material.Metal)
		end
		local lamp = Instance.new("PointLight"); lamp.Brightness = 0.4; lamp.Range = 14; lamp.Color = accent; lamp.Parent = glow
	elseif id == "Cryo" then
		-- Drei tall cryo capsules + frosted base + cold mist.
		p("CryoStageBase", Vector3.new(18, 1.4, 11), Vector3.new(cx, FLOOR_Y + 0.7, cz), LAB_DARK, Enum.Material.Metal)
		p("CryoStagePlate", Vector3.new(16, 0.18, 9), Vector3.new(cx, FLOOR_Y + 1.5, cz), tint(accent, LAB_WHITE, 0.6), Enum.Material.SmoothPlastic).Transparency = 0.1
		for i = -1, 1 do
			local px = cx + i * 5
			p("CryoCapBaseRing", Vector3.new(4.6, 0.4, 4.6), Vector3.new(px, FLOOR_Y + 1.9, cz), accent:Lerp(LAB_WHITE, 0.55), Enum.Material.SmoothPlastic).Shape = Enum.PartType.Cylinder
			local glass = p("CryoMainCap", Vector3.new(3.6, 17, 3.6), Vector3.new(px, FLOOR_Y + 10, cz), tint(accent, LAB_WHITE, 0.55), Enum.Material.Glass)
			glass.Shape = Enum.PartType.Cylinder
			glass.Orientation = Vector3.new(0, 0, 90)
			glass.Transparency = 0.68
			local frost = p("CryoMainFrost", Vector3.new(3.8, 17.2, 3.8), Vector3.new(px, FLOOR_Y + 10, cz), Color3.fromRGB(220, 232, 238), Enum.Material.Ice)
			frost.Shape = Enum.PartType.Cylinder
			frost.Orientation = Vector3.new(0, 0, 90)
			frost.Transparency = 0.8
			local core = p("CryoMainCore", Vector3.new(1.6, 13, 1.6), Vector3.new(px, FLOOR_Y + 10, cz), tint(accent, Color3.fromRGB(210, 235, 250), 0.3), Enum.Material.Neon)
			core.Shape = Enum.PartType.Cylinder
			core.Orientation = Vector3.new(0, 0, 90)
			core.Transparency = 0.25
			p("CryoMainCapTop", Vector3.new(4.6, 1.2, 4.6), Vector3.new(px, FLOOR_Y + 18.6, cz), LAB_TRIM, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
			local lamp = Instance.new("PointLight"); lamp.Brightness = 0.45; lamp.Range = 14; lamp.Color = tint(accent, Color3.fromRGB(225, 240, 250), 0.35); lamp.Parent = core
		end
		-- Bodendecke (Kaltnebel).
		local mist = p("CryoFloorMist", Vector3.new(18, 0.06, 11), Vector3.new(cx, LAYER_CONTAM, cz), Color3.fromRGB(220, 232, 238), Enum.Material.SmoothPlastic)
		mist.Transparency = 0.55
	elseif id == "ToxicReactor" then
		-- Grosser Toxic-Reaktor-Kern mit Energie-Saeule.
		p("TRBase", Vector3.new(14, 1.4, 11), Vector3.new(cx, FLOOR_Y + 0.7, cz), Color3.fromRGB(28, 30, 30), Enum.Material.Metal)
		p("TRBaseRing", Vector3.new(13, 0.4, 10), Vector3.new(cx, FLOOR_Y + 1.5, cz), accent, Enum.Material.SmoothPlastic).Transparency = 0.1
		local col = p("TRPillar", Vector3.new(7, 20, 7), Vector3.new(cx, FLOOR_Y + 11, cz), Color3.fromRGB(22, 24, 24), Enum.Material.Metal)
		col.Shape = Enum.PartType.Cylinder
		col.Orientation = Vector3.new(0, 0, 90)
		local glass = p("TRGlass", Vector3.new(5.2, 17, 5.2), Vector3.new(cx, FLOOR_Y + 11, cz), tint(accent, LAB_WHITE, 0.45), Enum.Material.Glass)
		glass.Shape = Enum.PartType.Cylinder
		glass.Orientation = Vector3.new(0, 0, 90)
		glass.Transparency = 0.55
		local core = p("TRCore", Vector3.new(3, 15, 3), Vector3.new(cx, FLOOR_Y + 11, cz), tint(accent, Color3.fromRGB(230, 245, 200), 0.2), Enum.Material.Neon)
		core.Shape = Enum.PartType.Cylinder
		core.Orientation = Vector3.new(0, 0, 90)
		core.Transparency = 0.05
		for i = 0, 5 do
			local ang = i * math.pi / 3
			local ring = p("TRRing" .. i, Vector3.new(0.8, 0.8, 0.8), Vector3.new(cx + math.cos(ang) * 3.4, FLOOR_Y + 6 + (i % 3) * 4.5, cz + math.sin(ang) * 1.2), accent, Enum.Material.Neon)
			ring.Shape = Enum.PartType.Ball
			ring.Transparency = 0.2
		end
		for _, dx in ipairs({ -5.2, 5.2 }) do
			p("TRConduit", Vector3.new(0.9, 18, 0.9), Vector3.new(cx + dx, FLOOR_Y + 10, cz), Color3.fromRGB(40, 44, 46), Enum.Material.Metal)
		end
		p("TRTop", Vector3.new(8, 1.2, 8), Vector3.new(cx, FLOOR_Y + 20.5, cz), Color3.fromRGB(22, 24, 24), Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		local lamp = Instance.new("PointLight"); lamp.Brightness = 0.85; lamp.Range = 20; lamp.Color = tint(accent, Color3.fromRGB(220, 245, 180), 0.4); lamp.Parent = core
	elseif id == "Greenhouse" then
		-- Bio-Dome mit zentralem Spore-Baum.
		p("GHDomeBase", Vector3.new(14, 1.4, 11), Vector3.new(cx, FLOOR_Y + 0.7, cz), LAB_DARK, Enum.Material.Metal)
		p("GHDomeFloor", Vector3.new(13, 0.18, 10), Vector3.new(cx, FLOOR_Y + 1.5, cz), tint(LAB_OLIVE, accent, 0.4), Enum.Material.SmoothPlastic).Transparency = 0.15
		local dome = p("GHDome", Vector3.new(14, 14, 11), Vector3.new(cx, FLOOR_Y + 8.5, cz), tint(accent, LAB_WHITE, 0.55), Enum.Material.Glass)
		dome.Shape = Enum.PartType.Ball
		dome.Transparency = 0.62
		-- zentraler Spore-Baum
		local trunk = p("GHTrunk", Vector3.new(1.6, 10, 1.6), Vector3.new(cx, FLOOR_Y + 6, cz), tint(LAB_OLIVE, accent, 0.4), Enum.Material.SmoothPlastic)
		trunk.Shape = Enum.PartType.Cylinder
		trunk.Orientation = Vector3.new(0, 0, 90)
		for i = 1, 6 do
			local ang = i * math.pi / 3
			local r = 2 + (i % 2) * 0.6
			local bloom = p("GHBloom" .. i, Vector3.new(2.2, 2.2, 2.2), Vector3.new(cx + math.cos(ang) * r, FLOOR_Y + 8 + (i % 3) * 1.5, cz + math.sin(ang) * (r * 0.5)), tint(accent, Color3.fromRGB(180, 120, 220), 0.3), Enum.Material.Neon)
			bloom.Shape = Enum.PartType.Ball
			bloom.Transparency = 0.18
		end
		local cap = p("GHTreeCap", Vector3.new(4.4, 2.6, 4.4), Vector3.new(cx, FLOOR_Y + 11.6, cz), tint(accent, LAB_OLIVE, 0.2), Enum.Material.SmoothPlastic)
		cap.Shape = Enum.PartType.Ball
		cap.Transparency = 0.05
		-- Wurzel-Wachstum am Boden.
		for i = 1, 4 do
			local ang = i * math.pi / 2 + 0.4
			local root = p("GHRoot" .. i, Vector3.new(0.7, 0.3, 4.5), Vector3.new(cx + math.cos(ang) * 2.4, LAYER_CONTAM, cz + math.sin(ang) * 2.4), tint(LAB_OLIVE, accent, 0.4), Enum.Material.SmoothPlastic)
			root.Orientation = Vector3.new(0, math.deg(ang), 0)
			root.Transparency = 0.18
		end
		local lamp = Instance.new("PointLight"); lamp.Brightness = 0.5; lamp.Range = 16; lamp.Color = tint(accent, Color3.fromRGB(170, 220, 150), 0.4); lamp.Parent = cap
	elseif id == "BlackSite" then
		-- Klassifizierte Containment-Kapsel mit Rotglas + Stahlrahmen.
		p("BSBase", Vector3.new(14, 1.4, 11), Vector3.new(cx, FLOOR_Y + 0.7, cz), Color3.fromRGB(18, 18, 22), Enum.Material.Metal)
		p("BSPlatform", Vector3.new(12, 0.2, 9), Vector3.new(cx, FLOOR_Y + 1.5, cz), Color3.fromRGB(24, 24, 28), Enum.Material.Metal).Transparency = 0.1
		local cage = p("BSCage", Vector3.new(10, 18, 7), Vector3.new(cx, FLOOR_Y + 10, cz), Color3.fromRGB(14, 14, 18), Enum.Material.Metal)
		local glass = p("BSGlass", Vector3.new(7.6, 14, 0.6), Vector3.new(cx, FLOOR_Y + 9, cz - 3.4), tint(accent, Color3.fromRGB(14, 8, 12), 0.55), Enum.Material.Glass)
		glass.Transparency = 0.4
		local inner = p("BSInnerGlow", Vector3.new(6, 11, 1.4), Vector3.new(cx, FLOOR_Y + 9, cz - 1.4), tint(accent, Color3.fromRGB(48, 14, 22), 0.3), Enum.Material.Neon)
		inner.Transparency = 0.42
		p("BSCageTop", Vector3.new(11, 1.2, 8), Vector3.new(cx, FLOOR_Y + 19.4, cz), Color3.fromRGB(10, 10, 14), Enum.Material.Metal)
		-- Rote Warnleuchten oben.
		for _, dx in ipairs({ -4.2, 0, 4.2 }) do
			local rl = p("BSRedLamp", Vector3.new(0.9, 0.9, 0.9), Vector3.new(cx + dx, FLOOR_Y + 19.4, cz - 3), accent, Enum.Material.Neon)
			rl.Shape = Enum.PartType.Ball
		end
		-- Vertikale Stahlrippen (Cage-Optik).
		for i = -2, 2 do
			p("BSCageRib", Vector3.new(0.45, 16, 0.45), Vector3.new(cx + i * 1.7, FLOOR_Y + 10, cz - 3.3), Color3.fromRGB(8, 8, 10), Enum.Material.Metal)
		end
		-- Bodenmarkierung -> "DO NOT CROSS".
		local floorStripe = p("BSFloorWarn", Vector3.new(11, 0.07, 9.4), Vector3.new(cx, LAYER_CONTAM, cz), Color3.fromRGB(40, 12, 18), Enum.Material.SmoothPlastic)
		floorStripe.Transparency = 0.2
		local plate = p("BSPlate", Vector3.new(4.4, 1.6, 0.45), Vector3.new(cx, FLOOR_Y + 4, cz - 3.7), Color3.fromRGB(8, 8, 10), Enum.Material.Metal)
		label(plate, "RESTRICTED", accent, 36, UDim2.fromOffset(180, 30), Vector3.new(0, 0, 0))
		local lamp = Instance.new("PointLight"); lamp.Brightness = 0.5; lamp.Range = 14; lamp.Color = tint(accent, Color3.fromRGB(160, 30, 40), 0.4); lamp.Parent = inner
	elseif id == "OmegaDNA" then
		-- Riesige goldene DNA-Helix in Premium-Glaszylinder mit Ringen.
		p("OmegaCBase", Vector3.new(15, 1.4, 12), Vector3.new(cx, FLOOR_Y + 0.7, cz), Color3.fromRGB(206, 210, 214), Enum.Material.Metal)
		p("OmegaCBaseRing", Vector3.new(13, 0.5, 10.5), Vector3.new(cx, FLOOR_Y + 1.65, cz), accent, Enum.Material.Neon).Transparency = 0.25
		local glass = p("OmegaCGlass", Vector3.new(6.4, 22, 6.4), Vector3.new(cx, FLOOR_Y + 12, cz), tint(accent, Color3.fromRGB(245, 240, 226), 0.5), Enum.Material.Glass)
		glass.Shape = Enum.PartType.Cylinder
		glass.Orientation = Vector3.new(0, 0, 90)
		glass.Transparency = 0.62
		for i = 0, 19 do
			local t = i / 19
			local ang = t * math.pi * 4
			local node = p("OmegaCNode" .. i, Vector3.new(1, 1, 1), Vector3.new(cx + math.cos(ang) * 1.9, FLOOR_Y + 2 + t * 20, cz + math.sin(ang) * 0.7), accent, Enum.Material.Neon)
			node.Shape = Enum.PartType.Ball
			node.Transparency = 0.1
			local mirror = p("OmegaCNodeM" .. i, Vector3.new(1, 1, 1), Vector3.new(cx - math.cos(ang) * 1.9, FLOOR_Y + 2 + t * 20, cz - math.sin(ang) * 0.7), Color3.fromRGB(245, 240, 218), Enum.Material.Neon)
			mirror.Shape = Enum.PartType.Ball
			mirror.Transparency = 0.16
			if i % 3 == 0 then
				local rung = p("OmegaCRung" .. i, Vector3.new(3.8, 0.32, 0.32), Vector3.new(cx, FLOOR_Y + 2 + t * 20, cz + math.sin(ang) * 0.2), accent, Enum.Material.Neon)
				rung.Transparency = 0.42
			end
		end
		-- Auessen-Energiering (orbitiert um die Helix).
		for i = 0, 3 do
			local h = FLOOR_Y + 5 + i * 5
			local ring = p("OmegaCFloatingRing" .. i, Vector3.new(8.4, 0.32, 8.4), Vector3.new(cx, h, cz), accent, Enum.Material.Neon)
			ring.Shape = Enum.PartType.Cylinder
			ring.Orientation = Vector3.new(0, 0, 90)
			ring.Transparency = 0.55
		end
		p("OmegaCTop", Vector3.new(11, 1.6, 11), Vector3.new(cx, FLOOR_Y + 23.5, cz), Color3.fromRGB(206, 210, 214), Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		local lamp = Instance.new("PointLight"); lamp.Brightness = 0.7; lamp.Range = 22; lamp.Color = tint(accent, Color3.fromRGB(245, 230, 200), 0.35); lamp.Parent = glass
	else
		-- FinalCore (Area 10): massiver Virus-Kern mit Stahlkaefig + Energie.
		p("FCBase", Vector3.new(18, 1.6, 13), Vector3.new(cx, FLOOR_Y + 0.8, cz), Color3.fromRGB(14, 12, 14), Enum.Material.Metal)
		p("FCBaseRing", Vector3.new(16, 0.5, 11), Vector3.new(cx, FLOOR_Y + 1.85, cz), accent, Enum.Material.Neon).Transparency = 0.15
		local glass = p("FCGlass", Vector3.new(9, 24, 9), Vector3.new(cx, FLOOR_Y + 13, cz), tint(accent, Color3.fromRGB(36, 18, 22), 0.45), Enum.Material.Glass)
		glass.Shape = Enum.PartType.Cylinder
		glass.Transparency = 0.5
		local core = p("FCCore", Vector3.new(5.4, 18, 5.4), Vector3.new(cx, FLOOR_Y + 13, cz), tint(accent, Color3.fromRGB(255, 195, 195), 0.18), Enum.Material.Neon)
		core.Shape = Enum.PartType.Cylinder
		core.Transparency = 0.04
		-- Schwebende Energiekugeln um den Kern.
		for i = 0, 5 do
			local ang = i * math.pi / 3
			local r = 3.5
			local sphere = p("FCEnergyOrb" .. i, Vector3.new(1.4, 1.4, 1.4), Vector3.new(cx + math.cos(ang) * r, FLOOR_Y + 7 + i * 2.6, cz + math.sin(ang) * (r * 0.4)), accent, Enum.Material.Neon)
			sphere.Shape = Enum.PartType.Ball
			sphere.Transparency = 0.12
		end
		-- Stahlrippen-Kaefig.
		for i = 0, 5 do
			local ang = i * math.pi / 3
			p("FCRib" .. i, Vector3.new(0.9, 22, 0.9), Vector3.new(cx + math.cos(ang) * 4.4, FLOOR_Y + 12, cz + math.sin(ang) * (4.4 * 0.5)), Color3.fromRGB(18, 14, 16), Enum.Material.Metal)
		end
		p("FCTop", Vector3.new(12, 1.6, 12), Vector3.new(cx, FLOOR_Y + 25.2, cz), Color3.fromRGB(14, 12, 14), Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		p("FCTopLamp", Vector3.new(1.8, 1.8, 1.8), Vector3.new(cx, FLOOR_Y + 26.6, cz), accent, Enum.Material.Neon).Shape = Enum.PartType.Ball
		local lamp = Instance.new("PointLight"); lamp.Brightness = 1.0; lamp.Range = 26; lamp.Color = tint(accent, Color3.fromRGB(255, 200, 200), 0.3); lamp.Parent = core
	end
end

-- ---- Outbreak polish layer ------------------------------------------------
-- Additive, low-touch environmental storytelling for every area tunnel:
-- sample carts, breach log panels, quarantine stripes and status beacons.
-- Everything is visual-only and kept at the corridor edges so the enemy path
-- and training/egg interactions stay readable.
local function buildIncidentPanel(parent, name, pos: Vector3, accent: Color3, title: string, status: string, faceSign: number)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local board = makePart(model, "IncidentPanelBody", Vector3.new(18, 7.2, 0.5), pos, Color3.fromRGB(32, 36, 38), Enum.Material.Metal, false)
	local frame = makePart(model, "IncidentPanelFrame", Vector3.new(19.2, 8.4, 0.32), pos + Vector3.new(0, 0, -0.12 * faceSign), LAB_DARK, Enum.Material.SmoothPlastic, false)
	label(board, title .. "\n" .. status, accent:Lerp(Color3.fromRGB(235, 240, 232), 0.4), 42, UDim2.fromOffset(210, 64), Vector3.new(0, 0, 0))

	for i = 0, 3 do
		local lightColor = if i < 2 then accent else LAB_WARNING_RED
		local dot = makePart(model, "IncidentStatusLight", Vector3.new(1, 1, 0.28), pos + Vector3.new(-7.2 + i * 2.1, -3.1, -0.42 * faceSign), lightColor, Enum.Material.SmoothPlastic, false)
		dot.Shape = Enum.PartType.Ball
		dot.Transparency = if i < 2 then 0.05 else 0.18
	end

	for i = 0, 4 do
		local barHeight = 0.6 + (i % 3) * 0.55
		makePart(
			model,
			"IncidentReadoutBar",
			Vector3.new(1.1, barHeight, 0.24),
			pos + Vector3.new(3.3 + i * 1.4, -2.7 + barHeight / 2, -0.44 * faceSign),
			accent:Lerp(LAB_DARK, 0.25),
			Enum.Material.SmoothPlastic,
			false
		).Transparency = 0.08
	end

	local trim = makePart(model, "IncidentAccentLine", Vector3.new(16, 0.25, 0.22), pos + Vector3.new(0, 2.95, -0.45 * faceSign), accent, Enum.Material.SmoothPlastic, false)
	trim.Transparency = 0.28
	return frame
end

local function buildSampleCart(parent, name, origin: Vector3, accent: Color3, face: number)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local base = makePart(model, "SampleCartBase", Vector3.new(12, 0.9, 5.8), origin + Vector3.new(0, 1.0, 0), Color3.fromRGB(48, 54, 56), Enum.Material.Metal, false)
	base.Transparency = 0.02
	makePart(model, "SampleCartShelf", Vector3.new(11.2, 0.5, 5.2), origin + Vector3.new(0, 3.4, 0), LAB_TRIM, Enum.Material.Metal, false)
	makePart(model, "SampleCartHandle", Vector3.new(0.55, 4.4, 4.8), origin + Vector3.new(-6.1, 3.1, 0), LAB_DARK, Enum.Material.Metal, false)

	for i = 0, 3 do
		local px = -3.9 + i * 2.6
		local vial = makePart(model, "InfectedVial", Vector3.new(1.05, 2.9, 1.05), origin + Vector3.new(px, 5.1, -0.8), Color3.fromRGB(178, 226, 218), Enum.Material.Glass, false)
		vial.Shape = Enum.PartType.Cylinder
		vial.Transparency = 0.48
		local sample = makePart(model, "VialSampleGlow", Vector3.new(0.72, 1.25, 0.72), origin + Vector3.new(px, 4.5, -0.8), accent:Lerp(LAB_OLIVE, 0.28), Enum.Material.SmoothPlastic, false)
		sample.Shape = Enum.PartType.Ball
		sample.Transparency = 0.16
		makePart(model, "VialCap", Vector3.new(1.2, 0.28, 1.2), origin + Vector3.new(px, 6.65, -0.8), LAB_DARK, Enum.Material.Metal, false)
	end

	local clipboard = makePart(model, "SampleClipboard", Vector3.new(4.2, 0.18, 2.8), origin + Vector3.new(3.2, 3.85, 1.15 * face), LAB_WARNING_YELLOW:Lerp(LAB_WHITE, 0.35), Enum.Material.SmoothPlastic, false)
	clipboard.Transparency = 0.08
	local tag = makePart(model, "SampleTag", Vector3.new(5, 1.8, 0.35), origin + Vector3.new(0, 6.2, 2.8 * face), LAB_DARK, Enum.Material.Metal, false)
	label(tag, "LIVE\nSAMPLES", accent:Lerp(Color3.fromRGB(235, 240, 232), 0.35), 28, UDim2.fromOffset(100, 42), Vector3.new(0, 0, 0))
end

local function buildQuarantineStripe(parent, name, center: Vector3, accent: Color3, length: number)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local base = makePart(model, "QuarantineStripeBase", Vector3.new(length, 0.07, 4.2), center, Color3.fromRGB(40, 42, 34), Enum.Material.SmoothPlastic, false)
	base.Transparency = 0.18
	for i = 0, 5 do
		local offset = -length / 2 + 3 + i * (length - 6) / 5
		local bar = makePart(model, "QuarantineStripeSlash", Vector3.new(5.8, 0.08, 1), center + Vector3.new(offset, 0.05, 0), if i % 2 == 0 then LAB_WARNING_YELLOW else LAB_DARK, Enum.Material.SmoothPlastic, false)
		bar.Orientation = Vector3.new(0, 24, 0)
		bar.Transparency = if i % 2 == 0 then 0.2 else 0.05
	end
	local glow = neonStrip(model, Vector3.new(length - 2, 0.05, 0.25), center + Vector3.new(0, 0.11, 1.85), accent, 0.72)
	glow.Name = "QuarantineStripeAccent"
end

local function buildWarningBeacon(parent, name, pos: Vector3, accent: Color3, critical: boolean)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	makePart(model, "BeaconBracket", Vector3.new(7, 0.55, 1.2), pos + Vector3.new(0, 0.45, 0), LAB_DARK, Enum.Material.Metal, false)
	for _, dx in ipairs({ -2.4, 2.4 }) do
		local lamp = makePart(model, "BeaconLamp", Vector3.new(1.25, 1.25, 1.25), pos + Vector3.new(dx, -0.25, 0), if critical then LAB_WARNING_RED else accent, Enum.Material.Neon, false)
		lamp.Shape = Enum.PartType.Ball
		lamp.Transparency = 0.18
		local light = Instance.new("PointLight")
		light.Brightness = if critical then 0.32 else 0.22
		light.Range = if critical then 13 else 10
		light.Color = if critical then LAB_WARNING_RED else accent:Lerp(Color3.fromRGB(230, 238, 230), 0.35)
		light.Parent = lamp
	end
end

local function buildCableDrop(parent, name, x: number, z: number, accent: Color3)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local topY = FLOOR_Y + L.WallHeight + BACTERIA_CEILING_LIFT - 5
	local bottomY = FLOOR_Y + 18
	makePart(model, "CableDropBackbone", Vector3.new(0.65, topY - bottomY, 0.65), Vector3.new(x, (topY + bottomY) / 2, z), Color3.fromRGB(34, 38, 40), Enum.Material.Metal, false)
	for i = 0, 2 do
		local side = if i % 2 == 0 then -1 else 1
		local cable = makePart(model, "LooseCableRun", Vector3.new(0.34, 8.5, 0.34), Vector3.new(x + side * (1.2 + i * 0.25), topY - 4.5 - i * 1.2, z), if i == 1 then accent:Lerp(LAB_DARK, 0.35) else Color3.fromRGB(24, 28, 30), Enum.Material.Metal, false)
		cable.Orientation = Vector3.new(0, 0, side * (8 + i * 4))
		cable.Transparency = if i == 1 then 0.12 else 0
	end
	makePart(model, "CableClampTop", Vector3.new(4.6, 0.55, 0.9), Vector3.new(x, topY, z), LAB_TRIM, Enum.Material.Metal, false)
	makePart(model, "CableClampBottom", Vector3.new(3.6, 0.45, 0.9), Vector3.new(x, bottomY, z), LAB_TRIM, Enum.Material.Metal, false)
end

local function addOutbreakStoryDetails(parent, area, hallX, theme, accent)
	local deco = makeFolder("OutbreakStoryDetails", parent)
	local critical = area.index >= 5
	local alert = if critical then LAB_WARNING_RED else if area.index >= 3 then LAB_WARNING_YELLOW else accent
	local statusByIndex = {
		[1] = "AIR FILTERS OK",
		[2] = "DECON ACTIVE",
		[3] = "DNA DRIFT RISING",
		[4] = "WASTE LINE SEALED",
		[5] = "VIRAL LOAD HIGH",
		[6] = "REACTOR FLUX",
		[7] = "SPORES DETECTED",
		[8] = "BLACK SITE LOCK",
		[9] = "OMEGA SAMPLE STABLE",
		[10] = "FINAL SEAL ARMED",
	}
	local status = statusByIndex[area.index] or "CONTAINMENT OK"

	buildIncidentPanel(
		deco,
		"IncidentPanelLeft",
		Vector3.new(hallX - 124, FLOOR_Y + 21, BACTERIA_LEFT_LIMIT_Z + 1.9),
		alert,
		"INCIDENT LOG A-" .. tostring(area.index),
		status,
		1
	)
	buildIncidentPanel(
		deco,
		"IncidentPanelRight",
		Vector3.new(hallX + 134, FLOOR_Y + 21, BACTERIA_RIGHT_LIMIT_Z - 1.9),
		accent,
		"SAMPLE STATUS",
		string.upper(theme.id),
		-1
	)

	buildSampleCart(deco, "SampleCartLeft", Vector3.new(hallX - 146, FLOOR_Y, BACTERIA_LEFT_LIMIT_Z + 8), accent, 1)
	if area.index >= 4 then
		buildSampleCart(deco, "SampleCartRight", Vector3.new(hallX + 150, FLOOR_Y, BACTERIA_RIGHT_LIMIT_Z - 8), alert, -1)
	end

	buildQuarantineStripe(deco, "QuarantineStripeGateLeft", Vector3.new(hallX + L.GateOffsetX + 54, LAYER_CONTAM + 0.12, -28), alert, 28)
	buildQuarantineStripe(deco, "QuarantineStripeGateRight", Vector3.new(hallX + L.GateOffsetX + 54, LAYER_CONTAM + 0.12, 28), alert, 28)
	if area.index >= 6 then
		buildQuarantineStripe(deco, "QuarantineStripeDeepLeft", Vector3.new(hallX + 116, LAYER_CONTAM + 0.12, -28), LAB_WARNING_RED, 30)
		buildQuarantineStripe(deco, "QuarantineStripeDeepRight", Vector3.new(hallX + 116, LAYER_CONTAM + 0.12, 28), LAB_WARNING_RED, 30)
	end

	buildWarningBeacon(deco, "GateWarningBeacon", Vector3.new(hallX + L.GateOffsetX + 54, FLOOR_Y + L.WallHeight + BACTERIA_CEILING_LIFT - 2.3, 0), alert, critical)
	buildWarningBeacon(deco, "HallWarningBeacon", Vector3.new(hallX + 112, FLOOR_Y + L.WallHeight + BACTERIA_CEILING_LIFT - 2.3, 0), accent, area.index >= 8)

	buildCableDrop(deco, "CableDropLeft", hallX - 58, BACTERIA_LEFT_LIMIT_Z + 2.8, accent)
	if area.index >= 3 then
		buildCableDrop(deco, "CableDropRight", hallX + 72, BACTERIA_RIGHT_LIMIT_Z - 2.8, alert)
	end
end

local function addBacteriaLabDetails(parent, area, hallX, primary)
	local deco = makeFolder("TunnelLabDetails", parent)
	local theme = themeFor(area.index)
	local accent = theme.accent
	-- Inner-Tunnel-Waende uebernehmen Area-Farbe deutlich (staerker als die
	-- aeusseren LabWalls, weil der Spieler hier direkt vorbeilaeuft).
	local tunnelWallColor = tint(LAB_WHITE, primary, 0.68)

	local wallStartX = hallX + L.GateOffsetX - 10
	-- Tunnel-Wand muss bis hinter den Boss-Raum reichen, aber NICHT ueber die
	-- (verschobene) Shell-Naht hinaus, sonst leuchtet die alte Area-Farbe in
	-- die neue rein. Shell endet bei hallX + 200; lass etwas Sicherheit.
	local normalSpan = (L.EnemiesPerArea - 2) * L.NormalEnemySpacing
	local wallEndX = math.min(hallX + 196, hallX + (normalSpan + L.BossOffsetX) / 2 + 48)
	local wallLength = wallEndX - wallStartX
	local wallCenterX = (wallStartX + wallEndX) / 2
	local tunnelWallHeight = L.WallHeight + BACTERIA_CEILING_LIFT - 2
	for _, z in ipairs({ BACTERIA_LEFT_LIMIT_Z, BACTERIA_RIGHT_LIMIT_Z }) do
		local wall = makePart(deco, "BacteriaTunnelWall", Vector3.new(wallLength, tunnelWallHeight, 3.2), Vector3.new(wallCenterX, FLOOR_Y + tunnelWallHeight / 2, z), tunnelWallColor, Enum.Material.SmoothPlastic, true)
		wall.Transparency = 0.02
		makePart(deco, "BacteriaWallDarkBase", Vector3.new(wallLength, 1.4, 3.5), Vector3.new(wallCenterX, FLOOR_Y + 0.8, z), LAB_DARK, Enum.Material.Metal, true)
		makePart(deco, "BacteriaWallTopRail", Vector3.new(wallLength, 1.2, 3.6), Vector3.new(wallCenterX, FLOOR_Y + tunnelWallHeight - 0.6, z), LAB_DARK, Enum.Material.Metal, true)
		neonStrip(deco, Vector3.new(wallLength - 12, 0.18, 0.26), Vector3.new(wallCenterX, FLOOR_Y + 5.8, z), primary, 0.78)
		neonStrip(deco, Vector3.new(wallLength - 16, 0.16, 0.24), Vector3.new(wallCenterX, FLOOR_Y + tunnelWallHeight - 5.5, z), LAB_PURPLE, 0.82)
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
		makePart(deco, "BacteriaTunnelOuterCapLeft", Vector3.new(3, tunnelWallHeight, leftWidth), Vector3.new(x, FLOOR_Y + tunnelWallHeight / 2, (CORRIDOR_MIN_Z + BACTERIA_LEFT_LIMIT_Z) / 2), tunnelWallColor, Enum.Material.SmoothPlastic, true)
		makePart(deco, "BacteriaTunnelOuterCapRight", Vector3.new(3, tunnelWallHeight, rightWidth), Vector3.new(x, FLOOR_Y + tunnelWallHeight / 2, (BACTERIA_RIGHT_LIMIT_Z + CORRIDOR_MAX_Z) / 2), tunnelWallColor, Enum.Material.SmoothPlastic, true)
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
	-- Fuer Area 2..10 ist der mittlere Rueckwand-Slot dem Hero-Centerpiece
	-- vorbehalten (siehe buildAreaCenterpiece). Sonst kollidieren Side-Prop
	-- und Centerpiece in derselben Z-Reihe.
	for _, x in ipairs({ hallX - 100, hallX + 10, hallX + 120 }) do
		for _, z in ipairs({ BACTERIA_LEFT_LIMIT_Z + 8, BACTERIA_RIGHT_LIMIT_Z - 8 }) do
			if area.index > 1 and x == hallX + 10 and z == BACTERIA_RIGHT_LIMIT_Z - 8 then
				continue
			end
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

	addOutbreakStoryDetails(deco, area, hallX, theme, accent)
end

-- ---- Trainingsbereich -----------------------------------------------------

local function buildTrainingArea(parent, bedsFolder, _gatesFolder, area, x)
	local bedDef = TrainingBedConfig[area.index]
	local primary = area.primaryColor
	local model = Instance.new("Model")
	model.Name = "Training_" .. area.id
	model.Parent = parent

	-- ---- Seitlicher Trainingsbereich (links, -Z) -------------------------
	-- Vergroesserte, futuristische Trainings-Bay: erhoehte Plattform mit
	-- Tech-Floor, holographischen Trainings-Props, Glas-Halbwaenden, vier
	-- Pylonen mit Statusringen und einem schwebenden POWER-TRAINING-Schild.
	-- Bleibt im weissen Bio-Labor (Cyan/Gruen-Akzente). Vertraege erhalten:
	-- TrainPadLedOrbit + TrainingLedStrip + LedIndex (Client-Animation) und
	-- Bett-Model + Hitbox + RequiredRebirth/PowerPerSecond (Service).
	local bayZ = -56
	local bayDepthZ = 56
	local bayHalfZ = bayDepthZ / 2
	local bayMouthZ = bayZ + bayHalfZ
	local bayBackZ = bayZ - bayHalfZ + 0.6
	local bayWidthX = 112
	local center = Vector3.new(x, FLOOR_Y, bayZ)

	-- Trainings-Akzente uebernehmen die Area-Farbe (primary) -> Power Training
	-- liest sich farblich wie die zugehoerige Area. Variablennamen historisch.
	local accentCyan = primary
	local accentGreen = tint(primary, Color3.fromRGB(245, 250, 255), 0.45)
	local accentLightBase = tint(primary, Color3.fromRGB(248, 250, 255), 0.65)
	local glassCol = Color3.fromRGB(206, 224, 230)
	local padTop = Color3.fromRGB(40, 46, 54)
	local padInset = Color3.fromRGB(28, 33, 40)
	local padDeep = Color3.fromRGB(18, 22, 28)

	-- 1. Bay-Boden + gelbe Eingangsschwelle (Schwelle bleibt zum Laufweg).
	makePart(model, "TrainingBayFloor", Vector3.new(bayWidthX, 0.6, bayDepthZ), Vector3.new(x, FLOOR_Y + 0.32, bayZ), tint(LAB_PANEL, primary, 0.70), Enum.Material.SmoothPlastic, true)
	makePart(model, "TrainingBayThreshold", Vector3.new(bayWidthX, 0.06, 1.8), Vector3.new(x, FLOOR_Y + 0.68, bayMouthZ - 1), LAB_WARNING_YELLOW, Enum.Material.SmoothPlastic, false).Transparency = 0.42

	-- 2. Erhoehte Trainingsplattform (groesser: 96x44 statt 50x24).
	local padBase = makePart(model, "TrainStationBase", Vector3.new(96, 0.22, 44), center + Vector3.new(0, 0.82, 0), padDeep, Enum.Material.Metal, false)
	padBase.Transparency = 0.04
	local pad = makePart(model, "TrainPad", Vector3.new(86, 0.16, 36), center + Vector3.new(0, 1.02, 0), padTop, Enum.Material.SmoothPlastic, false)
	pad.Transparency = 0.06
	makePart(model, "TrainPadInnerPanel", Vector3.new(70, 0.08, 26), center + Vector3.new(0, 1.16, 0), padInset, Enum.Material.SmoothPlastic, false).Transparency = 0.04

	-- 3. Tech-Grid auf dem Pad: 4 Quadrant-Kacheln + Crosshair + Center-Ring.
	for _, dx in ipairs({ -19, 19 }) do
		for _, dz in ipairs({ -8, 8 }) do
			local tile = makePart(model, "TrainPadHexTile", Vector3.new(30, 0.06, 11.5), center + Vector3.new(dx, 1.22, dz), Color3.fromRGB(54, 62, 72), Enum.Material.Metal, false)
			tile.Transparency = 0.05
		end
	end
	-- Crosshair-Linien
	local gridX = makePart(model, "TrainPadGridX", Vector3.new(82, 0.04, 0.22), center + Vector3.new(0, 1.26, 0), accentCyan, Enum.Material.Neon, false)
	gridX.Transparency = 0.18
	local gridZ = makePart(model, "TrainPadGridZ", Vector3.new(0.22, 0.04, 32), center + Vector3.new(0, 1.26, 0), accentCyan, Enum.Material.Neon, false)
	gridZ.Transparency = 0.18
	-- Center-Ringe (Cylinder als flache Scheibe via Orientation).
	local ringOuter = makePart(model, "TrainPadCenterRingOuter", Vector3.new(0.3, 9, 9), center + Vector3.new(0, 1.26, 0), accentCyan, Enum.Material.Neon, false)
	ringOuter.Shape = Enum.PartType.Cylinder
	ringOuter.Orientation = Vector3.new(0, 0, 90)
	ringOuter.Transparency = 0.5
	local ringInner = makePart(model, "TrainPadCenterRingInner", Vector3.new(0.3, 4.2, 4.2), center + Vector3.new(0, 1.28, 0), accentGreen, Enum.Material.Neon, false)
	ringInner.Shape = Enum.PartType.Cylinder
	ringInner.Orientation = Vector3.new(0, 0, 90)
	ringInner.Transparency = 0.35
	local centerDot = makePart(model, "TrainPadCenterDot", Vector3.new(0.18, 1.4, 1.4), center + Vector3.new(0, 1.3, 0), accentCyan, Enum.Material.Neon, false)
	centerDot.Shape = Enum.PartType.Cylinder
	centerDot.Orientation = Vector3.new(0, 0, 90)
	centerDot.Transparency = 0.05
	-- Pad-Kanten als duenne Cyan-Neon-Trim-Streifen.
	for _, dx in ipairs({ -43, 43 }) do
		makePart(model, "TrainPadSideFrame", Vector3.new(0.5, 0.4, 36), center + Vector3.new(dx, 1.2, 0), accentCyan, Enum.Material.Neon, false).Transparency = 0.32
	end
	for _, dz in ipairs({ -18, 18 }) do
		makePart(model, "TrainPadEndFrame", Vector3.new(86, 0.4, 0.5), center + Vector3.new(0, 1.2, dz), accentCyan, Enum.Material.Neon, false).Transparency = 0.32
	end

	-- 4. LED-Orbit (Client-Vertrag: Modellname + Part-Name + LedIndex bleiben).
	local ledOrbit = Instance.new("Model")
	ledOrbit.Name = "TrainPadLedOrbit"
	ledOrbit.Parent = model
	ledOrbit:SetAttribute("FlowSpeed", 0.85)
	-- Client (TrainingPadVisuals) liest AccentColor und animiert die LEDs in
	-- der Area-Farbe statt im globalen Lila.
	ledOrbit:SetAttribute("AccentColor", primary)
	local pivot = makePart(ledOrbit, "LedOrbitPivot", Vector3.new(0.2, 0.2, 0.2), center + Vector3.new(0, 1.6, 0), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, false)
	pivot.Transparency = 1
	pivot.CanTouch = false
	ledOrbit.PrimaryPart = pivot

	local ledRed = Color3.fromRGB(150, 42, 46)
	local ledGreen = Color3.fromRGB(52, 156, 82)
	local ledLength = 3.4
	local ledGap = 0.18
	local ledStep = ledLength + ledGap
	local ledRowsX = 22
	local ledRowsZ = 9
	local ledRowSpanX = (ledRowsX - 1) * ledStep
	local ledRowSpanZ = (ledRowsZ - 1) * ledStep
	local topZ = 17.6
	local sideX = 41.2
	local ledY = 1.78
	local function ledColor(index)
		return if index % 2 == 0 then ledRed else ledGreen
	end
	local ledIndex = 0
	for sideIndex, zOffset in ipairs({ -topZ, topZ }) do
		for i = 1, ledRowsX do
			ledIndex += 1
			local xOffset = -ledRowSpanX / 2 + (i - 1) * ledStep
			local strip = makePart(ledOrbit, "TrainingLedStrip", Vector3.new(ledLength, 0.78, 0.82), center + Vector3.new(xOffset, ledY, zOffset), ledColor(i + sideIndex), Enum.Material.Neon, false)
			strip.Transparency = 0
			strip.CanTouch = false
			strip.CastShadow = false
			strip:SetAttribute("LedIndex", ledIndex)
		end
	end
	for sideIndex, xOffset in ipairs({ -sideX, sideX }) do
		for i = 1, ledRowsZ do
			ledIndex += 1
			local zOffset = -ledRowSpanZ / 2 + (i - 1) * ledStep
			local strip = makePart(ledOrbit, "TrainingLedStrip", Vector3.new(0.82, 0.78, ledLength), center + Vector3.new(xOffset, ledY, zOffset), ledColor(i + sideIndex + 1), Enum.Material.Neon, false)
			strip.Transparency = 0
			strip.CanTouch = false
			strip.CastShadow = false
			strip:SetAttribute("LedIndex", ledIndex)
		end
	end

	-- 5. Vier Eckpylonen mit Statusringen + Spitzenlicht.
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local px = center.X + sx * 47
			local pz = center.Z + sz * 20.5
			local pylonH = 14
			local pylonY = FLOOR_Y + pylonH / 2
			makePart(model, "TrainPylonCore", Vector3.new(2.2, pylonH, 2.2), Vector3.new(px, pylonY, pz), LAB_DARK, Enum.Material.Metal, true)
			local shell = makePart(model, "TrainPylonShell", Vector3.new(2.9, pylonH * 0.88, 2.9), Vector3.new(px, pylonY + 0.4, pz), LAB_PANEL, Enum.Material.Metal, false)
			shell.Transparency = 0.04
			for ringIdx, ringY in ipairs({ FLOOR_Y + 4, FLOOR_Y + 8, FLOOR_Y + 11.5 }) do
				local ringCol = if ringIdx == 2 then accentGreen else accentCyan
				local pr = makePart(model, "TrainPylonRing", Vector3.new(0.35, 3.6, 3.6), Vector3.new(px, ringY, pz), ringCol, Enum.Material.Neon, false)
				pr.Shape = Enum.PartType.Cylinder
				pr.Orientation = Vector3.new(0, 0, 90)
				pr.Transparency = 0.22 + ringIdx * 0.04
			end
			makePart(model, "TrainPylonCap", Vector3.new(3.4, 0.6, 3.4), Vector3.new(px, FLOOR_Y + pylonH + 0.3, pz), LAB_TRIM, Enum.Material.Metal, false)
			local capLight = makePart(model, "TrainPylonLight", Vector3.new(0.3, 2, 2), Vector3.new(px, FLOOR_Y + pylonH + 1.4, pz), accentCyan, Enum.Material.Neon, false)
			capLight.Shape = Enum.PartType.Cylinder
			capLight.Orientation = Vector3.new(0, 0, 90)
			capLight.Transparency = 0.15
			local pl = Instance.new("PointLight")
			pl.Brightness = 1.2
			pl.Range = 18
			pl.Color = accentCyan
			pl.Parent = capLight
		end
	end

	-- 6. Rueckwand-Schild "POWER TRAINING" mit Cyan-Akzentstreifen.
	local rearZ = bayBackZ
	makePart(model, "TrainBackPanel", Vector3.new(bayWidthX - 22, 13, 0.7), Vector3.new(x, FLOOR_Y + 9, rearZ), LAB_PANEL, Enum.Material.Metal, false)
	makePart(model, "TrainBackPanelInset", Vector3.new(bayWidthX - 32, 9, 0.35), Vector3.new(x, FLOOR_Y + 9, rearZ + 0.3), LAB_DARK, Enum.Material.SmoothPlastic, false).Transparency = 0.04
	-- Cyan-Glow oben/unten am Schild
	makePart(model, "TrainBackPanelTopStrip", Vector3.new(bayWidthX - 28, 0.35, 0.5), Vector3.new(x, FLOOR_Y + 15.6, rearZ + 0.4), accentCyan, Enum.Material.Neon, false).Transparency = 0.12
	makePart(model, "TrainBackPanelBottomStrip", Vector3.new(bayWidthX - 28, 0.35, 0.5), Vector3.new(x, FLOOR_Y + 2.4, rearZ + 0.4), accentCyan, Enum.Material.Neon, false).Transparency = 0.18
	for _, sx in ipairs({ -1, 1 }) do
		makePart(model, "TrainBackEdgeLight", Vector3.new(0.5, 11, 0.5), Vector3.new(x + sx * (bayWidthX / 2 - 13), FLOOR_Y + 9, rearZ + 0.4), accentCyan, Enum.Material.Neon, false).Transparency = 0.15
	end
	-- Daten-Pixel rechts auf dem Schild (kleine vertikale "Balken").
	for i = 1, 8 do
		local px = x + (bayWidthX / 2 - 18) + (i - 1) * 0.9
		local barH = 1.6 + ((i * 7) % 5) * 0.5
		makePart(model, "TrainBackDataBar", Vector3.new(0.5, barH, 0.4), Vector3.new(px, FLOOR_Y + 6 + barH / 2, rearZ + 0.5), if i % 2 == 0 then accentGreen else accentCyan, Enum.Material.Neon, false).Transparency = 0.18
	end

	-- 7. Glas-Halbwaende an den Laengsseiten (offen zur Mouth-Seite).
	for _, sx in ipairs({ -1, 1 }) do
		local wallX = x + sx * (bayWidthX / 2 - 1.6)
		local glassWall = makePart(model, "TrainSideGlass", Vector3.new(0.5, 11, bayDepthZ - 8), Vector3.new(wallX, FLOOR_Y + 5.6, bayZ - 2), glassCol, Enum.Material.Glass, false)
		glassWall.Transparency = 0.7
		-- vertikale Rahmen entlang der Bay-Tiefe
		for _, fz in ipairs({ -bayHalfZ + 6, -bayHalfZ + 24, -bayHalfZ + 42 }) do
			makePart(model, "TrainSideFrame", Vector3.new(0.7, 11.4, 0.7), Vector3.new(wallX, FLOOR_Y + 5.7, bayZ + fz), LAB_TRIM, Enum.Material.Metal, false)
		end
		-- oberer Cyan-Akzent
		makePart(model, "TrainSideTopGlow", Vector3.new(0.3, 0.3, bayDepthZ - 10), Vector3.new(wallX, FLOOR_Y + 11, bayZ - 2), accentCyan, Enum.Material.Neon, false).Transparency = 0.25
	end

	-- 8. Holographischer Boxsack (vertikaler Cylinder mit Neon + Ringe).
	local bagX = center.X
	local bagZ = center.Z + 9
	makePart(model, "TrainBagAnchor", Vector3.new(2.2, 0.6, 2.2), Vector3.new(bagX, FLOOR_Y + 16.3, bagZ), LAB_TRIM, Enum.Material.Metal, false)
	makePart(model, "TrainBagCable", Vector3.new(0.35, 4.5, 0.35), Vector3.new(bagX, FLOOR_Y + 14, bagZ), LAB_TRIM, Enum.Material.Metal, false)
	local bag = makePart(model, "TrainHoloBag", Vector3.new(7, 2.8, 2.8), Vector3.new(bagX, FLOOR_Y + 7.5, bagZ), accentCyan, Enum.Material.Neon, false)
	bag.Shape = Enum.PartType.Cylinder
	bag.Orientation = Vector3.new(0, 0, 90)
	bag.Transparency = 0.55
	for _, ringY in ipairs({ FLOOR_Y + 5, FLOOR_Y + 7.5, FLOOR_Y + 10 }) do
		local br = makePart(model, "TrainHoloBagRing", Vector3.new(0.3, 3.4, 3.4), Vector3.new(bagX, ringY, bagZ), accentGreen, Enum.Material.Neon, false)
		br.Shape = Enum.PartType.Cylinder
		br.Orientation = Vector3.new(0, 0, 90)
		br.Transparency = 0.3
	end
	-- Projektor-Sockel unter dem Boxsack
	local bagProj = makePart(model, "TrainHoloBagProjector", Vector3.new(0.4, 4, 4), Vector3.new(bagX, FLOOR_Y + 1.18, bagZ), accentCyan, Enum.Material.Neon, false)
	bagProj.Shape = Enum.PartType.Cylinder
	bagProj.Orientation = Vector3.new(0, 0, 90)
	bagProj.Transparency = 0.2

	-- 9. Zwei holographische Hanteln links/rechts auf Projektor-Sockeln.
	for _, sx in ipairs({ -1, 1 }) do
		local dbX = center.X + sx * 22
		local dbY = FLOOR_Y + 6
		local dbZ = center.Z - 5
		makePart(model, "TrainHoloDumbbellBar", Vector3.new(0.5, 0.5, 3.8), Vector3.new(dbX, dbY, dbZ), accentGreen, Enum.Material.Neon, false).Transparency = 0.3
		for _, dz in ipairs({ -1.9, 1.9 }) do
			makePart(model, "TrainHoloDumbbellWeight", Vector3.new(1.8, 1.8, 0.95), Vector3.new(dbX, dbY, dbZ + dz), accentCyan, Enum.Material.Neon, false).Transparency = 0.35
		end
		local proj = makePart(model, "TrainHoloDumbbellProjector", Vector3.new(0.3, 3.2, 3.2), Vector3.new(dbX, FLOOR_Y + 1.18, dbZ), accentCyan, Enum.Material.Neon, false)
		proj.Shape = Enum.PartType.Cylinder
		proj.Orientation = Vector3.new(0, 0, 90)
		proj.Transparency = 0.2
	end

	-- 10. Schwebende DNA-Spirale als Trainings-Ziel (vor dem Schild).
	local dnaX = center.X
	local dnaZ = center.Z - 12
	local dnaBaseY = FLOOR_Y + 4
	local dnaTopY = FLOOR_Y + 13
	local dnaProj = makePart(model, "TrainHoloDNAProjector", Vector3.new(0.3, 3.4, 3.4), Vector3.new(dnaX, FLOOR_Y + 1.18, dnaZ), accentGreen, Enum.Material.Neon, false)
	dnaProj.Shape = Enum.PartType.Cylinder
	dnaProj.Orientation = Vector3.new(0, 0, 90)
	dnaProj.Transparency = 0.2
	for i = 0, 10 do
		local t = i / 10
		local h = dnaBaseY + t * (dnaTopY - dnaBaseY)
		local a = t * math.pi * 3.2
		local r = 1.6
		local left = makePart(model, "TrainHoloDNANode", Vector3.new(0.55, 0.55, 0.55), Vector3.new(dnaX + math.cos(a) * r, h, dnaZ + math.sin(a) * r), accentGreen, Enum.Material.Neon, false)
		left.Shape = Enum.PartType.Ball
		left.Transparency = 0.2
		local right = makePart(model, "TrainHoloDNANode", Vector3.new(0.55, 0.55, 0.55), Vector3.new(dnaX - math.cos(a) * r, h, dnaZ - math.sin(a) * r), accentCyan, Enum.Material.Neon, false)
		right.Shape = Enum.PartType.Ball
		right.Transparency = 0.2
	end

	-- 11. Decken-Spotlights ueber dem Pad.
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local lx = center.X + sx * 22
			local lz = center.Z + sz * 10
			makePart(model, "TrainSpotMount", Vector3.new(3.2, 0.6, 3.2), Vector3.new(lx, FLOOR_Y + 17, lz), LAB_TRIM, Enum.Material.Metal, true)
			local cone = makePart(model, "TrainSpotCone", Vector3.new(0.4, 2.6, 2.6), Vector3.new(lx, FLOOR_Y + 16.5, lz), accentLightBase, Enum.Material.Neon, false)
			cone.Shape = Enum.PartType.Cylinder
			cone.Orientation = Vector3.new(0, 0, 90)
			cone.Transparency = 0.12
			local pl = Instance.new("PointLight")
			pl.Brightness = 1.6
			pl.Range = 24
			pl.Color = tint(primary, Color3.fromRGB(248, 250, 255), 0.4)
			pl.Parent = cone
		end
	end

	-- 12. Boden-Leitungen (Cyan-Streifen aussen um die Plattform).
	for _, dz in ipairs({ -bayHalfZ + 4, bayHalfZ - 4 }) do
		makePart(model, "TrainFloorConduit", Vector3.new(bayWidthX - 22, 0.05, 0.55), Vector3.new(x, LAYER_LANE_GLOW, bayZ + dz), accentCyan, Enum.Material.Neon, false).Transparency = 0.45
	end
	for _, sx in ipairs({ -1, 1 }) do
		makePart(model, "TrainFloorConduitSide", Vector3.new(0.55, 0.05, bayDepthZ - 14), Vector3.new(x + sx * (bayWidthX / 2 - 9), LAYER_LANE_GLOW, bayZ), accentCyan, Enum.Material.Neon, false).Transparency = 0.45
	end

	-- 13. Schwebendes "POWER TRAINING"-Schild ueber der Bay.
	local signAnchor = makePart(model, "TrainSignAnchor", Vector3.new(0.4, 0.4, 0.4), center + Vector3.new(0, 19, 4), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, false)
	signAnchor.Transparency = 1
	signAnchor.CanTouch = false
	label(
		signAnchor,
		string.format("⚡ POWER TRAINING\n+%s PWR/s ⋅ %s", NumberFormatter.format(bedDef.powerPerSecond), area.displayName),
		accentLightBase,
		200,
		UDim2.fromOffset(340, 92),
		Vector3.new(0, 0, 0)
	)

	-- Trainings-Bett (Vertrag mit TrainingZoneService): Model + Hitbox-Part.
	-- Hitbox deckt die gesamte Bay ab -> Spieler trainiert in der Bay.
	-- Attribute UNVERAENDERT.
	local bedModel = Instance.new("Model")
	bedModel.Name = bedDef.id
	bedModel.Parent = bedsFolder
	local hitbox = makePart(bedModel, "Hitbox", Vector3.new(bayWidthX - 10, 8, bayDepthZ - 6), Vector3.new(x, FLOOR_Y + 4, bayZ), primary, Enum.Material.SmoothPlastic, false)
	hitbox.Transparency = 1
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox:SetAttribute("RequiredRebirth", bedDef.requiredRebirth)
	hitbox:SetAttribute("PowerPerSecond", bedDef.powerPerSecond)

	-- Keine zusaetzlichen Training-Gates/Mauern: Zugriff und Auto-Training
	-- bleiben serverseitig ueber Hitbox-Attribute/Rebirth-Anforderung geregelt.
end

-- ---- Pet-Egg-Station ------------------------------------------------------

-- Pet-Egg-Station als Labor-Inkubator (Side-Bay). Jede Area bekommt genau
-- eine Station fuer ihr Stage-Egg. Vertrag mit EggCatchService/PetService:
-- Model-Attribute (AreaIndex/EggId/EggCost) + ClickDetector/Prompt "OpenEgg".
local function buildEggStation(parent, areaIndex, stationIndex, eggDef, pos)
	local model = Instance.new("Model")
	model.Name = string.format("Egg_A%d", areaIndex)
	model.Parent = parent

	local eggName = eggDef.displayName
	local accent = eggDef.color
	local isAreaShop = areaIndex >= 2

	if isAreaShop then
		local platformColor = tint(Color3.fromRGB(112, 32, 32), accent, 0.32)
		local stepColor = tint(Color3.fromRGB(78, 22, 22), accent, 0.22)
		local signColor = tint(Color3.fromRGB(40, 45, 46), accent, 0.12)

		local thronePad = makePart(model, "PetEggThronePedestal", Vector3.new(32, 1.1, 22), pos + Vector3.new(0, 0.55, 0), platformColor, Enum.Material.Metal, true)
		thronePad.Transparency = 0.03
		makePart(model, "PetEggThroneFrontStep", Vector3.new(34, 0.35, 5.5), pos + Vector3.new(0, 0.18, -13.8), stepColor, Enum.Material.SmoothPlastic, true)

		local backPanel = makePart(model, "PetShopBackPanel", Vector3.new(26, 8, 0.55), pos + Vector3.new(0, 6, 10.6), signColor, Enum.Material.Metal, false)
		label(backPanel, string.format("PET SHOP\nAREA %d", areaIndex), accent:Lerp(Color3.fromRGB(245, 248, 240), 0.35), 95, UDim2.fromOffset(280, 72), Vector3.new(0, 1.2, 0))
		neonStrip(model, Vector3.new(21, 0.18, 0.36), backPanel.Position + Vector3.new(0, -3.4, -0.38), accent, 0.28)

		for _, sideX in ipairs({ -15.5, 15.5 }) do
			local sidePanel = makePart(model, "PetShopSidePanel", Vector3.new(0.55, 5.5, 12), pos + Vector3.new(sideX, 3.1, 4), tint(accent, LAB_CYAN, 0.45), Enum.Material.Glass, false)
			sidePanel.Transparency = 0.76
		end

		local hoverRing = makePart(model, "PetEggHoverRing", Vector3.new(18, 0.12, 18), pos + Vector3.new(0, 1.18, 0), accent, Enum.Material.Neon, false)
		hoverRing.Shape = Enum.PartType.Cylinder
		hoverRing.Orientation = Vector3.new(0, 0, 90)
		hoverRing.Transparency = 0.55

		local capsule = makePart(model, "EggCapsule", Vector3.new(8.8, 10.8, 8.8), pos + Vector3.new(0, 8.7, 0), accent, Enum.Material.SmoothPlastic, false)
		capsule.CanQuery = true -- anklickbar (OpenEgg ClickDetector)
		capsule.Shape = Enum.PartType.Ball
		capsule.Transparency = 0.05
		for i = 0, 7 do
			local a = i * math.pi * 2 / 8
			local spike = makePart(model, "VirusEggNodule", Vector3.new(1.2, 1.2, 1.2), capsule.Position + Vector3.new(math.cos(a) * 5.4, 0.5 + math.sin(i * 1.7) * 1.3, math.sin(a) * 5.4), accent:Lerp(Color3.fromRGB(28, 34, 38), 0.35), Enum.Material.SmoothPlastic, false)
			spike.Shape = Enum.PartType.Ball
			spike.CanCollide = false
		end

		local glow = Instance.new("PointLight")
		glow.Name = "VirusEggGlow"
		glow.Brightness = 0.85
		glow.Range = 16
		glow.Color = accent:Lerp(Color3.fromRGB(220, 255, 225), 0.35)
		glow.Parent = capsule

		model:SetAttribute("AreaIndex", areaIndex)
		model:SetAttribute("EggId", eggDef.eggId)
		model:SetAttribute("EggName", eggName)
		model:SetAttribute("EggCost", eggDef.cost)
		local cd = Instance.new("ClickDetector")
		cd.Name = "OpenEgg"
		cd.MaxActivationDistance = 18
		cd.Parent = capsule
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "OpenEggPrompt"
		prompt.ActionText = "Open Egg"
		prompt.ObjectText = eggName
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 16
		prompt.RequiresLineOfSight = false
		prompt.Parent = capsule

		label(
			capsule,
			string.format("%s\nCost: %s DNA", eggName, NumberFormatter.format(eggDef.cost)),
			accent:Lerp(Color3.fromRGB(245, 248, 240), 0.2),
			95,
			UDim2.fromOffset(320, 86),
			Vector3.new(0, 7, 0)
		)
		return
	end

	-- Eigener Inkubator-Sockel + Rueckpaneel (markiert die Side-Bay).
	local padSize = if isAreaShop then Vector3.new(24, 0.42, 20) else Vector3.new(15, 0.32, 15)
	local padEdgeSize = if isAreaShop then Vector3.new(24.8, 0.1, 20.8) else Vector3.new(15.4, 0.08, 15.4)
	local bayPad = makePart(model, "IncubatorBayPad", padSize, pos + Vector3.new(0, -0.24, 0), Color3.fromRGB(128, 42, 42), Enum.Material.SmoothPlastic, true)
	bayPad.Transparency = 0.05
	makePart(model, "IncubatorBayEdge", padEdgeSize, pos + Vector3.new(0, 0.02, 0), Color3.fromRGB(85, 28, 28), Enum.Material.SmoothPlastic, false).Transparency = 0.28
	local backPanelSize = if isAreaShop then Vector3.new(22, 13, 0.65) else Vector3.new(13, 11, 0.5)
	local backPanelOffset = if isAreaShop then Vector3.new(0, 6.8, 8.8) else Vector3.new(0, 6, 7)
	local backPanel = makePart(model, "IncubatorBackPanel", backPanelSize, pos + backPanelOffset, Color3.fromRGB(40, 45, 46), Enum.Material.Metal, false)
	if isAreaShop then
		label(backPanel, string.format("PET SHOP\nAREA %d", areaIndex), accent:Lerp(Color3.fromRGB(245, 248, 240), 0.35), 95, UDim2.fromOffset(280, 72), Vector3.new(0, 4.4, 0))
		neonStrip(model, Vector3.new(18, 0.18, 0.4), backPanel.Position + Vector3.new(0, -4.8, -0.45), accent, 0.22)
		for _, sideX in ipairs({ -12.2, 12.2 }) do
			local sidePanel = makePart(model, "PetShopSideGlass", Vector3.new(0.55, 6.4, 13), pos + Vector3.new(sideX, 3.35, 1.8), tint(accent, LAB_CYAN, 0.45), Enum.Material.Glass, false)
			sidePanel.Transparency = 0.74
			neonStrip(model, Vector3.new(0.38, 0.16, 10.5), sidePanel.Position + Vector3.new(0, 3.4, 0), accent, 0.35)
		end
	else
		label(backPanel, "PET INCUBATOR", accent:Lerp(Color3.fromRGB(225, 230, 222), 0.5), 30, UDim2.fromOffset(150, 36), Vector3.new(0, 3.6, 0))
	end

	local baseSize = if isAreaShop then Vector3.new(14.5, 1, 14.5) else Vector3.new(12, 0.85, 12)
	local base = makePart(model, "EggBase", baseSize, pos + Vector3.new(0, -0.15, 0), Color3.fromRGB(112, 36, 36), Enum.Material.Metal, true)
	base.Shape = Enum.PartType.Cylinder
	base.Orientation = Vector3.new(0, 0, 90)

	local ringSize = if isAreaShop then Vector3.new(15.4, 0.55, 15.4) else Vector3.new(12.6, 0.5, 12.6)
	local ring = makePart(model, "EggRing", ringSize, pos + Vector3.new(0, 0.8, 0), accent:Lerp(LAB_TRIM, 0.45), Enum.Material.SmoothPlastic, false)
	ring.Shape = Enum.PartType.Cylinder
	ring.Orientation = Vector3.new(0, 0, 90)
	ring.Transparency = 0.38

	-- Glas-Inkubationskammer um die Stage-Probe.
	local glassTransparency = math.clamp(0.76 - areaIndex * 0.025, 0.5, 0.74)
	local chamberSize = if isAreaShop then Vector3.new(8.8, 10.5, 8.8) else Vector3.new(7, 9, 7)
	local chamber = makePart(model, "IncubationGlass", chamberSize, pos + Vector3.new(0, if isAreaShop then 5.5 else 5, 0), tint(accent, LAB_WHITE, 0.55), Enum.Material.Glass, false)
	chamber.Shape = Enum.PartType.Cylinder
	chamber.Orientation = Vector3.new(0, 0, 90)
	chamber.Transparency = glassTransparency
	local capSize = if isAreaShop then Vector3.new(9.8, 0.8, 9.8) else Vector3.new(8, 0.7, 8)
	makePart(model, "IncubationCapBottom", capSize, pos + Vector3.new(0, 0.9, 0), LAB_TRIM, Enum.Material.Metal, false).Shape = Enum.PartType.Cylinder
	makePart(model, "IncubationCapTop", capSize, pos + Vector3.new(0, if isAreaShop then 10.2 else 9.1, 0), LAB_DARK, Enum.Material.Metal, false).Shape = Enum.PartType.Cylinder

	-- Spaetere Areas bekommen sichtbar schwerere Containment-Streben.
	local posts = if areaIndex <= 1 then 2 elseif areaIndex <= 5 then 4 else 6
	for i = 0, posts - 1 do
		local a = i * (2 * math.pi / posts) + math.pi / 4
		local radius = if isAreaShop then 5.4 else 4.4
		makePart(model, "ContainmentStrut", Vector3.new(0.55, if isAreaShop then 10.8 else 9.5, 0.55), pos + Vector3.new(math.cos(a) * radius, if isAreaShop then 5.55 else 5, math.sin(a) * radius), LAB_DARK, Enum.Material.Metal, false)
	end
	makePart(model, "IncubatorStatusLight", Vector3.new(0.9, 0.9, 0.3), pos + Vector3.new(if isAreaShop then 5.8 else 4.6, 2.4, if isAreaShop then 5.8 else 4.6), accent, Enum.Material.Neon, false).Shape = Enum.PartType.Ball

	-- Kleines Kontroll-Terminal an der Seite.
	local terminal = makePart(model, "IncubatorTerminal", if isAreaShop then Vector3.new(3.8, 3.8, 2.4) else Vector3.new(3, 3.4, 2), pos + Vector3.new(if isAreaShop then 8.4 else 6.5, 1.7, -0.4), Color3.fromRGB(44, 50, 52), Enum.Material.Metal, false)
	makePart(model, "IncubatorTerminalScreen", Vector3.new(0.3, 2, 1.5), terminal.Position + Vector3.new(-1.6, 0.6, 0), accent, Enum.Material.SmoothPlastic, false).Transparency = 0.2

	-- Ei / Kapsel in der Mitte (Klick-Ziel; Vertrag unveraendert).
	local capsule = makePart(model, "EggCapsule", if isAreaShop then Vector3.new(6.4, 8.2, 6.4) else Vector3.new(5, 6.5, 5), pos + Vector3.new(0, if isAreaShop then 5 else 4.5, 0), accent, Enum.Material.SmoothPlastic, false)
	capsule.CanQuery = true -- anklickbar (OpenEgg ClickDetector)
	capsule.Shape = Enum.PartType.Ball
	capsule.Transparency = 0.1
	local glow = Instance.new("PointLight")
	glow.Brightness = if isAreaShop then 0.7 else 0.45
	glow.Range = if isAreaShop then 14 else 9
	glow.Color = accent:Lerp(Color3.fromRGB(210, 220, 216), 0.55)
	glow.Parent = capsule

	-- Egg-Daten + Klick-Hook (EggCatchService verbindet "OpenEgg").
	model:SetAttribute("AreaIndex", areaIndex)
	model:SetAttribute("EggId", eggDef.eggId)
	model:SetAttribute("EggName", eggName)
	model:SetAttribute("EggCost", eggDef.cost)
	local cd = Instance.new("ClickDetector")
	cd.Name = "OpenEgg"
	cd.MaxActivationDistance = if isAreaShop then 18 else 14
	cd.Parent = capsule
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenEggPrompt"
	prompt.ActionText = "Open Egg"
	prompt.ObjectText = eggName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = if isAreaShop then 16 else 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = capsule

	label(
		capsule,
		string.format("%s\nCost: %s DNA", eggName, NumberFormatter.format(eggDef.cost)),
		accent,
		if isAreaShop then 95 else 40,
		if isAreaShop then UDim2.fromOffset(340, 92) else UDim2.fromOffset(240, 76),
		if isAreaShop then Vector3.new(0, 7, 0) else Vector3.new(0, 5.5, 0)
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
	banner.Transparency = 0.2
end

local function addCeilingConduits(parent, cx)
	for _, z in ipairs({ -66, -18, 30, 78 }) do
		makePart(parent, "CeilingPipe", Vector3.new(230, 1.1, 1.1), Vector3.new(cx - 24, FLOOR_Y + L.WallHeight - 5.4, z), LAB_DARK, Enum.Material.Metal, false)
		neonStrip(parent, Vector3.new(212, 0.25, 0.25), Vector3.new(cx - 18, FLOOR_Y + L.WallHeight - 4.65, z), LAB_GREEN, 0.35)
	end
end

-- ---- Spawn-Environment-Polish --------------------------------------------
-- Rein dekorativer Pass um den Spawn. Beruehrt KEIN System (SpawnLocation,
-- NPC-Stationen, Pet-Egg, Hero-Statue, Hub, Egg-Catch, Training). Fuegt nur
-- Wand-Panels, Lueftungen, Decken-Lichter, Kabel-Trassen und einen
-- weichen Spawn-Ring um den Spawnpunkt hinzu. Alles non-collide / Anchored.
local function addSpawnEnvironmentPolish(parent, cx)
	local envFolder = makeFolder("SpawnEnvironment", parent)
	local wallDeco = makeFolder("WallDeco", envFolder)
	local ceilingDeco = makeFolder("CeilingDeco", envFolder)
	local ringMarker = makeFolder("SpawnRingMarker", envFolder)

	-- Spawn-X-Range: cx-150 .. 0 (mit cx=-180 also -330 .. 0).
	-- Innenseiten der Seitenwaende: z=-85 (links) und z=130 (rechts).

	-- === SPAWN-RING um die SpawnLocation =================================
	-- Cyan Glow-Disc unter der SpawnLocation (welche bei Y=0..1.0 steht).
	-- Sichtbar wird nur der Rand ausserhalb der 14x14-Spawnplatte.
	-- Cylinder-Konvention (siehe buildMaintenanceHatch): Size.X = Dicke der
	-- Scheibe, Size.Y/Z = Durchmesser; Orientation (0,0,90) legt sie flach.
	local glowDisc = makePart(ringMarker, "SpawnRingGlow", Vector3.new(0.16, 28, 28), Vector3.new(cx, FLOOR_Y + 0.08, 0), LAB_CYAN, Enum.Material.Neon, false)
	glowDisc.Shape = Enum.PartType.Cylinder
	glowDisc.Orientation = Vector3.new(0, 0, 90)
	glowDisc.Transparency = 0.55
	local discRim = makePart(ringMarker, "SpawnRingRim", Vector3.new(0.10, 30, 30), Vector3.new(cx, FLOOR_Y + 0.12, 0), Color3.fromRGB(28, 32, 36), Enum.Material.SmoothPlastic, false)
	discRim.Shape = Enum.PartType.Cylinder
	discRim.Orientation = Vector3.new(0, 0, 90)
	discRim.Transparency = 0.08
	-- Vier Bodenlampen-Pylonen an den Diagonalen (radius 12, off-spawn).
	for i = 0, 3 do
		local a = math.pi / 4 + i * math.pi / 2
		local lx = cx + math.cos(a) * 12
		local lz = math.sin(a) * 12
		makePart(ringMarker, "SpawnLampPost", Vector3.new(0.6, 4, 0.6), Vector3.new(lx, FLOOR_Y + 2, lz), LAB_DARK, Enum.Material.Metal, false)
		local lamp = makePart(ringMarker, "SpawnLampOrb", Vector3.new(0.95, 0.95, 0.95), Vector3.new(lx, FLOOR_Y + 4.4, lz), LAB_CYAN, Enum.Material.Neon, false)
		lamp.Shape = Enum.PartType.Ball
		lamp.Transparency = 0.1
		local pl = Instance.new("PointLight")
		pl.Brightness = 0.4
		pl.Range = 9
		pl.Color = LAB_CYAN
		pl.Parent = lamp
	end
	-- Boden-Label "SUBJECT ENTRY" direkt vor der SpawnLocation (z=+18,
	-- weg vom Hub und ausserhalb der 14-Stud-Spawnplatte). Inline-SurfaceGui.
	local entryPlate = makePart(ringMarker, "SpawnEntryLabel", Vector3.new(14, 0.05, 2.4), Vector3.new(cx, FLOOR_Y + 1.05, 18), Color3.fromRGB(28, 32, 36), Enum.Material.SmoothPlastic, false)
	entryPlate.Transparency = 0.1
	do
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Top
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 50
		sg.LightInfluence = 1
		sg.AlwaysOnTop = false
		sg.Adornee = entryPlate
		sg.Parent = entryPlate
		local tl = Instance.new("TextLabel")
		tl.BackgroundTransparency = 1
		tl.Size = UDim2.fromScale(0.94, 0.78)
		tl.Position = UDim2.fromScale(0.03, 0.11)
		tl.Text = "SUBJECT ENTRY"
		tl.Font = Enum.Font.GothamBold
		tl.TextScaled = true
		tl.TextColor3 = Color3.fromRGB(180, 240, 230)
		tl.TextStrokeColor3 = Color3.new(0, 0, 0)
		tl.TextStrokeTransparency = 0.35
		tl.Parent = sg
	end

	-- === SEITENWAND-PANELS mit Schildern (beide Wände) ====================
	-- An Stellen positioniert, wo aktuell weder Hub-Pylonen noch
	-- NPC-Stationen oder Containment-Tubes vor der Wand stehen.
	-- Wand-Innenseiten: z=-85 (links) und z=130 (rechts). Panels haengen
	-- knapp davor (facing schiebt die Frontplatten Richtung Raum-Mitte).
	local wallSigns = {
		{ x = -280, z = -85, sign = "QUARANTINE",       facing = 1 },
		{ x = -90,  z = -85, sign = "BIOHAZARD ZONE",   facing = 1 },
		{ x = -280, z = 130, sign = "DNA RESEARCH",     facing = -1 },
		{ x = -90,  z = 130, sign = "MUTATION CONTROL", facing = -1 },
	}
	for i, spot in ipairs(wallSigns) do
		-- Helle Labor-Wandflaeche.
		makePart(wallDeco, "SpawnWallPanel" .. i, Vector3.new(26, 14, 0.35), Vector3.new(spot.x, FLOOR_Y + 12, spot.z + 0.4 * spot.facing), Color3.fromRGB(220, 226, 230), Enum.Material.SmoothPlastic, false)
		-- Dunkler Aussenrahmen.
		makePart(wallDeco, "SpawnWallFrame" .. i, Vector3.new(28, 15.5, 0.2), Vector3.new(spot.x, FLOOR_Y + 12, spot.z + 0.3 * spot.facing), LAB_DARK, Enum.Material.SmoothPlastic, false)
		-- Akzent-Streifen (grün unten, cyan oben).
		neonStrip(wallDeco, Vector3.new(22, 0.28, 0.28), Vector3.new(spot.x, FLOOR_Y + 5.5, spot.z + 0.62 * spot.facing), LAB_GREEN, 0.32)
		neonStrip(wallDeco, Vector3.new(22, 0.28, 0.28), Vector3.new(spot.x, FLOOR_Y + 18.5, spot.z + 0.62 * spot.facing), LAB_CYAN, 0.35)
		-- Dunkles Backboard mit Schrift.
		local signPlate = makePart(wallDeco, "SpawnWallSignPlate" .. i, Vector3.new(18, 4.4, 0.4), Vector3.new(spot.x, FLOOR_Y + 12, spot.z + 0.65 * spot.facing), LAB_DARK, Enum.Material.SmoothPlastic, false)
		label(signPlate, spot.sign, Color3.fromRGB(160, 240, 220), 55, UDim2.fromOffset(260, 56), Vector3.new(0, 0, 0))
		-- Vertikale Metall-Trim-Streifen.
		for _, dx in ipairs({ -13, 13 }) do
			makePart(wallDeco, "SpawnWallTrim" .. i .. "_" .. dx, Vector3.new(0.55, 15, 0.4), Vector3.new(spot.x + dx, FLOOR_Y + 12, spot.z + 0.5 * spot.facing), LAB_TRIM, Enum.Material.Metal, false)
		end
		-- Mini-Status-LED oben.
		local led = makePart(wallDeco, "SpawnWallLed" .. i, Vector3.new(0.7, 0.7, 0.25), Vector3.new(spot.x + 11, FLOOR_Y + 18, spot.z + 0.65 * spot.facing), LAB_GREEN, Enum.Material.Neon, false)
		led.Shape = Enum.PartType.Ball
		led.Transparency = 0.1
	end

	-- Glas-Beobachtungsfenster mit Virus-Probe dahinter (jeweils zwischen
	-- den Sign-Panels). Wirkt wie eine echte Quarantäne-Vitrine.
	local glassSpots = {
		{ x = -185, z = -85, facing = 1 },
		{ x = -185, z = 130, facing = -1 },
	}
	for i, spot in ipairs(glassSpots) do
		-- Dunkler Rahmen vor dem Fenster.
		makePart(wallDeco, "SpawnGlassFrame" .. i, Vector3.new(18, 10, 0.6), Vector3.new(spot.x, FLOOR_Y + 14, spot.z + 0.35 * spot.facing), LAB_DARK, Enum.Material.Metal, false)
		-- Glasscheibe.
		local glass = makePart(wallDeco, "SpawnGlassPane" .. i, Vector3.new(14, 7, 0.35), Vector3.new(spot.x, FLOOR_Y + 14, spot.z + 0.6 * spot.facing), Color3.fromRGB(132, 178, 178), Enum.Material.Glass, false)
		glass.Transparency = 0.55
		-- Virus-Probe-Tank dahinter (sichtbar durch das Fenster).
		-- Cylinder vertikal: Size.X = Hoehe, Size.Y/Z = Durchmesser.
		local tank = makePart(wallDeco, "SpawnGlassTank" .. i, Vector3.new(5.2, 3.4, 3.4), Vector3.new(spot.x, FLOOR_Y + 13.5, spot.z + 1.4 * spot.facing), tint(LAB_GREEN, LAB_OLIVE, 0.25), Enum.Material.Glass, false)
		tank.Shape = Enum.PartType.Cylinder
		tank.Orientation = Vector3.new(0, 0, 90)
		tank.Transparency = 0.32
		-- Sample-Kern.
		local core = makePart(wallDeco, "SpawnGlassTankCore" .. i, Vector3.new(3, 1.5, 1.5), tank.Position, tint(LAB_GREEN, Color3.fromRGB(220, 240, 200), 0.3), Enum.Material.Neon, false)
		core.Shape = Enum.PartType.Cylinder
		core.Orientation = Vector3.new(0, 0, 90)
		core.Transparency = 0.18
		-- Tank-Caps (flache Discs).
		local capTop = makePart(wallDeco, "SpawnGlassTankCapTop" .. i, Vector3.new(0.4, 4, 4), Vector3.new(spot.x, FLOOR_Y + 16.3, spot.z + 1.4 * spot.facing), LAB_TRIM, Enum.Material.Metal, false)
		capTop.Shape = Enum.PartType.Cylinder
		capTop.Orientation = Vector3.new(0, 0, 90)
		local capBot = makePart(wallDeco, "SpawnGlassTankCapBot" .. i, Vector3.new(0.4, 4, 4), Vector3.new(spot.x, FLOOR_Y + 10.7, spot.z + 1.4 * spot.facing), LAB_DARK, Enum.Material.Metal, false)
		capBot.Shape = Enum.PartType.Cylinder
		capBot.Orientation = Vector3.new(0, 0, 90)
	end

	-- Lüftungsgitter hoch oben an den Wänden.
	local ventSpots = {
		{ x = -240, z = -85, facing = 1 },
		{ x = -135, z = -85, facing = 1 },
		{ x = -40,  z = -85, facing = 1 },
		{ x = -240, z = 130, facing = -1 },
		{ x = -135, z = 130, facing = -1 },
		{ x = -40,  z = 130, facing = -1 },
	}
	for i, spot in ipairs(ventSpots) do
		makePart(wallDeco, "SpawnVent" .. i, Vector3.new(7, 3.5, 0.35), Vector3.new(spot.x, FLOOR_Y + 23.5, spot.z + 0.45 * spot.facing), Color3.fromRGB(70, 78, 82), Enum.Material.Metal, false)
		for j = -2, 2 do
			makePart(wallDeco, "SpawnVentSlat" .. i .. "_" .. j, Vector3.new(6, 0.18, 0.18), Vector3.new(spot.x, FLOOR_Y + 23.5 + j * 0.65, spot.z + 0.62 * spot.facing), LAB_DARK, Enum.Material.Metal, false)
		end
	end

	-- Lange Kabel-Trasse oben an beiden Wänden mit Mounts (innerhalb der
	-- Spawn-X-Range -330..0, Mitte cx+15=-165, Size 280).
	for _, z in ipairs({ -85, 130 }) do
		local sign = if z < 0 then 1 else -1
		makePart(wallDeco, "SpawnCableTray", Vector3.new(280, 0.7, 1.4), Vector3.new(cx + 15, FLOOR_Y + 27.2, z + 1.2 * sign), LAB_DARK, Enum.Material.Metal, false)
		for _, x in ipairs({ -290, -200, -110, -25 }) do
			makePart(wallDeco, "SpawnCableMount", Vector3.new(0.4, 2, 0.55), Vector3.new(x, FLOOR_Y + 28.2, z + 0.85 * sign), LAB_TRIM, Enum.Material.Metal, false)
		end
		neonStrip(wallDeco, Vector3.new(260, 0.16, 0.16), Vector3.new(cx + 15, FLOOR_Y + 26.7, z + 1.7 * sign), LAB_GREEN, 0.5)
	end

	-- === DECKEN-DEKO =====================================================
	-- Vier zusätzliche flache Labor-Lichtpanels (matt-neon, kein grelles
	-- Bloom). Eingerahmt mit dunklen Bezels.
	local ceilingY = FLOOR_Y + L.WallHeight - 1.5
	local ceilingPanels = {
		{ x = -260, z = 30 },
		{ x = -260, z = -30 },
		{ x = -80,  z = 30 },
		{ x = -80,  z = -30 },
	}
	for i, spot in ipairs(ceilingPanels) do
		local panel = makePart(ceilingDeco, "SpawnLightPanel" .. i, Vector3.new(16, 0.3, 8), Vector3.new(spot.x, ceilingY, spot.z), LAB_PURPLE_SOFT, Enum.Material.Neon, false)
		panel.Transparency = 0.18
		makePart(ceilingDeco, "SpawnLightFrame" .. i, Vector3.new(18, 0.18, 10), Vector3.new(spot.x, ceilingY + 0.25, spot.z), LAB_DARK, Enum.Material.SmoothPlastic, false)
		-- Starke SurfaceLight: leuchtet den Boden + Waende des Spawn-Labors aus.
		local sl = Instance.new("SurfaceLight")
		sl.Face = Enum.NormalId.Bottom
		sl.Brightness = 3.2
		sl.Range = 45
		sl.Angle = 160
		sl.Color = Color3.fromRGB(238, 226, 255)
		sl.Shadows = false
		sl.Parent = panel
	end

	-- Zwei rote Warnleuchten an der Decke (sparsam, klein, im Sichtfeld).
	for i, spot in ipairs({
		{ x = -250, z = 0 },
		{ x = -90,  z = 0 },
	}) do
		local base = makePart(ceilingDeco, "SpawnWarnBase" .. i, Vector3.new(0.6, 2.2, 2.2), Vector3.new(spot.x, FLOOR_Y + L.WallHeight - 1.8, spot.z), LAB_DARK, Enum.Material.Metal, false)
		base.Shape = Enum.PartType.Cylinder
		base.Orientation = Vector3.new(0, 0, 90)
		local lamp = makePart(ceilingDeco, "SpawnWarnLamp" .. i, Vector3.new(1.3, 1.3, 1.3), Vector3.new(spot.x, FLOOR_Y + L.WallHeight - 2.6, spot.z), LAB_WARNING_RED, Enum.Material.Neon, false)
		lamp.Shape = Enum.PartType.Ball
		lamp.Transparency = 0.18
		local pl = Instance.new("PointLight")
		pl.Brightness = 0.25
		pl.Range = 7
		pl.Color = LAB_WARNING_RED
		pl.Parent = lamp
	end

	-- Kurze Decken-Querträger zwischen den Lichtpanels (selbe X-Range wie
	-- die bestehenden Ceiling-Pipes, etwas tiefer als die CeilingPanels).
	for _, z in ipairs({ -30, 30 }) do
		makePart(ceilingDeco, "SpawnCeilingTruss", Vector3.new(220, 0.55, 0.75), Vector3.new(cx - 24, FLOOR_Y + L.WallHeight - 1.9, z), LAB_DARK, Enum.Material.Metal, false)
	end

	-- === ATMOSPHÄRE: 3 sanfte PointLights ================================
	-- Anker-Parts sind unsichtbar (Transparency=1, mini-size).
	local atmSpots = {
		{ x = -280, y = 14, z = 0,   color = LAB_PURPLE, br = 1.4, range = 32 },
		{ x = -90,  y = 14, z = 0,   color = LAB_PURPLE, br = 1.4, range = 32 },
		{ x = cx,   y = 8,  z = -15, color = LAB_PURPLE, br = 1.0, range = 22 },
	}
	for i, spot in ipairs(atmSpots) do
		local anchor = makePart(envFolder, "SpawnAtmLight" .. i, Vector3.new(0.2, 0.2, 0.2), Vector3.new(spot.x, FLOOR_Y + spot.y, spot.z), Color3.fromRGB(0, 0, 0), Enum.Material.SmoothPlastic, false)
		anchor.Transparency = 1
		local pl = Instance.new("PointLight")
		pl.Brightness = spot.br
		pl.Range = spot.range
		pl.Color = spot.color
		pl.Parent = anchor
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
-- Reihe von drei kleinen Specimen-Vitrinen. Ersetzt den alten klobigen
-- Stufensockel + die 4 Monitore + die grosse Glas-Kuppel mit einer cleanen,
-- bedrohlichen Ausstellung in Rot + Dunkelblau. Signatur bleibt
-- (parent, center, accent) damit der bestehende Aufrufer unveraendert
-- funktioniert; der accent-Parameter wird bewusst ignoriert.
local function buildVirusStatue(parent, center: Vector3, _accent: Color3?)
	local model = Instance.new("Model")
	model.Name = "SpecimenRow"
	model.Parent = parent

	local cx, cz = center.X, center.Z
	local SPACING = 18

	-- Rote und dunkelblaue Specimen-Farben (kraftvoll, leicht toxisch,
	-- nicht kitschig). Bewusst dunkel gewaehlt, damit der Neon-Kern strahlt.
	local SPEC_RED = Color3.fromRGB(178, 42, 56)
	local SPEC_BLUE = Color3.fromRGB(48, 70, 142)
	local SPEC_HYBRID = SPEC_RED:Lerp(SPEC_BLUE, 0.55)
	local DARK_BASE = Color3.fromRGB(16, 18, 22)
	local DARK_METAL = Color3.fromRGB(30, 34, 42)

	local specimens = {
		{ name = "SPECIMEN A-04", sub = "CYANIC STRAIN",  main = SPEC_BLUE,   accent = SPEC_RED },
		{ name = "SPECIMEN B-09", sub = "HEMATIC STRAIN", main = SPEC_RED,    accent = SPEC_BLUE },
		{ name = "SPECIMEN C-17", sub = "HYBRID STRAIN",  main = SPEC_HYBRID, accent = SPEC_BLUE },
	}

	for i, spec in ipairs(specimens) do
		local sx = cx + (i - 2) * SPACING

		-- Kleiner dunkler Sockel (eine einzige flache Cylinder-Disc,
		-- ~1.5 Studs hoch, 8 Studs Durchmesser). Kein weisser Block,
		-- kein klobiger Stufensockel, kein Warn-Rand. Bottom leicht im
		-- Boden versenkt -> kein Z-Fighting.
		local pedestal = makePart(model, "SpecimenPedestal_" .. i, Vector3.new(1.6, 8, 8), Vector3.new(sx, FLOOR_Y + 0.7, cz), DARK_BASE, Enum.Material.Metal, true)
		pedestal.Shape = Enum.PartType.Cylinder
		pedestal.Orientation = Vector3.new(0, 0, 90)
		-- Dezenter farbiger Akzent-Ring oben am Sockel (kein Yellow-Warn).
		local accentRing = makePart(model, "SpecimenPedestalRim_" .. i, Vector3.new(0.14, 8.2, 8.2), Vector3.new(sx, FLOOR_Y + 1.55, cz), spec.main, Enum.Material.Neon, false)
		accentRing.Shape = Enum.PartType.Cylinder
		accentRing.Orientation = Vector3.new(0, 0, 90)
		accentRing.Transparency = 0.4

		-- Schlanke Glas-Vitrine (vertikaler Cylinder ~10 Studs hoch,
		-- 6 Studs Durchmesser). Tinted in der Specimen-Farbe.
		local glass = makePart(model, "SpecimenVitrine_" .. i, Vector3.new(10, 6, 6), Vector3.new(sx, FLOOR_Y + 6.7, cz), tint(spec.main, Color3.fromRGB(150, 158, 170), 0.55), Enum.Material.Glass, false)
		glass.Shape = Enum.PartType.Cylinder
		glass.Orientation = Vector3.new(0, 0, 90)
		glass.Transparency = 0.58

		-- Bottom- und Top-Cap (Metall).
		local botCap = makePart(model, "SpecimenVitrineBot_" .. i, Vector3.new(0.6, 6.6, 6.6), Vector3.new(sx, FLOOR_Y + 1.7, cz), DARK_METAL, Enum.Material.Metal, true)
		botCap.Shape = Enum.PartType.Cylinder
		botCap.Orientation = Vector3.new(0, 0, 90)
		local topCap = makePart(model, "SpecimenVitrineTop_" .. i, Vector3.new(0.6, 6.6, 6.6), Vector3.new(sx, FLOOR_Y + 11.7, cz), DARK_METAL, Enum.Material.Metal, true)
		topCap.Shape = Enum.PartType.Cylinder
		topCap.Orientation = Vector3.new(0, 0, 90)
		-- Top-Lampe der Vitrine (schmaler Neon-Punkt in der Specimen-Farbe).
		local topLamp = makePart(model, "SpecimenVitrineLamp_" .. i, Vector3.new(0.9, 0.9, 0.9), Vector3.new(sx, FLOOR_Y + 12.2, cz), spec.main, Enum.Material.Neon, false)
		topLamp.Shape = Enum.PartType.Ball
		topLamp.Transparency = 0.18

		-- Vier dünne dunkle Streben an den Ecken der Vitrine.
		for j = 0, 3 do
			local a = j * math.pi / 2 + math.pi / 4
			local stx = sx + math.cos(a) * 3.4
			local stz = cz + math.sin(a) * 3.4
			makePart(model, "SpecimenStrut_" .. i .. "_" .. j, Vector3.new(0.4, 10, 0.4), Vector3.new(stx, FLOOR_Y + 6.7, stz), DARK_METAL, Enum.Material.Metal, true)
		end

		-- Das eigentliche Specimen: Capsid-Hülle + Neon-Kern + Spikes.
		local specY = FLOOR_Y + 6.7
		local capsid = makePart(model, "SpecimenCapsid_" .. i, Vector3.new(3.6, 3.6, 3.6), Vector3.new(sx, specY, cz), tint(spec.main, DARK_BASE, 0.3), Enum.Material.Glass, false)
		capsid.Shape = Enum.PartType.Ball
		capsid.Transparency = 0.30
		local innerCore = makePart(model, "SpecimenCore_" .. i, Vector3.new(2, 2, 2), Vector3.new(sx, specY, cz), spec.main, Enum.Material.Neon, false)
		innerCore.Shape = Enum.PartType.Ball
		innerCore.Transparency = 0.12
		local coreLight = Instance.new("PointLight")
		coreLight.Brightness = 0.65
		coreLight.Range = 11
		coreLight.Color = spec.main
		coreLight.Parent = innerCore

		-- 10 Spike-Proteine: Stiel + Knopf, ikosaedrisch verteilt.
		local spikeDirs = {
			Vector3.new(0, 1, 0), Vector3.new(0, -1, 0),
			Vector3.new(1, 0.4, 0), Vector3.new(-1, 0.4, 0),
			Vector3.new(0, 0.4, 1), Vector3.new(0, 0.4, -1),
			Vector3.new(1, -0.4, 1), Vector3.new(-1, -0.4, 1),
			Vector3.new(1, -0.4, -1), Vector3.new(-1, -0.4, -1),
		}
		for k, d in ipairs(spikeDirs) do
			local u = d.Unit
			local stalkPos = Vector3.new(sx, specY, cz) + u * 2.4
			local stalk = makePart(model, "SpecimenSpike_" .. i .. "_" .. k, Vector3.new(0.34, 1.4, 0.34), stalkPos, tint(spec.main, DARK_METAL, 0.4), Enum.Material.SmoothPlastic, false)
			local up = if math.abs(u.Y) > 0.99 then Vector3.new(0, 0, 1) else Vector3.new(0, 1, 0)
			stalk.CFrame = CFrame.lookAt(stalkPos, stalkPos + u, up) * CFrame.Angles(math.rad(90), 0, 0)
			local knob = makePart(model, "SpecimenSpikeTip_" .. i .. "_" .. k, Vector3.new(0.6, 0.6, 0.6), Vector3.new(sx, specY, cz) + u * 3.2, spec.accent, Enum.Material.Neon, false)
			knob.Shape = Enum.PartType.Ball
			knob.Transparency = 0.18
		end

		-- Schmale Plakette an der Vorderseite (Richtung Spieler, +Z).
		local plaqueZ = cz + 5.4
		local plaqueStand = makePart(model, "SpecimenPlaqueStand_" .. i, Vector3.new(0.5, 2.0, 0.5), Vector3.new(sx, FLOOR_Y + 1.3, plaqueZ), DARK_METAL, Enum.Material.Metal, true)
		local plaque = makePart(model, "SpecimenPlaque_" .. i, Vector3.new(7, 2.0, 0.3), Vector3.new(sx, FLOOR_Y + 2.6, plaqueZ + 0.1), Color3.fromRGB(12, 14, 18), Enum.Material.Metal, false)
		label(plaque, spec.name .. "\n" .. spec.sub, spec.main:Lerp(Color3.fromRGB(238, 246, 240), 0.5), 30, UDim2.fromOffset(150, 40), Vector3.new(0, 0, 0))

		-- Ein zarter Bodenschatten-Glow direkt unter dem Sockel.
		local underGlow = makePart(model, "SpecimenUnderGlow_" .. i, Vector3.new(0.08, 9.5, 9.5), Vector3.new(sx, FLOOR_Y + 0.06, cz), spec.main, Enum.Material.Neon, false)
		underGlow.Shape = Enum.PartType.Cylinder
		underGlow.Orientation = Vector3.new(0, 0, 90)
		underGlow.Transparency = 0.78
	end

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

-- Roblox-Avatar-stilisierter Stations-NPC. Klassische R6-Silhouette
-- (Kopf-Block + Torso-Block + 2 Arme + 2 Beine), Gesichtsdetails (Augen +
-- Mund) und ein style-spezifisches Outfit (Lab/Dark/Bot). Die Funktion
-- gibt weiterhin den Torso-BasePart zurueck, damit die bestehende
-- ProximityPrompt-Verkabelung in buildStationKiosk unveraendert bleibt.
local function buildStationNpc(parent, name, pos, accent, npcName, style, faceSign): BasePart
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local face = faceSign or 1

	-- Outfit-Palette je Stil. Bewusst gedaempfte Labor-Toene, damit die NPCs
	-- in die weisse Bio-Tech-Map passen.
	local skin, suit, pants, trim, hair, accessory
	if style == "Bot" then
		skin = Color3.fromRGB(214, 222, 228)
		suit = Color3.fromRGB(228, 232, 236)
		pants = Color3.fromRGB(158, 168, 176)
		trim = LAB_WARNING_YELLOW
		hair = nil
		accessory = "BotPanel"
	elseif style == "Dark" then
		skin = Color3.fromRGB(220, 184, 146)
		suit = Color3.fromRGB(36, 40, 48)
		pants = Color3.fromRGB(22, 24, 30)
		trim = accent
		hair = Color3.fromRGB(28, 24, 26)
		accessory = "Visor"
	else -- "Lab"
		skin = Color3.fromRGB(226, 190, 150)
		suit = Color3.fromRGB(238, 242, 244)
		pants = Color3.fromRGB(192, 198, 202)
		trim = accent
		hair = Color3.fromRGB(78, 50, 36)
		accessory = "Goggles"
	end

	local function p(partName, size, off, color, mat)
		return makePart(model, partName, size, pos + off, color, mat, false)
	end

	-- Beine: links + rechts getrennt (R6-Look) mit Schuhen.
	for _, side in ipairs({ -1, 1 }) do
		local legX = side * 0.75
		p("Leg", Vector3.new(1.25, 3.0, 1.1), Vector3.new(legX, 1.5, 0), pants, Enum.Material.SmoothPlastic)
		p("Shoe", Vector3.new(1.35, 0.55, 1.45), Vector3.new(legX, 0.275, 0.18 * face), Color3.fromRGB(24, 26, 30), Enum.Material.SmoothPlastic)
	end
	-- Becken-Akzent: schmale Trim-Linie zwischen Beinen und Torso.
	p("PelvisBand", Vector3.new(2.7, 0.35, 1.2), Vector3.new(0, 3.18, 0), trim, Enum.Material.SmoothPlastic)

	-- Torso + Brust-Akzentstreifen + Schulteransatz.
	local torso = p("Torso", Vector3.new(3.4, 4.0, 1.5), Vector3.new(0, 5.2, 0), suit, Enum.Material.SmoothPlastic)
	p("CollarLine", Vector3.new(3.4, 0.25, 1.55), Vector3.new(0, 7.0, 0), trim, Enum.Material.SmoothPlastic)
	p("ChestStripe", Vector3.new(0.4, 3.2, 0.05), Vector3.new(0, 5.4, 0.78 * face), trim, Enum.Material.SmoothPlastic)
	p("Belt", Vector3.new(3.45, 0.45, 1.55), Vector3.new(0, 3.45, 0), Color3.fromRGB(24, 26, 30), Enum.Material.SmoothPlastic)
	local beltBuckle = p("BeltBuckle", Vector3.new(0.9, 0.55, 0.06), Vector3.new(0, 3.45, 0.78 * face), trim, Enum.Material.SmoothPlastic)
	beltBuckle.Transparency = 0.1

	-- Arme (Oberarm + Hand). Schulterposition leicht angepasst, damit die
	-- Arme nicht in den Torso clippen.
	for _, side in ipairs({ -1, 1 }) do
		local armX = side * 2.32
		p("Arm", Vector3.new(1.0, 3.6, 1.05), Vector3.new(armX, 5.3, 0), suit, Enum.Material.SmoothPlastic)
		p("Cuff", Vector3.new(1.05, 0.3, 1.1), Vector3.new(armX, 3.6, 0), trim, Enum.Material.SmoothPlastic)
		p("Hand", Vector3.new(1.0, 1.0, 1.05), Vector3.new(armX, 3.0, 0), skin, Enum.Material.SmoothPlastic)
	end

	-- Kopf: klassischer Roblox-Quader, leicht breiter als hoch.
	local head = p("Head", Vector3.new(2.4, 1.9, 1.7), Vector3.new(0, 8.35, 0), skin, Enum.Material.SmoothPlastic)
	-- Hals-Andeutung.
	p("Neck", Vector3.new(1.4, 0.5, 1.15), Vector3.new(0, 7.5, 0), skin, Enum.Material.SmoothPlastic)

	-- Gesicht: Augen + Mund auf der Vorderseite (face-richtung).
	local eyeZ = 0.86 * face
	for _, side in ipairs({ -0.45, 0.45 }) do
		local eyeWhite = p("EyeWhite", Vector3.new(0.4, 0.36, 0.05), Vector3.new(side, 8.5, eyeZ), Color3.fromRGB(248, 248, 248), Enum.Material.SmoothPlastic)
		p("EyePupil", Vector3.new(0.18, 0.2, 0.06), Vector3.new(side, 8.48, eyeZ + 0.01 * face), Color3.fromRGB(18, 22, 30), Enum.Material.SmoothPlastic)
	end
	p("Mouth", Vector3.new(0.9, 0.12, 0.04), Vector3.new(0, 7.92, eyeZ), Color3.fromRGB(60, 40, 36), Enum.Material.SmoothPlastic)

	-- Accessoire je Stil.
	if accessory == "Goggles" then
		-- Cyan-/Gruene Forscherbrille.
		p("GogglesBand", Vector3.new(2.45, 0.18, 0.06), Vector3.new(0, 8.9, eyeZ), Color3.fromRGB(28, 30, 36), Enum.Material.SmoothPlastic)
		for _, side in ipairs({ -0.45, 0.45 }) do
			local lens = p("GoggleLens", Vector3.new(0.55, 0.5, 0.06), Vector3.new(side, 8.84, eyeZ + 0.02 * face), trim, Enum.Material.Neon)
			lens.Transparency = 0.2
		end
	elseif accessory == "Visor" then
		-- Dunkles Sci-Fi-Visor.
		local visor = p("Visor", Vector3.new(2.45, 0.55, 0.08), Vector3.new(0, 8.65, eyeZ), Color3.fromRGB(18, 20, 24), Enum.Material.SmoothPlastic)
		local glow = p("VisorGlow", Vector3.new(2.1, 0.18, 0.05), Vector3.new(0, 8.7, eyeZ + 0.02 * face), trim, Enum.Material.Neon)
		glow.Transparency = 0.18
	elseif accessory == "BotPanel" then
		-- Roboter-Gesichtsplatte mit Display.
		local panel = p("BotFacePanel", Vector3.new(2.0, 1.1, 0.08), Vector3.new(0, 8.42, eyeZ), Color3.fromRGB(28, 32, 38), Enum.Material.SmoothPlastic)
		for _, side in ipairs({ -0.4, 0.4 }) do
			local eyeLed = p("BotEyeLed", Vector3.new(0.42, 0.42, 0.04), Vector3.new(side, 8.55, eyeZ + 0.02 * face), trim, Enum.Material.Neon)
			eyeLed.Transparency = 0.05
		end
		p("BotChinLine", Vector3.new(1.1, 0.12, 0.04), Vector3.new(0, 8.05, eyeZ + 0.02 * face), trim, Enum.Material.Neon).Transparency = 0.3
	end

	-- Haare/Hut.
	if hair then
		p("HairCap", Vector3.new(2.45, 0.65, 1.75), Vector3.new(0, 9.45, -0.05 * face), hair, Enum.Material.SmoothPlastic)
		p("HairFront", Vector3.new(2.1, 0.45, 0.35), Vector3.new(0, 9.25, 0.7 * face), hair, Enum.Material.SmoothPlastic)
	elseif style == "Bot" then
		-- Bot-Antenne anstelle von Haaren.
		p("BotAntennaRod", Vector3.new(0.18, 0.9, 0.18), Vector3.new(0, 9.7, -0.1 * face), Color3.fromRGB(40, 44, 50), Enum.Material.Metal)
		local antennaTip = p("BotAntennaTip", Vector3.new(0.45, 0.45, 0.45), Vector3.new(0, 10.25, -0.1 * face), trim, Enum.Material.Neon)
		antennaTip.Shape = Enum.PartType.Ball
		antennaTip.Transparency = 0.1
	end

	-- Brust-Badge + Tablet vor dem Bauch (gleicher Look wie vorher,
	-- nur sauberer positioniert mit dem face-Vorzeichen).
	local badge = p("Badge", Vector3.new(0.85, 0.85, 0.1), Vector3.new(0.95, 5.95, 0.78 * face), accent, Enum.Material.SmoothPlastic)
	badge.Transparency = 0.08
	p("BadgeDot", Vector3.new(0.32, 0.32, 0.06), Vector3.new(0.95, 5.95, 0.81 * face), accent:Lerp(LAB_WHITE, 0.6), Enum.Material.Neon)
	local tablet = p("Tablet", Vector3.new(2.6, 1.5, 0.22), Vector3.new(0, 4.55, 1.0 * face), Color3.fromRGB(22, 24, 28), Enum.Material.Metal)
	local tabletScreen = p("TabletScreen", Vector3.new(2.2, 1.2, 0.06), Vector3.new(0, 4.55, 1.12 * face), trim, Enum.Material.Neon)
	tabletScreen.Transparency = 0.32

	-- Nicht-kollidierend / nicht-anklickbar: ProximityPrompt am Torso bleibt
	-- der einzige Interaktionspunkt. Anchored bleibt true (kommt von makePart).
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
		end
	end

	-- Name-Tag etwas hoeher, damit es nicht mit dem Roblox-Spieler-Display
	-- kollidiert (~3 Studs ueber dem Kopf).
	label(head, npcName, accent:Lerp(Color3.fromRGB(238, 246, 240), 0.4), 48, UDim2.fromOffset(190, 36), Vector3.new(0, 2.6, 0))
	return torso
end

-- Stations-spezifische Hero-Deko (Geschenk fuer Daily, DNA-Helix fuer
-- Upgrade etc.). Bekommt das Stations-Center + accent + face. Bewusst klein
-- gehalten, damit es den Kiosk nur akzentuiert -- nicht ueberladet.
local function buildStationSignature(parent, kind: string, pos: Vector3, accent: Color3, face: number)
	local function p(partName, size, off, color, mat)
		return makePart(parent, partName, size, pos + off, color, mat, false)
	end

	if kind == "Shop" then
		-- Boost-Kapsel mit DNA-/Geld-Icon im Kontrolldisplay.
		local cap = p("ShopBoostCapsule", Vector3.new(1.4, 2.4, 1.4), Vector3.new(4.9, 3.3, 2.4 * face), tint(accent, LAB_WHITE, 0.5), Enum.Material.Glass)
		cap.Shape = Enum.PartType.Cylinder
		cap.Orientation = Vector3.new(0, 0, 90)
		cap.Transparency = 0.45
		local pill = p("ShopBoostPill", Vector3.new(0.8, 1.4, 0.8), Vector3.new(4.9, 3.3, 2.4 * face), accent, Enum.Material.Neon)
		pill.Shape = Enum.PartType.Cylinder
		pill.Orientation = Vector3.new(0, 0, 90)
		pill.Transparency = 0.1
		local priceTag = p("ShopPriceTag", Vector3.new(2.4, 1.2, 0.18), Vector3.new(4.9, 5.0, 3.45 * face), Color3.fromRGB(20, 22, 26), Enum.Material.Metal)
		label(priceTag, "+ BOOST", accent:Lerp(LAB_WHITE, 0.5), 26, UDim2.fromOffset(120, 32), Vector3.new(0, 0, 0))
	elseif kind == "Daily" then
		-- Geschenk-Wuerfel + Reward-Roehrchen.
		local box = p("DailyGiftBox", Vector3.new(2.2, 2.2, 2.2), Vector3.new(4.9, 3.3, 2.4 * face), Color3.fromRGB(38, 42, 48), Enum.Material.Metal)
		p("DailyGiftLid", Vector3.new(2.35, 0.35, 2.35), Vector3.new(4.9, 4.55, 2.4 * face), accent, Enum.Material.SmoothPlastic)
		p("DailyGiftRibbonV", Vector3.new(0.45, 2.4, 2.3), Vector3.new(4.9, 3.3, 2.4 * face), accent, Enum.Material.SmoothPlastic)
		p("DailyGiftRibbonH", Vector3.new(2.3, 0.45, 2.3), Vector3.new(4.9, 3.3, 2.4 * face), accent, Enum.Material.SmoothPlastic)
		local bow = p("DailyGiftBow", Vector3.new(0.85, 0.7, 0.85), Vector3.new(4.9, 4.95, 2.4 * face), accent, Enum.Material.SmoothPlastic)
		bow.Shape = Enum.PartType.Ball
		-- Reward-Roehrchen daneben.
		for i, dx in ipairs({ 3.1, 3.95, 4.8 }) do
			local tube = p("DailyRewardVial" .. i, Vector3.new(0.55, 1.6, 0.55), Vector3.new(-dx, 2.8, 3.0 * face), tint(accent, LAB_WHITE, 0.4), Enum.Material.Glass)
			tube.Shape = Enum.PartType.Cylinder
			tube.Orientation = Vector3.new(0, 0, 90)
			tube.Transparency = 0.4
			local sample = p("DailyRewardSample" .. i, Vector3.new(0.32, 1.1, 0.32), Vector3.new(-dx, 2.8, 3.0 * face), accent, Enum.Material.Neon)
			sample.Shape = Enum.PartType.Cylinder
			sample.Orientation = Vector3.new(0, 0, 90)
			sample.Transparency = 0.18
		end
	elseif kind == "Skills" then
		-- DNA-Helix-Hologramm + Skill-Chips.
		local glass = p("UpgradeDnaGlass", Vector3.new(1.6, 5.8, 1.6), Vector3.new(4.9, 4.4, 2.4 * face), tint(accent, LAB_WHITE, 0.5), Enum.Material.Glass)
		glass.Shape = Enum.PartType.Cylinder
		glass.Orientation = Vector3.new(0, 0, 90)
		glass.Transparency = 0.55
		for i = 0, 7 do
			local t = i / 7
			local ang = t * math.pi * 2.6
			local node = p("UpgradeDnaNode" .. i, Vector3.new(0.45, 0.45, 0.45), Vector3.new(4.9 + math.cos(ang) * 0.55, 2.0 + t * 4.8, 2.4 * face + math.sin(ang) * 0.35), accent, Enum.Material.Neon)
			node.Shape = Enum.PartType.Ball
			node.Transparency = 0.15
			local mirror = p("UpgradeDnaNodeM" .. i, Vector3.new(0.4, 0.4, 0.4), Vector3.new(4.9 - math.cos(ang) * 0.55, 2.0 + t * 4.8, 2.4 * face - math.sin(ang) * 0.35), tint(accent, LAB_OLIVE, 0.4), Enum.Material.Neon)
			mirror.Shape = Enum.PartType.Ball
			mirror.Transparency = 0.25
		end
		-- 2 Skill-Chips am Pult.
		for i, dx in ipairs({ -3.7, -4.5 }) do
			local chip = p("UpgradeSkillChip" .. i, Vector3.new(1.2, 0.2, 0.85), Vector3.new(dx, 2.55, 3.0 * face), Color3.fromRGB(28, 30, 36), Enum.Material.Metal)
			p("UpgradeSkillChipLed" .. i, Vector3.new(0.85, 0.06, 0.55), Vector3.new(dx, 2.66, 3.0 * face), accent, Enum.Material.Neon).Transparency = 0.2
		end
	elseif kind == "Auras" then
		-- Aura-Kapseln in lila/cyan-Mix mit dezenten Energiekugeln.
		local cyan = LAB_CYAN
		for i, dx in ipairs({ 3.6, 4.6, 5.6 }) do
			local tubeColor = if i % 2 == 1 then accent else cyan
			local tube = p("AuraTube" .. i, Vector3.new(1.0, 3.0, 1.0), Vector3.new(dx, 3.0, 2.6 * face), tint(tubeColor, LAB_WHITE, 0.5), Enum.Material.Glass)
			tube.Shape = Enum.PartType.Cylinder
			tube.Orientation = Vector3.new(0, 0, 90)
			tube.Transparency = 0.45
			local orb = p("AuraOrb" .. i, Vector3.new(0.55, 0.55, 0.55), Vector3.new(dx, 3.0 + ((i - 2) * 0.3), 2.6 * face), tubeColor, Enum.Material.Neon)
			orb.Shape = Enum.PartType.Ball
			orb.Transparency = 0.1
		end
		-- Schwebende Probe ueber dem Pult.
		local floatGlass = p("AuraFloatGlass", Vector3.new(2.2, 2.2, 2.2), Vector3.new(-4.5, 4.0, 2.6 * face), tint(accent, LAB_WHITE, 0.55), Enum.Material.Glass)
		floatGlass.Shape = Enum.PartType.Ball
		floatGlass.Transparency = 0.5
		local floatCore = p("AuraFloatCore", Vector3.new(1.1, 1.1, 1.1), Vector3.new(-4.5, 4.0, 2.6 * face), accent, Enum.Material.Neon)
		floatCore.Shape = Enum.PartType.Ball
		floatCore.Transparency = 0.12
		local stand = p("AuraFloatStand", Vector3.new(0.5, 3.0, 0.5), Vector3.new(-4.5, 1.7, 2.6 * face), LAB_DARK, Enum.Material.Metal)
	end
end

-- Marker-String fuer das Bodenlabel je Menue.
local FLOOR_LABEL_BY_MENU = {
	Shop = "SHOP",
	Daily = "DAILY",
	Skills = "UPGRADE",
	Auras = "AURA",
}

-- Interaktiver Labor-Kiosk: Prompt oeffnet vorhandene UI-Menues clientseitig.
-- Geometrie (Pillar/Screen/Marquee/NPC-Position) bleibt unveraendert, damit
-- bestehende Stations-Layouts und ProximityPrompt-Funktion erhalten bleiben.
local function buildStationKiosk(parent, name, pos, accent, title, hint, menuTarget, actionText, npcName, npcStyle, faceSign, auraTier: number?)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local face = faceSign or 1
	if menuTarget == "Auras" and auraTier then
		model:SetAttribute("AuraTier", auraTier)
	end

	-- Boden-Akzent unter und vor dem Kiosk: flacher Bodenbelag (Mat), kein
	-- erhoehtes Podest -> NPC-Schuhe stehen sauber darueber, kein Clipping
	-- mit FLOOR_Y. Boden bleibt Spieler-passierbar (non-collide).
	local platform = makePart(model, "StationPlatform", Vector3.new(13, 0.08, 15), pos + Vector3.new(0, FLOOR_Y + 0.06, 2.5 * face), Color3.fromRGB(228, 232, 234), Enum.Material.SmoothPlastic, false)
	platform.Transparency = 0.04
	-- Boden-Glow in der Stations-Akzentfarbe: leuchtet sichtbar und wirft
	-- ueber SurfaceLight farbiges Licht nach oben auf NPC und Kiosk.
	local platformEdge = makePart(model, "StationPlatformEdge", Vector3.new(13.5, 0.05, 15.5), pos + Vector3.new(0, FLOOR_Y + 0.12, 2.5 * face), accent, Enum.Material.Neon, false)
	platformEdge.Transparency = 0.32
	local glowLight = Instance.new("SurfaceLight")
	glowLight.Face = Enum.NormalId.Top
	glowLight.Brightness = 2.4
	glowLight.Range = 18
	glowLight.Angle = 170
	glowLight.Color = accent
	glowLight.Shadows = false
	glowLight.Parent = platformEdge
	neonStrip(model, Vector3.new(11.6, 0.05, 0.32), pos + Vector3.new(0, FLOOR_Y + 0.16, 9.5 * face), accent, 0.35)
	neonStrip(model, Vector3.new(11.6, 0.05, 0.32), pos + Vector3.new(0, FLOOR_Y + 0.16, -4.0 * face), accent:Lerp(LAB_CYAN, 0.5), 0.55)
	-- Boden-Label direkt vor dem Stand (z.B. "SHOP", "DAILY" ...). Inline
	-- mit SurfaceGui, weil buildFloorLabel weiter unten im File definiert ist.
	local floorTag = FLOOR_LABEL_BY_MENU[menuTarget] or title
	local floorPlate = makePart(model, "StationFloorLabelPlate", Vector3.new(6, 0.04, 1.6), pos + Vector3.new(0, FLOOR_Y + 1.02, 5.5 * face), Color3.fromRGB(32, 36, 38), Enum.Material.SmoothPlastic, false)
	floorPlate.Transparency = 0.12
	do
		local sg = Instance.new("SurfaceGui")
		sg.Name = "StationFloorLabelSurface"
		sg.Face = Enum.NormalId.Top
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 50
		sg.LightInfluence = 1
		sg.AlwaysOnTop = false
		sg.Adornee = floorPlate
		sg.Parent = floorPlate
		local tl = Instance.new("TextLabel")
		tl.BackgroundTransparency = 1
		tl.Size = UDim2.fromScale(0.94, 0.78)
		tl.Position = UDim2.fromScale(0.03, 0.11)
		tl.Text = floorTag
		tl.Font = Enum.Font.GothamBold
		tl.TextScaled = true
		tl.TextColor3 = accent:Lerp(Color3.fromRGB(238, 244, 240), 0.4)
		tl.TextStrokeColor3 = Color3.new(0, 0, 0)
		tl.TextStrokeTransparency = 0.35
		tl.Parent = sg
	end

	-- Kiosk-Korpus (unveraendert, damit Position stabil bleibt).
	local pillar = makePart(model, "KioskBody", Vector3.new(8, 9, 6), pos + Vector3.new(0, 4.2, 0), Color3.fromRGB(212, 217, 216), Enum.Material.SmoothPlastic, true)
	makePart(model, "KioskBase", Vector3.new(9.5, 0.8, 7.5), pos + Vector3.new(0, 0.1, 0), LAB_DARK, Enum.Material.Metal, true)
	makePart(model, "KioskDarkTop", Vector3.new(8.4, 1.1, 6.4), pos + Vector3.new(0, 9.2, 0), LAB_DARK, Enum.Material.SmoothPlastic, false)
	-- Schmale Vertikalrillen am Korpus -> weniger flach, premium.
	for _, dx in ipairs({ -2.6, 0, 2.6 }) do
		makePart(model, "KioskGroove", Vector3.new(0.18, 7.6, 0.05), pos + Vector3.new(dx, 4.5, 3.04 * face), Color3.fromRGB(82, 90, 96), Enum.Material.SmoothPlastic, false)
	end
	for _, side in ipairs({ -1, 1 }) do
		makePart(model, "KioskSideStripe", Vector3.new(0.08, 7.6, 5.5), pos + Vector3.new(side * 4.02, 4.5, 0), accent:Lerp(LAB_DARK, 0.35), Enum.Material.SmoothPlastic, false).Transparency = 0.18
	end
	neonStrip(model, Vector3.new(7, 0.3, 0.3), pos + Vector3.new(0, 8.4, 3.05 * face), accent, 0.18)

	-- Hauptschirm.
	local screen = makePart(model, "KioskScreen", Vector3.new(5.6, 4.4, 0.25), pos + Vector3.new(0, 5.4, 3.05 * face), tint(accent, Color3.fromRGB(54, 70, 70), 0.4), Enum.Material.Neon, false)
	screen.Transparency = 0.12
	makePart(model, "KioskScreenBezel", Vector3.new(6.2, 5.0, 0.18), pos + Vector3.new(0, 5.4, 3.0 * face), Color3.fromRGB(18, 20, 24), Enum.Material.Metal, false)
	label(screen, title, Color3.fromRGB(236, 248, 242), 60, UDim2.fromOffset(220, 56), Vector3.new(0, 0, 0))
	-- Hinweis-Untertitel direkt unter dem Schirm.
	local subPanel = makePart(model, "KioskSubPanel", Vector3.new(5.6, 1.05, 0.22), pos + Vector3.new(0, 2.85, 3.05 * face), Color3.fromRGB(20, 22, 26), Enum.Material.Metal, false)
	label(subPanel, hint, accent:Lerp(Color3.fromRGB(232, 244, 238), 0.6), 28, UDim2.fromOffset(220, 34), Vector3.new(0, 0, 0))

	-- Marquee/Schild + kleiner Stations-Icon-Dot.
	local marqueePost = makePart(model, "StationMarqueePost", Vector3.new(0.75, 8, 0.75), pos + Vector3.new(-5.5, 4, 0), LAB_TRIM, Enum.Material.Metal, true)
	marqueePost.Transparency = 0
	makePart(model, "StationMarqueePost2", Vector3.new(0.75, 8, 0.75), pos + Vector3.new(5.5, 4, 0), LAB_TRIM, Enum.Material.Metal, true)
	local marquee = makePart(model, "StationMarquee", Vector3.new(13, 3.6, 0.5), pos + Vector3.new(0, 12.2, 0), LAB_DARK, Enum.Material.SmoothPlastic, false)
	makePart(model, "StationMarqueeFrame", Vector3.new(13.6, 4, 0.25), pos + Vector3.new(0, 12.2, -0.13), Color3.fromRGB(20, 22, 26), Enum.Material.Metal, false)
	neonStrip(model, Vector3.new(11.4, 0.24, 0.24), marquee.Position + Vector3.new(0, -1.55, -0.3), accent, 0.26)
	neonStrip(model, Vector3.new(11.4, 0.18, 0.18), marquee.Position + Vector3.new(0, 1.55, -0.3), accent:Lerp(LAB_CYAN, 0.4), 0.4)
	local marqueeDot = makePart(model, "StationMarqueeDot", Vector3.new(0.55, 0.55, 0.18), marquee.Position + Vector3.new(-5.4, 0, 0.28), accent, Enum.Material.Neon, false)
	marqueeDot.Shape = Enum.PartType.Ball
	marqueeDot.Transparency = 0.1
	label(marquee, title, Color3.fromRGB(245, 250, 248), 80, UDim2.fromOffset(220, 50), Vector3.new(0, 0, 0))

	-- NPC (Position UNVERAENDERT). Prompt bleibt am Torso.
	local npcPromptPart = buildStationNpc(model, "NPC_" .. npcName:gsub("%s+", ""), pos + Vector3.new(0, 0, 7.1 * face), accent, npcName, npcStyle, face)
	npcPromptPart:SetAttribute("MenuTarget", menuTarget)
	if menuTarget == "Auras" and auraTier then
		npcPromptPart:SetAttribute("AuraTier", auraTier)
	end
	makePrompt(npcPromptPart, menuTarget, actionText, npcName)
	local prompt = npcPromptPart:FindFirstChild("OpenMenuPrompt")
	if prompt and prompt:IsA("ProximityPrompt") and menuTarget == "Auras" and auraTier then
		prompt:SetAttribute("AuraTier", auraTier)
	end

	local trigger = makePart(model, "StationProximityTrigger", Vector3.new(12, 8, 12), pos + Vector3.new(0, FLOOR_Y + 4, 5.0 * face), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, false)
	trigger.Transparency = 1
	trigger.CanCollide = false
	trigger.CanTouch = false
	trigger.CanQuery = false
	trigger:SetAttribute("MenuTarget", menuTarget)
	if menuTarget == "Auras" and auraTier then
		trigger:SetAttribute("AuraTier", auraTier)
	end

	-- Sample-Tank seitlich (urspruengliches Element, sauberer gerahmt).
	local sampleA = makePart(model, "SampleCapsuleA", Vector3.new(1.4, 3.2, 1.4), pos + Vector3.new(-4.7, 2.4, 2.6 * face), Color3.fromRGB(180, 220, 210), Enum.Material.Glass, false)
	sampleA.Shape = Enum.PartType.Cylinder
	sampleA.Transparency = 0.42
	makePart(model, "SampleCapsuleACap", Vector3.new(1.5, 0.35, 1.5), pos + Vector3.new(-4.7, 4.05, 2.6 * face), LAB_TRIM, Enum.Material.Metal, false).Shape = Enum.PartType.Cylinder
	makePart(model, "SampleCapsuleABase", Vector3.new(1.5, 0.35, 1.5), pos + Vector3.new(-4.7, 0.75, 2.6 * face), LAB_DARK, Enum.Material.Metal, false).Shape = Enum.PartType.Cylinder
	makePart(model, "SampleGlowA", Vector3.new(0.8, 2.1, 0.8), sampleA.Position, accent:Lerp(LAB_GREEN, 0.35), Enum.Material.SmoothPlastic, false).Shape = Enum.PartType.Ball

	-- Zweiter Sample-Tank auf der anderen Seite -> wirkt nicht mehr leer.
	local sampleB = makePart(model, "SampleCapsuleB", Vector3.new(1.1, 2.6, 1.1), pos + Vector3.new(-3.4, 2.1, 2.6 * face), Color3.fromRGB(192, 224, 218), Enum.Material.Glass, false)
	sampleB.Shape = Enum.PartType.Cylinder
	sampleB.Transparency = 0.5
	makePart(model, "SampleGlowB", Vector3.new(0.55, 1.7, 0.55), sampleB.Position, tint(accent, LAB_CYAN, 0.4), Enum.Material.SmoothPlastic, false).Shape = Enum.PartType.Cylinder

	-- Service-Konsole rechts.
	local console = makePart(model, "ServiceConsole", Vector3.new(3.4, 2.1, 2.4), pos + Vector3.new(4.9, 1.55, 2.4 * face), LAB_DARK, Enum.Material.Metal, true)
	local consoleTop = makePart(model, "ServiceConsoleTop", Vector3.new(3.6, 0.18, 2.6), pos + Vector3.new(4.9, 2.7, 2.4 * face), accent:Lerp(LAB_DARK, 0.35), Enum.Material.Metal, false)
	consoleTop.Transparency = 0.15
	neonStrip(model, Vector3.new(2.3, 0.18, 0.18), console.Position + Vector3.new(0, 0.8, -1.25 * face), accent, 0.25)

	-- Stations-spezifische Hero-Deko (Boost-Kapsel/Geschenk/DNA/Aura ...).
	buildStationSignature(model, menuTarget, pos, accent, face)
	return model
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

local function buildLeaderboardBoard(parent: Instance, boardKey: string, title: string, pos: Vector3, accent: Color3, face: Enum.NormalId?)
	local model = Instance.new("Model")
	model.Name = "Top" .. boardKey .. "Board"
	model.Parent = parent

	-- Trim/Rail-Offsets liegen auf der "Rueckseite" der GUI -- bei Face=Left
	-- spiegeln wir das, sonst stecken sie in der Wand.
	local guiFace = face or Enum.NormalId.Right
	local backOffset = if guiFace == Enum.NormalId.Left then -0.06 else 0.06

	local frame = makePart(model, "BoardFrame", Vector3.new(0.85, 14.3, 20), pos, LAB_DARK, Enum.Material.Metal, false)
	frame:SetAttribute("BoardKey", boardKey)
	makePart(model, "BoardGlowRailTop", Vector3.new(1, 0.3, 18), pos + Vector3.new(backOffset, 6.68, 0), accent, Enum.Material.SmoothPlastic, false).Transparency = 0.2
	makePart(model, "BoardGlowRailBottom", Vector3.new(1, 0.22, 18), pos + Vector3.new(backOffset, -6.68, 0), accent:Lerp(LAB_GREEN, 0.35), Enum.Material.SmoothPlastic, false).Transparency = 0.4
	makePart(model, "BoardLeftTrim", Vector3.new(1, 13.7, 0.36), pos + Vector3.new(backOffset, 0, -9.8), LAB_TRIM, Enum.Material.Metal, false)
	makePart(model, "BoardRightTrim", Vector3.new(1, 13.7, 0.36), pos + Vector3.new(backOffset, 0, 9.8), LAB_TRIM, Enum.Material.Metal, false)

	local gui = makeSurfaceGui(frame, "BoardGui", Vector2.new(520, 420), guiFace)
	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(8, 13, 20)
	bg.BackgroundTransparency = 0.08
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Position = UDim2.new(0, 14, 0, 12)
	header.Size = UDim2.new(1, -28, 0, 48)
	header.BackgroundColor3 = Color3.fromRGB(15, 25, 32)
	header.BorderSizePixel = 0
	header.Parent = bg
	local headerStroke = Instance.new("UIStroke")
	headerStroke.Color = accent
	headerStroke.Thickness = 2
	headerStroke.Transparency = 0.25
	headerStroke.Parent = header
	surfaceText(header, "BoardTitle", title, UDim2.new(0, 12, 0, 0), UDim2.new(1, -24, 1, 0), Color3.fromRGB(238, 248, 246), 28, true)

	for i = 1, 5 do
		local row = Instance.new("Frame")
		row.Name = "Row" .. tostring(i)
		row.Position = UDim2.new(0, 14, 0, 76 + (i - 1) * 52)
		row.Size = UDim2.new(1, -28, 0, 44)
		row.BackgroundColor3 = if i == 1 then accent:Lerp(Color3.fromRGB(14, 20, 28), 0.7) elseif i <= 3 then Color3.fromRGB(20, 30, 40) else Color3.fromRGB(12, 18, 26)
		row.BackgroundTransparency = if i == 1 then 0.02 elseif i <= 3 then 0.08 else 0.16
		row.BorderSizePixel = 0
		row.Parent = bg
		local rowStroke = Instance.new("UIStroke")
		rowStroke.Color = if i == 1 then accent elseif i <= 3 then accent:Lerp(Color3.fromRGB(90, 96, 104), 0.4) else Color3.fromRGB(56, 70, 80)
		rowStroke.Thickness = if i == 1 then 2 else 1
		rowStroke.Transparency = if i == 1 then 0.08 else 0.45
		rowStroke.Parent = row

		local avatar = Instance.new("ImageLabel")
		avatar.Name = "Avatar" .. tostring(i)
		avatar.Position = UDim2.new(0, 52, 0, 8)
		avatar.Size = UDim2.new(0, 28, 0, 28)
		avatar.BackgroundColor3 = Color3.fromRGB(18, 24, 32)
		avatar.BorderSizePixel = 0
		avatar.ImageTransparency = 1
		avatar.Parent = row
		surfaceText(row, "Rank" .. tostring(i), "#" .. tostring(i), UDim2.new(0, 8, 0, 0), UDim2.new(0, 40, 1, 0), if i == 1 then Color3.fromRGB(255, 228, 112) else accent, 18, true)
		surfaceText(row, "Name" .. tostring(i), "No record yet", UDim2.new(0, 90, 0, 0), UDim2.new(0.56, -90, 1, 0), Color3.fromRGB(236, 242, 248), 17, true)
		local value = surfaceText(row, "Value" .. tostring(i), "-", UDim2.new(0.58, 0, 0, 0), UDim2.new(0.42, -10, 1, 0), Color3.fromRGB(180, 255, 196), 15, true)
		value.TextXAlignment = Enum.TextXAlignment.Right
	end

	local footer = surfaceText(bg, "UpdatedLabel", "Updates every 60 seconds", UDim2.new(0, 14, 1, -36), UDim2.new(1, -28, 0, 24), Color3.fromRGB(162, 184, 190), 14, false)
	footer.TextXAlignment = Enum.TextXAlignment.Center
end

local function buildLeaderboardZone(parent: Instance, cx: number)
	local zone = makeFolder("LeaderboardZone", parent)
	clearChildren(zone)
	local wallX = cx - 146
	local baseZ = 20
	local accentPower = Color3.fromRGB(72, 235, 132)
	local accentCyan = Color3.fromRGB(88, 220, 235)
	local accentGold = Color3.fromRGB(225, 190, 82)
	local accentRed = Color3.fromRGB(184, 72, 72)

	makePart(zone, "LeaderboardWallBacking", Vector3.new(1.4, 24, 102), Vector3.new(wallX - 0.4, FLOOR_Y + 12, baseZ), Color3.fromRGB(12, 16, 22), Enum.Material.Metal, false)
	makePart(zone, "LeaderboardWallTopFrame", Vector3.new(2, 1.2, 106), Vector3.new(wallX + 0.1, FLOOR_Y + 23.4, baseZ), LAB_TRIM, Enum.Material.Metal, false)
	makePart(zone, "LeaderboardWallBottomFrame", Vector3.new(2, 0.8, 106), Vector3.new(wallX + 0.1, FLOOR_Y + 1.2, baseZ), LAB_TRIM, Enum.Material.Metal, false)

	local boardY = FLOOR_Y + 11.2
	buildLeaderboardBoard(zone, "Power", "TOP POWER", Vector3.new(wallX + 1, boardY, baseZ - 38), accentPower)
	buildLeaderboardBoard(zone, "Mutations", "TOP MUTATIONS", Vector3.new(wallX + 1, boardY, baseZ - 13), accentCyan)
	buildLeaderboardBoard(zone, "Dna", "TOP DNA", Vector3.new(wallX + 1, boardY, baseZ + 13), accentGold)
	buildLeaderboardBoard(zone, "BossKills", "TOP BOSS KILLS", Vector3.new(wallX + 1, boardY, baseZ + 38), accentRed)

	local podiumFolder = makeFolder("TopPlayerPodiums", zone)
	local podiumTarget = Vector3.new(cx, FLOOR_Y, FLOOR_CENTER_Z)
	local function faceSpawn(part: BasePart)
		local target = Vector3.new(podiumTarget.X, part.Position.Y, podiumTarget.Z)
		part.CFrame = CFrame.lookAt(part.Position, target)
		part:SetAttribute("FaceTargetX", podiumTarget.X)
		part:SetAttribute("FaceTargetZ", podiumTarget.Z)
	end

	local podiums = {
		{ rank = 2, pos = Vector3.new(wallX + 16, FLOOR_Y + 0.65, baseZ + 84), size = Vector3.new(10, 1.3, 10), accent = accentCyan },
		{ rank = 1, pos = Vector3.new(wallX + 34, FLOOR_Y + 1, baseZ + 84), size = Vector3.new(13, 2, 13), accent = accentPower },
		{ rank = 3, pos = Vector3.new(wallX + 52, FLOOR_Y + 0.55, baseZ + 84), size = Vector3.new(10, 1.1, 10), accent = accentGold },
	}
	for _, p in ipairs(podiums) do
		local pod = makePart(podiumFolder, "Top" .. tostring(p.rank) .. "Podium", p.size, p.pos, Color3.fromRGB(25, 30, 36), Enum.Material.Metal, true)
		faceSpawn(pod)
		pod:SetAttribute("PodiumRank", p.rank)
		local frontStrip = neonStrip(podiumFolder, Vector3.new(p.size.X + 2, 0.08, 0.5), pod.Position, p.accent, 0.42)
		frontStrip.CFrame = pod.CFrame * CFrame.new(0, p.size.Y / 2 + 0.12, -p.size.Z / 2 - 0.2)
		local backStrip = neonStrip(podiumFolder, Vector3.new(p.size.X + 2, 0.08, 0.5), pod.Position, p.accent, 0.42)
		backStrip.CFrame = pod.CFrame * CFrame.new(0, p.size.Y / 2 + 0.12, p.size.Z / 2 + 0.2)
	end

	local floorMark = makePart(zone, "RankingZoneFloorMark", Vector3.new(58, 0.08, 22), Vector3.new(wallX + 34, FLOOR_Y + 1.2, baseZ + 84), Color3.fromRGB(28, 36, 42), Enum.Material.SmoothPlastic, false)
	faceSpawn(floorMark)
	floorMark.Transparency = 0.48

	makeFolder("AvatarDummies", zone)
	makeFolder("Decor", zone)
end

-- ---- End-of-Map Leaderboard ---------------------------------------------
-- Spiegel der Spawn-Ranked-Tabelle auf der FinalWall (hinter Area 10's Boss).
-- Parameter wallFaceX = X-Koordinate der -X-Seite der FinalWall, also der
-- Flaeche, vor der die Boards montiert werden. Boards bekommen Face=Left,
-- damit sie zum Spieler (aus -X kommend) zeigen.
local function buildEndLeaderboardZone(parent: Instance, wallFaceX: number)
	local zone = makeFolder("EndLeaderboardZone", parent)
	clearChildren(zone)

	-- Spawn-Spiegel: Backing leicht IN die Wand versenkt (sichtbar als duenne
	-- Frontplatte vor der FinalWall), Boards 1 Stud davor in der Luft.
	-- Player kommt aus -X -> Boards sind das vorderste Element.
	local boardX = wallFaceX - 1
	local backingX = wallFaceX + 0.4
	local centerZ = FLOOR_CENTER_Z
	local accentPower = Color3.fromRGB(72, 235, 132)
	local accentCyan = Color3.fromRGB(88, 220, 235)
	local accentGold = Color3.fromRGB(225, 190, 82)
	local accentRed = Color3.fromRGB(184, 72, 72)

	makePart(zone, "EndLeaderboardWallBacking", Vector3.new(1.4, 24, 110), Vector3.new(backingX, FLOOR_Y + 12, centerZ), Color3.fromRGB(12, 16, 22), Enum.Material.Metal, false)
	makePart(zone, "EndLeaderboardWallTopFrame", Vector3.new(2, 1.2, 114), Vector3.new(wallFaceX - 0.1, FLOOR_Y + 23.4, centerZ), LAB_TRIM, Enum.Material.Metal, false)
	makePart(zone, "EndLeaderboardWallBottomFrame", Vector3.new(2, 0.8, 114), Vector3.new(wallFaceX - 0.1, FLOOR_Y + 1.2, centerZ), LAB_TRIM, Enum.Material.Metal, false)

	local boardY = FLOOR_Y + 11.2
	buildLeaderboardBoard(zone, "Power", "TOP POWER", Vector3.new(boardX, boardY, centerZ - 38), accentPower, Enum.NormalId.Left)
	buildLeaderboardBoard(zone, "Mutations", "TOP MUTATIONS", Vector3.new(boardX, boardY, centerZ - 13), accentCyan, Enum.NormalId.Left)
	buildLeaderboardBoard(zone, "Dna", "TOP DNA", Vector3.new(boardX, boardY, centerZ + 13), accentGold, Enum.NormalId.Left)
	buildLeaderboardBoard(zone, "BossKills", "TOP BOSS KILLS", Vector3.new(boardX, boardY, centerZ + 38), accentRed, Enum.NormalId.Left)

	-- "CONGRATULATIONS"-Schild oben mittig (ueber den Boards). Sitzt VOR der
	-- FinalWall, gleiche Flucht wie das Backing.
	local signHeight = 6
	local signY = FLOOR_Y + 18 + signHeight / 2 + 4
	local signPart = makePart(zone, "EndCongratulationsSign", Vector3.new(0.6, signHeight, 96), Vector3.new(wallFaceX - 0.3, signY, centerZ), Color3.fromRGB(14, 18, 24), Enum.Material.Metal, false)
	local accentMix = Color3.fromRGB(255, 215, 90)
	makePart(zone, "EndCongratulationsFrameTop", Vector3.new(1.1, 0.7, 100), Vector3.new(wallFaceX - 0.55, signY + signHeight / 2, centerZ), accentMix, Enum.Material.Neon, false).Transparency = 0.18
	makePart(zone, "EndCongratulationsFrameBottom", Vector3.new(1.1, 0.5, 100), Vector3.new(wallFaceX - 0.55, signY - signHeight / 2, centerZ), accentMix, Enum.Material.SmoothPlastic, false).Transparency = 0.3

	local signGui = makeSurfaceGui(signPart, "EndCongratulationsGui", Vector2.new(1600, 100), Enum.NormalId.Left)
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 1)
	title.BackgroundTransparency = 1
	title.Text = "🏆  CONGRATULATIONS, YOU REACHED THE END OF THE MAP  🏆"
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = Color3.fromRGB(255, 232, 130)
	title.TextStrokeColor3 = Color3.fromRGB(20, 14, 0)
	title.TextStrokeTransparency = 0.4
	title.TextSize = 60
	title.TextScaled = false
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.Parent = signGui

	-- Floor-Markierung vor der Wand, damit der Spieler "ankommt".
	local floorMark = makePart(zone, "EndZoneFloorMark", Vector3.new(28, 0.1, 80), Vector3.new(wallFaceX - 18, LAYER_CONTAM + 0.05, centerZ), Color3.fromRGB(28, 36, 42), Enum.Material.SmoothPlastic, false)
	floorMark.Transparency = 0.4
	makePart(zone, "EndZoneFloorTrim", Vector3.new(30, 0.06, 84), Vector3.new(wallFaceX - 18, LAYER_CONTAM + 0.02, centerZ), LAB_WARNING_YELLOW, Enum.Material.SmoothPlastic, false).Transparency = 0.5

	-- Spotlight in Richtung Spieler, damit der Bereich beim Ankommen leuchtet.
	local lampMount = makePart(zone, "EndZoneLampMount", Vector3.new(2, 0.6, 2), Vector3.new(wallFaceX - 8, FLOOR_Y + L.WallHeight + BACTERIA_CEILING_LIFT - 3, centerZ), LAB_TRIM, Enum.Material.Metal, false)
	local lamp = makePart(zone, "EndZoneLamp", Vector3.new(1.4, 1.4, 1.4), lampMount.Position - Vector3.new(0, 0.7, 0), Color3.fromRGB(255, 240, 200), Enum.Material.Neon, false)
	lamp.Shape = Enum.PartType.Ball
	local pl = Instance.new("PointLight")
	pl.Brightness = 1.2
	pl.Range = 36
	pl.Color = Color3.fromRGB(255, 235, 190)
	pl.Parent = lamp
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

-- ---- Spawn-Boden-Detail ---------------------------------------------------
-- Macht aus den grossen leeren Boden-Flaechen im Spawn ein erkennbar
-- detailliertes Bio-Tech-Labor (Main Hub):
--   * Labor-Bodenplatten in verschiedenen Groessen (heller Grau-Mix).
--   * Dunkle Fugenlinien als Plattenraster.
--   * Eingelassene Kabelkanaele (Tech-Trenches) mit matter Akzentlinie.
--   * Wartungsdeckel (runde Service-Hatches mit Bolzen und Kreuzgriff).
--   * Bodenbeschriftungen via SurfaceGui auf dem Boden:
--     CENTRAL LAB / SPAWN LAB / TO BACTERIA LAB -> / DNA CORE / UPGRADE STATION.
--   * Kleine Biohazard-Markierungen.
--   * Wenige, kontrollierte Slime-Lecks (NICHT ueberall).
--   * Duenne cyan/gruene Wegfuehrungslinien (matt, kein Disco).
--
-- Layer-Hygiene: alle neuen Boden-Decals liegen ueber LAYER_CONTAM (0.58)
-- auf jeweils EINDEUTIGEN Y-Layern mit +0.06 Separation -> kein Z-Fighting
-- gegen bestehende Boden-Decals (LAYER_PATH..LAYER_CONTAM) oder den
-- HubPad-Belag (Y-Range -0.02..0.14).
-- XZ-Hygiene: Hub-Achteck-Region, SpawnLocation, NPC-Kiosks, Pet-Egg und
-- Guide-Arrows werden gemieden -> nichts steht im Laufweg, nichts
-- ueberdeckt eine bestehende Deko.
local LAYER_SPAWN_TILE = FLOOR_Y + 0.66
local LAYER_SPAWN_SEAM = FLOOR_Y + 0.72
local LAYER_SPAWN_CABLE = FLOOR_Y + 0.78
local LAYER_SPAWN_CABLE_GLOW = FLOOR_Y + 0.84
local LAYER_SPAWN_HATCH = FLOOR_Y + 0.90
local LAYER_SPAWN_BOLT = FLOOR_Y + 0.96
local LAYER_SPAWN_LABEL = FLOOR_Y + 1.02
local LAYER_SPAWN_BIO = FLOOR_Y + 1.08
local LAYER_SPAWN_LEAK = FLOOR_Y + 1.14
local LAYER_SPAWN_ACCENT = FLOOR_Y + 1.20

local LAB_FLOOR_TILE_LIGHT = Color3.fromRGB(220, 224, 224)
local LAB_FLOOR_TILE_MID = Color3.fromRGB(202, 207, 208)
local LAB_FLOOR_TILE_DARK = Color3.fromRGB(184, 190, 192)
local LAB_FLOOR_SEAM_COLOR = Color3.fromRGB(74, 80, 82)
local LAB_HATCH_BASE = Color3.fromRGB(58, 62, 64)
local LAB_HATCH_INNER = Color3.fromRGB(40, 44, 46)
local LAB_HATCH_BOLT = Color3.fromRGB(28, 30, 32)
local LAB_SLIME_OUTER = Color3.fromRGB(94, 136, 102)
local LAB_SLIME_INNER = Color3.fromRGB(132, 184, 132)

-- Boden-Beschriftung: SurfaceGui auf der Top-Flaeche, damit der Text wirklich
-- auf dem Boden gelesen wird (BillboardGui dreht sich zur Kamera -> falsch).
local function buildFloorLabel(parent, name, px, pz, sx, sz, text, color, rotateY)
	local plate = makePart(
		parent,
		"FloorLabelPlate_" .. name,
		Vector3.new(sx, 0.04, sz),
		Vector3.new(px, LAYER_SPAWN_LABEL, pz),
		Color3.fromRGB(32, 36, 38),
		Enum.Material.SmoothPlastic,
		false
	)
	plate.Transparency = 0.12
	if rotateY then
		plate.Orientation = Vector3.new(0, rotateY, 0)
	end

	local sg = Instance.new("SurfaceGui")
	sg.Name = "FloorLabelSurface"
	sg.Face = Enum.NormalId.Top
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 50
	sg.LightInfluence = 1
	sg.AlwaysOnTop = false
	sg.Adornee = plate
	sg.Parent = plate

	local tl = Instance.new("TextLabel")
	tl.BackgroundTransparency = 1
	tl.Size = UDim2.fromScale(0.94, 0.78)
	tl.Position = UDim2.fromScale(0.03, 0.11)
	tl.Text = text
	tl.Font = Enum.Font.GothamBold
	tl.TextScaled = true
	tl.TextColor3 = color
	tl.TextStrokeColor3 = Color3.new(0, 0, 0)
	tl.TextStrokeTransparency = 0.35
	tl.Parent = sg
	return plate
end

local function buildMaintenanceHatch(parent, name, px, pz, radius, accent)
	-- Roblox-Cylinder: Achse entlang LOKALER X. Mit Orientation (0,0,90) wird
	-- die lokale X-Achse zur Welt-Y-Achse -> Size.X ist die Hoehe der Scheibe,
	-- Size.Y/Z bilden den Durchmesser. Daher Size = (Hoehe, Durchmesser, Durchmesser).
	local outer = makePart(
		parent,
		"Hatch_" .. name,
		Vector3.new(0.10, radius * 2, radius * 2),
		Vector3.new(px, LAYER_SPAWN_HATCH, pz),
		LAB_HATCH_BASE,
		Enum.Material.Metal,
		false
	)
	outer.Shape = Enum.PartType.Cylinder
	outer.Orientation = Vector3.new(0, 0, 90)

	local inner = makePart(
		parent,
		"HatchInner_" .. name,
		Vector3.new(0.10, radius * 1.5, radius * 1.5),
		Vector3.new(px, LAYER_SPAWN_HATCH + 0.02, pz),
		LAB_HATCH_INNER,
		Enum.Material.Metal,
		false
	)
	inner.Shape = Enum.PartType.Cylinder
	inner.Orientation = Vector3.new(0, 0, 90)

	-- Kreuzgriff (T-handle) als zwei duenne Block-Riegel.
	makePart(
		parent,
		"HatchHandleX_" .. name,
		Vector3.new(radius * 1.2, 0.10, 0.45),
		Vector3.new(px, LAYER_SPAWN_BOLT, pz),
		accent:Lerp(LAB_DARK, 0.4),
		Enum.Material.Metal,
		false
	)
	makePart(
		parent,
		"HatchHandleZ_" .. name,
		Vector3.new(0.45, 0.10, radius * 1.2),
		Vector3.new(px, LAYER_SPAWN_BOLT, pz),
		accent:Lerp(LAB_DARK, 0.4),
		Enum.Material.Metal,
		false
	)

	-- Vier Bolzen am Rand (flache Bolt-Scheiben).
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		local bx = px + math.cos(a) * (radius - 0.55)
		local bz = pz + math.sin(a) * (radius - 0.55)
		local bolt = makePart(
			parent,
			"HatchBolt_" .. name .. i,
			Vector3.new(0.10, 0.55, 0.55),
			Vector3.new(bx, LAYER_SPAWN_BOLT, bz),
			LAB_HATCH_BOLT,
			Enum.Material.Metal,
			false
		)
		bolt.Shape = Enum.PartType.Cylinder
		bolt.Orientation = Vector3.new(0, 0, 90)
	end
end

local function buildCableTrench(parent, name, px, pz, length, axis, accent)
	local sx, sz, glowSx, glowSz
	if axis == "x" then
		sx, sz = length, 1.4
		glowSx, glowSz = length - 1.6, 0.32
	else
		sx, sz = 1.4, length
		glowSx, glowSz = 0.32, length - 1.6
	end
	makePart(
		parent,
		"CableTrench_" .. name,
		Vector3.new(sx, 0.08, sz),
		Vector3.new(px, LAYER_SPAWN_CABLE, pz),
		Color3.fromRGB(48, 52, 54),
		Enum.Material.Metal,
		false
	)
	neonStrip(
		parent,
		Vector3.new(glowSx, 0.06, glowSz),
		Vector3.new(px, LAYER_SPAWN_CABLE_GLOW, pz),
		accent,
		0.55
	)
end

local function buildFloorBiohazardMark(parent, name, px, pz)
	local plate = makePart(
		parent,
		"BioMark_" .. name,
		Vector3.new(2.6, 0.05, 2.6),
		Vector3.new(px, LAYER_SPAWN_BIO, pz),
		LAB_WARNING_YELLOW,
		Enum.Material.SmoothPlastic,
		false
	)
	plate.Transparency = 0.12
	local core = makePart(
		parent,
		"BioMarkCore_" .. name,
		Vector3.new(1.6, 0.05, 1.6),
		Vector3.new(px, LAYER_SPAWN_BIO + 0.02, pz),
		LAB_DARK,
		Enum.Material.SmoothPlastic,
		false
	)
	core.Transparency = 0.06
	-- Drei kleine "Petals" symbolisieren das Biohazard-Zeichen ohne Bildtextur.
	for i = 0, 2 do
		local a = i * (math.pi * 2 / 3) + math.pi / 2
		local petalX = px + math.cos(a) * 0.85
		local petalZ = pz + math.sin(a) * 0.85
		local petal = makePart(
			parent,
			"BioMarkPetal_" .. name .. i,
			Vector3.new(0.05, 0.75, 0.75),
			Vector3.new(petalX, LAYER_SPAWN_BIO + 0.03, petalZ),
			LAB_WARNING_YELLOW,
			Enum.Material.SmoothPlastic,
			false
		)
		petal.Shape = Enum.PartType.Cylinder
		petal.Orientation = Vector3.new(0, 0, 90)
	end
end

local function buildSlimeLeak(parent, name, px, pz, sx, sz)
	local pool = makePart(
		parent,
		"SlimeLeak_" .. name,
		Vector3.new(sx, 0.05, sz),
		Vector3.new(px, LAYER_SPAWN_LEAK, pz),
		LAB_SLIME_OUTER,
		Enum.Material.SmoothPlastic,
		false
	)
	pool.Transparency = 0.16
	local core = makePart(
		parent,
		"SlimeLeakCore_" .. name,
		Vector3.new(sx * 0.6, 0.05, sz * 0.6),
		Vector3.new(px, LAYER_SPAWN_LEAK + 0.02, pz),
		LAB_SLIME_INNER,
		Enum.Material.SmoothPlastic,
		false
	)
	core.Transparency = 0.10
end

local function buildSpawnFloorDetail(parent, cx)
	local model = Instance.new("Model")
	model.Name = "SpawnFloorDetail"
	model.Parent = parent

	-- Die kleinen hellen Rechteck-Bodenplatten wurden entfernt. Der Spawn
	-- nutzt weiter den sauberen Grundboden plus Kabel, Markierungen und Props.

	-- ===== 3) Eingelassene Kabelkanaele ==================================
	-- Verbinden den Hub visuell mit Back-Bereich, Kiosk-Reihe und Area-1.
	-- Liegen seitlich vom Laufweg (z != 0) -> blockieren keinen Weg.
	buildCableTrench(model, "BackToHubTop", cx - 80, 14, 80, "x", LAB_GREEN)
	buildCableTrench(model, "BackToHubBot", cx - 80, -42, 80, "x", LAB_CYAN)
	buildCableTrench(model, "HubToFrontTop", cx + 80, 14, 80, "x", LAB_GREEN)
	buildCableTrench(model, "HubToFrontBot", cx + 80, -42, 80, "x", LAB_CYAN)
	buildCableTrench(model, "HubToKioskA", cx - 64, 50, 56, "z", LAB_GREEN)
	buildCableTrench(model, "HubToKioskB", cx + 16, 50, 56, "z", LAB_CYAN)
	buildCableTrench(model, "FrontEdgeNorth", cx + 158, 50, 90, "z", LAB_CYAN)
	buildCableTrench(model, "BackEdgeNorth", cx - 130, 50, 90, "z", LAB_GREEN)

	-- ===== 4) Wartungsdeckel =============================================
	-- Verteilt in unauffaelligen Boden-Ecken; nie unter Spawn/Hub/Kiosk.
	buildMaintenanceHatch(model, "BackLeft", cx - 122, -55, 2.4, LAB_CYAN)
	buildMaintenanceHatch(model, "BackRight", cx - 122, 80, 2.4, LAB_GREEN)
	buildMaintenanceHatch(model, "MidBack", cx - 60, -60, 2.0, LAB_GREEN)
	buildMaintenanceHatch(model, "FrontLeft", cx + 50, -50, 2.0, LAB_CYAN)
	buildMaintenanceHatch(model, "FrontMid", cx + 100, -50, 2.4, LAB_GREEN)
	buildMaintenanceHatch(model, "FarFrontLeft", cx + 150, -50, 2.2, LAB_CYAN)
	buildMaintenanceHatch(model, "FarFrontRight", cx + 150, 65, 2.2, LAB_GREEN)
	buildMaintenanceHatch(model, "FrontNearArea1", cx + 158, 35, 2.0, LAB_CYAN)

	-- ===== 5) Bodenbeschriftungen ========================================
	-- SurfaceGui auf der Top-Flaeche -> Text liegt wirklich auf dem Boden.
	-- Y-Layer 1.02 ist sicher ueber HubPad (Y-Top 0.14), SpawnLocation
	-- (Y-Top 1.0) und allen bestehenden Boden-Decals (max LAYER_CONTAM=0.58).

	-- CENTRAL LAB: gross, zentral zwischen Spawn-Pad und Kiosk-Reihe.
	-- z=40..60 -> klar zwischen SpawnLocation (z[-7,7]) und Kiosk-Body (z[79,85]).
	buildFloorLabel(model, "CentralLab", cx, 50, 56, 8, "CENTRAL LAB", Color3.fromRGB(170, 230, 220))

	-- SPAWN LAB: direkt vor dem Spawn-Pad (z=14, sz=5 -> z[11.5,16.5]).
	-- Meidet Spawn-Pad (z[-7,7]) und Guide-Arrows (z[-2.5,2.5]).
	buildFloorLabel(model, "SpawnLab", cx, 14, 22, 5, "SPAWN LAB", Color3.fromRGB(170, 230, 220))

	-- TO BACTERIA LAB ->: vorn-rechts, zeigt Richtung Area 1 (+X).
	-- z=14 statt z=4 -> NICHT auf den Guide-Arrows bei z[-2.5,2.5].
	buildFloorLabel(
		model,
		"ToBacteriaLab",
		cx + 130,
		14,
		60,
		8,
		"TO BACTERIA LAB \xE2\x86\x92",
		Color3.fromRGB(174, 240, 188)
	)

	-- DNA CORE: auf dem Hub-Pad, aber AUSSERHALB der Virus-Statuen-Basis
	-- (Statue bei (cx, -45) mit Sockel-Radius 15 -> Distanz >=20 sicher).
	-- z=-22 -> Distanz 23 zum Statuen-Center, klar ausserhalb des Sockels.
	-- HubPad-Y-Top liegt bei 0.14; Label-Y bei 1.02 -> kein Z-Fighting.
	buildFloorLabel(model, "DnaCore", cx, -22, 22, 6, "DNA CORE", Color3.fromRGB(160, 220, 230))

	-- UPGRADE STATION: vor dem Upgrade-Kiosk (cx-64, _, 82) -> z=68, sz=6.
	-- Kiosk-Body bei z[79,85]; Label z[65,71] -> keine Ueberlappung.
	buildFloorLabel(
		model,
		"UpgradeStation",
		cx - 64,
		68,
		28,
		6,
		"UPGRADE STATION",
		Color3.fromRGB(174, 240, 188)
	)

	-- ===== 6) Biohazard-Markierungen =====================================
	-- Klein, sparsam, nahe Fass-/Tank-Deko bzw. an Kanal-Knotenpunkten.
	buildFloorBiohazardMark(model, "BackLeft", cx - 90, -75)
	buildFloorBiohazardMark(model, "BackRight", cx - 90, 95)
	buildFloorBiohazardMark(model, "FrontLeftEdge", cx + 80, -75)
	buildFloorBiohazardMark(model, "FrontRightEdge", cx + 80, 75)
	buildFloorBiohazardMark(model, "FarFront", cx + 168, -70)

	-- ===== 7) Kontrollierte Slime-Lecks ==================================
	-- Nur DREI Stellen, jeweils nahe Bio-/Mutation-Deko. Kein "Disco".
	buildSlimeLeak(model, "NearDrums", cx - 92, -68, 4.4, 3.2)
	buildSlimeLeak(model, "NearMutationTube", cx - 95, 28, 3.8, 2.8)
	buildSlimeLeak(model, "FrontEdge", cx + 92, -68, 3.6, 2.6)

	-- ===== 8) Cyan/gruene Akzent-Wegfuehrung =============================
	-- Schmale matte Linien (neonStrip -> hohe Mindest-Transparenz) flankieren
	-- den Laufweg vom Hub bis Area 1 und markieren die Kiosk-Reihe.

	-- Walk-Path-Begleitung: zwei gruene Parallel-Linien beiderseits des
	-- Laufwegs (z=+/-8) von Spawn (x=cx) bis kurz vor Area 1 (x=-20).
	-- Liegen z-seitig knapp neben den Guide-Arrows (z[-2.5, 2.5]) -> keine
	-- XZ-Ueberlappung mit Arrow-Decals.
	neonStrip(
		model,
		Vector3.new(160, 0.05, 0.45),
		Vector3.new(cx + 80, LAYER_SPAWN_ACCENT, 8),
		LAB_GREEN,
		0.45
	)
	neonStrip(
		model,
		Vector3.new(160, 0.05, 0.45),
		Vector3.new(cx + 80, LAYER_SPAWN_ACCENT, -8),
		LAB_GREEN,
		0.45
	)

	-- Kiosk-Reihen-Akzent: lange duenne cyan Linie vor der Kiosk-Reihe
	-- (z=68, knapp vor Kiosk-Body z[79, 85]).
	neonStrip(
		model,
		Vector3.new(220, 0.05, 0.45),
		Vector3.new(cx - 4, LAYER_SPAWN_ACCENT, 68),
		LAB_CYAN,
		0.55
	)

	-- Hub-Eingangs-Akzent: kurze cyan Querlinie zwischen Hub-Vorderkante
	-- und Spawn-Pad (z=-10, x-Spann 30 zentriert auf cx).
	-- Hub-z geht bis -6, SpawnLocation z=-7..7 -> z=-10 ist ON hub pad,
	-- aber Y=1.20 ist sicher ueber HubPad (Y-Top 0.14).
	neonStrip(
		model,
		Vector3.new(30, 0.05, 0.45),
		Vector3.new(cx, LAYER_SPAWN_ACCENT, -10),
		LAB_CYAN,
		0.55
	)

	return model
end

-- ---- Spawn Lab ------------------------------------------------------------

local function buildSpawnLab(parent, bedsFolder, orgFolders)
	local cx = L.SpawnCenterX
	local model = Instance.new("Model")
	model.Name = "SpawnLab"
	model.Parent = parent

	-- Boden + Shell des Spawn-Raums. Endet bei X=-60, weil Area 1's Shell jetzt
	-- 60 Studs nach hinten verschoben ist (Naht direkt nach dem Boss).
	local spawnEndX = -60
	local floorLen = math.abs(spawnEndX - (cx - 150)) -- (cx-150) .. spawnEndX
	local floorCx = (cx - 150 + spawnEndX) / 2
	buildShellSegment(model, floorCx, floorLen, Color3.fromRGB(95, 230, 200), Color3.fromRGB(150, 255, 220), true)
	addBackWallLabFeature(model, cx)
	addCeilingConduits(model, cx)
	addSpawnFloorArrows(model, cx, LAB_GREEN)
	-- Reine Environment-Polish-Schicht (Wand-Schilder, Glasfenster mit
	-- Virus-Probe, Lueftungen, Kabel-Trassen, zusaetzliche Decken-Lichter,
	-- Warn-Lampen, Spawn-Ring + Bodenlabel, Atmosphaere-Lights). Beruehrt
	-- keine bestehenden Systeme oder Stations-Folder.
	addSpawnEnvironmentPolish(model, cx)

	-- Boden-Detail (Hub fertig wirken lassen): Labor-Bodenplatten, Fugen,
	-- Kabelkanaele, Wartungsdeckel, Bodenbeschriftungen, Biohazard-Marken,
	-- kontrollierte Slime-Lecks, dezente cyan/gruene Wegfuehrung.
	buildSpawnFloorDetail(orgFolders.floorDetail, cx)
	buildLeaderboardZone(orgFolders.hub, cx)

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
	buildConsole(model, "MutationConsole", Vector3.new(cx + 34, FLOOR_Y, -48), LAB_CYAN, "CORE")
	buildTestTubeRack(model, "SampleTubeRack", Vector3.new(cx + 42, FLOOR_Y, 96), LAB_GREEN)
	buildCrateStack(model, "LabStorageCratesA", Vector3.new(cx + 88, FLOOR_Y, -76), LAB_CYAN)

	-- Dediziertes Pet-Egg: mit Abstand auf der anderen Seite der Shop-Reihe.
	-- Das breite rote Podest inszeniert das Ei wie eine wichtige Labor-Probe
	-- auf einem Thron, blockiert aber keinen Hauptweg.
	local shopEggPos = Vector3.new(cx + 118, FLOOR_Y, 82)
	local starterEgg = PetConfig.getEggById(PetConfig.DefaultEggId)
	local starterEggName = if starterEgg then starterEgg.displayName else "Beginner Virus Egg"
	local starterEggCost = if starterEgg then starterEgg.cost else PetConfig.EggCost
	local starterEggColor = if starterEgg then starterEgg.color else Color3.fromRGB(52, 210, 92)
	local thronePad = makePart(model, "PetEggThronePedestal", Vector3.new(32, 1.1, 22), shopEggPos + Vector3.new(0, 0.55, 0), Color3.fromRGB(112, 32, 32), Enum.Material.Metal, true)
	thronePad.Transparency = 0.03
	makePart(model, "PetEggThroneFrontStep", Vector3.new(34, 0.35, 5.5), shopEggPos + Vector3.new(0, 0.18, -13.8), Color3.fromRGB(78, 22, 22), Enum.Material.SmoothPlastic, true)
	local hoverRing = makePart(model, "PetEggHoverRing", Vector3.new(18, 0.12, 18), shopEggPos + Vector3.new(0, 1.18, 0), starterEggColor, Enum.Material.Neon, false)
	hoverRing.Shape = Enum.PartType.Cylinder
	hoverRing.Orientation = Vector3.new(0, 0, 90)
	hoverRing.Transparency = 0.55
	local egg = makePart(model, "PetEgg", Vector3.new(8.8, 10.8, 8.8), shopEggPos + Vector3.new(0, 8.7, 0), starterEggColor, Enum.Material.SmoothPlastic, false)
	egg.CanQuery = true -- anklickbar (OpenEgg ClickDetector; Main verdrahtet)
	egg.Shape = Enum.PartType.Ball
	egg.Transparency = 0.05
	egg:SetAttribute("AreaIndex", 1)
	egg:SetAttribute("EggId", PetConfig.DefaultEggId)
	egg:SetAttribute("EggName", starterEggName)
	egg:SetAttribute("EggCost", starterEggCost)
	local virusGlow = Instance.new("PointLight")
	virusGlow.Name = "VirusEggGlow"
	virusGlow.Brightness = 0.9
	virusGlow.Range = 16
	virusGlow.Color = starterEggColor:Lerp(Color3.fromRGB(210, 255, 220), 0.35)
	virusGlow.Parent = egg
	for i = 0, 7 do
		local a = i * math.pi * 2 / 8
		local spike = makePart(model, "VirusEggNodule", Vector3.new(1.35, 1.35, 1.35), egg.Position + Vector3.new(math.cos(a) * 5.4, 0.5 + math.sin(i * 1.7) * 1.3, math.sin(a) * 5.4), starterEggColor:Lerp(Color3.fromRGB(25, 90, 40), 0.35), Enum.Material.SmoothPlastic, false)
		spike.Shape = Enum.PartType.Ball
		spike.CanCollide = false
	end
	local cd = Instance.new("ClickDetector")
	cd.Name = "OpenEgg"
	cd.MaxActivationDistance = 16
	cd.Parent = egg
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenEggPrompt"
	prompt.ActionText = "View Egg"
	prompt.ObjectText = starterEggName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = egg
	label(egg, string.format("%s\nCost: %s DNA", starterEggName, NumberFormatter.format(starterEggCost)), starterEggColor:Lerp(Color3.fromRGB(220, 255, 225), 0.25), 40, UDim2.fromOffset(240, 70), Vector3.new(0, 7, 0))
	VirusLabBuilder.PetEgg = egg

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
		{ n = "UpgradeLabStation", t = "UPGRADE LAB", h = "Improve your mutation power", c = Color3.fromRGB(80, 220, 110), dx = -64, z = 82, menu = "Skills", action = "Open Upgrades", npc = "Dr. Upgrade", style = "Lab" },
		{ n = "AuraStation", t = "AURA STATION", h = "Tier 1 mutation effects", c = Color3.fromRGB(178, 110, 240), dx = -24, z = 82, menu = "Auras", action = "Open Auras", npc = "Aura Dealer", style = "Dark", tier = 1 },
		{ n = "ShopTerminalStation", t = "SHOP", h = "Boosts & Items", c = Color3.fromRGB(60, 140, 240), dx = 16, z = 82, menu = "Shop", action = "Open Shop", npc = "Shop Vendor", style = "Dark" },
		{ n = "DailyRewardStation", t = "DAILY REWARD", h = "Claim free rewards", c = Color3.fromRGB(248, 208, 60), dx = 56, z = 82, menu = "Daily", action = "Claim Daily", npc = "Daily Bot", style = "Bot" },
	}
	for _, st in ipairs(stations) do
		buildStationKiosk(orgFolders.npcStations, st.n, Vector3.new(cx + st.dx, FLOOR_Y, st.z), st.c, st.t, st.h, st.menu, st.action, st.npc, st.style, -1, st.tier)
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

local function buildAreaAuraStation(parent: Instance, area)
	if area.index < 2 or area.index > 10 then
		return
	end

	local gateX = area.hallCenterX + L.GateOffsetX
	local stationX = gateX - 34
	local stationZ = 25
	local accent = area.primaryColor:Lerp(Color3.fromRGB(132, 116, 170), 0.3)
	local station = Instance.new("Folder")
	station.Name = "AreaAuraStation_" .. tostring(area.index)
	station.Parent = parent

	buildStationKiosk(
		station,
		"AuraStation_Area" .. tostring(area.index),
		Vector3.new(stationX, FLOOR_Y, stationZ),
		accent,
		"AURA STATION",
		"Tier " .. tostring(area.index) .. " mutation effects",
		"Auras",
		"Open Auras",
		"Aura Dealer",
		"Dark",
		-1,
		area.index
	)

	station:SetAttribute("AreaIndex", area.index)
	station:SetAttribute("AuraTier", area.index)
	station:SetAttribute("MenuTarget", "Auras")
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
	local teleportFolder = makeFolder("TeleportPoints", Workspace)
	clearChildren(teleportFolder)
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
		floorDetail = makeFolder("SpawnFloorDetail", spawnHub),
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
		local theme = themeFor(area.index)

		-- Shell-Segment der Area. Center um 60 Studs nach hinten verschoben,
		-- damit die Naht 40 Studs hinter dem Boss liegt (war 100). Der neue
		-- Area-Farbton ist direkt nach dem Boss sichtbar, statt erst weit
		-- spaeter im Zwischen-Korridor.
		-- Sonderfall letzte Area: kein "naechstes Gate", die Shell muss bis
		-- zur FinalWall reichen, sonst entsteht ein Boden-Loch zwischen Shell-
		-- Ende (hallX+200) und FinalWall (hallX+260). Wir verlaengern die
		-- Shell um 60 Studs nach vorne und ruecken den Mittelpunkt entsprechend.
		local shellCenterX = hallX - 60
		local shellLengthX = L.AreaSpan
		if area.index == AreaConfig.count() then
			shellCenterX = hallX - 30
			shellLengthX = L.AreaSpan + 60
		end
		buildShellSegment(areaModel, shellCenterX, shellLengthX, primary, secondary, true, area.id, area.index > 1)
		liftBacteriaLabCeiling(areaModel)
		addBacteriaLabDetails(areaModel, area, hallX, primary)

		-- Eigenstaendige Identitaet pro Area 2..10: Eingangsbogen + Hero-Landmark.
		-- Bewusst NICHT in Area 1 (Bacteria Lab bleibt unangetastet).
		if area.index > 1 then
			buildAreaEntranceArch(areaModel, area, hallX, theme, theme.accent)
			buildAreaCenterpiece(areaModel, area, hallX, theme, theme.accent)
		end

		-- Trainingsbereich (vor der Halle) + ggf. Rebirth-Gate.
		buildTrainingArea(areaModel, bedsFolder, gatesFolder, area, hallX + L.TrainingOffsetX)
		buildAreaAuraStation(areaModel, area)

		-- Gegner dieser Area. 4 Normal-Slots vorne, dann Luecke + Boss-Raum.
		local defs = EnemyConfig.getByArea(area.id)
		local enemyAreaFolder = makeFolder(area.id, enemyFolder)
		local normalCount = L.EnemiesPerArea - 1
		local normalSpan = (normalCount - 1) * L.NormalEnemySpacing
		local totalSpan = normalSpan + L.BossOffsetX
		local startX = hallX - totalSpan / 2

		local function enemyOffset(index: number, isBoss: boolean): number
			if isBoss then
				return normalSpan + L.BossOffsetX
			end
			return (index - 1) * L.NormalEnemySpacing
		end

		-- Labor-Luke: Power-Anforderung aus der zentralen Area-Progression.
		local gateReq = area.requiredPower
		buildGate(gatesFolder, area, hallX + L.GateOffsetX, gateReq)
		local teleportPoint = makePart(
			teleportFolder,
			"TeleportPoint_Area" .. tostring(area.index),
			Vector3.new(2, 1, 2),
			Vector3.new(hallX + L.GateOffsetX + 8, FLOOR_Y + 1, 0),
			Color3.new(1, 1, 1),
			Enum.Material.SmoothPlastic,
			false
		)
		teleportPoint.Transparency = 1
		teleportPoint.CanCollide = false
		teleportPoint.CanTouch = false
		teleportPoint.CanQuery = false
		teleportPoint:SetAttribute("AreaNumber", area.index)
		teleportPoint:SetAttribute("AreaName", area.displayName)

		for i, def in ipairs(defs) do
			local ex = startX + enemyOffset(i, def.IsBoss)
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
			-- Normale Gegner: halber Normal-Abstand davor. Boss: mitten in der
			-- Boss-Luecke, doppelt als Schwelle ins Boss-Zimmer.
			if i >= 2 then
				local borderOffset = if def.IsBoss then L.BossOffsetX * 0.5 else L.NormalEnemySpacing * 0.5
				buildBorder(bordersFolder, def, ex - borderOffset, primary)
				if def.IsBoss then
					buildBossThreshold(enemyAreaFolder, def, ex - borderOffset + 22, theme, primary)
				end
			end
		end

		-- Eine Stage-Egg-Station seitlich (nicht im Weg).
		local eggDefs = EggCatchConfig.getForArea(area.index)
		for si, eggDef in ipairs(eggDefs) do
			local stationX = hallX
			local stationZ = L.EggZ
			if area.index >= 2 then
				local entranceX = hallX + L.GateOffsetX
				local rightSideWidth = CORRIDOR_MAX_Z - BACTERIA_RIGHT_LIMIT_Z
				stationX = entranceX - (L.EnemySpacing + 12)
				stationZ = BACTERIA_RIGHT_LIMIT_Z + math.min(30, rightSideWidth * 0.35)
			end
			buildEggStation(eggFolder, area.index, si, eggDef, Vector3.new(stationX, FLOOR_Y + 0.6, stationZ))
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
			local finalWallX = hallX + L.AreaSpan / 2
			makePart(
				areaModel,
				"FinalWall",
				Vector3.new(4, finalWallHeight, FLOOR_SIZE_Z),
				Vector3.new(finalWallX, FLOOR_Y + finalWallHeight / 2, FLOOR_CENTER_Z),
				LAB_DARK,
				Enum.Material.Metal,
				true
			)
			-- Spiegel der Spawn-Ranked-Tabelle + Glueckwunsch-Schild auf der
			-- -X-Seite der FinalWall. LeaderboardService aktualisiert beide
			-- Zones automatisch (siehe Refactor). Parent ist orgFolders.hub
			-- (Workspace.Map.SpawnHub), damit die Zone via getZones (sucht in
			-- Workspace.Map) gefunden wird -- die Welt-Position bleibt am
			-- Map-Ende, unabhaengig von der Folder-Hierarchie.
			buildEndLeaderboardZone(orgFolders.hub, finalWallX - 2)
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
