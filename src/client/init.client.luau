--!strict
-- Raise a Dino client entry point. Same two-phase bootstrap as the server.

local Controllers = script:WaitForChild("Controllers")

type Controller = {
	init: (() -> ())?,
	start: (() -> ())?,
}

local loaded: { [string]: Controller } = {}
local order: { string } = {}
for _, child in Controllers:GetChildren() do
	if child:IsA("ModuleScript") then
		loaded[child.Name] = require(child) :: any
		table.insert(order, child.Name)
	end
end
table.sort(order)

for _, name in order do
	local controller = loaded[name]
	if controller.init then
		controller.init()
	end
end

for _, name in order do
	local controller = loaded[name]
	if controller.start then
		task.spawn(controller.start)
	end
end

print("[RaiseADino] client started")
