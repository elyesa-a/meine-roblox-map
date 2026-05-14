--!strict
-- Auren-Definitionen: ID, Multiplikator, DNA-Preis, Partikel-Farben.
-- VFX-Defaults: Sparkle-Texture mit Aura-Farbe; Rainbow nutzt ColorSequence.

export type AuraDef = {
	id: string,
	displayName: string,
	multiplier: number,
	priceDna: number,
	color: Color3,
	-- Optional: ueberschreibt color durch eine Gradient-Sequence (z.B. Rainbow).
	colorSequence: ColorSequence?,
}

local AuraConfig = {}

AuraConfig.Auras = {
	{ id = "Electric", displayName = "Elektro-Aura", multiplier = 1.25, priceDna = 25, color = Color3.fromRGB(120, 200, 255) },
	{ id = "Blizzard", displayName = "Blizzard-Aura", multiplier = 1.5, priceDna = 100, color = Color3.fromRGB(180, 230, 255) },
	{ id = "Purple", displayName = "Purpur-Aura", multiplier = 1.75, priceDna = 250, color = Color3.fromRGB(200, 120, 255) },
	{ id = "Poison", displayName = "Gift-Aura", multiplier = 2.0, priceDna = 500, color = Color3.fromRGB(120, 255, 120) },
	{ id = "Magma", displayName = "Magma-Aura", multiplier = 3.0, priceDna = 2500, color = Color3.fromRGB(255, 120, 60) },
	{ id = "Glitch", displayName = "Glitch-Aura", multiplier = 5.0, priceDna = 10000, color = Color3.fromRGB(255, 80, 200) },
	{
		id = "Rainbow",
		displayName = "Regenbogen-Aura",
		multiplier = 9.99,
		priceDna = 50000,
		color = Color3.fromRGB(255, 255, 255),
		colorSequence = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 80, 80)),
			ColorSequenceKeypoint.new(0.20, Color3.fromRGB(255, 200, 80)),
			ColorSequenceKeypoint.new(0.40, Color3.fromRGB(120, 255, 120)),
			ColorSequenceKeypoint.new(0.60, Color3.fromRGB(80, 200, 255)),
			ColorSequenceKeypoint.new(0.80, Color3.fromRGB(180, 120, 255)),
			ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 80, 200)),
		}),
	},
}

function AuraConfig.getById(id: string): AuraDef?
	for _, def in ipairs(AuraConfig.Auras) do
		if def.id == id then
			return def :: AuraDef
		end
	end
	return nil
end

return AuraConfig
