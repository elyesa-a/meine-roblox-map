--!strict
-- EnemyService: server-authoritative Phase A combat.
-- Client/click detectors only request attacks; server validates distance,
-- Power requirement, cooldown, boss-start state, damage, DNA reward, and respawn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local AreaConfig = require(Configs:WaitForChild("AreaConfig"))
local EnemyConfig = require(Configs:WaitForChild("EnemyConfig"))

-- Gegnerwerte skalieren *4 (bis ~4e61). Anzeigen daher abgekuerzt
-- formatieren, sonst crasht string.format("%d", ...) bei Riesenzahlen.
local Modules = ReplicatedStorage:WaitForChild("Modules")
local NumberFormatter = require(Modules:WaitForChild("NumberFormatter"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestAttackEnemy = Remotes:WaitForChild("RequestAttackEnemy") :: RemoteEvent
local RequestAutoFight = Remotes:WaitForChild("RequestAutoFight") :: RemoteEvent
local AutoFightState = Remotes:WaitForChild("AutoFightState") :: RemoteEvent
local AutoTrainingState = Remotes:WaitForChild("AutoTrainingState") :: RemoteEvent
local EnemyUpdate = Remotes:WaitForChild("EnemyUpdate") :: RemoteEvent
local CombatVisual = Remotes:WaitForChild("CombatVisual") :: RemoteEvent
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
	battleOrigin: Vector3?,
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
local TeleportService
local TutorialService

local statesByModel: { [Model]: EnemyState } = {}
local statesByRoot: { [BasePart]: EnemyState } = {}
local statesById: { [string]: EnemyState } = {}
local battlesByPlayer: { [Player]: EnemyState } = {}
local lastAttackAt: { [Player]: number } = {}
local autoFightByPlayer: { [Player]: { enabled: boolean, token: number } } = {}
local rng = Random.new()

local PLAYER_AUTO_ATTACK_INTERVAL = 0.5
local AUTO_FIGHT_RETRY_DELAY = 0.75
local AUTO_FIGHT_MOVE_TIMEOUT = 14
local AUTO_FIGHT_REPATH_INTERVAL = 0.8
local getEnemyAccessPower: (EnemyState) -> number

local function fireCombatVisual(action: string, player: Player?, state: EnemyState?, extra: { [string]: any }?)
	if not player or not player.Parent or not state or not state.model.Parent then
		return
	end
	local payload = extra or {}
	payload.Action = action
	payload.Player = player
	payload.EnemyModel = state.model
	payload.EnemyRoot = state.root
	payload.EnemyId = state.def.Id
	CombatVisual:FireAllClients(payload)
end

local function getMaxRequiredPowerBeforeX(folderName: string, targetX: number): number
	local folder = Workspace:FindFirstChild(folderName)
	if not folder then
		return 0
	end
	local required = 0
	for _, desc in ipairs(folder:GetDescendants()) do
		if not desc:IsA("BasePart") then
			continue
		end
		local requiredPower = desc:GetAttribute("RequiredPower")
		if type(requiredPower) ~= "number" then
			continue
		end
		if desc.Position.X <= targetX + 0.25 then
			required = math.max(required, requiredPower)
		end
	end
	return required
end

local function getPathRequiredPower(state: EnemyState): number
	local targetX = state.root.Position.X
	return math.max(
		getMaxRequiredPowerBeforeX("AreaGates", targetX),
		getMaxRequiredPowerBeforeX("EnemyBorders", targetX)
	)
end

local function getCharacterRoot(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getCharacterHumanoid(player: Player): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid") :: Humanoid?
end

local function teleportToSpawnLab(player: Player)
	local hrp = getCharacterRoot(player)
	if not hrp then
		return
	end
	local spawn = Workspace:FindFirstChild("LabSpawn", true)
	if spawn and spawn:IsA("BasePart") then
		hrp.CFrame = spawn.CFrame + Vector3.new(0, 5, 0)
	else
		hrp.CFrame = CFrame.new(-180, 6, 0)
	end
end

local function isCloseEnough(player: Player, state: EnemyState, maxDistance: number): boolean
	local hrp = getCharacterRoot(player)
	if not hrp then
		return false
	end
	return (hrp.Position - state.root.Position).Magnitude <= maxDistance
end

local function horizontalDistance(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function getHomePosition(state: EnemyState): Vector3
	local hx = state.model:GetAttribute("HomeX")
	local hy = state.model:GetAttribute("HomeY")
	local hz = state.model:GetAttribute("HomeZ")
	if type(hx) == "number" and type(hy) == "number" and type(hz) == "number" then
		return Vector3.new(hx, hy, hz)
	end
	return state.root.Position
end

local function getBattleOrigin(state: EnemyState): Vector3
	return state.battleOrigin or getHomePosition(state)
end

local function getBattleLeashDistance(state: EnemyState): number
	return if state.def.IsBoss then EnemyConfig.BossBattleLeashDistance else EnemyConfig.BattleLeashDistance
end

local function isInsideBattleLeash(state: EnemyState, hrp: BasePart): boolean
	local origin = getBattleOrigin(state)
	local leash = getBattleLeashDistance(state)
	return horizontalDistance(hrp.Position, origin) <= leash
		and horizontalDistance(state.root.Position, origin) <= leash
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
	fireCombatVisual("End", owner, state)
	if owner and battlesByPlayer[owner] == state then
		battlesByPlayer[owner] = nil
		owner:SetAttribute("InCombat", false)
	end
	state.battleOwner = nil
	state.battleToken += 1
	state.battleOrigin = nil
	state.model:SetAttribute("BattleChasing", false)
	if state.battleHumanoidDiedConn then
		state.battleHumanoidDiedConn:Disconnect()
		state.battleHumanoidDiedConn = nil
	end
	setBattlePromptEnabled(state, state.alive)
	if message and owner and owner.Parent then
		ShowPopup:FireClient(owner, message)
	end
end

local function stepEnemyTowardPlayer(state: EnemyState, player: Player, dt: number)
	local hrp = getCharacterRoot(player)
	if not hrp or not state.model.PrimaryPart then
		return
	end

	local enemyPos = state.root.Position
	local targetPos = hrp.Position
	local flatDelta = Vector3.new(targetPos.X - enemyPos.X, 0, targetPos.Z - enemyPos.Z)
	local distance = flatDelta.Magnitude
	if distance <= EnemyConfig.EnemyAttackRange or distance <= 0.05 then
		return
	end

	local stepDistance = math.min(distance - EnemyConfig.EnemyAttackRange, EnemyConfig.EnemyChaseSpeed * dt)
	if stepDistance <= 0 then
		return
	end

	local nextPos = enemyPos + flatDelta.Unit * stepDistance
	local origin = getBattleOrigin(state)
	local leash = getBattleLeashDistance(state)
	local fromOrigin = Vector3.new(nextPos.X - origin.X, 0, nextPos.Z - origin.Z)
	if fromOrigin.Magnitude > leash then
		local clamped = fromOrigin.Unit * leash
		nextPos = Vector3.new(origin.X + clamped.X, nextPos.Y, origin.Z + clamped.Z)
	end
	state.model:PivotTo(CFrame.new(nextPos))
end

local function startEnemyChaseLoop(state: EnemyState, player: Player, token: number)
	task.spawn(function()
		while state.alive and state.battleOwner == player and state.battleToken == token do
			local dt = task.wait(EnemyConfig.EnemyChaseUpdateInterval)
			if not state.alive or state.battleOwner ~= player or state.battleToken ~= token then
				break
			end

			local humanoid = getCharacterHumanoid(player)
			local hrp = getCharacterRoot(player)
			if not humanoid or humanoid.Health <= 0 or not hrp then
				endBattle(state)
				break
			end
			if not isInsideBattleLeash(state, hrp) then
				endBattle(state, "Battle ended: enemy too far away.")
				break
			end

			stepEnemyTowardPlayer(state, player, dt)
		end
	end)
end

local function startEnemyAttackLoop(state: EnemyState, player: Player, token: number)
	task.spawn(function()
		while state.alive and state.battleOwner == player and state.battleToken == token do
			task.wait(EnemyConfig.EnemyAttackCooldownSec)
			if not state.alive or state.battleOwner ~= player or state.battleToken ~= token then
				break
			end

			local humanoid = getCharacterHumanoid(player)
			local hrp = getCharacterRoot(player)
			if not humanoid or humanoid.Health <= 0 or not hrp then
				endBattle(state)
				break
			end
			local distance = horizontalDistance(hrp.Position, state.root.Position)
			if not isInsideBattleLeash(state, hrp) then
				endBattle(state, "Battle ended: enemy too far away.")
				break
			end
			if distance > EnemyConfig.EnemyAttackRange then
				continue
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
	if state.def.IsBoss and TeleportService then
		TeleportService.recordBossDefeat(player, state.def.AreaIndex)
	end
	if TutorialService then
		TutorialService.record(player, if state.def.IsBoss then "BossDefeated" else "EnemyDefeated", {
			EnemyId = state.def.Id,
			AreaName = state.def.AreaName,
			AreaIndex = state.def.AreaIndex,
			DisplayName = state.def.DisplayName,
		})
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
	if profile.Power < getEnemyAccessPower(state) then
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
	fireCombatVisual("Hit", player, state, { Damage = damage })
	updateEnemy(state)
	if state.health <= 0 then
		defeatEnemy(player, state)
	end
end

local function startPlayerAutoAttackLoop(state: EnemyState, player: Player, token: number)
	task.spawn(function()
		while state.alive and state.battleOwner == player and state.battleToken == token do
			task.wait(PLAYER_AUTO_ATTACK_INTERVAL)
			if not state.alive or state.battleOwner ~= player or state.battleToken ~= token then
				break
			end
			local humanoid = getCharacterHumanoid(player)
			if not humanoid or humanoid.Health <= 0 then
				break
			end
			EnemyService.attack(player, state)
		end
	end)
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

local function startBattle(player: Player, state: EnemyState, silent: boolean?): boolean
	if not state.alive then
		return false
	end
	if not isCloseEnough(player, state, EnemyConfig.BattlePromptDistance + 3) then
		return false
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return false
	end
	if profile.Power < getEnemyAccessPower(state) then
		if not silent then
			ShowPopup:FireClient(player, "You need more Power!")
		end
		return false
	end
	local humanoid = getCharacterHumanoid(player)
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	if state.battleOwner == player then
		if not silent then
			ShowPopup:FireClient(player, "Battle already started!")
		end
		return true
	end
	if state.battleOwner then
		if not silent then
			ShowPopup:FireClient(player, "This enemy is already in battle!")
		end
		return false
	end

	local previousBattle = battlesByPlayer[player]
	if previousBattle and previousBattle ~= state then
		endBattle(previousBattle, "Previous battle ended.")
	end

	if player:GetAttribute("AutoTrainingEnabled") == true then
		player:SetAttribute("AutoTrainingEnabled", false)
		AutoTrainingState:FireClient(player, false)
	end

	state.battleOwner = player
	state.battleToken += 1
	state.battleOrigin = getHomePosition(state)
	battlesByPlayer[player] = state
	player:SetAttribute("InCombat", true)
	state.model:SetAttribute("BattleChasing", true)
	setBattlePromptEnabled(state, false)
	state.battleHumanoidDiedConn = humanoid.Died:Connect(function()
		if state.battleOwner == player then
			endBattle(state)
		end
	end)

	if not silent then
		ShowPopup:FireClient(player, "Battle started!")
	end
	fireCombatVisual("Start", player, state)
	startEnemyChaseLoop(state, player, state.battleToken)
	startEnemyAttackLoop(state, player, state.battleToken)
	startPlayerAutoAttackLoop(state, player, state.battleToken)
	return true
end

function getEnemyAccessPower(state: EnemyState): number
	local directRequiredPower
	if state.def.EnemyIndex == 1 then
		local area = AreaConfig.getById(state.def.AreaName)
		directRequiredPower = if area then area.requiredPower or 0 else 0
	else
		directRequiredPower = state.def.RequiredGatePower or 0
	end

	-- Auto Fight must respect the actual tunnel progression, not just the
	-- enemy's own number. If a locked border stands before the target, the
	-- enemy is not reachable yet.
	return math.max(directRequiredPower, getPathRequiredPower(state))
end

local function findBestEnemyForPlayer(player: Player): EnemyState?
	local profile = DataService.getProfile(player)
	if not profile then
		return nil
	end
	local currentPower = profile.Power or 0
	local best: EnemyState? = nil
	local bestRequirement = -1
	local bestPriority = -1
	for _, state in pairs(statesById) do
		if not state.alive or not state.model.Parent or state.battleOwner ~= nil then
			continue
		end
		local accessPower = getEnemyAccessPower(state)
		if accessPower > currentPower then
			continue
		end
		local priority = state.def.GlobalIndex or state.def.EnemyIndex or 0
		if accessPower > bestRequirement or (accessPower == bestRequirement and priority > bestPriority) then
			best = state
			bestRequirement = accessPower
			bestPriority = priority
		end
	end
	return best
end

local function canAutoFightTarget(player: Player, state: EnemyState): boolean
	local profile = DataService.getProfile(player)
	return profile ~= nil and (profile.Power or 0) >= getEnemyAccessPower(state)
end

local function getAutoFightState(player: Player)
	local state = autoFightByPlayer[player]
	if not state then
		state = { enabled = false, token = 0 }
		autoFightByPlayer[player] = state
	end
	return state
end

local function isAutoFightEnabled(player: Player, token: number): boolean
	local state = autoFightByPlayer[player]
	return state ~= nil
		and state.enabled
		and state.token == token
		and player.Parent ~= nil
		and player:GetAttribute("AutoFightEnabled") == true
		and player:GetAttribute("AutoTrainingEnabled") ~= true
end

local function stopAutoFight(player: Player, message: string?)
	local state = getAutoFightState(player)
	if not state.enabled and message == nil then
		AutoFightState:FireClient(player, false)
		return
	end
	state.enabled = false
	state.token += 1
	player:SetAttribute("AutoFightEnabled", false)
	AutoFightState:FireClient(player, false)
	local humanoid = getCharacterHumanoid(player)
	local hrp = getCharacterRoot(player)
	if humanoid and hrp then
		humanoid:MoveTo(hrp.Position)
	end
	local activeBattle = battlesByPlayer[player]
	if activeBattle then
		endBattle(activeBattle)
	end
	if message and player.Parent then
		ShowPopup:FireClient(player, message)
	end
end

local function bindAutoTrainingCancel(player: Player)
	player:GetAttributeChangedSignal("AutoTrainingEnabled"):Connect(function()
		if player:GetAttribute("AutoTrainingEnabled") == true then
			stopAutoFight(player)
		end
	end)
	player:GetAttributeChangedSignal("AutoFightEnabled"):Connect(function()
		local state = autoFightByPlayer[player]
		if player:GetAttribute("AutoFightEnabled") ~= true and state and state.enabled then
			stopAutoFight(player)
		end
	end)
end

local function movePlayerNearEnemy(player: Player, target: EnemyState, token: number): boolean
	local humanoid = getCharacterHumanoid(player)
	local hrp = getCharacterRoot(player)
	if not humanoid or humanoid.Health <= 0 or not hrp then
		return false
	end
	local startedAt = os.clock()
	local lastMoveAt = 0
	while isAutoFightEnabled(player, token) and target.alive and target.model.Parent do
		humanoid = getCharacterHumanoid(player)
		hrp = getCharacterRoot(player)
		if not humanoid or humanoid.Health <= 0 or not hrp then
			return false
		end
		if (hrp.Position - target.root.Position).Magnitude <= EnemyConfig.BattlePromptDistance + 4 then
			return true
		end
		if os.clock() - startedAt > AUTO_FIGHT_MOVE_TIMEOUT then
			return false
		end
		if os.clock() - lastMoveAt >= AUTO_FIGHT_REPATH_INTERVAL then
			lastMoveAt = os.clock()
			local offset = Vector3.new(-math.max(6, EnemyConfig.EnemyAttackRange - 1), 0, 0)
			humanoid:MoveTo(target.root.Position + offset)
		end
		task.wait(0.1)
	end
	return false
end

local function runAutoFightLoop(player: Player, token: number)
	task.spawn(function()
		while isAutoFightEnabled(player, token) do
			local humanoid = getCharacterHumanoid(player)
			if not humanoid or humanoid.Health <= 0 then
				stopAutoFight(player)
				break
			end

			local target = findBestEnemyForPlayer(player)
			if not target then
				stopAutoFight(player, "No valid enemy found")
				break
			end

			ShowPopup:FireClient(player, "Targeting strongest enemy")
			local reached = movePlayerNearEnemy(player, target, token)
			if not isAutoFightEnabled(player, token) then
				break
			end
			if not reached then
				task.wait(AUTO_FIGHT_RETRY_DELAY)
				continue
			end
			if not canAutoFightTarget(player, target) then
				task.wait(AUTO_FIGHT_RETRY_DELAY)
				continue
			end

			local started = startBattle(player, target, true)
			if not started then
				task.wait(AUTO_FIGHT_RETRY_DELAY)
				continue
			end

			while isAutoFightEnabled(player, token) and target.alive and battlesByPlayer[player] == target do
				task.wait(0.25)
			end

			if not isAutoFightEnabled(player, token) then
				break
			end
			task.wait(AUTO_FIGHT_RETRY_DELAY)
		end
	end)
end

local function setAutoFightEnabled(player: Player, enabled: boolean)
	local state = getAutoFightState(player)
	if enabled then
		if state.enabled then
			AutoFightState:FireClient(player, true)
			return
		end
		player:SetAttribute("AutoTrainingEnabled", false)
		AutoTrainingState:FireClient(player, false)
		player:SetAttribute("AutoFightEnabled", true)
		state.enabled = true
		state.token += 1
		AutoFightState:FireClient(player, true)
		ShowPopup:FireClient(player, "Auto Fight enabled")
		runAutoFightLoop(player, state.token)
	else
		stopAutoFight(player, "Auto Fight disabled")
	end
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
	model:SetAttribute("BattleChasing", false)
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
		battleOrigin = nil,
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
	TeleportService = deps.TeleportService
	TutorialService = deps.TutorialService

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

	AntiExploitService.safeBind(RequestAutoFight, 2, function(player, enabled)
		setAutoFightEnabled(player, enabled == true)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		bindAutoTrainingCancel(player)
	end
	Players.PlayerAdded:Connect(bindAutoTrainingCancel)

	Players.PlayerRemoving:Connect(function(player)
		lastAttackAt[player] = nil
		autoFightByPlayer[player] = nil
		player:SetAttribute("AutoFightEnabled", false)
		player:SetAttribute("AutoTrainingEnabled", false)
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
