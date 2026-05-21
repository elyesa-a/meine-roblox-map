--!strict
-- Story tutorial overlay for first-time players. It is intentionally separate
-- from gameplay systems: it highlights existing world/UI objects and listens
-- to existing state/progress updates.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent:WaitForChild("Theme"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestTutorialAction = Remotes:WaitForChild("RequestTutorialAction") :: RemoteEvent
local TutorialProgress = Remotes:WaitForChild("TutorialProgress") :: RemoteEvent

local TutorialFrame = {}

type Refs = {
	layer: Frame,
	panel: Frame,
	progressLabel: TextLabel,
	speakerLabel: TextLabel,
	titleLabel: TextLabel,
	bodyLabel: TextLabel,
	objectiveLabel: TextLabel,
	continueButton: TextButton,
	skipButton: TextButton,
	confirmPanel: Frame,
	confirmYes: TextButton,
	confirmNo: TextButton,
	uiHighlight: Frame,
	worldMarker: BillboardGui?,
	worldHighlight: Highlight?,
	uiFollowConn: RBXScriptConnection?,
	stepIndex: number,
	running: boolean,
	finishedLocal: boolean,
	events: { [string]: boolean },
	state: { [string]: any },
	stepStartPower: number,
}

type StepDef = {
	speaker: string,
	title: string,
	body: { string },
	objective: string?,
	markerText: string?,
	markerKind: string?,
	uiTargetName: string?,
	eventName: string?,
	condition: ((state: { [string]: any }, refs: Refs) -> boolean)?,
}

local LAB_DARK = Color3.fromRGB(8, 12, 18)
local PANEL = Color3.fromRGB(14, 20, 30)
local CYAN = Color3.fromRGB(0, 210, 190)
local GREEN = Color3.fromRGB(35, 220, 95)
local GOLD = Color3.fromRGB(255, 220, 80)
local RED = Color3.fromRGB(255, 70, 75)
local TEXT = Color3.fromRGB(245, 248, 255)
local MUTED = Color3.fromRGB(175, 185, 200)

local STEPS: { StepDef } = {
	{
		speaker = "Lab AI",
		title = "Subject Detected",
		body = {
			"Welcome to the Virus Lab.",
			"The outbreak has started. Your DNA is unstable, but it can evolve.",
			"Train, defeat viruses, collect DNA, hatch pets, and secure every quarantine sector.",
		},
		markerText = "SPAWN LAB",
		markerKind = "Spawn",
	},
	{
		speaker = "Lab AI",
		title = "Training Area",
		body = {
			"Your current body is too weak for infected zones.",
			"Use the Training Area to increase your Strength before entering quarantine pressure.",
		},
		objective = "Objective: Train once",
		markerText = "TRAIN HERE",
		markerKind = "Training",
		condition = function(state, refs)
			return (state.Power or 0) > refs.stepStartPower
		end,
	},
	{
		speaker = "Dr. Virox",
		title = "Infected Viruses",
		body = {
			"These viruses carry unstable DNA.",
			"Defeat them to collect DNA and push your mutation forward.",
		},
		objective = "Objective: Defeat 1 Virus",
		markerText = "FIGHT VIRUSES",
		markerKind = "Enemy",
		eventName = "EnemyDefeated",
	},
	{
		speaker = "System",
		title = "DNA Progression",
		body = {
			"DNA is your main evolution resource.",
			"Use it for pets, upgrades, boosts, and stronger mutation systems.",
		},
		markerText = "DNA / PWR",
		uiTargetName = "TopHUD",
	},
	{
		speaker = "Lab AI",
		title = "Egg Catch",
		body = {
			"Egg Catch contains captured lab organisms.",
			"Catch eggs to unlock pets and strengthen your mutation speed.",
		},
		objective = "Objective: Catch or hatch 1 egg",
		markerText = "EGG CATCH",
		markerKind = "EggCatch",
		eventName = "EggCaught",
	},
	{
		speaker = "Dr. Virox",
		title = "Pet Inventory",
		body = {
			"Pets are not cosmetic only.",
			"Equip your best pets before fighting stronger viruses.",
		},
		objective = "Objective: Open Pet Inventory",
		markerText = "PETS",
		uiTargetName = "PetsButton",
		eventName = "PetInventoryOpened",
	},
	{
		speaker = "Quarantine AI",
		title = "Boss Gates",
		body = {
			"Every quarantine area is locked behind a Boss Gate.",
			"Beat the current Area Boss to unlock the next sector. You cannot skip the required bosses.",
		},
		markerText = "BOSS GATE",
		markerKind = "Boss",
	},
	{
		speaker = "Lab AI",
		title = "Mutation Path Active",
		body = {
			"Tutorial complete. Your mutation path is active.",
			"Evolve, defeat the outbreak, and unlock every sector.",
		},
		objective = "Reward: +250 DNA, +25 Power",
	},
}

local function addCornerStroke(gui: GuiObject, radius: number, strokeColor: Color3, strokeTransparency: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = strokeColor
	stroke.Thickness = 1.5
	stroke.Transparency = strokeTransparency or 0.25
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = gui
end

local function makeLabel(parent: Instance, name: string, textSize: number, color: Color3, font: Enum.Font?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = font or Enum.Font.GothamMedium
	label.TextColor3 = color
	label.TextStrokeTransparency = 1
	label.TextSize = textSize
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.ZIndex = 82
	label.Parent = parent
	return label
end

local function makeButton(parent: Instance, text: string, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Text = text
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Theme.Font
	button.TextColor3 = TEXT
	button.TextSize = 14
	button.TextScaled = false
	button.TextStrokeTransparency = 1
	button.ZIndex = 83
	addCornerStroke(button, 10, color:Lerp(Color3.new(0, 0, 0), 0.35), 0.25)
	button.Parent = parent
	return button
end

local function firstBasePart(root: Instance?): BasePart?
	if not root then
		return nil
	end
	if root:IsA("BasePart") then
		return root
	end
	for _, desc in ipairs(root:GetDescendants()) do
		if desc:IsA("BasePart") then
			return desc
		end
	end
	return nil
end

local function findFirstChildByName(root: Instance?, name: string): Instance?
	if not root then
		return nil
	end
	local direct = root:FindFirstChild(name)
	if direct then
		return direct
	end
	return root:FindFirstChild(name, true)
end

local function findWorldTarget(kind: string?): Instance?
	if kind == "Spawn" then
		return findFirstChildByName(Workspace, "DNA_Core") or findFirstChildByName(Workspace, "LabSpawn")
	elseif kind == "Training" then
		return findFirstChildByName(Workspace, "Area1TrainingBed") or Workspace:FindFirstChild("TrainingBeds")
	elseif kind == "Enemy" then
		local area = findFirstChildByName(Workspace, "Area1")
		if area then
			for _, child in ipairs(area:GetChildren()) do
				if child:IsA("Model") and child:GetAttribute("IsBoss") ~= true then
					return child
				end
			end
		end
		return findFirstChildByName(Workspace, "A1E1")
	elseif kind == "EggCatch" then
		local folder = Workspace:FindFirstChild("EggStations")
		if folder then
			for _, child in ipairs(folder:GetChildren()) do
				if child:IsA("Model") then
					return child
				end
			end
		end
		return folder
	elseif kind == "Boss" then
		local area = findFirstChildByName(Workspace, "Area1")
		if area then
			for _, child in ipairs(area:GetChildren()) do
				if child:IsA("Model") and child:GetAttribute("IsBoss") == true then
					return child
				end
			end
		end
		return findFirstChildByName(Workspace, "A1E10")
	end
	return nil
end

local function clearWorldMarker(refs: Refs)
	if refs.worldMarker then
		refs.worldMarker:Destroy()
		refs.worldMarker = nil
	end
	if refs.worldHighlight then
		refs.worldHighlight:Destroy()
		refs.worldHighlight = nil
	end
end

local function showWorldMarker(refs: Refs, target: Instance?, text: string?)
	clearWorldMarker(refs)
	local part = firstBasePart(target)
	if not part then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "TutorialWorldHighlight"
	highlight.FillColor = GREEN
	highlight.FillTransparency = 0.82
	highlight.OutlineColor = CYAN
	highlight.OutlineTransparency = 0.1
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Adornee = if target and (target:IsA("Model") or target:IsA("BasePart")) then target else part
	highlight.Parent = part
	refs.worldHighlight = highlight

	local marker = Instance.new("BillboardGui")
	marker.Name = "TutorialMarker"
	marker.Size = UDim2.fromOffset(190, 54)
	marker.StudsOffset = Vector3.new(0, 9, 0)
	marker.AlwaysOnTop = true
	marker.MaxDistance = 220
	marker.Parent = part

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(8, 14, 16)
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Parent = marker
	addCornerStroke(frame, 12, CYAN, 0.18)

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.Text = text or "OBJECTIVE"
	label.TextColor3 = Color3.fromRGB(185, 255, 210)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.2
	label.TextSize = 18
	label.TextWrapped = true
	label.Parent = frame

	refs.worldMarker = marker
end

local function clearUiHighlight(refs: Refs)
	if refs.uiFollowConn then
		refs.uiFollowConn:Disconnect()
		refs.uiFollowConn = nil
	end
	refs.uiHighlight.Visible = false
end

local function findUiTarget(name: string?): GuiObject?
	if not name then
		return nil
	end
	local gui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not gui then
		return nil
	end
	local found = gui:FindFirstChild(name, true)
	if found and found:IsA("GuiObject") then
		return found
	end
	return nil
end

local function showUiHighlight(refs: Refs, target: GuiObject?)
	clearUiHighlight(refs)
	if not target then
		return
	end
	refs.uiHighlight.Visible = true
	refs.uiFollowConn = RunService.RenderStepped:Connect(function()
		if not target.Parent or not refs.uiHighlight.Parent then
			clearUiHighlight(refs)
			return
		end
		refs.uiHighlight.Position = UDim2.fromOffset(target.AbsolutePosition.X - 6, target.AbsolutePosition.Y - 6)
		refs.uiHighlight.Size = UDim2.fromOffset(target.AbsoluteSize.X + 12, target.AbsoluteSize.Y + 12)
	end)
end

local function clearHighlights(refs: Refs)
	clearWorldMarker(refs)
	clearUiHighlight(refs)
end

local function stepDone(refs: Refs, step: StepDef): boolean
	if step.eventName and refs.events[step.eventName] then
		return true
	end
	if step.eventName == "EggCaught" and (refs.events.EggHatched or refs.events.PetRewardAdded or refs.events.EggPreviewOpened) then
		return true
	end
	if step.condition then
		return step.condition(refs.state, refs)
	end
	return false
end

local function renderStep(refs: Refs)
	local step = STEPS[refs.stepIndex]
	if not step then
		return
	end
	clearHighlights(refs)

	refs.progressLabel.Text = string.format("Tutorial %d/%d", refs.stepIndex, #STEPS)
	refs.speakerLabel.Text = step.speaker
	refs.titleLabel.Text = step.title
	refs.bodyLabel.Text = table.concat(step.body, "\n")
	refs.objectiveLabel.Text = step.objective or "Press Continue when ready."
	refs.objectiveLabel.TextColor3 = if step.objective then GOLD else MUTED
	refs.stepStartPower = refs.state.Power or 0
	refs.events = {}

	showWorldMarker(refs, findWorldTarget(step.markerKind), step.markerText)
	showUiHighlight(refs, findUiTarget(step.uiTargetName))

	refs.panel.Position = UDim2.new(0.5, 0, 1, 26)
	TweenService:Create(refs.panel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 1, -22),
	}):Play()
end

local function finishLocal(refs: Refs)
	refs.running = false
	refs.finishedLocal = true
	clearHighlights(refs)
	refs.confirmPanel.Visible = false
	refs.layer.Visible = false
end

local function advance(refs: Refs)
	if not refs.running then
		return
	end
	if refs.stepIndex >= #STEPS then
		RequestTutorialAction:FireServer("Complete")
		finishLocal(refs)
		return
	end
	refs.stepIndex += 1
	renderStep(refs)
end

local function startTutorial(refs: Refs)
	if refs.running or refs.finishedLocal then
		return
	end
	refs.running = true
	refs.stepIndex = 1
	refs.events = {}
	refs.layer.Visible = true
	renderStep(refs)
end

function TutorialFrame.create(parent: ScreenGui): Refs
	local layer = Instance.new("Frame")
	layer.Name = "TutorialLayer"
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundTransparency = 1
	layer.Visible = false
	layer.ZIndex = 80
	layer.Parent = parent

	local panel = Instance.new("Frame")
	panel.Name = "TutorialPanel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -22)
	panel.Size = UDim2.new(0.92, 0, 0, 190)
	panel.BackgroundColor3 = PANEL
	panel.BackgroundTransparency = 0.04
	panel.BorderSizePixel = 0
	panel.ZIndex = 81
	panel.Parent = layer
	addCornerStroke(panel, 18, CYAN, 0.22)
	local panelConstraint = Instance.new("UISizeConstraint")
	panelConstraint.MaxSize = Vector2.new(640, 190)
	panelConstraint.MinSize = Vector2.new(320, 190)
	panelConstraint.Parent = panel

	local progressLabel = makeLabel(panel, "ProgressLabel", 12, MUTED, Enum.Font.GothamBold)
	progressLabel.Position = UDim2.new(0, 18, 0, 12)
	progressLabel.Size = UDim2.new(0, 180, 0, 18)

	local speakerLabel = makeLabel(panel, "SpeakerLabel", 13, GREEN, Enum.Font.GothamBlack)
	speakerLabel.Position = UDim2.new(0, 18, 0, 34)
	speakerLabel.Size = UDim2.new(0, 190, 0, 18)

	local titleLabel = makeLabel(panel, "TitleLabel", 21, TEXT, Enum.Font.GothamBlack)
	titleLabel.Position = UDim2.new(0, 18, 0, 56)
	titleLabel.Size = UDim2.new(1, -36, 0, 26)

	local bodyLabel = makeLabel(panel, "BodyLabel", 15, Color3.fromRGB(218, 230, 238), Enum.Font.GothamMedium)
	bodyLabel.Position = UDim2.new(0, 18, 0, 88)
	bodyLabel.Size = UDim2.new(1, -210, 0, 64)

	local objectiveLabel = makeLabel(panel, "ObjectiveLabel", 13, GOLD, Enum.Font.GothamBold)
	objectiveLabel.Position = UDim2.new(0, 18, 1, -30)
	objectiveLabel.Size = UDim2.new(1, -240, 0, 20)

	local skipButton = makeButton(panel, "Skip Tutorial", RED)
	skipButton.AnchorPoint = Vector2.new(1, 0)
	skipButton.Position = UDim2.new(1, -14, 0, 12)
	skipButton.Size = UDim2.new(0, 126, 0, 30)

	local continueButton = makeButton(panel, "Continue", GREEN)
	continueButton.AnchorPoint = Vector2.new(1, 1)
	continueButton.Position = UDim2.new(1, -14, 1, -14)
	continueButton.Size = UDim2.new(0, 132, 0, 38)

	local confirmPanel = Instance.new("Frame")
	confirmPanel.Name = "SkipConfirm"
	confirmPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	confirmPanel.Position = UDim2.fromScale(0.5, 0.5)
	confirmPanel.Size = UDim2.new(0.82, 0, 0, 150)
	confirmPanel.BackgroundColor3 = LAB_DARK
	confirmPanel.BackgroundTransparency = 0.02
	confirmPanel.Visible = false
	confirmPanel.ZIndex = 90
	confirmPanel.Parent = layer
	addCornerStroke(confirmPanel, 16, RED, 0.2)
	local confirmConstraint = Instance.new("UISizeConstraint")
	confirmConstraint.MaxSize = Vector2.new(360, 150)
	confirmConstraint.MinSize = Vector2.new(300, 150)
	confirmConstraint.Parent = confirmPanel

	local confirmText = makeLabel(confirmPanel, "ConfirmText", 18, TEXT, Enum.Font.GothamBlack)
	confirmText.Text = "Skip tutorial?"
	confirmText.TextXAlignment = Enum.TextXAlignment.Center
	confirmText.Position = UDim2.new(0, 18, 0, 24)
	confirmText.Size = UDim2.new(1, -36, 0, 30)

	local confirmSub = makeLabel(confirmPanel, "ConfirmSub", 13, MUTED, Enum.Font.GothamMedium)
	confirmSub.Text = "You can continue playing immediately."
	confirmSub.TextXAlignment = Enum.TextXAlignment.Center
	confirmSub.Position = UDim2.new(0, 18, 0, 58)
	confirmSub.Size = UDim2.new(1, -36, 0, 24)

	local confirmYes = makeButton(confirmPanel, "Yes, skip", RED)
	confirmYes.Position = UDim2.new(0, 34, 1, -48)
	confirmYes.Size = UDim2.new(0, 130, 0, 34)

	local confirmNo = makeButton(confirmPanel, "Continue tutorial", GREEN)
	confirmNo.Position = UDim2.new(1, -174, 1, -48)
	confirmNo.Size = UDim2.new(0, 140, 0, 34)

	local uiHighlight = Instance.new("Frame")
	uiHighlight.Name = "TutorialUIHighlight"
	uiHighlight.BackgroundTransparency = 1
	uiHighlight.Visible = false
	uiHighlight.ZIndex = 88
	uiHighlight.Parent = layer
	addCornerStroke(uiHighlight, 12, GREEN, 0.05)

	local refs: Refs = {
		layer = layer,
		panel = panel,
		progressLabel = progressLabel,
		speakerLabel = speakerLabel,
		titleLabel = titleLabel,
		bodyLabel = bodyLabel,
		objectiveLabel = objectiveLabel,
		continueButton = continueButton,
		skipButton = skipButton,
		confirmPanel = confirmPanel,
		confirmYes = confirmYes,
		confirmNo = confirmNo,
		uiHighlight = uiHighlight,
		worldMarker = nil,
		worldHighlight = nil,
		uiFollowConn = nil,
		stepIndex = 1,
		running = false,
		finishedLocal = false,
		events = {},
		state = {},
		stepStartPower = 0,
	}

	continueButton.MouseButton1Click:Connect(function()
		advance(refs)
	end)
	skipButton.MouseButton1Click:Connect(function()
		confirmPanel.Visible = true
	end)
	confirmNo.MouseButton1Click:Connect(function()
		confirmPanel.Visible = false
	end)
	confirmYes.MouseButton1Click:Connect(function()
		RequestTutorialAction:FireServer("Skip")
		finishLocal(refs)
	end)

	TutorialProgress.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		local eventName = payload.Event
		if type(eventName) == "string" then
			TutorialFrame.record(refs, eventName)
		end
	end)

	return refs
end

function TutorialFrame.record(refs: Refs, eventName: string)
	if not refs.running then
		return
	end
	refs.events[eventName] = true
	local step = STEPS[refs.stepIndex]
	if step and stepDone(refs, step) then
		task.delay(0.35, function()
			if refs.running and STEPS[refs.stepIndex] == step and stepDone(refs, step) then
				advance(refs)
			end
		end)
	end
end

function TutorialFrame.update(refs: Refs, state: { [string]: any })
	refs.state = state
	if state.HasCompletedTutorial == true then
		if refs.running then
			finishLocal(refs)
		end
		refs.finishedLocal = true
		return
	end

	if state.HasCompletedTutorial == false then
		startTutorial(refs)
	end

	if refs.running then
		local step = STEPS[refs.stepIndex]
		if step and stepDone(refs, step) then
			TweenService:Create(refs.objectiveLabel, TweenInfo.new(0.15), {
				TextColor3 = GREEN,
			}):Play()
		end
	end
end

return TutorialFrame
