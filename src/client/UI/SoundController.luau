--!strict
-- Erstellt SoundGroups und Sound-Instanzen einmalig im SoundService.
-- Spielt Sounds auf Client-Seite ab. Reagiert auf Settings.Music/SFX-Toggle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Sounds"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlaySound = Remotes:WaitForChild("PlaySound") :: RemoteEvent

local SoundController = {}

local groupInstances: { [string]: SoundGroup } = {}
local soundInstances: { [string]: Sound } = {}
local musicSound: Sound? = nil

local function ensureGroup(name: string): SoundGroup
	local existing = SoundService:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	local g = Instance.new("SoundGroup")
	g.Name = name
	g.Volume = 1
	g.Parent = SoundService
	return g
end

local function build()
	for _, groupName in pairs(Sounds.Groups) do
		groupInstances[groupName] = ensureGroup(groupName)
	end

	for name, def in pairs(Sounds.Sounds) do
		if def.id == "0" or def.id == "rbxassetid://0" or def.id == "" then
			continue
		end
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = def.id
		sound.Volume = def.volume or 0.5
		local groupName = Sounds.Groups[def.group]
		if groupName and groupInstances[groupName] then
			sound.SoundGroup = groupInstances[groupName]
		end
		sound.Parent = SoundService
		soundInstances[name] = sound
		if name == "BgMusic" then
			sound.Looped = true
			musicSound = sound
		end
	end
end

function SoundController.play(name: string)
	local sound = soundInstances[name]
	if not sound then
		return
	end
	-- Sound:Play startet eine neue Wiedergabe ohne den vorherigen abzubrechen --
	-- bei Click-Spam waere das hektisch, also kappen wir auf <= 1/Frame.
	sound.TimePosition = 0
	sound:Play()
end

-- Settings:
--   { Music = bool, SFX = bool, VFX = bool, Haptik = bool }
function SoundController.applySettings(settings)
	if not settings then
		return
	end
	local musicGroup = groupInstances[Sounds.Groups.Music]
	local sfxGroup = groupInstances[Sounds.Groups.SFX]
	local uiGroup = groupInstances[Sounds.Groups.UI]
	if musicGroup then
		musicGroup.Volume = if settings.Music == false then 0 else 1
	end
	if sfxGroup then
		sfxGroup.Volume = if settings.SFX == false then 0 else 1
	end
	if uiGroup then
		-- UI-Sounds laufen am SFX-Toggle mit.
		uiGroup.Volume = if settings.SFX == false then 0 else 1
	end

	if musicSound then
		if settings.Music == false then
			-- Volle Pause statt nur stummschalten, spart CPU.
			musicSound:Pause()
		else
			if not musicSound.IsPlaying then
				musicSound:Play()
			end
		end
	end
end

function SoundController.start()
	build()
	PlaySound.OnClientEvent:Connect(function(soundName)
		if type(soundName) ~= "string" then
			return
		end
		SoundController.play(soundName)
	end)
end

return SoundController
