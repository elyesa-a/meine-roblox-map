--!strict
-- EnemyService: server-authoritative Phase A combat.
-- Client/click detectors only request attacks; server validates distance,
-- Power requirement, cooldown, boss-start state, damage, DNA reward, and respawn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local EnemyConfig = require(Configs:WaitForChild("EnemyConfig"))

-- Gegnerwerte skalieren *4 (bis ~4e61). Anzeigen daher abgekuerzt
-- formatieren, sonst crasht string.format("%d", ...) bei Riesenzahlen.
local Modules = ReplicatedStorage:WaitForChild("Modules")
local NumberFormatter = require(Modules:WaitForChild("NumberFormatter"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestAttackEnemy = Remotes:WaitForChild("RequestAttackEnemy") :: RemoteEvent
local EnemyUpdate = Remotes:WaitForChild("EnemyUpdate") :: RemoteEvent
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

type EnemyState = {
	model: Model,
	root: BasePart,
	def: any,
	health: number,
	alive: boolean,
	rewardGiven: boolean,
	prompt: ProximityPrompt?,
	battleOwner: Player?,
	battleToken: number,
	battleHumanoidDiedConn: RBXScriptConnection?,
}

local EnemyService = {}

local DataService
local StatService
local AntiExploitService
local PetService
local AuraService
local BoostService
local DailyQuestService
local TitleService

local statesByModel: { [Model]: EnemyState } = {}
local statesByRoot: { [BasePart]: EnemyState } = {}
local statesById: { [string]: EnemyState } = {}
local battlesByPlayer: { [Player]: EnemyState } = {}
local lastAttackAt: { [Player]: number } = {}
local rng = Random.new()

local function getCharacterRoot(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getCharacterHumanoid(player: Player): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid") :: Humanoid?
end

local function isCloseEnough(player: Player, state: EnemyState, maxDistance: number): boolean
	local hrp = getCharacterRoot(player)
	if not hrp then
		return false
	end
	return (hrp.Position - state.root.Position).Magnitude <= maxDistance
end

local function updateEnemy(state: EnemyState)
	state.model:SetAttribute("CurrentHealth", state.health)
	state.model:SetAttribute("Alive", state.alive)
	local barFill = state.model:FindFirstChild("HealthBarFill", true) :: BasePart?
	if barFill then
		local maxWidth = barFill:GetAttribute("MaxWidth")
		local fullCenterX = barFill:GetAttribute("FullCenterX")
		if type(maxWidth) == "number" then
			-- Anker = aktuelle Mitte des HealthBarBack (Geschwister). Dadurch
			-- bleibt die Leiste korrekt, auch wenn der Gegner sich durch den
			-- EnemyMovementController bewegt (Model:PivotTo). Stationaer
			-- identisch zum alten Verhalten (Back-Mitte == FullCenterX).
			local barBack = state.model:FindFirstChild("HealthBarBack", true) :: BasePart?
			local centerX = if barBack then barBack.Position.X elseif type(fullCenterX) == "number" then fullCenterX else barFill.Position.X
			local ratio = math.clamp(state.health / state.def.MaxHealth, 0, 1)
			local newWidth = math.max(0.05, maxWidth * ratio)
			local currentSize = barFill.Size
			barFill.Size = Vector3.new(newWidth, currentSize.Y, currentSize.Z)
			barFill.Position = Vector3.new(centerX - (maxWidth - newWidth) / 2, barFill.Position.Y, barFill.Position.Z)
		end
	end
	EnemyUpdate:FireAllClients({
		EnemyId = state.def.Id,
		CurrentHealth = state.health,
		MaxHealth = state.def.MaxHealth,
		Alive = state.alive,
	})
end

local function setModelVisible(state: EnemyState, visible: boolean)
	for _, obj in ipairs(state.model:GetDescendants()) do
		if obj:IsA("BasePart") then
			if obj.Name ~= "BossPad" and obj.Name ~= "AreaPad" then
				obj.Transparency = visible and (obj:GetAttribute("OriginalTransparency") or obj.Transparency) or 1
			end
			obj.CanTouch = visible
			local clicker = obj:FindFirstChildOfClass("ClickDetector")
			if clicker then
				clicker.MaxActivationDistance = visible and EnemyConfig.AttackDistance or 0
			end
			local prompt = obj:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.Enabled = visible
			end
		elseif obj:IsA("BillboardGui") then
			obj.Enabled = visible
		elseif obj:IsA("ParticleEmitter") then
			obj.Enabled = visible
		end
	end
end

local function captureOriginalTransparency(model: Model)
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("BasePart") then
			obj:SetAttribute("OriginalTransparency", obj.Transparency)
		end
	end
end

local function setBattlePromptEnabled(state: EnemyState, enabled: boolean)
	if state.prompt then
		state.prompt.Enabled = enabled and state.alive
	end
end

local function spawnDamageNumber(state: EnemyState, amount: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DamageNumber"
	billboard.Size = UDim2.fromOffset(120, 42)
	billboard.StudsOffset = Vector3.new(0, 9, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 45
	billboard.Parent = state.root

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = "-" .. NumberFormatter.format(amount)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 245, 120)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.Parent = billboard

	task.delay(0.45, function()
		if billboard.Parent then
			billboard:Destroy()
		end
	end)
end

local function playAttackBurst(state: EnemyState)
	local originalColor = state.root.Color
	state.root.Color = Color3.fromRGB(255, 245, 120)
	task.delay(0.08, function()
		if state.root.Parent then
			state.root.Color = originalColor
		end
	end)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "EnemyHitBurst"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 255, 170)),
		ColorSequenceKeypoint.new(1, state.root.Color),
	})
	emitter.Lifetime = NumberRange.new(0.2, 0.45)
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(5, 10)
	emitter.SpreadAngle = Vector2.new(120, 120)
	emitter.Size = NumberSequence.new(0.45, 0.05)
	emitter.LightEmission = 0.35
	emitter.Parent = state.root
	emitter:Emit(12)
	task.delay(0.6, function()
		if emitter.Parent then
			emitter:Destroy()
		end
	end)
end

local function playDefeatEffect(state: EnemyState)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "EnemyDefeatBurst"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(state.root.Color)
	emitter.Lifetime = NumberRange.new(0.35, 0.8)
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(1.2, 0.1)
	emitter.LightEmission = 0.4
	emitter.Parent = state.root
	emitter:Emit(if state.def.IsBoss then 70 else 35)
	task.delay(1, function()
		if emitter.Parent then
			emitter:Destroy()
		end
	end)
end

local function getDamage(player: Player): number
	local profile = DataService.getProfile(player)
	if not profile then
		return 1
	end
	local petMult = if PetService then PetService.getMultiplier(player) else 1
	local auraMult = if AuraService then AuraService.getMultiplier(player) else 1
	local boostMult = if BoostService then BoostService.getMultiplier(player, "Power") else 1
	return math.max(1, profile.Power * 0.05 * petMult * auraMult * boostMult)
end

local function grantDna(player: Player, amount: number)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local dnaMult = if BoostService then BoostService.getMultiplier(player, "Dna") else 1
	local titleMult = if TitleService then TitleService.getBonusMultiplier(player, "Dna") else 1
	local reward = math.floor(amount * dnaMult * titleMult)
	profile.DnaCoins += reward
	if DailyQuestService then
		DailyQuestService.record(player, "CollectDna", reward)
	end
	StatService.broadcastProfile(player)
	ShowPopup:FireClient(player, "+" .. NumberFormatter.format(reward) .. " DNA")
end

local function grantBossBonus(player: Player, state: EnemyState)
	if not state.def.IsBoss then
		return
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local powerBonus = math.max(100, math.floor(state.def.RequiredPower * 0.025))
	StatService.addPowerReward(player, powerBonus)
	ShowPopup:FireClient(player, "+" .. NumberFormatter.format(powerBonus) .. " Power")
	if rng:NextNumber() <= 0.18 then
		local now = os.time()
		local existing = profile.ActiveBoosts.Luck2x
		profile.ActiveBoosts.Luck2x = if existing and existing > now then existing + 180 else now + 180
		ShowPopup:FireClient(player, "+3 min Luck Boost")
	end
	StatService.broadcastProfile(player)
end

local function getEnemyAttackDamage(state: EnemyState): number
	local areaIndex = if type(state.def.AreaIndex) == "number" then state.def.AreaIndex else 1
	local damage = EnemyConfig.EnemyAttackDamageBase + (areaIndex - 1) * EnemyConfig.EnemyAttackDamagePerArea
	if state.def.IsBoss then
		damage *= EnemyConfig.EnemyBossDamageMultiplier
	end
	return math.max(1, math.floor(damage))
end

local function endBattle(state: EnemyState, message: string?)
	local owner = state.battleOwner
	if owner and battlesByPlayer[owner] == state then
		battlesByPlayer[owner] = nil
	end
	state.battleOwner = nil
	state.battleToken += 1
	if state.battleHumanoidDiedConn then
		state.battleHumanoidDiedConn:Disconnect()
		state.battleHumanoidDiedConn = nil
	end
	setBattlePromptEnabled(state, state.alive)
	if message and owner and owner.Parent then
		ShowPopup:FireClient(owner, message)
	end
end

local function startEnemyAttackLoop(state: EnemyState, player: Player, token: number)
	task.spawn(function()
		while state.alive and state.battleOwner == player and state.battleToken == token do
			task.wait(EnemyConfig.EnemyAttackCooldownSec)
			if not state.alive or state.battleOwner ~= player or state.battleToken ~= token then
				break
			end

			local humanoid = getCharacterHumanoid(player)
			if not humanoid or humanoid.Health <= 0 then
				endBattle(state)
				break
			end
			if not isCloseEnough(player, state, EnemyConfig.BattleLeashDistance) then
				endBattle(state, "Battle ended: enemy too far away.")
				break
			end

			humanoid:TakeDamage(getEnemyAttackDamage(state))
		end
	end)
end

local function respawnEnemy(state: EnemyState)
	task.delay(state.def.RespawnTime, function()
		if not state.model.Parent then
			return
		end
		endBattle(state)
		state.health = state.def.MaxHealth
		state.alive = true
		state.rewardGiven = false
		setModelVisible(state, true)
		setBattlePromptEnabled(state, true)
		updateEnemy(state)
	end)
end

local function defeatEnemy(player: Player, state: EnemyState)
	if state.rewardGiven then
		return
	end
	state.rewardGiven = true
	state.alive = false
	state.health = 0
	endBattle(state)
	updateEnemy(state)
	grantDna(player, state.def.DNAReward)
	ShowPopup:FireClient(player, string.format("%s defeated! +%s DNA", state.def.DisplayName, NumberFormatter.format(state.def.DNAReward)))
	grantBossBonus(player, state)
	if DailyQuestService then
		DailyQuestService.record(player, if state.def.IsBoss then "DefeatBoss" else "DefeatEnemy", 1, state.def.AreaName)
	end
	if TitleService then
		if state.def.IsBoss then
			TitleService.recordBossDefeat(player, state.def.Id)
		else
			TitleService.evaluatePlayer(player)
		end
	end
	playDefeatEffect(state)
	setModelVisible(state, false)
	respawnEnemy(state)
end

function EnemyService.attack(player: Player, state: EnemyState?)
	if not state or not state.alive then
		return
	end
	local now = os.clock()
	if lastAttackAt[player] and now - lastAttackAt[player] < EnemyConfig.AttackCooldownSec then
		return
	end
	lastAttackAt[player] = now

	if not isCloseEnough(player, state, EnemyConfig.AttackDistance) then
		return
	end

	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	if profile.Power < state.def.RequiredPower then
		ShowPopup:FireClient(player, "You need more Power!")
		return
	end
	if state.battleOwner ~= player then
		if state.battleOwner then
			ShowPopup:FireClient(player, "This enemy is already in battle!")
		else
			ShowPopup:FireClient(player, "Press E to start the battle first!")
		end
		return
	end

	local damage = getDamage(player)
	state.health = math.max(0, state.health - damage)
	spawnDamageNumber(state, damage)
	playAttackBurst(state)
	updateEnemy(state)
	if state.health <= 0 then
		defeatEnemy(player, state)
	end
end

local function findStateFromInstance(instance: Instance?): EnemyState?
	if not instance then
		return nil
	end
	if instance:IsA("Model") then
		return statesByModel[instance]
	end
	if instance:IsA("BasePart") then
		if statesByRoot[instance] then
			return statesByRoot[instance]
		end
		local model = instance:FindFirstAncestorOfClass("Model")
		return model and statesByModel[model] or nil
	end
	local model = instance:FindFirstAncestorOfClass("Model")
	return model and statesByModel[model] or nil
end

local function ensureBattlePrompt(root: BasePart, def): ProximityPrompt
	local prompt = root:FindFirstChild("StartBattle") :: ProximityPrompt?
	if not prompt then
		prompt = root:FindFirstChild("StartBossFight") :: ProximityPrompt?
	end
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = root
	end

	prompt.Name = "StartBattle"
	prompt.ActionText = "Start Battle"
	prompt.ObjectText = def.DisplayName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.75
	prompt.MaxActivationDistance = EnemyConfig.BattlePromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = true
	return prompt
end

local function startBattle(player: Player, state: EnemyState)
	if not state.alive then
		return
	end
	if not isCloseEnough(player, state, EnemyConfig.BattlePromptDistance + 3) then
		return
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	if profile.Power < state.def.RequiredPower then
		ShowPopup:FireClient(player, "You need more Power!")
		return
	end
	local humanoid = getCharacterHumanoid(player)
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if state.battleOwner == player then
		ShowPopup:FireClient(player, "Battle already started!")
		return
	end
	if state.battleOwner then
		ShowPopup:FireClient(player, "This enemy is already in battle!")
		return
	end

	local previousBattle = battlesByPlayer[player]
	if previousBattle and previousBattle ~= state then
		endBattle(previousBattle, "Previous battle ended.")
	end

	state.battleOwner = player
	state.battleToken += 1
	battlesByPlayer[player] = state
	setBattlePromptEnabled(state, false)
	state.battleHumanoidDiedConn = humanoid.Died:Connect(function()
		if state.battleOwner == player then
			endBattle(state)
		end
	end)

	ShowPopup:FireClient(player, "Battle started!")
	startEnemyAttackLoop(state, player, state.battleToken)
end

local function registerEnemy(model: Model)
	local enemyId = model:GetAttribute("EnemyId")
	if type(enemyId) ~= "string" then
		return
	end
	local def = EnemyConfig.getById(enemyId)
	local root = model:FindFirstChild("EnemyCore") :: BasePart?
	if not def or not root then
		return
	end
	captureOriginalTransparency(model)
	local prompt = ensureBattlePrompt(root, def)
	local state: EnemyState = {
		model = model,
		root = root,
		def = def,
		health = def.MaxHealth,
		alive = true,
		rewardGiven = false,
		prompt = prompt,
		battleOwner = nil,
		battleToken = 0,
		battleHumanoidDiedConn = nil,
	}
	statesByModel[model] = state
	statesByRoot[root] = state
	statesById[def.Id] = state
	updateEnemy(state)

	local clicker = root:FindFirstChild("AttackClick") :: ClickDetector?
	if clicker then
		clicker.MouseClick:Connect(function(player)
			EnemyService.attack(player, state)
		end)
	end

	if prompt then
		prompt.Triggered:Connect(function(player)
			startBattle(player, state)
		end)
	end
end

local function registerFolder(folder: Instance?)
	if not folder then
		return
	end
	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("Model") and descendant:GetAttribute("EnemyId") ~= nil then
			registerEnemy(descendant)
		end
	end
end

function EnemyService.start(deps)
	DataService = deps.DataService
	StatService = deps.StatService
	AntiExploitService = deps.AntiExploitService
	PetService = deps.PetService
	AuraService = deps.AuraService
	BoostService = deps.BoostService
	DailyQuestService = deps.DailyQuestService
	TitleService = deps.TitleService

	registerFolder(Workspace:FindFirstChild("EnemyAreas"))
	registerFolder(Workspace:FindFirstChild("BossFields"))

	AntiExploitService.safeBind(RequestAttackEnemy, 5, function(player, target)
		if type(target) == "string" then
			EnemyService.attack(player, statesById[target])
			return
		end
		if typeof(target) == "Instance" then
			EnemyService.attack(player, findStateFromInstance(target))
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastAttackAt[player] = nil
		local activeBattle = battlesByPlayer[player]
		if activeBattle then
			endBattle(activeBattle)
		end
		for _, state in pairs(statesByModel) do
			if state.battleOwner == player then
				endBattle(state)
			end
		end
	end)
end

return EnemyService
