--!strict
-- Runtime (not saved) state for each player in this server. The saved
-- profile lives in Data.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)

export type Session = {
	player: Player,
	ready: boolean,
	chargeStart: number?, -- os.clock() when they started winding up a throw
	lastThrowAt: number, -- os.clock() of their last throw
}

local Sessions = {}

Sessions.Ready = Signal.new() :: Signal.Signal<Player>
Sessions.Leaving = Signal.new() :: Signal.Signal<Player>

local sessions: { [Player]: Session } = {}

function Sessions.create(player: Player): Session
	local session: Session = {
		player = player,
		ready = false,
		chargeStart = nil,
		lastThrowAt = -math.huge,
	}
	sessions[player] = session
	return session
end

function Sessions.get(player: Player): Session?
	return sessions[player]
end

-- The session, but only once the player has finished loading.
function Sessions.getReady(player: Player): Session?
	local session = sessions[player]
	if session and session.ready then
		return session
	end
	return nil
end

-- Every session that finished loading.
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
