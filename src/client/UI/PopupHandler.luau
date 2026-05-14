--!strict
-- Zeigt vom Server gesendete Popup-Nachrichten als Toast (2.5s).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

local PopupHandler = {}

function PopupHandler.start(parent: ScreenGui)
	ShowPopup.OnClientEvent:Connect(function(message)
		if type(message) ~= "string" then
			return
		end
		local toast = Instance.new("TextLabel")
		toast.AnchorPoint = Vector2.new(0.5, 0)
		toast.Position = UDim2.new(0.5, 0, 0, 80)
		toast.Size = UDim2.new(0, 400, 0, 56)
		Theme.applyPanelStyle(toast :: any, Theme.Colors.PanelDark)
		Theme.applyLabelStyle(toast)
		toast.Text = message
		toast.TextSize = 20
		toast.TextScaled = false
		toast.ZIndex = 100
		toast.Parent = parent

		local tweenIn = TweenService:Create(
			toast,
			TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, 0, 110) }
		)
		tweenIn:Play()

		task.delay(2.2, function()
			local tweenOut = TweenService:Create(
				toast,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = UDim2.new(0.5, 0, 0, 70), TextTransparency = 1, BackgroundTransparency = 1 }
			)
			tweenOut:Play()
			tweenOut.Completed:Connect(function()
				toast:Destroy()
			end)
		end)
	end)
end

return PopupHandler
