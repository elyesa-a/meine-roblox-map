--!strict
-- DailyChestService: 24h-Cooldown, Streak bis 7 Tage, DNA+Kraft als Belohnung.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local DailyChestConfig = require(Configs:WaitForChild("DailyChestConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestClaimDailyChest = Remotes:WaitForChild("RequestClaimDailyChest") :: RemoteEvent
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

local DailyChestService = {}

local DataService
local StatService
local PetService
local AntiExploitService
local DailyQuestService
local TitleService

function DailyChestService.canClaim(player: Player): (boolean, number)
	-- Liefert (canClaim, secondsUntilNext).
	local profile = DataService.getProfile(player)
	if not profile then
		return false, math.huge
	end
	local now = os.time()
	local last = profile.DailyChest.LastClaim or 0
	local elapsed = now - last
	if elapsed >= DailyChestConfig.CooldownSec then
		return true, 0
	end
	return false, DailyChestConfig.CooldownSec - elapsed
end

function DailyChestService.getNextStreak(player: Player): number
	local profile = DataService.getProfile(player)
	if not profile then
		return 1
	end
	local now = os.time()
	local last = profile.DailyChest.LastClaim or 0
	local elapsed = now - last
	if last == 0 or elapsed > DailyChestConfig.ResetAfterSec then
		return 1
	end
	return (profile.DailyChest.Streak or 0) + 1
end

function DailyChestService.claim(player: Player)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local can, _ = DailyChestService.canClaim(player)
	if not can then
		ShowPopup:FireClient(player, "Daily Chest is not ready yet.")
		return
	end

	local nextStreak = DailyChestService.getNextStreak(player)
	local reward = DailyChestConfig.getReward(nextStreak)

	-- Boost auf DNA (Upgrade + Boost) anwenden -- sauberster Weg waere ueber
	-- StatService, aber Daily Chest geht ueber Profile-Felder direkt.
	profile.DnaCoins += reward.dna
	if DailyQuestService then
		DailyQuestService.record(player, "CollectDna", reward.dna)
	end
	if reward.power > 0 then
		StatService.addPowerReward(player, reward.power)
	end

	profile.DailyChest.LastClaim = os.time()
	profile.DailyChest.Streak = nextStreak
	if TitleService then
		TitleService.evaluatePlayer(player)
	end

	-- Streak-7 Bonus: ein Random-Pet.
	if reward.bonusText and PetService then
		local pets = require(ReplicatedStorage.Configs.PetConfig)
		local rand = Random.new()
		local def = pets.rollRandomPet(rand)
		if def then
			PetService.grantPet(player, def.id)
		end
	end

	ShowPopup:FireClient(player, string.format(
		"Day %d! +%d DNA, +%d Power%s",
		nextStreak,
		reward.dna,
		reward.power,
		reward.bonusText and (", " .. reward.bonusText) or ""
	))
	StatService.broadcastProfile(player)
	StatService.playSound(player, "Reward")
end

function DailyChestService.start(deps)
	DataService = deps.DataService
	StatService = deps.StatService
	PetService = deps.PetService
	AntiExploitService = deps.AntiExploitService
	DailyQuestService = deps.DailyQuestService
	TitleService = deps.TitleService

	AntiExploitService.safeBind(RequestClaimDailyChest, 2, function(player)
		DailyChestService.claim(player)
	end)
end

return DailyChestService
