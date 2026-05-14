--!strict
-- SpinService: Glücksrad mit gewichteten Belohnungen. Free-Spin alle 30 Min.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local SpinConfig = require(Configs:WaitForChild("SpinConfig"))
local PetConfig = require(Configs:WaitForChild("PetConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestSpin = Remotes:WaitForChild("RequestSpin") :: RemoteEvent
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

local SpinService = {}

local DataService
local StatService
local PetService
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
		return
	end
	if reward.type == "Dna" then
		profile.DnaCoins += reward.amount
	elseif reward.type == "Power" then
		profile.Power = math.floor(profile.Power + reward.amount)
	elseif reward.type == "Pet" and PetService then
		-- "PetCommon" -> rolle nochmal random (Common+), "PetEpic" -> rare+
		local minRarityOrder = if reward.id == "PetEpic" then 3 else 1
		local rarityOrder = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5 }
		for _ = 1, 8 do
			local def = PetConfig.rollRandomPet(rng)
			if def and (rarityOrder[def.rarity] or 0) >= minRarityOrder then
				PetService.grantPet(player, def.id)
				return
			end
		end
		-- Fallback: einfach irgendein Pet.
		local fallback = PetConfig.rollRandomPet(rng)
		if fallback then
			PetService.grantPet(player, fallback.id)
		end
	end
end

function SpinService.spin(player: Player)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	if SpinService.getRemainingSec(player) > 0 then
		ShowPopup:FireClient(player, "Naechster Free-Spin noch nicht verfuegbar.")
		return
	end
	profile.Spin.LastFreeSpin = os.time()
	local reward = rollReward()
	grantReward(player, reward)
	ShowPopup:FireClient(player, string.format("Spin: %s", reward.displayName))
	StatService.broadcastProfile(player)
end

function SpinService.start(deps)
	DataService = deps.DataService
	StatService = deps.StatService
	PetService = deps.PetService
	AntiExploitService = deps.AntiExploitService

	AntiExploitService.safeBind(RequestSpin, 1, function(player)
		SpinService.spin(player)
	end)
end

return SpinService
