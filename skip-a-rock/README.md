# Skip a Rock

A Roblox skipping simulator on a sunny seaside boardwalk, facing an ocean that never ends.

Walk down to the beach or out onto a pier, hold to wind up, and let go when the needle swings into the gold. Your rock skips straight out to sea, hop after hop, and every throw pays coins for how far it went. Spend them on arm strength and better rocks, rebirth for a permanent boost, and skip past islands far out at sea for lasting bonuses. The numbers keep growing: there's always a further buoy, a better rock and another island over the horizon.

---

## Play it in Roblox Studio (about 2 minutes)

1. Install [Roblox Studio](https://create.roblox.com/) (free) and sign in.
2. Download **[`build/SkipARock.rbxlx`](build/SkipARock.rbxlx)** from this repo.
3. Open it: double-click the file, or in Studio use **File → Open from File**.
4. Press **▶ Play** (F5).

In Studio's edit view you'll only see a "Press Play" sign: the whole coast (terrain, ocean, boardwalk, piers and islands) is built by code at start-up. It takes a few seconds; you'll see "The tide is coming in…" until you spawn on the boardwalk.

> Progress doesn't save in Studio until you publish the game and turn on API access (see below). Until then you'll see a warning in Output; that's expected, and the leaderboards show the players in your test server instead.

## How to play

| | Computer | Phone / tablet | Gamepad |
|---|---|---|---|
| Wind up and throw | Hold the **left mouse button**, let go | Hold the **Throw** button, let go | Hold **R2**, let go |
| Open the menu | **M**, or the buttons on the left | The buttons on the left | **Y** |
| Pick up treasure | **E** | Tap the prompt | **X** |

- Throw from **the beach or the five piers**. The power meter appears next to you there.
- Let go in the **gold zone** for lots of skips. The bright line in the middle is a **perfect release**: +3 skips and +25% coins.
- At the very top (red) the rock is thrown **too hard** and dives straight in. Barely holding at all, it just **plops**.
- Your rock always flies straight out to sea. A **chase camera** follows it; click or press throw to skip it, or turn it off with 🎥.

## The loop

1. **Throw.** Coins = distance ÷ 10 + 2 per skip, times your coin multiplier.
2. **Upgrade your arm** (💪, or the Strength Gym on the boardwalk). Each level throws 10% further; each costs a bit more than the last.
3. **Buy better rocks** (🪨, or the Rock Shop). Each throws much further, and the flatter ones skip more. Your best one goes straight into your hand.
4. **Rebirth** (🔁, or the Rebirth Shrine) when you can afford it. Your coins and arm strength reset, but you keep every rock and island, earn +50% coins and throw +20% further for good.
5. **Reach islands.** Skip a rock past one for the first time and it gives you a lasting coin bonus, and some unlock new rocks.

| Rock | Price | Distance | Needs |
|---|---|---|---|
| Pebble | free | x1 | |
| River Stone | 120 | x1.6 | |
| Slate | 1.5K | x2.6 | |
| Sea Glass | 15K | x4.2 | |
| Basalt | 150K | x7 | Gull Rock |
| Jade | 2M | x12 | Gull Rock |
| Rose Quartz | 30M | x21 | Palm Isle |
| Obsidian | 400M | x37 | Palm Isle |
| Moonstone | 6B | x64 (x96 at night) | Turtle Atoll |
| Amber | 100B | x110 | Turtle Atoll |
| Starstone | 600B | x200 | Whale Reef |
| Comet Core | 10T | x380 | Glass Lagoon |

| Island | Distance | Coin bonus |
|---|---|---|
| Buoy Bay | 300 studs | +5% |
| Gull Rock | 1.5K | +10% |
| Palm Isle | 10K | +15% |
| Turtle Atoll | 100K | +25% |
| Whale Reef | 1M | +35% |
| Glass Lagoon | 10M | +50% |
| Storm Sea | 100M | +75% |
| Edge of the Map | 10B | +100% |
| Starfall Deep | 10T | +150% |
| The Beyond | 10Qa | +250% |

As a rough guide, a decent player reaches their first rebirth in about a quarter of an hour, Moonstone takes many hours, and the Comet Core is a long-term goal. The tests check this pacing with a simulated player.

**Also:** treasure washes up on the beach (walk over and press E for coins), 21 goals to complete, titles that float over your head as your longest throw grows (Skimmer at 1K studs up to Starfall Skipper at 1T), three global leaderboards (longest throw, most coins, most rebirths), and a 20-minute day that turns into a starry night with lanterns, a lighthouse and fireflies.

## Test tools

While playing in Studio, click **🧪 Test** (top right): coins, +10 strength, every rock and island, night, day, fresh treasure, and starting over. In a live game only the game's owner (and anyone you add to `DEV_USER_IDS` in `src/shared/Config.luau`) sees it.

## Publish it

1. In Studio: **File → Publish to Roblox**.
2. **Game Settings → Security → Enable Studio Access to API Services** (so saving works when you test in Studio too).
3. Set the game to public when you're happy with it.

Saving uses session-locked DataStores (a player's progress can never be loaded by two servers at once), autosaves every 2 minutes and saves on leave and shutdown. Leaderboards store big scores on a log scale, so they never overflow however far people throw.

### Optional: background music

The game is quiet by default, with only the sea. To add music, put Roblox audio asset ids in `MUSIC_TRACKS` in `src/shared/Config.luau` (for example tracks from the Creator Store's music library).

---

## For developers

Strict Luau, synced with [Rojo](https://rojo.space/). Everything (the world included) is code; there are no hand-made parts or uploaded assets, and every sound ships with Roblox. The coast is real Roblox terrain written from a heightmap when the server starts (beach, bay, hills and headlands, with terrain water), and the ocean is filled out to the horizon; the boardwalk, piers, buildings and islands are parts with real materials on top.

```
src/shared/
  Economy.luau     Distance, coins, strength, rebirth costs (all the simulator's numbers)
  Skip.luau        How a throw goes: the power needle, skips, hop lengths
  Sea.luau         The coast, the piers, and the endless sea's squeezed distance scale
  Land.luau        The coast's heightmap and which terrain material goes where
  Data/            Rocks, islands and goals
  Util/Format.luau Big numbers: 1.2K, 3.4M, 5T, 2Qa
src/server/
  Systems/         Saving, sessions, throws, shop (rocks, strength, rebirth), progress,
                   islands, treasure, leaderboards, day/night, test tools
  Lib/Ground.luau  Writes the coast terrain and fills the ocean
  Lib/Scenery.luau Builds the boardwalk, piers, beach, lighthouse, buoys and islands
src/client/
  Controllers/     Throw input, HUD, menu, rock flights and the chase camera,
                   messages, night ambience, sound, test panel
tests/           Lune tests that run the real code in fake Roblox servers and clients
tools/           Scene and UI exporters, and a terrain + ocean preview renderer
```

How it fits together:

- **The server decides everything.** The client only says when you started winding up and when you let go (with your hold time). The server checks you're on the beach or a pier, that the hold time matches its own clock, and the cooldown. Then it works out every skip, scales the throw by your strength, rock and rebirths, pays you and tells every player, so everyone sees the same rock. Purchases, upgrades and rebirths are all checked on the server too.
- **The endless sea** is drawn on a squeezed scale: true to life for the first 1,500 studs, then each extra stud covers a little less of the map. Every distance (even a quadrillion studs) lands somewhere on it, and the buoys and islands use the same scale, so a rock that lands by the 10K buoy really did go 10,000 studs.
- **Rocks only touch real water.** Terrain is made of 4-stud voxels that hold either sand or water, so the beach ends in a short bank and the water deepens straight away; a test checks the first touch is on water all along the beach.

Commands (run inside `skip-a-rock/`; install the toolchain from the repo root with `rokit install`):

```sh
lune run tests/run            # unit tests: economy and pacing, sea scale, coast, rocks, goals
lune run tests/integration    # the real server systems in a fake server: a full play session
lune run tests/client_smoke   # every client controller in a fake client
stylua --check src tests      # formatting
selene src                    # lint
rojo build default.project.json -o build/SkipARock.rbxlx
rojo serve                    # live-sync into Studio while editing
```

To rebalance, start with `src/shared/Economy.luau` (strength, rebirth and coin formulas), the prices in `src/shared/Data/RockData.luau` and the distances in `src/shared/Data/IslandData.luau`. The pacing test in `tests/run.luau` plays the game with a simulated player and fails if the first rebirth comes too early or too late.
