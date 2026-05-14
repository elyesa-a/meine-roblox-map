--!strict
-- Zentrale Farb/Schrift-Werte fuer das gesamte Simulator-UI.

local Theme = {}

Theme.Colors = {
	Green = Color3.fromRGB(25, 230, 110),
	Red = Color3.fromRGB(255, 59, 59),
	Blue = Color3.fromRGB(35, 166, 255),
	Pink = Color3.fromRGB(255, 79, 177),
	Purple = Color3.fromRGB(161, 72, 255),
	Orange = Color3.fromRGB(255, 154, 31),
	Yellow = Color3.fromRGB(255, 212, 25),
	White = Color3.fromRGB(255, 255, 255),
	Black = Color3.fromRGB(0, 0, 0),
	PanelDark = Color3.fromRGB(34, 34, 50),
	PanelMedium = Color3.fromRGB(48, 48, 70),
	DimBackdrop = Color3.fromRGB(0, 0, 0),
}

Theme.Font = Enum.Font.GothamBold
Theme.StrokeThickness = 3
Theme.CornerRadius = UDim.new(0, 12)

-- Helfer: standardisierten Button erzeugen.
function Theme.applyButtonStyle(button: GuiButton, color: Color3)
	button.BackgroundColor3 = color
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Font = Theme.Font
	button.TextColor3 = Theme.Colors.White
	button.TextStrokeColor3 = Theme.Colors.Black
	button.TextStrokeTransparency = 0
	button.TextScaled = true

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Black
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
	stroke.Color = Theme.Colors.Black
	stroke.Thickness = Theme.StrokeThickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
end

function Theme.applyLabelStyle(label: TextLabel)
	label.BackgroundTransparency = 1
	label.Font = Theme.Font
	label.TextColor3 = Theme.Colors.White
	label.TextStrokeColor3 = Theme.Colors.Black
	label.TextStrokeTransparency = 0
	label.TextScaled = true
end

return Theme
