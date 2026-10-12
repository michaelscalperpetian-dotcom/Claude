--!strict
-- The game's colours in one place, so the world and the UI share one cartoon
-- look: a limited, saturated palette with 2-3 shades per material (light top,
-- base, dark edge) instead of many unrelated colours.

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Palette = {
	-- World materials (light, base, dark)
	grassLight = rgb(155, 227, 110),
	grass = rgb(123, 211, 90),
	grassDark = rgb(93, 183, 74),
	grassDeep = rgb(74, 158, 60),
	leafLight = rgb(126, 214, 92),
	leaf = rgb(88, 186, 74),
	leafDark = rgb(60, 150, 70),
	pine = rgb(62, 155, 90),
	pineDark = rgb(45, 125, 78),
	sandLight = rgb(250, 228, 160),
	sand = rgb(242, 214, 138),
	sandDark = rgb(226, 190, 110),
	path = rgb(236, 200, 134),
	pathEdge = rgb(214, 172, 108),
	dirt = rgb(201, 139, 85),
	dirtDark = rgb(168, 107, 62),
	water = rgb(79, 195, 247),
	waterDeep = rgb(46, 155, 219),
	shallows = rgb(118, 220, 236),
	foam = rgb(250, 254, 255),
	woodLight = rgb(205, 145, 92),
	wood = rgb(181, 122, 74),
	woodDark = rgb(142, 90, 52),
	stoneLight = rgb(214, 210, 224),
	stone = rgb(185, 180, 199),
	stoneDark = rgb(150, 144, 168),
	plaza = rgb(222, 196, 160),
	plazaDark = rgb(196, 166, 128),
	rockLava = rgb(132, 104, 98),
	rockLavaDark = rgb(96, 74, 76),
	lava = rgb(255, 122, 26),
	lavaHot = rgb(255, 196, 74),
	cream = rgb(255, 246, 225),
	white = rgb(255, 255, 255),
	lampGlow = rgb(255, 224, 138),

	-- Accents (one per nest, also used by UI)
	red = rgb(255, 93, 93),
	orange = rgb(255, 159, 67),
	yellow = rgb(255, 217, 61),
	blue = rgb(93, 173, 236),
	purple = rgb(168, 139, 235),
	pink = rgb(255, 143, 199),
	mint = rgb(110, 231, 183),
	teal = rgb(72, 201, 196),
}

-- Nest accent colours, in plot order.
Palette.NEST_ACCENTS = {
	Palette.red,
	Palette.orange,
	Palette.yellow,
	Palette.mint,
	Palette.blue,
	Palette.purple,
	Palette.pink,
	Palette.teal,
}

Palette.FLOWERS = {
	Palette.pink,
	Palette.yellow,
	Palette.purple,
	Palette.white,
	Palette.red,
	Palette.orange,
}

return Palette
