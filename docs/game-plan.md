# Raise a Dino: Roblox Game Plan

*Working title. Research current as of October 2026.*

---

## 0. TL;DR

- **The game:** *Raise a Dino*. You hatch dinosaur eggs, raise baby dinos into giants that keep growing while you're offline, chase rare mutations during weather events, and guard your nest from egg raids at night. It takes the loop behind 2025–26's biggest hits (collect, grow, show off, a little stealing) and puts it on a theme kids have always loved, so it doesn't depend on a meme.
- **The target:** about **$3,000/month**. That takes roughly **12,500 visits a day (~130 players online on average)** at a typical spend rate. That's far below the top charts, but far above where most games ever get. Section 1 has the math.
- **The big 2026 catch:** under-16s can't see a new game until it passes the **Kids/Select evaluation**: **250 plays from highly engaged, age-checked 16+ players within 60 days**. Teens have to like the game first, so the launch plan is built around that.
- **How Roblox decides who sees your game:** the people shown your game on the Home page have to *click it, stay past the first 1–3 minutes, and come back on later days*. Total players count far less than each player's average engagement. Every design choice below ties back to one of those signals.
- **The approach:** build a playable prototype in about 3 weeks, test it on real players with a small ad budget, and keep going or pivot based on the numbers. Plan for more than one attempt. Most Roblox games never earn anything meaningful.

---

## 1. Reality check: what "thousands a month" takes

**How a Robux becomes a dollar (official):**

| Step | Number |
|---|---|
| Your share of a game pass / developer product sale | **70%** (Roblox keeps 30%) |
| DevEx cash-out rate (standard, since Sept 5 2025) | **$0.0038 per earned Robux** |
| Higher rate for purchases by age-verified US adults in eligible (R15-only) games (since June 8 2026) | $0.0054 per earned Robux |
| Minimum to cash out | 30,000 earned Robux (= $114) |
| Net to you per 1 Robux a player spends | **≈ $0.00266** |

So **$3,000/month needs about 1.13 million Robux of player spending per month** (~37,600 Robux a day).

**How much traffic that is.** Roblox doesn't publish per-game revenue. The scenarios below use *assumed* Robux-spent-per-visit figures. Third-party estimators use about 3 Robux per visit (2% of visits buy something, averaging 150 Robux). CCU (concurrent players) assumes 15-minute average sessions.

| Monthly goal | Weak monetization (1 R$/visit) | **Typical (3 R$/visit)** | Strong (6 R$/visit) |
|---|---|---|---|
| **$1,000** | 12.5K visits/day · ~130 CCU | **4.2K visits/day · ~45 CCU** | 2.1K visits/day · ~22 CCU |
| **$3,000** | 37.6K visits/day · ~390 CCU | **12.5K visits/day · ~130 CCU** | 6.3K visits/day · ~65 CCU |
| **$10,000** | 125K visits/day · ~1,300 CCU | **42K visits/day · ~435 CCU** | 21K visits/day · ~220 CCU |

Takeaways:
1. **Monetization quality is as important as traffic.** Going from 1 to 6 Robux per visit cuts the traffic you need by 6×. Section 4 is designed for the right-hand column.
2. **~100–150 CCU sustained is the realistic bar for "thousands."** That's very achievable for a game with good retention, and almost impossible for one without it.
3. **Extra income on top** (not in the table): Creator Rewards (5 Robux/day for each "Active Spender" who plays you 10+ min as one of their first three games that day), rewarded video ads, Roblox Plus sign-up bonuses, and Audience Expansion rewards. All are covered in Section 4.

**Odds, honestly:** Roblox reported 100+ developers earning $1M+ a year, but third-party data suggests most developers earn under $100/month. Breakouts are common enough to plan for and rare enough that **you should plan on 2–3 attempts**. That's why Section 6 has hard keep-going/kill gates.

---

## 2. What the research says

### 2.1 How Roblox decides who sees your game (official)

Most of a growing game's traffic comes from **Recommended For You** on the Home page. Roblox ranks games on signals measured **only on players who found you there organically**, as **per-user averages** (so small games aren't penalized for being small):

| Priority | Signal | What it means for design |
|---|---|---|
| Most important | **Play-through rate**: did they click after seeing you? | Icon and thumbnails are the #1 lever. Use thumbnail personalization (avg. +8.5% qualified play-through, some games +50%). |
| Most important | **First-play bounce rate** (<60 s and 61–180 s), a *negative* signal | Something delightful has to happen in the first 60 seconds. No loading walls, no shop pop-ups, no long tutorial. |
| Most important | **Play days per user** (Day 1, Days 2–7, Days 8–28) | Give kids a reason to come back *tomorrow* and *next week*: offline growth, streaks, weekly updates. |
| Most important | **Playtime per user**, **capped at 60 min/user/day** | Hours-long grinds don't help ranking. Design for 1–3 sessions of 15–30 min a day. |
| Important | **Intentional co-play days** (playing with friends via join, invite, private server) | Friend boosts, co-op actions, invite rewards. |
| Important | **Qualified play sessions per user** | Repeat meaningful sessions. |
| Important | **Spend days per user** and **Robux spent per user** | Monetization is a *ranking* signal. Cheap, useful items spread spending across more days. |

The algorithm also has an "explore, then expand" pattern. An update or ad push brings a spike of new players. If that group retains, Roblox keeps showing you to more groups like it. Ads and YouTubers **don't count toward ranking directly**, but they jump-start exploration. Weekly traffic peaks on **Saturday**.

Things that limit your exposure: clickbait or giveaway metadata ("FREE ROBUX"), thumbnails that don't match gameplay, and **non-unique games** (near-copies of existing titles or place files are deprioritized). Roblox's own advice is to *"add your own spin to existing trends."*

### 2.2 The 2026 kids gate: Roblox Kids & Roblox Select

Since June 2026, accounts are split by age:

| Account | Ages | Content allowed | Chat |
|---|---|---|---|
| Roblox Kids | 5–8 | Minimal or Mild only | Off by default; parent can enable after age check |
| Roblox Select | 9–15 (and anyone not yet age-checked) | Up to Moderate | Off for self-declared; introduced gradually after age check |
| Roblox | 16+ age-checked | All except Restricted | On (where available) |

**To reach anyone under 16, a game must:**
1. Be published from an **age-checked, ID-verified creator account with 2-Step Verification**. Adults use government ID; under-18s use facial age estimation.
2. Either pay a **refundable 1,000 Robux publishing fee** (refunded once the game holds 25 highly engaged players for 60 days) **or** have held **Roblox Premium or Plus for 2 consecutive months**. There's also a 50,000-Robux expedited review option. We don't need it.
3. **Pass evaluation.** The game first goes live only to age-checked 16+ players. It needs **250 unique plays from "highly engaged" age-checked 16+ users within 60 days** (they check account age, play history and spend to filter out bots), plus a safety review.
4. Ads Manager has an **"Engagement" objective** made specifically to reach those players and hit the threshold faster (higher cost per play).

**What this means for us:**
- The game must also be fun for **teenagers**, at least at first.
- **Keep the content rating Minimal/Mild** to reach the full 5–15 audience.
- **Don't rely on text chat.** A large share of kids can't use it. Social features have to work without words (Section 3.6).

### 2.3 What's working right now

| Game | What it is | Lesson |
|---|---|---|
| **Grow a Garden** (2025) | Plant seeds, crops grow in real time even offline, mutations, shop restocks on a timer | Peaked at **~22M concurrent players**. Offline growth and timed restocks create "come back" habits. |
| **Steal a Brainrot** (2025) | Collect meme characters, steal from other bases, lock your base | Stealing creates drama and shareable moments. ~69B visits. |
| **Steal an Egg** (mid-2026) | Egg-collecting, steal/tycoon | Reportedly went from ~280K players in August to ~1.6M in September 2026. Eggs and collecting are hot right now. |
| **Animal Hospital** (May 2026) | Caring for animals | Won Best New Game + People's Choice at the 2026 Innovation Awards. Nurturing themes resonate. |
| **99 Nights in the Forest** | Co-op survival | Co-op with friends works, but scarier content limits the youngest audience. |
| Brookhaven, Adopt Me!, Blox Fruits | Roleplay / pets / anime combat | Evergreen giants. Very hard to compete with head-on. |

**Two warnings from the same data:**
- **Hits fade fast.** *Grow a Garden 2* fell **47% in a single month** (Aug 2026). *Steal an Egg* was already dropping 9–18% week over week. Meme themes burn out. That's why we pair a proven *loop* with an **evergreen theme** (dinosaurs) instead of a meme.
- **Policy crackdowns hit kid-focused hits.** *Steal an Egg* was briefly pulled over an in-game video feed that rewarded watching clips. Roblox then **banned games that reward ongoing media consumption from Kids/Select**. A rumor that it copied code from *Pet Simulator 99* also circulated. Stay clean.

### 2.4 Ways to earn (official)

| Source | How it works | Notes |
|---|---|---|
| **Game passes** | One-time purchase, permanent perk | 70% to you |
| **Developer products** | Repeatable purchases (currency, boosts, skips) | 70% to you. Main revenue engine for simulators. |
| **Subscriptions** | Monthly auto-renew | **Local-currency subs: 70% first month, then 100%** after that. Robux-priced: 70% every month. |
| **Private servers** | Monthly Robux fee | Kids love safe private servers in "steal" games |
| **Rewarded video ads** | Player taps a button, watches a 6–30 s ad, gets a reward | Needs 2,000+ unique visitors/month, ID-verified 2FA account, approved maturity questionnaire. Reward must be a non-random developer product (worth ~3–10 Robux). Can't be a progress gate. |
| **Roblox Plus prompts** | Prompt players to subscribe to Plus in-game | **Up to 750 Robux per new subscriber** (250/month × 3). Plus subscribers get 10–20% off your items and Roblox covers the discount. |
| **Creator Rewards: Daily Engagement** | 5 Robux/day per Active Spender (spent $9.99+ in 60 days) who plays you 10+ min as one of their first 3 games that day | Rewards being a kid's *first* game of the day |
| **Creator Rewards: Audience Expansion** | 35% of a new or returning (60+ days lapsed) user's first $100 of spending on Roblox in 60 days, if they joined via your Share Link/direct link/search | Requires an average of 100+ DAU. Share Links are worth using in all marketing. |
| **US 18+ rate** | $0.0054 vs $0.0038 for adult US buyers | Small for a kids' game, but setting avatars to **R15 Only** costs nothing |

### 2.5 Lines we don't cross (policy and our own rules)

- **Paid random items need published odds.** Any egg, spin or chest bought *directly or indirectly* with Robux (including coins that can be bought with Robux) must show every outcome and its % odds before purchase. Odds must sum to 100% and sit behind a labeled "Odds"/"Details" button (an (i) icon alone doesn't count). Luck boosts must show the *updated* odds while active.
- **Some players can't buy random items.** Check `PolicyService:GetPolicyInfoForPlayerAsync()`. If `ArePaidRandomItemsRestricted` is true, give that player an earn-only path. If `IsPaidItemTradingAllowed` is false, no trading of paid items.
- **No feeds, autoplay or "watch to earn" mechanics** (the 2026 Kids/Select rule).
- **No "free Robux" or giveaway metadata**, no misleading thumbnails, no copied assets or code.
- **Our own rule:** no purchase prompts in a player's first session, no fake countdown pressure, no pay-to-win over other players. Kids' spending is controlled by parents. A game parents see as predatory gets parental blocks and reports. Good faith is also good business here.

---

## 3. The game: *Raise a Dino*

### 3.1 Pitch

> Hatch mystery dino eggs, raise tiny babies into gigantic dinosaurs that keep growing even while you sleep, catch ultra-rare **Lava, Frost and Cosmic** mutations during dino storms, and sneak into other nests at night to snatch eggs before the guard dinos roar you away.

**Why this concept:**
- **Proven loop, evergreen theme.** It combines the loops behind Grow a Garden (real-time growth, mutations, restocks), Steal a Brainrot/Steal an Egg (light stealing, base defense) and Animal Hospital (nurturing). Dinosaurs have been a top kids' theme for decades and won't burn out like a meme.
- **Unique enough for the algorithm.** Original title, art and twist (growth stages, guard dinos, storms).
- **Works for every audience we need.** Big, cool dinos appeal to the 16+ trial audience. Cute babies appeal to 5–8. Collecting rarities appeals to 9–15.
- **Fun solo at low player counts.** No waiting for full servers, which matters a lot at launch.
- **Minimal/Mild content.** No blood, no damage, no fear. Guard dinos *roar* thieves away; nobody fights.
- **Sized for a small team.** Most content is data: a new dino is one model plus one table row.

**Searchable title format:** "Raise a Dino" follows the verb-a-noun pattern of the 2025–26 hits and matches search intent. Add a tag when updating (e.g. "🦖 Raise a Dino [STORM UPDATE]"). **Check for name conflicts before publishing**, with alternates: *Dino Nest*, *Hatch a Dino*, *Grow a Dino*.

### 3.2 Core loop

```
 ┌───────────────────────────────────────────────────────────────────────┐
 │  BUY EGG (shop conveyor, restocks every 5 min)                        │
 │     ↓                                                                 │
 │  HATCH (timer; warm it with a friend = 2× faster)                     │
 │     ↓                                                                 │
 │  RAISE: Baby → Juvenile → Adult → Giant (real time, works offline)    │
 │     ↓            bigger dino = more coins/sec + better nest defense   │
 │  EARN COINS ──→ buy better eggs, more nest slots, nest upgrades       │
 │     ↓                                                                 │
 │  ADULTS LAY EGGS (sell, hatch, or protect at night)                   │
 │     ↓                                                                 │
 │  DINO STORMS → mutations (Glossy, Lava, Frost, Cosmic, Rainbow)       │
 │     ↓                                                                 │
 │  SHOW OFF: Dino-Dex completion, park likes, leaderboards              │
 └───────────────────────────────────────────────────────────────────────┘
```

**Growth timings (to tune with data):** Baby → Juvenile in 10 min, → Adult in 1 h, → Giant in 8 h. Legendaries take 24 h. Growth uses timestamps, so it keeps going offline. A kid who plays after school sees a giant the next morning. That's the main D1 hook.

### 3.3 Night raids (the stealing, made kid-friendly)

- A day/night cycle: about 8 minutes of day, then 2–3 minutes of **night**. Raids only happen at night, which creates a recurring "be there for it" moment.
- **Only eggs laid by your adult dinos can be stolen. Never your dinos.** Kids never lose a pet they raised (no tears, no rage-quits), but the thrill and the TikTok moments stay.
- **Free nest gate** for everyone: tap to lock for 60 s, then recharge. Plus a **new-player shield** for the whole first day.
- **Guard dinos:** grown dinos on your nest roar at intruders and stun them. Progress makes you safer for free.
- **Steal-back chase:** a thief carrying an egg moves slowly. Tag them to return it.
- Players who don't want any of this can use private servers (Section 4).

### 3.4 First 3 minutes (fighting first-play bounce)

| Time | What happens | Signal it serves |
|---|---|---|
| 0:00 | Spawn *at your own nest*. A big glowing egg is already wobbling. One giant arrow: **"Tap to warm your egg!"** | No dead time |
| 0:20 | It hatches: baby raptor, confetti, a name tag with the player's name. Coins start popping out of it. | Delight in <30 s |
| 0:40 | Arrow to the egg conveyor. Free starter coins buy a second egg. | Teach the loop by doing it |
| 1:30 | Second hatch is a **guaranteed "Glossy" mutation** for new players (free egg, not a paid random item) | "I got a rare!" before 2 min |
| 2:15 | "Night is coming!" A friendly NPC raptor tries to steal an egg. Tap to chase it away, then lock the gate. | Teaches raids with zero risk |
| 3:00 | Show the Dino-Dex, the 7-day streak calendar, and **"Your baby becomes an adult in 10 minutes. Come back to see it!"** Opt-in prompt for experience notifications. | Sets up the return visit |

No shop pop-ups, no purchase prompts and no rewarded-ad prompts in the first session.

### 3.5 Reasons to come back (one for each ranking signal)

| Signal | Hook |
|---|---|
| Day 1 return | Offline growth to Adult/Giant. Experience notification: *"Your T-Rex is fully grown!"* |
| Days 2–7 | 7-day login streak (Day 7 = exclusive Epic egg). 3 quick daily quests. Rare eggs show up in the shop at predictable times. |
| Days 8–28 | **Weekly update every Friday/Saturday** (1–2 new dinos, a new mutation or event) to ride the Saturday traffic peak. Dino-Dex completion. Monthly limited dinos. |
| Playtime (60-min cap) | Several short sessions: restocks every 5 min, night every ~10 min, a storm every hour |
| Co-play days | **Friend boost** (+10% coins per friend in server, capped at +40%). **Co-op warming** (2 players on one egg = 2× hatch speed). Invite prompt with reward when a friend joins. Visit a friend's park. |
| Spend days | Low-cost useful items (Section 4), plus a daily free "watch an ad" boost |
| Big moments | **Weekly "Dino Storm" event at a fixed Saturday time**: everyone's mutation odds are boosted for 15 minutes. It's an appointment, a reason to bring friends, and a recordable moment. |

### 3.6 Social play without chat

Many kids will have chat off, so social features use buttons and actions instead of words:
- **Emote wheel and dino roars** (each species has its own roar)
- **"Like this park" button** and a park-likes leaderboard
- **Visit friend's nest** teleport; **co-op warming**; **friend boost** shown on screen
- **Trading** (phase 2, after launch): a visual trade window with no text, gated by `IsPaidItemTradingAllowed`, with confirmation steps and value warnings to prevent scams. We hold it back at launch because it's the biggest source of exploits and scam reports.

### 3.7 Launch content (MVP)

- 1 island map, **8 nest plots per server** (small servers make it easy to join friends)
- **12 dinos** across Common / Uncommon / Rare / Epic / Legendary, plus 1 Secret
- **4 egg types**, **4 mutations** (Glossy, Lava, Frost, Cosmic) plus Rainbow for events
- Day/night raids, nest gate, guard dinos
- Dino-Dex, streak calendar, daily quests, leaderboards
- Shop and monetization (Section 4), odds UI, PolicyService handling
- Mobile-first UI (big buttons, readable at phone size). Most kids play on phones and tablets.
- Avatar settings set to **R15 Only** (qualifies for the 18+ DevEx rate at no cost)

---

## 4. Monetization plan

**Principles:** every purchase is useful or fun but never required. Nothing gives a pay-to-win edge over other players. Prices are read live with `MarketplaceService:GetProductInfoAsync()` so regional pricing, Plus discounts and price tests work automatically. Starting prices are below. Tune them with Experiments once there's traffic.

### Game passes (one-time)
| Pass | Starting price | Why kids buy it |
|---|---|---|
| **Ride Your Dinos** | 249 R$ | Riding a T-Rex is *the* dream feature. Pure fun, shareable. |
| 2× Coins | 299 R$ | Classic simulator pass |
| +4 Nest Slots | 149 R$ | More dinos at once |
| Auto-Collect | 99 R$ | Convenience |
| Fast Hatch (1.5×) | 199 R$ | Convenience |
| VIP (gold name tag, VIP lounge, exclusive VIP dino skin) | 399 R$ | Status |

### Developer products (repeatable)
| Product | Price | Notes |
|---|---|---|
| **Starter Pack** (one per account) | 49 R$ | Shown only after the first session milestone. Converts first-time spenders. |
| Coin packs | 25 / 99 / 249 / 499 / 999 R$ | Bigger packs give better value |
| Instant Hatch / Grow-Up Now | 9–49 R$ (scales with time left) | Cheap impulse buy. Drives spend days. |
| Lucky Potion (15 min) | 39 R$ | **Must show updated odds while active** |
| Restock Now | 29 R$ | Personal shop reroll |
| Gate Extender (5 min lock) | 19 R$ | Optional. The free gate already exists. |

### Recurring and other
| Item | Price | Notes |
|---|---|---|
| **Dino Club** subscription | Low local-currency tier | Daily free egg, 1 exclusive monthly dino skin, +10% coins. **100% revenue share from month 2.** |
| Private server | 100 R$/month | Safe grinding with friends, no raids from strangers. Plus subscribers get them free and you're paid for their time. |
| Rewarded video | Free (ad-funded) | "Watch an ad: 2× coins for 10 min." Button-started, non-random reward, never a gate. Unlocks at 2,000 monthly visitors. |
| Roblox Plus prompt | — | Optional. Offer a cosmetic reward to Plus subscribers. Earns up to 750 R$ per new subscriber. |

### Compliance checklist (build it in from day one)
- [ ] Every egg shows a labeled **"Odds"** button with per-dino % odds summing to 100%. The hatch code and the odds display read from the **same data table**, so they can never drift apart.
- [ ] Lucky Potion and mutation boosts update the displayed odds live
- [ ] `ArePaidRandomItemsRestricted` players: hide coin packs and potions so their eggs are bought with earn-only coins (an "unpaid, earnable path")
- [ ] `IsPaidItemTradingAllowed` checked before any trading (phase 2)
- [ ] `ProcessReceipt` is idempotent (never grants twice, never loses a purchase)
- [ ] Rewarded ads: clear disclosure text on the button, reward granted right after viewing, damage paused or lobby-only

---

## 5. Launch and growth plan

### Phase 0: Setup (week 0)
- Roblox account: **age check + ID verification + 2-Step Verification** (required to reach under-16s and to use rewarded ads)
- Buy 1,000 Robux for the refundable publishing fee (or start Premium now so the 2-month clock runs during development)
- Development setup: Roblox Studio, Rojo + VS Code, this Git repo, Luau strict mode
- Create a Roblox **Group** to own the game. Easier to add collaborators and split revenue later.

### Phase 1: Prototype (weeks 1–3)
- Basic shapes and free placeholder models. **Only the core loop**: hatch, grow (offline), coins, buy eggs, night raid, gate.
- Analytics funnel events for every first-session step (Section 3.4), so you can see exactly where new players leave
- Private playtests with 5–10 people. Watch them play without helping.

### Phase 2: Soft launch to 16+ (weeks 4–6)
- Publish publicly. The game is automatically in the 16+ trial phase.
- Commission the **icon + 3 thumbnails** (the most important art spend) and turn on **thumbnail personalization**
- Run **$50–100 of "Plays" ads** to get traffic, plus **$50–150 on the "Engagement" objective** to reach the 250 highly engaged 16+ players
- Pay the 1,000 R$ fee. Watch the **Audience Reach** dashboard until Kids & Select eligibility is granted.
- **Decision gate:** see Section 6

### Phase 3: Polish and monetize (weeks 5–9, overlapping)
- Real dino models and animations, sound, juice (screen shake, confetti, roars)
- Full monetization catalog with the compliance checklist
- Experience notifications, invite rewards, Dino-Dex, streaks
- Once Kids/Select eligible: **"official launch" update + Saturday Dino Storm**

### Phase 4: Live ops (week 10 onward)
- **Weekly update every Friday:** 1–2 new dinos (each is a model plus a table row), title tag refresh, new thumbnail
- **Monthly bigger update:** new biome or egg type, limited dinos, seasonal events (Halloween "Bone Dinos," winter "Frost Storm")
- Trading (phase 2 feature) once the economy is stable
- Price tests with Experiments once traffic allows (Roblox's built-in price optimization needs ~60K transactions/month)

### Marketing channels (cheapest first)
1. **The game itself:** rare hatches, steals and storms are built to be *recorded*. Use Roblox Share Links everywhere (they count toward Audience Expansion rewards).
2. **TikTok / YouTube Shorts:** post 1–3 short clips a day of rare hatches, "I stole a Legendary egg," and storm reactions. The 2025–26 hits spread this way.
3. **Small Roblox YouTubers (1K–100K subs):** offer early access plus a dino named after them. Use Roblox's **Video Stars** program where eligible.
4. **Roblox Group:** a member-only dino skin for joining. Announce updates through the group.
5. **Roblox Ads Manager:** use ads to *kick-start* the recommendation system's exploration around launches and big updates, not as a permanent traffic source.
6. **Game page events:** create an Experience Event for every Saturday storm so players can tap "notify me."

---

## 6. KPIs and decision gates

These are **our targets**, not Roblox numbers. Compare against the benchmark games in Creator Analytics, which needs 100+ DAU.

| Metric | Kill or pivot | Keep iterating | Scale up (more ads, faster updates) |
|---|---|---|---|
| New players still in game at 3 min | < 50% | 50–70% | > 70% |
| **Day-1 retention** | < 12% | 12–20% | **> 20%** (stretch 30%) |
| Day-7 retention | < 4% | 4–8% | > 8% |
| Average session length | < 8 min | 8–12 min | > 12 min |
| Daily payer rate (% of DAU who buy) | — | 1–2% | > 2% |
| Robux spent per visit | < 1 | 1–3 | > 3 |

**Rules:**
- Give each gate **two improvement passes** (about 1 week each) before deciding. Most fixes go into the first 3 minutes.
- If the prototype misses the kill line on D1 after two passes, **switch to a backup concept** (Section 9) and reuse the code: data saving, shop, analytics and monetization carry over.
- Never scale ad spend on a game below the "keep iterating" column. Ads can't fix retention.

---

## 7. Budget (lean)

| Item | Low | Comfortable |
|---|---|---|
| Publishing fee (refundable) or 2 months of Premium | ~$12 | ~$20 |
| Icon + 3 thumbnails (commissioned) | $50 | $200 |
| Dino models + animations (12) | $0 (self-made / AI-assisted) | $600–1,500 |
| Sound/music (Roblox library is free) | $0 | $50 |
| Launch ads (Plays + Engagement) | $100 | $300 |
| **Total** | **~$160** | **~$1,000–2,000** |

Spend on **thumbnails before models.** They drive play-through rate, the top-ranked signal.

---

## 8. Technical plan (summary)

- **Tooling:** Rojo + VS Code + Git (this repo), Luau `--!strict`, unit tests for economy and odds math
- **Server-authoritative everything.** The client only *asks*; the server validates and rate-limits every request. Coins, eggs, hatch results and growth never trust the client.
- **Data:** session-locked player profiles (ProfileStore pattern) with versioned schema, autosave, and saves on leave and on shutdown
- **Growth:** store `hatchedAt` timestamps and compute stage from time on join, so offline growth costs nothing to run
- **RNG:** one weighted-odds table per egg, used by both the hatch code and the odds UI. Mutation multipliers are stored in the same table.
- **Global timers** (restock, night, storms) are computed from server time, so every server agrees without extra services
- **Purchases:** single `ProcessReceipt` handler with a purchase-ID ledger in the profile (idempotent)
- **Policy:** a `PolicyService` lookup cached per player that drives shop visibility and trading
- **Analytics:** `AnalyticsService` funnel events (first-session steps), economy events (coin sources and sinks), custom events (raids, storms)
- **Configs and Experiments:** onboarding variants, prices and timers live in Configs, so tuning doesn't need a code deploy
- **Modules:** `DataService`, `PlotService`, `EggService`, `HatchService`, `GrowthService`, `EconomyService`, `RaidService`, `ShopService`, `MonetizationService`, `PolicyService` wrapper, `EventService` (night/storms), `NotificationService`, `AnalyticsService` wrapper, client UI controllers

---

## 9. Risks and mitigations

| Risk | Mitigation |
|---|---|
| The game simply doesn't catch on (most likely outcome) | Cheap prototype, hard gates, backup concepts, shared codebase for fast pivots |
| Trend fatigue with collect/steal games | Evergreen theme. Raids are one feature, not the whole identity. Nurturing angle like Animal Hospital. |
| Stuck in the 16+ trial | Design for teen appeal (big cool dinos, raids). Engagement-objective ads. Track the Audience Reach dashboard. |
| Policy changes / takedown | Minimal/Mild content, odds disclosure, no feeds, no giveaway metadata, original assets only |
| Exploiters and item duplication | Server-authoritative design, session locking, rate limits, purchase ledger, no trading at launch |
| Malicious free models (backdoors) | Only use audited Creator Store assets; scan for `require(<id>)` and hidden scripts |
| Algorithm or seasonal swings | Diversify traffic (Shorts, YouTubers, Share Links, group). Watch the Home Recommendations dashboard weekly. |
| Live-ops burnout | Data-driven content pipeline (new dino = model + row). A weekly cadence a 1–2 person team can sustain. |

---

## 10. Backup concepts (if *Raise a Dino* misses its gates)

1. **Monster Café:** a co-op cooking and serving game for 1–4 friends with cute monster customers. Upgrade the café, unlock recipes, decorate. Tests the **co-play** signal hardest. Minimal rating. Reuses the shop, data and monetization code.
2. **Ocean Rescue Aquarium:** dive to find hurt sea creatures, nurse them back to health (Animal Hospital's proven nurturing appeal), then build an aquarium that visitors pay to see. Offline healing timers reuse `GrowthService` directly.

---

## 11. Next steps (this week)

1. **Decide:** go with *Raise a Dino*, or pick a backup?
2. **You:** complete Roblox age check, ID verification and 2-Step Verification. Pick: 1,000 R$ fee or start Premium now.
3. **Me (next session):** scaffold the Rojo project in this repo with the core services (data, plots, eggs, growth, coins) and a greybox island, so you can open it in Studio and play the first loop.
4. **You:** write down 15–20 dino ideas with rarities. Kids' favorites are T-Rex, Raptor, Triceratops, Stego, Brachio, Spino, Ankylo, Ptero and Mosasaurus, plus a Secret.
5. Find an icon and thumbnail artist (Roblox Talent Hub, or ask in Roblox dev Discord communities) for week 4.

---

## Sources

**Official Roblox documentation** (read from Roblox's [creator-docs repository](https://github.com/Roblox/creator-docs), October 10 2026 snapshot):
- [Discovery: how recommendations work and the ranking signals](https://create.roblox.com/docs/discovery)
- [Roblox Kids and Select: publishing requirements and evaluation](https://create.roblox.com/docs/production/publishing/kids-and-select)
- [Publish games and places: publishing and expedited review fees](https://create.roblox.com/docs/production/publishing/publish-games-and-places)
- [Content maturity and compliance](https://create.roblox.com/docs/production/promotion/content-maturity)
- [Developer Exchange (DevEx): rates and eligibility](https://create.roblox.com/docs/production/monetization/developer-exchange)
- [U.S. 18+ DevEx rate](https://create.roblox.com/docs/production/monetization/18-plus-devex-rate)
- [Paid random items policy](https://create.roblox.com/docs/production/monetization/paid-random-items)
- [Subscriptions](https://create.roblox.com/docs/production/monetization/subscriptions)
- [Roblox Plus for creators](https://create.roblox.com/docs/production/monetization/roblox-plus)
- [Creator Rewards](https://create.roblox.com/docs/creator-rewards)
- [Rewarded video ads](https://create.roblox.com/docs/production/promotion/rewarded-video-ads)
- [Ads Manager: Plays / Earnings / Engagement objectives](https://create.roblox.com/docs/production/promotion/ads-manager)
- [Price optimization](https://create.roblox.com/docs/production/monetization/price-optimization)
- [Thumbnails and thumbnail personalization](https://create.roblox.com/docs/production/publishing/thumbnails)
- [Experiments (A/B testing)](https://create.roblox.com/docs/production/experiments)

**News and third-party data** (estimates; treat as directional):
- [Roblox introduces age-based accounts (Business Wire, Apr 2026)](https://www.businesswire.com/news/home/20260413497398/en/Roblox-Introduces-New-Age-Based-Accounts-and-Expanded-Parental-Controls-for-Users-Under-16)
- [Here's how Roblox's age checks work (TechCrunch, Feb 2026)](https://techcrunch.com/2026/02/06/heres-how-robloxs-age-checks-work/)
- [Roblox Q2 2026 results (Outlook Respawn)](https://respawn.outlookindia.com/gaming/gaming-news/roblox-q2-2026-revenue-soars-36-to-15b-despite-bookings-miss)
- [Roblox's top developers' earnings (Outlook Respawn)](https://respawn.outlookindia.com/gaming/gaming-news/robloxs-top-developers-average-339-million-in-annual-earnings)
- [Best Roblox games right now, Sept/Oct 2026 (Sportskeeda)](https://www.sportskeeda.com/roblox-news/best-roblox-games-to-play-right-now)
- [Top Roblox games May 2026 (StudioKrew)](https://studiokrew.com/blog/top-roblox-games-may-2026/)
- [Steal an Egg stats (Intelbricks)](https://www.intelbricks.com/games/steal-an-egg-10563114921)
- [Roblox's hottest new game is already cooling off (Yahoo Finance)](https://finance.yahoo.com/markets/stocks/articles/robloxs-hottest-game-already-cooling-133300538.html)
- [Roblox's top games in August 2026 (Maxpower Gaming)](https://www.maxpowergaming.co/post/roblox-s-top-games-in-august-2026-murder-mystery-2-and-steal-an-egg-take-over)
- [Steal an Egg ban: why it happened (AllThings.How)](https://allthings.how/steal-an-egg-roblox-ban-why-it-happened-and-how-it-returned/)
- [Roblox cracks down on games that reward kids for doomscrolling (TechSpot)](https://www.techspot.com/community/topics/roblox-is-cracking-down-on-games-that-reward-kids-for-doomscrolling.298617/)
- [Roblox Innovation Awards 2026 winners (Pocket Tactics)](https://www.pockettactics.com/roblox/innovation-awards-2026)
- [Grow a Garden (Wikipedia)](https://en.wikipedia.org/wiki/Grow_a_Garden)
- [Steal a Brainrot (Wikipedia)](https://en.wikipedia.org/wiki/Steal_a_Brainrot)
- [Revenue estimate methodology (profitable.app)](https://profitable.app/roblox)
- [Retention benchmarks by Roblox genre (RoWatcher)](https://rowatcher.com/news/retention-benchmarks-by-roblox-genre-what-good-actually-looks-like)
- [Roblox creator earnings tiers (RoLearn)](https://rolearn.dev/insights/roblox-creator-earnings-how-much-developers-make)
