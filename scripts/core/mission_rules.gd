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
	HUB_IDLE,
	LOBBY_READY,
	TRANSITIONING_TO_HUB,
	TRANSITIONING_TO_NERAVA,
	FIND_TEMPLE,
	FIND_CRYSTALS,
	ACTIVATE_ALTAR,
	RETRIEVE_STAR_MAP,
	RETURN_TO_DROP_POD,
	MISSION_COMPLETE,
	MISSION_FAILED,
	RETURNING_TO_LOBBY,
}

## Star Map lifecycle. "locked" until the altar opens; "extracted" is terminal.
const MAP_LOCKED := "locked"
const MAP_AVAILABLE := "available"
const MAP_CARRIED := "carried"
const MAP_DROPPED := "dropped"
const MAP_EXTRACTED := "extracted"

const OBJECTIVE_TEXT: Dictionary = {
	MissionState.HUB_IDLE: "Use the Mission Terminal to begin the expedition.",
	MissionState.LOBBY_READY: "Waiting for the host to start the session.",
	MissionState.TRANSITIONING_TO_HUB: "Boarding the Wayfinder Station...",
	MissionState.TRANSITIONING_TO_NERAVA: "Descending to Nerava...",
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
		MissionState.TRANSITIONING_TO_HUB,
	],
	MissionState.TRANSITIONING_TO_HUB: [
		MissionState.HUB_IDLE,
		MissionState.RETURNING_TO_LOBBY,
	],
	MissionState.HUB_IDLE: [
		MissionState.TRANSITIONING_TO_NERAVA,
		MissionState.RETURNING_TO_LOBBY,
	],
	MissionState.TRANSITIONING_TO_NERAVA: [
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
		MissionState.TRANSITIONING_TO_NERAVA,
		MissionState.RETURNING_TO_LOBBY,
	],
	MissionState.RETURNING_TO_LOBBY: [
		MissionState.LOBBY_READY,
	],
}

## States in which players are physically on Nerava with the puzzle live.
const NERAVA_STATES: Array = [
	MissionState.FIND_TEMPLE,
	MissionState.FIND_CRYSTALS,
	MissionState.ACTIVATE_ALTAR,
	MissionState.RETRIEVE_STAR_MAP,
	MissionState.RETURN_TO_DROP_POD,
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


static func is_nerava_state(state: int) -> bool:
	return NERAVA_STATES.has(state)


## A blank snapshot for a fresh Nerava descent. Used both by GameManager on
## reset and by tests as a known-good starting point.
static func fresh_snapshot(epoch: int) -> Dictionary:
	return {
		"epoch": epoch,
		"state": MissionState.TRANSITIONING_TO_NERAVA,
		"crystals_in_world": _crystal_list(),
		"crystals_carried": {},        # peer_id -> crystal_id
		"pedestals": {},               # pedestal_id -> crystal_id placed
		"altar_active": false,
		"star_map_state": MAP_LOCKED,
		"star_map_carrier": 0,
		"guardian_spawned": false,
		"temple_discovered": false,
		"extracted": false,
	}


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
	if not is_nerava_state(int(snap.get("state", -1))):
		return _deny("wrong_mission_state")
	if not GameConfig.ALL_CRYSTAL_IDS.has(crystal_id):
		return _deny("unknown_crystal")
	var in_world: Array = snap.get("crystals_in_world", [])
	if not in_world.has(crystal_id):
		return _deny("crystal_not_available")
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
	if not is_nerava_state(int(snap.get("state", -1))):
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
	if not is_nerava_state(int(snap.get("state", -1))):
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
# Mission terminal (hub)
# ==========================================================================

static func can_start_expedition(snap: Dictionary, peer_id: int, actor: Dictionary) -> Dictionary:
	if peer_id != GameConfig.HOST_PEER_ID:
		return _deny("not_host")
	var gate := actor_can_act(actor)
	if not bool(gate["ok"]):
		return gate
	if int(snap.get("state", -1)) != MissionState.HUB_IDLE:
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
			if String(snap.get("star_map_state", MAP_LOCKED)) == MAP_CARRIED:
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
