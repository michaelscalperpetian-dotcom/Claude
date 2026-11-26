--!strict
-- The colours of Skip a Rock, shared by the world and the UI: a bright,
-- breezy seaside with sun-bleached wood and a deep blue ocean.

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Palette = {
	-- Water: terrain water by day and by night, ripples
	seaDay = rgb(34, 112, 156),
	seaNight = rgb(16, 34, 64),
	ripple = rgb(232, 250, 255),

	-- Shore and land
	pebbleLight = rgb(204, 194, 176),
	pebble = rgb(178, 166, 148),
	pebbleDark = rgb(144, 132, 118),
	sand = rgb(228, 208, 168),
	path = rgb(196, 168, 124),
	grassLight = rgb(160, 206, 112),
	grass = rgb(128, 186, 94),
	grassDark = rgb(98, 160, 80),
	moss = rgb(112, 150, 82),

	-- Plants
	leafLight = rgb(138, 196, 98),
	leaf = rgb(102, 170, 84),
	leafDark = rgb(72, 138, 76),
	pine = rgb(60, 106, 70),
	pineDark = rgb(44, 84, 60),
	reed = rgb(150, 162, 92),
	reedDark = rgb(116, 132, 74),
	cattail = rgb(120, 82, 56),
	lily = rgb(92, 168, 96),

	-- Wood and stone (lighter than they look: wood textures darken them)
	woodLight = rgb(206, 164, 116),
	wood = rgb(178, 132, 90),
	woodDark = rgb(128, 92, 64),
	bark = rgb(116, 86, 64),
	logs = rgb(160, 112, 72),
	weathered = rgb(166, 150, 128),
	rope = rgb(200, 178, 132),
	iron = rgb(58, 56, 60),
	brass = rgb(214, 170, 82),
	window = rgb(164, 206, 226),
	rockLight = rgb(176, 174, 182),
	rock = rgb(146, 144, 156),
	rockDark = rgb(112, 110, 124),
	mountain = rgb(132, 136, 168),
	mountainDark = rgb(104, 108, 142),
	snow = rgb(246, 248, 255),

	-- Warm accents
	lantern = rgb(255, 204, 120),
	fire = rgb(255, 150, 60),
	ember = rgb(255, 110, 40),
	roof = rgb(150, 74, 62),
	cream = rgb(255, 246, 228),
	white = rgb(255, 255, 255),

	-- Seaside
	buoyRed = rgb(226, 72, 64),
	buoyWhite = rgb(246, 244, 238),
	canvas = rgb(244, 236, 214),
	awningBlue = rgb(70, 140, 214),
	awningRed = rgb(222, 86, 76),
	awningYellow = rgb(246, 196, 76),
	palmTrunk = rgb(150, 112, 76),
	palmLeaf = rgb(72, 150, 76),
	crystal = rgb(150, 220, 255),

	-- Flowers
	pink = rgb(246, 152, 184),
	yellow = rgb(250, 214, 92),
	purple = rgb(176, 148, 226),
	red = rgb(232, 98, 92),
	orange = rgb(246, 160, 82),
	blue = rgb(120, 170, 236),
}

Palette.FLOWERS = { Palette.pink, Palette.yellow, Palette.purple, Palette.white, Palette.orange }

return Palette
