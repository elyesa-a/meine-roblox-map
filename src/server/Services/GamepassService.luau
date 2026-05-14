--!strict
-- GamepassService: stellt fest, welche Gamepasses ein Spieler besitzt, und
-- aktiviert die jeweiligen Effekte (Auto-Klick, VIP-Zone-Zugang, etc.).
-- Hoert auf MarketplaceService:PromptGamePassPurchaseFinished und gewaehrt
-- One-Shot-Belohnungen wie das SpinPack.
--
-- Bei assetId = 0 (kein echter Roblox-Pass angelegt): Effekt wird nicht aktiv,
-- aber die Struktur ist bereits da. RequestPromptPurchase vom Client zeigt
-- dann nur einen Hinweis-Popup.
--
-- Datenmodell:
--   profile.OwnedGamepasses = { [gamepassId] = true }

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local GamepassConfig = require(Configs:WaitForChild("GamepassConfig"))
local SpinConfig = require(Configs:WaitForChild("SpinConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestPromptPurchase = Remotes:WaitForChild("RequestPromptPurchase") :: RemoteEvent
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

local GamepassService = {}

local DataService
local StatService
local SpinService
local AntiExploitService

-- Cache fuer ownsAsset-Lookups, damit nicht jede Frage einen API-Call macht.
local ownsCache: { [Player]: { [string]: boolean } } = {}

local function refreshOwnsCache(player: Player)
	local cache: { [string]: boolean } = {}
	for _, def in ipairs(GamepassConfig.Passes) do
		if def.assetId == 0 then
			cache[def.id] = false
			continue
		end
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.assetId)
		end)
		cache[def.id] = ok and owns or false
	end
	ownsCache[player] = cache
end

function GamepassService.owns(player: Player, gamepassId: string): boolean
	local cache = ownsCache[player]
	if cache then
		return cache[gamepassId] == true
	end
	-- Profile-Fallback (z.B. wenn refresh noch nicht durchgelaufen ist).
	local profile = DataService.getProfile(player)
	if profile and profile.OwnedGamepasses then
		return profile.OwnedGamepasses[gamepassId] == true
	end
	return false
end

-- VipZone gibt zusaetzlichen DNA-Multiplikator (x2). Wird von RebirthService
-- + StatService konsultiert.
function GamepassService.getDnaMultiplier(player: Player): number
	if GamepassService.owns(player, "VipZone") then
		return 2
	end
	return 1
end

-- One-Shot-Effekt nach erfolgreichem Kauf.
local function applyOneShotEffect(player: Player, def)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	if def.effect == "SpinPack" then
		-- 5 sofortige Free-Spins: Cooldown zuruecksetzen, dann 5 spins ausloesen.
		if SpinService then
			for i = 1, 5 do
				profile.Spin.LastFreeSpin = 0
				SpinService.spin(player)
				-- Jeder Spin setzt LastFreeSpin neu, also fuer den naechsten Loop wieder zuruecksetzen.
			end
			profile.Spin.LastFreeSpin = os.time()
		end
	end
	-- VipZone/AutoClicker/GlitchPet haben permanente Effekte ueber owns()-Check,
	-- die werden an anderer Stelle abgefragt (Zone-Lock, TrainingZone Auto-Click).
end

local function onPurchaseFinished(player: Player, assetId: number, success: boolean)
	if not success then
		return
	end
	local def = GamepassConfig.getByAssetId(assetId)
	if not def then
		return
	end
	local profile = DataService.getProfile(player)
	if profile then
		profile.OwnedGamepasses[def.id] = true
	end
	if ownsCache[player] then
		ownsCache[player][def.id] = true
	end
	applyOneShotEffect(player, def)
	ShowPopup:FireClient(player, string.format("%s freigeschaltet!", def.displayName))
	StatService.broadcastProfile(player)
end

function GamepassService.start(deps)
	DataService = deps.DataService
	StatService = deps.StatService
	SpinService = deps.SpinService
	AntiExploitService = deps.AntiExploitService

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPurchaseFinished)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			-- Warten bis Profil da ist (DataService laedt asynchron).
			local start = os.clock()
			while not DataService.getProfile(player) and os.clock() - start < 5 do
				task.wait(0.1)
			end
			refreshOwnsCache(player)
			-- Profile mit Cache syncen, damit OwnedGamepasses gespeichert wird.
			local profile = DataService.getProfile(player)
			if profile then
				for id, owns in pairs(ownsCache[player] or {}) do
					if owns then
						profile.OwnedGamepasses[id] = true
					end
				end
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		ownsCache[player] = nil
	end)

	-- Client bittet um Promp -> wir leiten an MarketplaceService weiter
	-- (oder zeigen einen Hinweis-Popup, wenn assetId 0 ist).
	AntiExploitService.safeBind(RequestPromptPurchase, 2, function(player, gamepassId)
		if type(gamepassId) ~= "string" then
			return
		end
		local def = GamepassConfig.getById(gamepassId)
		if not def then
			return
		end
		if def.assetId == 0 then
			ShowPopup:FireClient(player, string.format("%s -- bald verfuegbar!", def.displayName))
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, def.assetId)
	end)

	-- AutoClicker-Loop: 4x pro Sekunde +1 Klick fuer Besitzer.
	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, player in ipairs(Players:GetPlayers()) do
				if GamepassService.owns(player, "AutoClicker") then
					StatService.addPower(player, 1)
				end
			end
		end
	end)
end

return GamepassService
