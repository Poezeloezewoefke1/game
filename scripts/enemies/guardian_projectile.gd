extends Node3D
## A Sentinel energy bolt.
##
## AUTHORITY: the host spawns it, the host decides what it hits, and the host
## frees it. Every peer simulates the same deterministic straight-line motion
## from the same spawn payload, so no per-frame transform replication is needed
## at all - the only network traffic is one spawn and one despawn.
##
## Clients keep a safety timer at twice the nominal lifetime purely so a lost
## despawn packet can never leak a bolt into the next mission.

var spawn_position: Vector3 = Vector3.ZERO
var direction: Vector3 = Vector3.FORWARD

var _age: float = 0.0
var _resolved: bool = false

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _light: OmniLight3D = $Glow


func _ready() -> void:
	add_to_group(GameConfig.GROUP_PROJECTILE)
	add_to_group(GameConfig.GROUP_SESSION_BOUND)
	global_position = spawn_position
	if direction.length_squared() > 0.001:
		look_at(spawn_position + direction, Vector3.UP)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.28, 0.22)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.28, 0.22)
	mat.emission_energy_multiplier = 4.0
	_mesh.material_override = mat
	AudioDirector.play(AudioDirector.Cue.SENTINEL_PROJECTILE)


func _physics_process(delta: float) -> void:
	if _resolved:
		return
	_age += delta
	var step := direction.normalized() * GameConfig.GUARDIAN_PROJECTILE_SPEED * delta
	var previous := global_position
	global_position = previous + step

	if _is_host():
		_host_resolve(previous, global_position)
		if not _resolved and _age >= GameConfig.GUARDIAN_PROJECTILE_LIFETIME:
			_despawn()
	elif _age >= GameConfig.GUARDIAN_PROJECTILE_LIFETIME * 2.0:
		# Safety net only - the authoritative despawn comes from the host.
		queue_free()


func _host_resolve(from: Vector3, to: Vector3) -> void:
	# 1. Players, by authoritative position. Cheap (at most four) and immune to
	#    the physics-layer mistakes that silently break Area3D based hits.
	for node in SpawnManager.all_players():
		if not (node is Node3D):
			continue
		if not bool(node.get("is_alive")) or bool(node.get("is_downed")):
			continue
		var centre: Vector3 = node.authoritative_position() + Vector3.UP * 1.0
		if _segment_hits_sphere(from, to, centre, GameConfig.GUARDIAN_PROJECTILE_RADIUS + 0.6):
			if node.has_method("host_apply_damage"):
				node.host_apply_damage(GameConfig.GUARDIAN_PROJECTILE_DAMAGE, "sentinel")
			_despawn()
			return

	# 2. World geometry.
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = GameConfig.LAYER_WORLD
	if not space.intersect_ray(query).is_empty():
		_despawn()


func _despawn() -> void:
	if _resolved:
		return
	_resolved = true
	queue_free()


## Closest-point-on-segment test. A plain distance check on the end point would
## tunnel straight through a player at 13 m/s with a 0.45 m radius.
static func _segment_hits_sphere(a: Vector3, b: Vector3, centre: Vector3, radius: float) -> bool:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.000001:
		return a.distance_to(centre) <= radius
	var t := clampf((centre - a).dot(ab) / len_sq, 0.0, 1.0)
	return (a + ab * t).distance_to(centre) <= radius


func _is_host() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()
