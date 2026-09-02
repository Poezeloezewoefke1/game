extends TestCase
## Simultaneous requests for the same thing.
##
## Single-threaded does not mean race-free. Two peers can have requests queued in
## the same frame, and a handler that mutates a collection it is iterating - or
## that assumes it is the only one acting on a target - fails here and nowhere
## else.

const MS := MissionRules.MissionState
const P2 := 2
const P3 := 3

var _session: TestSession = null


func is_async() -> bool:
	return true


func run_async() -> void:
	_session = TestSession.new(tree)
	var err := _session.start("RaceTester", 7830)
	if not check(err.is_empty(), "host session starts (%s)" % err):
		return

	LobbyManager.host_add_player(P2, "Second")
	LobbyManager.host_add_player(P3, "Third")

	await GameManager.host_start_session()
	if not check(await _session.await_scene(GameConfig.SCENE_SHIP), "the hub mounts"):
		_session.stop()
		return
	await GameManager.host_start_expedition()
	if not check(await _session.await_scene(GameConfig.SCENE_NERAVA), "Nerava mounts"):
		_session.stop()
		return
	await wait_frames(2)

	await _test_simultaneous_crystal_grab()
	await _test_simultaneous_revive()
	await _test_duplicate_extraction()

	_session.stop()
	await tree.process_frame


# --------------------------------------------------------------------------

func _test_simultaneous_crystal_grab() -> void:
	set_current("crystal race")
	var epoch := GameManager.session_epoch
	# Put all three players next to the same crystal.
	for peer_id in [GameConfig.HOST_PEER_ID, P2, P3]:
		var node: Node = SpawnManager.player_node(peer_id)
		if node != null:
			(node as Node3D).global_position = Vector3(-42, 0, 0)
			node.set("sync_position", Vector3(-42, 0, 0))
	await tree.physics_frame

	# Three requests for one crystal, in the same frame.
	for peer_id in [GameConfig.HOST_PEER_ID, P2, P3]:
		GameManager.host_handle_interact_request(peer_id, "nerava_crystal_ruins", epoch)
	await wait_frames(2)

	var carried: Dictionary = GameManager.snapshot.get("crystals_carried", {})
	var holders := 0
	for peer_id in carried:
		if String(carried[peer_id]) == GameConfig.CRYSTAL_RUINS:
			holders += 1
	check_eq(holders, 1, "exactly one player ends up holding the contested crystal")
	check_false(GameManager.is_crystal_in_world(GameConfig.CRYSTAL_RUINS),
		"the contested crystal left the world exactly once")


func _test_simultaneous_revive() -> void:
	set_current("revive race")
	var epoch := GameManager.session_epoch
	var target: Node = SpawnManager.player_node(P3)
	if not check(target != null, "the revive target exists"):
		return

	# Two revivers, both in range, both starting on the same frame.
	for peer_id in [GameConfig.HOST_PEER_ID, P2]:
		var node: Node = SpawnManager.player_node(peer_id)
		if node != null:
			(node as Node3D).global_position = Vector3(-42.0, 0, 1.0)
			node.set("sync_position", Vector3(-42.0, 0, 1.0))
	(target as Node3D).global_position = Vector3(-42, 0, 0)
	target.set("sync_position", Vector3(-42, 0, 0))
	await tree.physics_frame

	target.host_set_downed()
	await wait_frames(2)
	check(bool(target.get("is_downed")), "the target is downed")

	GameManager.host_handle_revive_start(GameConfig.HOST_PEER_ID, P3, epoch)
	GameManager.host_handle_revive_start(P2, P3, epoch)
	await wait_frames(2)
	check(bool(target.get("revive_active")), "the revive is running")

	# Let both run to completion. Whichever finishes first must win, and the
	# other must be cancelled without the host erroring mid-iteration.
	await wait_seconds(GameConfig.REVIVE_DURATION + 0.8)

	check_false(bool(target.get("is_downed")), "the target was revived")
	check_eq(int(target.get("health")), GameConfig.REVIVED_HEALTH,
		"revived exactly once, at the revive health (a double revive would not change this, "
		+ "but a crashed tick loop would leave the player downed)")
	check_false(bool(target.get("revive_active")), "no revive is still marked active")
	check_eq(GameManager.debug_active_revives(), 0, "no revive entry survived the race")

	# The whole system must still work afterwards - a half-broken tick loop
	# would show up as the NEXT revive never completing.
	target.host_set_downed()
	await wait_frames(2)
	GameManager.host_handle_revive_start(GameConfig.HOST_PEER_ID, P3, epoch)
	await wait_seconds(GameConfig.REVIVE_DURATION + 0.8)
	check_false(bool(target.get("is_downed")),
		"a later revive still works, so the tick loop survived the race")


func _test_duplicate_extraction() -> void:
	set_current("extraction race")
	GameManager.snapshot["temple_discovered"] = true
	GameManager.snapshot["state"] = MS.RETRIEVE_STAR_MAP
	GameManager.snapshot["altar_active"] = true
	GameManager.snapshot["star_map_state"] = MissionRules.MAP_AVAILABLE
	GameManager.host_apply_star_map_pickup(GameConfig.HOST_PEER_ID)
	await wait_frames(2)
	check_eq(GameManager.mission_state(), MS.BOSS_FIGHT, "taking the map starts the boss fight")

	# This test is about the extraction RACE, not about the boss, so the Warden
	# is killed through the host entry point rather than shot down. Going
	# through host_on_boss_killed keeps the state machine honest - it is the
	# same call the real fight makes.
	GameManager.host_on_boss_killed()
	await wait_frames(2)
	check_eq(GameManager.mission_state(), MS.RETURN_TO_DROP_POD, "the return leg started")

	var epoch := GameManager.session_epoch
	var carrier: Node = SpawnManager.player_node(GameConfig.HOST_PEER_ID)
	(carrier as Node3D).global_position = Vector3(0, 0, 43)
	carrier.set("sync_position", Vector3(0, 0, 43))
	# A non-carrier standing at the pod must not be able to extract.
	var other: Node = SpawnManager.player_node(P2)
	(other as Node3D).global_position = Vector3(1, 0, 43)
	other.set("sync_position", Vector3(1, 0, 43))
	await tree.physics_frame

	GameManager.host_handle_interact_request(P2, "nerava_drop_pod", epoch)
	await wait_frames(2)
	check_eq(GameManager.mission_state(), MS.RETURN_TO_DROP_POD,
		"a non-carrier at the pod cannot extract")

	# Three extraction requests from the carrier in the same frame.
	for i in 3:
		GameManager.host_handle_interact_request(GameConfig.HOST_PEER_ID, "nerava_drop_pod", epoch)
	await wait_frames(3)
	check_eq(GameManager.mission_state(), MS.MISSION_COMPLETE, "extraction completed")
	check_eq(GameManager.star_map_state(), MissionRules.MAP_EXTRACTED, "the Star Map is secured once")
