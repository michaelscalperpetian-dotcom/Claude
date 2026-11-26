--!strict
-- Throwing. The client says when the player starts winding up (BeginCharge)
-- and when they let go (Release, with the way they're facing and how long
-- they held). The server checks the throw makes sense, works out every skip
-- itself, saves the result and tells everyone so all screens draw the same
-- stone.
--
-- The power comes from the client's hold time so the needle the player sees
-- is the needle that counts, but it must agree with the server's own timing
-- (CLOCK_SLACK), so nobody can claim a hold that never happened.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Lake = require(ReplicatedStorage.Shared.Lake)
local Net = require(ReplicatedStorage.Shared.Net)
local Skip = require(ReplicatedStorage.Shared.Skip)
local StoneData = require(ReplicatedStorage.Shared.Data.StoneData)
local Types = require(ReplicatedStorage.Shared.Types)
local Notify = require(script.Parent.Parent.Lib.Notify)
local Data = require(script.Parent.Data)
local DayNight = require(script.Parent.DayNight)
local Progress = require(script.Parent.Progress)
local Sessions = require(script.Parent.Sessions)
local Stones = require(script.Parent.Stones)

local Throws = {}

Throws.CLOCK_SLACK = 0.3 -- seconds the client's hold time may differ from the server's
Throws.HAND_HEIGHT = 1.2 -- the stone leaves the hand this far above the root part

export type Rejection =
	"notReady"
	| "noCharge"
	| "tooShort"
	| "tooLong"
	| "cooldown"
	| "noCharacter"
	| "tooHigh"
	| "badDirection"
	| "notFacingWater"
	| "tooFar"
	| "noRoom"

local MESSAGES: { [string]: string } = {
	notFacingWater = "Face the lake to throw",
	tooFar = "Walk a little closer to the water",
	noRoom = "Not enough open water that way",
	tooHigh = "Climb down to throw",
}

local random = Random.new()

local function rand(a: number, b: number): number
	return random:NextNumber(a, b)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function beginCharge(player: Player)
	local session = Sessions.getReady(player)
	if session then
		session.chargeStart = os.clock()
	end
end

local function cancelCharge(player: Player)
	local session = Sessions.get(player)
	if session then
		session.chargeStart = nil
	end
end

-- Checks and performs one throw. Returns the event sent to everyone, or why
-- it was refused.
function Throws.release(
	player: Player,
	rawDirection: unknown,
	rawHeld: unknown
): (Types.ThrowEvent?, Rejection?)
	local session = Sessions.getReady(player)
	local profile = Data.get(player)
	if not session or not profile then
		return nil, "notReady"
	end
	local started = session.chargeStart
	session.chargeStart = nil
	if not started then
		return nil, "noCharge"
	end
	local now = os.clock()
	local serverHeld = now - started
	local held = serverHeld
	if type(rawHeld) == "number" and rawHeld == rawHeld then
		held = math.clamp(rawHeld, serverHeld - Throws.CLOCK_SLACK, serverHeld + Throws.CLOCK_SLACK)
	end
	if held < Config.MIN_CHARGE_SECONDS then
		return nil, "tooShort"
	end
	if held > Config.MAX_CHARGE_SECONDS then
		return nil, "tooLong"
	end
	if now - session.lastThrowAt < Config.THROW_COOLDOWN then
		return nil, "cooldown"
	end
	local root = rootOf(player)
	if not root then
		return nil, "noCharacter"
	end
	if root.CFrame.Position.Y > Config.MAX_THROW_HEIGHT then
		return nil, "tooHigh"
	end
	if typeof(rawDirection) ~= "Vector3" then
		return nil, "badDirection"
	end
	local direction = Lake.flatten(rawDirection :: Vector3)
	if not direction then
		return nil, "badDirection"
	end
	local entry, reach = Lake.entry(root.CFrame.Position, direction)
	if not entry then
		return nil, "notFacingWater"
	end
	if reach > Config.THROW_REACH then
		return nil, "tooFar"
	end
	local available = Lake.openWater(entry, direction)
	if available < Lake.MIN_OPEN_WATER then
		return nil, "noRoom"
	end

	local stone = (
		StoneData.get(profile.equipped) or StoneData.get(StoneData.STARTER)
	) :: StoneData.Stone
	local night = DayNight.isNight()
	local outcome =
		Skip.outcome(Skip.power(held), stone, rand, { night = night, available = available })
	session.lastThrowAt = now
	local records = Progress.recordThrow(player, outcome, night)

	local event: Types.ThrowEvent = {
		userId = player.UserId,
		stone = stone.id,
		origin = root.CFrame.Position + Vector3.new(0, Throws.HAND_HEIGHT, 0) + direction * 0.8,
		entry = entry,
		direction = direction,
		hops = outcome.hops,
		skips = outcome.skips,
		distance = outcome.distance,
		verdict = outcome.verdict,
		perfect = outcome.perfect,
		power = outcome.power,
		night = night,
		newBestSkips = records.newBestSkips,
		newBestDistance = records.newBestDistance,
	}
	Net.fireAll("Throw", event)
	Stones.hideHeld(player, Config.THROW_COOLDOWN)
	return event, nil
end

function Throws.init()
	Net.on("BeginCharge", 4, 6, beginCharge)
	Net.on("CancelCharge", 4, 6, cancelCharge)
	Net.on("Release", 4, 6, function(player: Player, direction: unknown, held: unknown)
		local _, rejection = Throws.release(player, direction, held)
		local message = rejection and MESSAGES[rejection]
		if message then
			Notify.send(player, message, "bad")
		end
	end)
end

return Throws
