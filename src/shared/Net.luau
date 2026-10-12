--!strict
-- Every remote in the game, created by the server in one folder from one list.
-- Server handlers go through a per-player, per-remote rate limit before running.
-- Arguments from clients are hostile until validated (see server systems).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type ClientEvent =
	"Ready"
	| "BuyEgg"
	| "HatchEgg"
	| "WarmEgg"
	| "IncubateTrayEgg"
	| "SellTrayEgg"
	| "SellDino"
	| "BuyUpgrade"
	| "LockGate"
	| "ClaimStreak"
	| "ClaimClub"
	| "PromptPurchase"
	| "Ride"
	| "Roar"
	| "TutorialAction"
	| "WatchAd"
	| "Cheat"
	| "ClaimQuest"
	| "ClaimDex"
	| "RedeemCode"
	| "SetSetting"
	| "SetBuddy"

export type ServerEvent = "State" | "Notify" | "Effect"

local CLIENT_EVENTS: { ClientEvent } = {
	"Ready",
	"BuyEgg",
	"HatchEgg",
	"WarmEgg",
	"IncubateTrayEgg",
	"SellTrayEgg",
	"SellDino",
	"BuyUpgrade",
	"LockGate",
	"ClaimStreak",
	"ClaimClub",
	"PromptPurchase",
	"Ride",
	"Roar",
	"TutorialAction",
	"WatchAd",
	"Cheat",
	"ClaimQuest",
	"ClaimDex",
	"RedeemCode",
	"SetSetting",
	"SetBuddy",
}

local SERVER_EVENTS: { ServerEvent } = { "State", "Notify", "Effect" }

local FOLDER_NAME = "Remotes"

local Net = {}

local remotes: { [string]: RemoteEvent } = {}

-- Token bucket per player per remote.
type Bucket = { tokens: number, last: number }
local buckets: { [Player]: { [string]: Bucket } } = {}

local function allow(player: Player, key: string, ratePerSecond: number, burst: number): boolean
	local now = os.clock()
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end
	local b = playerBuckets[key]
	if not b then
		b = { tokens = burst, last = now }
		playerBuckets[key] = b
	end
	b.tokens = math.min(burst, b.tokens + (now - b.last) * ratePerSecond)
	b.last = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

-- Server: create every remote. Called once by the server entry point.
function Net.serverInit()
	assert(RunService:IsServer(), "Net.serverInit is server-only")
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for _, name in CLIENT_EVENTS do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		remotes[name] = remote
	end
	for _, name in SERVER_EVENTS do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		remotes[name] = remote
	end
	folder.Parent = ReplicatedStorage
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

local function getRemote(name: string): RemoteEvent
	local cached = remotes[name]
	if cached then
		return cached
	end
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	local remote = folder:WaitForChild(name)
	assert(remote:IsA("RemoteEvent"), `{name} is not a RemoteEvent`)
	remotes[name] = remote
	return remote
end

-- Server: handle a client event. Requests over the rate limit are dropped silently.
function Net.on(
	name: ClientEvent,
	ratePerSecond: number,
	burst: number,
	handler: (Player, ...unknown) -> ()
)
	getRemote(name).OnServerEvent:Connect(function(player: Player, ...: unknown)
		if not allow(player, name, ratePerSecond, burst) then
			return
		end
		handler(player, ...)
	end)
end

function Net.fire(player: Player, name: ServerEvent, ...: any)
	getRemote(name):FireClient(player, ...)
end

function Net.fireAll(name: ServerEvent, ...: any)
	getRemote(name):FireAllClients(...)
end

-- Client: send a request to the server.
function Net.send(name: ClientEvent, ...: any)
	getRemote(name):FireServer(...)
end

-- Client: listen to a server event.
function Net.listen(name: ServerEvent, handler: (...any) -> ())
	getRemote(name).OnClientEvent:Connect(handler)
end

return Net
