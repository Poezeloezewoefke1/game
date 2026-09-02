extends Node
## World object identity, authority spawning and cleanup.
## Autoload name: SpawnManager
##
## TWO KINDS OF WORLD OBJECT
##   * AUTHORED interactables (terminal, crystals, pedestals, altar, drop pod)
##     carry a stable, hand-written `object_id` baked into the level scene. They
##     exist identically on every peer the moment the level mounts, so no id
##     negotiation is needed and a client request can name one directly.
##   * SPAWNED entities (players, the Sentinel, its projectiles, a dropped Star
##     Map) are created by the HOST only, through the level's MultiplayerSpawner,
##     and receive a host-assigned id carried inside the spawn payload.
##
##   A client can therefore never invent an object. It can only name an object
##   the host already knows about, and the host re-checks that the object is in
##   the current scene and the current session epoch before acting.

const PLAYER_SCENE := "res://scenes/entities/player.tscn"
const GUARDIAN_SCENE := "res://scenes/enemies/sentinel.tscn"
const WARDEN_SCENE := "res://scenes/enemies/warden.tscn"
const GUARDIAN_PROJECTILE_SCENE := "res://scenes/enemies/guardian_projectile.tscn"
const DROPPED_STAR_MAP_SCENE := "res://scenes/interactables/dropped_star_map.tscn"

const KIND_PLAYER := "player"
const KIND_GUARDIAN := "guardian"
const KIND_WARDEN := "warden"
const KIND_GUARDIAN_PROJECTILE := "gproj"
const KIND_DROPPED_STAR_MAP := "smap"

signal player_registered(peer_id: int, node: Node)
signal player_unregistered(peer_id: int)

## Current level wiring, rebound every time a gameplay level mounts.
var _spawner: MultiplayerSpawner = null
var _entities_root: Node = null
var _spawn_points: Array[Node3D] = []
var _guardian_anchor: Node3D = null
var _fallback_drop: Node3D = null

## object_id -> Node (authored + dynamic interactables in the CURRENT scene).
var _interactables: Dictionary = {}
## peer_id -> player Node
var _players: Dictionary = {}

## Host-only monotonic counter for dynamic object ids. Reset per session so ids
## stay small; uniqueness within a session is what matters.
var _next_dynamic_id: int = 1


# ==========================================================================
# Level binding
# ==========================================================================

## Called by every gameplay level from its _ready().
##
## ORDERING - this is subtle and was a real bug: Godot runs _ready() BOTTOM-UP,
## so every interactable in the level has ALREADY registered itself by the time
## the level root gets here. Clearing the registry in this function silently
## erased the whole level's interactables, and every interaction was then
## rejected as "unknown object". The registry is cleared in unbind_level()
## instead, which runs from the OUTGOING level's _exit_tree() - before the
## incoming level's children are ready.
func bind_level(spawner: MultiplayerSpawner, entities_root: Node, spawn_points: Array[Node3D],
		guardian_anchor: Node3D, fallback_drop: Node3D) -> void:
	_spawner = spawner
	_entities_root = entities_root
	_spawn_points = spawn_points
	_guardian_anchor = guardian_anchor
	_fallback_drop = fallback_drop
	if _spawner != null:
		_spawner.spawn_function = Callable(self, "_spawn_entity")
	Logx.info("spawn", "Level bound (%d spawn points)" % _spawn_points.size())


## Called from the OUTGOING level's _exit_tree(). This is where world-object
## identity is reset, so nothing from the previous level can be named by a
## request in the next one.
func unbind_level() -> void:
	_spawner = null
	_entities_root = null
	_spawn_points.clear()
	_guardian_anchor = null
	_fallback_drop = null
	_interactables.clear()
	_players.clear()


func has_level() -> bool:
	return _spawner != null and is_instance_valid(_spawner)


## True when `spawner` is the spawner this manager is currently bound to. Levels
## use it so a level being freed AFTER its successor has bound cannot unbind the
## successor.
func is_bound_to(spawner: MultiplayerSpawner) -> bool:
	return _spawner != null and _spawner == spawner


# ==========================================================================
# Interactable registry
# ==========================================================================

func register_interactable(object_id: String, node: Node) -> void:
	if object_id.is_empty():
		Logx.error("spawn", "Interactable %s has an empty object_id" % node.name)
		return
	if _interactables.has(object_id) and is_instance_valid(_interactables[object_id]):
		Logx.error("spawn", "Duplicate object_id '%s' (%s and %s)" % [
			object_id, (_interactables[object_id] as Node).name, node.name])
		return
	_interactables[object_id] = node


func unregister_interactable(object_id: String, node: Node) -> void:
	if _interactables.get(object_id) == node:
		_interactables.erase(object_id)


func find_interactable(object_id: String) -> Node:
	var n: Variant = _interactables.get(object_id)
	if n == null or not is_instance_valid(n):
		_interactables.erase(object_id)
		return null
	return n


func interactable_ids() -> Array:
	return _interactables.keys()


# ==========================================================================
# Player registry
# ==========================================================================

func register_player(peer_id: int, node: Node) -> void:
	_players[peer_id] = node
	player_registered.emit(peer_id, node)


func unregister_player(peer_id: int, node: Node) -> void:
	if _players.get(peer_id) == node:
		_players.erase(peer_id)
		player_unregistered.emit(peer_id)


func player_node(peer_id: int) -> Node:
	var n: Variant = _players.get(peer_id)
	if n == null or not is_instance_valid(n):
		_players.erase(peer_id)
		return null
	return n


func local_player() -> Node:
	return player_node(NetworkManager.local_peer_id())


func all_players() -> Array:
	var out: Array = []
	for peer_id in _players:
		var n: Variant = _players[peer_id]
		if is_instance_valid(n):
			out.append(n)
	return out


## peer_id -> {"alive": bool, "downed": bool} for the failure check.
func host_player_liveness() -> Dictionary:
	var out: Dictionary = {}
	for peer_id in _players:
		var n: Variant = _players[peer_id]
		if not is_instance_valid(n):
			continue
		if not LobbyManager.has_player(int(peer_id)):
			continue
		out[peer_id] = {
			"alive": bool((n as Node).get("is_alive")),
			"downed": bool((n as Node).get("is_downed")),
		}
	return out


## The nearest living, non-downed player to `from`, or null.
func nearest_living_player(from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for n in all_players():
		if not (n is Node3D):
			continue
		if not bool(n.get("is_alive")) or bool(n.get("is_downed")):
			continue
		var d: float = (n as Node3D).global_position.distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = n
	return best


# ==========================================================================
# Host spawning
# ==========================================================================

func host_spawn_all_players() -> void:
	if not _is_host() or not has_level():
		return
	var index := 0
	for peer_id in LobbyManager.sorted_peer_ids():
		host_spawn_player(int(peer_id), index)
		index += 1


func host_spawn_player(peer_id: int, spawn_index: int = -1) -> Node:
	if not _is_host() or not has_level():
		return null
	if player_node(peer_id) != null:
		Logx.warn("spawn", "Player %d already spawned" % peer_id)
		return player_node(peer_id)
	if spawn_index < 0:
		spawn_index = _players.size()
	var point := _spawn_point(spawn_index)
	var data := {
		"kind": KIND_PLAYER,
		"peer": peer_id,
		"name": LobbyManager.display_name_of(peer_id),
		"pos": point.origin,
		"yaw": point.basis.get_euler().y,
	}
	return _spawner.spawn(data)


func host_despawn_player(peer_id: int) -> void:
	if not _is_host():
		return
	var n: Node = player_node(peer_id)
	if n == null:
		return
	_players.erase(peer_id)
	n.queue_free()


func host_spawn_guardian() -> Node:
	if not _is_host() or not has_level():
		return null
	# Only another SENTINEL blocks this, not the Warden: a crystal's guard and
	# the temple's boss are allowed to be alive at the same time.
	for existing in get_tree().get_nodes_in_group(GameConfig.GROUP_GUARDIAN):
		if not existing.is_in_group(GameConfig.GROUP_BOSS):
			Logx.warn("spawn", "A Sentinel is already present; refusing duplicate spawn")
			return null
	var origin := Vector3.ZERO
	if _guardian_anchor != null and is_instance_valid(_guardian_anchor):
		origin = _guardian_anchor.global_position
	Logx.info("spawn", "Spawning the Sentinel at %s" % str(origin))
	return _spawner.spawn({"kind": KIND_GUARDIAN, "pos": origin})


## The Warden hovers, so it spawns above the anchor rather than on it.
func host_spawn_warden() -> Node:
	if not _is_host() or not has_level():
		return null
	if not get_tree().get_nodes_in_group(GameConfig.GROUP_BOSS).is_empty():
		Logx.warn("spawn", "The Warden is already awake; refusing a second")
		return null
	var origin := Vector3.ZERO
	if _guardian_anchor != null and is_instance_valid(_guardian_anchor):
		origin = _guardian_anchor.global_position
	origin.y += GameConfig.BOSS_HOVER_HEIGHT
	Logx.info("spawn", "Spawning the Warden at %s" % str(origin))
	return _spawner.spawn({"kind": KIND_WARDEN, "pos": origin})


func host_spawn_guardian_projectile(origin: Vector3, direction: Vector3) -> Node:
	if not _is_host() or not has_level():
		return null
	var dir := direction.normalized()
	if dir.length_squared() < 0.5:
		return null
	_next_dynamic_id += 1
	return _spawner.spawn({
		"kind": KIND_GUARDIAN_PROJECTILE,
		"pos": origin,
		"dir": dir,
		"oid": _next_dynamic_id,
	})


func host_spawn_dropped_star_map(position: Vector3) -> Node:
	if not _is_host() or not has_level():
		return null
	host_clear_dropped_star_maps()
	_next_dynamic_id += 1
	var safe := position
	if not safe.is_finite():
		safe = fallback_drop_position()
	return _spawner.spawn({
		"kind": KIND_DROPPED_STAR_MAP,
		"pos": safe,
		"oid": "dropped_star_map_%d" % _next_dynamic_id,
	})


## The custom spawn function: runs on the host AND on every client with the same
## payload, so both sides build an identical node with an identical name.
func _spawn_entity(data: Variant) -> Node:
	if typeof(data) != TYPE_DICTIONARY:
		Logx.error("spawn", "Spawn payload was not a Dictionary")
		return null
	var d: Dictionary = data
	var kind := String(d.get("kind", ""))
	match kind:
		KIND_PLAYER:
			return _build_player(d)
		KIND_GUARDIAN:
			return _build_simple(GUARDIAN_SCENE, "Sentinel", d)
		KIND_WARDEN:
			return _build_simple(WARDEN_SCENE, "Warden", d)
		KIND_GUARDIAN_PROJECTILE:
			return _build_projectile(d)
		KIND_DROPPED_STAR_MAP:
			return _build_dropped_star_map(d)
		_:
			Logx.error("spawn", "Unknown spawn kind '%s'" % kind)
			return null


func _build_player(d: Dictionary) -> Node:
	var packed: PackedScene = load(PLAYER_SCENE) as PackedScene
	if packed == null:
		Logx.error("spawn", "Missing player scene")
		return null
	var node := packed.instantiate()
	var peer_id := int(d.get("peer", 0))
	node.name = "Player_%d" % peer_id
	# Set before the node enters the tree so _ready() already sees final values.
	node.set("owner_peer_id", peer_id)
	node.set("display_name", String(d.get("name", "")))
	node.set("spawn_position", d.get("pos", Vector3.ZERO))
	node.set("spawn_yaw", float(d.get("yaw", 0.0)))
	return node


func _build_simple(scene_path: String, node_name: String, d: Dictionary) -> Node:
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		Logx.error("spawn", "Missing scene %s" % scene_path)
		return null
	var node := packed.instantiate()
	node.name = node_name
	node.set("spawn_position", d.get("pos", Vector3.ZERO))
	return node


func _build_projectile(d: Dictionary) -> Node:
	var packed: PackedScene = load(GUARDIAN_PROJECTILE_SCENE) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate()
	node.name = "GProj_%d" % int(d.get("oid", 0))
	node.set("spawn_position", d.get("pos", Vector3.ZERO))
	node.set("direction", d.get("dir", Vector3.FORWARD))
	return node


func _build_dropped_star_map(d: Dictionary) -> Node:
	var packed: PackedScene = load(DROPPED_STAR_MAP_SCENE) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate()
	var oid := String(d.get("oid", "dropped_star_map"))
	node.name = oid
	node.set("object_id", oid)
	node.set("spawn_position", d.get("pos", Vector3.ZERO))
	return node


# ==========================================================================
# Host cleanup
# ==========================================================================

## Removes every dynamically spawned entity. Called on every transition, retry,
## victory, failure and return-to-lobby so nothing can survive into a replay.
##
## AWAIT THIS. queue_free() is deferred to the end of the frame, and
## MultiplayerSpawner only emits its despawn notifications when the node
## actually leaves the tree. If the caller broadcasts the next scene first, the
## client tears down the old scene and then receives a despawn for a node it no
## longer has - Godot logs "on_despawn_receive ... ERR_UNAUTHORIZED" once per
## entity. Waiting here lets the despawns flush while every peer still has the
## scene those entities live in.
func host_clear_all() -> void:
	if not _is_host():
		return
	_next_dynamic_id = 1
	var freed := false
	for group in [GameConfig.GROUP_GUARDIAN, GameConfig.GROUP_PROJECTILE, GameConfig.GROUP_SESSION_BOUND]:
		for n in get_tree().get_nodes_in_group(group):
			(n as Node).queue_free()
			freed = true
	for peer_id in _players.keys():
		var n: Variant = _players[peer_id]
		if is_instance_valid(n):
			(n as Node).queue_free()
			freed = true
	_players.clear()
	if freed:
		await get_tree().process_frame
		await get_tree().process_frame


## Guardian + its projectiles only; players stay for the victory/failure scene.
func host_clear_hostiles() -> void:
	if not _is_host():
		return
	for group in [GameConfig.GROUP_GUARDIAN, GameConfig.GROUP_PROJECTILE]:
		for n in get_tree().get_nodes_in_group(group):
			(n as Node).queue_free()


func host_clear_dropped_star_maps() -> void:
	if not _is_host():
		return
	for n in get_tree().get_nodes_in_group(GameConfig.GROUP_SESSION_BOUND):
		if (n as Node).has_method("is_dropped_star_map"):
			(n as Node).queue_free()


func fallback_drop_position() -> Vector3:
	if _fallback_drop != null and is_instance_valid(_fallback_drop):
		return _fallback_drop.global_position
	if _guardian_anchor != null and is_instance_valid(_guardian_anchor):
		return _guardian_anchor.global_position
	return Vector3.ZERO


func _spawn_point(index: int) -> Transform3D:
	if _spawn_points.is_empty():
		return Transform3D.IDENTITY
	var p := _spawn_points[index % _spawn_points.size()]
	if p == null or not is_instance_valid(p):
		return Transform3D.IDENTITY
	return p.global_transform


func _is_host() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()
