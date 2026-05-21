--!strict
-- Aura-Shop: scrollbare Liste mit allen Auren. Pro Karte: Name + Multiplier +
-- Aktions-Button (Kaufen/Ausruesten/Ablegen, abhaengig vom Status).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local LabTheme = require(script.Parent:WaitForChild("LabTheme"))
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
	nextLabel: TextLabel,
	cards: { [string]: { card: Frame, button: TextButton, status: TextLabel } },
}

local function makeCard(parent: ScrollingFrame, def): { card: Frame, button: TextButton, status: TextLabel }
	local card = Instance.new("Frame")
	card.Name = "Aura_" .. def.id
	card.Size = UDim2.new(1, 0, 0, 78)
	card.LayoutOrder = def.requiredTier * 100
	Theme.applyPanelStyle(card, LabTheme.Colors.Card)
	LabTheme.styleCard(card, def.color)
	LabTheme.bindHoverPopout(card, 1.018)
	card.ZIndex = 7
	card.Parent = parent

	local preview = Instance.new("Frame")
	preview.Name = "AuraPreview"
	preview.Size = UDim2.new(0, 42, 0, 42)
	preview.Position = UDim2.new(0, 12, 0.5, -21)
	preview.BackgroundColor3 = def.color
	preview.BackgroundTransparency = 0.12
	preview.BorderSizePixel = 0
	preview.ZIndex = 8
	preview.Parent = card
	local previewCorner = Instance.new("UICorner")
	previewCorner.CornerRadius = UDim.new(1, 0)
	previewCorner.Parent = preview
	local previewStroke = Instance.new("UIStroke")
	previewStroke.Color = def.color:Lerp(LabTheme.Colors.Text, 0.35)
	previewStroke.Thickness = 1.2
	previewStroke.Transparency = 0.2
	previewStroke.Parent = preview

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(0, 220, 0, 32)
	name.Position = UDim2.new(0, 66, 0, 8)
	Theme.applyLabelStyle(name)
	LabTheme.styleLabel(name, LabTheme.Colors.Text, 22, true)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = def.displayName
	name.TextSize = 22
	name.TextScaled = false
	name.ZIndex = 8
	name.Parent = card

	local multi = Instance.new("TextLabel")
	multi.Size = UDim2.new(0, 220, 0, 28)
	multi.Position = UDim2.new(0, 66, 0, 42)
	Theme.applyLabelStyle(multi)
	LabTheme.styleLabel(multi, def.color:Lerp(LabTheme.Colors.Text, 0.35), 18, true)
	multi.TextXAlignment = Enum.TextXAlignment.Left
	multi.Text = string.format("Tier %d  |  %.3gx Power", def.requiredTier, def.multiplier)
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
	LabTheme.styleLabel(status, LabTheme.Colors.SubText, 16, false)
	status.TextXAlignment = Enum.TextXAlignment.Right
	status.Text = string.format("Price: %s DNA", NumberFormatter.format(def.priceDna))
	status.TextSize = 16
	status.TextScaled = false
	status.ZIndex = 8
	status.Parent = card

	local button = Instance.new("TextButton")
	button.Name = "Action"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Size = UDim2.new(0, 160, 0, 50)
	button.Position = UDim2.new(1, -12, 0.5, 0)
	Theme.applyButtonStyle(button, LabTheme.Colors.Green)
	LabTheme.styleButton(button, LabTheme.Colors.Green, true)
	LabTheme.bindButtonFeedback(button, LabTheme.Colors.Green)
	button.Text = "BUY"
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
	LabTheme.styleBackdrop(backdrop)

	local root = Instance.new("Frame")
	root.Name = "AuraFrame"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.new(0, 640, 0, 520)
	Theme.applyPanelStyle(root, LabTheme.Colors.Base)
	LabTheme.styleModal(root, Color3.fromRGB(132, 116, 170))
	root.ZIndex = 6
	root.Parent = backdrop

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -16, 0, 40)
	header.Position = UDim2.new(0, 8, 0, 8)
	Theme.applyLabelStyle(header)
	LabTheme.styleLabel(header, LabTheme.Colors.Text, 28, true)
	header.Text = "AURA STABILIZER"
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
	infoLabel.Text = "DNA: 0  |  Current Aura: -  |  Unlocked Tier: 1 / 10"
	infoLabel.TextSize = 16
	infoLabel.TextScaled = false
	infoLabel.ZIndex = 7
	infoLabel.Parent = root

	local nextLabel = Instance.new("TextLabel")
	nextLabel.Size = UDim2.new(1, -32, 0, 24)
	nextLabel.Position = UDim2.new(0, 16, 0, 78)
	Theme.applyLabelStyle(nextLabel)
	LabTheme.styleLabel(nextLabel, LabTheme.Colors.Muted, 14, false)
	nextLabel.Text = ""
	nextLabel.TextXAlignment = Enum.TextXAlignment.Left
	nextLabel.TextSize = 14
	nextLabel.TextScaled = false
	nextLabel.ZIndex = 7
	nextLabel.Parent = root

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "AuraList"
	scroll.Size = UDim2.new(1, -32, 1, -126)
	scroll.Position = UDim2.new(0, 16, 0, 114)
	scroll.BackgroundColor3 = LabTheme.Colors.Panel
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ZIndex = 7
	scroll.Parent = root
	LabTheme.styleScroll(scroll)

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
		nextLabel = nextLabel,
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
	local unlockedTier = AuraConfig.getUnlockedTier(state.HighestBossDefeated)

	local equippedName = "-"
	if equipped then
		local def = AuraConfig.getById(equipped)
		if def then
			equippedName = def.displayName
		end
	end
	refs.infoLabel.Text = string.format(
		"DNA: %s  |  Current Aura: %s  |  Unlocked Tier: %d / %d",
		NumberFormatter.format(dna),
		equippedName,
		unlockedTier,
		AuraConfig.MaxTier
	)
	if unlockedTier < AuraConfig.MaxTier then
		refs.nextLabel.Text = "Next Tier locked: Beat Area " .. tostring(unlockedTier) .. " Boss to unlock"
	else
		refs.nextLabel.Text = "Max aura tier unlocked."
	end

	for index, def in ipairs(AuraConfig.Auras) do
		local cardRefs = refs.cards[def.id]
		if not cardRefs then
			continue
		end
		local owned = auras[def.id] == true
		if not owned and def.legacyIds then
			for _, legacyId in ipairs(def.legacyIds) do
				if auras[legacyId] == true then
					owned = true
					break
				end
			end
		end
		local isEquipped = AuraConfig.matchesId(def, equipped)
		local isCurrentTier = def.requiredTier == unlockedTier
		local isNextTier = def.requiredTier == unlockedTier + 1
		local showCard = owned or isCurrentTier or isNextTier
		local btn = cardRefs.button
		local status = cardRefs.status
		cardRefs.card.Visible = showCard
		cardRefs.card.Size = if showCard then UDim2.new(1, 0, 0, 78) else UDim2.new(1, 0, 0, 0)
		cardRefs.card.LayoutOrder = if isCurrentTier then index elseif owned then 1000 + index else 2000 + index
		cardRefs.card.BackgroundTransparency = if isNextTier and not owned then 0.34 else 0

		if isEquipped then
			btn.Text = "EQUIPPED"
			LabTheme.styleButton(btn, LabTheme.Colors.Green, true)
			btn:SetAttribute("Action", "Unequip")
			status.Text = "Equipped"
			status.TextColor3 = LabTheme.Colors.Green
			LabTheme.styleCard(cardRefs.card, def.color)
		elseif owned then
			btn.Text = "EQUIP"
			LabTheme.styleButton(btn, LabTheme.Colors.Cyan, true)
			btn:SetAttribute("Action", "Equip")
			status.Text = "Owned"
			status.TextColor3 = LabTheme.Colors.Cyan
		elseif def.requiredTier > unlockedTier then
			btn.Text = "LOCKED"
			LabTheme.styleButton(btn, LabTheme.Colors.Muted, false)
			btn:SetAttribute("Action", "Locked")
			status.Text = AuraConfig.getLockedText(def)
			status.TextColor3 = LabTheme.Colors.Gold
			LabTheme.styleCard(cardRefs.card, def.color, true)
		else
			btn.Text = if dna >= def.priceDna then "BUY" else "Need " .. NumberFormatter.format(def.priceDna) .. " DNA"
			LabTheme.styleButton(btn, LabTheme.Colors.Green, dna >= def.priceDna)
			btn:SetAttribute("Action", "Buy")
			status.Text = string.format("Price: %s DNA", NumberFormatter.format(def.priceDna))
			status.TextColor3 = if dna >= def.priceDna then LabTheme.Colors.Gold else LabTheme.Colors.Muted
		end
	end
end

return AuraFrame
