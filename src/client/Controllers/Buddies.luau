--!strict
-- Buddy dinos: a small copy of a player's chosen dino that hops along behind
-- them. The server sets a "Buddy" attribute on each Player
-- ("species|mutation|stage"); every client draws everyone's buddy locally so
-- the movement is smooth.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DinoModel = require(ReplicatedStorage.Shared.Visual.DinoModel)
local Growth = require(ReplicatedStorage.Shared.Util.Growth)

local Buddies = {}

local ATTRIBUTE = "Buddy"
local MAX_STAGE = Growth.JUVENILE -- buddies stay pet-sized
local SIDE_OFFSET = 3.5
local BACK_OFFSET = 4.5

type Follower = {
	look: string,
	model: Model,
	root: BasePart,
	position: Vector3,
	facing: Vector3,
	phase: number,
}

local followers: { [Player]: Follower } = {}
local folder: Folder
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function remove(player: Player)
	local follower = followers[player]
	if follower then
		follower.model:Destroy()
		followers[player] = nil
	end
end

local function build(player: Player, look: string)
	remove(player)
	local species, mutation, stageText, goldenText =
		string.match(look, "^([^|]+)|([^|]*)|(%d+)|?(%a*)$")
	if not species then
		return
	end
	local stage = math.min(tonumber(stageText) or 1, MAX_STAGE)
	local ok, model = pcall(function()
		return DinoModel.build(
			species,
			stage,
			if mutation == "" then nil else mutation,
			"World",
			goldenText == "g"
		)
	end)
	if not ok then
		return
	end
	model.Name = "Buddy_" .. player.Name
	local root = model.PrimaryPart :: BasePart
	model.Parent = folder
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local start = if hrp and hrp:IsA("BasePart")
		then hrp.CFrame.Position - Vector3.new(0, 3, 0)
		else Vector3.zero
	followers[player] = {
		look = look,
		model = model,
		root = root,
		position = start,
		facing = Vector3.new(0, 0, -1),
		phase = math.random() * 10,
	}
end

local function sync(player: Player)
	local look = player:GetAttribute(ATTRIBUTE)
	if typeof(look) ~= "string" or look == "" then
		remove(player)
		return
	end
	local existing = followers[player]
	if not existing or existing.look ~= look then
		build(player, look)
	end
end

local function watch(player: Player)
	sync(player)
	player:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
		sync(player)
	end)
end

local function groundBelow(position: Vector3, ignore: { Instance }): number?
	rayParams.FilterDescendantsInstances = ignore
	local hit =
		Workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), rayParams)
	return if hit then hit.Position.Y else nil
end

local function step(dt: number)
	for player, follower in followers do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not hrp or not hrp:IsA("BasePart") then
			continue
		end
		local rootCf = hrp.CFrame
		local look = rootCf.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 1e-3 then
			flat = Vector3.new(0, 0, -1)
		end
		flat = flat.Unit
		local right = Vector3.new(-flat.Z, 0, flat.X)
		local target = rootCf.Position - flat * BACK_OFFSET + right * SIDE_OFFSET
		local ground = groundBelow(target, { character, folder }) or (rootCf.Position.Y - 3)
		target = Vector3.new(target.X, ground, target.Z)

		local before = follower.position
		if (target - before).Magnitude > 40 then
			follower.position = target -- teleported: snap
		else
			local alpha = 1 - math.exp(-dt * 7)
			follower.position = before:Lerp(target, alpha)
		end
		local moved = follower.position - before
		local speed = moved.Magnitude / math.max(dt, 1e-3)
		local moving = Vector3.new(moved.X, 0, moved.Z)
		if speed > 1 and moving.Magnitude > 1e-4 then
			follower.facing = follower.facing:Lerp(moving.Unit, math.min(1, dt * 10))
		else
			follower.facing = follower.facing:Lerp(flat, math.min(1, dt * 3))
		end
		-- cartoon hop while walking, gentle breathing while idle
		follower.phase += dt * (if speed > 1 then 11 else 2)
		local hop = if speed > 1
			then math.abs(math.sin(follower.phase)) * 0.7
			else math.sin(follower.phase) * 0.05
		local facing = if follower.facing.Magnitude > 1e-3 then follower.facing.Unit else flat
		local position = follower.position + Vector3.new(0, hop + 0.1, 0)
		follower.root.CFrame = CFrame.lookAt(position, position + facing)
	end
end

function Buddies.init()
	folder = Instance.new("Folder")
	folder.Name = "Buddies"
	folder.Parent = Workspace
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(remove)
end

function Buddies.start()
	RunService.RenderStepped:Connect(step)
end

return Buddies
