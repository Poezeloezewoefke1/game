extends TestCase
## LAN session discovery.
##
## Runs in one process: the announcer broadcasts and the listener binds the same
## port, so the packets loop back exactly as they would between two machines on
## a switch. That is enough to exercise the real socket path rather than a mock.
##
## The adversarial half matters more than the happy path here. Discovery packets
## are an unauthenticated broadcast - anything on the network can send one - so
## the parser is the attack surface, and a browser that can be flooded or fed
## nonsense is a real problem even on a home LAN.

const SESSION_NAME := "Star Battle"
const GAME_PORT := 7000

var _injector: PacketPeerUDP = null


func is_async() -> bool:
	return true


func before_all() -> void:
	# Another suite or the scene phase may still hold the socket.
	LanDiscovery.local_teardown()


func after_all() -> void:
	LanDiscovery.local_teardown()
	if _injector != null:
		_injector.close()
		_injector = null


func run_async() -> void:
	if not check(LanDiscovery.start_listening(),
			"the browser can bind UDP %d (%s)" % [GameConfig.DISCOVERY_PORT, LanDiscovery.listen_error]):
		return

	_injector = PacketPeerUDP.new()
	_injector.set_dest_address("127.0.0.1", GameConfig.DISCOVERY_PORT)

	await _test_announcement_is_discovered()
	await _test_malformed_packets_are_ignored()
	await _test_trailing_separators_are_absorbed()
	await _test_the_browser_cannot_be_flooded()
	await _test_entries_expire()

	LanDiscovery.local_teardown()
	await tree.process_frame


# --------------------------------------------------------------------------

func _test_announcement_is_discovered() -> void:
	set_current("discovery")
	check_eq(LanDiscovery.sessions().size(), 0, "the browser starts empty")

	LanDiscovery.host_start_announcing(SESSION_NAME, GAME_PORT)
	check(LanDiscovery.is_announcing(), "the host is announcing")

	var found: Variant = await _await_session(SESSION_NAME, 6.0)
	if not check(found != null, "the announced session appears in the browser"):
		return

	var entry: Dictionary = found
	check_eq(String(entry["name"]), SESSION_NAME, "the session name arrives intact")
	check_eq(int(entry["port"]), GAME_PORT, "the game port arrives intact")
	check(JoinCode.ipv4_to_int(String(entry["address"])) >= 0,
		"the address is a usable IPv4 (%s)" % entry["address"])
	check(bool(entry["compatible"]), "a session from this build is marked compatible")
	check(bool(entry["joinable"]), "an empty lobby is joinable")
	check_ne(String(entry["host_name"]), "", "the host's display name arrives")

	# A code built from the discovered address must round-trip, so a player can
	# read the code off one machine and type it into another.
	var code := JoinCode.encode(String(entry["address"]), int(entry["port"]))
	check_ne(code, "", "a join code can be built from a discovered session")
	var decoded := JoinCode.decode(code)
	check_eq(String(decoded["address"]), String(entry["address"]),
		"that code points back at the same host")


func _test_malformed_packets_are_ignored() -> void:
	set_current("malformed packets")
	var before := LanDiscovery.sessions().size()

	var junk := [
		"",                                            # empty
		"not even close",                              # no magic
		"SBSL",                                        # magic only
		"SBSL|1|1|7000",                               # too few fields
		"SBSL|99|1|7000|0|1|Name|Host",                # unknown format version
		"SBSL|1|1|0|0|1|Name|Host",                    # port below the minimum
		"SBSL|1|1|99999|0|1|Name|Host",                # port above the maximum
		"SBSL|1|1|notaport|0|1|Name|Host",             # non-numeric port
	]
	for payload in junk:
		_injector.put_packet(String(payload).to_utf8_buffer())
	# A packet past the size cap must be dropped unread.
	_injector.put_packet(("SBSL|1|1|7000|0|1|" + "A".repeat(GameConfig.DISCOVERY_MAX_PACKET_BYTES) + "|Host").to_utf8_buffer())

	await wait_seconds(0.5)
	check_eq(LanDiscovery.sessions().size(), before,
		"no malformed packet created a browser entry")


func _test_trailing_separators_are_absorbed() -> void:
	set_current("field shifting")
	# The host's DISPLAY name is not stripped of the field separator, so a
	# player called "Bo|b" would otherwise shift every field after theirs and
	# corrupt the port and player count. The name is sent last and parsed with a
	# split limit so anything stray lands harmlessly in it.
	_injector.put_packet(("SBSL|1|%d|7100|2|1|Shifted Session|Bo|b|extra" % [
		GameConfig.PROTOCOL_VERSION]).to_utf8_buffer())
	await wait_seconds(0.5)

	var entry: Variant = _find_session("Shifted Session")
	if not check(entry != null, "a name containing separators still produces an entry"):
		return
	var found: Dictionary = entry
	check_eq(int(found["port"]), 7100, "the port was not shifted by the extra separators")
	check_eq(int(found["players"]), 2, "the player count was not shifted")
	check_eq(String(found["name"]), "Shifted Session", "the session name was not shifted")
	check(String(found["host_name"]).begins_with("Bo"),
		"the stray separators stayed inside the host name (%s)" % found["host_name"])


func _test_the_browser_cannot_be_flooded() -> void:
	set_current("flood")
	# Every injected packet shares a source address, so the game port is what
	# makes the keys distinct - which is exactly how a hostile peer would try to
	# grow the list without bound.
	for i in GameConfig.DISCOVERY_MAX_SESSIONS * 2:
		var port := 20000 + i
		_injector.put_packet(("SBSL|1|%d|%d|0|1|Flood %d|Attacker" % [
			GameConfig.PROTOCOL_VERSION, port, i]).to_utf8_buffer())
	await wait_seconds(0.6)

	check(LanDiscovery.sessions().size() <= GameConfig.DISCOVERY_MAX_SESSIONS,
		"the browser is capped at %d entries (got %d)" % [
			GameConfig.DISCOVERY_MAX_SESSIONS, LanDiscovery.sessions().size()])

	# The address must come from the UDP source, never from the packet body -
	# otherwise an announcement could point players at a host of its choosing.
	for entry in LanDiscovery.sessions():
		if String(entry["host_name"]) == "Attacker":
			check_eq(String(entry["address"]), "127.0.0.1",
				"an injected announcement is attributed to its real sender")
			break


func _test_entries_expire() -> void:
	set_current("expiry")
	LanDiscovery.host_stop_announcing()
	check_false(LanDiscovery.is_announcing(), "the host stopped announcing")

	# Measure the CLOCK, not a sum of frame deltas. Godot clamps the reported
	# delta when a frame runs long, so under load the sum drifts behind real
	# time - and this assertion is about real time. It failed three times in one
	# session, always while other work was running, always passing on the
	# immediate re-run, and each time it cost someone the trouble of proving it
	# had nothing to do with what they had changed. A test that measures the
	# wrong thing is worse than no test: it spends attention and returns noise.
	var gone := false
	var started := Time.get_ticks_msec()
	var waited := 0.0
	var limit: float = GameConfig.DISCOVERY_ENTRY_TIMEOUT + 3.0
	while waited < limit:
		await tree.process_frame
		waited = float(Time.get_ticks_msec() - started) / 1000.0
		if _find_session(SESSION_NAME) == null:
			gone = true
			break
	check(gone, "a host that stops announcing drops out of the browser (after %.1fs)" % waited)
	check(waited >= GameConfig.DISCOVERY_ENTRY_TIMEOUT - 1.0,
		"it stays listed for roughly the configured timeout rather than flickering")


# --------------------------------------------------------------------------

func _await_session(name: String, timeout: float) -> Variant:
	# Clock, not summed deltas - see _test_entries_expire.
	var started := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - started) / 1000.0 < timeout:
		var entry: Variant = _find_session(name)
		if entry != null:
			return entry
		await tree.process_frame
	return null


func _find_session(name: String) -> Variant:
	for entry in LanDiscovery.sessions():
		if String((entry as Dictionary)["name"]) == name:
			return entry
	return null
