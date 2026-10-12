--!strict
-- Settings window: music and sound effect switches (saved with your profile)
-- and a box for promo codes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local ClientState = require(script.Parent.ClientState)
local Panels = require(script.Parent.Parent.Lib.Panels)
local UI = require(script.Parent.Parent.Lib.UI)

local SettingsUI = {}

type Switch = { set: (on: boolean) -> () }

local switches: { [string]: Switch } = {}
local codeBox: TextBox

-- Local values win until the server confirms (so switches feel instant).
local pending: { [string]: boolean } = {}

-- Fired when a setting changes locally (the audio controller listens).
SettingsUI.changed = nil :: ((key: string, on: boolean) -> ())?

function SettingsUI.get(key: string): boolean
	if pending[key] ~= nil then
		return pending[key]
	end
	local snapshot = ClientState.get()
	if snapshot then
		return (snapshot.settings :: any)[key] ~= false
	end
	return true
end

local function switch(
	parent: Instance,
	order: number,
	icon: string,
	title: string,
	key: string
): Switch
	local row = UI.card({
		name = key,
		size = UDim2.new(1, -8, 0, 74),
		order = order,
		radius = 18,
		parent = parent,
	})
	UI.text({
		text = icon,
		size = UDim2.fromOffset(48, 48),
		position = UDim2.new(0, 16, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		maxTextSize = 38,
		noOutline = true,
		parent = row,
	})
	UI.body({
		text = title,
		size = UDim2.new(1, -220, 0, 32),
		position = UDim2.new(0, 76, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		font = UI.Font,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 26,
		parent = row,
	})
	local track = UI.new("TextButton", {
		Name = "Switch",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(112, 48),
		Position = UDim2.new(1, -18, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = UI.Theme.green,
		Parent = row,
	}, { UI.round(), UI.stroke(UI.Theme.ink, 3), UI.shade(0.86) }) :: TextButton
	local stateLabel = UI.text({
		text = "ON",
		size = UDim2.fromOffset(52, 30),
		position = UDim2.new(0, 14, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		maxTextSize = 22,
		zIndex = 2,
		parent = track,
	})
	local knob = UI.new("Frame", {
		Name = "Knob",
		Size = UDim2.fromOffset(38, 38),
		Position = UDim2.new(1, -5, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = UI.Theme.white,
		ZIndex = 3,
		Parent = track,
	}, { UI.round(), UI.stroke(UI.Theme.ink, 2.5) }) :: Frame
	local function set(on: boolean)
		track.BackgroundColor3 = if on then UI.Theme.green else UI.Theme.grey
		stateLabel.Text = if on then "ON" else "OFF"
		stateLabel.Position = if on then UDim2.new(0, 14, 0.5, 0) else UDim2.new(1, -66, 0.5, 0)
		TweenService:Create(knob, UI.FAST, {
			Position = if on then UDim2.new(1, -5, 0.5, 0) else UDim2.new(0, 43, 0.5, 0),
		}):Play()
	end
	track.Activated:Connect(function()
		local on = not SettingsUI.get(key)
		pending[key] = on
		set(on)
		UI.onClick()
		Net.send("SetSetting", key, on)
		local changed = SettingsUI.changed
		if changed then
			changed(key, on)
		end
	end)
	return { set = set }
end

local function refresh(snapshot: Types.Snapshot)
	for key, s in switches do
		local saved = (snapshot.settings :: any)[key] ~= false
		if pending[key] == saved then
			pending[key] = nil
		end
		s.set(SettingsUI.get(key))
	end
end

function SettingsUI.init()
	local _, content =
		Panels.window("Settings", "⚙️ Settings", Vector2.new(680, 500), UI.Theme.teal)
	local list = UI.new("Frame", {
		Name = "List",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = content,
	}, { UI.list(Enum.FillDirection.Vertical, 12) }) :: Frame
	if #Config.MUSIC_TRACKS > 0 then
		switches.music = switch(list, 1, "🎵", "Music", "music")
	end
	switches.sfx = switch(list, 2, "🔊", "Sound effects", "sfx")

	UI.body({
		name = "CodesTitle",
		text = "🎟 Have a code? Type it here!",
		size = UDim2.new(1, -8, 0, 32),
		font = UI.Font,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 24,
		order = 3,
		parent = list,
	})
	local codeRow = UI.new("Frame", {
		Name = "Codes",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 0, 62),
		LayoutOrder = 4,
		Parent = list,
	}) :: Frame
	codeBox = UI.new("TextBox", {
		Name = "CodeBox",
		Text = "",
		PlaceholderText = "Type a code...",
		ClearTextOnFocus = false,
		Size = UDim2.new(1, -180, 0, 56),
		BackgroundColor3 = UI.Theme.white,
		TextColor3 = UI.Theme.ink,
		PlaceholderColor3 = UI.Theme.grey,
		Font = UI.Font,
		TextScaled = true,
		Parent = codeRow,
	}, {
		UI.corner(16),
		UI.stroke(UI.Theme.ink, 3),
		UI.padding(16, 10),
		UI.new("UITextSizeConstraint", { MaxTextSize = 28 }),
	}) :: TextBox
	UI.button({
		name = "Redeem",
		text = "Redeem",
		size = UDim2.fromOffset(160, 56),
		position = UDim2.new(1, 0, 0, 0),
		anchor = Vector2.new(1, 0),
		color = UI.Theme.green,
		parent = codeRow,
		onClick = function()
			if codeBox.Text ~= "" then
				Net.send("RedeemCode", codeBox.Text)
				codeBox.Text = ""
			end
		end,
	})
	UI.body({
		text = "New codes are shared in the game's group and updates. Codes work once each.",
		size = UDim2.new(1, -8, 0, 40),
		color = UI.Theme.inkSoft,
		maxTextSize = 17,
		order = 5,
		parent = list,
	})

	ClientState.changed:connect(refresh)
	Panels.onOpen("Settings", function()
		local snapshot = ClientState.get()
		if snapshot then
			refresh(snapshot)
		end
	end)
end

return SettingsUI
