--!nocheck
-- A stand-in Roblox client: fake services + every real client controller,
-- loaded through the Loader. Used by the client smoke test and the UI preview
-- exporter. Tweens jump straight to their end values so screens can be captured.

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local taskLib = require("@lune/task")
local Loader = require("../loader")
local Common = require("./Common")

local Instance = roblox.Instance

local ClientEnv = {}

-- Events the client code connects to, stubbed onto the real classes.
local EVENTS = {
	GuiButton = { "MouseButton1Down", "MouseButton1Up", "MouseEnter", "MouseLeave", "Activated" },
	TextButton = { "MouseButton1Down", "MouseButton1Up", "MouseEnter", "MouseLeave", "Activated" },
	ImageButton = { "MouseButton1Down", "MouseButton1Up", "MouseEnter", "MouseLeave", "Activated" },
	TextBox = { "FocusLost", "Focused" },
	NumberValue = { "Changed" },
	CFrameValue = { "Changed" },
	ProximityPrompt = { "Triggered" },
	Player = { "CharacterAdded", "CharacterRemoving" },
}

local signals: { [string]: any } = {}

local function eventFor(instance, eventName)
	local key = eventName .. ":" .. tostring(instance)
	local existing = signals[key]
	if existing then
		return existing
	end
	local s = Common.signal()
	signals[key] = s
	return s
end

export type Options = { now: number?, start: boolean? }

function ClientEnv.new(options: Options?)
	local env = {}
	local now = (options and options.now) or 1_800_000_000
	function env.now()
		return now
	end
	function env.setNow(value: number)
		now = value
	end

	for className, events in EVENTS do
		for _, eventName in events do
			pcall(function()
				roblox.implementProperty(className, eventName, function(instance)
					return eventFor(instance, eventName)
				end)
			end)
		end
	end
	for _, className in
		{
			"Model",
			"Part",
			"Frame",
			"ViewportFrame",
			"TextLabel",
			"TextButton",
			"Folder",
			"ImageLabel",
		}
	do
		roblox.implementProperty(className, "Destroying", function(instance)
			return eventFor(instance, "Destroying")
		end)
	end

	local dataModel = Instance.new("DataModel")
	local workspaceService = dataModel:GetService("Workspace")
	local lighting = dataModel:GetService("Lighting")
	env.workspace = workspaceService
	env.lighting = lighting

	Common.implementEngine(function()
		return now
	end)

	-- Give the camera a viewport size (Lune has no renderer to report one).
	local camera = workspaceService.CurrentCamera or Instance.new("Camera")
	env.camera = camera
	function env.setViewport(width: number, height: number)
		camera.ViewportSize = roblox.Vector2.new(width, height)
		for _, fn in env.viewportListeners do
			fn()
		end
	end
	env.viewportListeners = {}
	roblox.implementMethod("Camera", "GetPropertyChangedSignal", function()
		return {
			Connect = function(_, fn)
				table.insert(env.viewportListeners, fn)
				return { Disconnect = function() end }
			end,
		}
	end)
	camera.ViewportSize = roblox.Vector2.new(1280, 720)

	roblox.implementMethod("Player", "WaitForChild", function(self, name)
		return self:FindFirstChild(name)
	end)
	-- Lune can't hook SetAttribute, so tests fire attribute changes with
	-- env.attributeChanged(instance, name) after setting the attribute.
	local attributeSignals = {}
	roblox.implementMethod("Player", "GetAttributeChangedSignal", function(self, name)
		attributeSignals[self] = attributeSignals[self] or {}
		attributeSignals[self][name] = attributeSignals[self][name] or Common.signal()
		return attributeSignals[self][name]
	end)
	function env.attributeChanged(instance, name)
		local signal = attributeSignals[instance] and attributeSignals[instance][name]
		if signal then
			signal:Fire()
		end
	end

	local localPlayer = Instance.new("Player")
	localPlayer.Name = "Tester"
	localPlayer.DisplayName = "Tester"
	localPlayer.UserId = 7
	local playerGui = Instance.new("PlayerGui")
	playerGui.Parent = localPlayer
	env.localPlayer = localPlayer
	env.playerGui = playerGui

	local tweens = {}
	env.tweens = tweens
	local tweenService = {
		Create = function(_, instance, _info, goals)
			local tween = {
				Completed = Common.signal(),
			}
			function tween.Play()
				for key, value in goals do
					pcall(function()
						instance[key] = value
					end)
				end
				table.insert(tweens, instance)
			end
			function tween.Cancel() end
			function tween.Pause() end
			return tween
		end,
	}

	local tagged = {}
	env.tagged = tagged
	local otherPlayers = {}
	env.otherPlayers = otherPlayers
	local services = {
		Players = {
			LocalPlayer = localPlayer,
			PlayerAdded = Common.signal(),
			PlayerRemoving = Common.signal(),
			GetPlayers = function()
				local list = { localPlayer }
				for _, p in otherPlayers do
					table.insert(list, p)
				end
				return list
			end,
			GetPlayerByUserId = function(_, id)
				if id == localPlayer.UserId then
					return localPlayer
				end
				for _, p in otherPlayers do
					if p.UserId == id then
						return p
					end
				end
				return nil
			end,
		},
		Workspace = workspaceService,
		Lighting = lighting,
		TweenService = tweenService,
		RunService = {
			Heartbeat = Common.signal(),
			RenderStepped = Common.signal(),
			IsStudio = function()
				return true
			end,
			IsClient = function()
				return true
			end,
		},
		CollectionService = {
			GetTagged = function(_, tag)
				return tagged[tag] or {}
			end,
			GetInstanceAddedSignal = function()
				return Common.signal()
			end,
			GetInstanceRemovedSignal = function()
				return Common.signal()
			end,
			AddTag = function(_, instance, tag)
				tagged[tag] = tagged[tag] or {}
				table.insert(tagged[tag], instance)
			end,
			HasTag = function(_, instance, tag)
				return table.find(tagged[tag] or {}, instance) ~= nil
			end,
		},
		ProximityPromptService = { PromptTriggered = Common.signal() },
		AdService = {
			GetAdAvailabilityNowAsync = function()
				return { AdAvailabilityResult = roblox.Enum.AdAvailabilityResult.NoFill }
			end,
			RegisterAdOpportunityAsync = function() end,
		},
		SocialService = {
			CanSendGameInviteAsync = function()
				return true
			end,
			PromptGameInvite = function() end,
		},
		MarketplaceService = {
			GetProductInfoAsync = function()
				return { PriceInRobux = 99 }
			end,
		},
		ExperienceNotificationService = {
			CanPromptOptInAsync = function()
				return false
			end,
			PromptOptIn = function() end,
		},
		SoundService = dataModel:GetService("SoundService"),
		MaterialService = dataModel:GetService("MaterialService"),
		UserInputService = {
			TouchEnabled = false,
			KeyboardEnabled = true,
			InputBegan = Common.signal(),
		},
		GuiService = {
			GetGuiInset = function()
				return roblox.Vector2.new(0, 58), roblox.Vector2.new(0, 0)
			end,
		},
	}
	env.services = services

	local replicatedAttributes = { RaidsEnabled = true }
	env.replicatedAttributes = replicatedAttributes
	services.ReplicatedStorage = Common.replicatedStorage(Loader, replicatedAttributes)

	local game = {
		GetService = function(_, name)
			local service = services[name]
			assert(service, "no stand-in for service " .. name)
			return service
		end,
	}
	Common.installGlobals(Loader, game, workspaceService)

	local listeners = {}
	local sent = {}
	env.listeners = listeners
	env.sent = sent
	Loader.stub("src/shared/Net", {
		listen = function(name, handler)
			listeners[name] = handler
		end,
		send = function(name, ...)
			table.insert(sent, { name = name, args = { ... } })
		end,
	})

	-- A minimal plot so the tutorial can find its pad, tray and floor.
	local plots = Instance.new("Folder")
	plots.Name = "Plots"
	plots.Parent = workspaceService
	local plot = Instance.new("Model")
	plot.Name = "Plot1"
	plot.Parent = plots
	for _, name in { "Floor", "Tray", "CoinPad" } do
		local part = Instance.new("Part")
		part.Name = name
		part.Size = roblox.Vector3.new(4, 1, 4)
		part.CFrame = roblox.CFrame.new(math.random(-20, 20), 1, 100)
		part.Parent = plot
	end

	-- Load and initialize every controller, like the real client entry point.
	local names = {}
	for _, file in fs.readDir("src/client/Controllers") do
		local name = string.match(file, "^(.+)%.luau$")
		if name then
			table.insert(names, name)
		end
	end
	table.sort(names)
	env.controllerNames = names
	local C = {}
	for _, name in names do
		C[name] = Loader.load("src/client/Controllers/" .. name)
	end
	for _, name in names do
		if C[name].init then
			C[name].init()
		end
	end
	env.C = C
	env.Panels = Loader.load("src/client/Lib/Panels")
	-- Run the controllers' start loops too (they never return, so the caller
	-- must end with process.exit).
	if options and options.start then
		for _, name in names do
			if C[name].start then
				taskLib.spawn(C[name].start)
			end
		end
	end

	-- A realistic state snapshot; override fields per test.
	function env.snapshot(overrides)
		local base = {
			coins = 12345,
			pendingCoins = 50,
			incomePerSecond = 12.5,
			multiplier = 1.4,
			dinos = {
				{
					id = "1",
					species = "Raptor",
					mutation = nil,
					bornAt = now - 4000,
					lastLaidAt = 0,
				},
				{
					id = "2",
					species = "TRex",
					mutation = "Rainbow",
					bornAt = now - 100,
					lastLaidAt = 0,
				},
				{
					id = "3",
					species = "Triceratops",
					mutation = "Frost",
					bornAt = now - 90000,
					lastLaidAt = 0,
				},
			},
			incubators = {
				["1"] = {
					id = "3",
					kind = "shop",
					eggType = "Jungle",
					placedAt = now,
					hatchAt = now + 20,
				},
			},
			tray = { { id = "4", species = "Raptor", laidAt = now } },
			dex = {
				Raptor = { Normal = true },
				TRex = { Rainbow = true },
				Triceratops = { Frost = true },
			},
			upgrades = { slots = 1, incubators = 0 },
			boosts = { luckUntil = now + 300, coinsUntil = now + 100 },
			instantHatchTokens = 0,
			streak = { count = 2, lastDay = math.floor(now / 86400) - 1 },
			clubClaimDay = 0,
			tutorial = 99,
			starterPackBought = false,
			shopBought = { restock = 0, bought = {} },
			likes = 3,
			passes = { RideDinos = true },
			subscribed = false,
			restricted = false,
			plotIndex = 1,
			maxSlots = 9,
			maxIncubators = 3,
			lockUntil = 0,
			lockCooldownUntil = 0,
			shieldUntil = now + 3600,
			friendsHere = 1,
			isDev = true,
			raidsEnabled = true,
			riding = nil,
			carrying = false,
			quests = {
				day = math.floor(now / 86400),
				progress = {},
				claimed = {},
				bonusClaimed = false,
			},
			dexClaimed = {},
			settings = { music = true, sfx = true },
			buddy = nil,
		}
		for k, v in overrides or {} do
			base[k] = v
		end
		return base
	end

	function env.pushState(overrides)
		local snapshot = env.snapshot(overrides)
		listeners.State(snapshot)
		return snapshot
	end

	return env
end

return ClientEnv
