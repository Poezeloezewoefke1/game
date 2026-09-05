# Test checklist

Legend: **[A]** covered by an automated test · **[N]** covered by the
multi-process multiplayer check · **[P]** covered by the automated playtest,
which drives the shipped game with simulated keyboard and mouse · **[M]**
manual, needs a human at a screen · **[B]** blocked in the current environment.

**[A] and [P] are different claims.** An [A] test calls the game's API -
`GameManager.request_interact()` - and proves the rules are right. A [P] check
walks a player there with `Input.action_press("move_forward")` and looks at the
thing with a synthetic mouse, and proves the rule can be reached by playing. A
row that is only [A] can be green in a game that cannot be played; that is not
hypothetical, it is how BUG-002 in `docs/QA_REPORT.md` survived 1394 assertions.

Run the automated layers with:

```bash
godot --headless --path . res://tests/test_runner.tscn
tools/run_multiplayer_check.sh /path/to/godot 7700 3
tools/run_playtest.sh /path/to/godot cautious
tools/check_structure.sh
```

---

## Main menu

| # | Case | Cover |
|---|---|---|
| 1 | Launches to the main menu | [M] |
| 2 | Empty player name is refused with a message | [A] `test_name_sanitizer` (rule) / [M] (UI) |
| 3 | One-character name is refused | [A] |
| 4 | Very long name is clamped to 16 characters | [A] |
| 5 | Control characters are stripped from a name | [A] |
| 6 | Zero-width and direction-override characters are stripped | [A] |
| 7 | Host game succeeds on the default port | [A] `TestSession.start` / [N] |
| 8 | Host game on a port already in use gives a readable error | [M] |
| 9 | Join a valid LAN IP | [B] loopback only — [N] covers loopback |
| 10 | Join an invalid address is refused before connecting | [A] `NetworkManager.resolve_address` |
| 11 | Join an unreachable host times out with a message | [M] |
| 12 | Join the wrong port fails cleanly | [M] |
| 13 | Settings panel persists sensitivity, volume and invert | [M] |
| 14 | Quit exits | [M] |

## LAN discovery and join codes

| # | Case | Cover |
|---|---|---|
| D1 | The host announces a named session | [A] `test_lan_discovery` / [N] |
| D2 | Another process discovers it and can join without typing an address | [N] (cross-process) |
| D3 | The advertised address comes from the UDP source, not the packet body | [A] |
| D4 | Malformed announcements are ignored (9 shapes) | [A] |
| D5 | An oversized packet is discarded unread | [A] |
| D6 | The browser is capped and cannot be flooded | [A] |
| D7 | A `\|` in a display name cannot shift other fields | [A] |
| D8 | A host that stops announcing drops out of the list | [A] |
| D9 | A second copy on one machine reports the busy port instead of an empty list | [M] |
| D10 | Session names are sanitised before display | [A] |
| C1 | A code round-trips to the same address and port | [A] `test_join_code` |
| C2 | Every single-character typo is caught | [A] (exhaustive) |
| C3 | Every transposition is caught | [A] (exhaustive) |
| C4 | I/L/O/U are folded to 1/1/0/V | [A] |
| C5 | Lowercase, spaces and underscores are forgiven | [A] |
| C6 | Garbage is rejected with a readable reason | [A] |
| C7 | The join field accepts a code or an address | [M] (UI) |
| C8 | A private-address code is labelled local-only in the lobby | [M] (UI) |
| C9 | A public-address code warns about port forwarding | [M] (UI) |

## Lobby

| # | Case | Cover |
|---|---|---|
| 15 | The host appears in the roster | [A] `test_mission_flow` |
| 16 | One client joins and the roster replicates | [N] |
| 17 | Three clients join (4 players total) | [N] |
| 18 | The four-player cap is enforced | [N] |
| 19 | The fifth player is refused with the *correct* reason | [N] |
| 20 | A client disconnecting in the lobby updates the roster | [M] |
| 21 | The host disconnecting returns clients to the menu with a message | [M] NET-017 |
| 22 | The host can start the mission | [A] / [N] |
| 23 | A client cannot force the mission to start | [N] |
| 24 | Duplicate display names are allowed and do not confuse identity | [A] (identity is the peer id) |
| 25 | Ready flags are cleared when returning to the lobby | [A] `test_session_reset` |

## Application shell

| # | Case | Cover |
|---|---|---|
| A1 | The game boots to the main menu | [A] `test_app_shell` |
| A2 | The menu does not capture the mouse | [A] |
| A3 | Hosting moves to the lobby by itself | [A] |
| A4 | The lobby does not capture the mouse | [A] |
| A5 | **Entering the hub captures the mouse, so the player can move** | [A] gate verified by reintroducing the defect |
| A6 | The HUD is mounted in a gameplay scene and removed on leaving | [A] |
| A7 | Pausing releases the mouse; resuming recaptures it | [A] |
| A8 | Returning to the lobby releases the mouse and clears overlays | [A] |
| A9 | Movement, look, jump, sprint actually feel right | [M] |

## The Starfarer: crew deck and pre-flight

The "hub" of earlier builds is gone; the crew now spends the first act aboard a
ship that flies. `ship` is a gameplay scene like any surface - it gets a
spawner, a HUD and players.

| # | Case | Cover |
|---|---|---|
| 26 | All players spawn on the crew deck | [A] / [N] |
| 27 | Nameplates appear above other players | [M] |
| 28 | Player movement replicates between peers | [N] (position-driven pickups prove it) |
| 29 | The host can set a course at the nav console | [A] / [N] |
| 30 | A client cannot set a course | [N] |
| 31 | An out-of-range interact request is refused | [A] |
| 32 | The readiness barrier waits for every peer | [N] |
| 33 | A peer that never acknowledges is disconnected on timeout | [M] |
| 34 | A stale transition acknowledgement is ignored | [A] (epoch/transition id checks) |
| 35 | Every ready client reaches the destination surface | [N] |
| 26a | Every deck station is reachable on foot from the spawn | [A] `test_level_reachability` (capsule sweep along `ShipRoutes`) |
| 26b | The whole deck spine is walkable end to end | [A] `test_level_reachability` |
| 26c | Furniture leaves standing room at each station | [A] `test_level_reachability` |
| 26d | The four pre-flight tasks each complete once, in any order | [A] `test_mission_rules` / [P] |
| 26e | A task cannot be completed twice | [A] |
| 26f | The launch lever refuses while the checklist is unfinished | [A] |
| 26g | The launch lever refuses while any crew member is unseated | [A] / [P] |
| 26g1 | **The launch control is within a seated pilot's reach and swivel** | [A] `test_level_reachability` |
| 26g2 | The pilot's seat is named as the one with the control, on the other bridge seats | [A] / [M] |
| 26g3 | A strapped-in pilot can launch by looking at the console and pressing E | [P] |
| 26h | A crew seat can be taken, and holding forward does not walk you out of it | [P] (drift measured, < 0.5 m) |
| 26i | A seat already occupied refuses a second player | [A] |
| 26j | The HUD shows the remaining checklist aboard the ship, not the Star Map line | [A] `test_scene_integrity` / [M] |
| 26k | **Every pre-flight station says WHERE it is, not just what it does** | [A] `test_mission_rules` / [M] |
| 26l | A station with no location entry reads as its bare label, never a dangling dash | [A] |
| 26k | Beds, mess, med bay and cargo are walkable, not just decorative | [P] (`explorer` strategy tours them) |

## Flight: launch, transit and landing

The flight is three host-clock states rendered identically on every peer;
`FlightSequence` never sets state, so there is no per-peer animation drift.

| # | Case | Cover |
|---|---|---|
| 26l | Pulling the lever moves the mission to LAUNCHING | [A] / [P] |
| 26m | LAUNCHING -> IN_TRANSIT -> LANDING advance on the host clock | [A] / [P] |
| 26n | The engine bells light during a burn and go dark in transit | [M] |
| 26o | Star streaks appear only in transit, outside the windows | [M] |
| 26p | Landing mounts the destination surface and spawns the crew there | [A] / [P] |
| 26q | The objective line reads "Descending..." during the landing | [P] |
| 26r | A client sees the same phase at the same time as the host | [N] |

## Multiple planets and mission unlocks

| # | Case | Cover |
|---|---|---|
| 26s | Nerava is flyable on a fresh save; Cinder and Hallow are not | [A] `test_mission_rules` |
| 26t | Completing a mission unlocks exactly the next one in order | [A] |
| 26u | The nav console names the destination and says why others are locked | [P] (prompt read: "Course: Nerava (no other destination unlocked)") |
| 26v | Each planet has its own sky, palette and crystal names | [M] / [A] `test_scene_integrity` |
| 26w | Cinder and Hallow are reachable and walkable | [A] `test_level_reachability` |
| 26x | **Every interactable id names its own level** - Cinder's altar and drop pod carried Nerava's | [A] `test_scene_integrity` |
| 26y | Cinder and Hallow can be flown end to end, not just loaded | **PARTIAL** [P] - both now reach the ruins guard; that fight is the open defect |
| 26z | **Every interactable can be used from somewhere** - the host's line of sight is clear from at least one of twelve approaches | [A] `test_scene_integrity` |
| 26z1 | The host aims its check at the collision shape the player's ray hits, not the object's origin | [A] |
| 26z2 | **The temple is discovered by walking into the clearing, not by spawning** | [A] / [P] |
| 26z3 | **A player can step onto a low ledge** rather than stopping dead against it | [P] |
| 26z4 | A cliff edge is still a cliff edge - the step-up needs ground to land on | [A] |
| 26z5 | **A hovering enemy is never wedged by scenery** - the Warden and the crystal guard both were | [P] |
| 26z6 | Cinder's and Hallow's plateau can be climbed, so the temple can be reached at all | [P] |

## Crystal locks: coupling, guard and hazard

| # | Case | Cover |
|---|---|---|
| 26x | A sealed crystal cannot be taken while its lock stands | [A] `test_mission_rules` |
| 26y | The coupling occupies the same inventory slot as a crystal | [A] |
| 26z | Fitting the coupling at the socket unseals the cave crystal | [A] / [P] |
| 26aa | A guarded crystal opens only when its guard is down | [A] / [P] |
| 26aa1 | Nerava guards its ruins crystal, so the first mission has two locks and one plain fetch | [A] `test_mission_rules` |
| 26aa2 | **Two shots on a guard in the same frame do not crash or double-kill it** | [A] (idempotent death path) |
| 26aa3 | A crystal guard and the temple Sentinel can be alive at once | [A] |
| 26aa4 | The guard is sized to the crew, and is never a formality | [A] `test_mission_rules` |
| 26ab | A hazard-locked crystal opens only when the vent is sealed | [A] |
| 26ac | The hazard field damages a player standing in it, and stops when sealed | [A] |
| 26ad | Only the host applies hazard damage | [A] (host-authoritative by construction) |

## The Warden

| # | Case | Cover |
|---|---|---|
| 26ae | Taking the Star Map wakes the Warden exactly once | [A] / [P] |
| 26af | Shots do nothing while any shield node stands | [A] |
| 26ag | Downing all three nodes exposes the boss | [A] |
| 26ah | The boss enrages below the configured health fraction | [A] |
| 26ai | Killing the Warden clears the way to extraction | [A] / [P] |
| 26aj | A wipe during the fight fails the mission | [A] |
| 26ak | **The Warden is sized to the crew, so one player can finish the game** | [A] `test_mission_rules` / [P] |
| 26al | A player joining or leaving mid-fight does not resize the boss | [A] (crew recorded in the snapshot at spawn) |
| 26am | **The Warden holds the height it spawned at** - the hover offset was applied twice | [A] `test_combat_and_revive` |
| 26an | **A player on the ground can look up far enough to aim at it at its enraged stand-off** | [A] / [P] |
| 26ao | The enraged Warden's contact damage can actually reach a player it closes on | [A] |
| 26ap | **It holds station OUTSIDE that reach** - contact is a punishment, not an aura | [A] |
| 26aq | Enraging still brings it closer than the ring it trades fire from | [A] |
| 26ar | **The Warden cannot be wedged on temple geometry** - it hovers inside the colonnade | [P] |
| 26as | **Its contact damage is sized to the crew**, like its health and its volleys | [A] `test_mission_rules` |

## Nerava mission

| # | Case | Cover |
|---|---|---|
| 36 | Entering the clearing discovers the Temple | [A] `test_mission_flow` |
| 37 | Each crystal can be picked up | [A] / [N] |
| 38 | A crystal cannot be picked up twice | [A] / [N] |
| 39 | A player cannot carry two crystals | [A] |
| 40 | Two players cannot hold the same crystal | [A] / [N] |
| 41 | Crystal state replicates to every peer | [N] |
| 42 | A pedestal refuses the wrong crystal without consuming it | [A] |
| 43 | A pedestal accepts its matching crystal | [A] |
| 44 | A filled pedestal cannot be filled again | [A] |
| 45 | The altar opens only after all three correct placements | [A] |
| 45a | **The altar restores the crew when it activates** | [A] `test_combat_and_revive` |
| 45b | It does not quietly revive a downed player | [A] |
| 45c | The altar test stands the second player back up before the next test runs | [A] |
| 46 | The Star Map cannot be taken early | [A] / [N] |
| 47 | Star Map ownership replicates | [A] |
| 48 | The Star Map drops exactly once when the carrier is downed | [A] |
| 48a | The drop test starts from a carrier who is STANDING, so the down is a real transition | [A] |
| 49 | The Star Map drops when the carrier disconnects | [A] |
| 50 | A living player can recover a dropped Star Map | [A] |
| 51 | **Every objective is physically reachable** | [A] `test_level_reachability` |
| 52 | The playable area cannot be escaped | [A] |
| 53 | A replay resets every puzzle state | [A] `test_session_reset` x3 |

## Combat

| # | Case | Cover |
|---|---|---|
| 54 | The blaster fires | [A] |
| 55 | The host enforces the fire interval on its own clock | [A] |
| 56 | Heat rises per shot and cools over time | [A] |
| 57 | Overheating blocks firing until sufficiently cool | [A] |
| 58 | A shot from an implausible origin is refused | [A] |
| 59 | A shot with a stale epoch is refused | [A] |
| 60 | Exactly one Sentinel spawns | [A] |
| 61 | A repeated Star Map request cannot duplicate the Sentinel | [A] |
| 62 | The Sentinel targets the Star Map carrier, even when another player is nearer | [A] `test_sentinel` |
| 63 | The Sentinel retargets when the carrier goes down, and never targets a downed player | [A] |
| 64 | The Sentinel recovers rather than freezing when it makes no progress | [A] `test_sentinel` |
| 65 | A guardian projectile damages a player once, then despawns | [A] |
| 66 | Ten validated hits stagger the Sentinel for three seconds | [A] |
| 66b | A validated blaster shot registers exactly one hit | [A] |
| 66c | Hits during a stagger are ignored | [A] |
| 66d | A teammate in the line of fire takes no damage | [A] |
| 67 | The Sentinel and its projectiles are removed on reset | [A] |

## Health and revive

| # | Case | Cover |
|---|---|---|
| 68 | Damage is applied by the host only | [A] |
| 69 | Three 33-damage hits leave 1 HP; the fourth downs the player | [A] (see BAL-001) |
| 70 | Damage on an already-downed player does nothing | [A] |
| 71 | Solo: being downed fails the mission | [A] |
| 72 | Multiplayer: failure requires everyone downed | [A] |
| 73 | Revive starts when in range | [A] |
| 74 | Revive completes after three uninterrupted seconds | [A] |
| 75 | Revive cancels when the reviver moves too far | [A] |
| 76 | Revive cancels on loss of line of sight | [M] |
| 77 | Revive cancels when `E` is released | [M] |
| 78 | Revive cancels when the reviver is downed, and clears the target's bar | [A] |
| 79 | Revive cancels when the reviver disconnects | [M] |
| 80 | A revived player returns at exactly 40 health | [A] |
| 81 | A standing player cannot be revived | [A] |
| 82 | A player cannot revive themselves | [A] |
| 83 | Two revivers racing cannot double-revive | [M] (deterministic by construction) |

## Simultaneous requests

| # | Case | Cover |
|---|---|---|
| S1 | Three players request the same crystal in one frame; exactly one wins | [A] `test_concurrency` |
| S2 | The contested crystal leaves the world exactly once | [A] |
| S3 | Two revivers race on one downed player; the target is revived once | [A] |
| S4 | The revive tick loop survives the race and later revives still work | [A] |
| S5 | Three extraction requests in one frame extract once | [A] |
| S6 | A non-carrier standing at the pod cannot extract | [A] |

## Extraction and end states

| # | Case | Cover |
|---|---|---|
| 84 | Extraction fails without the Star Map | [A] |
| 85 | Extraction fails away from the pod | [A] |
| 86 | Extraction succeeds for a living carrier at the pod | [A] |
| 87 | A client cannot force victory | [A] (rules require carrier + state) |
| 88 | Victory replicates to every peer | [M] |
| 89 | Failure replicates to every peer | [M] |
| 90 | Return to lobby works | [A] |
| 91 | Retry works | [A] |
| 92 | A replay carries no stale state (x3) | [A] |
| 93 | No duplicate players, crystals, guardians, projectiles or HUDs after replay | [A] |
| 94 | A request from the previous session is rejected | [A] / [N] |

## Networking and security

| # | Case | Cover |
|---|---|---|
| 95 | Host plus one client | [N] |
| 96 | Two instances on one machine | [N] |
| 97 | Two physical LAN devices | [B] VERIFY-003 |
| 98 | Three players | [N] |
| 99 | Four players | [N] |
| 100 | Artificial latency | [B] VERIFY-004 |
| 101 | Repeated RPC spam is throttled | [A] `test_rate_limiter` / [N] |
| 102 | Sustained flooding disconnects the peer | [N] |
| 103 | An RPC from an unexpected sender is refused | [A] (guards) / [N] |
| 104 | An invalid object id is refused | [A] / [N] |
| 105 | An out-of-range interaction is refused | [A] / [N] |
| 106 | A blocked line of sight refuses an interaction | [M] |
| 107 | A forged session epoch is refused | [A] / [N] |
| 108 | An impossible teleport is corrected | [N] |
| 109 | A client disconnecting mid-mission is handled | [N] |
| 110 | A disconnecting carrier's crystal returns to the world | [N] |
| 111 | Host disconnect is handled cleanly by clients | [M] NET-017 |
| 112 | Rejoin is refused (documented behaviour, not a bug) | [N] (joins refused after start) |

## CI and export

| # | Case | Cover |
|---|---|---|
| 113 | Repository structure validation | [A] `tools/check_structure.sh` |
| 114 | Headless Godot validation | [A] |
| 115 | Unit tests | [A] |
| 116 | Integration tests | [A] |
| 116b | An engine error inside a passing test fails the run | [A] `tools/run_validation.sh`, gate verified by reintroducing a real defect |
| 117 | Logs are uploaded on failure | [M] (needs a real CI run) |
| 118 | Debug export | [M] |
| 119 | Release export | [A] verified locally, exit 0 + `PE32+` |
| 120 | The correct export preset is used | [A] |
| 121 | Export templates match the engine version | [A] (both pinned; asserted by the structure check) |
| 122 | The artifact contains the complete release folder | [M] (needs a real CI run) |
| 123 | **The Windows executable launches** | [B] VERIFY-001 |
| 124 | **An exported host accepts an exported client** | [B] VERIFY-001 |
| 125 | Firewall / UDP documentation is accurate | [M] |

---

## Visuals and first person

These are checked by rendering, not by reading: run
`tools/capture_screenshots.sh <godot>` and look at `captures/`.

- [x] Rooms are lit. A lamp above a floor produces a visible pool of light on
      it. (If this fails, suspect mesh winding before you touch any light:
      an inside-out mesh shows its unlit interior and reads as "too dark".)
- [x] Walls, floors, props and rocks read as solid objects with shaded faces,
      not as flat single-colour slabs.
- [x] The weapon is visible in the lower right, its shape readable against both
      a dark and a bright background, and it does not cover the crosshair.
- [x] Firing produces a flash at the barrel, and the flash lights what is near
      it. Both firing shots (`05-hub-firing`, `15-nerava-firing`) show it.
- [x] Each Power Crystal is visible from across its alcove and glows in its own
      colour.
- [x] The Sentinel reads as an armoured machine with a lit core, not a blob.

Each model is also checked alone, via `tools/render_models.sh`:

- [x] Every subject in `captures/models/` renders - an empty frame means the
      builder produced a mesh with no surfaces, not that the shot was framed
      badly.
- [x] The explorer reads as a person: head, shoulders, elbows, knees, feet.
- [x] The team colour is unmistakably a colour on all four players, including
      against the white suit under a bright light.
- [x] The blaster has a visible bore, a trigger inside a guard, and coil rings
      that are outside the shroud where they can be seen.
- [x] The Sentinel's sensor head clearly faces one way, so a player can tell
      whether it has seen them.
- [x] No two kinds of set dressing read as the same shape in different colours.

The sky, via `tools/preview_sky.sh`:

- [x] Stars vary in brightness AND colour, and crowd towards the galactic band.
- [x] The galactic band has a dust lane cutting through it, not just a gradient.
- [x] Each planet has a terminator - a lit side and an unlit side - rather than
      being uniformly bright.
- [x] The ringed giant's rings pass behind it, and cast a shadow on its disc.
- [ ] MANUAL: the sky holds up while the player turns, at a real frame rate.

The interface, via `tools/render_ui.sh`:

- [x] Every screen is styled - no raw Godot default controls anywhere.
- [x] The menus show the game's sky behind them, and panel text stays readable
      when the bright part of it drifts past.
- [x] The health bar is green when healthy and red when nearly down, so it can
      be read without reading the number.
- [x] The crosshair is centred, and visible against both dark and bright ground.
- [ ] MANUAL: the HUD is readable in motion, over a sunlit dune and in a cave.
- [ ] MANUAL: every button is reachable and operable by keyboard alone.
- [ ] MANUAL: head bob, sprint FOV and damage shake feel right in motion. A
      still frame cannot show this.
- [ ] MANUAL: the weapon's heat glow is readable at a glance while firing.
- [ ] MANUAL: on a machine with a Vulkan driver, the Forward+ renderer looks
      correct - all captures here are Compatibility.

## Manual pass, in order, when a desktop is available

1. Launch. Check the menu renders, the version label is right, and an invalid
   name is refused.
2. Host on 7000. Confirm the lobby shows you as HOST.
3. Launch a second instance, join `127.0.0.1`. Confirm both rosters agree.
4. Start. Confirm both peers spawn on the Starfarer's crew deck and see each
   other with nameplates.
5. Walk the whole deck: quarters and beds, mess, med bay, engineering, cargo.
   Confirm nothing blocks the spine and every station has standing room.
6. As the client, aim at the nav console — confirm the prompt says only the host
   sets a course, and pressing `E` does nothing.
7. As the host, set a course. Confirm the destination list shows Nerava unlocked
   and the other two locked, with a reason.
8. Complete the four pre-flight tasks between both players. Confirm the HUD
   checklist shrinks as each lands, and that a completed task cannot be redone.
9. Pull the launch lever with someone still standing. Confirm it refuses and
   names who is not seated.
10. Everyone sits. Confirm the seat holds you — hold forward and check you do
    not walk out of the chair — and that the view still swivels.
11. Pull the lever. Watch the launch: engine bells lit under burn, star streaks
    outside the windows in transit, then the landing. Confirm both peers see the
    same phase at the same moment.
12. Walk into the clearing; confirm the objective changes to the crystal hunt.
13. Try the sealed crystal. Confirm it refuses and says what is holding it.
14. Fetch the power coupling. Confirm it fills the same slot a crystal would,
    then fit it at the socket and confirm the crystal unseals.
15. Collect all three crystals across both players; confirm HUD inventory,
    wrong-pedestal refusals, and the altar opening on the third placement.
16. Take the Star Map. Confirm the Warden wakes once, that shots do nothing
    while its shield nodes stand, that downing all three exposes it, and that it
    changes behaviour when it enrages.
17. Let the carrier go down mid-fight. Confirm the map drops once, is visible,
    and can be recovered by the other player.
18. Revive the downed player. Confirm the three-second hold, the progress
    readout, cancellation on walking away, and the 40 health on completion.
19. Kill the Warden, then extract. Confirm the victory screen on both peers.
20. Return to the ship. Confirm the next planet is now unlocked at the nav
    console, and fly it. Confirm its hazard damages you until the vent is
    sealed, and that its guarded crystal needs the guard down.
21. Return to lobby, then replay a whole mission. Confirm nothing is stale.
22. Fail deliberately (let both players go down). Confirm the failure screen and
    that Retry produces a clean run.
23. Kill the host process. Confirm the client returns to the menu with a
    readable message.
24. Repeat 2-19 with an exported Windows build, on two machines, over a LAN.
