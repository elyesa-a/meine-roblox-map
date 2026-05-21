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
local DailyQuestService
local TitleService

local AURA_EFFECTS_FOLDER_NAME = "AuraEffects"
local ACTIVE_AURA_NAME = "ActiveAuraEffect"
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"

-- VFX-Tracking: pro Spieler alle Instanzen, die zur aktiven Aura gehoeren.
local activeEffects: { [Player]: { Instance } } = {}

local auraEffectsFolder: Folder? = nil

local function makeFolder(name: string, parent: Instance): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function makeAttachmentTemplate(parent: Instance, name: string, targetPart: string, position: Vector3?): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Position = position or Vector3.zero
	attachment:SetAttribute("TargetPart", targetPart)
	attachment.Parent = parent
	return attachment
end

local function makeEmitter(parent: Instance, name: string, texture: string, color: ColorSequence, rate: number, lifetime: NumberRange, speed: NumberRange, size: NumberSequence, transparency: NumberSequence, lightEmission: number): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Texture = texture
	emitter.Color = color
	emitter.Rate = rate
	emitter.Lifetime = lifetime
	emitter.Speed = speed
	emitter.Size = size
	emitter.Transparency = transparency
	emitter.LightEmission = lightEmission
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Drag = 2
	emitter.Parent = parent
	return emitter
end

local function seq(startValue: number, endValue: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, startValue),
		NumberSequenceKeypoint.new(1, endValue),
	})
end

local function makeLightTemplate(parent: Instance, color: Color3, brightness: number, range: number)
	local light = Instance.new("PointLight")
	light.Name = "AuraLight"
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light:SetAttribute("TargetPart", "HumanoidRootPart")
	light.Parent = parent
end

local function makeBeamTemplate(parent: Instance, name: string, color: ColorSequence, attachment0Name: string, attachment1Name: string, width: number)
	local beam = Instance.new("Beam")
	beam.Name = name
	beam.Color = color
	beam.Width0 = width
	beam.Width1 = width * 0.65
	beam.LightEmission = 0.85
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(1, 0.55),
	})
	beam.FaceCamera = true
	beam.Segments = 6
	beam:SetAttribute("Attachment0Name", attachment0Name)
	beam:SetAttribute("Attachment1Name", attachment1Name)
	beam.Parent = parent
end

local function makeShardTemplate(parent: Instance, name: string, color: Color3, offset: Vector3, size: Vector3)
	local shard = Instance.new("Part")
	shard.Name = name
	shard.Anchored = false
	shard.CanCollide = false
	shard.CanTouch = false
	shard.CanQuery = false
	shard.Massless = true
	shard.Material = Enum.Material.Neon
	shard.Color = color
	shard.Size = size
	shard:SetAttribute("TargetPart", "HumanoidRootPart")
	shard:SetAttribute("OffsetX", offset.X)
	shard:SetAttribute("OffsetY", offset.Y)
	shard:SetAttribute("OffsetZ", offset.Z)
	shard.Parent = parent
end

local function resetTemplate(displayName: string): Folder
	local root = makeFolder(AURA_EFFECTS_FOLDER_NAME, ReplicatedStorage)
	auraEffectsFolder = root
	local existing = root:FindFirstChild(displayName)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = displayName
	folder.Parent = root
	return folder
end

local function colorSequenceFor(def): ColorSequence
	if def.colorSequence then
		return def.colorSequence
	end
	return ColorSequence.new(def.color, def.color:Lerp(Color3.fromRGB(245, 255, 245), 0.35))
end

local function buildGenericAuraTemplate(def)
	local folder = resetTemplate(def.displayName)
	local auraColor = colorSequenceFor(def)
	local root = makeAttachmentTemplate(folder, def.id .. "Root", "HumanoidRootPart")
	local rate = math.clamp(12 + def.requiredTier * 2, 14, 32)
	local sizeStart = math.clamp(0.45 + def.requiredTier * 0.05, 0.5, 1.1)
	local spark = makeEmitter(root, def.id .. "Particles", SPARKLE_TEXTURE, auraColor, rate, NumberRange.new(0.65, 1.35), NumberRange.new(1.2, 3.2), seq(sizeStart, 0.08), seq(0.14, 1), 0.65)
	spark.Acceleration = Vector3.new(0, 0.6 + def.requiredTier * 0.12, 0)

	if string.find(def.id, "Toxic") or string.find(def.id, "Venom") or string.find(def.id, "Plague") or string.find(def.id, "Corrupted") or string.find(def.id, "Dark") then
		local torso = makeAttachmentTemplate(folder, def.id .. "Mist", "UpperTorso")
		local mist = makeEmitter(torso, def.id .. "BioMist", SMOKE_TEXTURE, auraColor, math.clamp(5 + def.requiredTier, 6, 16), NumberRange.new(1.0, 1.8), NumberRange.new(0.5, 1.6), seq(1.1, 0.32), seq(0.55, 1), 0.22)
		mist.Acceleration = Vector3.new(0, 1.1, 0)
	end

	if def.requiredTier >= 4 then
		makeShardTemplate(folder, def.id .. "ShardA", def.color, Vector3.new(-2.0, 1.1, 0.25), Vector3.new(0.45, 0.45, 0.1))
		makeShardTemplate(folder, def.id .. "ShardB", def.color:Lerp(Color3.fromRGB(255, 255, 255), 0.2), Vector3.new(1.9, 0.15, -0.35), Vector3.new(0.34, 0.66, 0.1))
	end

	makeLightTemplate(folder, def.color, math.clamp(0.35 + def.requiredTier * 0.05, 0.4, 0.9), math.clamp(8 + def.requiredTier * 0.45, 9, 13))
end

local function buildAuraEffectTemplates()
	local electric = resetTemplate("Electric Aura")
	do
		local cyan = ColorSequence.new(Color3.fromRGB(120, 235, 255), Color3.fromRGB(255, 255, 255))
		local root = makeAttachmentTemplate(electric, "ElectricRoot", "HumanoidRootPart")
		makeEmitter(root, "ElectricSparks", SPARKLE_TEXTURE, cyan, 26, NumberRange.new(0.18, 0.42), NumberRange.new(4, 8), seq(0.35, 0.05), seq(0.05, 1), 0.9)
		local arcA = makeAttachmentTemplate(electric, "ElectricArcA", "HumanoidRootPart", Vector3.new(-2.2, 0.4, 0))
		local arcB = makeAttachmentTemplate(electric, "ElectricArcB", "HumanoidRootPart", Vector3.new(2.2, 1.8, 0))
		local arcC = makeAttachmentTemplate(electric, "ElectricArcC", "HumanoidRootPart", Vector3.new(0, -1.5, 1.7))
		makeBeamTemplate(electric, "ElectricBeamA", cyan, arcA.Name, arcB.Name, 0.17)
		makeBeamTemplate(electric, "ElectricBeamB", cyan, arcB.Name, arcC.Name, 0.12)
		makeLightTemplate(electric, Color3.fromRGB(120, 230, 255), 0.85, 11)
	end

	local blizzard = resetTemplate("Blizzard Aura")
	do
		local ice = ColorSequence.new(Color3.fromRGB(210, 245, 255), Color3.fromRGB(120, 210, 255))
		local root = makeAttachmentTemplate(blizzard, "BlizzardRoot", "HumanoidRootPart")
		makeEmitter(root, "Snowflakes", SPARKLE_TEXTURE, ice, 18, NumberRange.new(1.1, 1.8), NumberRange.new(1, 3), seq(0.5, 0.08), seq(0.12, 1), 0.35)
		local torso = makeAttachmentTemplate(blizzard, "FrostMist", "UpperTorso", Vector3.new(0, 0.1, 0))
		local mist = makeEmitter(torso, "ColdMist", SMOKE_TEXTURE, ice, 10, NumberRange.new(1, 1.6), NumberRange.new(0.7, 1.7), seq(1.6, 0.45), seq(0.58, 1), 0.18)
		mist.Acceleration = Vector3.new(0, 1.2, 0)
		makeLightTemplate(blizzard, Color3.fromRGB(180, 235, 255), 0.35, 9)
	end

	local purple = resetTemplate("Purple Aura")
	do
		local violet = ColorSequence.new(Color3.fromRGB(180, 80, 255), Color3.fromRGB(235, 180, 255))
		local root = makeAttachmentTemplate(purple, "PurpleRoot", "HumanoidRootPart")
		makeEmitter(root, "MysticGlow", SPARKLE_TEXTURE, violet, 22, NumberRange.new(0.8, 1.35), NumberRange.new(1.5, 3.2), seq(0.85, 0.12), seq(0.18, 1), 0.75)
		local torso = makeAttachmentTemplate(purple, "PurpleMist", "UpperTorso")
		makeEmitter(torso, "SoftPurpleMist", SMOKE_TEXTURE, violet, 8, NumberRange.new(1, 1.7), NumberRange.new(0.5, 1.3), seq(1.35, 0.35), seq(0.64, 1), 0.25)
		makeLightTemplate(purple, Color3.fromRGB(190, 100, 255), 0.5, 10)
	end

	local poison = resetTemplate("Poison Aura")
	do
		local toxic = ColorSequence.new(Color3.fromRGB(70, 255, 95), Color3.fromRGB(20, 120, 45))
		local root = makeAttachmentTemplate(poison, "PoisonRoot", "HumanoidRootPart")
		local gas = makeEmitter(root, "ToxicGas", SMOKE_TEXTURE, toxic, 15, NumberRange.new(1.1, 1.8), NumberRange.new(0.7, 1.8), seq(1.15, 0.32), seq(0.42, 1), 0.22)
		gas.Acceleration = Vector3.new(0, 1.4, 0)
		local bubbles = makeAttachmentTemplate(poison, "PoisonBubbles", "UpperTorso", Vector3.new(0, -0.2, 0))
		makeEmitter(bubbles, "ToxicBubbles", SPARKLE_TEXTURE, toxic, 12, NumberRange.new(0.7, 1.25), NumberRange.new(1.2, 2.2), seq(0.42, 0.08), seq(0.08, 1), 0.45)
		makeLightTemplate(poison, Color3.fromRGB(80, 255, 95), 0.45, 9)
	end

	local magma = resetTemplate("Magma Aura")
	do
		local lava = ColorSequence.new(Color3.fromRGB(255, 210, 70), Color3.fromRGB(255, 70, 35))
		local root = makeAttachmentTemplate(magma, "MagmaRoot", "HumanoidRootPart")
		local flame = makeEmitter(root, "LavaEmbers", FIRE_TEXTURE, lava, 18, NumberRange.new(0.45, 0.9), NumberRange.new(1.8, 3.8), seq(0.85, 0.14), seq(0.12, 1), 0.65)
		flame.Acceleration = Vector3.new(0, 3.4, 0)
		local embers = makeAttachmentTemplate(magma, "MagmaEmbers", "UpperTorso")
		makeEmitter(embers, "HotSparks", SPARKLE_TEXTURE, lava, 14, NumberRange.new(0.35, 0.8), NumberRange.new(2.4, 4.8), seq(0.35, 0.05), seq(0.05, 1), 0.85)
		makeLightTemplate(magma, Color3.fromRGB(255, 120, 45), 0.75, 11)
	end

	local glitch = resetTemplate("Glitch Aura")
	do
		local digital = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 245, 255)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 70, 220)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 90, 255)),
		})
		local root = makeAttachmentTemplate(glitch, "GlitchRoot", "HumanoidRootPart")
		makeEmitter(root, "DigitalFlicker", SPARKLE_TEXTURE, digital, 30, NumberRange.new(0.25, 0.65), NumberRange.new(2.2, 5.2), seq(0.48, 0.05), seq(0.03, 1), 0.9)
		makeShardTemplate(glitch, "GlitchShardA", Color3.fromRGB(80, 245, 255), Vector3.new(-2.1, 1.2, 0), Vector3.new(0.55, 0.55, 0.12))
		makeShardTemplate(glitch, "GlitchShardB", Color3.fromRGB(255, 70, 220), Vector3.new(1.9, 0.1, -0.6), Vector3.new(0.42, 0.8, 0.12))
		makeShardTemplate(glitch, "GlitchShardC", Color3.fromRGB(170, 90, 255), Vector3.new(0.5, 2.1, 0.7), Vector3.new(0.72, 0.36, 0.12))
		makeLightTemplate(glitch, Color3.fromRGB(255, 80, 220), 0.7, 10)
	end

	local rainbow = resetTemplate("Rainbow Aura")
	do
		local rainbowSeq = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 80, 80)),
			ColorSequenceKeypoint.new(0.18, Color3.fromRGB(255, 220, 80)),
			ColorSequenceKeypoint.new(0.36, Color3.fromRGB(110, 255, 120)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(80, 215, 255)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(165, 100, 255)),
			ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 90, 210)),
		})
		local root = makeAttachmentTemplate(rainbow, "RainbowRoot", "HumanoidRootPart")
		makeEmitter(root, "RainbowSparkles", SPARKLE_TEXTURE, rainbowSeq, 34, NumberRange.new(0.8, 1.45), NumberRange.new(1.8, 4), seq(0.7, 0.08), seq(0.06, 1), 0.95)
		local head = makeAttachmentTemplate(rainbow, "RainbowHalo", "Head", Vector3.new(0, 0.45, 0))
		makeEmitter(head, "RainbowHaloSpark", SPARKLE_TEXTURE, rainbowSeq, 12, NumberRange.new(0.75, 1.25), NumberRange.new(0.8, 1.8), seq(0.45, 0.05), seq(0.08, 1), 0.85)
		makeLightTemplate(rainbow, Color3.fromRGB(255, 245, 170), 0.85, 12)
	end

	for _, def in ipairs(AuraConfig.Auras) do
		local root = auraEffectsFolder or ReplicatedStorage:FindFirstChild(AURA_EFFECTS_FOLDER_NAME)
		if not root or not root:FindFirstChild(def.displayName) then
			buildGenericAuraTemplate(def)
		end
	end
end

local function markAuraInstance(instance: Instance)
	instance.Name = ACTIVE_AURA_NAME
	instance:SetAttribute("IsAuraVFX", true)
end

local function removeVFX(player: Player)
	local tracked = activeEffects[player]
	if tracked then
		for _, instance in ipairs(tracked) do
			if instance.Parent then
				instance:Destroy()
			end
		end
		activeEffects[player] = nil
	end

	local char = player.Character
	if char then
		for _, instance in ipairs(char:GetDescendants()) do
			if instance:GetAttribute("IsAuraVFX") == true or instance.Name == ACTIVE_AURA_NAME then
				instance:Destroy()
			end
		end
	end
end

local function findTargetPart(char: Model, targetPartName: string): BasePart?
	local direct = char:FindFirstChild(targetPartName)
	if direct and direct:IsA("BasePart") then
		return direct
	end
	if targetPartName == "UpperTorso" then
		local torso = char:FindFirstChild("Torso")
		if torso and torso:IsA("BasePart") then
			return torso
		end
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function getAuraTemplate(def): Folder?
	if not auraEffectsFolder then
		auraEffectsFolder = ReplicatedStorage:FindFirstChild(AURA_EFFECTS_FOLDER_NAME) :: Folder?
	end
	if not auraEffectsFolder then
		return nil
	end
	local template = auraEffectsFolder:FindFirstChild(def.displayName)
	if template and template:IsA("Folder") then
		return template
	end
	return nil
end

local function parseBossArea(bossId: string): number?
	local areaText = string.match(bossId, "^A(%d+)E10$")
	return areaText and tonumber(areaText) or nil
end

local function getHighestBossDefeated(profile): number
	local highest = if type(profile.HighestBossDefeated) == "number" then profile.HighestBossDefeated else 0
	if type(profile.BossDefeats) == "table" then
		for bossId, count in pairs(profile.BossDefeats) do
			if type(bossId) == "string" and type(count) == "number" and count > 0 then
				local areaNumber = parseBossArea(bossId)
				if areaNumber then
					highest = math.max(highest, areaNumber)
				end
			end
		end
	end
	return math.clamp(highest, 0, AuraConfig.MaxTier - 1)
end

local function getUnlockedAuraTier(profile): number
	local highest = getHighestBossDefeated(profile)
	if profile.HighestBossDefeated ~= highest then
		profile.HighestBossDefeated = highest
	end
	return AuraConfig.getUnlockedTier(highest)
end

local function ownsAura(profile, def): boolean
	if not profile.Auras then
		return false
	end
	if profile.Auras[def.id] == true then
		return true
	end
	if def.legacyIds then
		for _, legacyId in ipairs(def.legacyIds) do
			if profile.Auras[legacyId] == true then
				return true
			end
		end
	end
	return false
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

	local template = getAuraTemplate(def)
	if not template then
		return
	end

	local created: { Instance } = {}
	local attachmentsByTemplateName: { [string]: Attachment } = {}

	for _, child in ipairs(template:GetChildren()) do
		if child:IsA("Attachment") then
			local targetName = child:GetAttribute("TargetPart")
			local target = findTargetPart(char, if type(targetName) == "string" then targetName else "HumanoidRootPart")
			if target then
				local clone = child:Clone()
				markAuraInstance(clone)
				clone.Parent = target
				attachmentsByTemplateName[child.Name] = clone
				table.insert(created, clone)
			end
		end
	end

	for _, child in ipairs(template:GetChildren()) do
		if child:IsA("Beam") then
			local attachment0Name = child:GetAttribute("Attachment0Name")
			local attachment1Name = child:GetAttribute("Attachment1Name")
			if type(attachment0Name) == "string" and type(attachment1Name) == "string" then
				local attachment0 = attachmentsByTemplateName[attachment0Name]
				local attachment1 = attachmentsByTemplateName[attachment1Name]
				if attachment0 and attachment1 then
					local clone = child:Clone()
					clone.Attachment0 = attachment0
					clone.Attachment1 = attachment1
					markAuraInstance(clone)
					clone.Parent = hrp
					table.insert(created, clone)
				end
			end
		elseif child:IsA("PointLight") then
			local targetName = child:GetAttribute("TargetPart")
			local target = findTargetPart(char, if type(targetName) == "string" then targetName else "HumanoidRootPart")
			if target then
				local clone = child:Clone()
				markAuraInstance(clone)
				clone.Parent = target
				table.insert(created, clone)
			end
		elseif child:IsA("BasePart") then
			local targetName = child:GetAttribute("TargetPart")
			local target = findTargetPart(char, if type(targetName) == "string" then targetName else "HumanoidRootPart")
			if target then
				local clone = child:Clone()
				local offset = Vector3.new(
					child:GetAttribute("OffsetX") :: number? or 0,
					child:GetAttribute("OffsetY") :: number? or 0,
					child:GetAttribute("OffsetZ") :: number? or 0
				)
				markAuraInstance(clone)
				clone.CFrame = target.CFrame * CFrame.new(offset)
				clone.Parent = char
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = target
				weld.Part1 = clone
				markAuraInstance(weld)
				weld.Parent = clone
				table.insert(created, clone)
			end
		end
	end

	activeEffects[player] = created
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
	local unlockedTier = getUnlockedAuraTier(profile)
	if def.requiredTier > unlockedTier then
		ShowPopup:FireClient(player, AuraConfig.getLockedText(def))
		return
	end
	if ownsAura(profile, def) then
		profile.Auras[def.id] = true
		StatService.broadcastProfile(player)
		return
	end
	if profile.DnaCoins < def.priceDna then
		ShowPopup:FireClient(player, "Not enough DNA!")
		return
	end
	profile.DnaCoins -= def.priceDna
	profile.Auras[def.id] = true
	ShowPopup:FireClient(player, string.format("%s bought!", def.displayName))
	if TitleService then
		TitleService.evaluatePlayer(player)
	end
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
	local def = AuraConfig.getById(auraId)
	if not def then
		return
	end
	if not ownsAura(profile, def) then
		ShowPopup:FireClient(player, "You do not own this aura!")
		return
	end
	profile.Auras[def.id] = true
	profile.EquippedAura = def.id
	applyVFX(player, def.id)
	if DailyQuestService then
		DailyQuestService.record(player, "EquipAura", 1)
	end
	if TitleService then
		TitleService.evaluatePlayer(player)
	end
	ShowPopup:FireClient(player, string.format("%s equipped!", def.displayName))
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
	DailyQuestService = deps.DailyQuestService
	TitleService = deps.TitleService
	buildAuraEffectTemplates()

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
		activeEffects[player] = nil
	end)
end

return AuraService
