--!strict
-- Upgrade-Fenster: Skills/Upgrades, gekauft mit DNA.
-- Pro Karte: Level, aktueller Mult, naechster Mult, Preis, Kaufen-Button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local LabTheme = require(script.Parent:WaitForChild("LabTheme"))
local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))
local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))

local Configs = ReplicatedStorage:WaitForChild("Configs")
local UpgradeConfig = require(Configs:WaitForChild("UpgradeConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestBuyUpgrade = Remotes:WaitForChild("RequestBuyUpgrade") :: RemoteEvent

local UpgradeFrame = {}

type CardRefs = {
	card: Frame,
	descriptionLabel: TextLabel,
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
	card.Size = UDim2.new(1, 0, 0, 118)
	Theme.applyPanelStyle(card, LabTheme.Colors.Card)
	LabTheme.styleCard(card, def.color)
	LabTheme.bindHoverPopout(card, 1.018)
	card.ZIndex = 7
	card.Parent = parent

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 44, 0, 44)
	icon.Position = UDim2.new(0, 12, 0, 12)
	Theme.applyPanelStyle(icon, LabTheme.Colors.Panel2)
	LabTheme.styleCard(icon, def.color)
	icon.Text = def.iconText or "UP"
	icon.TextColor3 = def.color:Lerp(LabTheme.Colors.Text, 0.2)
	icon.TextSize = 14
	icon.TextScaled = false
	icon.Font = Enum.Font.GothamBlack
	icon.ZIndex = 8
	icon.Parent = card

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -270, 0, 28)
	name.Position = UDim2.new(0, 66, 0, 8)
	Theme.applyLabelStyle(name)
	LabTheme.styleLabel(name, LabTheme.Colors.Text, 22, true)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = def.displayName
	name.TextSize = 22
	name.TextScaled = false
	name.ZIndex = 8
	name.Parent = card

	local description = Instance.new("TextLabel")
	description.Size = UDim2.new(1, -270, 0, 20)
	description.Position = UDim2.new(0, 66, 0, 36)
	Theme.applyLabelStyle(description)
	LabTheme.styleLabel(description, LabTheme.Colors.SubText, 14, false)
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.Text = def.description or "Permanent upgrade"
	description.TextSize = 14
	description.TextScaled = false
	description.TextTransparency = 0.15
	description.ZIndex = 8
	description.Parent = card

	local level = Instance.new("TextLabel")
	level.Size = UDim2.new(1, -270, 0, 22)
	level.Position = UDim2.new(0, 66, 0, 62)
	Theme.applyLabelStyle(level)
	LabTheme.styleLabel(level, LabTheme.Colors.Text, 16, true)
	level.TextXAlignment = Enum.TextXAlignment.Left
	level.Text = "Level: 0 / 5"
	level.TextSize = 16
	level.TextScaled = false
	level.ZIndex = 8
	level.Parent = card

	local progress = Instance.new("TextLabel")
	progress.Size = UDim2.new(1, -270, 0, 22)
	progress.Position = UDim2.new(0, 66, 0, 88)
	Theme.applyLabelStyle(progress)
	LabTheme.styleLabel(progress, def.color:Lerp(LabTheme.Colors.Text, 0.35), 14, true)
	progress.TextXAlignment = Enum.TextXAlignment.Left
	progress.Text = "1x -> 1.1x"
	progress.TextSize = 14
	progress.TextScaled = false
	progress.ZIndex = 8
	progress.Parent = card

	local button = Instance.new("TextButton")
	button.Name = "Action"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Size = UDim2.new(0, 160, 0, 64)
	button.Position = UDim2.new(1, -12, 0.5, 0)
	Theme.applyButtonStyle(button, LabTheme.Colors.Green)
	LabTheme.styleButton(button, LabTheme.Colors.Green, true)
	LabTheme.bindButtonFeedback(button, LabTheme.Colors.Green)
	button.Text = "BUY\n100 DNA"
	button.TextSize = 16
	button.TextScaled = false
	button.ZIndex = 9
	button.Parent = card

	return { card = card, descriptionLabel = description, levelLabel = level, progressLabel = progress, button = button }
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
	LabTheme.styleBackdrop(backdrop)

	local root = Instance.new("Frame")
	root.Name = "UpgradeFrame"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.new(0, 640, 0, 520)
	Theme.applyPanelStyle(root, LabTheme.Colors.Base)
	LabTheme.styleModal(root, LabTheme.Colors.Green)
	root.ZIndex = 6
	root.Parent = backdrop

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -16, 0, 40)
	header.Position = UDim2.new(0, 8, 0, 8)
	Theme.applyLabelStyle(header)
	LabTheme.styleLabel(header, LabTheme.Colors.Text, 28, true)
	header.Text = "DNA UPGRADES"
	header.TextSize = 28
	header.TextScaled = false
	header.ZIndex = 7
	header.Parent = root

	local closeButton = Instance.new("TextButton")
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -8, 0, 8)
	closeButton.Size = UDim2.new(0, 36, 0, 36)
	closeButton.Text = "X"
	Theme.applyButtonStyle(closeButton, LabTheme.Colors.Red)
	LabTheme.styleClose(closeButton)
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
	LabTheme.styleLabel(infoLabel, LabTheme.Colors.SubText, 16, false)
	infoLabel.Text = "Available DNA: 0"
	infoLabel.TextSize = 16
	infoLabel.TextScaled = false
	infoLabel.ZIndex = 7
	infoLabel.Parent = root

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "UpgradeList"
	scroll.Size = UDim2.new(1, -32, 1, -100)
	scroll.Position = UDim2.new(0, 16, 0, 88)
	scroll.BackgroundColor3 = LabTheme.Colors.Panel
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ZIndex = 7
	scroll.Parent = root
	LabTheme.styleScroll(scroll)
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
	refs.infoLabel.Text = string.format("Available DNA: %s", NumberFormatter.format(dna))
	local upgrades = if type(state.Upgrades) == "table" then state.Upgrades else {}
	for _, def in ipairs(UpgradeConfig.Upgrades) do
		local cardRefs = refs.cards[def.id]
		if not cardRefs then
			continue
		end
		local level = upgrades[def.id] or 0
		local maxLevel = UpgradeConfig.getMaxLevel(def)
		cardRefs.descriptionLabel.Text = def.description or "Permanent upgrade"
		cardRefs.levelLabel.Text = string.format("Level: %d / %d", level, maxLevel)
		local currMult = UpgradeConfig.getMultiplier(level, def.perLevelDelta)
		if level >= maxLevel then
			if def.id == "Health" then
				cardRefs.progressLabel.Text = string.format("MAX HEALTH BONUS: +%s HP", NumberFormatter.format(level * 100))
			else
				cardRefs.progressLabel.Text = string.format("%.2gx (Max Level)", currMult)
			end
			cardRefs.button.Text = "MAX"
			LabTheme.styleButton(cardRefs.button, def.color, false)
		else
			local nextMult = UpgradeConfig.getMultiplier(level + 1, def.perLevelDelta)
			local cost = UpgradeConfig.getCost(level, def)
			if def.id == "Health" then
				cardRefs.progressLabel.Text = def.bonusText or "+100 HP per level"
			else
				cardRefs.progressLabel.Text = string.format("%.2gx -> %.2gx", currMult, nextMult)
			end
			if dna >= cost then
				cardRefs.button.Text = string.format("BUY\n%s DNA", NumberFormatter.format(cost))
				LabTheme.styleButton(cardRefs.button, LabTheme.Colors.Green, true)
			else
				cardRefs.button.Text = string.format("NEED\n%s DNA", NumberFormatter.format(cost))
				LabTheme.styleButton(cardRefs.button, def.color, false)
			end
		end
	end
end

return UpgradeFrame
