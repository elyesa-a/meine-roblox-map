--!strict
-- RebirthService: validiert Rebirth-Requests serverseitig.
--  * Rebirth geht von 0 bis 100, kein Skipping.
--  * Power muss >= RebirthConfig.getCost(Rebirths) sein.
--  * Bei Erfolg: Rebirths+=1, Power=0, Level=1, DnaCoins += getDnaReward(oldR).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local RebirthConfig = require(Configs:WaitForChild("RebirthConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestRebirth = Remotes:WaitForChild("RequestRebirth") :: RemoteEvent
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

local RebirthService = {}

local DataService
local StatService
local AntiExploitService
local UpgradeService
local BoostService
local GamepassService
local DailyQuestService
local TitleService

function RebirthService.handleRequest(player: Player)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end

	if profile.Rebirths >= RebirthConfig.MaxRebirth then
		ShowPopup:FireClient(player, "Max Rebirth reached")
		return
	end

	local cost = RebirthConfig.getCost(profile.Rebirths)
	if profile.Power < cost then
		ShowPopup:FireClient(player, "Not enough Power for Rebirth")
		return
	end

	local oldRebirth = profile.Rebirths
	local baseReward = RebirthConfig.getDnaReward(oldRebirth)
	local dnaMult = 1
	if UpgradeService then
		dnaMult *= UpgradeService.getMultiplier(player, "DnaBoost")
	end
	if BoostService then
		dnaMult *= BoostService.getMultiplier(player, "Dna")
	end
	if GamepassService then
		dnaMult *= GamepassService.getDnaMultiplier(player)
	end
	if TitleService then
		dnaMult *= TitleService.getBonusMultiplier(player, "Dna")
	end
	local reward = math.floor(baseReward * dnaMult)
	profile.Rebirths = oldRebirth + 1
	profile.Power = 0
	profile.Level = 1
	profile.DnaCoins = profile.DnaCoins + reward
	if DailyQuestService then
		DailyQuestService.record(player, "CollectDna", reward)
	end

	StatService.broadcastProfile(player)
	StatService.playSound(player, "Rebirth")
	StatService.spawnRebirthVfx(player)
	if DailyQuestService then
		DailyQuestService.record(player, "Rebirth", 1)
	end
	if TitleService then
		TitleService.evaluatePlayer(player)
	end
	ShowPopup:FireClient(player, string.format("Rebirth %d! +%d DNA", profile.Rebirths, reward))
end

function RebirthService.start(deps)
	DataService = deps.DataService
	StatService = deps.StatService
	AntiExploitService = deps.AntiExploitService
	UpgradeService = deps.UpgradeService
	BoostService = deps.BoostService
	GamepassService = deps.GamepassService
	DailyQuestService = deps.DailyQuestService
	TitleService = deps.TitleService

	AntiExploitService.safeBind(RequestRebirth, 2, RebirthService.handleRequest)
end

return RebirthService
