--!strict
-- The heads-up display:
--   * coins, big at the top, with your coin multiplier and longest throw
--   * buttons down the left: Rocks, Upgrade (one tap buys a level), Rebirth
--     (glows when you can afford one) and the chase camera
--   * the power meter beside your character (on the beach and the piers):
--     a needle that swings while you wind up, with the gold zone and the
--     perfect line, and a hint under it
--   * the result of each throw once the rock sinks: coins and distance
--   * a big Throw button on touch screens

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local RockData = require(ReplicatedStorage.Shared.Data.RockData)
local Skip = require(ReplicatedStorage.Shared.Skip)
local Types = require(ReplicatedStorage.Shared.Types)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Audio = require(script.Parent.Audio)
local ClientState = require(script.Parent.ClientState)
local Menu = require(script.Parent.Menu)
local RockFx = require(script.Parent.RockFx)
local ThrowInput = require(script.Parent.ThrowInput)
local UI = require(script.Parent.Parent.Lib.UI)

local Hud = {}

local T = UI.Theme
local METER_HEIGHT = 250
local METER_WIDTH = 30
local METER_X = 260 -- right of the screen's centre (clear of the messages)
local COIN_GOLD = Color3.fromRGB(255, 214, 92)

type Refs = {
	meter: Frame,
	needle: Frame,
	fill: Frame,
	hint: TextLabel,
	coins: TextLabel,
	details: TextLabel,
	upgrade: UI.Button,
	upgradeCost: TextLabel,
	rebirth: UI.Button,
	rocks: UI.Button,
	rockDot: Frame,
	camera: UI.Button,
	result: Frame,
	resultTitle: TextLabel,
	resultLine: TextLabel,
	flash: TextLabel,
	waking: Frame,
	throwButton: TextButton?,
}

local refs: Refs? = nil
local resultToken = 0
local flashToken = 0
local shownCoins = 0 -- the counter rolls up to the real number

-- ===== The power meter =====

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
		Position = UDim2.new(0.5, METER_X, 0.5, -10),
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

-- A square button down the left side: an emoji over a caption.
local function sideButton(
	canvas: Frame,
	name: string,
	emoji: string,
	caption: string,
	order: number,
	onClick: () -> ()
): UI.Button
	local button = UI.button({
		name = name,
		text = "",
		size = UDim2.fromOffset(88, 76),
		position = UDim2.new(0, 16, 0, 64 + (order - 1) * 84),
		parent = canvas,
		onClick = onClick,
	})
	button.label.Visible = false
	UI.text({
		name = "Icon",
		text = emoji,
		size = UDim2.new(1, -10, 0, 34),
		position = UDim2.fromOffset(5, 6),
		maxTextSize = 30,
		parent = button.root,
	})
	UI.text({
		name = "Caption",
		text = caption,
		size = UDim2.new(1, -8, 0, 22),
		position = UDim2.fromOffset(4, 44),
		font = UI.BodyFont,
		maxTextSize = 16,
		parent = button.root,
	})
	return button
end

local function build()
	local _, canvas = UI.screen("Hud", 5)
	local meter, needle, fill = buildMeter(canvas)

	-- coins, top centre
	local coinPill = UI.glass({
		Name = "CoinPill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(320, 76),
		Parent = canvas,
	})
	local coins = UI.text({
		name = "Coins",
		text = "🪙 0",
		size = UDim2.new(1, -20, 0, 44),
		position = UDim2.fromOffset(10, 4),
		color = COIN_GOLD,
		maxTextSize = 40,
		shadow = true,
		parent = coinPill,
	})
	local details = UI.text({
		name = "Details",
		text = "",
		size = UDim2.new(1, -20, 0, 22),
		position = UDim2.fromOffset(10, 48),
		font = UI.BodyFont,
		maxTextSize = 16,
		parent = coinPill,
	})

	-- buttons down the left
	local rocks = sideButton(canvas, "Rocks", "🪨", "Rocks", 1, function()
		Menu.open("Rocks")
	end)
	local rockDot = UI.new("Frame", {
		Name = "Dot",
		BackgroundColor3 = T.white,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(18, 13),
		Parent = rocks.root,
	}, { UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), UI.stroke(T.white, 1.5, 0.3) }) :: Frame
	local upgrade = sideButton(canvas, "Upgrade", "💪", "Upgrade", 2, function()
		Net.send("Upgrade", 1)
	end)
	local upgradeCost = UI.text({
		name = "Cost",
		text = "",
		size = UDim2.fromOffset(110, 22),
		position = UDim2.new(1, 8, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		color = COIN_GOLD,
		font = UI.BodyFont,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 17,
		shadow = true,
		parent = upgrade.root,
	})
	local rebirth = sideButton(canvas, "Rebirth", "🔁", "Rebirth", 3, function()
		Menu.open("Rebirth")
	end)
	local camera = sideButton(canvas, "Camera", "🎥", "Chase cam", 4, function()
		RockFx.chaseEnabled = not RockFx.chaseEnabled
		if not RockFx.chaseEnabled then
			RockFx.stopChase()
		end
	end)

	local hint = UI.text({
		name = "Hint",
		text = "",
		size = UDim2.fromOffset(420, 26),
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
		size = UDim2.fromOffset(240, 40),
		position = UDim2.new(0.5, METER_X + METER_WIDTH / 2, 0.5, -METER_HEIGHT / 2 - 40),
		anchor = Vector2.new(0.5, 0.5),
		color = T.perfect,
		maxTextSize = 34,
		shadow = true,
		parent = canvas,
	})
	flash.TextTransparency = 1

	-- the result of your throw, upper middle
	local result = UI.new("Frame", {
		Name = "Result",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(520, 90),
		Visible = false,
		Parent = canvas,
	}) :: Frame
	local resultTitle = UI.text({
		name = "Title",
		text = "",
		size = UDim2.new(1, 0, 0, 56),
		color = COIN_GOLD,
		maxTextSize = 52,
		shadow = true,
		parent = result,
	})
	local resultLine = UI.text({
		name = "Line",
		text = "",
		size = UDim2.new(1, 0, 0, 28),
		position = UDim2.fromOffset(0, 60),
		font = UI.BodyFont,
		maxTextSize = 22,
		shadow = true,
		parent = result,
	})

	local waking = UI.glass({
		Name = "Waking",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(380, 56),
		Parent = canvas,
	})
	UI.text({
		text = "The tide is coming in…",
		size = UDim2.new(1, -24, 1, -14),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		maxTextSize = 26,
		parent = waking,
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
				ThrowInput.press(input)
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
		coins = coins,
		details = details,
		upgrade = upgrade,
		upgradeCost = upgradeCost,
		rebirth = rebirth,
		rocks = rocks,
		rockDot = rockDot,
		camera = camera,
		result = result,
		resultTitle = resultTitle,
		resultLine = resultLine,
		flash = flash,
		waking = waking,
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

local function frame(dt: number)
	local r = refs
	if not r then
		return
	end
	ThrowInput.update()
	local state = ThrowInput.state
	r.waking.Visible = Players.LocalPlayer.Character == nil
	local near = state.charging or state.status ~= "far"
	r.meter.Visible = near
	if r.throwButton then
		r.throwButton.Visible = near
	end
	local power = ThrowInput.power()
	r.needle.Position = UDim2.new(0, -6, 1 - power, 0)
	r.fill.Size = UDim2.fromScale(1, power)
	r.needle.Visible = state.charging
	local snapshot = ClientState.get()
	if state.charging then
		r.hint.Text = ""
	elseif state.status == "ok" then
		local newcomer = not snapshot or snapshot.throws < 5
		r.hint.Text = if ThrowInput.coolingDown() or not newcomer then "" else howToThrow()
	elseif state.status == "high" then
		r.hint.Text = "Climb down to throw"
	else
		local newcomer = not snapshot or snapshot.throws < 1
		r.hint.Text = if newcomer and Players.LocalPlayer.Character
			then "Walk down to the beach to skip a rock"
			else ""
	end
	-- the coin counter rolls up smoothly to the real number
	local target = if snapshot then snapshot.coins else 0
	if shownCoins ~= target then
		local step = (target - shownCoins) * math.min(dt * 8, 1)
		shownCoins = if math.abs(target - shownCoins) < 1 then target else shownCoins + step
		r.coins.Text = "🪙 " .. Format.short(shownCoins)
	end
	r.camera.root.BackgroundTransparency = if RockFx.chaseEnabled then UI.GLASS else 0.65
end

local function showState(snapshot: Types.Snapshot)
	local r = refs
	if not r then
		return
	end
	local rock = RockData.get(snapshot.equipped) or RockData.get(RockData.STARTER)
	if rock then
		r.rockDot.BackgroundColor3 = UI.rgb(rock.color)
	end
	local multiplier = Format.times(snapshot.coinMultiplier)
	local best = if snapshot.bestDistance > 0
		then ` · Longest {Format.distance(snapshot.bestDistance)}`
		else ""
	r.details.Text = `{multiplier} coins{best}`
	r.upgradeCost.Text = "🪙 " .. Format.short(snapshot.strengthCost)
	local canUpgrade = snapshot.coins >= snapshot.strengthCost
	UI.setButton(r.upgrade, { color = if canUpgrade then T.good else T.glass })
	r.upgrade.root.BackgroundTransparency = if canUpgrade then 0.1 else UI.GLASS
	local canRebirth = snapshot.coins >= snapshot.rebirthCost
	UI.setButton(r.rebirth, { color = if canRebirth then T.dusk else T.glass })
	r.rebirth.root.BackgroundTransparency = if canRebirth then 0.05 else UI.GLASS
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
	if event.verdict == "plop" then
		return "Plop.", "Too gentle. Hold a little longer"
	elseif event.verdict == "dive" then
		return "Sploosh!", "Too hard, it dove straight in"
	end
	local lines: { string } = {}
	if event.newBest then
		table.insert(lines, "New record!")
	end
	table.insert(lines, Format.distance(event.distance))
	table.insert(lines, if event.skips == 1 then "1 skip" else `{event.skips} skips`)
	if event.perfect then
		table.insert(lines, "Perfect!")
	end
	return `+{Format.short(event.coins)} 🪙`, table.concat(lines, " · ")
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
	r.resultTitle.TextColor3 = if event.verdict == "skips" then COIN_GOLD else T.white
	r.resultTitle.TextTransparency = 0
	r.resultLine.TextTransparency = 0
	r.result.Visible = true
	UI.pop(r.result, 0.8)
	if event.newBest and event.skips > 0 then
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
	ClientState.changed:connect(showState)
	ClientState.landed:connect(showResult)
	ThrowInput.released:connect(function(power: number)
		if Skip.isPerfect(power) then
			flashWord("Perfect!", T.perfect)
		elseif power >= Skip.DIVE then
			flashWord("Too hard!", T.coral)
		end
	end)
end

function Hud.start()
	RunService.RenderStepped:Connect(frame)
end

return Hud
