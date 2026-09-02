# QA report

The rule for this document: **a claim without evidence is not a claim.** Every
line below is either backed by a command whose output was read, or explicitly
marked as not run.

**Engine used for every result here:** Godot `4.5.1.stable.official.f62fdbde1`,
Linux x86_64. Automated runs are headless; the screenshot pass in section 6
renders for real under Xvfb with a software rasteriser.

---

## What was actually executed

### 1. Project import

```
godot --headless --path . --import
```

**Result: clean.** No `SCRIPT ERROR`, no `Parse Error`, no `Compile Error`.

### 2. Headless validation and automated tests

```
tools/run_validation.sh <godot>
```

**Result: PASS — 105 checks, 925 assertions, exit code 0, no engine errors.**

The wrapper matters. GDScript cannot hook the engine's error stream, so a
`SCRIPT ERROR` raised *inside* a test is printed by the engine while the suite
still reports PASS. `tools/run_validation.sh` greps the run log for engine-level
errors and fails on them. That gate was verified by removing the fix for defect
17 below and confirming the gate returns exit code 1 — a gate that has never
fired is not a gate.

```
[1/3] Compiling scripts...     70 scripts, 0 failed
[2/3] Loading scenes...        20 scenes,  0 failed
[3/3] UNIT tests...
      PASS  test_join_code            (108 assertions)
      PASS  test_mesh_factory         (157 assertions)
      PASS  test_mission_rules        (41 assertions)
      PASS  test_name_sanitizer       (23 assertions)
      PASS  test_rate_limiter         (13 assertions)
      PASS  test_state_machine        (66 assertions)
      INTEGRATION tests...
      PASS  test_app_shell            (44 assertions)
      PASS  test_combat_and_revive    (62 assertions)
      PASS  test_concurrency          (17 assertions)
      PASS  test_lan_discovery        (23 assertions)
      PASS  test_level_reachability   (54 assertions)
      PASS  test_mission_flow         (60 assertions)
      PASS  test_scene_integrity      (137 assertions)
      PASS  test_sentinel             (28 assertions)
      PASS  test_session_reset        (92 assertions)
 RESULT: PASS   (105 checks passed, 925 assertions)
RESULT: PASS - validation clean, no engine errors
```

What that run genuinely covers:

* Every script compiles **with autoloads live**, and a script that fails to
  parse fails the phase (see BUILD-003 in `docs/KNOWN_LIMITATIONS.md` for why
  the obvious check is not enough).
* Every scene loads **and instantiates**.
* A complete mission — lobby, hub, terminal, descent, temple discovery, three
  crystals, three pedestals, altar, Star Map, Sentinel spawn, extraction,
  victory — driven against a **real ENet host session**, with every action going
  through the same public entry point player input uses.
* Damage, downed, revive (start, progress, cancel-by-distance, completion,
  refusal to revive a standing player, refusal to self-revive), the Star Map
  drop, its recovery, and total-party failure.
* Three full replays with an assertion after each that no mission fact, entity,
  duplicate player or stale registry entry survived.
* Simultaneous requests: three players grabbing one crystal in the same frame,
  two revivers racing on one downed player, and duplicate extraction requests.
* The Sentinel: navigation becoming usable, targeting the Star Map carrier over
  a nearer player, a validated blaster shot registering exactly one hit, the
  ten-hit stagger and its expiry, retargeting when the carrier goes down,
  projectile damage landing exactly once, recovery from being stuck rather than
  freezing, and cleanup on mission end.
* Friendly fire: a teammate standing in the line of a blaster shot takes no
  damage.
* The real application shell (main.tscn + main.gd + UIRoot) driven the way a
  player drives it: boot to the menu, host, reach the lobby, start the mission,
  pause, resume, and return to the lobby - asserting mouse capture at each step.
* Join codes: exhaustive single-character-typo and transposition sweeps,
  confusable-letter folding, and rejection of malformed input.
* LAN discovery over a real socket: announce, discover, reject nine malformed
  packet shapes, discard oversized packets, cap a 64-packet flood at 32
  entries, resist field shifting, and expire a host that stops announcing.
* Navigation-mesh path queries proving every objective is reachable in both
  directions and the playable area is enclosed.

### 3. Multi-process multiplayer check

```
tools/run_multiplayer_check.sh <godot> 7910 3
```

**Result: PASS — 78 assertions across 5 OS processes, exit code 0.**

One host, three clients and one over-capacity client, all separate processes,
over real ENet on loopback. Selected results, quoted from the run:

```
NETCHECK PASS [host]   all 3 clients complete the handshake  <- roster=4
NETCHECK PASS [host]   the readiness barrier releases and the hub mounts on every peer
NETCHECK PASS [host]   a player entity exists for every peer  <- players=4
NETCHECK PASS [host]   joins are refused once the session has started
NETCHECK PASS [host]   the second barrier releases and Nerava mounts on every peer
NETCHECK PASS [host]   clients picked up 3 crystals through host validation  <- carried=3
NETCHECK PASS [host]   no crystal is duplicated or held twice
NETCHECK PASS [host]   exactly the flooding peer was removed from the roster  <- roster 4 -> 3
NETCHECK PASS [host]   a disconnected carrier's crystal returns to the world
NETCHECK PASS [host]   the mission is still alive after a mid-mission disconnect
NETCHECK PASS [client] a client cannot start the expedition through the terminal
NETCHECK PASS [client] an out-of-range pickup is refused by the host
NETCHECK PASS [client] an in-range pickup is authorised and replicates back
NETCHECK PASS [client] a request carrying a forged session epoch is refused
NETCHECK PASS [client] the host corrects an impossible 180m teleport
NETCHECK PASS [client] sustained request flooding gets the peer disconnected
NETCHECK PASS [reject] the extra client was turned away rather than silently dropped
                       <- The session is full (4/4 players).
NETCHECK PASS [host]   the host is announcing itself on the network  <- Probe Session
NETCHECK PASS [client] the host's session was discovered on the network  <- after 0.2s
NETCHECK PASS [client] the discovered session is marked joinable
NETCHECK PASS [client] a join code round-trips through the discovered address
```

This is the only evidence that covers the **client** half of the protocol.

### 4. Windows export

```
godot --headless --path . --export-release "Windows Desktop" build/windows/StarboundStation.exe
```

**Result: exit code 0.** Output verified with `file`:

```
StarboundStation.exe: PE32+ executable (GUI) x86-64 (stripped to external PDB),
                      for MS Windows, 13 sections
StarboundStation.pck: 14M (the generated texture set)
```

Leak check on the shipped pack: no test source, no `NETCHECK`, no
`headless validation`, no `check_denied`, no compiled test bytecode. Only path
strings in engine-generated caches remain (BUILD-001).

### 5. Repository structure

```
tools/check_structure.sh
```

**Result: PASS.** Required directories and files present, engine version pinned
identically in both workflows, no binaries or build output tracked, no
assignment-shaped secrets, `.gitignore` covers generated output, all script and
scene filenames snake_case.

### 6. Rendered interface

```
tools/render_ui.sh <godot>
```

**Result: 6 images written** into `captures/ui/`: main menu, lobby, HUD, pause,
victory and failure. Each screen is mounted on a dark ground so accidental
transparency is obvious rather than invisible, and the HUD is filled with
representative mid-mission state - hurt, carrying a crystal, an objective up, a
teammate down - because the default empty state proves nothing.

This pass is what found defects 42, 43 and 44.

### 7. Rendered sky

```
tools/preview_sky.sh <godot>
```

**Result: 6 images written** into `captures/sky/`. The sky shader is rendered on
its own, aimed at each body in turn, so it can be iterated on without hosting a
session and walking to a viewpoint. This pass is what found that the ring plane
had been built perpendicular to the line of sight - the rings were being viewed
exactly edge-on and rendered as nothing at all.

### 8. Rendered model gallery

```
tools/render_models.sh <godot>
```

**Result: 13 images written** into `captures/models/`. Every model in the game
is instantiated alone on a neutral sweep under three-point lighting and
photographed from a fixed three-quarter angle: the explorer (upright and
downed), the blaster, the Sentinel, the pedestal, the altar, the terminal, the
drop pod, the power crystal, the Star Map, boulders, the five kinds of set
dressing, and the nine `MeshFactory` primitives.

Where possible the gallery instantiates the REAL scene and applies the same
materials the owning script applies at runtime, rather than a hand-written
approximation - otherwise it drifts away from the game and stops being
evidence. This pass is what found defects 32, 34 and 35.

### 9. Rendered screenshots

```
tools/capture_screenshots.sh <godot>
```

**Result: 15 images written.** The real game is hosted, driven into the hub and
then into Nerava, and the host's own camera is moved to fifteen fixed viewpoints
and photographed. Two of them fire the blaster on the captured frame so the
muzzle flash is in shot.

This runs under Xvfb with Mesa's software rasteriser, using
`--rendering-driver opengl3 --rendering-method gl_compatibility`, because this
machine has no GPU and no Vulkan driver. **What that means for the images:**
geometry, layout, materials, colour and light direction are faithful; anything
Forward+ only - SSAO, SSIL, SDFGI - is absent. The shipped game runs Forward+.

The images are not committed (`captures/` is ignored); the command above
reproduces them. This pass is what found defects 27, 29, 30 and 31 - none of
which any headless test could have seen.

### 10. Recorded trailer

```
tools/record_trailer.sh <godot> captures/starbound-station-trailer.mp4
```

**Result: 1200 frames, encoded to a 50-second 1280x720 H.264 file.** A scripted
camera runs fourteen eased shots across both levels; one PNG is saved per video
frame and ffmpeg encodes them.

This is the first artefact in the project that shows the game MOVING. Everything
else here is a still, and a still cannot show a camera arriving somewhere badly -
which is precisely what it turned out to be doing. Watching it back found defects
45 and 46.

One wrinkle is specific to this rig. A frame takes about a second to render on a
software rasteriser, so at wall-clock speed shader `TIME`, the crystal spin and
the Sentinel's rotation would each advance a full second per rendered frame and
the result would strobe. `Engine.time_scale` is pinned to 0.045 and the camera is
driven from an explicit frame counter rather than from delta, so shot timing is
exact and reproducible however slow the renderer is. The Xvfb and
software-rasteriser caveats from section 9 apply unchanged.

A `duration-scale` argument shortens every shot for a rehearsal pass, which is
how both defects below were confirmed fixed without spending another full render
on a guess.

The video is not committed (`captures/` is ignored); the command above
reproduces it.

### 11. Trailer audio and grade

```
tools/finish_trailer.sh captures/starbound-station-trailer.mp4 24
```

**Result: 69.000 s, 1656 frames, 1280x720 H.264 with AAC stereo.** The score and
the voice are synthesised by `tools/audio/`; nothing was downloaded. The voice is
eSpeak NG, pitched down by resampling, band-limited to roughly a radio channel
and given a room to sit in.

**What was verified, and how.** None of this is a claim about whether it SOUNDS
good - that cannot be established from here, and is recorded as an open question
in `docs/KNOWN_LIMITATIONS.md`. What was measured:

| Claim | Method | Result |
|---|---|---|
| Every line is placed where intended | `build_audio.py --report` prints each line's span against the cut | 15 lines, 0 overlapping |
| Lines do not talk over each other | speech-energy end per clip, not buffer end | 0 overlaps (4 in the first schedule) |
| The film has dynamic shape | per-second RMS across the mix | 32.9 dB range; guardian 15 dB above the opening |
| Nothing clips | peak of the mix, then `volumedetect` on the encoded file | peak 0.867 pre-encode; max -1.1 dB in the MP4 |
| Audio actually reached the container | `volumedetect` sample count | 6,625,280 samples = 69.0 s stereo at 48 kHz |
| The cuts to black are black | file size and inspection of a graded frame | ~8 KB vs ~300 KB for a picture frame |
| Cue-to-picture alignment | frame counts per shot vs. line cue times | "the ruins" / "the cave" / "the grove" each land inside their own crystal shot |

---

## What was NOT executed

Stated plainly. None of the following is claimed to work.

| Not run | Why | Tracked as |
|---|---|---|
| The Windows executable was never launched | No Windows machine | VERIFY-001 |
| The game running at a screen, in motion, played | Motion IS now rendered here (section 10), but a scripted camera is not a player: input feel, head bob, aim, weapon timing and the HUD in motion are still unverified. The owner running it for real is what produced defect 24 | VERIFY-002 |
| Anything Forward+ only (SSAO, SSIL, SDFGI) | No GPU and no Vulkan driver here, so captures use the Compatibility renderer | VERIFY-002 |
| Two physical LAN devices | Only loopback available | VERIFY-003 |
| Internet play through a forwarded port | No such network | VERIFY-003 |
| Artificial latency or packet loss | No conditioner available | VERIFY-004 |
| Audio playback | `AudioDirector` disables itself when headless | VERIFY-005 |
| Frame time, memory or draw-call measurement | No display, no target hardware | VERIFY-006 |
| The Windows BUILD workflow on a runner | `build-windows.yml` is `workflow_dispatch` only and has never been triggered. `validate.yml` HAS run: 8 runs, all green, most recently on `949c95f` | — |
| Host-disconnect behaviour observed by a client | Needs two live instances at a screen | NET-017 |

---

## Defects found and fixed during development

Each of these was found by a test or a log, not by reading code hopefully. They
are recorded because they are the reason the test suite looks the way it does.

| # | Defect | How it surfaced | Fix |
|---|---|---|---|
| 1 | `Transform3D.get_euler()` does not exist | Import errors | Use `basis.get_euler()` |
| 2 | `PackedStringArray(...)` is not a constant expression | Parse errors | Array-literal constant syntax |
| 3 | **Every interaction rejected as "unknown object"** | `test_mission_flow` | `_ready()` runs bottom-up, so `bind_level()` was wiping interactables that had already registered. Registry now clears in `unbind_level()` |
| 4 | **The compile phase was blind to broken scripts** | A parse error passed as "0 failed" | `load()` returns a non-null invalid `GDScript`; now checks `can_instantiate()` |
| 5 | RPCs to a departed peer spammed engine errors | `test_combat_and_revive` | `NetworkManager.is_peer_connected()` guard |
| 6 | `on_despawn_receive ... ERR_UNAUTHORIZED` on every transition | Multi-process logs | Despawns now flush before the next scene is announced |
| 7 | **The host could not send corrections to its own players** | Multi-process logs: `RPC ... not allowed ... Mode is 2, authority is <client>` | A player node's authority is the *client*; host-originated RPCs are now `any_peer` + `_from_host()` |
| 8 | A flooding client was kicked once per queued request | `Unable to send packet on channel 0` x94 | Kicking made idempotent |
| 9 | **The 5th player was dropped silently** | The reject probe | The socket closed in the same frame as the rejection RPC; disconnect is now delayed so the message flushes |
| 10 | **The rejection reason was wrong** — a full lobby was reported as "the host has already started" | The reject probe | Capacity and started-ness are now checked in an order that produces an actionable message |
| 11 | **The Grove Crystal was unreachable — the mission was unwinnable** | `test_level_reachability` | The temple back wall spanned the whole grove corridor; a doorway was opened |
| 12 | Navigation readiness check was wrong on a second visit | Reachability paths returned zero points | `map_get_iteration_id > 0` is already true from the previous visit; `NavUtil` now asks the map a real question |
| 13 | A legitimate respawn was flagged as cheating | Review of #12's fix | `host_full_reset()` re-baselines the movement validator |
| 14 | The host never validated fire cadence | Adversarial review | Only a rate limiter existed; an explicit host-side interval check was added |
| 15 | Revive progress cost ~60 reliable packets/second | Adversarial review | Moved onto the player's `StateSync` |
| 16 | Navmesh precision warnings on every load | Import log | Agent dimensions made exact multiples of the voxel size; project defaults matched |
| 17 | **Two revivers on one player crashed the revive tick, silently breaking revives for the rest of the mission** | `test_concurrency` | Completing a revive cancels every *other* revive on that target, so the next iteration of the key snapshot read an erased key and assigned null to a typed `Dictionary`. Guarded with a `has()` check |
| 18 | **The suite reported PASS while the engine was erroring** | Defect 17 sat inside a green run | GDScript cannot see engine errors; `tools/run_validation.sh` now greps the log and fails |
| 19 | A freed `scene_root` would have crashed rather than being detected | Adversarial review | A freed Node in Godot 4 is not `== null`; switched to `is_instance_valid()` |
| 20 | Downed visuals were rebuilt 60x per second per player | Adversarial review | Refresh now runs on state change |
| 21 | **A downed teammate's revive bar hung on screen forever** | `test_combat_and_revive` | Downing a reviver erased the revive entry directly, which removed it from the tick loop - the only thing that would have cleared the target's bar. All cancellation now routes through `host_handle_revive_stop` |
| 22 | A navigation wait could outlive the node that started it | Leak investigation | A Sentinel despawned mid-wait left a coroutine polling for four seconds holding a freed reference; `NavUtil.await_map_usable` now takes an `owner` and abandons the wait |
| 23 | Dead state in `SceneManager` (`_loading` written, never read) | Adversarial review | Removed |
| 24 | **The player could not move, look, shoot or interact after the hub loaded** | Reported by the owner running the real game - the first runtime feedback this project has had | The lobby set the mouse to VISIBLE and nothing captured it again on the scene change; the player treats an uncaptured mouse as "a menu is open". Mouse mode now has exactly one owner, re-evaluated every frame. Pressing Escape twice was the accidental workaround |
| 25 | Tearing down during a scene transition threw on a freed node | The new app-shell test | `_mount` awaited, then called a method on an instance the teardown had freed; guarded with `is_instance_valid` |
| 26 | A freed object cannot even be PASSED to a `Node`-typed parameter | Fixing 25 | The argument type check throws before the body runs, so the guard's parameter is deliberately untyped |
| 27 | **Every hand-built mesh in the game was inside-out, from the first commit** | The first rendered screenshots: rooms were near-black under lamps that should have lit them | Godot's front faces are CLOCKWISE; `MeshFactory` emitted counter-clockwise, so outward faces were culled and the visible surface was the unlit interior of the far side. Confirmed by an A/B against Godot's own `BoxMesh` (identical size, material and lamp; one lit, one black) and by a shader drawing the raw normal. No headless test could see it: collision, navigation, AABBs and silhouettes are identical either way |
| 28 | The winding test could never have failed | Fixing 27 | It compared the stored normal to the shape's centre, which the builder guarantees. It now reads Godot's convention off `BoxMesh` and `PlaneMesh` and checks every generated mesh against it |
| 29 | A muzzle flash shorter than one frame was never drawn | The firing screenshots came out with no flash | `_process` runs before the draw, so a 55 ms timer expires unseen below ~18 fps - the player loses shot feedback exactly when the game is struggling. The flash now guarantees one rendered frame |
| 30 | Hull surfaces at `metallic` 0.45-0.75 rendered near-black | Hub screenshots | A metal surface has no diffuse response - it shows reflected environment, and a sealed room lit by a flat background colour has none. These are painted panels, which are dielectric; values lowered accordingly |
| 31 | Hub ceiling lamps delivered ~6% of their energy to the floor | Arithmetic during the same investigation | Godot's omni falloff divides by `pow(distance, omni_attenuation)`; at 1.4 over 7.4 m that is a rounding error. Softened, and real ceiling fixtures added |
| 32 | **Small shapes silently built EMPTY meshes** | The blaster's coil rings were missing from the model gallery, and probing the node found a zero-size AABB | `_add_polygon` judged degeneracy against a fixed 1e-6, an area in SQUARE METRES: a 2 cm x 1 cm quad is under it, so every quad in a small torus was discarded, `generate_tangents` then failed on the empty surface, and the builder returned an ArrayMesh with no surfaces - which renders as nothing and reports nothing. Two blaster parts and several suit fittings were simply absent. Test is now relative to the polygon's own size, and `_commit` refuses to return an empty surface quietly |
| 33 | The mesh winding test asserted something false for hollow shapes | Adding `tube` and `torus` | "Normals point away from the origin" assumes star-shaped geometry. A bore and a torus's inner surface legitimately face inward; asserting otherwise would force the barrel to be built solid. That half is now opt-out, the winding half still applies to everything |
| 34 | **The power crystal sat buried in its own bedrock** | The model gallery photographed a squat cluster with no visible spike | `_process` assigned an ABSOLUTE `position.y`, throwing away the rest height its scene set. Fixed by naming the rest height and animating relative to it |
| 35 | The power crystal's glow light had no colour | Same gallery shot - the crystal rendered white | The scene set no `light_color`, so a white lamp washed out the crystal it belongs to until the first snapshot refresh. Colour is a function of `crystal_id`, which never changes, so it is now set once at build time |
| 36 | **A brazier on the grove corridor's centre-line stopped clients ever reaching the Grove Crystal** | The multi-process check, which WALKS the authored routes as a player does | Set dressing placed at (0, 0, -34), squarely in the only route to the grove. Moved off the centre-line |
| 37 | **Collision and navigation disagreed about the level** | Investigating 36 | Dressing with collision was parented outside `NavigationRegion3D`, so the navmesh was baked as though the corridors were empty - pathfinding and `test_level_reachability` both believed a blocked route was clear. Dressing now lives inside the region and bakes into the mesh |
| 38 | The reachability test could not have caught 36 | Gate-checking the fix | "A path exists" and "the corridor is clear" are different claims: the grove corridor is 12 m wide, so a navmesh path routed around the obstruction while a player walked into it. A straight-line corridor-clearance check was added, and verified by reintroducing the brazier - it fails and names the prop |
| 39 | `_set_emission` would have wiped every effect shader in the level | Reading the crystal path after adding the shaders | It replaced whatever material it was handed with a `StandardMaterial3D`, so the first snapshot refresh after a crystal was built would have silently reverted it. It now recognises the effect shaders and drives their parameters |
| 40 | The whole station looked wet after the texture pass | Hub screenshots | The metallic values predated the textures, and the roughness map's scratches dip to 0.16. Dielectric values for painted panels, and a 0.22 roughness floor |
| 41 | The detail normal aliased into glitter on every hull surface | Hub screenshots | 2.4 repeats per metre is fine enough to beat against the pixel grid. Softened and pulled in closer to the camera |
| 42 | **The entire interface had never been seen** | Building `tools/render_ui.sh` | The in-game rig binds its own roots and never mounts the UI, so six screens - half of what a player looks at - were running on the raw Godot default theme. Themed, and the menus now show the game's own sky |
| 43 | The crosshair was off-centre | The first HUD screenshot | Ticks were positioned from the control's origin, but the control is a 16 px box whose top-left sits eight pixels up and left of screen centre. Anchored to the parent's centre instead |
| 44 | A tinted `ProgressBar` fill would have tinted every bar in the game | Writing the health colour ramp | The fill stylebox comes from the theme and is shared. Each bar now owns its own |
| 45 | **Both drop-pod shots framed the ship as an unreadable white slab** | Watching the encoded trailer back | The pod stands at (0, 0, 46); both shots that are about it started roughly two metres from its door, including the one the title card sits on. Reframed to fourteen and eighteen metres down the side of the pad, so the ship, the landing pad and its dressing all read |
| 46 | Title cards disappeared over pale geometry | The same pass | White text over a `Color(0, 0, 0, 0.9)` outline renders as a grey halo - a blur rather than a contrasting edge. The outline is now opaque and larger, with a gradient scrim behind the caption band that no shot can defeat |
| 47 | The closing title faded out before the film ended | Extracting the last frames of the encoded file | The last second was gameplay with no title on it - the frame most likely to be used as a thumbnail. The final shot's card now holds |
| 48 | **The shot captioned "FIND THREE POWER CRYSTALS" pointed 180 degrees away from the crystal** | Extracting a frame from a shot that had never been looked at, after two full renders had shipped it | A hand-guessed yaw of 268 faces +X; the Ruins Crystal is at x = -44. Every shot that is ABOUT an object now has its yaw computed from that object's real position via `yaw = atan2(-d.x, -d.z)`, and the convention is documented in the shot list. The ruins and cave crystals are in frame for the first time |
| 49 | Four voice lines talked over each other | `build_audio.py --report` on the first schedule | Cue times were guessed from reading the script. Retimed against the shot boundaries |
| 50 | The overlap check fired on echo tails, not on speech | Gate-checking 49 | Comparing buffer lengths flags every line whose reverb rings into the next, which is what a tail is for; a warning that is usually wrong is a warning nobody reads. It now measures where the words stop |
| 51 | The opening was as loud as the guardian | Per-second RMS of the mix | Three seconds of black at full level wastes the opening and leaves the hit nowhere to go. The music now follows a level curve and opens 15 dB down |

---

## Open defects

**None known.** That is a statement about what has been tested, not a claim of
correctness: everything in the "not executed" table above is untested, and
`docs/KNOWN_LIMITATIONS.md` lists what that leaves unknown.
