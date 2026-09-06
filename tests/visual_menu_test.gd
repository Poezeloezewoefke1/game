extends Node
## Renders the real main menu (via the actual scene router) for a screenshot.
## Pass a screen name as the third user arg through run_visual.gd's scene script slot is not
## available, so the screen is chosen by the SCREEN constant below or by an env-style override
## in OS.get_cmdline_user_args().

var main: Node

func _ready() -> void:
	main = load("res://scripts/core/main.gd").new()
	add_child(main)
	var args := OS.get_cmdline_user_args()
	var screen := "menu"
	if args.size() > 3:
		screen = String(args[3])
	await get_tree().process_frame
	match screen:
		"heroes":
			main.go_to_hero_select()
		"maps":
			main.go_to_map_select()
		"codex":
			main.go_to_codex()
		"towers":
			main.go_to_towers()
		"settings":
			main.go_to_settings()
		_:
			pass
	print("[VISUAL] showing screen: ", screen)
