--!strict
-- Coin math shared by server (authoritative) and client (display only).

local Config = require(script.Parent.Parent.Config)
local Growth = require(script.Parent.Growth)

local Economy = {}

export type MultiplierInput = {
	doubleCoins: boolean,
	vip: boolean,
	club: boolean,
	adBoost: boolean,
	friends: number,
	rebirths: number?,
}

-- Additive bonuses (friends, club) stack together, then multiplicative boosts apply.
function Economy.coinMultiplier(input: MultiplierInput): number
	local friendBonus =
		math.min(input.friends * Config.FRIEND_BOOST_PER_FRIEND, Config.FRIEND_BOOST_MAX)
	local additive = 1 + friendBonus + (if input.club then Config.CLUB_COIN_BONUS else 0)
	local multiplier = additive
	if input.doubleCoins then
		multiplier *= Config.DOUBLE_COINS_MULTIPLIER
	end
	if input.adBoost then
		multiplier *= Config.AD_BOOST_MULTIPLIER
	end
	if input.vip then
		multiplier *= Config.VIP_COIN_MULTIPLIER
	end
	return multiplier * Economy.rebirthMultiplier(input.rebirths or 0)
end

-- Permanent coin boost from rebirths.
function Economy.rebirthMultiplier(rebirths: number): number
	return 1 + rebirths * Config.REBIRTH_BONUS
end

-- Coins needed for the next rebirth after `rebirths` of them.
function Economy.rebirthCost(rebirths: number): number
	return math.floor(Config.REBIRTH_BASE_COST * Config.REBIRTH_COST_GROWTH ^ rebirths)
end

-- Coins from selling a dino.
function Economy.dinoValue(baseIncome: number, stage: number, mutationMultiplier: number): number
	return math.floor(baseIncome * 300 * Growth.SELL[math.clamp(stage, 1, 4)] * mutationMultiplier)
end

-- Extra income/value multiplier for Golden dinos.
function Economy.goldenMultiplier(golden: boolean?): number
	return if golden then Config.GOLDEN_MULTIPLIER else 1
end

-- Coins it costs to fuse three dinos of a species into a Golden one.
function Economy.goldenFee(baseIncome: number): number
	return math.max(100, math.floor(baseIncome * Config.GOLDEN_FEE_SECONDS))
end

-- Coins from selling a laid egg from your tray.
function Economy.trayEggValue(baseIncome: number): number
	return math.max(1, math.floor(baseIncome * 120))
end

-- Coins earned while offline (reduced rate, capped).
function Economy.offlineCoins(incomePerSecond: number, secondsAway: number): number
	local seconds = math.clamp(secondsAway, 0, Config.OFFLINE_EARNINGS_CAP_SECONDS)
	return math.floor(incomePerSecond * seconds * Config.OFFLINE_EARNINGS_RATE)
end

-- "X minutes of your income, or the minimum" rewards (coin packs, streaks, club).
function Economy.incomeReward(incomePerSecond: number, minutes: number, minimum: number): number
	return math.max(minimum, math.floor(incomePerSecond * minutes * 60))
end

-- Cost of the next upgrade level, or nil when maxed. `owned` = levels already bought.
function Economy.nextUpgradeCost(costs: { number }, owned: number): number?
	return costs[owned + 1]
end

return Economy
