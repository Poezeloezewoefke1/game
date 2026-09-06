extends SceneTree
## Headless scene runner: loads a scene script, ticks it for N frames, calls on_finish(), quits.
##   godot --headless --path . -s tests/run_headless.gd -- <scene_script> [frames]

var frames := 0
var target_frames := 600
var scene: Node

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var script_path := "res://tests/headless_run.gd"
	if args.size() > 0:
		script_path = args[0]
	if args.size() > 1:
		target_frames = int(args[1])
	var scr = load(script_path)
	if scr == null:
		push_error("cannot load " + script_path)
		quit(2)
		return
	scene = scr.new()
	get_root().add_child(scene)

func _process(_delta: float) -> bool:
	frames += 1
	if scene != null and scene.has_method("on_frame"):
		scene.call("on_frame", frames)
	if frames >= target_frames:
		if scene != null and scene.has_method("on_finish"):
			scene.call("on_finish")
		return true
	return false
