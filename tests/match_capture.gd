extends Node3D
## Screenshots a real match at normal speed and then proves, rather than assumes, whether the enemies
## are on screen: it captures the same frame twice, once with the enemy node hidden, and diffs them.
## If the diff is empty the enemies are drawing nothing, whatever the logs say about their positions.
##
##   godot --path . --rendering-driver opengl3 -s tests/run_visual.gd -- res://tests/match_capture.gd build/match.png 900
##
## Writes build/match_with.png, build/match_without.png and build/match_marked.png (crosshairs on
## every live enemy's projected position).

var game
var state := "warmup"
var shot_with: Image
var shot_without: Image
var settle := 0
var captured_at := -1

func _ready() -> void:
	game = load("res://scripts/core/game_controller.gd").new()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.add_emeralds(50000)
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
	# Normal speed on purpose: this is meant to be what a player sees, not a fast-forward.

func on_frame(f: int) -> void:
	if game == null or game.enemies == null:
		return
	var e = game.enemies
	match state:
		"warmup":
			# Wait until a decent number of enemies are well along the path, like a real mid-match.
			if e.live_count >= 4:
				settle += 1
				if settle > 30:
					state = "shoot_with"
		"shoot_with":
			shot_with = get_viewport().get_texture().get_image()
			captured_at = f
			_report(e)
			e.visible = false
			state = "wait_hidden"
		"wait_hidden":
			state = "shoot_without"
		"shoot_without":
			shot_without = get_viewport().get_texture().get_image()
			e.visible = true
			state = "done"
			_finish()

func _report(e) -> void:
	print("[MATCH] captured at frame %d: live=%d spawned=%d killed=%d wave=%d lives=%d"
		% [captured_at, e.live_count, e.total_spawned, e.total_killed,
			game.waves.wave_index + 1, GameState.lives])
	print("[MATCH] camera pos=%s fov=%.1f  unit_display_scale=%.2f"
		% [str(game.camera.global_position), game.camera.fov, GameState.unit_display_scale])
	for g in e.groups:
		var mm: MultiMesh = g["mm"]
		var mmi: MultiMeshInstance3D = g["mmi"]
		print("[MATCH]   group %-26s instances=%-3d visible=%s aabb=%s"
			% [String(g["key"]), mm.instance_count, str(mmi.visible),
				str(mmi.get_aabb()) if mm.instance_count > 0 else "-"])

func _finish() -> void:
	shot_with.save_png("build/match_with.png")
	shot_without.save_png("build/match_without.png")
	# Diff: where on screen do the enemies actually put pixels?
	var w := shot_with.get_width()
	var h := shot_with.get_height()
	var diff := 0
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var a := shot_with.get_pixel(x, y)
			var b := shot_without.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.02:
				diff += 1
				x0 = mini(x0, x); y0 = mini(y0, y)
				x1 = maxi(x1, x); y1 = maxi(y1, y)
	print("[MATCH] enemy pixels on screen: %d sampled (of %d sampled points)"
		% [diff, (w / 2) * (h / 2)])
	if diff == 0:
		print("[MATCH] !!! THE ENEMIES DRAW NOTHING. They exist and are 'visible' but put no pixels on screen.")
	else:
		print("[MATCH] enemy pixels span x=%d..%d y=%d..%d" % [x0, x1, y0, y1])

	# Mark every live enemy's projected position so it is obvious where they should be.
	var marked := shot_with.duplicate()
	var e = game.enemies
	var n := 0
	for slot in e.active:
		if e.alive[slot] == 0:
			continue
		var wp: Vector3 = e.unit_position(slot)
		var sp: Vector2 = game.camera.unproject_position(wp)
		var head: Vector2 = game.camera.unproject_position(wp + Vector3(0, 1.8 * GameState.unit_display_scale, 0))
		if n < 8:
			print("[MATCH]   enemy %-16s world=%s screen=%s px_tall=%.1f"
				% [e.type_id_of(slot), str(wp.round()), str(sp.round()), absf(sp.y - head.y)])
		_crosshair(marked, sp)
		n += 1
	marked.save_png("build/match_marked.png")
	print("[MATCH] wrote build/match_with.png, match_without.png, match_marked.png (%d markers)" % n)

func _crosshair(img: Image, p: Vector2) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for d in range(-14, 15):
		for pt in [Vector2i(int(p.x) + d, int(p.y)), Vector2i(int(p.x), int(p.y) + d)]:
			if pt.x >= 0 and pt.x < w and pt.y >= 0 and pt.y < h:
				img.set_pixel(pt.x, pt.y, Color.MAGENTA)

func on_finish() -> void:
	if state != "done":
		print("[MATCH] never reached a capture (state=%s, live=%s)"
			% [state, str(game.enemies.live_count) if game != null and game.enemies != null else "?"])
