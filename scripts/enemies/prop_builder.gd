class_name PropBuilder
extends RefCounted
## Procedural blocky meshes for non-humanoid units and map props. Units are skin pixels (16 px = 1.0).
## All boxes use the shared armor/pattern texture so they share the character material.

static var _cache: Dictionary = {}

static func get_mesh(kind: String) -> ArrayMesh:
	if _cache.has(kind):
		return _cache[kind]
	var b := MCMeshBuilder.new()
	b.tex_size = Vector2(16, 16)
	match kind:
		"wall":
			_wall(b)
		"wither":
			_wither(b)
		"blimp":
			_blimp(b)
		"tnt_cart":
			_tnt_cart(b)
		"minecart":
			_minecart(b)
		"horse":
			_horse(b)
		"core":
			_core(b)
		_:
			b.add_color_box(Vector3(-4, 0, -4), Vector3(8, 8, 8), Color.MAGENTA, MCGeometry.Part.EXTRA, Vector3.ZERO)
	var mesh := b.commit()
	_cache[kind] = mesh
	return mesh

static func _box(b: MCMeshBuilder, bmin: Vector3, size: Vector3, c: Color, glint: float = 0.0) -> void:
	b.add_color_box(bmin, size, c, MCGeometry.Part.EXTRA, Vector3.ZERO, glint)

static func _wall(b: MCMeshBuilder) -> void:
	var stone := Color(0.44, 0.43, 0.45)
	for row in 3:
		var y := row * 8.0
		var offset := 0.0 if row % 2 == 0 else 4.0
		for col in 3:
			var x := -12.0 + col * 8.0 + offset
			_box(b, Vector3(x, y, -4), Vector3(7.5, 7.5, 8), stone.lightened(0.05 * ((row + col) % 3)))

static func _wither(b: MCMeshBuilder) -> void:
	var bone := Color(0.29, 0.29, 0.27)
	var dark := Color(0.13, 0.13, 0.13)
	# Central skull + two side skulls
	_box(b, Vector3(-4, 22, -4), Vector3(8, 8, 8), bone)
	_box(b, Vector3(-11, 20, -3), Vector3(6, 6, 6), bone)
	_box(b, Vector3(5, 20, -3), Vector3(6, 6, 6), bone)
	for eye_x in [-2.5, 0.5]:
		_box(b, Vector3(eye_x, 26, -4.6), Vector3(2, 2, 1), Color(0.35, 0.55, 0.35), 1.0)
	_box(b, Vector3(-9.5, 23, -3.6), Vector3(1.5, 1.5, 1), Color(0.35, 0.55, 0.35), 1.0)
	_box(b, Vector3(7.5, 23, -3.6), Vector3(1.5, 1.5, 1), Color(0.35, 0.55, 0.35), 1.0)
	# Spine
	_box(b, Vector3(-1.5, 8, -1.5), Vector3(3, 14, 3), dark)
	for i in 3:
		_box(b, Vector3(-7.0, 18.0 - i * 4.0, -1.0), Vector3(14, 2, 2), dark)
	_box(b, Vector3(-1.5, 2, -1.5), Vector3(3, 6, 3), dark)

static func _blimp(b: MCMeshBuilder) -> void:
	var hull := Color(0.55, 0.16, 0.12)
	var trim := Color(0.2, 0.2, 0.22)
	var wood := Color(0.42, 0.29, 0.16)
	# Envelope: tapered stack of boxes
	var lengths := [26.0, 44.0, 52.0, 44.0, 26.0]
	var heights := [10.0, 18.0, 22.0, 18.0, 10.0]
	var z := -60.0
	for i in lengths.size():
		var l: float = lengths[i]
		var h: float = heights[i]
		_box(b, Vector3(-h * 0.5, 40.0 - h * 0.5, z), Vector3(h, h, l), hull.lightened(0.04 * i))
		z += l
	# Stripe
	_box(b, Vector3(-11.5, 38, -58), Vector3(23, 4, 116), Color(0.85, 0.75, 0.35))
	# Gondola
	_box(b, Vector3(-8, 16, -18), Vector3(16, 10, 36), wood)
	_box(b, Vector3(-8, 26, -18), Vector3(16, 3, 36), trim)
	for zx in [-16.0, 12.0]:
		_box(b, Vector3(-1.5, 26, zx), Vector3(3, 6, 3), trim)
	# Tail fins
	_box(b, Vector3(-1.5, 40, 56), Vector3(3, 22, 12), trim)
	_box(b, Vector3(-14, 39, 56), Vector3(28, 3, 12), trim)
	# Redstone lamps
	for lz in [-40.0, 0.0, 40.0]:
		_box(b, Vector3(-2, 16, lz), Vector3(4, 2, 4), Color(1.0, 0.45, 0.2), 1.0)

static func _tnt_cart(b: MCMeshBuilder) -> void:
	var cart := Color(0.35, 0.35, 0.38)
	_box(b, Vector3(-6, 1, -6), Vector3(12, 2, 12), cart)
	for sx in [-6.0, 4.0]:
		_box(b, Vector3(sx, 3, -6), Vector3(2, 6, 12), cart)
	for sz in [-6.0, 4.0]:
		_box(b, Vector3(-6, 3, sz), Vector3(12, 6, 2), cart)
	_box(b, Vector3(-4, 3, -4), Vector3(8, 8, 8), Color(0.82, 0.16, 0.11))
	_box(b, Vector3(-4.2, 6, -4.2), Vector3(8.4, 2, 8.4), Color(0.94, 0.94, 0.9))
	_box(b, Vector3(-0.5, 11, -0.5), Vector3(1, 3, 1), Color(0.9, 0.9, 0.85))
	for wx in [-6.5, 5.5]:
		_box(b, Vector3(wx, 0, -3), Vector3(1, 3, 3), Color(0.2, 0.2, 0.2))
		_box(b, Vector3(wx, 0, 1), Vector3(1, 3, 3), Color(0.2, 0.2, 0.2))

static func _minecart(b: MCMeshBuilder) -> void:
	var cart := Color(0.4, 0.4, 0.44)
	_box(b, Vector3(-6, 1, -6), Vector3(12, 2, 12), cart)
	for sx in [-6.0, 4.0]:
		_box(b, Vector3(sx, 3, -6), Vector3(2, 5, 12), cart)
	for sz in [-6.0, 4.0]:
		_box(b, Vector3(-6, 3, sz), Vector3(12, 5, 2), cart)
	for wx in [-6.5, 5.5]:
		_box(b, Vector3(wx, 0, -3), Vector3(1, 3, 3), Color(0.2, 0.2, 0.2))
		_box(b, Vector3(wx, 0, 1), Vector3(1, 3, 3), Color(0.2, 0.2, 0.2))

static func _horse(b: MCMeshBuilder) -> void:
	var coat := Color(0.42, 0.28, 0.18)
	var mane := Color(0.2, 0.14, 0.1)
	_box(b, Vector3(-4, 12, -10), Vector3(8, 9, 20), coat)         # barrel
	_box(b, Vector3(-3, 18, -16), Vector3(6, 6, 8), coat)          # neck
	_box(b, Vector3(-3, 20, -22), Vector3(6, 5, 8), coat)          # head
	_box(b, Vector3(-3, 25, -17), Vector3(6, 2, 8), mane)          # mane
	for ex in [-3.0, 1.0]:
		_box(b, Vector3(ex, 25, -20), Vector3(2, 3, 2), coat)      # ears
	for lx in [-4.0, 2.0]:
		for lz in [-8.0, 6.0]:
			_box(b, Vector3(lx, 0, lz), Vector3(2.5, 12, 2.5), coat)
	_box(b, Vector3(-1, 16, 10), Vector3(2, 8, 2), mane)           # tail

static func _core(b: MCMeshBuilder) -> void:
	# The base / objective: a banner-topped keep block used as the "core" marker.
	_box(b, Vector3(-12, 0, -12), Vector3(24, 4, 24), Color(0.4, 0.4, 0.43))
	_box(b, Vector3(-10, 4, -10), Vector3(20, 16, 20), Color(0.55, 0.53, 0.5))
	_box(b, Vector3(-11, 20, -11), Vector3(22, 3, 22), Color(0.35, 0.35, 0.38))
	for cx in [-11.0, 8.0]:
		for cz in [-11.0, 8.0]:
			_box(b, Vector3(cx, 23, cz), Vector3(3, 5, 3), Color(0.35, 0.35, 0.38))
	_box(b, Vector3(-0.8, 23, -0.8), Vector3(1.6, 22, 1.6), Color(0.4, 0.28, 0.16))
	_box(b, Vector3(-8, 30, -0.4), Vector3(8, 12, 0.8), Color(0.25, 0.42, 0.85))
