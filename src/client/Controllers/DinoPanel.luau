--!strict
-- Info card for one of your dinos (opened from its "View" prompt): growth
-- progress, income, mutation, and Sell / Ride buttons.

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
local previewHolder: Frame
local nameLabel: TextLabel
local rarityLabel: TextLabel
local growthLabel: TextLabel
local barFill: Frame
local incomeLabel: TextLabel
local extraLabel: TextLabel
local sellButton: TextButton
local rideButton: TextButton
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
	end

	nameLabel.Text = (if mutation then mutation.emoji .. " " .. mutation.name .. " " else "")
		.. species.name
	rarityLabel.Text = `{species.rarity} • {Growth.stageName(stage)}`
	rarityLabel.TextColor3 = UI.rgb(DinoData.rarityInfo(species.rarity).color)
	if stage >= Growth.GIANT then
		growthLabel.Text = "Fully grown GIANT! 🏆"
		barFill.Size = UDim2.fromScale(1, 1)
	else
		growthLabel.Text = `Grows into {Growth.stageName(stage + 1)} in {Format.time(secondsLeft)}`
		barFill.Size = UDim2.fromScale(math.clamp(fraction, 0.02, 1), 1)
	end
	local income = Growth.income(species.income, stage, MutationData.multiplier(dino.mutation))
		* snapshot.multiplier
	incomeLabel.Text = `💰 +{Format.number(income)} coins/sec`
	local lays = Growth.layInterval(stage, Config.LAY_INTERVAL_ADULT, Config.LAY_INTERVAL_GIANT)
	extraLabel.Text = if lays
		then `🥚 Lays an egg every {Format.duration(lays)} • guards your nest at night`
		else "🍼 Too young to lay eggs or guard the nest yet"

	local value = Economy.dinoValue(species.income, stage, MutationData.multiplier(dino.mutation))
	if now < sellArmedUntil then
		sellButton.Text = "Tap again to sell!"
		sellButton.BackgroundColor3 = UI.Theme.red
	else
		sellButton.Text = "Sell 💰 " .. Format.number(value)
		sellButton.BackgroundColor3 = UI.Theme.orange
	end

	if snapshot.riding == dino.id then
		rideButton.Text = "⬇ Get off"
		UI.setEnabled(rideButton, true, UI.Theme.grey)
	elseif not snapshot.passes.RideDinos then
		rideButton.Text = "🦖 Ride (pass)"
		UI.setEnabled(rideButton, true, UI.Theme.blue)
	elseif stage < Growth.JUVENILE then
		rideButton.Text = "Too small to ride"
		UI.setEnabled(rideButton, false, UI.Theme.blue)
	else
		rideButton.Text = "🦖 Ride!"
		UI.setEnabled(rideButton, true, UI.Theme.blue)
	end
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
		Panels.window("Dino", "🦖 Your Dino", Vector2.new(720, 420), UI.Theme.green)
	previewHolder = UI.new("Frame", {
		BackgroundColor3 = UI.Theme.panelDark,
		Size = UDim2.fromOffset(260, 260),
		Parent = content,
	}, { UI.corner(16) }) :: Frame
	local right = UI.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(276, 0),
		Size = UDim2.new(1, -276, 1, 0),
		Parent = content,
	}) :: Frame
	nameLabel = UI.text({
		text = "",
		size = UDim2.new(1, 0, 0, 44),
		color = UI.Theme.ink,
		stroke = false,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 34,
		parent = right,
	})
	rarityLabel = UI.text({
		text = "",
		size = UDim2.new(1, 0, 0, 30),
		position = UDim2.fromOffset(0, 46),
		align = Enum.TextXAlignment.Left,
		maxTextSize = 24,
		parent = right,
	})
	growthLabel = UI.text({
		text = "",
		size = UDim2.new(1, 0, 0, 26),
		position = UDim2.fromOffset(0, 84),
		color = UI.Theme.ink,
		stroke = false,
		font = UI.BodyFont,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 20,
		parent = right,
	})
	local bar = UI.new("Frame", {
		BackgroundColor3 = UI.Theme.panelDark,
		Size = UDim2.new(1, -10, 0, 22),
		Position = UDim2.fromOffset(0, 114),
		Parent = right,
	}, { UI.corner(11), UI.stroke(UI.Theme.ink, 2) }) :: Frame
	barFill = UI.new("Frame", {
		BackgroundColor3 = UI.Theme.green,
		Size = UDim2.fromScale(0.1, 1),
		Parent = bar,
	}, { UI.corner(11) }) :: Frame
	incomeLabel = UI.text({
		text = "",
		size = UDim2.new(1, 0, 0, 30),
		position = UDim2.fromOffset(0, 146),
		color = Color3.fromRGB(190, 130, 0),
		stroke = false,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 24,
		parent = right,
	})
	extraLabel = UI.text({
		text = "",
		size = UDim2.new(1, 0, 0, 44),
		position = UDim2.fromOffset(0, 180),
		color = UI.Theme.ink,
		stroke = false,
		font = UI.BodyFont,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 18,
		parent = right,
	})
	sellButton = UI.button({
		text = "Sell",
		size = UDim2.new(0.48, 0, 0, 58),
		position = UDim2.fromOffset(0, 250),
		color = UI.Theme.orange,
		parent = right,
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
		text = "Ride",
		size = UDim2.new(0.48, 0, 0, 58),
		position = UDim2.new(1, -10, 0, 250),
		anchor = Vector2.new(1, 0),
		color = UI.Theme.blue,
		parent = right,
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
