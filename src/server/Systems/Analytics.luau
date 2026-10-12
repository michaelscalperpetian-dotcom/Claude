--!strict
-- Thin wrapper around AnalyticsService. Every call is pcall'd: analytics must
-- never break gameplay. Results show up in Creator Hub > Analytics.

local AnalyticsService = game:GetService("AnalyticsService")

local Analytics = {}

export type Transaction =
	"Gameplay"
	| "Shop"
	| "IAP"
	| "Onboarding"
	| "TimedReward"
	| "ContextualPurchase"

local TRANSACTIONS: { [Transaction]: Enum.AnalyticsEconomyTransactionType } = {
	Gameplay = Enum.AnalyticsEconomyTransactionType.Gameplay,
	Shop = Enum.AnalyticsEconomyTransactionType.Shop,
	IAP = Enum.AnalyticsEconomyTransactionType.IAP,
	Onboarding = Enum.AnalyticsEconomyTransactionType.Onboarding,
	TimedReward = Enum.AnalyticsEconomyTransactionType.TimedReward,
	ContextualPurchase = Enum.AnalyticsEconomyTransactionType.ContextualPurchase,
}

-- Onboarding funnel: log each step once, in order (1, 2, 3...).
function Analytics.funnel(player: Player, step: number, name: string)
	local ok, err = pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)
	end)
	if not ok then
		warn(`[Analytics] funnel {step} failed: {err}`)
	end
end

function Analytics.economy(
	player: Player,
	flow: "Source" | "Sink",
	amount: number,
	endingBalance: number,
	transaction: Transaction,
	sku: string?
)
	local rounded = math.floor(amount)
	if rounded <= 0 then
		return
	end
	local flowType = if flow == "Source"
		then Enum.AnalyticsEconomyFlowType.Source
		else Enum.AnalyticsEconomyFlowType.Sink
	pcall(function()
		AnalyticsService:LogEconomyEvent(
			player,
			flowType,
			"Coins",
			rounded,
			math.floor(endingBalance),
			TRANSACTIONS[transaction].Name,
			sku
		)
	end)
end

function Analytics.event(player: Player, name: string, value: number?)
	pcall(function()
		AnalyticsService:LogCustomEvent(player, name, value)
	end)
end

return Analytics
