extends RefCounted
class_name MissionRules
## PURE authoritative rules for THE LOST SIGNAL.
##
## Everything in here is a static function over plain data. No nodes, no tree,
## no networking. That is deliberate: it makes every security-relevant decision
## in the mission directly unit-testable (see tests/unit/test_mission_rules.gd)
## instead of only reachable through a live 4-player session.
##
## GameManager owns the state; MissionRules decides whether a requested change
## is legal. The two must never disagree - GameManager must not contain its own
## copy of a rule that lives here.

enum MissionState {
	SHIP_IDLE,
	LOBBY_READY,
	TRANSITIONING_TO_SHIP,
	TRANSITIONING_TO_SURFACE,
	FIND_TEMPLE,
	FIND_CRYSTALS,
	ACTIVATE_ALTAR,
	RETRIEVE_STAR_MAP,
	RETURN_TO_DROP_POD,
	MISSION_COMPLETE,
	MISSION_FAILED,
	RETURNING_TO_LOBBY,
	# --- flight, added when the hub became a ship -------------------------
	# LAUNCHING and LANDING are the two scripted sequences. They are real
	# states rather than a flag on SHIP_IDLE because while one is running the
	# crew must not be able to interact, leave their seats, or start a second
	# launch - and "cannot act" is exactly what a state is for.
	LAUNCHING,
	IN_TRANSIT,
	LANDING,
	# The Warden wakes when the Star Map leaves the altar. The crew cannot
	# extract until it is dead, so this sits between the pickup and the run
	# back to the pod.
	BOSS_FIGHT,
}

## Star Map lifecycle. "locked" until the altar opens; "extracted" is terminal.
const MAP_LOCKED := "locked"
const MAP_AVAILABLE := "available"
const MAP_CARRIED := "carried"
const MAP_DROPPED := "dropped"
const MAP_EXTRACTED := "extracted"

const OBJECTIVE_TEXT: Dictionary = {
	MissionState.SHIP_IDLE: "Ready the ship for launch.",
	MissionState.LOBBY_READY: "Waiting for the host to start the session.",
	MissionState.TRANSITIONING_TO_SHIP: "Boarding the Starfarer...",
	MissionState.TRANSITIONING_TO_SURFACE: "Descending...",
	MissionState.LAUNCHING: "Launching. Stay in your seat.",
	MissionState.IN_TRANSIT: "In transit.",
	MissionState.LANDING: "Landing. Stay in your seat.",
	MissionState.BOSS_FIGHT: "Kill the Warden.",
	MissionState.FIND_TEMPLE: "Locate the Temple.",
	MissionState.FIND_CRYSTALS: "Find 3 Power Crystals to power the altar.",
	MissionState.ACTIVATE_ALTAR: "Place the remaining Power Crystals into the altar.",
	MissionState.RETRIEVE_STAR_MAP: "Retrieve the Star Map.",
	MissionState.RETURN_TO_DROP_POD: "Return to the Drop Pod.",
	MissionState.MISSION_COMPLETE: "Mission accomplished.",
	MissionState.MISSION_FAILED: "Mission failed.",
	MissionState.RETURNING_TO_LOBBY: "Returning to the lobby...",
}

## Legal state edges. Anything not listed is rejected by is_valid_transition().
const _EDGES: Dictionary = {
	MissionState.LOBBY_READY: [
		MissionState.TRANSITIONING_TO_SHIP,
	],
	MissionState.TRANSITIONING_TO_SHIP: [
		MissionState.SHIP_IDLE,
		MissionState.RETURNING_TO_LOBBY,
	],
	MissionState.SHIP_IDLE: [
		MissionState.LAUNCHING,
		MissionState.RETURNING_TO_LOBBY,
	],
	MissionState.LAUNCHING: [
		MissionState.IN_TRANSIT,
		# An abort during the sequence puts the crew back on the deck rather
		# than stranding them in a state with no exit.
		MissionState.SHIP_IDLE,
		MissionState.RETURNING_TO_LOBBY,
	],
	MissionState.IN_TRANSIT: [
		MissionState.LANDING,
		MissionState.RETURNING_TO_LOBBY,
	],
	MissionState.LANDING: [
		MissionState.TRANSITIONING_TO_SURFACE,
		MissionState.RETURNING_TO_LOBBY,
	],
	MissionState.TRANSITIONING_TO_SURFACE: [
		MissionState.FIND_TEMPLE,
		MissionState.RETURNING_TO_LOBBY,
	],
	MissionState.FIND_TEMPLE: [
		MissionState.FIND_CRYSTALS,
		MissionState.MISSION_FAILED,
		MissionState.RETURNING_TO_LOBBY,
	],
	MissionState.FIND_CRYSTALS: [
		MissionState.ACTIVATE_ALTAR,
		MissionState.MISSION_FAILED,
		MissionState.RETURNING_TO_LOBBY,
	],
	MissionState.ACTIVATE_ALTAR: [
		MissionState.RETRIEVE_STAR_MAP,
		MissionState.MISSION_FAILED,
		MissionState.RETURNING_TO_LOBBY,
	],
	MissionState.RETRIEVE_STAR_MAP: [
		MissionState.BOSS_FIGHT,
		MissionState.MISSION_FAILED,
		MissionState.RETURNING_TO_LOBBY,
	],
	MissionState.BOSS_FIGHT: [
		MissionState.RETURN_TO_DROP_POD,
		MissionState.MISSION_FAILED,
		MissionState.RETURNING_TO_LOBBY,
	],
	MissionState.RETURN_TO_DROP_POD: [
		MissionState.MISSION_COMPLETE,
		MissionState.MISSION_FAILED,
		MissionState.RETURNING_TO_LOBBY,
	],
	MissionState.MISSION_COMPLETE: [
		MissionState.RETURNING_TO_LOBBY,
	],
	MissionState.MISSION_FAILED: [
		# Retry restarts the descent; Return to Lobby unwinds the whole session.
		MissionState.TRANSITIONING_TO_SURFACE,
		MissionState.RETURNING_TO_LOBBY,
	],
	MissionState.RETURNING_TO_LOBBY: [
		MissionState.LOBBY_READY,
	],
}

## States in which players are physically on a planet surface with the puzzle
## live. Every mission-object interaction is gated on one of these.
const SURFACE_STATES: Array = [
	MissionState.FIND_TEMPLE,
	MissionState.FIND_CRYSTALS,
	MissionState.ACTIVATE_ALTAR,
	MissionState.RETRIEVE_STAR_MAP,
	MissionState.BOSS_FIGHT,
	MissionState.RETURN_TO_DROP_POD,
]

## States in which the crew is aboard the ship. Seats, ship tasks and the launch
## lever are gated on these; nothing aboard is interactive mid-flight.
const SHIP_STATES: Array = [
	MissionState.SHIP_IDLE,
]

## The scripted flight sequences. Input is locked and the crew stays seated.
const FLIGHT_STATES: Array = [
	MissionState.LAUNCHING,
	MissionState.IN_TRANSIT,
	MissionState.LANDING,
]


static func is_valid_transition(from: int, to: int) -> bool:
	if from == to:
		return false
	var allowed: Variant = _EDGES.get(from)
	if allowed == null:
		return false
	return (allowed as Array).has(to)


static func objective_text(state: int) -> String:
	return String(OBJECTIVE_TEXT.get(state, ""))


static func state_name(state: int) -> String:
	var keys := MissionState.keys()
	if state >= 0 and state < keys.size():
		return String(keys[state])
	return "UNKNOWN(%d)" % state


static func is_surface_state(state: int) -> bool:
	return SURFACE_STATES.has(state)


## Boss phases. 0 is "not awake"; the Warden only exists once the Star Map moves.
const BOSS_ASLEEP := 0
const BOSS_SHIELDED := 1   ## invulnerable until every shield node is down
const BOSS_VOLLEY := 2     ## exposed, ranged
const BOSS_ENRAGED := 3    ## faster, closes distance
const BOSS_DEAD := 4


## A blank snapshot for a fresh descent. Used both by GameManager on reset and
## by tests as a known-good starting point.
##
## `mission_id` and `completed_missions` survive a descent reset because they
## describe the CAMPAIGN, not the run: retrying a failed landing must not send
## the crew to a different planet or forget what they have already finished.
static func fresh_snapshot(epoch: int, mission_id: String = "",
		completed: Array = []) -> Dictionary:
	var mid := mission_id if mission_id != "" else MissionCatalog.first_id()
	return {
		"epoch": epoch,
		"state": MissionState.TRANSITIONING_TO_SURFACE,
		"mission_id": mid,
		"completed_missions": completed.duplicate(),
		"crystals_in_world": _crystal_list(),
		"crystals_carried": {},        # peer_id -> crystal_id
		"pedestals": {},               # pedestal_id -> crystal_id placed
		"altar_active": false,
		"star_map_state": MAP_LOCKED,
		"star_map_carrier": 0,
		"guardian_spawned": false,
		"temple_discovered": false,
		"extracted": false,
		# --- ship ---------------------------------------------------------
		"ship_tasks": {},              # task_id -> true once completed
		"seats": {},                   # seat_id -> peer_id
		"flight_started_ms": 0,        # host clock when the current phase began
		# --- surface difficulty ------------------------------------------
		"crystal_locks": locked_crystals(mid),   # crystal_id -> lock kind
		"hazard_online": MissionCatalog.hazard(mid) != MissionCatalog.HAZARD_NONE,
		"guards_down": [],             # crystal_id whose guard has been killed
		"coupling_taken": false,       # the power coupling has left its cradle
		# --- boss ---------------------------------------------------------
		"boss_phase": BOSS_ASLEEP,
		"boss_health": 0,
		"boss_nodes": [],              # shield node ids still standing
	}


## A snapshot for the crew standing on the ship between missions.
static func fresh_ship_snapshot(epoch: int, mission_id: String = "",
		completed: Array = []) -> Dictionary:
	var snap := fresh_snapshot(epoch, mission_id, completed)
	snap["state"] = MissionState.TRANSITIONING_TO_SHIP
	return snap


## Which crystals start locked on this mission, and by what.
##
## Every mission uses the same three shapes so the crew learns them once: one
## crystal sealed behind a coupling that has to be found and fitted, one held by
## a guard that has to be put down, one sitting in the hazard field.
##
## Nerava is the tutorial and carries two of the three. It used to carry only the
## coupling, and the measured consequence was that the first mission any player
## sees is one interesting errand followed by TWO identical fetch-and-carry
## trips: 63 of the 124 seconds to the boss, in three round trips of the same
## shape. The first mission is the one that decides whether anyone plays a
## second. Nerava has no hazard - it is a jungle, not a furnace - so the third
## lock still waits for Cinder, and one crystal is still a plain fetch, which is
## what teaches the base move.
static func locked_crystals(mission_id: String) -> Dictionary:
	if mission_id == MissionCatalog.NERAVA:
		return {
			GameConfig.CRYSTAL_CAVE: LOCK_COUPLING,
			GameConfig.CRYSTAL_RUINS: LOCK_GUARD,
		}
	return {
		GameConfig.CRYSTAL_CAVE: LOCK_COUPLING,
		GameConfig.CRYSTAL_RUINS: LOCK_GUARD,
		GameConfig.CRYSTAL_GROVE: LOCK_HAZARD,
	}


const LOCK_COUPLING := "coupling"   ## needs a power coupling carried to it
const LOCK_GUARD := "guard"         ## needs its guard killed
const LOCK_HAZARD := "hazard"       ## needs the surface hazard shut down


# ==========================================================================
# Actor eligibility
# ==========================================================================

## `actor` is {"alive": bool, "downed": bool, "in_mission_scene": bool}.
static func actor_can_act(actor: Dictionary) -> Dictionary:
	if not bool(actor.get("in_mission_scene", false)):
		return _deny("actor_wrong_scene")
	if not bool(actor.get("alive", false)):
		return _deny("actor_not_alive")
	if bool(actor.get("downed", false)):
		return _deny("actor_downed")
	return _allow()


# ==========================================================================
# Crystals
# ==========================================================================

static func can_pick_up_crystal(snap: Dictionary, peer_id: int, crystal_id: String, actor: Dictionary) -> Dictionary:
	var gate := actor_can_act(actor)
	if not bool(gate["ok"]):
		return gate
	if not is_surface_state(int(snap.get("state", -1))):
		return _deny("wrong_mission_state")
	if not GameConfig.ALL_CRYSTAL_IDS.has(crystal_id):
		return _deny("unknown_crystal")
	var in_world: Array = snap.get("crystals_in_world", [])
	if not in_world.has(crystal_id):
		return _deny("crystal_not_available")
	# The lock is checked HERE, in the authoritative gate, not in the crystal's
	# own can_interact(). A client that patched its prompt to say the crystal is
	# free would still be refused by the host.
	var lock := crystal_lock(snap, crystal_id)
	if lock != "":
		return _deny("crystal_locked_" + lock)
	var carried: Dictionary = snap.get("crystals_carried", {})
	if carried.has(peer_id):
		return _deny("inventory_full")
	# Defence in depth: a crystal must never be carried by two peers at once.
	for holder in carried:
		if String(carried[holder]) == crystal_id:
			return _deny("crystal_already_carried")
	if String(snap.get("star_map_state", MAP_LOCKED)) == MAP_CARRIED \
			and int(snap.get("star_map_carrier", 0)) == peer_id:
		return _deny("hands_full_star_map")
	return _allow()


static func can_place_crystal(snap: Dictionary, peer_id: int, pedestal_id: String,
		pedestal_accepts: String, actor: Dictionary) -> Dictionary:
	var gate := actor_can_act(actor)
	if not bool(gate["ok"]):
		return gate
	if not is_surface_state(int(snap.get("state", -1))):
		return _deny("wrong_mission_state")
	var pedestals: Dictionary = snap.get("pedestals", {})
	if pedestals.has(pedestal_id):
		return _deny("pedestal_already_active")
	var carried: Dictionary = snap.get("crystals_carried", {})
	if not carried.has(peer_id):
		return _deny("no_crystal_carried")
	var held := String(carried[peer_id])
	if held != pedestal_accepts:
		return _deny("wrong_crystal")
	return _allow()


# ==========================================================================
# Altar / Star Map
# ==========================================================================

## The altar opens only on exactly the required number of DISTINCT correct
## pedestal activations.
static func altar_should_activate(snap: Dictionary) -> bool:
	var pedestals: Dictionary = snap.get("pedestals", {})
	if pedestals.size() != GameConfig.REQUIRED_PEDESTAL_COUNT:
		return false
	var seen: Dictionary = {}
	for pid in pedestals:
		var cid := String(pedestals[pid])
		if not GameConfig.ALL_CRYSTAL_IDS.has(cid):
			return false
		if seen.has(cid):
			return false
		seen[cid] = true
	return seen.size() == GameConfig.REQUIRED_PEDESTAL_COUNT


static func can_take_star_map(snap: Dictionary, peer_id: int, actor: Dictionary) -> Dictionary:
	var gate := actor_can_act(actor)
	if not bool(gate["ok"]):
		return gate
	if not is_surface_state(int(snap.get("state", -1))):
		return _deny("wrong_mission_state")
	var st := String(snap.get("star_map_state", MAP_LOCKED))
	if st == MAP_LOCKED:
		return _deny("shield_active")
	if st == MAP_CARRIED:
		return _deny("already_carried")
	if st == MAP_EXTRACTED:
		return _deny("already_extracted")
	if not bool(snap.get("altar_active", false)):
		return _deny("altar_inactive")
	return _allow()


static func can_extract(snap: Dictionary, peer_id: int, actor: Dictionary) -> Dictionary:
	var gate := actor_can_act(actor)
	if not bool(gate["ok"]):
		return gate
	if int(snap.get("state", -1)) != MissionState.RETURN_TO_DROP_POD:
		return _deny("wrong_mission_state")
	if String(snap.get("star_map_state", MAP_LOCKED)) != MAP_CARRIED:
		return _deny("star_map_not_carried")
	if int(snap.get("star_map_carrier", 0)) != peer_id:
		return _deny("not_star_map_carrier")
	return _allow()


# ==========================================================================
# The ship: seats, tasks, launch
# ==========================================================================

static func is_ship_state(state: int) -> bool:
	return SHIP_STATES.has(state)


static func is_flight_state(state: int) -> bool:
	return FLIGHT_STATES.has(state)


## A seat holds exactly one crew member. Sitting is refused while a sequence is
## already running, or the crew could leave and re-enter seats mid-launch.
static func can_take_seat(snap: Dictionary, peer_id: int, seat_id: String,
		actor: Dictionary) -> Dictionary:
	var gate := actor_can_act(actor)
	if not bool(gate["ok"]):
		return gate
	if not is_ship_state(int(snap.get("state", -1))):
		return _deny("wrong_mission_state")
	var seats: Dictionary = snap.get("seats", {})
	var holder := int(seats.get(seat_id, 0))
	if holder == peer_id:
		return _deny("already_seated_here")
	if holder != 0:
		return _deny("seat_occupied")
	if seat_of(snap, peer_id) != "":
		return _deny("already_seated_elsewhere")
	return _allow()


## Standing up. Allowed on the deck, refused mid-flight - the restraints are
## the fiction, but the real reason is that a player walking around during a
## scripted camera sequence has nowhere sensible to be.
static func can_leave_seat(snap: Dictionary, peer_id: int) -> Dictionary:
	if is_flight_state(int(snap.get("state", -1))):
		return _deny("restrained_in_flight")
	if seat_of(snap, peer_id) == "":
		return _deny("not_seated")
	return _allow()


## Which seat this peer is in, or "" for none.
static func seat_of(snap: Dictionary, peer_id: int) -> String:
	var seats: Dictionary = snap.get("seats", {})
	for seat_id in seats:
		if int(seats[seat_id]) == peer_id:
			return String(seat_id)
	return ""


static func can_complete_ship_task(snap: Dictionary, _peer_id: int, task_id: String,
		actor: Dictionary) -> Dictionary:
	var gate := actor_can_act(actor)
	if not bool(gate["ok"]):
		return gate
	if not is_ship_state(int(snap.get("state", -1))):
		return _deny("wrong_mission_state")
	if not GameConfig.SHIP_TASK_IDS.has(task_id):
		return _deny("unknown_ship_task")
	var done: Dictionary = snap.get("ship_tasks", {})
	if done.has(task_id):
		return _deny("task_already_done")
	return _allow()


static func ship_tasks_remaining(snap: Dictionary) -> Array:
	var done: Dictionary = snap.get("ship_tasks", {})
	var out: Array = []
	for task_id in GameConfig.SHIP_TASK_IDS:
		if not done.has(task_id):
			out.append(task_id)
	return out


## "Prime the reactor - engineering, by the spine".
##
## One string so every surface that names a station names its place too, and a
## station added without a location reads as its bare label rather than as
## "task_reactor - " with nothing after the dash.
static func ship_task_hint(task_id: String) -> String:
	var label := String(GameConfig.SHIP_TASK_LABELS.get(task_id, task_id))
	var where := String(GameConfig.SHIP_TASK_LOCATIONS.get(task_id, ""))
	if where.is_empty():
		return label
	return "%s - %s" % [label, where]


## The launch gate, and the reason the seats exist.
##
## `crew` is peer_id -> {"alive": bool, "downed": bool}. Every living crew
## member must be strapped in and every station must be green. A downed player
## does NOT block launch - otherwise one unconscious crew member could strand
## the ship forever with no way to revive them aboard.
static func can_launch(snap: Dictionary, peer_id: int, crew: Dictionary,
		actor: Dictionary) -> Dictionary:
	if peer_id != GameConfig.HOST_PEER_ID:
		return _deny("not_host")
	var gate := actor_can_act(actor)
	if not bool(gate["ok"]):
		return gate
	if int(snap.get("state", -1)) != MissionState.SHIP_IDLE:
		return _deny("wrong_mission_state")
	if not ship_tasks_remaining(snap).is_empty():
		return _deny("tasks_incomplete")
	var mission_id := String(snap.get("mission_id", ""))
	if not MissionCatalog.has_mission(mission_id):
		return _deny("no_destination")
	if not MissionCatalog.is_unlocked(mission_id, snap.get("completed_missions", [])):
		return _deny("destination_locked")
	if crew.is_empty():
		return _deny("no_crew")
	for other in crew:
		var c: Dictionary = crew[other]
		if bool(c.get("downed", false)):
			continue
		if seat_of(snap, int(other)) == "":
			return _deny("crew_not_seated")
	return _allow()


## Choosing where to fly. Any crew member may plot a course; only the host can
## pull the lever, which is the same split the mission terminal always had.
static func can_set_destination(snap: Dictionary, mission_id: String,
		actor: Dictionary) -> Dictionary:
	var gate := actor_can_act(actor)
	if not bool(gate["ok"]):
		return gate
	if int(snap.get("state", -1)) != MissionState.SHIP_IDLE:
		return _deny("wrong_mission_state")
	if not MissionCatalog.has_mission(mission_id):
		return _deny("unknown_destination")
	if not MissionCatalog.is_unlocked(mission_id, snap.get("completed_missions", [])):
		return _deny("destination_locked")
	return _allow()


# ==========================================================================
# Surface difficulty: locks, guards, hazard
# ==========================================================================

## Why a crystal cannot be taken yet, or "" when it is free. Presentation reads
## this for the prompt; can_pick_up_crystal enforces it.
static func crystal_lock(snap: Dictionary, crystal_id: String) -> String:
	var locks: Dictionary = snap.get("crystal_locks", {})
	var kind := String(locks.get(crystal_id, ""))
	if kind == "":
		return ""
	match kind:
		LOCK_GUARD:
			var down: Array = snap.get("guards_down", [])
			return "" if down.has(crystal_id) else LOCK_GUARD
		LOCK_HAZARD:
			return LOCK_HAZARD if bool(snap.get("hazard_online", false)) else ""
		_:
			return kind


## Fitting the power coupling clears the coupling lock on that crystal.
## Picking the coupling up. It takes the one inventory slot, which is the whole
## cost of the fetch: you cannot carry a crystal and the coupling at once.
static func can_take_coupling(snap: Dictionary, peer_id: int, actor: Dictionary) -> Dictionary:
	var gate := actor_can_act(actor)
	if not bool(gate["ok"]):
		return gate
	if not is_surface_state(int(snap.get("state", -1))):
		return _deny("wrong_mission_state")
	var carried: Dictionary = snap.get("crystals_carried", {})
	if carried.has(peer_id):
		return _deny("inventory_full")
	if bool(snap.get("coupling_taken", false)):
		return _deny("coupling_already_taken")
	# Nothing to fetch it for: every coupling lock on this mission is cleared.
	var locks: Dictionary = snap.get("crystal_locks", {})
	var needed := false
	for cid in locks:
		if crystal_lock(snap, String(cid)) == LOCK_COUPLING:
			needed = true
	if not needed:
		return _deny("nothing_needs_a_coupling")
	return _allow()


static func can_fit_coupling(snap: Dictionary, peer_id: int, crystal_id: String,
		actor: Dictionary) -> Dictionary:
	var gate := actor_can_act(actor)
	if not bool(gate["ok"]):
		return gate
	if not is_surface_state(int(snap.get("state", -1))):
		return _deny("wrong_mission_state")
	if crystal_lock(snap, crystal_id) != LOCK_COUPLING:
		return _deny("nothing_to_fit")
	var carried: Dictionary = snap.get("crystals_carried", {})
	if String(carried.get(peer_id, "")) != GameConfig.ITEM_COUPLING:
		return _deny("no_coupling_carried")
	return _allow()


static func can_shut_down_hazard(snap: Dictionary, _peer_id: int,
		actor: Dictionary) -> Dictionary:
	var gate := actor_can_act(actor)
	if not bool(gate["ok"]):
		return gate
	if not is_surface_state(int(snap.get("state", -1))):
		return _deny("wrong_mission_state")
	if not bool(snap.get("hazard_online", false)):
		return _deny("hazard_already_down")
	return _allow()


# ==========================================================================
# The Warden
# ==========================================================================

## Damage only lands while the boss is exposed. During BOSS_SHIELDED every shot
## is refused, which is what forces the crew to deal with the shield nodes.
static func boss_takes_damage(snap: Dictionary) -> bool:
	var phase := int(snap.get("boss_phase", BOSS_ASLEEP))
	return phase == BOSS_VOLLEY or phase == BOSS_ENRAGED


## How the Warden is sized to the crew it is actually fighting.
##
## This game is 1-4 players, and the Warden was tuned for 4. Measured against a
## solo run of the shipped build: the crew reaches the boss with 100 health and
## no one to revive them, faces a three-projectile volley every 2.6 s, and has
## to land 51 hits through a blaster that overheats after twelve. The automated
## playtest broke every shield node, took the boss to 525 of 900, and was
## downed - which alone is the end of the mission. A supported player count that
## cannot finish the game is the same class of defect as a launch lever nobody
## can reach; it is just less absolute.
##
## So the fight keeps its shape at every crew size and only changes its size:
## health and shield nodes scale down, and volleys come further apart, for a
## smaller crew. Nothing is removed - a solo player still has to break three
## nodes before the body can be hurt, which is the whole point of the phase.
const BOSS_CREW_SCALE: Array = [0.5, 0.7, 0.85, 1.0]


static func boss_scale(crew: int) -> float:
	var index: int = clampi(crew, 1, BOSS_CREW_SCALE.size()) - 1
	return float(BOSS_CREW_SCALE[index])


## Volleys come further apart against a smaller crew: one player cannot dodge
## four players' worth of incoming and has nobody to draw fire.
static func boss_volley_interval(crew: int, enraged: bool) -> float:
	var base: float = GameConfig.BOSS_ENRAGED_VOLLEY_INTERVAL if enraged \
		else GameConfig.BOSS_VOLLEY_INTERVAL
	return base * (2.0 - boss_scale(crew))


## How many hits a crystal guard takes before it dies, by crew size.
##
## The same argument as the Warden, one rung down. `GUARD_HITS_TO_KILL` is a
## flat 14, and a Sentinel that four players drop in three seconds each is a
## long solo fight in front of a crystal you cannot take until it is over. It
## matters more now than it used to: Nerava carries a guard, so this is the
## first enemy a new player has to actually beat rather than run past.
##
## Rounded UP, and floored well above zero, so a smaller crew never gets a guard
## that dies in one burst - the point of the lock is that it is a fight, not a
## formality. The floor is not arbitrary: at the boss curve alone a solo guard
## came to 7 hits and an automated run killed it in 2.6 seconds, which made the
## guarded trip only 2.7 seconds longer than the plain fetch beside it. A lock
## that changes the SHAPE of a trip but not its cost is barely a lock.
const GUARD_MIN_HITS: int = 8


static func guard_hits_to_kill(crew: int) -> int:
	return maxi(int(ceil(float(GameConfig.GUARD_HITS_TO_KILL) * boss_scale(crew))),
		GUARD_MIN_HITS)


## How many projectiles the Warden puts in a volley, by crew size.
##
## Measured across four solo runs of the shipped build: one win, three losses,
## every loss the same shape - downed in the exposed phase with the boss around
## 275 of 450. Scaling the boss's HEALTH down had already been done and did not
## fix it, because health is not what was killing the player. Three projectiles
## at 33 damage against 100 health is a down in three volleys, and one player
## cannot spread four players' worth of incoming across four bodies.
##
## So a smaller crew faces a smaller volley. The spread still exists at two -
## the point of a volley rather than a single shot is that it forces a decision
## about which way to go, and two projectiles still do that - and a full crew
## faces exactly what it faced before.
## Contact damage scales with the crew for exactly the reason everything else
## about the Warden does. Its health, its volley interval and the number of
## projectiles per volley are all sized to how many people are shooting back;
## the 18 a second it does for touching you was a flat number, so a solo player
## took the whole of a four-player crew's punishment alone. That was invisible
## for as long as the check that gates it could never pass (defect 71), and the
## moment it could, the enraged phase went from harmless to lethal in eleven
## seconds - measured, from full health, on the explorer driver.
static func boss_contact_damage(crew: int) -> int:
	return maxi(int(round(float(GameConfig.BOSS_CONTACT_DAMAGE) * boss_scale(crew))), 1)


const BOSS_VOLLEY_BY_CREW: Array = [1, 2, 3, 3]


static func boss_volley_projectiles(crew: int) -> int:
	var index: int = clampi(crew, 1, BOSS_VOLLEY_BY_CREW.size()) - 1
	return int(BOSS_VOLLEY_BY_CREW[index])


## The phase the Warden should be in for a given health fraction, given that its
## shield is already down. Kept separate from the node so the ladder is testable
## without spawning anything.
static func boss_phase_for(health_fraction: float, nodes_left: int) -> int:
	if health_fraction <= 0.0:
		return BOSS_DEAD
	if nodes_left > 0:
		return BOSS_SHIELDED
	return BOSS_ENRAGED if health_fraction <= GameConfig.BOSS_ENRAGE_FRACTION else BOSS_VOLLEY


static func can_break_shield_node(snap: Dictionary, node_id: String) -> Dictionary:
	if int(snap.get("state", -1)) != MissionState.BOSS_FIGHT:
		return _deny("wrong_mission_state")
	if int(snap.get("boss_phase", BOSS_ASLEEP)) != BOSS_SHIELDED:
		return _deny("shield_not_up")
	var nodes: Array = snap.get("boss_nodes", [])
	if not nodes.has(node_id):
		return _deny("node_already_down")
	return _allow()


# ==========================================================================
# Mission terminal (hub)
# ==========================================================================

static func can_start_expedition(snap: Dictionary, peer_id: int, actor: Dictionary) -> Dictionary:
	if peer_id != GameConfig.HOST_PEER_ID:
		return _deny("not_host")
	var gate := actor_can_act(actor)
	if not bool(gate["ok"]):
		return gate
	if int(snap.get("state", -1)) != MissionState.SHIP_IDLE:
		return _deny("wrong_mission_state")
	return _allow()


# ==========================================================================
# Failure condition
# ==========================================================================

## `players` is peer_id -> {"alive": bool, "downed": bool}.
## Mission failure requires that at least one player exists and every remaining
## connected player is downed. A player who DISCONNECTED is simply not in the
## dictionary, so a disconnect can never wedge the check.
static func should_fail(players: Dictionary) -> bool:
	if players.is_empty():
		return false
	for peer_id in players:
		var p: Dictionary = players[peer_id]
		if not bool(p.get("downed", false)):
			return false
	return true


# ==========================================================================
# Objective progression helpers
# ==========================================================================

## Given the snapshot after a successful mutation, returns the state the mission
## SHOULD be in, or -1 when no progression is warranted. GameManager still runs
## the result through is_valid_transition().
static func next_progress_state(snap: Dictionary) -> int:
	var state := int(snap.get("state", -1))
	match state:
		MissionState.FIND_TEMPLE:
			if bool(snap.get("temple_discovered", false)):
				return MissionState.FIND_CRYSTALS
		MissionState.FIND_CRYSTALS:
			var pedestals: Dictionary = snap.get("pedestals", {})
			var in_world: Array = snap.get("crystals_in_world", [])
			if pedestals.size() > 0 or in_world.is_empty():
				return MissionState.ACTIVATE_ALTAR
		MissionState.ACTIVATE_ALTAR:
			if bool(snap.get("altar_active", false)):
				return MissionState.RETRIEVE_STAR_MAP
		MissionState.RETRIEVE_STAR_MAP:
			# Taking the map wakes the Warden. The run to the pod is not
			# available until it is dead - that is the whole point of it.
			if String(snap.get("star_map_state", MAP_LOCKED)) == MAP_CARRIED:
				return MissionState.BOSS_FIGHT
		MissionState.BOSS_FIGHT:
			if int(snap.get("boss_phase", BOSS_ASLEEP)) == BOSS_DEAD:
				return MissionState.RETURN_TO_DROP_POD
		MissionState.RETURN_TO_DROP_POD:
			if bool(snap.get("extracted", false)):
				return MissionState.MISSION_COMPLETE
	return -1


## A fresh, mutable Array copy of the crystal id list. Never hand out the
## constant itself: const collections are shared and mutating one would corrupt
## every future snapshot.
static func _crystal_list() -> Array:
	var out: Array = []
	for cid in GameConfig.ALL_CRYSTAL_IDS:
		out.append(cid)
	return out


static func _allow() -> Dictionary:
	return {"ok": true, "reason": ""}


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
