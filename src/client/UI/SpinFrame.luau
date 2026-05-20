--!strict
-- Lucky Wheel UI. The server rolls the reward; the client animates to that
-- exact segment so the visual result matches the real reward.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))

local Configs = ReplicatedStorage:WaitForChild("Configs")
local SpinConfig = require(Configs:WaitForChild("SpinConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestSpin = Remotes:WaitForChild("RequestSpin") :: RemoteEvent
local SpinResult = Remotes:WaitForChild("SpinResult") :: RemoteEvent

local SpinFrame = {}

type Refs = {
	backdrop: Frame,
	root: Frame,
	wheel: Frame,
	statusLabel: TextLabel,
	cooldownLabel: TextLabel,
	resultLabel: TextLabel,
	spinButton: TextButton,
	currentRotation: number,
	isWaiting: boolean,
	isSpinning: boolean,
	requestToken: number,
}

-- Sci-Fi-Labor-Palette: dunkles Panel, gedaempfte Cyan/Teal-Akzente,
-- subtile Rarity-Hints. Bewusst KEIN flaches Gelb mehr.
local PALETTE = {
	PanelDeep = Color3.fromRGB(14, 18, 26),
	PanelBase = Color3.fromRGB(22, 28, 38),
	PanelInset = Color3.fromRGB(30, 38, 50),
	PanelEdge = Color3.fromRGB(72, 96, 118),
	Cyan = Color3.fromRGB(96, 208, 224),
	CyanDeep = Color3.fromRGB(46, 132, 158),
	Teal = Color3.fromRGB(78, 194, 188),
	DnaGreen = Color3.fromRGB(120, 218, 158),
	Amber = Color3.fromRGB(232, 188, 96),
	Magenta = Color3.fromRGB(220, 120, 188),
	Mythic = Color3.fromRGB(180, 138, 232),
	TextSoft = Color3.fromRGB(208, 220, 232),
	TextMute = Color3.fromRGB(140, 156, 172),
}

local SLICE_DARK = Color3.fromRGB(26, 36, 50)
local SLICE_LIGHT = Color3.fromRGB(54, 104, 132)

-- Rarity-tinted slice palette. Common ~ cyan, Epic ~ amber etc. Wird auf die
-- abwechselnde Hell/Dunkel-Basis nur sanft gemischt, damit die Felgen-Optik
-- ruhig bleibt und das Rad nicht regenbogenhaft wirkt.
local RARITY_TINT = {
	Common = PALETTE.Cyan,
	Rare = PALETTE.Teal,
	Epic = PALETTE.Amber,
	Legendary = PALETTE.Magenta,
	Mythic = PALETTE.Mythic,
}

local RARITY_TEXT = {
	Common = Color3.fromRGB(232, 240, 248),
	Rare = Color3.fromRGB(160, 232, 232),
	Epic = Color3.fromRGB(248, 220, 140),
	Legendary = Color3.fromRGB(246, 200, 232),
	Mythic = Color3.fromRGB(220, 200, 248),
}

local WHEEL_DIAMETER = 390
local WHEEL_RADIUS = WHEEL_DIAMETER / 2
local TILE_SIZE = 6 -- kleiner = glattere Kreiskontur
local LABEL_RADIUS = 132

local function formatCooldown(sec: number): string
	sec = math.max(0, math.floor(sec))
	local m = math.floor(sec / 60)
	local s = sec % 60
	return string.format("%02d:%02d", m, s)
end

local function normalizeDegrees(degrees: number): number
	local normalized = degrees % 360
	if normalized < 0 then
		normalized += 360
	end
	return normalized
end

local function getRewardIndex(rewardId: string): number
	for i, reward in ipairs(SpinConfig.Rewards) do
		if reward.id == rewardId then
			return i
		end
	end
	return 1
end

local function textColorFor(bg: Color3): Color3
	local brightness = bg.R * 0.299 + bg.G * 0.587 + bg.B * 0.114
	return if brightness > 0.72 then Color3.fromRGB(18, 26, 40) else Color3.fromRGB(255, 255, 255)
end

local function rarityOfIndex(index: number): string
	local r = SpinConfig.Rewards[index]
	return (r and tostring(r.rarity)) or "Common"
end

-- Premium 2-Ton-Rhythmus mit dezentem Rarity-Tint. Verhindert das alte
-- Drei-Farben-Repeat-Muster und bleibt trotzdem ruhig/kohaerent.
local function colorForSegment(index: number): Color3
	local base = if index % 2 == 1 then SLICE_DARK else SLICE_LIGHT
	local tint = RARITY_TINT[rarityOfIndex(index)] or PALETTE.Cyan
	return base:Lerp(tint, 0.18)
end

local function makeLabel(parent: Instance, text: string, size: UDim2, position: UDim2, zIndex: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = position
	Theme.applyLabelStyle(label)
	label.Text = text
	label.TextWrapped = true
	label.TextScaled = true
	label.ZIndex = zIndex
	label.Parent = parent
	return label
end

local function makeCircle(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3, zIndex: number): Frame
	local circle = Instance.new("Frame")
	circle.Name = name
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.Size = size
	circle.Position = position
	circle.BackgroundColor3 = color
	circle.BorderSizePixel = 0
	circle.ZIndex = zIndex
	circle.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = circle

	return circle
end

local function addSegmentTiles(wheel: Frame, count: number)
	local segmentAngle = 360 / count
	local radiusSquared = (WHEEL_RADIUS - 4) * (WHEEL_RADIUS - 4)

	for x = TILE_SIZE / 2, WHEEL_DIAMETER - TILE_SIZE / 2, TILE_SIZE do
		for y = TILE_SIZE / 2, WHEEL_DIAMETER - TILE_SIZE / 2, TILE_SIZE do
			local dx = x - WHEEL_RADIUS
			local dy = y - WHEEL_RADIUS
			if dx * dx + dy * dy <= radiusSquared then
				local angleFromTop = normalizeDegrees(math.deg(math.atan(dy, dx)) + 90)
				local segmentIndex = math.clamp(math.floor(angleFromTop / segmentAngle) + 1, 1, count)
				local color = colorForSegment(segmentIndex)

				local tile = Instance.new("Frame")
				tile.Name = "SegmentTile"
				tile.AnchorPoint = Vector2.new(0.5, 0.5)
				tile.Size = UDim2.fromOffset(TILE_SIZE + 1, TILE_SIZE + 1)
				tile.Position = UDim2.fromOffset(x, y)
				tile.BackgroundColor3 = color
				tile.BorderSizePixel = 0
				tile.ZIndex = 9
				tile.Parent = wheel
			end
		end
	end
end

local function addRewardLabel(wheel: Frame, reward, index: number, count: number)
	local segmentAngle = 360 / count
	local sliceColor = colorForSegment(index)
	local midAngle = -90 + (index - 0.5) * segmentAngle
	local radians = math.rad(midAngle)
	local labelX = WHEEL_RADIUS + math.cos(radians) * LABEL_RADIUS
	local labelY = WHEEL_RADIUS + math.sin(radians) * LABEL_RADIUS

	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Name = "RewardLabel"
	rewardLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	rewardLabel.Size = UDim2.new(0, 90, 0, 36)
	rewardLabel.Position = UDim2.fromOffset(labelX, labelY)
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Font = Enum.Font.GothamBold
	rewardLabel.Text = reward.displayName
	rewardLabel.TextWrapped = true
	rewardLabel.TextScaled = true
	rewardLabel.TextColor3 = RARITY_TEXT[tostring(reward.rarity)] or textColorFor(sliceColor)
	rewardLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	rewardLabel.TextStrokeTransparency = 0.25
	rewardLabel.ZIndex = 12
	rewardLabel.Parent = wheel
end

local function animateToReward(refs: Refs, rewardId: string, displayName: string, rarity: string?)
	local rewardIndex = getRewardIndex(rewardId)
	local segmentAngle = 360 / #SpinConfig.Rewards
	local targetMod = normalizeDegrees(-((rewardIndex - 0.5) * segmentAngle))
	local currentMod = normalizeDegrees(refs.currentRotation)
	local relative = targetMod - currentMod
	if relative < 0 then
		relative += 360
	end

	local finalRotation = refs.currentRotation + 360 * 5 + relative
	refs.isWaiting = false
	refs.isSpinning = true
	refs.spinButton.Active = false
	refs.spinButton.AutoButtonColor = false
	refs.spinButton.Text = "SPINNING"
	refs.statusLabel.Text = "SPINNING..."
	refs.statusLabel.TextColor3 = PALETTE.Cyan
	refs.cooldownLabel.Text = "LANDING ON REWARD"
	refs.resultLabel.Text = "REWARD: ..."
	refs.resultLabel.TextColor3 = PALETTE.TextSoft

	local tween = TweenService:Create(
		refs.wheel,
		TweenInfo.new(4.1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Rotation = finalRotation }
	)
	tween:Play()
	tween.Completed:Connect(function()
		refs.currentRotation = finalRotation
		refs.wheel.Rotation = normalizeDegrees(finalRotation)
		refs.currentRotation = refs.wheel.Rotation
		refs.isSpinning = false
		refs.resultLabel.Text = "YOU WON: " .. displayName
		refs.statusLabel.Text = string.upper(rarity or "REWARD")
		local rarityKey = tostring(rarity or "")
		refs.statusLabel.TextColor3 = RARITY_TEXT[rarityKey] or PALETTE.Cyan
		refs.resultLabel.TextColor3 = RARITY_TEXT[rarityKey] or PALETTE.DnaGreen
	end)
end

function SpinFrame.create(parent: ScreenGui): Refs
	local backdrop = Instance.new("Frame")
	backdrop.Name = "SpinBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = PALETTE.PanelDeep
	backdrop.BackgroundTransparency = 0.32
	backdrop.BorderSizePixel = 0
	backdrop.Visible = false
	backdrop.ZIndex = 5
	backdrop.Parent = parent

	-- Modal-Panel: dunkle Labor-Optik mit weichen Ecken + Cyan-Edge.
	local root = Instance.new("Frame")
	root.Name = "SpinFrame"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.new(0, 620, 0, 740)
	root.BackgroundColor3 = PALETTE.PanelBase
	root.BorderSizePixel = 0
	root.ZIndex = 6
	root.Parent = backdrop

	local rootCorner = Instance.new("UICorner")
	rootCorner.CornerRadius = UDim.new(0, 18)
	rootCorner.Parent = root

	local rootStroke = Instance.new("UIStroke")
	rootStroke.Color = PALETTE.PanelEdge
	rootStroke.Thickness = 2
	rootStroke.Transparency = 0.25
	rootStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rootStroke.Parent = root

	local rootGradient = Instance.new("UIGradient")
	rootGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, PALETTE.PanelBase),
		ColorSequenceKeypoint.new(1, PALETTE.PanelDeep),
	})
	rootGradient.Rotation = 90
	rootGradient.Parent = root

	-- Header-Band: dunkles Inset-Streifen unter dem Titel als Hierarchie.
	local headerBand = Instance.new("Frame")
	headerBand.Name = "HeaderBand"
	headerBand.Size = UDim2.new(1, 0, 0, 70)
	headerBand.Position = UDim2.new(0, 0, 0, 0)
	headerBand.BackgroundColor3 = PALETTE.PanelDeep
	headerBand.BorderSizePixel = 0
	headerBand.ZIndex = 7
	headerBand.Parent = root

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 18)
	headerCorner.Parent = headerBand
	-- Unteren Rand des Bands gerade halten.
	local headerMask = Instance.new("Frame")
	headerMask.Size = UDim2.new(1, 0, 0, 22)
	headerMask.Position = UDim2.new(0, 0, 1, -22)
	headerMask.BackgroundColor3 = PALETTE.PanelDeep
	headerMask.BorderSizePixel = 0
	headerMask.ZIndex = 7
	headerMask.Parent = headerBand

	local headerAccent = Instance.new("Frame")
	headerAccent.Name = "HeaderAccent"
	headerAccent.Size = UDim2.new(1, -36, 0, 2)
	headerAccent.Position = UDim2.new(0, 18, 1, -2)
	headerAccent.BackgroundColor3 = PALETTE.Cyan
	headerAccent.BackgroundTransparency = 0.25
	headerAccent.BorderSizePixel = 0
	headerAccent.ZIndex = 8
	headerAccent.Parent = headerBand

	local header = Instance.new("TextLabel")
	header.Name = "Title"
	header.AnchorPoint = Vector2.new(0, 0.5)
	header.Size = UDim2.new(1, -86, 0, 36)
	header.Position = UDim2.new(0, 22, 0, 32)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.GothamBold
	header.Text = "LUCKY WHEEL"
	header.TextColor3 = PALETTE.TextSoft
	header.TextStrokeTransparency = 1
	header.TextSize = 26
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.ZIndex = 9
	header.Parent = root

	local headerDot = Instance.new("Frame")
	headerDot.Name = "TitleDot"
	headerDot.AnchorPoint = Vector2.new(0, 0.5)
	headerDot.Size = UDim2.new(0, 8, 0, 8)
	headerDot.Position = UDim2.new(0, 8, 0, 32)
	headerDot.BackgroundColor3 = PALETTE.Cyan
	headerDot.BorderSizePixel = 0
	headerDot.ZIndex = 9
	headerDot.Parent = root
	local headerDotCorner = Instance.new("UICorner")
	headerDotCorner.CornerRadius = UDim.new(1, 0)
	headerDotCorner.Parent = headerDot

	-- Close-Button: flacher dunkler Knopf mit Cyan-Stroke. Kein roter Klotz.
	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.AnchorPoint = Vector2.new(1, 0.5)
	closeButton.Position = UDim2.new(1, -16, 0, 32)
	closeButton.Size = UDim2.new(0, 38, 0, 38)
	closeButton.Text = "×"
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 24
	closeButton.TextColor3 = PALETTE.TextSoft
	closeButton.BackgroundColor3 = PALETTE.PanelInset
	closeButton.AutoButtonColor = true
	closeButton.BorderSizePixel = 0
	closeButton.ZIndex = 12
	closeButton.Parent = root
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 10)
	closeCorner.Parent = closeButton
	local closeStroke = Instance.new("UIStroke")
	closeStroke.Color = PALETTE.PanelEdge
	closeStroke.Thickness = 1.5
	closeStroke.Transparency = 0.2
	closeStroke.Parent = closeButton
	closeButton.MouseButton1Click:Connect(function()
		UIAnimator.framePopOut(backdrop, root)
	end)

	-- Wheel-Bereich: Aussenring (Glas-/Metallic-Optik) + Innerer Rahmen
	-- + tatsaechliches Rad. Drei Lagen geben das polierte "Ring"-Gefuehl.
	local outerRing = makeCircle(root, "OuterRing", UDim2.fromOffset(WHEEL_DIAMETER + 36, WHEEL_DIAMETER + 36), UDim2.new(0.5, 0, 0, 302), PALETTE.PanelInset, 6)
	local outerStroke = Instance.new("UIStroke")
	outerStroke.Color = PALETTE.PanelEdge
	outerStroke.Thickness = 1.5
	outerStroke.Transparency = 0.3
	outerStroke.Parent = outerRing
	local outerGradient = Instance.new("UIGradient")
	outerGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, PALETTE.PanelInset),
		ColorSequenceKeypoint.new(1, PALETTE.PanelDeep),
	})
	outerGradient.Rotation = 90
	outerGradient.Parent = outerRing

	local midRing = makeCircle(root, "MidRing", UDim2.fromOffset(WHEEL_DIAMETER + 16, WHEEL_DIAMETER + 16), UDim2.new(0.5, 0, 0, 302), PALETTE.PanelDeep, 6)
	local midStroke = Instance.new("UIStroke")
	midStroke.Color = PALETTE.Cyan
	midStroke.Thickness = 2
	midStroke.Transparency = 0.55
	midStroke.Parent = midRing

	local wheelHolder = makeCircle(root, "WheelHolder", UDim2.fromOffset(WHEEL_DIAMETER, WHEEL_DIAMETER), UDim2.new(0.5, 0, 0, 302), Color3.fromRGB(16, 22, 30), 7)
	wheelHolder.ClipsDescendants = false
	local holderStroke = Instance.new("UIStroke")
	holderStroke.Color = PALETTE.Cyan
	holderStroke.Thickness = 2
	holderStroke.Transparency = 0.18
	holderStroke.Parent = wheelHolder

	local wheel = Instance.new("Frame")
	wheel.Name = "SegmentsFrame"
	wheel.AnchorPoint = Vector2.new(0.5, 0.5)
	wheel.Size = UDim2.fromOffset(WHEEL_DIAMETER, WHEEL_DIAMETER)
	wheel.Position = UDim2.fromScale(0.5, 0.5)
	wheel.BackgroundTransparency = 1
	wheel.BorderSizePixel = 0
	wheel.ZIndex = 8
	wheel.Parent = wheelHolder

	addSegmentTiles(wheel, #SpinConfig.Rewards)
	for i, reward in ipairs(SpinConfig.Rewards) do
		addRewardLabel(wheel, reward, i, #SpinConfig.Rewards)
	end

	-- Speichen: schmaler + dunkler -> die Slice-Trennung wirkt sauberer.
	for i = 1, #SpinConfig.Rewards do
		local spoke = Instance.new("Frame")
		spoke.Name = "Spoke_" .. tostring(i)
		spoke.AnchorPoint = Vector2.new(0.5, 0.5)
		spoke.Size = UDim2.new(0, WHEEL_DIAMETER - 12, 0, 2)
		spoke.Position = UDim2.fromScale(0.5, 0.5)
		spoke.Rotation = (i - 1) * (360 / #SpinConfig.Rewards) - 90
		spoke.BackgroundColor3 = PALETTE.PanelDeep
		spoke.BackgroundTransparency = 0.15
		spoke.BorderSizePixel = 0
		spoke.ZIndex = 11
		spoke.Parent = wheel
	end

	-- Center-Hub: drei Lagen (Aussenring/Kern/Glow) fuer Premium-Look.
	local centerOuter = makeCircle(wheelHolder, "CenterOuter", UDim2.new(0, 84, 0, 84), UDim2.fromScale(0.5, 0.5), PALETTE.PanelDeep, 13)
	local centerOuterStroke = Instance.new("UIStroke")
	centerOuterStroke.Color = PALETTE.PanelEdge
	centerOuterStroke.Thickness = 1.5
	centerOuterStroke.Transparency = 0.35
	centerOuterStroke.Parent = centerOuter

	local center = makeCircle(wheelHolder, "CenterCircle", UDim2.new(0, 66, 0, 66), UDim2.fromScale(0.5, 0.5), PALETTE.PanelInset, 14)
	local centerStroke = Instance.new("UIStroke")
	centerStroke.Color = PALETTE.Cyan
	centerStroke.Thickness = 1.8
	centerStroke.Transparency = 0.15
	centerStroke.Parent = center
	local centerGradient = Instance.new("UIGradient")
	centerGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, PALETTE.PanelInset),
		ColorSequenceKeypoint.new(1, PALETTE.PanelDeep),
	})
	centerGradient.Rotation = 135
	centerGradient.Parent = center

	local centerCore = makeCircle(wheelHolder, "CenterCore", UDim2.new(0, 24, 0, 24), UDim2.fromScale(0.5, 0.5), PALETTE.Cyan, 15)
	centerCore.BackgroundTransparency = 0.05
	local centerCoreGlow = makeCircle(wheelHolder, "CenterCoreGlow", UDim2.new(0, 40, 0, 40), UDim2.fromScale(0.5, 0.5), PALETTE.Cyan, 14)
	centerCoreGlow.BackgroundTransparency = 0.75

	-- Pointer: scharfes Diamant-Stack (Schatten -> Body -> Cyan-Highlight).
	local pointerShadow = Instance.new("Frame")
	pointerShadow.Name = "PointerShadow"
	pointerShadow.AnchorPoint = Vector2.new(0.5, 0.5)
	pointerShadow.Size = UDim2.new(0, 34, 0, 34)
	pointerShadow.Position = UDim2.new(0.5, 0, 0, 4)
	pointerShadow.Rotation = 45
	pointerShadow.BackgroundColor3 = PALETTE.PanelDeep
	pointerShadow.BorderSizePixel = 0
	pointerShadow.ZIndex = 15
	pointerShadow.Parent = wheelHolder
	local pointerShadowCorner = Instance.new("UICorner")
	pointerShadowCorner.CornerRadius = UDim.new(0, 3)
	pointerShadowCorner.Parent = pointerShadow

	local pointer = Instance.new("Frame")
	pointer.Name = "Pointer"
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.Size = UDim2.new(0, 26, 0, 26)
	pointer.Position = UDim2.new(0.5, 0, 0, 2)
	pointer.Rotation = 45
	pointer.BackgroundColor3 = PALETTE.PanelInset
	pointer.BorderSizePixel = 0
	pointer.ZIndex = 16
	pointer.Parent = wheelHolder
	local pointerCorner = Instance.new("UICorner")
	pointerCorner.CornerRadius = UDim.new(0, 3)
	pointerCorner.Parent = pointer
	local pointerStroke = Instance.new("UIStroke")
	pointerStroke.Color = PALETTE.Cyan
	pointerStroke.Thickness = 1.5
	pointerStroke.Transparency = 0.1
	pointerStroke.Parent = pointer

	local pointerTip = Instance.new("Frame")
	pointerTip.Name = "PointerTip"
	pointerTip.AnchorPoint = Vector2.new(0.5, 0.5)
	pointerTip.Size = UDim2.new(0, 10, 0, 10)
	pointerTip.Position = UDim2.new(0.5, 0, 0, 8)
	pointerTip.Rotation = 45
	pointerTip.BackgroundColor3 = PALETTE.Cyan
	pointerTip.BorderSizePixel = 0
	pointerTip.ZIndex = 17
	pointerTip.Parent = wheelHolder
	local pointerTipCorner = Instance.new("UICorner")
	pointerTipCorner.CornerRadius = UDim.new(0, 2)
	pointerTipCorner.Parent = pointerTip

	-- Info-Bereich: eigene Inset-Karte unterhalb des Rads (saubere Hierarchie).
	local infoCard = Instance.new("Frame")
	infoCard.Name = "InfoCard"
	infoCard.AnchorPoint = Vector2.new(0.5, 0)
	infoCard.Size = UDim2.new(1, -42, 0, 110)
	infoCard.Position = UDim2.new(0.5, 0, 0, 530)
	infoCard.BackgroundColor3 = PALETTE.PanelDeep
	infoCard.BorderSizePixel = 0
	infoCard.ZIndex = 7
	infoCard.Parent = root
	local infoCorner = Instance.new("UICorner")
	infoCorner.CornerRadius = UDim.new(0, 12)
	infoCorner.Parent = infoCard
	local infoStroke = Instance.new("UIStroke")
	infoStroke.Color = PALETTE.PanelEdge
	infoStroke.Thickness = 1.2
	infoStroke.Transparency = 0.5
	infoStroke.Parent = infoCard

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.AnchorPoint = Vector2.new(0.5, 0)
	statusLabel.Size = UDim2.new(1, -24, 0, 24)
	statusLabel.Position = UDim2.new(0.5, 0, 0, 12)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.Text = "FREE SPIN READY"
	statusLabel.TextColor3 = PALETTE.Cyan
	statusLabel.TextStrokeTransparency = 1
	statusLabel.TextSize = 18
	statusLabel.ZIndex = 8
	statusLabel.Parent = infoCard

	local cooldownLabel = Instance.new("TextLabel")
	cooldownLabel.Name = "CooldownLabel"
	cooldownLabel.AnchorPoint = Vector2.new(0.5, 0)
	cooldownLabel.Size = UDim2.new(1, -24, 0, 20)
	cooldownLabel.Position = UDim2.new(0.5, 0, 0, 40)
	cooldownLabel.BackgroundTransparency = 1
	cooldownLabel.Font = Enum.Font.Gotham
	cooldownLabel.Text = ""
	cooldownLabel.TextColor3 = PALETTE.TextMute
	cooldownLabel.TextStrokeTransparency = 1
	cooldownLabel.TextSize = 14
	cooldownLabel.ZIndex = 8
	cooldownLabel.Parent = infoCard

	-- Divider zwischen Status und Reward.
	local divider = Instance.new("Frame")
	divider.Name = "InfoDivider"
	divider.AnchorPoint = Vector2.new(0.5, 0)
	divider.Size = UDim2.new(1, -48, 0, 1)
	divider.Position = UDim2.new(0.5, 0, 0, 66)
	divider.BackgroundColor3 = PALETTE.PanelEdge
	divider.BackgroundTransparency = 0.65
	divider.BorderSizePixel = 0
	divider.ZIndex = 8
	divider.Parent = infoCard

	local resultLabel = Instance.new("TextLabel")
	resultLabel.Name = "ResultLabel"
	resultLabel.AnchorPoint = Vector2.new(0.5, 0)
	resultLabel.Size = UDim2.new(1, -24, 0, 28)
	resultLabel.Position = UDim2.new(0.5, 0, 0, 74)
	resultLabel.BackgroundTransparency = 1
	resultLabel.Font = Enum.Font.GothamBold
	resultLabel.Text = "REWARD —"
	resultLabel.TextColor3 = PALETTE.DnaGreen
	resultLabel.TextStrokeTransparency = 1
	resultLabel.TextSize = 19
	resultLabel.ZIndex = 8
	resultLabel.Parent = infoCard

	-- Spin-Button: Cyan-Accent, dunkler Body, weicher Cyan-Stroke.
	local spinButton = Instance.new("TextButton")
	spinButton.Name = "SpinButton"
	spinButton.AnchorPoint = Vector2.new(0.5, 1)
	spinButton.Size = UDim2.new(1, -42, 0, 62)
	spinButton.Position = UDim2.new(0.5, 0, 1, -22)
	spinButton.BackgroundColor3 = PALETTE.CyanDeep
	spinButton.AutoButtonColor = true
	spinButton.BorderSizePixel = 0
	spinButton.Text = "SPIN"
	spinButton.Font = Enum.Font.GothamBold
	spinButton.TextSize = 24
	spinButton.TextColor3 = Color3.fromRGB(252, 254, 255)
	spinButton.TextStrokeTransparency = 0.8
	spinButton.ZIndex = 7
	spinButton.Parent = root
	local spinCorner = Instance.new("UICorner")
	spinCorner.CornerRadius = UDim.new(0, 14)
	spinCorner.Parent = spinButton
	local spinStroke = Instance.new("UIStroke")
	spinStroke.Color = PALETTE.Cyan
	spinStroke.Thickness = 1.8
	spinStroke.Transparency = 0.15
	spinStroke.Parent = spinButton
	local spinGradient = Instance.new("UIGradient")
	spinGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, PALETTE.Cyan),
		ColorSequenceKeypoint.new(1, PALETTE.CyanDeep),
	})
	spinGradient.Rotation = 90
	spinGradient.Parent = spinButton

	local refs: Refs = {
		backdrop = backdrop,
		root = root,
		wheel = wheel,
		statusLabel = statusLabel,
		cooldownLabel = cooldownLabel,
		resultLabel = resultLabel,
		spinButton = spinButton,
		currentRotation = 0,
		isWaiting = false,
		isSpinning = false,
		requestToken = 0,
	}

	spinButton.MouseButton1Click:Connect(function()
		if refs.isWaiting or refs.isSpinning or not spinButton.Active then
			return
		end
		refs.isWaiting = true
		refs.requestToken += 1
		local token = refs.requestToken
		UIAnimator.buttonPunch(spinButton)
		spinButton.Active = false
		spinButton.Text = "SPINNING"
		statusLabel.Text = "SPINNING..."
		statusLabel.TextColor3 = PALETTE.Cyan
		cooldownLabel.Text = "WAITING FOR REWARD"
		resultLabel.Text = "REWARD: ..."
		resultLabel.TextColor3 = PALETTE.TextSoft
		RequestSpin:FireServer()
		task.delay(2.5, function()
			if refs.isWaiting and refs.requestToken == token then
				refs.isWaiting = false
				spinButton.Active = true
				spinButton.Text = "SPIN"
				statusLabel.Text = "FREE SPIN READY!"
				statusLabel.TextColor3 = PALETTE.Cyan
				cooldownLabel.Text = ""
				resultLabel.Text = "REWARD: -"
				resultLabel.TextColor3 = PALETTE.DnaGreen
			end
		end)
	end)

	SpinResult.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		local rewardId = payload.id
		if type(rewardId) ~= "string" then
			return
		end
		local displayName = tostring(payload.grantedDisplayName or payload.displayName or "Reward")
		local rarity = if type(payload.rarity) == "string" then payload.rarity else "Reward"
		animateToReward(refs, rewardId, displayName, rarity)
	end)

	return refs
end

function SpinFrame.show(refs: Refs)
	UIAnimator.framePopIn(refs.backdrop, refs.root)
end

function SpinFrame.tick(refs: Refs, state)
	if refs.isWaiting or refs.isSpinning then
		return
	end
	if not state or not state.Spin then
		return
	end
	if not state.ServerTime or state.ServerTime == 0 then
		return
	end
	local extrapolated = state.ServerTime + (os.clock() - (state._clientReceivedAt or os.clock()))
	local lastSpin = state.Spin.LastFreeSpin or 0
	local elapsed = extrapolated - lastSpin
	if elapsed >= SpinConfig.CooldownSec then
		refs.statusLabel.Text = "FREE SPIN READY"
		refs.statusLabel.TextColor3 = PALETTE.Cyan
		refs.cooldownLabel.Text = ""
		refs.spinButton.BackgroundColor3 = PALETTE.CyanDeep
		refs.spinButton.Active = true
		refs.spinButton.AutoButtonColor = true
		refs.spinButton.Text = "SPIN"
	else
		refs.statusLabel.Text = "COOLDOWN ACTIVE"
		refs.statusLabel.TextColor3 = PALETTE.TextMute
		refs.cooldownLabel.Text = "NEXT SPIN IN " .. formatCooldown(SpinConfig.CooldownSec - elapsed)
		refs.spinButton.BackgroundColor3 = PALETTE.PanelInset
		refs.spinButton.Active = false
		refs.spinButton.AutoButtonColor = false
		refs.spinButton.Text = "WAIT"
	end
end

return SpinFrame
