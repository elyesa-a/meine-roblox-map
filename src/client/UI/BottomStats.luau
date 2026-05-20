--!strict
-- Unten in der Mitte: Mutation-Power-Bar, Level-Progress und Klick-Button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))

local Configs = ReplicatedStorage:WaitForChild("Configs")
local TitleConfig = require(Configs:WaitForChild("TitleConfig"))

local BottomStats = {}
local POWER_GREEN = Color3.fromRGB(35, 220, 95)

type Refs = {
	root: Frame,
	powerLabel: TextLabel,
	levelLabel: TextLabel,
	rankLabel: TextLabel,
	progressFill: Frame,
	progressLabel: TextLabel,
	clickButton: TextButton,
	autoClickButton: TextButton,
	quickButtons: { TextButton },
}

function BottomStats.create(parent: ScreenGui): Refs
	local root = Instance.new("Frame")
	root.Name = "MutationPowerBar"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -20)
	root.Size = UDim2.new(0, 500, 0, 124)
	root.BackgroundColor3 = Color3.fromRGB(9, 13, 20)
	root.BackgroundTransparency = 0.08
	root.BorderSizePixel = 0
	root.Parent = parent

	local rootCorner = Instance.new("UICorner")
	rootCorner.CornerRadius = UDim.new(0, 16)
	rootCorner.Parent = root

	local rootStroke = Instance.new("UIStroke")
	rootStroke.Color = POWER_GREEN
	rootStroke.Thickness = 1.5
	rootStroke.Transparency = 0.45
	rootStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rootStroke.Parent = root

	local icon = Instance.new("TextLabel")
	icon.Name = "PowerIcon"
	icon.Position = UDim2.new(0, 12, 0, 10)
	icon.Size = UDim2.new(0, 40, 0, 40)
	icon.BackgroundColor3 = Color3.fromRGB(16, 31, 34)
	icon.BorderSizePixel = 0
	icon.Font = Enum.Font.GothamBlack
	icon.Text = "PWR"
	icon.TextColor3 = POWER_GREEN
	icon.TextSize = 15
	icon.TextScaled = false
	icon.TextStrokeTransparency = 1
	icon.Parent = root
	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0, 14)
	iconCorner.Parent = icon
	local iconStroke = Instance.new("UIStroke")
	iconStroke.Color = POWER_GREEN
	iconStroke.Transparency = 0.35
	iconStroke.Thickness = 1.5
	iconStroke.Parent = icon

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Position = UDim2.new(0, 64, 0, 9)
	titleLabel.Size = UDim2.new(0.5, -72, 0, 20)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Theme.Font
	titleLabel.Text = "Mutation Power"
	titleLabel.TextColor3 = Color3.fromRGB(150, 255, 180)
	titleLabel.TextSize = 15
	titleLabel.TextScaled = false
	titleLabel.TextStrokeTransparency = 1
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = root

	local powerLabel = Instance.new("TextLabel")
	powerLabel.Name = "PowerLabel"
	powerLabel.Size = UDim2.new(0.5, -64, 0, 20)
	powerLabel.Position = UDim2.new(0, 64, 0, 30)
	powerLabel.BackgroundTransparency = 1
	powerLabel.Font = Enum.Font.GothamBlack
	powerLabel.TextColor3 = Theme.Colors.White
	powerLabel.TextStrokeTransparency = 1
	powerLabel.TextSize = 18
	powerLabel.TextScaled = false
	powerLabel.TextXAlignment = Enum.TextXAlignment.Left
	powerLabel.Text = "0 Power"
	powerLabel.Parent = root

	local rankLabel = Instance.new("TextLabel")
	rankLabel.Name = "RankLabel"
	rankLabel.AnchorPoint = Vector2.new(1, 0)
	rankLabel.Position = UDim2.new(1, -12, 0, 11)
	rankLabel.Size = UDim2.new(0, 210, 0, 22)
	rankLabel.BackgroundTransparency = 1
	rankLabel.Font = Theme.Font
	rankLabel.Text = "Rank: Rookie"
	rankLabel.TextColor3 = Theme.Colors.Yellow
	rankLabel.TextSize = 13
	rankLabel.TextScaled = false
	rankLabel.TextStrokeTransparency = 1
	rankLabel.TextXAlignment = Enum.TextXAlignment.Right
	rankLabel.Parent = root

	-- Level-Bar.
	local levelHolder = Instance.new("Frame")
	levelHolder.Name = "LevelHolder"
	levelHolder.Size = UDim2.new(1, -76, 0, 26)
	levelHolder.Position = UDim2.new(0, 64, 0, 54)
	levelHolder.BackgroundColor3 = Color3.fromRGB(4, 8, 12)
	levelHolder.BorderSizePixel = 0
	levelHolder.Parent = root
	local holderCorner = Instance.new("UICorner")
	holderCorner.CornerRadius = UDim.new(1, 0)
	holderCorner.Parent = levelHolder

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "LevelLabel"
	levelLabel.Size = UDim2.new(0, 76, 1, 0)
	levelLabel.Position = UDim2.new(0, 8, 0, 0)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Font = Theme.Font
	levelLabel.TextColor3 = Theme.Colors.White
	levelLabel.TextStrokeTransparency = 1
	levelLabel.TextSize = 12
	levelLabel.TextScaled = false
	levelLabel.TextXAlignment = Enum.TextXAlignment.Left
	levelLabel.Text = "Level 1"
	levelLabel.Parent = levelHolder

	local progressBg = Instance.new("Frame")
	progressBg.Name = "ProgressBg"
	progressBg.Size = UDim2.new(1, -94, 1, -12)
	progressBg.Position = UDim2.new(0, 86, 0, 6)
	progressBg.BackgroundColor3 = Color3.fromRGB(5, 8, 10)
	progressBg.BorderSizePixel = 0
	progressBg.Parent = levelHolder
	local pbCorner = Instance.new("UICorner")
	pbCorner.CornerRadius = UDim.new(1, 0)
	pbCorner.Parent = progressBg

	local progressFill = Instance.new("Frame")
	progressFill.Name = "Fill"
	progressFill.Size = UDim2.new(0, 0, 1, 0)
	progressFill.BackgroundColor3 = POWER_GREEN
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
	progressLabel.TextSize = 12
	progressLabel.TextScaled = false
	progressLabel.TextColor3 = Theme.Colors.White
	progressLabel.TextStrokeColor3 = Theme.Colors.Black
	progressLabel.TextStrokeTransparency = 0.15
	progressLabel.Parent = progressBg

	-- Klick-Button + Quick-Buttons + Autoklicker-Toggle.
	local actionRow = Instance.new("Frame")
	actionRow.Name = "ActionRow"
	actionRow.Size = UDim2.new(1, -24, 0, 34)
	actionRow.Position = UDim2.new(0, 12, 0, 86)
	actionRow.BackgroundTransparency = 1
	actionRow.Parent = root

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.Parent = actionRow

	local quickButtons: { TextButton } = {}
	for _, label in ipairs({ "+100K", "+10K", "+1M" }) do
		local btn = Instance.new("TextButton")
		btn.Name = label .. "Button"
		btn.Size = UDim2.new(0, 58, 1, 0)
		btn.Text = label
		Theme.applyButtonStyle(btn, Color3.fromRGB(31, 38, 52))
		btn.TextSize = 12
		btn.TextScaled = false
		btn.AutoButtonColor = false
		btn.Active = false
		btn.Parent = actionRow
		table.insert(quickButtons, btn)
	end

	local autoButton = Instance.new("TextButton")
	autoButton.Name = "AutoButton"
	autoButton.Size = UDim2.new(0, 82, 1, 0)
	autoButton.Text = "AUTO: OFF"
	Theme.applyButtonStyle(autoButton, Color3.fromRGB(31, 38, 52))
	autoButton.TextSize = 12
	autoButton.TextScaled = false
	autoButton.TextColor3 = Color3.fromRGB(255, 95, 95)
	autoButton.AutoButtonColor = false
	autoButton.Active = true
	autoButton.Parent = actionRow

	local clickButton = Instance.new("TextButton")
	clickButton.Name = "ClickButton"
	clickButton.Size = UDim2.new(0, 136, 1, 0)
	clickButton.Text = "+1 POWER"
	Theme.applyButtonStyle(clickButton, Theme.Colors.Green)
	clickButton.TextSize = 15
	clickButton.TextScaled = false
	clickButton.Parent = actionRow

	return {
		root = root,
		powerLabel = powerLabel,
		levelLabel = levelLabel,
		rankLabel = rankLabel,
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
	local titleDef = TitleConfig.getById(state.EquippedTitle or "Rookie")
	refs.rankLabel.Text = "Rank: " .. (if titleDef then titleDef.displayName else "Rookie")
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
