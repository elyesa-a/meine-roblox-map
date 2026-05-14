--!strict
-- UpgradeService: kauft Upgrade-Levels mit DNA-Coins. Multiplikatoren werden
-- von StatService/RebirthService/PetService/TrainingZoneService eingelesen.
--
-- Datenmodell:
--   profile.Upgrades = { [upgradeId] = level }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local UpgradeConfig = require(Configs:WaitForChild("UpgradeConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestBuyUpgrade = Remotes:WaitForChild("RequestBuyUpgrade") :: RemoteEvent
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

local UpgradeService = {}

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
	if currentLevel >= UpgradeConfig.MaxLevel then
		ShowPopup:FireClient(player, "Max Level erreicht!")
		return
	end
	local cost = UpgradeConfig.getCost(currentLevel)
	if profile.DnaCoins < cost then
		ShowPopup:FireClient(player, "Nicht genug DNA-Coins!")
		return
	end
	profile.DnaCoins -= cost
	profile.Upgrades[upgradeId] = currentLevel + 1
	StatService.broadcastProfile(player)
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
end

return UpgradeService
