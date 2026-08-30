# Known limitations

Two kinds of entry: things that are **unverified** (they may work, nobody has
proven it) and things that are **out of scope** (deliberately not built).

Nothing here is hidden in a footnote elsewhere. If a claim is not supported by
evidence, it belongs on this page.

---

## Unverified

### VERIFY-001 - The Windows executable has never been launched

**Status:** blocked.
The export itself is verified: `--export-release "Windows Desktop"` produces a
`PE32+ executable (GUI) x86-64, for MS Windows` plus its `.pck`, and CI asserts
the file type on every build. Whether that executable **starts, renders, accepts
input, hosts, or joins** is unknown - no Windows machine was available at any
point.
**To close it:** run the manual `CI and export` section of
`docs/TEST_CHECKLIST.md` on a Windows machine.

### VERIFY-002 - Nothing has been seen on a screen

**Status:** blocked.
Every run so far has been `--headless`. Geometry, lighting, materials, the HUD
layout, camera feel, the third-person spring arm, readability of the interaction
prompt and the downed marker are all **unverified**. They are constructed
correctly enough to instantiate without error, which is not the same as looking
right.
**To close it:** run the game on a desktop and work through the manual sections
of `docs/TEST_CHECKLIST.md`.

### VERIFY-003 - Only loopback networking has been tested

**Status:** partially verified.
The multi-process check runs a genuine host plus three clients plus an
over-capacity client as separate OS processes over real ENet - but all on
`127.0.0.1`. Two physical machines on a LAN, real packet loss, real latency and
real MTU behaviour are **unverified**, as is anything about internet play
through a forwarded port.
**To close it:** two machines, one LAN, the `Networking and security` section of
`docs/TEST_CHECKLIST.md`.

### VERIFY-004 - No artificial latency or packet loss has been applied

**Status:** unverified.
The interaction validation range carries deliberate slack for latency
(`INTERACT_VALIDATE_DISTANCE` 5.0 m against a client prompt range of 3.2 m), and
the movement plausibility envelope carries slack for jitter. Neither margin has
been tested against real adverse conditions. Under sustained high latency,
legitimate players may see interactions rejected, or the movement validator may
correct them.
**To close it:** run with a network conditioner (`tc netem` on Linux, Clumsy on
Windows) at 100 ms / 3% loss and repeat the mission.

### VERIFY-005 - Audio has never been heard

**Status:** unverified.
All cues are original tones synthesised in code, and `AudioDirector` disables
itself entirely under a headless display server, so no audio path has ever
actually run. Mixing, volume balance and whether the cues are distinguishable
are unknown.

### VERIFY-006 - Performance has not been measured

**Status:** unverified.
The design avoids the usual causes of degradation - no per-frame whole-tree
searches, no unbounded spawning, projectiles that despawn on hit/timeout/reset,
navigation repathing on a timer rather than per frame, and a replay test that
asserts entity counts do not grow across three runs. But no frame time, memory
figure or draw-call count has been measured, on any hardware.

---

## Design limitations (deliberate)

### LIMIT-001 - No host migration

If the host leaves, the session ends for everyone with a clear message and the
in-progress mission is discarded. No client is promoted. Migration would require
transferring authority over every entity mid-flight, and getting it subtly wrong
is worse than a clean ending.

### LIMIT-002 - No rejoin, and no join in progress

Joins are refused once the host starts the session; a dropped player cannot come
back. The alternative is a full state-transfer path that would be the single
most complex and least testable part of the project.
A disconnecting player's **crystal is returned to the world** and their **Star
Map is dropped**, specifically so their departure cannot make the mission
unwinnable.

### LIMIT-003 - No NAT traversal, relay or matchmaking

LAN and direct IP only. Internet play requires the host to forward UDP 7000.

Join codes do **not** change this. A code is an encoding of an address, not a
name looked up on a server, so it reaches exactly the hosts a typed address
would. Making chosen names work from anywhere needs either a registry service
(which solves addressing but still leaves NAT) or a relay (which solves NAT but
is not free at scale). Both were deliberately left out of this scope.

### LIMIT-007 - Discovery is local-network only, and unauthenticated

Broadcasts do not cross routers, so the session browser finds sessions on your
own network and nothing else.

Announcements are also unauthenticated: anyone on the network can advertise a
session with any name, pointing at their own machine. The address is always
taken from the UDP source rather than the packet body, so an announcement cannot
impersonate a *different* host — but it can advertise itself attractively. On a
home network this is no different from someone telling you the wrong IP. On an
untrusted network, join by code.

### LIMIT-008 - One session browser per machine

The browser binds a fixed UDP port, so a second copy of the game on the same
computer cannot browse. This is stated in the UI, and joining by code or address
still works. It affects local testing more than real play.

### LIMIT-004 - No authentication or encryption

Anyone who can reach the port can attempt to join, and traffic is readable and
modifiable in transit. The protocol version check is a compatibility check, not
a security control. Do not expose the port to the open internet.

### LIMIT-005 - The host is fully trusted

A modified host can do anything. The security model protects players from a
malicious *client*, not from a malicious host.

### LIMIT-006 - Client-side "Return to Lobby" is really "Leave Session"

Only the host can move the whole crew back to the lobby, because only the host
drives scene transitions. On a client the button is labelled **Leave Session**
and the end-of-mission screens explain that the host is choosing. This is
honest labelling of a real constraint rather than a button that silently does
nothing.

---

## Balance and content notes

### BAL-001 - 100 health against 33 damage means four hits, not three

The specified constants are `MAX_HEALTH = 100` and
`GUARDIAN_PROJECTILE_DAMAGE = 33`. Three hits therefore leave a player on **1
HP**, and it takes a fourth to down them - which reads to a player like a bug
("that should have killed me"). The constants are implemented exactly as
specified and are **not** silently adjusted.
`tests/integration/test_combat_and_revive.gd` asserts this behaviour explicitly,
so changing either constant fails a test rather than quietly altering how
survivable the Sentinel is.
**If three hits was the intent, the fix is `GUARDIAN_PROJECTILE_DAMAGE = 34`.**
That is a design decision, not an implementation detail, so it has been left to
the owner.

### BAL-002 - A downed player keeps their crystal

Only the Star Map drops when a carrier goes down. A downed crystal carrier keeps
theirs, so the crew must revive them to progress. That is intentional
cooperative pressure. It is only unrecoverable if that player *disconnects*, and
that case returns the crystal to the world (see LIMIT-002).

### BAL-003 - The Sentinel cannot be killed

By design. Ten host-validated blaster hits stagger it for three seconds; there
is no health pool and no kill. The mission is a heist, not a boss fight.

---

## Build and tooling notes

### BUILD-001 - The exported pack lists test file paths (not test code)

Godot's engine-generated `.godot/uid_cache.bin` and
`global_script_class_cache.cfg` are packed with every build and contain resource
paths for **everything** in the project, including `tests/`. The test *code*
is correctly excluded - verified by asserting that no test source, no
`NETCHECK` string and no compiled test bytecode appear in the pack, a check CI
runs on every Windows build. What remains is a handful of path strings in an
engine cache. Cosmetic, and not controllable from the export preset.

### BUILD-002 - Branch naming differs from the original specification

The specification names the development branch `claude/development`. This work
was carried out on **`claude/starbound-station-dev-62c8jv`**, which is the
branch the environment designated. `.github/workflows/validate.yml` triggers on
**both**, so renaming later needs no workflow change.

### BUILD-003 - `--check-only --script` cannot validate this project

Godot does not register autoload singletons in that mode, so every file that
calls an autoload method reports a false `Identifier not found`. Real validation
therefore runs the project (`res://tests/test_runner.tscn`), where autoloads are
live. Worse, `load()` returns a **non-null but invalid** `GDScript` for a file
that failed to parse - checking only for `null` makes a compile phase blind, and
CI would report green on a project that cannot run. The runner checks
`can_instantiate()` and `get_instance_base_type()` instead.

### BUILD-005 - Two suspended coroutines are reported at test-run exit

Running the suite with `--verbose` ends with:

```
WARNING: ObjectDB instances leaked at exit
Leaked instance: GDScriptFunctionState:...
Leaked instance: GDScriptFunctionState:...
```

These are **coroutines belonging to the test runner itself**, suspended on
`await` when `get_tree().quit()` fires. A suspended coroutine is never resumed
during shutdown, so its function state is reported as leaked.

The evidence that this is a shutdown artifact rather than a per-object leak: the
count stays at exactly **two** across a run that mounts roughly ten levels,
spawns several Sentinels and replays the mission three times. A genuine leak in
level loading or guardian spawning would scale with those counts.

Separately, and this one *was* a real risk worth fixing: `NavUtil.await_map_usable`
now takes an optional `owner` and abandons the wait as soon as that node is
freed. Without it, a Sentinel despawned at the end of a mission could leave a
coroutine polling the navigation map for another four seconds while holding a
reference to a freed node.

### BUILD-004 - Adding a `class_name` requires an import pass first

A newly added global class is invisible until `godot --headless --path . --import`
refreshes `.godot/global_script_class_cache.cfg`. Both workflows run the import
step before validating, so CI is unaffected; locally, run the import once after
adding a `class_name`.
