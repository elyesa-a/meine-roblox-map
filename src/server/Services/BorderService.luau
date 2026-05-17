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

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

local Modules = ReplicatedStorage:WaitForChild("Modules")
local NumberFormatter = require(Modules:WaitForChild("NumberFormatter"))

local BorderService = {}

local DataService
local lastBlock: { [Player]: number } = {}

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

local function onBarrierTouched(barrier: BasePart, otherPart: BasePart)
	local player = findPlayerFromPart(otherPart)
	if not player then
		return
	end
	local now = os.clock()
	if lastBlock[player] and now - lastBlock[player] < 1.25 then
		return
	end

	local profile = DataService.getProfile(player)
	if not profile then
		return
	end

	local requiredDna = barrier:GetAttribute("RequiredDNA")
	local requiredRebirth = barrier:GetAttribute("RequiredRebirth")
	if type(requiredDna) ~= "number" then
		requiredDna = 0
	end
	if type(requiredRebirth) ~= "number" then
		requiredRebirth = 0
	end

	if profile.Rebirths < requiredRebirth then
		lastBlock[player] = now
		ShowPopup:FireClient(player, string.format("🔒 Requires Rebirth %d!", requiredRebirth))
		pushBack(player, barrier)
	elseif profile.DnaCoins < requiredDna then
		lastBlock[player] = now
		local missing = requiredDna - profile.DnaCoins
		ShowPopup:FireClient(player, string.format(
			"🔒 Need %s DNA to pass! (%s more)",
			NumberFormatter.format(requiredDna),
			NumberFormatter.format(missing)
		))
		pushBack(player, barrier)
	end
	-- Anforderung erfuellt -> Spieler darf ungehindert durchlaufen.
end

local function bindFolder(folderName: string)
	local folder = Workspace:FindFirstChild(folderName)
	if not folder then
		return
	end
	for _, desc in ipairs(folder:GetDescendants()) do
		if desc:IsA("BasePart") and desc:GetAttribute("RequiredDNA") ~= nil then
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

	Players.PlayerRemoving:Connect(function(player)
		lastBlock[player] = nil
	end)
end

return BorderService
