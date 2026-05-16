--!strict
-- Zentraler Client-Bootstrap: baut die gesamte UI auf, abonniert
-- Server-Updates und Popup-Nachrichten.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UpdateClientData = Remotes:WaitForChild("UpdateClientData") :: RemoteEvent

local UI = script.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local LeftButtons = require(UI:WaitForChild("LeftButtons"))
local BottomStats = require(UI:WaitForChild("BottomStats"))
local RightBoosts = require(UI:WaitForChild("RightBoosts"))
local TopBar = require(UI:WaitForChild("TopBar"))
local RebirthFrame = require(UI:WaitForChild("RebirthFrame"))
local SettingsFrame = require(UI:WaitForChild("SettingsFrame"))
local PetFrame = require(UI:WaitForChild("PetFrame"))
local AuraFrame = require(UI:WaitForChild("AuraFrame"))
local UpgradeFrame = require(UI:WaitForChild("UpgradeFrame"))
local SpinFrame = require(UI:WaitForChild("SpinFrame"))
local DailyChestFrame = require(UI:WaitForChild("DailyChestFrame"))
local GamepassFrame = require(UI:WaitForChild("GamepassFrame"))
local StubFrame = require(UI:WaitForChild("StubFrame"))
local PopupHandler = require(UI:WaitForChild("PopupHandler"))
local ClickHandler = require(UI:WaitForChild("ClickHandler"))
local SoundController = require(UI:WaitForChild("SoundController"))

SoundController.start()

-- ScreenGui anlegen.
local screen = Instance.new("ScreenGui")
screen.Name = "MainUI"
screen.IgnoreGuiInset = true
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

-- Layout-Elemente.
local bottomRefs = BottomStats.create(screen)

-- Fenster (zunaechst unsichtbar) -- vorab anlegen, damit Top/Left-Buttons sie
-- referenzieren koennen.
local rebirthRefs = RebirthFrame.create(screen)
local settingsRefs = SettingsFrame.create(screen)
local petRefs = PetFrame.create(screen)
local auraRefs = AuraFrame.create(screen)
local upgradeRefs = UpgradeFrame.create(screen)
local spinRefs = SpinFrame.create(screen)
local dailyRefs = DailyChestFrame.create(screen)
local gamepassRefs = GamepassFrame.create(screen)
local titleRefs = StubFrame.create(screen, "TitleFrame", Theme.Colors.Yellow, "TITEL")

-- TopBar mit Spin-Button-Klick.
local topRefs = TopBar.create(screen, function()
	SpinFrame.show(spinRefs)
end)

-- Rechte Boost-Leiste: kauft DNA-Boosts. (Gamepasses liegen nur im Shop.)
local rightRefs = RightBoosts.create(screen)

-- Linke Button-Leiste mit Klick-Handlern.
LeftButtons.create(screen, function(id)
	if id == "Rebirth" then
		RebirthFrame.show(rebirthRefs)
	elseif id == "Settings" then
		SettingsFrame.show(settingsRefs)
	elseif id == "Pets" then
		PetFrame.show(petRefs)
	elseif id == "Upgrades" then
		UpgradeFrame.show(upgradeRefs)
	elseif id == "Auras" then
		AuraFrame.show(auraRefs)
	elseif id == "Daily" then
		DailyChestFrame.show(dailyRefs)
	elseif id == "Shop" then
		GamepassFrame.show(gamepassRefs)
	elseif id == "Title" then
		StubFrame.show(titleRefs)
	end
end)

-- Klick-Button (zentral unten).
ClickHandler.bind(screen, bottomRefs.clickButton, Theme.Colors.Yellow)

-- Popup-Listener.
PopupHandler.start(screen)

-- State-Cache + Update-Funktion.
local state: { [string]: any } = {
	Power = 0,
	Rebirths = 0,
	DnaCoins = 0,
	Level = 1,
	LevelCost = 100,
	RebirthCost = 1000,
	CurrentMultiplier = 1,
	NextMultiplier = 1.5,
	MaxRebirth = 100,
	Settings = { Music = true, SFX = true, VFX = true, Haptik = true },
	Upgrades = {},
	ActiveBoosts = {},
	DailyChest = { LastClaim = 0, Streak = 0 },
	Spin = { LastFreeSpin = 0 },
	ServerTime = 0,
	_clientReceivedAt = os.clock(),
}

local function applyState()
	BottomStats.update(bottomRefs, state)
	TopBar.update(topRefs, state)
	RebirthFrame.update(rebirthRefs, state)
	SettingsFrame.update(settingsRefs, state)
	PetFrame.update(petRefs, state)
	AuraFrame.update(auraRefs, state)
	UpgradeFrame.update(upgradeRefs, state)
end

UpdateClientData.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	for k, v in pairs(payload) do
		state[k] = v
	end
	state._clientReceivedAt = os.clock()
	applyState()
	-- Settings koennen sich aendern (Toggle Music/SFX) -> Sound-Groups syncen.
	SoundController.applySettings(state.Settings)
end)

-- Initial-Render mit Default-State.
applyState()

-- Tick-Loop fuer Cooldown-/Timer-basierte UI (Spin, DailyChest, Boost-Timer).
-- Heartbeat ist sparsam, wir drosseln auf 4 Hz.
local accum = 0
RunService.Heartbeat:Connect(function(dt)
	accum += dt
	if accum < 0.25 then
		return
	end
	accum = 0
	SpinFrame.tick(spinRefs, state)
	DailyChestFrame.tick(dailyRefs, state)
	RightBoosts.tick(rightRefs, state)
end)

print("[UIController] UI bereit.")
