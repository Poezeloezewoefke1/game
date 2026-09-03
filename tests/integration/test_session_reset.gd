extends TestCase
## Replay hygiene: the requirement that a retried or restarted mission begins
## with NO stale state of any kind.
##
## This is the test that would catch the classic co-op bug where the second
## attempt starts with the previous run's crystals missing, two Sentinels alive,
## or a player still marked as downed.

const MS := MissionRules.MissionState
const REPLAYS := 3

var _session: TestSession = null


func is_async() -> bool:
	return true


func run_async() -> void:
	_session = TestSession.new(tree)
	var err := _session.start("ResetTester", 7690)
	if not check(err.is_empty(), "host session starts (%s)" % err):
		return

	await GameManager.host_start_session()
	if not check(await _session.await_scene(GameConfig.SCENE_SHIP), "the hub mounts"):
		_session.stop()
		return
	await GameManager.host_start_expedition()
	if not check(await _session.await_scene(GameConfig.SCENE_NERAVA), "Nerava mounts"):
		_session.stop()
		return

	# Replay the same mission several times. A leak usually shows up as growth,
	# so the counts are compared across runs, not just checked once.
	for attempt in REPLAYS:
		set_current("replay %d" % (attempt + 1))
		await _dirty_the_session()
		await _fail_and_retry()
		_check_clean_slate(attempt + 1)

	await _test_return_to_lobby()

	_session.stop()
	await tree.process_frame


## Makes the mission as messy as possible before the reset, so the reset has
## something real to clean up.
func _dirty_the_session() -> void:
	var epoch := GameManager.session_epoch
	GameManager.snapshot["temple_discovered"] = true
	GameManager.snapshot["state"] = MS.RETRIEVE_STAR_MAP
	GameManager.snapshot["crystals_in_world"] = []
	GameManager.snapshot["pedestals"] = {
		"pedestal_a": GameConfig.CRYSTAL_RUINS,
		"pedestal_b": GameConfig.CRYSTAL_CAVE,
		"pedestal_c": GameConfig.CRYSTAL_GROVE,
	}
	GameManager.snapshot["altar_active"] = true
	GameManager.snapshot["star_map_state"] = MissionRules.MAP_AVAILABLE
	GameManager.host_apply_star_map_pickup(GameConfig.HOST_PEER_ID)
	await wait_frames(2)
	check_eq(_session.guardian_count(), 1, "a Sentinel is alive before the reset")

	# Drop the map so a dropped entity exists too.
	var player := _session.host_player()
	if player != null:
		player.host_set_downed()
	await wait_frames(2)
	check_eq(GameManager.session_epoch, epoch, "the epoch does not drift during play")


func _fail_and_retry() -> void:
	check(await _session.await_mission_state(MS.MISSION_FAILED, 5.0),
		"downing the only player fails the mission")
	var epoch_before := GameManager.session_epoch
	await GameManager.host_retry_mission()
	check(await _session.await_scene(GameConfig.SCENE_NERAVA), "the retry re-enters Nerava")
	check(await _session.await_mission_state(MS.FIND_TEMPLE, 10.0), "the retry restarts the objective")
	check(GameManager.session_epoch > epoch_before,
		"the retry bumps the session epoch (invalidating stale requests)")
	await wait_frames(3)


func _check_clean_slate(attempt: int) -> void:
	var tag := "after replay %d" % attempt

	# --- Mission facts ---
	for cid in GameConfig.ALL_CRYSTAL_IDS:
		check(GameManager.is_crystal_in_world(cid), "%s: %s is back in the world" % [tag, cid])
	check_eq(GameManager.placed_pedestal_count(), 0, "%s: every pedestal is empty" % tag)
	check_false(GameManager.is_altar_active(), "%s: the altar is shielded again" % tag)
	check_eq(GameManager.star_map_state(), MissionRules.MAP_LOCKED, "%s: the Star Map is locked" % tag)
	check_eq(GameManager.star_map_carrier(), 0, "%s: nobody carries the Star Map" % tag)
	check_false(bool(GameManager.snapshot.get("guardian_spawned", true)),
		"%s: the guardian_spawned flag is cleared" % tag)
	check_false(bool(GameManager.snapshot.get("temple_discovered", true)),
		"%s: temple discovery is cleared" % tag)
	check_eq(GameManager.carried_crystal_of(GameConfig.HOST_PEER_ID), "",
		"%s: no crystal is still held" % tag)

	# --- Nodes ---
	check_eq(_session.guardian_count(), 0, "%s: no Sentinel survives" % tag)
	check_eq(_session.projectile_count(), 0, "%s: no projectile survives" % tag)
	check_eq(_session.session_bound_count(), 0, "%s: no session-bound entity survives" % tag)

	# --- Players ---
	var players := SpawnManager.all_players()
	check_eq(players.size(), LobbyManager.player_count(),
		"%s: exactly one player node per roster entry (no duplicates)" % tag)
	var player := _session.host_player()
	if check(player != null, "%s: the player respawned" % tag):
		check_eq(int(player.get("health")), GameConfig.MAX_HEALTH, "%s: full health" % tag)
		check_false(bool(player.get("is_downed")), "%s: not downed" % tag)
		check_near(float(player.get("heat")), 0.0, 0.01, "%s: the blaster is cool" % tag)
		check_false(bool(player.get("revive_active")), "%s: no revive is in progress" % tag)

	# --- Interactable registry ---
	# Counted from the scene, not hardcoded. The point of this check is that a
	# replay leaves NO stale registrations behind - not that Nerava happens to
	# contain a particular number of objects. The hardcoded 8 only ever measured
	# how recently someone had edited the level.
	var ids := SpawnManager.interactable_ids()
	check_eq(ids.size(), _authored_interactable_count(),
		"%s: exactly the authored interactables are registered (got %d)" % [tag, ids.size()])
	check_eq(ids.size(), _unique(ids).size(),
		"%s: no id is registered twice" % tag)

	# --- Stale requests must be rejected ---
	var stale_epoch := GameManager.session_epoch - 1
	GameManager.host_handle_interact_request(GameConfig.HOST_PEER_ID, "nerava_crystal_ruins", stale_epoch)
	check(GameManager.is_crystal_in_world(GameConfig.CRYSTAL_RUINS),
		"%s: a request carrying the previous epoch is rejected" % tag)


func _test_return_to_lobby() -> void:
	set_current("return to lobby")
	await GameManager.host_return_to_lobby()
	check(await _session.await_mission_state(MS.LOBBY_READY, 10.0), "the session returns to LOBBY_READY")
	check_eq(SceneManager.current_scene_key, GameConfig.SCENE_LOBBY, "the lobby scene is mounted")
	check_eq(SpawnManager.all_players().size(), 0, "no player entity survives the return to lobby")
	check_eq(_session.guardian_count(), 0, "no Sentinel survives the return to lobby")
	check_eq(_session.session_bound_count(), 0, "no session-bound entity survives the return to lobby")
	check_eq(SpawnManager.interactable_ids().size(), 0, "the interactable registry is empty in the lobby")
	check(GameManager.host_accepts_new_players(), "the lobby accepts joins again")
	check_false(LobbyManager.is_ready(GameConfig.HOST_PEER_ID), "ready flags are cleared")


## How many interactables the destination's scene actually authors. Loaded once
## and cached: instantiating a level per replay would dominate the test's time.
var _authored_count: int = -1


func _authored_interactable_count() -> int:
	if _authored_count >= 0:
		return _authored_count
	_authored_count = 0
	var key := MissionCatalog.scene_key(String(GameManager.snapshot.get("mission_id", "")))
	var path := GameConfig.scene_path(key if key != "" else GameConfig.SCENE_NERAVA)
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return _authored_count
	var level := packed.instantiate()
	for node in level.find_children("*", "", true, false):
		var oid: Variant = node.get("object_id")
		if oid != null and String(oid) != "":
			_authored_count += 1
	level.free()
	return _authored_count


func _unique(values: Array) -> Array:
	var seen: Dictionary = {}
	for v in values:
		seen[v] = true
	return seen.keys()
