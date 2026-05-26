--!strict
-- Titles menu: owned/locked/equipped state, rarity, unlock text, bonuses.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))

local Configs = ReplicatedStorage:WaitForChild("Configs")
local TitleConfig = require(Configs:WaitForChild("TitleConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestEquipTitle = Remotes:WaitForChild("RequestEquipTitle") :: RemoteEvent

local TitleFrame = {}

local LAB_BASE = Color3.fromRGB(10, 14, 22)
local LAB_PANEL = Color3.fromRGB(18, 24, 35)
local LAB_PANEL_2 = Color3.fromRGB(25, 32, 46)
local LAB_STROKE = Color3.fromRGB(0, 210, 190)
local TEXT_MAIN = Color3.fromRGB(245, 248, 255)
local TEXT_SECONDARY = Color3.fromRGB(175, 185, 200)
local TEXT_MUTED = Color3.fromRGB(110, 120, 135)
local DNA_GREEN = Color3.fromRGB(0, 220, 120)
local CYAN = Color3.fromRGB(0, 190, 255)
local REWARD_GOLD = Color3.fromRGB(255, 220, 80)
local DANGER_RED = Color3.fromRGB(255, 70, 75)
local BUTTON_LOCKED = Color3.fromRGB(96, 110, 136)

local function restyleStroke(gui: GuiObject, color: Color3, thickness: number?, transparency: number?)
	local stroke = gui:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Thickness = thickness or 1.5
		stroke.Transparency = transparency or 0.35
	end
end

local function ensureGradient(gui: GuiObject): UIGradient
	local gradient = gui:FindFirstChildOfClass("UIGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Parent = gui
	end
	return gradient
end

local function bindTitleButtonFeedback(button: TextButton)
	if button:GetAttribute("TitleReadableFeedback") == true then
		return
	end
	button:SetAttribute("TitleReadableFeedback", true)

	local scale = Instance.new("UIScale")
	scale.Name = "TitleButtonScale"
	scale.Parent = button

	button.MouseEnter:Connect(function()
		local state = button:GetAttribute("ReadableState")
		local accent = button:GetAttribute("ReadableAccent")
		local color = if typeof(accent) == "Color3" then accent else BUTTON_LOCKED
		local locked = state == "Locked"
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = if locked then 1.015 else 1.045,
		}):Play()
		TweenService:Create(button, TweenInfo.new(0.12), {
			BackgroundColor3 = if locked then BUTTON_LOCKED:Lerp(Color3.fromRGB(255, 255, 255), 0.06) else color:Lerp(Color3.fromRGB(255, 255, 255), 0.08),
		}):Play()
	end)

	button.MouseLeave:Connect(function()
		local state = button:GetAttribute("ReadableState")
		local accent = button:GetAttribute("ReadableAccent")
		local color = if typeof(accent) == "Color3" then accent else BUTTON_LOCKED
		local locked = state == "Locked"
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
		TweenService:Create(button, TweenInfo.new(0.12), {
			BackgroundColor3 = if locked then BUTTON_LOCKED else color:Lerp(Color3.fromRGB(18, 26, 38), 0.08),
		}):Play()
	end)
end

local function styleTitleButton(button: TextButton, accent: Color3, state: "Active" | "Equipped" | "Locked")
	local isLocked = state == "Locked"
	local fill = if isLocked then BUTTON_LOCKED else accent:Lerp(Color3.fromRGB(18, 26, 38), 0.08)
	button:SetAttribute("ReadableAccent", accent)
	button:SetAttribute("ReadableState", state)
	button.BackgroundColor3 = fill
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	button.TextStrokeTransparency = if isLocked then 0.1 else 0.04
	button.Font = Enum.Font.GothamBlack

	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if isLocked then Color3.fromRGB(190, 205, 230) else accent:Lerp(Color3.fromRGB(255, 255, 255), 0.24)
		stroke.Thickness = if isLocked then 2.6 else 3
		stroke.Transparency = if isLocked then 0.08 else 0.02
	end

	local gradient = ensureGradient(button)
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, fill:Lerp(Color3.fromRGB(255, 255, 255), if isLocked then 0.14 else 0.22)),
		ColorSequenceKeypoint.new(1, fill:Lerp(Color3.fromRGB(0, 0, 0), if isLocked then 0.12 else 0.2)),
	})
	gradient.Rotation = 90
	bindTitleButtonFeedback(button)
end

local RARITY_ORDER = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythic = 6,
	Secret = 7,
	Exclusive = 8,
	Other = 99,
}

local CONFIG_ORDER_BY_ID: { [string]: number } = {}
for order, def in ipairs(TitleConfig.Titles) do
	CONFIG_ORDER_BY_ID[def.id] = order
end

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

local function getConditionGroup(def): string
	local condition = def.condition
	if type(condition) ~= "table" then
		return "None"
	end
	local kind = tostring(condition.kind or "None")
	if kind == "Boss" then
		return "Boss"
	end
	return kind .. ":" .. tostring(condition.key or "")
end

local function getConditionValue(def): number
	local condition = def.condition
	if type(condition) ~= "table" then
		return 0
	end
	if condition.kind == "Auto" then
		return 0
	end
	if condition.kind == "Boss" and type(condition.key) == "string" then
		local area, enemy = string.match(condition.key, "^A(%d+)E(%d+)$")
		if area and enemy then
			local areaNumber = tonumber(area)
			local enemyNumber = tonumber(enemy)
			if areaNumber and enemyNumber then
				return areaNumber * 100 + enemyNumber
			end
		end
	end
	if type(condition.value) == "number" then
		return condition.value
	end
	return 0
end

local function sortedTitleDefs(): { any }
	local list = table.clone(TitleConfig.Titles)
	table.sort(list, function(a, b)
		local aRarity = RARITY_ORDER[a.rarity] or RARITY_ORDER.Other
		local bRarity = RARITY_ORDER[b.rarity] or RARITY_ORDER.Other
		if aRarity ~= bRarity then
			return aRarity < bRarity
		end

		local aGroup = getConditionGroup(a)
		local bGroup = getConditionGroup(b)
		if aGroup == bGroup then
			local aValue = getConditionValue(a)
			local bValue = getConditionValue(b)
			if aValue ~= bValue then
				return aValue < bValue
			end
		end

		local aOrder = CONFIG_ORDER_BY_ID[a.id] or math.huge
		local bOrder = CONFIG_ORDER_BY_ID[b.id] or math.huge
		if aOrder ~= bOrder then
			return aOrder < bOrder
		end

		return string.lower(a.displayName or a.id) < string.lower(b.displayName or b.id)
	end)
	return list
end

local function makeCard(parent: ScrollingFrame, def): CardRefs
	local card = Instance.new("Frame")
	card.Name = "Title_" .. def.id
	card.Size = UDim2.new(1, 0, 0, 92)
	Theme.applyPanelStyle(card, LAB_PANEL)
	card.ZIndex = 7
	card.Parent = parent
	restyleStroke(card, def.color, 1.4, 0.28)

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(0, 260, 0, 28)
	name.Position = UDim2.new(0, 12, 0, 8)
	Theme.applyLabelStyle(name)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = def.displayName
	name.TextColor3 = TEXT_MAIN
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
	unlock.TextColor3 = TEXT_SECONDARY
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
	status.TextColor3 = TEXT_MUTED
	status.TextSize = 15
	status.TextScaled = false
	status.ZIndex = 8
	status.Parent = card

	local button = Instance.new("TextButton")
	button.Name = "EquipButton"
	button.AnchorPoint = Vector2.new(1, 1)
	button.Size = UDim2.new(0, 146, 0, 42)
	button.Position = UDim2.new(1, -12, 1, -10)
	Theme.applyButtonStyle(button, LAB_PANEL_2)
	button.Text = "LOCKED"
	button.TextSize = 16
	button.TextScaled = false
	button.ZIndex = 9
	button.Parent = card
	styleTitleButton(button, def.color, "Locked")
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
	Theme.applyPanelStyle(root, LAB_BASE)
	root.ZIndex = 6
	root.Parent = backdrop
	restyleStroke(root, LAB_STROKE, 2, 0.18)

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -16, 0, 40)
	header.Position = UDim2.new(0, 8, 0, 8)
	Theme.applyLabelStyle(header)
	header.Text = "TITLES"
	header.TextColor3 = TEXT_MAIN
	header.TextSize = 28
	header.TextScaled = false
	header.ZIndex = 7
	header.Parent = root

	local closeButton = Instance.new("TextButton")
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -8, 0, 8)
	closeButton.Size = UDim2.new(0, 36, 0, 36)
	closeButton.Text = "X"
	Theme.applyButtonStyle(closeButton, DANGER_RED)
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
	infoLabel.TextColor3 = TEXT_SECONDARY
	infoLabel.TextSize = 17
	infoLabel.TextScaled = false
	infoLabel.ZIndex = 7
	infoLabel.Parent = root

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "TitleList"
	scroll.Size = UDim2.new(1, -32, 1, -96)
	scroll.Position = UDim2.new(0, 16, 0, 86)
	scroll.BackgroundColor3 = LAB_BASE
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
	for order, def in ipairs(sortedTitleDefs()) do
		cards[def.id] = makeCard(scroll, def)
		cards[def.id].card.LayoutOrder = order
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
			card.status.TextColor3 = DNA_GREEN
			card.button.Text = "EQUIPPED"
			styleTitleButton(card.button, DNA_GREEN, "Equipped")
			restyleStroke(card.card, CYAN, 2, 0.08)
			card.button:SetAttribute("Action", "None")
		elseif owned then
			card.status.Text = "UNLOCKED"
			card.status.TextColor3 = CYAN
			card.button.Text = "EQUIP"
			styleTitleButton(card.button, CYAN, "Active")
			restyleStroke(card.card, def.color, 1.4, 0.24)
			card.button:SetAttribute("Action", "Equip")
		else
			card.status.Text = "LOCKED"
			card.status.TextColor3 = Color3.fromRGB(205, 216, 230)
			card.button.Text = "LOCKED"
			styleTitleButton(card.button, def.color, "Locked")
			restyleStroke(card.card, def.color, 1.1, 0.55)
			card.button:SetAttribute("Action", "None")
		end
	end
end

return TitleFrame
