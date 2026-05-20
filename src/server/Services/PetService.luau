--!strict
-- PetService: server-authoritative area egg hatch, pet inventory, and equip.
--
-- Datenmodell im Profil:
--   profile.Pets = { [instanceId] = { id = petId, eggId = eggId?, hatchedAt = os.time()? } }
--   profile.EquippedPets = { instanceId1, instanceId2, ... }
--
-- Pet Power stacking is additive:
--   1 + sum(powerMultiplier - 1) for equipped pets.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local PetConfig = require(Configs:WaitForChild("PetConfig"))

local Modules = ReplicatedStorage:WaitForChild("Modules")
local NumberFormatter = require(Modules:WaitForChild("NumberFormatter"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestEquipPet = Remotes:WaitForChild("RequestEquipPet") :: RemoteEvent
local RequestUnequipPet = Remotes:WaitForChild("RequestUnequipPet") :: RemoteEvent
local RequestHatchPetEgg = Remotes:WaitForChild("RequestHatchPetEgg") :: RemoteEvent
local HatchPetResult = Remotes:WaitForChild("HatchPetResult") :: RemoteEvent
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

local PetService = {}

local DataService
local StatService
local AntiExploitService
local UpgradeService
local BoostService

local rng = Random.new()
local lastEggOpenAt: { [Player]: number } = {}

local function generateInstanceId(): string
	return HttpService:GenerateGUID(false)
end

local function countDict(t: { [any]: any }): number
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

local function ensurePetTables(profile)
	profile.Pets = profile.Pets or {}
	profile.EquippedPets = profile.EquippedPets or {}
end

local function getPetPowerMultiplier(def): number
	if not def then
		return 1
	end
	local value = def.powerMultiplier or def.multiplier or 1
	if type(value) ~= "number" then
		return 1
	end
	return math.max(1, value)
end

local function getLuckMultiplier(player: Player): number
	local mult = 1
	if UpgradeService then
		mult *= UpgradeService.getMultiplier(player, "LuckBoost")
	end
	if BoostService then
		mult *= BoostService.getMultiplier(player, "Luck")
	end
	return math.max(1, mult)
end

local function hasEggAccess(profile, egg): (boolean, string?)
	if profile.Rebirths < egg.requiredRebirth then
		return false, string.format("Requires Rebirth %d!", egg.requiredRebirth)
	end
	local progressPower = profile.Power or 0
	if progressPower < egg.requiredPower then
		return false, string.format(
			"Need %s PWR for %s!",
			NumberFormatter.format(egg.requiredPower),
			egg.areaDisplayName
		)
	end
	return true, nil
end

local function addPetToInventory(profile, petId: string, eggId: string?): string?
	local def = PetConfig.getById(petId)
	if not def then
		return nil
	end
	if countDict(profile.Pets) >= PetConfig.MaxInventorySize then
		return nil
	end
	local instanceId = generateInstanceId()
	profile.Pets[instanceId] = {
		id = petId,
		eggId = eggId,
		hatchedAt = os.time(),
	}
	return instanceId
end

function PetService.getMultiplier(player: Player): number
	local profile = DataService.getProfile(player)
	if not profile then
		return 1
	end
	ensurePetTables(profile)

	local bonus = 0
	for _, instanceId in ipairs(profile.EquippedPets) do
		local entry = profile.Pets[instanceId]
		if entry then
			local def = PetConfig.getById(entry.id)
			bonus += getPetPowerMultiplier(def) - 1
		end
	end
	return math.max(1, 1 + bonus)
end

-- Gibt ein Pet ins Inventar des Spielers. Wird auch von anderen Reward-
-- Services genutzt und bleibt deshalb als stabile Schnittstelle erhalten.
function PetService.grantPet(player: Player, petId: string): string?
	local profile = DataService.getProfile(player)
	if not profile then
		return nil
	end
	ensurePetTables(profile)
	local def = PetConfig.getById(petId)
	if not def then
		return nil
	end
	if countDict(profile.Pets) >= PetConfig.MaxInventorySize then
		ShowPopup:FireClient(player, "Pet inventory full!")
		return nil
	end
	local instanceId = addPetToInventory(profile, petId, nil)
	if instanceId then
		StatService.broadcastProfile(player)
	end
	return instanceId
end

function PetService.hatchEgg(player: Player, eggId: string)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	ensurePetTables(profile)

	local egg = PetConfig.getEggById(eggId)
	if not egg then
		ShowPopup:FireClient(player, "Unknown egg.")
		return
	end

	local now = os.clock()
	local lastOpen = lastEggOpenAt[player]
	if lastOpen and now - lastOpen < PetConfig.EggCooldownSec then
		ShowPopup:FireClient(player, "Please wait before hatching again.")
		return
	end

	local hasAccess, reason = hasEggAccess(profile, egg)
	if not hasAccess then
		ShowPopup:FireClient(player, reason or "Egg locked.")
		return
	end

	if countDict(profile.Pets) >= PetConfig.MaxInventorySize then
		ShowPopup:FireClient(player, "Pet inventory full!")
		return
	end

	if profile.DnaCoins < egg.cost then
		ShowPopup:FireClient(player, string.format(
			"Not enough DNA! Need %s DNA.",
			NumberFormatter.format(egg.cost)
		))
		return
	end

	local petDef = PetConfig.rollRandomPetForEgg(egg.id, rng, getLuckMultiplier(player))
	if not petDef then
		ShowPopup:FireClient(player, "Egg pool is empty.")
		return
	end

	profile.DnaCoins -= egg.cost
	lastEggOpenAt[player] = now

	local instanceId = addPetToInventory(profile, petDef.id, egg.id)
	if not instanceId then
		-- Should be unreachable because inventory was checked before deduction,
		-- but keep the transaction safe if profile data changes mid-call.
		profile.DnaCoins += egg.cost
		ShowPopup:FireClient(player, "Pet inventory full!")
		return
	end

	local multiplier = getPetPowerMultiplier(petDef)
	HatchPetResult:FireClient(player, {
		instanceId = instanceId,
		petId = petDef.id,
		displayName = petDef.displayName,
		rarity = petDef.rarity,
		powerMultiplier = multiplier,
		eggId = egg.id,
		eggName = egg.displayName,
	})
	ShowPopup:FireClient(player, string.format(
		"Hatched %s (%s) - %.2gx Power!",
		petDef.displayName,
		petDef.rarity,
		multiplier
	))
	StatService.broadcastProfile(player)
	StatService.playSound(player, "Reward")
end

-- Compatibility entry point for older world click hooks.
function PetService.openEgg(player: Player, eggId: string?)
	PetService.hatchEgg(player, eggId or PetConfig.DefaultEggId)
end

local function findEquippedIndex(profile, instanceId: string): number?
	for i, id in ipairs(profile.EquippedPets) do
		if id == instanceId then
			return i
		end
	end
	return nil
end

function PetService.equipPet(player: Player, instanceId: string)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	ensurePetTables(profile)
	if not profile.Pets[instanceId] then
		return
	end
	if findEquippedIndex(profile, instanceId) then
		return
	end
	if #profile.EquippedPets >= PetConfig.MaxEquipped then
		ShowPopup:FireClient(player, string.format("Max %d pets equipped!", PetConfig.MaxEquipped))
		return
	end
	table.insert(profile.EquippedPets, instanceId)
	StatService.broadcastProfile(player)
end

function PetService.unequipPet(player: Player, instanceId: string)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	ensurePetTables(profile)
	local idx = findEquippedIndex(profile, instanceId)
	if idx then
		table.remove(profile.EquippedPets, idx)
		StatService.broadcastProfile(player)
	end
end

function PetService.equipBest(player: Player)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	ensurePetTables(profile)

	local list = {}
	for instanceId, entry in pairs(profile.Pets) do
		local def = PetConfig.getById(entry.id)
		if def then
			table.insert(list, {
				instanceId = instanceId,
				multiplier = getPetPowerMultiplier(def),
			})
		end
	end
	table.sort(list, function(a, b)
		return a.multiplier > b.multiplier
	end)

	local newEquipped = {}
	for i = 1, math.min(PetConfig.MaxEquipped, #list) do
		table.insert(newEquipped, list[i].instanceId)
	end
	profile.EquippedPets = newEquipped
	StatService.broadcastProfile(player)
end

function PetService.unequipAll(player: Player)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	ensurePetTables(profile)
	if #profile.EquippedPets > 0 then
		profile.EquippedPets = {}
		StatService.broadcastProfile(player)
	end
end

local function handleEquipRequest(player: Player, payload: any)
	if payload == "BEST" then
		PetService.equipBest(player)
		return
	end
	if type(payload) ~= "string" then
		return
	end
	PetService.equipPet(player, payload)
end

local function handleUnequipRequest(player: Player, payload: any)
	if payload == "ALL" then
		PetService.unequipAll(player)
		return
	end
	if type(payload) ~= "string" then
		return
	end
	PetService.unequipPet(player, payload)
end

function PetService.start(deps)
	DataService = deps.DataService
	StatService = deps.StatService
	AntiExploitService = deps.AntiExploitService
	UpgradeService = deps.UpgradeService
	BoostService = deps.BoostService

	AntiExploitService.safeBind(RequestEquipPet, 8, handleEquipRequest)
	AntiExploitService.safeBind(RequestUnequipPet, 8, handleUnequipRequest)
	AntiExploitService.safeBind(RequestHatchPetEgg, 3, function(player, eggId)
		if type(eggId) ~= "string" then
			return
		end
		PetService.hatchEgg(player, eggId)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastEggOpenAt[player] = nil
	end)
end

return PetService
