--!strict
-- Gentle messages from the server, stacked near the top of the screen, and
-- a bigger card when you pick up a stone ("You found Slate! New!").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local StoneData = require(ReplicatedStorage.Shared.Data.StoneData)
local Audio = require(script.Parent.Audio)
local UI = require(script.Parent.Parent.Lib.UI)

local Toasts = {}

Toasts.MAX = 4
Toasts.SECONDS = 3.2

local T = UI.Theme
local STYLE_COLORS: { [string]: Color3 } = {
	info = T.white,
	good = UI.lighten(T.sage, 0.35),
	bad = UI.lighten(T.coral, 0.35),
	rare = T.perfect,
}

local stack: Frame? = nil
local alive: { [Frame]: boolean } = {} -- toasts on screen
local order: { Frame } = {} -- oldest first
local toastCount = 0

local function remove(pill: Frame)
	if not alive[pill] then
		return
	end
	alive[pill] = nil
	local index = table.find(order, pill)
	if index then
		table.remove(order, index)
	end
	pill:Destroy()
end
local foundCard: Frame? = nil
local foundToken = 0

function Toasts.show(text: string, style: string?)
	local parent = stack
	if not parent then
		return
	end
	if #order >= Toasts.MAX then
		remove(order[1])
	end
	toastCount += 1
	local pill = UI.glass({
		Name = "Toast",
		Size = UDim2.fromOffset(420, 38),
		LayoutOrder = toastCount,
		Parent = parent,
	})
	alive[pill] = true
	table.insert(order, pill)
	local label = UI.text({
		text = text,
		size = UDim2.new(1, -24, 1, -8),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = STYLE_COLORS[style or "info"] or T.white,
		font = UI.BodyFont,
		maxTextSize = 19,
		parent = pill,
	})
	UI.pop(pill, 0.9)
	if style == "good" or style == "rare" or style == "bad" then
		Audio.play(style)
	end
	task.delay(Toasts.SECONDS, function()
		if not alive[pill] then
			return -- pushed out by newer toasts already
		end
		UI.tween(pill, UI.SOFT, { BackgroundTransparency = 1 })
		UI.tween(label, UI.SOFT, { TextTransparency = 1 })
		task.delay(0.4, remove, pill)
	end)
end

-- "You found …" card for a stone picked up off the beach.
function Toasts.found(id: string, isNew: boolean, count: number)
	local card = foundCard
	local stone = StoneData.get(id)
	if not card or not stone then
		return
	end
	foundToken += 1
	local token = foundToken
	local rarityColor = UI.rgb(StoneData.rarityInfo(stone.rarity).color)
	local swatch = card:FindFirstChild("Swatch") :: Frame
	local title = card:FindFirstChild("Title") :: TextLabel
	local line = card:FindFirstChild("Line") :: TextLabel
	swatch.BackgroundColor3 = UI.rgb(stone.color)
	title.Text = if isNew then `New stone: {stone.name}!` else `Another {stone.name}`
	line.Text = if isNew
		then `{stone.rarity} · {stone.blurb}`
		else `{stone.rarity} · you have {count} now`
	line.TextColor3 = if isNew then rarityColor else T.white
	card.Visible = true
	UI.pop(card, 0.8)
	Audio.play(if isNew then "rare" else "pickup")
	task.delay(if isNew then 4.5 else 2.5, function()
		if token == foundToken then
			card.Visible = false
		end
	end)
end

function Toasts.init()
	local _, canvas = UI.screen("Toasts", 20)
	stack = UI.new("Frame", {
		Name = "Stack",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.fromOffset(440, 180),
		Parent = canvas,
	}, { UI.list(Enum.FillDirection.Vertical, 6) }) :: Frame

	local card = UI.glass({
		Name = "Found",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.fromOffset(460, 76),
		Visible = false,
		Parent = canvas,
	})
	UI.new("Frame", {
		Name = "Swatch",
		BackgroundColor3 = T.white,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(56, 38),
		Parent = card,
	}, { UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), UI.stroke(T.white, 2, 0.4) })
	UI.text({
		name = "Title",
		text = "",
		size = UDim2.new(1, -100, 0, 30),
		position = UDim2.fromOffset(86, 8),
		align = Enum.TextXAlignment.Left,
		maxTextSize = 24,
		parent = card,
	})
	UI.text({
		name = "Line",
		text = "",
		size = UDim2.new(1, -100, 0, 28),
		position = UDim2.fromOffset(86, 40),
		align = Enum.TextXAlignment.Left,
		font = UI.BodyFont,
		maxTextSize = 15,
		parent = card,
	})
	foundCard = card

	Net.listen("Notify", function(text: string, style: string)
		Toasts.show(text, style)
	end)
	Net.listen("Found", function(id: string, isNew: boolean, count: number)
		Toasts.found(id, isNew, count)
	end)
end

return Toasts
