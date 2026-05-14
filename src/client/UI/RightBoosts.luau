--!strict
-- Rechte Seite: Boost-/Gamepass-Buttons.
--  * DNA-Boosts: kaufbar via RequestBuyBoost (Phase 4), zeigen Restzeit, wenn
--    aktiv.
--  * Gamepass-Eintraege: oeffnen einen Robux-Platzhalter-Popup.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))

local Configs = ReplicatedStorage:WaitForChild("Configs")
local BoostConfig = require(Configs:WaitForChild("BoostConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestBuyBoost = Remotes:WaitForChild("RequestBuyBoost") :: RemoteEvent
local RequestPromptPurchase = Remotes:WaitForChild("RequestPromptPurchase") :: RemoteEvent

local RightBoosts = {}

type BoostEntry = {
	kind: "Boost",
	boostId: string,
	label: string,
	color: Color3,
}

type GamepassEntry = {
	kind: "Gamepass",
	gamepassId: string,
	label: string,
	color: Color3,
	robux: number,
}

type Entry = BoostEntry | GamepassEntry

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
	{ kind = "Boost",   boostId = "Power2x", label = "2X KRAFT",    color = Theme.Colors.Red },
	{ kind = "Boost",   boostId = "Dna2x",   label = "2X DNA",      color = Theme.Colors.Blue },
	{ kind = "Boost",   boostId = "Luck2x",  label = "2X GLUECK",   color = Theme.Colors.Yellow },
	{ kind = "Gamepass", gamepassId = "AutoClicker", label = "AUTO-KLICK", color = Theme.Colors.Pink,   robux = 99 },
	{ kind = "Gamepass", gamepassId = "VipZone",     label = "VIP-ZONE",   color = Theme.Colors.Orange, robux = 39 },
	{ kind = "Gamepass", gamepassId = "GlitchPet",   label = "GLITCH-PET", color = Theme.Colors.Purple, robux = 279 },
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
	frame.Size = UDim2.new(0, 110, 0, 78)
	frame.BackgroundTransparency = 1
	frame.Parent = parent

	local button = Instance.new("TextButton")
	button.Name = "Btn"
	button.Size = UDim2.fromScale(1, 1)
	button.Text = ""
	Theme.applyButtonStyle(button, entry.color)
	button.AutoButtonColor = true
	button.Active = true
	button.Parent = frame

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -6, 0, 22)
	titleLabel.Position = UDim2.new(0, 3, 0, 6)
	Theme.applyLabelStyle(titleLabel)
	titleLabel.Text = entry.label
	titleLabel.TextSize = 14
	titleLabel.TextScaled = false
	titleLabel.Parent = button

	local subLabel = Instance.new("TextLabel")
	subLabel.Size = UDim2.new(1, -6, 0, 22)
	subLabel.Position = UDim2.new(0, 3, 0, 30)
	Theme.applyLabelStyle(subLabel)
	if entry.kind == "Gamepass" then
		subLabel.Text = string.format("NUR %d R$", entry.robux)
	else
		local def = BoostConfig.getById(entry.boostId)
		subLabel.Text = if def then string.format("%d DNA", def.priceDna) else "?"
	end
	subLabel.TextSize = 12
	subLabel.TextScaled = false
	subLabel.Parent = button

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Size = UDim2.new(1, -6, 0, 22)
	timerLabel.Position = UDim2.new(0, 3, 0, 52)
	Theme.applyLabelStyle(timerLabel)
	timerLabel.Text = ""
	timerLabel.TextSize = 12
	timerLabel.TextScaled = false
	timerLabel.TextColor3 = Theme.Colors.Yellow
	timerLabel.Parent = button

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

function RightBoosts.create(parent: ScreenGui, onGamepass: ((string, number) -> ())?): Refs
	local holder = Instance.new("Frame")
	holder.Name = "RightBoosts"
	holder.AnchorPoint = Vector2.new(1, 0.5)
	holder.Position = UDim2.new(1, -16, 0.5, 0)
	holder.Size = UDim2.new(0, 120, 0, #ENTRIES * 86)
	holder.BackgroundTransparency = 1
	holder.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 6)
	layout.Parent = holder

	local buttonRefs: { [string]: ButtonRefs } = {}

	local function handleClick(entry: Entry)
		if entry.kind == "Boost" then
			RequestBuyBoost:FireServer(entry.boostId)
		else
			-- Direkter Prompt-Kauf. Wenn assetId noch 0 ist, zeigt Server "bald verfuegbar".
			RequestPromptPurchase:FireServer(entry.gamepassId)
			if onGamepass then
				onGamepass(entry.gamepassId, entry.robux)
			end
		end
	end

	for _, entry in ipairs(ENTRIES) do
		local key = if entry.kind == "Boost" then entry.boostId else entry.gamepassId
		buttonRefs[key] = makeButton(holder, entry, handleClick)
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
		if entry.kind ~= "Boost" then
			continue
		end
		local btnRefs = refs.buttonRefs[entry.boostId]
		if not btnRefs then
			continue
		end
		local expiry = activeBoosts[entry.boostId]
		if expiry and expiry > extrapolated then
			local remain = expiry - extrapolated
			btnRefs.timerLabel.Text = formatTime(remain)
			btnRefs.button.BackgroundColor3 = Theme.Colors.Green
		else
			btnRefs.timerLabel.Text = ""
			btnRefs.button.BackgroundColor3 = entry.color
		end
	end
end

return RightBoosts
