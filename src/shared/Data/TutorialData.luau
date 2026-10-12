--!strict
-- First-session tutorial. The server decides the step; the client shows the
-- hint and an arrow toward the target. Designed so a new player hatches a dino
-- in under 30 seconds and gets a rare one before 2 minutes.

export type Target = "Incubator" | "Pad" | "Shop" | "Thief" | "Lock" | "None"

export type Step = {
	text: string,
	target: Target,
	funnelName: string,
}

local TutorialData = {
	DONE = 99,
	STEPS = {
		{
			text = "Tap your glowing egg to warm it up! 🔥",
			target = "Incubator",
			funnelName = "WarmStarterEgg",
		},
		{
			text = "Your first dino! Step on the gold pad to collect coins 💰",
			target = "Pad",
			funnelName = "CollectCoins",
		},
		{
			text = "Head to the Egg Shop in the middle of the island and buy an egg 🥚",
			target = "Shop",
			funnelName = "BuyFirstEgg",
		},
		{
			text = "A shiny Gift Egg appeared at your nest! Go hatch it ✨",
			target = "Incubator",
			funnelName = "HatchGiftEgg",
		},
		{
			text = "Night raid practice! Tap the sneaky raptor to chase it off 🦖",
			target = "Thief",
			funnelName = "RaidPractice",
		},
		{
			text = "At night, lock your gate 🔒 to keep thieves out. Your dinos grow even while you're away!",
			target = "Lock",
			funnelName = "LockGate",
		},
	} :: { Step },
	STARTER_SPECIES = "Raptor",
	GIFT_SPECIES = "Parasaur",
	GIFT_MUTATION = "Glossy",
}

return TutorialData
