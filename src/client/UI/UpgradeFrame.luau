--!strict
-- Upgrade-Fenster: 4 Karten (Mehr Kraft / DNA / Glueck / Training-Speed).
-- Pro Karte: Level, aktueller Mult, naechster Mult, Preis, Kaufen-Button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))
local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))

local Configs = ReplicatedStorage:WaitForChild("Configs")
local UpgradeConfig = require(Configs:WaitForChild("UpgradeConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestBuyUpgrade = Remotes:WaitForChild("RequestBuyUpgrade") :: RemoteEvent

local UpgradeFrame = {}

type CardRefs = {
	card: Frame,
	levelLabel: TextLabel,
	progressLabel: TextLabel,
	button: TextButton,
}

type Refs = {
	backdrop: Frame,
	root: Frame,
	infoLabel: TextLabel,
	cards: { [string]: CardRefs },
}

local function makeCard(parent: ScrollingFrame, def): CardRefs
	local card = Instance.new("Frame")
	card.Name = "Upgrade_" .. def.id
	card.Size = UDim2.new(1, 0, 0, 96)
	Theme.applyPanelStyle(card, def.color)
	card.ZIndex = 7
	card.Parent = parent

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(0, 240, 0, 32)
	name.Position = UDim2.new(0, 12, 0, 8)
	Theme.applyLabelStyle(name)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = def.displayName
	name.TextSize = 22
	name.TextScaled = false
	name.ZIndex = 8
	name.Parent = card

	local level = Instance.new("TextLabel")
	level.Size = UDim2.new(0, 240, 0, 22)
	level.Position = UDim2.new(0, 12, 0, 42)
	Theme.applyLabelStyle(level)
	level.TextXAlignment = Enum.TextXAlignment.Left
	level.Text = "Level 0"
	level.TextSize = 16
	level.TextScaled = false
	level.ZIndex = 8
	level.Parent = card

	local progress = Instance.new("TextLabel")
	progress.Size = UDim2.new(0, 240, 0, 22)
	progress.Position = UDim2.new(0, 12, 0, 66)
	Theme.applyLabelStyle(progress)
	progress.TextXAlignment = Enum.TextXAlignment.Left
	progress.Text = "1x -> 1.1x"
	progress.TextSize = 14
	progress.TextScaled = false
	progress.ZIndex = 8
	progress.Parent = card

	local button = Instance.new("TextButton")
	button.Name = "Action"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Size = UDim2.new(0, 180, 0, 64)
	button.Position = UDim2.new(1, -12, 0.5, 0)
	Theme.applyButtonStyle(button, Theme.Colors.Green)
	button.Text = "BUY\n100 DNA"
	button.TextSize = 16
	button.TextScaled = false
	button.ZIndex = 9
	button.Parent = card

	return { card = card, levelLabel = level, progressLabel = progress, button = button }
end

function UpgradeFrame.create(parent: ScreenGui): Refs
	local backdrop = Instance.new("Frame")
	backdrop.Name = "UpgradeBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.DimBackdrop
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Visible = false
	backdrop.ZIndex = 5
	backdrop.Parent = parent

	local root = Instance.new("Frame")
	root.Name = "UpgradeFrame"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.new(0, 640, 0, 520)
	Theme.applyPanelStyle(root, Theme.Colors.Green)
	root.ZIndex = 6
	root.Parent = backdrop

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -16, 0, 40)
	header.Position = UDim2.new(0, 8, 0, 8)
	Theme.applyLabelStyle(header)
	header.Text = "SKILLS"
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

	local infoLabel = Instance.new("TextLabel")
	infoLabel.Size = UDim2.new(1, -32, 0, 28)
	infoLabel.Position = UDim2.new(0, 16, 0, 52)
	Theme.applyLabelStyle(infoLabel)
	infoLabel.Text = "DNA: 0"
	infoLabel.TextSize = 16
	infoLabel.TextScaled = false
	infoLabel.ZIndex = 7
	infoLabel.Parent = root

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "UpgradeList"
	scroll.Size = UDim2.new(1, -32, 1, -100)
	scroll.Position = UDim2.new(0, 16, 0, 88)
	scroll.BackgroundColor3 = Theme.Colors.PanelDark
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ZIndex = 7
	scroll.Parent = root
	local sc = Instance.new("UICorner")
	sc.CornerRadius = Theme.CornerRadius
	sc.Parent = scroll

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = scroll

	local cards: { [string]: CardRefs } = {}
	for i, def in ipairs(UpgradeConfig.Upgrades) do
		local refs = makeCard(scroll, def)
		refs.card.LayoutOrder = i
		cards[def.id] = refs
		refs.button.MouseButton1Click:Connect(function()
			UIAnimator.buttonPunch(refs.button)
			RequestBuyUpgrade:FireServer(def.id)
		end)
	end

	return {
		backdrop = backdrop,
		root = root,
		infoLabel = infoLabel,
		cards = cards,
	}
end

function UpgradeFrame.show(refs: Refs)
	UIAnimator.framePopIn(refs.backdrop, refs.root)
end

function UpgradeFrame.update(refs: Refs, state)
	local dna = state.DnaCoins or 0
	refs.infoLabel.Text = string.format("DNA: %s", NumberFormatter.format(dna))
	local upgrades = if type(state.Upgrades) == "table" then state.Upgrades else {}
	for _, def in ipairs(UpgradeConfig.Upgrades) do
		local cardRefs = refs.cards[def.id]
		if not cardRefs then
			continue
		end
		local level = upgrades[def.id] or 0
		cardRefs.levelLabel.Text = string.format("Level %d", level)
		local currMult = UpgradeConfig.getMultiplier(level, def.perLevelDelta)
		if level >= UpgradeConfig.MaxLevel then
			cardRefs.progressLabel.Text = string.format("%.2gx (Max Level)", currMult)
			cardRefs.button.Text = "MAX LEVEL"
			cardRefs.button.BackgroundColor3 = Theme.Colors.PanelMedium
		else
			local nextMult = UpgradeConfig.getMultiplier(level + 1, def.perLevelDelta)
			local cost = UpgradeConfig.getCost(level)
			cardRefs.progressLabel.Text = string.format("%.2gx -> %.2gx", currMult, nextMult)
			cardRefs.button.Text = string.format("BUY\n%s DNA", NumberFormatter.format(cost))
			cardRefs.button.BackgroundColor3 = if dna >= cost then Theme.Colors.Green else Theme.Colors.PanelMedium
		end
	end
end

return UpgradeFrame
