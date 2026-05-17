--!strict
-- DailyQuestService: three daily goals, progress tracking, rewards, and streaks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local DailyQuestConfig = require(Configs:WaitForChild("DailyQuestConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestClaimDailyQuest = Remotes:WaitForChild("RequestClaimDailyQuest") :: RemoteEvent
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

local DailyQuestService = {}

local DataService
local StatService
local AntiExploitService
local TitleService

local function currentDay(): number
	return math.floor(os.time() / DailyQuestConfig.ResetSec)
end

local function pickQuestId(day: number, difficulty: string, offset: number): string
	local pool = DailyQuestConfig.getByDifficulty(difficulty)
	if #pool == 0 then
		return DailyQuestConfig.Quests[1].id
	end
	local index = ((day + offset) % #pool) + 1
	return pool[index].id
end

local function ensureDailyState(profile)
	profile.DailyQuests = profile.DailyQuests or {
		LastResetDay = 0,
		CompletedCount = 0,
		Streak = 0,
		QuestTokens = 0,
		Quests = {},
	}
	local day = currentDay()
	if profile.DailyQuests.LastResetDay ~= day or #profile.DailyQuests.Quests == 0 then
		profile.DailyQuests.LastResetDay = day
		profile.DailyQuests.Quests = {
			{ Id = pickQuestId(day, "Easy", 1), Progress = 0, Claimed = false },
			{ Id = pickQuestId(day, "Medium", 3), Progress = 0, Claimed = false },
			{ Id = pickQuestId(day, "Hard", 7), Progress = 0, Claimed = false },
		}
	end
	return profile.DailyQuests
end

local function questMatches(def, kind: string, target: string?): boolean
	if def.kind ~= kind then
		return false
	end
	if def.target and target and def.target ~= target then
		return false
	end
	if def.target and not target then
		return false
	end
	return true
end

local function setProgress(profile, entry, def, value: number)
	entry.Progress = math.clamp(value, 0, def.required)
end

function DailyQuestService.record(player: Player, kind: string, amount: number?, target: string?)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local daily = ensureDailyState(profile)
	for _, entry in ipairs(daily.Quests) do
		local def = DailyQuestConfig.getById(entry.Id)
		if def and not entry.Claimed and questMatches(def, kind, target) then
			entry.Progress = math.clamp((entry.Progress or 0) + (amount or 1), 0, def.required)
		end
	end
	StatService.broadcastProfile(player)
end

function DailyQuestService.recordSet(player: Player, kind: string, value: number, target: string?)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local daily = ensureDailyState(profile)
	for _, entry in ipairs(daily.Quests) do
		local def = DailyQuestConfig.getById(entry.Id)
		if def and not entry.Claimed and questMatches(def, kind, target) then
			setProgress(profile, entry, def, value)
		end
	end
	StatService.broadcastProfile(player)
end

function DailyQuestService.refreshPlayer(player: Player)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	ensureDailyState(profile)
	StatService.broadcastProfile(player)
end

local function grantQuestReward(player: Player, reward)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	if reward.Dna then
		profile.DnaCoins += reward.Dna
	end
	if reward.Power then
		StatService.addPowerReward(player, reward.Power)
	end
	if reward.Luck then
		local now = os.time()
		local existing = profile.ActiveBoosts.Luck2x
		local seconds = math.max(300, reward.Luck * 12)
		profile.ActiveBoosts.Luck2x = if existing and existing > now then existing + seconds else now + seconds
	end
	if reward.QuestTokens then
		profile.DailyQuests.QuestTokens = (profile.DailyQuests.QuestTokens or 0) + reward.QuestTokens
	end
end

function DailyQuestService.claim(player: Player, questId: string)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local daily = ensureDailyState(profile)
	for _, entry in ipairs(daily.Quests) do
		if entry.Id == questId then
			local def = DailyQuestConfig.getById(entry.Id)
			if not def then
				return
			end
			if entry.Claimed then
				ShowPopup:FireClient(player, "Quest already claimed!")
				return
			end
			if (entry.Progress or 0) < def.required then
				ShowPopup:FireClient(player, "Quest not finished yet!")
				return
			end
			entry.Claimed = true
			daily.CompletedCount = (daily.CompletedCount or 0) + 1
			daily.Streak = (daily.Streak or 0) + 1
			grantQuestReward(player, def.reward)
			if TitleService then
				TitleService.addStat(player, "DailyQuestClaims", 1)
			end
			ShowPopup:FireClient(player, "Daily Quest claimed!")
			StatService.playSound(player, "Reward")
			StatService.broadcastProfile(player)
			return
		end
	end
end

function DailyQuestService.start(deps)
	DataService = deps.DataService
	StatService = deps.StatService
	AntiExploitService = deps.AntiExploitService
	TitleService = deps.TitleService

	AntiExploitService.safeBind(RequestClaimDailyQuest, 4, function(player, questId)
		if type(questId) ~= "string" then
			return
		end
		DailyQuestService.claim(player, questId)
	end)

	Players.PlayerAdded:Connect(function(player)
		task.delay(1, function()
			DailyQuestService.refreshPlayer(player)
		end)
	end)

	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in ipairs(Players:GetPlayers()) do
				local profile = DataService.getProfile(player)
				if profile then
					ensureDailyState(profile)
					DailyQuestService.record(player, "PlayMinutes", 1)
				end
			end
		end
	end)
end

return DailyQuestService
