extends CharacterBody3D
## THE SENTINEL - the temple's ancient guardian.
##
## AUTHORITY: the host runs the entire brain. Clients receive position, yaw and
## the current state through a host-authority MultiplayerSynchronizer and do
## nothing but present it. A client cannot move it, retarget it, stagger it, or
## make it shoot.
##
## NAVIGATION SAFETY - the three ways a NavigationAgent3D normally breaks, and
## what this script does about each:
##   1. Querying before the navigation map has synchronised -> we wait for a
##      physics frame AND a non-zero map iteration id before the first query.
##   2. Re-setting target_position every frame -> we repath on a timer, and only
##      when the target actually moved (GUARDIAN_REPATH_MIN_DELTA).
##   3. No reachable path (target inside geometry, off-mesh, disconnected) ->
##      we fall back to direct steering, and if nothing improves for
##      GUARDIAN_STUCK_RECOVER_TIME we return to the spawn anchor instead of
##      freezing or spamming the log.

enum State { IDLE, CHASE, SHOOT, STAGGERED }

var spawn_position: Vector3 = Vector3.ZERO

## When set, this Sentinel is a crystal's GUARD rather than the temple's roving
## defender: it can be destroyed, and destroying it unseals that crystal.
##
## The temple Sentinel was never destructible - it staggers on the tenth hit and
## recovers, forever - and that is still right for a hazard you are meant to
## flee. A lock you cannot remove is not a lock, so a guard needs a death.
var guards_crystal_id: String = ""
var _guard_hits: int = 0

# --- Replicated (host authority) ------------------------------------------
var sync_position: Vector3 = Vector3.ZERO
var sync_yaw: float = 0.0
var sync_state: int = State.IDLE

# --- Host only ------------------------------------------------------------
var _hits: int = 0
var _stagger_timer: float = 0.0
var _shoot_timer: float = 0.0
var _repath_timer: float = 0.0
var _last_repath_target: Vector3 = Vector3.INF
var _stuck_timer: float = 0.0
## How many times this Sentinel has had to recover from being stuck. Exposed for
## tests; a rising number in a real session means the level geometry is trapping
## the guardian and the level needs fixing, not the AI.
var _stuck_recoveries: int = 0
var _last_progress_position: Vector3 = Vector3.ZERO
var _nav_ready: bool = false
var _target: Node3D = null

@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var _core: MeshInstance3D = $Core
@onready var _shell: MeshInstance3D = $Shell
@onready var _eye: MeshInstance3D = $Eye
@onready var _light: OmniLight3D = $CoreLight
@onready var _muzzle: Node3D = $Muzzle
@onready var _sync: MultiplayerSynchronizer = $StateSync


func _enter_tree() -> void:
	set_multiplayer_authority(GameConfig.HOST_PEER_ID)
	_configure_replication()


func _ready() -> void:
	add_to_group(GameConfig.GROUP_GUARDIAN)
	add_to_group(GameConfig.GROUP_SESSION_BOUND)
	collision_layer = GameConfig.LAYER_ENEMY
	collision_mask = GameConfig.LAYER_WORLD
	global_position = spawn_position
	sync_position = spawn_position
	_last_progress_position = spawn_position
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING

	_agent.path_desired_distance = 1.2
	_agent.target_desired_distance = 3.0
	_agent.avoidance_enabled = false

	_apply_materials()
	PropBuilder.build_sentinel(_shell, _core, _eye)
	AudioDirector.play(AudioDirector.Cue.SENTINEL_SPAWN)

	if _is_host():
		_prepare_navigation.call_deferred()


func _configure_replication() -> void:
	var s := get_node_or_null("StateSync") as MultiplayerSynchronizer
	if s == null:
		return
	var cfg := SceneReplicationConfig.new()
	for prop in ["sync_position", "sync_yaw", "sync_state"]:
		var p := NodePath(".:" + prop)
		cfg.add_property(p)
		cfg.property_set_spawn(p, true)
		cfg.property_set_replication_mode(p, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	s.replication_config = cfg
	s.replication_interval = 0.033


func _is_host() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


## Waits until the navigation map can genuinely answer a query near the spawn
## anchor. See NavUtil for why "iteration id > 0" is not good enough on a level
## that can be entered twice.
func _prepare_navigation() -> void:
	var map := _agent.get_navigation_map()
	var usable: bool = await NavUtil.await_map_usable(get_tree(), map, spawn_position, 240, self)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_nav_ready = usable
	if usable:
		Logx.info("sentinel", "Navigation ready")
	else:
		Logx.warn("sentinel", "Navigation map never became usable; using direct steering")


func _physics_process(delta: float) -> void:
	if _is_host():
		_host_think(delta)
	else:
		_remote_present(delta)
	_present_common(delta)


# ==========================================================================
# Host brain
# ==========================================================================

func _host_think(delta: float) -> void:
	if GameManager.is_mission_over():
		velocity = Vector3.ZERO
		sync_state = State.IDLE
		return

	if sync_state == State.STAGGERED:
		_stagger_timer -= delta
		velocity = velocity.move_toward(Vector3.ZERO, GameConfig.GUARDIAN_ACCELERATION * 2.0 * delta)
		move_and_slide()
		_publish_transform()
		if _stagger_timer <= 0.0:
			sync_state = State.IDLE
			_hits = 0
		return

	_target = _host_select_target()
	if _target == null:
		sync_state = State.IDLE
		velocity = velocity.move_toward(Vector3.ZERO, GameConfig.GUARDIAN_ACCELERATION * delta)
		move_and_slide()
		_publish_transform()
		return

	var target_pos := _target_position(_target)
	var to_target := target_pos - global_position
	var distance := to_target.length()

	if distance > GameConfig.GUARDIAN_LOSE_RANGE:
		sync_state = State.IDLE
	elif distance <= GameConfig.GUARDIAN_SHOOT_RANGE and _host_has_line_of_sight(target_pos):
		sync_state = State.SHOOT
	else:
		sync_state = State.CHASE

	_host_steer(delta, target_pos, distance)
	_host_face(target_pos, delta)

	_shoot_timer -= delta
	if sync_state == State.SHOOT and _shoot_timer <= 0.0:
		_shoot_timer = GameConfig.GUARDIAN_SHOOT_INTERVAL
		_host_fire_at(target_pos)

	_host_track_stuck(delta)
	_publish_transform()


## Star Map carrier first; otherwise the nearest living player.
func _host_select_target() -> Node3D:
	var carrier := GameManager.star_map_carrier()
	if carrier != 0 and GameManager.star_map_state() == MissionRules.MAP_CARRIED:
		var node: Node = SpawnManager.player_node(carrier)
		if node is Node3D and bool(node.get("is_alive")) and not bool(node.get("is_downed")):
			return node as Node3D
	return SpawnManager.nearest_living_player(global_position)


func _target_position(node: Node3D) -> Vector3:
	if node.has_method("authoritative_position"):
		return node.authoritative_position() + Vector3.UP * 1.0
	return node.global_position + Vector3.UP * 1.0


func _host_steer(delta: float, target_pos: Vector3, distance: float) -> void:
	var desired := Vector3.ZERO

	if sync_state == State.CHASE:
		var steer_point := target_pos
		if _nav_ready:
			_repath_timer -= delta
			if _repath_timer <= 0.0 and _last_repath_target.distance_to(target_pos) > GameConfig.GUARDIAN_REPATH_MIN_DELTA:
				_repath_timer = GameConfig.GUARDIAN_REPATH_INTERVAL
				_last_repath_target = target_pos
				_agent.target_position = target_pos
			if not _agent.is_navigation_finished():
				steer_point = _agent.get_next_path_position()
		var to_point := steer_point - global_position
		to_point.y = 0.0
		if to_point.length_squared() > 0.01:
			desired = to_point.normalized() * GameConfig.GUARDIAN_MAX_SPEED
	elif sync_state == State.SHOOT:
		# Hold at a comfortable firing distance rather than crowding the player.
		var ideal := GameConfig.GUARDIAN_SHOOT_RANGE * 0.55
		var flat := target_pos - global_position
		flat.y = 0.0
		if flat.length() > 0.01:
			var sign_dir := 1.0 if distance > ideal else -1.0
			desired = flat.normalized() * GameConfig.GUARDIAN_MAX_SPEED * 0.45 * sign_dir

	velocity.x = move_toward(velocity.x, desired.x, GameConfig.GUARDIAN_ACCELERATION * delta * 4.0)
	velocity.z = move_toward(velocity.z, desired.z, GameConfig.GUARDIAN_ACCELERATION * delta * 4.0)

	# Hover: keep a constant height above whatever is below.
	var desired_y := _ground_height() + GameConfig.GUARDIAN_HOVER_HEIGHT
	velocity.y = clampf((desired_y - global_position.y) * 3.0, -6.0, 6.0)

	move_and_slide()


func _ground_height() -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return global_position.y - GameConfig.GUARDIAN_HOVER_HEIGHT
	var from := global_position + Vector3.UP * 2.0
	var to := global_position + Vector3.DOWN * 40.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = GameConfig.LAYER_WORLD
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return spawn_position.y - GameConfig.GUARDIAN_HOVER_HEIGHT
	return float((hit["position"] as Vector3).y)


func _host_face(target_pos: Vector3, delta: float) -> void:
	var flat := target_pos - global_position
	flat.y = 0.0
	if flat.length_squared() < 0.01:
		return
	var wanted := atan2(flat.x, flat.z)
	rotation.y = lerp_angle(rotation.y, wanted, clampf(6.0 * delta, 0.0, 1.0))


func _host_has_line_of_sight(target_pos: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(_muzzle.global_position, target_pos)
	query.collision_mask = GameConfig.LAYER_WORLD
	query.exclude = [get_rid()]
	return space.intersect_ray(query).is_empty()


func _host_fire_at(target_pos: Vector3) -> void:
	var origin := _muzzle.global_position
	var direction := (target_pos - origin).normalized()
	if not direction.is_finite() or direction.length_squared() < 0.5:
		return
	SpawnManager.host_spawn_guardian_projectile(origin, direction)


## Detects "the Sentinel is not getting anywhere" and recovers, rather than
## letting it grind against geometry for the rest of the mission.
func _host_track_stuck(delta: float) -> void:
	if sync_state != State.CHASE:
		_stuck_timer = 0.0
		_last_progress_position = global_position
		return
	if global_position.distance_to(_last_progress_position) > 1.0:
		_stuck_timer = 0.0
		_last_progress_position = global_position
		return
	_stuck_timer += delta
	if _stuck_timer >= GameConfig.GUARDIAN_STUCK_RECOVER_TIME:
		Logx.warn("sentinel", "Stuck for %.1fs - returning to anchor" % _stuck_timer)
		_stuck_timer = 0.0
		_stuck_recoveries += 1
		global_position = spawn_position
		velocity = Vector3.ZERO
		_last_progress_position = spawn_position
		_last_repath_target = Vector3.INF
		_publish_transform()


func _publish_transform() -> void:
	sync_position = global_position
	sync_yaw = rotation.y


# ==========================================================================
# Host: damage intake
# ==========================================================================

## Called by the host after IT validated a blaster shot. Never called from a
## client RPC, so there is no path for a client to inflate the hit count.
## `part` is unused here - the Sentinel is one body - but the signature has to
## match the Warden's, because the host's fire path calls whichever it hit.
func host_register_hit(from_peer: int, _part: Node = null) -> void:
	if guards_crystal_id != "":
		_host_register_guard_hit()
		return
	if not _is_host():
		return
	if sync_state == State.STAGGERED or GameManager.is_mission_over():
		return
	_hits += 1
	Logx.debug("sentinel", "hit %d/%d by peer %d" % [_hits, GameConfig.GUARDIAN_STAGGER_HIT_THRESHOLD, from_peer])
	_rpc_hit_flash.rpc()
	if _hits >= GameConfig.GUARDIAN_STAGGER_HIT_THRESHOLD:
		_hits = 0
		sync_state = State.STAGGERED
		_stagger_timer = GameConfig.GUARDIAN_STAGGER_DURATION
		Logx.info("sentinel", "Staggered")


## Read-only seams for tests. The Sentinel's brain is host-only and has no
## natural observation point, so these expose what it decided without exposing
## any way to change it.
func debug_hit_count() -> int:
	return _hits


func debug_target_peer() -> int:
	if _target == null or not is_instance_valid(_target):
		return 0
	return int(_target.get("owner_peer_id"))


func debug_state() -> int:
	return sync_state


func debug_nav_ready() -> bool:
	return _nav_ready


func debug_recovery_count() -> int:
	return _stuck_recoveries


func debug_stuck_seconds() -> float:
	return _stuck_timer


@rpc("authority", "call_local", "unreliable")
func _rpc_hit_flash() -> void:
	if _core == null:
		return
	var mat := _core.material_override as StandardMaterial3D
	if mat == null:
		return
	var tween := create_tween()
	tween.tween_property(mat, "emission_energy_multiplier", 2.6, 0.05)
	tween.tween_property(mat, "emission_energy_multiplier", 0.9, 0.2)


# ==========================================================================
# Presentation
# ==========================================================================

func _remote_present(delta: float) -> void:
	if global_position.distance_to(sync_position) > GameConfig.REMOTE_SNAP_DISTANCE:
		global_position = sync_position
	else:
		global_position = global_position.lerp(sync_position, clampf(GameConfig.REMOTE_SMOOTHING * delta, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, sync_yaw, clampf(GameConfig.REMOTE_SMOOTHING * delta, 0.0, 1.0))


func _present_common(delta: float) -> void:
	if _shell != null:
		_shell.rotate_y(delta * (0.4 if sync_state == State.STAGGERED else 1.1))
	var colour := _state_colour()
	if _light != null:
		_light.light_color = colour
		_light.light_energy = 0.7 if sync_state == State.STAGGERED else 1.5
	if _eye != null:
		var mat := _eye.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = colour
			mat.emission = colour


func _state_colour() -> Color:
	match sync_state:
		State.STAGGERED: return Color(0.45, 0.55, 1.0)
		State.SHOOT: return Color(1.0, 0.25, 0.2)
		State.CHASE: return Color(1.0, 0.55, 0.2)
		_: return Color(0.75, 0.75, 0.85)


func _apply_materials() -> void:
	# Emission is kept low deliberately. With glow on, anything much above 1
	# stops being "a glowing core" and becomes a white disc with a halo, taking
	# the whole silhouette with it.
	var core := StandardMaterial3D.new()
	core.albedo_color = Color(0.72, 0.26, 0.2)
	core.emission_enabled = true
	core.emission = Color(1.0, 0.4, 0.28)
	core.emission_energy_multiplier = 0.9
	_core.material_override = core

	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.24, 0.26, 0.33)
	shell.metallic = 0.7
	shell.roughness = 0.35
	_shell.material_override = shell

	var eye := StandardMaterial3D.new()
	eye.albedo_color = Color(1.0, 0.3, 0.24)
	eye.emission_enabled = true
	eye.emission = Color(1.0, 0.3, 0.24)
	eye.emission_energy_multiplier = 1.8
	_eye.material_override = eye


## A guard dies on GUARD_HITS_TO_KILL, unseals its crystal, and removes itself.
func _host_register_guard_hit() -> void:
	if not _is_host():
		return
	_guard_hits += 1
	AudioDirector.play(AudioDirector.Cue.SENTINEL_PROJECTILE)
	if _guard_hits < GameConfig.GUARD_HITS_TO_KILL:
		return
	Logx.info("sentinel", "guard on %s destroyed" % guards_crystal_id)
	GameManager.host_apply_guard_killed(guards_crystal_id)
	queue_free()
