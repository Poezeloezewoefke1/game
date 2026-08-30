extends Node
## Owns the ENet peer, the join handshake, and peer lifecycle.
## Autoload name: NetworkManager
##
## RESPONSIBILITY BOUNDARY
##   NetworkManager knows about sockets, peers and the handshake.
##   It does NOT know about missions, crystals or scenes. LobbyManager owns the
##   roster, GameManager owns mission state, SceneManager owns transitions.
##
## THREAT MODEL SUMMARY (full version in docs/NETWORK_RULES.md)
##   * Every client->host RPC is declared `any_peer` and MUST begin with
##     `_reject_unless_host()`. Godot's relay would otherwise let a malicious
##     client invoke a request handler on a peer instead of on the host.
##   * Every host->client RPC is declared `authority` so Godot itself drops it
##     unless it genuinely came from peer 1.
##   * A connected socket is NOT a player. A peer only becomes a player after a
##     successful handshake; unregistered peers are dropped on a timer.

signal hosting_started()
signal host_failed(reason: String)
signal join_started()
signal join_succeeded()
signal join_failed(reason: String)
## Emitted when the local peer is no longer in a session, for any reason.
signal session_ended(reason: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

const REASON_HOST_ENDED := "The host ended the session."
const REASON_LOCAL_LEFT := "You left the session."
const REASON_CONNECT_FAILED := "Could not reach the host."
const REASON_HANDSHAKE_TIMEOUT := "The host did not respond in time."

## Seconds the host gives a freshly connected socket to complete the handshake.
const PENDING_HANDSHAKE_TIMEOUT: float = 8.0

var is_hosting: bool = false
var is_online: bool = false
## Set while a join is in flight so the UI can show a spinner and so a late
## connection_failed cannot be mistaken for a mid-session drop.
var is_joining: bool = false

var local_display_name: String = ""

## peer_id -> seconds remaining before an unregistered peer is dropped (host only).
var _pending_handshake: Dictionary = {}
## Peers already being disconnected. ENet keeps a peer in get_peers() until the
## graceful disconnect completes, so without this a flooding client is kicked
## once per queued request and every follow-up rpc_id() to it fails with
## "Unable to send packet on channel 0".
var _kicking: Dictionary = {}
## peer_id -> seconds until the socket is actually closed.
##
## The disconnect is DELAYED on purpose. RPCs are written to the transport when
## the multiplayer layer flushes at the end of the frame; closing the socket in
## the same frame as `_rpc_reject` throws the rejection message away and the
## rejected player just sees a silent drop. The delay is what turns
## "connection lost" into "the session is full (4/4 players)".
var _pending_kicks: Dictionary = {}

## Seconds between telling a peer why it is being removed and closing its socket.
const KICK_FLUSH_DELAY: float = 0.35
var _join_timer: float = 0.0
var _handshake_timer: float = 0.0
var _awaiting_handshake: bool = false

var _lobby_limiter: RateLimiter


func _ready() -> void:
	_lobby_limiter = RateLimiter.new(
		GameConfig.RATE_LIMIT_LOBBY, GameConfig.RATE_LIMIT_LOBBY,
		GameConfig.RATE_LIMIT_ABUSE_MULTIPLIER, GameConfig.RATE_LIMIT_ABUSE_WINDOW)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	set_process(true)


func _process(delta: float) -> void:
	if is_hosting:
		_tick_pending_handshakes(delta)
		_tick_pending_kicks(delta)
	if is_joining:
		_join_timer -= delta
		if _join_timer <= 0.0:
			_fail_join(REASON_CONNECT_FAILED)
	elif _awaiting_handshake:
		_handshake_timer -= delta
		if _handshake_timer <= 0.0:
			_awaiting_handshake = false
			_fail_join(REASON_HANDSHAKE_TIMEOUT)


# ==========================================================================
# Public API
# ==========================================================================

## Starts a listen server. Returns {ok: bool, error: String}.
func host_game(port: int, display_name: String) -> Dictionary:
	if is_online:
		return {"ok": false, "error": "Already in a session."}
	var safe_port := SettingsManager.sanitize_port(port)
	var peer := ENetMultiplayerPeer.new()
	# Deliberately allow a couple of sockets ABOVE the player cap so that the
	# fifth player receives an explicit, readable rejection instead of ENet
	# silently refusing the connection with no diagnosis. See LOBBY-006.
	var err := peer.create_server(safe_port, GameConfig.MAX_CLIENTS + 2)
	if err != OK:
		var reason := _describe_listen_error(err, safe_port)
		Logx.error("net", "create_server failed: %s" % reason)
		host_failed.emit(reason)
		return {"ok": false, "error": reason}

	multiplayer.multiplayer_peer = peer
	is_hosting = true
	is_online = true
	local_display_name = NameSanitizer.sanitize(display_name, GameConfig.HOST_PEER_ID)
	_pending_handshake.clear()
	_kicking.clear()
	_pending_kicks.clear()
	_lobby_limiter.clear()

	LobbyManager.host_reset()
	LobbyManager.host_add_player(GameConfig.HOST_PEER_ID, local_display_name)
	GameManager.host_begin_lobby()

	Logx.info("net", "Hosting on UDP %d as '%s'" % [safe_port, local_display_name])
	hosting_started.emit()
	return {"ok": true, "error": ""}


## Connects to a host. Returns {ok: bool, error: String} for the *attempt*;
## success or failure of the session itself arrives via signals.
func join_game(address: String, port: int, display_name: String) -> Dictionary:
	if is_online:
		return {"ok": false, "error": "Already in a session."}
	var resolved := resolve_address(address)
	if resolved.is_empty():
		var msg := "'%s' is not a valid address." % address
		join_failed.emit(msg)
		return {"ok": false, "error": msg}

	var safe_port := SettingsManager.sanitize_port(port)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(resolved, safe_port)
	if err != OK:
		var msg2 := "Could not open a client socket (error %d)." % err
		join_failed.emit(msg2)
		return {"ok": false, "error": msg2}

	multiplayer.multiplayer_peer = peer
	is_hosting = false
	is_online = true
	is_joining = true
	_join_timer = GameConfig.CONNECT_TIMEOUT
	local_display_name = display_name
	Logx.info("net", "Joining %s:%d" % [resolved, safe_port])
	join_started.emit()
	return {"ok": true, "error": ""}


## Tears the session down locally. Safe to call when not connected.
func shutdown(reason: String = REASON_LOCAL_LEFT) -> void:
	if not is_online and multiplayer.multiplayer_peer == null:
		return
	Logx.info("net", "Shutting down session: %s" % reason)
	var peer := multiplayer.multiplayer_peer
	if peer != null:
		peer.close()
	multiplayer.multiplayer_peer = null
	is_hosting = false
	is_online = false
	is_joining = false
	_awaiting_handshake = false
	_pending_handshake.clear()
	_kicking.clear()
	_pending_kicks.clear()
	_lobby_limiter.clear()
	LobbyManager.local_clear()
	GameManager.local_teardown()
	SceneManager.local_teardown()
	session_ended.emit(reason)


func local_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()


## True when a targeted RPC to `peer_id` can actually be delivered right now.
##
## Godot raises "Attempt to call RPC with unknown peer ID" if you rpc_id() a
## peer that has already gone. That window is REAL: the host keeps running
## gameplay for a frame or two between the socket dropping and
## peer_disconnected being processed, and every feedback RPC aimed at the
## departing player lands in it. Guard host->specific-peer sends with this.
func is_peer_connected(peer_id: int) -> bool:
	if multiplayer.multiplayer_peer == null:
		return false
	if _kicking.has(peer_id):
		return false
	if peer_id == GameConfig.HOST_PEER_ID:
		return is_online
	if peer_id == multiplayer.get_unique_id():
		return true
	return multiplayer.get_peers().has(peer_id)


func is_local_host() -> bool:
	return is_online and multiplayer.multiplayer_peer != null and multiplayer.is_server()


## Peers currently connected (host only). Excludes the host itself.
func connected_client_ids() -> PackedInt32Array:
	if multiplayer.multiplayer_peer == null:
		return PackedInt32Array()
	return multiplayer.get_peers()


## Every peer that should be considered part of the session, host included.
func session_peer_ids() -> PackedInt32Array:
	var ids := PackedInt32Array()
	if not is_online:
		return ids
	ids.append(GameConfig.HOST_PEER_ID)
	for p in multiplayer.get_peers():
		if p != GameConfig.HOST_PEER_ID:
			ids.append(p)
	return ids


## Accepts a dotted IPv4/IPv6 literal or a resolvable hostname.
## Returns "" when the input cannot be used.
static func resolve_address(address: String) -> String:
	var a := address.strip_edges()
	if a.is_empty():
		return ""
	# Reject anything with whitespace or control characters outright.
	for i in a.length():
		var c := a.unicode_at(i)
		if c <= 0x20 or c == 0x7F:
			return ""
	if a.is_valid_ip_address():
		return a
	var resolved := IP.resolve_hostname(a, IP.TYPE_ANY)
	if resolved.is_valid_ip_address():
		return resolved
	return ""


# ==========================================================================
# Host: connection lifecycle
# ==========================================================================

func _on_peer_connected(peer_id: int) -> void:
	if not is_hosting:
		# Clients also receive peer_connected for the server (id 1) and, with
		# relay on, for other clients. Nothing to do on the client side.
		return
	Logx.info("net", "Socket connected: %d (awaiting handshake)" % peer_id)
	_pending_handshake[peer_id] = PENDING_HANDSHAKE_TIMEOUT


func _on_peer_disconnected(peer_id: int) -> void:
	_pending_handshake.erase(peer_id)
	_kicking.erase(peer_id)
	_pending_kicks.erase(peer_id)
	if not is_hosting:
		return
	Logx.info("net", "Peer disconnected: %d" % peer_id)
	_lobby_limiter.forget(peer_id)
	# Order matters: gameplay resolution first (drops carried items, retargets
	# the Sentinel, releases revives), then roster removal, then scene barrier.
	GameManager.host_handle_peer_left(peer_id)
	SceneManager.host_handle_peer_left(peer_id)
	LobbyManager.host_remove_player(peer_id)
	peer_left.emit(peer_id)


func _tick_pending_handshakes(delta: float) -> void:
	if _pending_handshake.is_empty():
		return
	var expired: Array = []
	for peer_id in _pending_handshake:
		var remaining: float = float(_pending_handshake[peer_id]) - delta
		if remaining <= 0.0:
			expired.append(peer_id)
		else:
			_pending_handshake[peer_id] = remaining
	for peer_id in expired:
		_pending_handshake.erase(peer_id)
		Logx.reject("net", peer_id, "handshake_timeout")
		_kick(peer_id)


## Schedules a graceful disconnect. See _pending_kicks for why it is not
## immediate.
func _kick(peer_id: int) -> void:
	_pending_kicks[peer_id] = KICK_FLUSH_DELAY


func _tick_pending_kicks(delta: float) -> void:
	if _pending_kicks.is_empty():
		return
	var due: Array = []
	for peer_id in _pending_kicks:
		var remaining: float = float(_pending_kicks[peer_id]) - delta
		if remaining <= 0.0:
			due.append(peer_id)
		else:
			_pending_kicks[peer_id] = remaining
	for peer_id in due:
		_pending_kicks.erase(peer_id)
		var peer := multiplayer.multiplayer_peer
		if peer is ENetMultiplayerPeer:
			# `false` = graceful, so anything still queued is flushed.
			(peer as ENetMultiplayerPeer).disconnect_peer(int(peer_id), false)


## Called by other host-side systems when a peer misbehaves badly enough that
## throttling is not sufficient. Idempotent: repeat calls for a peer already on
## its way out are ignored.
func host_kick_peer(peer_id: int, reason: String) -> void:
	if not is_local_host():
		return
	if _kicking.has(peer_id):
		return
	_kicking[peer_id] = true
	Logx.reject("net", peer_id, "kicked:" + reason)
	if is_peer_connected(peer_id):
		_rpc_reject.rpc_id(peer_id, reason)
	_kick(peer_id)


## True once a peer has been told to leave. Every host-side request handler
## treats such a peer as already gone.
func is_peer_leaving(peer_id: int) -> bool:
	return _kicking.has(peer_id)


# ==========================================================================
# Handshake
# ==========================================================================

func _on_connected_to_server() -> void:
	is_joining = false
	_awaiting_handshake = true
	_handshake_timer = GameConfig.HANDSHAKE_TIMEOUT
	Logx.info("net", "Socket established; registering")
	_rpc_register.rpc_id(GameConfig.HOST_PEER_ID, GameConfig.PROTOCOL_VERSION, local_display_name)


## CLIENT -> HOST. Declared `any_peer` because clients must be able to call it;
## the first line therefore has to prove we are the host.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_register(protocol_version: int, raw_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	if not _pending_handshake.has(sender):
		# Either a duplicate registration or a peer trying to re-register to
		# rename itself / take a second slot.
		Logx.reject("net", sender, "register_not_pending")
		return
	if not _lobby_limiter.allow(sender):
		Logx.reject("net", sender, "register_rate_limited")
		return
	_pending_handshake.erase(sender)

	if protocol_version != GameConfig.PROTOCOL_VERSION:
		_reject_peer(sender, "Version mismatch: host runs protocol %d, you run %d." % [
			GameConfig.PROTOCOL_VERSION, protocol_version])
		return
	# Order matters for the MESSAGE, not just the outcome. Checking a combined
	# "accepts new players" predicate first would tell a player arriving at a
	# full lobby that the mission had already started, which is both wrong and
	# unactionable - they would wait instead of asking for a slot.
	if not GameManager.host_is_in_lobby():
		_reject_peer(sender, "The host has already started the mission.")
		return
	if LobbyManager.player_count() >= GameConfig.MAX_PLAYERS:
		_reject_peer(sender, "The session is full (%d/%d players)." % [
			LobbyManager.player_count(), GameConfig.MAX_PLAYERS])
		return

	var safe_name := NameSanitizer.sanitize(raw_name, sender)
	LobbyManager.host_add_player(sender, safe_name)
	Logx.info("net", "Peer %d registered as '%s'" % [sender, safe_name])
	if not is_peer_connected(sender):
		Logx.reject("net", sender, "vanished_before_accept")
		LobbyManager.host_remove_player(sender)
		return
	_rpc_accept.rpc_id(sender, safe_name)
	LobbyManager.host_broadcast_roster()
	peer_joined.emit(sender)


func _reject_peer(peer_id: int, reason: String) -> void:
	Logx.reject("net", peer_id, reason)
	if is_peer_connected(peer_id):
		_rpc_reject.rpc_id(peer_id, reason)
	_kick(peer_id)


## HOST -> CLIENT.
@rpc("authority", "call_remote", "reliable")
func _rpc_accept(assigned_name: String) -> void:
	_awaiting_handshake = false
	local_display_name = assigned_name
	Logx.info("net", "Join accepted as '%s'" % assigned_name)
	join_succeeded.emit()


## HOST -> CLIENT.
@rpc("authority", "call_remote", "reliable")
func _rpc_reject(reason: String) -> void:
	_awaiting_handshake = false
	Logx.warn("net", "Join rejected: %s" % reason)
	_fail_join(reason)


func _on_connection_failed() -> void:
	_fail_join(REASON_CONNECT_FAILED)


func _on_server_disconnected() -> void:
	# Host migration is explicitly NOT supported. Every client returns to the
	# menu with a clear message and the in-progress session is discarded.
	Logx.warn("net", "Host disconnected")
	shutdown(REASON_HOST_ENDED)


func _fail_join(reason: String) -> void:
	if not is_online and not is_joining:
		join_failed.emit(reason)
		return
	is_joining = false
	_awaiting_handshake = false
	var peer := multiplayer.multiplayer_peer
	if peer != null:
		peer.close()
	multiplayer.multiplayer_peer = null
	is_online = false
	is_hosting = false
	LobbyManager.local_clear()
	GameManager.local_teardown()
	SceneManager.local_teardown()
	join_failed.emit(reason)


static func _describe_listen_error(err: int, port: int) -> String:
	match err:
		ERR_ALREADY_IN_USE:
			return "UDP port %d is already in use. Close the other copy or pick another port." % port
		ERR_CANT_CREATE:
			return "Could not bind UDP port %d. A firewall may be blocking it." % port
		_:
			return "Could not start the server on port %d (error %d)." % [port, err]
