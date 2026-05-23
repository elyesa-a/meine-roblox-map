--!strict
-- Kleine lokale Optik fuer Trainingspads: rot/gruene LED-Segmente bleiben
-- fest am Pad und das Lichtmuster laeuft langsam um den Rand.
-- Reine Client-Visuals, keine Gameplay-Logik.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TrainingPadVisuals = {}

type OrbitState = {
	model: Model,
	strips: { BasePart },
	phase: number,
	speed: number,
}

local started = false
local orbits: { [Model]: OrbitState } = {}
-- Lila Lichter: dunkles Lila <-> helles Magenta-Lila, damit die Welle
-- weiterhin sichtbar pulsiert, aber die Farbe komplett lila bleibt.
local LED_DARK = Color3.fromRGB(78, 22, 142)
local LED_BRIGHT = Color3.fromRGB(206, 118, 255)

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
	if orbits[model] then
		orbits[model].strips = collectStrips(model)
		return
	end
	local speedAttr = model:GetAttribute("FlowSpeed")
	local speed = if type(speedAttr) == "number" then speedAttr else 0.78
	orbits[model] = {
		model = model,
		strips = collectStrips(model),
		phase = 0,
		speed = speed,
	}
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
						local color = LED_DARK:Lerp(LED_BRIGHT, smoothBlend)
						strip.Color = color
						strip.Transparency = 0
					end
				end
			end
		end
	end)
end

return TrainingPadVisuals
