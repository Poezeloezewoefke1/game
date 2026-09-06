extends Node3D
## Performance stress test: ramps a live map up through 50 / 100 / 250 / 500 / 1000 concurrent
## enemies with a full tower loadout firing, and reports FPS, frame time, memory and node counts.
##   godot --headless --path . -s tests/run_headless.gd -- res://tests/stress_test.gd 2400
##   (or under xvfb with tests/run_visual.gd to measure with real rendering)

const STEPS := [50, 100, 250, 500, 1000]
const FRAMES_PER_STEP := 260
const WARMUP_FRAMES := 60

var game
var step := -1
var frames_in_step := 0
var samples: Array[float] = []
var results: Array = []
var started := false
var _spawn_pool := ["chungie_t1", "chungie_t2", "chungie_t3", "chungie_t4", "chungie_t5",
	"chungie_t6", "elytra_glider", "archer", "speedster", "totem_carrier", "assassin", "shield_bearer"]

func _ready() -> void:
	game = load("res://scripts/core/game_controller.gd").new()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.add_emeralds(2000000)
	GameState.max_lives = 1000000
	GameState.lives = 1000000
	# fill every build zone and max the towers so the renderer and combat both work hard
	var ids := DataDB.towers.keys()
	var placed := 0
	for i in game.towers.zones.size():
		if not game.towers.can_place_at(i):
			continue
		var t = game.towers.place(String(ids[placed % ids.size()]), i)
		if t != null:
			placed += 1
			for path in 3:
				for k in 4:
					if t.can_upgrade(path) and GameState.can_afford(t.upgrade_cost(path)):
						t.apply_upgrade(path)
	game.waves.auto_start = false
	print("[STRESS] towers placed: %d" % placed)
	print("[STRESS] enemy pool capacity: %d" % game.enemies.capacity)
	started = true
	_next_step()

func _next_step() -> void:
	step += 1
	frames_in_step = 0
	samples.clear()
	if step >= STEPS.size():
		return
	var target: int = STEPS[step]
	game.enemies.clear_all()
	# Spread the wave along the whole path so towers everywhere are engaged.
	var spawned := 0
	for i in target:
		var id: String = _spawn_pool[i % _spawn_pool.size()]
		var d: float = game.path.total_length * (float(i) / float(target)) * 0.92
		if game.enemies.spawn(id, d) >= 0:
			spawned += 1
	# Enemies must not die during the measurement, so make them effectively immortal.
	for slot: int in game.enemies.active:
		if game.enemies.is_alive(slot):
			game.enemies.hp[slot] = 1.0e9
			game.enemies.max_hp[slot] = 1.0e9
	print("[STRESS] --- step %d: requested %d, spawned %d" % [step + 1, target, spawned])

func on_frame(_f: int) -> void:
	if not started or step >= STEPS.size():
		return
	frames_in_step += 1
	# keep the population topped up as units walk off the end of the path
	if frames_in_step % 20 == 0:
		var target: int = STEPS[step]
		while game.enemies.live_count < target:
			var id: String = _spawn_pool[game.enemies.live_count % _spawn_pool.size()]
			var slot: int = game.enemies.spawn(id, randf() * game.path.total_length * 0.9)
			if slot < 0:
				break
			game.enemies.hp[slot] = 1.0e9
			game.enemies.max_hp[slot] = 1.0e9
	if frames_in_step > WARMUP_FRAMES:
		samples.append(get_process_delta_time())
	if frames_in_step >= FRAMES_PER_STEP:
		_record()
		_next_step()

func _record() -> void:
	if samples.is_empty():
		return
	samples.sort()
	var total := 0.0
	for s in samples:
		total += s
	var mean := total / float(samples.size())
	var p95: float = samples[mini(samples.size() - 1, int(samples.size() * 0.95))]
	var worst: float = samples[samples.size() - 1]
	var row := {
		"enemies": STEPS[step],
		"live": game.enemies.live_count,
		"fps_mean": 1.0 / maxf(mean, 0.00001),
		"ms_mean": mean * 1000.0,
		"ms_p95": p95 * 1000.0,
		"ms_worst": worst * 1000.0,
		"nodes": get_tree().get_node_count(),
		"multimesh_groups": game.enemies.groups.size(),
		"static_mem_mb": float(OS.get_static_memory_usage()) / 1048576.0,
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"video_mem_mb": float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / 1048576.0,
	}
	results.append(row)
	print("[STRESS] %4d enemies | %6.1f fps | mean %5.2f ms | p95 %5.2f ms | worst %5.2f ms | nodes %4d | groups %2d | mem %.1f MB" % [
		int(row["enemies"]), float(row["fps_mean"]), float(row["ms_mean"]), float(row["ms_p95"]),
		float(row["ms_worst"]), int(row["nodes"]), int(row["multimesh_groups"]), float(row["static_mem_mb"])])

func on_finish() -> void:
	print("\n[STRESS] ================= RESULTS =================")
	print("[STRESS] enemies | fps  | mean ms | p95 ms | nodes | groups | draw calls")
	for r in results:
		print("[STRESS] %7d | %4.0f | %7.2f | %6.2f | %5d | %6d | %d" % [
			int(r["enemies"]), float(r["fps_mean"]), float(r["ms_mean"]), float(r["ms_p95"]),
			int(r["nodes"]), int(r["multimesh_groups"]), int(r["draw_calls"])])
	# Node count must stay flat as the enemy count grows — that is the whole point of the pool.
	if results.size() >= 2:
		var first: Dictionary = results[0]
		var last: Dictionary = results[results.size() - 1]
		var node_growth: int = int(last["nodes"]) - int(first["nodes"])
		print("[STRESS] node growth from %d to %d enemies: %d nodes" % [int(first["enemies"]), int(last["enemies"]), node_growth])
		if node_growth > 40:
			print("[STRESS][WARN] node count grew with enemy count — pooling may be broken")
		else:
			print("[STRESS] PASS: node count is independent of enemy count")
	var json := JSON.stringify({"results": results}, "  ")
	var f := FileAccess.open("user://stress_results.json", FileAccess.WRITE)
	if f != null:
		f.store_string(json)
		f.close()
		print("[STRESS] results written to ", ProjectSettings.globalize_path("user://stress_results.json"))
