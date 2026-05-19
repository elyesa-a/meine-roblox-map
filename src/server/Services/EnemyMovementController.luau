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

type MoveState = {
	model: Model,
	style: string,
	home: Vector3,
	rx: number,
	rz: number,
	speed: number,
	bob: number,
	phase: number,
	target: Vector3,
	pos: Vector3,
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
		home = home,
		rx = model:GetAttribute("MoveRangeX") or 6,
		rz = model:GetAttribute("MoveRangeZ") or 10,
		speed = model:GetAttribute("MoveSpeed") or 3,
		bob = model:GetAttribute("BobAmp") or 0.4,
		phase = rng:NextNumber(0, math.pi * 2),
		target = home,
		pos = home,
		lastAlive = true,
		wasChasing = false,
	}
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
		pickTarget(st)
	end
	if model:GetAttribute("BattleChasing") == true then
		st.wasChasing = true
		return
	end
	if st.wasChasing then
		local current = model.PrimaryPart.Position
		st.pos = Vector3.new(current.X, st.home.Y, current.Z)
		pickTarget(st)
		st.wasChasing = false
	end

	if not anyPlayerNear(st.home) then
		return
	end

	local style = st.style
	local pos = st.pos
	local bobY = 0

	if style == "Hover" then
		-- Sanftes Lissajous-Schweben + Auf/Ab.
		local t = elapsed + st.phase
		local ox = math.sin(t * 0.5) * st.rx
		local oz = math.cos(t * 0.37) * st.rz
		pos = Vector3.new(st.home.X + ox, st.home.Y, st.home.Z + oz)
		bobY = math.sin(t * 1.1) * st.bob
	elseif style == "Hop" then
		-- Langsames Driften + huepfender Bogen (nie unter die Plattform).
		local toT = st.target - Vector3.new(pos.X, st.home.Y, pos.Z)
		if toT.Magnitude < 1.5 then
			pickTarget(st)
		else
			local stepv = toT.Unit * math.min(st.speed * dt, toT.Magnitude)
			pos = Vector3.new(pos.X + stepv.X, st.home.Y, pos.Z + stepv.Z)
		end
		bobY = math.abs(math.sin((elapsed + st.phase) * 3.2)) * st.bob
	else
		-- Ground / Sway / Crawl: zwischen Zonen-Punkten laufen + leichtes Wippen.
		local flat = Vector3.new(pos.X, st.home.Y, pos.Z)
		local toT = st.target - flat
		if toT.Magnitude < 1.2 then
			pickTarget(st)
		else
			local stepv = toT.Unit * math.min(st.speed * dt, toT.Magnitude)
			pos = Vector3.new(pos.X + stepv.X, st.home.Y, pos.Z + stepv.Z)
		end
		bobY = math.sin((elapsed + st.phase) * 4.0) * st.bob
	end

	-- Hart auf die eigene Zone klemmen (Sicherheitsnetz gegen Ausbruch).
	local cx = math.clamp(pos.X, st.home.X - st.rx, st.home.X + st.rx)
	local cz = math.clamp(pos.Z, st.home.Z - st.rz, st.home.Z + st.rz)
	st.pos = Vector3.new(cx, st.home.Y, cz)

	-- Orientierung bewusst unveraendert (Augen/Details zeigen wie gebaut
	-- nach -Z zum Laufweg); nur Translation + Wippen -> keine Glitches.
	model:PivotTo(CFrame.new(cx, st.home.Y + bobY, cz))
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

	print(string.format("[EnemyMovementController] %d bewegliche Gegner registriert.", #states))
end

return EnemyMovementController
