extends TestCase
## The Interact press rule: _resolve().
##
## WHY THIS EXISTS. The press used to be sampled on exactly one frame, so if the
## interact ray was momentarily off the object - head bob is enough - the press
## was spent against nothing and the latch blocked every retry until the key was
## released. It reproduced only under the automated playtest, which caught it as
## "held=true ray=none latch=true": E down, ray on nothing, intent consumed.
##
## The fix made a press an intent with a deadline, and this pins the whole
## contract so it cannot quietly regress into a one-frame sample again.

const GRACE_MS := int(GameConfig.INTERACT_GRACE_TIME * 1000.0)

## player.gd declares no class_name, so the static rule is reached through the
## loaded script - the same way test_app_shell reaches UIRoot.should_capture_mouse().
static var _player_script: GDScript = load("res://scripts/player/player.gd")


func _resolve(pressed: bool, held: bool, pending: int, now: int, target: String) -> Dictionary:
	return _player_script.resolve_interact(pressed, held, pending, now, target)


func test_a_press_on_a_target_fires_once() -> void:
	var r := _resolve(true, false, 0, 1000, "crystal_ruins")
	check(bool(r["fire"]), "a press with a target fires")
	check(bool(r["held"]), "and is marked spent")

	# The same key still down on the next frame must not fire again.
	var r2 := _resolve(true, bool(r["held"]), int(r["pending_until_ms"]),
		1016, "crystal_ruins")
	check_false(bool(r2["fire"]), "holding the key does not fire a second time")
	check(bool(r2["held"]), "and stays spent")


func test_a_press_with_no_target_waits_instead_of_being_spent() -> void:
	var r := _resolve(true, false, 0, 1000, "")
	check_false(bool(r["fire"]), "a press with nothing under the ray does not fire")
	check_false(bool(r["held"]), "and is NOT spent - this is the whole bug")
	check(int(r["pending_until_ms"]) > 1000, "it records a deadline to keep looking until")


func test_a_waiting_press_fires_when_the_target_appears() -> void:
	# Frame 1: ray on nothing. Frame 2: the ray finds the station.
	var r1 := _resolve(true, false, 0, 1000, "")
	var r2 := _resolve(true, bool(r1["held"]), int(r1["pending_until_ms"]),
		1016, "ship_task_reactor")
	check(bool(r2["fire"]), "the press is satisfied one frame later")
	check(bool(r2["held"]), "and is then spent")


func test_a_waiting_press_expires() -> void:
	var r1 := _resolve(true, false, 0, 1000, "")
	var late := 1000 + GRACE_MS + 1
	var r2 := _resolve(true, bool(r1["held"]), int(r1["pending_until_ms"]),
		late, "")
	check_false(bool(r2["fire"]), "an unsatisfied press does not fire after the deadline")
	check(bool(r2["held"]), "it is spent, so a held key cannot fire on something later")


## The safety property the grace window must not break: holding E while walking
## past things is a legitimate action (it is also the revive key), and it must
## never turn into a stream of interactions.
func test_holding_the_key_never_autofires() -> void:
	var held := false
	var pending := 0
	var fires := 0
	var now := 1000
	for _frame in 120:
		var r := _resolve(true, held, pending, now, "some_object")
		if bool(r["fire"]):
			fires += 1
		held = bool(r["held"])
		pending = int(r["pending_until_ms"])
		now += 16
	check_eq(fires, 1, "two seconds of holding E fires exactly once")


func test_releasing_clears_everything() -> void:
	var r := _resolve(false, true, 12345, 2000, "anything")
	check_false(bool(r["fire"]), "releasing does not fire")
	check_false(bool(r["held"]), "releasing clears the latch")
	check_eq(int(r["pending_until_ms"]), 0, "and clears any pending deadline")


## And the press must be usable again immediately after a release.
func test_press_release_press_fires_twice() -> void:
	var a := _resolve(true, false, 0, 1000, "pedestal_a")
	var b := _resolve(false, bool(a["held"]), int(a["pending_until_ms"]), 1016, "")
	var c := _resolve(true, bool(b["held"]), int(b["pending_until_ms"]),
		1032, "pedestal_a")
	check(bool(a["fire"]) and bool(c["fire"]), "two separate presses both fire")
