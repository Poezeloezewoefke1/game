# Test checklist

Legend: **[A]** covered by an automated test · **[N]** covered by the
multi-process multiplayer check · **[M]** manual, needs a human at a screen ·
**[B]** blocked in the current environment.

Run the automated layers with:

```bash
godot --headless --path . res://tests/test_runner.tscn
tools/run_multiplayer_check.sh /path/to/godot 7700 3
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

## Hub and transition

| # | Case | Cover |
|---|---|---|
| 26 | All players spawn in the hub | [A] / [N] |
| 27 | Nameplates appear above other players | [M] |
| 28 | Player movement replicates between peers | [N] (position-driven pickups prove it) |
| 29 | The host can use the Mission Terminal | [A] / [N] |
| 30 | A client cannot use the Mission Terminal | [N] |
| 31 | An out-of-range terminal request is refused | [A] |
| 32 | The readiness barrier waits for every peer | [N] |
| 33 | A peer that never acknowledges is disconnected on timeout | [M] |
| 34 | A stale transition acknowledgement is ignored | [A] (epoch/transition id checks) |
| 35 | Every ready client reaches Nerava | [N] |

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
| 46 | The Star Map cannot be taken early | [A] / [N] |
| 47 | Star Map ownership replicates | [A] |
| 48 | The Star Map drops exactly once when the carrier is downed | [A] |
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
| 62 | The Sentinel targets the Star Map carrier | [M] |
| 63 | The Sentinel retargets when the carrier goes down | [M] |
| 64 | The Sentinel recovers rather than freezing when it has no path | [M] |
| 65 | A guardian projectile damages a player once, then despawns | [M] |
| 66 | Ten validated hits stagger the Sentinel for three seconds | [M] |
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
| 78 | Revive cancels when the reviver is downed | [M] |
| 79 | Revive cancels when the reviver disconnects | [M] |
| 80 | A revived player returns at exactly 40 health | [A] |
| 81 | A standing player cannot be revived | [A] |
| 82 | A player cannot revive themselves | [A] |
| 83 | Two revivers racing cannot double-revive | [M] (deterministic by construction) |

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

## Manual pass, in order, when a desktop is available

1. Launch. Check the menu renders, the version label is right, and an invalid
   name is refused.
2. Host on 7000. Confirm the lobby shows you as HOST.
3. Launch a second instance, join `127.0.0.1`. Confirm both rosters agree.
4. Start the mission. Confirm both peers reach the hub and see two players with
   nameplates.
5. As the client, aim at the terminal — confirm the prompt says only the host
   can start it, and pressing `E` does nothing.
6. As the host, start the expedition. Confirm both reach Nerava.
7. Walk into the clearing; confirm the objective changes to the crystal hunt.
8. Collect all three crystals across both players; confirm HUD inventory,
   wrong-pedestal refusals, and the altar opening on the third placement.
9. Take the Star Map. Confirm the Sentinel spawns once, chases the carrier, and
   staggers after ten hits.
10. Let the carrier go down. Confirm the map drops once, is visible, and can be
    recovered by the other player.
11. Revive the downed player. Confirm the three-second hold, the progress
    readout, cancellation on walking away, and the 40 health on completion.
12. Extract. Confirm the victory screen on both peers.
13. Return to lobby, then replay the whole mission. Confirm nothing is stale.
14. Fail deliberately (let both players go down). Confirm the failure screen and
    that Retry produces a clean run.
15. Kill the host process. Confirm the client returns to the menu with a
    readable message.
16. Repeat 2-12 with an exported Windows build, on two machines, over a LAN.
