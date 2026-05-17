--!strict
-- Modernes Top-HUD: DNA, Power, Rank und kleiner Spin-Zugang.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))
local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))

local Configs = ReplicatedStorage:WaitForChild("Configs")
local TitleConfig = require(Configs:WaitForChild("TitleConfig"))

local TopBar = {}

type Refs = {
	root: Frame,
	dnaLabel: TextLabel,
	powerLabel: TextLabel,
	rankLabel: TextLabel,
	boostLabel: TextLabel,
	spinButton: TextButton,
}

local function addCornerAndStroke(frame: GuiObject, color: Color3, thickness: number?, transparency: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness or 1.5
	stroke.Transparency = transparency or 0.35
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
end

local function makeCapsule(parent: Frame, name: string, icon: string, accent: Color3, width: number?): TextLabel
	local capsule = Instance.new("Frame")
	capsule.Name = name
	capsule.Size = UDim2.new(0, width or 112, 0, 32)
	capsule.BackgroundColor3 = Color3.fromRGB(15, 20, 29)
	capsule.BackgroundTransparency = 0.05
	capsule.BorderSizePixel = 0
	addCornerAndStroke(capsule, accent, 1.5, 0.4)
	capsule.Parent = parent

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.Position = UDim2.new(0, 10, 0, 0)
	iconLabel.Size = UDim2.new(0, 26, 1, 0)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Font = Enum.Font.GothamBlack
	iconLabel.Text = icon
	iconLabel.TextColor3 = accent
	iconLabel.TextSize = 13
	iconLabel.TextScaled = false
	iconLabel.TextStrokeTransparency = 1
	iconLabel.Parent = capsule

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.Position = UDim2.new(0, 42, 0, 0)
	value.Size = UDim2.new(1, -46, 1, 0)
	value.BackgroundTransparency = 1
	value.Font = Theme.Font
	value.TextColor3 = Theme.Colors.White
	value.TextStrokeTransparency = 1
	value.TextSize = 13
	value.TextScaled = false
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.Text = "-"
	value.Parent = capsule

	return value
end

local function formatTime(sec: number): string
	sec = math.max(0, math.floor(sec))
	local m = math.floor(sec / 60)
	local s = sec % 60
	return string.format("%02d:%02d", m, s)
end

local function currentBoostText(state): string
	local activeBoosts = state.ActiveBoosts or {}
	local serverTime = state.ServerTime
	if not serverTime or serverTime == 0 then
		return "Boost: -"
	end

	local now = serverTime + (os.clock() - (state._clientReceivedAt or os.clock()))
	local bestId = nil
	local bestRemain = 0
	for id, expiry in pairs(activeBoosts) do
		if type(expiry) == "number" and expiry > now and expiry - now > bestRemain then
			bestId = id
			bestRemain = expiry - now
		end
	end

	if not bestId then
		return "Boost: -"
	end

	local label = if bestId == "Power2x" then "Power" elseif bestId == "Dna2x" then "DNA" else "Luck"
	return label .. " " .. formatTime(bestRemain)
end

function TopBar.create(parent: ScreenGui, onSpinClick: (() -> ())?): Refs
	local root = Instance.new("Frame")
	root.Name = "TopHUD"
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, 0, 14)
	root.Size = UDim2.new(0, 590, 0, 48)
	root.BackgroundColor3 = Color3.fromRGB(9, 13, 20)
	root.BackgroundTransparency = 0.08
	root.BorderSizePixel = 0
	root.Parent = parent
	addCornerAndStroke(root, Color3.fromRGB(56, 236, 207), 1.5, 0.45)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 7)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = root

	local dnaLabel = makeCapsule(root, "DnaCapsule", "DNA", Theme.Colors.Green, 104)
	local powerLabel = makeCapsule(root, "PowerCapsule", "PWR", Color3.fromRGB(56, 236, 207), 104)
	local rankLabel = makeCapsule(root, "RankCapsule", "TAG", Theme.Colors.Yellow, 122)
	local boostLabel = makeCapsule(root, "BoostCapsule", "2X", Theme.Colors.Purple, 120)

	local spinBtn = Instance.new("TextButton")
	spinBtn.Name = "SpinButton"
	spinBtn.Size = UDim2.new(0, 64, 0, 32)
	spinBtn.Text = "SPIN"
	Theme.applyButtonStyle(spinBtn, Color3.fromRGB(35, 166, 255))
	spinBtn.TextSize = 13
	spinBtn.TextScaled = false
	spinBtn.Parent = root

	if onSpinClick then
		spinBtn.MouseButton1Click:Connect(function()
			UIAnimator.buttonPunch(spinBtn)
			onSpinClick()
		end)
	end

	return {
		root = root,
		dnaLabel = dnaLabel,
		powerLabel = powerLabel,
		rankLabel = rankLabel,
		boostLabel = boostLabel,
		spinButton = spinBtn,
	}
end

function TopBar.update(refs: Refs, state)
	refs.dnaLabel.Text = NumberFormatter.format(state.DnaCoins or 0)
	refs.powerLabel.Text = NumberFormatter.format(state.Power or 0)

	local titleDef = TitleConfig.getById(state.EquippedTitle or "Rookie")
	refs.rankLabel.Text = if titleDef then titleDef.displayName else "Rookie"
	refs.boostLabel.Text = currentBoostText(state)
end

return TopBar
