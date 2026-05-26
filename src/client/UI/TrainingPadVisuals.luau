--!strict
-- Kleine lokale Optik fuer Trainingspads: ruhiger dunkler Gruen-Neonrand.
-- Reine Client-Visuals, keine Gameplay-Logik.

local Workspace = game:GetService("Workspace")

local TrainingPadVisuals = {}

type OrbitState = {
	model: Model,
	strips: { BasePart },
}

local started = false
local orbits: { [Model]: OrbitState } = {}
local TRAINING_LED_COLOR = Color3.fromRGB(18, 125, 55)
local TRAINING_LED_TRANSPARENCY = 0

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
		for _, strip in ipairs(orbits[model].strips) do
			if strip.Parent then
				strip.Color = TRAINING_LED_COLOR
				strip.Material = Enum.Material.Neon
				strip.Transparency = TRAINING_LED_TRANSPARENCY
				strip.CastShadow = false
			end
		end
		return
	end
	orbits[model] = {
		model = model,
		strips = collectStrips(model),
	}
	for _, strip in ipairs(orbits[model].strips) do
		if strip.Parent then
			strip.Color = TRAINING_LED_COLOR
			strip.Material = Enum.Material.Neon
			strip.Transparency = TRAINING_LED_TRANSPARENCY
			strip.CastShadow = false
		end
	end
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

	task.spawn(function()
		while started do
			task.wait(2)
			scanForOrbits()
			for model in pairs(orbits) do
				if not model.Parent then
					orbits[model] = nil
				end
			end
		end
	end)
end

return TrainingPadVisuals
