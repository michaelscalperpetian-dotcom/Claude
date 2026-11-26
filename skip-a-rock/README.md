# Still Lake

A small, calm Roblox game about skipping stones across a mountain lake.

Walk down to the water, hold to wind up, and let go when the needle swings into the gold. The stone skims across the lake, hop after hop, each one shorter and quicker, with a ripple and a little *plip* every time it touches. Sparkling stones wash up on the beach now and then. Pick them up to find flatter, rarer stones that skip further. The day turns slowly into a starry night, the lanterns come on and fireflies drift over the beach. Some stones skip best by moonlight.

No timers, no shop, no pressure. Just you, a lake, and the next good throw.

---

## Play it in Roblox Studio (about 2 minutes)

1. Install [Roblox Studio](https://create.roblox.com/) (free) and sign in.
2. Download **[`build/StillLake.rbxlx`](build/StillLake.rbxlx)** from this repo.
3. Open it: double-click the file, or in Studio use **File → Open from File**.
4. Press **▶ Play** (F5). The lake builds itself when the game starts.

In Studio's edit view you'll only see a "Press Play" sign: the whole valley (terrain, lake, mountains, docks, cabin and forest) is built by code at start-up. It takes a few seconds; you'll see "The lake is waking up…" until you spawn.

> Progress doesn't save in Studio until you publish the game and turn on API access (see below). Until then you'll see a warning in Output; that's expected, and the leaderboards show the players in your test server instead.

## How to play

| | Computer | Phone / tablet | Gamepad |
|---|---|---|---|
| Wind up and throw | Hold the **left mouse button**, let go | Hold the **Throw** button, let go | Hold **R2**, let go |
| Aim | Look where you want to throw (the camera) | Drag to turn the camera | Right stick |
| Pick up a glinting stone | **E** | Tap the prompt | **X** |
| Open the journal | **J**, or click your stone (bottom left) | Tap your stone | **Y** |

- The **power meter** appears next to you when you're close enough to the water. The needle swings up and back down while you hold.
- Let go in the **gold zone** for lots of skips. The bright line in the middle is a **perfect release** (+3 skips).
- At the very top (red) the stone is thrown **too hard** and dives straight in. Barely holding at all, it just **plops**.
- Throw from the beach or from the end of one of the three **docks**. Skip one all the way across the lake for a special goal.

## What there is to do

**12 stones to collect.** You start with a Pebble. The rest wash up as glints on the beach (ten at a time, new ones every minute or so). Flatter stones skip more times; heavier stones fly further on each hop.

| Stone | Rarity | Chance per glint | Notes |
|---|---|---|---|
| Pebble | Common | — | Everyone starts with one |
| River Stone, Sandstone | Common | 23% each | |
| Slate, Sea Glass, Basalt | Uncommon | 12–14% each | |
| Jade, Rose Quartz, Obsidian | Rare | 4–5% each | |
| Moonstone | Epic | 1.5% | +25% skips at night |
| Amber | Epic | 1.5% | |
| Starstone | Legendary | 0.6% | The best skipper there is |

**19 journal goals:** 5 to 30 skips in one throw, 50 to 150-stud throws, perfect releases, finding stones, skipping at night, crossing the whole lake, and skipping hundreds of stones.

**Titles** float over your head as your best throw grows: Ripple Rookie (5 skips), Splash Artist (10), Skimmer (15), Lake Dancer (20), Stone Whisperer (25) and Legend of Still Lake (30). The top title needs one of the best stones and a near-perfect throw.

**Leaderboards** by the cabin show the most skips in one throw and the longest throw across every server. Your best throw also shows in the player list.

**A day on the lake** lasts 20 minutes: about 14 minutes of daylight, then dusk, a starry night and dawn. At night the lanterns, cabin windows and fireflies come on.

Sit on the cabin porch or round the campfire if you just want to watch the water.

## Test tools

While playing in Studio, click **🧪 Test** (top right). It has buttons for every stone, night, day, a fresh set of glints, and starting over. In a live game only the game's owner (and anyone you add to `DEV_USER_IDS` in `src/shared/Config.luau`) sees it.

## Publish it

1. In Studio: **File → Publish to Roblox**.
2. **Game Settings → Security → Enable Studio Access to API Services** (so saving works when you test in Studio too).
3. Set the game to public when you're happy with it.

Saving uses session-locked DataStores (a player's progress can never be loaded by two servers at once), autosaves every 2 minutes and saves on leave and shutdown.

### Optional: background music

The game is quiet by default, with only water sounds. To add calm music, put Roblox audio asset ids in `MUSIC_TRACKS` in `src/shared/Config.luau` (for example tracks from the Creator Store's music library). They play in a loop, softly.

---

## For developers

The game is written in strict Luau and synced with [Rojo](https://rojo.space/). Everything (the world included) is code; there are no hand-made parts or uploaded assets, and every sound ships with Roblox. The valley is real Roblox terrain (smooth voxels, terrain water with waves and reflections, swaying grass and volumetric clouds) written from a heightmap when the server starts; the buildings, docks and forest are parts with real materials on top.

```
src/shared/      Rules and data both sides use
  Skip.luau        How a throw goes: the power needle, skips, hop lengths
  Lake.luau        The lake's shape, the docks, where a throw first touches
  Land.luau        The valley's heightmap and which terrain material goes where
  Data/            The 12 stones and the journal goals
  DayCycle.luau    The day and night clock
src/server/
  Systems/         Saving, sessions, throws, glints, progress, leaderboards, day/night, test tools
  Lib/Ground.luau  Writes the terrain (lake bowl, beach, meadow, mountains, water, clouds)
  Lib/Scenery.luau Builds the docks, cabin, campfire, lanterns, forest and signs on top
src/client/
  Controllers/     Throw input, HUD and power meter, stone flights and ripples,
                   journal, messages, night ambience, sound, test panel
tests/           Lune tests that run the real code in fake Roblox servers and clients
tools/           Scene and UI exporters, and a terrain preview renderer
```

How it fits together:

- **The server decides every throw.** The client only says when you started winding up and when you let go (with your hold time and the way you're facing). The server checks you're near the water and facing it, that the hold time matches its own clock, and the cooldown. It then works out every skip, saves the result and tells every player, so everyone sees the same stone.
- **Every client draws every throw** from that one message: the arc to the water, each hop, the ripples, splashes and plips.
- **The world is walled** with invisible walls along the top of the bank and around the docks, so nobody walks into the lake. The camera passes through them. Anyone who somehow ends up in the water is put back by the spawn.
- **The lake has a sandy shelf and a short bank** rather than a gentle slope, because terrain voxels are 4 studs and hold either sand or water. This way every spot where a stone can touch down is real water (a test checks it all the way round).

Commands (run inside `still-lake/`; install the toolchain from the repo root with `rokit install`):

```sh
lune run tests/run            # unit tests: skip rules, lake geometry, stones, goals, day cycle
lune run tests/integration    # the real server systems in a fake server: a full play session
lune run tests/client_smoke   # every client controller in a fake client
stylua --check src tests      # formatting
selene src                    # lint
rojo build default.project.json -o build/StillLake.rbxlx
rojo serve                    # live-sync into Studio while editing
```

Most numbers you'd want to tune are in `src/shared/Config.luau` (lake size, throw reach, cooldown, glints, day length) and `src/shared/Skip.luau` (the power needle and how skips are counted). The unit tests check the balance still holds, for example that a Pebble can't reach the top title and a perfect Starstone throw can.
