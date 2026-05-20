--!strict
-- Pet hatch + inventory window. Extends the existing pet inventory instead of
-- creating a parallel UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))
local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))

local Configs = ReplicatedStorage:WaitForChild("Configs")
local PetConfig = require(Configs:WaitForChild("PetConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestEquipPet = Remotes:WaitForChild("RequestEquipPet") :: RemoteEvent
local RequestUnequipPet = Remotes:WaitForChild("RequestUnequipPet") :: RemoteEvent
local RequestHatchPetEgg = Remotes:WaitForChild("RequestHatchPetEgg") :: RemoteEvent
local OpenPetEggShop = Remotes:WaitForChild("OpenPetEggShop") :: RemoteEvent
local HatchPetResult = Remotes:WaitForChild("HatchPetResult") :: RemoteEvent

local PetFrame = {}

type Refs = {
	backdrop: Frame,
	root: Frame,
	eggScroll: ScrollingFrame,
	eggNameLabel: TextLabel,
	eggReqLabel: TextLabel,
	eggCostLabel: TextLabel,
	eggChanceLabel: TextLabel,
	hatchButton: TextButton,
	resultPanel: Frame,
	resultNameLabel: TextLabel,
	resultRarityLabel: TextLabel,
	resultMultiplierLabel: TextLabel,
	countLabel: TextLabel,
	multLabel: TextLabel,
	scroll: ScrollingFrame,
	bestButton: TextButton,
	unequipAllButton: TextButton,
	selectedEggId: string?,
	lastState: { [string]: any }?,
}

local PET_CARD_SIZE = Vector2.new(136, 104)
local EGG_CARD_SIZE = Vector2.new(158, 72)

local function petMultiplier(def): number
	local value = if def then (def.powerMultiplier or def.multiplier or 1) else 1
	return if type(value) == "number" then value else 1
end

local function rarityColor(rarity: string?): Color3
	if rarity and PetConfig.RarityColor[rarity] then
		return PetConfig.RarityColor[rarity]
	end
	return Theme.Colors.White
end

local function richColor(color: Color3): string
	return string.format(
		"rgb(%d,%d,%d)",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5)
	)
end

local function makeSmallLabel(parent: Instance, text: string, pos: UDim2, size: UDim2, textSize: number, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.Position = pos
	label.Size = size
	Theme.applyLabelStyle(label)
	label.Text = text
	label.TextSize = textSize
	label.TextScaled = false
	label.TextColor3 = color or Theme.Colors.White
	label.ZIndex = 8
	label.Parent = parent
	return label
end

local function eggRequirementText(egg): string
	local parts = {}
	if egg.requiredPower and egg.requiredPower > 0 then
		table.insert(parts, NumberFormatter.format(egg.requiredPower) .. " PWR")
	end
	if egg.requiredRebirth and egg.requiredRebirth > 0 then
		table.insert(parts, "Rebirth " .. tostring(egg.requiredRebirth))
	end
	return if #parts > 0 then table.concat(parts, " + ") else "Unlocked"
end

local function canAccessEgg(state, egg): boolean
	local power = state.Power or 0
	local rebirths = state.Rebirths or 0
	return power >= (egg.requiredPower or 0) and rebirths >= (egg.requiredRebirth or 0)
end

local function rarityChanceText(): string
	local parts = {}
	for _, entry in ipairs(PetConfig.RarityChances) do
		local color = richColor(rarityColor(entry.rarity))
		table.insert(parts, string.format("<font color=\"%s\">%s %.1f%%</font>", color, entry.rarity, entry.chance))
	end
	return table.concat(parts, "  |  ")
end

local function getSortedEggs()
	if PetConfig.getSortedEggs then
		return PetConfig.getSortedEggs()
	end
	return PetConfig.Eggs
end

local function chooseEggForArea(state, areaIndex: number): string?
	local firstMatching = nil
	for _, egg in ipairs(getSortedEggs()) do
		if egg.areaIndex == areaIndex then
			firstMatching = firstMatching or egg
			if canAccessEgg(state or {}, egg) then
				return egg.id
			end
		end
	end
	return firstMatching and firstMatching.id or nil
end

local function findSelectedEgg(refs: Refs)
	if refs.selectedEggId then
		local selected = PetConfig.getEggById(refs.selectedEggId)
		if selected then
			return selected
		end
	end
	local fallback = PetConfig.getEggById(PetConfig.DefaultEggId) or PetConfig.Eggs[1]
	if fallback then
		refs.selectedEggId = fallback.id
	end
	return fallback
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

local function buildEggCard(parent: ScrollingFrame, refs: Refs, egg, state): TextButton
	local unlocked = canAccessEgg(state, egg)
	local selected = refs.selectedEggId == egg.id
	local accent = egg.color
	local titleColor = if unlocked then accent else accent:Lerp(Color3.fromRGB(125, 125, 135), 0.45)
	local cardColor = if selected then accent:Lerp(Color3.fromRGB(18, 22, 32), 0.35) else Color3.fromRGB(31, 38, 52)
	if not unlocked then
		cardColor = if selected then Color3.fromRGB(72, 56, 62) else Color3.fromRGB(35, 36, 44)
	end

	local card = Instance.new("TextButton")
	card.Name = "Egg_" .. egg.id
	card.LayoutOrder = if PetConfig.getEggSortOrder then PetConfig.getEggSortOrder(egg) else egg.areaIndex
	card.Size = UDim2.fromOffset(EGG_CARD_SIZE.X, EGG_CARD_SIZE.Y)
	card.Text = ""
	Theme.applyButtonStyle(card, cardColor)
	card.TextScaled = false
	card.ZIndex = 7
	card.Parent = parent

	makeSmallLabel(card, egg.tier .. " Egg", UDim2.new(0, 6, 0, 5), UDim2.new(1, -12, 0, 18), 12, titleColor)
	local area = makeSmallLabel(card, egg.areaDisplayName, UDim2.new(0, 6, 0, 23), UDim2.new(1, -12, 0, 16), 11)
	area.TextXAlignment = Enum.TextXAlignment.Left
	local cost = makeSmallLabel(card, NumberFormatter.format(egg.cost) .. " DNA", UDim2.new(0, 6, 0, 41), UDim2.new(1, -12, 0, 14), 11, Theme.Colors.Yellow)
	cost.TextXAlignment = Enum.TextXAlignment.Left
	local status = makeSmallLabel(
		card,
		if unlocked then (if selected then "SELECTED" else "OPEN") else "LOCKED",
		UDim2.new(0, 6, 0, 56),
		UDim2.new(1, -12, 0, 13),
		10,
		if unlocked then Theme.Colors.Green else Theme.Colors.Red
	)
	status.TextXAlignment = Enum.TextXAlignment.Left

	card.MouseButton1Click:Connect(function()
		refs.selectedEggId = egg.id
		if refs.lastState then
			PetFrame.update(refs, refs.lastState)
		end
	end)

	return card
end

local function buildPetCard(parent: ScrollingFrame, instanceId: string, def, equipped: boolean): Frame
	local petColor = rarityColor(def.rarity)

	local card = Instance.new("Frame")
	card.Name = "Pet_" .. instanceId
	card.LayoutOrder = (if equipped then 0 else 100000) - math.floor(petMultiplier(def) * 1000)
	card.Size = UDim2.fromOffset(PET_CARD_SIZE.X, PET_CARD_SIZE.Y)
	Theme.applyPanelStyle(card, petColor)
	card.ZIndex = 7
	card.Parent = parent

	local name = makeSmallLabel(card, def.displayName, UDim2.new(0, 4, 0, 4), UDim2.new(1, -8, 0, 20), 13)
	name.TextXAlignment = Enum.TextXAlignment.Center

	local rarity = makeSmallLabel(card, def.rarity, UDim2.new(0, 4, 0, 26), UDim2.new(1, -8, 0, 16), 11, petColor)
	rarity.TextXAlignment = Enum.TextXAlignment.Center

	local multi = makeSmallLabel(card, string.format("%.2gx Power", petMultiplier(def)), UDim2.new(0, 4, 0, 45), UDim2.new(1, -8, 0, 22), 16)
	multi.TextXAlignment = Enum.TextXAlignment.Center

	local action = Instance.new("TextButton")
	action.Name = "Action"
	action.Size = UDim2.new(1, -8, 0, 26)
	action.Position = UDim2.new(0, 4, 1, -30)
	Theme.applyButtonStyle(action, if equipped then Theme.Colors.Red else Theme.Colors.Green)
	action.Text = if equipped then "UNEQUIP" else "EQUIP"
	action.TextSize = 13
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
	root.Size = UDim2.new(0, 760, 0, 560)
	Theme.applyPanelStyle(root, Theme.Colors.Blue)
	root.ZIndex = 6
	root.Parent = backdrop

	local header = makeSmallLabel(root, "PETS & EGGS", UDim2.new(0, 8, 0, 8), UDim2.new(1, -16, 0, 34), 26)
	header.TextXAlignment = Enum.TextXAlignment.Center

	local closeButton = Instance.new("TextButton")
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -8, 0, 8)
	closeButton.Size = UDim2.new(0, 36, 0, 36)
	closeButton.Text = "X"
	Theme.applyButtonStyle(closeButton, Theme.Colors.Red)
	closeButton.TextSize = 22
	closeButton.TextScaled = false
	closeButton.ZIndex = 9
	closeButton.Parent = root
	closeButton.MouseButton1Click:Connect(function()
		UIAnimator.framePopOut(backdrop, root)
	end)

	local eggPanel = Instance.new("Frame")
	eggPanel.Name = "EggPanel"
	eggPanel.Size = UDim2.new(1, -32, 0, 166)
	eggPanel.Position = UDim2.new(0, 16, 0, 52)
	Theme.applyPanelStyle(eggPanel, Color3.fromRGB(24, 28, 42))
	eggPanel.ZIndex = 7
	eggPanel.Parent = root

	local eggScroll = Instance.new("ScrollingFrame")
	eggScroll.Name = "EggGrid"
	eggScroll.Size = UDim2.new(0, 360, 1, -16)
	eggScroll.Position = UDim2.new(0, 8, 0, 8)
	eggScroll.BackgroundColor3 = Theme.Colors.PanelDark
	eggScroll.BorderSizePixel = 0
	eggScroll.ScrollBarThickness = 8
	eggScroll.CanvasSize = UDim2.fromOffset(0, 0)
	eggScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	eggScroll.ZIndex = 7
	eggScroll.Parent = eggPanel
	local eggCorner = Instance.new("UICorner")
	eggCorner.CornerRadius = Theme.CornerRadius
	eggCorner.Parent = eggScroll
	local eggGrid = Instance.new("UIGridLayout")
	eggGrid.CellSize = UDim2.fromOffset(EGG_CARD_SIZE.X, EGG_CARD_SIZE.Y)
	eggGrid.CellPadding = UDim2.fromOffset(8, 8)
	eggGrid.SortOrder = Enum.SortOrder.LayoutOrder
	eggGrid.Parent = eggScroll
	local eggPad = Instance.new("UIPadding")
	eggPad.PaddingTop = UDim.new(0, 8)
	eggPad.PaddingLeft = UDim.new(0, 8)
	eggPad.PaddingRight = UDim.new(0, 8)
	eggPad.PaddingBottom = UDim.new(0, 8)
	eggPad.Parent = eggScroll

	local eggNameLabel = makeSmallLabel(eggPanel, "Select an egg", UDim2.new(0, 384, 0, 10), UDim2.new(1, -400, 0, 24), 18)
	eggNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	local eggReqLabel = makeSmallLabel(eggPanel, "Requirement: -", UDim2.new(0, 384, 0, 38), UDim2.new(1, -400, 0, 20), 13, Color3.fromRGB(200, 230, 235))
	eggReqLabel.TextXAlignment = Enum.TextXAlignment.Left
	local eggCostLabel = makeSmallLabel(eggPanel, "Cost: -", UDim2.new(0, 384, 0, 62), UDim2.new(1, -400, 0, 20), 13, Theme.Colors.Yellow)
	eggCostLabel.TextXAlignment = Enum.TextXAlignment.Left
	local eggChanceLabel = makeSmallLabel(eggPanel, rarityChanceText(), UDim2.new(0, 384, 0, 88), UDim2.new(1, -400, 0, 34), 11, Color3.fromRGB(190, 210, 220))
	eggChanceLabel.RichText = true
	eggChanceLabel.TextWrapped = true
	eggChanceLabel.TextXAlignment = Enum.TextXAlignment.Left

	local hatchButton = Instance.new("TextButton")
	hatchButton.Name = "HatchButton"
	hatchButton.Size = UDim2.new(0, 170, 0, 34)
	hatchButton.Position = UDim2.new(0, 384, 1, -42)
	hatchButton.Text = "HATCH"
	Theme.applyButtonStyle(hatchButton, Theme.Colors.Green)
	hatchButton.TextSize = 16
	hatchButton.TextScaled = false
	hatchButton.ZIndex = 8
	hatchButton.Parent = eggPanel

	local resultPanel = Instance.new("Frame")
	resultPanel.Name = "HatchResultPanel"
	resultPanel.Size = UDim2.new(1, -566, 0, 54)
	resultPanel.Position = UDim2.new(0, 564, 1, -62)
	Theme.applyPanelStyle(resultPanel, Color3.fromRGB(18, 23, 32))
	resultPanel.Visible = false
	resultPanel.ZIndex = 8
	resultPanel.Parent = eggPanel

	local resultNameLabel = makeSmallLabel(resultPanel, "New Pet", UDim2.new(0, 8, 0, 5), UDim2.new(1, -16, 0, 18), 14)
	resultNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	local resultRarityLabel = makeSmallLabel(resultPanel, "Rarity", UDim2.new(0, 8, 0, 24), UDim2.new(0.5, -8, 0, 16), 12, Theme.Colors.Green)
	resultRarityLabel.TextXAlignment = Enum.TextXAlignment.Left
	local resultMultiplierLabel = makeSmallLabel(resultPanel, "1x Power", UDim2.new(0.5, 0, 0, 24), UDim2.new(0.5, -8, 0, 16), 12, Theme.Colors.Yellow)
	resultMultiplierLabel.TextXAlignment = Enum.TextXAlignment.Right

	local infoRow = Instance.new("Frame")
	infoRow.Size = UDim2.new(1, -32, 0, 28)
	infoRow.Position = UDim2.new(0, 16, 0, 226)
	infoRow.BackgroundTransparency = 1
	infoRow.ZIndex = 7
	infoRow.Parent = root

	local countLabel = makeSmallLabel(infoRow, "0/100 Inventory  |  0/2 Equipped", UDim2.new(0, 0, 0, 0), UDim2.new(0.5, -4, 1, 0), 15)
	countLabel.TextXAlignment = Enum.TextXAlignment.Left

	local multLabel = makeSmallLabel(infoRow, "Pet Power: 1x", UDim2.new(0.5, 4, 0, 0), UDim2.new(0.5, -4, 1, 0), 15)
	multLabel.TextXAlignment = Enum.TextXAlignment.Right

	local actionRow = Instance.new("Frame")
	actionRow.Size = UDim2.new(1, -32, 0, 40)
	actionRow.Position = UDim2.new(0, 16, 0, 260)
	actionRow.BackgroundTransparency = 1
	actionRow.ZIndex = 7
	actionRow.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, 8)
	layout.Parent = actionRow

	local bestButton = Instance.new("TextButton")
	bestButton.Size = UDim2.new(0, 190, 1, 0)
	bestButton.Text = "EQUIP BEST"
	Theme.applyButtonStyle(bestButton, Theme.Colors.Green)
	bestButton.TextSize = 15
	bestButton.TextScaled = false
	bestButton.ZIndex = 8
	bestButton.Parent = actionRow

	local unequipAllButton = Instance.new("TextButton")
	unequipAllButton.Size = UDim2.new(0, 170, 1, 0)
	unequipAllButton.Text = "UNEQUIP ALL"
	Theme.applyButtonStyle(unequipAllButton, Theme.Colors.Red)
	unequipAllButton.TextSize = 15
	unequipAllButton.TextScaled = false
	unequipAllButton.ZIndex = 8
	unequipAllButton.Parent = actionRow

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "PetGrid"
	scroll.Size = UDim2.new(1, -32, 1, -318)
	scroll.Position = UDim2.new(0, 16, 0, 308)
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
	grid.CellSize = UDim2.fromOffset(PET_CARD_SIZE.X, PET_CARD_SIZE.Y)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = scroll

	local refs: Refs = {
		backdrop = backdrop,
		root = root,
		eggScroll = eggScroll,
		eggNameLabel = eggNameLabel,
		eggReqLabel = eggReqLabel,
		eggCostLabel = eggCostLabel,
		eggChanceLabel = eggChanceLabel,
		hatchButton = hatchButton,
		resultPanel = resultPanel,
		resultNameLabel = resultNameLabel,
		resultRarityLabel = resultRarityLabel,
		resultMultiplierLabel = resultMultiplierLabel,
		countLabel = countLabel,
		multLabel = multLabel,
		scroll = scroll,
		bestButton = bestButton,
		unequipAllButton = unequipAllButton,
		selectedEggId = PetConfig.DefaultEggId,
		lastState = nil,
	}

	hatchButton.MouseButton1Click:Connect(function()
		local egg = findSelectedEgg(refs)
		if not egg then
			return
		end
		UIAnimator.buttonPunch(hatchButton)
		RequestHatchPetEgg:FireServer(egg.id)
	end)

	bestButton.MouseButton1Click:Connect(function()
		UIAnimator.buttonPunch(bestButton)
		RequestEquipPet:FireServer("BEST")
	end)
	unequipAllButton.MouseButton1Click:Connect(function()
		UIAnimator.buttonPunch(unequipAllButton)
		RequestUnequipPet:FireServer("ALL")
	end)

	OpenPetEggShop.OnClientEvent:Connect(function(payload)
		if type(payload) == "string" and PetConfig.getEggById(payload) then
			refs.selectedEggId = payload
		elseif type(payload) == "table" then
			local preferredEggId = payload.eggId
			local areaIndex = payload.areaIndex
			if type(preferredEggId) == "string" and PetConfig.getEggById(preferredEggId) then
				refs.selectedEggId = preferredEggId
			elseif type(areaIndex) == "number" then
				refs.selectedEggId = chooseEggForArea(refs.lastState or {}, areaIndex) or refs.selectedEggId
			end
		end
		PetFrame.show(refs)
		if refs.lastState then
			PetFrame.update(refs, refs.lastState)
		end
	end)

	HatchPetResult.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		local name = tostring(payload.displayName or "Pet")
		local rarity = tostring(payload.rarity or "?")
		local mult = if type(payload.powerMultiplier) == "number" then payload.powerMultiplier else 1
		local color = rarityColor(rarity)
		refs.resultPanel.Visible = true
		refs.resultPanel.BackgroundColor3 = color:Lerp(Color3.fromRGB(14, 18, 26), 0.68)
		refs.resultNameLabel.Text = name
		refs.resultNameLabel.TextColor3 = Theme.Colors.White
		refs.resultRarityLabel.Text = rarity
		refs.resultRarityLabel.TextColor3 = color
		refs.resultMultiplierLabel.Text = string.format("%.2gx Power", mult)
		UIAnimator.buttonPunch(refs.resultPanel)
	end)

	return refs
end

function PetFrame.show(refs: Refs)
	UIAnimator.framePopIn(refs.backdrop, refs.root)
end

function PetFrame.update(refs: Refs, state)
	refs.lastState = state
	local pets = if type(state.Pets) == "table" then state.Pets else {}
	local equipped = if type(state.EquippedPets) == "table" then state.EquippedPets else {}
	local petMult = state.PetMultiplier or 1

	local selectedEgg = findSelectedEgg(refs)
	if selectedEgg then
		local unlocked = canAccessEgg(state, selectedEgg)
		local enoughDna = (state.DnaCoins or 0) >= selectedEgg.cost
		refs.eggNameLabel.Text = selectedEgg.displayName
		refs.eggNameLabel.TextColor3 = selectedEgg.color
		refs.eggReqLabel.Text = "Requirement: " .. eggRequirementText(selectedEgg)
		refs.eggCostLabel.Text = "Cost: " .. NumberFormatter.format(selectedEgg.cost) .. " DNA"
		refs.hatchButton.Text = if unlocked then (if enoughDna then "HATCH" else "NEED DNA") else "LOCKED"
		refs.hatchButton.BackgroundColor3 = if unlocked and enoughDna then Theme.Colors.Green else Theme.Colors.Red
	end

	for _, child in ipairs(refs.eggScroll:GetChildren()) do
		if child:IsA("GuiObject") and child.Name:sub(1, 4) == "Egg_" then
			child:Destroy()
		end
	end
	for _, egg in ipairs(getSortedEggs()) do
		buildEggCard(refs.eggScroll, refs, egg, state)
	end

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
	refs.multLabel.Text = string.format("Pet Power: %.3gx", petMult)

	for _, child in ipairs(refs.scroll:GetChildren()) do
		if child:IsA("Frame") and child.Name:sub(1, 4) == "Pet_" then
			child:Destroy()
		end
	end

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
		return petMultiplier(a.def) > petMultiplier(b.def)
	end)

	for _, entry in ipairs(sorted) do
		buildPetCard(refs.scroll, entry.instanceId, entry.def, entry.equipped)
	end
end

return PetFrame
