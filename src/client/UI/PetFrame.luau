--!strict
-- Pet-Inventar-Fenster: Grid mit Pet-Karten, Equip/Unequip pro Karte,
-- Buttons "Bestes Ausruesten" und "Alle Ablegen", Inventory-/Equipped-Counter.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))

local Configs = ReplicatedStorage:WaitForChild("Configs")
local PetConfig = require(Configs:WaitForChild("PetConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestEquipPet = Remotes:WaitForChild("RequestEquipPet") :: RemoteEvent
local RequestUnequipPet = Remotes:WaitForChild("RequestUnequipPet") :: RemoteEvent

local PetFrame = {}

type Refs = {
	backdrop: Frame,
	root: Frame,
	countLabel: TextLabel,
	multLabel: TextLabel,
	scroll: ScrollingFrame,
	bestButton: TextButton,
	unequipAllButton: TextButton,
}

local CARD_SIZE = Vector2.new(140, 110)

local function buildCard(parent: ScrollingFrame, instanceId: string, def, equipped: boolean): Frame
	local rarityColor = PetConfig.RarityColor[def.rarity] or Theme.Colors.White

	local card = Instance.new("Frame")
	card.Name = "Pet_" .. instanceId
	card.Size = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y)
	Theme.applyPanelStyle(card, rarityColor)
	card.ZIndex = 7
	card.Parent = parent

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -8, 0, 22)
	name.Position = UDim2.new(0, 4, 0, 4)
	Theme.applyLabelStyle(name)
	name.Text = def.displayName
	name.TextSize = 14
	name.TextScaled = false
	name.ZIndex = 8
	name.Parent = card

	local rarity = Instance.new("TextLabel")
	rarity.Size = UDim2.new(1, -8, 0, 18)
	rarity.Position = UDim2.new(0, 4, 0, 28)
	Theme.applyLabelStyle(rarity)
	rarity.Text = def.rarity
	rarity.TextSize = 12
	rarity.TextScaled = false
	rarity.ZIndex = 8
	rarity.Parent = card

	local multi = Instance.new("TextLabel")
	multi.Size = UDim2.new(1, -8, 0, 24)
	multi.Position = UDim2.new(0, 4, 0, 48)
	Theme.applyLabelStyle(multi)
	multi.Text = string.format("%.2gx", def.multiplier)
	multi.TextSize = 18
	multi.TextScaled = false
	multi.ZIndex = 8
	multi.Parent = card

	local action = Instance.new("TextButton")
	action.Name = "Action"
	action.Size = UDim2.new(1, -8, 0, 28)
	action.Position = UDim2.new(0, 4, 1, -32)
	Theme.applyButtonStyle(action, if equipped then Theme.Colors.Red else Theme.Colors.Green)
	action.Text = if equipped then "UNEQUIP" else "EQUIP"
	action.TextSize = 14
	action.TextScaled = false
	action.ZIndex = 9
	action.Parent = card

	action.MouseButton1Click:Connect(function()
		UIAnimator.buttonPunch(action)
		if equipped then
			RequestUnequipPet:FireServer(instanceId)
		else
			RequestEquipPet:FireServer(instanceId)
		end
	end)

	return card
end

function PetFrame.create(parent: ScreenGui): Refs
	local backdrop = Instance.new("Frame")
	backdrop.Name = "PetBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.DimBackdrop
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Visible = false
	backdrop.ZIndex = 5
	backdrop.Parent = parent

	local root = Instance.new("Frame")
	root.Name = "PetFrame"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.new(0, 640, 0, 480)
	Theme.applyPanelStyle(root, Theme.Colors.Blue)
	root.ZIndex = 6
	root.Parent = backdrop

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -16, 0, 40)
	header.Position = UDim2.new(0, 8, 0, 8)
	Theme.applyLabelStyle(header)
	header.Text = "PETS"
	header.TextSize = 26
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

	-- Info-Zeile: Inventar / Equipped / Pet-Multiplier.
	local infoRow = Instance.new("Frame")
	infoRow.Size = UDim2.new(1, -32, 0, 28)
	infoRow.Position = UDim2.new(0, 16, 0, 52)
	infoRow.BackgroundTransparency = 1
	infoRow.ZIndex = 7
	infoRow.Parent = root

	local countLabel = Instance.new("TextLabel")
	countLabel.Size = UDim2.new(0.5, -4, 1, 0)
	countLabel.Position = UDim2.new(0, 0, 0, 0)
	Theme.applyLabelStyle(countLabel)
	countLabel.TextXAlignment = Enum.TextXAlignment.Left
	countLabel.Text = "0/50 Inventory  |  0/3 Equipped"
	countLabel.TextSize = 16
	countLabel.TextScaled = false
	countLabel.ZIndex = 8
	countLabel.Parent = infoRow

	local multLabel = Instance.new("TextLabel")
	multLabel.Size = UDim2.new(0.5, -4, 1, 0)
	multLabel.Position = UDim2.new(0.5, 4, 0, 0)
	Theme.applyLabelStyle(multLabel)
	multLabel.TextXAlignment = Enum.TextXAlignment.Right
	multLabel.Text = "Pet Multiplier: 1x"
	multLabel.TextSize = 16
	multLabel.TextScaled = false
	multLabel.ZIndex = 8
	multLabel.Parent = infoRow

	-- Aktions-Buttons (Best / All).
	local actionRow = Instance.new("Frame")
	actionRow.Size = UDim2.new(1, -32, 0, 44)
	actionRow.Position = UDim2.new(0, 16, 0, 86)
	actionRow.BackgroundTransparency = 1
	actionRow.ZIndex = 7
	actionRow.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, 8)
	layout.Parent = actionRow

	local bestButton = Instance.new("TextButton")
	bestButton.Size = UDim2.new(0, 200, 1, 0)
	bestButton.Text = "EQUIP BEST"
	Theme.applyButtonStyle(bestButton, Theme.Colors.Green)
	bestButton.TextSize = 16
	bestButton.TextScaled = false
	bestButton.ZIndex = 8
	bestButton.Parent = actionRow

	local unequipAllButton = Instance.new("TextButton")
	unequipAllButton.Size = UDim2.new(0, 180, 1, 0)
	unequipAllButton.Text = "UNEQUIP ALL"
	Theme.applyButtonStyle(unequipAllButton, Theme.Colors.Red)
	unequipAllButton.TextSize = 16
	unequipAllButton.TextScaled = false
	unequipAllButton.ZIndex = 8
	unequipAllButton.Parent = actionRow

	bestButton.MouseButton1Click:Connect(function()
		UIAnimator.buttonPunch(bestButton)
		RequestEquipPet:FireServer("BEST")
	end)
	unequipAllButton.MouseButton1Click:Connect(function()
		UIAnimator.buttonPunch(unequipAllButton)
		RequestUnequipPet:FireServer("ALL")
	end)

	-- Scroll-Bereich fuer Pet-Karten.
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "PetGrid"
	scroll.Size = UDim2.new(1, -32, 1, -148)
	scroll.Position = UDim2.new(0, 16, 0, 140)
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

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	grid.Parent = scroll

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = scroll

	return {
		backdrop = backdrop,
		root = root,
		countLabel = countLabel,
		multLabel = multLabel,
		scroll = scroll,
		bestButton = bestButton,
		unequipAllButton = unequipAllButton,
	}
end

function PetFrame.show(refs: Refs)
	UIAnimator.framePopIn(refs.backdrop, refs.root)
end

local function isEquipped(equippedList: { string }?, instanceId: string): boolean
	if type(equippedList) ~= "table" then
		return false
	end
	for _, id in ipairs(equippedList) do
		if id == instanceId then
			return true
		end
	end
	return false
end

function PetFrame.update(refs: Refs, state)
	local pets = if type(state.Pets) == "table" then state.Pets else {}
	local equipped = if type(state.EquippedPets) == "table" then state.EquippedPets else {}
	local petMult = state.PetMultiplier or 1

	-- Counter aktualisieren.
	local petCount = 0
	for _ in pairs(pets) do
		petCount += 1
	end
	refs.countLabel.Text = string.format(
		"%d/%d Inventory  |  %d/%d Equipped",
		petCount,
		PetConfig.MaxInventorySize,
		#equipped,
		PetConfig.MaxEquipped
	)
	refs.multLabel.Text = string.format("Pet Multiplier: %.3gx", petMult)

	-- Cards neu rendern.
	for _, child in ipairs(refs.scroll:GetChildren()) do
		if child:IsA("Frame") and child.Name:sub(1, 4) == "Pet_" then
			child:Destroy()
		end
	end

	-- Sortierte Liste: Equipped zuerst, dann nach Multiplier absteigend.
	local sorted = {}
	for instanceId, entry in pairs(pets) do
		local def = PetConfig.getById(entry.id)
		if def then
			table.insert(sorted, {
				instanceId = instanceId,
				def = def,
				equipped = isEquipped(equipped, instanceId),
			})
		end
	end
	table.sort(sorted, function(a, b)
		if a.equipped ~= b.equipped then
			return a.equipped
		end
		return a.def.multiplier > b.def.multiplier
	end)

	for _, entry in ipairs(sorted) do
		buildCard(refs.scroll, entry.instanceId, entry.def, entry.equipped)
	end
end

return PetFrame
