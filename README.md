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
| **Eggs & hatching** | 4 shop eggs with limited stock that restocks every 5 minutes. Tap eggs to warm them (2× faster), and friends standing nearby warm them too. |
| **13 dinos** | Raptor → T-Rex, plus a secret Mosasaurus. Each grows Baby → Juvenile → Adult → Giant in real time, even while you're offline. |
| **Coins** | Dinos earn coins onto your gold pad. Offline earnings are waiting when you come back. |
| **Mutations** | Glossy, Lava, Frost, Cosmic, Rainbow (1.5×–8× coins). There's a storm every 30 minutes, and a **Rainbow Mega Storm every Saturday at 17:00 UTC**. |
| **Night raids** | At night, visitors can steal *laid* eggs (never your dinos). You get a free gate lock with a cooldown, a 24-hour shield for new players, and you can tag a thief to get your egg back. Grown dinos roar thieves away. Raids are off in private servers. |
| **Tutorial** | A guided first 3 minutes: hatch → collect → buy → gift egg → raid practice → lock. Each step is logged as an onboarding funnel in Creator Analytics. |
| **Progression** | Dino-Dex (with mutations), a 7-day login streak, slot and incubator upgrades bought with coins, and selling dinos and eggs. |
| **Social (no chat needed)** | Friend coin boost (+10% each, up to +40%), likes on nest signs, a Roar emote, invites, and riding your dinos (with the pass). |
| **Saving** | Session-locked DataStore profiles with retries, autosave, save on leave and on shutdown, and schema versioning. |

Not built yet (next steps from the plan):
- **Real 3D art.** Dinos and eggs are built from simple shapes in `src/shared/Visual/`. Replace `DinoModel.build` to use real models.
- **Sounds and music.**
- **Daily quests, trading, and global leaderboards.**
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
stylua --check src tests        # formatting
selene src                      # lint
lune run tests/run              # 42 unit tests: odds, growth, economy, storms, streaks
lune run tests/smoke            # builds the island + every dino/egg model with real Roblox classes
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
│   ├── Visual/             dino and egg model builders
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
tests/                      Lune test suites
build/RaiseADino.rbxlx      ready-to-open place file
```

**Tuning the game:** almost every number lives in `src/shared/Config.luau`: prices, timers, storm frequency, raid rules, boosts and upgrade costs. Dino stats are in `src/shared/Data/DinoData.luau` and egg odds in `src/shared/Data/EggData.luau`. Each egg's odds must add up to exactly 10000; the tests check this.
