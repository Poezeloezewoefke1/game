extends RefCounted
class_name TestCase
## Minimal assertion-based test base.
##
## No third-party test framework is used: the project must be checkable with a
## stock Godot binary and nothing else, in CI and on a contributor's machine.
##
## Two flavours of test:
##   * synchronous - every `test_*` method is discovered and called.
##   * asynchronous - override `is_async()` to true and implement `run_async()`;
##     the runner awaits it. Needed for anything involving frames, scene
##     mounting, physics or the network.

var tree: SceneTree = null

var failures: Array[String] = []
var assertions: int = 0
var _current: String = ""


func suite_name() -> String:
	return get_script().resource_path.get_file().get_basename()


func is_async() -> bool:
	return false


## Overridden by async suites.
func run_async() -> void:
	pass


## Optional per-suite setup/teardown.
func before_all() -> void:
	pass


func after_all() -> void:
	pass


func set_current(name: String) -> void:
	_current = name


# --- Assertions -----------------------------------------------------------

func _fail(message: String) -> void:
	failures.append("%s :: %s" % [_current if not _current.is_empty() else "?", message])


func check(condition: bool, message: String) -> bool:
	assertions += 1
	if not condition:
		_fail(message)
		return false
	return true


func check_false(condition: bool, message: String) -> bool:
	return check(not condition, message)


func check_eq(actual: Variant, expected: Variant, message: String) -> bool:
	assertions += 1
	if not _same(actual, expected):
		_fail("%s (expected %s, got %s)" % [message, str(expected), str(actual)])
		return false
	return true


func check_ne(actual: Variant, unexpected: Variant, message: String) -> bool:
	assertions += 1
	if _same(actual, unexpected):
		_fail("%s (did not expect %s)" % [message, str(unexpected)])
		return false
	return true


func check_near(actual: float, expected: float, tolerance: float, message: String) -> bool:
	assertions += 1
	if absf(actual - expected) > tolerance:
		_fail("%s (expected %f +/- %f, got %f)" % [message, expected, tolerance, actual])
		return false
	return true


## Asserts a MissionRules verdict allowed the action.
func check_allowed(verdict: Dictionary, message: String) -> bool:
	assertions += 1
	if not bool(verdict.get("ok", false)):
		_fail("%s (denied: %s)" % [message, str(verdict.get("reason", ""))])
		return false
	return true


## Asserts a MissionRules verdict denied the action, optionally for a specific
## reason. Checking the reason matters: a rule that denies for the WRONG reason
## is a rule that will stop denying as soon as something unrelated changes.
func check_denied(verdict: Dictionary, expected_reason: String, message: String) -> bool:
	assertions += 1
	if bool(verdict.get("ok", false)):
		_fail("%s (was allowed but should have been denied)" % message)
		return false
	if not expected_reason.is_empty() and String(verdict.get("reason", "")) != expected_reason:
		_fail("%s (denied for '%s', expected '%s')" % [
			message, str(verdict.get("reason", "")), expected_reason])
		return false
	return true


static func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_FLOAT or typeof(b) == TYPE_FLOAT:
		return is_equal_approx(float(a), float(b))
	return a == b


# --- Helpers --------------------------------------------------------------

func wait_frames(count: int) -> void:
	for i in count:
		await tree.process_frame


func wait_seconds(seconds: float) -> void:
	await tree.create_timer(seconds).timeout
