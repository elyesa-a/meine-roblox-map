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
local ZoneConfig = require(Configs:WaitForChild("ZoneConfig"))

local Modules = ReplicatedStorage:WaitForChild("Modules")
local VFX = require(Modules:WaitForChild("VFX"))

local TrainingZoneService = {}

local DataService
local StatService
local AntiExploitService
local UpgradeService

local trainingPulseCounter: { [Player]: number } = {}

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
		-- serverseitig per Rebirth-Anforderung freigeschaltet hat.
		local zone = getActiveZone(hrp.Position)
		if zone and profile.Rebirths >= zone.requiredRebirth then
			StatService.setZoneMultiplier(player, zone.zoneMultiplier)
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

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		trainingPulseCounter[player] = nil
	end)

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
