--!strict
-- Small HUD label that shows which lab area the player is currently inside.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent:WaitForChild("Theme"))

local CurrentAreaLabel = {}

type Refs = {
	root: Frame,
	label: TextLabel,
	currentArea: string,
}

local function isInside(part: BasePart, point: Vector3): boolean
	local localPoint = part.CFrame:PointToObjectSpace(point)
	return math.abs(localPoint.X) <= part.Size.X / 2
		and math.abs(localPoint.Y) <= part.Size.Y / 2
		and math.abs(localPoint.Z) <= part.Size.Z / 2
end

local function getRootPart(): BasePart?
	local player = Players.LocalPlayer
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function findCurrentArea(): string
	local hrp = getRootPart()
	if not hrp then
		return "Spawn Lab"
	end

	local map = Workspace:FindFirstChild("Map")
	local triggers = map and map:FindFirstChild("ZoneTriggers")
	if not triggers then
		return "Spawn Lab"
	end

	for _, obj in ipairs(triggers:GetChildren()) do
		if obj:IsA("BasePart") and isInside(obj, hrp.Position) then
			local displayName = obj:GetAttribute("DisplayName")
			if type(displayName) == "string" then
				return displayName
			end
		end
	end

	return "Central Lab"
end

function CurrentAreaLabel.create(parent: ScreenGui): Refs
	local root = Instance.new("Frame")
	root.Name = "CurrentAreaLabel"
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, 0, 78)
	root.Size = UDim2.new(0, 360, 0, 42)
	root.BackgroundColor3 = Color3.fromRGB(20, 32, 58)
	root.BackgroundTransparency = 0.02
	root.BorderSizePixel = 0
	root.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = root

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Cyan
	stroke.Thickness = 3
	stroke.Transparency = 0.08
	stroke.Parent = root

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.Colors.Cyan:Lerp(Color3.fromRGB(255, 255, 255), 0.15)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(30, 44, 72)),
		ColorSequenceKeypoint.new(1, Theme.Colors.Green:Lerp(Color3.fromRGB(0, 0, 0), 0.35)),
	})
	gradient.Rotation = 90
	gradient.Parent = root

	local icon = Instance.new("TextLabel")
	icon.Name = "AreaIcon"
	icon.Position = UDim2.new(0, 10, 0.5, -14)
	icon.Size = UDim2.new(0, 30, 0, 28)
	icon.BackgroundColor3 = Theme.Colors.Green
	icon.BorderSizePixel = 0
	icon.Font = Enum.Font.GothamBlack
	icon.Text = "LAB"
	icon.TextColor3 = Theme.Colors.White
	icon.TextStrokeColor3 = Theme.Colors.Black
	icon.TextStrokeTransparency = 0.1
	icon.TextSize = 10
	icon.Parent = root
	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(1, 0)
	iconCorner.Parent = icon

	local label = Instance.new("TextLabel")
	label.Name = "AreaText"
	label.Size = UDim2.new(1, -56, 1, 0)
	label.Position = UDim2.new(0, 48, 0, 0)
	label.BackgroundTransparency = 1
	label.Font = Theme.Font
	label.Text = "AREA: SPAWN LAB"
	label.TextColor3 = Theme.Colors.White
	label.TextSize = 16
	label.TextScaled = false
	label.TextStrokeColor3 = Theme.Colors.Black
	label.TextStrokeTransparency = 0.12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = root

	return { root = root, label = label, currentArea = "Spawn Lab" }
end

function CurrentAreaLabel.start(refs: Refs)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.25 then
			return
		end
		accumulator = 0

		local area = findCurrentArea()
		if area ~= refs.currentArea then
			refs.currentArea = area
			refs.label.Text = "AREA: " .. string.upper(area)
		end
	end)
end

return CurrentAreaLabel
