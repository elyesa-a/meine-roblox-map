--!strict
-- Shared premium virus-lab styling helpers for modal UI windows.

local TweenService = game:GetService("TweenService")

local LabTheme = {}

LabTheme.Colors = {
	Base = Color3.fromRGB(8, 12, 18),
	Panel = Color3.fromRGB(12, 18, 28),
	Panel2 = Color3.fromRGB(18, 26, 38),
	Card = Color3.fromRGB(20, 28, 40),
	CardMuted = Color3.fromRGB(14, 18, 26),
	Stroke = Color3.fromRGB(0, 210, 190),
	StrokeDark = Color3.fromRGB(0, 120, 115),
	Green = Color3.fromRGB(35, 220, 95),
	Toxic = Color3.fromRGB(80, 255, 120),
	Cyan = Color3.fromRGB(0, 190, 255),
	Blue = Color3.fromRGB(40, 120, 255),
	Gold = Color3.fromRGB(255, 220, 80),
	Amber = Color3.fromRGB(255, 190, 40),
	Red = Color3.fromRGB(255, 70, 75),
	Text = Color3.fromRGB(245, 248, 255),
	SubText = Color3.fromRGB(175, 185, 200),
	Muted = Color3.fromRGB(110, 120, 135),
}

local function ensureCorner(gui: GuiObject, radius: number)
	local corner = gui:FindFirstChildOfClass("UICorner")
	if not corner then
		corner = Instance.new("UICorner")
		corner.Parent = gui
	end
	corner.CornerRadius = UDim.new(0, radius)
end

local function ensureStroke(gui: GuiObject): UIStroke
	local stroke = gui:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Parent = gui
	end
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return stroke
end

function LabTheme.styleBackdrop(backdrop: Frame)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.46
end

function LabTheme.styleModal(root: Frame, accent: Color3?)
	root.BackgroundColor3 = LabTheme.Colors.Base
	root.BackgroundTransparency = 0.04
	root.BorderSizePixel = 0
	ensureCorner(root, 18)
	local stroke = ensureStroke(root)
	stroke.Color = accent or LabTheme.Colors.Stroke
	stroke.Thickness = 1.5
	stroke.Transparency = 0.18

	local gradient = root:FindFirstChildOfClass("UIGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Parent = root
	end
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(16, 24, 34)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(6, 10, 16)),
	})
	gradient.Rotation = 90
end

function LabTheme.styleScroll(scroll: ScrollingFrame)
	scroll.BackgroundColor3 = Color3.fromRGB(7, 11, 17)
	scroll.BackgroundTransparency = 0.06
	scroll.BorderSizePixel = 0
	scroll.ScrollBarImageColor3 = LabTheme.Colors.Stroke
	scroll.ScrollBarThickness = 6
	ensureCorner(scroll, 14)
	local stroke = ensureStroke(scroll)
	stroke.Color = Color3.fromRGB(55, 70, 82)
	stroke.Thickness = 1
	stroke.Transparency = 0.45
end

function LabTheme.styleCard(card: GuiObject, accent: Color3?, muted: boolean?)
	card.BackgroundColor3 = if muted then LabTheme.Colors.CardMuted else LabTheme.Colors.Card
	card.BackgroundTransparency = if muted then 0.14 else 0.04
	card.BorderSizePixel = 0
	ensureCorner(card, 14)
	local stroke = ensureStroke(card)
	stroke.Color = accent or Color3.fromRGB(60, 70, 85)
	stroke.Thickness = 1.15
	stroke.Transparency = if accent then 0.35 else 0.5
end

function LabTheme.styleButton(button: TextButton, accent: Color3?, enabled: boolean?)
	local isEnabled = enabled ~= false
	local color = accent or LabTheme.Colors.Green
	button.BackgroundColor3 = if isEnabled then color:Lerp(Color3.fromRGB(12, 18, 24), 0.16) else Color3.fromRGB(38, 45, 55)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextColor3 = if isEnabled then LabTheme.Colors.Text else LabTheme.Colors.Muted
	button.TextStrokeTransparency = 1
	ensureCorner(button, 10)
	local stroke = ensureStroke(button)
	stroke.Color = if isEnabled then color else Color3.fromRGB(70, 78, 88)
	stroke.Thickness = 1.1
	stroke.Transparency = if isEnabled then 0.25 else 0.52
end

function LabTheme.styleClose(button: TextButton)
	LabTheme.styleButton(button, LabTheme.Colors.Red, true)
	button.Text = "X"
	button.TextSize = 18
	button.TextScaled = false
end

function LabTheme.styleLabel(label: TextLabel, color: Color3?, size: number?, bold: boolean?)
	label.BackgroundTransparency = 1
	label.Font = if bold == false then Enum.Font.GothamMedium else Enum.Font.GothamBold
	label.TextColor3 = color or LabTheme.Colors.Text
	label.TextStrokeTransparency = 1
	label.TextSize = size or label.TextSize
	label.TextScaled = false
end

function LabTheme.bindButtonFeedback(button: TextButton, accent: Color3?)
	local color = accent or LabTheme.Colors.Green
	button.MouseEnter:Connect(function()
		if button.Active == false then
			return
		end
		TweenService:Create(button, TweenInfo.new(0.12), {
			BackgroundColor3 = color:Lerp(Color3.fromRGB(255, 255, 255), 0.08),
		}):Play()
	end)
	button.MouseLeave:Connect(function()
		if button.Active == false then
			return
		end
		TweenService:Create(button, TweenInfo.new(0.12), {
			BackgroundColor3 = color:Lerp(Color3.fromRGB(12, 18, 24), 0.16),
		}):Play()
	end)
end

return LabTheme
