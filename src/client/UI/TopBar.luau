--!strict
-- Obere Leiste: DNA-Coin-Anzeige + Spin-Wheel-Platzhalter.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))

local TopBar = {}

type Refs = {
	root: Frame,
	dnaLabel: TextLabel,
}

function TopBar.create(parent: ScreenGui): Refs
	local root = Instance.new("Frame")
	root.Name = "TopBar"
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, 0, 12)
	root.Size = UDim2.new(0, 360, 0, 50)
	root.BackgroundTransparency = 1
	root.Parent = parent

	-- DNA-Coin-Karte.
	local dnaCard = Instance.new("Frame")
	dnaCard.Name = "DnaCard"
	dnaCard.Size = UDim2.new(0, 220, 1, 0)
	dnaCard.Position = UDim2.new(0, 0, 0, 0)
	Theme.applyPanelStyle(dnaCard, Theme.Colors.Blue)
	dnaCard.Parent = root

	local dnaLabel = Instance.new("TextLabel")
	dnaLabel.Size = UDim2.new(1, -16, 1, -8)
	dnaLabel.Position = UDim2.new(0, 8, 0, 4)
	Theme.applyLabelStyle(dnaLabel)
	dnaLabel.Text = "DNA: 0"
	dnaLabel.Parent = dnaCard

	-- Spin-Wheel-Platzhalter.
	local spinBtn = Instance.new("TextButton")
	spinBtn.Name = "SpinButton"
	spinBtn.Size = UDim2.new(0, 130, 1, 0)
	spinBtn.Position = UDim2.new(0, 230, 0, 0)
	spinBtn.Text = "SPIN!"
	Theme.applyButtonStyle(spinBtn, Theme.Colors.Yellow)
	spinBtn.TextSize = 18
	spinBtn.TextScaled = false
	spinBtn.AutoButtonColor = false
	spinBtn.Active = false
	spinBtn.Parent = root

	return { root = root, dnaLabel = dnaLabel }
end

function TopBar.update(refs: Refs, state)
	refs.dnaLabel.Text = "DNA: " .. NumberFormatter.format(state.DnaCoins or 0)
end

return TopBar
