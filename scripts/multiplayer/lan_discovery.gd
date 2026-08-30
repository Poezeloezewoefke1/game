extends Node
## Local-network session browser. Autoload name: LanDiscovery
##
## The host broadcasts a small announcement once a second; clients on the same
## network listen and build a list. Nobody types an address, and there is no
## server anywhere - it is a UDP broadcast and a dictionary with a timeout.
##
## SCOPE, STATED HONESTLY
##   This works on a local network. Broadcasts do not cross routers, so it does
##   nothing for playing over the internet - that still needs an address (or a
##   join code, which is the same thing in fewer characters) and a forwarded
##   port. See docs/NETWORK_RULES.md.
##
## THE PAYLOAD IS UNTRUSTED
##   Anyone on the network can send one of these packets, including one that
##   points at an address they chose. That is why the payload is a plain
##   delimited string parsed field by field rather than a serialised Variant:
##   there is no deserialisation step to attack. The host's address is taken
##   from the UDP source address, never from the packet body, so an announcement
##   cannot claim to come from somewhere it did not.

signal sessions_changed()

## Bumped if the announcement layout ever changes, independently of the game's
## PROTOCOL_VERSION - a browser should still be able to show, and grey out, a
## session running a game build it cannot join.
const DISCOVERY_FORMAT: int = 1
const MAGIC: String = "SBSL"

var _announcer: PacketPeerUDP = null
var _listener: PacketPeerUDP = null

## "ip:port" -> Dictionary(session entry)
var _sessions: Dictionary = {}
var _announce_countdown: float = 0.0

var _session_name: String = ""
var _game_port: int = GameConfig.DEFAULT_PORT

## Set when the listen socket could not be opened - almost always a second copy
## of the game already listening on this machine. The UI explains that rather
## than silently showing an empty list.
var listen_error: String = ""


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if _announcer != null:
		_announce_countdown -= delta
		if _announce_countdown <= 0.0:
			_announce_countdown = GameConfig.DISCOVERY_ANNOUNCE_INTERVAL
			_broadcast()
	if _listener != null:
		_drain()
	if not _sessions.is_empty():
		_expire()


# ==========================================================================
# Host side
# ==========================================================================

func host_start_announcing(session_name: String, game_port: int) -> void:
	_session_name = sanitize_session_name(session_name)
	_game_port = game_port
	if _announcer == null:
		_announcer = PacketPeerUDP.new()
		_announcer.set_broadcast_enabled(true)
		var err := _announcer.set_dest_address("255.255.255.255", GameConfig.DISCOVERY_PORT)
		if err != OK:
			Logx.warn("discovery", "Could not set broadcast address (%d); LAN browsing is off" % err)
			_announcer = null
			return
	_announce_countdown = 0.0
	Logx.info("discovery", "Announcing '%s' on UDP %d" % [_session_name, GameConfig.DISCOVERY_PORT])


func host_stop_announcing() -> void:
	if _announcer == null:
		return
	_announcer.close()
	_announcer = null
	Logx.info("discovery", "Stopped announcing")


func is_announcing() -> bool:
	return _announcer != null


func session_name() -> String:
	return _session_name


func _broadcast() -> void:
	if _announcer == null:
		return
	# Field order matters: host_name is LAST so that any separator surviving in
	# a display name lands in the final field instead of shifting the others.
	var accepting := 1 if GameManager.host_accepts_new_players() else 0
	var payload := "%s|%d|%d|%d|%d|%d|%s|%s" % [
		MAGIC,
		DISCOVERY_FORMAT,
		GameConfig.PROTOCOL_VERSION,
		_game_port,
		LobbyManager.player_count(),
		accepting,
		_session_name,
		LobbyManager.display_name_of(GameConfig.HOST_PEER_ID),
	]
	_announcer.put_packet(payload.to_utf8_buffer())


# ==========================================================================
# Client side
# ==========================================================================

## Returns true when the browser is live. False means another program (usually a
## second copy of this game) already holds the port; `listen_error` says so.
func start_listening() -> bool:
	if _listener != null:
		return true
	var socket := PacketPeerUDP.new()
	var err := socket.bind(GameConfig.DISCOVERY_PORT, "*")
	if err != OK:
		listen_error = "Another program on this computer is already using UDP %d, so the session list is unavailable. Joining by code or address still works." % GameConfig.DISCOVERY_PORT
		Logx.warn("discovery", "bind failed (%d)" % err)
		return false
	listen_error = ""
	_listener = socket
	Logx.info("discovery", "Listening on UDP %d" % GameConfig.DISCOVERY_PORT)
	return true


func stop_listening() -> void:
	if _listener != null:
		_listener.close()
		_listener = null
	if not _sessions.is_empty():
		_sessions.clear()
		sessions_changed.emit()


func is_listening() -> bool:
	return _listener != null


## Fresh sessions, ordered so the list does not reshuffle under the cursor.
func sessions() -> Array:
	var out: Array = _sessions.values()
	out.sort_custom(func(a, b): return String(a["name"]) + String(a["key"]) < String(b["name"]) + String(b["key"]))
	return out


func _drain() -> void:
	var changed := false
	while _listener != null and _listener.get_available_packet_count() > 0:
		var raw := _listener.get_packet()
		var from_ip := _listener.get_packet_ip()
		if raw.size() == 0 or raw.size() > GameConfig.DISCOVERY_MAX_PACKET_BYTES:
			continue
		if _absorb(raw.get_string_from_utf8(), from_ip):
			changed = true
	if changed:
		sessions_changed.emit()


## Returns true when the browser changed. Every field is validated; a packet
## that is not exactly what we expect is dropped without comment, because on an
## open network most malformed packets are somebody else's protocol, not an
## attack worth logging on every frame.
func _absorb(text: String, from_ip: String) -> bool:
	if not text.begins_with(MAGIC + "|"):
		return false
	# maxsplit keeps stray separators inside the final field.
	var parts := text.split("|", true, 7)
	if parts.size() != 8:
		return false
	if parts[1].to_int() != DISCOVERY_FORMAT:
		return false
	if from_ip.is_empty() or JoinCode.ipv4_to_int(from_ip) < 0:
		return false

	var game_port := parts[3].to_int()
	if game_port < GameConfig.MIN_PORT or game_port > GameConfig.MAX_PORT:
		return false

	var key := "%s:%d" % [from_ip, game_port]
	if not _sessions.has(key) and _sessions.size() >= GameConfig.DISCOVERY_MAX_SESSIONS:
		return false

	var entry := {
		"key": key,
		"address": from_ip,
		"port": game_port,
		"protocol": parts[2].to_int(),
		"players": clampi(parts[4].to_int(), 0, GameConfig.MAX_PLAYERS),
		"accepting": parts[5].to_int() == 1,
		"name": sanitize_session_name(parts[6]),
		"host_name": NameSanitizer.sanitize(parts[7], 1),
		"last_seen": Time.get_ticks_msec(),
	}
	entry["compatible"] = int(entry["protocol"]) == GameConfig.PROTOCOL_VERSION
	entry["joinable"] = bool(entry["accepting"]) \
		and bool(entry["compatible"]) \
		and int(entry["players"]) < GameConfig.MAX_PLAYERS

	var previous: Variant = _sessions.get(key)
	_sessions[key] = entry
	# Only report a change when something a player can see actually changed;
	# otherwise the list would rebuild once a second per host.
	if previous == null:
		return true
	var before: Dictionary = previous
	for field in ["name", "host_name", "players", "accepting", "joinable", "compatible"]:
		if before[field] != entry[field]:
			return true
	return false


func _expire() -> void:
	var now := Time.get_ticks_msec()
	var cutoff := int(GameConfig.DISCOVERY_ENTRY_TIMEOUT * 1000.0)
	var stale: Array = []
	for key in _sessions:
		if now - int((_sessions[key] as Dictionary)["last_seen"]) > cutoff:
			stale.append(key)
	if stale.is_empty():
		return
	for key in stale:
		_sessions.erase(key)
	sessions_changed.emit()


# ==========================================================================

## Session names are broadcast and rendered, so they get the same treatment as
## display names plus removal of the field separator.
static func sanitize_session_name(raw: String) -> String:
	var stripped := raw.replace("|", " ")
	var out := ""
	var previous_space := false
	for i in stripped.length():
		var c := stripped.unicode_at(i)
		if c <= 0x1F or c == 0x7F:
			continue
		if c == 0x20 or c == 0x09:
			if out.is_empty() or previous_space:
				continue
			previous_space = true
			out += " "
			continue
		previous_space = false
		out += String.chr(c)
		if out.length() >= GameConfig.SESSION_NAME_MAX_LENGTH:
			break
	out = out.strip_edges()
	if out.length() < GameConfig.SESSION_NAME_MIN_LENGTH:
		return GameConfig.SESSION_NAME_FALLBACK
	return out


func local_teardown() -> void:
	host_stop_announcing()
	stop_listening()
