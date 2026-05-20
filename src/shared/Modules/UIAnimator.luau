--!strict
-- Kleine TweenService-Helfer fuer das UI: ButtonPunch, FadeIn/FadeOut, FloatText.

local TweenService = game:GetService("TweenService")

local UIAnimator = {}

-- Oeffnet ein Fenster mit Scale-Bounce: Backdrop fade-in, Root von 0.7 auf 1.
function UIAnimator.framePopIn(backdrop: GuiObject, root: GuiObject)
	backdrop.Visible = true
	backdrop.BackgroundTransparency = 1
	TweenService:Create(
		backdrop,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0.5 }
	):Play()

	local targetSize = root.Size
	root.Size = UDim2.new(
		targetSize.X.Scale,
		math.floor(targetSize.X.Offset * 0.7),
		targetSize.Y.Scale,
		math.floor(targetSize.Y.Offset * 0.7)
	)
	TweenService:Create(
		root,
		TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = targetSize }
	):Play()
end

-- Schliesst ein Fenster mit Scale-Down + Fade-Out.
function UIAnimator.framePopOut(backdrop: GuiObject, root: GuiObject)
	local startSize = root.Size
	local shrunk = UDim2.new(
		startSize.X.Scale,
		math.floor(startSize.X.Offset * 0.85),
		startSize.Y.Scale,
		math.floor(startSize.Y.Offset * 0.85)
	)
	TweenService:Create(
		root,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = shrunk }
	):Play()

	local fade = TweenService:Create(
		backdrop,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 }
	)
	fade:Play()
	fade.Completed:Connect(function()
		backdrop.Visible = false
		root.Size = startSize -- Original wiederherstellen, damit naechstes Oeffnen sauber laeuft.
	end)
end

function UIAnimator.buttonPunch(gui: GuiObject)
	-- Ausgangsgroesse EINMALIG merken. Sonst liest ein schneller Folgeklick die
	-- bereits vergroesserte Groesse eines noch laufenden Tweens als "Original"
	-- und der Button waechst bei jedem Druck weiter.
	local original = gui:GetAttribute("PunchBaseSize") :: UDim2?
	if original == nil then
		original = gui.Size
		gui:SetAttribute("PunchBaseSize", original)
	end

	-- Laeuft schon ein Punch? Dann nicht stapeln -- der Klick zaehlt trotzdem,
	-- nur die Animation wird nicht neu ausgeloest.
	if gui:GetAttribute("Punching") then
		return
	end
	gui:SetAttribute("Punching", true)

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
	downTween.Completed:Connect(function()
		gui.Size = original -- exakt auf Ausgangsgroesse zuruecksetzen
		gui:SetAttribute("Punching", false)
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
	label.Name = "FloatingText"
	label.Text = text
	label.Font = Enum.Font.GothamBold
	label.TextSize = 30
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.15
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
