--!strict
-- PetService: zentrale Pet-Logik.
--
-- Datenmodell im Profil:
--   profile.Pets       = { [instanceId: string] = { id: string } }
--   profile.EquippedPets = { instanceId1, instanceId2, ... }  -- max 3
--
-- Multiplier:
--   product(equippedPets.multiplier), 1 wenn keine ausgeruestet.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local PetConfig = require(Configs:WaitForChild("PetConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestEquipPet = Remotes:WaitForChild("RequestEquipPet") :: RemoteEvent
local RequestUnequipPet = Remotes:WaitForChild("RequestUnequipPet") :: RemoteEvent
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
	-- GenerateGUID gibt z.B. "{xxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}" zurueck.
	-- Wir entfernen die Klammern fuer kuerzere Keys.
	local g = HttpService:GenerateGUID(false)
	return g
end

local function countDict(t: { [any]: any }): number
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

function PetService.getMultiplier(player: Player): number
	local profile = DataService.getProfile(player)
	if not profile then
		return 1
	end
	local mult = 1
	for _, instanceId in ipairs(profile.EquippedPets) do
		local entry = profile.Pets[instanceId]
		if entry then
			local def = PetConfig.getById(entry.id)
			if def then
				mult *= def.multiplier
			end
		end
	end
	return mult
end

-- Gibt ein Pet ins Inventar des Spielers. Liefert die instanceId zurueck oder
-- nil, wenn das Inventar voll ist.
function PetService.grantPet(player: Player, petId: string): string?
	local profile = DataService.getProfile(player)
	if not profile then
		return nil
	end
	local def = PetConfig.getById(petId)
	if not def then
		return nil
	end
	if countDict(profile.Pets) >= PetConfig.MaxInventorySize then
		ShowPopup:FireClient(player, "Pet-Inventar voll!")
		return nil
	end
	local instanceId = generateInstanceId()
	profile.Pets[instanceId] = { id = petId }
	StatService.broadcastProfile(player)
	return instanceId
end

function PetService.openEgg(player: Player)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local now = os.clock()
	local lastOpen = lastEggOpenAt[player]
	if lastOpen and now - lastOpen < PetConfig.EggCooldownSec then
		ShowPopup:FireClient(player, "Bitte kurz warten!")
		return
	end
	if countDict(profile.Pets) >= PetConfig.MaxInventorySize then
		ShowPopup:FireClient(player, "Pet-Inventar voll!")
		return
	end
	if profile.DnaCoins < PetConfig.EggCost then
		ShowPopup:FireClient(player, "Nicht genug DNA-Coins!")
		return
	end
	profile.DnaCoins -= PetConfig.EggCost
	lastEggOpenAt[player] = now
	-- Luck-Multiplikator: bessere Chancen auf hohe Raritaeten. Wir rollen
	-- mehrfach und behalten den seltensten Treffer.
	local luckMult = 1
	if UpgradeService then
		luckMult *= UpgradeService.getMultiplier(player, "LuckBoost")
	end
	if BoostService then
		luckMult *= BoostService.getMultiplier(player, "Luck")
	end
	local extraRolls = math.max(0, math.floor(luckMult - 1))

	local rarityOrder = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5 }
	local best = PetConfig.rollRandomPet(rng)
	for _ = 1, extraRolls do
		local candidate = PetConfig.rollRandomPet(rng)
		if candidate and best
			and (rarityOrder[candidate.rarity] or 0) > (rarityOrder[best.rarity] or 0) then
			best = candidate
		end
	end
	if not best then
		return
	end
	local instanceId = PetService.grantPet(player, best.id)
	if instanceId then
		ShowPopup:FireClient(player, string.format("Du hast %s (%s) bekommen!", best.displayName, best.rarity))
	end
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
	if not profile or not profile.Pets[instanceId] then
		return
	end
	if findEquippedIndex(profile, instanceId) then
		return -- schon ausgeruestet
	end
	if #profile.EquippedPets >= PetConfig.MaxEquipped then
		ShowPopup:FireClient(player, string.format("Max %d Pets gleichzeitig!", PetConfig.MaxEquipped))
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
	-- Alle Pets nach Multiplier absteigend sortieren.
	local list = {}
	for instanceId, entry in pairs(profile.Pets) do
		local def = PetConfig.getById(entry.id)
		if def then
			table.insert(list, { instanceId = instanceId, multiplier = def.multiplier })
		end
	end
	table.sort(list, function(a, b)
		return a.multiplier > b.multiplier
	end)
	-- Top N ausruesten.
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
	if #profile.EquippedPets > 0 then
		profile.EquippedPets = {}
		StatService.broadcastProfile(player)
	end
end

-- Remote-Handler. Aktionsstrings "BEST" und "ALL" werden als Spezialwerte
-- akzeptiert, sonst muss eine instanceId folgen.
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

	Players.PlayerRemoving:Connect(function(player)
		lastEggOpenAt[player] = nil
	end)
end

return PetService
