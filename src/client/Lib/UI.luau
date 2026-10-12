--!strict
-- Raise a Dino UI kit: one theme and a few building blocks so every screen
-- shares the same chunky cartoon look.
--
--   * Candy buttons: a coloured face with a top shine and a darker 3D base
--     that the face presses into.
--   * Cream panels and white cards with soft edges, ink outlines for text
--     on top of the 3D world, Fredoka One for headings and buttons.
--   * Layout in design pixels; each ScreenGui gets a UIScale that fits the
--     design canvas (about 1150 x 650) to phones, tablets and desktops.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local UI = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

UI.Theme = {
	ink = rgb(43, 33, 64),
	inkSoft = rgb(104, 92, 132),
	panel = rgb(255, 248, 236),
	panelDark = rgb(244, 232, 210),
	card = rgb(255, 255, 255),
	cardEdge = rgb(232, 216, 190),
	track = rgb(232, 220, 200),
	hud = rgb(43, 33, 64),
	white = rgb(255, 255, 255),
	gold = rgb(255, 201, 60),
	coin = rgb(255, 214, 77),
	green = rgb(85, 209, 110),
	blue = rgb(74, 168, 255),
	red = rgb(255, 90, 95),
	orange = rgb(255, 159, 67),
	purple = rgb(155, 107, 255),
	pink = rgb(255, 120, 190),
	teal = rgb(56, 196, 186),
	grey = rgb(184, 179, 196),
	night = rgb(98, 96, 214),
	day = rgb(74, 168, 255),
	-- readable text colours on cream/white
	good = rgb(40, 150, 72),
	bad = rgb(214, 64, 70),
	money = rgb(206, 140, 0),
}

UI.Font = Enum.Font.FredokaOne
UI.BodyFont = Enum.Font.BuilderSansBold
UI.HeavyFont = Enum.Font.BuilderSansExtraBold

-- Sound hooks (set by the audio controller): button clicks, windows opening.
UI.onClick = function() end
UI.onOpen = function() end

UI.FAST = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
UI.BOUNCY = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
UI.SMOOTH = TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

-- Design canvas the layouts are drawn for.
UI.DESIGN = Vector2.new(1150, 650)

function UI.darken(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), amount)
end

function UI.lighten(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), amount)
end

function UI.rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Create an instance, set properties, parent children. Returns `any` so callers
-- cast to the concrete class (`:: Frame`).
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

-- ===== Decorators (return `any` so they mix in one children list) =====

function UI.corner(radius: number?): any
	return UI.new("UICorner", { CornerRadius = UDim.new(0, radius or 14) })
end

function UI.round(): any
	return UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) })
end

function UI.stroke(color: Color3?, thickness: number?, transparency: number?): any
	return UI.new("UIStroke", {
		Color = color or UI.Theme.ink,
		Thickness = thickness or 3,
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

function UI.grid(cell: Vector2, gap: number, horizontalAlign: Enum.HorizontalAlignment?): any
	return UI.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(cell.X, cell.Y),
		CellPadding = UDim2.fromOffset(gap, gap),
		HorizontalAlignment = horizontalAlign or Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

-- Vertical gradient that multiplies the parent's colour: 1 at the top down to
-- `bottom` (e.g. 0.82) at the bottom.
function UI.shade(bottom: number?): any
	local b = bottom or 0.82
	return UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(b, b, b)),
		Rotation = 90,
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
	-- outline colour; defaults to ink for light text, none for dark text
	outline: Color3?,
	outlineThickness: number?,
	noOutline: boolean?,
	align: Enum.TextXAlignment?,
	valign: Enum.TextYAlignment?,
	maxTextSize: number?,
	minTextSize: number?,
	order: number?,
	wrap: boolean?,
	parent: Instance?,
	name: string?,
	zIndex: number?,
}

local function isLight(c: Color3): boolean
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B > 0.6
end

function UI.text(props: TextProps): TextLabel
	local color = props.color or UI.Theme.white
	local label = UI.new("TextLabel", {
		Name = props.name or "Text",
		BackgroundTransparency = 1,
		Text = props.text,
		Size = props.size,
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.zero,
		TextColor3 = color,
		Font = props.font or UI.Font,
		TextScaled = true,
		TextWrapped = props.wrap ~= false,
		TextXAlignment = props.align or Enum.TextXAlignment.Center,
		TextYAlignment = props.valign or Enum.TextYAlignment.Center,
		LayoutOrder = props.order or 0,
		ZIndex = props.zIndex or 1,
	}) :: TextLabel
	UI.new("UITextSizeConstraint", {
		MaxTextSize = props.maxTextSize or 40,
		MinTextSize = props.minTextSize or 8,
		Parent = label,
	})
	local outline = props.outline or (if isLight(color) then UI.Theme.ink else nil)
	if outline and not props.noOutline then
		UI.new("UIStroke", {
			Color = outline,
			Thickness = props.outlineThickness or 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			Parent = label,
		})
	end
	if props.parent then
		label.Parent = props.parent
	end
	return label
end

-- Dark text for cream panels and white cards (no outline).
function UI.body(props: TextProps): TextLabel
	props.color = props.color or UI.Theme.ink
	props.font = props.font or UI.BodyFont
	props.noOutline = true
	return UI.text(props)
end

-- ===== Candy buttons =====

export type Button = {
	root: Frame,
	face: TextButton,
	base: Frame,
	label: TextLabel,
	color: Color3,
	enabled: boolean,
	faceStroke: UIStroke,
	baseStroke: UIStroke,
	labelStroke: UIStroke,
}

export type ButtonProps = {
	text: string,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	color: Color3?,
	textColor: Color3?,
	font: Enum.Font?,
	radius: number?,
	depth: number?,
	parent: Instance?,
	order: number?,
	name: string?,
	maxTextSize: number?,
	zIndex: number?,
	onClick: () -> (),
}

local function paint(button: Button)
	local c = if button.enabled then button.color else UI.Theme.grey
	local edge = UI.darken(c, 0.42)
	button.face.BackgroundColor3 = c
	button.base.BackgroundColor3 = UI.darken(c, 0.3)
	button.faceStroke.Color = edge
	button.baseStroke.Color = edge
	button.labelStroke.Color = UI.darken(c, 0.55)
end

-- A button that presses into its 3D base. Layout (size, position, parent,
-- visibility) goes on `.root`; the label is `.label`.
function UI.button(props: ButtonProps): Button
	local depth = props.depth or 5
	local radius = props.radius or 14
	local z = props.zIndex or 1
	local root = UI.new("Frame", {
		Name = props.name or "Button",
		BackgroundTransparency = 1,
		Size = props.size,
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.zero,
		LayoutOrder = props.order or 0,
		ZIndex = z,
	}) :: Frame
	local baseStroke = UI.stroke(UI.Theme.ink, 2.5) :: UIStroke
	local base = UI.new("Frame", {
		Name = "Base",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, depth),
		ZIndex = z,
		Parent = root,
	}, { UI.corner(radius), baseStroke }) :: Frame
	local faceStroke = UI.stroke(UI.Theme.ink, 2.5) :: UIStroke
	local face = UI.new("TextButton", {
		Name = "Face",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 1,
		Parent = root,
	}, { UI.corner(radius), faceStroke, UI.shade(0.84) }) :: TextButton
	UI.new("Frame", {
		Name = "Shine",
		BackgroundColor3 = UI.Theme.white,
		BackgroundTransparency = 0.8,
		Size = UDim2.new(1, -10, 0.38, 0),
		Position = UDim2.fromOffset(5, 3),
		ZIndex = z + 2,
		Parent = face,
	}, { UI.corner(math.max(radius - 4, 4)) })
	local label = UI.text({
		name = "Label",
		text = props.text,
		size = UDim2.new(1, -14, 1, -10),
		position = UDim2.fromOffset(7, 5),
		color = props.textColor or UI.Theme.white,
		font = props.font or UI.Font,
		maxTextSize = props.maxTextSize or 30,
		outlineThickness = 2,
		outline = UI.Theme.ink,
		zIndex = z + 3,
		parent = face,
	})
	local labelStroke = label:FindFirstChildOfClass("UIStroke") :: UIStroke
	local button: Button = {
		root = root,
		face = face,
		base = base,
		label = label,
		color = props.color or UI.Theme.green,
		enabled = true,
		faceStroke = faceStroke,
		baseStroke = baseStroke,
		labelStroke = labelStroke,
	}
	paint(button)

	local pressed = UDim2.fromOffset(0, depth - 1)
	local function release()
		TweenService:Create(face, UI.FAST, { Position = UDim2.new() }):Play()
	end
	face.MouseButton1Down:Connect(function()
		TweenService:Create(face, UI.FAST, { Position = pressed }):Play()
	end)
	face.MouseButton1Up:Connect(release)
	face.MouseLeave:Connect(release)
	face.Activated:Connect(function()
		release()
		if button.enabled then
			UI.onClick()
			props.onClick()
		end
	end)
	if props.parent then
		root.Parent = props.parent
	end
	return button
end

export type ButtonUpdate = { text: string?, color: Color3?, enabled: boolean? }

function UI.setButton(button: Button, update: ButtonUpdate)
	if update.text and button.label.Text ~= update.text then
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

-- Square menu button: a big emoji icon with a caption underneath and an
-- optional red badge (for "something to claim").
export type MenuButton = { button: Button, badge: Frame, badgeLabel: TextLabel }

function UI.menuButton(props: {
	icon: string,
	caption: string,
	color: Color3,
	size: number?,
	order: number?,
	parent: Instance?,
	onClick: () -> (),
}): MenuButton
	local size = props.size or 70
	local button = UI.button({
		name = props.caption,
		text = props.icon,
		size = UDim2.fromOffset(size, size),
		color = props.color,
		radius = 18,
		order = props.order,
		maxTextSize = 44,
		parent = props.parent,
		onClick = props.onClick,
	})
	UI.text({
		name = "Caption",
		text = props.caption,
		size = UDim2.new(1, 24, 0, 22),
		position = UDim2.new(0.5, 0, 1, 4),
		anchor = Vector2.new(0.5, 0),
		maxTextSize = 18,
		outlineThickness = 2.5,
		parent = button.root,
	})
	local badge = UI.new("Frame", {
		Name = "Badge",
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.new(1, 6, 0, -6),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = UI.Theme.red,
		Visible = false,
		ZIndex = 6,
		Parent = button.root,
	}, { UI.round(), UI.stroke(UI.Theme.white, 2.5) }) :: Frame
	local badgeLabel = UI.text({
		text = "!",
		size = UDim2.fromScale(0.8, 0.8),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		maxTextSize = 20,
		outlineThickness = 1.5,
		zIndex = 7,
		parent = badge,
	})
	return { button = button, badge = badge, badgeLabel = badgeLabel }
end

-- ===== Cards, chips, bars =====

function UI.card(props: {
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	color: Color3?,
	edge: Color3?,
	radius: number?,
	order: number?,
	name: string?,
	parent: Instance?,
}): Frame
	return UI.new("Frame", {
		Name = props.name or "Card",
		Size = props.size,
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.zero,
		BackgroundColor3 = props.color or UI.Theme.card,
		LayoutOrder = props.order or 0,
		Parent = props.parent,
	}, { UI.corner(props.radius or 16), UI.stroke(props.edge or UI.Theme.cardEdge, 2.5) }) :: Frame
end

-- Rounded pill with text, used for HUD timers and small tags.
export type Chip = { root: Frame, label: TextLabel, stroke: UIStroke }

function UI.chip(props: {
	text: string,
	size: UDim2,
	color: Color3?,
	transparency: number?,
	position: UDim2?,
	anchor: Vector2?,
	order: number?,
	maxTextSize: number?,
	name: string?,
	parent: Instance?,
}): Chip
	local color = props.color or UI.Theme.hud
	local stroke = UI.stroke(UI.darken(color, 0.45), 2.5) :: UIStroke
	local root = UI.new("Frame", {
		Name = props.name or "Chip",
		Size = props.size,
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.zero,
		BackgroundColor3 = color,
		BackgroundTransparency = props.transparency or 0.08,
		LayoutOrder = props.order or 0,
		Parent = props.parent,
	}, { UI.round(), stroke, UI.shade(0.88) }) :: Frame
	local label = UI.text({
		text = props.text,
		size = UDim2.new(1, -18, 1, -8),
		position = UDim2.fromOffset(9, 4),
		maxTextSize = props.maxTextSize or 22,
		outlineThickness = 2,
		parent = root,
	})
	return { root = root, label = label, stroke = stroke }
end

function UI.setChipColor(chip: Chip, color: Color3)
	chip.root.BackgroundColor3 = color
	chip.stroke.Color = UI.darken(color, 0.45)
end

export type Bar = { root: Frame, fill: Frame, label: TextLabel }

function UI.bar(props: {
	size: UDim2,
	position: UDim2?,
	color: Color3?,
	order: number?,
	parent: Instance?,
}): Bar
	local root = UI.new("Frame", {
		Name = "Bar",
		Size = props.size,
		Position = props.position or UDim2.new(),
		BackgroundColor3 = UI.Theme.track,
		LayoutOrder = props.order or 0,
		Parent = props.parent,
	}, { UI.round(), UI.stroke(UI.Theme.ink, 2.5) }) :: Frame
	local fill = UI.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0.5, 1),
		BackgroundColor3 = props.color or UI.Theme.green,
		Parent = root,
	}, { UI.round(), UI.shade(0.8) }) :: Frame
	local label = UI.text({
		text = "",
		size = UDim2.new(1, -16, 1, -4),
		position = UDim2.fromOffset(8, 2),
		maxTextSize = 20,
		outlineThickness = 2,
		zIndex = 2,
		parent = root,
	})
	return { root = root, fill = fill, label = label }
end

function UI.setBar(bar: Bar, fraction: number, text: string?)
	bar.fill.Size = UDim2.fromScale(math.clamp(fraction, 0.04, 1), 1)
	bar.fill.Visible = fraction > 0.001
	if text then
		bar.label.Text = text
	end
end

-- Drawn gold coin (no image assets needed).
function UI.coin(size: number, parent: Instance?): Frame
	local coin = UI.new("Frame", {
		Name = "Coin",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = UI.Theme.coin,
	}, {
		UI.round(),
		UI.stroke(UI.darken(UI.Theme.gold, 0.4), math.max(2, size / 16)),
		UI.shade(0.82),
	}) :: Frame
	UI.new("Frame", {
		Name = "Inner",
		Size = UDim2.fromScale(0.62, 0.62),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = UI.lighten(UI.Theme.coin, 0.35),
		Parent = coin,
	}, { UI.round(), UI.stroke(UI.darken(UI.Theme.gold, 0.15), math.max(1, size / 26)) })
	UI.text({
		text = "$",
		size = UDim2.fromScale(0.62, 0.62),
		position = UDim2.fromScale(0.5, 0.53),
		anchor = Vector2.new(0.5, 0.5),
		color = UI.darken(UI.Theme.gold, 0.35),
		noOutline = true,
		maxTextSize = 40,
		parent = coin,
	})
	if parent then
		coin.Parent = parent
	end
	return coin
end

-- A coin icon followed by an amount, laid out in a row.
function UI.price(props: {
	amount: string,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	color: Color3?,
	order: number?,
	parent: Instance?,
}): (Frame, TextLabel)
	local row = UI.new("Frame", {
		Name = "Price",
		BackgroundTransparency = 1,
		Size = props.size,
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.zero,
		LayoutOrder = props.order or 0,
		Parent = props.parent,
	}, {
		UI.list(
			Enum.FillDirection.Horizontal,
			6,
			Enum.HorizontalAlignment.Center,
			Enum.VerticalAlignment.Center
		),
	}) :: Frame
	local height = props.size.Y.Offset
	local coin = UI.coin(math.floor(height * 0.85), row)
	coin.LayoutOrder = 1
	local label = UI.text({
		text = props.amount,
		size = UDim2.new(0, 0, 1, 0),
		color = props.color or UI.Theme.money,
		noOutline = props.color == nil,
		maxTextSize = height,
		order = 2,
		parent = row,
	})
	label.AutomaticSize = Enum.AutomaticSize.X
	label.TextScaled = false
	label.TextWrapped = false
	label.TextSize = math.floor(height * 0.95)
	return row, label
end

-- ===== Motion =====

function UI.pop(gui: GuiObject, from: number?)
	local scale = gui:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = UI.new("UIScale", { Parent = gui })
	end
	local s = scale :: UIScale
	s.Scale = from or 1.15
	TweenService:Create(s, UI.BOUNCY, { Scale = 1 }):Play()
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

-- UIScale that fits the design canvas to a viewport.
function UI.scaleFor(viewport: Vector2): number
	return math.clamp(math.min(viewport.X / UI.DESIGN.X, viewport.Y / UI.DESIGN.Y), 0.62, 1.3)
end

function UI.viewportSize(): Vector2
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

-- A ScreenGui that scales its contents to the screen size.
function UI.screen(name: string, displayOrder: number): ScreenGui
	local gui = UI.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		DisplayOrder = displayOrder,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = false,
	}) :: ScreenGui
	local scale = UI.new("UIScale", { Parent = gui }) :: UIScale
	local function update()
		scale.Scale = UI.scaleFor(UI.viewportSize())
	end
	update()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

-- Usable design-pixel size of a screen (inside the top bar inset).
function UI.canvasSize(): Vector2
	local viewport = UI.viewportSize()
	local scale = UI.scaleFor(viewport)
	return Vector2.new(viewport.X / scale, (viewport.Y - UI.topInset()) / scale)
end

-- 3D preview of a model in the UI. The model faces -Z, so the camera sits in front.
function UI.viewport(model: Model, size: UDim2, parent: Instance?, angle: number?): ViewportFrame
	local frame = UI.new("ViewportFrame", {
		Name = "Preview",
		BackgroundTransparency = 1,
		Size = size,
		Ambient = Color3.fromRGB(200, 196, 210),
		LightColor = Color3.fromRGB(255, 248, 235),
		LightDirection = Vector3.new(-0.5, -1, 0.6),
	}) :: ViewportFrame
	local camera = UI.new("Camera", { FieldOfView = 32, Parent = frame }) :: Camera
	frame.CurrentCamera = camera
	model.Parent = frame
	local cf, extents = model:GetBoundingBox()
	local radius = extents.Magnitude / 2
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 1.0
	local yaw = math.rad(angle or 35)
	local direction = Vector3.new(-math.sin(yaw), 0.32, -math.cos(yaw)).Unit
	camera.CFrame = CFrame.lookAt(cf.Position + direction * distance, cf.Position)
	if parent then
		frame.Parent = parent
	end
	return frame
end

return UI
