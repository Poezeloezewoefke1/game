extends Node
## Loads every JSON data file under res://data into memory. Autoload name: DataDB.
## Access with DataDB.towers["theo"], DataDB.enemies["chungie_t3"], DataDB.lore.characters ...

var heroes: Dictionary = {}
var towers: Dictionary = {}
var enemies: Dictionary = {}
var bosses: Dictionary = {}
var maps: Dictionary = {}
var waves: Dictionary = {}
var factions: Dictionary = {}
var relationships: Array = []
var weapons_catalog: Dictionary = {}
var armor_catalog: Dictionary = {}
var lore: Dictionary = {}          # category -> Array of entries
var characters: Dictionary = {}    # character id -> lore character entry
var asset_manifest: Dictionary = {}
var loaded: bool = false

func _ready() -> void:
	load_all()

func load_all() -> void:
	heroes = _load_map("res://data/heroes/heroes.json", "heroes")
	towers = _load_map("res://data/towers/towers.json", "towers")
	enemies = _load_map("res://data/enemies/enemies.json", "enemies")
	bosses = _load_map("res://data/bosses/bosses.json", "bosses")
	maps = _load_map("res://data/maps/maps.json", "maps")
	factions = _load_map("res://data/enemies/factions.json", "factions")
	weapons_catalog = _load_map("res://data/characters/weapons_catalog.json", "weapons")
	armor_catalog = _load_map("res://data/characters/armor_catalog.json", "armor")
	relationships = _load_json("res://data/characters/relationships.json").get("relationships", [])
	asset_manifest = _load_json("res://data/asset_manifest.json")
	for map_id in maps.keys():
		var wave_path: String = maps[map_id].get("waves", "")
		if wave_path != "":
			waves[map_id] = _load_json(wave_path)
	for cat in ["characters", "arcs", "factions", "locations", "events", "weapons", "bosses"]:
		var j := _load_json("res://data/lore/%s.json" % cat)
		lore[cat] = j.get("entries", [])
	for entry in lore.get("characters", []):
		characters[entry.get("id", "")] = entry
	loaded = true
	print("[DataDB] loaded: %d heroes, %d towers, %d enemies, %d bosses, %d maps, %d lore characters" % [
		heroes.size(), towers.size(), enemies.size(), bosses.size(), maps.size(), characters.size()])

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("[DataDB] missing data file: %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[DataDB] failed to parse %s" % path)
		return {}
	return parsed

func _load_map(path: String, key: String) -> Dictionary:
	var j := _load_json(path)
	var out: Dictionary = {}
	var list = j.get(key, [])
	if typeof(list) == TYPE_ARRAY:
		for e in list:
			if typeof(e) == TYPE_DICTIONARY and e.has("id"):
				out[e["id"]] = e
	elif typeof(list) == TYPE_DICTIONARY:
		out = list
	return out

func get_lore_entry(category: String, id: String) -> Dictionary:
	for e in lore.get(category, []):
		if e.get("id", "") == id:
			return e
	return {}

func character_display_name(id: String) -> String:
	if characters.has(id):
		return characters[id].get("name", id)
	if towers.has(id):
		return towers[id].get("name", id)
	if heroes.has(id):
		return heroes[id].get("name", id)
	return id.capitalize()
