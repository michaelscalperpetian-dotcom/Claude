--!nocheck
-- Shared pieces of the fake Roblox engine used by the test environments.

local roblox = require("@lune/roblox")
local taskLib = require("@lune/task")

local Common = {}

function Common.signal()
	local s = { handlers = {} }
	function s:Connect(fn)
		table.insert(self.handlers, fn)
		local handlers = self.handlers
		return {
			Disconnect = function()
				local index = table.find(handlers, fn)
				if index then
					table.remove(handlers, index)
				end
			end,
		}
	end
	function s:Once(fn)
		local connection
		connection = self:Connect(function(...)
			connection.Disconnect()
			fn(...)
		end)
		return connection
	end
	function s:Fire(...)
		for _, handler in table.clone(self.handlers) do
			handler(...)
		end
	end
	function s:Wait() end
	return s
end

local engineInstalled = false

-- Methods Lune doesn't implement but the game uses.
function Common.implementEngine(getNow: () -> number)
	if engineInstalled then
		return
	end
	engineInstalled = true

	-- Nothing to hit in the fake world (callers fall back to defaults).
	roblox.implementMethod("Workspace", "Raycast", function()
		return nil
	end)
	roblox.implementMethod("Workspace", "GetServerTimeNow", function()
		return getNow()
	end)

	local function pivotOf(model)
		if model.PrimaryPart then
			return model.PrimaryPart.CFrame
		end
		local hrp = model:FindFirstChild("HumanoidRootPart")
		if hrp then
			return hrp.CFrame
		end
		return roblox.CFrame.new()
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
	roblox.implementMethod("ParticleEmitter", "Emit", function() end)
	roblox.implementMethod("Sound", "Play", function() end)
	roblox.implementMethod("Sound", "Stop", function() end)
end

-- ReplicatedStorage stand-in: `.Shared` maps to src/shared, attributes work.
function Common.replicatedStorage(Loader, attributes: { [string]: any })
	return setmetatable({}, {
		__index = function(_, key)
			if key == "Shared" then
				return Loader.path("src/shared")
			elseif key == "GetAttribute" then
				return function(_, name)
					return attributes[name]
				end
			elseif key == "SetAttribute" then
				return function(_, name, value)
					attributes[name] = value
				end
			elseif key == "GetAttributeChangedSignal" then
				return function()
					return Common.signal()
				end
			end
			return nil
		end,
	})
end

function Common.randomStub()
	return {
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
end

-- Lune's CFrame.lookAt mirrors the Z axis (lookAt(origin, -Z) faces +Z), unlike
-- Roblox. Game code relies on Roblox's behaviour, so loaded modules get this
-- CFrame table with a corrected lookAt; everything else is Lune's.
local function lookAt(at, target, up)
	local look = target - at
	if look.Magnitude < 1e-9 then
		return roblox.CFrame.new(at)
	end
	look = look.Unit
	local right = look:Cross(up or roblox.Vector3.new(0, 1, 0))
	if right.Magnitude < 1e-6 then
		right = look:Cross(roblox.Vector3.new(0, 0, 1))
	end
	right = right.Unit
	local newUp = right:Cross(look).Unit
	return roblox.CFrame.fromMatrix(at, right, newUp, -look)
end
Common.CFrame = setmetatable({ lookAt = lookAt }, { __index = roblox.CFrame })

-- Roblox datatypes + engine globals for modules loaded through the Loader.
function Common.installGlobals(Loader, game, workspaceService)
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
			"Rect",
		}
	do
		Loader.globals[name] = (roblox :: any)[name]
	end
	Loader.globals.CFrame = Common.CFrame
	Loader.globals.RaycastParams = {
		new = function()
			return { FilterDescendantsInstances = {} }
		end,
	}
	Loader.globals.TweenInfo = {
		new = function(...)
			return { ... }
		end,
	}
	Loader.globals.Instance = roblox.Instance
	Loader.globals.game = game
	Loader.globals.workspace = workspaceService
	Loader.globals.task = taskLib
	Loader.globals.Random = Common.randomStub()
	Loader.globals.warn = function(...)
		print("[warn]", ...)
	end
end

return Common
