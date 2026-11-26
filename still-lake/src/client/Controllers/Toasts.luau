--!strict
-- Gentle messages from the server, stacked near the top of the screen, and
-- a bigger card when you pick up a stone ("You found Slate! New!").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local StoneData = require(ReplicatedStorage.Shared.Data.StoneData)
local Audio = require(script.Parent.Audio)
local UI = require(script.Parent.Parent.Lib.UI)

local Toasts = {}

Toasts.MAX = 3
Toasts.SECONDS = 3.2

local T = UI.Theme
local STYLE_COLORS: { [string]: Color3 } = {
	info = T.white,
	good = UI.lighten(T.sage, 0.35),
	bad = UI.lighten(T.coral, 0.35),
	rare = T.perfect,
}

-- Messages and found-stone cards share one stack above the hint line,
-- newest at the bottom.
local stack: Frame? = nil
local alive: { [Frame]: boolean } = {}
local order: { Frame } = {} -- oldest first
local count = 0

local function remove(item: Frame)
	if not alive[item] then
		return
	end
	alive[item] = nil
	local index = table.find(order, item)
	if index then
		table.remove(order, index)
	end
	item:Destroy()
end

-- Adds a pill to the stack (pushing out the oldest) and fades it later.
local function push(item: Frame, seconds: number, labels: { TextLabel })
	if #order >= Toasts.MAX then
		remove(order[1])
	end
	count += 1
	item.LayoutOrder = count
	alive[item] = true
	table.insert(order, item)
	item.Parent = stack
	UI.pop(item, 0.9)
	task.delay(seconds, function()
		if not alive[item] then
			return -- pushed out by newer messages already
		end
		UI.tween(item, UI.SOFT, { BackgroundTransparency = 1 })
		for _, label in labels do
			UI.tween(label, UI.SOFT, { TextTransparency = 1 })
		end
		task.delay(0.4, remove, item)
	end)
end

-- The newest message or card on screen (nil if none).
function Toasts.latest(): Frame?
	return order[#order]
end

function Toasts.show(text: string, style: string?)
	if not stack then
		return
	end
	local pill = UI.glass({ Name = "Toast", Size = UDim2.fromOffset(440, 38) })
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
	push(pill, Toasts.SECONDS, { label })
	if style == "good" or style == "rare" or style == "bad" then
		Audio.play(style)
	end
end

-- "New stone: …" card for a stone picked up off the beach.
function Toasts.found(id: string, isNew: boolean, owned: number)
	local stone = StoneData.get(id)
	if not stack or not stone then
		return
	end
	local rarityColor = UI.rgb(StoneData.rarityInfo(stone.rarity).color)
	local card = UI.glass({ Name = "Found", Size = UDim2.fromOffset(480, 84) })
	UI.new("Frame", {
		Name = "Swatch",
		BackgroundColor3 = UI.rgb(stone.color),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(58, 40),
		Parent = card,
	}, { UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), UI.stroke(T.white, 2, 0.4) })
	local title = UI.text({
		name = "Title",
		text = if isNew then `New stone: {stone.name}!` else `Another {stone.name}`,
		size = UDim2.new(1, -104, 0, 30),
		position = UDim2.fromOffset(88, 9),
		align = Enum.TextXAlignment.Left,
		maxTextSize = 26,
		parent = card,
	})
	local line = UI.text({
		name = "Line",
		text = if isNew
			then `{stone.rarity} · {stone.blurb}`
			else `{stone.rarity} · you have {owned} now`,
		size = UDim2.new(1, -104, 0, 34),
		position = UDim2.fromOffset(88, 42),
		align = Enum.TextXAlignment.Left,
		valign = Enum.TextYAlignment.Top,
		color = if isNew then UI.lighten(rarityColor, 0.25) else T.white,
		font = UI.BodyFont,
		maxTextSize = 17,
		parent = card,
	})
	push(card, if isNew then 5 else 2.5, { title, line })
	Audio.play(if isNew then "rare" else "pickup")
end

function Toasts.init()
	local _, canvas = UI.screen("Toasts", 20)
	stack = UI.new("Frame", {
		Name = "Stack",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.fromOffset(480, 260),
		Parent = canvas,
	}, {
		UI.list(
			Enum.FillDirection.Vertical,
			6,
			Enum.HorizontalAlignment.Center,
			Enum.VerticalAlignment.Bottom
		),
	}) :: Frame

	Net.listen("Notify", function(text: string, style: string)
		Toasts.show(text, style)
	end)
	Net.listen("Found", function(id: string, isNew: boolean, owned: number)
		Toasts.found(id, isNew, owned)
	end)
end

return Toasts
