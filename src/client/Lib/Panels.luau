--!strict
-- Pop-up windows (shop, store, dex...). One open at a time, with a bouncy open
-- animation, a round close button and a dimmed background that closes on tap.
-- Windows shrink to fit small screens, so nothing spills off a phone.

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local UI = require(script.Parent.UI)

local Panels = {}

local HEADER = 66
local MARGIN = 24

type Window = {
	frame: Frame,
	content: Frame,
	scale: UIScale,
	size: Vector2,
	title: TextLabel,
	onOpen: { () -> () },
	onClose: { () -> () },
}

local gui: ScreenGui? = nil
local dim: TextButton? = nil
local windows: { [string]: Window } = {}
local current: string? = nil

-- How much a window must shrink to fit the current screen (1 = not at all).
local function fit(window: Window): number
	local canvas = UI.canvasSize()
	return math.min(
		1,
		(canvas.X - MARGIN) / window.size.X,
		(canvas.Y - MARGIN) / (window.size.Y + 8)
	)
end

local function root(): ScreenGui
	if gui then
		return gui
	end
	local screen = UI.screen("Panels", 10)
	local background = UI.new("TextButton", {
		Name = "Dim",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(20, 14, 34),
		BackgroundTransparency = 0.5,
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
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local name = current
			local window = name and windows[name]
			if window then
				window.scale.Scale = fit(window)
			end
		end)
	end
	return screen
end

-- Creates a window and returns (window frame, content frame). The content
-- frame sits under the header with padding already applied.
function Panels.window(name: string, title: string, size: Vector2, accent: Color3?): (Frame, Frame)
	local screen = root()
	local color = accent or UI.Theme.orange
	local frame = UI.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 2,
		Parent = screen,
	}) :: Frame
	local scale = UI.new("UIScale", { Parent = frame }) :: UIScale

	-- soft drop shadow
	UI.new("Frame", {
		Name = "Shadow",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, 9),
		BackgroundColor3 = Color3.fromRGB(20, 14, 34),
		BackgroundTransparency = 0.6,
		Parent = frame,
	}, { UI.corner(28) })

	local body = UI.new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UI.Theme.panel,
		Parent = frame,
	}, { UI.corner(28), UI.stroke(UI.Theme.ink, 4) }) :: Frame
	UI.studs(body, 28)

	-- coloured ribbon header (rounded top, square bottom)
	local header = UI.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, HEADER),
		BackgroundColor3 = color,
		Parent = body,
	}, { UI.corner(28), UI.shade(0.86) }) :: Frame
	UI.new("Frame", {
		Name = "Square",
		Size = UDim2.new(1, 0, 0, 28),
		Position = UDim2.new(0, 0, 1, -28),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = header,
	}, { UI.shade(0.93) })
	UI.new("Frame", {
		Name = "Edge",
		Size = UDim2.new(1, 0, 0, 4),
		Position = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = UI.darken(color, 0.3),
		BorderSizePixel = 0,
		Parent = header,
	})
	local titleLabel = UI.text({
		name = "Title",
		text = title,
		size = UDim2.new(1, -150, 0, 46),
		position = UDim2.new(0.5, 0, 0, 10),
		anchor = Vector2.new(0.5, 0),
		maxTextSize = 36,
		outlineThickness = 3,
		zIndex = 2,
		parent = header,
	})

	UI.button({
		name = "Close",
		text = "X",
		size = UDim2.fromOffset(52, 52),
		position = UDim2.new(1, -12, 0, 12),
		anchor = Vector2.new(0.5, 0.5),
		color = UI.Theme.red,
		radius = 26,
		depth = 4,
		maxTextSize = 30,
		zIndex = 4,
		parent = frame,
		onClick = function()
			Panels.close()
		end,
	})

	local content = UI.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, HEADER + 14),
		Size = UDim2.new(1, -36, 1, -(HEADER + 28)),
		Parent = body,
	}) :: Frame

	windows[name] = {
		frame = frame,
		content = content,
		scale = scale,
		size = size,
		title = titleLabel,
		onOpen = {},
		onClose = {},
	}
	return frame, content
end

function Panels.setTitle(name: string, title: string)
	local window = windows[name]
	if window then
		window.title.Text = title
	end
end

function Panels.has(name: string): boolean
	return windows[name] ~= nil
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
	local target = fit(window)
	window.scale.Scale = target * 0.82
	TweenService:Create(window.scale, UI.BOUNCY, { Scale = target }):Play()
	UI.onOpen()
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

-- Segmented tab bar. `pages` maps tab name -> page frame; returns a function
-- that selects a tab by name.
function Panels.tabs(
	parent: Instance,
	tabs: { { name: string, text: string, color: Color3 } },
	onSelect: (name: string) -> ()
): (name: string) -> ()
	local bar = UI.new("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 50),
		Parent = parent,
	}, { UI.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left) }) :: Frame
	local buttons: { [string]: UI.Button } = {}
	local colors: { [string]: Color3 } = {}
	local function selectTab(name: string)
		for tabName, button in buttons do
			local active = tabName == name
			UI.setButton(button, { color = if active then colors[tabName] else UI.Theme.grey })
			button.root.Size =
				UDim2.fromOffset(button.root.Size.X.Offset, if active then 46 else 42)
		end
		onSelect(name)
	end
	for order, tab in tabs do
		colors[tab.name] = tab.color
		buttons[tab.name] = UI.button({
			name = tab.name .. "Tab",
			text = tab.text,
			size = UDim2.fromOffset(170, 44),
			color = tab.color,
			order = order,
			maxTextSize = 24,
			depth = 4,
			parent = bar,
			onClick = function()
				selectTab(tab.name)
			end,
		})
	end
	return selectTab
end

return Panels
