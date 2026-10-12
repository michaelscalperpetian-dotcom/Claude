--!nocheck
-- Integration test: runs the real server systems with stand-in Roblox services
-- and plays through a session: tutorial, buying, hatching, growing, laying,
-- selling, upgrades, streaks, a Robux purchase (with a duplicate receipt), and a
-- two-player night raid (steal, steal-back, lock).
-- Run with: lune run tests/integration

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local taskLib = require("@lune/task")
local ServerEnv = require("./support/ServerEnv")

local env = ServerEnv.new({
	configure = function(Config)
		Config.PRODUCT_IDS.CoinsSmall = 1001
		Config.PRODUCT_IDS.InstantHatchSmall = 1002
		Config.PRODUCT_IDS.InstantHatchMedium = 1003
		Config.PRODUCT_IDS.InstantHatchLarge = 1004
	end,
})

local S = env.S
local Config = env.Config
local Clock = env.Clock
local Cycle = env.Cycle
local handlers = env.handlers
local outbox = env.outbox
local marketplace = env.marketplace
local friendships = env.friendships
local advance = env.advance
local makePlayer = env.makePlayer
local join = env.join
local moveTo = env.moveTo
local profileOf = env.profileOf
local findPrompt = env.findPrompt
local trigger = env.trigger
local _ = taskLib

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

step("daily quests track play and pay out once each", function()
	local profile = profileOf(alice)
	local QuestData = require("./loader").load("src/shared/Data/QuestData")
	local day = Cycle.dayNumber(Clock.now())
	local quests = QuestData.forDay(day)
	eq(#quests, 3, "three quests a day")
	local first = quests[1]
	handlers.ClaimQuest(alice, first.id)
	eq(profile.quests.claimed[first.id], nil, "can't claim before it's done")
	for _ = 1, first.goal + 2 do
		S.Quests.track(alice, first.event)
	end
	eq(profile.quests.progress[first.id], first.goal, "progress capped at the goal")
	local coins, luck, boost = profile.coins, profile.boosts.luckUntil, profile.boosts.coinsUntil
	handlers.ClaimQuest(alice, first.id)
	assert(profile.quests.claimed[first.id], "claimed")
	assert(
		profile.coins > coins
			or profile.boosts.luckUntil > luck
			or profile.boosts.coinsUntil > boost,
		"rewarded"
	)
	local after = profile.coins
	handlers.ClaimQuest(alice, first.id)
	eq(profile.coins, after, "only once")
	handlers.ClaimQuest(alice, "bonus")
	eq(profile.quests.bonusClaimed, false, "bonus needs every quest")
	for _, quest in quests do
		for _ = 1, quest.goal do
			S.Quests.track(alice, quest.event)
		end
		handlers.ClaimQuest(alice, quest.id)
	end
	handlers.ClaimQuest(alice, "bonus")
	eq(profile.quests.bonusClaimed, true, "bonus after all quests")
	handlers.ClaimQuest(alice, 42)
	handlers.ClaimQuest(alice, "nope")
	advance(86400)
	S.Quests.track(alice, "roar")
	eq(profile.quests.day, Cycle.dayNumber(Clock.now()), "new day resets quests")
	eq(profile.quests.bonusClaimed, false, "bonus resets")
end)

step("promo codes work once per player", function()
	local profile = profileOf(alice)
	local coins = profile.coins
	handlers.RedeemCode(alice, " dino ")
	assert(profile.codes.DINO, "code recorded")
	assert(profile.coins > coins, "code paid coins")
	local after = profile.coins
	handlers.RedeemCode(alice, "DINO")
	eq(profile.coins, after, "can't use a code twice")
	handlers.RedeemCode(alice, "NOTACODE")
	handlers.RedeemCode(alice, string.rep("A", 500))
	handlers.RedeemCode(alice, { "DINO" })
	eq(profile.coins, after, "bad codes do nothing")
end)

step("Dex milestones pay out when enough species are found", function()
	local profile = profileOf(alice)
	local DexRewards = require("./loader").load("src/shared/Data/DexRewards")
	S.Nest.addDino(alice, "Stegosaurus")
	S.Nest.addDino(alice, "Triceratops")
	local found = DexRewards.discovered(profile.dex)
	assert(found >= 3, "alice has found at least 3 species")
	handlers.ClaimDex(alice, 3)
	assert(profile.dexClaimed["3"], "3-species prize claimed")
	handlers.ClaimDex(alice, 13)
	eq(profile.dexClaimed["13"], nil, "can't claim the all-species prize early")
	handlers.ClaimDex(alice, 5)
	eq(profile.dexClaimed["5"], nil, "not a milestone")
	handlers.ClaimDex(alice, "3")
end)

step("settings save and ignore junk", function()
	local profile = profileOf(alice)
	handlers.SetSetting(alice, "music", false)
	eq(profile.settings.music, false, "music off")
	handlers.SetSetting(alice, "sfx", "yes")
	eq(profile.settings.sfx, true, "non-boolean ignored")
	handlers.SetSetting(alice, "coins", true)
	eq(profile.settings.coins, nil, "unknown setting ignored")
	eq(S.State.snapshot(alice).settings.music, false, "snapshot has settings")
end)

step("a buddy dino follows its owner and leaves when sold", function()
	local profile = profileOf(alice)
	local dino = profile.dinos[1]
	handlers.SetBuddy(alice, dino.id)
	eq(profile.buddy, dino.id, "buddy chosen")
	local look = alice:GetAttribute("Buddy")
	assert(
		typeof(look) == "string" and string.find(look, dino.species, 1, true),
		"buddy look replicated"
	)
	handlers.SetBuddy(alice, "not-mine")
	eq(profile.buddy, dino.id, "can't pick someone else's dino")
	handlers.SellDino(alice, dino.id)
	eq(profile.buddy, nil, "selling the buddy clears it")
	eq(alice:GetAttribute("Buddy"), nil, "follower removed")
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
