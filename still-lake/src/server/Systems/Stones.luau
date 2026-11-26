--!strict
-- Stones: glints that wash up on the beach (walk over and pick one up to find
-- out what it is), choosing which stone to throw, and the stone you hold in
-- your hand.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Lake = require(ReplicatedStorage.Shared.Lake)
local Net = require(ReplicatedStorage.Shared.Net)
local StoneData = require(ReplicatedStorage.Shared.Data.StoneData)
local StoneModel = require(ReplicatedStorage.Shared.StoneModel)
local Notify = require(script.Parent.Parent.Lib.Notify)
local Scenery = require(script.Parent.Parent.Lib.Scenery)
local Data = require(script.Parent.Data)
local Progress = require(script.Parent.Progress)
local Sessions = require(script.Parent.Sessions)
local State = require(script.Parent.State)

local Stones = {}

Stones.HELD_NAME = "HeldStone"
Stones.PICKUP_RANGE = 10 -- a little more than the prompt's, for lag
Stones.INNER = Config.LAKE_RADIUS + 2.5 -- glints wash up between these radii
Stones.OUTER = Config.LAKE_RADIUS + Config.SHORE_WIDTH - 2
Stones.SPACING = 10 -- glints are at least this far apart

local folder: Folder? = nil
local glints: { [BasePart]: true } = {}
local random = Random.new()

-- ===== The stone in your hand =====

local function hand(character: Model): BasePart?
	local right = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if right and right:IsA("BasePart") then
		return right
	end
	return nil
end

-- Puts the equipped stone in the character's right hand (replacing the old one).
function Stones.updateHeld(player: Player)
	local profile = Data.get(player)
	local character = player.Character
	if not profile or not character then
		return
	end
	local old = character:FindFirstChild(Stones.HELD_NAME)
	if old then
		old:Destroy()
	end
	local grip = hand(character)
	if not grip then
		return
	end
	local stone = StoneModel.build(profile.equipped, 0.8)
	stone.Name = Stones.HELD_NAME
	stone.Anchored = false
	stone:SetAttribute("BaseTransparency", stone.Transparency)
	local attachment = grip:FindFirstChild("RightGripAttachment")
	local at = if attachment and attachment:IsA("Attachment")
		then attachment.WorldCFrame
		else grip.CFrame * CFrame.new(0, -grip.Size.Y / 2, 0)
	stone.CFrame = at * CFrame.new(0, -0.15, 0) * CFrame.Angles(0, 0, math.rad(90))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = grip
	weld.Part1 = stone
	weld.Parent = stone
	stone.Parent = character
end

-- Hides the held stone while a thrown one is in the air.
function Stones.hideHeld(player: Player, seconds: number)
	local character = player.Character
	local held = character and character:FindFirstChild(Stones.HELD_NAME)
	if not held or not held:IsA("BasePart") then
		return
	end
	held.Transparency = 1
	local sparkle = held:FindFirstChild("Sparkle")
	if sparkle and sparkle:IsA("ParticleEmitter") then
		sparkle.Enabled = false
	end
	task.delay(seconds, function()
		if held.Parent == nil then
			return
		end
		local base = held:GetAttribute("BaseTransparency")
		held.Transparency = if type(base) == "number" then base else 0
		if sparkle and sparkle:IsA("ParticleEmitter") then
			sparkle.Enabled = true
		end
	end)
end

local function equip(player: Player, id: unknown)
	if type(id) ~= "string" or not Sessions.getReady(player) then
		return
	end
	local profile = Data.get(player)
	if not profile or not StoneData.get(id) or (profile.stones[id] or 0) < 1 then
		return
	end
	if profile.equipped == id then
		return
	end
	profile.equipped = id
	Stones.updateHeld(player)
	State.markDirty(player)
end

-- ===== Glints on the beach =====

-- A free spot on the beach: away from the docks, the other glints and the spawn.
local function findSpot(): Vector3?
	for _ = 1, 40 do
		local angle = random:NextNumber(0, 2 * math.pi)
		local radius = random:NextNumber(Stones.INNER, Stones.OUTER)
		local p = Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
		local clear = not Lake.underDock(p, 3)
		if clear then
			for glint in glints do
				local g = glint.CFrame.Position
				if Vector3.new(g.X - p.X, 0, g.Z - p.Z).Magnitude < Stones.SPACING then
					clear = false
					break
				end
			end
		end
		if clear then
			return Vector3.new(p.X, Scenery.BEACH_TOP + 0.25, p.Z)
		end
	end
	return nil
end

local spawnGlint: () -> ()

local function collect(glint: BasePart, player: Player)
	if not glints[glint] or not Sessions.getReady(player) then
		return
	end
	local profile = Data.get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not profile or not root or not root:IsA("BasePart") then
		return
	end
	if (root.CFrame.Position - glint.CFrame.Position).Magnitude > Stones.PICKUP_RANGE then
		return
	end
	glints[glint] = nil
	glint:Destroy()

	local id = StoneData.roll(random:NextNumber())
	local stone = StoneData.get(id) :: StoneData.Stone
	local count = (profile.stones[id] or 0) + 1
	local isNew = count == 1
	profile.stones[id] = count
	Net.fire(player, "Found", id, isNew, count)
	if isNew and (stone.rarity == "Epic" or stone.rarity == "Legendary") then
		Notify.all(`✨ {player.DisplayName} found a {stone.name}!`, "rare")
	end
	Progress.check(player)
	State.markDirty(player)

	task.delay(random:NextNumber(Config.GLINT_RESPAWN_MIN, Config.GLINT_RESPAWN_MAX), spawnGlint)
end

function spawnGlint()
	local parent = folder
	if not parent then
		return
	end
	local spot = findSpot()
	if not spot then
		-- the beach is crowded; try again a little later
		task.delay(10, spawnGlint)
		return
	end
	local glint = Instance.new("Part")
	glint.Name = "Glint"
	glint.Shape = Enum.PartType.Ball
	glint.Size = Vector3.new(0.7, 0.7, 0.7)
	glint.CFrame = CFrame.new(spot)
	glint.Color = Color3.fromRGB(255, 250, 225)
	glint.Material = Enum.Material.Neon
	glint.Anchored = true
	glint.CanCollide = false
	glint.CanTouch = false
	glint.CastShadow = false
	glint.TopSurface = Enum.SurfaceType.Smooth
	glint.BottomSurface = Enum.SurfaceType.Smooth

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "Sparkle"
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 246, 200))
	sparkle.LightEmission = 1
	sparkle.Rate = 6
	sparkle.Lifetime = NumberRange.new(0.6, 1.2)
	sparkle.Speed = NumberRange.new(0.5, 1.5)
	sparkle.SpreadAngle = Vector2.new(40, 40)
	sparkle.EmissionDirection = Enum.NormalId.Top
	sparkle.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkle.Parent = glint
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 240, 200)
	light.Range = 6
	light.Brightness = 0.8
	light.Shadows = false
	light.Parent = glint

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.ObjectText = "Glinting stone"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = glint
	prompt.Triggered:Connect(function(player: Player)
		collect(glint, player)
	end)

	glints[glint] = true
	glint.Parent = parent
end

function Stones.glintCount(): number
	local n = 0
	for _ in glints do
		n += 1
	end
	return n
end

-- Testing: wash every glint away and bring a fresh set.
function Stones.refreshGlints()
	for glint in glints do
		glint:Destroy()
	end
	table.clear(glints)
	for _ = 1, Config.GLINT_COUNT do
		spawnGlint()
	end
end

-- Testing: pick up a glint for a player as if they had walked to it.
function Stones.collectFor(player: Player, glint: BasePart)
	collect(glint, player)
end

function Stones.list(): { BasePart }
	local list = {}
	for glint in glints do
		table.insert(list, glint)
	end
	return list
end

function Stones.init()
	local f = Instance.new("Folder")
	f.Name = "Glints"
	f.Parent = Workspace
	folder = f
	Net.on("Equip", 4, 8, equip)
	Sessions.Ready:connect(function(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 10)
			character:WaitForChild("RightHand", 3)
			if Sessions.getReady(player) and player.Character == character then
				Stones.updateHeld(player)
			end
		end)
		if player.Character then
			task.spawn(Stones.updateHeld, player)
		end
	end)
end

function Stones.start()
	for _ = 1, Config.GLINT_COUNT do
		spawnGlint()
	end
end

return Stones
