--!strict
-- Linke vertikale Button-Leiste: Rebirth, Titel, Pets, Schub, Auras, Daily,
-- Shop, Settings.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))

local LeftButtons = {}

type Entry = {
	id: string,
	icon: string,
	label: string,
	color: Color3,
}

local ENTRIES: { Entry } = {
	{ id = "Rebirth",  icon = "DNA", label = "REBIRTH",  color = Theme.Colors.Red },
	{ id = "Title",    icon = "VIP", label = "TITLES",   color = Theme.Colors.Yellow },
	{ id = "Pets",     icon = "EGG", label = "PETS",     color = Theme.Colors.Blue },
	{ id = "Upgrades", icon = "UP",  label = "SKILLS",   color = Theme.Colors.Green },
	{ id = "Auras",    icon = "FX",  label = "AURAS",    color = Theme.Colors.Purple },
	{ id = "Daily",    icon = "DAY", label = "DAILY",    color = Theme.Colors.Orange },
	{ id = "Quests",   icon = "!",   label = "QUESTS",   color = Theme.Colors.Yellow },
	{ id = "Shop",     icon = "$",   label = "SHOP",     color = Theme.Colors.Pink },
	{ id = "Settings", icon = "SET", label = "SETTINGS", color = Theme.Colors.PanelMedium },
}

function LeftButtons.create(parent: ScreenGui, onClick: (string) -> ())
	local holder = Instance.new("Frame")
	holder.Name = "LeftButtons"
	holder.AnchorPoint = Vector2.new(0, 0.5)
	holder.Position = UDim2.new(0, 16, 0.5, 0)
	holder.Size = UDim2.new(0, 116, 0, #ENTRIES * 62 + 18)
	holder.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
	holder.BackgroundTransparency = 0.18
	holder.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = holder

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(90, 255, 220)
	stroke.Thickness = 2
	stroke.Transparency = 0.35
	stroke.Parent = holder

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = holder

	for _, entry in ipairs(ENTRIES) do
		local button = Instance.new("TextButton")
		button.Name = entry.id .. "Button"
		button.Size = UDim2.new(0, 96, 0, 56)
		button.Text = entry.icon .. "\n" .. entry.label
		Theme.applyButtonStyle(button, entry.color)
		button.BackgroundColor3 = Color3.fromRGB(31, 38, 52)
		button.TextSize = 14
		button.TextScaled = false
		button.Parent = holder

		local accent = Instance.new("Frame")
		accent.Name = "Accent"
		accent.AnchorPoint = Vector2.new(0, 0.5)
		accent.Position = UDim2.new(0, 0, 0.5, 0)
		accent.Size = UDim2.new(0, 5, 1, -12)
		accent.BackgroundColor3 = entry.color
		accent.BorderSizePixel = 0
		accent.Parent = button
		local accentCorner = Instance.new("UICorner")
		accentCorner.CornerRadius = UDim.new(1, 0)
		accentCorner.Parent = accent

		button.MouseButton1Click:Connect(function()
			UIAnimator.buttonPunch(button)
			onClick(entry.id)
		end)
	end

	return holder
end

return LeftButtons
