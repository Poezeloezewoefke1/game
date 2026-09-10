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
  places each tower in the free zone furthest from its existing ones, and never sells or re-targets.
  It does now reposition the hero, but by a crude rule — stand on the build zone covering the most
  towers — with no dodging, kiting or following a wave. A person will play better in some ways
  (reacting to a wave's composition) and worse in others (missing ability windows). The AI is a
  competent-but-unimaginative benchmark, so the game is probably somewhat easier for an engaged human
  than these numbers suggest.
- **One hero of the four still cannot win the campaign, and a second is far above the target band.**
  This is the most serious balance problem left in the game, and it is measured, not suspected. Measured on an isolated benchmark (every hero at meta
  level 1, nothing written back), three seeds each. These are the first hero numbers in this
  repository not contaminated by persisted progression, and they supersede every hero table
  published before them:

  | hero | result |
  |---|---|
  | ParrotX2 | 3 of 3, all three on 100/100 lives — above the band the curve targets |
  | Wemmbu | 3 of 3, wins on 51/21/48 lives — in the band |
  | SpokeIsHere | 2 of 3, wins on 27 and 55 lives — in the band |
  | FlameFrags | 0 of 3, dead at waves 19/19/19 |

  Three of the four now finish the campaign, against one when this was first measured. Wemmbu's fix
  was scale: his webs already lingered, they were simply too small and too short to matter, and a
  10-unit patch lasting 14 seconds with a 60% vulnerability puts him squarely in SpokeIsHere's band.
  Worth recording that the value shipped here was probed as a deliberately *oversized* bracket to test
  whether the lever worked at all — the measurement then said the oversized setting was the correct
  one, and a dial-back to 9 units and 11 seconds dropped him straight back to 0 of 3.

  The curve itself is not the problem: it fits SpokeIsHere well. ParrotX2 sits above it and Wemmbu
  and FlameFrags below.

  **What each kit is actually worth**, measured by stripping every ability and passive from a hero
  and comparing waves survived on the same seed:

  | hero | no kit | with kit | the kit is worth |
  |---|---|---|---|
  | SpokeIsHere | wave 16 | wave 25, win | **+9 waves** |
  | ParrotX2 | wave 18 | wave 25, win | **+7 waves** |
  | Wemmbu | wave 17 | wave 20 | +3 waves |
  | FlameFrags | wave 19 | wave 21 | +2 waves |

  This overturned the explanation given earlier in this document's history, that the divide is
  board-multiplying versus personal-damage kits. SpokeIsHere has no global tower buff of any kind and
  his kit is worth *more* than ParrotX2's, so that was not the discriminator.

  What the two effective kits share, and the two weak ones entirely lack, is **persistent board
  presence** — things that keep fighting after the button is pressed. ParrotX2 has summons, a wall
  that blocks the lane, and a global buff; SpokeIsHere has six summons, a converted enemy fighting
  for him, and a debuff that rides the enemies. Wemmbu and FlameFrags have kits made only of
  instantaneous damage plus a self-buff: once the ability resolves, nothing of it remains on the
  board.

  Two rounds of buffs test that and support it by failing. Giving both an earlier and wider share of
  their buff measured as noise; so did attaching their multiplier to enemies instead of to nearby
  towers, which the superseded theory predicted would work. Every change is documented and truthful,
  but none of them moved the outcome, because none of them gave those heroes anything that persists.
  Acting on it turned out not to need an invention, because both heroes' descriptions already promise
  something persistent and neither was implementing it:

  - **Wemmbu's Cobweb Trap** "throws cobwebs over a stretch of path", but applied a slow only to
    whoever stood there at the instant of the cast — webs that stopped existing the moment they
    landed. The pool now supports lingering ground hazards (`EnemyManager.add_hazard`) and the webs
    stay for their full duration, catching whatever walks in. It is his best result to date, waves
    22/21/20 against 20/21/21, and still 0 of 3.
  - **FlameFrags' Trained by Theo** "drops a TNT minecart that explodes", but detonated instantly at
    the kill site and dropped nothing. It now leaves a real cart on its fuse. Faithful, and
    **balance-neutral**: 120 damage in a 2.4-unit radius is trivial against wave-19 enemies, so his
    result is unchanged. Persistence alone is not worth anything — the persistent thing has to hit
    hard enough to matter, and his does not.

  **FlameFrags is the one that is left, and scaling is not his answer.** Two things were wrong and
  both are now fixed: his cart was dropping (correct) but his Trained by Theo passive unlocked at
  level 9, which he only reaches around wave 17, so it was live for the last two waves of a campaign
  — which is why buffing the cart repeatedly produced byte-identical runs. It now unlocks at 4. With
  that done the carts are his single largest damage source at **31% of everything his run deals**,
  and he still loses all three seeds at wave 19. Raising the blast further made him *worse*, not
  better.

  The diagnostic says why, and it is the shape of his kit rather than its size: his mean kill depth
  is **0.19 of the path, with 82% of kills in the first two tenths**. He attacks at 6.5 range, the
  shortest of the four, so his damage and the carts those kills drop all land in one spot; anything
  that survives that spot walks the remaining 80% of the path against towers alone. Wemmbu's web, by
  contrast, is a zone that applies to everything passing through it wherever he stands. Giving
  FlameFrags reach — or a contribution that is not anchored to where he personally kills — is a
  design decision about the owner's character, so it is scoped and left rather than guessed at.

  Treat even these as weak evidence. Removing ParrotX2's +57% meta damage bonus moved him from
  48/100/77 lives to 100/100/100 — impossible as a power effect, since his personal damage is 1–3% of
  what his board does, so it is reshuffling. Three seeds cannot separate a real change from that.

  Two rounds of work aimed squarely at this have not closed the gap. An earlier round appeared to put
  ParrotX2 at 4 of 5 on 60–100 lives, which read like progress; that measurement was contaminated by
  the meta-progression bug above and does not stand. What both rounds found is recorded further down,
  because the findings turned out to be worth more than the attempts.

  A control run pins down what that means. ParrotX2 stripped of **every ability and passive** dies on
  wave 19 with 49 leaks — which is where the other three finish *with their full kits*. Their
  complete kits are worth about what having no kit at all is worth.

  The cause is structural rather than numeric. Towers do 85–99% of a board's damage, and ParrotX2 is
  the only hero whose kit multiplies them: Royal Decree buffs every tower's fire rate, and his
  ultimate doubles every tower's damage. The other three are personal-damage heroes, and personal
  damage does not scale with a 17-tower board. Wemmbu was measured contributing 63% of all damage
  done in his run and still losing. Raising their numbers is not obviously the fix — closing the gap
  by damage alone needs something like a fivefold increase — so this needs a design decision about
  their kits, not a tuning pass, and it is not one to make silently on the owner's characters.

  - **Their late passives were unreachable, and now are not.** Heroes top out at level 11, so
    Wemmbu's Totem of Undying (unlock 12), SpokeIsHere's Totem of NULL (13) and FlameFrags' Trained
    by Theo (14) could never fire. All three now unlock at 9. ParrotX2's First 100 Days is
    deliberately left at 15, unreachable: he is the hero who needs no help, and +3 lives a wave is
    not the buff to hand him. That is a balance decision, not an oversight.
  - **Buffing an ability a hero never unlocks does nothing at all.** SpokeIsHere's Purgatory and
    Totem of NULL were both raised substantially and his run came back **byte-identical** — because
    he finishes a losing campaign at level 7 and neither ability had ever unlocked. Losing costs
    kills, kills are XP, and XP is the kit: a hero that is behind is locked out of the tools that
    would catch it up. Enemies that leak now pay their XP too, which breaks that loop in principle,
    though honestly it barely moves it in practice — leaks are about 12% of enemies, so SpokeIsHere
    is still level 7.
  - **FlameFrags is the one that responded**, going from a wave-18 death to a win once Trained by
    Theo became reachable and his ultimate started sharing its buff with nearby towers. He is still
    only 1 of 3.

  ParrotX2's aura passive was measured contributing nothing — removing it changed the result by
  zero — but that measurement is superseded and the reason matters. Its radius is 9 units, and at the
  time the benchmark could not move the hero, so it never covered a tower. Now that the simulation
  repositions him the aura lands, and it is worth a great deal: he went from 95 lives and 16 leaks to
  100 lives and 4. Repositioning helped the one hero who was already winning more than the three who
  were losing, which widened the gap rather than closing it.
- **Only one map and one difficulty are tuned.** The sweeps are Fort Feather at normal. Merchant City
  and the easy/hard multipliers have had no campaign-level tuning at all.
- **The curve is currently below its own target and is deliberately not being refitted.** Fixing hero
  XP (below) made ParrotX2 markedly stronger — he now finishes on 45–95 lives against the 32–54 band
  the curve was fitted to. Refitting upward would mean tuning the map to the one hero who can already
  win it, making it harder still for the three who cannot. That refit is blocked on the parity
  question above.
- **The wave curve does not need refitting, and that is a measured answer rather than a deferral.**
  It produces 27–55 lives for SpokeIsHere, which is the band it targets. Raising it to rein in
  ParrotX2 would push the median hero out of the band and the bottom two further out still. The
  outlier is the hero, not the map.
- **Every balance number this repository published before the isolation fix was measured against a
  contaminated benchmark, and those fits are not trustworthy.** Finishing a run calls `SaveSystem.record_run_result`
  and `save_game()`, so each simulated campaign permanently levelled the hero it played — and
  `Hero.setup` reads that back as `damage *= 1 + 0.03 * (meta_level - 1)`. The save file accumulated
  ParrotX2 at meta level 20 across 123 runs and Wemmbu at 11 across 7, so the hero comparison was
  being made with ParrotX2 carrying **+57% hero damage** and Wemmbu **+30%** — a handicap that grew
  with how many times each hero happened to have been measured, and that drifted between sweeps. It
  is why the same seed reported a wave-22 defeat in one sweep and wave 18 an hour later on identical
  code. `SaveSystem.begin_benchmark()` now isolates the simulation in both directions, and the sim
  prints its meta level so a contaminated run is visible in the output. **The wave curve in
  `tools/tune_waves.py` was fitted before this and has not been refitted since**; on a clean
  benchmark ParrotX2 wins 3 of 3 without dropping below 100 lives, so the curve is now too easy for
  him and the whole fit is owed a redo.
- **Run-to-run variance is wide, and reproducibility took three fixes.** Seeding the RNG was not
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
- **The curve has been refitted twice, both times because a bug was masking the board's real power,**
  and a third refit is now owed. First the spatial grid returned only the first enemy in each cell, so
  splash, auras and targeting were working at a fraction of their configured strength. Then the `wall`
  ability turned out never to have blocked anything. Now hero XP turns out never to have been awarded
  properly. Each fix made the board stronger and put the benchmark back above its target. The honest
  reading is that the numbers in `tools/tune_waves.py` are fitted to whatever the code actually did on
  the day they were fitted, so a fix to a combat system invalidates them and the sweep has to be
  re-run — the file keeps its fits side by side for exactly that reason.
- **Signature (tier 4) upgrade costs were still set by feel**, not fitted.
- **No human has played it at normal speed** with the actual UI, so nothing is known about whether the
  game *feels* good — only about whether it can be won.

**The board was shooting its own property.** Both `Tower` and `Hero` ask for targets with
`ignore_structures: false`, because the builder enemy's cobblestone walls are structures that should
be shot — but ParrotX2's Fort Feather wall and FlameFrags' dropped carts use that same entity and
flag. A 2000 HP friendly wall standing in the lane therefore absorbed the player's own tower fire for
as long as it stood, which is the exact opposite of what placing it is for. Structures now carry
per-slot ownership (`EnemyManager.friendly`, per slot rather than per type, because the builder enemy
and the hero place the same `cobble_wall`) and targeting always skips the player's own. It moved
ParrotX2 from 82 to 100 lives on the seed that had been costing him any, and left the three heroes
who place no structures byte-identical — which is the check that the fix is scoped correctly.

### Systems that shipped inert, and are now live

A recurring failure in this codebase is data that is authored, populated and displayed to the player
while nothing reads it. Each of these was found by checking data fields against the code that
consumes them, not by anything failing:

- **`leak_cap` and `wall`** — the hero ultimate's leak cap had no callers, and walls were spawned but
  never consulted during movement. Both now work.
- **Hero XP.** Every enemy carries an authored `xp` value, running from 1 for a scout to 400 for
  Saparata, and they sum to 5,805 across a Fort Feather campaign against the 5,565 needed to reach
  level 15 — the highest unlock in the game. The code awarded a flat **1** for anything a tower killed
  and a flat **3** for anything the hero killed, so a hero banked roughly 700 XP a run and finished at
  level 5. Everything gated above that never happened. All four ultimates unlock at level 10, which
  means **no ultimate had ever been cast in a real campaign**, and neither had ParrotX2's Royal Army
  (level 8), Wemmbu's Clutch (8), FlameFrags' Prison Break (8) or SpokeIsHere's Purgatory (8). Heroes
  now reach level 11.
- **Per-unit vulnerability.** SpokeIsHere is built around it — Purgatory's "+35% damage taken for 8
  seconds", Totem of NULL's "+25% for 4" — and the enemy pool had no such concept, so both handlers
  applied a slow instead, at strengths that appear nowhere in their data or their descriptions. The
  mechanic now exists (`EnemyManager.apply_vulnerability`) and both abilities use it.
- **The income passive's timer** was a single accumulator reset on a hardcoded 8.0 while payouts fired
  on the passive's own interval — correct only for the one 8.0 in the data, paying every frame below
  it and never above it.
- **`level_scaling`** is the key every hero's data uses; the code read `level_stats`. Both resolved to
  nothing, so all four heroes shared one hardcoded scaling curve and anything written into the field
  would have been ignored.
- **`aura: true` on FlameFrags' ultimate** and **`prefer_boss` on his Duel Challenge** were both
  authored and both unread. The buff is now shared with towers within his attack range (his own stat,
  not a new constant), and the duel picks a boss or mini-boss ahead of a merely high-HP target, which
  is what its description promises. Its ability text has been updated to say the buff is shared.
- **Wemmbu's Gambit did nothing, and has been re-authored.** `mace_height_bonus` multiplies damage by
  `1 + max(0, attacker.y − target.y) × 0.35`. The board was converted to a flat painted plane, and
  measurement confirms every build zone, the hero, the whole path and every enemy sit at exactly
  `y = 0.0` — so the multiplier is 1.0, always, for Wemmbu's level-1 signature passive and for the
  tower that shares the formula. There is no height on this board to key off, so making it work means
  either giving the board real elevation or re-authoring the passive around something else. Both are
  design decisions about the owner's character rather than repairs, so it is reported, not guessed at.
  On the owner's instruction to choose, it was re-authored rather than met with new terrain: the
  passive now winds up, adding +50% to the next blow for every second Wemmbu goes without landing
  one, capped at +150% — the same ceiling the height rule had. It keeps what a mace is for, a heavy
  committed hit that rewards patience, without needing a third dimension the board does not have.
  The real Density rule is still applied whenever a target genuinely is below the attacker, so this
  costs nothing if a map with elevation ever arrives, and the tower sharing the formula is untouched.
  The ability's description says plainly that it is a game mechanic adapted for a flat board.

### Something the benchmark could not do

Hero repositioning existed only as a mouse handler taking a screen position, so the balance simulation
— the only thing that ever measures this game — could not move the hero and never did. That is not a
neutral omission: ParrotX2's kit works board-wide at any range, while Wemmbu and FlameFrags attack at
7.0 and 6.5 and auras reach 9. A stationary benchmark measures the global-effect hero at full strength
and the short-range ones at almost none. `GameController.place_hero_at()` is now callable headlessly
and the simulation stands the hero where its kit is worth the most.

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

- 2508 automated assertions pass with 0 failures (2322 with the resource pack removed).
- A full run builds, places and upgrades towers, spawns and kills enemies, pays out and advances waves
  with no errors logged.
- All five boss phases fire in order; the mini-boss spawns; the blimp flies, drops 10 paratroopers,
  and can be shot down to stop the drops; the boss dies and the stat is recorded.
- 1000 concurrent enemies cost 6 extra nodes and 0.5 ms.
- The Windows exe is a valid x86-64 PE that boots and loads all its data from its embedded PCK.
- Every screen renders correctly, verified by screenshot: menu, hero select, codex, map, live gameplay.
