--!strict
-- Daily Quest UI: three daily goals with progress and claim buttons.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))
local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))

local Configs = ReplicatedStorage:WaitForChild("Configs")
local DailyQuestConfig = require(Configs:WaitForChild("DailyQuestConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestClaimDailyQuest = Remotes:WaitForChild("RequestClaimDailyQuest") :: RemoteEvent

local DailyQuestFrame = {}

type QuestCard = {
	card: Frame,
	title: TextLabel,
	desc: TextLabel,
	progress: TextLabel,
	reward: TextLabel,
	button: TextButton,
}

type Refs = {
	backdrop: Frame,
	root: Frame,
	streakLabel: TextLabel,
	resetLabel: TextLabel,
	cards: { QuestCard },
}

local function formatTime(sec: number): string
	sec = math.max(0, math.floor(sec))
	local h = math.floor(sec / 3600)
	local m = math.floor((sec % 3600) / 60)
	return string.format("%02dh %02dm", h, m)
end

local function rewardText(reward): string
	local parts = {}
	if reward.Dna then
		table.insert(parts, "+" .. NumberFormatter.format(reward.Dna) .. " DNA")
	end
	if reward.Power then
		table.insert(parts, "+" .. NumberFormatter.format(reward.Power) .. " Power")
	end
	if reward.Luck then
		table.insert(parts, "+" .. NumberFormatter.format(reward.Luck) .. " Luck")
	end
	if reward.QuestTokens then
		table.insert(parts, "+" .. tostring(reward.QuestTokens) .. " Quest Token")
	end
	return table.concat(parts, " | ")
end

local function makeCard(parent: Frame, index: number): QuestCard
	local card = Instance.new("Frame")
	card.Name = "QuestCard" .. tostring(index)
	card.Size = UDim2.new(1, 0, 0, 102)
	Theme.applyPanelStyle(card, Theme.Colors.PanelDark)
	card.ZIndex = 7
	card.Parent = parent

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -170, 0, 28)
	title.Position = UDim2.new(0, 12, 0, 8)
	Theme.applyLabelStyle(title)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Quest"
	title.TextSize = 21
	title.TextScaled = false
	title.ZIndex = 8
	title.Parent = card

	local desc = Instance.new("TextLabel")
	desc.Size = UDim2.new(1, -180, 0, 24)
	desc.Position = UDim2.new(0, 12, 0, 38)
	Theme.applyLabelStyle(desc)
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.Text = "-"
	desc.TextSize = 15
	desc.TextScaled = false
	desc.ZIndex = 8
	desc.Parent = card

	local progress = Instance.new("TextLabel")
	progress.Size = UDim2.new(0.5, -18, 0, 24)
	progress.Position = UDim2.new(0, 12, 0, 66)
	Theme.applyLabelStyle(progress)
	progress.TextXAlignment = Enum.TextXAlignment.Left
	progress.Text = "0 / 0"
	progress.TextSize = 15
	progress.TextScaled = false
	progress.ZIndex = 8
	progress.Parent = card

	local reward = Instance.new("TextLabel")
	reward.Size = UDim2.new(0.5, -18, 0, 24)
	reward.Position = UDim2.new(0.5, 0, 0, 66)
	Theme.applyLabelStyle(reward)
	reward.TextXAlignment = Enum.TextXAlignment.Left
	reward.Text = "-"
	reward.TextColor3 = Theme.Colors.Yellow
	reward.TextSize = 14
	reward.TextScaled = false
	reward.ZIndex = 8
	reward.Parent = card

	local button = Instance.new("TextButton")
	button.Name = "Claim"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Size = UDim2.new(0, 140, 0, 48)
	button.Position = UDim2.new(1, -12, 0.5, 0)
	Theme.applyButtonStyle(button, Theme.Colors.Green)
	button.Text = "CLAIM"
	button.TextSize = 16
	button.TextScaled = false
	button.ZIndex = 9
	button.Parent = card
	button.MouseButton1Click:Connect(function()
		local questId = button:GetAttribute("QuestId")
		if type(questId) == "string" and button:GetAttribute("CanClaim") == true then
			UIAnimator.buttonPunch(button)
			RequestClaimDailyQuest:FireServer(questId)
		end
	end)

	return { card = card, title = title, desc = desc, progress = progress, reward = reward, button = button }
end

function DailyQuestFrame.create(parent: ScreenGui): Refs
	local backdrop = Instance.new("Frame")
	backdrop.Name = "DailyQuestBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.DimBackdrop
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Visible = false
	backdrop.ZIndex = 5
	backdrop.Parent = parent

	local root = Instance.new("Frame")
	root.Name = "DailyQuestFrame"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.new(0, 660, 0, 500)
	Theme.applyPanelStyle(root, Theme.Colors.Orange)
	root.ZIndex = 6
	root.Parent = backdrop

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -16, 0, 40)
	header.Position = UDim2.new(0, 8, 0, 8)
	Theme.applyLabelStyle(header)
	header.Text = "DAILY QUESTS"
	header.TextSize = 28
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
	streakLabel.Size = UDim2.new(0.5, -24, 0, 28)
	streakLabel.Position = UDim2.new(0, 16, 0, 52)
	Theme.applyLabelStyle(streakLabel)
	streakLabel.TextXAlignment = Enum.TextXAlignment.Left
	streakLabel.Text = "Completed: 0"
	streakLabel.TextSize = 16
	streakLabel.TextScaled = false
	streakLabel.ZIndex = 7
	streakLabel.Parent = root

	local resetLabel = Instance.new("TextLabel")
	resetLabel.Size = UDim2.new(0.5, -24, 0, 28)
	resetLabel.Position = UDim2.new(0.5, 8, 0, 52)
	Theme.applyLabelStyle(resetLabel)
	resetLabel.TextXAlignment = Enum.TextXAlignment.Right
	resetLabel.Text = "Reset: --"
	resetLabel.TextSize = 16
	resetLabel.TextScaled = false
	resetLabel.ZIndex = 7
	resetLabel.Parent = root

	local list = Instance.new("Frame")
	list.Size = UDim2.new(1, -32, 1, -98)
	list.Position = UDim2.new(0, 16, 0, 88)
	list.BackgroundTransparency = 1
	list.ZIndex = 7
	list.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 10)
	layout.Parent = list

	local cards = {}
	for i = 1, DailyQuestConfig.QuestsPerDay do
		table.insert(cards, makeCard(list, i))
	end

	return { backdrop = backdrop, root = root, streakLabel = streakLabel, resetLabel = resetLabel, cards = cards }
end

function DailyQuestFrame.show(refs: Refs)
	UIAnimator.framePopIn(refs.backdrop, refs.root)
end

function DailyQuestFrame.update(refs: Refs, state)
	local daily = if type(state.DailyQuests) == "table" then state.DailyQuests else nil
	if not daily then
		return
	end
	refs.streakLabel.Text = string.format(
		"Completed: %d  |  Quest Tokens: %d",
		daily.CompletedCount or 0,
		daily.QuestTokens or 0
	)
	local serverTime = state.ServerTime or os.time()
	local resetAt = ((daily.LastResetDay or math.floor(serverTime / DailyQuestConfig.ResetSec)) + 1) * DailyQuestConfig.ResetSec
	refs.resetLabel.Text = "Reset in: " .. formatTime(resetAt - serverTime)

	for index, card in ipairs(refs.cards) do
		local entry = daily.Quests and daily.Quests[index]
		local def = entry and DailyQuestConfig.getById(entry.Id)
		if not entry or not def then
			card.card.Visible = false
			continue
		end
		card.card.Visible = true
		local progress = math.clamp(entry.Progress or 0, 0, def.required)
		local complete = progress >= def.required
		card.title.Text = def.displayName .. " [" .. def.difficulty .. "]"
		card.desc.Text = def.description
		card.progress.Text = NumberFormatter.format(progress) .. " / " .. NumberFormatter.format(def.required)
		card.reward.Text = rewardText(def.reward)
		card.button:SetAttribute("QuestId", def.id)

		if entry.Claimed then
			card.button.Text = "CLAIMED"
			card.button.BackgroundColor3 = Theme.Colors.PanelMedium
			card.button:SetAttribute("CanClaim", false)
		elseif complete then
			card.button.Text = "CLAIM"
			card.button.BackgroundColor3 = Theme.Colors.Green
			card.button:SetAttribute("CanClaim", true)
		else
			card.button.Text = "IN PROGRESS"
			card.button.BackgroundColor3 = Theme.Colors.PanelMedium
			card.button:SetAttribute("CanClaim", false)
		end
	end
end

function DailyQuestFrame.tick(refs: Refs, state)
	if not state or not state.ServerTime then
		return
	end
	local original = state.ServerTime
	state.ServerTime = original + (os.clock() - (state._clientReceivedAt or os.clock()))
	DailyQuestFrame.update(refs, state)
	state.ServerTime = original
end

return DailyQuestFrame
