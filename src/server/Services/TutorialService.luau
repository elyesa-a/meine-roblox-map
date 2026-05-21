--!strict
-- TutorialService: serverseitige Persistenz und sichere Tutorial-Aktionen.
-- Das eigentliche Story-UI laeuft clientseitig; dieser Service speichert nur
-- Abschluss/Skip, vergibt die kleine Abschlussbelohnung und leitet echte
-- Gameplay-Fortschritte an den Client weiter.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestTutorialAction = Remotes:WaitForChild("RequestTutorialAction") :: RemoteEvent
local TutorialProgress = Remotes:WaitForChild("TutorialProgress") :: RemoteEvent
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

local TutorialService = {}

local DataService
local StatService
local AntiExploitService

local COMPLETE_DNA_REWARD = 250
local COMPLETE_POWER_REWARD = 25

local function getProfile(player: Player)
	return DataService and DataService.getProfile(player)
end

local function markFinished(player: Player, completed: boolean)
	local profile = getProfile(player)
	if not profile or profile.HasCompletedTutorial == true then
		return
	end

	profile.HasCompletedTutorial = true
	if completed then
		profile.DnaCoins = math.floor((profile.DnaCoins or 0) + COMPLETE_DNA_REWARD)
		if StatService then
			StatService.addPowerReward(player, COMPLETE_POWER_REWARD)
		end
		ShowPopup:FireClient(player, string.format("Tutorial complete! +%d DNA, +%d Power", COMPLETE_DNA_REWARD, COMPLETE_POWER_REWARD))
	else
		ShowPopup:FireClient(player, "Tutorial skipped")
	end

	if StatService then
		StatService.broadcastProfile(player)
	end
end

function TutorialService.record(player: Player, eventName: string, payload: { [string]: any }?)
	local profile = getProfile(player)
	if not profile or profile.HasCompletedTutorial == true then
		return
	end
	local data = payload or {}
	data.Event = eventName
	TutorialProgress:FireClient(player, data)
end

function TutorialService.start(deps: {
	DataService: any,
	StatService: any,
	AntiExploitService: any,
})
	DataService = deps.DataService
	StatService = deps.StatService
	AntiExploitService = deps.AntiExploitService

	AntiExploitService.safeBind(RequestTutorialAction, 2, function(player, action)
		if action == "Complete" then
			markFinished(player, true)
		elseif action == "Skip" then
			markFinished(player, false)
		end
	end)

	Players.PlayerRemoving:Connect(function(_player)
		-- No per-player runtime state at the moment.
	end)
end

return TutorialService
