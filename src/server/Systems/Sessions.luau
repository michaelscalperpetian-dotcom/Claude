--!strict
-- Runtime (not saved) state for each player in this server. Systems read and
-- write their own fields here; the saved profile lives in Data.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)

export type Carry = {
	victim: Player,
	eggId: string,
	species: string,
	model: Model?,
	startedAt: number,
	arriveAfter: number, -- can't legitimately be home before this (walking speed)
}

export type Session = {
	player: Player,
	ready: boolean,
	plotIndex: number,
	passes: { [string]: boolean },
	fakePasses: { [string]: boolean }, -- Studio/QA only
	subscribed: boolean,
	restricted: boolean, -- PolicyService: paid random items restricted
	tradingAllowed: boolean,
	friendIds: { [number]: boolean }, -- friends currently in this server
	lockUntil: number,
	lockCooldownUntil: number,
	pendingInstantHatch: string?,
	carry: Carry?,
	stunnedUntil: number,
	riding: string?,
	mount: Model?,
	originalHipHeight: number?,
	lastAdAt: number,
}

local Sessions = {}

Sessions.Ready = Signal.new() :: Signal.Signal<Player>
Sessions.Leaving = Signal.new() :: Signal.Signal<Player>

local sessions: { [Player]: Session } = {}

function Sessions.create(player: Player): Session
	local session: Session = {
		player = player,
		ready = false,
		plotIndex = 0,
		passes = {},
		fakePasses = {},
		subscribed = false,
		restricted = true, -- safe default until PolicyService answers
		tradingAllowed = false,
		friendIds = {},
		lockUntil = 0,
		lockCooldownUntil = 0,
		pendingInstantHatch = nil,
		carry = nil,
		stunnedUntil = 0,
		riding = nil,
		mount = nil,
		originalHipHeight = nil,
		lastAdAt = 0,
	}
	sessions[player] = session
	return session
end

function Sessions.get(player: Player): Session?
	return sessions[player]
end

-- Only sessions that finished loading (profile + plot ready).
function Sessions.ready(): { Session }
	local list: { Session } = {}
	for _, s in sessions do
		if s.ready then
			table.insert(list, s)
		end
	end
	return list
end

function Sessions.remove(player: Player)
	sessions[player] = nil
end

return Sessions
