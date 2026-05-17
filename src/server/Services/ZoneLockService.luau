--!strict
-- ZoneLockService: Portal-Touches pruefen Rebirth-Anforderung serverseitig.
-- Bei zu wenig Rebirth: Popup + Spieler wird zurueckgesetzt.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local ZoneConfig = require(Configs:WaitForChild("ZoneConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

local ZoneLockService = {}

local DataService
-- Pro Spieler ein "Cooldown" zwischen Portal-Triggers (verhindert Popup-Spam).
local lastTrigger: { [Player]: number } = {}

local function findPlayerFromPart(part: BasePart): Player?
	local char = part:FindFirstAncestorOfClass("Model")
	if not char then
		return nil
	end
	return Players:GetPlayerFromCharacter(char)
end

local function onPortalTouched(portal: BasePart, otherPart: BasePart)
	local player = findPlayerFromPart(otherPart)
	if not player then
		return
	end
	local now = os.clock()
	if lastTrigger[player] and now - lastTrigger[player] < 1.5 then
		return
	end
	lastTrigger[player] = now

	local zoneId = portal:GetAttribute("ZoneId")
	local requiredRebirth = portal:GetAttribute("RequiredRebirth") or 0
	local requiredPower = portal:GetAttribute("RequiredPower") or 0
	if type(requiredRebirth) ~= "number" then
		requiredRebirth = 0
	end
	if type(requiredPower) ~= "number" then
		requiredPower = 0
	end

	local profile = DataService.getProfile(player)
	if not profile then
		return
	end

	if profile.Rebirths < requiredRebirth then
		ShowPopup:FireClient(player, string.format("You need Rebirth %d!", requiredRebirth))
		-- Spieler zur StartZone zurueckwerfen, damit er nicht durchgehen kann.
		local startZone = ZoneConfig.getById("StartZone")
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp and startZone then
			hrp.CFrame = CFrame.new(startZone.center + Vector3.new(0, 5, 0))
		end
	elseif profile.Power < requiredPower then
		ShowPopup:FireClient(player, string.format("Not enough Power! Need %d more PWR", math.max(0, requiredPower - profile.Power)))
		local startZone = ZoneConfig.getById("StartZone")
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp and startZone then
			hrp.CFrame = CFrame.new(startZone.center + Vector3.new(0, 5, 0))
		end
	else
		-- Spieler hat Zugang -- Portal-Teleport ist optional. Wir schieben ihn
		-- einfach in die Zonenmitte, damit kein zweites Touch-Event in der
		-- Cooldown-Phase getriggert wird.
		local targetZone = ZoneConfig.getById(zoneId)
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp and targetZone then
			hrp.CFrame = CFrame.new(targetZone.center + Vector3.new(0, 5, 0))
			ShowPopup:FireClient(player, "New Area Unlocked!")
		end
	end
end

function ZoneLockService.start(deps)
	DataService = deps.DataService

	local portalsFolder = Workspace:WaitForChild("Portals")
	for _, portal in ipairs(portalsFolder:GetChildren()) do
		if portal:IsA("BasePart") then
			portal.Touched:Connect(function(otherPart)
				onPortalTouched(portal, otherPart)
			end)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		lastTrigger[player] = nil
	end)
end

return ZoneLockService
