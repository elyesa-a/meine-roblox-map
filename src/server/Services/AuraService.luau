--!strict
-- AuraService: Kauf/Equip/Unequip einer einzelnen Aura + VFX am Charakter.
--
-- Datenmodell:
--   profile.Auras = { [auraId] = true }  -- gekaufte Auren
--   profile.EquippedAura = auraId? -- aktuell ausgeruestete Aura, oder nil

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local AuraConfig = require(Configs:WaitForChild("AuraConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestBuyAura = Remotes:WaitForChild("RequestBuyAura") :: RemoteEvent
local RequestEquipAura = Remotes:WaitForChild("RequestEquipAura") :: RemoteEvent
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

local AuraService = {}

local DataService
local StatService
local AntiExploitService

-- VFX-Tracking: pro Spieler die aktive Aura-Attachment-Instanz.
local activeAttachments: { [Player]: Attachment } = {}

local function removeVFX(player: Player)
	local att = activeAttachments[player]
	if att then
		att:Destroy()
		activeAttachments[player] = nil
	end
end

local function applyVFX(player: Player, auraId: string?)
	removeVFX(player)
	if not auraId then
		return
	end
	local def = AuraConfig.getById(auraId)
	if not def then
		return
	end
	local char = player.Character
	if not char then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "AuraVFX"
	attachment.Parent = hrp

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "AuraEmitter"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.LightEmission = 0.5
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1.0),
	})
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Rate = 40
	emitter.Speed = NumberRange.new(2, 4)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	if def.colorSequence then
		emitter.Color = def.colorSequence
	else
		emitter.Color = ColorSequence.new(def.color)
	end
	emitter.Parent = attachment

	activeAttachments[player] = attachment
end

function AuraService.getMultiplier(player: Player): number
	local profile = DataService.getProfile(player)
	if not profile or not profile.EquippedAura then
		return 1
	end
	local def = AuraConfig.getById(profile.EquippedAura)
	if not def then
		return 1
	end
	return def.multiplier
end

function AuraService.buyAura(player: Player, auraId: string)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	local def = AuraConfig.getById(auraId)
	if not def then
		return
	end
	if profile.Auras[auraId] then
		return -- schon gekauft
	end
	if profile.DnaCoins < def.priceDna then
		ShowPopup:FireClient(player, "Not enough DNA!")
		return
	end
	profile.DnaCoins -= def.priceDna
	profile.Auras[auraId] = true
	ShowPopup:FireClient(player, string.format("%s bought!", def.displayName))
	StatService.broadcastProfile(player)
	StatService.playSound(player, "Purchase")
end

function AuraService.equipAura(player: Player, auraId: string?)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	if auraId == nil then
		profile.EquippedAura = nil
		removeVFX(player)
		StatService.broadcastProfile(player)
		return
	end
	if type(auraId) ~= "string" then
		return
	end
	if not profile.Auras[auraId] then
		ShowPopup:FireClient(player, "You do not own this aura!")
		return
	end
	if not AuraConfig.getById(auraId) then
		return
	end
	profile.EquippedAura = auraId
	applyVFX(player, auraId)
	StatService.broadcastProfile(player)
end

local function onCharacterAdded(player: Player, _char: Model)
	-- Beim Respawn neue Attachment-Instanz an neuen HRP haengen.
	local profile = DataService.getProfile(player)
	if not profile then
		-- Profile ggf. noch nicht geladen -- spaeter erneut versuchen.
		task.delay(0.5, function()
			local p = DataService.getProfile(player)
			if p and p.EquippedAura then
				applyVFX(player, p.EquippedAura)
			end
		end)
		return
	end
	if profile.EquippedAura then
		-- Warte kurz, bis Character voll geladen.
		task.delay(0.2, function()
			applyVFX(player, profile.EquippedAura)
		end)
	end
end

function AuraService.start(deps)
	DataService = deps.DataService
	StatService = deps.StatService
	AntiExploitService = deps.AntiExploitService

	AntiExploitService.safeBind(RequestBuyAura, 5, function(player, auraId)
		if type(auraId) ~= "string" then
			return
		end
		AuraService.buyAura(player, auraId)
	end)
	AntiExploitService.safeBind(RequestEquipAura, 8, function(player, auraId)
		-- nil = Aura ablegen
		if auraId ~= nil and type(auraId) ~= "string" then
			return
		end
		AuraService.equipAura(player, auraId)
	end)

	-- Respawn: VFX nach neuer Charakter-Spawn wieder anlegen.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(char)
			onCharacterAdded(player, char)
		end)
		if player.Character then
			onCharacterAdded(player, player.Character)
		end
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function(char)
			onCharacterAdded(player, char)
		end)
		if player.Character then
			onCharacterAdded(player, player.Character)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		activeAttachments[player] = nil
	end)
end

return AuraService
