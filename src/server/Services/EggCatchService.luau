--!strict
-- EggCatchService: server-controlled touch mini-game for Egg Catch stations.
--
-- The normal Pets & Eggs hatch flow remains in PetService. Egg Catch uses the
-- same egg pools and pet inventory, but rewards are granted when the player
-- physically collects spawned lab eggs during a timed round.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local PetConfig = require(Configs:WaitForChild("PetConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local EggCatchUpdate = Remotes:WaitForChild("EggCatchUpdate") :: RemoteEvent
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

local EggCatchService = {}

local DataService
local PetService

type GameState = {
	player: Player,
	station: Model,
	eggId: string,
	eggName: string,
	areaIndex: number,
	tier: string,
	token: number,
	active: boolean,
	startedAt: number,
	endsAt: number,
	caught: number,
	spawned: { BasePart },
	connections: { RBXScriptConnection },
}

local ROUND_DURATION = 30
local SPAWN_INTERVAL = 1.15
local MAX_ACTIVE_EGGS = 8
local EGG_LIFETIME = 8
local CATCH_RADIUS_X = 22
local CATCH_RADIUS_Z = 18
local rng = Random.new()

local activeByPlayer: { [Player]: GameState } = {}
local tokenCounter = 0

local function getCharacterRoot(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function countInventory(player: Player): number
	local profile = DataService and DataService.getProfile(player) or nil
	if not profile or type(profile.Pets) ~= "table" then
		return 0
	end
	local count = 0
	for _ in pairs(profile.Pets) do
		count += 1
	end
	return count
end

local function canStartEggCatch(player: Player, eggId: string): (boolean, string?)
	local profile = DataService and DataService.getProfile(player) or nil
	local egg = PetConfig.getEggById(eggId)
	if not profile or not egg then
		return false, "Egg Catch unavailable"
	end
	if countInventory(player) >= PetConfig.MaxInventorySize then
		return false, "Inventory Full"
	end
	if (profile.Rebirths or 0) < egg.requiredRebirth then
		return false, "Egg locked"
	end
	if (profile.Power or 0) < egg.requiredPower then
		return false, "Not enough PWR"
	end
	return true, nil
end

local function findEggModel(instance: Instance): Model?
	local current: Instance? = instance
	while current do
		if current:IsA("Model") and current:GetAttribute("AreaIndex") ~= nil and current:GetAttribute("EggTier") ~= nil then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function eggContextForStation(clickDetector: ClickDetector): { [string]: any }?
	local model = findEggModel(clickDetector)
	if not model then
		return nil
	end
	local areaIndex = model:GetAttribute("AreaIndex")
	local tier = model:GetAttribute("EggTier")
	if type(areaIndex) ~= "number" or type(tier) ~= "string" then
		return nil
	end
	local eggId = PetConfig.getEggId(areaIndex, tier)
	local egg = PetConfig.getEggById(eggId)
	if not egg then
		return nil
	end
	return {
		station = model,
		areaIndex = areaIndex,
		eggTier = tier,
		eggId = eggId,
		eggName = egg.displayName,
	}
end

local function sendUpdate(state: GameState, phase: string, message: string?)
	local timeLeft = math.max(0, math.ceil(state.endsAt - os.clock()))
	EggCatchUpdate:FireClient(state.player, {
		phase = phase,
		eggName = state.eggName,
		tier = state.tier,
		areaIndex = state.areaIndex,
		timeLeft = timeLeft,
		caught = state.caught,
		inventoryCount = countInventory(state.player),
		inventoryMax = PetConfig.MaxInventorySize,
		message = message,
	})
end

local function cleanupEgg(part: BasePart?)
	if part and part.Parent then
		part:Destroy()
	end
end

local function finishGame(player: Player, reason: string?)
	local state = activeByPlayer[player]
	if not state then
		return
	end
	state.active = false
	activeByPlayer[player] = nil
	for _, conn in ipairs(state.connections) do
		conn:Disconnect()
	end
	for _, part in ipairs(state.spawned) do
		cleanupEgg(part)
	end
	sendUpdate(state, "End", reason)
end

local function getStationCenter(station: Model): Vector3
	local capsule = station:FindFirstChild("EggCapsule", true)
	if capsule and capsule:IsA("BasePart") then
		return capsule.Position
	end
	return station:GetPivot().Position
end

local function activeEggCount(state: GameState): number
	local count = 0
	for _, part in ipairs(state.spawned) do
		if part.Parent then
			count += 1
		end
	end
	return count
end

local function collectEgg(state: GameState, part: BasePart)
	if not state.active or not part.Parent or part:GetAttribute("Collected") == true then
		return
	end
	part:SetAttribute("Collected", true)

	local ok = PetService.grantEggReward(state.player, state.eggId, "Egg Caught")
	if ok then
		state.caught += 1
		ShowPopup:FireClient(state.player, "Egg Caught!")
		sendUpdate(state, "Running", nil)
	else
		ShowPopup:FireClient(state.player, "Inventory Full")
		finishGame(state.player, "Inventory Full")
	end
	cleanupEgg(part)
end

local function makeCatchEgg(state: GameState)
	if not state.active or activeEggCount(state) >= MAX_ACTIVE_EGGS then
		return
	end
	local stationCenter = getStationCenter(state.station)
	local x = stationCenter.X + rng:NextNumber(-CATCH_RADIUS_X, CATCH_RADIUS_X)
	local z = stationCenter.Z + rng:NextNumber(-CATCH_RADIUS_Z, CATCH_RADIUS_Z)
	local y = stationCenter.Y + rng:NextNumber(2, 6)

	local eggDef = PetConfig.getEggById(state.eggId)
	local color = if eggDef then eggDef.color else Color3.fromRGB(80, 255, 150)

	local egg = Instance.new("Part")
	egg.Name = "CatchEgg"
	egg.Shape = Enum.PartType.Ball
	egg.Size = Vector3.new(3.2, 4.2, 3.2)
	egg.Position = Vector3.new(x, y, z)
	egg.Color = color
	egg.Material = Enum.Material.SmoothPlastic
	egg.Anchored = true
	egg.CanCollide = false
	egg.CanTouch = true
	egg.CanQuery = false
	egg:SetAttribute("Collected", false)
	egg.Parent = state.station

	local light = Instance.new("PointLight")
	light.Brightness = 0.35
	light.Range = 7
	light.Color = color
	light.Parent = egg

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CatchEggPrompt"
	prompt.ActionText = "Catch Egg"
	prompt.ObjectText = state.tier .. " Egg"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = egg

	table.insert(state.spawned, egg)
	table.insert(state.connections, egg.Touched:Connect(function(hit)
		local character = state.player.Character
		if character and hit and hit:IsDescendantOf(character) then
			collectEgg(state, egg)
		end
	end))
	table.insert(state.connections, prompt.Triggered:Connect(function(player)
		if player == state.player then
			collectEgg(state, egg)
		end
	end))

	task.delay(EGG_LIFETIME, function()
		if state.active and egg.Parent and egg:GetAttribute("Collected") ~= true then
			cleanupEgg(egg)
		end
	end)
end

local function runGame(state: GameState)
	task.spawn(function()
		sendUpdate(state, "Start", "Egg Catch started")
		ShowPopup:FireClient(state.player, "Egg Catch started")
		local nextSpawn = 0
		while state.active and activeByPlayer[state.player] == state and os.clock() < state.endsAt do
			local hrp = getCharacterRoot(state.player)
			if not hrp then
				finishGame(state.player, "Egg Catch ended")
				return
			end
			if os.clock() >= nextSpawn then
				nextSpawn = os.clock() + SPAWN_INTERVAL
				makeCatchEgg(state)
				sendUpdate(state, "Running", nil)
			end
			task.wait(0.2)
		end
		if state.active then
			finishGame(state.player, "Egg Catch complete")
		end
	end)
end

local function startGame(player: Player, context: { [string]: any })
	local current = activeByPlayer[player]
	if current and current.active then
		ShowPopup:FireClient(player, "Egg Catch already active")
		return
	end
	local canStart, reason = canStartEggCatch(player, context.eggId)
	if not canStart then
		ShowPopup:FireClient(player, reason or "Egg Catch unavailable")
		return
	end

	tokenCounter += 1
	local state: GameState = {
		player = player,
		station = context.station,
		eggId = context.eggId,
		eggName = context.eggName,
		areaIndex = context.areaIndex,
		tier = context.eggTier,
		token = tokenCounter,
		active = true,
		startedAt = os.clock(),
		endsAt = os.clock() + ROUND_DURATION,
		caught = 0,
		spawned = {},
		connections = {},
	}
	activeByPlayer[player] = state

	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(state.connections, humanoid.Died:Connect(function()
			finishGame(player, "Egg Catch ended")
		end))
	end

	runGame(state)
end

function EggCatchService.start(deps)
	DataService = deps.DataService
	PetService = deps.PetService

	local folder = Workspace:FindFirstChild("EggStations")
	if not folder then
		return
	end

	for _, desc in ipairs(folder:GetDescendants()) do
		if desc:IsA("ClickDetector") and desc.Name == "OpenEgg" then
			local eggContext = eggContextForStation(desc)
			if eggContext then
				desc.MouseClick:Connect(function(player)
					startGame(player, eggContext)
				end)
			end
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		finishGame(player, nil)
	end)
end

return EggCatchService
