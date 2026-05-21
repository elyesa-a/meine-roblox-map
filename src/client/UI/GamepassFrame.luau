--!strict
-- Shop / Gamepass-Fenster: zeigt Premium-Angebote. DNA-kaufbare Boosts werden
-- hier bewusst nicht mehr angeboten.
--
-- Spaeter (Phase 5/Monetarisierung) werden hier MarketplaceService.PromptPurchase
-- + Gamepass-IDs angebunden.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local LabTheme = require(script.Parent:WaitForChild("LabTheme"))
local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestPromptPurchase = Remotes:WaitForChild("RequestPromptPurchase") :: RemoteEvent

local GamepassFrame = {}

type Entry = {
	id: string,
	displayName: string,
	subText: string,
	robux: number,
	color: Color3,
}

type Refs = {
	backdrop: Frame,
	root: Frame,
	closeButton: TextButton,
}

local ENTRIES: { Entry } = {
	{ id = "SpinPack",    displayName = "5x SPINS",     subText = "Instant 5 Free Spins", robux = 9,   color = Theme.Colors.Yellow },
	{ id = "VipZone",     displayName = "VIP ZONE",     subText = "Access to the VIP Zone", robux = 39,  color = Theme.Colors.Orange },
	{ id = "AutoClicker", displayName = "AUTO CLICKER", subText = "Clicks automatically", robux = 99,  color = Theme.Colors.Pink },
	{ id = "GlitchPet",   displayName = "GLITCH PET",   subText = "Guaranteed Mythic", robux = 279, color = Theme.Colors.Purple },
}

local function makeCard(parent: ScrollingFrame, entry: Entry, onPurchase: (Entry) -> ()): Frame
	local card = Instance.new("Frame")
	card.Name = "Gamepass_" .. entry.id
	card.Size = UDim2.new(1, 0, 0, 100)
	Theme.applyPanelStyle(card, LabTheme.Colors.Card)
	LabTheme.styleCard(card, entry.color)
	card.ZIndex = 7
	card.Parent = parent

	local icon = Instance.new("TextLabel")
	icon.Name = "ProductIcon"
	icon.Size = UDim2.new(0, 46, 0, 46)
	icon.Position = UDim2.new(0, 14, 0.5, -23)
	Theme.applyPanelStyle(icon, LabTheme.Colors.Panel2)
	LabTheme.styleCard(icon, entry.color)
	icon.Font = Enum.Font.GothamBlack
	icon.Text = "R$"
	icon.TextColor3 = entry.color:Lerp(LabTheme.Colors.Text, 0.25)
	icon.TextSize = 18
	icon.TextStrokeTransparency = 1
	icon.ZIndex = 8
	icon.Parent = card

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -200, 0, 36)
	name.Position = UDim2.new(0, 74, 0, 10)
	Theme.applyLabelStyle(name)
	LabTheme.styleLabel(name, LabTheme.Colors.Text, 22, true)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = entry.displayName
	name.TextSize = 22
	name.TextScaled = false
	name.ZIndex = 8
	name.Parent = card

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, -200, 0, 28)
	sub.Position = UDim2.new(0, 74, 0, 50)
	Theme.applyLabelStyle(sub)
	LabTheme.styleLabel(sub, LabTheme.Colors.SubText, 16, false)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Text = entry.subText
	sub.TextSize = 16
	sub.TextScaled = false
	sub.ZIndex = 8
	sub.Parent = card

	local btn = Instance.new("TextButton")
	btn.Name = "BuyButton"
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Size = UDim2.new(0, 170, 0, 68)
	btn.Position = UDim2.new(1, -12, 0.5, 0)
	Theme.applyButtonStyle(btn, LabTheme.Colors.Gold)
	LabTheme.styleButton(btn, LabTheme.Colors.Gold, true)
	LabTheme.bindButtonFeedback(btn, LabTheme.Colors.Gold)
	btn.Text = string.format("ONLY %d R$", entry.robux)
	btn.TextSize = 18
	btn.TextScaled = false
	btn.ZIndex = 9
	btn.Parent = card

	btn.MouseButton1Click:Connect(function()
		UIAnimator.buttonPunch(btn)
		onPurchase(entry)
	end)

	return card
end

function GamepassFrame.create(parent: ScreenGui): Refs
	local backdrop = Instance.new("Frame")
	backdrop.Name = "GamepassBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.DimBackdrop
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Visible = false
	backdrop.ZIndex = 5
	backdrop.Parent = parent
	LabTheme.styleBackdrop(backdrop)

	local root = Instance.new("Frame")
	root.Name = "GamepassFrame"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.new(0, 640, 0, 520)
	Theme.applyPanelStyle(root, LabTheme.Colors.Base)
	LabTheme.styleModal(root, LabTheme.Colors.Cyan)
	root.ZIndex = 6
	root.Parent = backdrop

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -16, 0, 40)
	header.Position = UDim2.new(0, 8, 0, 8)
	Theme.applyLabelStyle(header)
	LabTheme.styleLabel(header, LabTheme.Colors.Text, 28, true)
	header.Text = "SHOP"
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

	local note = Instance.new("TextLabel")
	note.Size = UDim2.new(1, -32, 0, 28)
	note.Position = UDim2.new(0, 16, 0, 52)
	Theme.applyLabelStyle(note)
	LabTheme.styleLabel(note, LabTheme.Colors.SubText, 14, false)
	note.Text = "Premium lab offers only."
	note.TextSize = 14
	note.TextScaled = false
	note.ZIndex = 7
	note.Parent = root

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "GamepassList"
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

	local order = 1
	for _, entry in ipairs(ENTRIES) do
		local card = makeCard(scroll, entry, function(e)
			RequestPromptPurchase:FireServer(e.id)
		end)
		card.LayoutOrder = order
		order += 1
	end

	return { backdrop = backdrop, root = root, closeButton = closeButton }
end

function GamepassFrame.show(refs: Refs)
	UIAnimator.framePopIn(refs.backdrop, refs.root)
end

return GamepassFrame
