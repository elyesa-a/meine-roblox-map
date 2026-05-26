--!strict
-- Zentrale Farb/Schrift-Werte fuer das gesamte Simulator-UI.

local Theme = {}

Theme.Colors = {
	Green = Color3.fromRGB(55, 255, 120),
	Red = Color3.fromRGB(255, 80, 82),
	Blue = Color3.fromRGB(42, 178, 255),
	Pink = Color3.fromRGB(255, 98, 196),
	Purple = Color3.fromRGB(176, 94, 255),
	Orange = Color3.fromRGB(255, 168, 46),
	Yellow = Color3.fromRGB(255, 224, 44),
	Cyan = Color3.fromRGB(36, 235, 255),
	Lime = Color3.fromRGB(130, 255, 64),
	Gold = Color3.fromRGB(255, 205, 58),
	White = Color3.fromRGB(255, 255, 255),
	Black = Color3.fromRGB(0, 0, 0),
	PanelDark = Color3.fromRGB(16, 20, 34),
	PanelMedium = Color3.fromRGB(30, 38, 62),
	PanelBright = Color3.fromRGB(42, 55, 88),
	DimBackdrop = Color3.fromRGB(0, 0, 0),
}

Theme.Font = Enum.Font.GothamBlack
Theme.BodyFont = Enum.Font.GothamBold
Theme.StrokeThickness = 3
Theme.CornerRadius = UDim.new(0, 18)

local function addGradient(gui: GuiObject, topColor: Color3, bottomColor: Color3, rotation: number?)
	local gradient = gui:FindFirstChildOfClass("UIGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Parent = gui
	end
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, topColor),
		ColorSequenceKeypoint.new(1, bottomColor),
	})
	gradient.Rotation = rotation or 90
	return gradient
end

function Theme.applyGradient(gui: GuiObject, accent: Color3)
	return addGradient(gui, accent:Lerp(Theme.Colors.White, 0.12), accent:Lerp(Theme.Colors.Black, 0.35), 90)
end

-- Helfer: standardisierten Button erzeugen.
function Theme.applyButtonStyle(button: GuiButton, color: Color3)
	button.BackgroundColor3 = color:Lerp(Color3.fromRGB(18, 22, 34), 0.12)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Font = Theme.Font
	button.TextColor3 = Theme.Colors.White
	button.TextStrokeColor3 = Theme.Colors.Black
	button.TextStrokeTransparency = 0.12
	button.TextScaled = true

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius
	corner.Parent = button

	addGradient(button, color:Lerp(Theme.Colors.White, 0.1), color:Lerp(Theme.Colors.Black, 0.25), 90)

	local stroke = Instance.new("UIStroke")
	stroke.Color = color:Lerp(Theme.Colors.White, 0.15)
	stroke.Thickness = Theme.StrokeThickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
end

function Theme.applyPanelStyle(frame: GuiObject, color: Color3?)
	frame.BackgroundColor3 = color or Theme.Colors.PanelDark
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Cyan
	stroke.Thickness = Theme.StrokeThickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	addGradient(frame, (color or Theme.Colors.PanelDark):Lerp(Theme.Colors.White, 0.08), Theme.Colors.PanelDark, 90)
end

function Theme.applyLabelStyle(label: TextLabel)
	label.BackgroundTransparency = 1
	label.Font = Theme.Font
	label.TextColor3 = Theme.Colors.White
	label.TextStrokeColor3 = Theme.Colors.Black
	label.TextStrokeTransparency = 0.08
	label.TextScaled = true
end

return Theme
