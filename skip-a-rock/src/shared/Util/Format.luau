--!strict
-- Big numbers the simulator way: 950, 1.2K, 34.5M, 7B, 1.25T, 3Qa…

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- A short number: three significant figures and a suffix.
function Format.short(value: number): string
	if value ~= value then
		return "0"
	end
	local sign = if value < 0 then "-" else ""
	local n = math.abs(value)
	if n < 1000 then
		return sign .. tostring(math.floor(n))
	end
	local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
	local scaled = n / 10 ^ (tier * 3)
	-- rounding can carry over to the next tier (999.96K -> 1M)
	local digits = if scaled >= 100 then 0 elseif scaled >= 10 then 1 else 2
	local rounded = math.floor(scaled * 10 ^ digits + 0.5) / 10 ^ digits
	if rounded >= 1000 and tier < #SUFFIXES - 1 then
		tier += 1
		rounded /= 1000
		digits = 2
	end
	local text = string.format(`%.{digits}f`, rounded)
	-- drop trailing zeros: 1.50K -> 1.5K, 2.00M -> 2M
	if string.find(text, ".", 1, true) then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return sign .. text .. SUFFIXES[tier + 1]
end

-- A whole number with thousands separators: 1,234,567 (for exact counts).
function Format.commas(value: number): string
	local s = tostring(math.floor(math.abs(value)))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return (if value < 0 then "-" else "") .. out
end

-- A distance in studs: "84 studs", "12.4K studs".
function Format.distance(studs: number): string
	return Format.short(studs) .. " studs"
end

return Format
