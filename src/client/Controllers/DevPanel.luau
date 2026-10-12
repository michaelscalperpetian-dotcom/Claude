--!strict
-- QA cheat panel. Only appears when the server says you're a developer
-- (always in Studio). The server checks permission on every command too.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local StoreData = require(ReplicatedStorage.Shared.Data.StoreData)
local Types = require(ReplicatedStorage.Shared.Types)
local ClientState = require(script.Parent.ClientState)
local Panels = require(script.Parent.Parent.Lib.Panels)
local UI = require(script.Parent.Parent.Lib.UI)

local DevPanel = {}

local toggle: TextButton

local COMMANDS = {
	{ "coins", "+1M coins" },
	{ "grow", "Grow dinos" },
	{ "hatch", "Eggs ready" },
	{ "lay", "Lay eggs" },
	{ "night", "Make night" },
	{ "day", "Make day" },
	{ "storm", "Start storm" },
	{ "mega", "Mega storm" },
	{ "resettime", "Normal time" },
	{ "luck", "Luck 15m" },
	{ "trex", "Add T-Rex" },
	{ "noshield", "Remove shield" },
	{ "skiptutorial", "Skip tutorial" },
	{ "reset", "Reset save" },
}

function DevPanel.init()
	local _, content =
		Panels.window("Dev", "🛠 Test Tools (Studio only)", Vector2.new(760, 500), UI.Theme.grey)
	local grid = UI.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = content,
	}, {
		UI.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(170, 54),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: ScrollingFrame
	for order, entry in COMMANDS do
		UI.button({
			text = entry[2],
			size = UDim2.fromOffset(170, 54),
			color = if entry[1] == "reset" then UI.Theme.red else UI.Theme.blue,
			order = order,
			maxTextSize = 22,
			parent = grid,
			onClick = function()
				Net.send("Cheat", entry[1])
			end,
		})
	end
	for order, pass in StoreData.PASSES do
		UI.button({
			text = "Pass: " .. pass.name,
			size = UDim2.fromOffset(170, 54),
			color = UI.Theme.purple,
			order = 100 + order,
			maxTextSize = 18,
			parent = grid,
			onClick = function()
				Net.send("Cheat", "pass", pass.key)
			end,
		})
	end

	local screen = UI.screen("DevToggle", 4)
	toggle = UI.button({
		text = "🛠",
		size = UDim2.fromOffset(56, 56),
		position = UDim2.new(0, 12, 0, 60),
		color = UI.Theme.grey,
		parent = screen,
		onClick = function()
			Panels.toggle("Dev")
		end,
	})
	toggle.Visible = false
	ClientState.changed:connect(function(snapshot: Types.Snapshot)
		toggle.Visible = snapshot.isDev
	end)
end

return DevPanel
