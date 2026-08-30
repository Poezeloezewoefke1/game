# QA report

The rule for this document: **a claim without evidence is not a claim.** Every
line below is either backed by a command whose output was read, or explicitly
marked as not run.

**Engine used for every result here:** Godot `4.5.1.stable.official.f62fdbde1`,
Linux x86_64, headless.

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

**Result: PASS — 79 checks, 589 assertions, exit code 0, no engine errors.**

The wrapper matters. GDScript cannot hook the engine's error stream, so a
`SCRIPT ERROR` raised *inside* a test is printed by the engine while the suite
still reports PASS. `tools/run_validation.sh` greps the run log for engine-level
errors and fails on them. That gate was verified by removing the fix for defect
17 below and confirming the gate returns exit code 1 — a gate that has never
fired is not a gate.

```
[1/3] Compiling scripts...     46 scripts, 0 failed
[2/3] Loading scenes...        20 scenes,  0 failed
[3/3] UNIT tests...
      PASS  test_mission_rules        (41 assertions)
      PASS  test_name_sanitizer       (23 assertions)
      PASS  test_rate_limiter         (13 assertions)
      PASS  test_state_machine        (66 assertions)
      INTEGRATION tests...
      PASS  test_combat_and_revive    (62 assertions)
      PASS  test_concurrency          (17 assertions)
      PASS  test_level_reachability   (50 assertions)
      PASS  test_mission_flow         (60 assertions)
      PASS  test_scene_integrity      (137 assertions)
      PASS  test_sentinel             (28 assertions)
      PASS  test_session_reset        (92 assertions)
 RESULT: PASS   (79 checks passed, 589 assertions)
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
* Navigation-mesh path queries proving every objective is reachable in both
  directions and the playable area is enclosed.

### 3. Multi-process multiplayer check

```
tools/run_multiplayer_check.sh <godot> 7870 3
```

**Result: PASS — 73 assertions across 5 OS processes, exit code 0.**

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
StarboundStation.pck: 224K
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

---

## What was NOT executed

Stated plainly. None of the following is claimed to work.

| Not run | Why | Tracked as |
|---|---|---|
| The Windows executable was never launched | No Windows machine | VERIFY-001 |
| Nothing was ever displayed on a screen | Every run was headless | VERIFY-002 |
| Two physical LAN devices | Only loopback available | VERIFY-003 |
| Internet play through a forwarded port | No such network | VERIFY-003 |
| Artificial latency or packet loss | No conditioner available | VERIFY-004 |
| Audio playback | `AudioDirector` disables itself when headless | VERIFY-005 |
| Frame time, memory or draw-call measurement | No display, no target hardware | VERIFY-006 |
| GitHub Actions workflow execution | Workflows are authored and YAML-validated; they have not been run | — |
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

---

## Open defects

**None known.** That is a statement about what has been tested, not a claim of
correctness: everything in the "not executed" table above is untested, and
`docs/KNOWN_LIMITATIONS.md` lists what that leaves unknown.
