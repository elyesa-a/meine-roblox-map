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

local SEGMENT_COLORS = {
	Color3.fromRGB(246, 250, 255),
	Color3.fromRGB(65, 145, 255),
	Color3.fromRGB(245, 70, 82),
}
local WHEEL_DIAMETER = 390
local WHEEL_RADIUS = WHEEL_DIAMETER / 2
local TILE_SIZE = 10
local LABEL_RADIUS = 130

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
				local color = SEGMENT_COLORS[((segmentIndex - 1) % #SEGMENT_COLORS) + 1]

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
	local color = SEGMENT_COLORS[((index - 1) % #SEGMENT_COLORS) + 1]
	local midAngle = -90 + (index - 0.5) * segmentAngle
	local radians = math.rad(midAngle)
	local labelX = WHEEL_RADIUS + math.cos(radians) * LABEL_RADIUS
	local labelY = WHEEL_RADIUS + math.sin(radians) * LABEL_RADIUS

	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Name = "RewardLabel"
	rewardLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	rewardLabel.Size = UDim2.new(0, 82, 0, 34)
	rewardLabel.Position = UDim2.fromOffset(labelX, labelY)
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Font = Enum.Font.GothamBold
	rewardLabel.Text = reward.displayName
	rewardLabel.TextWrapped = true
	rewardLabel.TextScaled = true
	rewardLabel.TextColor3 = textColorFor(color)
	rewardLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	rewardLabel.TextStrokeTransparency = if color == SEGMENT_COLORS[1] then 0.75 else 0.15
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
	refs.cooldownLabel.Text = "LANDING ON REWARD"
	refs.resultLabel.Text = "REWARD: ..."

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
	end)
end

function SpinFrame.create(parent: ScreenGui): Refs
	local backdrop = Instance.new("Frame")
	backdrop.Name = "SpinBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.DimBackdrop
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Visible = false
	backdrop.ZIndex = 5
	backdrop.Parent = parent

	local root = Instance.new("Frame")
	root.Name = "SpinFrame"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.new(0, 620, 0, 700)
	Theme.applyPanelStyle(root, Theme.Colors.Yellow)
	root.ZIndex = 6
	root.Parent = backdrop

	local header = makeLabel(root, "LUCKY WHEEL", UDim2.new(1, -76, 0, 42), UDim2.new(0, 16, 0, 10), 7)
	header.TextSize = 30
	header.TextScaled = false

	local closeButton = Instance.new("TextButton")
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -10, 0, 10)
	closeButton.Size = UDim2.new(0, 38, 0, 38)
	closeButton.Text = "X"
	Theme.applyButtonStyle(closeButton, Theme.Colors.Red)
	closeButton.TextSize = 22
	closeButton.TextScaled = false
	closeButton.ZIndex = 12
	closeButton.Parent = root
	closeButton.MouseButton1Click:Connect(function()
		UIAnimator.framePopOut(backdrop, root)
	end)

	local wheelHolder = makeCircle(root, "WheelHolder", UDim2.fromOffset(WHEEL_DIAMETER, WHEEL_DIAMETER), UDim2.new(0.5, 0, 0, 270), Color3.fromRGB(20, 25, 38), 7)
	wheelHolder.ClipsDescendants = false
	local holderStroke = Instance.new("UIStroke")
	holderStroke.Color = Color3.fromRGB(255, 235, 120)
	holderStroke.Thickness = 5
	holderStroke.Transparency = 0.05
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

	for i = 1, #SpinConfig.Rewards do
		local spoke = Instance.new("Frame")
		spoke.Name = "Spoke_" .. tostring(i)
		spoke.AnchorPoint = Vector2.new(0.5, 0.5)
		spoke.Size = UDim2.new(0, WHEEL_DIAMETER - 10, 0, 3)
		spoke.Position = UDim2.fromScale(0.5, 0.5)
		spoke.Rotation = (i - 1) * (360 / #SpinConfig.Rewards) - 90
		spoke.BackgroundColor3 = Color3.fromRGB(18, 24, 36)
		spoke.BorderSizePixel = 0
		spoke.ZIndex = 11
		spoke.Parent = wheel
	end

	local center = makeCircle(wheelHolder, "CenterCircle", UDim2.new(0, 62, 0, 62), UDim2.fromScale(0.5, 0.5), Color3.fromRGB(32, 39, 56), 14)
	local centerStroke = Instance.new("UIStroke")
	centerStroke.Color = Color3.fromRGB(255, 255, 255)
	centerStroke.Thickness = 3
	centerStroke.Transparency = 0.08
	centerStroke.Parent = center

	local pointer = Instance.new("Frame")
	pointer.Name = "Pointer"
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.Size = UDim2.new(0, 30, 0, 30)
	pointer.Position = UDim2.new(0.5, 0, 0, -2)
	pointer.Rotation = 45
	pointer.BackgroundColor3 = Color3.fromRGB(255, 65, 80)
	pointer.BorderSizePixel = 0
	pointer.ZIndex = 16
	pointer.Parent = wheelHolder
	local pointerStroke = Instance.new("UIStroke")
	pointerStroke.Color = Color3.fromRGB(255, 255, 255)
	pointerStroke.Thickness = 2
	pointerStroke.Parent = pointer

	local statusLabel = makeLabel(root, "FREE SPIN READY!", UDim2.new(1, -32, 0, 28), UDim2.new(0, 16, 0, 480), 7)
	statusLabel.TextSize = 18
	statusLabel.TextScaled = false

	local cooldownLabel = makeLabel(root, "", UDim2.new(1, -32, 0, 22), UDim2.new(0, 16, 0, 512), 7)
	cooldownLabel.TextSize = 14
	cooldownLabel.TextScaled = false

	local resultLabel = makeLabel(root, "REWARD: -", UDim2.new(1, -32, 0, 32), UDim2.new(0, 16, 0, 548), 7)
	resultLabel.TextSize = 18
	resultLabel.TextScaled = false
	resultLabel.TextColor3 = Theme.Colors.Yellow

	local spinButton = Instance.new("TextButton")
	spinButton.Name = "SpinButton"
	spinButton.AnchorPoint = Vector2.new(0.5, 1)
	spinButton.Size = UDim2.new(1, -42, 0, 58)
	spinButton.Position = UDim2.new(0.5, 0, 1, -18)
	Theme.applyButtonStyle(spinButton, Theme.Colors.Green)
	spinButton.Text = "SPIN"
	spinButton.TextSize = 24
	spinButton.TextScaled = false
	spinButton.ZIndex = 7
	spinButton.Parent = root

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
		cooldownLabel.Text = "WAITING FOR REWARD"
		resultLabel.Text = "REWARD: ..."
		RequestSpin:FireServer()
		task.delay(2.5, function()
			if refs.isWaiting and refs.requestToken == token then
				refs.isWaiting = false
				spinButton.Active = true
				spinButton.Text = "SPIN"
				statusLabel.Text = "FREE SPIN READY!"
				cooldownLabel.Text = ""
				resultLabel.Text = "REWARD: -"
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
		refs.statusLabel.Text = "FREE SPIN READY!"
		refs.cooldownLabel.Text = ""
		refs.spinButton.BackgroundColor3 = Theme.Colors.Green
		refs.spinButton.Active = true
		refs.spinButton.AutoButtonColor = true
		refs.spinButton.Text = "SPIN"
	else
		refs.statusLabel.Text = "COOLDOWN ACTIVE..."
		refs.cooldownLabel.Text = "NEXT SPIN IN " .. formatCooldown(SpinConfig.CooldownSec - elapsed)
		refs.spinButton.BackgroundColor3 = Theme.Colors.PanelMedium
		refs.spinButton.Active = false
		refs.spinButton.AutoButtonColor = false
		refs.spinButton.Text = "WAIT"
	end
end

return SpinFrame
