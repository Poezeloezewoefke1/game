class_name SkinParser
extends RefCounted
## Loads and normalizes Minecraft-compatible skin PNGs (64x64, legacy 64x32, and HD multiples).
##
## Layout reference (64x64, pixel coordinates, y down):
##   head (0,0) hat (32,0) | body (16,16) jacket (16,32) | right arm (40,16) sleeve (40,32)
##   right leg (0,16) pants (0,32) | left leg (16,48) pants (0,48) | left arm (32,48) sleeve (48,48)
## Slim skins use 3-pixel-wide arms in the same regions.

# Regions that must be fully transparent for a skin to be considered slim (x, y, w, h) in 64x64 space.
const SLIM_PROBES := [
	Rect2i(50, 16, 2, 4), Rect2i(54, 20, 2, 12),
	Rect2i(42, 48, 2, 4), Rect2i(46, 52, 2, 12),
]

static func load_from_path(path: String, id: String = "", model_override: String = "") -> SkinData:
	var img := load_image(path)
	if img == null:
		return null
	var skin_id := id if id != "" else path.get_file().get_basename()
	return from_image(img, skin_id, path, model_override)

static func load_image(path: String) -> Image:
	var img: Image = null
	if path.begins_with("res://") or path.begins_with("user://"):
		if not FileAccess.file_exists(path):
			return null
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.is_empty():
			return null
		img = Image.new()
		if img.load_png_from_buffer(bytes) != OK:
			push_warning("[SkinParser] could not decode PNG: %s" % path)
			return null
	else:
		if not FileAccess.file_exists(path):
			return null
		img = Image.load_from_file(path)
	return img

static func from_image(src: Image, id: String, source: String = "", model_override: String = "") -> SkinData:
	if src == null:
		return null
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var data := SkinData.new()
	data.id = id
	data.source_path = source
	var w := img.get_width()
	var h := img.get_height()
	if w < 64 or w % 64 != 0:
		push_warning("[SkinParser] unusual skin width %d for %s; expected a multiple of 64" % [w, id])
	if h * 2 == w:
		img = convert_legacy(img)
		data.legacy = true
	elif h != w:
		push_warning("[SkinParser] unusual skin size %dx%d for %s" % [w, h, id])
	data.image = img
	data.scale = max(1, int(img.get_width() / 64))
	match model_override:
		"slim":
			data.slim = true
		"classic":
			data.slim = false
		_:
			data.slim = detect_slim(img)
	return data

## Expands a 64x32 legacy skin onto a 64x64 canvas. Lower half stays transparent;
## MCGeometry mirrors the right limbs for the left ones when SkinData.legacy is true.
static func convert_legacy(img: Image) -> Image:
	var w := img.get_width()
	var out := Image.create(w, w, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	out.blit_rect(img, Rect2i(0, 0, w, img.get_height()), Vector2i.ZERO)
	return out

## Heuristic used by most skin viewers: slim skins leave the unused 1px arm columns fully transparent.
static func detect_slim(img: Image) -> bool:
	if img.get_height() != img.get_width():
		return false
	var s := max(1, int(img.get_width() / 64))
	for probe in SLIM_PROBES:
		for y in range(probe.position.y * s, (probe.position.y + probe.size.y) * s):
			for x in range(probe.position.x * s, (probe.position.x + probe.size.x) * s):
				if img.get_pixel(x, y).a > 0.0:
					return false
	return true

## Counts opaque pixels in a 64x64-space rectangle (scaled for HD). Used by tests and outer-layer checks.
static func opaque_count(img: Image, rect: Rect2i) -> int:
	var s := max(1, int(img.get_width() / 64))
	var n := 0
	for y in range(rect.position.y * s, (rect.position.y + rect.size.y) * s):
		for x in range(rect.position.x * s, (rect.position.x + rect.size.x) * s):
			if img.get_pixel(x, y).a > 0.5:
				n += 1
	return n

## Generates a readable placeholder skin so characters without a supplied texture still render distinctly.
## The result is clearly a placeholder (flat colours, simple face) and is never presented as the real skin.
static func generate_placeholder(id: String, primary: Color, secondary: Color, accent: Color, slim: bool = false) -> SkinData:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var skin_tone := Color(0.85, 0.66, 0.5)
	# Head (all faces) skin tone, hair band on top faces.
	_fill(img, Rect2i(0, 0, 32, 16), skin_tone)
	_fill(img, Rect2i(8, 0, 16, 8), secondary)      # top + bottom
	_fill(img, Rect2i(0, 8, 32, 2), secondary)      # hairline
	# Face: eyes + mouth on the front face (8..16, 8..16)
	_fill(img, Rect2i(9, 11, 2, 2), Color.WHITE)
	_fill(img, Rect2i(13, 11, 2, 2), Color.WHITE)
	_fill(img, Rect2i(10, 12, 1, 1), Color(0.1, 0.1, 0.2))
	_fill(img, Rect2i(14, 12, 1, 1), Color(0.1, 0.1, 0.2))
	_fill(img, Rect2i(11, 14, 2, 1), Color(0.5, 0.25, 0.2))
	# Body
	_fill(img, Rect2i(16, 16, 24, 16), primary)
	_fill(img, Rect2i(20, 20, 8, 4), accent)        # chest emblem stripe
	# Arms (right at 40,16 ; left at 32,48)
	_fill(img, Rect2i(40, 16, 16, 16), primary)
	_fill(img, Rect2i(40, 26, 16, 6), skin_tone)    # hands
	_fill(img, Rect2i(32, 48, 16, 16), primary)
	_fill(img, Rect2i(32, 58, 16, 6), skin_tone)
	# Legs (right at 0,16 ; left at 16,48)
	_fill(img, Rect2i(0, 16, 16, 16), secondary)
	_fill(img, Rect2i(0, 28, 16, 4), Color(0.2, 0.15, 0.1))   # boots
	_fill(img, Rect2i(16, 48, 16, 16), secondary)
	_fill(img, Rect2i(16, 60, 16, 4), Color(0.2, 0.15, 0.1))
	if slim:
		# Clear the unused columns so detect_slim() agrees.
		_fill(img, Rect2i(50, 16, 2, 4), Color(0, 0, 0, 0))
		_fill(img, Rect2i(54, 20, 2, 12), Color(0, 0, 0, 0))
		_fill(img, Rect2i(42, 48, 2, 4), Color(0, 0, 0, 0))
		_fill(img, Rect2i(46, 52, 2, 12), Color(0, 0, 0, 0))
	var data := from_image(img, id, "", "slim" if slim else "classic")
	data.placeholder = true
	return data

static func _fill(img: Image, r: Rect2i, c: Color) -> void:
	img.fill_rect(r, c)
