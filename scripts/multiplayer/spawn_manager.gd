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
	# Only another TEMPLE Sentinel blocks this. Neither the Warden nor a crystal
	# guard does: they are different roles that are meant to coexist, and the
	# comment here always said so - the test just asked the wrong question. It
	# counted every non-boss guardian, so the moment a mission put a guard on a
	# crystal, that guard held the temple's slot and the temple Sentinel was
	# silently refused.
	for existing in get_tree().get_nodes_in_group(GameConfig.GROUP_GUARDIAN):
		if existing.is_in_group(GameConfig.GROUP_BOSS):
			continue
		if String(existing.get("guards_crystal_id")) != "":
			continue
		Logx.warn("spawn", "A Sentinel is already present; refusing duplicate spawn")
		return null
	var origin := Vector3.ZERO
	if _guardian_anchor != null and is_instance_valid(_guardian_anchor):
		origin = _guardian_anchor.global_position
	Logx.info("spawn", "Spawning the Sentinel at %s" % str(origin))
	return _spawner.spawn({"kind": KIND_GUARDIAN, "pos": origin})


## Where a crystal's guard should stand.
##
## This replaces `crystal + Vector3(0, 0, 5)`, which was applied on every level
## without ever asking what was five metres north of the crystal. The answer was
## "a wall" on all three: 0.447 m INSIDE RuinsBack on Cinder and Hallow, and
## 1.0 m in front of the 10 m RuinsWallSouth on Nerava. The levels differed only
## in how far into it, and Nerava was survivable - which is why the constant
## lasted this long, and why the fix had to be checked against the planet that
## worked as carefully as against the two that did not.
##
## What that cost is worth stating precisely, because the obvious story is not
## the one the evidence supports. The runs where these guards took 0 hits in 60
## volleys failed for a different reason - the driver was stuck against a mesa
## 25 m away, see I34 in docs/QA_REPORT.md - so this placement has never been
## observed to make a mission unwinnable. What it demonstrably did do is wedge
## the guard: while the Sentinel still carried a world collision mask it was
## trapped where it spawned and logged "Stuck for 6.0s - returning to anchor"
## eighteen times in one run, returning each time to the same point inside the
## wall. That is defect 79, and this is where it came from.
##
## It is fixed here rather than left alone because a guard spawning inside a
## wall is wrong however it plays, and because no gate in the suite had ever
## asked where a guard ends up.
##
## The check reads the level's COLLISION SHAPES, not the physics server. Guards
## are spawned from the scene barrier, which can land before the space has
## stepped with the new level in it - and a query that quietly returns "clear"
## because the wall was not registered yet would put the guard back in the wall
## and pass its own test. Everything on LAYER_WORLD in these levels is a
## BoxShape3D (world_block.gd and set_dressing.gd both build one), so the tree
## carries the whole truth and the timing question does not arise.
func guard_post(crystal: Node3D) -> Vector3:
	var home: Vector3 = crystal.global_position
	var due_north: Vector3 = home + Vector3(0.0, 0.0, GameConfig.GUARD_STAND_OFF)
	if crystal.get_tree() == null:
		return due_north
	var boxes := _solid_boxes(crystal)
	if boxes.is_empty():
		return due_north
	for i in GameConfig.GUARD_POST_SAMPLES:
		var angle: float = TAU * float(i) / float(GameConfig.GUARD_POST_SAMPLES)
		# i == 0 is due north, so a crystal that stands in the open keeps the
		# post it has always had and no working level moves its guard.
		var post: Vector3 = home + Vector3(sin(angle), 0.0, cos(angle)) * GameConfig.GUARD_STAND_OFF
		if _post_is_clear(boxes, post):
			if i > 0:
				# Name the crystal and the post. "Moved 60 degrees" on its own
				# is not something anyone can check against a level file.
				Logx.info("spawn", "Guard post for %s moved %.0f degrees off north to %s to clear the scenery"
					% [crystal.name, rad_to_deg(angle), str(post.snapped(Vector3.ONE * 0.1))])
			return post
	# Say so rather than silently returning a bad post. A guard in the wrong
	# place is still better than no guard, but nobody should have to rediscover
	# this by playing the level.
	Logx.warn("spawn", "No clear guard post around %s at %s - falling back to due north, which may be blocked"
		% [crystal.name, str(home.snapped(Vector3.ONE * 0.1))])
	return due_north


## Every solid box in the level, as [global transform, half extents].
##
## Rooted by walking UP from the crystal, not from current_scene: in the game
## the level hangs under the stage, and in the test suite it is added straight
## to the tree root beside the runner. Walking up finds the level in both, which
## is what stops this check from passing in tests and measuring nothing in play.
func _solid_boxes(from: Node3D) -> Array:
	var out: Array = []
	var tree_root: Node = from.get_tree().root
	var root: Node = from
	while root.get_parent() != null and root.get_parent() != tree_root:
		root = root.get_parent()
	for node in root.find_children("*", "CollisionShape3D", true, false):
		var cs := node as CollisionShape3D
		if cs == null or cs.disabled:
			continue
		var box := cs.shape as BoxShape3D
		if box == null:
			continue
		var body := cs.get_parent() as CollisionObject3D
		if body == null or (body.collision_layer & GameConfig.LAYER_WORLD) == 0:
			continue
		out.append([cs.global_transform, box.size * 0.5])
	return out


## Is a guard standing here clear of the scenery? The guard is treated as a
## column GUARD_BODY_HEIGHT tall and GUARD_CLEARANCE wide, because it hovers -
## a check that only looked at the ground would call the inside of a wall clear
## as long as the wall started above the guard's feet.
func _post_is_clear(boxes: Array, post: Vector3) -> bool:
	for entry in boxes:
		var xform: Transform3D = entry[0]
		var half: Vector3 = entry[1]
		var local: Vector3 = xform.affine_inverse() * post
		if absf(local.x) > half.x + GameConfig.GUARD_CLEARANCE:
			continue
		if absf(local.z) > half.z + GameConfig.GUARD_CLEARANCE:
			continue
		# Vertical overlap between the box, which spans -half.y..+half.y in its
		# own frame, and the guard's column.
		#
		# The column starts ABOVE the post, not at it. Starting at the post made
		# the check reject every position standing on RuinsFloor - the 18 x 0.3
		# x 14 slab the ruins crystal sits on - because the floor a guard stands
		# on overlaps a column that begins at its feet. Ground is not an
		# obstruction; a wall through the chest is.
		var column_bottom: float = local.y + GameConfig.GUARD_FOOT_CLEAR
		var column_top: float = local.y + GameConfig.GUARD_BODY_HEIGHT
		if column_bottom > half.y:
			continue
		if column_top < -half.y:
			continue
		return false
	return true


## A crystal's guard: a Sentinel that stands at a named spot and can be killed.
## `at` is passed explicitly because a guard belongs beside its crystal, not at
## the temple's GuardianAnchor.
func host_spawn_crystal_guard(crystal_id: String, at: Vector3) -> Node:
	if not _is_host() or not has_level():
		return null
	Logx.info("spawn", "Spawning a guard for %s at %s" % [crystal_id, str(at)])
	return _spawner.spawn({"kind": KIND_GUARDIAN, "pos": at, "guards": crystal_id})


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
			var sentinel := _build_simple(GUARDIAN_SCENE, "Sentinel", d)
			if sentinel != null and String(d.get("guards", "")) != "":
				sentinel.set("guards_crystal_id", String(d["guards"]))
			return sentinel
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
