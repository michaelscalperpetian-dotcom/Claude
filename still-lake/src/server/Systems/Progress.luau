--!strict
-- Records, journal goals and titles. Every finished throw comes through
-- recordThrow; finding a stone comes through check. A skipper's title floats
-- over their head and their best throw shows on the player list.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GoalData = require(ReplicatedStorage.Shared.Data.GoalData)
local Skip = require(ReplicatedStorage.Shared.Skip)
local Types = require(ReplicatedStorage.Shared.Types)
local Notify = require(script.Parent.Parent.Lib.Notify)
local Data = require(script.Parent.Data)
local Sessions = require(script.Parent.Sessions)
local State = require(script.Parent.State)

local Progress = {}

Progress.TITLE_NAME = "SkipperTitle"

export type Records = { newBestSkips: boolean, newBestDistance: boolean }

function Progress.stats(profile: Types.Profile): GoalData.Stats
	local kinds = 0
	for _, count in profile.stones do
		if count > 0 then
			kinds += 1
		end
	end
	return {
		bestSkips = profile.bestSkips,
		bestDistance = profile.bestDistance,
		perfects = profile.perfects,
		stones = kinds,
		shore = profile.shore,
		nightSkips = profile.nightSkips,
		throws = profile.throws,
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
	local title = GoalData.title(profile.bestSkips)
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
		gui.MaxDistance = 70
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 240, 200)
		label.TextStrokeColor3 = Color3.fromRGB(40, 50, 70)
		label.TextStrokeTransparency = 0.2
		label.Parent = gui
		gui.Parent = head
	end
	local label = gui:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = `✦ {title} ✦`
	end
end

local function setLeaderstat(player: Player, bestSkips: number)
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Best Skips")
	if value and value:IsA("IntValue") then
		value.Value = bestSkips
	end
end

-- Marks newly finished goals and tells the player about each one.
function Progress.check(player: Player)
	local profile = Data.get(player)
	if not profile then
		return
	end
	local stats = Progress.stats(profile)
	for _, goal in GoalData.GOALS do
		if not profile.goals[goal.id] and GoalData.isDone(goal, stats) then
			profile.goals[goal.id] = true
			Notify.send(player, `{goal.emoji} Goal complete: {goal.text}`, "good")
		end
	end
	State.markDirty(player)
end

-- Folds one finished throw into the thrower's profile.
function Progress.recordThrow(player: Player, outcome: Skip.Outcome, night: boolean): Records
	local profile = Data.get(player)
	local records: Records = { newBestSkips = false, newBestDistance = false }
	if not profile then
		return records
	end
	local oldTitle = GoalData.title(profile.bestSkips)
	if outcome.skips > 0 then
		profile.throws += 1
		profile.totalSkips += outcome.skips
	end
	if outcome.perfect then
		profile.perfects += 1
	end
	if outcome.skips > profile.bestSkips then
		profile.bestSkips = outcome.skips
		records.newBestSkips = true
	end
	local distance = math.floor(outcome.distance * 10 + 0.5) / 10
	if distance > profile.bestDistance then
		profile.bestDistance = distance
		records.newBestDistance = true
	end
	if night and outcome.skips > profile.nightSkips then
		profile.nightSkips = outcome.skips
	end
	if outcome.verdict == "shore" then
		profile.shore = true
	end
	Progress.check(player)
	if records.newBestSkips then
		setLeaderstat(player, profile.bestSkips)
		local newTitle = GoalData.title(profile.bestSkips)
		if newTitle and newTitle ~= oldTitle then
			applyTitle(player)
			Notify.send(player, `✦ New title: {newTitle} ✦`, "rare")
		end
	end
	return records
end

-- After a profile reset (testing): redraw the title and the player list.
function Progress.refresh(player: Player)
	local profile = Data.get(player)
	if profile then
		setLeaderstat(player, profile.bestSkips)
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
	local best = Instance.new("IntValue")
	best.Name = "Best Skips"
	best.Value = profile.bestSkips
	best.Parent = stats
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
	-- goals added in an update may already be done
	Progress.check(player)
end

function Progress.init()
	Sessions.Ready:connect(onReady)
end

return Progress
