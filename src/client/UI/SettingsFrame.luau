--!strict
-- Settings-Fenster: Toggle Buttons fuer Musik/SFX/VFX/Haptik.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestSettingsChange = Remotes:WaitForChild("RequestSettingsChange") :: RemoteEvent

local SettingsFrame = {}

type Refs = {
	backdrop: Frame,
	root: Frame,
	toggles: { [string]: TextButton },
}

local KEYS = { "Music", "SFX", "VFX", "Haptik" }
local LABELS: { [string]: string } = {
	Music = "MUSIK",
	SFX = "SFX",
	VFX = "VFX",
	Haptik = "HAPTIK",
}

local function setToggleVisual(btn: TextButton, on: boolean, key: string)
	btn.Text = string.format("%s: %s", LABELS[key] or key, on and "EIN" or "AUS")
	btn.BackgroundColor3 = if on then Theme.Colors.Green else Theme.Colors.Red
end

function SettingsFrame.create(parent: ScreenGui): Refs
	local backdrop = Instance.new("Frame")
	backdrop.Name = "SettingsBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.DimBackdrop
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Visible = false
	backdrop.ZIndex = 5
	backdrop.Parent = parent

	local root = Instance.new("Frame")
	root.Name = "SettingsFrame"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.new(0, 420, 0, 380)
	Theme.applyPanelStyle(root, Theme.Colors.PanelDark)
	root.ZIndex = 6
	root.Parent = backdrop

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -16, 0, 48)
	header.Position = UDim2.new(0, 8, 0, 8)
	Theme.applyLabelStyle(header)
	header.Text = "EINSTELLUNGEN"
	header.TextSize = 28
	header.TextScaled = false
	header.ZIndex = 7
	header.Parent = root

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

	local toggles: { [string]: TextButton } = {}
	local listHolder = Instance.new("Frame")
	listHolder.Size = UDim2.new(1, -32, 1, -80)
	listHolder.Position = UDim2.new(0, 16, 0, 72)
	listHolder.BackgroundTransparency = 1
	listHolder.ZIndex = 7
	listHolder.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 10)
	layout.Parent = listHolder

	for _, key in ipairs(KEYS) do
		local btn = Instance.new("TextButton")
		btn.Name = key .. "Toggle"
		btn.Size = UDim2.new(1, 0, 0, 54)
		Theme.applyButtonStyle(btn, Theme.Colors.Green)
		btn.TextSize = 20
		btn.TextScaled = false
		btn.ZIndex = 8
		btn.Parent = listHolder
		setToggleVisual(btn, true, key)
		toggles[key] = btn

		btn.MouseButton1Click:Connect(function()
			-- Wir kennen den aktuellen Wert nicht direkt; lesen aus dem
			-- letzten Server-Update via Tag-Attribut.
			local current = btn:GetAttribute("State")
			if current == nil then
				current = true
			end
			local newVal = not current
			-- UI optimistisch updaten, Server hat letztes Wort.
			setToggleVisual(btn, newVal, key)
			btn:SetAttribute("State", newVal)
			RequestSettingsChange:FireServer(key, newVal)
		end)
	end

	return { backdrop = backdrop, root = root, toggles = toggles }
end

function SettingsFrame.show(refs: Refs)
	refs.backdrop.Visible = true
end

function SettingsFrame.update(refs: Refs, state)
	local settings = state.Settings or {}
	for _, key in ipairs(KEYS) do
		local val = settings[key]
		if val == nil then val = true end
		local btn = refs.toggles[key]
		if btn then
			setToggleVisual(btn, val, key)
			btn:SetAttribute("State", val)
		end
	end
end

return SettingsFrame
