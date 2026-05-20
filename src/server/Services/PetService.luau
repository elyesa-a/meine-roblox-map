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
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

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

type VisualState = {
	player: Player,
	model: Model,
	instanceId: string,
	petId: string,
	slot: number,
	pos: Vector3,
	phase: number,
}

local VISUAL_FOLDER_NAME = "EquippedPetVisuals"
local VISUAL_STEP = 1 / 30
local visualFolder: Folder? = nil
local visualsByPlayer: { [Player]: { VisualState } } = {}
local visualConnections: { [Player]: { RBXScriptConnection } } = {}
local visualAccumulator = 0

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
	while #profile.EquippedPets > PetConfig.MaxEquipped do
		table.remove(profile.EquippedPets)
	end
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

local function getVisualFolder(): Folder
	if visualFolder and visualFolder.Parent then
		return visualFolder
	end
	local existing = Workspace:FindFirstChild(VISUAL_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		visualFolder = existing
	else
		local folder = Instance.new("Folder")
		folder.Name = VISUAL_FOLDER_NAME
		folder.Parent = Workspace
		visualFolder = folder
	end
	return visualFolder :: Folder
end

local function rarityRank(rarity: string?): number
	return if rarity then (PetConfig.RarityOrder[rarity] or 1) else 1
end

local function rarityColor(rarity: string?): Color3
	if rarity and PetConfig.RarityColor[rarity] then
		return PetConfig.RarityColor[rarity]
	end
	return Color3.fromRGB(235, 238, 240)
end

local function makeVisualPart(parent: Instance, name: string, shape: Enum.PartType?, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		part.Shape = shape
	end
	part.Parent = parent
	return part
end

local function addPetLabel(core: BasePart, ownerName: string, petName: string, color: Color3)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PetOwnerLabel"
	billboard.Size = UDim2.fromOffset(150, 42)
	billboard.StudsOffset = Vector3.new(0, 2.3, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 55
	billboard.Parent = core

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = ownerName .. "\n" .. petName
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.15
	label.Parent = billboard
end

local function createPetModel(player: Player, instanceId: string, def, slot: number): Model
	local rarity = def.rarity or "Common"
	local rank = rarityRank(rarity)
	local color = rarityColor(rarity)
	local softColor = color:Lerp(Color3.fromRGB(245, 248, 248), 0.32)
	local darkColor = color:Lerp(Color3.fromRGB(12, 16, 22), 0.55)
	local model = Instance.new("Model")
	model.Name = string.format("%s_Pet_%d", player.Name, slot)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("OwnerName", player.Name)
	model:SetAttribute("PetInstanceId", instanceId)
	model:SetAttribute("PetId", def.id)
	model:SetAttribute("Slot", slot)

	local size = 1.8 + math.min(rank, 6) * 0.08
	local core = makeVisualPart(model, "PetCore", Enum.PartType.Ball, Vector3.new(size, size, size), CFrame.new(), color, Enum.Material.SmoothPlastic)
	model.PrimaryPart = core

	makeVisualPart(model, "LeftEye", Enum.PartType.Ball, Vector3.new(0.32, 0.32, 0.16), CFrame.new(-0.34, 0.24, -0.78), Color3.fromRGB(245, 250, 245), Enum.Material.SmoothPlastic)
	makeVisualPart(model, "RightEye", Enum.PartType.Ball, Vector3.new(0.32, 0.32, 0.16), CFrame.new(0.34, 0.24, -0.78), Color3.fromRGB(245, 250, 245), Enum.Material.SmoothPlastic)
	makeVisualPart(model, "LeftPupil", Enum.PartType.Ball, Vector3.new(0.13, 0.13, 0.08), CFrame.new(-0.34, 0.24, -0.88), Color3.fromRGB(10, 13, 18), Enum.Material.SmoothPlastic)
	makeVisualPart(model, "RightPupil", Enum.PartType.Ball, Vector3.new(0.13, 0.13, 0.08), CFrame.new(0.34, 0.24, -0.88), Color3.fromRGB(10, 13, 18), Enum.Material.SmoothPlastic)

	for i, offset in ipairs({
		Vector3.new(0, 0.95, 0),
		Vector3.new(0.9, 0.1, 0),
		Vector3.new(-0.9, 0.1, 0),
		Vector3.new(0, -0.05, 0.9),
	}) do
		local spike = makeVisualPart(model, "VirusNode" .. tostring(i), Enum.PartType.Ball, Vector3.new(0.34, 0.34, 0.34), CFrame.new(offset), softColor, Enum.Material.SmoothPlastic)
		spike.Transparency = 0.04
	end

	local ring = makeVisualPart(model, "PetGlowRing", Enum.PartType.Cylinder, Vector3.new(0.12, 2.25, 2.25), CFrame.Angles(0, 0, math.rad(90)), softColor, Enum.Material.Neon)
	ring.Transparency = if rank >= 4 then 0.45 else 0.65

	if rank >= 3 then
		local light = Instance.new("PointLight")
		light.Name = "RarityGlow"
		light.Color = color
		light.Brightness = if rank >= 5 then 0.85 else 0.45
		light.Range = if rank >= 5 then 12 else 8
		light.Parent = core
	end

	if rank >= 5 then
		local aura = Instance.new("ParticleEmitter")
		aura.Name = "RarePetAura"
		aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		aura.Color = ColorSequence.new(color, softColor)
		aura.LightEmission = 0.35
		aura.Rate = if rank >= 6 then 5 else 3
		aura.Lifetime = NumberRange.new(0.7, 1.2)
		aura.Speed = NumberRange.new(0.25, 0.8)
		aura.SpreadAngle = Vector2.new(60, 60)
		aura.Size = NumberSequence.new(0.24, 0.02)
		aura.Parent = core
	end

	addPetLabel(core, player.DisplayName, def.displayName, softColor:Lerp(darkColor, 0.15))
	model.Parent = getVisualFolder()
	return model
end

local function getCharacterRoot(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function desiredPetPosition(hrp: BasePart, slot: number, t: number): Vector3
	local side = if slot == 1 then 3 elseif slot == 2 then -3 else 0
	local behind = if slot == 3 then 6.3 else 5
	local height = if slot == 3 then 2.75 else 2.2
	local bob = math.sin(t * 2.2 + slot * 1.7) * 0.35
	return hrp.Position - hrp.CFrame.LookVector * behind + hrp.CFrame.RightVector * side + Vector3.new(0, height + bob, 0)
end

local function clearPetVisuals(player: Player)
	local states = visualsByPlayer[player]
	if states then
		for _, state in ipairs(states) do
			if state.model.Parent then
				state.model:Destroy()
			end
		end
	end
	visualsByPlayer[player] = nil
end

local function refreshPetVisuals(player: Player)
	clearPetVisuals(player)
	local profile = DataService and DataService.getProfile(player)
	local hrp = getCharacterRoot(player)
	if not profile or not hrp then
		return
	end
	ensurePetTables(profile)

	local states: { VisualState } = {}
	for slot, instanceId in ipairs(profile.EquippedPets) do
		if slot > PetConfig.MaxEquipped then
			break
		end
		local entry = profile.Pets[instanceId]
		local def = entry and PetConfig.getById(entry.id)
		if def then
			local model = createPetModel(player, instanceId, def, slot)
			local startPos = desiredPetPosition(hrp, slot, os.clock())
			model:PivotTo(CFrame.lookAt(startPos, startPos + hrp.CFrame.LookVector))
			table.insert(states, {
				player = player,
				model = model,
				instanceId = instanceId,
				petId = def.id,
				slot = slot,
				pos = startPos,
				phase = rng:NextNumber(0, math.pi * 2),
			})
		end
	end
	if #states > 0 then
		visualsByPlayer[player] = states
	end
end

local function updatePetVisuals(dt: number)
	local now = os.clock()
	for player, states in pairs(visualsByPlayer) do
		local hrp = getCharacterRoot(player)
		if not hrp then
			continue
		end
		local look = hrp.CFrame.LookVector
		for _, state in ipairs(states) do
			if state.model.Parent then
				local target = desiredPetPosition(hrp, state.slot, now + state.phase)
				state.pos = state.pos:Lerp(target, math.clamp(dt * 7, 0, 1))
				state.model:PivotTo(CFrame.lookAt(state.pos, state.pos + look))
			end
		end
	end
end

local function bindPetVisuals(player: Player)
	if visualConnections[player] then
		return
	end
	local connections = {}
	table.insert(connections, player.CharacterAdded:Connect(function()
		task.delay(0.35, function()
			if player.Parent then
				refreshPetVisuals(player)
			end
		end)
	end))
	table.insert(connections, player.CharacterRemoving:Connect(function()
		clearPetVisuals(player)
	end))
	visualConnections[player] = connections

	task.spawn(function()
		for _ = 1, 80 do
			if not player.Parent then
				return
			end
			if DataService and DataService.getProfile(player) and player.Character then
				refreshPetVisuals(player)
				return
			end
			task.wait(0.1)
		end
	end)
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
	refreshPetVisuals(player)
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
		refreshPetVisuals(player)
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
	refreshPetVisuals(player)
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
		refreshPetVisuals(player)
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

	getVisualFolder():ClearAllChildren()
	for _, player in ipairs(Players:GetPlayers()) do
		bindPetVisuals(player)
	end
	Players.PlayerAdded:Connect(bindPetVisuals)
	RunService.Heartbeat:Connect(function(dt)
		visualAccumulator += dt
		if visualAccumulator < VISUAL_STEP then
			return
		end
		local stepDt = visualAccumulator
		visualAccumulator = 0
		updatePetVisuals(stepDt)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastEggOpenAt[player] = nil
		clearPetVisuals(player)
		local connections = visualConnections[player]
		if connections then
			for _, conn in ipairs(connections) do
				conn:Disconnect()
			end
		end
		visualConnections[player] = nil
	end)
end

return PetService
