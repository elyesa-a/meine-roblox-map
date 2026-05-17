--!strict
-- Unten in der Mitte: Kraft-Anzeige, Level-Progress und Klick-Button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))

local BottomStats = {}

type Refs = {
	root: Frame,
	powerLabel: TextLabel,
	levelLabel: TextLabel,
	progressFill: Frame,
	progressLabel: TextLabel,
	clickButton: TextButton,
	autoClickButton: TextButton,
	quickButtons: { TextButton },
}

function BottomStats.create(parent: ScreenGui): Refs
	local root = Instance.new("Frame")
	root.Name = "BottomStats"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -16)
	root.Size = UDim2.new(0, 520, 0, 158)
	root.BackgroundTransparency = 1
	root.Parent = parent

	-- Kraft-Anzeige (gleiche Hoehe wie Stufe).
	local powerCard = Instance.new("Frame")
	powerCard.Name = "PowerCard"
	powerCard.Size = UDim2.new(1, 0, 0, 38)
	powerCard.Position = UDim2.new(0, 0, 0, 0)
	Theme.applyPanelStyle(powerCard, Theme.Colors.Red)
	powerCard.Parent = root

	local powerLabel = Instance.new("TextLabel")
	powerLabel.Name = "PowerLabel"
	powerLabel.Size = UDim2.new(1, -16, 1, -8)
	powerLabel.Position = UDim2.new(0, 8, 0, 4)
	Theme.applyLabelStyle(powerLabel)
	powerLabel.TextXAlignment = Enum.TextXAlignment.Center
	powerLabel.Text = "0 Power"
	powerLabel.Parent = powerCard

	-- Level-Bar.
	local levelHolder = Instance.new("Frame")
	levelHolder.Name = "LevelHolder"
	levelHolder.Size = UDim2.new(1, 0, 0, 38)
	levelHolder.Position = UDim2.new(0, 0, 0, 46)
	Theme.applyPanelStyle(levelHolder, Theme.Colors.PanelMedium)
	levelHolder.Parent = root

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "LevelLabel"
	levelLabel.Size = UDim2.new(0, 100, 1, 0)
	levelLabel.Position = UDim2.new(0, 8, 0, 0)
	Theme.applyLabelStyle(levelLabel)
	levelLabel.TextXAlignment = Enum.TextXAlignment.Left
	levelLabel.Text = "Level 1"
	levelLabel.Parent = levelHolder

	local progressBg = Instance.new("Frame")
	progressBg.Name = "ProgressBg"
	progressBg.Size = UDim2.new(1, -130, 1, -16)
	progressBg.Position = UDim2.new(0, 116, 0, 8)
	progressBg.BackgroundColor3 = Theme.Colors.Black
	progressBg.BorderSizePixel = 0
	progressBg.Parent = levelHolder
	local pbCorner = Instance.new("UICorner")
	pbCorner.CornerRadius = UDim.new(1, 0)
	pbCorner.Parent = progressBg

	local progressFill = Instance.new("Frame")
	progressFill.Name = "Fill"
	progressFill.Size = UDim2.new(0, 0, 1, 0)
	progressFill.BackgroundColor3 = Theme.Colors.Green
	progressFill.BorderSizePixel = 0
	progressFill.Parent = progressBg
	local pfCorner = Instance.new("UICorner")
	pfCorner.CornerRadius = UDim.new(1, 0)
	pfCorner.Parent = progressFill

	local progressLabel = Instance.new("TextLabel")
	progressLabel.Name = "ProgressLabel"
	progressLabel.Size = UDim2.new(1, 0, 1, 0)
	Theme.applyLabelStyle(progressLabel)
	progressLabel.Text = "0/0"
	progressLabel.TextSize = 14
	progressLabel.TextScaled = false
	progressLabel.Parent = progressBg

	-- Klick-Button + Quick-Buttons + Autoklicker-Toggle.
	local actionRow = Instance.new("Frame")
	actionRow.Name = "ActionRow"
	actionRow.Size = UDim2.new(1, 0, 0, 64)
	actionRow.Position = UDim2.new(0, 0, 0, 94)
	actionRow.BackgroundTransparency = 1
	actionRow.Parent = root

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.Parent = actionRow

	local clickButton = Instance.new("TextButton")
	clickButton.Name = "ClickButton"
	clickButton.Size = UDim2.new(0, 160, 1, 0)
	clickButton.Text = "+1 POWER"
	Theme.applyButtonStyle(clickButton, Theme.Colors.Red)
	clickButton.TextSize = 22
	clickButton.TextScaled = false
	clickButton.Parent = actionRow

	local quickButtons: { TextButton } = {}
	for _, label in ipairs({ "+10K", "+100K", "+1M" }) do
		local btn = Instance.new("TextButton")
		btn.Name = label .. "Button"
		btn.Size = UDim2.new(0, 70, 1, 0)
		btn.Text = label
		Theme.applyButtonStyle(btn, Theme.Colors.PanelMedium)
		btn.TextSize = 16
		btn.TextScaled = false
		btn.AutoButtonColor = false
		btn.Active = false
		btn.Parent = actionRow
		table.insert(quickButtons, btn)
	end

	local autoButton = Instance.new("TextButton")
	autoButton.Name = "AutoButton"
	autoButton.Size = UDim2.new(0, 110, 1, 0)
	autoButton.Text = "AUTO: OFF"
	Theme.applyButtonStyle(autoButton, Theme.Colors.PanelMedium)
	autoButton.TextSize = 16
	autoButton.TextScaled = false
	autoButton.AutoButtonColor = false
	autoButton.Active = false
	autoButton.Parent = actionRow

	return {
		root = root,
		powerLabel = powerLabel,
		levelLabel = levelLabel,
		progressFill = progressFill,
		progressLabel = progressLabel,
		clickButton = clickButton,
		autoClickButton = autoButton,
		quickButtons = quickButtons,
	}
end

function BottomStats.update(refs: Refs, state)
	refs.powerLabel.Text = NumberFormatter.format(state.Power or 0) .. " Power"
	refs.levelLabel.Text = "Level " .. tostring(state.Level or 1)
	local cost = state.LevelCost or 0
	local frac = if cost > 0 then math.clamp((state.Power or 0) / cost, 0, 1) else 0
	refs.progressFill.Size = UDim2.new(frac, 0, 1, 0)
	refs.progressLabel.Text = string.format(
		"%s / %s",
		NumberFormatter.format(state.Power or 0),
		NumberFormatter.format(cost)
	)
end

return BottomStats
