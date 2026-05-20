--!strict
-- Teleport menu: displays boss-gated area travel without trusting the client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))

local Configs = ReplicatedStorage:WaitForChild("Configs")
local AreaConfig = require(Configs:WaitForChild("AreaConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestTeleportArea = Remotes:WaitForChild("RequestTeleportArea") :: RemoteEvent

local TeleportFrame = {}

type CardRefs = {
	card: Frame,
	status: TextLabel,
	requirement: TextLabel,
	button: TextButton,
	stroke: UIStroke?,
}

type Refs = {
	backdrop: Frame,
	root: Frame,
	cards: { [number]: CardRefs },
	lastState: { [string]: any }?,
}

local LAB_BASE = Color3.fromRGB(10, 14, 22)
local LAB_PANEL = Color3.fromRGB(18, 24, 35)
local LAB_PANEL_2 = Color3.fromRGB(25, 32, 46)
local LAB_STROKE = Color3.fromRGB(0, 210, 190)
local TEXT_MAIN = Color3.fromRGB(245, 248, 255)
local TEXT_SECONDARY = Color3.fromRGB(175, 185, 200)
local TEXT_MUTED = Color3.fromRGB(110, 120, 135)
local DNA_GREEN = Color3.fromRGB(0, 220, 120)
local AMBER = Color3.fromRGB(255, 190, 40)
local DANGER_RED = Color3.fromRGB(255, 70, 75)

local AREA_ACCENTS = {
	Color3.fromRGB(0, 210, 190),
	Color3.fromRGB(255, 190, 40),
	Color3.fromRGB(80, 255, 120),
	Color3.fromRGB(255, 150, 55),
	Color3.fromRGB(115, 210, 255),
	Color3.fromRGB(170, 255, 70),
	Color3.fromRGB(120, 220, 145),
	Color3.fromRGB(180, 90, 220),
	Color3.fromRGB(255, 220, 80),
	Color3.fromRGB(255, 70, 75),
}

local function addCorner(gui: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 12)
	corner.Parent = gui
end

local function addStroke(gui: GuiObject, color: Color3, thickness: number?, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness or 1.5
	stroke.Transparency = transparency or 0.35
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = gui
	return stroke
end

local function makeLabel(parent: Instance, name: string, text: string, pos: UDim2, size: UDim2, textSize: number, color: Color3, bold: boolean?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = pos
	label.Size = size
	label.BackgroundTransparency = 1
	label.Font = if bold then Enum.Font.GothamBlack else Theme.Font
	label.Text = text
	label.TextSize = textSize
	label.TextScaled = false
	label.TextColor3 = color
	label.TextStrokeTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 8
	label.Parent = parent
	return label
end

local function getHighestBossDefeated(state): number
	if type(state.HighestBossDefeated) == "number" then
		return state.HighestBossDefeated
	end
	local highest = 0
	if type(state.BossDefeats) == "table" then
		for bossId, count in pairs(state.BossDefeats) do
			if type(bossId) == "string" and type(count) == "number" and count > 0 then
				local areaText = string.match(bossId, "^A(%d+)E10$")
				local areaNumber = areaText and tonumber(areaText) or nil
				if areaNumber then
					highest = math.max(highest, areaNumber)
				end
			end
		end
	end
	return highest
end

local function isUnlocked(state, areaNumber: number): boolean
	return areaNumber <= getHighestBossDefeated(state) + 1
end

local function buildCard(parent: ScrollingFrame, area): CardRefs
	local accent = AREA_ACCENTS[area.index] or LAB_STROKE

	local card = Instance.new("Frame")
	card.Name = "Area" .. tostring(area.index) .. "Card"
	card.Size = UDim2.new(1, -10, 0, 88)
	card.BackgroundColor3 = LAB_PANEL
	card.BorderSizePixel = 0
	card.LayoutOrder = area.index
	card.ZIndex = 7
	card.Parent = parent
	addCorner(card, 12)
	local stroke = addStroke(card, accent, 1.4, 0.35)

	local accentBar = Instance.new("Frame")
	accentBar.Name = "AccentBar"
	accentBar.Size = UDim2.new(0, 5, 1, -16)
	accentBar.Position = UDim2.new(0, 10, 0, 8)
	accentBar.BackgroundColor3 = accent
	accentBar.BorderSizePixel = 0
	accentBar.ZIndex = 8
	accentBar.Parent = card
	addCorner(accentBar, 99)

	makeLabel(card, "AreaNumber", "AREA " .. tostring(area.index), UDim2.new(0, 24, 0, 8), UDim2.new(0, 92, 0, 18), 11, accent, true)
	makeLabel(card, "AreaName", area.displayName, UDim2.new(0, 24, 0, 27), UDim2.new(1, -168, 0, 24), 17, TEXT_MAIN, true)
	local status = makeLabel(card, "Status", "LOCKED", UDim2.new(0, 24, 0, 55), UDim2.new(0, 100, 0, 18), 11, DANGER_RED, true)
	local requirement = makeLabel(card, "Requirement", "Beat Area " .. tostring(math.max(1, area.index - 1)) .. " Boss", UDim2.new(0, 130, 0, 55), UDim2.new(1, -260, 0, 18), 11, AMBER, false)

	local button = Instance.new("TextButton")
	button.Name = "TeleportButton"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -12, 0.5, 0)
	button.Size = UDim2.new(0, 118, 0, 40)
	button.Text = "LOCKED"
	Theme.applyButtonStyle(button, LAB_PANEL_2)
	button.TextSize = 13
	button.TextScaled = false
	button.ZIndex = 8
	button.Parent = card
	local buttonStroke = button:FindFirstChildOfClass("UIStroke")
	if buttonStroke then
		buttonStroke.Color = accent
		buttonStroke.Thickness = 1.2
		buttonStroke.Transparency = 0.45
	end

	button.MouseButton1Click:Connect(function()
		RequestTeleportArea:FireServer(area.index)
		UIAnimator.buttonPunch(button)
	end)

	return { card = card, status = status, requirement = requirement, button = button, stroke = stroke }
end

function TeleportFrame.create(parent: ScreenGui): Refs
	local backdrop = Instance.new("Frame")
	backdrop.Name = "TeleportBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.DimBackdrop
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Visible = false
	backdrop.ZIndex = 5
	backdrop.Parent = parent

	local root = Instance.new("Frame")
	root.Name = "TeleportFrame"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.new(0, 560, 0, 540)
	root.BackgroundColor3 = LAB_BASE
	root.BorderSizePixel = 0
	root.ZIndex = 6
	root.Parent = backdrop
	addCorner(root, 16)
	addStroke(root, LAB_STROKE, 1.8, 0.18)

	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, -70, 0, 54)
	header.Position = UDim2.new(0, 18, 0, 10)
	Theme.applyLabelStyle(header)
	header.Text = "TELEPORT"
	header.TextSize = 28
	header.TextScaled = false
	header.TextColor3 = TEXT_MAIN
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.ZIndex = 7
	header.Parent = root

	local closeButton = Instance.new("TextButton")
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -14, 0, 14)
	closeButton.Size = UDim2.new(0, 38, 0, 38)
	closeButton.Text = "X"
	Theme.applyButtonStyle(closeButton, DANGER_RED)
	closeButton.TextSize = 22
	closeButton.TextScaled = false
	closeButton.ZIndex = 8
	closeButton.Parent = root
	closeButton.MouseButton1Click:Connect(function()
		UIAnimator.framePopOut(backdrop, root)
	end)

	local subtitle = makeLabel(root, "Subtitle", "Travel between boss-unlocked laboratory areas.", UDim2.new(0, 20, 0, 58), UDim2.new(1, -40, 0, 22), 13, TEXT_SECONDARY, false)
	subtitle.ZIndex = 7

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "AreaList"
	scroll.Position = UDim2.new(0, 16, 0, 90)
	scroll.Size = UDim2.new(1, -32, 1, -108)
	scroll.BackgroundColor3 = LAB_PANEL_2
	scroll.BackgroundTransparency = 0.18
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = LAB_STROKE
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ZIndex = 7
	scroll.Parent = root
	addCorner(scroll, 12)
	addStroke(scroll, Color3.fromRGB(60, 70, 85), 1.2, 0.25)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 4)
	padding.Parent = scroll

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	local cards: { [number]: CardRefs } = {}
	for _, area in ipairs(AreaConfig.Areas) do
		cards[area.index] = buildCard(scroll, area)
	end

	return { backdrop = backdrop, root = root, cards = cards, lastState = nil }
end

function TeleportFrame.show(refs: Refs)
	UIAnimator.framePopIn(refs.backdrop, refs.root)
	if refs.lastState then
		TeleportFrame.update(refs, refs.lastState)
	end
end

function TeleportFrame.update(refs: Refs, state)
	refs.lastState = state
	for _, area in ipairs(AreaConfig.Areas) do
		local card = refs.cards[area.index]
		if not card then
			continue
		end
		local unlocked = isUnlocked(state, area.index)
		if unlocked then
			card.card.BackgroundColor3 = LAB_PANEL
			if card.stroke then
				card.stroke.Color = AREA_ACCENTS[area.index] or LAB_STROKE
				card.stroke.Transparency = 0.24
			end
			card.status.Text = "UNLOCKED"
			card.status.TextColor3 = DNA_GREEN
			card.requirement.Text = "Ready to travel"
			card.requirement.TextColor3 = TEXT_SECONDARY
			card.button.Text = "TELEPORT"
			card.button.BackgroundColor3 = DNA_GREEN
			card.button.TextColor3 = TEXT_MAIN
		else
			card.card.BackgroundColor3 = Color3.fromRGB(14, 17, 24)
			if card.stroke then
				card.stroke.Color = Color3.fromRGB(60, 70, 85)
				card.stroke.Transparency = 0.45
			end
			card.status.Text = "LOCKED"
			card.status.TextColor3 = DANGER_RED
			card.requirement.Text = "Beat Area " .. tostring(area.index - 1) .. " Boss"
			card.requirement.TextColor3 = AMBER
			card.button.Text = "LOCKED"
			card.button.BackgroundColor3 = LAB_PANEL_2
			card.button.TextColor3 = TEXT_MUTED
		end
	end
end

return TeleportFrame
