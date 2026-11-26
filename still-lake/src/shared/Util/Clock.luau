--!strict
-- One clock for everything: the server's Unix time (synced to clients), so the
-- sun sets at the same moment on every screen.

local Clock = {}

function Clock.now(): number
	return workspace:GetServerTimeNow()
end

return Clock
