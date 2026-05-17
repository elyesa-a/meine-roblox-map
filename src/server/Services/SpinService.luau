--!strict
-- SpinService: weighted Lucky Wheel rewards. Free spin every 30 minutes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local SpinConfig = require(Configs:WaitForChild("SpinConfig"))
local RebirthConfig = require(Configs:WaitForChild("RebirthConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestSpin = Remotes:WaitForChild("RequestSpin") :: RemoteEvent
local SpinResult = Remotes:WaitForChild("SpinResult") :: RemoteEvent
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

local SpinService = {}

local DataService
local StatService
local AntiExploitService

local rng = Random.new()

function SpinService.getRemainingSec(player: Player): number
	local profile = DataService.getProfile(player)
	if not profile then
		return math.huge
	end
	local now = os.time()
	local last = profile.Spin.LastFreeSpin or 0
	local elapsed = now - last
	if elapsed >= SpinConfig.CooldownSec then
		return 0
	end
	return SpinConfig.CooldownSec - elapsed
end

local function rollReward()
	local total = SpinConfig.totalWeight()
	local roll = rng:NextNumber(0, total)
	local acc = 0
	for _, reward in ipairs(SpinConfig.Rewards) do
		acc += reward.weight
		if roll <= acc then
			return reward
		end
	end
	return SpinConfig.Rewards[1]
end

local function grantReward(player: Player, reward)
	local profile = DataService.getProfile(player)
	if not profile then
		return reward.displayName
	end
	if reward.type == "Dna" then
		profile.DnaCoins += reward.amount
	elseif reward.type == "Power" then
		profile.Power = math.floor(profile.Power + reward.amount)
	elseif reward.type == "Luck" then
		local now = os.time()
		local boostSeconds = reward.boostSeconds or 300
		local existing = profile.ActiveBoosts.Luck2x
		if existing and existing > now then
			profile.ActiveBoosts.Luck2x = existing + boostSeconds
		else
			profile.ActiveBoosts.Luck2x = now + boostSeconds
		end
	elseif reward.type == "Rebirth" then
		local before = profile.Rebirths
		profile.Rebirths = math.min(RebirthConfig.MaxRebirth, before + reward.amount)
		local granted = profile.Rebirths - before
		if granted <= 0 then
			return "Max Rebirth reached"
		end
		return string.format("+%d %s", granted, if granted == 1 then "Rebirth" else "Rebirths")
	end

	return reward.displayName
end

function SpinService.spin(player: Player)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	if SpinService.getRemainingSec(player) > 0 then
		ShowPopup:FireClient(player, "Next Free Spin is not ready yet.")
		return
	end
	profile.Spin.LastFreeSpin = os.time()
	StatService.playSound(player, "Spin")
	local reward = rollReward()
	local grantedDisplay = grantReward(player, reward)
	SpinResult:FireClient(player, {
		id = reward.id,
		displayName = reward.displayName,
		grantedDisplayName = grantedDisplay,
		type = reward.type,
		amount = reward.amount,
		rarity = reward.rarity,
	})
	ShowPopup:FireClient(player, "You won " .. tostring(grantedDisplay) .. "!")
	StatService.broadcastProfile(player)
	StatService.playSound(player, "Reward")
end

function SpinService.start(deps)
	DataService = deps.DataService
	StatService = deps.StatService
	AntiExploitService = deps.AntiExploitService

	AntiExploitService.safeBind(RequestSpin, 1, function(player)
		SpinService.spin(player)
	end)
end

return SpinService
