--!strict
-- Raise a Dino client entry point. Same two-phase bootstrap as the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Studs = require(ReplicatedStorage.Shared.Visual.Studs)

Studs.apply()

local Controllers = script:WaitForChild("Controllers")

type Controller = {
	init: (() -> ())?,
	start: (() -> ())?,
}

local loaded: { [string]: Controller } = {}
local order: { string } = {}
for _, child in Controllers:GetChildren() do
	if child:IsA("ModuleScript") then
		-- One broken controller must not stop the others from loading.
		local ok, result = pcall(require, child)
		if ok then
			loaded[child.Name] = result :: any
			table.insert(order, child.Name)
		else
			warn(`[RaiseADino] {child.Name} failed to load: {result}`)
		end
	end
end
table.sort(order)

for _, name in order do
	local init = loaded[name].init
	if init then
		local ok, err = pcall(function()
			init()
		end)
		if not ok then
			warn(`[RaiseADino] {name}.init failed: {err}`)
		end
	end
end

for _, name in order do
	local controller = loaded[name]
	if controller.start then
		task.spawn(controller.start)
	end
end

print("[RaiseADino] client started")
