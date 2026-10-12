--!nocheck
-- Client smoke test: builds every HUD element and panel with real Roblox GUI
-- classes (Lune validates every property name), feeds in a state snapshot,
-- opens every window, walks the tutorial steps and plays a hatch reveal.
-- Run with: lune run tests/client_smoke

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local taskLib = require("@lune/task")
local ClientEnv = require("./support/ClientEnv")

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

local env
step("every controller loads and initializes", function()
	env = ClientEnv.new()
	assert(env.playerGui:FindFirstChild("HUD"), "HUD screen")
	assert(env.playerGui:FindFirstChild("Panels"), "Panels screen")
end)
if not env then
	process.exit(1)
end

local C = env.C
local listeners = env.listeners
local sent = env.sent
local playerGui = env.playerGui
local snapshot = env.snapshot

step("a state snapshot updates the HUD", function()
	listeners.State(snapshot())
	taskLib.wait(0.05)
end)

step("every window opens and renders", function()
	local Panels = env.Panels
	Panels.open("Shop")
	taskLib.wait(0.05)
	C.ShopUI.showOdds("Crystal")
	taskLib.wait(0.05)
	Panels.open("Store")
	taskLib.wait(0.1)
	Panels.open("Dex")
	taskLib.wait(0.05)
	Panels.open("Rewards")
	taskLib.wait(0.05)
	C.DinoPanel.open("2")
	taskLib.wait(0.05)
	Panels.open("Dev")
	Panels.close()
end)

step("policy-restricted players don't see coin packs or luck", function()
	listeners.State(snapshot({ restricted = true }))
	C.StoreUI.refresh()
	local panels = playerGui:FindFirstChild("Panels")
	local store = panels:FindFirstChild("Store")
	local hiddenCoins, hiddenLuck = false, false
	for _, d in store:GetDescendants() do
		if d.Name == "CoinsSmall" then
			hiddenCoins = d.Visible == false
		elseif d.Name == "LuckyPotion" then
			hiddenLuck = d.Visible == false
		end
	end
	assert(hiddenCoins and hiddenLuck, "random-feeding products hidden")
end)

step("tutorial walks through every step", function()
	for tutorialStep = 1, 5 do
		listeners.State(snapshot({ tutorial = tutorialStep }))
		taskLib.wait(0.05)
	end
	listeners.State(snapshot({ tutorial = 99 }))
	taskLib.wait(0.05)
end)

step("toasts and effects play", function()
	C.Toasts.show("Hello!", "good")
	listeners.Notify("From the server", "rare")
	listeners.Effect("Dex", { species = "Raptor" })
	listeners.Effect("Reward", { day = 1 })
	listeners.Effect("Roar", { position = roblox.Vector3.new(0, 0, 0), big = true })
	listeners.Effect("Mutate", { position = roblox.Vector3.new(0, 0, 0), mutation = "Lava" })
end)

step("hatch reveal plays to the end", function()
	listeners.Effect("Hatch", { species = "TRex", mutation = "Cosmic" })
	taskLib.wait(5)
end)

-- Candy buttons keep their text on a label inside the clickable face.
local function click(root, text)
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == text and d.Parent and d.Parent:IsA("TextButton") then
			d.Parent.Activated:Fire()
			return true
		end
	end
	return false
end

local function sentMessage(name)
	for _, message in sent do
		if message.name == name then
			return message
		end
	end
	return nil
end

step("buttons send the right requests", function()
	local hud = playerGui:FindFirstChild("HUD")
	assert(click(hud, "🦖 Roar"), "roar button")
	assert(sentMessage("Roar"), "Roar sent")
end)

step("new windows: quests, settings and codes", function()
	local Panels = env.Panels
	assert(Panels.has("Quests") and Panels.has("Settings"), "windows exist")
	listeners.State(
		snapshot({ quests = { day = 0, progress = {}, claimed = {}, bonusClaimed = false } })
	)
	Panels.open("Quests")
	taskLib.wait(0.05)
	Panels.open("Settings")
	taskLib.wait(0.05)
	local panels = playerGui:FindFirstChild("Panels")
	local settings = panels:FindFirstChild("Settings")
	assert(
		settings:FindFirstChild("music", true) == nil,
		"no Music switch without tracks in Config"
	)
	local sfx = settings:FindFirstChild("sfx", true)
	local switch = sfx:FindFirstChild("Switch")
	switch.Activated:Fire()
	local message = sentMessage("SetSetting")
	assert(
		message and message.args[1] == "sfx" and message.args[2] == false,
		"sound effects switched off"
	)
	local box = settings:FindFirstChild("CodeBox", true)
	box.Text = "dino"
	assert(click(settings, "Redeem"), "redeem button")
	local redeem = sentMessage("RedeemCode")
	assert(redeem and redeem.args[1] == "dino", "code sent")
	Panels.close()
end)

step("quest badge lights up when a quest is done", function()
	local QuestData = require("./loader").load("src/shared/Data/QuestData")
	local day = snapshot().quests.day
	local first = QuestData.forDay(day)[1]
	local s = snapshot({
		quests = {
			day = day,
			progress = { [first.id] = first.goal },
			claimed = {},
			bonusClaimed = false,
		},
	})
	assert(C.QuestsUI.claimable(s), "claimable")
	s.quests.claimed[first.id] = true
	assert(not C.QuestsUI.claimable(s), "nothing left after claiming")
end)

step("a buddy attribute spawns a follower", function()
	env.localPlayer:SetAttribute("Buddy", "Raptor||3")
	env.attributeChanged(env.localPlayer, "Buddy")
	taskLib.wait(0.05)
	local folder = env.workspace:FindFirstChild("Buddies")
	assert(folder and #folder:GetChildren() == 1, "follower built")
	env.localPlayer:SetAttribute("Buddy", nil)
	env.attributeChanged(env.localPlayer, "Buddy")
	taskLib.wait(0.05)
	assert(#folder:GetChildren() == 0, "follower removed")
end)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
