--!strict
-- Linke vertikale Button-Leiste: Rebirth, Titel, Pets, Schub, Auras, Daily,
-- Shop, Settings.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))

local LeftButtons = {}

type Entry = {
	id: string,
	label: string,
	color: Color3,
}

local ENTRIES: { Entry } = {
	{ id = "Rebirth",  label = "REBIRTH",  color = Theme.Colors.Red },
	{ id = "Title",    label = "TITLES",   color = Theme.Colors.Yellow },
	{ id = "Pets",     label = "PETS",          color = Theme.Colors.Blue },
	{ id = "Upgrades", label = "SKILLS",        color = Theme.Colors.Green },
	{ id = "Auras",    label = "AURAS",         color = Theme.Colors.Purple },
	{ id = "Daily",    label = "DAILY",         color = Theme.Colors.Orange },
	{ id = "Quests",   label = "QUESTS",        color = Theme.Colors.Yellow },
	{ id = "Shop",     label = "SHOP",          color = Theme.Colors.Pink },
	{ id = "Settings", label = "SETTINGS", color = Theme.Colors.PanelMedium },
}

function LeftButtons.create(parent: ScreenGui, onClick: (string) -> ())
	local holder = Instance.new("Frame")
	holder.Name = "LeftButtons"
	holder.AnchorPoint = Vector2.new(0, 0.5)
	holder.Position = UDim2.new(0, 16, 0.5, 0)
	holder.Size = UDim2.new(0, 92, 0, #ENTRIES * 72)
	holder.BackgroundTransparency = 1
	holder.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 6)
	layout.Parent = holder

	for _, entry in ipairs(ENTRIES) do
		local button = Instance.new("TextButton")
		button.Name = entry.id .. "Button"
		button.Size = UDim2.new(0, 84, 0, 64)
		button.Text = entry.label
		Theme.applyButtonStyle(button, entry.color)
		button.TextSize = 16
		button.TextScaled = false
		button.Parent = holder

		button.MouseButton1Click:Connect(function()
			UIAnimator.buttonPunch(button)
			onClick(entry.id)
		end)
	end

	return holder
end

return LeftButtons
