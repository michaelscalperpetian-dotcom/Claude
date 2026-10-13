--!strict
-- Info card for one of your dinos (opened from its "View" prompt): its name
-- (tap ✏️ to rename), growth progress, income, mutation, Make Golden (fuse 3
-- of a species), Feed (fruit from the fruit trees), and Sell / Ride / Buddy.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local Config = require(ReplicatedStorage.Shared.Config)
local DinoData = require(ReplicatedStorage.Shared.Data.DinoData)
local DinoModel = require(ReplicatedStorage.Shared.Visual.DinoModel)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local FruitData = require(ReplicatedStorage.Shared.Data.FruitData)
local Growth = require(ReplicatedStorage.Shared.Util.Growth)
local MutationData = require(ReplicatedStorage.Shared.Data.MutationData)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local ClientState = require(script.Parent.ClientState)
local Toasts = require(script.Parent.Toasts)
local Panels = require(script.Parent.Parent.Lib.Panels)
local UI = require(script.Parent.Parent.Lib.UI)

local DinoPanel = {}

local currentId: string? = nil
local shownKey = ""
local showcase: Frame
local previewHolder: Frame
local nameLabel: TextLabel
local nameBox: TextBox
local renameButton: UI.Button
local rarityChip: UI.Chip
local stageChip: UI.Chip
local mutationChip: UI.Chip
local goldenChip: UI.Chip
local growthLabel: TextLabel
local growthBar: UI.Bar
local incomeLabel: TextLabel
local extraLabel: TextLabel
local sellButton: UI.Button
local rideButton: UI.Button
local buddyButton: UI.Button
local goldenButton: UI.Button
local feedButton: UI.Button
local sellArmedUntil = 0
local goldenArmedUntil = 0

local function findDino(snapshot: Types.Snapshot, id: string): Types.DinoRecord?
	for _, dino in snapshot.dinos do
		if dino.id == id then
			return dino
		end
	end
	return nil
end

-- Non-golden dinos of this species you own (the ones a fuse can use).
local function fuseCount(snapshot: Types.Snapshot, speciesId: string): number
	local count = 0
	for _, dino in snapshot.dinos do
		if dino.species == speciesId and not dino.golden then
			count += 1
		end
	end
	return count
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

	local golden = dino.golden == true
	local key = `{dino.id}:{stage}:{dino.mutation or ""}:{golden}`
	if key ~= shownKey then
		shownKey = key
		for _, child in previewHolder:GetChildren() do
			child:Destroy()
		end
		UI.viewport(
			DinoModel.build(dino.species, stage, dino.mutation, "Static", golden),
			UDim2.fromScale(1, 1),
			previewHolder,
			30
		)
		showcase.BackgroundColor3 = UI.lighten(
			if golden then UI.Theme.gold elseif mutation then UI.rgb(mutation.color) else rarityColor,
			0.65
		)
	end

	Panels.setTitle("Dino", `🦖 {species.name}`)
	nameLabel.Text = dino.name or species.name
	rarityChip.label.Text = species.rarity
	UI.setChipColor(rarityChip, rarityColor)
	stageChip.label.Text = Growth.stageName(stage)
	mutationChip.root.Visible = mutation ~= nil
	if mutation then
		mutationChip.label.Text = `{mutation.emoji} {mutation.name} x{mutation.multiplier}`
		UI.setChipColor(mutationChip, UI.rgb(mutation.color))
	end
	goldenChip.root.Visible = golden
	if stage >= Growth.GIANT then
		growthLabel.Text = "Fully grown GIANT! 🏆"
		UI.setBar(growthBar, 1, "MAX")
	else
		growthLabel.Text =
			`Grows into a {Growth.stageName(stage + 1)} in {Format.time(secondsLeft)}`
		UI.setBar(growthBar, fraction, `{math.floor(fraction * 100)}%`)
	end
	local multiplier = MutationData.multiplier(dino.mutation) * Economy.goldenMultiplier(golden)
	local income = Growth.income(species.income, stage, multiplier) * snapshot.multiplier
	incomeLabel.Text = `+{Format.number(income)} / sec`
	local lays = Growth.layInterval(stage, Config.LAY_INTERVAL_ADULT, Config.LAY_INTERVAL_GIANT)
	extraLabel.Text = if lays
		then `🥚 Lays an egg every {Format.duration(lays)}\n🛡 Guards your nest at night`
		else "🍼 Too young to lay eggs or guard the nest yet"

	local value = Economy.dinoValue(species.income, stage, multiplier)
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

	if golden then
		UI.setButton(
			goldenButton,
			{ text = "⭐ Golden ✓", color = UI.Theme.gold, enabled = false }
		)
	else
		local count = fuseCount(snapshot, dino.species)
		if count < 3 then
			UI.setButton(
				goldenButton,
				{ text = `⭐ Golden ({count}/3)`, color = UI.Theme.orange, enabled = true }
			)
		elseif now < goldenArmedUntil then
			UI.setButton(
				goldenButton,
				{ text = "Fuse 3? Tap again!", color = UI.Theme.red, enabled = true }
			)
		else
			UI.setButton(goldenButton, {
				text = `⭐ Make Golden 💰{Format.number(Economy.goldenFee(species.income))}`,
				color = UI.Theme.gold,
				enabled = true,
			})
		end
	end

	local fruitKind = FruitData.nextToFeed(snapshot.fruit)
	if stage >= Growth.GIANT then
		UI.setButton(
			feedButton,
			{ text = "🏆 Fully grown", color = UI.Theme.red, enabled = false }
		)
	elseif fruitKind then
		local info = FruitData.FRUITS[fruitKind]
		UI.setButton(feedButton, {
			text = `{info.emoji} Feed ({snapshot.fruit[fruitKind]})`,
			color = UI.Theme.red,
			enabled = true,
		})
	else
		UI.setButton(feedButton, { text = "🍎 No fruit", color = UI.Theme.red, enabled = true })
	end

	local isBuddy = snapshot.buddy == dino.id
	UI.setButton(
		buddyButton,
		{ text = if isBuddy then "💗 Buddy ✓" else "💗 Buddy", enabled = true }
	)
end

local function stopRenaming()
	nameBox.Visible = false
	nameLabel.Visible = true
	renameButton.root.Visible = true
end

local function startRenaming()
	local snapshot = ClientState.get()
	local dino = if snapshot and currentId then findDino(snapshot, currentId) else nil
	if not dino then
		return
	end
	nameBox.Text = dino.name or ""
	nameLabel.Visible = false
	renameButton.root.Visible = false
	nameBox.Visible = true
	nameBox:CaptureFocus()
end

function DinoPanel.open(dinoId: string)
	stopRenaming()
	currentId = dinoId
	shownKey = ""
	sellArmedUntil = 0
	goldenArmedUntil = 0
	refresh()
	Panels.open("Dino")
end

function DinoPanel.init()
	local _, content =
		Panels.window("Dino", "🦖 Your Dino", Vector2.new(820, 540), UI.Theme.green)
	showcase = UI.new("Frame", {
		Name = "Showcase",
		Size = UDim2.new(0, 300, 1, 0),
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
		size = UDim2.new(1, -60, 0, 44),
		font = UI.Font,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 38,
		parent = right,
	})
	nameBox = UI.new("TextBox", {
		Name = "NameBox",
		Text = "",
		PlaceholderText = "Give your dino a name!",
		ClearTextOnFocus = false,
		Visible = false,
		Size = UDim2.new(1, -6, 0, 46),
		BackgroundColor3 = UI.Theme.white,
		TextColor3 = UI.Theme.ink,
		PlaceholderColor3 = UI.Theme.grey,
		Font = UI.Font,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
		Parent = right,
	}, {
		UI.corner(14),
		UI.stroke(UI.Theme.ink, 3),
		UI.padding(14, 8),
		UI.new("UITextSizeConstraint", { MaxTextSize = 28 }),
	}) :: TextBox
	nameBox.FocusLost:Connect(function()
		local id = currentId
		local snapshot = ClientState.get()
		local dino = if snapshot and id then findDino(snapshot, id) else nil
		stopRenaming()
		if id and dino and nameBox.Text ~= (dino.name or "") then
			Net.send("RenameDino", id, nameBox.Text)
		end
	end)
	renameButton = UI.button({
		name = "Rename",
		text = "✏️",
		size = UDim2.fromOffset(50, 44),
		position = UDim2.new(1, -6, 0, 0),
		anchor = Vector2.new(1, 0),
		color = UI.Theme.purple,
		radius = 12,
		depth = 4,
		maxTextSize = 24,
		parent = right,
		onClick = startRenaming,
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
		size = UDim2.fromOffset(110, 32),
		order = 1,
		maxTextSize = 18,
		parent = tags,
	})
	stageChip = UI.chip({
		text = "",
		size = UDim2.fromOffset(100, 32),
		color = UI.Theme.teal,
		order = 2,
		maxTextSize = 18,
		parent = tags,
	})
	mutationChip = UI.chip({
		text = "",
		size = UDim2.fromOffset(150, 32),
		order = 3,
		maxTextSize = 18,
		parent = tags,
	})
	goldenChip = UI.chip({
		text = `⭐ x{Economy.goldenMultiplier(true)}`,
		size = UDim2.fromOffset(78, 32),
		color = UI.Theme.gold,
		order = 4,
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

	-- Care row: Make Golden (and Feed)
	local care = UI.new("Frame", {
		Name = "Care",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -6, 0, 60),
		Position = UDim2.new(0, 0, 1, -134),
		Parent = right,
	}, { UI.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left) }) :: Frame
	goldenButton = UI.button({
		name = "Golden",
		text = "⭐ Golden",
		size = UDim2.new(0.55, -5, 0, 58),
		color = UI.Theme.gold,
		order = 1,
		maxTextSize = 22,
		parent = care,
		onClick = function()
			local id = currentId
			local snapshot = ClientState.get()
			local dino = if snapshot and id then findDino(snapshot, id) else nil
			local species = if dino then DinoData.get(dino.species) else nil
			if not snapshot or not dino or not species or dino.golden then
				return
			end
			if fuseCount(snapshot, dino.species) < 3 then
				Toasts.show(
					`Collect 3 {species.name}s, then fuse them into one ⭐ Golden dino that earns {Economy.goldenMultiplier(
						true
					)}x!`,
					"info"
				)
			elseif Clock.now() < goldenArmedUntil then
				goldenArmedUntil = 0
				Net.send("FuseGolden", dino.id)
			else
				goldenArmedUntil = Clock.now() + 3
				refresh()
			end
		end,
	})

	feedButton = UI.button({
		name = "Feed",
		text = "🍎 Feed",
		size = UDim2.new(0.45, -5, 0, 58),
		color = UI.Theme.red,
		order = 2,
		maxTextSize = 22,
		parent = care,
		onClick = function()
			local id = currentId
			local snapshot = ClientState.get()
			if not id or not snapshot then
				return
			end
			if FruitData.nextToFeed(snapshot.fruit) then
				Net.send("FeedDino", id)
			else
				Toasts.show(
					"Pick up fruit under the 🍎 fruit trees, then feed it here to grow your dino faster!",
					"info"
				)
			end
		end,
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
