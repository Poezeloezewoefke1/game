extends SceneTree
## Generates the game's PBR texture set and writes it to assets/textures/.
##
##   usage: <godot> --headless --path . --script tools/generate_textures.gd
##
## WHY GENERATED RATHER THAN DOWNLOADED. Every host that serves cleanly-licensed
## texture and photographic material - NASA, Wikimedia, Poly Haven, Kenney - is
## unreachable from this machine; the only reachable sources carry licences that
## do not permit redistribution. Rather than commit assets whose provenance
## cannot be established, the whole set is synthesised here. Everything written
## by this script is original output of this repository's own code, so it can be
## shipped, modified and relicensed without asking anyone.
##
## Each material gets an albedo, a tangent-space normal, a roughness map and,
## where it means anything, a metallic/AO map. All of them TILE: the base noise
## is generated seamless and every derived map is computed with wrapping
## neighbour lookups, so a 140 m ground slab does not show a grid.

const SIZE := 512
const OUT_DIR := "res://assets/textures"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	print("generating into %s at %dx%d" % [OUT_DIR, SIZE, SIZE])

	await _rock()
	await _sand()
	await _hull()
	await _moss()
	await _detail()

	print("TEXTURES done")
	quit()


# --------------------------------------------------------------------------
# Noise
# --------------------------------------------------------------------------

## A seamless noise field as a float grid. `NoiseTexture2D` does the tiling in
## C++, which matters: the equivalent in GDScript takes minutes per layer.
func _field(seed_value: int, frequency: float, octaves: int,
		noise_type: int = FastNoiseLite.TYPE_SIMPLEX,
		fractal_type: int = FastNoiseLite.FRACTAL_FBM,
		gain: float = 0.5) -> PackedFloat32Array:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = noise_type
	noise.frequency = frequency
	noise.fractal_type = fractal_type
	noise.fractal_octaves = octaves
	noise.fractal_gain = gain

	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.width = SIZE
	texture.height = SIZE
	texture.seamless = true
	texture.as_normal_map = false
	texture.generate_mipmaps = false

	# Generation is threaded; the image is null until it finishes.
	var image: Image = texture.get_image()
	var waited := 0.0
	while image == null and waited < 60.0:
		await process_frame
		waited += 0.016
		image = texture.get_image()
	if image == null:
		push_error("noise generation timed out")
		return PackedFloat32Array()

	var out := PackedFloat32Array()
	out.resize(SIZE * SIZE)
	for y in SIZE:
		for x in SIZE:
			out[y * SIZE + x] = image.get_pixel(x, y).r
	return out


func _at(field: PackedFloat32Array, x: int, y: int) -> float:
	return field[(posmod(y, SIZE)) * SIZE + posmod(x, SIZE)]


# --------------------------------------------------------------------------
# Derived maps
# --------------------------------------------------------------------------

## Tangent-space normal map from a height field, by central differences with
## WRAPPING lookups - the wrap is what keeps the seams invisible.
func _normal_map(height: PackedFloat32Array, strength: float) -> Image:
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			var dx := (_at(height, x + 1, y) - _at(height, x - 1, y)) * strength
			var dy := (_at(height, x, y + 1) - _at(height, x, y - 1)) * strength
			var n := Vector3(-dx, -dy, 1.0).normalized()
			image.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	return image


func _save(image: Image, name: String) -> void:
	var path := "%s/%s.png" % [OUT_DIR, name]
	if image.save_png(ProjectSettings.globalize_path(path)) == OK:
		print("  wrote %s" % path)
	else:
		push_error("could not write %s" % path)


func _grey(values: PackedFloat32Array) -> Image:
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			var v: float = clampf(values[y * SIZE + x], 0.0, 1.0)
			image.set_pixel(x, y, Color(v, v, v))
	return image


# --------------------------------------------------------------------------
# Materials
# --------------------------------------------------------------------------

## Weathered stone. Two scales of lump plus a fine grain, and a sparse crack
## network from ridged noise - the cracks are what stop it reading as porridge.
func _rock() -> void:
	var coarse := await _field(101, 0.006, 5)
	var medium := await _field(102, 0.02, 4)
	var grain := await _field(103, 0.08, 3)
	var cracks := await _field(104, 0.011, 3, FastNoiseLite.TYPE_SIMPLEX,
		FastNoiseLite.FRACTAL_RIDGED)

	var height := PackedFloat32Array()
	height.resize(SIZE * SIZE)
	var albedo := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var rough := PackedFloat32Array()
	rough.resize(SIZE * SIZE)

	var dark := Color(0.30, 0.27, 0.24)
	var mid := Color(0.48, 0.44, 0.39)
	var pale := Color(0.62, 0.58, 0.52)

	for y in SIZE:
		for x in SIZE:
			var i := y * SIZE + x
			var h: float = coarse[i] * 0.55 + medium[i] * 0.32 + grain[i] * 0.13
			# Cracks cut into the height, and darken the albedo, because a
			# crevice is both lower and in shadow.
			var crack: float = smoothstep(0.72, 0.96, cracks[i])
			h -= crack * 0.35
			height[i] = h

			var c := dark.lerp(mid, clampf(coarse[i] * 1.5, 0.0, 1.0))
			c = c.lerp(pale, clampf((medium[i] - 0.45) * 2.2, 0.0, 1.0))
			c = c.lerp(Color(0.18, 0.16, 0.15), crack * 0.8)
			albedo.set_pixel(x, y, c)
			# Exposed high faces are polished by weather; sheltered low ground
			# is rougher.
			rough[i] = clampf(0.94 - h * 0.28 + crack * 0.05, 0.4, 1.0)

	_save(albedo, "rock_albedo")
	_save(_normal_map(height, 5.5), "rock_normal")
	_save(_grey(rough), "rock_roughness")


## Fine sand: dune ripples plus grain. The ripples are directional, which is
## what makes it read as wind-blown rather than as generic bumpiness.
func _sand() -> void:
	var dunes := await _field(201, 0.010, 3)
	var grain := await _field(202, 0.16, 2)
	var patches := await _field(203, 0.005, 3)

	var height := PackedFloat32Array()
	height.resize(SIZE * SIZE)
	var albedo := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var rough := PackedFloat32Array()
	rough.resize(SIZE * SIZE)

	var light := Color(0.78, 0.70, 0.54)
	var deep := Color(0.56, 0.48, 0.36)

	for y in SIZE:
		for x in SIZE:
			var i := y * SIZE + x
			# A stretched sine ripple, phase-shifted by noise so the crests
			# wander instead of running dead straight.
			var ripple: float = sin((float(x) * 0.09 + float(y) * 0.028)
				+ dunes[i] * 9.0) * 0.5 + 0.5
			var h: float = ripple * 0.5 + dunes[i] * 0.35 + grain[i] * 0.15
			height[i] = h
			var c := deep.lerp(light, clampf(h * 1.25, 0.0, 1.0))
			c = c.lerp(Color(0.62, 0.55, 0.44), clampf(patches[i] * 0.6, 0.0, 1.0))
			albedo.set_pixel(x, y, c)
			rough[i] = clampf(0.86 + grain[i] * 0.1, 0.6, 1.0)

	_save(albedo, "sand_albedo")
	_save(_normal_map(height, 2.6), "sand_normal")
	_save(_grey(rough), "sand_roughness")


## Ship hull: a panel grid with recessed seams, rivets, scratches and rust
## creeping out of the joins. The seams are the reason a wall reads as built.
func _hull() -> void:
	var wear := await _field(301, 0.013, 4)
	var scratch := await _field(302, 0.05, 3, FastNoiseLite.TYPE_SIMPLEX,
		FastNoiseLite.FRACTAL_RIDGED)
	var rust := await _field(303, 0.02, 4)
	var grime := await _field(304, 0.008, 3)

	var height := PackedFloat32Array()
	height.resize(SIZE * SIZE)
	var albedo := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var rough := PackedFloat32Array()
	rough.resize(SIZE * SIZE)
	var metal := PackedFloat32Array()
	metal.resize(SIZE * SIZE)

	var base := Color(0.42, 0.45, 0.51)
	var seam_colour := Color(0.20, 0.22, 0.27)
	var rust_colour := Color(0.44, 0.24, 0.13)

	# Panels of two sizes, offset every other row, so the grid is not a
	# chessboard.
	for y in SIZE:
		for x in SIZE:
			var i := y * SIZE + x
			var row := int(floor(float(y) / 128.0))
			var offset := 64 if row % 2 == 1 else 0
			var px := posmod(x + offset, 128)
			var py := posmod(y, 128)
			var seam: float = 0.0
			seam = maxf(seam, smoothstep(4.0, 0.0, float(px)))
			seam = maxf(seam, smoothstep(4.0, 0.0, float(127 - px)))
			seam = maxf(seam, smoothstep(4.0, 0.0, float(py)))
			seam = maxf(seam, smoothstep(4.0, 0.0, float(127 - py)))

			# Rivets around each panel edge.
			var rivet: float = 0.0
			var rx: int = px % 32
			var ry: int = py % 32
			if px < 12 or px > 115 or py < 12 or py > 115:
				var d := Vector2(float(rx) - 16.0, float(ry) - 16.0).length()
				rivet = smoothstep(3.2, 1.4, d)

			var h: float = 0.62 - seam * 0.45 + rivet * 0.3 + wear[i] * 0.08
			h -= smoothstep(0.65, 0.95, scratch[i]) * 0.06
			height[i] = h

			var rust_amount: float = clampf(
				smoothstep(0.55, 0.85, rust[i]) * (0.35 + seam * 0.9), 0.0, 1.0)
			var c := base.lerp(Color(0.55, 0.58, 0.63), wear[i] * 0.5)
			c = c.lerp(seam_colour, seam * 0.85)
			c = c.lerp(Color(0.70, 0.73, 0.78), smoothstep(0.72, 0.95, scratch[i]) * 0.5)
			c = c.lerp(rust_colour, rust_amount)
			c = c.lerp(Color(0.24, 0.25, 0.28), clampf(grime[i] - 0.5, 0.0, 1.0) * 0.5)
			albedo.set_pixel(x, y, c)

			rough[i] = clampf(0.34 + rust_amount * 0.5 + seam * 0.2
				- smoothstep(0.72, 0.95, scratch[i]) * 0.18, 0.1, 1.0)
			# Rust is not metal any more - that is the whole visual point of it.
			metal[i] = clampf(0.85 - rust_amount * 0.8 - seam * 0.25, 0.0, 1.0)

	_save(albedo, "hull_albedo")
	_save(_normal_map(height, 6.0), "hull_normal")
	_save(_grey(rough), "hull_roughness")
	_save(_grey(metal), "hull_metallic")


## Ground cover for the grove: clumped leaf litter over damp earth.
func _moss() -> void:
	var clumps := await _field(401, 0.03, 4)
	var leaves := await _field(402, 0.12, 3)
	var damp := await _field(403, 0.007, 3)

	var height := PackedFloat32Array()
	height.resize(SIZE * SIZE)
	var albedo := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var rough := PackedFloat32Array()
	rough.resize(SIZE * SIZE)

	var earth := Color(0.20, 0.16, 0.11)
	var green := Color(0.20, 0.38, 0.18)
	var bright := Color(0.34, 0.52, 0.24)

	for y in SIZE:
		for x in SIZE:
			var i := y * SIZE + x
			var cover: float = smoothstep(0.42, 0.72, clumps[i])
			var h: float = cover * 0.6 + leaves[i] * 0.4
			height[i] = h
			var c := earth.lerp(green, cover)
			c = c.lerp(bright, clampf((leaves[i] - 0.5) * 1.6, 0.0, 1.0) * cover)
			albedo.set_pixel(x, y, c)
			# Wet earth is glossy; leaf litter is not.
			rough[i] = clampf(0.92 - (1.0 - cover) * damp[i] * 0.55, 0.35, 1.0)

	_save(albedo, "moss_albedo")
	_save(_normal_map(height, 4.0), "moss_normal")
	_save(_grey(rough), "moss_roughness")


## A high-frequency detail normal, tiled far more often than the base maps.
## This is what keeps a surface from going smooth and plastic when the player
## walks right up to it, which is where a single 512px base map falls apart.
func _detail() -> void:
	var fine := await _field(501, 0.09, 4)
	var finer := await _field(502, 0.22, 3)
	var height := PackedFloat32Array()
	height.resize(SIZE * SIZE)
	for i in SIZE * SIZE:
		height[i] = fine[i] * 0.6 + finer[i] * 0.4
	_save(_normal_map(height, 3.2), "detail_normal")
