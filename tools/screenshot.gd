extends Node
## Renders the real game to PNG files so its visuals can be reviewed.
##
## Everything else in this repository is verified headlessly, which cannot say
## anything at all about how the game LOOKS. This drives a real session through
## a software OpenGL context under Xvfb and captures what the player's own
## camera sees.
##
##   tools/capture_screenshots.sh <godot-binary> [output-dir]
##
## HONEST CAVEAT: captures use the Compatibility renderer on a software
## rasteriser, because there is no GPU or Vulkan driver here. Geometry, layout,
## materials, colour and light direction are faithful. Screen-space effects that
## are Forward+ only - SSAO, SSIL, SDFGI - do not appear. Treat a capture as
## "the shapes and colours are right", not "this is pixel-identical to your GPU".

## Deliberately modest. Captures render on a software rasteriser and glow is a
## multi-pass blur; at 720p a full run took longer than the feedback was worth.
## This is still ample for composition, lighting, silhouettes and colour.
const SHOT_SIZE := Vector2i(960, 540)

## scene key, player position, yaw degrees, pitch degrees, file name,
## and optionally `true` to fire the blaster on the frame that is captured.
##
## A Node3D with rotation.y == 0 faces -Z in Godot, so a yaw of 0 looks "north"
## up the map. Getting this wrong the first time pointed half the shots at a
## blank wall.
const SHOTS: Array = [
	["hub", Vector3(0, 0, -5), 0.0, -2.0, "01-hub-terminal"],
	["hub", Vector3(-8, 0, 0), 90.0, 2.0, "02-hub-window"],
	["hub", Vector3(6, 0, -4), 270.0, -2.0, "03-hub-consoles"],
	["hub", Vector3(-2, 0, 10), 0.0, 0.0, "04-hub-wide"],
	["hub", Vector3(0, 0, -2), 0.0, 0.0, "05-hub-firing", true],
	["nerava", Vector3(0, 0, 40), 180.0, -2.0, "06-nerava-drop-pod"],
	["nerava", Vector3(0, 0, 32), 0.0, 0.0, "07-nerava-canyon"],
	["nerava", Vector3(0, 0, 16), 0.0, 0.0, "08-nerava-temple-approach"],
	["nerava", Vector3(0, 0, 5), 0.0, 2.0, "09-nerava-altar"],
	["nerava", Vector3(-5, 0, 8), 0.0, -4.0, "10-nerava-pedestal"],
	["nerava", Vector3(-38, 0, 0), 90.0, 0.0, "11-nerava-ruins-crystal"],
	["nerava", Vector3(39, 0, 3), 285.0, -3.0, "12-nerava-cave-crystal"],
	["nerava", Vector3(0, 0, -38), 0.0, 0.0, "13-nerava-grove-crystal"],
	["nerava", Vector3(0, 0, -3), 0.0, 8.0, "14-nerava-sentinel"],
	["nerava", Vector3(0, 0, -3), 0.0, 6.0, "15-nerava-firing", true],
]

var _out_dir: String = "captures"
var _scene_root: Node
var _ui_layer: CanvasLayer
var _saved: int = 0
var _only: String = ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--out="):
			_out_dir = String(arg).split("=", true, 1)[1]
		elif String(arg).begins_with("--only="):
			# Restrict the run to one scene. Lighting work is an iteration loop,
			# and re-hosting a whole mission to re-check one room is the slow
			# part of it.
			_only = String(arg).split("=", true, 1)[1]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _run() -> void:
	get_window().size = SHOT_SIZE

	_scene_root = Node.new()
	_scene_root.name = "ShotSceneRoot"
	add_child(_scene_root)
	_ui_layer = CanvasLayer.new()
	add_child(_ui_layer)
	SceneManager.bind_roots(_scene_root, _ui_layer)

	var hosted := false
	for offset in 20:
		if bool(NetworkManager.host_game(7980 + offset, "Photographer", "Capture")["ok"]):
			hosted = true
			break
	if not hosted:
		push_error("could not host a capture session")
		get_tree().quit(1)
		return

	await GameManager.host_start_session()
	if not await _wait_for(GameConfig.SCENE_SHIP, 30.0):
		push_error("hub never mounted")
		get_tree().quit(1)
		return
	await _shoot_all("hub")

	await GameManager.host_start_expedition()
	if not await _wait_for(GameConfig.SCENE_NERAVA, 40.0):
		push_error("nerava never mounted")
		get_tree().quit(1)
		return

	# Unlock the altar and take the Star Map so the Sentinel is in frame for the
	# last shot - otherwise the most interesting model in the game is missing.
	GameManager.snapshot["temple_discovered"] = true
	GameManager.snapshot["state"] = MissionRules.MissionState.RETRIEVE_STAR_MAP
	GameManager.snapshot["altar_active"] = true
	GameManager.snapshot["star_map_state"] = MissionRules.MAP_AVAILABLE
	GameManager.host_apply_star_map_pickup(GameConfig.HOST_PEER_ID)
	await _frames(20)

	await _shoot_all("nerava")

	print("CAPTURED %d screenshots into %s" % [_saved, _out_dir])
	NetworkManager.shutdown()
	LanDiscovery.local_teardown()
	get_tree().quit(0)


func _shoot_all(scene_key: String) -> void:
	var player: Node = SpawnManager.player_node(GameConfig.HOST_PEER_ID)
	if player == null:
		push_error("no player to shoot from in '%s'" % scene_key)
		return
	for shot in SHOTS:
		if String(shot[0]) != scene_key:
			continue
		if _only != "" and _only != scene_key:
			continue
		var firing: bool = shot.size() > 5 and bool(shot[5])
		await _shoot(player, shot[1], float(shot[2]), float(shot[3]), String(shot[4]), firing)


func _shoot(player: Node, position: Vector3, yaw_deg: float, pitch_deg: float, name: String,
		firing: bool = false) -> void:
	var body := player as Node3D
	body.global_position = position
	body.rotation.y = deg_to_rad(yaw_deg)
	player.set("sync_position", position)
	player.set("velocity", Vector3.ZERO)
	var pivot := body.get_node_or_null("CameraPivot") as Node3D
	if pivot != null:
		pivot.rotation.x = deg_to_rad(pitch_deg)

	# Several frames so physics settles the body onto the floor and any
	# per-frame visual state (materials, lights) has been applied.
	await _frames(6)

	# The muzzle flash lasts about three frames, so it has to be triggered on
	# the last frame before the capture or it will have faded by then. Calling
	# the flash directly rather than pulling the trigger keeps this shot out of
	# the host's fire path - the capture rig must never look like a client
	# asking to shoot.
	# The flash lasts 55 ms. A software rasteriser spends far longer than that on
	# one frame, so triggering it and then waiting a process frame guarantees it
	# has already faded by the time anything is drawn - which is exactly how the
	# first firing shots came out with no flash in them. Trigger it after the
	# last process step, so the very next draw is the one that catches it.
	if firing:
		var view_model := body.get_node_or_null("CameraPivot/ViewModel")
		if view_model != null and view_model.has_method("kick"):
			view_model.call("kick")
		var flash := body.get_node_or_null("CameraPivot/Muzzle/MuzzleFlash")
		if flash != null and flash.has_method("flash"):
			flash.call("flash")

	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, name]
	if image.save_png(path) == OK:
		_saved += 1
		print("  shot %s" % path)
	else:
		push_error("could not save %s" % path)


func _wait_for(scene_key: String, timeout: float) -> bool:
	var waited := 0.0
	while waited < timeout:
		if SceneManager.current_scene_key == scene_key:
			await _frames(6)
			return true
		await get_tree().process_frame
		waited += get_process_delta_time()
	return false


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
