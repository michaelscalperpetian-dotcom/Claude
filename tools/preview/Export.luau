--!nocheck
-- Turns Roblox instances (from the Lune test environments) into plain JSON so
-- the Python preview renderers can draw them: 3D parts for scene renders and
-- GUI trees for UI screenshots.

local Export = {}

local function color(c)
	return { c.R, c.G, c.B }
end

local function enumName(value)
	if value == nil then
		return nil
	end
	local s = tostring(value)
	return string.match(s, "([^%.]+)$") or s
end

local function udim2(u)
	return { u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset }
end

local function udim(u)
	return { u.Scale, u.Offset }
end

local function cframe(cf)
	return { cf:GetComponents() }
end

local function safe(instance, property)
	local ok, value = pcall(function()
		return instance[property]
	end)
	if ok then
		return value
	end
	return nil
end

-- ===== 3D parts =====

function Export.part(part)
	local shape = "Block"
	if part.ClassName == "WedgePart" then
		shape = "Wedge"
	elseif part.ClassName == "CornerWedgePart" then
		shape = "CornerWedge"
	else
		local s = safe(part, "Shape")
		if s then
			shape = enumName(s)
		end
	end
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	if mesh and enumName(mesh.MeshType) == "Sphere" then
		shape = "Ellipsoid"
	end
	local lights = {}
	for _, child in part:GetChildren() do
		if child:IsA("PointLight") or child:IsA("SurfaceLight") or child:IsA("SpotLight") then
			table.insert(
				lights,
				{ color = color(child.Color), range = child.Range, brightness = child.Brightness }
			)
		end
	end
	return {
		name = part.Name,
		shape = shape,
		cf = cframe(part.CFrame),
		size = { part.Size.X, part.Size.Y, part.Size.Z },
		color = color(part.Color),
		transparency = part.Transparency,
		reflectance = part.Reflectance,
		material = enumName(part.Material),
		castShadow = part.CastShadow,
		lights = if #lights > 0 then lights else nil,
	}
end

-- Every visible BasePart under `root`, skipping anything under `exclude`.
function Export.parts(root, exclude)
	local out = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			local skip = false
			if exclude then
				for _, e in exclude do
					if d:IsDescendantOf(e) then
						skip = true
						break
					end
				end
			end
			if not skip then
				table.insert(out, Export.part(d))
			end
		end
	end
	return out
end

-- ===== GUI =====

local GUI_PROPS = {
	"Visible",
	"ZIndex",
	"LayoutOrder",
	"Rotation",
	"BackgroundTransparency",
	"ClipsDescendants",
	"Text",
	"TextScaled",
	"TextSize",
	"TextWrapped",
	"TextTransparency",
	"TextStrokeTransparency",
	"ImageTransparency",
	"Image",
	"ScrollBarThickness",
	"RichText",
	"LineHeight",
	"BorderSizePixel",
	"GroupTransparency",
}

local MODIFIERS = {
	UICorner = function(m)
		return { radius = udim(m.CornerRadius) }
	end,
	UIStroke = function(m)
		local gradient = m:FindFirstChildOfClass("UIGradient")
		return {
			color = color(m.Color),
			thickness = m.Thickness,
			transparency = m.Transparency,
			mode = enumName(m.ApplyStrokeMode),
			enabled = m.Enabled,
			gradient = gradient and Export.gradient(gradient) or nil,
		}
	end,
	UIGradient = function(m)
		return Export.gradient(m)
	end,
	UIPadding = function(m)
		return {
			top = udim(m.PaddingTop),
			bottom = udim(m.PaddingBottom),
			left = udim(m.PaddingLeft),
			right = udim(m.PaddingRight),
		}
	end,
	UIListLayout = function(m)
		return {
			direction = enumName(m.FillDirection),
			padding = udim(m.Padding),
			halign = enumName(m.HorizontalAlignment),
			valign = enumName(m.VerticalAlignment),
			sort = enumName(m.SortOrder),
			wraps = safe(m, "Wraps"),
		}
	end,
	UIGridLayout = function(m)
		return {
			cellSize = udim2(m.CellSize),
			cellPadding = udim2(m.CellPadding),
			direction = enumName(m.FillDirection),
			halign = enumName(m.HorizontalAlignment),
			valign = enumName(m.VerticalAlignment),
			sort = enumName(m.SortOrder),
			maxCells = m.FillDirectionMaxCells,
		}
	end,
	UIScale = function(m)
		return { scale = m.Scale }
	end,
	UITextSizeConstraint = function(m)
		return { max = m.MaxTextSize, min = m.MinTextSize }
	end,
	UISizeConstraint = function(m)
		-- MaxSize defaults to infinity, which JSON can't hold.
		local function finite(v)
			return math.min(v, 1e9)
		end
		return {
			min = { m.MinSize.X, m.MinSize.Y },
			max = { finite(m.MaxSize.X), finite(m.MaxSize.Y) },
		}
	end,
	UIAspectRatioConstraint = function(m)
		return {
			ratio = m.AspectRatio,
			type = enumName(m.AspectType),
			axis = enumName(m.DominantAxis),
		}
	end,
	UIShadow = function(m)
		return {
			color = color(m.Color),
			transparency = m.Transparency,
			blur = udim(m.BlurRadius),
			offset = udim2(m.Offset),
			spread = udim2(m.Spread),
			enabled = m.Enabled,
		}
	end,
}

function Export.gradient(g)
	local colors = {}
	for _, k in g.Color.Keypoints do
		table.insert(colors, { k.Time, k.Value.R, k.Value.G, k.Value.B })
	end
	local transparency = {}
	for _, k in g.Transparency.Keypoints do
		table.insert(transparency, { k.Time, k.Value })
	end
	return {
		colors = colors,
		transparency = transparency,
		rotation = g.Rotation,
		offset = { g.Offset.X, g.Offset.Y },
		enabled = g.Enabled,
	}
end

function Export.gui(instance)
	local node = { class = instance.ClassName, name = instance.Name, children = {}, modifiers = {} }
	if instance:IsA("GuiObject") then
		node.position = udim2(instance.Position)
		node.size = udim2(instance.Size)
		node.anchor = { instance.AnchorPoint.X, instance.AnchorPoint.Y }
		node.background = color(instance.BackgroundColor3)
		node.border = color(instance.BorderColor3)
		for _, prop in GUI_PROPS do
			local value = safe(instance, prop)
			if value ~= nil then
				node[prop] = value
			end
		end
		local textColor = safe(instance, "TextColor3")
		if textColor then
			node.textColor = color(textColor)
			node.textStrokeColor = color(instance.TextStrokeColor3)
			node.font = enumName(safe(instance, "Font")) or "SourceSans"
			node.xalign = enumName(instance.TextXAlignment)
			node.yalign = enumName(instance.TextYAlignment)
		end
		local imageColor = safe(instance, "ImageColor3")
		if imageColor then
			node.imageColor = color(imageColor)
		end
		local automatic = safe(instance, "AutomaticSize")
		if automatic then
			node.automaticSize = enumName(automatic)
		end
		local canvas = safe(instance, "CanvasSize")
		if canvas then
			node.canvasSize = udim2(canvas)
			node.automaticCanvas = enumName(safe(instance, "AutomaticCanvasSize"))
			node.scrollDirection = enumName(safe(instance, "ScrollingDirection"))
		end
	elseif instance:IsA("ScreenGui") then
		node.displayOrder = instance.DisplayOrder
		node.enabled = instance.Enabled
		node.ignoreGuiInset = instance.IgnoreGuiInset
	end
	if instance:IsA("ViewportFrame") then
		local camera = safe(instance, "CurrentCamera") or instance:FindFirstChildOfClass("Camera")
		node.camera = camera and { cf = cframe(camera.CFrame), fov = camera.FieldOfView } or nil
		node.parts = Export.parts(instance)
		node.imageColor = color(instance.ImageColor3)
		node.ambient = color(instance.Ambient)
		node.lightColor = color(instance.LightColor)
		node.lightDirection =
			{ instance.LightDirection.X, instance.LightDirection.Y, instance.LightDirection.Z }
	end
	for _, child in instance:GetChildren() do
		local modifier = MODIFIERS[child.ClassName]
		if modifier then
			local ok, data = pcall(modifier, child)
			if ok then
				node.modifiers[child.ClassName] = data
			end
		elseif child:IsA("GuiObject") then
			table.insert(node.children, Export.gui(child))
		end
	end
	return node
end

function Export.screens(playerGui)
	local screens = {}
	for _, child in playerGui:GetChildren() do
		if child:IsA("ScreenGui") then
			local node = Export.gui(child)
			for _, c in child:GetChildren() do
				if c:IsA("UIScale") then
					node.modifiers.UIScale = { scale = c.Scale }
				end
			end
			table.insert(screens, node)
		end
	end
	table.sort(screens, function(a, b)
		return (a.displayOrder or 0) < (b.displayOrder or 0)
	end)
	return screens
end

return Export
