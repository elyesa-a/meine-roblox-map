--!strict
-- Rebirth-Fenster: zeigt aktuellen + naechsten Rebirth, Multiplikator, Kosten.
-- Sendet RequestRebirth bei Klick auf den gruenen Button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LabTheme = require(script.Parent:WaitForChild("LabTheme"))
local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))
local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestRebirth = Remotes:WaitForChild("RequestRebirth") :: RemoteEvent

local RebirthFrame = {}

local REBIRTH_RED = Color3.fromRGB(165, 56, 62)
local REBIRTH_RED_DARK = Color3.fromRGB(95, 34, 42)
local REBIRTH_RED_SOFT = Color3.fromRGB(215, 92, 96)

type Refs = {
	root: Frame,
	backdrop: Frame,
	currentLabel: TextLabel,
	nextLabel: TextLabel,
	currentMultLabel: TextLabel,
	nextMultLabel: TextLabel,
	costLabel: TextLabel,
	progressFill: Frame,
	confirmButton: TextButton,
}

function RebirthFrame.create(parent: ScreenGui): Refs
	-- Dunkler Backdrop, der den Hintergrund abdunkelt.
	local backdrop = Instance.new("Frame")
	backdrop.Name = "RebirthBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	LabTheme.styleBackdrop(backdrop)
	backdrop.BorderSizePixel = 0
	backdrop.Visible = false
	backdrop.ZIndex = 5
	backdrop.Parent = parent

	local root = Instance.new("Frame")
	root.Name = "RebirthFrame"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.new(0, 520, 0, 360)
	LabTheme.styleModal(root, REBIRTH_RED)
	root.ZIndex = 6
	root.Parent = backdrop

	local headerBar = Instance.new("Frame")
	headerBar.Name = "MutationHeaderBar"
	headerBar.Size = UDim2.new(1, -24, 0, 64)
	headerBar.Position = UDim2.new(0, 12, 0, 10)
	LabTheme.styleCard(headerBar, REBIRTH_RED, false)
	headerBar.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
	headerBar.ZIndex = 6
	headerBar.Parent = root
	local headerGradient = Instance.new("UIGradient")
	headerGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, REBIRTH_RED_DARK),
		ColorSequenceKeypoint.new(0.48, Color3.fromRGB(18, 24, 34)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(9, 13, 20)),
	})
	headerGradient.Rotation = 0
	headerGradient.Parent = headerBar

	-- Header.
	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -78, 0, 34)
	header.Position = UDim2.new(0, 24, 0, 14)
	LabTheme.styleLabel(header, LabTheme.Colors.Text, 30, true)
	header.Text = "REBIRTH"
	header.TextScaled = false
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.ZIndex = 7
	header.Parent = root

	local subHeader = Instance.new("TextLabel")
	subHeader.Size = UDim2.new(1, -78, 0, 22)
	subHeader.Position = UDim2.new(0, 24, 0, 48)
	LabTheme.styleLabel(subHeader, Color3.fromRGB(210, 165, 168), 15, false)
	subHeader.Text = "Reset Power to evolve your mutation."
	subHeader.TextScaled = false
	subHeader.TextXAlignment = Enum.TextXAlignment.Left
	subHeader.ZIndex = 7
	subHeader.Parent = root

	-- Zwei Karten nebeneinander: aktuell / naechster.
	local function makeStatCard(parentFrame: Frame, side: "Left" | "Right"): { title: TextLabel, multi: TextLabel }
		local card = Instance.new("Frame")
		card.Size = UDim2.new(0.45, 0, 0, 100)
		card.AnchorPoint = if side == "Left" then Vector2.new(0, 0) else Vector2.new(1, 0)
		card.Position = if side == "Left"
			then UDim2.new(0, 16, 0, 100)
			else UDim2.new(1, -16, 0, 100)
		local accent = if side == "Left" then Color3.fromRGB(95, 110, 125) else REBIRTH_RED_SOFT
		LabTheme.styleCard(card, accent, false)
		card.ZIndex = 7
		card.Parent = parentFrame
		LabTheme.bindHoverPopout(card, 1.014)

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, -8, 0, 32)
		title.Position = UDim2.new(0, 4, 0, 4)
		LabTheme.styleLabel(title, LabTheme.Colors.SubText, 17, true)
		title.Text = "..."
		title.TextScaled = false
		title.ZIndex = 8
		title.Parent = card

		local multi = Instance.new("TextLabel")
		multi.Size = UDim2.new(1, -8, 0, 56)
		multi.Position = UDim2.new(0, 4, 0, 40)
		LabTheme.styleLabel(multi, if side == "Left" then LabTheme.Colors.Text else REBIRTH_RED_SOFT, 34, true)
		multi.Text = "1x"
		multi.TextScaled = false
		multi.ZIndex = 8
		multi.Parent = card

		return { title = title, multi = multi }
	end

	local left = makeStatCard(root, "Left")
	local right = makeStatCard(root, "Right")

	-- Kosten + Progressbar (alle ueber center-X gespiegelt, damit symmetrisch).
	local costLabel = Instance.new("TextLabel")
	costLabel.AnchorPoint = Vector2.new(0.5, 0)
	costLabel.Size = UDim2.new(1, -32, 0, 24)
	costLabel.Position = UDim2.new(0.5, 0, 0, 210)
	LabTheme.styleLabel(costLabel, Color3.fromRGB(222, 226, 232), 18, true)
	costLabel.Text = "Required Power: 0"
	costLabel.TextScaled = false
	costLabel.ZIndex = 7
	costLabel.Parent = root

	local progressBg = Instance.new("Frame")
	progressBg.AnchorPoint = Vector2.new(0.5, 0)
	progressBg.Size = UDim2.new(1, -32, 0, 18)
	progressBg.Position = UDim2.new(0.5, 0, 0, 238)
	progressBg.BackgroundColor3 = Color3.fromRGB(7, 10, 15)
	progressBg.BorderSizePixel = 0
	progressBg.ZIndex = 7
	progressBg.Parent = root
	local pbCorner = Instance.new("UICorner")
	pbCorner.CornerRadius = UDim.new(1, 0)
	pbCorner.Parent = progressBg
	local pbStroke = Instance.new("UIStroke")
	pbStroke.Color = Color3.fromRGB(65, 76, 88)
	pbStroke.Thickness = 1
	pbStroke.Transparency = 0.35
	pbStroke.Parent = progressBg

	local progressFill = Instance.new("Frame")
	progressFill.Size = UDim2.new(0, 0, 1, 0)
	progressFill.BackgroundColor3 = REBIRTH_RED_SOFT
	progressFill.BorderSizePixel = 0
	progressFill.ZIndex = 8
	progressFill.Parent = progressBg
	local pfCorner = Instance.new("UICorner")
	pfCorner.CornerRadius = UDim.new(1, 0)
	pfCorner.Parent = progressFill
	local pfGradient = Instance.new("UIGradient")
	pfGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, REBIRTH_RED_DARK),
		ColorSequenceKeypoint.new(1, REBIRTH_RED_SOFT),
	})
	pfGradient.Parent = progressFill

	-- Confirm-Button (center-bottom anchored, damit links/rechts gleicher Abstand).
	local confirmButton = Instance.new("TextButton")
	confirmButton.Name = "ConfirmButton"
	confirmButton.AnchorPoint = Vector2.new(0.5, 1)
	confirmButton.Size = UDim2.new(1, -32, 0, 56)
	confirmButton.Position = UDim2.new(0.5, 0, 1, -16)
	confirmButton.Text = "REBIRTH"
	LabTheme.styleButton(confirmButton, REBIRTH_RED, true)
	LabTheme.bindButtonFeedback(confirmButton, REBIRTH_RED)
	confirmButton.TextSize = 22
	confirmButton.TextScaled = false
	confirmButton.ZIndex = 7
	confirmButton.Parent = root

	-- X zum Schliessen.
	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -8, 0, 8)
	closeButton.Size = UDim2.new(0, 36, 0, 36)
	closeButton.Text = "X"
	LabTheme.styleClose(closeButton)
	closeButton.TextSize = 22
	closeButton.TextScaled = false
	closeButton.ZIndex = 8
	closeButton.Parent = root

	confirmButton.MouseButton1Click:Connect(function()
		UIAnimator.buttonPunch(confirmButton)
		RequestRebirth:FireServer()
	end)
	closeButton.MouseButton1Click:Connect(function()
		UIAnimator.framePopOut(backdrop, root)
	end)
	-- Klick auf Backdrop schliesst ebenfalls.
	backdrop.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			UIAnimator.framePopOut(backdrop, root)
		end
	end)
	root.InputBegan:Connect(function() end) -- Stopper, damit Klicks aufs Panel den Backdrop nicht schliessen

	return {
		root = root,
		backdrop = backdrop,
		currentLabel = left.title,
		nextLabel = right.title,
		currentMultLabel = left.multi,
		nextMultLabel = right.multi,
		costLabel = costLabel,
		progressFill = progressFill,
		confirmButton = confirmButton,
	}
end

function RebirthFrame.show(refs: Refs)
	UIAnimator.framePopIn(refs.backdrop, refs.root)
end

function RebirthFrame.update(refs: Refs, state)
	local r = state.Rebirths or 0
	local max = state.MaxRebirth or 100
	refs.currentLabel.Text = "Rebirth " .. r
	refs.currentMultLabel.Text = string.format("%.2gx", state.CurrentMultiplier or 1)

	if r >= max then
		refs.nextLabel.Text = "Max reached"
		refs.nextMultLabel.Text = "-"
		refs.costLabel.Text = "Max Rebirth reached"
		refs.progressFill.Size = UDim2.new(1, 0, 1, 0)
		refs.confirmButton.Text = "MAX REBIRTH REACHED"
		refs.confirmButton.AutoButtonColor = false
		refs.confirmButton.Active = false
		LabTheme.styleButton(refs.confirmButton, REBIRTH_RED, false)
	else
		refs.nextLabel.Text = "Rebirth " .. (r + 1)
		refs.nextMultLabel.Text = string.format("%.2gx", state.NextMultiplier or 1)
		local cost = state.RebirthCost or 0
		refs.costLabel.Text = "Required Power: " .. NumberFormatter.format(cost)
		local frac = if cost > 0 then math.clamp((state.Power or 0) / cost, 0, 1) else 0
		refs.progressFill.Size = UDim2.new(frac, 0, 1, 0)
		refs.confirmButton.Text = "REBIRTH"
		refs.confirmButton.Active = true
		LabTheme.styleButton(refs.confirmButton, REBIRTH_RED, true)
	end
end

return RebirthFrame
