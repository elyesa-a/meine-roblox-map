--!strict
-- DEV: Rechter Unlock-Button. Setzt serverseitig Power/DNA/Rebirths/Zonen auf
-- Maximalwerte, damit waehrend der Entwicklung jede Area erreichbar ist.
--
-- TEMPORAER -- vor Release wieder loeschen:
--   * dieses File
--   * src/shared/Remotes/RequestDevUnlockAll.model.json
--   * Handler in src/server/Main.server.luau (Block "6d. DEV: Alles freischalten")
--   * Mount-Call in src/client/UIController.client.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestDevUnlockAll = Remotes:WaitForChild("RequestDevUnlockAll") :: RemoteEvent

local DevUnlockButton = {}

local DEV_ORANGE = Color3.fromRGB(255, 138, 56)
local DEV_RED = Color3.fromRGB(220, 70, 80)

function DevUnlockButton.create(parent: ScreenGui)
	local holder = Instance.new("Frame")
	holder.Name = "DevUnlockButton"
	holder.AnchorPoint = Vector2.new(1, 0.5)
	holder.Position = UDim2.new(1, -16, 0.62, 0)
	holder.Size = UDim2.new(0, 168, 0, 96)
	holder.BackgroundColor3 = Color3.fromRGB(20, 14, 14)
	holder.BackgroundTransparency = 0.12
	holder.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = holder

	local stroke = Instance.new("UIStroke")
	stroke.Color = DEV_ORANGE
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent = holder

	local devTag = Instance.new("TextLabel")
	devTag.Name = "DevTag"
	devTag.AnchorPoint = Vector2.new(0.5, 0)
	devTag.Position = UDim2.new(0.5, 0, 0, 6)
	devTag.Size = UDim2.new(1, -16, 0, 14)
	devTag.BackgroundTransparency = 1
	devTag.Text = "⚠ DEV ONLY"
	devTag.Font = Enum.Font.GothamBold
	devTag.TextColor3 = DEV_ORANGE
	devTag.TextSize = 11
	devTag.TextStrokeTransparency = 0.6
	devTag.Parent = holder

	local button = Instance.new("TextButton")
	button.Name = "UnlockBtn"
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -8)
	button.Size = UDim2.new(1, -16, 0, 60)
	button.Text = "🔓 UNLOCK ALL\nPower · DNA · Areas"
	button.Font = Enum.Font.GothamBold
	button.TextSize = 13
	button.TextColor3 = Color3.fromRGB(255, 245, 240)
	button.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	button.TextStrokeTransparency = 0.4
	button.TextWrapped = true
	button.BackgroundColor3 = DEV_RED
	button.AutoButtonColor = true
	button.Parent = holder

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 10)
	btnCorner.Parent = button

	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = Color3.fromRGB(0, 0, 0)
	btnStroke.Thickness = 1.5
	btnStroke.Transparency = 0.5
	btnStroke.Parent = button

	-- Klick-Cooldown, damit das Remote nicht durch versehentliches Doppelklicken
	-- mehrfach gefeuert wird (Server hat zusaetzlich Rate-Limit).
	local lastClick = 0
	local COOLDOWN = 1.5
	button.MouseButton1Click:Connect(function()
		local now = os.clock()
		if now - lastClick < COOLDOWN then
			return
		end
		lastClick = now
		button.Text = "✓ UNLOCKED"
		button.BackgroundColor3 = Color3.fromRGB(60, 180, 100)
		RequestDevUnlockAll:FireServer()
		task.delay(1.2, function()
			button.Text = "🔓 UNLOCK ALL\nPower · DNA · Areas"
			button.BackgroundColor3 = DEV_RED
		end)
	end)

	return {
		root = holder,
		button = button,
	}
end

return DevUnlockButton
