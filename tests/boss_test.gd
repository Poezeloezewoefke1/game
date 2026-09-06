extends Node3D
## Boss encounter test: jumps straight to the Saparata wave and verifies every phase fires,
## the blimp flies, the mini-boss appears, and the boss can actually be defeated.
##   godot --headless --path . -s tests/run_headless.gd -- res://tests/boss_test.gd 3000

var game
var phases_seen: Array[int] = []
var blimp_launched := false
var mini_boss_seen := false
var boss_spawned := false
var boss_defeated := false
var paratroopers := 0
var errors: Array[String] = []
var _cheat_timer := 0.0

func _ready() -> void:
	Engine.time_scale = 8.0
	game = load("res://scripts/core/game_controller.gd").new()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.add_emeralds(500000)
	GameState.max_lives = 100000
	GameState.lives = 100000
	# Fill the map with maxed towers so the encounter can actually be won.
	var ids := DataDB.towers.keys()
	var n := 0
	for i in game.towers.zones.size():
		if not game.towers.can_place_at(i):
			continue
		var t = game.towers.place(String(ids[n % ids.size()]), i)
		if t != null:
			n += 1
			for path in 3:
				for k in 4:
					if t.can_upgrade(path) and GameState.can_afford(t.upgrade_cost(path)):
						t.apply_upgrade(path)
	print("[BOSS] towers: %d" % n)
	EventBus.boss_phase_changed.connect(func(i: int, name: String, _d: String) -> void:
		if not phases_seen.has(i):
			phases_seen.append(i)
		print("[BOSS] phase %d entered: %s" % [i + 1, name]))
	EventBus.boss_spawned.connect(func(_s: int) -> void:
		boss_spawned = true
		print("[BOSS] Saparata on the field"))
	EventBus.boss_defeated.connect(func(_s: int) -> void:
		boss_defeated = true
		print("[BOSS] Saparata defeated"))
	EventBus.enemy_spawned.connect(func(_s: int, type_id: String) -> void:
		if type_id == "shoebilly" and not mini_boss_seen:
			mini_boss_seen = true
			print("[BOSS] ShoeBilly_ spawned")
		elif type_id == "paratrooper":
			paratroopers += 1
		elif type_id == "blimp" and not blimp_launched:
			blimp_launched = true
			print("[BOSS] Redstone Blimp launched"))
	# Skip straight to the boss wave.
	game.waves.auto_start = true
	game.waves.between_delay = 0.2
	game.waves.skip_to_wave(game.waves.total_waves() - 1)
	print("[BOSS] jumping to wave %d of %d" % [game.waves.total_waves(), game.waves.total_waves()])

func on_frame(f: int) -> void:
	# Help the towers along so the fight resolves inside the frame budget: this is a mechanics
	# test, not a balance test.
	_cheat_timer += get_process_delta_time()
	if _cheat_timer > 0.25:
		_cheat_timer = 0.0
		var e = game.enemies
		for slot: int in e.active:
			if not e.is_alive(slot):
				continue
			# Leave structures and the blimp alone — the blimp must survive long enough to drop
			# its paratroopers, which is the behaviour this test is checking.
			if (e.flags[slot] & (EnemyManager.F_STRUCTURE | EnemyManager.F_OFF_PATH)) != 0:
				continue
			e.damage(slot, 900.0, "true", 1.0, "test_harness")
	if f % 200 == 0:
		print("[BOSS] frame %d | phase %s | live %d | boss_hp %s" % [
			f, str(game.boss.phase + 1), game.enemies.live_count,
			("%.0f" % game.enemies.hp[game.boss.boss_slot]) if game.boss.boss_slot >= 0 and game.enemies.is_alive(game.boss.boss_slot) else "-"])

func on_finish() -> void:
	print("\n[BOSS] ============ RESULTS ============")
	print("[BOSS] phases entered: %s of 5" % str(phases_seen.size()))
	print("[BOSS] mini-boss seen: %s" % mini_boss_seen)
	print("[BOSS] blimp launched: %s" % blimp_launched)
	print("[BOSS] paratroopers dropped: %d" % paratroopers)
	print("[BOSS] boss spawned: %s" % boss_spawned)
	print("[BOSS] boss defeated: %s" % boss_defeated)
	print("[BOSS] run stats: %s" % JSON.stringify(GameState.run_stats))
	if phases_seen.size() < 5:
		errors.append("only %d of 5 phases were entered" % phases_seen.size())
	if not mini_boss_seen:
		errors.append("ShoeBilly never spawned")
	if not blimp_launched:
		errors.append("the Redstone Blimp never launched")
	if not boss_spawned:
		errors.append("Saparata never entered the field")
	if not boss_defeated:
		errors.append("Saparata was never defeated")
	if not bool(GameState.run_stats.get("boss_defeated", false)):
		errors.append("boss_defeated stat not recorded")
	for e in errors:
		print("[BOSS][FAIL] ", e)
	print("[BOSS] ERRORS: %d" % errors.size())
