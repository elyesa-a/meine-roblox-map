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
	{ id = "Shop",     icon = "$",   label = "Shop",     color = Theme.Colors.Pink },
	{ id = "Pets",     icon = "EGG", label = "Pets",     color = Theme.Colors.Blue },
	{ id = "Quests",   icon = "!",   label = "Zones",    color = Theme.Colors.Yellow },
	{ id = "Rebirth",  icon = "DNA", label = "Bosses",   color = Theme.Colors.Red },
	{ id = "Upgrades", icon = "UP",  label = "Upgrades", color = Theme.Colors.Green },
	{ id = "Settings", icon = "SET", label = "Settings", color = Theme.Colors.PanelMedium },
	{ id = "Auras",    icon = "FX",  label = "Auras",    color = Theme.Colors.Purple },
	{ id = "Title",    icon = "VIP", label = "Titles",   color = Theme.Colors.Yellow },
	{ id = "Daily",    icon = "DAY", label = "Daily",    color = Theme.Colors.Orange },
}

function LeftButtons.create(parent: ScreenGui, onClick: (string) -> ())
	local holder = Instance.new("Frame")
	holder.Name = "LeftButtons"
	holder.AnchorPoint = Vector2.new(0, 0.5)
	holder.Position = UDim2.new(0, 16, 0.5, 0)
	holder.Size = UDim2.new(0, 132, 0, #ENTRIES * 48 + 18)
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
		button.Size = UDim2.new(0, 112, 0, 42)
		button.Text = ""
		Theme.applyButtonStyle(button, entry.color)
		button.BackgroundColor3 = Color3.fromRGB(31, 38, 52)
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

		local iconFrame = Instance.new("Frame")
		iconFrame.Name = "IconSlot"
		iconFrame.AnchorPoint = Vector2.new(0, 0.5)
		iconFrame.Position = UDim2.new(0, 10, 0.5, 0)
		iconFrame.Size = UDim2.new(0, 26, 0, 26)
		iconFrame.BackgroundColor3 = entry.color
		iconFrame.BackgroundTransparency = 0.12
		iconFrame.BorderSizePixel = 0
		iconFrame.Parent = button
		local iconCorner = Instance.new("UICorner")
		iconCorner.CornerRadius = UDim.new(0, 8)
		iconCorner.Parent = iconFrame

		local iconLabel = Instance.new("TextLabel")
		iconLabel.Name = "IconText"
		iconLabel.Size = UDim2.fromScale(1, 1)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Font = Enum.Font.GothamBlack
		iconLabel.Text = entry.icon
		iconLabel.TextSize = if #entry.icon <= 1 then 17 else 10
		iconLabel.TextScaled = false
		iconLabel.TextColor3 = Theme.Colors.White
		iconLabel.TextStrokeColor3 = Theme.Colors.Black
		iconLabel.TextStrokeTransparency = 0
		iconLabel.Parent = iconFrame

		local textLabel = Instance.new("TextLabel")
		textLabel.Name = "ButtonLabel"
		textLabel.AnchorPoint = Vector2.new(0, 0.5)
		textLabel.Position = UDim2.new(0, 44, 0.5, 0)
		textLabel.Size = UDim2.new(1, -50, 1, -8)
		textLabel.BackgroundTransparency = 1
		textLabel.Font = Theme.Font
		textLabel.Text = entry.label
		textLabel.TextXAlignment = Enum.TextXAlignment.Left
		textLabel.TextSize = 15
		textLabel.TextScaled = false
		textLabel.TextColor3 = Theme.Colors.White
		textLabel.TextStrokeColor3 = Theme.Colors.Black
		textLabel.TextStrokeTransparency = 0
		textLabel.Parent = button

		button.MouseButton1Click:Connect(function()
			UIAnimator.buttonPunch(button)
			onClick(entry.id)
		end)
	end

	return holder
end

return LeftButtons
