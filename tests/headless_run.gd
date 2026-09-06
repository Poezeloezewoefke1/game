extends Node3D
## Headless smoke test: builds a full run, places towers, forces waves through, uses hero abilities,
## triggers the boss, and reports what happened. Loaded by tests/run_visual.gd (which also works
## without a window when Godot runs with --headless, since it only saves a screenshot at the end).

var game
var frames := 0
var log_lines: Array[String] = []
var placed: Array = []
var errors: Array[String] = []
var wave_target := 999
var fast_forward := 6.0
var _next_place := 0
var _ability_timer := 0.0

const PLACEMENT_PLAN := [
	"royal_guard", "royal_guard", "theobaldthebird", "eggchan", "spepticle",
	"mapicc", "lomedy", "minutetech", "deputy_ace", "reinadrop", "4cvit", "leow0ok",
]

func _ready() -> void:
	Engine.time_scale = fast_forward
	game = load("res://scripts/core/game_controller.gd").new()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	_log("map=%s hero=%s zones=%d waves=%d" % [
		String(game.map_def.get("id", "?")), game.hero.hero_id,
		game.towers.zones.size(), game.waves.total_waves()])
	_log("path length=%.1f points=%d" % [game.path.total_length, game.path.points.size()])
	_log("enemy defs=%d tower defs=%d" % [game.enemies.defs.size(), DataDB.towers.size()])
	GameState.add_emeralds(300000)
	_place_towers()
	_upgrade_towers()
	game.waves.auto_start = true
	game.waves.between_delay = 0.4
	EventBus.run_victory.connect(func(_s: Dictionary) -> void: _log("VICTORY"))
	EventBus.run_defeat.connect(func(_s: Dictionary) -> void: _log("DEFEAT"))
	EventBus.boss_phase_changed.connect(func(i: int, n: String, _d: String) -> void: _log("BOSS PHASE %d: %s" % [i + 1, n]))
	EventBus.boss_defeated.connect(func(_s: int) -> void: _log("BOSS DEFEATED"))
	EventBus.relationship_activated.connect(func(a: String, b: String, _r: Dictionary) -> void: _log("BOND: %s + %s" % [a, b]))

func _place_towers() -> void:
	var zone := 0
	for id in PLACEMENT_PLAN:
		while zone < game.towers.zones.size() and not game.towers.can_place_at(zone):
			zone += 1
		if zone >= game.towers.zones.size():
			break
		var t = game.towers.place(id, zone)
		if t != null:
			placed.append(t)
		else:
			errors.append("failed to place %s at zone %d" % [id, zone])
		zone += 1
	_log("placed %d towers" % placed.size())

func _upgrade_towers() -> void:
	var upgrades := 0
	for t in placed:
		for path in 3:
			for i in 4:
				if t.can_upgrade(path) and GameState.can_afford(t.upgrade_cost(path)):
					if t.apply_upgrade(path):
						upgrades += 1
	_log("applied %d upgrades" % upgrades)
	for t in placed:
		if t.tier_label() == "0-0-0":
			errors.append("%s never upgraded" % t.tower_id)
	# verify the Gear Rule held
	for t in placed:
		var over_two := 0
		var started := 0
		for v in t.tiers:
			if v > 0:
				started += 1
			if v > 2:
				over_two += 1
		if over_two > 1 or started > 2:
			errors.append("Gear Rule violated on %s: %s" % [t.tower_id, t.tier_label()])

func on_frame(f: int) -> void:
	frames = f
	_ability_timer += get_process_delta_time()
	if _ability_timer > 0.4:
		_ability_timer = 0.0
		for slot in 4:
			if game.hero.can_use(slot):
				game.hero.use_ability(slot)

func _process(_delta: float) -> void:
	pass

func _log(text: String) -> void:
	log_lines.append(text)
	print("[TEST] ", text)

func on_finish() -> void:
	var e = game.enemies
	_log("waves reached %d/%d" % [game.waves.wave_index + 1, game.waves.total_waves()])
	_log("enemies spawned=%d killed=%d live=%d groups=%d" % [e.total_spawned, e.total_killed, e.live_count, e.groups.size()])
	_log("hero level=%d kills=%d" % [game.hero.level, game.hero.kills])
	_log("emeralds=%d lives=%d/%d" % [GameState.emeralds, GameState.lives, GameState.max_lives])
	_log("stats=%s" % JSON.stringify(GameState.run_stats))
	_log("bonds=%d" % game.towers.active_relationships.size())
	if e.total_spawned == 0:
		errors.append("no enemies ever spawned")
	if e.total_killed == 0:
		errors.append("no enemies were ever killed")
	if int(GameState.run_stats.get("emeralds_earned", 0)) <= 0:
		errors.append("no emeralds earned from kills")
	for err in errors:
		print("[TEST][FAIL] ", err)
	print("[TEST] ERRORS: ", errors.size())
