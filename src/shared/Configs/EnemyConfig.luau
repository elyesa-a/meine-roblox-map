--!strict
-- EnemyConfig: 100 Gegner, datenbasiert erzeugt (10 Areale x 10 Gegner).
--
-- Scaling-Formel (Vorgabe): jeder naechste Gegner ist 4x staerker.
--   Health   = 100 * 4^(globalIndex-1)
--   Strength = 10  * 4^(globalIndex-1)
--   DNADrop  = 10  * 4^(globalIndex-1)
-- Werte werden intern als echte Zahlen gehalten und nur auf Labels per
-- NumberFormatter abgekuerzt (K, M, B, T, Qa, Qi, ... Dc).
--
-- RequiredPower bleibt bewusst eine MILDE Kurve (nicht *4), weil der
-- bestehende EnemyService Angriffe ueber RequiredPower freischaltet. Die
-- spec-konforme Progression laeuft ueber die DNA-Borders (siehe RequiredDNA
-- + BorderService). So bleibt das bestehende Kampf-System spielbar.
--
-- Oeffentliche API (unveraendert, damit EnemyService weiterlaeuft):
--   EnemyConfig.Enemies           -> { EnemyDef }
--   EnemyConfig.getById(id)       -> EnemyDef?
--   EnemyConfig.getByArea(name)   -> { EnemyDef }
--   EnemyConfig.AttackCooldownSec / AttackDistance / BossPromptDistance

local AreaConfig = require(script.Parent:WaitForChild("AreaConfig"))

export type EnemyDef = {
	Id: string,
	DisplayName: string,
	MaxHealth: number,
	Strength: number,
	RequiredPower: number,
	DNAReward: number,
	-- DNA, die der Spieler besitzen muss, um die Border VOR diesem Gegner
	-- zu passieren (0 = frei, kein Border davor).
	RequiredDNA: number,
	RespawnTime: number,
	AreaName: string, -- = AreaConfig id (z.B. "Area1")
	AreaIndex: number, -- 1..10
	EnemyIndex: number, -- 1..10 innerhalb der Area
	GlobalIndex: number, -- 1..100
	Shape: string, -- Form-Hinweis fuer den Builder (Optik-Variation)
	IsBoss: boolean,
}

local EnemyConfig = {}

EnemyConfig.AttackCooldownSec = 0.2
EnemyConfig.AttackDistance = 18
EnemyConfig.BossPromptDistance = 10
EnemyConfig.BattlePromptDistance = 10
EnemyConfig.BattleLeashDistance = 36
EnemyConfig.EnemyAttackCooldownSec = 1.6
EnemyConfig.EnemyAttackDamageBase = 3
EnemyConfig.EnemyAttackDamagePerArea = 1
EnemyConfig.EnemyBossDamageMultiplier = 1.5

-- 9 Namen pro Area (Gegner 1..9). Gegner 10 = Boss (AreaConfig.bossName).
local areaEnemyNames = {
	{ "Petri Microbe", "Lab Germ", "Splitting Cell", "Sticky Spore", "Twin Bacteria", "Acid Microbe", "Gut Flora", "Rod Bacillus", "Coccus Cluster" },
	{ "Pale Host Cell", "Swollen Cell", "Burst Membrane", "Lysed Cell", "Infected Plasma", "Necrotic Cell", "Fever Cell", "Blistered Cell", "Rupturing Cell" },
	{ "Splice Error", "Twisted Gene", "Mutagen Blob", "Helix Crawler", "Code Glitch Cell", "Forked Strand", "Warped Nucleus", "Recombinant", "Aberrant Clone" },
	{ "Leaking Drum", "Sludge Crawler", "Caustic Slime", "Hazmat Leech", "Solvent Worm", "Corrosive Glob", "Spill Creeper", "Acid Pooler", "Barrel Lurker" },
	{ "Spike Virion", "Capsid Drone", "Envelope Phage", "RNA Stinger", "Budding Virus", "Lytic Phage", "Latent Carrier", "Swarm Virion", "Replicant Phage" },
	{ "Rogue Sample", "Server Blight", "Faulty Centrifuge", "Broken Incubator", "Tainted Reagent", "Static Specimen", "Glitched Vial", "Corrupt Culture", "Rusted Servo" },
	{ "Reactor Spore", "Containment Breach", "Plasma Pathogen", "Core Mutagen", "Hazard Sentinel", "Meltdown Cell", "Fission Microbe", "Radiant Phage", "Burning Pathogen" },
	{ "Shadow Strand", "Void Mutant", "Black Helix", "Umbral Cell", "Night Pathogen", "Dusk Mutant", "Eclipse Spore", "Abyss Crawler", "Dark Splicer" },
	{ "Omega Spore", "Prime Mutant", "Alpha Virion", "Sigma Pathogen", "Apex Strain", "Hyper Phage", "Titan Microbe", "Overcharged Cell", "Doom Vector" },
	{ "Sealed Horror", "Last Specimen", "Containment Wraith", "Final Strain", "Vault Mutant", "Endgame Phage", "Terminal Virus", "Lockdown Beast", "Ground Zero Cell" },
}

local enemyShapes = { "Blob", "Crawler", "Drone", "Slime", "Spiky", "Brute" }

local BASE_HEALTH = 100
local BASE_STRENGTH = 10
local BASE_DNA = 10

local function buildEnemies(): { EnemyDef }
	local list: { EnemyDef } = {}
	local areaCount = AreaConfig.count()
	local perArea = AreaConfig.Layout.EnemiesPerArea

	for areaIndex = 1, areaCount do
		local area = AreaConfig.getByIndex(areaIndex)
		if not area then
			continue
		end
		for enemyIndex = 1, perArea do
			local globalIndex = (areaIndex - 1) * perArea + enemyIndex
			-- *4 Scaling: Faktor 4^(globalIndex-1).
			local factor = 4 ^ (globalIndex - 1)
			local isBoss = (enemyIndex == perArea)

			local maxHealth = BASE_HEALTH * factor
			local strength = BASE_STRENGTH * factor
			local dnaReward = BASE_DNA * factor

			-- Milde Power-Kurve nur pro Area (DNA-Borders sind das eigentliche
			-- Progressions-Gate). Boss minimal hoeher.
			local requiredPower = math.floor(50 * (3.2 ^ (areaIndex - 1)))
			if isBoss then
				requiredPower = math.floor(requiredPower * 1.4)
			end

			-- Border VOR diesem Gegner verlangt dessen eigenen DNA-Drop.
			-- Erster Gegner von Area 1 ist frei (Vorgabe: "Required: 0 DNA").
			local requiredDna = dnaReward
			if globalIndex == 1 then
				requiredDna = 0
			end

			local displayName: string
			if isBoss then
				displayName = area.bossName
			else
				displayName = areaEnemyNames[areaIndex][enemyIndex]
			end

			local shape = if isBoss
				then "Boss"
				else enemyShapes[((enemyIndex - 1) % #enemyShapes) + 1]

			table.insert(list, {
				Id = string.format("A%dE%d", areaIndex, enemyIndex),
				DisplayName = displayName,
				MaxHealth = maxHealth,
				Strength = strength,
				RequiredPower = requiredPower,
				DNAReward = dnaReward,
				RequiredDNA = requiredDna,
				RespawnTime = if isBoss then 28 + areaIndex * 3 else 7 + areaIndex,
				AreaName = area.id,
				AreaIndex = areaIndex,
				EnemyIndex = enemyIndex,
				GlobalIndex = globalIndex,
				Shape = shape,
				IsBoss = isBoss,
			})
		end
	end

	return list
end

EnemyConfig.Enemies = buildEnemies()

local byId: { [string]: EnemyDef } = {}
local byArea: { [string]: { EnemyDef } } = {}

for _, def in ipairs(EnemyConfig.Enemies) do
	byId[def.Id] = def
	if not byArea[def.AreaName] then
		byArea[def.AreaName] = {}
	end
	table.insert(byArea[def.AreaName], def)
end

function EnemyConfig.getById(id: string): EnemyDef?
	return byId[id]
end

function EnemyConfig.getByArea(areaName: string): { EnemyDef }
	return byArea[areaName] or {}
end

return EnemyConfig
