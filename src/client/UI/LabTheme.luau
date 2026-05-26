--!strict
-- Shared premium virus-lab styling helpers for modal UI windows.

local TweenService = game:GetService("TweenService")

local LabTheme = {}

LabTheme.Colors = {
	Base = Color3.fromRGB(12, 17, 32),
	Panel = Color3.fromRGB(18, 27, 48),
	Panel2 = Color3.fromRGB(28, 42, 72),
	Card = Color3.fromRGB(26, 38, 64),
	CardMuted = Color3.fromRGB(18, 24, 38),
	Stroke = Color3.fromRGB(34, 235, 255),
	StrokeDark = Color3.fromRGB(0, 145, 170),
	Green = Color3.fromRGB(55, 255, 120),
	Toxic = Color3.fromRGB(125, 255, 70),
	Cyan = Color3.fromRGB(36, 220, 255),
	Blue = Color3.fromRGB(58, 145, 255),
	Gold = Color3.fromRGB(255, 218, 65),
	Amber = Color3.fromRGB(255, 176, 48),
	Red = Color3.fromRGB(255, 82, 88),
	Text = Color3.fromRGB(245, 248, 255),
	SubText = Color3.fromRGB(205, 220, 235),
	Muted = Color3.fromRGB(135, 150, 170),
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
	root.BackgroundTransparency = 0.02
	root.BorderSizePixel = 0
	ensureCorner(root, 22)
	local stroke = ensureStroke(root)
	stroke.Color = accent or LabTheme.Colors.Stroke
	stroke.Thickness = 3
	stroke.Transparency = 0.08

	local gradient = root:FindFirstChildOfClass("UIGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Parent = root
	end
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(36, 54, 88)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(18, 27, 48)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 14, 26)),
	})
	gradient.Rotation = 90
end

function LabTheme.styleScroll(scroll: ScrollingFrame)
	scroll.BackgroundColor3 = Color3.fromRGB(7, 11, 17)
	scroll.BackgroundTransparency = 0.06
	scroll.BorderSizePixel = 0
	scroll.ScrollBarImageColor3 = LabTheme.Colors.Stroke
	scroll.ScrollBarThickness = 8
	ensureCorner(scroll, 16)
	local stroke = ensureStroke(scroll)
	stroke.Color = LabTheme.Colors.Cyan
	stroke.Thickness = 2
	stroke.Transparency = 0.32
end

function LabTheme.styleCard(card: GuiObject, accent: Color3?, muted: boolean?)
	card.BackgroundColor3 = if muted then LabTheme.Colors.CardMuted else LabTheme.Colors.Card
	card.BackgroundTransparency = if muted then 0.12 else 0.02
	card.BorderSizePixel = 0
	ensureCorner(card, 18)
	local stroke = ensureStroke(card)
	stroke.Color = accent or LabTheme.Colors.Stroke
	stroke.Thickness = if accent then 2.4 else 1.8
	stroke.Transparency = if accent then 0.14 else 0.36

	local gradient = card:FindFirstChildOfClass("UIGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Parent = card
	end
	local top = if accent then LabTheme.Colors.Card:Lerp(accent, 0.18) else Color3.fromRGB(32, 44, 72)
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, top),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 20, 34)),
	})
	gradient.Rotation = 90
end

function LabTheme.styleButton(button: TextButton, accent: Color3?, enabled: boolean?)
	local isEnabled = enabled ~= false
	local color = accent or LabTheme.Colors.Green
	button.BackgroundColor3 = if isEnabled then color:Lerp(Color3.fromRGB(32, 42, 62), 0.12) else Color3.fromRGB(72, 82, 102)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBlack
	button.TextColor3 = if isEnabled then LabTheme.Colors.Text else Color3.fromRGB(228, 235, 246)
	button.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	button.TextStrokeTransparency = if isEnabled then 0.1 else 0.22
	ensureCorner(button, 14)
	local stroke = ensureStroke(button)
	stroke.Color = if isEnabled then color:Lerp(Color3.fromRGB(255, 255, 255), 0.12) else Color3.fromRGB(150, 165, 188)
	stroke.Thickness = 2.4
	stroke.Transparency = if isEnabled then 0.06 else 0.2

	local gradient = button:FindFirstChildOfClass("UIGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Parent = button
	end
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color:Lerp(Color3.fromRGB(255, 255, 255), if isEnabled then 0.16 else 0.08)),
		ColorSequenceKeypoint.new(1, color:Lerp(Color3.fromRGB(0, 0, 0), if isEnabled then 0.24 else 0.38)),
	})
	gradient.Rotation = 90
end

function LabTheme.styleClose(button: TextButton)
	LabTheme.styleButton(button, LabTheme.Colors.Red, true)
	button.Text = "X"
	button.TextSize = 18
	button.TextScaled = false
end

function LabTheme.styleLabel(label: TextLabel, color: Color3?, size: number?, bold: boolean?)
	label.BackgroundTransparency = 1
	label.Font = if bold == false then Enum.Font.GothamBold else Enum.Font.GothamBlack
	label.TextColor3 = color or LabTheme.Colors.Text
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = if bold == false then 0.75 else 0.25
	label.TextSize = size or label.TextSize
	label.TextScaled = false
end

function LabTheme.bindHoverPopout(gui: GuiObject, hoverScale: number?)
	if gui:GetAttribute("HoverPopoutBound") == true then
		return
	end
	gui:SetAttribute("HoverPopoutBound", true)
	local scale = gui:FindFirstChild("HoverPopoutScale")
	if not scale or not scale:IsA("UIScale") then
		scale = Instance.new("UIScale")
		scale.Name = "HoverPopoutScale"
		scale.Parent = gui
	end
	scale.Scale = 1

	local targetScale = hoverScale or 1.035
	gui.MouseEnter:Connect(function()
		local stroke = gui:FindFirstChildOfClass("UIStroke")
		if stroke then
			gui:SetAttribute("HoverOriginalStrokeTransparency", stroke.Transparency)
		end
		TweenService:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = targetScale,
		}):Play()
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.14), {
				Transparency = math.max(0.08, stroke.Transparency - 0.16),
			}):Play()
		end
	end)
	gui.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
		local stroke = gui:FindFirstChildOfClass("UIStroke")
		if stroke then
			local originalTransparency = gui:GetAttribute("HoverOriginalStrokeTransparency")
			TweenService:Create(stroke, TweenInfo.new(0.14), {
				Transparency = if type(originalTransparency) == "number" then originalTransparency else stroke.Transparency,
			}):Play()
		end
	end)
end

function LabTheme.bindButtonFeedback(button: TextButton, accent: Color3?)
	local color = accent or LabTheme.Colors.Green
	LabTheme.bindHoverPopout(button, 1.045)
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
