--!strict
-- Global leaderboards in the hub's Hall of Fame: top coin earners, biggest
-- Dex and most rebirths. Scores go to OrderedDataStores every few minutes
-- (and when a player leaves); the top 10 are read back and shown on the
-- boards. Without DataStore access (Studio before publishing) the boards
-- show the players in this server instead.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")
local Workspace = game:GetService("Workspace")

local Format = require(ReplicatedStorage.Shared.Util.Format)
local Types = require(ReplicatedStorage.Shared.Types)
local Data = require(script.Parent.Data)
local Sessions = require(script.Parent.Sessions)
local BoardData = require(script.Parent.Parent.Lib.BoardData)

local Leaderboards = {}

Leaderboards.REFRESH_SECONDS = 120

export type Entry = { userId: number, value: number }

local MAX_VALUE = 2 ^ 53

local stores: { [string]: OrderedDataStore } = {}
local mock = false
local lastWritten: { [Player]: { [string]: number } } = {}
local names: { [number]: string } = {}

local function valueOf(key: string, profile: Types.Profile): number
	local value = 0
	if key == "Earned" then
		value = profile.totalEarned
	elseif key == "Dex" then
		for _ in profile.dex do
			value += 1
		end
	elseif key == "Rebirths" then
		value = profile.rebirths
	end
	return math.clamp(math.floor(value), 0, MAX_VALUE)
end

local function formatValue(key: string, value: number): string
	if key == "Earned" then
		return "💰 " .. Format.number(value)
	elseif key == "Dex" then
		return `{value} 🦖`
	end
	return `⭐ {value}`
end

local function openStores()
	for _, board in BoardData.BOARDS do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(board.store)
		end)
		if not ok then
			mock = true
			return
		end
		stores[board.key] = store
	end
end

-- Saves a player's scores (only the ones that changed since last time).
local function write(player: Player, profile: Types.Profile)
	if mock then
		return
	end
	local written = lastWritten[player] or {}
	lastWritten[player] = written
	for _, board in BoardData.BOARDS do
		local value = valueOf(board.key, profile)
		local store = stores[board.key]
		if store and written[board.key] ~= value and value > 0 then
			local ok = pcall(function()
				store:SetAsync(tostring(player.UserId), value)
			end)
			if ok then
				written[board.key] = value
			end
		end
	end
end

local function topEntries(key: string): { Entry }
	local entries: { Entry } = {}
	if mock then
		for _, player in Players:GetPlayers() do
			local profile = Data.get(player)
			if profile then
				table.insert(entries, { userId = player.UserId, value = valueOf(key, profile) })
				names[player.UserId] = player.DisplayName
			end
		end
		table.sort(entries, function(a, b)
			return a.value > b.value
		end)
		while #entries > BoardData.ROWS do
			table.remove(entries)
		end
		return entries
	end
	local store = stores[key]
	if not store then
		return entries
	end
	local ok, page = pcall(function()
		return store:GetSortedAsync(false, BoardData.ROWS):GetCurrentPage()
	end)
	if ok and type(page) == "table" then
		for _, item in page do
			local userId = tonumber(item.key)
			if userId and type(item.value) == "number" then
				table.insert(entries, { userId = userId, value = item.value })
			end
		end
	end
	return entries
end

-- Display names for any user ids we haven't seen yet.
local function resolveNames(entries: { Entry })
	local missing = {}
	for _, entry in entries do
		if not names[entry.userId] then
			local player = Players:GetPlayerByUserId(entry.userId)
			if player then
				names[entry.userId] = player.DisplayName
			else
				table.insert(missing, entry.userId)
			end
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(missing)
	end)
	if ok and type(infos) == "table" then
		for _, info in infos do
			if type(info.Id) == "number" and type(info.DisplayName) == "string" then
				names[info.Id] = info.DisplayName
			end
		end
	end
end

local function render(key: string, entries: { Entry })
	local map = Workspace:FindFirstChild("Map")
	local hall = map and map:FindFirstChild("HallOfFame")
	local model = hall and hall:FindFirstChild(key)
	local face = model and model:FindFirstChild("Face")
	local gui = face and face:FindFirstChild("Board")
	if not gui then
		return
	end
	for row = 1, BoardData.ROWS do
		local frame = gui:FindFirstChild("Row" .. row)
		local nameLabel = frame and frame:FindFirstChild("Player")
		local valueLabel = frame and frame:FindFirstChild("Score")
		local rankLabel = frame and frame:FindFirstChild("Rank")
		if
			not nameLabel
			or not nameLabel:IsA("TextLabel")
			or not valueLabel
			or not valueLabel:IsA("TextLabel")
			or not rankLabel
			or not rankLabel:IsA("TextLabel")
		then
			continue
		end
		local entry = entries[row]
		rankLabel.Text = if row == 1
			then "🥇"
			elseif row == 2 then "🥈"
			elseif row == 3 then "🥉"
			else tostring(row)
		nameLabel.Text = if entry then names[entry.userId] or "Player" else ""
		valueLabel.Text = if entry then formatValue(key, entry.value) else ""
	end
end

-- One full pass: save everyone's scores, then redraw every board.
function Leaderboards.refresh()
	for _, session in Sessions.ready() do
		local profile = Data.get(session.player)
		if profile then
			write(session.player, profile)
		end
	end
	for _, board in BoardData.BOARDS do
		local entries = topEntries(board.key)
		resolveNames(entries)
		render(board.key, entries)
	end
end

function Leaderboards.isMock(): boolean
	return mock
end

function Leaderboards.init()
	openStores()
	Sessions.Leaving:connect(function(player: Player)
		local profile = Data.get(player)
		if profile then
			task.spawn(write, player, profile)
		end
		lastWritten[player] = nil
	end)
end

function Leaderboards.start()
	task.wait(10)
	while true do
		Leaderboards.refresh()
		task.wait(Leaderboards.REFRESH_SECONDS)
	end
end

return Leaderboards
