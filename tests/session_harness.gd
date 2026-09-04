extends RefCounted
class_name TestSession
## Boots a REAL host session for integration tests.
##
## Deliberately not a mock: it opens an actual ENetMultiplayerPeer on loopback,
## so `multiplayer.is_server()` is genuinely true and every host-only guard,
## every RPC declaration and the whole scene-readiness barrier run exactly as
## they do in a shipped build. A mocked multiplayer layer would let a broken
## authority check pass the tests.

var tree: SceneTree
var scene_root: Node
var ui_layer: CanvasLayer
var port: int = 0

var _prev_scene_root: Node = null
var _prev_ui_layer: CanvasLayer = null


func _init(p_tree: SceneTree) -> void:
	tree = p_tree


## Returns "" on success or a human-readable error.
func start(display_name: String, first_port: int) -> String:
	scene_root = Node.new()
	scene_root.name = "TestSceneRoot"
	tree.root.add_child(scene_root)
	ui_layer = CanvasLayer.new()
	ui_layer.name = "TestUILayer"
	tree.root.add_child(ui_layer)

	_prev_scene_root = SceneManager.scene_root
	_prev_ui_layer = SceneManager.ui_layer
	SceneManager.bind_roots(scene_root, ui_layer)

	# CI runners recycle ports; try a small range rather than failing the whole
	# suite because one socket is in TIME_WAIT.
	for offset in 20:
		var candidate := first_port + offset
		var result := NetworkManager.host_game(candidate, display_name)
		if bool(result["ok"]):
			port = candidate
			return ""
	return "could not bind any port in %d..%d" % [first_port, first_port + 19]


func stop() -> void:
	NetworkManager.shutdown(NetworkManager.REASON_LOCAL_LEFT)
	SceneManager.bind_roots(_prev_scene_root, _prev_ui_layer)
	if is_instance_valid(scene_root):
		scene_root.queue_free()
	if is_instance_valid(ui_layer):
		ui_layer.queue_free()


func host_player() -> Node:
	return SpawnManager.player_node(GameConfig.HOST_PEER_ID)


## Teleports the host's own player. The host IS the motion authority for its own
## player, so this is exactly the state a real player reaches by walking - it
## does not bypass any check the host performs.
func move_host_player_to(position: Vector3) -> void:
	var p := host_player()
	if p == null:
		return
	p.global_position = position
	p.set("velocity", Vector3.ZERO)
	p.set("sync_position", position)
	await tree.physics_frame
	await tree.physics_frame


## Polls until `SceneManager.current_scene_key` matches, or the timeout expires.
func await_scene(key: String, timeout: float = 20.0) -> bool:
	var waited := 0.0
	while waited < timeout:
		if SceneManager.current_scene_key == key and SpawnManager.has_level():
			# One more frame so post-barrier spawning has definitely happened.
			await tree.process_frame
			return true
		await tree.process_frame
		waited += tree.root.get_process_delta_time()
	return false


func await_mission_state(state: int, timeout: float = 20.0) -> bool:
	var waited := 0.0
	while waited < timeout:
		if GameManager.mission_state() == state:
			return true
		await tree.process_frame
		waited += tree.root.get_process_delta_time()
	return false


## Every enemy in the guardian group: temple Sentinel, crystal guards, Warden.
## Tests about cleanup and session reset mean exactly this - "is anything still
## alive" - so it keeps the broad meaning.
func guardian_count() -> int:
	return tree.get_nodes_in_group(GameConfig.GROUP_GUARDIAN).size()


## The TEMPLE Sentinel specifically: not the boss, not a crystal's guard.
##
## Three different things live in the guardian group and every test used to
## count all of them. That was harmless right up until a mission put a guard on
## a crystal, and then "taking the Star Map spawns the Sentinel" counted two and
## failed - while what it had actually been counting all along was the Warden.
## A test should say which of the three it means.
func temple_sentinel_count() -> int:
	var n := 0
	for node in tree.get_nodes_in_group(GameConfig.GROUP_GUARDIAN):
		if node.is_in_group(GameConfig.GROUP_BOSS):
			continue
		if String(node.get("guards_crystal_id")) != "":
			continue
		n += 1
	return n


## How many bosses are awake. Exactly one Warden per descent, ever.
func boss_count() -> int:
	return tree.get_nodes_in_group(GameConfig.GROUP_BOSS).size()


## How many crystal guards are standing.
func crystal_guard_count() -> int:
	var n := 0
	for node in tree.get_nodes_in_group(GameConfig.GROUP_GUARDIAN):
		if String(node.get("guards_crystal_id")) != "":
			n += 1
	return n


func projectile_count() -> int:
	return tree.get_nodes_in_group(GameConfig.GROUP_PROJECTILE).size()


func session_bound_count() -> int:
	return tree.get_nodes_in_group(GameConfig.GROUP_SESSION_BOUND).size()
