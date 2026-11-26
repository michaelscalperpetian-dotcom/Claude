--!strict
-- Throwing. The client says when the player starts winding up (BeginCharge)
-- and when they let go (Release, with how long they held). The server checks
-- the throw makes sense, works out every skip itself, scales it by the
-- player's strength, rock and rebirths, pays out, and tells everyone so all
-- screens draw the same rock flying out to sea.
--
-- The power comes from the client's hold time so the needle the player sees
-- is the needle that counts, but it must agree with the server's own timing
-- (CLOCK_SLACK), so nobody can claim a hold that never happened.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Net = require(ReplicatedStorage.Shared.Net)
local Sea = require(ReplicatedStorage.Shared.Sea)
local Skip = require(ReplicatedStorage.Shared.Skip)
local Types = require(ReplicatedStorage.Shared.Types)
local Notify = require(script.Parent.Parent.Lib.Notify)
local Data = require(script.Parent.Data)
local DayNight = require(script.Parent.DayNight)
local Progress = require(script.Parent.Progress)
local Sessions = require(script.Parent.Sessions)
local Shop = require(script.Parent.Shop)

local Throws = {}

Throws.CLOCK_SLACK = 0.3 -- seconds the client's hold time may differ from the server's
Throws.HAND_HEIGHT = 1.2 -- the rock leaves the hand this far above the root part

export type Rejection =
	"notReady"
	| "noCharge"
	| "tooShort"
	| "tooLong"
	| "cooldown"
	| "noCharacter"
	| "notHere"

local MESSAGES: { [string]: string } = {
	notHere = "Walk down to the beach or onto a pier to throw",
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
function Throws.release(player: Player, rawHeld: unknown): (Types.ThrowEvent?, Rejection?)
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
	local position = root.CFrame.Position
	if not Sea.canThrowFrom(position) then
		return nil, "notHere"
	end

	local stats = Economy.statsOf(profile)
	local rock = Economy.rockOf(stats)
	local night = DayNight.isNight()
	local outcome = Skip.outcome(Skip.power(held), rock, rand)
	local scale = Economy.distanceMultiplier(stats, night)
	local hops: { number } = {}
	for i, hop in outcome.hops do
		hops[i] = hop * scale
	end
	local distance = outcome.distance * scale
	local coins = Economy.coinsFor(distance, outcome.skips, outcome.perfect, stats)
	session.lastThrowAt = now
	local newBest = Progress.recordThrow(player, {
		distance = distance,
		skips = outcome.skips,
		perfect = outcome.perfect,
		coins = coins,
	})

	local origin = position + Vector3.new(0, Throws.HAND_HEIGHT, 0.8)
	local event: Types.ThrowEvent = {
		userId = player.UserId,
		rock = rock.id,
		origin = origin,
		entry = Sea.entry(position),
		hops = hops,
		skips = outcome.skips,
		distance = distance,
		coins = coins,
		verdict = outcome.verdict,
		perfect = outcome.perfect,
		power = outcome.power,
		night = night,
		newBest = newBest,
	}
	Net.fireAll("Throw", event)
	Shop.hideHeld(player, Config.THROW_COOLDOWN)
	return event, nil
end

function Throws.init()
	Net.on("BeginCharge", 4, 6, beginCharge)
	Net.on("CancelCharge", 4, 6, cancelCharge)
	Net.on("Release", 4, 6, function(player: Player, held: unknown)
		local _, rejection = Throws.release(player, held)
		local message = rejection and MESSAGES[rejection]
		if message then
			Notify.send(player, message, "bad")
		end
	end)
end

return Throws
