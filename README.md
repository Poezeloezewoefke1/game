# STARBOUND STATION: THE LOST SIGNAL

A 1-4 player cooperative third-person space adventure built in Godot 4.5.1 with
GDScript. One complete, finished 10-15 minute mission rather than a large
unfinished feature list.

Your crew wakes aboard the Wayfinder Station, descends to the jungle world of
Nerava, finds three Power Crystals hidden along the ruins, cave and grove paths,
powers the temple altar, retrieves the Star Map, survives the Sentinel that
wakes when you take it, and gets back to the Drop Pod alive.

---

## Project status

**Playable vertical slice, verified headlessly; not verified on Windows.**

Concretely, and separating what has been *proven* from what has not:

| Area | Status | Evidence |
|---|---|---|
| Scripts compile, scenes instantiate | Verified | `tests/run_tests.gd` phases 1-2, 46 scripts / 20 scenes |
| Mission rules, state machine, name hygiene, rate limiting | Verified | 143 unit assertions |
| Simultaneous requests (crystal race, revive race, double extraction) | Verified | `tests/integration/test_concurrency.gd` |
| Full mission lobby -> victory | Verified | `tests/integration/test_mission_flow.gd` against a real ENet host |
| Combat, downed, revive, Star Map drop, failure | Verified | `tests/integration/test_combat_and_revive.gd` |
| Sentinel targeting, stagger, projectiles, cleanup | Verified | `tests/integration/test_sentinel.gd` |
| Replay leaves no stale state (x3) | Verified | `tests/integration/test_session_reset.gd` |
| Every objective is physically reachable | Verified | `tests/integration/test_level_reachability.gd` (navmesh path queries) |
| 4-player session over real ENet, hostile-client probes | Verified | `tools/run_multiplayer_check.sh`, 5 OS processes, 73 assertions |
| Windows export produces a real PE32+ executable | Verified | `.github/workflows/build-windows.yml`, and locally |
| **The Windows executable launches and plays** | **NOT verified** | No Windows machine was available - see `docs/KNOWN_LIMITATIONS.md` |
| **Two physical LAN devices** | **NOT verified** | Only loopback was available |
| **Anything visual** | **NOT verified** | Every run so far has been headless |

`docs/QA_REPORT.md` records exactly which runs produced this evidence.

---

## Requirements

* **Godot 4.5.1-stable.** The version is pinned; see `docs/TECH_STACK.md`.
* For a Windows build, the matching 4.5.1-stable export templates.

## Getting started

```bash
git clone https://github.com/Poezeloezewoefke1/game.git
cd game
godot --path . --editor      # or open project.godot from the Godot project manager
```

Press **F5** to run. The first launch imports resources, which takes a moment.

### Running the checks yourself

```bash
# Import, compile every script, instantiate every scene, run all automated
# tests, and fail on engine errors the test runner itself cannot see
tools/run_validation.sh /path/to/godot

# Host + 3 clients + an over-capacity client, as real OS processes
tools/run_multiplayer_check.sh /path/to/godot 7700 3

# Repository structure and hygiene
tools/check_structure.sh
```

All three are what CI runs. Nothing in CI is a check you cannot reproduce.

---

## Controls

| Input | Action |
|---|---|
| `W` `A` `S` `D` | Move |
| Mouse | Look and aim |
| `Space` | Jump |
| `Left Shift` | Sprint |
| `E` | Interact — hold on a downed teammate to revive |
| `Left Mouse Button` | Fire blaster |
| `Escape` | Pause menu |

The blaster runs on **heat**, not ammunition. It cools on its own; overheat it
and it locks until it has cooled below 45%. It cannot hurt teammates, and its
only combat effect is staggering the Sentinel — ten host-validated hits buy you
three seconds.

---

## Playing together

### Hosting

1. Enter a name (2-16 characters).
2. Leave the port at **7000** unless you have a reason to change it.
3. Press **Host Game**.
4. Tell your crew your LAN IP: `ipconfig` on Windows, `ip addr` on Linux,
   `ifconfig` on macOS. You want the `192.168.x.x` or `10.x.x.x` address.
5. When everyone is in the lobby, press **Start Mission**.

### Joining

1. Enter a name.
2. Enter the host's IP address and the same port.
3. Press **Join Game**.

Up to **four players** including the host. The fifth is turned away with an
explicit message rather than a silent failure.

### LAN testing on one machine

Run two copies of the game and have the second join `127.0.0.1`. From the
editor, *Debug -> Run Multiple Instances* does the same thing. For a headless
check, `tools/run_multiplayer_check.sh` runs a whole session this way.

### Direct IP over the internet — read this before trying

Playing outside your LAN needs the **host** to:

* allow the game through the firewall, and
* forward **UDP port 7000** to the hosting machine.

There is **no NAT traversal, no relay and no matchmaking**. If the port is not
reachable, clients will simply fail to connect. Forwarding a port exposes it to
the internet, and this game's protocol is neither authenticated nor encrypted:
anyone who can reach the port can attempt to join. Prefer a LAN or a VPN, and
close the port when you are done. `docs/NETWORK_RULES.md` has the full threat
model.

### If the host leaves

The session ends for everyone, with a message. There is no host migration and
no rejoin — see `docs/KNOWN_LIMITATIONS.md`.

---

## Building for Windows

### From the editor

1. Install the **4.5.1-stable** export templates (*Editor -> Manage Export
   Templates*). They must match the editor version exactly.
2. *Project -> Export* -> **Windows Desktop** -> *Export Project*.
3. Export to `build/windows/StarboundStation.exe`.

### From the command line

```bash
godot --path /absolute/path/to/game --headless \
      --export-release "Windows Desktop" \
      "/absolute/path/to/game/build/windows/StarboundStation.exe"
```

Use absolute paths for both. `--path` sets the project; the export path is
resolved relative to the current working directory, not the project, which is a
common way to end up with a build in an unexpected place.

The release folder contains **both** of these, and the game will not start
without both:

```
build/windows/
├── StarboundStation.exe
└── StarboundStation.pck
```

### From GitHub Actions

Run the **Build Windows** workflow (*Actions -> Build Windows -> Run workflow*),
or push a `v*` tag. Download the `starbound-station-windows-x86_64` artifact and
unzip the whole folder. Binaries are never committed to the repository.

---

## Screenshots

_Not yet captured — every run so far has been headless. Add them here once the
game has been run on a desktop._

```
docs/images/main-menu.png
docs/images/wayfinder-hub.png
docs/images/nerava-temple.png
docs/images/sentinel.png
```

---

## Repository layout

```
assets/      placeholder audio, materials, models, particles, textures
docs/        architecture, network rules, QA, traceability, checklists
resources/   items, missions, settings
scenes/      entities, enemies, interactables, levels, multiplayer, ui
scripts/     core, enemies, interactables, multiplayer, player, ui, utility
tests/       unit, integration, the headless runner, the multi-process probe
tools/       structure check, multiplayer check
```

## Documentation

| Document | What it is for |
|---|---|
| `docs/ARCHITECTURE.md` | How the game is put together and why |
| `docs/NETWORK_RULES.md` | Authority, validation, rate limits, threat model |
| `docs/TECH_STACK.md` | Pinned versions and why |
| `docs/REQUIREMENTS_TRACEABILITY.md` | Every requirement -> code -> test -> status |
| `docs/TEST_CHECKLIST.md` | The full manual and automated test matrix |
| `docs/QA_REPORT.md` | What was actually run, and what was not |
| `docs/KNOWN_LIMITATIONS.md` | Everything unverified or deliberately out of scope |
| `docs/BUILD_MANIFEST.md` | What a build contains and how it is produced |
| `docs/RELEASE_CHECKLIST.md` | What must be true before calling a build releasable |
| `docs/REPOSITORY_SETUP.md` | GitHub settings that need a human |

## Known limitations

The short version: no host migration, no rejoin, no join-in-progress, no NAT
traversal, no encryption or authentication, and the Windows build has never been
launched. The full list, with reasoning, is in `docs/KNOWN_LIMITATIONS.md`.

## License

MIT — see `LICENSE`. All art, geometry and audio are original placeholders
generated in code or built from Godot primitives; no third-party assets are
bundled.
