--!strict
-- EggCatchService: binds world egg stations to the normal pet egg shop.
--
-- The old Common/Rare/Epic station split is gone. Each Area/Stage station
-- opens exactly one PetConfig stage egg, and PetService performs all hatch
-- validation, weighted rolls, inventory writes, and DNA deduction.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local PetConfig = require(Configs:WaitForChild("PetConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

local EggCatchService = {}

local PetService

local function findEggModel(instance: Instance): Model?
	local current: Instance? = instance
	while current do
		if current:IsA("Model")
			and current:GetAttribute("AreaIndex") ~= nil
			and (current:GetAttribute("EggId") ~= nil or current:GetAttribute("EggTier") ~= nil) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function eggContextForStation(instance: Instance): { [string]: any }?
	local model = findEggModel(instance)
	if not model then
		return nil
	end

	local areaIndex = model:GetAttribute("AreaIndex")
	local eggId = model:GetAttribute("EggId")
	if type(areaIndex) ~= "number" then
		return nil
	end
	if type(eggId) ~= "string" then
		local legacyTier = model:GetAttribute("EggTier")
		eggId = PetConfig.getEggId(areaIndex, if type(legacyTier) == "string" then legacyTier else nil)
	end

	local egg = PetConfig.getEggById(eggId)
	if not egg then
		return nil
	end

	return {
		station = model,
		areaIndex = egg.areaIndex,
		eggId = egg.id,
		eggName = egg.displayName,
	}
end

local function openStation(player: Player, context: { [string]: any })
	if not PetService or type(context.eggId) ~= "string" then
		ShowPopup:FireClient(player, "Egg station unavailable")
		return
	end
	PetService.openEggStation(player, context.eggId, context.station)
end

function EggCatchService.start(deps)
	PetService = deps.PetService

	local folder = Workspace:FindFirstChild("EggStations")
	if not folder then
		return
	end

	for _, desc in ipairs(folder:GetDescendants()) do
		if desc:IsA("ClickDetector") and desc.Name == "OpenEgg" then
			local eggContext = eggContextForStation(desc)
			if eggContext then
				desc.MouseClick:Connect(function(player)
					openStation(player, eggContext)
				end)
			end
		elseif desc:IsA("ProximityPrompt") and desc.Name == "OpenEggPrompt" then
			local eggContext = eggContextForStation(desc)
			if eggContext then
				desc.Triggered:Connect(function(player)
					openStation(player, eggContext)
				end)
			end
		end
	end
end

return EggCatchService
