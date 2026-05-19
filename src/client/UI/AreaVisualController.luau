--!strict
-- Clientseitige Lock-Farben fuer per-Spieler Area-Zugang.

local Workspace = game:GetService("Workspace")

local AreaVisualController = {}

local UNLOCKED = Color3.fromRGB(80, 255, 140)
local UNLOCKED_TEXT = Color3.fromRGB(170, 255, 205)
local LOCKED = Color3.fromRGB(255, 85, 85)
local LOCKED_TEXT = Color3.fromRGB(255, 170, 170)

local TINTABLE_FIELD_NAMES = {
	GateField = true,
	TunnelGateScanField = true,
	BorderField = true,
	TrainingGateField = true,
	Neon = true,
}

local function num(value: any): number
	return if type(value) == "number" then value else 0
end

local function canAccess(state: { [string]: any }, requiredDna: any, requiredRebirth: any): boolean
	return num(state.DnaCoins) >= num(requiredDna) and num(state.Rebirths) >= num(requiredRebirth)
end

local function findRequirement(inst: Instance): (number, number)
	for _, desc in ipairs(inst:GetDescendants()) do
		if desc:IsA("BasePart") then
			local requiredDna = desc:GetAttribute("RequiredDNA")
			if requiredDna ~= nil then
				return num(requiredDna), num(desc:GetAttribute("RequiredRebirth"))
			end
		end
	end
	return 0, 0
end

local function tintPart(part: BasePart, color: Color3)
	part.Color = color
	for _, desc in ipairs(part:GetDescendants()) do
		if desc:IsA("PointLight") then
			desc.Color = color
		end
	end
end

local function tintModelVisuals(model: Instance, unlocked: boolean)
	local partColor = if unlocked then UNLOCKED else LOCKED
	local textColor = if unlocked then UNLOCKED_TEXT else LOCKED_TEXT
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			if TINTABLE_FIELD_NAMES[desc.Name] then
				tintPart(desc, partColor)
			end
		elseif desc:IsA("TextLabel") then
			desc.TextColor3 = textColor
		end
	end
end

local function collectAreaRequirements(state: { [string]: any }): { [string]: boolean }
	local result: { [string]: boolean } = {}
	local gates = Workspace:FindFirstChild("AreaGates")
	if not gates then
		return result
	end
	for _, model in ipairs(gates:GetChildren()) do
		local areaId = model:GetAttribute("AreaId")
		if type(areaId) == "string" then
			local requiredDna, requiredRebirth = findRequirement(model)
			result[areaId] = canAccess(state, requiredDna, requiredRebirth)
			tintModelVisuals(model, result[areaId])
		else
			local requiredDna, requiredRebirth = findRequirement(model)
			tintModelVisuals(model, canAccess(state, requiredDna, requiredRebirth))
		end
	end
	return result
end

local function updateAreaShells(areaUnlocked: { [string]: boolean })
	local lab = Workspace:FindFirstChild("VirusLab")
	if not lab then
		return
	end
	for _, areaFolder in ipairs(lab:GetChildren()) do
		local unlocked = areaUnlocked[areaFolder.Name]
		if unlocked == nil then
			continue
		end
		local color = if unlocked then UNLOCKED else LOCKED
		for _, desc in ipairs(areaFolder:GetDescendants()) do
			if desc:IsA("BasePart") and desc:GetAttribute("AreaVisualId") == areaFolder.Name then
				tintPart(desc, color)
			end
		end
	end
end

local function updateBorders(state: { [string]: any })
	local borders = Workspace:FindFirstChild("EnemyBorders")
	if not borders then
		return
	end
	for _, model in ipairs(borders:GetChildren()) do
		local requiredDna, requiredRebirth = findRequirement(model)
		tintModelVisuals(model, canAccess(state, requiredDna, requiredRebirth))
	end
end

function AreaVisualController.update(state: { [string]: any })
	local areaUnlocked = collectAreaRequirements(state)
	updateAreaShells(areaUnlocked)
	updateBorders(state)
end

return AreaVisualController
