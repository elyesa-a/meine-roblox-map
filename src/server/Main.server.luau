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
local TitleService = require(Services:WaitForChild("TitleService"))
local DailyQuestService = require(Services:WaitForChild("DailyQuestService"))
local WorldBuilder = require(Services:WaitForChild("WorldBuilder"))
local ZoneLockService = require(Services:WaitForChild("ZoneLockService"))
local TrainingZoneService = require(Services:WaitForChild("TrainingZoneService"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestClick = Remotes:WaitForChild("RequestClick") :: RemoteEvent
local RequestSettingsChange = Remotes:WaitForChild("RequestSettingsChange") :: RemoteEvent

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
TrainingZoneService.start({
	DataService = DataService,
	StatService = StatService,
	AntiExploitService = AntiExploitService,
	UpgradeService = UpgradeService,
	DailyQuestService = DailyQuestService,
	TitleService = TitleService,
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
})
DailyQuestService.start({
	DataService = DataService,
	StatService = StatService,
	AntiExploitService = AntiExploitService,
	TitleService = TitleService,
})

-- 6a. Pet-Egg ClickDetector.
if WorldBuilder.PetEgg then
	local clicker = WorldBuilder.PetEgg:FindFirstChild("OpenEgg") :: ClickDetector?
	if clicker then
		clicker.MouseClick:Connect(function(player)
			PetService.openEgg(player)
		end)
	end
end

-- 6b. Click-Remote (+1 Kraft pro Klick, 10/s Cap).
AntiExploitService.safeBind(RequestClick, 10, function(player)
	StatService.addPower(player, 1)
	StatService.spawnClickVfx(player)
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
