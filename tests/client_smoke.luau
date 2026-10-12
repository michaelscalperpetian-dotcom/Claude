--!nocheck
-- Client smoke test: builds every HUD element and panel with real Roblox GUI
-- classes (Lune validates every property name), feeds in a state snapshot,
-- opens every window, walks the tutorial steps and plays a hatch reveal.
-- Run with: lune run tests/client_smoke

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local taskLib = require("@lune/task")
local Loader = require("./loader")

local Instance = roblox.Instance

local now = 1_800_000_000

local function signal()
	local s = { handlers = {} }
	function s:Connect(fn)
		table.insert(self.handlers, fn)
		return { Disconnect = function() end }
	end
	function s:Fire(...)
		for _, handler in self.handlers do
			handler(...)
		end
	end
	function s:Wait() end
	return s
end

-- Events used by the client code, stubbed onto the real classes.
local EVENTS = {
	TextButton = { "MouseButton1Down", "MouseButton1Up", "MouseLeave", "Activated" },
	NumberValue = { "Changed" },
	CFrameValue = { "Changed" },
	ProximityPrompt = { "Triggered" },
	Player = { "CharacterAdded" },
}
for className, events in EVENTS do
	for _, eventName in events do
		roblox.implementProperty(className, eventName, function(instance)
			local key = "__event_" .. eventName
			local existing = rawget(_G, key .. tostring(instance))
			if existing then
				return existing
			end
			local s = signal()
			rawset(_G, key .. tostring(instance), s)
			return s
		end)
	end
end
for _, className in { "Model", "Part", "Frame", "ViewportFrame", "TextLabel", "Folder" } do
	roblox.implementProperty(className, "Destroying", function()
		return signal()
	end)
end

local dataModel = Instance.new("DataModel")
local workspaceService = dataModel:GetService("Workspace")
local lighting = dataModel:GetService("Lighting")
-- Give the camera a viewport size (Lune has no renderer to report one).
local camera = workspaceService.CurrentCamera or Instance.new("Camera")
camera.ViewportSize = roblox.Vector2.new(1280, 720)
roblox.implementMethod("Camera", "GetPropertyChangedSignal", function()
	return signal()
end)

roblox.implementMethod("Workspace", "GetServerTimeNow", function()
	return now
end)
roblox.implementMethod("ParticleEmitter", "Emit", function() end)
roblox.implementMethod("Player", "WaitForChild", function(self, name)
	return self:FindFirstChild(name)
end)

local function pivotOf(model)
	return if model.PrimaryPart then model.PrimaryPart.CFrame else roblox.CFrame.new()
end
roblox.implementMethod("Model", "GetPivot", pivotOf)
roblox.implementMethod("Model", "PivotTo", function(model, target)
	local delta = target * pivotOf(model):Inverse()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
end)
roblox.implementMethod("Model", "GetBoundingBox", function(model)
	local min = roblox.Vector3.new(math.huge, math.huge, math.huge)
	local max = -min
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local p = d.CFrame.Position
			local half = d.Size / 2
			min = min:Min(p - half)
			max = max:Max(p + half)
		end
	end
	return roblox.CFrame.new((min + max) / 2), max - min
end)

local localPlayer = Instance.new("Player")
localPlayer.Name = "Tester"
localPlayer.UserId = 7
local playerGui = Instance.new("PlayerGui")
playerGui.Parent = localPlayer

local function tweenStub()
	return {
		Play = function() end,
		Cancel = function() end,
		Completed = signal(),
	}
end

local tagged = {}
local services = {
	Players = { LocalPlayer = localPlayer },
	Workspace = workspaceService,
	Lighting = lighting,
	TweenService = {
		Create = function()
			return tweenStub()
		end,
	},
	RunService = {
		Heartbeat = signal(),
		RenderStepped = signal(),
		IsStudio = function()
			return true
		end,
	},
	CollectionService = {
		GetTagged = function(_, tag)
			return tagged[tag] or {}
		end,
		GetInstanceAddedSignal = function()
			return signal()
		end,
		GetInstanceRemovedSignal = function()
			return signal()
		end,
		AddTag = function() end,
	},
	ProximityPromptService = { PromptTriggered = signal() },
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
}

local replicatedAttributes = { RaidsEnabled = true }
services.ReplicatedStorage = setmetatable({}, {
	__index = function(_, key)
		if key == "Shared" then
			return Loader.path("src/shared")
		elseif key == "GetAttribute" then
			return function(_, name)
				return replicatedAttributes[name]
			end
		end
		return nil
	end,
})

local game = {
	GetService = function(_, name)
		local service = services[name]
		assert(service, "no stand-in for service " .. name)
		return service
	end,
}

for _, name in
	{
		"Vector3",
		"Vector2",
		"CFrame",
		"Color3",
		"UDim",
		"UDim2",
		"Enum",
		"NumberSequence",
		"NumberSequenceKeypoint",
		"ColorSequence",
		"ColorSequenceKeypoint",
		"NumberRange",
	}
do
	Loader.globals[name] = (roblox :: any)[name]
end
Loader.globals.TweenInfo = {
	new = function(...)
		return { ... }
	end,
}
Loader.globals.Instance = Instance
Loader.globals.game = game
Loader.globals.workspace = workspaceService
Loader.globals.task = taskLib
Loader.globals.warn = function(...)
	print("[warn]", ...)
end
Loader.globals.Random = {
	new = function()
		return {
			NextNumber = function(_, a, b)
				a = a or 0
				b = b or 1
				return a + math.random() * (b - a)
			end,
			NextInteger = function(_, a, b)
				return math.random(a, b)
			end,
		}
	end,
}

local listeners = {}
local sent = {}
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

-- ===== Run =====

local passed, failed = 0, 0
local function step(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("ok    " .. name)
	else
		failed += 1
		print(`FAIL  {name}\n      {err}`)
	end
end

local CONTROLLERS = {
	"ClientState",
	"DevPanel",
	"DexUI",
	"DinoPanel",
	"Effects",
	"Hud",
	"PromptVisibility",
	"RewardsUI",
	"ShopUI",
	"StoreUI",
	"Toasts",
	"Tutorial",
	"WorldFx",
}
local C = {}
step("every controller loads and initializes", function()
	for _, name in CONTROLLERS do
		C[name] = Loader.load("src/client/Controllers/" .. name)
	end
	for _, name in CONTROLLERS do
		if C[name].init then
			C[name].init()
		end
	end
	assert(playerGui:FindFirstChild("HUD"), "HUD screen")
	assert(playerGui:FindFirstChild("Panels"), "Panels screen")
end)

local function snapshot(overrides)
	local base = {
		coins = 12345,
		pendingCoins = 50,
		incomePerSecond = 12.5,
		multiplier = 1.4,
		dinos = {
			{ id = "1", species = "Raptor", mutation = nil, bornAt = now - 4000, lastLaidAt = 0 },
			{
				id = "2",
				species = "TRex",
				mutation = "Rainbow",
				bornAt = now - 100,
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
		dex = { Raptor = { Normal = true }, TRex = { Rainbow = true } },
		upgrades = { slots = 1, incubators = 0 },
		boosts = { luckUntil = now + 300, coinsUntil = now + 100 },
		instantHatchTokens = 0,
		streak = { count = 2, lastDay = math.floor(now / 86400) - 1 },
		clubClaimDay = 0,
		tutorial = 1,
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
	}
	for k, v in overrides or {} do
		base[k] = v
	end
	return base
end

step("a state snapshot updates the HUD", function()
	listeners.State(snapshot())
	taskLib.wait(0.05)
end)

step("every window opens and renders", function()
	local Panels = Loader.load("src/client/Lib/Panels")
	Panels.open("Shop")
	taskLib.wait(0.05)
	C.ShopUI.showOdds("Crystal")
	taskLib.wait(0.05)
	Panels.open("Store")
	taskLib.wait(0.1)
	Panels.open("Dex")
	taskLib.wait(0.05)
	Panels.open("Rewards")
	taskLib.wait(0.05)
	C.DinoPanel.open("2")
	taskLib.wait(0.05)
	Panels.open("Dev")
	Panels.close()
end)

step("policy-restricted players don't see coin packs or luck", function()
	listeners.State(snapshot({ restricted = true }))
	C.StoreUI.refresh()
	local panels = playerGui:FindFirstChild("Panels")
	local store = panels:FindFirstChild("Store")
	local hiddenCoins, hiddenLuck = false, false
	for _, d in store:GetDescendants() do
		if d.Name == "CoinsSmall" then
			hiddenCoins = d.Visible == false
		elseif d.Name == "LuckyPotion" then
			hiddenLuck = d.Visible == false
		end
	end
	assert(hiddenCoins and hiddenLuck, "random-feeding products hidden")
end)

step("tutorial walks through every step", function()
	for tutorialStep = 1, 6 do
		listeners.State(snapshot({ tutorial = tutorialStep }))
		taskLib.wait(0.05)
	end
	listeners.State(snapshot({ tutorial = 99 }))
	taskLib.wait(0.05)
end)

step("toasts and effects play", function()
	C.Toasts.show("Hello!", "good")
	listeners.Notify("From the server", "rare")
	listeners.Effect("Dex", { species = "Raptor" })
	listeners.Effect("Reward", { day = 1 })
	listeners.Effect("Roar", { position = roblox.Vector3.new(0, 0, 0), big = true })
	listeners.Effect("Mutate", { position = roblox.Vector3.new(0, 0, 0), mutation = "Lava" })
end)

step("hatch reveal plays to the end", function()
	listeners.Effect("Hatch", { species = "TRex", mutation = "Cosmic" })
	taskLib.wait(5)
end)

step("buttons send the right requests", function()
	local hud = playerGui:FindFirstChild("HUD")
	local function click(root, text)
		for _, d in root:GetDescendants() do
			if d:IsA("TextButton") and d.Text == text then
				d.Activated:Fire()
				return true
			end
		end
		return false
	end
	assert(click(hud, "🦖 Roar"), "roar button")
	local found = false
	for _, message in sent do
		if message.name == "Roar" then
			found = true
		end
	end
	assert(found, "Roar sent")
end)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
