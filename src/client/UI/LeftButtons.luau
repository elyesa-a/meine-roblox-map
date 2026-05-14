--!strict
-- Linke vertikale Button-Leiste: Rebirth, Titel, Pets, Schub, Auras, Settings.

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
	{ id = "Rebirth",  label = "WIEDERGEBURT", color = Theme.Colors.Red },
	{ id = "Title",    label = "TITEL",         color = Theme.Colors.Yellow },
	{ id = "Pets",     label = "PETS",          color = Theme.Colors.Blue },
	{ id = "Upgrades", label = "SCHUB",         color = Theme.Colors.Green },
	{ id = "Auras",    label = "AUREN",         color = Theme.Colors.Purple },
	{ id = "Settings", label = "EINSTELLUNGEN", color = Theme.Colors.Pink },
}

function LeftButtons.create(parent: ScreenGui, onClick: (string) -> ())
	local holder = Instance.new("Frame")
	holder.Name = "LeftButtons"
	holder.AnchorPoint = Vector2.new(0, 0.5)
	holder.Position = UDim2.new(0, 16, 0.5, 0)
	holder.Size = UDim2.new(0, 92, 0, 6 * 76)
	holder.BackgroundTransparency = 1
	holder.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 8)
	layout.Parent = holder

	for _, entry in ipairs(ENTRIES) do
		local button = Instance.new("TextButton")
		button.Name = entry.id .. "Button"
		button.Size = UDim2.new(0, 84, 0, 68)
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
