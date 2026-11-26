--!strict
-- Records, islands, goals and titles. Every finished throw comes through
-- recordThrow; anything else that changes progress calls check. A skipper's
-- title floats over their head, and their coins, longest throw and rebirths
-- show on the player list.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GoalData = require(ReplicatedStorage.Shared.Data.GoalData)
local IslandData = require(ReplicatedStorage.Shared.Data.IslandData)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Notify = require(script.Parent.Parent.Lib.Notify)
local Data = require(script.Parent.Data)
local Sessions = require(script.Parent.Sessions)
local State = require(script.Parent.State)

local Progress = {}

Progress.TITLE_NAME = "SkipperTitle"

-- One finished throw, as far as records are concerned.
export type Throw = {
	distance: number,
	skips: number,
	perfect: boolean,
	coins: number,
}

function Progress.stats(profile: Types.Profile): GoalData.Stats
	local rocks = 0
	for _, owned in profile.rocks do
		if owned then
			rocks += 1
		end
	end
	return {
		bestSkips = profile.bestSkips,
		bestDistance = profile.bestDistance,
		perfects = profile.perfects,
		rocks = rocks,
		rebirths = profile.rebirths,
		throws = profile.throws,
		totalCoins = profile.totalCoins,
	}
end

-- The floating title over a character's head (or none below the first title).
local function applyTitle(player: Player)
	local profile = Data.get(player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not profile or not head or not head:IsA("BasePart") then
		return
	end
	local title = GoalData.title(profile.bestDistance)
	local existing = head:FindFirstChild(Progress.TITLE_NAME)
	if not title then
		if existing then
			existing:Destroy()
		end
		return
	end
	local gui: BillboardGui
	if existing and existing:IsA("BillboardGui") then
		gui = existing
	else
		gui = Instance.new("BillboardGui")
		gui.Name = Progress.TITLE_NAME
		gui.Size = UDim2.fromOffset(220, 34)
		gui.StudsOffset = Vector3.new(0, 2.6, 0)
		gui.MaxDistance = 80
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 236, 170)
		label.TextStrokeColor3 = Color3.fromRGB(24, 40, 70)
		label.TextStrokeTransparency = 0.2
		label.Parent = gui
		gui.Parent = head
	end
	local label = gui:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = `✦ {title} ✦`
	end
end

local function stat(player: Player, name: string, value: string | number)
	local stats = player:FindFirstChild("leaderstats")
	local holder = stats and stats:FindFirstChild(name)
	local fits = holder
		and (
			(holder:IsA("StringValue") and type(value) == "string")
			or (holder:IsA("IntValue") and type(value) == "number")
		)
	if fits then
		(holder :: any).Value = value
	end
end

local function updateLeaderstats(player: Player)
	local profile = Data.get(player)
	if not profile then
		return
	end
	stat(player, "Coins", Format.short(profile.coins))
	stat(player, "Longest", Format.short(profile.bestDistance))
	stat(player, "Rebirths", profile.rebirths)
end

-- Marks newly finished goals and newly reached islands, and tells the player.
function Progress.check(player: Player)
	local profile = Data.get(player)
	if not profile then
		return
	end
	for _, island in IslandData.LIST do
		if not profile.islands[island.id] and profile.bestDistance >= island.distance then
			profile.islands[island.id] = true
			Net.fire(player, "Island", island.id) -- the client shows a banner
		end
	end
	local stats = Progress.stats(profile)
	for _, goal in GoalData.GOALS do
		if not profile.goals[goal.id] and GoalData.isDone(goal, stats) then
			profile.goals[goal.id] = true
			Notify.send(player, `{goal.emoji} Goal complete: {goal.text}`, "good")
		end
	end
	updateLeaderstats(player)
	applyTitle(player)
	State.markDirty(player)
end

-- Folds one finished throw into the thrower's profile. Returns whether it
-- was their longest yet.
function Progress.recordThrow(player: Player, throw: Throw): boolean
	local profile = Data.get(player)
	if not profile then
		return false
	end
	local oldTitle = GoalData.title(profile.bestDistance)
	profile.coins += throw.coins
	profile.totalCoins += throw.coins
	if throw.skips > 0 then
		profile.throws += 1
		profile.totalSkips += throw.skips
	end
	if throw.perfect then
		profile.perfects += 1
	end
	profile.bestSkips = math.max(profile.bestSkips, throw.skips)
	local newBest = throw.distance > profile.bestDistance
	if newBest then
		profile.bestDistance = throw.distance
	end
	Progress.check(player)
	local newTitle = GoalData.title(profile.bestDistance)
	if newTitle and newTitle ~= oldTitle then
		Notify.send(player, `✦ New title: {newTitle} ✦`, "rare")
	end
	return newBest
end

-- After a rebirth or a reset: redraw the title and the player list.
function Progress.refresh(player: Player)
	if Data.get(player) then
		updateLeaderstats(player)
		applyTitle(player)
		State.markDirty(player)
	end
end

local function onReady(player: Player)
	local profile = Data.get(player)
	if not profile then
		return
	end
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	for _, name in { "Coins", "Longest" } do
		local value = Instance.new("StringValue")
		value.Name = name
		value.Parent = stats
	end
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = stats
	stats.Parent = player
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head", 10)
		if Sessions.getReady(player) then
			applyTitle(player)
		end
	end)
	if player.Character then
		task.spawn(applyTitle, player)
	end
	-- goals and islands added in an update may already be done
	Progress.check(player)
end

function Progress.init()
	Sessions.Ready:connect(onReady)
end

return Progress
