# QA report

The rule for this document: **a claim without evidence is not a claim.** Every
line below is either backed by a command whose output was read, or explicitly
marked as not run.

**Engine used for every result here:** Godot `4.5.1.stable.official.f62fdbde1`,
Linux x86_64. Automated runs are headless; the screenshot pass in section 6
renders for real under Xvfb with a software rasteriser.

---

## Verdict

**All three planets can now be played from the main menu to extraction, and only
one of them could when this pass started.** Nerava 181.5 s, Cinder 195.3 s,
Hallow 199.9 s - one build, one batch, no downs. Cinder and Hallow had never
been completed before: a guard spawned inside a wall, a crystal 0.03 m inside
another wall, and a staircase you could stand beside but not on (defects 80-82).

Earlier in the pass, four defects made even Nerava impossible to finish, and
none was visible to the assertion suite of its day:

* **58** - the launch lever sat 3.9 m behind the nearest flight seat and 168
  degrees round from it, against a 3.2 m interact ray and a 105 degree seated
  swivel. The lever refuses to fire while any crew member is standing. So once
  the crew strapped in, nobody could reach the only control that starts the
  flight, at any crew size. The ship could not leave.
* **60/61** - the Warden was tuned for four players. Solo, four complete runs
  gave one win and three losses, every loss identical: downed in the exposed
  phase with the boss around 275 of 450. The README offers 1-4 players.
* **67** - health was a one-way resource across an entire descent, so a solo
  player who fought a crystal guard on the way arrived at a boss tuned to be
  close-run from full and was downed having played correctly.
* **70** - the Warden's hover height was applied twice, in the spawner and
  again in its height hold, so it flew 3.4 m higher than authored. At its
  enraged stand-off that needs 70 degrees of upward pitch against a 65 degree
  clamp: the boss parks overhead where it cannot be shot. One run sat at the
  clamp for 84 volleys with the boss frozen on 50 health and the player
  untouched. Earlier runs passed only because they killed it before it closed.

A fifth, **71**, was not a blocker but a hole: the enraged Warden's contact
damage - 18 a second for letting it reach you, the phase's whole threat - had
never once fired, because a 3.2 m *three-dimensional* range test can never be
met by an enemy that hovers metres up. Fixing it exposed two more (**72**, the
boss held station inside its own damage radius; **74**, contact damage was the
one thing about it not sized to the crew), and fixing **70** exposed a third
(**73**, at its authored height it could be wedged on a temple pillar and sit
there for the rest of the fight). Each was hiding the next.

All are fixed and all are gated by a test that fails if they come back.

**What is NOT claimed.** Nobody has played it. There is no GPU, no audio device
and no person at a screen here, so every judgement in this document about how
the game FEELS is an inference from timings, distances, prompts and death
counts - clearly separated below, and recorded as VERIFY-002, VERIFY-007 and
VERIFY-008 in `docs/KNOWN_LIMITATIONS.md`. What IS claimed is that the game can
be played from the main menu to extraction using nothing but a keyboard and a
mouse, because that was measured, repeatedly, on the shipped build.

| Gate | Result |
|---|---|
| Repository structure | PASS |
| Import, compile, scene load | PASS, no script errors |
| Automated suite | PASS - 133 checks, 1769 assertions, no engine errors |
| Multi-process multiplayer | PASS - 81 assertions across 5 OS processes |
| Automated playtest, 3 strategies | PASS - 0 failures, 0 deaths |
| Automated playtest, all 3 planets end to end | PASS - Nerava 181.5 s, Cinder 195.3 s, Hallow 199.9 s, 0 downs each |
| Windows executable launches | BLOCKED - no Windows machine (VERIFY-001) |
| Played by a person | NOT DONE (VERIFY-008) |

---

## Completion Checklist

Every feature the brief asked for, and whether it has been *exercised* rather
than merely written. "Measured" means a run or an assertion produced the
evidence; the full case-by-case list is `docs/TEST_CHECKLIST.md`.

| Feature | State | How it is known |
|---|---|---|
| Main menu, host, join by code, LAN browser | Measured | playtest reaches the lobby every run; `test_lan_discovery` exercises the real socket |
| 1-4 player co-op, host-authoritative | Measured | 5-process multiplayer check, 81 assertions |
| Ship interior, crew quarters, seats | Measured | playtest sits, launches |
| Pre-flight tasks gating launch | Measured | the lever refuses while anyone is standing, and says so |
| Flight: launch and landing sequences | Measured | every run flies |
| Three planets with distinct palettes and crystal names | Measured | `test_scene_integrity` per level |
| Temple discovery by walking into the clearing | Measured | `temple_trigger`, all three planets |
| Three crystals, three different locks (coupling, hazard, guard) | Measured | all three exercised on Cinder and Hallow, two on Nerava |
| Crystal guard fight | Measured | 4-16 volleys across the three planets |
| Altar, Star Map, boss trigger | Measured | every run |
| The Warden: four phases, shield nodes, enrage, contact damage | Measured | killed on all three planets |
| Downed / revive | Measured | `test_combat_and_revive`; solo runs cannot be revived by design |
| Extraction at the drop pod | Measured | `mission.complete` on all three planets |
| **The whole campaign, menu to extraction, on every planet** | **Measured** | one batch, one build: 181.5 / 195.3 / 199.9 s, 0 downs |
| Windows export | NOT verified | no Windows machine here (VERIFY-001) |
| Played by a person | NOT done | no GPU, no audio device, nobody at a screen (VERIFY-008) |

---

## Playthrough Logs

The definitive run: one build, one batch, each planet start to finish with
simulated keyboard and mouse only.

| Planet | Result | Duration | Downs | Shots | Walked | Guard fight |
|---|---|---|---|---|---|---|
| Nerava | PASS | 181.5 s | 0 | 69 | 494 m | 16 volleys |
| Cinder | PASS | 195.3 s | 0 | 48 | 659 m | 4 volleys |
| Hallow | PASS | 199.9 s | 0 | 54 | 693 m | 5 volleys |

Read the spread rather than the totals. The guard fight ranges from 4 volleys to
16 across three levels running identical enemy stats, which is what a fight
whose difficulty comes from *where it happens* looks like - the same observation
that produced defects 80 and 82. The distances differ by 40% for the same three
errands, because Cinder and Hallow are the larger, more open maps.

Before this run, Cinder and Hallow had never been completed. What stopped them
was not difficulty: a guard placed inside a wall, a crystal 0.03 m inside a
wall, and a staircase you could stand beside but not on. See defects 80-82.

Earlier runs, including the three-strategy comparison on Nerava and the
timings-per-act breakdown, are in the sections below.

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

**Result: PASS — 133 checks, 1516 assertions, exit code 0, no engine errors.**

The wrapper matters. GDScript cannot hook the engine's error stream, so a
`SCRIPT ERROR` raised *inside* a test is printed by the engine while the suite
still reports PASS. `tools/run_validation.sh` greps the run log for engine-level
errors and fails on them. That gate was verified by removing the fix for defect
17 below and confirming the gate returns exit code 1 — a gate that has never
fired is not a gate.

```
[1/3] Compiling scripts...     84 scripts, 0 failed
[2/3] Loading scenes...        27 scenes,  0 failed
[3/3] UNIT tests...
      PASS  test_interact_press                (16 assertions)
      PASS  test_join_code                     (108 assertions)
      PASS  test_mesh_factory                  (157 assertions)
      PASS  test_mission_rules                 (76 assertions)
      PASS  test_name_sanitizer                (27 assertions)
      PASS  test_rate_limiter                  (13 assertions)
      PASS  test_state_machine                 (80 assertions)
      INTEGRATION tests...
      PASS  test_app_shell                     (44 assertions)
      PASS  test_combat_and_revive             (62 assertions)
      PASS  test_concurrency                   (18 assertions)
      PASS  test_lan_discovery                 (23 assertions)
      PASS  test_level_reachability            (126 assertions)
      PASS  test_mission_flow                  (101 assertions)
      PASS  test_scene_integrity               (542 assertions)
      PASS  test_sentinel                      (28 assertions)
      PASS  test_session_reset                 (95 assertions)
 RESULT: PASS   (133 checks passed, 1516 assertions)
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

### 11b. Multi-process multiplayer check

```
tools/run_multiplayer_check.sh <godot> 7800 3
```

**Result: PASS - 81 assertions across 5 real OS processes**, a host plus three
clients plus a fifth that is correctly refused, over real ENet on loopback.
The refusal names the true cause ("The session is full (4/4 players)") rather
than a generic message, which is defect 10 staying fixed.

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

**Routes come from the level, not from a table.** Every corridor the driver
walked used to be a hand-measured `Vector3` list taken off Nerava, which is the
honest reason no automated run had ever played Cinder or Hallow. It now asks
each level's own `NavigationRegion3D` for the path - the same mesh the Sentinel
navigates by - and takes `--mission=` to plot a course for a later planet the
way a crew who had already flown Nerava would. See I16 and I17: the first
attempt at following those paths walked straight through a temple pillar, which
was the follower thinning corners, not the path being wrong.

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

**Defects 52-60, 67 and 70-71 were all found by this, in builds where every
assertion passed.** Four of them made the game impossible to finish: 58 for
every crew size, 60 for a solo player, 67 for anyone who took damage on the way
to the altar, and 70 for anyone whose Warden reached its enraged phase.

**Results, by strategy.** Three strategies exist so the game is not measured by
one kind of player: `cautious` keeps its distance, `aggressive` sprints
everywhere and stands its ground, `explorer` tours the whole crew deck before
starting work.

| Strategy | Result | Duration | Walked | Downs | Shots | Warden killed at |
|---|---|---|---|---|---|---|
| cautious | **PASS** | 151.2 s | 452 m | 0 | 46 | 146.8 s |
| aggressive | **PASS** | 107.9 s | 469 m | 0 | 46 | 103.3 s |
| explorer | **PASS** | 156.8 s | 519 m | 0 | 44 | 149.2 s |

These are runs against the build carrying the Warden fixes (70-73) and a guard
on Nerava's Ruins Crystal, which is a materially harder game than the one the
earlier table measured: the enraged phase's contact damage now actually fires,
having never once done so.

The spread is the strongest evidence available here that the fight has depth.
`aggressive` finishes forty seconds sooner by sprinting between objectives and
arrives at the altar untouched - and then wins the fight with **one hit point
left**. `cautious` takes the guard fight at 67 hp, is restored to full at the
altar, and finishes with 67. Same route, same boss, two quite different
stories.

Menu, name, host, lobby, crew deck, course, three stations, a refused lever,
the pilot's seat, launch from the chair, flight, landing, the temple, the
coupling errand, three crystals fetched and placed, the Star Map, the Warden
killed at 147.3 s, and extraction - all of it walked, aimed and pressed with
simulated input, with nothing reached through the game's API.

### 13. What the mission actually costs, in seconds

Taken from a complete solo run of the shipped build (`ci-logs/playtest-*.log`),
driven by simulated input. These are the game's timings, not a human's: the
driver walks optimal routes, never stops to look at anything, and reads no
text. A person will be slower everywhere and much slower on a first run.

| Beat | Elapsed | Cost |
|---|---|---|
| Menu, name, host, lobby, deck mounted | 0.7 s | - |
| Course set at the nav console | 2.3 s | 1.6 s |
| Three pre-flight stations worked | 10.7 s | 8.4 s |
| Walk back, lever refuses (nobody seated) | 20.1 s | 9.4 s |
| Seated in the pilot's chair | 21.1 s | 1.0 s |
| Launch pulled from the chair | 22.5 s | 1.4 s |
| Landed on Nerava | 41.1 s | 18.6 s of flight |
| Temple clearing found | 46.6 s | 5.4 s |
| Coupling fetched and fitted | 59.4 s | 12.8 s |
| Ruins Crystal fetched and placed | 83.9 s | 24.5 s |
| Cave Crystal fetched and placed | 102.2 s | 18.3 s |
| Grove Crystal fetched and placed | 122.8 s | 20.6 s |
| Star Map taken, the Warden wakes | 123.7 s | 0.9 s |

Two things this measures that are hard to see any other way. The pre-flight act
is **22 seconds** for one player - dense, not a trudge, and it parallelises
across a crew of four. And the crystal hunt is **64 seconds of the 124**, split
into three structurally identical round trips of roughly 20 s each: walk out,
press E, walk back, press E. That repetition is the weakest shape in the
mission, and it is exactly what the crystal locks exist to break up - but on
Nerava only one of the three is locked, so two of those trips are plain fetches.
See the recommendations.

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

## Bugs & Issues

Everything found, in three groups: defects in the game that were fixed, defects
in the measuring instrument itself, and what is still open. The instrument group
is not padding - it is the larger of the two by count, and on several occasions
an instrument fault was one commit away from being fixed as a game fault.

### Defects found and fixed during development

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
| 60 | **A solo player could not finish the game: the Warden was tuned for four** | The automated playtest reached the boss alone, broke all three shield nodes, took the body from 900 to 525 - and was downed, which with nobody to revive you is the end of the mission | The README offers 1-4 players and the fight assumed 4. Solo you arrive with 100 health, face a three-projectile volley every 2.6 s, and have to land 51 hits through a blaster that overheats after twelve. The Warden is now sized to the crew that woke it (`MissionRules.boss_scale`): health and shield-node health scale down and volleys come further apart for a smaller crew, recorded in the snapshot at spawn so a join or a disconnect cannot resize the boss mid-fight. Nothing is removed - a solo player still has to break all three nodes before the body can be hurt. Pinned by `test_mission_rules`, which asserts the shape (strictly increasing, exactly 1.0 at four, clamped for nonsense inputs) rather than the numbers |
| 61 | **Scaling the Warden's health was not enough: solo, the fight was still a coin flip** | Four complete solo runs of the shipped build across three strategies - one win, three losses, and every loss the same shape: downed in the exposed phase with the boss around 275 of 450, after 23 volleys | Health was not what killed the player. Three projectiles at 33 damage against 100 health, with no healing anywhere in the mission, is a down in three volleys - and one player cannot spread four players' worth of incoming across four bodies. A ~25% win rate on the FIRST planet's climax, with no checkpoint and a two-minute mission to replay, is not a hard fight, it is a wall. A smaller crew now faces a smaller volley (`MissionRules.boss_volley_projectiles`): one projectile solo, two for a pair, the full three from three players up. The spread still forces a decision about which way to move at two, and a full crew faces exactly what it faced before |
| 62 | **Two shots on a crystal guard in the same frame crashed the engine** | Turning on the guard lock for Nerava, which put that code on a path something actually plays. The log said it plainly: `guard on crystal_ruins destroyed` twice, then `handle_crash: Program crashed with signal 11` | `queue_free()` is deferred to the end of the frame, so between the killing shot and the node going away the guard still exists, still answers calls, and its hit counter happily goes past the threshold again. `GameManager.host_apply_guard_killed` was already idempotent; the NODE was not. In a four-player game this is simply two people firing at the same guard. The death now latches a flag before it does anything else, and a dying node refuses hits |
| 63 | A crystal guard held the temple Sentinel's spawn slot | Same run: `A Sentinel is already present; refusing duplicate spawn`, followed by a test shooting the wrong guardian | `host_spawn_guardian` refused to spawn if ANY non-boss guardian existed, so the moment a mission put a guard on a crystal that guard blocked the temple's own Sentinel. The comment beside the check already said the two were meant to coexist - the check just asked the wrong question. It now ignores guards that belong to a crystal |
| 64 | An assertion labelled "taking the Star Map spawns the Sentinel" was counting the Warden | Separating guard roles in the test harness | `guardian_count()` lumped every guardian together - temple Sentinel, crystal guard and boss - so the one it found was the Warden and the assertion passed while saying something untrue. It now counts the three roles separately, and the assertion says what actually happens |
| 65 | **The extraction race was passing only because the crystal race was failing** | Giving Nerava a guard made the crystal race start succeeding, and the extraction race two phases later began to fail | The races run in sequence against one live session. The crystal race leaves somebody holding a crystal, and full hands cannot take the Star Map - so the extraction phase depended on nobody ever winning the contested crystal, which was true only because that crystal was locked. A test that is green for a reason unrelated to its subject is not evidence. Both later phases now reset hands explicitly |
| 66 | The revive race ran four metres from where a guard now spawns | The revive never completed and the extraction two phases later failed with it | `test_concurrency` stands two revivers at (-42, 0, 1) to bring up a third, and Nerava's ruins guard spawns at (-44, 0, 5). A Sentinel opening fire on the participants is exactly right for the game and fatal for a test about two things happening in the same frame - the target kept being shot back down. The races clear the field first, and say why |
| 67 | **Health was a one-way resource across the whole mission** | Adding the guard to Nerava exposed it immediately: a solo run fought the guard, arrived at the Warden below full, and was downed having played correctly | Nothing anywhere in a descent restored health, so every point lost fetching crystals was a point missing at a boss that is tuned to be close-run from full. That is a difficulty curve decided by attrition rather than by play, and it gets worse with every hazard or guard added in front of it. The altar now restores the crew when it activates - the one moment that unambiguously means "the work is done, the fight is next", earned by placing three crystals, and costing nothing if you took no damage. A DOWNED player is deliberately excluded; being brought round is what reviving is for |
| 68 | **Cinder's and Hallow's altar and drop pod carried Nerava's object ids** | Found by reading the scenes while making the playtest able to fly them: neither level overrode `object_id` on `StarMapAltar` or `DropPod`, so both shipped a `nerava_star_map_altar` and a `nerava_drop_pod` | It never collided, because two levels are never mounted at once and the id is only a lookup key - which is exactly why it survived. But every caller that builds an id as `"%s_star_map_altar" % mission_id` looked for something that did not exist on two of the three planets, and the automated playtest was one of them. Fixed in both scenes; `test_scene_integrity` now requires every interactable id to begin with its own level key, so uniqueness within a level is no longer enough to pass |
| 69 | The pre-flight checklist said what to do and never where | The HUD reads "Next: Prime the reactor (3 left)" on a 41 m deck divided by four bulkheads | The four stations are spread bow to stern and the only way to find them was to walk the whole ship once. `SHIP_TASK_LOCATIONS` now pairs each label with its place - "Prime the reactor - engineering, by the spine" - through one `ship_task_hint()` that the HUD and the launch lever both use, so a station added without a location cannot silently render as a label with a dangling dash |
| 70 | **The Warden hovered 3.4 m higher than authored, which made the enraged phase a stalemate** | A run sat at the +65 degree pitch clamp for 84 volleys with the boss frozen on 50 of 450 health and the player untouched. Measured from the log the instrument was made to print: `me (6.0, 0.0, 1.6) boss (-1.8, 9.8, -6.2)` - the Warden at y=9.8 where the anchor plus its hover height is 6.4 | `SpawnManager.host_spawn_warden` adds `BOSS_HOVER_HEIGHT` to the anchor so the Warden appears at its hover height instead of dropping in; `Warden._host_think` then held `spawn_position.y + BOSS_HOVER_HEIGHT`, adding the same offset a second time. Two places each taking responsibility for one offset. Not cosmetic: the enraged Warden closes to a 3 m ring, and from 9.8 m up that needs 70 degrees of upward pitch against a 65 degree clamp - the boss parks overhead where it cannot be shot. Three earlier runs passed only because they killed it before it ever closed |
| 71 | **The enraged Warden's contact damage had never once fired** | Found while reading the same code: `global_position.distance_to(player) > 3.2` on an enemy that hovers metres up | The vertical gap alone exceeds 3.2 m at any hover height the level authors, so the check could never pass and the enraged phase's signature threat - 18 damage a second for letting it reach you - was dead code. It now measures the HORIZONTAL distance, which is what "it is on top of you" means for something flying, against a named `BOSS_CONTACT_RANGE`. `test_combat_and_revive` asserts both that the Warden holds the height it spawned at and that a player on the ground can look up far enough to aim at it at the closest it ever comes |
| 72 | **The enraged Warden held station INSIDE its own contact radius** | Exposed the moment 71 was fixed: with contact damage live, all three strategies died about four seconds into the enraged phase - the aggressive one from a full 100 hp, having taken no damage anywhere else in the run | The enraged ring was 3.0 m and the contact reach 3.2 m, so the boss parked inside the radius and dealt 18 damage a second for the entire phase unconditionally. That is not a punishment for letting it reach you, it is an aura, and no amount of playing well avoids it. The rings are now named constants (`BOSS_STAND_OFF`, `BOSS_ENRAGED_STAND_OFF`) with the enraged one at 4.5 m, outside the reach: enraging still halves the distance and closes fast, and contact is what happens when it CATCHES you. `test_combat_and_revive` asserts the ordering, so the two numbers cannot drift back past each other |
| 73 | **The Warden could be wedged on a temple pillar, permanently** | Exposed by fixing 70: `480 volleys, phase=3 boss=150, 17.0 m away, pitch 17 (want 17), at (-0.9, 0.0, -22.6) boss at (-11.7, 6.4, -11.1)` - the boss motionless against `TemplePillar1` for four minutes, taking nothing, while the aim was dead on | The temple's pillars are 7 m and its lintels 7.4; the Warden hovers at 6.4, so it flies INSIDE the colonnade, which is the design - it is what makes the arena read as a temple. But it carried a world collision mask, so it drove into a pillar and stopped there. At the old doubled height it flew over everything, which is why this never showed: one bug was hiding the other. A hovering boss has no business being trapped by scenery, so it no longer collides with the world; the height hold keeps it off the floor and its hitboxes are unchanged, so nothing about shooting it changes |
| 74 | **Contact damage was the one thing about the Warden not sized to the crew** | With 71 and 72 fixed, the enraged phase still killed the explorer driver from a full 100 hp in eleven seconds, and the aggressive one survived it with 1 | Its health, its volley interval and the projectiles per volley are all scaled by `MissionRules.boss_scale`; the 18 a second for touching you was a flat constant, so a solo player absorbed the whole of a four-player crew's punishment alone. Exactly the shape of defects 60 and 61, hidden for as long as the check that gates it could never pass. It now scales the same way, through `MissionRules.boss_contact_damage`, with a floor of 1 so it is never free |
| 75 | **Cinder's coupling socket showed a prompt and refused every press, sealing the cave crystal for good** | The first mission ever flown on Cinder: `'Press E to Fit Power Coupling'` on screen, `REJECTED reason=interact_no_line_of_sight` five times, from 2.98 m with the interact ray on the socket | The client's ray and the host's validation ray are different rays. The client's leaves the camera and hits the collision SHAPE; the host's went from the player's chest to the object's ORIGIN plus 0.6 m - for anything standing on the ground, its feet, the most obstructed point on it. A piece of set dressing 0.2 m in front of the socket blocked the second and not the first, so the game advertised an action it would always refuse and the mission became unfinishable. The base class already carried a `needs_line_of_sight` escape hatch whose own comment named the cause - "a strict eye-to-origin ray" - so the symptom had been seen and worked around rather than fixed. The host now aims at `Interactable.interaction_point()`, the same collision-shape centre the client's ray hits, which makes them agree by construction on every level and every prop instead of one opt-out at a time. The obstruction itself was `D03_ruin_pillar`, **1.0 m** from the socket - defect 57 again, a different planet and a line of sight rather than a walk. Hallow was built from the same template and had the identical pillar in the identical place, so it was unfinishable too and nobody had ever got far enough to find out |
| 76 | **On Cinder and Hallow the temple was discovered before the player had taken a step** | `State -> FIND_TEMPLE` followed immediately by `State -> FIND_CRYSTALS`, logged between the level mounting and the player being placed - the objective on landing read "Find 3 Power Crystals" instead of "Locate the Temple" | The discovery volume is a box on `LAYER_PLAYER`. Nerava's is a 30x8x6 band across the approach; Cinder's and Hallow's are 30x6x**30**, which reaches back to the world origin - and a player entity exists at the origin for a frame before the spawner places it. So the beat that gives the descent its opening was skipped on two of the three planets, by nothing the player did. The physics server evaluates overlaps against the transform a body had when it was REGISTERED, so a freshly spawned player is matched at the origin. Filtering the bad signal does not work, and that is the instructive part: reject it and the REAL entry never arrives either, because as far as the server is concerned the body never left, so there is no second crossing to report - a fix that looked right and silently removed the beat from all three planets instead of two. The trigger now asks the geometry itself once per physics frame until it fires, which is immune to both halves, and logs who reached the clearing and where, so a state change can never again arrive with no cause attached |
| 77 | **The player could not step onto a 0.3 m ledge, so Cinder's and Hallow's ruins crystal was unreachable** | Stuck dead against `RuinsFloor` 0.9 m from the crystal, `v=0.00`, with a near-vertical wall normal - on the first mission ever flown there | `move_and_slide()` has no step handling: a CharacterBody3D walks up SLOPES and stops against any vertical face, however small. The levels are authored against the navigation bake's `agent_max_climb` of 0.4 m, so navigation routes players over lips the physics then refuses - two systems answering "can you get there" differently, which is defect 75's shape again in a different subsystem. The player now steps up to what the bake already promises: only while grounded, only when actually pressed against something, and only where there is ground to land on, so a cliff edge is still a cliff edge |
| 78 | **Cinder's and Hallow's entire temple was unreachable on foot** | Carrying the first crystal home, the driver stopped at the plateau wall 12.8 m from the pedestal and never got a prompt | The pedestals, the altar and the Star Map all sit on a plateau whose top is 1.4 m above the basin. The four blocks named `PlateauRamp1..4` are not ramps - they are boxes topping out at 1.05 m, so reaching one is a 1.05 m step from the ground. Nothing can climb that: not the player, and not the navigation bake, which is why `map_get_path` had been quietly returning routes that stop at the plateau edge rather than admitting there is none. So on two of the three planets the crystals could be fetched and then never placed - the mission was impossible, not merely hard. Each approach now rises in four 0.35 m steps, inside both the player's step height and the bake's `agent_max_climb` |
| 79 | **The crystal guard was wedged among the ruin pillars, so it could not be shot** | `Stuck for 6.0s - returning to anchor` eighteen times in one Hallow run, while the driver fired 60 volleys and landed nothing; on Cinder, 2 hits in 60 | Defect 73 in a second body. The Sentinel HOVERS - `_host_move` holds it a constant height above whatever is below - and it still carried a world collision mask, so the ruin pillars around the ruins crystal trapped it and the player's shots hit the pillar it was behind. Its own stuck-recovery is for losing a path, not for being wedged by masonry it should be floating over, and firing it eighteen times is the log saying so. Nothing depends on it colliding: the height hold keeps it off the ground and its hurtbox is unchanged. Nerava's guard escaped only because it stands on open ground |
| 80 | **Every crystal guard was placed by a constant that pointed at a wall - on all three planets** | Arithmetic on the level files, then confirmed by the physics server in `test_scene_integrity`: the post is 0.447 m INSIDE `RuinsBack` on Cinder and on Hallow, and 1.0 m in front of `RuinsWallSouth`, which is 10 m tall, on Nerava | Guards were spawned at `crystal + Vector3(0, 0, 5)` - the same offset in the same direction on every level, without anything ever asking what was five metres north of that particular crystal. The answer was "a wall" every time; the levels differed only in how far into it. Nerava was survivable, which is why the constant lasted, and it is the reason a fix here had to be checked against the planet that WORKED as carefully as against the two that did not. What the placement cost is worth stating carefully, because the obvious story is not the one the evidence supports: the 60-volley runs that found these guards unhittable failed for a different reason entirely (I34 - the driver was stuck against a mesa 25 m away), so this has never been observed to make a mission unwinnable. What it demonstrably did was wedge the guard - defect 79 recorded a Hallow guard logging `Stuck for 6.0s - returning to anchor` eighteen times in one run, and the anchor it kept returning to was this point, inside the wall. `SpawnManager.guard_post` now tries twelve posts around the crystal and takes the first that is clear, starting due north so nothing moves that does not have to. All three planets move: Cinder and Hallow 60 degrees to (-22.1, 0.3, 40.2), Nerava 30 degrees to (-41.5, 0.0, 4.3). `test_scene_integrity` asks the PHYSICS SERVER whether the chosen post is solid and whether the crystal is visible from it, deliberately not reusing the box arithmetic that picks it: a check that agrees with its own reasoning is exactly what the broken version was  **Amended:** the first version of this fix took the first post that was merely CLEAR, and moved Nerava's guard - which dies in seven volleys - 30 degrees onto a spot behind `RuinColumn2`, where sixteen volleys in ninety seconds landed nothing. Two planets fixed by breaking the third, pushed before it was caught, and no gate said a word. Clear is not the property that matters: shootable is. Posts are now scored by how many of twelve approaches have a clear line to a guard standing there, ties keeping the lowest index so due north still wins when nothing is wrong, and `test_scene_integrity` asserts the same property from the physics side  **Amended twice.** The replacement scored posts by how many of twelve stances on a 12 m ring could see them - which works in an open basin and not in Nerava's ruins, a corridor 12 m wide where ten of the twelve samples land inside the walls. Every post there scored one or two, the score could not tell a good one from a bad one, and it picked the post with `RuinColumn2` directly between the guard and the only approach: `the shot stops on RuinColumn2 at 11.7 m, 5.3 m short of the guard`. Sightlines are now traced OUTWARD from the guard - along each bearing, how far can a shot run before it meets scenery - which asks the question that actually matters and is not defeated by the size of the room. Nerava's best post went from 2 of 12 to 5 of 12 and the planet flies end to end again |
| 81 | **Cinder's and Hallow's third crystal was inside a wall, so neither planet could be finished** | Reached for the first time once the guard fight worked: `press.blocked  the crystal_grove: the host's line of sight (43.8, 1.5, -2.7) -> (45.8, 0.9, -4.0) is blocked by GroveBack at (45.8, 0.9, -4.0)` - the ray ends on the wall AT the point it was aiming for | `CrystalGrove` sits at x 45.825 and `GroveBack` starts at x 45.795: the crystal is 0.03 m inside it, so the host's line of sight to the interaction point is blocked from every direction and the prompt can never be honoured. All three enclosures are built from one template - a 16 x 8 x 4 back wall, two shoulders, an 18 x 0.3 x 14 floor with the crystal at its centre - and in the other two the back wall lies along the floor edge it is offset toward. The grove's was moved to the east side and never ROTATED, so its 16 m length still ran east-west and its face landed on the crystal. Rotating it 90 degrees puts the crystal 5.97 m clear, in line with the ruins at 4.55 m and the cave at 4.93 m. Defect 75's shape for the fourth time - geometry against an objective - but the first one where the objective was inside the geometry rather than behind it |
| 82 | **The staircase built to fix defect 78 had no width margin, so stepping 0.22 m off it was a wall** | Reached for the first time once the guard and the grove crystal were fixed: `stuck  carry crystal_ruins home (13/21): moved 0.22 m in 2.5s at (-4.72, 0.28, 25.83) ... touching PlateauStepMidS`, at 1 hp, with the crystal in hand | The four plateau approaches rise 0 -> 0.35 -> 0.70 -> 1.05 -> 1.40, every tier within the bake's 0.40 m `agent_max_climb`. The heights were right and the WIDTHS were not: all of them 9 m, exactly as wide as the ramp above. The navigation bake shrinks a 9 m tier by the 0.6 m agent radius to 7.8 m of walkable surface, so a route can pass within 0.1 m of the edge - and a player who drifts off the side of a step is not one step down, they are on the basin facing the step's 0.70 m SIDE, which nothing can climb. Defect 78 in the other axis: I fixed the profile someone climbs and left the profile they fall off. The tiers now taper 13 / 11 / 9, so drifting sideways always lands one tier down, and `test_scene_integrity` asserts both the rise and the overhang against the level's OWN `agent_max_climb` rather than a copy of it - a copied number is what let the geometry and the navigation disagree in the first place |

---

### Defects in the instrument, not the game

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
| I10 | **The driver's model of mouse sensitivity was wrong by a factor of twenty** | The root cause under I7 and I9. A probe that sent a known nudge to the real player and measured the result: 2 px moved the camera 5.04 degrees, 5 px moved it 12.61, 20 px moved it 50.42 - dead linear at 2.52 deg/px, against the 0.126 deg/px the sensitivity constant implies | Every correction was computed as `-error / MOUSE_SENSITIVITY` and then applied twenty times too hard, so the closed loop had a gain of 20 and oscillated into whichever clamp it was heading for. The header had always claimed the steering was closed-loop so that a sensitivity change could not invalidate it; the STEP SIZE was still computed from the constant, which is the half of it that was open loop. The driver now measures radians-per-pixel against the live player at the start of a run and uses that, and takes 60% of each correction so a measurement error cannot turn the loop into an oscillator |
| I11 | The boss fight aimed with yaw only | The Warden woke, the driver fired for a minute, and its health never moved off 900 | The Warden hovers 6.4 m above the temple floor and the fight steered with `_look_at_point`, which turns the body and not the head, so every shot went under it. A fight the driver cannot win is indistinguishable from a boss that cannot be killed. The fight now aims in three dimensions, and reports its own progress every twelve volleys - phase, health, nodes left, range and pitch - so a stall says why before the deadline rather than after it |
| I12 | The driver stood still in a fight built around moving | It went down in every boss run, and the fight looked unwinnable solo | The Warden throws three projectiles doing 33 damage each at a player with 100 health, and they take the best part of a second to cross the gap: strafing out of the way is the fight. The driver fired from a standstill, ate the third volley every time, and made a demanding fight look impossible. It now weaves, flipping direction each volley. Anything read off a driver that does not play the way a fight is designed to be played is a measurement of the driver, not of the game - and tuning the game against it would have made the game worse for real players |
| I13 | The driver would not run from a boss designed to be run from | It reached the enraged phase with the Warden at 150 of 450 and was still run down and killed, which reads as "the boss is too strong" | An enraged Warden moves at 6.4 m/s and does 18 contact damage a second. A walking player does 5.0 and cannot escape; a SPRINTING player does 8.5 and can. The enrage is precisely what turns the fight from a shooting gallery into a retreat, and the driver never touched sprint. Two rounds of boss tuning were nearly spent on a driver that would not run away - which is the argument for fixing the instrument before believing anything it says about balance |
| I14 | Carrying a crystal home cut the corner the corridor exists to avoid | Stopped dead at (29.2, 0, 2.1) against `CaveStalagmite`, carrying the Cave Crystal | The route OUT dog-legs through (14, 0, 0) precisely to miss that rock; the route home was a straight line to (0, 0, 4) and walked into it. The corridor was never blocked - the shortcut was. The carry-home legs are now the outbound route reversed, which is also what a player who just walked it does |
| I15 | A test asserted the outcome it needed instead of the change it was measuring | `star map drop` reported three failures the moment a new test ran ahead of it: the map stayed carried when its carrier was downed | The drop fires on the DOWNED transition, and the test proved it by damaging the carrier and checking `is_downed`. A player who was already down satisfies that check without any transition happening at all - so the assertion passed while the thing it names never occurred. It only became visible because the altar-restore test left the second player down; for as long as the order happened to suit it, the test was green on a state it never created. It now asserts the carrier is STANDING first, and the altar test stands them back up rather than leaving the world changed for whoever runs next |
| I16 | The driver's routes were Nerava's, hand-measured, so nothing had ever played the other two planets | Every corridor, errand and run-for-the-pod leg was a literal `Vector3` table written off one level | The tables encoded real knowledge - the dog-leg at (14, 0, 0) exists because a straight line walks into a stalagmite - but it was knowledge about ONE world, and it silently limited every automated playthrough to the only planet a fresh save unlocks. The driver now asks the level's own navigation mesh for each route, which is more general than a table and closer to what a player does, and takes `--mission=` so it can plot a course for Cinder or Hallow the way a crew who had flown Nerava would |
| I17 | Following a navigation path by thinning its corners walked straight through a pillar | `stuck: to the socket (5/8) ... against TemplePillar4` with a perfectly good path in hand | Two mistakes with one cause - treating a navmesh corner as a waypoint rather than as a turn. The follower dropped any corner within 2.6 m of the next, and then arrived at the ones it kept from 2.6 m away before heading for the one after. A corner is a corner PRECISELY because the straight line past it is not walkable, so both shortcuts cut the exact geometry the turn exists to avoid. Corners are now kept unless they repeat, and intermediate ones are rounded to 0.9 m; only the final leg, which ends in front of an object rather than at a corner, keeps the loose radius |
| I18 | The fight could not say why it was losing | 84 volleys against a boss whose health never moved, and a log line that said only "12.1 m away, pitch 65" | Range and pitch alone cannot distinguish "the shots are missing" from "the shots are not being fired" from "the boss cannot be aimed at from here", and the run before this one was all three at once. `_aim_at_point` now REPORTS whether it converged, the fight logs the pitch it wanted beside the pitch it has and both positions, and a volley whose aim did not converge is not fired at all - it moves for an angle instead, which is what a player does when they cannot see what is shooting at them. The very next run printed `boss (-1.8, 9.8, -6.2)` and defect 70 was a two-line read |
| I19 | The driver never sprinted away from the enraged Warden, because it held sprint in a direction the game does not sprint in | It was run down in the enraged phase every time, and the fight read as too hard | `player.gd` gates sprint on moving FORWARD (`input.y < 0.0`). The driver held `sprint` together with `move_back`, so it walked backwards at 5.0 m/s away from something that closes at 6.4 and could never open a gap - the enraged phase always ended in contact range no matter how the boss was tuned. This is I13 in a second costume: the code comment already said a sprinting player escapes and a walking one does not, and the driver believed it while doing the opposite. It now turns round and runs, which is what the enrage is FOR |
| I20 | The driver crashed instead of reporting a mission it had just lost | `SCRIPT ERROR: Trying to cast a freed object` at `_fight_the_warden`, reported as "aborted without recording a reason" | The crew was wiped out during an 0.8 s retreat; the failure freed every session-bound node, and a freed Node in Godot 4 is not null - it is an object that crashes on the cast. The loop re-checks `is_instance_valid` after the await and tests for MISSION_FAILED before firing, so a lost fight now reads as "the crew was wiped out by the Warden", which is a result rather than an incident |
| I21 | "Break away" was a 1.1 s dash | The driver reached the enraged phase with the Warden on 25 of 450 and was still caught and downed | A sprinting player gains 2.1 m/s on an enraged Warden, so 1.1 s of running buys 2.3 m and the boss is back inside contact range before the next volley leaves the barrel. Breaking away has to mean breaking away: the retreat now runs until the gap is genuinely open (14 m, beyond the boss's own stand-off ring) or four seconds have passed, re-facing away each step as the boss moves. The same discipline as I12, I13 and I19 - measure the game with a driver that plays it the way it is designed to be played, or measure the driver |
| I22 | The driver fired three-shot bursts from a weapon that allows seven | With the retreat fixed it survived the enraged phase three times longer and took the boss from 150 to 75 instead of to 25 - it lived longer and did LESS damage | A fixed 0.55 s on the trigger is three shots. The blaster holds 100 heat, spends 14 a shot and cools at 26 a second, so after a four-second retreat it is stone cold and good for seven. The fixed burst threw away more than half the damage of every window the retreat had just bought, which turns a fight built on kiting into a war of attrition the player loses. The burst is now sized from the heat the weapon actually has left |
| I23 | Two playtests at once, and the loser blamed the game | `hosting did not reach the lobby` on three consecutive runs, from `ERROR: Couldn't create an ENet host` | A second batch was started while the first was still going; both bound the same ENet port and the loser reported a clean-looking game failure fifteen seconds in. `run_playtest.sh` now waits for any other playtest to finish and refuses rather than starting a second, so a scheduling mistake cannot come back as a bug report about the lobby |
| I24 | "Keep moving while firing" flipped direction every volley, which is not moving | Measured from the driver's own position: 0.6 m covered in four seconds of standing fire, eating every projectile | Alternating left and right each volley oscillates in place. The Warden's shots take about a second to cross 12 m and a player moving sideways at 5 m/s is five metres clear by the time they land - dodging is the whole reason the fight tells you to move. The driver now holds a direction for three volleys before reversing. I12 fixed the driver standing still; this is the same mistake wearing the fix as a disguise |
| I25 | Aimed shots that did nothing were fired 480 times without comment | `480 volleys, phase=3 boss=150, pitch 17 (want 17)` - the aim dead on and the boss untouched for four minutes | The aim converging says the camera is pointed at the boss, not that anything can travel between them; a pillar in the line is invisible to it. The fight now watches the boss's health, and ten aimed volleys that change nothing make it move for a line instead of emptying the blaster into masonry. This is what turned defect 73 from "the deadline ran out" into a position and a cause |
| I26 | The retreat ran dead away from something that shoots | Downed from a full 100 hp in eleven seconds, 24 m clear of the temple, while sprinting | Running in a straight line directly away is the easiest target there is: no lateral motion means no dodge, so every projectile lands. The retreat now serpentines, angling 35 degrees either side of dead-away and alternating each step, which opens the same distance while still crossing the shot's path. Fourth time this harness has measured itself instead of the game by not moving the way the fight is built around (I12, I19, I21, I24) |
| I27 | A refused press said only that it was refused | Five presses at Cinder's coupling socket with the prompt on screen, and a failure line that could name the ray but not the reason | The host's rejection reason reaches the log but not the driver, and `interact_no_line_of_sight` still does not say WHAT is in the way. The driver now runs the host's own query on failure and names the obstruction and where it was hit - which is how a mystery on Cinder became `blocked by @StaticBody3D@864 at (-19.8, 0.7, -34.5)`, and from there a named prop one metre from the socket. Same lesson as `_what_is_blocking` for a stuck leg: "it failed" is a bug report, "X is at Y" is a bug fix |
| I28 | The driver walked thirty metres into a Sentinel's fire without shooting back | Downed on Cinder having fired ZERO shots, and reported the crystal unreachable | It fought the guard only AFTER arriving at the crystal, so the approach was taken under fire with the trigger untouched. On Nerava that survived because the walk starts from full health; on Cinder the hazard errand costs a third of it first. Walking toward something that is shooting you, without shooting back, is not caution - it is standing still with extra steps, and it is the fifth time this harness has measured itself by not playing the way the game is built to be played. It now engages first |
| I29 | The guard fight could not tell "aimed and blocked" from "losing" | 60 volleys with the guard on 0 hits, reported as "still standing after 90 s" | The Warden fight learned this (I25) and the guard fight had not: the crystal lock is binary, so the only progress signal is the guard's own hit count. Watching it turns a timeout into `8 volleys with crystal_ruins still on 0 hits - moving for a line`, which is what pointed at the guard being wedged rather than the fight being too hard |
| I30 | A test measured elapsed time by adding up frame deltas | `test_lan_discovery :: expiry` failed three times in one session, always while other work was running, always passing on the immediate re-run | Godot CLAMPS the delta it reports when a frame runs long, so a sum of deltas drifts behind the wall clock under load - and the assertion is about the wall clock: "it stays listed for roughly the configured timeout". Each failure cost the trouble of proving it had nothing to do with the change in hand, twice for player movement and once for level geometry, neither of which can reach a UDP socket. It reads `Time.get_ticks_msec()` now. Tolerating it as a known flake was the wrong call and is withdrawn: a test that measures the wrong thing spends attention and returns noise  **Amended:** it failed again after that fix, in the opposite direction - the entry dropped out EARLY. The clamped delta was real and was one of two causes. The other is that an entry ages from its last PACKET, not from the moment the host stopped announcing, so a stop landing just before the next announcement leaves the entry already a full interval old. The lower bound was a hard-coded 1.0 s, which is exactly the announce interval: zero margin, guaranteed to fire eventually. It is derived from the two constants now, with slack, and says the numbers it used when it fails. Recording this because the first entry read as though the matter were closed, and a fix that removes one of two causes and then reports the flake solved is worse than one that says which half it addressed |
| I31 | The "one playtest at a time" guard deadlocked against itself | Three runs refused with "another playtest is already running" when nothing was | `pgrep -f playtest.tscn` matches any process whose command line mentions that string - including the shell asking the question. The guard added to stop two runs fighting over the ENet port (I23) became a second way to lose a run to a scheduling detail. It matches the ENGINE now, `Godot_v.*playtest\.tscn`, which is the thing that actually holds the port |
| I32 | **The driver aborted on the shot that WON the fight** | `SCRIPT ERROR: Trying to cast a freed object` at `_fight_the_warden`, surfacing as "the playtest driver aborted during 'play the surface' without recording a reason" - on a Nerava run that had just killed the Warden | The Warden fight logs progress every twelfth volley, and a dead Warden is freed on the frame it dies. When the killing shot happened to be a twelfth one, the progress log cast a freed node and took the run down with it. Flaky by construction - one run in twelve - with the worst possible failure mode: a nameless abort reported on a mission the player actually completed, sending the reader after a game bug that was never there. The log checks `is_instance_valid` first now |
| I33 | **The baseline shot reading was taken from beyond the blaster's range** | `guard.sight  the shot hits NOTHING in 60 m (guard 69.5 m away, aim off by 2.0 deg)` - on Nerava, where the guard dies in seven volleys | Added to give every guard fight a verified baseline, then placed on the FIRST aim, which happens before the driver has closed. At 69.5 m - past the blaster's 60 m range - it correctly reported that nothing was hit by a shot nobody was taking. A measurement taken at a moment the thing never happens measures nothing. It is now taken once the driver is inside the range it fires from |
| I34 | **The guard approach was the one leg that ignored the navmesh** | `the shot stops on NavigationRegion3D/Mesa4 (SCENERY) at 0.1 m, 24.5 m short of the guard, which is 24.6 m away; aim off by 1.7 deg` - repeated for sixty volleys, on Cinder and on Hallow | Every other leg of a run routes with `map_get_path`; this one held `move_forward` toward the guard, which works only if the ground between is empty. On both planets the approach from the south runs into `Mesa4`, a 12 x 4.5 x 9 block, so the driver stood with its face a tenth of a metre from a mesa, aimed to within two degrees of a guard 25 m away on the far side of it, and emptied the blaster into rock. It reported the guard unkillable - on two planets, across several rounds of investigation, one of which charged it to the game and wrote a level-layout diagnosis into this document. Sixth time the harness has measured itself, second time it was nearly believed. It routes on the navmesh now |
| I35 | **The guard fight had no clock, so a fight that failed by NOT firing printed nothing** | `PLAYTEST FAIL ... duration=176.1s walked=358m downs=0 shots=5` with exactly one line in the log between "the crystal is guarded" and "still standing after 90 s" | Its only progress line was the reposition notice, which needs eight fruitless volleys to trigger. That covers a fight that is firing and missing, and says nothing at all about a fight that never gets to fire - five volleys in ninety seconds while the player walked 358 m. The Warden fight was taught to log its position on a cadence when defect 70 hid behind the same silence; this one had not been, and the one run where it mattered was unreadable for it. It now reports position, gap, health and hit count every six seconds, on the clock rather than per volley |
| I36 | **The driver walked INTO the guard it was shooting** | Same run: the navmesh fix (I34) routed to `(guard as Node3D).global_position`, and the fight spent its time closing to contact and backing out again | Fixing the approach to use the navmesh was right; routing it to the guard's own feet was not. Arriving trips the too-close branch, which backs away, which re-opens the gap, which walks in again. A player closes to a range they can shoot from, so the driver now routes to a point 12 m out along its own line to the guard - inside the Sentinel's 22 m firing range, outside the 7 m the driver retreats from |
| I37 | **The test written to catch unusable interactables scored a ray from inside a wall as the clearest line of all** | It passed Cinder and Hallow for their whole history while their grove crystal sat 0.03 m inside `GroveBack` and could never be picked up | `_check_usable_from_somewhere` samples twelve approaches and passes if any has a clear ray. `PhysicsRayQueryParameters3D.hit_from_inside` defaults to FALSE, so the samples that were themselves buried in the wall reported no hit at all and counted as clear - the check answered "usable from six of twelve approaches" about an object usable from none. The docstring of the very next function in the same file is about the player's interact ray needing exactly this flag, for exactly this reason: the file carried the lesson and the check did not apply it. It sets `hit_from_inside` now, as does every ray in the new guard-post gate |
| I38 | **Two guard-fight ranges crossed, and the driver walked in a circle firing nothing** | `PLAYTEST FAIL ... duration=176.8s walked=330m downs=0 shots=0` on Cinder and Hallow, 6 shots on Nerava, all three reported as "the guard was still standing after 90 s" | The fight walks when the gap exceeds 22 m and aims that walk at a fixed range. Moving the walk target to 20 m - a change made to spend less of the approach under fire - put it inside the navmesh arrive tolerance of the 22 m threshold, so arriving left the gap over the threshold and the driver walked to the same place forever. Zero shots in ninety seconds, reported as an unkillable guard: an instrument bug wearing the costume of a game bug, which is the failure this whole section exists for. It was also self-inflicted, chasing a secondary signal (the solo player finishing the fight on 1 hp) at the cost of the primary one. Same shape as defect 72, where the Warden's stand-off and contact radius crossed, and it gets the same treatment: the three ranges are named together, the required ordering is written down, and the driver refuses to run if they violate it rather than producing a confident wrong answer |
| I39 | **The guard fight reversed its strafe every volley, which is not dodging** | The driver reached `crystal.taken crystal_ruins` on 1 hp of 100 on both planets with an open guard, and on a third run a projectile already in the air finished the job | I24 exactly, a second time. That defect was found in the Warden fight - alternating direction each volley oscillates in place, and a player who reverses is standing where the last shot was aimed - and fixed there by holding a direction for three volleys. The guard fight was never given the same treatment, so it spent every guard fight jinking on the spot while being shot. The "solo player finishes on 1 hp" observation was recorded in the design section as a measurement to re-take rather than a number to tune, on the grounds that six of the previous ten apparent balance problems had turned out to be the instrument. It was the instrument again. Seventh time |

### Open defects

#### Closed: the crystal guard on Cinder and Hallow

This section used to say the guard could not be hit, and offered two candidate
causes: that defect 79's collision-mask change had let the guard drift inside
`RuinsBack`, or that set dressing sat too close to the objective. It ended by
saying the way to choose between them was to measure where the shots actually
stop.

That measurement was taken, and **both candidates were wrong**. The shots were
stopping on `Mesa4`, a 12 x 4.5 x 9 block, **0.1 m from the muzzle** - the
driver had walked into a mesa and was firing into it with the guard 25 m away
on the far side, aimed to within two degrees. The guard approach was the one leg
of a run that did not route on the navigation mesh (I34). Neither theory in this
section survived contact with the reading, and the more confident of the two -
the one written up as a risk introduced by the last fix - was the further off.

Two real defects were found underneath it, both by the same measurement: every
crystal guard was placed by a constant that pointed at a wall on all three
planets (80), and Cinder's and Hallow's third crystal was 0.03 m inside
`GroveBack`, so neither planet could be finished (81). Behind those, a staircase
with no width margin (82). None of them was the thing this section named.

The lesson is worth more than the fixes. A characterisation written before the
decisive measurement reads exactly like one written after it, and this one was
specific, plausible, argued from real numbers, and wrong in both branches. It
was also two commits from being acted on. The reason it did not cost anything is
that the next step recorded here was to measure rather than to fix.

**None known elsewhere.** That is a statement about what has been tested, not a claim of
correctness: everything in the "not executed" table above is untested, and
`docs/KNOWN_LIMITATIONS.md` lists what that leaves unknown.

---

## Fun Evaluation

**7 / 10 for one mission. 5 / 10 for the campaign.** Both are inferences, and
neither can discharge a "is it fun" question on its own - nobody has played this
(VERIFY-008), so what follows is reasoning from shape and timing, not from
anyone's experience.

*One mission, flown once: 7.* It has three acts and they are different from each
other. The pre-flight is 22 seconds of set-up, refusal and fix. The surface is
three errands that are genuinely not the same errand - one wants an object
carried to a socket, one wants a hazard shut off somewhere else, one wants a
fight - and each ends with a walk home under a load. The boss escalates through
four phases and changes its behaviour at the end rather than just its numbers.
The beats land where a 3-minute mission needs them.

*The campaign, all three: 5.* Nerava, Cinder and Hallow are the same mission
with different colours. Same three locks in the same order, same temple, same
altar, same boss, same extraction. The second planet teaches nothing the first
did not, and the third teaches nothing the second did not. What changes is the
palette, the crystal names, and how far you walk - 494 m against 693 m, which is
felt as "longer", not as "different". This is what Recommendation 5 is about,
and it is now the highest-value work left: the levels are finishable, so the
next thing that would make the game better is not another fix.

The honest summary is that the mission is in decent shape and the campaign is
one mission repeated. Fixing that is a design job, not a defect hunt.

## Design observations from the measured runs

These are judgements, not measurements, and they are separated from the rest of
this document for that reason. Each names the evidence it rests on. Nobody has
played this game - see VERIFY-008 in `docs/KNOWN_LIMITATIONS.md` - so treat
these as hypotheses for the first human playtest, not as findings.

**The Warden fight has no margin: one volley that lands is the whole health
bar.** The boss fires `BOSS_VOLLEY_PROJECTILES` = 3 projectiles per volley, and
each does `GUARDIAN_PROJECTILE_DAMAGE` = 33 against a player's 100. Nothing
restores health after the altar. So a solo player's entire boss fight is "do not
take three hits", and a single volley that connects fully does it in one go.

Every loss measured this session has that exact shape - 100, then 34, then
downed - and the wins differ only in which volleys missed. That is not by itself
a defect: dodging is the mechanic, and the fight is meant to be close-run. It
does mean the difficulty has no gradient. There is no such thing as *nearly*
losing this fight, or winning it hurt; a run is decided by a single binary event
and the player has no way to spend a small mistake.

Whether the resulting loss rate is acceptable is a real question and it is being
given a denominator rather than an opinion - repeated solo runs on one build,
because the five runs that produced this observation span three different driver
builds and are an anecdote, not a rate.

**Cinder and Hallow are not two levels. They are one level with two palettes.**
This is the campaign-repetition problem stated as a number rather than an
impression, and the number is worse than the impression was. Comparing the two
scene files node by node: of the 96 nodes they share by name, **91 have byte-
identical transforms**. The five that differ are the sun and four pieces of
scatter. Every wall, mesa, plateau tier, approach step, crystal, pedestal,
altar and drop pod is in exactly the same place on both planets.

The crystal layout says the same thing across all three. Every one of the nine
crystals sits between 42 and 48 m from its altar - a spread of about 2 m across
nine trips on three planets. Nerava places them on a symmetric three-point star
at bearings 267 / 93 / 0; Cinder and Hallow both use 214 / 329 / 87, the same
numbers as each other.

So "vary the journeys, not just the locks" is not a matter of taste. Nine trips
of the same length, six of them from identical positions, is the measurement
behind the campaign scoring 5 while one mission scores 7 - and it is a level
authoring job, not a systems one: the locks, the guards and the hazard already
differ, and the geometry they hang on does not.

**The crystal guard costs a dodging player one hit. It was the instrument, for
the seventh time.** This entry previously read that the guard cost a solo player
almost all of their health - the driver reached `crystal.taken crystal_ruins` on
**1 hp of 100** on both planets with an open guard - and it said the thing to do
was measure what the fight costs a player who strafes, rather than change a
number.

Measured: **67 hp** on all three planets - Nerava, Cinder and Hallow. One projectile, not three.
The driver had been reversing its strafe on every volley, which is oscillating
in place rather than dodging (I39), and it was standing where each previous shot
had been aimed. The crystal guard needs no balance change at all.

Recording the near-miss as well as the result. The 1 hp reading was real, it was
reproduced on two planets, and the arithmetic behind it was clean - the guard's
projectile does 33 and three of them is 99. Every part of it was true except the
conclusion. What stopped it becoming a difficulty change was the standing rule
that an apparent balance problem gets one more measurement before it gets a
number, and the tally is now seven of eleven.

**The pre-flight act is the right length.** 22 seconds solo for a course, three
stations, a refused lever, a seat and a launch. It has a shape - set up, be
told no, fix the reason, go - and the refusal is what gives it one. With a crew
of four the four tasks parallelise, so it gets shorter rather than longer with
more players, which is the correct direction for a co-op opening.

**The crystal hunt was the weakest part, and the fix already existed.** 64 of
the 124 seconds to the boss were three structurally identical round trips: walk
out, press E, walk back, press E. The crystal locks - a coupling to fetch, a
guard to kill, a hazard to shut off - are exactly the mechanism that breaks
that repetition, and `MissionRules` already supported all three on any mission.
Nerava, the mission every player sees first, applied only the coupling.

It now applies two: the cave crystal is still sealed behind the coupling, the
ruins crystal is guarded, and the grove crystal is still a plain fetch, which
is what teaches the base move. Nerava has no hazard for the third lock to key
off, so that still waits for Cinder. Measured afterwards, the three trips are
12.8 s, 10.1 s and 10.2 s against 20 s each before - and, more to the point,
they are no longer the same trip three times.

**The coupling errand is the most interesting thing in the mission** because it
is the only one with a constraint: it fills the same single inventory slot a
crystal does, so it cannot be combined with anything. That is a real decision
in a four-player crew - who breaks off - and it costs one player 13 seconds.

**The Warden's numbers are tuned for a crew, not for one player.** 900 health
plus three 120-health shield nodes, against a blaster doing 25 a shot on a 0.22
s cadence that overheats after about twelve shots, is 51 hits and roughly 25
seconds of trigger time even before dodging. Solo, under a three-projectile
volley every 2.6 seconds, that is a long time to stay alive with 100 health and
nobody to revive you. Nothing scales the boss to crew size.

## Recommendations

Ranked by what the evidence supports, with the reasoning stated so a designer
can disagree with it on the merits.

**1. DONE - Nerava carries a second lock.** `MissionRules.locked_crystals` gave
Nerava only the coupling, with the comment "Nerava is the tutorial", which was a
real reason. The measured consequence was that the first mission any player sees
was one interesting errand followed by two identical fetch-and-carry trips - and
the first mission is the one that decides whether they play a second. The Ruins
Crystal now has a guard, leaving exactly one plain fetch, which is enough to
teach the base move. Measured solo: the guard fight lasts 3.2 s and 5 volleys,
and the crystal that used to take 9 s now takes 13.3.

**2. DONE - the crew is restored at the altar.** Adding that guard immediately
exposed something the flat mission had hidden: health was a one-way resource
across an entire descent, so a solo player who fought the guard arrived at a
Warden tuned to be close-run from full and was downed having played correctly.
Difficulty by attrition rather than by play, and it would have got worse with
every lock added in front of the boss. Placing the third crystal now restores
the crew - the one moment that unambiguously means "the work is done, the fight
is next". Same run, after the fix: 0 downs across all three strategies.

**3. DONE - the Sentinel scales to crew size,** as the Warden already did, with
a floor of `GUARD_MIN_HITS` so a solo guard is shorter but never a formality.

**4. DONE - the pre-flight checklist says where each station is.** "Next: Prime
the reactor (3 left)" named the job and not the place, on a 41 m deck divided by
four bulkheads, so the only way to learn the ship was to walk all of it once.

**5. Give the crystal trips different shapes, not just different locks.** Still
open, and now the weakest measured part of the mission. All three run out and
back at about 10-13 s each. The locks vary what you do at the far end; they do
not vary the journey. The one that already reads differently is the coupling,
because it makes you give up your inventory slot - a constraint that follows you
the whole way rather than sitting at the destination.

**6. Nobody has heard the game or seen it in motion at a real frame rate.** The
gap that everything above is written around. See VERIFY-002, VERIFY-007 and
VERIFY-008 in `docs/KNOWN_LIMITATIONS.md`.

## Next steps

In the order they would pay off.

1. **Play it.** Everything this document cannot say is waiting on one person
   with a Windows build and half an hour. `docs/TEST_CHECKLIST.md` has the
   ordered walkthrough, rewritten for the ship-and-flight structure.
2. **Run the Windows build workflow.** `build-windows.yml` is
   `workflow_dispatch` only and has never been triggered (VERIFY-001).
3. **Take recommendation 5** - varying the journeys rather than the locks. This
   has moved up from "last measured weakness in the crystal hunt" to the most
   valuable thing left to do at all. With all three planets finishable, the
   campaign's problem is no longer that it breaks; it is that Cinder and Hallow
   repeat Nerava beat for beat in different colours. See the Fun Evaluation:
   one mission scores 7, three of the same mission score 5.
4. **Measure what the crystal guard costs a player who dodges.** The driver
   arrives at `crystal.taken` on 1 hp of 100 on two planets, but it closes on a
   navigation path without strafing, so some of those hits are its own. Six of
   the last ten apparent balance problems turned out to be the instrument, so
   this is a measurement to take before it is a number to change.

## Change Log

This pass, in the order the work happened. Each line names what it changed and
what proved it.

| Change | Proof |
|---|---|
| Guard posts chosen rather than assumed - `SpawnManager.guard_post` scores twelve posts by clearance and by how far shots can run outward from each | Nerava's guard went from a post 1.0 m inside a 10 m wall to one with 5 of 12 bearings open; the old placement now fails the new gate on Cinder and Hallow, naming `RuinsBack` |
| `GroveBack` rotated 90 degrees on Cinder and Hallow, so the grove crystal is 5.97 m clear instead of 0.03 m inside it | the third crystal can be picked up; both planets finish |
| The plateau approach tapered 13 / 11 / 9 so each tier overhangs the one above | the carry home no longer wedges beside the steps |
| Driver: guard approach routes on the navigation mesh | the shot-stop probe reads `THE GUARD` instead of `Mesa4` at 0.1 m |
| Driver: guard fight reports position, gap, health and hits every six seconds | a fight failing by not firing is now legible; it printed nothing before |
| Driver: guard-fight ranges named together with a startup ordering check | a crossed pair had it walking in a circle firing nothing |
| Driver: `_shot_report` - where does the shot actually stop | this is what found defects 80, 81 and I34 |
| Driver: the Warden progress log no longer casts a freed node | one run in twelve aborted on the winning shot |
| Driver: a downed player is named in every failure, once, centrally | "could not reach crystal_ruins" was really "was shot and is lying on the floor" |
| `test_scene_integrity`: guard post clear of scenery, crystal visible from it, shootable along some bearing, approach rises within the level's own `agent_max_climb`, each tier overhangs the one above | +135 assertions; 1634 -> 1769 |
| `test_scene_integrity`: `hit_from_inside` on the usable-from-somewhere probe | it had been scoring rays that start inside walls as the clearest of the twelve, which is how a crystal shipped inside one |
| `test_lan_discovery`: the expiry bound derived from the announce interval and the timeout instead of a hard-coded 1.0 | the bound had exactly zero margin and failed in both directions |

**Withdrawn this pass:** the open-defect entry claiming the crystal guard could
not be hit, and both of the causes it proposed. The measurement it asked for was
taken and refuted both. See "Open defects" above - it is kept rather than
deleted, because a confident wrong diagnosis is worth more in the record than
out of it.
