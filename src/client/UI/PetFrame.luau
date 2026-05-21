--!strict
-- Pet hatch + inventory window. Extends the existing pet inventory instead of
-- creating a parallel UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))
local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))
local PetVisualBuilder = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PetVisualBuilder"))

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
	header: TextLabel,
	eggPanel: Frame,
	eggScroll: ScrollingFrame,
	eggNameLabel: TextLabel,
	eggReqLabel: TextLabel,
	eggCostLabel: TextLabel,
	eggChanceLabel: TextLabel,
	hatchButton: TextButton,
	resultPanel: Frame,
	resultPreview: ViewportFrame,
	resultPreviewWorld: WorldModel,
	resultPreviewCamera: Camera,
	resultNameLabel: TextLabel,
	resultRarityLabel: TextLabel,
	resultMultiplierLabel: TextLabel,
	infoRow: Frame,
	countLabel: TextLabel,
	multLabel: TextLabel,
	actionRow: Frame,
	scroll: ScrollingFrame,
	bestButton: TextButton,
	unequipAllButton: TextButton,
	selectedEggId: string?,
	lastState: { [string]: any }?,
	previewSpin: number,
	previewModel: Model?,
	eggOnlyMode: boolean,
}

local PET_CARD_SIZE = Vector2.new(136, 104)
local EGG_CARD_SIZE = Vector2.new(158, 72)
local LAB_BASE = Color3.fromRGB(10, 14, 22)
local LAB_PANEL = Color3.fromRGB(18, 24, 35)
local LAB_PANEL_2 = Color3.fromRGB(25, 32, 46)
local LAB_STROKE = Color3.fromRGB(0, 210, 190)
local LAB_STROKE_DARK = Color3.fromRGB(0, 120, 115)
local TEXT_MAIN = Color3.fromRGB(245, 248, 255)
local TEXT_SECONDARY = Color3.fromRGB(175, 185, 200)
local TEXT_MUTED = Color3.fromRGB(110, 120, 135)
local DNA_GREEN = Color3.fromRGB(0, 220, 120)
local REWARD_GOLD = Color3.fromRGB(255, 220, 80)
local DANGER_RED = Color3.fromRGB(255, 70, 75)

local function restyleStroke(gui: GuiObject, color: Color3, thickness: number?, transparency: number?)
	local stroke = gui:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Thickness = thickness or 1.5
		stroke.Transparency = transparency or 0.35
	end
end

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
	local cardColor = if selected then LAB_PANEL_2 else LAB_PANEL
	if not unlocked then
		cardColor = if selected then Color3.fromRGB(40, 36, 42) else Color3.fromRGB(17, 20, 28)
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
	restyleStroke(card, if selected then LAB_STROKE else (if unlocked then LAB_STROKE_DARK else Color3.fromRGB(60, 70, 85)), if selected then 2 else 1.25, if selected then 0.12 else 0.45)

	makeSmallLabel(card, egg.tier .. " Egg", UDim2.new(0, 6, 0, 5), UDim2.new(1, -12, 0, 18), 12, titleColor)
	local area = makeSmallLabel(card, egg.areaDisplayName, UDim2.new(0, 6, 0, 23), UDim2.new(1, -12, 0, 16), 11)
	area.TextColor3 = if unlocked then TEXT_SECONDARY else TEXT_MUTED
	area.TextXAlignment = Enum.TextXAlignment.Left
	local cost = makeSmallLabel(card, NumberFormatter.format(egg.cost) .. " DNA", UDim2.new(0, 6, 0, 41), UDim2.new(1, -12, 0, 14), 11, REWARD_GOLD)
	cost.TextXAlignment = Enum.TextXAlignment.Left
	local status = makeSmallLabel(
		card,
		if unlocked then (if selected then "SELECTED" else "OPEN") else "LOCKED",
		UDim2.new(0, 6, 0, 56),
		UDim2.new(1, -12, 0, 13),
		10,
		if unlocked then DNA_GREEN else DANGER_RED
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
	Theme.applyPanelStyle(card, if equipped then Color3.fromRGB(20, 34, 32) else LAB_PANEL)
	card.ZIndex = 7
	card.Parent = parent
	restyleStroke(card, petColor, if equipped then 2 else 1.35, if equipped then 0.12 else 0.35)

	local name = makeSmallLabel(card, def.displayName, UDim2.new(0, 4, 0, 4), UDim2.new(1, -8, 0, 20), 13)
	name.TextColor3 = TEXT_MAIN
	name.TextXAlignment = Enum.TextXAlignment.Center

	local rarity = makeSmallLabel(card, def.rarity, UDim2.new(0, 4, 0, 26), UDim2.new(1, -8, 0, 16), 11, petColor)
	rarity.TextXAlignment = Enum.TextXAlignment.Center

	local multi = makeSmallLabel(card, string.format("%.2gx Power", petMultiplier(def)), UDim2.new(0, 4, 0, 45), UDim2.new(1, -8, 0, 22), 16)
	multi.TextColor3 = REWARD_GOLD
	multi.TextXAlignment = Enum.TextXAlignment.Center

	local action = Instance.new("TextButton")
	action.Name = "Action"
	action.Size = UDim2.new(1, -8, 0, 26)
	action.Position = UDim2.new(0, 4, 1, -30)
	Theme.applyButtonStyle(action, if equipped then DANGER_RED else DNA_GREEN)
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
	Theme.applyPanelStyle(root, LAB_BASE)
	root.ZIndex = 6
	root.Parent = backdrop
	restyleStroke(root, LAB_STROKE, 2, 0.18)

	local header = makeSmallLabel(root, "PETS & EGGS", UDim2.new(0, 8, 0, 8), UDim2.new(1, -16, 0, 34), 26)
	header.TextColor3 = TEXT_MAIN
	header.TextXAlignment = Enum.TextXAlignment.Center

	local closeButton = Instance.new("TextButton")
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -8, 0, 8)
	closeButton.Size = UDim2.new(0, 36, 0, 36)
	closeButton.Text = "X"
	Theme.applyButtonStyle(closeButton, DANGER_RED)
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
	Theme.applyPanelStyle(eggPanel, LAB_PANEL)
	eggPanel.ZIndex = 7
	eggPanel.Parent = root
	restyleStroke(eggPanel, LAB_STROKE_DARK, 1.25, 0.42)

	local eggScroll = Instance.new("ScrollingFrame")
	eggScroll.Name = "EggGrid"
	eggScroll.Size = UDim2.new(0, 360, 1, -16)
	eggScroll.Position = UDim2.new(0, 8, 0, 8)
	eggScroll.BackgroundColor3 = LAB_BASE
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
	eggNameLabel.TextColor3 = TEXT_MAIN
	eggNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	local eggReqLabel = makeSmallLabel(eggPanel, "Requirement: -", UDim2.new(0, 384, 0, 38), UDim2.new(1, -400, 0, 20), 13, TEXT_SECONDARY)
	eggReqLabel.TextXAlignment = Enum.TextXAlignment.Left
	local eggCostLabel = makeSmallLabel(eggPanel, "Cost: -", UDim2.new(0, 384, 0, 62), UDim2.new(1, -400, 0, 20), 13, REWARD_GOLD)
	eggCostLabel.TextXAlignment = Enum.TextXAlignment.Left
	local eggChanceLabel = makeSmallLabel(eggPanel, rarityChanceText(), UDim2.new(0, 384, 0, 88), UDim2.new(1, -400, 0, 34), 11, TEXT_SECONDARY)
	eggChanceLabel.RichText = true
	eggChanceLabel.TextWrapped = true
	eggChanceLabel.TextXAlignment = Enum.TextXAlignment.Left

	local hatchButton = Instance.new("TextButton")
	hatchButton.Name = "HatchButton"
	hatchButton.Size = UDim2.new(0, 170, 0, 34)
	hatchButton.Position = UDim2.new(0, 384, 1, -42)
	hatchButton.Text = "HATCH"
	Theme.applyButtonStyle(hatchButton, DNA_GREEN)
	hatchButton.TextSize = 16
	hatchButton.TextScaled = false
	hatchButton.ZIndex = 8
	hatchButton.Parent = eggPanel

	local resultPanel = Instance.new("Frame")
	resultPanel.Name = "HatchResultPanel"
	resultPanel.Size = UDim2.new(1, -566, 0, 54)
	resultPanel.Position = UDim2.new(0, 564, 1, -62)
	Theme.applyPanelStyle(resultPanel, LAB_PANEL_2)
	resultPanel.Visible = false
	resultPanel.ZIndex = 8
	resultPanel.Parent = eggPanel

	-- Live 3D-Vorschau des frisch geschluepften Pets. Eigene WorldModel +
	-- Kamera -> isoliert vom Workspace, kein Performance-Bezug zur Welt.
	local resultPreview = Instance.new("ViewportFrame")
	resultPreview.Name = "ResultPreview"
	resultPreview.Position = UDim2.new(0, 4, 0, 4)
	resultPreview.Size = UDim2.new(0, 46, 0, 46)
	resultPreview.BackgroundColor3 = LAB_BASE
	resultPreview.BorderSizePixel = 0
	resultPreview.LightDirection = Vector3.new(-0.4, -1, -0.5).Unit
	resultPreview.Ambient = Color3.fromRGB(160, 170, 185)
	resultPreview.LightColor = Color3.fromRGB(255, 250, 245)
	resultPreview.ZIndex = 9
	resultPreview.Parent = resultPanel

	local previewCorner = Instance.new("UICorner")
	previewCorner.CornerRadius = UDim.new(0, 6)
	previewCorner.Parent = resultPreview

	local previewStroke = Instance.new("UIStroke")
	previewStroke.Thickness = 1.2
	previewStroke.Transparency = 0.45
	previewStroke.Color = Color3.fromRGB(95, 110, 130)
	previewStroke.Parent = resultPreview

	local resultPreviewWorld = Instance.new("WorldModel")
	resultPreviewWorld.Name = "PreviewWorld"
	resultPreviewWorld.Parent = resultPreview

	local resultPreviewCamera = Instance.new("Camera")
	resultPreviewCamera.FieldOfView = 50
	resultPreviewCamera.Parent = resultPreview
	resultPreview.CurrentCamera = resultPreviewCamera

	local resultNameLabel = makeSmallLabel(resultPanel, "New Pet", UDim2.new(0, 56, 0, 5), UDim2.new(1, -64, 0, 18), 14)
	resultNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	local resultRarityLabel = makeSmallLabel(resultPanel, "Rarity", UDim2.new(0, 56, 0, 24), UDim2.new(0.5, -32, 0, 16), 12, DNA_GREEN)
	resultRarityLabel.TextXAlignment = Enum.TextXAlignment.Left
	local resultMultiplierLabel = makeSmallLabel(resultPanel, "1x Power", UDim2.new(0.5, 0, 0, 24), UDim2.new(0.5, -8, 0, 16), 12, REWARD_GOLD)
	resultMultiplierLabel.TextXAlignment = Enum.TextXAlignment.Right

	local infoRow = Instance.new("Frame")
	infoRow.Size = UDim2.new(1, -32, 0, 28)
	infoRow.Position = UDim2.new(0, 16, 0, 226)
	infoRow.BackgroundTransparency = 1
	infoRow.ZIndex = 7
	infoRow.Parent = root

	local countLabel = makeSmallLabel(
		infoRow,
		string.format("0/%d Inventory  |  0/%d Equipped", PetConfig.MaxInventorySize, PetConfig.MaxEquipped),
		UDim2.new(0, 0, 0, 0),
		UDim2.new(0.5, -4, 1, 0),
		15
	)
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
	Theme.applyButtonStyle(bestButton, DNA_GREEN)
	bestButton.TextSize = 15
	bestButton.TextScaled = false
	bestButton.ZIndex = 8
	bestButton.Parent = actionRow

	local unequipAllButton = Instance.new("TextButton")
	unequipAllButton.Size = UDim2.new(0, 170, 1, 0)
	unequipAllButton.Text = "UNEQUIP ALL"
	Theme.applyButtonStyle(unequipAllButton, DANGER_RED)
	unequipAllButton.TextSize = 15
	unequipAllButton.TextScaled = false
	unequipAllButton.ZIndex = 8
	unequipAllButton.Parent = actionRow

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "PetGrid"
	scroll.Size = UDim2.new(1, -32, 1, -318)
	scroll.Position = UDim2.new(0, 16, 0, 308)
	scroll.BackgroundColor3 = LAB_BASE
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
		header = header,
		eggPanel = eggPanel,
		eggScroll = eggScroll,
		eggNameLabel = eggNameLabel,
		eggReqLabel = eggReqLabel,
		eggCostLabel = eggCostLabel,
		eggChanceLabel = eggChanceLabel,
		hatchButton = hatchButton,
		resultPanel = resultPanel,
		resultPreview = resultPreview,
		resultPreviewWorld = resultPreviewWorld,
		resultPreviewCamera = resultPreviewCamera,
		resultNameLabel = resultNameLabel,
		resultRarityLabel = resultRarityLabel,
		resultMultiplierLabel = resultMultiplierLabel,
		infoRow = infoRow,
		countLabel = countLabel,
		multLabel = multLabel,
		actionRow = actionRow,
		scroll = scroll,
		bestButton = bestButton,
		unequipAllButton = unequipAllButton,
		selectedEggId = PetConfig.DefaultEggId,
		lastState = nil,
		previewSpin = 0,
		previewModel = nil,
		eggOnlyMode = false,
	}

	-- Sanfte, kostengünstige Eigen-Rotation der Hatch-Vorschau. Dreht nur,
	-- solange ein Modell vorhanden ist; sonst Early-Out -> 0 Kosten.
	RunService.RenderStepped:Connect(function(dt)
		local model = refs.previewModel
		if not model or not model.Parent then
			return
		end
		refs.previewSpin = (refs.previewSpin + dt * 0.9) % (math.pi * 2)
		local pp = model.PrimaryPart
		if pp then
			model:PivotTo(CFrame.new(pp.Position.X, pp.Position.Y, pp.Position.Z) * CFrame.Angles(0, refs.previewSpin, 0))
		end
	end)

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
		PetFrame.show(refs, true)
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
		refs.resultPanel.BackgroundColor3 = color:Lerp(LAB_PANEL, 0.78)
		refs.resultNameLabel.Text = name
		refs.resultNameLabel.TextColor3 = TEXT_MAIN
		refs.resultRarityLabel.Text = rarity
		refs.resultRarityLabel.TextColor3 = color
		refs.resultMultiplierLabel.Text = string.format("%.2gx Power", mult)

		-- Live-Vorschau: alten Preview-Inhalt loeschen, neues Pet-Modell mit
		-- PetVisualBuilder bauen und in das ViewportFrame setzen.
		local world = refs.resultPreviewWorld
		if world then
			for _, child in ipairs(world:GetChildren()) do
				child:Destroy()
			end
			refs.previewModel = nil

			local def = PetConfig.getById(tostring(payload.petId or ""))
			if def then
				local previewModel = Instance.new("Model")
				previewModel.Name = "PreviewPet"
				local _ = PetVisualBuilder.build(previewModel, def)
				previewModel.Parent = world
				if previewModel.PrimaryPart then
					previewModel:PivotTo(CFrame.new(0, 0, 0))
				end

				-- Kamera so positionieren, dass das Pet rarity-skaliert ins Bild passt.
				local rank = PetVisualBuilder.getRank(def.rarity)
				local distance = 5.4 + math.min(rank, 6) * 0.45
				refs.resultPreviewCamera.CFrame = CFrame.lookAt(
					Vector3.new(0, 1.1, distance),
					Vector3.new(0, 0.4, 0)
				)
				refs.resultPreview.BackgroundColor3 = color:Lerp(LAB_BASE, 0.82)

				refs.previewSpin = 0
				refs.previewModel = previewModel
			end
		end

		UIAnimator.buttonPunch(refs.resultPanel)
	end)

	return refs
end

local function setEggOnlyMode(refs: Refs, enabled: boolean)
	refs.eggOnlyMode = enabled
	if enabled then
		refs.header.Text = "EGG SHOP"
		refs.root.Size = UDim2.new(0, 760, 0, 270)
		refs.eggPanel.Position = UDim2.new(0, 16, 0, 52)
		refs.eggPanel.Size = UDim2.new(1, -32, 1, -68)
		refs.eggPanel.Visible = true
		refs.infoRow.Visible = false
		refs.actionRow.Visible = false
		refs.scroll.Visible = false
	else
		refs.header.Text = "PET INVENTORY"
		refs.root.Size = UDim2.new(0, 760, 0, 430)
		refs.eggPanel.Visible = false
		refs.infoRow.Position = UDim2.new(0, 16, 0, 54)
		refs.infoRow.Visible = true
		refs.actionRow.Position = UDim2.new(0, 16, 0, 88)
		refs.actionRow.Visible = true
		refs.scroll.Position = UDim2.new(0, 16, 0, 140)
		refs.scroll.Size = UDim2.new(1, -32, 1, -156)
		refs.scroll.Visible = true
	end
end

function PetFrame.show(refs: Refs, eggOnly: boolean?)
	setEggOnlyMode(refs, eggOnly == true)
	UIAnimator.framePopIn(refs.backdrop, refs.root)
end

function PetFrame.showInventory(refs: Refs)
	PetFrame.show(refs, false)
end

function PetFrame.showEggShop(refs: Refs)
	PetFrame.show(refs, true)
end

function PetFrame.isEggOnlyMode(refs: Refs): boolean
	return refs.eggOnlyMode == true
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
		refs.hatchButton.BackgroundColor3 = if unlocked and enoughDna then DNA_GREEN else DANGER_RED
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
