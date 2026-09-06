class_name BlimpController
extends Node3D
## The Cindercrest Redstone Blimp: a destructible airship that crosses the map dropping slow-falling
## paratroopers behind the walls. Shooting it down stops the drops early.
## (Fort Feather fell to exactly this manoeuvre.)

signal destroyed()
signal finished()

var enemies: EnemyManager
var mesh_instance: MeshInstance3D
var active: bool = false
var from: Vector3 = Vector3.ZERO
var to: Vector3 = Vector3.ZERO
var travel: float = 0.0
var duration: float = 26.0
var drops_left: int = 0
var drop_interval: float = 1.2
var drop_timer: float = 0.0
var drop_window: Vector2 = Vector2(0.35, 0.85)
var slot: int = -1

func setup(enemy_mgr: EnemyManager, route: Dictionary) -> void:
	enemies = enemy_mgr
	var f: Array = route.get("from", [-40, 9, -30])
	var t: Array = route.get("to", [40, 9, 30])
	from = Vector3(f[0], f[1], f[2])
	to = Vector3(t[0], t[1], t[2])
	var dr: Array = route.get("drop_range", [0.35, 0.85])
	drop_window = Vector2(dr[0], dr[1])
	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = PropBuilder.get_mesh("blimp")
	mesh_instance.material_override = MCMaterials.make(SkinLibrary.get_skin("cindercrest_soldier").get_texture(), false, false)
	mesh_instance.scale = Vector3(0.09, 0.09, 0.09)
	mesh_instance.visible = false
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh_instance)

func launch(paratroopers: int, interval: float) -> void:
	if active:
		return
	active = true
	travel = 0.0
	drops_left = paratroopers
	drop_interval = interval
	drop_timer = 0.0
	mesh_instance.visible = true
	# The blimp itself is an off-path enemy so towers can shoot it down.
	slot = enemies.spawn("blimp", 0.0, 0.0)
	if slot >= 0:
		enemies.scripted[slot] = 1
		enemies.flags[slot] = enemies.flags[slot] | EnemyManager.F_OFF_PATH
	AudioMgr.play_sfx("blimp", -3.0)
	EventBus.camera_shake.emit(0.2, 0.5)

func _process(delta: float) -> void:
	if not active:
		return
	travel += delta / duration
	var pos := from.lerp(to, clampf(travel, 0.0, 1.0))
	pos.y += sin(travel * 8.0) * 0.4
	mesh_instance.global_position = pos
	var dir := (to - from).normalized()
	mesh_instance.look_at(pos + dir, Vector3.UP)
	if slot >= 0 and enemies.is_alive(slot):
		enemies.pos_x[slot] = pos.x
		enemies.pos_y[slot] = pos.y
		enemies.pos_z[slot] = pos.z
	elif slot >= 0:
		_shot_down()
		return
	if drops_left > 0 and travel >= drop_window.x and travel <= drop_window.y:
		drop_timer -= delta
		if drop_timer <= 0.0:
			drop_timer = drop_interval
			_drop_paratrooper(pos)
	if travel >= 1.0:
		_finish()

func _drop_paratrooper(from_pos: Vector3) -> void:
	if enemies.path == null:
		return
	drops_left -= 1
	# Land them where the blimp currently is, projected onto the path.
	var d := enemies.path.nearest_distance_to(from_pos)
	d = clampf(d, enemies.path.total_length * 0.35, enemies.path.total_length * 0.85)
	var s := enemies.spawn("paratrooper", d, randf_range(-0.8, 0.8))
	if s >= 0:
		enemies.y_offset[s] = maxf(4.0, from_pos.y - enemies.path.position_at(d).y)
	AudioMgr.play_sfx_at("drop", from_pos, -10.0)

func _shot_down() -> void:
	active = false
	slot = -1
	mesh_instance.visible = false
	EventBus.announce.emit("BLIMP DOWN", "No more paratroopers.", 2.4)
	EventBus.camera_shake.emit(0.8, 0.6)
	AudioMgr.play_sfx("explosion", 0.0)
	destroyed.emit()
	finished.emit()

func _finish() -> void:
	active = false
	mesh_instance.visible = false
	if slot >= 0 and enemies.is_alive(slot):
		enemies.kill(slot, "escaped", false)
	slot = -1
	finished.emit()
