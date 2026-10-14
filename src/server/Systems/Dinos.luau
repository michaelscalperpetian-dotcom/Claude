--!strict
-- Living dinos: growth (re-rendering as they grow), coin income onto the pad,
-- egg laying, offline earnings, selling, and riding (game pass).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local Config = require(ReplicatedStorage.Shared.Config)
local DinoData = require(ReplicatedStorage.Shared.Data.DinoData)
local DinoModel = require(ReplicatedStorage.Shared.Visual.DinoModel)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Growth = require(ReplicatedStorage.Shared.Util.Growth)
local MutationData = require(ReplicatedStorage.Shared.Data.MutationData)
local Net = require(ReplicatedStorage.Shared.Net)
local Coins = require(script.Parent.Coins)
local Data = require(script.Parent.Data)
local Nest = require(script.Parent.Nest)
local Plots = require(script.Parent.Plots)
local Progress = require(script.Parent.Progress)
local Quests = require(script.Parent.Quests)
local Sessions = require(script.Parent.Sessions)
local State = require(script.Parent.State)
local World = require(script.Parent.World)
local Notify = require(script.Parent.Parent.Lib.Notify)
local Stats = require(script.Parent.Parent.Lib.Stats)

local Dinos = {}

local lastCollect: { [Player]: number } = {}

-- ===== Riding =====

function Dinos.dismount(player: Player)
	local session = Sessions.get(player)
	if not session then
		return
	end
	if session.mount then
		session.mount:Destroy()
		session.mount = nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if session.originalHipHeight then
			humanoid.HipHeight = session.originalHipHeight
		end
		if session.carry == nil then
			humanoid.WalkSpeed = Config.NORMAL_WALKSPEED
		end
	end
	session.originalHipHeight = nil
	if session.riding then
		session.riding = nil
		State.markDirty(player)
	end
end

local function ride(player: Player, dinoId: string)
	local session = Sessions.get(player)
	local profile = Data.get(player)
	if not session or not profile or not session.ready then
		return
	end
	if not Stats.hasPass(session, "RideDinos") then
		Notify.send(player, "Get the 🦖 Ride Your Dinos pass to ride!", "info")
		return
	end
	if session.carry then
		Notify.send(player, "You can't ride while carrying an egg!", "bad")
		return
	end
	local dino = Nest.findDino(profile, dinoId)
	if not dino then
		return
	end
	local stage = Stats.dinoStage(dino, Clock.now())
	if stage < Growth.JUVENILE then
		Notify.send(player, "This baby is too small to ride. Let it grow first!", "info")
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	Dinos.dismount(player)

	local mount = DinoModel.build(dino.species, stage, dino.mutation, "Mount", dino.golden)
	mount.Name = "Mount"
	local height = mount:GetAttribute("Height")
	local saddle = if typeof(height) == "number" then height * 0.55 else 3
	session.originalHipHeight = humanoid.HipHeight
	local newHip = humanoid.HipHeight + saddle
	humanoid.HipHeight = newHip

	local mountRoot = mount.PrimaryPart :: BasePart
	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = mountRoot
	weld.C0 = CFrame.new(0, -(root.Size.Y / 2 + newHip), 0)
	weld.Parent = mountRoot
	mount.Parent = character

	humanoid.WalkSpeed = Config.RIDE_WALKSPEED
	session.mount = mount
	session.riding = dinoId
	State.markDirty(player)
end

-- ===== Selling =====

local function sellDino(player: Player, dinoId: string)
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
	if session.riding == dinoId then
		Dinos.dismount(player)
	end
	local stage = Stats.dinoStage(dino, Clock.now())
	local value = Economy.dinoValue(
		species.income,
		stage,
		MutationData.multiplier(dino.mutation) * Economy.goldenMultiplier(dino.golden)
	)
	Nest.removeDino(player, dinoId)
	profile.stats.sold += 1
	local amount = Coins.add(player, value, "Gameplay", "SellDino")
	Notify.send(player, `Sold {species.name} for 💰 {Format.number(amount)}`, "good")
end

-- ===== Income, growth, laying =====

local function layEggs(player: Player)
	local profile = Data.get(player)
	if not profile then
		return
	end
	local now = Clock.now()
	local laidNames: { string } = {}
	for _, dino in profile.dinos do
		local species = DinoData.get(dino.species)
		if not species then
			continue
		end
		local room = Nest.trayRoom(profile)
		local laid, newLast = Growth.laysDue(
			dino.bornAt,
			dino.lastLaidAt,
			species.growth,
			now,
			Config.LAY_INTERVAL_ADULT,
			Config.LAY_INTERVAL_GIANT,
			room
		)
		dino.lastLaidAt = newLast
		for _ = 1, laid do
			if Nest.addTrayEgg(player, dino.species) then
				table.insert(laidNames, species.name)
			end
		end
	end
	if #laidNames == 1 then
		Notify.send(player, `🥚 Your {laidNames[1]} laid an egg!`, "good")
	elseif #laidNames > 1 then
		Notify.send(player, `🥚 Your dinos laid {#laidNames} eggs!`, "good")
	end
end

-- Coins earned while away go onto the pad so returning players get a big pile.
function Dinos.applyOffline(player: Player)
	local profile = Data.get(player)
	local session = Sessions.get(player)
	if not profile or not session then
		return
	end
	local now = Clock.now()
	local away = now - profile.lastSeen
	if away < 60 then
		return
	end
	local income = Stats.incomePerSecond(profile, session, now)
	local earned = Economy.offlineCoins(income, away)
	if earned > 0 then
		profile.pendingCoins += earned
		task.delay(4, function()
			Notify.send(
				player,
				`While you were away your dinos made 💰 {Format.number(earned)}! Grab it from your coin pad.`,
				"good"
			)
		end)
	end
	layEggs(player)
end

local function tick(dt: number, withLaying: boolean)
	local now = Clock.now()
	for _, session in Sessions.ready() do
		local player = session.player
		local profile = Data.get(player)
		if not profile then
			continue
		end
		local income = Stats.incomePerSecond(profile, session, now)
		Coins.accrue(player, income * dt, Stats.hasPass(session, "AutoCollect"))
		Plots.updatePad(player, profile.pendingCoins)
		Plots.syncDinos(player)
		if withLaying then
			layEggs(player)
		end
	end
end

local function collectPad(player: Player, plot: World.PlotInfo)
	if Plots.ownerOf(plot.index) ~= player then
		return
	end
	local now = os.clock()
	if lastCollect[player] and now - lastCollect[player] < 0.5 then
		return
	end
	lastCollect[player] = now
	local amount = Coins.collect(player)
	if amount > 0 then
		Plots.updatePad(player, 0)
		Notify.effect(player, "Collect", { amount = amount, position = plot.pad.CFrame.Position })
		Quests.track(player, "collect")
	end
	-- Advance the tutorial even if the pad was nearly empty.
	Progress.event(player, "collect")
end

local function hookCoinPads()
	for _, plot in World.plots do
		plot.pad.Touched:Connect(function(hit: BasePart)
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = character and Players:GetPlayerFromCharacter(character)
			if player then
				collectPad(player, plot)
			end
		end)
	end
end

-- Riders float above the pad (their feet never touch it), so collect by
-- distance while riding.
function Dinos.collectForRiders()
	for _, session in Sessions.ready() do
		local plot = if session.riding then World.getPlot(session.plotIndex) else nil
		local character = session.player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if plot and root and root:IsA("BasePart") then
			local offset = root.CFrame.Position - plot.pad.CFrame.Position
			if Vector3.new(offset.X, 0, offset.Z).Magnitude <= 5 and math.abs(offset.Y) <= 14 then
				collectPad(session.player, plot)
			end
		end
	end
end

-- One income/growth/laying pass (start() runs this every second; tests call it).
function Dinos.step(dt: number)
	tick(dt, true)
end

function Dinos.init()
	Net.on("SellDino", 3, 5, function(player: Player, dinoId: unknown)
		if typeof(dinoId) == "string" and #dinoId <= 20 then
			sellDino(player, dinoId)
		end
	end)
	Net.on("Ride", 1, 3, function(player: Player, dinoId: unknown)
		if dinoId == nil then
			Dinos.dismount(player)
		elseif typeof(dinoId) == "string" and #dinoId <= 20 then
			ride(player, dinoId)
		end
	end)
	Sessions.Leaving:connect(function(player: Player)
		lastCollect[player] = nil
	end)
end

function Dinos.start()
	hookCoinPads()
	local ticks = 0
	while true do
		local dt = task.wait(1)
		ticks += 1
		tick(dt, ticks % 5 == 0)
		Dinos.collectForRiders()
	end
end

return Dinos
