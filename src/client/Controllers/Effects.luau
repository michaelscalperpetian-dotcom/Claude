--!strict
-- One-shot moments: the hatch reveal (anticipation shake, flash, big reveal),
-- roars with screen shake, coin pops, mutation sparkles and confetti.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local DinoData = require(ReplicatedStorage.Shared.Data.DinoData)
local DinoModel = require(ReplicatedStorage.Shared.Visual.DinoModel)
local EggModel = require(ReplicatedStorage.Shared.Visual.EggModel)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local MutationData = require(ReplicatedStorage.Shared.Data.MutationData)
local Net = require(ReplicatedStorage.Shared.Net)
local Hud = require(script.Parent.Hud)
local Toasts = require(script.Parent.Toasts)
local UI = require(script.Parent.Parent.Lib.UI)

local Effects = {}

local screen: ScreenGui
local revealQueue: { { species: string, mutation: string? } } = {}
local revealing = false

-- ===== Confetti =====

local CONFETTI_COLORS = {
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(255, 210, 60),
	Color3.fromRGB(90, 220, 120),
	Color3.fromRGB(80, 170, 255),
	Color3.fromRGB(200, 120, 255),
}

local function confetti(amount: number)
	local rng = Random.new()
	for _ = 1, amount do
		local piece = UI.new("Frame", {
			Size = UDim2.fromOffset(rng:NextInteger(8, 16), rng:NextInteger(10, 20)),
			Position = UDim2.new(rng:NextNumber(0, 1), 0, -0.05, 0),
			BackgroundColor3 = CONFETTI_COLORS[rng:NextInteger(1, #CONFETTI_COLORS)],
			Rotation = rng:NextInteger(0, 360),
			ZIndex = 20,
			Parent = screen,
		}) :: Frame
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

local function reveal(species: string, mutation: string?)
	local data = DinoData.get(species)
	if not data then
		return
	end
	local rarity = DinoData.rarityInfo(data.rarity)
	local overlay = UI.new("Frame", {
		Size = UDim2.fromScale(4, 4),
		Position = UDim2.fromScale(-1.5, -1.5),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		ZIndex = 10,
		Parent = screen,
	}) :: Frame
	local stage = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromOffset(420, 420),
		BackgroundTransparency = 1,
		ZIndex = 11,
		Parent = screen,
	}) :: Frame

	-- 1. Anticipation: the egg shakes harder and harder
	local eggViewport =
		UI.viewport(EggModel.build(EggModel.giftLook(), 3, true), UDim2.fromOffset(260, 260), stage)
	eggViewport.AnchorPoint = Vector2.new(0.5, 0.5)
	eggViewport.Position = UDim2.fromScale(0.5, 0.5)
	eggViewport.ZIndex = 12
	for i = 1, 10 do
		eggViewport.Rotation = (if i % 2 == 0 then 1 else -1) * (4 + i * 1.5)
		task.wait(0.07)
	end
	eggViewport:Destroy()

	-- 2. Flash
	local flash = UI.new("Frame", {
		Size = UDim2.fromScale(4, 4),
		Position = UDim2.fromScale(-1.5, -1.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		ZIndex = 15,
		Parent = screen,
	}) :: Frame
	TweenService:Create(flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	task.delay(0.5, function()
		flash:Destroy()
	end)

	-- 3. Reveal
	local dinoViewport = UI.viewport(
		DinoModel.build(species, 3, mutation, "Static"),
		UDim2.fromOffset(320, 320),
		stage,
		25
	)
	dinoViewport.AnchorPoint = Vector2.new(0.5, 0.5)
	dinoViewport.Position = UDim2.fromScale(0.5, 0.42)
	dinoViewport.ZIndex = 12
	UI.pop(dinoViewport)
	local m = MutationData.get(mutation)
	local title = UI.text({
		text = (if m then m.emoji .. " " .. m.name .. " " else "") .. data.name .. "!",
		size = UDim2.fromOffset(520, 56),
		position = UDim2.new(0.5, 0, 1, -40),
		anchor = Vector2.new(0.5, 0),
		maxTextSize = 48,
		parent = stage,
	})
	title.ZIndex = 13
	local rarityLabel = UI.text({
		text = data.rarity:upper(),
		size = UDim2.fromOffset(320, 40),
		position = UDim2.new(0.5, 0, 1, 18),
		anchor = Vector2.new(0.5, 0),
		color = UI.rgb(rarity.color),
		maxTextSize = 36,
		parent = stage,
	})
	rarityLabel.ZIndex = 13
	UI.pop(title)

	if rarity.order >= DinoData.rarityInfo("Rare").order or m then
		confetti(if rarity.order >= DinoData.rarityInfo("Legendary").order then 120 else 60)
	end
	if rarity.order >= DinoData.rarityInfo("Epic").order then
		shake(0.6, 0.6)
	end

	-- spin the preview a little while it's on screen
	local started = os.clock()
	local spin = RunService.RenderStepped:Connect(function()
		local model = dinoViewport:FindFirstChildOfClass("Model")
		if model then
			model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(0.6), 0))
		end
	end)

	local done = false
	local closeButton = UI.new("TextButton", {
		Size = UDim2.fromScale(4, 4),
		Position = UDim2.fromScale(-1.5, -1.5),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 16,
		Parent = screen,
	}) :: TextButton
	closeButton.Activated:Connect(function()
		if os.clock() - started > 0.8 then
			done = true
		end
	end)
	while not done and os.clock() - started < 3.5 do
		task.wait(0.1)
	end
	spin:Disconnect()
	closeButton:Destroy()
	overlay:Destroy()
	stage:Destroy()
end

local function processQueue()
	if revealing then
		return
	end
	revealing = true
	while #revealQueue > 0 do
		local item = table.remove(revealQueue, 1) :: { species: string, mutation: string? }
		reveal(item.species, item.mutation)
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
		parent = gui,
	})
	TweenService:Create(gui, TweenInfo.new(1.4), { StudsOffsetWorldSpace = Vector3.new(0, 10, 0) })
		:Play()
	TweenService
		:Create(label, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
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

local function coinPop(amount: number)
	-- Offsets inside a UIScale'd screen are in unscaled pixels.
	local uiScale = screen:FindFirstChildOfClass("UIScale")
	local target = Hud.coinTarget() / (if uiScale then uiScale.Scale else 1)
	local label = UI.text({
		text = "+💰 " .. Format.number(amount),
		size = UDim2.fromOffset(240, 50),
		position = UDim2.fromOffset(target.X, target.Y + 80),
		anchor = Vector2.new(0.5, 0.5),
		color = UI.Theme.gold,
		maxTextSize = 40,
		parent = screen,
	})
	label.ZIndex = 5
	TweenService:Create(label, TweenInfo.new(0.9, Enum.EasingStyle.Quad), {
		Position = UDim2.fromOffset(target.X, target.Y + 20),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1, function()
		label:Destroy()
	end)
end

local function onEffect(kind: string, data: { [string]: any })
	if kind == "Hatch" then
		if typeof(data.species) == "string" then
			table.insert(revealQueue, { species = data.species, mutation = data.mutation })
			task.spawn(processQueue)
		end
	elseif kind == "Roar" then
		if typeof(data.position) == "Vector3" then
			worldText(
				data.position,
				"ROAR!",
				Color3.fromRGB(255, 120, 60),
				if data.big then 48 else 34
			)
			local character = Players.LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and (root.Position - data.position).Magnitude < 45 then
				shake(if data.big then 0.5 else 0.25, 0.4)
			end
		end
	elseif kind == "Collect" then
		if typeof(data.amount) == "number" then
			coinPop(data.amount)
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

function Effects.init()
	screen = UI.screen("Effects", 30)
	Net.listen("Effect", onEffect)
end

return Effects
