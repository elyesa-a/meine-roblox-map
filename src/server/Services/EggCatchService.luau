--!strict
-- EggCatchService: connects world EggStations to the existing Pet hatch UI.
--
-- The stations are built by VirusLabBuilder with AreaIndex/EggTier
-- attributes. Clicking a station opens the matching egg in the Pet frame; the
-- actual hatch is still validated and rolled server-side in PetService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local PetConfig = require(Configs:WaitForChild("PetConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local OpenPetEggShop = Remotes:WaitForChild("OpenPetEggShop") :: RemoteEvent

local EggCatchService = {}

local function findEggModel(instance: Instance): Model?
	local current: Instance? = instance
	while current do
		if current:IsA("Model") and current:GetAttribute("AreaIndex") ~= nil and current:GetAttribute("EggTier") ~= nil then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function eggIdForStation(clickDetector: ClickDetector): string?
	local model = findEggModel(clickDetector)
	if not model then
		return nil
	end
	local areaIndex = model:GetAttribute("AreaIndex")
	local tier = model:GetAttribute("EggTier")
	if type(areaIndex) ~= "number" or type(tier) ~= "string" then
		return nil
	end
	local eggId = PetConfig.getEggId(areaIndex, tier)
	if not PetConfig.getEggById(eggId) then
		return nil
	end
	return eggId
end

function EggCatchService.start(_deps)
	local folder = Workspace:FindFirstChild("EggStations")
	if not folder then
		return
	end

	for _, desc in ipairs(folder:GetDescendants()) do
		if desc:IsA("ClickDetector") and desc.Name == "OpenEgg" then
			local eggId = eggIdForStation(desc)
			if eggId then
				desc.MouseClick:Connect(function(player)
					OpenPetEggShop:FireClient(player, eggId)
				end)
			end
		end
	end
end

return EggCatchService
