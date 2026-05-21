--!strict
-- EggCatchConfig: one pet egg station per Area/Stage.
--
-- The station data mirrors PetConfig's stage eggs. EggCatchService binds these
-- world stations to the normal server-authoritative PetService hatch flow.

local PetConfig = require(script.Parent:WaitForChild("PetConfig"))

export type EggStationDef = {
	eggId: string,
	displayName: string,
	areaIndex: number,
	areaDisplayName: string,
	cost: number,
	color: Color3,
}

local EggCatchConfig = {}

EggCatchConfig.ForArea = {} :: { [number]: { EggStationDef } }

for _, egg in ipairs(PetConfig.getSortedEggs()) do
	EggCatchConfig.ForArea[egg.areaIndex] = {
		{
			eggId = egg.id,
			displayName = egg.displayName,
			areaIndex = egg.areaIndex,
			areaDisplayName = egg.areaDisplayName,
			cost = egg.cost,
			color = egg.color,
		},
	}
end

function EggCatchConfig.getForArea(areaIndex: number): { EggStationDef }
	return EggCatchConfig.ForArea[areaIndex] or {}
end

return EggCatchConfig
