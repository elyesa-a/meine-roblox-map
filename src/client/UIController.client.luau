--!strict
-- Zentraler Client-Bootstrap: baut die gesamte UI auf, abonniert
-- Server-Updates und Popup-Nachrichten.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UpdateClientData = Remotes:WaitForChild("UpdateClientData") :: RemoteEvent

local UI = script.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local LeftButtons = require(UI:WaitForChild("LeftButtons"))
local BottomStats = require(UI:WaitForChild("BottomStats"))
local TopBar = require(UI:WaitForChild("TopBar"))
local ProgressionPanel = require(UI:WaitForChild("ProgressionPanel"))
local CurrentAreaLabel = require(UI:WaitForChild("CurrentAreaLabel"))
local AreaVisualController = require(UI:WaitForChild("AreaVisualController"))
local RebirthFrame = require(UI:WaitForChild("RebirthFrame"))
local SettingsFrame = require(UI:WaitForChild("SettingsFrame"))
local PetFrame = require(UI:WaitForChild("PetFrame"))
local AuraFrame = require(UI:WaitForChild("AuraFrame"))
local UpgradeFrame = require(UI:WaitForChild("UpgradeFrame"))
local SpinFrame = require(UI:WaitForChild("SpinFrame"))
local DailyChestFrame = require(UI:WaitForChild("DailyChestFrame"))
local DailyQuestFrame = require(UI:WaitForChild("DailyQuestFrame"))
local GamepassFrame = require(UI:WaitForChild("GamepassFrame"))
local TitleFrame = require(UI:WaitForChild("TitleFrame"))
local TeleportFrame = require(UI:WaitForChild("TeleportFrame"))
local TutorialFrame = require(UI:WaitForChild("TutorialFrame"))
local MenuController = require(UI:WaitForChild("MenuController"))
local PopupHandler = require(UI:WaitForChild("PopupHandler"))
local ClickHandler = require(UI:WaitForChild("ClickHandler"))
local SoundController = require(UI:WaitForChild("SoundController"))
local UIAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIAnimator"))

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
local dailyQuestRefs = DailyQuestFrame.create(screen)
local gamepassRefs = GamepassFrame.create(screen)
local titleRefs = TitleFrame.create(screen)
local teleportRefs = TeleportFrame.create(screen)
local tutorialRefs = TutorialFrame.create(screen)

local menuController = MenuController.new({
	Auras = { backdrop = auraRefs.backdrop, root = auraRefs.root, show = AuraFrame.show },
	Daily = { backdrop = dailyRefs.backdrop, root = dailyRefs.root, show = DailyChestFrame.show },
	DailyQuests = { backdrop = dailyQuestRefs.backdrop, root = dailyQuestRefs.root, show = DailyQuestFrame.show },
	Pets = { backdrop = petRefs.backdrop, root = petRefs.root, show = PetFrame.showInventory },
	Rebirth = { backdrop = rebirthRefs.backdrop, root = rebirthRefs.root, show = RebirthFrame.show },
	Settings = { backdrop = settingsRefs.backdrop, root = settingsRefs.root, show = SettingsFrame.show },
	Shop = { backdrop = gamepassRefs.backdrop, root = gamepassRefs.root, show = GamepassFrame.show },
	Titles = { backdrop = titleRefs.backdrop, root = titleRefs.root, show = TitleFrame.show },
	Teleport = { backdrop = teleportRefs.backdrop, root = teleportRefs.root, show = TeleportFrame.show },
	Skills = { backdrop = upgradeRefs.backdrop, root = upgradeRefs.root, show = UpgradeFrame.show },
	Spin = { backdrop = spinRefs.backdrop, root = spinRefs.root, show = SpinFrame.show },
})

local STATION_OPEN_RADIUS = 8
local STATION_CLOSE_RADIUS = 12
local STATION_REOPEN_COOLDOWN = 5
local SPAWN_CENTER_X = -180
local STATION_TRIGGER_Z = 77
local AUTO_STATION_ZONES = {
	{ menu = "Skills", modelName = "UpgradeLabStation", fallback = Vector3.new(SPAWN_CENTER_X - 64, 4, STATION_TRIGGER_Z) },
	{ menu = "Auras", modelName = "AuraStation", fallback = Vector3.new(SPAWN_CENTER_X - 24, 4, STATION_TRIGGER_Z) },
	{ menu = "Shop", modelName = "ShopTerminalStation", fallback = Vector3.new(SPAWN_CENTER_X + 16, 4, STATION_TRIGGER_Z) },
	{ menu = "Daily", modelName = "DailyRewardStation", fallback = Vector3.new(SPAWN_CENTER_X + 56, 4, STATION_TRIGGER_Z) },
}
local stationTriggers: { BasePart } = {}
local autoOpenedMenu: string? = nil
local suppressedStationMenus: { [string]: boolean } = {}
local stationReopenAt: { [string]: number } = {}

local function isStationMenuTarget(target: any): boolean
	return target == "Shop" or target == "Skills" or target == "Auras" or target == "Daily"
end

local function isStationTriggerPart(inst: Instance): boolean
	if not inst:IsA("BasePart") then
		return false
	end
	local target = inst:GetAttribute("MenuTarget")
	if not isStationMenuTarget(target) then
		return false
	end
	if inst.Name == "StationProximityTrigger" or inst.Name == "ShopProximityTrigger" then
		return true
	end
	if inst:FindFirstChildOfClass("ProximityPrompt") then
		return true
	end
	local parent = inst.Parent
	while parent do
		if parent.Name == "NPCStations" or parent.Name == "StationNPCs" then
			return true
		end
		parent = parent.Parent
	end
	return false
end

local function refreshStationTriggers(): { BasePart }
	local valid: { BasePart } = {}
	for _, trigger in ipairs(stationTriggers) do
		if trigger.Parent and isStationTriggerPart(trigger) then
			table.insert(valid, trigger)
		end
	end
	if #valid > 0 then
		stationTriggers = valid
		return stationTriggers
	end

	for _, inst in ipairs(Workspace:GetDescendants()) do
		if isStationTriggerPart(inst) then
			table.insert(valid, inst :: BasePart)
		end
	end
	stationTriggers = valid
	return stationTriggers
end

local function getRootPart(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getDistanceToPartBounds(part: BasePart, worldPosition: Vector3): number
	local localPosition = part.CFrame:PointToObjectSpace(worldPosition)
	local halfSize = part.Size * 0.5
	local outside = Vector3.new(
		math.max(math.abs(localPosition.X) - halfSize.X, 0),
		math.max(math.abs(localPosition.Y) - halfSize.Y, 0),
		math.max(math.abs(localPosition.Z) - halfSize.Z, 0)
	)
	return outside.Magnitude
end

local function getFlatDistance(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function findStationPosition(modelName: string): Vector3?
	local map = Workspace:FindFirstChild("Map")
	local spawnHub = map and map:FindFirstChild("SpawnHub")
	local stations = spawnHub and spawnHub:FindFirstChild("NPCStations")
	local model = stations and stations:FindFirstChild(modelName)
	if not model then
		return nil
	end
	local trigger = model:FindFirstChild("StationProximityTrigger", true)
	if trigger and trigger:IsA("BasePart") then
		return trigger.Position
	end
	local prompt = model:FindFirstChild("OpenMenuPrompt", true)
	if prompt and prompt:IsA("ProximityPrompt") and prompt.Parent and prompt.Parent:IsA("BasePart") then
		return prompt.Parent.Position
	end
	local body = model:FindFirstChild("KioskBody", true)
	if body and body:IsA("BasePart") then
		return body.Position
	end
	return nil
end

local function isAnyMenuOpenExcept(exceptMenuName: string): boolean
	for name, refs in pairs(menuController.menus) do
		if name ~= exceptMenuName and refs.backdrop.Visible then
			return true
		end
	end
	return false
end

local function openStationMenuManually(menuName: string)
	autoOpenedMenu = nil
	suppressedStationMenus[menuName] = false
	menuController:openMenu(menuName)
end

local function toggleSidebarMenu(menuName: string)
	autoOpenedMenu = nil
	menuController:toggleMenu(menuName)
end

local function closeAutoOpenedMenu()
	local menuName = autoOpenedMenu
	if not menuName then
		return
	end
	local refs = menuController.menus[menuName]
	autoOpenedMenu = nil
	if not refs or not refs.backdrop.Visible then
		return
	end
	UIAnimator.framePopOut(refs.backdrop, refs.root)
end

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	local target = prompt:GetAttribute("MenuTarget")
	if type(target) ~= "string" then
		return
	end
	if target == "Shop" or target == "Skills" or target == "Auras" or target == "Daily" then
		openStationMenuManually(target)
	else
		menuController:openMenu(target)
	end
end)

-- TopBar mit Spin-Button-Klick.
local topRefs = TopBar.create(screen, function()
	menuController:openMenu("Spin")
end)

-- Ziel-/Mission-HUD: zeigt naechste Zone und aktuelle Daily-Mission.
local progressionRefs = ProgressionPanel.create(screen)
local areaRefs = CurrentAreaLabel.create(screen)
CurrentAreaLabel.start(areaRefs)

-- Linke Button-Leiste mit Klick-Handlern.
LeftButtons.create(screen, function(id)
	if id == "Rebirth" then
		toggleSidebarMenu("Rebirth")
	elseif id == "Settings" then
		toggleSidebarMenu("Settings")
	elseif id == "Pets" then
		autoOpenedMenu = nil
		if petRefs.backdrop.Visible and not PetFrame.isEggOnlyMode(petRefs) then
			UIAnimator.framePopOut(petRefs.backdrop, petRefs.root)
		else
			menuController:closeAllMenus("Pets")
			PetFrame.showInventory(petRefs)
			TutorialFrame.record(tutorialRefs, "PetInventoryOpened")
		end
	elseif id == "Teleport" then
		toggleSidebarMenu("Teleport")
	elseif id == "Upgrades" then
		toggleSidebarMenu("Skills")
	elseif id == "Auras" then
		toggleSidebarMenu("Auras")
	elseif id == "Daily" then
		toggleSidebarMenu("Daily")
	elseif id == "Quests" then
		toggleSidebarMenu("DailyQuests")
	elseif id == "Shop" then
		if gamepassRefs.backdrop.Visible then
			toggleSidebarMenu("Shop")
		else
			openStationMenuManually("Shop")
		end
	elseif id == "Title" then
		toggleSidebarMenu("Titles")
	end
end)

-- Klick-Button + Screen-Tap fuer Power.
ClickHandler.bind(
	screen,
	bottomRefs.clickButton,
	Color3.fromRGB(70, 255, 120),
	bottomRefs.autoClickButton,
	bottomRefs.autoFightButton,
	bottomRefs.autoTrainingButton
)

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
	DailyQuests = { LastResetDay = 0, CompletedCount = 0, Streak = 0, QuestTokens = 0, Quests = {} },
	Spin = { LastFreeSpin = 0 },
	Titles = { Rookie = true },
	EquippedTitle = "Rookie",
	HighestBossDefeated = 0,
	HasCompletedTutorial = nil,
	ServerTime = 0,
	_clientReceivedAt = os.clock(),
}

local function applyState()
	BottomStats.update(bottomRefs, state)
	TopBar.update(topRefs, state)
	ProgressionPanel.update(progressionRefs, state)
	RebirthFrame.update(rebirthRefs, state)
	SettingsFrame.update(settingsRefs, state)
	PetFrame.update(petRefs, state)
	AuraFrame.update(auraRefs, state)
	UpgradeFrame.update(upgradeRefs, state)
	TitleFrame.update(titleRefs, state)
	TeleportFrame.update(teleportRefs, state)
	DailyQuestFrame.update(dailyQuestRefs, state)
	AreaVisualController.update(state)
	TutorialFrame.update(tutorialRefs, state)
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
local shopAccum = 0
RunService.Heartbeat:Connect(function(dt)
	accum += dt
	shopAccum += dt
	if shopAccum >= 0.15 then
		shopAccum = 0
		local rootPart = getRootPart()
		if rootPart then
			local nearestTarget: string? = nil
			local nearestDistance = math.huge
			local activeMenuDistance = math.huge
			local function considerStation(target: string, distance: number)
				if distance > STATION_CLOSE_RADIUS then
					suppressedStationMenus[target] = false
				end
				if autoOpenedMenu == target then
					activeMenuDistance = math.min(activeMenuDistance, distance)
				end
				if distance < nearestDistance then
					nearestDistance = distance
					nearestTarget = target
				end
			end

			for _, trigger in ipairs(refreshStationTriggers()) do
				local target = trigger:GetAttribute("MenuTarget")
				if type(target) == "string" and menuController.menus[target] then
					local distance = getDistanceToPartBounds(trigger, rootPart.Position)
					considerStation(target, distance)
				end
			end
			for _, zone in ipairs(AUTO_STATION_ZONES) do
				local pos = findStationPosition(zone.modelName) or zone.fallback
				local distance = getFlatDistance(pos, rootPart.Position)
				considerStation(zone.menu, distance)
			end

			if autoOpenedMenu then
				local refs = menuController.menus[autoOpenedMenu]
				if not refs or not refs.backdrop.Visible then
					if nearestTarget == autoOpenedMenu and nearestDistance <= STATION_CLOSE_RADIUS then
						suppressedStationMenus[autoOpenedMenu] = true
						stationReopenAt[autoOpenedMenu] = os.clock() + STATION_REOPEN_COOLDOWN
					end
					autoOpenedMenu = nil
				elseif activeMenuDistance > STATION_CLOSE_RADIUS then
					closeAutoOpenedMenu()
				end
			end

			if nearestTarget and nearestDistance <= STATION_OPEN_RADIUS then
				local refs = menuController.menus[nearestTarget]
				if refs
					and not refs.backdrop.Visible
					and not autoOpenedMenu
					and not suppressedStationMenus[nearestTarget]
					and os.clock() >= (stationReopenAt[nearestTarget] or 0)
					and not isAnyMenuOpenExcept(nearestTarget)
				then
					autoOpenedMenu = nearestTarget
					menuController:openMenu(nearestTarget)
				end
			end
		end
	end
	if accum < 0.25 then
		return
	end
	accum = 0
	SpinFrame.tick(spinRefs, state)
	DailyChestFrame.tick(dailyRefs, state)
	DailyQuestFrame.tick(dailyQuestRefs, state)
	TopBar.update(topRefs, state)
	ProgressionPanel.update(progressionRefs, state)
end)

print("[UIController] UI bereit.")
