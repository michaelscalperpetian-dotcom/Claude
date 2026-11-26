--!strict
-- The colours of Still Lake, shared by the world and the UI: a calm,
-- golden-hour mountain lake with soft, slightly dusty tones.

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Palette = {
	-- Water, from the shallows out to the deep middle
	shallows = rgb(126, 206, 214),
	water = rgb(84, 172, 204),
	deep = rgb(56, 132, 178),
	ripple = rgb(232, 250, 255),

	-- Shore and land
	pebbleLight = rgb(214, 204, 186),
	pebble = rgb(190, 178, 160),
	pebbleDark = rgb(152, 140, 124),
	sand = rgb(228, 208, 168),
	grassLight = rgb(160, 206, 112),
	grass = rgb(128, 186, 94),
	grassDark = rgb(98, 160, 80),
	moss = rgb(112, 150, 82),

	-- Plants
	leafLight = rgb(138, 196, 98),
	leaf = rgb(102, 170, 84),
	leafDark = rgb(72, 138, 76),
	pine = rgb(66, 130, 92),
	pineDark = rgb(48, 104, 80),
	reed = rgb(150, 162, 92),
	cattail = rgb(120, 82, 56),
	lily = rgb(92, 168, 96),

	-- Wood and stone
	woodLight = rgb(198, 150, 104),
	wood = rgb(166, 118, 78),
	woodDark = rgb(122, 84, 58),
	rockLight = rgb(176, 174, 182),
	rock = rgb(146, 144, 156),
	rockDark = rgb(112, 110, 124),
	mountain = rgb(132, 136, 168),
	mountainDark = rgb(104, 108, 142),
	snow = rgb(246, 248, 255),

	-- Warm accents
	lantern = rgb(255, 204, 120),
	fire = rgb(255, 150, 60),
	roof = rgb(176, 86, 72),
	cream = rgb(255, 246, 228),
	white = rgb(255, 255, 255),

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
