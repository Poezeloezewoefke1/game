class_name MapBuilder
extends Node3D
## Builds a blocky, Minecraft-inspired environment from a map definition. Every block face that is
## visible is merged into a handful of surface arrays (one per block texture), so a 96x96 map with
## structures costs a few draw calls rather than thousands of nodes.

const BLOCK := 1.0

## When true the map is painted as a single flat 2D board (see _build_flat_board); when false it is
## extruded into the original voxel world. Flat is the shipping look: a 2D map with 3D characters.
## The voxel renderer stays reachable because it is what the block-face diagnostics test.
var flat_board: bool = true
var board_plane: MeshInstance3D
var board_bounds: Rect2i

var map_def: Dictionary = {}
var path: MapPath
var rng := RandomNumberGenerator.new()
var _buffers: Dictionary = {}      # block name -> SurfaceTool-like arrays
var _textures: Dictionary = {}
var height_map: Dictionary = {}    # Vector2i -> top height
var build_zone_markers: Array = []
var block_face_counts: Dictionary = {}   # block texture -> faces emitted (diagnostics/tests)

func build(definition: Dictionary) -> MapPath:
	map_def = definition
	rng.seed = hash(String(definition.get("id", "map")))
	path = MapPath.new()
	var pts := PackedVector3Array()
	for p in definition.get("path", []):
		pts.push_back(Vector3(p[0], p[1], p[2]))
	path.build(pts)
	_build_environment()
	if flat_board:
		_build_flat_board()
	else:
		_build_terrain()
		_build_path_surface()
		_build_structures()
		_flush_buffers()
	_build_zone_markers()
	_build_base_marker()
	return path

## The build zones this map should use, flattened to ground level on a 2D board so models stand on
## the painted surface instead of floating at the voxel world's elevations.
func zone_data() -> Array:
	var src: Array = map_def.get("build_zones", [])
	if not flat_board:
		return src
	var out: Array = []
	for z in src:
		var copy: Dictionary = (z as Dictionary).duplicate(true)
		var p: Array = copy.get("pos", [0, 0, 0])
		copy["pos"] = [p[0], 0.0, p[2]]
		copy["elevation"] = 0.0
		out.append(copy)
	return out

# ================================================================================================
# Flat board
# ================================================================================================

## Paints the whole map into one texture on a single quad. See BoardPainter for what it draws and
## why: the map is 2D, the characters standing on it stay 3D.
func _build_flat_board() -> void:
	var bounds := _play_bounds()
	var painter := BoardPainter.new()
	var img := painter.paint(map_def, path, bounds)
	board_bounds = bounds

	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(float(bounds.size.x), float(bounds.size.y))
	# One subdivision per ~8 units keeps the quad's lighting from banding across a large plane.
	pm.subdivide_width = maxi(1, bounds.size.x / 8)
	pm.subdivide_depth = maxi(1, bounds.size.y / 8)
	plane.mesh = pm
	plane.position = Vector3(float(bounds.position.x) + float(bounds.size.x) * 0.5, 0.0,
		float(bounds.position.y) + float(bounds.size.y) * 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# The board already carries painted shading, and pale blocks (sand especially) clipped to flat
	# white once the sun and the filmic tonemap were applied on top. Tint it down to keep the texture.
	mat.albedo_color = Color(0.82, 0.82, 0.82)
	plane.material_override = mat
	add_child(plane)
	board_plane = plane

	# A larger, darker quad just underneath frames the board and hides the sky at its edges when
	# the camera is tilted.
	var backing := MeshInstance3D.new()
	var bm := PlaneMesh.new()
	bm.size = pm.size * 1.6
	backing.mesh = bm
	backing.position = plane.position + Vector3(0, -0.05, 0)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.07, 0.09, 0.08)
	bmat.roughness = 1.0
	bmat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	backing.material_override = bmat
	add_child(backing)

## The rect worth painting: everything the player interacts with (path and build zones) plus a
## margin, clipped to the map's terrain. Painting the full 96x96 terrain would put the action in a
## small island of empty grass.
func _play_bounds() -> Rect2i:
	const MARGIN := 6
	var min_x := INF
	var min_z := INF
	var max_x := -INF
	var max_z := -INF
	var pts: Array[Vector3] = []
	var steps := maxi(2, int(path.total_length / 2.0))
	for i in steps + 1:
		pts.append(path.position_at(path.total_length * float(i) / float(steps)))
	for z in map_def.get("build_zones", []):
		var p: Array = z.get("pos", [0, 0, 0])
		pts.append(Vector3(p[0], 0, p[2]))
	var bp: Array = map_def.get("base_position", [0, 0, 0])
	pts.append(Vector3(bp[0], 0, bp[2]))
	for p in pts:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	var terrain: Dictionary = map_def.get("terrain", {})
	var size: Array = terrain.get("size", [64, 64])
	var origin: Array = terrain.get("origin", [-32, 0, -32])
	var tx := int(origin[0])
	var tz := int(origin[2])
	var x0: int = maxi(tx, int(floor(min_x)) - MARGIN)
	var z0: int = maxi(tz, int(floor(min_z)) - MARGIN)
	var x1: int = mini(tx + int(size[0]), int(ceil(max_x)) + MARGIN)
	var z1: int = mini(tz + int(size[1]), int(ceil(max_z)) + MARGIN)
	return Rect2i(x0, z0, maxi(8, x1 - x0), maxi(8, z1 - z0))

# ================================================================================================
# Environment
# ================================================================================================

func _build_environment() -> void:
	var env_def: Dictionary = map_def.get("environment", {})
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = _color(env_def.get("sky_top", [0.3, 0.4, 0.6]))
	sky_mat.sky_horizon_color = _color(env_def.get("sky_horizon", [0.7, 0.6, 0.55]))
	sky_mat.ground_bottom_color = _color(env_def.get("ground_color", [0.25, 0.25, 0.2]))
	sky_mat.ground_horizon_color = _color(env_def.get("sky_horizon", [0.7, 0.6, 0.55]))
	sky_mat.sun_angle_max = 12.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = _color(env_def.get("ambient_color", [0.55, 0.6, 0.7]))
	env.ambient_light_energy = float(env_def.get("ambient_energy", 0.55))
	# Depth fog is for a world you look *into*. A flat board is viewed from far enough back that
	# every part of it sits at roughly the same distance, so fog stops reading as atmosphere and
	# just drains the whole map's contrast uniformly.
	if bool(env_def.get("fog", false)) and not flat_board:
		env.fog_enabled = true
		env.fog_light_color = _color(env_def.get("fog_color", [0.6, 0.6, 0.6]))
		env.fog_density = float(env_def.get("fog_density", 0.003))
		env.fog_sky_affect = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.4
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	var ang: Array = env_def.get("sun_angle", [-45, 145, 0])
	sun.rotation_degrees = Vector3(ang[0], ang[1], ang[2])
	sun.light_color = _color(env_def.get("sun_color", [1.0, 0.95, 0.85]))
	sun.light_energy = float(env_def.get("sun_energy", 1.3))
	sun.shadow_enabled = bool(SaveSystem.get_setting("shadows", true))
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)

static func _color(arr) -> Color:
	if typeof(arr) == TYPE_ARRAY and (arr as Array).size() >= 3:
		return Color(arr[0], arr[1], arr[2])
	return Color.WHITE

# ================================================================================================
# Terrain
# ================================================================================================

func _build_terrain() -> void:
	var terrain: Dictionary = map_def.get("terrain", {})
	var size: Array = terrain.get("size", [64, 64])
	var origin: Array = terrain.get("origin", [-32, 0, -32])
	var w := int(size[0])
	var h := int(size[1])
	var ox := int(origin[0])
	var oz := int(origin[2])
	var base_block := String(terrain.get("base", "grass"))
	var patches: Array = terrain.get("patches", [])
	# resolve block + height per column
	for x in range(ox, ox + w):
		for z in range(oz, oz + h):
			var block := base_block
			var top := 0
			for p in patches:
				var r: Array = p.get("rect", [0, 0, 0, 0])
				if x >= int(r[0]) and x < int(r[0]) + int(r[2]) and z >= int(r[1]) and z < int(r[1]) + int(r[3]):
					block = String(p.get("block", block))
					top = int(p.get("height", top))
			height_map[Vector2i(x, z)] = top
			_column(x, z, top, block)

func _column(x: int, z: int, top: int, block: String) -> void:
	# Grass columns show grass on top and dirt on the sides.
	var side_block := block
	var top_block := block
	if block == "grass":
		top_block = "grass_top"
		side_block = "grass_side"
	_add_block(Vector3(x, top, z), top_block, side_block, "dirt")
	for y in range(top - 1, maxi(-2, top - 2), -1):
		_add_block(Vector3(x, y, z), "dirt", "dirt", "dirt")

func _build_path_surface() -> void:
	# The road is painted by REPLACING the terrain column's surface block, because _add_block
	# refuses to overwrite an occupied cell.
	var width := float(map_def.get("path_width", 3.0))
	var block := String(map_def.get("path_block", "path"))
	var steps := int(path.total_length / 0.5)
	var painted: Dictionary = {}
	for i in range(steps + 1):
		var d := float(i) * 0.5
		var centre := path.position_at(d)
		var normal := path.normal_at(d)
		var half := int(ceil(width * 0.5))
		for o in range(-half, half + 1):
			var p := centre + normal * float(o)
			var key := Vector2i(int(round(p.x)), int(round(p.z)))
			if painted.has(key):
				continue
			painted[key] = true
			var top: int = int(height_map.get(key, 0))
			_set_block(Vector3(key.x, top, key.y), block, block, "dirt")

# ================================================================================================
# Structures
# ================================================================================================

func _build_structures() -> void:
	for s in map_def.get("structures", []):
		match String(s.get("kind", "")):
			"fort_wall", "tower", "keep":
				_box_structure(s)
			"watchtower":
				_watchtower(s)
			"banner":
				_banner(s)
			"camp":
				_camp(s)
			"trees":
				_trees(s)
			"rocks":
				_rocks(s)
			"market_stalls":
				_stalls(s)
			"training_dummies":
				_dummies(s)

func _box_structure(s: Dictionary) -> void:
	var pos: Array = s.get("pos", [0, 0, 0])
	var size: Array = s.get("size", [1, 1, 1])
	var block := String(s.get("block", "stone_bricks"))
	var x0 := int(pos[0])
	var y0 := int(pos[1])
	var z0 := int(pos[2])
	for x in range(x0, x0 + int(size[0])):
		for y in range(y0, y0 + int(size[1])):
			for z in range(z0, z0 + int(size[2])):
				var edge := x == x0 or x == x0 + int(size[0]) - 1 or z == z0 or z == z0 + int(size[2]) - 1 or y == y0 + int(size[1]) - 1
				if not edge:
					continue
				var b := block
				if y == y0 + int(size[1]) - 1 and (x + z) % 2 == 0:
					b = "cobble"           # crenellations pattern
				_add_block(Vector3(x, y, z), b, b, b)

func _watchtower(s: Dictionary) -> void:
	var pos: Array = s.get("pos", [0, 0, 0])
	var height := int(s.get("height", 7))
	var x := int(pos[0])
	var z := int(pos[2])
	for y in height:
		for dx in 2:
			for dz in 2:
				_add_block(Vector3(x + dx, y, z + dz), "log_side", "log_side", "log_top")
	for dx in range(-1, 3):
		for dz in range(-1, 3):
			_add_block(Vector3(x + dx, height, z + dz), "dark_planks", "dark_planks", "dark_planks")
	for dx in range(-1, 3):
		_add_block(Vector3(x + dx, height + 1, z - 1), "dark_planks", "dark_planks", "dark_planks")
		_add_block(Vector3(x + dx, height + 1, z + 2), "dark_planks", "dark_planks", "dark_planks")

func _banner(s: Dictionary) -> void:
	var pos: Array = s.get("pos", [0, 0, 0])
	var mi := MeshInstance3D.new()
	mi.mesh = WeaponBuilder.build_mesh("royal_banner" if String(s.get("color", "royal")) == "royal" else "cinder_banner")
	mi.material_override = MCMaterials.make(SkinLibrary.get_skin("chungie").get_texture(), false, false)
	mi.position = Vector3(pos[0], pos[1], pos[2])
	mi.scale = Vector3(1.6, 1.6, 1.6)
	add_child(mi)

func _camp(s: Dictionary) -> void:
	var pos: Array = s.get("pos", [0, 0, 0])
	var cx := int(pos[0])
	var cz := int(pos[2])
	for i in 5:
		var a := TAU * float(i) / 5.0
		var tx := cx + int(cos(a) * 5.0)
		var tz := cz + int(sin(a) * 5.0)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				_add_block(Vector3(tx + dx, 0, tz + dz), "wool_red", "wool_red", "wool_red")
		_add_block(Vector3(tx, 1, tz), "wool_red", "wool_red", "wool_red")
	_add_block(Vector3(cx, 0, cz), "magma", "magma", "magma")
	var fire := OmniLight3D.new()
	fire.position = Vector3(cx, 1.2, cz)
	fire.light_color = Color(1.0, 0.55, 0.2)
	fire.light_energy = 2.2
	fire.omni_range = 14.0
	add_child(fire)

func _trees(s: Dictionary) -> void:
	var area: Array = s.get("area", [0, 0, 10, 10])
	var count := int(s.get("count", 8))
	for i in count:
		var x := int(rng.randf_range(area[0], area[0] + area[2]))
		var z := int(rng.randf_range(area[1], area[1] + area[3]))
		if path.min_distance_to(Vector3(x, 0, z), 1.0) < 5.0:
			continue
		var h := rng.randi_range(4, 7)
		for y in h:
			_add_block(Vector3(x, y, z), "log_side", "log_side", "log_top")
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				for dy in range(h - 2, h + 2):
					if abs(dx) + abs(dz) + absi(dy - h) > 4:
						continue
					if dx == 0 and dz == 0 and dy < h:
						continue
					_add_block(Vector3(x + dx, dy, z + dz), "leaves", "leaves", "leaves")

func _rocks(s: Dictionary) -> void:
	var area: Array = s.get("area", [0, 0, 10, 10])
	var count := int(s.get("count", 10))
	for i in count:
		var x := int(rng.randf_range(area[0], area[0] + area[2]))
		var z := int(rng.randf_range(area[1], area[1] + area[3]))
		if path.min_distance_to(Vector3(x, 0, z), 1.0) < 3.5:
			continue
		var block := "cobble" if rng.randf() < 0.6 else "gravel"
		_add_block(Vector3(x, 1, z), block, block, block)
		if rng.randf() < 0.4:
			_add_block(Vector3(x + 1, 1, z), block, block, block)
		if rng.randf() < 0.3:
			_add_block(Vector3(x, 2, z), block, block, block)

func _stalls(s: Dictionary) -> void:
	var area: Array = s.get("area", [0, 0, 10, 10])
	var count := int(s.get("count", 10))
	var colors := ["wool_red", "wool_blue", "wool_gold", "wool_white"]
	for i in count:
		var x := int(rng.randf_range(area[0], area[0] + area[2]))
		var z := int(rng.randf_range(area[1], area[1] + area[3]))
		if path.min_distance_to(Vector3(x, 0, z), 1.0) < 4.0:
			continue
		var cloth: String = colors[rng.randi() % colors.size()]
		for dx in 3:
			for dz in 3:
				_add_block(Vector3(x + dx, 3, z + dz), cloth, cloth, cloth)
		for cx in [0, 2]:
			for cz in [0, 2]:
				for y in 3:
					_add_block(Vector3(x + cx, y, z + cz), "log_side", "log_side", "log_top")
		_add_block(Vector3(x + 1, 1, z + 1), "planks", "planks", "planks")

func _dummies(s: Dictionary) -> void:
	var pos: Array = s.get("pos", [0, 0, 0])
	var count := int(s.get("count", 3))
	for i in count:
		var x := int(pos[0]) + i * 2
		var z := int(pos[2])
		for y in 2:
			_add_block(Vector3(x, y, z), "log_side", "log_side", "log_top")
		_add_block(Vector3(x, 2, z), "wool_white", "wool_white", "wool_white")
		_add_block(Vector3(x - 1, 2, z), "planks", "planks", "planks")
		_add_block(Vector3(x + 1, 2, z), "planks", "planks", "planks")

# ================================================================================================
# Block mesh accumulation
# ================================================================================================

const FACE_DIRS := [
	Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)
]

var _occupied: Dictionary = {}

func _add_block(pos: Vector3, top_tex: String, side_tex: String, bottom_tex: String) -> void:
	var key := Vector3i(int(pos.x), int(pos.y), int(pos.z))
	if _occupied.has(key):
		return
	_occupied[key] = [top_tex, side_tex, bottom_tex]

## Like _add_block, but overwrites an existing cell (used to paint the road over the terrain).
func _set_block(pos: Vector3, top_tex: String, side_tex: String, bottom_tex: String) -> void:
	_occupied[Vector3i(int(pos.x), int(pos.y), int(pos.z))] = [top_tex, side_tex, bottom_tex]

func _flush_buffers() -> void:
	# Second pass: emit only faces that touch air.
	var by_tex: Dictionary = {}
	for key in _occupied.keys():
		var textures: Array = _occupied[key]
		var pos := Vector3(key.x, key.y, key.z)
		for f in 6:
			var dir: Vector3 = FACE_DIRS[f]
			var neighbour := Vector3i(key.x + int(dir.x), key.y + int(dir.y), key.z + int(dir.z))
			if _occupied.has(neighbour):
				continue
			var tex: String = textures[1]
			if f == 0:
				tex = textures[0]
			elif f == 1:
				tex = textures[2]
			if not by_tex.has(tex):
				by_tex[tex] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "i": PackedInt32Array()}
			_emit_face(by_tex[tex], pos, f)
	for tex in by_tex.keys():
		var buf: Dictionary = by_tex[tex]
		if (buf["v"] as PackedVector3Array).is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = buf["v"]
		arrays[Mesh.ARRAY_NORMAL] = buf["n"]
		arrays[Mesh.ARRAY_TEX_UV] = buf["uv"]
		arrays[Mesh.ARRAY_INDEX] = buf["i"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.name = "Blocks_%s" % String(tex)
		mi.mesh = mesh
		mi.material_override = _block_material(String(tex))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
		block_face_counts[String(tex)] = (buf["v"] as PackedVector3Array).size() / 4
	_occupied.clear()

func _emit_face(buf: Dictionary, pos: Vector3, face: int) -> void:
	var v: PackedVector3Array = buf["v"]
	var n: PackedVector3Array = buf["n"]
	var uv: PackedVector2Array = buf["uv"]
	var idx: PackedInt32Array = buf["i"]
	var base := v.size()
	var c := pos
	var corners: Array
	match face:
		0: corners = [c + Vector3(0, 1, 1), c + Vector3(1, 1, 1), c + Vector3(1, 1, 0), c + Vector3(0, 1, 0)]
		1: corners = [c + Vector3(0, 0, 0), c + Vector3(1, 0, 0), c + Vector3(1, 0, 1), c + Vector3(0, 0, 1)]
		2: corners = [c + Vector3(1, 1, 1), c + Vector3(1, 1, 0), c + Vector3(1, 0, 0), c + Vector3(1, 0, 1)]
		3: corners = [c + Vector3(0, 1, 0), c + Vector3(0, 1, 1), c + Vector3(0, 0, 1), c + Vector3(0, 0, 0)]
		4: corners = [c + Vector3(1, 1, 1), c + Vector3(0, 1, 1), c + Vector3(0, 0, 1), c + Vector3(1, 0, 1)]
		_: corners = [c + Vector3(0, 1, 0), c + Vector3(1, 1, 0), c + Vector3(1, 0, 0), c + Vector3(0, 0, 0)]
	# Blocks are centred on integer coordinates, so shift by half a block.
	for i in 4:
		v.push_back((corners[i] as Vector3) - Vector3(0.5, 0.5, 0.5))
		n.push_back(FACE_DIRS[face])
	uv.push_back(Vector2(0, 0)); uv.push_back(Vector2(1, 0)); uv.push_back(Vector2(1, 1)); uv.push_back(Vector2(0, 1))
	# Godot treats clockwise-as-seen-from-outside as front-facing. The corner lists above wind
	# counter-clockwise, so the triangles are emitted in reverse order.
	idx.push_back(base); idx.push_back(base + 2); idx.push_back(base + 1)
	idx.push_back(base); idx.push_back(base + 3); idx.push_back(base + 2)

static var _block_texture_cache: Dictionary = {}

## Decodes a block PNG into a mipmapped ImageTexture, cached process-wide.
static func load_block_texture(path: String) -> ImageTexture:
	if _block_texture_cache.has(path):
		return _block_texture_cache[path]
	var img := SkinParser.load_image(path)
	var tex: ImageTexture = null
	if img != null:
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
	_block_texture_cache[path] = tex
	return tex

func _block_material(tex: String) -> StandardMaterial3D:
	if _textures.has(tex):
		return _textures[tex]
	var mat := StandardMaterial3D.new()
	# Block PNGs are stored with the "keep" importer (raw files), so they are decoded directly
	# rather than through ResourceLoader — the same path the skin system uses.
	var t := load_block_texture("res://assets/textures/block_%s.png" % tex)
	if t != null:
		mat.albedo_texture = t
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	else:
		mat.albedo_color = Color(0.6, 0.6, 0.6)
	mat.roughness = 0.95
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if tex == "leaves":
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif tex == "water" or tex == "glass":
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	elif tex == "lava" or tex == "magma":
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.45, 0.15)
		mat.emission_energy_multiplier = 1.5
	_textures[tex] = mat
	return mat

# ================================================================================================
# Markers
# ================================================================================================

func _build_zone_markers() -> void:
	for z in zone_data():
		var pos_arr: Array = z.get("pos", [0, 0, 0])
		var pos := Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
		var elevation := float(z.get("elevation", 0.0))
		var radius := float(z.get("radius", 3.0))
		# Raised platform for elevated zones.
		if elevation > 0.1:
			var plat := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = radius * 0.85
			cyl.bottom_radius = radius * 0.95
			cyl.height = elevation
			plat.mesh = cyl
			plat.position = pos + Vector3(0, elevation * 0.5, 0)
			plat.material_override = _block_material("stone_bricks")
			add_child(plat)
		var marker := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = radius - 0.18
		torus.outer_radius = radius
		torus.rings = 32
		marker.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.85, 0.5, 0.35)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		marker.material_override = mat
		marker.position = pos + Vector3(0, elevation + 0.06, 0)
		marker.visible = false
		add_child(marker)
		build_zone_markers.append(marker)

func show_zone_markers(v: bool) -> void:
	for m in build_zone_markers:
		if is_instance_valid(m):
			m.visible = v

func set_zone_marker_state(index: int, available: bool) -> void:
	if index < 0 or index >= build_zone_markers.size():
		return
	var m: MeshInstance3D = build_zone_markers[index]
	var mat: StandardMaterial3D = m.material_override
	mat.albedo_color = Color(0.35, 0.85, 0.5, 0.35) if available else Color(0.85, 0.3, 0.3, 0.3)

func _build_base_marker() -> void:
	var bp: Array = map_def.get("base_position", [0, 0, 0])
	var base_y: float = 0.0 if flat_board else float(bp[1])
	var mi := MeshInstance3D.new()
	mi.mesh = PropBuilder.get_mesh("core")
	mi.material_override = MCMaterials.make(SkinLibrary.get_skin("chungie").get_texture(), false, false)
	mi.position = Vector3(bp[0], base_y, bp[2])
	add_child(mi)
	var light := OmniLight3D.new()
	light.position = Vector3(bp[0], base_y + 3.0, bp[2])
	light.light_color = Color(0.5, 0.7, 1.0)
	light.light_energy = 1.6
	light.omni_range = 18.0
	add_child(light)
