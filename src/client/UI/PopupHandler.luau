--!strict
-- Zeigt vom Server gesendete Popup-Nachrichten als Toast (2.5s).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

local PopupHandler = {}

function PopupHandler.start(parent: ScreenGui)
	local container = Instance.new("Frame")
	container.Name = "NotificationFrame"
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.Position = UDim2.new(0.5, 0, 0, 110)
	container.Size = UDim2.new(0, 300, 0, 150)
	container.BackgroundTransparency = 1
	container.ZIndex = 100
	container.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0, 6)
	layout.Parent = container

	ShowPopup.OnClientEvent:Connect(function(message)
		if type(message) ~= "string" then
			return
		end

		local toast = Instance.new("Frame")
		toast.Name = "NotificationToast"
		toast.Size = UDim2.new(0, 0, 0, 48)
		toast.BackgroundColor3 = Color3.fromRGB(22, 34, 62)
		toast.BackgroundTransparency = 0.02
		toast.BorderSizePixel = 0
		toast.ClipsDescendants = true
		toast.ZIndex = 101
		toast.Parent = container

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 18)
		corner.Parent = toast

		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.Colors.Green
		stroke.Thickness = 3
		stroke.Transparency = 0.08
		stroke.Parent = toast

		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Theme.Colors.Green:Lerp(Color3.fromRGB(255, 255, 255), 0.13)),
			ColorSequenceKeypoint.new(0.35, Color3.fromRGB(28, 44, 76)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 18, 32)),
		})
		gradient.Rotation = 90
		gradient.Parent = toast

		local accent = Instance.new("Frame")
		accent.Name = "Accent"
		accent.Size = UDim2.new(0, 8, 1, 0)
		accent.BackgroundColor3 = Theme.Colors.Green
		accent.BorderSizePixel = 0
		accent.ZIndex = 102
		accent.Parent = toast

		local label = Instance.new("TextLabel")
		label.Name = "Message"
		label.Position = UDim2.new(0, 22, 0, 0)
		label.Size = UDim2.new(1, -30, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Theme.Font
		label.Text = message
		label.TextColor3 = Theme.Colors.White
		label.TextSize = 16
		label.TextScaled = false
		label.TextStrokeColor3 = Theme.Colors.Black
		label.TextStrokeTransparency = 0.12
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.ZIndex = 102
		label.Parent = toast

		local tweenIn = TweenService:Create(
			toast,
			TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.new(0, 340, 0, 48) }
		)
		tweenIn:Play()

		task.delay(2.2, function()
			local tweenOut = TweenService:Create(
				toast,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Size = UDim2.new(0, 0, 0, 48), BackgroundTransparency = 1 }
			)
			TweenService:Create(label, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
			TweenService:Create(stroke, TweenInfo.new(0.2), { Transparency = 1 }):Play()
			tweenOut:Play()
			tweenOut.Completed:Connect(function()
				toast:Destroy()
			end)
		end)
	end)
end

return PopupHandler
