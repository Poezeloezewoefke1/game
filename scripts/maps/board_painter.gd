class_name BoardPainter
extends RefCounted
## Paints a map definition into a single top-down image: the "2D board" the game is played on.
##
## The voxel renderer in MapBuilder extrudes the same definition into blocks. This paints it flat
## instead, compositing the real 16x16 block textures one cell per world unit, so the board still
## reads as Minecraft terrain while being a genuinely 2D surface with 3D characters standing on it.
##
## Everything here is presentation. The path, build zones and gameplay bounds come from the same
## definition either way, so switching renderers cannot change how a map plays.

const PX := 16                      ## pixels per world unit — one block texture, unscaled
const SHADOW := Color(0, 0, 0, 0.22)

var _cache: Dictionary = {}         # block name -> Image
var rng := RandomNumberGenerator.new()

# Painted result and the world rect it covers.
var image: Image
var rect: Rect2i                    # in world units: position = (min_x, min_z), size = (w, h)
var _ground: Dictionary = {}        # Vector2i -> the terrain block painted there

## Paints the board for `map_def`. `bounds` is the world-space rect to cover, in whole units.
func paint(map_def: Dictionary, path: MapPath, bounds: Rect2i) -> Image:
	rect = bounds
	_ground.clear()
	rng.seed = hash(String(map_def.get("id", "map")))
	image = Image.create_empty(bounds.size.x * PX, bounds.size.y * PX, false, Image.FORMAT_RGBA8)
	_paint_terrain(map_def)
	_paint_ground_detail(map_def, path)
	_paint_structures(map_def, path)
	_paint_path(map_def, path)
	image.generate_mipmaps()
	return image

# ================================================================================================
# Terrain
# ================================================================================================

func _paint_terrain(map_def: Dictionary) -> void:
	var terrain: Dictionary = map_def.get("terrain", {})
	var base := String(terrain.get("base", "grass"))
	var patches: Array = terrain.get("patches", [])
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var block := base
			for p in patches:
				var r: Array = p.get("rect", [0, 0, 0, 0])
				if x >= int(r[0]) and x < int(r[0]) + int(r[2]) and z >= int(r[1]) and z < int(r[1]) + int(r[3]):
					block = String(p.get("block", block))
			# Remember what each cell actually is, so the detail pass can put plants on soil and
			# leave the stone alone rather than sprinkling daisies across a courtyard.
			_ground[Vector2i(x, z)] = block
			_cell(x, z, "grass_top" if block == "grass" else block)

## Breaks up the flat fields. A board painted from one grass tile per cell reads as a green table;
## real ground has patches of a different soil and things growing on it. Everything scattered here is
## a real Minecraft block, and it is all cosmetic -- placement rules never consult it.
##
## Two passes, because they do different jobs. Patches are large, low-contrast blotches of a
## neighbouring ground type, which give the field shape at a distance. Sprinkles are single cells of
## grass, ferns and flowers, which give it texture up close. Both are driven by the map's own seeded
## RNG, so a map paints the same way every time it is loaded.
const DETAIL_GROUND := {
	# Weighted by repetition: moss and coarse dirt read as ground, rooted dirt is pink enough that a
	# field full of it stops looking like a field.
	"grass": ["moss", "moss", "coarse_dirt", "coarse_dirt", "rooted_dirt"],
	"sand": ["gravel", "coarse_dirt"],
	"stone": ["andesite", "mossy_cobble"],
	"cobble": ["mossy_cobble", "andesite"],
}
const DETAIL_PLANTS := ["short_grass", "short_grass", "short_grass", "fern",
	"dandelion", "poppy", "cornflower", "azure_bluet", "oxeye_daisy"]
## How far from the middle of the road detail stops, so the lane stays clean and readable.
const DETAIL_PATH_CLEARANCE := 2.6

func _paint_ground_detail(map_def: Dictionary, path: MapPath) -> void:
	if not ResourcePack.available():
		return                                    # the generated stand-ins have no detail blocks
	var terrain: Dictionary = map_def.get("terrain", {})
	var base := String(terrain.get("base", "grass"))

	# Pass one: soft blotches of a ground type related to whatever is already there.
	var blotches := int(rect.size.x * rect.size.y / 220)
	for _i in blotches:
		var cx := rng.randi_range(rect.position.x, rect.end.x - 1)
		var cz := rng.randi_range(rect.position.y, rect.end.y - 1)
		var under := String(_ground.get(Vector2i(cx, cz), base))
		var options: Array = DETAIL_GROUND.get(under, [])
		if options.is_empty():
			continue
		var r := rng.randi_range(2, 5)
		var block := String(options[rng.randi() % options.size()])
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dz * dz > r * r:
					continue
				# Ragged edge: skip some rim cells so blotches are not discs.
				if dx * dx + dz * dz > (r - 1) * (r - 1) and rng.randf() < 0.55:
					continue
				_detail_cell(cx + dx, cz + dz, block, path, under)

	# Pass two: single cells of growth, on soil only.
	var sprinkles := int(rect.size.x * rect.size.y / 14)
	for _i in sprinkles:
		var x := rng.randi_range(rect.position.x, rect.end.x - 1)
		var z := rng.randi_range(rect.position.y, rect.end.y - 1)
		_detail_cell(x, z, String(DETAIL_PLANTS[rng.randi() % DETAIL_PLANTS.size()]), path, "grass")

## Paints a decorative cell, subject to two rules: never on or beside the road, because the lane has
## to stay obvious, and only where the ground underneath is the kind this detail belongs on.
func _detail_cell(x: int, z: int, block: String, path: MapPath, requires: String = "") -> void:
	if _origin(x, z).x < 0:
		return
	if requires != "" and String(_ground.get(Vector2i(x, z), "")) != requires:
		return
	if path != null and path.min_distance_to(Vector3(x, 0, z)) < DETAIL_PATH_CLEARANCE:
		return
	_cell(x, z, block)

# ================================================================================================
# Path
# ================================================================================================

func _paint_path(map_def: Dictionary, path: MapPath) -> void:
	# Same footprint the voxel renderer paints, so what you see is what enemies walk on.
	var width := float(map_def.get("path_width", 3.0))
	var block := String(map_def.get("path_block", "path"))
	var painted: Dictionary = {}
	var steps := int(path.total_length / 0.5)
	for i in range(steps + 1):
		var centre := path.position_at(float(i) * 0.5)
		var normal := path.normal_at(float(i) * 0.5)
		var half := int(ceil(width * 0.5))
		for o in range(-half, half + 1):
			var p := centre + normal * float(o)
			var key := Vector2i(int(round(p.x)), int(round(p.z)))
			if painted.has(key):
				continue
			painted[key] = true
			_cell(key.x, key.y, block)
	# A dark rim around the road so it reads as a road at a glance rather than as another texture
	# patch. Any painted cell with an unpainted neighbour gets its outer pixels darkened.
	for key: Vector2i in painted.keys():
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if painted.has(key + d):
				continue
			_edge_shade(key, d)

func _edge_shade(cell: Vector2i, dir: Vector2i) -> void:
	var o := _origin(cell.x, cell.y)
	if o.x < 0:
		return
	var thickness := 3
	for i in thickness:
		var a := 0.30 * (1.0 - float(i) / float(thickness))
		for t in PX:
			var px := o
			if dir.x != 0:
				px += Vector2i(PX - 1 - i if dir.x > 0 else i, t)
			else:
				px += Vector2i(t, PX - 1 - i if dir.y > 0 else i)
			if px.x < 0 or px.y < 0 or px.x >= image.get_width() or px.y >= image.get_height():
				continue
			image.set_pixelv(px, image.get_pixelv(px).darkened(a))

# ================================================================================================
# Structures
# ================================================================================================

func _paint_structures(map_def: Dictionary, path: MapPath) -> void:
	for s in map_def.get("structures", []):
		match String(s.get("kind", "")):
			"fort_wall", "tower", "keep":
				_paint_box(s)
			"watchtower":
				_paint_watchtower(s)
			"banner":
				_paint_banner(s)
			"camp":
				_paint_camp(s)
			"trees":
				_paint_trees(s, path)
			"rocks":
				_paint_rocks(s, path)
			"market_stalls":
				_paint_stalls(s, path)
			"training_dummies":
				_paint_dummies(s)

## Walls and keeps seen from above: a ring of blocks with a floor inside, plus a cast shadow so a
## tall structure still reads as tall on a flat board.
func _paint_box(s: Dictionary) -> void:
	var pos: Array = s.get("pos", [0, 0, 0])
	var size: Array = s.get("size", [1, 1, 1])
	var block := String(s.get("block", "stone_bricks"))
	var x0 := int(pos[0])
	var z0 := int(pos[2])
	var w := int(size[0])
	var d := int(size[2])
	var height := int(size[1])
	_shadow_rect(x0 + 1, z0 + 1, w, d, minf(0.55, 0.12 + 0.05 * float(height)))
	for x in range(x0, x0 + w):
		for z in range(z0, z0 + d):
			var edge: bool = x == x0 or x == x0 + w - 1 or z == z0 or z == z0 + d - 1
			if edge:
				_cell(x, z, "cobble" if (x + z) % 2 == 0 else block)
			else:
				_cell(x, z, "dark_planks", 0.25)      # shaded courtyard floor
	_outline(x0, z0, w, d)

func _paint_watchtower(s: Dictionary) -> void:
	var pos: Array = s.get("pos", [0, 0, 0])
	var x := int(pos[0])
	var z := int(pos[2])
	_shadow_rect(x, z + 1, 4, 4, 0.4)
	for dx in range(-1, 3):
		for dz in range(-1, 3):
			_cell(x + dx, z + dz, "dark_planks")
	for dx in 2:
		for dz in 2:
			_cell(x + dx, z + dz, "log_top")
	_outline(x - 1, z - 1, 4, 4)

func _paint_banner(s: Dictionary) -> void:
	var pos: Array = s.get("pos", [0, 0, 0])
	var cloth := "wool_blue" if String(s.get("color", "royal")) == "royal" else "wool_red"
	_shadow_rect(int(pos[0]), int(pos[2]) + 1, 1, 1, 0.35)
	_cell(int(pos[0]), int(pos[2]), cloth)

func _paint_camp(s: Dictionary) -> void:
	var pos: Array = s.get("pos", [0, 0, 0])
	var cx := int(pos[0])
	var cz := int(pos[2])
	for i in 5:
		var a := TAU * float(i) / 5.0
		var tx := cx + int(cos(a) * 5.0)
		var tz := cz + int(sin(a) * 5.0)
		_shadow_rect(tx - 1, tz, 3, 3, 0.3)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				_cell(tx + dx, tz + dz, "wool_red")
	_cell(cx, cz, "magma")

func _paint_trees(s: Dictionary, path: MapPath) -> void:
	var area: Array = s.get("area", [0, 0, 10, 10])
	for i in int(s.get("count", 8)):
		var x := int(rng.randf_range(area[0], area[0] + area[2]))
		var z := int(rng.randf_range(area[1], area[1] + area[3]))
		var h := rng.randi_range(4, 7)                # consumed either way, keeps rng in step
		if path.min_distance_to(Vector3(x, 0, z), 1.0) < 5.0:
			continue
		_shadow_disc(x + 1, z + 1, 2, 0.32)
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				if absi(dx) + absi(dz) > 3:
					continue
				_cell(x + dx, z + dz, "leaves", 0.10 if absi(dx) + absi(dz) > 1 else 0.0)
		_cell(x, z, "log_top")
		if h > 5:
			_cell(x, z - 1, "leaves", 0.05)

func _paint_rocks(s: Dictionary, path: MapPath) -> void:
	var area: Array = s.get("area", [0, 0, 10, 10])
	for i in int(s.get("count", 10)):
		var x := int(rng.randf_range(area[0], area[0] + area[2]))
		var z := int(rng.randf_range(area[1], area[1] + area[3]))
		var block := "cobble" if rng.randf() < 0.6 else "gravel"
		var wide := rng.randf() < 0.4
		var tall := rng.randf() < 0.3
		if path.min_distance_to(Vector3(x, 0, z), 1.0) < 3.5:
			continue
		_shadow_disc(x, z + 1, 1, 0.25)
		_cell(x, z, block)
		if wide:
			_cell(x + 1, z, block)
		if tall:
			_cell(x, z - 1, block)

func _paint_stalls(s: Dictionary, path: MapPath) -> void:
	var area: Array = s.get("area", [0, 0, 10, 10])
	var colors := ["wool_red", "wool_blue", "wool_gold", "wool_white"]
	for i in int(s.get("count", 10)):
		var x := int(rng.randf_range(area[0], area[0] + area[2]))
		var z := int(rng.randf_range(area[1], area[1] + area[3]))
		var cloth: String = colors[rng.randi() % colors.size()]
		if path.min_distance_to(Vector3(x, 0, z), 1.0) < 4.0:
			continue
		_shadow_rect(x + 1, z + 1, 3, 3, 0.3)
		for dx in 3:
			for dz in 3:
				_cell(x + dx, z + dz, cloth)
		for cx in [0, 2]:
			for cz in [0, 2]:
				_cell(x + cx, z + cz, "log_top")

func _paint_dummies(s: Dictionary) -> void:
	var pos: Array = s.get("pos", [0, 0, 0])
	for i in int(s.get("count", 3)):
		var x := int(pos[0]) + i * 2
		var z := int(pos[2])
		_shadow_disc(x, z + 1, 1, 0.25)
		_cell(x, z, "wool_white")
		_cell(x - 1, z, "planks", 0.15)
		_cell(x + 1, z, "planks", 0.15)

# ================================================================================================
# Painting primitives
# ================================================================================================

## Top-left pixel of a world cell, or (-1, -1) when the cell is outside the board.
func _origin(x: int, z: int) -> Vector2i:
	if x < rect.position.x or z < rect.position.y or x >= rect.end.x or z >= rect.end.y:
		return Vector2i(-1, -1)
	return Vector2i((x - rect.position.x) * PX, (z - rect.position.y) * PX)

## Stamps one block texture into a world cell, optionally darkened.
func _cell(x: int, z: int, block: String, darken: float = 0.0) -> void:
	var o := _origin(x, z)
	if o.x < 0:
		return
	var src := _block_image(block)
	if src == null:
		return
	var r := Rect2i(0, 0, PX, PX)
	# blend rather than blit so textures with holes (leaves) show the ground through them
	image.blend_rect(src, r, o)
	if darken > 0.0:
		for py in PX:
			for px in PX:
				var v := o + Vector2i(px, py)
				image.set_pixelv(v, image.get_pixelv(v).darkened(darken))

func _shadow_rect(x: int, z: int, w: int, h: int, alpha: float) -> void:
	for dz in h:
		for dx in w:
			_tint(x + dx, z + dz, Color(SHADOW.r, SHADOW.g, SHADOW.b, alpha))

func _shadow_disc(x: int, z: int, r: int, alpha: float) -> void:
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dz * dz > r * r + 1:
				continue
			_tint(x + dx, z + dz, Color(SHADOW.r, SHADOW.g, SHADOW.b, alpha))

func _tint(x: int, z: int, c: Color) -> void:
	var o := _origin(x, z)
	if o.x < 0:
		return
	for py in PX:
		for px in PX:
			var v := o + Vector2i(px, py)
			image.set_pixelv(v, image.get_pixelv(v).blend(c))

## One-pixel dark border around a footprint, so structures have a clean silhouette.
func _outline(x: int, z: int, w: int, h: int) -> void:
	var tl := _origin(x, z)
	if tl.x < 0:
		return
	var x1: int = mini(tl.x + w * PX, image.get_width()) - 1
	var y1: int = mini(tl.y + h * PX, image.get_height()) - 1
	for px in range(tl.x, x1 + 1):
		_dark_px(px, tl.y)
		_dark_px(px, y1)
	for py in range(tl.y, y1 + 1):
		_dark_px(tl.x, py)
		_dark_px(x1, py)

func _dark_px(x: int, y: int) -> void:
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return
	image.set_pixel(x, y, image.get_pixel(x, y).darkened(0.45))

## Block textures are stored with the "keep" importer, so they are decoded from raw bytes rather
## than loaded as resources — the same path the skin system uses.
func _block_image(block: String) -> Image:
	if _cache.has(block):
		return _cache[block]
	# Real pack art when a resource pack is installed, otherwise the project's generated stand-in.
	var img := ResourcePack.block_image(block)
	if img != null:
		img = img.duplicate()          # the pack's cache is shared; never resize the cached copy
	else:
		img = SkinParser.load_image("res://assets/textures/block_%s.png" % block)
	if img != null:
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		if img.get_width() != PX or img.get_height() != PX:
			img.resize(PX, PX, Image.INTERPOLATE_NEAREST)
	_cache[block] = img
	return img
