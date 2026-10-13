--!strict
-- Dino nicknames. A player types a name; Roblox's text filter decides what
-- everyone may see. The name as typed stays on the server (profile.nicknames)
-- and is filtered again on every join, because filter rules change. Dinos
-- only carry the filtered, broadcast-safe name (dino.name).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local Data = require(script.Parent.Data)
local Nest = require(script.Parent.Nest)
local Plots = require(script.Parent.Plots)
local Sessions = require(script.Parent.Sessions)
local State = require(script.Parent.State)
local Notify = require(script.Parent.Parent.Lib.Notify)

local Nicknames = {}

local busy: { [Player]: boolean } = {}

-- Collapses whitespace and control characters; nil for invalid UTF-8.
function Nicknames.clean(text: string): string?
	if utf8.len(text) == nil then
		return nil
	end
	local cleaned = string.gsub(text, "%c", " ")
	cleaned = string.gsub(cleaned, "%s+", " ")
	return string.match(cleaned, "^%s*(.-)%s*$") or ""
end

-- What everyone may see, or nil if the filter didn't answer or hid any of it.
local function filter(player: Player, text: string): (string?, boolean)
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, player.UserId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(result) ~= "string" then
		return nil, false
	end
	local blocked = string.find(result, "#", 1, true) ~= nil
		and string.find(text, "#", 1, true) == nil
	return if blocked then nil else result, true
end

local function setName(player: Player, dino: Types.DinoRecord, name: string?)
	dino.name = name
	Plots.syncDinos(player)
	State.markDirty(player)
end

local function rename(player: Player, dinoId: string, text: string)
	local profile = Data.get(player)
	if not profile or busy[player] or not Nest.findDino(profile, dinoId) then
		return
	end
	local name = Nicknames.clean(text)
	if not name then
		return
	end
	if name == "" then
		profile.nicknames[dinoId] = nil
		local dino = Nest.findDino(profile, dinoId)
		if dino then
			setName(player, dino, nil)
		end
		return
	end
	if (utf8.len(name) or 0) > Config.NICKNAME_MAX_LENGTH then
		Notify.send(player, `Names can be up to {Config.NICKNAME_MAX_LENGTH} letters long.`, "bad")
		return
	end
	busy[player] = true
	local filtered, answered = filter(player, name)
	busy[player] = nil
	-- The dino may have been sold (or the player left) while the filter ran.
	local current = Data.get(player)
	local dino = if current then Nest.findDino(current, dinoId) else nil
	if not current or not dino then
		return
	end
	if not answered then
		Notify.send(player, "Couldn't check that name right now. Try again in a moment!", "bad")
	elseif not filtered then
		Notify.send(player, "That name isn't allowed. Try another one!", "bad")
	else
		current.nicknames[dinoId] = name
		setName(player, dino, filtered)
		Notify.send(player, `🏷 Say hi to {filtered}!`, "good")
	end
end

-- Runs every saved name through the filter again (on join).
function Nicknames.refresh(player: Player)
	local profile = Data.get(player)
	if not profile then
		return
	end
	local changed = false
	for dinoId, raw in table.clone(profile.nicknames) do
		if not Nest.findDino(profile, dinoId) then
			profile.nicknames[dinoId] = nil
			continue
		end
		local filtered, answered = filter(player, raw)
		if Data.get(player) ~= profile then
			return -- left while filtering
		end
		local dino = Nest.findDino(profile, dinoId)
		if answered and dino and profile.nicknames[dinoId] == raw then
			if not filtered then
				profile.nicknames[dinoId] = nil
			end
			if dino.name ~= filtered then
				dino.name = filtered
				changed = true
			end
		end
	end
	if changed then
		Plots.syncDinos(player)
		State.markDirty(player)
	end
end

function Nicknames.init()
	Net.on("RenameDino", 0.5, 3, function(player: Player, dinoId: unknown, text: unknown)
		if
			typeof(dinoId) == "string"
			and #dinoId <= 20
			and typeof(text) == "string"
			and #text <= 200
		then
			rename(player, dinoId, text)
		end
	end)
	Nest.DinoRemoved:connect(function(player: Player, dino: Types.DinoRecord)
		local profile = Data.get(player)
		if profile then
			profile.nicknames[dino.id] = nil
		end
	end)
	Sessions.Ready:connect(function(player: Player)
		task.spawn(Nicknames.refresh, player)
	end)
	Sessions.Leaving:connect(function(player: Player)
		busy[player] = nil
	end)
end

return Nicknames
