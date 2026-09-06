# Known Limitations

An honest account of what is missing, unverified, or deliberately deferred. Nothing here is described
as working when it is not.

---

## 1. The character skins are placeholders

**All 38 character skins are procedurally generated.** They are not the real creators' Minecraft
skins, and they are not close approximations — they are colour-coded stand-ins built from a palette
and a few marker features (a crown for Parrot, a hood for Wemmbu, an egg head for Eggchan).

This is deliberate. The brief said not to download third-party assets, and a publicly available skin
is not automatically licensed for redistribution. So the *pipeline* is the deliverable: supply a
licensed PNG and the game uses it immediately.

**To fix:** drop a Minecraft-compatible PNG at `assets/skins/<id>.png` or `user://skins/<id>.png`.
64×64, legacy 64×32 and HD multiples all work; slim arms are auto-detected. The complete list of ids
awaiting a real skin is in [ASSET_LICENSES.md](ASSET_LICENSES.md). No code change is needed.

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

## 5. Balance is untuned

The numbers are set for readability and internal consistency, not by playtesting. Nobody has played a
full 25-wave run at normal speed with a human making decisions.

Known-suspect areas:
- Late-wave difficulty is asserted by the test suite only as a ramp (last third > 2× first third by
  total HP). Whether wave 24 is *beatable* by a reasonable board has not been established.
- Economy towers may be too strong: a defence that opens with Eggchan and Lomedy accumulates a large
  bank by wave 10.
- Signature (tier 4) upgrade costs were set by feel.
- The boss test wins by damaging enemies directly through the harness, which proves the *encounter
  mechanics* work — not that the fight is winnable with a legitimate board.

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
- **No voice acting.** Characters speak through on-screen dialogue only.
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

- 2198 automated assertions pass with 0 failures.
- A full run builds, places and upgrades towers, spawns and kills enemies, pays out and advances waves
  with no errors logged.
- All five boss phases fire in order; the mini-boss spawns; the blimp flies, drops 10 paratroopers,
  and can be shot down to stop the drops; the boss dies and the stat is recorded.
- 1000 concurrent enemies cost 6 extra nodes and 0.5 ms.
- The Windows exe is a valid x86-64 PE that boots and loads all its data from its embedded PCK.
- Every screen renders correctly, verified by screenshot: menu, hero select, codex, map, live gameplay.
