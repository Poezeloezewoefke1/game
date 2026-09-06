extends Node3D
## Builds a live run with towers placed and a wave in progress, then holds it for a screenshot.

var game

func _ready() -> void:
	game = load("res://scripts/core/game_controller.gd").new()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.add_emeralds(400000)
	var plan := ["theobaldthebird", "royal_guard", "mapicc", "lomedy", "eggchan", "spepticle",
		"deputy_ace", "minutetech", "4cvit", "reinadrop", "purpled", "leow0ok"]
	var zone := 0
	var n := 0
	for id in plan:
		while zone < game.towers.zones.size() and not game.towers.can_place_at(zone):
			zone += 1
		if zone >= game.towers.zones.size():
			break
		var t = game.towers.place(id, zone)
		if t != null:
			n += 1
			for path in 3:
				for k in 3:
					if t.can_upgrade(path) and GameState.can_afford(t.upgrade_cost(path)):
						t.apply_upgrade(path)
		zone += 1
	# Populate the path with a mixed, visibly-geared column.
	var mix := ["chungie_t1", "chungie_t2", "chungie_t3", "chungie_t4", "chungie_t5", "chungie_t6",
		"chungie_t7", "elytra_glider", "archer", "shield_bearer", "horse_rider", "totem_carrier"]
	for i in 90:
		var id: String = mix[i % mix.size()]
		game.enemies.spawn(id, game.path.total_length * (float(i) / 90.0) * 0.92)
	game.enemies.spawn("shoebilly", game.path.total_length * 0.45, 0.0)
	game.enemies.spawn("saparata", game.path.total_length * 0.30, 0.0)
	# Use the game's own default framing (set in GameController._build_camera).
	print("[VISUAL] towers=%d enemies=%d groups=%d" % [n, game.enemies.live_count, game.enemies.groups.size()])

func on_frame(f: int) -> void:
	if f == 20:
		EventBus.announce.emit("WAVE 21 — CINDERCREST WARRIORS", "Netherite. Maces. Old players.", 8.0)
		EventBus.dialogue.emit("saparata", "The old players are starving. Every one of these new spawns is why.", 8.0)
		EventBus.boss_health_changed.emit(3800.0, 5200.0)
		EventBus.boss_phase_changed.emit(3, "Saparata Enters", "The King of Unstable takes the field.")
