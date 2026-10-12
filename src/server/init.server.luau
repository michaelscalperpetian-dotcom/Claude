--!strict
-- Raise a Dino server entry point. Two-phase bootstrap: init() every system,
-- then start() every system (see docs: roblox-architecture).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

-- Remotes must exist before any system registers handlers in init().
Net.serverInit()

local Systems = script:WaitForChild("Systems")

type System = {
	init: (() -> ())?,
	start: (() -> ())?,
}

local loaded: { [string]: System } = {}
local order: { string } = {}
for _, child in Systems:GetChildren() do
	if child:IsA("ModuleScript") then
		loaded[child.Name] = require(child) :: any
		table.insert(order, child.Name)
	end
end
table.sort(order)

for _, name in order do
	local system = loaded[name]
	if system.init then
		system.init()
	end
end

for _, name in order do
	local system = loaded[name]
	if system.start then
		task.spawn(system.start)
	end
end

print("[RaiseADino] server started")
