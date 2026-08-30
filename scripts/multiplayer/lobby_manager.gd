extends Node
## Authoritative player roster. Autoload name: LobbyManager
##
## The host owns the roster. Clients hold a read-only mirror that is replaced
## wholesale by `_rpc_roster`, so a client can never end up with a roster the
## host does not agree with.
##
## Display names are presentation only - identity is always the peer id.

signal roster_changed()
signal local_ready_changed(is_ready: bool)

## peer_id -> {"name": String, "ready": bool}
var players: Dictionary = {}

var _ready_limiter: RateLimiter


func _ready() -> void:
	_ready_limiter = RateLimiter.new(
		GameConfig.RATE_LIMIT_LOBBY, GameConfig.RATE_LIMIT_LOBBY,
		GameConfig.RATE_LIMIT_ABUSE_MULTIPLIER, GameConfig.RATE_LIMIT_ABUSE_WINDOW)


# ==========================================================================
# Queries (safe on host and client)
# ==========================================================================

func player_count() -> int:
	return players.size()


func has_player(peer_id: int) -> bool:
	return players.has(peer_id)


func display_name_of(peer_id: int) -> String:
	var entry: Variant = players.get(peer_id)
	if entry == null:
		return NameSanitizer.fallback_name(peer_id)
	return String((entry as Dictionary).get("name", NameSanitizer.fallback_name(peer_id)))


func is_ready(peer_id: int) -> bool:
	var entry: Variant = players.get(peer_id)
	if entry == null:
		return false
	return bool((entry as Dictionary).get("ready", false))


func is_host_peer(peer_id: int) -> bool:
	return peer_id == GameConfig.HOST_PEER_ID


## Peer ids sorted so every client renders the lobby list in the same order.
func sorted_peer_ids() -> Array:
	var ids: Array = players.keys()
	ids.sort()
	return ids


func is_full() -> bool:
	return players.size() >= GameConfig.MAX_PLAYERS


# ==========================================================================
# Host mutations
# ==========================================================================

func host_reset() -> void:
	players.clear()
	if _ready_limiter != null:
		_ready_limiter.clear()
	roster_changed.emit()


func host_add_player(peer_id: int, display_name: String) -> void:
	if not _assert_host("host_add_player"):
		return
	if players.has(peer_id):
		Logx.warn("lobby", "Duplicate add for peer %d ignored" % peer_id)
		return
	if players.size() >= GameConfig.MAX_PLAYERS:
		Logx.warn("lobby", "Roster full; refusing peer %d" % peer_id)
		return
	players[peer_id] = {
		"name": NameSanitizer.sanitize(display_name, peer_id),
		"ready": false,
	}
	roster_changed.emit()


func host_remove_player(peer_id: int) -> void:
	if not _assert_host("host_remove_player"):
		return
	if not players.erase(peer_id):
		return
	if _ready_limiter != null:
		_ready_limiter.forget(peer_id)
	roster_changed.emit()
	host_broadcast_roster()


func host_set_ready(peer_id: int, value: bool) -> void:
	if not _assert_host("host_set_ready"):
		return
	if not players.has(peer_id):
		return
	(players[peer_id] as Dictionary)["ready"] = value
	roster_changed.emit()
	host_broadcast_roster()


## Clears every ready flag - used when a mission ends and everyone returns to
## the lobby, so a stale ready from the previous session cannot leak forward.
func host_clear_ready_flags() -> void:
	if not _assert_host("host_clear_ready_flags"):
		return
	for peer_id in players:
		(players[peer_id] as Dictionary)["ready"] = false
	roster_changed.emit()
	host_broadcast_roster()


func host_broadcast_roster() -> void:
	if not _assert_host("host_broadcast_roster"):
		return
	if multiplayer.multiplayer_peer == null:
		return
	_rpc_roster.rpc(_serialize())


# ==========================================================================
# Local (non-authoritative) teardown
# ==========================================================================

func local_clear() -> void:
	players.clear()
	if _ready_limiter != null:
		_ready_limiter.clear()
	roster_changed.emit()


# ==========================================================================
# Client requests
# ==========================================================================

## Called locally by the lobby UI on a client (or on the host for itself).
func request_toggle_ready() -> void:
	var me := NetworkManager.local_peer_id()
	if me == 0:
		return
	var desired := not is_ready(me)
	if multiplayer.is_server():
		host_set_ready(me, desired)
	else:
		_rpc_request_ready.rpc_id(GameConfig.HOST_PEER_ID, desired)
	local_ready_changed.emit(desired)


## CLIENT -> HOST.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_ready(value: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender > 0 and NetworkManager.is_peer_leaving(sender):
		return
	if sender <= 0 or not players.has(sender):
		Logx.reject("lobby", sender, "ready_unknown_peer")
		return
	if not _ready_limiter.allow(sender):
		Logx.reject("lobby", sender, "ready_rate_limited")
		if _ready_limiter.is_abusive(sender):
			NetworkManager.host_kick_peer(sender, "Too many lobby requests.")
		return
	if not GameManager.host_accepts_lobby_input():
		Logx.reject("lobby", sender, "ready_wrong_state")
		return
	host_set_ready(sender, value)


# ==========================================================================
# Replication
# ==========================================================================

## Serialised as a flat array so the payload stays small and order-stable.
## [[peer_id, name, ready], ...]
func _serialize() -> Array:
	var out: Array = []
	for peer_id in sorted_peer_ids():
		var e: Dictionary = players[peer_id]
		out.append([int(peer_id), String(e["name"]), bool(e["ready"])])
	return out


## HOST -> CLIENT. Replaces the mirror wholesale.
@rpc("authority", "call_remote", "reliable")
func _rpc_roster(data: Array) -> void:
	if multiplayer.is_server():
		return
	var rebuilt: Dictionary = {}
	for row in data:
		if typeof(row) != TYPE_ARRAY or (row as Array).size() != 3:
			continue
		var r: Array = row
		var peer_id := int(r[0])
		if peer_id <= 0:
			continue
		rebuilt[peer_id] = {
			"name": NameSanitizer.sanitize(String(r[1]), peer_id),
			"ready": bool(r[2]),
		}
	players = rebuilt
	roster_changed.emit()


func _assert_host(where: String) -> bool:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		Logx.error("lobby", "%s called on a client" % where)
		return false
	return true
