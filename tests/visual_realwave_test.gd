extends Node3D
## Runs the REAL game with the REAL wave flow (no staged spawns) and holds for a screenshot once
## enemies are actually on the path. This is what the player sees; visual_game_test.gd spawns its own
## enemies and so cannot catch a bug in the live spawn-to-render path.

var game
var reported := false

func _ready() -> void:
	game = load("res://scripts/core/game_controller.gd").new()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.add_emeralds(50000)
	# A few towers so the scene is not bare, placed the way a player would.
	var plan := ["royal_guard", "theobaldthebird", "mapicc", "spepticle"]
	var zone := 0
	for id in plan:
		while zone < game.towers.zones.size() and not game.towers.can_place_at(zone):
			zone += 1
		if zone >= game.towers.zones.size():
			break
		game.towers.place(id, zone)
		zone += 2
	game.waves.between_delay = 0.5
	game.waves.auto_start = true
	Engine.time_scale = 3.0

func on_frame(f: int) -> void:
	if game == null or game.enemies == null:
		return
	if not reported and game.enemies.live_count > 0:
		reported = true
		var e = game.enemies
		print("[REAL] first enemies live at frame %d: count=%d groups=%d" % [f, e.live_count, e.groups.size()])
		for g in e.groups:
			var mmi: MultiMeshInstance3D = g["mmi"]
			var mm: MultiMesh = g["mm"]
			var mesh_ok := mm.mesh != null and (mm.mesh as Mesh).get_surface_count() > 0
			print("[REAL]   group %-22s instances=%-4d mesh_surfaces=%s visible=%s mat=%s riders=%d"
				% [String(g["key"]), mm.instance_count,
					str((mm.mesh as Mesh).get_surface_count() if mm.mesh != null else -1),
					str(mmi.visible), str(mmi.material_override != null),
					(g.get("riders", []) as Array).size()])
			if not mesh_ok:
				print("[REAL]   !! group %s HAS NO MESH" % String(g["key"]))

func on_finish() -> void:
	if game != null and game.enemies != null:
		var e = game.enemies
		print("[REAL] final: live=%d spawned=%d killed=%d wave=%d"
			% [e.live_count, e.total_spawned, e.total_killed, game.waves.wave_index + 1])
		print("[REAL] camera pos=%s target=%s dist=%.1f fov=%.1f"
			% [str(game.camera.global_position), str(game._cam_target), game._cam_distance, game.camera.fov])
		# Where do enemies land on screen? If they are off-screen or sub-pixel, that is the bug.
		var vp := get_viewport().get_visible_rect().size
		var n := 0
		for slot in e.active:
			if e.alive[slot] == 0 or n >= 6:
				continue
			var wp: Vector3 = e.unit_position(slot)
			var sp: Vector2 = game.camera.unproject_position(wp)
			var head: Vector2 = game.camera.unproject_position(wp + Vector3(0, 1.8 * GameState.unit_display_scale, 0))
			print("[REAL]   enemy %-14s world=%s screen=%s px_tall=%.1f onscreen=%s"
				% [e.type_id_of(slot), str(wp.round()), str(sp.round()), absf(sp.y - head.y),
					str(sp.x >= 0 and sp.x <= vp.x and sp.y >= 0 and sp.y <= vp.y)])
			n += 1
