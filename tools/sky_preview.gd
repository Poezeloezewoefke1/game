extends Node3D
## Renders the sky on its own, from several directions, so the shader can be
## iterated on without hosting a session and walking to a viewpoint.
##
##   usage: tools/preview_sky.sh <godot> [out-dir]

const SHOT_SIZE := Vector2i(720, 405)

## Name, the direction to look at, and the field of view. Aiming at a target
## rather than at hand-picked yaw/pitch is not a nicety: the first version had
## the camera pointed 180 degrees away from the planet it was named after, and
## the shot was read as "the rings are still broken".
const VIEWS: Array = [
	["01-galaxy", Vector3(0.36, 0.10, -0.93), 75.0],
	["02-ringed-giant", Vector3(-0.55, 0.22, -0.80), 46.0],
	["03-ocean-world", Vector3(0.80, 0.44, 0.40), 34.0],
	["04-moon", Vector3(-0.20, 0.52, 0.83), 30.0],
	["05-sun", Vector3(0.42, 0.30, -0.85), 55.0],
	["06-wide", Vector3(-0.30, 0.35, -0.60), 100.0],
]

var _out_dir: String = "captures/sky"
var _camera: Camera3D
var _saved: int = 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--out="):
			_out_dir = String(arg).split("=", true, 1)[1]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _run() -> void:
	get_window().size = SHOT_SIZE

	var sky := Sky.new()
	sky.sky_material = load("res://resources/sky_nerava.tres")
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 3.0
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	_camera = Camera3D.new()
	add_child(_camera)
	_camera.current = true

	for view in VIEWS:
		await _shoot(String(view[0]), view[1] as Vector3, float(view[2]))

	print("SKY %d images -> %s" % [_saved, _out_dir])
	get_tree().quit()


func _shoot(name: String, target: Vector3, fov: float) -> void:
	_camera.fov = fov
	_camera.look_at_from_position(Vector3.ZERO, target.normalized(), Vector3.UP)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [_out_dir, name]
	if get_viewport().get_texture().get_image().save_png(path) == OK:
		_saved += 1
		print("  sky %s" % path)
