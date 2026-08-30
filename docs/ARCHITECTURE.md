# Architecture

## The one rule everything else follows

**The host decides. Everybody else asks.**

A client may say "I would like to pick up the ruins crystal". It may never say
"I picked up the ruins crystal". Every gameplay outcome is produced on the host
from the host's own state, and then replicated outward. If you find code that
takes a gameplay fact from a client, that is a bug, not a shortcut.

## Node layout

The whole application lives under one fixed tree. This is not cosmetic:
`MultiplayerSpawner` and `MultiplayerSynchronizer` address nodes by **path**, so
the path has to be identical on every peer.

```
/root/Main                          main.tscn / main.gd
  ├── SceneRoot                     SceneManager mounts the current scene here
  │     └── Stage                   ALWAYS named "Stage", whatever is loaded
  │           ├── EntityRoot        instanced from scenes/multiplayer/
  │           │     ├── EntitySpawner   (MultiplayerSpawner)
  │           │     └── Entities        (spawn target: players, Sentinel, ...)
  │           ├── NavigationRegion3D    (Nerava only)
  │           ├── Interactables         authored, stable object ids
  │           └── PlayerSpawnPoints
  └── UILayer                       CanvasLayer, OUTSIDE the swapped scene
        └── UIRoot
              ├── HudSlot           exactly one HUD instance, ever
              ├── OverlaySlot       pause / victory / failure
              └── ToastSlot
```

Two deliberate choices:

* **The mount point is always called `Stage`.** Naming it after the level would
  make every replicated path level-dependent. Changing this name is a wire
  protocol change and requires bumping `GameConfig.PROTOCOL_VERSION`.
* **The HUD lives outside `SceneRoot`.** If it lived inside a level it would be
  destroyed and rebuilt on every transition, and a failed transition could leave
  two HUDs alive at once.

## Autoloads and what each one owns

| Autoload | Owns | Must not own |
|---|---|---|
| `GameConfig` | Every tunable number and shared identifier | Any state |
| `Logx` | Levelled logging, rejection log lines | Anything gameplay |
| `SettingsManager` | Local per-machine preferences | Anything that affects an outcome |
| `NetworkManager` | The ENet peer, the join handshake, peer lifecycle | Missions, scenes, crystals |
| `LobbyManager` | The authoritative player roster | Mission state |
| `SceneManager` | What is on screen; the scene readiness barrier | Mission rules |
| `GameManager` | Mission state, the session epoch, authoritative outcomes | Sockets, scene loading details |
| `SpawnManager` | World-object identity, authority spawning, cleanup | Rules |
| `AudioDirector` | Named audio cues | Anything else |

`MissionRules` is deliberately **not** an autoload. It is a pure static class
with no nodes, no tree and no networking, which is what makes every
security-relevant decision directly unit-testable.

## The authority model in practice

### Two synchronizers on the player

A player node carries two `MultiplayerSynchronizer` children with *different*
authorities:

| Synchronizer | Authority | Carries | Why |
|---|---|---|---|
| `MotionSync` | the owning client | `sync_position`, `sync_yaw`, `sync_flags` | Local input drives local motion, so movement feels immediate. |
| `StateSync` | the host (peer 1) | `health`, `is_downed`, `is_alive`, `revive_progress`, `revive_active`, `heat`, `overheated` | A client cannot heal itself, un-down itself, or cool its own weapon. |

Movement being client-driven is a **presentation** decision, not a permission.
The host samples each client's position and rejects the physically impossible
(`GameConfig.max_plausible_travel`), correcting the player after three
consecutive violations.

Two consequences that are easy to get wrong, and are commented in the code:

* Gameplay range checks read `authoritative_position()` - the raw replicated
  value - not the smoothed visual transform. Otherwise interaction range would
  depend on interpolation.
* A player node's multiplayer authority is the **client**, so `@rpc("authority")`
  on that node means "only that client may call it". Host-originated RPCs on a
  player are therefore declared `any_peer` and gated on the sender being peer 1.
  Getting this wrong produces `RPC ... is not allowed on node ...` and silently
  drops the host's own corrections.

### RPC categories

| Direction | Declaration | Guard |
|---|---|---|
| client -> host request | `@rpc("any_peer", "call_remote", "reliable")` | First line proves `multiplayer.is_server()`; then sender identity, rate limit, epoch and rules |
| host -> all, on a host-authority node | `@rpc("authority", ...)` | Godot enforces it |
| host -> client, on a client-authority node | `@rpc("any_peer", ...)` | Explicit `_from_host()` check |
| cosmetic broadcast | `unreliable` | Carries no gameplay meaning |

## Object identity

There are two kinds of world object, and they get their identity differently.

**Authored interactables** (mission terminal, crystals, pedestals, altar, drop
pod) carry a hand-written `object_id` baked into the level scene. They exist
identically on every peer the instant the level mounts, so no negotiation is
needed and a client can name one directly. `tests/integration/test_scene_integrity.gd`
fails the build if two of them collide.

**Spawned entities** (players, the Sentinel, its projectiles, a dropped Star
Map) are created by the host through the level's `MultiplayerSpawner` with a
host-assigned id inside the spawn payload. A client cannot ask for one.

Either way the host re-checks, on every request, that the named object exists in
*its* registry, in the current scene, in the current session.

### A registry-ordering trap worth remembering

Godot runs `_ready()` **bottom-up**. Every interactable in a level has already
registered itself by the time the level root's `_ready()` runs. The registry is
therefore cleared in `SpawnManager.unbind_level()` - called from the *outgoing*
level's `_exit_tree()` - and never in `bind_level()`. Clearing it in
`bind_level()` erased the whole level's interactables and made every interaction
fail as "unknown object".

## The session epoch

`GameManager.session_epoch` increments on every fresh lobby, hub entry, descent,
retry and return to lobby. Every critical client request carries the epoch it
was made under, and the host rejects anything that is not current.

That single mechanism kills, in one place:

* requests from a mission that already ended,
* requests aimed at a scene that has been unloaded,
* replayed or crafted packets from an earlier session,
* a click that was in flight when the host pressed Retry.

## The scene readiness barrier

1. The host picks a new `transition_id` and broadcasts the target scene.
2. Every peer, host included, mounts the scene at `SceneRoot/Stage` and then
   acknowledges with the transition id **and** the session epoch.
3. The host completes the barrier when all expected peers have acknowledged, or
   after `GameConfig.SCENE_TRANSITION_TIMEOUT`, at which point peers that never
   answered are disconnected with a readable reason rather than being left in an
   inconsistent world.
4. Only then does the host spawn players.

A peer that drops mid-barrier is removed from the expected set immediately, so
the barrier does not sit waiting for the full timeout on somebody who has gone.

Mounting is a custom swap rather than `change_scene_to_file()` because the
barrier needs an exact "the new scene is fully live" moment, and because the
mount point name has to be fixed.

`GameLevel.await_scene_ready()` is awaited before a peer acknowledges. On the
host that includes waiting for the navigation mesh to become genuinely
*queryable* - see the `NavUtil` note below.

## Lifecycles

**Player** - spawned by the host after the barrier -> authority split applied in
`_enter_tree()` -> registered with `SpawnManager` -> despawned on disconnect, on
`host_clear_all()`, or with the level.

**Crystal** - the node always exists in the level; whether it is collectable is
decided solely by the snapshot. That is what makes replay clean: resetting the
snapshot restores every crystal with no respawn logic at all.

**Star Map** - `locked` -> `available` (altar opens) -> `carried` -> optionally
`dropped` (carrier downed or disconnected) -> `carried` again -> `extracted`.
While it sits on the altar it is part of the authored altar node. Only a
*dropped* map is a spawned entity, because only then does it need a position the
level author did not choose. The drop is guarded by the map's **state**, not by
the caller, so repeated damage or repeated downed events cannot duplicate it.

**Sentinel** - spawned exactly once per descent, when the Star Map is first
taken, guarded by `snapshot.guardian_spawned` *and* a group check. Removed on
victory, failure, retry, return to lobby and host shutdown.

## Failure, retry and replay

Failure requires that at least one player exists and every remaining connected
player is downed. A player who disconnected is simply absent from the check, so
a disconnect can never wedge it in either direction.

`GameManager._host_reset_facts()` is the single choke point that wipes every
mission fact while keeping the current state, so the caller can then make one
validated transition out of it. There is no path that resets some facts and
forgets others. `tests/integration/test_session_reset.gd` replays the mission
three times and asserts the slate is clean each time, including that the number
of player nodes still matches the roster (no duplicates) and that the
interactable registry holds exactly the eight authored Nerava objects.

## Disconnect behaviour

**A client drops.** The host drops its carried Star Map into the world, returns
its carried crystal to the world (otherwise the mission becomes unwinnable),
cancels revives in both directions, despawns its player, removes it from the
roster and re-evaluates the failure condition.

**The host drops.** Host migration is not supported. Every client receives a
clear "The host ended the session" message, returns to the main menu, and the
in-progress session is discarded. No client is promoted.

## A navigation trap worth remembering

The common recipe for "wait until navigation is ready" is `await
get_tree().physics_frame`, or the slightly better "wait until
`map_get_iteration_id() > 0`". Both are wrong once a level can be entered more
than once: the iteration id belongs to the **map**, not the region, and it is
already non-zero from the previous visit. The check passes instantly while the
freshly baked mesh has not been committed, and the first path query silently
returns nothing.

`NavUtil.is_map_usable()` asks the map a real question instead - does it hold a
region, and can it actually produce a path near the point we care about. Both
the Sentinel and `GameLevel` use it.

## Testing architecture

| Layer | Location | What it can prove |
|---|---|---|
| Compile | `tests/run_tests.gd` phase 1 | Every script compiles **with autoloads live** - `--check-only --script` cannot do this, and `load()` returns a non-null but invalid script for a broken file, so `can_instantiate()` is checked |
| Scenes | phase 2 | Every scene loads *and instantiates* |
| Unit | `tests/unit/` | Pure rules, name hygiene, rate limiting, the state machine |
| Integration | `tests/integration/` | A real ENet host session driven through a whole mission, combat, revive, replay, and navmesh reachability |
| Multi-process | `tests/net_probe.gd` + `tools/run_multiplayer_check.sh` | The **client** half of the protocol, across real OS processes |

The multi-process check is the only thing that exercises client-side RPC
declarations, the barrier as seen by a client, and the host's rejection of
hostile client requests. Everything in `tests/integration/` runs host-side in
one process.
