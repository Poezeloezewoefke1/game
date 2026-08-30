extends TestCase
## Drives a complete mission - lobby to victory - against a real host session.
##
## Every gameplay action goes through the SAME public entry point a player's
## input uses (GameManager.request_interact), so the host's range check, line of
## sight check, epoch check and MissionRules verdict all run for real.

const MS := MissionRules.MissionState

## Positions chosen to sit inside the authored geometry and within
## INTERACT_VALIDATE_DISTANCE of their target.
const HUB_TERMINAL_SPOT := Vector3(0, 0, -9)
const TEMPLE_TRIGGER_SPOT := Vector3(0, 0, 13)
const CRYSTAL_SPOTS := {
	"nerava_crystal_ruins": Vector3(-42, 0, 0),
	"nerava_crystal_cave": Vector3(42, 0, 0),
	"nerava_crystal_grove": Vector3(0, 0, -42),
}
const PEDESTAL_SPOTS := {
	"nerava_pedestal_a": Vector3(-3, 0, 3),
	"nerava_pedestal_b": Vector3(3, 0, 3),
	"nerava_pedestal_c": Vector3(0, 0, -6),
}
const PEDESTAL_FOR_CRYSTAL := {
	"crystal_ruins": "nerava_pedestal_a",
	"crystal_cave": "nerava_pedestal_b",
	"crystal_grove": "nerava_pedestal_c",
}
const ALTAR_SPOT := Vector3(0, 0, 1)
const DROP_POD_SPOT := Vector3(0, 0, 43)

var _session: TestSession = null


func is_async() -> bool:
	return true


func run_async() -> void:
	_session = TestSession.new(tree)
	var err := _session.start("FlowTester", 7610)
	if not check(err.is_empty(), "host session starts (%s)" % err):
		return

	await _phase_lobby()
	await _phase_hub()
	await _phase_descent()
	await _phase_temple()
	await _phase_crystals()
	await _phase_altar()
	await _phase_extraction()

	_session.stop()
	await tree.process_frame


# --------------------------------------------------------------------------

func _phase_lobby() -> void:
	set_current("lobby")
	check_eq(GameManager.mission_state(), MS.LOBBY_READY, "a fresh host session sits in LOBBY_READY")
	check_eq(LobbyManager.player_count(), 1, "the host is on the roster")
	check_eq(LobbyManager.display_name_of(GameConfig.HOST_PEER_ID), "FlowTester", "the host name is stored")
	check(GameManager.host_accepts_new_players(), "the lobby accepts joins")
	check(NetworkManager.is_local_host(), "the local peer is the host")


func _phase_hub() -> void:
	set_current("hub")
	await GameManager.host_start_session()
	if not check(await _session.await_scene(GameConfig.SCENE_HUB), "the hub mounts"):
		return
	check(await _session.await_mission_state(MS.HUB_IDLE), "the mission reaches HUB_IDLE")
	check_false(GameManager.host_accepts_new_players(), "joins are refused once the session has started")

	var player := _session.host_player()
	if not check(player != null, "the host player spawned in the hub"):
		return
	check_eq(int(player.get("health")), GameConfig.MAX_HEALTH, "the player spawns at full health")
	check_false(bool(player.get("is_downed")), "the player does not spawn downed")
	check_eq(int(player.get("owner_peer_id")), GameConfig.HOST_PEER_ID, "the player belongs to the host peer")

	check(SpawnManager.find_interactable("hub_mission_terminal") != null,
		"the Mission Terminal is registered by object id")


func _phase_descent() -> void:
	set_current("descent")
	# Out of range first: the host must refuse even though the object is real.
	await _session.move_host_player_to(Vector3(0, 0, 8))
	GameManager.request_interact("hub_mission_terminal")
	await tree.process_frame
	check_eq(GameManager.mission_state(), MS.HUB_IDLE, "an out-of-range terminal request is refused")

	# An object id that does not exist must be refused without side effects.
	GameManager.request_interact("totally_made_up_object")
	await tree.process_frame
	check_eq(GameManager.mission_state(), MS.HUB_IDLE, "an unknown object id changes nothing")

	# Now in range - this is the real path.
	await _session.move_host_player_to(HUB_TERMINAL_SPOT)
	GameManager.request_interact("hub_mission_terminal")
	check(await _session.await_scene(GameConfig.SCENE_NERAVA), "the terminal starts the descent to Nerava")
	check(await _session.await_mission_state(MS.FIND_TEMPLE), "the mission reaches FIND_TEMPLE")
	check(_session.host_player() != null, "the player respawned on Nerava")


func _phase_temple() -> void:
	set_current("temple")
	check_eq(GameManager.mission_state(), MS.FIND_TEMPLE, "the objective starts at FIND_TEMPLE")
	await _session.move_host_player_to(TEMPLE_TRIGGER_SPOT)
	check(await _session.await_mission_state(MS.FIND_CRYSTALS, 5.0),
		"walking into the clearing discovers the Temple")
	check(bool(GameManager.snapshot.get("temple_discovered", false)), "the snapshot records the discovery")


func _phase_crystals() -> void:
	set_current("crystals")
	var first := true
	for oid in CRYSTAL_SPOTS:
		var crystal_id := String(oid).replace("nerava_", "")
		await _session.move_host_player_to(CRYSTAL_SPOTS[oid])

		if first:
			first = false
			# A pedestal cannot be filled by an empty-handed player.
			await _session.move_host_player_to(PEDESTAL_SPOTS["nerava_pedestal_a"])
			GameManager.request_interact("nerava_pedestal_a")
			await tree.process_frame
			check_eq(GameManager.pedestal_content("pedestal_a"), "",
				"an empty-handed placement is refused")
			await _session.move_host_player_to(CRYSTAL_SPOTS[oid])

		GameManager.request_interact(String(oid))
		await tree.process_frame
		check_eq(GameManager.carried_crystal_of(GameConfig.HOST_PEER_ID), crystal_id,
			"picking up %s puts it in the player's hands" % crystal_id)
		check_false(GameManager.is_crystal_in_world(crystal_id),
			"%s leaves the world when carried" % crystal_id)

		# Taking it twice must be impossible.
		GameManager.request_interact(String(oid))
		await tree.process_frame
		check_eq(GameManager.carried_crystal_of(GameConfig.HOST_PEER_ID), crystal_id,
			"%s cannot be picked up twice" % crystal_id)

		# A pedestal that wants a different crystal must refuse without
		# consuming the one being carried.
		var wrong := "nerava_pedestal_b" if crystal_id != "crystal_cave" else "nerava_pedestal_a"
		await _session.move_host_player_to(PEDESTAL_SPOTS[wrong])
		GameManager.request_interact(wrong)
		await tree.process_frame
		check_eq(GameManager.carried_crystal_of(GameConfig.HOST_PEER_ID), crystal_id,
			"a wrong-pedestal attempt does not consume %s" % crystal_id)

		var correct := String(PEDESTAL_FOR_CRYSTAL[crystal_id])
		await _session.move_host_player_to(PEDESTAL_SPOTS[correct])
		GameManager.request_interact(correct)
		await tree.process_frame
		check_eq(GameManager.pedestal_content(correct.replace("nerava_", "")), crystal_id,
			"%s is accepted by its pedestal" % crystal_id)
		check_eq(GameManager.carried_crystal_of(GameConfig.HOST_PEER_ID), "",
			"placing %s empties the player's hands" % crystal_id)

		# A filled pedestal must refuse a second placement.
		GameManager.request_interact(correct)
		await tree.process_frame
		check_eq(GameManager.pedestal_content(correct.replace("nerava_", "")), crystal_id,
			"a filled pedestal is not overwritten")

	check_eq(GameManager.placed_pedestal_count(), GameConfig.REQUIRED_PEDESTAL_COUNT,
		"all three pedestals are powered")


func _phase_altar() -> void:
	set_current("altar")
	check(GameManager.is_altar_active(), "the altar opens once all three pedestals are powered")
	check_eq(GameManager.star_map_state(), MissionRules.MAP_AVAILABLE, "the Star Map becomes available")
	check(await _session.await_mission_state(MS.RETRIEVE_STAR_MAP, 5.0),
		"the objective advances to RETRIEVE_STAR_MAP")
	check_eq(_session.guardian_count(), 0, "no Sentinel exists before the Star Map is taken")

	await _session.move_host_player_to(ALTAR_SPOT)
	GameManager.request_interact("nerava_star_map_altar")
	await tree.process_frame
	check_eq(GameManager.star_map_state(), MissionRules.MAP_CARRIED, "the Star Map is carried")
	check_eq(GameManager.star_map_carrier(), GameConfig.HOST_PEER_ID, "the carrier is recorded")
	check(await _session.await_mission_state(MS.RETURN_TO_DROP_POD, 5.0),
		"the objective advances to RETURN_TO_DROP_POD")

	await wait_frames(2)
	check_eq(_session.guardian_count(), 1, "exactly one Sentinel spawns")

	# Requesting it again must not spawn a second Sentinel.
	GameManager.request_interact("nerava_star_map_altar")
	await wait_frames(2)
	check_eq(_session.guardian_count(), 1, "a repeated Star Map request does not duplicate the Sentinel")


func _phase_extraction() -> void:
	set_current("extraction")
	# Extraction must be refused from the altar, far from the pod.
	GameManager.request_interact("nerava_drop_pod")
	await tree.process_frame
	check_eq(GameManager.mission_state(), MS.RETURN_TO_DROP_POD,
		"extraction is refused away from the Drop Pod")

	await _session.move_host_player_to(DROP_POD_SPOT)
	GameManager.request_interact("nerava_drop_pod")
	check(await _session.await_mission_state(MS.MISSION_COMPLETE, 5.0), "extraction completes the mission")
	check_eq(GameManager.star_map_state(), MissionRules.MAP_EXTRACTED, "the Star Map is secured")
	check_eq(GameManager.star_map_carrier(), 0, "no one carries the Star Map after extraction")

	await wait_frames(3)
	check_eq(_session.guardian_count(), 0, "the Sentinel is removed on victory")
	check_eq(_session.projectile_count(), 0, "no projectiles survive victory")
