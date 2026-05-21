--!strict
-- Spawns small walkable collectibles around zones and grants rewards server-side.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local ZoneConfig = require(Configs:WaitForChild("ZoneConfig"))
local CollectibleConfig = require(Configs:WaitForChild("CollectibleConfig"))
local RebirthConfig = require(Configs:WaitForChild("RebirthConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

local CollectibleService = {}

local DataService
local StatService
local DailyQuestService
local TitleService

local rng = Random.new()
local activeByZone: { [string]: number } = {}
local playerTouchCooldown: { [Player]: number } = {}
local folder: Folder
local COLLECTIBLES_ENABLED = false

local function makeFolder(): Folder
	local existing = Workspace:FindFirstChild("Collectibles")
	if existing and existing:IsA("Folder") then
		existing:ClearAllChildren()
		return existing
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "Collectibles"
	newFolder.Parent = Workspace
	return newFolder
end

local function findPlayer(part: BasePart): Player?
	local char = part:FindFirstAncestorOfClass("Model")
	if not char then
		return nil
	end
	return Players:GetPlayerFromCharacter(char)
end

local function randomPoint(zone): Vector3
	local x = rng:NextNumber(-zone.size.X * 0.38, zone.size.X * 0.38)
	local z = rng:NextNumber(-zone.size.Z * 0.3, zone.size.Z * 0.3)
	return Vector3.new(zone.center.X + x, 3.2, zone.center.Z + 86 + z)
end

local function hasZoneAccess(profile, zoneId: string): boolean
	local zone = ZoneConfig.getById(zoneId)
	if not zone or not zone.enabled then
		return false
	end
	local progressPower = profile.Power or 0
	return profile.Rebirths >= zone.requiredRebirth and progressPower >= zone.requiredPower
end

local function grant(player: Player, zoneId: string, def): boolean
	local profile = DataService.getProfile(player)
	if not profile then
		return false
	end
	if not hasZoneAccess(profile, zoneId) then
		return false
	end
	local zoneMult = CollectibleConfig.getZoneMultiplier(zoneId)
	local amount = math.floor(def.amount * zoneMult)

	if def.kind == "Dna" then
		local titleMult = if TitleService then TitleService.getBonusMultiplier(player, "Dna") else 1
		local granted = math.floor(amount * titleMult)
		profile.DnaCoins += granted
		if DailyQuestService then
			DailyQuestService.record(player, "CollectDna", granted)
		end
		ShowPopup:FireClient(player, "+" .. tostring(granted) .. " DNA")
	elseif def.kind == "Power" then
		StatService.addPower(player, amount)
		ShowPopup:FireClient(player, "+" .. tostring(amount) .. " Power")
	elseif def.kind == "Luck" then
		local titleMult = if TitleService then TitleService.getBonusMultiplier(player, "Luck") else 1
		local seconds = math.floor(amount * titleMult)
		local now = os.time()
		local existing = profile.ActiveBoosts.Luck2x
		profile.ActiveBoosts.Luck2x = if existing and existing > now then existing + seconds else now + seconds
		ShowPopup:FireClient(player, "+" .. tostring(seconds) .. "s Luck")
	elseif def.kind == "RebirthShard" then
		profile.RebirthShards = (profile.RebirthShards or 0) + 1
		if profile.RebirthShards >= CollectibleConfig.RebirthShardsPerRebirth and profile.Rebirths < RebirthConfig.MaxRebirth then
			profile.RebirthShards -= CollectibleConfig.RebirthShardsPerRebirth
			profile.Rebirths += 1
			ShowPopup:FireClient(player, "Rebirth Shards formed +1 Rebirth!")
		else
			ShowPopup:FireClient(player, "+1 Rebirth Shard")
		end
	end

	if TitleService then
		TitleService.evaluatePlayer(player)
	end
	StatService.broadcastProfile(player)
	StatService.playSound(player, "Reward")
	return true
end

local function spawnOne(zone)
	activeByZone[zone.id] = activeByZone[zone.id] or 0
	if activeByZone[zone.id] >= CollectibleConfig.MaxActivePerZone then
		return
	end

	local def = CollectibleConfig.roll(rng)
	local part = Instance.new("Part")
	part.Name = def.id
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = true
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(def.size, def.size, def.size)
	part.Position = randomPoint(zone)
	part.Color = def.color
	part.Material = Enum.Material.Neon
	part.Transparency = if def.kind == "RebirthShard" then 0.08 else 0.18
	part:SetAttribute("ZoneId", zone.id)
	part:SetAttribute("CollectibleId", def.id)
	part.Parent = folder

	local light = Instance.new("PointLight")
	light.Brightness = if def.kind == "RebirthShard" then 1.1 else 0.55
	light.Range = if def.kind == "RebirthShard" then 14 else 9
	light.Color = def.color
	light.Parent = part

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(120, 36)
	billboard.StudsOffset = Vector3.new(0, 3.4, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 28
	billboard.Parent = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = def.displayName
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.Parent = billboard

	activeByZone[zone.id] += 1

	local collected = false
	part.Touched:Connect(function(hit)
		if collected then
			return
		end
		local player = findPlayer(hit)
		if not player then
			return
		end
		local now = os.clock()
		if playerTouchCooldown[player] and now - playerTouchCooldown[player] < 0.3 then
			return
		end
		playerTouchCooldown[player] = now
		if not grant(player, zone.id, def) then
			return
		end
		collected = true
		part:Destroy()
		activeByZone[zone.id] = math.max(0, (activeByZone[zone.id] or 1) - 1)
		task.delay(def.respawnSec, function()
			spawnOne(zone)
		end)
	end)
end

function CollectibleService.start(deps)
	DataService = deps.DataService
	StatService = deps.StatService
	DailyQuestService = deps.DailyQuestService
	TitleService = deps.TitleService
	folder = makeFolder()

	if not COLLECTIBLES_ENABLED then
		activeByZone = {}
		return
	end

	for _, zone in ipairs(ZoneConfig) do
		if zone.enabled then
			for _ = 1, 2 do
				spawnOne(zone)
			end
		end
	end

	task.spawn(function()
		while true do
			task.wait(CollectibleConfig.SpawnIntervalSec)
			for _, zone in ipairs(ZoneConfig) do
				if zone.enabled then
					spawnOne(zone)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		playerTouchCooldown[player] = nil
	end)
end

return CollectibleService
