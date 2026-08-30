extends Node
## Headless test runner.
##
## Run with:
##   godot --headless --path . res://tests/test_runner.tscn
##
## It runs in THREE phases, and each phase is a real check rather than a claim:
##   1. COMPILE  - every .gd file in the project is loaded. Because autoloads are
##                 live in this mode (unlike `--check-only --script`), this
##                 catches identifier and type errors that a script-mode parse
##                 check silently misses.
##   2. SCENES   - every .tscn is loaded AND instantiated, then freed. Loading
##                 alone would not catch a bad node path or a missing @onready.
##   3. TESTS    - tests/unit then tests/integration.
##
## Exit code 0 = everything passed. Non-zero = something failed, and the reason
## is printed above the summary.

const UNIT_DIR := "res://tests/unit"
const INTEGRATION_DIR := "res://tests/integration"
const SCRIPT_ROOTS: Array[String] = ["res://scripts", "res://tests"]
const SCENE_ROOTS: Array[String] = ["res://scenes"]

## Scenes that must not be instantiated bare by the scene phase, because they
## are only meaningful when spawned with a payload by SpawnManager.
const SCENE_INSTANTIATE_SKIP: Array[String] = [
	"res://scenes/entities/player.tscn",
	"res://scenes/enemies/sentinel.tscn",
	"res://scenes/enemies/guardian_projectile.tscn",
	"res://scenes/interactables/dropped_star_map.tscn",
	# Template scenes: their object_id / crystal_id exports are intentionally
	# empty and are filled in by the level that instances them. They are still
	# fully exercised - the level scenes below instantiate every one of them.
	"res://scenes/interactables/power_crystal.tscn",
	"res://scenes/interactables/crystal_pedestal.tscn",
]

var _failures: Array[String] = []
var _passed: int = 0
var _assertions: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	print("")
	print("================================================================")
	print(" STARBOUND STATION - headless validation")
	print(" Godot %s" % Engine.get_version_info().get("string", "?"))
	print("================================================================")

	_phase_compile()
	await _phase_scenes()
	await _phase_suites(UNIT_DIR, "UNIT")
	await _phase_suites(INTEGRATION_DIR, "INTEGRATION")

	print("")
	print("----------------------------------------------------------------")
	if _failures.is_empty():
		print(" RESULT: PASS   (%d checks passed, %d assertions)" % [_passed, _assertions])
		print("----------------------------------------------------------------")
		get_tree().quit(0)
		return
	print(" RESULT: FAIL   (%d failures)" % _failures.size())
	for f in _failures:
		print("   x %s" % f)
	print("----------------------------------------------------------------")
	get_tree().quit(1)


# ==========================================================================
# Phase 1 - compile every script
# ==========================================================================

func _phase_compile() -> void:
	print("")
	print("[1/3] Compiling scripts...")
	var files: Array[String] = []
	for root in SCRIPT_ROOTS:
		_collect(root, ".gd", files)
	files.sort()
	var bad := 0
	for path in files:
		var problem := _script_problem(path)
		if problem.is_empty():
			_passed += 1
		else:
			bad += 1
			_failures.append("compile: %s %s" % [path, problem])
	print("      %d scripts, %d failed" % [files.size(), bad])


## Returns "" when the script is genuinely usable, otherwise the reason.
##
## IMPORTANT: load() returns a NON-NULL GDScript for a script that failed to
## parse. Checking only for null makes the whole compile phase blind - CI would
## report green on a project that cannot run. can_instantiate() is false and
## get_instance_base_type() is empty for a script that did not compile, so both
## are checked here.
func _script_problem(path: String) -> String:
	var res := load(path)
	if res == null:
		return "failed to load"
	var gds := res as GDScript
	if gds == null:
		return "is not a GDScript"
	if not gds.can_instantiate():
		return "did not compile (see the parse errors above)"
	if gds.get_instance_base_type() == StringName(""):
		return "has no resolvable base type"
	return ""


# ==========================================================================
# Phase 2 - load and instantiate every scene
# ==========================================================================

func _phase_scenes() -> void:
	print("[2/3] Loading scenes...")
	var files: Array[String] = []
	for root in SCENE_ROOTS:
		_collect(root, ".tscn", files)
	files.append("res://main.tscn")
	files.sort()
	var bad := 0
	for path in files:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			bad += 1
			_failures.append("scene: %s failed to load" % path)
			continue
		if SCENE_INSTANTIATE_SKIP.has(path):
			_passed += 1
			continue
		var instance: Node = packed.instantiate()
		if instance == null:
			bad += 1
			_failures.append("scene: %s failed to instantiate" % path)
			continue
		# main.tscn binds global roots; instantiating a second copy would
		# hijack SceneManager. Free it without ever entering the tree.
		if path == "res://main.tscn":
			instance.free()
			_passed += 1
			continue
		add_child(instance)
		await get_tree().process_frame
		instance.queue_free()
		await get_tree().process_frame
		_passed += 1
	print("      %d scenes, %d failed" % [files.size(), bad])


# ==========================================================================
# Phase 3 - test suites
# ==========================================================================

func _phase_suites(dir: String, label: String) -> void:
	print("[3/3] %s tests..." % label if dir == UNIT_DIR else "      %s tests..." % label)
	var files: Array[String] = []
	_collect(dir, ".gd", files)
	files.sort()
	for path in files:
		await _run_suite(path)


func _run_suite(path: String) -> void:
	var problem := _script_problem(path)
	if not problem.is_empty():
		_failures.append("suite: %s %s" % [path, problem])
		return
	var script: GDScript = load(path) as GDScript
	var instance: Variant = script.new()
	if not (instance is TestCase):
		# Helper file in the tests folder, not a suite.
		return
	var suite: TestCase = instance
	suite.tree = get_tree()

	suite.before_all()
	if suite.is_async():
		suite.set_current("run_async")
		await suite.run_async()
	else:
		for method in script.get_script_method_list():
			var name := String(method.get("name", ""))
			if not name.begins_with("test_"):
				continue
			suite.set_current(name)
			suite.call(name)
	suite.after_all()

	_assertions += suite.assertions
	if suite.failures.is_empty():
		_passed += 1
		print("      PASS  %-34s (%d assertions)" % [suite.suite_name(), suite.assertions])
	else:
		for f in suite.failures:
			_failures.append("%s :: %s" % [suite.suite_name(), f])
		print("      FAIL  %-34s (%d failures)" % [suite.suite_name(), suite.failures.size()])


# ==========================================================================

func _collect(dir_path: String, suffix: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_collect(full, suffix, out)
		elif entry.ends_with(suffix):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
