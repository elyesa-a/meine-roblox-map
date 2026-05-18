--!strict
-- BorderService: setzt DNA-Borders und Labor-Luken serverseitig durch.
--
-- Gegner-Borders (Workspace.EnemyBorders) und Gates (Workspace.AreaGates)
-- sind nicht kollidierende Trigger-Waende. Beruehrt ein Spieler eine Wand,
-- ohne die Anforderung (DNA bzw. Rebirth) zu erfuellen, wird er ein paar
-- Studs zurueckgeschoben + bekommt ein Popup. Erfuellt er sie, darf er
-- passieren. Dieses Muster ist identisch zur bestehenden ZoneLockService-
-- Logik (kein per-Spieler-CanCollide moeglich).

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

local Modules = ReplicatedStorage:WaitForChild("Modules")
local NumberFormatter = require(Modules:WaitForChild("NumberFormatter"))

local BorderService = {}

local DataService
local lastBlock: { [Player]: number } = {}
local barrierGuards: { BasePart } = {}
local guardAccum = 0

local function findPlayerFromPart(part: BasePart): Player?
	local model = part:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end
	return Players:GetPlayerFromCharacter(model)
end

local function pushBack(player: Player, barrier: BasePart)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end
	-- Der Parcours laeuft entlang +X; vor der Wand = kleineres X.
	local backX = barrier.Position.X - 9
	local z = math.clamp(hrp.Position.Z, -55, 55)
	hrp.CFrame = CFrame.new(backX, barrier.Position.Y + 2, z)
end

local function getRequirements(barrier: BasePart): (number, number)
	local requiredDna = barrier:GetAttribute("RequiredDNA")
	local requiredRebirth = barrier:GetAttribute("RequiredRebirth")
	if type(requiredDna) ~= "number" then
		requiredDna = 0
	end
	if type(requiredRebirth) ~= "number" then
		requiredRebirth = 0
	end
	return requiredDna, requiredRebirth
end

local function hasAccess(profile, requiredDna: number, requiredRebirth: number): boolean
	return profile.Rebirths >= requiredRebirth and profile.DnaCoins >= requiredDna
end

local function blockPlayer(player: Player, profile, barrier: BasePart, requiredDna: number, requiredRebirth: number)
	local now = os.clock()
	local shouldNotify = not lastBlock[player] or now - lastBlock[player] >= 1.25
	if shouldNotify then
		lastBlock[player] = now
	end
	if profile.Rebirths < requiredRebirth then
		if shouldNotify then
			ShowPopup:FireClient(player, string.format("🔒 Requires Rebirth %d!", requiredRebirth))
		end
	else
		local missing = requiredDna - profile.DnaCoins
		if shouldNotify then
			ShowPopup:FireClient(player, string.format(
				"🔒 Need %s DNA to pass! (%s more)",
				NumberFormatter.format(requiredDna),
				NumberFormatter.format(missing)
			))
		end
	end
	pushBack(player, barrier)
end

local function onBarrierTouched(barrier: BasePart, otherPart: BasePart)
	local player = findPlayerFromPart(otherPart)
	if not player then
		return
	end

	local profile = DataService.getProfile(player)
	if not profile then
		return
	end

	local requiredDna, requiredRebirth = getRequirements(barrier)
	if not hasAccess(profile, requiredDna, requiredRebirth) then
		blockPlayer(player, profile, barrier, requiredDna, requiredRebirth)
	end
	-- Anforderung erfuellt -> Spieler darf ungehindert durchlaufen.
end

local function guardLockedAreas()
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = DataService.getProfile(player)
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not profile or not hrp then
			continue
		end
		for _, barrier in ipairs(barrierGuards) do
			if not barrier.Parent then
				continue
			end
			local requiredDna, requiredRebirth = getRequirements(barrier)
			if hrp.Position.X > barrier.Position.X + 6 and not hasAccess(profile, requiredDna, requiredRebirth) then
				blockPlayer(player, profile, barrier, requiredDna, requiredRebirth)
				break
			end
		end
	end
end

local function bindFolder(folderName: string)
	local folder = Workspace:FindFirstChild(folderName)
	if not folder then
		return
	end
	for _, desc in ipairs(folder:GetDescendants()) do
		if desc:IsA("BasePart") and desc:GetAttribute("RequiredDNA") ~= nil then
			table.insert(barrierGuards, desc)
			desc.Touched:Connect(function(other)
				onBarrierTouched(desc, other)
			end)
		end
	end
end

function BorderService.start(deps)
	DataService = deps.DataService

	bindFolder("EnemyBorders")
	bindFolder("AreaGates")
	table.sort(barrierGuards, function(a, b)
		return a.Position.X < b.Position.X
	end)

	RunService.Heartbeat:Connect(function(dt)
		guardAccum += dt
		if guardAccum < 0.5 then
			return
		end
		guardAccum = 0
		guardLockedAreas()
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastBlock[player] = nil
	end)
end

return BorderService
