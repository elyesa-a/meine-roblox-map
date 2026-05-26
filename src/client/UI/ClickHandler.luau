--!strict
-- Client-Rate-Limit + Floating-Text fuer Klicks und langsamer Free-Autoclick.
-- Server hat trotzdem das letzte Wort (AntiExploit hartet auf 10/s).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local NumberFormatter = require(Modules:WaitForChild("NumberFormatter"))
local UIAnimator = require(Modules:WaitForChild("UIAnimator"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestClick = Remotes:WaitForChild("RequestClick") :: RemoteEvent
local RequestAutoFight = Remotes:WaitForChild("RequestAutoFight") :: RemoteEvent
local AutoFightState = Remotes:WaitForChild("AutoFightState") :: RemoteEvent
local RequestAutoTraining = Remotes:WaitForChild("RequestAutoTraining") :: RemoteEvent
local AutoTrainingState = Remotes:WaitForChild("AutoTrainingState") :: RemoteEvent

local ClickHandler = {}

type PendingClickPopup = {
	screen: ScreenGui,
	anchorPos: UDim2,
	color: Color3,
}

local CLIENT_RATE = 7 -- pro Sekunde, passend zum serverseitigen 0.15s Cooldown.
local CLIENT_COOLDOWN = 0.15
local MAX_PENDING_CLICK_POPUPS = 12
local AUTO_CLICK_INTERVALS = {
	Free = 1.5,
	Premium = 0.35, -- fuer den spaeteren Shop/Gamepass-Autoclicker vorbereitet.
}
local AUTO_ON_COLOR = Color3.fromRGB(80, 255, 125)
local AUTO_OFF_COLOR = Color3.fromRGB(255, 88, 88)
local AUTO_ON_BACKGROUND = Color3.fromRGB(14, 70, 34)
local AUTO_OFF_BACKGROUND = Color3.fromRGB(42, 18, 24)
local MOVEMENT_KEYS = {
	[Enum.KeyCode.W] = true,
	[Enum.KeyCode.A] = true,
	[Enum.KeyCode.S] = true,
	[Enum.KeyCode.D] = true,
	[Enum.KeyCode.Up] = true,
	[Enum.KeyCode.Down] = true,
	[Enum.KeyCode.Left] = true,
	[Enum.KeyCode.Right] = true,
	[Enum.KeyCode.Space] = true,
}

local tokens = CLIENT_RATE
local lastRefill = os.clock()
local lastClickAt = 0
local boundScreenClick = false
local boundPowerFeedback = false
local nextClickRequestId = 0
local pendingClickPopups: { [number]: PendingClickPopup } = {}
local pendingClickOrder: { number } = {}

local function consumeToken(): boolean
	local now = os.clock()
	if now - lastClickAt < CLIENT_COOLDOWN then
		return false
	end
	tokens = math.min(CLIENT_RATE, tokens + (now - lastRefill) * CLIENT_RATE)
	lastRefill = now
	if tokens >= 1 then
		tokens -= 1
		lastClickAt = now
		return true
	end
	return false
end

local function formatPowerGain(amount: number): string
	if amount >= 1000 then
		return NumberFormatter.format(amount)
	end
	return NumberFormatter.formatDecimal(amount, 2)
end

local function showPowerPopup(screen: ScreenGui, anchorPos: UDim2, color: Color3, amount: number)
	UIAnimator.floatText(screen, "+" .. formatPowerGain(amount) .. " Power", anchorPos, color)
end

local function popPendingClick(clickRequestId: number): PendingClickPopup?
	local pending = pendingClickPopups[clickRequestId]
	if not pending then
		return nil
	end
	pendingClickPopups[clickRequestId] = nil
	local orderIndex = table.find(pendingClickOrder, clickRequestId)
	if orderIndex then
		table.remove(pendingClickOrder, orderIndex)
	end
	return pending
end

local function popOldestPendingClick(): PendingClickPopup?
	local clickRequestId = table.remove(pendingClickOrder, 1)
	if not clickRequestId then
		return nil
	end
	return popPendingClick(clickRequestId)
end

local function queuePowerPopup(screen: ScreenGui, anchorPos: UDim2, color: Color3): number
	while #pendingClickOrder >= MAX_PENDING_CLICK_POPUPS do
		popOldestPendingClick()
	end

	nextClickRequestId += 1
	pendingClickPopups[nextClickRequestId] = {
		screen = screen,
		anchorPos = anchorPos,
		color = color,
	}
	table.insert(pendingClickOrder, nextClickRequestId)
	return nextClickRequestId
end

local function bindPowerFeedback()
	if boundPowerFeedback then
		return
	end
	boundPowerFeedback = true
	RequestClick.OnClientEvent:Connect(function(powerGain, clickRequestId)
		if type(powerGain) ~= "number" then
			return
		end
		if powerGain <= 0 or powerGain ~= powerGain then
			return
		end

		local pending: PendingClickPopup?
		if type(clickRequestId) == "number" then
			pending = popPendingClick(clickRequestId)
		else
			pending = popOldestPendingClick()
		end
		if not pending or not pending.screen.Parent then
			return
		end

		showPowerPopup(pending.screen, pending.anchorPos, pending.color, powerGain)
	end)
end

local function requestPowerClick(screen: ScreenGui, color: Color3, anchorPos: UDim2): boolean
	if not consumeToken() then
		return false
	end

	local clickRequestId = queuePowerPopup(screen, anchorPos, color)
	RequestClick:FireServer(clickRequestId)
	SoundController.play("Click")
	return true
end

local function requestPowerButtonClick(screen: ScreenGui, button: TextButton, color: Color3, animateButton: boolean)
	local absPos = button.AbsolutePosition + button.AbsoluteSize / 2
	local didRequest = requestPowerClick(screen, color, UDim2.fromOffset(absPos.X, absPos.Y - 20))
	if didRequest and animateButton then
		UIAnimator.buttonPunch(button)
	end
end

local function isInside(instance: Instance, ancestor: Instance): boolean
	local current: Instance? = instance
	while current do
		if current == ancestor then
			return true
		end
		current = current.Parent
	end
	return false
end

local function isOverBlockingGui(inputPosition: Vector2, allowedButton: TextButton): boolean
	local screenGui = allowedButton:FindFirstAncestorOfClass("ScreenGui")
	if not screenGui then
		return false
	end
	-- GetGuiObjectsAtPosition lebt auf PlayerGui (LayerCollector), NICHT auf
	-- GuiService. Wir greifen ueber das ScreenGui des Buttons zur PlayerGui.
	local playerGui = screenGui:FindFirstAncestorOfClass("PlayerGui")
	if not playerGui then
		return false
	end
	for _, guiObject in ipairs(playerGui:GetGuiObjectsAtPosition(inputPosition.X, inputPosition.Y)) do
		if guiObject.Name == "FloatingText" then
			continue
		end
		if guiObject.Visible and isInside(guiObject, allowedButton) then
			return true
		end
		if guiObject.Visible and guiObject:IsDescendantOf(screenGui) then
			return true
		end
	end
	return false
end

local function setAutoButtonState(button: TextButton, enabled: boolean)
	button.Text = if enabled then "AUTO: ON" else "AUTO: OFF"
	button.TextColor3 = if enabled then AUTO_ON_COLOR else AUTO_OFF_COLOR
	button.BackgroundColor3 = if enabled then AUTO_ON_BACKGROUND else AUTO_OFF_BACKGROUND
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if enabled then AUTO_ON_COLOR else AUTO_OFF_COLOR
		stroke.Transparency = 0.08
	end
	button.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	button.TextStrokeTransparency = 0
	button.TextTransparency = 0
	button.Font = Enum.Font.GothamBlack
end

local function setAutoFightButtonState(button: TextButton, enabled: boolean)
	button.Text = if enabled then "AUTO FIGHT: ON" else "AUTO FIGHT: OFF"
	button.TextColor3 = if enabled then AUTO_ON_COLOR else AUTO_OFF_COLOR
	button.BackgroundColor3 = if enabled then AUTO_ON_BACKGROUND else AUTO_OFF_BACKGROUND
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if enabled then AUTO_ON_COLOR else AUTO_OFF_COLOR
		stroke.Transparency = 0.08
	end
	button.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	button.TextStrokeTransparency = 0
	button.TextTransparency = 0
	button.Font = Enum.Font.GothamBlack
end

local function setAutoTrainingButtonState(button: TextButton, enabled: boolean)
	button.Text = if enabled then "AUTO TRAIN: ON" else "AUTO TRAIN: OFF"
	button.TextColor3 = if enabled then AUTO_ON_COLOR else AUTO_OFF_COLOR
	button.BackgroundColor3 = if enabled then AUTO_ON_BACKGROUND else AUTO_OFF_BACKGROUND
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if enabled then AUTO_ON_COLOR else AUTO_OFF_COLOR
		stroke.Transparency = 0.08
	end
	button.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	button.TextStrokeTransparency = 0
	button.TextTransparency = 0
	button.Font = Enum.Font.GothamBlack
end

local function showAutoMessage(screen: ScreenGui, button: TextButton, text: string)
	local absPos = button.AbsolutePosition + button.AbsoluteSize / 2
	UIAnimator.floatText(screen, text, UDim2.fromOffset(absPos.X, absPos.Y - 24), AUTO_ON_COLOR)
end

function ClickHandler.bind(
	screen: ScreenGui,
	button: TextButton,
	color: Color3,
	autoButton: TextButton?,
	autoFightButton: TextButton?,
	autoTrainingButton: TextButton?
)
	bindPowerFeedback()

	button.MouseButton1Click:Connect(function()
		requestPowerButtonClick(screen, button, color, true)
	end)

	if not boundScreenClick then
		boundScreenClick = true
		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			if UserInputService:GetFocusedTextBox() then
				return
			end

			local inputPos = Vector2.new(input.Position.X, input.Position.Y)
			if isOverBlockingGui(inputPos, button) then
				return
			end
			requestPowerClick(screen, color, UDim2.fromOffset(inputPos.X, inputPos.Y - 16))
		end)
	end

	if not autoButton then
		return
	end

	local autoEnabled = false
	local autoFightEnabled = false
	local autoTrainingEnabled = false
	setAutoButtonState(autoButton, false)
	if autoFightButton then
		setAutoFightButtonState(autoFightButton, false)
		AutoFightState.OnClientEvent:Connect(function(enabled: boolean)
			autoFightEnabled = enabled == true
			setAutoFightButtonState(autoFightButton, autoFightEnabled)
			if autoFightEnabled and autoEnabled then
				autoEnabled = false
				setAutoButtonState(autoButton, false)
				showAutoMessage(screen, autoFightButton, "Auto Clicker disabled")
			end
			if autoFightEnabled and autoTrainingEnabled then
				autoTrainingEnabled = false
				if autoTrainingButton then
					setAutoTrainingButtonState(autoTrainingButton, false)
				end
				showAutoMessage(screen, autoFightButton, "Auto Training disabled")
			end
		end)
	end
	if autoTrainingButton then
		setAutoTrainingButtonState(autoTrainingButton, false)
		AutoTrainingState.OnClientEvent:Connect(function(enabled: boolean)
			autoTrainingEnabled = enabled == true
			setAutoTrainingButtonState(autoTrainingButton, autoTrainingEnabled)
			if autoTrainingEnabled and autoEnabled then
				autoEnabled = false
				setAutoButtonState(autoButton, false)
				showAutoMessage(screen, autoTrainingButton, "Auto Clicker disabled")
			end
			if autoTrainingEnabled and autoFightEnabled then
				autoFightEnabled = false
				if autoFightButton then
					setAutoFightButtonState(autoFightButton, false)
				end
				showAutoMessage(screen, autoTrainingButton, "Auto Fight disabled")
			end
		end)
	end

	local function cancelAutoModesForManualMovement()
		if UserInputService:GetFocusedTextBox() then
			return
		end
		if autoFightEnabled then
			autoFightEnabled = false
			if autoFightButton then
				setAutoFightButtonState(autoFightButton, false)
				showAutoMessage(screen, autoFightButton, "Auto Fight disabled")
			end
			RequestAutoFight:FireServer(false)
		end
		if autoTrainingEnabled then
			autoTrainingEnabled = false
			if autoTrainingButton then
				setAutoTrainingButtonState(autoTrainingButton, false)
				showAutoMessage(screen, autoTrainingButton, "Auto Training disabled")
			end
			RequestAutoTraining:FireServer(false)
		end
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or (not autoFightEnabled and not autoTrainingEnabled) then
			return
		end
		if input.UserInputType == Enum.UserInputType.Keyboard and MOVEMENT_KEYS[input.KeyCode] then
			cancelAutoModesForManualMovement()
		elseif input.UserInputType == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.ButtonA then
			cancelAutoModesForManualMovement()
		end
	end)

	UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if gameProcessed or (not autoFightEnabled and not autoTrainingEnabled) then
			return
		end
		if input.UserInputType == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.Thumbstick1 then
			local pos = input.Position
			if math.abs(pos.X) > 0.18 or math.abs(pos.Y) > 0.18 then
				cancelAutoModesForManualMovement()
			end
		end
	end)

	autoButton.MouseButton1Click:Connect(function()
		if autoFightEnabled then
			autoFightEnabled = false
			if autoFightButton then
				setAutoFightButtonState(autoFightButton, false)
			end
			RequestAutoFight:FireServer(false)
		end
		if autoTrainingEnabled then
			autoTrainingEnabled = false
			if autoTrainingButton then
				setAutoTrainingButtonState(autoTrainingButton, false)
			end
			RequestAutoTraining:FireServer(false)
		end
		autoEnabled = not autoEnabled
		setAutoButtonState(autoButton, autoEnabled)
		UIAnimator.buttonPunch(autoButton)

		if not autoEnabled then
			return
		end

		task.spawn(function()
			while autoEnabled and not autoFightEnabled and not autoTrainingEnabled and autoButton.Parent do
				requestPowerButtonClick(screen, button, color, false)
				task.wait(AUTO_CLICK_INTERVALS.Free)
			end
		end)
	end)

	if autoFightButton then
		autoFightButton.MouseButton1Click:Connect(function()
			if autoEnabled then
				autoEnabled = false
				setAutoButtonState(autoButton, false)
				showAutoMessage(screen, autoFightButton, "Auto Clicker disabled")
			end
			if autoTrainingEnabled then
				autoTrainingEnabled = false
				if autoTrainingButton then
					setAutoTrainingButtonState(autoTrainingButton, false)
				end
				RequestAutoTraining:FireServer(false)
				showAutoMessage(screen, autoFightButton, "Auto Training disabled")
			end
			autoFightEnabled = not autoFightEnabled
			setAutoFightButtonState(autoFightButton, autoFightEnabled)
			UIAnimator.buttonPunch(autoFightButton)
			RequestAutoFight:FireServer(autoFightEnabled)
		end)
	end

	if autoTrainingButton then
		autoTrainingButton.MouseButton1Click:Connect(function()
			if autoEnabled then
				autoEnabled = false
				setAutoButtonState(autoButton, false)
				showAutoMessage(screen, autoTrainingButton, "Auto Clicker disabled")
			end
			if autoFightEnabled then
				autoFightEnabled = false
				if autoFightButton then
					setAutoFightButtonState(autoFightButton, false)
				end
				RequestAutoFight:FireServer(false)
				showAutoMessage(screen, autoTrainingButton, "Auto Fight disabled")
			end
			autoTrainingEnabled = not autoTrainingEnabled
			setAutoTrainingButtonState(autoTrainingButton, autoTrainingEnabled)
			UIAnimator.buttonPunch(autoTrainingButton)
			RequestAutoTraining:FireServer(autoTrainingEnabled)
		end)
	end
end

return ClickHandler
