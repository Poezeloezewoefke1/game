extends Node
## Autoload: SkinLibrary. Resolves character ids to SkinData, caching parsed skins, materials and merged meshes.
## Resolution order: user://skins/<id>.png (drop-in override)  >  res://assets/skins/<id>.png  >  generated placeholder.

const SKIN_DIR := "res://assets/skins/"
const USER_SKIN_DIR := "user://skins/"

var _skins: Dictionary = {}
var _materials: Dictionary = {}
var _merged_meshes: Dictionary = {}
var _manifest: Dictionary = {}
var missing_assets: Array[String] = []

func _ready() -> void:
	_load_manifest()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_SKIN_DIR))

func _load_manifest() -> void:
	var path := "res://data/asset_manifest.json"
	if FileAccess.file_exists(path):
		var j = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(j) == TYPE_DICTIONARY:
			for a in j.get("assets", []):
				if a.has("id"):
					_manifest[a["id"]] = a

func has_supplied_skin(id: String) -> bool:
	return FileAccess.file_exists(USER_SKIN_DIR + id + ".png") or FileAccess.file_exists(SKIN_DIR + id + ".png")

func get_skin(id: String) -> SkinData:
	if _skins.has(id):
		return _skins[id]
	var model_override: String = _manifest.get(id, {}).get("model", "")
	var data: SkinData = null
	for path in [USER_SKIN_DIR + id + ".png", SKIN_DIR + id + ".png"]:
		if FileAccess.file_exists(path):
			data = SkinParser.load_from_path(path, id, model_override)
			if data:
				break
	if data == null:
		data = _placeholder_for(id)
		if not missing_assets.has(id):
			missing_assets.append(id)
	_skins[id] = data
	return data

func _placeholder_for(id: String) -> SkinData:
	# Deterministic palette from id so each placeholder is recognisable and stable between runs.
	var h := hash(id)
	var hue := float(h % 360) / 360.0
	var primary := Color.from_hsv(hue, 0.65, 0.75)
	var secondary := Color.from_hsv(fmod(hue + 0.5, 1.0), 0.45, 0.35)
	var accent := Color.from_hsv(fmod(hue + 0.15, 1.0), 0.8, 0.95)
	var info: Dictionary = DataDB.characters.get(id, {}) if DataDB.loaded else {}
	var pal = info.get("placeholder_palette", null)
	if typeof(pal) == TYPE_ARRAY and pal.size() >= 3:
		primary = Color(pal[0]); secondary = Color(pal[1]); accent = Color(pal[2])
	var slim: bool = info.get("model", "classic") == "slim"
	return SkinParser.generate_placeholder(id, primary, secondary, accent, slim)

func get_material(id: String, ghost: bool = false, gpu_anim: bool = false) -> ShaderMaterial:
	var key := "%s|%s|%s" % [id, ghost, gpu_anim]
	if _materials.has(key):
		return _materials[key]
	var m := MCMaterials.make(get_skin(id).get_texture(), ghost, gpu_anim)
	_materials[key] = m
	return m

## Merged single-surface mesh for MultiMesh enemies. Cache key includes armor and held item.
func get_merged_mesh(id: String, armor: Dictionary, held: String, extras: Array = []) -> ArrayMesh:
	var key := "%s|%s|%s|%s" % [id, JSON.stringify(armor), held, JSON.stringify(extras)]
	if _merged_meshes.has(key):
		return _merged_meshes[key]
	var mesh := MCMeshBuilder.build_merged_character(get_skin(id), armor, held, extras)
	_merged_meshes[key] = mesh
	return mesh

func clear_cache() -> void:
	_skins.clear(); _materials.clear(); _merged_meshes.clear()

func list_supplied_skins() -> Array[String]:
	var out: Array[String] = []
	for dir in [SKIN_DIR, USER_SKIN_DIR]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			if f.ends_with(".png"):
				out.append(f.get_basename())
	return out
