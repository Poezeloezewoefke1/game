# Test Report

Everything below was actually executed in this build environment. Commands are given so any claim can
be re-run. Where a measurement is limited by the environment, that is stated rather than glossed.

**Environment:** Ubuntu 24.04 x86-64 VM, 4 cores, 15 GB RAM, **no GPU** (Mesa llvmpipe software
rasteriser). Godot 4.4.1-stable.

---

## 1. Automated test suite — 2508 assertions, 0 failures

```
godot --headless --path . -s tests/run_headless.gd -- res://tests/test_suite.gd 4
```

```
PASSED: 2508
FAILED: 0
ALL TESTS PASSED
```

| Section | What it verifies |
|---|---|
| Skin parser | 64×64, legacy 64×32 expansion, HD (128×128) scale detection, slim vs classic detection, placeholder fallback, missing-asset recording |
| Skin UV mapping | All six parts present; head/body/arm/leg UV origins; all six face rects per box; mirroring swaps left/right; slim arms are 3px and classic 4px; legacy mirrors left limbs and drops body outer layer; **every UV rect of every part stays inside the 64×64 texture** |
| Character generation | Merged mesh is one surface with ≥144 vertices; CUSTOM0/CUSTOM1 present for GPU animation; armour and weapons add geometry; six part nodes with pivots at 24px (head) and 12px (leg); right arm on +X; animation states; the attack animation emits its hit frame; facing −Z gives yaw 0 |
| Armor system | Tier parsing; `_enchanted` suffix; netherite outscores leather; enchanting adds points; every tier in the catalog produces geometry with a real colour; **the helmet does not seal the face shut**; slim and classic have the same piece count |
| Weapons | Every weapon in the catalog builds geometry; the mace mesh has vertices; enchanted weapons carry the glint flag |
| Held item pose | The carry angle swings the item clear of the body and downward; its face stays at least 25% towards the board camera at all 72 sampled walking directions; the socket is in the fist, not the wrist joint; a 20px item's tip clears the ground |
| Held items | Every weapon id used by the shipped data has a fallback box model and, with a pack installed, real Minecraft art, one surface, an item material, a size and position that stay within reach of the grip; the `_enchanted` suffix carries the glint and resolves to the plain item's texture; the merged MultiMesh character drops the box weapon when the real one is drawn; an unknown weapon falls back instead of vanishing |
| Damage calculation | Armour formula at 0/50/95%; full and half pierce; the 10% floor; over-cap armour; damage types vs shields and structures; true damage; guaranteed and zero-chance crits; splash falloff at centre, rim and midpoint; mace height bonus and its cap |
| Path | Length is the sum of segments; start/end/midpoints; clamping before and past the ends; tangent direction; lateral offset distance; range queries; nearest-point projection |
| Enemy pool | Capacity; spawn returns a live slot; type round-trip; position follows path distance; spatial query finds near and excludes far; damage applies; lethal damage kills; slot reuse; **pool exhaustion is graceful and never exceeds capacity**; slow, stun and knockback; knockback clamps at the path start; bosses resist slows and cannot be knocked back |
| Enemy data | ≥25 definitions; positive HP; armour in range; every enemy has a codex entry and a stated gameplay reason; every downgrade target exists; all 14 special enemy types required by the brief are present |
| Gear progression | The 7-tier chain exists; HP, armour and reward increase monotonically up it; each tier links down correctly; the base Chungie has nothing left to break; iron and netherite wear visibly different gear; **a live gear break leaves the unit alive, swaps its type and carries overflow damage** |
| Tower stats and upgrades | ≥12 towers; every tower has cost, damage, range, interval, lore, a character, three paths of four tiers with strictly increasing costs and non-empty descriptions; live stat resolution; upgrades raise damage and DPS; the Signature tier is a large jump; aura multipliers apply; sell returns 75% |
| Upgrade path rule | A fresh tower can start any path; a maxed path stops at 4; a second path may start; the second stops at 2; **no third path once two are open**; a second path may start while the first is above tier 2 |
| Hero data | Exactly four heroes, all present; each has three actives and an ultimate on slots 0–3; every ability has a cooldown, description and effect; ultimates cost ≥60s; ≥3 passives; lore, summary, strengths and weaknesses; the XP curve rises |
| Wave generation | Every map has ≥10 waves; every wave is named and pays; every group references a real enemy with a positive count and interval; every event has a type and a time; **difficulty ramps — the last third is >2× the first third by total enemy HP**; Fort Feather ends on a boss wave |
| Boss phases | Five phases in code and in data; every phase names its basis in the story and its mechanic; the boss and mini-boss map to real enemy definitions; the boss has boss-sized health and carries the boss flag |
| Currency | Add, afford, exact-amount affordability, spend, failed spend changes nothing, earning and spending are tracked; leaks cost lives; repairs are capped at max; lives cannot go negative; running out ends the run; difficulty multipliers |
| Save data | Default shape; four heroes unlocked; meta starts at level 1; a win completes the map and records the best wave; meta levels up from XP; bottles bank; codex unlocks; **save round-trips through disk**; settings survive a reload |
| Relationships | ≥10 bonds; unique ids; two different members, both placeable characters; **every bond cites its basis in the story, its sources and its confidence**; every bond has an effect |
| Lore database integrity | Every category populated; every entry has an id, a confidence tier from the four known values, and ≥1 source; the four protagonists are flagged; Saparata is flagged an antagonist; **≥3 arcs record concurrency**; no entry uses an unknown confidence tier |

---

## 2. Full-run smoke test

```
godot --headless --path . -s tests/run_headless.gd -- res://tests/headless_run.gd 1500
```

```
[TEST] map=fort_feather hero=parrotx2 zones=18 waves=25
[TEST] path length=157.6 points=15
[TEST] enemy defs=30 tower defs=14
[TEST] placed 12 towers
[TEST] applied 72 upgrades
[TEST] waves reached 6/25
[TEST] enemies spawned=79 killed=70 live=9 groups=11
[TEST] emeralds=200606 lives=100/100
[TEST] stats={"kills":96,"leaks":0,"damage_dealt":4273.0,"towers_built":12,"upgrades":72,"waves_cleared":5,...}
[TEST] bonds=7
[TEST] ERRORS: 0
```

Verified: the map builds, 18 build zones resolve, 12 towers place and take 72 upgrades without
violating the Gear Rule, 7 relationship bonds activate, waves spawn and advance, enemies move and die,
kills pay emeralds, and no error is logged.

---

## 3. Boss encounter test

```
godot --headless --path . -s tests/run_headless.gd -- res://tests/boss_test.gd 2000
```

```
[BOSS] phase 1 entered: Cindercrest Vanguard
[BOSS] phase 2 entered: Elite Strike
[BOSS] ShoeBilly_ spawned
[BOSS] phase 3 entered: The Redstone Blimp
[BOSS] Redstone Blimp launched
[BOSS] phase 4 entered: Saparata Enters
[BOSS] Saparata on the field
[BOSS] phase 5 entered: The Usurper King
[BOSS] Saparata defeated

[BOSS] phases entered: 5 of 5
[BOSS] mini-boss seen: true
[BOSS] blimp launched: true
[BOSS] paratroopers dropped: 10
[BOSS] boss spawned: true
[BOSS] boss defeated: true
[BOSS] ERRORS: 0
```

All five phases fire in order, the mini-boss appears, the blimp flies and drops its full complement of
paratroopers, the boss enters and can be killed, and the `boss_defeated` stat is recorded.

A separate run with the harness damaging the blimp confirmed the counter-play: the blimp dies before
reaching its drop window and **0 paratroopers** are dropped.

---

## 4. Performance

### Headless (game logic only)

```
godot --headless --path . -s tests/run_headless.gd -- res://tests/stress_test.gd 1400
```

| Enemies | FPS | Mean frame | p95 | Nodes | MultiMesh groups | Memory |
|---|---|---|---|---|---|---|
| 50 | 145 | 6.89 ms | 6.93 ms | 520 | 25 | 50.0 MB |
| 100 | 139 | 7.19 ms | 6.94 ms | 525 | 30 | 50.4 MB |
| 250 | 143 | 7.01 ms | 7.14 ms | 528 | 30 | 50.7 MB |
| 500 | 140 | 7.14 ms | 6.92 ms | 526 | 31 | 50.7 MB |
| 1000 | 135 | 7.39 ms | 7.14 ms | 526 | 31 | 50.7 MB |

**Going from 50 to 1000 concurrent enemies costs 0.5 ms of frame time, 6 nodes and 0.7 MB.** The
enemy pool is doing what it was designed to do: the node count is independent of the enemy count.

### With rendering (software rasteriser)

```
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
  -s tests/run_visual.gd -- res://tests/stress_test.gd build/stress.png 1400
```

| Enemies | FPS | Mean frame | p95 | Nodes | Draw calls |
|---|---|---|---|---|---|
| 50 | 7.5 | 133.33 ms | 147.58 ms | 588 | 828 |
| 100 | 7.5 | 133.34 ms | 144.17 ms | 600 | 844 |
| 250 | 7.5 | 133.35 ms | 144.05 ms | 600 | 852 |
| 500 | 7.5 | 133.32 ms | 144.46 ms | 598 | 848 |
| 1000 | 7.5 | 133.40 ms | 149.38 ms | 598 | 848 |

**These numbers replace an earlier table that was measuring nothing.** The previous run was taken
while the enemy MultiMeshes had an instance_count of 0 — no enemy was being drawn at all (see the
rendering bug in section 13) — so "adding 950 enemies costs no draw calls" was true in the most
useless possible sense. The table above is a re-run with the enemies actually on screen.

**And read the rest carefully too.** The 7.5 fps is llvmpipe filling 1280×720 in software; there is
no GPU in this VM, and 133 ms is the floor it charges for a frame whatever is in it. That floor is
*why* the frame times look flat, so this run cannot distinguish "the instancing scales well" from
"the rasteriser was saturated either way", and it should not be quoted as evidence of the former.

What it does establish, because these are counted rather than timed: **draw calls and node count stay
flat from 50 to 1000 enemies** — 828 to 848 calls and 10 extra nodes across a twentyfold increase in
units. Enemy count adds instances, not draws, which is the thing the architecture was built for.

**No frame rate on real GPU hardware has been measured, and none is claimed.** See
[KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md).

---

## 5. Windows executable verification

```
godot --headless --path . --export-release "Windows Desktop" build/windows/UNSTABLE_LAST_STAND.exe
```

Export completes with **0 warnings and 0 errors**. Binary verification:

```
PE32+ executable (GUI) x86-64, for MS Windows, 13 sections
MZ header: b'MZ'   PE signature: b'PE\0\0'   machine: 0x8664 (x86-64)
embedded PCK marker (GDPC): found
size: 77.3 MB
```

The exe was then **executed under Wine 9.0** in this environment:

```
wine UNSTABLE_LAST_STAND.exe --headless --quit-after 300
→ Godot Engine v4.4.1.stable.custom_build - https://godotengine.org
→ [DataDB] loaded: 4 heroes, 14 towers, 30 enemies, 2 bosses, 2 maps, 49 lore characters
→ exit 0
```

The packaged game boots, loads every data file from the embedded PCK, and runs its main scene. A
windowed run under Wine fails at display creation only — Wine's software GL does not expose OpenGL 3.3
and ANGLE/EGL is not installed in the prefix. That is a limitation of this VM, not of the build.

---

## 6. Visual verification

Rendered under Xvfb at 1600×900 and inspected:

| Screenshot | Result |
|---|---|
| `build/screen_menu.png` | Title, four distinct 3D heroes with their gear and enchant glint, full button set, save stats |
| `build/screen_heroes.png` | Hero select with 3D previews, abilities, passives, strengths/weaknesses, confidence tags |
| `build/screen_codex.png` | Codex with category tabs, entry list and sourced detail pane |
| `build/screen_map.png` | Full Fort Feather map: grass, the winding road, the stone fort, build platforms, trees, the Cindercrest camp |
| `build/screen_game.png` | Live run: HUD, 14-tower shop, active bonds, boss bar with phase, dialogue, hero ability bar, enemies on the path |
| `build/visual_test.png` | Character line-up across armour tiers with weapons and glint |
| `build/visual_mm.png` | MultiMesh vs node rendering parity check |

---

## 7. Bugs found by testing and fixed

These were all found by the tests or the screenshots, not by inspection.

1. **Stale spatial grid.** `query_range` could read a grid built before a spawn or death in the same
   frame. Found by the enemy-pool test. Fixed by marking the grid dirty on spawn/kill/leak/clear and
   rebuilding lazily on query.

2. **The boss never appeared.** A wave whose only content was a scripted event completed instantly,
   because completion did not wait for events to fire. The run was won before Saparata spawned. Found
   by the boss test. Fixed by requiring an empty event queue (and an idle blimp) for wave completion.

3. **Inverted block winding.** Every map face was wound counter-clockwise, so the entire world was
   back-facing and the camera saw its underside — the terrain read as flat brown with no road. Found
   by the map screenshot plus a per-texture face-count diagnostic. Fixed by reversing the triangle
   order.

4. **The road was never drawn.** `_add_block` refuses to overwrite an occupied cell, so path blocks
   painted over terrain columns were discarded. Fixed by adding `_set_block` for deliberate
   replacement; path faces went from 395 to 1170.

5. **All four menu previews rendered the same pile of characters.** `SubViewport` defaults to sharing
   the parent's 3D world. Fixed with `own_world_3d = true`.

6. **`look_at` before the tree.** `CharacterPreview` built its camera before the viewport entered the
   scene tree, logging an error on every preview. Fixed by composing the transform directly.

7. **Towers kept acting after the run ended**, still spawning walls on a finished map. Fixed by gating
   tower processing on `GameState.run_active`.

8. **Shader `#include` misuse.** The shared include defined functions that wrote to built-ins, which
   the compiler rejected. Restructured so the include holds only pure helpers.

9. **MultiMesh instances rendered black.** `use_colors` was not enabled, so the shader's `COLOR` input
   read as zero. Found by comparing MultiMesh and node rendering side by side.

10. **Armour sealed the face shut**, making every character unidentifiable under a helmet. Rebuilt
    armour as shell pieces; the test suite now asserts the face stays open.

11. **Explosion chains overflowed the stack.** A dense cluster of TNT runners killing each other
    recursed through `damage()` until Godot ran out of stack. Found by the balance simulation. Fixed
    by queuing blasts and draining them iteratively with a round cap.

12. **Gear breaks were counted as kills.** Every armour layer a chungie shed incremented the kill
    stat, so "enemies defeated" reported several times the number of units actually stopped (1526 at
    wave 9). Split into `kills` and `gear_breaks`.

13. **A lambda capture leak in the HUD.** `_refresh_hero_panel()` connected a fresh lambda to
    `EventBus.hero_xp_changed` on every rebuild, spamming "Lambda capture at index 0 was freed".
    Replaced with a single bound method and a retained bar reference.

---

## 8. Bugs found by the balance simulation

Section 7's bugs stopped the game from running correctly. This second group is different: the game
ran, looked fine, and was quietly *unplayable as designed*. They were only found by having an AI
player play a full 25-wave campaign under the same rules as a human and then measuring where the
damage actually came from — no amount of reading the code surfaced them.

The investigation is worth recording, because the first two hypotheses were wrong:

1. **The symptom.** Every campaign ended 100/100 lives with zero leaks. Raising late-wave enemy counts
   made it *easier* (kill rewards scale with count, so a bigger wave pays for the towers that answer
   it). Raising HP did nothing either: a sanity run at **25x HP** on waves 16-25 still finished
   100/100 with a single leak. Difficulty was not tunable at all, which meant something was
   HP-invariant.

2. **Wrong hypothesis #1: crowd control.** `apply_stun` only ever extended `stun_until`, and
   `push_back` subtracted path distance on every hit, both with no cap — so stun/knockback towers near
   the exit could pin any non-boss unit indefinitely regardless of its health. This is a genuine
   defect and is fixed (diminishing returns on stun, a per-unit cooldown *and* a lifetime budget on
   knockback, a floor on slows), but it was **not** the cause: the 25x run was unchanged.

3. **Wrong hypothesis #2: the hero was overpowered.** Kill attribution showed `parrotx2` landing 448
   of 674 kills and 448 of 452 kills past 90% of the path. But kill credit misleads — a unit worn down
   by five towers and finished by a sixth credits only the sixth. Measuring *damage* rather than kills
   showed the hero at 90% of all damage in the run, while its 316 recorded attacks at 32.8 damage
   could account for at most ~21,000 of 4.7 million.

4. **Real cause A: wave HP scaling evaporated on the first gear break.** `spawn()` applied
   `hp_scale * hp_mult`, but `_downgrade()` applied only `hp_scale`. A seven-layer chungie therefore
   carried the wave's multiplier on roughly one seventh of its real health pool. Fixed by storing the
   spawn multiplier per unit (`hp_mult_of`) and reapplying it to every layer below.

5. **Real cause B: the hero's relationship bonus compounded without ever being reset.**
   `apply_relationship()` multiplies `relationship_damage_mult`, and `reset_relationship()` was never
   called from anywhere. `refresh_auras()` runs on every placement, upgrade and sell — about 125 times
   in a campaign — and each call re-multiplied the hero by every active bond. Towers were rebuilt from
   identity on each refresh; the hero was not. Fixed by resetting the hero alongside the towers in
   `refresh_auras()`.

   Total damage in a campaign fell from 4,702,027 to 16,795 once this was fixed, and the damage table
   became what the design intends: the towers carry the run (royal_guard 27%, jaden_man 22%,
   purpled 17%) and the support hero contributes 8%.

6. **Base healing made lives meaningless.** Once the two bugs above were fixed and leaks became real,
   the simulation still finished a campaign on **100/100 lives having taken 53 leaks** — every one of
   them healed back. The cause is structural rather than a wrong number: base repair was expressed per
   second, and a campaign runs roughly forty minutes, so ReinaDrop's signature tier (6 lives per 10s)
   restored about fourteen times the entire hundred-life pool over a run. Fymada's `lives_on_wave` 40
   was likewise larger than the damage any single wave could do. Fixed structurally with a per-wave
   repair cap (`repair_cap`, enforced in `Tower._tick_repair` and reset each wave) rather than by
   shrinking the numbers alone, so the medic identity survives without leaks becoming free.

7. **Campaign results were not reproducible — and seeding alone did not fix it.** The enemy RNG was
   seeded from the clock, so two runs of one build finished "won with 80 lives" and "lost on wave 23".
   The simulation was given a seed argument and `tools/balance_sweep.sh` was written to report a
   distribution rather than trust one run.

   **That was not enough, and the first version of this section wrongly called the result
   reproducible.** Re-running the *committed* build at seed 1 later produced a defeat on wave 19 where
   the recorded sweep had a victory with 59 lives. The cause was the timestep, not the RNG: the game
   advances on wall-clock `delta`, so under different machine load each simulated step covers a
   different slice of game time and the run diverges. A seeded run is only reproducible if the
   timestep is fixed as well.

   Fixed by running the simulation with `--fixed-fps 60` (baked into `tools/balance_sweep.sh`) and
   setting `Engine.time_scale = 3.0` for a 1/20 s step. The simulation also detects a variable
   timestep at runtime and prints a loud warning rather than reporting a number that means nothing.

8. **Audio was drawing from the gameplay RNG.** Even with a fixed timestep, two *concurrent* runs of
   one build and seed still diverged — identically through wave 23, then apart at wave 24. The cause:
   `AudioMgr.play_sfx` throttles on wall-clock `Time.get_ticks_msec()`, and a sound that got through
   the throttle called `randf_range` for pitch variation — from the *global* RNG that `Tower`'s muzzle
   jitter and `Hero`'s `kill_mark` passive also drew from. How many sounds happened to play therefore
   shifted the gameplay random sequence.

   Fixed by giving `AudioMgr` its own `RandomNumberGenerator` and moving the two gameplay draws onto
   the seeded stream (`enemies.rng`), so no gameplay randomness comes from the global RNG any more.
   Two concurrent runs of the same build and seed now produce byte-identical output, verified under
   deliberate CPU contention.

---

## 9. Campaign balance result

`tests/balance_sim.gd` plays a full 25-wave campaign with an AI player bound by the same rules as a
human: the map's real starting emeralds, purchases and upgrades only when affordable, hero abilities
on cooldown, towers placed in the free zone furthest from the ones already built.

**Run it with `--fixed-fps 60`.** Without a fixed timestep the result is not reproducible and means
nothing — see section 8.7. `tools/balance_sweep.sh` does this for you.

ParrotX2 on Fort Feather at normal, on the 2D board:

| seed | outcome | wave  | lives   | leaks | boss killed |
|------|---------|-------|---------|-------|-------------|
| 1    | VICTORY | 25/25 | 54/100  | 46    | yes         |
| 2    | VICTORY | 25/25 | 100/100 | 29    | yes         |
| 3    | VICTORY | 25/25 | 32/100  | 52    | yes         |
| 4    | VICTORY | 25/25 | 41/100  | 55    | yes         |
| 5    | VICTORY | 25/25 | 39/100  | 48    | yes         |

Five wins from five, Saparata killed in every one, four of them ending on 32–54 lives. Wave 25 *is*
the boss wave, so a VICTORY is by definition a boss kill.

**Five of five was the target for four of five, and that miss is the interesting part** — see the
cliff below. Where the life bar goes, on seed 1: 157 threat reached the base across 46 leaks, 101
lives were lost, 56 were mitigated (36%), 55 were healed back.

**These numbers have now been refitted three times, each time because a bug was hiding how strong the
board really was.** That is the honest summary of this section: a wave curve is fitted to whatever the
code actually did on the day it was fitted, so fixing a combat system invalidates it.

1. The spatial-grid bug (section 13) meant splash and tower targeting only ever saw the first unit in
   each 4×4 cell, so the curve before it had been fitted against a board doing a fraction of its
   configured damage. Fixed → 5 of 5 without losing a life, mean kill depth 0.42.
2. The `wall` ability had never blocked anything — nothing read `blocks_path` during movement — and
   Fort Feather's detonation had never fired. Fixed → the same 0.22 curve went from 79/96/71/77/93
   lives to **100/100 on all five seeds**.
3. Leak mitigation, newly wired up, was bounded to 60% of a leak. That one change took the 0.65 curve
   from 4 of 5 to **0 of 5, every seed dead at wave 20–21**.

The third one is worth dwelling on, because the first diagnosis was wrong. The suspicion was that
`leak_reduction` stacking to 17 across the roster was flooring every leak at one life. Measurement
said otherwise: this build order buys **2**, and the one-life floor never bound. But 2 points turned
out to matter enormously, because the average leak is worth only 3.7 threat — a flat −2 was halving
the median leak and absorbing 55% of all threat that reached the base. At ~50 leaks a run, bounding it
costs about a life per leak, which is the entire margin of the fit.

Bracketing the late-game HP slope, by column. Read down a column: each is the same curve against a
different set of working systems, and the gaps between them are what those systems are worth.

| slope | walls inert | walls working | + bounded mitigation |
|---|---|---|---|
| 0.13 | 5 of 5, never lost a life | | |
| 0.20 | 5 of 5, 71–96 | | |
| 0.22 | 4 of 5, 51–98 | 5 of 5, all 100/100 | |
| 0.245 | 3 of 5, 72–84 | | |
| 0.30 | lost at wave 21 | | |
| 0.45 | | | 3 of 3, 51–68 |
| **0.55** | | 3 of 3, 66–79 | **5 of 5, 32–54 (one seed 100)** |
| 0.60 | | | 2 of 5, wins on 15–35 |
| 0.65 | | 4 of 5, 37–58 | 0 of 5, all dead at 20–21 |
| 0.75 | | 2 of 3, 26–35 | |

**There is no slope that wins four of five.** The transition is a cliff — 5 of 5 at 0.55, 2 of 5 at
0.60 — and every loss lands on wave 21. The curve stops on the safe side of it, and the 5 of 5 it
produces is not the 5 of 5 that meant "no campaign": those wins ended on 100/100 having leaked five
times, these end on 32–54 having leaked around fifty.

Two things that only showed up by doing it this way rather than by picking a number:

1. **The late curve's constant has to meet the mid-game curve where it ends.** A first attempt jumped
   from 1.73 at wave 15 to 2.90 at wave 16 and the run simply died there. A 68% step in one wave is a
   wall, not a difficulty curve.
2. **Wave 21 is where it breaks when it breaks, and that is authored content.** Wave 20 is a wither
   plus ten flying elytra gliders; wave 21 follows immediately with ten tier-6 chungies and five shield
   bearers at 50% armour who also block a third of all projectiles. Flyers, then heavy armour, back to
   back. A person answers that by buying into it. The benchmark cannot — it follows one fixed build
   order and never adapts — so past a certain point it falls over there every time. That is the
   benchmark's ceiling showing rather than the curve's, and it is why the shipped slope sits below it.
   The exact point has moved with each refit (0.24 with the walls inert, 0.60 now), but the wave has
   not.

**A probe confirms this is the build order, not the economy.** `balance_sim.gd` takes an optional
start-wave argument that jumps to a wave and grants the money a run would plausibly have by then.
Dropped into wave 20 with 74,469 emeralds, the AI built 17 towers and 87 upgrades and *still* lost on
wave 21, finishing with 8,122 unspent that it could not usefully deploy. Money is not the answer to
wave 21; adapting the build is, and the benchmark cannot. (That probe was run on seed 4 under the
0.22 curve, when seed 4 was the seed that lost there. Seed 4 wins under the shipped curve; the probe
has not been re-run, so read it as a result about wave 21 rather than about that seed.)

That probe was wrong on its first run and the mistake is worth recording, because the result looked
plausible. It granted only the banked wave rewards — 7,230 by wave 20 — on the reasoning that
estimating kill income would make the board size a guess. But a campaign pays 14,762 in wave rewards
against roughly 151,580 actually earned: **bounties are about ten times the rewards.** The probe was
funding a wave-20 board at a tenth of its true value and returned a defeat that said nothing about
wave 21 at all. A conclusion drawn from that first run would have been an artifact of a tenfold
funding error. The grant now scales by the measured ratio.

What the probe still cannot do is reproduce a real board's *upgrade history* — depth bought in the
order the pressure demanded, rather than a lump sum spent at once — so read it as "can a board of
about the right value survive the finale", never as "is the campaign balanced".

The seeds are also markedly bimodal: a board either finishes the campaign or breaks outright at wave
21, with nothing in between — at 0.60 the two wins end on 15 and 35 lives and the three losses end on
zero. The spread among wins is wide as well: seed 2 finishes the shipped curve on 100/100 while the
other four land between 32 and 54. That is seed composition talking, not the slope, which is another
reason a single run is worthless as evidence.

Reproduce with:

```
tools/balance_sweep.sh parrotx2 normal fort_feather 1 2 3 4 5
```

Read this as a claim about the *simulated* player, not a human one — see KNOWN_LIMITATIONS §5 for
what that does and does not establish.

### The benchmark was measuring a moving target

Every balance figure this report published before this section was measured against a simulation that
**wrote persistent progression and then read it back**. `_finish_run` calls `record_run_result` and
`save_game()`; `Hero.setup` applies `damage *= 1 + 0.03 * (meta_level - 1)`. After a long session of
sweeping, the save held:

```
parrotx2:    meta level 20 (capped), 123 runs
flamefrags:  meta level 16,            7 runs
spokeishere: meta level 14,           11 runs
wemmbu:      meta level 11,            7 runs
```

So the hero comparison ran with ParrotX2 at **+57% hero damage** and Wemmbu at **+30%**, a per-hero
handicap proportional to how often each had been measured. It also explains a discrepancy that
surfaced by accident: the same seed reported a wave-22 defeat in one sweep and wave 18 an hour later
on identical code. Determinism *within* a moment was verified byte-identical, so the drift was coming
from the save file between them.

This is the third bug of exactly this shape in this benchmark, after an unseeded RNG and a variable
timestep. A result is reproducible only when every input is pinned, and persistent progression is an
input. `SaveSystem.begin_benchmark()` now isolates the run in both directions, and the sim prints its
meta level so a contaminated run is visible in the output rather than silently wrong.

**The wave curve was fitted before this and has not been refitted since.** On a clean benchmark
ParrotX2 wins three of three without dropping below 100 lives.

### Hero parity: three of four heroes lose every seed

The sweep above is ParrotX2. Running the other three on the same curve, three seeds each:

Superseded by the isolated grid below; the numbers this table originally carried were measured with
per-hero meta bonuses of +30% to +57% damage. On a clean benchmark, three seeds each:

| hero | result |
|---|---|
| ParrotX2 | 3 of 3, all three on 100/100 lives |
| Wemmbu | 3 of 3, wins on 51/21/48 lives |
| SpokeIsHere | 2 of 3, wins on 27 and 55 lives |
| FlameFrags | 0 of 3, dead at waves 19/19/19 |

Three of four now finish, against one when this was first measured on a clean benchmark. Wemmbu's fix
was scale — the webs already lingered, they were too small and too short — and the value shipped was
probed as a deliberately oversized bracket that the measurement then endorsed; dialling it back to 9
units and 11 seconds returned him to 0 of 3.

FlameFrags is the exception, and the reason his earlier buffs kept producing byte-identical runs is
that Trained by Theo unlocked at level 9, which he reaches around wave 17 — the passive was live for
two waves of a campaign. At unlock 4 the carts become his largest damage source at **31% of his run's
total**, and he still loses all three seeds at wave 19; a larger blast made him worse. His mean kill
depth is **0.19 of the path, 82% of kills in the first two tenths**: at 6.5 attack range his damage
and the carts it drops all land in one place, and whatever survives it walks the rest of the path
against towers alone. That is kit shape, not magnitude.

Two abilities were found not to be doing what their own text says, both of them the persistent half of
a hero's kit. Wemmbu's Cobweb Trap "throws cobwebs over a stretch of path" but only swept whoever
stood there at the instant of the cast; the webs now linger (`EnemyManager.add_hazard`) and it is his
best result to date. FlameFrags' Trained by Theo "drops a TNT minecart that explodes" but detonated
instantly and dropped nothing; it now leaves a real cart on a fuse, which is faithful and
**balance-neutral** — 120 damage in a 2.4-unit radius is trivial at wave 19, so persistence by itself
buys nothing unless the persistent thing hits hard enough to matter.

And the board was shooting its own property: both `Tower` and `Hero` request targets with
`ignore_structures: false` so that the builder enemy's walls can be shot, but ParrotX2's 2000 HP Fort
Feather wall and FlameFrags' carts use the same entity, so a friendly wall absorbed the player's own
tower fire for as long as it stood. Structures now carry per-slot ownership and targeting skips the
player's own. It moved ParrotX2 from 82 to 100 lives on the one seed that had been costing him any,
and left the three heroes who place no structures byte-identical — the check that the fix is scoped
correctly.

Two of ParrotX2's abilities were also found to be far stronger than their own descriptions. `rate_mult`
multiplies the attack *interval*, so Royal Decree's `0.55` was **+82% fire rate on every tower** against
a stated 45%, and his ultimate's `0.4` was **+150%** against a stated +60%. Every other hero's numbers
match their text exactly (FlameFrags' "three times as fast" is `0.34`, Wemmbu's "twice as fast" is
`0.5`), so this was a bug rather than a design choice, and only the two board-wide buffs had it. Both
now match what the player is told — which is also, by itself, the balance correction the clean data
called for. He is still 3 of 3.

Two controls make the result interpretable rather than just bad news.

**What each kit is worth.** Stripping every ability and passive from each hero and comparing waves
survived on the same seed:

| hero | no kit | with kit | the kit is worth |
|---|---|---|---|
| SpokeIsHere | wave 16 | wave 25, win | +9 waves |
| ParrotX2 | wave 18 | wave 25, win | +7 waves |
| Wemmbu | wave 17 | wave 20 | +3 waves |
| FlameFrags | wave 19 | wave 21 | +2 waves |

SpokeIsHere has no global tower buff and his kit outperforms ParrotX2's, which rules out
"board-multiplying versus personal-damage" as the explanation. The two effective kits both carry
**persistent board presence** — summons, a lane-blocking wall, a converted enemy, a debuff riding the
enemies — while Wemmbu's and FlameFrags' kits are instantaneous damage plus a self-buff, leaving
nothing on the board once the ability resolves. Two rounds of buffs aimed at the superseded theory
(wider tower auras, then enemy-attached multipliers) both measured as noise, which is consistent.

**Strip ParrotX2's kit entirely** — every ability, every passive — and he dies on wave 19 with 49
leaks, which is where the other three finish carrying their full kits. So those kits are worth about
what no kit is worth. The cause is structural: towers do 85–99% of the damage, ParrotX2 is the only
hero who multiplies them (Royal Decree on every tower's fire rate, his ultimate on every tower's
damage), and personal damage does not scale with a 17-tower board. Wemmbu was measured doing 63% of
all damage in his run and still lost.

**Remove only ParrotX2's aura passive** and the run was unchanged to the byte — 584 kills, 16 leaks,
95/100. That null result was real (the same edit mechanism, used to strip the whole kit, collapses the
run completely, so it was not an edit that failed to take) but it is **superseded**, and by a change
made in the same sitting. The aura's radius is 9 units, and at that point the benchmark could not move
the hero, so it never covered a tower. With repositioning in place the aura lands and is worth a great
deal: seed 1 goes from 95 lives and 16 leaks to 100 lives and 4.

The lesson is the one this report keeps relearning: a measurement is only valid for the configuration
it was taken in. Repositioning helped the hero who was already winning far more than the three who
were losing.

### What the hero XP bug was hiding

Heroes finished a full 25-wave campaign at **level 5**. Every ultimate in the game unlocks at level
10. No ultimate had ever been cast in a real campaign, and neither had any of the level-8 abilities.

Every enemy carries an authored `xp` value — 1 for a scout, 400 for Saparata — and they sum to 5,805
across a campaign, against the 5,565 needed for level 15, the highest unlock in the game. That is the
authored progression. The code awarded a flat 1 for anything a tower killed, and a flat 3 for anything
the hero killed (its `is_alive(slot)` guard is always false by the time the kill signal fires), so a
hero banked about 700 XP a run. Awarding the type's own value takes ParrotX2 to level 11, and
`parrotx2:summon` appears in the damage share for the first time — Royal Army had never been cast.

This is why the curve is not refitted here: the fix made the one hero who can win the campaign
markedly stronger (54 → 95 lives on seed 1, leaks 46 → 16), and refitting upward would tune the map
to him and put it further out of reach for the three who already lose. See KNOWN_LIMITATIONS §5.

Hero repositioning is covered by `tests/headless_run.gd`, which relocates the hero to a build zone
mid-run and asserts the cooldown starts and the bond multiplier stays fixed across 21 aura refreshes
(the loop that used to compound it).

---

## 10. The 2D board

The map is now painted flat (`BoardPainter`) instead of extruded into voxels, with the 3D characters
standing on it. Verified by screenshot at `docs/screenshots/04-fort-feather-map.png` and
`05-gameplay.png`, and by `tests/dump_board.gd`, which writes the painted board straight to a PNG with
no camera or lighting involved so the art can be checked on its own.

Three things were found and fixed by looking at the renders rather than the code:

1. **Depth fog washed the board out.** Framing a whole board puts the camera ~150 units back, where
   the map's fog density drained all contrast uniformly. Fog is now skipped for a flat board.
2. **Pale blocks clipped to white.** Sand came out as a flat white rectangle once the sun and the
   filmic tonemap were applied over already-shaded painted art. The board material is tinted to 0.82
   to keep the texture.
3. **The board read as a 3D world, not a board.** At the default 52° field of view it was a strong
   trapezoid. A 34° lens from further back flattens the projection towards orthographic.

Build zones are flattened to ground level on a board, so tower and hero models stand on the painted
surface rather than floating at the voxel world's elevations. Targeting is unaffected: `query_range`
was already planar in x/z, so no tower's coverage changed.

---

## 11. Real Minecraft assets

The supplied skins and resource pack replaced most of the procedural stand-ins.

**Skins.** All four playable heroes and all fourteen tower characters now use skins supplied by the
project owner. The hero mapping was checked against the artwork before use rather than taken from the
order the files arrived in — skin 4 is a crowned king with parrot wings and skin 1 is covered in
flames, which is the opposite of how they were listed. Verified by rendering all eighteen
(`tests/visual_heroes_test.gd`).

**Armour.** Armour is now drawn the way Minecraft draws it: a copy of the humanoid model inflated by
1 pixel (helmet, chestplate, boots) or 0.5 (leggings) and textured by the pack's equipment layers,
which use the 64×32 legacy net. Three things a naive port gets wrong, all found by rendering a tier
line-up:

1. **Leather came out white.** Its layers ship greyscale because vanilla multiplies them by the dye
   colour at runtime. Fixed with the default leather tint plus the untinted `leather_overlay`.
2. **Anything the pack cannot draw vanished.** `layers_available()` is true if *any* slot has a
   texture, and the first version then skipped the slots without one — so capes, elytra and this
   project's own royal and cinder liveries silently disappeared. `slots_without_layers()` now keeps
   them on the shell-box treatment.
3. **Boots and leggings both cover the legs.** Listing the leg parts twice in one layer would
   z-fight, so a part is only added once per group. Asserted in `test_armor_layers`.

Enemies render through MultiMesh, and each armour group needs its own texture, so a group gets one
extra MultiMesh per layer sharing the skin's transforms — the merged skin mesh drops the slots the
layers now draw. Verified by cropping into a live board render.

**The three slots vanilla has no equipment layer for**, plus this project's invented liveries, were
the last things still drawn as coloured boxes. All four are now real art:

- **Royal and cinder liveries** are dyed leather. Minecraft has no coloured plate armour, but
  leather is dyeable, so a livery is the real leather layer multiplied by its dye with the undyed
  overlay on top — the same compositing vanilla does, and what a player who actually wanted a royal
  or Cindercrest uniform in Minecraft would have to wear.
- **Capes** use banner cloth, dyed the same way. Minecraft ships no cape texture at all — capes are
  per-account and not part of a resource pack — so banner cloth is the closest real one, on vanilla's
  own 10×16×1 CapeModel box.
- **Elytra** have a texture and a model of their own (`entity/equipment/wings/elytra`, one 10×20×2
  wing at uv (22,0) mirrored for the other side), so both are used directly.
- **The crown** is the one shape Minecraft has no equivalent for, so the geometry stays this
  project's; the surface is the gold block's own art rather than an invented yellow.

Only the *shape* of the crown is now non-vanilla. Across every enemy, tower and hero in the shipped
data, `slots_without_layers` returns empty — nothing is left on the coloured shell boxes
(`tests/enemy_item_check.gd` prints this per enemy; `tests/visual_armor_test.gd` renders all twelve
combinations front and back). The boxes are still the no-pack fallback, and are still exercised: with
`assets/resourcepack/` moved aside the suite runs 2322 assertions with 0 failures.

**Held items.** Weapons were coloured boxes; they are now built from the pack's own art, and
Minecraft turns out to build three different kinds of thing:

- **Sprites.** Most items are the flat 16×16 inventory icon extruded into a slab 1/16 of a block
  thick. Front and back quads carry the whole sprite, and an edge quad is emitted wherever an opaque
  pixel borders a transparent one, which is what gives a sword its stepped rim instead of a
  cardboard silhouette. Vanilla also poses two classes of sprite differently — tools use the
  `handheld` transform, rolled onto the sprite's handle-to-tip diagonal, and everything else uses
  `generated`, standing upright — and both are reproduced, because a sword posed like a potion
  points sideways out of the fist.
- **Box models.** Shields and banners are not sprites at all: the game draws them from small box
  models with their own entity textures (`shield_base_nopattern`, `banner_base`), so they are built
  with the same box net the body parts use, at vanilla's own UV offsets. Banner cloth ships white
  and is multiplied by the dye colour, exactly like leather armour.
- **Blocks.** TNT is a block, so it is a cube wearing `tnt_side`/`tnt_top`/`tnt_bottom` composited
  into a box net.

Two things only showed up on screen:

1. **The potion was a white blob.** `item/potion.png` is the greyscale *liquid*; the glass is a
   separate `potion_overlay`, and the game multiplies the first by the potion colour before
   compositing. Same trap as leather.
2. **The pose that suited boxes hides sprites, and copying vanilla's does not fix it.** This took
   three passes and a test that renders one character per walking direction, because every failure
   only shows from *some* angles and a single screenshot always looks fine.

   Minecraft's own third-person pose is: blade straight forward, edge up, gripped part-way along the
   handle. Reproducing it exactly fails here in two separate ways. A character walking *away* from
   the board camera has a forward-pointing weapon hidden behind their own body — a quarter of every
   path with the weapon simply gone. And a one-pixel-thick sprite seen edge-on is not thin, it is
   invisible; vanilla gets away with edge-up because its camera can move, and this one cannot.

   Rolling the item flat instead (the first attempt, a −100° tilt) solved visibility and produced
   the opposite complaint: the weapon read as *balanced on* the fist rather than held. That turned
   out to be a separate bug — the grip point was the extreme corner of the sprite, so the fist was
   pinching the very tip of the pommel with nothing passing through the hand.

   Both are fixed. The fist now closes 3.5 sprite pixels up the handle, and the socket moved from
   the wrist joint at the arm's base into the fist itself. The item is carried swung out to the
   character's right and angled down, which is never behind the torso and never square to the
   camera's line of sight for long. There is a hard limit behind that choice worth recording: the
   further the blade tips below horizontal, the more its face has to turn away from a camera that
   is looking down, and past roughly 38° of tip — the camera's own pitch — there is *always* a
   walking direction where the item vanishes. `test_held_pose` asserts the item swings clear of the
   body, hangs downward, keeps at least 25% of its face towards the camera at all 72 sampled yaws,
   is socketed in the fist rather than the wrist, and that a 20px item's tip clears the ground.

All 22 weapon ids in the shipped data resolve to real art (`tests/item_check.gd`), and all 24 armed
enemies get it on the MultiMesh path with the box model correctly dropped from the merged skin mesh
rather than drawn underneath it (`tests/enemy_item_check.gd`). Rendered for eyeballing by
`tests/visual_items_test.gd`, which can shoot the line-up from the front, the side, or the board
camera's own angle.

**Glint.** The procedural stripe is replaced by Minecraft's own `enchanted_glint_armor.png`, sampled
twice with different scroll directions and speeds and added on top; the stripe remains as the
no-pack fallback. Items use `enchanted_glint_item.png`, which is the sheet vanilla uses for them.

**Blocks.** Covered in section 10's notes on tinting and animated-texture frames.
