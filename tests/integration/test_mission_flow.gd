extends TestCase
## Drives a complete mission - lobby to victory - against a real host session.
##
## Every gameplay action goes through the SAME public entry point a player's
## input uses (GameManager.request_interact), so the host's range check, line of
## sight check, epoch check and MissionRules verdict all run for real.

const MS := MissionRules.MissionState

## Positions chosen to sit inside the authored geometry and within
## INTERACT_VALIDATE_DISTANCE of their target.
## Aboard the Starfarer. The bridge is at the bow, so these are all negative Z.
const SHIP_NAV_SPOT := Vector3(0, 0, -14.5)
const SHIP_LEVER_SPOT := Vector3(5.0, 0, -15.0)
const SHIP_SEAT_SPOT := Vector3(-5.6, 0, -18.6)
const SHIP_STATION_SPOTS := {
	"ship_task_reactor": Vector3(1.0, 0, 8.4),
	"ship_task_fuel": Vector3(6.2, 0, 13.4),
	"ship_task_hatch": Vector3(0.0, 0, 21.6),
}
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
## The coupling and the socket that unseals the cave crystal.
const COUPLING_SPOT := Vector3(-4, 0, 24)
const SOCKET_SPOT := Vector3(34, 0, -3)
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
	await _phase_preflight()
	await _phase_descent()
	await _phase_temple()
	await _phase_coupling()
	await _phase_crystals()
	await _phase_altar()
	await _phase_boss()
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
	if not check(await _session.await_scene(GameConfig.SCENE_SHIP), "the hub mounts"):
		return
	check(await _session.await_mission_state(MS.SHIP_IDLE), "the mission reaches SHIP_IDLE")
	check_false(GameManager.host_accepts_new_players(), "joins are refused once the session has started")

	var player := _session.host_player()
	if not check(player != null, "the host player spawned in the hub"):
		return
	check_eq(int(player.get("health")), GameConfig.MAX_HEALTH, "the player spawns at full health")
	check_false(bool(player.get("is_downed")), "the player does not spawn downed")
	check_eq(int(player.get("owner_peer_id")), GameConfig.HOST_PEER_ID, "the player belongs to the host peer")

	for object_id in ["ship_nav_console", "ship_launch_lever", "ship_seat_1",
			"ship_task_reactor", "ship_task_fuel", "ship_task_hatch"]:
		check(SpawnManager.find_interactable(String(object_id)) != null,
			"%s is registered by object id" % object_id)


## The pre-flight checklist, driven exactly as a player drives it: walk to each
## station, work it, sit down, pull the lever. Every step goes through
## request_interact, so the host's range, line-of-sight and MissionRules checks
## all run for real.
func _phase_preflight() -> void:
	set_current("preflight")

	# Out of range first: the host must refuse even though the object is real.
	await _session.move_host_player_to(Vector3(0, 0, 10))
	GameManager.request_interact("ship_launch_lever")
	await tree.process_frame
	check_eq(GameManager.mission_state(), MS.SHIP_IDLE, "an out-of-range lever request is refused")

	# An object id that does not exist must be refused without side effects.
	GameManager.request_interact("totally_made_up_object")
	await tree.process_frame
	check_eq(GameManager.mission_state(), MS.SHIP_IDLE, "an unknown object id changes nothing")

	# The lever must refuse while the checklist is red, even in range.
	await _session.move_host_player_to(SHIP_LEVER_SPOT)
	GameManager.request_interact("ship_launch_lever")
	await tree.process_frame
	check_eq(GameManager.mission_state(), MS.SHIP_IDLE,
		"the lever refuses to launch with stations still red")

	# Work the three stations.
	for object_id in SHIP_STATION_SPOTS:
		await _session.move_host_player_to(SHIP_STATION_SPOTS[object_id])
		GameManager.request_interact(String(object_id))
		await tree.process_frame
	# ...and plot a course, which is the fourth item on the checklist.
	await _session.move_host_player_to(SHIP_NAV_SPOT)
	GameManager.request_interact("ship_nav_console")
	await tree.process_frame
	check(MissionRules.ship_tasks_remaining(GameManager.snapshot).is_empty(),
		"every pre-flight station is green")

	# Still refused: nobody is strapped in.
	await _session.move_host_player_to(SHIP_LEVER_SPOT)
	GameManager.request_interact("ship_launch_lever")
	await tree.process_frame
	check_eq(GameManager.mission_state(), MS.SHIP_IDLE,
		"the lever refuses to launch with the crew out of their seats")

	# Sit down.
	await _session.move_host_player_to(SHIP_SEAT_SPOT)
	GameManager.request_interact("ship_seat_1")
	await tree.process_frame
	check_eq(MissionRules.seat_of(GameManager.snapshot, GameConfig.HOST_PEER_ID),
		"ship_seat_1", "the host is recorded in seat one")
	var player := _session.host_player()
	check_eq(String(player.get("seated_at")), "ship_seat_1",
		"the player node knows it is seated")
	check(player.call("is_seated"), "the player reports itself seated")

	# A second peer cannot take a seat that is already held. There is only one
	# player in this session, so this is checked through the rule directly.
	var taken := MissionRules.can_take_seat(GameManager.snapshot, 99, "ship_seat_1",
		{"alive": true, "downed": false, "in_mission_scene": true})
	check_false(bool(taken["ok"]), "a held seat is refused to a second peer")
	check_eq(String(taken["reason"]), "seat_occupied", "and refused for the right reason")


func _phase_descent() -> void:
	set_current("descent")
	# The lever is armed now. This is the real path.
	await _session.move_host_player_to(SHIP_LEVER_SPOT)
	GameManager.request_interact("ship_launch_lever")
	check(await _session.await_mission_state(MS.LAUNCHING, 5.0),
		"the lever starts the launch sequence")
	# A seated player cannot leave their seat mid-flight.
	var leave := MissionRules.can_leave_seat(GameManager.snapshot, GameConfig.HOST_PEER_ID)
	check_false(bool(leave["ok"]), "the crew is restrained during flight")
	check_eq(String(leave["reason"]), "restrained_in_flight", "and told why")

	check(await _session.await_scene(GameConfig.SCENE_NERAVA, 40.0),
		"the flight ends on the destination surface")
	check(await _session.await_mission_state(MS.FIND_TEMPLE), "the mission reaches FIND_TEMPLE")
	check(_session.host_player() != null, "the player respawned on Nerava")
	check_eq(String(_session.host_player().get("seated_at")), "",
		"nobody is still strapped into a seat that no longer exists")


func _phase_temple() -> void:
	set_current("temple")
	check_eq(GameManager.mission_state(), MS.FIND_TEMPLE, "the objective starts at FIND_TEMPLE")
	await _session.move_host_player_to(TEMPLE_TRIGGER_SPOT)
	check(await _session.await_mission_state(MS.FIND_CRYSTALS, 5.0),
		"walking into the clearing discovers the Temple")
	check(bool(GameManager.snapshot.get("temple_discovered", false)), "the snapshot records the discovery")


## The coupling lock, end to end: the cave crystal is sealed, the coupling is
## across the map, it takes the one inventory slot, and fitting it opens the
## seal. Everything goes through request_interact, so the host's own gate is
## what refuses the early attempts - not the prompt.
func _phase_coupling() -> void:
	set_current("coupling")
	check_eq(MissionRules.crystal_lock(GameManager.snapshot, GameConfig.CRYSTAL_CAVE),
		MissionRules.LOCK_COUPLING, "the cave crystal starts sealed")

	# Taking it while sealed must be refused by the host.
	await _session.move_host_player_to(CRYSTAL_SPOTS["nerava_crystal_cave"])
	GameManager.request_interact("nerava_crystal_cave")
	await tree.process_frame
	check_eq(GameManager.carried_crystal_of(GameConfig.HOST_PEER_ID), "",
		"a sealed crystal cannot be taken")
	check(GameManager.is_crystal_in_world(GameConfig.CRYSTAL_CAVE),
		"and it stays in the world")

	# Fitting nothing must be refused too.
	await _session.move_host_player_to(SOCKET_SPOT)
	GameManager.request_interact("nerava_coupling_socket")
	await tree.process_frame
	check_eq(MissionRules.crystal_lock(GameManager.snapshot, GameConfig.CRYSTAL_CAVE),
		MissionRules.LOCK_COUPLING, "the socket refuses an empty hand")

	# Fetch it.
	await _session.move_host_player_to(COUPLING_SPOT)
	GameManager.request_interact("nerava_power_coupling")
	await tree.process_frame
	check_eq(GameManager.carried_crystal_of(GameConfig.HOST_PEER_ID),
		GameConfig.ITEM_COUPLING, "the coupling is carried")
	check(bool(GameManager.snapshot.get("coupling_taken", false)),
		"the snapshot records the coupling as lifted")

	# It occupies the crystal slot: a crystal cannot be picked up while holding it.
	await _session.move_host_player_to(CRYSTAL_SPOTS["nerava_crystal_ruins"])
	GameManager.request_interact("nerava_crystal_ruins")
	await tree.process_frame
	check_eq(GameManager.carried_crystal_of(GameConfig.HOST_PEER_ID),
		GameConfig.ITEM_COUPLING, "the coupling blocks the inventory slot")

	# Fit it, and the seal opens.
	await _session.move_host_player_to(SOCKET_SPOT)
	GameManager.request_interact("nerava_coupling_socket")
	await tree.process_frame
	check_eq(MissionRules.crystal_lock(GameManager.snapshot, GameConfig.CRYSTAL_CAVE), "",
		"fitting the coupling unseals the cave crystal")
	check_eq(GameManager.carried_crystal_of(GameConfig.HOST_PEER_ID), "",
		"fitting the coupling empties the hands again")


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
	check(await _session.await_mission_state(MS.BOSS_FIGHT, 5.0),
		"taking the Star Map starts the boss fight")

	await wait_frames(2)
	check_eq(_session.guardian_count(), 1, "exactly one Warden spawns")

	# Requesting it again must not spawn a second guardian.
	GameManager.request_interact("nerava_star_map_altar")
	await wait_frames(2)
	check_eq(_session.guardian_count(), 1, "a repeated Star Map request does not duplicate the Warden")


## The Warden, from shield to death, through the same entry point a blaster ray
## uses. Nothing here reaches past host_register_hit into the boss's internals.
func _phase_boss() -> void:
	set_current("boss")
	var warden := _find_warden()
	if not check(warden != null, "the Warden is in the level"):
		return

	check_eq(int(GameManager.snapshot.get("boss_phase", -1)), MissionRules.BOSS_SHIELDED,
		"the Warden starts shielded")
	check_false(MissionRules.boss_takes_damage(GameManager.snapshot),
		"a shielded Warden takes no body damage")

	# Shoot the body while the shield is up: health must not move.
	var before := int(warden.get("sync_health"))
	for i in 20:
		warden.call("host_register_hit", GameConfig.HOST_PEER_ID, warden)
	check_eq(int(warden.get("sync_health")), before,
		"body shots are refused while the shield holds")

	# Break the three nodes.
	var ring: Node = warden.get_node_or_null("ShieldRing")
	if not check(ring != null, "the Warden has a shield ring"):
		return
	for i in 3:
		var node: Node = ring.get_node_or_null("Node%d" % (i + 1))
		if node == null:
			continue
		var guard := 0
		while (int(warden.get("sync_nodes")) & (1 << i)) != 0 and guard < 60:
			guard += 1
			warden.call("host_register_hit", GameConfig.HOST_PEER_ID, node)
		check_eq(int(warden.get("sync_nodes")) & (1 << i), 0,
			"shield node %d can be destroyed" % (i + 1))

	await wait_frames(2)
	check_eq(int(GameManager.snapshot.get("boss_phase", -1)), MissionRules.BOSS_VOLLEY,
		"the Warden drops its shield once every node is down")
	check(MissionRules.boss_takes_damage(GameManager.snapshot),
		"an exposed Warden takes damage")

	# Now kill it, and watch it pass through the enrage threshold on the way.
	var saw_enraged := false
	var shots := 0
	while int(warden.get("sync_health")) > 0 and shots < 400:
		shots += 1
		warden.call("host_register_hit", GameConfig.HOST_PEER_ID, warden)
		if int(GameManager.snapshot.get("boss_phase", -1)) == MissionRules.BOSS_ENRAGED:
			saw_enraged = true
	check(saw_enraged, "the Warden enrages before it dies")
	check_eq(int(GameManager.snapshot.get("boss_phase", -1)), MissionRules.BOSS_DEAD,
		"the Warden dies")
	check(await _session.await_mission_state(MS.RETURN_TO_DROP_POD, 5.0),
		"killing the Warden opens the run back to the pod")


func _find_warden() -> Node:
	for node in tree.get_nodes_in_group(GameConfig.GROUP_GUARDIAN):
		if node.has_method("health_fraction"):
			return node
	return null


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
	check_eq(_session.guardian_count(), 0, "no guardian survives victory")
	check(GameManager.snapshot.get("completed_missions", []).has(MissionCatalog.NERAVA),
		"finishing Nerava records it as complete")
	check(MissionCatalog.is_unlocked(MissionCatalog.CINDER,
			GameManager.snapshot.get("completed_missions", [])),
		"finishing Nerava unlocks the next destination")
	check_eq(_session.projectile_count(), 0, "no projectiles survive victory")
