--!strict
-- Server-Bootstrap.
--
-- Reihenfolge:
--  1. Welt aufbauen (WorldBuilder).
--  2. DataService + AntiExploit (Foundation).
--  3. Multiplikator-Services (Upgrade, Boost, Pet, Aura) -- diese werden vom
--     StatService.computeMultiplier referenziert.
--  4. StatService mit allen Multiplikator-Refs.
--  5. Rebirth, ZoneLock, Training, DailyChest, Spin.
--  6. Remote-Handler fuer Click, Settings, Egg-Click.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Services = ServerScriptService:WaitForChild("Services")

local DataService = require(Services:WaitForChild("DataService"))
local AntiExploitService = require(Services:WaitForChild("AntiExploitService"))
local StatService = require(Services:WaitForChild("StatService"))
local RebirthService = require(Services:WaitForChild("RebirthService"))
local PetService = require(Services:WaitForChild("PetService"))
local AuraService = require(Services:WaitForChild("AuraService"))
local UpgradeService = require(Services:WaitForChild("UpgradeService"))
local BoostService = require(Services:WaitForChild("BoostService"))
local DailyChestService = require(Services:WaitForChild("DailyChestService"))
local SpinService = require(Services:WaitForChild("SpinService"))
local GamepassService = require(Services:WaitForChild("GamepassService"))
local EnemyService = require(Services:WaitForChild("EnemyService"))
local EnemyMovementController = require(Services:WaitForChild("EnemyMovementController"))
local TitleService = require(Services:WaitForChild("TitleService"))
local DailyQuestService = require(Services:WaitForChild("DailyQuestService"))
local CollectibleService = require(Services:WaitForChild("CollectibleService"))
local WorldBuilder = require(Services:WaitForChild("WorldBuilder"))
local ZoneLockService = require(Services:WaitForChild("ZoneLockService"))
local TrainingZoneService = require(Services:WaitForChild("TrainingZoneService"))
local BorderService = require(Services:WaitForChild("BorderService"))
local EggCatchService = require(Services:WaitForChild("EggCatchService"))
local TeleportService = require(Services:WaitForChild("TeleportService"))
local TutorialService = require(Services:WaitForChild("TutorialService"))
local LeaderboardService = require(Services:WaitForChild("LeaderboardService"))

local Configs = ReplicatedStorage:WaitForChild("Configs")
local PetConfig = require(Configs:WaitForChild("PetConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestClick = Remotes:WaitForChild("RequestClick") :: RemoteEvent
local RequestSettingsChange = Remotes:WaitForChild("RequestSettingsChange") :: RemoteEvent
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

-- 1. Welt.
WorldBuilder.build()

-- 2. Foundation.
DataService.start()
AntiExploitService.start()

-- 3. Multiplikator-Services. Reihenfolge unter sich beliebig, weil sie
--    untereinander keine Aufrufe in start() machen.
UpgradeService.start({
	DataService = DataService,
	StatService = StatService,
	AntiExploitService = AntiExploitService,
})
BoostService.start({
	DataService = DataService,
	StatService = StatService,
	AntiExploitService = AntiExploitService,
})
AuraService.start({
	DataService = DataService,
	StatService = StatService,
	AntiExploitService = AntiExploitService,
	DailyQuestService = DailyQuestService,
	TitleService = TitleService,
})
PetService.start({
	DataService = DataService,
	StatService = StatService,
	AntiExploitService = AntiExploitService,
	UpgradeService = UpgradeService,
	BoostService = BoostService,
	TutorialService = TutorialService,
})
TitleService.start({
	DataService = DataService,
	StatService = StatService,
	AntiExploitService = AntiExploitService,
})

-- 4. StatService (mit allen Multiplikator-Services verdrahtet).
StatService.start({
	DataService = DataService,
	PetService = PetService,
	AuraService = AuraService,
	UpgradeService = UpgradeService,
	BoostService = BoostService,
	TitleService = TitleService,
	DailyQuestService = DailyQuestService,
})

-- 5. Gameplay-Services.
RebirthService.start({
	DataService = DataService,
	StatService = StatService,
	AntiExploitService = AntiExploitService,
	UpgradeService = UpgradeService,
	BoostService = BoostService,
	GamepassService = GamepassService,
	DailyQuestService = DailyQuestService,
	TitleService = TitleService,
})
ZoneLockService.start({ DataService = DataService })
-- PWR-Borders + Labor-Luken (Virus-Labor). Reines Map-Gating, additiv.
BorderService.start({ DataService = DataService })
-- Egg-Catch-Stationen an das bestehende Pet-Egg-System koppeln.
EggCatchService.start({ DataService = DataService, PetService = PetService, TutorialService = TutorialService })
TeleportService.start({
	DataService = DataService,
	StatService = StatService,
	AntiExploitService = AntiExploitService,
})
TutorialService.start({
	DataService = DataService,
	StatService = StatService,
	AntiExploitService = AntiExploitService,
})
LeaderboardService.start({
	DataService = DataService,
})
TrainingZoneService.start({
	DataService = DataService,
	StatService = StatService,
	AntiExploitService = AntiExploitService,
	UpgradeService = UpgradeService,
	DailyQuestService = DailyQuestService,
	TitleService = TitleService,
	TutorialService = TutorialService,
})
DailyChestService.start({
	DataService = DataService,
	StatService = StatService,
	PetService = PetService,
	AntiExploitService = AntiExploitService,
	DailyQuestService = DailyQuestService,
	TitleService = TitleService,
})
SpinService.start({
	DataService = DataService,
	StatService = StatService,
	PetService = PetService,
	AntiExploitService = AntiExploitService,
	DailyQuestService = DailyQuestService,
	TitleService = TitleService,
})
GamepassService.start({
	DataService = DataService,
	StatService = StatService,
	SpinService = SpinService,
	AntiExploitService = AntiExploitService,
})
EnemyService.start({
	DataService = DataService,
	StatService = StatService,
	AntiExploitService = AntiExploitService,
	PetService = PetService,
	AuraService = AuraService,
	BoostService = BoostService,
	DailyQuestService = DailyQuestService,
	TitleService = TitleService,
	TeleportService = TeleportService,
	TutorialService = TutorialService,
})
-- Gegner-Bewegung (additiv, beruehrt EnemyService/Respawn nicht).
EnemyMovementController.start()
DailyQuestService.start({
	DataService = DataService,
	StatService = StatService,
	AntiExploitService = AntiExploitService,
	TitleService = TitleService,
})
CollectibleService.start({
	DataService = DataService,
	StatService = StatService,
	DailyQuestService = DailyQuestService,
	TitleService = TitleService,
})

-- 6a. Spawn Pet-Egg interaction:
--     opens the Stage 1 egg shop. Hatching stays behind the Hatch button and
--     PetService validates station proximity again on every hatch request.

local function handlePetEggInteraction(player: Player)
	if not WorldBuilder.PetEgg then
		return
	end
	PetService.openEggStation(player, PetConfig.DefaultEggId, WorldBuilder.PetEgg)
	ShowPopup:FireClient(player, "Egg shop opened.")
end

if WorldBuilder.PetEgg then
	local clicker = WorldBuilder.PetEgg:FindFirstChild("OpenEgg") :: ClickDetector?
	if clicker then
		clicker.MouseClick:Connect(function(player)
			handlePetEggInteraction(player)
		end)
	end
	local prompt = WorldBuilder.PetEgg:FindFirstChild("OpenEggPrompt") :: ProximityPrompt?
	if prompt then
		prompt.Triggered:Connect(handlePetEggInteraction)
	end
end

-- 6b. Click-Remote (+1 Kraft pro Klick, serverseitiger 0.15s Cooldown).
local CLICK_COOLDOWN = 0.15
local lastPowerClickAt: { [Player]: number } = {}
AntiExploitService.safeBind(RequestClick, 7, function(player)
	local now = os.clock()
	local last = lastPowerClickAt[player] or 0
	if now - last < CLICK_COOLDOWN then
		return
	end
	lastPowerClickAt[player] = now
	StatService.addPower(player, 1)
	StatService.spawnClickVfx(player)
end)

Players.PlayerRemoving:Connect(function(player)
	lastPowerClickAt[player] = nil
end)

-- 6c. Settings-Remote.
local ALLOWED_SETTING_KEYS = { Music = true, SFX = true, VFX = true, Haptik = true }
AntiExploitService.safeBind(RequestSettingsChange, 5, function(player, key, value)
	if type(key) ~= "string" or type(value) ~= "boolean" then
		return
	end
	if not ALLOWED_SETTING_KEYS[key] then
		return
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	profile.Settings[key] = value
	StatService.broadcastProfile(player)
end)

print("[Main] Virus Evolution Simulator -- Phase 5 bereit.")
