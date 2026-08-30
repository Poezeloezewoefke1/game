extends Node
## Central, authoritative tuning table for STARBOUND STATION: THE LOST SIGNAL.
##
## Every gameplay-significant number lives here so that host validation, client
## prediction, UI display and automated tests all read the SAME value. Never
## hard-code these numbers anywhere else - a divergence between the value the
## client predicts with and the value the host validates with is a desync bug.
##
## Autoload name: GameConfig

# --------------------------------------------------------------------------
# Build / protocol identity
# --------------------------------------------------------------------------

## Bumped whenever the wire protocol or authoritative rules change. Host and
## client must match exactly; mismatched clients are rejected at handshake.
const PROTOCOL_VERSION: int = 1

const GAME_VERSION: String = "0.1.0"

# --------------------------------------------------------------------------
# Networking
# --------------------------------------------------------------------------

const DEFAULT_PORT: int = 7000
const MIN_PORT: int = 1024
const MAX_PORT: int = 65535

## Host peer id in Godot's high-level multiplayer is always 1.
const HOST_PEER_ID: int = 1

## Total simultaneous players INCLUDING the host.
const MAX_PLAYERS: int = 4

## ENetMultiplayerPeer.create_server() takes max *clients*, i.e. excluding host.
const MAX_CLIENTS: int = MAX_PLAYERS - 1

## Seconds a joining client waits for the connection to succeed before failing.
const CONNECT_TIMEOUT: float = 10.0

## Seconds a joined client waits for the host handshake (protocol + lobby state)
## before giving up. Guards against connecting to a socket that is not this game.
const HANDSHAKE_TIMEOUT: float = 8.0

# --------------------------------------------------------------------------
# Scene transition / readiness barrier
# --------------------------------------------------------------------------

## Seconds the host waits for every peer to acknowledge a scene load before it
## gives up on the laggards. Peers that miss the barrier are disconnected with
## a documented reason (see docs/NETWORK_RULES.md).
const SCENE_TRANSITION_TIMEOUT: float = 25.0

# --------------------------------------------------------------------------
# Player identity
# --------------------------------------------------------------------------

const NAME_MIN_LENGTH: int = 2
const NAME_MAX_LENGTH: int = 16
const NAME_FALLBACK_PREFIX: String = "Explorer"

# --------------------------------------------------------------------------
# Player movement
# --------------------------------------------------------------------------

const WALK_SPEED: float = 5.0
const SPRINT_SPEED: float = 8.5
const JUMP_VELOCITY: float = 8.0
const AIR_CONTROL: float = 0.35
const GROUND_ACCELERATION: float = 55.0
const GROUND_FRICTION: float = 45.0

const MOUSE_SENSITIVITY: float = 0.0022
const PITCH_MIN_DEG: float = -75.0
const PITCH_MAX_DEG: float = 65.0

## How fast a remote (non-authority) player's visual transform catches up to the
## replicated transform. Higher = snappier but jitterier.
const REMOTE_SMOOTHING: float = 18.0

## If a remote transform update is further away than this, snap instead of
## interpolating (teleport, respawn, scene change).
const REMOTE_SNAP_DISTANCE: float = 6.0

# --------------------------------------------------------------------------
# Movement plausibility (host-side anti-teleport)
# --------------------------------------------------------------------------
#
# Movement is client-driven so it feels responsive, so the host samples it and
# rejects the physically impossible. The numbers are a deliberate trade-off:
#
#   * Sampling over a LONGER window makes the fixed jitter allowance matter
#     less, which tightens the effective speed ceiling. Sampling every frame
#     would make the allowance dominate and let a cheater "micro-teleport".
#   * The tolerance multiplier has to absorb latency, slope-assisted descents
#     and jump arcs. Roughly twice sprint speed is enough for those and still
#     nowhere near enough to cross the map.

## Seconds between host position samples.
const MOVEMENT_SAMPLE_INTERVAL: float = 0.5

## Multiple of SPRINT_SPEED treated as still plausible.
const MOVEMENT_SPEED_TOLERANCE: float = 1.6

## Fixed metres of slack per sample, for packet jitter.
const MOVEMENT_JITTER_ALLOWANCE: float = 1.5

## Consecutive violations before the host teleports the player back.
const MOVEMENT_STRIKES_BEFORE_CORRECTION: int = 3


## Greatest distance the host will accept over `dt` seconds.
static func max_plausible_travel(dt: float) -> float:
	return SPRINT_SPEED * MOVEMENT_SPEED_TOLERANCE * dt + MOVEMENT_JITTER_ALLOWANCE


# --------------------------------------------------------------------------
# Interaction
# --------------------------------------------------------------------------

## Range of the client-side interaction ray (what drives the HUD prompt).
const INTERACT_DISTANCE: float = 3.2

## Range the HOST validates against. Deliberately larger than
## INTERACT_DISTANCE to absorb latency between the client seeing a valid
## prompt and the host processing the request. Must stay small enough that it
## is not exploitable - see NET-010 in docs/REQUIREMENTS_TRACEABILITY.md.
const INTERACT_VALIDATE_DISTANCE: float = 5.0

## Extra vertical tolerance when validating interaction distance, so standing on
## a crate next to a pedestal does not silently fail.
const INTERACT_VALIDATE_HEIGHT: float = 3.0

# --------------------------------------------------------------------------
# Health / downed / revive
# --------------------------------------------------------------------------

const MAX_HEALTH: int = 100
const REVIVED_HEALTH: int = 40
const REVIVE_DURATION: float = 3.0

## Reviver must stay within this distance of the downed player for the whole
## revive. Slightly larger than INTERACT_DISTANCE so small steps do not cancel.
const REVIVE_MAX_DISTANCE: float = 4.0

## Host re-checks an in-progress revive at this interval (seconds).
const REVIVE_VALIDATE_INTERVAL: float = 0.25

# --------------------------------------------------------------------------
# Blaster (heat based - no ammunition)
# --------------------------------------------------------------------------

const BLASTER_FIRE_INTERVAL: float = 0.22
const BLASTER_HEAT_MAX: float = 100.0
const BLASTER_HEAT_PER_SHOT: float = 14.0
const BLASTER_COOL_RATE: float = 26.0

## Once overheated the weapon stays locked until heat falls below this fraction
## of BLASTER_HEAT_MAX. Prevents single-shot stutter at the cap.
const BLASTER_OVERHEAT_RESET_RATIO: float = 0.45

const BLASTER_RANGE: float = 60.0

## Host-side leniency on fire rate: clients may be up to this fraction early
## because of clock jitter. Anything faster is rejected AND rate limited.
const BLASTER_RATE_TOLERANCE: float = 0.85

# --------------------------------------------------------------------------
# Sentinel guardian
# --------------------------------------------------------------------------

const GUARDIAN_MAX_SPEED: float = 4.6
const GUARDIAN_ACCELERATION: float = 6.0
const GUARDIAN_HOVER_HEIGHT: float = 2.2
const GUARDIAN_SHOOT_INTERVAL: float = 1.6
const GUARDIAN_SHOOT_RANGE: float = 22.0
const GUARDIAN_LOSE_RANGE: float = 70.0
const GUARDIAN_PROJECTILE_DAMAGE: int = 33
const GUARDIAN_PROJECTILE_SPEED: float = 13.0
const GUARDIAN_PROJECTILE_LIFETIME: float = 6.0
const GUARDIAN_PROJECTILE_RADIUS: float = 0.45

## Host-validated blaster hits required to stagger the Sentinel.
const GUARDIAN_STAGGER_HIT_THRESHOLD: int = 10
const GUARDIAN_STAGGER_DURATION: float = 3.0

## Repath cadence. The Sentinel does NOT set a navigation target every frame -
## see AI-004 in docs/REQUIREMENTS_TRACEABILITY.md.
const GUARDIAN_REPATH_INTERVAL: float = 0.4

## Only repath if the target moved at least this far since the last repath.
const GUARDIAN_REPATH_MIN_DELTA: float = 1.0

## If the Sentinel has had no usable path for this long it teleports back to its
## spawn anchor rather than freezing forever.
const GUARDIAN_STUCK_RECOVER_TIME: float = 6.0

# --------------------------------------------------------------------------
# RPC rate limiting (requests per second, per peer, per channel)
# --------------------------------------------------------------------------

const RATE_LIMIT_INTERACT: float = 8.0
const RATE_LIMIT_FIRE: float = 12.0
const RATE_LIMIT_REVIVE: float = 10.0
const RATE_LIMIT_LOBBY: float = 4.0
const RATE_LIMIT_SCENE_ACK: float = 4.0

## A peer that exceeds a limit by this multiplier over a sustained window is
## treated as hostile/broken and disconnected.
const RATE_LIMIT_ABUSE_MULTIPLIER: float = 6.0
const RATE_LIMIT_ABUSE_WINDOW: float = 3.0

# --------------------------------------------------------------------------
# Mission content identifiers
# --------------------------------------------------------------------------

const CRYSTAL_RUINS: String = "crystal_ruins"
const CRYSTAL_CAVE: String = "crystal_cave"
const CRYSTAL_GROVE: String = "crystal_grove"

const ALL_CRYSTAL_IDS: PackedStringArray = ["crystal_ruins", "crystal_cave", "crystal_grove"]

const REQUIRED_PEDESTAL_COUNT: int = 3

# --------------------------------------------------------------------------
# Physics layers (keep in sync with [layer_names] in project.godot)
# --------------------------------------------------------------------------

const LAYER_WORLD: int = 1 << 0
const LAYER_PLAYER: int = 1 << 1
const LAYER_INTERACTABLE: int = 1 << 2
const LAYER_ENEMY: int = 1 << 3
const LAYER_PROJECTILE: int = 1 << 4
const LAYER_PLAYER_HURTBOX: int = 1 << 5

# --------------------------------------------------------------------------
# Groups
# --------------------------------------------------------------------------

const GROUP_INTERACTABLE: String = "Interactable"
const GROUP_PLAYER: String = "Player"
const GROUP_GUARDIAN: String = "Guardian"
const GROUP_PROJECTILE: String = "Projectile"
const GROUP_SESSION_BOUND: String = "SessionBound"

# --------------------------------------------------------------------------
# Scene keys -> resource paths (single source of truth for transitions)
# --------------------------------------------------------------------------

const SCENE_MAIN_MENU: String = "main_menu"
const SCENE_LOBBY: String = "lobby"
const SCENE_HUB: String = "hub"
const SCENE_NERAVA: String = "nerava"

const SCENE_PATHS: Dictionary = {
	SCENE_MAIN_MENU: "res://scenes/ui/main_menu.tscn",
	SCENE_LOBBY: "res://scenes/ui/lobby.tscn",
	SCENE_HUB: "res://scenes/levels/wayfinder_hub.tscn",
	SCENE_NERAVA: "res://scenes/levels/nerava_landing_zone.tscn",
}

## Scenes that are real gameplay levels (get an entity spawner, HUD, players).
const GAMEPLAY_SCENES: PackedStringArray = ["hub", "nerava"]


static func is_valid_scene_key(key: String) -> bool:
	return SCENE_PATHS.has(key)


static func scene_path(key: String) -> String:
	return String(SCENE_PATHS.get(key, ""))
