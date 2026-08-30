extends CharacterBody3D
## Third-person cooperative player.
##
## AUTHORITY SPLIT (the single most important thing in this file)
##   * MotionSync  - authority is the OWNING PEER. Carries `sync_position`,
##     `sync_yaw` and a small motion flag set. Local input drives local motion so
##     the game feels responsive; motion is presentation, never permission.
##   * StateSync   - authority is the HOST. Carries health, downed, revive
##     progress and blaster heat. A client cannot write any of these, so it
##     cannot heal itself, un-down itself or cool its own weapon.
##
##   Gameplay-critical positions are read from `authoritative_position()`, which
##   returns the raw replicated value rather than the smoothed visual transform,
##   so interaction-range checks are not affected by interpolation.

const MOTION_GROUNDED := 1
const MOTION_SPRINTING := 2
const MOTION_MOVING := 4

## Set by SpawnManager before the node enters the tree.
var owner_peer_id: int = 0
var display_name: String = ""
var spawn_position: Vector3 = Vector3.ZERO
var spawn_yaw: float = 0.0

# --- MotionSync (owning peer authority) -----------------------------------
var sync_position: Vector3 = Vector3.ZERO
var sync_yaw: float = 0.0
var sync_flags: int = 0

# --- StateSync (host authority) -------------------------------------------
var health: int = GameConfig.MAX_HEALTH
var is_downed: bool = false
var is_alive: bool = true
var revive_progress: float = 0.0
var revive_active: bool = false
var heat: float = 0.0
var overheated: bool = false

# --- Local only -----------------------------------------------------------
var _pitch: float = 0.0
var _hovered: Node = null
var _hovered_prompt: String = ""
var _reviving_target: int = 0
var _interact_held: bool = false
## Last downed state the visuals were built for, so the refresh runs on change
## rather than 60 times a second per player.
var _visuals_downed: bool = not is_downed

# --- Local prediction -----------------------------------------------------
## Only used to avoid sending requests the host would obviously reject. It is
## NOT the rate check - the host keeps its own clock below.
var _local_next_fire_ms: int = 0

# --- Host only ------------------------------------------------------------
## The authoritative fire clock. A client that patches its own cooldown gains
## nothing: the host compares against this.
var _host_next_fire_ms: int = 0
var _host_fire_limiter: RateLimiter = null
## Rolling record used to detect impossible movement.
var _host_last_pos: Vector3 = Vector3.ZERO
var _host_last_pos_ms: int = 0
var _host_speed_strikes: int = 0

@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var _interact_ray: RayCast3D = $CameraPivot/InteractRay
@onready var _muzzle: Node3D = $CameraPivot/Muzzle
@onready var _nameplate: Label3D = $Nameplate
@onready var _body_mesh: MeshInstance3D = $Body/Mesh
@onready var _visor_mesh: MeshInstance3D = $Body/Visor
@onready var _downed_marker: Node3D = $DownedMarker
@onready var _motion_sync: MultiplayerSynchronizer = $MotionSync
@onready var _state_sync: MultiplayerSynchronizer = $StateSync


func _enter_tree() -> void:
	# Authority must be settled BEFORE the synchronizer children enter the tree.
	set_multiplayer_authority(owner_peer_id)
	var state_sync := get_node_or_null("StateSync")
	if state_sync != null:
		state_sync.set_multiplayer_authority(GameConfig.HOST_PEER_ID)
	_configure_replication()


func _ready() -> void:
	add_to_group(GameConfig.GROUP_PLAYER)
	global_position = spawn_position
	rotation.y = spawn_yaw
	sync_position = spawn_position
	sync_yaw = spawn_yaw
	_host_last_pos = spawn_position
	_host_last_pos_ms = Time.get_ticks_msec()

	collision_layer = GameConfig.LAYER_PLAYER
	collision_mask = GameConfig.LAYER_WORLD

	_interact_ray.target_position = Vector3(0.0, 0.0, -GameConfig.INTERACT_DISTANCE)
	_interact_ray.collision_mask = GameConfig.LAYER_INTERACTABLE | GameConfig.LAYER_WORLD | GameConfig.LAYER_PLAYER
	_interact_ray.add_exception(self)
	_interact_ray.collide_with_areas = true
	_interact_ray.collide_with_bodies = true

	_nameplate.text = display_name
	_apply_team_colour()

	if is_local():
		_camera.current = true
		_nameplate.visible = false
		_host_fire_limiter = null
	else:
		_camera.current = false

	if _is_host():
		_host_fire_limiter = RateLimiter.new(
			GameConfig.RATE_LIMIT_FIRE, GameConfig.RATE_LIMIT_FIRE,
			GameConfig.RATE_LIMIT_ABUSE_MULTIPLIER, GameConfig.RATE_LIMIT_ABUSE_WINDOW)

	SpawnManager.register_player(owner_peer_id, self)
	_refresh_downed_visuals()


func _exit_tree() -> void:
	is_alive = false
	SpawnManager.unregister_player(owner_peer_id, self)


func _configure_replication() -> void:
	var motion := get_node_or_null("MotionSync") as MultiplayerSynchronizer
	if motion != null:
		var mc := SceneReplicationConfig.new()
		for prop in ["sync_position", "sync_yaw", "sync_flags"]:
			var p := NodePath(".:" + prop)
			mc.add_property(p)
			mc.property_set_spawn(p, true)
			mc.property_set_replication_mode(p, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
		motion.replication_config = mc
		motion.replication_interval = 0.033

	var state := get_node_or_null("StateSync") as MultiplayerSynchronizer
	if state != null:
		var sc := SceneReplicationConfig.new()
		for prop in ["health", "is_downed", "is_alive", "revive_progress", "revive_active", "heat", "overheated"]:
			var p2 := NodePath(".:" + prop)
			sc.add_property(p2)
			sc.property_set_spawn(p2, true)
			sc.property_set_replication_mode(p2, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
		state.replication_config = sc
		state.delta_interval = 0.05
		state.replication_interval = 0.05


# ==========================================================================
# Identity helpers
# ==========================================================================

func is_local() -> bool:
	return owner_peer_id == NetworkManager.local_peer_id() or (owner_peer_id != 0 and NetworkManager.local_peer_id() == 0)


func _is_host() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


## Guard for HOST-ORIGINATED messages on THIS node.
##
## Subtle but important: a player node's multiplayer authority is the OWNING
## CLIENT (that is what makes motion client-driven). @rpc("authority") therefore
## means "only that client may call it" - which blocks the HOST from sending
## corrections and feedback to the owner, and Godot logs
## "RPC ... is not allowed on node ... Mode is 2, authority is <client>".
##
## Host-originated RPCs on this node are declared "any_peer" and gated here
## instead. A sender id of 0 means the call was made locally (call_local);
## anything other than 0 or the host id is a peer trying to impersonate the
## host and is dropped.
func _from_host() -> bool:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or sender == GameConfig.HOST_PEER_ID:
		return true
	Logx.reject("player", sender, "spoofed_host_message")
	return false


## Raw replicated position - NOT the smoothed visual transform. Every
## host-side range check must use this.
func authoritative_position() -> Vector3:
	return sync_position


func actor_state() -> Dictionary:
	return {
		"alive": is_alive,
		"downed": is_downed,
		"in_mission_scene": SceneManager.is_in_gameplay_scene(),
	}


func can_act() -> bool:
	return is_alive and not is_downed


# ==========================================================================
# Frame loop
# ==========================================================================

func _physics_process(delta: float) -> void:
	if is_local():
		_local_physics(delta)
	else:
		_remote_physics(delta)

	if _is_host():
		_host_cool_blaster(delta)
		_host_check_impossible_movement()

	_refresh_downed_visuals()


func _local_physics(delta: float) -> void:
	var on_floor := is_on_floor()
	if not on_floor:
		velocity.y -= float(ProjectSettings.get_setting("physics/3d/default_gravity", 24.0)) * delta

	var wish := Vector3.ZERO
	var sprinting := false
	if can_act() and not _menu_blocking_input():
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		wish = (transform.basis * Vector3(input.x, 0.0, input.y))
		wish.y = 0.0
		if wish.length_squared() > 1.0:
			wish = wish.normalized()
		sprinting = Input.is_action_pressed("sprint") and input.y < 0.0
		if on_floor and Input.is_action_just_pressed("jump"):
			velocity.y = GameConfig.JUMP_VELOCITY
			on_floor = false

	var target_speed := GameConfig.SPRINT_SPEED if sprinting else GameConfig.WALK_SPEED
	var target := wish * target_speed
	var accel := GameConfig.GROUND_ACCELERATION if on_floor else GameConfig.GROUND_ACCELERATION * GameConfig.AIR_CONTROL
	var friction := GameConfig.GROUND_FRICTION if on_floor else 0.0
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if target.length_squared() > 0.001:
		horizontal = horizontal.move_toward(target, accel * delta)
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, friction * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	move_and_slide()

	sync_position = global_position
	sync_yaw = rotation.y
	sync_flags = 0
	if is_on_floor():
		sync_flags |= MOTION_GROUNDED
	if sprinting:
		sync_flags |= MOTION_SPRINTING
	if horizontal.length_squared() > 0.25:
		sync_flags |= MOTION_MOVING

	_update_interaction_focus()
	_tick_local_actions()


func _remote_physics(delta: float) -> void:
	# Remote players are presentation. Never simulate them - just chase the
	# replicated transform, snapping on large jumps (respawn, teleport, reset).
	if global_position.distance_to(sync_position) > GameConfig.REMOTE_SNAP_DISTANCE:
		global_position = sync_position
	else:
		global_position = global_position.lerp(sync_position, clampf(GameConfig.REMOTE_SMOOTHING * delta, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, sync_yaw, clampf(GameConfig.REMOTE_SMOOTHING * delta, 0.0, 1.0))


func _menu_blocking_input() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return Input.mouse_mode != Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not is_local():
		return
	if event is InputEventMouseMotion and not _menu_blocking_input():
		var motion := event as InputEventMouseMotion
		var sens := SettingsManager.effective_mouse_sensitivity()
		var vertical := motion.relative.y * (-1.0 if SettingsManager.invert_look else 1.0)
		rotation.y -= motion.relative.x * sens
		_pitch = clampf(_pitch - vertical * sens,
			deg_to_rad(GameConfig.PITCH_MIN_DEG), deg_to_rad(GameConfig.PITCH_MAX_DEG))
		_camera_pivot.rotation.x = _pitch


# ==========================================================================
# Interaction (local)
# ==========================================================================

func _update_interaction_focus() -> void:
	_hovered = null
	_hovered_prompt = ""
	if not _interact_ray.is_colliding():
		return
	var hit := _interact_ray.get_collider()
	if hit == null:
		return
	var candidate := _resolve_interactable(hit)
	if candidate == null:
		return
	_hovered = candidate
	if candidate.has_method("get_interaction_prompt"):
		_hovered_prompt = String(candidate.get_interaction_prompt(self))


## The ray can land on a child collider; walk up to the node that implements
## the interactable contract.
func _resolve_interactable(node: Object) -> Node:
	var current := node as Node
	var guard := 0
	while current != null and guard < 6:
		guard += 1
		if current.is_in_group(GameConfig.GROUP_INTERACTABLE):
			return current
		if current.is_in_group(GameConfig.GROUP_PLAYER) and current != self:
			return current
		current = current.get_parent()
	return null


func hovered_prompt() -> String:
	return _hovered_prompt


func hovered_node() -> Node:
	return _hovered


func _tick_local_actions() -> void:
	if _menu_blocking_input():
		if _reviving_target != 0:
			_stop_revive()
		_interact_held = false
		return

	var pressed := Input.is_action_pressed("interact")

	# --- Revive: hold E on a downed teammate ---
	var revive_target := 0
	if _hovered != null and _hovered.is_in_group(GameConfig.GROUP_PLAYER) and _hovered != self:
		if bool(_hovered.get("is_downed")):
			revive_target = int(_hovered.get("owner_peer_id"))

	if pressed and revive_target != 0 and can_act():
		if _reviving_target != revive_target:
			_reviving_target = revive_target
			GameManager.request_revive_start(revive_target)
			AudioDirector.play(AudioDirector.Cue.REVIVE_START)
	elif _reviving_target != 0:
		_stop_revive()

	# --- Interact: single press on a world object ---
	if pressed and not _interact_held:
		_interact_held = true
		if revive_target == 0 and _hovered != null and _hovered.is_in_group(GameConfig.GROUP_INTERACTABLE):
			var oid := String(_hovered.get("object_id"))
			if not oid.is_empty():
				GameManager.request_interact(oid)
	elif not pressed:
		_interact_held = false

	# --- Fire ---
	if Input.is_action_pressed("fire") and can_act():
		_try_fire()


func _stop_revive() -> void:
	if _reviving_target == 0:
		return
	_reviving_target = 0
	GameManager.request_revive_stop()


# ==========================================================================
# Blaster
# ==========================================================================

func _try_fire() -> void:
	# Client-side gate purely to avoid flooding the host with requests it would
	# reject anyway. The HOST decision is the one that matters.
	if overheated or heat >= GameConfig.BLASTER_HEAT_MAX:
		return
	var now := Time.get_ticks_msec()
	if now < _local_next_fire_ms:
		return
	_local_next_fire_ms = now + int(GameConfig.BLASTER_FIRE_INTERVAL * 1000.0)

	var origin := _muzzle.global_position
	var direction := -_camera.global_transform.basis.z
	if _is_host():
		host_process_fire_request(GameConfig.HOST_PEER_ID, origin, direction, GameManager.session_epoch)
	else:
		_rpc_request_fire.rpc_id(GameConfig.HOST_PEER_ID, origin, direction, GameManager.session_epoch)


## CLIENT -> HOST.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_fire(origin: Vector3, direction: Vector3, epoch: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != owner_peer_id:
		Logx.reject("blaster", sender, "fire_wrong_owner")
		return
	host_process_fire_request(sender, origin, direction, epoch)


## THE authoritative shot decision. Returns true when the shot was taken.
## Called directly on the host and via _rpc_request_fire from a client, so both
## paths go through exactly the same checks.
func host_process_fire_request(peer_id: int, origin: Vector3, direction: Vector3, epoch: int) -> bool:
	if not _is_host():
		return false
	if epoch != GameManager.session_epoch:
		Logx.reject("blaster", peer_id, "fire_stale_epoch")
		return false
	# Flood guard first, so a spamming client cannot make the host do work.
	if _host_fire_limiter != null and not _host_fire_limiter.allow(peer_id):
		Logx.reject("blaster", peer_id, "fire_rate_limited")
		if _host_fire_limiter.is_abusive(peer_id):
			NetworkManager.host_kick_peer(peer_id, "Weapon request flood.")
		return false
	# Then the real cadence check, against the HOST's clock. The tolerance
	# absorbs client/host clock jitter without allowing a meaningfully faster
	# rate of fire.
	var now := Time.get_ticks_msec()
	if now < _host_next_fire_ms:
		Logx.reject("blaster", peer_id, "fire_too_soon")
		return false
	if not can_act():
		Logx.reject("blaster", peer_id, "fire_not_able")
		return false
	if not SceneManager.is_in_gameplay_scene():
		Logx.reject("blaster", peer_id, "fire_wrong_scene")
		return false
	if GameManager.is_mission_over():
		Logx.reject("blaster", peer_id, "fire_mission_over")
		return false
	if not origin.is_finite() or not direction.is_finite():
		Logx.reject("blaster", peer_id, "fire_non_finite")
		return false
	var dir := direction.normalized()
	if dir.length_squared() < 0.5:
		Logx.reject("blaster", peer_id, "fire_bad_direction")
		return false
	# The shot must start at the shooter, not wherever the client claims.
	if origin.distance_to(authoritative_position() + Vector3.UP * 1.4) > 2.5:
		Logx.reject("blaster", peer_id, "fire_origin_mismatch")
		return false
	if overheated or heat + GameConfig.BLASTER_HEAT_PER_SHOT > GameConfig.BLASTER_HEAT_MAX:
		Logx.reject("blaster", peer_id, "fire_overheated")
		return false

	_host_next_fire_ms = now + int(GameConfig.BLASTER_FIRE_INTERVAL * GameConfig.BLASTER_RATE_TOLERANCE * 1000.0)
	heat = minf(heat + GameConfig.BLASTER_HEAT_PER_SHOT, GameConfig.BLASTER_HEAT_MAX)
	if heat >= GameConfig.BLASTER_HEAT_MAX:
		overheated = true

	var hit_point: Vector3 = origin + dir * GameConfig.BLASTER_RANGE
	var space := get_world_3d().direct_space_state
	if space != null:
		var query := PhysicsRayQueryParameters3D.create(origin, hit_point)
		query.collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_ENEMY
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			hit_point = hit["position"]
			var collider := hit.get("collider") as Node
			var guardian := _find_guardian(collider)
			if guardian != null and guardian.has_method("host_register_hit"):
				guardian.host_register_hit(peer_id)

	_rpc_tracer.rpc(origin, hit_point)
	return true


func _find_guardian(node: Node) -> Node:
	var current := node
	var guard := 0
	while current != null and guard < 6:
		guard += 1
		if current.is_in_group(GameConfig.GROUP_GUARDIAN):
			return current
		current = current.get_parent()
	return null


## HOST -> ALL (including host). Pure visual; carries no gameplay meaning, which
## is why unreliable delivery is correct here.
@rpc("any_peer", "call_local", "unreliable")
func _rpc_tracer(from: Vector3, to: Vector3) -> void:
	if not _from_host():
		return
	AudioDirector.play(AudioDirector.Cue.BLASTER_FIRE)
	var stage := SceneManager.current_stage()
	if stage == null:
		return
	var tracer := preload("res://scenes/entities/blaster_tracer.tscn").instantiate()
	stage.add_child(tracer)
	if tracer.has_method("configure"):
		tracer.configure(from, to)


func _host_cool_blaster(delta: float) -> void:
	if heat <= 0.0:
		overheated = false
		return
	heat = maxf(heat - GameConfig.BLASTER_COOL_RATE * delta, 0.0)
	if overheated and heat <= GameConfig.BLASTER_HEAT_MAX * GameConfig.BLASTER_OVERHEAT_RESET_RATIO:
		overheated = false


# ==========================================================================
# Host: damage, downed, revive
# ==========================================================================

func host_apply_damage(amount: int, _source: String = "") -> void:
	if not _is_host():
		return
	if not is_alive or is_downed or amount <= 0:
		return
	if GameManager.is_mission_over():
		return
	health = maxi(health - amount, 0)
	if owner_peer_id == GameConfig.HOST_PEER_ID:
		AudioDirector.play(AudioDirector.Cue.PLAYER_HURT)
	elif NetworkManager.is_peer_connected(owner_peer_id):
		_rpc_hurt_feedback.rpc_id(owner_peer_id)
	if health <= 0:
		host_set_downed()


func host_set_downed() -> void:
	if not _is_host() or is_downed:
		return
	is_downed = true
	health = 0
	revive_progress = 0.0
	revive_active = false
	velocity = Vector3.ZERO
	Logx.info("player", "peer %d downed" % owner_peer_id)
	_rpc_downed_feedback.rpc()
	GameManager.host_on_player_downed(owner_peer_id)


func host_revive() -> void:
	if not _is_host() or not is_downed:
		return
	is_downed = false
	health = GameConfig.REVIVED_HEALTH
	revive_progress = 0.0
	revive_active = false
	Logx.info("player", "peer %d revived" % owner_peer_id)
	_rpc_revived_feedback.rpc()
	GameManager.host_on_player_revived(owner_peer_id)


func host_set_revive_progress(progress: float, active: bool) -> void:
	if not _is_host():
		return
	revive_progress = clampf(progress, 0.0, 1.0)
	revive_active = active


func host_full_reset(at_position: Vector3, yaw: float) -> void:
	if not _is_host():
		return
	health = GameConfig.MAX_HEALTH
	is_downed = false
	is_alive = true
	heat = 0.0
	overheated = false
	revive_progress = 0.0
	revive_active = false
	_host_next_fire_ms = 0
	_local_next_fire_ms = 0
	velocity = Vector3.ZERO
	global_position = at_position
	rotation.y = yaw
	sync_position = at_position
	sync_yaw = yaw
	# Re-baseline the movement validator: without this the host would read the
	# legitimate respawn teleport as impossible movement and snap the player
	# straight back to where they died.
	_host_last_pos = at_position
	_host_last_pos_ms = Time.get_ticks_msec()
	_host_speed_strikes = 0
	# The host already moved its own player above; only a remote owner needs the
	# corrective RPC, and only while it is still reachable.
	if owner_peer_id != GameConfig.HOST_PEER_ID and NetworkManager.is_peer_connected(owner_peer_id):
		_rpc_force_transform.rpc_id(owner_peer_id, at_position, yaw)


## HOST -> OWNER. The owner is the motion authority, so a corrective teleport has
## to be applied on their machine; the host cannot simply move them.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_force_transform(pos: Vector3, yaw: float) -> void:
	if not _from_host():
		return
	global_position = pos
	rotation.y = yaw
	sync_position = pos
	sync_yaw = yaw
	velocity = Vector3.ZERO


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hurt_feedback() -> void:
	if not _from_host():
		return
	AudioDirector.play(AudioDirector.Cue.PLAYER_HURT)


@rpc("any_peer", "call_local", "reliable")
func _rpc_downed_feedback() -> void:
	if not _from_host():
		return
	AudioDirector.play(AudioDirector.Cue.PLAYER_DOWNED)


@rpc("any_peer", "call_local", "reliable")
func _rpc_revived_feedback() -> void:
	if not _from_host():
		return
	AudioDirector.play(AudioDirector.Cue.REVIVE_COMPLETE)


# ==========================================================================
# Host: movement plausibility
# ==========================================================================

## Movement is client-driven for feel, so the host samples it and rejects the
## physically impossible. Three consecutive violations snap the player back to
## the last position the host accepted.
func _host_check_impossible_movement() -> void:
	if owner_peer_id == GameConfig.HOST_PEER_ID:
		return
	var now := Time.get_ticks_msec()
	var dt := float(now - _host_last_pos_ms) / 1000.0
	if dt < GameConfig.MOVEMENT_SAMPLE_INTERVAL:
		return
	_host_last_pos_ms = now
	var travelled := _host_last_pos.distance_to(sync_position)
	var ceiling := GameConfig.max_plausible_travel(dt)
	if travelled > ceiling:
		_host_speed_strikes += 1
		Logx.reject("player", owner_peer_id,
			"impossible_movement %.1fm in %.2fs (limit %.1fm, strike %d)" % [
				travelled, dt, ceiling, _host_speed_strikes])
		if _host_speed_strikes >= GameConfig.MOVEMENT_STRIKES_BEFORE_CORRECTION:
			_host_speed_strikes = 0
			if NetworkManager.is_peer_connected(owner_peer_id):
				_rpc_force_transform.rpc_id(owner_peer_id, _host_last_pos, sync_yaw)
			return
	else:
		_host_speed_strikes = maxi(_host_speed_strikes - 1, 0)
		_host_last_pos = sync_position


# ==========================================================================
# Presentation
# ==========================================================================

func set_revive_progress(progress: float, active: bool) -> void:
	revive_progress = progress
	revive_active = active


func _refresh_downed_visuals() -> void:
	if _visuals_downed == is_downed:
		return
	_visuals_downed = is_downed
	_downed_marker.visible = is_downed
	if _body_mesh.material_override is StandardMaterial3D:
		var mat := _body_mesh.material_override as StandardMaterial3D
		mat.albedo_color = Color(0.55, 0.16, 0.18) if is_downed else _team_colour()
	if not is_local():
		_nameplate.modulate = Color(1, 0.5, 0.5) if is_downed else Color(1, 1, 1)


func _apply_team_colour() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _team_colour()
	mat.metallic = 0.25
	mat.roughness = 0.55
	_body_mesh.material_override = mat
	var visor := StandardMaterial3D.new()
	visor.albedo_color = Color(0.15, 0.85, 1.0)
	visor.emission_enabled = true
	visor.emission = Color(0.15, 0.85, 1.0)
	visor.emission_energy_multiplier = 2.0
	_visor_mesh.material_override = visor


func _team_colour() -> Color:
	const PALETTE := [
		Color(0.29, 0.71, 0.94),
		Color(0.95, 0.62, 0.27),
		Color(0.51, 0.85, 0.44),
		Color(0.83, 0.47, 0.86),
	]
	var index := 0
	var sorted := LobbyManager.sorted_peer_ids()
	var found := sorted.find(owner_peer_id)
	if found >= 0:
		index = found
	return PALETTE[index % PALETTE.size()]
