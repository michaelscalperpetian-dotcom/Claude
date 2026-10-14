--!strict
-- One-shot moments: the hatch reveal (egg wobble and cracks, flash, spinning
-- rays, big reveal), coins flying into the counter, roars with screen shake,
-- mutation sparkles and confetti.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local DinoData = require(ReplicatedStorage.Shared.Data.DinoData)
local DinoModel = require(ReplicatedStorage.Shared.Visual.DinoModel)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local FruitData = require(ReplicatedStorage.Shared.Data.FruitData)
local EggModel = require(ReplicatedStorage.Shared.Visual.EggModel)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local MutationData = require(ReplicatedStorage.Shared.Data.MutationData)
local Net = require(ReplicatedStorage.Shared.Net)
local Hud = require(script.Parent.Hud)
local Toasts = require(script.Parent.Toasts)
local UI = require(script.Parent.Parent.Lib.UI)

local Effects = {}

-- Sound hooks (set by the audio controller).
Effects.onReveal = function(_rarity: string) end
Effects.onCrack = function() end
Effects.onCoins = function() end

type Reveal = { species: string, mutation: string?, new: boolean, golden: boolean? }

local screen: ScreenGui
local revealQueue: { Reveal } = {}
local revealing = false

-- ===== Confetti =====

local CONFETTI_COLORS = {
	Color3.fromRGB(255, 90, 95),
	Color3.fromRGB(255, 201, 60),
	Color3.fromRGB(85, 209, 110),
	Color3.fromRGB(74, 168, 255),
	Color3.fromRGB(155, 107, 255),
	Color3.fromRGB(255, 120, 190),
}

local function confetti(amount: number)
	local rng = Random.new()
	for _ = 1, amount do
		local piece = UI.new("Frame", {
			Name = "Confetti",
			Size = UDim2.fromOffset(rng:NextInteger(8, 16), rng:NextInteger(10, 22)),
			Position = UDim2.new(rng:NextNumber(0, 1), 0, -0.05, 0),
			BackgroundColor3 = CONFETTI_COLORS[rng:NextInteger(1, #CONFETTI_COLORS)],
			Rotation = rng:NextInteger(0, 360),
			ZIndex = 20,
			Parent = screen,
		}, { UI.corner(3) }) :: Frame
		local duration = rng:NextNumber(1.6, 2.8)
		TweenService
			:Create(
				piece,
				TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{
					Position = UDim2.new(
						piece.Position.X.Scale + rng:NextNumber(-0.15, 0.15),
						0,
						1.1,
						0
					),
					Rotation = piece.Rotation + rng:NextInteger(-360, 360),
				}
			)
			:Play()
		task.delay(duration, function()
			piece:Destroy()
		end)
	end
end

-- ===== Camera shake =====

local function shake(intensity: number, duration: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		if elapsed >= duration then
			connection:Disconnect()
			return
		end
		local falloff = 1 - elapsed / duration
		local offset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0)
			* intensity
			* falloff
		camera.CFrame = camera.CFrame * CFrame.new(offset)
	end)
end

-- ===== Hatch reveal =====

local RAYS = 8

-- Soft light beams behind the reveal: long bars through the centre whose
-- sides fade out, spun slowly, over a layered glow.
local function rays(parent: Instance, color: Color3): { Frame }
	for i, size in { 420, 300, 190 } do
		UI.new("Frame", {
			Name = "Glow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.44),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = UI.lighten(color, 0.2 + i * 0.15),
			BackgroundTransparency = 0.82 - i * 0.08,
			ZIndex = 11,
			Parent = parent,
		}, { UI.round() })
	end
	local list = {}
	for i = 0, RAYS - 1 do
		local ray = UI.new("Frame", {
			Name = "Ray",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.44),
			Size = UDim2.fromOffset(110, 1800),
			BackgroundColor3 = UI.lighten(color, 0.25),
			BackgroundTransparency = if i % 2 == 0 then 0.45 else 0.62,
			Rotation = i * (180 / RAYS),
			ZIndex = 11,
			Parent = parent,
		}, {
			UI.new("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		}) :: Frame
		table.insert(list, ray)
	end
	return list
end

-- Zig-zag crack drawn over the egg, revealed one segment at a time.
local CRACK = {
	{ 0.24, 0.5, 0.36, 0.43 },
	{ 0.36, 0.43, 0.46, 0.53 },
	{ 0.46, 0.53, 0.57, 0.44 },
	{ 0.57, 0.44, 0.67, 0.53 },
	{ 0.67, 0.53, 0.77, 0.46 },
}

local function crackSegment(parent: Instance, segment: { number }): Frame
	local x0, y0, x1, y1 = segment[1], segment[2], segment[3], segment[4]
	local size = 260
	local dx, dy = (x1 - x0) * size, (y1 - y0) * size
	return UI.new("Frame", {
		Name = "Crack",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale((x0 + x1) / 2, (y0 + y1) / 2),
		Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + 4, 6),
		Rotation = math.deg(math.atan2(dy, dx)),
		BackgroundColor3 = UI.Theme.ink,
		ZIndex = 14,
		Parent = parent,
	}, { UI.round() }) :: Frame
end

local function reveal(item: Reveal)
	local data = DinoData.get(item.species)
	if not data then
		return
	end
	local rarity = DinoData.rarityInfo(data.rarity)
	local rarityColor = UI.rgb(rarity.color)
	local m = MutationData.get(item.mutation)

	local overlay = UI.new("Frame", {
		Name = "Overlay",
		Size = UDim2.fromScale(4, 4),
		Position = UDim2.fromScale(-1.5, -1.5),
		BackgroundColor3 = Color3.fromRGB(20, 14, 34),
		BackgroundTransparency = 1,
		ZIndex = 10,
		Parent = screen,
	}) :: Frame
	TweenService:Create(overlay, TweenInfo.new(0.25), { BackgroundTransparency = 0.3 }):Play()
	-- The reveal (460 px stage, chips and "Tap to continue" below it, 554 px
	-- in all) shrinks to fit short landscape phones and stays centred.
	local canvasHeight = UI.canvasSize().Y
	local fit = math.min(1, (canvasHeight - 24) / 554)
	local stage = UI.new("Frame", {
		Name = "Reveal",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, canvasHeight / 2 - 47 * fit),
		Size = UDim2.fromOffset(460, 460),
		BackgroundTransparency = 1,
		ZIndex = 11,
		Parent = screen,
	}, { UI.new("UIScale", { Scale = fit }) }) :: Frame

	-- 1. The egg drops in and wobbles harder and harder, then cracks
	local eggHolder = UI.new("Frame", {
		Name = "Egg",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(260, 260),
		BackgroundTransparency = 1,
		ZIndex = 12,
		Parent = stage,
	}) :: Frame
	local eggViewport = UI.viewport(
		EggModel.build(EggModel.giftLook(), 3, true),
		UDim2.fromScale(1, 1),
		eggHolder,
		0
	)
	eggViewport.ZIndex = 12
	UI.pop(eggHolder, 0.4)
	local cracks = 0
	for i = 1, 14 do
		eggHolder.Rotation = (if i % 2 == 0 then 1 else -1) * (3 + i * 1.3)
		if i % 3 == 0 and cracks < #CRACK then
			cracks += 1
			crackSegment(eggHolder, CRACK[cracks])
			Effects.onCrack()
		end
		task.wait(0.075)
	end
	for k = cracks + 1, #CRACK do
		crackSegment(eggHolder, CRACK[k])
	end
	task.wait(0.12)
	eggHolder:Destroy()

	-- 2. Flash + rays
	local flash = UI.new("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(4, 4),
		Position = UDim2.fromScale(-1.5, -1.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 18,
		Parent = screen,
	}) :: Frame
	TweenService:Create(flash, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
	task.delay(0.45, function()
		flash:Destroy()
	end)
	local rayList = rays(stage, if m then UI.rgb(m.color) else rarityColor)

	-- 3. The dino pops out
	local dinoViewport = UI.viewport(
		DinoModel.build(item.species, 3, item.mutation, "Static", item.golden),
		UDim2.fromOffset(340, 340),
		stage,
		25
	)
	dinoViewport.AnchorPoint = Vector2.new(0.5, 0.5)
	dinoViewport.Position = UDim2.fromScale(0.5, 0.44)
	dinoViewport.ZIndex = 13
	UI.pop(dinoViewport, 0.3)
	Effects.onReveal(data.rarity)

	local ribbon = UI.new("Frame", {
		Name = "Ribbon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -64),
		Size = UDim2.fromOffset(500, 72),
		BackgroundColor3 = rarityColor,
		ZIndex = 14,
		Parent = stage,
	}, { UI.corner(20), UI.stroke(UI.darken(rarityColor, 0.5), 4), UI.shade(0.82) }) :: Frame
	UI.text({
		name = "Title",
		text = (if item.golden then "⭐ GOLDEN " else "") .. (if m
			then m.emoji .. " " .. m.name .. " "
			else "") .. data.name .. "!",
		size = UDim2.new(1, -30, 1, -14),
		position = UDim2.fromOffset(15, 7),
		maxTextSize = 46,
		outlineThickness = 3,
		zIndex = 15,
		parent = ribbon,
	})
	local tags = UI.new("Frame", {
		Name = "Tags",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 16),
		Size = UDim2.fromOffset(500, 36),
		ZIndex = 14,
		Parent = stage,
	}, { UI.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center) }) :: Frame
	local rarityChip = UI.chip({
		text = data.rarity:upper(),
		size = UDim2.fromOffset(170, 36),
		color = UI.darken(rarityColor, 0.1),
		order = 1,
		maxTextSize = 22,
		parent = tags,
	})
	rarityChip.root.ZIndex = 15
	if m then
		local chip = UI.chip({
			text = `x{m.multiplier} coins`,
			size = UDim2.fromOffset(150, 36),
			color = UI.rgb(m.color),
			order = 2,
			maxTextSize = 22,
			parent = tags,
		})
		chip.root.ZIndex = 15
	end
	if item.golden then
		local chip = UI.chip({
			text = `⭐ x{Economy.goldenMultiplier(true)} coins`,
			size = UDim2.fromOffset(160, 36),
			color = UI.Theme.gold,
			order = 3,
			maxTextSize = 22,
			parent = tags,
		})
		chip.root.ZIndex = 15
	end
	if item.new then
		local newBadge = UI.chip({
			name = "New",
			text = "NEW!",
			size = UDim2.fromOffset(110, 44),
			position = UDim2.new(1, -40, 0, 30),
			anchor = Vector2.new(1, 0),
			color = UI.Theme.red,
			maxTextSize = 30,
			parent = stage,
		})
		newBadge.root.ZIndex = 16
		newBadge.root.Rotation = 12
		UI.pop(newBadge.root, 0.2)
	end
	UI.pop(ribbon, 0.5)
	local hint = UI.text({
		name = "Hint",
		text = "Tap to continue",
		size = UDim2.fromOffset(300, 30),
		position = UDim2.new(0.5, 0, 1, 64),
		anchor = Vector2.new(0.5, 0),
		maxTextSize = 22,
		zIndex = 15,
		parent = stage,
	})
	hint.TextTransparency = 1
	local hintPulse = TweenService:Create(
		hint,
		TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, 0.8),
		{ TextTransparency = 0.2 }
	)
	hintPulse:Play()

	if rarity.order >= DinoData.rarityInfo("Rare").order or m then
		confetti(if rarity.order >= DinoData.rarityInfo("Legendary").order then 120 else 60)
	end
	if rarity.order >= DinoData.rarityInfo("Epic").order then
		shake(0.6, 0.6)
	end

	-- spin the rays and the dino while the reveal is on screen
	local started = os.clock()
	local spin = RunService.RenderStepped:Connect(function(dt: number)
		for i, ray in rayList do
			ray.Rotation = (i - 1) * (180 / RAYS) + (os.clock() - started) * 18
		end
		local model = dinoViewport:FindFirstChildOfClass("Model")
		if model then
			model:PivotTo(model:GetPivot() * CFrame.Angles(0, dt * 0.6, 0))
		end
	end)

	local done = false
	local closeButton = UI.new("TextButton", {
		Name = "Continue",
		Size = UDim2.fromScale(4, 4),
		Position = UDim2.fromScale(-1.5, -1.5),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 19,
		Parent = screen,
	}) :: TextButton
	closeButton.Activated:Connect(function()
		if os.clock() - started > 0.8 then
			done = true
		end
	end)
	while not done and os.clock() - started < 4 do
		task.wait(0.1)
	end
	spin:Disconnect()
	closeButton:Destroy()
	overlay:Destroy()
	hintPulse:Cancel()
	stage:Destroy()
end

local function processQueue()
	if revealing then
		return
	end
	revealing = true
	while #revealQueue > 0 do
		reveal(table.remove(revealQueue, 1) :: Reveal)
	end
	revealing = false
end

-- ===== World-space popups =====

local function worldText(position: Vector3, text: string, color: Color3, size: number)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace.CurrentCamera or Workspace
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(size * 6, size * 2)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = anchor
	local label = UI.text({
		text = text,
		size = UDim2.fromScale(1, 1),
		color = color,
		maxTextSize = size,
		outlineThickness = 3,
		parent = gui,
	})
	TweenService:Create(gui, TweenInfo.new(1.4), { StudsOffsetWorldSpace = Vector3.new(0, 10, 0) })
		:Play()
	TweenService
		:Create(label, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
		})
		:Play()
	task.delay(1.5, function()
		anchor:Destroy()
	end)
end

local function burst(position: Vector3, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
	anchor.Parent = Workspace.CurrentCamera or Workspace
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Speed = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Size = NumberSequence.new(0.8, 0)
	emitter.Rate = 0
	emitter.Parent = anchor
	emitter:Emit(40)
	task.delay(1.5, function()
		anchor:Destroy()
	end)
end

-- ===== Coins flying into the counter =====

local function designScale(): number
	local uiScale = screen:FindFirstChildOfClass("UIScale")
	return if uiScale then uiScale.Scale else 1
end

local function coinsFly(amount: number, from: Vector3?)
	local scale = designScale()
	local target = Hud.coinTarget() / scale
	local start = target + Vector2.new(0, 260)
	local camera = Workspace.CurrentCamera
	if from and camera then
		local point, onScreen = camera:WorldToViewportPoint(from)
		if onScreen then
			start = Vector2.new(point.X, point.Y - UI.topInset()) / scale
		end
	end
	local rng = Random.new()
	local count = math.clamp(math.floor(math.log10(math.max(amount, 1)) * 2) + 3, 4, 12)
	for i = 1, count do
		local coin = UI.coin(34, screen)
		coin.AnchorPoint = Vector2.new(0.5, 0.5)
		coin.ZIndex = 6
		local spread = Vector2.new(rng:NextNumber(-60, 60), rng:NextNumber(-40, 40))
		coin.Position = UDim2.fromOffset(start.X, start.Y)
		local delayTime = (i - 1) * 0.04
		task.delay(delayTime, function()
			local burstTween = TweenService:Create(
				coin,
				TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{
					Position = UDim2.fromOffset(start.X + spread.X, start.Y + spread.Y),
				}
			)
			burstTween:Play()
			burstTween.Completed:Wait()
			local fly = TweenService:Create(
				coin,
				TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{
					Position = UDim2.fromOffset(target.X, target.Y),
					Size = UDim2.fromOffset(22, 22),
				}
			)
			fly:Play()
			fly.Completed:Wait()
			coin:Destroy()
		end)
	end
	task.delay(0.75 + count * 0.04, function()
		Effects.onCoins()
		UI.pop(Hud.coinPill(), 1.12)
	end)
	local label = UI.text({
		text = "+" .. Format.number(amount),
		size = UDim2.fromOffset(240, 46),
		position = UDim2.fromOffset(target.X, target.Y + 64),
		anchor = Vector2.new(0.5, 0.5),
		color = UI.Theme.coin,
		maxTextSize = 38,
		outlineThickness = 3,
		zIndex = 7,
		parent = screen,
	})
	TweenService:Create(label, TweenInfo.new(1.2, Enum.EasingStyle.Quad), {
		Position = UDim2.fromOffset(target.X, target.Y + 40),
		TextTransparency = 1,
	}):Play()
	task.delay(1.3, function()
		label:Destroy()
	end)
end

local function onEffect(kind: string, data: { [string]: any })
	if kind == "Hatch" then
		if typeof(data.species) == "string" then
			table.insert(revealQueue, {
				species = data.species,
				mutation = if typeof(data.mutation) == "string" then data.mutation else nil,
				new = data.new == true,
			})
			task.spawn(processQueue)
		end
	elseif kind == "Golden" then
		if typeof(data.species) == "string" then
			table.insert(revealQueue, {
				species = data.species,
				mutation = if typeof(data.mutation) == "string" then data.mutation else nil,
				new = false,
				golden = true,
			})
			task.spawn(processQueue)
		end
	elseif kind == "Fruit" then
		local info = if typeof(data.kind) == "string" then FruitData.get(data.kind) else nil
		if info and typeof(data.position) == "Vector3" then
			worldText(data.position, `+1 {info.emoji} ({data.count or 1})`, UI.rgb(info.color), 28)
		end
	elseif kind == "Feed" then
		if typeof(data.position) == "Vector3" then
			burst(data.position, UI.Theme.pink)
			worldText(data.position, "Yum! 💕", UI.Theme.pink, 34)
		end
	elseif kind == "Roar" then
		if typeof(data.position) == "Vector3" then
			worldText(data.position, "ROAR!", UI.Theme.orange, if data.big then 48 else 34)
			local character = Players.LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if
				root
				and root:IsA("BasePart")
				and (root.CFrame.Position - data.position).Magnitude < 45
			then
				shake(if data.big then 0.5 else 0.25, 0.4)
			end
		end
	elseif kind == "Collect" then
		if typeof(data.amount) == "number" then
			coinsFly(data.amount, if typeof(data.position) == "Vector3" then data.position else nil)
		end
	elseif kind == "Mutate" then
		if typeof(data.position) == "Vector3" then
			local m = MutationData.get(data.mutation)
			burst(data.position, if m then UI.rgb(m.color) else Color3.new(1, 1, 1))
		end
	elseif kind == "Dex" then
		local species = if typeof(data.species) == "string" then DinoData.get(data.species) else nil
		if species then
			Toasts.show(`📖 New Dex entry: {species.name}!`, "rare")
		end
	elseif kind == "Reward" then
		confetti(70)
	elseif kind == "Caught" then
		if data.victim == Players.LocalPlayer.UserId then
			confetti(40)
		end
	end
end

-- Plays a reveal directly (used by previews and tests).
function Effects.reveal(species: string, mutation: string?, new: boolean?)
	table.insert(revealQueue, { species = species, mutation = mutation, new = new == true })
	task.spawn(processQueue)
end

function Effects.init()
	screen = UI.screen("Effects", 30)
	Net.listen("Effect", onEffect)
end

return Effects
