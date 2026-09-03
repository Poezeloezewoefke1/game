extends Node
## An automated PLAYTEST, as opposed to an automated test.
##
## Everything else in tests/ drives the game through its public API -
## GameManager.request_interact(), SpawnManager.host_spawn_*() - which proves
## the rules are right but says nothing about whether the game can be PLAYED.
## This boots the shipped shell (main.tscn, main menu, lobby, UIRoot, HUD) and
## then moves the player with Input.action_press() and InputEventMouseMotion:
## the same code path a keyboard and mouse drive. If walking to the temple is
## impossible with WASD, this notices and the rest of the suite does not.
##
## Steering is CLOSED LOOP, deliberately. Rather than computing a mouse delta
## from the sensitivity and hoping, it nudges the mouse and re-reads the yaw,
## the way a person does. That means a change to sensitivity, to the pitch
## clamp or to the look code cannot silently invalidate the driver.
##
## Three rules that the aiming code paid for the hard way, and that anything
## touching it should keep:
##
##   1. Aim is only correct when the interact ray is on the object we WANT.
##      "Some prompt appeared" put the driver in the wrong chair on a bridge
##      with four in a row, and reported success.
##   2. Every search returns to where it started. A scan of offsets that do not
##      sum to zero is a random walk, and it walked the camera into the -75
##      degree clamp with the target dead ahead.
##   3. Never trust a value read back in the same frame as the input that
##      changed it. `Input.parse_input_event` is handled in `_unhandled_input`
##      on the IDLE frame, so a pitch read after only a physics frame is the
##      OLD pitch - and an open-loop correction applied twice runs to the
##      opposite clamp. Loop until it lands.
##
##   tools/run_playtest.sh <godot> [--strategy=cautious|aggressive|explorer]
##
## Everything it does is recorded as a structured event line, so the run is
## reviewable afterwards rather than only pass/fail.

const MS := MissionRules.MissionState

## How close counts as "arrived", and how long a leg may take before the driver
## declares itself stuck. A stuck leg is the single most valuable thing this
## harness can find: it means geometry blocks a route a player must walk.
const ARRIVE_RADIUS: float = 2.6
const LEG_TIMEOUT: float = 45.0
## If the player moves less than this over STUCK_WINDOW while holding forward,
## something solid is in the way.
const STUCK_DISTANCE: float = 0.35
const STUCK_WINDOW: float = 2.5

var _strategy: String = "cautious"
var _out_path: String = ""
var _events: Array = []
var _t0: int = 0
var _main: Node = null
var _failures: Array[String] = []
var _distance_walked: float = 0.0
var _downs: int = 0
var _shots: int = 0
var _trace: Array = []
## The prompt seen at the moment of the last interaction. Read after the fact,
## the prompt is already gone - the press moves the aim on.
var _last_prompt: String = ""
## What the last aim attempt did, for the failure report. A camera that is
## pointing the wrong way is the single most common reason a prompt does not
## appear, and "no prompt" on its own never says so.
var _last_aim: String = ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("--strategy="):
			_strategy = a.split("=", true, 1)[1]
		elif a.begins_with("--out="):
			_out_path = a.split("=", true, 1)[1]
	_t0 = Time.get_ticks_msec()
	_run.call_deferred()


func _now() -> float:
	return float(Time.get_ticks_msec() - _t0) / 1000.0


func _event(kind: String, detail: String = "") -> void:
	var line := "[%7.2fs] %-22s %s" % [_now(), kind, detail]
	_events.append(line)
	print(line)


func _fail(message: String) -> void:
	_failures.append("%s (at %.1fs)" % [message, _now()])
	_event("FAIL", message)


# ==========================================================================

func _run() -> void:
	_event("playtest.start", "strategy=%s godot=%s" % [_strategy, Engine.get_version_info()["string"]])

	LanDiscovery.local_teardown()
	var packed: PackedScene = load("res://main.tscn") as PackedScene
	if packed == null:
		_fail("main.tscn does not load")
		return _finish()
	_main = packed.instantiate()
	get_tree().root.add_child(_main)
	await _frames(3)
	_event("shell.booted", "scene=%s" % SceneManager.current_scene_key)

	# Each phase must reach its own end marker. A phase that returns false
	# without recording a failure means the coroutine died on an engine error -
	# the driver has to notice that rather than call it a clean run.
	# Compare the failure COUNT across each phase, not just "is the list empty".
	# Checking emptiness masked a silent abort in the surface phase the moment
	# any earlier phase had already recorded something.
	var before := _failures.size()
	if not await _reach_the_deck():
		_require_failure("reach the deck", before)
		return _finish()
	before = _failures.size()
	if not await _play_the_ship():
		_require_failure("play the ship", before)
		return _finish()
	before = _failures.size()
	if not await _play_the_surface():
		_require_failure("play the surface", before)
		return _finish()

	_finish()


## A phase can only end early for a reason. If it did not give one, the driver
## itself broke, and saying so is far better than a green 0.1 s run.
func _require_failure(phase: String, failures_before: int) -> void:
	if _failures.size() == failures_before:
		_fail("the playtest driver aborted during '%s' without recording a reason "
			% phase + "- check the log above for an engine error")


## Main menu -> lobby -> the Starfarer, through the screens a player uses.
func _reach_the_deck() -> bool:
	if not await _until(func() -> bool:
		return SceneManager.current_scene_key == GameConfig.SCENE_MAIN_MENU, 12.0):
		_fail("the shell never reached the main menu")
		return false
	_event("menu.reached")

	# Type a name, the way a player does. Setting .text and emitting
	# text_changed is exactly what a LineEdit does on keystrokes.
	var menu := _mounted_scene()
	for edit in (menu.find_children("*", "LineEdit", true, false) if menu != null else []):
		if String(edit.name).to_lower().begins_with("name"):
			edit.text = "Tester"
			edit.emit_signal("text_changed", "Tester")
			_event("menu.named", "'Tester'")
			break

	# The Host button. Pressing a Button emits "pressed"; that IS the click, and
	# it runs the same handler a mouse would.
	var host_button := _find_button(menu, ["Host", "HostButton"])
	if host_button == null:
		_fail("no Host button found on the main menu")
		return false
	host_button.emit_signal("pressed")
	if not await _until(func() -> bool:
		return SceneManager.current_scene_key == GameConfig.SCENE_LOBBY, 15.0):
		_fail("hosting did not reach the lobby")
		return false
	_event("lobby.reached")

	var start_button := _find_button(_mounted_scene(), ["Start", "StartButton", "Launch"])
	if start_button == null:
		_fail("no Start button found in the lobby")
		return false
	start_button.emit_signal("pressed")
	if not await _until(func() -> bool:
		return SceneManager.current_scene_key == GameConfig.SCENE_SHIP, 40.0):
		_fail("starting the session did not mount the ship")
		return false
	await _frames(8)
	_event("ship.mounted", "objective='%s'" % GameManager.objective_text())
	return true


## Whatever SceneManager currently has mounted. There is no `current_scene`
## property - the mounted node lives under `scene_root`, and the first attempt
## at this reached for one that does not exist, which killed the whole driver
## coroutine silently and reported a PASS in 0.1 s.
func _mounted_scene() -> Node:
	if not is_instance_valid(SceneManager.scene_root):
		return null
	for child in SceneManager.scene_root.get_children():
		return child
	return null


func _find_button(root: Node, names: Array) -> Button:
	if root == null:
		return null
	for node in root.find_children("*", "Button", true, false):
		for wanted in names:
			if String(node.name).to_lower().begins_with(String(wanted).to_lower()):
				return node as Button
	return null


# ==========================================================================
# Aboard the ship: the pre-flight checklist, walked and pressed
# ==========================================================================

func _play_the_ship() -> bool:
	# Routes come from ShipRoutes so the playtest and the walkability gate can
	# never disagree about what "the way to the fuel station" means.
	var stations := ShipRoutes.ALL

	# An explorer wanders the crew deck first; the others go straight to work.
	# This is the only thing the strategy changes aboard the ship, and it is
	# there to prove the quarters and mess are walkable at all.
	if _strategy == "explorer":
		for spot in [Vector3(-6.0, 0, -11.0), Vector3(6.0, 0, -7.0),
				Vector3(0.0, 0, 1.0), Vector3(-6.0, 0, 10.0)]:
			if not await _walk_to(spot, "deck tour"):
				_fail("the crew deck is not walkable at %s" % str(spot))

	for object_id in stations:
		# The lever and the seat are walked separately, after the checklist.
		if String(object_id) in ["ship_launch_lever", "ship_seat_1"]:
			continue
		var blocked := false
		for leg in stations[object_id]:
			if not await _walk_to(leg, "station %s" % object_id):
				_fail("could not walk to %s (leg %s)" % [object_id, str(leg)])
				blocked = true
				break
		if blocked:
			continue
		var task_id := String(object_id).replace("ship_", "")
		if String(object_id) == "ship_nav_console":
			task_id = GameConfig.SHIP_TASK_COURSE
		await _approach_and_use(String(object_id), "",
			func() -> bool: return _station_done(task_id))
	var remaining: Array = MissionRules.ship_tasks_remaining(GameManager.snapshot)
	_event("ship.checklist", "remaining=%s" % str(remaining))
	if not remaining.is_empty():
		_fail("the pre-flight checklist could not be completed by walking and pressing E: %s"
			% str(remaining))
		return false

	# The lever must refuse while nobody is seated. This is a DESIGN claim the
	# player is told about, so the playtest checks the player is told correctly.
	for leg in ShipRoutes.TO_LEVER:
		if not await _walk_to(leg, "back to the lever"):
			_fail("could not walk back to the launch lever (leg %s)" % str(leg))
			return false
	await _approach_and_use("ship_launch_lever", "the launch lever")
	var prompt := _last_prompt
	_event("lever.prompt", "'%s'" % prompt)
	if not prompt.contains("not seated"):
		_fail("the lever does not explain that the crew is unseated; prompt='%s'" % prompt)
	if GameManager.mission_state() != MS.SHIP_IDLE:
		_fail("the lever launched with nobody strapped in")
		return false
	_event("lever.refused", "correctly, while unseated")

	for leg in ShipRoutes.TO_SEAT:
		if not await _walk_to(leg, "to a flight seat"):
			_fail("could not walk to a flight seat (leg %s)" % str(leg))
			return false
	await _approach_and_use("ship_seat_1", "flight seat 1",
		func() -> bool:
			var p := _player()
			return p != null and String(p.get("seated_at")) != "")
	await _frames(4)
	var player := _player()
	if player == null or String(player.get("seated_at")) == "":
		_fail("pressing E on a seat did not seat the player")
		return false
	_event("seat.taken", String(player.get("seated_at")))

	# Seated, the player must not be able to walk away.
	var before: Vector3 = (player as Node3D).global_position
	await _hold("move_forward", 1.2)
	var drift: float = before.distance_to((player as Node3D).global_position)
	_event("seat.drift", "%.2f m while holding forward" % drift)
	if drift > 1.0:
		_fail("a seated player walked %.2f m out of the chair" % drift)

	# Strapped in, the pilot pulls the lever. This used to call
	# GameManager.host_begin_launch() directly, with a comment explaining that
	# the lever was out of reach from the seat - which is not a note about the
	# harness, it is the report that the ship could not be launched by playing
	# the game. A driver that reaches past the control it is testing proves
	# nothing, so it now does what a player does: look at the console and press
	# E, from the chair.
	if not await _approach_and_use("ship_launch_lever", "the launch lever, from the seat",
			func() -> bool: return GameManager.mission_state() == MS.LAUNCHING,
			false):
		_fail("a seated pilot could not launch the ship")
		return false
	if not await _until(func() -> bool:
		return GameManager.mission_state() == MS.LAUNCHING, 6.0):
		_fail("the launch never started")
		return false
	_event("launch.started", MissionCatalog.display_name(
		String(GameManager.snapshot.get("mission_id", ""))))

	if not await _until(func() -> bool:
		return GameConfig.SURFACE_SCENES.has(SceneManager.current_scene_key), 60.0):
		_fail("the flight never reached a planet surface")
		return false
	await _frames(8)
	_event("surface.landed", "scene=%s objective='%s'"
		% [SceneManager.current_scene_key, GameManager.objective_text()])
	# The transition respawns the player, so it can be null for a few frames.
	if not await _until(func() -> bool:
		var p := _player()
		return p != null and is_instance_valid(p), 15.0):
		_fail("no player node exists after landing")
		return false
	if String(_player().get("seated_at")) != "":
		_fail("the player is still strapped into a seat that no longer exists")
	return true


# ==========================================================================
# On the surface: the whole mission, walked
# ==========================================================================

func _play_the_surface() -> bool:
	var key := SceneManager.current_scene_key
	var mission_id := String(GameManager.snapshot.get("mission_id", ""))

	# The player node is respawned by the transition, so it can be null for a
	# few frames after the scene mounts. Walking before it exists aborted the
	# whole phase on a null dereference.
	if not await _until(func() -> bool:
		var p := _player()
		return p != null and is_instance_valid(p), 15.0):
		_fail("no player node exists on %s after landing" % key)
		return false
	await _frames(6)
	_event("surface.ready", "player at %s"
		% str((_player() as Node3D).global_position.snapped(Vector3.ONE * 0.1)))

	if not await _walk_to(Vector3(0, 0, 13), "temple clearing"):
		_fail("could not walk from the landing pad to the temple")
		return false
	if not await _until(func() -> bool:
		return GameManager.mission_state() == MS.FIND_CRYSTALS, 8.0):
		_fail("walking into the clearing did not discover the temple")
		return false
	_event("temple.found", "objective='%s'" % GameManager.objective_text())

	# The coupling errand, if this mission seals a crystal behind one.
	if MissionRules.crystal_lock(GameManager.snapshot, GameConfig.CRYSTAL_CAVE) \
			== MissionRules.LOCK_COUPLING:
		if not await _do_coupling_errand(mission_id):
			return false

	# Three crystals, each fetched and placed. The routes are the authored
	# corridors; a straight line walks into rock.
	var routes := {
		GameConfig.CRYSTAL_RUINS: [Vector3(0, 0, 4), Vector3(-12, 0, 0), Vector3(-41, 0, 0)],
		GameConfig.CRYSTAL_CAVE: [Vector3(0, 0, 4), Vector3(14, 0, 0), Vector3(41, 0, 0)],
		GameConfig.CRYSTAL_GROVE: [Vector3(0, 0, 4), Vector3(0, 0, -18), Vector3(0, 0, -41)],
	}
	var pedestals := {
		GameConfig.CRYSTAL_RUINS: Vector3(-4, 0, 3),
		GameConfig.CRYSTAL_CAVE: Vector3(4, 0, 3),
		GameConfig.CRYSTAL_GROVE: Vector3(0, 0, -7),
	}
	for crystal_id in routes:
		var t_start := _now()
		for leg in routes[crystal_id]:
			if not await _walk_to(leg, "to %s" % crystal_id):
				_fail("route to %s is blocked at %s" % [crystal_id, str(leg)])
		var want: String = String(crystal_id)
		if not await _approach_and_use("%s_%s" % [mission_id, crystal_id],
				"the %s" % crystal_id,
				func() -> bool: return _carrying() == want):
			return false
		_event("crystal.taken", "%s in %.1fs" % [crystal_id, _now() - t_start])

		for leg in [Vector3(0, 0, 4), pedestals[crystal_id]]:
			if not await _walk_to(leg, "carry %s home" % crystal_id):
				_fail("carrying %s home is blocked at %s" % [crystal_id, str(leg)])
		if not await _approach_and_use(
				"%s_pedestal_%s" % [mission_id, _pedestal_letter(crystal_id)],
				"the %s pedestal" % crystal_id,
				func() -> bool: return _carrying() == ""):
			return false
	_event("pedestals.placed", "%d of %d"
		% [GameManager.placed_pedestal_count(), GameConfig.REQUIRED_PEDESTAL_COUNT])
	if GameManager.placed_pedestal_count() < GameConfig.REQUIRED_PEDESTAL_COUNT:
		_fail("the altar puzzle could not be completed by walking and pressing E")
		return false

	# The Star Map.
	if not await _walk_to(Vector3(0, 0, 1), "altar"):
		_fail("could not reach the altar")
		return false
	if not await _approach_and_use("%s_star_map_altar" % mission_id, "the altar",
			func() -> bool:
				return GameManager.star_map_state() == MissionRules.MAP_CARRIED):
		return false
	_event("starmap.taken", "state=%s" % MissionRules.state_name(GameManager.mission_state()))

	if not await _fight_the_warden():
		return false

	# Home.
	for leg in [Vector3(0, 0, 14), Vector3(0, 0, 32), Vector3(0, 0, 42)]:
		if not await _walk_to(leg, "run for the pod"):
			_fail("the run back to the pod is blocked at %s" % str(leg))
	if not await _approach_and_use("%s_drop_pod" % mission_id, "the drop pod",
			func() -> bool: return GameManager.mission_state() == MS.MISSION_COMPLETE):
		return false
	if not await _until(func() -> bool:
		return GameManager.mission_state() == MS.MISSION_COMPLETE, 10.0):
		_fail("extraction did not complete the mission")
		return false
	_event("mission.complete", "in %.1fs, %d downs, %d shots, %.0f m walked"
		% [_now(), _downs, _shots, _distance_walked])
	return true


## What this player is holding, asked of the same peer the game asks about.
## The surface act used a hard-coded peer 1, which is right only because the
## driver happens to host; naming it here means a two-peer playtest reads the
## right inventory without a second edit.
func _carrying() -> String:
	return GameManager.carried_crystal_of(NetworkManager.local_peer_id())


## The id of an interactable, or "-" for a body that is not one. `get()` on a
## missing property returns null, and `String(null)` is not a constructor -
## it raised a SCRIPT ERROR inside the failure report, which killed the very
## diagnostic that was trying to explain the failure.
## Is the ray on the thing we are trying to use? With no id given, any prompt
## counts, which is what the free-aim callers want.
func _aimed_at(wanted_id: String) -> bool:
	if _prompt_text() == "":
		return false
	return wanted_id == "" or _hovered_id() == wanted_id


## The object the interact ray is currently latched onto, or "" for nothing.
func _hovered_id() -> String:
	var p := _player()
	if p == null or not is_instance_valid(p):
		return ""
	var hovered: Variant = p.get("_hovered")
	if hovered == null or not is_instance_valid(hovered):
		return ""
	return _object_id_of(hovered as Node)


func _object_id_of(n: Node) -> String:
	var oid: Variant = n.get("object_id")
	return "-" if oid == null else str(oid)


## A node named the way a person can find it: the tail of its path, not just a
## leaf name. "NavigationRegion3D" as a blocker name is useless - a level has
## one of those and everything solid hangs off it. "Terrain/RidgeBlock" is not.
func _describe(n: Node) -> String:
	var parts: Array = []
	var at: Node = n
	for _i in 3:
		if at == null:
			break
		parts.push_front(String(at.name))
		at = at.get_parent()
	return "/".join(parts)


func _pedestal_letter(crystal_id: String) -> String:
	match crystal_id:
		GameConfig.CRYSTAL_RUINS: return "a"
		GameConfig.CRYSTAL_CAVE: return "b"
		_: return "c"


func _do_coupling_errand(mission_id: String) -> bool:
	_event("coupling.errand", "the cave crystal is sealed")
	for leg in [Vector3(0, 0, 20), Vector3(-4, 0, 24)]:
		if not await _walk_to(leg, "to the coupling"):
			_fail("the power coupling is not reachable at %s" % str(leg))
			return false
	if not await _approach_and_use("%s_power_coupling" % mission_id, "the power coupling",
			func() -> bool: return _carrying() == GameConfig.ITEM_COUPLING):
		return false
	for leg in [Vector3(0, 0, 8), Vector3(0, 0, 2), Vector3(14, 0, 0),
			Vector3(24, 0, -2), Vector3(34, 0, -3)]:
		if not await _walk_to(leg, "to the socket"):
			_fail("the coupling socket is not reachable at %s" % str(leg))
			return false
	if not await _approach_and_use("%s_coupling_socket" % mission_id, "the coupling socket",
			func() -> bool:
				return MissionRules.crystal_lock(
					GameManager.snapshot, GameConfig.CRYSTAL_CAVE) == ""):
		return false
	_event("coupling.fitted", "the cave crystal is open")

	# Walk back down the authored corridor rather than cutting the diagonal
	# home. The crystal routes all start at (0, 0, 4), and a straight line to it
	# from the socket crosses ground no corridor covers - so a failure there
	# would say "the level is broken" when the truth is "nobody designed that
	# line to be walkable".
	for leg in [Vector3(24, 0, -2), Vector3(14, 0, 0), Vector3(0, 0, 4)]:
		if not await _walk_to(leg, "back from the socket"):
			_fail("the way back from the coupling socket is blocked at %s" % str(leg))
			return false
	return true


## The boss, fought by aiming and holding the trigger. Strategy decides how the
## driver behaves under fire, which is the closest this harness gets to the
## difference between two human players.
func _fight_the_warden() -> bool:
	var warden: Node = null
	if not await _until(func() -> bool:
		warden = _find_boss()
		return warden != null, 10.0):
		_fail("taking the Star Map did not wake the Warden")
		return false
	_event("warden.awake", "phase=%d" % int(GameManager.snapshot.get("boss_phase", -1)))

	var deadline := _now() + 180.0
	var last_phase := -1
	while _now() < deadline:
		if GameManager.mission_state() == MS.MISSION_FAILED:
			_fail("the crew was wiped out by the Warden")
			return false
		var phase := int(GameManager.snapshot.get("boss_phase", 0))
		if phase != last_phase:
			last_phase = phase
			_event("warden.phase", "%d, health=%d nodes=%d at %.1fs"
				% [phase, int(GameManager.snapshot.get("boss_health", 0)),
					int(GameManager.snapshot.get("boss_nodes", 0)), _now()])
		if phase == MissionRules.BOSS_DEAD:
			break
		if not is_instance_valid(warden):
			warden = _find_boss()
			if warden == null:
				break

		# Aim at the shield node while one stands, otherwise at the body. This
		# is the fight's actual decision, so the driver has to make it.
		var aim_at: Node3D = warden as Node3D
		if phase == MissionRules.BOSS_SHIELDED:
			var node := _live_shield_node(warden)
			if node != null:
				aim_at = node
		await _look_at_point((aim_at as Node3D).global_position)

		# Cautious backs off between volleys; aggressive stands and shoots.
		if _strategy == "cautious" and _player() != null:
			var player := _player() as Node3D
			var gap: float = player.global_position.distance_to((warden as Node3D).global_position)
			if gap < 9.0:
				await _hold("move_back", 0.5)
		await _hold("fire", 0.55)
		_shots += 1
		await _frames(2)
		if bool(_player().get("is_downed")):
			_downs += 1
			_event("player.downed", "during the Warden fight")
			# Alone, a downed player cannot be revived. The mission is lost.
			break

	var final_phase := int(GameManager.snapshot.get("boss_phase", 0))
	if final_phase != MissionRules.BOSS_DEAD:
		_fail("the Warden was not killed within 180 s (phase=%d, health=%d)"
			% [final_phase, int(GameManager.snapshot.get("boss_health", 0))])
		return false
	_event("warden.killed", "at %.1fs" % _now())
	return true


func _find_boss() -> Node:
	for node in get_tree().get_nodes_in_group(GameConfig.GROUP_BOSS):
		return node
	return null


func _live_shield_node(warden: Node) -> Node3D:
	var ring: Node = warden.get_node_or_null("ShieldRing")
	if ring == null:
		return null
	var mask := int(warden.get("sync_nodes"))
	for i in 3:
		if (mask & (1 << i)) == 0:
			continue
		var node := ring.get_node_or_null("Node%d" % (i + 1)) as Node3D
		if node != null:
			return node
	return null


# ==========================================================================
# The driver: keyboard, mouse, and closed-loop steering
# ==========================================================================

func _player() -> Node:
	return SpawnManager.local_player()


func _prompt_text() -> String:
	var p := _player()
	if p != null and is_instance_valid(p) and p.has_method("hovered_prompt"):
		return String(p.call("hovered_prompt"))
	return ""


## Yaw the body towards a world point by nudging the mouse and re-reading the
## result, rather than by computing a delta from the sensitivity constant.
func _look_at_point(target: Vector3, tolerance_deg: float = 2.0) -> void:
	var player := _player() as Node3D
	if player == null:
		return
	for _i in 90:
		var to_target: Vector3 = target - player.global_position
		to_target.y = 0.0
		if to_target.length_squared() < 0.001:
			return
		var wanted := atan2(-to_target.x, -to_target.z)
		var error: float = wrapf(wanted - player.rotation.y, -PI, PI)
		if absf(error) < deg_to_rad(tolerance_deg):
			break
		# rotation.y -= relative.x * sens, so a POSITIVE error needs a NEGATIVE
		# relative.x. The step is capped so the loop cannot overshoot forever.
		var sens: float = SettingsManager.effective_mouse_sensitivity()
		var relative: float = clampf(-error / sens, -600.0, 600.0)
		var ev := InputEventMouseMotion.new()
		ev.relative = Vector2(relative, 0.0)
		Input.parse_input_event(ev)
		await get_tree().process_frame


## Point the camera at an interactable so the interact ray finds it.
##
## Pitch is closed-loop like yaw, and that matters: the first version only ever
## nudged DOWNWARDS looking for the prompt, so once it overshot it could never
## look back up, and the reactor station - which sits slightly above the deck
## the player approaches it from - became permanently unaimable. A one-way
## search is not a search.
func _look_at_object(object_id: String) -> void:
	var node := SpawnManager.find_interactable(object_id)
	if node == null:
		return
	var player := _player() as Node3D
	if player == null:
		return
	var aim: Vector3 = _aim_point(node as Node3D)
	await _look_at_point(aim)
	await _pitch_towards(aim, object_id)


## Where to point at an interactable: the centre of its collision shape when it
## has one, since that is the thing the interact ray must actually hit.
##
## The fallback of "origin plus 0.9 m" is a guess that suits a waist-high
## console and misses both a floor-level cradle and a tall pillar. Asking the
## shape works for all three, and stays right when a prop is redesigned.
func _aim_point(node: Node3D) -> Vector3:
	for child in node.find_children("*", "CollisionShape3D", true, false):
		var shape := child as CollisionShape3D
		if shape != null and shape.shape != null:
			return shape.global_position
	return node.global_position + Vector3(0.0, 0.9, 0.0)


## Drive the camera pitch to look at a world point, then micro-scan around it
## until the interact ray reports the object we WANT - which is the only
## definition of "aimed at it" that matters.
##
## `wanted` matters more than it looks. Stopping as soon as any prompt appeared
## meant that on a bridge with four chairs in a row, the scan settled on
## whichever one the ray happened to graze first and then reported success while
## looking at the wrong seat. An empty `wanted` keeps the old any-prompt
## behaviour for callers that genuinely do not care.
func _pitch_towards(target: Vector3, wanted_id: String = "") -> void:
	var player := _player() as Node3D
	if player == null:
		return
	var pivot := player.get_node_or_null("CameraPivot") as Node3D
	if pivot == null:
		return
	var sens: float = SettingsManager.effective_mouse_sensitivity()
	var started_at: float = pivot.rotation.x
	var wanted: float = 0.0
	var converged := false
	# Converge GEOMETRICALLY FIRST, even when the ray already reports the
	# target. Returning early on "the prompt is showing" left the camera
	# wherever the previous aim had put it - once at the -75 degree clamp, with
	# the ray grazing the very bottom edge of a flight seat 1.2 m away. The
	# prompt was there, so the driver called it aimed; the press then lost the
	# seat on the first frame and read the floor. Grazing an object is not
	# looking at it, and a player who walks up to a chair looks at the chair.
	for _i in 60:
		var eye: Vector3 = pivot.global_position
		var to_target: Vector3 = target - eye
		var flat: float = Vector2(to_target.x, to_target.z).length()
		wanted = atan2(to_target.y, maxf(flat, 0.01))
		var error: float = wanted - pivot.rotation.x
		if absf(error) < deg_to_rad(1.0):
			converged = true
			break
		# _pitch = _pitch - relative.y * sens, so a POSITIVE error (look up)
		# needs a NEGATIVE relative.y.
		var ev := InputEventMouseMotion.new()
		ev.relative = Vector2(0.0, clampf(-error / sens, -400.0, 400.0))
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().physics_frame

	# On target geometrically but still no prompt: scan a few degrees either
	# side, because the ray is a line and the object has a finite hitbox.
	#
	# The scan RETURNS TO CENTRE afterwards. It used to walk away: the offsets
	# summed to -12 degrees, so every failed scan left the camera a further 12
	# degrees below the target and three attempts in a row pinned the pitch at
	# the -75 degree clamp, staring at the floor with the object dead ahead.
	var centre: float = pivot.rotation.x
	for step in [4.0, -4.0, 8.0, -8.0, 12.0, -12.0]:
		if _aimed_at(wanted_id):
			return
		await _set_pitch(pivot, centre + deg_to_rad(step), sens)
		await get_tree().physics_frame
	if not _aimed_at(wanted_id):
		await _set_pitch(pivot, centre, sens)
	_last_aim = "pitch %.0f -> wanted %.0f, settled %.0f%s" % [
		rad_to_deg(started_at), rad_to_deg(wanted), rad_to_deg(pivot.rotation.x),
		"" if converged else " (never converged)"]


## Drive the camera to an absolute pitch, closed-loop.
##
## Absolute rather than relative, because a scan that never returns to where it
## started is a random walk - that is how the camera ended up pinned at the -75
## degree clamp with the target dead ahead.
##
## Closed-loop rather than one nudge, because `Input.parse_input_event` is not
## applied by the time the next physics frame ends: the player handles motion in
## `_unhandled_input`, which runs on the idle frame. Reading `rotation.x` back
## too early returns the OLD pitch, so an open-loop nudge applies its full
## correction twice and runs to the opposite clamp. Re-reading until it lands
## makes the staleness harmless instead of fatal.
func _set_pitch(pivot: Node3D, wanted: float, sens: float) -> void:
	for _i in 8:
		var error: float = wanted - pivot.rotation.x
		if absf(error) < deg_to_rad(0.5):
			return
		var ev := InputEventMouseMotion.new()
		ev.relative = Vector2(0.0, clampf(-error / sens, -400.0, 400.0))
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().physics_frame


## Walk to a point with WASD. Returns false if the player gets stuck or the leg
## times out - which is the finding this whole harness exists to produce.
func _walk_to(target: Vector3, label: String) -> bool:
	var player := _player() as Node3D
	if player == null:
		_fail("no player to walk (%s)" % label)
		return false
	var deadline := _now() + LEG_TIMEOUT
	var last_check := _now()
	# Two positions, deliberately. `window_start` is where the player was when
	# the current stuck window opened and only moves when the window rolls over;
	# `previous` is last frame's position and only feeds the odometer. Using one
	# variable for both made "moved in 2.5s" measure a single frame - 0.08 m at a
	# full run - so every leg longer than the window was reported stuck while the
	# player was walking normally at 5 m/s.
	var window_start: Vector3 = player.global_position
	var previous: Vector3 = player.global_position
	var sprinting := _strategy == "aggressive"
	Input.action_press("move_forward")
	if sprinting:
		Input.action_press("sprint")
	var arrived := false
	while _now() < deadline:
		player = _player() as Node3D
		if player == null:
			break
		var flat_target := Vector3(target.x, player.global_position.y, target.z)
		if player.global_position.distance_to(flat_target) <= ARRIVE_RADIUS:
			arrived = true
			break
		await _look_at_point(target, 6.0)
		await get_tree().physics_frame
		_distance_walked += player.global_position.distance_to(previous)
		previous = player.global_position
		if _now() - last_check >= STUCK_WINDOW:
			var moved: float = player.global_position.distance_to(window_start)
			if moved < STUCK_DISTANCE:
				Input.action_release("move_forward")
				Input.action_release("sprint")
				_event("stuck", "%s: moved %.2f m in %.1fs at %s (target %s) - against %s"
					% [label, moved, STUCK_WINDOW, str(player.global_position),
						str(target), _what_is_blocking(player)])
				return false
			last_check = _now()
			window_start = player.global_position
	Input.action_release("move_forward")
	Input.action_release("sprint")
	if not arrived:
		_event("timeout", "%s: %.1fs without arriving, at %s"
			% [label, LEG_TIMEOUT, str((_player() as Node3D).global_position)])
	return arrived


## What the player is pressed against. "Stuck" on its own says a route failed;
## this says which object to move, which is the difference between a bug report
## and a bug fix.
func _what_is_blocking(player: Node3D) -> String:
	var space := player.get_world_3d().direct_space_state
	if space == null:
		return "unknown (no physics space)"
	var eye: Vector3 = player.global_position + Vector3(0.0, 0.9, 0.0)
	var ahead: Vector3 = -player.global_transform.basis.z
	var names: Array = []
	# A capsule first: thin rays miss anything they happen to thread past, and
	# "nothing the rays could find" in front of a player who cannot move is a
	# useless report. This asks the same question the walkability gate does.
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	for step in [0.5, 0.9, 1.3]:
		var probe: Vector3 = player.global_position + ahead * step
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = capsule
		params.transform = Transform3D(Basis(), Vector3(probe.x, 0.95, probe.z))
		params.collision_mask = GameConfig.LAYER_WORLD
		for hit in space.intersect_shape(params, 4):
			var tag := "capsule:%s@%.1fm" % [_describe(hit["collider"] as Node), step]
			if not names.has(tag):
				names.append(tag)

	# Then a short fan of rays at three heights: a table blocks the knees while
	# a doorway header blocks the head, and they need different fixes.
	for height in [0.25, 0.9, 1.5]:
		for spread in [-0.35, 0.0, 0.35]:
			var from: Vector3 = player.global_position + Vector3(0.0, height, 0.0)
			var dir: Vector3 = ahead.rotated(Vector3.UP, spread)
			var q := PhysicsRayQueryParameters3D.create(from, from + dir * 1.4)
			q.collision_mask = GameConfig.LAYER_WORLD
			q.exclude = [player.get_rid()]
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			var label := "%s(y=%.2f)" % [_describe(hit["collider"] as Node), height]
			if not names.has(label):
				names.append(label)
	# Finally the player's own state. Geometry is only one reason a body does not
	# move: downed, seated, or simply not receiving input all look identical from
	# the outside, and a probe that only looks outward can never tell them apart.
	names.append(_player_state_line(player))
	return ", ".join(names)


## What the character controller itself believes. `get_slide_collision` is the
## authority on what the player is pressing against - it names the collider the
## motion actually resolved against, on whatever layer it lives, which is the one
## question outward-facing rays cannot answer.
func _player_state_line(player: Node3D) -> String:
	var body := player as CharacterBody3D
	if body == null:
		return "state: not a CharacterBody3D"
	var bits: Array = []
	bits.append("v=%.2f" % body.velocity.length())
	bits.append("floor=%s" % str(body.is_on_floor()))
	if body.is_on_wall():
		bits.append("wall n=%s" % str(body.get_wall_normal().snapped(Vector3.ONE * 0.01)))
	bits.append("hp=%d" % int(body.get("health")))
	if bool(body.get("is_downed")):
		bits.append("DOWNED")
	if not bool(body.get("is_alive")):
		bits.append("DEAD")
	var seat: String = String(body.get("seated_at"))
	if seat != "":
		bits.append("SEATED at %s" % seat)
	for i in range(body.get_slide_collision_count()):
		var col := body.get_slide_collision(i)
		var other := col.get_collider() as Node
		if other == null:
			continue
		bits.append("touching %s (layer %d, normal %s)" % [_describe(other),
			int(other.get("collision_layer")) if other.get("collision_layer") != null else -1,
			str(col.get_normal().snapped(Vector3.ONE * 0.01))])
	return "state: " + " ".join(bits)


## Walk up to an interactable, aim, and press E - reporting the prompt it saw.
##
## The interact RayCast3D is 3.2 m long (player.tscn), shorter than the host's
## 5 m validation range, so being within range is not enough: the player has to
## close to arm's length and look at the thing. Reporting the prompt is what
## makes a failure legible - "pressed E and nothing happened" and "the prompt
## said Hands full" are very different bugs.
## `done` is how the caller knows the press worked. When it is given, the press
## is retried until it reads true; when it is not, the press happens once and
## the caller checks the outcome itself. The first version inferred "done" from
## the object id and silently treated every id it did not recognise as already
## finished - so pressing E on a seat never pressed at all.
## `may_walk` is false for a seated player: stepping towards the target is how
## this closes the gap, and a player in a chair cannot step anywhere. Letting it
## try would hide the very thing being tested - whether the control is within
## reach OF THE SEAT - behind a walk that silently does nothing.
func _approach_and_use(object_id: String, what: String = "",
		done: Callable = Callable(), may_walk: bool = true) -> bool:
	var label := what if what != "" else object_id
	var node := SpawnManager.find_interactable(object_id)
	if node == null:
		_fail("%s is not registered in this level" % label)
		return false

	for _attempt in (14 if may_walk else 3):
		await _look_at_object(object_id)
		# A prompt is not enough: it has to be THIS object's prompt. Walking to
		# a flight seat, the driver stopped 3 m short with the ray on the chair
		# NEXT to it, saw a prompt, and declared itself arrived. A player headed
		# for a particular chair keeps walking until they are looking at that
		# chair, so the loop only breaks when the ray agrees with the target.
		if _prompt_text() != "" and _hovered_id() == object_id:
			break
		if not may_walk:
			continue
		# Not in range, not aimed, or aimed at the wrong thing - step towards it.
		await _look_at_point((node as Node3D).global_position)
		await _hold("move_forward", 0.28)
		await _frames(2)

	var prompt := _prompt_text()
	if prompt == "":
		var player := _player() as Node3D
		var gap: float = player.global_position.distance_to((node as Node3D).global_position) \
			if player != null else -1.0
		# Say what the ray DID find. "No prompt" is a symptom; "the ray is on the
		# hull" and "the ray is on nothing" need completely different fixes.
		var seen := "nothing"
		var pivot := player.get_node_or_null("CameraPivot") as Node3D if player != null else null
		if pivot != null:
			var space := player.get_world_3d().direct_space_state
			var eye: Vector3 = pivot.global_position
			var aim2: Vector3 = (node as Node3D).global_position + Vector3(0, 0.9, 0)
			var q := PhysicsRayQueryParameters3D.create(eye, eye + (aim2 - eye).normalized() * 3.2)
			q.collision_mask = 7
			q.exclude = [player.get_rid()]
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				var n: Node = hit["collider"]
				seen = "%s (oid='%s') at %.2f m" % [_describe(n), _object_id_of(n),
					eye.distance_to(hit["position"])]
		_fail("%s never showed a prompt (closed to %.1f m; player at %s, camera pitch %.0f deg, aim: %s, ray found %s)"
			% [label, gap, str(player.global_position.snapped(Vector3.ONE * 0.1)),
				rad_to_deg(pivot.rotation.x) if pivot != null else 0.0, _last_aim, seen])
		return false
	var hovered_id := _hovered_id()
	_last_prompt = prompt
	_event("prompt", "%s -> '%s' (ray on '%s')" % [label, prompt, hovered_id])
	if hovered_id != object_id:
		_fail("%s: the prompt showed but the interact ray is on '%s'"
			% [label, hovered_id])
	_trace.clear()
	var has_check := done.is_valid()
	# Press while STILL AIMING. A player walking up to a console keeps looking
	# at it while they press E; the driver used to stop aiming the moment the
	# prompt appeared, and the player is still sliding to a halt for a few
	# frames after that, which swung the 3.2 m ray off a small target.
	for attempt in (5 if has_check else 1):
		if has_check and bool(done.call()):
			break
		Input.action_press("interact")
		for _tick in 8:
			await get_tree().physics_frame
			if attempt == 0:
				var pp := _player() as Node3D
				var hh: Variant = pp.get("_hovered") if pp != null else null
				var ray := pp.get_node_or_null("CameraPivot/InteractRay") as RayCast3D \
					if pp != null else null
				var piv := pp.get_node_or_null("CameraPivot") as Node3D if pp != null else null
				var target := SpawnManager.find_interactable(object_id) as Node3D
				var collider := "-"
				if ray != null and ray.is_colliding():
					var c: Object = ray.get_collider()
					collider = String((c as Node).name) if c is Node else "?"
				elif ray != null:
					collider = "NOT-COLLIDING"
				_trace.append("[d=%.2f pitch=%.0f ray=%s hov=%s vel=%.1f]" % [
					pp.global_position.distance_to(target.global_position) if target != null else -1.0,
					rad_to_deg(piv.rotation.x) if piv != null else 0.0,
					collider,
					("none" if hh == null or not is_instance_valid(hh)
						else String((hh as Node).get("object_id"))),
					(pp.get("velocity") as Vector3).length() if pp != null else -1.0])
			if has_check and bool(done.call()):
				break
			# NO re-aiming inside the press. An earlier version corrected the
			# aim every frame and fought itself into a pitch oscillation
			# between both clamps - the trace showed -75 deg and +65 deg on
			# alternate frames, with the ray hitting the floor and then the
			# ceiling. Aim once, hold E, and let the interact grace window do
			# its job; if the press still misses, the attempt loop re-approaches
			# and aims again, which is what a player does anyway.
		Input.action_release("interact")
		await get_tree().physics_frame
		await _frames(3)
		if has_check and not bool(done.call()):
			# Missed. Take a fresh run at it rather than mashing from the same
			# spot - a slightly different angle is what a player would try.
			await _look_at_object(object_id)
			await _frames(2)

	if has_check and not bool(done.call()):
		var pl := _player()
		var h: Variant = pl.get("_hovered") if pl != null else null
		_event("press.trace", "%s %s" % [label, " ".join(_trace)])
		_fail("%s: five presses while aimed at it did not take (last frame: ray='%s' latch=%s pending=%d)"
			% [label,
				("none" if h == null or not is_instance_valid(h)
					else String((h as Node).get("object_id"))),
				str(pl.get("_interact_held")) if pl != null else "?",
				int(pl.get("_interact_pending_until_ms")) if pl != null else -1])
		return false
	return true


## Has this pre-flight station been worked? Used as the `done` check above.
func _station_done(task_id: String) -> bool:
	return GameManager.snapshot.get("ship_tasks", {}).has(task_id)


func _press(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


func _hold(action: String, seconds: float) -> void:
	Input.action_press(action)
	var until := _now() + seconds
	while _now() < until:
		await get_tree().physics_frame
	Input.action_release(action)


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _until(predicate: Callable, timeout: float) -> bool:
	var deadline := _now() + timeout
	while _now() < deadline:
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	return false


# ==========================================================================

func _finish() -> void:
	# Release everything, or a held key leaks into the next run.
	for action in ["move_forward", "move_back", "move_left", "move_right",
			"sprint", "fire", "interact", "jump"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)

	_event("playtest.end", "%d failure(s)" % _failures.size())
	var summary := "PLAYTEST %s strategy=%s failures=%d duration=%.1fs walked=%.0fm downs=%d shots=%d" \
		% ["FAIL" if not _failures.is_empty() else "PASS",
			_strategy, _failures.size(), _now(), _distance_walked, _downs, _shots]
	print("")
	print(summary)
	for f in _failures:
		print("  x %s" % f)

	# The summary goes in the LOG as well as on stdout. CI uploads the log and
	# nothing else, so a verdict that only ever reached the terminal is a
	# verdict nobody reading the artifact can see.
	if _out_path != "":
		var lines: Array = _events.duplicate()
		lines.append("")
		lines.append(summary)
		for f in _failures:
			lines.append("  x %s" % f)
		var file := FileAccess.open(_out_path, FileAccess.WRITE)
		if file != null:
			file.store_string("\n".join(lines) + "\n")
			file.close()

	NetworkManager.shutdown()
	LanDiscovery.local_teardown()
	get_tree().quit(1 if not _failures.is_empty() else 0)
