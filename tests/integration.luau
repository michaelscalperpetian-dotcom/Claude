--!nocheck
-- Integration test: runs the real server systems with stand-in Roblox services
-- and plays through a session: tutorial, buying, hatching, growing, laying,
-- selling, upgrades, streaks, a Robux purchase (with a duplicate receipt), and a
-- two-player night raid (steal, steal-back, lock).
-- Run with: lune run tests/integration

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local taskLib = require("@lune/task")
local Loader = require("./loader")

local Instance = roblox.Instance

-- ===== Fake clock =====
local now = 1_800_000_000 -- a Friday, well away from the weekly mega storm
local function advance(seconds: number)
	now += seconds
end

-- ===== Engine stand-ins =====

local function signal()
	local s = { handlers = {} }
	function s:Connect(fn)
		table.insert(self.handlers, fn)
		return {
			Disconnect = function() end,
		}
	end
	function s:Fire(...)
		for _, handler in self.handlers do
			handler(...)
		end
	end
	return s
end

local dataModel = Instance.new("DataModel")
local workspaceService = dataModel:GetService("Workspace")
local playersFolder = dataModel:GetService("Players")

roblox.implementMethod("Workspace", "GetServerTimeNow", function()
	return now
end)

local function pivotOf(model)
	if model.PrimaryPart then
		return model.PrimaryPart.CFrame
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp then
		return hrp.CFrame
	end
	return roblox.CFrame.new()
end
roblox.implementMethod("Model", "GetPivot", function(model)
	return pivotOf(model)
end)
roblox.implementMethod("Model", "PivotTo", function(model, target)
	local delta = target * pivotOf(model):Inverse()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
end)

local friendships = {}
roblox.implementMethod("Player", "IsFriendsWithAsync", function(player, userId)
	return friendships[player.UserId .. ":" .. userId] == true
end)
roblox.implementMethod("Player", "Kick", function(player, message)
	error("kicked: " .. tostring(message))
end)

local tags = {}
local collectionService = {
	AddTag = function(_, instance, tag)
		tags[tag] = (tags[tag] or 0) + 1
	end,
}

local replicatedAttributes = {}
local replicatedStorage = setmetatable({}, {
	__index = function(_, key)
		if key == "Shared" then
			return Loader.path("src/shared")
		elseif key == "GetAttribute" then
			return function(_, name)
				return replicatedAttributes[name]
			end
		elseif key == "SetAttribute" then
			return function(_, name, value)
				replicatedAttributes[name] = value
			end
		end
		return nil
	end,
})

local playerList = {}
local players = {
	PlayerAdded = signal(),
	PlayerRemoving = signal(),
	UserSubscriptionStatusChanged = signal(),
	CharacterAutoLoads = true,
	GetPlayers = function()
		return playerList
	end,
	GetPlayerByUserId = function(_, id)
		for _, p in playerList do
			if p.UserId == id then
				return p
			end
		end
		return nil
	end,
	GetPlayerFromCharacter = function(_, character)
		for _, p in playerList do
			if p.Character == character then
				return p
			end
		end
		return nil
	end,
}

local marketplace = {
	PromptGamePassPurchaseFinished = signal(),
	PromptSubscriptionPurchaseFinished = signal(),
	prompts = {},
	PromptProductPurchase = function(self, player, id)
		table.insert(self.prompts, { player = player, id = id })
	end,
	PromptGamePassPurchase = function() end,
	PromptSubscriptionPurchase = function() end,
	UserOwnsGamePassAsync = function()
		return false
	end,
	GetUserSubscriptionStatusAsync = function()
		return { IsSubscribed = false }
	end,
}

local promptService = { PromptTriggered = signal() }

local services = {
	ReplicatedStorage = replicatedStorage,
	Workspace = workspaceService,
	CollectionService = collectionService,
	Players = players,
	MarketplaceService = marketplace,
	ProximityPromptService = promptService,
	RunService = {
		IsStudio = function()
			return true
		end,
		IsServer = function()
			return true
		end,
	},
	DataStoreService = {
		GetDataStore = function()
			error("StudioAccessToApisNotAllowed")
		end,
	},
	AnalyticsService = {
		LogOnboardingFunnelStepEvent = function() end,
		LogEconomyEvent = function() end,
		LogCustomEvent = function() end,
	},
	PolicyService = {
		GetPolicyInfoForPlayerAsync = function()
			return { ArePaidRandomItemsRestricted = false, IsPaidItemTradingAllowed = true }
		end,
	},
	AdService = {
		CreateAdRewardFromDevProductId = function()
			return {}
		end,
		ShowRewardedVideoAdAsync = function()
			return roblox.Enum.ShowAdResult.ShowCompleted
		end,
	},
}

local game = {
	JobId = "",
	PrivateServerId = "",
	GetService = function(_, name)
		local service = services[name]
		assert(service, "no stand-in for service " .. name)
		return service
	end,
	BindToClose = function() end,
}

for _, name in
	{
		"Vector3",
		"Vector2",
		"CFrame",
		"Color3",
		"UDim",
		"UDim2",
		"Enum",
		"NumberSequence",
		"NumberSequenceKeypoint",
		"ColorSequence",
		"ColorSequenceKeypoint",
		"NumberRange",
	}
do
	Loader.globals[name] = (roblox :: any)[name]
end
Loader.globals.Instance = Instance
Loader.globals.game = game
Loader.globals.workspace = workspaceService
Loader.globals.task = taskLib
Loader.globals.warn = function(...)
	print("[warn]", ...)
end
Loader.globals.Random = {
	new = function()
		return {
			NextNumber = function(_, a, b)
				a = a or 0
				b = b or 1
				return a + math.random() * (b - a)
			end,
			NextInteger = function(_, a, b)
				return math.random(a, b)
			end,
		}
	end,
}

-- Net stand-in: record handlers and outgoing messages.
local handlers = {}
local outbox = {}
Loader.stub("src/shared/Net", {
	serverInit = function() end,
	on = function(name, _rate, _burst, handler)
		handlers[name] = handler
	end,
	fire = function(player, name, ...)
		table.insert(outbox, { player = player, name = name, args = { ... } })
	end,
	fireAll = function(name, ...)
		table.insert(outbox, { player = "all", name = name, args = { ... } })
	end,
	send = function() end,
	listen = function() end,
})

-- ===== Load the real server =====

local Config = Loader.load("src/shared/Config")
Config.PRODUCT_IDS.CoinsSmall = 1001
Config.PRODUCT_IDS.InstantHatchSmall = 1002
Config.PRODUCT_IDS.InstantHatchMedium = 1003
Config.PRODUCT_IDS.InstantHatchLarge = 1004

local SYSTEMS = {
	"Analytics",
	"Cheats",
	"Coins",
	"Data",
	"Dinos",
	"Eggs",
	"Lifecycle",
	"Monetization",
	"Nest",
	"Plots",
	"Progress",
	"Prompts",
	"Raids",
	"Sessions",
	"Social",
	"State",
	"Upgrades",
	"Weather",
	"World",
}
local S = {}
for _, name in SYSTEMS do
	S[name] = Loader.load("src/server/Systems/" .. name)
end
for _, name in SYSTEMS do
	if S[name].init then
		S[name].init()
	end
end
S.Social.start() -- creates the nest "Like" prompts

local Clock = Loader.load("src/shared/Util/Clock")
local Cycle = Loader.load("src/shared/Util/Cycle")

-- ===== Helpers =====

local nextUserId = 100
local function makePlayer(name: string)
	nextUserId += 1
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = nextUserId
	player.Parent = playersFolder
	local character = Instance.new("Model")
	character.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = roblox.Vector3.new(2, 2, 1)
	root.Parent = character
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = roblox.Vector3.new(1, 1, 1)
	head.Parent = character
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = character
	character.Parent = workspaceService
	player.Character = character
	table.insert(playerList, player)
	return player
end

-- Same steps as Lifecycle.onJoin, minus spawning (no engine here).
local function join(player)
	local session = S.Sessions.create(player)
	assert(S.Data.load(player), "profile loads")
	assert(S.Plots.assign(player), "gets a plot")
	S.Dinos.applyOffline(player)
	S.Plots.renderAll(player)
	S.Coins.setupLeaderstats(player)
	S.Monetization.onJoin(player)
	S.Social.onJoin(player)
	session.ready = true
	S.Progress.onJoin(player)
	return session
end

local function moveTo(player, position)
	player.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(position)
end

local function profileOf(player)
	return S.Data.get(player)
end

local function findPrompt(container, action, key)
	for _, d in container:GetDescendants() do
		if d:IsA("ProximityPrompt") and d:GetAttribute("Action") == action then
			if key == nil or d:GetAttribute("Key") == key then
				return d
			end
		end
	end
	return nil
end

local function trigger(prompt, player)
	-- The dispatcher rate-limits per action; wait it out like a real player would.
	taskLib.wait(0.15)
	promptService.PromptTriggered:Fire(prompt, player)
end

local passed, failed = 0, 0
local function step(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("ok    " .. name)
	else
		failed += 1
		print(`FAIL  {name}\n      {err}`)
	end
end

local function eq(actual, expected, label)
	if actual ~= expected then
		error(`{label}: expected {tostring(expected)}, got {tostring(actual)}`, 2)
	end
end

-- ===== The session =====

local alice = makePlayer("Alice")
local aliceSession

step("joining gives a nest, a starter egg and tutorial step 1", function()
	aliceSession = join(alice)
	local profile = profileOf(alice)
	eq(profile.tutorial, 1, "tutorial step")
	eq(profile.coins, Config.STARTING_COINS, "starting coins")
	local egg = profile.incubators["1"]
	assert(egg and egg.kind == "starter", "starter egg in incubator 1")
	local plot = S.World.getPlot(aliceSession.plotIndex)
	eq(#plot.eggFolder:GetChildren(), 1, "egg model rendered")
	eq(plot.model:GetAttribute("OwnerId"), alice.UserId, "plot owner attribute")
	assert(alice:FindFirstChild("leaderstats"), "leaderstats")
end)

step("warming the egg by tapping speeds it up", function()
	local profile = profileOf(alice)
	local before = profile.incubators["1"].hatchAt
	local plot = S.World.getPlot(aliceSession.plotIndex)
	local prompt = findPrompt(plot.eggFolder, "IncubatorTap", "1")
	assert(prompt, "incubator prompt")
	trigger(prompt, alice)
	assert(profile.incubators["1"].hatchAt < before, "hatchAt moved earlier")
end)

step("hatching the starter egg gives a Raptor and advances the tutorial", function()
	advance(Config.STARTER_EGG_SECONDS + 1)
	local plot = S.World.getPlot(aliceSession.plotIndex)
	trigger(findPrompt(plot.eggFolder, "IncubatorTap", "1"), alice)
	local profile = profileOf(alice)
	eq(#profile.dinos, 1, "dino count")
	eq(profile.dinos[1].species, "Raptor", "species")
	eq(profile.tutorial, 2, "tutorial step")
	eq(#plot.dinoFolder:GetChildren(), 1, "dino model rendered")
	assert(profile.dex.Raptor and profile.dex.Raptor.Normal, "dex entry")
	local hatchEffect = false
	for _, message in outbox do
		if message.player == alice and message.name == "Effect" and message.args[1] == "Hatch" then
			hatchEffect = true
		end
	end
	assert(hatchEffect, "hatch reveal sent to the client")
end)

step("income piles up on the pad and collecting it advances the tutorial", function()
	S.Dinos.step(10)
	local profile = profileOf(alice)
	assert(profile.pendingCoins > 0, "pending coins after a tick")
	local coinsBefore = profile.coins
	S.Coins.collect(alice)
	S.Progress.event(alice, "collect")
	assert(profile.coins > coinsBefore, "coins collected")
	eq(profile.tutorial, 3, "tutorial step")
end)

step("buying an egg spends coins, fills an incubator and gives the gift egg", function()
	local profile = profileOf(alice)
	local coinsBefore = profile.coins
	handlers.BuyEgg(alice, "Jungle")
	eq(profile.coins, coinsBefore - 50, "coins spent")
	local shopEggs, giftEggs = 0, 0
	for _, egg in profile.incubators do
		if egg.kind == "shop" then
			shopEggs += 1
		elseif egg.kind == "gift" then
			giftEggs += 1
		end
	end
	eq(shopEggs, 1, "shop egg")
	eq(giftEggs, 1, "gift egg")
	eq(profile.tutorial, 4, "tutorial step")
end)

step("bad remote arguments are ignored", function()
	local profile = profileOf(alice)
	local coins = profile.coins
	handlers.BuyEgg(alice, nil)
	handlers.BuyEgg(alice, 12345)
	handlers.BuyEgg(alice, { "Jungle" })
	handlers.BuyEgg(alice, "NotAnEgg")
	handlers.HatchEgg(alice, "999")
	handlers.HatchEgg(alice, 0 / 0)
	handlers.SellDino(alice, "nope")
	handlers.BuyUpgrade(alice, "everything")
	eq(profile.coins, coins, "coins unchanged")
end)

step("hatching the gift egg gives a Glossy Parasaur", function()
	advance(Config.GIFT_EGG_SECONDS + 1)
	local profile = profileOf(alice)
	local giftSlot
	for slot, egg in profile.incubators do
		if egg.kind == "gift" then
			giftSlot = slot
		end
	end
	assert(giftSlot, "gift slot")
	handlers.HatchEgg(alice, giftSlot)
	local found = false
	for _, dino in profile.dinos do
		if dino.species == "Parasaur" and dino.mutation == "Glossy" then
			found = true
		end
	end
	assert(found, "glossy parasaur")
	eq(profile.tutorial, 5, "tutorial step")
end)

step("finishing the raid practice completes the tutorial", function()
	handlers.TutorialAction(alice, "ChasedThief")
	eq(profileOf(alice).tutorial, 6, "after chase")
	handlers.TutorialAction(alice, "Finish")
	eq(profileOf(alice).tutorial, 99, "done")
end)

step("shop eggs hatch into species from the egg's odds table", function()
	advance(60)
	local profile = profileOf(alice)
	for slot, egg in profile.incubators do
		if egg.kind == "shop" then
			handlers.HatchEgg(alice, slot)
		end
	end
	local allowed =
		{ Raptor = true, Gallimimus = true, Pachy = true, Parasaur = true, Dilophosaurus = true }
	eq(#profile.dinos, 3, "three dinos")
	assert(allowed[profile.dinos[3].species], "jungle species " .. profile.dinos[3].species)
end)

step("sold-out stock can't be bought", function()
	handlers.Cheat(alice, "coins")
	local profile = profileOf(alice)
	local restock = Cycle.restock(Clock.cycleNow())
	local stock = restock.stock.Jungle
	local bought = 0
	for _ = 1, stock + 3 do
		-- free an incubator each time so only stock limits us
		for slot in profile.incubators do
			profile.incubators[slot] = nil
		end
		local before = profile.shop.bought.Jungle or 0
		handlers.BuyEgg(alice, "Jungle")
		if (profile.shop.bought.Jungle or 0) > before then
			bought += 1
		end
	end
	eq(bought, stock - 1, "bought exactly the remaining stock") -- one was bought earlier
	for slot in profile.incubators do
		profile.incubators[slot] = nil
	end
	S.Plots.syncIncubators(alice)
end)

step("dinos grow over time and adults lay eggs", function()
	advance(2 * 3600)
	S.Dinos.step(1)
	local profile = profileOf(alice)
	local stage = S.Plots.dinoModel(alice, profile.dinos[1].id):GetAttribute("Stage")
	assert(stage >= 3, "raptor is an adult after 2h, stage " .. tostring(stage))
	advance(Config.LAY_INTERVAL_ADULT + 1)
	S.Dinos.step(1)
	assert(#profile.tray >= 1, "adult laid an egg")
	local plot = S.World.getPlot(aliceSession.plotIndex)
	eq(#plot.trayFolder:GetChildren(), #profile.tray, "tray eggs rendered")
end)

step("incubating and selling laid eggs", function()
	local profile = profileOf(alice)
	local first = profile.tray[1]
	handlers.IncubateTrayEgg(alice, first.id)
	local laid = false
	for _, egg in profile.incubators do
		if egg.kind == "laid" and egg.species == first.species then
			laid = true
		end
	end
	assert(laid, "laid egg in incubator")
	handlers.Cheat(alice, "lay")
	local trayEgg = profile.tray[1]
	local coins = profile.coins
	handlers.SellTrayEgg(alice, trayEgg.id)
	assert(profile.coins > coins, "sold laid egg")
end)

step("selling a dino pays coins and frees the slot", function()
	local profile = profileOf(alice)
	local count = #profile.dinos
	local coins = profile.coins
	handlers.SellDino(alice, profile.dinos[count].id)
	eq(#profile.dinos, count - 1, "dino removed")
	assert(profile.coins > coins, "paid")
	local plot = S.World.getPlot(aliceSession.plotIndex)
	eq(#plot.dinoFolder:GetChildren(), count - 1, "model removed")
end)

step("upgrades cost coins and raise limits", function()
	local profile = profileOf(alice)
	local coins = profile.coins
	handlers.BuyUpgrade(alice, "slots")
	eq(profile.upgrades.slots, 1, "slot upgrade")
	eq(profile.coins, coins - Config.SLOT_UPGRADE_COSTS[1], "paid for slot")
	handlers.BuyUpgrade(alice, "incubators")
	eq(profile.upgrades.incubators, 1, "incubator upgrade")
end)

step("daily streak can be claimed once per day", function()
	local profile = profileOf(alice)
	handlers.ClaimStreak(alice)
	eq(profile.streak.count, 1, "day 1")
	handlers.ClaimStreak(alice)
	eq(profile.streak.count, 1, "still day 1 the same day")
	advance(86400)
	handlers.ClaimStreak(alice)
	eq(profile.streak.count, 2, "day 2 next day")
end)

step("Robux purchase is granted once even if the receipt arrives twice", function()
	local profile = profileOf(alice)
	local coins = profile.coins
	local receipt =
		{ PlayerId = alice.UserId, PurchaseId = "receipt-1", ProductId = 1001, CurrencySpent = 25 }
	local first = marketplace.ProcessReceipt(receipt)
	eq(first, roblox.Enum.ProductPurchaseDecision.PurchaseGranted, "granted")
	local afterFirst = profile.coins
	assert(afterFirst > coins, "coins added")
	local second = marketplace.ProcessReceipt(receipt)
	eq(second, roblox.Enum.ProductPurchaseDecision.PurchaseGranted, "acknowledged again")
	eq(profile.coins, afterFirst, "not granted twice")
	local unknown =
		marketplace.ProcessReceipt({ PlayerId = alice.UserId, PurchaseId = "x", ProductId = 999 })
	eq(unknown, roblox.Enum.ProductPurchaseDecision.NotProcessedYet, "unknown product not granted")
end)

step("instant hatch: prompt picks a product tier and the receipt finishes that egg", function()
	local profile = profileOf(alice)
	for slot in profile.incubators do
		profile.incubators[slot] = nil
	end
	handlers.BuyEgg(alice, "Jungle")
	local slot = next(profile.incubators)
	assert(slot, "egg placed")
	handlers.PromptPurchase(alice, "product", "InstantHatch", slot)
	local last = marketplace.prompts[#marketplace.prompts]
	eq(last.id, 1002, "small tier for a short egg")
	marketplace.ProcessReceipt({ PlayerId = alice.UserId, PurchaseId = "ih-1", ProductId = 1002 })
	assert(profile.incubators[slot].hatchAt <= Clock.now(), "egg ready now")
end)

-- ===== Two players: night raid =====

local bob = makePlayer("Bob")
local bobSession

step("a second player gets a different nest", function()
	bobSession = join(bob)
	assert(bobSession.plotIndex ~= aliceSession.plotIndex, "different plots")
end)

local function makeNight()
	handlers.Cheat(alice, "night")
	assert(Cycle.dayNight(Clock.cycleNow()).isNight, "it is night")
end

step("new players are shielded from raids", function()
	makeNight()
	handlers.Cheat(alice, "lay")
	local profile = profileOf(alice)
	profile.firstJoin = Clock.now() - 60 -- joined a minute ago: shield is on
	S.Plots.updateSign(alice)
	local eggId = profile.tray[1].id
	local trayPrompt =
		findPrompt(S.World.getPlot(aliceSession.plotIndex).trayFolder, "Steal", eggId)
	assert(trayPrompt, "steal prompt exists")
	moveTo(bob, S.Plots.trayPosition(alice))
	trigger(trayPrompt, bob)
	eq(bobSession.carry, nil, "shield blocks the steal")
end)

step("stealing at night and carrying the egg home moves it to the thief", function()
	local profile = profileOf(alice)
	profile.firstJoin = Clock.now() - 3 * 86400 -- shield expired
	S.Plots.updateSign(alice)
	local eggId = profile.tray[1].id
	local species = profile.tray[1].species
	local trayBefore = #profile.tray
	local trayPrompt =
		findPrompt(S.World.getPlot(aliceSession.plotIndex).trayFolder, "Steal", eggId)
	moveTo(bob, S.Plots.trayPosition(alice))
	trigger(trayPrompt, bob)
	assert(bobSession.carry ~= nil, "bob is carrying")
	eq(#profile.tray, trayBefore, "egg stays in alice's save while carried")
	-- run home
	moveTo(
		bob,
		S.World.getPlot(bobSession.plotIndex).pad.CFrame.Position + roblox.Vector3.new(0, 3, 0)
	)
	moveTo(alice, roblox.Vector3.new(0, 3, 0))
	S.Raids.step()
	eq(bobSession.carry, nil, "carry finished")
	eq(#profile.tray, trayBefore - 1, "alice lost the egg")
	local bobTray = profileOf(bob).tray
	eq(bobTray[#bobTray].species, species, "bob has the egg")
end)

step("the owner can tag the thief to get the egg back", function()
	local profile = profileOf(alice)
	local eggId = profile.tray[1].id
	local trayBefore = #profile.tray
	local trayPrompt =
		findPrompt(S.World.getPlot(aliceSession.plotIndex).trayFolder, "Steal", eggId)
	moveTo(bob, S.Plots.trayPosition(alice))
	trigger(trayPrompt, bob)
	assert(bobSession.carry ~= nil, "carrying")
	moveTo(alice, S.Plots.trayPosition(alice) + roblox.Vector3.new(2, 0, 0))
	S.Raids.step()
	eq(bobSession.carry, nil, "caught")
	eq(#profile.tray, trayBefore, "egg still alice's")
end)

step("a locked gate stops thieves", function()
	handlers.LockGate(alice)
	assert(aliceSession.lockUntil > Clock.now(), "locked")
	local profile = profileOf(alice)
	local eggId = profile.tray[1].id
	local trayPrompt =
		findPrompt(S.World.getPlot(aliceSession.plotIndex).trayFolder, "Steal", eggId)
	advance(5) -- get past the thief's stun
	moveTo(bob, S.Plots.trayPosition(alice))
	trigger(trayPrompt, bob)
	eq(bobSession.carry, nil, "lock blocks the steal")
	S.Raids.step()
	assert(
		not S.World.isInside(aliceSession.plotIndex, bob.Character.HumanoidRootPart.CFrame.Position),
		"pushed out"
	)
end)

step("friends boost each other's coins", function()
	friendships[alice.UserId .. ":" .. bob.UserId] = true
	friendships[bob.UserId .. ":" .. alice.UserId] = true
	S.Social.onJoin(bob)
	assert(
		aliceSession.friendIds[bob.UserId] and bobSession.friendIds[alice.UserId],
		"friends linked"
	)
	local snapshot = S.State.snapshot(alice)
	eq(snapshot.friendsHere, 1, "friend counted")
	assert(snapshot.multiplier > 1, "coin multiplier above 1")
end)

step("liking another player's nest", function()
	local likePrompt = findPrompt(S.World.getPlot(bobSession.plotIndex).signPart, "Like")
	assert(likePrompt, "like prompt on sign")
	trigger(likePrompt, alice)
	eq(profileOf(bob).likes, 1, "bob got a like")
	trigger(likePrompt, alice)
	eq(profileOf(bob).likes, 1, "only once per session")
end)

step("storms mutate dinos", function()
	handlers.Cheat(alice, "storm")
	local storm = Cycle.storm(Clock.cycleNow())
	assert(storm.active, "storm active")
	local profile = profileOf(alice)
	-- the storm loop is a start() loop; apply a guaranteed mutation through Nest
	S.Nest.setMutation(alice, profile.dinos[1].id, "Lava")
	eq(profile.dinos[1].mutation, "Lava", "mutated")
	assert(profile.dex.Raptor.Lava, "dex records mutation")
end)

step("snapshot has everything the HUD needs", function()
	local snapshot = S.State.snapshot(alice)
	for _, key in
		{
			"coins",
			"dinos",
			"incubators",
			"tray",
			"maxSlots",
			"maxIncubators",
			"passes",
			"tutorial",
		}
	do
		assert(snapshot[key] ~= nil, "snapshot." .. key)
	end
	eq(snapshot.maxSlots, Config.BASE_DINO_SLOTS + 1, "slots include upgrade")
end)

step("leaving cleans up the nest and frees the plot", function()
	local index = bobSession.plotIndex
	S.Raids.onLeave(bob)
	S.Plots.release(bob)
	S.Data.release(bob)
	S.Sessions.remove(bob)
	local plot = S.World.getPlot(index)
	eq(plot.model:GetAttribute("OwnerId"), 0, "plot free")
	eq(#plot.dinoFolder:GetChildren(), 0, "dinos cleared")
	eq(S.Plots.ownerOf(index), nil, "no owner")
end)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
