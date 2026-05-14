--!strict
-- Zentraler Client-Bootstrap: baut die gesamte UI auf, abonniert
-- Server-Updates und Popup-Nachrichten.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
local StubFrame = require(UI:WaitForChild("StubFrame"))
local PopupHandler = require(UI:WaitForChild("PopupHandler"))
local ClickHandler = require(UI:WaitForChild("ClickHandler"))

-- ScreenGui anlegen.
local screen = Instance.new("ScreenGui")
screen.Name = "MainUI"
screen.IgnoreGuiInset = true
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

-- Layout-Elemente.
local bottomRefs = BottomStats.create(screen)
local topRefs = TopBar.create(screen)
RightBoosts.create(screen)

-- Fenster (zunaechst unsichtbar).
local rebirthRefs = RebirthFrame.create(screen)
local settingsRefs = SettingsFrame.create(screen)
local petRefs = PetFrame.create(screen)
local auraRefs = AuraFrame.create(screen)
local upgradeRefs = StubFrame.create(screen, "UpgradeFrame", Theme.Colors.Green, "SCHUB")
local titleRefs = StubFrame.create(screen, "TitleFrame", Theme.Colors.Yellow, "TITEL")

-- Linke Button-Leiste mit Klick-Handlern.
LeftButtons.create(screen, function(id)
	if id == "Rebirth" then
		RebirthFrame.show(rebirthRefs)
	elseif id == "Settings" then
		SettingsFrame.show(settingsRefs)
	elseif id == "Pets" then
		PetFrame.show(petRefs)
	elseif id == "Upgrades" then
		StubFrame.show(upgradeRefs)
	elseif id == "Auras" then
		AuraFrame.show(auraRefs)
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
}

local function applyState()
	BottomStats.update(bottomRefs, state)
	TopBar.update(topRefs, state)
	RebirthFrame.update(rebirthRefs, state)
	SettingsFrame.update(settingsRefs, state)
	PetFrame.update(petRefs, state)
	AuraFrame.update(auraRefs, state)
end

UpdateClientData.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	for k, v in pairs(payload) do
		state[k] = v
	end
	applyState()
end)

-- Initial-Render mit Default-State.
applyState()

print("[UIController] UI bereit.")
