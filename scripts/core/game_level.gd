extends Node3D
class_name GameLevel
## Base for every gameplay level (the Hub and Nerava).
##
## A level's job is to describe WHERE things are, bind itself to SpawnManager,
## and report when it is genuinely ready. It owns no mission state.
##
## SCENE-READY CONTRACT
##   SceneManager awaits `await_scene_ready()` before acknowledging the network
##   barrier. On the host that includes waiting for the navigation mesh bake,
##   because spawning the Sentinel into an unbaked map is exactly how a guardian
##   ends up frozen at its anchor.

@export var level_key: String = ""
@export var ambience: AudioDirector.Cue = AudioDirector.Cue.STATION_AMBIENCE

## Seconds to wait for a navigation bake before giving up and continuing with
## direct steering rather than blocking the whole session.
const NAV_BAKE_TIMEOUT: float = 12.0

## Both come from scenes/multiplayer/entity_root.tscn, instanced identically in
## every level so the replicated node paths are guaranteed to match.
@onready var entity_spawner: MultiplayerSpawner = $EntityRoot/EntitySpawner
@onready var entities: Node3D = $EntityRoot/Entities
@onready var spawn_points_root: Node3D = $PlayerSpawnPoints

var _nav_region: NavigationRegion3D = null
var _nav_done: bool = false


func _ready() -> void:
	_nav_region = get_node_or_null("NavigationRegion3D") as NavigationRegion3D

	var points: Array[Node3D] = []
	if spawn_points_root != null:
		for child in spawn_points_root.get_children():
			if child is Node3D:
				points.append(child as Node3D)
	if points.is_empty():
		Logx.error("level", "%s has no player spawn points" % level_key)

	entity_spawner.spawn_path = entity_spawner.get_path_to(entities)
	SpawnManager.bind_level(
		entity_spawner,
		entities,
		points,
		get_node_or_null("GuardianAnchor") as Node3D,
		get_node_or_null("StarMapDropAnchor") as Node3D)

	AudioDirector.play_ambience(ambience)

	if _is_host() and _nav_region != null:
		_bake_navigation.call_deferred()
	else:
		_nav_done = true


func _exit_tree() -> void:
	# Only unbind if this level is still the bound one: a fast transition can
	# free the old level AFTER the new one has already bound itself.
	if is_instance_valid(entity_spawner) and SpawnManager.is_bound_to(entity_spawner):
		SpawnManager.unbind_level()


## Awaited by SceneManager before it acknowledges the readiness barrier.
func await_scene_ready() -> void:
	var waited := 0.0
	while not _nav_done and waited < NAV_BAKE_TIMEOUT:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if not _nav_done:
		Logx.warn("level", "Navigation bake timed out after %.1fs" % waited)


func _bake_navigation() -> void:
	if _nav_region == null:
		_nav_done = true
		return
	if _nav_region.navigation_mesh == null:
		Logx.error("level", "%s NavigationRegion3D has no NavigationMesh" % level_key)
		_nav_done = true
		return
	if not _nav_region.bake_finished.is_connected(_on_bake_finished):
		_nav_region.bake_finished.connect(_on_bake_finished)
	Logx.info("level", "Baking navigation for %s" % level_key)
	_nav_region.bake_navigation_mesh(false)


func _on_bake_finished() -> void:
	Logx.info("level", "Navigation bake finished for %s" % level_key)
	_await_navigation_usable()


## The bake finishing is not the same as the navigation map being queryable -
## the server commits the new mesh on a later synchronisation pass. Reporting
## scene-ready too early is how the Sentinel ends up with no path on a replay.
func _await_navigation_usable() -> void:
	var map := _nav_region.get_navigation_map()
	var probe := global_position
	if spawn_points_root != null and spawn_points_root.get_child_count() > 0:
		var first := spawn_points_root.get_child(0) as Node3D
		if first != null:
			probe = first.global_position
	var ok: bool = await NavUtil.await_map_usable(get_tree(), map, probe, 240, self)
	if not is_instance_valid(self):
		return
	if not ok:
		Logx.warn("level", "%s navigation never became queryable" % level_key)
	_nav_done = true


func _is_host() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()
