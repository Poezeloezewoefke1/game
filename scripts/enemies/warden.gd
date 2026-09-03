extends CharacterBody3D
## THE WARDEN - what the temple was actually protecting.
##
## Wakes when the Star Map leaves the altar and has to be killed before the crew
## can extract. Three phases:
##
##   SHIELDED  invulnerable. Three shield nodes orbit it; each has its own
##             health and its own collider, and the body ignores every shot
##             until all three are down. This is the phase that makes the fight
##             a fight rather than a health bar: four players have to split up
##             and pick targets instead of all holding the trigger on the middle.
##   VOLLEY    exposed. Fires spreads at the Star Map carrier by preference,
##             because the person holding the objective should feel hunted.
##   ENRAGED   below BOSS_ENRAGE_FRACTION health: faster, shorter volleys,
##             closes to contact range.
##
## AUTHORITY: the host runs all of it. Clients receive position, yaw, phase,
## health and the shield bitmask, and present them. A client cannot damage it,
## change its phase, or move it.
##
## WHY IT FLIES AND THE SENTINEL WALKS. The Sentinel uses a NavigationAgent3D
## and carries three separate workarounds for the ways that breaks. The Warden
## hovers over the temple plateau on direct steering with a height hold, so it
## needs no navmesh at all - which removes that entire class of failure from the
## most important fight in the game.

## Written out in full rather than aliased: `const MR := MissionRules` is not a
## constant expression, and the alias buys nothing but a failed compile.

## Shield nodes are a bitmask rather than an array because a bitmask replicates
## as one int and cannot arrive half-applied.
const NODE_BITS: int = 0b111

# --- Replicated (host authority) ------------------------------------------
var sync_position: Vector3 = Vector3.ZERO
var sync_yaw: float = 0.0
var sync_phase: int = MissionRules.BOSS_SHIELDED
var sync_health: int = GameConfig.BOSS_MAX_HEALTH
var sync_nodes: int = NODE_BITS

# --- Host only -------------------------------------------------------------
var spawn_position: Vector3 = Vector3.ZERO
var _node_health: Array[int] = []
var _volley_timer: float = 0.0
var _contact_timer: float = 0.0
var _spin: float = 0.0
var _target: Node3D = null
var _retarget_timer: float = 0.0

@onready var _hull: MeshInstance3D = $Hull
@onready var _eye: MeshInstance3D = $Eye
@onready var _shield: MeshInstance3D = $Shield
@onready var _ring: Node3D = $ShieldRing
@onready var _light: OmniLight3D = $CoreLight
@onready var _muzzle: Node3D = $Muzzle
@onready var _sync: MultiplayerSynchronizer = $StateSync


func _ready() -> void:
	add_to_group(GameConfig.GROUP_GUARDIAN)
	add_to_group(GameConfig.GROUP_BOSS)
	add_to_group(GameConfig.GROUP_SESSION_BOUND)
	collision_layer = GameConfig.LAYER_ENEMY
	collision_mask = GameConfig.LAYER_WORLD
	PropBuilder.build_warden(self, _hull, _eye, _shield, _ring)
	_configure_replication()
	if _is_host():
		# Sized to the crew, like the body's health. See MissionRules.boss_scale:
		# a solo player still has to break all three nodes, they are just not
		# four players' worth of health each.
		_node_health.resize(3)
		_node_health.fill(int(round(
			float(GameConfig.BOSS_SHIELD_NODE_HEALTH) * _crew_scale())))
		sync_health = int(GameManager.snapshot.get("boss_health", GameConfig.BOSS_MAX_HEALTH))
		global_position = spawn_position
		sync_position = spawn_position
		_publish_to_snapshot()
	else:
		global_position = sync_position
	_refresh_visuals()


## The crew this fight was sized for, recorded in the snapshot when the Warden
## woke so that a player joining or leaving mid-fight cannot resize the boss
## underneath everyone.
func _crew() -> int:
	return maxi(int(GameManager.snapshot.get("boss_crew", 1)), 1)


func _crew_scale() -> float:
	return MissionRules.boss_scale(_crew())


func _scaled_max_health() -> float:
	return float(GameConfig.BOSS_MAX_HEALTH) * _crew_scale()


func _configure_replication() -> void:
	var config := SceneReplicationConfig.new()
	for prop in ["sync_position", "sync_yaw", "sync_phase", "sync_health", "sync_nodes"]:
		var path := NodePath(".:%s" % prop)
		config.add_property(path)
		config.property_set_replication_mode(path,
			SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	_sync.replication_config = config
	# Authority is the host, always. This is the line that makes every other
	# claim in the header true.
	_sync.set_multiplayer_authority(GameConfig.HOST_PEER_ID)


func _is_host() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()


# ==========================================================================
# Frame loop
# ==========================================================================

func _physics_process(delta: float) -> void:
	_spin += delta
	if _is_host():
		_host_think(delta)
	else:
		global_position = global_position.lerp(sync_position,
			clampf(GameConfig.REMOTE_SMOOTHING * delta, 0.0, 1.0))
		rotation.y = lerp_angle(rotation.y, sync_yaw,
			clampf(GameConfig.REMOTE_SMOOTHING * delta, 0.0, 1.0))
	_animate(delta)
	_refresh_visuals()


func _host_think(delta: float) -> void:
	if sync_phase == MissionRules.BOSS_DEAD:
		return
	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = 0.8
		_target = _pick_target()

	var speed := GameConfig.BOSS_MOVE_SPEED
	var stand_off := 11.0
	if sync_phase == MissionRules.BOSS_ENRAGED:
		speed = GameConfig.BOSS_ENRAGED_MOVE_SPEED
		stand_off = 3.0

	if _target != null and is_instance_valid(_target):
		var to_target: Vector3 = _target.global_position - global_position
		to_target.y = 0.0
		var distance := to_target.length()
		if distance > 0.05:
			rotation.y = lerp_angle(rotation.y, atan2(-to_target.x, -to_target.z), 3.0 * delta)
		# Hold a stand-off ring rather than sitting on top of the player: a boss
		# inside your own hitbox is impossible to aim at and impossible to read.
		var drive: Vector3 = to_target.normalized() * signf(distance - stand_off)
		velocity.x = drive.x * speed
		velocity.z = drive.z * speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	# Height hold: hover above whatever is below, so it drifts over the temple
	# rather than clipping into it.
	var want_y := spawn_position.y + GameConfig.BOSS_HOVER_HEIGHT
	velocity.y = clampf((want_y - global_position.y) * 2.4, -6.0, 6.0)
	move_and_slide()

	if sync_phase != MissionRules.BOSS_SHIELDED:
		_host_fire(delta)
	if sync_phase == MissionRules.BOSS_ENRAGED:
		_host_contact_damage(delta)

	sync_position = global_position
	sync_yaw = rotation.y


## Prefers whoever is carrying the Star Map, then the nearest player who can
## still act. Downed players are never targeted - the fight should not finish
## itself off while the crew is trying to revive someone.
func _pick_target() -> Node3D:
	var carrier := GameManager.star_map_carrier()
	if carrier != 0:
		var node: Node = SpawnManager.player_node(carrier)
		if node != null and not bool(node.get("is_downed")):
			return node as Node3D
	var best: Node3D = null
	var best_distance := INF
	for peer_id in LobbyManager.sorted_peer_ids():
		var candidate: Node = SpawnManager.player_node(int(peer_id))
		if candidate == null or bool(candidate.get("is_downed")):
			continue
		var d: float = global_position.distance_to((candidate as Node3D).global_position)
		if d < best_distance:
			best_distance = d
			best = candidate as Node3D
	return best


func _host_fire(delta: float) -> void:
	_volley_timer -= delta
	if _volley_timer > 0.0 or _target == null or not is_instance_valid(_target):
		return
	_volley_timer = MissionRules.boss_volley_interval(
		_crew(), sync_phase == MissionRules.BOSS_ENRAGED)
	var origin: Vector3 = _muzzle.global_position
	var aim: Vector3 = (_target.global_position + Vector3(0.0, 1.0, 0.0) - origin).normalized()
	# A spread rather than a single shot: one projectile is dodgeable by walking,
	# three force a decision about which way.
	var spread := 0.13
	for i in GameConfig.BOSS_VOLLEY_PROJECTILES:
		var offset := float(i) - float(GameConfig.BOSS_VOLLEY_PROJECTILES - 1) * 0.5
		var dir := aim.rotated(Vector3.UP, offset * spread).normalized()
		SpawnManager.host_spawn_guardian_projectile(origin, dir)
	AudioDirector.play(AudioDirector.Cue.WARDEN_VOLLEY)


func _host_contact_damage(delta: float) -> void:
	_contact_timer -= delta
	if _contact_timer > 0.0:
		return
	for peer_id in LobbyManager.sorted_peer_ids():
		var node: Node = SpawnManager.player_node(int(peer_id))
		if node == null or bool(node.get("is_downed")):
			continue
		if global_position.distance_to((node as Node3D).global_position) > 3.2:
			continue
		if node.has_method("host_apply_damage"):
			node.host_apply_damage(GameConfig.BOSS_CONTACT_DAMAGE)
			_contact_timer = 1.0


# ==========================================================================
# Damage
# ==========================================================================

## Called by the host when a blaster ray connects. `part` is the collider that
## was actually hit, which is how a shot at a shield node is told from a shot at
## the body - without it the shield phase would be decorative.
func host_register_hit(from_peer: int, part: Node = null) -> void:
	if not _is_host() or sync_phase == MissionRules.BOSS_DEAD:
		return
	var index := _node_index_of(part)
	if index >= 0:
		_host_damage_node(index, from_peer)
		return
	if not MissionRules.boss_takes_damage(GameManager.snapshot):
		# Shots on a shielded body are refused loudly enough to be legible in a
		# log, and silently in game beyond the shield's own flash.
		return
	sync_health = maxi(sync_health - GameConfig.BLASTER_BOSS_DAMAGE, 0)
	_host_update_phase()


func _node_index_of(part: Node) -> int:
	var current := part
	var guard := 0
	while current != null and guard < 4:
		guard += 1
		if current.get_meta("shield_index", -1) != -1:
			return int(current.get_meta("shield_index"))
		current = current.get_parent()
	return -1


func _host_damage_node(index: int, _from_peer: int) -> void:
	if index < 0 or index >= _node_health.size():
		return
	if (sync_nodes & (1 << index)) == 0:
		return
	_node_health[index] = maxi(_node_health[index] - GameConfig.BLASTER_BOSS_DAMAGE, 0)
	if _node_health[index] > 0:
		return
	sync_nodes &= ~(1 << index)
	Logx.info("warden", "shield node %d down (%d left)" % [index, _alive_node_count()])
	AudioDirector.play(AudioDirector.Cue.WARDEN_SHIELD_BREAK)
	_host_update_phase()


func _alive_node_count() -> int:
	var n := 0
	for i in 3:
		if (sync_nodes & (1 << i)) != 0:
			n += 1
	return n


func _host_update_phase() -> void:
	var fraction := health_fraction()
	var next := MissionRules.boss_phase_for(fraction, _alive_node_count())
	if next != sync_phase:
		sync_phase = next
		Logx.info("warden", "phase -> %d (health %d, nodes %d)"
			% [sync_phase, sync_health, _alive_node_count()])
	_publish_to_snapshot()
	if sync_phase == MissionRules.BOSS_DEAD:
		GameManager.host_on_boss_killed()


func _publish_to_snapshot() -> void:
	GameManager.host_set_boss_state(sync_phase, sync_health, _alive_node_count())


# ==========================================================================
# Presentation
# ==========================================================================

func _animate(delta: float) -> void:
	# The shield ring counter-rotates against the hull, which reads as machinery
	# holding something in rather than as one spinning object.
	if _ring != null:
		_ring.rotation.y -= delta * 0.9
	if _hull != null:
		_hull.rotation.y += delta * 0.35
	for i in 3:
		var child := _ring.get_node_or_null("Node%d" % (i + 1)) as Node3D
		if child != null:
			child.visible = (sync_nodes & (1 << i)) != 0


func _refresh_visuals() -> void:
	var shielded := sync_phase == MissionRules.BOSS_SHIELDED
	if _shield != null:
		_shield.visible = shielded
	var colour := Color(0.42, 0.78, 1.0)
	if sync_phase == MissionRules.BOSS_VOLLEY:
		colour = Color(1.0, 0.68, 0.24)
	elif sync_phase == MissionRules.BOSS_ENRAGED:
		colour = Color(1.0, 0.28, 0.22)
	elif sync_phase == MissionRules.BOSS_DEAD:
		colour = Color(0.25, 0.25, 0.28)
	ModelKit.set_emission(_eye, colour, 2.6 if sync_phase != MissionRules.BOSS_DEAD else 0.2)
	if _light != null:
		_light.light_color = colour
		_light.light_energy = 2.2 if sync_phase != MissionRules.BOSS_DEAD else 0.2


func health_fraction() -> float:
	return float(sync_health) / maxf(_scaled_max_health(), 1.0)
