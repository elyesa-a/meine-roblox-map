--!strict
-- Rechte Seite: Boost-/Gamepass-Buttons (Phase 1: nur Platzhalter, deaktiviert).

local Theme = require(script.Parent:WaitForChild("Theme"))

local RightBoosts = {}

local ENTRIES = {
	{ label = "2X KRAFT",      color = Theme.Colors.Red },
	{ label = "2X DNA",        color = Theme.Colors.Blue },
	{ label = "2X GLUECK",     color = Theme.Colors.Yellow },
	{ label = "AUTO: AUS",     color = Theme.Colors.Pink },
	{ label = "GLITCH-PET",    color = Theme.Colors.Purple },
}

function RightBoosts.create(parent: ScreenGui)
	local holder = Instance.new("Frame")
	holder.Name = "RightBoosts"
	holder.AnchorPoint = Vector2.new(1, 0.5)
	holder.Position = UDim2.new(1, -16, 0.5, 0)
	holder.Size = UDim2.new(0, 110, 0, #ENTRIES * 72)
	holder.BackgroundTransparency = 1
	holder.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 8)
	layout.Parent = holder

	for _, entry in ipairs(ENTRIES) do
		local btn = Instance.new("TextButton")
		btn.Name = entry.label .. "Button"
		btn.Size = UDim2.new(0, 100, 0, 64)
		btn.Text = entry.label
		Theme.applyButtonStyle(btn, entry.color)
		btn.TextSize = 14
		btn.TextScaled = false
		btn.AutoButtonColor = false
		btn.Active = false
		btn.Parent = holder
	end

	return holder
end

return RightBoosts
