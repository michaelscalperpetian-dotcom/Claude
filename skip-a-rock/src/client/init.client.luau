--!strict
-- Skip a Rock client entry point. Same two-phase start as the server: init()
-- every controller (in name order), then start() each in its own thread.
-- One broken controller must never stop the others.

local Controllers = script:WaitForChild("Controllers")

type Controller = {
	init: (() -> ())?,
	start: (() -> ())?,
}

local loaded: { [string]: Controller } = {}
local order: { string } = {}
for _, child in Controllers:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, result = pcall(require, child)
		if ok then
			loaded[child.Name] = result :: any
			table.insert(order, child.Name)
		else
			warn(`[SkipARock] {child.Name} failed to load: {result}`)
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
			warn(`[SkipARock] {name}.init failed: {err}`)
		end
	end
end

for _, name in order do
	local start = loaded[name].start
	if start then
		task.spawn(function()
			local ok, err = pcall(function()
				start()
			end)
			if not ok then
				warn(`[SkipARock] {name}.start failed: {err}`)
			end
		end)
	end
end

print("[SkipARock] client started")
