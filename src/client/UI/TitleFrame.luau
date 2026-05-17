--!strict
-- Titles menu: owned/locked/equipped state, rarity, unlock text, bonuses.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))

local Configs = ReplicatedStorage:WaitForChild("Configs")
local TitleConfig = require(Configs:WaitForChild("TitleConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestEquipTitle = Remotes:WaitForChild("RequestEquipTitle") :: RemoteEvent

local TitleFrame = {}

type CardRefs = {
	card: Frame,
	status: TextLabel,
	button: TextButton,
}

type Refs = {
	backdrop: Frame,
	root: Frame,
	infoLabel: TextLabel,
	cards: { [string]: CardRefs },
}

local function bonusText(def): string
	if not def.bonus then
		return "Bonus: -"
	end
	local parts = {}
	if def.bonus.Power then
		table.insert(parts, "+" .. tostring(math.floor(def.bonus.Power * 100)) .. "% Power")
	end
	if def.bonus.Dna then
		table.insert(parts, "+" .. tostring(math.floor(def.bonus.Dna * 100)) .. "% DNA")
	end
	if def.bonus.Luck then
		table.insert(parts, "+" .. tostring(math.floor(def.bonus.Luck * 100)) .. "% Luck")
	end
	return "Bonus: " .. table.concat(parts, " | ")
end

local function makeCard(parent: ScrollingFrame, def): CardRefs
	local card = Instance.new("Frame")
	card.Name = "Title_" .. def.id
	card.Size = UDim2.new(1, 0, 0, 92)
	card.LayoutOrder = table.find(TitleConfig.Titles, def) or 1
	Theme.applyPanelStyle(card, def.color)
	card.ZIndex = 7
	card.Parent = parent

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(0, 260, 0, 28)
	name.Position = UDim2.new(0, 12, 0, 8)
	Theme.applyLabelStyle(name)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = def.displayName
	name.TextSize = 22
	name.TextScaled = false
	name.ZIndex = 8
	name.Parent = card

	local rarity = Instance.new("TextLabel")
	rarity.Size = UDim2.new(0, 190, 0, 24)
	rarity.Position = UDim2.new(0, 12, 0, 38)
	Theme.applyLabelStyle(rarity)
	rarity.TextXAlignment = Enum.TextXAlignment.Left
	rarity.Text = def.rarity .. " | " .. def.category
	rarity.TextColor3 = def.color
	rarity.TextSize = 15
	rarity.TextScaled = false
	rarity.ZIndex = 8
	rarity.Parent = card

	local unlock = Instance.new("TextLabel")
	unlock.Size = UDim2.new(1, -210, 0, 24)
	unlock.Position = UDim2.new(0, 12, 0, 62)
	Theme.applyLabelStyle(unlock)
	unlock.TextXAlignment = Enum.TextXAlignment.Left
	unlock.Text = def.unlockText .. "  |  " .. bonusText(def)
	unlock.TextSize = 13
	unlock.TextScaled = false
	unlock.ZIndex = 8
	unlock.Parent = card

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(1, 0)
	status.Size = UDim2.new(0, 150, 0, 24)
	status.Position = UDim2.new(1, -14, 0, 10)
	Theme.applyLabelStyle(status)
	status.TextXAlignment = Enum.TextXAlignment.Right
	status.Text = "LOCKED"
	status.TextSize = 15
	status.TextScaled = false
	status.ZIndex = 8
	status.Parent = card

	local button = Instance.new("TextButton")
	button.Name = "EquipButton"
	button.AnchorPoint = Vector2.new(1, 1)
	button.Size = UDim2.new(0, 146, 0, 42)
	button.Position = UDim2.new(1, -12, 1, -10)
	Theme.applyButtonStyle(button, Theme.Colors.PanelMedium)
	button.Text = "LOCKED"
	button.TextSize = 16
	button.TextScaled = false
	button.ZIndex = 9
	button.Parent = card
	button.MouseButton1Click:Connect(function()
		if button:GetAttribute("Action") == "Equip" then
			UIAnimator.buttonPunch(button)
			RequestEquipTitle:FireServer(def.id)
		end
	end)

	return { card = card, status = status, button = button }
end

function TitleFrame.create(parent: ScreenGui): Refs
	local backdrop = Instance.new("Frame")
	backdrop.Name = "TitleBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.DimBackdrop
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Visible = false
	backdrop.ZIndex = 5
	backdrop.Parent = parent

	local root = Instance.new("Frame")
	root.Name = "TitleFrame"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.new(0, 700, 0, 560)
	Theme.applyPanelStyle(root, Theme.Colors.Yellow)
	root.ZIndex = 6
	root.Parent = backdrop

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -16, 0, 40)
	header.Position = UDim2.new(0, 8, 0, 8)
	Theme.applyLabelStyle(header)
	header.Text = "TITLES"
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
	infoLabel.Text = "Current Title: Rookie"
	infoLabel.TextSize = 17
	infoLabel.TextScaled = false
	infoLabel.ZIndex = 7
	infoLabel.Parent = root

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "TitleList"
	scroll.Size = UDim2.new(1, -32, 1, -96)
	scroll.Position = UDim2.new(0, 16, 0, 86)
	scroll.BackgroundColor3 = Theme.Colors.PanelDark
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ZIndex = 7
	scroll.Parent = root

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius
	corner.Parent = scroll

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = scroll

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = scroll

	local cards = {}
	for _, def in ipairs(TitleConfig.Titles) do
		cards[def.id] = makeCard(scroll, def)
	end

	return { backdrop = backdrop, root = root, infoLabel = infoLabel, cards = cards }
end

function TitleFrame.show(refs: Refs)
	UIAnimator.framePopIn(refs.backdrop, refs.root)
end

function TitleFrame.update(refs: Refs, state)
	local titles = if type(state.Titles) == "table" then state.Titles else {}
	local equipped = state.EquippedTitle or "Rookie"
	local equippedDef = TitleConfig.getById(equipped)
	refs.infoLabel.Text = "Current Title: " .. (if equippedDef then equippedDef.displayName else "-")

	for _, def in ipairs(TitleConfig.Titles) do
		local card = refs.cards[def.id]
		if not card then
			continue
		end
		local owned = titles[def.id] == true
		local isEquipped = equipped == def.id
		if isEquipped then
			card.status.Text = "EQUIPPED"
			card.button.Text = "EQUIPPED"
			card.button.BackgroundColor3 = Theme.Colors.Yellow
			card.button:SetAttribute("Action", "None")
		elseif owned then
			card.status.Text = "UNLOCKED"
			card.button.Text = "EQUIP"
			card.button.BackgroundColor3 = Theme.Colors.Blue
			card.button:SetAttribute("Action", "Equip")
		else
			card.status.Text = "LOCKED"
			card.button.Text = "LOCKED"
			card.button.BackgroundColor3 = Theme.Colors.PanelMedium
			card.button:SetAttribute("Action", "None")
		end
	end
end

return TitleFrame
