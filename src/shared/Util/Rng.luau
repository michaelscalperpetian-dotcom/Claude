--!strict
-- Deterministic pseudo-random numbers (mulberry32). Used for things every
-- server and client must agree on without talking to each other, like which
-- storm is coming and what the egg shop has in stock. Pure: runs under Lune too.

local Rng = {}

local TWO_32 = 4294967296

local function imul(a: number, b: number): number
	local ah = bit32.rshift(a, 16)
	local al = bit32.band(a, 0xFFFF)
	local bh = bit32.rshift(b, 16)
	local bl = bit32.band(b, 0xFFFF)
	local high = bit32.band(ah * bl + al * bh, 0xFFFF)
	return (al * bl + high * 65536) % TWO_32
end

export type Generator = {
	next: () -> number,
	int: (min: number, max: number) -> number,
}

-- Mix two integers into a 32-bit seed.
function Rng.hash(a: number, b: number): number
	local h = (math.floor(a) % TWO_32 + imul(math.floor(b) % TWO_32, 0x9E3779B1)) % TWO_32
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = imul(h, 0x85EBCA6B)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = imul(h, 0xC2B2AE35)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h
end

function Rng.new(seed: number): Generator
	local state = math.floor(seed) % TWO_32

	local function nextFloat(): number
		state = (state + 0x6D2B79F5) % TWO_32
		local t = state
		t = imul(bit32.bxor(t, bit32.rshift(t, 15)), bit32.bor(t, 1))
		t = bit32.bxor(t, (t + imul(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(t, 61))) % TWO_32)
		return bit32.bxor(t, bit32.rshift(t, 14)) / TWO_32
	end

	local function int(min: number, max: number): number
		return min + math.floor(nextFloat() * (max - min + 1))
	end

	return {
		next = nextFloat,
		int = int,
	}
end

return Rng
