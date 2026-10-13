--!strict
-- Player profiles: load, autosave, release. Follows docs/roblox-datastores:
--   * UpdateAsync only (never Get+Set), with retry + backoff
--   * session locking so two servers can never both own a profile (no dupes)
--   * save on autosave, on leave, and on server shutdown (BindToClose)
--   * a failed load kicks the player instead of handing them an empty profile
--
-- In Studio without "Enable Studio Access to API Services", DataStores are not
-- available; profiles then live in memory only and a warning is printed.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

type Profile = Types.Profile

local Data = {}

local STORE_NAME = "RaiseADino_Profiles_v1"
local CURRENT_VERSION = 1
local MAX_RECEIPTS = 100

type Lock = { jobId: string, time: number }
type Stored = { profile: Profile, lock: Lock? }

local store: DataStore? = nil
local mock = false

local profiles: { [Player]: Profile } = {}
local saving: { [Player]: boolean } = {}
local nextAutosave: { [Player]: number } = {}

local function defaultProfile(now: number): Profile
	return {
		version = CURRENT_VERSION,
		coins = Config.STARTING_COINS,
		pendingCoins = 0,
		totalEarned = 0,
		nextId = 1,
		dinos = {},
		incubators = {},
		tray = {},
		dex = {},
		upgrades = { slots = 0, incubators = 0 },
		boosts = { luckUntil = 0, coinsUntil = 0 },
		instantHatchTokens = 0,
		streak = { count = 0, lastDay = 0 },
		club = { lastClaimDay = 0 },
		tutorial = 0,
		starterPackBought = false,
		shop = { restock = 0, bought = {} },
		likes = 0,
		stats = { hatched = 0, stolen = 0, eggsLost = 0, sold = 0 },
		receipts = {},
		firstJoin = now,
		lastSeen = now,
		quests = { day = 0, progress = {}, claimed = {}, bonusClaimed = false },
		dexClaimed = {},
		codes = {},
		settings = { music = true, sfx = true },
		nicknames = {},
	}
end

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[k] = deepCopy(v)
	end
	return copy :: any
end

local function isArray(t: { [any]: any }): boolean
	return #t > 0 or next(t) == nil
end

-- Fill in any fields added to the default profile since this one was saved.
local function reconcile(target: { [any]: any }, template: { [any]: any })
	for key, value in template do
		if target[key] == nil then
			target[key] = deepCopy(value)
		elseif type(value) == "table" and type(target[key]) == "table" and not isArray(value) then
			reconcile(target[key], value)
		end
	end
end

-- Version migrations: MIGRATIONS[n] upgrades a version-n profile to n+1.
local MIGRATIONS: { [number]: (any) -> any } = {}

local function migrate(profile: any): Profile
	local version = if type(profile.version) == "number" then profile.version else 1
	while version < CURRENT_VERSION do
		local step = MIGRATIONS[version]
		if not step then
			error(`missing migration from v{version}`)
		end
		profile = step(profile)
		version += 1
		profile.version = version
	end
	reconcile(profile, defaultProfile(Clock.now()))
	return profile
end

local function keyFor(player: Player): string
	return `u_{player.UserId}`
end

local function withRetry(attempts: number, fn: () -> ()): (boolean, string?)
	local delaySeconds = 1
	local lastError: string? = nil
	for attempt = 1, attempts do
		local result = table.pack(pcall(fn))
		if result[1] then
			return true, nil
		end
		local err = result[2]
		lastError = tostring(err)
		warn(`[Data] attempt {attempt}/{attempts} failed: {err}`)
		if attempt < attempts then
			task.wait(delaySeconds)
			delaySeconds = math.min(delaySeconds * 2, 16)
		end
	end
	return false, lastError
end

function Data.isMock(): boolean
	return mock
end

-- Loads and session-locks a profile. Yields. Returns nil if it can't be loaded
-- safely (the caller kicks the player).
function Data.load(player: Player): Profile?
	if mock then
		local profile = defaultProfile(Clock.now())
		profiles[player] = profile
		nextAutosave[player] = os.clock() + Config.AUTOSAVE_INTERVAL
		return profile
	end
	local ds = store :: DataStore
	local key = keyFor(player)

	for _ = 1, 5 do
		local loaded: Profile? = nil
		local lockedElsewhere = false
		local ok = withRetry(3, function()
			ds:UpdateAsync(key, function(stored: any): any
				loaded = nil
				lockedElsewhere = false
				local now = Clock.now()
				if type(stored) == "table" and type(stored.lock) == "table" then
					local lock = stored.lock :: Lock
					if
						lock.jobId ~= game.JobId
						and now - lock.time < Config.SESSION_LOCK_STALE_SECONDS
					then
						lockedElsewhere = true
						return nil -- abort: another server still owns this profile
					end
				end
				local profile: Profile
				if type(stored) == "table" and type(stored.profile) == "table" then
					profile = migrate(stored.profile)
				else
					profile = defaultProfile(now)
				end
				loaded = profile
				local result: Stored =
					{ profile = profile, lock = { jobId = game.JobId, time = now } }
				return result
			end)
		end)
		if not ok then
			return nil
		end
		if loaded then
			profiles[player] = loaded
			nextAutosave[player] = os.clock() + Config.AUTOSAVE_INTERVAL
			return loaded
		end
		if lockedElsewhere then
			-- The other server is probably mid-save after the player hopped servers.
			task.wait(4)
		end
		if player.Parent == nil then
			return nil
		end
	end
	return nil
end

function Data.get(player: Player): Profile?
	return profiles[player]
end

local function save(player: Player, release: boolean): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	if mock then
		return true
	end
	-- One write per key at a time.
	while saving[player] do
		task.wait(0.2)
	end
	saving[player] = true
	profile.lastSeen = Clock.now()
	local ds = store :: DataStore
	local lostLock = false
	local ok = withRetry(if release then 5 else 3, function()
		ds:UpdateAsync(keyFor(player), function(stored: any): any
			lostLock = false
			local now = Clock.now()
			if type(stored) == "table" and type(stored.lock) == "table" then
				local lock = stored.lock :: Lock
				if
					lock.jobId ~= game.JobId
					and now - lock.time < Config.SESSION_LOCK_STALE_SECONDS
				then
					lostLock = true
					return nil
				end
			end
			local result: Stored = {
				profile = profile,
				lock = if release then nil else { jobId = game.JobId, time = now },
			}
			return result
		end)
	end)
	saving[player] = nil
	if lostLock then
		warn(`[Data] {player.Name}'s profile is locked by another server; not saving`)
		return false
	end
	return ok
end

-- Save immediately (used after Robux purchases). Returns true on success.
function Data.saveNow(player: Player): boolean
	return save(player, false)
end

-- Final save + release the session lock, then forget the profile.
function Data.release(player: Player)
	if not profiles[player] then
		return
	end
	save(player, true)
	profiles[player] = nil
	nextAutosave[player] = nil
end

-- QA: replace a profile with a brand-new one (keeps the purchase ledger).
function Data.reset(player: Player): Profile?
	local old = profiles[player]
	if not old then
		return nil
	end
	local fresh = defaultProfile(Clock.now())
	fresh.receipts = old.receipts
	profiles[player] = fresh
	return fresh
end

-- Remember a processed Robux purchase so it is never granted twice.
function Data.hasReceipt(profile: Profile, purchaseId: string): boolean
	return table.find(profile.receipts, purchaseId) ~= nil
end

function Data.addReceipt(profile: Profile, purchaseId: string)
	table.insert(profile.receipts, purchaseId)
	while #profile.receipts > MAX_RECEIPTS do
		table.remove(profile.receipts, 1)
	end
end

function Data.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	end
	if RunService:IsStudio() then
		local usable = ok
			and pcall(function()
				(result :: DataStore):GetAsync("studio_probe")
			end)
		if not usable then
			mock = true
			warn(
				"[Data] DataStores aren't available in this Studio session, so progress won't save.\n"
					.. "To test saving: publish the game, then Game Settings > Security > "
					.. "Enable Studio Access to API Services."
			)
		end
	elseif not ok then
		error("[Data] could not open DataStore: " .. tostring(result))
	end
end

function Data.start()
	-- Autosave, staggered per player.
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			for player, due in nextAutosave do
				if now >= due and player.Parent ~= nil then
					nextAutosave[player] = now + Config.AUTOSAVE_INTERVAL
					task.spawn(save, player, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		if mock then
			return
		end
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				save(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		-- Lifecycle calls Data.release after other systems clean up; this is the
		-- safety net in case a player leaves before Lifecycle finished loading them.
		task.delay(10, function()
			if profiles[player] and player.Parent == nil then
				Data.release(player)
			end
		end)
	end)
end

return Data
