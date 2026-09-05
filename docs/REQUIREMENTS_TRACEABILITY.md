# Requirements traceability

Every meaningful requirement, where it is implemented, how it is verified, and
its honest status.

## Status vocabulary

| Status | Meaning |
|---|---|
| **AUTO** | An automated test asserts it and that test passes |
| **NET** | The multi-process multiplayer check asserts it across real OS processes |
| **STATIC** | Implemented and reviewed by reading; no test exercises it |
| **MANUAL** | Requires a human at a screen; listed in `docs/TEST_CHECKLIST.md` |
| **PLAY** | The automated playtest reaches it by driving the shipped build with simulated keyboard and mouse |
| **BLOCKED** | Cannot be verified in this environment |

Test files are referenced by name; `runner` means `tests/run_tests.gd`.

---

## Networking and session (NET)

| ID | Requirement | Implementation | Verification | Status |
|---|---|---|---|---|
| NET-001 | Host is authoritative for Crystal pickup | `game_manager.gd:host_apply_crystal_pickup`, `power_crystal.gd` | `test_mission_rules`, `test_mission_flow`, net probe | AUTO + NET |
| NET-002 | Clients may request, never decide | every `_rpc_*` handler begins with a host check | `test_mission_flow`, net probe | AUTO + NET |
| NET-003 | Join handshake validates protocol version | `network_manager.gd:_rpc_register` | net probe (matching versions only) | NET (partial) |
| NET-004 | Session capped at 4 players | `network_manager.gd`, `lobby_manager.gd:is_full` | net probe: `the lobby is full at the player cap` | NET |
| NET-005 | Fifth player refused with a readable reason | `network_manager.gd:_reject_peer` + `KICK_FLUSH_DELAY` | net probe: `the rejection names the real cause` | NET |
| NET-006 | A connected socket is not a player until it registers | `_pending_handshake` + timeout | STATIC | STATIC |
| NET-007 | Stale-epoch requests rejected | `session_epoch` on every request | `test_session_reset`, net probe: forged epoch | AUTO + NET |
| NET-008 | Unknown object ids rejected | `spawn_manager.gd:find_interactable` | `test_mission_flow`, net probe | AUTO + NET |
| NET-009 | Host re-checks interaction range | `game_manager.gd:_host_within_reach` | `test_mission_flow`, net probe: out-of-range pickup | AUTO + NET |
| NET-010 | Validation range exceeds prompt range only enough to absorb latency | `GameConfig.INTERACT_VALIDATE_DISTANCE` (5.0) vs `INTERACT_DISTANCE` (3.2) | STATIC + `docs/NETWORK_RULES.md` | STATIC |
| NET-011 | Host re-checks line of sight | `game_manager.gd:_host_clear_line` | STATIC | STATIC |
| NET-012 | Per-peer, per-channel rate limiting | `rate_limiter.gd`, used in 5 places | `test_rate_limiter` | AUTO |
| NET-013 | Sustained flooding disconnects the peer | `RateLimiter.is_abusive` -> `host_kick_peer` | net probe: flooding gets disconnected | NET |
| NET-014 | Kicking is idempotent | `network_manager.gd:_kicking` | net probe (no ENet channel errors) | NET |
| NET-015 | No RPC is sent to a departed peer | `network_manager.gd:is_peer_connected` | `test_combat_and_revive` (no engine errors) | AUTO |
| NET-016 | Host->client RPCs on a client-authority node verify the sender | `player.gd:_from_host` | net probe: anti-teleport correction lands | NET |
| NET-017 | Host disconnect ends the session cleanly for all clients | `network_manager.gd:_on_server_disconnected` | MANUAL | MANUAL |
| NET-018 | Client disconnect drops the Star Map into the world | `game_manager.gd:host_handle_peer_left` | `test_combat_and_revive` | AUTO |
| NET-019 | Client disconnect returns a carried crystal (no softlock) | `game_manager.gd:host_handle_peer_left` | net probe: `a disconnected carrier's crystal returns` | NET |
| NET-020 | Impossible movement is detected and corrected | `player.gd:_host_check_impossible_movement` | net probe: 180 m teleport corrected | NET |
| NET-021 | Movement correction re-baselines on respawn | `player.gd:host_full_reset` | STATIC | STATIC |

## LAN discovery and join codes (LAN / CODE)

| ID | Requirement | Implementation | Verification | Status |
|---|---|---|---|---|
| LAN-001 | The host announces a named session on the local network | `lan_discovery.gd:host_start_announcing` | `test_lan_discovery`, net probe | AUTO + NET |
| LAN-002 | A client discovers announced sessions and can join without typing an address | `lan_discovery.gd`, `main_menu.gd` | `test_lan_discovery`, net probe (cross-process) | AUTO + NET |
| LAN-003 | The advertised address comes from the UDP source, never the packet body | `_absorb` uses `get_packet_ip()` | `test_lan_discovery` (injected packet attributed to its real sender) | AUTO |
| LAN-004 | Malformed announcements are ignored | `_absorb` validates every field | `test_lan_discovery` (9 malformed shapes) | AUTO |
| LAN-005 | Oversized packets are discarded unread | `DISCOVERY_MAX_PACKET_BYTES` | `test_lan_discovery` | AUTO |
| LAN-006 | The browser cannot be flooded without bound | `DISCOVERY_MAX_SESSIONS` | `test_lan_discovery` (64 injected, capped at 32) | AUTO |
| LAN-007 | A separator inside a display name cannot shift other fields | name sent last, split limit | `test_lan_discovery` | AUTO |
| LAN-008 | A host that stops announcing leaves the browser | `_expire` | `test_lan_discovery` | AUTO |
| LAN-009 | Session names are sanitised before display | `sanitize_session_name` | `test_join_code` | AUTO |
| LAN-010 | A busy discovery port is reported, not silently empty | `listen_error`, `main_menu.gd` | STATIC + net probe SKIP path | STATIC |
| LAN-011 | Discovery does not use the game's port | `DISCOVERY_PORT` 7001 vs 7000 | `test_lan_discovery` | AUTO |
| CODE-001 | A code round-trips to the same address and port | `join_code.gd` | `test_join_code` | AUTO |
| CODE-002 | Default-port codes are 8 characters, custom-port 11 | length disambiguates the two forms | `test_join_code` | AUTO |
| CODE-003 | No single-character typo silently resolves to the original host | position-weighted checksum | `test_join_code` (exhaustive sweep) | AUTO |
| CODE-004 | No transposition silently resolves to the original host | position weighting | `test_join_code` (exhaustive sweep) | AUTO |
| CODE-005 | Confusable letters (I, L, O, U) are folded on decode | `_normalise` | `test_join_code` | AUTO |
| CODE-006 | Case and separators are forgiven | `_normalise` | `test_join_code` | AUTO |
| CODE-007 | Invalid input is rejected with a readable reason | `decode` returns `reason` | `test_join_code` | AUTO |
| CODE-008 | The join field accepts either a code or an address | `looks_like_code`, `main_menu.gd` | `test_join_code`; UI path STATIC | AUTO (rule) |
| CODE-009 | A code built from a private address is labelled local-only | `is_private_address`, `lobby.gd` | `test_join_code` (rule); label STATIC | AUTO (rule) |
| CODE-010 | A code never claims to make an unreachable host reachable | lobby wording, README, NETWORK_RULES | STATIC | STATIC |

## Scene transitions (SCN)

| ID | Requirement | Implementation | Verification | Status |
|---|---|---|---|---|
| SCN-001 | Every scene mounts at a fixed replicated path | `scene_manager.gd:STAGE_NODE_NAME` | `test_mission_flow` | AUTO |
| SCN-002 | Host broadcasts, all peers ack, then the barrier releases | `scene_manager.gd` | net probe: both barriers release | NET |
| SCN-003 | Acks carry transition id and epoch; stale acks rejected | `_rpc_scene_ready` | STATIC | STATIC |
| SCN-004 | Barrier timeout disconnects late peers rather than continuing broken | `_timeout_barrier` | STATIC | STATIC |
| SCN-005 | A peer dropping mid-barrier does not stall it | `host_handle_peer_left` | STATIC | STATIC |
| SCN-006 | Players spawn only after the barrier completes | `host_on_scene_barrier_completed` | `test_mission_flow`, net probe | AUTO + NET |
| SCN-007 | Despawns flush before the next scene is announced | `spawn_manager.gd:host_clear_all` (awaited) | net probe (no `on_despawn_receive` errors) | NET |
| SCN-008 | A client cannot trigger a transition | `_rpc_load_scene` is `authority` | net probe: client terminal request refused | NET |

## Gameplay (GAME)

| ID | Requirement | Implementation | Verification | Status |
|---|---|---|---|---|
| GAME-001 | Mission states match the specified enum | `mission_rules.gd:MissionState` | `test_state_machine` | AUTO |
| GAME-002 | Objective text matches the specified strings exactly | `mission_rules.gd:OBJECTIVE_TEXT` | `test_state_machine` | AUTO |
| GAME-003 | Illegal state transitions are refused | `is_valid_transition` + `_host_set_state` | `test_state_machine` | AUTO |
| GAME-010 | Only the host can start the expedition | `can_start_expedition`, `mission_terminal.gd` | `test_mission_rules`, net probe | AUTO + NET |
| GAME-011 | Temple discovery advances the objective | `temple_trigger.gd` | `test_mission_flow` | AUTO |
| GAME-012 | Three distinct crystals exist and are collectable | Nerava scene, `power_crystal.gd` | `test_scene_integrity`, `test_mission_flow` | AUTO |
| GAME-013 | A crystal cannot be picked up twice or duplicated | `can_pick_up_crystal` | `test_mission_rules`, `test_mission_flow`, net probe | AUTO + NET |
| GAME-014 | A player cannot carry more than one Power Crystal | `can_pick_up_crystal` -> `inventory_full` | `test_mission_rules` | AUTO |
| GAME-015 | Two peers cannot hold the same crystal | `crystal_already_carried` guard | `test_mission_rules`, net probe | AUTO + NET |
| GAME-016 | A pedestal accepts only its matching crystal | `can_place_crystal` | `test_mission_rules`, `test_mission_flow` | AUTO |
| GAME-017 | A rejected placement does not consume the crystal | rules return before mutating | `test_mission_flow` | AUTO |
| GAME-018 | A pedestal cannot activate twice | `pedestal_already_active` | `test_mission_rules`, `test_mission_flow` | AUTO |
| GAME-019 | The altar opens only on three distinct correct placements | `altar_should_activate` | `test_mission_rules` | AUTO |
| GAME-020 | The Star Map cannot be taken before the altar opens | `can_take_star_map` -> `shield_active` | `test_mission_rules`, net probe | AUTO + NET |
| GAME-021 | Only one Star Map exists per session | snapshot state machine | `test_mission_flow` | AUTO |
| GAME-022 | The Star Map drops exactly once when the carrier is downed | `_host_drop_star_map` guarded by state | `test_combat_and_revive` | AUTO |
| GAME-023 | A living player can recover a dropped Star Map | `dropped_star_map.gd` | `test_combat_and_revive` | AUTO |
| GAME-024 | Extraction requires a living carrier at the pod | `can_extract` | `test_mission_rules`, `test_mission_flow` | AUTO |
| GAME-025 | Victory is reachable | full flow | `test_mission_flow` | AUTO |
| GAME-026 | Failure requires every connected player downed | `should_fail` | `test_mission_rules`, `test_combat_and_revive` | AUTO |
| GAME-027 | A disconnect cannot wedge the failure check | `should_fail` over connected players only | `test_mission_rules` | AUTO |
| GAME-028 | Replay restores every mission fact | `_host_reset_facts` | `test_session_reset` (x3) | AUTO |
| GAME-029 | Replay leaves no stale entity and no duplicate player | `host_clear_all` | `test_session_reset` | AUTO |
| GAME-030 | Return to lobby clears players, entities and the registry | `host_return_to_lobby` | `test_session_reset` | AUTO |
| GAME-031 | Two players grabbing one crystal: exactly one wins | `can_pick_up_crystal` applied atomically on the host | `test_concurrency` | AUTO |
| GAME-032 | Duplicate extraction requests extract exactly once | `can_extract` + state | `test_concurrency` | AUTO |
| GAME-033 | A non-carrier at the pod cannot extract | `can_extract` | `test_concurrency` | AUTO |

## Player (PLR)

| ID | Requirement | Implementation | Verification | Status |
|---|---|---|---|---|
| PLR-001 | ~~Third-person CharacterBody3D with spring-arm camera~~ **First-person camera at eye height, no spring arm** — changed on the owner's instruction ("make the game like first person"), superseding the original brief | `player.tscn`, `player.gd`, `view_model.gd`, `player_body.gd` | `test_app_shell :: first person` | AUTO (structure) / MANUAL (feel) |
| PLR-006 | A viewmodel weapon whose glow reports blaster heat | `view_model.gd` | `test_app_shell :: first person` | AUTO (present) / MANUAL (readability) |
| PLR-007 | Muzzle flash on every shot the host confirms, for the shooter and for everyone watching | `muzzle_flash.gd`, `player.gd::_rpc_tracer` | `test_app_shell :: first person` | AUTO |
| ART-001 | Models built from procedural geometry, no downloaded or paid assets | `mesh_factory.gd`, `model_kit.gd`, `prop_builder.gd`, `prop_scatter.gd` | `test_mesh_factory` (71 assertions) | AUTO |
| ART-002 | Generated geometry must match Godot's clockwise front-face winding | `mesh_factory.gd::_add_polygon` | `test_mesh_factory :: test_matches_godots_own_winding` | AUTO (read back off Godot's own primitives) |
| ART-003 | No builder may return an empty mesh, at any scale | `mesh_factory.gd::_add_polygon`, `_commit` | `test_mesh_factory :: test_small_shapes_are_not_silently_empty` | AUTO |
| ART-004 | Hollow shapes must actually be hollow | `mesh_factory.gd::tube` | `test_mesh_factory :: test_a_hollow_shape_really_is_hollow` | AUTO |
| ART-005 | Every model is inspectable alone, not only in situ | `tools/model_gallery.gd`, `tools/render_models.sh` | `captures/models/` (13 images) | MANUAL (visual) |
| ART-006 | A detailed sky with stars and planets — owner request, 2026-09-02 | `shaders/deep_space_sky.gdshader`, `resources/sky_*.tres` | `captures/sky/` (6 images) | MANUAL (visual) |
| ART-007 | Real photographs must be droppable in without code changes | `deep_space_sky.gdshader` `planetN_photo` / `planetN_use_photo` | `docs/ASSET_PROVENANCE.md` | MANUAL |
| ART-008 | Proper textures on level geometry — owner request | `tools/generate_textures.gd`, `shaders/surface.gdshader`, `world_block.gd` | `captures/` screenshots | MANUAL (visual) |
| ART-009 | The map must be filled with detail rather than empty — owner request | `scripts/utility/set_dressing.gd`, 56 placements across two levels | `test_level_reachability :: corridors clear` | AUTO (clearance) / MANUAL (visual) |
| ART-010 | Set dressing must never block an objective | dressing parented inside `NavigationRegion3D` | `test_level_reachability`, `run_multiplayer_check.sh` | AUTO |
| UI-010 | One consistent visual identity across every screen | `resources/ui_theme.tres` as the project default theme | `captures/ui/` (6 images) | MANUAL (visual) |
| UI-011 | Menus must look like the game, not like a settings dialog | `scripts/ui/sky_backdrop.gd` | `captures/ui/01-main-menu.png` | MANUAL (visual) |
| UI-012 | Health and heat must be readable without reading the numbers | `hud.gd::_tint_health`, `_tint_heat` | `captures/ui/03-hud.png` | MANUAL (visual) |
| PLR-002 | Walk, sprint, jump, mouse look, pitch clamp | `player.gd:_local_physics`, `_unhandled_input` | MANUAL | MANUAL |
| PLR-003 | Remote players are smoothed, and snapped on large jumps | `_remote_physics` | STATIC | STATIC |
| PLR-004 | Host authority over health | `StateSync` authority = 1 | `test_combat_and_revive` | AUTO |
| PLR-005 | Zero health causes the downed state | `host_apply_damage` | `test_combat_and_revive` | AUTO |
| PLR-006 | A downed player cannot act | `MissionRules.actor_can_act` | `test_mission_rules` | AUTO |
| PLR-007 | Revive takes an uninterrupted 3 s and restores 40 health | `_host_tick_revives`, `host_revive` | `test_combat_and_revive` | AUTO |
| PLR-008 | Revive cancels on distance, line of sight, release, downed reviver or disconnect | `_host_revive_pair_valid` | `test_combat_and_revive` (distance, downed reviver, not-downed target, self) | AUTO (partial - line of sight and release are MANUAL) |
| PLR-009 | Revive races resolve deterministically, and the tick loop survives | first to finish wins; others cancelled; the key snapshot is re-checked | `test_concurrency` | AUTO |
| PLR-010 | Display names are sanitised and never used as identity | `name_sanitizer.gd` | `test_name_sanitizer` | AUTO |
| PLR-011 | Revive progress does not cost 60 reliable packets/second | replicated via `StateSync` | STATIC | STATIC |
| PLR-012 | Cancelling a revive always clears the target's revive bar | every path routes through `host_handle_revive_stop` | `test_combat_and_revive` | AUTO |

## Blaster and Sentinel (AI / WPN)

| ID | Requirement | Implementation | Verification | Status |
|---|---|---|---|---|
| WPN-001 | The blaster uses heat, not ammunition | `GameConfig` + `player.gd` | `test_combat_and_revive` | AUTO |
| WPN-002 | The host validates fire cadence on its own clock | `_host_next_fire_ms` | `test_combat_and_revive` | AUTO |
| WPN-003 | The host validates heat and overheat | `host_process_fire_request` | `test_combat_and_revive` | AUTO |
| WPN-004 | A shot must originate at the shooter | origin-vs-position check | `test_combat_and_revive` | AUTO |
| WPN-005 | Clients cannot spawn authoritative projectiles | player fire is host-resolved hitscan; the tracer is cosmetic | STATIC | STATIC |
| WPN-006 | The blaster cannot hurt teammates | no player damage path from a blaster shot | `test_combat_and_revive` (shot straight through a teammate) | AUTO |
| AI-001 | Exactly one Sentinel spawns, when the Star Map is first taken | `host_apply_star_map_pickup` + group check | `test_mission_flow` | AUTO |
| AI-002 | A repeated Star Map request cannot duplicate the Sentinel | same | `test_mission_flow` | AUTO |
| AI-003 | The Sentinel targets the carrier, else the nearest living player | `_host_select_target` | `test_sentinel` (the carrier is deliberately the *farther* player) | AUTO |
| AI-004 | Navigation is not reset every frame | `GUARDIAN_REPATH_INTERVAL` + movement delta | STATIC | STATIC |
| AI-005 | Navigation queries wait until the map can genuinely answer | `nav_util.gd` | `test_level_reachability`, `test_sentinel` | AUTO |
| AI-006 | No path / stuck is recovered, not frozen | `_host_track_stuck` | `test_sentinel` (pinned in place, recovers after the configured time) | AUTO |
| AI-007 | The Sentinel retargets when the carrier is downed or leaves | `_host_select_target` re-evaluated each tick | `test_sentinel` | AUTO |
| AI-008 | Ten host-validated hits cause a 3 s stagger, and hits during it are ignored | `host_register_hit` | `test_sentinel` | AUTO |
| AI-009 | Guardian projectiles damage a player once and despawn | `guardian_projectile.gd` (swept sphere test) | `test_sentinel` | AUTO |
| AI-010 | Projectiles cannot survive a reset | `GROUP_SESSION_BOUND` + `host_clear_all` | `test_session_reset` | AUTO |

## Levels (LVL)

| ID | Requirement | Implementation | Verification | Status |
|---|---|---|---|---|
| LVL-001 | The Hub has four spawn points and a Mission Terminal | `wayfinder_hub.tscn` | `test_scene_integrity` | AUTO |
| LVL-002 | Nerava has a drop pod, canyon, temple, three paths, three crystals, three pedestals, altar | `nerava_landing_zone.tscn` | `test_scene_integrity` | AUTO |
| LVL-003 | Every object id in a level is unique | authored | `test_scene_integrity` | AUTO |
| LVL-004 | Every interactable implements the full contract | `interactable_base.gd` | `test_scene_integrity` | AUTO |
| LVL-005 | **Every objective is physically reachable** | Nerava geometry | `test_level_reachability` (navmesh paths) | AUTO |
| LVL-006 | The playable area is enclosed | boundary blocks | `test_level_reachability` (outward paths stop short) | AUTO |
| LVL-007 | Nerava has a valid, bakeable navigation mesh | `NavigationRegion3D` | `test_level_reachability` | AUTO |

## UI

| ID | Requirement | Implementation | Verification | Status |
|---|---|---|---|---|
| UI-001 | Main menu: title, subtitle, name, host, join, IP, port, settings, quit, version, errors | `main_menu.tscn/.gd` | runner phase 2 | AUTO (structure) / MANUAL (layout) |
| UI-002 | Lobby: roster, host indicator, readiness, start, leave, status, capacity | `lobby.tscn/.gd` | runner phase 2 | AUTO (structure) / MANUAL |
| UI-003 | HUD: crosshair, objective, prompt, health, heat, crystal, Star Map, carrier, team, downed, revive | `hud.tscn/.gd` | runner phase 2 | AUTO (structure) / MANUAL |
| UI-004 | Pause, victory and failure screens | `pause_menu`, `end_screen` | runner phase 2 | AUTO (structure) / MANUAL |
| UI-005 | Exactly one HUD instance can exist | mounted in `UIRoot`, outside the swapped scene | `test_app_shell` (mounted in a level, removed on leaving) | AUTO |
| UI-008 | **Entering a gameplay scene captures the mouse, so the player can move** | `ui_root.gd:_process` | `test_app_shell` - gate verified by reintroducing the defect | AUTO |
| UI-009 | Opening an overlay releases the mouse; closing recaptures it | `ui_root.gd:_process` | `test_app_shell` | AUTO |
| UI-010 | Mouse mode has exactly one writer | `ui_root.gd` | `grep` in review; four writers reduced to one | STATIC |
| UI-011 | A scene mount abandoned by teardown does not touch a freed node | `scene_manager.gd:_mount_still_valid` | `test_app_shell` (engine-error gate) | AUTO |
| UI-006 | UI never owns authoritative state | all UI reads `GameManager` | STATIC | STATIC |
| UI-007 | Interaction prompts match the specified wording | interactable `get_interaction_prompt` | STATIC | STATIC |

## Build and CI (BUILD)

| ID | Requirement | Implementation | Verification | Status |
|---|---|---|---|---|
| BUILD-001 | The engine version is pinned identically everywhere | workflows + `docs/TECH_STACK.md` | `tools/check_structure.sh` | AUTO |
| BUILD-002 | Validation runs on push, PR and manual dispatch | `validate.yml` | valid YAML; asserted by the structure check | STATIC |
| BUILD-003 | The Windows release export is uploaded as a complete folder | `build-windows.yml` | export verified locally; artifact upload STATIC | AUTO (export) / STATIC (upload) |
| BUILD-004 | Logs are uploaded when validation fails | both workflows | STATIC | STATIC |
| BUILD-005 | No binary or build output is committed | `.gitignore` + structure check | `tools/check_structure.sh` | AUTO |
| BUILD-006 | Test and tool code cannot ship to players | `export_presets.cfg` exclude filter | asserted in `build-windows.yml`; verified locally | AUTO |
| BUILD-007 | Workflows use least-privilege permissions | `permissions: contents: read` | STATIC | STATIC |
| BUILD-008 | A broken script fails the compile phase | `run_tests.gd:_script_problem` | proven by a real regression during development | AUTO |
| BUILD-009 | An engine error inside a passing test fails the run | `tools/run_validation.sh` | proven by removing the defect-17 fix and confirming exit 1 | AUTO |
| BUILD-010 | CI and a developer run byte-identical checks | both workflows call `tools/run_validation.sh` | STATIC | STATIC |

## The ship, the flight and the campaign (SHIP / FLY / MIS)

| ID | Requirement | Implementation | Verification | Status |
|---|---|---|---|---|
| SHIP-001 | The crew begins each run aboard a ship, not a static hub | `starfarer_deck.tscn`, `GameConfig.SCENE_SHIP` | `test_scene_integrity`, playtest | AUTO + PLAY |
| SHIP-002 | Four pre-flight tasks must be completed before launch | `ship_station.gd`, `MissionRules.ship_tasks_remaining` | `test_mission_rules`, playtest | AUTO + PLAY |
| SHIP-003 | A completed task cannot be completed twice | `MissionRules.can_complete_ship_task` | `test_mission_rules` | AUTO |
| SHIP-004 | The course is set at the nav console, host only | `nav_console.gd` | `test_mission_flow`, playtest | AUTO + PLAY |
| SHIP-005 | Every station is reachable on foot from the spawn | `ShipRoutes`, level layout | `test_level_reachability` (capsule sweep), playtest | AUTO + PLAY |
| SHIP-006 | The crew must be seated before the ship will launch | `launch_lever.gd:_blocker`, `MissionRules.can_launch` | `test_mission_rules`, playtest reads the refusal prompt | AUTO + PLAY |
| SHIP-007 | A seated player cannot walk out of the chair | `player.gd:_seated_physics` | playtest measures the drift under held input | PLAY |
| SHIP-008 | A seated player may swivel but not turn their back on the seat | `player.gd:SEATED_YAW_LIMIT` | STATIC | STATIC |
| SHIP-009 | **The launch control is within a seated pilot's reach and swivel** | `starfarer_deck.tscn`, `crew_seat.gd:is_pilot_seat` | `test_level_reachability:_check_pilot_can_launch`; the playtest pulls it from the chair | AUTO + PLAY |
| SHIP-010 | Seats are occupied host-authoritatively and freed on disconnect | `crew_seat.gd`, `game_manager.gd` | `test_mission_rules`, `test_session_reset` | AUTO |
| FLY-001 | Launch, transit and landing run on the host clock | `game_manager.gd`, `MissionRules` | `test_mission_flow`, playtest | AUTO + PLAY |
| FLY-002 | The flight is presented identically on every peer with no extra RPC | `flight_sequence.gd` reads phase + start time only | STATIC (single-peer playtest sees the sequence run) | STATIC |
| FLY-003 | Landing mounts the destination surface and respawns the crew there | `scene_manager.gd`, `spawn_manager.gd` | `test_mission_flow`, playtest | AUTO + PLAY |
| FLY-004 | A player is never left strapped into a seat that no longer exists | `player.gd`, transition reset | playtest asserts `seated_at` is clear after landing | PLAY |
| MIS-001 | Three planets exist as data, each with its own scene, sky and hazard | `mission_catalog.gd` | `test_mission_rules`, `test_scene_integrity` | AUTO |
| MIS-002 | Missions unlock in order; the first is always flyable | `MissionCatalog.is_unlocked` | `test_mission_rules` | AUTO |
| MIS-003 | The nav console says why a destination is locked | `nav_console.gd` | playtest reads the prompt | PLAY |
| MIS-004 | A crystal may be sealed behind a coupling, a guard or a hazard | `MissionRules.crystal_lock` | `test_mission_rules` | AUTO |
| MIS-005 | The coupling occupies the crystal inventory slot | `game_manager.gd`, `GameConfig.ITEM_COUPLING` | `test_mission_rules`, playtest | AUTO + PLAY |
| MIS-006 | Fitting the coupling unseals its crystal | `coupling_socket.gd` | `test_mission_rules`, playtest | AUTO + PLAY |
| MIS-007 | A hazard field damages players until the vent is sealed, host only | `hazard_field.gd`, `hazard_control.gd` | `test_mission_rules`; damage path STATIC | AUTO + STATIC |
| MIS-008 | Taking the Star Map wakes the Warden exactly once | `game_manager.gd:guardian_spawned` | `test_mission_flow` | AUTO |
| MIS-009 | The Warden is invulnerable until all three shield nodes are down | `MissionRules.boss_is_vulnerable`, `warden.gd` | `test_mission_rules` | AUTO |
| MIS-010 | The Warden enrages below a health fraction and hunts the map carrier | `warden.gd` | `test_mission_rules` (phase function) | AUTO |
| MIS-011 | **The Warden is sized to the crew, so a solo player can finish the game** | `MissionRules.boss_scale`, `game_manager.gd`, `warden.gd` | `test_mission_rules`, playtest | AUTO + PLAY |
| MIS-012 | The first mission carries two locks, not one, so it is not three identical fetches | `MissionRules.locked_crystals` | `test_mission_rules`, playtest | AUTO + PLAY |
| MIS-013 | **A guard cannot be killed twice, however many shots land in one frame** | `sentinel.gd:_guard_dead` | `test_mission_rules`; found by a real engine crash | AUTO |
| MIS-014 | A crystal guard and the temple Sentinel coexist | `spawn_manager.gd:host_spawn_guardian` | `test_sentinel`, `test_combat_and_revive` | AUTO |
| MIS-015 | A guard is sized to the crew and never dies in one burst | `MissionRules.guard_hits_to_kill` | `test_mission_rules` | AUTO |
| MIS-016 | **The altar restores the crew when it activates, so the boss is decided by play and not by attrition** | `GameManager._host_restore_crew`, `Player.host_heal` | `test_combat_and_revive`, playtest | AUTO + PLAY |
| MIS-017 | The restore does not stand a downed player up - reviving is what does that | `GameManager._host_restore_crew` | `test_combat_and_revive` | AUTO |
| MIS-018 | **Every interactable id names the level it is in** - Cinder and Hallow shipped Nerava's altar and drop pod ids | level scenes | `test_scene_integrity` (prefix gate) | AUTO |
| MIS-019 | Every pre-flight station names its place, not just its job | `GameConfig.SHIP_TASK_LOCATIONS`, `MissionRules.ship_task_hint` | `test_mission_rules` | AUTO |
| MIS-020 | **The Warden stays inside the angle a player is allowed to look up** | `Warden._host_think` height hold | `test_combat_and_revive`, playtest | AUTO + PLAY |
| MIS-021 | The enraged Warden can actually damage a player it closes on | `Warden._host_contact_damage` (horizontal range) | `test_combat_and_revive` | AUTO |
| MIS-022 | **A hovering boss is never trapped by scenery** - it flew into a temple pillar and stopped there for the rest of the fight | `Warden._ready` collision mask | playtest | PLAY |
| MIS-023 | Contact damage is sized to the crew, like the boss's health and volleys | `MissionRules.boss_contact_damage` | `test_mission_rules` | AUTO |
| MIS-024 | **The game never shows a prompt for something the host will always refuse** | `Interactable.interaction_point`, `GameManager._host_clear_line` | `test_scene_integrity` (12 approaches per interactable) | AUTO |
| MIS-025 | The temple is discovered by walking into the clearing, not by being spawned | `temple_trigger.gd` (confirms the overlap a physics step later) | playtest on all three planets | PLAY |
| MIS-026 | **A player can step onto what the navigation bake says they can climb** | `Player._try_step_up` | playtest | PLAY |
| MIS-027 | Every objective on every planet can be reached on foot | level geometry (plateau approach steps) | playtest per mission | PLAY |
| MIS-028 | No hovering enemy is trapped by scenery | `Warden._ready`, `Sentinel._ready` collision masks | playtest | PLAY |

## Quality gates (QA)

| ID | Requirement | Implementation | Verification | Status |
|---|---|---|---|---|
| QA-001 | The game can be played from the main menu to extraction | `tools/playtest.gd`, run in CI | the playtest itself | PLAY |
| QA-002 | A press of E is never silently swallowed | `player.gd:resolve_interact` | `test_interact_press` (16 assertions) | AUTO |
| QA-003 | Every authored route is walkable by a player-sized capsule, across its width | `test_level_reachability` | itself | AUTO |
| QA-004 | A spawn point has a clear run at the objective, not just a clear axis | `test_level_reachability:_check_spawn_exits` | itself | AUTO |
| QA-005 | The playtest cannot report a clean run after dying | `playtest.gd:_require_failure` | proven by a driver that died and was caught | AUTO |
| QA-006 | The playtest routes come from each level's navigation mesh, so any mission can be driven | `tools/playtest.gd:_nav_walk_to` | playtest runs | PLAY |
| QA-007 | The playtest can plot a course for a later planet the way an unlocked crew would | `tools/playtest.gd:_plot_the_course`, `--mission=` | playtest runs | PLAY |
