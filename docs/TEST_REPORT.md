# Test Report

Everything below was actually executed in this build environment. Commands are given so any claim can
be re-run. Where a measurement is limited by the environment, that is stated rather than glossed.

**Environment:** Ubuntu 24.04 x86-64 VM, 4 cores, 15 GB RAM, **no GPU** (Mesa llvmpipe software
rasteriser). Godot 4.4.1-stable.

---

## 1. Automated test suite — 2198 assertions, 0 failures

```
godot --headless --path . -s tests/run_headless.gd -- res://tests/test_suite.gd 4
```

```
PASSED: 2198
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

| Enemies | FPS | Mean frame | Draw calls |
|---|---|---|---|
| 50 | 7.5 | 133.29 ms | 580 |
| 100 | 7.5 | 133.28 ms | 580 |
| 250 | 7.5 | 133.39 ms | 580 |
| 500 | 7.5 | 133.33 ms | 578 |
| 1000 | 7.5 | 133.27 ms | 578 |

**Read this carefully.** The 7.5 fps is llvmpipe filling 1280×720 in software; there is no GPU in this
VM. The number that matters is that **frame time and draw calls are flat from 50 to 1000 enemies** —
133.29 ms vs 133.27 ms, 580 vs 578 calls. Adding 950 enemies added no draw calls and no measurable
cost. The frame time is fill-rate bound on the software rasteriser, not geometry bound.

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
