--!strict
-- Tiny UI toolkit: one theme, a few element builders, juicy buttons, 3D
-- previews, and a responsive scale so layouts work from phones to desktops.
-- UI here is built in code; layouts use anchors + Scale positions, sizes are in
-- design pixels and a UIScale fits them to the screen.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local UI = {}

UI.Theme = {
	ink = Color3.fromRGB(35, 30, 45),
	panel = Color3.fromRGB(255, 249, 236),
	panelDark = Color3.fromRGB(240, 228, 205),
	hud = Color3.fromRGB(28, 32, 46),
	white = Color3.fromRGB(255, 255, 255),
	gold = Color3.fromRGB(255, 205, 60),
	green = Color3.fromRGB(90, 200, 90),
	blue = Color3.fromRGB(70, 150, 255),
	red = Color3.fromRGB(240, 80, 80),
	orange = Color3.fromRGB(255, 150, 50),
	purple = Color3.fromRGB(160, 100, 255),
	grey = Color3.fromRGB(160, 160, 170),
	night = Color3.fromRGB(90, 100, 200),
}

UI.Font = Enum.Font.FredokaOne
UI.BodyFont = Enum.Font.GothamBold

UI.FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
UI.BOUNCY = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
UI.SMOOTH = TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

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

-- Decorators return `any` so they can be mixed in one children list.
function UI.corner(radius: number?): any
	return UI.new("UICorner", { CornerRadius = UDim.new(0, radius or 14) })
end

function UI.stroke(color: Color3?, thickness: number?): any
	return UI.new("UIStroke", {
		Color = color or UI.Theme.ink,
		Thickness = thickness or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UI.padding(px: number): any
	local u = UDim.new(0, px)
	return UI.new(
		"UIPadding",
		{ PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u }
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

export type TextProps = {
	text: string,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	color: Color3?,
	font: Enum.Font?,
	stroke: boolean?,
	align: Enum.TextXAlignment?,
	maxTextSize: number?,
	parent: Instance?,
	order: number?,
	wrap: boolean?,
}

function UI.text(props: TextProps): TextLabel
	local label = UI.new("TextLabel", {
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
		TextStrokeTransparency = if props.stroke == false then 1 else 0.4,
		LayoutOrder = props.order or 0,
	}) :: TextLabel
	UI.new(
		"UITextSizeConstraint",
		{ MaxTextSize = props.maxTextSize or 40, MinTextSize = 8, Parent = label }
	)
	if props.parent then
		label.Parent = props.parent
	end
	return label
end

export type ButtonProps = {
	text: string,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	color: Color3?,
	textColor: Color3?,
	parent: Instance?,
	order: number?,
	maxTextSize: number?,
	onClick: () -> (),
}

-- Chunky button with a press pop.
function UI.button(props: ButtonProps): TextButton
	local button = UI.new("TextButton", {
		Text = props.text,
		Size = props.size,
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.zero,
		BackgroundColor3 = props.color or UI.Theme.green,
		TextColor3 = props.textColor or UI.Theme.white,
		Font = UI.Font,
		TextScaled = true,
		TextStrokeTransparency = 0.5,
		AutoButtonColor = false,
		LayoutOrder = props.order or 0,
	}, {
		UI.corner(12),
		UI.stroke(UI.Theme.ink, 3),
		UI.padding(6),
	}) :: TextButton
	UI.new(
		"UITextSizeConstraint",
		{ MaxTextSize = props.maxTextSize or 30, MinTextSize = 8, Parent = button }
	)
	local scale = UI.new("UIScale", { Parent = button }) :: UIScale
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, UI.FAST, { Scale = 0.92 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, UI.BOUNCY, { Scale = 1 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, UI.BOUNCY, { Scale = 1 }):Play()
	end)
	button.Activated:Connect(function()
		TweenService:Create(scale, UI.BOUNCY, { Scale = 1 }):Play()
		if button:GetAttribute("Disabled") == true then
			return
		end
		props.onClick()
	end)
	if props.parent then
		button.Parent = props.parent
	end
	return button
end

function UI.setEnabled(button: TextButton, enabled: boolean, color: Color3)
	button:SetAttribute("Disabled", not enabled)
	button.BackgroundColor3 = if enabled then color else UI.Theme.grey
end

function UI.pop(gui: GuiObject)
	local scale = gui:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = UI.new("UIScale", { Parent = gui })
	end
	local s = scale :: UIScale
	s.Scale = 1.15
	TweenService:Create(s, UI.BOUNCY, { Scale = 1 }):Play()
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
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local size = camera.ViewportSize
		scale.Scale = math.clamp(math.min(size.X / 1150, size.Y / 650), 0.62, 1.3)
	end
	update()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

-- 3D preview of a model in the UI. The model faces -Z, so the camera sits in front.
function UI.viewport(model: Model, size: UDim2, parent: Instance?, angle: number?): ViewportFrame
	local frame = UI.new("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = size,
		Ambient = Color3.fromRGB(190, 190, 200),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.5, -1, 0.6),
	}) :: ViewportFrame
	local camera = UI.new("Camera", { FieldOfView = 35, Parent = frame }) :: Camera
	frame.CurrentCamera = camera
	model.Parent = frame
	local cf, extents = model:GetBoundingBox()
	local radius = extents.Magnitude / 2
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 1.02
	local yaw = math.rad(angle or 35)
	local direction = Vector3.new(-math.sin(yaw), 0.35, -math.cos(yaw)).Unit
	camera.CFrame = CFrame.lookAt(cf.Position + direction * distance, cf.Position)
	if parent then
		frame.Parent = parent
	end
	return frame
end

function UI.rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

return UI
