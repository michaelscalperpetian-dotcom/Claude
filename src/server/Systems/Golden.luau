--!strict
-- Golden dinos: fuse three dinos of one species into a Golden one that earns
-- Config.GOLDEN_MULTIPLIER times the coins. The dino you fuse from keeps its
-- id, name and spot, and takes the oldest age and best mutation of the three.
-- The two partners are the cheapest other dinos of that species. A small coin
-- fee keeps it a choice (and frees up nest space).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local DinoData = require(ReplicatedStorage.Shared.Data.DinoData)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local MutationData = require(ReplicatedStorage.Shared.Data.MutationData)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local Coins = require(script.Parent.Coins)
local Data = require(script.Parent.Data)
local Dinos = require(script.Parent.Dinos)
local Nest = require(script.Parent.Nest)
local Plots = require(script.Parent.Plots)
local Preferences = require(script.Parent.Preferences)
local Sessions = require(script.Parent.Sessions)
local State = require(script.Parent.State)
local Notify = require(script.Parent.Parent.Lib.Notify)
local Stats = require(script.Parent.Parent.Lib.Stats)

local Golden = {}

Golden.NEEDED = 3

-- Other non-golden dinos of the same species, cheapest first.
function Golden.partners(profile: Types.Profile, keeper: Types.DinoRecord): { Types.DinoRecord }
	local species = DinoData.get(keeper.species)
	local now = Clock.now()
	local list = {}
	for _, dino in profile.dinos do
		if dino ~= keeper and dino.species == keeper.species and not dino.golden then
			table.insert(list, dino)
		end
	end
	local function value(dino: Types.DinoRecord): number
		local income = if species then species.income else 1
		return Economy.dinoValue(
			income,
			Stats.dinoStage(dino, now),
			MutationData.multiplier(dino.mutation)
		)
	end
	table.sort(list, function(a, b)
		return value(a) < value(b)
	end)
	return list
end

local function fuse(player: Player, dinoId: string)
	local profile = Data.get(player)
	local session = Sessions.get(player)
	if not profile or not session or not session.ready then
		return
	end
	local keeper = Nest.findDino(profile, dinoId)
	local species = keeper and DinoData.get(keeper.species)
	if not keeper or not species or keeper.golden then
		return
	end
	local partners = Golden.partners(profile, keeper)
	if #partners < Golden.NEEDED - 1 then
		Notify.send(
			player,
			`You need {Golden.NEEDED} {species.name}s to make a Golden one!`,
			"info"
		)
		return
	end
	local fee = Economy.goldenFee(species.income)
	if not Coins.spend(player, fee, "Gameplay", "GoldenFuse") then
		Notify.send(player, `Making it Golden costs 💰 {Format.number(fee)}.`, "bad")
		return
	end

	local mutation = keeper.mutation
	local bornAt = keeper.bornAt
	for i = 1, Golden.NEEDED - 1 do
		local partner = partners[i]
		if MutationData.multiplier(partner.mutation) > MutationData.multiplier(mutation) then
			mutation = partner.mutation
		end
		bornAt = math.min(bornAt, partner.bornAt)
		if session.riding == partner.id then
			Dinos.dismount(player)
		end
		Nest.removeDino(player, partner.id)
	end
	if session.riding == keeper.id then
		Dinos.dismount(player) -- the mount is rebuilt golden next ride
	end
	keeper.golden = true
	keeper.mutation = mutation
	keeper.bornAt = bornAt
	Plots.syncDinos(player)
	Preferences.syncBuddy(player)
	State.markDirty(player)
	Nest.DinoChanged:fire(player, keeper)
	Notify.effect(player, "Golden", { species = keeper.species, mutation = mutation })
	Notify.send(
		player,
		`⭐ Your {species.name} is GOLDEN! It earns {Economy.goldenMultiplier(true)}x coins!`,
		"rare"
	)
end

function Golden.init()
	Net.on("FuseGolden", 1, 3, function(player: Player, dinoId: unknown)
		if typeof(dinoId) == "string" and #dinoId <= 20 then
			fuse(player, dinoId)
		end
	end)
end

return Golden
