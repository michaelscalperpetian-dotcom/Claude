--!strict
-- Number and time formatting for UI text.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

-- 950 -> "950", 12345 -> "12.3K", 4500000 -> "4.5M"
function Format.number(n: number): string
	if n ~= n then
		return "0"
	end
	local negative = n < 0
	local value = math.abs(n)
	if value < 1000 then
		local whole = if value >= 100 or value == math.floor(value)
			then string.format("%d", math.floor(value))
			else string.format("%.1f", value)
		return (if negative then "-" else "") .. whole
	end
	local index = 1
	while value >= 1000 and index < #SUFFIXES do
		value /= 1000
		index += 1
	end
	local text
	if value >= 100 then
		text = string.format("%d", math.floor(value))
	else
		text = string.format("%.1f", math.floor(value * 10) / 10)
		text = string.gsub(text, "%.0$", "")
	end
	return (if negative then "-" else "") .. text .. SUFFIXES[index]
end

-- 75 -> "1:15", 3725 -> "1:02:05"
function Format.time(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	local h = math.floor(s / 3600)
	local m = math.floor((s % 3600) / 60)
	local sec = s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, sec)
	end
	return string.format("%d:%02d", m, sec)
end

-- 45 -> "45s", 300 -> "5m", 5400 -> "1h 30m"
function Format.duration(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s < 60 then
		return `{s}s`
	elseif s < 3600 then
		local m = math.floor(s / 60)
		local rest = s % 60
		return if rest > 0 then `{m}m {rest}s` else `{m}m`
	end
	local h = math.floor(s / 3600)
	local m = math.floor((s % 3600) / 60)
	return if m > 0 then `{h}h {m}m` else `{h}h`
end

return Format
