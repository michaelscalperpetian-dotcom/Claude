--!strict
-- Game passes, developer products, the Dino Club subscription and rewarded
-- video ads. Purchases are granted in ProcessReceipt, which is idempotent: a
-- purchase ID is recorded in the player's save and never granted twice, and we
-- only tell Roblox "granted" after the save succeeds.
--
-- Policy: players for whom PolicyService says paid random items are restricted
-- can't buy coins or luck (both feed the random egg hatches); they earn coins
-- by playing instead. See docs/game-plan.md section 2.5.

local AdService = game:GetService("AdService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Analytics = require(script.Parent.Analytics)
local Coins = require(script.Parent.Coins)
local Data = require(script.Parent.Data)
local Eggs = require(script.Parent.Eggs)
local Prompts = require(script.Parent.Prompts)
local Raids = require(script.Parent.Raids)
local Sessions = require(script.Parent.Sessions)
local State = require(script.Parent.State)
local Notify = require(script.Parent.Parent.Lib.Notify)
local Stats = require(script.Parent.Parent.Lib.Stats)

local Monetization = {}

-- (player) fired when passes or subscription status change.
Monetization.PassesChanged = Signal.new() :: Signal.Signal<Player>

-- Products that feed random egg results; hidden from restricted players.
local RANDOM_FEEDING: { [string]: boolean } = {
	StarterPack = true,
	CoinsSmall = true,
	CoinsMedium = true,
	CoinsLarge = true,
	CoinsHuge = true,
	CoinsMega = true,
	LuckyPotion = true,
}

-- Products a client may ask to buy (AdCoinBoost only comes from ads).
local SELLABLE: { [string]: boolean } = {
	StarterPack = true,
	CoinsSmall = true,
	CoinsMedium = true,
	CoinsLarge = true,
	CoinsHuge = true,
	CoinsMega = true,
	LuckyPotion = true,
	SuperLock = true,
}

local passKeyById: { [number]: string } = {}
local productKeyById: { [number]: string } = {}

local function productId(key: string): number
	return (Config.PRODUCT_IDS :: { [string]: number })[key] or 0
end

local function passId(key: string): number
	return (Config.GAME_PASS_IDS :: { [string]: number })[key] or 0
end

-- ===== Granting =====

local function grantProduct(player: Player, key: string)
	local profile = Data.get(player)
	local session = Sessions.get(player)
	assert(profile and session, "profile not loaded")
	local now = Clock.now()

	local pack = (Config.COIN_PACKS :: { [string]: { minutes: number, minimum: number } })[key]
	if pack then
		local income = Stats.incomePerSecond(profile, session, now)
		local amount = Economy.incomeReward(income, pack.minutes, pack.minimum)
		Coins.add(player, amount, "IAP", key)
		Notify.send(player, `💰 +{Format.number(amount)} coins! Thank you!`, "good")
	elseif key == "StarterPack" then
		profile.starterPackBought = true
		Coins.add(player, Config.STARTER_PACK.coins, "IAP", key)
		profile.boosts.luckUntil = math.max(profile.boosts.luckUntil, now)
			+ Config.STARTER_PACK.luckSeconds
		Notify.send(player, "🎁 Starter Pack: coins + 30 minutes of Luck!", "good")
	elseif
		key == "InstantHatchSmall"
		or key == "InstantHatchMedium"
		or key == "InstantHatchLarge"
	then
		local slot = session.pendingInstantHatch
		session.pendingInstantHatch = nil
		if not Eggs.finishNow(player, slot) then
			profile.instantHatchTokens += 1
			Notify.send(player, "⚡ Saved an Instant Hatch for your next egg!", "good")
		end
	elseif key == "LuckyPotion" then
		profile.boosts.luckUntil = math.max(profile.boosts.luckUntil, now)
			+ Config.LUCK_POTION_SECONDS
		Notify.send(player, "🍀 Lucky Potion active! Rare dinos are twice as likely.", "good")
	elseif key == "SuperLock" then
		Raids.superLock(player)
		Notify.send(player, "🔒 Super Lock! Your nest is sealed for 5 minutes.", "good")
	elseif key == "AdCoinBoost" then
		profile.boosts.coinsUntil = math.max(profile.boosts.coinsUntil, now)
			+ Config.AD_BOOST_SECONDS
		Notify.send(player, "⚡ 2x Coins for 10 minutes! Thanks for watching.", "good")
	else
		error(`unknown product {key}`)
	end
	State.markDirty(player)
end

local function processReceipt(receiptInfo: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = Data.get(player)
	local session = Sessions.get(player)
	if not profile or not session or not session.ready then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receiptInfo.PurchaseId)
	if Data.hasReceipt(profile, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local key = productKeyById[receiptInfo.ProductId]
	if not key then
		warn(`[Monetization] unknown product id {receiptInfo.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local granted = table.pack(pcall(grantProduct, player, key))
	if not granted[1] then
		warn(`[Monetization] grant {key} failed: {granted[2]}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	Data.addReceipt(profile, purchaseId)
	Analytics.event(player, "Purchase" .. key, receiptInfo.CurrencySpent)
	if Data.saveNow(player) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	-- Granted in memory and recorded; Roblox will retry and the receipt check
	-- above prevents a second grant.
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- ===== Prompting =====

local function instantHatchProduct(secondsLeft: number): string
	if secondsLeft <= Config.INSTANT_HATCH_SMALL_MAX_SECONDS then
		return "InstantHatchSmall"
	elseif secondsLeft <= Config.INSTANT_HATCH_MEDIUM_MAX_SECONDS then
		return "InstantHatchMedium"
	end
	return "InstantHatchLarge"
end

function Monetization.promptInstantHatch(player: Player, slot: string)
	local profile = Data.get(player)
	local session = Sessions.get(player)
	if not profile or not session then
		return
	end
	local egg = profile.incubators[slot]
	local now = Clock.now()
	if not egg or egg.hatchAt <= now then
		return
	end
	if profile.instantHatchTokens > 0 then
		profile.instantHatchTokens -= 1
		Eggs.finishNow(player, slot)
		State.markDirty(player)
		return
	end
	local key = instantHatchProduct(egg.hatchAt - now)
	local id = productId(key)
	if id == 0 then
		Notify.send(player, "Instant Hatch isn't set up yet (add product IDs in Config).", "info")
		return
	end
	session.pendingInstantHatch = slot
	MarketplaceService:PromptProductPurchase(player, id)
end

local function promptPurchase(player: Player, kind: unknown, key: unknown, context: unknown)
	local session = Sessions.get(player)
	local profile = Data.get(player)
	if not session or not profile or not session.ready then
		return
	end
	if typeof(kind) ~= "string" or typeof(key) ~= "string" then
		return
	end
	if kind == "pass" then
		local id = passId(key)
		if id == 0 then
			Notify.send(player, "This pass isn't set up yet (add its ID in Config).", "info")
			return
		end
		if not Stats.hasPass(session, key) then
			MarketplaceService:PromptGamePassPurchase(player, id)
		end
	elseif kind == "product" then
		if key == "InstantHatch" then
			if typeof(context) == "string" and tonumber(context) then
				Monetization.promptInstantHatch(player, context)
			end
			return
		end
		if not SELLABLE[key] then
			return
		end
		if session.restricted and RANDOM_FEEDING[key] then
			return
		end
		if key == "StarterPack" and profile.starterPackBought then
			return
		end
		local id = productId(key)
		if id == 0 then
			Notify.send(player, "This item isn't set up yet (add its ID in Config).", "info")
			return
		end
		MarketplaceService:PromptProductPurchase(player, id)
	elseif kind == "subscription" then
		if Config.SUBSCRIPTION_ID ~= "" and not session.subscribed then
			MarketplaceService:PromptSubscriptionPurchase(player, Config.SUBSCRIPTION_ID)
		end
	end
end

-- ===== Ownership checks =====

local function refreshSubscription(player: Player)
	local session = Sessions.get(player)
	if not session or Config.SUBSCRIPTION_ID == "" then
		return
	end
	local ok, status = pcall(function()
		return MarketplaceService:GetUserSubscriptionStatusAsync(player, Config.SUBSCRIPTION_ID)
	end)
	if ok and type(status) == "table" then
		session.subscribed = status.IsSubscribed == true
		Monetization.PassesChanged:fire(player)
		State.markDirty(player)
	end
end

-- Called by Lifecycle when a player joins (yields; run in its own thread).
function Monetization.onJoin(player: Player)
	local session = Sessions.get(player)
	if not session then
		return
	end
	for key, id in Config.GAME_PASS_IDS :: { [string]: number } do
		if id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
			end)
			if ok and owns then
				session.passes[key] = true
			end
		end
	end
	local ok, policy = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	if ok and type(policy) == "table" then
		session.restricted = policy.ArePaidRandomItemsRestricted == true
		session.tradingAllowed = policy.IsPaidItemTradingAllowed == true
	else
		-- Unknown policy: be safe in live games, permissive while testing in Studio.
		session.restricted = not RunService:IsStudio()
	end
	refreshSubscription(player)
	Monetization.PassesChanged:fire(player)
	State.markDirty(player)
end

-- QA: toggle a pass without buying it (Studio / dev allowlist only; checked by Cheats).
function Monetization.toggleFakePass(player: Player, key: string)
	local session = Sessions.get(player)
	if not session or (Config.GAME_PASS_IDS :: { [string]: number })[key] == nil then
		return
	end
	if session.fakePasses[key] then
		session.fakePasses[key] = nil
	else
		session.fakePasses[key] = true
	end
	Monetization.PassesChanged:fire(player)
	State.markDirty(player)
end

local function watchAd(player: Player)
	local session = Sessions.get(player)
	local id = productId("AdCoinBoost")
	if not session or id == 0 then
		return
	end
	local ok, result = pcall(function()
		local reward = AdService:CreateAdRewardFromDevProductId(id)
		return AdService:ShowRewardedVideoAdAsync(player, reward)
	end)
	if not ok then
		Notify.send(player, "No video available right now. Try again later!", "info")
	elseif result ~= Enum.ShowAdResult.ShowCompleted then
		Notify.send(player, "Watch the whole video to get the reward.", "info")
	end
	-- The reward itself arrives through ProcessReceipt (AdCoinBoost).
end

function Monetization.init()
	for key, id in Config.GAME_PASS_IDS :: { [string]: number } do
		if id ~= 0 then
			passKeyById[id] = key
		end
	end
	for key, id in Config.PRODUCT_IDS :: { [string]: number } do
		if id ~= 0 then
			productKeyById[id] = key
		end
	end

	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, id: number, purchased: boolean)
			local key = passKeyById[id]
			local session = Sessions.get(player)
			if purchased and key and session then
				session.passes[key] = true
				Analytics.event(player, "Pass" .. key)
				Notify.send(player, "🎉 Thanks for your support! Your pass is active.", "good")
				Monetization.PassesChanged:fire(player)
				State.markDirty(player)
			end
		end
	)

	MarketplaceService.PromptSubscriptionPurchaseFinished:Connect(function(player: Player)
		refreshSubscription(player)
	end)
	Players.UserSubscriptionStatusChanged:Connect(function(player: Player)
		refreshSubscription(player)
	end)

	Net.on("PromptPurchase", 2, 4, promptPurchase)
	Net.on("WatchAd", 1 / 15, 1, function(player: Player)
		watchAd(player)
	end)

	Prompts.register("InstantHatch", function(player: Player, prompt: ProximityPrompt)
		local slot = Prompts.key(prompt)
		if slot and Prompts.ownerId(prompt) == player.UserId then
			Monetization.promptInstantHatch(player, slot)
		end
	end)
end

return Monetization
