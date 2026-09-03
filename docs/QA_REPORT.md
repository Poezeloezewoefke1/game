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

### 12. Automated playtest - the game driven by simulated input

```
tools/run_playtest.sh <godot> cautious
```

This is the only check in the project that asks whether the game can be
PLAYED. Sections 1-3 drive the game through its own API - `request_interact()`,
`host_spawn_*()` - which proves the rules are right and says nothing about
whether a player can reach the thing the rules are about. `tools/playtest.gd`
boots the shipped shell (`main.tscn`, main menu, lobby, `UIRoot`, HUD) and then
moves a player with `Input.action_press()` and `InputEventMouseMotion`: the
same code path a keyboard and mouse drive. Both work headless, which is what
makes this possible at all.

It runs in `validate.yml` alongside the other gates.

What it asserts, in the order a player meets them: the menu accepts a name and
hosts; the lobby starts; the crew deck mounts; every pre-flight station can be
walked to and worked; the launch lever refuses while anyone is standing and
SAYS SO; a seat can be taken and cannot be walked out of; a strapped-in pilot
can launch; the flight lands on the destination; the temple is discovered by
walking into the clearing; sealed crystals refuse until unsealed; each crystal
can be fetched and placed; the Star Map wakes the Warden; the Warden can be
killed by aiming and firing; and the crew can extract.

Every prompt is recorded at the moment it is read, which is what makes a
failure legible - "pressed E and nothing happened" and "the prompt said Hands
full" are different bugs with different fixes.

**Defects 52-59 were all found by this, in a build where 1468 assertions
passed.** One of them, defect 58, made the game impossible to finish.

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
| 52 | **The Host button did nothing on a brand-new install** | The automated playtest, on its first run: it pressed Host and never reached the lobby | `SettingsManager.display_name` defaulted to `""`, the menu prefills the name field from it, and the host path refuses an empty name. The rejection was correct and clearly worded, but the primary action of the primary screen failed on first press. The default is now `"Explorer"` |
| 53 | **The interact ray found nothing when the player stood right up against a console** | The playtest closed to arm's length and still read an empty prompt | Godot's `RayCast3D.hit_from_inside` defaults to `false`, and a player who walks up to a station is standing inside its collision hull, so the 3.2 m ray started inside the shape and reported nothing. Set on `InteractRay`, and asserted by `test_scene_integrity` so a scene edit cannot drop it |
| 54 | **A press of E issued a frame before the ray acquired its target was silently swallowed** | The playtest pressed E while still sliding to a halt, exactly as a player does | The press was consumed on the frame it arrived; if the ray had not yet latched the station, nothing happened and the player had to press again. `Player.resolve_interact()` now holds an unfired press for `GameConfig.INTERACT_GRACE_TIME` (0.18 s) and fires it the moment a target appears, without ever autofiring on a held key. Pinned by `test_interact_press` (16 assertions, including 120 frames of holding) |
| 55 | **Crew-deck furniture sat on the spine, blocking the walk between compartments** | A player-sized capsule swept along the deck by `test_level_reachability` | A ray at chest height passes over a dining table, so the earlier corridor check could not see this: the mess table, engineering spool, med cryo pod, cargo barrels and cargo pallet all stood in the only route fore-and-aft. Moved off the centre-line, and the gate is now a capsule sweep of the whole spine plus every authored route in `ShipRoutes` |
| 56 | Two props narrowed the Nerava approach | The same capsule sweep | A supply pallet and a crate stack were moved clear of the landing-pad corridor |
| 57 | **A ruin pillar stood in the only route back from the coupling socket** | The automated playtest walked the errand and was stopped dead at (12.4, 0, 2.5), pressed against `D21_ruin_pillar` | Same class as defect 36, and the reason the corridor gate had to grow again: the earlier check swept only the corridor's centre-line, and a player returning from an objective cuts the corner rather than walking down the middle. The gate now sweeps three lanes (x = -2.5, 0, +2.5) and fails if ANY of them is blocked; `D20_ruin_pillar`, `D21_ruin_pillar` and `GroveTree1` were moved clear |
| 58 | **The ship could not be launched by playing the game** | The automated playtest's own source: it launched by calling `GameManager.host_begin_launch()` directly, with a comment saying the lever was out of reach from the seat. That is not a note about the harness, it is the bug report | The launch lever refuses while any crew member is standing, and it stood at (6.4, 0, -16.4) - 3.90 m from the nearest chair and 168 degrees round from it, against a 3.2 m interact ray and a 105 degree seated swivel. Measured from all four seats: every one out of reach, so no crew of any size could ever leave. The launch control now sits on the pilot's console 2.4 m dead ahead of `CrewSeat1`, that seat is flagged `is_pilot_seat`, and the other bridge seats tell the host which chair has the control. `test_level_reachability` now asserts the lever is inside both the ray and the swivel limit from the pilot's seat, and the playtest pulls it from the chair instead of reaching past it |
| 59 | **A 5 m rock stood four metres in front of a spawn point, across the line to the objective** | The playtest walked into `CanyonSpire1` on one run and past it on the next | The spawn-exit gate swept straight -Z and the capsule cleared the rock's corner by 0.1 m, so it passed. A player does not leave a landing pad on a laser line: the gate now sweeps spawn -> temple clearing at three lateral offsets 0.9 m apart, and both canyon spires were moved clear |

---

## Defects in the instrument, not the game

The automated playtest is a measuring device, and a measuring device that is
wrong is worse than none - it produces confident false findings. These are the
times it was wrong, recorded for the same reason the game's defects are.

| # | Defect | How it surfaced | Fix |
|---|---|---|---|
| I1 | **"Stuck" was measured over one frame, not the 2.5 s window** | Every leg longer than the stuck window failed, always reporting "moved 0.08 m" - which is 5 m/s x one 16 ms frame | One variable served as both the window's start position and the odometer's previous position, and the odometer reassigned it every frame. Split into `window_start` and `previous`. This one masked the entire surface act: the whole Nerava playthrough was reported blocked while the player was running normally |
| I2 | A driver that died reported a clean run | The first working version passed in 0.1 s | `SceneManager.current_scene` does not exist, so the phase coroutine died on the property access and the run "finished". Every phase now compares the failure count before and after, and a phase that ends without recording a reason is itself a failure |
| I3 | The blocking report could only see thin rays | "moved 0.08 m ... against nothing the rays could find", in front of a player who could not move | Rays thread past anything they happen to miss. The probe now sweeps a player-sized capsule first, then a fan of rays at knee, chest and head height, and finally prints the character controller's own state - velocity, floor and wall contact, health, seat, and every slide collision by name and layer. That last field is what identified I1: `v=5.00 floor=true` is not a stuck player |
| I4 | An absolute `--out` path was silently rewritten | The log everyone was tailing never appeared | `run_playtest.sh` joined the path to the project directory unconditionally, so `/tmp/x.log` became `/home/user/game/tmp/x.log`. Absolute paths are now taken as given |
| I5 | The lane gate first asked the wrong question | It failed on three pieces of deliberate scenery | Relaxed to "at least one lane is clear", which the playtest then proved too weak by walking into one of those pieces (defect 57). Now strict again, with the level fixed to satisfy it - the gate and the level agreeing is the point, and only one of the two was allowed to move |
| I6 | The surface act aimed from wherever walking stopped | "pressing E on the coupling did not pick it up (prompt '')" | `_walk_to` stops within 2.6 m of a waypoint and the interact ray is 3.2 m, so aiming from there missed. The whole surface act now goes through `_approach_and_use`, which closes the gap step by step and, on failure, reports what the ray actually found |
| I7 | **The aim scan walked the camera into the floor** | A seated pilot with the launch console 2.4 m dead ahead, camera pitch pinned at -75 - the clamp - and the diagnostic ray finding the lever perfectly | When the geometric aim found no prompt, the driver micro-scanned pitch offsets of +4, -8, +12, -16, +20 degrees. Those sum to -12 and it never returned to centre, so every failed scan left the camera 12 degrees lower than it started and three attempts in a row hit the clamp. The scan is now absolute about a remembered centre and returns to it, and the failure report says what the aim tried: start pitch, wanted pitch, where it settled, and whether it ever converged |
| I8 | Any prompt counted as being aimed at the target | On a bridge with four chairs in a row the driver stopped 3 m short with the ray on the chair NEXT to the one it wanted, and reported arrival | Both the approach loop and the aim scan tested `prompt != ""`. They now test that the interact ray is latched onto the object being used |
| I9 | Fixing I7 sent the camera to the OTHER clamp | Every station prompt appeared, then the press missed with pitch pinned at +65 and the ray on the ceiling | `Input.parse_input_event` is handled in `_unhandled_input`, which runs on the IDLE frame; reading `rotation.x` back after only a physics frame returns the old pitch, so an open-loop nudge applies its full correction twice. The setter is now closed-loop over both frames, which makes the staleness harmless rather than fatal |

## Open defects

**None known.** That is a statement about what has been tested, not a claim of
correctness: everything in the "not executed" table above is untested, and
`docs/KNOWN_LIMITATIONS.md` lists what that leaves unknown.
