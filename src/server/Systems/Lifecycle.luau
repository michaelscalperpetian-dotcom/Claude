--!strict
-- Join and leave, in the right order:
--   join:  session -> load save -> claim a nest -> offline progress -> draw nest
--          -> spawn character -> ready -> tutorial/streak
--   leave: stop raids/riding -> free the nest -> final save + release lock

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Coins = require(script.Parent.Coins)
local Data = require(script.Parent.Data)
local Dinos = require(script.Parent.Dinos)
local Monetization = require(script.Parent.Monetization)
local Plots = require(script.Parent.Plots)
local Preferences = require(script.Parent.Preferences)
local Progress = require(script.Parent.Progress)
local Quests = require(script.Parent.Quests)
local Raids = require(script.Parent.Raids)
local Sessions = require(script.Parent.Sessions)
local Social = require(script.Parent.Social)
local State = require(script.Parent.State)
local World = require(script.Parent.World)

local Lifecycle = {}

local function onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.WalkSpeed = Config.NORMAL_WALKSPEED
	local session = Sessions.get(player)
	if session then
		session.mount = nil
		session.riding = nil
		session.originalHipHeight = nil
		State.markDirty(player)
	end
	task.defer(Social.decorateCharacter, player)
	humanoid.Died:Connect(function()
		Raids.dropCarry(player)
		Dinos.dismount(player)
		task.delay(3, function()
			if player.Parent ~= nil and Sessions.get(player) then
				player:LoadCharacterAsync()
			end
		end)
	end)
end

local function onJoin(player: Player)
	local session = Sessions.create(player)
	-- The player can leave during any yield below; onLeave then cleans up
	-- (including the nest) and this join stops.
	local function left(): boolean
		return player.Parent == nil or Sessions.get(player) ~= session
	end

	local profile = Data.load(player)
	if player.Parent == nil then
		Data.release(player)
		Sessions.remove(player)
		return
	end
	if not profile then
		Sessions.remove(player)
		player:Kick("We couldn't load your dinos right now. Please rejoin in a moment!")
		return
	end

	local index = Plots.assign(player)
	if not index then
		Data.release(player)
		Sessions.remove(player)
		player:Kick("This island is full! Please join another server.")
		return
	end

	-- Passes and the Club first, so offline earnings include their boosts.
	Monetization.onJoin(player)
	if left() then
		return
	end
	Dinos.applyOffline(player)
	Plots.renderAll(player)
	Coins.setupLeaderstats(player)
	task.spawn(Social.onJoin, player)

	local plot = World.getPlot(index)
	if plot then
		player.RespawnLocation = plot.spawn
	end
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	local loaded, err = pcall(function()
		player:LoadCharacterAsync()
	end)
	if left() then
		return
	end
	if not loaded then
		warn(`[Lifecycle] couldn't load {player.Name}'s character: {err}`)
	end

	session.ready = true
	Sessions.Ready:fire(player)
	Progress.onJoin(player)
	Quests.refresh(player)
	Preferences.syncBuddy(player)
	State.markDirty(player)
end

local function onLeave(player: Player)
	local session = Sessions.get(player)
	if not session then
		return
	end
	local wasReady = session.ready
	session.ready = false
	Sessions.Leaving:fire(player)
	if wasReady then
		Raids.onLeave(player)
		Dinos.dismount(player)
		Social.onLeave(player)
	end
	-- also when they leave before finishing joining (no-op without a nest)
	Plots.release(player)
	Data.release(player)
	Sessions.remove(player)
end

function Lifecycle.init()
	Players.CharacterAutoLoads = false
end

function Lifecycle.start()
	Players.PlayerAdded:Connect(onJoin)
	Players.PlayerRemoving:Connect(onLeave)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
end

return Lifecycle
