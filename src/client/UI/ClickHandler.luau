--!strict
-- Client-Rate-Limit + Floating-Text fuer Klicks und langsamer Free-Autoclick.
-- Server hat trotzdem das letzte Wort (AntiExploit hartet auf 10/s).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestClick = Remotes:WaitForChild("RequestClick") :: RemoteEvent

local ClickHandler = {}

local CLIENT_RATE = 7 -- pro Sekunde, passend zum serverseitigen 0.15s Cooldown.
local CLIENT_COOLDOWN = 0.15
local AUTO_CLICK_INTERVALS = {
	Free = 1.5,
	Premium = 0.35, -- fuer den spaeteren Shop/Gamepass-Autoclicker vorbereitet.
}
local AUTO_ON_COLOR = Color3.fromRGB(80, 255, 150)
local AUTO_OFF_COLOR = Color3.fromRGB(255, 95, 95)

local tokens = CLIENT_RATE
local lastRefill = os.clock()
local lastClickAt = 0
local boundScreenClick = false

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

local function showPowerPopup(screen: ScreenGui, anchorPos: UDim2, color: Color3)
	UIAnimator.floatText(screen, "+1 Power", anchorPos, color)
end

local function requestPowerClick(screen: ScreenGui, color: Color3, anchorPos: UDim2): boolean
	if not consumeToken() then
		return false
	end

	RequestClick:FireServer()
	showPowerPopup(screen, anchorPos, color)
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
	for _, guiObject in ipairs(GuiService:GetGuiObjectsAtPosition(inputPosition.X, inputPosition.Y)) do
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
end

function ClickHandler.bind(screen: ScreenGui, button: TextButton, color: Color3, autoButton: TextButton?)
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
	setAutoButtonState(autoButton, false)

	autoButton.MouseButton1Click:Connect(function()
		autoEnabled = not autoEnabled
		setAutoButtonState(autoButton, autoEnabled)
		UIAnimator.buttonPunch(autoButton)

		if not autoEnabled then
			return
		end

		task.spawn(function()
			while autoEnabled and autoButton.Parent do
				requestPowerButtonClick(screen, button, color, false)
				task.wait(AUTO_CLICK_INTERVALS.Free)
			end
		end)
	end)
end

return ClickHandler
