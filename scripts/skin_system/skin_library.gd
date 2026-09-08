extends Node
## Autoload: SkinLibrary. Resolves character ids to SkinData, caching parsed skins, materials and merged meshes.
## Resolution order: user://skins/<id>.png (drop-in override)  >  res://assets/skins/<id>.png  >  generated placeholder.

const SKIN_DIR := "res://assets/skins/"
const USER_SKIN_DIR := "user://skins/"

var _skins: Dictionary = {}
var _materials: Dictionary = {}
var _merged_meshes: Dictionary = {}
var _faces: Dictionary = {}
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

## One merged mesh per armour layer group, for MultiMesh rendering. Each needs its own texture, so
## they cannot be merged into the skin mesh the way the shell-box armour was.
func get_armor_layer_meshes(armor: Dictionary) -> Array:
	var key := "armor|" + JSON.stringify(armor)
	if _merged_meshes.has(key):
		return _merged_meshes[key]
	var out: Array = []
	for group in ArmorBuilder.layer_groups(armor):
		out.append({
			"mesh": ArmorBuilder.build_layer_merged_mesh(group["parts"], group), "group": group,
		})
	_merged_meshes[key] = out
	return out

## The held item as its own merged mesh, positioned in the character's hand. Separate from the skin
## mesh for the same reason the armour layers are: it wears a different texture.
## Returns {} when the pack cannot draw this weapon, in which case the box model is already merged in.
func get_held_item_mesh(weapon_id: String, slim: bool) -> Dictionary:
	if weapon_id == "" or not WeaponBuilder.has_real_item(weapon_id):
		return {}
	var key := "held|%s|%s" % [weapon_id, slim]
	if _merged_meshes.has(key):
		return _merged_meshes[key]
	var mesh := WeaponBuilder.build_real_mesh(weapon_id, MCMeshBuilder.hand_transform(slim),
		MCMeshBuilder.hand_pivot(slim), MCGeometry.Part.HELD)
	var out: Dictionary = {"mesh": mesh, "weapon": weapon_id} if mesh != null else {}
	_merged_meshes[key] = out
	return out

# ================================================================================================
# Avatars
# ================================================================================================

## A character's face as a 2D texture, for the UI. This is exactly the avatar Minecraft itself shows:
## the head's front face out of the skin, with the hat layer composited on top so hoods, hair and
## masks are not lost. Nearest-neighbour scaled, because a Minecraft face is 8 pixels across and
## smoothing it turns a recognisable character into a smudge.
func face_texture(id: String, px: int = 64) -> ImageTexture:
	var key := "%s|%d" % [id, px]
	if _faces.has(key):
		return _faces[key]
	var skin := get_skin(id)
	var src := skin.image
	var tex: ImageTexture = null
	if src != null:
		var s := skin.scale                     # 2 for a 128x128 skin, and so on
		var face := src.get_region(Rect2i(8 * s, 8 * s, 8 * s, 8 * s))
		# The hat is the second layer at (40,8); many supplied skins carry the whole silhouette there.
		if src.get_width() >= 64 * s:
			var hat := src.get_region(Rect2i(40 * s, 8 * s, 8 * s, 8 * s))
			face.blend_rect(hat, Rect2i(Vector2i.ZERO, hat.get_size()), Vector2i.ZERO)
		face.resize(px, px, Image.INTERPOLATE_NEAREST)
		tex = ImageTexture.create_from_image(face)
	_faces[key] = tex
	return tex

func clear_cache() -> void:
	_skins.clear(); _materials.clear(); _merged_meshes.clear(); _faces.clear()

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
