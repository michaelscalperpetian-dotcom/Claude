--!strict
-- The test panel (Studio, and the game's owner in live games): a small
-- button in the corner that opens a few shortcuts for trying things out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local ClientState = require(script.Parent.ClientState)
local UI = require(script.Parent.Parent.Lib.UI)

local DevPanel = {}

local ACTIONS: { { action: string, label: string } } = {
	{ action = "stones", label = "🪨 Every stone" },
	{ action = "night", label = "🌙 Night" },
	{ action = "day", label = "☀️ Day" },
	{ action = "glints", label = "✨ New glints" },
	{ action = "reset", label = "🧽 Start over" },
}

local toggle: UI.Button? = nil

function DevPanel.init()
	local _, canvas = UI.screen("DevPanel", 30)
	local panel = UI.glass({
		Name = "Panel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 58),
		Size = UDim2.fromOffset(176, 14 + #ACTIONS * 44),
		Visible = false,
		Parent = canvas,
	})
	UI.new("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = panel,
	}, { UI.list(Enum.FillDirection.Vertical, 6), UI.padding(8, 8) })
	local buttons = panel:FindFirstChild("Buttons") :: Frame
	for i, item in ACTIONS do
		UI.button({
			name = item.action,
			text = item.label,
			size = UDim2.new(1, 0, 0, 38),
			order = i,
			parent = buttons,
			onClick = function()
				Net.send("Dev", item.action)
			end,
		})
	end
	local button = UI.button({
		name = "Toggle",
		text = "🧪 Test",
		size = UDim2.fromOffset(100, 38),
		position = UDim2.new(1, -16, 0, 12),
		anchor = Vector2.new(1, 0),
		parent = canvas,
		onClick = function()
			panel.Visible = not panel.Visible
		end,
	})
	button.root.Visible = false
	toggle = button
	ClientState.changed:connect(function(snapshot: Types.Snapshot)
		local t = toggle
		if t then
			t.root.Visible = snapshot.isDev
		end
		if not snapshot.isDev then
			panel.Visible = false
		end
	end)
end

return DevPanel
