--!strict
-- Sends each player a snapshot of their own state whenever it changes
-- (batched, at most 5 times per second), plus a full snapshot when their
-- client says it's ready. Clients render; they never compute anything that matters.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local Data = require(script.Parent.Data)
local Sessions = require(script.Parent.Sessions)
local Stats = require(script.Parent.Parent.Lib.Stats)

local State = {}

local dirty: { [Player]: boolean } = {}
local clientReady: { [Player]: boolean } = {}

function State.markDirty(player: Player)
	dirty[player] = true
end

function State.snapshot(player: Player): Types.Snapshot?
	local profile = Data.get(player)
	local session = Sessions.get(player)
	if not profile or not session then
		return nil
	end
	local now = Clock.now()
	local passes: { [string]: boolean } = {}
	for key in session.passes do
		passes[key] = true
	end
	for key in session.fakePasses do
		passes[key] = true
	end
	return {
		coins = profile.coins,
		pendingCoins = profile.pendingCoins,
		incomePerSecond = Stats.incomePerSecond(profile, session, now),
		multiplier = Stats.multiplier(profile, session, now),
		dinos = profile.dinos,
		incubators = profile.incubators,
		tray = profile.tray,
		dex = profile.dex,
		upgrades = profile.upgrades,
		boosts = profile.boosts,
		instantHatchTokens = profile.instantHatchTokens,
		streak = profile.streak,
		clubClaimDay = profile.club.lastClaimDay,
		tutorial = profile.tutorial,
		starterPackBought = profile.starterPackBought,
		shopBought = profile.shop,
		likes = profile.likes,
		passes = passes,
		subscribed = session.subscribed,
		restricted = session.restricted,
		plotIndex = session.plotIndex,
		maxSlots = Stats.maxSlots(profile, session),
		maxIncubators = Stats.maxIncubators(profile),
		lockUntil = session.lockUntil,
		lockCooldownUntil = session.lockCooldownUntil,
		shieldUntil = Stats.shieldUntil(profile),
		friendsHere = Stats.friendsHere(session),
		isDev = Stats.isDev(player),
		raidsEnabled = Stats.raidsEnabled(),
		riding = session.riding,
		carrying = session.carry ~= nil,
	}
end

local function send(player: Player)
	local snapshot = State.snapshot(player)
	if snapshot then
		Net.fire(player, "State", snapshot)
	end
end

function State.init()
	Net.on("Ready", 1, 3, function(player: Player)
		clientReady[player] = true
		send(player)
	end)
	Sessions.Leaving:connect(function(player: Player)
		dirty[player] = nil
		clientReady[player] = nil
	end)
end

function State.start()
	while true do
		task.wait(0.2)
		for player in dirty do
			dirty[player] = nil
			if clientReady[player] and player.Parent ~= nil then
				send(player)
			end
		end
	end
end

return State
