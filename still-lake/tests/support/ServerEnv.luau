--!nocheck
-- A stand-in Roblox server: fake services plus the real server systems,
-- loaded through the Loader. Used by the integration test and the 3D preview
-- exporter. Only one environment can exist per Lune process (modules are
-- cached). Run from the still-lake folder.
--
-- Time is fake: env.advance(seconds) moves the server clock forward and runs
-- any task.delay callbacks that fall due, so tests never really wait.

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local taskLib = require("@lune/task")
local Loader = require("../loader")
local Common = require("./Common")

local Instance = roblox.Instance

local ServerEnv = {}

-- start() functions that only do setup (the others loop forever).
local SETUP_STARTS = { "Lifecycle", "Stones" }

export type Options = {
	configure: ((Config: any) -> ())?,
	now: number?,
}

function ServerEnv.new(options: Options?)
	local env = {}
	local opts = options or {}
	local now = opts.now or 1_800_000_000
	local clock = 1000 -- os.clock() stand-in

	-- ===== Fake time =====
	local delayed = {}
	local function fakeDelay(seconds, fn, ...)
		local item = { at = clock + (seconds or 0), fn = fn, args = table.pack(...) }
		table.insert(delayed, item)
		return item
	end
	function env.now()
		return now
	end
	function env.advance(seconds: number)
		local target = clock + seconds
		while true do
			table.sort(delayed, function(a, b)
				return a.at < b.at
			end)
			local first = delayed[1]
			if not first or first.at > target then
				break
			end
			table.remove(delayed, 1)
			now += first.at - clock
			clock = first.at
			first.fn(table.unpack(first.args, 1, first.args.n))
		end
		now += target - clock
		clock = target
	end
	function env.pendingDelays()
		return #delayed
	end

	local dataModel = Instance.new("DataModel")
	local workspaceService = dataModel:GetService("Workspace")
	local lighting = dataModel:GetService("Lighting")
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Parent = lighting
	local playersFolder = dataModel:GetService("Players")
	env.workspace = workspaceService
	env.lighting = lighting

	Common.implementEngine(function()
		return now
	end)

	-- Events Lune doesn't have: one fake signal per instance, which tests fire.
	-- (Lune hands out a new wrapper for an instance on every access, so each
	-- instance is tagged with an id attribute to find its signals again.)
	local signals = {}
	local nextSignalId = 0
	local function eventStub(className, eventName)
		roblox.implementProperty(className, eventName, function(instance)
			local id = instance:GetAttribute("TestSignalId")
			if not id then
				nextSignalId += 1
				id = nextSignalId
				instance:SetAttribute("TestSignalId", id)
			end
			local perInstance = signals[id]
			if not perInstance then
				perInstance = {}
				signals[id] = perInstance
			end
			local signal = perInstance[eventName]
			if not signal then
				signal = Common.signal()
				perInstance[eventName] = signal
			end
			return signal
		end)
	end
	eventStub("ProximityPrompt", "Triggered")
	eventStub("Player", "CharacterAdded")
	eventStub("Player", "CharacterAppearanceLoaded")
	function env.signal(instance, eventName)
		return instance[eventName]
	end
	-- Everything already exists in the fake world, so nothing needs waiting for.
	roblox.implementMethod("Model", "WaitForChild", function(model, name)
		return model:FindFirstChild(name)
	end)
	roblox.implementMethod("Player", "Kick", function(_, message)
		error("kicked: " .. tostring(message))
	end)

	local tags = {}
	env.tags = tags
	local collectionService = {
		AddTag = function(_, instance, tag)
			tags[tag] = tags[tag] or {}
			table.insert(tags[tag], instance)
		end,
		GetTagged = function(_, tag)
			return tags[tag] or {}
		end,
	}

	local playerList = {}
	env.players = playerList
	local players = {
		PlayerAdded = Common.signal(),
		PlayerRemoving = Common.signal(),
		GetPlayers = function()
			return playerList
		end,
		GetPlayerByUserId = function(_, id)
			for _, p in playerList do
				if p.UserId == id then
					return p
				end
			end
			return nil
		end,
	}
	env.playersService = players

	local services = {
		ReplicatedStorage = Common.replicatedStorage(Loader, {}),
		Workspace = workspaceService,
		Lighting = lighting,
		CollectionService = collectionService,
		Players = players,
		RunService = {
			IsStudio = function()
				return true
			end,
			IsServer = function()
				return true
			end,
		},
		DataStoreService = {
			GetDataStore = function()
				error("StudioAccessToApisNotAllowed")
			end,
			GetOrderedDataStore = function()
				error("StudioAccessToApisNotAllowed")
			end,
		},
		UserService = {
			GetUserInfosByUserIdsAsync = function()
				return {}
			end,
		},
	}
	env.services = services

	local game = {
		JobId = "",
		CreatorId = 0,
		CreatorType = roblox.Enum.CreatorType.User,
		GetService = function(_, name)
			local service = services[name]
			assert(service, "no stand-in for service " .. name)
			return service
		end,
		BindToClose = function() end,
	}

	Common.installGlobals(Loader, game, workspaceService)
	Loader.globals.task = {
		wait = taskLib.wait,
		spawn = taskLib.spawn,
		defer = taskLib.defer,
		cancel = taskLib.cancel,
		delay = fakeDelay,
	}
	Loader.globals.os = setmetatable({
		clock = function()
			return clock
		end,
	}, { __index = os })

	-- Net stand-in: record handlers and outgoing messages.
	local handlers = {}
	local outbox = {}
	env.handlers = handlers
	env.outbox = outbox
	Loader.stub("src/shared/Net", {
		serverInit = function() end,
		on = function(name, _rate, _burst, handler)
			handlers[name] = handler
		end,
		fire = function(player, name, ...)
			table.insert(outbox, { player = player, name = name, args = table.pack(...) })
		end,
		fireAll = function(name, ...)
			table.insert(outbox, { player = "all", name = name, args = table.pack(...) })
		end,
		send = function() end,
		listen = function() end,
	})

	-- ===== Load the real server =====
	env.Config = Loader.load("src/shared/Config")
	if opts.configure then
		opts.configure(env.Config)
	end
	local names = {}
	for _, file in fs.readDir("src/server/Systems") do
		local name = string.match(file, "^(.+)%.luau$")
		if name then
			table.insert(names, name)
		end
	end
	table.sort(names)
	local S = {}
	for _, name in names do
		S[name] = Loader.load("src/server/Systems/" .. name)
	end
	for _, name in names do
		if S[name].init then
			S[name].init()
		end
	end
	for _, name in SETUP_STARTS do
		S[name].start()
	end
	env.S = S
	env.names = names

	-- ===== Helpers =====
	local nextUserId = 100
	function env.makeCharacter(player, position)
		local character = Instance.new("Model")
		character.Name = player.Name
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = roblox.Vector3.new(2, 2, 1)
		root.CFrame = roblox.CFrame.new(position or roblox.Vector3.new(0, 3, 140))
		root.Parent = character
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Size = roblox.Vector3.new(1, 1, 1)
		head.Parent = character
		local hand = Instance.new("Part")
		hand.Name = "RightHand"
		hand.Size = roblox.Vector3.new(0.6, 0.6, 0.6)
		hand.Parent = character
		local humanoid = Instance.new("Humanoid")
		humanoid.Health = 100
		humanoid.Parent = character
		character.Parent = workspaceService
		player.Character = character
		return character
	end

	function env.makePlayer(name: string)
		nextUserId += 1
		local player = Instance.new("Player")
		player.Name = name
		player.DisplayName = name
		player.UserId = nextUserId
		player.Parent = playersFolder
		env.makeCharacter(player)
		table.insert(playerList, player)
		return player
	end

	-- Joins through the real Lifecycle (saving is in memory, so it's instant).
	function env.join(player)
		players.PlayerAdded:Fire(player)
		local session = S.Sessions.getReady(player)
		assert(session, "joined")
		return session
	end

	function env.leave(player)
		players.PlayerRemoving:Fire(player)
		player.Parent = nil
		local index = table.find(playerList, player)
		if index then
			table.remove(playerList, index)
		end
	end

	function env.moveTo(player, position)
		player.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(position)
	end

	function env.profileOf(player)
		return S.Data.get(player)
	end

	-- Sends a client event to the server the way a client would.
	function env.send(player, name, ...)
		local handler = handlers[name]
		assert(handler, "no handler for " .. name)
		handler(player, ...)
	end

	function env.messages(player, name)
		local list = {}
		for _, message in outbox do
			if (message.player == player or message.player == "all") and message.name == name then
				table.insert(list, message)
			end
		end
		return list
	end

	function env.lastMessage(player, name)
		local list = env.messages(player, name)
		return list[#list]
	end

	function env.clearOutbox()
		table.clear(outbox)
	end

	return env
end

return ServerEnv
