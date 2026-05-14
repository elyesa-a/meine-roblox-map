--!strict
-- Kleine TweenService-Helfer fuer das UI: ButtonPunch, FadeIn/FadeOut, FloatText.

local TweenService = game:GetService("TweenService")

local UIAnimator = {}

function UIAnimator.buttonPunch(gui: GuiObject)
	local original = gui.Size
	-- Wenn schon einmal getweened: keine kumulierten Effekte.
	-- Wir skalieren BEIDE Komponenten (Scale + Offset), damit der Effekt auch
	-- bei reinen Pixel-Buttons sichtbar ist.
	local enlarged = UDim2.new(
		original.X.Scale * 1.08,
		math.floor(original.X.Offset * 1.08),
		original.Y.Scale * 1.08,
		math.floor(original.Y.Offset * 1.08)
	)
	local upTween = TweenService:Create(
		gui,
		TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = enlarged }
	)
	local downTween = TweenService:Create(
		gui,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{ Size = original }
	)
	upTween:Play()
	upTween.Completed:Connect(function()
		downTween:Play()
	end)
end

function UIAnimator.fadeIn(gui: GuiObject, duration: number?)
	gui.Visible = true
	local dur = duration or 0.15
	-- BackgroundTransparency tweenen
	local startBg = gui.BackgroundTransparency
	gui.BackgroundTransparency = 1
	TweenService:Create(
		gui,
		TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = startBg }
	):Play()
end

function UIAnimator.fadeOut(gui: GuiObject, duration: number?)
	local dur = duration or 0.15
	local tween = TweenService:Create(
		gui,
		TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	)
	tween:Play()
	tween.Completed:Connect(function()
		gui.Visible = false
	end)
end

-- Erzeugt einen kurz aufsteigenden Text an einer Bildschirmposition.
function UIAnimator.floatText(parent: ScreenGui, text: string, anchorPos: UDim2, color: Color3)
	local label = Instance.new("TextLabel")
	label.Text = text
	label.Font = Enum.Font.GothamBold
	label.TextSize = 28
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromOffset(180, 40)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = anchorPos
	label.ZIndex = 50
	label.Parent = parent

	local endPos = UDim2.new(anchorPos.X.Scale, anchorPos.X.Offset, anchorPos.Y.Scale, anchorPos.Y.Offset - 80)
	local tween = TweenService:Create(
		label,
		TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = endPos, TextTransparency = 1, TextStrokeTransparency = 1 }
	)
	tween:Play()
	tween.Completed:Connect(function()
		label:Destroy()
	end)
end

return UIAnimator
