--!strict
-- Linke vertikale Button-Leiste: Rebirth, Titel, Pets, Schub, Auras, Daily,
-- Shop, Settings.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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
	{ id = "Auras",    icon = "FX",  label = "Auras",    color = Theme.Colors.Purple },
	{ id = "Daily",    icon = "DAY", label = "Daily",    color = Theme.Colors.Orange },
	{ id = "Pets",     icon = "EGG", label = "Pets",     color = Theme.Colors.Blue },
	{ id = "Quests",   icon = "!",   label = "Zones",    color = Theme.Colors.Yellow },
	{ id = "Rebirth",  icon = "DNA", label = "Bosses",   color = Theme.Colors.Red },
	{ id = "Settings", icon = "SET", label = "Settings", color = Theme.Colors.PanelMedium },
	{ id = "Shop",     icon = "$",   label = "Shop",     color = Theme.Colors.Pink },
	{ id = "Title",    icon = "VIP", label = "Titles",   color = Theme.Colors.Yellow },
	{ id = "Upgrades", icon = "UP",  label = "Upgrades", color = Theme.Colors.Green },
}

function LeftButtons.create(parent: ScreenGui, onClick: (string) -> ())
	local holder = Instance.new("Frame")
	holder.Name = "LeftButtons"
	holder.AnchorPoint = Vector2.new(0, 0.5)
	holder.Position = UDim2.new(0, 16, 0.5, 0)
	holder.Size = UDim2.new(0, 118, 0, #ENTRIES * 41 + 16)
	holder.BackgroundColor3 = Color3.fromRGB(9, 13, 20)
	holder.BackgroundTransparency = 0.18
	holder.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = holder

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(90, 255, 220)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.45
	stroke.Parent = holder

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 5)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = holder

	local activeButton: TextButton? = nil
	local activeAccent: Frame? = nil

	local function setActive(button: TextButton, accent: Frame, color: Color3)
		if activeButton and activeButton ~= button then
			TweenService:Create(activeButton, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(24, 31, 43) }):Play()
			local oldStroke = activeButton:FindFirstChildOfClass("UIStroke")
			if oldStroke then
				oldStroke.Color = Color3.fromRGB(56, 236, 207)
				oldStroke.Transparency = 0.75
				oldStroke.Thickness = 1
			end
		end
		if activeAccent and activeAccent ~= accent then
			TweenService:Create(activeAccent, TweenInfo.new(0.12), { Size = UDim2.new(0, 5, 1, -12) }):Play()
		end
		activeButton = button
		activeAccent = accent
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(30, 45, 58) }):Play()
		TweenService:Create(accent, TweenInfo.new(0.12), { Size = UDim2.new(0, 8, 1, -10) }):Play()
		local strokeObj = button:FindFirstChildOfClass("UIStroke")
		if strokeObj then
			strokeObj.Color = color
			strokeObj.Transparency = 0.2
			strokeObj.Thickness = 1.5
		end
	end

	for _, entry in ipairs(ENTRIES) do
		local button = Instance.new("TextButton")
		button.Name = entry.id .. "Button"
		button.Size = UDim2.new(0, 100, 0, 36)
		button.Text = ""
		Theme.applyButtonStyle(button, Color3.fromRGB(24, 31, 43))
		local buttonStroke = button:FindFirstChildOfClass("UIStroke")
		if buttonStroke then
			buttonStroke.Color = Color3.fromRGB(56, 236, 207)
			buttonStroke.Thickness = 1
			buttonStroke.Transparency = 0.75
		end
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
		iconFrame.Position = UDim2.new(0, 8, 0.5, 0)
		iconFrame.Size = UDim2.new(0, 23, 0, 23)
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
		iconLabel.TextSize = if #entry.icon <= 1 then 15 else 9
		iconLabel.TextScaled = false
		iconLabel.TextColor3 = Theme.Colors.White
		iconLabel.TextStrokeColor3 = Theme.Colors.Black
		iconLabel.TextStrokeTransparency = 0
		iconLabel.Parent = iconFrame

		local textLabel = Instance.new("TextLabel")
		textLabel.Name = "ButtonLabel"
		textLabel.AnchorPoint = Vector2.new(0, 0.5)
		textLabel.Position = UDim2.new(0, 38, 0.5, 0)
		textLabel.Size = UDim2.new(1, -42, 1, -8)
		textLabel.BackgroundTransparency = 1
		textLabel.Font = Theme.Font
		textLabel.Text = entry.label
		textLabel.TextXAlignment = Enum.TextXAlignment.Left
		textLabel.TextSize = 12
		textLabel.TextScaled = false
		textLabel.TextColor3 = Theme.Colors.White
		textLabel.TextStrokeTransparency = 1
		textLabel.Parent = button

		button.MouseEnter:Connect(function()
			if activeButton ~= button then
				TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(32, 40, 54) }):Play()
			end
		end)
		button.MouseLeave:Connect(function()
			if activeButton ~= button then
				TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(24, 31, 43) }):Play()
			end
		end)

		button.MouseButton1Click:Connect(function()
			UIAnimator.buttonPunch(button)
			setActive(button, accent, entry.color)
			onClick(entry.id)
		end)
	end

	return holder
end

return LeftButtons
