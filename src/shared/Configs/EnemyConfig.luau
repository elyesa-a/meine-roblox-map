--!strict
-- Phase A enemy and boss definitions.
-- Enemies use Power-only requirements. Rebirths are intentionally not used here.

export type EnemyDef = {
	Id: string,
	DisplayName: string,
	MaxHealth: number,
	RequiredPower: number,
	DNAReward: number,
	RespawnTime: number,
	AreaName: string,
	IsBoss: boolean,
}

local EnemyConfig = {}

EnemyConfig.AttackCooldownSec = 0.2
EnemyConfig.AttackDistance = 18
EnemyConfig.BossPromptDistance = 10

EnemyConfig.Enemies = {
	{ Id = "TinyAntibody", DisplayName = "Tiny Antibody", MaxHealth = 100, RequiredPower = 80, DNAReward = 5, RespawnTime = 8, AreaName = "StartEnemies", IsBoss = false },
	{ Id = "LabGerm", DisplayName = "Lab Germ", MaxHealth = 250, RequiredPower = 150, DNAReward = 10, RespawnTime = 8, AreaName = "StartEnemies", IsBoss = false },
	{ Id = "MiniCellGuard", DisplayName = "Mini Cell Guard", MaxHealth = 500, RequiredPower = 300, DNAReward = 20, RespawnTime = 10, AreaName = "StartEnemies", IsBoss = false },
	{ Id = "WeakCureBot", DisplayName = "Weak Cure Bot", MaxHealth = 1000, RequiredPower = 700, DNAReward = 35, RespawnTime = 12, AreaName = "StartEnemies", IsBoss = false },

	{ Id = "AntibodySoldier", DisplayName = "Antibody Soldier", MaxHealth = 2500, RequiredPower = 1500, DNAReward = 60, RespawnTime = 12, AreaName = "HospitalEnemies", IsBoss = false },
	{ Id = "WhiteCellGuard", DisplayName = "White Cell Guard", MaxHealth = 5000, RequiredPower = 3000, DNAReward = 90, RespawnTime = 14, AreaName = "HospitalEnemies", IsBoss = false },
	{ Id = "CleanseDrone", DisplayName = "Cleanse Drone", MaxHealth = 10000, RequiredPower = 7000, DNAReward = 150, RespawnTime = 16, AreaName = "HospitalEnemies", IsBoss = false },
	{ Id = "HospitalDefender", DisplayName = "Hospital Defender", MaxHealth = 25000, RequiredPower = 15000, DNAReward = 250, RespawnTime = 18, AreaName = "HospitalEnemies", IsBoss = false },

	{ Id = "DNAMutant", DisplayName = "DNA Mutant", MaxHealth = 50000, RequiredPower = 30000, DNAReward = 400, RespawnTime = 20, AreaName = "MutationEnemies", IsBoss = false },
	{ Id = "MutationBeast", DisplayName = "Mutation Beast", MaxHealth = 100000, RequiredPower = 70000, DNAReward = 700, RespawnTime = 22, AreaName = "MutationEnemies", IsBoss = false },
	{ Id = "ToxicCell", DisplayName = "Toxic Cell", MaxHealth = 250000, RequiredPower = 150000, DNAReward = 1200, RespawnTime = 25, AreaName = "MutationEnemies", IsBoss = false },
	{ Id = "DNAGuardian", DisplayName = "DNA Guardian", MaxHealth = 500000, RequiredPower = 300000, DNAReward = 2000, RespawnTime = 30, AreaName = "MutationEnemies", IsBoss = false },

	{ Id = "QuarantineBot", DisplayName = "Quarantine Bot", MaxHealth = 1000000, RequiredPower = 700000, DNAReward = 3500, RespawnTime = 35, AreaName = "QuarantineEnemies", IsBoss = false },
	{ Id = "RedAlertGuard", DisplayName = "Red Alert Guard", MaxHealth = 2500000, RequiredPower = 1500000, DNAReward = 6000, RespawnTime = 40, AreaName = "QuarantineEnemies", IsBoss = false },
	{ Id = "SterileTitan", DisplayName = "Sterile Titan", MaxHealth = 5000000, RequiredPower = 3000000, DNAReward = 10000, RespawnTime = 45, AreaName = "QuarantineEnemies", IsBoss = false },
	{ Id = "LockdownBoss", DisplayName = "Lockdown Boss", MaxHealth = 10000000, RequiredPower = 6000000, DNAReward = 18000, RespawnTime = 60, AreaName = "QuarantineBoss", IsBoss = true },

	{ Id = "GlitchHunter", DisplayName = "Glitch Hunter", MaxHealth = 25000000, RequiredPower = 15000000, DNAReward = 35000, RespawnTime = 60, AreaName = "GlitchEnemies", IsBoss = false },
	{ Id = "FirewallBeast", DisplayName = "Firewall Beast", MaxHealth = 50000000, RequiredPower = 30000000, DNAReward = 60000, RespawnTime = 75, AreaName = "GlitchEnemies", IsBoss = false },
	{ Id = "AntiVirusCore", DisplayName = "Anti-Virus Core", MaxHealth = 100000000, RequiredPower = 60000000, DNAReward = 100000, RespawnTime = 90, AreaName = "GlitchBoss", IsBoss = true },
	{ Id = "CoreSentry", DisplayName = "Core Sentry", MaxHealth = 150000000, RequiredPower = 90000000, DNAReward = 150000, RespawnTime = 90, AreaName = "EndgameEnemies", IsBoss = false },
	{ Id = "OmegaCellGuard", DisplayName = "Omega Cell Guard", MaxHealth = 250000000, RequiredPower = 140000000, DNAReward = 250000, RespawnTime = 100, AreaName = "EndgameEnemies", IsBoss = false },
	{ Id = "FinalCoreBeast", DisplayName = "Final Core Beast", MaxHealth = 350000000, RequiredPower = 200000000, DNAReward = 350000, RespawnTime = 110, AreaName = "EndgameEnemies", IsBoss = false },
	{ Id = "OmegaImmuneBoss", DisplayName = "Omega Immune Boss", MaxHealth = 500000000, RequiredPower = 250000000, DNAReward = 500000, RespawnTime = 120, AreaName = "EndgameBoss", IsBoss = true },

	-- Boss-field Phase A entries for early progression arenas.
	{ Id = "MiniAntibodyKing", DisplayName = "Mini Antibody King", MaxHealth = 3000, RequiredPower = 1000, DNAReward = 100, RespawnTime = 30, AreaName = "StartBoss", IsBoss = true },
	{ Id = "WhiteCellTitan", DisplayName = "White Cell Titan", MaxHealth = 30000, RequiredPower = 15000, DNAReward = 500, RespawnTime = 45, AreaName = "HospitalBoss", IsBoss = true },
	{ Id = "DNAGuardianBoss", DisplayName = "DNA Guardian Boss", MaxHealth = 650000, RequiredPower = 300000, DNAReward = 2500, RespawnTime = 60, AreaName = "MutationBoss", IsBoss = true },
}

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
