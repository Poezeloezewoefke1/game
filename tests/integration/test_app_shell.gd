extends TestCase
## The application shell: main.tscn, main.gd and UIRoot.
##
## WHY THIS EXISTS: everything else mounts scenes through a test harness that
## binds its own roots, so the real shell was never exercised. A shipped bug
## went straight through that gap - the lobby set the mouse to VISIBLE, nothing
## captured it again when the hub mounted, and because the player treats an
## uncaptured mouse as "a menu is open", it silently refused to move, look,
## shoot or interact. Every headless test passed, because the check that broke
## short-circuits under a headless display server.
##
## So this suite instantiates the REAL main.tscn and drives it the way a player
## would, asserting on what the UI believes rather than on Input.mouse_mode,
## which a headless run cannot observe.

const MS := MissionRules.MissionState
const PAUSE_SCENE := "res://scenes/ui/pause_menu.tscn"

var _main: Node = null
var _ui_root: Control = null
var _prev_scene_root: Node = null
var _prev_ui_layer: CanvasLayer = null


func is_async() -> bool:
	return true


func run_async() -> void:
	_test_the_rule_itself()

	_prev_scene_root = SceneManager.scene_root
	_prev_ui_layer = SceneManager.ui_layer
	LanDiscovery.local_teardown()

	var packed: PackedScene = load("res://main.tscn") as PackedScene
	if not check(packed != null, "main.tscn loads"):
		return
	# Entering the tree runs main.gd._ready(), which binds the real roots and
	# boots to the menu. From here on the shell is driving itself.
	_main = packed.instantiate()
	tree.root.add_child(_main)
	await wait_frames(2)

	_ui_root = _main.get_node_or_null("UILayer/UIRoot") as Control
	if not check(_ui_root != null, "the shell exposes UILayer/UIRoot"):
		_teardown()
		return

	if not await _wait_for_scene(GameConfig.SCENE_MAIN_MENU, 10.0):
		check(false, "the shell boots to the main menu")
		_teardown()
		return
	check(true, "the shell boots to the main menu")

	await _test_menu_releases_the_mouse()
	await _test_hub_captures_the_mouse()
	await _test_first_person()
	await _test_pause_releases_and_resume_recaptures()
	await _test_returning_to_the_lobby_releases()

	_teardown()
	await tree.process_frame


func _teardown() -> void:
	NetworkManager.shutdown(NetworkManager.REASON_LOCAL_LEFT)
	LanDiscovery.local_teardown()
	if is_instance_valid(_main):
		_main.queue_free()
	SceneManager.bind_roots(_prev_scene_root, _prev_ui_layer)


# --------------------------------------------------------------------------

func _test_the_rule_itself() -> void:
	set_current("capture rule")
	var f := Callable(load("res://scripts/ui/ui_root.gd"), "should_capture_mouse")
	check(bool(f.call(true, false)), "in a level with no overlay -> captured")
	check_false(bool(f.call(true, true)), "in a level with an overlay -> released")
	check_false(bool(f.call(false, false)), "in a menu -> released")
	check_false(bool(f.call(false, true)), "in a menu with an overlay -> released")


func _test_menu_releases_the_mouse() -> void:
	set_current("main menu")
	check_false(_ui_root.wants_mouse_captured(), "the main menu does not capture the mouse")
	check(_ui_root.hud() == null, "there is no HUD in the menu")


func _test_hub_captures_the_mouse() -> void:
	set_current("hub")
	var started := false
	for offset in 20:
		var result := NetworkManager.host_game(7960 + offset, "ShellTester", "Shell Session")
		if bool(result["ok"]):
			started = true
			break
	if not check(started, "the shell can host a session"):
		return

	# main.gd moves to the lobby on hosting_started, with no help from the test.
	if not check(await _wait_for_scene(GameConfig.SCENE_LOBBY, 10.0), "hosting moves to the lobby"):
		return
	await wait_frames(2)
	check_false(_ui_root.wants_mouse_captured(), "the lobby does not capture the mouse")

	await GameManager.host_start_session()
	if not check(await _wait_for_scene(GameConfig.SCENE_HUB, 25.0), "the mission starts and the hub mounts"):
		return
	await wait_frames(3)

	# THE REGRESSION. Before the fix this was false, and the player could not
	# move, look, shoot or interact until Escape was pressed twice.
	check(_ui_root.wants_mouse_captured(),
		"entering the hub captures the mouse, so the player can actually move")
	check(_ui_root.hud() != null, "the HUD is mounted in a gameplay scene")

	# And the player's own gate must agree, since that is what actually decides.
	var player: Node = SpawnManager.player_node(GameConfig.HOST_PEER_ID)
	if check(player != null, "the host's player spawned"):
		check(bool(player.get("is_alive")) and not bool(player.get("is_downed")),
			"the player is in a state that permits acting")


## First person is a structural property, not a setting: if a spring arm comes
## back, or the camera stops being a direct child of the pivot, the player ends
## up looking at the back of their own head again.
func _test_first_person() -> void:
	set_current("first person")
	var player: Node = SpawnManager.player_node(GameConfig.HOST_PEER_ID)
	if not check(player != null, "the host's player exists"):
		return

	var pivot := player.get_node_or_null("CameraPivot") as Node3D
	if not check(pivot != null, "the player has a CameraPivot"):
		return
	check_near(pivot.position.y, GameConfig.EYE_HEIGHT, 0.2,
		"the camera pivot sits at eye height")

	var camera := pivot.get_node_or_null("Camera3D") as Camera3D
	check(camera != null, "the camera is a direct child of the pivot, not on a boom")
	if camera != null:
		check(camera.current, "the local player's camera is the active one")

	check(_find_node_of_type(player, "SpringArm3D") == null,
		"no spring arm survives anywhere on the player - that is what put the "
		+ "camera behind the body and filled the screen with a capsule")

	check(pivot.get_node_or_null("ViewModel") != null,
		"the owning player has a viewmodel weapon")

	# The flash hangs off the Muzzle, not the ViewModel, so that remote players
	# - who never get a viewmodel - still light up when they shoot.
	var flash := pivot.get_node_or_null("Muzzle/MuzzleFlash") as Node3D
	if check(flash != null, "there is a muzzle flash at the muzzle"):
		check(flash.has_method("flash"), "the muzzle flash can be fired")
		check_false(flash.is_processing(),
			"an idle muzzle flash does not process, so it is free until it fires")
		var lit := _find_node_of_type(flash, "OmniLight3D") as OmniLight3D
		if check(lit != null, "the flash carries its own light"):
			check_near(lit.light_energy, 0.0, 0.001, "the idle flash emits nothing")
			flash.call("flash")
			check(lit.light_energy > 1.0, "firing lights the flash")
			check(flash.is_processing(), "a lit flash processes so it can fade")
			# And it must put itself away again rather than leaving a lamp on.
			await wait_seconds(0.25)
			check_near(lit.light_energy, 0.0, 0.001, "the flash goes out on its own")
			check_false(flash.is_processing(), "a spent flash stops processing")

	var body := player.get_node_or_null("Body") as Node3D
	if check(body != null, "the player has a body"):
		check_false(body.visible,
			"the local player's own body is hidden, since the camera is inside it")
		check(body.get_child_count() > 4,
			"the body is assembled from parts, not a single capsule (%d parts)"
			% body.get_child_count())


func _find_node_of_type(root: Node, type_name: String) -> Node:
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.is_class(type_name):
			return node
		for child in node.get_children():
			stack.append(child)
	return null


func _test_pause_releases_and_resume_recaptures() -> void:
	set_current("pause")
	_ui_root.open_overlay(PAUSE_SCENE)
	await wait_frames(3)
	check(_ui_root.has_overlay(), "the pause overlay opened")
	check_false(_ui_root.wants_mouse_captured(), "pausing releases the mouse")

	_ui_root.close_overlay()
	await wait_frames(3)
	check_false(_ui_root.has_overlay(), "the pause overlay closed")
	check(_ui_root.wants_mouse_captured(), "resuming recaptures the mouse")


func _test_returning_to_the_lobby_releases() -> void:
	set_current("return to lobby")
	await GameManager.host_return_to_lobby()
	if not check(await _wait_for_scene(GameConfig.SCENE_LOBBY, 25.0), "the crew returns to the lobby"):
		return
	await wait_frames(3)
	check_false(_ui_root.wants_mouse_captured(), "the lobby releases the mouse again")
	check(_ui_root.hud() == null, "the HUD is removed when leaving a gameplay scene")
	check_false(_ui_root.has_overlay(), "no overlay survives the transition")


# --------------------------------------------------------------------------

func _wait_for_scene(key: String, timeout: float) -> bool:
	var waited := 0.0
	while waited < timeout:
		if SceneManager.current_scene_key == key:
			return true
		await tree.process_frame
		waited += tree.root.get_process_delta_time()
	return false
