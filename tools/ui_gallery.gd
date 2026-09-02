extends Node
## Photographs every screen the player actually looks at.
##
##   usage: tools/render_ui.sh <godot> [out-dir]
##
## The in-game screenshot rig binds its own roots and never mounts the interface,
## so the menus, the lobby and the HUD had never been seen at all - which is half
## of what a player spends the mission looking at. This mounts each screen with
## representative state and saves a PNG.
##
## State is pushed in directly rather than reached by playing the game: a HUD
## showing full health, no crystals and no objective is the one state that tells
## you nothing about whether the HUD works.

const SHOT_SIZE := Vector2i(1280, 720)

var _out_dir: String = "captures/ui"
var _layer: CanvasLayer
var _saved: int = 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--out="):
			_out_dir = String(arg).split("=", true, 1)[1]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _run() -> void:
	get_window().size = SHOT_SIZE
	_layer = CanvasLayer.new()
	add_child(_layer)

	# A dark ground, so a screen with transparent regions is still legible and
	# any accidental transparency is obvious rather than invisible on black.
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.06, 0.09)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	_layer.add_child(backdrop)

	await _shoot("01-main-menu", "res://scenes/ui/main_menu.tscn")
	await _shoot("02-lobby", "res://scenes/ui/lobby.tscn")
	await _shoot("03-hud", "res://scenes/ui/hud.tscn")
	await _shoot("04-pause", "res://scenes/ui/pause_menu.tscn")
	await _shoot("05-victory", "res://scenes/ui/victory_screen.tscn")
	await _shoot("06-failure", "res://scenes/ui/failure_screen.tscn")

	print("UI %d images -> %s" % [_saved, _out_dir])
	get_tree().quit()


func _shoot(name: String, path: String) -> void:
	var scene: PackedScene = load(path)
	if scene == null:
		push_error("could not load %s" % path)
		return
	var instance := scene.instantiate()
	_layer.add_child(instance)
	await get_tree().process_frame
	await get_tree().process_frame

	# Give each screen something worth looking at.
	if name == "03-hud":
		_populate_hud(instance)

	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var file := "%s/%s.png" % [_out_dir, name]
	if get_viewport().get_texture().get_image().save_png(file) == OK:
		_saved += 1
		print("  ui %s" % file)
	else:
		push_error("could not save %s" % file)

	_layer.remove_child(instance)
	instance.queue_free()


## Mid-mission: hurt, carrying a crystal, an objective on screen, a teammate
## down. Every element the HUD can show, at once.
func _populate_hud(hud: Node) -> void:
	if hud.has_method("preview_state"):
		hud.call("preview_state")
