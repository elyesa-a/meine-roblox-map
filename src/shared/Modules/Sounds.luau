--!strict
-- Zentrale Liste aller Sound-AssetIds. Werden vom SoundController (Client)
-- als SoundInstanzen gespiegelt. Server kann ueber PlaySound:FireClient(...)
-- den Client-Sound abspielen. Musik-Loop laeuft client-only.
--
-- WICHTIG: Standardmaessig sind alle IDs leer ("0"). Roblox spielt fremde
-- Sound-Assets oft nicht ab (HTTP 403). Trage hier deine eigenen, in dein
-- Spiel hochgeladenen AssetIds ein (rbxassetid://<DEINE_ID>). Leere Eintraege
-- werden vom SoundController einfach ignoriert -- das Spiel laeuft sauber
-- weiter, nur ohne Sound.

local Sounds = {}

-- Kategorie -> SoundGroup-Name. Wird im SoundController als SoundGroup-
-- Instanz angelegt und an Sound.SoundGroup gehaengt -- so wirkt der globale
-- Music/SFX-Toggle.
Sounds.Groups = {
	Music = "MusicGroup",
	SFX = "SFXGroup",
	UI = "UIGroup",
}

-- Sobald du echte Sounds hast: ersetze "0" durch "rbxassetid://<DEINE_ID>".
Sounds.Sounds = {
	UIClick = { id = "0", group = "UI", volume = 0.4 },
	UIOpen = { id = "0", group = "UI", volume = 0.5 },
	UIClose = { id = "0", group = "UI", volume = 0.4 },

	Click = { id = "0", group = "SFX", volume = 0.3 },
	Purchase = { id = "0", group = "SFX", volume = 0.6 },
	LevelUp = { id = "0", group = "SFX", volume = 0.7 },
	Rebirth = { id = "0", group = "SFX", volume = 0.8 },
	Spin = { id = "0", group = "SFX", volume = 0.7 },
	Reward = { id = "0", group = "SFX", volume = 0.6 },

	BgMusic = { id = "0", group = "Music", volume = 0.25 },
}

return Sounds
