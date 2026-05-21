--!strict
-- Server-authoritative global lab leaderboards for Spawn Lab.
-- Writes compact values to OrderedDataStores on a safe interval, then updates
-- the world ranking wall in Workspace.Map.SpawnHub.LeaderboardZone.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))

local LeaderboardService = {}

local REFRESH_INTERVAL = 60
local MAX_ROWS = 5
local MAX_ORDERED_VALUE = 9_000_000_000_000_000
local TOP_DUMMY_SCALE = 3

local DataService
local stores: { [string]: OrderedDataStore? } = {}
local lastSavedValues: { [string]: { [number]: number } } = {}
local cachedNames: { [number]: string } = {}
local cachedTopPowerUsers: { [number]: number } = {}
local dummySpin = 0

type BoardDef = {
	key: string,
	title: string,
	valueLabel: string,
	storeName: string,
	metric: (any) -> number,
}

local BOARD_DEFS: { BoardDef } = {
	{
		key = "Power",
		title = "TOP POWER",
		valueLabel = "Power",
		storeName = "VirusRankings_Power_v1",
		metric = function(profile)
			return math.max(profile.Power or 0, profile.HighestPower or 0)
		end,
	},
	{
		key = "Mutations",
		title = "TOP MUTATIONS",
		valueLabel = "Mutations",
		storeName = "VirusRankings_Mutations_v1",
		metric = function(profile)
			return profile.Rebirths or 0
		end,
	},
	{
		key = "Dna",
		title = "TOP DNA",
		valueLabel = "DNA",
		storeName = "VirusRankings_DNA_v1",
		metric = function(profile)
			return profile.DnaCoins or 0
		end,
	},
	{
		key = "BossKills",
		title = "TOP BOSS KILLS",
		valueLabel = "Boss Kills",
		storeName = "VirusRankings_BossKills_v1",
		metric = function(profile)
			local total = 0
			if type(profile.BossDefeats) == "table" then
				for _, count in pairs(profile.BossDefeats) do
					if type(count) == "number" then
						total += count
					end
				end
			end
			return total
		end,
	},
}

local function safeOrderedValue(value: number): number
	if value ~= value or value < 0 then
		return 0
	end
	return math.clamp(math.floor(value), 0, MAX_ORDERED_VALUE)
end

local function getZone(): Instance?
	local map = Workspace:FindFirstChild("Map")
	local spawnHub = map and map:FindFirstChild("SpawnHub")
	return spawnHub and spawnHub:FindFirstChild("LeaderboardZone") or nil
end

local function getBoardSurface(boardKey: string): BasePart?
	local zone = getZone()
	if not zone then
		return nil
	end
	for _, desc in ipairs(zone:GetDescendants()) do
		if desc:IsA("BasePart") and desc:GetAttribute("BoardKey") == boardKey then
			return desc
		end
	end
	return nil
end

local function getPlayerName(userId: number): string
	if cachedNames[userId] then
		return cachedNames[userId]
	end
	local name = "User " .. tostring(userId)
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(result) == "string" and result ~= "" then
		name = result
	end
	cachedNames[userId] = name
	return name
end

local function formatValue(value: number, suffix: string): string
	return NumberFormatter.format(value) .. " " .. suffix
end

local function writeLoadedPlayerScores(player: Player, profile)
	if not profile then
		return
	end
	for _, def in ipairs(BOARD_DEFS) do
		local store = stores[def.key]
		if not store then
			continue
		end
		local value = safeOrderedValue(def.metric(profile))
		local byUser = lastSavedValues[def.key]
		if not byUser then
			byUser = {}
			lastSavedValues[def.key] = byUser
		end
		if byUser[player.UserId] == value then
			continue
		end
		byUser[player.UserId] = value
		task.spawn(function()
			local ok, err = pcall(function()
				(store :: OrderedDataStore):SetAsync(tostring(player.UserId), value)
			end)
			if not ok then
				warn(string.format("[LeaderboardService] Failed to save %s for %s: %s", def.key, player.Name, tostring(err)))
			end
		end)
	end
end

local function writeAllLoadedScores()
	for _, player in ipairs(Players:GetPlayers()) do
		writeLoadedPlayerScores(player, DataService.getProfile(player))
	end
end

local function fallbackEntries(def: BoardDef)
	local entries = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = DataService.getProfile(player)
		if profile then
			local value = safeOrderedValue(def.metric(profile))
			if value > 0 or def.key == "Power" or def.key == "Mutations" then
				table.insert(entries, { userId = player.UserId, name = player.Name, value = value })
			end
		end
	end
	table.sort(entries, function(a, b)
		if a.value == b.value then
			return a.name < b.name
		end
		return a.value > b.value
	end)
	while #entries > MAX_ROWS do
		table.remove(entries)
	end
	return entries
end

local function readTopEntries(def: BoardDef)
	local store = stores[def.key]
	if not store then
		return fallbackEntries(def)
	end

	local ok, pages = pcall(function()
		return (store :: OrderedDataStore):GetSortedAsync(false, MAX_ROWS)
	end)
	if not ok or not pages then
		warn("[LeaderboardService] OrderedDataStore read failed for " .. def.key .. ": " .. tostring(pages))
		return fallbackEntries(def)
	end

	local entries = {}
	for _, item in ipairs(pages:GetCurrentPage()) do
		local userId = tonumber(item.key)
		local value = tonumber(item.value) or 0
		if userId and value > 0 then
			table.insert(entries, {
				userId = userId,
				name = getPlayerName(userId),
				value = value,
			})
		end
	end
	if #entries == 0 then
		return fallbackEntries(def)
	end
	return entries
end

local function setText(gui: Instance?, name: string, text: string)
	local label = gui and gui:FindFirstChild(name, true)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function setImage(gui: Instance?, name: string, userId: number?)
	local image = gui and gui:FindFirstChild(name, true)
	if image and image:IsA("ImageLabel") then
		if userId then
			image.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
			image.ImageTransparency = 0
		else
			image.Image = ""
			image.ImageTransparency = 1
		end
	end
end

local function updateBoard(def: BoardDef, entries)
	local surface = getBoardSurface(def.key)
	local gui = surface and surface:FindFirstChild("BoardGui")
	if not gui then
		return
	end

	setText(gui, "BoardTitle", def.title)
	setText(gui, "UpdatedLabel", "Updates every 60 seconds")
	for i = 1, MAX_ROWS do
		local entry = entries[i]
		setText(gui, "Rank" .. i, "#" .. tostring(i))
		setText(gui, "Name" .. i, entry and entry.name or "No record yet")
		setText(gui, "Value" .. i, entry and formatValue(entry.value, def.valueLabel) or "-")
		setImage(gui, "Avatar" .. i, entry and entry.userId or nil)
	end
end

local function clearPodium(rank: number)
	local zone = getZone()
	local folder = zone and zone:FindFirstChild("AvatarDummies")
	local model = folder and folder:FindFirstChild("Top" .. tostring(rank))
	if model then
		model:Destroy()
	end
end

local function anchorDummy(model: Model)
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
			desc.CanTouch = false
			desc.CanQuery = false
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
end

local function updatePodiums(powerEntries)
	local zone = getZone()
	if not zone then
		return
	end
	local folder = zone:FindFirstChild("AvatarDummies")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "AvatarDummies"
		folder.Parent = zone
	end

	for rank = 1, 3 do
		local entry = powerEntries[rank]
		if not entry then
			cachedTopPowerUsers[rank] = nil
			clearPodium(rank)
			continue
		end

		if cachedTopPowerUsers[rank] == entry.userId then
			continue
		end
		cachedTopPowerUsers[rank] = entry.userId
		local old = folder:FindFirstChild("Top" .. tostring(rank))
		if old then
			old:Destroy()
		end

		task.spawn(function()
			local podium = zone:FindFirstChild("Top" .. tostring(rank) .. "Podium", true)
			if not podium or not podium:IsA("BasePart") then
				return
			end
			local ok, model = pcall(function()
				return Players:CreateHumanoidModelFromUserId(entry.userId)
			end)
			if not ok or not model then
				return
			end
			model.Name = "Top" .. tostring(rank)
			pcall(function()
				model:ScaleTo(TOP_DUMMY_SCALE)
			end)
			anchorDummy(model)
			model.Parent = folder
			local height = model:GetExtentsSize().Y
			model:PivotTo(CFrame.new(podium.Position + Vector3.new(0, podium.Size.Y / 2 + height / 2, 0)) * CFrame.Angles(0, -math.pi / 2, 0))
		end)
	end
end

local function refreshDisplays()
	writeAllLoadedScores()
	local powerEntries = nil
	for _, def in ipairs(BOARD_DEFS) do
		local entries = readTopEntries(def)
		updateBoard(def, entries)
		if def.key == "Power" then
			powerEntries = entries
		end
	end
	if powerEntries then
		updatePodiums(powerEntries)
	end
end

local function initStores()
	for _, def in ipairs(BOARD_DEFS) do
		local ok, result = pcall(function()
			return DataStoreService:GetOrderedDataStore(def.storeName)
		end)
		if ok then
			stores[def.key] = result
		else
			stores[def.key] = nil
			warn("[LeaderboardService] OrderedDataStore unavailable for " .. def.key .. ": " .. tostring(result))
		end
	end
end

local function spinDummies()
	task.spawn(function()
		while true do
			task.wait(0.1)
			local zone = getZone()
			local folder = zone and zone:FindFirstChild("AvatarDummies")
			if folder then
				dummySpin = (dummySpin + 0.018) % (math.pi * 2)
				for rank = 1, 3 do
					local model = folder:FindFirstChild("Top" .. tostring(rank))
					local podium = zone and zone:FindFirstChild("Top" .. tostring(rank) .. "Podium", true)
					if model and model:IsA("Model") and podium and podium:IsA("BasePart") then
						local height = model:GetExtentsSize().Y
						model:PivotTo(CFrame.new(podium.Position + Vector3.new(0, podium.Size.Y / 2 + height / 2, 0)) * CFrame.Angles(0, -math.pi / 2 + dummySpin, 0))
					end
				end
			end
		end
	end)
end

function LeaderboardService.start(deps)
	DataService = deps.DataService
	initStores()
	task.defer(refreshDisplays)
	spinDummies()

	if DataService.onBeforeProfileRemoved then
		DataService.onBeforeProfileRemoved(function(player, profile)
			writeLoadedPlayerScores(player, profile)
		end)
	end

	task.spawn(function()
		while true do
			task.wait(REFRESH_INTERVAL)
			refreshDisplays()
		end
	end)
end

return LeaderboardService
