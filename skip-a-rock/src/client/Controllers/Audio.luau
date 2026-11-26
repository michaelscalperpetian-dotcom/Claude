--!strict
-- Sound. Effects use clips that ship with every Roblox client
-- (rbxasset://sounds/...), so they always load and need no uploads; pitch and
-- layering turn a few clips into soft, distinct cues. Skips and splashes play
-- out on the lake where they happen. Optional music: Config.MUSIC_TRACKS.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local UI = require(script.Parent.Parent.Lib.UI)

local Audio = {}

-- Built-in client sounds (content/sounds in the Roblox install).
local CLIPS: { [string]: string } = {
	water = "rbxasset://sounds/impact_water.mp3",
	tick = "rbxasset://sounds/volume_slider.ogg",
	whoosh = "rbxasset://sounds/action_jump.mp3",
	thud = "rbxasset://sounds/action_jump_land.mp3",
}

-- A cue is one or more notes: { clip, speed, volume, delay }.
type Note = { clip: string, speed: number, volume: number, delay: number? }

local CUES: { [string]: { Note } } = {
	click = { { clip = "tick", speed = 1.2, volume = 0.35 } },
	open = { { clip = "tick", speed = 0.9, volume = 0.3 } },
	throw = { { clip = "whoosh", speed = 1.5, volume = 0.25 } },
	good = {
		{ clip = "tick", speed = 1.3, volume = 0.35 },
		{ clip = "tick", speed = 1.65, volume = 0.35, delay = 0.09 },
	},
	bad = { { clip = "tick", speed = 0.7, volume = 0.35 } },
	rare = {
		{ clip = "tick", speed = 1.4, volume = 0.4 },
		{ clip = "tick", speed = 1.75, volume = 0.4, delay = 0.09 },
		{ clip = "tick", speed = 2.1, volume = 0.45, delay = 0.18 },
	},
	pickup = {
		{ clip = "thud", speed = 1.9, volume = 0.35 },
		{ clip = "tick", speed = 1.6, volume = 0.35, delay = 0.06 },
	},
}

local templates: { [string]: Sound } = {}
local sfx: SoundGroup? = nil
local music: SoundGroup? = nil

local function newSound(clip: string): Sound?
	local template = templates[clip]
	if not template then
		return nil
	end
	return template:Clone()
end

local function playNote(note: Note)
	local sound = newSound(note.clip)
	if not sound then
		return
	end
	sound.PlaybackSpeed = note.speed
	sound.Volume = note.volume
	sound.SoundGroup = sfx
	sound.Parent = sfx
	sound:Play()
	task.delay(4, function()
		sound:Destroy()
	end)
end

-- Plays a cue on the player's own speakers (not in the world).
function Audio.play(cue: string)
	local notes = CUES[cue]
	if not notes then
		return
	end
	for _, note in notes do
		if note.delay then
			task.delay(note.delay, playNote, note)
		else
			playNote(note)
		end
	end
end

-- Plays a clip out in the world at `position` (heard louder up close).
function Audio.at(position: Vector3, clip: string, speed: number, volume: number)
	local sound = newSound(clip)
	if not sound then
		return
	end
	-- (Terrain sits at the origin, so an attachment's Position is world space)
	local anchor = Instance.new("Attachment")
	anchor.Name = "Sound"
	anchor.Position = position
	anchor.Parent = Workspace.Terrain
	sound.PlaybackSpeed = speed
	sound.Volume = volume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 12
	sound.RollOffMaxDistance = 220
	sound.SoundGroup = sfx
	sound.Parent = anchor
	sound:Play()
	task.delay(3, function()
		anchor:Destroy()
	end)
end

-- One skip touching the water: a "plip" that rises in pitch as the hops shorten.
function Audio.skip(position: Vector3, index: number)
	Audio.at(position, "water", math.min(1.6 + index * 0.06, 2.8), 0.32)
end

-- The stone sinking (or a dive).
function Audio.splash(position: Vector3, big: boolean)
	Audio.at(position, "water", if big then 0.8 else 1.1, if big then 0.55 else 0.4)
end

local function startMusic(group: SoundGroup)
	local tracks = Config.MUSIC_TRACKS
	if #tracks == 0 then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "Music"
	sound.Volume = 0.35
	sound.SoundGroup = group
	sound.Parent = group
	local index = math.random(1, #tracks)
	local function playNext()
		sound.SoundId = "rbxassetid://" .. tracks[index]
		index = index % #tracks + 1
		sound:Play()
	end
	sound.Ended:Connect(playNext)
	playNext()
end

function Audio.init()
	local effects = Instance.new("SoundGroup")
	effects.Name = "Effects"
	effects.Volume = 0.9
	effects.Parent = SoundService
	sfx = effects
	local tunes = Instance.new("SoundGroup")
	tunes.Name = "Music"
	tunes.Volume = 0.7
	tunes.Parent = SoundService
	music = tunes
	for name, id in CLIPS do
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = id
		templates[name] = sound
	end
	UI.onClick = function()
		Audio.play("click")
	end
end

function Audio.start()
	if music then
		startMusic(music)
	end
end

return Audio
