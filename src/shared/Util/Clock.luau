--!strict
-- One clock for everything. Uses the server's Unix time (synced to clients), so
-- timers, day/night and storms line up on every screen.
--
-- `cycleNow()` adds a debug offset (set by the cheat panel in Studio) so you can
-- skip to night or a storm while testing. Saved timestamps always use `now()`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = {}

Clock.OFFSET_ATTRIBUTE = "DebugCycleOffset"

function Clock.now(): number
	return workspace:GetServerTimeNow()
end

function Clock.cycleNow(): number
	local offset = ReplicatedStorage:GetAttribute(Clock.OFFSET_ATTRIBUTE)
	if typeof(offset) == "number" then
		return Clock.now() + offset
	end
	return Clock.now()
end

return Clock
