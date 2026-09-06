extends Node
## Scene router. Everything is built from code; this node swaps the active screen.

var current: Node

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--quick-play" in args:
		go_to_game()
	else:
		go_to_main_menu()

func _swap(scene: Node) -> void:
	if is_instance_valid(current):
		current.queue_free()
	current = scene
	add_child(scene)

func go_to_main_menu() -> void:
	GameState.end_run()
	_swap(load("res://scripts/ui/main_menu.gd").new())

func go_to_hero_select() -> void:
	_swap(load("res://scripts/ui/hero_select.gd").new())

func go_to_map_select() -> void:
	_swap(load("res://scripts/ui/map_select.gd").new())

func go_to_codex() -> void:
	_swap(load("res://scripts/ui/codex_screen.gd").new())

func go_to_towers() -> void:
	_swap(load("res://scripts/ui/towers_screen.gd").new())

func go_to_settings() -> void:
	_swap(load("res://scripts/ui/settings_screen.gd").new())

func go_to_game() -> void:
	_swap(load("res://scripts/core/game_controller.gd").new())
