# Raise a Dino

A Roblox game where you hatch dinosaur eggs, raise baby dinos into giants that keep growing while you're offline, catch rare mutations during storms, and guard your nest from egg thieves at night.

The research and business plan behind it is in [docs/game-plan.md](docs/game-plan.md).

---

## Play it in Roblox Studio (about 5 minutes)

1. Install [Roblox Studio](https://create.roblox.com/) (free) and sign in.
2. Download **[`build/RaiseADino.rbxlx`](build/RaiseADino.rbxlx)** from this repo.
3. Open it: double-click the file, or in Studio use **File → Open from File**.
4. Press **▶ Play** (F5). The island builds itself and the tutorial starts.

In Studio the edit view only shows a "Press Play" sign. The island, the nests and the egg shop are built by code when the game starts.

**Test tools:** while playing in Studio, click the **🛠** button (top-left). It has buttons to add coins, grow dinos, finish eggs, lay eggs, make it night, start a storm or the weekly Rainbow Mega Storm, add a T-Rex, remove the new-player shield, skip the tutorial, reset your save, and switch on any game pass without buying it.

**Testing raids** needs two players: open the **Test** tab, set **Clients and Servers** to 2 players, and press **Start**. New players have a 24-hour shield. In the victim's 🛠 panel press **Remove shield** and **Lay eggs**, then press **Make night**. The other player can now walk into that nest and hold **Steal!** on a laid egg.

> Progress doesn't save in Studio until you publish the game and turn on API access (see below). Until then you'll see a warning in Output; that's expected.

---

## Turn on the square studs (once, about 2 minutes)

Every surface in the game (ground, paths, fences, trees, the volcano, dinos and eggs) wears **square studs** from one custom material, `MaterialService → SquareStuds`. The place already uses it everywhere, but Roblox only lets images be added by uploading them, so you add its three pictures once:

1. Download the images in [`assets/textures/`](assets/textures): `SquareStuds_Color.png`, `SquareStuds_Normal.png`, `SquareStuds_Roughness.png` (and `SquareStuds_UI.png` for the menus, see below).
2. In Studio open the **Material Manager**: **Window → 3D → Material Manager** (in older Studio: the **Model** tab → **Material Manager**).
3. Find **SquareStuds** (it's listed under *Smooth Plastic*), select it and click **Edit**.
4. Next to each map, use the **import** button and pick the matching file:
   - **Color** → `SquareStuds_Color.png`
   - **Normal** → `SquareStuds_Normal.png`
   - **Roughness** → `SquareStuds_Roughness.png`
5. Leave **Studs Per Tile** at **4**. Each picture holds 4 × 4 studs, so one stud is one 1×1 stud cell, like classic Roblox bricks.
6. Press **▶ Play**. Studio uploads the images to your account; a new upload can show grey for a minute until it's approved.

You can also upload the images in the Asset Manager or Creator Hub, right-click each one, choose **Copy Asset ID**, and paste the IDs into the `ColorMap`, `NormalMap` and `RoughnessMap` properties of `SquareStuds`. If you build the place with Rojo, paste them into `default.project.json` (`MaterialService.SquareStuds`) as `"rbxassetid://…"` so rebuilds keep them.

**Studs on the menus too:** upload `SquareStuds_UI.png` the same way (Asset Manager → **Import**), right-click it → **Copy Asset ID**, then in the **Explorer** click **MaterialService → SquareStuds** and, in **Properties** under **Attributes**, paste the ID into **UIStudImage**. Every window, card and button then shows studs.

Until the images are added, parts and menus just look smooth. Glowing lava, glass and crystal parts always stay smooth on purpose.

**Other looks:** set `STUD_STYLE` in `src/shared/Config.luau` to `"classic"` for Roblox's built-in round studs on brick tops (no upload needed), or `"none"` for smooth plastic. To change the studs themselves (size, roundness, height), edit the numbers at the top of `tools/textures/make_studs.py`, run `python3 tools/textures/make_studs.py`, and import the new images.

---

## Publish it

1. **File → Publish to Roblox** and create a new experience.
2. In **Game Settings**:
   - **Security:** turn on *Enable Studio Access to API Services* (so saving works in Studio).
   - **Avatar:** set avatars to **R15 only**. This is required for the higher US 18+ DevEx rate.
   - Set the **server size (max players) to 8**. The island has 8 nests, one per player, and a 9th player would be turned away.
3. On the Creator Hub, fill in the **Maturity & Compliance questionnaire** honestly. The game has no blood, no fighting (guard dinos only roar) and no scary content, so it should come out **Mild**. That rating lets it reach Roblox Kids (5–8) and Select (9–15).
4. To reach players under 16 (see plan section 2.2):
   - Your account must be age-checked and ID-verified, with 2-Step Verification on.
   - You need to pay the refundable 1,000 Robux fee, or have Premium or Plus for 2 months.
   - The game then has to collect **250 plays from engaged, age-checked 16+ players** within 60 days. Track this in Creator Hub → **Audience → Reach**.

---

## Set up passes and products

1. In Creator Hub → your game → **Monetization**, create these. Suggested prices are in `Config.SUGGESTED_PRICES`.

   | Game passes | Developer products |
   |---|---|
   | RideDinos (249) | StarterPack (49) |
   | DoubleCoins (299) | CoinsSmall / Medium / Large / Huge / Mega (25 / 99 / 249 / 499 / 999) |
   | ExtraSlots (149) | InstantHatchSmall / Medium / Large (9 / 19 / 49) |
   | AutoCollect (99) | LuckyPotion (39) |
   | FastHatch (199) | SuperLock (19) |
   | VIP (399) | AdCoinBoost (reward for rewarded video ads, not sold) |

2. Paste each ID into **`src/shared/Config.luau`** under `GAME_PASS_IDS` and `PRODUCT_IDS`. If you edit in Studio instead of with Rojo, it's at *ReplicatedStorage → Shared → Config*. Anything left at `0` stays hidden from players.
3. Optional: create a **subscription** called "Dino Club" (+10% coins and a daily coin gift) and paste its `EXP-...` ID into `SUBSCRIPTION_ID`.
4. **Rewarded video ads:** once the game has 2,000+ visitors a month, turn on Rewarded Video in Monetization → Ads, with **AdCoinBoost** as the reward. The "▶ Free 2x" button then appears on its own.

Purchases follow the rules in the plan (section 2.5):
- Every egg has an **📊 Odds** button showing the exact odds, which add up to 100%. Luck potions and storms update the shown odds live, using the same code the server uses to roll.
- Players that Roblox's PolicyService restricts from paid random items never see coin packs, luck or the starter pack.
- A Robux purchase is never granted twice, and it's only confirmed to Roblox after it has been saved.

---

## What's in the game

| Feature | Details |
|---|---|
| **Eggs & hatching** | 6 shop eggs (Jungle, Swamp, Volcano, Crystal, Glacier, Abyss) with limited stock that restocks every 5 minutes. Tap eggs to warm them (2× faster), and friends standing nearby warm them too. |
| **21 dinos** | From tiny Compsognathus to the huge Giganotosaurus, plus 2 secrets: Mosasaurus and Cryolophosaurus. Each grows Baby → Juvenile → Adult → Giant in real time, even while you're offline. |
| **Coins** | Dinos earn coins onto your gold pad. Offline earnings are waiting when you come back. |
| **Mutations** | Glossy, Lava, Frost, Cosmic, Rainbow (1.5×–8× coins). There's a storm every 30 minutes, each with its own look: a ❄️ Blizzard with blowing snow (Frost), a 🌠 Meteor Shower with shooting stars (Cosmic) and a 🌋 Lava Storm with floating embers and ash (Lava). A **Rainbow Mega Storm** with rainbow confetti comes **every Saturday at 17:00 UTC**. |
| **Night raids** | At night, visitors can steal *laid* eggs (never your dinos). You get a free gate lock with a cooldown, a 24-hour shield for new players, and you can tag a thief to get your egg back. Grown dinos roar thieves away. Raids are off in private servers. |
| **Tutorial** | A guided first 3 minutes: hatch → collect → buy → gift egg → lock your gate. Each step is logged as an onboarding funnel in Creator Analytics. |
| **Progression** | Dino-Dex (with mutations) with prizes at 3, 6, 9 and all 21 species, a 7-day login streak, slot and incubator upgrades bought with coins, and selling dinos and eggs. |
| **Golden dinos** | Have 3 of the same dino? Open one and tap **⭐ Make Golden** (costs 5 minutes of that dino's income). The two cheapest are used up and the one you picked turns gold with a crown, keeps the oldest age and best mutation of the three, and earns 3x coins. Golden ones get a ⭐ in the Dex. |
| **Rebirth** | Open **⭐ Rebirth** once you have 💰1M: all your coins (wallet and coin pad) reset, and everything you earn gets **+50% forever** (stacks: +100%, +150%...). Dinos, eggs, upgrades, passes and the Dex are kept. Each rebirth costs 4x the last. Rebirths show on your nest sign and in the player list. |
| **Feeding** | Fruit trees around the island drop 🍎 Dino Apples (and rare 🌟 Golden Apples) on the ground. Walk over one to pick it up (basket holds 20 apples and 5 golden), then tap **Feed** in a dino's card: an apple is 5 minutes of growth, a golden apple 30. Fruit grows back about a minute after it's picked. |
| **Leaderboards** | The Hall of Fame in the hub (opposite the volcano) shows the top 10 coin earners, Dex collectors and rebirthers across the whole game, saved with ordered DataStores and refreshed every 2 minutes. In Studio before publishing they show the players in your test server. |
| **Daily quests** | Three fresh quests every day (hatch eggs, buy eggs, collect coins, roar...), each with a coin or boost reward, plus a bonus for finishing all three. |
| **Codes** | A code box in ⚙️ Settings. Codes are listed in `src/server/Lib/CodeData.luau` (server only, so nobody can read them early): add a NAME in capitals, a reward, and optionally an `expires` time. Each player can use each code once. Starts with `DINO`, `RAWR` and `EGGCELLENT`. |
| **Dino buddy & nicknames** | Pick any of your dinos as a buddy and it follows you around the island. Tap ✏️ in a dino's card to name it; names go through Roblox's text filter (and again every time you join) before anyone sees them. |
| **Social (no chat needed)** | Friend coin boost (+10% each, up to +40%), likes on nest signs, a Roar emote, invites, and riding your dinos (with the pass). |
| **Look & feel** | A cartoon island with square studs on every surface, a volcano, candy-striped hub, day/night lighting with glowing lamps, chunky rounded UI that scales for phones, tablets and PCs, a hatch reveal with light beams, coins that fly to your counter, and sound effects (switchable in ⚙️ Settings). |
| **Saving** | Session-locked DataStore profiles with retries, autosave, save on leave and on shutdown, and schema versioning. |

Not built yet (next steps from the plan):
- **Real 3D art.** Dinos and eggs are built from simple shapes in `src/shared/Visual/`. Replace `DinoModel.build` to use real models.
- **Music.** Sound effects use Roblox's built-in sounds. For music, paste audio IDs you're allowed to use (e.g. Roblox-uploaded tracks from the Creator Store) into `Config.MUSIC_TRACKS`; the Music switch in Settings appears on its own.
- **Trading and global leaderboards.**
- **The Roblox Plus prompt.**
- **"Your dino is grown!" push notifications.** These need Open Cloud; the in-game opt-in prompt is already there.
- **Your icon and thumbnails.** These are the most important art spend.

---

## Working on the code

The project uses [Rojo](https://rojo.space) so the code lives in files (and in Git) instead of inside the place.

```sh
# one-time: install the toolchain (https://github.com/rojo-rbx/rokit)
rokit install

# live-sync into Studio: run this, then click "Connect" in the Rojo Studio plugin
rojo serve

# build a fresh place file
rojo build default.project.json -o build/RaiseADino.rbxlx
```

When you use Rojo, edit the files in `src/` and not the scripts in Studio, because Rojo overwrites them. Map decorations you add to Workspace in Studio are kept.

**Checks** (CI runs all of these):

```sh
stylua --check src tests tools  # formatting
selene src                      # lint
lune run tests/run              # unit tests: odds, growth, economy, storms, streaks, quests, studs
lune run tests/smoke            # builds the island + every dino/egg model with real Roblox classes,
                                # and checks every part wears the stud material
lune run tests/integration      # plays a full session against the real server code
lune run tests/client_smoke     # builds the whole UI and opens every window
```

### Layout

```text
src/
├── shared/                 → ReplicatedStorage.Shared (both sides)
│   ├── Config.luau         every tunable number + monetization IDs
│   ├── Data/               dinos, eggs, mutations, tutorial, store items
│   ├── Util/               pure logic: odds, growth, economy, day/night + storms, streaks
│   ├── Visual/             dino and egg model builders, the stud look
│   ├── Net.luau            every remote, rate-limited
│   └── Types.luau          save format + state snapshot
├── server/                 → ServerScriptService.Server
│   ├── init.server.luau    bootstrap (init all systems, then start all)
│   ├── Systems/            Data, Lifecycle, World, Plots, Nest, Eggs, Dinos, Raids,
│   │                       Weather, Progress, Monetization, Social, Upgrades, Cheats...
│   └── Lib/                Stats (derived numbers), Notify
└── client/                 → StarterPlayerScripts.Client
    ├── init.client.luau
    ├── Controllers/        HUD, shop + odds, store, dex, rewards, dino panel,
    │                       tutorial, effects, world FX, dev panel
    └── Lib/                UI toolkit, pop-up windows
assets/textures/            square-stud material images (import once, see above)
tools/textures/             make_studs.py: generates those images
tools/preview/              offline renderers for the island, models and UI
tests/                      Lune test suites
build/RaiseADino.rbxlx      ready-to-open place file
```

**Tuning the game:** almost every number lives in `src/shared/Config.luau`: prices, timers, storm frequency, raid rules, boosts and upgrade costs. Dino stats are in `src/shared/Data/DinoData.luau` and egg odds in `src/shared/Data/EggData.luau`. Each egg's odds must add up to exactly 10000; the tests check this.
