--!strict
-- Client-only combat visuals. Damage, rewards and enemy state stay server-authoritative.
-- Punch motion is driven by real Roblox AnimationTracks so character arms visibly move.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CombatAnimationConfig = require(Configs:WaitForChild("CombatAnimationConfig"))
local CombatVisual = Remotes:WaitForChild("CombatVisual") :: RemoteEvent

local CombatVisualController = {}

type CombatState = {
	player: Player,
	character: Model,
	humanoid: Humanoid,
	animator: Animator,
	enemyRoot: BasePart?,
	loopTrack: AnimationTrack?,
	rightTrack: AnimationTrack?,
	leftTrack: AnimationTrack?,
	nextSide: "Right" | "Left",
	diedConnection: RBXScriptConnection?,
	characterRemovingConnection: RBXScriptConnection?,
}

local states: { [Player]: CombatState } = {}
local started = false

local function debugLog(message: string)
	if CombatAnimationConfig.Debug then
		print("[CombatAnimation] " .. message)
	end
end

local function debugWarn(message: string)
	warn("[CombatAnimation] " .. message)
end

local function asAnimationId(value: any): string?
	if type(value) ~= "string" then
		return nil
	end

	local trimmed = value:gsub("^%s+", ""):gsub("%s+$", "")
	if trimmed == "" or trimmed == "0" or trimmed == "rbxassetid://0" then
		return nil
	end
	if string.find(trimmed, "HIER") then
		return nil
	end
	if string.match(trimmed, "^%d+$") then
		return "rbxassetid://" .. trimmed
	end
	if string.match(trimmed, "^rbxassetid://%d+$") then
		return trimmed
	end

	return nil
end

local function getRigType(humanoid: Humanoid): "R15" | "R6"
	return if humanoid.RigType == Enum.HumanoidRigType.R15 then "R15" else "R6"
end

local function getLoopAnimationId(rigType: "R15" | "R6"): string?
	local configured = asAnimationId(CombatAnimationConfig.PunchLoopAnimationId)
	if configured then
		return configured
	end

	if CombatAnimationConfig.EnableRobloxDefaultFallback then
		local fallback = if rigType == "R15"
			then asAnimationId(CombatAnimationConfig.R15PunchLoopAnimationId)
			else asAnimationId(CombatAnimationConfig.R6PunchLoopAnimationId)
		if fallback then
			debugWarn("Missing PunchAnimationId; using Roblox default fallback")
			return fallback
		end
	end

	return nil
end

local function ensureAnimator(humanoid: Humanoid): Animator?
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end

	debugWarn("Missing Animator")
	animator = Instance.new("Animator")
	animator.Name = "Animator"
	animator.Parent = humanoid
	return animator
end

local function loadTrack(animator: Animator, animationId: string, looped: boolean): AnimationTrack?
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	local ok, trackOrError = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()

	if not ok then
		debugWarn("Punch animation cannot play: " .. tostring(trackOrError))
		return nil
	end

	local track = trackOrError :: AnimationTrack
	track.Priority = CombatAnimationConfig.Priority or Enum.AnimationPriority.Action
	track.Looped = looped
	debugLog("Punch animation loaded")
	return track
end

local function cleanupState(state: CombatState, fadeOut: number?)
	local fade = fadeOut or CombatAnimationConfig.FadeOut or 0.12
	local tracks = { state.loopTrack, state.rightTrack, state.leftTrack }

	for _, track in ipairs(tracks) do
		if track then
			pcall(function()
				if track.IsPlaying then
					track:Stop(fade)
				end
				track:Destroy()
			end)
		end
	end

	if state.diedConnection then
		state.diedConnection:Disconnect()
	end
	if state.characterRemovingConnection then
		state.characterRemovingConnection:Disconnect()
	end
end

local function stopCombat(player: Player)
	local state = states[player]
	if not state then
		return
	end

	cleanupState(state)
	states[player] = nil
	debugLog("Combat animation stopped")
end

local function buildState(player: Player, enemyRoot: BasePart?): CombatState?
	local character = player.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	local animator = ensureAnimator(humanoid)
	if not animator then
		return nil
	end

	local rigType = getRigType(humanoid)
	local configuredRig = CombatAnimationConfig.RigType
	if configuredRig ~= nil and configuredRig ~= "Auto" and configuredRig ~= rigType then
		debugWarn("Wrong rig type possible")
	end

	local loopId = getLoopAnimationId(rigType)
	local rightId = asAnimationId(CombatAnimationConfig.RightPunchAnimationId)
	local leftId = asAnimationId(CombatAnimationConfig.LeftPunchAnimationId)

	if not loopId and not rightId and not leftId then
		debugWarn("Missing PunchAnimationId")
		debugWarn("Punch animation cannot play: missing valid AnimationId")
		return nil
	end

	local loopTrack = if loopId then loadTrack(animator, loopId, true) else nil
	local rightTrack = if rightId then loadTrack(animator, rightId, false) else nil
	local leftTrack = if leftId then loadTrack(animator, leftId, false) else nil

	if not loopTrack and not rightTrack and not leftTrack then
		debugWarn("Punch animation cannot play: missing valid AnimationId")
		return nil
	end

	local state: CombatState = {
		player = player,
		character = character,
		humanoid = humanoid,
		animator = animator,
		enemyRoot = enemyRoot,
		loopTrack = loopTrack,
		rightTrack = rightTrack,
		leftTrack = leftTrack,
		nextSide = "Right",
		diedConnection = nil,
		characterRemovingConnection = nil,
	}

	state.diedConnection = humanoid.Died:Connect(function()
		stopCombat(player)
	end)
	state.characterRemovingConnection = player.CharacterRemoving:Connect(function(removingCharacter)
		if removingCharacter == character then
			stopCombat(player)
		end
	end)

	return state
end

local function playLoop(state: CombatState)
	local track = state.loopTrack
	if not track then
		return
	end

	if track.IsPlaying then
		return
	end

	track:Play(CombatAnimationConfig.FadeIn or 0.08, 1, CombatAnimationConfig.LoopSpeed or 1.15)
	debugLog("Punch animation playing")
end

local function startCombat(player: Player, enemyRoot: BasePart?)
	local existing = states[player]
	if existing and existing.character == player.Character and existing.humanoid.Health > 0 then
		existing.enemyRoot = enemyRoot
		playLoop(existing)
		return
	elseif existing then
		stopCombat(player)
	end

	local state = buildState(player, enemyRoot)
	if not state then
		return
	end

	states[player] = state
	debugLog("Combat animation started")
	playLoop(state)
end

local function emitHitFeedback(enemyRoot: BasePart?)
	if not enemyRoot or not enemyRoot.Parent then
		return
	end

	local originalColor = enemyRoot.Color
	enemyRoot.Color = Color3.fromRGB(255, 85, 78)
	task.delay(0.08, function()
		if enemyRoot.Parent then
			enemyRoot.Color = originalColor
		end
	end)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "LocalCombatHitSparks"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(95, 255, 135)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 220, 255)),
	})
	emitter.Lifetime = NumberRange.new(0.16, 0.32)
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(4, 9)
	emitter.SpreadAngle = Vector2.new(95, 95)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.34),
		NumberSequenceKeypoint.new(1, 0.04),
	})
	emitter.LightEmission = 0.4
	emitter.Parent = enemyRoot
	emitter:Emit(8)
	task.delay(0.45, function()
		if emitter.Parent then
			emitter:Destroy()
		end
	end)
end

local function playHitTrack(state: CombatState)
	local track: AnimationTrack? = nil

	if state.nextSide == "Right" then
		track = state.rightTrack or state.leftTrack
		state.nextSide = "Left"
	else
		track = state.leftTrack or state.rightTrack
		state.nextSide = "Right"
	end

	if not track then
		playLoop(state)
		return
	end

	pcall(function()
		if track.IsPlaying then
			track:Stop(0)
		end
		track:Play(CombatAnimationConfig.FadeIn or 0.08, 1, CombatAnimationConfig.HitSpeed or 1.25)
	end)
	debugLog("Punch animation playing")
end

local function onHit(player: Player, enemyRoot: BasePart?)
	startCombat(player, enemyRoot)
	local state = states[player]
	if state then
		state.enemyRoot = enemyRoot
		playHitTrack(state)
	end
	emitHitFeedback(enemyRoot)
end

function CombatVisualController.start()
	if started then
		return
	end
	started = true

	CombatVisual.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end

		local action = payload.Action
		local player = payload.Player
		local enemyRoot = payload.EnemyRoot
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return
		end

		local root = if typeof(enemyRoot) == "Instance" and enemyRoot:IsA("BasePart") then enemyRoot else nil
		if action == "Start" then
			startCombat(player, root)
		elseif action == "Hit" then
			onHit(player, root)
		elseif action == "End" then
			stopCombat(player)
		end
	end)

	Players.PlayerRemoving:Connect(stopCombat)
end

return CombatVisualController
