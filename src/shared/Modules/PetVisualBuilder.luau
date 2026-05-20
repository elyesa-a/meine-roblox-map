--!nonstrict
-- PetVisualBuilder: zentrale, stilisierte Pet-Modellfabrik fuer den
-- Virus-Lab-Simulator.
--
-- Idee:
--   * AREA bestimmt den "Spezies"-Archetyp (Bacteria, Cell, Gene, Toxic,
--     Virus, Glitch, Biohazard, Shadow, Omega, Containment).
--   * RARITY bestimmt schichtweise Detail-/Glanz-Layer (Antennen ->
--     Orbiter -> Trim-Platten + Licht -> Halo + Funken-Aura ->
--     Strahl + Crown + Mythic-Effekte).
--   * EGG TIER (Common/Rare/Epic) toent die Akzentfarbe (von neutral zu
--     cyan/gruen).
--
-- Output: alle Parts sind Anchored, CanCollide=false, CanQuery=false,
-- Massless=true -> sicher fuer eine schwebende Begleiter-Geometrie.
-- PrimaryPart wird vom Aufrufer (PetService) auf den zurueckgegebenen
-- Core-Part gesetzt.

local PetVisualBuilder = {}

local DEFAULT_COLOR = Color3.fromRGB(235, 238, 240)

local RarityRank = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythic = 6,
}

local RarityColor = {
	Common = Color3.fromRGB(235, 238, 240),
	Uncommon = Color3.fromRGB(90, 220, 125),
	Rare = Color3.fromRGB(70, 155, 255),
	Epic = Color3.fromRGB(175, 90, 255),
	Legendary = Color3.fromRGB(255, 172, 45),
	Mythic = Color3.fromRGB(255, 70, 125),
}

local ArchetypeByArea = {
	[1] = "Bacteria",
	[2] = "Cell",
	[3] = "Gene",
	[4] = "Toxic",
	[5] = "Virus",
	[6] = "Glitch",
	[7] = "Biohazard",
	[8] = "Shadow",
	[9] = "Omega",
	[10] = "Containment",
}

local TIER_ACCENT_MIX = {
	Common = 0.12,
	Rare = 0.32,
	Epic = 0.55,
}

local function lerpColor(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, math.clamp(t, 0, 1))
end

-- Kleines Helfer-Setup. Werte werden per props-Tabelle uebergeben, damit
-- die Archetyp-Code-Bloecke kompakt bleiben.
local function makePart(parent: Instance, name: string, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- Palette aus Rarity + Tier ableiten. Tier mischt einen Bio-Lab-Akzent
-- (cyan->gruen->violett) in die Hauptfarbe -> Common/Rare/Epic-Eier
-- erzeugen sichtbar verschiedene Farb-Familien fuer Pets gleicher Rarity.
local function makePalette(rarity: string, tier: string?)
	local main = RarityColor[rarity] or DEFAULT_COLOR
	local mix = TIER_ACCENT_MIX[tier or ""] or 0.18
	local accent = lerpColor(main, Color3.fromRGB(96, 232, 198), mix)
	local soft = lerpColor(main, Color3.fromRGB(245, 248, 248), 0.30)
	local dark = lerpColor(main, Color3.fromRGB(12, 16, 22), 0.55)
	local glow = lerpColor(main, Color3.fromRGB(220, 246, 255), 0.42)
	return { main = main, soft = soft, dark = dark, accent = accent, glow = glow }
end

-- Standard-Augenpaar nach vorne (-Z = nach vorn im PrimaryPart-Frame).
local function addEyes(parent: Instance, head: Vector3, radius: number, eyeColor: Color3?)
	local eyeC = eyeColor or Color3.fromRGB(248, 252, 252)
	local pupilC = Color3.fromRGB(10, 13, 18)
	local sideX = radius * 0.36
	local upY = radius * 0.25
	local front = -radius * 0.84
	local frontPupil = -radius * 0.95
	local sizeEye = Vector3.new(radius * 0.36, radius * 0.36, radius * 0.18)
	local sizePup = Vector3.new(radius * 0.16, radius * 0.16, radius * 0.10)
	makePart(parent, "EyeL", {
		Shape = Enum.PartType.Ball,
		Size = sizeEye,
		Color = eyeC,
		Material = Enum.Material.SmoothPlastic,
		CFrame = CFrame.new(head + Vector3.new(-sideX, upY, front)),
	})
	makePart(parent, "EyeR", {
		Shape = Enum.PartType.Ball,
		Size = sizeEye,
		Color = eyeC,
		Material = Enum.Material.SmoothPlastic,
		CFrame = CFrame.new(head + Vector3.new(sideX, upY, front)),
	})
	makePart(parent, "PupL", {
		Shape = Enum.PartType.Ball,
		Size = sizePup,
		Color = pupilC,
		Material = Enum.Material.SmoothPlastic,
		CFrame = CFrame.new(head + Vector3.new(-sideX, upY, frontPupil)),
	})
	makePart(parent, "PupR", {
		Shape = Enum.PartType.Ball,
		Size = sizePup,
		Color = pupilC,
		Material = Enum.Material.SmoothPlastic,
		CFrame = CFrame.new(head + Vector3.new(sideX, upY, frontPupil)),
	})
end

-- =====================================================================
-- ARCHETYPEN: jede Funktion baut den Koerper ohne Rarity-Add-Ons. Der
-- erste zurueckgegebene Part ist der Core (PrimaryPart-Kandidat).
-- =====================================================================
local Archetypes = {}

-- Area 1: Bacteria -- runde, freundliche Mikrobe mit Cilia-Haaren.
function Archetypes.Bacteria(model, palette, scale)
	local r = 0.95 * scale
	local core = makePart(model, "PetCore", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(r * 2.0, r * 1.75, r * 2.0),
		Color = palette.main,
		Material = Enum.Material.SmoothPlastic,
		CFrame = CFrame.new(),
	})
	local n = 8
	for i = 1, n do
		local a = (i - 1) * (math.pi * 2 / n)
		makePart(model, "Cilia" .. i, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(r * 0.32, r * 0.32, r * 0.32),
			Color = palette.soft,
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.10,
			CFrame = CFrame.new(math.cos(a) * r * 0.95, r * 0.35, math.sin(a) * r * 0.95),
		})
	end
	addEyes(model, Vector3.new(0, 0, 0), r)
	return core
end

-- Area 2: Cell -- transparente Membran mit innerem Nukleus + Organellen.
function Archetypes.Cell(model, palette, scale)
	local r = 1.0 * scale
	local core = makePart(model, "PetCore", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(r * 2.0, r * 2.0, r * 2.0),
		Color = palette.soft,
		Material = Enum.Material.Glass,
		Transparency = 0.32,
		CFrame = CFrame.new(),
	})
	makePart(model, "Nucleus", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(r * 1.0, r * 1.0, r * 1.0),
		Color = palette.dark,
		Material = Enum.Material.SmoothPlastic,
		CFrame = CFrame.new(),
	})
	for i = 1, 3 do
		local a = (i - 1) * math.pi * 2 / 3
		makePart(model, "Organelle" .. i, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(r * 0.42, r * 0.28, r * 0.42),
			Color = palette.accent,
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.12,
			CFrame = CFrame.new(math.cos(a) * r * 0.55, ((i % 2) * 0.4 - 0.2) * r, math.sin(a) * r * 0.55),
		})
	end
	addEyes(model, Vector3.new(0, 0, 0), r * 0.95)
	return core
end

-- Area 3: Gene -- Kopf + DNA-Doppelhelix-Schwanz.
function Archetypes.Gene(model, palette, scale)
	local r = 0.85 * scale
	local core = makePart(model, "PetCore", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(r * 2.0, r * 2.0, r * 2.0),
		Color = palette.main,
		Material = Enum.Material.SmoothPlastic,
		CFrame = CFrame.new(),
	})
	for s = 0, 1 do
		local phase = s * math.pi
		for i = 1, 6 do
			local t = i / 6
			local cx = math.cos(t * math.pi * 3 + phase) * r * 0.65
			local cy = math.sin(t * math.pi * 3 + phase) * r * 0.45
			local cz = r * (1.05 + t * 1.55)
			makePart(model, string.format("HelixS%dN%d", s, i), {
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(r * 0.36, r * 0.36, r * 0.36),
				Color = if s == 0 then palette.accent else palette.soft,
				Material = Enum.Material.SmoothPlastic,
				CFrame = CFrame.new(cx, cy, cz),
			})
		end
	end
	addEyes(model, Vector3.new(0, 0, 0), r)
	return core
end

-- Area 4: Toxic -- asymmetrische Schleim-Blob mit Tropfen und Slime-Patches.
function Archetypes.Toxic(model, palette, scale)
	local r = 0.95 * scale
	local core = makePart(model, "PetCore", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(r * 2.1, r * 1.7, r * 1.95),
		Color = palette.main,
		Material = Enum.Material.SmoothPlastic,
		CFrame = CFrame.new(),
	})
	for i = 1, 3 do
		local dx = (i - 2) * r * 0.55
		local dropletSize = r * (0.32 + 0.08 * (3 - i))
		makePart(model, "Droplet" .. i, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(dropletSize, dropletSize, dropletSize),
			Color = palette.accent,
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.12,
			CFrame = CFrame.new(dx, -r * 0.85, 0),
		})
	end
	for i = 1, 2 do
		makePart(model, "SlimePatch" .. i, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(r * 0.55, r * 0.22, r * 0.55),
			Color = Color3.fromRGB(122, 196, 88),
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.05,
			CFrame = CFrame.new((i - 1.5) * r * 0.7, r * 0.7, 0),
		})
	end
	addEyes(model, Vector3.new(0, 0, 0), r * 0.95)
	return core
end

-- Area 5: Virus -- ikosaedrische Spike-Kugel (klassisches Viruspartikel).
function Archetypes.Virus(model, palette, scale)
	local r = 0.82 * scale
	local core = makePart(model, "PetCore", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(r * 2.0, r * 2.0, r * 2.0),
		Color = palette.main,
		Material = Enum.Material.SmoothPlastic,
		CFrame = CFrame.new(),
	})
	local n = 10
	for i = 1, n do
		local phi = math.acos(1 - 2 * (i - 0.5) / n)
		local theta = math.pi * (1 + math.sqrt(5)) * (i - 0.5)
		local dir = Vector3.new(math.sin(phi) * math.cos(theta), math.cos(phi), math.sin(phi) * math.sin(theta))
		local spikeLen = r * 0.80
		local mid = dir * (r + spikeLen * 0.5)
		makePart(model, "Spike" .. i, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(spikeLen, r * 0.18, r * 0.18),
			Color = palette.dark,
			Material = Enum.Material.SmoothPlastic,
			CFrame = CFrame.lookAt(mid, mid + dir) * CFrame.Angles(0, math.rad(90), 0),
		})
		makePart(model, "SpikeTip" .. i, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(r * 0.32, r * 0.32, r * 0.32),
			Color = palette.accent,
			Material = Enum.Material.SmoothPlastic,
			CFrame = CFrame.new(dir * (r + spikeLen)),
		})
	end
	addEyes(model, Vector3.new(0, 0, 0), r * 0.95)
	return core
end

-- Area 6: Glitch -- Pixel-Block-Kreatur, leichte Asymmetrie.
function Archetypes.Glitch(model, palette, scale)
	local r = 0.95 * scale
	local core = makePart(model, "PetCore", {
		Shape = Enum.PartType.Block,
		Size = Vector3.new(r * 1.8, r * 1.8, r * 1.8),
		Color = palette.main,
		Material = Enum.Material.SmoothPlastic,
		CFrame = CFrame.new(),
	})
	-- deterministisch (kein math.random, damit identische Pets identisch aussehen)
	local fragments = {
		{ x = -1.4, y = 0.4, z = 0.6, s = 0.40 },
		{ x = 1.3, y = 0.7, z = -0.3, s = 0.36 },
		{ x = 0.2, y = 1.3, z = 0.1, s = 0.30 },
		{ x = -0.6, y = -0.8, z = 0.9, s = 0.34 },
		{ x = 1.0, y = -0.2, z = 1.1, s = 0.38 },
	}
	for i, f in ipairs(fragments) do
		makePart(model, "Glitch" .. i, {
			Shape = Enum.PartType.Block,
			Size = Vector3.new(f.s * scale, f.s * scale, f.s * scale),
			Color = palette.accent,
			Material = if i % 2 == 0 then Enum.Material.Neon else Enum.Material.SmoothPlastic,
			Transparency = if i % 2 == 0 then 0.15 else 0.05,
			CFrame = CFrame.new(f.x * r, f.y * r * 0.6, f.z * r)
				* CFrame.Angles(math.rad(i * 23), math.rad(i * 47), math.rad(i * 19)),
		})
	end
	addEyes(model, Vector3.new(0, 0.05 * scale, -0.04 * scale), r * 0.85)
	return core
end

-- Area 7: Biohazard -- Containment-Drum mit Bio-Bands und Visier-Augen.
function Archetypes.Biohazard(model, palette, scale)
	local r = 0.9 * scale
	local core = makePart(model, "PetCore", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(r * 1.9, r * 1.6, r * 1.6),
		Color = palette.main,
		Material = Enum.Material.Metal,
		CFrame = CFrame.Angles(0, 0, math.rad(90)),
	})
	for _, dy in ipairs({ -r * 0.6, r * 0.6 }) do
		makePart(model, "DrumBand", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(r * 0.20, r * 1.72, r * 1.72),
			Color = Color3.fromRGB(220, 188, 64),
			Material = Enum.Material.SmoothPlastic,
			CFrame = CFrame.new(0, dy, 0) * CFrame.Angles(0, 0, math.rad(90)),
		})
	end
	makePart(model, "DrumLidTop", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(r * 0.22, r * 1.65, r * 1.65),
		Color = palette.dark,
		Material = Enum.Material.Metal,
		CFrame = CFrame.new(0, r * 0.92, 0) * CFrame.Angles(0, 0, math.rad(90)),
	})
	makePart(model, "VisorL", {
		Shape = Enum.PartType.Block,
		Size = Vector3.new(r * 0.5, r * 0.18, r * 0.05),
		Color = palette.glow,
		Material = Enum.Material.Neon,
		CFrame = CFrame.new(-r * 0.4, r * 0.18, -r * 0.80),
	})
	makePart(model, "VisorR", {
		Shape = Enum.PartType.Block,
		Size = Vector3.new(r * 0.5, r * 0.18, r * 0.05),
		Color = palette.glow,
		Material = Enum.Material.Neon,
		CFrame = CFrame.new(r * 0.4, r * 0.18, -r * 0.80),
	})
	return core
end

-- Area 8: Shadow -- transluzenter Wisp mit Zyklopen-Auge.
function Archetypes.Shadow(model, palette, scale)
	local r = 1.0 * scale
	local core = makePart(model, "PetCore", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(r * 2.0, r * 1.8, r * 2.0),
		Color = palette.dark,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.42,
		CFrame = CFrame.new(),
	})
	makePart(model, "ShadowGlow", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(r * 0.7, r * 0.7, r * 0.7),
		Color = palette.glow,
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		CFrame = CFrame.new(),
	})
	makePart(model, "BigEye", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(r * 0.7, r * 0.7, r * 0.32),
		Color = palette.accent,
		Material = Enum.Material.Neon,
		CFrame = CFrame.new(0, 0, -r * 0.82),
	})
	makePart(model, "BigPup", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(r * 0.28, r * 0.28, r * 0.14),
		Color = Color3.fromRGB(10, 12, 16),
		Material = Enum.Material.SmoothPlastic,
		CFrame = CFrame.new(0, 0, -r * 1.00),
	})
	for i = 1, 3 do
		local size = r * (0.55 - i * 0.10)
		makePart(model, "WispTail" .. i, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(size, size * 0.85, size),
			Color = palette.dark,
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.5 + i * 0.1,
			CFrame = CFrame.new(0, -i * r * 0.08, r * (1.0 + i * 0.5)),
		})
	end
	return core
end

-- Area 9: Omega -- mehraeugige Orb mit Energie-Krone.
function Archetypes.Omega(model, palette, scale)
	local r = 1.0 * scale
	local core = makePart(model, "PetCore", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(r * 2.1, r * 2.1, r * 2.1),
		Color = palette.main,
		Material = Enum.Material.SmoothPlastic,
		CFrame = CFrame.new(),
	})
	local eyePositions = {
		Vector3.new(0, 0.55, -1.00),
		Vector3.new(-0.70, 0.30, -0.75),
		Vector3.new(0.70, 0.30, -0.75),
		Vector3.new(-0.42, 0.72, -0.55),
		Vector3.new(0.42, 0.72, -0.55),
	}
	for i, ep in ipairs(eyePositions) do
		makePart(model, "OmegaEye" .. i, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(r * 0.30, r * 0.30, r * 0.16),
			Color = palette.accent,
			Material = Enum.Material.Neon,
			CFrame = CFrame.new(ep * r),
		})
		makePart(model, "OmegaPup" .. i, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(r * 0.12, r * 0.12, r * 0.08),
			Color = Color3.fromRGB(10, 12, 16),
			Material = Enum.Material.SmoothPlastic,
			CFrame = CFrame.new(ep * r * 1.08),
		})
	end
	for i = 1, 5 do
		local a = (i - 1) * math.pi * 2 / 5
		makePart(model, "OmegaCrown" .. i, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(r * 0.32, r * 0.32, r * 0.32),
			Color = palette.glow,
			Material = Enum.Material.Neon,
			Transparency = 0.12,
			CFrame = CFrame.new(math.cos(a) * r * 0.85, r * 1.25, math.sin(a) * r * 0.85),
		})
	end
	return core
end

-- Area 10: Containment -- versiegelter Glow-Kern mit Kaefig + Lock-Plates.
function Archetypes.Containment(model, palette, scale)
	local r = 0.95 * scale
	local core = makePart(model, "PetCore", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(r * 1.6, r * 1.6, r * 1.6),
		Color = palette.glow,
		Material = Enum.Material.Neon,
		Transparency = 0.18,
		CFrame = CFrame.new(),
	})
	local plates = {
		Vector3.new(0, 1, 0),
		Vector3.new(0.86, 0, 0.5),
		Vector3.new(-0.86, 0, 0.5),
		Vector3.new(0, 0, -1),
	}
	for i, axis in ipairs(plates) do
		makePart(model, "LockPlate" .. i, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(r * 1.1, r * 0.45, r * 1.1),
			Color = palette.dark,
			Material = Enum.Material.Metal,
			CFrame = CFrame.new(axis * r * 0.55) * CFrame.lookAt(Vector3.new(0, 0, 0), axis),
		})
	end
	for i = 1, 4 do
		local a = (i - 1) * math.pi / 2
		makePart(model, "CageBar" .. i, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(r * 2.3, r * 0.12, r * 0.12),
			Color = palette.dark,
			Material = Enum.Material.Metal,
			CFrame = CFrame.Angles(0, a, 0) * CFrame.Angles(0, 0, math.rad(90)),
		})
	end
	addEyes(model, Vector3.new(0, 0, 0), r * 0.95)
	return core
end

-- =====================================================================
-- RARITY-LAYERS: stapeln cumulative Glanz-Elemente auf den Archetyp.
-- =====================================================================
local function applyRarityLayers(model: Model, core: Part, rarity: string, palette, scale: number)
	local rank = RarityRank[rarity] or 1

	-- Uncommon+: zwei Antennen mit Glow-Spitzen (klare Silhouette-Aenderung).
	if rank >= 2 then
		for _, side in ipairs({ -1, 1 }) do
			makePart(model, "Antenna" .. side, {
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.55 * scale, 0.12 * scale, 0.12 * scale),
				Color = palette.accent,
				Material = Enum.Material.SmoothPlastic,
				CFrame = CFrame.new(side * 0.55 * scale, 1.0 * scale, 0) * CFrame.Angles(0, 0, math.rad(78 * side)),
			})
			makePart(model, "AntennaTip" .. side, {
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(0.22 * scale, 0.22 * scale, 0.22 * scale),
				Color = palette.glow,
				Material = Enum.Material.Neon,
				CFrame = CFrame.new(side * 0.78 * scale, 1.25 * scale, 0),
			})
		end
	end

	-- Rare+: zwei Orbiter um den Koerper.
	if rank >= 3 then
		for i = 1, 2 do
			local a = (i - 1) * math.pi + math.pi / 4
			makePart(model, "Orbiter" .. i, {
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(0.34 * scale, 0.34 * scale, 0.34 * scale),
				Color = palette.soft,
				Material = Enum.Material.Neon,
				Transparency = 0.18,
				CFrame = CFrame.new(math.cos(a) * 1.45 * scale, 0.35 * scale, math.sin(a) * 1.45 * scale),
			})
		end
	end

	-- Epic+: Trim-Platten + weiches Point-Light.
	if rank >= 4 then
		for i = 1, 3 do
			local a = (i - 1) * math.pi * 2 / 3 + math.rad(30)
			makePart(model, "TrimPlate" .. i, {
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(0.55 * scale, 0.18 * scale, 0.78 * scale),
				Color = palette.dark,
				Material = Enum.Material.Metal,
				CFrame = CFrame.new(math.cos(a) * 0.95 * scale, 0.05 * scale, math.sin(a) * 0.95 * scale)
					* CFrame.Angles(0, -a + math.rad(90), 0),
			})
		end
		local light = Instance.new("PointLight")
		light.Name = "RarityLight"
		light.Color = palette.main
		light.Brightness = 0.55
		light.Range = 9
		light.Parent = core
	end

	-- Legendary+: Halo + Funken-Aura + staerkeres Licht.
	if rank >= 5 then
		makePart(model, "Halo", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.12 * scale, 2.5 * scale, 2.5 * scale),
			Color = palette.glow,
			Material = Enum.Material.Neon,
			Transparency = 0.45,
			CFrame = CFrame.new(0, 1.45 * scale, 0) * CFrame.Angles(0, 0, math.rad(90)),
		})
		local aura = Instance.new("ParticleEmitter")
		aura.Name = "RarePetAura"
		aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		aura.Color = ColorSequence.new(palette.main, palette.soft)
		aura.LightEmission = 0.42
		aura.LightInfluence = 0
		aura.Rate = 6
		aura.Lifetime = NumberRange.new(0.7, 1.1)
		aura.Speed = NumberRange.new(0.3, 0.9)
		aura.SpreadAngle = Vector2.new(65, 65)
		aura.Size = NumberSequence.new(0.30, 0.02)
		aura.Parent = core
		local light = core:FindFirstChild("RarityLight")
		if light and light:IsA("PointLight") then
			light.Brightness = 1.0
			light.Range = 12
		end
	end

	-- Mythic: Strahl + Orb-Crown + verstaerkte Effekte.
	if rank >= 6 then
		makePart(model, "MythicBeam", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(5.5 * scale, 0.35 * scale, 0.35 * scale),
			Color = palette.glow,
			Material = Enum.Material.Neon,
			Transparency = 0.62,
			CFrame = CFrame.new(0, 2.7 * scale, 0) * CFrame.Angles(0, 0, math.rad(90)),
		})
		for i = 1, 4 do
			local a = (i - 1) * math.pi * 2 / 4
			makePart(model, "MythicCrown" .. i, {
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(0.36 * scale, 0.36 * scale, 0.36 * scale),
				Color = palette.glow,
				Material = Enum.Material.Neon,
				Transparency = 0.12,
				CFrame = CFrame.new(math.cos(a) * 0.65 * scale, 1.55 * scale, math.sin(a) * 0.65 * scale),
			})
		end
		local aura = core:FindFirstChild("RarePetAura")
		if aura and aura:IsA("ParticleEmitter") then
			aura.Rate = 12
			aura.Size = NumberSequence.new(0.36, 0.02)
			aura.Speed = NumberRange.new(0.4, 1.1)
		end
		local light = core:FindFirstChild("RarityLight")
		if light and light:IsA("PointLight") then
			light.Brightness = 1.4
			light.Range = 16
		end
	end
end

-- Rarity-basiertes Groessen-Scaling (Mythic ist klar groesser als Common).
local SCALE_BY_RANK = { 1.00, 1.06, 1.12, 1.18, 1.26, 1.36 }

-- Liefert auch Metadaten zurueck, die der Caller (PetService) fuer
-- Bewegungs-Tuning / Label-Farbe nutzen kann -> alle Visual-Konstanten
-- bleiben in diesem Modul.
function PetVisualBuilder.build(model: Model, def): { core: Part, palette: any, scale: number, rank: number }
	local rarity = def.rarity or "Common"
	local rank = RarityRank[rarity] or 1
	local archetypeKey = ArchetypeByArea[def.areaIndex or 0] or "Bacteria"
	local archetypeFn = Archetypes[archetypeKey] or Archetypes.Bacteria

	local palette = makePalette(rarity, def.eggTier)
	local scale = SCALE_BY_RANK[rank] or 1.0

	local core = archetypeFn(model, palette, scale)
	model.PrimaryPart = core

	applyRarityLayers(model, core, rarity, palette, scale)

	model:SetAttribute("Archetype", archetypeKey)
	model:SetAttribute("Rarity", rarity)
	model:SetAttribute("RarityRank", rank)
	model:SetAttribute("Scale", scale)

	return { core = core, palette = palette, scale = scale, rank = rank }
end

function PetVisualBuilder.getPalette(rarity: string, tier: string?)
	return makePalette(rarity, tier)
end

function PetVisualBuilder.getRank(rarity: string?): number
	return rarity and (RarityRank[rarity] or 1) or 1
end

function PetVisualBuilder.getArchetype(areaIndex: number?): string
	return ArchetypeByArea[areaIndex or 0] or "Bacteria"
end

return PetVisualBuilder
