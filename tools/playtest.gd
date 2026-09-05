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
## How close the driver has to get to an intermediate navigation corner before
## turning for the next one. Tight, deliberately: see _nav_walk_to.
const NAV_CORNER_RADIUS: float = 0.9
## How much room the driver wants between itself and an enraged Warden before it
## turns round to shoot. Beyond the boss's own 11 m stand-off ring, so turning to
## fight does not simply hand the distance straight back.
const WARDEN_SAFE_GAP: float = 14.0
const LEG_TIMEOUT: float = 45.0
## If the player moves less than this over STUCK_WINDOW while holding forward,
## something solid is in the way.
const STUCK_DISTANCE: float = 0.35
const STUCK_WINDOW: float = 2.5

var _strategy: String = "cautious"
## Which planet to fly. Empty means "whatever is unlocked on a fresh save",
## which is Nerava - and which is why for a long time nothing had ever played
## the other two thirds of the campaign.
var _mission: String = ""
var _out_path: String = ""
var _events: Array = []
var _t0: int = 0
var _main: Node = null
var _failures: Array[String] = []
var _distance_walked: float = 0.0
var _downs: int = 0
var _shots: int = 0
## Which way the driver is side-stepping in a fight. Flipped every volley, so it
## weaves rather than running in one direction into the scenery.
var _strafe: int = 1
var _trace: Array = []
## The prompt seen at the moment of the last interaction. Read after the fact,
## the prompt is already gone - the press moves the aim on.
var _last_prompt: String = ""
## What the last aim attempt did, for the failure report. A camera that is
## pointing the wrong way is the single most common reason a prompt does not
## appear, and "no prompt" on its own never says so.
var _last_aim: String = ""
## Radians of camera rotation per pixel of synthetic mouse motion, MEASURED
## rather than taken from the sensitivity setting. See _look_gain().
var _rad_per_px: float = 0.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("--strategy="):
			_strategy = a.split("=", true, 1)[1]
		elif a.begins_with("--out="):
			_out_path = a.split("=", true, 1)[1]
		elif a.begins_with("--mission="):
			_mission = a.split("=", true, 1)[1]
	# Godot ACCUMULATES mouse motion by default: several events parsed within
	# one frame are merged into one before they reach `_unhandled_input`. For a
	# person that is a smoothing feature. For a driver that nudges the mouse and
	# re-reads the result, it means a correction can arrive late, arrive merged
	# with the next one, or appear not to have arrived at all - which is how the
	# camera kept ending up pinned at a pitch clamp with the target dead ahead.
	# Turning it off makes each parsed event dispatch on its own, so what the
	# driver sends is what the player gets.
	Input.set_use_accumulated_input(false)
	_t0 = Time.get_ticks_msec()
	_run.call_deferred()


func _now() -> float:
	return float(Time.get_ticks_msec() - _t0) / 1000.0


func _event(kind: String, detail: String = "") -> void:
	var line := "[%7.2fs] %-22s %s" % [_now(), kind, detail]
	_events.append(line)
	print(line)


func _fail(message: String) -> void:
	# A downed player is the dominant fact about any failure, so say it here
	# rather than at each of the ten call sites - which is how "could not reach
	# crystal_ruins" came to be the headline for a run where the player had been
	# shot and was lying on the floor. The evidence was in the stuck line all
	# along, four fields deep; the failure everyone reads said something else.
	var text := message
	var pl := _player()
	if pl != null and is_instance_valid(pl) and bool(pl.get("is_downed")):
		text += " - the player was DOWNED at the time"
	_failures.append("%s (at %.1fs)" % [text, _now()])
	_event("FAIL", text)


# ==========================================================================

func _run() -> void:
	_event("playtest.start", "strategy=%s mission=%s godot=%s"
		% [_strategy, (_mission if _mission != "" else "first unlocked"),
			Engine.get_version_info()["string"]])

	# The driver's own constants, checked before it measures anything. A tuning
	# change put the guard walk's target within the arrive tolerance of the gap
	# that triggers the walk, and the result was a run that fired zero shots in
	# ninety seconds and reported the guard unkillable - a bug in the instrument
	# wearing the costume of a bug in the game, which is the failure this whole
	# document is about. The same shape as defect 72's stand-off and contact
	# radius crossing, and it gets the same treatment: state the ordering, and
	# refuse to run rather than produce a confident wrong answer.
	if GUARD_BACKOFF_RANGE >= GUARD_FIGHT_RANGE \
			or GUARD_FIGHT_RANGE > GUARD_ENGAGE_RANGE - GUARD_RANGE_MARGIN:
		_fail("the guard fight ranges are inconsistent: back off %.1f < fight %.1f < engage %.1f - %.1f"
			% [GUARD_BACKOFF_RANGE, GUARD_FIGHT_RANGE,
				GUARD_ENGAGE_RANGE, GUARD_RANGE_MARGIN])
		return

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

## Cycle the chart table round to the planet this run is meant to fly.
##
## The console offers only what the crew has UNLOCKED, and on a fresh save that
## is Nerava alone - which is the honest reason two thirds of the catalog had
## never been played by anything. Asking for a later planet therefore has to
## grant the campaign progress that would have earned it, and the log says so
## in as many words: this is a driver standing in for a save file, not the game
## handing out destinations.
func _plot_the_course() -> bool:
	if _mission == "" or _mission == String(GameManager.snapshot.get("mission_id", "")):
		return true
	if not MissionCatalog.has_mission(_mission):
		_fail("--mission=%s is not in the catalog" % _mission)
		return false

	# Everything ordered before the wanted planet counts as flown already.
	var earned: Array = []
	for id in MissionCatalog.ids():
		if String(id) == _mission:
			break
		earned.append(String(id))
	if not earned.is_empty():
		GameManager.snapshot["completed_missions"] = earned
		_event("campaign.unlocked",
			"standing in for a save that has flown %s" % str(earned))

	# Then plot it the way a player does: press E until the chart reads right.
	for _i in MissionCatalog.ids().size() + 1:
		if String(GameManager.snapshot.get("mission_id", "")) == _mission:
			_event("course.plotted", MissionCatalog.display_name(_mission))
			return true
		if not await _approach_and_use("ship_nav_console", "the chart table",
				func() -> bool:
					return String(GameManager.snapshot.get("mission_id", "")) == _mission,
				false):
			break
	if String(GameManager.snapshot.get("mission_id", "")) == _mission:
		_event("course.plotted", MissionCatalog.display_name(_mission))
		return true
	_fail("the chart table would not plot a course for %s (it reads %s)"
		% [_mission, GameManager.snapshot.get("mission_id", "")])
	return false


func _play_the_ship() -> bool:
	# Routes come from ShipRoutes so the playtest and the walkability gate can
	# never disagree about what "the way to the fuel station" means.
	var stations := ShipRoutes.ALL

	# An explorer wanders the crew deck first; the others go straight to work.
	# This is the only thing the strategy changes aboard the ship, and it is
	# there to prove the quarters and mess are walkable at all.
	if _strategy == "explorer":
		var here := Vector3(0.0, 0.0, -8.0)   # the crew quarters, where players spawn
		for spot in [Vector3(-6.0, 0, -11.0), Vector3(6.0, 0, -7.0),
				Vector3(0.0, 0, 1.0), Vector3(-6.0, 0, 10.0)]:
			# Cross the bulkheads through their doorways, the way a player does.
			for leg in ShipRoutes.route_between(here, spot):
				if not await _walk_to(leg, "deck tour"):
					_fail("the crew deck is not walkable at %s (heading for %s)"
						% [str(leg), str(spot)])
					break
			here = spot
		# Back to the crew quarters before starting work. The station routes in
		# ShipRoutes all begin from the spawn area, so a wanderer who goes
		# straight from the med bay to the bridge walks into the bulkhead
		# between them - the tour has to put the player back where the routes
		# expect to find them, which is also what a player does.
		for leg in ShipRoutes.route_between(here, Vector3(0.0, 0.0, -8.0)):
			if not await _walk_to(leg, "back from the tour"):
				_fail("the way back from the deck tour is blocked at %s" % str(leg))
				break

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
		if String(object_id) == "ship_nav_console" and not await _plot_the_course():
			return false
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
	#
	# Let the body settle into the chair FIRST. Sitting lerps the player onto
	# the seat anchor, so measuring from where they were standing counts the
	# snap into the seat as drift - it read 1.14 m on a run where the player had
	# not moved at all, which is a false failure against the game.
	await _frames(30)
	var seat_node: Node3D = _player().call("seat_node") as Node3D \
		if _player().has_method("seat_node") else null
	var anchor: Vector3 = (seat_node.call("sit_position") as Vector3) \
		if seat_node != null and seat_node.has_method("sit_position") \
		else (player as Node3D).global_position
	var before: Vector3 = (player as Node3D).global_position
	await _hold("move_forward", 1.2)
	var here: Vector3 = (player as Node3D).global_position
	var drift: float = before.distance_to(here)
	var off_anchor: float = anchor.distance_to(here)
	_event("seat.drift", "%.2f m while holding forward, %.2f m from the seat anchor"
		% [drift, off_anchor])
	if drift > 0.5 or off_anchor > 0.5:
		_fail("a seated player moved %.2f m while holding forward and ended %.2f m from the chair"
			% [drift, off_anchor])

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

	if not await _walk_to_temple():
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

	# The hazard errand, if this mission runs a hazard field over a crystal.
	# Nerava has none; Cinder burns and Hallow freezes, and on both of them one
	# crystal sits inside the field. Walking in without sealing the vent is a
	# slow death, so the valve comes first - which is what the lock is for.
	if _hazard_locks_a_crystal():
		if not await _seal_the_vent(mission_id):
			return false

	# Three crystals, each fetched and placed. Every route is asked of the
	# level's own navigation mesh rather than read off a table: the tables were
	# hand-measured on Nerava, which is why nothing had ever walked Cinder.
	var last_hp_before_place := GameConfig.MAX_HEALTH
	for crystal_id in [GameConfig.CRYSTAL_RUINS, GameConfig.CRYSTAL_CAVE,
			GameConfig.CRYSTAL_GROVE]:
		var t_start := _now()
		var want: String = String(crystal_id)
		var crystal_object: String = "%s_%s" % [mission_id, crystal_id]
		var guarded: bool = MissionRules.crystal_lock(GameManager.snapshot, want) \
			== MissionRules.LOCK_GUARD

		# Deal with the guard BEFORE walking into its field of fire, not after
		# arriving. Walking the last thirty metres to a Sentinel that is already
		# shooting, without shooting back, is not caution - it is standing still
		# with extra steps. Measured on Cinder, where the hazard errand costs a
		# third of your health first: the driver was downed en route having
		# fired ZERO shots, and reported the crystal unreachable. A player who
		# can see something shooting at them shoots back.
		if guarded:
			if not await _kill_the_guard(want):
				return false

		if not await _nav_walk_to_object(crystal_object, "to %s" % crystal_id):
			_fail("could not reach %s" % crystal_id)
			return false

		if not await _approach_and_use(crystal_object, "the %s" % crystal_id,
				func() -> bool: return _carrying() == want):
			return false
		_event("crystal.taken", "%s in %.1fs, %d hp"
			% [crystal_id, _now() - t_start, int(_player().get("health"))])

		var pedestal_object: String = "%s_pedestal_%s" \
			% [mission_id, _pedestal_letter(crystal_id)]
		if not await _nav_walk_to_object(pedestal_object, "carry %s home" % crystal_id):
			_fail("could not carry %s back to its pedestal" % crystal_id)
			return false
		var hp_before_place := int(_player().get("health"))
		if not await _approach_and_use(pedestal_object,
				"the %s pedestal" % crystal_id,
				func() -> bool: return _carrying() == ""):
			return false
		last_hp_before_place = hp_before_place
	# Health at the altar is the number that decides whether the Warden is a
	# fight or a formality. It used to be whatever the descent had left of it,
	# so a run that fought a crystal guard arrived at a boss tuned for full
	# health and lost to arithmetic rather than to play. Log it either way.
	_event("altar.health", "%d hp before the last crystal was placed, %d after"
		% [last_hp_before_place, int(_player().get("health"))])
	_event("pedestals.placed", "%d of %d"
		% [GameManager.placed_pedestal_count(), GameConfig.REQUIRED_PEDESTAL_COUNT])
	if GameManager.placed_pedestal_count() < GameConfig.REQUIRED_PEDESTAL_COUNT:
		_fail("the altar puzzle could not be completed by walking and pressing E")
		return false

	# The Star Map.
	if not await _nav_walk_to_object("%s_star_map_altar" % mission_id, "altar"):
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
	if not await _nav_walk_to_object("%s_drop_pod" % mission_id, "run for the pod"):
		_fail("the run back to the drop pod is blocked")
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


## Put down the Sentinel standing over a crystal.
##
## Shorter and simpler than the Warden: no shield phase, no enrage, and it dies
## on a hit count rather than a health pool. What it shares is that standing
## still in front of something that shoots you is not playing - so this weaves
## too, and backs off if it closes.
func _kill_the_guard(crystal_id: String) -> bool:
	var guard: Node = null
	if not await _until(func() -> bool:
		guard = _find_guard(crystal_id)
		return guard != null, 8.0):
		_fail("%s is locked by a guard that never spawned" % crystal_id)
		return false
	_event("guard.found", "%s is guarded" % crystal_id)
	_guard_hits_seen = -1
	_guard_fruitless = 0
	_guard_last_report = _now()
	# One baseline reading per fight, taken on the first properly aimed volley.
	# It is here for the guard that WORKS as much as for the one that does not:
	# a probe that says "THE GUARD" on Nerava, where the guard dies in nine
	# volleys, is a probe whose "SCENERY" on Cinder can be believed. Without
	# that pairing the reading is just another unverified claim.
	var sighted := false

	var t_start := _now()
	var deadline := _now() + 90.0
	while _now() < deadline:
		if MissionRules.crystal_lock(GameManager.snapshot, crystal_id) != MissionRules.LOCK_GUARD:
			_event("guard.killed", "%s unsealed in %.1fs, %d volleys"
				% [crystal_id, _now() - t_start, _shots])
			return true
		if not is_instance_valid(guard):
			guard = _find_guard(crystal_id)
			if guard == null:
				await _frames(4)
				continue
		var player := _player() as Node3D
		if player == null:
			break
		if bool(player.get("is_downed")):
			_downs += 1
			_fail("the guard on %s downed the player, who alone cannot be revived"
				% crystal_id)
			return false
		var gap: float = player.global_position.distance_to((guard as Node3D).global_position)
		if gap < GUARD_BACKOFF_RANGE:
			await _hold("move_back", 0.5)
		elif gap > GUARD_ENGAGE_RANGE:
			# Close to a range where the shot is worth taking, ON THE NAVMESH.
			#
			# This used to hold move_forward toward the guard, which works only
			# if the ground between here and there is empty. On Cinder and
			# Hallow it is not: the approach from the south runs into Mesa4, a
			# 12 x 4.5 x 9 block, and the driver spent sixty volleys with its
			# face 0.5 m from that mesa, aimed to within a degree of a guard
			# 26 m away on the far side of it. It reported the guard unkillable.
			# Every other leg of the run routes with the navmesh; this one did
			# not, and it was the one that decided whether two of the three
			# planets could be finished.
			# Walk to a FIRING position, not onto the guard. Routing to its exact
			# position marches the player into contact, which then trips the
			# too-close branch and backs straight out again - a there-and-back
			# that burned most of a 90 s fight and fired five volleys in it.
			var g_pos: Vector3 = (guard as Node3D).global_position
			var stand: Vector3 = g_pos + (player.global_position - g_pos).normalized() * GUARD_FIGHT_RANGE
			if not await _nav_walk_to(stand, "firing range of the guard"):
				# Say which it was. A player downed while closing produces a
				# failed walk, and reporting that as "could not reach the guard"
				# would send the reader after a navigation bug instead of a
				# survivability one - the same mistake the Warden fight already
				# had to be taught out of.
				var pl := _player()
				if pl != null and is_instance_valid(pl) and bool(pl.get("is_downed")):
					_downs += 1
					_fail("the guard on %s downed the player while they closed, and alone they cannot be revived"
						% crystal_id)
				else:
					_fail("could not walk to the guard on %s" % crystal_id)
				return false
			continue
		await _aim_at_point((guard as Node3D).global_position + Vector3(0.0, 1.0, 0.0))
		# Only once we are inside the range the driver actually fires from. The
		# first version read on the FIRST aim, which on Nerava is 69.5 m out -
		# past the blaster's 60 m range - so it dutifully reported "the shot
		# hits NOTHING" about a shot no one was taking. A measurement taken at a
		# moment the thing never happens measures nothing.
		if not sighted and gap <= GUARD_ENGAGE_RANGE:
			sighted = true
			_event("guard.sight", _shot_report(guard))

		# Volleys that land nothing mean something is in the way. The guard's
		# own hit count is the only progress signal there is - the lock state is
		# binary - and without watching it the driver emptied 69 volleys into
		# terrain on Hallow and reported the guard unkillable. Same lesson as
		# the Warden: aimed and ineffective is a THIRD outcome, distinct from
		# missing and from not firing, and only moving fixes it.
		var hits := int(guard.get("_guard_hits")) if guard.has_method("get") else 0

		# Say what is happening on a CLOCK, not per volley. The reposition line
		# below needs eight volleys to trigger, so a fight that is failing by
		# NOT FIRING - five shots in ninety seconds, the player walking back and
		# forth - printed nothing at all and reported only "still standing after
		# 90 s". The Warden fight learned to log its position (defect 70); this
		# one had never been given the same, and the one run where it mattered
		# was unreadable for it.
		if _now() - _guard_last_report >= 6.0:
			_guard_last_report = _now()
			_event("guard.pressing",
				"%d volleys, %d hits, %.1f m away, me=%d hp, at %s guard at %s"
					% [_shots, hits, gap, _my_health(),
						str(player.global_position.snapped(Vector3.ONE * 0.1)),
						str((guard as Node3D).global_position.snapped(Vector3.ONE * 0.1))])

		if hits > _guard_hits_seen:
			_guard_hits_seen = hits
			_guard_fruitless = 0
		else:
			_guard_fruitless += 1
			if _guard_fruitless >= 8:
				_guard_fruitless = 0
				_event("guard.reposition",
					"8 volleys with %s still on %d hits - moving for a line"
						% [crystal_id, hits])
				_event("guard.blocked", _shot_report(guard))
				await _look_at_point((guard as Node3D).global_position)
				Input.action_press("move_left" if _strafe > 0 else "move_right")
				Input.action_press("sprint")
				await _hold("move_forward", 0.8)
				Input.action_release("sprint")
				Input.action_release("move_left" if _strafe > 0 else "move_right")
				continue

		_strafe = -_strafe
		var side := "move_left" if _strafe > 0 else "move_right"
		Input.action_press(side)
		await _hold("fire", 0.55)
		Input.action_release(side)
		_shots += 1
		await _frames(2)

	_fail("the guard on %s was still standing after 90 s" % crystal_id)
	return false


## Run from an enraged Warden - FORWARDS, which is the only direction the game
## lets anyone sprint in.
##
## `player.gd` gates sprint on moving forward (`input.y < 0.0`). The driver held
## `sprint` together with `move_back`, so it was not sprinting at all: it walked
## backwards at 5.0 m/s away from something that closes at 6.4, and could never
## open a gap. Every enraged phase therefore ended in contact range no matter
## how the fight was tuned. Turning round to run is not a trick to beat the
## boss - it is what the enrage is FOR, and a driver that will not do it
## measures itself rather than the game.
func _run_from_the_warden(warden: Node) -> void:
	var player := _player() as Node3D
	if player == null or not is_instance_valid(warden):
		return
	# Run until the gap is actually open, not for a fixed time. A sprinting
	# player gains 2.1 m/s on an enraged Warden, so a 1.1 s dash buys 2.3 m and
	# the boss is back inside contact range before the next volley leaves the
	# barrel. Breaking away means breaking away.
	var deadline := _now() + 4.0
	Input.action_press("sprint")
	while _now() < deadline:
		player = _player() as Node3D
		if player == null or not is_instance_valid(warden):
			break
		if player.global_position.distance_to((warden as Node3D).global_position) \
				>= WARDEN_SAFE_GAP:
			break
		var away: Vector3 = player.global_position - (warden as Node3D).global_position
		away.y = 0.0
		if away.length() < 0.1:
			away = Vector3(1.0, 0.0, 0.0)
		# SERPENTINE, not straight. Running dead away from something that shoots
		# at you is the easiest target there is: no lateral motion means no
		# dodge, and the driver was killed from a full 100 hp in eleven seconds
		# doing exactly that, 24 m clear of the temple. Angling the run keeps
		# the distance opening while still crossing the projectile's path.
		_strafe = -_strafe
		away = away.normalized().rotated(Vector3.UP, deg_to_rad(35.0 * _strafe))
		await _look_at_point(player.global_position + away * 20.0)
		await _hold("move_forward", 0.35)
	Input.action_release("sprint")


## Where does the shot actually STOP?
##
## The guard on Cinder and Hallow takes 0 hits in 60 aimed volleys while the
## identical guard on Nerava dies in 9, and two explanations fit that equally
## well: the guard has drifted inside RuinsBack (it has no collision mask, so
## nothing stops it), or a piece of set dressing sits between the player and
## the guard. Both predict "aimed and ineffective". They differ in exactly one
## observable - what the ray hits - and nobody had looked.
##
## This is a REPLICA of the host's own query in host_process_fire_request:
## same origin (the muzzle), same direction (the camera's forward), same mask,
## same area/body flags, same exclusion. If that function's query ever changes,
## this must change with it or it measures a shot the game does not fire.
func _shot_report(guard: Node) -> String:
	var player := _player() as Node3D
	if player == null:
		return "no player"
	var muzzle := player.get("_muzzle") as Node3D
	var camera := player.get("_camera") as Camera3D
	if muzzle == null or camera == null:
		return "no muzzle/camera"
	var space := player.get_world_3d().direct_space_state
	if space == null:
		return "no space"

	var origin: Vector3 = muzzle.global_position
	var dir: Vector3 = -camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * GameConfig.BLASTER_RANGE)
	query.collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_ENEMY
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [player.get_rid()]
	var hit := space.intersect_ray(query)

	var g3 := guard as Node3D
	var to_guard: float = origin.distance_to(g3.global_position) if g3 != null else -1.0
	if hit.is_empty():
		return "the shot hits NOTHING in %.0f m (guard %.1f m away, aim off by %.1f deg)" % [
			GameConfig.BLASTER_RANGE, to_guard, _aim_error_deg(origin, dir, g3)]

	var collider := hit["collider"] as Node
	var where: Vector3 = hit["position"]
	var hit_name: String = String(collider.name) if collider != null else "<freed>"
	var owner_path: String = hit_name
	if collider != null and collider.get_parent() != null:
		owner_path = String(collider.get_parent().name) + "/" + hit_name
	# Is what we hit the guard, something under it, or scenery?
	var kind := "SCENERY"
	var n: Node = collider
	for _i in 6:
		if n == null:
			break
		if n == guard:
			kind = "THE GUARD"
			break
		n = n.get_parent()
	return "the shot stops on %s (%s) at %.1f m, %.1f m short of the guard, which is %.1f m away; aim off by %.1f deg" % [
		owner_path, kind, origin.distance_to(where),
		maxf(to_guard - origin.distance_to(where), 0.0), to_guard,
		_aim_error_deg(origin, dir, g3)]


## Angle between where the camera points and where the guard actually is. A
## large value here means the driver is missing, which is a different defect
## from a blocked line and must not be reported as one.
func _aim_error_deg(origin: Vector3, dir: Vector3, target: Node3D) -> float:
	if target == null:
		return -1.0
	var want: Vector3 = (target.global_position + Vector3.UP - origin)
	if want.length_squared() < 0.0001:
		return -1.0
	return rad_to_deg(dir.normalized().angle_to(want.normalized()))


## The Sentinel that guards a particular crystal, or null.
func _find_guard(crystal_id: String) -> Node:
	for node in get_tree().get_nodes_in_group(GameConfig.GROUP_GUARDIAN):
		if node.is_in_group(GameConfig.GROUP_BOSS):
			continue
		if String(node.get("guards_crystal_id")) == crystal_id:
			return node
	return null


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
## How far the camera actually turns per pixel of synthetic mouse motion.
##
## The obvious answer is `SettingsManager.effective_mouse_sensitivity()`, and
## the obvious answer is wrong: measured against the real player, one pixel
## moves the camera TWENTY times as far as that constant says. The driver's
## whole steering approach is closed loop precisely so that it does not have to
## trust a number like this - but the size of each correction was still computed
## from it, so every nudge overshot by 20x, the loop had a gain far above one,
## and it oscillated straight into whichever pitch clamp it was heading for.
## That is what pinned the camera at -75 and +65 with the target dead ahead.
##
## So: nudge by a known amount once, see what happened, and use that. It costs
## two frames at the start of a run and makes the driver correct for any
## sensitivity, any engine version, and any input quirk, which is what the
## closed loop was supposed to buy in the first place.
func _look_gain() -> float:
	if _rad_per_px > 0.0:
		return _rad_per_px
	var fallback: float = SettingsManager.effective_mouse_sensitivity()
	var player := _player() as Node3D
	if player == null:
		return fallback
	var pivot := player.get_node_or_null("CameraPivot") as Node3D
	if pivot == null:
		return fallback
	const PROBE_PX := 2.0
	var before: float = pivot.rotation.x
	await _send_mouse(Vector2(0.0, PROBE_PX))
	var moved: float = pivot.rotation.x - before
	await _send_mouse(Vector2(0.0, -PROBE_PX))
	# A measurement taken against a clamp is truncated and would read low, so
	# only believe one that actually moved a sensible amount.
	if absf(moved) < deg_to_rad(0.2):
		return fallback
	_rad_per_px = absf(moved) / PROBE_PX
	_event("look.calibrated", "%.5f rad/px measured (setting says %.5f, ratio %.1fx)"
		% [_rad_per_px, fallback, _rad_per_px / maxf(fallback, 0.000001)])
	return _rad_per_px


## Send one mouse motion and let it land. Both frames matter: the event is
## handled in `_unhandled_input`, which runs on the idle frame, so a value read
## back after only a physics frame is the value from before the nudge.
func _send_mouse(relative: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = relative
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().physics_frame


## Record what the last aim attempt did, for the failure report and the prompt
## line. A camera pointing the wrong way is the commonest reason a prompt does
## not appear, and "no prompt" never says so on its own.
func _note_aim(started: float, wanted: float, settled: float, converged: bool) -> void:
	_last_aim = "%.0f -> want %.0f -> %.0f%s" % [rad_to_deg(started),
		rad_to_deg(wanted), rad_to_deg(settled), "" if converged else " NOCONV"]


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
	if not await _nav_walk_to_object("%s_power_coupling" % mission_id, "to the coupling"):
		_fail("the power coupling is not reachable")
		return false
	if not await _approach_and_use("%s_power_coupling" % mission_id, "the power coupling",
			func() -> bool: return _carrying() == GameConfig.ITEM_COUPLING):
		return false
	if not await _nav_walk_to_object("%s_coupling_socket" % mission_id, "to the socket"):
		_fail("the coupling socket is not reachable")
		return false
	if not await _approach_and_use("%s_coupling_socket" % mission_id, "the coupling socket",
			func() -> bool:
				return MissionRules.crystal_lock(
					GameManager.snapshot, GameConfig.CRYSTAL_CAVE) == ""):
		return false
	_event("coupling.fitted", "the cave crystal is open")
	return true


## True when a crystal on this mission is behind a live hazard field.
func _hazard_locks_a_crystal() -> bool:
	for crystal_id in [GameConfig.CRYSTAL_RUINS, GameConfig.CRYSTAL_CAVE,
			GameConfig.CRYSTAL_GROVE]:
		if MissionRules.crystal_lock(GameManager.snapshot, String(crystal_id)) \
				== MissionRules.LOCK_HAZARD:
			return true
	return false


## Shut the surface hazard down before walking into it.
##
## Cinder burns and Hallow freezes, and on both of them one crystal stands in
## the field. Fetching it with the vent open is a slow death by design, so the
## valve is the errand - and it is at the far edge of the map, which is the
## point of it.
func _seal_the_vent(mission_id: String) -> bool:
	_event("hazard.errand", "the vent is open and a crystal stands in the field")
	var t_start := _now()
	if not await _nav_walk_to_object("%s_hazard_control" % mission_id, "to the vent"):
		_fail("the hazard control is not reachable")
		return false
	if not await _approach_and_use("%s_hazard_control" % mission_id, "the hazard control",
			func() -> bool:
				return not bool(GameManager.snapshot.get("hazard_online", false))):
		return false
	_event("hazard.sealed", "the field is down after %.1fs, %d hp"
		% [_now() - t_start, int(_player().get("health"))])
	return true


## Walk into the temple clearing, wherever this mission put it.
##
## The trigger is an authored Area3D and every surface has one; walking to a
## literal (0, 0, 13) only ever worked because that was Nerava's.
func _walk_to_temple() -> bool:
	var target := Vector3(0.0, 0.0, 13.0)
	var stage := SceneManager.current_stage()
	var trigger := stage.get_node_or_null("TempleTrigger") as Node3D \
		if stage != null else null
	if trigger != null:
		target = trigger.global_position
		target.y = 0.0
	if await _nav_walk_to(target, "temple clearing"):
		return true
	_fail("could not walk from the landing pad to the temple")
	return false


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
			# The PLAYER's health belongs here too. Three balance questions in a
			# row could not be answered from these logs - "is the fight too
			# hard" and "is the driver playing it badly" look identical without
			# the number that separates them.
			_event("warden.phase", "%d, boss=%d nodes=%d, me=%d hp at %.1fs"
				% [phase, int(GameManager.snapshot.get("boss_health", 0)),
					int(GameManager.snapshot.get("boss_nodes", 0)),
					_my_health(), _now()])
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
		_aim_converged = await _aim_at_point((aim_at as Node3D).global_position)

		# Break away when it enrages. An enraged Warden moves at 6.4 m/s and does
		# 18 contact damage a second; a walking player does 5.0 and cannot get
		# away, but a SPRINTING player does 8.5 and can. That is the design - the
		# enrage is what turns the fight from a shooting gallery into a
		# retreat - and a driver that never sprints simply gets run down, which
		# is what kept happening. It is not a boss that is too strong; it is a
		# driver that would not run.
		var player := _player() as Node3D
		if player != null:
			var gap: float = player.global_position.distance_to((warden as Node3D).global_position)
			var enraged := phase == MissionRules.BOSS_ENRAGED
			if enraged and gap < 14.0:
				await _run_from_the_warden(warden)
				# Re-check AFTER the await. Eight tenths of a second is long
				# enough for the crew to be wiped out and every session-bound
				# node freed, and a freed Node in Godot 4 is not null - it is an
				# object that crashes the moment it is cast. The driver died
				# here reporting "aborted without recording a reason", which is
				# the least useful thing a harness can say about a mission that
				# had in fact just been lost in a perfectly legible way.
				if not is_instance_valid(warden):
					break
				_aim_converged = await _aim_at_point((warden as Node3D).global_position)
			elif _strategy == "cautious" and gap < 9.0:
				await _hold("move_back", 0.5)

		# KEEP MOVING WHILE FIRING. The Warden throws three projectiles doing 33
		# damage each at a player with 100 health, and they take the best part of
		# a second to cross the gap - the fight is built around strafing out of
		# the way, and standing still is death by the third volley. The driver
		# used to stand still, went down every time, and made a fight that is
		# merely demanding look unwinnable. Anything read off a driver that does
		# not play the way the fight is designed to be played is a measurement
		# of the driver.
		if GameManager.mission_state() == MS.MISSION_FAILED:
			_fail("the crew was wiped out by the Warden")
			return false

		# Hold a direction for a few volleys instead of flipping every one.
		# Alternating each volley is not moving: measured, the driver covered
		# 0.6 m in four seconds of standing fire and ate every projectile. The
		# Warden's shots take about a second to cross 12 m and a player moving
		# sideways at 5 m/s is five metres away by the time they arrive - which
		# is the whole reason the fight tells you to keep moving.
		_strafe_volleys += 1
		if _strafe_volleys >= 3:
			_strafe_volleys = 0
			_strafe = -_strafe
		var strafe_action := "move_left" if _strafe > 0 else "move_right"

		# Shots that are aimed and still do nothing mean something is IN THE
		# WAY - a temple pillar between us, most likely. The driver once fired
		# 480 volleys at a boss wedged behind one, with the aim dead on, and
		# reported nothing but a deadline. A player would move; so does this.
		# Progress is nodes FIRST, then health: while the shield stands, hitting
		# the body is meant to do nothing, so health alone would read the whole
		# shield phase as fruitless and send the driver wandering off mid-fight.
		var boss_now := int(GameManager.snapshot.get("boss_nodes", 0)) * 10000 \
			+ int(GameManager.snapshot.get("boss_health", 0))
		if boss_now < _boss_health_seen:
			_boss_health_seen = boss_now
			_fruitless = 0
		elif _aim_converged:
			_fruitless += 1
			if _fruitless >= 10:
				_fruitless = 0
				_event("warden.reposition",
					"10 aimed volleys with no progress (%d nodes, %d health) - moving for a line"
						% [int(GameManager.snapshot.get("boss_nodes", 0)),
							int(GameManager.snapshot.get("boss_health", 0))])
				Input.action_press(strafe_action)
				await _hold("move_forward", 0.9)
				Input.action_release(strafe_action)
				continue

		# No angle, no shot. When the aim cannot reach the Warden - the camera
		# against its pitch clamp, or a pillar between us - firing is worse than
		# useless: it overheats the blaster and reads in the log as a fight that
		# was fought and lost. Move for an angle instead, which is what a player
		# does when they cannot see what is shooting at them. A run that spent
		# 84 volleys pinned at +65 degrees with the boss on 50 health is what
		# this is here to stop being invisible.
		if not _aim_converged:
			Input.action_press(strafe_action)
			await _hold("move_back", 0.6)
			Input.action_release(strafe_action)
			await _frames(2)
			continue

		Input.action_press(strafe_action)
		await _hold("fire", _burst_length())
		Input.action_release(strafe_action)
		_shots += 1
		await _frames(2)
		# A fight that is not progressing has to say so before the 180 s
		# deadline, or the only evidence is "the boss did not die".
		#
		# is_instance_valid FIRST. The volley just fired can be the one that
		# kills the Warden, and a dead Warden is freed the same frame - so one
		# run in twelve, the progress log casts a freed object and the whole
		# driver aborts on the winning shot. That is exactly the failure that is
		# worst to have: it reports "aborted without a reason" on a mission the
		# player actually completed, and sends the reader hunting a game bug
		# that is not there.
		if _shots % 12 == 0 and is_instance_valid(warden):
			var pl := _player() as Node3D
			var pivot := pl.get_node_or_null("CameraPivot") as Node3D if pl != null else null
			var boss3 := warden as Node3D
			_event("warden.pressing",
				"%d volleys, phase=%d boss=%d nodes=%d, me=%d hp, %.1f m away, pitch %.0f (want %.0f), at %s boss at %s%s"
				% [_shots, phase, int(GameManager.snapshot.get("boss_health", 0)),
					int(GameManager.snapshot.get("boss_nodes", 0)), _my_health(),
					pl.global_position.distance_to(boss3.global_position)
						if pl != null else -1.0,
					rad_to_deg(pivot.rotation.x) if pivot != null else 999.0,
					rad_to_deg(_wanted_pitch_to(boss3.global_position)),
					str(pl.global_position.snapped(Vector3.ONE * 0.1)) if pl != null else "?",
					str(boss3.global_position.snapped(Vector3.ONE * 0.1)),
					"" if _aim_converged else "  AIM-DID-NOT-CONVERGE"])
		if bool(_player().get("is_downed")):
			_downs += 1
			_event("player.downed", "during the Warden fight")
			# Alone, a downed player cannot be revived. The mission is lost.
			break

	var final_phase := int(GameManager.snapshot.get("boss_phase", 0))
	if final_phase != MissionRules.BOSS_DEAD:
		# Say WHY. This reported "not killed within 180 s" on a fight that ended
		# after 23 because the player was downed, which sent the reader looking
		# for a damage bug instead of a survivability one.
		var pl := _player()
		var reason := "the 180 s limit ran out"
		if pl != null and is_instance_valid(pl) and bool(pl.get("is_downed")):
			reason = "the player was downed and, alone, could not be revived"
		elif not is_instance_valid(warden):
			reason = "the Warden node disappeared"
		_fail("the Warden was not killed - %s (phase=%d, health=%d, %d volleys fired)"
			% [reason, final_phase, int(GameManager.snapshot.get("boss_health", 0)), _shots])
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
		# rotation.y -= relative.x * gain, so a POSITIVE error needs a NEGATIVE
		# relative.x. The step is capped so the loop cannot overshoot forever,
		# and takes 60% of the correction so a small measurement error cannot
		# turn the loop into an oscillator.
		var gain: float = await _look_gain()
		var relative: float = clampf(-(error * 0.6) / gain, -600.0, 600.0)
		await _send_mouse(Vector2(relative, 0.0))


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


## Aim at a point in the world, yaw AND pitch.
##
## `_look_at_point` only turns the body. That is enough for walking, and it was
## wrong for the boss: the Warden hovers 6.4 m above the temple floor, the fight
## aimed with yaw alone, and every shot went under it. A fight the driver cannot
## win looks exactly like a boss that cannot be killed.
func _aim_at_point(target: Vector3) -> bool:
	await _look_at_point(target)
	var player := _player() as Node3D
	if player == null:
		return false
	var pivot := player.get_node_or_null("CameraPivot") as Node3D
	if pivot == null:
		return false
	var sens: float = await _look_gain()
	_last_aim_error = 0.0
	for _i in 12:
		var to_target: Vector3 = target - pivot.global_position
		var flat: float = Vector2(to_target.x, to_target.z).length()
		var error: float = atan2(to_target.y, maxf(flat, 0.01)) - pivot.rotation.x
		_last_aim_error = error
		if absf(error) < deg_to_rad(1.0):
			return true
		await _send_mouse(Vector2(0.0, clampf(-(error * 0.6) / sens, -400.0, 400.0)))
	# Twelve corrections and still off target. Almost always this means the
	# camera is against a pitch clamp: the point is steeper than the player is
	# allowed to look, so no amount of mouse will reach it and every shot fired
	# from here goes somewhere else. Saying so is the difference between "the
	# boss survived" and "the boss could not be aimed at from where we stood".
	return false


## How long to hold the trigger, from what the blaster can actually take.
##
## A fixed 0.55 s is three shots. The weapon allows seven before it overheats,
## and after a retreat it is stone cold - so a fixed burst threw away more than
## half the damage of every window the retreat had just bought, and the enraged
## phase became a war of attrition the player loses. Firing until nearly hot and
## then breaking is how the weapon is built to be used.
func _burst_length() -> float:
	var p := _player()
	if p == null or not is_instance_valid(p):
		return 0.55
	if bool(p.get("overheated")):
		return 0.0
	var headroom: float = GameConfig.BLASTER_HEAT_MAX * 0.92 - float(p.get("heat"))
	var shots: int = clampi(int(headroom / GameConfig.BLASTER_HEAT_PER_SHOT), 1, 7)
	return float(shots) * GameConfig.BLASTER_FIRE_INTERVAL + 0.05


## This player's health, or -1 when there is no player to ask.
func _my_health() -> int:
	var p := _player()
	if p == null or not is_instance_valid(p):
		return -1
	return int(p.get("health"))


## Pitch error left over from the last _aim_at_point, in radians.
var _last_aim_error: float = 0.0
## Whether the last fight aim actually reached its target.
var _aim_converged: bool = true
## Guard hits landed so far, and volleys since the last one. See _kill_the_guard.
var _guard_hits_seen: int = -1
var _guard_fruitless: int = 0
var _guard_last_report: float = 0.0

## The three ranges the guard fight is built from. They have to keep their
## order, so they are defined together and checked at startup rather than left
## as three independent numbers that can quietly cross.
##
## GUARD_ENGAGE_RANGE is the gap above which the driver stops fighting and
## walks. GUARD_FIGHT_RANGE is where that walk aims. GUARD_BACKOFF_RANGE is
## where it decides it is too close.
##
## Setting the walk target to 20 with the threshold at 22 is what broke this:
## the walk arrives within a couple of metres, that put the gap back OVER the
## threshold, and the driver walked to the same place forever - 0 shots fired in
## ninety seconds on two planets, 6 on the third. It was a change made to spend
## less time under fire on the approach, and the health it was chasing is a
## secondary signal; it cost the fight entirely. The margin below is what stops
## the arrive tolerance from reaching the threshold.
const GUARD_ENGAGE_RANGE: float = 22.0
const GUARD_FIGHT_RANGE: float = 16.0
const GUARD_BACKOFF_RANGE: float = 7.0

## How much room the walk target must leave below the engage threshold. The
## navmesh arrive radius is 2.6 m, so anything under about 4 can round-trip.
const GUARD_RANGE_MARGIN: float = 4.0
## Volleys fired since the last strafe reversal. See _fight_the_warden.
var _strafe_volleys: int = 0
## Best boss progress seen (nodes weighted above health), and aimed volleys
## since it last improved.
var _boss_health_seen: int = 1 << 30
var _fruitless: int = 0


## The pitch the camera WOULD need to look at a world point, in radians. Read
## alongside the pitch it actually has: the two disagreeing by tens of degrees
## is the signature of a camera against its clamp, firing at the sky.
func _wanted_pitch_to(target: Vector3) -> float:
	var player := _player() as Node3D
	if player == null:
		return 0.0
	var pivot := player.get_node_or_null("CameraPivot") as Node3D
	if pivot == null:
		return 0.0
	var to_target: Vector3 = target - pivot.global_position
	return atan2(to_target.y, maxf(Vector2(to_target.x, to_target.z).length(), 0.01))


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
	var sens: float = await _look_gain()
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
		if _aimed_at(wanted_id) and absf(error) < deg_to_rad(12.0):
			# Close enough AND the ray is on it: stop rather than chase the last
			# few degrees, which can only shake the aim loose.
			converged = true
			break
		# _pitch = _pitch - relative.y * gain, so a POSITIVE error (look up)
		# needs a NEGATIVE relative.y.
		await _send_mouse(Vector2(0.0, clampf(-(error * 0.6) / sens, -400.0, 400.0)))

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
	_note_aim(started_at, wanted, pivot.rotation.x, converged)


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
	for _i in 10:
		var error: float = wanted - pivot.rotation.x
		if absf(error) < deg_to_rad(0.5):
			return
		await _send_mouse(Vector2(0.0, clampf(-(error * 0.6) / sens, -400.0, 400.0)))


## Walk to a point with WASD. Returns false if the player gets stuck or the leg
## times out - which is the finding this whole harness exists to produce.
func _walk_to(target: Vector3, label: String,
		arrive: float = ARRIVE_RADIUS) -> bool:
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
		if player.global_position.distance_to(flat_target) <= arrive:
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


## Walk somewhere using the level's OWN navigation mesh.
##
## The hard-coded corridor tables encoded real knowledge - the dog-leg at
## (14, 0, 0) exists because a straight line walks into a stalagmite - but it
## was one mission's knowledge, hand-measured off Nerava. Two thirds of the
## catalog had therefore never been played by anything, on any build.
##
## The navmesh already knows where the walkable ground is on every surface,
## because the Sentinel navigates by it and `GameLevel` bakes it before it
## reports the scene ready. Asking it for the corridor is more general than a
## table AND closer to what a player does, which is walk round the rock they
## can see. When there is no navmesh or no route the leg falls back to a
## straight line, so a missing bake degrades to the old behaviour and the stuck
## detector still says what it hit.
func _nav_walk_to(target: Vector3, label: String) -> bool:
	var path: PackedVector3Array = _nav_path(target)
	if path.size() < 2:
		return await _walk_to(target, label)
	var legs: Array = []
	# Drop the first corner - it is where the player already stands - and any
	# corner that repeats the one before it. Nothing else: a navmesh corner is a
	# corner precisely BECAUSE the straight line past it is not walkable, and
	# thinning them on distance is how the driver walked into TemplePillar4 with
	# a perfectly good path in hand.
	for i in range(1, path.size()):
		var corner: Vector3 = path[i]
		if not legs.is_empty() and corner.distance_to(legs.back()) < 0.3:
			continue
		legs.append(corner)
	if legs.is_empty():
		legs.append(target)
	for i in legs.size():
		# Round each corner properly. The default arrive radius is 2.6 m, which
		# is fine for "walk over to that console" and far too loose for a corner
		# with 0.4 m of clearance either side: stopping 2.6 m short of a turn
		# and heading for the next corner cuts exactly the geometry the turn
		# exists to avoid. The last leg keeps the loose radius, because it ends
		# at a stand-off point in front of an object rather than at a corner.
		var last: bool = i == legs.size() - 1
		if not await _walk_to(legs[i], "%s (%d/%d)" % [label, i + 1, legs.size()],
				ARRIVE_RADIUS if last else NAV_CORNER_RADIUS):
			return false
	return true


## The navigation path from where the player stands to `target`, or empty.
func _nav_path(target: Vector3) -> PackedVector3Array:
	var player := _player() as Node3D
	if player == null:
		return PackedVector3Array()
	var region := _nav_region()
	if region == null:
		return PackedVector3Array()
	var map: RID = region.get_navigation_map()
	if not map.is_valid():
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(map, player.global_position, target, true)


func _nav_region() -> NavigationRegion3D:
	var stage := SceneManager.current_stage()
	if stage == null:
		return null
	return stage.get_node_or_null("NavigationRegion3D") as NavigationRegion3D


## Walk to an interactable by id, without knowing where it is.
##
## This is what makes the driver mission-agnostic: the object ids differ only by
## their mission prefix, and the navmesh supplies the route. `offset` backs off
## from the object itself so the player ends up in front of it rather than
## inside its collision shape.
func _nav_walk_to_object(object_id: String, label: String) -> bool:
	var node := SpawnManager.find_interactable(object_id) as Node3D
	if node == null:
		_fail("%s does not exist in this level" % object_id)
		return false
	var player := _player() as Node3D
	if player == null:
		return false
	var to_object: Vector3 = node.global_position - player.global_position
	to_object.y = 0.0
	var stand_off: Vector3 = node.global_position
	if to_object.length() > 2.0:
		stand_off -= to_object.normalized() * 1.6
	return await _nav_walk_to(stand_off, label)


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
	var piv0 := (_player() as Node3D).get_node_or_null("CameraPivot") as Node3D
	_event("prompt", "%s -> '%s' (ray on '%s', pitch %.0f, aim: %s)"
		% [label, prompt, hovered_id,
			rad_to_deg(piv0.rotation.x) if piv0 != null else 999.0, _last_aim])
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
		_event("press.blocked", "%s: %s" % [label, _why_the_host_refuses(object_id)])
		_fail("%s: five presses while aimed at it did not take (last frame: ray='%s' latch=%s pending=%d)"
			% [label,
				("none" if h == null or not is_instance_valid(h)
					else String((h as Node).get("object_id"))),
				str(pl.get("_interact_held")) if pl != null else "?",
				int(pl.get("_interact_pending_until_ms")) if pl != null else -1])
		return false
	return true


## Run the HOST's own line-of-sight query and name what it hits.
##
## The client's interact ray and the host's validation ray are different rays -
## the client's leaves the camera and stops at whatever it touches, the host's
## goes from the player's chest to a point 0.6 m above the object's ORIGIN and
## is blocked only by world geometry. When they disagree the player is shown a
## prompt for something that will always be refused, which is as bad as a bug
## gets: `REJECTED reason=interact_no_line_of_sight` five times while the HUD
## said "Press E to Fit Power Coupling". Naming the obstruction is the
## difference between a bug report and a bug fix.
func _why_the_host_refuses(object_id: String) -> String:
	var node := SpawnManager.find_interactable(object_id) as Node3D
	var player := _player() as Node3D
	if node == null or player == null:
		return "no node to test"
	var space := player.get_world_3d().direct_space_state
	if space == null:
		return "no physics space"
	var from: Vector3 = player.global_position + Vector3.UP * 1.2
	var to: Vector3 = node.global_position + Vector3.UP * 0.6
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = GameConfig.LAYER_WORLD
	query.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return "the host's line of sight is CLEAR from %s to %s - the refusal is something else" \
			% [str(from.snapped(Vector3.ONE * 0.1)), str(to.snapped(Vector3.ONE * 0.1))]
	var who: Node = hit.get("collider")
	return "the host's line of sight %s -> %s is blocked by %s at %s" % [
		str(from.snapped(Vector3.ONE * 0.1)), str(to.snapped(Vector3.ONE * 0.1)),
		(who.name if who != null else "?"),
		str((hit.get("position", Vector3.ZERO) as Vector3).snapped(Vector3.ONE * 0.1))]


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
