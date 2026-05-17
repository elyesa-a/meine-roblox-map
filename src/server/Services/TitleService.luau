--!strict
-- TitleService: unlocks, equips, bonuses, and visible overhead title tags.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local TitleConfig = require(Configs:WaitForChild("TitleConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestEquipTitle = Remotes:WaitForChild("RequestEquipTitle") :: RemoteEvent
local ShowPopup = Remotes:WaitForChild("ShowPopup") :: RemoteEvent

local TitleService = {}

local DataService
local StatService
local AntiExploitService

local TITLE_BILLBOARD_NAME = "ActiveTitleBillboard"

local function ensureTitleData(profile)
	profile.Titles = profile.Titles or {}
	profile.TitleStats = profile.TitleStats or {}
	profile.BossDefeats = profile.BossDefeats or {}
	profile.ZonesReached = profile.ZonesReached or {}
	if profile.Titles.Rookie ~= true then
		profile.Titles.Rookie = true
	end
	if not profile.EquippedTitle then
		profile.EquippedTitle = "Rookie"
	end
end

local function getConditionValue(profile, condition): number
	if not condition then
		return 0
	end
	if condition.kind == "Auto" then
		return math.huge
	elseif condition.kind == "Power" then
		return profile.Power or 0
	elseif condition.kind == "Dna" then
		return profile.DnaCoins or 0
	elseif condition.kind == "Rebirth" then
		return profile.Rebirths or 0
	elseif condition.kind == "Aura" then
		return if condition.key and profile.Auras and profile.Auras[condition.key] then 1 else 0
	elseif condition.kind == "Boss" then
		return if condition.key and profile.BossDefeats then profile.BossDefeats[condition.key] or 0 else 0
	elseif condition.kind == "Zone" then
		return if condition.key and profile.ZonesReached and profile.ZonesReached[condition.key] then 1 else 0
	elseif condition.kind == "Stat" then
		return if condition.key and profile.TitleStats then profile.TitleStats[condition.key] or 0 else 0
	end
	return 0
end

local function conditionMet(profile, condition): boolean
	if not condition then
		return false
	end
	if condition.kind == "Auto" then
		return true
	end
	local required = condition.value or 1
	return getConditionValue(profile, condition) >= required
end

function TitleService.unlockTitle(player: Player, titleId: string, silent: boolean?)
	local profile = DataService.getProfile(player)
	if not profile then
		return false
	end
	ensureTitleData(profile)
	local def = TitleConfig.getById(titleId)
	if not def then
		return false
	end
	if profile.Titles[titleId] == true then
		return false
	end
	profile.Titles[titleId] = true
	ShowPopup:FireClient(player, "Title unlocked: " .. def.displayName)
	if silent ~= true then
		StatService.playSound(player, "Reward")
	end
	StatService.broadcastProfile(player)
	return true
end

function TitleService.evaluatePlayer(player: Player)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	ensureTitleData(profile)
	for _, def in ipairs(TitleConfig.Titles) do
		if profile.Titles[def.id] ~= true and conditionMet(profile, def.condition) then
			TitleService.unlockTitle(player, def.id, true)
		end
	end
end

function TitleService.addStat(player: Player, key: string, amount: number)
	if amount <= 0 then
		return
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	ensureTitleData(profile)
	profile.TitleStats[key] = (profile.TitleStats[key] or 0) + amount
	TitleService.evaluatePlayer(player)
end

function TitleService.setZoneReached(player: Player, zoneId: string)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	ensureTitleData(profile)
	profile.ZonesReached[zoneId] = true
	TitleService.evaluatePlayer(player)
end

function TitleService.recordBossDefeat(player: Player, bossId: string)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	ensureTitleData(profile)
	profile.BossDefeats[bossId] = (profile.BossDefeats[bossId] or 0) + 1
	TitleService.evaluatePlayer(player)
end

function TitleService.getBonusMultiplier(player: Player, bonusType: string): number
	local profile = DataService.getProfile(player)
	if not profile or not profile.EquippedTitle then
		return 1
	end
	local def = TitleConfig.getById(profile.EquippedTitle)
	if not def or not def.bonus then
		return 1
	end
	local bonus = (def.bonus :: any)[bonusType]
	if type(bonus) ~= "number" then
		return 1
	end
	return 1 + bonus
end

local function clearBillboard(char: Model)
	local head = char:FindFirstChild("Head")
	if head then
		local existing = head:FindFirstChild(TITLE_BILLBOARD_NAME)
		if existing then
			existing:Destroy()
		end
	end
end

local function applyBillboard(player: Player)
	local profile = DataService.getProfile(player)
	local char = player.Character
	if not profile or not char then
		return
	end
	ensureTitleData(profile)
	clearBillboard(char)

	local titleId = profile.EquippedTitle
	if not titleId then
		return
	end
	local def = TitleConfig.getById(titleId)
	local head = char:FindFirstChild("Head")
	if not def or not head or not head:IsA("BasePart") then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = TITLE_BILLBOARD_NAME
	billboard.Size = UDim2.fromOffset(190, 44)
	billboard.StudsOffset = Vector3.new(0, 2.65, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 90
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.Text = "[" .. def.displayName .. "]"
	label.TextScaled = true
	label.TextColor3 = def.color
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.Parent = billboard

	if def.rarity == "Mythic" then
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 120)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 80)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 255, 160)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 190, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 90, 220)),
		})
		gradient.Parent = label
	end
end

function TitleService.equipTitle(player: Player, titleId: string)
	local profile = DataService.getProfile(player)
	if not profile then
		return
	end
	ensureTitleData(profile)
	if profile.Titles[titleId] ~= true then
		ShowPopup:FireClient(player, "Title is locked!")
		return
	end
	local def = TitleConfig.getById(titleId)
	if not def then
		return
	end
	profile.EquippedTitle = titleId
	applyBillboard(player)
	ShowPopup:FireClient(player, def.displayName .. " equipped!")
	StatService.broadcastProfile(player)
end

local function onCharacter(player: Player)
	task.delay(0.35, function()
		applyBillboard(player)
	end)
end

function TitleService.start(deps)
	DataService = deps.DataService
	StatService = deps.StatService
	AntiExploitService = deps.AntiExploitService

	AntiExploitService.safeBind(RequestEquipTitle, 6, function(player, titleId)
		if type(titleId) ~= "string" then
			return
		end
		TitleService.equipTitle(player, titleId)
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			onCharacter(player)
		end)
		task.delay(1, function()
			TitleService.evaluatePlayer(player)
			if player.Character then
				onCharacter(player)
			end
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function()
			onCharacter(player)
		end)
		task.delay(1, function()
			TitleService.evaluatePlayer(player)
			if player.Character then
				onCharacter(player)
			end
		end)
	end
end

return TitleService
