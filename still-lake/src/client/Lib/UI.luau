--!strict
-- Still Lake's UI kit: one calm look shared by every screen.
--
--   * Soft slate "glass" pills float over the world (HUD); warm paper
--     panels hold the journal. Everything is rounded, nothing shouts.
--   * Fredoka One for headings and numbers, Builder Sans for body text.
--   * Layout is in design pixels; each ScreenGui gets a UIScale that fits a
--     1150 x 650 canvas to phones, tablets and desktops.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local UI = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

UI.Theme = {
	ink = rgb(36, 48, 66), -- text on paper, outlines
	inkSoft = rgb(104, 116, 134),
	glass = rgb(28, 40, 58), -- HUD pills (with GLASS transparency)
	paper = rgb(250, 246, 238),
	paperDark = rgb(238, 230, 216),
	card = rgb(255, 255, 255),
	line = rgb(222, 212, 196),
	white = rgb(255, 255, 255),
	water = rgb(84, 172, 204),
	waterDeep = rgb(56, 132, 178),
	gold = rgb(246, 196, 84),
	perfect = rgb(255, 240, 160),
	coral = rgb(236, 112, 96),
	sage = rgb(120, 186, 120),
	dusk = rgb(132, 120, 206),
	good = rgb(52, 150, 92),
	bad = rgb(206, 84, 76),
}

UI.GLASS = 0.28 -- transparency of HUD pills
UI.Font = Enum.Font.FredokaOne
UI.BodyFont = Enum.Font.BuilderSansBold
UI.LightFont = Enum.Font.BuilderSansMedium

-- Sound hooks (set by the Audio controller).
UI.onClick = function() end

UI.FAST = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
UI.SOFT = TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
UI.BOUNCY = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

UI.DESIGN = Vector2.new(1150, 650)

function UI.rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

function UI.lighten(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), amount)
end

function UI.darken(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), amount)
end

-- Create an instance, set properties, parent children. Returns `any` so
-- callers cast to the concrete class (`:: Frame`).
function UI.new(className: string, props: { [string]: any }?, children: { any }?): any
	local instance = Instance.new(className)
	local parent: Instance? = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

-- ===== Decorators (return `any` so they mix into one children list) =====

function UI.corner(radius: number?): any
	return UI.new("UICorner", { CornerRadius = UDim.new(0, radius or 14) })
end

function UI.round(): any
	return UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) })
end

function UI.stroke(color: Color3?, thickness: number?, transparency: number?): any
	return UI.new("UIStroke", {
		Color = color or UI.Theme.ink,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UI.padding(px: number, vertical: number?): any
	local h = UDim.new(0, px)
	local v = UDim.new(0, vertical or px)
	return UI.new(
		"UIPadding",
		{ PaddingTop = v, PaddingBottom = v, PaddingLeft = h, PaddingRight = h }
	)
end

function UI.list(
	direction: Enum.FillDirection,
	padding: number,
	horizontalAlign: Enum.HorizontalAlignment?,
	verticalAlign: Enum.VerticalAlignment?
): any
	return UI.new("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, padding),
		HorizontalAlignment = horizontalAlign or Enum.HorizontalAlignment.Center,
		VerticalAlignment = verticalAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function UI.grid(cell: Vector2, gap: number): any
	return UI.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(cell.X, cell.Y),
		CellPadding = UDim2.fromOffset(gap, gap),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

-- ===== Text =====

export type TextProps = {
	text: string,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	color: Color3?,
	font: Enum.Font?,
	align: Enum.TextXAlignment?,
	valign: Enum.TextYAlignment?,
	maxTextSize: number?,
	shadow: boolean?, -- a soft dark outline, for light text over the world
	wrap: boolean?,
	order: number?,
	parent: Instance?,
	name: string?,
	zIndex: number?,
}

function UI.text(props: TextProps): TextLabel
	local label = UI.new("TextLabel", {
		Name = props.name or "Text",
		BackgroundTransparency = 1,
		Text = props.text,
		Size = props.size,
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.zero,
		TextColor3 = props.color or UI.Theme.white,
		Font = props.font or UI.Font,
		TextScaled = true,
		TextWrapped = props.wrap ~= false,
		TextXAlignment = props.align or Enum.TextXAlignment.Center,
		TextYAlignment = props.valign or Enum.TextYAlignment.Center,
		LayoutOrder = props.order or 0,
		ZIndex = props.zIndex or 1,
	}) :: TextLabel
	UI.new("UITextSizeConstraint", {
		MaxTextSize = props.maxTextSize or 32,
		MinTextSize = 8,
		Parent = label,
	})
	if props.shadow then
		UI.new("UIStroke", {
			Color = UI.Theme.glass,
			Thickness = 1.6,
			Transparency = 0.35,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			Parent = label,
		})
	end
	if props.parent then
		label.Parent = props.parent
	end
	return label
end

-- Dark body text for paper panels and cards.
function UI.body(props: TextProps): TextLabel
	props.color = props.color or UI.Theme.ink
	props.font = props.font or UI.BodyFont
	return UI.text(props)
end

-- ===== Surfaces =====

-- A translucent slate pill for the HUD.
function UI.glass(props: { [string]: any }?): Frame
	local frame = UI.new("Frame", {
		BackgroundColor3 = UI.Theme.glass,
		BackgroundTransparency = UI.GLASS,
		BorderSizePixel = 0,
	}, { UI.corner(16), UI.stroke(UI.Theme.white, 1.5, 0.82) }) :: Frame
	if props then
		for key, value in props do
			if key ~= "Parent" then
				(frame :: any)[key] = value
			end
		end
		if props.Parent then
			frame.Parent = props.Parent
		end
	end
	return frame
end

-- A warm paper panel (the journal).
function UI.paper(props: { [string]: any }?): Frame
	local frame = UI.new("Frame", {
		BackgroundColor3 = UI.Theme.paper,
		BorderSizePixel = 0,
	}, { UI.corner(22), UI.stroke(UI.Theme.line, 2) }) :: Frame
	if props then
		for key, value in props do
			if key ~= "Parent" then
				(frame :: any)[key] = value
			end
		end
		if props.Parent then
			frame.Parent = props.Parent
		end
	end
	return frame
end

-- ===== Buttons =====

export type Button = {
	root: TextButton,
	label: TextLabel,
	color: Color3,
	enabled: boolean,
}

export type ButtonProps = {
	text: string,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	color: Color3?, -- face colour; defaults to the HUD glass
	textColor: Color3?,
	font: Enum.Font?,
	order: number?,
	parent: Instance?,
	name: string?,
	onClick: (() -> ())?,
}

local function paint(button: Button)
	local face = if button.enabled then button.color else UI.Theme.inkSoft
	button.root.BackgroundColor3 = face
	button.label.TextTransparency = if button.enabled then 0 else 0.35
end

-- A soft rounded button that dips a little when pressed.
function UI.button(props: ButtonProps): Button
	local color = props.color or UI.Theme.glass
	local root = UI.new("TextButton", {
		Name = props.name or "Button",
		Text = "",
		AutoButtonColor = false,
		Size = props.size,
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.zero,
		BackgroundColor3 = color,
		BackgroundTransparency = if props.color then 0 else UI.GLASS,
		BorderSizePixel = 0,
		LayoutOrder = props.order or 0,
	}, { UI.corner(14), UI.stroke(UI.Theme.white, 1.5, 0.75) }) :: TextButton
	local scale = UI.new("UIScale", { Parent = root }) :: UIScale
	local label = UI.text({
		text = props.text,
		size = UDim2.new(1, -16, 1, -10),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = props.textColor or UI.Theme.white,
		font = props.font,
		maxTextSize = 26,
		name = "Label",
		parent = root,
	})
	local button: Button = { root = root, label = label, color = color, enabled = true }
	root.MouseEnter:Connect(function()
		if button.enabled then
			TweenService:Create(scale, UI.FAST, { Scale = 1.04 }):Play()
		end
	end)
	root.MouseLeave:Connect(function()
		TweenService:Create(scale, UI.FAST, { Scale = 1 }):Play()
	end)
	root.MouseButton1Down:Connect(function()
		if button.enabled then
			TweenService:Create(scale, UI.FAST, { Scale = 0.95 }):Play()
		end
	end)
	root.MouseButton1Up:Connect(function()
		TweenService:Create(scale, UI.FAST, { Scale = 1 }):Play()
	end)
	root.Activated:Connect(function()
		if button.enabled and props.onClick then
			UI.onClick()
			props.onClick()
		end
	end)
	paint(button)
	if props.parent then
		root.Parent = props.parent
	end
	return button
end

function UI.setButton(button: Button, update: { text: string?, color: Color3?, enabled: boolean? })
	if update.text then
		button.label.Text = update.text
	end
	if update.color then
		button.color = update.color
	end
	if update.enabled ~= nil then
		button.enabled = update.enabled
	end
	paint(button)
end

-- ===== Motion =====

function UI.pop(gui: GuiObject, from: number?)
	local scale = gui:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = UI.new("UIScale", { Parent = gui })
	end
	local s = scale :: UIScale
	s.Scale = from or 0.85
	TweenService:Create(s, UI.BOUNCY, { Scale = 1 }):Play()
end

function UI.tween(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local tween = TweenService:Create(instance, info, goal)
	tween:Play()
	return tween
end

-- ===== Screens =====

function UI.topInset(): number
	local ok, topLeft = pcall(function()
		return (GuiService:GetGuiInset())
	end)
	if ok and typeof(topLeft) == "Vector2" and topLeft.Y > 0 then
		return topLeft.Y
	end
	return 58
end

function UI.scaleFor(viewport: Vector2): number
	return math.clamp(math.min(viewport.X / UI.DESIGN.X, viewport.Y / UI.DESIGN.Y), 0.6, 1.3)
end

function UI.viewportSize(): Vector2
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

function UI.isTouch(): boolean
	local UserInputService = game:GetService("UserInputService")
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- A ScreenGui whose contents scale with the screen. Its "Canvas" frame is
-- the design-pixel area to lay things out in (inside the top-bar inset).
function UI.screen(name: string, displayOrder: number): (ScreenGui, Frame)
	local gui = UI.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		DisplayOrder = displayOrder,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = false,
	}) :: ScreenGui
	local canvas = UI.new("Frame", {
		Name = "Canvas",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = gui,
	}) :: Frame
	local scale = UI.new("UIScale", { Parent = canvas }) :: UIScale
	local function update()
		local viewport = UI.viewportSize()
		local s = UI.scaleFor(viewport)
		scale.Scale = s
		-- (offsets are whole pixels: round up so the canvas never falls short)
		canvas.Size =
			UDim2.fromOffset(math.ceil(viewport.X / s), math.ceil((viewport.Y - UI.topInset()) / s))
	end
	update()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui, canvas
end

return UI
