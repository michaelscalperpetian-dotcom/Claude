--!strict
-- Night raids. At night, visitors can steal eggs from another player's tray and
-- carry them home. Kid-friendly rules:
--   * only laid eggs can be stolen, never dinos you raised
--   * every nest has a free gate lock (with cooldown) and a first-day shield
--   * the owner can tag the thief to get the egg back; guard dinos roar thieves away
--   * the egg stays in the owner's save until the thief reaches home, so a
--     disconnect can never duplicate or delete an egg
--   * raids are off in private servers (configurable)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local Config = require(ReplicatedStorage.Shared.Config)
local Cycle = require(ReplicatedStorage.Shared.Util.Cycle)
local DinoData = require(ReplicatedStorage.Shared.Data.DinoData)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local EggModel = require(ReplicatedStorage.Shared.Visual.EggModel)
local Growth = require(ReplicatedStorage.Shared.Util.Growth)
local Net = require(ReplicatedStorage.Shared.Net)
local Analytics = require(script.Parent.Analytics)
local Coins = require(script.Parent.Coins)
local Data = require(script.Parent.Data)
local Dinos = require(script.Parent.Dinos)
local Nest = require(script.Parent.Nest)
local Plots = require(script.Parent.Plots)
local Prompts = require(script.Parent.Prompts)
local Sessions = require(script.Parent.Sessions)
local State = require(script.Parent.State)
local World = require(script.Parent.World)
local Notify = require(script.Parent.Parent.Lib.Notify)
local Stats = require(script.Parent.Parent.Lib.Stats)

local Raids = {}

local rng = Random.new()
local carriedEggs: { [string]: Player } = {} -- "ownerUserId:eggId" -> thief

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function isNight(): boolean
	return Cycle.dayNight(Clock.cycleNow()).isNight
end

local function carryKey(owner: Player, eggId: string): string
	return `{owner.UserId}:{eggId}`
end

function Raids.isProtected(owner: Player): boolean
	local session = Sessions.get(owner)
	local profile = Data.get(owner)
	if not session or not profile then
		return true
	end
	local now = Clock.now()
	return session.lockUntil > now or Stats.shieldUntil(profile) > now
end

local function stun(player: Player)
	local session = Sessions.get(player)
	local humanoid = humanoidOf(player)
	if not session or not humanoid then
		return
	end
	session.stunnedUntil = Clock.now() + Config.STUN_SECONDS
	humanoid.WalkSpeed = 0
	humanoid.JumpHeight = 0
	task.delay(Config.STUN_SECONDS, function()
		local s = Sessions.get(player)
		local h = humanoidOf(player)
		if s and h and Clock.now() >= s.stunnedUntil then
			h.WalkSpeed = if s.carry then Config.CARRY_WALKSPEED else Config.NORMAL_WALKSPEED
			h.JumpHeight = 7.2
		end
	end)
end

-- End a carry. success = thief made it home.
local function endCarry(thief: Player, success: boolean, reason: string?)
	local session = Sessions.get(thief)
	local carry = session and session.carry
	if not session or not carry then
		return
	end
	session.carry = nil
	local victim = carry.victim
	carriedEggs[carryKey(victim, carry.eggId)] = nil
	if carry.model then
		carry.model:Destroy()
	end
	local humanoid = humanoidOf(thief)
	if humanoid and Clock.now() >= session.stunnedUntil then
		humanoid.WalkSpeed = Config.NORMAL_WALKSPEED
	end
	local victimSession = Sessions.get(victim)
	local species = DinoData.get(carry.species)
	local name = if species then species.name else "dino"

	if success and victimSession and victimSession.ready then
		local victimProfile = Data.get(victim)
		local thiefProfile = Data.get(thief)
		local removed = Nest.removeTrayEgg(victim, carry.eggId)
		Plots.setTrayEggHidden(victim, carry.eggId, false)
		if removed and thiefProfile and victimProfile then
			victimProfile.stats.eggsLost += 1
			thiefProfile.stats.stolen += 1
			if not Nest.addTrayEgg(thief, removed.species) then
				local value = if species then Economy.trayEggValue(species.income) else 10
				Coins.add(thief, value, "Gameplay", "StolenEggSold")
			end
			Notify.send(thief, `🥚 You stole a {name} egg! Sneaky!`, "rare")
			Notify.send(
				victim,
				`😱 {thief.DisplayName} stole your {name} egg! Lock your gate at night!`,
				"bad"
			)
			Notify.effectAll(
				"Stolen",
				{ thief = thief.UserId, victim = victim.UserId, species = carry.species }
			)
			Analytics.event(thief, "StoleEgg")
		end
	else
		if victimSession then
			Plots.setTrayEggHidden(victim, carry.eggId, false)
		end
		if reason == "caught" then
			Notify.send(thief, "🫣 Caught! The egg went back home.", "bad")
			Notify.send(
				victim,
				`🛡 You caught {thief.DisplayName} and saved your {name} egg!`,
				"good"
			)
			Notify.effectAll("Caught", { thief = thief.UserId, victim = victim.UserId })
		elseif reason == "roar" then
			Notify.send(thief, "🦖 ROAR! The guard dinos made you drop the egg!", "bad")
		elseif reason == "morning" then
			Notify.send(thief, "☀️ The sun came up and the egg rolled home.", "info")
		end
	end
	State.markDirty(thief)
	if victimSession then
		State.markDirty(victim)
	end
end

local function steal(thief: Player, prompt: ProximityPrompt)
	local ownerId = Prompts.ownerId(prompt)
	local eggId = Prompts.key(prompt)
	if not ownerId or not eggId or ownerId == thief.UserId then
		return
	end
	local owner = Players:GetPlayerByUserId(ownerId)
	local thiefSession = Sessions.get(thief)
	if not owner or not thiefSession or not thiefSession.ready then
		return
	end
	local ownerSession = Sessions.get(owner)
	local ownerProfile = Data.get(owner)
	if not ownerSession or not ownerSession.ready or not ownerProfile then
		return
	end
	if not Stats.raidsEnabled() or not isNight() then
		return
	end
	if Raids.isProtected(owner) then
		Notify.send(thief, "This nest is protected right now!", "bad")
		return
	end
	if thiefSession.carry or Clock.now() < thiefSession.stunnedUntil then
		return
	end
	if carriedEggs[carryKey(owner, eggId)] then
		return
	end
	local egg = Nest.findTrayEgg(ownerProfile, eggId)
	local root = rootOf(thief)
	local trayPosition = Plots.trayPosition(owner)
	if
		not egg
		or not root
		or not trayPosition
		or (root.CFrame.Position - trayPosition).Magnitude > 16
	then
		return
	end

	Dinos.dismount(thief)
	local head = thief.Character and thief.Character:FindFirstChild("Head")
	local model: Model? = nil
	if head and head:IsA("BasePart") then
		local carried = EggModel.build(EggModel.lookForSpecies(egg.species), 2.2)
		carried.Name = "CarriedEgg"
		local carriedRoot = carried.PrimaryPart :: BasePart
		carriedRoot.Anchored = false
		carriedRoot.Massless = true
		for _, d in carried:GetDescendants() do
			if d:IsA("BasePart") then
				d.Massless = true
				d.CanCollide = false
			end
		end
		carried:PivotTo(head.CFrame * CFrame.new(0, head.Size.Y / 2 + 0.2, 0))
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = carriedRoot
		weld.Parent = carriedRoot
		carried.Parent = thief.Character
		model = carried
	end

	thiefSession.carry = {
		victim = owner,
		eggId = eggId,
		species = egg.species,
		model = model,
		startedAt = Clock.now(),
	}
	carriedEggs[carryKey(owner, eggId)] = thief
	Plots.setTrayEggHidden(owner, eggId, true)
	local humanoid = humanoidOf(thief)
	if humanoid then
		humanoid.WalkSpeed = Config.CARRY_WALKSPEED
	end
	Notify.send(thief, "🏃 Run back to your nest with the egg!", "event")
	Notify.send(
		owner,
		`🚨 {thief.DisplayName} is stealing your egg! Tag them to get it back!`,
		"bad"
	)
	State.markDirty(thief)
	State.markDirty(owner)
end

local function carryTick()
	local night = isNight()
	for _, session in Sessions.ready() do
		local carry = session.carry
		if not carry then
			continue
		end
		local thief = session.player
		local root = rootOf(thief)
		local victimSession = Sessions.get(carry.victim)
		if not root or not victimSession or not victimSession.ready then
			endCarry(thief, false, nil)
		elseif not night then
			endCarry(thief, false, "morning")
		else
			local victimRoot = rootOf(carry.victim)
			if
				victimRoot
				and (victimRoot.CFrame.Position - root.CFrame.Position).Magnitude
					<= Config.TAG_RANGE
			then
				endCarry(thief, false, "caught")
				stun(thief)
			elseif World.isInside(session.plotIndex, root.CFrame.Position) then
				endCarry(thief, true, nil)
			end
		end
	end
end

-- Grown dinos guard the nest at night.
local function guardTick()
	if not isNight() then
		return
	end
	local now = Clock.now()
	for _, ownerSession in Sessions.ready() do
		local owner = ownerSession.player
		local profile = Data.get(owner)
		if not profile then
			continue
		end
		local power = 0
		local strongest: string? = nil
		local strongestStage = 0
		for _, dino in profile.dinos do
			local stage = Stats.dinoStage(dino, now)
			if stage >= Growth.ADULT then
				power += if stage >= Growth.GIANT then 2 else 1
				if stage > strongestStage then
					strongestStage = stage
					strongest = dino.id
				end
			end
		end
		if power == 0 then
			continue
		end
		local chance = math.min(Config.GUARD_MAX_CHANCE, power * Config.GUARD_CHANCE_PER_POWER)
		for _, visitor in Sessions.ready() do
			if visitor.player == owner or now < visitor.stunnedUntil then
				continue
			end
			local root = rootOf(visitor.player)
			if not root or not World.isInside(ownerSession.plotIndex, root.CFrame.Position) then
				continue
			end
			if rng:NextNumber() < chance then
				stun(visitor.player)
				local model = strongest and Plots.dinoModel(owner, strongest)
				local position = if model then model:GetPivot().Position else root.CFrame.Position
				Notify.effectAll("Roar", { position = position, big = true })
				if visitor.carry and visitor.carry.victim == owner then
					endCarry(visitor.player, false, "roar")
				else
					Notify.send(visitor.player, "🦖 ROAR! The guard dinos scared you!", "bad")
				end
			end
		end
	end
end

-- Locked nests push visitors back out of the gate.
local function lockTick()
	local now = Clock.now()
	for _, ownerSession in Sessions.ready() do
		if ownerSession.lockUntil <= now then
			continue
		end
		for _, visitor in Sessions.ready() do
			if visitor.player == ownerSession.player then
				continue
			end
			local root = rootOf(visitor.player)
			if root and World.isInside(ownerSession.plotIndex, root.CFrame.Position, 1) then
				local character = visitor.player.Character
				if character then
					character:PivotTo(World.outsideGate(ownerSession.plotIndex))
				end
			end
		end
	end
end

local function lockGate(player: Player)
	local session = Sessions.get(player)
	if not session or not session.ready then
		return
	end
	local now = Clock.now()
	if now < session.lockCooldownUntil then
		return
	end
	session.lockUntil = math.max(session.lockUntil, now + Config.GATE_LOCK_SECONDS)
	session.lockCooldownUntil = now + Config.GATE_LOCK_SECONDS + Config.GATE_COOLDOWN_SECONDS
	Plots.setBarrier(player, session.lockUntil)
	Notify.send(player, "🔒 Gate locked! Nobody can get in for a minute.", "good")
	State.markDirty(player)
	task.delay(Config.GATE_LOCK_SECONDS + 0.1, function()
		if Sessions.get(player) then
			Plots.setBarrier(player, session.lockUntil)
		end
	end)
end

-- Robux "Super Lock": extends the lock without touching the free cooldown.
function Raids.superLock(player: Player)
	local session = Sessions.get(player)
	if not session then
		return
	end
	local now = Clock.now()
	session.lockUntil = math.max(session.lockUntil, now) + Config.SUPER_LOCK_SECONDS
	Plots.setBarrier(player, session.lockUntil)
	State.markDirty(player)
	task.delay(session.lockUntil - now + 0.1, function()
		if Sessions.get(player) then
			Plots.setBarrier(player, session.lockUntil)
		end
	end)
end

-- Called by Lifecycle before a player's data is released.
function Raids.onLeave(player: Player)
	local session = Sessions.get(player)
	if session and session.carry then
		endCarry(player, false, nil)
	end
	for _, other in Sessions.ready() do
		if other.carry and other.carry.victim == player then
			endCarry(other.player, false, nil)
		end
	end
end

-- One pass of the carry and lock checks. The start() loops call these on
-- timers; tests call this directly.
function Raids.step()
	carryTick()
	lockTick()
end

function Raids.init()
	Prompts.register("Steal", steal)
	Net.on("LockGate", 1, 2, function(player: Player)
		lockGate(player)
	end)
	ReplicatedStorage:SetAttribute("RaidsEnabled", Stats.raidsEnabled())
end

function Raids.start()
	task.spawn(function()
		while true do
			task.wait(0.2)
			carryTick()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			lockTick()
		end
	end)
	while true do
		task.wait(Config.GUARD_TICK)
		guardTick()
	end
end

return Raids
