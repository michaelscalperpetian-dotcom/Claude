--!strict
-- Sound effects and music. Effects use the sounds that ship with every Roblox
-- client (rbxasset://sounds/...), so they always load and need no uploads;
-- pitch and layering turn a few clips into distinct cues. Music plays the
-- tracks listed in Config.MUSIC_TRACKS, if any. Both obey the Settings switches.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)
local Effects = require(script.Parent.Effects)
local SettingsUI = require(script.Parent.SettingsUI)
local Toasts = require(script.Parent.Toasts)
local UI = require(script.Parent.Parent.Lib.UI)

local Audio = {}

-- Built-in client sounds (content/sounds in the Roblox install).
local CLIPS: { [string]: string } = {
	tick = "rbxasset://sounds/volume_slider.ogg",
	whoosh = "rbxasset://sounds/action_jump.mp3",
	thud = "rbxasset://sounds/action_jump_land.mp3",
	boom = "rbxasset://sounds/impact_explosion_03.mp3",
	wind = "rbxasset://sounds/action_falling.ogg",
	splash = "rbxasset://sounds/impact_water.mp3",
}

-- A cue is one or more clips: { clip, speed, volume, delay }.
type Note = { clip: string, speed: number, volume: number, delay: number? }

local CUES: { [string]: { Note } } = {
	click = { { clip = "tick", speed = 1.15, volume = 0.5 } },
	open = { { clip = "whoosh", speed = 1.6, volume = 0.3 } },
	coins = {
		{ clip = "tick", speed = 1.5, volume = 0.55 },
		{ clip = "tick", speed = 1.75, volume = 0.55, delay = 0.07 },
		{ clip = "tick", speed = 2.0, volume = 0.6, delay = 0.14 },
	},
	good = {
		{ clip = "tick", speed = 1.3, volume = 0.45 },
		{ clip = "tick", speed = 1.65, volume = 0.45, delay = 0.08 },
	},
	bad = {
		{ clip = "tick", speed = 0.7, volume = 0.5 },
		{ clip = "tick", speed = 0.55, volume = 0.5, delay = 0.1 },
	},
	rare = {
		{ clip = "tick", speed = 1.4, volume = 0.5 },
		{ clip = "tick", speed = 1.7, volume = 0.5, delay = 0.08 },
		{ clip = "tick", speed = 2.1, volume = 0.55, delay = 0.16 },
	},
	event = { { clip = "wind", speed = 1.1, volume = 0.35 } },
	crack = { { clip = "thud", speed = 1.8, volume = 0.6 } },
	pop = {
		{ clip = "boom", speed = 1.5, volume = 0.3 },
		{ clip = "tick", speed = 1.9, volume = 0.5, delay = 0.05 },
	},
	big = { { clip = "boom", speed = 0.95, volume = 0.4, delay = 0.08 } },
}

local templates: { [string]: Sound } = {}
local sfxGroup: SoundGroup
local musicGroup: SoundGroup
local music: Sound? = nil

local function enabled(key: string): boolean
	return SettingsUI.get(key)
end

local function playNote(note: Note)
	local template = templates[note.clip]
	if not template then
		return
	end
	local sound = template:Clone()
	sound.PlaybackSpeed = note.speed
	sound.Volume = note.volume
	sound.Parent = sfxGroup
	sound:Play()
	task.delay(4, function()
		sound:Destroy()
	end)
end

function Audio.play(cue: string)
	if not enabled("sfx") then
		return
	end
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

-- ===== Music =====

local function nextTrack(): number?
	local tracks = Config.MUSIC_TRACKS
	if #tracks == 0 then
		return nil
	end
	return tracks[math.random(1, #tracks)]
end

local function updateMusic()
	local on = enabled("music") and #Config.MUSIC_TRACKS > 0
	if on and not music then
		local id = nextTrack()
		if not id then
			return
		end
		local sound = Instance.new("Sound")
		sound.Name = "Music"
		sound.SoundId = "rbxassetid://" .. id
		sound.Volume = 0.3
		sound.Parent = musicGroup
		sound.Ended:Connect(function()
			local following = nextTrack()
			if following and music == sound then
				sound.SoundId = "rbxassetid://" .. following
				sound:Play()
			end
		end)
		sound:Play()
		music = sound
	elseif not on and music then
		music:Destroy()
		music = nil
	end
end

function Audio.init()
	sfxGroup = Instance.new("SoundGroup")
	sfxGroup.Name = "SFX"
	sfxGroup.Volume = 0.8
	sfxGroup.Parent = SoundService
	musicGroup = Instance.new("SoundGroup")
	musicGroup.Name = "Music"
	musicGroup.Volume = 0.6
	musicGroup.Parent = SoundService
	for name, id in CLIPS do
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = id
		sound.Parent = sfxGroup
		templates[name] = sound
	end

	UI.onClick = function()
		Audio.play("click")
	end
	UI.onOpen = function()
		Audio.play("open")
	end
	Toasts.onShow = function(style: string)
		if style == "good" or style == "bad" or style == "rare" or style == "event" then
			Audio.play(style)
		end
	end
	Effects.onCrack = function()
		Audio.play("crack")
	end
	Effects.onCoins = function()
		Audio.play("coins")
	end
	Effects.onReveal = function(rarity: string)
		Audio.play("pop")
		if rarity == "Epic" or rarity == "Legendary" or rarity == "Secret" then
			Audio.play("big")
		end
	end
	SettingsUI.changed = function(key: string, _on: boolean)
		if key == "music" then
			updateMusic()
		end
	end
end

function Audio.start()
	-- the saved settings arrive with the first state snapshot
	task.wait(2)
	updateMusic()
end

return Audio
