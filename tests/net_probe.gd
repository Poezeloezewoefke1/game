extends Node
## Two-process networking probe.
##
## Everything else in tests/ runs inside ONE process, which means the host code
## paths are real but the client code paths are only simulated. This probe runs
## the game as separate OS processes talking over real ENet on loopback, so the
## client-side RPC declarations, the scene-readiness barrier, snapshot
## replication and the host's rejection of hostile client requests are all
## exercised for real.
##
## Launched by tools/run_multiplayer_check.sh. Never shipped: the export preset
## excludes res://tests/.
##
##   Host:   --role=host   --port=7700 --peers=2
##   Client: --role=client --port=7700 --address=127.0.0.1 --name=Crew1 --slot=0
##   Extra:  --role=reject --port=7700 --address=127.0.0.1 --name=Crew5
##           (expects to be turned away because the session is full)

const CRYSTAL_FOR_SLOT := [
	["nerava_crystal_ruins", "crystal_ruins"],
	["nerava_crystal_cave", "crystal_cave"],
	["nerava_crystal_grove", "crystal_grove"],
]

## Routes through the authored corridors. The probe must WALK, not teleport:
## the host rejects implausible movement, and a straight line from the drop pod
## to a crystal goes through solid canyon rock, which shoves the character body
## somewhere unpredictable.
const ROUTE_FOR_SLOT := [
	[Vector3(0, 0, 30), Vector3(0, 0, 14), Vector3(0, 0, 4), Vector3(-10, 0, 0), Vector3(-42, 0, 0)],
	# The cave crystal is SEALED. Slot 1 collects the power coupling in the
	# canyon on its way past and fits it at the socket in the cave mouth, so the
	# lock is exercised across real processes and not only in-process by
	# test_mission_flow. Nerava is the tutorial: its coupling sits ON the route
	# everyone already walks. Cinder and Hallow put theirs on the far side of
	# the map, which is where the errand is meant to cost something.
	# The dog-leg to z = -3 clears the cave stalagmite at (28, 1.2, 3), which the
	# straight line walked into: the probe WALKS, so a prop in the way stops it
	# short of its target and the interaction is refused for being out of range.
	[Vector3(0, 0, 34), Vector3(-5, 0, 25), Vector3(0, 0, 14), Vector3(0, 0, 4),
		Vector3(14, 0, 0), Vector3(24, 0, -2), Vector3(34, 0, -3), Vector3(42, 0, 0)],
	[Vector3(0, 0, 30), Vector3(0, 0, 14), Vector3(0, 0, 4), Vector3(0, 0, -18), Vector3(0, 0, -42)],
]

var role: String = "host"
var port: int = 7700
var address: String = "127.0.0.1"
var display_name: String = "Probe"
var expect_peers: int = 1
var slot: int = 0

var _failures: int = 0
var _scene_root: Node
var _ui_layer: CanvasLayer


func _ready() -> void:
	_parse_args()
	_scene_root = Node.new()
	_scene_root.name = "ProbeSceneRoot"
	add_child(_scene_root)
	_ui_layer = CanvasLayer.new()
	add_child(_ui_layer)
	SceneManager.bind_roots(_scene_root, _ui_layer)
	_run.call_deferred()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := String(arg).split("=", true, 1)
		if parts.size() != 2:
			continue
		var key := parts[0].lstrip("-")
		var value := parts[1]
		match key:
			"role": role = value
			"port": port = value.to_int()
			"address": address = value
			"name": display_name = value
			"peers": expect_peers = value.to_int()
			"slot": slot = value.to_int()


## Neither a pass nor a failure: something that could not be attempted in this
## environment. Kept distinct so a skipped check can never be mistaken for a
## passing one.
func _skip(label: String, detail: String = "") -> void:
	print("NETCHECK SKIP [%s] %s%s" % [
		role, label, "" if detail.is_empty() else "  <- " + detail])


func _report(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("NETCHECK %s [%s] %s%s" % [
		"PASS" if ok else "FAIL", role, label,
		"" if detail.is_empty() else "  <- " + detail])


func _run() -> void:
	match role:
		"host": await _run_host()
		"client": await _run_client()
		"reject": await _run_reject()
		_: _report("unknown role '%s'" % role, false)
	print("NETCHECK DONE %s failures=%d" % [role, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# ==========================================================================
# Host
# ==========================================================================

func _run_host() -> void:
	var result := NetworkManager.host_game(port, display_name, "Probe Session")
	if not _require(bool(result["ok"]), "host starts on port %d" % port, String(result["error"])):
		return
	_report("the host is announcing itself on the network", LanDiscovery.is_announcing(),
		LanDiscovery.session_name())

	var joined: bool = await _until(func() -> bool:
		return LobbyManager.player_count() >= expect_peers + 1, 45.0)
	_report("all %d clients complete the handshake" % expect_peers, joined,
		"roster=%d" % LobbyManager.player_count())
	if not joined:
		return

	# Every peer must appear with a sanitised, non-empty display name.
	var names_ok := true
	for peer_id in LobbyManager.sorted_peer_ids():
		if LobbyManager.display_name_of(int(peer_id)).strip_edges().is_empty():
			names_ok = false
	_report("every peer has a usable display name", names_ok)

	# Linger in the lobby so an over-capacity probe (--role=reject) has a real
	# window to be turned away by the CAPACITY check rather than by the
	# already-started check - they are different code paths.
	await _sleep(14.0)
	_report("the lobby is full at the player cap",
		LobbyManager.player_count() == GameConfig.MAX_PLAYERS
			or expect_peers + 1 < GameConfig.MAX_PLAYERS,
		"roster=%d cap=%d" % [LobbyManager.player_count(), GameConfig.MAX_PLAYERS])

	await GameManager.host_start_session()
	var in_hub: bool = await _until(func() -> bool:
		return SceneManager.current_scene_key == GameConfig.SCENE_SHIP, 45.0)
	_report("the readiness barrier releases and the hub mounts on every peer", in_hub)
	if not in_hub:
		return

	var everyone: bool = await _until(func() -> bool:
		return SpawnManager.all_players().size() >= expect_peers + 1, 30.0)
	_report("a player entity exists for every peer", everyone,
		"players=%d" % SpawnManager.all_players().size())

	_report("joins are refused once the session has started",
		not GameManager.host_accepts_new_players())

	# Dwell in the hub so the clients' host-only-terminal probe is answered
	# while the mission is genuinely still in SHIP_IDLE.
	await _sleep(6.0)
	_report("the hub stayed in SHIP_IDLE despite client terminal requests",
		GameManager.mission_state() == MissionRules.MissionState.SHIP_IDLE,
		MissionRules.state_name(GameManager.mission_state()))

	await GameManager.host_start_expedition()
	var in_nerava: bool = await _until(func() -> bool:
		return SceneManager.current_scene_key == GameConfig.SCENE_NERAVA, 45.0)
	_report("the second barrier releases and Nerava mounts on every peer", in_nerava)
	if not in_nerava:
		return

	# Wait for the clients to run their scripted actions.
	# 90 s, not 45: slot 1's route now detours the length of the grove corridor
	# for the power coupling and back to the cave. The host used to finish its
	# own script and shut the session down while that client was still walking,
	# which failed three of the client's assertions for a reason that had
	# nothing to do with what they were testing.
	var expected := mini(expect_peers, CRYSTAL_FOR_SLOT.size())
	var picked: bool = await _until(func() -> bool:
		return _carried_count() >= expected, 90.0)
	_report("clients picked up %d crystals through host validation" % expected, picked,
		"carried=%d" % _carried_count())

	# Each crystal must be held by exactly one peer and be out of the world.
	var carried: Dictionary = GameManager.snapshot.get("crystals_carried", {})
	var distinct: Dictionary = {}
	var duplicated := false
	for peer_id in carried:
		var cid := String(carried[peer_id])
		if cid == GameConfig.ITEM_COUPLING:
			continue
		if distinct.has(cid):
			duplicated = true
		distinct[cid] = true
		if GameManager.is_crystal_in_world(cid):
			duplicated = true
	_report("no crystal is duplicated or held twice", not duplicated)

	# Give the clients time to finish their hostile-request probes so the host
	# is still alive to reject them.
	var roster_before := LobbyManager.player_count()
	await _sleep(30.0)

	# The mission may legitimately have advanced to ACTIVATE_ALTAR - collecting
	# every crystal is real progress. What must NOT happen is leaving the
	# descent or unlocking anything the clients were not entitled to.
	_report("the host stayed inside the descent throughout the probes",
		MissionRules.is_surface_state(GameManager.mission_state()),
		MissionRules.state_name(GameManager.mission_state()))
	_report("the Star Map stayed locked throughout",
		GameManager.star_map_state() == MissionRules.MAP_LOCKED)
	_report("no pedestal was powered by a client that never placed a crystal",
		GameManager.placed_pedestal_count() == 0)

	# Exactly the flooding client (slot 0) must be gone - the others are still
	# connected at this point, so a wrong number means the host disconnected
	# somebody it should not have, or failed to remove the flooder.
	_report("exactly the flooding peer was removed from the roster",
		LobbyManager.player_count() == roster_before - 1,
		"roster %d -> %d" % [roster_before, LobbyManager.player_count()])
	_report("a disconnected carrier's crystal returns to the world",
		GameManager.is_crystal_in_world(GameConfig.CRYSTAL_RUINS),
		"crystals_in_world=%s" % str(GameManager.snapshot.get("crystals_in_world", [])))
	_report("the mission is still alive after a mid-mission disconnect",
		not GameManager.is_mission_over())

	NetworkManager.shutdown()
	await _sleep(0.5)


## Real CRYSTALS in crew hands. The power coupling shares the same inventory
## slot, so counting the dictionary's size counted the coupling as a crystal and
## let the host's "clients picked up N crystals" pass for the wrong reason.
func _carried_count() -> int:
	var carried: Dictionary = GameManager.snapshot.get("crystals_carried", {})
	var n := 0
	for peer_id in carried:
		if GameConfig.ALL_CRYSTAL_IDS.has(String(carried[peer_id])):
			n += 1
	return n


# ==========================================================================
# Client
# ==========================================================================

func _run_client() -> void:
	# Slot 0 checks LAN discovery before joining. Only one process per machine
	# can hold the discovery port, so the others would fail for an uninteresting
	# reason - and a busy port is a skip, never a pass.
	if slot == 0:
		await _check_lan_discovery()

	var result := NetworkManager.join_game(address, port, display_name)
	if not _require(bool(result["ok"]), "client opens a socket", String(result["error"])):
		return

	var joined: bool = await _until(func() -> bool:
		return LobbyManager.has_player(NetworkManager.local_peer_id()), 45.0)
	_report("the handshake is accepted and the roster replicates", joined)
	if not joined:
		return

	var me := NetworkManager.local_peer_id()
	_report("the client received a real peer id", me > 1, "peer=%d" % me)
	_report("the client knows it is NOT the host", not NetworkManager.is_local_host())

	# --- Hub: a client must not be able to start the expedition. ---
	var in_hub: bool = await _until(func() -> bool:
		return SceneManager.current_scene_key == GameConfig.SCENE_SHIP, 45.0)
	_report("the host-driven transition mounted the hub here", in_hub)
	if not in_hub:
		return

	var mine: bool = await _until(func() -> bool:
		return SpawnManager.player_node(me) != null, 30.0)
	_report("the client's own player entity replicated", mine)

	# Wait for the snapshot to settle first: capturing the state mid-transition
	# would make the perfectly correct SHIP_IDLE that follows look like a change.
	var settled: bool = await _until(func() -> bool:
		return GameManager.mission_state() == MissionRules.MissionState.SHIP_IDLE, 30.0)
	_report("the client sees the mission settle into SHIP_IDLE", settled,
		MissionRules.state_name(GameManager.mission_state()))
	GameManager.request_interact("hub_mission_terminal")
	await _sleep(1.5)
	_report("a client cannot start the expedition through the terminal",
		GameManager.mission_state() == MissionRules.MissionState.SHIP_IDLE,
		MissionRules.state_name(GameManager.mission_state()))

	# --- Nerava ---
	var in_nerava: bool = await _until(func() -> bool:
		return SceneManager.current_scene_key == GameConfig.SCENE_NERAVA, 60.0)
	_report("the client followed the host to Nerava", in_nerava)
	if not in_nerava:
		return

	# NOTE: a GDScript lambda captures by VALUE, so assigning to an outer
	# variable inside the predicate does nothing. Re-fetch after the wait.
	var have: bool = await _until(func() -> bool:
		return SpawnManager.player_node(me) != null, 30.0)
	_report("the client's player respawned on Nerava", have)
	if not have:
		return
	var player: Node = SpawnManager.player_node(me)
	if not _require(player != null, "the client holds a reference to its player"):
		return

	var index := slot % CRYSTAL_FOR_SLOT.size()
	var target: Array = CRYSTAL_FOR_SLOT[index]
	var object_id := String(target[0])
	var crystal_id := String(target[1])
	var route: Array = ROUTE_FOR_SLOT[index]

	# --- Out of range: the host must refuse. ---
	GameManager.request_interact(object_id)
	await _sleep(1.5)
	_report("an out-of-range pickup is refused by the host",
		GameManager.carried_crystal_of(me).is_empty())

	# --- Walk there. The client IS the motion authority for its own player, so
	# this is legitimate movement - and it follows the authored corridors in
	# plausible steps, because the host rejects teleporting (see the anti-cheat
	# probe below) and walls would otherwise displace the character body.
	for i in route.size():
		await _walk_to(SpawnManager.player_node(me), route[i])
		# On the coupling leg, stop and do the errand. Indices rather than
		# positions, so moving a waypoint cannot silently skip the pickup.
		if crystal_id == GameConfig.CRYSTAL_CAVE:
			if i == 1:
				_report("a sealed crystal is refused even in range",
					GameManager.carried_crystal_of(me).is_empty())
				GameManager.request_interact("nerava_power_coupling")
				var lifted: bool = await _until(func() -> bool:
					return GameManager.carried_crystal_of(me) == GameConfig.ITEM_COUPLING, 12.0)
				_report("a client can take the power coupling", lifted,
					"carrying='%s'" % GameManager.carried_crystal_of(me))
			elif i == 6:
				GameManager.request_interact("nerava_coupling_socket")
				var fitted: bool = await _until(func() -> bool:
					return MissionRules.crystal_lock(
						GameManager.snapshot, GameConfig.CRYSTAL_CAVE) == "", 12.0)
				_report("fitting the coupling unseals the crystal for everyone", fitted)
	await _sleep(1.0)

	# Slot 1 is standing at the cave crystal having walked past the coupling and
	# the socket on the way. Its detour work happens inside _walk_route below.
	GameManager.request_interact(object_id)
	var got: bool = await _until(func() -> bool:
		return GameManager.carried_crystal_of(me) == crystal_id, 20.0)
	_report("an in-range pickup is authorised and replicates back", got,
		"carrying='%s'" % GameManager.carried_crystal_of(me))

	# --- Hostile probes. None of these may change anything. ---
	GameManager.request_interact(object_id)
	await _sleep(0.8)
	_report("a repeated pickup does not duplicate the crystal",
		GameManager.carried_crystal_of(me) == crystal_id)

	GameManager.request_interact("object_that_does_not_exist")
	await _sleep(0.8)
	_report("an invented object id is refused",
		GameManager.carried_crystal_of(me) == crystal_id)

	# A forged epoch is exactly what a replayed or crafted packet looks like.
	GameManager._rpc_request_interact.rpc_id(
		GameConfig.HOST_PEER_ID, "nerava_star_map_altar", GameManager.session_epoch + 500)
	await _sleep(0.8)
	_report("a request carrying a forged session epoch is refused",
		GameManager.star_map_state() == MissionRules.MAP_LOCKED)

	# --- Slot 1 only: impossible movement must be corrected by the host. ---
	if slot == 1:
		var legit: Vector3 = (player as Node3D).global_position
		var cheat: Vector3 = legit + Vector3(180, 0, 0)
		player.global_position = cheat
		player.set("sync_position", cheat)
		var snapped: bool = await _until(func() -> bool:
			return SpawnManager.player_node(me) != null \
				and (SpawnManager.player_node(me) as Node3D).global_position.distance_to(cheat) > 20.0,
			12.0)
		_report("the host corrects an impossible 180m teleport", snapped,
			"ended at %s" % str((SpawnManager.player_node(me) as Node3D).global_position.round()))

	# --- Slot 0 only: sustained flooding must get the peer disconnected. ---
	if slot == 0:
		var ended := {"value": false}
		NetworkManager.session_ended.connect(func(_r: String) -> void: ended["value"] = true)
		# Spread across frames: 400 reliable RPCs queued in a single frame can
		# overflow the outgoing ENet queue and never reach the host at all,
		# which would make this test pass for the wrong reason.
		for burst in 12:
			for i in 40:
				GameManager.request_interact("nerava_star_map_altar")
			await get_tree().process_frame
		var kicked: bool = await _until(func() -> bool: return bool(ended["value"]), 20.0)
		_report("sustained request flooding gets the peer disconnected", kicked)
		_report("the flood never unlocked the Star Map",
			GameManager.star_map_state() == MissionRules.MAP_LOCKED)
		await _sleep(1.0)
		return

	# Stay connected past the host's roster check so the only peer missing at
	# that point is the one the host disconnected for flooding.
	await _sleep(60.0)
	NetworkManager.shutdown()
	await _sleep(0.5)


## Proves the host's announcement crosses a process boundary and lands in
## another copy of the game, which is the whole point of the feature.
func _check_lan_discovery() -> void:
	if not LanDiscovery.start_listening():
		_skip("LAN discovery", LanDiscovery.listen_error)
		return

	var seen: Variant = null
	var waited := 0.0
	while waited < 12.0:
		for entry in LanDiscovery.sessions():
			if int((entry as Dictionary)["port"]) == port:
				seen = entry
				break
		if seen != null:
			break
		await get_tree().process_frame
		waited += get_process_delta_time()

	_report("the host's session was discovered on the network", seen != null,
		"after %.1fs" % waited)
	if seen != null:
		var entry: Dictionary = seen
		_report("the discovered session carries a name", String(entry["name"]).length() >= 3,
			String(entry["name"]))
		_report("the discovered session is marked joinable", bool(entry["joinable"]))
		var code := JoinCode.encode(String(entry["address"]), int(entry["port"]))
		var decoded := JoinCode.decode(code)
		_report("a join code round-trips through the discovered address",
			bool(decoded["ok"]) and String(decoded["address"]) == String(entry["address"]),
			code)

	# Hand the port back before joining, so it is not held for the whole session.
	LanDiscovery.stop_listening()


# ==========================================================================
# Reject probe - the player past the cap
# ==========================================================================

func _run_reject() -> void:
	var rejected := {"value": false, "reason": ""}
	NetworkManager.join_failed.connect(func(reason: String) -> void:
		rejected["value"] = true
		rejected["reason"] = reason)

	var result := NetworkManager.join_game(address, port, display_name)
	if not _require(bool(result["ok"]), "the extra client opens a socket", String(result["error"])):
		return

	var done: bool = await _until(func() -> bool:
		return bool(rejected["value"]) or LobbyManager.has_player(NetworkManager.local_peer_id()), 45.0)
	_report("the extra client received a definite answer", done)
	_report("the extra client was turned away rather than silently dropped",
		bool(rejected["value"]), String(rejected["reason"]))
	_report("the rejection message explains why",
		String(rejected["reason"]).length() > 8, String(rejected["reason"]))
	# The reason must name the ACTUAL cause. Being told the mission had started
	# when the lobby is simply full sends the player off to wait for nothing.
	_report("the rejection names the real cause (a full session)",
		String(rejected["reason"]).to_lower().contains("full"), String(rejected["reason"]))
	NetworkManager.shutdown()
	await _sleep(0.5)


# ==========================================================================

func _require(condition: bool, label: String, detail: String = "") -> bool:
	_report(label, condition, detail)
	return condition


## Polls `predicate` until it is true or the timeout expires.
func _until(predicate: Callable, timeout: float) -> bool:
	var waited := 0.0
	while waited < timeout:
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
		waited += get_process_delta_time()
	return false


func _sleep(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Moves a player in steps the host considers plausible.
##
## The host samples position every 0.25s and rejects anything faster than
## (sprint + jump) * dt + 2m. Teleporting straight to the destination is
## therefore treated as cheating - correctly - so the probe covers the ground
## in believable increments, the way a real player walking would.
func _walk_to(player: Node, target: Vector3) -> void:
	if player == null or not is_instance_valid(player):
		return
	var node := player as Node3D
	# Move at roughly sprint speed - the pace a real player travels at, and
	# comfortably inside GameConfig.max_plausible_travel().
	const STEP_SECONDS := 0.1
	var step_limit: float = GameConfig.SPRINT_SPEED * STEP_SECONDS
	var guard := 0
	while node.global_position.distance_to(target) > 0.6 and guard < 900:
		guard += 1
		var next: Vector3 = node.global_position.move_toward(target, step_limit)
		node.global_position = next
		node.set("sync_position", next)
		await get_tree().create_timer(STEP_SECONDS).timeout
		if not is_instance_valid(node):
			return
