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

What that testing *does* establish is the thing the architecture was built for: **frame time and draw
calls are flat from 50 to 1000 enemies** (133.29 ms → 133.27 ms; 580 → 578 draw calls). Enemy count
adds no draw calls and no measurable cost. Headless timing shows the game logic for 1000 enemies costs
0.5 ms per frame.

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
- **The AI loses one run in five** on the current tuning, always in the last two waves. That is
  deliberate — a benchmark that always wins tells you nothing — but it means the margin is thin, and
  a change that looks harmless can push it over.
- **Signature (tier 4) upgrade costs were still set by feel**, not fitted.
- **No human has played it at normal speed** with the actual UI, so nothing is known about whether the
  game *feels* good — only about whether it can be won.

Two balance-relevant systems are also currently inert and should be treated as unbalanced rather than
absent: the ultimate ability effect `leak_cap` is parsed and stored but never read by anything
(`Hero.leak_damage_cap()` has no callers), and the `wall` ability spawns a `cobble_wall` unit that
nothing checks for during movement, so walls do not actually block the path.

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
- **The hero cannot be repositioned mid-run.** It is placed on the keep zone at the start and stays
  there. Repositioning is the obvious next feature.
- **No save-slot management.** One save file, at `user://save.json`.
- **Settings are not remapped in game.** Key bindings are fixed and documented in Settings.
- **`potion_brewer`'s heal aura is per-frame-throttled** to twice a second; with many brewers stacked
  this is an approximation, not an exact heal-rate simulation.

---

## 8. What is genuinely proven

Because the list above is long, it is worth being equally precise about the other side:

- 2377 automated assertions pass with 0 failures.
- A full run builds, places and upgrades towers, spawns and kills enemies, pays out and advances waves
  with no errors logged.
- All five boss phases fire in order; the mini-boss spawns; the blimp flies, drops 10 paratroopers,
  and can be shot down to stop the drops; the boss dies and the stat is recorded.
- 1000 concurrent enemies cost 6 extra nodes and 0.5 ms.
- The Windows exe is a valid x86-64 PE that boots and loads all its data from its embedded PCK.
- Every screen renders correctly, verified by screenshot: menu, hero select, codex, map, live gameplay.
