--!strict
-- Spin-Wheel: visualisierter Kreis aus Segmenten + Spin-Button.
-- Server entscheidet das Ergebnis; Client animiert nur die Rotation und zeigt
-- Cooldown / verfuegbar.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))

local Configs = ReplicatedStorage:WaitForChild("Configs")
local SpinConfig = require(Configs:WaitForChild("SpinConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestSpin = Remotes:WaitForChild("RequestSpin") :: RemoteEvent

local SpinFrame = {}

type Refs = {
	backdrop: Frame,
	root: Frame,
	wheel: Frame,
	statusLabel: TextLabel,
	cooldownLabel: TextLabel,
	spinButton: TextButton,
}

local function formatCooldown(sec: number): string
	sec = math.max(0, math.floor(sec))
	local m = math.floor(sec / 60)
	local s = sec % 60
	return string.format("%02d:%02d", m, s)
end

function SpinFrame.create(parent: ScreenGui): Refs
	local backdrop = Instance.new("Frame")
	backdrop.Name = "SpinBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.DimBackdrop
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Visible = false
	backdrop.ZIndex = 5
	backdrop.Parent = parent

	local root = Instance.new("Frame")
	root.Name = "SpinFrame"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.new(0, 560, 0, 540)
	Theme.applyPanelStyle(root, Theme.Colors.Yellow)
	root.ZIndex = 6
	root.Parent = backdrop

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -16, 0, 40)
	header.Position = UDim2.new(0, 8, 0, 8)
	Theme.applyLabelStyle(header)
	header.Text = "SPIN"
	header.TextSize = 28
	header.TextScaled = false
	header.ZIndex = 7
	header.Parent = root

	local closeButton = Instance.new("TextButton")
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -8, 0, 8)
	closeButton.Size = UDim2.new(0, 36, 0, 36)
	closeButton.Text = "X"
	Theme.applyButtonStyle(closeButton, Theme.Colors.Red)
	closeButton.TextSize = 22
	closeButton.TextScaled = false
	closeButton.ZIndex = 8
	closeButton.Parent = root
	closeButton.MouseButton1Click:Connect(function()
		UIAnimator.framePopOut(backdrop, root)
	end)

	-- Wheel-Container
	local wheelHolder = Instance.new("Frame")
	wheelHolder.AnchorPoint = Vector2.new(0.5, 0)
	wheelHolder.Size = UDim2.new(0, 320, 0, 320)
	wheelHolder.Position = UDim2.new(0.5, 0, 0, 58)
	wheelHolder.BackgroundColor3 = Theme.Colors.PanelDark
	wheelHolder.BorderSizePixel = 0
	wheelHolder.ZIndex = 7
	wheelHolder.Parent = root

	local wholeCorner = Instance.new("UICorner")
	wholeCorner.CornerRadius = UDim.new(1, 0)
	wholeCorner.Parent = wheelHolder

	-- Rotierender Frame fuer die Segmente.
	local wheel = Instance.new("Frame")
	wheel.AnchorPoint = Vector2.new(0.5, 0.5)
	wheel.Size = UDim2.new(1, -8, 1, -8)
	wheel.Position = UDim2.fromScale(0.5, 0.5)
	wheel.BackgroundTransparency = 1
	wheel.ZIndex = 8
	wheel.Parent = wheelHolder

	local wheelCorner = Instance.new("UICorner")
	wheelCorner.CornerRadius = UDim.new(1, 0)
	wheelCorner.Parent = wheel

	-- Segmente als rotierende Label-Streifen.
	local n = #SpinConfig.Rewards
	for i, reward in ipairs(SpinConfig.Rewards) do
		local segment = Instance.new("Frame")
		segment.Size = UDim2.new(0.5, 0, 0.5, 0)
		segment.AnchorPoint = Vector2.new(0, 1)
		segment.Position = UDim2.fromScale(0.5, 0.5)
		segment.Rotation = (i - 1) * (360 / n)
		segment.BackgroundColor3 = reward.color
		segment.BorderSizePixel = 0
		segment.ZIndex = 8
		segment.Parent = wheel

		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Size = UDim2.new(0, 90, 0, 24)
		label.Position = UDim2.new(0, 0, 0.05, 0)
		Theme.applyLabelStyle(label)
		label.Text = reward.displayName
		label.TextSize = 11
		label.TextScaled = false
		label.Rotation = 90 - 360 / (n * 2)
		label.ZIndex = 9
		label.Parent = segment
	end

	-- Zeiger (Dreieck oben auf Wheel).
	local pointer = Instance.new("TextLabel")
	pointer.AnchorPoint = Vector2.new(0.5, 0)
	pointer.Size = UDim2.new(0, 0, 0, 0)
	pointer.Position = UDim2.new(0.5, 0, 0, -8)
	pointer.BackgroundTransparency = 1
	pointer.Text = "v"
	Theme.applyLabelStyle(pointer)
	pointer.TextSize = 40
	pointer.TextScaled = false
	pointer.TextColor3 = Theme.Colors.Red
	pointer.ZIndex = 10
	pointer.Parent = wheelHolder

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(1, -32, 0, 28)
	statusLabel.Position = UDim2.new(0, 16, 0, 392)
	Theme.applyLabelStyle(statusLabel)
	statusLabel.Text = "Ready!"
	statusLabel.TextSize = 18
	statusLabel.TextScaled = false
	statusLabel.ZIndex = 7
	statusLabel.Parent = root

	local cooldownLabel = Instance.new("TextLabel")
	cooldownLabel.Size = UDim2.new(1, -32, 0, 22)
	cooldownLabel.Position = UDim2.new(0, 16, 0, 420)
	Theme.applyLabelStyle(cooldownLabel)
	cooldownLabel.Text = ""
	cooldownLabel.TextSize = 14
	cooldownLabel.TextScaled = false
	cooldownLabel.ZIndex = 7
	cooldownLabel.Parent = root

	local spinButton = Instance.new("TextButton")
	spinButton.Name = "SpinButton"
	spinButton.AnchorPoint = Vector2.new(0.5, 1)
	spinButton.Size = UDim2.new(1, -32, 0, 60)
	spinButton.Position = UDim2.new(0.5, 0, 1, -16)
	Theme.applyButtonStyle(spinButton, Theme.Colors.Green)
	spinButton.Text = "SPIN"
	spinButton.TextSize = 24
	spinButton.TextScaled = false
	spinButton.ZIndex = 7
	spinButton.Parent = root

	local isSpinning = false
	spinButton.MouseButton1Click:Connect(function()
		if isSpinning then
			return
		end
		isSpinning = true
		UIAnimator.buttonPunch(spinButton)
		RequestSpin:FireServer()
		-- Animation: zufaellige End-Rotation 720°-1440° dazu.
		local endRot = wheel.Rotation + 720 + math.random(0, 720)
		local tween = TweenService:Create(
			wheel,
			TweenInfo.new(2.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Rotation = endRot }
		)
		tween:Play()
		tween.Completed:Connect(function()
			isSpinning = false
		end)
	end)

	return {
		backdrop = backdrop,
		root = root,
		wheel = wheel,
		statusLabel = statusLabel,
		cooldownLabel = cooldownLabel,
		spinButton = spinButton,
	}
end

function SpinFrame.show(refs: Refs)
	UIAnimator.framePopIn(refs.backdrop, refs.root)
end

function SpinFrame.tick(refs: Refs, state)
	if not state or not state.Spin then
		return
	end
	-- Vor der ersten Server-Antwort haben wir keine echte ServerTime -> skippen.
	if not state.ServerTime or state.ServerTime == 0 then
		return
	end
	local extrapolated = state.ServerTime + (os.clock() - (state._clientReceivedAt or os.clock()))
	local lastSpin = state.Spin.LastFreeSpin or 0
	local elapsed = extrapolated - lastSpin
	if elapsed >= SpinConfig.CooldownSec then
		refs.statusLabel.Text = "Free Spin ready!"
		refs.cooldownLabel.Text = ""
		refs.spinButton.BackgroundColor3 = Theme.Colors.Green
		refs.spinButton.Active = true
		refs.spinButton.Text = "SPIN"
	else
		refs.statusLabel.Text = "Cooldown running..."
		refs.cooldownLabel.Text = "Next Spin in " .. formatCooldown(SpinConfig.CooldownSec - elapsed)
		refs.spinButton.BackgroundColor3 = Theme.Colors.PanelMedium
		refs.spinButton.Active = false
		refs.spinButton.Text = "WAIT"
	end
end

return SpinFrame
