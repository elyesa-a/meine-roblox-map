--!strict
-- Unten in der Mitte: Mutation-Power-Bar, Level-Progress und Klick-Button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))

local Configs = ReplicatedStorage:WaitForChild("Configs")
local TitleConfig = require(Configs:WaitForChild("TitleConfig"))

local BottomStats = {}
local POWER_GREEN = Color3.fromRGB(42, 220, 110)
local POWER_CYAN = Color3.fromRGB(34, 210, 255)
local AUTO_OFF_RED = Color3.fromRGB(255, 88, 88)
local PANEL_DARK = Color3.fromRGB(10, 16, 30)
local PANEL_MID = Color3.fromRGB(18, 28, 48)
local BUTTON_DARK = Color3.fromRGB(22, 31, 48)
local BUTTON_OFF_DARK = Color3.fromRGB(42, 18, 24)

type Refs = {
	root: Frame,
	powerLabel: TextLabel,
	levelLabel: TextLabel,
	rankLabel: TextLabel,
	progressFill: Frame,
	progressLabel: TextLabel,
	clickButton: TextButton,
	autoTrainingButton: TextButton,
	autoFightButton: TextButton,
	autoClickButton: TextButton,
	quickButtons: { TextButton },
}

local function addRoundedStroke(gui: GuiObject, radius: number, strokeColor: Color3, thickness: number, transparency: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = strokeColor
	stroke.Thickness = thickness
	stroke.Transparency = transparency
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = gui

	return stroke
end

local function addGradient(gui: GuiObject, top: Color3, bottom: Color3)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, top),
		ColorSequenceKeypoint.new(1, bottom),
	})
	gradient.Rotation = 90
	gradient.Parent = gui
	return gradient
end

local function styleActionButton(button: TextButton, accent: Color3, main: boolean?)
	local oldGradient = button:FindFirstChildOfClass("UIGradient")
	if oldGradient then
		oldGradient:Destroy()
	end
	button.BackgroundColor3 = if main then accent:Lerp(BUTTON_DARK, 0.22) else BUTTON_DARK
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Theme.Font
	button.TextColor3 = Theme.Colors.White
	button.TextStrokeColor3 = Theme.Colors.Black
	button.TextStrokeTransparency = 0
	button.TextTransparency = 0
	button.TextScaled = false
	addRoundedStroke(button, if main then 16 else 13, accent, if main then 2.8 else 2, if main then 0.08 else 0.18)
end

function BottomStats.create(parent: ScreenGui): Refs
	local root = Instance.new("Frame")
	root.Name = "MutationPowerBar"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -20)
	root.Size = UDim2.new(0, 560, 0, 128)
	root.BackgroundColor3 = PANEL_DARK
	root.BackgroundTransparency = 0.02
	root.BorderSizePixel = 0
	root.Parent = parent

	addRoundedStroke(root, 22, POWER_CYAN, 2.5, 0.16)

	addGradient(root, PANEL_MID:Lerp(POWER_CYAN, 0.08), Color3.fromRGB(7, 11, 22))

	local icon = Instance.new("TextLabel")
	icon.Name = "PowerIcon"
	icon.Position = UDim2.new(0, 14, 0, 12)
	icon.Size = UDim2.new(0, 44, 0, 44)
	icon.BackgroundColor3 = POWER_GREEN
	icon.BorderSizePixel = 0
	icon.Font = Enum.Font.GothamBlack
	icon.Text = "PWR"
	icon.TextColor3 = Theme.Colors.White
	icon.TextSize = 16
	icon.TextScaled = false
	icon.TextStrokeColor3 = Theme.Colors.Black
	icon.TextStrokeTransparency = 0.14
	icon.Parent = root
	addRoundedStroke(icon, 14, POWER_GREEN:Lerp(Color3.fromRGB(255, 255, 255), 0.22), 2.2, 0.18)
	addGradient(icon, POWER_GREEN:Lerp(Color3.fromRGB(255, 255, 255), 0.1), POWER_GREEN:Lerp(Color3.fromRGB(0, 0, 0), 0.28))

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Position = UDim2.new(0, 70, 0, 11)
	titleLabel.Size = UDim2.new(0.5, -72, 0, 20)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Theme.Font
	titleLabel.Text = "Mutation Power"
	titleLabel.TextColor3 = Color3.fromRGB(150, 255, 190)
	titleLabel.TextSize = 16
	titleLabel.TextScaled = false
	titleLabel.TextStrokeColor3 = Theme.Colors.Black
	titleLabel.TextStrokeTransparency = 0.22
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = root

	local powerLabel = Instance.new("TextLabel")
	powerLabel.Name = "PowerLabel"
	powerLabel.Size = UDim2.new(0.5, -66, 0, 24)
	powerLabel.Position = UDim2.new(0, 70, 0, 32)
	powerLabel.BackgroundTransparency = 1
	powerLabel.Font = Enum.Font.GothamBlack
	powerLabel.TextColor3 = Theme.Colors.White
	powerLabel.TextStrokeColor3 = Theme.Colors.Black
	powerLabel.TextStrokeTransparency = 0.08
	powerLabel.TextSize = 20
	powerLabel.TextScaled = false
	powerLabel.TextXAlignment = Enum.TextXAlignment.Left
	powerLabel.Text = "0 Power"
	powerLabel.Parent = root

	local rankLabel = Instance.new("TextLabel")
	rankLabel.Name = "RankLabel"
	rankLabel.AnchorPoint = Vector2.new(1, 0)
	rankLabel.Position = UDim2.new(1, -16, 0, 14)
	rankLabel.Size = UDim2.new(0, 210, 0, 22)
	rankLabel.BackgroundTransparency = 1
	rankLabel.Font = Theme.Font
	rankLabel.Text = "Rank: Rookie"
	rankLabel.TextColor3 = Color3.fromRGB(255, 220, 85)
	rankLabel.TextSize = 15
	rankLabel.TextScaled = false
	rankLabel.TextStrokeColor3 = Theme.Colors.Black
	rankLabel.TextStrokeTransparency = 0.18
	rankLabel.TextXAlignment = Enum.TextXAlignment.Right
	rankLabel.Parent = root

	-- Level-Bar.
	local levelHolder = Instance.new("Frame")
	levelHolder.Name = "LevelHolder"
	levelHolder.Size = UDim2.new(1, -84, 0, 28)
	levelHolder.Position = UDim2.new(0, 70, 0, 61)
	levelHolder.BackgroundColor3 = Color3.fromRGB(8, 13, 24)
	levelHolder.BorderSizePixel = 0
	levelHolder.Parent = root
	addRoundedStroke(levelHolder, 14, POWER_CYAN, 1.5, 0.46)

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
	progressBg.BackgroundColor3 = Color3.fromRGB(5, 10, 18)
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
	local fillGradient = Instance.new("UIGradient")
	fillGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(95, 255, 145)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 190, 105)),
	})
	fillGradient.Parent = progressFill

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

	-- Core controls only: Auto modes + main power button.
	local actionRow = Instance.new("Frame")
	actionRow.Name = "ActionRow"
	actionRow.Size = UDim2.new(1, -44, 0, 36)
	actionRow.Position = UDim2.new(0, 22, 0, 91)
	actionRow.BackgroundTransparency = 1
	actionRow.Parent = root

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, 11)
	rowLayout.Parent = actionRow

	local quickButtons: { TextButton } = {}

	local autoTrainingButton = Instance.new("TextButton")
	autoTrainingButton.Name = "AutoTrainingButton"
	autoTrainingButton.Size = UDim2.new(0, 94, 0, 34)
	autoTrainingButton.Text = "AUTO TRAIN: OFF"
	styleActionButton(autoTrainingButton, POWER_CYAN, false)
	autoTrainingButton.BackgroundColor3 = BUTTON_OFF_DARK
	autoTrainingButton.TextSize = 11
	autoTrainingButton.TextScaled = false
	autoTrainingButton.TextColor3 = AUTO_OFF_RED
	autoTrainingButton.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	autoTrainingButton.TextStrokeTransparency = 0
	autoTrainingButton.AutoButtonColor = false
	autoTrainingButton.Active = true
	autoTrainingButton.Parent = actionRow

	local autoFightButton = Instance.new("TextButton")
	autoFightButton.Name = "AutoFightButton"
	autoFightButton.Size = UDim2.new(0, 94, 0, 34)
	autoFightButton.Text = "AUTO FIGHT: OFF"
	styleActionButton(autoFightButton, POWER_CYAN, false)
	autoFightButton.BackgroundColor3 = BUTTON_OFF_DARK
	autoFightButton.TextSize = 11
	autoFightButton.TextScaled = false
	autoFightButton.TextColor3 = AUTO_OFF_RED
	autoFightButton.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	autoFightButton.TextStrokeTransparency = 0
	autoFightButton.AutoButtonColor = false
	autoFightButton.Active = true
	autoFightButton.Parent = actionRow

	local autoButton = Instance.new("TextButton")
	autoButton.Name = "AutoButton"
	autoButton.Size = UDim2.new(0, 78, 0, 34)
	autoButton.Text = "AUTO: OFF"
	styleActionButton(autoButton, POWER_CYAN, false)
	autoButton.BackgroundColor3 = BUTTON_OFF_DARK
	autoButton.TextSize = 12
	autoButton.TextScaled = false
	autoButton.TextColor3 = AUTO_OFF_RED
	autoButton.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	autoButton.TextStrokeTransparency = 0
	autoButton.AutoButtonColor = false
	autoButton.Active = true
	autoButton.Parent = actionRow

	local clickButton = Instance.new("TextButton")
	clickButton.Name = "ClickButton"
	clickButton.Size = UDim2.new(0, 122, 0, 36)
	clickButton.Text = "+1 POWER"
	styleActionButton(clickButton, POWER_GREEN, true)
	clickButton.TextSize = 14
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
		autoTrainingButton = autoTrainingButton,
		autoFightButton = autoFightButton,
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
