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
	info = Color3.fromRGB(45, 50, 70),
	good = Color3.fromRGB(40, 140, 70),
	bad = Color3.fromRGB(190, 60, 60),
	rare = Color3.fromRGB(150, 80, 230),
	event = Color3.fromRGB(230, 120, 30),
}

local container: Frame? = nil
local order = 0

function Toasts.show(text: string, style: string?)
	local holder = container
	if not holder then
		return
	end
	order += 1
	local toast = UI.new("Frame", {
		Size = UDim2.fromOffset(340, 56),
		BackgroundColor3 = COLORS[style or "info"] or COLORS.info,
		BackgroundTransparency = 0.05,
		LayoutOrder = -order,
		Parent = holder,
	}, {
		UI.corner(14),
		UI.stroke(UI.Theme.ink, 2),
	}) :: Frame
	local label = UI.text({
		text = text,
		size = UDim2.new(1, -16, 1, -8),
		position = UDim2.fromOffset(8, 4),
		align = Enum.TextXAlignment.Left,
		maxTextSize = 22,
		parent = toast,
	})
	UI.pop(toast)

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
		toasts[i]:Destroy()
	end

	task.delay(LIFETIME, function()
		if toast.Parent then
			TweenService:Create(toast, UI.SMOOTH, { BackgroundTransparency = 1 }):Play()
			TweenService
				:Create(label, UI.SMOOTH, { TextTransparency = 1, TextStrokeTransparency = 1 })
				:Play()
			task.wait(0.4)
			toast:Destroy()
		end
	end)
end

function Toasts.init()
	local screen = UI.screen("Toasts", 20)
	container = UI.new("Frame", {
		Name = "Container",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(340, 300),
		Parent = screen,
	}, {
		UI.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right),
	})
	Net.listen("Notify", function(text: string, style: string?)
		if typeof(text) == "string" then
			Toasts.show(text, style)
		end
	end)
end

return Toasts
