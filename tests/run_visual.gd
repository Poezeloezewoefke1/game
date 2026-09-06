extends SceneTree
## Thin runner for visual tests. Usage:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -s tests/run_visual.gd -- <scene_script> <out.png> [frames]
## The scene script (a Node3D/Node script) is loaded here, after autoload singletons exist, so it may
## reference autoloads normally. Scripts loaded by `-s` compile before autoloads are registered as globals.

var frames := 0
var target_frames := 45
var out_path := "build/visual.png"
var scene: Node

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var script_path := "res://tests/visual_character_test.gd"
	if args.size() > 0:
		script_path = args[0]
	if args.size() > 1:
		out_path = args[1]
	if args.size() > 2:
		target_frames = int(args[2])
	var scr = load(script_path)
	if scr == null:
		push_error("cannot load " + script_path)
		quit(2)
		return
	scene = scr.new()
	get_root().add_child(scene)

func _process(_delta: float) -> bool:
	frames += 1
	if scene and scene.has_method("on_frame"):
		scene.call("on_frame", frames)
	if frames >= target_frames:
		var img := get_root().get_viewport().get_texture().get_image()
		var abs_path := ProjectSettings.globalize_path(out_path) if out_path.begins_with("user://") or out_path.begins_with("res://") else out_path
		var err := img.save_png(abs_path)
		print("screenshot saved: ", abs_path, " err=", err, " size=", img.get_size())
		if scene and scene.has_method("on_finish"):
			scene.call("on_finish")
		return true
	return false
