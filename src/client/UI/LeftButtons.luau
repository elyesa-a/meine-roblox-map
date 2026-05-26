--!strict
-- Linke vertikale Button-Leiste: kompakte HUD-Navigation fuer Menues ohne
-- eigene Spawn-Station.

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

-- Temporary TextLabel placeholders only. Swap IconPlaceholder for ImageLabel
-- later when real rbxassetid icons are ready.
local ENTRIES: { Entry } = {
	{ id = "Pets",     icon = "EGG", label = "Pets",     color = Color3.fromRGB(80, 190, 255) },
	{ id = "Teleport", icon = "TP",  label = "Teleport", color = Color3.fromRGB(70, 255, 135) },
	{ id = "Quests",   icon = "!",   label = "Quests",   color = Color3.fromRGB(255, 225, 60) },
	{ id = "Rebirth",  icon = "DNA", label = "Rebirth",  color = Color3.fromRGB(255, 90, 90) },
	{ id = "Settings", icon = "⚙",   label = "Settings", color = Color3.fromRGB(120, 170, 255) },
	{ id = "Title",    icon = "VIP", label = "Titles",   color = Color3.fromRGB(255, 205, 58) },
}

local BUTTON_HEIGHT = 54
local BUTTON_GAP = 12

local function addGradient(gui: GuiObject, color: Color3)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color:Lerp(Color3.fromRGB(255, 255, 255), 0.18)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(30, 42, 68)),
		ColorSequenceKeypoint.new(1, color:Lerp(Color3.fromRGB(0, 0, 0), 0.38)),
	})
	gradient.Rotation = 90
	gradient.Parent = gui
	return gradient
end

function LeftButtons.create(parent: ScreenGui, onClick: (string) -> ())
	local holder = Instance.new("Frame")
	holder.Name = "LeftButtons"
	holder.AnchorPoint = Vector2.new(0, 0.5)
	holder.Position = UDim2.new(0, 18, 0.5, 6)
	holder.Size = UDim2.new(0, 150, 0, #ENTRIES * BUTTON_HEIGHT + (#ENTRIES - 1) * BUTTON_GAP + 24)
	holder.BackgroundColor3 = Color3.fromRGB(17, 25, 48)
	holder.BackgroundTransparency = 0.04
	holder.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 22)
	corner.Parent = holder

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(55, 225, 255)
	stroke.Thickness = 3
	stroke.Transparency = 0.12
	stroke.Parent = holder
	addGradient(holder, Color3.fromRGB(62, 170, 255))

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, BUTTON_GAP)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = holder

	local activeButton: TextButton? = nil
	local activeAccent: Frame? = nil

	local function setActive(button: TextButton, accent: Frame, color: Color3)
		if activeButton and activeButton ~= button then
			TweenService:Create(activeButton, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(32, 42, 68) }):Play()
			local oldStroke = activeButton:FindFirstChildOfClass("UIStroke")
			if oldStroke then
				oldStroke.Color = Color3.fromRGB(70, 220, 255)
				oldStroke.Transparency = 0.28
				oldStroke.Thickness = 2.4
			end
		end
		if activeAccent and activeAccent ~= accent then
			TweenService:Create(activeAccent, TweenInfo.new(0.12), { Size = UDim2.new(0, 5, 1, -12) }):Play()
		end
		activeButton = button
		activeAccent = accent
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = color:Lerp(Color3.fromRGB(24, 30, 48), 0.55) }):Play()
		TweenService:Create(accent, TweenInfo.new(0.12), { Size = UDim2.new(0, 9, 1, -8) }):Play()
		local strokeObj = button:FindFirstChildOfClass("UIStroke")
		if strokeObj then
			strokeObj.Color = color
			strokeObj.Transparency = 0.04
			strokeObj.Thickness = 3
		end
	end

	for _, entry in ipairs(ENTRIES) do
		local button = Instance.new("TextButton")
		button.Name = entry.id .. "Button"
		button.Size = UDim2.new(0, 128, 0, BUTTON_HEIGHT)
		button.Text = ""
		Theme.applyButtonStyle(button, entry.color)
		button.BackgroundColor3 = Color3.fromRGB(32, 42, 68)
		addGradient(button, entry.color)
		local buttonStroke = button:FindFirstChildOfClass("UIStroke")
		if buttonStroke then
			buttonStroke.Color = entry.color
			buttonStroke.Thickness = 2.4
			buttonStroke.Transparency = 0.22
		end
		button.Parent = holder

		local scale = Instance.new("UIScale")
		scale.Name = "HoverScale"
		scale.Parent = button

		local accent = Instance.new("Frame")
		accent.Name = "Accent"
		accent.AnchorPoint = Vector2.new(0, 0.5)
		accent.Position = UDim2.new(0, 0, 0.5, 0)
		accent.Size = UDim2.new(0, 6, 1, -12)
		accent.BackgroundColor3 = entry.color
		accent.BorderSizePixel = 0
		accent.Parent = button
		local accentCorner = Instance.new("UICorner")
		accentCorner.CornerRadius = UDim.new(1, 0)
		accentCorner.Parent = accent

		local iconFrame = Instance.new("Frame")
		iconFrame.Name = "IconSlot"
		iconFrame.AnchorPoint = Vector2.new(0, 0.5)
		iconFrame.Position = UDim2.new(0, 13, 0.5, 0)
		iconFrame.Size = UDim2.new(0, 36, 0, 36)
		iconFrame.BackgroundColor3 = entry.color
		iconFrame.BackgroundTransparency = 0
		iconFrame.BorderSizePixel = 0
		iconFrame.Parent = button
		local iconCorner = Instance.new("UICorner")
		iconCorner.CornerRadius = UDim.new(0, 13)
		iconCorner.Parent = iconFrame
		local iconStroke = Instance.new("UIStroke")
		iconStroke.Color = Theme.Colors.White
		iconStroke.Thickness = 2
		iconStroke.Transparency = 0.35
		iconStroke.Parent = iconFrame
		addGradient(iconFrame, entry.color)

		local iconLabel = Instance.new("TextLabel")
		iconLabel.Name = "IconPlaceholder"
		iconLabel.Size = UDim2.fromScale(1, 1)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Font = Enum.Font.GothamBlack
		iconLabel.Text = entry.icon
		iconLabel.TextSize = if #entry.icon <= 1 then 22 else 12
		iconLabel.TextScaled = false
		iconLabel.TextColor3 = Theme.Colors.White
		iconLabel.TextStrokeColor3 = Theme.Colors.Black
		iconLabel.TextStrokeTransparency = 0
		iconLabel.Parent = iconFrame

		local textLabel = Instance.new("TextLabel")
		textLabel.Name = "ButtonLabel"
		textLabel.AnchorPoint = Vector2.new(0, 0.5)
		textLabel.Position = UDim2.new(0, 58, 0.5, 0)
		textLabel.Size = UDim2.new(1, -62, 1, -8)
		textLabel.BackgroundTransparency = 1
		textLabel.Font = Theme.Font
		textLabel.Text = entry.label
		textLabel.TextXAlignment = Enum.TextXAlignment.Left
		textLabel.TextSize = 15
		textLabel.TextScaled = false
		textLabel.TextColor3 = Theme.Colors.White
		textLabel.TextStrokeColor3 = Theme.Colors.Black
		textLabel.TextStrokeTransparency = 0.16
		textLabel.Parent = button

		button.MouseEnter:Connect(function()
			if activeButton ~= button then
				TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = entry.color:Lerp(Color3.fromRGB(32, 42, 68), 0.52) }):Play()
			end
			TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.05 }):Play()
		end)
		button.MouseLeave:Connect(function()
			if activeButton ~= button then
				TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(32, 42, 68) }):Play()
			end
			TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
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
