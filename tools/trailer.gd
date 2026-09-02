extends Node3D
## Records a trailer for the game: real camera moves through the real levels,
## with title cards, encoded to MP4 by tools/record_trailer.sh.
##
## HOW TIME IS HANDLED, because it is the whole trick. This machine renders a
## frame in roughly a second on a software rasteriser. If the game were left to
## run at wall-clock speed, one rendered frame would advance shader `TIME`,
## crystal spin and the Sentinel's rotation by a whole second, and the finished
## video would be a strobe. So `Engine.time_scale` is pinned low and the camera
## is driven from an explicit frame counter rather than from delta: shot timing
## is exact and reproducible regardless of how slow the renderer is, and the
## animated parts advance by about one video frame's worth per rendered frame.

const FPS := 24
const SHOT_SIZE := Vector2i(1280, 720)
## Chosen so shader animation advances ~1/24 s per rendered frame at roughly a
## second per frame. Wrong by a factor of two either way still reads fine; wrong
## by twenty is a strobe.
const TIME_SCALE := 0.045

## scene, start [pos, yaw, pitch, fov], end [pos, yaw, pitch, fov], seconds,
## card text (empty for none), fire the blaster, hide the weapon.
const SHOTS: Array = [
	# --- Opening: the station -------------------------------------------
	["hub", [Vector3(-2, 0, 13), 0.0, 4.0, 70.0], [Vector3(-2, 0, 6), 0.0, 2.0, 66.0],
		4.0, "STARBOUND STATION", false, true],
	["hub", [Vector3(-9, 0, 2), 75.0, 2.0, 62.0], [Vector3(-9, 0, -4), 95.0, 0.0, 62.0],
		3.0, "THE LOST SIGNAL", false, true],
	["hub", [Vector3(6, 0, -2), 250.0, 0.0, 60.0], [Vector3(2, 0, -7), 200.0, -3.0, 60.0],
		3.0, "", false],
	["hub", [Vector3(0, 0, -3), 0.0, -1.0, 58.0], [Vector3(0, 0, -8), 0.0, 0.0, 54.0],
		3.0, "ONE TO FOUR EXPLORERS", false],

	# --- Arrival --------------------------------------------------------
	# The pod stands at (0, 0, 46). Both pod shots used to start about two metres
	# from its door, so the "ship" was an unreadable white slab filling the frame -
	# the reference capture that reads properly sits six metres out. These two are
	# framed from eight to eighteen metres and swing off the centre-line, which
	# also puts the pad dressing (floodlights, crates, the antenna mast) between
	# the lens and the pod instead of nothing at all.
	["nerava", [Vector3(6.0, 0, 33), 155.0, 3.0, 68.0], [Vector3(2.0, 0, 38), 166.0, -1.0, 60.0],
		3.5, "", false, true],
	["nerava", [Vector3(0, 0, 34), 0.0, 6.0, 70.0], [Vector3(0, 0, 24), 0.0, 0.0, 66.0],
		4.0, "A SIGNAL FROM A DEAD WORLD", false, true],
	["nerava", [Vector3(-6, 0, 18), 20.0, 8.0, 64.0], [Vector3(-2, 0, 12), 0.0, 0.0, 62.0],
		3.5, "", false],

	# --- The objective --------------------------------------------------
	["nerava", [Vector3(-30, 0, 2), 250.0, 0.0, 62.0], [Vector3(-36, 0, 0), 268.0, -4.0, 58.0],
		3.5, "FIND THREE POWER CRYSTALS", false],
	["nerava", [Vector3(0, 0, -30), 0.0, 0.0, 62.0], [Vector3(0, 0, -38), 0.0, -3.0, 56.0],
		3.5, "", false],
	["nerava", [Vector3(0, 0, 9), 0.0, 2.0, 66.0], [Vector3(0, 0, 3), 0.0, 4.0, 58.0],
		4.0, "POWER THE ALTAR", false],

	# --- The guardian ---------------------------------------------------
	["nerava", [Vector3(0, 0, -3), 0.0, 12.0, 62.0], [Vector3(0, 0, -6.5), 0.0, 9.0, 52.0],
		3.5, "SOMETHING IS GUARDING IT", false],
	["nerava", [Vector3(0, 0, -5), 0.0, 10.0, 56.0], [Vector3(0, 0, -6.5), 5.0, 9.0, 54.0],
		3.0, "", true],

	# --- Extraction -----------------------------------------------------
	["nerava", [Vector3(0, 0, 30), 180.0, 0.0, 66.0], [Vector3(0, 0, 40), 180.0, 0.0, 62.0],
		3.5, "GET OFF THE PLANET", false],
	# Crane out through the canyon gateway: tight on the pod, then back to the
	# whole landing pad for the title. Held inside x = +/-8, which is the clear
	# lane between the canyon walls at x = +/-12.
	["nerava", [Vector3(2.0, 0, 37.5), 167.0, 0.0, 54.0], [Vector3(2.0, 0, 28.0), 174.0, 3.0, 74.0],
		5.0, "STARBOUND STATION\nTHE LOST SIGNAL", false, true],
]

var _out_dir: String = "captures/trailer"
var _scene_root: Node
var _ui_layer: CanvasLayer
var _card: Label
var _card_group: Control
var _card_scrim: TextureRect
var _letterbox_top: ColorRect
var _letterbox_bottom: ColorRect
var _frame: int = 0
var _duration_scale: float = 1.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--out="):
			_out_dir = String(arg).split("=", true, 1)[1]
		elif String(arg).begins_with("--scale="):
			# Shortens every shot, for a fast end-to-end rehearsal before
			# committing twenty minutes of software rasterising to a full take.
			_duration_scale = maxf(String(arg).split("=", true, 1)[1].to_float(), 0.02)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _run() -> void:
	get_window().size = SHOT_SIZE
	Engine.time_scale = TIME_SCALE

	_scene_root = Node.new()
	_scene_root.name = "TrailerSceneRoot"
	add_child(_scene_root)
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 10
	add_child(_ui_layer)
	SceneManager.bind_roots(_scene_root, _ui_layer)
	_build_overlay()

	var hosted := false
	for offset in 20:
		if bool(NetworkManager.host_game(7960 + offset, "Director", "Trailer")["ok"]):
			hosted = true
			break
	if not hosted:
		push_error("could not host a trailer session")
		get_tree().quit(1)
		return

	await GameManager.host_start_session()
	if not await _wait_for(GameConfig.SCENE_HUB, 40.0):
		push_error("hub never mounted")
		get_tree().quit(1)
		return
	await _record_scene("hub")

	await GameManager.host_start_expedition()
	if not await _wait_for(GameConfig.SCENE_NERAVA, 60.0):
		push_error("nerava never mounted")
		get_tree().quit(1)
		return

	# Open the altar and take the Star Map, so the Sentinel is awake and the
	# altar is lit for the shots that are about them.
	GameManager.snapshot["temple_discovered"] = true
	GameManager.snapshot["state"] = MissionRules.MissionState.RETRIEVE_STAR_MAP
	GameManager.snapshot["altar_active"] = true
	GameManager.snapshot["star_map_state"] = MissionRules.MAP_AVAILABLE
	GameManager.host_apply_star_map_pickup(GameConfig.HOST_PEER_ID)
	await _frames(20)

	await _record_scene("nerava")

	print("TRAILER %d frames -> %s" % [_frame, _out_dir])
	NetworkManager.shutdown()
	LanDiscovery.local_teardown()
	get_tree().quit(0)


# --------------------------------------------------------------------------

func _build_overlay() -> void:
	# Letterbox bars. They cost nothing and they are most of what separates
	# "a recording of a game" from "a trailer".
	_letterbox_top = ColorRect.new()
	_letterbox_top.color = Color(0, 0, 0)
	_letterbox_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_letterbox_top.offset_bottom = float(SHOT_SIZE.y) * 0.085
	_ui_layer.add_child(_letterbox_top)

	_letterbox_bottom = ColorRect.new()
	_letterbox_bottom.color = Color(0, 0, 0)
	_letterbox_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_letterbox_bottom.offset_top = float(-SHOT_SIZE.y) * 0.085
	_ui_layer.add_child(_letterbox_bottom)

	# Cards live in a wrapper so the scrim behind the text fades with it. Fading
	# them separately would show a dark band hanging over the shot after the words
	# had gone.
	_card_group = Control.new()
	_card_group.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_group.modulate.a = 0.0
	_ui_layer.add_child(_card_group)

	# A soft dark band under the caption. White text with only an outline behind
	# it disappeared over pale geometry - "POWER THE ALTAR" was unreadable against
	# the altar's own stonework, which is the one shot where the word matters.
	# A gradient scrim fixes it for every shot at once and cannot be defeated by
	# whatever happens to be on screen.
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([
		Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.62), Color(0, 0, 0, 0.0)])
	var scrim_texture := GradientTexture2D.new()
	scrim_texture.gradient = gradient
	scrim_texture.width = 4
	scrim_texture.height = 160
	scrim_texture.fill_from = Vector2(0.0, 0.0)
	scrim_texture.fill_to = Vector2(0.0, 1.0)

	_card_scrim = TextureRect.new()
	_card_scrim.texture = scrim_texture
	_card_scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card_scrim.stretch_mode = TextureRect.STRETCH_SCALE
	_card_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_scrim.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_card_scrim.anchor_left = 0.0
	_card_scrim.anchor_right = 1.0
	_card_scrim.offset_top = -246.0
	_card_scrim.offset_bottom = -90.0
	_card_group.add_child(_card_scrim)

	_card = Label.new()
	_card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_card.anchor_left = 0.0
	_card.anchor_right = 1.0
	_card.offset_top = -215.0
	_card.offset_bottom = -120.0
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card.add_theme_font_size_override("font_size", 44)
	_card.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	# Fully opaque. At alpha 0.9 the outline came out as a grey halo that read as
	# a blur rather than as a contrasting edge.
	_card.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
	_card.add_theme_constant_override("outline_size", 9)
	_card_group.add_child(_card)


func _record_scene(scene_key: String) -> void:
	var player: Node = SpawnManager.player_node(GameConfig.HOST_PEER_ID)
	if player == null:
		push_error("no player to record from in '%s'" % scene_key)
		return
	for shot in SHOTS:
		if String(shot[0]) != scene_key:
			continue
		await _record_shot(player, shot)


func _record_shot(player: Node, shot: Array) -> void:
	var from: Array = shot[1]
	var to: Array = shot[2]
	var seconds: float = float(shot[3])
	var card: String = String(shot[4])
	var firing: bool = bool(shot[5])
	var hide_weapon: bool = shot.size() > 6 and bool(shot[6])
	var count: int = maxi(int(seconds * _duration_scale * float(FPS)), 1)

	var body := player as Node3D
	var pivot := body.get_node_or_null("CameraPivot") as Node3D
	var camera := body.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	var flash := body.get_node_or_null("CameraPivot/Muzzle/MuzzleFlash")
	var view_model := body.get_node_or_null("CameraPivot/ViewModel")
	if view_model != null:
		(view_model as Node3D).visible = not hide_weapon

	_card.text = card
	for i in count:
		# Ease in and out, so a shot starts and ends at rest. A linear dolly is
		# the single clearest sign that a camera move was scripted.
		var t: float = float(i) / float(maxi(count - 1, 1))
		var eased: float = t * t * (3.0 - 2.0 * t)

		body.global_position = (from[0] as Vector3).lerp(to[0] as Vector3, eased)
		body.rotation.y = deg_to_rad(lerpf(float(from[1]), float(to[1]), eased))
		player.set("sync_position", body.global_position)
		player.set("velocity", Vector3.ZERO)
		if pivot != null:
			pivot.rotation.x = deg_to_rad(lerpf(float(from[2]), float(to[2]), eased))
		if camera != null:
			camera.fov = lerpf(float(from[3]), float(to[3]), eased)

		# Cards fade in over the first fifth and out over the last fifth.
		var alpha: float = 1.0
		if t < 0.2:
			alpha = t / 0.2
		elif t > 0.8:
			alpha = (1.0 - t) / 0.2
		_card_group.modulate.a = alpha if card != "" else 0.0

		# Two shots at even intervals, so the muzzle flash lands on frames that
		# are actually rendered rather than between them.
		if firing and (i == int(count * 0.35) or i == int(count * 0.6)):
			if view_model != null and view_model.has_method("kick"):
				view_model.call("kick")
			if flash != null and flash.has_method("flash"):
				flash.call("flash")

		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/f%05d.png" % [_out_dir, _frame]
		if get_viewport().get_texture().get_image().save_png(path) != OK:
			push_error("could not write %s" % path)
		_frame += 1


func _wait_for(key: String, timeout: float) -> bool:
	var waited := 0.0
	while waited < timeout:
		if SceneManager.current_scene_key == key:
			await _frames(8)
			return true
		await get_tree().process_frame
		waited += 0.05
	return false


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
