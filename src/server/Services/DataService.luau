--!strict
-- DataService: laedt & speichert Spielerprofile via DataStoreService.
--
-- Robustheit:
--  * pcall um alle GetAsync/UpdateAsync-Aufrufe.
--  * Bis zu 3 Retries mit Backoff beim Laden.
--  * Wenn das Laden komplett scheitert: Profil wird mit Defaults gefuellt und
--    "NotPersistent" markiert -- in dem Fall wird NICHT gespeichert, damit
--    ein temporaerer DataStore-Ausfall keine echten Daten ueberschreibt.
--  * Auto-Save alle 60s pro Spieler.
--  * PlayerRemoving und BindToClose speichern hart.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local STORE_NAME = "VirusEvo_v1"
local AUTOSAVE_INTERVAL = 60

-- DataStore-Zugriff ist in nicht-veroeffentlichten Studio-Spielen blockiert.
-- Wir holen den Store deshalb defensiv: pcall + nil-Fallback. Wenn store == nil,
-- laufen Profile rein im Speicher (NotPersistent).
local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStore nicht verfuegbar (vermutlich Studio ohne Publish). Profile laufen nur im Speicher. Grund: " .. tostring(result))
	end
end

export type Settings = {
	Music: boolean,
	SFX: boolean,
	VFX: boolean,
	Haptik: boolean,
}

export type DailyChestState = {
	LastClaim: number,
	Streak: number,
}

export type SpinState = {
	LastFreeSpin: number,
}

export type DailyQuestEntry = {
	Id: string,
	Progress: number,
	Claimed: boolean,
}

export type DailyQuestState = {
	LastResetDay: number,
	CompletedCount: number,
	Streak: number,
	QuestTokens: number,
	Quests: { DailyQuestEntry },
}

export type Profile = {
	Power: number,
	HighestPower: number,
	Rebirths: number,
	RebirthShards: number,
	DnaCoins: number,
	Level: number,
	Pets: { [string]: any },
	EquippedPets: { string },
	Auras: { [string]: boolean },
	EquippedAura: string?,
	Upgrades: { [string]: number },
	ActiveBoosts: { [string]: number }, -- boostId -> expiration timestamp (os.time)
	DailyChest: DailyChestState,
	DailyQuests: DailyQuestState,
	Spin: SpinState,
	Titles: { [string]: boolean },
	EquippedTitle: string?,
	TitleStats: { [string]: number },
	BossDefeats: { [string]: number },
	HighestBossDefeated: number,
	HasCompletedTutorial: boolean,
	ZonesReached: { [string]: boolean },
	OwnedGamepasses: { [string]: boolean },
	Settings: Settings,
	-- Internes Flag, wird NICHT gespeichert (filtern wir vor dem Speichern).
	NotPersistent: boolean?,
}

local DataService = {}

local profiles: { [Player]: Profile } = {}

local function getDefaultProfile(): Profile
	return {
		Power = 0,
		HighestPower = 0,
		Rebirths = 0,
		RebirthShards = 0,
		DnaCoins = 0,
		Level = 1,
		Pets = {},
		EquippedPets = {},
		Auras = {},
		EquippedAura = nil,
		Upgrades = {},
		ActiveBoosts = {},
		DailyChest = { LastClaim = 0, Streak = 0 },
		DailyQuests = { LastResetDay = 0, CompletedCount = 0, Streak = 0, QuestTokens = 0, Quests = {} },
		Spin = { LastFreeSpin = 0 },
		Titles = { Rookie = true },
		EquippedTitle = "Rookie",
		TitleStats = {},
		BossDefeats = {},
		HighestBossDefeated = 0,
		HasCompletedTutorial = false,
		ZonesReached = {},
		OwnedGamepasses = {},
		Settings = {
			Music = true,
			SFX = true,
			VFX = true,
			Haptik = true,
		},
	}
end

local function deepMerge(base: { [any]: any }, override: { [any]: any }): { [any]: any }
	-- Stellt sicher, dass neu hinzugefuegte Felder in spaeteren Versionen
	-- nicht NIL sind, indem fehlende Keys aus dem Default ergaenzt werden.
	for k, v in pairs(base) do
		if override[k] == nil then
			override[k] = v
		elseif type(v) == "table" and type(override[k]) == "table" then
			deepMerge(v, override[k])
		end
	end
	return override
end

local function keyFor(player: Player): string
	return "player_" .. tostring(player.UserId)
end

local function loadProfile(player: Player)
	-- Kein DataStore verfuegbar (Studio ohne Publish) -> Default-Profil in-memory.
	if store == nil then
		local profile = getDefaultProfile()
		profile.NotPersistent = true
		profile.HighestPower = math.max(profile.HighestPower or 0, profile.Power or 0)
		profiles[player] = profile
		print(string.format("[DataService] Studio-Modus: Default-Profil fuer %s im Speicher.", player.Name))
		return
	end

	local key = keyFor(player)
	local data
	local lastErr
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return (store :: DataStore):GetAsync(key)
		end)
		if ok then
			data = result
			lastErr = nil
			break
		else
			lastErr = result
			task.wait(0.5 * attempt)
		end
	end

	local profile: Profile
	if lastErr then
		warn(
			string.format("[DataService] Konnte Profil von %s nicht laden (%s). Verwende temporaeres Default-Profil ohne Speicherung.",
				player.Name, tostring(lastErr))
		)
		profile = getDefaultProfile()
		profile.NotPersistent = true
	elseif data == nil then
		print(string.format("[DataService] Neues Profil fuer %s erstellt.", player.Name))
		profile = getDefaultProfile()
	else
		profile = deepMerge(getDefaultProfile(), data) :: Profile
		print(string.format("[DataService] Profil fuer %s geladen.", player.Name))
	end

	profiles[player] = profile
	profile.HighestPower = math.max(profile.HighestPower or 0, profile.Power or 0)
end

local function saveProfile(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	if profile.NotPersistent or store == nil then
		return
	end

	-- Eine Kopie ohne interne Felder erstellen.
	local toSave = {}
	for k, v in pairs(profile) do
		if k ~= "NotPersistent" then
			toSave[k] = v
		end
	end

	local key = keyFor(player)
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key, function()
			return toSave
		end)
	end)
	if not ok then
		warn(string.format("[DataService] Speichern fuer %s fehlgeschlagen: %s", player.Name, tostring(err)))
	end
end

function DataService.getProfile(player: Player): Profile?
	return profiles[player]
end

function DataService.setField(player: Player, key: string, value: any)
	local profile = profiles[player]
	if profile then
		(profile :: any)[key] = value
	end
end

function DataService.start()
	Players.PlayerAdded:Connect(loadProfile)
	Players.PlayerRemoving:Connect(function(player)
		saveProfile(player)
		profiles[player] = nil
	end)

	-- Spieler, die bereits drin sind (z.B. bei Studio-Reload):
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(loadProfile, p)
	end

	-- Auto-Save-Schleife.
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player, _ in pairs(profiles) do
				if player.Parent then
					saveProfile(player)
				end
			end
		end
	end)

	game:BindToClose(function()
		-- Im Studio ist BindToClose oft sofortig, in Live-Games haben wir ~30s.
		if RunService:IsStudio() then
			for _, player in ipairs(Players:GetPlayers()) do
				saveProfile(player)
			end
			return
		end
		local pending = 0
		for _, player in ipairs(Players:GetPlayers()) do
			pending += 1
			task.spawn(function()
				saveProfile(player)
				pending -= 1
			end)
		end
		local start = os.clock()
		while pending > 0 and os.clock() - start < 25 do
			task.wait(0.2)
		end
	end)
end

return DataService
