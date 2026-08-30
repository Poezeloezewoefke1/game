extends TestCase
## The Sentinel: targeting, stagger, projectiles and cleanup.
##
## Most of this was previously only reviewed by reading. The guardian's brain is
## host-only and runs on a timer, so the failure mode of "it silently never
## moves or never shoots" is invisible until somebody plays the mission - which
## is exactly the kind of thing that should not be left to a manual pass.

const MS := MissionRules.MissionState
const P2 := 2

var _session: TestSession = null
var _guardian: Node = null
var _p1: Node = null
var _p2: Node = null


func is_async() -> bool:
	return true


func run_async() -> void:
	_session = TestSession.new(tree)
	var err := _session.start("SentinelTester", 7860)
	if not check(err.is_empty(), "host session starts (%s)" % err):
		return

	if not await _setup():
		_session.stop()
		return

	await _test_navigation_ready()
	await _test_targets_the_carrier()
	await _test_blaster_registers_a_hit()
	await _test_stagger()
	await _test_retargets_when_the_carrier_goes_down()
	await _test_projectile_damage()
	await _test_cleanup_on_mission_end()

	_session.stop()
	await tree.process_frame


func _setup() -> bool:
	set_current("setup")
	LobbyManager.host_add_player(P2, "Second")
	await GameManager.host_start_session()
	if not check(await _session.await_scene(GameConfig.SCENE_HUB), "the hub mounts"):
		return false
	await GameManager.host_start_expedition()
	if not check(await _session.await_scene(GameConfig.SCENE_NERAVA), "Nerava mounts"):
		return false
	await wait_frames(2)

	_p1 = SpawnManager.player_node(GameConfig.HOST_PEER_ID)
	_p2 = SpawnManager.player_node(P2)
	if not check(_p1 != null and _p2 != null, "both players spawned"):
		return false

	# Put the mission where the Star Map is genuinely takeable, then take it -
	# that is the only thing that spawns a Sentinel.
	GameManager.snapshot["temple_discovered"] = true
	GameManager.snapshot["state"] = MS.RETRIEVE_STAR_MAP
	GameManager.snapshot["altar_active"] = true
	GameManager.snapshot["star_map_state"] = MissionRules.MAP_AVAILABLE
	GameManager.host_apply_star_map_pickup(P2)
	await wait_frames(3)

	var guardians := tree.get_nodes_in_group(GameConfig.GROUP_GUARDIAN)
	if not check_eq(guardians.size(), 1, "exactly one Sentinel exists"):
		return false
	_guardian = guardians[0]
	return true


func _test_navigation_ready() -> void:
	set_current("navigation")
	# The bake happened at level load; the Sentinel only has to find the map
	# usable. If this never becomes true the guardian silently falls back to
	# direct steering and will grind against the temple walls.
	var ready := false
	for i in 300:
		await tree.physics_frame
		if bool(_guardian.debug_nav_ready()):
			ready = true
			break
	check(ready, "the Sentinel's navigation became usable")


func _test_targets_the_carrier() -> void:
	set_current("targeting")
	# Put both players in range, with P2 (the carrier) further away, so a
	# "nearest player" implementation would pick the wrong one.
	_place(_p1, Vector3(-4, 0, -10))
	_place(_p2, Vector3(6, 0, -10))
	await wait_frames(6)
	check_eq(int(_guardian.debug_target_peer()), P2,
		"the Sentinel targets the Star Map carrier, not the nearest player")


func _test_blaster_registers_a_hit() -> void:
	set_current("blaster hit")
	var before := int(_guardian.debug_hit_count())
	# Stand next to the guardian and shoot straight at it.
	var gpos: Vector3 = (_guardian as Node3D).global_position
	_place(_p1, gpos + Vector3(0, -GameConfig.GUARDIAN_HOVER_HEIGHT, 6))
	await wait_frames(2)
	var origin: Vector3 = _p1.authoritative_position() + Vector3.UP * 1.4
	var direction: Vector3 = (gpos - origin).normalized()
	var fired: bool = _p1.host_process_fire_request(
		GameConfig.HOST_PEER_ID, origin, direction, GameManager.session_epoch)
	check(fired, "the shot was accepted by the host")
	await wait_frames(2)
	check_eq(int(_guardian.debug_hit_count()), before + 1,
		"a validated blaster shot registers exactly one hit on the Sentinel")


func _test_stagger() -> void:
	set_current("stagger")
	# Drive the counter through the host-side entry point rather than firing:
	# a single player cannot land ten shots before overheating, so firing would
	# be testing the heat budget, not the stagger rule.
	for i in GameConfig.GUARDIAN_STAGGER_HIT_THRESHOLD:
		_guardian.host_register_hit(GameConfig.HOST_PEER_ID)
	await wait_frames(2)
	check_eq(int(_guardian.debug_state()), 3, "ten validated hits stagger the Sentinel")
	check_eq(int(_guardian.debug_hit_count()), 0, "the hit counter resets on stagger")

	# Further hits while staggered must not extend or re-trigger it.
	_guardian.host_register_hit(GameConfig.HOST_PEER_ID)
	check_eq(int(_guardian.debug_hit_count()), 0, "hits during a stagger are ignored")

	await wait_seconds(GameConfig.GUARDIAN_STAGGER_DURATION + 0.6)
	check_ne(int(_guardian.debug_state()), 3, "the stagger ends after its duration")


func _test_retargets_when_the_carrier_goes_down() -> void:
	set_current("retargeting")
	check_eq(int(_guardian.debug_target_peer()), P2, "the carrier is still the target")
	_p2.host_set_downed()
	await wait_frames(6)
	check_eq(GameManager.star_map_state(), MissionRules.MAP_DROPPED,
		"downing the carrier drops the Star Map")
	check_eq(int(_guardian.debug_target_peer()), GameConfig.HOST_PEER_ID,
		"with no carrier the Sentinel switches to the nearest living player")

	# A downed player must never be chosen as a target.
	check_ne(int(_guardian.debug_target_peer()), P2, "a downed player is not targeted")


func _test_projectile_damage() -> void:
	set_current("projectile")
	var health_before := int(_p1.get("health"))
	_place(_p1, Vector3(0, 0, 0))
	await wait_frames(2)

	var target: Vector3 = _p1.authoritative_position() + Vector3.UP * 1.0
	var origin: Vector3 = target + Vector3(0, 0, 6)
	var projectile: Node = SpawnManager.host_spawn_guardian_projectile(
		origin, (target - origin).normalized())
	if not check(projectile != null, "a guardian projectile spawned"):
		return
	check_eq(_session.projectile_count(), 1, "exactly one projectile exists")

	var hit := false
	for i in 240:
		await tree.physics_frame
		if int(_p1.get("health")) < health_before:
			hit = true
			break
	check(hit, "the projectile damaged the player")
	check_eq(int(_p1.get("health")), health_before - GameConfig.GUARDIAN_PROJECTILE_DAMAGE,
		"it dealt exactly the configured damage, once")

	await wait_frames(3)
	check_eq(_session.projectile_count(), 0, "the projectile despawned on impact")


func _test_cleanup_on_mission_end() -> void:
	set_current("cleanup")
	# Down the last standing player: the mission fails, and the Sentinel and
	# everything it produced must go with it.
	_p1.host_set_downed()
	await wait_frames(4)
	check_eq(GameManager.mission_state(), MS.MISSION_FAILED, "the mission failed")
	await wait_frames(4)
	check_eq(_session.guardian_count(), 0, "the Sentinel is removed")
	check_eq(_session.projectile_count(), 0, "no projectile survives")


func _place(node: Node, position: Vector3) -> void:
	if node == null:
		return
	(node as Node3D).global_position = position
	node.set("sync_position", position)
	node.set("velocity", Vector3.ZERO)
