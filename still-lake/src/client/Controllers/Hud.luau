--!strict
-- The heads-up display, kept small so the lake stays the star:
--   * the power meter beside your character (only near the water): a needle
--     that swings while you wind up, with the gold zone and the perfect line
--   * a hint under it saying how to throw, or what's in the way
--   * your stone (bottom left), which opens the journal
--   * your best throw and title (top)
--   * the result of each of your throws once the stone stops
--   * a big Throw button on touch screens

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local StoneData = require(ReplicatedStorage.Shared.Data.StoneData)
local Skip = require(ReplicatedStorage.Shared.Skip)
local Types = require(ReplicatedStorage.Shared.Types)
local Audio = require(script.Parent.Audio)
local ClientState = require(script.Parent.ClientState)
local Journal = require(script.Parent.Journal)
local ThrowInput = require(script.Parent.ThrowInput)
local UI = require(script.Parent.Parent.Lib.UI)

local Hud = {}

local T = UI.Theme
local METER_HEIGHT = 250
local METER_WIDTH = 30

type Refs = {
	meter: Frame,
	needle: Frame,
	fill: Frame,
	hint: TextLabel,
	stoneDot: Frame,
	stoneName: TextLabel,
	stoneRarity: TextLabel,
	best: TextLabel,
	result: Frame,
	resultTitle: TextLabel,
	resultLine: TextLabel,
	flash: TextLabel,
	throwButton: TextButton?,
}

local refs: Refs? = nil
local resultToken = 0
local flashToken = 0

-- ===== The power meter =====

-- A band of the meter from power `a` to power `b`.
local function band(
	parent: Instance,
	a: number,
	b: number,
	color: Color3,
	z: number,
	name: string
): Frame
	return UI.new("Frame", {
		Name = name,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1 - a),
		Size = UDim2.fromScale(1, b - a),
		ZIndex = z,
		Parent = parent,
	}) :: Frame
end

local function buildMeter(canvas: Frame): (Frame, Frame, Frame)
	local meter = UI.new("Frame", {
		Name = "PowerMeter",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, 150, 0.5, -10),
		Size = UDim2.fromOffset(METER_WIDTH + 70, METER_HEIGHT),
		Visible = false,
		Parent = canvas,
	}) :: Frame
	local track = UI.glass({
		Name = "Track",
		Size = UDim2.fromOffset(METER_WIDTH, METER_HEIGHT),
		ClipsDescendants = true,
		Parent = meter,
	})
	local inner = UI.new("Frame", {
		Name = "Bands",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = track,
	}, { UI.corner(16) }) :: Frame
	band(inner, 0, Skip.PLOP, UI.darken(T.waterDeep, 0.35), 1, "Plop")
	band(inner, Skip.PLOP, Skip.GOLD_LOW, T.waterDeep, 1, "Water")
	band(inner, Skip.GOLD_LOW, Skip.DIVE, T.gold, 1, "Gold")
	band(inner, Skip.SWEET - Skip.PERFECT, Skip.SWEET + Skip.PERFECT, T.perfect, 2, "Perfect")
	band(inner, Skip.DIVE, 1, T.coral, 1, "Dive")
	local fill = UI.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = T.white,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		ZIndex = 3,
		Parent = inner,
	}) :: Frame
	-- the needle sticks out to the right of the bar
	local needle = UI.new("Frame", {
		Name = "Needle",
		BackgroundColor3 = T.white,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(METER_WIDTH + 12, 4),
		ZIndex = 4,
		Parent = meter,
	}, { UI.round(), UI.stroke(T.glass, 1.5, 0.3) }) :: Frame
	-- little labels for the zones
	UI.text({
		text = "too hard",
		size = UDim2.fromOffset(64, 16),
		position = UDim2.new(0, METER_WIDTH + 8, 1 - (1 + Skip.DIVE) / 2, 0),
		anchor = Vector2.new(0, 0.5),
		color = T.coral,
		font = UI.BodyFont,
		maxTextSize = 13,
		align = Enum.TextXAlignment.Left,
		shadow = true,
		parent = meter,
	})
	UI.text({
		text = "sweet spot",
		size = UDim2.fromOffset(70, 16),
		position = UDim2.new(0, METER_WIDTH + 8, 1 - Skip.SWEET, 0),
		anchor = Vector2.new(0, 0.5),
		color = T.perfect,
		font = UI.BodyFont,
		maxTextSize = 13,
		align = Enum.TextXAlignment.Left,
		shadow = true,
		parent = meter,
	})
	return meter, needle, fill
end

-- ===== Building =====

local function build()
	local _, canvas = UI.screen("Hud", 5)
	local meter, needle, fill = buildMeter(canvas)

	local hint = UI.text({
		name = "Hint",
		text = "",
		size = UDim2.fromOffset(360, 26),
		position = UDim2.new(0.5, 0, 1, -118),
		anchor = Vector2.new(0.5, 1),
		font = UI.BodyFont,
		maxTextSize = 20,
		shadow = true,
		parent = canvas,
	})

	-- a quick word right after letting go ("Perfect!")
	local flash = UI.text({
		name = "Flash",
		text = "",
		size = UDim2.fromOffset(220, 40),
		position = UDim2.new(0.5, 150 + METER_WIDTH / 2, 0.5, -METER_HEIGHT / 2 - 40),
		anchor = Vector2.new(0.5, 0.5),
		color = T.perfect,
		maxTextSize = 34,
		shadow = true,
		parent = canvas,
	})
	flash.TextTransparency = 1

	-- your stone, bottom left
	local card = UI.button({
		name = "StoneCard",
		text = "",
		size = UDim2.fromOffset(230, 64),
		position = UDim2.new(0, 18, 1, -18),
		anchor = Vector2.new(0, 1),
		parent = canvas,
		onClick = function()
			Journal.open("Stones")
		end,
	})
	card.label.Visible = false
	local dot = UI.new("Frame", {
		Name = "Dot",
		BackgroundColor3 = T.white,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(40, 28),
		Parent = card.root,
	}, { UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), UI.stroke(T.white, 2, 0.4) }) :: Frame
	local stoneName = UI.text({
		name = "StoneName",
		text = "Pebble",
		size = UDim2.new(1, -110, 0, 26),
		position = UDim2.fromOffset(62, 8),
		align = Enum.TextXAlignment.Left,
		maxTextSize = 22,
		parent = card.root,
	})
	local stoneRarity = UI.text({
		name = "Rarity",
		text = "Common",
		size = UDim2.new(1, -110, 0, 18),
		position = UDim2.fromOffset(62, 36),
		align = Enum.TextXAlignment.Left,
		font = UI.BodyFont,
		maxTextSize = 15,
		parent = card.root,
	})
	UI.text({
		text = "📖",
		size = UDim2.fromOffset(34, 34),
		position = UDim2.new(1, -10, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		maxTextSize = 26,
		parent = card.root,
	})

	-- best throw and title, top centre
	local bestPill = UI.glass({
		Name = "Best",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(300, 36),
		Parent = canvas,
	})
	local best = UI.text({
		name = "Text",
		text = "Skip your first stone",
		size = UDim2.new(1, -20, 1, -8),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		font = UI.BodyFont,
		maxTextSize = 18,
		parent = bestPill,
	})

	-- the result of your throw, upper middle
	local result = UI.new("Frame", {
		Name = "Result",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.26),
		Size = UDim2.fromOffset(460, 110),
		Visible = false,
		Parent = canvas,
	}) :: Frame
	local resultTitle = UI.text({
		name = "Title",
		text = "",
		size = UDim2.new(1, 0, 0, 64),
		maxTextSize = 58,
		shadow = true,
		parent = result,
	})
	local resultLine = UI.text({
		name = "Line",
		text = "",
		size = UDim2.new(1, 0, 0, 30),
		position = UDim2.fromOffset(0, 66),
		font = UI.BodyFont,
		maxTextSize = 22,
		shadow = true,
		parent = result,
	})

	-- the Throw button on touch screens (hold it like the mouse button)
	local throwButton: TextButton? = nil
	if UserInputService.TouchEnabled then
		local button = UI.new("TextButton", {
			Name = "Throw",
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = T.glass,
			BackgroundTransparency = UI.GLASS,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -150, 1, -60),
			Size = UDim2.fromOffset(110, 110),
			Visible = false,
			Parent = canvas,
		}, { UI.round(), UI.stroke(T.white, 2, 0.5) }) :: TextButton
		UI.text({
			text = "🪨\nThrow",
			size = UDim2.fromScale(0.8, 0.7),
			position = UDim2.fromScale(0.5, 0.5),
			anchor = Vector2.new(0.5, 0.5),
			maxTextSize = 24,
			parent = button,
		})
		button.InputBegan:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				ThrowInput.press()
			end
		end)
		button.InputEnded:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				ThrowInput.letGo()
			end
		end)
		throwButton = button
	end

	refs = {
		meter = meter,
		needle = needle,
		fill = fill,
		hint = hint,
		stoneDot = dot,
		stoneName = stoneName,
		stoneRarity = stoneRarity,
		best = best,
		result = result,
		resultTitle = resultTitle,
		resultLine = resultLine,
		flash = flash,
		throwButton = throwButton,
	}
end

-- ===== Updating =====

local function howToThrow(): string
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Hold R2 to wind up, let go in the gold"
	elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Hold Throw to wind up, let go in the gold"
	end
	return "Hold click to wind up, let go in the gold"
end

local HINTS: { [string]: string } = {
	away = "Face the open water to throw",
	high = "Climb down to throw",
}

local function frame()
	local r = refs
	if not r then
		return
	end
	ThrowInput.update()
	local state = ThrowInput.state
	local near = state.charging or state.status ~= "far"
	r.meter.Visible = near
	if r.throwButton then
		r.throwButton.Visible = near
	end
	local power = ThrowInput.power()
	r.needle.Position = UDim2.new(0, -6, 1 - power, 0)
	r.fill.Size = UDim2.fromScale(1, power)
	r.needle.Visible = state.charging
	if state.charging then
		r.hint.Text = ""
	elseif state.status == "ok" then
		local snapshot = ClientState.get()
		local newcomer = not snapshot or snapshot.throws < 5
		r.hint.Text = if ThrowInput.coolingDown() then "" elseif newcomer then howToThrow() else ""
	else
		r.hint.Text = HINTS[state.status] or ""
	end
end

local function showStone(snapshot: Types.Snapshot)
	local r = refs
	if not r then
		return
	end
	local stone = StoneData.get(snapshot.equipped) or StoneData.get(StoneData.STARTER)
	if not stone then
		return
	end
	r.stoneDot.BackgroundColor3 = UI.rgb(stone.color)
	r.stoneName.Text = stone.name
	r.stoneRarity.Text = stone.rarity
	r.stoneRarity.TextColor3 = UI.rgb(StoneData.rarityInfo(stone.rarity).color)
	if snapshot.bestSkips > 0 then
		local distance = string.format("%.0f", snapshot.bestDistance)
		local title = if snapshot.title then ` · {snapshot.title}` else ""
		r.best.Text = `Best ×{snapshot.bestSkips} · {distance} studs{title}`
	else
		r.best.Text = "Skip your first stone"
	end
end

local function flashWord(text: string, color: Color3)
	local r = refs
	if not r then
		return
	end
	flashToken += 1
	local token = flashToken
	r.flash.Text = text
	r.flash.TextColor3 = color
	r.flash.TextTransparency = 0
	UI.pop(r.flash, 0.7)
	task.delay(0.9, function()
		if token == flashToken then
			UI.tween(r.flash, UI.SOFT, { TextTransparency = 1 })
		end
	end)
end

-- How a finished throw reads to the player who threw it.
function Hud.describe(event: Types.ThrowEvent): (string, string)
	local lines: { string } = {}
	local title: string
	if event.verdict == "plop" then
		title = "Plop."
		table.insert(lines, "Too gentle. Hold a little longer")
	elseif event.verdict == "dive" then
		title = "Sploosh!"
		table.insert(lines, "Too hard, it dove straight in")
	else
		title = if event.skips == 1 then "1 skip" else `{event.skips} skips!`
		if event.verdict == "shore" then
			table.insert(lines, "All the way across the lake!")
		end
		if event.perfect then
			table.insert(lines, "Perfect release")
		end
		table.insert(lines, string.format("%.0f studs", event.distance))
	end
	if event.newBestSkips and event.skips > 0 then
		table.insert(lines, 1, "New best!")
	elseif event.newBestDistance and event.skips > 0 then
		table.insert(lines, 1, "Your longest yet!")
	end
	return title, table.concat(lines, " · ")
end

local function showResult(event: Types.ThrowEvent)
	local r = refs
	if not r then
		return
	end
	local title, line = Hud.describe(event)
	resultToken += 1
	local token = resultToken
	r.resultTitle.Text = title
	r.resultLine.Text = line
	r.resultTitle.TextColor3 = if event.perfect then T.perfect else T.white
	r.resultTitle.TextTransparency = 0
	r.resultLine.TextTransparency = 0
	r.result.Visible = true
	UI.pop(r.result, 0.8)
	if event.newBestSkips and event.skips > 0 then
		Audio.play("rare")
	elseif event.skips >= 10 then
		Audio.play("good")
	end
	task.delay(2.6, function()
		if token ~= resultToken then
			return
		end
		UI.tween(r.resultTitle, UI.SOFT, { TextTransparency = 1 })
		UI.tween(r.resultLine, UI.SOFT, { TextTransparency = 1 })
		task.delay(0.4, function()
			if token == resultToken then
				r.result.Visible = false
			end
		end)
	end)
end

function Hud.init()
	build()
	ClientState.changed:connect(showStone)
	ClientState.landed:connect(showResult)
	ThrowInput.released:connect(function(power: number)
		if Skip.isPerfect(power) then
			flashWord("Perfect!", T.perfect)
		elseif power >= Skip.DIVE then
			flashWord("Too hard!", T.coral)
		end
	end)
	ThrowInput.refused:connect(function(status)
		local text = HINTS[status]
		if text then
			flashWord(text, T.white)
			Audio.play("bad")
		end
	end)
end

function Hud.start()
	RunService.RenderStepped:Connect(frame)
end

return Hud
