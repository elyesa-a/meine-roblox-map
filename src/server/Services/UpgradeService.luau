--!strict
-- UpgradeService: kauft Upgrade-Levels mit DNA-Coins. Multiplikatoren werden
-- von StatService/RebirthService/PetService/TrainingZoneService eingelesen.
--
-- Datenmodell:
--   profile.Upgrades = { [upgradeId] = level }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local UpgradeConfig = require(Configs:WaitForChild("UpgradeConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestBuyUpgrade = Remotes:WaitForChild("RequestBuyUpgrade") :: RemoteEvent
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

local UpgradeService = {}

local BASE_WALK_SPEED = 16
local SPEED_UPGRADE_ID = "SpeedBoost"
local BASE_HEALTH = 100
local HEALTH_PER_LEVEL = 100
local HEALTH_UPGRADE_ID = "Health"

local DataService
local StatService
local AntiExploitService

function UpgradeService.getLevel(player: Player, upgradeId: string): number
	local profile = DataService.getProfile(player)
	if not profile then
		return 0
	end
	return profile.Upgrades[upgradeId] or 0
end

function UpgradeService.getMultiplier(player: Player, upgradeId: string): number
	local def = UpgradeConfig.getById(upgradeId)
	if not def then
		return 1
	end
	local level = UpgradeService.getLevel(player, upgradeId)
	return UpgradeConfig.getMultiplier(level, def.perLevelDelta)
end

function UpgradeService.applySpeed(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local multiplier = UpgradeService.getMultiplier(player, SPEED_UPGRADE_ID)
	humanoid.WalkSpeed = BASE_WALK_SPEED * multiplier
end

function UpgradeService.getMaxHealth(player: Player): number
	local def = UpgradeConfig.getById(HEALTH_UPGRADE_ID)
	local maxLevel = UpgradeConfig.getMaxLevel(def)
	local level = math.clamp(UpgradeService.getLevel(player, HEALTH_UPGRADE_ID), 0, maxLevel)
	return BASE_HEALTH + (level * HEALTH_PER_LEVEL)
end

function UpgradeService.applyHealth(player: Player, fillToMax: boolean?)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local maxHealth = UpgradeService.getMaxHealth(player)
	humanoid.MaxHealth = maxHealth
	if fillToMax then
		humanoid.Health = maxHealth
	else
		humanoid.Health = math.min(humanoid.Health, maxHealth)
	end
end

function UpgradeService.buyUpgrade(player: Player, upgradeId: string)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local def = UpgradeConfig.getById(upgradeId)
	if not def then
		return
	end
	local currentLevel = profile.Upgrades[upgradeId] or 0
	local maxLevel = UpgradeConfig.getMaxLevel(def)
	if currentLevel >= maxLevel then
		if upgradeId == HEALTH_UPGRADE_ID then
			ShowPopup:FireClient(player, "Health Skill is already MAX!")
		else
			ShowPopup:FireClient(player, "Max Level reached!")
		end
		return
	end
	local cost = UpgradeConfig.getCost(currentLevel, def)
	if profile.DnaCoins < cost then
		ShowPopup:FireClient(player, "Not enough DNA!")
		return
	end
	profile.DnaCoins -= cost
	profile.Upgrades[upgradeId] = currentLevel + 1
	if upgradeId == SPEED_UPGRADE_ID then
		UpgradeService.applySpeed(player)
	elseif upgradeId == HEALTH_UPGRADE_ID then
		UpgradeService.applyHealth(player, true)
		ShowPopup:FireClient(player, "Health upgraded! +100 Max HP")
	end
	StatService.broadcastProfile(player)
	StatService.playSound(player, "Purchase")
end

local function bindCharacterStatsOnSpawn(player: Player)
	player.CharacterAdded:Connect(function()
		task.wait(0.15)
		UpgradeService.applySpeed(player)
		UpgradeService.applyHealth(player, true)
	end)
	task.spawn(function()
		for _ = 1, 80 do
			if DataService.getProfile(player) then
				UpgradeService.applySpeed(player)
				UpgradeService.applyHealth(player, true)
				return
			end
			task.wait(0.1)
		end
	end)
end

function UpgradeService.start(deps)
	DataService = deps.DataService
	StatService = deps.StatService
	AntiExploitService = deps.AntiExploitService

	AntiExploitService.safeBind(RequestBuyUpgrade, 8, function(player, upgradeId)
		if type(upgradeId) ~= "string" then
			return
		end
		UpgradeService.buyUpgrade(player, upgradeId)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		bindCharacterStatsOnSpawn(player)
	end
	Players.PlayerAdded:Connect(bindCharacterStatsOnSpawn)
end

return UpgradeService
