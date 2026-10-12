--!strict
-- The only code that changes a player's coins. Logs sources and sinks to
-- analytics and keeps the leaderboard in sync.

local Analytics = require(script.Parent.Analytics)
local Data = require(script.Parent.Data)
local State = require(script.Parent.State)

local Coins = {}

local function updateLeaderstats(player: Player, coins: number)
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Coins")
	if value and value:IsA("NumberValue") then
		value.Value = math.floor(coins)
	end
end

function Coins.setupLeaderstats(player: Player)
	local profile = Data.get(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local coins = Instance.new("NumberValue")
	coins.Name = "Coins"
	coins.Value = if profile then math.floor(profile.coins) else 0
	coins.Parent = stats
	local dex = Instance.new("IntValue")
	dex.Name = "Dex"
	dex.Value = 0
	dex.Parent = stats
	stats.Parent = player
end

function Coins.setDexCount(player: Player, count: number)
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Dex")
	if value and value:IsA("IntValue") then
		value.Value = count
	end
end

function Coins.add(
	player: Player,
	amount: number,
	transaction: Analytics.Transaction,
	sku: string?
): number
	local profile = Data.get(player)
	if not profile or amount ~= amount or amount <= 0 or amount == math.huge then
		return 0
	end
	local whole = math.floor(amount)
	profile.coins += whole
	profile.totalEarned += whole
	Analytics.economy(player, "Source", whole, profile.coins, transaction, sku)
	updateLeaderstats(player, profile.coins)
	State.markDirty(player)
	return whole
end

function Coins.spend(
	player: Player,
	amount: number,
	transaction: Analytics.Transaction,
	sku: string?
): boolean
	local profile = Data.get(player)
	if not profile or amount ~= amount or amount < 0 or amount == math.huge then
		return false
	end
	if profile.coins < amount then
		return false
	end
	profile.coins -= amount
	Analytics.economy(player, "Sink", amount, profile.coins, transaction, sku)
	updateLeaderstats(player, profile.coins)
	State.markDirty(player)
	return true
end

-- Income piles up on the coin pad until the player walks over it
-- (or goes straight to their wallet with the Auto-Collect pass).
function Coins.accrue(player: Player, amount: number, autoCollect: boolean)
	local profile = Data.get(player)
	if not profile or amount <= 0 then
		return
	end
	if autoCollect then
		profile.coins += amount
		profile.totalEarned += amount
		updateLeaderstats(player, profile.coins)
	else
		profile.pendingCoins += amount
	end
	State.markDirty(player)
end

function Coins.collect(player: Player): number
	local profile = Data.get(player)
	if not profile then
		return 0
	end
	local amount = math.floor(profile.pendingCoins)
	if amount <= 0 then
		return 0
	end
	profile.pendingCoins -= amount
	return Coins.add(player, amount, "Gameplay", "CoinPad")
end

return Coins
