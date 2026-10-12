--!strict
-- Loads src/ modules under Lune with Roblox-style `require(script.Parent.X)`
-- working, by giving each module a fake `script` that maps to its file path.
-- Only pure modules (no game services) can be loaded this way.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Loader = {}

-- Extra globals (e.g. Roblox datatypes for smoke tests) visible to loaded modules.
Loader.globals = {} :: { [string]: any }

local cache: { [string]: any } = {}

type FakeScript = { __path: string }

local function parentOf(path: string): string
	local parent = string.match(path, "^(.*)/[^/]+$")
	return parent or "."
end

local makeScript: (path: string) -> any
local requireModule: (target: any) -> any

makeScript = function(path: string): any
	return setmetatable({ __path = path }, {
		__index = function(_, key: string)
			if key == "Parent" then
				return makeScript(parentOf(path))
			end
			return makeScript(path .. "/" .. key)
		end,
	})
end

local function resolveFile(path: string): (string, string)
	if fs.isFile(path .. ".luau") then
		return path .. ".luau", path
	elseif fs.isFile(path .. "/init.luau") then
		return path .. "/init.luau", path
	end
	error(`module not found: {path}`)
end

local function makeEnvironment(scriptPath: string): { [string]: any }
	local env = {
		script = makeScript(scriptPath),
		require = function(target: any)
			return requireModule(target)
		end,
	}
	-- Lune merges raw keys of this table into the chunk's globals.
	for key, value in Loader.globals do
		(env :: any)[key] = value
	end
	return env :: any
end

requireModule = function(target: any): any
	local path = rawget(target, "__path")
	assert(type(path) == "string", "require expects a fake script")
	local file, scriptPath = resolveFile(path)
	if cache[file] ~= nil then
		return cache[file]
	end
	local source = fs.readFile(file)
	local chunk = luau.load(source, {
		debugName = file,
		environment = makeEnvironment(scriptPath),
	})
	local result = chunk()
	cache[file] = result
	return result
end

-- Load a module by its path relative to the repo root, e.g. "src/shared/Util/Odds".
function Loader.load(path: string): any
	return requireModule(makeScript(path))
end

-- Replace a module with a stand-in before anything requires it.
function Loader.stub(path: string, value: any)
	cache[path .. ".luau"] = value
end

-- A fake instance path ("src/shared") that modules can index and require, used
-- to stand in for e.g. ReplicatedStorage.Shared.
function Loader.path(path: string): any
	return makeScript(path)
end

return Loader
