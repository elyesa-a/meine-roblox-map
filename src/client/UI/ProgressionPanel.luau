--!strict
-- Compact right objective HUD: current mission + next zone progress.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))

local Configs = ReplicatedStorage:WaitForChild("Configs")
local ZoneConfig = require(Configs:WaitForChild("ZoneConfig"))
local DailyQuestConfig = require(Configs:WaitForChild("DailyQuestConfig"))

local ProgressionPanel = {}

type Refs = {
	root: Frame,
	missionPanel: Frame,
	zoneName: TextLabel,
	zoneReq: TextLabel,
	zoneCurrent: TextLabel,
	zoneFill: Frame,
	missionTitle: TextLabel,
	missionDesc: TextLabel,
	missionProgress: TextLabel,
	missionReward: TextLabel,
	missionFill: Frame,
	missionCollapse: TextButton,
	missionCollapsed: boolean,
}

local function stylePanel(frame: Frame, accent: Color3)
	frame.BackgroundColor3 = Color3.fromRGB(13, 18, 26)
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = accent
	stroke.Thickness = 1.25
	stroke.Transparency = 0.38
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
end

local function makeLabel(parent: Instance, name: string, textSize: number, color: Color3?, bold: boolean?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = if bold == false then Enum.Font.GothamMedium else Theme.Font
	label.TextColor3 = color or Theme.Colors.White
	label.TextStrokeTransparency = 1
	label.TextSize = textSize
	label.TextScaled = false
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function makeProgress(parent: Frame, y: number, color: Color3): Frame
	local bg = Instance.new("Frame")
	bg.Name = "ProgressTrack"
	bg.Position = UDim2.new(0, 10, 0, y)
	bg.Size = UDim2.new(1, -20, 0, 5)
	bg.BackgroundColor3 = Color3.fromRGB(4, 8, 12)
	bg.BorderSizePixel = 0
	bg.Parent = parent

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(1, 0)
	bgCorner.Parent = bg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = bg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	return fill
end

local function rewardText(reward): string
	local parts = {}
	if reward and reward.Dna then
		table.insert(parts, "+" .. NumberFormatter.format(reward.Dna) .. " DNA")
	end
	if reward and reward.Power then
		table.insert(parts, "+" .. NumberFormatter.format(reward.Power) .. " Power")
	end
	if reward and reward.Luck then
		table.insert(parts, "+" .. NumberFormatter.format(reward.Luck) .. " Luck")
	end
	if reward and reward.QuestTokens then
		table.insert(parts, "+" .. tostring(reward.QuestTokens) .. " Token")
	end
	return if #parts > 0 then table.concat(parts, " | ") else "+50 DNA"
end

local function findNextZone(state)
	local power = state.Power or 0
	local rebirths = state.Rebirths or 0
	local fallback = nil

	for _, zone in ipairs(ZoneConfig) do
		if zone.enabled and zone.id ~= "StartZone" then
			fallback = zone
			if power < zone.requiredPower or rebirths < zone.requiredRebirth then
				return zone
			end
		end
	end

	return fallback
end

local function getMission(state)
	local daily = if type(state.DailyQuests) == "table" then state.DailyQuests else nil
	if daily and type(daily.Quests) == "table" then
		for _, entry in ipairs(daily.Quests) do
			local def = entry and DailyQuestConfig.getById(entry.Id)
			if def and not entry.Claimed then
				return def, entry
			end
		end
	end

	return {
		displayName = "Starter Mission",
		description = "Collect 100 DNA",
		required = 100,
		reward = { Dna = 50 },
	}, { Progress = math.min(state.DnaCoins or 0, 100), Claimed = false }
end

function ProgressionPanel.create(parent: ScreenGui): Refs
	local root = Instance.new("Frame")
	root.Name = "RightObjectivePanel"
	root.AnchorPoint = Vector2.new(1, 0)
	root.Position = UDim2.new(1, -24, 0, 135)
	root.Size = UDim2.new(0, 300, 0, 190)
	root.BackgroundTransparency = 1
	root.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 8)
	layout.Parent = root

	local mission = Instance.new("Frame")
	mission.Name = "CurrentMissionPanel"
	mission.Size = UDim2.new(1, 0, 0, 88)
	stylePanel(mission, Theme.Colors.Green)
	mission.Parent = root

	local missionHeader = makeLabel(mission, "Header", 11, Color3.fromRGB(123, 255, 224), true)
	missionHeader.Position = UDim2.new(0, 10, 0, 8)
	missionHeader.Size = UDim2.new(1, -46, 0, 14)
	missionHeader.Text = "CURRENT MISSION"

	local missionCollapse = Instance.new("TextButton")
	missionCollapse.Name = "CollapseButton"
	missionCollapse.AnchorPoint = Vector2.new(1, 0)
	missionCollapse.Position = UDim2.new(1, -8, 0, 6)
	missionCollapse.Size = UDim2.new(0, 22, 0, 18)
	missionCollapse.BackgroundColor3 = Color3.fromRGB(19, 27, 36)
	missionCollapse.BorderSizePixel = 0
	missionCollapse.Font = Theme.Font
	missionCollapse.Text = "-"
	missionCollapse.TextColor3 = Color3.fromRGB(123, 255, 224)
	missionCollapse.TextSize = 13
	missionCollapse.TextScaled = false
	missionCollapse.TextStrokeTransparency = 1
	missionCollapse.Parent = mission
	local collapseCorner = Instance.new("UICorner")
	collapseCorner.CornerRadius = UDim.new(0, 6)
	collapseCorner.Parent = missionCollapse

	local missionTitle = makeLabel(mission, "MissionTitle", 15, Theme.Colors.White, true)
	missionTitle.Position = UDim2.new(0, 10, 0, 24)
	missionTitle.Size = UDim2.new(1, -20, 0, 18)
	missionTitle.Text = "Collect DNA"

	local missionDesc = makeLabel(mission, "MissionDesc", 12, Color3.fromRGB(195, 224, 230), false)
	missionDesc.Position = UDim2.new(0, 10, 0, 43)
	missionDesc.Size = UDim2.new(1, -20, 0, 15)
	missionDesc.Text = "Collect 100 DNA"

	local missionFill = makeProgress(mission, 61, Color3.fromRGB(56, 236, 207))

	local missionProgress = makeLabel(mission, "MissionProgress", 11, Color3.fromRGB(175, 255, 230), false)
	missionProgress.Position = UDim2.new(0, 10, 0, 72)
	missionProgress.Size = UDim2.new(0.5, -10, 0, 12)
	missionProgress.Text = "0 / 100"

	local missionReward = makeLabel(mission, "MissionReward", 11, Theme.Colors.Yellow, true)
	missionReward.Position = UDim2.new(0.5, 0, 0, 72)
	missionReward.Size = UDim2.new(0.5, -10, 0, 12)
	missionReward.TextXAlignment = Enum.TextXAlignment.Right
	missionReward.Text = "Reward: +50 DNA"

	local nextZone = Instance.new("Frame")
	nextZone.Name = "NextZonePanel"
	nextZone.Size = UDim2.new(1, 0, 0, 88)
	stylePanel(nextZone, Color3.fromRGB(56, 236, 207))
	nextZone.Parent = root

	local zoneHeader = makeLabel(nextZone, "Header", 11, Color3.fromRGB(123, 255, 224), true)
	zoneHeader.Position = UDim2.new(0, 10, 0, 8)
	zoneHeader.Size = UDim2.new(1, -20, 0, 14)
	zoneHeader.Text = "NEXT ZONE"

	local zoneName = makeLabel(nextZone, "ZoneName", 16, Theme.Colors.White, true)
	zoneName.Position = UDim2.new(0, 10, 0, 24)
	zoneName.Size = UDim2.new(1, -20, 0, 18)
	zoneName.Text = "Toxic Cell Zone"

	local zoneReq = makeLabel(nextZone, "RequiredPower", 12, Color3.fromRGB(195, 224, 230), false)
	zoneReq.Position = UDim2.new(0, 10, 0, 44)
	zoneReq.Size = UDim2.new(1, -20, 0, 15)
	zoneReq.Text = "Required: 500 PWR"

	local zoneFill = makeProgress(nextZone, 62, Theme.Colors.Green)

	local zoneCurrent = makeLabel(nextZone, "CurrentPower", 11, Color3.fromRGB(175, 255, 230), false)
	zoneCurrent.Position = UDim2.new(0, 10, 0, 74)
	zoneCurrent.Size = UDim2.new(1, -20, 0, 12)
	zoneCurrent.Text = "0 / 500"

	local collapsed = false
	missionCollapse.MouseButton1Click:Connect(function()
		collapsed = not collapsed
		missionCollapse.Text = if collapsed then "+" else "-"
		missionDesc.Visible = not collapsed
		missionProgress.Visible = not collapsed
		missionReward.Visible = not collapsed
		missionFill.Parent.Visible = not collapsed
		TweenService:Create(mission, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = if collapsed then UDim2.new(1, 0, 0, 48) else UDim2.new(1, 0, 0, 88),
		}):Play()
		TweenService:Create(root, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = if collapsed then UDim2.new(0, 300, 0, 146) else UDim2.new(0, 300, 0, 190),
		}):Play()
	end)

	return {
		root = root,
		missionPanel = mission,
		zoneName = zoneName,
		zoneReq = zoneReq,
		zoneCurrent = zoneCurrent,
		zoneFill = zoneFill,
		missionTitle = missionTitle,
		missionDesc = missionDesc,
		missionProgress = missionProgress,
		missionReward = missionReward,
		missionFill = missionFill,
		missionCollapse = missionCollapse,
		missionCollapsed = false,
	}
end

function ProgressionPanel.update(refs: Refs, state)
	local zone = findNextZone(state)
	if zone then
		local power = state.Power or 0
		local required = math.max(zone.requiredPower or 0, 1)
		local progress = math.clamp(power / required, 0, 1)
		refs.zoneName.Text = zone.displayName
		refs.zoneReq.Text = "Required: " .. NumberFormatter.format(zone.requiredPower or 0) .. " PWR"
		local currentText = NumberFormatter.format(power) .. " / " .. NumberFormatter.format(zone.requiredPower or 0)
		refs.zoneCurrent.Text = if progress >= 0.9 and progress < 1 then currentText .. "  Almost unlocked!" else currentText
		refs.zoneFill.Size = UDim2.new(progress, 0, 1, 0)
	else
		refs.zoneName.Text = "All Zones Unlocked"
		refs.zoneReq.Text = "Keep evolving your mutation"
		refs.zoneCurrent.Text = "MAX"
		refs.zoneFill.Size = UDim2.fromScale(1, 1)
	end

	local def, entry = getMission(state)
	local progress = math.clamp(entry.Progress or 0, 0, def.required)
	refs.missionTitle.Text = def.displayName or "Current Mission"
	refs.missionDesc.Text = def.description or "Complete your lab task"
	refs.missionProgress.Text = NumberFormatter.format(progress) .. " / " .. NumberFormatter.format(def.required)
	refs.missionReward.Text = "Reward: " .. rewardText(def.reward)
	refs.missionFill.Size = UDim2.new(if def.required > 0 then math.clamp(progress / def.required, 0, 1) else 0, 0, 1, 0)
end

return ProgressionPanel
