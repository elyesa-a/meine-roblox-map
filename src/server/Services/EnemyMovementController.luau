--!nonstrict
-- EnemyMovementController: laesst die Gegner LEBENDIG, aber KONTROLLIERT in
-- ihrer eigenen Zone wirken -- ohne das bestehende Kampf-/Respawn-System
-- (EnemyService) zu beruehren.
--
-- Funktionsweise:
--   * Liest die vom VirusLabBuilder gesetzten Movement-Attribute pro Gegner
--     (MoveStyle, HomeX/Y/Z, MoveRangeX/Z, MoveSpeed, BobAmp).
--   * Bewegt das ganze Model rein server-seitig per Model:PivotTo() in einer
--     EINZIGEN, gedrosselten Heartbeat-Schleife (fester 1/15s-Takt). Keine
--     aggressiven Loops, kein Pathfinding, keine Raycasts.
--   * Die Reichweiten sind so klein, dass jeder Gegner auf seiner eigenen
--     Plattform bleibt: nie in Spawn/andere Areas, nie durch Waende/Gates.
--   * Bewegt nur lebende (Attribut "Alive" ~= false, von EnemyService
--     gesetzt) Gegner in Spielernaehe -> performant.
--   * Bosse (MoveStyle == "Static") bleiben bewusst stehen (imposant, und
--     ihre kollidierende Stand-Plattform soll Spieler nicht schieben).
--
-- Vertrag: setzt nur CFrames via PivotTo. Health-Bar bleibt korrekt, weil
-- EnemyService die Fuellung relativ zum (mitbewegten) HealthBarBack setzt.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local EnemyMovementController = {}

local STEP = 1 / 15 -- fester Bewegungstakt (gedrosselt)
local ACTIVE_RADIUS = 240 -- nur Gegner in Spielernaehe bewegen
local ACTIVE_RADIUS_SQ = ACTIVE_RADIUS * ACTIVE_RADIUS
local WATCH_RADIUS = 70
local WATCH_RADIUS_SQ = WATCH_RADIUS * WATCH_RADIUS

type LimbState = {
	part: BasePart,
	localCFrame: CFrame,
	side: number,
	phase: number,
	swing: number,
	lift: number,
	stride: number,
	lateral: number,
}

type BlinkState = {
	part: BasePart,
	originalSize: Vector3,
	originalTransparency: number,
	mesh: SpecialMesh?,
	meshScale: Vector3?,
}

type MoveState = {
	model: Model,
	style: string,
	areaIndex: number,
	stage: number,
	home: Vector3,
	rx: number,
	rz: number,
	speed: number,
	bob: number,
	phase: number,
	target: Vector3,
	pos: Vector3,
	velocity: Vector3,
	facing: Vector3,
	pauseUntil: number,
	limbs: { LimbState },
	blinkParts: { BlinkState },
	nextBlinkAt: number,
	lastAlive: boolean,
	wasChasing: boolean,
}

local states: { MoveState } = {}
local byModel: { [Model]: boolean } = {}
local accumulator = 0
local elapsed = 0
local rng = Random.new()

local function pickTarget(st: MoveState)
	-- Zufallspunkt im Zonen-Rechteck um die Home-Position.
	local nx = st.home.X + rng:NextNumber(-st.rx, st.rx)
	local nz = st.home.Z + rng:NextNumber(-st.rz, st.rz)
	st.target = Vector3.new(nx, st.home.Y, nz)
end

local function getEnemyStage(model: Model): number
	local id = model:GetAttribute("EnemyId")
	if type(id) ~= "string" then
		id = model.Name
	end
	local parsed = string.match(id, "E(%d+)$")
	return tonumber(parsed) or 0
end

local function getEnemyArea(model: Model): number
	local id = model:GetAttribute("EnemyId")
	if type(id) ~= "string" then
		id = model.Name
	end
	local parsed = string.match(id, "^A(%d+)E")
	return tonumber(parsed) or 0
end

local function effectiveStyle(st: MoveState): string
	-- Area/Stage 1 soll bodennah bleiben: alle fuenf ersten Gegner wirken
	-- wie kleine Labor-Lebewesen, nicht wie springende Baelle.
	if st.areaIndex == 1 and st.style == "Hop" then
		return "Ground"
	end
	return st.style
end

local function flatUnit(v: Vector3, fallback: Vector3): Vector3
	local flat = Vector3.new(v.X, 0, v.Z)
	if flat.Magnitude < 0.05 then
		return fallback
	end
	return flat.Unit
end

local function smoothFacing(current: Vector3, desired: Vector3, alpha: number): Vector3
	local currentFlat = flatUnit(current, Vector3.new(0, 0, -1))
	local desiredFlat = flatUnit(desired, currentFlat)
	local mixed = currentFlat:Lerp(desiredFlat, math.clamp(alpha, 0, 1))
	if mixed.Magnitude < 0.05 then
		return currentFlat
	end
	return mixed.Unit
end

local function isLimbPart(part: BasePart): boolean
	local n = part.Name
	if n == "EnemyCore" or n == "HealthBarBack" or n == "HealthBarFill" then
		return false
	end
	return n:find("Leg") ~= nil
		or n:find("Foot") ~= nil
		or n:find("Boot") ~= nil
		or n:find("Toe") ~= nil
		or n:find("Claw") ~= nil
		or n:find("Cilia") ~= nil
		or n:find("Tentacle") ~= nil
		or n:find("Tendril") ~= nil
		or n:find("Cable") ~= nil
		or n:find("Mandible") ~= nil
		or n:find("Arm") ~= nil
end

local function isMainEyePart(part: BasePart): boolean
	local n = part.Name
	if n:find("Pupil") or n:find("Glow") or n:find("Socket") or n:find("Inner") then
		return false
	end
	return n:find("Eye") ~= nil or n == "ScannerEye"
end

local function isEyeVisualPart(part: BasePart): boolean
	local n = part.Name
	if n:find("Socket") then
		return false
	end
	return n:find("Eye") ~= nil or n:find("Pupil") ~= nil
end

local function collectLimbStates(model: Model): { LimbState }
	local limbs: { LimbState } = {}
	local primary = model.PrimaryPart
	if not primary then
		return limbs
	end
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") and isLimbPart(inst) then
			local side = if inst.Position.X >= primary.Position.X then 1 else -1
			local sizeScale = math.clamp((inst.Size.X + inst.Size.Y + inst.Size.Z) / 9, 0.35, 1.8)
			table.insert(limbs, {
				part = inst,
				localCFrame = primary.CFrame:ToObjectSpace(inst.CFrame),
				side = side,
				phase = rng:NextNumber(0, math.pi * 2),
				swing = math.rad(18 + rng:NextNumber(8, 18)) * sizeScale,
				lift = math.clamp(inst.Size.Y * 0.18, 0.12, 0.9),
				stride = math.clamp(inst.Size.Z * 0.22, 0.12, 0.85),
				lateral = math.clamp(inst.Size.X * 0.12, 0.04, 0.35),
			})
		end
	end
	return limbs
end

local function collectBlinkParts(model: Model): { BlinkState }
	local primary = model.PrimaryPart
	if not primary then
		return {}
	end

	local mainEyes = 0
	local hasObviousSingleEye = false
	local blinkParts: { BlinkState } = {}
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") and isMainEyePart(inst) then
			mainEyes += 1
			if inst.Name == "ScannerEye" or inst.Name == "BoneBossEye" or inst.Name == "CytokineWormEye" then
				hasObviousSingleEye = true
			end
		end
	end
	if mainEyes ~= 1 and not hasObviousSingleEye then
		return blinkParts
	end

	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") and isEyeVisualPart(inst) then
			local mesh = inst:FindFirstChildOfClass("SpecialMesh")
			table.insert(blinkParts, {
				part = inst,
				originalSize = inst.Size,
				originalTransparency = inst.Transparency,
				mesh = mesh,
				meshScale = if mesh then mesh.Scale else nil,
			})
		end
	end
	return blinkParts
end

local function register(model: Model)
	if byModel[model] then
		return
	end
	local style = model:GetAttribute("MoveStyle")
	if type(style) ~= "string" or style == "Static" then
		return
	end
	if not model.PrimaryPart then
		return
	end
	local hx = model:GetAttribute("HomeX")
	local hy = model:GetAttribute("HomeY")
	local hz = model:GetAttribute("HomeZ")
	if type(hx) ~= "number" or type(hy) ~= "number" or type(hz) ~= "number" then
		return
	end
	local home = Vector3.new(hx, hy, hz)
	local st: MoveState = {
		model = model,
		style = style,
		areaIndex = getEnemyArea(model),
		stage = getEnemyStage(model),
		home = home,
		rx = model:GetAttribute("MoveRangeX") or 6,
		rz = model:GetAttribute("MoveRangeZ") or 10,
		speed = model:GetAttribute("MoveSpeed") or 3,
		bob = model:GetAttribute("BobAmp") or 0.4,
		phase = rng:NextNumber(0, math.pi * 2),
		target = home,
		pos = home,
		velocity = Vector3.zero,
		facing = flatUnit(model.PrimaryPart.CFrame.LookVector, Vector3.new(0, 0, -1)),
		pauseUntil = 0,
		limbs = collectLimbStates(model),
		blinkParts = collectBlinkParts(model),
		nextBlinkAt = rng:NextNumber(2.0, 5.0),
		lastAlive = true,
		wasChasing = false,
	}
	if st.areaIndex == 1 then
		st.bob = math.min(st.bob, 0.12)
	end
	pickTarget(st)
	byModel[model] = true
	table.insert(states, st)
end

local function anyPlayerNear(p: Vector3): boolean
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local d = (hrp.Position - p)
			if d.X * d.X + d.Z * d.Z <= ACTIVE_RADIUS_SQ then
				return true
			end
		end
	end
	return false
end

local function nearestPlayerPosition(p: Vector3): (Vector3?, number)
	local nearest: Vector3? = nil
	local nearestSq = WATCH_RADIUS_SQ
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local d = hrp.Position - p
			local sq = d.X * d.X + d.Z * d.Z
			if sq < nearestSq then
				nearestSq = sq
				nearest = hrp.Position
			end
		end
	end
	return nearest, nearestSq
end

local function animateLimbs(st: MoveState, pivot: CFrame, moveAmount: number, style: string)
	if #st.limbs == 0 then
		return
	end
	local gaitSpeed = if style == "Crawl" then 8.8 elseif style == "Hop" then 5.8 else 6.4
	local strideAmount = math.clamp(moveAmount, 0.22, 1)
	for i, limb in ipairs(st.limbs) do
		if not limb.part.Parent then
			continue
		end
		local t = elapsed * gaitSpeed + limb.phase + i * 0.55
		local opposite = limb.side * math.sin(t)
		local swing = opposite * limb.swing * strideAmount
		local footCycle = math.sin(t + math.pi * 0.5)
		local lift = math.max(0, footCycle) * limb.lift * strideAmount
		local stride = math.sin(t) * limb.stride * strideAmount
		local sideSlide = math.cos(t * 0.7) * limb.lateral * limb.side * strideAmount
		local crawlSpread = if style == "Crawl" then math.sin(t * 0.5) * math.rad(8) else 0
		local hopTuck = if style == "Hop" then math.abs(math.sin(t * 0.5)) * math.rad(8) else 0
		local twist = math.sin(t * 0.85) * math.rad(6) * limb.side * strideAmount
		limb.part.CFrame = pivot
			* limb.localCFrame
			* CFrame.new(sideSlide, lift, stride)
			* CFrame.Angles(swing + hopTuck, twist, crawlSpread * limb.side)
	end
end

local function animateBlink(st: MoveState)
	if #st.blinkParts == 0 then
		return
	end

	local blinkProgress = elapsed - st.nextBlinkAt
	local blinkWindow = 0.18
	if blinkProgress > blinkWindow then
		st.nextBlinkAt = elapsed + rng:NextNumber(2.6, 6.2)
		blinkProgress = -1
	end

	local closeAmount = 0
	if blinkProgress >= 0 then
		local p = math.clamp(blinkProgress / blinkWindow, 0, 1)
		closeAmount = math.sin(p * math.pi)
	end

	for _, eye in ipairs(st.blinkParts) do
		if not eye.part.Parent then
			continue
		end
		local squish = 1 - closeAmount * 0.96
		eye.part.Size = Vector3.new(eye.originalSize.X, math.max(0.04, eye.originalSize.Y * squish), eye.originalSize.Z)
		eye.part.Transparency = math.clamp(eye.originalTransparency + closeAmount * 0.18, 0, 0.95)
		if eye.mesh and eye.meshScale then
			eye.mesh.Scale = Vector3.new(eye.meshScale.X, math.max(0.03, eye.meshScale.Y * squish), eye.meshScale.Z)
		end
	end
end

local function stepState(st: MoveState, dt: number)
	local model = st.model
	if not model.Parent or not model.PrimaryPart then
		return
	end

	-- Tote/unsichtbare Gegner (EnemyService setzt "Alive") nicht bewegen.
	local alive = model:GetAttribute("Alive")
	if alive == false then
		st.lastAlive = false
		return
	end
	if not st.lastAlive then
		-- Respawn: sauber an die Home-Position zuruecksetzen.
		st.lastAlive = true
		st.pos = st.home
		st.velocity = Vector3.zero
		st.pauseUntil = 0
		pickTarget(st)
	end
	if model:GetAttribute("BattleChasing") == true then
		local battleStyle = effectiveStyle(st)
		local currentPivot = model.PrimaryPart.CFrame
		local currentPos = model.PrimaryPart.Position
		local moved = Vector3.new(currentPos.X - st.pos.X, 0, currentPos.Z - st.pos.Z)
		local battleMoveAmount = if moved.Magnitude > 0.03 then 1 else 0.25
		animateLimbs(st, currentPivot, battleMoveAmount, battleStyle)
		animateBlink(st)
		st.pos = Vector3.new(currentPos.X, st.home.Y, currentPos.Z)
		st.wasChasing = true
		return
	end
	if st.wasChasing then
		local current = model.PrimaryPart.Position
		st.pos = Vector3.new(current.X, st.home.Y, current.Z)
		st.velocity = Vector3.zero
		st.pauseUntil = elapsed + rng:NextNumber(0.25, 0.8)
		pickTarget(st)
		st.wasChasing = false
	end

	if not anyPlayerNear(st.home) then
		return
	end

	local style = effectiveStyle(st)
	local pos = st.pos
	local previousPos = pos
	local watcherPos, watcherSq = nearestPlayerPosition(st.home)
	local bobY = 0
	local pitch = 0
	local roll = 0
	local moveAmount = 0
	local canMove = elapsed >= st.pauseUntil

	if style == "Hover" then
		-- Sanftes Lissajous-Schweben + Auf/Ab.
		local t = elapsed + st.phase
		local ox = math.sin(t * 0.5) * st.rx
		local oz = math.cos(t * 0.37) * st.rz
		pos = Vector3.new(st.home.X + ox, st.home.Y, st.home.Z + oz)
		bobY = math.sin(t * 1.1) * st.bob
		st.velocity = (pos - previousPos) / math.max(dt, 0.001)
		moveAmount = math.clamp(st.velocity.Magnitude / math.max(st.speed, 0.1), 0, 1)
		pitch = math.sin(t * 0.8) * math.rad(2)
		roll = math.cos(t * 0.9) * math.rad(3)
	elseif style == "Hop" then
		-- Langsames Driften + huepfender Bogen (nie unter die Plattform).
		local toT = st.target - Vector3.new(pos.X, st.home.Y, pos.Z)
		if toT.Magnitude < 1.5 then
			st.pauseUntil = elapsed + rng:NextNumber(0.15, 0.65)
			pickTarget(st)
		elseif canMove then
			local desired = toT.Unit * st.speed
			st.velocity = st.velocity:Lerp(desired, math.clamp(dt * 5.2, 0, 1))
			local stepv = st.velocity * dt
			if stepv.Magnitude > toT.Magnitude then
				stepv = toT
			end
			pos = Vector3.new(pos.X + stepv.X, st.home.Y, pos.Z + stepv.Z)
		else
			st.velocity = st.velocity:Lerp(Vector3.zero, math.clamp(dt * 5, 0, 1))
		end
		local hop = math.abs(math.sin((elapsed + st.phase) * 3.2))
		moveAmount = math.clamp(st.velocity.Magnitude / math.max(st.speed, 0.1), 0, 1)
		bobY = hop * st.bob + math.sin((elapsed + st.phase) * 1.3) * 0.08
		pitch = -math.sin((elapsed + st.phase) * 3.2) * math.rad(3)
		roll = math.sin((elapsed + st.phase) * 1.7) * math.rad(1.4)
	else
		-- Ground / Sway / Crawl: zwischen Zonen-Punkten laufen + leichtes Wippen.
		local flat = Vector3.new(pos.X, st.home.Y, pos.Z)
		local toT = st.target - flat
		if toT.Magnitude < 1.2 then
			st.pauseUntil = elapsed + rng:NextNumber(0.25, if style == "Crawl" then 0.9 else 1.25)
			pickTarget(st)
		elseif canMove then
			local speedMul = if style == "Crawl" then 1.15 elseif style == "Sway" then 0.75 else 1
			local desired = toT.Unit * st.speed * speedMul
			local accel = if style == "Crawl" then 6.2 elseif style == "Sway" then 2.4 else 3.6
			st.velocity = st.velocity:Lerp(desired, math.clamp(dt * accel, 0, 1))
			local stepv = st.velocity * dt
			if stepv.Magnitude > toT.Magnitude then
				stepv = toT
			end
			pos = Vector3.new(pos.X + stepv.X, st.home.Y, pos.Z + stepv.Z)
		else
			st.velocity = st.velocity:Lerp(Vector3.zero, math.clamp(dt * 4, 0, 1))
		end
		local gait = elapsed + st.phase
		moveAmount = math.clamp(st.velocity.Magnitude / math.max(st.speed, 0.1), 0, 1)
		bobY = math.sin(gait * (if style == "Crawl" then 7.5 else 4.0)) * st.bob * (0.25 + moveAmount * 0.75)
		roll = math.sin(gait * (if style == "Crawl" then 5.8 else 2.6)) * math.rad(if style == "Crawl" then 3.2 else 1.6)
		pitch = math.cos(gait * 2.1) * math.rad(if style == "Sway" then 2.2 else 1.1) * (0.35 + moveAmount * 0.65)
	end

	-- Hart auf die eigene Zone klemmen (Sicherheitsnetz gegen Ausbruch).
	local cx = math.clamp(pos.X, st.home.X - st.rx, st.home.X + st.rx)
	local cz = math.clamp(pos.Z, st.home.Z - st.rz, st.home.Z + st.rz)
	st.pos = Vector3.new(cx, st.home.Y, cz)

	local moved = st.pos - previousPos
	if moved.Magnitude > 0.03 then
		st.facing = smoothFacing(st.facing, moved, if style == "Hover" then 0.08 else 0.16)
	elseif watcherPos and watcherSq < WATCH_RADIUS_SQ * 0.55 then
		st.facing = smoothFacing(st.facing, watcherPos - st.pos, 0.045)
	end

	-- Natuerlicher als reines Verschieben: Gegner drehen sanft in ihre
	-- Bewegungsrichtung und bekommen je nach Stil ein winziges Koerper-Wippen.
	local pivotPos = Vector3.new(cx, st.home.Y + bobY, cz)
	local breathing = math.sin((elapsed + st.phase) * 1.4) * math.rad(0.8)
	local pivot = CFrame.lookAt(pivotPos, pivotPos + st.facing) * CFrame.Angles(pitch + breathing, 0, roll)
	model:PivotTo(pivot)
	animateLimbs(st, pivot, moveAmount, style)
	animateBlink(st)
end

function EnemyMovementController.start()
	local enemyAreas = Workspace:FindFirstChild("EnemyAreas")
	if enemyAreas then
		for _, d in ipairs(enemyAreas:GetDescendants()) do
			if d:IsA("Model") and d:GetAttribute("MoveStyle") ~= nil then
				register(d)
			end
		end
		enemyAreas.DescendantAdded:Connect(function(d)
			if d:IsA("Model") and d:GetAttribute("MoveStyle") ~= nil then
				task.defer(register, d)
			end
		end)
	end
	local bossFields = Workspace:FindFirstChild("BossFields")
	if bossFields then
		for _, d in ipairs(bossFields:GetDescendants()) do
			if d:IsA("Model") and d:GetAttribute("MoveStyle") ~= nil then
				register(d)
			end
		end
	end

	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < STEP then
			return
		end
		local frameDt = accumulator
		accumulator = 0
		elapsed += frameDt
		for _, st in ipairs(states) do
			stepState(st, frameDt)
		end
	end)

	local limbCount = 0
	local blinkCount = 0
	for _, st in ipairs(states) do
		limbCount += #st.limbs
		blinkCount += #st.blinkParts
	end
	print(string.format(
		"[EnemyMovementController] %d bewegliche Gegner registriert. Limb parts: %d, blink parts: %d.",
		#states,
		limbCount,
		blinkCount
	))
end

return EnemyMovementController
