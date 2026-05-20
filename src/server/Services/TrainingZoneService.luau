--!strict
-- TrainingZoneService: alle 1s pruefen, ob ein Spieler in einer Bett-Hitbox
-- steht und die Rebirth-Anforderung erfuellt. Wenn ja: addPower mit der
-- Bett-Rate (Multiplikatoren werden im StatService draufgerechnet).
--
-- Zusaetzlich wird der Zone-Multiplikator anhand der Standzone gesetzt,
-- damit auch Klicks in der hoeherwertigen Zone mehr Kraft geben.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local AreaConfig = require(Configs:WaitForChild("AreaConfig"))
local ZoneConfig = require(Configs:WaitForChild("ZoneConfig"))

local Modules = ReplicatedStorage:WaitForChild("Modules")
local VFX = require(Modules:WaitForChild("VFX"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestAutoTraining = Remotes:WaitForChild("RequestAutoTraining") :: RemoteEvent
local AutoTrainingState = Remotes:WaitForChild("AutoTrainingState") :: RemoteEvent
local AutoFightState = Remotes:WaitForChild("AutoFightState") :: RemoteEvent
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

local TrainingZoneService = {}

local DataService
local StatService
local AntiExploitService
local UpgradeService
local DailyQuestService
local TitleService

local trainingPulseCounter: { [Player]: number } = {}
local autoTrainingByPlayer: { [Player]: { enabled: boolean, token: number, target: Model? } } = {}

local AUTO_TRAIN_RECHECK_INTERVAL = 0.75

local function isInsidePart(part: BasePart, pos: Vector3): boolean
	local relative = part.CFrame:PointToObjectSpace(pos)
	local half = part.Size / 2
	return math.abs(relative.X) <= half.X
		and math.abs(relative.Y) <= half.Y
		and math.abs(relative.Z) <= half.Z
end

local function getActiveZone(pos: Vector3)
	-- Welche enabled Zone enthaelt die Position? StartZone ist Fallback.
	local fallback = ZoneConfig.getById("StartZone")
	for _, zone in ipairs(ZoneConfig) do
		if zone.enabled then
			local halfX = zone.size.X / 2
			local halfZ = zone.size.Z / 2
			if math.abs(pos.X - zone.center.X) <= halfX
				and math.abs(pos.Z - zone.center.Z) <= halfZ then
				return zone
			end
		end
	end
	return fallback
end

local function getCharacterRoot(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getCharacterHumanoid(player: Player): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid") :: Humanoid?
end

local function getAreaIndexFromBed(model: Model): number?
	local index = string.match(model.Name, "^Area(%d+)TrainingBed$")
	if not index then
		return nil
	end
	return tonumber(index)
end

local function getOrCreateTeleportPoint(model: Model, hitbox: BasePart): BasePart
	local point = model:FindFirstChild("AutoTrainingTeleportPoint") :: BasePart?
	if point and point:IsA("BasePart") then
		return point
	end

	point = Instance.new("Part")
	point.Name = "AutoTrainingTeleportPoint"
	point.Size = Vector3.new(2, 1, 2)
	point.Transparency = 1
	point.Anchored = true
	point.CanCollide = false
	point.CanTouch = false
	point.CanQuery = false
	point.CFrame = hitbox.CFrame + Vector3.new(0, 1, 0)
	point.Parent = model
	return point
end

local function getAutoTrainingState(player: Player)
	local state = autoTrainingByPlayer[player]
	if not state then
		state = { enabled = false, token = 0, target = nil }
		autoTrainingByPlayer[player] = state
	end
	return state
end

local function isAutoTrainingEnabled(player: Player, token: number): boolean
	local state = autoTrainingByPlayer[player]
	return state ~= nil
		and state.enabled
		and state.token == token
		and player.Parent ~= nil
		and player:GetAttribute("AutoTrainingEnabled") == true
end

local function getBestTrainingBed(player: Player): (Model?, BasePart?, BasePart?)
	local bedsFolder = Workspace:FindFirstChild("TrainingBeds")
	if not bedsFolder then
		return nil, nil, nil
	end

	local profile = DataService.getProfile(player)
	if not profile then
		return nil, nil, nil
	end

	local currentPower = profile.Power or 0
	local rebirths = profile.Rebirths or 0
	local bestModel: Model? = nil
	local bestHitbox: BasePart? = nil
	local bestTeleport: BasePart? = nil
	local bestPriority = -1
	local bestRequiredPower = -1

	for _, child in ipairs(bedsFolder:GetChildren()) do
		if not child:IsA("Model") then
			continue
		end
		local hitbox = child:FindFirstChild("Hitbox") :: BasePart?
		if not hitbox or not hitbox:IsA("BasePart") then
			continue
		end
		local areaIndex = getAreaIndexFromBed(child)
		if not areaIndex then
			continue
		end
		local area = AreaConfig.getByIndex(areaIndex)
		if not area then
			continue
		end
		local requiredRebirth = hitbox:GetAttribute("RequiredRebirth") or 0
		if type(requiredRebirth) ~= "number" then
			requiredRebirth = 0
		end
		if currentPower < area.requiredPower or rebirths < requiredRebirth then
			continue
		end
		if area.requiredPower > bestRequiredPower or (area.requiredPower == bestRequiredPower and areaIndex > bestPriority) then
			bestModel = child
			bestHitbox = hitbox
			bestTeleport = getOrCreateTeleportPoint(child, hitbox)
			bestRequiredPower = area.requiredPower
			bestPriority = areaIndex
		end
	end

	return bestModel, bestHitbox, bestTeleport
end

local function teleportToTraining(player: Player, point: BasePart, hitbox: BasePart)
	local hrp = getCharacterRoot(player)
	if not hrp then
		return
	end
	local look = hitbox.Position + Vector3.new(0, 0, -8)
	hrp.CFrame = CFrame.new(point.Position + Vector3.new(0, 1.5, 0), look)
end

local function stopAutoTraining(player: Player, message: string?)
	local state = getAutoTrainingState(player)
	state.enabled = false
	state.token += 1
	state.target = nil
	player:SetAttribute("AutoTrainingEnabled", false)
	AutoTrainingState:FireClient(player, false)
	if message and player.Parent then
		ShowPopup:FireClient(player, message)
	end
end

local function bindAutoTrainingAttributeSync(player: Player)
	player:GetAttributeChangedSignal("AutoTrainingEnabled"):Connect(function()
		local state = autoTrainingByPlayer[player]
		if player:GetAttribute("AutoTrainingEnabled") ~= true and state and state.enabled then
			stopAutoTraining(player)
		end
	end)
end

local function runAutoTrainingLoop(player: Player, token: number)
	task.spawn(function()
		while isAutoTrainingEnabled(player, token) do
			local humanoid = getCharacterHumanoid(player)
			if not humanoid or humanoid.Health <= 0 then
				stopAutoTraining(player)
				break
			end

			local model, hitbox, point = getBestTrainingBed(player)
			if not model or not hitbox or not point then
				stopAutoTraining(player, "No valid training area found")
				break
			end

			local state = getAutoTrainingState(player)
			local hrp = getCharacterRoot(player)
			if state.target ~= model or not hrp or not isInsidePart(hitbox, hrp.Position) then
				state.target = model
				teleportToTraining(player, point, hitbox)
				ShowPopup:FireClient(player, "Moving to best training area")
			end

			task.wait(AUTO_TRAIN_RECHECK_INTERVAL)
		end
	end)
end

local function setAutoTrainingEnabled(player: Player, enabled: boolean)
	local state = getAutoTrainingState(player)
	if enabled then
		if state.enabled then
			AutoTrainingState:FireClient(player, true)
			return
		end

		player:SetAttribute("AutoFightEnabled", false)
		AutoFightState:FireClient(player, false)
		player:SetAttribute("AutoTrainingEnabled", true)
		state.enabled = true
		state.token += 1
		state.target = nil
		AutoTrainingState:FireClient(player, true)
		ShowPopup:FireClient(player, "Auto Training enabled")
		runAutoTrainingLoop(player, state.token)
	else
		stopAutoTraining(player, "Auto Training disabled")
	end
end

local function tick()
	local bedsFolder = Workspace:FindFirstChild("TrainingBeds")
	if not bedsFolder then
		return
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then
			continue
		end

		-- Position-Sanity (warnt nur, blockiert nicht).
		AntiExploitService.isPositionSane(player, hrp.Position)

		local profile = DataService.getProfile(player)
		if not profile then
			continue
		end

		-- Zone-Multiplikator nur fuer Zonen gewaehren, die der Spieler
		-- mit aktueller Power + Rebirth gerade betreten darf.
		local zone = getActiveZone(hrp.Position)
		local progressPower = profile.Power or 0
		if zone and profile.Rebirths >= zone.requiredRebirth and progressPower >= zone.requiredPower then
			StatService.setZoneMultiplier(player, zone.zoneMultiplier)
			profile.ZonesReached = profile.ZonesReached or {}
			profile.ZonesReached[zone.id] = true
			if TitleService then
				TitleService.setZoneReached(player, zone.id)
			end
			if DailyQuestService then
				DailyQuestService.record(player, "ReachZone", 1, zone.id)
			end
		else
			StatService.setZoneMultiplier(player, 1)
		end

		-- Pruefen, ob Spieler in irgendeiner Bett-Hitbox steht.
		for _, model in ipairs(bedsFolder:GetChildren()) do
			local hitbox = model:FindFirstChild("Hitbox") :: BasePart?
			if hitbox and hitbox:IsA("BasePart") then
				local required = hitbox:GetAttribute("RequiredRebirth") or 0
				local rate = hitbox:GetAttribute("PowerPerSecond") or 0
				if type(required) == "number" and type(rate) == "number"
					and rate > 0
					and profile.Rebirths >= required
					and isInsidePart(hitbox, hrp.Position) then
					local speedMult = if UpgradeService
						then UpgradeService.getMultiplier(player, "TrainingSpeed")
						else 1
					StatService.addPower(player, rate * speedMult)
					if DailyQuestService then
						DailyQuestService.record(player, "Train", 1)
					end
					if TitleService then
						TitleService.addStat(player, "TrainTicks", 1)
					end
					-- VFX-Pulse alle 3 Ticks, sofern VFX nicht im Setting deaktiviert.
					local counter = (trainingPulseCounter[player] or 0) + 1
					trainingPulseCounter[player] = counter
					if counter % 3 == 0 and profile.Settings.VFX ~= false then
						VFX.spawnTrainingPulse(hitbox, Color3.fromRGB(120, 255, 160))
					end
					break
				end
			end
		end
	end
end

function TrainingZoneService.start(deps)
	DataService = deps.DataService
	StatService = deps.StatService
	AntiExploitService = deps.AntiExploitService
	UpgradeService = deps.UpgradeService
	DailyQuestService = deps.DailyQuestService
	TitleService = deps.TitleService

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		trainingPulseCounter[player] = nil
		autoTrainingByPlayer[player] = nil
		player:SetAttribute("AutoTrainingEnabled", false)
	end)

	AntiExploitService.safeBind(RequestAutoTraining, 2, function(player, enabled)
		setAutoTrainingEnabled(player, enabled == true)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		bindAutoTrainingAttributeSync(player)
	end
	Players.PlayerAdded:Connect(bindAutoTrainingAttributeSync)

	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(tick)
			if not ok then
				warn("[TrainingZoneService] Tick-Fehler: " .. tostring(err))
			end
		end
	end)
end

return TrainingZoneService
