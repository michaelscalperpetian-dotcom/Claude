--!strict
-- Fruit trees drop Dino Apples (and the odd Golden Apple) on the ground
-- around them. Walk over one to put it in your basket, then feed it to a dino
-- from its card to make it grow faster. Fruit grows back a minute after it's
-- picked, so everyone on the server shares the orchard.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local DinoData = require(ReplicatedStorage.Shared.Data.DinoData)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local FruitData = require(ReplicatedStorage.Shared.Data.FruitData)
local Growth = require(ReplicatedStorage.Shared.Util.Growth)
local Net = require(ReplicatedStorage.Shared.Net)
local Data = require(script.Parent.Data)
local Nest = require(script.Parent.Nest)
local Plots = require(script.Parent.Plots)
local Quests = require(script.Parent.Quests)
local Sessions = require(script.Parent.Sessions)
local State = require(script.Parent.State)
local Notify = require(script.Parent.Parent.Lib.Notify)
local Stats = require(script.Parent.Parent.Lib.Stats)

local Fruit = {}

type Spot = { part: BasePart, fruit: BasePart?, respawnAt: number }

local spots: { Spot } = {}
local folder: Instance? = nil
local rng = Random.new()
local fullNoticeAt: { [Player]: number } = {}

local function spotOf(fruit: BasePart): Spot?
	for _, spot in spots do
		if spot.fruit == fruit then
			return spot
		end
	end
	return nil
end

-- Hands a fruit to a player standing next to it. Returns true if picked.
function Fruit.collect(player: Player, fruit: BasePart): boolean
	local spot = spotOf(fruit)
	if not spot then
		return false -- already picked
	end
	local kind = fruit:GetAttribute("Kind")
	local info = if typeof(kind) == "string" then FruitData.get(kind) else nil
	local profile = Data.get(player)
	local session = Sessions.get(player)
	if not spot or not info or not profile or not session or not session.ready then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if
		not root
		or not root:IsA("BasePart")
		or (root.CFrame.Position - fruit.CFrame.Position).Magnitude > FruitData.PICK_DISTANCE
	then
		return false
	end
	local have = profile.fruit[info.kind] or 0
	if have >= info.cap then
		local now = os.clock()
		if not fullNoticeAt[player] or now - fullNoticeAt[player] > 6 then
			fullNoticeAt[player] = now
			Notify.send(
				player,
				`Your basket is full of {info.name}s! Feed some to your dinos.`,
				"info"
			)
		end
		return false
	end
	profile.fruit[info.kind] = have + 1
	local position = fruit.CFrame.Position
	fruit:Destroy()
	spot.fruit = nil
	spot.respawnAt = Clock.now() + FruitData.RESPAWN_SECONDS * rng:NextNumber(0.8, 1.25)
	State.markDirty(player)
	Notify.effect(
		player,
		"Fruit",
		{ position = position, kind = info.kind, count = profile.fruit[info.kind] }
	)
	return true
end

local function makeFruit(spot: Spot, kind: FruitData.Kind)
	local info = FruitData.FRUITS[kind]
	local fruit = Instance.new("Part")
	fruit.Name = "Fruit"
	fruit.Shape = Enum.PartType.Ball
	fruit.Size = Vector3.new(1.4, 1.4, 1.4)
	fruit.Color = Color3.fromRGB(info.color[1], info.color[2], info.color[3])
	fruit.Material = Enum.Material.SmoothPlastic
	fruit.Anchored = true
	fruit.CanCollide = false
	fruit.CanQuery = false
	fruit.CastShadow = false
	fruit.CFrame = spot.part.CFrame
	fruit:SetAttribute("Kind", kind)
	local leaf = Instance.new("Part")
	leaf.Name = "Leaf"
	leaf.Size = Vector3.new(0.5, 0.15, 0.3)
	leaf.Color = Color3.fromRGB(90, 190, 80)
	leaf.Material = Enum.Material.SmoothPlastic
	leaf.Anchored = true
	leaf.CanCollide = false
	leaf.CanTouch = false
	leaf.CanQuery = false
	leaf.CFrame = spot.part.CFrame * CFrame.new(0.2, 0.75, 0) * CFrame.Angles(0, 0, 0.5)
	leaf.Parent = fruit
	if kind == "golden" then
		fruit.Reflectance = 0.3
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
		sparkle.LightEmission = 1
		sparkle.Rate = 6
		sparkle.Lifetime = NumberRange.new(0.6, 1.2)
		sparkle.Speed = NumberRange.new(0.5, 1.5)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparkle.Parent = fruit
	end
	fruit.Touched:Connect(function(hit: BasePart)
		local model = hit:FindFirstAncestorOfClass("Model")
		local player = model and Players:GetPlayerFromCharacter(model)
		if player and fruit.Parent then
			Fruit.collect(player, fruit)
		end
	end)
	fruit.Parent = folder
	spot.fruit = fruit
end

-- Finds the orchard's fruit spots (World builds the island first).
function Fruit.setup()
	table.clear(spots)
	local map = Workspace:FindFirstChild("Map")
	local orchard = map and map:FindFirstChild("FruitTrees")
	folder = orchard
	if not orchard then
		return
	end
	for _, part in orchard:GetDescendants() do
		if part.Name == "FruitSpot" and part:IsA("BasePart") then
			table.insert(spots, { part = part, fruit = nil, respawnAt = 0 })
		end
	end
end

-- Grows fruit on every empty spot whose time has come.
function Fruit.spawnDue(now: number)
	for _, spot in spots do
		if not spot.fruit and now >= spot.respawnAt then
			local kind: FruitData.Kind = if rng:NextNumber() < FruitData.GOLDEN_CHANCE
				then "golden"
				else "apple"
			makeFruit(spot, kind)
		end
	end
end

function Fruit.spots(): { Spot }
	return spots
end

local function feed(player: Player, dinoId: string)
	local profile = Data.get(player)
	local session = Sessions.get(player)
	if not profile or not session or not session.ready then
		return
	end
	local dino = Nest.findDino(profile, dinoId)
	local species = dino and DinoData.get(dino.species)
	if not dino or not species then
		return
	end
	local now = Clock.now()
	local stageBefore = Stats.dinoStage(dino, now)
	if stageBefore >= Growth.GIANT then
		Notify.send(player, "This dino is fully grown already! 🏆", "info")
		return
	end
	local kind = FruitData.nextToFeed(profile.fruit)
	if not kind then
		Notify.send(player, "No fruit! Pick some up under the fruit trees 🍎", "info")
		return
	end
	local info = FruitData.FRUITS[kind]
	profile.fruit[kind] -= 1
	dino.bornAt -= info.grows
	if stageBefore < Growth.ADULT and Stats.dinoStage(dino, now) >= Growth.ADULT then
		dino.lastLaidAt = now -- grown up just now: no backlog of eggs
	end
	Plots.syncDinos(player)
	State.markDirty(player)
	Quests.track(player, "feed")
	local model = Plots.dinoModel(player, dino.id)
	Notify.effect(player, "Feed", {
		position = if model then model:GetPivot().Position + Vector3.new(0, 3, 0) else nil,
		kind = kind,
	})
	Notify.send(
		player,
		`{info.emoji} Yum! {dino.name or species.name} grew {Format.duration(info.grows)} in one bite.`,
		"good"
	)
end

function Fruit.init()
	Net.on("FeedDino", 2, 4, function(player: Player, dinoId: unknown)
		if typeof(dinoId) == "string" and #dinoId <= 20 then
			feed(player, dinoId)
		end
	end)
	Sessions.Leaving:connect(function(player: Player)
		fullNoticeAt[player] = nil
	end)
end

-- Riders float above the ground, so they pick fruit by distance.
function Fruit.collectForRiders()
	for _, session in Sessions.ready() do
		local character = if session.riding then session.player.Character else nil
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			for _, spot in spots do
				local fruit = spot.fruit
				if fruit then
					local offset = root.CFrame.Position - fruit.CFrame.Position
					if Vector3.new(offset.X, 0, offset.Z).Magnitude <= 4 then
						Fruit.collect(session.player, fruit)
					end
				end
			end
		end
	end
end

function Fruit.start()
	Fruit.setup()
	local ticks = 0
	while true do
		if ticks % 8 == 0 then
			Fruit.spawnDue(Clock.now())
		end
		Fruit.collectForRiders()
		ticks += 1
		task.wait(0.25)
	end
end

return Fruit
