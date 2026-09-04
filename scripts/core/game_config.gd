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

const GAME_VERSION: String = "0.6.0"

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
# LAN discovery
# --------------------------------------------------------------------------
#
# The host broadcasts a short announcement on this port so players on the same
# network can pick the session out of a list instead of typing an address.
# Deliberately NOT the game port: discovery is an unauthenticated broadcast and
# has no business sharing a socket with the session itself.

const DISCOVERY_PORT: int = 7001

## How often the host announces itself.
const DISCOVERY_ANNOUNCE_INTERVAL: float = 1.0

## An entry disappears from the browser this long after its last announcement,
## so a host that quits stops being listed rather than lingering as a dead row.
const DISCOVERY_ENTRY_TIMEOUT: float = 4.0

## Hard cap on tracked sessions. Discovery packets are unauthenticated, so
## anybody on the network can send them; without a cap a flood would grow the
## browser without bound.
const DISCOVERY_MAX_SESSIONS: int = 32

## Anything larger is discarded unread.
const DISCOVERY_MAX_PACKET_BYTES: int = 512

const SESSION_NAME_MIN_LENGTH: int = 3
const SESSION_NAME_MAX_LENGTH: int = 24
const SESSION_NAME_FALLBACK: String = "Expedition"

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

## First person. The camera sits at eye height on the pivot itself - there is
## no spring arm, so nothing can push the view into the player's own body.
const EYE_HEIGHT: float = 1.62

const FOV_BASE: float = 78.0
## Widening while sprinting is the cheapest possible sense of speed.
const FOV_SPRINT: float = 88.0
const FOV_BLEND: float = 6.0

## Camera roll and shake, all presentation only.
const VIEW_BOB_FREQUENCY: float = 8.0
const VIEW_BOB_AMOUNT: float = 0.035
const LAND_DIP: float = 0.09
const DAMAGE_SHAKE: float = 0.35
## Firing shakes the view too, but an order of magnitude less than being
## hit does - at ten shots a second, anything larger is nausea, not weight.
const FIRE_SHAKE: float = 0.035
const SHAKE_DECAY: float = 3.2

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

## How long a press of Interact keeps looking for something to act on.
##
## A press used to be sampled on exactly ONE frame. If the interact ray happened
## to be off the object on that frame - head bob is enough, and so is still
## decelerating as you walk up to something - the press was spent against
## nothing and the latch blocked any retry until the key was released. To a
## player that is "I pressed E looking right at it and nothing happened".
##
## A press is now an INTENT with a short deadline. It still fires at most once
## per key press, so holding E cannot autofire and holding E to revive a
## teammate is unchanged.
const INTERACT_GRACE_TIME: float = 0.18

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

## Carryable that is not a crystal. It occupies the same single inventory slot,
## which is the point: fetching the coupling costs you a trip.
const ITEM_COUPLING: String = "power_coupling"

# --------------------------------------------------------------------------
# The ship
# --------------------------------------------------------------------------

## Stations that must all be green before the launch lever arms. Order is the
## order the HUD lists them in.
const SHIP_TASK_REACTOR: String = "task_reactor"
const SHIP_TASK_COURSE: String = "task_course"
const SHIP_TASK_FUEL: String = "task_fuel"
const SHIP_TASK_HATCH: String = "task_hatch"

const SHIP_TASK_IDS: PackedStringArray = [
	"task_reactor", "task_course", "task_fuel", "task_hatch",
]

## What each station is called on screen.
const SHIP_TASK_LABELS: Dictionary = {
	"task_reactor": "Prime the reactor",
	"task_course": "Plot the course",
	"task_fuel": "Pressurise the fuel line",
	"task_hatch": "Seal the outer hatch",
}

## Where each station IS. The deck runs 41 m from bow to stern through four
## bulkheads, and the HUD used to name the next task without saying where to
## find it - so the only way to learn the ship was to walk all of it once. The
## label says what to do; this says where, and the two are shown together.
## Bow is -Z, stern is +Z, port is -X, starboard is +X.
const SHIP_TASK_LOCATIONS: Dictionary = {
	"task_reactor": "engineering, by the spine",
	"task_course": "the bridge, at the bow",
	"task_fuel": "engineering, on the starboard wall",
	"task_hatch": "the cargo bay, at the stern",
}

## How long each seat's restraint animation takes to settle. Purely cosmetic;
## the seat is authoritative the instant the host accepts it.
const SEAT_SETTLE_TIME: float = 0.35

# --------------------------------------------------------------------------
# Flight sequence timing (seconds). The host drives these; clients replay the
# same numbers from the replicated phase start, so nobody's animation drifts.
# --------------------------------------------------------------------------

const FLIGHT_LAUNCH_TIME: float = 7.5
const FLIGHT_TRANSIT_TIME: float = 4.0
const FLIGHT_LANDING_TIME: float = 6.5

# --------------------------------------------------------------------------
# Surface hazard
# --------------------------------------------------------------------------

## Damage per second inside a live hazard field, and how often it is applied.
const HAZARD_DAMAGE_PER_TICK: int = 6
const HAZARD_TICK_INTERVAL: float = 1.0

# --------------------------------------------------------------------------
# The Warden (boss)
# --------------------------------------------------------------------------

## Damage one blaster bolt does to the Warden, and to one of its shield nodes.
##
## The Sentinel counts HITS and staggers on the tenth; it has no health at all.
## A boss needs a bar, so it needs a number - at 25 a node takes 5 bolts and the
## body takes 36, which is a fight for one player and a brisk one for four.
## Hits to destroy a crystal's guard. Lower than the boss on purpose: the guard
## is an obstacle on the way to an objective, not the fight itself.
const GUARD_HITS_TO_KILL: int = 14

## How much health the altar gives back when it activates. A full heal: the
## crew has earned it by placing three crystals, and the fight it summons is
## balanced around arriving at full. See GameManager._host_restore_crew.
const ALTAR_RESTORE_HEALTH: int = MAX_HEALTH

const BLASTER_BOSS_DAMAGE: int = 25

const BOSS_MAX_HEALTH: int = 900
const BOSS_SHIELD_NODE_COUNT: int = 3
const BOSS_SHIELD_NODE_HEALTH: int = 120
## Health fraction at or below which the Warden enrages.
const BOSS_ENRAGE_FRACTION: float = 0.35
const BOSS_VOLLEY_INTERVAL: float = 2.6
const BOSS_ENRAGED_VOLLEY_INTERVAL: float = 1.4
const BOSS_VOLLEY_PROJECTILES: int = 3
const BOSS_CONTACT_DAMAGE: int = 18
## How close, MEASURED ON THE GROUND, the enraged Warden has to be to hurt you
## by contact. Horizontal because it flies: see Warden._host_contact_damage.
const BOSS_CONTACT_RANGE: float = 3.2

## The rings the Warden holds around its target: comfortable while it trades
## fire, close while enraged.
##
## The enraged ring MUST sit outside BOSS_CONTACT_RANGE. It was 3.0 against a
## contact range of 3.2, so the boss deliberately parked inside its own damage
## radius and contact damage stopped being a punishment for letting it reach
## you - it was an unconditional 18 damage a second for the whole phase, which
## killed a solo player from full in four seconds however well they played.
## Measured, on both the cautious and the aggressive driver.
const BOSS_STAND_OFF: float = 11.0
const BOSS_ENRAGED_STAND_OFF: float = 4.5
const BOSS_MOVE_SPEED: float = 4.2
## How far above its anchor the Warden hovers. It flies rather than walks, so it
## needs no navmesh - which removes the whole class of navigation failures the
## Sentinel carries three workarounds for, from the most important fight here.
const BOSS_HOVER_HEIGHT: float = 3.4
const BOSS_ENRAGED_MOVE_SPEED: float = 6.4

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
## The Warden is ALSO a Guardian, so that hostile cleanup and the blaster's
## target search keep working unchanged. This narrower group exists so the two
## spawn calls can refuse duplicates of their own kind without refusing each
## other: a Sentinel guarding a crystal and the Warden at the temple are allowed
## to be alive at the same time.
const GROUP_BOSS: String = "Boss"
const GROUP_PROJECTILE: String = "Projectile"
const GROUP_SESSION_BOUND: String = "SessionBound"

# --------------------------------------------------------------------------
# Scene keys -> resource paths (single source of truth for transitions)
# --------------------------------------------------------------------------

const SCENE_MAIN_MENU: String = "main_menu"
const SCENE_LOBBY: String = "lobby"
## "ship" replaced "hub" when the Wayfinder Station became a vessel that flies.
const SCENE_SHIP: String = "ship"
const SCENE_NERAVA: String = "nerava"
const SCENE_CINDER: String = "cinder"
const SCENE_HALLOW: String = "hallow"

const SCENE_PATHS: Dictionary = {
	SCENE_MAIN_MENU: "res://scenes/ui/main_menu.tscn",
	SCENE_LOBBY: "res://scenes/ui/lobby.tscn",
	SCENE_SHIP: "res://scenes/levels/starfarer_deck.tscn",
	SCENE_NERAVA: "res://scenes/levels/nerava_landing_zone.tscn",
	SCENE_CINDER: "res://scenes/levels/cinder_ashflats.tscn",
	SCENE_HALLOW: "res://scenes/levels/hallow_icefield.tscn",
}

## Scenes that are real gameplay levels (get an entity spawner, HUD, players).
const GAMEPLAY_SCENES: PackedStringArray = ["ship", "nerava", "cinder", "hallow"]

## Every surface a mission can land on. The ship is not one of them.
const SURFACE_SCENES: PackedStringArray = ["nerava", "cinder", "hallow"]


static func is_valid_scene_key(key: String) -> bool:
	return SCENE_PATHS.has(key)


static func scene_path(key: String) -> String:
	return String(SCENE_PATHS.get(key, ""))
