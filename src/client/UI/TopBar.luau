--!strict
-- Modernes Top-HUD: DNA, Power, Boost und kleiner Spin-Zugang.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))
local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))

local TopBar = {}

type Refs = {
	root: Frame,
	dnaLabel: TextLabel,
	powerLabel: TextLabel,
	boostLabel: TextLabel,
	spinButton: TextButton,
}

local function addCornerAndStroke(frame: GuiObject, color: Color3, thickness: number?, transparency: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness or 3
	stroke.Transparency = transparency or 0.08
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
end

local function addGradient(gui: GuiObject, accent: Color3)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, accent:Lerp(Color3.fromRGB(255, 255, 255), 0.16)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(25, 34, 58)),
		ColorSequenceKeypoint.new(1, accent:Lerp(Color3.fromRGB(0, 0, 0), 0.35)),
	})
	gradient.Rotation = 90
	gradient.Parent = gui
end

local function makeCapsule(parent: Frame, name: string, icon: string, labelText: string, accent: Color3, width: number?): TextLabel
	local capsule = Instance.new("Frame")
	capsule.Name = name
	capsule.Size = UDim2.new(0, width or 126, 0, 42)
	capsule.BackgroundColor3 = accent
	capsule.BackgroundTransparency = 0
	capsule.BorderSizePixel = 0
	addCornerAndStroke(capsule, accent:Lerp(Color3.fromRGB(255, 255, 255), 0.12), 3, 0.06)
	addGradient(capsule, accent)
	capsule.Parent = parent

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.fromScale(0.5, 0.56)
	shadow.Size = UDim2.new(1, 6, 1, 6)
	shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	shadow.BackgroundTransparency = 0.72
	shadow.BorderSizePixel = 0
	shadow.ZIndex = capsule.ZIndex - 1
	shadow.Parent = capsule
	local shadowCorner = Instance.new("UICorner")
	shadowCorner.CornerRadius = UDim.new(1, 0)
	shadowCorner.Parent = shadow

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.Position = UDim2.new(0, 7, 0.5, -15)
	iconLabel.Size = UDim2.new(0, 32, 0, 30)
	iconLabel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	iconLabel.BackgroundTransparency = 0.82
	iconLabel.BorderSizePixel = 0
	iconLabel.Font = Enum.Font.GothamBlack
	iconLabel.Text = icon
	iconLabel.TextColor3 = Theme.Colors.White
	iconLabel.TextSize = if #icon <= 2 then 15 else 10
	iconLabel.TextScaled = false
	iconLabel.TextStrokeColor3 = Theme.Colors.Black
	iconLabel.TextStrokeTransparency = 0.15
	iconLabel.Parent = capsule
	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(1, 0)
	iconCorner.Parent = iconLabel

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Position = UDim2.new(0, 45, 0, 4)
	label.Size = UDim2.new(1, -50, 0, 13)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.Text = labelText
	label.TextColor3 = accent:Lerp(Theme.Colors.White, 0.55)
	label.TextStrokeColor3 = Theme.Colors.Black
	label.TextStrokeTransparency = 0.25
	label.TextSize = 10
	label.TextScaled = false
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = capsule

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.Position = UDim2.new(0, 45, 0, 17)
	value.Size = UDim2.new(1, -50, 0, 19)
	value.BackgroundTransparency = 1
	value.Font = Theme.Font
	value.TextColor3 = Theme.Colors.White
	value.TextStrokeColor3 = Theme.Colors.Black
	value.TextStrokeTransparency = 0.05
	value.TextSize = 15
	value.TextScaled = false
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.Text = "-"
	value.Parent = capsule

	return value
end

local function formatTime(sec: number): string
	sec = math.max(0, math.floor(sec))
	local m = math.floor(sec / 60)
	local s = sec % 60
	return string.format("%02d:%02d", m, s)
end

local function currentBoostText(state): string
	local activeBoosts = state.ActiveBoosts or {}
	local serverTime = state.ServerTime
	if not serverTime or serverTime == 0 then
		return "Boost: -"
	end

	local now = serverTime + (os.clock() - (state._clientReceivedAt or os.clock()))
	local bestId = nil
	local bestRemain = 0
	for id, expiry in pairs(activeBoosts) do
		if type(expiry) == "number" and expiry > now and expiry - now > bestRemain then
			bestId = id
			bestRemain = expiry - now
		end
	end

	if not bestId then
		return "Boost: -"
	end

	local label = if bestId == "Power2x" then "Power" elseif bestId == "Dna2x" then "DNA" else "Luck"
	return label .. " " .. formatTime(bestRemain)
end

function TopBar.create(parent: ScreenGui, onSpinClick: (() -> ())?): Refs
	local root = Instance.new("Frame")
	root.Name = "TopHUD"
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, 0, 10)
	root.Size = UDim2.new(0, 560, 0, 62)
	root.BackgroundColor3 = Color3.fromRGB(18, 28, 54)
	root.BackgroundTransparency = 0
	root.BorderSizePixel = 0
	root.Parent = parent
	addCornerAndStroke(root, Color3.fromRGB(48, 236, 255), 3, 0.1)
	addGradient(root, Color3.fromRGB(52, 184, 255))

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 9)
	padding.PaddingBottom = UDim.new(0, 9)
	padding.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 9)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = root

	local dnaLabel = makeCapsule(root, "DnaCapsule", "DNA", "DNA", Theme.Colors.Green, 122)
	local powerLabel = makeCapsule(root, "PowerCapsule", "PWR", "POWER", Theme.Colors.Cyan, 122)
	local boostLabel = makeCapsule(root, "BoostCapsule", "2X", "BOOST", Theme.Colors.Purple, 138)

	local spinBtn = Instance.new("TextButton")
	spinBtn.Name = "SpinButton"
	spinBtn.Size = UDim2.new(0, 80, 0, 42)
	spinBtn.Text = "SPIN"
	Theme.applyButtonStyle(spinBtn, Theme.Colors.Blue)
	spinBtn.TextSize = 15
	spinBtn.TextScaled = false
	spinBtn.Parent = root

	if onSpinClick then
		spinBtn.MouseButton1Click:Connect(function()
			UIAnimator.buttonPunch(spinBtn)
			onSpinClick()
		end)
	end

	return {
		root = root,
		dnaLabel = dnaLabel,
		powerLabel = powerLabel,
		boostLabel = boostLabel,
		spinButton = spinBtn,
	}
end

function TopBar.update(refs: Refs, state)
	refs.dnaLabel.Text = NumberFormatter.format(state.DnaCoins or 0)
	refs.powerLabel.Text = NumberFormatter.format(state.Power or 0)
	refs.boostLabel.Text = currentBoostText(state)
end

return TopBar
