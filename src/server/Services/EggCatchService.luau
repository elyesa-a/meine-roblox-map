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
local RequestOpenEggStation = Remotes:WaitForChild("RequestOpenEggStation") :: RemoteEvent

local EggCatchService = {}

local PetService
local lastAutoOpenAt: { [Player]: number } = {}
local AUTO_OPEN_COOLDOWN = 0.8
local AUTO_OPEN_MAX_DISTANCE = 20

local function findEggStation(instance: Instance): Instance?
	local current: Instance? = instance
	while current do
		if (current:IsA("Model") or current:IsA("BasePart"))
			and current:GetAttribute("AreaIndex") ~= nil
			and (current:GetAttribute("EggId") ~= nil or current:GetAttribute("EggTier") ~= nil) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function eggContextForStation(instance: Instance): { [string]: any }?
	local station = findEggStation(instance)
	if not station then
		return nil
	end

	local areaIndex = station:GetAttribute("AreaIndex")
	local eggId = station:GetAttribute("EggId")
	if type(areaIndex) ~= "number" then
		return nil
	end
	if type(eggId) ~= "string" then
		local legacyTier = station:GetAttribute("EggTier")
		eggId = PetConfig.getEggId(areaIndex, if type(legacyTier) == "string" then legacyTier else nil)
	end

	local egg = PetConfig.getEggById(eggId)
	if not egg then
		return nil
	end

	return {
		station = station,
		areaIndex = egg.areaIndex,
		eggId = egg.id,
		eggName = egg.displayName,
	}
end

local function getCharacterRoot(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getStationCenter(station: Instance?): Vector3?
	if not station or not station.Parent then
		return nil
	end
	if station:IsA("BasePart") then
		return station.Position
	end
	if station:IsA("Model") then
		local capsule = station:FindFirstChild("EggCapsule", true)
		if capsule and capsule:IsA("BasePart") then
			return capsule.Position
		end
		local petEgg = station:FindFirstChild("PetEgg", true)
		if petEgg and petEgg:IsA("BasePart") then
			return petEgg.Position
		end
		return station:GetPivot().Position
	end
	local part = station:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Position or nil
end

local function canAutoOpenStation(player: Player, station: Instance): boolean
	if not station:IsDescendantOf(Workspace) then
		return false
	end
	local now = os.clock()
	local last = lastAutoOpenAt[player]
	if last and now - last < AUTO_OPEN_COOLDOWN then
		return false
	end
	local root = getCharacterRoot(player)
	local center = getStationCenter(station)
	if not root or not center then
		return false
	end
	if (root.Position - center).Magnitude > AUTO_OPEN_MAX_DISTANCE then
		return false
	end
	lastAutoOpenAt[player] = now
	return true
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

	RequestOpenEggStation.OnServerEvent:Connect(function(player, station)
		if typeof(station) ~= "Instance" then
			return
		end
		local eggContext = eggContextForStation(station)
		if not eggContext or not canAutoOpenStation(player, eggContext.station) then
			return
		end
		openStation(player, eggContext)
	end)
end

game:GetService("Players").PlayerRemoving:Connect(function(player)
	lastAutoOpenAt[player] = nil
end)

return EggCatchService
