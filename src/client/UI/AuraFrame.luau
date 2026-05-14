--!strict
-- Aura-Shop: scrollbare Liste mit allen Auren. Pro Karte: Name + Multiplier +
-- Aktions-Button (Kaufen/Ausruesten/Ablegen, abhaengig vom Status).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))
local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))

local Configs = ReplicatedStorage:WaitForChild("Configs")
local AuraConfig = require(Configs:WaitForChild("AuraConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestBuyAura = Remotes:WaitForChild("RequestBuyAura") :: RemoteEvent
local RequestEquipAura = Remotes:WaitForChild("RequestEquipAura") :: RemoteEvent

local AuraFrame = {}

type Refs = {
	backdrop: Frame,
	root: Frame,
	scroll: ScrollingFrame,
	infoLabel: TextLabel,
	cards: { [string]: { card: Frame, button: TextButton, status: TextLabel } },
}

local function makeCard(parent: ScrollingFrame, def): { card: Frame, button: TextButton, status: TextLabel }
	local card = Instance.new("Frame")
	card.Name = "Aura_" .. def.id
	card.Size = UDim2.new(1, 0, 0, 78)
	card.LayoutOrder = def.priceDna
	Theme.applyPanelStyle(card, def.color)
	card.ZIndex = 7
	card.Parent = parent

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(0, 220, 0, 32)
	name.Position = UDim2.new(0, 12, 0, 8)
	Theme.applyLabelStyle(name)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = def.displayName
	name.TextSize = 22
	name.TextScaled = false
	name.ZIndex = 8
	name.Parent = card

	local multi = Instance.new("TextLabel")
	multi.Size = UDim2.new(0, 220, 0, 28)
	multi.Position = UDim2.new(0, 12, 0, 42)
	Theme.applyLabelStyle(multi)
	multi.TextXAlignment = Enum.TextXAlignment.Left
	multi.Text = string.format("%.2gx Kraft", def.multiplier)
	multi.TextSize = 18
	multi.TextScaled = false
	multi.ZIndex = 8
	multi.Parent = card

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(1, 0)
	status.Size = UDim2.new(0, 200, 0, 28)
	status.Position = UDim2.new(1, -180, 0, 12)
	Theme.applyLabelStyle(status)
	status.TextXAlignment = Enum.TextXAlignment.Right
	status.Text = string.format("Preis: %s DNA", NumberFormatter.format(def.priceDna))
	status.TextSize = 16
	status.TextScaled = false
	status.ZIndex = 8
	status.Parent = card

	local button = Instance.new("TextButton")
	button.Name = "Action"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Size = UDim2.new(0, 160, 0, 50)
	button.Position = UDim2.new(1, -12, 0.5, 0)
	Theme.applyButtonStyle(button, Theme.Colors.Green)
	button.Text = "KAUFEN"
	button.TextSize = 18
	button.TextScaled = false
	button.ZIndex = 9
	button.Parent = card

	return { card = card, button = button, status = status }
end

function AuraFrame.create(parent: ScreenGui): Refs
	local backdrop = Instance.new("Frame")
	backdrop.Name = "AuraBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.DimBackdrop
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Visible = false
	backdrop.ZIndex = 5
	backdrop.Parent = parent

	local root = Instance.new("Frame")
	root.Name = "AuraFrame"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.new(0, 640, 0, 520)
	Theme.applyPanelStyle(root, Theme.Colors.Purple)
	root.ZIndex = 6
	root.Parent = backdrop

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -16, 0, 40)
	header.Position = UDim2.new(0, 8, 0, 8)
	Theme.applyLabelStyle(header)
	header.Text = "AUREN"
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
	infoLabel.Text = "DNA: 0  |  Aktuelle Aura: -"
	infoLabel.TextSize = 16
	infoLabel.TextScaled = false
	infoLabel.ZIndex = 7
	infoLabel.Parent = root

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "AuraList"
	scroll.Size = UDim2.new(1, -32, 1, -100)
	scroll.Position = UDim2.new(0, 16, 0, 88)
	scroll.BackgroundColor3 = Theme.Colors.PanelDark
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ZIndex = 7
	scroll.Parent = root

	local scrollCorner = Instance.new("UICorner")
	scrollCorner.CornerRadius = Theme.CornerRadius
	scrollCorner.Parent = scroll

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

	-- Eine Karte je Aura, statisch erzeugt.
	local cards: { [string]: { card: Frame, button: TextButton, status: TextLabel } } = {}
	for _, def in ipairs(AuraConfig.Auras) do
		local refs = makeCard(scroll, def)
		cards[def.id] = refs

		refs.button.MouseButton1Click:Connect(function()
			UIAnimator.buttonPunch(refs.button)
			-- Aktion entscheidet sich anhand des aktuellen Button-Tags, das in
			-- update() gesetzt wird.
			local action = refs.button:GetAttribute("Action")
			if action == "Buy" then
				RequestBuyAura:FireServer(def.id)
			elseif action == "Equip" then
				RequestEquipAura:FireServer(def.id)
			elseif action == "Unequip" then
				RequestEquipAura:FireServer(nil)
			end
		end)
	end

	return {
		backdrop = backdrop,
		root = root,
		scroll = scroll,
		infoLabel = infoLabel,
		cards = cards,
	}
end

function AuraFrame.show(refs: Refs)
	UIAnimator.framePopIn(refs.backdrop, refs.root)
end

function AuraFrame.update(refs: Refs, state)
	local auras = if type(state.Auras) == "table" then state.Auras else {}
	local equipped = state.EquippedAura
	local dna = state.DnaCoins or 0

	local equippedName = "-"
	if equipped then
		local def = AuraConfig.getById(equipped)
		if def then
			equippedName = def.displayName
		end
	end
	refs.infoLabel.Text = string.format(
		"DNA: %s  |  Aktuelle Aura: %s",
		NumberFormatter.format(dna),
		equippedName
	)

	for _, def in ipairs(AuraConfig.Auras) do
		local cardRefs = refs.cards[def.id]
		if not cardRefs then
			continue
		end
		local owned = auras[def.id] == true
		local isEquipped = equipped == def.id
		local btn = cardRefs.button
		local status = cardRefs.status

		if isEquipped then
			btn.Text = "ABLEGEN"
			btn.BackgroundColor3 = Theme.Colors.Red
			btn:SetAttribute("Action", "Unequip")
			status.Text = "Ausgeruestet"
		elseif owned then
			btn.Text = "AUSRUESTEN"
			btn.BackgroundColor3 = Theme.Colors.Blue
			btn:SetAttribute("Action", "Equip")
			status.Text = "Gekauft"
		else
			btn.Text = "KAUFEN"
			btn.BackgroundColor3 = if dna >= def.priceDna then Theme.Colors.Green else Theme.Colors.PanelMedium
			btn:SetAttribute("Action", "Buy")
			status.Text = string.format("Preis: %s DNA", NumberFormatter.format(def.priceDna))
		end
	end
end

return AuraFrame
