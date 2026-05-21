--!strict
-- BoostService: zeitlich begrenzte Multiplikatoren. Boosts koennen aktiv sein,
-- werden aber nicht mehr fuer DNA verkauft.
--
-- Datenmodell:
--   profile.ActiveBoosts = { [boostId] = expirationTimestamp (os.time) }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local BoostConfig = require(Configs:WaitForChild("BoostConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestBuyBoost = Remotes:WaitForChild("RequestBuyBoost") :: RemoteEvent
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

local BoostService = {}

local DataService
local StatService
local AntiExploitService

local function clearExpired(profile)
	local now = os.time()
	local removed = false
	for id, expiry in pairs(profile.ActiveBoosts) do
		if expiry <= now then
			profile.ActiveBoosts[id] = nil
			removed = true
		end
	end
	return removed
end

-- Liefert den aktiven Multiplikator fuer einen bestimmten "affects"-Typ
-- ("Power", "Dna", "Luck"). Mehrere Boosts werden multiplikativ kombiniert.
function BoostService.getMultiplier(player: Player, affects: string): number
	local profile = DataService.getProfile(player)
	if not profile then
		return 1
	end
	clearExpired(profile)
	local mult = 1
	for boostId, _expiry in pairs(profile.ActiveBoosts) do
		local def = BoostConfig.getById(boostId)
		if def and def.affects == affects then
			mult *= def.multiplier
		end
	end
	return mult
end

function BoostService.getRemainingSec(player: Player, boostId: string): number
	local profile = DataService.getProfile(player)
	if not profile then
		return 0
	end
	local expiry = profile.ActiveBoosts[boostId]
	if not expiry then
		return 0
	end
	return math.max(0, expiry - os.time())
end

function BoostService.buyBoost(player: Player, boostId: string)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local def = BoostConfig.getById(boostId)
	if not def then
		return
	end
	ShowPopup:FireClient(player, "Boost purchases are unavailable.")
end

function BoostService.start(deps)
	DataService = deps.DataService
	StatService = deps.StatService
	AntiExploitService = deps.AntiExploitService

	AntiExploitService.safeBind(RequestBuyBoost, 5, function(player, boostId)
		if type(boostId) ~= "string" then
			return
		end
		BoostService.buyBoost(player, boostId)
	end)

	-- Tick-Loop: alle 5s ablaufende Boosts aufraeumen und Clients updaten.
	task.spawn(function()
		while true do
			task.wait(5)
			for _, player in ipairs(Players:GetPlayers()) do
				local profile = DataService.getProfile(player)
				if profile and clearExpired(profile) then
					StatService.broadcastProfile(player)
				end
			end
		end
	end)
end

return BoostService
