--!strict
-- Spending coins: buying and choosing rocks, arm-strength upgrades and
-- rebirths. Also the rock in each player's hand. Every request is checked
-- here: the client only asks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Economy)
local Net = require(ReplicatedStorage.Shared.Net)
local RockData = require(ReplicatedStorage.Shared.Data.RockData)
local RockModel = require(ReplicatedStorage.Shared.RockModel)
local Types = require(ReplicatedStorage.Shared.Types)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Notify = require(script.Parent.Parent.Lib.Notify)
local Data = require(script.Parent.Data)
local Progress = require(script.Parent.Progress)
local Sessions = require(script.Parent.Sessions)
local State = require(script.Parent.State)

local Shop = {}

Shop.HELD_NAME = "HeldRock"

-- Why a request was refused: "notReady" | "unknown" | "owned" | "locked" |
-- "poor" | "notOwned" | "maxed" (plain strings: the type checker widens them).
export type Refusal = string

-- ===== The rock in your hand =====

local function hand(character: Model): BasePart?
	local right = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if right and right:IsA("BasePart") then
		return right
	end
	return nil
end

-- Puts the equipped rock in the character's right hand (replacing the old one).
function Shop.updateHeld(player: Player)
	local profile = Data.get(player)
	local character = player.Character
	if not profile or not character then
		return
	end
	local old = character:FindFirstChild(Shop.HELD_NAME)
	if old then
		old:Destroy()
	end
	local grip = hand(character)
	if not grip then
		return
	end
	local rock = RockModel.build(profile.equipped, 0.8)
	rock.Name = Shop.HELD_NAME
	rock.Anchored = false
	rock:SetAttribute("BaseTransparency", rock.Transparency)
	local attachment = grip:FindFirstChild("RightGripAttachment")
	local at = if attachment and attachment:IsA("Attachment")
		then attachment.WorldCFrame
		else grip.CFrame * CFrame.new(0, -grip.Size.Y / 2, 0)
	rock.CFrame = at * CFrame.new(0, -0.15, 0) * CFrame.Angles(0, 0, math.rad(90))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = grip
	weld.Part1 = rock
	weld.Parent = rock
	rock.Parent = character
end

-- Hides the held rock while a thrown one is in the air.
function Shop.hideHeld(player: Player, seconds: number)
	local character = player.Character
	local held = character and character:FindFirstChild(Shop.HELD_NAME)
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

-- ===== Buying =====

local function ready(player: Player): Types.Profile?
	if not Sessions.getReady(player) then
		return nil
	end
	return Data.get(player)
end

function Shop.equip(player: Player, id: unknown): Refusal?
	local profile = ready(player)
	if not profile then
		return "notReady"
	end
	if type(id) ~= "string" or not RockData.get(id) then
		return "unknown"
	end
	if not profile.rocks[id] then
		return "notOwned"
	end
	if profile.equipped ~= id then
		profile.equipped = id
		Shop.updateHeld(player)
		State.markDirty(player)
	end
	return nil
end

function Shop.buyRock(player: Player, id: unknown): Refusal?
	local profile = ready(player)
	if not profile then
		return "notReady"
	end
	local rock = if type(id) == "string" then RockData.get(id) else nil
	if not rock then
		return "unknown"
	end
	if profile.rocks[rock.id] then
		return "owned"
	end
	if not Economy.rockUnlocked(rock, profile.islands) then
		return "locked"
	end
	if profile.coins < rock.price then
		return "poor"
	end
	profile.coins -= rock.price
	profile.rocks[rock.id] = true
	-- a new rock goes straight into your hand if it's better than the one you hold
	local held = Economy.rockOf(Economy.statsOf(profile))
	if rock.power > held.power then
		profile.equipped = rock.id
		Shop.updateHeld(player)
	end
	Notify.send(player, `🪨 You bought {rock.name}!`, "good")
	Progress.check(player)
	State.markDirty(player)
	return nil
end

-- Buys `count` strength levels (or as many as you can afford, if fewer).
-- Returns how many it bought.
function Shop.upgrade(player: Player, count: unknown): (number, Refusal?)
	local profile = ready(player)
	if not profile then
		return 0, "notReady"
	end
	local wanted = if type(count) == "number" and count == count
		then math.clamp(math.floor(count), 1, 100)
		else 1
	local bought = 0
	while bought < wanted do
		if profile.strength >= Economy.MAX_STRENGTH then
			break
		end
		local cost = Economy.strengthCost(profile.strength)
		if profile.coins < cost then
			break
		end
		profile.coins -= cost
		profile.strength += 1
		bought += 1
	end
	if bought == 0 then
		return 0, if profile.strength >= Economy.MAX_STRENGTH then "maxed" else "poor"
	end
	State.markDirty(player)
	return bought, nil
end

function Shop.rebirth(player: Player): Refusal?
	local profile = ready(player)
	if not profile then
		return "notReady"
	end
	local cost = Economy.rebirthCost(profile.rebirths)
	if profile.coins < cost then
		return "poor"
	end
	profile.rebirths += 1
	profile.coins = 0
	profile.strength = 0
	local multiplier = Economy.coinMultiplier(Economy.statsOf(profile))
	Notify.send(
		player,
		`🔁 Rebirth {profile.rebirths}! Every throw now pays {Format.times(multiplier)} coins`,
		"rare"
	)
	Progress.check(player)
	Progress.refresh(player)
	State.markDirty(player)
	return nil
end

local MESSAGES: { [string]: string } = {
	poor = "Not enough coins yet",
	locked = "Skip a rock past the island to unlock this one",
	maxed = "Your arm can't get any stronger",
}

local function tell(player: Player, refusal: Refusal?)
	local message = refusal and MESSAGES[refusal]
	if message then
		Notify.send(player, message, "bad")
	end
end

function Shop.init()
	Net.on("Equip", 4, 8, function(player: Player, id: unknown)
		Shop.equip(player, id)
	end)
	Net.on("BuyRock", 3, 6, function(player: Player, id: unknown)
		tell(player, Shop.buyRock(player, id))
	end)
	Net.on("Upgrade", 6, 12, function(player: Player, count: unknown)
		local _, refusal = Shop.upgrade(player, count)
		tell(player, refusal)
	end)
	Net.on("Rebirth", 1, 2, function(player: Player)
		tell(player, Shop.rebirth(player))
	end)
	Sessions.Ready:connect(function(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 10)
			character:WaitForChild("RightHand", 3)
			if Sessions.getReady(player) and player.Character == character then
				Shop.updateHeld(player)
			end
		end)
		-- the avatar's own body parts can replace the hands once it loads
		player.CharacterAppearanceLoaded:Connect(function(character)
			if Sessions.getReady(player) and player.Character == character then
				Shop.updateHeld(player)
			end
		end)
		if player.Character then
			task.spawn(Shop.updateHeld, player)
		end
	end)
end

return Shop
