--!strict
-- Gamepass-Definitionen. assetId = 0 bedeutet "noch nicht im Roblox-Marketplace
-- erstellt"; in dem Fall werden Pseudo-Kaeufe nur per Popup angekuendigt.
-- Trage hier echte AssetIds ein, sobald die Gamepasses bei Roblox angelegt sind.

export type GamepassDef = {
	id: string,
	displayName: string,
	robux: number,
	assetId: number,
	-- Effekt-Hooks: was passiert, wenn der Spieler diesen Pass besitzt.
	-- Werden vom GamepassService ausgewertet.
	effect: string, -- "AutoClicker" | "VipZone" | "GlitchPet" | "SpinPack"
}

local GamepassConfig = {}

GamepassConfig.Passes = {
	{ id = "SpinPack",    displayName = "5x SPINS",   robux = 9,   assetId = 0, effect = "SpinPack" },
	{ id = "VipZone",     displayName = "VIP ZONE",   robux = 39,  assetId = 0, effect = "VipZone" },
	{ id = "AutoClicker", displayName = "AUTO CLICKER", robux = 99,  assetId = 0, effect = "AutoClicker" },
	{ id = "GlitchPet",   displayName = "GLITCH PET", robux = 279, assetId = 0, effect = "GlitchPet" },
} :: { GamepassDef }

function GamepassConfig.getById(id: string): GamepassDef?
	for _, def in ipairs(GamepassConfig.Passes) do
		if def.id == id then
			return def
		end
	end
	return nil
end

function GamepassConfig.getByAssetId(assetId: number): GamepassDef?
	for _, def in ipairs(GamepassConfig.Passes) do
		if def.assetId ~= 0 and def.assetId == assetId then
			return def
		end
	end
	return nil
end

return GamepassConfig
