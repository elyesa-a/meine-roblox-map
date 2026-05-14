--!strict
-- Daily Chest: zeigt aktuellen Streak (Tag 1..7), naechste Belohnung,
-- Cooldown-Timer + Abholen-Button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))
local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))

local Configs = ReplicatedStorage:WaitForChild("Configs")
local DailyChestConfig = require(Configs:WaitForChild("DailyChestConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestClaimDailyChest = Remotes:WaitForChild("RequestClaimDailyChest") :: RemoteEvent

local DailyChestFrame = {}

type Refs = {
	backdrop: Frame,
	root: Frame,
	streakLabel: TextLabel,
	rewardLabel: TextLabel,
	cooldownLabel: TextLabel,
	claimButton: TextButton,
	dayCards: { [number]: Frame },
}

local function formatCooldown(sec: number): string
	sec = math.max(0, math.floor(sec))
	local h = math.floor(sec / 3600)
	local m = math.floor((sec % 3600) / 60)
	local s = sec % 60
	return string.format("%02d:%02d:%02d", h, m, s)
end

function DailyChestFrame.create(parent: ScreenGui): Refs
	local backdrop = Instance.new("Frame")
	backdrop.Name = "DailyChestBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.DimBackdrop
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Visible = false
	backdrop.ZIndex = 5
	backdrop.Parent = parent

	local root = Instance.new("Frame")
	root.Name = "DailyChestFrame"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.new(0, 640, 0, 460)
	Theme.applyPanelStyle(root, Theme.Colors.Yellow)
	root.ZIndex = 6
	root.Parent = backdrop

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -16, 0, 40)
	header.Position = UDim2.new(0, 8, 0, 8)
	Theme.applyLabelStyle(header)
	header.Text = "TAEGLICHE BELOHNUNG"
	header.TextSize = 26
	header.TextScaled = false
	header.ZIndex = 7
	header.Parent = root

	local closeButton = Instance.new("TextButton")
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -8, 0, 8)
	closeButton.Size = UDim2.new(0, 36, 0, 36)
	closeButton.Text = "X"
	Theme.applyButtonStyle(closeButton, Theme.Colors.Red)
	closeButton.TextSize = 22
	closeButton.TextScaled = false
	closeButton.ZIndex = 8
	closeButton.Parent = root
	closeButton.MouseButton1Click:Connect(function()
		UIAnimator.framePopOut(backdrop, root)
	end)

	local streakLabel = Instance.new("TextLabel")
	streakLabel.Size = UDim2.new(1, -32, 0, 28)
	streakLabel.Position = UDim2.new(0, 16, 0, 52)
	Theme.applyLabelStyle(streakLabel)
	streakLabel.Text = "Streak: 0 Tage"
	streakLabel.TextSize = 18
	streakLabel.TextScaled = false
	streakLabel.ZIndex = 7
	streakLabel.Parent = root

	-- 7 Tages-Karten als horizontale Reihe.
	local daysHolder = Instance.new("Frame")
	daysHolder.Size = UDim2.new(1, -32, 0, 140)
	daysHolder.Position = UDim2.new(0, 16, 0, 88)
	daysHolder.BackgroundTransparency = 1
	daysHolder.ZIndex = 7
	daysHolder.Parent = root

	local dayLayout = Instance.new("UIListLayout")
	dayLayout.FillDirection = Enum.FillDirection.Horizontal
	dayLayout.Padding = UDim.new(0, 6)
	dayLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dayLayout.Parent = daysHolder

	local dayCards: { [number]: Frame } = {}
	for _, rew in ipairs(DailyChestConfig.Rewards) do
		local dayCard = Instance.new("Frame")
		dayCard.Size = UDim2.new(0, 78, 1, 0)
		Theme.applyPanelStyle(dayCard, Theme.Colors.PanelDark)
		dayCard.ZIndex = 7
		dayCard.Parent = daysHolder

		local dayLabel = Instance.new("TextLabel")
		dayLabel.Size = UDim2.new(1, 0, 0, 28)
		dayLabel.Position = UDim2.new(0, 0, 0, 6)
		Theme.applyLabelStyle(dayLabel)
		dayLabel.Text = "Tag " .. rew.streakDay
		dayLabel.TextSize = 14
		dayLabel.TextScaled = false
		dayLabel.ZIndex = 8
		dayLabel.Parent = dayCard

		local dnaLabel = Instance.new("TextLabel")
		dnaLabel.Size = UDim2.new(1, 0, 0, 22)
		dnaLabel.Position = UDim2.new(0, 0, 0, 40)
		Theme.applyLabelStyle(dnaLabel)
		dnaLabel.Text = string.format("+%s DNA", NumberFormatter.format(rew.dna))
		dnaLabel.TextSize = 12
		dnaLabel.TextScaled = false
		dnaLabel.ZIndex = 8
		dnaLabel.Parent = dayCard

		local powerLabel = Instance.new("TextLabel")
		powerLabel.Size = UDim2.new(1, 0, 0, 22)
		powerLabel.Position = UDim2.new(0, 0, 0, 62)
		Theme.applyLabelStyle(powerLabel)
		powerLabel.Text = string.format("+%s Kraft", NumberFormatter.format(rew.power))
		powerLabel.TextSize = 12
		powerLabel.TextScaled = false
		powerLabel.ZIndex = 8
		powerLabel.Parent = dayCard

		if rew.bonusText then
			local bonusLabel = Instance.new("TextLabel")
			bonusLabel.Size = UDim2.new(1, 0, 0, 18)
			bonusLabel.Position = UDim2.new(0, 0, 0, 90)
			Theme.applyLabelStyle(bonusLabel)
			bonusLabel.Text = rew.bonusText
			bonusLabel.TextSize = 12
			bonusLabel.TextColor3 = Theme.Colors.Yellow
			bonusLabel.TextScaled = false
			bonusLabel.ZIndex = 8
			bonusLabel.Parent = dayCard
		end

		dayCards[rew.streakDay] = dayCard
	end

	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Size = UDim2.new(1, -32, 0, 32)
	rewardLabel.Position = UDim2.new(0, 16, 0, 244)
	Theme.applyLabelStyle(rewardLabel)
	rewardLabel.Text = "Naechste Belohnung: ?"
	rewardLabel.TextSize = 18
	rewardLabel.TextScaled = false
	rewardLabel.ZIndex = 7
	rewardLabel.Parent = root

	local cooldownLabel = Instance.new("TextLabel")
	cooldownLabel.Size = UDim2.new(1, -32, 0, 28)
	cooldownLabel.Position = UDim2.new(0, 16, 0, 284)
	Theme.applyLabelStyle(cooldownLabel)
	cooldownLabel.Text = "Bereit!"
	cooldownLabel.TextSize = 16
	cooldownLabel.TextScaled = false
	cooldownLabel.ZIndex = 7
	cooldownLabel.Parent = root

	local claimButton = Instance.new("TextButton")
	claimButton.Name = "ClaimButton"
	claimButton.AnchorPoint = Vector2.new(0.5, 1)
	claimButton.Size = UDim2.new(1, -32, 0, 64)
	claimButton.Position = UDim2.new(0.5, 0, 1, -16)
	Theme.applyButtonStyle(claimButton, Theme.Colors.Green)
	claimButton.Text = "ABHOLEN"
	claimButton.TextSize = 22
	claimButton.TextScaled = false
	claimButton.ZIndex = 7
	claimButton.Parent = root

	claimButton.MouseButton1Click:Connect(function()
		UIAnimator.buttonPunch(claimButton)
		RequestClaimDailyChest:FireServer()
	end)

	return {
		backdrop = backdrop,
		root = root,
		streakLabel = streakLabel,
		rewardLabel = rewardLabel,
		cooldownLabel = cooldownLabel,
		claimButton = claimButton,
		dayCards = dayCards,
	}
end

function DailyChestFrame.show(refs: Refs)
	UIAnimator.framePopIn(refs.backdrop, refs.root)
end

-- Wird vom Tick aufgerufen, damit Cooldown live runterzaehlt.
function DailyChestFrame.tick(refs: Refs, state)
	if not state then
		return
	end
	local serverTime = state.ServerTime
	local chest = state.DailyChest
	if not serverTime or serverTime == 0 or not chest then
		return
	end
	local lastClaim = chest.LastClaim or 0
	-- Wir kennen die echte aktuelle Server-Zeit nicht; wir extrapolieren von
	-- der letzten ServerTime mit os.clock-Differenz, damit der Cooldown auch
	-- ohne staendige Updates runterlaeuft.
	local extrapolated = serverTime + (os.clock() - (state._clientReceivedAt or os.clock()))
	local elapsed = extrapolated - lastClaim
	local cooldown = DailyChestConfig.CooldownSec
	local resetAfter = DailyChestConfig.ResetAfterSec

	-- Naechster Streak
	local nextStreak
	if lastClaim == 0 or elapsed > resetAfter then
		nextStreak = 1
	else
		nextStreak = ((chest.Streak or 0)) + 1
	end
	if nextStreak < 1 then nextStreak = 1 end

	refs.streakLabel.Text = string.format("Aktueller Streak: %d Tage", chest.Streak or 0)

	local rew = DailyChestConfig.getReward(nextStreak)
	refs.rewardLabel.Text = string.format(
		"Tag %d: +%s DNA, +%s Kraft%s",
		((nextStreak - 1) % #DailyChestConfig.Rewards) + 1,
		NumberFormatter.format(rew.dna),
		NumberFormatter.format(rew.power),
		rew.bonusText and (" + " .. rew.bonusText) or ""
	)

	-- Cards highlighten: Tage <= aktueller Streak gruenlich.
	for day, card in pairs(refs.dayCards) do
		local highlight = (day <= ((chest.Streak or 0))) or (day == ((nextStreak - 1) % #DailyChestConfig.Rewards) + 1)
		card.BackgroundColor3 = if day == ((nextStreak - 1) % #DailyChestConfig.Rewards) + 1
			then Theme.Colors.Green
			elseif highlight then Theme.Colors.PanelMedium
			else Theme.Colors.PanelDark
	end

	if elapsed >= cooldown then
		refs.cooldownLabel.Text = "Bereit!"
		refs.claimButton.Text = "ABHOLEN"
		refs.claimButton.BackgroundColor3 = Theme.Colors.Green
		refs.claimButton.Active = true
	else
		refs.cooldownLabel.Text = "Naechste Belohnung in " .. formatCooldown(cooldown - elapsed)
		refs.claimButton.Text = "WARTEN"
		refs.claimButton.BackgroundColor3 = Theme.Colors.PanelMedium
		refs.claimButton.Active = false
	end
end

return DailyChestFrame
