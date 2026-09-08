# Known Limitations

An honest account of what is missing, unverified, or deliberately deferred. Nothing here is described
as working when it is not.

---

## 1. Character skins are supplied; two identical sets remain

**Every character in the game now uses a real skin supplied by the project owner** — the four
playable heroes, all fourteen tower characters, and all seventeen enemies, bosses and supporting
characters. The only procedural skins left are `uv_test` and `uv_test_legacy`, which are test
fixtures for the UV-mapping tests and are meant to stay generated.

Two things about them are worth knowing:

- **Six characters share one skin.** `chungie`, `chungie_b`, `chungie_c`, `cindercrest_soldier`,
  `lawman` and `pirate` are byte-identical — the Minecraft default. For the chungies that reads
  correctly (they *are* the new players Cindercrest is killing), but `chungie_b` and `chungie_c`
  exist to give the horde visual variety and currently give none, and a Cindercrest veteran looking
  like a new player is backwards. Their armour tiers still tell them apart in play. Dropping distinct
  PNGs at those ids fixes it with no code change.
- **`mafia_invis` has no supplied skin on purpose.** The Invisible Mafia is invisible; the enemy
  renders with the `F_INVISIBLE` ghost treatment, and the generated silhouette is only what shows
  when a detection tower reveals it.

**On the supplied skins:** they are used at the owner's direction and recorded in the manifest as
`supplied_by_developer`. That covers use inside this project; it is not a redistribution licence, so
confirm rights with each skin's author before shipping the game publicly.

**On the bundled Minecraft textures:** `assets/resourcepack/` holds a vanilla-layout Minecraft
resource pack — Mojang's artwork, not this project's. It is committed at the project owner's explicit
direction after the licensing position was raised. **Mojang's permission has not been obtained and is
not claimed.** Anyone redistributing this repository, or a build made from it, is responsible for
clearing that. The dependency is deliberately shallow: delete the directory and `ResourcePack` falls
back to the generated placeholders, so nothing breaks.

**On the music:** `assets/audio/music_main.mp3` is CHAOS CONSTRUCT by AZALI, supplied by the owner
from YouTube. No licence from the artist has been obtained or is claimed. The generated original
tracks are still in the tree; reverting is a one-line data change.

---

## 2. Research was done through search snippets, not full pages

The community wiki, the official site and the fan hub were all **blocked by this environment's network
policy**. Research proceeded via search-engine summaries of those pages.

Every claim cites the page it came from and carries a confidence tier — but a citation records *which
page a statement came from*, not that the page was read end to end. A `supported` entry has not been
cross-checked against the episode.

This is stated in the schema of `data/lore/characters.json`, in [LORE_RESEARCH.md](LORE_RESEARCH.md),
and shown next to every Codex entry in game. Treat `supported` as "the wiki says so", not "verified".

---

## 3. No frame rate has been measured on real GPU hardware

This VM has **no GPU**. Rendering measurements used Mesa's llvmpipe software rasteriser, which spends
133 ms per frame filling 1280×720 regardless of scene content.

What that testing *does* establish, because these are counted rather than timed: **draw calls and node
count are flat from 50 to 1000 enemies** (828 → 848 calls, 10 extra nodes). Enemy count adds
instances, not draws. Headless timing shows the game logic for 1000 enemies costs 0.5 ms per frame.

It does **not** establish that the renderer scales, even though the frame times are also flat: 133 ms
is what llvmpipe charges for a 1280×720 frame regardless of contents, so the flatness of the timing
is the rasteriser's floor, not a result. An earlier version of this file quoted those frame times as
if they were evidence; worse, they were measured while the enemy MultiMeshes were empty and nothing
was drawn at all. Both are corrected in [TEST_REPORT.md](TEST_REPORT.md).

What it does **not** establish is an actual frame rate on a real machine. No fps figure for real
hardware is claimed anywhere in this repository, and none should be inferred.

---

## 4. The Windows exe was verified under Wine, not on Windows

The binary is a valid PE32+ x86-64 image with an embedded PCK, and it **boots and runs** under Wine
9.0: the engine starts, the PCK mounts, all data loads, autoloads run and the main scene starts.

A windowed run under Wine fails at display creation because Wine's software GL does not expose OpenGL
3.3 and ANGLE/EGL is not installed. **The game has not been seen rendering on real Windows.** On real
hardware it should use Vulkan (Forward+) with OpenGL 3 configured as a fallback, but that is a
reasonable expectation, not a tested result.

---

## 5. Balance is tuned against a simulated player, not a human one

The campaign is now known to be winnable, and it is tuned — but by an AI player, not a person.

`tests/balance_sim.gd` plays a full 25-wave campaign under exactly the rules a human has: the map's
real starting emeralds, no free money, purchases and upgrades only when affordable, hero abilities on
cooldown. `tools/balance_sweep.sh` runs it across several seeds and reports the spread. That is what
the current wave numbers (`tools/tune_waves.py`) were fitted to.

What this establishes: the campaign can be won from wave 1 to the Saparata kill without cheating, the
difficulty curve responds to tuning, and the boss is reachable and beatable by a legitimate board.

What it does **not** establish, and these are real gaps:

- **A human is not this AI.** The simulated player follows one fixed build order and one upgrade plan,
  places each tower in the free zone furthest from its existing ones, and never sells, re-targets, or
  repositions the hero. A person will play better in some ways (reacting to a wave's composition) and
  worse in others (missing ability windows). The AI is a competent-but-unimaginative benchmark, so the
  game is probably somewhat easier for an engaged human than these numbers suggest.
- **Only one hero and one map are tuned.** The sweep above is ParrotX2 on Fort Feather at normal.
  Wemmbu, FlameFrags and SpokeIsHere have had no campaign-level tuning at all, and neither has
  Merchant City or the easy/hard difficulty multipliers.
- **Run-to-run variance is wide, and reproducibility took two fixes.** Seeding the RNG was not
  enough: the game advances on wall-clock delta, so the same build at the same seed produced "won
  with 59 lives" and "lost on wave 19" depending on machine load. The simulation must be run with
  `--fixed-fps 60` (which `tools/balance_sweep.sh` does, and which the sim now warns about if
  missing). Even then the spread across seeds is wide enough that a single run should never be used
  to judge a change.
- **The AI wins all five seeds on the current tuning, and the target was four.** That is a real miss,
  not a rounding of the target: the aim is a benchmark that loses occasionally, because one that
  always wins measures nothing. There is no slope that produces it. The transition is a cliff — 5 of 5
  at the shipped 0.55, 2 of 5 at 0.60 — and every loss lands on wave 21. Wave 20 is a wither plus ten
  flying elytra gliders and wave 21 follows it with tier-6 chungies and shield bearers at 50% armour:
  flyers, then heavy armour, back to back. A person buys into that; the AI cannot, because it follows
  one fixed build order, so it does not degrade across wave 21, it falls off it. The curve stops on
  the safe side. What makes the 5 of 5 different from the 5 of 5 that meant "no campaign" is the
  margin: those wins ended on 100/100 having leaked five times, these end on 32–54 having leaked
  around fifty.
- **Outcomes are bimodal across seeds.** A board either finishes the campaign or breaks outright at
  wave 21, with nothing in between: at 0.60 the two wins end on 15 and 35 lives and the three losses
  end on zero. The spread among wins is wide too — one seed finishes the shipped curve on 100/100
  while the rest land in the thirties and fifties. That is wave composition talking, not the tuning,
  and it is one more reason a single run is worthless as evidence about a change.
- **The curve has been refitted twice, both times because a bug was masking the board's real power.**
  First the spatial grid returned only the first enemy in each cell, so splash, auras and targeting
  were working at a fraction of their configured strength. Then the `wall` ability turned out never
  to have blocked anything. Each fix made the board stronger and sent the benchmark back to 100/100
  on every seed. The honest reading is that the numbers in `tools/tune_waves.py` are fitted to
  whatever the code actually did on the day they were fitted, so a fix to a combat system invalidates
  them and the sweep has to be re-run — the file keeps both fits side by side for exactly that reason.
- **Signature (tier 4) upgrade costs were still set by feel**, not fitted.
- **No human has played it at normal speed** with the actual UI, so nothing is known about whether the
  game *feels* good — only about whether it can be won.

Both of the balance-relevant systems previously listed here as inert now work: `leak_cap` is read
through `GameController._mitigate_leak`, and walls placed as barricades are consulted during movement
and detonate when they go down.

Mitigation is now bounded to 60% of a leak (`GameController.LEAK_MITIGATION_MAX`), because
`leak_reduction` is a flat subtraction that stacks to 17 across the roster while enemy threat runs
1–12. Without the bound, a player who bought Deputy_Ace's Shield Wall and Fymada's Evacuation to
depth would reduce nearly every leak to the one-life floor. The bound is not a precaution taken on
paper: the benchmark buys only 2 points, and because the average leak is worth 3.7 threat those 2
points were absorbing 55% of everything that reached the base. Bounding them dropped that to 36% and
cost roughly a life per leak, which was enough on its own to turn a 4-of-5 curve into 0-of-5.

What is still untested is the maximum-reduction build itself. The simulated player's upgrade plan
skips the Evacuation path entirely and never approaches 17 points, so nothing here measures what a
board built specifically around leak reduction feels like — only that it can no longer make leaks
free.

---

## 6. Content scope

Implemented: **2 maps** (Fort Feather with 25 waves and the full boss; Merchant City with 11 waves and
a mini-boss).

Designed and documented but **not implemented** — every one has research behind it in the database:

- Maps: Spawn (four historical variants), Capital City, Highwater, Steampunk City, Kingdom of the
  Caves, the Far Lands, the Nether, Purgatory, Lomedy's Farm, Skymore.
- Bosses: Arachn1d, Ashswagg, ClownPierce, LettuceK, PrinceZam, JamatoP.
- Factions: the Invisible Mafia, the Law, the Pirates, the Spider Web Faction, the Zam Empire, the
  NULL and the toxic civilization are all defined in `data/enemies/factions.json` with skins, stat
  multipliers, special units and music, but only Cindercrest is exercised by a shipped map.

Adding a map is a JSON edit plus a wave file; adding a faction to an existing map is a one-line change.

---

## 7. Smaller gaps

- **The exe has the default Godot icon** and no embedded version metadata, because `modify_resources`
  needs `rcedit`, a Windows tool unavailable here. The in-game window icon is set correctly.
- **Music is short loops.** Each track is 8 bars (roughly 17 seconds) of synthesised chiptune. It
  loops seamlessly but will get repetitive over a long run.
- **Voice acting covers two of five speaking characters.** ParrotX2 and Wemmbu each have all
  thirteen lines recorded and playing; SpokeIsHere, FlameFrags, Saparata and the fourteen towers are
  still on-screen dialogue only. The playback path is convention-based, so the remaining sets need
  files and no code (see docs/VOICE_LINES.md).
- **Godot logs a resource leak at exit.** Static caches (shaders, the armour texture, block textures,
  prop meshes) outlive the scene tree teardown. Harmless at shutdown; it does not leak during play.
- **Enemies do not path around obstacles.** They follow a fixed polyline with a lateral offset. Walls
  block by stunning rather than by rerouting; there is no navmesh.
- **The AI benchmark still builds by zone.** Placement is free-form now — a tower stands wherever it
  is put, checked against the board edge, the road and other towers' footprints — but
  `tests/balance_sim.gd` still places at the map's suggested build zones. That makes it a *weaker*
  player than a person, who can cluster towers on a corner the zones do not cover, so the tuning it
  produces is, if anything, on the hard side.
- **No save-slot management.** One save file, at `user://save.json`.
- **Settings are not remapped in game.** Key bindings are fixed and documented in Settings.
- **`potion_brewer`'s heal aura is per-frame-throttled** to twice a second; with many brewers stacked
  this is an approximation, not an exact heal-rate simulation.

---

## 8. What is genuinely proven

Because the list above is long, it is worth being equally precise about the other side:

- 2485 automated assertions pass with 0 failures (2322 with the resource pack removed).
- A full run builds, places and upgrades towers, spawns and kills enemies, pays out and advances waves
  with no errors logged.
- All five boss phases fire in order; the mini-boss spawns; the blimp flies, drops 10 paratroopers,
  and can be shot down to stop the drops; the boss dies and the stat is recorded.
- 1000 concurrent enemies cost 6 extra nodes and 0.5 ms.
- The Windows exe is a valid x86-64 PE that boots and loads all its data from its embedded PCK.
- Every screen renders correctly, verified by screenshot: menu, hero select, codex, map, live gameplay.
