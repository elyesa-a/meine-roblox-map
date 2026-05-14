--!strict
-- Generisches Stub-Fenster fuer Pet/Aura/Upgrade in Phase 1.
-- Zeigt nur Header + "Kommt bald" + Close-Button.

local Theme = require(script.Parent:WaitForChild("Theme"))

local StubFrame = {}

type Refs = {
	backdrop: Frame,
	root: Frame,
}

function StubFrame.create(parent: ScreenGui, name: string, headerColor: Color3, title: string): Refs
	local backdrop = Instance.new("Frame")
	backdrop.Name = name .. "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.DimBackdrop
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Visible = false
	backdrop.ZIndex = 5
	backdrop.Parent = parent

	local root = Instance.new("Frame")
	root.Name = name
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.new(0, 480, 0, 340)
	Theme.applyPanelStyle(root, headerColor)
	root.ZIndex = 6
	root.Parent = backdrop

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -16, 0, 48)
	header.Position = UDim2.new(0, 8, 0, 8)
	Theme.applyLabelStyle(header)
	header.Text = title
	header.TextSize = 28
	header.TextScaled = false
	header.ZIndex = 7
	header.Parent = root

	local body = Instance.new("TextLabel")
	body.Size = UDim2.new(1, -16, 0, 80)
	body.Position = UDim2.fromScale(0, 0.45)
	body.AnchorPoint = Vector2.new(0, 0.5)
	body.Position = UDim2.new(0, 8, 0.5, 0)
	Theme.applyLabelStyle(body)
	body.Text = "KOMMT BALD\n(Phase 2-4)"
	body.TextSize = 24
	body.TextScaled = false
	body.ZIndex = 7
	body.Parent = root

	local closeButton = Instance.new("TextButton")
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -8, 0, 8)
	closeButton.Size = UDim2.new(0, 36, 0, 36)
	closeButton.Text = "X"
	Theme.applyButtonStyle(closeButton, Theme.Colors.Red)
	closeButton.TextSize = 22
	closeButton.TextScaled = false
	closeButton.ZIndex = 8
	closeButton.Parent = root
	closeButton.MouseButton1Click:Connect(function()
		backdrop.Visible = false
	end)

	return { backdrop = backdrop, root = root }
end

function StubFrame.show(refs: Refs)
	refs.backdrop.Visible = true
end

return StubFrame
