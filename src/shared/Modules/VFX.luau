--!strict
-- Server-/Shared-VFX-Helper. Spawnen kurzlebiger ParticleEmitter-Bursts an
-- bestehenden Parts (Workspace). Sichtbar fuer alle Spieler.

local Debris = game:GetService("Debris")

local VFX = {}

local function emitBurst(parent: BasePart, props: { [string]: any }, count: number, life: number)
	local att = Instance.new("Attachment")
	att.Parent = parent

	local emitter = Instance.new("ParticleEmitter")
	for k, v in pairs(props) do
		(emitter :: any)[k] = v
	end
	emitter.Enabled = false
	emitter.Parent = att

	emitter:Emit(count)
	Debris:AddItem(att, life)
end

-- Kleiner Power-Burst am Spieler-Charakter (bei Klick).
function VFX.spawnClickBurst(character: Model, color: Color3)
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end
	emitBurst(hrp, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(color),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(1, 0.1),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(0.3, 0.5),
		Speed = NumberRange.new(4, 8),
		SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360),
		LightEmission = 0.6,
	}, 8, 1.0)
end

-- Grosser Rebirth-Burst mit Schockwellen-Look.
function VFX.spawnRebirthBurst(character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end
	emitBurst(hrp, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 200, 80)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
		}),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 2),
			NumberSequenceKeypoint.new(1, 6),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(0.6, 1.0),
		Speed = NumberRange.new(20, 40),
		SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360),
		LightEmission = 1,
	}, 40, 1.5)

	-- Zusaetzliche Boden-Welle.
	emitBurst(hrp, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 180)),
		Size = NumberSequence.new(1.4, 0.2),
		Transparency = NumberSequence.new(0.1, 1),
		Lifetime = NumberRange.new(0.5, 0.8),
		Speed = NumberRange.new(10, 20),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 0.8,
	}, 60, 1.2)
end

-- Trainings-Burst am Bett, sichtbar fuer alle.
function VFX.spawnTrainingPulse(bedPart: BasePart, color: Color3)
	emitBurst(bedPart, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(color),
		Size = NumberSequence.new(0.8, 0.1),
		Transparency = NumberSequence.new(0.4, 1),
		Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(2, 5),
		SpreadAngle = Vector2.new(90, 90),
		LightEmission = 0.5,
		Rate = 0,
	}, 6, 0.9)
end

return VFX
