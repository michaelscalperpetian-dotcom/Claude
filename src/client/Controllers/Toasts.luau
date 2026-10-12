--!strict
-- Little message pop-ups in the top-right corner. Server messages arrive via
-- the "Notify" remote; other controllers can call Toasts.show directly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local UI = require(script.Parent.Parent.Lib.UI)

local Toasts = {}

local MAX_TOASTS = 4
local LIFETIME = 4.5

local COLORS: { [string]: Color3 } = {
	info = Color3.fromRGB(70, 62, 102),
	good = Color3.fromRGB(56, 178, 92),
	bad = Color3.fromRGB(230, 76, 82),
	rare = Color3.fromRGB(150, 92, 240),
	event = Color3.fromRGB(245, 140, 40),
}

local container: Frame? = nil
local order = 0
-- Live toasts by name (names are unique; instance identity isn't reliable in
-- every runtime, e.g. the Lune test harness).
local live: { [string]: boolean } = {}

-- Hook for a sound per toast style (set by the audio controller).
Toasts.onShow = function(_style: string) end

function Toasts.show(text: string, style: string?)
	local holder = container
	if not holder then
		return
	end
	order += 1
	local color = COLORS[style or "info"] or COLORS.info
	local id = "Toast" .. order
	local slot = UI.new("Frame", {
		Name = id,
		Size = UDim2.fromOffset(340, 56),
		BackgroundTransparency = 1,
		LayoutOrder = -order,
		Parent = holder,
	}) :: Frame
	local card = UI.new("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(60, 0),
		BackgroundColor3 = color,
		Parent = slot,
	}, { UI.corner(18), UI.stroke(UI.darken(color, 0.45), 3), UI.shade(0.86) }) :: Frame
	local label = UI.text({
		text = text,
		size = UDim2.new(1, -24, 1, -10),
		position = UDim2.fromOffset(12, 5),
		align = Enum.TextXAlignment.Left,
		maxTextSize = 21,
		outline = UI.darken(color, 0.6),
		parent = card,
	})
	live[id] = true
	TweenService:Create(card, UI.BOUNCY, { Position = UDim2.new() }):Play()
	Toasts.onShow(style or "info")

	local toasts = {}
	for _, child in holder:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	table.sort(toasts, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = MAX_TOASTS + 1, #toasts do
		live[toasts[i].Name] = nil
		toasts[i]:Destroy()
	end

	task.delay(LIFETIME, function()
		if live[id] then
			TweenService:Create(
				card,
				UI.SMOOTH,
				{ BackgroundTransparency = 1, Position = UDim2.fromOffset(40, 0) }
			):Play()
			TweenService:Create(label, UI.SMOOTH, { TextTransparency = 1 }):Play()
			for _, stroke in card:GetDescendants() do
				if stroke:IsA("UIStroke") then
					TweenService:Create(stroke, UI.SMOOTH, { Transparency = 1 }):Play()
				end
			end
			task.wait(0.4)
			if live[id] then
				live[id] = nil
				slot:Destroy()
			end
		end
	end)
end

function Toasts.init()
	local screen = UI.screen("Toasts", 20)
	container = UI.new("Frame", {
		Name = "Container",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 12),
		Size = UDim2.fromOffset(340, 300),
		Parent = screen,
	}, {
		UI.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right),
	})
	Net.listen("Notify", function(text: string, style: string?)
		if typeof(text) == "string" then
			Toasts.show(text, style)
		end
	end)
end

return Toasts
