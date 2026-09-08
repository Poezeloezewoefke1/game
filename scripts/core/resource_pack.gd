class_name ResourcePack
extends RefCounted
## Reads textures out of a Minecraft resource pack laid out the vanilla way, so the game can use real
## block, armour, glint and item art instead of the procedural stand-ins.
##
## Drop an unzipped pack at res://assets/resourcepack/ (so it ships inside the build) or at
## user://resourcepack/ (so a player can swap it without a rebuild); the user path wins. If neither is
## present every lookup returns null and callers fall back to the generated placeholders, which is why
## the game still runs with no pack installed.
##
## A pack IS committed at assets/resourcepack/, at the project owner's direction. That artwork is
## Mojang's, not this project's, and their permission has not been obtained -- see
## docs/ASSET_LICENSES.md and KNOWN_LIMITATIONS. Deleting the directory is a supported configuration:
## every lookup then returns null and the generated placeholders take over.

const ROOTS := ["user://resourcepack/", "res://assets/resourcepack/"]
const MC := "assets/minecraft/textures/"

# Vanilla renders these greyscale and tints them per biome, so a raw load comes out grey.
# These are the plains-biome colours.
const GRASS_TINT := Color(0.569, 0.741, 0.349)
const FOLIAGE_TINT := Color(0.467, 0.671, 0.184)
const WATER_TINT := Color(0.247, 0.463, 0.894)
## Vanilla's default (undyed) leather colour. The leather layers ship greyscale because the game
## multiplies them by the dye at runtime, so loading them raw gives white armour.
const LEATHER_TINT := Color(0.647, 0.412, 0.247)
## Vanilla's water-bottle colour. Potion sprites ship greyscale for the same reason leather does.
const POTION_TINT := Color(0.220, 0.451, 0.851)

## This project's block ids -> {path, tint}. A block missing from here simply has no pack texture and
## keeps its generated one.
const BLOCKS := {
	"grass_top": {"path": "block/grass_block_top", "tint": "grass"},
	"grass_side": {"path": "block/grass_block_side"},
	"dirt": {"path": "block/dirt"},
	"path": {"path": "block/dirt_path_top"},
	"cobble": {"path": "block/cobblestone"},
	"stone": {"path": "block/stone"},
	"stone_bricks": {"path": "block/stone_bricks"},
	"sand": {"path": "block/sand"},
	"gravel": {"path": "block/gravel"},
	"planks": {"path": "block/oak_planks"},
	"dark_planks": {"path": "block/dark_oak_planks"},
	"log_side": {"path": "block/oak_log"},
	"log_top": {"path": "block/oak_log_top"},
	"leaves": {"path": "block/oak_leaves", "tint": "foliage"},
	"dead_leaves": {"path": "block/azalea_leaves"},
	"snow": {"path": "block/snow"},
	"obsidian": {"path": "block/obsidian"},
	"crying": {"path": "block/crying_obsidian"},
	"netherrack": {"path": "block/netherrack"},
	"basalt": {"path": "block/basalt_top"},
	"blackstone": {"path": "block/blackstone"},
	"magma": {"path": "block/magma"},
	"glass": {"path": "block/glass"},
	"gold_block": {"path": "block/gold_block"},
	"iron_block": {"path": "block/iron_block"},
	"tnt_side": {"path": "block/tnt_side"},
	"tnt_top": {"path": "block/tnt_top"},
	"tnt_bottom": {"path": "block/tnt_bottom"},
	"water": {"path": "block/water_still", "tint": "water"},
	"lava": {"path": "block/lava_still"},
	"wool_red": {"path": "block/red_wool"},
	"wool_blue": {"path": "block/blue_wool"},
	"wool_gold": {"path": "block/yellow_wool"},
	"wool_white": {"path": "block/white_wool"},
	"wool_black": {"path": "block/black_wool"},
	# Ground detail, scattered over the board so a field of grass is not one flat colour.
	"short_grass": {"path": "block/short_grass", "tint": "foliage"},
	"fern": {"path": "block/fern", "tint": "foliage"},
	"moss": {"path": "block/moss_block"},
	"coarse_dirt": {"path": "block/coarse_dirt"},
	"rooted_dirt": {"path": "block/rooted_dirt"},
	"mossy_cobble": {"path": "block/mossy_cobblestone"},
	"andesite": {"path": "block/andesite"},
	"dandelion": {"path": "block/dandelion"},
	"poppy": {"path": "block/poppy"},
	"cornflower": {"path": "block/cornflower"},
	"azure_bluet": {"path": "block/azure_bluet"},
	"oxeye_daisy": {"path": "block/oxeye_daisy"},
}

## This project's armour material names -> the pack's equipment texture name.
const ARMOR_MATERIALS := {
	"leather": "leather", "chain": "chainmail", "chainmail": "chainmail", "copper": "copper",
	"iron": "iron", "gold": "gold", "golden": "gold", "diamond": "diamond", "netherite": "netherite",
	"turtle": "turtle_scute",
}

static var _cache: Dictionary = {}
static var _root: String = ""
static var _root_checked: bool = false

## The pack directory in use, or "" when no pack is installed.
static func root() -> String:
	if not _root_checked:
		_root_checked = true
		for r in ROOTS:
			if DirAccess.dir_exists_absolute(r + MC + "block"):
				_root = r
				break
	return _root

static func available() -> bool:
	return root() != ""

## Forgets the cached lookups. Only needed if a pack is installed while the game is running.
static func reset() -> void:
	_cache.clear()
	_root = ""
	_root_checked = false

# ================================================================================================
# Lookups
# ================================================================================================

## A block texture for one of this project's block ids, tinted and de-animated. Null when absent.
static func block_image(block: String) -> Image:
	var key := "b:" + block
	if _cache.has(key):
		return _cache[key]
	var img: Image = null
	var entry: Dictionary = BLOCKS.get(block, {})
	if not entry.is_empty():
		img = _load(String(entry["path"]))
		if img != null:
			img = _first_frame(img)
			match String(entry.get("tint", "")):
				"grass": _tint(img, GRASS_TINT)
				"foliage": _tint(img, FOLIAGE_TINT)
				"water": _tint(img, WATER_TINT)
			# The grass side texture is a dirt face plus a separate overlay that carries the tint;
			# without compositing it the block has bare dirt sides.
			if block == "grass_side":
				var overlay := _load("block/grass_block_side_overlay")
				if overlay != null:
					overlay = _first_frame(overlay)
					_tint(overlay, GRASS_TINT)
					img.blend_rect(overlay, Rect2i(Vector2i.ZERO, overlay.get_size()), Vector2i.ZERO)
	_cache[key] = img
	return img

## An armour layer. `layer` is 1 (helmet, chestplate, boots) or 2 (leggings), matching Minecraft's
## two-texture split. Null when the pack has no such material.
static func armor_layer(material: String, layer: int = 1) -> Image:
	var mat := String(ARMOR_MATERIALS.get(material, material))
	var key := "a:%s:%d" % [mat, layer]
	if _cache.has(key):
		return _cache[key]
	var img: Image = null
	if mat == "leather":
		img = dyed_leather_layer(layer, LEATHER_TINT)
	else:
		img = _load("%s/%s" % [_equipment_dir(layer), mat])
	_cache[key] = img
	return img

## Leather is the only armour Minecraft lets a player colour, so a coloured livery is dyed leather:
## the layer ships greyscale, the game multiplies it by the dye, and the overlay carries the parts
## that are never dyed (buckles, stitching) and goes on top untinted. `armor_layer` uses this with
## vanilla's default brown; anything wanting another colour asks for it here.
static func dyed_leather_layer(layer: int, dye: Color) -> Image:
	var key := "dl:%d:%s" % [layer, dye.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	var dir := _equipment_dir(layer)
	var img := _load("%s/leather" % dir)
	if img != null:
		img = img.duplicate()
		_tint(img, dye)
		var overlay := _load("%s/leather_overlay" % dir)
		if overlay != null:
			img.blend_rect(overlay, Rect2i(Vector2i.ZERO, overlay.get_size()), Vector2i.ZERO)
	_cache[key] = img
	return img

static func _equipment_dir(layer: int) -> String:
	return "entity/equipment/humanoid" if layer == 1 else "entity/equipment/humanoid_leggings"

## The scrolling overlay Minecraft draws over enchanted gear.
static func glint_image(for_armor: bool = true) -> Image:
	var key := "g:%s" % for_armor
	if _cache.has(key):
		return _cache[key]
	_cache[key] = _load("misc/enchanted_glint_armor" if for_armor else "misc/enchanted_glint_item")
	return _cache[key]

## An inventory item icon, e.g. "diamond_sword". Potions are composited the way the game does it:
## the sprite ships as a greyscale liquid that gets multiplied by the potion colour, with the glass
## bottle as a separate overlay, so loading `potion` raw gives a white blob and no bottle.
static func item_image(item: String) -> Image:
	var key := "i:" + item
	if _cache.has(key):
		return _cache[key]
	var img := _load("item/" + item)
	if img != null and (item == "potion" or item == "splash_potion" or item == "lingering_potion"):
		img = img.duplicate()
		_tint(img, POTION_TINT)
		var overlay := _load("item/%s_overlay" % item)
		if overlay != null:
			img.blend_rect(overlay, Rect2i(Vector2i.ZERO, overlay.get_size()), Vector2i.ZERO)
	_cache[key] = img
	return img

## Any texture in the pack addressed by its vanilla-relative path, e.g.
## "entity/shield/shield_base_nopattern". Null when the pack has no such file.
static func raw_image(rel: String) -> Image:
	var key := "r:" + rel
	if _cache.has(key):
		return _cache[key]
	_cache[key] = _load(rel)
	return _cache[key]

# ================================================================================================
# Internals
# ================================================================================================

static func _load(rel: String) -> Image:
	var r := root()
	if r == "":
		return null
	var path := r + MC + rel + ".png"
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	# Loaded from bytes rather than as a resource: pack files are plain data, not imported assets.
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty() or img.load_png_from_buffer(bytes) != OK:
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img

## Animated block textures are a vertical strip of square frames; take the first one.
static func _first_frame(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	if h <= w or w <= 0 or h % w != 0:
		return img
	return img.get_region(Rect2i(0, 0, w, w))

static func _tint(img: Image, colour: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r * colour.r, c.g * colour.g, c.b * colour.b, c.a))
