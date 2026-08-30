extends Node
## Lightweight levelled logger. Autoload name: Logx
##
## Why not print() everywhere: CI needs to grep for failures, and multiplayer
## bugs are impossible to read without knowing which peer emitted a line.
## Every line is prefixed with the local peer role and id.

enum Level { DEBUG, INFO, WARN, ERROR }

## Lines below this level are dropped. Raised to WARN in release builds unless
## the --verbose-game command line flag is present.
var min_level: Level = Level.INFO

## When true, lines are also appended to _history for in-game/network diagnostics.
var keep_history: bool = true
const HISTORY_LIMIT: int = 400

var _history: PackedStringArray = PackedStringArray()


func _ready() -> void:
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	if args.has("--verbose-game"):
		min_level = Level.DEBUG
	elif not OS.is_debug_build():
		min_level = Level.WARN


func _role_tag() -> String:
	var mp := multiplayer
	if mp == null or mp.multiplayer_peer == null:
		return "OFFLINE"
	if mp.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return "CONNECTING"
	return ("HOST" if mp.is_server() else "CLIENT") + ":" + str(mp.get_unique_id())


func _emit(level: Level, category: String, message: String) -> void:
	if level < min_level:
		return
	var names := ["DBG", "INF", "WRN", "ERR"]
	var line := "[%s][%s][%s] %s" % [names[level], _role_tag(), category, message]
	if keep_history:
		_history.append(line)
		if _history.size() > HISTORY_LIMIT:
			_history.remove_at(0)
	if level >= Level.WARN:
		printerr(line)
	else:
		print(line)


func debug(category: String, message: String) -> void:
	_emit(Level.DEBUG, category, message)


func info(category: String, message: String) -> void:
	_emit(Level.INFO, category, message)


func warn(category: String, message: String) -> void:
	_emit(Level.WARN, category, message)


func error(category: String, message: String) -> void:
	_emit(Level.ERROR, category, message)


## A rejected client request. Deliberately its own call so that security review
## and CI log scraping can find every rejection path in one grep.
func reject(category: String, peer_id: int, reason: String) -> void:
	_emit(Level.WARN, category, "REJECTED peer=%d reason=%s" % [peer_id, reason])


func history() -> PackedStringArray:
	return _history.duplicate()


func clear_history() -> void:
	_history.clear()
