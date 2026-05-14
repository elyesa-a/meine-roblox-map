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

local store = DataStoreService:GetDataStore(STORE_NAME)

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

export type Profile = {
	Power: number,
	Rebirths: number,
	DnaCoins: number,
	Level: number,
	Pets: { [string]: any },
	EquippedPets: { string },
	Auras: { [string]: boolean },
	EquippedAura: string?,
	Upgrades: { [string]: number },
	ActiveBoosts: { [string]: number }, -- boostId -> expiration timestamp (os.time)
	DailyChest: DailyChestState,
	Spin: SpinState,
	Settings: Settings,
	-- Internes Flag, wird NICHT gespeichert (filtern wir vor dem Speichern).
	NotPersistent: boolean?,
}

local DataService = {}

local profiles: { [Player]: Profile } = {}

local function getDefaultProfile(): Profile
	return {
		Power = 0,
		Rebirths = 0,
		DnaCoins = 0,
		Level = 1,
		Pets = {},
		EquippedPets = {},
		Auras = {},
		EquippedAura = nil,
		Upgrades = {},
		ActiveBoosts = {},
		DailyChest = { LastClaim = 0, Streak = 0 },
		Spin = { LastFreeSpin = 0 },
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
	local key = keyFor(player)
	local data
	local lastErr
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return store:GetAsync(key)
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
end

local function saveProfile(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	if profile.NotPersistent then
		warn(string.format("[DataService] Skip Speichern fuer %s (NotPersistent).", player.Name))
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
		store:UpdateAsync(key, function()
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
