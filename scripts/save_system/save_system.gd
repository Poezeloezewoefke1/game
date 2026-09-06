extends Node
## Autoload: SaveSystem. Persistent progression + settings in user://save.json.

const SAVE_PATH := "user://save.json"
const VERSION := 1

var data: Dictionary = {}

func _ready() -> void:
	load_game()

func default_data() -> Dictionary:
	return {
		"version": VERSION,
		"xp_bottles": 0,                      # meta currency (between-map progression)
		"unlocked_heroes": ["wemmbu", "flamefrags", "parrotx2", "spokeishere"],
		"hero_meta": {},                      # hero id -> {"level": int, "xp": int, "runs": int, "wins": int}
		"unlocked_towers": [],                # empty = all starter towers available
		"maps": {},                           # map id -> {"completed": bool, "best_waves": int, "wins": int, "attempts": int, "stars": int}
		"codex_unlocked": [],
		"settings": {
			"master_volume": 1.0, "music_volume": 0.7, "sfx_volume": 0.9,
			"fullscreen": false, "graphics_quality": 2, "shadows": true, "vsync": true,
			"show_damage_numbers": true, "camera_edge_pan": true,
		},
		"stats": {"total_kills": 0, "total_runs": 0, "total_wins": 0, "boss_kills": 0},
	}

func load_game() -> void:
	data = default_data()
	if FileAccess.file_exists(SAVE_PATH):
		var text := FileAccess.get_file_as_string(SAVE_PATH)
		var parsed = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			_merge(data, parsed)
	apply_settings()

func save_game() -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[SaveSystem] cannot write save file")
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true

func reset() -> void:
	data = default_data()
	save_game()

func _merge(dst: Dictionary, src: Dictionary) -> void:
	for k in src.keys():
		if dst.has(k) and typeof(dst[k]) == TYPE_DICTIONARY and typeof(src[k]) == TYPE_DICTIONARY:
			_merge(dst[k], src[k])
		else:
			dst[k] = src[k]

# --- convenience -------------------------------------------------------------------------------

func get_setting(key: String, default = null):
	return data["settings"].get(key, default)

func set_setting(key: String, value) -> void:
	data["settings"][key] = value
	apply_settings()
	save_game()

func apply_settings() -> void:
	var s: Dictionary = data["settings"]
	var master := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master, linear_to_db(clamp(float(s.get("master_volume", 1.0)), 0.0001, 1.0)))
	for bus_name in ["Music", "SFX"]:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx >= 0:
			var key := "music_volume" if bus_name == "Music" else "sfx_volume"
			AudioServer.set_bus_volume_db(idx, linear_to_db(clamp(float(s.get(key, 1.0)), 0.0001, 1.0)))
	if not DisplayServer.get_name() == "headless":
		var want_fs: bool = s.get("fullscreen", false)
		var mode := DisplayServer.window_get_mode()
		if want_fs and mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif not want_fs and mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if s.get("vsync", true) else DisplayServer.VSYNC_DISABLED)

func hero_meta(hero_id: String) -> Dictionary:
	if not data["hero_meta"].has(hero_id):
		data["hero_meta"][hero_id] = {"level": 1, "xp": 0, "runs": 0, "wins": 0}
	return data["hero_meta"][hero_id]

func map_record(map_id: String) -> Dictionary:
	if not data["maps"].has(map_id):
		data["maps"][map_id] = {"completed": false, "best_waves": 0, "wins": 0, "attempts": 0, "stars": 0}
	return data["maps"][map_id]

func unlock_codex(entry_id: String) -> void:
	if not data["codex_unlocked"].has(entry_id):
		data["codex_unlocked"].append(entry_id)
		EventBus.codex_unlocked.emit(entry_id)

func is_codex_unlocked(entry_id: String) -> bool:
	return data["codex_unlocked"].has(entry_id)

func record_run_result(map_id: String, hero_id: String, won: bool, waves_reached: int, xp_earned: int, bottles: int) -> void:
	var rec := map_record(map_id)
	rec["attempts"] += 1
	rec["best_waves"] = max(rec["best_waves"], waves_reached)
	if won:
		rec["completed"] = true
		rec["wins"] += 1
		rec["stars"] = max(rec["stars"], 1)
	var hm := hero_meta(hero_id)
	hm["runs"] += 1
	if won:
		hm["wins"] += 1
	hm["xp"] += xp_earned
	while hm["xp"] >= meta_xp_for_level(hm["level"]) and hm["level"] < 20:
		hm["xp"] -= meta_xp_for_level(hm["level"])
		hm["level"] += 1
	data["xp_bottles"] += bottles
	data["stats"]["total_runs"] += 1
	if won:
		data["stats"]["total_wins"] += 1
	save_game()

static func meta_xp_for_level(level: int) -> int:
	return 100 + level * 60
