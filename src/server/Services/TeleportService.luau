--!strict
-- TeleportService: server-authoritative area teleporting.
--
-- Unlock rule:
--   Area N is available when N <= HighestBossDefeated + 1.
--   HighestBossDefeated is advanced only by real boss defeats on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local AreaConfig = require(Configs:WaitForChild("AreaConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestTeleportArea = Remotes:WaitForChild("RequestTeleportArea") :: RemoteEvent
local AutoFightState = Remotes:WaitForChild("AutoFightState") :: RemoteEvent
local AutoTrainingState = Remotes:WaitForChild("AutoTrainingState") :: RemoteEvent
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

local TeleportService = {}

local DataService
local StatService
local AntiExploitService

local TELEPORT_COOLDOWN = 1.25
local lastTeleportAt: { [Player]: number } = {}

local function getCharacterRoot(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getCharacterHumanoid(player: Player): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid") :: Humanoid?
end

local function getSpawnFallback(): BasePart?
	local spawn = Workspace:FindFirstChild("LabSpawn", true)
	if spawn and spawn:IsA("BasePart") then
		return spawn
	end
	return nil
end

local function getTeleportPoint(areaNumber: number): BasePart?
	local folder = Workspace:FindFirstChild("TeleportPoints")
	if folder then
		local point = folder:FindFirstChild("TeleportPoint_Area" .. tostring(areaNumber))
		if point and point:IsA("BasePart") then
			return point
		end
	end

	if areaNumber == 1 then
		return getSpawnFallback()
	end

	local area = AreaConfig.getByIndex(areaNumber)
	if not area then
		return nil
	end

	local fallback = Instance.new("Part")
	fallback.Name = "RuntimeTeleportPoint_Area" .. tostring(areaNumber)
	fallback.Size = Vector3.new(2, 1, 2)
	fallback.Transparency = 1
	fallback.Anchored = true
	fallback.CanCollide = false
	fallback.CanTouch = false
	fallback.CanQuery = false
	fallback.CFrame = CFrame.new(area.hallCenterX + AreaConfig.Layout.GateOffsetX + 28, AreaConfig.Layout.FloorTopY + 4, 0)
	fallback.Parent = folder or Workspace
	return fallback
end

local function parseBossArea(bossId: string): number?
	local areaText = string.match(bossId, "^A(%d+)E10$")
	return areaText and tonumber(areaText) or nil
end

local function deriveHighestBossDefeated(profile): number
	local highest = if type(profile.HighestBossDefeated) == "number" then profile.HighestBossDefeated else 0
	if type(profile.BossDefeats) == "table" then
		for bossId, count in pairs(profile.BossDefeats) do
			if type(bossId) == "string" and type(count) == "number" and count > 0 then
				local areaNumber = parseBossArea(bossId)
				if areaNumber then
					highest = math.max(highest, areaNumber)
				end
			end
		end
	end
	return math.clamp(highest, 0, AreaConfig.count())
end

local function getHighestBossDefeated(player: Player): number
	local profile = DataService.getProfile(player)
	if not profile then
		return 0
	end
	local highest = deriveHighestBossDefeated(profile)
	if profile.HighestBossDefeated ~= highest then
		profile.HighestBossDefeated = highest
	end
	return highest
end

local function isAreaUnlocked(player: Player, areaNumber: number): boolean
	if areaNumber < 1 or areaNumber > AreaConfig.count() then
		return false
	end
	return areaNumber <= getHighestBossDefeated(player) + 1
end

local function getLockedMessage(areaNumber: number): string
	return "Locked: Beat Area " .. tostring(math.max(1, areaNumber - 1)) .. " Boss first."
end

local function stopAutomation(player: Player)
	if player:GetAttribute("AutoFightEnabled") == true then
		player:SetAttribute("AutoFightEnabled", false)
		AutoFightState:FireClient(player, false)
	end
	if player:GetAttribute("AutoTrainingEnabled") == true then
		player:SetAttribute("AutoTrainingEnabled", false)
		AutoTrainingState:FireClient(player, false)
	end
end

function TeleportService.recordBossDefeat(player: Player, areaNumber: number)
	local profile = DataService.getProfile(player)
	if not profile or areaNumber <= 0 then
		return
	end
	local previous = deriveHighestBossDefeated(profile)
	local nextHighest = math.max(previous, areaNumber)
	profile.HighestBossDefeated = nextHighest
	if nextHighest > previous and nextHighest < AreaConfig.count() then
		local unlockedArea = AreaConfig.getByIndex(nextHighest + 1)
		if unlockedArea then
			ShowPopup:FireClient(player, "Area " .. tostring(nextHighest + 1) .. " Unlocked!")
			task.delay(0.25, function()
				if player.Parent then
					ShowPopup:FireClient(player, "Teleport to " .. unlockedArea.displayName .. " is now available.")
				end
			end)
		end
	end
	if StatService then
		StatService.broadcastProfile(player)
	end
end

local function teleportPlayer(player: Player, areaNumber: number)
	local now = os.clock()
	local last = lastTeleportAt[player] or 0
	if now - last < TELEPORT_COOLDOWN then
		return
	end
	lastTeleportAt[player] = now

	local profile = DataService.getProfile(player)
	if not profile then
		return
	end

	if not isAreaUnlocked(player, areaNumber) then
		ShowPopup:FireClient(player, getLockedMessage(areaNumber))
		return
	end
	if player:GetAttribute("InCombat") == true then
		ShowPopup:FireClient(player, "Finish battle before teleporting.")
		return
	end

	local humanoid = getCharacterHumanoid(player)
	local hrp = getCharacterRoot(player)
	local point = getTeleportPoint(areaNumber)
	if not humanoid or humanoid.Health <= 0 or not hrp or not point then
		return
	end

	stopAutomation(player)
	local targetCFrame = point.CFrame + Vector3.new(0, 4, 0)
	hrp.CFrame = targetCFrame
	local area = AreaConfig.getByIndex(areaNumber)
	ShowPopup:FireClient(player, "Teleported to " .. (area and area.displayName or "Area " .. tostring(areaNumber)))
end

function TeleportService.start(deps)
	DataService = deps.DataService
	StatService = deps.StatService
	AntiExploitService = deps.AntiExploitService

	AntiExploitService.safeBind(RequestTeleportArea, 2, function(player, areaNumber)
		if type(areaNumber) ~= "number" then
			return
		end
		teleportPlayer(player, math.floor(areaNumber))
	end)

	Players.PlayerAdded:Connect(function(player)
		task.delay(1, function()
			if player.Parent and DataService.getProfile(player) then
				getHighestBossDefeated(player)
				StatService.broadcastProfile(player)
			end
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			if DataService.getProfile(player) then
				getHighestBossDefeated(player)
				StatService.broadcastProfile(player)
			end
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastTeleportAt[player] = nil
	end)
end

return TeleportService
