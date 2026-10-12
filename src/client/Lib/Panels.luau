--!strict
-- Pop-up windows (shop, store, dex...). One open at a time, with an open
-- animation and a close button. Tapping the dimmed background closes too.

local TweenService = game:GetService("TweenService")

local UI = require(script.Parent.UI)

local Panels = {}

type Window = {
	frame: Frame,
	content: Frame,
	scale: UIScale,
	onOpen: { () -> () },
	onClose: { () -> () },
}

local gui: ScreenGui? = nil
local dim: TextButton? = nil
local windows: { [string]: Window } = {}
local current: string? = nil

local function root(): ScreenGui
	if gui then
		return gui
	end
	local screen = UI.screen("Panels", 10)
	local background = UI.new("TextButton", {
		Name = "Dim",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		Size = UDim2.fromScale(4, 4),
		Position = UDim2.fromScale(-1.5, -1.5),
		Visible = false,
		ZIndex = 0,
		Parent = screen,
	}) :: TextButton
	background.Activated:Connect(function()
		Panels.close()
	end)
	gui = screen
	dim = background
	return screen
end

-- Creates a window and returns (window frame, content frame).
function Panels.window(name: string, title: string, size: Vector2, accent: Color3?): (Frame, Frame)
	local screen = root()
	local frame = UI.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = UI.Theme.panel,
		Visible = false,
		ZIndex = 2,
		Parent = screen,
	}, {
		UI.corner(22),
		UI.stroke(UI.Theme.ink, 4),
	}) :: Frame
	local scale = UI.new("UIScale", { Parent = frame }) :: UIScale

	local titleBar = UI.new("Frame", {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundColor3 = accent or UI.Theme.orange,
		Parent = frame,
	}, { UI.corner(22) }) :: Frame
	-- square off the bottom of the title bar
	UI.new("Frame", {
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 1, -22),
		BackgroundColor3 = accent or UI.Theme.orange,
		BorderSizePixel = 0,
		Parent = titleBar,
	})
	UI.text({
		text = title,
		size = UDim2.new(1, -140, 0, 44),
		position = UDim2.new(0.5, 0, 0, 7),
		anchor = Vector2.new(0.5, 0),
		maxTextSize = 36,
		parent = titleBar,
	})
	UI.button({
		text = "✕",
		size = UDim2.fromOffset(46, 46),
		position = UDim2.new(1, -8, 0, 6),
		anchor = Vector2.new(1, 0),
		color = UI.Theme.red,
		parent = frame,
		onClick = function()
			Panels.close()
		end,
	})

	local content = UI.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 68),
		Size = UDim2.new(1, -28, 1, -80),
		Parent = frame,
	}) :: Frame

	windows[name] = { frame = frame, content = content, scale = scale, onOpen = {}, onClose = {} }
	return frame, content
end

function Panels.onOpen(name: string, fn: () -> ())
	table.insert(windows[name].onOpen, fn)
end

function Panels.onClose(name: string, fn: () -> ())
	table.insert(windows[name].onClose, fn)
end

function Panels.isOpen(name: string): boolean
	return current == name
end

function Panels.current(): string?
	return current
end

function Panels.close()
	if not current then
		return
	end
	local window = windows[current]
	current = nil
	if dim then
		dim.Visible = false
	end
	if window then
		window.frame.Visible = false
		for _, fn in window.onClose do
			task.spawn(fn)
		end
	end
end

function Panels.open(name: string)
	local window = windows[name]
	if not window then
		return
	end
	if current and current ~= name then
		Panels.close()
	end
	current = name
	if dim then
		dim.Visible = true
	end
	window.frame.Visible = true
	window.scale.Scale = 0.8
	TweenService:Create(window.scale, UI.BOUNCY, { Scale = 1 }):Play()
	for _, fn in window.onOpen do
		task.spawn(fn)
	end
end

function Panels.toggle(name: string)
	if current == name then
		Panels.close()
	else
		Panels.open(name)
	end
end

return Panels
