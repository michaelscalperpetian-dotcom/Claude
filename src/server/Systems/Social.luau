--!strict
-- Friends (coin boost + egg warming), nest likes, the Roar emote and the VIP tag.
-- All social features work without text chat, since many young players have
-- chat turned off.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Data = require(script.Parent.Data)
local Monetization = require(script.Parent.Monetization)
local Plots = require(script.Parent.Plots)
local Prompts = require(script.Parent.Prompts)
local Sessions = require(script.Parent.Sessions)
local State = require(script.Parent.State)
local World = require(script.Parent.World)
local Notify = require(script.Parent.Parent.Lib.Notify)
local Stats = require(script.Parent.Parent.Lib.Stats)

local Social = {}

-- Finds which players already here are friends with the new player.
function Social.onJoin(player: Player)
	local session = Sessions.get(player)
	if not session then
		return
	end
	for _, other in Players:GetPlayers() do
		if other == player then
			continue
		end
		local ok, isFriend = pcall(function()
			return player:IsFriendsWithAsync(other.UserId)
		end)
		if ok and isFriend then
			session.friendIds[other.UserId] = true
			local otherSession = Sessions.get(other)
			if otherSession then
				otherSession.friendIds[player.UserId] = true
				State.markDirty(other)
				Notify.send(
					other,
					`👋 Your friend {player.DisplayName} joined! Friends boost coins and warm eggs.`,
					"good"
				)
			end
		end
	end
	State.markDirty(player)
end

function Social.onLeave(player: Player)
	for _, session in Sessions.ready() do
		if session.friendIds[player.UserId] then
			session.friendIds[player.UserId] = nil
			State.markDirty(session.player)
		end
	end
end

-- Name tag over VIPs (and the plot sign shows likes for everyone).
function Social.decorateCharacter(player: Player)
	local session = Sessions.get(player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not session or not head then
		return
	end
	local existing = head:FindFirstChild("VipTag")
	if existing then
		existing:Destroy()
	end
	if not Stats.hasPass(session, "VIP") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "VipTag"
	gui.Size = UDim2.fromOffset(110, 30)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "⭐ VIP"
	label.TextColor3 = Color3.fromRGB(255, 215, 60)
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	gui.Parent = head
end

local function like(player: Player, prompt: ProximityPrompt)
	local ownerId = prompt:GetAttribute("OwnerId")
	local plotIndex = prompt:GetAttribute("PlotIndex")
	local session = Sessions.get(player)
	if typeof(plotIndex) ~= "number" or not session then
		return
	end
	local owner = Plots.ownerOf(plotIndex)
	if
		not owner
		or owner == player
		or (typeof(ownerId) == "number" and ownerId ~= owner.UserId)
	then
		return
	end
	if session.liked[owner.UserId] then
		Notify.send(player, "You already liked this nest today ❤", "info")
		return
	end
	local profile = Data.get(owner)
	if not profile then
		return
	end
	session.liked[owner.UserId] = true
	profile.likes += 1
	Plots.updateSign(owner)
	State.markDirty(owner)
	Notify.send(owner, `❤ {player.DisplayName} liked your nest!`, "good")
	Notify.send(player, "❤ Liked!", "good")
end

local function roar(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local session = Sessions.get(player)
	Notify.effectAll("Roar", {
		position = root.CFrame.Position,
		userId = player.UserId,
		big = session ~= nil and session.riding ~= nil,
	})
end

function Social.init()
	Prompts.register("Like", like)
	Net.on("Roar", 0.5, 1, function(player: Player)
		roar(player)
	end)
	Monetization.PassesChanged:connect(function(player: Player)
		Social.decorateCharacter(player)
	end)
end

function Social.start()
	-- A "Like" prompt on every nest sign, shown to visitors only. (World builds
	-- the plots during init, so this waits for start.)
	for _, plot in World.plots do
		Prompts.create(plot.signPart, {
			action = "Like",
			text = "Like ❤",
			objectText = "Nest",
			audience = "Others",
			plotIndex = plot.index,
			distance = 18,
		})
	end
end

return Social
