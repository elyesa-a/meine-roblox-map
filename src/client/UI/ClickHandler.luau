--!strict
-- Client-Rate-Limit + Floating-Text fuer Klicks.
-- Server hat trotzdem das letzte Wort (AntiExploit hartet auf 10/s).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestClick = Remotes:WaitForChild("RequestClick") :: RemoteEvent

local ClickHandler = {}

local CLIENT_RATE = 10 -- pro Sekunde
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

function ClickHandler.bind(screen: ScreenGui, button: TextButton, color: Color3)
	button.MouseButton1Click:Connect(function()
		if not consumeToken() then
			return
		end
		UIAnimator.buttonPunch(button)
		SoundController.play("Click")
		RequestClick:FireServer()
		-- Optimistischer Floating-Text (Server berechnet das echte Plus).
		local absPos = button.AbsolutePosition + button.AbsoluteSize / 2
		UIAnimator.floatText(screen, "+1 Power", UDim2.fromOffset(absPos.X, absPos.Y - 20), color)
	end)
end

return ClickHandler
