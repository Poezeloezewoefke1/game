extends Node
## Authoritative mission and session state. Autoload name: GameManager
##
## OWNERSHIP
##   The host owns `snapshot`. Clients hold a mirror that is replaced wholesale
##   by `_rpc_snapshot`. There is exactly ONE authoritative copy of every mission
##   fact (which crystals exist, who carries what, whether the altar is open) and
##   it lives here. Interactables and UI READ the snapshot; they never keep a
##   second copy that could drift.
##
## SESSION EPOCH
##   Every fresh lobby/hub/descent/retry bumps `session_epoch`. Every critical
##   client request carries the epoch it was made under, and the host rejects
##   any request whose epoch is not current. That single mechanism kills stale
##   requests from a previous mission, a superseded scene, or a replayed packet.
##
## DECISION LOGIC lives in MissionRules (pure, unit-tested). This node applies
## decisions and replicates them; it must not re-implement a rule.

signal snapshot_changed(snap: Dictionary)
signal mission_state_changed(state: int)
signal objective_changed(text: String)
signal mission_ended(victory: bool)
## Transient, human-readable feedback for the local player ("Inventory full").
signal notice(text: String)

const MS := MissionRules.MissionState

var session_epoch: int = 0
var snapshot: Dictionary = {}

var _interact_limiter: RateLimiter
var _revive_limiter: RateLimiter

## Host only: peer_id -> {"start": float, "target": int} for in-flight revives.
var _revives: Dictionary = {}


func _ready() -> void:
	_interact_limiter = RateLimiter.new(
		GameConfig.RATE_LIMIT_INTERACT, GameConfig.RATE_LIMIT_INTERACT,
		GameConfig.RATE_LIMIT_ABUSE_MULTIPLIER, GameConfig.RATE_LIMIT_ABUSE_WINDOW)
	_revive_limiter = RateLimiter.new(
		GameConfig.RATE_LIMIT_REVIVE, GameConfig.RATE_LIMIT_REVIVE,
		GameConfig.RATE_LIMIT_ABUSE_MULTIPLIER, GameConfig.RATE_LIMIT_ABUSE_WINDOW)
	snapshot = MissionRules.fresh_snapshot(0)
	snapshot["state"] = MS.LOBBY_READY
	# Subscribed here rather than in main.gd so the mission flow works in any
	# host context - including the headless test runner, which has no app shell.
	SceneManager.barrier_completed.connect(_on_barrier_completed)
	set_process(true)


func _on_barrier_completed(scene_key: String, _transition_id: int) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	host_on_scene_barrier_completed(scene_key)


func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_host_tick_revives(delta)


# ==========================================================================
# Read-only queries (valid on host and client)
# ==========================================================================

func mission_state() -> int:
	return int(snapshot.get("state", MS.LOBBY_READY))


func objective_text() -> String:
	return MissionRules.objective_text(mission_state())


func star_map_carrier() -> int:
	return int(snapshot.get("star_map_carrier", 0))


func star_map_state() -> String:
	return String(snapshot.get("star_map_state", MissionRules.MAP_LOCKED))


func carried_crystal_of(peer_id: int) -> String:
	var carried: Dictionary = snapshot.get("crystals_carried", {})
	return String(carried.get(peer_id, ""))


func is_crystal_in_world(crystal_id: String) -> bool:
	var in_world: Array = snapshot.get("crystals_in_world", [])
	return in_world.has(crystal_id)


func pedestal_content(pedestal_id: String) -> String:
	var pedestals: Dictionary = snapshot.get("pedestals", {})
	return String(pedestals.get(pedestal_id, ""))


func is_altar_active() -> bool:
	return bool(snapshot.get("altar_active", false))


func placed_pedestal_count() -> int:
	var pedestals: Dictionary = snapshot.get("pedestals", {})
	return pedestals.size()


func is_mission_over() -> bool:
	var s := mission_state()
	return s == MS.MISSION_COMPLETE or s == MS.MISSION_FAILED


## True while the session is still gathering players in the lobby, regardless
## of how many have joined.
func host_is_in_lobby() -> bool:
	return mission_state() == MS.LOBBY_READY


## True when a new player could actually be admitted right now.
func host_accepts_new_players() -> bool:
	return host_is_in_lobby() and not LobbyManager.is_full()


func host_accepts_lobby_input() -> bool:
	return mission_state() == MS.LOBBY_READY


# ==========================================================================
# Host: session lifecycle
# ==========================================================================

func host_begin_lobby() -> void:
	if not _is_host():
		return
	session_epoch += 1
	snapshot = MissionRules.fresh_snapshot(session_epoch)
	snapshot["state"] = MS.LOBBY_READY
	_revives.clear()
	_interact_limiter.clear()
	_revive_limiter.clear()
	Logx.info("mission", "Lobby ready (epoch %d)" % session_epoch)
	_host_publish()


## Lobby -> Wayfinder Station Hub. Host only.
func host_start_session() -> bool:
	if not _is_host():
		return false
	if mission_state() != MS.LOBBY_READY:
		Logx.warn("mission", "start_session in state %s" % MissionRules.state_name(mission_state()))
		return false
	session_epoch += 1
	_host_reset_facts()
	if not _host_set_state(MS.TRANSITIONING_TO_HUB):
		return false
	await SpawnManager.host_clear_all()
	LobbyManager.host_clear_ready_flags()
	var started: bool = await SceneManager.host_transition_to(GameConfig.SCENE_HUB)
	return started


## Hub Mission Terminal -> Nerava. Host only (validated for peer 1).
func host_start_expedition() -> bool:
	if not _is_host():
		return false
	if mission_state() != MS.HUB_IDLE:
		return false
	session_epoch += 1
	_host_reset_facts()
	if not _host_set_state(MS.TRANSITIONING_TO_NERAVA):
		return false
	await SpawnManager.host_clear_all()
	var started: bool = await SceneManager.host_transition_to(GameConfig.SCENE_NERAVA)
	return started


## Retry after failure. Host only. Full reset of every mission fact.
func host_retry_mission() -> bool:
	if not _is_host():
		return false
	if mission_state() != MS.MISSION_FAILED:
		return false
	session_epoch += 1
	_host_reset_facts()
	if not _host_set_state(MS.TRANSITIONING_TO_NERAVA):
		return false
	await SpawnManager.host_clear_all()
	_revives.clear()
	Logx.info("mission", "Retry (epoch %d)" % session_epoch)
	var started: bool = await SceneManager.host_transition_to(GameConfig.SCENE_NERAVA)
	return started


## Return everyone to the lobby from any state. Host only.
func host_return_to_lobby() -> bool:
	if not _is_host():
		return false
	if not _host_set_state(MS.RETURNING_TO_LOBBY):
		return false
	await SpawnManager.host_clear_all()
	_revives.clear()
	session_epoch += 1
	_host_reset_facts()
	if not _host_set_state(MS.LOBBY_READY):
		return false
	LobbyManager.host_clear_ready_flags()
	var started: bool = await SceneManager.host_transition_to(GameConfig.SCENE_LOBBY)
	return started


## Unrecoverable host-side problem: tell everyone and unwind cleanly.
func host_abort_session(reason: String) -> void:
	if not _is_host():
		return
	Logx.error("mission", "Aborting session: %s" % reason)
	_rpc_notice.rpc(reason)
	NetworkManager.shutdown(reason)


# ==========================================================================
# Host: peer lifecycle
# ==========================================================================

func host_handle_peer_left(peer_id: int) -> void:
	if not _is_host():
		return
	var changed := false

	# 1. A disconnecting carrier must not take the Star Map out of the world.
	if star_map_state() == MissionRules.MAP_CARRIED and star_map_carrier() == peer_id:
		_host_drop_star_map("carrier_disconnected")
		changed = true

	# 2. A disconnecting crystal carrier would otherwise SOFTLOCK the mission -
	#    the crystal would exist nowhere. Return it to its world pedestal spot.
	var carried: Dictionary = snapshot.get("crystals_carried", {})
	if carried.has(peer_id):
		var cid := String(carried[peer_id])
		carried.erase(peer_id)
		var in_world: Array = snapshot["crystals_in_world"]
		if not in_world.has(cid):
			in_world.append(cid)
		Logx.info("mission", "Returned %s to the world (peer %d left)" % [cid, peer_id])
		changed = true

	# 3. Cancel revives in either direction.
	if _revives.erase(peer_id):
		changed = true
	for reviver in _revives.keys():
		if int((_revives[reviver] as Dictionary)["target"]) == peer_id:
			_revives.erase(reviver)
			changed = true

	_interact_limiter.forget(peer_id)
	_revive_limiter.forget(peer_id)
	SpawnManager.host_despawn_player(peer_id)

	if changed:
		_host_publish()
	# A disconnect can complete a failure condition (last standing player left)
	# or clear one (the only downed player left). Always re-evaluate.
	host_evaluate_failure()


# ==========================================================================
# Host: mission progression events
# ==========================================================================

func host_report_temple_discovered() -> void:
	if not _is_host():
		return
	if bool(snapshot.get("temple_discovered", false)):
		return
	if mission_state() != MS.FIND_TEMPLE:
		return
	snapshot["temple_discovered"] = true
	_host_progress_and_publish()


## Called by SceneManager's barrier completion handler once everybody is in.
func host_on_scene_barrier_completed(scene_key: String) -> void:
	if not _is_host():
		return
	match scene_key:
		GameConfig.SCENE_HUB:
			SpawnManager.host_spawn_all_players()
			_host_set_state(MS.HUB_IDLE)
		GameConfig.SCENE_NERAVA:
			SpawnManager.host_spawn_all_players()
			_host_set_state(MS.FIND_TEMPLE)
		GameConfig.SCENE_LOBBY:
			pass
		_:
			pass
	_host_publish()


# ==========================================================================
# Host: interaction requests
# ==========================================================================

## Entry point used by the local player on ANY peer. On the host it validates
## directly; on a client it forwards to the host.
func request_interact(object_id: String) -> void:
	if object_id.is_empty():
		return
	if _is_host():
		host_handle_interact_request(GameConfig.HOST_PEER_ID, object_id, session_epoch)
	else:
		_rpc_request_interact.rpc_id(GameConfig.HOST_PEER_ID, object_id, session_epoch)


## CLIENT -> HOST.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_interact(object_id: String, epoch: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0 or NetworkManager.is_peer_leaving(sender):
		return
	if not _interact_limiter.allow(sender):
		Logx.reject("mission", sender, "interact_rate_limited")
		if _interact_limiter.is_abusive(sender):
			NetworkManager.host_kick_peer(sender, "Too many interaction requests.")
		return
	host_handle_interact_request(sender, object_id, epoch)


## THE single validation path for any interaction, whoever asked. The local host
## path, the client RPC path and the tests all funnel through here, so there is
## exactly one place where an interaction can be authorised.
func host_handle_interact_request(peer_id: int, object_id: String, epoch: int) -> void:
	if epoch != session_epoch:
		Logx.reject("mission", peer_id, "interact_stale_epoch")
		return
	if not LobbyManager.has_player(peer_id):
		Logx.reject("mission", peer_id, "interact_not_a_player")
		return
	var target: Node = SpawnManager.find_interactable(object_id)
	if target == null:
		Logx.reject("mission", peer_id, "interact_unknown_object:" + object_id)
		return
	var player: Node = SpawnManager.player_node(peer_id)
	if player == null:
		Logx.reject("mission", peer_id, "interact_no_player_node")
		return
	if not _host_within_reach(player, target):
		Logx.reject("mission", peer_id, "interact_out_of_range")
		return
	if not _host_has_line_of_sight(player, target):
		Logx.reject("mission", peer_id, "interact_no_line_of_sight")
		return
	if not target.has_method("host_validate_and_apply_interaction"):
		Logx.reject("mission", peer_id, "interact_not_interactable")
		return
	var result: Dictionary = target.host_validate_and_apply_interaction(peer_id, player)
	if not bool(result.get("ok", false)):
		var reason := String(result.get("reason", "denied"))
		Logx.reject("mission", peer_id, "interact:" + reason)
		_host_notify(peer_id, _reason_to_message(reason))


# ==========================================================================
# Host: authoritative mission mutations (called by interactables)
# ==========================================================================

func host_apply_crystal_pickup(peer_id: int, crystal_id: String) -> void:
	var in_world: Array = snapshot["crystals_in_world"]
	in_world.erase(crystal_id)
	var carried: Dictionary = snapshot["crystals_carried"]
	carried[peer_id] = crystal_id
	Logx.info("mission", "peer %d picked up %s" % [peer_id, crystal_id])
	_host_progress_and_publish()


func host_apply_crystal_placement(peer_id: int, pedestal_id: String, crystal_id: String) -> void:
	var carried: Dictionary = snapshot["crystals_carried"]
	carried.erase(peer_id)
	var pedestals: Dictionary = snapshot["pedestals"]
	pedestals[pedestal_id] = crystal_id
	Logx.info("mission", "peer %d placed %s in %s" % [peer_id, crystal_id, pedestal_id])
	if MissionRules.altar_should_activate(snapshot):
		snapshot["altar_active"] = true
		snapshot["star_map_state"] = MissionRules.MAP_AVAILABLE
		Logx.info("mission", "Altar activated; Star Map available")
	_host_progress_and_publish()


func host_apply_star_map_pickup(peer_id: int) -> void:
	snapshot["star_map_state"] = MissionRules.MAP_CARRIED
	snapshot["star_map_carrier"] = peer_id
	Logx.info("mission", "peer %d took the Star Map" % peer_id)
	SpawnManager.host_clear_dropped_star_maps()
	# Exactly one Sentinel, ever, per descent.
	if not bool(snapshot.get("guardian_spawned", false)):
		snapshot["guardian_spawned"] = true
		SpawnManager.host_spawn_guardian()
	_host_progress_and_publish()


func host_apply_extraction(peer_id: int) -> void:
	snapshot["extracted"] = true
	snapshot["star_map_state"] = MissionRules.MAP_EXTRACTED
	snapshot["star_map_carrier"] = 0
	Logx.info("mission", "peer %d extracted with the Star Map" % peer_id)
	_host_progress_and_publish()
	if mission_state() == MS.MISSION_COMPLETE:
		SpawnManager.host_clear_hostiles()
		mission_ended.emit(true)
		_rpc_mission_ended.rpc(true)


# ==========================================================================
# Host: health, downed, revive
# ==========================================================================

func host_on_player_downed(peer_id: int) -> void:
	if not _is_host():
		return
	Logx.info("mission", "peer %d is downed" % peer_id)
	# Drop the Star Map exactly once - the guard is the state, not the caller,
	# so repeated damage or repeated downed events cannot duplicate the drop.
	if star_map_state() == MissionRules.MAP_CARRIED and star_map_carrier() == peer_id:
		_host_drop_star_map("carrier_downed")
		_host_publish()
	# Cancel a revive this player was performing, and any revive targeting them
	# is cancelled too (they are no longer a valid target of a *completed* one).
	_revives.erase(peer_id)
	host_evaluate_failure()


func host_on_player_revived(peer_id: int) -> void:
	if not _is_host():
		return
	Logx.info("mission", "peer %d revived" % peer_id)
	for reviver in _revives.keys():
		if int((_revives[reviver] as Dictionary)["target"]) == peer_id:
			_revives.erase(reviver)


func host_evaluate_failure() -> void:
	if not _is_host():
		return
	if not MissionRules.is_nerava_state(mission_state()):
		return
	var players: Dictionary = SpawnManager.host_player_liveness()
	if players.is_empty():
		return
	if not MissionRules.should_fail(players):
		return
	Logx.info("mission", "All players downed - mission failed")
	if _host_set_state(MS.MISSION_FAILED):
		SpawnManager.host_clear_hostiles()
		_revives.clear()
		_host_publish()
		mission_ended.emit(false)
		_rpc_mission_ended.rpc(false)


## Local entry point for "hold E on a downed teammate".
func request_revive_start(target_peer: int) -> void:
	if _is_host():
		_host_revive_start(GameConfig.HOST_PEER_ID, target_peer, session_epoch)
	else:
		_rpc_revive_start.rpc_id(GameConfig.HOST_PEER_ID, target_peer, session_epoch)


func request_revive_stop() -> void:
	if _is_host():
		_host_revive_stop(GameConfig.HOST_PEER_ID)
	else:
		_rpc_revive_stop.rpc_id(GameConfig.HOST_PEER_ID)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_revive_start(target_peer: int, epoch: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0 or NetworkManager.is_peer_leaving(sender):
		return
	if not _revive_limiter.allow(sender):
		Logx.reject("revive", sender, "rate_limited")
		if _revive_limiter.is_abusive(sender):
			NetworkManager.host_kick_peer(sender, "Too many revive requests.")
		return
	_host_revive_start(sender, target_peer, epoch)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_revive_stop() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	_host_revive_stop(sender)


func _host_revive_start(reviver: int, target_peer: int, epoch: int) -> void:
	if epoch != session_epoch:
		Logx.reject("revive", reviver, "stale_epoch")
		return
	if reviver == target_peer:
		Logx.reject("revive", reviver, "self_revive")
		return
	if _revives.has(reviver):
		return  # already reviving; idempotent
	var check := _host_revive_pair_valid(reviver, target_peer)
	if not bool(check["ok"]):
		Logx.reject("revive", reviver, String(check["reason"]))
		return
	_revives[reviver] = {"elapsed": 0.0, "target": target_peer}
	_host_set_revive_progress(target_peer, 0.0, true)


func _host_revive_stop(reviver: int) -> void:
	var entry: Variant = _revives.get(reviver)
	if entry == null:
		return
	var target := int((entry as Dictionary)["target"])
	_revives.erase(reviver)
	if not _any_reviver_for(target):
		_host_set_revive_progress(target, 0.0, false)


func _any_reviver_for(target_peer: int) -> bool:
	for reviver in _revives:
		if int((_revives[reviver] as Dictionary)["target"]) == target_peer:
			return true
	return false


func _host_revive_pair_valid(reviver: int, target_peer: int) -> Dictionary:
	if not LobbyManager.has_player(reviver) or not LobbyManager.has_player(target_peer):
		return {"ok": false, "reason": "unknown_peer"}
	var a: Node = SpawnManager.player_node(reviver)
	var b: Node = SpawnManager.player_node(target_peer)
	if a == null or b == null:
		return {"ok": false, "reason": "missing_player_node"}
	if not bool(a.get("is_alive")) or bool(a.get("is_downed")):
		return {"ok": false, "reason": "reviver_not_able"}
	if not bool(b.get("is_downed")):
		return {"ok": false, "reason": "target_not_downed"}
	if _authoritative_position(a).distance_to(_authoritative_position(b)) > GameConfig.REVIVE_MAX_DISTANCE:
		return {"ok": false, "reason": "too_far"}
	if not _host_clear_line(a, b):
		return {"ok": false, "reason": "no_line_of_sight"}
	return {"ok": true, "reason": ""}


func _host_tick_revives(delta: float) -> void:
	if _revives.is_empty():
		return
	for reviver in _revives.keys():
		var entry: Dictionary = _revives[reviver]
		var target := int(entry["target"])
		var check := _host_revive_pair_valid(reviver, target)
		if not bool(check["ok"]):
			Logx.debug("revive", "cancelled %d->%d: %s" % [reviver, target, check["reason"]])
			_host_revive_stop(reviver)
			continue
		entry["elapsed"] = float(entry["elapsed"]) + delta
		_revives[reviver] = entry
		var progress: float = clampf(float(entry["elapsed"]) / GameConfig.REVIVE_DURATION, 0.0, 1.0)
		_host_set_revive_progress(target, progress, true)
		if float(entry["elapsed"]) >= GameConfig.REVIVE_DURATION:
			# Resolve deterministically: the FIRST reviver to reach full duration
			# wins; every other revive targeting this player is cancelled by
			# host_on_player_revived(), so a race cannot double-revive.
			var target_node: Node = SpawnManager.player_node(target)
			if target_node != null and target_node.has_method("host_revive"):
				target_node.host_revive()
			_revives.erase(reviver)
			_host_set_revive_progress(target, 0.0, false)


## Revive progress rides the player's host-authority StateSync rather than an
## RPC: an RPC here would be ~60 reliable packets per second per revive.
func _host_set_revive_progress(target_peer: int, progress: float, active: bool) -> void:
	var node: Node = SpawnManager.player_node(target_peer)
	if node != null and node.has_method("host_set_revive_progress"):
		node.host_set_revive_progress(clampf(progress, 0.0, 1.0), active)


# ==========================================================================
# Host: internal helpers
# ==========================================================================

func _host_drop_star_map(reason: String) -> void:
	if star_map_state() != MissionRules.MAP_CARRIED:
		return
	var carrier := star_map_carrier()
	var drop_position := Vector3.ZERO
	var node: Node = SpawnManager.player_node(carrier)
	if node != null:
		drop_position = _authoritative_position(node)
	else:
		drop_position = SpawnManager.fallback_drop_position()
	snapshot["star_map_state"] = MissionRules.MAP_DROPPED
	snapshot["star_map_carrier"] = 0
	SpawnManager.host_spawn_dropped_star_map(drop_position)
	Logx.info("mission", "Star Map dropped (%s) at %s" % [reason, str(drop_position)])


## Wipes every mission fact back to its starting value while KEEPING the current
## state, so the caller can then make exactly one validated transition out of it.
## This is the single choke point that guarantees a replay starts clean: there is
## no path that resets some facts and forgets others.
func _host_reset_facts() -> void:
	var current := mission_state()
	snapshot = MissionRules.fresh_snapshot(session_epoch)
	snapshot["state"] = current


func _host_set_state(next_state: int, force: bool = false) -> bool:
	var current := mission_state()
	if force:
		snapshot["state"] = next_state
		return true
	if not MissionRules.is_valid_transition(current, next_state):
		Logx.error("mission", "Illegal transition %s -> %s" % [
			MissionRules.state_name(current), MissionRules.state_name(next_state)])
		return false
	snapshot["state"] = next_state
	Logx.info("mission", "State -> %s" % MissionRules.state_name(next_state))
	return true


func _host_progress_and_publish() -> void:
	# Progression may cascade (placing the last crystal can move
	# FIND_CRYSTALS -> ACTIVATE_ALTAR -> RETRIEVE_STAR_MAP in one event).
	var guard := 0
	while guard < 8:
		guard += 1
		var next := MissionRules.next_progress_state(snapshot)
		if next < 0:
			break
		if not _host_set_state(next):
			break
	_host_publish()


func _host_publish() -> void:
	snapshot["epoch"] = session_epoch
	_emit_local()
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_rpc_snapshot.rpc(snapshot)


func _host_within_reach(player: Node, target: Node) -> bool:
	if not (player is Node3D) or not (target is Node3D):
		return false
	# authoritative_position() is the RAW replicated value. Using the smoothed
	# visual transform here would make range checks depend on interpolation.
	var a: Vector3 = _authoritative_position(player)
	var b: Vector3 = (target as Node3D).global_position
	var flat := Vector2(a.x - b.x, a.z - b.z).length()
	var vertical: float = absf(a.y - b.y)
	return flat <= GameConfig.INTERACT_VALIDATE_DISTANCE \
		and vertical <= GameConfig.INTERACT_VALIDATE_HEIGHT


func _host_has_line_of_sight(player: Node, target: Node) -> bool:
	if target.has_method("requires_line_of_sight") and not target.requires_line_of_sight():
		return true
	return _host_clear_line(player, target)


## Raycast between two nodes against world geometry only.
func _host_clear_line(a: Node, b: Node) -> bool:
	if not (a is Node3D) or not (b is Node3D):
		return false
	var from: Vector3 = _authoritative_position(a) + Vector3.UP * 1.2
	var to: Vector3 = _authoritative_position(b) + Vector3.UP * 0.6
	var space := (a as Node3D).get_world_3d().direct_space_state
	if space == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = GameConfig.LAYER_WORLD
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	return hit.is_empty()


## Raw replicated position for players; plain transform for static objects.
func _authoritative_position(node: Node) -> Vector3:
	if node != null and node.has_method("authoritative_position"):
		return node.authoritative_position()
	if node is Node3D:
		return (node as Node3D).global_position
	return Vector3.ZERO


func _host_notify(peer_id: int, message: String) -> void:
	if message.is_empty():
		return
	if peer_id == GameConfig.HOST_PEER_ID:
		notice.emit(message)
	elif NetworkManager.is_peer_connected(peer_id):
		_rpc_notice.rpc_id(peer_id, message)


static func _reason_to_message(reason: String) -> String:
	match reason:
		"inventory_full": return "Inventory Full - Place Your Current Crystal First"
		"wrong_crystal": return "This pedestal needs a different Crystal"
		"no_crystal_carried": return "Bring a Power Crystal"
		"pedestal_already_active": return "This pedestal is already powered"
		"shield_active", "altar_inactive": return "Star Map Shield Active"
		"star_map_not_carried", "not_star_map_carrier": return "Star Map Required for Extraction"
		"actor_downed": return "You are down - a teammate must revive you"
		"not_host": return "Only the host can begin the expedition"
		"crystal_not_available", "crystal_already_carried": return "That Crystal is already taken"
		_: return ""


func _is_host() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


# ==========================================================================
# Replication
# ==========================================================================

## HOST -> CLIENT. Wholesale replacement; the client never merges.
@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot(snap: Dictionary) -> void:
	if multiplayer.is_server():
		return
	if int(snap.get("epoch", -1)) < int(snapshot.get("epoch", 0)):
		# Out-of-order or replayed snapshot from a superseded session.
		Logx.warn("mission", "Dropped stale snapshot")
		return
	snapshot = snap
	session_epoch = int(snap.get("epoch", session_epoch))
	_emit_local()


@rpc("authority", "call_remote", "reliable")
func _rpc_notice(message: String) -> void:
	if multiplayer.is_server():
		return
	notice.emit(message)


@rpc("authority", "call_remote", "reliable")
func _rpc_mission_ended(victory: bool) -> void:
	if multiplayer.is_server():
		return
	mission_ended.emit(victory)


func client_set_epoch(epoch: int) -> void:
	if multiplayer.is_server():
		return
	session_epoch = epoch


var _last_emitted_state: int = -1

func _emit_local() -> void:
	snapshot_changed.emit(snapshot)
	var s := mission_state()
	if s != _last_emitted_state:
		_last_emitted_state = s
		mission_state_changed.emit(s)
		objective_changed.emit(MissionRules.objective_text(s))


# ==========================================================================
# Teardown
# ==========================================================================

func local_teardown() -> void:
	_revives.clear()
	if _interact_limiter != null:
		_interact_limiter.clear()
	if _revive_limiter != null:
		_revive_limiter.clear()
	session_epoch = 0
	snapshot = MissionRules.fresh_snapshot(0)
	snapshot["state"] = MS.LOBBY_READY
	_last_emitted_state = -1
	_emit_local()
