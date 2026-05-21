--!strict
-- StatService: zentrale Stelle fuer Kraftberechnung und Level-Aufstieg.
--
-- WICHTIG: Kein anderer Codepfad darf profile.Power direkt setzen.
--          Rebirth setzt Power=0 (RebirthService) -- das ist ok.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local RebirthConfig = require(Configs:WaitForChild("RebirthConfig"))
local LevelConfig = require(Configs:WaitForChild("LevelConfig"))

local Modules = ReplicatedStorage:WaitForChild("Modules")
local VFX = require(Modules:WaitForChild("VFX"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UpdateClientData = Remotes:WaitForChild("UpdateClientData") :: RemoteEvent
local PlaySound = Remotes:WaitForChild("PlaySound") :: RemoteEvent

local DataService -- gesetzt in start()
local PetService -- optional, gesetzt in start()
local AuraService -- optional, gesetzt in start()
local UpgradeService -- optional, gesetzt in start()
local BoostService -- optional, gesetzt in start()
local TitleService -- optional, gesetzt in start()
local DailyQuestService -- optional, gesetzt in start()

local StatService = {}

-- Pro-Spieler Zustand fuer Zone-Multiplikator und gedrosselte Updates.
local zoneMultByPlayer: { [Player]: number } = {}
local lastUpdateAt: { [Player]: number } = {}
local lastClickVfxAt: { [Player]: number } = {}

function StatService.setZoneMultiplier(player: Player, mult: number)
	zoneMultByPlayer[player] = mult
end

function StatService.getZoneMultiplier(player: Player): number
	return zoneMultByPlayer[player] or 1
end

function StatService.computeMultiplier(player: Player): number
	local profile = DataService.getProfile(player)
	if not profile then
		return 1
	end
	local rebirthMult = RebirthConfig.getMultiplier(profile.Rebirths)
	local zoneMult = zoneMultByPlayer[player] or 1
	local petMult = if PetService then PetService.getMultiplier(player) else 1
	local auraMult = if AuraService then AuraService.getMultiplier(player) else 1
	local upgradeMult = if UpgradeService then UpgradeService.getMultiplier(player, "PowerBoost") else 1
	local boostMult = if BoostService then BoostService.getMultiplier(player, "Power") else 1
	local titleMult = if TitleService then TitleService.getBonusMultiplier(player, "Power") else 1
	return rebirthMult * petMult * auraMult * zoneMult * boostMult * upgradeMult * titleMult
end

-- Sendet das aktuelle Profil-Snapshot an den Client (max 1x/100ms gedrosselt).
local function sendUpdate(player: Player)
	local now = os.clock()
	local last = lastUpdateAt[player]
	if last and now - last < 0.1 then
		return
	end
	lastUpdateAt[player] = now

	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	profile.ZonesReached = profile.ZonesReached or {}
	local rebirthCost = nil
	if profile.Rebirths < RebirthConfig.MaxRebirth then
		rebirthCost = RebirthConfig.getCost(profile.Rebirths)
	end
	UpdateClientData:FireClient(player, {
		Power = profile.Power,
		HighestPower = profile.HighestPower or 0,
		Rebirths = profile.Rebirths,
		RebirthShards = profile.RebirthShards,
		DnaCoins = profile.DnaCoins,
		Level = profile.Level,
		LevelCost = LevelConfig.getCost(profile.Level),
		RebirthCost = rebirthCost,
		CurrentMultiplier = RebirthConfig.getMultiplier(profile.Rebirths),
		NextMultiplier = RebirthConfig.getMultiplier(profile.Rebirths + 1),
		MaxRebirth = RebirthConfig.MaxRebirth,
		Settings = profile.Settings,
		Pets = profile.Pets,
		EquippedPets = profile.EquippedPets,
		PetMultiplier = if PetService then PetService.getMultiplier(player) else 1,
		Auras = profile.Auras,
		EquippedAura = profile.EquippedAura,
		AuraMultiplier = if AuraService then AuraService.getMultiplier(player) else 1,
		Upgrades = profile.Upgrades,
		ActiveBoosts = profile.ActiveBoosts,
		DailyChest = profile.DailyChest,
		DailyQuests = profile.DailyQuests,
		Spin = profile.Spin,
		Titles = profile.Titles,
		EquippedTitle = profile.EquippedTitle,
		TitleStats = profile.TitleStats,
		BossDefeats = profile.BossDefeats,
		HighestBossDefeated = profile.HighestBossDefeated or 0,
		HasCompletedTutorial = profile.HasCompletedTutorial == true,
		ZonesReached = profile.ZonesReached,
		TitlePowerMultiplier = if TitleService then TitleService.getBonusMultiplier(player, "Power") else 1,
		TitleDnaMultiplier = if TitleService then TitleService.getBonusMultiplier(player, "Dna") else 1,
		TitleLuckMultiplier = if TitleService then TitleService.getBonusMultiplier(player, "Luck") else 1,
		ServerTime = os.time(),
		TotalMultiplier = StatService.computeMultiplier(player),
	})
end

function StatService.broadcastProfile(player: Player)
	-- Forced update, ignoriert Throttle, fuer Initial-Send.
	lastUpdateAt[player] = nil
	sendUpdate(player)
end

function StatService.playSound(player: Player, soundName: string)
	PlaySound:FireClient(player, soundName)
end

-- Wird bei Klick aufgerufen, gedrosselt auf 4/s damit Partikel-Bursts nicht
-- ueberbordern. VFX wird nicht ausgespielt, wenn der Spieler "VFX" aus hat.
function StatService.spawnClickVfx(player: Player)
	local profile = DataService.getProfile(player)
	if not profile or profile.Settings.VFX == false then
		return
	end
	local char = player.Character
	if not char then
		return
	end
	local now = os.clock()
	local last = lastClickVfxAt[player] or 0
	if now - last < 0.25 then
		return
	end
	lastClickVfxAt[player] = now
	VFX.spawnClickBurst(char, Color3.fromRGB(255, 220, 80))
end

function StatService.spawnRebirthVfx(player: Player)
	local profile = DataService.getProfile(player)
	if not profile or profile.Settings.VFX == false then
		return
	end
	local char = player.Character
	if not char then
		return
	end
	VFX.spawnRebirthBurst(char)
end

local function checkLevelUp(profile)
	-- Loop, falls genug Kraft fuer mehrere Level vorhanden ist.
	while profile.Power >= LevelConfig.getCost(profile.Level) do
		profile.Level += 1
	end
end

local function afterPowerChanged(player: Player, profile)
	local levelBefore = profile.Level
	if profile.Power > (profile.HighestPower or 0) then
		profile.HighestPower = profile.Power
	end
	checkLevelUp(profile)
	if DailyQuestService then
		DailyQuestService.recordSet(player, "ReachPower", profile.Power)
	end
	if TitleService then
		TitleService.evaluatePlayer(player)
	end
	if profile.Level > levelBefore then
		PlaySound:FireClient(player, "LevelUp")
	end
	sendUpdate(player)
end

function StatService.addPower(player: Player, baseAmount: number)
	if baseAmount <= 0 then
		return
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local total = baseAmount * StatService.computeMultiplier(player)
	profile.Power = math.floor(profile.Power + total)
	afterPowerChanged(player, profile)
end

function StatService.addPowerReward(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	profile.Power = math.floor(profile.Power + amount)
	afterPowerChanged(player, profile)
end

function StatService.start(deps: {
	DataService: any,
	PetService: any?,
	AuraService: any?,
	UpgradeService: any?,
	BoostService: any?,
	TitleService: any?,
	DailyQuestService: any?,
})
	DataService = deps.DataService
	PetService = deps.PetService
	AuraService = deps.AuraService
	UpgradeService = deps.UpgradeService
	BoostService = deps.BoostService
	TitleService = deps.TitleService
	DailyQuestService = deps.DailyQuestService

	-- Beim Beitritt: nach kurzer Wartezeit Initial-Profil schicken.
	-- (Profil-Load passiert asynchron im DataService.)
	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			-- Warten, bis das Profile da ist (max 5s).
			local start = os.clock()
			while not DataService.getProfile(player) and os.clock() - start < 5 do
				task.wait(0.1)
			end
			if DataService.getProfile(player) then
				StatService.broadcastProfile(player)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		zoneMultByPlayer[player] = nil
		lastUpdateAt[player] = nil
		lastClickVfxAt[player] = nil
	end)
end

return StatService
