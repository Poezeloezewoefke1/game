extends Node3D
## Assembles a run: map, camera, enemy/tower/projectile managers, hero, waves, boss, HUD.

var map_def: Dictionary = {}
var map_builder: MapBuilder
var path: MapPath
var enemies: EnemyManager
var projectiles: ProjectileManager
var towers: TowerManager
var waves: WaveManager
var boss: SaparataEncounter
var blimp: BlimpController
var hero: Hero
var camera_rig: Node3D
var camera: Camera3D
var hud
var vfx: Node3D

var placing_tower_id: String = ""
var placement_preview: Node3D
var placement_zone: int = -1
var _shake_time: float = 0.0
var _shake_strength: float = 0.0
var _cam_target: Vector3 = Vector3.ZERO
var _cam_distance: float = 34.0
var _cam_yaw: float = 0.0
var _cam_pitch: float = -0.95
var _ended: bool = false
var _float_texts: Array = []

func _ready() -> void:
	map_def = GameState.map_def()
	if map_def.is_empty():
		map_def = DataDB.maps.get("fort_feather", {})
		GameState.selected_map_id = "fort_feather"
	GameState.start_run(map_def)
	_build_world()
	_build_camera()
	_build_managers()
	_build_hero()
	_build_hud()
	_connect_signals()
	AudioMgr.play_music(String(map_def.get("music", "map_fort_feather")))
	_play_intro()

func _build_world() -> void:
	map_builder = MapBuilder.new()
	add_child(map_builder)
	path = map_builder.build(map_def)
	vfx = Node3D.new()
	add_child(vfx)

func _build_camera() -> void:
	camera_rig = Node3D.new()
	add_child(camera_rig)
	camera = Camera3D.new()
	camera.fov = 52.0
	camera.far = 400.0
	camera_rig.add_child(camera)
	# Frame the whole battlefield: centre on the middle of the path and pull back far enough that
	# both the entrance and the base are on screen.
	var mid := path.position_at(path.total_length * 0.5)
	var spread := 0.0
	for i in 9:
		var p := path.position_at(path.total_length * float(i) / 8.0)
		spread = maxf(spread, Vector2(p.x - mid.x, p.z - mid.z).length())
	_cam_target = Vector3(mid.x, 0, mid.z)
	_cam_distance = clampf(spread * 2.4, 28.0, 70.0)
	_cam_yaw = 0.35
	_cam_pitch = -0.95
	_update_camera()

func _build_managers() -> void:
	var faction: Dictionary = DataDB.factions.get(String(map_def.get("faction", "cindercrest")), {})
	enemies = EnemyManager.new()
	add_child(enemies)
	enemies.setup(path, faction, 1200)

	projectiles = ProjectileManager.new()
	add_child(projectiles)
	projectiles.setup(enemies)

	towers = TowerManager.new()
	add_child(towers)
	towers.setup(enemies, projectiles, map_def.get("build_zones", []))

	blimp = BlimpController.new()
	add_child(blimp)
	blimp.setup(enemies, map_def.get("blimp_route", {}))

	boss = SaparataEncounter.new()
	add_child(boss)
	boss.setup(enemies, towers, blimp)

	waves = WaveManager.new()
	add_child(waves)
	var wave_data: Dictionary = DataDB.waves.get(String(map_def.get("id", "")), {})
	waves.setup(enemies, wave_data, map_def)
	waves.boss_controller = boss
	waves.blimp_controller = blimp

func _build_hero() -> void:
	var hdef: Dictionary = GameState.hero_def()
	if hdef.is_empty():
		hdef = DataDB.heroes.get("parrotx2", {})
	hero = Hero.new()
	add_child(hero)
	hero.setup(String(hdef.get("id", "parrotx2")), hdef, enemies, projectiles, towers)
	towers.hero = hero
	# Place the hero on the keep zone if there is one, otherwise near the base.
	var placed := false
	for i in towers.zones.size():
		if String(towers.zones[i]["type"]) == "keep":
			hero.position = (towers.zones[i]["pos"] as Vector3) + Vector3(0, float(towers.zones[i]["elevation"]), 0)
			placed = true
			break
	if not placed:
		var bp: Array = map_def.get("base_position", [0, 0, 0])
		hero.position = Vector3(bp[0], bp[1], bp[2] - 3.0)
	towers.refresh_auras()
	EventBus.hero_placed.emit(hero)

func _build_hud() -> void:
	hud = load("res://scripts/ui/game_hud.gd").new()
	add_child(hud)
	hud.setup(self)

func _connect_signals() -> void:
	EventBus.run_defeat.connect(_on_defeat)
	EventBus.all_waves_cleared.connect(_on_all_waves_cleared)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.wave_cleared.connect(_on_wave_cleared)
	EventBus.camera_shake.connect(_on_camera_shake)
	EventBus.boss_event.connect(_on_boss_event)
	EventBus.float_text.connect(_on_float_text)
	boss.defeated.connect(_on_boss_defeated)

func _play_intro() -> void:
	var intro: Dictionary = map_def.get("intro", {})
	if intro.is_empty():
		return
	EventBus.announce.emit(String(intro.get("title", "")), String(intro.get("subtitle", "")), 3.5)
	var delay := 3.0
	for line in intro.get("lines", []):
		var l: Dictionary = line
		await get_tree().create_timer(delay).timeout
		if _ended or not is_inside_tree():
			return
		EventBus.dialogue.emit(String(l.get("speaker", "")), String(l.get("text", "")), 5.0)
		delay = 5.2

# ================================================================================================
# Input
# ================================================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if placing_tower_id != "":
			cancel_placement()
		else:
			hud.toggle_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("start_wave"):
		if not waves.running:
			waves.start_next_wave()
	if event.is_action_pressed("toggle_speed"):
		GameState.set_speed(1.0 if GameState.game_speed >= 2.0 else (GameState.game_speed + 1.0))
	if event.is_action_pressed("toggle_range"):
		towers.show_all_ranges(true)
	if event.is_action_released("toggle_range"):
		towers.show_all_ranges(false)
	for i in 3:
		if event.is_action_pressed("ability_%d" % (i + 1)):
			hero.use_ability(i)
	if event.is_action_pressed("ultimate"):
		hero.use_ability(3)
	if event.is_action_pressed("sell") and towers.selected != null:
		towers.sell(towers.selected)
	if event.is_action_pressed("zoom_in"):
		_cam_distance = clampf(_cam_distance - 2.5, 12.0, 70.0)
		_update_camera()
	if event.is_action_pressed("zoom_out"):
		_cam_distance = clampf(_cam_distance + 2.5, 12.0, 70.0)
		_update_camera()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click(event.position)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if placing_tower_id != "":
			cancel_placement()
		else:
			towers.select(null)
	if event is InputEventMouseMotion and placing_tower_id != "":
		_update_placement_preview(event.position)

func _handle_click(screen_pos: Vector2) -> void:
	if placing_tower_id != "":
		_try_place(screen_pos)
		return
	var t: Tower = towers.tower_at_screen(camera, screen_pos)
	if t != null:
		towers.select(t)
		return
	# clicking the hero selects it
	var ground := _ground_point(screen_pos)
	if hero != null and ground.distance_to(hero.global_position) < 1.6:
		towers.select(null)
		hud.show_hero_panel()
		return
	towers.select(null)

func _ground_point(screen_pos: Vector2) -> Vector3:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return from
	# Intersect a set of candidate heights so elevated zones can be clicked.
	var best := from + dir * 100.0
	var best_dist := INF
	for h: float in [0.0, 1.5, 2.0, 2.5, 3.5]:
		var t := (h - from.y) / dir.y
		if t <= 0.0:
			continue
		var p := from + dir * t
		var zi := towers.zone_at(p)
		if zi >= 0:
			var z: Dictionary = towers.zones[zi]
			if absf(float(z["elevation"]) - h) < 0.6 and t < best_dist:
				best_dist = t
				best = p
	if best_dist < INF:
		return best
	var t0 := -from.y / dir.y
	return from + dir * maxf(t0, 0.0)

func begin_placement(tower_id: String) -> void:
	placing_tower_id = tower_id
	if is_instance_valid(placement_preview):
		placement_preview.queue_free()
	var def: Dictionary = DataDB.towers.get(tower_id, {})
	placement_preview = MinecraftCharacter.new()
	add_child(placement_preview)
	(placement_preview as MinecraftCharacter).setup(
		SkinLibrary.get_skin(String(def.get("character", tower_id))),
		def.get("armor", {}), String(def.get("weapon", "")), true)
	(placement_preview as MinecraftCharacter).set_ghost(0.55)
	map_builder.show_zone_markers(true)
	for i in towers.zones.size():
		map_builder.set_zone_marker_state(i, towers.can_place_at(i))
	EventBus.placement_started.emit(tower_id)

func cancel_placement() -> void:
	placing_tower_id = ""
	if is_instance_valid(placement_preview):
		placement_preview.queue_free()
	map_builder.show_zone_markers(false)
	EventBus.placement_cancelled.emit()

func _update_placement_preview(screen_pos: Vector2) -> void:
	if not is_instance_valid(placement_preview):
		return
	var p := _ground_point(screen_pos)
	placement_zone = towers.zone_at(p)
	if placement_zone >= 0:
		var z: Dictionary = towers.zones[placement_zone]
		placement_preview.position = (z["pos"] as Vector3) + Vector3(0, float(z["elevation"]), 0)
		var ok := towers.can_place_at(placement_zone) and GameState.can_afford(int(DataDB.towers[placing_tower_id].get("cost", 0)))
		(placement_preview as MinecraftCharacter).set_tint(Color(0.6, 1.0, 0.6) if ok else Color(1.0, 0.5, 0.5))
	else:
		placement_preview.position = p
		(placement_preview as MinecraftCharacter).set_tint(Color(1.0, 0.5, 0.5))

func _try_place(screen_pos: Vector2) -> void:
	var p := _ground_point(screen_pos)
	var zone := towers.zone_at(p)
	if zone < 0 or not towers.can_place_at(zone):
		AudioMgr.play_sfx("denied", -6.0)
		return
	var t := towers.place(placing_tower_id, zone)
	if t != null:
		map_builder.set_zone_marker_state(zone, false)
		cancel_placement()
		towers.select(t)
	else:
		AudioMgr.play_sfx("denied", -6.0)

# ================================================================================================
# Camera
# ================================================================================================

func _process(delta: float) -> void:
	_update_camera_input(delta)
	_update_shake(delta)
	_update_float_texts(delta)

func _update_camera_input(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_action_pressed("cam_left"):
		move.x -= 1.0
	if Input.is_action_pressed("cam_right"):
		move.x += 1.0
	if Input.is_action_pressed("cam_forward"):
		move.y -= 1.0
	if Input.is_action_pressed("cam_back"):
		move.y += 1.0
	if Input.is_action_pressed("cam_rotate_left"):
		_cam_yaw -= delta * 1.2
	if Input.is_action_pressed("cam_rotate_right"):
		_cam_yaw += delta * 1.2
	if move != Vector2.ZERO:
		var speed := _cam_distance * 0.9 * delta
		var forward := Vector3(sin(_cam_yaw), 0, cos(_cam_yaw))
		var right := Vector3(cos(_cam_yaw), 0, -sin(_cam_yaw))
		_cam_target += (right * move.x + forward * move.y) * speed
		_cam_target.x = clampf(_cam_target.x, -60.0, 60.0)
		_cam_target.z = clampf(_cam_target.z, -60.0, 60.0)
	_update_camera()

func _update_camera() -> void:
	if camera == null:
		return
	var offset := Vector3(
		sin(_cam_yaw) * cos(_cam_pitch),
		-sin(_cam_pitch),
		cos(_cam_yaw) * cos(_cam_pitch)
	) * _cam_distance
	camera.position = _cam_target + offset
	camera.look_at(_cam_target, Vector3.UP)

func _on_camera_shake(strength: float, duration: float) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	_shake_time = maxf(_shake_time, duration)

func _update_shake(delta: float) -> void:
	if _shake_time <= 0.0:
		return
	_shake_time -= delta
	var amp := _shake_strength * clampf(_shake_time, 0.0, 1.0)
	camera.h_offset = randf_range(-amp, amp) * 0.4
	camera.v_offset = randf_range(-amp, amp) * 0.4
	if _shake_time <= 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		_shake_strength = 0.0

func focus_on(point: Vector3) -> void:
	_cam_target = Vector3(point.x, 0, point.z)
	_update_camera()

# ================================================================================================
# Effects and events
# ================================================================================================

func _on_boss_event(event_id: String, payload: Dictionary) -> void:
	match event_id:
		"orbital_telegraph":
			_spawn_marker(payload.get("position", Vector3.ZERO), float(payload.get("radius", 4.0)), Color(1.0, 0.3, 0.2, 0.5), float(payload.get("delay", 1.0)))
		"orbital_impact", "web_burst", "purgatory":
			var color := Color(1.0, 0.6, 0.2, 0.6)
			if event_id == "web_burst":
				color = Color(0.9, 0.9, 1.0, 0.6)
			elif event_id == "purgatory":
				color = Color(0.6, 0.4, 1.0, 0.6)
			_spawn_marker(payload.get("position", Vector3.ZERO), float(payload.get("radius", 4.0)), color, 0.6)
		"ember_strike":
			_spawn_marker(payload.get("position", Vector3.ZERO), 1.6, Color(1.0, 0.4, 0.1, 0.7), 0.5)

func _spawn_marker(pos: Vector3, radius: float, color: Color, duration: float) -> void:
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.85
	torus.outer_radius = radius
	torus.rings = 32
	mi.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mi.material_override = mat
	mi.position = pos + Vector3(0, 0.15, 0)
	vfx.add_child(mi)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	tw.tween_callback(mi.queue_free)

func _on_float_text(pos: Vector3, text: String, color: Color) -> void:
	if text == "" or not bool(SaveSystem.get_setting("show_damage_numbers", true)):
		return
	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.font_size = 42
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = pos + Vector3(0, 1.8, 0)
	vfx.add_child(label)
	_float_texts.append({"node": label, "life": 1.1})

func _update_float_texts(delta: float) -> void:
	var w := 0
	for ft in _float_texts:
		var node: Label3D = ft["node"]
		if not is_instance_valid(node):
			continue
		ft["life"] = float(ft["life"]) - delta
		node.position.y += delta * 1.4
		node.modulate.a = clampf(float(ft["life"]), 0.0, 1.0)
		if float(ft["life"]) <= 0.0:
			node.queue_free()
			continue
		_float_texts[w] = ft
		w += 1
	_float_texts.resize(w)

func _on_enemy_killed(slot: int, _type_id: String, killer_id: String) -> void:
	if hero != null and is_instance_valid(hero):
		hero.on_enemy_killed(slot, killer_id)
		if killer_id != hero.hero_id:
			hero.add_xp(1)

func _on_wave_cleared(_index: int) -> void:
	towers.on_wave_cleared()
	if hero != null:
		hero.on_wave_cleared()

func _on_all_waves_cleared() -> void:
	if _ended:
		return
	_ended = true
	GameState.run_active = false
	_finish_run(true)

func _on_boss_defeated() -> void:
	pass

func _on_defeat(_stats: Dictionary) -> void:
	if _ended:
		return
	# The hero's death-save passive can cancel a fatal leak once per run.
	if hero != null and GameState.lives <= 0 and hero.consume_death_save():
		GameState.lives = maxi(1, int(GameState.max_lives * 0.15))
		GameState.run_active = true
		EventBus.lives_changed.emit(GameState.lives, GameState.max_lives)
		return
	_ended = true
	_finish_run(false)

func _finish_run(won: bool) -> void:
	enemies.enabled = false
	var stats: Dictionary = GameState.run_stats.duplicate()
	stats["won"] = won
	stats["waves"] = waves.wave_index + 1
	stats["total_waves"] = waves.total_waves()
	stats["hero"] = hero.hero_id if hero != null else ""
	stats["hero_level"] = hero.level if hero != null else 1
	stats["map"] = String(map_def.get("id", ""))
	var xp_earned := int(stats.get("kills", 0)) * 2 + (400 if won else 60)
	var bottles := int(stats.get("kills", 0)) / 4 + (150 if won else 20)
	stats["xp_earned"] = xp_earned
	stats["bottles"] = bottles
	SaveSystem.record_run_result(String(map_def.get("id", "")), stats["hero"], won, waves.wave_index + 1, xp_earned, bottles)
	_unlock_codex_for_run()
	if won:
		AudioMgr.play_music("victory", 0.4)
	else:
		AudioMgr.play_music("defeat", 0.4)
	var outro: Dictionary = map_def.get("outro_victory" if won else "outro_defeat", {})
	hud.show_results(stats, outro)

func _unlock_codex_for_run() -> void:
	SaveSystem.unlock_codex("map_" + String(map_def.get("id", "")))
	if hero != null:
		SaveSystem.unlock_codex("hero_" + hero.hero_id)
	for t in towers.towers:
		if is_instance_valid(t):
			SaveSystem.unlock_codex("tower_" + t.tower_id)
	for r in towers.active_relationships:
		SaveSystem.unlock_codex("rel_" + String(r["id"]))
	if bool(GameState.run_stats.get("boss_defeated", false)):
		SaveSystem.unlock_codex("boss_saparata")
	SaveSystem.save_game()

func restart() -> void:
	GameState.end_run()
	get_tree().call_deferred("reload_current_scene")

func quit_to_menu() -> void:
	GameState.end_run()
	AudioMgr.play_music("menu")
	var main := get_parent()
	if main != null and main.has_method("go_to_main_menu"):
		main.go_to_main_menu()
