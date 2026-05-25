--!strict
-- Kleine lokale Optik fuer Trainingspads: die LED-Segmente am Rand pulsieren
-- in der Area-Farbe (gelesen vom Model-Attribut AccentColor, gesetzt vom
-- VirusLabBuilder). Reine Client-Visuals, keine Gameplay-Logik.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TrainingPadVisuals = {}

type OrbitState = {
	model: Model,
	strips: { BasePart },
	phase: number,
	speed: number,
	dark: Color3,
	bright: Color3,
}

local started = false
local orbits: { [Model]: OrbitState } = {}
-- Fallback (falls Server kein AccentColor-Attribut gesetzt hat): neutrales Weiss.
local FALLBACK_DARK = Color3.fromRGB(40, 44, 52)
local FALLBACK_BRIGHT = Color3.fromRGB(220, 226, 232)

local function deriveColors(model: Model): (Color3, Color3)
	local accent = model:GetAttribute("AccentColor")
	if typeof(accent) ~= "Color3" then
		return FALLBACK_DARK, FALLBACK_BRIGHT
	end
	-- Dunkle Variante: stark zu Schwarz gemischt -> klare Pulse-Tiefe.
	-- Helle Variante: leicht zu Weiss aufgehellt -> Glow ohne Farbverlust.
	local dark = accent:Lerp(Color3.fromRGB(8, 10, 14), 0.65)
	local bright = accent:Lerp(Color3.fromRGB(252, 252, 252), 0.18)
	return dark, bright
end

local function collectStrips(model: Model): { BasePart }
	local strips = {}
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") and inst.Name == "TrainingLedStrip" then
			table.insert(strips, inst)
		end
	end
	table.sort(strips, function(a, b)
		local ai = a:GetAttribute("LedIndex")
		local bi = b:GetAttribute("LedIndex")
		return (if type(ai) == "number" then ai else 0) < (if type(bi) == "number" then bi else 0)
	end)
	return strips
end

local function registerOrbit(model: Model)
	local dark, bright = deriveColors(model)
	if orbits[model] then
		orbits[model].strips = collectStrips(model)
		orbits[model].dark = dark
		orbits[model].bright = bright
		return
	end
	local speedAttr = model:GetAttribute("FlowSpeed")
	local speed = if type(speedAttr) == "number" then speedAttr else 0.78
	orbits[model] = {
		model = model,
		strips = collectStrips(model),
		phase = 0,
		speed = speed,
		dark = dark,
		bright = bright,
	}
	model:GetAttributeChangedSignal("AccentColor"):Connect(function()
		local d, b = deriveColors(model)
		local state = orbits[model]
		if state then
			state.dark = d
			state.bright = b
		end
	end)
end

local function scanForOrbits()
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("Model") and inst.Name == "TrainPadLedOrbit" then
			registerOrbit(inst)
		end
	end
end

function TrainingPadVisuals.start()
	if started then
		return
	end
	started = true

	scanForOrbits()

	Workspace.DescendantAdded:Connect(function(inst)
		if inst:IsA("Model") and inst.Name == "TrainPadLedOrbit" then
			task.defer(registerOrbit, inst)
		end
	end)

	local scanAccum = 0
	RunService.RenderStepped:Connect(function(dt)
		scanAccum += dt
		if scanAccum >= 1 then
			scanAccum = 0
			scanForOrbits()
		end

		for model, state in pairs(orbits) do
			if not model.Parent then
				orbits[model] = nil
			else
				state.phase = (state.phase + dt * state.speed) % 24
				for index, strip in ipairs(state.strips) do
					if strip.Parent then
						local wave = math.sin((index * 0.86 - state.phase) * math.pi)
						local blend = (wave + 1) * 0.5
						local smoothBlend = blend * blend * (3 - 2 * blend)
						local color = state.dark:Lerp(state.bright, smoothBlend)
						strip.Color = color
						strip.Transparency = 0
					end
				end
			end
		end
	end)
end

return TrainingPadVisuals
