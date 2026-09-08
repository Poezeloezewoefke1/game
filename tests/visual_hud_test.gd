extends Node3D
## Screenshots the in-game HUD with enough state on it to see every panel at once: money that makes
## some of the roster affordable and some not, a tower selected so the upgrade panel is up, a bond
## active, and a wave running so the wave bar and its preview have something to show.
##   godot --path . --rendering-driver opengl3 -s tests/run_visual.gd -- res://tests/visual_hud_test.gd build/hud.png 220
var game
func _ready() -> void:
	game = load("res://scripts/core/game_controller.gd").new()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.add_emeralds(1500)
	var zone := 0
	for id in ["royal_guard", "theobaldthebird"]:
		while zone < game.towers.zones.size() and not game.towers.can_place_at(zone):
			zone += 1
		game.towers.place(id, zone, true)
		zone += 3
	game.waves.between_delay = 0.6
	game.waves.auto_start = true

func on_frame(f: int) -> void:
	if f == 120 and game.towers.towers.size() > 0:
		game.towers.select(game.towers.towers[0])

func on_finish() -> void:
	print("[HUD] emeralds=%d towers=%d wave=%d" % [GameState.emeralds,
		game.towers.towers.size(), game.waves.wave_index + 1])
