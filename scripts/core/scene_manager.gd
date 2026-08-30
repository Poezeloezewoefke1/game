extends Node
## Owns what is currently on screen, and the host-driven scene readiness
## barrier. Autoload name: SceneManager
##
## WHY A CUSTOM SWAP INSTEAD OF change_scene_to_file()
##   change_scene_to_file() is deferred to the end of the frame and gives no
##   hook for "the new scene is fully live". A networked barrier needs an exact
##   moment to acknowledge, and MultiplayerSpawner requires the spawner's node
##   path to be byte-identical on every peer. We therefore mount every scene at
##   the fixed path /root/Main/SceneRoot/Stage, whatever the scene is.
##
## THE BARRIER
##   1. Host picks a new transition id and broadcasts the target scene.
##   2. Every peer (host included) mounts the scene, then acknowledges.
##   3. The host completes the barrier when all expected peers have acked, or
##      when SCENE_TRANSITION_TIMEOUT elapses - late peers are then disconnected
##      rather than being left in an inconsistent world.
##   Acks carry the transition id AND the session epoch, so an ack from a stale
##   session or a superseded transition is rejected instead of releasing the
##   barrier early.

signal scene_changed(scene_key: String)
signal barrier_completed(scene_key: String, transition_id: int)
signal barrier_progress(ready_count: int, expected_count: int)
signal transition_started(scene_key: String)

## Fixed mount-point name. Never change this without bumping PROTOCOL_VERSION:
## it is part of every replicated node path.
const STAGE_NODE_NAME: StringName = &"Stage"

var current_scene_key: String = ""

var scene_root: Node = null
var ui_layer: CanvasLayer = null

var _transition_id: int = 0
var _barrier_active: bool = false
var _barrier_scene_key: String = ""
## peer_id -> true once acknowledged (host only).
var _acks: Dictionary = {}
var _expected: Array = []
var _barrier_timer: float = 0.0

var _ack_limiter: RateLimiter
## Bumped on every mount. A mount that finds the generation has moved on while it
## was awaiting knows a newer transition superseded it and bails out.
var _load_generation: int = 0


func _ready() -> void:
	_ack_limiter = RateLimiter.new(
		GameConfig.RATE_LIMIT_SCENE_ACK, GameConfig.RATE_LIMIT_SCENE_ACK,
		GameConfig.RATE_LIMIT_ABUSE_MULTIPLIER, GameConfig.RATE_LIMIT_ABUSE_WINDOW)
	set_process(true)


func _process(delta: float) -> void:
	if not _barrier_active:
		return
	if not multiplayer.is_server():
		return
	_barrier_timer -= delta
	if _barrier_timer <= 0.0:
		_timeout_barrier()


# ==========================================================================
# Wiring
# ==========================================================================

## Called once by main.gd. Kept explicit rather than searched for, so the whole
## UI/scene mounting contract is visible in one place.
func bind_roots(p_scene_root: Node, p_ui_layer: CanvasLayer) -> void:
	scene_root = p_scene_root
	ui_layer = p_ui_layer


func current_stage() -> Node:
	# is_instance_valid, not `== null`: a freed Node reference in Godot 4 is a
	# "previously freed" object that compares unequal to null and crashes on
	# access. This matters during teardown and between test sessions.
	if not is_instance_valid(scene_root):
		return null
	return scene_root.get_node_or_null(NodePath(STAGE_NODE_NAME))


func is_in_gameplay_scene() -> bool:
	return GameConfig.GAMEPLAY_SCENES.has(current_scene_key)


# ==========================================================================
# Local (offline / non-barriered) navigation
# ==========================================================================

## Used for menu-level navigation that has no networked meaning. Never use this
## for gameplay levels while a session is live - go through host_transition_to.
func local_goto(scene_key: String) -> void:
	if not GameConfig.is_valid_scene_key(scene_key):
		Logx.error("scene", "local_goto with unknown key '%s'" % scene_key)
		return
	await _mount(scene_key)


# ==========================================================================
# Host-driven transition with readiness barrier
# ==========================================================================

## Returns false when the transition was refused (bad key, not host, barrier
## already running).
func host_transition_to(scene_key: String) -> bool:
	if not multiplayer.is_server():
		Logx.error("scene", "host_transition_to called on a client")
		return false
	if not GameConfig.is_valid_scene_key(scene_key):
		Logx.error("scene", "host_transition_to unknown key '%s'" % scene_key)
		return false
	if _barrier_active:
		Logx.warn("scene", "Transition to '%s' refused: barrier already running" % scene_key)
		return false

	_transition_id += 1
	_barrier_scene_key = scene_key
	_barrier_active = true
	_barrier_timer = GameConfig.SCENE_TRANSITION_TIMEOUT
	_acks.clear()
	_expected = []
	for pid in NetworkManager.session_peer_ids():
		_expected.append(pid)

	Logx.info("scene", "Transition #%d -> %s (expecting %d peers)" % [
		_transition_id, scene_key, _expected.size()])
	transition_started.emit(scene_key)
	_rpc_load_scene.rpc(scene_key, _transition_id, GameManager.session_epoch)

	await _mount(scene_key)
	_host_record_ack(GameConfig.HOST_PEER_ID, _transition_id)
	return true


## HOST -> CLIENT.
@rpc("authority", "call_remote", "reliable")
func _rpc_load_scene(scene_key: String, transition_id: int, epoch: int) -> void:
	if multiplayer.is_server():
		return
	if not GameConfig.is_valid_scene_key(scene_key):
		Logx.warn("scene", "Host asked for unknown scene '%s'" % scene_key)
		return
	# Adopt the host's epoch: the client mirror must follow, never lead.
	GameManager.client_set_epoch(epoch)
	_barrier_scene_key = scene_key
	transition_started.emit(scene_key)
	await _mount(scene_key)
	_rpc_scene_ready.rpc_id(GameConfig.HOST_PEER_ID, transition_id, epoch)


## CLIENT -> HOST.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_scene_ready(transition_id: int, epoch: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0 or NetworkManager.is_peer_leaving(sender):
		return
	if not _ack_limiter.allow(sender):
		Logx.reject("scene", sender, "ack_rate_limited")
		if _ack_limiter.is_abusive(sender):
			NetworkManager.host_kick_peer(sender, "Too many scene acknowledgements.")
		return
	if epoch != GameManager.session_epoch:
		Logx.reject("scene", sender, "ack_stale_epoch")
		return
	if transition_id != _transition_id:
		Logx.reject("scene", sender, "ack_stale_transition")
		return
	if not LobbyManager.has_player(sender):
		Logx.reject("scene", sender, "ack_not_a_player")
		return
	_host_record_ack(sender, transition_id)


func _host_record_ack(peer_id: int, transition_id: int) -> void:
	if not _barrier_active or transition_id != _transition_id:
		return
	if _acks.has(peer_id):
		return
	if not _expected.has(peer_id):
		# A peer that joined after the barrier opened is not part of it.
		Logx.warn("scene", "Ack from unexpected peer %d ignored" % peer_id)
		return
	_acks[peer_id] = true
	barrier_progress.emit(_acks.size(), _expected.size())
	Logx.debug("scene", "Barrier %d: %d/%d" % [transition_id, _acks.size(), _expected.size()])
	_maybe_complete_barrier()


func _maybe_complete_barrier() -> void:
	if not _barrier_active:
		return
	for pid in _expected:
		if not _acks.has(pid):
			return
	_complete_barrier()


func _complete_barrier() -> void:
	var key := _barrier_scene_key
	var tid := _transition_id
	_barrier_active = false
	_acks.clear()
	_expected.clear()
	Logx.info("scene", "Barrier %d complete -> %s" % [tid, key])
	barrier_completed.emit(key, tid)


func _timeout_barrier() -> void:
	var missing: Array = []
	for pid in _expected:
		if not _acks.has(pid):
			missing.append(pid)
	Logx.warn("scene", "Barrier %d timed out; missing peers: %s" % [_transition_id, str(missing)])
	for pid in missing:
		if pid == GameConfig.HOST_PEER_ID:
			# The host itself failed to mount - this is a bug, not a network
			# problem. Abort rather than continue into an empty world.
			Logx.error("scene", "Host failed to mount '%s'; aborting session" % _barrier_scene_key)
			_barrier_active = false
			GameManager.host_abort_session("The host could not load the level.")
			return
		NetworkManager.host_kick_peer(int(pid), "You did not finish loading the level in time.")
	_complete_barrier()


## Called by NetworkManager when a peer drops, so a barrier waiting on that peer
## does not hang for the full timeout.
func host_handle_peer_left(peer_id: int) -> void:
	if not _barrier_active:
		return
	_expected.erase(peer_id)
	_acks.erase(peer_id)
	barrier_progress.emit(_acks.size(), _expected.size())
	_maybe_complete_barrier()


# ==========================================================================
# Mounting
# ==========================================================================

func _mount(scene_key: String) -> void:
	if not is_instance_valid(scene_root):
		Logx.error("scene", "bind_roots() was never called, or the root was freed")
		return

	_load_generation += 1
	var generation := _load_generation

	var path := GameConfig.scene_path(scene_key)
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		Logx.error("scene", "Could not load '%s'" % path)
		return

	# Detach the previous stage BEFORE instantiating the new one so the fixed
	# node name is free and no duplicate-name suffix can appear.
	var old := current_stage()
	if old != null:
		scene_root.remove_child(old)
		old.queue_free()

	var instance := packed.instantiate()
	instance.name = STAGE_NODE_NAME
	scene_root.add_child(instance)
	current_scene_key = scene_key

	# One frame so every _ready() in the subtree has definitely run and any
	# deferred setup (nav region registration) has been processed.
	await get_tree().process_frame
	if not _mount_still_valid(generation, instance, scene_key):
		return

	if instance.has_method("await_scene_ready"):
		await instance.await_scene_ready()
	if not _mount_still_valid(generation, instance, scene_key):
		return

	Logx.info("scene", "Mounted '%s'" % scene_key)
	scene_changed.emit(scene_key)


## True when a mount that has been awaiting is still the one that should finish.
##
## TWO ways it can stop being valid, and both have to be checked:
##   * a newer transition superseded it - the generation moved on;
##   * the whole shell was torn down while it awaited, which frees the instance
##     WITHOUT touching the generation. A freed Node in Godot 4 is not `== null`
##     - it is a "previously freed" object that passes every null check and
##     throws on the first method call - so this needs is_instance_valid().
##     Quitting during a scene transition hit exactly that path.
##
## `instance` is deliberately untyped: passing a freed object into a parameter
## typed as Node throws on the argument type check itself, before the function
## body ever gets a chance to notice.
func _mount_still_valid(generation: int, instance: Variant, scene_key: String) -> bool:
	if generation != _load_generation:
		Logx.warn("scene", "Mount of '%s' superseded" % scene_key)
		return false
	if not is_instance_valid(instance) or not is_instance_valid(scene_root):
		Logx.warn("scene", "Mount of '%s' abandoned: the scene root went away" % scene_key)
		return false
	return true


# ==========================================================================
# Teardown
# ==========================================================================

## Local-only reset. Does NOT change the current scene: the caller decides where
## to go next (usually the main menu).
func local_teardown() -> void:
	_barrier_active = false
	_barrier_scene_key = ""
	_acks.clear()
	_expected.clear()
	_barrier_timer = 0.0
	if _ack_limiter != null:
		_ack_limiter.clear()


func debug_state() -> Dictionary:
	return {
		"current_scene_key": current_scene_key,
		"transition_id": _transition_id,
		"barrier_active": _barrier_active,
		"acks": _acks.size(),
		"expected": _expected.size(),
	}
