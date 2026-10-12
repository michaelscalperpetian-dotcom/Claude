--!strict
-- Buying eggs, warming and hatching them, and the laid-egg tray (incubate/sell).
-- Hatch results are rolled here, on the server, from the same odds tables the
-- client shows in the Odds panel.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local Config = require(ReplicatedStorage.Shared.Config)
local Cycle = require(ReplicatedStorage.Shared.Util.Cycle)
local DinoData = require(ReplicatedStorage.Shared.Data.DinoData)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local EggData = require(ReplicatedStorage.Shared.Data.EggData)
local EggOdds = require(ReplicatedStorage.Shared.Util.EggOdds)
local Net = require(ReplicatedStorage.Shared.Net)
local Odds = require(ReplicatedStorage.Shared.Util.Odds)
local Types = require(ReplicatedStorage.Shared.Types)
local Analytics = require(script.Parent.Analytics)
local Coins = require(script.Parent.Coins)
local Data = require(script.Parent.Data)
local Nest = require(script.Parent.Nest)
local Plots = require(script.Parent.Plots)
local Progress = require(script.Parent.Progress)
local Prompts = require(script.Parent.Prompts)
local Sessions = require(script.Parent.Sessions)
local State = require(script.Parent.State)
local Notify = require(script.Parent.Parent.Lib.Notify)
local Stats = require(script.Parent.Parent.Lib.Stats)

local Eggs = {}

local rng = Random.new()

-- Warm taps: token bucket so tapping can at most double hatch speed.
local warmBudget: { [Player]: { tokens: number, last: number } } = {}

local function validSlot(value: unknown): string?
	if typeof(value) ~= "string" then
		return nil
	end
	local n = tonumber(value)
	if not n or n ~= math.floor(n) or n < 1 or n > Config.MAX_INCUBATORS then
		return nil
	end
	return value
end

local function validId(value: unknown): string?
	if typeof(value) ~= "string" or #value > 20 then
		return nil
	end
	return value
end

-- ===== Buying =====

local function buyEgg(player: Player, eggId: unknown)
	if typeof(eggId) ~= "string" then
		return
	end
	local eggType = EggData.get(eggId)
	local profile = Data.get(player)
	local session = Sessions.get(player)
	if not eggType or not profile or not session or not session.ready then
		return
	end
	local now = Clock.now()
	local restock = Cycle.restock(Clock.cycleNow())
	if profile.shop.restock ~= restock.index then
		profile.shop = { restock = restock.index, bought = {} }
	end
	local bought = profile.shop.bought[eggId] or 0
	if bought >= (restock.stock[eggId] or 0) then
		Notify.send(player, "Sold out! The shop restocks soon.", "bad")
		return
	end
	if Nest.freeIncubator(player) == nil then
		Notify.send(player, "All your incubators are full! Hatch an egg first.", "bad")
		return
	end
	if not Coins.spend(player, eggType.price, "Shop", eggId) then
		Notify.send(player, "Not enough coins yet!", "bad")
		return
	end
	profile.shop.bought[eggId] = bought + 1
	Nest.placeEgg(player, {
		id = Nest.newId(profile),
		kind = "shop",
		eggType = eggId,
		placedAt = now,
		hatchAt = now + eggType.hatchSeconds / Stats.hatchSpeed(session),
	})
	Notify.send(player, `🥚 {eggType.name} is warming in your nest!`, "good")
	Progress.event(player, "buy_egg")
	State.markDirty(player)
end

-- ===== Hatching =====

local function rollMutation(): string?
	return Odds.pick(EggOdds.mutations(Clock.cycleNow()), rng:NextNumber())
end

local function resultFor(egg: Types.IncubatorEgg, profile: Types.Profile): (string?, string?)
	if egg.kind == "shop" then
		if not egg.eggType or not EggData.get(egg.eggType) then
			return nil, nil
		end
		local luck = Stats.luckActive(profile, Clock.now())
		local species = Odds.roll(EggOdds.species(egg.eggType, luck), rng:NextNumber())
		return species, rollMutation()
	elseif egg.kind == "laid" then
		return egg.species, rollMutation()
	elseif egg.kind == "gift" then
		return egg.species, egg.mutation
	end
	return egg.species, nil -- starter
end

function Eggs.hatch(player: Player, slot: string)
	local profile = Data.get(player)
	local session = Sessions.get(player)
	if not profile or not session or not session.ready then
		return
	end
	local egg = profile.incubators[slot]
	if not egg or egg.hatchAt > Clock.now() then
		return
	end
	if not Nest.hasFreeSlot(player) then
		Notify.send(player, "Your nest is full! Sell a dino or get more space.", "bad")
		return
	end
	local species, mutation = resultFor(egg, profile)
	if not species or not DinoData.get(species) then
		return
	end
	Nest.removeEgg(player, slot)
	local dino = Nest.addDino(player, species, mutation)
	if not dino then
		-- Shouldn't happen (slot checked above), but never lose the egg.
		profile.incubators[slot] = egg
		Plots.syncIncubators(player)
		return
	end
	profile.stats.hatched += 1
	local data = DinoData.get(species) :: DinoData.Species
	Notify.effect(player, "Hatch", { species = species, mutation = mutation, dinoId = dino.id })
	Analytics.event(player, "Hatch" .. data.rarity)
	if egg.kind == "starter" then
		Progress.event(player, "hatch_starter")
	elseif egg.kind == "gift" then
		Progress.event(player, "hatch_gift")
	else
		Progress.event(player, "hatch")
	end
	if data.rarity == "Legendary" or data.rarity == "Secret" then
		Notify.all(`🌟 {player.DisplayName} just hatched a {data.rarity} {data.name}!`, "rare")
	end
	State.markDirty(player)
end

function Eggs.warm(player: Player, slot: string)
	local profile = Data.get(player)
	local egg = profile and profile.incubators[slot]
	if not egg then
		return
	end
	local now = Clock.now()
	if egg.hatchAt <= now then
		return
	end
	local budget = warmBudget[player]
	local clock = os.clock()
	if not budget then
		budget = { tokens = Config.WARM_TAP_RATE, last = clock }
		warmBudget[player] = budget
	end
	budget.tokens =
		math.min(Config.WARM_TAP_RATE, budget.tokens + (clock - budget.last) * Config.WARM_TAP_RATE)
	budget.last = clock
	if budget.tokens < 1 then
		return
	end
	budget.tokens -= 1
	Nest.setHatchAt(player, slot, math.max(now, egg.hatchAt - Config.WARM_TAP_SECONDS))
end

-- Instantly finish an egg (Robux purchase or token). Returns true if it applied.
function Eggs.finishNow(player: Player, slot: string?): boolean
	local profile = Data.get(player)
	if not profile then
		return false
	end
	local now = Clock.now()
	local target = slot and profile.incubators[slot]
	if not target or target.hatchAt <= now then
		-- fall back to the egg closest to hatching
		target = nil
		slot = nil
		for key, egg in profile.incubators do
			if egg.hatchAt > now and (target == nil or egg.hatchAt < target.hatchAt) then
				target = egg
				slot = key
			end
		end
	end
	if not target or not slot then
		return false
	end
	Nest.setHatchAt(player, slot, now)
	Notify.send(player, "⚡ Your egg is ready to hatch!", "good")
	return true
end

-- ===== Tray =====

local function incubateTrayEgg(player: Player, eggId: string)
	local profile = Data.get(player)
	local session = Sessions.get(player)
	if not profile or not session or Plots.isTrayEggHidden(player, eggId) then
		return
	end
	local trayEgg = Nest.findTrayEgg(profile, eggId)
	if not trayEgg then
		return
	end
	local species = DinoData.get(trayEgg.species)
	if not species then
		return
	end
	if Nest.freeIncubator(player) == nil then
		Notify.send(player, "All your incubators are full!", "bad")
		return
	end
	Nest.removeTrayEgg(player, eggId)
	local now = Clock.now()
	Nest.placeEgg(player, {
		id = Nest.newId(profile),
		kind = "laid",
		species = trayEgg.species,
		placedAt = now,
		hatchAt = now + species.layHatchSeconds / Stats.hatchSpeed(session),
	})
end

local function sellTrayEgg(player: Player, eggId: string)
	local profile = Data.get(player)
	if not profile or Plots.isTrayEggHidden(player, eggId) then
		return
	end
	local trayEgg = Nest.findTrayEgg(profile, eggId)
	local species = trayEgg and DinoData.get(trayEgg.species)
	if not trayEgg or not species then
		return
	end
	Nest.removeTrayEgg(player, eggId)
	local amount = Coins.add(player, Economy.trayEggValue(species.income), "Gameplay", "SellEgg")
	Notify.send(player, `Sold a {species.name} egg for 💰 {amount}`, "good")
end

-- Friends standing near your incubators warm your eggs (2x speed).
local function friendWarmTick()
	local now = Clock.now()
	for _, session in Sessions.ready() do
		local profile = Data.get(session.player)
		if not profile or next(session.friendIds) == nil then
			continue
		end
		for slot, egg in profile.incubators do
			if egg.hatchAt <= now then
				continue
			end
			local position = Plots.incubatorPosition(session.player, slot)
			if not position then
				continue
			end
			for userId in session.friendIds do
				local friend = Players:GetPlayerByUserId(userId)
				local character = friend and friend.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if
					root
					and root:IsA("BasePart")
					and (root.CFrame.Position - position).Magnitude <= Config.FRIEND_WARM_RANGE
				then
					egg.hatchAt = math.max(now, egg.hatchAt - 1)
					Plots.syncIncubators(session.player)
					Plots.flagFriendWarm(session.player, slot)
					State.markDirty(session.player)
					break
				end
			end
		end
	end
end

local function ownerCheck(player: Player, prompt: ProximityPrompt): boolean
	return Prompts.ownerId(prompt) == player.UserId
end

function Eggs.init()
	Net.on("BuyEgg", 4, 6, function(player: Player, eggId: unknown)
		buyEgg(player, eggId)
	end)
	Net.on("HatchEgg", 4, 6, function(player: Player, slot: unknown)
		local key = validSlot(slot)
		if key then
			Eggs.hatch(player, key)
		end
	end)
	Net.on("WarmEgg", 8, 8, function(player: Player, slot: unknown)
		local key = validSlot(slot)
		if key then
			Eggs.warm(player, key)
		end
	end)
	Net.on("IncubateTrayEgg", 3, 5, function(player: Player, eggId: unknown)
		local id = validId(eggId)
		if id then
			incubateTrayEgg(player, id)
		end
	end)
	Net.on("SellTrayEgg", 3, 5, function(player: Player, eggId: unknown)
		local id = validId(eggId)
		if id then
			sellTrayEgg(player, id)
		end
	end)

	Prompts.register("IncubatorTap", function(player: Player, prompt: ProximityPrompt)
		local slot = Prompts.key(prompt)
		if not ownerCheck(player, prompt) or not slot then
			return
		end
		local profile = Data.get(player)
		local egg = profile and profile.incubators[slot]
		if not egg then
			return
		end
		if egg.hatchAt <= Clock.now() then
			Eggs.hatch(player, slot)
		else
			Eggs.warm(player, slot)
		end
	end)
	Prompts.register("TrayIncubate", function(player: Player, prompt: ProximityPrompt)
		local id = Prompts.key(prompt)
		if ownerCheck(player, prompt) and id then
			incubateTrayEgg(player, id)
		end
	end)
	Prompts.register("TraySell", function(player: Player, prompt: ProximityPrompt)
		local id = Prompts.key(prompt)
		if ownerCheck(player, prompt) and id then
			sellTrayEgg(player, id)
		end
	end)

	Sessions.Leaving:connect(function(player: Player)
		warmBudget[player] = nil
	end)
end

function Eggs.start()
	while true do
		task.wait(1)
		friendWarmTick()
	end
end

return Eggs
