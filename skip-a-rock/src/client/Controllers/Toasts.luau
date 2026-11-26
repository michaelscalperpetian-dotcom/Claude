--!strict
-- Gentle messages from the server, stacked near the top of the screen, and
-- a bigger banner when you reach an island far out at sea.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local IslandData = require(ReplicatedStorage.Shared.Data.IslandData)
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

-- Messages and island banners share one stack above the hint line,
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

-- A big banner: an island reached.
function Toasts.island(id: string)
	local island = IslandData.get(id)
	if not stack or not island then
		return
	end
	local card = UI.glass({ Name = "Island", Size = UDim2.fromOffset(480, 84) })
	card.BackgroundColor3 = T.waterDeep
	local title = UI.text({
		name = "Title",
		text = `🏝️ You reached {island.name}!`,
		size = UDim2.new(1, -24, 0, 34),
		position = UDim2.fromOffset(12, 8),
		maxTextSize = 28,
		parent = card,
	})
	local line = UI.text({
		name = "Line",
		text = `+{math.floor(island.bonus * 100 + 0.5)}% coins from every throw, forever`,
		size = UDim2.new(1, -24, 0, 26),
		position = UDim2.fromOffset(12, 46),
		color = T.perfect,
		font = UI.BodyFont,
		maxTextSize = 18,
		parent = card,
	})
	push(card, 5, { title, line })
	Audio.play("rare")
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
	Net.listen("Island", function(id: string)
		Toasts.island(id)
	end)
end

return Toasts
