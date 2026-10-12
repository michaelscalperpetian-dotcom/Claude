--!strict
-- Gives each player a nest (plot) and draws their dinos, incubator eggs and
-- laid eggs into the world from their profile. Rendering is diff-based: a
-- model is only rebuilt when that dino's stage or mutation changes.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local Config = require(ReplicatedStorage.Shared.Config)
local DinoData = require(ReplicatedStorage.Shared.Data.DinoData)
local DinoModel = require(ReplicatedStorage.Shared.Visual.DinoModel)
local EggData = require(ReplicatedStorage.Shared.Data.EggData)
local EggModel = require(ReplicatedStorage.Shared.Visual.EggModel)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Growth = require(ReplicatedStorage.Shared.Util.Growth)
local MutationData = require(ReplicatedStorage.Shared.Data.MutationData)
local Types = require(ReplicatedStorage.Shared.Types)
local Data = require(script.Parent.Data)
local Prompts = require(script.Parent.Prompts)
local Sessions = require(script.Parent.Sessions)
local World = require(script.Parent.World)
local Stats = require(script.Parent.Parent.Lib.Stats)

local Plots = {}

Plots.EGG_TAG = "IncubatorEgg"

type DinoRender = { model: Model, stage: number, mutation: string, home: number }
type EggRender = { id: string, model: Model }

type Render = {
	dinos: { [string]: DinoRender },
	eggs: { [string]: EggRender }, -- by incubator slot ("1".."5")
	tray: { [string]: Model }, -- by tray egg id
	hiddenTray: { [string]: boolean },
}

local renders: { [Player]: Render } = {}
local owners: { [number]: Player } = {} -- plot index -> player

local function plotFor(player: Player): World.PlotInfo?
	local session = Sessions.get(player)
	if not session or session.plotIndex == 0 then
		return nil
	end
	return World.getPlot(session.plotIndex)
end

function Plots.ownerOf(index: number): Player?
	return owners[index]
end

-- Claim the first free plot. Returns its index or nil when the server is full.
function Plots.assign(player: Player): number?
	local session = Sessions.get(player)
	if not session then
		return nil
	end
	for index = 1, Config.PLOT_COUNT do
		if not owners[index] then
			owners[index] = player
			session.plotIndex = index
			renders[player] = { dinos = {}, eggs = {}, tray = {}, hiddenTray = {} }
			local plot = World.getPlot(index)
			if plot then
				plot.model:SetAttribute("OwnerId", player.UserId)
			end
			Plots.updateSign(player)
			return index
		end
	end
	return nil
end

local function clearFolder(folder: Instance)
	for _, child in folder:GetChildren() do
		child:Destroy()
	end
end

function Plots.release(player: Player)
	local session = Sessions.get(player)
	if not session or session.plotIndex == 0 then
		return
	end
	local index = session.plotIndex
	local plot = World.getPlot(index)
	if plot then
		clearFolder(plot.dinoFolder)
		clearFolder(plot.eggFolder)
		clearFolder(plot.trayFolder)
		plot.model:SetAttribute("OwnerId", 0)
		plot.model:SetAttribute("LockedUntil", 0)
		plot.model:SetAttribute("ShieldUntil", 0)
		World.setSign(plot, "Empty Nest", "Waiting for a new owner")
		plot.padLabel.Text = "💰 0"
		for _, wall in plot.barrier do
			wall.Transparency = 1
		end
		for slot = 1, Config.MAX_INCUBATORS do
			plot.incubatorLocks[slot].Enabled = false
			plot.incubatorRings[slot].Transparency = 0
		end
	end
	owners[index] = nil
	renders[player] = nil
	session.plotIndex = 0
end

function Plots.updateSign(player: Player)
	local plot = plotFor(player)
	local profile = Data.get(player)
	if not plot then
		return
	end
	local likes = if profile then profile.likes else 0
	local shielded = profile ~= nil and Stats.shieldUntil(profile) > Clock.now()
	local info = `❤ {Format.number(likes)} likes`
		.. (if shielded then "  🛡 New Nest Shield" else "")
	World.setSign(plot, `{player.DisplayName}'s Nest`, info)
	if profile then
		plot.model:SetAttribute("ShieldUntil", Stats.shieldUntil(profile))
	end
end

function Plots.updatePad(player: Player, amount: number)
	local plot = plotFor(player)
	if plot then
		plot.padLabel.Text = "💰 " .. Format.number(math.floor(amount))
	end
end

function Plots.setBarrier(player: Player, lockedUntil: number)
	local plot = plotFor(player)
	if not plot then
		return
	end
	plot.model:SetAttribute("LockedUntil", lockedUntil)
	local locked = lockedUntil > Clock.now()
	for _, wall in plot.barrier do
		wall.Transparency = if locked then 0.35 else 1
	end
end

-- ===== Dinos =====

local function labelFor(dino: Types.DinoRecord, stage: number): string
	local species = DinoData.get(dino.species)
	local name = if species then species.name else dino.species
	local mutation = MutationData.get(dino.mutation)
	local prefix = if mutation then mutation.emoji .. " " .. mutation.name .. " " else ""
	return `{prefix}{name} • {Growth.stageName(stage)}`
end

local function buildDino(
	player: Player,
	plot: World.PlotInfo,
	dino: Types.DinoRecord,
	stage: number,
	home: number
): Model
	local model = DinoModel.build(dino.species, stage, dino.mutation, "World")
	model.Name = "Dino_" .. dino.id
	model:SetAttribute("DinoId", dino.id)
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("Species", dino.species)
	model:SetAttribute("Stage", stage)
	local spot = plot.homeSpots[math.clamp(home, 1, #plot.homeSpots)]
	model:SetAttribute("Home", spot)
	model:PivotTo(spot)

	local root = model.PrimaryPart :: BasePart
	local promptAttachment = root:FindFirstChild("PromptAttachment")
	local height = model:GetAttribute("Height")
	local reach = 8 + (if typeof(height) == "number" then height * 0.6 else 0)
	Prompts.create(promptAttachment or root, {
		action = "OpenUI",
		openUI = "Dino",
		text = "View",
		objectText = (DinoData.get(dino.species) :: DinoData.Species).name,
		audience = "Owner",
		ownerId = player.UserId,
		key = dino.id,
		distance = reach,
	})

	local labelAttachment = root:FindFirstChild("LabelAttachment")
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(170, 30)
	gui.MaxDistance = 40
	gui.LightInfluence = 0
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.3
	text.Text = labelFor(dino, stage)
	text.Parent = gui
	gui.Parent = labelAttachment or root

	CollectionService:AddTag(model, DinoModel.TAG)
	model.Parent = plot.dinoFolder
	return model
end

function Plots.syncDinos(player: Player)
	local plot = plotFor(player)
	local profile = Data.get(player)
	local render = renders[player]
	if not plot or not profile or not render then
		return
	end
	local now = Clock.now()
	local seen: { [string]: boolean } = {}
	for home, dino in profile.dinos do
		seen[dino.id] = true
		local stage = Stats.dinoStage(dino, now)
		local mutation = dino.mutation or ""
		local existing: DinoRender? = render.dinos[dino.id]
		if existing and (existing.stage ~= stage or existing.mutation ~= mutation) then
			existing.model:Destroy()
			existing = nil
		end
		if not existing then
			local model = buildDino(player, plot, dino, stage, home)
			render.dinos[dino.id] =
				{ model = model, stage = stage, mutation = mutation, home = home }
		elseif existing.home ~= home then
			local spot = plot.homeSpots[math.clamp(home, 1, #plot.homeSpots)]
			existing.model:SetAttribute("Home", spot)
			existing.model:PivotTo(spot)
			existing.home = home
		end
	end
	for id, entry in render.dinos do
		if not seen[id] then
			entry.model:Destroy()
			render.dinos[id] = nil
		end
	end
end

function Plots.dinoModel(player: Player, dinoId: string): Model?
	local render = renders[player]
	local entry = render and render.dinos[dinoId]
	return if entry then entry.model else nil
end

-- ===== Incubators =====

local function eggLook(egg: Types.IncubatorEgg): EggModel.Look
	if egg.kind == "shop" and egg.eggType and EggData.get(egg.eggType) then
		return EggModel.lookForShopEgg(egg.eggType)
	elseif egg.kind == "gift" then
		return EggModel.giftLook()
	elseif egg.species and DinoData.get(egg.species) then
		return EggModel.lookForSpecies(egg.species)
	end
	return EggModel.giftLook()
end

local function eggTitle(egg: Types.IncubatorEgg): string
	if egg.kind == "shop" and egg.eggType then
		local data = EggData.get(egg.eggType)
		return if data then data.name else "Egg"
	elseif egg.kind == "gift" then
		return "Gift Egg"
	elseif egg.kind == "starter" then
		return "Starter Egg"
	end
	local species = egg.species and DinoData.get(egg.species)
	return if species then species.name .. " Egg" else "Egg"
end

local function buildIncubatorEgg(
	player: Player,
	plot: World.PlotInfo,
	slot: string,
	egg: Types.IncubatorEgg
): Model
	local pedestal = plot.incubators[tonumber(slot) :: number]
	local model = EggModel.build(eggLook(egg), 3.4)
	model.Name = "IncubatorEgg" .. slot
	model:SetAttribute("EggId", egg.id)
	model:SetAttribute("Slot", slot)
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("HatchAt", egg.hatchAt)
	model:SetAttribute("Title", eggTitle(egg))
	model:PivotTo(
		CFrame.new(pedestal.CFrame.Position + Vector3.new(0, pedestal.Size.X / 2 + 0.1, 0))
	)

	local root = model.PrimaryPart :: BasePart
	local promptAttachment = Instance.new("Attachment")
	promptAttachment.Position = Vector3.new(0, 1.8, 0)
	promptAttachment.Parent = root
	Prompts.create(promptAttachment, {
		action = "IncubatorTap",
		text = "Warm",
		objectText = eggTitle(egg),
		audience = "Owner",
		ownerId = player.UserId,
		key = slot,
		distance = 10,
	})
	Prompts.create(promptAttachment, {
		action = "InstantHatch",
		text = "⚡ Instant Hatch",
		audience = "Owner",
		ownerId = player.UserId,
		key = slot,
		keyCode = Enum.KeyCode.F,
		distance = 10,
		hideInTutorial = true,
	})

	local gui = Instance.new("BillboardGui")
	gui.Name = "Timer"
	gui.Size = UDim2.fromOffset(150, 46)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5.2, 0)
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.2
	text.Text = ""
	text.Parent = gui
	gui.Parent = root

	CollectionService:AddTag(model, Plots.EGG_TAG)
	model.Parent = plot.eggFolder
	return model
end

function Plots.syncIncubators(player: Player)
	local plot = plotFor(player)
	local profile = Data.get(player)
	local render = renders[player]
	if not plot or not profile or not render then
		return
	end
	local maxIncubators = Stats.maxIncubators(profile)
	for slot = 1, Config.MAX_INCUBATORS do
		local unlocked = slot <= maxIncubators
		plot.incubatorLocks[slot].Enabled = not unlocked
		plot.incubatorRings[slot].Transparency = if unlocked then 0 else 0.8
		local key = tostring(slot)
		local egg = profile.incubators[key]
		local existing: EggRender? = render.eggs[key]
		if existing and (not egg or existing.id ~= egg.id) then
			existing.model:Destroy()
			render.eggs[key] = nil
			existing = nil
		end
		if egg and not existing then
			render.eggs[key] = { id = egg.id, model = buildIncubatorEgg(player, plot, key, egg) }
		elseif egg and existing then
			existing.model:SetAttribute("HatchAt", egg.hatchAt)
		end
	end
end

function Plots.incubatorPosition(player: Player, slot: string): Vector3?
	local plot = plotFor(player)
	local index = tonumber(slot)
	if not plot or not index or not plot.incubators[index] then
		return nil
	end
	return plot.incubators[index].CFrame.Position
end

-- Brief sparkle flag the client shows when a friend is warming the egg.
function Plots.flagFriendWarm(player: Player, slot: string)
	local render = renders[player]
	local entry = render and render.eggs[slot]
	if entry then
		entry.model:SetAttribute("FriendWarmAt", Clock.now())
	end
end

-- ===== Laid-egg tray =====

local function buildTrayEgg(
	player: Player,
	plot: World.PlotInfo,
	egg: Types.TrayEgg,
	spot: number
): Model
	local model = EggModel.build(EggModel.lookForSpecies(egg.species), 2.2)
	model.Name = "TrayEgg_" .. egg.id
	model:SetAttribute("EggId", egg.id)
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("Species", egg.species)
	model:PivotTo(plot.traySpots[math.clamp(spot, 1, #plot.traySpots)])
	local root = model.PrimaryPart :: BasePart
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, 1.2, 0)
	attachment.Parent = root
	local species = DinoData.get(egg.species)
	local name = if species then species.name .. " Egg" else "Egg"
	Prompts.create(attachment, {
		action = "TrayIncubate",
		text = "Incubate",
		objectText = name,
		audience = "Owner",
		ownerId = player.UserId,
		plotIndex = plot.index,
		key = egg.id,
		distance = 8,
	})
	Prompts.create(attachment, {
		action = "TraySell",
		text = "Sell",
		objectText = name,
		audience = "Owner",
		ownerId = player.UserId,
		plotIndex = plot.index,
		key = egg.id,
		keyCode = Enum.KeyCode.F,
		distance = 8,
	})
	Prompts.create(attachment, {
		action = "Steal",
		text = "Steal!",
		objectText = name,
		audience = "Others",
		ownerId = player.UserId,
		plotIndex = plot.index,
		key = egg.id,
		hold = Config.STEAL_HOLD_SECONDS,
		distance = 8,
		nightOnly = true,
	})
	model.Parent = plot.trayFolder
	return model
end

function Plots.syncTray(player: Player)
	local plot = plotFor(player)
	local profile = Data.get(player)
	local render = renders[player]
	if not plot or not profile or not render then
		return
	end
	local seen: { [string]: boolean } = {}
	for spot, egg in profile.tray do
		if render.hiddenTray[egg.id] then
			continue
		end
		seen[egg.id] = true
		local existing = render.tray[egg.id]
		if not existing then
			render.tray[egg.id] = buildTrayEgg(player, plot, egg, spot)
		else
			existing:PivotTo(plot.traySpots[math.clamp(spot, 1, #plot.traySpots)])
		end
	end
	for id, model in render.tray do
		if not seen[id] then
			model:Destroy()
			render.tray[id] = nil
		end
	end
end

-- Hide a tray egg while a thief is carrying it (it stays in the owner's
-- profile until the thief actually gets home with it).
function Plots.setTrayEggHidden(player: Player, eggId: string, hidden: boolean)
	local render = renders[player]
	if not render then
		return
	end
	if hidden then
		render.hiddenTray[eggId] = true
	else
		render.hiddenTray[eggId] = nil
	end
	Plots.syncTray(player)
end

function Plots.isTrayEggHidden(player: Player, eggId: string): boolean
	local render = renders[player]
	if not render then
		return false
	end
	return render.hiddenTray[eggId] == true
end

function Plots.trayPosition(player: Player): Vector3?
	local plot = plotFor(player)
	if not plot then
		return nil
	end
	return plot.traySpots[1].Position
end

function Plots.renderAll(player: Player)
	Plots.syncDinos(player)
	Plots.syncIncubators(player)
	Plots.syncTray(player)
	Plots.updateSign(player)
	local session = Sessions.get(player)
	if session then
		Plots.setBarrier(player, session.lockUntil)
	end
end

return Plots
