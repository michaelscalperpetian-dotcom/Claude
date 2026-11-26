--!nocheck
-- A stand-in Roblox client: fake services plus every real client controller,
-- loaded through the Loader. Used by the client smoke test and the UI preview
-- exporter. Tweens jump straight to their end values; time is fake
-- (env.advance) and RenderStepped only fires when a test calls env.frame().

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local taskLib = require("@lune/task")
local Loader = require("../loader")
local Common = require("./Common")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3

local ClientEnv = {}

-- Events the client code connects to, stubbed onto the real classes.
local EVENTS = {
	TextButton = {
		"MouseButton1Down",
		"MouseButton1Up",
		"MouseEnter",
		"MouseLeave",
		"Activated",
		"InputBegan",
		"InputEnded",
	},
	Player = { "CharacterAdded" },
	Sound = { "Ended" },
}

export type Options = { now: number?, touch: boolean? }

function ClientEnv.new(options: Options?)
	local env = {}
	local opts = options or {}
	local now = opts.now or 1_800_000_000
	local clock = 500

	-- ===== Fake time =====
	local delayed = {}
	local function fakeDelay(seconds, fn, ...)
		table.insert(delayed, { at = clock + (seconds or 0), fn = fn, args = table.pack(...) })
	end
	function env.clock()
		return clock
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
			clock = first.at
			first.fn(table.unpack(first.args, 1, first.args.n))
		end
		now += target - clock
		clock = target
	end

	-- One instance's fake events, found again through an id attribute (Lune
	-- hands out a fresh wrapper for an instance on every access).
	local signals = {}
	local nextId = 0
	local function eventFor(instance, eventName)
		local id = instance:GetAttribute("TestSignalId")
		if not id then
			nextId += 1
			id = nextId
			instance:SetAttribute("TestSignalId", id)
		end
		signals[id] = signals[id] or {}
		signals[id][eventName] = signals[id][eventName] or Common.signal()
		return signals[id][eventName]
	end
	for className, events in EVENTS do
		for _, eventName in events do
			roblox.implementProperty(className, eventName, function(instance)
				return eventFor(instance, eventName)
			end)
		end
	end
	function env.signal(instance, eventName)
		return eventFor(instance, eventName)
	end

	local dataModel = Instance.new("DataModel")
	local workspaceService = dataModel:GetService("Workspace")
	local lighting = dataModel:GetService("Lighting")
	lighting.ClockTime = 14
	env.workspace = workspaceService
	env.lighting = lighting

	Common.implementEngine(function()
		return now
	end)

	-- The camera (Lune has no renderer, so its size is set by hand).
	local camera = Instance.new("Camera")
	camera.Parent = workspaceService
	pcall(function()
		workspaceService.CurrentCamera = camera
	end)
	env.camera = camera
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
	function env.setViewport(width: number, height: number)
		camera.ViewportSize = roblox.Vector2.new(width, height)
		for _, fn in env.viewportListeners do
			fn()
		end
	end
	function env.lookAt(from: any, target: any)
		camera.CFrame = Common.CFrame.lookAt(from, target)
	end

	roblox.implementMethod("Player", "WaitForChild", function(self, name)
		return self:FindFirstChild(name)
	end)

	local localPlayer = Instance.new("Player")
	localPlayer.Name = "Tester"
	localPlayer.DisplayName = "Tester"
	localPlayer.UserId = 7
	local playerGui = Instance.new("PlayerGui")
	playerGui.Parent = localPlayer
	env.localPlayer = localPlayer
	env.playerGui = playerGui

	-- A character standing on the beach.
	function env.makeCharacter(position)
		local character = Instance.new("Model")
		character.Name = "Tester"
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		root.CFrame = roblox.CFrame.new(position or Vector3.new(0, 3, 116))
		root.Parent = character
		local humanoid = Instance.new("Humanoid")
		humanoid.Health = 100
		humanoid.WalkSpeed = 16
		humanoid.Sit = false
		humanoid.Parent = character
		character.Parent = workspaceService
		localPlayer.Character = character
		return character
	end
	function env.moveTo(position)
		localPlayer.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(position)
	end

	local tweenService = {
		Create = function(_, instance, _info, goals)
			local tween = { Completed = Common.signal() }
			function tween.Play()
				for key, value in goals do
					pcall(function()
						instance[key] = value
					end)
				end
			end
			function tween.Cancel() end
			return tween
		end,
	}

	local tagged = {}
	env.tagged = tagged
	local inputBegan, inputEnded = Common.signal(), Common.signal()
	env.inputBegan, env.inputEnded = inputBegan, inputEnded
	local renderStepped = Common.signal()
	function env.frame(seconds: number?)
		env.advance(seconds or 1 / 60)
		renderStepped:Fire(seconds or 1 / 60)
	end

	local services = {
		Players = {
			LocalPlayer = localPlayer,
			GetPlayers = function()
				return { localPlayer }
			end,
		},
		Workspace = workspaceService,
		Lighting = lighting,
		TweenService = tweenService,
		RunService = {
			RenderStepped = renderStepped,
			Heartbeat = Common.signal(),
			IsStudio = function()
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
			AddTag = function(_, instance, tag)
				tagged[tag] = tagged[tag] or {}
				table.insert(tagged[tag], instance)
			end,
		},
		SoundService = dataModel:GetService("SoundService"),
		UserInputService = {
			TouchEnabled = opts.touch == true,
			KeyboardEnabled = opts.touch ~= true,
			GamepadEnabled = false,
			InputBegan = inputBegan,
			InputEnded = inputEnded,
		},
		GuiService = {
			GetGuiInset = function()
				return roblox.Vector2.new(0, 58), roblox.Vector2.new(0, 0)
			end,
		},
		ReplicatedStorage = Common.replicatedStorage(Loader, {}),
	}
	env.services = services

	local game = {
		GetService = function(_, name)
			local service = services[name]
			assert(service, "no stand-in for service " .. name)
			return service
		end,
	}
	Common.installGlobals(Loader, game, workspaceService)
	Loader.globals.task = {
		wait = function() end, -- loops are driven by the tests, not by waiting
		spawn = taskLib.spawn,
		defer = taskLib.defer,
		delay = fakeDelay,
	}
	Loader.globals.os = setmetatable({
		clock = function()
			return clock
		end,
	}, { __index = os })

	local listeners = {}
	local sent = {}
	env.listeners = listeners
	env.sent = sent
	Loader.stub("src/shared/Net", {
		listen = function(name, handler)
			listeners[name] = handler
		end,
		send = function(name, ...)
			table.insert(sent, { name = name, args = table.pack(...) })
		end,
	})
	function env.lastSent(name)
		for i = #sent, 1, -1 do
			if sent[i].name == name then
				return sent[i]
			end
		end
		return nil
	end

	-- Load and initialize every controller, like the real client entry point
	-- (start() loops that never return are not run; tests call what they need).
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
	-- the start() functions that only hook up per-frame updates
	for _, name in { "Hud", "StoneFx", "ThrowInput" } do
		C[name].start()
	end
	env.C = C

	-- A realistic snapshot; override fields per test.
	function env.snapshot(overrides)
		local base = {
			stones = { pebble = 1, slate = 2, seaglass = 1 },
			equipped = "pebble",
			bestSkips = 12,
			bestDistance = 64.3,
			nightSkips = 0,
			shore = false,
			throws = 40,
			totalSkips = 250,
			perfects = 3,
			goals = { skip1 = true, skip5 = true, skip10 = true, perfect1 = true },
			title = "Splash Artist",
			isDev = true,
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
