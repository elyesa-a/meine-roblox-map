--!strict
-- Rechte Seite: DNA-Boost-Buttons.
--  * DNA-Boosts: kaufbar via RequestBuyBoost (Phase 4), zeigen Restzeit, wenn
--    aktiv.
-- (Gamepasses gibt es nur noch im Shop, daher hier entfernt.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))

local Configs = ReplicatedStorage:WaitForChild("Configs")
local BoostConfig = require(Configs:WaitForChild("BoostConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestBuyBoost = Remotes:WaitForChild("RequestBuyBoost") :: RemoteEvent

local RightBoosts = {}

type Entry = {
	boostId: string,
	label: string,
	icon: string,
	color: Color3,
}

type ButtonRefs = {
	frame: Frame,
	titleLabel: TextLabel,
	subLabel: TextLabel,
	timerLabel: TextLabel,
	button: TextButton,
}

type Refs = {
	root: Frame,
	entries: { Entry },
	buttonRefs: { [string]: ButtonRefs },
}

local ENTRIES: { Entry } = {
	{ boostId = "Dna2x",   label = "2X DNA",   icon = "DNA", color = Color3.fromRGB(56, 236, 207) },
	{ boostId = "Luck2x",  label = "2X LUCK",  icon = "LCK", color = Theme.Colors.Yellow },
	{ boostId = "Power2x", label = "2X POWER", icon = "PWR", color = Theme.Colors.Green },
}

local function formatTime(sec: number): string
	sec = math.max(0, math.floor(sec))
	local m = math.floor(sec / 60)
	local s = sec % 60
	return string.format("%02d:%02d", m, s)
end

local function makeButton(parent: Frame, entry: Entry, onClick: (Entry) -> ()): ButtonRefs
	local frame = Instance.new("Frame")
	frame.Name = entry.label
	frame.Size = UDim2.new(0, 104, 0, 72)
	frame.BackgroundTransparency = 1
	frame.Parent = parent

	local button = Instance.new("TextButton")
	button.Name = "Btn"
	button.Size = UDim2.fromScale(1, 1)
	button.Text = ""
	Theme.applyButtonStyle(button, Color3.fromRGB(13, 18, 26))
	button.AutoButtonColor = false
	button.Active = true
	button.Parent = frame
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = entry.color
		stroke.Thickness = 1.5
		stroke.Transparency = 0.32
	end

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.AnchorPoint = Vector2.new(0.5, 0)
	iconLabel.Position = UDim2.new(0.5, 0, 0, 6)
	iconLabel.Size = UDim2.new(0, 38, 0, 20)
	iconLabel.BackgroundColor3 = Color3.fromRGB(4, 8, 12)
	iconLabel.BorderSizePixel = 0
	iconLabel.Font = Enum.Font.GothamBlack
	iconLabel.Text = entry.icon
	iconLabel.TextColor3 = entry.color
	iconLabel.TextSize = 12
	iconLabel.TextScaled = false
	iconLabel.TextStrokeTransparency = 1
	iconLabel.Parent = button
	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(1, 0)
	iconCorner.Parent = iconLabel

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -8, 0, 20)
	titleLabel.Position = UDim2.new(0, 4, 0, 30)
	Theme.applyLabelStyle(titleLabel)
	titleLabel.Text = entry.label
	titleLabel.TextSize = 12
	titleLabel.TextScaled = false
	titleLabel.TextStrokeTransparency = 1
	titleLabel.Parent = button

	local subLabel = Instance.new("TextLabel")
	subLabel.Size = UDim2.new(1, -8, 0, 18)
	subLabel.Position = UDim2.new(0, 4, 0, 49)
	Theme.applyLabelStyle(subLabel)
	local def = BoostConfig.getById(entry.boostId)
	subLabel.Text = if def then string.format("%d DNA", def.priceDna) else "?"
	subLabel.TextSize = 12
	subLabel.TextScaled = false
	subLabel.TextColor3 = Color3.fromRGB(197, 224, 230)
	subLabel.TextStrokeTransparency = 1
	subLabel.Parent = button

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Size = UDim2.new(1, -8, 0, 14)
	timerLabel.Position = UDim2.new(0, 4, 0, 62)
	Theme.applyLabelStyle(timerLabel)
	timerLabel.Text = ""
	timerLabel.TextSize = 11
	timerLabel.TextScaled = false
	timerLabel.TextColor3 = Theme.Colors.Yellow
	timerLabel.TextStrokeTransparency = 1
	timerLabel.Parent = button

	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), {
			BackgroundColor3 = Color3.fromRGB(22, 32, 44),
			Size = UDim2.new(1, 2, 1, 2),
		}):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), {
			BackgroundColor3 = Color3.fromRGB(13, 18, 26),
			Size = UDim2.fromScale(1, 1),
		}):Play()
	end)

	button.MouseButton1Click:Connect(function()
		UIAnimator.buttonPunch(button)
		onClick(entry)
	end)

	return {
		frame = frame,
		titleLabel = titleLabel,
		subLabel = subLabel,
		timerLabel = timerLabel,
		button = button,
	}
end

function RightBoosts.create(parent: ScreenGui): Refs
	local holder = Instance.new("Frame")
	holder.Name = "BoostShopPanel"
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.Position = UDim2.new(1, -24, 0, 345)
	holder.Size = UDim2.new(0, 124, 0, #ENTRIES * 78 + 32)
	holder.BackgroundColor3 = Color3.fromRGB(9, 13, 20)
	holder.BackgroundTransparency = 0.1
	holder.BorderSizePixel = 0
	holder.Parent = parent
	local holderCorner = Instance.new("UICorner")
	holderCorner.CornerRadius = UDim.new(0, 14)
	holderCorner.Parent = holder
	local holderStroke = Instance.new("UIStroke")
	holderStroke.Color = Color3.fromRGB(56, 236, 207)
	holderStroke.Thickness = 1.5
	holderStroke.Transparency = 0.55
	holderStroke.Parent = holder

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -12, 0, 24)
	title.Position = UDim2.new(0, 6, 0, 6)
	title.BackgroundTransparency = 1
	title.Font = Theme.Font
	title.Text = "BOOSTS"
	title.TextColor3 = Color3.fromRGB(138, 255, 226)
	title.TextSize = 12
	title.TextScaled = false
	title.TextStrokeTransparency = 1
	title.Parent = holder

	local list = Instance.new("Frame")
	list.Name = "List"
	list.Position = UDim2.new(0, 10, 0, 30)
	list.Size = UDim2.new(1, -20, 1, -36)
	list.BackgroundTransparency = 1
	list.Parent = holder

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = list

	local buttonRefs: { [string]: ButtonRefs } = {}

	local function handleClick(entry: Entry)
		RequestBuyBoost:FireServer(entry.boostId)
	end

	for _, entry in ipairs(ENTRIES) do
		buttonRefs[entry.boostId] = makeButton(list, entry, handleClick)
	end

	return {
		root = holder,
		entries = ENTRIES,
		buttonRefs = buttonRefs,
	}
end

-- Aktualisiert nur die Boost-Timer / -Status. Wird vom Tick-Loop aufgerufen.
function RightBoosts.tick(refs: Refs, state)
	if not state then
		return
	end
	local activeBoosts = state.ActiveBoosts or {}
	local serverTime = state.ServerTime
	if not serverTime or serverTime == 0 then
		return
	end
	local extrapolated = serverTime + (os.clock() - (state._clientReceivedAt or os.clock()))

	for _, entry in ipairs(refs.entries) do
		local btnRefs = refs.buttonRefs[entry.boostId]
		if not btnRefs then
			continue
		end
		local expiry = activeBoosts[entry.boostId]
		if expiry and expiry > extrapolated then
			local remain = expiry - extrapolated
			btnRefs.timerLabel.Text = formatTime(remain)
			btnRefs.button.BackgroundColor3 = Color3.fromRGB(16, 44, 34)
		else
			btnRefs.timerLabel.Text = ""
			btnRefs.button.BackgroundColor3 = Color3.fromRGB(13, 18, 26)
		end
	end
end

return RightBoosts
