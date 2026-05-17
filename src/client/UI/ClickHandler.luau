--!strict
-- Client-Rate-Limit + Floating-Text fuer Klicks und langsamer Free-Autoclick.
-- Server hat trotzdem das letzte Wort (AntiExploit hartet auf 10/s).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestClick = Remotes:WaitForChild("RequestClick") :: RemoteEvent

local ClickHandler = {}

local CLIENT_RATE = 10 -- pro Sekunde
local AUTO_CLICK_INTERVALS = {
	Free = 1.5,
	Premium = 0.35, -- fuer den spaeteren Shop/Gamepass-Autoclicker vorbereitet.
}
local AUTO_ON_COLOR = Color3.fromRGB(80, 255, 150)
local AUTO_OFF_COLOR = Color3.fromRGB(255, 95, 95)

local tokens = CLIENT_RATE
local lastRefill = os.clock()

local function consumeToken(): boolean
	local now = os.clock()
	tokens = math.min(CLIENT_RATE, tokens + (now - lastRefill) * CLIENT_RATE)
	lastRefill = now
	if tokens >= 1 then
		tokens -= 1
		return true
	end
	return false
end

local function requestPowerClick(screen: ScreenGui, button: TextButton, color: Color3, animateButton: boolean)
	if not consumeToken() then
		return
	end

	if animateButton then
		UIAnimator.buttonPunch(button)
		SoundController.play("Click")
	end

	RequestClick:FireServer()
	local absPos = button.AbsolutePosition + button.AbsoluteSize / 2
	UIAnimator.floatText(screen, "+1 Power", UDim2.fromOffset(absPos.X, absPos.Y - 20), color)
end

local function setAutoButtonState(button: TextButton, enabled: boolean)
	button.Text = if enabled then "AUTO: ON" else "AUTO: OFF"
	button.TextColor3 = if enabled then AUTO_ON_COLOR else AUTO_OFF_COLOR
end

function ClickHandler.bind(screen: ScreenGui, button: TextButton, color: Color3, autoButton: TextButton?)
	button.MouseButton1Click:Connect(function()
		requestPowerClick(screen, button, color, true)
	end)

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
				requestPowerClick(screen, button, color, false)
				task.wait(AUTO_CLICK_INTERVALS.Free)
			end
		end)
	end)
end

return ClickHandler
