--!strict
-- Info card for one of your dinos (opened from its "View" prompt): growth
-- progress, income, mutation, and Sell / Ride / Buddy buttons.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local Config = require(ReplicatedStorage.Shared.Config)
local DinoData = require(ReplicatedStorage.Shared.Data.DinoData)
local DinoModel = require(ReplicatedStorage.Shared.Visual.DinoModel)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Growth = require(ReplicatedStorage.Shared.Util.Growth)
local MutationData = require(ReplicatedStorage.Shared.Data.MutationData)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local ClientState = require(script.Parent.ClientState)
local Panels = require(script.Parent.Parent.Lib.Panels)
local UI = require(script.Parent.Parent.Lib.UI)

local DinoPanel = {}

local currentId: string? = nil
local shownKey = ""
local showcase: Frame
local previewHolder: Frame
local nameLabel: TextLabel
local rarityChip: UI.Chip
local stageChip: UI.Chip
local mutationChip: UI.Chip
local growthLabel: TextLabel
local growthBar: UI.Bar
local incomeLabel: TextLabel
local extraLabel: TextLabel
local sellButton: UI.Button
local rideButton: UI.Button
local buddyButton: UI.Button
local sellArmedUntil = 0

local function findDino(snapshot: Types.Snapshot, id: string): Types.DinoRecord?
	for _, dino in snapshot.dinos do
		if dino.id == id then
			return dino
		end
	end
	return nil
end

local function refresh()
	local snapshot = ClientState.get()
	local id = currentId
	if not snapshot or not id then
		return
	end
	local dino = findDino(snapshot, id)
	local species = dino and DinoData.get(dino.species)
	if not dino or not species then
		Panels.close()
		return
	end
	local now = Clock.now()
	local stage, fraction, secondsLeft = Growth.progress(now - dino.bornAt, species.growth)
	local mutation = MutationData.get(dino.mutation)
	local rarityColor = UI.rgb(DinoData.rarityInfo(species.rarity).color)

	local key = `{dino.id}:{stage}:{dino.mutation or ""}`
	if key ~= shownKey then
		shownKey = key
		for _, child in previewHolder:GetChildren() do
			child:Destroy()
		end
		UI.viewport(
			DinoModel.build(dino.species, stage, dino.mutation, "Static"),
			UDim2.fromScale(1, 1),
			previewHolder,
			30
		)
		showcase.BackgroundColor3 =
			UI.lighten(if mutation then UI.rgb(mutation.color) else rarityColor, 0.65)
	end

	nameLabel.Text = species.name
	rarityChip.label.Text = species.rarity
	UI.setChipColor(rarityChip, rarityColor)
	stageChip.label.Text = Growth.stageName(stage)
	mutationChip.root.Visible = mutation ~= nil
	if mutation then
		mutationChip.label.Text = `{mutation.emoji} {mutation.name} x{mutation.multiplier}`
		UI.setChipColor(mutationChip, UI.rgb(mutation.color))
	end
	if stage >= Growth.GIANT then
		growthLabel.Text = "Fully grown GIANT! 🏆"
		UI.setBar(growthBar, 1, "MAX")
	else
		growthLabel.Text =
			`Grows into a {Growth.stageName(stage + 1)} in {Format.time(secondsLeft)}`
		UI.setBar(growthBar, fraction, `{math.floor(fraction * 100)}%`)
	end
	local income = Growth.income(species.income, stage, MutationData.multiplier(dino.mutation))
		* snapshot.multiplier
	incomeLabel.Text = `+{Format.number(income)} / sec`
	local lays = Growth.layInterval(stage, Config.LAY_INTERVAL_ADULT, Config.LAY_INTERVAL_GIANT)
	extraLabel.Text = if lays
		then `🥚 Lays an egg every {Format.duration(lays)}\n🛡 Guards your nest at night`
		else "🍼 Too young to lay eggs or guard the nest yet"

	local value = Economy.dinoValue(species.income, stage, MutationData.multiplier(dino.mutation))
	if now < sellArmedUntil then
		UI.setButton(sellButton, { text = "Sure? Tap again!", color = UI.Theme.red })
	else
		UI.setButton(
			sellButton,
			{ text = "Sell 💰" .. Format.number(value), color = UI.Theme.orange }
		)
	end

	if snapshot.riding == dino.id then
		UI.setButton(rideButton, { text = "⬇ Get off", color = UI.Theme.grey, enabled = true })
	elseif not snapshot.passes.RideDinos then
		UI.setButton(
			rideButton,
			{ text = "🦖 Ride (pass)", color = UI.Theme.blue, enabled = true }
		)
	elseif stage < Growth.JUVENILE then
		UI.setButton(rideButton, { text = "Too small", color = UI.Theme.blue, enabled = false })
	else
		UI.setButton(rideButton, { text = "🦖 Ride!", color = UI.Theme.blue, enabled = true })
	end

	local isBuddy = snapshot.buddy == dino.id
	UI.setButton(
		buddyButton,
		{ text = if isBuddy then "💗 Buddy ✓" else "💗 Buddy", enabled = true }
	)
end

function DinoPanel.open(dinoId: string)
	currentId = dinoId
	shownKey = ""
	sellArmedUntil = 0
	refresh()
	Panels.open("Dino")
end

function DinoPanel.init()
	local _, content =
		Panels.window("Dino", "🦖 Your Dino", Vector2.new(820, 470), UI.Theme.green)
	showcase = UI.new("Frame", {
		Name = "Showcase",
		Size = UDim2.fromOffset(300, 362),
		BackgroundColor3 = UI.Theme.panelDark,
		Parent = content,
	}, { UI.corner(22), UI.stroke(UI.Theme.cardEdge, 3), UI.shade(0.86) }) :: Frame
	previewHolder = UI.new("Frame", {
		Name = "Preview",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -16, 1, -16),
		Position = UDim2.fromOffset(8, 8),
		Parent = showcase,
	}) :: Frame

	local right = UI.new("Frame", {
		Name = "Info",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(320, 0),
		Size = UDim2.new(1, -320, 1, 0),
		Parent = content,
	}) :: Frame
	nameLabel = UI.body({
		text = "",
		size = UDim2.new(1, 0, 0, 44),
		font = UI.Font,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 38,
		parent = right,
	})
	local tags = UI.new("Frame", {
		Name = "Tags",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 32),
		Position = UDim2.fromOffset(0, 50),
		Parent = right,
	}, { UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left) }) :: Frame
	rarityChip = UI.chip({
		text = "",
		size = UDim2.fromOffset(120, 32),
		order = 1,
		maxTextSize = 18,
		parent = tags,
	})
	stageChip = UI.chip({
		text = "",
		size = UDim2.fromOffset(110, 32),
		color = UI.Theme.teal,
		order = 2,
		maxTextSize = 18,
		parent = tags,
	})
	mutationChip = UI.chip({
		text = "",
		size = UDim2.fromOffset(170, 32),
		order = 3,
		maxTextSize = 18,
		parent = tags,
	})

	growthLabel = UI.body({
		text = "",
		size = UDim2.new(1, 0, 0, 24),
		position = UDim2.fromOffset(0, 96),
		align = Enum.TextXAlignment.Left,
		maxTextSize = 19,
		parent = right,
	})
	growthBar = UI.bar({
		size = UDim2.new(1, -6, 0, 28),
		position = UDim2.fromOffset(0, 124),
		color = UI.Theme.green,
		parent = right,
	})

	local stats = UI.card({
		name = "Stats",
		size = UDim2.new(1, -6, 0, 118),
		position = UDim2.fromOffset(0, 166),
		radius = 16,
		parent = right,
	})
	local coin = UI.coin(44, stats)
	coin.Position = UDim2.fromOffset(14, 12)
	incomeLabel = UI.body({
		text = "",
		size = UDim2.new(1, -80, 0, 40),
		position = UDim2.fromOffset(68, 14),
		color = UI.Theme.money,
		font = UI.Font,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 32,
		parent = stats,
	})
	extraLabel = UI.body({
		text = "",
		size = UDim2.new(1, -28, 0, 50),
		position = UDim2.fromOffset(14, 62),
		color = UI.Theme.inkSoft,
		align = Enum.TextXAlignment.Left,
		valign = Enum.TextYAlignment.Top,
		maxTextSize = 17,
		parent = stats,
	})

	local buttons = UI.new("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -6, 0, 60),
		Position = UDim2.new(0, 0, 1, -66),
		Parent = right,
	}, { UI.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left) }) :: Frame
	sellButton = UI.button({
		name = "Sell",
		text = "Sell",
		size = UDim2.new(0.36, -7, 0, 58),
		color = UI.Theme.orange,
		order = 1,
		maxTextSize = 22,
		parent = buttons,
		onClick = function()
			local id = currentId
			if not id then
				return
			end
			if Clock.now() < sellArmedUntil then
				sellArmedUntil = 0
				Net.send("SellDino", id)
			else
				sellArmedUntil = Clock.now() + 3
				refresh()
			end
		end,
	})
	rideButton = UI.button({
		name = "Ride",
		text = "Ride",
		size = UDim2.new(0.34, -7, 0, 58),
		color = UI.Theme.blue,
		order = 2,
		maxTextSize = 22,
		parent = buttons,
		onClick = function()
			local id = currentId
			local snapshot = ClientState.get()
			if not id or not snapshot then
				return
			end
			if snapshot.riding == id then
				Net.send("Ride", nil)
			elseif not snapshot.passes.RideDinos then
				Net.send("PromptPurchase", "pass", "RideDinos")
			else
				Net.send("Ride", id)
				Panels.close()
			end
		end,
	})
	buddyButton = UI.button({
		name = "Buddy",
		text = "💗 Buddy",
		size = UDim2.new(0.3, -6, 0, 58),
		color = UI.Theme.pink,
		order = 3,
		maxTextSize = 22,
		parent = buttons,
		onClick = function()
			local id = currentId
			local snapshot = ClientState.get()
			if not id or not snapshot then
				return
			end
			Net.send("SetBuddy", if snapshot.buddy == id then nil else id)
		end,
	})

	ClientState.changed:connect(function(_: Types.Snapshot)
		if Panels.isOpen("Dino") then
			refresh()
		end
	end)
end

function DinoPanel.start()
	while true do
		task.wait(0.5)
		if Panels.isOpen("Dino") then
			refresh()
		end
	end
end

return DinoPanel
