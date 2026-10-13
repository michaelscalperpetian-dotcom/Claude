--!nocheck
-- A stand-in Roblox server: fake services + the real server systems loaded
-- through the Loader. Used by the integration test and the 3D preview exporter.
-- Only one environment can exist per Lune process (modules are cached).

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local taskLib = require("@lune/task")
local Loader = require("../loader")
local Common = require("./Common")

local Instance = roblox.Instance

local ServerEnv = {}

-- start() functions that only do setup (most start() loops run forever).
local SETUP_STARTS = { "Social" }

export type Options = {
	configure: ((Config: any) -> ())?,
	now: number?,
}

function ServerEnv.new(options: Options?)
	local env = {}
	local opts = options or {}
	local now = opts.now or 1_800_000_000 -- a Friday, away from the weekly mega storm

	function env.now()
		return now
	end
	function env.advance(seconds: number)
		now += seconds
	end

	local dataModel = Instance.new("DataModel")
	local workspaceService = dataModel:GetService("Workspace")
	local playersFolder = dataModel:GetService("Players")
	env.workspace = workspaceService

	Common.implementEngine(function()
		return now
	end)

	local friendships = {}
	env.friendships = friendships
	-- Touch events never fire under Lune; tests call the handlers directly.
	roblox.implementProperty("Part", "Touched", function()
		return {
			Connect = function()
				return { Disconnect = function() end }
			end,
		}
	end)
	roblox.implementMethod("Player", "IsFriendsWithAsync", function(player, userId)
		return friendships[player.UserId .. ":" .. userId] == true
	end)
	roblox.implementMethod("Player", "Kick", function(_, message)
		error("kicked: " .. tostring(message))
	end)

	local tags = {}
	env.tags = tags
	local collectionService = {
		AddTag = function(_, _instance, tag)
			tags[tag] = (tags[tag] or 0) + 1
		end,
	}

	local replicatedAttributes = {}
	env.replicatedAttributes = replicatedAttributes

	local playerList = {}
	env.players = playerList
	local players = {
		PlayerAdded = Common.signal(),
		PlayerRemoving = Common.signal(),
		UserSubscriptionStatusChanged = Common.signal(),
		CharacterAutoLoads = true,
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
		GetPlayerFromCharacter = function(_, character)
			for _, p in playerList do
				if p.Character == character then
					return p
				end
			end
			return nil
		end,
	}

	local marketplace = {
		PromptGamePassPurchaseFinished = Common.signal(),
		PromptSubscriptionPurchaseFinished = Common.signal(),
		prompts = {},
		PromptProductPurchase = function(self, player, id)
			table.insert(self.prompts, { player = player, id = id })
		end,
		PromptGamePassPurchase = function() end,
		PromptSubscriptionPurchase = function() end,
		UserOwnsGamePassAsync = function()
			return false
		end,
		GetUserSubscriptionStatusAsync = function()
			return { IsSubscribed = false }
		end,
	}
	env.marketplace = marketplace

	local promptService = { PromptTriggered = Common.signal() }
	env.promptService = promptService

	local orderedStores = {}
	env.orderedStores = orderedStores

	local services = {
		ReplicatedStorage = Common.replicatedStorage(Loader, replicatedAttributes),
		Workspace = workspaceService,
		CollectionService = collectionService,
		Players = players,
		MarketplaceService = marketplace,
		ProximityPromptService = promptService,
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
		AnalyticsService = {
			LogOnboardingFunnelStepEvent = function() end,
			LogEconomyEvent = function() end,
			LogCustomEvent = function() end,
		},
		PolicyService = {
			GetPolicyInfoForPlayerAsync = function()
				return { ArePaidRandomItemsRestricted = false, IsPaidItemTradingAllowed = true }
			end,
		},
		AdService = {
			CreateAdRewardFromDevProductId = function()
				return {}
			end,
			ShowRewardedVideoAdAsync = function()
				return roblox.Enum.ShowAdResult.ShowCompleted
			end,
		},
		UserService = {
			GetUserInfosByUserIdsAsync = function()
				return {}
			end,
		},
		-- Hashes "badword" like Roblox's filter would.
		TextService = {
			FilterStringAsync = function(_, text)
				return {
					GetNonChatStringForBroadcastAsync = function()
						return (string.gsub(text, "badword", "#######"))
					end,
				}
			end,
		},
	}
	env.services = services

	local game = {
		JobId = "",
		PrivateServerId = "",
		GetService = function(_, name)
			local service = services[name]
			assert(service, "no stand-in for service " .. name)
			return service
		end,
		BindToClose = function() end,
	}

	Common.installGlobals(Loader, game, workspaceService)

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
			table.insert(outbox, { player = player, name = name, args = { ... } })
		end,
		fireAll = function(name, ...)
			table.insert(outbox, { player = "all", name = name, args = { ... } })
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
		if S[name] and S[name].start then
			S[name].start()
		end
	end
	env.S = S
	env.Clock = Loader.load("src/shared/Util/Clock")
	env.Cycle = Loader.load("src/shared/Util/Cycle")

	-- ===== Helpers =====
	local nextUserId = 100
	function env.makePlayer(name: string)
		nextUserId += 1
		local player = Instance.new("Player")
		player.Name = name
		player.DisplayName = name
		player.UserId = nextUserId
		player.Parent = playersFolder
		local character = Instance.new("Model")
		character.Name = name
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = roblox.Vector3.new(2, 2, 1)
		root.Parent = character
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Size = roblox.Vector3.new(1, 1, 1)
		head.Parent = character
		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = character
		character.Parent = workspaceService
		player.Character = character
		table.insert(playerList, player)
		return player
	end

	-- Same steps as Lifecycle.onJoin, minus spawning (no engine here).
	function env.join(player)
		local session = S.Sessions.create(player)
		assert(S.Data.load(player), "profile loads")
		assert(S.Plots.assign(player), "gets a plot")
		S.Dinos.applyOffline(player)
		S.Plots.renderAll(player)
		S.Coins.setupLeaderstats(player)
		S.Monetization.onJoin(player)
		S.Social.onJoin(player)
		session.ready = true
		S.Progress.onJoin(player)
		return session
	end

	function env.moveTo(player, position)
		player.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(position)
	end

	function env.profileOf(player)
		return S.Data.get(player)
	end

	function env.findPrompt(container, action, key)
		for _, d in container:GetDescendants() do
			if d:IsA("ProximityPrompt") and d:GetAttribute("Action") == action then
				if key == nil or d:GetAttribute("Key") == key then
					return d
				end
			end
		end
		return nil
	end

	function env.trigger(prompt, player)
		-- The dispatcher rate-limits per action; wait it out like a real player would.
		taskLib.wait(0.15)
		promptService.PromptTriggered:Fire(prompt, player)
	end

	function env.lastMessage(player, name)
		for i = #outbox, 1, -1 do
			local message = outbox[i]
			if (message.player == player or message.player == "all") and message.name == name then
				return message
			end
		end
		return nil
	end

	return env
end

return ServerEnv
